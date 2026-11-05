# my-caddy

## What This Is

`my-caddy` builds one self-hosted Caddy binary and one delivery Caddyfile that
serve three roles on the same `:443` listener: a website reverse proxy, an
in-process naive proxy, and REALITY+Vision passthrough to Xray over layer4.
The repository is both a delivery kit and a testbed for the Qoder agent-team
workflow, so every behavioural claim must be backed by a command, an artifact,
or a recorded run.

The three roles are deliberately not three deployments. They share one binary,
one Caddyfile, and one port. The project exists to prove that this coexistence
is real, not merely configured.

## Core Value

Three roles — website, naiveproxy, and REALITY+Vision — coexist on one binary,
one Caddyfile, and one `:443` without interfering with each other, and that
claim is reproducible from evidence.

## Requirements

### Validated

- ✓ One Caddy binary carries `http.handlers.forward_proxy`,
  `layer4.handlers.proxy`, `caddy.listeners.layer4`, and `layer4.matchers.quic` —
  existing, v0.4.2.
- ✓ A single catch-all `:443` site runs `reverse_proxy` for the website role and
  `forward_proxy` for naive, with `forward_proxy` ordered first — existing,
  v0.2.1 onward.
- ✓ `layer4` reads SNI before `tls` and forwards `b.test` raw to
  `127.0.0.1:19098` with PROXY protocol v2 — existing, Sprint 5.
- ✓ The protocol surface is pinned to `protocols h1 h2`, so no QUIC listener is
  created and no `Alt-Svc` is advertised — existing, `feat/protocol-pin`.
- ✓ Secrets hygiene, placeholder registration, redaction tooling, and a
  one-command verifier — existing, Sprint 7.
- ✓ README provenance: upstreams, forks, the one mandatory patch, build inputs,
  and honest limitations — existing, v0.4.2.

### Active

- [ ] Freeze the current verification slice into a reviewable commit: the
  26-item offline verifier, the 7-item coexistence suite, and the CI workflow
  that runs both.
- [ ] Close the remaining `v0.4.0` runtime-acceptance findings: REALITY
  placeholder defaults, the `probe_resistance` target collision, and evidence
  completeness.
- [ ] Publish `v0.4.3` only after both suites are green, with artifacts, pins,
  and redacted evidence that match the tagged tree.

### Out of Scope

- HTTP/3 on `:443` — removed by the `protocols h1 h2` pin because one SNI with
  two transport identities on one port is the coexistence hazard this project
  avoids.
- Running the arm64 artifact — it is artifact-verified only; no run is claimed.
- Docker, a packaged distribution, BBR, or upstream cascades — outside the v4
  delivery shape.
- Public-internet HTTP/3 measurement — HTTP/3 is off by design.
- Licence or SPDX conclusions — not evidenced in this repository.
- Real domains, credentials, UUIDs, or REALITY key material — placeholders only.

## Context

The v4 specification (`../my-caddy-v4-SPEC.md`) defines Sprints 1–7 with
acceptance criteria `S1`–`S12` and edge cases `E1`–`E13`. Those sprints are
delivered through tag `v0.4.2`. The current work is the next slice: the offline
verifier grew from 24 to 26 items, a live coexistence suite was added under
`tests/coexist/`, and `.github/workflows/verify.yml` was added to run both.
Those changes are in the working tree on `feat/protocol-pin`, not on `main`.

The v0.4.0 runtime acceptance round passed 12 of 21 items, failed 7, and left 2
untested. The disposition is recorded in
`.gate/PM-DISPOSITION-RUNTIME-ACCEPT.md`. Two findings still matter most:
REALITY's shipped placeholder `dest` was rejected by the destination, and
naive's `probe_resistance` target collided with the destination being proxied.

The project runs in two environments. Windows is authoring-only: it cannot
execute the Linux ELF. A Linux host with root runs the coexistence suite,
because the suite binds `:443` and samples sockets with `ss`.

## Constraints

- **Single listener**: one `:443`; do not split roles onto additional ports.
- **Single Caddyfile**: the delivery shape is one file; probes must not be
  imported into it.
- **Caddy baseline**: `v2.11.7`; the patch and the four module assertions are
  stated against that tag.
- **One patch**: exactly one `.patch` under `patches/`; a second fails the build.
- **Forks**: both non-core modules come from `olst57/forwardproxy@naive` and
  `olst57/caddy-l4@master`.
- **Build flag**: `--replace` is mandatory with the patch; either alone does not
  compile.
- **Protocol pin**: `protocols h1 h2` must stay explicit; absence restores
  `h1 h2 h3`.
- **Handler order**: `forward_proxy` before `reverse_proxy`; `layer4` before
  `tls`.
- **No site-level `basic_auth`**: naive authenticates the CONNECT itself.
- **No `forward_proxy` upstream**: it silently disables the ACL and ports
  defaults.
- **Secrets**: no real domain, IP, host name, credential, UUID, or REALITY key.
- **Evidence**: a claim without a command and its output is not a result.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| One binary, one Caddyfile, one `:443` | The product claim is coexistence, not three separate proxies | — Pending |
| Build both modules from project forks | Upstream branch heads once changed the artifact with no commit here | ✓ Good |
| Keep `--replace` plus the single patch | The naive branch calls `caddyhttp.IdleTimeoutsFromContext`, absent in `v2.11.7` | ✓ Good |
| Pin `protocols h1 h2` | Removes the QUIC listener and Alt-Svc, avoiding two transport identities for one SNI | ✓ Good |
| Put `layer4` before `tls` | SNI must be read before TLS consumes the ClientHello | ✓ Good |
| No site-level `basic_auth` | It ran before `forward_proxy` and answered 401 to every request | ✓ Good |
| Enable `probe_resistance` | Unauthenticated CONNECT falls through to the site instead of 407 | ⚠ Revisit — target must not collide with the proxied destination |
| Verify offline first, then live | Config shape is cheap to check; only a live stack proves coexistence | ✓ Good |
| Treat Windows as authoring-only | The binary is a Linux ELF; runtime checks need Linux/root | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-05 after initialization*
