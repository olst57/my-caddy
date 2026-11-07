---
phase: 06-stability-smoke-evidence-and-release-decision
plan: 01
subsystem: testing
tags: [bash, smoke, concurrency, reality, naive, e2e]

requires:
  - phase: 05-naive-acl-assertions-and-fixture-guards
    provides: the eleven-item harness, its preflight, and the fixture guards
provides:
  - a serial and concurrent smoke over both legs, with printed counts
  - an upstream corroboration that a bypassed listener cannot fake
  - a measured latency budget that separates the tunnel from the destination
affects: [phase-6]

actuals:
  tokens: 8400
  tasks: 3
  commits: [6ef8ef8, 2797575]

tech-stack:
  added: []
  patterns: [per-request client unit, no-retry smoke, upstream-counter corroboration]

key-files:
  created:
    - tests/e2e/smoke.sh
  modified:
    - tests/e2e/run.sh
    - tests/e2e/naive-tunnel.py
    - tests/e2e/backend-counting.py
    - tests/e2e/README.md
    - docs/VERIFY.md

key-decisions:
  - "Every smoke request builds a complete client unit: a new SOCKS/TLS stack for REALITY, a new TLS+CONNECT+GET for naive. No connection is reused and no request is retried."
  - "A single failed request turns E2E-08 red; the item never rounds partial success up."
  - "The naive smoke target is a TEST-NET-3 address bound to lo, so the smoke does not touch the frozen ACL and E2E-05c still exercises the unmodified private-network deny."

requirements-completed: [E2E-08]

coverage:
  - id: D1
    description: "Thirty serial REALITY requests complete with zero failures and the count is printed."
    requirement: E2E-08
    verification:
      - kind: e2e
        ref: "SMOKE leg=reality mode=serial count=30 failures=0 on the Linux test host"
        status: pass
    human_judgment: false
  - id: D2
    description: "Eight concurrent REALITY requests complete with zero failures."
    requirement: E2E-08
    verification:
      - kind: e2e
        ref: "SMOKE leg=reality mode=concurrent count=8 failures=0"
        status: pass
    human_judgment: false
  - id: D3
    description: "The naive leg passes the same two modes through the tunnel, including the inner body marker."
    requirement: E2E-08
    verification:
      - kind: e2e
        ref: "naive serial 30/30 and concurrent 8/8, each with --expect target"
        status: pass
    human_judgment: false
  - id: D4
    description: "The upstream counters agree with the client counts, so a bypassed listener cannot pass."
    requirement: E2E-08
    verification:
      - kind: e2e
        ref: "SMOKE UPSTREAM reality_requests=38 naive_records=38"
        status: pass
    human_judgment: false
  - id: D5
    description: "A denied naive target makes E2E-08 red while the other ten items stay green."
    requirement: E2E-08
    verification:
      - kind: e2e
        ref: "negative control with E2E_SMOKE_TARGET_IP=127.0.0.1: naive 30/30 and 8/8 failures, passed=10 failed=1"
        status: pass
    human_judgment: false

duration: 2h
completed: 2026-11-07
status: complete
---

# Phase 6 Plan 1: Serial and Concurrent Smoke Summary

**Both legs survive 30 serial and 8 concurrent requests, and the upstream
counters prove the traffic actually crossed the listener**

## Performance

- **Duration:** ~2 h across implementation, the failed first destination, and
  the re-run
- **Completed:** 2026-11-07
- **Tasks:** 3 (implement, measure, document)
- **Files modified:** 6

## Accomplishments

- Added `tests/e2e/smoke.sh <reality|naive> <serial|concurrent>`: 30 serial
  and 8 concurrent requests, no retries, one fresh client unit per request,
  nearest-rank percentiles, and one machine-readable result line.
- Wired it into `tests/e2e/run.sh` as `E2E-08` and raised the verdict from ten
  items to eleven, so a smoke that stops running cannot still print green.
- Added `--expect target` to the naive tunnel helper: success now means the
  inner `GET /smoke` returned `200` **and** the target marker, not merely that
  a CONNECT was answered.
- Bound the naive smoke target to `203.0.113.10:18082` on `lo`, which the
  delivery ACL allows, so the smoke never weakens or edits the frozen ACL that
  `E2E-05c` asserts.
- Corroborated the client counts with the upstream side: the site backend and
  the counting target each record 38 requests (30 + 8).

## Measured Counts

| Leg | Mode | Requests | Failures | p50 | p95 |
|---|---|---:|---:|---:|---:|
| REALITY | serial | 30 | 0 | 32 ms | 57 ms |
| REALITY | concurrent | 8 | 0 | 61 ms | 74 ms |
| naive | serial | 30 | 0 | 93 ms | 99 ms |
| naive | concurrent | 8 | 0 | 209 ms | 227 ms |

`SMOKE UPSTREAM reality_requests=38 naive_records=38`. The naive leg is slower
because the helper performs a full TLS handshake, CONNECT, and inner GET per
request; the REALITY leg pays a SOCKS setup and a VLESS round trip.

## The First Failure, and What It Was

The first green attempt used `www.microsoft.com` as the REALITY destination.
Three of thirty serial requests hit the 20-second request budget
(`first_fail=3`), the upstream saw 37 of 38, and `E2E-08` went red.

The tunnel was not the cause. Inbound REALITY relays each new connection's
ClientHello to the configured destination, so the destination's TLS handshake
is on the per-connection path. Measured from the test host, that destination
took 1.6–2.3 s and occasionally hung. Replacing it with a destination about
40 ms away produced 30/30 and 8/8 with `p50=32 ms`.

This is recorded as a **test-path defect**, not a tunnel defect: the harness
now documents the destination round-trip bound, and a latency spike has to be
attributed to the path before it is called a regression.

## Negative Control

Re-running the whole suite with `E2E_SMOKE_TARGET_IP=127.0.0.1` makes the naive
smoke ask the proxy for a private address, which the delivery ACL denies. The
other ten items stayed green and `E2E-08` turned red with `naive serial 30/30
failures`, `naive concurrent 8/8 failures`, and `naive_records=0`, ending
`E2E: FAIL (passed=10 failed=1)`. The item is therefore sensitive to the ACL,
not merely to a listener being up.

## Assertion Design

- The pass condition is `failures=0` over the full count; there is no tolerance
  and no retry.
- A failure prints its index and reason and exits non-zero, so CI-shaped
  parsing cannot mistake a partial run for success.
- `E2E-08` requires all four count lines and both upstream facts; a missing
  line is a failure rather than a skip.
- The destination and SNI stay environment inputs. No destination name is
  hard-coded in a tracked file.

## Files Created/Modified

- `tests/e2e/smoke.sh` - the smoke loop, percentiles, and result line
- `tests/e2e/run.sh` - `E2E-08`, the TEST-NET-3 target, and upstream assertions
- `tests/e2e/naive-tunnel.py` - `--expect target`
- `tests/e2e/backend-counting.py` - `TARGET_BIND`
- `tests/e2e/README.md` - item table, budget, and destination-RTT note
- `docs/VERIFY.md` - `E2E-08` row, smoke budget, and the measured latency split

## Deviations from Plan

**1. [Rule 3 - Blocking] The naive smoke could not use a loopback target**
- **Found during:** Task 1
- **Issue:** the delivery ACL denies `127.0.0.1`, so a loopback smoke target
  would have forced a test-only ACL change, which would have made the frozen
  delivery shape untested by this item.
- **Fix:** the smoke target is `203.0.113.10:18082` bound to `lo`, which the
  ACL allows; the address is removed at exit.
- **Impact:** `E2E-05c` still exercises the unmodified private-network deny,
  and no delivery file was touched.

**2. [Rule 1 - Decision] The first destination was replaced**
- **Found during:** Task 2
- **Issue:** a destination with a 1.6–2.3 s handshake produced 3 of 30
  timeouts.
- **Fix:** used a destination ~40 ms away and documented the bound.
- **Impact:** the smoke now measures the tunnel rather than the destination's
  health; the limitation is stated in `docs/VERIFY.md`.

---

**Total deviations:** 2 (1 blocking, 1 decision)
**Impact on plan:** the smoke is implemented, measured, and corroborated; the
frozen counts are unchanged.

## Issues Encountered

- The first offline re-run on the test host reported 25/26 with `S7-18` red,
  because the git bundle used to clone the test tree did not carry the `v0.3.0`
  tag. Rebuilding the bundle with `refs/tags/v0.3.0` and re-cloning produced
  26/26. This is a run-fixture defect, and it is recorded rather than hidden:
  the tag is part of the input the verifier reads.
- Percentiles are nearest-rank, not interpolated, so they are reproducible
  from the printed per-request timings.

## Verification Evidence

- `bash -n` and `shellcheck -S warning` over the modified scripts: exit `0`.
- `E2E: PASS`, 11/11 items, with both positive controls green.
- `PASS=26 FAIL=0`, `VERIFY: PASS`.
- `ITEM CO-1` through `CO-8`, `COEXIST: PASS`.
- Negative control as described above: `passed=10 failed=1`.
