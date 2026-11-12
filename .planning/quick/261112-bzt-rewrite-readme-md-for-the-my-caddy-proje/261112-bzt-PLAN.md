---
quick_id: 261112-bzt
slug: rewrite-readme-md-for-the-my-caddy-project
description: "Rewrite README.md from scratch as a structured technical landing document for my-caddy"
status: in_progress
created: 2026-11-12
---

# Quick Task: Rewrite `README.md` for the my-caddy project

The current README is accurate but reads as a patchwork: it never explains how
to run the build, it has no repository map, and several sections are dense
prose walls. This task replaces it with a from-scratch, well-structured English
document for a technical reader who has just landed on the repository.

The deliverable is one file: `README.md`. Every factual claim in the current
README that this plan does not explicitly supersede must survive into the new
document. This plan is the specification; there is no research or discussion
phase.

## Assumptions and boundaries

- Only `README.md` changes in the executor's code commit. `deploy/`, `pins/`,
  `patches/`, `scripts/`, `tests/`, `docs/`, `evidence/` and `LICENSES/` are
  read-only inputs.
- The baseline named in the status line is `v0.5.0` (per `.planning/STATE.md`).
- Target 280-340 lines. Dense but readable. English, second person, direct
  declarative voice, no marketing adjectives.
- The plan file and the summary are GSD artifacts; the orchestrator commits
  them. Stage only `README.md` in the code commit.
- The authoring host is Windows: it can edit files and run Git, but it cannot
  execute the Linux ELF. `bash scripts/verify.sh` is expected to be BLOCKED
  here and is recorded as BLOCKED with its observed message, never as PASS.
- The whole work tree is scanned by items S7-12 and S7-13 of
  `scripts/verify.sh`, so the plan's own text and the new README both stay
  inside the constraints below.

## Redaction constraints (hard)

`scripts/verify.sh` item S7-13 extracts every token matching

```
[A-Za-z0-9][A-Za-z0-9.-]*\.(test|com|net|org|io)\b(/[A-Za-z0-9._-]+)?
```

from the whole work tree (`git grep --untracked`) and compares the exact set, in
both directions, with the 19 entries in `docs/REDACTION.md`. The new README may
use only domain-shaped tokens that already appear in that allowlist. For this
document that means:

- `a.test`, `b.test`, `example.com`;
- module identifiers such as `github.com/olst57`;
- no other domain-shaped token, and never the GitHub host written on its own
  without a path segment.

Item S7-12 forbids, anywhere in the work tree: a real-looking value in a
`privateKey` JSON field, any UUID shape, and any of the credential words
`secret`, `password`, `passwd`, `passphrase` followed by `:` or `=` and a
literal value. Prose may use the word "password" — the placeholder
`<NAIVE_PASSWORD>` is required — but never in that key/value position.

## Required document structure

The new `README.md` contains the following, in this order. The `##` heading
strings are exact: the verification compares the full ordered list. The only
lines in the README that begin with `## ` are these headings.

### Opening (no `##` heading)

1. `# my-caddy` as the first line.
2. One sentence stating the claim: three roles — a website reverse proxy, an
   in-process naive proxy, and an SNI-routed REALITY+Vision passthrough — on
   one binary, one Caddyfile, and one `:443`.
3. A status line naming the current baseline `v0.5.0`.
4. A short contents list: one bullet link per `##` section, placed before the
   first `##` heading.

### `## What this is`

- The repository is a build recipe plus a verification harness for one
  self-hosted Caddy binary. It is not a Caddyfile collection and not a
  distribution.
- It doubles as a test bed for an agent-team working method: the deliverable is
  the binary; the method under test is the evidence chain, which hands over
  original evidence rather than a summary.

### `## Routing`

- A small fenced ASCII diagram (no language tag) of the `:443` path:
  - the raw ClientHello reaches the `layer4` wrapper before TLS;
  - SNI `b.test` goes to Xray on `127.0.0.1:19098` with PROXY protocol v2 and
    no local decryption;
  - every other SNI continues to `tls`;
  - CONNECT traffic reaches `forward_proxy`, and ordinary requests reach
    `reverse_proxy 127.0.0.1:8080`.
- One or two sentences naming the consequence: one listener, one SNI claim, and
  no role consuming another role's connection.

Suggested shape (keep the edges and labels; redraw as needed):

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

### `## Is this for you?`

- Fits: one process and one port serving a website, a naive endpoint, and a
  REALITY tunnel; the reader is willing to run a small verification suite
  before trusting a build.
- Does not fit: a general-purpose Caddy module set, a container image, Windows
  or macOS binaries, or a configuration that can be deployed without reading
  `deploy/PLACEHOLDERS.md` first. None is in scope.
- Keep this section short.

### `## Quick start`

- One sentence: three tracks, pick one.
- `### Track A: use a release`
  - Download four build assets: `caddy-linux-amd64`, `caddy-linux-arm64`,
    `SHA256SUMS`, `pins.txt`. The six licence and notice files on the release
    page are not listed in `SHA256SUMS`.
  - From the directory that holds the downloads, run
    `sha256sum -c SHA256SUMS`. The file names are bare, so a check run
    elsewhere reports a failure.
  - In a checkout of this repository, point `CADDY_BIN` at the binary and run
    `bash scripts/verify.sh`; it needs no root, no network, and no running
    stack.
- `### Track B: build from source`
  - State the prerequisites in one sentence and run `bash scripts/build.sh`.
    Point at `## Build from source` for the details.
- `### Track C: deploy`
  - Deploying is a separate step and starts at `deploy/PLACEHOLDERS.md`. The
    shipped configuration is a placeholder posture, not runnable as shipped.

Use fenced `bash` blocks for every command, without a `$ ` prompt.

### `## The three roles`

- **Site reverse proxy.** Ordinary web traffic is reverse proxied to a local
  backend over HTTP/1.1 and HTTP/2 only. The delivery config pins
  `protocols h1 h2` on `:443`, so no QUIC listener is created and no `Alt-Svc`
  is advertised. HTTP/3 is deliberately off: one SNI with two transport
  identities on one port is the coexistence hazard this deployment exists to
  avoid.
- **naive proxy.** The site block carries `forward_proxy`, which serves
  `https://` entry points over H2 under the same pin. `probe_resistance` is
  enabled, so an unauthenticated CONNECT is not answered with `407`; it falls
  through to the site handler as an ordinary request. What shows that
  authentication worked is an established tunnel, not the status code.
- **REALITY and Vision.** The `layer4` listener wrapper reads the raw
  ClientHello and routes on SNI to a loopback listener, prefixing the
  connection with PROXY protocol v2. Caddy does no local decryption on that
  path; the tunnel endpoint does the TLS work.
- `### Two orderings that are load-bearing`
  - `order forward_proxy before reverse_proxy`: without it, `caddy adapt` still
    exits 0, but the site handler answers first and swallows every request, so
    no CONNECT reaches `forward_proxy` and naive is dead silently.
    `scripts/verify.sh` item `S3-9` asserts the resulting order.
  - `layer4` before `tls`: the wrapper must see the raw ClientHello. If `tls`
    ran first, the ClientHello would already be consumed, and the order is
    semantic, not cosmetic.

### `## Pinned inputs`

- Intro: everything the build consumes is a concrete value in
  `pins/build-inputs.env`, never a branch head and never a range.
- A table with exactly these inputs:
  - Caddy core: tag `v2.11.7`
  - naive forward proxy: fork of `klzgrad/forwardproxy`, `naive` branch
  - Layer 4: fork of `mholt/caddy-l4`, `master` branch
  - xcaddy: `v0.4.7`
  - Go: `1.26.9`
  - Xray (probe only): `v26.10.31`
- `pins/build-inputs.env` is the single source of truth and records the exact
  40-hex commits (`PIN_CADDY_COMMIT`, `PIN_FWDPROXY_SHA`, `PIN_L4_SHA`).
  Branch names are not build inputs: the upstream watch reads branch heads,
  the build consumes commits.
- The import paths stay the upstream ones, so a fork does not change module
  identity. The two forks are the only forks: Caddy core is consumed as a tag
  plus the patch, and xcaddy and Go are consumed as released tools. Forking
  either would buy nothing and cost a sync obligation.
- The Go pin is measured, not guessed: the official naiveproxy Caddy
  `v2.11.7-naive2` build reports `go1.26.9` in its embedded build metadata.
  The pin was added after `v0.4.3`; that release's receipt records `go1.26.10`
  and is not rewritten.
- `tests/pins/check.sh` fails if any copy of a pin drifts from this file,
  including the copies inside the workflows that call `setup-go`.

### `## The one patch`

- `patches/caddy-read-idle-timeout.patch` is the only patch here; the build
  refuses to start if `patches/` holds a second `.patch` file.
- It is mandatory for a causal reason. The naive branch calls
  `caddyhttp.IdleTimeoutsFromContext` from `forwardproxy.go`, and that symbol
  does not exist in Caddy `v2.11.7`. The patch adds it, and the build also
  passes `--replace` so the Caddy module comes from the patched tree rather
  than the unpatched tag.
- The build line in the upstream naive README has neither, so copying it as
  written does not compile.

### `## Build from source`

- Prerequisites: Bash, Git, Go exactly `1.26.9`, and network access to the
  module sources.
- `bash scripts/build.sh` builds both linux/amd64 and linux/arm64;
  `--arch amd64|arm64` selects one; `--print-pins` prints the inputs without
  building.
- Outputs: `dist/caddy-linux-amd64`, `dist/caddy-linux-arm64`,
  `dist/SHA256SUMS`, `dist/pins.txt`.
- Environment overrides: `CADDY_TAG`, `CADDY_COMMIT`, `FWDPROXY_SHA`,
  `L4_SHA`, `XCADDY_VERSION`, `PINS_FILE`, `DIST_DIR`, `BUILD_DIR`.
  `PIN_GO_VERSION` is deliberately not overridable; the active toolchain must
  match it.
- Before compiling, the script asserts: the tag's HEAD equals the pinned
  commit; exactly one patch is applied; the patched file actually changed;
  `go.mod` still pins `quic-go v0.63.0` and carries no `sagernet` reference;
  and after the build all four asserted modules are present in the binary.
- A subsection or paragraph on build triggers: `.github/workflows/build.yml`
  watches five paths on `main`: `scripts/**`, `patches/**`, `pins/**`,
  `tests/pins/**`, and the workflow file itself. A push touching any of them
  builds the artifacts without uploading them. A published release builds and
  attaches them. `workflow_dispatch` builds without uploading. Syncing a fork
  triggers nothing, because it lands outside those paths, so run the build by
  hand afterwards.

### `## Verification in three tiers`

- A table: tier, suite, item count, requirements, CI behaviour. Rows: offline
  26; coexistence 8; end to end 11.
- **Offline, 26 items.** `scripts/verify.sh` reads the delivery configs and the
  repository's own invariants: the adapter output, the handler order, the
  credential positions, the pin copies, the licence set, and the `deploy/`
  freeze. It needs `CADDY_BIN` and `jq`, and nothing else: no listener, no
  root, no network. CI runs it on every push.
- **Coexistence, 8 items.** `bash tests/coexist/run.sh .` starts the real
  binary on `:443` and asserts each role with a control next to the assertion:
  `CO-1` site leg, `CO-2` REALITY leg with a PROXY v2 record at the stub,
  `CO-3` unknown SNI claimed by nobody, `CO-4` naive tunnel over HTTP/1.1,
  `CO-5` decoy control, `CO-6` the same naive hop over HTTP/2, `CO-7` no QUIC
  listener on UDP `:443`, `CO-8` decoy and target are disjoint. It needs root
  and one external TLS endpoint, because the delivery ACL refuses loopback
  targets.
- **End to end, 11 items.** `tests/e2e/run.sh` runs eleven assertions across
  `E2E-01`-`E2E-08`: the Vision tunnel, the destination certificate on an
  unauthenticated probe, the PROXY v2 header, three wrong-credential controls
  for REALITY, three for naive (including the private-target ACL denial), SNI
  rejection, and 30 serial plus 8 concurrent requests through each leg.
  `E2E-06`, the non-443 address-shape guard, lives in `tests/fixtures/check.sh`.
  The suite derives its Caddyfile from `deploy/Caddyfile` by literal
  substitution and reverse-diffs the derivation before starting anything. It
  needs root, ports `8443`, `19099`, `18080`, `18081`, `18082` and `10802`, a
  real destination, and key material that must not be committed. CI
  syntax-checks the harness and runs its fail-closed `--negative-preflight`
  mode, which starts no process; CI does not execute the E2E suite.
- **Execution coverage paragraph.** The `v0.4.3` amd64 asset ran the 26-item
  gate and the 8-item suite on the Linux test host and in CI; its arm64 asset
  ran both on a GitHub-hosted `ubuntu-24.04-arm` runner, recorded in
  `evidence/v0.4.3/arm64-release.log`. The `v0.5.0` amd64 asset has not been
  executed on the Linux test host: the release CDN download ran at roughly
  19 KB/s there, so the 53 MB asset was deferred rather than half-transferred.
  The runtime numbers in `evidence/v0.5.0/` come from a locally built binary
  with the same pinned inputs, and the `v0.5.0` arm64 asset was not executed at
  all. Neither gap is upgraded to "verified" by the document.
- One sentence: executing an arm64 artifact is not the same as rebuilding it
  byte for byte.

### `## Release assets`

- A build produces four files: `caddy-linux-amd64`, `caddy-linux-arm64`,
  `SHA256SUMS` and `pins.txt`. A release carries those four plus `LICENSE`,
  `THIRD_PARTY_NOTICES.md`, `Apache-2.0.txt`, `MIT.txt`, `BSD-3-Clause-Go.txt`
  and `MPL-2.0.txt` — ten assets. Both `v0.5.0` and `v0.4.3` carry the full
  set. Sizes and checksums are not repeated; `SHA256SUMS` is the authority.
- `pins.txt` is the audit trail of a run: what it consumed, not what was
  intended. It holds seven `name=value` lines — `caddy_tag`,
  `caddy_source_head`, `forwardproxy_sha`, `caddy_l4_sha`, `xcaddy_version`,
  `go_version` and `patch`. To audit a build, read this file first. The two
  fork commits and the xcaddy version can be passed back as `FWDPROXY_SHA`,
  `L4_SHA` and `XCADDY_VERSION` to replay the same inputs.

### `## Operating the delivery config`

- `deploy/` is the only authoritative configuration in this repository.
  `docs/` explains it; nothing else overrides it.
- Five angle-bracket placeholders: `<VLESS_UUID>`, `<REALITY_PRIVATE_KEY>`,
  `<REALITY_SHORT_ID>`, `<NAIVE_USER>`, `<NAIVE_PASSWORD>`. They are
  registered in `deploy/PLACEHOLDERS.md`, which is checked in both directions.
- The literal hostnames `a.test`, `b.test`, `example.com` and the loopback
  addresses `127.0.0.1:19098` and `127.0.0.1:8080` are replace-me literals, not
  angle-bracket tokens. A Caddy site address must parse as a valid host, which
  is why the hostnames are literal.
- `tls internal` is a placeholder posture: it makes Caddy issue certificates
  from its own local CA so the skeleton validates and the structure is testable
  offline. Before deployment, replace it with an ACME issuer or an explicitly
  managed certificate. Caddy's internal CA leaves the subject DN empty, so
  certificate assertions must read the SAN, never the subject.
- There is deliberately no site-level `basic_auth`. naive authenticates the
  CONNECT itself through `forward_proxy`'s own `basic_auth`, which reads
  `Proxy-Authorization`. Its credentials are base64 `user:pass`, not bcrypt,
  and they are a separate list from any site credential. A site-level
  `basic_auth` is forbidden: it runs before `forward_proxy` and answers `401`
  to every request, so the site serves nothing and no CONNECT can
  authenticate. An earlier release carried exactly that defect.
- Do not add an `upstream` sub-directive to `forward_proxy`: setting one
  silently disables `acl` and `ports`, which removes the default
  private-network deny.
- One listener, `protocols h1 h2`, no HTTP/3.

### `## Keeping up with upstream`

- Two scheduled workflows watch the outside world; neither one changes what
  this repository builds.
- `scripts/check-upstream.sh` and `upstream-watch.yml` run on the 1st and 15th
  at 01:00 UTC. The Caddy and `xcaddy` tags come from upstream releases; the
  two module SHAs come from this project's own forks
  (`github.com/olst57/forwardproxy` on `naive`,
  `github.com/olst57/caddy-l4` on `master`), which are auto-synced
  from upstream, so the fork head is the commit the build would eventually
  follow. The check never edits `pins/build-inputs.env` and never starts a
  build: a bump needs a fork sync, a patch check and a full gate run first.
  While its tracking issue is already open, later runs stay silent: no
  comment, no edit, no duplicate.
- `scripts/check-forks.sh` and `fork-sync.yml` run daily at 01:30 UTC,
  fast-forward the two module forks when a `FORK_SYNC_TOKEN` token is
  configured, and report otherwise. They also stay silent while their issue is
  already open. A sync never moves a pin, so it cannot change the binary.
- The forks exist so that no upstream push can change what this repository
  produces. The cost: no upstream fixes until the fork is synced.
- GitHub may start a scheduled run late, so these are cadences, not exact
  wall-clock delivery times.

### `## Repository map`

One line each for `deploy/`, `patches/`, `pins/`, `scripts/`, `tests/`,
`docs/`, `evidence/`, `LICENSES/`, `.github/workflows/`, `.planning/`. Keep
each line factual; no line may claim more than the directory contains.

### `## Version history`

- `v0.4.0` was the first release with all three roles on one port, and it
  carried a site-level `basic_auth` defect plus fork refs that resolved to live
  branch heads.
- `v0.4.3` removed the defect, pinned both fork commits, and added the arm64
  execution record.
- `v0.5.0` closed REALITY with the E2E harness and the redacted
  `evidence/v0.5.0/` capture set.
- Earlier tags are retired; the body of each release is the changelog, not this
  file.

### `## Limits and non-claims`

- No real domain, public address, cloud instance, credential, unique identifier
  or REALITY key appears here. Where a concrete value would be needed, the text
  points at `deploy/` and `docs/`, which hold redacted placeholders.
- Byte-identical rebuilds are not established: the toolchain is pinned, but two
  clean builds of the same commit with the same inputs have not been compared,
  and build paths, build IDs and other compiler inputs may still differ.
- HTTP/3 is not claimed. The delivery config turns it off, and earlier local H3
  measurements predate the pin.
- The execution-coverage gaps above are stated, not upgraded: the `v0.5.0`
  amd64 asset was not run on the Linux test host, and the `v0.5.0` arm64 asset
  was not executed at all.
- Windows is an authoring host only; it cannot execute the Linux ELF.

### `## Licensing`

- The repository's own material is proprietary and all rights reserved; see
  `LICENSE` (`LicenseRef-Proprietary`).
- The release binary links Apache-2.0, MIT and BSD-3-Clause components, and the
  Caddy source is modified at build time.
- `THIRD_PARTY_NOTICES.md`, `LICENSES/` and `docs/LICENSING.md` record the
  components, the upstream refs, the licence-text hashes and the obligations.
  This is a provenance record, not legal advice.

### `## Documentation index`

One line each, each naming the file and its purpose:

- `docs/BUILD.md` — how the binary is produced.
- `docs/VERIFY.md` — reproducing the offline checks and what the runtime tests
  answered.
- `docs/XRAY.md` — the REALITY inbound and how it pairs with Caddy.
- `docs/LICENSING.md` — the licence conclusion and the obligations.
- `docs/REDACTION.md` — the domain-token allowlist and the redaction rules.
- `evidence/README.md` — the redacted evidence set and its provenance.
- `tests/e2e/README.md` — the REALITY end-to-end harness.
- `AGENTS.md` — the project instructions and constraints.

## Style rules

- English throughout, second person, direct declarative voice. No marketing
  adjectives.
- Fenced `bash` blocks for commands, without a leading `$ ` prompt.
- Every number, path, port and count must be checkable in the repository;
  invent nothing.
- Name the failure a rule prevents, as the current README does.
- No required section may be dropped or reordered.

## Task 1: Replace `README.md`

**Files:** `README.md`

**Action:** Rewrite `README.md` from scratch in one pass, to the structure and
content in "Required document structure". Write one coherent document, not the
old README with new headings: the opening claim, the contents list, the routing
diagram and the three quick-start tracks are new material. Keep every factual
claim the current README makes unless the structure above explicitly supersedes
it; the superseded pieces are only the old heading names and the old section
order. In particular, fold the old "Build triggers" paragraph into
`## Build from source`, the old "Built by an agent team" paragraph into
`## What this is`, the old "Sixty seconds" list into `## Quick start`, the old
"Should you use this?" section into `## Is this for you?`, and the old "What
this document does not claim" section into `## Limits and non-claims`.

Use the exact `##` and `###` heading strings specified. Do not use a `## ` line
inside a fenced block. Do not modify any other file. Stage and commit only
`README.md`, with a message stating the behaviour change, for example
`docs(readme): rewrite the project landing document`.

**Verify:** Run from the repository root. Every command must succeed except
the offline verifier, which is expected to be BLOCKED on this host and must be
recorded with its observed message, never as PASS.

```bash
# 1. Whitespace and conflict hygiene.
git diff --check

# 2. S7-13 replica: exact-token set comparison in both directions.
allow=$(grep -E '^\[C[123]\] ' docs/REDACTION.md | cut -d' ' -f2 | sort -u)
tree=$(git grep --untracked -hoE '[A-Za-z0-9][A-Za-z0-9.-]*\.(test|com|net|org|io)\b(/[A-Za-z0-9._-]+)?' -- . 2>/dev/null | sort -u)
missing=$(comm -23 <(printf '%s\n' "$tree") <(printf '%s\n' "$allow"))
excess=$(comm -13 <(printf '%s\n' "$tree") <(printf '%s\n' "$allow") | grep -vxE 'example\.(net|org)')
if [ -n "$missing" ] || [ -n "$excess" ]; then
	printf 'S7-13 REPLICA: FAIL\nmissing:\n%s\nexcess:\n%s\n' "$missing" "$excess"
	exit 1
fi
[ "$(printf '%s\n' "$allow" | wc -l)" -eq 19 ] || { echo 'S7-13 REPLICA: FAIL (allowlist size)'; exit 1; }
echo 'S7-13 REPLICA: PASS'

# 3. S7-12 replica: no credential-shaped material.
hits=$(
	git grep --untracked -nE '"privateKey"[[:space:]]*:[[:space:]]*"[^<"]' -- . || true
	git grep --untracked -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -- . || true
	git grep --untracked -niE '(secret|password|passwd|passphrase)[[:space:]]*[:=][[:space:]]*[^<$[:space:]]' -- . || true
)
if [ -n "$hits" ]; then printf '%s\n' "$hits"; exit 1; fi
echo 'S7-12 REPLICA: PASS'

# 4. Required headings, in order, plus the required subsection and tracks.
actual=$(grep '^## ' README.md)
expected=$(cat <<'EOF'
## What this is
## Routing
## Is this for you?
## Quick start
## The three roles
## Pinned inputs
## The one patch
## Build from source
## Verification in three tiers
## Release assets
## Operating the delivery config
## Keeping up with upstream
## Repository map
## Version history
## Limits and non-claims
## Licensing
## Documentation index
EOF
)
[ "$actual" = "$expected" ] || { printf 'README SECTIONS: FAIL\n--- actual:\n%s\n' "$actual"; exit 1; }
head -1 README.md | grep -qx '# my-caddy'
grep -qx '### Two orderings that are load-bearing' README.md
grep -qx '### Track A: use a release' README.md
grep -qx '### Track B: build from source' README.md
grep -qx '### Track C: deploy' README.md
contents=$(grep -cE '^- \[.+\]\(#[a-z0-9-]+\)$' README.md || true)
[ "$contents" -ge 17 ] || { printf 'README CONTENTS LIST: FAIL (%s link bullets)\n' "$contents"; exit 1; }
echo 'README SECTIONS: PASS'

# 5. Static workflow control (does not read the README).
bash tests/workflows/check.sh

# 6. Offline verifier: BLOCKED on this host; record the observed message.
bash scripts/verify.sh; echo "verify-exit=$?"
```

**Done:**

- `README.md` has the title `# my-caddy`, the one-sentence three-role claim,
  the `v0.5.0` status line, and a contents list before the first `##`.
- All 17 `##` sections appear in the order listed above, with the
  `### Two orderings that are load-bearing` subsection under
  `## The three roles` and the three `### Track ...` headings under
  `## Quick start`.
- The routing diagram names the layer4 wrapper, the `b.test` claim to
  `127.0.0.1:19098` with PROXY v2, and both handlers on the TLS path.
- Every surviving fact listed in "Required document structure" is present,
  including build triggers, the agent-team note, the item-level verification
  detail (`CO-1`-`CO-8`, `E2E-01`-`E2E-08`, `E2E-06` in
  `tests/fixtures/check.sh`) and the execution-coverage paragraph.
- S7-13 and S7-12 replicas pass; `bash tests/workflows/check.sh` prints
  `WORKFLOWS-TEST: PASS`; `git diff --check` is clean.
- `bash scripts/verify.sh` is recorded as BLOCKED with its observed message,
  never as PASS.
- The document is 280-340 lines, and only `README.md` is staged in the code
  commit.

## Verification baselines recorded at planning time

Measured on the current tree before this plan was written, with the authoring
host's Git Bash:

- S7-13 replica: PASS; both differences empty; allowlist is 19 entries.
- S7-12 replica: PASS; no hits.
- `bash tests/workflows/check.sh`: `WORKFLOWS-TEST: PASS`.
- `bash scripts/verify.sh`: exit 2, with `VERIFY: FAIL` and
  `FATAL: CADDY_BIN not found: dist/caddy-linux-amd64`. On this host that is
  BLOCKED, not PASS, because the Linux ELF cannot run here.

## Done criteria

- `README.md` is rewritten to the structure above and no other file is
  modified.
- The S7-13 and S7-12 replicas pass with the new README in the work tree, so
  the document introduces no domain-shaped or credential-shaped token.
- `git diff --check` is clean, the workflow guard still passes, and the offline
  verifier's BLOCKED result is recorded in the summary with its observed
  message.
- The code commit stages only `README.md`; the plan and summary are left for
  the orchestrator's docs commit.
