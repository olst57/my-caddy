---
phase: 06-stability-smoke-evidence-and-release-decision
plan: 03
subsystem: release
tags: [release, tag, ci, gate, decision]

requires:
  - phase: 06-stability-smoke-evidence-and-release-decision
    provides: the smoke and the redacted evidence set
provides:
  - a dated, owner-approved publication decision
  - the annotated `v0.5.0` tag on a CI-green commit
  - a published release with four assets and matching digests
affects: [milestone-v0.5.0]

actuals:
  tokens: 3600
  tasks: 4
  commits: []

tech-stack:
  added: []
  patterns: [gate-then-tag, digest cross-check, owner checkpoint]

key-files:
  modified:
    - .planning/ROADMAP.md
    - .planning/STATE.md
    - .planning/REQUIREMENTS.md
    - evidence/README.md
    - evidence/v0.5.0/index.md
    - docs/VERIFY.md

key-decisions:
  - "Publish: the owner answered the blocking checkpoint with `approved` on 2026-11-07."
  - "The tag points at `d3c19c3`, the commit whose `verify` and `gate0` runs are green, not at a later documentation commit."
  - "Executing the 53 MB release asset on the Linux test host is deferred rather than claimed; the CDN measured 5–35 KB/s and about 19 KB/s from the test host."
  - "`v0.4.3` was not moved, re-tagged, or rewritten."

requirements-completed: [REL-01]

coverage:
  - id: D1
    description: "Both existing suites are re-run on the candidate commit."
    requirement: REL-01
    verification:
      - kind: gate
        ref: "c8bfe42 and b720f9a on the Linux test host: PASS=26 FAIL=0, CO-1..CO-8 PASS"
        status: pass
    human_judgment: false
  - id: D2
    description: "CI is green on the exact commit that is tagged."
    requirement: REL-01
    verification:
      - kind: ci
        ref: "verify 42369088803 and gate0 42369088807 on d3c19c3"
        status: pass
    human_judgment: false
  - id: D3
    description: "The owner approves publication explicitly."
    requirement: REL-01
    verification:
      - kind: manual
        ref: "owner reply `approved`, 2026-11-07"
        status: pass
    human_judgment: true
  - id: D4
    description: "An annotated tag exists on the approved commit, and the release build publishes four assets."
    requirement: REL-01
    verification:
      - kind: ci
        ref: "build run 42370444867: preflight/build/publish success; release 437547357 has 4 assets"
        status: pass
    human_judgment: false
  - id: D5
    description: "The published amd64 asset is the binary the gate actually ran."
    requirement: REL-01
    verification:
      - kind: ci
        ref: "asset digest, SHA256SUMS, and the CI-built binary all equal c780d1d6…; offline printed PASS=26 and coexist re-used that artifact"
        status: pass
    human_judgment: false

duration: 1h
completed: 2026-11-07
status: complete
---

# Phase 6 Plan 3: Re-run, Decision, and Publication Summary

**`v0.5.0` is published on the commit the gate measured, and the evidence says
exactly which binary it describes**

## Performance

- **Duration:** ~1 h across the re-runs, the checkpoint, and the release
- **Completed:** 2026-11-07
- **Tasks:** 4 (re-run, CI record, owner decision, tag and release)
- **Files modified:** 6

## What Was Measured

| Check | Commit | Result |
|---|---|---|
| offline + coexistence, Linux test host | `c8bfe42` | `PASS=26 FAIL=0`, `CO-1`…`CO-8` PASS |
| offline + coexistence, Linux test host | `b720f9a` | `PASS=26 FAIL=0`, `CO-1`…`CO-8` PASS |
| CI `verify` | `d3c19c3` | success, run 42369088803 |
| CI `gate0` | `d3c19c3` | success, run 42369088807 |
| release `build` | `v0.5.0` | success, run 42370444867 |

`build` does not run on a push to `main`; it runs on the release event. That is
why the tag-and-release step is what produced the artifacts, and why the first
two rows used the locally built go1.26.9 binary.

## The Decision

The phase plan makes publication a blocking human-verify checkpoint with the
resume signals `approved` and `hold`. The owner answered `approved` on
2026-11-07. `ROADMAP.md` records the decision with the gate it rests on.

The tag was created **before** the decision documentation was committed: the
tag points at `d3c19c3`, the commit whose CI is green, and the later commits
only add the record of the decision. Tagging a documentation commit whose own
CI had not yet finished would have been the T-6-05 failure the plan warns
about.

## Release

- Annotated tag `v0.5.0` on `d3c19c3`; `v0.4.3` still on `b60f042`.
- Release: <https://github.com/olst57/my-caddy/releases/tag/v0.5.0>
  (id 437547357), not a draft and not a pre-release.
- Assets: `caddy-linux-amd64`, `caddy-linux-arm64`, `SHA256SUMS`, `pins.txt`.

| Asset | Size | sha256 |
|---|---:|---|
| `caddy-linux-amd64` | 53,022,882 | `c780d1d63fa72b355f28ff7625968860dd9f36294ec884ca3b34920126bd04a8` |
| `caddy-linux-arm64` | 49,414,306 | `8fcd7377649d9351ce0e7b2b42d9a890bcfc16cc0fd6a3d7e7ee1e16bf1c1b49` |
| `SHA256SUMS` | 168 | `083f0c8310ccda5d7661c2a3789f68ec078c5cd06558b600f2bc57b833ee9f57` |
| `pins.txt` | 267 | `677b2813466aa721d38a32d105e19c49f2ccba39abcd4d334deb8138040aed34` |

`pins.txt` records `go_version=go1.26.9`, `forwardproxy_sha=e747854e…`,
`caddy_l4_sha=96e1a6bf…`, and `caddy_tag=v2.11.7`.

## Which Binary the Gate Ran

The published amd64 asset hash is not the hash of the local test build
(`872caeee…`). The two are different builds of the same pinned inputs, and the
repository does not claim byte-identical rebuilds.

The asset hash is, however, exactly the binary the CI gate ran. The `offline`
job at `d3c19c3` built `dist/caddy-linux-amd64`, printed
`c780d1d63fa72b355f28ff7625968860dd9f36294ec884ca3b34920126bd04a8` in its
`SHA256SUMS`, and then printed `PASS=26 FAIL=0` and `VERIFY: PASS`. The
`coexist` job downloads that artifact instead of rebuilding, and printed
`ITEM CO-8 PASS` and `COEXIST: PASS`. The release API digest and the
downloaded `SHA256SUMS` both report the same `c780d1d6…`.

`evidence/v0.5.0/index.md` now states both hashes: the CI/release hash and the
local test-build hash, and which numbers came from which.

## Deferred

The 53 MB amd64 asset was not executed on the Linux test host. Measured
throughput to the release CDN was 5–35 KB/s from the authoring machine and
about 19 KB/s from the test host, so the transfer was hours rather than
minutes. The item is recorded in `STATE.md` Deferred Items as a `v0.5.0`
follow-up rather than silently dropped.

What is not deferred: the two CI suites ran the byte-identical binary, and the
asset was verified by three independent digests.

## Files Created/Modified

- `.planning/ROADMAP.md` - Phase 6 complete, milestone delivered, dated REL-01
  decision with the release link
- `.planning/STATE.md` - 3/3 phases, 9/9 plans, deferred asset execution
- `.planning/REQUIREMENTS.md` - REL-01 complete
- `evidence/v0.5.0/index.md` - the release-asset section and the two hashes
- `evidence/README.md` - the `v0.5.0` asset table and the digest cross-check
- `docs/VERIFY.md` - the candidate gate, the CI runs, and the decision status

## Deviations from Plan

**1. [Rule 3 - Blocking] The release asset was not executed locally**
- **Found during:** Task 4
- **Issue:** downloading 53 MB from the release CDN measured 5–35 KB/s, and
  about 19 KB/s from the test host.
- **Fix:** verified the asset by three independent digests and by the CI suites
  that ran the same bytes; recorded the execution as deferred.
- **Impact:** the evidence index names the local test-build hash rather than
  implying the published asset was executed on the test host.

---

**Total deviations:** 1 (blocking)
**Impact on plan:** publication is complete and the artifact is gated by hash;
one runtime run on the published asset remains open.

## Issues Encountered

- The release notes were written before the release existed, so the notes
  describe the gate rather than post-hoc asset results; the repository record
  (`evidence/v0.5.0/index.md`) carries the asset cross-check.
- The window between the tag push and the release creation is not a build
  trigger: only `release: published` starts `build`, which is why the asset
  appears after the release object, not the tag.

## Verification Evidence

- `git cat-file -t v0.5.0` → `tag`; `v0.5.0^{}` → `d3c19c3`;
  `v0.4.3^{}` → `b60f042` (unchanged).
- Release 437547357: four assets, `draft=false`, `prerelease=false`.
- `build` run 42370444867: `preflight`, `build`, and `publish` all success.
- Asset digest == downloaded `SHA256SUMS` line == CI-built binary hash.
