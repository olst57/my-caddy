---
phase: 03-publish-v043
plan: 01
subsystem: release
tags: [tag, release, assets, provenance]

requires:
  - phase: 02
    plan: 03
    provides: the 8-item coexistence suite and the acceptance closure record

provides:
  - annotated tag v0.4.3 on b60f042
  - GitHub release with four assets
  - docs that name the released run and the binary the evidence describes

affects:
  - phase-03 plan 02

actuals:
  tokens: 0
  tasks: 4
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Evidence must describe the downloadable asset, not the locally built binary"

key-files:
  created: []
  modified:
    - docs/VERIFY.md
    - docs/BUILD.md

key-decisions:
  - "Tag b60f042, the head of main after pull request #1 was rebase-merged."
  - "Re-run the gate on the downloaded release asset instead of citing the local build."
  - "Document the build-time fork-SHA resolution as a known limitation rather than silently republishing."

patterns-established:
  - "A release is not done until the artifact a reader downloads has been run through the same gate as the tree."

requirements-completed: [REL-01, REL-02]

coverage:
  - id: D1
    description: "The tagged commit has a green verify run with both jobs"
    requirement: "REL-01"
    verification:
      - kind: ci
        ref: "https://github.com/olst57/my-caddy/actions/runs/42060352580"
        status: pass
    human_judgment: false
  - id: D2
    description: "The release carries four assets and pins.txt matches the tag"
    requirement: "REL-01"
    verification:
      - kind: other
        ref: "release 435420474: caddy-linux-amd64, caddy-linux-arm64, SHA256SUMS, pins.txt"
        status: pass
    human_judgment: false
  - id: D3
    description: "The release notes state 26 offline and 8 coexistence items, the run URL, and the arm64 limitation"
    requirement: "REL-01"
    verification:
      - kind: other
        ref: ".gate/release-notes-v0.4.3.md published as the release body"
        status: pass
    human_judgment: false
  - id: D4
    description: "The gate passes against the published caddy-linux-amd64 asset"
    requirement: "REL-02"
    verification:
      - kind: other
        ref: "hw-gz: PASS=26 FAIL=0, CO-1..CO-8 PASS on sha256 693057c2…f2"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-11-06
status: complete
---

# Phase 3: Publish v0.4.3 — Plan 01 Summary

`v0.4.3` is published from a green commit, and the evidence now describes the
binary a reader actually downloads rather than the one built on the test host.

## Performance

- **Duration:** 55 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-06
- **Tasks:** 4

## Release Object

| Item | Value |
|------|-------|
| Tag | annotated `v0.4.3` |
| Tagged commit | `b60f042`, head of `main` after PR #1 |
| Green run | 42060352580 — `offline` and `coexist` both success |
| Release | <https://github.com/olst57/my-caddy/releases/tag/v0.4.3> (id 435420474) |
| Assets | `caddy-linux-amd64`, `caddy-linux-arm64`, `SHA256SUMS`, `pins.txt` |

The notes state 26 offline items, 8 coexistence items, the run URL, the Linux
test host, both limitations (arm64 artifact-verified only, HTTP/3 off by
design), and the REALITY placeholder posture.

## Provenance Drift

`scripts/build.sh` resolves `FWDPROXY_SHA` and `L4_SHA` from
`refs/heads/master` when they are not passed in. `caddy-l4` head moved between
the first measurement and the release build:

| | caddy-l4 | caddy-linux-amd64 sha256 |
|---|---|---|
| Local build first tested | `f607ccea…` | `1a9115…2624` |
| Published asset | `96e1a6bf…` | `693057c2…f2` |

The published artifact is the one that matters, so the 26-item gate and the
8-item coexistence suite were re-run on the **downloaded** asset at `b60f042`:
`PASS=26 FAIL=0` and `CO-1..CO-8 PASS`. `docs/BUILD.md` now states that
`pins.txt` is a receipt for one run, not a reproducibility promise, and
`docs/VERIFY.md` names the tag, the run, and the asset hash. Pinning the two
forks to the receipt SHAs is carried into the next milestone.

## Deviations

1. **Task order.** The archive (03-02) was built before the tag because the tag
   needed permission. It was regenerated afterwards against the release asset,
   so its commit field is `b60f042` and its hash changed from `cf787b6b…` to
   `ad92d5f5…`.
2. **Docs landed after the tag.** `e9618ba` aligns `docs/BUILD.md` and
   `docs/VERIFY.md` with the published asset. CI for that commit is run
   42062987801 (both jobs success), so the documentation is gate-checked even
   though it is not part of the tagged tree.
3. **No republish.** Moving the tag or rebuilding to force identical bytes
   would invalidate the release the notes already cite. The drift is recorded
   instead.

## Verification

- Tag SHA equals the release `target_commitish` commit `b60f042`.
- Four assets present; `pins.txt` names the tag and the module commits.
- Release body contains `26`, `CO-1`…`CO-8`, the run URL, and the arm64 caveat.
- `hw-gz` on the release asset: 26/26 offline, 8/8 coexistence.
- `main` at `083ec57`: verify run 42062987801 green; gate0 run 42062987745 green.

## Next Phase Readiness

- Milestone `v0.4.3` is delivered; no task in this plan remains open.
- Deferred: pin the two fork SHAs so a later build reproduces the published
  bytes, and execute the arm64 asset on real hardware.
