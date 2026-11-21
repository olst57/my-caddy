#!/usr/bin/env bash
# Artifact-only special build: Caddy v2.11.9 with ONLY the forwardproxy module.
#
# This is NOT the delivery build (scripts/build.sh). It mirrors that script's
# shape, but it applies no patch, uses no source-replacement flag and adds no
# layer 4 module, because Caddy v2.11.9 already ships the idle-timeout override
# API that v2.11.7 required a delivery patch for. Artifacts carry the
# caddy-special- prefix and the receipt records patch=none so this build cannot
# be mistaken for delivery evidence.
#
# Usage: scripts/build-special.sh [--arch amd64|arm64|all] [--print-pins]
#
# Environment overrides (all optional):
#   PINS_FILE        default ./pins/special-build-inputs.env
#   DIST_DIR         default ./dist
#   BUILD_DIR        default ./.build
#   CADDY_TAG        default from pins/special-build-inputs.env
#   CADDY_COMMIT     default from pins/special-build-inputs.env
#   FWDPROXY_SHA     default from pins/special-build-inputs.env
#   XCADDY_VERSION   default from pins/special-build-inputs.env
#
# SPECIAL_GO_VERSION is not overridable: the active toolchain must match that
# exact patch. The pins file supplies the fixed default for every other input;
# a named override is opt-in and the workflow declares none.
#
# scripts/verify.sh hardcodes v2.11.7 and must never be pointed at this binary.
# The special artifact is not delivery evidence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/.build}"
SRC="$BUILD_DIR/caddy-special-src"

log() { printf '%s\n' "$*"; }
die() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------- pins
# The special pins file is a separate surface on purpose: the delivery checks
# read only pins/build-inputs.env, so this build can move without touching the
# delivery pin surface. A named override still wins for a one-off rebuild, but
# the fixed default in the file never floats.
PINS_FILE="${PINS_FILE:-$REPO_ROOT/pins/special-build-inputs.env}"
[ -f "$PINS_FILE" ] || die "missing pins file: $PINS_FILE"
# shellcheck source=../pins/special-build-inputs.env
. "$PINS_FILE"

# Write the effective values back into the SPECIAL_ names so the build line and
# the receipt share one value: the file supplies the fixed default, and a named
# override is opt-in.
SPECIAL_CADDY_TAG="${CADDY_TAG:-$SPECIAL_CADDY_TAG}"
SPECIAL_CADDY_COMMIT="${CADDY_COMMIT:-$SPECIAL_CADDY_COMMIT}"
SPECIAL_FWDPROXY_SHA="${FWDPROXY_SHA:-$SPECIAL_FWDPROXY_SHA}"
SPECIAL_XCADDY_VERSION="${XCADDY_VERSION:-$SPECIAL_XCADDY_VERSION}"

# ---------------------------------------------------------------- argument
ARCHS="amd64 arm64"
print_pins=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--arch)
		[ "$#" -ge 2 ] || die "--arch requires a value (offending token: $1)"
		case "$2" in
		amd64 | arm64) ARCHS="$2" ;;
		all) ARCHS="amd64 arm64" ;;
		*) die "unknown arch '$2' (expected amd64|arm64|all)" ;;
		esac
		shift 2
		;;
	--print-pins)
		print_pins=1
		shift
		;;
	*)
		die "unknown argument '$1' (usage: scripts/build-special.sh [--arch amd64|arm64|all] [--print-pins])"
		;;
	esac
done

# Shape check, not a pin: it catches a truncated or malformed value before any
# clone or compile, and it says nothing about which version is acceptable.
for v in SPECIAL_CADDY_COMMIT SPECIAL_FWDPROXY_SHA; do
	val="${!v}"
	printf '%s' "$val" | grep -qE '^[0-9a-f]{40}$' \
		|| die "$v is not a 40-hex commit (got '$val')"
done
for v in SPECIAL_CADDY_TAG SPECIAL_XCADDY_VERSION; do
	val="${!v}"
	printf '%s' "$val" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
		|| die "$v is not an exact vX.Y.Z tag (got '$val')"
done
printf '%s' "$SPECIAL_GO_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
	|| die "SPECIAL_GO_VERSION is not an exact X.Y.Z version (got '$SPECIAL_GO_VERSION')"

# This block must run before every Go and git command: it is the whole reason
# the script is usable on a host that has neither toolchain.
if [ "$print_pins" -eq 1 ]; then
	printf 'pins_file=%s\n' "$PINS_FILE"
	printf 'caddy_tag=%s\n' "$SPECIAL_CADDY_TAG"
	printf 'caddy_commit=%s\n' "$SPECIAL_CADDY_COMMIT"
	printf 'forwardproxy_sha=%s\n' "$SPECIAL_FWDPROXY_SHA"
	printf 'xcaddy_version=%s\n' "$SPECIAL_XCADDY_VERSION"
	printf 'go_version=go%s\n' "$SPECIAL_GO_VERSION"
	exit 0
fi

export GOTOOLCHAIN=local
ACTUAL_GO_VERSION="$(go env GOVERSION 2>/dev/null || true)"
[ "$ACTUAL_GO_VERSION" = "go$SPECIAL_GO_VERSION" ] \
	|| die "Go toolchain is '${ACTUAL_GO_VERSION:-missing}', expected go$SPECIAL_GO_VERSION; set up Go from SPECIAL_GO_VERSION"

mkdir -p "$DIST_DIR" "$BUILD_DIR"

log "pins: caddy=$SPECIAL_CADDY_TAG forwardproxy=$SPECIAL_FWDPROXY_SHA xcaddy=$SPECIAL_XCADDY_VERSION go=go$SPECIAL_GO_VERSION"

# -------------------------------------------------------------- source tree
# The special build keeps its own source tree so a delivery build tree, which
# carries the patch, can never leak into this unpatched build.
if [ -e "$SRC" ] && [ ! -d "$SRC/.git" ]; then
	die "build source directory exists but is not a Git tree: $SRC; remove it before rebuilding"
fi
if [ ! -d "$SRC/.git" ]; then
	log "cloning caddy $SPECIAL_CADDY_TAG"
	git clone --depth 1 --branch "$SPECIAL_CADDY_TAG" https://github.com/caddyserver/caddy.git "$SRC" >/dev/null
fi

HEAD_SHA="$(git -C "$SRC" rev-parse HEAD)"
log "caddy source HEAD: $HEAD_SHA"

[ "$HEAD_SHA" = "$SPECIAL_CADDY_COMMIT" ] \
	|| die "caddy $SPECIAL_CADDY_TAG resolved to $HEAD_SHA, expected $SPECIAL_CADDY_COMMIT"

# A dirty tree means modifications were applied. This build must stay
# unpatched, so fail before compiling rather than shipping a patched binary
# under an unpatched receipt.
git -C "$SRC" diff --quiet \
	|| die "caddy source tree at $SRC is dirty; this build must stay unpatched"

# These two symbols are the evidence that the upstream tag already ships the
# idle API the delivery patch adds to v2.11.7. If either disappears, this build
# would need a patch and the premise of the special build is gone.
for sym in 'func (r *IdleTimeoutReader) Override(' 'func IdleTimeoutsFromContext('; do
	grep -Fq "$sym" "$SRC/modules/caddyhttp/idletimeout.go" \
		|| die "missing '$sym' in $SRC/modules/caddyhttp/idletimeout.go"
done

# ------------------------------------------------------------------- build
# Install xcaddy unconditionally: a preinstalled binary on PATH could otherwise
# float this build input silently, and the receipt would name a version the
# build did not use. Invoking it by absolute path closes the remaining hole.
XCADDY_BIN="$(go env GOPATH)/bin/xcaddy"
log "installing xcaddy@$SPECIAL_XCADDY_VERSION"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$SPECIAL_XCADDY_VERSION" >/dev/null
[ -x "$XCADDY_BIN" ] || die "go install produced no executable at $XCADDY_BIN"

build_one() { # $1=GOARCH
	local arch="$1" out="$DIST_DIR/caddy-special-linux-$1"
	log "building linux/$arch (special, forwardproxy only)"
	(
		cd "$BUILD_DIR"
		# Exactly one module-add and no source-replacement flag: the fixed
		# default from the pins file is the source input this run compiles.
		GOOS=linux GOARCH=$arch CGO_ENABLED=0 "$XCADDY_BIN" build "$SPECIAL_CADDY_TAG" --with "github.com/caddyserver/forwardproxy=github.com/olst57/forwardproxy@$SPECIAL_FWDPROXY_SHA" --output "$out"
	)
	[ -f "$out" ] || die "build produced no file at $out"
	chmod +x "$out"
}

for arch in $ARCHS; do
	build_one "$arch"
done

# --------------------------------------------------------- verify + checksums
# Only the native arch can be executed. The other arch is structural only, and
# the receipt must never claim it was run.
native_arch="$(go env GOARCH)"
for arch in $ARCHS; do
	out="$DIST_DIR/caddy-special-linux-$arch"
	file "$out"
	if [ "$arch" = "$native_arch" ]; then
		version_out="$("$out" version)"
		log "version: $version_out"
		caddy_tag_re="$(printf '%s' "$SPECIAL_CADDY_TAG" | sed 's/\./\\./g')"
		printf '%s\n' "$version_out" | grep -qE "^${caddy_tag_re}([[:space:]]|$)" \
			|| die "$out reports '${version_out}', expected the leading token $SPECIAL_CADDY_TAG"
		mods="$("$out" list-modules)"
		if ! printf '%s\n' "$mods" | grep -qx 'http.handlers.forward_proxy'; then
			die "$out is missing module http.handlers.forward_proxy; observed matching lines: $(printf '%s\n' "$mods" | grep -iE 'forward|layer4' || true)"
		fi
		for m in layer4.handlers.proxy caddy.listeners.layer4 layer4.matchers.quic; do
			if printf '%s\n' "$mods" | grep -qx "$m"; then
				die "$out unexpectedly contains module $m"
			fi
		done
		log "native arch $arch: version $SPECIAL_CADDY_TAG and the forwardproxy-only module set verified"
	else
		build_info="$(go version -m "$out")"
		observed_build_lines="$(printf '%s\n' "$build_info" | grep -E 'GOARCH|GOOS' || true)"
		printf '%s\n' "$build_info" | grep -qE "GOARCH=$arch" \
			|| die "$out build info does not record GOARCH=$arch; observed: ${observed_build_lines:-none}"
		printf '%s\n' "$build_info" | grep -qE 'GOOS=linux' \
			|| die "$out build info does not record GOOS=linux; observed: ${observed_build_lines:-none}"
		log "cross arch $arch: structural verification only (artifact not executed)"
	fi
done

files=()
for arch in $ARCHS; do
	files+=("caddy-special-linux-$arch")
done
(
	cd "$DIST_DIR"
	sha256sum "${files[@]}" >SHA256SUMS
)

{
	printf 'caddy_tag=%s\n' "$SPECIAL_CADDY_TAG"
	printf 'caddy_source_head=%s\n' "$HEAD_SHA"
	printf 'forwardproxy_sha=%s\n' "$SPECIAL_FWDPROXY_SHA"
	printf 'xcaddy_version=%s\n' "$SPECIAL_XCADDY_VERSION"
	printf 'go_version=%s\n' "$(go env GOVERSION)"
	printf 'patch=none\n'
	printf 'modules_asserted=http.handlers.forward_proxy\n'
	printf 'modules_absent=layer4.handlers.proxy,caddy.listeners.layer4,layer4.matchers.quic\n'
} >"$DIST_DIR/special-pins.txt"

log "artifacts:"
ls -l "$DIST_DIR"
cat "$DIST_DIR/SHA256SUMS"
cat "$DIST_DIR/special-pins.txt"
log "special build complete"
