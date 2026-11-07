---
gsd_state_version: "1.0"
milestone: v0.5.0
milestone_name: REALITY closure and E2E regression harness
current_phase: 05
current_phase_name: naive/ACL assertions and fixture guards
status: executing
stopped_at: Phase 5 plans 01-02 verified; E2E-07 baseline recorded; awaiting posture decision.
last_updated: "2026-11-07T06:30:35.860Z"
last_activity: 2026-11-07
last_activity_desc: Phase 5 plans 01-02 verified; E2E-07 baseline recorded; CI fbc1a2f green; awaiting posture decision
state_head: 9e46d0cb11d946bd77e1ceab8d9a765eff09bbf2
progress:
  total_phases: 3
  completed_phases: 1
  total_plans: 9
  completed_plans: 5
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

Phase: 05 — naive/ACL assertions and fixture guards
Plan: 05-03 — Decide and assert the unknown-SNI posture
Status: In progress — blocking E2E-07 checkpoint
Last activity: 2026-11-07 — Plan 05-01/05-02 verified; baseline recorded

## Performance Metrics

**Velocity:**
- Total plans completed in `v0.5.0`: 5
- `v0.4.3` baseline: 8 plans, ~22 min average, ~3 h total

**By Phase (`v0.5.0`):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 4. REALITY E2E harness | 3 | 3 | — |
| 5. naive/ACL assertions and fixture guards | 2 | 3 | — |
| 6. Stability smoke, evidence, release decision | 0 | 3 | — |

**Recent Trend:**
- Phase 5 has 2/3 plans complete. The final E2E run is 9/9 with both positive
  controls, the offline suite is 26/26, and coexistence is 8/8. The remaining
  plan is the blocking E2E-07 posture decision. CI `gate0` and `verify` are
  green on `fbc1a2f`:
  <https://github.com/olst57/my-caddy/actions/runs/42347099461> and
  <https://github.com/olst57/my-caddy/actions/runs/42347099453>.

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
- The unknown-SNI/no-SNI posture is **undecided**. Phase 5 measured a
  reject-like baseline on the current fixture and stops at a checkpoint until
  the owner picks `reject`, `decoy`, or `default`.
- [Phase 4]: The REALITY E2E harness is a separate fail-closed suite that derives its Caddyfile from deploy/Caddyfile and keeps the 26/8 frozen counts unchanged. — A green run must describe the delivery shape, not a hand-written fixture; the existing gates stay comparable.
- [Phase 4]: Xray 26 needs a test-only finalRules loopback allow, and caddy-l4 writes the dialled destination into PROXY v2. — Both were measured on the Linux host; they make E2E-01 and E2E-03 deterministic without changing production configuration.
- [Phase 4]: Negative controls get a 90-second budget and are classified against both client and server logs. — A wrong UUID can be rejected only after the client's REALITY retry loop exceeds the ordinary 25-second request budget.
- [Phase 5]: The unknown/empty/absent SNI baseline is measured, not asserted. — The owner has not chosen reject, decoy, or default; encoding a posture before the answer would make the suite defend an unchosen behaviour.
- [Phase 5]: `socks_get` clears its per-attempt body, header, output and error files before each request. — An earlier closing-control run left a stale marker behind and could have made an empty reply look successful.
- [Phase 5]: CI is green on the recorded commit `fbc1a2f`; the exact commit also re-ran 26/26 offline and 8/8 coexistence on `hw-gz`. — The CI status is evidence for the pushed tree, not a substitute for the Linux runtime checks.

### Pending Todos

- Decide the E2E-07 posture (`reject`, `decoy`, or `default`) before running
  the assertion half of 05-03.
- Execute Phase 6 after Phase 5 closes, with the Caddy and Xray binaries
  uploaded from the local machine rather than downloaded there.
- Phase 6 publication waits on explicit owner approval.

### Blockers/Concerns

- Byte-identical rebuilds are still not established. The Go patch level is now
  fixed at `1.26.9`, but the same sources produced different amd64 bytes on
  `hw-gz` (`872cae…`) and CI (`c780d1…`); build IDs and host paths still vary.
- The REALITY harness needs a destination whose certificate covers the chosen
  SNI. A mismatched pair reproduces `alert 40`, so the destination is an
  external input, not a fixture.
- E2E-07 is a blocking owner decision. The measured baseline is reject-like
  for unknown/absent SNI, but the delivery file does not yet state that
  posture explicitly; the plan must not encode one before the answer.
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

Last session: 2026-11-07T06:30:35.860Z
Stopped at: Phase 5 plans 01-02 complete; E2E-07 baseline recorded; awaiting the
owner's posture decision.
Resume file: .planning/phases/05-naive-acl-assertions-and-fixture-guards/05-03-PLAN.md
Baseline: .planning/phases/05-naive-acl-assertions-and-fixture-guards/05-03-BASELINE.md
