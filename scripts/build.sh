#!/usr/bin/env bash
# Reproducible build of the self-hosted Caddy binary.
#
# This is the delivery build script (sprint 2). It is NOT the Gate 0 probe
# (tests/probes/gate-build.sh); that one exists only to let the gate jobs share
# a single binary and is never used to produce artifacts.
#
# Contract, per the v4 spec:
#   S1  the build is reproducible from a clean clone, and does NOT copy the
#       naive README's bare command (which cannot compile, see below)
#   S2  the binary carries all four target modules
#   S3  exactly one patch is applied, and go.mod keeps quic-go v0.63.0 with no
#       sagernet entry
#   S10 both linux/amd64 and linux/arm64 artifacts, each with a sha256
#
# Why --replace is mandatory rather than decorative: klzgrad/forwardproxy@naive
# calls caddyhttp.IdleTimeoutsFromContext (forwardproxy.go:353-357), a symbol
# that does not exist in caddy v2.11.7. The naive README's own build line omits
# both the patch and the replace, so it cannot compile against this tag. The
# read-idle patch is therefore a compile-time requirement, not an optimisation;
# Gate 0 proved the negative case in SP1-A1(c).
#
# Usage: scripts/build.sh [--arch amd64|arm64|all]
#
# Environment overrides (all optional):
#   CADDY_TAG        default v2.11.7
#   FWDPROXY_SHA     default resolved from klzgrad/forwardproxy@naive
#   L4_SHA           default resolved from mholt/caddy-l4@master
#   XCADDY_VERSION   default resolved to the newest stable tag
#   GO_VERSION       informational only; the toolchain comes from CI setup-go
#   DIST_DIR         default ./dist
#   BUILD_DIR        default ./.build
#
# Every pin is resolved to a concrete 40-hex SHA (or a concrete tag for tools
# that need a module version) and written to dist/pins.txt, so a run records
# exactly what it built.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CADDY_TAG="${CADDY_TAG:-v2.11.7}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/.build}"

PATCH="$REPO_ROOT/patches/caddy-read-idle-timeout.patch"
SRC="$BUILD_DIR/caddy-src"

log() { printf '%s\n' "$*"; }
die() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- argument
ARCHS="amd64 arm64"
if [ "${1:-}" = "--arch" ]; then
	case "${2:-}" in
	amd64) ARCHS="amd64" ;;
	arm64) ARCHS="arm64" ;;
	all) ARCHS="amd64 arm64" ;;
	*) die "unknown arch '${2:-}' (expected amd64|arm64|all)" ;;
	esac
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"

# ------------------------------------------------------------------- pins
resolve_sha() { # $1=repo $2=ref
	local sha
	sha=$(git ls-remote "$1" "$2" | awk '{print $1}' | head -n1)
	printf '%s' "$sha"
}

if [ -z "${FWDPROXY_SHA:-}" ]; then
	FWDPROXY_SHA=$(resolve_sha https://github.com/klzgrad/forwardproxy refs/heads/naive)
fi
if [ -z "${L4_SHA:-}" ]; then
	L4_SHA=$(resolve_sha https://github.com/mholt/caddy-l4 refs/heads/master)
fi
if [ -z "${XCADDY_VERSION:-}" ]; then
	XCADDY_VERSION=$(git ls-remote --tags --refs https://github.com/caddyserver/xcaddy \
		| awk '{print $2}' | sed 's#refs/tags/##' \
		| grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)
fi

for v in FWDPROXY_SHA L4_SHA; do
	val="${!v}"
	printf '%s' "$val" | grep -qE '^[0-9a-f]{40}$' \
		|| die "$v did not resolve to a 40-hex commit (got '$val')"
done
[ -n "$XCADDY_VERSION" ] || die "XCADDY_VERSION resolved to nothing"

log "pins: caddy=$CADDY_TAG forwardproxy=$FWDPROXY_SHA caddy-l4=$L4_SHA xcaddy=$XCADDY_VERSION"

# ------------------------------------------------------- source + one patch
if [ ! -d "$SRC/.git" ]; then
	log "cloning caddy $CADDY_TAG"
	git clone --depth 1 --branch "$CADDY_TAG" https://github.com/caddyserver/caddy.git "$SRC" >/dev/null
fi

HEAD_SHA=$(git -C "$SRC" rev-parse HEAD)
log "caddy source HEAD: $HEAD_SHA"

[ -f "$PATCH" ] || die "missing patch: $PATCH"

# Exactly one patch may ever be applied. A second .patch file in patches/ is a
# scope violation (the spec's red line), so fail loudly instead of silently
# applying only the first one.
patch_count=$(find "$REPO_ROOT/patches" -maxdepth 1 -name '*.patch' -type f | wc -l | tr -d ' ')
[ "$patch_count" -eq 1 ] || die "patches/ must contain exactly 1 .patch file, found $patch_count"

if grep -q 'func IdleTimeoutsFromContext' "$SRC/modules/caddyhttp/idletimeout.go" 2>/dev/null; then
	log "read-idle patch already applied"
else
	log "applying read-idle patch"
	git -C "$SRC" apply --check "$PATCH" || die "read-idle patch does not apply to $CADDY_TAG"
	git -C "$SRC" apply "$PATCH"
fi

# Assert the post-conditions the gate proved, so a drifted source tree cannot
# produce a silently wrong binary.
git -C "$SRC" diff --stat | grep -q 'modules/caddyhttp/idletimeout.go' \
	|| die "patched tree does not show idletimeout.go"
grep -q 'github.com/quic-go/quic-go v0.63.0' "$SRC/go.mod" \
	|| die "go.mod no longer pins quic-go v0.63.0"
if git -C "$SRC" grep -q -I 'sagernet' -- . 2>/dev/null; then
	die "sagernet reference found in the caddy source tree; BBR was supposed to be abandoned"
fi

# ------------------------------------------------------------------- build
export PATH="$PATH:$(go env GOPATH)/bin"
if ! command -v xcaddy >/dev/null 2>&1; then
	log "installing xcaddy@$XCADDY_VERSION"
	go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION" >/dev/null
fi

build_one() { # $1=GOARCH
	local arch="$1" out="$DIST_DIR/caddy-linux-$1"
	log "building linux/$arch"
	(
		cd "$BUILD_DIR"
		GOOS=linux GOARCH="$arch" CGO_ENABLED=0 xcaddy build "$CADDY_TAG" \
			--replace "github.com/caddyserver/caddy/v2=$SRC" \
			--with "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@$FWDPROXY_SHA" \
			--with "github.com/mholt/caddy-l4=github.com/mholt/caddy-l4@$L4_SHA" \
			--output "$out"
	)
	[ -f "$out" ] || die "build produced no file at $out"
	chmod +x "$out"
}

for arch in $ARCHS; do
	build_one "$arch"
done

# --------------------------------------------------------- verify + checksums
# Only the native arch can be executed. arm64 is verified structurally, and the
# docs must never claim it was run (spec E12 / S10).
native_arch=$(go env GOARCH)
for arch in $ARCHS; do
	out="$DIST_DIR/caddy-linux-$arch"
	file "$out"
	if [ "$arch" = "$native_arch" ]; then
		"$out" version
		mods=$("$out" list-modules)
		for m in http.handlers.forward_proxy layer4.handlers.proxy \
			caddy.listeners.layer4 layer4.matchers.quic; do
			printf '%s\n' "$mods" | grep -qx "$m" \
				|| die "$out is missing module $m"
		done
		log "native arch $arch: version + 4 modules verified"
	else
		log "cross arch $arch: artifact-level verification only (not executed)"
		go version -m "$out" | grep -E 'GOARCH|GOOS' || true
	fi
done

(
	cd "$DIST_DIR"
	sha256sum caddy-linux-* > SHA256SUMS
)

{
	printf 'caddy_tag=%s\n' "$CADDY_TAG"
	printf 'caddy_source_head=%s\n' "$HEAD_SHA"
	printf 'forwardproxy_sha=%s\n' "$FWDPROXY_SHA"
	printf 'caddy_l4_sha=%s\n' "$L4_SHA"
	printf 'xcaddy_version=%s\n' "$XCADDY_VERSION"
	printf 'patch=%s\n' "$(basename "$PATCH")"
} > "$DIST_DIR/pins.txt"

log "artifacts:"
ls -l "$DIST_DIR"
cat "$DIST_DIR/SHA256SUMS"
cat "$DIST_DIR/pins.txt"
log "build complete"
