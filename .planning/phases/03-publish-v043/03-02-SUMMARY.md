---
phase: 03-publish-v043
plan: 02
subsystem: evidence
tags: [redaction, evidence, archive]

requires:
  - phase: 02
    plan: 03
    provides: the closure record and the 8-item suite

provides:
  - evidence/v0.4.3/ redacted copy of the capture set
  - evidence/README.md section with method, counts, and hash

affects:
  - phase-03 plan 01

actuals:
  tokens: 0
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A redaction guard that disagrees with its own rewrite rules fails closed; fix the guard, keep the rules"

key-files:
  created:
    - evidence/v0.4.3/ci-runs.txt
    - evidence/v0.4.3/coexist-8.log
    - evidence/v0.4.3/host.txt
    - evidence/v0.4.3/verify-26.log
  modified:
    - evidence/README.md
    - scripts/redact-evidence.sh

key-decisions:
  - "Ran the archive before 03-01 because the tag needs user permission, and pinned it to one commit."
  - "Narrowed the survivor scan to exempt exactly `PASS=<n> FAIL=<n>`."
  - "Added <HOST-8> for the bare machine name that no domain scan can see."

patterns-established:
  - "A redacted archive states its line counts, idempotence, and hash in the index, not in prose alone."

requirements-completed: [REL-02]

coverage:
  - id: D1
    description: "The archive is a redacted copy with matching line counts"
    requirement: "REL-02"
    verification:
      - kind: other
        ref: "wc -l per file: 8/8, 9/9, 20/20, 28/28"
        status: pass
    human_judgment: false
  - id: D2
    description: "The archive is reproducible and stable"
    requirement: "REL-02"
    verification:
      - kind: other
        ref: "second run into /tmp/redact2, diff -r empty"
        status: pass
    human_judgment: false
  - id: D3
    description: "No credential, UUID, public address or host identity survives"
    requirement: "REL-02"
    verification:
      - kind: other
        ref: "grep scan over evidence/v0.4.3: none; host name now <HOST-8>"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-11-05
status: complete
---

# Phase 3: Publish v0.4.3 — Plan 02 Summary

The capture set is now publishable: four files, token-only differences, stable
under a second run, with the machine name aliased.

## Performance

- **Duration:** 40 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-05
- **Tasks:** 3

## Ordering Deviation

The plan depends on 03-01, which needs permission to push `main` and create the
tag. That permission is not available, so the archive was built first and
pinned to commit `e5f5abd`, the commit the runs were captured from. When the
tag lands, the archive is still valid if the tag points at that commit or a
descendant that does not change `deploy/` or `tests/coexist/`; otherwise it has
to be regenerated, which is one command.

## Capture Set

| File | Lines | Content |
|------|-------|---------|
| `ci-runs.txt` | 8 | five green runs, two negative controls, the pull request |
| `coexist-8.log` | 9 | `ITEM CO-1`…`CO-8`, `COEXIST: PASS` |
| `host.txt` | 20 | commit, uid, binary sha256, four socket samples, aliased host |
| `verify-26.log` | 28 | 26 `ITEM` lines, `PASS=26 FAIL=0`, `VERIFY: PASS` |

`RTA-DISPOSITIONS.md` stays in `.gate/v043/`: the script skips `*.md` by design,
and the file has no address, UUID, userinfo or credential token.

## Two Script Findings

1. The survivor scan flagged the verifier's counter line as a keyed credential.
   The rewrite rules already left that line alone, because a bare `PASS` has no
   key prefix, so the guard and the rules disagreed. The guard now exempts
   exactly the counter shape: line number, `PASS`, a number, `FAIL`, a number.
   A keyed value under `PASSWORD`, `DB_PASS` or a non-numeric `PASS` is still
   caught.
2. `uname -a` prints the machine name, which has no dot, so neither the
   allowlist nor the domain scan ever sees it. `<HOST-8>` was added to the alias
   map, and the archived line now reads `Linux <HOST-8> 6.8.0-136-generic …`.

## Verification

- `redact-evidence.sh: 4 file(s) redacted into evidence/v0.4.3`, exit 0.
- Line counts equal for all four files; `diff -r` against a second run is empty.
- Archive hash `cf787b6b6d1a6e657677a4f83e6ab3e9d5f41bc1bcf75deaac05e1826bc3fe14`.
- Scan: no IPv4 outside loopback, no UUID, no userinfo, and the only
  host-shaped tokens are the C2 module paths, the kernel version and the
  version string.

## Next Phase Readiness

- 03-01 still needs merge and tag permission; nothing else blocks it.
