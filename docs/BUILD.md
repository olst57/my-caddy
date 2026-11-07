# BUILD — how the `my-caddy` binary is produced

This document describes how `dist/caddy-linux-amd64` and
`dist/caddy-linux-arm64` are built. Every command below was executed; the
transcript `docs/transcript-v0.2.0.txt` records each one with its real exit code
and the host it ran on.

## What the binary is

It is **not** a stock `caddy` from a package manager. It is a custom build of
Caddy `v2.11.7` with four added modules:

| module | why |
| --- | --- |
| `caddy.listeners.layer4` | reads the raw ClientHello and routes on SNI before TLS terminates |
| `layer4.handlers.proxy` | forwards a matched connection to the REALITY socket |
| `layer4.matchers.quic` | present in the build; not exercised by v0.2.0 |
| `http.handlers.forward_proxy` | the naive coexistence side |

`sagernet` is deliberately absent. This build has no BBR support.

## Where the artifact comes from

The artifacts are **not** in the working tree (`dist/` is gitignored). They are
produced by the `build` workflow (`.github/workflows/build.yml`) and downloaded
from its run — for this slice, **run 41069346485** on
`ubuntu-latest`, at commit `0a3b22af3c4a467c12dd99eac50ebad7f6174530`. Download
the `caddy-linux` artifact from that run before running any check that needs the
binary.

The `build` workflow builds and checksums the artifacts and does not run
`scripts/verify.sh`; the separate `verify` workflow
(`.github/workflows/verify.yml`) does. It builds amd64, runs the offline
verifier, then runs `tests/coexist/run.sh` against that same binary on
`ubuntu-latest`. The first enforced run is pull request #1,
<https://github.com/olst57/my-caddy/actions/runs/42049087626>, on commit
`75bd95a`: `offline` passed 26/26 (`VERIFY: PASS`) and `coexist` passed 7/7
(`COEXIST: PASS`). The historical verifier runs were manual, on ubuntu-latest
in a GitHub Codespace and on `hw-gz`. See
`docs/VERIFY.md` for the provenance of that run and for the `chmod +x`
requirement. The reproducibility limit is stated there as well; its evidence
entry (D-5) is in `.gate/release/DEVIATIONS.md`, which is gitignored and not part
of the tracked tree.

## Pinned inputs

Every build input is a concrete commit or tag, recorded in `dist/pins.txt` so a
run states exactly what it built. The values in this slice are:

The fixed values live in `pins/build-inputs.env`, and `dist/pins.txt` records
what a run actually compiled:

```text
caddy_tag=v2.11.7
caddy_source_head=72dd0fb067f6d7826c7f79907670ba4a713bfe37
forwardproxy_sha=e747854e78743dba85c039b38ed185fb11d93667
caddy_l4_sha=96e1a6bf063c206c3bd09ca6dc4a0484a158d83f
xcaddy_version=v0.4.7
go_version=go1.26.9
patch=caddy-read-idle-timeout.patch
```

### The inputs are fixed in `pins/build-inputs.env`

`scripts/build.sh` sources the file and does not query a branch head.
`CADDY_COMMIT` is checked against the cloned tag, so a moved tag fails before
compilation. Environment variables with the old names (`CADDY_TAG`,
`FWDPROXY_SHA`, `L4_SHA`, `XCADDY_VERSION`) still override the file for a
one-off rebuild; the default never floats. `PIN_GO_VERSION` is deliberately
not overridable: the delivery build must run on exactly `go1.26.9`.

The Go pin comes from the official naiveproxy Caddy release
`v2.11.7-naive2`. Its published `caddy` binary reports `go1.26.9` in the Go
build metadata; the downloaded archive has sha256
`c273dc07dd79c5919f97639cbdcb559d40ce90475dbd8aac80641b0a8c8065ff`,
and the contained `caddy` has sha256
`ee571de2ed6d68dd29c1f83e5dbc62d043982c65d73ea230b78389253743527c`.
Before compiling, `scripts/build.sh` sets `GOTOOLCHAIN=local` and compares
`go env GOVERSION` with the pin, so a different installed patch fails closed
instead of silently downloading a replacement toolchain.

The `v0.4.3` receipt records `go1.26.10`. That release, its assets, and its
evidence are historical records and are not rewritten by this pin.

This closes the defect the v0.4.3 release exposed. The binary used for the first
`hw-gz` measurement was built when `caddy-l4` head was `f607ccea…`; by the time
the release workflow ran, head had advanced to `96e1a6bf…`, so the published
asset had a different sha256 from the tested tree. v0.4.3 was handled by
re-running the gate on the downloaded asset; the follow-up pins the input so
the mismatch cannot recur.

Changing a pin is a reviewable edit plus a rebuild. `tests/pins/check.sh`
verifies the file shape, refuses any `git ls-remote` in the two build paths,
runs `scripts/build.sh --print-pins`, and (with `--pins dist/pins.txt`) checks
the receipt against the file. It runs in the `verify` workflow before the
artifact is built and again in `build` after both architectures are built.

### Knowing when upstream moves

`scripts/check-upstream.sh` compares every pin with its upstream: the Caddy and
`xcaddy` release tags, the `forwardproxy` `naive` head, the `caddy-l4` `master`
head, and the latest stable Go release. It only reports. It never edits
`pins/build-inputs.env`, because a bump has to prove that the read-idle-timeout
patch still applies and that both forks were synced before their commits move.

`forwardproxy` is compared on `naive`, not `master`: master stopped in 2024 and
diverged from the maintained line by a README-only commit, so a master
comparison would always report a false positive. The pin is a `naive` commit.

The scheduled workflow `.github/workflows/upstream-watch.yml` runs it daily and
opens one tracking issue when a pin is behind, commenting on that issue on later
runs instead of creating duplicates. A manual run takes a `dry_run` input that
prints the comparison without touching issues. The workflow fails only when a
source cannot be read; drift is a report, not a red build.

The offline test `tests/upstream/check.sh` builds its fixtures from the pins
file, so it stays valid after a deliberate bump, and it covers the in-sync,
stale, missing-key, bad-argument, and missing-fixture paths. `verify` runs it
with the other static checks.

A watcher is not an upgrade. Moving a pin still needs the fork sync, a patch
rebase if the Caddy source moved, a full gate run, and a new receipt; the Go pin
in particular tracks the toolchain of the official naiveproxy build, not the
newest release.

### Keeping the module forks current

Both modules are already built from this project's forks (`olst57/forwardproxy`
and `olst57/caddy-l4`), and both forks mirror one upstream branch:
`forwardproxy` mirrors `klzgrad/forwardproxy` `naive`, and `caddy-l4` mirrors
`mholt/caddy-l4` `master`.

`scripts/check-forks.sh` compares each fork with that branch and prints
`FORK <name> ... state=in-sync|behind|ahead|diverged`. The scheduled
`.github/workflows/fork-sync.yml` runs it daily at 01:30 UTC (09:30
Asia/Shanghai). When a fork is behind, it fast-forwards it with `gh repo sync`;
`ahead` and `diverged` are reported, never forced, because that would discard
local commits.

The sync needs a `FORK_SYNC_TOKEN` repository secret — a fine-grained token
with `Contents: read and write` on the two fork repositories. Without it the
workflow still runs and reports, and the issue it opens says so. The default
`GITHUB_TOKEN` cannot write to another repository.

**A sync does not move a pin.** The build checks out the exact commits in
`pins/build-inputs.env`, so syncing only prepares the fork for a future bump;
it cannot change today's binary. `tests/forks/check.sh` covers the in-sync,
behind, diverged, unexpected-status, missing-key, and missing-fixture paths,
and `verify` runs it with the static checks.

## The one patch, and why `--replace` is mandatory

`patches/caddy-read-idle-timeout.patch` is a compile-time requirement, not an
optimisation. The naive forwardproxy at the pinned SHA calls
`caddyhttp.IdleTimeoutsFromContext`, a symbol that does not exist in Caddy
`v2.11.7`. Without the patch the build cannot compile.

For the same reason the build must pass `--replace` to xcaddy so the patched
source tree is used instead of the module proxy's copy of Caddy:

```text
--replace github.com/caddyserver/caddy/v2=<patched source tree>
--with    github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@<sha>
--with    github.com/mholt/caddy-l4=github.com/mholt/caddy-l4@<sha>
```

`scripts/build.sh` is the executable form of this. It reads the pins, clones
the tag, applies `patches/caddy-read-idle-timeout.patch`, asserts the
post-conditions, builds both architectures, and writes `dist/SHA256SUMS` and
`dist/pins.txt`. It is the delivery build script; `tests/probes/gate-build.sh`
is a separate Gate 0 probe and is never used to produce artifacts.

There is exactly one patch. A second `.patch` file in `patches/` is a scope
violation, and both `scripts/build.sh` and the CI preflight job fail loudly if
one appears. The count is recorded in the transcript:

```bash
$ find patches -maxdepth 1 -name '*.patch' -type f | wc -l
```

## The patch's upstream source, and one corrected reference

The patch header carries this claim, kept here as the object of the correction:

```text
Backport Caddy's idle-timeout override API from:
https://github.com/caddyserver/caddy/commit/f355b8687d5582ea9fcc99f71598109d1e5b6ced
```

That reference is a **misreference**. `f355b8687d5582ea9fcc99f71598109d1e5b6ced`
is `reverseproxy: retry dial errors wrapped by a forward proxy (#8264)` — a
reverse-proxy retry fix. It touches only `retries_test.go` and `reverseproxy.go`,
and a case-insensitive search for `idletimeout` or `deadlineIdle` over that
commit returns no hit. It does not carry the API this patch adds.

The real upstream source is `8f549e6df151f6a947bc183200c5d26baefa8666`, whose
first line is `timeouts: take precedence over server-wide and enclosing idle
timeouts (#8121)`. It is the squash merge of PR #8121, merged at
`2026-10-03T12:18:43Z`; its committer date is `2026-10-03T12:18:42Z`; it touches
five files, including `modules/caddyhttp/idletimeout.go`, and the symbols its
diff adds are exactly the ones this patch carries.

`8f549e6` is **not** contained in `v2.11.7`, so "Backport" is the correct word for
the direction of the port. v2.11.7（annotated tag，tagger date 2026-10-03T05:25:14Z；tag 指向 commit 72dd0fb，committer date 2026-10-03T05:06:18Z）

The ordering that establishes that:

- The tag points at commit `72dd0fb067f6d7826c7f79907670ba4a713bfe37`, whose
  committer date is `2026-10-03T05:06:18Z`.
- `8f549e6` follows that commit by 7h12m24s, and the upstream compare API reports
  `"status":"behind"`, `"ahead_by":0`, `"behind_by":2`.
- `f355b86` follows `8f549e6` by 17d23h30m50s — which is why the wrong SHA looked
  plausible in the header in the first place.

The mechanical checks for this paragraph are the seven greps in
`.gate/release/SPEC-v0.4.0-SP7.md` B.4, and `scripts/verify.sh` runs the same
assertions as item `S7-15`.

## Which architecture was executed

`caddy-linux-amd64` is the native artifact: it runs the 26-item offline gate
and the 8-item coexistence suite on `hw-gz` and on the CI runner.

`caddy-linux-arm64` is no longer artifact-verified only. The manual
`verify-arm64-release` workflow downloads the published `v0.4.3` asset, checks
its recorded sha256 before execution, and runs the same two suites on a
GitHub-hosted `ubuntu-24.04-arm` runner. The successful run is
<https://github.com/olst57/my-caddy/actions/runs/42228779590>; the extracted
record is `evidence/v0.4.3/arm64-release.log`. That run executes the released
binary, not a local rebuild; the byte-reproducibility caveat above still
applies to both architectures.

## Checking the artifacts you downloaded

After downloading them, verify them from the directory that holds them, because
`SHA256SUMS` lists bare filenames:

```bash
$ ( cd dist && sha256sum -c SHA256SUMS )
```

## Environment

The artifact under test is a Linux ELF:

```bash
$ file dist/caddy-linux-amd64
```

It executes only on Linux. On the Windows authoring host it exits `126` with
`cannot execute binary file: Exec format error`, which is recorded in the
transcript; every command that needs to run it was executed on ubuntu-latest in
a GitHub Codespace instead. Before running it there, make the exec bit explicit —
transfer loses it:

```bash
$ chmod +x dist/caddy-linux-amd64
```

```bash
$ ./dist/caddy-linux-amd64 version
```

`caddy validate` and `caddy adapt` are static operations: they parse and
provision configuration without binding a listener. They are **not** runtime
evidence, and this document does not claim otherwise.

## NOT VERIFIED IN THIS SLICE

This label means "never attempted on any host in this slice", and it is
deliberately narrower than it used to be. One entry that v0.2.0 listed here no
longer holds: `caddy run`, a listener bind, a TLS handshake and an HTTP request
**were** performed on `hw-gz` for the v0.2.1 runtime re-run recorded in
`docs/VERIFY.md` and in `.gate/release/SP4B-D1.txt`, `SP4B-D2.txt` and
`SP4B-D5.txt`. They are not part of the offline verifier, and they were not run
on the Windows authoring host. What has still never been attempted:

- Any xray start.
- Any REALITY session through the layer4 path. The runtime re-run exercised the
  naive and website paths only.

These were never attempted. They are not achievements, and no later document in
this slice should be read as claiming them.

## Unreachable on the Windows authoring host

The artifact is a Linux ELF and the authoring host is Windows/MSYS, so that host
cannot execute it: `test -x` is false and the attempt exits `126` with
`cannot execute binary file: Exec format error`, recorded verbatim in the
transcript. There, `caddy validate`, `caddy adapt`, and every check that needs
the binary are BLOCKED at preflight. This is a limitation of the authoring host,
not a verdict on the deliverable.

The S3 items that require the binary **were** executed — on ubuntu-latest, in a
GitHub Codespace, against the artifact from run 41069346485, after
`chmod +x`. The verifier printed `VERIFY: PASS` there, over the item set that
existed at that time. `docs/VERIFY.md` states it and the transcript records it.
For v0.2.1 the whole verifier was re-run on `hw-gz` after the S3-9 assertion
changed, against the same binary by sha256, and again printed `VERIFY: PASS`;
that run and its log are described in `docs/VERIFY.md`. The item set has since
grown: `scripts/verify.sh` now declares `EXPECTED_ITEMS=26`, and
`docs/VERIFY.md` lists all 26 IDs. `scripts/verify.sh` now runs in CI on every
pull request targeting `main` and every push to `main`, so a regression is
caught by the repository's own workflow rather than by a manual run.

The hygiene gates read the **work tree**, not the index: `git grep --untracked`
is used for the credential, UUID, hostname and placeholder scans, so a new file
is checked before it is committed rather than after. It still honours
`.gitignore`, which keeps `dist/`, `.build/`, `.gate/` and `.env` out of the
scan. This was not cosmetic: `tests/coexist/` was added as untracked files, and
the previous tracked-only scan had never looked at them at all.

## A fact that bites certificate checks

Caddy's internal CA leaves the certificate subject distinguished name **empty**,
so the hostname lives only in the SAN extension. Any certificate assertion must
read the SAN, never `subject=`. The Gate 0 evidence for `b.test` shows exactly
this: `subject=` prints empty while the SAN carries `DNS:b.test`. The same fact
is why `deploy/Caddyfile` uses `tls internal` only as a placeholder posture.
