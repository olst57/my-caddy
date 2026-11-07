---
phase: 05-naive-acl-assertions-and-fixture-guards
plan: 02
subsystem: testing
tags: [bash, caddyfile, fixtures, protocols, ci, e2e]

requires:
  - phase: 05-naive-acl-assertions-and-fixture-guards
    provides: the E2E overlay and its preflight
provides:
  - machine-checked non-443 fixture address guard
  - machine-checked explicit protocol pin
  - CI and E2E preflight sharing one implementation
affects: [phase-5, phase-6]

actuals:
  tokens: 3600
  tasks: 3
  commits: [7626468]

tech-stack:
  added: [POSIX awk fixture parser]
  patterns: [one guard reused by CI and runtime, read-only delivery check]

key-files:
  created:
    - tests/fixtures/check.sh
    - tests/fixtures/README.md
  modified:
    - tests/e2e/run.sh
    - .github/workflows/verify.yml
    - docs/VERIFY.md

key-decisions:
  - "The guard accepts the protocol pin in a dual-form site block or in the global servers block that owns the same port."
  - "The delivery file's `:443, a.test` form is read-only and exempt from the non-443 rule because the second address inherits the first port."
  - "The guard is a separate check, not a 27th offline item, so the frozen 26/8 counts remain comparable."

requirements-completed: [E2E-06]

coverage:
  - id: D1
    description: "A non-443 fixture written as `host:port` fails before startup."
    requirement: E2E-06
    verification:
      - kind: integration
        ref: "bash tests/fixtures/check.sh with a bad sample"
        status: pass
    human_judgment: false
  - id: D2
    description: "A non-443 fixture without `protocols h1 h2` fails the same way."
    requirement: E2E-06
    verification:
      - kind: integration
        ref: "bash tests/fixtures/check.sh with a missing-protocol sample"
        status: pass
    human_judgment: false
  - id: D3
    description: "The delivery file remains compliant and unchanged."
    requirement: E2E-06
    verification:
      - kind: integration
        ref: "bash tests/fixtures/check.sh (deploy/Caddyfile PASS)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The rendered E2E overlay is rejected by preflight when its address shape is broken."
    requirement: E2E-06
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh --preflight-only with a bad render"
        status: pass
    human_judgment: false

duration: 30min
completed: 2026-11-07
status: complete
---

# Phase 5 Plan 2: Fixture Address and Protocol Guards Summary

**The F-01 address trap and the protocol pin now fail before a listener starts**

## Performance

- **Duration:** ~30 min in the shared Linux test session
- **Completed:** 2026-11-07
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added `tests/fixtures/check.sh`, a single awk-based parser for every
  `tests/**/*.Caddyfile` plus the read-only `deploy/Caddyfile`.
- Required every non-443 listener to have both `:port` and `host:port` forms
  and an explicit `protocols h1 h2` in the site block or its `servers` block.
- Called the same guard from CI and from the E2E preflight over the rendered
  overlay; the rule has one implementation.
- Kept `scripts/verify.sh` at 26 items and the coexistence suite at eight.
- Documented the delivery-file exception and the fixture rule in
  `tests/fixtures/README.md` and `docs/VERIFY.md`.

## Files Created/Modified

- `tests/fixtures/check.sh` - fixture parser and exit contract
- `tests/fixtures/README.md` - address forms, protocol pin and CI/runtime reuse
- `tests/e2e/run.sh` - preflight invokes the shared guard on the rendered file
- `.github/workflows/verify.yml` - a separate fixture-guard step
- `docs/VERIFY.md` - the frozen-count rationale and the read-only delivery rule

## Decisions Made

- A host-specific auxiliary site on the same port is allowed only because it
  shares a listener that already has a dual-form block and a protocol pin.
- The global `servers :8443` form is accepted because the E2E overlay inherits
  that line from the delivery file; the rule is about the listener, not about
  one particular textual location.
- The guard is deliberately not part of `scripts/verify.sh`. That keeps the
  historical `v0.4.3` 26-item evidence and the current 26/8 counts comparable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] The protocol pin can live in the global servers block**
- **Found during:** Task 1
- **Issue:** the E2E overlay inherits `protocols h1 h2` from `deploy/Caddyfile`'s
  `servers :443` block after the port substitution, so a site-block-only check
  would reject the actual rendered fixture.
- **Fix:** record a protocol pin for the port in the `servers` block and accept
  it for site blocks on that port; keep the dual-address rule on the site block.
- **Files modified:** `tests/fixtures/check.sh`, `tests/fixtures/README.md`
- **Verification:** both the rendered overlay and the delivery file pass.
- **Committed in:** `7626468`

**2. [Rule 3 - Blocking] The plan's optional lib.sh and coexist changes were not needed**
- **Found during:** Task 2
- **Issue:** the existing E2E preflight already has a single hook for the
  guard, and adding a wrapper in `lib.sh` or `tests/coexist/run.sh` would create
  a second invocation surface without adding coverage.
- **Fix:** invoke `tests/fixtures/check.sh` directly from `preflight()` and from
  the CI step. No duplicate rule and no extra frozen item were added.
- **Files modified:** `tests/e2e/run.sh`, `.github/workflows/verify.yml`
- **Verification:** `bash tests/e2e/run.sh --preflight-only` passes; bad
  rendered address fails before any listener.
- **Committed in:** `7626468`

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 blocking)
**Impact on plan:** The guard is stricter on the relevant path and leaves the
delivery file and historical evidence untouched.

## Issues Encountered

- A bad-render preflight intentionally fails with exit `2` before starting the
  listener. The useful output is the named port and the missing address form:
  `non-443 port 8443 lacks ':port, host:port' with 'protocols h1 h2'`.
- The first offline verification run was `25/26` because the temporary clone
  lacked the `v0.3.0` tag. Restoring the tag gave `26/26`; the guard itself
  passed in both runs.

## Verification Evidence

- Local and Linux: `FIXTURES: PASS` for every fixture and the delivery file.
- Bad address sample: exit `1`; missing-protocol sample: exit `1`; compliant
  sample: exit `0`.
- Bad rendered overlay: preflight failed before startup with
  `FIXTURE ... FAIL` and `FIXTURES: FAIL`.
- `bash tests/e2e/run.sh --preflight-only`: PASS.
- `PASS=26 FAIL=0`, `VERIFY: PASS`; `CO-1` through `CO-8` PASS,
  `COEXIST: PASS`.
- `shellcheck -S warning tests/e2e/*.sh tests/fixtures/check.sh`: exit `0`.
- Evidence: `.gate/v050/e2e-p5-badrender.log`,
  `.gate/v050/verify-p5.log`, `.gate/v050/coexist-p5.log`.

## Next Phase Readiness

Plan 05-03 can now measure the unknown-SNI baseline without changing the
delivery file or the frozen counts. The posture remains an owner decision and
the plan stops at that checkpoint.

---
*Phase: 05-naive-acl-assertions-and-fixture-guards*
*Completed: 2026-11-07*

## Self-Check: PASSED
