#!/usr/bin/env python3
"""Stand-in for the website role's upstream backend.

Every method and every path answers 200 with `X-Site: v4` and the body
`SITE-MARKER-v4`. The header is what the coexistence test reads: it can only
come from this process, so its presence proves the request reached the
reverse_proxy leg rather than being swallowed by forward_proxy.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MARKER = b"SITE-MARKER-v4"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _respond(self):
        body = MARKER
        self.send_response(200)
        self.send_header("X-Site", "v4")
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    do_GET = _respond
    do_HEAD = _respond
    do_POST = _respond
    do_PUT = _respond
    do_DELETE = _respond

    def log_message(self, fmt, *args):
        sys.stderr.write((fmt % args) + "\n")


def main():
    port = int(os.environ.get("WEB_PORT", "8080"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
