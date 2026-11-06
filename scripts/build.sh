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
# Why --replace is mandatory rather than decorative: the forwardproxy naive
# branch (upstream: klzgrad/forwardproxy, which this project's fork tracks)
# calls caddyhttp.IdleTimeoutsFromContext (forwardproxy.go:353-357), a symbol
# that does not exist in caddy v2.11.7. The naive README's own build line omits
# both the patch and the replace, so it cannot compile against this tag. The
# read-idle patch is therefore a compile-time requirement, not an optimisation;
# Gate 0 proved the negative case in SP1-A1(c).
#
# Usage: scripts/build.sh [--arch amd64|arm64|all]
#
# Environment overrides (all optional):
#   CADDY_TAG        default from pins/build-inputs.env
#   CADDY_COMMIT     default from pins/build-inputs.env
#   FWDPROXY_SHA     default from pins/build-inputs.env
#   L4_SHA           default from pins/build-inputs.env
#   XCADDY_VERSION   default from pins/build-inputs.env
#   PINS_FILE        default ./pins/build-inputs.env
#   GO_VERSION       informational only; the toolchain comes from CI setup-go
#   DIST_DIR         default ./dist
#   BUILD_DIR        default ./.build
#
# The two replaced modules are built from this project's own forks at commits
# fixed in pins/build-inputs.env. A fork sync does not move a build until that
# file is edited and reviewed, so the same tree always compiles the same source
# inputs. Each run still writes dist/pins.txt, and that receipt is the record of
# what the run actually compiled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/.build}"

PATCH="$REPO_ROOT/patches/caddy-read-idle-timeout.patch"
SRC="$BUILD_DIR/caddy-src"

log() { printf '%s\n' "$*"; }
die() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------- pins
# One file is the source of truth for the delivery build and the Gate 0
# probes. Environment variables still win, so a one-off rebuild can be pinned
# to a different commit without editing the tree; the default never floats.
PINS_FILE="${PINS_FILE:-$REPO_ROOT/pins/build-inputs.env}"
[ -f "$PINS_FILE" ] || die "missing pins file: $PINS_FILE"
# shellcheck source=../pins/build-inputs.env
. "$PINS_FILE"

FWDPROXY_REPO=https://github.com/olst57/forwardproxy
L4_REPO=https://github.com/olst57/caddy-l4

# No default is assigned before the pins file is read. A pre-set CADDY_TAG here
# would shadow PIN_CADDY_TAG forever and make the file look authoritative while
# the tag still came from a constant in this script.
CADDY_TAG="${CADDY_TAG:-$PIN_CADDY_TAG}"
CADDY_COMMIT="${CADDY_COMMIT:-$PIN_CADDY_COMMIT}"
FWDPROXY_SHA="${FWDPROXY_SHA:-$PIN_FWDPROXY_SHA}"
L4_SHA="${L4_SHA:-$PIN_L4_SHA}"
XCADDY_VERSION="${XCADDY_VERSION:-$PIN_XCADDY_VERSION}"

print_pins=0

# ---------------------------------------------------------------- argument
ARCHS="amd64 arm64"
if [ "${1:-}" = "--arch" ]; then
	case "${2:-}" in
	amd64) ARCHS="amd64" ;;
	arm64) ARCHS="arm64" ;;
	all) ARCHS="amd64 arm64" ;;
	*) die "unknown arch '${2:-}' (expected amd64|arm64|all)" ;;
	esac
elif [ "${1:-}" = "--print-pins" ]; then
	print_pins=1
fi

# Shape check, not a pin: it catches a truncated or malformed value before any
# clone or compile, and it says nothing about which version is acceptable.
for v in FWDPROXY_SHA L4_SHA CADDY_COMMIT; do
	val="${!v}"
	printf '%s' "$val" | grep -qE '^[0-9a-f]{40}$' \
		|| die "$v is not a 40-hex commit (got '$val')"
done
printf '%s' "$XCADDY_VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
	|| die "XCADDY_VERSION is not an exact vX.Y.Z tag (got '$XCADDY_VERSION')"

if [ "$print_pins" -eq 1 ]; then
	printf 'pins_file=%s\n' "$PINS_FILE"
	printf 'caddy_tag=%s\n' "$CADDY_TAG"
	printf 'caddy_commit=%s\n' "$CADDY_COMMIT"
	printf 'forwardproxy_sha=%s\n' "$FWDPROXY_SHA"
	printf 'caddy_l4_sha=%s\n' "$L4_SHA"
	printf 'xcaddy_version=%s\n' "$XCADDY_VERSION"
	exit 0
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"

log "pins: caddy=$CADDY_TAG forwardproxy=$FWDPROXY_SHA caddy-l4=$L4_SHA xcaddy=$XCADDY_VERSION"

# ------------------------------------------------------- source + one patch
if [ ! -d "$SRC/.git" ]; then
	log "cloning caddy $CADDY_TAG"
	git clone --depth 1 --branch "$CADDY_TAG" https://github.com/caddyserver/caddy.git "$SRC" >/dev/null
fi

HEAD_SHA=$(git -C "$SRC" rev-parse HEAD)
log "caddy source HEAD: $HEAD_SHA"

# The tag is pinned as well. If it ever moves, fail before compiling instead of
# recording a source head that disagrees with the fixed input.
[ "$HEAD_SHA" = "$CADDY_COMMIT" ] \
	|| die "caddy $CADDY_TAG resolved to $HEAD_SHA, expected $CADDY_COMMIT"

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
# The xcaddy that builds the artifacts is always the version resolved above,
# installed unconditionally. Installing only when nothing is on PATH would let
# an image that ships another xcaddy silently float this build input, and
# pins.txt would then name a version the build did not use. Invoking the binary
# by absolute path closes the remaining hole: a stale xcaddy earlier in PATH
# cannot shadow the freshly installed one.
XCADDY_BIN="$(go env GOPATH)/bin/xcaddy"
log "installing xcaddy@$XCADDY_VERSION"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION" >/dev/null
[ -x "$XCADDY_BIN" ] || die "go install produced no executable at $XCADDY_BIN"

build_one() { # $1=GOARCH
	local arch="$1" out="$DIST_DIR/caddy-linux-$1"
	log "building linux/$arch"
	(
		cd "$BUILD_DIR"
		# --with is "import path=replacement module path@version". A go module
		# path cannot carry a scheme, so the fork URL is stripped to its path
		# form here; the repo constants stay URLs so they match the other
		# records in the tree.
		GOOS=linux GOARCH="$arch" CGO_ENABLED=0 "$XCADDY_BIN" build "$CADDY_TAG" \
			--replace "github.com/caddyserver/caddy/v2=$SRC" \
			--with "github.com/caddyserver/forwardproxy=${FWDPROXY_REPO#https://}@$FWDPROXY_SHA" \
			--with "github.com/mholt/caddy-l4=${L4_REPO#https://}@$L4_SHA" \
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
	printf 'go_version=%s\n' "$(go env GOVERSION)"
	printf 'patch=%s\n' "$(basename "$PATCH")"
} > "$DIST_DIR/pins.txt"

log "artifacts:"
ls -l "$DIST_DIR"
cat "$DIST_DIR/SHA256SUMS"
cat "$DIST_DIR/pins.txt"
log "build complete"
