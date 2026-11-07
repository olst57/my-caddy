# Roadmap: my-caddy

## Overview

The delivery shape is unchanged: one Caddy binary, one Caddyfile, one `:443`,
three roles. Milestones `v0.4.2` and `v0.4.3` delivered that shape and froze the
verification gate (26 offline items, 8 coexistence items, CI enforcement,
tagged artifacts).

`v0.5.0` closes the last unproven leg. A REALITY round was already measured by
hand against an isolated test stack on 2026-11-06; it proved the handshake, the
masquerade certificate, PROXY v2, and the negative controls, but it left no
executable guard in the repository. This milestone converts that measurement
into `tests/e2e/`, decides the remaining posture questions, and archives
redacted evidence.

The milestone does not add a fourth role, does not move off `v2.11.7`, does not
reopen the HTTP/3 decision, and does not re-run by hand what is already
recorded. It also does not rewrite the `v0.4.3` tag, assets, or evidence.

## Milestones

- ✅ **v0.4.2 Delivery** (pre-GSD)
- ✅ **v0.4.3 Verification gate** (Phases 1–3, archived under
  `.planning/milestones/v0.4.3-phases/`)
- 🚧 **v0.5.0 REALITY closure and E2E regression harness** (Phases 4–6)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): planned milestone work
- Decimal phases (2.1, 2.2): urgent insertions

Phase numbers continue from the previous milestone: `v0.4.3` ended at Phase 3,
so `v0.5.0` starts at Phase 4.

- [ ] **Phase 4: REALITY E2E harness** — Build `tests/e2e/` so a REALITY
  handshake, the masquerade certificate, PROXY v2, and the three negative
  controls run as assertions on `hw-gz`.
- [ ] **Phase 5: naive/ACL assertions and fixture guards** — Upgrade the naive
  negative controls to body-and-log assertions, make the non-443 fixture shape
  machine-checked, and settle the unknown-SNI posture.
- [ ] **Phase 6: Stability smoke, evidence, and release decision** — Run the
  serial/concurrent smoke, capture and redact evidence, and decide whether to
  publish `v0.5.0`.

## Phase Details

### Phase 4: REALITY E2E harness
**Goal:** Make the REALITY leg executable in the repository, so a change to the
Caddyfile, the layer4 matcher, the forwardproxy fork, or the Xray config cannot
silently break it.
**Mode:** mvp
**Depends on:** Nothing (first phase of this milestone; `v0.4.3` is archived)
**Requirements**: E2E-01, E2E-02, E2E-03, E2E-04
**Success Criteria** (what must be TRUE):
  1. `bash tests/e2e/run.sh` on `hw-gz` starts a real Xray server and client,
     opens a VLESS/Vision tunnel through the Caddy listener, and returns the
     expected inner HTTP body with no `alert 40`.
  2. The unauthenticated probe certificate matches the configured real
     destination on SAN, issuer, validity window, and fingerprint, over TLS 1.3
     with ALPN `h2`.
  3. The layer4 upstream records a 28-byte PROXY v2 preamble with `0d0a0d0a`,
     `0x21`, and `0x11`, and the expected upstream address.
  4. A wrong UUID, a wrong publicKey, and a wrong shortId each fail to open a
     tunnel, and each failure is reported as its own assertion.
  5. With key material removed from the environment, the run exits non-zero
     before any handshake, and prints which variable is missing.
  6. No real key, UUID, shortId, host, or address is added to the tree.
**Plans**: 3 plans

Plans:
- [ ] 04-01: Scaffold `tests/e2e/` from the coexist fixtures
- [ ] 04-02: Implement the REALITY handshake, certificate, and PROXY v2 assertions
- [ ] 04-03: Add the negative controls and the fail-closed key handling

### Phase 5: naive/ACL assertions and fixture guards
**Goal:** Close the remaining assertion gaps the hand-run round exposed, and
make the fixture rules that cost time (F-01, F-02, F-03) machine-checked.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements**: E2E-05, E2E-06, E2E-07
**Success Criteria** (what must be TRUE):
  1. A missing or wrong naive credential reaches the decoy and produces no
     target data; the assertion reads the upstream byte count and the decoy
     body, not only the status code.
  2. A private target produces no upstream data and a 403 ACL log entry, and a
     regression that drops the ACL is red.
  3. A non-443 fixture address that is not written `:port, host:port` fails
     before the listener starts, and a fixture without an explicit
     `protocols h1 h2` fails the same way.
  4. The unknown-SNI and no-SNI posture is recorded as a decision and asserted
     by the suite.
**Plans**: 3 plans

Plans:
- [ ] 05-01: Upgrade the naive and private-target assertions
- [ ] 05-02: Add the fixture address and protocol guards
- [ ] 05-03: Decide and assert the unknown-SNI posture

### Phase 6: Stability smoke, evidence, and release decision
**Goal:** Show the harness is not a single lucky request, archive evidence that
matches the run, and put the release decision in front of the owner.
**Mode:** mvp
**Depends on:** Phase 5
**Requirements**: E2E-08, EVID-01, REL-01
**Success Criteria** (what must be TRUE):
  1. Thirty serial requests and eight concurrent requests through the same
     listener complete with zero errors, and the counts are printed.
  2. Raw logs and captures are stored locally under `.gate/`, then scrubbed and
     archived under `evidence/v0.5.0/` with an index entry in
     `evidence/README.md`.
  3. `scripts/verify.sh` still reports 26/26 and the coexistence suite still
     reports 8/8 after the harness is added.
  4. The release decision is written down; a tag is created only if the owner
     explicitly approves it.
**Plans**: 3 plans

Plans:
- [ ] 06-01: Run the serial and concurrent smoke
- [ ] 06-02: Capture, redact, and index the evidence
- [ ] 06-03: Re-run both existing suites and decide on publication

## Progress

**Execution Order:**
Phases execute in numeric order: 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. REALITY E2E harness | 0/3 | Not started | - |
| 5. naive/ACL assertions and fixture guards | 0/3 | Not started | - |
| 6. Stability smoke, evidence, and release decision | 0/3 | Not started | - |

## Open Decision

**E2E-07 — unknown-SNI and no-SNI fallback.** The hand-run round observed that
an unknown or absent SNI is answered with the site certificate
(`CN=<NAIVE_TEST_SNI>`), because the catch-all site is the last route. The
options are:

1. Keep the current default certificate (least change, weakest cover story).
2. Serve a dedicated decoy certificate and site for unmatched SNI.
3. Reject the handshake for unknown SNI.

This decision belongs to Phase 5. Until it is made, Phase 5 asserts the current
behaviour as a recorded baseline rather than as a desired posture, and the plan
stops if the assertion would have to encode a posture the owner has not chosen.
