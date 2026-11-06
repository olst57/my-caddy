#!/usr/bin/env bash
# Static check that the delivery build and the Gate 0 probes consume fixed
# inputs. It does not build anything, so it runs in seconds on any host.
#
# Usage: bash tests/pins/check.sh [--pins <dist/pins.txt>]
#
# Exits 0 only when:
#   1. pins/build-inputs.env exists and holds exactly the seven expected keys,
#   2. every key has the right shape,
#   3. neither scripts/build.sh nor gate0.yml resolves a branch at run time,
#   4. `scripts/build.sh --print-pins` prints those exact values,
#   5. if a build receipt is supplied, every compared pinned field agrees.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PINS_FILE="$REPO_ROOT/pins/build-inputs.env"
RECEIPT=""

while [ "$#" -gt 0 ]; do
	case "$1" in
	--pins)
		RECEIPT="${2:-}"
		[ -n "$RECEIPT" ] || { echo "usage: check.sh [--pins FILE]" >&2; exit 2; }
		shift 2
		;;
	*)
		echo "usage: check.sh [--pins FILE]" >&2
		exit 2
		;;
	esac
done

fail() {
	printf 'PINS: FAIL - %s\n' "$*" >&2
	exit 1
}

[ -f "$PINS_FILE" ] || fail "missing $PINS_FILE"

expected_keys='PIN_CADDY_TAG PIN_CADDY_COMMIT PIN_FWDPROXY_SHA PIN_L4_SHA PIN_XCADDY_VERSION PIN_GO_VERSION PIN_XRAY_VERSION'
seen_keys=""

line_no=0
while IFS= read -r line || [ -n "$line" ]; do
	line_no=$((line_no + 1))
	case "$line" in
	'' | '#'*) continue ;;
	esac
	if ! printf '%s' "$line" | grep -qE '^PIN_[A-Z0-9_]+=[^[:space:]]+$'; then
		fail "line $line_no is not KEY=VALUE: $line"
	fi
	key=${line%%=*}
	case " $expected_keys " in
	*" $key "*)
		case " $seen_keys " in
		*" $key "*) fail "duplicate key on line $line_no: $key" ;;
		esac
		;;
	*) fail "unexpected key on line $line_no: $key" ;;
	esac
	value=${line#*=}
	printf -v "$key" '%s' "$value"
	seen_keys="$seen_keys $key"
done <"$PINS_FILE"

for key in $expected_keys; do
	[ -n "${!key:-}" ] || fail "$key is missing from $PINS_FILE"
done

for key in PIN_CADDY_COMMIT PIN_FWDPROXY_SHA PIN_L4_SHA; do
	printf '%s' "${!key}" | grep -qE '^[0-9a-f]{40}$' \
		|| fail "$key is not a 40-hex commit: ${!key}"
done

for key in PIN_CADDY_TAG PIN_XCADDY_VERSION PIN_XRAY_VERSION; do
	printf '%s' "${!key}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
		|| fail "$key is not an exact vX.Y.Z tag: ${!key}"
done

printf '%s' "$PIN_GO_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
	|| fail "PIN_GO_VERSION is not an exact X.Y.Z version: $PIN_GO_VERSION"

# GO_VERSION is duplicated in the workflows because setup-go needs it before
# the build starts. Keep those copies honest by making this check fail when any
# workflow drifts from the pins file.
go_version_re=$(printf '%s' "$PIN_GO_VERSION" | sed 's/\./\\./g')
for workflow in build gate0 verify verify-arm64-release; do
	workflow_file="$REPO_ROOT/.github/workflows/$workflow.yml"
	[ -f "$workflow_file" ] || fail "missing workflow: $workflow.yml"
	count=$(grep -cE '^[[:space:]]*GO_VERSION:' "$workflow_file" || true)
	[ "$count" -eq 1 ] \
		|| fail "$workflow.yml must declare GO_VERSION exactly once, found $count"
	grep -qE "^[[:space:]]*GO_VERSION:[[:space:]]*${go_version_re}[[:space:]]*$" "$workflow_file" \
		|| fail "$workflow.yml does not pin GO_VERSION to $PIN_GO_VERSION"
done

if grep -nE 'git[[:space:]]+ls-remote' "$REPO_ROOT/scripts/build.sh" \
	"$REPO_ROOT/.github/workflows/gate0.yml" >&2; then
	fail "a build path still resolves a ref at run time"
fi
if grep -nE 'refs/heads/' "$REPO_ROOT/scripts/build.sh" \
	"$REPO_ROOT/.github/workflows/gate0.yml" >&2; then
	fail "a build path still contains a branch ref"
fi

grep -q 'pins/build-inputs.env' "$REPO_ROOT/.github/workflows/gate0.yml" \
	|| fail "gate0.yml does not read pins/build-inputs.env"
grep -q 'CADDY_TAG="\$PIN_CADDY_TAG"' "$REPO_ROOT/.github/workflows/gate0.yml" \
	|| fail "gate0.yml does not take CADDY_TAG from the pins file"
grep -q 'CADDY_COMMIT="\$PIN_CADDY_COMMIT"' "$REPO_ROOT/.github/workflows/gate0.yml" \
	|| fail "gate0.yml does not take CADDY_COMMIT from the pins file"

printed=$(bash "$REPO_ROOT/scripts/build.sh" --print-pins)
for pair in \
	"caddy_tag=$PIN_CADDY_TAG" \
	"caddy_commit=$PIN_CADDY_COMMIT" \
	"forwardproxy_sha=$PIN_FWDPROXY_SHA" \
	"caddy_l4_sha=$PIN_L4_SHA" \
	"xcaddy_version=$PIN_XCADDY_VERSION" \
	"go_version=go$PIN_GO_VERSION"; do
	printf '%s\n' "$printed" | grep -qx "$pair" \
		|| fail "build.sh --print-pins does not print $pair"
done

if [ -n "$RECEIPT" ]; then
	[ -f "$RECEIPT" ] || fail "missing receipt: $RECEIPT"
	for pair in \
		"caddy_tag=$PIN_CADDY_TAG" \
		"caddy_source_head=$PIN_CADDY_COMMIT" \
		"forwardproxy_sha=$PIN_FWDPROXY_SHA" \
		"caddy_l4_sha=$PIN_L4_SHA" \
		"xcaddy_version=$PIN_XCADDY_VERSION" \
		"go_version=go$PIN_GO_VERSION"; do
		grep -qx "$pair" "$RECEIPT" \
			|| fail "receipt disagrees with the pins file: expected $pair"
	done
fi

printf 'PINS: PASS\n'
