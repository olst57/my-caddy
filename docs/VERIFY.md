# VERIFY — reproducing the offline checks

This document explains how to reproduce every offline check in this slice.
Every command quoted below was executed; `docs/transcript-v0.2.0.txt` records
each with its real exit code and the host it ran on. Nothing here binds a
listener, starts a server, performs a TLS handshake, or sends an HTTP request.

## Where the checks actually ran

Two hosts matter, and they produced different lines. The transcript labels
every record with its host so a reader can tell which host produced which line.

**The result of record is the Linux run.** `scripts/verify.sh` was run on
**ubuntu-latest**, inside a **GitHub Codespace** (Ubuntu 24.04.5, `Linux x86_64`),
against the artifact from the `build` workflow's **run 41069346485** — the
`caddy-linux-amd64` binary built at commit
`0a3b22af3c4a467c12dd99eac50ebad7f6174530`. On that host all 19 items pass and
the verifier prints `VERIFY: PASS`. That is the verdict for the deliverable.

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
anything. The run was manual, in a Codespace.

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
| naive preconditions | exactly one `forward_proxy` server on `:443`, a `http_basic` authentication provider present, and no `upstream` key on the `forward_proxy` object |

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

The last clause is a security property, not a style preference: setting a
forwardproxy `upstream` silently disables `acl` and `ports`, including the
default private-network deny.

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

On the Linux host the verifier is green. Its recorded output, from ubuntu-latest
in a GitHub Codespace against the artifact from `build` run 41069346485, is:

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
transcript with `exit=0` under the HOST B heading. The log itself is
`.gate/release/verify-run.log`.

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
