<!-- GSD:project-start source:PROJECT.md -->

## Project

**my-caddy**

`my-caddy` builds one self-hosted Caddy binary and one delivery Caddyfile that
serve three roles on the same `:443` listener: a website reverse proxy, an
in-process naive proxy, and REALITY+Vision passthrough to Xray over layer4.
The repository is both a delivery kit and a testbed for the Qoder agent-team
workflow, so every behavioural claim must be backed by a command, an artifact,
or a recorded run.

The three roles are deliberately not three deployments. They share one binary,
one Caddyfile, and one port. The project exists to prove that this coexistence
is real, not merely configured.

**Core Value:** Three roles — website, naiveproxy, and REALITY+Vision — coexist on one binary,
one Caddyfile, and one `:443` without interfering with each other, and that
claim is reproducible from evidence.

### Constraints

- **Single listener**: one `:443`; do not split roles onto additional ports.
- **Single Caddyfile**: the delivery shape is one file; probes must not be
  imported into it.
- **Caddy baseline**: `v2.11.7`; the patch and the four module assertions are
  stated against that tag.
- **One patch**: exactly one `.patch` under `patches/`; a second fails the build.
- **Forks**: both non-core modules are read from the commits pinned in
  `pins/build-inputs.env`; branch names are not build inputs.
- **Build flag**: `--replace` is mandatory with the patch; either alone does not
  compile.
- **Protocol pin**: `protocols h1 h2` must stay explicit; absence restores
  `h1 h2 h3`.
- **Handler order**: `forward_proxy` before `reverse_proxy`; `layer4` before
  `tls`.
- **No site-level `basic_auth`**: naive authenticates the CONNECT itself.
- **No `forward_proxy` upstream**: it silently disables the ACL and ports
  defaults.
- **Secrets**: no real domain, IP, host name, credential, UUID, or REALITY key.
- **Evidence**: a claim without a command and its output is not a result.

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Caddyfile — delivery and probe configuration under `deploy/` and `tests/probes/`.
- Bash — build, verification, probes, and the coexistence harness in `scripts/` and `tests/`.
- JSON — Xray configuration (`deploy/xray/config.json`) and adapted Caddy JSON.
- Python 3 — test-only helpers under `tests/coexist/`.
- Go — not authored here; the binary is assembled from pinned upstream and forked modules.
- YAML — GitHub Actions workflows under `.github/workflows/`.

## Runtime
- Linux `amd64` for execution and runtime tests on `hw-gz` and CI.
- Linux `arm64` for execution of the published asset on `ubuntu-24.04-arm`;
- Windows is authoring-only: it can edit files and run Git, but cannot execute the Linux ELF.
- Go modules for the upstream and forked Caddy modules.
- No `package.json`, lockfile, or Node runtime is required by the project itself.

## Frameworks

- Caddy `v2.11.7` — HTTP server, TLS, reverse proxy, and listener wrapper host.
- `github.com/olst57/forwardproxy` at the commit pinned in `pins/build-inputs.env` — naive forward proxy module.
- `github.com/olst57/caddy-l4` at the commit pinned in `pins/build-inputs.env` — layer4 routing.
- Xray — REALITY inbound on `127.0.0.1:19098`.
- `scripts/verify.sh` — 26-item offline verifier; no listener bind.
- `tests/coexist/run.sh` — 8-item live coexistence suite; binds `:443`.
- `tests/probes/*.sh` — Gate 0 probes.
- `xcaddy` `v0.4.7` — pinned in `pins/build-inputs.env`.
- Go `1.26.9` — pinned in `pins/build-inputs.env` and recorded in `dist/pins.txt`.
- `jq` — offline JSON assertions.
- `curl`, `openssl`, `python3`, `iproute2` — coexistence suite.

## Key Dependencies

- Caddy `v2.11.7` — the baseline the patch and four module assertions target.
- `forwardproxy` at the pinned commit — calls `caddyhttp.IdleTimeoutsFromContext`, absent in Caddy `v2.11.7`.
- `caddy-l4` at the pinned commit — provides `layer4.handlers.proxy`, `caddy.listeners.layer4`, and `layer4.matchers.quic`.
- `caddy-read-idle-timeout.patch` — adds the missing symbol; exactly one patch is allowed.
- `jq` — mandatory for the offline verifier; absence is a hard failure.
- `ss` from `iproute2` — CO-7 socket assertion.
- Caddy internal CA — placeholder TLS posture for `a.test` and `b.test`.

## Configuration

- `deploy/Caddyfile` — one catch-all `:443` site, isolated `b.test`, `protocols h1 h2`.
- `deploy/xray/config.json` — REALITY inbound with `acceptProxyProtocol: true`.
- `deploy/PLACEHOLDERS.md` — every token that must be replaced before deployment.
- `.github/workflows/build.yml` — artifact build.
- `.github/workflows/gate0.yml` — Gate 0 probes.
- `.github/workflows/verify.yml` — offline and coexistence suites.

## Platform Requirements

- **Build host:** Bash, Git, Go, `xcaddy`, network access to the module sources.
- **Offline verifier:** Linux or MSYS with `jq` and an executable Caddy binary.
- **Coexistence suite:** Linux with root, because it binds `:443` and samples sockets.
- **Authoring host:** Windows is supported for edits and Git only.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Code Style

- `#!/usr/bin/env bash` plus `set -euo pipefail` for executable scripts.
- Functions and variables are lower-case with underscores.
- Destructive or state-changing commands are guarded by a precondition.
- Comments explain why a line is load-bearing, not what the syntax does.
- Tabs for indentation.
- The global block pins `order` and `protocols` before site blocks.
- Every non-obvious directive carries a short comment naming the failure it
- Site addresses put `:443` first so forwardproxy's ACL and port defaults stay
- Two-space indentation.
- Placeholder values are angle-bracketed, for example `<VLESS_UUID>`.

## Naming Patterns

- Item IDs are stable and referenced by docs, tests, and reports.
- Evidence files use the item or round identifier.
- Branches use descriptive names such as `feat/protocol-pin`.
- Commit messages state the behaviour change, not the file touched.

## Error Handling

- Fail closed: a missing dependency or input is a hard error with a diagnostic.
- A check must be sensitive to the defect it guards. Add a mutation or negative
- Print the observed value on failure; do not print only "failed".
- Do not silently skip an item on an unsupported host; report it as blocked.

## Configuration Patterns

- Do not add a site-level `basic_auth`; naive authenticates the CONNECT itself.
- Do not add a `forward_proxy` upstream sub-directive; it disables the ACL and
- Do not remove `protocols h1 h2`; absence restores the compiled `h1 h2 h3`
- Do not reorder `layer4` and `tls`; `layer4` must see the raw ClientHello.
- Do not split roles onto additional ports; the delivery contract is one `:443`.

## Testing Patterns

- Offline first: prove config shape without binding a listener.
- Runtime second: prove the three roles on a real stack.
- Every positive assertion gets a control where a false positive is plausible.
- Record the host, the binary hash, and the exact command with the result.

## Documentation Patterns

- Separate "what ran" from "what is expected".
- Never upgrade an inference to a PASS.
- Keep `NOT VERIFIED` and `BLOCKED` distinct.
- State the host limitation next to the result it affects.

## Git Conventions

- Do not rewrite published history.
- Do not tag before the verification gate is green.
- Keep generated artifacts (`dist/`, `.build/`, `.gate/`) out of Git.
- Keep placeholder scans working over untracked files.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## Pattern Overview

- One Caddy process owns TCP `:443` for all three roles.
- SNI is inspected before TLS termination.
- The delivery configuration is a placeholder posture, not a runnable deployment.
- Every behavioural claim is backed by an offline check, a live check, or a

## Layers

- Purpose: produce auditable binaries from pinned inputs.
- Contains: `scripts/build.sh`, `patches/caddy-read-idle-timeout.patch`,
- Depends on: upstream Caddy, both forks, `xcaddy`, Go.
- Used by: releases and the verification jobs.
- Purpose: declare the three-role listener without cross-contamination.
- Contains: `deploy/Caddyfile`, `deploy/xray/config.json`,
- Depends on: the four modules asserted at build time.
- Used by: the runtime and the offline verifier.
- Purpose: route each connection to the correct role.
- Contains: the `layer4` listener wrapper, `forward_proxy`, `reverse_proxy`, and
- Depends on: Xray on `127.0.0.1:19098` and the site backend on
- Used by: real clients and `tests/coexist/run.sh`.
- Purpose: make regressions fail before release.
- Contains: `scripts/verify.sh` (26 items), `tests/coexist/run.sh` (7 items),
- Depends on: the built binary, `jq`, Linux, root for the coexistence suite.
- Used by: CI, release gating, and the agent-team review loop.

## Data Flow

- No persistent application state.
- Caddy holds only in-memory listener and connection state.
- Evidence lives in `.gate/`, `evidence/`, and `dist/pins.txt`.

## Key Abstractions

- Purpose: keep HTTP/3 and its QUIC listener off `:443`.
- Expression: `protocols h1 h2` in `deploy/Caddyfile`.
- Why: one SNI with two transport identities on one port is the coexistence hazard.
- Purpose: ensure proxy requests reach `forward_proxy` before the site handler.
- Expression: `order forward_proxy before reverse_proxy`.
- Why: without it, validation still passes while naive is silently dead.
- Purpose: inspect SNI before TLS consumes the ClientHello.
- Expression: `layer4` listed before `tls`.
- Why: reversing the order breaks REALITY passthrough.
- Purpose: keep the delivery config runnable-looking but not runnable-as-shipped.
- Expression: `deploy/PLACEHOLDERS.md` plus `<...>` tokens.
- Why: real secrets must never enter the tree.

## Entry Points

- Location: `scripts/build.sh`.
- Triggers: CI, releases, manual runs.
- Responsibilities: pin inputs, build, assert modules, emit artifacts.
- Location: `scripts/verify.sh`.
- Triggers: `bash scripts/verify.sh`, CI.
- Responsibilities: validate config shape and hygiene without binding a listener.
- Location: `tests/coexist/run.sh`.
- Triggers: CI as root, manual Linux run.
- Responsibilities: start the real stack and assert the three roles.
- Location: `deploy/Caddyfile`.
- Triggers: `caddy validate`, `caddy adapt`, `caddy run`.
- Responsibilities: declare all three roles on one listener.

## Error Handling

- The build fails closed on a missing module, a second patch, or a bad pin.
- The offline verifier fails closed on missing `jq`, a missing input, or a
- The coexistence suite refuses to start if `:443`, `19098`, or `8080` is taken.
- Assertions carry the observed value, not just a non-zero exit.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `$gsd-fast` for a trivial task inline, with no subagents and no PLAN.md
- `$gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `$gsd-debug` for investigation and bug fixing
- `$gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `$gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
