#!/usr/bin/env python3
"""Drive the naive entry point the way a proxy client does, and prove a tunnel.

Three things have to be true for the naive role to be alive, and this fixture
checks all three on one connection:

  1. the TLS handshake to :443 with SNI a.test succeeds against Caddy's own
     certificate (so the request reached the tls wrapper, not layer4);
  2. a CONNECT carrying Proxy-Authorization is answered `200`, not `407` and
     not the probe_resistance decoy page -- the decoy is what a CONNECT to the
     decoy domain itself gets, which is why the target must not be that domain;
  3. bytes actually flow: a TLS handshake to the target is performed *inside*
     the tunnel and a GET comes back 200 with a non-empty body.

A `200` alone is not enough. forwardproxy answers `200 OK` before it dials
(fast-open), so a denied or unreachable target also gets `200` and then a
closed socket. Step 3 is what separates a tunnel from a status line.

Output: one JSON object on stdout. Exit 0 only when every step passed.
"""

import argparse
import json
import socket
import ssl
import sys

DECOY_MARKER = b"Hidden Proxy Page"


def read_headers(sock, limit=65536):
    data = b""
    while b"\r\n\r\n" not in data and len(data) < limit:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--connect-host", default="127.0.0.1")
    ap.add_argument("--connect-port", type=int, default=443)
    ap.add_argument("--sni", default="a.test")
    ap.add_argument("--ca", required=True, help="PEM root of Caddy's internal CA")
    ap.add_argument("--target", default="www.apple.com:443")
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--timeout", type=float, default=25.0)
    args = ap.parse_args()

    result = {
        "connect_status": None,
        "decoy_page": False,
        "tunnel_tls": False,
        "inner_status": None,
        "inner_body_bytes": 0,
    }

    raw = socket.create_connection((args.connect_host, args.connect_port), args.timeout)
    raw.settimeout(args.timeout)

    ctx = ssl.create_default_context(cafile=args.ca)
    outer = ctx.wrap_socket(raw, server_hostname=args.sni)
    result["outer_tls_version"] = outer.version()
    result["outer_cert_san_ok"] = True

    auth = f"{args.user}:{args.password}".encode()
    import base64
    token = base64.b64encode(auth).decode()
    request = (
        f"CONNECT {args.target} HTTP/1.1\r\n"
        f"Host: {args.target}\r\n"
        f"Proxy-Authorization: Basic {token}\r\n"
        "\r\n"
    ).encode()
    outer.sendall(request)
    head = read_headers(outer)
    status_line = head.split(b"\r\n", 1)[0].decode("latin-1")
    result["connect_status"] = status_line
    result["decoy_page"] = DECOY_MARKER in head
    if not status_line.startswith("HTTP/1.1 200"):
        print(json.dumps(result, indent=2))
        return 1
    if result["decoy_page"]:
        print(json.dumps(result, indent=2))
        return 1

    # The tunnel is already an SSL socket, and Python cannot wrap an SSLSocket
    # inside another SSLSocket. Drive the inner handshake through MemoryBIO
    # instead: every byte the inner TLS layer wants to send is written to the
    # outer tunnel, and every byte read back is fed into the inner BIO.
    target_host = args.target.rsplit(":", 1)[0]
    incoming = ssl.MemoryBIO()
    outgoing = ssl.MemoryBIO()
    inner = ssl.create_default_context().wrap_bio(
        incoming, outgoing, server_hostname=target_host
    )

    def flush_outgoing():
        pending = outgoing.read()
        if pending:
            outer.sendall(pending)

    def feed_incoming():
        chunk = outer.recv(65536)
        if not chunk:
            raise EOFError("tunnel closed before inner TLS finished")
        incoming.write(chunk)

    while True:
        try:
            inner.do_handshake()
            break
        except ssl.SSLWantReadError:
            flush_outgoing()
            feed_incoming()
    flush_outgoing()
    result["tunnel_tls"] = True

    request = (
        f"GET / HTTP/1.1\r\nHost: {target_host}\r\nConnection: close\r\n\r\n"
    ).encode()
    while request:
        try:
            request = request[inner.write(request) :]
        except ssl.SSLWantReadError:
            flush_outgoing()
            feed_incoming()
    flush_outgoing()

    body = b""
    while True:
        try:
            chunk = inner.read(65536)
        except ssl.SSLWantReadError:
            flush_outgoing()
            feed_incoming()
            continue
        except (ssl.SSLEOFError, ssl.SSLError, EOFError):
            break
        if not chunk:
            break
        body += chunk
    flush_outgoing()
    head, _, rest = body.partition(b"\r\n\r\n")
    result["inner_status"] = head.split(b"\r\n", 1)[0].decode("latin-1") if head else None
    result["inner_body_bytes"] = len(rest)
    result["inner_head_bytes"] = len(head)

    ok = (
        result["connect_status"].startswith("HTTP/1.1 200")
        and not result["decoy_page"]
        and result["tunnel_tls"]
        and (result["inner_status"] or "").split(" ")[1:2] == ["200"]
        and result["inner_body_bytes"] > 0
    )
    print(json.dumps(result, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
