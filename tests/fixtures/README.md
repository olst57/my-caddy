# Fixture Caddyfile guard

`tests/fixtures/check.sh` is the single implementation of the address and
protocol rules for test Caddyfiles. It scans every `*.Caddyfile` under `tests/`
and also reads `deploy/Caddyfile` without modifying it:

```bash
bash tests/fixtures/check.sh
bash tests/fixtures/check.sh .gate/e2e/Caddyfile   # a rendered overlay
```

For each non-443 listener, at least one site block must carry both address
forms:

```caddyfile
:8443, a.test:8443 {
```

The listener must also pin `protocols h1 h2`, either in the dual-form site
block or in the global `servers :8443` block that owns it. The rendered E2E
overlay uses the global form because it inherits that line from
`deploy/Caddyfile`. A host-specific auxiliary site on the same port, such as
the test's `b.test:8443` 404 block, is allowed because it shares the already
pinned listener; it cannot satisfy the rule by itself.

`deploy/Caddyfile` is the delivery file, not a test fixture. Its
`:443, a.test` address is compliant because the second address inherits the
first one's port, so the non-443 rule does not apply. The file is read only:
this guard never rewrites it.

The guard is separate from `scripts/verify.sh`; the offline verifier stays at
26 items and the coexistence suite stays at eight. CI calls this script as its
own step, and the E2E preflight calls the same script over the rendered
overlay, so the rule cannot drift between the two paths.
