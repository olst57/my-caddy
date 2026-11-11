#!/usr/bin/env bash
# Compare the pinned build inputs with where they are read from today.
#
# Read-only. This script never edits pins/build-inputs.env: a bump stays a
# reviewed change that has to pass the gate, because a new Caddy tag can break
# the read-idle-timeout patch and the two forks have to be synced first.
#
# The Caddy tag, the xcaddy tag and the Go release are upstream lookups. The
# two module SHAs are read from this project's own forks, not from the
# upstream repositories: fork-sync.yml fast-forwards those forks from
# upstream, and the fork head is therefore the commit the build would
# eventually follow.
#
# Usage:
#   bash scripts/check-upstream.sh
#   bash scripts/check-upstream.sh --from FIXTURE
#
# --from reads key=value facts instead of the network, which is what the
# offline test uses. Recognised keys: caddy_tag, forwardproxy_sha,
# caddy_l4_sha, xcaddy_version, go_version.
#
# Output: one `UPSTREAM <name> pinned=... latest=...` line per component, then
# either `UPSTREAM: OK` or `UPSTREAM: STALE components=N`.
# Exit: 0 in sync, 3 stale, 2 usage or fetch error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS_FILE="${PINS_FILE:-$REPO_ROOT/pins/build-inputs.env}"

die() {
	printf 'UPSTREAM: ERROR - %s\n' "$*" >&2
	exit 2
}

[ -f "$PINS_FILE" ] || die "missing pins file: $PINS_FILE"
# shellcheck source=../pins/build-inputs.env
. "$PINS_FILE"

FROM=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--from)
		[ "$#" -ge 2 ] || die "--from needs a file"
		FROM="$2"
		shift 2
		;;
	-h | --help)
		sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		die "unknown argument: $1"
		;;
	esac
done

caddy_tag=""
forwardproxy_sha=""
caddy_l4_sha=""
xcaddy_version=""
go_version=""

if [ -n "$FROM" ]; then
	[ -f "$FROM" ] || die "missing fixture: $FROM"
	while IFS='=' read -r key value; do
		value="${value%$'\r'}"
		case "$key" in
		caddy_tag) caddy_tag="$value" ;;
		forwardproxy_sha) forwardproxy_sha="$value" ;;
		caddy_l4_sha) caddy_l4_sha="$value" ;;
		xcaddy_version) xcaddy_version="$value" ;;
		go_version) go_version="$value" ;;
		'') ;;
		*) die "unknown fixture key: $key" ;;
		esac
	done <"$FROM"
else
	command -v gh >/dev/null 2>&1 || die "gh is required for the network mode"
	command -v jq >/dev/null 2>&1 || die "jq is required for the network mode"
	command -v curl >/dev/null 2>&1 || die "curl is required for the network mode"

	caddy_tag="$(gh api repos/caddyserver/caddy/releases/latest --jq .tag_name)" \
		|| die "caddy release lookup failed"
	# The fork is the source of truth because fork-sync.yml auto-syncs it from
	# upstream, so its head is the commit the build would eventually follow.
	# The branch is `naive`, not `master`: master stopped in 2024 and diverged
	# only by a README edit, so a master comparison reports a permanent false
	# positive. The pin is a `naive` commit.
	forwardproxy_sha="$(gh api repos/olst57/forwardproxy/commits/naive --jq .sha)" \
		|| die "forwardproxy commit lookup failed"
	# The caddy-l4 fork mirrors upstream `master`.
	caddy_l4_sha="$(gh api repos/olst57/caddy-l4/commits/master --jq .sha)" \
		|| die "caddy-l4 commit lookup failed"
	xcaddy_version="$(gh api repos/caddyserver/xcaddy/releases/latest --jq .tag_name)" \
		|| die "xcaddy release lookup failed"
	go_tag="$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version')" \
		|| die "go release list lookup failed"
	go_version="${go_tag#go}"
fi

for pair in "caddy_tag" "forwardproxy_sha" "caddy_l4_sha" "xcaddy_version" "go_version"; do
	case "$pair" in
	caddy_tag) value="$caddy_tag" ;;
	forwardproxy_sha) value="$forwardproxy_sha" ;;
	caddy_l4_sha) value="$caddy_l4_sha" ;;
	xcaddy_version) value="$xcaddy_version" ;;
	go_version) value="$go_version" ;;
	esac
	[ -n "$value" ] || die "no value for $pair"
done

stale=0
report() { # $1=name $2=pinned $3=latest
	printf 'UPSTREAM %s pinned=%s latest=%s\n' "$1" "$2" "$3"
	[ "$2" = "$3" ] || stale=$((stale + 1))
}

report caddy_tag "$PIN_CADDY_TAG" "$caddy_tag"
report forwardproxy_sha "$PIN_FWDPROXY_SHA" "$forwardproxy_sha"
report caddy_l4_sha "$PIN_L4_SHA" "$caddy_l4_sha"
report xcaddy_version "$PIN_XCADDY_VERSION" "$xcaddy_version"
report go_version "$PIN_GO_VERSION" "$go_version"

if [ "$stale" -eq 0 ]; then
	printf 'UPSTREAM: OK\n'
	exit 0
fi

printf 'UPSTREAM: STALE components=%s\n' "$stale"
exit 3
