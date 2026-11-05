---
phase: 01-freeze-verification-gate
plan: 01
subsystem: testing
tags: [bash, caddy, ci, verification, naive, reality]

requires:
  - phase: none
    provides: initial verification slice in the working tree

provides:
  - 26-item offline verifier committed
  - 7-item coexistence suite committed
  - verify.yml CI entry point committed
  - documentation aligned with the frozen item set

affects:
  - phase-01 plan 02
  - phase-01 plan 03
  - phase-02

actuals:
  tokens: 0
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Static self-consistency check before committing a verification gate"
    - "Separate verification-slice commit from planning-doc commit"

key-files:
  created:
    - .github/workflows/verify.yml
    - tests/coexist/run.sh
    - tests/coexist/naive-tunnel.py
    - tests/coexist/site-backend.py
    - tests/coexist/stub-upstream.py
  modified:
    - scripts/verify.sh
    - docs/VERIFY.md
    - docs/BUILD.md
    - README.md

key-decisions:
  - "Commit the verification slice before any runtime evidence run."
  - "Do not stage .codex/ or .gate/ with the source slice."

patterns-established:
  - "A gate commit is preceded by count, set-equality, syntax, and secret checks."

requirements-completed: [VER-01, VER-02, VER-03]

coverage:
  - id: D1
    description: "Verification slice committed as one reviewable source commit"
    requirement: "VER-01"
    verification:
      - kind: other
        ref: "git show --stat 05e954b"
        status: pass
    human_judgment: false
  - id: D2
    description: "26 unique item IDs, S3-13 mutation cases, and shell syntax verified statically"
    requirement: "VER-02"
    verification:
      - kind: other
        ref: "PowerShell set comparison + Git Bash bash -n"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-11-05
status: complete
---

# Phase 1: Freeze the Verification Gate — Plan 01 Summary

The verification slice is committed as one reviewable change, with its
self-consistency proven before the commit.

## Performance

- **Duration:** 15 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-05
- **Tasks:** 3
- **Files modified:** 18

## Accomplishments

- Classified every changed and untracked verification file against VER-01..03.
- Proved `EXPECTED_ITEMS=26`, 26 unique `ITEM_LIST` IDs, 26 unique emitted IDs,
  the three S3-13 mutation cases, and CO-1..CO-7 presence.
- Ran `bash -n` on `scripts/verify.sh` and `tests/coexist/run.sh` through Git
  Bash; both passed.
- Scanned the new files for credential, UUID, and key patterns; no hits.
- Committed the slice as `05e954b`.

## Task Commits

1. **Task 1–3: Freeze the verification slice** - `05e954b` (verify)

## Files Created/Modified

- `.github/workflows/verify.yml` — offline and coexistence CI jobs.
- `tests/coexist/` — live three-role suite and fixtures.
- `scripts/verify.sh` — 26-item offline verifier.
- `docs/VERIFY.md`, `docs/BUILD.md`, `README.md` — aligned documentation.

## Decisions & Deviations

- No Linux host is available on this machine (no WSL, no Docker, no native
  bash for execution). Only static checks ran here; 01-02 remains the runtime
  plan.
- `.codex/` and `.gate/` were deliberately not staged.

## Issues Encountered

- `grep -c` counts lines, not matches. The item set was verified with a
  set comparison in PowerShell instead.

## Next Phase Readiness

- 01-02 needs a Linux host with root and the built binary.
- The frozen commit is ready to push for 01-03.
