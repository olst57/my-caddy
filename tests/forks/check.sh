#!/usr/bin/env bash
# Offline test for scripts/check-forks.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-forks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
	printf 'FORKS-TEST: FAIL - %s\n' "$*" >&2
	exit 1
}

run() { # sets OUT and RC
	set +e
	OUT="$(bash "$SCRIPT" "$@" 2>&1)"
	RC=$?
	set -e
}

cat >"$TMP/equal.env" <<'EOF'
forwardproxy_fork=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
forwardproxy_upstream=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
forwardproxy_status=identical
forwardproxy_ahead=0
forwardproxy_behind=0
caddy_l4_fork=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
caddy_l4_upstream=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
caddy_l4_status=identical
caddy_l4_ahead=0
caddy_l4_behind=0
EOF

run --from "$TMP/equal.env"
[ "$RC" -eq 0 ] || fail "in-sync fixture exited $RC: $OUT"
printf '%s\n' "$OUT" | grep -Fqx 'FORKS: OK' || fail "no FORKS: OK"
printf '%s\n' "$OUT" | grep -Fq 'FORK forwardproxy branch=naive fork=aaaaaaaaaaaa upstream=aaaaaaaaaaaa state=in-sync' \
	|| fail "forwardproxy in-sync line missing"

sed 's/^caddy_l4_status=.*/caddy_l4_status=ahead/' "$TMP/equal.env" >"$TMP/behind.env"
sed -i 's/^caddy_l4_ahead=.*/caddy_l4_ahead=3/' "$TMP/behind.env"
run --from "$TMP/behind.env"
[ "$RC" -eq 3 ] || fail "behind fixture exited $RC, expected 3: $OUT"
printf '%s\n' "$OUT" | grep -Fq 'state=behind ahead_by=3' || fail "behind state not reported"
printf '%s\n' "$OUT" | grep -Fqx 'FORKS: DRIFT forks=1' || fail "drift count wrong"

sed 's/^forwardproxy_status=.*/forwardproxy_status=diverged/' "$TMP/equal.env" >"$TMP/diverged.env"
run --from "$TMP/diverged.env"
[ "$RC" -eq 3 ] || fail "diverged fixture exited $RC, expected 3"
printf '%s\n' "$OUT" | grep -Fq 'state=diverged' || fail "diverged state not reported"

sed 's/^forwardproxy_status=.*/forwardproxy_status=bogus/' "$TMP/equal.env" >"$TMP/bogus.env"
run --from "$TMP/bogus.env"
[ "$RC" -eq 2 ] || fail "bogus status exited $RC, expected 2"
printf '%s\n' "$OUT" | grep -Fq 'FORKS: ERROR' || fail "bogus status printed no error"

grep -v '^caddy_l4_fork=' "$TMP/equal.env" >"$TMP/missing.env"
run --from "$TMP/missing.env"
[ "$RC" -eq 2 ] || fail "missing key exited $RC, expected 2"

run --from "$TMP/nope.env"
[ "$RC" -eq 2 ] || fail "missing fixture exited $RC, expected 2"

printf 'FORKS-TEST: PASS\n'
