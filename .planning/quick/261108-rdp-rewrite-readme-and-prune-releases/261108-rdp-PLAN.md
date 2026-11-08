---
quick_id: 261108-rdp
slug: rewrite-readme-and-prune-releases
description: "Rewrite the public README and converge the release set to v0.5.0 and v0.4.3"
status: in_progress
created: 2026-11-08
---

# Quick Task: Rewrite the public README and prune the release set

The README still describes `v0.4.3` as the current baseline and carries five
statements the tree has since contradicted. The release page carries eight tags,
six of which no longer have a reason to exist. This task fixes the entry
document, removes the internal codename that leaked into public docs, and leaves
exactly two releases and two tags: `v0.5.0` and `v0.4.3`.

## Assumptions

- The README stays English and single-language. `evidence/README.md` stays
  Chinese; only its index and its dead references change.
- The README describes what the repository is now. Version history is one short
  paragraph, not a changelog; `.gate/release-notes-*.md` already holds those.
- `deploy/` is frozen. The `v0.2.1` strings inside `deploy/Caddyfile` and
  `deploy/PLACEHOLDERS.md` are load-bearing for `S7-18` and are not touched.
- `Sprint N` and `SP*-*` identifiers stay; they are internal vocabulary, not
  host names, and renaming them would invalidate the evidence index.
- The `v0.5.0` amd64 asset was never executed on the Linux test host. That
  deferral stays stated as a deferral.

## Task 1: Rewrite `README.md`

**Files:** `README.md`

Layered so the first screen answers "what is this / should I use it / how do I
run it in a minute", and everything below that is operator material: pinned
inputs, the verification tiers, the release asset set, the deployment posture,
and the drift/fork automation.

Corrections carried in the same pass: the naive credential position (site-level
`basic_auth` is forbidden; `forward_proxy` authenticates the CONNECT from
`Proxy-Authorization`), `tls internal` as a placeholder posture rather than a
known limitation, the arm64 claim scoped to `v0.4.3`, the build trigger list
restored to the five paths the workflow actually watches, and the release asset
count stated as ten per release.

## Task 2: Replace the internal host codename

**Files:** `AGENTS.md`, `README.md`, `evidence/README.md`, `docs/BUILD.md`,
`docs/VERIFY.md`, `docs/XRAY.md`, `tests/coexist/run.sh`, `tests/e2e/run.sh`

`hw-gz` becomes `the Linux test host`. The `docs/XRAY.md` heading and its two
in-document anchors move with it. `.planning/` keeps the old token: it is a
historical record, not public prose.

## Task 3: Move the `S7-18` baseline to `v0.4.3`

**Files:** `scripts/verify.sh`, `.github/workflows/verify.yml`,
`docs/VERIFY.md`

`git diff v0.4.3 HEAD -- deploy/` is empty, so the item can assert zero
difference and drop the numstat branch that recognised one exempt
`protocols h1 h2` line. The ref-missing and untracked-file failures stay.

## Task 4: Archive the superseded evidence and repoint the references

**Files:** `evidence/README.md`, `docs/BUILD.md`, `docs/VERIFY.md`,
`docs/XRAY.md`, `scripts/redact-evidence.sh`, `scripts/verify.sh`

The twenty-three top-level capture files are removed from the tree; they exist
in full at tag `v0.5.0`, so the index becomes an archive pointer
(`git show v0.5.0:evidence/<name>`) instead of a table. The fifteen
`.gate/release/` paths in `docs/` that name published files become the same
pointer. Paths that name never-published local records keep their local
reference.

## Task 5: Close the remaining documentation debt

**Files:** `AGENTS.md`, `.env.example`, `.gitignore`, `docs/VERIFY.md`,
`docs/LICENSING.md`

`AGENTS.md` says the coexistence suite has 7 items; it has 8. `.env.example`
names a delivery-kit version. `.codex/` is untracked but not ignored.
`docs/VERIFY.md` still says nothing in `tests/` replays the REALITY round.
`docs/LICENSING.md` documents the license attachment for `v0.4.3` only.

## Task 6: Attach the license set to `v0.5.0`

**Files:** `.gate/release/THIRD_PARTY_NOTICES-v0.5.0.md` (gitignored)

The `v0.5.0` release carries four assets; `v0.4.3` carries ten. Uploading the
same six license files closes the gap. The repository's own
`THIRD_PARTY_NOTICES.md` is not edited (`tests/licenses/check.sh` pins its
`v0.4.3` line); the release asset is a two-line copy.

## Task 7: Prune the remote

Push `main` and `v0.5.0`, upload the license set, delete the `v0.4.2` and
`v0.4.1` releases, delete six tags and the merged-nothing branch
`feat/protocol-pin`. Local `feat/protocol-pin` is kept.

## Verification

- `git diff --check`; `rg -n 'hw-gz'` over the public tree returns nothing.
- `rg -n '\.gate/release' docs/` returns only the never-published records.
- `bash tests/licenses/check.sh`, `bash -n` over the shell scripts,
  `bash tests/pins/check.sh`, `bash tests/fixtures/check.sh`.
- `scripts/verify.sh` needs an executable Linux ELF, so the 26 items are
  settled by CI, not locally.
- After the push: CI `verify` and `gate0` green, `S7-18` still PASS with the new
  baseline, two releases, two tags, one remote branch.
