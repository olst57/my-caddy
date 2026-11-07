#!/usr/bin/env python3
"""Stand-in for two upstreams at once, on one loopback port.

The e2e overlay keeps the delivery file's `reverse_proxy` leg pointed here, and
the REALITY tunnel's inner request is pointed here too. Serving both from one
process is deliberate: the harness then has exactly one moving part behind the
Caddy listener instead of two, and the marker on each path still tells the
reader which path produced a body.

  * every path except INNER_PATH answers `X-Site: e2e` + `E2E-SITE-MARKER`
  * INNER_PATH answers `E2E-INNER-MARKER`

The inner marker is what E2E-01 checks. It can only come from this process, so
a 200 with that body proves the request traversed the VLESS/Vision tunnel and
was not answered by the decoy site on the Caddy listener.

This file is a copy of tests/coexist/site-backend.py by design: the two suites
must not import from each other, because a change made for one suite would then
silently change the other's fixture.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SITE_MARKER = b"E2E-SITE-MARKER"
INNER_MARKER = b"E2E-INNER-MARKER"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _respond(self):
        inner = self.path.split("?", 1)[0] == INNER_PATH
        body = INNER_MARKER if inner else SITE_MARKER
        self.send_response(200)
        self.send_header("X-Site", "e2e-inner" if inner else "e2e")
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
    port = int(os.environ.get("WEB_PORT", "18080"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


INNER_PATH = os.environ.get("E2E_INNER_PATH", "/inner")


if __name__ == "__main__":
    main()
