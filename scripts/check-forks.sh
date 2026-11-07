#!/usr/bin/env bash
# Compare each module fork with the upstream branch it mirrors.
#
# The build never follows a branch head: it checks out the commits pinned in
# pins/build-inputs.env. Syncing a fork therefore cannot change a build by
# itself; it only keeps the fork ready for the next reviewed pin bump.
#
# Usage:
#   bash scripts/check-forks.sh
#   bash scripts/check-forks.sh --from FIXTURE
#
# --from reads the eight fact keys instead of the network:
#   forwardproxy_fork, forwardproxy_upstream, forwardproxy_status,
#   forwardproxy_ahead, forwardproxy_behind,
#   caddy_l4_fork, caddy_l4_upstream, caddy_l4_status,
#   caddy_l4_ahead, caddy_l4_behind
# status is the GitHub compare value: identical, ahead, behind, or diverged.
#
# Output: one `FORK <name> ...` line per fork, then `FORKS: OK` or
# `FORKS: DRIFT`.
# Exit: 0 in sync, 3 drift, 2 usage or fetch error.

set -euo pipefail

die() {
	printf 'FORKS: ERROR - %s\n' "$*" >&2
	exit 2
}

FROM=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--from)
		[ "$#" -ge 2 ] || die "--from needs a file"
		FROM="$2"
		shift 2
		;;
	-h | --help)
		sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		die "unknown argument: $1"
		;;
	esac
done

forwardproxy_fork=""
forwardproxy_upstream=""
forwardproxy_status=""
forwardproxy_ahead=""
forwardproxy_behind=""
caddy_l4_fork=""
caddy_l4_upstream=""
caddy_l4_status=""
caddy_l4_ahead=""
caddy_l4_behind=""

short() { printf '%s' "${1:0:12}"; }

fill() { # $1=fork repo $2=upstream repo $3=branch $4=prefix
	local fork_repo="$1" up_repo="$2" branch="$3" prefix="$4"
	local fork_sha up_sha cmp status ahead behind
	fork_sha="$(gh api "repos/$fork_repo/commits/$branch" --jq .sha)" \
		|| die "$fork_repo $branch lookup failed"
	up_sha="$(gh api "repos/$up_repo/commits/$branch" --jq .sha)" \
		|| die "$up_repo $branch lookup failed"
	if [ "$fork_sha" = "$up_sha" ]; then
		status=identical
		ahead=0
		behind=0
	else
		cmp="$(gh api "repos/$fork_repo/compare/$fork_sha...$up_sha")" \
			|| die "$fork_repo compare failed"
		status="$(printf '%s' "$cmp" | jq -r .status)"
		ahead="$(printf '%s' "$cmp" | jq -r .ahead_by)"
		behind="$(printf '%s' "$cmp" | jq -r .behind_by)"
	fi
	printf -v "${prefix}_fork" '%s' "$fork_sha"
	printf -v "${prefix}_upstream" '%s' "$up_sha"
	printf -v "${prefix}_status" '%s' "$status"
	printf -v "${prefix}_ahead" '%s' "$ahead"
	printf -v "${prefix}_behind" '%s' "$behind"
}

if [ -n "$FROM" ]; then
	[ -f "$FROM" ] || die "missing fixture: $FROM"
	while IFS='=' read -r key value; do
		value="${value%$'\r'}"
		case "$key" in
		forwardproxy_fork) forwardproxy_fork="$value" ;;
		forwardproxy_upstream) forwardproxy_upstream="$value" ;;
		forwardproxy_status) forwardproxy_status="$value" ;;
		forwardproxy_ahead) forwardproxy_ahead="$value" ;;
		forwardproxy_behind) forwardproxy_behind="$value" ;;
		caddy_l4_fork) caddy_l4_fork="$value" ;;
		caddy_l4_upstream) caddy_l4_upstream="$value" ;;
		caddy_l4_status) caddy_l4_status="$value" ;;
		caddy_l4_ahead) caddy_l4_ahead="$value" ;;
		caddy_l4_behind) caddy_l4_behind="$value" ;;
		'') ;;
		*) die "unknown fixture key: $key" ;;
		esac
	done <"$FROM"
else
	command -v gh >/dev/null 2>&1 || die "gh is required for the network mode"
	command -v jq >/dev/null 2>&1 || die "jq is required for the network mode"
	fill olst57/forwardproxy klzgrad/forwardproxy naive forwardproxy
	fill olst57/caddy-l4 mholt/caddy-l4 master caddy_l4
fi

for pair in forwardproxy caddy_l4; do
	case "$pair" in
	forwardproxy) f="$forwardproxy_fork" u="$forwardproxy_upstream" ;;
	caddy_l4) f="$caddy_l4_fork" u="$caddy_l4_upstream" ;;
	esac
	[ -n "$f" ] && [ -n "$u" ] || die "no values for $pair"
done

drift=0
report() { # $1=name $2=branch $3=fork $4=upstream $5=status $6=ahead $7=behind
	local state
	case "$5" in
	identical) state="in-sync" ;;
	ahead) state="behind" ;;
	behind) state="ahead" ;;
	diverged) state="diverged" ;;
	*) die "unexpected compare status: $5" ;;
	esac
	printf 'FORK %s branch=%s fork=%s upstream=%s state=%s ahead_by=%s behind_by=%s\n' \
		"$1" "$2" "$(short "$3")" "$(short "$4")" "$state" "$6" "$7"
	[ "$state" = "in-sync" ] || drift=$((drift + 1))
}

report forwardproxy naive "$forwardproxy_fork" "$forwardproxy_upstream" \
	"$forwardproxy_status" "$forwardproxy_ahead" "$forwardproxy_behind"
report caddy_l4 master "$caddy_l4_fork" "$caddy_l4_upstream" \
	"$caddy_l4_status" "$caddy_l4_ahead" "$caddy_l4_behind"

if [ "$drift" -eq 0 ]; then
	printf 'FORKS: OK\n'
	exit 0
fi

printf 'FORKS: DRIFT forks=%s\n' "$drift"
exit 3
