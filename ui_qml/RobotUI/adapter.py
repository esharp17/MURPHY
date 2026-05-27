# dummy_fanuc_eip_adapter_ui.py
# Dummy EtherNet/IP "robot adapter" with a simple UI:
# - Accepts TCP 44818: ListServices, RegisterSession, ForwardOpen (enough for your existing driver)
# - UDP 2222:
#    * Receives O->T (PC->robot) data and displays it
#    * Sends T->O (robot->PC) data you can toggle in the UI
#
# This is intentionally shaped to match the packet structure you pasted:
# - UDP payload is CPF: [item_count=2][0x8002 seq addr item][0x00B1 connected data item]
# - Connected data item = [seq16][run_idle32][io_bytes...]
#
# NOTE:
# Your current driver reads UDP starting at byte offset 20 (data[20:]) and then truncates to in_words.
# This dummy sends valid CPF so that offset 20 lands at the first 2 bytes of the 0x00B1 data,
# exactly like your capture. If your in_words is small, you may only see header words; increase in_words
# in your driver/config to include the IO words after seq/run-idle.

import socket
import struct
import threading
import time
import tkinter as tk
from tkinter import ttk


def log(msg):
    print(f"[DUMMY] {msg}", flush=True)


def u16(x): return x & 0xFFFF

def u32(x): return x & 0xFFFFFFFF


class DummyEipAdapter:
    def __init__(self, bind_ip="0.0.0.0", tcp_port=44818, udp_port=2222, in_words=4, out_words=4):
        self.bind_ip = bind_ip
        self.tcp_port = int(tcp_port)
        self.udp_port = int(udp_port)

        self.in_words = int(in_words)   # robot->pc (T->O) word count
        self.out_words = int(out_words) # pc->robot (O->T) word count

        self._lock = threading.Lock()
        self._run = threading.Event()

        # "inputs" = robot -> PC (what UI toggles and what we send on UDP)
        self.inputs_words = [0] * self.in_words
        # "outputs" = PC -> robot (what we receive on UDP and display)
        self.outputs_words = [0] * self.out_words

        # learned remote (scanner) endpoint for UDP sends
        self._scanner_ip = None
        self._scanner_udp_port = 2222

        # TCP session handle we hand out
        self._session = 0x801FE810  # can be fixed; driver doesn’t care as long as nonzero

        # ForwardOpen reply conn-id used by scanner->adapter (O->T) in UDP 0x8002 item
        # Use the value seen in your UDP capture:
        self.o2t_conn_id = 0x01641234

        # T->O conn-id (adapter->scanner). Your driver doesn’t validate on RX, but keep consistent.
        self._t2o_base = 0x50B04F00
        self._next_t2o = self._t2o_base
        self._active_conns = []  # list of {"t2o_id": int, "scanner_ip": str}

        self._tcp_thread = None
        self._udp_rx_thread = None
        self._udp_tx_thread = None

        self._udp_sock = None

        self._tx_seq32 = 1
        self._tx_seq16 = 1

        self._last_udp_rx_ts = 0.0

    # ---------------- TCP (44818) ----------------
    @staticmethod
    def _encap_header(cmd, length, session):
        # ENIP encapsulation header: <HHIIQI  (cmd, len, session, status, sender_ctx(8), options)
        return struct.pack("<HHIIQI", cmd, length, session, 0, 0, 0)

    def _handle_list_services(self, session):
        # Payload copied structurally from your capture:
        # item_count=1, type_id=0x0100, item_len=0x0014, protocol_ver=1, capability=0,
        # name "Communications" padded to 16.
        name = b"Communications"
        name_padded = name + b"\x00" * (16 - len(name))
        payload = struct.pack("<H", 1) + struct.pack("<HHHH", 0x0100, 0x0014, 0x0001, 0x0000) + name_padded
        return self._encap_header(0x0004, len(payload), session) + payload

    def _handle_register_session(self):
        payload = struct.pack("<HH", 1, 0)  # protocol version 1, flags 0
        return self._encap_header(0x0065, len(payload), self._session) + payload

    def _build_forward_open_response(self, scanner_ip: str, t2o_id: int = None):
        if t2o_id is None:
            t2o_id = self._t2o_base
        # Build SendRRData response with 4 CPF items exactly like your capture:
        #  - Null address
        #  - Unconnected data item with CIP ForwardOpen reply (service 0xD4)
        #  - Socket Address Info O->T (0x8000)
        #  - Socket Address Info T->O (0x8001)
        #
        # Your driver’s parser requirements:
        # - item_count at offset 30
        # - an item type 0x8001 with ilen>=8 and IPv4 at offset+8
        # - find b"\xB2\x00" then CIP starts 4 bytes later
        # - CIP bytes: [service][status][addn][reserved]
        # - o2t_conn_id located at cip_start+4 (since addn=0)
        #
        # Keep CIP minimal:
        cip = bytearray()
        cip += struct.pack("BBBB", 0xD4, 0x00, 0x00, 0x00)        # service, status, addn, reserved
        cip += struct.pack("<I", u32(self.o2t_conn_id))            # o->t conn id
        cip += struct.pack("<I", u32(t2o_id))                      # t->o conn id (unique per connection)
        cip += b"\x00" * 18                                        # padding to look like real-ish reply

        # CPF items:
        items = bytearray()

        # item0: Null Address Item
        items += struct.pack("<HH", 0x0000, 0)

        # item1: Unconnected Data Item
        items += struct.pack("<HH", 0x00B2, len(cip)) + cip

        # item2: Socket Address Info O->T (0x8000), len 16: sin_family, sin_port, sin_addr, sin_zero[8]
        items += struct.pack("<HH", 0x8000, 16)
        items += struct.pack(">HH", 2, 2222)   # big-endian for sockaddr fields
        items += socket.inet_aton("0.0.0.0")
        items += b"\x00" * 8

        # item3: Socket Address Info T->O (0x8001), len 16
        items += struct.pack("<HH", 0x8001, 16)
        items += struct.pack(">HH", 2, 2222)
        # Put scanner_ip here; your capture did. Your driver uses this as "mcast_ip".
        items += socket.inet_aton(scanner_ip)
        items += b"\x00" * 8

        # SendRRData command specific data:
        # interface_handle (4) + timeout (2) + item_count (2) + items...
        rr = struct.pack("<IHH", 0, 0, 4) + items
        log("ForwardOpen response built")
        return self._encap_header(0x006F, len(rr), self._session) + rr

    def _handle_tcp_client(self, conn, addr):
        """Handle a single TCP client connection in its own thread."""
        scanner_ip = addr[0]
        log(f"TCP connection from {addr}")
        conn.settimeout(5.0)
        t2o_id = None

        try:
            while self._run.is_set():
                try:
                    hdr = conn.recv(24)
                except socket.timeout:
                    continue  # TCP idle after ForwardOpen is normal; keep connection alive
                except Exception:
                    break
                if not hdr or len(hdr) < 24:
                    break
                cmd, length, session, status, sender_ctx, options = struct.unpack("<HHIIQI", hdr)
                log(f"TCP RX cmd=0x{cmd:04X} len={length} session=0x{session:08X}")
                payload = b""
                while len(payload) < length:
                    chunk = conn.recv(length - len(payload))
                    if not chunk:
                        break
                    payload += chunk

                if cmd == 0x0004:  # ListServices
                    resp = self._handle_list_services(session)
                    conn.sendall(resp)
                    log("TX ListServices response")

                elif cmd == 0x0065:  # RegisterSession
                    resp = self._handle_register_session()
                    conn.sendall(resp)
                    log("TX RegisterSession response")

                elif cmd == 0x006F:  # SendRRData (ForwardOpen)
                    with self._lock:
                        t2o_id = u32(self._next_t2o)
                        self._next_t2o = u32(self._next_t2o + 1)
                        self._active_conns.append({"t2o_id": t2o_id, "scanner_ip": scanner_ip})
                        self._scanner_ip = scanner_ip
                        self._scanner_udp_port = 2222
                    resp = self._build_forward_open_response(scanner_ip, t2o_id)
                    conn.sendall(resp)
                    log(f"TX ForwardOpen response t2o_id=0x{t2o_id:08X} (scanner_ip={scanner_ip})")

                else:
                    # Ignore unsupported commands
                    pass

        except Exception:
            pass
        finally:
            try:
                conn.close()
                log(f"TCP connection closed ({addr})")
            except Exception:
                pass
            if t2o_id is not None:
                with self._lock:
                    self._active_conns = [c for c in self._active_conns if c.get("t2o_id") != t2o_id]

    def _tcp_server(self):
        lsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        lsock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        lsock.bind((self.bind_ip, self.tcp_port))
        lsock.listen(8)
        log(f"TCP listening on {self.bind_ip}:{self.tcp_port}")

        while self._run.is_set():
            try:
                lsock.settimeout(1.0)
                conn, addr = lsock.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            # Handle each connection in its own thread
            t = threading.Thread(target=self._handle_tcp_client, args=(conn, addr), daemon=True)
            t.start()

        try:
            lsock.close()
        except Exception:
            pass

    # ---------------- UDP (2222) ----------------
    def _udp_open(self):
        self._udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._udp_sock.bind(("0.0.0.0", self.udp_port))
        log(f"UDP bound 0.0.0.0:{self.udp_port}")
        self._udp_sock.settimeout(1.0)

    def _parse_scanner_udp(self, data: bytes):
        # Expect CPF: item_count(2), then items.
        if len(data) < 10:
            return

        item_count = struct.unpack_from("<H", data, 0)[0]
        off = 2
        conn_id = None
        io_words = None

        for _ in range(item_count):
            if off + 4 > len(data):
                break
            itype, ilen = struct.unpack_from("<HH", data, off)
            off += 4
            if off + ilen > len(data):
                break

            item = data[off:off + ilen]

            if itype == 0x8002 and ilen >= 8:
                conn_id = struct.unpack_from("<I", item, 0)[0]
                # seq32 at +4 (ignored)

            if itype == 0x00B1 and ilen >= (2 + 4):
                # connected data = seq16 + runidle32 + io_bytes
                io = item[6:]
                # take first out_words*2 bytes
                need = self.out_words * 2
                if len(io) >= need:
                    io_words = list(struct.unpack_from("<" + "H" * self.out_words, io, 0))
                else:
                    # pad
                    tmp = io + b"\x00" * (need - len(io))
                    io_words = list(struct.unpack_from("<" + "H" * self.out_words, tmp, 0))

            off += ilen

        if io_words is not None:
            with self._lock:
                self.outputs_words = [u16(x) for x in io_words]
                self._last_udp_rx_ts = time.time()

    def _udp_rx_loop(self):
        while self._run.is_set():
            try:
                data, addr = self._udp_sock.recvfrom(4096)
                log(f"UDP RX from {addr} len={len(data)}")
            except socket.timeout:
                continue
            except OSError:
                break

            # Learn scanner address for TX (if not learned via TCP yet)
            with self._lock:
                self._scanner_ip = addr[0]
                self._scanner_udp_port = addr[1] if addr[1] else 2222

            self._parse_scanner_udp(data)
            log("UDP RX parsed O->T data")

    def _build_adapter_udp(self, t2o_id: int):

        with self._lock:
            in_words = [u16(x) for x in self.inputs_words]

        io = struct.pack("<H", u16(self._tx_seq16))
        io += struct.pack("<" + "H" * self.in_words, *in_words)

        payload = bytearray()
        payload += struct.pack("<H", 2)  # item count
        payload += struct.pack("<HH", 0x8002, 8)
        payload += struct.pack("<I", u32(t2o_id))
        payload += struct.pack("<I", u32(self._tx_seq32))
        payload += struct.pack("<HH", 0x00B1, len(io))
        payload += io

        # Advance seq counters
        self._tx_seq32 = u32(self._tx_seq32 + 1)
        self._tx_seq16 = u16(self._tx_seq16 + 1)

        return bytes(payload)

    def _udp_tx_loop(self):
        # 10ms-ish is typical; your driver uses 8ms
        period = 0.008
        while self._run.is_set():
            with self._lock:
                conns = list(self._active_conns)

            for c in conns:
                try:
                    pkt = self._build_adapter_udp(c["t2o_id"])
                    self._udp_sock.sendto(pkt, (c["scanner_ip"], 2222))
                except Exception:
                    pass

            if conns and (self._tx_seq32 % 500) == 0:
                log(f"UDP TX seq={self._tx_seq32} conns={len(conns)}")

            time.sleep(period)

    # ---------------- control ----------------
    def start(self):
        log("START called")
        if self._run.is_set():
            return
        self._run.set()

        self._udp_open()
        log("UDP socket opened")

        self._tcp_thread = threading.Thread(target=self._tcp_server, daemon=True)
        self._udp_rx_thread = threading.Thread(target=self._udp_rx_loop, daemon=True)
        self._udp_tx_thread = threading.Thread(target=self._udp_tx_loop, daemon=True)

        self._tcp_thread.start()
        self._udp_rx_thread.start()
        self._udp_tx_thread.start()
        log("TCP/UDP threads started")

    def stop(self):
        log("STOP called")
        self._run.clear()
        try:
            if self._udp_sock:
                log("Closing UDP socket")
                self._udp_sock.close()
        except Exception:
            pass
        self._udp_sock = None

    # ---------------- UI helpers ----------------
    def set_input_bit(self, bit_index: int, value: int):
        word = bit_index // 16
        bit = bit_index % 16
        with self._lock:
            if word >= len(self.inputs_words):
                return
            mask = 1 << bit
            if value:
                self.inputs_words[word] = u16(self.inputs_words[word] | mask)
            else:
                self.inputs_words[word] = u16(self.inputs_words[word] & ~mask)

    def get_inputs_words(self):
        with self._lock:
            return list(self.inputs_words)

    def get_outputs_words(self):
        with self._lock:
            return list(self.outputs_words)

    def get_last_rx_ms(self):
        with self._lock:
            if self._last_udp_rx_ts <= 0:
                return 0
            return int((time.time() - self._last_udp_rx_ts) * 1000)


class App(tk.Tk):
    def __init__(self, sim: DummyEipAdapter):
        super().__init__()
        self.sim = sim
        self.title("Dummy FANUC EIP Adapter (UI)")

        self.inputs_vars = []
        self.outputs_vars = []
        self.word4_var = tk.StringVar(value="0")

        top = ttk.Frame(self)
        top.pack(fill="x", padx=8, pady=8)

        self.lbl_status = ttk.Label(top, text="Stopped")
        self.lbl_status.pack(side="left")

        btn_start = ttk.Button(top, text="Start", command=self.on_start)
        btn_stop = ttk.Button(top, text="Stop", command=self.on_stop)
        btn_start.pack(side="right", padx=(4, 0))
        btn_stop.pack(side="right")

        mid = ttk.Frame(self)
        mid.pack(fill="both", expand=True, padx=8, pady=8)

        lf_in = ttk.LabelFrame(mid, text="Robot → PC (Inputs you toggle / we send)")
        lf_out = ttk.LabelFrame(mid, text="PC → Robot (Outputs received / display)")
        lf_in.pack(side="left", fill="both", expand=True, padx=(0, 6))
        lf_out.pack(side="left", fill="both", expand=True, padx=(6, 0))

        # Inputs toggles (bits 1-64 shown, plus optional 65-80 if in_words >= 5)
        self._build_bits_panel(lf_in, is_inputs=True)
        # Outputs display
        self._build_bits_panel(lf_out, is_inputs=False)

        # Decimal sender mapped to bits 65-80 (word index 4)
        dec_frame = ttk.Frame(lf_in)
        dec_frame.pack(fill="x", padx=6, pady=(0, 6))
        ttk.Label(dec_frame, text="Bits 65-80 decimal:").pack(side="left")
        ent = ttk.Entry(dec_frame, textvariable=self.word4_var, width=8)
        ent.pack(side="left", padx=(6, 0))
        ent.bind("<Return>", self._set_word4_from_entry)
        ent.bind("<FocusOut>", self._set_word4_from_entry)

        bot = ttk.Frame(self)
        bot.pack(fill="x", padx=8, pady=(0, 8))

        self.lbl_words = ttk.Label(bot, text="")
        self.lbl_words.pack(side="left")

        self.after(100, self._ui_tick)
        self.lbl_words.pack(side="left")

        self.after(100, self._ui_tick)

    def _build_bits_panel(self, parent, is_inputs: bool):
        vars_list = self.inputs_vars if is_inputs else self.outputs_vars
        nbits = (self.sim.in_words if is_inputs else self.sim.out_words) * 16

        grid = ttk.Frame(parent)
        grid.pack(padx=6, pady=6)

        # 16 columns, N rows
        cols = 16
        rows = (nbits + cols - 1) // cols

        for r in range(rows):
            for c in range(cols):
                idx = r * cols + c
                if idx >= nbits:
                    continue
                v = tk.IntVar(value=0)
                vars_list.append(v)
                label_txt = str(idx + 1)  # display bits as 1..N
                if is_inputs:
                    cb = ttk.Checkbutton(
                        grid, text=label_txt,
                        variable=v,
                        command=lambda i=idx, vv=v: self.sim.set_input_bit(i, vv.get())
                    )
                else:
                    cb = ttk.Checkbutton(grid, text=label_txt, variable=v)
                    cb.state(["disabled"])
                cb.grid(row=r, column=c, sticky="w", padx=2, pady=1)

    def _set_word4_from_entry(self, *_):
        """Map decimal entry to bits 65-80 (word index 4)."""
        if self.sim.in_words < 5:
            return
        try:
            val = int(self.word4_var.get())
        except Exception:
            return
        val = max(0, min(65535, val))
        with self.sim._lock:
            self.sim.inputs_words[4] = u16(val)
        # refresh checkboxes for bits 65-80
        base = 64
        for b in range(16):
            i = base + b
            if i < len(self.inputs_vars):
                self.inputs_vars[i].set((val >> b) & 1)

    def _sync_word4_entry_from_bits(self):
        if self.sim.in_words < 5:
            return
        with self.sim._lock:
            val = self.sim.inputs_words[4]
        self.word4_var.set(str(val))

    def on_start(self):
        log("UI start pressed")
        self.sim.start()
        self.lbl_status.config(text=f"Running (TCP {self.sim.tcp_port}, UDP {self.sim.udp_port})")

    def on_stop(self):
        log("UI stop pressed")
        self.sim.stop()
        self.lbl_status.config(text="Stopped")

    def _ui_tick(self):
        # Update outputs bits
        out_words = self.sim.get_outputs_words()
        n_out_bits = len(out_words) * 16
        for i in range(n_out_bits):
            w = i // 16
            b = i % 16
            bit = (out_words[w] >> b) & 1
            if i < len(self.outputs_vars):
                self.outputs_vars[i].set(bit)

        # Update word display + RX age
        in_words = self.sim.get_inputs_words()
        rx_ms = self.sim.get_last_rx_ms()
        self.lbl_words.config(
            text=f"IN(words)={['0x%04X'%w for w in in_words]}   OUT(words)={['0x%04X'%w for w in out_words]}   last_rx={rx_ms}ms"
        )

        self.after(100, self._ui_tick)


if __name__ == "__main__":
    # If your existing PC-side driver currently connects to robot_ip=192.168.2.1,
    # set your PC running this dummy to that IP, OR change the driver to point to this PC’s IP.
    sim = DummyEipAdapter(
        bind_ip="0.0.0.0",
        tcp_port=44818,
        udp_port=2222,
        in_words=4,
        out_words=4,
    )
    app = App(sim)
    app.mainloop()
    sim.stop()