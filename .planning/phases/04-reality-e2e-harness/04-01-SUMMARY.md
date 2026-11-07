---
phase: 04-reality-e2e-harness
plan: 01
subsystem: testing
tags: [bash, caddy, xray, reality, e2e, preflight]

requires: []
provides:
  - fail-closed REALITY E2E preflight
  - reversible overlay derivation from deploy/Caddyfile
  - fixed loopback fixture layout for the harness
affects: [phase-5, phase-6]

actuals:
  tokens: 4600
  tasks: 4
  commits: [2fb3e97]

tech-stack:
  added: [bash, python3 stdlib HTTP server, Caddy adapt]
  patterns: [literal substitution with reverse diff, fail-closed input contract]

key-files:
  created:
    - tests/e2e/run.sh
    - tests/e2e/lib.sh
    - tests/e2e/site-backend.py
    - tests/e2e/README.md
  modified:
    - docs/VERIFY.md

key-decisions:
  - "The E2E fixture derives its Caddyfile from deploy/Caddyfile by literal substitution, reverses it, and requires an empty diff before starting a process."
  - "The fixture keeps `protocols h1 h2` and spells the non-443 site address as `:8443, a.test:8443`."
  - "A missing or empty input exits 2 and names the variable; there is no skip path."

patterns-established:
  - "Fixture derivation: delivery file -> literal replacement -> reverse replacement -> byte diff -> start"
  - "Input contract: every external value is named, checked before startup and covered by a negative preflight"

requirements-completed: [E2E-01]

coverage:
  - id: D1
    description: "The E2E fixture refuses to start with missing inputs and names each missing variable."
    requirement: E2E-01
    verification:
      - kind: integration
        ref: "bash tests/e2e/run.sh --negative-preflight"
        status: pass
    human_judgment: false
  - id: D2
    description: "The overlay is a reversible substitution of the delivery Caddyfile and preserves the address/protocol guards."
    requirement: E2E-01
    verification:
      - kind: integration
        ref: "bash tests/e2e/run.sh --preflight-only"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-11-07
status: complete
---

# Phase 4 Plan 1: REALITY E2E Harness Scaffold Summary

**Fail-closed REALITY preflight with a provably reversible overlay of the delivery Caddyfile**

## Performance

- **Duration:** ~45 min (shared session; not separately instrumented)
- **Completed:** 2026-11-07
- **Tasks:** 4
- **Files modified:** 5

## Accomplishments

- Added `tests/e2e/lib.sh` with report, process, port, JSONL and environment helpers.
- Added `tests/e2e/run.sh` with `--preflight-only`, `--negative-preflight` and the full-run entry point.
- Derived the harness Caddyfile from `deploy/Caddyfile` with literal substitutions and a reverse diff that must be byte-empty.
- Added the loopback backend fixture and the preflight port guards for `8443`, `19099`, `18080` and `10802`.
- Documented the separate suite and its CI/syntax-only posture in `docs/VERIFY.md`.

## Files Created/Modified

- `tests/e2e/run.sh` - preflight, overlay derivation, process lifecycle and item driver
- `tests/e2e/lib.sh` - item, process, port, record and environment helpers
- `tests/e2e/site-backend.py` - one loopback upstream for the site and tunnel paths
- `tests/e2e/README.md` - input contract, ports, modes and limitations
- `docs/VERIFY.md` - the harness is documented as a separate, fail-closed suite

## Decisions Made

- The overlay keeps the delivery file's structure and only changes values, addresses and the fixture SNI; this makes a green run a statement about the delivery shape.
- `E2E_TARGET_MARKER` is a required input in addition to the variables named in the plan, because a status code alone cannot identify the tunnel's body.
- The harness refuses to start if any of its four fixture ports is busy, rather than racing a listener.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added a marker input and an explicit port guard**
- **Found during:** Tasks 2 and 3
- **Issue:** `E2E_TARGET` alone cannot prove the inner response came from the intended target, and a missing port guard would let a stale listener answer a test.
- **Fix:** Added `E2E_TARGET_MARKER`, checked all four fixture ports before startup, and checked every required value through `require_env`.
- **Files modified:** `tests/e2e/run.sh`, `tests/e2e/README.md`
- **Verification:** `--negative-preflight` reports 12/12 PASS; the full run later reached the marker path.
- **Committed in:** `2fb3e97`

**2. [Rule 3 - Blocking] The overlay needed eight literal substitutions, not the smaller list implied by the plan**
- **Found during:** Task 2
- **Issue:** The delivery file has two credentials, two listener/site addresses, the `b.test` site address, the SNI matcher, the layer4 upstream and the reverse-proxy upstream.
- **Fix:** Implemented all eight substitutions and made the reverse path independently reverse them; preflight fails unless the diff is empty.
- **Files modified:** `tests/e2e/run.sh`
- **Verification:** Reverse diff is byte-empty on the delivery file; local and Linux preflight both pass.
- **Committed in:** `2fb3e97`

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 blocking)
**Impact on plan:** Both are required for an attributable test and a clean fixture; no scope expansion.

## Issues Encountered

The plan's example placeholder form is not usable here: `tests/e2e` is scanned by the repository hygiene gate, and a placeholder such as `@@TOKEN@@` inside a `privateKey` value would look like live material. The templates use `<E2E_*>` tokens instead.

## User Setup Required

None - the harness is invoked with the documented external inputs on the Linux test host.

## Next Phase Readiness

The harness has a deterministic stack contract. Phase 4 plan 2 can now add the positive REALITY, certificate and PROXY v2 assertions without inventing a second fixture.

---
*Phase: 04-reality-e2e-harness*
*Completed: 2026-11-07*

## Self-Check: PASSED
