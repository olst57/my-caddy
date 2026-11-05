---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Code Conventions

**Analysis Date:** 2026-11-05

## Code Style

**Shell:**
- `#!/usr/bin/env bash` plus `set -euo pipefail` for executable scripts.
- Functions and variables are lower-case with underscores.
- Destructive or state-changing commands are guarded by a precondition.
- Comments explain why a line is load-bearing, not what the syntax does.

**Caddyfile:**
- Tabs for indentation.
- The global block pins `order` and `protocols` before site blocks.
- Every non-obvious directive carries a short comment naming the failure it
  prevents.
- Site addresses put `:443` first so forwardproxy's ACL and port defaults stay
  in force.

**JSON:**
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
  control where practical.
- Print the observed value on failure; do not print only "failed".
- Do not silently skip an item on an unsupported host; report it as blocked.

## Configuration Patterns

- Do not add a site-level `basic_auth`; naive authenticates the CONNECT itself.
- Do not add a `forward_proxy` upstream sub-directive; it disables the ACL and
  ports defaults.
- Do not remove `protocols h1 h2`; absence restores the compiled `h1 h2 h3`
  default.
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

<!-- refreshed: 2026-11-05 -->
