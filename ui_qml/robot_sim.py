"""
robot_sim.py  -  Simulates a FANUC robot PLC for testing the HMI.

Acts as a full EtherNet/IP endpoint:
  1. TCP server on port 44818 - handles RegisterSession + ForwardOpen
  2. UDP on port 2222 - receives HMI output packets, sends back input packets

The HMI connects to this simulator exactly like a real robot.

Setup:
  1. Set robot IP to 127.0.0.1 in the HMI config (Robot Comm screen -> CONFIG)
  2. Start this simulator:  python robot_sim.py
  3. Start the HMI:         python main.py
  4. The HMI will auto-connect and you'll see "CYCLIC" state

CLI Commands:
    running <robot>         Toggle RUNNING bit (robot 1-4)
    fault <robot>           Toggle FAULT bit
    tpen <robot>            Toggle TPEN bit
    set <robot> w<N> <hex>  Set input word N to hex value (e.g. set 1 w0 0x0004)
    bit <robot> w<N> <bit> on|off   Set specific bit (1-based)
    show                    Show all robot states + HMI output bits
    help                    Show this help
    quit                    Exit
"""
import argparse
import socket
import struct
import threading
import time
import sys
import binascii


# Status bit positions (1-based, matching SideBar.qml)
BIT_ST_RUNNING = 3
BIT_ST_FAULT   = 6
BIT_ST_TPEN    = 8

# Friendly names for known bits (1-based)
STATUS_BIT_NAMES = {
    1: "IMSTP_FB",
    2: "ENABLED_FB",
    3: "RUNNING",
    4: "PAUSED",
    5: "RESET_FB",
    6: "FAULT",
    7: "ALARM",
    8: "TPEN",
    9: "REMOTE",
    10: "AUTO_FB",
    11: "MANUAL_FB",
}

CMD_BIT_NAMES = {
    1: "IMSTP",
    2: "SPARE2",
    3: "SPARE3",
    4: "SPARE4",
    5: "RESET",
    6: "START",
    7: "STOP",
    8: "ENABLE",
    9: "SPARE9",
    10: "AUTO",
    11: "MANUAL",
}


class RobotSim:
    def __init__(self, num_robots=4, in_words=16, out_words=16,
                 tcp_port=44818, udp_port=2222):
        self.num_robots = num_robots
        self.in_words = in_words
        self.out_words = out_words
        self.tcp_port = tcp_port
        self.udp_port = udp_port

        # Input words: what the "robot" sends TO the HMI (ROBOT -> HMI)
        self._inputs = [[0] * in_words for _ in range(num_robots)]
        # Output words: what the HMI sends TO the "robot" (HMI -> ROBOT) - captured
        self._outputs = [[0] * out_words for _ in range(num_robots)]
        self._lock = threading.Lock()

        # Connection tracking
        self._connections = {}       # conn_id -> robot_index
        self._conn_lock = threading.Lock()
        self._next_robot = 0         # next robot index to assign

        # T->O conn IDs we generate (one per ForwardOpen)
        self._t2o_ids = {}           # robot_index -> t2o_conn_id
        self._o2t_ids = {}           # robot_index -> o2t_conn_id (from HMI)

        # Sequence counters per robot
        self._seq = [1] * num_robots

        # Track HMI's UDP source address per robot
        self._hmi_addr = {}

        self._running = True
        self._udp_sock = None
        self._tcp_sock = None

    def start(self):
        """Start TCP + UDP servers."""
        # TCP server for EtherNet/IP session + ForwardOpen
        self._tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._tcp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._tcp_sock.bind(("0.0.0.0", self.tcp_port))
        self._tcp_sock.listen(8)
        self._tcp_sock.settimeout(1.0)
        print(f"[SIM] TCP listening on *:{self.tcp_port}")

        # UDP socket for I/O exchange
        self._udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._udp_sock.settimeout(0.5)
        self._udp_sock.bind(("0.0.0.0", self.udp_port))
        print(f"[SIM] UDP listening on *:{self.udp_port}")

        threading.Thread(target=self._tcp_accept_loop, daemon=True).start()
        threading.Thread(target=self._udp_rx_loop, daemon=True).start()
        threading.Thread(target=self._udp_tx_loop, daemon=True).start()

    def stop(self):
        self._running = False
        if self._udp_sock:
            try: self._udp_sock.close()
            except: pass
        if self._tcp_sock:
            try: self._tcp_sock.close()
            except: pass

    # ---- TCP: EtherNet/IP session + ForwardOpen ----

    def _tcp_accept_loop(self):
        while self._running:
            try:
                conn, addr = self._tcp_sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            print(f"[SIM] TCP connection from {addr}")
            threading.Thread(target=self._handle_tcp_client, args=(conn, addr), daemon=True).start()

    def _handle_tcp_client(self, conn, addr):
        """Handle one HMI TCP connection (ListServices, RegisterSession, ForwardOpen)."""
        conn.settimeout(10.0)
        session_id = 0x00010001  # fake session

        try:
            while self._running:
                # Read encapsulation header (24 bytes)
                hdr = self._recv_exact(conn, 24)
                if hdr is None:
                    break

                cmd = struct.unpack_from("<H", hdr, 0)[0]
                length = struct.unpack_from("<H", hdr, 2)[0]

                # Read payload
                payload = b""
                if length > 0:
                    payload = self._recv_exact(conn, length)
                    if payload is None:
                        break

                if cmd == 0x0004:
                    # ListServices
                    print(f"[SIM] <- ListServices")
                    resp = self._build_list_services_reply()
                    conn.sendall(resp)

                elif cmd == 0x0065:
                    # RegisterSession
                    print(f"[SIM] <- RegisterSession")
                    resp = self._build_register_session_reply(session_id)
                    conn.sendall(resp)

                elif cmd == 0x006F:
                    # SendRRData (contains ForwardOpen)
                    print(f"[SIM] <- SendRRData (ForwardOpen)")
                    robot_i, o2t_conn_id, resp = self._handle_forward_open(payload, session_id)
                    if resp:
                        conn.sendall(resp)
                        print(f"[SIM]    Assigned to Robot {robot_i + 1}, o2t=0x{o2t_conn_id:08X}")
                    else:
                        print(f"[SIM]    ForwardOpen parse failed")

                else:
                    print(f"[SIM] <- Unknown EIP cmd=0x{cmd:04X} len={length}")

        except Exception as e:
            print(f"[SIM] TCP handler error: {e}")
        finally:
            conn.close()
            print(f"[SIM] TCP connection closed from {addr}")

    def _recv_exact(self, sock, n):
        buf = b""
        while len(buf) < n:
            try:
                chunk = sock.recv(n - len(buf))
            except (socket.timeout, OSError):
                return None
            if not chunk:
                return None
            buf += chunk
        return buf

    def _build_list_services_reply(self):
        # Minimal ListServices reply
        item = struct.pack("<HH", 0x0100, 20)  # Communications service
        item += struct.pack("<HH", 1, 0x0120)  # version, capability
        name = b"Communications\x00\x00"
        item += name[:16]

        payload = struct.pack("<HH", 1, 0) + item  # item count=1
        return self._encap_header(0x0004, 0, len(payload)) + payload

    def _build_register_session_reply(self, session_id):
        payload = struct.pack("<HH", 1, 0)  # protocol version, options
        return self._encap_header(0x0065, session_id, len(payload)) + payload

    def _handle_forward_open(self, payload, session_id):
        """Parse ForwardOpen from payload, assign robot index, return response."""
        # Assign next robot
        with self._conn_lock:
            robot_i = self._next_robot
            if robot_i >= self.num_robots:
                robot_i = 0  # wrap around
            self._next_robot = robot_i + 1

        # Generate connection IDs
        o2t_conn_id = 0xAA000000 | (robot_i << 16) | (int(time.time()) & 0xFFFF)
        t2o_conn_id = 0xBB000000 | (robot_i << 16) | (int(time.time()) & 0xFFFF)

        with self._conn_lock:
            self._connections[o2t_conn_id] = robot_i
            self._t2o_ids[robot_i] = t2o_conn_id
            self._o2t_ids[robot_i] = o2t_conn_id

        print(f"[SIM]    o2t=0x{o2t_conn_id:08X} t2o=0x{t2o_conn_id:08X} -> Robot {robot_i + 1}")

        # Build ForwardOpen reply
        # CIP reply: service=0xD4, status=0, addl_status_size=0
        cip_reply = struct.pack("<BBBx", 0xD4, 0x00, 0x00)
        # O->T conn id, T->O conn id
        cip_reply += struct.pack("<II", o2t_conn_id, t2o_conn_id)
        # Connection serial, vendor, originator serial
        cip_reply += struct.pack("<HHI", 0x1234, 0x0164, 0x12345678)
        # O->T API, T->O API
        cip_reply += struct.pack("<II", 0x00004E20, 0x00004E20)
        # Application reply size (0)
        cip_reply += struct.pack("<Bx", 0)

        # Wrap in SendRRData
        rr = struct.pack("<IHH", 0, 0, 2)  # interface, timeout, item_count
        rr += struct.pack("<HH", 0x0000, 0)  # null addr item
        rr += struct.pack("<HH", 0x00B2, len(cip_reply))  # unconnected data item
        rr += cip_reply

        return robot_i, o2t_conn_id, self._encap_header(0x006F, session_id, len(rr)) + rr

    def _encap_header(self, cmd, session, length):
        return struct.pack("<HHIIQI", cmd, length, session, 0, 0, 0)

    # ---- UDP: Cyclic I/O ----

    def _udp_rx_loop(self):
        """Receive HMI -> Robot output packets."""
        while self._running:
            try:
                data, addr = self._udp_sock.recvfrom(8192)
            except socket.timeout:
                continue
            except OSError:
                break

            if len(data) < 16:
                continue

            # Extract conn_id at offset 6
            try:
                conn_id = struct.unpack_from("<I", data, 6)[0]
            except struct.error:
                continue

            with self._conn_lock:
                robot_i = self._connections.get(conn_id)

            if robot_i is None:
                continue

            # Store HMI address for responses
            self._hmi_addr[robot_i] = addr

            # Parse output words from B1 data item
            b1_idx = data.find(b"\xB1\x00")
            if b1_idx < 0:
                continue
            if len(data) < b1_idx + 4:
                continue

            payload_len = struct.unpack_from("<H", data, b1_idx + 2)[0]
            payload = data[b1_idx + 4:b1_idx + 4 + payload_len]

            if len(payload) < 6:
                continue

            # Skip seq(2) + run_idle(4), then output words
            word_data = payload[6:]
            wc = len(word_data) // 2
            if wc > 0:
                words = list(struct.unpack_from("<" + "H" * wc, word_data, 0))
                with self._lock:
                    for j in range(min(wc, self.out_words)):
                        self._outputs[robot_i][j] = words[j]

    def _udp_tx_loop(self):
        """Send Robot -> HMI input packets at ~125Hz."""
        while self._running:
            for robot_i in range(self.num_robots):
                addr = self._hmi_addr.get(robot_i)
                if addr is None:
                    continue

                t2o_id = self._t2o_ids.get(robot_i)
                if t2o_id is None:
                    continue

                pkt = self._build_input_packet(robot_i, t2o_id)
                try:
                    self._udp_sock.sendto(pkt, addr)
                except Exception:
                    pass

            time.sleep(0.008)

    def _build_input_packet(self, robot_i, conn_id):
        """Build a T->O (robot -> HMI) UDP packet."""
        seq = self._seq[robot_i]
        self._seq[robot_i] = (seq + 1) & 0xFFFFFFFF

        header = struct.pack("<H", 2)  # item count
        header += struct.pack("<HHI", 0x8002, 8, conn_id)
        header += struct.pack("<I", seq)

        with self._lock:
            words = list(self._inputs[robot_i][:self.in_words])

        payload = struct.pack("<H", seq & 0xFFFF)
        payload += struct.pack("<" + "H" * len(words), *words)

        header += struct.pack("<HH", 0x00B1, len(payload))
        header += payload
        return header

    # ---- State manipulation ----

    def set_bit(self, robot_i, word_i, bit_1based, on):
        if robot_i < 0 or robot_i >= self.num_robots:
            return
        bit_0 = bit_1based - 1
        with self._lock:
            w = self._inputs[robot_i][word_i]
            if on:
                w |= (1 << bit_0)
            else:
                w &= ~(1 << bit_0)
            self._inputs[robot_i][word_i] = w & 0xFFFF

    def get_bit(self, robot_i, word_i, bit_1based):
        bit_0 = bit_1based - 1
        with self._lock:
            return (self._inputs[robot_i][word_i] >> bit_0) & 1

    def toggle_bit(self, robot_i, word_i, bit_1based):
        current = self.get_bit(robot_i, word_i, bit_1based)
        self.set_bit(robot_i, word_i, bit_1based, not current)
        return not current

    def set_word(self, robot_i, word_i, value):
        if robot_i < 0 or robot_i >= self.num_robots:
            return
        with self._lock:
            self._inputs[robot_i][word_i] = value & 0xFFFF

    def get_state_str(self):
        lines = []
        for ri in range(self.num_robots):
            connected = ri in self._hmi_addr
            status = "CONNECTED" if connected else "waiting..."

            with self._lock:
                in_w0 = self._inputs[ri][0]
                out_w0 = self._outputs[ri][0]

            lines.append(f"\n  Robot {ri + 1} [{status}]")
            lines.append(f"    ROBOT -> HMI (Input word 0): 0x{in_w0:04X}")
            for bit_1, name in sorted(STATUS_BIT_NAMES.items()):
                val = (in_w0 >> (bit_1 - 1)) & 1
                marker = "\033[92mON \033[0m" if val else "\033[90moff\033[0m"
                lines.append(f"      bit {bit_1:2d} ({name:12s}): {marker}")

            lines.append(f"    HMI -> ROBOT (Output word 0): 0x{out_w0:04X}")
            for bit_1, name in sorted(CMD_BIT_NAMES.items()):
                val = (out_w0 >> (bit_1 - 1)) & 1
                marker = "\033[92mON \033[0m" if val else "\033[90moff\033[0m"
                lines.append(f"      bit {bit_1:2d} ({name:12s}): {marker}")

        return "\n".join(lines)


def print_help():
    print("""
Commands:
  running <robot>         Toggle RUNNING bit (robot 1-4)
  fault <robot>           Toggle FAULT bit
  tpen <robot>            Toggle TPEN bit
  set <robot> w<N> <hex>  Set input word N to hex value
                            e.g.  set 1 w0 0x0004
  bit <robot> w<N> <bit> on|off
                          Set specific bit (1-based) on|off
                            e.g.  bit 1 w0 3 on
  show                    Show all robot states
  help                    Show this help
  quit / exit             Exit simulator
""")


def main():
    parser = argparse.ArgumentParser(description="Robot PLC Simulator for HMI testing")
    parser.add_argument("--robots", type=int, default=1,
                        help="Number of robots to simulate (default: 1)")
    parser.add_argument("--tcp-port", type=int, default=44818,
                        help="TCP port for EtherNet/IP (default: 44818)")
    parser.add_argument("--udp-port", type=int, default=2222,
                        help="UDP port for I/O (default: 2222)")
    args = parser.parse_args()

    num_robots = max(1, min(4, args.robots))
    sim = RobotSim(num_robots=num_robots, tcp_port=args.tcp_port, udp_port=args.udp_port)

    try:
        sim.start()
    except OSError as e:
        print(f"\n[SIM] Failed to start: {e}")
        print("[SIM] Make sure nothing else is using ports 44818/2222.")
        print("[SIM] Start this simulator BEFORE the HMI app.")
        sys.exit(1)

    print(f"\n[SIM] Simulating {num_robots} robot(s)")
    print("[SIM] Configure HMI robot IP to 127.0.0.1 (Robot Comm -> CONFIG)")
    print("[SIM] Then start the HMI:  python main.py\n")
    print_help()

    try:
        while True:
            try:
                line = input("sim> ").strip()
            except EOFError:
                break

            if not line:
                continue

            parts = line.split()
            cmd = parts[0].lower()

            try:
                if cmd in ("quit", "exit", "q"):
                    break

                elif cmd == "help":
                    print_help()

                elif cmd == "show":
                    print(sim.get_state_str())

                elif cmd == "running" and len(parts) >= 2:
                    ri = int(parts[1]) - 1
                    val = sim.toggle_bit(ri, 0, BIT_ST_RUNNING)
                    print(f"  Robot {ri+1} RUNNING = {'ON' if val else 'OFF'}")

                elif cmd == "fault" and len(parts) >= 2:
                    ri = int(parts[1]) - 1
                    val = sim.toggle_bit(ri, 0, BIT_ST_FAULT)
                    print(f"  Robot {ri+1} FAULT = {'ON' if val else 'OFF'}")

                elif cmd == "tpen" and len(parts) >= 2:
                    ri = int(parts[1]) - 1
                    val = sim.toggle_bit(ri, 0, BIT_ST_TPEN)
                    print(f"  Robot {ri+1} TPEN = {'ON' if val else 'OFF'}")

                elif cmd == "set" and len(parts) >= 4:
                    ri = int(parts[1]) - 1
                    wi = int(parts[2].lstrip("wW"))
                    val = int(parts[3], 0)
                    sim.set_word(ri, wi, val)
                    print(f"  Robot {ri+1} input word {wi} = 0x{val & 0xFFFF:04X}")

                elif cmd == "bit" and len(parts) >= 5:
                    ri = int(parts[1]) - 1
                    wi = int(parts[2].lstrip("wW"))
                    bit = int(parts[3])
                    on = parts[4].lower() in ("on", "1", "true")
                    sim.set_bit(ri, wi, bit, on)
                    print(f"  Robot {ri+1} word {wi} bit {bit} = {'ON' if on else 'OFF'}")

                else:
                    print(f"  Unknown command: {line}")
                    print("  Type 'help' for commands")

            except (ValueError, IndexError) as e:
                print(f"  Error: {e}")
                print("  Type 'help' for usage")

    except KeyboardInterrupt:
        pass
    finally:
        print("\n[SIM] Shutting down...")
        sim.stop()


if __name__ == "__main__":
    main()
