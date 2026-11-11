#!/usr/bin/env bash
# Offline static guard for the two scheduled watch workflows.
#
# These checks read the files as text on purpose: no YAML parser, no network,
# no jq. A reverted cron line or a re-added comment path would otherwise only
# surface weeks later on a scheduled run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPSTREAM_WATCH="$REPO_ROOT/.github/workflows/upstream-watch.yml"
FORK_SYNC="$REPO_ROOT/.github/workflows/fork-sync.yml"
CHECK_UPSTREAM="$REPO_ROOT/scripts/check-upstream.sh"

fail() {
	printf 'WORKFLOWS-TEST: FAIL - %s\n' "$*" >&2
	exit 1
}

for f in "$UPSTREAM_WATCH" "$FORK_SYNC" "$CHECK_UPSTREAM"; do
	[ -f "$f" ] || fail "missing $f"
done

# The watch runs on the 1st and 15th; a daily cron must not creep back.
grep -Fq "cron: '0 1 1,15 * *'" "$UPSTREAM_WATCH" \
	|| fail "upstream-watch.yml is missing the twice-monthly cron"
cron_count="$(grep -c '^[[:space:]]*- cron:' "$UPSTREAM_WATCH" || true)"
[ "$cron_count" -eq 1 ] || fail "upstream-watch.yml has $cron_count cron entries, expected 1"
if grep -Fq "cron: '0 1 * * *'" "$UPSTREAM_WATCH"; then
	fail "upstream-watch.yml still carries the daily cron"
fi

# fork-sync keeps its daily slot; only its issue path changed.
grep -Fq "cron: '30 1 * * *'" "$FORK_SYNC" \
	|| fail "fork-sync.yml cron changed unexpectedly"

# An already-open issue must silence both workflows: no comment path at all.
for f in "$UPSTREAM_WATCH" "$FORK_SYNC"; do
	if grep -Fq 'gh issue comment' "$f"; then
		fail "$f still has a comment path"
	fi
	grep -Fq 'gh issue create' "$f" || fail "$f is missing the issue creation path"
done

# The two module SHAs come from this project's forks, never upstream. Scope the
# negative check to this script: check-forks.sh compares against upstream by
# design.
grep -Fq 'repos/olst57/forwardproxy/commits/naive' "$CHECK_UPSTREAM" \
	|| fail "check-upstream.sh does not read the forwardproxy fork head"
grep -Fq 'repos/olst57/caddy-l4/commits/master' "$CHECK_UPSTREAM" \
	|| fail "check-upstream.sh does not read the caddy-l4 fork head"
for stale in 'repos/klzgrad/forwardproxy/commits' 'repos/mholt/caddy-l4/commits'; do
	if grep -Fq "$stale" "$CHECK_UPSTREAM"; then
		fail "check-upstream.sh still reads $stale"
	fi
done

# The issue lookup keys on these exact titles; renaming one breaks dedupe.
grep -Fq 'upstream-watch: pinned inputs are behind upstream' "$UPSTREAM_WATCH" \
	|| fail "upstream-watch tracking title changed"
grep -Fq 'fork-sync: module forks are behind upstream' "$FORK_SYNC" \
	|| fail "fork-sync tracking title changed"

printf 'WORKFLOWS-TEST: PASS\n'
