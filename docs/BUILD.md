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

The `build` workflow builds and checksums the artifacts. It does **not** run
`scripts/verify.sh`; no committed workflow does. The verifier was run manually
on ubuntu-latest in a GitHub Codespace against this artifact. See
`docs/VERIFY.md` for the provenance of that run and for the `chmod +x`
requirement. The reproducibility limit is stated there as well; its evidence
entry (D-5) is in `.gate/release/DEVIATIONS.md`, which is gitignored and not part
of the tracked tree.

## Pinned inputs

Every build input is a concrete commit or tag, recorded in `dist/pins.txt` so a
run states exactly what it built. The values in this slice are:

```text
caddy_tag=v2.11.7
caddy_source_head=72dd0fb067f6d7826c7f79907670ba4a713bfe37
forwardproxy_sha=e747854e78743dba85c039b38ed185fb11d93667
caddy_l4_sha=f607ccea1b7dbe61cfcec089f2005621c61f7e6c
xcaddy_version=v0.4.7
patch=caddy-read-idle-timeout.patch
```

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

`scripts/build.sh` is the executable form of this. It resolves the pins, clones
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

`caddy-linux-amd64` is the native artifact and is the only one that is ever
executed. `caddy-linux-arm64` is **artifact-verified only, never executed**: no
behavioural claim exists for it in this slice. This is a deliberate scope
boundary, not an oversight.

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
- Any arm64 behaviour. `caddy-linux-arm64` is artifact-verified only.
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
grown: `scripts/verify.sh` now declares `EXPECTED_ITEMS=24`, and
`docs/VERIFY.md` lists all 24 IDs. No CI job runs the verifier, so both runs are
manual and neither is re-executable from the repository alone.

## A fact that bites certificate checks

Caddy's internal CA leaves the certificate subject distinguished name **empty**,
so the hostname lives only in the SAN extension. Any certificate assertion must
read the SAN, never `subject=`. The Gate 0 evidence for `b.test` shows exactly
this: `subject=` prints empty while the SAN carries `DNS:b.test`. The same fact
is why `deploy/Caddyfile` uses `tls internal` only as a placeholder posture.
