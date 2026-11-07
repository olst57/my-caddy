# Requirements: my-caddy

**Defined:** 2026-11-05
**Core Value:** Three roles coexist on one binary, one Caddyfile, and one
`:443` without interference, and that claim is reproducible from evidence.

## v0.5.0 Requirements

Requirements for milestone `v0.5.0`. Each maps to exactly one roadmap phase.
The milestone exists because a REALITY round was measured by hand and produced
no executable guard; these requirements convert that measurement into tests.

### REALITY end-to-end

- [x] **E2E-01**: `tests/e2e/` starts a real Xray server behind layer4 and a
  second Xray client that reaches it through the Caddy `:443` listener, opens a
  VLESS/Vision tunnel, and gets the expected inner HTTP response with no
  `alert 40`. Key material is generated at run time or injected from the
  environment; a missing value fails the run instead of skipping it.
- [x] **E2E-02**: An unauthenticated probe receives the outer certificate of
  the configured real destination — same SAN, issuer, validity window, and
  fingerprint — over TLS 1.3 with ALPN `h2`, not the site certificate.
- [x] **E2E-03**: The layer4 upstream receives a well-formed PROXY v2 header:
  28-byte preamble, `0d0a0d0a` signature, version/command `0x21`, family
  `0x11`, and the expected upstream address.
- [x] **E2E-04**: A wrong UUID, a wrong publicKey, and a wrong shortId each
  fail to open a tunnel, and the failure is asserted rather than tolerated.

### naive, ACL, and fixture guards

- [ ] **E2E-05**: A missing or wrong naive credential reaches the decoy with no
  target data, and a private target is asserted as "no upstream bytes plus a
  403 ACL log entry" — never on the status code alone.
- [ ] **E2E-06**: Any non-443 fixture address is written `:port, host:port`
  with an explicit `protocols h1 h2`, and a fixture that violates either rule
  fails before the test runs.
- [ ] **E2E-07**: The unknown-SNI and no-SNI fallback posture is decided
  (reject, decoy, or default certificate) and asserted.

### Stability and evidence

- [ ] **E2E-08**: The harness completes 30 serial and 8 concurrent requests
  through the same listener with zero errors.
- [ ] **EVID-01**: Raw logs from the harness run are captured, scrubbed with
  `scripts/redact-evidence.sh`, archived under `evidence/v0.5.0/`, and linked
  from `evidence/README.md`; no real key, UUID, host, or address is tracked.
- [ ] **REL-01**: A `v0.5.0` tag and release happen only after both suites are
  green on the tagged commit and the owner approves publication.

## Validated Requirements

Capabilities already present in the repository and observed through prior
evidence. They are locked unless a later phase explicitly reopens them.

### Coexistence

- [x] **CORE-01**: One Caddy binary serves website, naiveproxy, and REALITY on
  one `:443` listener — existing, v0.4.2.
- [x] **CORE-02**: The delivery shape is one Caddyfile; probes are separate
  files and are not imported — existing.

### Build

- [x] **BUILD-01**: A clean clone plus exactly one patch and `--replace`
  compiles — existing, Gate 0.
- [x] **BUILD-02**: The binary asserts four modules — existing, v0.4.2.
- [x] **BUILD-03**: amd64 and arm64 artifacts plus `SHA256SUMS` and `pins.txt`
  are produced — existing, v0.4.2.
- [x] **BUILD-04**: `pins.txt` records the actual source commits, xcaddy
  version, Go version, and patch — existing, v0.4.2.

### Configuration

- [x] **CONFIG-01**: `caddy validate` and `caddy adapt` accept the delivery
  Caddyfile — existing, v0.2.1 onward.
- [x] **CONFIG-02**: `forward_proxy` precedes `reverse_proxy`; `layer4`
  precedes `tls` — existing.
- [x] **CONFIG-03**: `protocols h1 h2` keeps the QUIC listener off `:443` —
  existing, `feat/protocol-pin`.

### Runtime roles

- [x] **NAIVE-01**: A credentialled CONNECT opens a real tunnel — existing,
  Sprint 4.
- [x] **NAIVE-02**: Missing or wrong credentials do not open a tunnel —
  existing, Sprint 4.
- [x] **NAIVE-03**: Under `probe_resistance`, an unauthenticated CONNECT is not
  answered `407` — existing, `PM-DISPOSITION-407`.
- [x] **REALITY-01**: REALITY traffic reaches `127.0.0.1:19098` by SNI without
  local TLS termination — existing, Sprint 5.
- [x] **REALITY-02**: PROXY v2 works only when both sides enable it — existing,
  Gate 0.
- [x] **REALITY-03**: A REALITY client completes a VLESS/Vision tunnel through
  `:443` against a real destination, and wrong UUID / publicKey / shortId fail
  — measured 2026-11-06 on an isolated test stack
  (`docs/E2E-NAIVE-REALITY-2026-11-06.md`); not yet automated.

### Hygiene

- [x] **HYGIENE-01**: No real secret, UUID, domain, or host name is tracked —
  existing, Sprint 7.
- [x] **HYGIENE-02**: Every placeholder is registered in
  `deploy/PLACEHOLDERS.md` — existing.
- [x] **HYGIENE-03**: Evidence can be redacted with
  `scripts/redact-evidence.sh` — existing, Sprint 7.

## Out of Scope

| Feature | Reason |
|---------|--------|
| HTTP/3 on `:443` | The protocol pin removes the QUIC listener by design. |
| arm64 runtime execution | Artifact verification only; no arm64 run is claimed. |
| Docker or a packaged distribution | Outside the v4 delivery shape. |
| BBR, upstream cascades | Explicitly excluded by the v4 spec red lines. |
| HTTP/3 on production `:443` | A separate change with its own risk; the test stack must not enable it silently. |
| Long-soak, DPI, and active-probing campaigns | Out of the milestone budget; the harness covers a smoke level only. |
| Real domains, real credentials, real key material in the tree | The repository stays placeholder-only; runtime generation or environment injection. |
| arm64 execution of `v0.5.0` | Artifact verification only, unless a run is explicitly scheduled. |
| Public-internet H3 measurement | HTTP/3 is off; measuring it would test nothing shipped. |
| Licence/SPDX conclusions | Not evidenced in this repository. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| E2E-01 | Phase 4 | Complete |
| E2E-02 | Phase 4 | Complete |
| E2E-03 | Phase 4 | Complete |
| E2E-04 | Phase 4 | Complete |
| E2E-05 | Phase 5 | Pending |
| E2E-06 | Phase 5 | Pending |
| E2E-07 | Phase 5 | Pending |
| E2E-08 | Phase 6 | Pending |
| EVID-01 | Phase 6 | Pending |
| REL-01 | Phase 6 | Pending |

**Coverage:**

- v0.5.0 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0

---
*Requirements defined: 2026-11-07*
*Last updated: 2026-11-07 for milestone v0.5.0*
