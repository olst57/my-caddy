---
gsd_state_version: "1.0"
milestone: v0.5.0
milestone_name: REALITY closure and E2E regression harness
current_phase: 06
current_phase_name: Stability smoke, evidence, and release decision
status: complete
stopped_at: README rewritten for v0.5.0, the release set cut to v0.5.0 plus v0.4.3, and the prune executed on the remote.
last_updated: "2026-11-11T13:53:46.775Z"
last_activity: 2026-11-11
last_activity_desc: Moved upstream-watch to the 1st and 15th, sourced the two module pins from the forks, and made both watch workflows stay quiet while an issue is open
state_head: 8a584d8b6d05e0b80f5e9b9959bb0c440072700e
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 9
  completed_plans: 9
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
Plan: 06-03 — Re-run both suites and decide on publication
Status: Complete — owner approved, `v0.5.0` tagged and published
Last activity: 2026-11-11 — upstream-watch moved to the 1st and 15th, the two
module pins now come from the forks, and both watch workflows stay quiet while
their tracking issue is open

## Performance Metrics

**Velocity:**
- Total plans completed in `v0.5.0`: 9
- `v0.4.3` baseline: 8 plans, ~22 min average, ~3 h total

**By Phase (`v0.5.0`):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 4. REALITY E2E harness | 3 | 3 | — |
| 5. naive/ACL assertions and fixture guards | 3 | 3 | — |
| 6. Stability smoke, evidence, release decision | 3 | 3 | — |

**Recent Trend:**
- The milestone is delivered. E2E-08 ran 30 serial and 8 concurrent requests on
  both legs with zero failures, the upstream counters recorded 38/38, and the
  redacted evidence set is `evidence/v0.5.0/` (archive hash
  `35e1511a2c571fdb550be2f5cc02fb0c3873db058c891aaa78476a5cf1ddaf0b`).
  CI `verify` and `gate0` are green on `d3c19c3`:
  <https://github.com/olst57/my-caddy/actions/runs/42369088803> and
  <https://github.com/olst57/my-caddy/actions/runs/42369088807>. The annotated
  tag `v0.5.0` points at that commit; release 437547357 has four assets and the
  `build` workflow run 42370444867 succeeded.

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
- [Phase 6]: `v0.5.0` publication was approved by the owner on 2026-11-07 and the annotated tag points at `d3c19c3`. — The plan makes publication the owner's decision; the approval is recorded in `ROADMAP.md` with the gate it rests on.
- [Phase 6]: The published amd64 asset (`c780d1d6…`) is the binary the CI `offline` job built at the same commit, so the two suites gated exactly that hash. — CI reproduces the same bytes for the same inputs; the local test build differs (`872caeee…`), which is why the evidence index names both.
- [Phase 6]: Executing the 53 MB release asset on `hw-gz` is deferred, not claimed. — The release CDN measured 5–35 KB/s from the authoring machine and about 19 KB/s from the test host.
- [Phase 6 follow-up]: Upstream drift is **reported**, never auto-applied. — A new Caddy tag can break the read-idle-timeout patch and both forks need syncing, so a bump stays a reviewed change; the daily watcher opens one issue and does not build.
- [Phase 6 follow-up]: `forwardproxy` is watched on its `naive` branch, not `master`. — The pin is a `naive` commit; master stopped in 2024 and diverged by a README-only edit, so a master comparison reported a permanent false positive.
- [Phase 6 follow-up]: Module forks are fast-forwarded daily, but only with an explicit `FORK_SYNC_TOKEN`; the pin never moves automatically. — `GITHUB_TOKEN` cannot write to another repository, and a synced fork head must not change today's binary.
- [Quick 261111-u68]: The upstream watch runs on the 1st and 15th, reads both module SHAs from this project's forks, and stays silent while its tracking issue is open; `fork-sync` follows the same no-repeat rule. — Daily comments were noise, and the forks are the source of truth because `fork-sync` keeps them current.

### Pending Todos

- None. The milestone is delivered; follow-ups are in Deferred Items.

### Blockers/Concerns

- Byte-identical rebuilds are still not established. The Go patch level is now
  fixed at `1.26.9`, but the same sources produced different amd64 bytes on
  `hw-gz` (`872cae…`) and CI (`c780d1…`); build IDs and host paths still vary.
- The REALITY harness needs a destination whose certificate covers the chosen
  SNI. A mismatched pair reproduces `alert 40`, so the destination is an
  external input, not a fixture.
- arm64 execution of `v0.5.0` is out of scope unless scheduled; the existing
  arm64 claim belongs to `v0.4.3`.
- The published amd64 asset was not executed on `hw-gz`. Its hash matches the
  CI-built binary that both suites gated, but a runtime run on the release
  artifact is still open; the CDN transfer was too slow to complete.

## Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 261108-rdp | Rewrite the public README and converge the release set to v0.5.0 and v0.4.3 | 2026-11-08 | 348734e, 0934f18 | complete | [261108-rdp-rewrite-readme-and-prune-releases](./quick/261108-rdp-rewrite-readme-and-prune-releases/) |
| 261107-fksync | Fast-forward the module forks without moving a pin | 2026-11-07 | 9b73137 | complete | [261107-fksync-sync-module-forks](./quick/261107-fksync-sync-module-forks/) |
| 261107-uwu | Report when a pinned input falls behind upstream | 2026-11-07 | 2c894df | complete | [261107-uwu-report-upstream-drift](./quick/261107-uwu-report-upstream-drift/) |
| 261106-wsw | Pin Go 1.26.9 to match the official naiveproxy Caddy build | 2026-11-07 | decb4cf | complete | [261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici](./quick/261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici/) |
| 261106-tfx | Close the v0.4.3 follow-ups: pin fork SHAs, execute arm64, conclude licenses | 2026-11-06 | db05ba0 | complete | [261106-tfx-close-v0-4-3-follow-ups-pin-fork-shas-ex](./quick/261106-tfx-close-v0-4-3-follow-ups-pin-fork-shas-ex/) |
| 261111-u68 | Run the upstream watch twice monthly from the forks and stay quiet while an issue is open | 2026-11-11 | 8a584d8 | complete | [261111-u68-change-the-upstream-watch-workflow-to-ru](./quick/261111-u68-change-the-upstream-watch-workflow-to-ru/) |

## Deferred Items

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| Build | Byte-identical rebuilds | Open — inputs fixed, but `hw-gz` and CI produced different amd64 bytes | 2026-11-07 | post-v0.4.3 |
| Release | Execute the published `v0.5.0` amd64 asset on `hw-gz` | Open — asset hash matches the CI-gated binary, but the 53 MB download measured 5–35 KB/s | 2026-11-07 | v0.5.0 follow-up |
| Build | Pin `FWDPROXY_SHA` and `L4_SHA` to the release receipt | Closed — `pins/build-inputs.env` (`0ef98bb`) | 2026-11-06 | v0.4.3 follow-up |
| Runtime | arm64 execution | Closed — released asset ran on `ubuntu-24.04-arm` (run 42228779590) | v0.4.2 | v0.4.3 follow-up |
| Protocol | HTTP/3 on `:443` | Removed by design | 2026-11-04 | v0.4.3 |
| Docs | Licence/SPDX conclusions | Closed — `docs/LICENSING.md` plus `LICENSES/`; repository stays proprietary | v0.4.2 | v0.4.3 follow-up |

## Session Continuity

Last session: 2026-11-07T14:05:00.000Z
Stopped at: `v0.5.0` published; upstream watcher and fork-sync both added. The
caddy-l4 fork was fast-forwarded to `1da0f2bd…` while the build pin stays at
`96e1a6bf…`, and CI `build` proved the pin still compiles.
Resume file: .planning/phases/06-stability-smoke-evidence-and-release-decision/06-03-SUMMARY.md
Previous: .planning/phases/06-stability-smoke-evidence-and-release-decision/06-02-SUMMARY.md
