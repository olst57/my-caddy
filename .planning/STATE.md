---
gsd_state_version: "1.0"
milestone: v0.5.0
milestone_name: REALITY closure and E2E regression harness
current_phase: 06
current_phase_name: Stability smoke, evidence, and release decision
status: executing
stopped_at: Phase 6 plans 06-01 and 06-02 complete; smoke and evidence recorded; release decision pending the owner checkpoint.
last_updated: "2026-11-07T12:10:00.000Z"
last_activity: 2026-11-07
last_activity_desc: E2E-08 smoke and evidence/v0.5.0 recorded; CI and the Linux gate green on c8bfe42; publication awaits the owner
state_head: c8bfe42f6a7c964aafaf14ad66fde639608c9d23
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 9
  completed_plans: 8
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

Phase: 06 — Stability smoke, evidence, and release decision
Plan: 06-03 — Re-run both suites and decide on publication (blocking owner
checkpoint)
Status: In progress — 06-01 and 06-02 complete; the decision is pending
Last activity: 2026-11-07 — smoke and evidence measured; CI green on `c8bfe42`

## Performance Metrics

**Velocity:**
- Total plans completed in `v0.5.0`: 8
- `v0.4.3` baseline: 8 plans, ~22 min average, ~3 h total

**By Phase (`v0.5.0`):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 4. REALITY E2E harness | 3 | 3 | — |
| 5. naive/ACL assertions and fixture guards | 3 | 3 | — |
| 6. Stability smoke, evidence, release decision | 2 | 3 | — |

**Recent Trend:**
- Phase 6 has two measured plans. E2E-08 runs 30 serial and 8 concurrent
  requests on both legs with zero failures, and the upstream counters record
  38/38. The redacted evidence set is `evidence/v0.5.0/`, archive hash
  `35e1511a2c571fdb550be2f5cc02fb0c3873db058c891aaa78476a5cf1ddaf0b`.
  CI `verify` and `gate0` are green on `c8bfe42`:
  <https://github.com/olst57/my-caddy/actions/runs/42368473402> and
  <https://github.com/olst57/my-caddy/actions/runs/42368473449>. The offline
  suite is 26/26 and coexistence is 8/8 at that commit.

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
- The unknown-SNI/no-SNI posture is **`reject`** (decided 2026-11-07). The
  delivery file already had no catch-all site and no `tls` fallback, so the
  harness freezes measured behaviour instead of editing the frozen file. A
  later move to `decoy` or `default` is an explicit `deploy/Caddyfile`
  amendment paired with an S7-18 update.
- [Phase 4]: The REALITY E2E harness is a separate fail-closed suite that derives its Caddyfile from deploy/Caddyfile and keeps the 26/8 frozen counts unchanged. — A green run must describe the delivery shape, not a hand-written fixture; the existing gates stay comparable.
- [Phase 4]: Xray 26 needs a test-only finalRules loopback allow, and caddy-l4 writes the dialled destination into PROXY v2. — Both were measured on the Linux host; they make E2E-01 and E2E-03 deterministic without changing production configuration.
- [Phase 4]: Negative controls get a 90-second budget and are classified against both client and server logs. — A wrong UUID can be rejected only after the client's REALITY retry loop exceeds the ordinary 25-second request budget.
- [Phase 5]: The unknown/empty/absent SNI baseline is measured, not asserted. — The owner has not chosen reject, decoy, or default; encoding a posture before the answer would make the suite defend an unchosen behaviour.
- [Phase 5]: `socks_get` clears its per-attempt body, header, output and error files before each request. — An earlier closing-control run left a stale marker behind and could have made an empty reply look successful.
- [Phase 5]: The unknown/empty/absent SNI baseline is **asserted**, not printed. — The posture decision is now `reject`, so a listener that starts presenting a certificate for an unmatched name turns E2E-07 red.
- [Phase 5]: CI is green on the recorded commit `ae5a6f8`; the exact commit also re-ran 26/26 offline, 8/8 coexistence, and 10/10 E2E on `hw-gz`. — The CI status is evidence for the pushed tree, not a substitute for the Linux runtime checks.
- [Phase 6]: Each smoke request builds a complete client unit and nothing is retried. — A reused connection or a silent retry would hide the leak or race the item exists to expose.
- [Phase 6]: The naive smoke target is `203.0.113.10:18082` bound to `lo`, not a loopback address. — The delivery ACL denies `127/8`, so a loopback target would have forced a test-only ACL edit and made E2E-08 describe something other than the delivery shape.
- [Phase 6]: The archived E2E log is a line-selected excerpt of item, posture, control and verdict lines. — The full log carries a third-party certificate transcript, which is not evidence about this repository.
- [Phase 6]: `v0.5.0` publication is a blocking owner checkpoint; no tag exists until it is answered. — The plan makes publication the owner's decision, and moving `v0.4.3` is forbidden either way.

### Pending Todos

- Answer the Phase 6 owner checkpoint: `approved` creates the annotated
  `v0.5.0` tag and lets the release build publish; `hold` records the hold and
  leaves the milestone open.

### Blockers/Concerns

- Byte-identical rebuilds are still not established. The Go patch level is now
  fixed at `1.26.9`, but the same sources produced different amd64 bytes on
  `hw-gz` (`872cae…`) and CI (`c780d1…`); build IDs and host paths still vary.
- The REALITY harness needs a destination whose certificate covers the chosen
  SNI. A mismatched pair reproduces `alert 40`, so the destination is an
  external input, not a fixture.
- arm64 execution of `v0.5.0` is out of scope unless scheduled; the existing
  arm64 claim belongs to `v0.4.3`.
- The `v0.5.0` tag is blocked on the owner checkpoint. Everything the decision
  rests on is measured: 26/26, 8/8, 11/11 E2E, 30/30 and 8/8 smoke on both
  legs, and green CI on `c8bfe42`.

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

Last session: 2026-11-07T12:10:00.000Z
Stopped at: Phase 6 plans 06-01 and 06-02 complete — E2E-08 measured, evidence
archived, CI and the Linux gate green on `c8bfe42`. The publication decision is
the blocking owner checkpoint.
Resume file: .planning/phases/06-stability-smoke-evidence-and-release-decision/06-03-PLAN.md
Previous: .planning/phases/06-stability-smoke-evidence-and-release-decision/06-02-SUMMARY.md
