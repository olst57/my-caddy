# my-caddy

This repository is the build recipe for a personal, self-hosted Caddy binary:
one binary that fills three roles at once, all of them on port 443. It is not a
collection of Caddyfile fragments, and it is not a distribution. The sections
below cover where the code comes from, how the binary is assembled and checked,
how to obtain it, and what this document does not claim.

## Caddy base

The Caddy core is `github.com/caddyserver/caddy` at tag `v2.11.7`. That tag is
the baseline for everything downstream: the module sources, the patch, and the
four module assertions are all stated against it. This document does not
restate Caddy's configuration language; `deploy/` and `docs/` are the
authoritative places for that.

## The two modules and their forks

The binary carries two modules that are not part of Caddy core. Each one reaches
this repository through a fork, so both sides of the pair are written out here.

- naive forward proxy: the upstream is the `naive` branch of
  `github.com/klzgrad/forwardproxy`; this project builds the `naive` branch of
  `github.com/olst57/forwardproxy`.
- Layer 4: the upstream is the `master` branch of
  `github.com/mholt/caddy-l4`; this project builds the `master` branch of
  `github.com/olst57/caddy-l4`.

The import path stays the upstream one, so the module identity does not change
when the source moves to a fork. How each module is configured belongs to
`docs/XRAY.md` and `deploy/`, not here.

## Build toolchain and Go

The binary is assembled by `github.com/caddyserver/xcaddy`, always at the
newest stable tag rather than at a fixed one. In the `v0.4.2` build that lookup
resolved to `v0.4.7`. Go comes from the `1.26.x` line in CI; the `v0.4.2` build
reported `go1.26.10`. Both are recorded as the values that run actually used,
not as values a future run is guaranteed to use.

## The single patch, and why it is mandatory

`patches/caddy-read-idle-timeout.patch` is the only patch here, and the build
refuses to start if `patches/` holds more than one `.patch` file: the
repository must hold only one .patch, and a second one is a scope violation
rather than a convenience.

The reason it is mandatory is causal, not stylistic. The naive branch calls
`caddyhttp.IdleTimeoutsFromContext` from `forwardproxy.go`, and that symbol does
not exist in Caddy `v2.11.7`. The patch adds it. On its own the patch is not
enough either, because xcaddy would still compile the module against the
unpatched tag; the build also passes `--replace` so the Caddy module is taken
from the local patched tree. Both are therefore required, and the build does
not compile with only one of them. The build line printed by the upstream naive
README contains neither the patch nor the replace, so copying it as written
does not compile.

## Why the forks are ours, and what that costs

This is a design decision, not an accident. The build used to resolve commit
ids straight from the upstream `refs/heads`, which tied the artifacts to
somebody else's branch heads: the `v0.4.0` and `v0.4.1` binaries differ only
because a caddy-l4 branch head moved, with no commit landing in this repository
at all. The forks cut that link. Moving to a newer upstream is now the explicit
act of syncing a fork, and no upstream push can change what this repository
produces.

The cost is stated plainly: there are no upstream fixes until you sync the fork.
A fork that is never synced is a fork that slowly falls behind.

## Build triggers

`.github/workflows/build.yml` has three inputs.

- A push to `main` whose changed paths fall under `scripts/**`, `patches/**`,
  or the workflow file itself: the artifacts are built but do not upload.
- A published release: the artifacts are built and attached to the release.
- A manual `workflow_dispatch`: the artifacts are built and are not uploaded.

Syncing a fork does not trigger a build, because a sync lands outside those
paths. After a sync, run the build again by hand.

## Artifacts and the module assertion

Every build asserts that the binary carries four modules:
`http.handlers.forward_proxy`, `layer4.handlers.proxy`, `caddy.listeners.layer4`,
and `layer4.matchers.quic`. A binary that is missing any one of them fails the
build instead of shipping.

Four assets come out of a run: `caddy-linux-amd64`, `caddy-linux-arm64`,
`SHA256SUMS`, and `pins.txt`. Sizes and checksums are not repeated here, because
they change with every build.

## What pins.txt records

`pins.txt` is the audit trail of a run: what it consumed, not what was
intended. It holds seven fields, each written as a `name=value` line.

- `caddy_tag=`: the Caddy tag that was built.
- `caddy_source_head=`: the Caddy commit the source tree was cloned at.
- `forwardproxy_sha=`: the forward proxy commit that was used.
- `caddy_l4_sha=`: the Layer 4 commit that was used.
- `xcaddy_version=`: the xcaddy tag that was installed.
- `go_version=`: the Go toolchain the run reported.
- `patch=`: the patch file that was applied.

To audit a build, read this file first. The two fork commits and the xcaddy
version in it can be passed back to the build as `FWDPROXY_SHA`, `L4_SHA` and
`XCADDY_VERSION` to replay the same inputs.

## How the binary is verified

Only the binary for the architecture of the build host is executed, and only
that one is checked for its four modules. The arm64 artifact is verified at
build-level only, and it is not executed.

That is the whole of it: no arm64 binary from this repository has ever been run,
and none is claimed to have been run.

## One binary, three roles on 443

One binary answers on port 443 in three roles.

**Site reverse proxy.** Ordinary web traffic is reverse proxied to a local site,
and HTTP/3 is available on that path: a local HTTP/3 client was measured at
`%{http_version}=3` with a `200` and the site's identifying header present.

**naive proxy.** This role serves two entry points: `https://` connections
travel over H2 and `quic://` connections over H3, both measured. `basic_auth`
is in force, and `probe_resistance` is enabled. Because of `probe_resistance`,
an unauthenticated CONNECT is not answered with `407`; it falls through to the
site handler as an ordinary request. What tells you whether authentication
worked is whether a tunnel was established, not the status code.

**REALITY and Vision.** The layer 4 handler routes on SNI to a loopback
listener and prefixes the connection with PROXY protocol v2. Caddy does no local
decryption on that path; the tunnel endpoint does the TLS work. An end to end
request through it was measured at `200`.

## Built by an agent team, and used as a test bed

This repository is built by Qoder's agent team, and it doubles as a test bed for
that team's own capability. The deliverable is the binary; the working method is
the thing under test.

## Roles and evidence discipline

The chain is fixed: evidence gathering, requirement framing, spec decomposition,
targeted implementation, item grading, release execution. Each stage hands over
the original evidence rather than a summary of it. A stage whose evidence fails
a check is sent back to the previous stage, and it does not advance until that
check is satisfied.

## Known limitations

**naive TLS uses an internal CA.** naive terminates TLS with Caddy's own
internal CA, so a client must trust the root certificate before it can connect
at all; on a clean machine the root has to be installed first. A client without
it sees a failed handshake, and that is not a configuration error.

**REALITY matching.** The `serverNames` and `dest` settings must match a real
domain that resolves and serves TLS. A mismatch fails at connection time.

**HTTP/3 from the public internet.** The HTTP/3 path from the public internet
has not been exercised. Every HTTP/3 measurement so far was taken on a local
host or inside a private network.

**Byte identity across reruns.** The Go patch level floats with the runner
cache, so `1.26.x` can land on a different patch between two runs. Two reruns of
the same commit are therefore not byte-identical, and the difference shows up in
the `go_version` field of `pins.txt`.

## Quick start

1. Download the assets from the release page: `caddy-linux-amd64`,
   `caddy-linux-arm64`, `SHA256SUMS`, and `pins.txt`.
2. From the directory that holds them, run `sha256sum -c SHA256SUMS`. The
   checksum file lists bare filenames, so the check reports a failure if you run
   it from somewhere else.
3. To trigger a build by hand, run the workflow with `workflow_dispatch`. After
   syncing a fork, run the build again; the sync itself does not start one.

## Confidentiality and unproven claims

Nothing in this document names a real domain, a public address, a cloud
instance, a credential, a unique identifier, or a REALITY key. Where a concrete
value would be needed, the text either omits it or points at `deploy/` and
`docs/`, which is where the redacted placeholders live.

This document also does not claim that the arm64 artifact has been run, that
HTTP/3 has been verified from the public internet, or that a byte-identical
rebuild has been established. Each of those is written as not done, here and in
the limitations above.

## Out of scope in this round

License texts and third-party notices were not verified in this round, so no
license conclusion is drawn here. Community files and an English copy are out of
scope for this round as well.
