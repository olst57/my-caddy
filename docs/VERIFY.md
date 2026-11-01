# VERIFY — reproducing the offline checks

This document explains how to reproduce every offline check in this slice, and
records what the runtime tests actually answered.

The offline part binds no listener, starts no server, performs no TLS handshake
and sends no HTTP request; it needs `caddy adapt`/`validate` and `jq` only.
Every command quoted there was executed, and `docs/transcript-v0.2.0.txt`
records each with its real exit code and the host it ran on. The runtime section
later in this document — "What the runtime actually answers" — is different in
kind: it comes from a live `caddy run` on `hw-gz` and is **not** reproducible
from the repository alone. It is evidence for the behaviours v0.2.1 asserts, and
it is not part of the offline verifier.

## Where the checks actually ran

Two hosts matter, and they produced different lines. The transcript labels
every record with its host so a reader can tell which host produced which line.

**The v0.2.1 run was repeated on `hw-gz`.** The S3-9 assertion changed in
v0.2.1, so the whole verifier was re-run against the corrected config: as `root`
on `hw-gz` (Ubuntu 24.04, `Linux 6.8.0-136-generic x86_64`) against the same
binary, sha256 `1a9115339c7a0edefd692d74324bd4906508c40b11bb781e841d5910337b2624`.
Every item in the set that existed then passed and the verifier printed
`VERIFY: PASS`; the log is `.gate/release/verify-run.log`. That run was manual
too. Before the config was
corrected, the same verifier was run on that host against the v0.2.0 config and
S3-9 FAILed, with every other item PASS: the site's subroute chain read
`["authentication","forward_proxy"]` and carried no `reverse_proxy`. That is the
defect ruled in `.gate/release/PM-DECISIONS-3.md` F-1.

**The v0.2.0 result of record was the Linux run.** `scripts/verify.sh` was run
on **ubuntu-latest**, inside a **GitHub Codespace** (Ubuntu 24.04.5,
`Linux x86_64`), against the artifact from the `build` workflow's **run
41069346485** — the `caddy-linux-amd64` binary built at commit
`0a3b22af3c4a467c12dd99eac50ebad7f6174530`. On that host every item in that
run's set passes and the verifier prints `VERIFY: PASS`.

**The Windows authoring host cannot run the S3 items at all.** The artifact is a
Linux ELF and the authoring host is Windows/MSYS. It fail-closes at preflight —
`FATAL: CADDY_BIN is not executable: dist/caddy-linux-amd64` — and exits `2`
before any item runs, so the eleven S3 items are unreachable there. That is a
limitation of the authoring host, not a verdict on the deliverable. The
fail-closed behaviour itself **is** verified on that host, because that path was
exercised.

**No CI job runs `verify.sh`.** There is no committed workflow that invokes the
verifier; `.github/workflows/build.yml` builds the artifacts and
`.github/workflows/gate0.yml` runs the Gate 0 probes, and neither runs
`scripts/verify.sh`. Do not read this document as a claim that CI verified
anything. Both runs were manual: v0.2.0 in a Codespace, v0.2.1 on `hw-gz`.

Anyone reproducing it locally requires a **Linux host** (a Codespace, a
container, or any Linux machine) plus the artifact downloaded from the `build`
workflow. The artifact's exec bit is lost on transfer, so `chmod +x` is
**mandatory** — without it the verifier fail-closes at preflight exactly as it
does on Windows:

```bash
$ chmod +x dist/caddy-linux-amd64
```

Then, from the repository root, run it. The form that keeps the log is quoted,
with its recorded output, under "The aggregate verifier" below.

## Environment

| requirement | value |
| --- | --- |
| shell | `bash` |
| host | Linux (the result of record); the Windows authoring host fail-closes |
| tools | `jq`, `git`, `grep`, `sort`, `diff`, `comm`, `awk` |
| artifact | `dist/caddy-linux-amd64`, the **built** binary from the `build` workflow run 41069346485 |

Check the tool that the structural assertions depend on:

```bash
$ jq --version
```

If `jq` is missing, every check that uses it must fail closed. It must never
silently skip, because a skipped check manufactures green.

## The one structural rule that matters most

Wrapper order inside `listener_wrappers` is semantic. `layer4` must come
**before** `tls`, because layer4 has to see the raw ClientHello and route on SNI
before decryption happens; if `tls` ran first, the ClientHello would already be
consumed and REALITY passthrough could not work.

The adapted JSON therefore pins this order, and the check is shown to be
sensitive: a `/tmp` copy with the two wrappers swapped must fail the same
assertion. An order pin that cannot fail pins nothing.

## What "adapted JSON" means

`caddy adapt` turns the Caddyfile into the JSON config Caddy actually loads. The
C2 assertions read that JSON rather than the Caddyfile text, because the
Caddyfile is a shorthand and the JSON is the real structure.

Two shapes are worth knowing before reading any assertion, because they differ
from what a Caddyfile-only reading would suggest:

1. The layer4 proxy handler's upstream is an **array**: `upstreams` is a list of
   objects, each with a `dial` list of addresses. In the adapted JSON the
   upstream appears as `upstreams[0].dial[0]`, not as a singular `upstream`
   string. `proxy_protocol` is a plain string on the handler.
2. The SNI matcher appears as a `sni` array nested inside the layer4 wrapper's
   matcher set, so the assertion looks for objects that `has("sni")` and
   requires the value to be exactly `["b.test"]`.

Every path that differs from the spec text, and why, is recorded in
`.gate/release/DEVIATIONS.md`. That file is an evidence artifact kept beside the
release evidence; `.gate/` is gitignored, so it is not in the tracked tree. Each
entry's substance is also stated inline where it applies, so this document does
not depend on having that file to hand.

## The checks

### C1 — `caddy validate` accepts the delivery Caddyfile

`caddy validate --config deploy/Caddyfile` must exit `0`. This is the proof that
the placeholder discipline holds: the skeleton may carry `<TOKEN>` values, but
it must still be valid Caddyfile syntax and provisionable modules.

A green `validate` is worthless if the command is a no-op, so it is paired with
a sensitivity control: a `/tmp` copy carrying an undefined directive **inside a
site block** must be **rejected**. The mutation has to land inside a site block:
at the top level a bare token parses as a site *address*, so the control would
be inert there. See D-2 in `.gate/release/DEVIATIONS.md`.

### C2 — the adapted JSON structure

| property | assertion |
| --- | --- |
| exactly one layer4-wrapped `:443` server | count servers whose `listen` contains `:443` and whose wrappers include `layer4`; must be 1 |
| `layer4` before `tls` | index of `layer4` < index of `tls` in that server's `listener_wrappers`, plus a swapped-copy control |
| SNI matcher | exactly one `sni` object under the layer4 wrapper, value exactly `["b.test"]` |
| PROXY forwarding | exactly one `proxy` handler, `proxy_protocol` = `v2`, `upstreams[0].dial[0]` matching `^127\.0\.0\.1:[0-9]+$` |
| B isolated | the `b.test` 404 route is `terminal` and is ordered before the `forward_proxy` route in the same server |
| naive preconditions | exactly one `forward_proxy` server on `:443`, no `upstream` key on the `forward_proxy` object, and `forward_proxy` ordered **before** `reverse_proxy` in the site's subroute |

The B-isolation row is a deliberate substitution and it must be stated plainly,
because a reader comparing the spec text to the verifier will otherwise think a
check was quietly weakened. The spec asked for B's 404 to come from a server
carrying **no** `layer4` wrapper. Real adapt output shows that is unsatisfiable
with this delivery config: every site keyed on `:443` — including `b.test`,
whose implicit scheme is https and whose default port is 443 — consolidates into
one server, `srv0`, and the global
`servers :443 { listener_wrappers { layer4 {...} tls } }` block applies to that
server. Measured on ubuntu-latest: `srv0 listen=[":443"] wrappers=[layer4,tls]`
holds `b.test`'s routes. `b.test:443` and `https://b.test` both still merge into
`srv0`; only `:8443` splits, and that moves B off `:443` and breaks the
coexistence the config exists for.

The check therefore asserts the property the wrapper clause was protecting — B
is never handled by the naive proxy — which is directly observable: the `b.test`
404 route is `terminal` and ordered before `forward_proxy` in the same server,
so a request to `b.test` cannot reach the naive handler. Sensitivity was
demonstrated: reordering the routes, clearing `terminal`, changing the status to
200, or deleting the route all FAIL. See D-1 in
`.gate/release/DEVIATIONS.md`.

The `upstream` clause is a security property, not a style preference: setting a
forwardproxy `upstream` silently disables `acl` and `ports`, including the
default private-network deny.

### The handler order is a required pin, and v0.2.0's check pointed the wrong way

Two directives in one site compile into one `subroute` in the adapted JSON, and
their order there is the order Caddy runs them. `order forward_proxy before
reverse_proxy` in the global options block is what produces

```text
handle = [forward_proxy, reverse_proxy]
```

Measured: **delete that line and `caddy adapt` still exits 0.** The route
becomes `["reverse_proxy","forward_proxy"]`, the website handler answers first
and swallows every request, and no CONNECT ever reaches `forward_proxy`. A
silent misconfiguration with a green validation is worse than a validation
error, so S3-9 asserts the resulting order in the adapted JSON as well as the
Caddyfile asserting it. The ordering clause also requires a `reverse_proxy` to
be present at all: the "website" role has to exist, and in v0.2.0 it did not.

That assertion was shown to be sensitive, not merely present: adapting a `/tmp`
copy with the `order` line deleted yields `["reverse_proxy","forward_proxy"]`,
and `verify.sh` against that copy reports `ITEM S3-9 FAIL` (S3-8 still PASS) and
`VERIFY: FAIL`. An order pin that cannot fail pins nothing.

S3-9 **replaced** a clause in v0.2.1. v0.2.0 required "an `authentication`
handler with a `http_basic` provider exists". That clause protected neither
naive property, and it produced the defect it was supposed to catch: the
site-level `basic_auth` it demanded ran before `forward_proxy` and answered
`401` with `www-authenticate: Basic realm="restricted"` to every request — a
plain `GET` and a correctly credentialed `CONNECT` alike. Measured on the v0.2.0
config, `.gate/release/SP4-D1.txt`. naive authenticates the CONNECT itself,
through `forward_proxy`'s own `basic_auth` reading `Proxy-Authorization`; that
is a separate mechanism and it needs no `authentication` handler in the site.
Do not reintroduce either the clause or the site-level `basic_auth`.

### C3 — the xray skeleton

`deploy/xray/config.json` must parse, and its `acceptProxyProtocol` must be
`true`. That boolean is asserted **in both directions**: the Caddy side sends
`proxy_protocol v2`, the xray side must accept it, and the upstream port must
equal the xray inbound port. One side alone produces a tunnel that validates and
then breaks at runtime.

The parse check:

```bash
$ jq -e . deploy/xray/config.json >/dev/null && echo PASS
```

The pairing check joins both files and is implemented in `scripts/verify.sh` as
item S3-11, including a mutation control that flips `acceptProxyProtocol` to
`false` in a `/tmp` copy and requires the join to fail. The SNI collection
reads the `sni` array's scalars directly; wrapping it again would compare
`[["b.test"]]` against `["b.test"]` and fail for the wrong reason (D-3).

### Sprint 7 — secrets hygiene and the placeholder register

No credential-shaped value may exist outside the register. The checks are:

```bash
$ git ls-files --error-unmatch .env >/dev/null 2>&1 || echo "not tracked"
```

```bash
$ git grep -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -- . || echo "no UUID-shaped string"
```

The hostname allowlist is a set-equality check, so adding any new hostname to
`deploy/` is a visible spec change rather than a silent edit:

```bash
$ git grep -hoE '[A-Za-z0-9._-]+\.(test|com|net|io|org)' -- deploy/ ':!deploy/PLACEHOLDERS.md' | sort -u
```

The placeholder register is closed in both directions: every token in `deploy/`
must be documented, and every documented token must appear.

```bash
$ git grep -hoE '<[A-Z_]+>' -- deploy/ ':!deploy/PLACEHOLDERS.md' | sort -u
```

```bash
$ git grep -hoE '<[A-Z_]+>' -- deploy/PLACEHOLDERS.md | sort -u
```

### The aggregate verifier

`scripts/verify.sh` re-runs the offline checks and prints one `ITEM <ID> PASS`
line per check followed by a final `VERIFY: PASS`. It is fail-closed: a missing
`jq`, a non-executable `CADDY_BIN`, or a missing input file is a hard error with
a diagnostic.

Syntax-check the script itself:

```bash
$ bash -n scripts/verify.sh
```

Fail-closed control: pointing `CADDY_BIN` at a nonexistent path must exit
non-zero. This control was exercised on the Windows authoring host, which is
where it is most useful — the binary is unusable there, so the preflight path is
the only path that host reaches.

```bash
$ CADDY_BIN=/nonexistent/caddy bash scripts/verify.sh  # expect-fail
```

The same preflight control fires with the default `CADDY_BIN` on that host,
because the artifact has no exec bit there:

```bash
$ CADDY_BIN=dist/caddy-linux-amd64 bash scripts/verify.sh  # expect-fail
```

On the Linux host the verifier is green. The recorded output below is from
ubuntu-latest in a GitHub Codespace against the artifact from `build` run
41069346485; the v0.2.1 run on `hw-gz` produced the same lines over that run's
item set and the same final line.

```bash
$ bash scripts/verify.sh | tee .gate/release/verify-run.log
ITEM S3-1 PASS
ITEM S3-2 PASS
ITEM S3-3 PASS
ITEM S3-4 PASS
ITEM S3-5 PASS
ITEM S3-6 PASS
ITEM S3-7 PASS
ITEM S3-8 PASS
ITEM S3-9 PASS
ITEM S3-10 PASS
ITEM S3-11 PASS
ITEM S7-1 PASS
ITEM S7-2 PASS
ITEM S7-3 PASS
ITEM S7-4 PASS
ITEM S7-5 PASS
ITEM S7-6 PASS
ITEM S7-7 PASS
ITEM S7-8 PASS
VERIFY: PASS
```

This line pipes through `tee` so the log is kept; it is the form recorded in the
transcript with `exit=0` under the HOST B heading. `.gate/release/verify-run.log`
holds the **v0.2.1** run's output, i.e. one PASS line per item in that run's set
and `VERIFY: PASS`, produced on `hw-gz` after S3-9 changed.

## The item set, the summary line, and the binary precondition

That recorded output predates the five items v0.4.0-SP7 added, so it is not the
current item set and must not be read as one. `scripts/verify.sh` now declares
its own size — `EXPECTED_ITEMS=24`, kept in the same file as the items it counts
— and the current set is

`S3-1`, `S3-2`, `S3-3`, `S3-4`, `S3-5`, `S3-6`, `S3-7`, `S3-8`, `S3-9`,
`S3-10`, `S3-11`, `S7-1`, `S7-2`, `S7-3`, `S7-4`, `S7-5`, `S7-6`, `S7-7`,
`S7-8`, `S7-12`, `S7-13`, `S7-14`, `S7-15`, `S7-18`.

The gap in the `S7-*` numbering is deliberate. `S7-9`, `S7-10`, `S7-11`,
`S7-16` and `S7-17` are meta-items about the verifier itself: does it exit `0`,
does it fail closed, does this document cover every ID, is the declared item
count self-consistent, is the evidence set publishable. A check cannot assert its
own output from inside itself without the item set growing on every edit, so
those five are reviewed by re-running the commands in the specification and are
not emitted by the script.

**The runtime items are not in the script and are not counted.** A2, A3, B\* and
C\* are observations that need a running Caddy on a real host: a live CONNECT, a
live `acl` deny, a live `probe_resistance` probe. They cannot be produced
offline, so they are **not** in `scripts/verify.sh` and therefore do **not**
count towards `EXPECTED_ITEMS`. They are recorded in "What the runtime actually
answers" below.

A full run ends with a machine-readable summary line, then the verdict:

```text
PASS=24 FAIL=0
VERIFY: PASS
```

`PASS=<n> FAIL=<m>` is printed only after every item has had its chance to run,
and the exit status is `0` only when `n` equals `EXPECTED_ITEMS` and `m` is `0`.
A fail-closed exit — missing `jq`, missing input file, non-executable
`CADDY_BIN` — prints `VERIFY: FAIL` and a `FATAL:` diagnostic but **no** summary
line, so a truncated run can never be mistaken for a complete one.
`VERIFY: PASS|FAIL` is always the last line of output.

**The verifier needs a built Caddy.** `CADDY_BIN` must point at a Caddy binary
that is both built and executable. It defaults to `dist/caddy-linux-amd64`, and
`dist/` is gitignored, so a clean clone has no such file: build first, per
`docs/BUILD.md`, then run the verifier. A missing binary is not a defect in the
verifier — it is the designed fail-closed path, and it exits `2`.

The credential scan (`S7-12`) matches three patterns, quoted here so a reader can
re-run them by hand. The first and third use the POSIX bracket expression
`[[:space:]]` rather than a shorthand whitespace class, which POSIX ERE does not
define:

```text
"privateKey"[[:space:]]*:[[:space:]]*"[^<"]
[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
(secret|password|passwd|passphrase)[[:space:]]*[:=][[:space:]]*[^<$[:space:]]
```

The third pattern is matched case-insensitively. A case-sensitive scan would let
an all-uppercase assignment through untouched.

The five items added in v0.4.0-SP7 post-date the recorded run, so their output
below is from a later, separate run on the Windows authoring host. That run used
`CADDY_BIN=/bin/true` only to reach the item layer; the S3 items FAIL in it,
correctly, because `/bin/true` is not Caddy. The five new items reported:

```text
ITEM S7-12 PASS
ITEM S7-13 PASS
ITEM S7-14 PASS
ITEM S7-15 PASS
ITEM S7-18 FAIL
```

`S7-18` FAILs because this clone carries no `v0.3.0` tag, so there is no baseline
to diff `deploy/` against. It fails closed rather than skipping, because a
missing baseline cannot be read as "unchanged". It stays FAIL until the tag
exists.

## What the runtime actually answers

Everything in this section was measured with `caddy run` on `hw-gz`, against
the delivery config with **only** `<NAIVE_USER>` and `<NAIVE_PASSWORD>` replaced
by throwaway test values (`diff -u` in the evidence proves nothing else
changed), and a test backend answering `200` + `X-Site: v4` + `SITE-BODY-v4` on
`127.0.0.1:8080`. The evidence files are `.gate/release/SP4B-D1.txt`,
`SP4B-D2.txt` and `SP4B-D5.txt`. Two of v0.2.0's spec sentences guessed the
wrong observables; the properties they were reaching for are recorded here as
measured, which is a correction of the text, not a loosening of the check.

### The site role answers

A plain `GET /` to the site returns `HTTP/2 200` with `x-site: v4` and the body
`SITE-BODY-v4`, and no `www-authenticate` and no `Proxy-Authenticate`. That is
what the `reverse_proxy` handler is there for, and it is only reachable because
`forward_proxy` comes first and passes a non-proxy request through.

### A successful naive CONNECT does not say "Connection established"

A CONNECT carrying a valid `Proxy-Authorization` answers

```text
HTTP/1.1 200 OK
Alt-Svc: h3=":443"; ma=2592000
Padding: <random padding>
Server: Caddy
Date: ...
```

`200 OK` with a `Padding:` header and `Alt-Svc`, **not** `200 Connection
established`. The status string is not the verdict either: the tunnel is
established when bytes reach the far end. Measured as a relayed inner request —
a `GET /` sent inside the tunnel came back with the origin's own
`HTTP/1.0 200 OK` and a full page body (201,691 bytes in `SP4B-D2.txt`; the
page size varies per run). Do not assert on "Connection established", and do not
treat `200 OK` alone as proof.

### An acl-denied CONNECT also answers 200 OK, then closes

The default private-network deny does **not** answer `403` or `502`. Measured, a
credentialed CONNECT to `127.0.0.1:8080` on the unmodified delivery config (no
`acl` directive) answers `200 OK` with the same `Padding:`/`Alt-Svc` headers and
then closes the connection: no body, no error, and `openssl s_client` exits `0`
well before its timeout.

The verdict cannot come from the status line. It comes from four independent
observables, all measured in `SP4B-D5.txt`:

- the denied CONNECT answers `200 OK` carrying a `Padding:` header — naive's
  decoy reply, not a tunnel;
- `captured_bytes=149`: response headers only, no origin payload, so the inner
  `GET` was never relayed;
- the backend's request log has zero lines before the probe and zero after it;
- the positive control described below: on the test-only
  `acl { allow 127.0.0.1/32 }` copy, the same probe returns `X-Site: v4` and
  appends `GET /from-control` to that same log.

That negative is only meaningful beside a positive control, and the control was
run: the same probe, same credentials, on a test-only copy of the config with
`acl { allow 127.0.0.1/32 }` added, relayed the inner request — `X-Site: v4`,
`SITE-BODY-v4`, and a new `GET /from-control` line in the backend log. The acl is
the only difference between the two runs, which is what attributes the deny
result to the deny.

One measurement hazard, found the hard way: `reverse_proxy` keeps an upstream
keep-alive connection open, so after any successful site request `ss -tn` shows
a caddy-owned ESTAB to `127.0.0.1:8080` that is **not** a proxy tunnel and looks
identical to one. Socket sampling is therefore ambiguous and is not used as
evidence here. `SP4B-D5.txt` does carry an `ss` table labelled as sampled while
a second denied CONNECT was held open, but no process is shown holding that
CONNECT, so that table proves nothing even setting the keep-alive aside. Sample
sockets on a freshly started caddy, before the site has been requested, or the
deny check reads a false positive.

### `probe_resistance`: the two variants are identical on the probes tried

Sprint 4 exercised two `probe_resistance` variants — the bare form and a
`<secret>` form — against the three D6 probes. Both produced identical results
on all three: `200` + `X-Site`, `0` x `407`, `0` x `Proxy-Authenticate`. That is
the whole claim, and U1 is closed only to that extent: this is not evidence that
a secret path resists probing in general, and nothing here says what another
client or another probe set would see. Measured in `.gate/release/SP4-D6.txt`;
not re-run in v0.2.1. The delivery config keeps the form it already has.

### `listener_wrappers { tls }` alone cannot start

A global `servers :443 { listener_wrappers { tls } }` block is refused by this
build: "it is unnecessary to specify the TLS listener wrapper in the first
position because that is the default". The refusal applies only to a wrapper
list naming `tls` **alone**. It bit the Sprint 4 test harness, whose overlay
configs dropped the block; that is a harness note, not a delivery defect. The
delivery config lists `layer4` and then `tls`, which is valid and loads. Do not
"simplify" the block to `tls` alone, and do not read the Sprint 4 overlays as
the delivery shape.

## What the Windows authoring host cannot do

On the Windows/MSYS authoring host the binary cannot be executed. It is a Linux
ELF, and the attempt exits `126` with
`cannot execute binary file: Exec format error`, recorded verbatim in the
transcript. There `test -x` is also false, so `scripts/verify.sh` fail-closes at
preflight with exit `2` and never reaches an item.

Therefore, **on that host only**:

- S3-1 binary provenance, S3-2 `validate`, S3-3 the validate sensitivity
  control, and every C2/C3 assertion that depends on `caddy adapt` are
  unreachable. They are **BLOCKED** there, and no expected value was relaxed to
  pretend otherwise.
- The verifier's fail-closed path **is** verified, because that path was
  exercised.

This is a limitation of the host, not a verdict on the deliverable. The S3 items
are BLOCKED **on the Windows host** and PASS **on the Linux host**; the Linux run
is the result of record. The label `NOT VERIFIED IN THIS SLICE` is reserved for
work never attempted on any host, and the S3 items are not in that category.

## Certificate assertions must read the SAN, not the subject

Caddy's internal CA leaves the certificate subject distinguished name empty, so
`subject=` prints nothing useful; the hostname lives only in the SAN extension
as `DNS:<name>`. Any certificate assertion must therefore read the SAN.
