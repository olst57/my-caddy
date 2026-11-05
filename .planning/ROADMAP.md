# Roadmap: my-caddy

## Overview

The v4 delivery is complete through `v0.4.2`. This roadmap covers the first
GSD-managed milestone, `v0.4.3`: freeze the verification slice that already
exists in the working tree, close the remaining runtime-acceptance findings,
and publish a tag whose artifacts and evidence match the tree.

The milestone is deliberately narrow. It does not add a fourth role, move off
`v2.11.7`, or reopen the HTTP/3 decision.

## Milestones

- 🚧 **v0.4.3 Verification gate** (Phases 1–3)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): planned milestone work
- Decimal phases (2.1, 2.2): urgent insertions

- [ ] **Phase 1: Freeze the verification gate** - Commit the 26-item offline
  verifier, the 7-item coexistence suite, and the CI workflow that runs both.
- [ ] **Phase 2: Close runtime acceptance** - Give every remaining v0.4.0
  runtime finding a defensible disposition.
- [ ] **Phase 3: Publish v0.4.3** - Tag and release with artifacts, pins, and
  redacted evidence.

## Phase Details

### Phase 1: Freeze the verification gate
**Goal:** Turn the verification work already in the working tree into a
reviewable, reproducible gate on `main`.
**Mode:** mvp
**Depends on:** Nothing (first phase of this milestone)
**Requirements**: VER-01, VER-02, VER-03, VER-04, VER-05, VER-06
**Success Criteria** (what must be TRUE):
  1. `scripts/verify.sh` emits exactly 26 unique items and prints
     `VERIFY: PASS` on a Linux host.
  2. `tests/coexist/run.sh` prints `COEXIST: PASS` with seven items on a Linux
     host with root.
  3. `.github/workflows/verify.yml` runs both suites on push and pull request,
     and a failure in either job is red.
  4. The verification slice is committed and reachable from `main`.
  5. `docs/VERIFY.md` and `docs/BUILD.md` name the same item set the scripts
     execute.
**Plans**: 3 plans

Plans:
- [ ] 01-01: Review and commit the verification slice
- [ ] 01-02: Run both suites on Linux and record evidence
- [ ] 01-03: Make CI the gate and reconcile docs

### Phase 2: Close runtime acceptance
**Goal:** Resolve the v0.4.0 runtime-acceptance findings that are still open,
without pretending an unrun check passed.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements**: RTA-01, RTA-02, RTA-03
**Success Criteria** (what must be TRUE):
  1. REALITY defaults are either runnable as shipped or documented and checked
     as mandatory-replace.
  2. `probe_resistance` cannot silently target the proxied destination.
  3. Every v0.4.0 RTA FAIL has a written disposition: fixed, documented, or
     deferred.
  4. The evidence report is regenerated from raw outputs with no undisclosed
     files.
**Plans**: 3 plans

Plans:
- [ ] 02-01: Decide and enforce the REALITY placeholder posture
- [ ] 02-02: Guard the `probe_resistance` target
- [ ] 02-03: Audit and close the remaining RTA findings

### Phase 3: Publish v0.4.3
**Goal:** Publish a tag whose artifacts, pins, and evidence match the tested
tree.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements**: REL-01, REL-02
**Success Criteria** (what must be TRUE):
  1. `main` contains the reviewed verification slice.
  2. `v0.4.3` artifacts include `SHA256SUMS` and `pins.txt`.
  3. The release notes state the item counts and the host that produced the
     runtime evidence.
  4. Redacted evidence is archived and linked from the evidence index.
**Plans**: 2 plans

Plans:
- [ ] 03-01: Tag and release v0.4.3
- [ ] 03-02: Archive redacted evidence and update the index

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Freeze the verification gate | 0/3 | In progress | - |
| 2. Close runtime acceptance | 0/3 | Not started | - |
| 3. Publish v0.4.3 | 0/2 | Not started | - |
