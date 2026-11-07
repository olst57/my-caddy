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

- [x] **Phase 4: REALITY E2E harness** (completed 2026-11-07) — Build `tests/e2e/` so a REALITY
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
**Plans**: 3/3 plans complete

Plans:
- [x] 04-01: Scaffold `tests/e2e/` from the coexist fixtures
- [x] 04-02: Implement the REALITY handshake, certificate, and PROXY v2 assertions
- [x] 04-03: Add the negative controls and the fail-closed key handling

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
**Plans**: 2/3 plans complete

Plans:
- [x] 05-01: Upgrade the naive and private-target assertions
- [x] 05-02: Add the fixture address and protocol guards
- [ ] 05-03: Decide and assert the unknown-SNI posture (baseline measured; awaiting owner decision)

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
| 4. REALITY E2E harness | 3/3 | Complete    | 2026-11-07 |
| 5. naive/ACL assertions and fixture guards | 2/3 | In progress — E2E-07 checkpoint | - |
| 6. Stability smoke, evidence, and release decision | 0/3 | Not started | - |

## Open Decision

**E2E-07 — unknown, empty, and absent SNI (baseline measured 2026-11-07).** On
the `hw-gz` test overlay, `unknown.test` and an absent SNI both failed the TLS
handshake with an internal-error alert; the empty-SNI case was rejected by the
client before a record was sent; all three produced a layer4 record delta of
zero. The current delivery file has no catch-all site, so the earlier claim
that an unmatched SNI receives the site certificate did not reproduce. This
changes the current state from "default certificate" to effectively "reject".
The posture is still undecided. The options are:

1. **reject** — keep the measured behaviour and make it explicit in the
   delivery file and the harness.
2. **decoy** — serve a dedicated decoy certificate and site for unmatched SNI.
3. **default** — add a catch-all site and serve the default/site certificate.

The Phase 5 baseline records the facts only. The plan stops at its blocking
checkpoint; no posture or delivery change is encoded until the owner answers.
