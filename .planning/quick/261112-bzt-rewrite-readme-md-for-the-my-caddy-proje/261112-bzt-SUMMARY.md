---
quick_id: 261112-bzt
slug: rewrite-readme-md-for-the-my-caddy-project
description: "Rewrite README.md from scratch as a structured technical landing document for my-caddy"
status: complete
created: 2026-11-12
completed: 2026-11-12
commits: [d53de84, 1f1b125]
---

# Quick Task Summary: Rewrite `README.md` for the my-caddy project

**The entry document is now a 339-line technical landing page: 17 ordered sections, an ASCII
routing diagram, a pinned-inputs table, the three verification tiers, and the execution-coverage
gaps stated rather than upgraded.**

## What Was Built

### `README.md`, rewritten (339 lines, English, second person)

The document opens with the title, a one-sentence three-role claim, the `v0.5.0` baseline, and a
contents list with one link per section (17 entries). Then, in the plan's fixed order:

- **What this is** — a build recipe and verification harness, not a Caddyfile collection or a
  distribution; also a test bed for an agent-team working method whose deliverable is the evidence
  chain.
- **Routing** — an untagged fence holding the ASCII path: `client` → TCP `:443` raw ClientHello →
  `layer4` wrapper (before `tls`), SNI `b.test` → Xray `127.0.0.1:19098` with PROXY v2 and no local
  decryption, every other SNI → `tls`, CONNECT → `forward_proxy`, other requests →
  `reverse_proxy 127.0.0.1:8080`.
- **Is this for you?** — fit / does-not-fit lists.
- **Quick start** — three tracks: release (four build assets, `sha256sum -c SHA256SUMS`, the offline
  verifier), source build, and deploy (placeholders).
- **The three roles** — per-role detail plus `### Two orderings that are load-bearing`
  (`forward_proxy` before `reverse_proxy`, asserted by `S3-9`; `layer4` before `tls`).
- **Pinned inputs** — table naming Caddy core tag `v2.11.7`, the two fork commits
  (`PIN_FWDPROXY_SHA`, `PIN_L4_SHA`) mirroring the `klzgrad/forwardproxy` `naive` and
  `mholt/caddy-l4` `master` heads, `xcaddy v0.4.7`, Go `1.26.9`, Xray `v26.10.31` (probe only);
  the pins file records 40-hex commits and branch names are never build inputs.
- **The one patch** — why `--replace` and the patch are both mandatory, and the build-time module
  assertions.
- **Build from source** — commands, the five trigger paths `build.yml` watches, and what each
  trigger uploads (push: nothing; release: attaches; `workflow_dispatch`: nothing; a fork sync:
  nothing).
- **Verification in three tiers** — table with 26 offline items, 8 coexistence items (`CO-1`–`CO-8`)
  and 11 end-to-end items (`E2E-01`–`E2E-08`, with `E2E-06` in `tests/fixtures/check.sh`), plus the
  execution-coverage paragraph: `v0.4.3` amd64 ran both suites on the Linux test host and in CI,
  `v0.4.3` arm64 is recorded at `evidence/v0.4.3/arm64-release.log`, `v0.5.0` amd64 was deferred
  because the CDN download ran at roughly 19 KB/s against a 53 MB asset, `v0.5.0` arm64 was not
  executed at all, and neither gap is upgraded.
- **Release assets** — four build outputs plus six licence/notice files (ten per release);
  `pins.txt` holds seven `name=value` lines.
- **Operating the delivery config** — five angle-bracket placeholders, the literal `a.test` /
  `b.test` / `example.com` replace-me values, `tls internal` as a placeholder posture, no site-level
  `basic_auth` (it runs before `forward_proxy` and 401s everything), no `forward_proxy` upstream
  sub-directive, and the single `:443` listener with `protocols h1 h2`.
- **Keeping up with upstream** — upstream watch on the 1st and 15th at 01:00 UTC, fork sync daily
  at 01:30 UTC, neither moves a pin, both stay silent while an issue is open.
- **Repository map**, **Version history** (`v0.4.0` → `v0.4.3` → `v0.5.0`), **Limits and
  non-claims**, **Licensing** (`LicenseRef-Proprietary`, third-party notices, provenance not legal
  advice), and a **Documentation index** with one purpose line per document.

Every factual claim from the previous README that the plan did not supersede survives; the plan's
required facts were checked against the tree before being written:

- `pins/build-inputs.env` — tag, both fork commits, `xcaddy`, Go and Xray versions as stated.
- `scripts/build.sh` — `--arch amd64|arm64|all`, 40-hex enforcement, the two binaries plus
  `SHA256SUMS` and `pins.txt`, and `sha256sum caddy-linux-*` (so the licence files are not hashed).
- `.github/workflows/build.yml` — push / release / `workflow_dispatch` triggers and the five watched
  paths.
- `scripts/verify.sh` — `EXPECTED_ITEMS=26`, `CADDY_BIN` default, and `S3-9` asserting handler order.
- `tests/coexist/run.sh` — `CO-1`–`CO-8`; `tests/e2e/run.sh` — eleven items and
  `--negative-preflight`, which exits 2 before any process starts.
- `deploy/Caddyfile` — global `order forward_proxy before reverse_proxy`, the `layer4` wrapper before
  `tls`, and both site blocks.
- `docs/REDACTION.md` — the 19-entry allowlist.

## Verification

The plan's six blocks ran in order from the repository root. Observed output:

1. Whitespace and conflict hygiene:

   ```text
   $ git diff --check
   (no output; exit 0)
   ```

2. S7-13 replica (exact-token comparison in both directions):

   ```text
   S7-13 REPLICA: PASS
   ```

3. S7-12 replica (credential-shaped material):

   ```text
   S7-12 REPLICA: PASS
   ```

4. Required headings, subsections, tracks and contents list:

   ```text
   README SECTIONS: PASS
   ```

5. Static workflow control:

   ```text
   WORKFLOWS-TEST: PASS
   workflows-exit=0
   ```

6. Offline verifier — **BLOCKED** on this Windows authoring host, which cannot execute the Linux
   ELF and has no built binary:

   ```text
   VERIFY: FAIL
   FATAL: CADDY_BIN not found: dist/caddy-linux-amd64
   verify-exit=2
   ```

   Recorded as BLOCKED, not PASS and not FAIL: the message reports a missing input, not a failed
   assertion. The 26 items are settled by CI on a Linux host.

Additional checks:

- `wc -l README.md` → `339`, inside the 280-340 budget.
- The S7-12 and S7-13 replicas ran with `git grep --untracked` over the whole tree, so they cover
  this SUMMARY as well as the new README; both passed with this file present was re-run after
  writing it (same commands, same results).
- `git status --porcelain` after the code commit lists only this untracked SUMMARY.
- The code commit contains one file: `README.md`, 282 insertions, 194 deletions, no deletions of
  tracked files.

## Deviations from Plan

None. The only iteration was line-count trimming to land inside the 280-340 budget (successive
drafts measured 414, 396, 392, 354, and finally 337 lines before review); no content requirement,
section order, heading string or factual claim changed.

## Orchestrator Review (`1f1b125`)

Five claims were tightened after re-reading the sources, in commit
`1f1b125 docs(readme): tighten the release, pin and CI claims`:

- Quick start now links the release page, and states that `SHA256SUMS` covers the two binaries only
  — `sha256sum caddy-linux-*` in `scripts/build.sh:225` hashes neither `pins.txt` nor the licence
  files.
- The pinned-inputs table names the consumed fork commits (`PIN_FWDPROXY_SHA`, `PIN_L4_SHA`) instead
  of the fork branches, which contradicted the paragraph below it.
- The CI cadence is stated as push and pull request against `main`, matching
  `.github/workflows/verify.yml:31-34`, not "every push".
- The watch paragraphs name the workflow that runs each script, and drop the redundant
  "a `FORK_SYNC_TOKEN` token".
- The orphan sentence about artifact execution moved into the byte-identical-rebuild bullet.

Both redaction replicas, the heading gate and `tests/workflows/check.sh` were re-run after these
edits with the same results; the document is 339 lines.

## Files Changed

Modified: `README.md` — commit `d53de84`
(`docs(readme): rewrite the project landing document`), plus the review edits in `1f1b125`.

Added: this SUMMARY, left for the orchestrator's docs commit.

## Self-Check

- `README.md` exists and is committed at `d53de84`: FOUND.
- `.planning/quick/261112-bzt-rewrite-readme-md-for-the-my-caddy-proje/261112-bzt-SUMMARY.md`
  exists: FOUND.

## Self-Check: PASSED
