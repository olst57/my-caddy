---
phase: 04-reality-e2e-harness
verified: 2026-11-07T04:11:35Z
status: passed
score: 6/6 must-haves verified
behavior_unverified: 0
---

# Phase 4: REALITY E2E Harness Verification Report

**Phase Goal:** Make the REALITY leg executable in the repository, so a change
to the Caddyfile, the layer4 matcher, the forwardproxy fork, or the Xray config
cannot silently break it.
**Verified:** 2026-11-07T04:11:35Z
**Status:** passed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A real Xray server and client open a VLESS/Vision tunnel through the Caddy listener and return the inner marker. | ✓ VERIFIED | `E2E-01 PASS`; body `E2E-INNER-MARKER`, header `X-Site: e2e-inner`. |
| 2 | An unauthenticated probe receives the live destination certificate over TLS 1.3 and ALPN `h2`. | ✓ VERIFIED | `E2E-02 PASS`; SAN, issuer, validity and leaf sha256 matched against three live destination fetches. |
| 3 | The layer4 upstream receives a structurally valid PROXY v2 header. | ✓ VERIFIED | `E2E-03 PASS`; signature `0d0a0d0a000d0a515549540a`, `0x21`, `0x11`, 12-byte IPv4 block, destination `127.0.0.1:8443`, ClientHello and SNI present. |
| 4 | Wrong UUID, publicKey and shortId each fail to open a tunnel as separate assertions. | ✓ VERIFIED | `E2E-04a`, `E2E-04b`, `E2E-04c` all PASS; each control changed exactly one field. |
| 5 | Missing key material fails before a handshake and names the missing variable. | ✓ VERIFIED | `--negative-preflight` 12/12 PASS, including empty and partial key sets; no listener starts. |
| 6 | No real key, UUID, shortId, host or address is added to the tree. | ✓ VERIFIED | `scripts/verify.sh` S7-12 and S7-13 PASS on the pushed commit; test templates use `<E2E_*>` only. |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/e2e/run.sh` | fail-closed stack and six items | ✓ EXISTS + SUBSTANTIVE | 700 lines; preflight, overlay reverse-diff, positive and negative items. |
| `tests/e2e/lib.sh` | shared helpers | ✓ EXISTS + SUBSTANTIVE | item, process, port, JSONL and environment helpers. |
| `tests/e2e/negative-controls.sh` | one-field mutations | ✓ EXISTS + SUBSTANTIVE | Asserts exactly one removed and one added line per control. |
| `tests/e2e/xray-server.tpl.json` | REALITY server template | ✓ EXISTS + SUBSTANTIVE | No stored values; test-only loopback allow. |
| `tests/e2e/xray-client.tpl.json` | one-outbound client template | ✓ EXISTS + SUBSTANTIVE | SOCKS inbound plus one VLESS/Vision outbound. |
| `tests/e2e/probe-cert.py` | live certificate comparison | ✓ EXISTS + SUBSTANTIVE | TLS 1.3, ALPN, SAN, issuer, dates, leaf sha256. |
| `tests/e2e/proxyv2.py` | PROXY v2 field parser | ✓ EXISTS + SUBSTANTIVE | Signature, command, family, address block and ClientHello. |
| `.github/workflows/verify.yml` | syntax-only CI coverage | ✓ EXISTS + SUBSTANTIVE | shellcheck, `bash -n`, `py_compile`, negative preflight. |

**Artifacts:** 8/8 verified

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `deploy/Caddyfile` | harness overlay | literal replacement and reverse diff | ✓ WIRED | Reverse diff byte-empty before startup. |
| Xray client | Caddy `:8443` | SOCKS plus one VLESS/Vision outbound | ✓ WIRED | E2E-01 returned the inner marker. |
| layer4 | Xray server `127.0.0.1:19099` | PROXY v2 plus `acceptProxyProtocol` | ✓ WIRED | E2E-03 parsed the header and ClientHello. |
| probe | REALITY listener | TLS 1.3 with SNI and ALPN `h2` | ✓ WIRED | E2E-02 compared the live certificate. |
| CI | fail-closed preflight | `--negative-preflight` | ✓ WIRED | CI `verify` run 42337117568 concluded success. |

**Wiring:** 5/5 connections verified

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| E2E-01: real tunnel returns the expected inner response | ✓ SATISFIED | - |
| E2E-02: live destination certificate over TLS 1.3 and h2 | ✓ SATISFIED | - |
| E2E-03: well-formed PROXY v2 header | ✓ SATISFIED | - |
| E2E-04: three credential negative controls | ✓ SATISFIED | - |

**Coverage:** 4/4 requirements satisfied

## Anti-Patterns Found

None. The harness has no skip path, the negative controls assert a one-field
diff, and CI executes only syntax and fail-closed preflight checks.

## Human Verification Required

None. The hand-run measurement was converted into automated assertions; the
execution evidence is in the ignored `.gate/v050/e2e-run5/` archive.

## Gaps Summary

**No gaps found.** Phase goal achieved. The production certificate chain,
long soak and unknown-SNI posture remain explicitly out of scope for Phase 4
and belong to later phases.

## Verification Metadata

**Verification approach:** Goal-backward, based on the Phase 4 success criteria.
**Must-haves source:** `04-01-PLAN.md`, `04-02-PLAN.md`, `04-03-PLAN.md`.
**Automated checks:** Full default harness `E2E: PASS`; 26/26 offline;
8/8 coexistence; CI `gate0` and `verify` success.
**Human checks required:** 0.
**Total verification time:** one test session plus CI.

---
*Verified: 2026-11-07T04:11:35Z*
*Verifier: the agent, with Linux-host execution*
