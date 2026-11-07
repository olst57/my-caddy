---
quick_id: 261107-fksync
slug: sync-module-forks
description: "Fast-forward the module forks without moving a pin"
status: in_progress
created: 2026-11-07
---

# Quick Task: Keep the module forks current

Both modules already build from this project's forks, but nothing kept those
forks current: `olst57/caddy-l4` was three commits behind upstream, and the
`forwardproxy` fork had no sync at all.

## Assumptions

- A sync is not a version bump. The build checks out the commits in
  `pins/build-inputs.env`, so moving a fork head cannot change today's binary.
- Only fast-forwards are allowed. `ahead` and `diverged` are reported, never
  forced, because a force would discard commits.
- The default `GITHUB_TOKEN` cannot write to another repository, so the sync
  needs a `FORK_SYNC_TOKEN` secret. Without it the workflow reports and opens
  an issue.

## Task 1: Fork checker with an offline fixture mode

**Files:** `scripts/check-forks.sh`, `tests/forks/check.sh`

Compares `olst57/forwardproxy` with `klzgrad/forwardproxy` `naive`, and
`olst57/caddy-l4` with `mholt/caddy-l4` `master`. Prints one `FORK ...` line
each and exits `0` in sync, `3` on drift, `2` on a bad source.

## Task 2: Scheduled sync workflow

**Files:** `.github/workflows/fork-sync.yml`, `.github/workflows/verify.yml`

Daily at 01:30 UTC (09:30 Asia/Shanghai) and on demand. Fast-forwards only
`state=behind` forks when the token exists, re-checks, then opens or updates
one issue if drift remains.

## Task 3: Document the boundary and enable the token

**Files:** `README.md`, `docs/BUILD.md`

Record that a sync never moves a pin, and how to create the fine-grained token.

## Verification

- `bash -n` and `shellcheck -S warning` over both scripts.
- `bash tests/forks/check.sh` covers in-sync, behind, diverged, unexpected
  status, missing key, and missing fixture.
- All six workflow files parse as YAML.
- One manual fast-forward of `olst57/caddy-l4`, then a live check that reports
  `FORKS: OK`.
