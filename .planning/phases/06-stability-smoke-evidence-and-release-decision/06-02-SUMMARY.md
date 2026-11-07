---
phase: 06-stability-smoke-evidence-and-release-decision
plan: 02
subsystem: evidence
tags: [redaction, evidence, sha256, index, s7-13]

requires:
  - phase: 06-stability-smoke-evidence-and-release-decision
    provides: the Phase 4-6 run logs on the Linux host
provides:
  - a redacted evidence set whose every file matches its source line for line
  - an index that names the binary, the commit, the counts, and the limits
  - an idempotence check and an archive hash a reader can recompute
affects: [phase-6]

actuals:
  tokens: 4600
  tasks: 3
  commits: [c8bfe42]

tech-stack:
  added: []
  patterns: [script-only evidence, line-count equality, archive hash]

key-files:
  created:
    - evidence/v0.5.0/index.md
    - evidence/v0.5.0/verify-26.log
    - evidence/v0.5.0/coexist-8.log
    - evidence/v0.5.0/e2e-items.log
    - evidence/v0.5.0/smoke-counts.log
    - evidence/v0.5.0/caddy-sha256.txt
  modified:
    - evidence/README.md

key-decisions:
  - "Only scripts/redact-evidence.sh writes the log files; the index is the single hand-written markdown file, because the script skips markdown by design."
  - "The E2E log is archived as a line-selected excerpt of item, posture, control and verdict lines, so a third-party certificate transcript is not published."
  - "The archive hash is computed over the five redacted files only, so adding the index does not silently change the hash it documents."

requirements-completed: [EVID-01]

coverage:
  - id: D1
    description: "Every archived log is produced by the redaction script and has the same line count as its raw source."
    requirement: EVID-01
    verification:
      - kind: manual
        ref: "line counts 29/29, 10/10, 20/20, 6/6, 2/2"
        status: pass
    human_judgment: false
  - id: D2
    description: "A second redaction pass produces byte-identical output."
    requirement: EVID-01
    verification:
      - kind: manual
        ref: "diff -r against .gate/v050/redact-2: empty"
        status: pass
    human_judgment: false
  - id: D3
    description: "The index names the commit, the binary hash, the counts, and what the set does not prove."
    requirement: EVID-01
    verification:
      - kind: manual
        ref: "evidence/v0.5.0/index.md"
        status: pass
    human_judgment: false
  - id: D4
    description: "The redaction and credential scans are green on the committed tree."
    requirement: EVID-01
    verification:
      - kind: gate
        ref: "S7-12 and S7-13 on the Linux test host at c8bfe42"
        status: pass
    human_judgment: false
  - id: D5
    description: "Raw logs stay out of the repository."
    requirement: EVID-01
    verification:
      - kind: manual
        ref: ".gate/ is gitignored; git status lists only the evidence copies"
        status: pass
    human_judgment: false

duration: 1h
completed: 2026-11-07
status: complete
---

# Phase 6 Plan 2: Evidence Capture and Index Summary

**Five redacted files, each line-for-line identical to its source, with an
index that states the limits instead of implying more**

## Performance

- **Duration:** ~1 h
- **Completed:** 2026-11-07
- **Tasks:** 3 (capture, redact, index)
- **Files created:** 6

## Accomplishments

- Captured five raw artifacts under `.gate/v050/capture/`, each carrying a
  provenance line with the run time, the commit, the binary hash, and the host
  class, so a copy cannot drift away from the run it describes.
- Ran `bash scripts/redact-evidence.sh .gate/v050/capture evidence/v0.5.0`
  and confirmed every output has the same line count as its source:
  `verify-26.log` 29/29, `coexist-8.log` 10/10, `e2e-items.log` 20/20,
  `smoke-counts.log` 6/6, `caddy-sha256.txt` 2/2.
- Ran the redaction a second time into a scratch directory; `diff -r` was
  empty, so the output is idempotent.
- Wrote `evidence/v0.5.0/index.md`: commit `2797575`, binary sha256
  `872caeee23f804fcb2991e26f3c7fe9526eb8a1d5003d4dedcc280c95d762f1d`, the
  four smoke lines, the counts, the negative control, and an explicit
  "what this set does not prove" section.
- Added the `v0.5.0` section to `evidence/README.md` with the same line-count,
  idempotence, and hash facts, plus the two differences from the `v0.4.3` set.

## Provenance

| Field | Value |
|---|---|
| Commit | `2797575` (code); evidence committed at `c8bfe42` |
| Run date | 2026-11-07, 11:23–11:25 UTC |
| Host class | `linux-amd64`, root |
| Caddy binary | `872caeee23f804fcb2991e26f3c7fe9526eb8a1d5003d4dedcc280c95d762f1d` |
| Xray | 26.10.29 |
| Raw input | `.gate/v050/capture/` (gitignored) |
| Script | `bash scripts/redact-evidence.sh <IN_DIR> <OUT_DIR>` |
| Archive hash | `35e1511a2c571fdb550be2f5cc02fb0c3873db058c891aaa78476a5cf1ddaf0b` |

The hash is `sha256sum` over the five redacted files, piped to `sha256sum`;
`index.md` is excluded because it is hand-written and would otherwise make the
documented hash change whenever prose changes.

## Contents

| File | Lines | Records |
|---|---:|---|
| `verify-26.log` | 29 | 26 items, `PASS=26 FAIL=0`, `VERIFY: PASS` |
| `coexist-8.log` | 10 | `CO-1`…`CO-8`, `COEXIST: PASS` |
| `e2e-items.log` | 20 | 11 items, three `E2E-07 BASELINE` lines, two positive controls, `E2E: PASS` |
| `smoke-counts.log` | 6 | four `SMOKE` lines and the upstream corroboration |
| `caddy-sha256.txt` | 2 | the binary used by the run |

## Files Created/Modified

- `evidence/v0.5.0/` - five redacted files plus `index.md`
- `evidence/README.md` - the `v0.5.0` section, with hashes and differences

## Deviations from Plan

**1. [Rule 2 - Privacy] The E2E archive is a line-selected excerpt**
- **Found during:** Task 2
- **Issue:** the full E2E log contains the destination's certificate transcript
  and hex dumps that are not evidence about this repository, and publishing
  them would add third-party material to the tree.
- **Fix:** the capture keeps every item, posture, control and verdict line and
  drops only the verbose certificate body; the full log stays in `.gate/`.
- **Impact:** a reader can still see every assertion and its verdict, but not
  the raw certificate fields; the index says so.

**2. [Rule 1 - Decision] There is no `host.txt` this round**
- **Found during:** Task 1
- **Issue:** the plan's file list implies a host record, while the `v0.4.3`
  set had a separate `host.txt`.
- **Fix:** the host class, commit, and binary hash are on the first line of
  every file, so a second copy would be redundant.
- **Impact:** one fewer file; nothing is lost, and the index repeats the facts.

---

**Total deviations:** 2 (1 privacy, 1 decision)
**Impact on plan:** the evidence set is complete, reproducible, and does not
publish third-party material.

## Issues Encountered

- `redact-evidence.sh` skips `*.md` by design, so `index.md` cannot be produced
  by the script. That is stated in both the index and the README rather than
  presented as script output.
- The `v0.4.3` set has no `index.md`; its index is the README section. The
  `v0.5.0` set has one because the plan asked for it, and the README links the
  two facts together.

## Verification Evidence

- `redact-evidence.sh: 5 file(s) redacted into evidence/v0.5.0`, stderr empty,
  exit `0`.
- Line counts equal for all five files; second pass `diff -r` empty.
- `ITEM S7-12 PASS` and `ITEM S7-13 PASS` on the Linux test host at `c8bfe42`.
- `PASS=26 FAIL=0` and `CO-1`…`CO-8` PASS re-run at `c8bfe42` on the same
  binary, so the evidence commit itself does not regress the gate.
