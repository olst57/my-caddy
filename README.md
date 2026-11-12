# my-caddy

Three roles — a website reverse proxy, an in-process naive proxy, and an
SNI-routed REALITY+Vision passthrough — run on one binary, one Caddyfile, and one
`:443` listener.

The current baseline is `v0.5.0`.

- [What this is](#what-this-is)
- [Routing](#routing)
- [Is this for you?](#is-this-for-you)
- [Quick start](#quick-start)
- [The three roles](#the-three-roles)
- [Pinned inputs](#pinned-inputs)
- [The one patch](#the-one-patch)
- [Build from source](#build-from-source)
- [Verification in three tiers](#verification-in-three-tiers)
- [Release assets](#release-assets)
- [Operating the delivery config](#operating-the-delivery-config)
- [Keeping up with upstream](#keeping-up-with-upstream)
- [Repository map](#repository-map)
- [Version history](#version-history)
- [Limits and non-claims](#limits-and-non-claims)
- [Licensing](#licensing)
- [Documentation index](#documentation-index)

## What this is

This repository is a build recipe and verification harness for a self-hosted Caddy binary. It is not
a Caddyfile collection or a distribution: no package to install, no image to pull. It also doubles as
a test bed for an agent-team working method. The deliverable is the binary; the method under test is
the evidence chain, which hands over original evidence, not a summary.

## Routing

```
client
  |  TCP :443, raw ClientHello
  v
layer4 wrapper -- SNI b.test --> Xray 127.0.0.1:19098 (PROXY v2, no local decryption)
  |
  |  any other SNI
  v
tls
  |-- CONNECT --------> forward_proxy
  `-- other requests -> reverse_proxy 127.0.0.1:8080
```

The raw ClientHello reaches the `layer4` wrapper before TLS. The SNI `b.test` goes to Xray on
`127.0.0.1:19098` with PROXY protocol v2 and no local decryption; every other SNI continues to
`tls`, where CONNECT traffic reaches `forward_proxy` and ordinary requests reach
`reverse_proxy 127.0.0.1:8080`. One listener, one SNI claim, no cross-role consumption.

## Is this for you?

**It fits** if you want one process and one port to serve a website, a naive endpoint, and a REALITY
tunnel, and you are willing to run a small verification suite before you trust a build. **It does not
fit** if you want a general-purpose Caddy module set, a container image, Windows or macOS binaries,
or a configuration you can deploy without reading `deploy/PLACEHOLDERS.md` first. None is in scope.

## Quick start

There are three tracks. Pick the one that matches what you need.

### Track A: use a release

Download four build assets from the release page: `caddy-linux-amd64`, `caddy-linux-arm64`,
`SHA256SUMS` and `pins.txt`. The six licence and notice files on the release page are not listed in
`SHA256SUMS`. From the directory that holds the downloads, run the checksum check; the names in
`SHA256SUMS` are bare, so a check run elsewhere reports a failure.

```bash
sha256sum -c SHA256SUMS
```

In a checkout of this repository, point `CADDY_BIN` at the binary and run the offline verifier. It
needs no root, no network, and no running stack.

```bash
CADDY_BIN=/path/to/caddy-linux-amd64 bash scripts/verify.sh
```

### Track B: build from source

With Bash, Git, Go exactly `1.26.9`, and network access to the module sources:

```bash
bash scripts/build.sh
```

[Build from source](#build-from-source) has the flags, the outputs, and the assertions.

### Track C: deploy

Deploying is a separate step and starts at `deploy/PLACEHOLDERS.md`. The shipped configuration is a
placeholder posture, not runnable as shipped.

## The three roles

**Site reverse proxy.** Ordinary web traffic is reverse proxied to a local backend over HTTP/1.1 and
HTTP/2 only. The delivery config pins `protocols h1 h2` on `:443`, so no QUIC listener is created and
no `Alt-Svc` is advertised. HTTP/3 is deliberately off: one SNI with two transport identities on one
port is the coexistence hazard this deployment exists to avoid.

**naive proxy.** The site block carries `forward_proxy`, which serves `https://` entry points over H2
under the same pin. `probe_resistance` is enabled, so an unauthenticated CONNECT is not answered with
`407`; it falls through to the site handler as an ordinary request. What shows that authentication
worked is an established tunnel, not the status code.

**REALITY and Vision.** The `layer4` listener wrapper reads the raw ClientHello and routes on SNI to a
loopback listener, prefixing the connection with PROXY protocol v2. Caddy does no local decryption on
that path; the tunnel endpoint does the TLS work.

### Two orderings that are load-bearing

`order forward_proxy before reverse_proxy` is mandatory. Without it, `caddy adapt` still exits 0, but
the site handler answers first and swallows every request, so no CONNECT reaches `forward_proxy` and
naive is dead silently. `scripts/verify.sh` item `S3-9` asserts the resulting order.

`layer4` before `tls` is equally mandatory. The wrapper must see the raw ClientHello; if `tls` ran
first, the ClientHello would already be consumed by the TLS stack, so REALITY passthrough could not
work. The order is semantic, not cosmetic.

## Pinned inputs

Everything the build consumes is a concrete value in `pins/build-inputs.env`, never a branch head and
never a range.

| Input | Pin |
| --- | --- |
| Caddy core | tag `v2.11.7` |
| naive forward proxy | fork of `klzgrad/forwardproxy`, `naive` branch |
| Layer 4 | fork of `mholt/caddy-l4`, `master` branch |
| xcaddy | `v0.4.7` |
| Go | `1.26.9` |
| Xray (probe only) | `v26.10.31` |

`pins/build-inputs.env` is the single source of truth. It records the exact 40-hex commits in
`PIN_CADDY_COMMIT`, `PIN_FWDPROXY_SHA` and `PIN_L4_SHA`. Branch names are not build inputs: the
upstream watch reads branch heads, the build consumes commits. The import paths stay the upstream
ones, so a fork does not change module identity. The two forks are the only forks: Caddy core is
consumed as a tag plus the patch below, and xcaddy and Go are released tools. Forking either would
buy nothing and cost a sync obligation.

The Go pin is measured, not guessed: the official naiveproxy Caddy `v2.11.7-naive2` build reports
`go1.26.9` in its embedded build metadata. The pin was added after `v0.4.3`; that release's receipt
records `go1.26.10` and is not rewritten. `tests/pins/check.sh` fails if any copy of a pin drifts from
this file, including the copies inside the workflows that call `setup-go`.

## The one patch

`patches/caddy-read-idle-timeout.patch` is the only patch here. The build refuses to start if
`patches/` holds a second `.patch` file. It is mandatory for a causal reason. The naive branch calls
`caddyhttp.IdleTimeoutsFromContext` from `forwardproxy.go`, and that symbol does not exist in Caddy
`v2.11.7`. The patch adds it, and the build also passes `--replace` so the Caddy module comes from
the patched tree rather than the unpatched tag.

The build line in the upstream naive README has neither the patch nor the replace, so copying it as
written does not compile.

## Build from source

Prerequisites: Bash, Git, Go exactly `1.26.9`, and network access to the module sources.
`bash scripts/build.sh` builds both linux/amd64 and linux/arm64. Add `--arch amd64` or `--arch arm64`
to select one, or `--print-pins` to print the inputs without building.

```bash
bash scripts/build.sh
bash scripts/build.sh --arch amd64
bash scripts/build.sh --print-pins
```

Outputs: `dist/caddy-linux-amd64`, `dist/caddy-linux-arm64`, `dist/SHA256SUMS`, `dist/pins.txt`.

The following environment variables override the defaults: `CADDY_TAG`, `CADDY_COMMIT`,
`FWDPROXY_SHA`, `L4_SHA`, `XCADDY_VERSION`, `PINS_FILE`, `DIST_DIR` and `BUILD_DIR`. `PIN_GO_VERSION`
is deliberately not overridable; the active toolchain must match it.

Before compiling, the script asserts that the tag's HEAD equals the pinned commit, that exactly one
patch is applied, that the patched file actually changed, that `go.mod` still pins `quic-go v0.63.0`
and carries no `sagernet` reference, and that after the build all four asserted modules are present
in the binary.

**Build triggers.** `.github/workflows/build.yml` watches five paths on `main`: `scripts/**`,
`patches/**`, `pins/**`, `tests/pins/**`, and the workflow file itself. A push touching any of them
builds the artifacts without uploading them. A published release builds and attaches them.
`workflow_dispatch` builds without uploading. Syncing a fork triggers nothing, because it lands
outside those paths, so run the build by hand afterwards.

## Verification in three tiers

| Tier | Suite | Items | Needs | In CI |
| --- | --- | --- | --- | --- |
| Offline | `scripts/verify.sh` | 26 | `CADDY_BIN` and `jq` | Every push |
| Coexistence | `tests/coexist/run.sh` | 8 | root, a free `:443`, one external TLS endpoint | After the offline job |
| End to end | `tests/e2e/run.sh` | 11 | root, six test ports, a real destination, key material | Syntax check and `--negative-preflight` |

**Offline, 26 items.** `scripts/verify.sh` reads the delivery configs and the repository's own
invariants: the adapter output, the handler order, the credential positions, the pin copies, the
licence set, and the `deploy/` freeze. It needs `CADDY_BIN` and `jq`, and nothing else: no listener,
no root, no network. CI runs it on every push.

**Coexistence, 8 items.** `bash tests/coexist/run.sh .` starts the real binary on `:443` and asserts
each role with a control next to the assertion: `CO-1` site leg, `CO-2` REALITY leg with a PROXY v2
record at the stub, `CO-3` unknown SNI claimed by nobody, `CO-4` naive tunnel over HTTP/1.1, `CO-5`
decoy control, `CO-6` the same naive hop over HTTP/2, `CO-7` no QUIC listener on UDP `:443`, `CO-8`
decoy and target are disjoint. It needs root and one external TLS endpoint, because the delivery ACL
refuses loopback targets.

**End to end, 11 items.** `tests/e2e/run.sh` runs eleven assertions across `E2E-01` through `E2E-08`:
the Vision tunnel, the destination certificate on an unauthenticated probe, the PROXY v2 header,
three wrong-credential controls for REALITY, three for naive (including the private-target ACL
denial), SNI rejection, and 30 serial plus 8 concurrent requests through each leg. `E2E-06`, the
non-443 address-shape guard, lives in `tests/fixtures/check.sh`. The suite derives its Caddyfile from
`deploy/Caddyfile` by literal substitution and reverse-diffs the derivation before starting
anything. It needs root, ports `8443`, `19099`, `18080`, `18081`, `18082` and `10802`, a real
destination, and key material that must not be committed. CI syntax-checks the harness and runs its
fail-closed `--negative-preflight` mode, which starts no process; CI does not execute the E2E suite.

**Execution coverage.** The `v0.4.3` amd64 asset ran the 26-item gate and the 8-item suite on the
Linux test host and in CI; its arm64 asset ran both on a GitHub-hosted `ubuntu-24.04-arm` runner,
recorded in `evidence/v0.4.3/arm64-release.log`. The `v0.5.0` amd64 asset has not been executed on
the Linux test host: the release CDN download ran at roughly 19 KB/s there, so the 53 MB asset was
deferred rather than half-transferred. The runtime numbers in `evidence/v0.5.0/` come from a locally
built binary with the same pinned inputs, and the `v0.5.0` arm64 asset was not executed at all.
Neither gap is upgraded to "verified" by this document. Executing an arm64 artifact is not the same
as rebuilding it byte for byte.

## Release assets

A build produces four files: `caddy-linux-amd64`, `caddy-linux-arm64`, `SHA256SUMS` and `pins.txt`. A
release carries those four plus `LICENSE`, `THIRD_PARTY_NOTICES.md`, `Apache-2.0.txt`, `MIT.txt`,
`BSD-3-Clause-Go.txt` and `MPL-2.0.txt` — ten assets. Both `v0.5.0` and `v0.4.3` carry the full set.
Sizes and checksums are not repeated here; `SHA256SUMS` is the authority.

`pins.txt` is the audit trail of a run: what it consumed, not what was intended. Seven `name=value`
lines: `caddy_tag`, `caddy_source_head`, `forwardproxy_sha`, `caddy_l4_sha`, `xcaddy_version`,
`go_version` and `patch`. To audit a build, read this file first. The fork commits and xcaddy version
pass back as `FWDPROXY_SHA`, `L4_SHA` and `XCADDY_VERSION` to replay the same inputs.

## Operating the delivery config

`deploy/` is the only authoritative configuration; `docs/` explains it and nothing else overrides
it. Five angle-bracket placeholders must be replaced before deployment: `<VLESS_UUID>`,
`<REALITY_PRIVATE_KEY>`, `<REALITY_SHORT_ID>`, `<NAIVE_USER>` and `<NAIVE_PASSWORD>`. They are
registered in `deploy/PLACEHOLDERS.md`, which is checked in both directions.

The literal hostnames `a.test`, `b.test`, `example.com` and the loopback addresses `127.0.0.1:19098`
and `127.0.0.1:8080` are replace-me literals, not angle-bracket tokens. A Caddy site address must
parse as a valid host, which is why the hostnames are literal.

**`tls internal` is a placeholder posture.** It makes Caddy issue certificates from its own local CA
so the skeleton validates and the structure is testable offline, not a production posture. Before
deployment, replace it with an ACME issuer or an explicitly managed certificate. Caddy's internal CA
leaves the subject DN empty, so certificate assertions must read the SAN, never the subject.

**There is deliberately no site-level `basic_auth`.** naive authenticates the CONNECT itself, through
`forward_proxy`'s own `basic_auth`, which reads `Proxy-Authorization`. Its credentials are base64
`user:pass`, not bcrypt, and they are a separate list from any site credential. A site-level
`basic_auth` is forbidden: it runs before `forward_proxy` and answers `401` to every request, so the
site serves nothing and no CONNECT can authenticate. An earlier release carried exactly that defect.

Do not add an `upstream` sub-directive to `forward_proxy`: setting one silently disables `acl` and
`ports`, which removes the default private-network deny. One listener, `protocols h1 h2`, no HTTP/3.

## Keeping up with upstream

Two scheduled workflows watch the outside world. Neither one changes what this repository builds.

`scripts/check-upstream.sh` and `upstream-watch.yml` run on the 1st and 15th at 01:00 UTC. The Caddy
and `xcaddy` tags come from upstream releases; the two module SHAs come from this project's own forks
(`github.com/olst57/forwardproxy` on `naive`,
`github.com/olst57/caddy-l4` on `master`), which are auto-synced from upstream, so the
fork head is the commit the build would eventually follow. The check never edits
`pins/build-inputs.env` and never starts a build: a bump needs a fork sync, a patch check and a full
gate run first. While its tracking issue is already open, later runs stay silent: no comment, no
edit, no duplicate.

`scripts/check-forks.sh` and `fork-sync.yml` run daily at 01:30 UTC, fast-forward the two module
forks when a `FORK_SYNC_TOKEN` token is configured, and report otherwise. They also stay silent while
their issue is already open. A sync never moves a pin, so it cannot change the binary. The forks
exist so that no upstream push can change what this repository produces. The cost: no upstream fixes
until the fork is synced. GitHub may start a scheduled run late, so these are cadences, not exact
wall-clock delivery times.

## Repository map

- `deploy/` — the delivery Caddyfile, the Xray inbound, and the placeholder register.
- `patches/` — the single Caddy patch the build applies.
- `pins/` — `build-inputs.env`, the pinned build inputs.
- `scripts/` — build, offline verification, the two watches, and evidence redaction.
- `tests/` — Gate 0 probes, the coexistence suite, the E2E harness, and offline guards.
- `docs/` — the build, verification, Xray, licensing and redaction references.
- `evidence/` — the redacted capture sets for `v0.4.3` and `v0.5.0`.
- `LICENSES/` — the four third-party licence texts.
- `.github/workflows/` — build, verify, Gate 0, the two watches, and the arm64 check.
- `.planning/` — the GSD state, requirements, roadmap, and phase and quick-task records.

## Version history

`v0.4.0` was the first release with all three roles on one port, and it carried a site-level
`basic_auth` defect plus fork refs that resolved to live branch heads. `v0.4.3` removed the defect,
pinned both fork commits, and added the arm64 execution record. `v0.5.0` closed REALITY with the E2E
harness and the redacted `evidence/v0.5.0/` capture set. Earlier tags are retired; the body of each
release is the changelog, not this file.

## Limits and non-claims

- No real domain, address, cloud instance, credential, identifier or REALITY key appears here. Where
  a concrete value is needed, read the redacted placeholders in `deploy/` and `docs/`.
- Byte-identical rebuilds are not established: the toolchain is pinned, but two clean builds of the
  same commit with the same inputs have not been compared, and build paths, build IDs and other
  compiler inputs may still differ.
- HTTP/3 is not claimed. The delivery config turns it off, and earlier local H3 measurements predate
  the pin.
- The execution-coverage gaps above are stated, not upgraded: the `v0.5.0` amd64 asset was not run on
  the Linux test host, and the `v0.5.0` arm64 asset was not executed at all.
- Windows is an authoring host only; it cannot execute the Linux ELF.

## Licensing

The repository's own material is proprietary and all rights reserved; see `LICENSE`
(`LicenseRef-Proprietary`). The release binary links Apache-2.0, MIT and BSD-3-Clause components, and
the Caddy source is modified at build time. `THIRD_PARTY_NOTICES.md`, `LICENSES/` and
`docs/LICENSING.md` record the components, the upstream refs, the licence-text hashes and the
obligations. This is a provenance record, not legal advice.

## Documentation index

- `docs/BUILD.md` — how the binary is produced.
- `docs/VERIFY.md` — reproducing the offline checks and what the runtime tests answered.
- `docs/XRAY.md` — the REALITY inbound and how it pairs with Caddy.
- `docs/LICENSING.md` — the licence conclusion and the obligations.
- `docs/REDACTION.md` — the domain-token allowlist and the redaction rules.
- `evidence/README.md` — the redacted evidence set and its provenance.
- `tests/e2e/README.md` — the REALITY end-to-end harness.
- `AGENTS.md` — the project instructions and constraints.
