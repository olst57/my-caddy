---
quick_id: 261107-uwu
slug: report-upstream-drift
description: "Report when a pinned input falls behind upstream"
status: in_progress
created: 2026-11-07
---

# Quick Task: Report upstream drift without moving a pin

The delivery build is pinned on purpose, but nothing currently tells the owner
when Caddy, `xcaddy`, either fork, or Go moves. This task adds a read-only
checker and a scheduled workflow that reports drift through one tracking issue.

## Assumptions

- A bump stays a reviewed change. The watcher never edits
  `pins/build-inputs.env`, never builds, and never tags.
- Go drift is informative, not an instruction: the pin follows the official
  naiveproxy Caddy toolchain, not the newest release.
- Drift is not a red build. Only an unreadable source fails the job.
- The issue is public, so the body carries no host, address, or credential.

## Task 1: Checker with an offline fixture mode

**Files:** `scripts/check-upstream.sh`, `tests/upstream/check.sh`

Compares five pins against their upstream and prints one line per component,
then `UPSTREAM: OK` or `UPSTREAM: STALE components=N`. Exit `3` means stale,
`2` means usage or fetch error. `--from` reads the same five keys from a file
so the test runs without network or credentials.

## Task 2: Daily workflow

**Files:** `.github/workflows/upstream-watch.yml`,
`.github/workflows/verify.yml`

Runs daily at 01:00 UTC (09:00 Asia/Shanghai) and on demand, with a `dry_run`
input. On drift it opens one issue or comments on the existing one. `verify`
runs the offline test with the other static checks.

## Task 3: Document the boundary

**Files:** `README.md`, `docs/BUILD.md`

States that the watcher is a report, and that a bump still needs a fork sync,
a patch check, a gate run, and a new receipt.

## Verification

- `bash -n` and `shellcheck -S warning` over both shell scripts.
- `bash tests/upstream/check.sh` covers in-sync, stale, missing key, bad
  argument, and missing fixture.
- `bash tests/pins/check.sh` and `bash tests/fixtures/check.sh` stay green.
- One `workflow_dispatch` run with `dry_run=true` on the pushed commit.
