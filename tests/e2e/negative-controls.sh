#!/usr/bin/env bash
# Render the three single-field negative controls for the REALITY client.
#
# Each control starts from the PASSING config and substitutes exactly one
# literal value with a fresh, syntactically valid value that the server does
# not know. The script refuses to emit a control whose diff against the passing
# config is anything other than one removed and one added line: a control that
# changes two fields cannot attribute a failure to either one.
#
# It only renders files. run.sh starts the clients and asserts the failures.
#
# Usage: negative-controls.sh <passing-config> <outdir>
# Env:   E2E_REALITY_UUID, E2E_REALITY_PUBLIC_KEY, E2E_REALITY_SHORT_ID,
#        E2E_XRAY_CLIENT_BIN (used for `uuid` and `x25519`), openssl for hex.
# Output: one `CONTROL <name> <path>` line per control.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/e2e/lib.sh
. "$HERE/lib.sh"

PASSING="${1:?usage: negative-controls.sh <passing-config> <outdir>}"
OUTDIR="${2:?usage: negative-controls.sh <passing-config> <outdir>}"
XRAY="${E2E_XRAY_CLIENT_BIN:-}"

[ -f "$PASSING" ] || {
	printf 'FATAL: passing config not found: %s\n' "$PASSING" >&2
	exit 2
}
mkdir -p "$OUTDIR" || exit 2

fresh_uuid() {
	local value
	value="$("$XRAY" uuid 2>/dev/null)" || return 1
	[ -n "$value" ] || return 1
	printf '%s\n' "$value"
}

fresh_public_key() {
	local value
	value="$("$XRAY" x25519 2>/dev/null |
		sed -nE 's/.*[(]PublicKey[)]:[[:space:]]*//p; s/^[Pp]ublic[[:space:]]*[Kk]ey[[:space:]]*:[[:space:]]*//p' |
		head -n1)"
	[ -n "$value" ] || return 1
	printf '%s\n' "$value"
}

fresh_short_id() {
	local value
	value="$(openssl rand -hex 4 2>/dev/null)" || return 1
	[ -n "$value" ] || return 1
	printf '%s\n' "$value"
}

# one_line_diff prints the number of content lines that differ (0, 2, ...), so
# a one-field change is exactly 2: one removal and one addition.
one_line_diff() {
	diff -u "$1" "$2" | grep -cE '^[+-][^+-]'
}

render() { # $1=name $2=old $3=new
	local name="$1" old="$2" new="$3" out="$OUTDIR/client-$1.json"
	if [ -z "$old" ] || [ -z "$new" ]; then
		printf 'FATAL: cannot render control %s: empty old or new value\n' "$name" >&2
		return 2
	fi
	literal_replace "$old" "$new" <"$PASSING" >"$out" || return 2
	if [ "$old" = "$new" ]; then
		printf 'FATAL: control %s did not change its value\n' "$name" >&2
		return 2
	fi
	local changed
	changed="$(one_line_diff "$PASSING" "$out")"
	if [ "$changed" -ne 2 ]; then
		printf 'FATAL: control %s changes %s lines, expected exactly 1\n' "$name" "$((changed / 2))" >&2
		diff -u "$PASSING" "$out" >&2
		return 2
	fi
	printf 'CONTROL %s %s\n' "$name" "$out"
}

rc=0

uuid="${E2E_REALITY_UUID:-}"
new_uuid="$(fresh_uuid)" || {
	printf 'FATAL: could not generate a UUID with %s uuid\n' "$XRAY" >&2
	exit 2
}
[ "$new_uuid" = "$uuid" ] && new_uuid="$(fresh_uuid)"
render uuid "$uuid" "$new_uuid" || rc=2

public_key="${E2E_REALITY_PUBLIC_KEY:-}"
new_public_key="$(fresh_public_key)" || {
	printf 'FATAL: could not generate an x25519 key with %s x25519\n' "$XRAY" >&2
	exit 2
}
[ "$new_public_key" = "$public_key" ] && new_public_key="$(fresh_public_key)"
render public_key "$public_key" "$new_public_key" || rc=2

short_id="${E2E_REALITY_SHORT_ID:-}"
new_short_id="$(fresh_short_id)" || {
	printf 'FATAL: could not generate a shortId with openssl rand\n' >&2
	exit 2
}
[ "$new_short_id" = "$short_id" ] && new_short_id="$(fresh_short_id)"
render short_id "$short_id" "$new_short_id" || rc=2

exit "$rc"
