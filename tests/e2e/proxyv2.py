#!/usr/bin/env python3
"""Stand-in for the xray REALITY inbound that records PROXY v2 by field.

The coexistence stub answers "did a PROXY header arrive". This one answers
"what exactly is in it", because E2E-03 is a structural assertion:

  signature (12 bytes) | version/command (1) | family/protocol (1) |
  address length (2)   | address block (length) | payload

Each accepted connection appends one JSON object to --out (default stdout), so
the caller can assert field by field instead of counting bytes.

The payload is NOT parsed as TLS. The point of the record is that the bytes
after the header are an untouched ClientHello: `client_hello` and `sni_present`
are computed from the raw stream.
"""

import argparse
import json
import socket
import sys
import time

SIGNATURE = bytes.fromhex("0d0a0d0a000d0a515549540a")
FIXED = 16


def read_first_stream(conn, deadline):
    data = b""
    conn.settimeout(0.5)
    while time.time() < deadline:
        try:
            chunk = conn.recv(8192)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        data += chunk
        if len(data) >= FIXED:
            addr_len = int.from_bytes(data[14:16], "big")
            if len(data) >= FIXED + addr_len + 3:
                break
    return data


def describe(data, sni):
    result = {
        "total_bytes": len(data),
        "signature_hex": data[:12].hex(" ") if len(data) >= 12 else "",
        "signature_ok": data[:12] == SIGNATURE,
        "version_command": None,
        "family_protocol": None,
        "address_length": None,
        "source": None,
        "destination": None,
        "payload_prefix_hex": "",
        "client_hello": False,
        "sni_present": False,
    }
    if len(data) < FIXED:
        return result
    addr_len = int.from_bytes(data[14:16], "big")
    payload = data[FIXED + addr_len :]
    result.update(
        {
            "version_command": hex(data[12]),
            "family_protocol": hex(data[13]),
            "address_length": addr_len,
            "payload_prefix_hex": payload[:16].hex(" "),
            "client_hello": payload[:3] == b"\x16\x03\x01",
            "sni_present": sni.encode() in payload,
        }
    )
    # Family 0x11 is TCP over IPv4: 4+4 addresses and 2+2 ports.
    if data[13] == 0x11 and addr_len >= 12 and len(data) >= FIXED + 12:
        block = data[FIXED : FIXED + 12]
        result["source"] = "%s:%d" % (
            socket.inet_ntoa(block[0:4]),
            int.from_bytes(block[8:10], "big"),
        )
        result["destination"] = "%s:%d" % (
            socket.inet_ntoa(block[4:8]),
            int.from_bytes(block[10:12], "big"),
        )
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=19099)
    ap.add_argument("--sni", required=True)
    ap.add_argument("--out", default="-", help="file to append JSON lines to")
    ap.add_argument("--window", type=float, default=120.0)
    ap.add_argument(
        "--connections",
        type=int,
        default=1,
        help="how many connections to record before exiting",
    )
    args = ap.parse_args()

    sink = sys.stdout if args.out == "-" else open(args.out, "a", encoding="utf-8")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(8)
    srv.settimeout(0.5)
    print("ready", flush=True)

    recorded = 0
    deadline = time.time() + args.window
    while recorded < args.connections and time.time() < deadline:
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        data = read_first_stream(conn, time.time() + 10)
        try:
            conn.close()
        except OSError:
            pass
        sink.write(json.dumps(describe(data, args.sni), sort_keys=True) + "\n")
        sink.flush()
        recorded += 1
    srv.close()
    if sink is not sys.stdout:
        sink.close()
    return 0 if recorded >= args.connections else 1


if __name__ == "__main__":
    sys.exit(main())
