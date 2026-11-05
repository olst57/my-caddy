---
phase: 02-close-runtime-acceptance
plan: 01
subsystem: docs
tags: [reality, placeholders, alert-40]

requires:
  - phase: 01
    plan: 03
    provides: the frozen gate and its green CI

provides:
  - REALITY posture recorded as mandatory paired replacement
  - alert-40 measurement attributed to the v0.4.0 acceptance run

affects:
  - phase-02 plan 02
  - phase-03

actuals:
  tokens: 0
  tasks: 2
  commits: 1

tech-stack:
  added: []
  patterns:
    - "A placeholder that spans three files is documented as one atomic replacement"

key-files:
  created: []
  modified:
    - docs/XRAY.md
    - docs/VERIFY.md

key-decisions:
  - "option-a: keep the placeholder pair and make the replacement mandatory."
  - "The deploy/PLACEHOLDERS.md row is deferred because S7-18 freezes deploy/."

patterns-established:
  - "A configuration that validates but fails at connection time is documented as a measurement, not a PASS."

requirements-completed: [RTA-01]

coverage:
  - id: D1
    description: "The posture is stated in the deployment-facing docs"
    requirement: "RTA-01"
    verification:
      - kind: other
        ref: "docs/XRAY.md REALITY preflight section"
        status: pass
    human_judgment: false
  - id: D2
    description: "No doc claims the placeholder pair was accepted"
    requirement: "RTA-01"
    verification:
      - kind: other
        ref: "docs/VERIFY.md The REALITY default pair is a placeholder pair"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-11-05
status: complete
---

# Phase 2: Close Runtime Acceptance — Plan 01 Summary

The REALITY skeleton stays a placeholder, and the replacement rule is now
stated where a deployer will hit it.

## Performance

- **Duration:** 20 min
- **Started:** 2026-11-05
- **Completed:** 2026-11-05
- **Tasks:** 1 decision (option-a) + 2 documentation tasks, one deferred

## Decision

`option-a`: keep the placeholder pair and require a paired replacement. The
user selected it directly.

## What Landed

- `docs/XRAY.md` gained a `## REALITY preflight` section: the v0.4.0 `alert 40`
  measurement, the three `b.test` positions that must change together, and the
  separate rule for `realitySettings.dest`.
- `docs/VERIFY.md` gained `### The REALITY default pair is a placeholder pair`:
  the pair is not runnable, one measured topology is not a general PASS, and a
  handshake against the replacement destination is the precondition.
- A stale field-position row was corrected from `deploy/Caddyfile:32` to `:50`;
  the matcher has been on line 50 since the protocol-pin commit.

## Deferred, With Reason

The plan asks for a matching row in `deploy/PLACEHOLDERS.md`. That file is
inside the frozen `deploy/` tree, and item S7-18 permits exactly one amendment
there (`protocols h1 h2`). Editing the register turned S7-18 red:

```
ITEM S7-18 FAIL
deploy/ delta removes ... / differs in files other than deploy/Caddyfile
```

The edit was reverted and `VERIFY: PASS 26/26` was restored. Extending the
register therefore needs a decision about the freeze itself, which is recorded
in `STATE.md` as the current blocker.

**Resolution (assumption, not a user reply):** option A was applied, because
it is the least-loss branch — it changes nothing in the frozen tree and keeps
the supply-chain guard at exactly one amendment. The rule lives in
`docs/XRAY.md` and `docs/VERIFY.md`, which a deployer reads before touching
`deploy/`. The missing register row is recorded here as a documented deviation.
If the register must carry the rule, that is option B and it needs a decision
plus a `scripts/verify.sh` change.

## Verification

- `hw-gz`: `bash scripts/verify.sh` → `PASS=26 FAIL=0`, `VERIFY: PASS`,
  including `ITEM S7-18 PASS` after the revert.
- CI run
  [42054615674](https://github.com/olst57/my-caddy/actions/runs/42054615674)
  on `d3b4f67`: `offline` success.

## Next Phase Readiness

- The remaining register row and the freeze question are one decision.
- 02-02's code and documentation changes are independent of that row.
