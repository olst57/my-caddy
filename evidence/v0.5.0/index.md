# `v0.5.0` — REALITY closure and the E2E harness (2026-11-07)

This set is the **redacted copy** of the run capture. It is produced only by
`scripts/redact-evidence.sh`; no file here was written by hand, and every
file has the same line count as its source.

## Provenance

| Field | Value |
|---|---|
| Commit | `2797575` |
| Run date | 2026-11-07 (11:23–11:25 UTC) |
| Host class | `linux-amd64`, root, ports `8443`/`19099`/`18080`/`18081`/`18082`/`10802` |
| Caddy binary | go1.26.9 build, sha256 `872caeee23f804fcb2991e26f3c7fe9526eb8a1d5003d4dedcc280c95d762f1d` |
| Xray binary | 26.10.29 |
| Raw capture | `.gate/v050/capture/` (gitignored, not committed) |
| Command | `bash scripts/redact-evidence.sh .gate/v050/capture evidence/v0.5.0` |
| Line counts | `verify-26.log` 29/29, `coexist-8.log` 10/10, `e2e-items.log` 20/20, `smoke-counts.log` 6/6, `caddy-sha256.txt` 2/2 |
| Idempotence | second pass into a scratch directory: `diff -r` empty |
| Archive hash | `sha256sum` over the five files, piped to `sha256sum` = `35e1511a2c571fdb550be2f5cc02fb0c3873db058c891aaa78476a5cf1ddaf0b` |

## Contents

| File | What it records |
|---|---|
| `verify-26.log` | the offline gate: `ITEM S3-1`…`S3-13`, `S7-1`…`S7-8`, `S7-12`…`S7-15`, `S7-18`, `PASS=26 FAIL=0`, `VERIFY: PASS` |
| `coexist-8.log` | `ITEM CO-1`…`CO-8` and `COEXIST: PASS` |
| `e2e-items.log` | eleven `ITEM E2E-xx PASS` lines, the three `E2E-07 BASELINE` records (`reject`), both positive controls, and `E2E: PASS` |
| `smoke-counts.log` | the four `SMOKE` count lines and the upstream corroboration (`reality_requests=38`, `naive_records=38`) |
| `caddy-sha256.txt` | the binary the run used |

The E2E capture is a **line-selected excerpt**: every item, posture, control and
verdict line, but not the verbose certificate dump. The full log stays in
`.gate/`; it is not committed because it contains a third-party certificate
transcript that is not evidence about this repository.

## Counts

| Suite | Result |
|---|---|
| Offline `verify.sh` | `PASS=26 FAIL=0` |
| Fixture guard | `FIXTURES: PASS` (inside the E2E preflight) |
| Coexistence | `CO-1`…`CO-8` PASS |
| E2E items | 11/11 PASS |
| Smoke, REALITY serial / concurrent | 30/30, 8/8, zero failures |
| Smoke, naive serial / concurrent | 30/30, 8/8, zero failures |
| Smoke upstream corroboration | 38 REALITY requests, 38 naive records |

The smoke percentiles from this run: REALITY `p50=32 ms`, `p95=57 ms` (serial)
and `p50=61 ms`, `p95=74 ms` (concurrent); naive `p50=93 ms`, `p95=99 ms`
(serial) and `p50=209 ms`, `p95=227 ms` (concurrent).

## Negative control (not archived)

A second full run set `E2E_SMOKE_TARGET_IP=127.0.0.1`, which makes the naive
smoke ask the proxy for an address the delivery ACL denies. Result: the ten
other items stayed green and `E2E-08` turned red — `naive serial 30/30
failures`, `naive concurrent 8/8 failures`, `naive_records=0`. The control log
stays in `.gate/v050/e2e-p6neg.full.log` and is not published: a red run is not
release evidence, only proof that the item is sensitive.

## What this set does not prove

- **Byte-identical rebuilds.** The same sources still produce different bytes
  on different hosts; the binary hash identifies the artifact, not a
  reproducible build.
- **Production behaviour.** The run uses a non-443 listener, a throwaway SNI,
  Caddy's internal CA, and a REALITY destination chosen for a short path from
  this host. None of those is a production deployment.
- **Soak behaviour.** E2E-08 is 30 serial plus 8 concurrent requests per leg,
  not a long soak, and it does not measure resource growth.
- **DPI resistance or active probing.** Nothing here characterises traffic
  under an adversary.
- **arm64.** This set is amd64 only; the arm64 claim belongs to `v0.4.3`.
- **The REALITY destination's own health.** The destination is on the
  per-connection path. A latency spike can come from that path rather than
  from the tunnel.

## Notes

- The unknown-SNI posture is `reject`, and `E2E-07` asserts it for an unknown,
  an empty, and an absent SNI. The empty case is a documented client
  limitation: the probe's TLS client refuses to build the extension.
- The `deploy/` tree was not modified by this milestone. The E2E Caddyfile is
  derived from it by literal substitution and reversed before a listener
  starts.
- `v0.4.3` was not moved, re-tagged, or rewritten.
