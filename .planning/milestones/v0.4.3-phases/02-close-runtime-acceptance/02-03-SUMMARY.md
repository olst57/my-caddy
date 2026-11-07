---
phase: 02-close-runtime-acceptance
plan: 03
subsystem: docs
tags: [rta, dispositions, closure]

requires:
  - phase: 02
    plan: 02
    provides: CO-8 and the eight-item suite

provides:
  - one disposition per v0.4.0 FAIL and NOT-TESTED row
  - a pointer from docs/VERIFY.md to the closure record

affects:
  - phase-03

actuals:
  tokens: 0
  tasks: 3
  commits: 0

tech-stack:
  added: []
  patterns:
    - "A closure table is derived from the grader's verdicts, not from a plan's example IDs"

key-files:
  created:
    - .gate/v043/RTA-DISPOSITIONS.md
  modified:
    - docs/VERIFY.md

key-decisions:
  - "Use GRADE-RTA.md as the row source: the plan's example ID list did not match it."
  - "Only two rows are fixed, and each names the item that fails when the defect returns."

patterns-established:
  - "Deferred rows state the measurement that would close them, not the intent to run it someday."

requirements-completed: [RTA-03]

coverage:
  - id: D1
    description: "The row set equals the grader's FAIL plus NOT-TESTED set"
    requirement: "RTA-03"
    verification:
      - kind: other
        ref: ".gate/v043/RTA-DISPOSITIONS.md rows RTA-8/11/12/13/14/15/16/17/20"
        status: pass
    human_judgment: false
  - id: D2
    description: "Each row has one disposition and one evidence pointer"
    requirement: "RTA-03"
    verification:
      - kind: other
        ref: "Tally section: fixed 2, documented 5, deferred 2"
        status: pass
    human_judgment: false
  - id: D3
    description: "docs/VERIFY.md points at the table"
    requirement: "RTA-03"
    verification:
      - kind: other
        ref: "docs/VERIFY.md §The v0.4.0 acceptance closure record"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-11-05
status: complete
---

# Phase 2: Close Runtime Acceptance — Plan 03 Summary

Every failed or unrun v0.4.0 acceptance item now has one auditable
disposition, and the table is linked from the main verification document.

## Performance

- **Duration:** 25 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-05
- **Tasks:** 3

## Row Source Correction

The plan named `RTA-2, RTA-6, RTA-8, RTA-12, RTA-13, RTA-15, RTA-16, RTA-17,
RTA-18` and said to verify rather than assume. Checked against
`.gate/release/GRADE-RTA.md`, three of those are PASS (RTA-2, RTA-6, RTA-18)
and three real failures were missing (RTA-8, RTA-14, RTA-20). The table uses
the grader's set: RTA-8, RTA-11, RTA-12, RTA-13, RTA-14, RTA-15, RTA-16,
RTA-17, RTA-20 — 7 FAIL plus 2 NOT-TESTED.

## Dispositions

| Disposition | Count | Rows |
|-------------|-------|------|
| fixed | 2 | RTA-16, RTA-17 |
| documented limitation | 5 | RTA-8, RTA-11, RTA-12, RTA-15, RTA-20 |
| deferred | 2 | RTA-13, RTA-14 |

- RTA-16 is fixed by CO-6 replacing a control whose two branches could both
  hold.
- RTA-17 is fixed by the single scratch directory and `EXIT` trap in
  `scripts/verify.sh:103-108` (commit `ef99d27`), plus a re-check on `hw-gz`
  that `/tmp/tmp.YA6WTjpwd8` no longer exists.
- RTA-13 and RTA-14 stay deferred: REALITY has not been measured against a
  replaced destination, and the placeholder pair cannot stand in for that.

## Verification

- Row count 9 equals 7 FAIL + 2 NOT-TESTED in `GRADE-RTA.md`.
- `grep -n 'RTA-DISPOSITIONS' docs/VERIFY.md` matches.
- The tally in `docs/VERIFY.md` matches the table (2 / 5 / 2).

## Next Phase Readiness

- Phase 2 has one open decision left: the `deploy/` freeze question that
  02-01 and 02-02 both hit.
- Phase 3 can start once that decision is recorded.
