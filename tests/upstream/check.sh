#!/usr/bin/env bash
# Offline test for scripts/check-upstream.sh.
#
# The in-sync fixture is generated from pins/build-inputs.env, so this test
# keeps passing after a deliberate bump instead of hard-coding today's values.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-upstream.sh"
PINS_FILE="$REPO_ROOT/pins/build-inputs.env"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
	printf 'UPSTREAM-TEST: FAIL - %s\n' "$*" >&2
	exit 1
}

run() { # sets OUT and RC
	set +e
	OUT="$(bash "$SCRIPT" "$@" 2>&1)"
	RC=$?
	set -e
}

[ -f "$PINS_FILE" ] || fail "missing $PINS_FILE"
# shellcheck source=../../pins/build-inputs.env
. "$PINS_FILE"

printf 'caddy_tag=%s\n' "$PIN_CADDY_TAG" >"$TMP/equal.env"
printf 'forwardproxy_sha=%s\n' "$PIN_FWDPROXY_SHA" >>"$TMP/equal.env"
printf 'caddy_l4_sha=%s\n' "$PIN_L4_SHA" >>"$TMP/equal.env"
printf 'xcaddy_version=%s\n' "$PIN_XCADDY_VERSION" >>"$TMP/equal.env"
printf 'go_version=%s\n' "$PIN_GO_VERSION" >>"$TMP/equal.env"

run --from "$TMP/equal.env"
[ "$RC" -eq 0 ] || fail "in-sync fixture exited $RC: $OUT"
printf '%s\n' "$OUT" | grep -Fqx 'UPSTREAM: OK' \
	|| fail "in-sync fixture did not print UPSTREAM: OK"
printf '%s\n' "$OUT" | grep -Fqx "UPSTREAM caddy_tag pinned=$PIN_CADDY_TAG latest=$PIN_CADDY_TAG" \
	|| fail "in-sync fixture did not report the caddy line"

sed 's/^caddy_tag=.*/caddy_tag=v9.9.9/' "$TMP/equal.env" >"$TMP/stale.env"
run --from "$TMP/stale.env"
[ "$RC" -eq 3 ] || fail "stale fixture exited $RC, expected 3: $OUT"
printf '%s\n' "$OUT" | grep -Fqx 'UPSTREAM: STALE components=1' \
	|| fail "stale fixture did not count exactly one component"
printf '%s\n' "$OUT" | grep -Fqx "UPSTREAM caddy_tag pinned=$PIN_CADDY_TAG latest=v9.9.9" \
	|| fail "stale fixture did not print the drift line"

grep -v '^go_version=' "$TMP/equal.env" >"$TMP/missing.env"
run --from "$TMP/missing.env"
[ "$RC" -eq 2 ] || fail "a missing key exited $RC, expected 2"
printf '%s\n' "$OUT" | grep -Fq 'UPSTREAM: ERROR' \
	|| fail "a missing key did not print an error line"

run --from "$TMP/equal.env" --bogus
[ "$RC" -eq 2 ] || fail "an unknown argument exited $RC, expected 2"

run --from "$TMP/does-not-exist.env"
[ "$RC" -eq 2 ] || fail "a missing fixture exited $RC, expected 2"

printf 'UPSTREAM-TEST: PASS\n'
