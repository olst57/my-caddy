---
phase: 04-reality-e2e-harness
plan: 03
subsystem: testing
tags: [bash, python3, xray, reality, negative-controls, ci, e2e]

requires:
  - phase: 04-reality-e2e-harness
    provides: passing REALITY, certificate and PROXY v2 baseline
provides:
  - three single-field REALITY negative controls
  - per-variable fail-closed preflight controls
  - CI syntax coverage without executing the harness
affects: [phase-5, phase-6]

actuals:
  tokens: 4300
  tasks: 4
  commits: [2fb3e97]

tech-stack:
  added: [Xray 26.10.29, shellcheck, python3 py_compile]
  patterns: [single-field mutation diff, scoped client-or-server failure classification, split control timeout]

key-files:
  created:
    - tests/e2e/negative-controls.sh
  modified:
    - tests/e2e/run.sh
    - tests/e2e/README.md
    - docs/VERIFY.md
    - .github/workflows/verify.yml
    - .gitignore

key-decisions:
  - "A wrong UUID is rejected by the VLESS server after the REALITY handshake, so failure attribution scans both the scoped client log and the scoped server log."
  - "Negative controls get a separate 90-second default timeout; the ordinary request budget stays 25 seconds."
  - "CI syntax-checks the harness and runs only its fail-closed preflight controls; it never executes the full stack."

patterns-established:
  - "Credential control: passing config -> exactly one literal mutation -> diff must be one removal and one addition -> expected non-tunnel"
  - "Failure attribution is scoped to the item's byte window, not the whole process log"

requirements-completed: [E2E-04]

coverage:
  - id: D1
    description: "A wrong UUID, publicKey and shortId each fail to open the REALITY tunnel as separate assertions."
    requirement: E2E-04
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-04a..E2E-04c"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every required variable has a fail-closed preflight control that starts no process."
    requirement: E2E-04
    verification:
      - kind: integration
        ref: "bash tests/e2e/run.sh --negative-preflight"
        status: pass
    human_judgment: false
  - id: D3
    description: "CI syntax-checks the harness without claiming to run the REALITY stack."
    requirement: E2E-04
    verification:
      - kind: unit
        ref: ".github/workflows/verify.yml#E2E harness is syntax-checked, not executed"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-11-07
status: complete
---

# Phase 4 Plan 3: Negative Controls and Fail-Closed CI Summary

**Three independent REALITY credential controls and a CI gate that proves fail-closed input handling without running the stack**

## Performance

- **Duration:** ~50 min (shared session; not separately instrumented)
- **Completed:** 2026-11-07
- **Tasks:** 4
- **Files modified:** 6

## Accomplishments

- Added `negative-controls.sh` to render UUID, publicKey and shortId mutations and enforce a one-field diff.
- Added `E2E-04a/b/c`, the positive control and the closing positive control.
- Added the per-variable `--negative-preflight` tablature: 12 controls pass with no destination and no listener.
- Added CI coverage for `bash -n`, shellcheck, `python3 -m py_compile` and `--negative-preflight`.
- Completed the default-parameter full run on the Linux test host: `E2E-01`..`E2E-04c` PASS, closing control PASS, `E2E: PASS`.
- Verified the pushed commit in CI: [gate0 run 42337117641](https://github.com/olst57/my-caddy/actions/runs/42337117641) and [verify run 42337117568](https://github.com/olst57/my-caddy/actions/runs/42337117568) both concluded success.

## Files Created/Modified

- `tests/e2e/negative-controls.sh` - single-field control renderer
- `tests/e2e/run.sh` - control execution, scoped classification and timeout split
- `tests/e2e/README.md` - control semantics and timeout contract
- `docs/VERIFY.md` - CI and execution boundary
- `.github/workflows/verify.yml` - syntax-only E2E coverage
- `.gitignore` - Python bytecode from the syntax step

## Decisions Made

- The wrong-UUID control is classified against both the client log and the server log; the server is the component that names `invalid request user id`.
- The control timeout is 90 seconds while ordinary requests remain at 25 seconds, because REALITY retries can outlive a normal request without changing the expected rejection.
- CI never runs the full harness; it proves the fail-closed surface and leaves the stack execution to the Linux host.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan assumed an existing shellcheck step**
- **Found during:** Task 3
- **Issue:** `verify.yml` had no shellcheck installation or step, so extending it required adding the dependency and the step.
- **Fix:** Installed `shellcheck` in the offline job and added `bash -n`, shellcheck, `py_compile` and `--negative-preflight`.
- **Files modified:** `.github/workflows/verify.yml`, `.gitignore`
- **Verification:** Local shellcheck and negative preflight pass; the Linux-host verifier remains 26/26.
- **Committed in:** `2fb3e97`

**2. [Rule 1 - Bug] A wrong UUID can exceed the ordinary request timeout before the server logs the rejection**
- **Found during:** Repeated full runs
- **Issue:** With the 25-second budget, the client sometimes timed out before the server named the invalid user id, so E2E-04a was not attributable.
- **Fix:** Added `E2E_CONTROL_TIMEOUT` with a 90-second default and kept `E2E_TIMEOUT` at 25 for ordinary requests.
- **Files modified:** `tests/e2e/run.sh`, `tests/e2e/README.md`
- **Verification:** Default-parameter full run passed E2E-04a and all six items.
- **Committed in:** `2fb3e97`

**3. [Rule 1 - Bug] The wrong-UUID failure is server-side, not client-side**
- **Found during:** E2E-04a debugging
- **Issue:** The client warning log contained only startup and SOCKS acceptance; the server log contained `rejected proxy/vless/encoding: invalid request user id`.
- **Fix:** Scoped a byte window on the server log and classified either side, while keeping the positive control as the attribution precondition.
- **Files modified:** `tests/e2e/run.sh`
- **Verification:** E2E-04a PASS; E2E-04b and E2E-04c continue to use client-side REALITY errors.
- **Committed in:** `2fb3e97`

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All three were necessary for a deterministic, attributable negative-control suite. No production code or deploy/ file changed.

## Issues Encountered

The first complete run after the loopback fix reached 5/6: E2E-04a was marked FAIL even though the server had rejected the UUID, because the assertion only scanned the client log. The scoped server-log classification and the dedicated control timeout made the same behavior pass without weakening the failure condition.

The existing suites were re-run after the change:

- `scripts/verify.sh`: `PASS=26 FAIL=0`, `VERIFY: PASS`
- `tests/coexist/run.sh`: CO-1..CO-8 PASS, `COEXIST: PASS`

CI on the pushed commit: `gate0` success at
<https://github.com/olst57/my-caddy/actions/runs/42337117641>; `verify`
success at <https://github.com/olst57/my-caddy/actions/runs/42337117568>.

## User Setup Required

None - CI needs no destination, key material or root.

## Next Phase Readiness

Phase 4 is complete: the positive tunnel, live certificate, PROXY v2 and all three credential controls are executable and green. Phase 5 can now add the naive/ACL assertions and the unknown-SNI decision checkpoint.

---
*Phase: 04-reality-e2e-harness*
*Completed: 2026-11-07*

## Self-Check: PASSED
