# LICENSING — what the release contains and what it must carry

This document records the license conclusion for every component that is
linked into the delivery binary, plus the two open decisions that belong to the
repository owner. The evidence is the upstream `LICENSE` file fetched at the
pinned commit or tag on 2026-11-06, not a recollection of what a project
usually uses.

## Method

Each file was fetched from the GitHub contents API at the exact ref named
below, decoded, and hashed. The hash is the check that the text in
`LICENSES/` is the upstream text and not a retyped copy.

| Component | Ref | `LICENSE` sha256 (first 12) | SPDX |
| --- | --- | --- | --- |
| Caddy | `v2.11.7` | `cfc7749b96f6` | Apache-2.0 |
| caddy-l4 | `96e1a6bf063c` | `cfc7749b96f6` | Apache-2.0 |
| forwardproxy | `e747854e7874` | `cfc7749b96f6` | Apache-2.0 |
| xcaddy | `v0.4.7` | `58d1e17ffe51` | Apache-2.0 |
| quic-go | `v0.63.0` | `77d0b7b53e8a` | MIT |
| Go | `go1.26.10` | `911f8f578293` | BSD-3-Clause |
| Xray-core | `v26.10.31` | `1f256ecad192` | MPL-2.0 |

Caddy has no `NOTICE` file at `v2.11.7` (the contents API returns 404), so
Apache-2.0 section 4(d) adds nothing beyond the license text itself.

## Conclusion

The published binary is a combined work of Apache-2.0, MIT and BSD-3-Clause
code. Distributing it requires:

1. a copy of the Apache-2.0 text, which also covers caddy-l4 and
   forwardproxy;
2. the MIT text with the quic-go copyright line;
3. the BSD-3-Clause text with the Go copyright line;
4. a statement that the Caddy source was modified — the read-idle patch.

All four are satisfied by `LICENSES/` and `THIRD_PARTY_NOTICES.md` in this
repository. Xray is MPL-2.0, but no Xray binary is published here, so its
source-disclosure obligation does not attach to this project's artifacts.

## Repository content

The repository had no explicit license, so the legal default was already
all rights reserved. Rather than grant rights the owner did not request, this
task makes that default explicit:

- [`LICENSE`](../LICENSE) carries
  `SPDX-License-Identifier: LicenseRef-Proprietary`;
- reuse, modification and redistribution need a separate written agreement;
- this decision does not change any third-party license or the rights in a
  published binary.

The owner can replace `LICENSE` with an open-source license later; that is a
deliberate repository-wide decision, not something this audit chooses.

## Release material

The `v0.4.3` release notes are the publication record. The release carries the
four original binary/provenance assets plus the license and notice set:

- `LICENSE`;
- `THIRD_PARTY_NOTICES.md`;
- `Apache-2.0.txt`;
- `MIT.txt`;
- `BSD-3-Clause-Go.txt`;
- `MPL-2.0.txt`.

The binary file names and their hashes are unchanged. `tests/licenses/check.sh`
fails if the local texts, SPDX identifiers or notices drift from this record.

## What is not claimed

- This is not legal advice.
- The table covers the named components and the quic-go/Go runtime that are
  part of the delivered binary. It is not a module-by-module enumeration of
  every transitive Go module; those arrive through Caddy's own `go.mod` at the
  pinned tag and can be listed from the binary with `go version -m`.
- A transitive-module review does not by itself make `LicenseRef-Proprietary`
  compatible with an open-source contribution; the owner must choose that
  policy explicitly.
