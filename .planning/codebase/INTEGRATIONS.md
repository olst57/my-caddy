---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# External Integrations

**Analysis Date:** 2026-11-05

## External APIs

**Upstream source repositories:**
- `github.com/caddyserver/caddy` at tag `v2.11.7` — Caddy core source.
- `github.com/olst57/forwardproxy` at branch `naive` — this project's naive fork.
- `github.com/olst57/caddy-l4` at branch `master` — this project's layer4 fork.
- `github.com/caddyserver/xcaddy` — builder, resolved to the newest stable tag.

**Build-time network:**
- `scripts/build.sh` clones Caddy and resolves fork heads and `xcaddy` tags.
- `pins.txt` records the exact commits and tool versions actually used.

**Runtime test network:**
- `tests/coexist/run.sh` contacts one external TLS endpoint, `$CO_TARGET`
  (default `www.apple.com:443`), because forwardproxy's default private-network
  deny refuses a loopback destination.
- Every other connection in the suite is to loopback.

## Databases

None. The project has no database, ORM, migration, or persistence layer.

## Authentication Providers

**naive proxy authentication:**
- `forward_proxy` uses its own `basic_auth <NAIVE_USER> <NAIVE_PASSWORD>`.
- Credentials travel in `Proxy-Authorization` on CONNECT.
- This is separate from any site-level authentication and must not be replaced
  by a site-level `basic_auth`.

**REALITY:**
- Xray holds `<VLESS_UUID>`, `<REALITY_PRIVATE_KEY>`, and `<REALITY_SHORT_ID>`
  as registered placeholders.
- Caddy does not terminate REALITY TLS; it forwards raw bytes to Xray.

**Internal CA:**
- Caddy's internal CA issues `a.test` and `b.test` certificates as a placeholder
  posture. Clients must trust that root or skip verification in tests.

## Webhooks

None.

## External Services

**GitHub Actions:**
- `build.yml` — builds artifacts on path-filtered pushes, releases, and manual dispatch.
- `gate0.yml` — runs the Gate 0 probes.
- `verify.yml` — runs the offline verifier and the coexistence suite.

**Xray process:**
- Listens on `127.0.0.1:19098`.
- Must enable `acceptProxyProtocol: true` to pair with Caddy's
  `proxy_protocol v2`.

**Local site backend:**
- `reverse_proxy 127.0.0.1:8080` is a placeholder upstream.
- In tests, `tests/coexist/site-backend.py` plays this role.

## Trust Boundaries

- Caddy's internal CA is not a public PKI and must not be presented as one.
- The naive tunnel is authenticated at the proxy layer, not by the site.
- REALITY traffic remains encrypted end-to-end through Caddy.
- No real credential, UUID, domain, or host name is stored in the repository.

<!-- refreshed: 2026-11-05 -->
