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

## Current Milestone: v0.5.0 REALITY closure and E2E regression harness

**Goal:** Turn the REALITY and naive end-to-end results that were measured by
hand into a repository-owned regression suite, and use it to close the last
unproven leg of the three-role claim.

**Target features:**

- A REALITY handshake harness: a real Xray server behind layer4, a second Xray
  client through `:443`, a VLESS/Vision tunnel, and an inner HTTP request that
  must return the expected body with no `alert 40`.
- Outer-certificate masquerade assertions: an unauthenticated probe must
  receive the certificate of the chosen real destination, not the site's.
- PROXY v2 and negative-control assertions that fail closed on a wrong UUID,
  wrong publicKey, wrong shortId, wrong credential, or private target.
- Test-fixture guards that make the `:port, host:port` address shape and the
  `probe_resistance` ≠ target rule machine-checked rather than prose.
- Redacted evidence under `evidence/v0.5.0/`, produced from raw logs that were
  captured and then scrubbed, not from a narrative report.

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
- ✓ The verification slice is frozen as a reviewable commit: 26 offline items,
  8 coexistence items, and blocking CI — v0.4.3.
- ✓ Runtime-acceptance findings are closed or explicitly dispositioned; the
  `deploy/` freeze keeps its single amendment — v0.4.3.
- ✓ `v0.4.3` is published only after both suites are green, with four assets
  and redacted evidence that describe the downloaded release binary — release
  435420474.
- ✓ Both fork commits, the Caddy tag/commit and xcaddy are fixed in
  `pins/build-inputs.env`; a real CI build reproduced the published sha256 —
  commit `0ef98bb`, build run 42224616127.
- ✓ The published arm64 asset was executed on a real `ubuntu-24.04-arm`
  runner: 26 offline and 8 coexistence items passed — run 42228779590.
- ✓ Third-party licenses and SPDX identifiers are recorded, and the
  repository's all-rights-reserved default is explicit — commit `820b890`.

### Active

- [ ] `E2E-01` REALITY handshake is automated and fails closed without key
  material.
- [ ] `E2E-02` The outer certificate of a REALITY probe matches the real
  destination.
- [ ] `E2E-03` layer4 sends a well-formed PROXY v2 header to the upstream.
- [ ] `E2E-04` Wrong UUID, wrong publicKey, and wrong shortId cannot open a
  tunnel.
- [ ] `E2E-05` naive negative controls and the private-target ACL are asserted
  on body, upstream data, and the 403 log, not on a status code.
- [ ] `E2E-06` A non-443 test fixture must use `:port, host:port` and must
  pin `protocols h1 h2`.
- [ ] `E2E-07` The unknown/no-SNI fallback posture is decided and checked.
- [ ] `E2E-08` The harness survives 30 serial requests and 8 concurrent ones
  with zero errors.
- [ ] `EVID-01` Evidence for the E2E suite is captured, redacted, and indexed.
- [ ] `REL-01` A `v0.5.0` release happens only after explicit approval.

### Out of Scope

- HTTP/3 on `:443` — removed by the `protocols h1 h2` pin because one SNI with
  two transport identities on one port is the coexistence hazard this project
  avoids.
- Docker, a packaged distribution, BBR, or upstream cascades — outside the v4
  delivery shape.
- Public-internet HTTP/3 measurement — HTTP/3 is off by design.
- Real domains, credentials, UUIDs, or REALITY key material — placeholders only.
- Choosing an open-source license for the repository — that is the owner's
  decision; this slice records the existing all-rights-reserved default.

## Context

The v4 specification (`../my-caddy-v4-SPEC.md`) defines Sprints 1–7 with
acceptance criteria `S1`–`S12` and edge cases `E1`–`E13`. Those sprints are
delivered through tag `v0.4.2`. Milestone `v0.4.3` froze the verification slice
(26 offline items plus 8 coexistence items), closed the runtime-acceptance
findings, and published a tag whose assets and redacted evidence describe the
downloaded artifact. That milestone is archived under
`.planning/milestones/v0.4.3-phases/`.

The current work is milestone `v0.5.0`. A REALITY end-to-end round was already
run by hand against an isolated test stack on a separate machine: layer4
forwarded REALITY SNI traffic to Xray with PROXY v2, an Xray client opened a
VLESS/Vision tunnel, the outer certificate matched a real destination, and
wrong UUID / publicKey / shortId all failed. `docs/E2E-NAIVE-REALITY-2026-11-06.md`
records that round, its fixtures, and its limitations. It is a tested report,
not a production acceptance and not a substitute for raw captures.

The point of `v0.5.0` is therefore not to re-measure by hand. It is to make the
same assertions executable in this repository, so a future change to the
Caddyfile, the layer4 matcher, the forwardproxy fork, or the Xray config cannot
silently break the REALITY leg.

The v0.4.0 runtime acceptance round passed 12 of 21 items, failed 7, and left 2
untested. The disposition is recorded in
`.gate/PM-DISPOSITION-RUNTIME-ACCEPT.md`. Two findings still matter most:
REALITY's shipped placeholder `dest` was rejected by the destination, and
naive's `probe_resistance` target collided with the destination being proxied.
Both are now closed: the paired-replacement rule is documented and checked, and
CO-8 asserts the decoy is not the target.

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
- **Forks**: both non-core modules are read from the commits pinned in
  `pins/build-inputs.env`; branch names are not build inputs.
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
| Keep the `deploy/` freeze at one amendment | A second exception would weaken a supply-chain guard for a rule the docs already carry | ✓ Good — option A chosen 2026-11-05 |
| Verify offline first, then live | Config shape is cheap to check; only a live stack proves coexistence | ✓ Good |
| Treat Windows as authoring-only | The binary is a Linux ELF; runtime checks need Linux/root | ✓ Good |
| Pin both fork commits in one tracked file | A branch head changed the published binary with no commit here; a receipt is not a build input | ✓ Good — `0ef98bb` |
| Execute the released arm64 asset on an ARM runner | Artifact inspection is not execution; a real host is the only way to earn the claim | ✓ Good — run 42228779590 |
| Record licenses, keep the repository proprietary | The owner never selected an open-source license; granting rights silently would be irreversible | ✓ Good — `LicenseRef-Proprietary` |
| Turn the hand-run REALITY round into a repository test | A one-off measurement cannot catch a regression; the report is evidence of a state, not a guard | Pending — v0.5.0 |
| Keep the E2E stack on isolated ports | `:443` on the test host is occupied by production; the delivery address shape is replicated, not the delivery port | Pending — v0.5.0 |
| Fail closed when REALITY key material is absent | A skipped handshake test that reports PASS is worse than no test | Pending — v0.5.0 |

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
*Last updated: 2026-11-07 when milestone v0.5.0 started*
