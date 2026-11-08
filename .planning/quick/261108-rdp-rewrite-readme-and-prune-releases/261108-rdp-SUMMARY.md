---
quick_id: 261108-rdp
slug: rewrite-readme-and-prune-releases
description: "Rewrite the public README and converge the release set to v0.5.0 and v0.4.3"
status: complete
created: 2026-11-08
completed: 2026-11-08
commits: [348734e]
---

# Quick Task Summary: Rewrite the public README and prune the release set

**The entry document now describes `v0.5.0`, the internal host codename is gone
from the public tree, and the repository is down to two releases and two tags**

## What Was Built

### 1. `README.md`, rewritten (240 lines, English)

Layered the way the owner chose: the first screen answers "what is this",
"should I use it", "sixty seconds to a verified binary"; everything below that
is operator material.

- Opening: one Caddy binary, three roles on `:443` (site reverse proxy,
  in-process naive, SNI-routed REALITY/Vision), and the explicit statement that
  this repository is a build recipe plus verification harness, not a Caddyfile
  collection.
- Fit / no-fit section, then the 60-second path: download four assets, run
  `sha256sum -c SHA256SUMS` in the download directory, then
  `CADDY_BIN=... bash scripts/verify.sh`.
- Middle: the three roles, the pinned input table, the single mandatory patch,
  the five build triggers, and the three verification tiers with their counts
  (26 offline / 8 coexistence / 11 E2E), the release asset set (ten), and the
  execution-coverage paragraph.
- Below that: `deploy/` as the only authoritative config, `tls internal` as a
  placeholder posture, the site-level `basic_auth` prohibition, upstream drift
  and fork-sync automation, one short version-history paragraph, a three-line
  note about the agent team, and a "what this document does not claim" list.

Five statements that had drifted from the tree were corrected rather than
carried forward:

| Was | Now |
| --- | --- |
| site-level `basic_auth` described as the naive credential carrier | forbidden; `forward_proxy` reads `Proxy-Authorization`, base64 `user:pass`, and a site-level handler answers `401` to everything |
| `tls internal` listed as a known limitation | stated as a placeholder posture that must be replaced with ACME or a managed certificate before deployment |
| "both architectures executed" in the present tense | arm64 execution belongs to `v0.4.3` only; the `v0.5.0` arm64 asset was not executed |
| release described as four assets | ten per release (four build outputs plus six license/notice files) |
| build triggers listed as three paths | the five paths `build.yml` actually watches, including `pins/**` and `tests/pins/**` |

### 2. Internal codename removed from the public tree

`hw-gz` became `the Linux test host` in `AGENTS.md`, `README.md`,
`evidence/README.md`, `docs/BUILD.md`, `docs/VERIFY.md`, `docs/XRAY.md`,
`tests/coexist/run.sh` and `tests/e2e/run.sh`. The `docs/XRAY.md` heading and
both in-document anchors moved with it
(`#measured-on-the-linux-test-host-sprint-5`). `Sprint N` and `SP*-*` stay: they
are internal vocabulary, not host names, and renaming them would invalidate the
evidence index. `.planning/` keeps the old token on purpose — it is a historical
record, not public prose.

### 3. `S7-18` baseline moved from `v0.3.0` to `v0.4.3`

`scripts/verify.sh` now diffs `deploy/` against `v0.4.3` and fails on any
non-empty result. The numstat branch that recognised exactly one exempt
`protocols h1 h2` line is deleted: that line is part of the frozen tree now, so
an exemption would only hide a real edit. The ref-missing and untracked-file
failures are unchanged. `.github/workflows/verify.yml` and `docs/VERIFY.md` say
the same thing. `deploy/Caddyfile` and `deploy/PLACEHOLDERS.md` were not touched
— their `v0.2.1` strings are inside the frozen tree and editing them would fail
the item.

### 4. Evidence tree slimmed, references repointed

The 23 top-level capture files (`SP4-*`, `SP4B-*`, `SP5-*`, `SP6-*`,
`adapt.err`, `adapted.json`, `verify-run.log`) were removed with `git rm`. They
exist byte for byte at tag `v0.5.0`, which was verified before the removal:

```text
SP4-D1.txt           6658        SP6-F1.txt           5072
SP4B-D1.txt          2511        verify-run.log        300
SP5-C1.txt           9135        adapted.json          893
adapt.err               0
```

`evidence/README.md` keeps its index table (it records what was published) and
now says how to fetch each entry: `git show v0.5.0:evidence/<name>`. Its three
dead references and the `SP4-D4.txt:14` note became the same pointer. The nine
`.gate/release/` paths in `docs/` that named published files became
`git show v0.5.0:evidence/X`; the paths that name never-published local records
(`DEVIATIONS.md`, `PM-DECISIONS-3.md`, `SPRINT5-SUMMARY.md`,
`SPRINT6-SUMMARY.md`, `SPEC-v0.4.0-SP7.md`, `REDACTION-MAP.md`,
`SP7-EVIDENCE.md`, `F9-REPORT.md`) keep their local reference, because those
files were never published and there is nothing to point at.

`scripts/redact-evidence.sh` no longer claims the capture directory yields
"exactly the 23 files"; it says the set is archived at the `v0.5.0` tag.

### 5. Remaining documentation debt closed

- `AGENTS.md`: coexistence suite `7 items` → `8 items`.
- `.env.example`: the first line no longer names a delivery-kit version.
- `.gitignore`: `.codex/` added; it was untracked but not ignored.
- `docs/VERIFY.md`: the `v0.4.3` REALITY paragraph now says `v0.5.0` added
  `tests/e2e/` and that the harness, not the hand-run report, is the regression
  claim.
- `docs/LICENSING.md`: the Release material section records that `v0.5.0` now
  carries the same six files, and that its notice is a `v0.5.0`-specific copy
  anchored on `go1.26.9`.

### 6. `v0.5.0` license attachment

The release carried four assets; `v0.4.3` carries ten. Six files were uploaded
to close the gap, under the same names `v0.4.3` uses: `LICENSE`,
`THIRD_PARTY_NOTICES.md`, `Apache-2.0.txt`, `MIT.txt`, `BSD-3-Clause-Go.txt`,
`MPL-2.0.txt`.

The repository's own `THIRD_PARTY_NOTICES.md` was **not** edited:
`tests/licenses/check.sh` asserts its `v0.4.3` line. The release asset is a
separate copy at `.gate/release/THIRD_PARTY_NOTICES-v0.5.0.md` (gitignored,
2,669 bytes). It differs from the tracked file in exactly two lines:

```text
7c7
< Release: v0.4.3
---
> Release: v0.5.0
19c19
< | Go runtime | go1.26.10 | ...
---
> | Go runtime | go1.26.9 | ...
```

Copy sha256:
`68d1123a5381736096b7e193672e530ba9c695949e175a9b299ae84c0263fa8a`.

### 7. Remote pruning

Recorded in "Remote Result" below.

## Verification

Local, all passing:

```text
git diff --check                                        exit 0, no output
rg -n 'hw-gz' AGENTS.md README.md docs/ evidence/ tests/  no match
rg -n '\.gate/release' docs/                            14 hits, all never-published local records
rg -n 'v0\.4\.[012]|v0\.3\.0|v0\.2\.[01]' README.md      only the history paragraph
bash tests/licenses/check.sh                            LICENSES: PASS
bash tests/pins/check.sh                                PINS: PASS
bash tests/fixtures/check.sh                            FIXTURES: PASS
bash tests/e2e/run.sh --negative-preflight              PREFLIGHT CONTROLS: PASS
bash -n tests/e2e/*.sh tests/fixtures/check.sh          exit 0
shellcheck -S warning <the four changed scripts>         no output
```

`scripts/verify.sh` itself was not run locally: the checked-in
`dist/caddy-linux-amd64` is the `v0.2.0` binary (`1a911533…`) and `dist/pins.txt`
predates the `v0.4.3` pin set, so the run would describe an artifact this tree no
longer produces. The 26 items are settled by CI. To keep that from being an
unchecked claim, the S7 items this change could plausibly break were recomputed
by hand against the work tree:

| Item | Why it was at risk | Recomputed result |
| --- | --- | --- |
| S7-6 | mandatory doc facts must survive the rewrites | all nine greps found; PASS |
| S7-7 | every fenced `$ ` command needs a transcript entry | 18 doc commands, 0 without an entry; PASS |
| S7-8 | doc verdicts must agree with recorded exit codes | 0 `UNRUN`, 0 `MARKED-FAIL-BUT-PASSED`, 0 `PASSED-AS-FAIL`; PASS |
| S7-12 | credential-shaped material must not appear in the new prose | 0 hits across the three patterns; PASS |
| S7-13 | the allowlist must still be exactly present in the tree | 19 tree tokens, 19 allowlist entries, `comm -13` empty; PASS |
| S7-14 | `.env.example` must keep exactly five placeholders | 5; PASS |
| S7-15 | no stale "19 items" counts, provenance intact | 0 hits; PASS |
| S7-18 | `deploy/` must equal `v0.4.3` byte for byte | 0 numstat lines, 0 untracked; PASS |

S7-13 was the one worth checking twice. The item compares the tree's extracted
domain tokens against `docs/REDACTION.md` in both directions, so deleting 23
evidence files could have removed a token the allowlist still names — which
would read as FAIL with no obvious cause. It did not: every allowlisted token
still occurs in the tree (`a.test`, `b.test`, `probe.test`, `unknown.test`,
`example.com`, `example.net`, `example.org`, the six `caddyserver`/`klzgrad`/
`mholt`/`olst57`/`XTLS`/`quic-go` repository paths,
`go.uber.org/zap`, `www.microsoft.com`, `www.apple.com`, `www.google.com`,
`www.apache.org/licenses`, `mozilla.org/MPL`), and no new token entered the
tree. The new `README.md`, `docs/` text and this SUMMARY were written with that
constraint in mind.

## Remote Result

REMOTE_RESULT_PLACEHOLDER

## Deliberately Not Done

- **No archive of the `v0.4.1` / `v0.4.2` binaries or release bodies.** The
  bodies were saved to `.gate/release/` before deletion (gitignored), but the
  binaries are gone. Both tags carried the site-level `basic_auth` defect, so
  there is no reason to keep a download of them.
- **`scripts/verify.sh:2` still says "v0.2.0 delivery kit".** Out of scope for
  this task; changing prose in the verifier risks S7-13 token churn for no gain.
- **`docs/BUILD.md`'s "NOT VERIFIED IN THIS SLICE" list still names "Any xray
  start / Any REALITY session".** `v0.5.0` E2E now covers both. Left as a known
  debt rather than edited blind in the same commit that moved the S7-18
  baseline.
- **`docs/E2E-NAIVE-REALITY-2026-11-06.md` stays untracked**, and
  `docs/XRAY.md:179` keeps its host address. Neither is in this task's scope.
- **`.planning/milestones/v0.4.3-phases/01-*/01-02-SUMMARY.md:41` contains a
  real host address and machine name.** Pre-existing, inside the historical
  record, not touched here. It is worth a separate pass.
- **`v0.5.0` amd64 was not executed on the Linux test host, and `v0.5.0` arm64
  was not executed at all.** Both stay stated as deferrals.

## Files Changed

Modified: `.env.example`, `.github/workflows/verify.yml`, `.gitignore`,
`AGENTS.md`, `README.md`, `docs/BUILD.md`, `docs/LICENSING.md`,
`docs/VERIFY.md`, `docs/XRAY.md`, `evidence/README.md`,
`scripts/redact-evidence.sh`, `scripts/verify.sh`, `tests/coexist/run.sh`,
`tests/e2e/run.sh`.

Deleted: 23 files under `evidence/`.

Added: this quick-task directory (`PLAN` + `SUMMARY`).
