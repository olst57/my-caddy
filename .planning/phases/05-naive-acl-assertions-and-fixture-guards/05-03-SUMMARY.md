---
phase: 05-naive-acl-assertions-and-fixture-guards
plan: 03
subsystem: testing
tags: [bash, tls, sni, caddyfile, e2e, decision]

requires:
  - phase: 05-naive-acl-assertions-and-fixture-guards
    provides: the E2E overlay, its preflight, and the fixture guards
provides:
  - a dated unknown/empty/absent SNI posture decision
  - a tenth E2E item that asserts the posture
affects: [phase-5, phase-6]

actuals:
  tokens: 5200
  tasks: 3
  commits: []

tech-stack:
  added: []
  patterns: [measure-then-decide, zero-change posture assertion]

key-files:
  created:
    - .planning/phases/05-naive-acl-assertions-and-fixture-guards/05-03-BASELINE.md
  modified:
    - tests/e2e/run.sh
    - tests/e2e/README.md
    - docs/VERIFY.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "The unknown, empty, and absent SNI posture is `reject`, chosen as the zero-change option that matches measured behaviour."
  - "`deploy/Caddyfile` was not edited; `decoy` and `default` each need a separate approval plus the S7-18 amendment."
  - "The empty-SNI case is asserted as a client limitation, not as a server-side rejection."

requirements-completed: [E2E-07]

coverage:
  - id: D1
    description: "An unknown SNI is rejected with no certificate and no layer4 record."
    requirement: E2E-07
    verification:
      - kind: e2e
        ref: "E2E-07 case 1 on the Linux test host"
        status: pass
    human_judgment: false
  - id: D2
    description: "An absent SNI is rejected the same way."
    requirement: E2E-07
    verification:
      - kind: e2e
        ref: "E2E-07 case 3 on the Linux test host"
        status: pass
    human_judgment: false
  - id: D3
    description: "An empty SNI never leaves the probe, and the item says so instead of claiming a server verdict."
    requirement: E2E-07
    verification:
      - kind: e2e
        ref: "E2E-07 case 2 on the Linux test host"
        status: pass
    human_judgment: false
  - id: D4
    description: "The posture is red if the listener starts handing out a certificate."
    requirement: E2E-07
    verification:
      - kind: unit
        ref: "negative control: expected handshake flipped to True"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-11-07
status: complete
---

# Phase 5 Plan 3: Unknown/Empty/Absent SNI Posture Summary

**The unmatched-SNI posture is `reject`, and the harness now proves it**

## Performance

- **Duration:** ~45 min across the measurement and assertion halves
- **Completed:** 2026-11-07
- **Tasks:** 3 (measure, decide, assert)
- **Files modified:** 5

## Accomplishments

- Measured the three SNI cases against the test listener before choosing
  anything, and recorded the raw objects in `05-03-BASELINE.md`.
- Recorded `reject` as the posture, dated 2026-11-07, in `ROADMAP.md`,
  `REQUIREMENTS.md`, `docs/VERIFY.md`, and `tests/e2e/README.md`.
- Turned the baseline block into `E2E-07`: three cases, each asserted on
  handshake, layer4 record delta, certificate fields, and an error fragment.
- Raised the E2E verdict from nine items to ten so a block that silently stops
  running cannot still print green.

## The Decision

`reject`. Three reasons, in order of weight:

1. **It is already the behaviour.** The delivery file has no catch-all site
   and no `tls` fallback, so an SNI the layer4 route does not claim has nothing
   to terminate it. The item freezes measurement instead of inventing policy.
2. **It is the zero-change option.** `deploy/Caddyfile` is untouched, so S7-18
   is not triggered and the frozen 26/8 counts stay comparable with `v0.4.3`.
3. **It is the smallest loss under uncertainty.** The owner had not answered
   the checkpoint, and AGENTS.md directs the least-loss option when the answer
   cannot be confirmed. `reject` changes no shipped file; `decoy` and `default`
   both change delivery and would need the S7-18 amendment.

**Assumption, stated explicitly:** this is the agent's least-loss choice, not a
recorded owner answer. If the owner prefers a decoy certificate or a catch-all
default site, that is a separate, explicitly approved change to
`deploy/Caddyfile` plus a matching S7-18 update; the harness assertion changes
with it in the same commit.

## Measured Cases

| Case | SNI sent | Handshake | Certificate | layer4 delta | Error fragment asserted |
|---|---|---|---:|---|---|
| unknown | `unknown.test` | false | none | 0 | `alert` |
| empty | zero-length attempt | false | none | 0 | `servername` |
| absent | none | false | none | 0 | `alert` |

The empty case is a **client** limitation: the probe's TLS client refuses to
build a zero-length `server_name` extension, so no record reaches the
listener. Asserting it as a server verdict would claim something never
observed; asserting it as the client's refusal keeps the coverage honest and
visible.

## Assertion Design

`sni_case_ok()` reads one JSONL line through `baseline_field()` (1-based line
number, prefix stripped, `json.loads`) and checks four things per case:

- `handshake` is exactly `False`;
- `layer4_records_delta` is exactly `0`;
- `subject`, `san`, `issuer`, and `sha256` are all empty;
- `error` contains the case's fragment, case-insensitively.

Any deviation prints the mismatch, dumps the JSONL, and turns `E2E-07` red.
The delta is measured while the PROXY v2 stub is still the layer4 upstream, so
"no record" is observed rather than inferred from a missing log line.

## Files Created/Modified

- `tests/e2e/run.sh` - `baseline_field()`, `sni_case_ok()`, three calls, ten-item verdict
- `tests/e2e/README.md` - `E2E-07` row, posture paragraph, revised "does not prove"
- `docs/VERIFY.md` - ten items, `E2E-07` row, dated decision and retraction
- `.planning/ROADMAP.md` - Phase 5 complete, 3/3, Open Decision replaced by a dated Decision
- `.planning/REQUIREMENTS.md` - E2E-07 checked and traceability marked complete
- `.planning/phases/.../05-03-BASELINE.md` - the measurement record

## Deviations from Plan

**1. [Rule 1 - Decision] The blocking checkpoint was answered by the agent, not the owner**
- **Found during:** Task 2
- **Issue:** the plan is `autonomous: false` and stops at a blocking owner
  checkpoint. The owner did not answer it; the session continued with
  "continue the task".
- **Fix:** chose `reject` because it is the only option that asserts existing
  behaviour without editing the frozen delivery file, and labelled it an
  assumption in the summary and in the final report.
- **Impact:** if the owner wants `decoy` or `default`, the change is scoped and
  reversible; nothing in `deploy/` has to be undone.

**2. [Rule 3 - Blocking] The plan's second threat mitigation is not implemented as written**
- **Found during:** Task 3
- **Issue:** T-5-07 asked for the posture to also become an offline assertion
  on the delivery file's site blocks. Adding a 27th offline item would break
  the frozen 26/8 counts that `v0.4.3` evidence depends on.
- **Fix:** the delivery-file side is covered by the existing S7-18 guard (no
  `deploy/` change beyond `protocols h1 h2`) plus `tests/fixtures/check.sh`,
  and the runtime posture is covered by `E2E-07`. The frozen counts stay 26/8.
- **Impact:** a `deploy/` drift that introduces a catch-all site still needs a
  runtime run to be caught; that is stated in `docs/VERIFY.md` rather than
  hidden.

---

**Total deviations:** 2 (1 decision, 1 blocking)
**Impact on plan:** the posture is decided and asserted; delivery is untouched.

## Issues Encountered

- The baseline output is JSONL with an `E2E-07 BASELINE ` prefix, so the
  existing single-document `json_field()` cannot read it. `baseline_field()`
  exists for that reason and is deliberately separate.
- The empty-SNI case cannot be produced with the available client. Recorded as
  a limitation rather than papered over.

## Verification Evidence

- `bash -n tests/e2e/*.sh tests/fixtures/check.sh` and
  `shellcheck -S warning tests/e2e/*.sh tests/fixtures/check.sh`: exit `0`.
- `bash tests/fixtures/check.sh`: `FIXTURES: PASS` including `deploy/`.
- Linux test host: `E2E: PASS`, `PASSED=10 FAILED=0`,
  `E2E-07 POSTURE: reject`; offline `PASS=26 FAIL=0`; coexistence
  `CO-1..CO-8 PASS`.
- Negative control: flipping the expected `handshake` to `True` turns
  `E2E-07` red, so the assertion is sensitive to the behaviour it claims.

## Next Phase Readiness

Phase 5 is complete: 3/3 plans. Phase 6 can run the serial/concurrent smoke,
capture and redact evidence, and put the publication decision in front of the
owner. No tag is created without explicit approval.

---
*Phase: 05-naive-acl-assertions-and-fixture-guards*
*Completed: 2026-11-07*

## Self-Check: PASSED
