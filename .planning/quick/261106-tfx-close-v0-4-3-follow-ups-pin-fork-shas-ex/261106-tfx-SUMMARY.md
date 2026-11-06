---
quick_id: 261106-tfx
slug: close-v0-4-3-follow-ups-pin-fork-shas-ex
status: complete
completed: 2026-11-06

provides:
  - pinned build inputs in pins/build-inputs.env
  - arm64 execution of the published v0.4.3 asset
  - license and SPDX record plus release assets

actuals:
  commits: 5
  release_assets_added: 6

key-files:
  created:
    - pins/build-inputs.env
    - tests/pins/check.sh
    - LICENSE
    - THIRD_PARTY_NOTICES.md
    - LICENSES/
    - docs/LICENSING.md
    - tests/licenses/check.sh
    - .github/workflows/verify-arm64-release.yml
    - evidence/v0.4.3/arm64-release.log
  modified:
    - scripts/build.sh
    - .github/workflows/build.yml
    - .github/workflows/gate0.yml
    - .github/workflows/verify.yml
    - docs/BUILD.md
    - docs/VERIFY.md
    - README.md
    - AGENTS.md

requirements-completed: [BLD-01, RUN-01, LIC-01]
---

# Quick Task Summary: Close the v0.4.3 Follow-ups

The three follow-ups named after `v0.4.3` are closed without moving the tag or
replacing a binary.

## Task 1 — build inputs pinned

`pins/build-inputs.env` is now the only source for the Caddy tag/commit, the
two fork commits and xcaddy. `scripts/build.sh` no longer runs `git ls-remote`
against a branch head, and `tests/pins/check.sh` rejects duplicate keys,
non-40-hex commits, branch lookups and a moved Caddy tag.

Verification:

- `bash tests/pins/check.sh` → `PINS: PASS`.
- CI at `0ef98bb`: build run 42224616127, verify run 42224616092, gate0 run
  42224616089, all green.
- The build log reports the published hashes:
  - amd64 `693057c2f596e163144eb0d2991bd4c8b19cadb351199cb8cc87b183647618f2`
  - arm64 `76760bdf0ebf3447246806dbc8f18ee6a89871423625dec0a3b0d5798f9abd36`
- The receipt names forwardproxy `e747854e…`, caddy-l4 `96e1a6bf…`, xcaddy
  `v0.4.7` and Go `go1.26.10`.

## Task 2 — arm64 executed

`.github/workflows/verify-arm64-release.yml` downloads the published asset by
tag, checks a required sha256 input **before** execution, asserts
`runner_arch=aarch64`, and runs `version`, `list-modules`, the 26-item offline
gate and the 8-item coexistence suite.

Two failures were kept as real history rather than edited away:

- run 42224995715 — the upload action pin was mistyped; fixed in `89be9cf`.
- run 42225382758 — the module inventory was written under `evidence/`, and
  S7-13 read a Caddy module id as a hostname. The inventory now goes to
  `.gate/arm64/modules.txt`, outside the scanned tree.

The successful run is
<https://github.com/olst57/my-caddy/actions/runs/42228779590> at `820b890`:

- `runner_arch=aarch64`, `go version go1.26.10 linux/arm64`
- asset sha256 `76760bdf…bd36`, checked before execution
- `PASS=26 FAIL=0`, `VERIFY: PASS`
- `ITEM CO-1`…`ITEM CO-8`, `COEXIST: PASS`

The extracted record is `evidence/v0.4.3/arm64-release.log` (47 lines). The
evidence archive hash over all five files is `4521633c…9464`.

## Task 3 — licenses recorded and published

- `LICENSE` declares `SPDX-License-Identifier: LicenseRef-Proprietary` and
  states the existing all-rights-reserved default. This is a least-loss
  assumption: the owner never selected an open-source license, so this task
  does not grant rights on the owner's behalf.
- `LICENSES/` carries the upstream texts and `THIRD_PARTY_NOTICES.md` names the
  linked components, the Caddy modification, xcaddy (not linked) and Xray (not
  shipped).
- `docs/LICENSING.md` records the ref, SPDX identifier and text hash per
  component.
- `bash tests/licenses/check.sh` → `LICENSES: PASS`; `verify.yml` runs it before
  the build.
- Release 435420474 now lists ten assets: the four build/provenance files plus
  `LICENSE`, `THIRD_PARTY_NOTICES.md`, `Apache-2.0.txt`, `MIT.txt`,
  `BSD-3-Clause-Go.txt` and `MPL-2.0.txt`. The notes no longer claim arm64 was
  unexecuted and now cite run 42228779590.

## hw-gz re-verification

The `hw-gz` checkout was fast-forwarded from `083ec57` to `820b890` with a
31 KB local git bundle; no download was performed on the server. The binary in
place was the published amd64 asset
(`693057c2f596e163144eb0d2991bd4c8b19cadb351199cb8cc87b183647618f2`).

- `bash scripts/verify.sh` → `PASS=26 FAIL=0`, `VERIFY: PASS`
- `bash tests/coexist/run.sh "$PWD"` → `ITEM CO-1`…`ITEM CO-8`,
  `COEXIST: PASS`

## Deviations and open items

- The repository stays proprietary. Changing that is the owner's decision, not
  a side effect of a license audit.
- Byte-identical rebuilds are still not established: the Go patch level follows
  the runner cache.
- REALITY remains deferred; its placeholder pair is not a working handshake.
