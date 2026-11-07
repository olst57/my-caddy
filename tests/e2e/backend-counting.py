#!/usr/bin/env python3
"""A loopback target that records every request it accepts.

The naive checks need a target whose traffic can be counted independently of
the proxy's status line. This backend binds only 127.0.0.1, serves one fixed
marker, and appends one JSON object per accepted request to the file named by
TARGET_COUNT_FILE. The append and fsync happen before the response is written,
so a counter delta of zero cannot be an artefact of buffering.

The counter is deliberately separate from the site backend: the naive checks
and the REALITY checks must not share a mutable fixture.
"""

import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MARKER = b"E2E-NAIVE-TARGET-MARKER"
LOCK = threading.Lock()


def count_file():
    path = os.environ.get("TARGET_COUNT_FILE", "")
    if not path:
        raise SystemExit("TARGET_COUNT_FILE is required")
    return path


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _record(self, body):
        record = {
            "bytes": len(body),
            "path": self.path,
            "headers_seen": sorted({name.lower() for name in self.headers}),
        }
        line = json.dumps(record, sort_keys=True) + "\n"
        with LOCK:
            with open(count_file(), "a", encoding="utf-8") as fh:
                fh.write(line)
                fh.flush()
                os.fsync(fh.fileno())

    def _respond(self):
        body = MARKER
        self._record(body)
        self.send_response(200)
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
    port = int(os.environ.get("TARGET_PORT", "18081"))
    bind = os.environ.get("TARGET_BIND", "127.0.0.1")
    count_file()
    ThreadingHTTPServer((bind, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
