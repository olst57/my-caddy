# XRAY — the REALITY inbound and how it pairs with Caddy

This document describes the xray side of the delivery kit: what
`deploy/xray/config.json` contains, how it pairs with `deploy/Caddyfile`, and
what must be replaced before deployment.

The skeleton is placeholder-only. It is **not runnable as shipped**: with
`<REALITY_PRIVATE_KEY>` in place xray will not start. No item in this slice
asserts otherwise, and no xray process was started on any host.

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

This heading covers the xray *runtime*, and it is accurate on every host used in
this slice — no xray process was started anywhere. It is not a statement about
the Caddy-side offline checks, which ran and passed on Linux; see
`docs/VERIFY.md` for those.

- Any xray start. No process was launched, no socket was bound, on any host.
- Whether xray accepts these placeholders. It will not; they are placeholders.
- Any handshake, any PROXY header observed on the wire. That was Gate 0's probe,
  not this slice.
- That the tunnel works. Nothing in v0.2.0 claims connectivity.

`deploy/Caddyfile` uses `tls internal`, which is a placeholder posture, not a
production one. Caddy's internal CA leaves the certificate subject DN empty, so
the hostname is present only in the SAN extension. Any certificate assertion
must read the SAN, never `subject=`.
