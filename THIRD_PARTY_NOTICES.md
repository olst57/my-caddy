# Third-party notices

The `my-caddy` release binary is a Caddy build that links the components
below. Full license texts are in [`LICENSES/`](LICENSES/). This file records
the copyright lines and the role each component plays.

This notice accompanies release `v0.4.3`. The repository's own material is
covered separately by [`LICENSE`](LICENSE), which keeps the existing
all-rights-reserved default and does not alter any third-party license.

## Linked into `caddy-linux-amd64` and `caddy-linux-arm64`

| Component | Version / commit | License | Copyright |
| --- | --- | --- | --- |
| Caddy | `v2.11.7` (`72dd0fb0`) | Apache-2.0 | The Caddy Authors |
| caddy-l4 | `96e1a6bf` | Apache-2.0 | The caddy-l4 Authors |
| forwardproxy (naive fork) | `e747854e` | Apache-2.0 | The forwardproxy Authors |
| quic-go | `v0.63.0` | MIT | 2016 the quic-go authors & Google, Inc. |
| Go runtime | `go1.26.10` | BSD-3-Clause | The Go Authors |

The three Apache-2.0 components ship byte-identical license texts (sha256
`cfc7749b…3d30`); [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) is that
text.

The exact texts are also pinned by hash in
[`docs/LICENSING.md`](docs/LICENSING.md) and checked by
`tests/licenses/check.sh`:

- `Apache-2.0.txt` — `cfc7749b96f6`
- `MIT.txt` — `77d0b7b53e8a`
- `BSD-3-Clause-Go.txt` — `911f8f578293`
- `MPL-2.0.txt` — `1f256ecad192`

The Caddy source tree is modified at build time by
`patches/caddy-read-idle-timeout.patch`, which adds
`modules/caddyhttp/idletimeout.go`. That modification is stated here as
required by Apache-2.0 section 4(b). The patched tree is not distributed;
only the compiled binary is.

## Build tooling (not linked)

| Component | Version | License |
| --- | --- | --- |
| xcaddy | `v0.4.7` | Apache-2.0 |

## Deployment dependency (not shipped)

| Component | Version | License |
| --- | --- | --- |
| Xray-core | `v26.10.31` | MPL-2.0 |

`deploy/xray/config.json` is a configuration file. The Xray binary is installed
by the operator and is not part of any artifact published from this repository,
so its MPL-2.0 obligations apply to whoever distributes that binary.

## Scope of this notice

This file names the components whose licenses were verified against the
upstream `LICENSE` at the pinned ref, including the two replaced modules and
the quic-go/Go runtime that are part of the delivered binary. It is not a
blanket statement that every transitive Go module has been enumerated here;
those modules are resolved by Caddy's own `go.mod` at `v2.11.7`. A reader who
needs a module-by-module audit can start from
`go version -m dist/caddy-linux-amd64`.

This is a provenance record, not legal advice.
