#!/usr/bin/env python3
"""Stand-in for the xray REALITY inbound on the layer4 upstream port.

It records, byte for byte, what Caddy's layer4 wrapper forwards on each
connection it receives:

  * the 16-byte PROXY v2 header (signature, version/command, family/protocol,
    address block) that `proxy_protocol v2` writes, and
  * the untouched TLS ClientHello that follows it, which carries the SNI.

It is deliberately NOT a TLS server. A client that expects Caddy to terminate
the handshake therefore fails, and that failure is the proof Caddy did not
decrypt the connection: if the layer4 matcher had missed, Caddy's own TLS stack
would have completed the handshake with a certificate for the SNI.

Each accepted connection is appended to $UPSTREAM_OUT as one JSON object per
line, flushed immediately, so the caller can count connections while the stub
is still running. That count is what makes the "unknown SNI does not reach the
upstream" control measurable rather than assumed.

Env: UPSTREAM_PORT (19098), UPSTREAM_OUT (upstream.jsonl), REALITY_SNI (b.test),
     UPSTREAM_WINDOW seconds before the process gives up (120).
"""

import json
import os
import signal
import socket
import sys
import time

SIGNATURE = bytes.fromhex("0d0a0d0a000d0a515549540a")
HEADER_FIXED = 16


def read_first_stream(conn, deadline):
    """Read the PROXY header and the first bytes of its payload."""
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
        if len(data) >= HEADER_FIXED:
            addr_len = int.from_bytes(data[14:16], "big")
            if len(data) >= HEADER_FIXED + addr_len + 3:
                break
    return data


def describe(data, sni):
    result = {
        "total_bytes": len(data),
        "proxy_signature": data[:12] == SIGNATURE,
        "version_command": None,
        "family_protocol": None,
        "address_length": None,
        "payload_prefix_hex": "",
        "client_hello": False,
        "sni_present": False,
    }
    if len(data) >= HEADER_FIXED:
        addr_len = int.from_bytes(data[14:16], "big")
        payload = data[HEADER_FIXED + addr_len:]
        result.update({
            "version_command": hex(data[12]),
            "family_protocol": hex(data[13]),
            "address_length": addr_len,
            "payload_prefix_hex": payload[:16].hex(" "),
            "client_hello": payload[:3] == b"\x16\x03\x01",
            "sni_present": sni.encode() in payload,
        })
    return result


def main():
    port = int(os.environ.get("UPSTREAM_PORT", "19098"))
    out = os.environ.get("UPSTREAM_OUT", "upstream.jsonl")
    sni = os.environ.get("REALITY_SNI", "b.test")
    window = float(os.environ.get("UPSTREAM_WINDOW", "120"))

    stopping = []

    def stop(_signum, _frame):
        stopping.append(1)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(8)
    srv.settimeout(0.5)
    print("ready", flush=True)

    deadline = time.time() + window
    with open(out, "a", encoding="utf-8") as fh:
        while not stopping and time.time() < deadline:
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
            fh.write(json.dumps(describe(data, sni), sort_keys=True) + "\n")
            fh.flush()
    srv.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
