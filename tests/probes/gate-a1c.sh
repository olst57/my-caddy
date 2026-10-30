#!/usr/bin/env bash
# Gate 0 / sprint 1 / SP1-A1(c) reverse control. One-off probe, not a delivery artifact.
#
# The build here is EXPECTED to fail. The job goes green only if the build really
# failed AND the log carries the identifier IdleTimeoutsFromContext. A green build
# means the pinned forwardproxy SHA does not call that symbol, which contradicts
# E2: that is a FAIL of the item, never a pass.
#
# Spec 7.4 requires this reverse control in its own job, while spec 7.5 requires
# one SP1-A1.txt covering (a)(b)(c). This script therefore writes the (c) section
# into evidence/SP1-A1.txt in this job's workspace, and the canonical file is the
# concatenation of the sp1-a1 and sp1-a1c artifacts in that order. The banner
# below makes it obvious which half a reader is looking at.
#
# Usage: gate-a1c.sh <repo-root>
# Required env: CADDY_TAG GATE_DIR FWDPROXY_SHA XCADDY_VERSION
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/probes/lib-evidence.sh
. "$HERE/lib-evidence.sh"

REPO_ROOT="${1:?usage: gate-a1c.sh <repo-root>}"
: "${CADDY_TAG:?}" "${GATE_DIR:?}" "${FWDPROXY_SHA:?}" "${XCADDY_VERSION:?}"

EVID="$REPO_ROOT/evidence/SP1-A1.txt"
mkdir -p "$GATE_DIR" "$REPO_ROOT/evidence"
evidence_init "$EVID" "SP1-A1(c)" "ubuntu-latest, $(go version), caddy $CADDY_TAG (unpatched, no --replace), forwardproxy@$FWDPROXY_SHA, xcaddy@$XCADDY_VERSION"
ev_note "this is the (c) reverse-control section of SP1-A1; the (a)(b) section is the sp1-a1 artifact"

export PATH="$PATH:$(go env GOPATH)/bin"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION" > "$GATE_DIR/a1c-xcaddy.log" 2>&1
c5=$?
ev_block "go install github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION" "$c5" "$GATE_DIR/a1c-xcaddy.log"
if [ "$c5" -ne 0 ]; then
	ev_assert "xcaddy pinned install" FAIL "exit $c5"
	evidence_finish FAIL
	exit 1
fi
ev_assert "xcaddy pinned install" PASS "installed $XCADDY_VERSION, no @latest"

cd "$GATE_DIR" || exit 1

# Deliberately no --replace and no caddy-l4: one variable only (forwardproxy, no patch).
CMD="xcaddy build $CADDY_TAG --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@$FWDPROXY_SHA"
xcaddy build "$CADDY_TAG" \
	--with "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@$FWDPROXY_SHA" \
	> "$GATE_DIR/a1c-build.log" 2>&1
c=$?
ev_block "$CMD" "$c" "$GATE_DIR/a1c-build.log"

FIRST_ERR=$(grep -m1 'IdleTimeoutsFromContext' "$GATE_DIR/a1c-build.log" || true)
if [ -n "$FIRST_ERR" ]; then
	ev_note "first IdleTimeoutsFromContext line: $FIRST_ERR"
else
	ev_note "no IdleTimeoutsFromContext line in the build log"
fi

if [ "$c" -eq 0 ]; then
	ev_assert "build must fail" FAIL "build SUCCEEDED (exit 0): the pinned forwardproxy@$FWDPROXY_SHA does not reference caddyhttp.IdleTimeoutsFromContext, so E2's premise does not hold for this pin. Stop and re-check the pin; do not swap it silently."
else
	ev_assert "build must fail" PASS "exit $c (non-zero, as required)"
fi

if grep -q 'IdleTimeoutsFromContext' "$GATE_DIR/a1c-build.log"; then
	ev_assert "error names the missing symbol" PASS "IdleTimeoutsFromContext present in the build log"
else
	ev_assert "error names the missing symbol" FAIL "IdleTimeoutsFromContext absent; the failure is for some other reason and does not prove E2"
fi

if [ "$ASSERT_FAIL" -eq 0 ]; then
	evidence_finish PASS
	exit 0
fi
evidence_finish FAIL
exit 1
