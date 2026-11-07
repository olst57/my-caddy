---
phase: 05-naive-acl-assertions-and-fixture-guards
plan: 03
status: checkpoint-pending
measured: 2026-11-07
---

# Phase 5 Plan 3: Unknown/Empty/Absent SNI Baseline

This is a measurement, not a posture decision. It records what the current
fixture does before the owner chooses what it should do.

## Measured Cases

| Case | SNI sent | Handshake | Certificate | layer4 delta | Observation |
|---|---|---|---|---:|---|
| unknown | `unknown.test` | false | none | 0 | TLS internal-error alert |
| empty | zero-length attempt | false | none | 0 | client refused to build the extension; no record left the probe |
| absent | none | false | none | 0 | TLS internal-error alert |

The empty case is a client limitation, not evidence that the listener rejects
a valid empty-SNI ClientHello. The probe records it explicitly rather than
turning it into a server-side claim.

## What Changed From The Previous Assumption

The roadmap previously said an unknown or absent SNI was answered with the
site certificate because a catch-all site was last. The current delivery file
and its test overlay have no catch-all site. On the `hw-gz` fixture, both
cases failed the handshake and neither reached the layer4 upstream. That is a
reject-like baseline, not a default-certificate baseline.

## Final Run

- `E2E: PASS`
- `PASSED=9`, `FAILED=0`
- opening and closing positive controls passed; the closing control's first
  attempt returned an empty reply and its retry passed
- offline gate `PASS=26 FAIL=0`
- coexistence `CO-1..CO-8 PASS`
- CI `gate0` and `verify` both concluded success on `fbc1a2f`:
  <https://github.com/olst57/my-caddy/actions/runs/42347099461> and
  <https://github.com/olst57/my-caddy/actions/runs/42347099453>

An earlier run also reached nine passing items but the closing control got an
empty reply after the backend had answered. That failed run is retained in
`.gate/v050/p5-final5-evidence.tgz`; the harness now clears per-attempt output
files and retries the opening and closing controls three times.

## Awaiting Decision

The owner must choose one posture:

1. `reject` — keep the measured reject-like behavior and make it explicit.
2. `decoy` — serve a dedicated decoy certificate and site for unmatched SNI.
3. `default` — add a catch-all site and serve the default/site certificate.

Until that answer, this plan does not add an `E2E-07` pass/fail assertion and
does not change `deploy/Caddyfile`.

Evidence archive:
`p5-final6-evidence.tgz` sha256
`7ecda0beafb8c014bce50fd4f2f432e759b244bcb7c72d3cedbaae3bf3d027fd`.
