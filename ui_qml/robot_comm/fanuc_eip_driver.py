# ui_qml/robot_comm/fanuc_eip_driver.py
# Add/replace with this DEBUG infrastructure + call sites. (Keep your existing logic.)
print("IMPORTED fanuc_eip_driver FROM:", __file__)

import socket
import struct
import time
import threading
import traceback


def _hexdump(b: bytes, max_len: int = 256) -> str:
    if not b:
        return "<empty>"
    bb = b[:max_len]
    s = bb.hex()
    if len(b) > max_len:
        s += f"...(+{len(b)-max_len} bytes)"
    return s


class FanucEipDriver:
    def __init__(self, debug: bool = False, log_max: int = 400):
        self.debug = debug
        self._log_max = log_max
        self._log = []  # list[str]
        self._log_lock = threading.Lock()

        self._run = threading.Event()
        self._thread = None
        self._sock = None
        self._udp_sock = None

        self._state = 0  # 0=disc 1=conn 2=cyclic 3=fault
        self._fault = ""
        self._last_udp_recv = 0.0
        self._udp_rx_count = 0
        self._udp_tx_count = 0

        self.robot_ip = "192.168.2.1"
        self.eip_port = 44818
        self.eth_slot = 1
        self.in_words = 4
        self.out_words = 4

        self._lock = threading.Lock()
        self._inputs_words = [0] * 4
        self._outputs_words = [0] * 4
        self._outgoing_seq = 1
        self._io_cb = None

    # -------------------- DEBUG --------------------
    def _dbg(self, msg: str):
        ts = time.strftime("%H:%M:%S")
        line = f"[{ts}] {msg}"
        with self._log_lock:
            self._log.append(line)
            if len(self._log) > self._log_max:
                self._log = self._log[-self._log_max :]
        if self.debug:
            print(line)

    def get_debug_log(self) -> str:
        with self._log_lock:
            return "\n".join(self._log)

    def clear_debug_log(self):
        with self._log_lock:
            self._log.clear()

    # -------------------- getters --------------------
    def get_state(self): return self._state
    def get_fault(self): return self._fault
    def get_last_rx_ms(self):
        if self._last_udp_recv <= 0:
            return 0
        return int((time.time() - self._last_udp_recv) * 1000.0)

    def get_udp_counts(self):
        return int(self._udp_rx_count), int(self._udp_tx_count)

    def get_inputs(self):
        with self._lock:
            return list(self._inputs_words)

    def get_outputs(self):
        with self._lock:
            return list(self._outputs_words)

    # -------------------- config/control --------------------
    def configure(self, ip: str, port: int, slot: int, in_words: int, out_words: int):
        self.robot_ip = ip
        self.eip_port = int(port)
        self.eth_slot = int(slot)
        self.in_words = int(in_words)
        self.out_words = int(out_words)
        with self._lock:
            self._inputs_words = [0] * self.in_words
            self._outputs_words = [0] * self.out_words
        self._dbg(f"CONFIG ip={self.robot_ip} port={self.eip_port} slot={self.eth_slot} in_words={self.in_words} out_words={self.out_words}")

    def start(self, io_cb):
        self._io_cb = io_cb
        if self._thread and self._thread.is_alive():
            self._dbg("START ignored (already running)")
            return
        self._dbg("START requested")
        self._run.set()
        self._thread = threading.Thread(target=self._worker, daemon=True)
        self._thread.start()

    def stop(self):
        self._dbg("STOP requested")
        self._run.clear()
        self._state = 0
        try:
            if self._sock: self._sock.close()
        except: pass
        try:
            if self._udp_sock: self._udp_sock.close()
        except: pass
        self._sock = None
        self._udp_sock = None

    # -------------------- EIP helpers --------------------
    def _encap_header(self, cmd, session, length):
        return struct.pack("<HHIIQI", cmd, length, session, 0, 0, 0)

    def _build_list_services(self):
        return (
            struct.pack("<H", 0x0004) +
            struct.pack("<H", 0x0000) +
            struct.pack("<I", 0x00000000) +
            struct.pack("<I", 0x00000000) +
            b"\x00" * 8 +
            struct.pack("<I", 0x00000000)
        )

    def _register_session(self, sock):
        payload = struct.pack("<HH", 1, 0)
        pkt = self._encap_header(0x65, 0, len(payload)) + payload
        self._dbg(f"EIP TX RegisterSession len={len(pkt)} hex={_hexdump(pkt)}")
        sock.sendall(pkt)
        resp = sock.recv(1024)
        self._dbg(f"EIP RX RegisterSession len={len(resp)} hex={_hexdump(resp)}")
        session = struct.unpack("<I", resp[4:8])[0]
        self._dbg(f"EIP session=0x{session:08X}")
        return session

    def _build_forward_open(self, session):
        slot = self.eth_slot

        cip = b"\x54\x02\x20\x06\x24\x01" + b"\x05\x99"
        cip += struct.pack("<I", 0x2A365DAE) + struct.pack("<I", 0)
        cip += struct.pack("<H", 0x1234) + struct.pack("<H", 0x0164)
        cip += struct.pack("<I", 0x12345678) + b"\x00\x00\x00\x00"

        in_size = (self.in_words * 2) + 2
        out_size = (self.out_words * 2) + 6

        CONN_TYPE_MC = 0b01 << 13
        CONN_TYPE_P2P = 0b10 << 13
        CONN_FIXED = 0

        in_param = CONN_TYPE_MC | CONN_FIXED | in_size
        out_param = CONN_TYPE_P2P | CONN_FIXED | out_size

        self._dbg(f"FO sizes: in_size={in_size} out_size={out_size} in_param=0x{in_param:04X} out_param=0x{out_param:04X}")

        cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", out_param)
        cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", in_param) + b'\x01'

        path = bytearray(b"\x34\x04")
        path += struct.pack("<H", 0x0164)
        path += struct.pack("<H", 0x000C) + struct.pack("<H", 0x0004)
        path += b"\x03\x01\x20\x04\x24\x64"
        ot = 150 + slot
        to = 100 + slot
        path += struct.pack("BB", 0x2C, ot) + struct.pack("BB", 0x2C, to)

        cip += struct.pack("B", len(path)//2) + path

        rr = struct.pack("<IHH", 0, 0, 2)
        rr += struct.pack("<HH", 0x0000, 0)
        rr += struct.pack("<HH", 0x00B2, len(cip)) + cip

        pkt = self._encap_header(0x6F, session, len(rr)) + rr
        self._dbg(f"EIP TX ForwardOpen len={len(pkt)} hex={_hexdump(pkt)}")
        return pkt

    def _extract_multicast_info(self, data: bytes):
        # Show structure in logs
        cmd, length = struct.unpack_from("<HH", data, 0)
        self._dbg(f"FO RX encap cmd=0x{cmd:04X} lenField={length} total={len(data)}")
        item_count = struct.unpack_from("<H", data, 30)[0]
        self._dbg(f"FO RX item_count={item_count}")

        offset = 32
        mcast_ip = None
        for n in range(item_count):
            itype, ilen = struct.unpack_from("<HH", data, offset)
            self._dbg(f"FO RX item[{n}] type=0x{itype:04X} ilen={ilen} off={offset}")
            if itype == 0x8001 and ilen >= 8:
                addr = data[offset+8: offset+12]
                mcast_ip = socket.inet_ntoa(addr)
                self._dbg(f"FO RX multicast_ip={mcast_ip}")
            offset += 4 + ilen

        uci = data.find(b"\xB2\x00")
        self._dbg(f"FO RX uci_off={uci}")
        if uci < 0:
            raise Exception("Missing Unconnected-Data Item")

        cip_start = uci + 4
        service, status, addn = struct.unpack_from("<BBB", data, cip_start)
        self._dbg(f"FO RX CIP service=0x{service:02X} status=0x{status:02X} addn={addn}")

        if service != 0xD4 or status != 0x00:
            raise Exception(f"ForwardOpen error svc=0x{service:02X} status=0x{status:02X}")

        conn_off = cip_start + 4 + (addn * 2)
        o2t_conn_id = struct.unpack_from("<I", data, conn_off)[0]
        self._dbg(f"FO RX o2t_conn_id=0x{o2t_conn_id:08X} conn_off={conn_off}")

        if not mcast_ip:
            raise Exception("Missing T→O Socket Address Item (0x8001)")

        return mcast_ip, o2t_conn_id

    def _do_tcp_connect(self, retry_delay=1.0):
        while self._run.is_set():
            self._dbg(f"TCP connect {self.robot_ip}:{self.eip_port} ...")
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            try:
                sock.connect((self.robot_ip, self.eip_port))
                self._dbg(f"TCP connected local={sock.getsockname()} remote={sock.getpeername()}")
                return sock
            except Exception as e:
                self._dbg(f"TCP connect failed: {e!r}")
                try: sock.close()
                except: pass
                time.sleep(retry_delay)
        return None

    # -------------------- UDP --------------------
    def _process_io_data(self, data: bytes):
        if len(data) < 24:
            self._dbg(f"UDP RX too short len={len(data)}")
            return

        payload = data[20:]
        words = list(struct.unpack_from("<" + "H" * (len(payload) // 2), payload))

        if len(words) < self.in_words:
            words += [0] * (self.in_words - len(words))
        elif len(words) > self.in_words:
            words = words[:self.in_words]

        with self._lock:
            self._inputs_words = words

        if self._io_cb:
            with self._lock:
                outs = list(self._outputs_words)
            self._io_cb(words, outs)

    def _udp_sender_loop(self, conn_id):
        interval = 0.008
        self._dbg(f"UDP TX loop start conn_id=0x{conn_id:08X}")
        while self._run.is_set():
            try:
                with self._lock:
                    outs = list(self._outputs_words)

                header = struct.pack("<H", 2) + struct.pack("<HHI", 0x8002, 8, conn_id)
                header += struct.pack("<I", self._outgoing_seq)

                resp_payload = struct.pack("<H", self._outgoing_seq & 0xFFFF) + struct.pack("<I", 1)
                resp_payload += struct.pack("<" + "H"*self.out_words, *outs[:self.out_words])
                resp = header + struct.pack("<HH", 0x00B1, len(resp_payload)) + resp_payload

                self._udp_sock.sendto(resp, (self.robot_ip, 2222))
                self._udp_tx_count += 1
                self._outgoing_seq = (self._outgoing_seq + 1) & 0xFFFFFFFF
            except Exception as e:
                self._dbg(f"UDP TX error: {e!r}")
                time.sleep(0.25)

            time.sleep(interval)

    def _listen_loop(self):
        self._dbg("UDP RX loop start")
        while self._run.is_set():
            try:
                data, addr = self._udp_sock.recvfrom(4096)
                self._last_udp_recv = time.time()
                self._udp_rx_count += 1
                if self.debug and (self._udp_rx_count % 200 == 1):
                    self._dbg(f"UDP RX sample from {addr} len={len(data)} hex={_hexdump(data, 96)}")
            except socket.timeout:
                continue
            except Exception as e:
                self._dbg(f"UDP RX error: {e!r}")
                self._run.clear()
                break

            try:
                self._process_io_data(data)
            except Exception as e:
                self._dbg(f"UDP parse error: {e!r}")
                if self.debug:
                    traceback.print_exc()

    def _udp_watchdog(self, timeout=2.0, check_interval=0.5):
        self._dbg(f"UDP watchdog start timeout={timeout}s")
        while self._run.is_set():
            time.sleep(check_interval)
            if self._last_udp_recv > 0 and (time.time() - self._last_udp_recv) > timeout:
                self._fault = f"No UDP in {timeout}s"
                self._state = 3
                self._dbg(f"WATCHDOG trip: {self._fault}")
                self._run.clear()
                break

    def _start_udp(self, mcast_ip, conn_id, local_ip):
        self._udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._udp_sock.setsockopt(socket.IPPROTO_IP, socket.IP_TTL, 1)
        self._udp_sock.settimeout(2.0)

        self._udp_sock.bind(("", 2222))
        self._dbg(f"UDP bind *:2222 ok; local_ip={local_ip} mcast_ip={mcast_ip}")

        if mcast_ip != self.robot_ip:
            try:
                mreq = struct.pack("4s4s", socket.inet_aton(mcast_ip), socket.inet_aton(local_ip))
                self._udp_sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
                self._dbg("UDP multicast join OK")
            except Exception as e:
                self._dbg(f"UDP multicast join FAILED: {e!r}")

        threading.Thread(target=self._listen_loop, daemon=True).start()
        threading.Thread(target=self._udp_sender_loop, args=(conn_id,), daemon=True).start()
        threading.Thread(target=self._udp_watchdog, daemon=True).start()

    # -------------------- main worker --------------------
    def _worker(self):
        self._dbg("WORKER start")
        while self._run.is_set():
            self._fault = ""
            self._state = 1
            self._last_udp_recv = 0.0
            self._udp_rx_count = 0
            self._udp_tx_count = 0
            self._outgoing_seq = 1

            try:
                self._sock = self._do_tcp_connect()
                if not self._sock:
                    self._dbg("WORKER exit (no socket)")
                    break

                ls = self._build_list_services()
                self._dbg(f"EIP TX ListServices len={len(ls)} hex={_hexdump(ls)}")
                self._sock.sendall(ls)
                resp_ls = self._sock.recv(1024)
                self._dbg(f"EIP RX ListServices len={len(resp_ls)} hex={_hexdump(resp_ls)}")

                session = self._register_session(self._sock)
                fo = self._build_forward_open(session)
                self._sock.sendall(fo)
                resp = self._sock.recv(1024)
                self._dbg(f"EIP RX ForwardOpen len={len(resp)} hex={_hexdump(resp)}")

                if len(resp) < 41:
                    raise RuntimeError(f"ForwardOpen reply too short len={len(resp)}")

                svc = resp[40]
                self._dbg(f"FO RX svcByte@40=0x{svc:02X}")
                if svc != 0xD4:
                    raise RuntimeError(f"Expected FO reply svc=0xD4, got 0x{svc:02X}")

                local_ip = self._sock.getsockname()[0]

                try:
                    mcast_ip, conn_id = self._extract_multicast_info(resp)
                    self._dbg(f"FO parsed multicast_ip={mcast_ip} conn_id=0x{conn_id:08X}")
                except Exception as e:
                    self._dbg(f"FO parse multicast failed: {e!r} -> fallback unicast")
                    conn_id = struct.unpack_from("<I", resp, 44)[0]
                    mcast_ip = self.robot_ip
                    self._dbg(f"FO fallback conn_id=0x{conn_id:08X} mcast_ip={mcast_ip}")

                self._state = 2
                self._start_udp(mcast_ip, conn_id, local_ip)

                while self._run.is_set():
                    time.sleep(0.2)

            except Exception as e:
                self._fault = str(e)
                self._state = 3
                self._dbg(f"WORKER exception: {e!r}")
                if self.debug:
                    traceback.print_exc()

            finally:
                try:
                    if self._sock: self._sock.close()
                except: pass
                try:
                    if self._udp_sock: self._udp_sock.close()
                except: pass
                self._sock = None
                self._udp_sock = None

            if self._run.is_set():
                self._dbg("WORKER retry in 1s")
                time.sleep(1.0)

        self._dbg("WORKER stop")
