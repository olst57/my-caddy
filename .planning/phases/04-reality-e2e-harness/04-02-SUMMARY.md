---
phase: 04-reality-e2e-harness
plan: 02
subsystem: testing
tags: [bash, python3, xray, reality, vless, vision, proxy-v2, tls, e2e]

requires:
  - phase: 04-reality-e2e-harness
    provides: reusable fixture layout and fail-closed preflight
provides:
  - executable REALITY tunnel assertion
  - live destination-certificate comparison
  - structural PROXY v2 assertion
affects: [phase-5, phase-6]

actuals:
  tokens: 5200
  tasks: 4
  commits: [2fb3e97]

tech-stack:
  added: [Xray 26.10.29, Caddy layer4, VLESS/Vision, REALITY, PROXY v2]
  patterns: [live certificate comparison, field-by-field proxy parser, test-only loopback allow]

key-files:
  created:
    - tests/e2e/xray-server.tpl.json
    - tests/e2e/xray-client.tpl.json
    - tests/e2e/probe-cert.py
    - tests/e2e/proxyv2.py
  modified:
    - tests/e2e/run.sh
    - tests/e2e/README.md
    - docs/VERIFY.md

key-decisions:
  - "The Xray server template allows only TCP to the fixture loopback target; REALITY fallback remains independent of the freedom outbound."
  - "The certificate comparison fetches the destination live three times and accepts a leaf fingerprint that matches any one fetch, while requiring every SAN, issuer and validity field to agree."
  - "PROXY v2 destination is the address the client dialled, not the loopback upstream; the measured value is `127.0.0.1:8443`."

patterns-established:
  - "Positive tunnel evidence is a body marker plus a response header, not a status code alone."
  - "Certificate identity is measured against the same destination in the same run."
  - "PROXY v2 is parsed as a structure; no assertion relies on a byte count alone."

requirements-completed: [E2E-01, E2E-02, E2E-03]

coverage:
  - id: D1
    description: "A VLESS/Vision request through the Caddy listener returns the inner target marker."
    requirement: E2E-01
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-01"
        status: pass
    human_judgment: false
  - id: D2
    description: "The listener presents the live destination certificate over TLS 1.3 with ALPN h2."
    requirement: E2E-02
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-02"
        status: pass
    human_judgment: false
  - id: D3
    description: "The layer4 upstream receives a structurally valid PROXY v2 header before the ClientHello."
    requirement: E2E-03
    verification:
      - kind: e2e
        ref: "bash tests/e2e/run.sh#E2E-03"
        status: pass
    human_judgment: false

duration: 60min
completed: 2026-11-07
status: complete
---

# Phase 4 Plan 2: REALITY, Certificate and PROXY v2 Assertions Summary

**A real Xray client reaches an inner HTTP marker through VLESS/Vision, sees the live destination certificate, and leaves a parseable PROXY v2 header**

## Performance

- **Duration:** ~60 min (shared session; not separately instrumented)
- **Completed:** 2026-11-07
- **Tasks:** 4
- **Files modified:** 7

## Accomplishments

- Added environment-rendered Xray server and client templates with no stored key values.
- Added `probe-cert.py` to fetch and compare SAN, issuer, validity and leaf fingerprint against a live destination.
- Added `proxyv2.py` to parse signature, version/command, family/protocol, address block and ClientHello.
- Ran `E2E-01`, `E2E-02` and `E2E-03` successfully on the Linux test host with the published Caddy build and Xray 26.10.29.

## Files Created/Modified

- `tests/e2e/xray-server.tpl.json` - REALITY inbound, test-only loopback allow rule
- `tests/e2e/xray-client.tpl.json` - one SOCKS inbound and one VLESS/Vision outbound
- `tests/e2e/probe-cert.py` - live certificate fetch and field comparison
- `tests/e2e/proxyv2.py` - PROXY v2 parser and ClientHello check
- `tests/e2e/run.sh` - stack startup and E2E-01..03 items
- `tests/e2e/README.md` - fixture behavior and limits
- `docs/VERIFY.md` - recorded run and evidence posture

## Decisions Made

- `finalRules` is scoped to the fixture loopback target. Xray 26 otherwise classifies a loopback destination as private and blackholes it before the inner request is exercised.
- The certificate probe requires TLS 1.3 and `h2` on the listener, and compares against three live destination fetches to tolerate normal edge-certificate rotation without accepting a different identity.
- The E2E-03 destination assertion uses the measured dialled address `127.0.0.1:8443`; the layer4 upstream port is not what caddy-l4 writes into the PROXY v2 block.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's `@@TOKEN@@` placeholder form would trip the repository hygiene gate**
- **Found during:** Task 1
- **Issue:** The delivery hygiene scan treats a `privateKey` value not beginning with `<` as credential-shaped, so `@@TOKEN@@` could not be used safely.
- **Fix:** Used `<E2E_*>` placeholders and added a render-time check that no placeholder survives.
- **Files modified:** `tests/e2e/xray-server.tpl.json`, `tests/e2e/xray-client.tpl.json`, `tests/e2e/run.sh`
- **Verification:** Rendered JSON parses; `--negative-preflight` passes; the committed tree passes the 26-item verifier.
- **Committed in:** `2fb3e97`

**2. [Rule 3 - Blocking] Xray 26 blackholed the loopback inner target**
- **Found during:** First full run on the Linux host
- **Issue:** `proxy/freedom` rejected `tcp:127.0.0.1:18080` as a private destination, so E2E-01 timed out while E2E-02 and E2E-03 already passed.
- **Fix:** Added a test-only `finalRules` allow for TCP to `127.0.0.1/8` port `18080`; the rule is documented as fixture-only in `tests/e2e/README.md`.
- **Files modified:** `tests/e2e/xray-server.tpl.json`, `tests/e2e/README.md`
- **Verification:** `E2E-01 PASS` with the marker and `X-Site: e2e-inner`.
- **Committed in:** `2fb3e97`

**3. [Rule 1 - Bug] The PROXY v2 destination is not the upstream port**
- **Found during:** E2E-03 measurement
- **Issue:** The plan expected the upstream address, but caddy-l4 writes the address the client dialled.
- **Fix:** Defaulted the assertion to `127.0.0.1:8443` with `E2E_PROXYV2_DEST` as an override and documented the measurement.
- **Files modified:** `tests/e2e/run.sh`, `tests/e2e/README.md`
- **Verification:** PROXY signature, `0x21`, `0x11`, address length 12, destination, ClientHello and SNI all pass.
- **Committed in:** `2fb3e97`

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All three were necessary to make the positive REALITY assertions executable and attributable; no production configuration or deploy/ file changed.

## Issues Encountered

The first full run reached 2/6: E2E-02 and E2E-03 passed, E2E-01 was blocked by the Xray private-target policy, and the negative controls could not be attributed because the positive control was failing. The loopback allow and the control-timeout work in plan 3 resolved the sequence.

## User Setup Required

None beyond the documented uploaded binaries and the external destination whose certificate covers the chosen SNI.

## Next Phase Readiness

The positive REALITY path is now executable. Plan 3 can add the three credential mutations and the per-variable fail-closed controls on top of a passing baseline.

---
*Phase: 04-reality-e2e-harness*
*Completed: 2026-11-07*

## Self-Check: PASSED
