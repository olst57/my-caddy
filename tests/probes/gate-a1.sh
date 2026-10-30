#!/usr/bin/env bash
# Gate 0 / sprint 1 / SP1-A1(a) + SP1-A1(b). One-off probe, not a delivery artifact.
#
# Usage: gate-a1.sh <repo-root>
# Required env: CADDY_TAG CADDY_COMMIT GATE_DIR FWDPROXY_SHA L4_SHA XCADDY_VERSION
#
# XCADDY_VERSION holds a concrete tag (e.g. v0.4.x), not a SHA: go install needs a
# module version, so a pinned tag is the reproducible form. It is never @latest.
#
# The source tree lives at $GATE_DIR/caddy-src, not $GATE_DIR/caddy: xcaddy writes
# its output to ./caddy in the working directory ($GATE_DIR), so a source directory
# named "caddy" would collide with the output binary path.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/probes/lib-evidence.sh
. "$HERE/lib-evidence.sh"

REPO_ROOT="${1:?usage: gate-a1.sh <repo-root>}"
: "${CADDY_TAG:?}" "${CADDY_COMMIT:?}" "${GATE_DIR:?}"
: "${FWDPROXY_SHA:?}" "${L4_SHA:?}" "${XCADDY_VERSION:?}"

PATCH="$REPO_ROOT/patches/caddy-read-idle-timeout.patch"
SRC="$GATE_DIR/caddy-src"
BIN="$GATE_DIR/caddy"
EVID="$REPO_ROOT/evidence/SP1-A1.txt"

mkdir -p "$GATE_DIR" "$REPO_ROOT/evidence"
evidence_init "$EVID" "SP1-A1" "ubuntu-latest, $(go version), caddy $CADDY_TAG, forwardproxy@$FWDPROXY_SHA, caddy-l4@$L4_SHA, xcaddy@$XCADDY_VERSION"

# ---------------------------------------------------------------- A1(a) clone
CMD_CLONE="git clone --depth 1 --branch $CADDY_TAG https://github.com/caddyserver/caddy.git $SRC"
git clone --depth 1 --branch "$CADDY_TAG" https://github.com/caddyserver/caddy.git "$SRC" > "$GATE_DIR/a1-clone.log" 2>&1
c=$?
ev_block "$CMD_CLONE" "$c" "$GATE_DIR/a1-clone.log"
if [ "$c" -ne 0 ]; then
	ev_assert "clone" FAIL "exit $c"
	evidence_finish FAIL "clone failed, nothing further ran"
	exit 1
fi

cd "$SRC" || exit 1
TAG_SHA=$(git rev-parse "${CADDY_TAG}^{commit}" 2>/dev/null || true)
HEAD_SHA=$(git rev-parse HEAD)
{
	printf 'rev-parse %s^{commit} -> %s\n' "$CADDY_TAG" "${TAG_SHA:-<unknown revision>}"
	printf 'rev-parse HEAD           -> %s\n' "$HEAD_SHA"
} > "$GATE_DIR/a1-commit.log"
ev_block "git rev-parse '${CADDY_TAG}^{commit}' ; git rev-parse HEAD" 0 "$GATE_DIR/a1-commit.log"

if [ "$HEAD_SHA" = "$CADDY_COMMIT" ]; then
	ev_assert "HEAD commit" PASS "$HEAD_SHA"
else
	ev_assert "HEAD commit" FAIL "got $HEAD_SHA want $CADDY_COMMIT"
fi
if [ -z "$TAG_SHA" ]; then
	ev_assert "tag peel" PASS "shallow clone carries no tag object; HEAD is the criterion, per the spec 7.4 A1(a) allowance"
elif [ "$TAG_SHA" = "$CADDY_COMMIT" ]; then
	ev_assert "tag commit" PASS "$TAG_SHA"
else
	ev_assert "tag commit" FAIL "got $TAG_SHA want $CADDY_COMMIT"
fi

# ------------------------------------------------------------ A1(a) patch only
git apply --check --verbose "$PATCH" > "$GATE_DIR/a1-check.log" 2>&1
c1=$?
ev_block "git apply --check --verbose $PATCH" "$c1" "$GATE_DIR/a1-check.log"
if [ "$c1" -eq 0 ]; then
	ev_assert "git apply --check" PASS "EXIT=0"
else
	ev_assert "git apply --check" FAIL "EXIT=$c1"
fi
for f in modules/caddyhttp/idletimeout.go modules/caddyhttp/server.go; do
	if grep -q "Checking patch $f..." "$GATE_DIR/a1-check.log"; then
		ev_assert "--check lists $f" PASS
	else
		ev_assert "--check lists $f" FAIL "not present in --verbose output"
	fi
done

git apply "$PATCH" > "$GATE_DIR/a1-apply.log" 2>&1
c2=$?
ev_block "git apply $PATCH" "$c2" "$GATE_DIR/a1-apply.log"
if [ "$c2" -eq 0 ]; then
	ev_assert "git apply" PASS "EXIT=0"
else
	ev_assert "git apply" FAIL "EXIT=$c2"
fi

git diff --name-only | sort > "$GATE_DIR/a1-files.log"
git diff --stat > "$GATE_DIR/a1-diffstat.log" 2>&1
ev_block "git diff --name-only | sort" 0 "$GATE_DIR/a1-files.log"
ev_block "git diff --stat" 0 "$GATE_DIR/a1-diffstat.log"

printf '%s\n' modules/caddyhttp/idletimeout.go modules/caddyhttp/server.go | sort > "$GATE_DIR/a1-files-want.log"
if diff -u "$GATE_DIR/a1-files-want.log" "$GATE_DIR/a1-files.log" > "$GATE_DIR/a1-files-diff.log" 2>&1; then
	ev_assert "diff file set" PASS "exactly idletimeout.go and server.go"
else
	ev_assert "diff file set" FAIL "file set differs from the two expected paths"
	{
		printf '[关键输出] git diff --name-only vs expected\n'
		cat "$GATE_DIR/a1-files-diff.log"
		printf '\n'
	} >> "$EVID"
fi
if grep -q '2 files changed, 131 insertions(+), 3 deletions(-)' "$GATE_DIR/a1-diffstat.log"; then
	ev_assert "diff counts" PASS "2 files changed, 131 insertions(+), 3 deletions(-)"
else
	ev_assert "diff counts" FAIL "expected 2 files changed, 131 insertions(+), 3 deletions(-)"
fi

grep -n 'github.com/quic-go/quic-go' go.mod > "$GATE_DIR/a1-gomod.log" 2>&1
c3=$?
ev_block "grep -n 'github.com/quic-go/quic-go' go.mod" "$c3" "$GATE_DIR/a1-gomod.log"
# The requirement is that go.mod pins quic-go v0.63.0; the line number it happens
# to sit on is not part of the contract, so it is deliberately not anchored here.
if grep -q 'github.com/quic-go/quic-go v0.63.0' "$GATE_DIR/a1-gomod.log"; then
	ev_assert "quic-go pin" PASS "go.mod contains github.com/quic-go/quic-go v0.63.0"
else
	ev_assert "quic-go pin" FAIL "go.mod does not contain github.com/quic-go/quic-go v0.63.0"
fi

git grep -c -I 'sagernet' -- . > "$GATE_DIR/a1-sagernet.log" 2>&1
c4=$?
ev_block "git grep -c -I 'sagernet' -- ." "$c4" "$GATE_DIR/a1-sagernet.log"
if [ "$c4" -eq 1 ] && [ ! -s "$GATE_DIR/a1-sagernet.log" ]; then
	ev_assert "no sagernet" PASS "no output, EXIT=1"
else
	ev_assert "no sagernet" FAIL "expected empty output with EXIT=1, got EXIT=$c4"
fi

# ----------------------------------------------------------------- A1(b) build
export PATH="$PATH:$(go env GOPATH)/bin"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION" > "$GATE_DIR/a1-xcaddy.log" 2>&1
c5=$?
xcaddy version >> "$GATE_DIR/a1-xcaddy.log" 2>&1
ev_block "go install github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION ; xcaddy version" "$c5" "$GATE_DIR/a1-xcaddy.log"
if [ "$c5" -eq 0 ]; then
	ev_assert "xcaddy pinned install" PASS "installed $XCADDY_VERSION, no @latest"
else
	ev_assert "xcaddy pinned install" FAIL "exit $c5"
fi

# gate-build.sh finds $SRC already cloned and already patched, so it reuses both.
bash "$HERE/gate-build.sh" "$REPO_ROOT" > "$GATE_DIR/a1-build.log" 2>&1
c6=$?
ev_block "xcaddy build $CADDY_TAG --replace github.com/caddyserver/caddy/v2=$SRC --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@$FWDPROXY_SHA --with github.com/mholt/caddy-l4=github.com/mholt/caddy-l4@$L4_SHA" "$c6" "$GATE_DIR/a1-build.log"
if [ "$c6" -eq 0 ]; then
	ev_assert "build" PASS "EXIT=0"
else
	ev_assert "build" FAIL "EXIT=$c6"
fi

if [ ! -f "$BIN" ]; then
	ev_assert "binary produced" FAIL "no regular file at $BIN"
	evidence_finish FAIL
	exit 1
fi

"$BIN" version > "$GATE_DIR/a1-version.log" 2>&1
ev_block "$BIN version" 0 "$GATE_DIR/a1-version.log"
if head -n1 "$GATE_DIR/a1-version.log" | grep -q "^$CADDY_TAG"; then
	ev_assert "caddy version" PASS "$(head -n1 "$GATE_DIR/a1-version.log")"
else
	ev_assert "caddy version" FAIL "first line does not start with $CADDY_TAG"
fi

"$BIN" list-modules > "$GATE_DIR/a1-modules.log" 2>&1
if ! grep -qx 'layer4.matchers.quic' "$GATE_DIR/a1-modules.log"; then
	ev_note "layer4.matchers.quic absent after the first build; rebuilding with the explicit l4quic module (the remedy the spec requires, not a waiver)"
	bash "$HERE/gate-build.sh" "$REPO_ROOT" --with github.com/mholt/caddy-l4/modules/l4quic > "$GATE_DIR/a1-build2.log" 2>&1
	c=$?
	ev_block "xcaddy build $CADDY_TAG --replace ... --with .../caddy-l4@$L4_SHA --with github.com/mholt/caddy-l4/modules/l4quic" "$c" "$GATE_DIR/a1-build2.log"
	"$BIN" list-modules > "$GATE_DIR/a1-modules.log" 2>&1
fi

grep -x -e 'http.handlers.forward_proxy' -e 'layer4.handlers.proxy' -e 'caddy.listeners.layer4' -e 'layer4.matchers.quic' "$GATE_DIR/a1-modules.log" > "$GATE_DIR/a1-modules-4.log" 2>&1
c7=$?
ev_block "list-modules | grep -x -e http.handlers.forward_proxy -e layer4.handlers.proxy -e caddy.listeners.layer4 -e layer4.matchers.quic" "$c7" "$GATE_DIR/a1-modules-4.log"
n=$(wc -l < "$GATE_DIR/a1-modules-4.log" | tr -d ' ')
if [ "$c7" -eq 0 ] && [ "$n" -eq 4 ]; then
	ev_assert "four modules" PASS "exactly 4 lines, one per module"
else
	ev_assert "four modules" FAIL "expected exactly 4 matching lines, got $n"
fi

if [ "$ASSERT_FAIL" -eq 0 ]; then
	evidence_finish PASS
	exit 0
fi
evidence_finish FAIL
exit 1
