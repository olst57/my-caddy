# XRAY — the REALITY inbound and how it pairs with Caddy

This document describes the xray side of the delivery kit: what
`deploy/xray/config.json` contains, how it pairs with `deploy/Caddyfile`, and
what must be replaced before deployment.

The skeleton is placeholder-only. It is **not runnable as shipped**: with
`<REALITY_PRIVATE_KEY>` in place xray will not start. No item in this slice
asserts otherwise, and no xray process was started on any host.

> That paragraph describes the v0.2.1 slice. Sprint 5 has since run a real xray
> against this same configuration shape on `hw-gz`; the version, the field
> positions and what was measured are in
> [Measured on hw-gz (Sprint 5)](#measured-on-hw-gz-sprint-5) at the end, with
> the raw command output in `.gate/release/SP5-C1.txt` … `SP5-C6.txt`.

## The division of labour

Caddy owns the edge. The layer4 listener wrapper reads the raw ClientHello,
matches `tls sni b.test`, and forwards that connection to a fixed loopback
upstream. Everything else falls through to the `tls` wrapper and is terminated
locally — which is what the `b.test` site block answers `404` for.

xray owns the tunnel. Its REALITY inbound listens on `127.0.0.1:19098`, the same
socket Caddy forwards to, and expects the PROXY header Caddy prepends.

## The pairing, in both directions

`proxy_protocol v2` on the Caddy side and `acceptProxyProtocol: true` on the
xray side are a **pair**, not two independent settings. Setting one without the
other produces a tunnel that looks correct at configuration-validation level and
is broken at runtime. That is exactly why the check joins both files instead of
inspecting each in isolation.

Direction 1 — xray expects the header. In `deploy/xray/config.json` the reality
inbound's `streamSettings.sockopt.acceptProxyProtocol` must be `true`.

Direction 2 — Caddy sends it, to that same socket. In the adapted Caddy JSON the
layer4 proxy handler carries `proxy_protocol v2`, and its upstream address must
resolve to the same port the xray inbound listens on (`19098`). The port equality
is the load-bearing clause: it proves the header is sent to the socket that
expects it, rather than merely that both keywords exist somewhere in the repo.

The third clause ties the routing together: the xray `serverNames` value must
equal the Caddy-side SNI matcher value. In the skeleton both are `b.test`.

## Field-by-field

| field | skeleton value | meaning |
| --- | --- | --- |
| `inbounds[0].listen` | `127.0.0.1` | loopback only; the edge forwards here |
| `inbounds[0].port` | `19098` | must equal the Caddy layer4 upstream port |
| `inbounds[0].protocol` | `vless` | the tunnel protocol |
| `clients[0].id` | `<VLESS_UUID>` | placeholder; a real UUID must never be committed |
| `streamSettings.security` | `reality` | REALITY, not plain TLS |
| `realitySettings.serverNames` | `["b.test"]` | must equal the Caddy SNI matcher |
| `realitySettings.privateKey` | `<REALITY_PRIVATE_KEY>` | placeholder; the x25519 private key |
| `realitySettings.shortIds` | `["<REALITY_SHORT_ID>"]` | placeholder; must agree with the client |
| `realitySettings.dest` | `example.com:443` | documentation domain; replace with a reachable decoy |
| `sockopt.acceptProxyProtocol` | `true` | pairs with Caddy's `proxy_protocol v2` |

## What to replace

Replace, in order:

1. `<VLESS_UUID>` — generate on the deployment host; never commit a real one.
2. `<REALITY_PRIVATE_KEY>` — the x25519 private key. The matching public key
   belongs in the client configuration, not here.
3. `<REALITY_SHORT_ID>` — generate for this deployment; the client must agree.
4. `b.test` — in both `serverNames` here and the Caddy site address and SNI
   matcher. The two sides must stay equal.
5. `example.com:443` — a real, reachable decoy site for REALITY.
6. `19098` — only if you also change the Caddy upstream; the two must stay equal.

The full register, including the naive side's credentials, is
`deploy/PLACEHOLDERS.md`.

## Verification that was actually performed

These are `jq` checks against the skeleton. They are static: they parse JSON and
read fields. They do not start xray and say nothing about whether xray accepts
these placeholders. They were run on the Windows authoring host, where `jq` is
available; they need no Linux binary and therefore do not fail-close there.

The skeleton's JSON syntax is checked offline:

```bash
$ jq -e . deploy/xray/config.json >/dev/null && echo PASS
```

The structural check that the key material is exactly the registered
placeholders:

```bash
$ jq -e '([.inbounds[] | select(.streamSettings.security=="reality")] | length==1) and (.inbounds[0].streamSettings.realitySettings.privateKey=="<REALITY_PRIVATE_KEY>") and (.inbounds[0].streamSettings.realitySettings.shortIds|length==1) and (.inbounds[0].streamSettings.realitySettings.shortIds[0]=="<REALITY_SHORT_ID>")' deploy/xray/config.json >/dev/null && echo PASS
```

Note the indexing: the reality inbound is `.inbounds[0]`. Indexing `.[0]` at the
document root would try to index the root object with a number and fail; that
distinction is why the check reads `.inbounds[0]`. The failing form is recorded
here so the difference is visible rather than merely asserted:

```bash
$ jq -e '([.inbounds[] | select(.streamSettings.security=="reality")] | length==1) and (.[0].streamSettings.realitySettings.privateKey=="<REALITY_PRIVATE_KEY>") and (.[0].streamSettings.realitySettings.shortIds|length==1) and (.[0].streamSettings.realitySettings.shortIds[0]=="<REALITY_SHORT_ID>")' deploy/xray/config.json  # expect-fail
```

That form exits `5` with `Cannot index object with number (0)`. The passing
form uses `.inbounds[0]`.

The bidirectional pairing check lives in `scripts/verify.sh` as item S3-11. It
reads the **adapted** Caddy JSON, so it needs the Linux binary and ran on
ubuntu-latest in a GitHub Codespace against the artifact from `build` run
41069346485; `docs/VERIFY.md` states that provenance. It is not runnable on the
Windows authoring host, which fail-closes at preflight.

## NOT VERIFIED IN THIS SLICE

This heading covers the xray *runtime* as it stood in the v0.2.1 slice, and it
was accurate on every host used in that slice — no xray process had been
started anywhere. It is superseded by
[Measured on hw-gz (Sprint 5)](#measured-on-hw-gz-sprint-5) below. It is not a
statement about the Caddy-side offline checks, which ran and passed on Linux;
see `docs/VERIFY.md` for those.

- Any xray start *in the v0.2.1 slice*. No process was launched and no socket
  was bound on any host during that slice. Sprint 5 has since started xray on
  `hw-gz`; see below.
- Whether xray accepts these placeholders. It will not; they are placeholders.
- Any handshake, any PROXY header observed on the wire. That was Gate 0's probe,
  not this slice. Sprint 5 has since captured both; see below.
- That the REALITY tunnel works. In the v0.2.1 slice nothing was started
  anywhere, so nothing there claimed connectivity through this inbound. v0.2.1
  did measure a working naive CONNECT tunnel on the delivery config — an
  external target relayed an inner request — but that path never touches xray
  and is no evidence about this inbound. See `docs/VERIFY.md`.

`deploy/Caddyfile` uses `tls internal`, which is a placeholder posture, not a
production one. Caddy's internal CA leaves the certificate subject DN empty, so
the hostname is present only in the SAN extension. Any certificate assertion
must read the SAN, never `subject=`.

## Measured on hw-gz (Sprint 5)

Sprint 5 ran a real xray against the shape this document describes, on `hw-gz`
(Ubuntu 24.04.4 LTS, x86_64, root), on 2026-10-31 UTC. Inbound 443 is closed at
the cloud security group — that was recorded in the run session but is **not**
part of the evidence bundle, as noted under [Provenance](#provenance) below — so
every connection in the run is host-local: the listener is Caddy on `:443`, the
client is a second xray on the same box. The packet captures attached to C1 and
C2 are consistent with that premise: their outer endpoints are only `127.0.0.1`
and the host's own `172.31.2.95`. Raw output, including every command, is in
`.gate/release/SP5-C1.txt` … `SP5-C6.txt`; the PASS/FAIL table and the numbered
deviations are in `.gate/release/SPRINT5-SUMMARY.md`.

`deploy/xray/config.json` and `deploy/Caddyfile` were **not** modified by
Sprint 5. No item proved the shipped pairing wrong.

### Version actually used

```console
$ xray version | head -1
Xray 26.10.29 (Xray, Penetrates Everything.) 0afec66 (go1.27.3 linux/amd64)
```

The binary's sha256 on the host is
`e783b9d2b46ed1ab3617c59b04dfbce38c999322d018c6e060f18d88bf6158aa`; it came from
`Xray-linux-64.zip`, tag `v26.10.29`, downloaded on the authoring host and copied
up (the server cannot reliably reach github.com). `26.10.29` is a calendar
version, so it satisfies the `>= v1.8.0` requirement by the spec's own rule and
is not string-compared to `v1.8.0`.

### Provenance

The version line above is the whole of what `SP5-C4.txt` records. Three facts
used in this document were recorded in the run session but have no artifact in
the evidence bundle, and are marked here so they are not mistaken for captured
output:

- the sha256 `e783b9d2…`: **not in the bundle** — no `sha256sum` output was
  captured for the xray binary;
- the archive and tag it came from (`Xray-linux-64.zip`, `v26.10.29`,
  downloaded on the authoring host and `scp`'d up): **not in the bundle** — no
  download transcript was captured;
- inbound 443 being closed at the cloud security group: **not in the bundle** —
  no security-group listing was captured. It is the premise for reading the run
  as host-local, so the reading is corroborated where it can be: the C1 and C2
  captures show only `127.0.0.1` and `172.31.2.95` endpoints.

Treat these three as session notes rather than as evidence in either bundle.
The binary digest, in particular, is not corroborated: no `sha256sum` invocation
or output for it exists in the Sprint 5 bundle or the Sprint 6 one, so the value
is asserted, not captured. `SPRINT6-SUMMARY.md` repeats the same digest in its
tools table, but a table row is not command output either. The archive/tag
lineage and the security-group reading are likewise uncaptured. See
`.gate/release/SPRINT6-SUMMARY.md`.

### Field positions, as shipped

| # | file:line | field | value |
| --- | --- | --- | --- |
| 1 | `deploy/xray/config.json:34` | `inbounds[0].streamSettings.sockopt.acceptProxyProtocol` | `true` |
| 2 | `deploy/Caddyfile:39` | layer4 `proxy_protocol` | `v2` |
| 3 | `deploy/Caddyfile:42` | layer4 `upstream` | `127.0.0.1:19098` = `config.json:8` port |
| 4 | `deploy/Caddyfile:32` | `@reality tls sni` | `b.test` = `config.json:23` serverNames |
| 5 | `deploy/xray/config.json:30` | `realitySettings.dest` | `example.com:443`, placeholder |
| 6 | `deploy/xray/config.json:7` | `inbounds[0].listen` | `127.0.0.1` |

Row 1 is the only occurrence of the key in the file (`grep -c` = 1) and it sits
in `sockopt`, not in `tcpSettings`; rows 1+2 are the pair, rows 3+4 are the
equalities that tie the two files together.

### What the wire showed

With the shipped pairing, `openssl s_client -servername b.test` against `:443`
produces this on the Caddy → xray hop, as the first bytes of the connection:

```
0d0a0d0a000d0a515549540a 21 11 000c 7f000001 7f000001 ea7c 01bb | 16 03 01 ...
^ PROXY v2 signature      ^^ ^^ ^^^^ ^ src ip   ^ dst ip   ^srcport  ^443  ^ TLS ClientHello
                                                            (60028)
```

That is: PROXY v2 header (28 bytes, TCP over IPv4, length 12), then the client's
untouched ClientHello record. Caddy writes the header and the ClientHello as two
adjacent TCP segments rather than one — the stream is contiguous (seq `0:28`
then `29:337`), so "header then raw ClientHello" holds on the stream but not
inside a single packet. The certificate presented on that handshake is the one
belonging to the dest **this run measured**: `www.microsoft.com:443`, substituted
into a test copy of the config in place of the shipped placeholder
`example.com:443`. The `b.test` site block is never reached: the Caddy access log
has zero records for `b.test` while a control SNI (`a.test`) served by the same
Caddy does appear in it.

### Where the logged client IP comes from

- pairing on: `from 172.31.2.95:49182 accepted tcp:www.apple.com:443`. That
  address is the PROXY header's source; the socket peer on the 19098 hop was
  `127.0.0.1`. The PROXY header on that hop read
  `... 2111000c ac1f025f ac1f025f c01e 01bb`, i.e. source `172.31.2.95:49182`,
  destination `172.31.2.95:443`.
- both sides off: the same request succeeds but the log says
  `from 127.0.0.1:`, which is the socket address. That is the proof the address
  in the paired case came from the header and not from the socket.
- one side on, the other off: the connection is refused in both directions.

### Caveats measured here

1. **On a `freedom` outbound probe, 26.10.29 did not apply `sendThrough`.** The
   spec's suggested client-side trick for making the client's source differ from
   the l4 dial address, `"sendThrough": "127.0.0.2"` on the outbound, was
   accepted and not applied: a plain `freedom` outbound set to `127.0.0.2`
   still arrived from `127.0.0.1`, and `"sendThrough": "999.999.999.999"` still
   passed `xray run -test`. This is a finding about that outbound type in that
   probe, not about every outbound protocol in the build — none other was
   exercised. The Sprint 5 measurement therefore used a genuinely different
   source address (the host's own `172.31.2.95`) instead of a loopback alias.
2. **Choose the dest by the certificate you see through the tunnel.** On this
   host `www.apple.com:443` answers its own certificate when probed directly,
   but through REALITY the handshake presented `CN = tzcdn.ksc-test.com`
   (issuer Sectigo) — a cert that does not correspond to the dest. The item
   that asserts "the cert is the dest's" therefore failed for apple and passed
   for `www.microsoft.com:443`, whose direct and tunneled certificates are
   identical. Verify the decoy through the tunnel, not only with a direct
   `openssl` call. `www.google.com:443` is unreachable from this host.
3. **Intermittent first-connection stall on the layer4 path.** Three times
   during bring-up the first connection from a freshly started client to a
   freshly started layer4 listener stalled and timed out, with Caddy logging
   `caddy.listeners.layer4 ... "matching connection" ... "error":"EOF"`; the
   next attempt on the same client succeeded immediately. It is not a
   PROXY-pairing effect (it also happens with both sides off) and it is not
   explained here. Flagged for Sprint 6; it did not change any Sprint 5 verdict.

### What this does not cover

Sprint 6 has since run what this section used to list: HTTP/3 to the site
(`3 200`, SP6-F1), an unknown SNI (SP6-F3 — admin `200` before and after, the
xray log byte-identical, and the alert `internal error` rather than the
`unrecognized_name` the spec named), and B's two terminal states (SP6-F4, hit
with the upstream down; SP6-F5, miss → `404`) all passed on `hw-gz`, with the
raw output in `.gate/release/SP6-F1.txt` … `SP6-F5.txt`.

What remains uncovered: UDP/QUIC layer-4 routing, which was never built;
cascade/`upstream`, which was not exercised; any real domain or public-IP path,
since inbound 443 is blocked at the cloud security group (a session note — see
[Provenance](#provenance)); and the slow-ClientHello `matching_timeout` fallback
(U9), which was explicitly not constructed — nothing here claims that a
timed-out ClientHello falls to `404`.
