---
last_mapped_commit: a4c550f273bea63657ea15c571ae26b1f485e7dd
last_mapped_at: 2026-11-05
---
# Codebase Concerns

**Analysis Date:** 2026-11-05

## Tech Debt

**Uncommitted verification slice:**
- Issue: the 26-item verifier, the coexistence suite, and `verify.yml` are in
  the working tree on `feat/protocol-pin`, not on `main`.
- Files: `scripts/verify.sh`, `tests/coexist/*`, `.github/workflows/verify.yml`,
  `docs/VERIFY.md`, `docs/BUILD.md`.
- Impact: a clean checkout of `main` cannot reproduce the documented gate.
- Fix: review, commit, and merge before tagging.

**Documentation ahead of the tag:**
- Issue: `docs/VERIFY.md` says CI runs the verifier "from v0.4.3 onward" before
  `v0.4.3` exists.
- Impact: a reader can mistake a forward-looking statement for released
  behaviour.
- Fix: publish the tag or reword until it exists.

## Known Issues

**REALITY placeholder defaults:**
- The shipped `serverNames=["b.test"]` plus `dest=example.com:443` was rejected
  by the destination in the v0.4.0 acceptance run (alert 40).
- A different destination accepted the same topology once.
- Fix: decide between a runnable default and a mandatory-replace rule.

**naive `probe_resistance` collision:**
- `probe_resistance example.com` collided with the destination being proxied;
  the tunnelled request failed with `code=000` / `CURL_EXIT=35`.
- Fix: document and check that the decoy target is not the proxied target.

**Temporary directory cleanup:**
- The v0.4.0 run left `/tmp/tmp.YA6WTjpwd8` behind; the cleanup item was
  reclassified FAIL.
- Fix: verify the current verifier's scratch handling and re-run the cleanup
  check.

**Evidence-form defects:**
- Three report/original-output mismatches and six undisclosed evidence files
  were recorded in the v0.4.0 acceptance.
- Fix: regenerate the report from raw outputs and publish the full file list.

## Security Considerations

- `probe_resistance` makes a rejected CONNECT look like an ordinary site
  request; a security check must inspect the tunnel outcome, not the status
  code.
- A `200 OK` on CONNECT is not proof of a tunnel. The suite asserts relayed
  bytes and a control.
- The delivery config keeps forwardproxy's default private-network deny; do not
  add an `upstream` sub-directive, which disables that deny.
- No real credential, UUID, domain, or key material may enter the tree.

## Performance Bottlenecks

- None measured. The project does not claim throughput or latency results.
- The coexistence suite's external target adds latency and one network
  dependency to CI.

## Fragile Areas

- **Order pins:** removing one line can restore a silent, validating-but-broken
  configuration.
- **Protocol pin:** deleting `protocols h1 h2` restores h3 and the QUIC listener
  without failing validation.
- **Fork drift:** a fork that is never synced misses upstream fixes; a sync does
  not trigger a build.
- **Byte identity:** the Go patch level floats with the runner cache, so reruns
  are not guaranteed byte-identical.
- **Host split:** Windows cannot execute the binary; evidence must carry its
  host.

## Test Coverage Gaps

- arm64 is executed by the manual `verify-arm64-release` workflow against the
  `v0.4.3` release asset. A future release must run it again; the result does
  not transfer to a new build.
- Public-internet HTTP/3 is not tested because HTTP/3 is off.
- A real deployment with real credentials is not tested.
- `S7-9`, `S7-10`, `S7-11`, `S7-16`, and `S7-17` are script-external meta items
  and never emit.

## Dependencies at Risk

- `jq` is mandatory for the offline verifier; absence fails closed.
- `xcaddy` is pinned in `pins/build-inputs.env`; moving it is now a tracked
  change rather than an ambient one.
- Both module forks are single-maintainer projects.

<!-- refreshed: 2026-11-05 -->
