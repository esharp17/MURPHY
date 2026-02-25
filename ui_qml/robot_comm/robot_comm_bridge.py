# ui_qml/robot_comm/robot_comm_bridge.py
import json
import os
import threading
import time
import traceback
import socket
import struct
import binascii
from dataclasses import dataclass, asdict

from PySide6.QtCore import QObject, Signal, Slot, Property

from robot_ui.config import SYSTEM_LOG_JSONL
from robot_ui.storage_log import append_log as _sys_log


print("LOADED RobotCommBridge FROM:", __file__)
print("USING ROBOT_COMM_BRIDGE FROM:", __file__, flush=True)


@dataclass
class RobotCfg:
    ip: str = "192.168.2.1"
    port: int = 44818
    slot: int = 3
    in_words: int = 16
    out_words: int = 16


class RobotCommBridge(QObject):
    # signals used by QML
    ioUpdated = Signal(int)
    stateChanged = Signal(int)
    faulted = Signal(int, str)
    configChanged = Signal(int)
    logUpdated = Signal(int)
    inWordsChanged = Signal()
    _inWordsRx = Signal(object)   # internal handoff to Qt thread

    # internal
    logLine = Signal(int, str)

    def __init__(self, parent=None):
        super().__init__(parent)

        # ---- RX demux: T->O conn_id -> robot_index ----
        self._rx_map = {}
        self._rx_map_lock = threading.Lock()

        # ---- shared UDP RX listener (ONE socket on 2222) ----
        self._udp_rx_sock = None
        self._udp_rx_thread = None

        # per robot conn ids (for TX + demux)
        self._o2t_conn_id = [0] * 4
        self._t2o_conn_id = [0] * 4

        # per robot timestamps for watchdog / lastRxMs
        self._last_udp_ts = [0.0] * 4

        self._cfg_path = os.path.join(os.getcwd(), "robot_comm_config.json")
        print(f"[BRIDGE] Config file: {self._cfg_path}", flush=True)

        self._cfgs = [RobotCfg() for _ in range(4)]

        self._inWordsRx.connect(self._on_in_words_rx)

        # 0=disc 1=connecting 2=cyclic 3=fault
        self._state = [0] * 4
        self._fault = [""] * 4
        self._last_rx_ms = [0] * 4

        # backing buffers; getters slice to configured size
        self._inputs = [[0] * 256 for _ in range(4)]
        self._outputs = [[0] * 256 for _ in range(4)]
        self._io_lock = threading.Lock()
        self._in_words = []

        self._udp_rx = [0] * 4
        self._udp_tx = [0] * 4

        self._logs = [""] * 4
        self._log_lock = threading.Lock()

        self._threads = [None] * 4
        self._stop_events = [threading.Event() for _ in range(4)]

        # per-robot outgoing seq
        self._outgoing_seq = [1] * 4

        self.logLine.connect(self._on_log_line)

        self._load_config()
        for idx in range(4):
            c = self._cfgs[idx]
            print(f"[BRIDGE] Robot {idx}: ip={c.ip} port={c.port} slot={c.slot} in={c.in_words} out={c.out_words}", flush=True)

    def get_in_words(self):
        return self._in_words

    in_words = Property("QVariantList", get_in_words, notify=inWordsChanged)

    # -------------------------
    # logging / config helpers
    # -------------------------
    def _clamp_robot(self, i):
        try:
            i = int(i)
        except Exception:
            i = 0
        return max(0, min(3, i))

    @Slot(object)
    def _on_in_words_rx(self, words):
        self._in_words = list(words)
        self.inWordsChanged.emit()

    @Slot(int, str)
    def _on_log_line(self, i, text):
        i = self._clamp_robot(i)
        self._append_log(i, text)

    def _append_log(self, i, text):
        line = f"{time.strftime('%H:%M:%S')}  {text}\n"
        with self._log_lock:
            self._logs[i] += line
            if len(self._logs[i]) > 60000:
                self._logs[i] = self._logs[i][-60000:]
        self.logUpdated.emit(i)

    def _save_config(self):
        data = {"robots": [asdict(c) for c in self._cfgs]}
        with open(self._cfg_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    def _load_config(self):
        if not os.path.exists(self._cfg_path):
            self._save_config()
            return
        try:
            with open(self._cfg_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            robots = data.get("robots", [])
            for idx in range(min(4, len(robots))):
                r = robots[idx]
                self._cfgs[idx] = RobotCfg(
                    ip=str(r.get("ip", self._cfgs[idx].ip)),
                    port=int(r.get("port", self._cfgs[idx].port)),
                    slot=int(r.get("slot", self._cfgs[idx].slot)),
                    in_words=int(r.get("in_words", self._cfgs[idx].in_words)),
                    out_words=int(r.get("out_words", self._cfgs[idx].out_words)),
                )
        except Exception as e:
            self._append_log(0, f"Config load failed: {e}")

    # -------------------------
    # Shared UDP RX listener (ONE socket, demux by conn_id)
    # -------------------------
    def _ensure_udp_rx_listener(self):
        if self._udp_rx_sock:
            return

        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.settimeout(0.5)
        s.bind(("", 2222))
        self._udp_rx_sock = s
        print("[BRIDGE] UDP listener bound *:2222", flush=True)

        def rx_loop():
            rx_count = 0
            while True:
                try:
                    data, addr = s.recvfrom(8192)
                except socket.timeout:
                    continue
                except Exception:
                    break

                if len(data) < 18:
                    continue

                # T->O conn_id at offset 6 (after item_count(2) + item_type(2) + item_len(2))
                t2o = struct.unpack_from("<I", data, 6)[0]

                with self._rx_map_lock:
                    i = self._rx_map.get(t2o)

                if i is None:
                    continue

                self._last_udp_ts[i] = time.time()
                self._udp_rx[i] += 1
                self._last_rx_ms[i] = 0
                rx_count += 1

                self._process_io_data(i, data)
                try:
                    self.ioUpdated.emit(i)
                except RuntimeError:
                    break

                if rx_count <= 3 or (rx_count % 500) == 0:
                    print(f"[BRIDGE] UDP RX #{rx_count} from {addr} robot={i} len={len(data)}", flush=True)

        self._udp_rx_thread = threading.Thread(target=rx_loop, daemon=True)
        self._udp_rx_thread.start()

    # -------------------------
    # QML API getters
    # -------------------------
    @Slot(int, result=int)
    def getState(self, i):
        i = self._clamp_robot(i)
        return int(self._state[i])

    @Slot(int, result="QVariantList")
    def getInputs(self, i):
        i = self._clamp_robot(i)
        n = max(1, int(self._cfgs[i].in_words))
        with self._io_lock:
            return [int(x) for x in self._inputs[i][:n]]

    @Slot(int, result="QVariantList")
    def getOutputs(self, i):
        i = self._clamp_robot(i)
        n = max(1, int(self._cfgs[i].out_words))
        with self._io_lock:
            return [int(x) for x in self._outputs[i][:n]]

    @Slot(int, result=int)
    def getLastRxMs(self, i):
        i = self._clamp_robot(i)
        return int(self._last_rx_ms[i])

    @Slot(int, result=str)
    def getFault(self, i):
        i = self._clamp_robot(i)
        return str(self._fault[i])

    @Slot(int, result="QVariantList")
    def getUdpCounts(self, i):
        i = self._clamp_robot(i)
        return [int(self._udp_rx[i]), int(self._udp_tx[i])]

    @Slot(int, result=str)
    def getDebugLog(self, i):
        i = self._clamp_robot(i)
        with self._log_lock:
            return self._logs[i]

    @Slot(int)
    def clearDebugLog(self, i):
        i = self._clamp_robot(i)
        with self._log_lock:
            self._logs[i] = ""
        self.logUpdated.emit(i)

    @Slot(int, result="QVariantMap")
    def getConfig(self, i):
        i = self._clamp_robot(i)
        c = self._cfgs[i]
        return {
            "ip": c.ip,
            "port": int(c.port),
            "slot": int(c.slot),
            "in_words": int(c.in_words),
            "out_words": int(c.out_words),
        }

    # -------------------------
    # QML API setters/actions
    # -------------------------
    @Slot(int, str, int, int, int, int)
    def setConfig(self, i, ip, port, slot, in_words, out_words):
        i = self._clamp_robot(i)
        c = self._cfgs[i]
        c.ip = str(ip)
        try:
            c.port = int(port)
        except Exception:
            c.port = 44818
        try:
            c.slot = int(slot)
        except Exception:
            c.slot = 1
        try:
            c.in_words = int(in_words)
        except Exception:
            c.in_words = 4
        try:
            c.out_words = int(out_words)
        except Exception:
            c.out_words = 4

        self._cfgs[i] = c
        self._save_config()
        self._append_log(i, f"Saved config: {c}")
        _sys_log(SYSTEM_LOG_JSONL, "ROBOT_CONFIG_SAVE", None, {"robot": i, "ip": c.ip, "port": c.port})
        self.configChanged.emit(i)

    @Slot(int)
    def connectRobot(self, i):
        i = self._clamp_robot(i)
        c = self._cfgs[i]

        print(f"[BRIDGE] connectRobot({i}) ip={c.ip} port={c.port} slot={c.slot}", flush=True)

        self.logLine.emit(
            i,
            f"CONNECT requested: ip={c.ip} port={c.port} slot={c.slot} in={c.in_words} out={c.out_words}",
        )
        _sys_log(SYSTEM_LOG_JSONL, "ROBOT_CONNECT", None, {"robot": i, "ip": c.ip, "port": c.port})

        t = self._threads[i]
        if t and t.is_alive():
            return

        # reset state
        self._stop_events[i].clear()
        self._udp_rx[i] = 0
        self._udp_tx[i] = 0
        self._last_rx_ms[i] = 0
        self._fault[i] = ""
        self._state[i] = 1
        self.stateChanged.emit(i)

        def worker():
            tcp = None
            tx_sock = None

            try:
                self.logLine.emit(i, "Worker started")

                # TCP connect (no ping — it wastes 4+ seconds)
                tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                tcp.settimeout(5.0)
                print(f"[BRIDGE] Robot {i}: TCP connecting to {c.ip}:{c.port} ...", flush=True)
                self.logLine.emit(i, f"TCP connect -> {c.ip}:{c.port}")
                tcp.connect((c.ip, int(c.port)))
                print(f"[BRIDGE] Robot {i}: TCP connected!", flush=True)
                self.logLine.emit(i, "TCP connected")

                # ListServices
                self.logLine.emit(i, "EIP: ListServices")
                tcp.sendall(self._build_list_services())
                _ = tcp.recv(1024)

                # RegisterSession
                self.logLine.emit(i, "EIP: RegisterSession")
                session = self._register_session(tcp, i)
                print(f"[BRIDGE] Robot {i}: session=0x{session:08X}", flush=True)
                self.logLine.emit(i, f"EIP: session=0x{session:08X}")

                # ForwardOpen
                self.logLine.emit(i, "CIP: ForwardOpen send")
                fwd = self._build_forward_open(i, session)
                tcp.sendall(fwd)
                resp = tcp.recv(2048)

                # Verify FO reply
                svc = resp[40] if len(resp) > 40 else 0
                if svc != 0xD4:
                    self.logLine.emit(i, f"ForwardOpen bad service byte at [40]=0x{svc:02X}")
                    raise RuntimeError("ForwardOpen failed (service != 0xD4)")

                # Extract both conn ids
                conn0, conn1 = self._extract_conn_ids(resp)
                o2t_conn_id = conn0
                t2o_conn_id = conn1

                self._o2t_conn_id[i] = o2t_conn_id
                self._t2o_conn_id[i] = t2o_conn_id

                with self._rx_map_lock:
                    self._rx_map[t2o_conn_id] = i

                print(f"[BRIDGE] Robot {i}: ForwardOpen OK  o2t=0x{o2t_conn_id:08X} t2o=0x{t2o_conn_id:08X}", flush=True)
                self.logLine.emit(i, f"FO OK: o2t=0x{o2t_conn_id:08X} t2o=0x{t2o_conn_id:08X}")

                # Ensure shared UDP RX is running
                self._ensure_udp_rx_listener()

                # TX socket (do NOT bind; just send to robot:2222)
                tx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                tx_sock.settimeout(0.5)

                # Set CYCLIC now
                self._state[i] = 2
                self.stateChanged.emit(i)
                print(f"[BRIDGE] Robot {i}: CYCLIC — sending/receiving UDP on port 2222", flush=True)
                self.logLine.emit(i, "State -> CYCLIC")

                def udp_tx():
                    interval = 0.008
                    while not self._stop_events[i].is_set():
                        try:
                            pkt = self._build_udp_output(i, o2t_conn_id)
                            tx_sock.sendto(pkt, (c.ip, 2222))
                            self._udp_tx[i] += 1
                            self._outgoing_seq[i] = (self._outgoing_seq[i] + 1) & 0xFFFFFFFF
                        except Exception:
                            pass
                        time.sleep(interval)

                def watchdog():
                    while not self._stop_events[i].is_set():
                        time.sleep(0.5)
                        ts = self._last_udp_ts[i]
                        if ts > 0:
                            self._last_rx_ms[i] = int((time.time() - ts) * 1000.0)
                            if (time.time() - ts) > 2.0:
                                self.logLine.emit(i, "WATCHDOG: no UDP RX for 2.0s -> stopping")
                                self._stop_events[i].set()
                                break

                threading.Thread(target=udp_tx, daemon=True).start()
                threading.Thread(target=watchdog, daemon=True).start()

                while not self._stop_events[i].is_set():
                    time.sleep(0.2)

                self.logLine.emit(i, "Worker stopping (stop_event set)")

            except Exception as e:
                self._state[i] = 3
                self._fault[i] = str(e)
                self.stateChanged.emit(i)
                self.faulted.emit(i, self._fault[i])
                _sys_log(SYSTEM_LOG_JSONL, "ROBOT_FAULT", None, {"robot": i, "error": str(e)})
                print(f"[BRIDGE] Robot {i}: FAULT: {e}", flush=True)
                self.logLine.emit(i, f"FAULT: {e}")
                self.logLine.emit(i, traceback.format_exc())

            finally:
                self._state[i] = 0 if self._state[i] != 3 else 3
                self.stateChanged.emit(i)

                if tx_sock:
                    try:
                        tx_sock.close()
                    except Exception:
                        pass
                if tcp:
                    try:
                        tcp.close()
                    except Exception:
                        pass

                with self._rx_map_lock:
                    tid = self._t2o_conn_id[i]
                    if tid in self._rx_map and self._rx_map[tid] == i:
                        del self._rx_map[tid]

                print(f"[BRIDGE] Robot {i}: worker exit (state={self._state[i]})", flush=True)
                self.logLine.emit(i, "Worker exit")

        t = threading.Thread(target=worker, daemon=True)
        self._threads[i] = t
        t.start()

    @Slot(int, int, int)
    def setOutputWord(self, i, word_index, value):
        """Set a single output WORD for a single robot."""
        i = self._clamp_robot(i)
        try:
            wi = int(word_index)
        except Exception:
            wi = 0
        wi = max(0, min(255, wi))

        try:
            v = int(value) & 0xFFFF
        except Exception:
            v = 0

        with self._io_lock:
            self._outputs[i][wi] = v

        try:
            self.ioUpdated.emit(i)
        except Exception:
            pass

    @Slot(int, int)
    def setOutputWordAll(self, word_index, value):
        """Set the same output WORD on all 4 robots."""
        try:
            wi = int(word_index)
        except Exception:
            wi = 0
        wi = max(0, min(255, wi))

        try:
            v = int(value) & 0xFFFF
        except Exception:
            v = 0

        with self._io_lock:
            for r in range(4):
                self._outputs[r][wi] = v

        for r in range(4):
            try:
                self.ioUpdated.emit(r)
            except Exception:
                pass

    @Slot(int)
    def disconnectRobot(self, i):
        i = self._clamp_robot(i)
        self.logLine.emit(i, "DISCONNECT requested")
        _sys_log(SYSTEM_LOG_JSONL, "ROBOT_DISCONNECT", None, {"robot": i})
        self._stop_events[i].set()
        self._state[i] = 0
        self.stateChanged.emit(i)

        with self._rx_map_lock:
            tid = self._t2o_conn_id[i]
            if tid in self._rx_map and self._rx_map[tid] == i:
                del self._rx_map[tid]

    # -------------------------
    # EtherNet/IP / CIP helpers
    # -------------------------
    def _encap_header(self, cmd, session, length):
        return struct.pack("<HHIIQI", cmd, length, session, 0, 0, 0)

    def _build_list_services(self):
        return (
            struct.pack("<H", 0x0004)
            + struct.pack("<H", 0x0000)
            + struct.pack("<I", 0x00000000)
            + struct.pack("<I", 0x00000000)
            + b"\x00" * 8
            + struct.pack("<I", 0x00000000)
        )

    def _register_session(self, sock, robot_i):
        payload = struct.pack("<HH", 1, 0)
        sock.sendall(self._encap_header(0x65, 0, len(payload)) + payload)
        resp = sock.recv(1024)
        if len(resp) < 8:
            raise RuntimeError("RegisterSession short response")
        session = struct.unpack("<I", resp[4:8])[0]
        return session

    def _build_forward_open(self, robot_i, session):
        c = self._cfgs[robot_i]
        slot = int(c.slot)

        cip = b"\x54\x02\x20\x06\x24\x01" + b"\x05\x99"
        cip += struct.pack("<I", 0x2A365DAE) + struct.pack("<I", 0)
        cip += struct.pack("<H", 0x1234) + struct.pack("<H", 0x0164)
        cip += struct.pack("<I", 0x12345678) + b"\x00\x00\x00\x00"

        in_words = int(c.in_words)
        out_words = int(c.out_words)

        in_size = (in_words * 2) + 2
        out_size = (out_words * 2) + 6

        CONN_TYPE_P2P = 0b10 << 13  # 0x4000
        CONN_FIXED = 0

        in_param = CONN_TYPE_P2P | CONN_FIXED | in_size
        out_param = CONN_TYPE_P2P | CONN_FIXED | out_size

        self.logLine.emit(robot_i, f"FO params: in_param=0x{in_param:04X} out_param=0x{out_param:04X}")

        cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", out_param)
        cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", in_param) + b"\x01"

        path = bytearray(b"\x34\x04")
        path += struct.pack("<H", 0x0164)
        path += struct.pack("<H", 0x000C) + struct.pack("<H", 0x0004)
        path += b"\x03\x01\x20\x04\x24\x64"
        ot = 150 + slot
        to = 100 + slot
        path += struct.pack("BB", 0x2C, ot) + struct.pack("BB", 0x2C, to)

        cip += struct.pack("B", len(path) // 2) + path

        rr = struct.pack("<IHH", 0, 0, 2)
        rr += struct.pack("<HH", 0x0000, 0)
        rr += struct.pack("<HH", 0x00B2, len(cip)) + cip

        return self._encap_header(0x6F, session, len(rr)) + rr

    def _extract_conn_ids(self, data: bytes):
        uci = data.find(b"\xB2\x00")
        if uci < 0:
            raise RuntimeError("Missing Unconnected-Data Item (0x00B2)")

        cip_start = uci + 4
        service = data[cip_start + 0]
        status = data[cip_start + 1]
        addn = data[cip_start + 2]

        if service != 0xD4 or status != 0x00:
            raise RuntimeError(f"ForwardOpen error: svc=0x{service:02X} status=0x{status:02X}")

        conn_off = cip_start + 4 + (addn * 2)
        conn0 = struct.unpack_from("<I", data, conn_off + 0)[0]
        conn1 = struct.unpack_from("<I", data, conn_off + 4)[0]
        return conn0, conn1

    # -------------------------
    # UDP / I/O helpers
    # -------------------------
    def _process_io_data(self, robot_i, data):
        # Find the Connected Data Item (0x00B1)
        idx = data.find(b"\xB1\x00")
        if idx < 0:
            return

        if len(data) < idx + 4:
            return

        payload_len = struct.unpack_from("<H", data, idx + 2)[0]
        payload_start = idx + 4
        payload_end = payload_start + payload_len

        if payload_end > len(data):
            return

        payload = data[payload_start:payload_end]

        # B1 payload format: seq16(2) + run_idle(4) + io_words
        # Skip 6 bytes to get to the actual I/O data
        if len(payload) < 6:
            return
        io_data = payload[6:]

        wc = len(io_data) // 2
        if wc <= 0:
            return

        words = list(struct.unpack_from("<" + "H" * wc, io_data, 0))

        in_n = max(1, int(self._cfgs[robot_i].in_words))
        if len(words) < in_n:
            words += [0] * (in_n - len(words))
        else:
            words = words[:in_n]

        with self._io_lock:
            self._inputs[robot_i][:in_n] = words

        # publish words to QML
        if robot_i == 0:
            self._inWordsRx.emit(words)

    def _build_udp_output(self, robot_i, conn_id):
        c = self._cfgs[robot_i]
        seq = self._outgoing_seq[robot_i]

        header = struct.pack("<H", 2) + struct.pack("<HHI", 0x8002, 8, conn_id)
        header += struct.pack("<I", seq)

        out_n = max(1, int(c.out_words))
        with self._io_lock:
            outs = list(self._outputs[robot_i][:out_n])

        resp_payload = struct.pack("<H", seq & 0xFFFF) + struct.pack("<I", 1)
        resp_payload += struct.pack("<" + "H" * out_n, *[int(x) & 0xFFFF for x in outs])

        pkt = header + struct.pack("<HH", 0x00B1, len(resp_payload)) + resp_payload
        return pkt
