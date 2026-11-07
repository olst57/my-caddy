---
phase: 05-naive-acl-assertions-and-fixture-guards
plan: 01
subsystem: testing
tags: [bash, python3, naiveproxy, acl, decoy, e2e]

requires:
  - phase: 04-reality-e2e-harness
    provides: fail-closed E2E preflight and process lifecycle
provides:
  - byte-counted naive refusal assertions
  - decoy-body and target-marker separation
  - private-target ACL assertion with an in-tunnel request
affects: [phase-5, phase-6]

actuals:
  tokens: 6400
  tasks: 3
  commits: [7626468]

tech-stack:
  added: [Python stdlib counting backend, raw CONNECT probe]
  patterns: [data-not-status assertion, scoped log window, mutation controls]

key-files:
  created:
    - tests/e2e/backend-counting.py
    - tests/e2e/naive-tunnel.py
  modified:
    - tests/e2e/run.sh
    - tests/e2e/README.md
    - docs/VERIFY.md

key-decisions:
  - "The decoy and private-target checks are decided by response data and a JSONL counter, never by the CONNECT status alone."
  - "The private-target probe sends a GET inside the tunnel so an ACL regression produces the target marker and a counter delta even when the log line changes."
  - "The test-only debug directive is inserted into the overlay and removed before the reverse diff; the delivery file keeps its normal log level."

patterns-established:
  - "A refusal assertion must name the decoy body, the absence of the target marker, and a zero counter delta."
  - "Every mutation control changes one behaviour and is reported alongside its unmodified neighbours."

requirements-completed: [E2E-05]

coverage:
  - id: D1
    description: "A wrong credential returns the decoy page, not the target marker, and the counting target does not move."
    requirement: E2E-05
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-05a"
        status: pass
    human_judgment: false
  - id: D2
    description: "A missing credential produces the same three facts."
    requirement: E2E-05
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-05b"
        status: pass
    human_judgment: false
  - id: D3
    description: "A correct credential cannot reach the private target; the counter is unchanged and the 403 ACL log is present."
    requirement: E2E-05
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-05c"
        status: pass
    human_judgment: false
  - id: D4
    description: "Removing the ACL or changing the decoy domain makes the corresponding item red."
    requirement: E2E-05
    verification:
      - kind: e2e
        ref: "scratch overlay mutations recorded in .gate/v050/"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-11-07
status: complete
---

# Phase 5 Plan 1: Naive and Private-Target Assertions Summary

**Decoy and ACL refusals are now measured by body markers and upstream bytes, not by proxy status**

## Performance

- **Duration:** ~55 min in the shared Linux test session
- **Completed:** 2026-11-07
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added `tests/e2e/backend-counting.py`, a loopback-only HTTP target that writes
  one fsynced JSONL record per accepted request.
- Added `tests/e2e/naive-tunnel.py`, a raw CONNECT probe that records the
  response bytes and distinguishes the decoy page from the target marker.
- Added `E2E-05a`, `E2E-05b` and `E2E-05c` to the harness.
- Made the private-target client send an inner GET, so an ACL regression is
  observable through the counter and the marker even before the log is read.
- Kept the delivery Caddyfile unchanged by inserting `debug` and
  `probe_resistance localhost` only in the reversible test overlay.

## Files Created/Modified

- `tests/e2e/backend-counting.py` - loopback counter and fixed marker target
- `tests/e2e/naive-tunnel.py` - CONNECT probe with decoy and target detection
- `tests/e2e/run.sh` - counter lifecycle and the three naive/ACL items
- `tests/e2e/README.md` - input, port, decoy, ACL and retry explanation
- `docs/VERIFY.md` - recorded run and the new assertion semantics

## Decisions Made

- A refused CONNECT can still return a `200` header, so status is never the
  verdict; the decoy body and the target counter are the required facts.
- The private-target probe sends `GET /private-probe` inside the tunnel. This
  makes the ACL check sensitive to both the log line and the data path.
- The forwarding log needs the test-only `debug` directive because the ACL
  denial is logged at debug level. The reverse diff strips that line, so the
  delivery file is unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] The private-target check needed an in-tunnel request**
- **Found during:** Task 3
- **Issue:** A CONNECT response can be a `200` followed by an empty body even
  when the ACL denies the dial, so a response-only check can be vacuous.
- **Fix:** The probe sends a GET after the CONNECT request; if an allow rule is
  present, the counting target records the request and returns its marker.
- **Files modified:** `tests/e2e/naive-tunnel.py`, `tests/e2e/run.sh`
- **Verification:** the ACL mutation produced counter `0 -> 1`, status `200`,
  target marker `true`, body bytes `161`, and `E2E-05c FAIL`.
- **Committed in:** `7626468`

**2. [Rule 3 - Blocking] The 403 denial is not visible at the delivery log level**
- **Found during:** Task 3
- **Issue:** Caddy records the forwardproxy ACL denial at debug level after the
  CONNECT `200`, while the delivery file intentionally uses normal logging.
- **Fix:** insert a single test-only `debug` line in the overlay and remove it
  during the reverse diff; require the scoped `no allowed IP addresses for
  127.0.0.1` and `"status":403` lines.
- **Files modified:** `tests/e2e/run.sh`, `tests/e2e/README.md`,
  `docs/VERIFY.md`
- **Verification:** `E2E-05c` PASS with the log window; reverse diff is
  byte-empty.
- **Committed in:** `7626468`

**3. [Rule 2 - Missing Critical] The decoy domain had to point at the counting target for the mutation to be observable**
- **Found during:** Task 2
- **Issue:** the delivery file's decoy domain is not the loopback target, so a
  future tunnel regression could not produce a counter delta.
- **Fix:** substitute `probe_resistance localhost` in the test overlay; the
  refused requests name `localhost:18081`. The delivery file is unchanged and
  the substitution is reversed with the other overlay edits.
- **Files modified:** `tests/e2e/run.sh`, `tests/e2e/README.md`
- **Verification:** decoy mutation made `E2E-05a` and `E2E-05b` red while
  `E2E-05c` stayed green.
- **Committed in:** `7626468`

---

**Total deviations:** 3 auto-fixed (2 missing critical, 1 blocking)
**Impact on plan:** All are required to make the assertions non-vacuous; the
delivery Caddyfile and the frozen gate counts are unchanged.

## Issues Encountered

- The first full positive run was affected by Xray's listener-before-REALITY
  readiness window. The final harness polls the same client/server pair with
  backoff instead of restarting it; the functional item still requires a
  complete successful request.
- One decoy-mutation run also lost its live destination certificate fetch to
  the test host's network. The targeted result was unambiguous: `E2E-05a` and
  `E2E-05b` failed, `E2E-05c` passed, and the unrelated `E2E-02` red was a
  live-destination transient, not a decoy effect.

## Verification Evidence

- Final positive run: `E2E-01` through `E2E-05c` and both positive controls
  passed; `E2E: PASS`.
- Decoy mutation: `E2E-05a` and `E2E-05b` failed; `E2E-05c` passed.
- ACL mutation: only `E2E-05c` failed; counter `0 -> 1`, response `200`,
  target marker present, body bytes `161`.
- `--negative-preflight`: 12/12 PASS.
- `PASS=26 FAIL=0`, `VERIFY: PASS`; `CO-1` through `CO-8` PASS,
  `COEXIST: PASS`.
- First offline run was `25/26`: the temporary clone lacked the `v0.3.0` tag,
  so `S7-18` could not verify the deploy freeze. Restoring the tag made the
  same tree pass `26/26`; this is a run-fixture deviation, not a code result.
- Evidence: `.gate/v050/e2e-p5-final2.log`,
  `.gate/v050/e2e-p5-decoy.log`, `.gate/v050/e2e-p5-acl.log`,
  `.gate/v050/e2e-p5-badrender.log`, and the archived
  `.gate/v050/p5-evidence.tgz`.

## Next Phase Readiness

Plan 05-02 reuses the same loopback discipline for the fixture address and
protocol guard. The E2E-07 posture checkpoint remains untouched until its
baseline is measured.

---
*Phase: 05-naive-acl-assertions-and-fixture-guards*
*Completed: 2026-11-07*

## Self-Check: PASSED
