---
quick_id: 261106-wsw
slug: pin-go-1-26-9-to-match-naiveproxy-offici
description: "Pin Go 1.26.9 to match the official naiveproxy Caddy build"
status: in_progress
created: 2026-11-06
---

# Quick Task: Pin Go to the naiveproxy official Caddy toolchain

The official naiveproxy Caddy release `v2.11.7-naive2` was built with
`go1.26.9`, measured from the Go buildinfo embedded in its published `caddy`
binary. The repository must use that exact patch level rather than the floating
`1.26.x` range.

## Assumptions

- `v0.4.3` remains immutable. Its historical evidence and license notice record
  `go1.26.10`; this task changes the next build input, not the old release.
- `1.26.9` satisfies every current module minimum: Caddy `v2.11.7` declares
  `go 1.26.0`, the pinned `caddy-l4` fork declares `go 1.26.9`, and
  forwardproxy declares `go 1.21.0`.
- The Linux test host remains `hw-gz`. Go and the repository are uploaded from
  the authoring machine so the host does not download them from GitHub.

## Task 1: Make Go 1.26.9 a fixed build input

**Files:** `pins/build-inputs.env`, `scripts/build.sh`, `tests/pins/check.sh`,
`.github/workflows/{build,gate0,verify,verify-arm64-release}.yml`

**Action:** Add `PIN_GO_VERSION=1.26.9`. Make the delivery build fail unless the
active `go env GOVERSION` equals `go1.26.9`. Teach the static pin check to
require the new key, reject a floating workflow value, and compare the receipt's
`go_version` with the pin.

**Verify:** `bash tests/pins/check.sh` prints `PINS: PASS`; a build run on
`hw-gz` prints `go version go1.26.9 ...` and its `dist/pins.txt` contains
`go_version=go1.26.9`.

**Done:** No delivery build can silently use a different Go patch level.

## Task 2: Update build documentation without rewriting history

**Files:** `README.md`, `docs/BUILD.md`, `.planning/codebase/STACK.md`,
`AGENTS.md`

**Action:** State that the next build pins `1.26.9` to the toolchain measured in
the official naiveproxy Caddy binary. Add the new field to the receipt example,
update the "six values" count, and replace the floating-patch limitation with
the remaining unproven claim: a double clean build has not yet been compared.
Keep `v0.4.3` license/evidence references at `go1.26.10`.

**Verify:** No tracked documentation still describes the delivery build as
following `1.26.x`.

**Done:** A reader can tell which Go version the next build uses, why it was
chosen, and which historical release used a different patch.

## Task 3: Rebuild and run the complete gate on hw-gz

**Files:** `dist/pins.txt`, `.gate/` evidence only (both ignored)

**Action:** Upload the pinned Go 1.26.9 Linux archive and a repository bundle to
`hw-gz`. Build `caddy-linux-amd64` there with `GOTOOLCHAIN=local`, confirm the
receipt, then run `scripts/verify.sh` (26 items) and
`tests/coexist/run.sh` (8 items) with the freshly built binary.

**Verify:** `PASS=26 FAIL=0`, `VERIFY: PASS`, `ITEM CO-1` through `ITEM CO-8`,
and `COEXIST: PASS`; record the binary sha256 and host output.

**Done:** The pinned toolchain has produced a binary that passes both suites on
the real Linux host.
