---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Architecture

**Analysis Date:** 2026-11-05

## Pattern Overview

**Overall:** Single-binary, single-listener delivery kit with a build-and-verify
pipeline around it.

**Key Characteristics:**
- One Caddy process owns TCP `:443` for all three roles.
- SNI is inspected before TLS termination.
- The delivery configuration is a placeholder posture, not a runnable deployment.
- Every behavioural claim is backed by an offline check, a live check, or a
  recorded gate report.

## Layers

**Build layer:**
- Purpose: produce auditable binaries from pinned inputs.
- Contains: `scripts/build.sh`, `patches/caddy-read-idle-timeout.patch`,
  `.github/workflows/build.yml`.
- Depends on: upstream Caddy, both forks, `xcaddy`, Go.
- Used by: releases and the verification jobs.

**Configuration layer:**
- Purpose: declare the three-role listener without cross-contamination.
- Contains: `deploy/Caddyfile`, `deploy/xray/config.json`,
  `deploy/PLACEHOLDERS.md`.
- Depends on: the four modules asserted at build time.
- Used by: the runtime and the offline verifier.

**Runtime layer:**
- Purpose: route each connection to the correct role.
- Contains: the `layer4` listener wrapper, `forward_proxy`, `reverse_proxy`, and
  the isolated `b.test` site.
- Depends on: Xray on `127.0.0.1:19098` and the site backend on
  `127.0.0.1:8080`.
- Used by: real clients and `tests/coexist/run.sh`.

**Verification layer:**
- Purpose: make regressions fail before release.
- Contains: `scripts/verify.sh` (26 items), `tests/coexist/run.sh` (7 items),
  `tests/probes/*.sh` (Gate 0), `.github/workflows/verify.yml`.
- Depends on: the built binary, `jq`, Linux, root for the coexistence suite.
- Used by: CI, release gating, and the agent-team review loop.

## Data Flow

**Build flow:**

1. Resolve fork branch heads and the newest stable `xcaddy` tag.
2. Clone Caddy at `v2.11.7`.
3. Apply exactly one patch.
4. Build with `xcaddy --replace` against the patched tree.
5. Assert four modules.
6. Write both architectures, `SHA256SUMS`, and `pins.txt`.

**Request flow:**

1. A client opens TCP `:443`.
2. `layer4` reads the ClientHello before `tls`.
3. SNI `b.test` is proxied raw to `127.0.0.1:19098` with PROXY v2.
4. Any other SNI falls through to the local TLS wrapper.
5. The `:443, a.test` site runs `forward_proxy` before `reverse_proxy`.
6. A valid `Proxy-Authorization` CONNECT opens a tunnel.
7. Anything else falls through to the site's `reverse_proxy`.
8. `b.test` answers 404 and never carries site content or `forward_proxy`.

**State Management:**
- No persistent application state.
- Caddy holds only in-memory listener and connection state.
- Evidence lives in `.gate/`, `evidence/`, and `dist/pins.txt`.

## Key Abstractions

**Protocol pin:**
- Purpose: keep HTTP/3 and its QUIC listener off `:443`.
- Expression: `protocols h1 h2` in `deploy/Caddyfile`.
- Why: one SNI with two transport identities on one port is the coexistence hazard.

**Handler order:**
- Purpose: ensure proxy requests reach `forward_proxy` before the site handler.
- Expression: `order forward_proxy before reverse_proxy`.
- Why: without it, validation still passes while naive is silently dead.

**Listener wrapper order:**
- Purpose: inspect SNI before TLS consumes the ClientHello.
- Expression: `layer4` listed before `tls`.
- Why: reversing the order breaks REALITY passthrough.

**Placeholder register:**
- Purpose: keep the delivery config runnable-looking but not runnable-as-shipped.
- Expression: `deploy/PLACEHOLDERS.md` plus `<...>` tokens.
- Why: real secrets must never enter the tree.

## Entry Points

**Build:**
- Location: `scripts/build.sh`.
- Triggers: CI, releases, manual runs.
- Responsibilities: pin inputs, build, assert modules, emit artifacts.

**Offline verification:**
- Location: `scripts/verify.sh`.
- Triggers: `bash scripts/verify.sh`, CI.
- Responsibilities: validate config shape and hygiene without binding a listener.

**Runtime verification:**
- Location: `tests/coexist/run.sh`.
- Triggers: CI as root, manual Linux run.
- Responsibilities: start the real stack and assert the three roles.

**Delivery configuration:**
- Location: `deploy/Caddyfile`.
- Triggers: `caddy validate`, `caddy adapt`, `caddy run`.
- Responsibilities: declare all three roles on one listener.

## Error Handling

- The build fails closed on a missing module, a second patch, or a bad pin.
- The offline verifier fails closed on missing `jq`, a missing input, or a
  non-executable binary.
- The coexistence suite refuses to start if `:443`, `19098`, or `8080` is taken.
- Assertions carry the observed value, not just a non-zero exit.

<!-- refreshed: 2026-11-05 -->
