# REDACTION — domain-token allowlist for this repository

This file is the single source of truth for the domain-shaped tokens that are
allowed to appear in content that is about to be committed. Item `S7-13` in
`scripts/verify.sh` extracts every domain-shaped token from the work tree and
computes a set difference in both directions against the allowlist below; both
differences must be empty. The comparison is done with `sort -u` plus `comm`,
i.e. it is an exact-token comparison, not a substring search.

The scan reads the work tree (`git grep --untracked`), not the index. A plain
`git grep` sees only tracked paths, so a file that is new and not yet staged
would be invisible to this gate and would be scanned for the first time only
after it was committed — the wrong moment to discover an operational hostname.
`--untracked` still honours `.gitignore`, so `dist/`, `.build/`, `.gate/` and
`.env` stay out of the scan while every file that is about to be committed is
in it. The extractor also stops at a word boundary: without that, Python source
such as `self\.command` is extracted as the host `self\.com`, which is not a
host and must not be allow-listed to make a difference disappear. Both tokens
are written with an escaped dot here for the same reason as the C4 control
below: unescaped, this sentence would be extracted from this file and would
then have to be allow-listed, which would be a lie about what it is.

The list is machine-read. Each entry is a line that begins at column zero with a
class marker (`[C1] `, `[C2] `, `[C3] ` or `[C4] `) followed by the token; the
token is the second whitespace-separated field. Do not indent these lines, do
not reflow them, and do not keep a second copy of the list anywhere else.

A class is a statement about why the literal is harmless, not a permission to
add more literals. A token that is a real, reachable host does not belong in any
of these classes: it is replaced by an alias of the form `<HOST-n>` (and a
public address by `<PUBLIC_IP-n>`), and the alias-to-host mapping is kept in
`.gate/release/REDACTION-MAP.md`, which is local scratch state and is ignored by
git. An alias never contains a dotted-quad number, so the alias form cannot be
re-extracted as a host.

## C1 — reserved names (RFC 2606 / RFC 6761)

Names reserved for documentation, examples and testing. They cannot resolve to
anything, so they cannot leak an operational endpoint.

[C1] a.test
[C1] b.test
[C1] probe.test
[C1] unknown.test
[C1] example.com
[C1] example.net
[C1] example.org

`unknown.test` is the negative-control SNI in `tests/coexist/run.sh` CO-3: a
handshake that names it must be answered by the catch-all site and must leave
no record at the REALITY upstream, which is what proves the layer4 matcher
claims exactly one SNI instead of everything. It is a reserved name in the same
sense as the others above — it cannot resolve, so it cannot leak an endpoint —
and it belongs to class C1 rather than C3 because this project creates it
rather than quoting a third party's artefact.

`example.net` and `example.org` do not currently occur in the tree. They are
allow-listed but not required to exist, so that a future documentation edit that
uses either one does not have to edit this file first. They must not be removed
to make a difference disappear.

## C2 — Go module path identifiers (not reachable hosts)

Module paths, used as identifiers in build scripts and prose. The leading
host-shaped segment of each path (written `github\.com` and `go\.uber\.org` here,
with the dot escaped so that the tree scan does not extract a bare host) is part
of the identifier, not an address this project contacts.

[C2] github.com/caddyserver
[C2] github.com/klzgrad
[C2] github.com/mholt
[C2] github.com/olst57
[C2] github.com/XTLS
[C2] github.com/quic-go
[C2] go.uber.org/zap

A bare host with no module path (written `github\.com` here, dot escaped for the
same reason) is not in this class: it is an incomplete identifier and must be
written out as the module path it refers to.

## C3 — third-party reference hosts

Hosts named in prose when quoting an external artefact or describing an
observation. They are references, not endpoints of this delivery.

[C3] www.microsoft.com
[C3] www.apple.com
[C3] www.google.com
[C3] www.apache.org/licenses
[C3] mozilla.org/MPL

## C4 — negative control

The token below is a **negative control**. It must not occur anywhere in the
tracked tree and must not become a member of the allowlist. It exists so that
the in-script trap can demonstrate that the set comparison is exact-token
rather than a prefix or substring test: the trap feeds the control token plus
one operational-domain token to `comm` against the allowlist and must get
exactly two lines back. Fewer than two would mean the matcher is being fooled by
adjacent text; more than two would mean the allowlist has been widened.

[C4] nexample\.com

The dot is escaped on purpose. Written unescaped, this token would be extracted
from this very file by the tree scan and would then surface as an unclassified
difference — the negative control would break the allowlist it is meant to
police. The escape keeps the token readable for a human while keeping it
invisible to the extractor.
