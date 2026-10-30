#!/usr/bin/env bash
# Gate 0 (sprint 1) one-off probe helper -- NOT a delivery artifact.
# Sprint 2 owns the reproducible scripts/build.sh; this file exists only so the
# A1(b), A2 and A3 jobs build the exact same probe binary from one place.
#
# Usage: gate-build.sh <repo-root> [extra xcaddy args...]
#
# Required env: CADDY_TAG, GATE_DIR, FWDPROXY_SHA, L4_SHA
#
# The source tree is cloned to $GATE_DIR/caddy-src, deliberately NOT $GATE_DIR/caddy:
# xcaddy writes its output as ./caddy in the working directory, which is $GATE_DIR,
# so a source directory named "caddy" would collide with the output binary path.
#
# The build command below uses pinned 40-hex SHAs only. The upstream branch names
# (klzgrad/forwardproxy `naive`, mholt/caddy-l4 `master`) are resolved to SHAs in
# the `pins` job and never appear as build arguments.
set -uo pipefail

REPO_ROOT="${1:?usage: gate-build.sh <repo-root> [extra xcaddy args...]}"
shift
EXTRA_ARGS=("$@")

: "${CADDY_TAG:?CADDY_TAG is required}"
: "${GATE_DIR:?GATE_DIR is required}"
: "${FWDPROXY_SHA:?FWDPROXY_SHA is required}"
: "${L4_SHA:?L4_SHA is required}"

SRC="$GATE_DIR/caddy-src"
BIN="$GATE_DIR/caddy"
PATCH="$REPO_ROOT/patches/caddy-read-idle-timeout.patch"

mkdir -p "$GATE_DIR"

if [ ! -d "$SRC/.git" ]; then
	echo "clone caddy $CADDY_TAG -> $SRC"
	git clone --depth 1 --branch "$CADDY_TAG" https://github.com/caddyserver/caddy.git "$SRC" || exit 1
fi

echo "caddy HEAD: $(git -C "$SRC" rev-parse HEAD)"

if [ ! -f "$PATCH" ]; then
	echo "missing patch file: $PATCH" >&2
	exit 1
fi

if grep -q 'func IdleTimeoutsFromContext' "$SRC/modules/caddyhttp/idletimeout.go" 2>/dev/null; then
	echo "idle patch already applied"
else
	echo "applying $PATCH"
	git -C "$SRC" apply "$PATCH" || { echo "idle patch failed to apply" >&2; exit 1; }
fi

# A rebuild must not clobber the binary that is still being used by a running probe.
if [ -e "$BIN" ] && [ ! -f "$BIN" ]; then
	echo "refusing to build: $BIN exists and is not a regular file" >&2
	exit 1
fi

cd "$GATE_DIR" || exit 1

echo "xcaddy build: forwardproxy@$FWDPROXY_SHA caddy-l4@$L4_SHA ${EXTRA_ARGS[*]:-}"
xcaddy build "$CADDY_TAG" \
	--replace "github.com/caddyserver/caddy/v2=$SRC" \
	--with "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@$FWDPROXY_SHA" \
	--with "github.com/mholt/caddy-l4=github.com/mholt/caddy-l4@$L4_SHA" \
	"${EXTRA_ARGS[@]}"
