# Placeholder register for the v0.2.1 delivery skeletons.
#
# This file is the single source of truth for every token that must be replaced
# before deployment. Item S7-5 checks it in both directions: every angle-bracket
# token in deploy/ must be documented here, and every token documented here must
# actually appear in deploy/.
#
# Two kinds of placeholder exist, and they are deliberately different:
#
#   1. Credential placeholders use angle-bracket tokens: <VLESS_UUID>,
#      <REALITY_PRIVATE_KEY>, <REALITY_SHORT_ID>, <NAIVE_USER>,
#      <NAIVE_PASSWORD>.
#
#   2. Hostnames are NOT angle-bracket tokens. A Caddy site address must parse
#      as a valid host, and an angle-bracket token would fail address parsing.
#      The hostnames
#      used here are RFC 6761 reserved test names and are used literally:
#      a.test, b.test, example.com. Item S7-4 enforces that this is the complete
#      set of hostname literals in deploy/.

| token | where it appears | what to replace it with |
| --- | --- | --- |
| <VLESS_UUID> | deploy/xray/config.json, clients[0].id | A freshly generated VLESS client UUID. Generate it on the deployment host; never commit a real one. |
| <REALITY_PRIVATE_KEY> | deploy/xray/config.json, realitySettings.privateKey | The x25519 private key printed by the xray x25519 helper. The matching public key goes in the client, not here. |
| <REALITY_SHORT_ID> | deploy/xray/config.json, realitySettings.shortIds[0] | A short id generated for this deployment. It must agree with the client configuration. |
| <NAIVE_USER> | deploy/Caddyfile, forward_proxy block of the naive site | The naive proxy username, for the `Proxy-Authorization` the CONNECT carries. There is no site-level `basic_auth` in v0.2.1, so this token appears in exactly one place. |
| <NAIVE_PASSWORD> | deploy/Caddyfile, forward_proxy basic_auth | The naive proxy secret, in clear text. forwardproxy stores base64 of "user:secret" rather than a bcrypt hash, so this position takes the plaintext. |

## Replace-me literals (not angle-bracket tokens)

| literal | where | what it is |
| --- | --- | --- |
| a.test | deploy/Caddyfile site address | RFC 6761 reserved test hostname. Replace with the naive endpoint's real hostname. |
| b.test | deploy/Caddyfile site address, layer4 SNI matcher, deploy/xray/config.json serverNames | RFC 6761 reserved test hostname. Replace with the REALITY hostname. The Caddy-side matcher and the xray-side serverNames must stay equal; S3-11 asserts that. |
| example.com | deploy/Caddyfile probe_resistance, deploy/xray/config.json dest | Documentation domain. Replace with a real, reachable decoy site. |
| 127.0.0.1:19098 | deploy/Caddyfile layer4 upstream, deploy/xray/config.json inbound port | Fixed loopback address. The port must stay equal on both sides; S3-11 asserts the port equality. |
| 127.0.0.1:8080 | deploy/Caddyfile reverse_proxy of the naive site | Placeholder website upstream, fixed loopback in the same style as the xray port. Point it at the real backend before deployment. |

## Removed in v0.2.1: the site-level `basic_auth` hash

v0.2.0 carried a site-level `basic_auth` in the naive site, with a format-valid
bcrypt hash of a published throwaway string, so that `caddy validate` would pass
and an `authentication` handler would exist. Both the block and the hash are
**gone**, and they must not come back:

- the block ran before `forward_proxy` and answered `401` with
  `www-authenticate: Basic realm="restricted"` to every request, so the site
  served nothing and even a correctly credentialed CONNECT was refused;
- the only thing that demanded it was a verifier clause that protected no naive
  property. S3-9 now asserts the handler order instead.

naive authenticates the CONNECT itself, from `Proxy-Authorization`, through
`forward_proxy`'s own `basic_auth`. That is the only credential position left on
this site, and it is the two angle-bracket tokens above.

## Why `tls internal` is here

`tls internal` is a placeholder posture, not a production one. It makes Caddy
issue certificates from its own local CA so the skeleton validates and the
structure is testable offline. Before deployment, replace it with an ACME
issuer or an explicitly managed certificate.

Caddy's internal CA leaves the certificate subject DN empty, so the hostname is
present only in the SAN extension (DNS:...). Any certificate assertion must
read the SAN, never `subject=`.
