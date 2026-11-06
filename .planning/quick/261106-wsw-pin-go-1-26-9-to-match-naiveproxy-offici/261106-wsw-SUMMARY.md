---
quick_id: 261106-wsw
slug: pin-go-1-26-9-to-match-naiveproxy-offici
status: complete
completed: 2026-11-07

provides:
  - Go 1.26.9 as a non-overridable delivery build input
  - measured provenance from the official naiveproxy Caddy binary
  - a clean hw-gz build that passes all 26 offline and 8 coexistence items

actuals:
  commits: 4
  hw_gz_binary_sha256: 872caeee23f804fcb2991e26f3c7fe9526eb8a1d5003d4dedcc280c95d762f1d
  ci_verify_run: 42249057819
  ci_build_run: 42249057708
  ci_gate0_run: 42249057842

key-files:
  created:
    - .planning/quick/261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici/261106-wsw-PLAN.md
    - .planning/quick/261106-wsw-pin-go-1-26-9-to-match-naiveproxy-offici/261106-wsw-SUMMARY.md
  modified:
    - pins/build-inputs.env
    - scripts/build.sh
    - tests/pins/check.sh
    - .github/workflows/build.yml
    - .github/workflows/gate0.yml
    - .github/workflows/verify.yml
    - .github/workflows/verify-arm64-release.yml
    - README.md
    - docs/BUILD.md
    - .planning/codebase/STACK.md
    - AGENTS.md
    - .planning/STATE.md

requirements-completed: [BUILD-04]
---

# Quick Task Summary: Pin Go 1.26.9 to the naiveproxy Toolchain

The official naiveproxy Caddy release `v2.11.7-naive2` was built with
`go1.26.9`. That is now the only Go patch level the delivery build accepts.
The `v0.4.3` release is history and was not rewritten.

## Task 1 — measure the official toolchain, then make it non-overridable

The version was read from the Go build metadata embedded in the official
`caddy` binary, not inferred from a version range:

- Archive `caddy-forwardproxy-naive.tar.xz` sha256
  `c273dc07dd79c5919f97639cbdcb559d40ce90475dbd8aac80641b0a8c8065ff`.
- Extracted `caddy` sha256
  `ee571de2ed6d68dd29c1f83e5dbc62d043982c65d73ea230b78389253743527c`.
- The embedded build metadata reports `go1.26.9`; no other Go version matched.

The matching official Go archive was used for the real build:

- `go1.26.9.linux-amd64.tar.gz`, 66,935,201 bytes, sha256
  `42d158b4d8f7b61ac0a830567c940a86098fb7aac52e467a5ebec03ef5cc2f8d`.
- Extracted toolchain reports `go version go1.26.9 linux/amd64`.

The archive hash differs from the one previously used by the CI mirror
(`3d4726…`). The official archive was used; the mirror hash is not a substitute
for the same bytes.

`pins/build-inputs.env` now carries `PIN_GO_VERSION=1.26.9`.
`scripts/build.sh` exports `GOTOOLCHAIN=local` and refuses to compile unless
`go env GOVERSION` is exactly `go1.26.9`. `PIN_GO_VERSION` is deliberately not
overridable by an environment variable. `tests/pins/check.sh` requires exactly
seven pin keys and exactly one `GO_VERSION` per workflow, each equal to the pin.
The four workflows now declare `1.26.9`.

Negative control: a fake `go` reporting `go1.26.10` stopped the build before
compilation with
`FATAL: Go toolchain is 'go1.26.10', expected go1.26.9`.

## Task 2 — documentation updated without rewriting history

`README.md`, `docs/BUILD.md`, `.planning/codebase/STACK.md` and `AGENTS.md`
now name `1.26.9`, explain that it was measured from the official binary, and
show `go_version=go1.26.9` in the receipt example. They also state that the
`v0.4.3` receipt and evidence remain at `go1.26.10`.

## Task 3 — clean build and both suites on hw-gz

The server received local copies of the official Go archive, an unpatched
Caddy source archive, a repository bundle and a file-based Go module proxy.
No GitHub download was needed on the host.

Build receipt:

```text
caddy_tag=v2.11.7
caddy_source_head=72dd0fb067f6d7826c7f79907670ba4a713bfe37
forwardproxy_sha=e747854e78743dba85c039b38ed185fb11d93667
caddy_l4_sha=96e1a6bf063c206c3bd09ca6dc4a0484a158d83f
xcaddy_version=v0.4.7
go_version=go1.26.9
patch=caddy-read-idle-timeout.patch
```

The binary is 53,026,978 bytes with sha256
`872caeee23f804fcb2991e26f3c7fe9526eb8a1d5003d4dedcc280c95d762f1d`.

Results:

- `bash scripts/verify.sh` → `PASS=26 FAIL=0`, `VERIFY: PASS`.
- `bash tests/coexist/run.sh "$PWD"` → `ITEM CO-1` through `ITEM CO-8`,
  `COEXIST: PASS`.

The first offline run was `PASS=25 FAIL=1` because the uploaded git bundle did
not carry the `v0.3.0` tag, so S7-18 could not verify the deploy freeze. The
tag was added only inside the throwaway `/tmp` clone and the suite was rerun.
This was a run-fixture gap, not a source change; it is recorded rather than
edited away.

## CI

All three workflows at `decb4cf` passed:

- verify
  <https://github.com/olst57/my-caddy/actions/runs/42249057819>:
  `go version go1.26.9 linux/amd64`, `PASS=26 FAIL=0`, `VERIFY: PASS`,
  `ITEM CO-1`…`ITEM CO-8`, `COEXIST: PASS`.
- build
  <https://github.com/olst57/my-caddy/actions/runs/42249057708>:
  receipt names `go_version=go1.26.9`; amd64 sha256
  `c780d1d63fa72b355f28ff7625968860dd9f36294ec884ca3b34920126bd04a8`,
  arm64 sha256
  `8fcd7377649d9351ce0e7b2b42d9a890bcfc16cc0fd6a3d7e7ee1e16bf1c1b49`.
- gate0
  <https://github.com/olst57/my-caddy/actions/runs/42249057842>:
  green.

The CI amd64 hash (`c780d1…`) differs from the hw-gz hash (`872cae…`) even
though both receipts name the same sources and `go1.26.9`. That is direct
evidence that a byte-identical rebuild is still not established.

## Deviations and open items

- Byte-identical rebuilds remain unproven. The Go patch level is now fixed, but
  two clean builds have not produced the same bytes; build IDs and host paths
  are still free to differ. No claim of bit-for-bit reproducibility is made.
- `v0.4.3` was not moved, replaced or re-released. Its tag, assets and evidence
  still describe `go1.26.10`.
- No new release was created by this task.
- REALITY remains deferred; this task did not touch its placeholder pair.
