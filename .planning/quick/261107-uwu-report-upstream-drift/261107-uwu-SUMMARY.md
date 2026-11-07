---
quick_id: 261107-uwu
slug: report-upstream-drift
description: "Report when a pinned input falls behind upstream"
status: complete
created: 2026-11-07
completed: 2026-11-07
commits: [b09cbd2, 2c894df]
---

# Quick Task Summary: Upstream drift report

**The pins now announce their own staleness, and the first live run found four
components behind**

## What Was Built

- `scripts/check-upstream.sh` compares the five pinned inputs with their
  upstream and prints one `UPSTREAM <name> pinned=... latest=...` line each,
  then `UPSTREAM: OK` or `UPSTREAM: STALE components=N`. Exit `3` is drift,
  `2` is a usage or fetch error.
- `--from FIXTURE` reads the same five keys from a file, so the test needs no
  network, token, or `gh`.
- `.github/workflows/upstream-watch.yml` runs daily at 01:00 UTC (09:00
  Asia/Shanghai) and on demand with a `dry_run` input. On drift it creates one
  issue, or comments on the open one instead of duplicating it.
- `tests/upstream/check.sh` derives the in-sync fixture from
  `pins/build-inputs.env`, so a deliberate bump keeps the test valid, and it
  covers in-sync, stale, missing-key, bad-argument, and missing-fixture paths.
- `verify` runs the offline test with the other static checks; `README.md` and
  `docs/BUILD.md` state that the watcher reports and never bumps.

## First Live Report

Manual `workflow_dispatch` with `dry_run=true`, run
<https://github.com/olst57/my-caddy/actions/runs/42374657145>, commit
`2c894df`: success, no issue created.

| Component | Pinned | Upstream | State |
|---|---|---|---|
| `caddy_tag` | `v2.11.7` | `v2.11.9` | behind |
| `forwardproxy_sha` | `e747854e…` | `80dde13c…` | behind |
| `caddy_l4_sha` | `96e1a6bf…` | `1da0f2bd…` | behind |
| `xcaddy_version` | `v0.4.7` | `v0.4.7` | in sync |
| `go_version` | `1.26.9` | `1.27.3` | behind |

`UPSTREAM: STALE components=4`. The next scheduled run is what would open the
tracking issue; the dry run deliberately did not.

The l4 row also shows the fork lag: upstream moved to `1da0f2bd…` while the
`olst57` fork still sits at the pinned `96e1a6bf…`. A bump therefore needs a
fork sync, not just a pins edit.

## The YAML Bug the Dispatch Test Caught

The first push registered the workflow but GitHub reported
`.github/workflows/upstream-watch.yml` with the path as its name and rejected
`workflow_dispatch` with HTTP 422. The cause was a plain YAML scalar containing
a colon-space:

```text
run: printf 'dry run: an issue would have been opened\n'
```

YAML read the `: ` as a new mapping entry, so the whole file failed to parse.
The fix turns the value into a block scalar (`run: |`). This is worth
remembering: **a syntactically invalid workflow does not fail the push** — it
shows up as a failed `push` run named after the file path, and only the
dispatch probe makes it obvious.

After the fix, all five workflow files parse in a local `js-yaml` check, and
the dispatched run is green.

## Files

- `scripts/check-upstream.sh`
- `tests/upstream/check.sh`
- `.github/workflows/upstream-watch.yml`
- `.github/workflows/verify.yml`
- `README.md`, `docs/BUILD.md`

## Verification

- `bash -n` and `shellcheck -S warning` over both scripts: clean.
- `bash tests/upstream/check.sh`: `UPSTREAM-TEST: PASS`.
- `bash tests/pins/check.sh`: `PINS: PASS`; `bash tests/fixtures/check.sh`:
  `FIXTURES: PASS`.
- Workflow YAML: all five parse; the dry-run dispatch succeeded on `2c894df`.

## Notes

- Drift is a report, not a red build: only an unreadable source fails the job.
- The issue body carries component names, pinned values, upstream values, and
  the run URL. It has no host, address, or credential, so it is safe to publish.
