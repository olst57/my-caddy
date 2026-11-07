#!/usr/bin/env python3
"""Measure the certificate a TLS client is shown, twice, and compare.

`fetch` opens one TLS connection and writes a JSON record: SAN set, issuer,
validity window, leaf sha256, negotiated version and ALPN.

`compare` takes one probe record and one or more expected records:

  * the probe MUST be TLSv1.3 and MUST have negotiated ALPN h2;
  * SAN set, issuer and validity window MUST equal every expected record;
  * the leaf sha256 MUST match at least one expected record.

The last rule exists because a large destination can rotate between edge
certificates within seconds. Insisting on one specific fingerprint would make
the item flaky for a reason unrelated to the code under test; the other fields
still have to agree with every fetch, and a fingerprint that matches none of
them is still a failure.

Fields are read with `openssl x509` rather than a Python ASN.1 library: the
harness already requires openssl, and adding a dependency to the runner is a
larger cost than one subprocess.
"""

import argparse
import json
import os
import socket
import ssl
import subprocess
import sys
import tempfile


def _openssl_fields(pem, path):
    base = ["openssl", "x509", "-in", path, "-noout"]
    text = subprocess.run(
        base + ["-fingerprint", "-sha256", "-issuer", "-dates", "-ext", "subjectAltName"],
        capture_output=True,
        text=True,
    )
    if text.returncode != 0:
        text = subprocess.run(base + ["-text"], capture_output=True, text=True)
        if text.returncode != 0:
            raise RuntimeError("openssl x509 failed: %s" % text.stderr.strip())
    body = text.stdout

    fields = {"san": [], "issuer": None, "not_before": None, "not_after": None, "sha256": None}
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith(("issuer=", "issuer: ")):
            fields["issuer"] = stripped.split("=", 1)[-1] if "=" in stripped else stripped[7:].strip()
        elif stripped.startswith("notBefore="):
            fields["not_before"] = stripped.split("=", 1)[1].strip()
        elif stripped.startswith("notAfter="):
            fields["not_after"] = stripped.split("=", 1)[1].strip()
        elif "Fingerprint=" in stripped:
            value = stripped.split("Fingerprint=", 1)[1].strip()
            fields["sha256"] = value.replace(":", "").lower()
        elif "DNS:" in stripped:
            for item in stripped.split("DNS:")[1:]:
                name = item.split(",")[0].strip()
                if name:
                    fields["san"].append(name)
    if fields["san"]:
        fields["san"] = sorted(set(fields["san"]))
    return fields


def fetch(connect, sni, alpn, timeout):
    host, _, port = connect.rpartition(":")
    if not host or not port.isdigit():
        raise SystemExit("FATAL: --connect must be host:port, got %r" % connect)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    if alpn:
        ctx.set_alpn_protocols([alpn])
    raw = socket.create_connection((host, int(port)), timeout)
    raw.settimeout(timeout)
    tls = ctx.wrap_socket(raw, server_hostname=sni)
    der = tls.getpeercert(binary_form=True)
    record = {
        "connect": connect,
        "sni": sni,
        "tls_version": tls.version(),
        "alpn": tls.selected_alpn_protocol(),
    }
    tls.close()
    pem = ssl.DER_cert_to_PEM_cert(der)
    fd, path = tempfile.mkstemp(prefix="e2e-cert-", suffix=".pem")
    try:
        with os.fdopen(fd, "w", encoding="ascii") as fh:
            fh.write(pem)
        record.update(_openssl_fields(pem, path))
    finally:
        os.unlink(path)
    return record


def compare(probe, expected):
    failures = 0

    def report(field, ok, detail=""):
        nonlocal failures
        print("CERT %s %s%s" % (field, "OK" if ok else "MISMATCH", detail))
        if not ok:
            failures += 1

    report("probe_tls_version", probe.get("tls_version") == "TLSv1.3", " (%s)" % probe.get("tls_version"))
    report("probe_alpn", probe.get("alpn") == "h2", " (%s)" % probe.get("alpn"))

    for index, want in enumerate(expected, start=1):
        for field in ("san", "issuer", "not_before", "not_after"):
            report(
                "%s_%d" % (field, index),
                probe.get(field) == want.get(field),
                " probe=%r expected=%r" % (probe.get(field), want.get(field)),
            )

    wanted = {want.get("sha256") for want in expected}
    report(
        "sha256",
        probe.get("sha256") in wanted,
        " probe=%s expected=%s" % (probe.get("sha256"), sorted(wanted)),
    )
    return 0 if failures == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)

    p_fetch = sub.add_parser("fetch")
    p_fetch.add_argument("--connect", required=True, help="host:port to dial")
    p_fetch.add_argument("--sni", required=True)
    p_fetch.add_argument("--alpn", default="h2")
    p_fetch.add_argument("--timeout", type=float, default=20.0)
    p_fetch.add_argument("--out", required=True)

    p_cmp = sub.add_parser("compare")
    p_cmp.add_argument("--probe", required=True)
    p_cmp.add_argument("--expected", required=True, action="append")

    args = ap.parse_args()

    if args.mode == "fetch":
        try:
            record = fetch(args.connect, args.sni, args.alpn, args.timeout)
        except Exception as exc:  # noqa: BLE001 - the caller needs the text
            print("CERT fetch FAILED: %s" % exc)
            return 2
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print(json.dumps(record, sort_keys=True))
        return 0

    with open(args.probe, encoding="utf-8") as fh:
        probe = json.load(fh)
    expected = []
    for path in args.expected:
        with open(path, encoding="utf-8") as fh:
            expected.append(json.load(fh))
    return compare(probe, expected)


if __name__ == "__main__":
    sys.exit(main())
