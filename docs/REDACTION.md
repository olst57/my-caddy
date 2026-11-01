# REDACTION — domain-token allowlist for this repository

This file is the single source of truth for the domain-shaped tokens that are
allowed to appear in tracked content. Item `S7-13` in `scripts/verify.sh`
extracts every domain-shaped token from the tracked tree and computes a set
difference in both directions against the allowlist below; both differences must
be empty. The comparison is done with `sort -u` plus `comm`, i.e. it is an
exact-token comparison, not a substring search.

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
[C1] example.com
[C1] example.net
[C1] example.org

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
