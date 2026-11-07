#!/usr/bin/env python3
"""Probe the naive entry point and report what actually came back.

The decisive distinction is data, not the CONNECT status: forwardproxy can
answer `200` before it dials, and the probe-resistance page has its own status.
This client therefore records the response bytes and makes the caller assert
either the decoy marker or the absence of the target marker.
"""

import argparse
import base64
import json
import socket
import ssl
import sys

DECOY_MARKER = b"Hidden Proxy Page"
TARGET_MARKER = b"E2E-NAIVE-TARGET-MARKER"


def read_until_quiet(sock, read_timeout):
    sock.settimeout(read_timeout)
    data = b""
    while True:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
        if len(data) >= 1_048_576:
            break
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--connect-host", default="127.0.0.1")
    ap.add_argument("--connect-port", type=int, default=8443)
    ap.add_argument("--sni", required=True)
    ap.add_argument("--ca", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--auth", choices=("missing", "wrong", "correct"), required=True)
    ap.add_argument("--user")
    ap.add_argument("--password")
    ap.add_argument("--expect", choices=("decoy", "not-target"), required=True)
    ap.add_argument("--timeout", type=float, default=25.0)
    args = ap.parse_args()

    result = {
        "auth": args.auth,
        "connect_status": None,
        "decoy_page": False,
        "target_marker": False,
        "body_bytes": 0,
    }

    raw = b""
    try:
        sock = socket.create_connection(
            (args.connect_host, args.connect_port), args.timeout
        )
        sock.settimeout(args.timeout)
        context = ssl.create_default_context(cafile=args.ca)
        tls = context.wrap_socket(sock, server_hostname=args.sni)
        result["tls_version"] = tls.version()
        lines = [
            f"CONNECT {args.target} HTTP/1.1",
            f"Host: {args.target}",
            "Connection: close",
        ]
        if args.auth == "wrong":
            token = base64.b64encode(b"wrong-e2e-user:wrong-e2e-password").decode()
            lines.append(f"Proxy-Authorization: Basic {token}")
        elif args.auth == "correct":
            if not args.user or not args.password:
                raise SystemExit("--user and --password are required with --auth correct")
            token = base64.b64encode(
                f"{args.user}:{args.password}".encode()
            ).decode()
            lines.append(f"Proxy-Authorization: Basic {token}")
        request = ("\r\n".join(lines) + "\r\n\r\n").encode()
        if args.expect == "not-target":
            # If the ACL is removed, CONNECT succeeds before the lookup and
            # this request reaches the counting target. Sending it makes the
            # target marker and counter independent of the log line.
            request += (
                "GET /private-probe HTTP/1.1\r\n"
                f"Host: {args.target}\r\n"
                "Connection: close\r\n\r\n"
            ).encode()
        tls.sendall(request)
        raw = read_until_quiet(tls, min(args.timeout, 5.0))
    except (OSError, ssl.SSLError) as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(result, indent=2, sort_keys=True))
        return 2

    head, _, body = raw.partition(b"\r\n\r\n")
    status = head.split(b"\r\n", 1)[0].decode("latin-1") if head else ""
    result["connect_status"] = status
    result["decoy_page"] = DECOY_MARKER in raw
    result["target_marker"] = TARGET_MARKER in raw
    result["body_bytes"] = len(body)

    has_status = status.startswith("HTTP/")
    if args.expect == "decoy":
        ok = has_status and result["decoy_page"] and not result["target_marker"]
    else:
        ok = has_status and not result["target_marker"]
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
