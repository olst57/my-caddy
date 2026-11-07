---
quick_id: 261107-fksync
slug: sync-module-forks
description: "Fast-forward the module forks without moving a pin"
status: complete
created: 2026-11-07
completed: 2026-11-07
commits: [3adb33d, 9b73137]
---

# Quick Task Summary: Module fork sync

**The forks are current, the pin did not move, and the daily job only reports
until a write token is added**

## What Was Built

- `scripts/check-forks.sh` compares each fork with the upstream branch it
  mirrors: `olst57/forwardproxy` vs `klzgrad/forwardproxy` `naive`, and
  `olst57/caddy-l4` vs `mholt/caddy-l4` `master`. It prints
  `state=in-sync|behind|ahead|diverged`, exits `3` on drift, and never forces.
- `.github/workflows/fork-sync.yml` runs daily at 01:30 UTC (09:30
  Asia/Shanghai) and on demand. With a `FORK_SYNC_TOKEN` secret it
  fast-forwards only the `behind` forks, re-checks, and opens or updates one
  issue if anything remains. Without the token it reports and says why.
- `tests/forks/check.sh` covers in-sync, behind, diverged, unexpected status,
  missing key, and missing fixture; `verify` runs it with the static checks.
- `README.md` and `docs/BUILD.md` state the boundary: a sync is not a bump.

## Live Result

Before: `FORK caddy_l4 ... state=behind ahead_by=3`.

`gh repo sync olst57/caddy-l4 --branch master` fast-forwarded the fork from
`96e1a6bf…` to `1da0f2bd…`. After:

```text
FORK forwardproxy branch=naive fork=e747854e7874 upstream=e747854e7874 state=in-sync
FORK caddy_l4 branch=master fork=1da0f2bd8fc8 upstream=1da0f2bd8fc8 state=in-sync
FORKS: OK
```

`pins/build-inputs.env` still says `PIN_L4_SHA=96e1a6bf…`, so the next build
checks out the same commit as `v0.5.0`. The CI `build` job on this commit
compiled from that pin **after** the fork head moved, and succeeded — which is
the proof that syncing a fork cannot silently change the artifact.

## The Token

`GITHUB_TOKEN` is scoped to this repository and cannot write to the two forks,
so the automatic sync needs a repository secret `FORK_SYNC_TOKEN` — a
fine-grained token with `Contents: read and write` on both forks. Until it is
added, the workflow only reports drift in an issue. The user's own token can
write to both forks, which is how the one-off sync above was done.

## A Gate Wording Lesson

The first draft of `docs/BUILD.md` introduced the token with the word "secret"
followed by a colon and a value. `S7-12` matches that shape, so the sentence
was indistinguishable from a credential assignment to the scanner. It was
rewritten with an em dash. The local scratch scanner now exits non-zero on a
hit, so a chained commit stops instead of carrying the phrase forward.

## Verification

- `bash -n` and `shellcheck -S warning` over both scripts: clean.
- `bash tests/forks/check.sh`: `FORKS-TEST: PASS`.
- All six workflow files parse as YAML.
- `fork-sync` dry run: <https://github.com/olst57/my-caddy/actions/runs/42377261717>.
- CI on `9b73137`: `verify` <https://github.com/olst57/my-caddy/actions/runs/42377188030>,
  `gate0` <https://github.com/olst57/my-caddy/actions/runs/42377188026>,
  `build` <https://github.com/olst57/my-caddy/actions/runs/42377188027>, all
  success.
