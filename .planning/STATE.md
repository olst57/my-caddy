---
gsd_state_version: "1.0"
milestone: v0.5.0
milestone_name: REALITY closure and E2E regression harness
current_phase: 4
current_phase_name: REALITY E2E harness
status: executing
stopped_at: v0.5.0 planned; Phase 4 ready to execute on the Linux host.
last_updated: "2026-11-07T02:11:35.279Z"
last_activity: 2026-11-07
last_activity_desc: v0.5.0 phases 4-6 planned (9 plans)
state_head: 5741b1993b1ebc7e0759f94a29de198a9f37740b
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 9
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-06)

**Core value:** Three roles coexist on one binary, one Caddyfile, and one
`:443` without interference, and that claim is reproducible from evidence.
**Current focus:** Milestone `v0.5.0` — turn the hand-run REALITY round into
`tests/e2e/`, close the naive/ACL assertion gaps, and archive redacted
evidence. `v0.4.3` is delivered and frozen; its tag, assets and evidence are
read-only inputs.

## Current Position

Phase: 4 (REALITY E2E harness) — READY TO EXECUTE
Plan: 1 of 3 (04-01 scaffold)
Status: Ready to execute
Last activity: 2026-11-07 — v0.5.0 planning complete (9 plans)

## Performance Metrics

**Velocity:**
- Total plans completed in `v0.5.0`: 0
- `v0.4.3` baseline: 8 plans, ~22 min average, ~3 h total

**By Phase (`v0.5.0`):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 4. REALITY E2E harness | 0 | 3 | — |
| 5. naive/ACL assertions and fixture guards | 0 | 3 | — |
| 6. Stability smoke, evidence, release decision | 0 | 3 | — |

**Recent Trend:**
- No `v0.5.0` plan has run yet; the `v0.4.3` trend was stable.

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
- The 2026-11-06 REALITY round is a **measurement**, not a guard: it proved
  the handshake, the masquerade certificate, PROXY v2, and the three negative
  controls by hand and kept no raw capture. `v0.5.0` converts it into
  `tests/e2e/` rather than re-running it by hand.
- The E2E stack runs on `8443`/`19099`/`18080` because the test host's `:443`
  is production. The delivery address shape is replicated, not the delivery
  port.
- Key material is injected from the environment and a missing variable is a
  hard failure; there is no skip path that could report PASS.
- The frozen counts stay 26 offline and 8 coexistence. New guards are
  separate checks, not additional items, so `v0.4.3` evidence stays
  comparable.
- The unknown-SNI/no-SNI posture is **undecided**; Phase 5 measures the
  baseline first and stops at a checkpoint until the owner picks one of
  default certificate, dedicated decoy, or reject.

### Pending Todos

- Execute Phase 4 (04-01 → 04-03) on the Linux host; upload the Caddy and
  Xray binaries from the local machine rather than downloading them there.
- Phase 5 waits on the E2E-07 posture decision at its checkpoint.
- Phase 6 publication waits on explicit owner approval.

### Blockers/Concerns

- Byte-identical rebuilds are still not established. The Go patch level is now
  fixed at `1.26.9`, but the same sources produced different amd64 bytes on
  `hw-gz` (`872cae…`) and CI (`c780d1…`); build IDs and host paths still vary.
- The REALITY harness needs a destination whose certificate covers the chosen
  SNI. A mismatched pair reproduces `alert 40`, so the destination is an
  external input, not a fixture.
- E2E-07 is open by design; the plan must not encode a posture the owner has
  not chosen.
- arm64 execution of `v0.5.0` is out of scope unless scheduled; the existing
  arm64 claim belongs to `v0.4.3`.

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
Stopped at: v0.5.0 planning complete; Phase 4 ready to execute on the Linux
host.
Resume file: .planning/phases/04-reality-e2e-harness/04-01-PLAN.md
