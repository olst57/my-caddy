---
quick_id: 261106-tfx
slug: close-v0-4-3-follow-ups-pin-fork-shas-ex
description: "Close v0.4.3 follow-ups: pin fork SHAs, execute arm64, conclude licenses"
status: in_progress
created: 2026-11-06
---

# Quick Task: Close v0.4.3 Follow-ups

This task closes the three follow-ups named after the `v0.4.3` release without
reopening that milestone or rewriting its tag.

## Assumptions

- The repository owner has not selected an open-source license. The least-loss
  decision is to keep the existing default, all rights reserved, and state it
  explicitly rather than granting rights the owner did not request.
- `hw-gz` remains the Linux runtime test host for amd64. It is x86_64 and has no
  ARM emulator, so ARM64 execution uses a GitHub-hosted `ubuntu-24.04-arm`
  runner. The downloaded artifact is hashed before execution.
- The published `v0.4.3` binaries are not replaced. License material may be
  added to the release without changing an existing binary.

## Task 1: Pin the delivery inputs

**Files:** `pins/build-inputs.env`, `scripts/build.sh`, `tests/pins/check.sh`,
`.github/workflows/{gate0,build,verify}.yml`, `docs/BUILD.md`, `docs/VERIFY.md`

**Action:** Read both fork SHAs and the Caddy tag/commit from one tracked file.
Reject runtime branch resolution, false receipts, duplicate keys and a moved
Caddy tag. Run the static pin check before any delivery build.

**Verify:** `bash tests/pins/check.sh` prints `PINS: PASS`; the GitHub build
produces a receipt whose fork fields equal the pins file.

**Done:** No build path follows `refs/heads/*`, and the receipt is derived from
the fixed file rather than a branch head.

## Task 2: Execute the arm64 release artifact

**Files:** `.github/workflows/verify-arm64-release.yml`, `docs/BUILD.md`,
`docs/VERIFY.md`, `README.md`, `evidence/v0.4.3/arm64-*`

**Action:** Add a manual workflow on a real GitHub-hosted ARM64 runner. It
downloads `caddy-linux-arm64` from the pinned `v0.4.3` release, checks the
recorded sha256, runs `version`, `list-modules`, the 26-item offline verifier and
the 8-item coexistence suite. Archive the resulting log and run URL.

**Verify:** The workflow is green on `ubuntu-24.04-arm`, and the archived log
names `aarch64`, the asset hash, `PASS=26 FAIL=0`, `CO-1` through `CO-8`, and
`VERIFY: PASS` / `COEXIST: PASS`.

**Done:** Documentation distinguishes the executed release asset from a
locally rebuilt ARM64 binary; no architecture claim is inferred without a run.

## Task 3: Conclude licenses and verify the release

**Files:** `LICENSE`, `LICENSES/`, `THIRD_PARTY_NOTICES.md`,
`docs/LICENSING.md`, `tests/licenses/check.sh`, `README.md`,
`.github/workflows/verify.yml`

**Action:** Record SPDX identifiers, upstream refs and license-text hashes for
the linked components. State the repository's own license explicitly. Add a
static license check, attach the notice/license material to the existing
release, and update the release notes to remove the stale arm64 limitation.

**Verify:** `bash tests/licenses/check.sh` prints `LICENSES: PASS`; the release
API lists the notice assets; `scripts/verify.sh` remains 26/26 on `hw-gz`.

**Done:** A reader can identify the binary's direct third-party licenses, find
the corresponding texts, and see the repository's own usage terms without a
silent “all rights reserved” default.
