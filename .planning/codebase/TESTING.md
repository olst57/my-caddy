---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Testing Infrastructure

**Analysis Date:** 2026-11-05

## Test Framework

**Runner:**
- Bash scripts with explicit exit codes and item lines.
- No Jest, pytest, Go test, or other framework is used by this repository.

**Assertion style:**
- Each item prints `ITEM <ID> PASS|FAIL`.
- The verifier prints a final `VERIFY: PASS|FAIL`.
- The coexistence suite prints `COEXIST: PASS|FAIL`.

## Test Structure

**Gate 0 probes (`tests/probes/`):**
- `gate-a1.sh`, `gate-a1c.sh` — patch separability and the negative build case.
- `gate-a2.sh` — `b.test` isolation.
- `gate-a3.sh` — PROXY v2 pairing.
- `gate-build.sh` — shared build helper.
- `lib-evidence.sh` — evidence capture helpers.

**Offline verifier (`scripts/verify.sh`):**
- 26 items: `S3-1`..`S3-13`, `S7-1`..`S7-8`, `S7-12`..`S7-15`, `S7-18`.
- Binds no listener, performs no TLS handshake, sends no HTTP request.
- Requires `jq` and an executable Caddy binary.

**Coexistence suite (`tests/coexist/`):**
- `run.sh` starts the real stack on `:443`.
- `site-backend.py` — local site backend.
- `stub-upstream.py` — REALITY upstream stub.
- `naive-tunnel.py` — tunnel assertion helper.
- Items `CO-1`..`CO-7`.

## Coverage

**Offline coverage:**
- Build provenance and module set.
- Handler order and listener wrapper order.
- Protocol pin declaration and adapted semantics.
- Open-proxy shape (`auth_credentials` plus `probe_resistance`).
- Secrets, UUID, hostname, and placeholder hygiene.
- `deploy/` freeze relative to the `v0.3.0` tag.

**Runtime coverage:**
- Site leg, REALITY leg, unknown SNI, naive tunnel, decoy control, h2 proxy hop,
  and absence of a UDP `:443` listener.

**Not covered:**
- arm64 execution.
- Public-internet HTTP/3 (off by design).
- Any behaviour of a real deployment with real credentials.

## Mocking

- `tests/coexist/stub-upstream.py` stands in for the REALITY destination.
- `tests/coexist/site-backend.py` stands in for the site upstream.
- The suite still uses one real external TLS endpoint for the naive tunnel,
  because the delivery ACL denies loopback destinations.

## CI Integration

`.github/workflows/verify.yml`:

1. `offline` builds the amd64 artifact and runs `scripts/verify.sh`.
2. `coexist` downloads that artifact, restores the exec bit, installs runtime
   dependencies, and runs `tests/coexist/run.sh` as root.
3. Logs and artifacts upload when the job finishes.

`build.yml` and `gate0.yml` remain separate: they build artifacts and run Gate 0
probes respectively.

## Host Constraints

- Windows: cannot execute the ELF; `verify.sh` fail-closes at preflight.
- Linux without root: cannot run the coexistence suite.
- CI: `ubuntu-latest` provides Linux and root through `sudo`.

## Current Status

The 26-item verifier and the 7-item coexistence suite exist in the working tree.
They are not committed, and `verify.yml` has not run on this slice yet.

<!-- refreshed: 2026-11-05 -->
