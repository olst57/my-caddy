---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Technology Stack

**Analysis Date:** 2026-11-05

## Languages

**Primary:**
- Caddyfile — delivery and probe configuration under `deploy/` and `tests/probes/`.
- Bash — build, verification, probes, and the coexistence harness in `scripts/` and `tests/`.
- JSON — Xray configuration (`deploy/xray/config.json`) and adapted Caddy JSON.

**Secondary:**
- Python 3 — test-only helpers under `tests/coexist/`.
- Go — not authored here; the binary is assembled from pinned upstream and forked modules.
- YAML — GitHub Actions workflows under `.github/workflows/`.

## Runtime

**Environment:**
- Linux `amd64` for execution and runtime tests.
- Linux `arm64` artifact is produced but never executed.
- Windows is authoring-only: it can edit files and run Git, but cannot execute the Linux ELF.

**Package Manager:**
- Go modules for the upstream and forked Caddy modules.
- No `package.json`, lockfile, or Node runtime is required by the project itself.

## Frameworks

**Core:**
- Caddy `v2.11.7` — HTTP server, TLS, reverse proxy, and listener wrapper host.
- `github.com/olst57/forwardproxy` at branch `naive` — naive forward proxy module.
- `github.com/olst57/caddy-l4` at branch `master` — layer4 routing.
- Xray — REALITY inbound on `127.0.0.1:19098`.

**Testing:**
- `scripts/verify.sh` — 26-item offline verifier; no listener bind.
- `tests/coexist/run.sh` — 7-item live coexistence suite; binds `:443`.
- `tests/probes/*.sh` — Gate 0 probes.

**Build/Dev:**
- `xcaddy` — newest stable tag at build time.
- Go `1.26.x` — exact patch recorded per run in `dist/pins.txt`.
- `jq` — offline JSON assertions.
- `curl`, `openssl`, `python3`, `iproute2` — coexistence suite.

## Key Dependencies

**Critical:**
- Caddy `v2.11.7` — the baseline the patch and four module assertions target.
- `forwardproxy@naive` — calls `caddyhttp.IdleTimeoutsFromContext`, absent in Caddy `v2.11.7`.
- `caddy-l4@master` — provides `layer4.handlers.proxy`, `caddy.listeners.layer4`, and `layer4.matchers.quic`.
- `caddy-read-idle-timeout.patch` — adds the missing symbol; exactly one patch is allowed.

**Infrastructure:**
- `jq` — mandatory for the offline verifier; absence is a hard failure.
- `ss` from `iproute2` — CO-7 socket assertion.
- Caddy internal CA — placeholder TLS posture for `a.test` and `b.test`.

## Configuration

- `deploy/Caddyfile` — one catch-all `:443` site, isolated `b.test`, `protocols h1 h2`.
- `deploy/xray/config.json` — REALITY inbound with `acceptProxyProtocol: true`.
- `deploy/PLACEHOLDERS.md` — every token that must be replaced before deployment.
- `.github/workflows/build.yml` — artifact build.
- `.github/workflows/gate0.yml` — Gate 0 probes.
- `.github/workflows/verify.yml` — offline and coexistence suites.

## Platform Requirements

- **Build host:** Bash, Git, Go, `xcaddy`, network access to the module sources.
- **Offline verifier:** Linux or MSYS with `jq` and an executable Caddy binary.
- **Coexistence suite:** Linux with root, because it binds `:443` and samples sockets.
- **Authoring host:** Windows is supported for edits and Git only.

<!-- refreshed: 2026-11-05 -->
