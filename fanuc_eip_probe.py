# fanuc_eip_probe.py
# Single-file EtherNet/IP probe:
# - TCP: ListServices (optional), RegisterSession
# - CIP: ForwardOpen (SendRRData)
# - UDP: bind + (optional) multicast join + RX
# - UDP: (optional) send basic O->T frames to keep connection alive
#
# NOTE: This is built from the snippets you posted.
# The UDP output frame format may need adjustments for your robot's O->T image expectations.
# The ForwardOpen packet construction matches your known-good pattern.

import argparse
import binascii
import socket
import struct
import time
import threading


# ----------------------------
# Encapsulation helpers
# ----------------------------
def encap_header(cmd: int, session: int, length: int, status: int = 0) -> bytes:
    # Encapsulation header is 24 bytes:
    # 0:2  command
    # 2:4  length
    # 4:8  session handle
    # 8:12 status
    # 12:20 sender context (8 bytes)
    # 20:24 options
    sender_ctx = b"\x00" * 8
    options = 0
    return struct.pack("<HHII8sI", cmd, length, session, status, sender_ctx, options)


def build_list_services() -> bytes:
    # Command 0x0004 ListServices, no session
    payload = b""
    return encap_header(0x0004, 0, len(payload)) + payload


def build_register_session() -> bytes:
    # Command 0x0065 RegisterSession
    # Payload: protocol version (1), options (0)
    payload = struct.pack("<HH", 1, 0)
    return encap_header(0x0065, 0, len(payload)) + payload


def parse_register_session(resp: bytes) -> int:
    if len(resp) < 24:
        raise RuntimeError("RegisterSession response too short")
    cmd, length, session = struct.unpack_from("<HHI", resp, 0)
    if cmd != 0x0065:
        raise RuntimeError(f"Expected RegisterSession reply (0x0065), got 0x{cmd:04X}")
    if session == 0:
        raise RuntimeError("RegisterSession returned session=0")
    return session


def build_send_rr_data(session: int, cip: bytes) -> bytes:
    # SendRRData (0x006F) with CPF:
    # Interface handle (0), timeout (0), item count (2)
    # Item 1: Null address (0x0000, len 0)
    # Item 2: Unconnected Data (0x00B2, len CIP)
    rr = struct.pack("<IHH", 0, 0, 2)
    rr += struct.pack("<HH", 0x0000, 0)
    rr += struct.pack("<HH", 0x00B2, len(cip)) + cip
    return encap_header(0x006F, session, len(rr)) + rr


# ----------------------------
# ForwardOpen (built from your snippet)
# ----------------------------
def build_forward_open_cip(slot: int, in_words: int, out_words: int, t2o_multicast: bool) -> bytes:
    # Your "known-good pattern" header:
    cip = b"\x54\x02\x20\x06\x24\x01" + b"\x05\x99"

    # 32-bit values you had hard-coded:
    cip += struct.pack("<I", 0x2A365DAE)  # ?
    cip += struct.pack("<I", 0)           # ?
    cip += struct.pack("<H", 0x1234)      # conn serial (example)
    cip += struct.pack("<H", 0x0164)      # vendor?
    cip += struct.pack("<I", 0x12345678)  # originator serial?
    cip += b"\x00\x00\x00\x00"            # timeout multiplier + reserved?

    # Sizes exactly as your code
    in_size = (in_words * 2) + 2
    out_size = (out_words * 2) + 6

    CONN_TYPE_MC = 0b01 << 13   # 0x2000
    CONN_TYPE_P2P = 0b10 << 13  # 0x4000
    CONN_FIXED = 0

    in_param = (CONN_TYPE_MC if t2o_multicast else CONN_TYPE_P2P) | CONN_FIXED | in_size
    out_param = CONN_TYPE_P2P | CONN_FIXED | out_size

    # RPIs and params (your exact sequence)
    cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", out_param)
    cip += struct.pack("<I", 0x00004E20) + struct.pack("<H", in_param) + b"\x01"

    # Path (your exact path builder)
    path = bytearray(b"\x34\x04")
    path += struct.pack("<H", 0x0164)
    path += struct.pack("<H", 0x000C) + struct.pack("<H", 0x0004)
    path += b"\x03\x01\x20\x04\x24\x64"
    ot = 150 + slot
    to = 100 + slot
    path += struct.pack("BB", 0x2C, ot) + struct.pack("BB", 0x2C, to)

    cip += struct.pack("B", len(path) // 2) + path
    return cip, in_param, out_param


def parse_forward_open_response(resp: bytes) -> dict:
    if len(resp) < 48:
        raise RuntimeError(f"FO response too short: {len(resp)} bytes")

    cmd, length = struct.unpack_from("<HH", resp, 0)
    if cmd != 0x006F:
        raise RuntimeError(f"Expected SendRRData response (0x006F), got 0x{cmd:04X}")

    # CPF items begin at offset 30 in your earlier parser
    item_count = struct.unpack_from("<H", resp, 30)[0]
    off = 32

    socket_items = []
    for _ in range(item_count):
        itype, ilen = struct.unpack_from("<HH", resp, off)
        data = resp[off + 4: off + 4 + ilen]
        socket_items.append((itype, ilen, data))
        off += 4 + ilen

    # Find Unconnected Data item marker 0x00B2
    uci = resp.find(b"\xB2\x00")
    if uci < 0:
        raise RuntimeError("Missing Unconnected-Data item (0x00B2)")

    cip_start = uci + 4
    # Many replies have: service, reserved?, general status, addl status size
    # Your earlier code assumed service/status/addn packed as BBB.
    service = resp[cip_start + 0]
    status = resp[cip_start + 1]
    addn = resp[cip_start + 2]

    if service != 0xD4 or status != 0x00:
        raise RuntimeError(f"ForwardOpen error: svc=0x{service:02X} status=0x{status:02X} addn={addn}")

    # Connection IDs typically start after: 4 bytes (svc/stat/addn/?) + addn*2
    conn_off = cip_start + 4 + (addn * 2)
    if conn_off + 8 > len(resp):
        raise RuntimeError("FO conn_id area out of range")

    # Return both IDs (order can matter by device)
    conn_id_0 = struct.unpack_from("<I", resp, conn_off + 0)[0]
    conn_id_1 = struct.unpack_from("<I", resp, conn_off + 4)[0]

    # Try extract multicast ip/port from Socket Address Items
    # Commonly 0x8001 (T->O) and 0x8002 (O->T), formats vary.
    mcast_ip = None
    mcast_port = None
    for itype, ilen, data in socket_items:
        if itype == 0x8001 and ilen >= 16:
            # Many implementations: family(2), port(2), addr(4), zero(8) => total 16
            try:
                port = struct.unpack_from(">H", data, 2)[0]  # network order
                addr = socket.inet_ntoa(data[4:8])
                mcast_ip = addr
                mcast_port = port
            except Exception:
                pass

    return {
        "conn_id_0": conn_id_0,
        "conn_id_1": conn_id_1,
        "mcast_ip": mcast_ip,
        "mcast_port": mcast_port,
        "socket_items": socket_items,
    }


# ----------------------------
# UDP I/O (probe-level)
# ----------------------------
def udp_listen(sock: socket.socket, stop_evt: threading.Event):
    while not stop_evt.is_set():
        try:
            data, addr = sock.recvfrom(8192)
            print(f"[UDP RX] from={addr} len={len(data)} head={binascii.hexlify(data[:24]).decode()}", flush=True)
        except socket.timeout:
            continue
        except Exception as e:
            print(f"[UDP RX] exception: {e!r}", flush=True)
            break


def build_udp_o2t(conn_id: int, seq: int, out_words: list[int]) -> bytes:
    # Common implicit I/O UDP frame used by many devices:
    #   4 bytes: connection ID (LE)
    #   4 bytes: sequence (LE)
    #   N bytes: output data
    #
    # Your app likely has additional run/idle + header words.
    # This is a minimal probe frame.
    payload = struct.pack("<II", conn_id & 0xFFFFFFFF, seq & 0xFFFFFFFF)
    for w in out_words:
        payload += struct.pack("<H", w & 0xFFFF)
    return payload


def udp_send_loop(sock: socket.socket, dst_ip: str, dst_port: int, conn_id: int, out_words: list[int], stop_evt: threading.Event):
    seq = 1
    interval = 0.01
    while not stop_evt.is_set():
        try:
            pkt = build_udp_o2t(conn_id, seq, out_words)
            sock.sendto(pkt, (dst_ip, dst_port))
            seq = (seq + 1) & 0xFFFFFFFF
        except Exception as e:
            print(f"[UDP TX] exception: {e!r}", flush=True)
        time.sleep(interval)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip", default="192.168.2.1")
    ap.add_argument("--port", type=int, default=44818)
    ap.add_argument("--slot", type=int, default=1)
    ap.add_argument("--in_words", type=int, default=16)
    ap.add_argument("--out_words", type=int, default=16)
    ap.add_argument("--t2o", choices=["multicast", "unicast"], default="multicast")
    ap.add_argument("--udp_bind", type=int, default=2222, help="Local UDP bind port (multicast usually needs 2222)")
    ap.add_argument("--send", action="store_true", help="Send basic O->T frames (probe)")
    args = ap.parse_args()

    t2o_multicast = (args.t2o == "multicast")

    # TCP connect
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.settimeout(5.0)
    print(f"[TCP] connect {args.ip}:{args.port}", flush=True)
    tcp.connect((args.ip, args.port))

    # ListServices (optional)
    try:
        tcp.sendall(build_list_services())
        _ = tcp.recv(1024)
        print("[EIP] ListServices OK (ignored)", flush=True)
    except Exception as e:
        print(f"[EIP] ListServices failed (ignored): {e!r}", flush=True)

    # RegisterSession
    tcp.sendall(build_register_session())
    rs = tcp.recv(1024)
    session = parse_register_session(rs)
    print(f"[EIP] session=0x{session:08X}", flush=True)

    # ForwardOpen
    cip, in_param, out_param = build_forward_open_cip(args.slot, args.in_words, args.out_words, t2o_multicast)
    fo = build_send_rr_data(session, cip)
    print(f"[FO] req hex={binascii.hexlify(fo).decode()}", flush=True)
    tcp.sendall(fo)
    resp = tcp.recv(4096)
    print(f"[FO] resp len={len(resp)} head={binascii.hexlify(resp[:64]).decode()}", flush=True)

    info = parse_forward_open_response(resp)
    print(f"[FO] conn_id_0=0x{info['conn_id_0']:08X} conn_id_1=0x{info['conn_id_1']:08X}", flush=True)
    print(f"[FO] in_param=0x{in_param:04X} out_param=0x{out_param:04X} t2o={args.t2o}", flush=True)

    if info["mcast_ip"] and info["mcast_port"]:
        print(f"[FO] socket_item T->O ip={info['mcast_ip']} port={info['mcast_port']}", flush=True)
    else:
        print("[FO] no multicast socket address parsed", flush=True)

    # UDP setup
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.settimeout(0.5)
    udp.bind(("", args.udp_bind))
    print(f"[UDP] bound local *:{udp.getsockname()[1]}", flush=True)

    # Join multicast if requested and mcast_ip present
    if t2o_multicast and info["mcast_ip"]:
        # best-effort interface selection
        local_ip = socket.gethostbyname(socket.gethostname())
        try:
            mreq = struct.pack("4s4s", socket.inet_aton(info["mcast_ip"]), socket.inet_aton(local_ip))
            udp.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            print(f"[UDP] joined multicast {info['mcast_ip']} on if={local_ip}", flush=True)
        except Exception as e:
            print(f"[UDP] multicast join failed: {e!r}", flush=True)

    stop_evt = threading.Event()
    rx_t = threading.Thread(target=udp_listen, args=(udp, stop_evt), daemon=True)
    rx_t.start()

    # TX: destination is typically target UDP 2222
    if args.send:
        # You may need to choose which conn_id is O->T for your robot.
        # Start by trying conn_id_0 (matches your current code behavior).
        o2t_conn_id = info["conn_id_0"]
        out_words = [0] * args.out_words
        tx_t = threading.Thread(
            target=udp_send_loop,
            args=(udp, args.ip, 2222, o2t_conn_id, out_words, stop_evt),
            daemon=True,
        )
        tx_t.start()
        print(f"[UDP] TX enabled -> {args.ip}:2222 using conn_id=0x{o2t_conn_id:08X}", flush=True)

    print("[RUN] Ctrl+C to stop", flush=True)
    try:
        while True:
            time.sleep(0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop_evt.set()
        try:
            udp.close()
        except Exception:
            pass
        try:
            tcp.close()
        except Exception:
            pass
        print("[EXIT]", flush=True)


if __name__ == "__main__":
    main()
