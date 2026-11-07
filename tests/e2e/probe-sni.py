#!/usr/bin/env python3
"""Measure the unknown, empty, and absent SNI baseline.

This probe deliberately does not choose a posture. It records the certificate
and the layer4 record delta for each case, so the owner can decide whether the
current default certificate is acceptable, whether a dedicated decoy is
needed, or whether the handshake should be rejected.
"""

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path


def record_count(path):
    if not path:
        return None
    try:
        return sum(1 for line in Path(path).read_text(encoding="utf-8").splitlines() if line)
    except FileNotFoundError:
        return 0


def certificate_fields(pem, timeout):
    if not pem:
        return {}
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as fh:
        fh.write(pem)
        temp_path = Path(fh.name)
    try:
        proc = subprocess.run(
            [
                "openssl",
                "x509",
                "-in",
                str(temp_path),
                "-noout",
                "-subject",
                "-issuer",
                "-nameopt",
                "RFC2253",
                "-fingerprint",
                "-sha256",
                "-dates",
                "-ext",
                "subjectAltName",
            ],
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"error": f"{type(exc).__name__}: {exc}"}
    finally:
        temp_path.unlink(missing_ok=True)

    text = proc.stdout + "\n" + proc.stderr
    fields = {}
    san = []
    in_san = False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("subject="):
            fields["subject"] = line.split("=", 1)[1]
        elif line.startswith("issuer="):
            fields["issuer"] = line.split("=", 1)[1]
        elif line.startswith("SHA256 Fingerprint="):
            fields["sha256"] = line.split("=", 1)[1].replace(":", "").lower()
        elif line.startswith("notBefore="):
            fields["not_before"] = line.split("=", 1)[1]
        elif line.startswith("notAfter="):
            fields["not_after"] = line.split("=", 1)[1]
        elif line.startswith("X509v3 Subject Alternative Name:"):
            in_san = True
        elif in_san:
            if line.startswith("X509v3 "):
                in_san = False
            elif line:
                san.extend(re.findall(r"(?:DNS|IP Address|URI):[^,\s]+", line))
                in_san = False
    if san:
        fields["san"] = san
    return fields


def first_certificate(output):
    begin = output.find("-----BEGIN CERTIFICATE-----")
    if begin < 0:
        return ""
    end = output.find("-----END CERTIFICATE-----", begin)
    if end < 0:
        return ""
    end += len("-----END CERTIFICATE-----")
    return output[begin:end] + "\n"


def probe(case, servername, host, port, count_file, timeout):
    before = record_count(count_file)
    command = [
        "openssl",
        "s_client",
        "-connect",
        f"{host}:{port}",
        "-tls1_3",
        "-alpn",
        "h2",
        "-showcerts",
    ]
    if servername is not None:
        command.extend(["-servername", servername])
    try:
        proc = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        output = proc.stdout + "\n" + proc.stderr
        error = ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        output = ""
        error = f"{type(exc).__name__}: {exc}"
    after = record_count(count_file)

    cert = first_certificate(output)
    result = {
        "case": case,
        "sni": servername,
        "handshake": bool(cert),
        "layer4_records_delta": after - before if before is not None and after is not None else None,
    }
    protocol = re.search(r"(?:New,|Protocol\s*:)\s*(TLSv1\.[0-9])", output)
    alpn = re.search(r"ALPN protocol:\s*(\S+)", output)
    if protocol:
        result["tls_version"] = protocol.group(1)
    if alpn:
        result["alpn"] = alpn.group(1)
    if error:
        result["error"] = error
    elif not cert:
        tail = [line for line in output.splitlines() if line.strip()][-5:]
        result["error"] = " | ".join(tail)
    if case == "empty" and not cert:
        result["note"] = (
            "The client refused to construct an empty SNI extension; "
            "no TLS record left the process."
        )
    result.update(certificate_fields(cert, timeout))
    print("E2E-07 BASELINE " + json.dumps(result, sort_keys=True))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--connect-host", default="127.0.0.1")
    ap.add_argument("--connect-port", type=int, default=8443)
    ap.add_argument("--count-file")
    ap.add_argument("--timeout", type=float, default=15.0)
    args = ap.parse_args()

    cases = (
        ("unknown", "unknown.test"),
        ("empty", ""),
        ("absent", None),
    )
    for case, servername in cases:
        probe(
            case,
            servername,
            args.connect_host,
            args.connect_port,
            args.count_file,
            args.timeout,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
