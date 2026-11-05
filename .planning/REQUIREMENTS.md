# Requirements: my-caddy

**Defined:** 2026-11-05
**Core Value:** Three roles coexist on one binary, one Caddyfile, and one
`:443` without interference, and that claim is reproducible from evidence.

## v0.4.3 Requirements

Requirements for the first GSD-managed milestone. Each maps to exactly one
roadmap phase.

### Verification

- [ ] **VER-01**: `scripts/verify.sh` declares `EXPECTED_ITEMS=26` and emits
  exactly the 26 IDs in its explicit item set, once each, with no silent skip.
- [ ] **VER-02**: `S3-12` proves the `protocols h1 h2` pin at declaration level
  and in the adapted JSON, and fails when the line is removed.
- [ ] **VER-03**: `S3-13` proves the adapted `forward_proxy` keeps both
  `auth_credentials` and `probe_resistance`, and fails when either is removed.
- [ ] **VER-04**: `tests/coexist/run.sh` prints `COEXIST: PASS` with CO-1
  through CO-7 on a Linux host with root.
- [ ] **VER-05**: `.github/workflows/verify.yml` runs the offline and
  coexistence suites on push and pull request, and either failure is red.
- [ ] **VER-06**: `docs/VERIFY.md` and `docs/BUILD.md` describe the same item
  set the scripts execute, without claiming an unrun result.

### Runtime acceptance

- [ ] **RTA-01**: The REALITY default posture is decided: either the shipped
  placeholder pair is runnable, or the docs and checks require replacing
  `serverNames` and `dest` together before use.
- [ ] **RTA-02**: The `probe_resistance` target cannot silently equal the
  destination being proxied; the rule is documented and checked.
- [ ] **RTA-03**: Every `v0.4.0` runtime-acceptance FAIL has a disposition —
  fixed, documented as a limitation, or explicitly deferred.

### Release

- [ ] **REL-01**: The verification slice is committed on a reviewable branch
  and merged to `main` without rewriting published history.
- [ ] **REL-02**: `v0.4.3` is tagged only after both suites are green, and its
  artifacts, `SHA256SUMS`, `pins.txt`, and redacted evidence match the tag.

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
| Public-internet H3 measurement | HTTP/3 is off; measuring it would test nothing shipped. |
| Licence/SPDX conclusions | Not evidenced in this repository. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| VER-01 | Phase 1 | Pending |
| VER-02 | Phase 1 | Pending |
| VER-03 | Phase 1 | Pending |
| VER-04 | Phase 1 | Pending |
| VER-05 | Phase 1 | Pending |
| VER-06 | Phase 1 | Pending |
| RTA-01 | Phase 2 | Pending |
| RTA-02 | Phase 2 | Pending |
| RTA-03 | Phase 2 | Pending |
| REL-01 | Phase 3 | Pending |
| REL-02 | Phase 3 | Pending |

**Coverage:**

- v0.4.3 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-11-05*
*Last updated: 2026-11-05 after initialization*
