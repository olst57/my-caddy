---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Codebase Structure

**Analysis Date:** 2026-11-05

## Directory Layout

```text
my-caddy/
├── README.md                  # public entry: provenance, build, roles, limits
├── AGENTS.md                  # Codex/GSD project instructions
├── .planning/                 # GSD project management and codebase map
├── .codex/                    # project-local GSD runtime and standard skills
├── deploy/
│   ├── Caddyfile              # delivery posture with placeholders
│   ├── PLACEHOLDERS.md        # register of tokens to replace
│   └── xray/config.json       # REALITY inbound on 127.0.0.1:19098
├── docs/
│   ├── BUILD.md               # how the binary is produced
│   ├── VERIFY.md              # offline checks and runtime observations
│   ├── XRAY.md                # xray side of the topology
│   └── REDACTION.md           # evidence redaction rules
├── scripts/
│   ├── build.sh               # reproducible build
│   ├── verify.sh              # 26-item offline verifier
│   └── redact-evidence.sh     # evidence redaction
├── patches/
│   └── caddy-read-idle-timeout.patch
├── tests/
│   ├── probes/                # Gate 0 probes and helpers
│   └── coexist/               # live three-role suite
├── .github/workflows/
│   ├── build.yml
│   ├── gate0.yml
│   └── verify.yml
├── evidence/                  # redacted evidence index
├── .gate/                     # historical gate reports (gitignored)
├── dist/                      # build outputs (gitignored)
└── .build/                    # build scratch (gitignored)
```

## Key Locations

- **Delivery shape:** `deploy/Caddyfile`.
- **Offline assertions:** `scripts/verify.sh`.
- **Runtime assertions:** `tests/coexist/run.sh`.
- **Build inputs and pins:** `scripts/build.sh`, `dist/pins.txt`.
- **Known runtime findings:** `.gate/PM-DISPOSITION-RUNTIME-ACCEPT.md`.
- **Current project position:** `.planning/STATE.md`.

## Naming Conventions

- Gate 0 probes: `gate-a1.sh`, `gate-a1c.sh`, `gate-a2.sh`, `gate-a3.sh`,
  `gate-build.sh`.
- Offline items: `S3-*` for configuration, `S7-*` for hygiene.
- Runtime items: `CO-1` through `CO-7`.
- Releases: `v0.4.0`, `v0.4.1`, `v0.4.2`; next is `v0.4.3`.
- Evidence files: host or round prefix plus the item ID, for example
  `SP4B-D2.txt`, `RTA-5-verify.log`.

## Module Boundaries

- `build.sh` produces artifacts; it does not start a server.
- `verify.sh` reads configs and the binary; it does not bind a listener.
- `tests/coexist/run.sh` owns the live stack and all port binding.
- `tests/probes/` is historical Gate 0 material, not the delivery harness.
- `deploy/` is the delivery posture; `tests/` must not import it by copy.

## Where to Add Things

- A new offline assertion: add an item to `scripts/verify.sh`, update
  `EXPECTED_ITEMS`, the explicit ID set, and `docs/VERIFY.md`.
- A new runtime assertion: add a `CO-*` item to `tests/coexist/run.sh` and the
  CI log list.
- A new build input: add it to `scripts/build.sh` and `dist/pins.txt`.
- A new placeholder: add it to `deploy/PLACEHOLDERS.md` and the relevant config.

<!-- refreshed: 2026-11-05 -->
