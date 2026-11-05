---
phase: 02-close-runtime-acceptance
plan: 02
subsystem: testing
tags: [coexist, probe-resistance, ci]

requires:
  - phase: 02
    plan: 01
    provides: the recorded REALITY and decoy posture

provides:
  - CO-8 decoy/target disjointness guard
  - eight-item coexistence verdict
  - CI and docs that describe eight items

affects:
  - phase-02 plan 03
  - phase-03

actuals:
  tokens: 0
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns:
    - "A guard that can parse nothing must fail, not pass by default"

key-files:
  created: []
  modified:
    - tests/coexist/run.sh
    - .github/workflows/verify.yml
    - docs/VERIFY.md

key-decisions:
  - "Parse probe_resistance from comment-stripped Caddyfile lines, not from prose."
  - "Fail CO-8 on an empty value as well as on equality."

patterns-established:
  - "Every new runtime item ships with a mutation that makes exactly that item red."

requirements-completed: [RTA-02]

coverage:
  - id: D1
    description: "CO-8 fails when the decoy equals the tunnel target"
    requirement: "RTA-02"
    verification:
      - kind: other
        ref: "hw-gz mutation: CO_TARGET=example.com:443 -> ITEM CO-8 FAIL, probe_resistance=[example.com] target=[example.com]"
        status: pass
    human_judgment: false
  - id: D2
    description: "The verdict requires eight passes"
    requirement: "RTA-02"
    verification:
      - kind: other
        ref: "hw-gz clean run: CO-1..CO-8 PASS, COEXIST: PASS"
        status: pass
    human_judgment: false
  - id: D3
    description: "CI and docs describe eight items"
    requirement: "RTA-02"
    verification:
      - kind: other
        ref: "CI run 42054615674 logs: ITEM CO-8 PASS"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-11-05
status: checkpoint-pending
---

# Phase 2: Close Runtime Acceptance — Plan 02 Summary

The v0.4.0 decoy/target collision is now a red test, and the repository counts
eight coexistence items.

## Performance

- **Duration:** 35 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-05
- **Tasks:** 3 automatic, one acceptance bullet deferred

## Implementation

- `decoy_domain()` strips `#` comments from `deploy/Caddyfile` and prints the
  first argument of the active `probe_resistance` directive. The file mentions
  the keyword in prose above the directive, so a naive grep would parse a
  sentence.
- `TARGET_HOST` is derived from `CO_TARGET` with `${TARGET%%:*}`.
- CO-8 compares both values case-insensitively and requires both to be
  non-empty. The failure line prints both values.
- The verdict is `PASSED -eq 8`; the header list and the CI comment name
  `CO-1..CO-8`.

## Evidence

| Run | Tree | Result |
|-----|------|--------|
| hw-gz, `d3b4f67` | delivery config | `ITEM CO-1..CO-8 PASS`, `COEXIST: PASS` |
| hw-gz mutation | `CO_TARGET=example.com:443` | `ITEM CO-8 FAIL`, `probe_resistance=[example.com] target=[example.com]`, `COEXIST: FAIL` |
| hw-gz, `d3b4f67` | offline verifier | `PASS=26 FAIL=0`, `VERIFY: PASS` |
| CI run [42054615674](https://github.com/olst57/my-caddy/actions/runs/42054615674) | `d3b4f67` | `offline` success, `coexist` success with `ITEM CO-8 PASS` |

The mutation run is the sensitivity control: the same suite passes with
different values and fails when they collide. Ports 443/19098/8080 were free
after every run.

## Deferred, With Reason

Task 3 also asks for the `example.com` row in `deploy/PLACEHOLDERS.md` to state
the disjointness rule. That file sits in the frozen `deploy/` tree; S7-18
rejects any change there beyond `protocols h1 h2`, and the edit was reverted
after `ITEM S7-18 FAIL`. The rule is stated in `docs/VERIFY.md` and
`docs/XRAY.md` instead; the register row waits on the same freeze decision that
02-01 records.

## Next Phase Readiness

- 02-03 needs the v0.4.0 acceptance report mapped to dispositions.
- The freeze decision is independent of that work.
