---
gsd_state_version: "1.0"
milestone: v0.4.3
milestone_name: Verification gate
current_phase: 3
current_phase_name: Publish v0.4.3
status: complete
stopped_at: quick task `261106-wsw` complete; the delivery toolchain is pinned at `decb4cf`.
last_updated: "2026-11-06T16:11:17.895Z"
last_activity: 2026-11-07
last_activity_desc: "pinned Go 1.26.9 to the official naiveproxy toolchain"
state_head: decb4cf36b58492961565397bce1ce08f098a3a7
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 8
  completed_plans: 8
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-06)

**Core value:** Three roles coexist on one binary, one Caddyfile, and one
`:443` without interference, and that claim is reproducible from evidence.
**Current focus:** Milestone `v0.4.3` delivered; the delivery toolchain now
matches the official naiveproxy Caddy build at `go1.26.9`.

## Current Position

Phase: 3 of 3 (Publish v0.4.3) — complete
Plan: 2 of 2 complete
Status: Phase complete — milestone delivered; post-release toolchain pin applied
Last activity: 2026-11-07 — quick task `261106-wsw` pinned `go1.26.9` from the
official naiveproxy Caddy binary. The pinned toolchain rebuilt on `hw-gz` and
passed 26 + 8 items; CI verify, build and gate0 are green at `decb4cf`.

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: ~22 min
- Total execution time: ~3 h

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Freeze the verification gate | 2 | 3 | 12min |
| 2. Close runtime acceptance | 3 | 3 | 27min |
| 3. Publish v0.4.3 | 2 | 2 | 48min |

**Recent Trend:**
- Last 5 plans: 25min, 27min, 40min, 55min
- Trend: Stable

*Updated after each plan completion.*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions
affecting current work:

- The milestone is `v0.4.3`, not a new product direction.
- The three roles must stay on one binary, one Caddyfile, and one `:443`.
- Evidence is split by host: Windows authors, Linux executes.
- Option A was confirmed on 2026-11-05: the `deploy/` freeze keeps exactly one
  amendment, and the REALITY/decoy rules live in `docs/`.
- `v0.4.3` is tagged on `b60f042`, the head of `main` after PR #1.
- Evidence describes the **downloaded release asset**, not the local build,
  because `scripts/build.sh` resolves the two fork SHAs at build time.
- Both fork commits are now pinned in `pins/build-inputs.env`; a CI build at
  `0ef98bb` reproduced the published amd64 sha256, so the receipt is a build
  input rather than a post-hoc record.
- The arm64 claim is earned by execution, not inspection: the released asset
  was run on `ubuntu-24.04-arm` and passed the same two suites.
- The repository is `LicenseRef-Proprietary` and all rights reserved; the
  third-party obligations are recorded, not relicensed.
- The delivery build pins Go to `1.26.9`, the patch level measured in the Go
  build metadata of the official naiveproxy Caddy `v2.11.7-naive2` binary.
  `PIN_GO_VERSION` is not overridable, and `v0.4.3` remains `go1.26.10`.

### Pending Todos

None. The milestone's plans are all complete.

### Blockers/Concerns

- Byte-identical rebuilds are still not established. The Go patch level is now
  fixed at `1.26.9`, but the same sources produced different amd64 bytes on
  `hw-gz` (`872cae…`) and CI (`c780d1…`); build IDs and host paths still vary.
- The REALITY handshake remains deferred: the shipped pair is a placeholder and
  the acceptance run measured `alert 40`.

## Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 261106-wsw | Pin Go 1.26.9 to match the official naiveproxy Caddy build | 2026-11-07 | decb4cf | complete | [261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici](./quick/261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici/) |
| 261106-tfx | Close the v0.4.3 follow-ups: pin fork SHAs, execute arm64, conclude licenses | 2026-11-06 | db05ba0 | complete | [261106-tfx-close-v0-4-3-follow-ups-pin-fork-shas-ex](./quick/261106-tfx-close-v0-4-3-follow-ups-pin-fork-shas-ex/) |

## Deferred Items

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| Build | Byte-identical rebuilds | Open — inputs fixed, but `hw-gz` and CI produced different amd64 bytes | 2026-11-07 | post-v0.4.3 |
| Build | Pin `FWDPROXY_SHA` and `L4_SHA` to the release receipt | Closed — `pins/build-inputs.env` (`0ef98bb`) | 2026-11-06 | v0.4.3 follow-up |
| Runtime | arm64 execution | Closed — released asset ran on `ubuntu-24.04-arm` (run 42228779590) | v0.4.2 | v0.4.3 follow-up |
| Protocol | HTTP/3 on `:443` | Removed by design | 2026-11-04 | v0.4.3 |
| Docs | Licence/SPDX conclusions | Closed — `docs/LICENSING.md` plus `LICENSES/`; repository stays proprietary | v0.4.2 | v0.4.3 follow-up |

## Session Continuity

Last session: 2026-11-07
Stopped at: quick task `261106-wsw` complete; toolchain pinned at `decb4cf`.
Resume file: .planning/quick/261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici/261106-wsw-SUMMARY.md
