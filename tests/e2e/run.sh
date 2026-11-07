#!/usr/bin/env bash
# REALITY end-to-end harness: the executable guard for the three roles.
#
# What it does
#   Derives a test Caddyfile from deploy/Caddyfile by literal substitution
#   only, proves the derivation is reversible by reversing it and diffing
#   against the delivery file, renders both Xray configs from the environment,
#   starts the stack on a fixed loopback layout, and asserts:
#
#     E2E-01  a VLESS/Vision tunnel through the Caddy listener returns the
#             target's body marker, over a client with exactly one outbound
#     E2E-02  an unauthenticated probe is shown the destination's certificate,
#             compared field by field against a live fetch of that destination
#     E2E-03  the layer4 upstream receives a PROXY v2 header whose fields parse
#             as TCP/IPv4 with a 12-byte address block and an intact ClientHello
#     E2E-04a a wrong UUID opens no tunnel
#     E2E-04b a wrong publicKey opens no tunnel
#     E2E-04c a wrong shortId opens no tunnel
#     E2E-05a a wrong naive credential reaches the decoy, not the target
#     E2E-05b a missing naive credential reaches the decoy, not the target
#     E2E-05c a correct credential cannot reach a private target (ACL + zero bytes)
#     E2E-07    an unmatched or absent SNI is rejected, not handed a certificate
#     E2E-08    30 serial and 8 concurrent requests through each leg, with the
#               upstream count corroborating the client count
#
#   Every negative control mutates exactly one line of the passing client
#   config; the render step refuses to emit a control whose diff is not
#   exactly one removed plus one added line.
#
# Modes
#   --preflight-only      validate inputs, ports, overlay and configs, then exit
#   --negative-preflight  prove that a missing or empty input exits 2 before any
#                         process starts; needs no destination and no binary
#
# External inputs (never downloaded on the host; upload them):
#   CADDY_BIN              Caddy built with forwardproxy + caddy-l4
#   E2E_XRAY_SERVER_BIN    Xray used for the REALITY inbound
#   E2E_XRAY_CLIENT_BIN    Xray used for the SOCKS client (also `uuid`/`x25519`)
#   E2E_REALITY_SNI        outer SNI, a name the destination presents a valid
#                          certificate for
#   E2E_REALITY_DEST       host:port the REALITY inbound falls back to
#   E2E_TARGET             URL fetched through the SOCKS inbound
#   E2E_TARGET_MARKER      body marker only the target produces
#
#   Key material is generated at run time with the Xray binary when all four of
#   E2E_REALITY_UUID, E2E_REALITY_PRIVATE_KEY, E2E_REALITY_PUBLIC_KEY and
#   E2E_REALITY_SHORT_ID are unset. Supplying a subset is a hard failure: a
#   half-injected key set is ambiguous, and the harness has no skip path.
#
# Needs: root (bind 8443), curl, openssl, python3, ss.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=tests/e2e/lib.sh
. "$HERE/lib.sh"

MODE=full
case "${1:-}" in
'') ;;
--preflight-only) MODE=preflight ;;
--negative-preflight) MODE=negative-preflight ;;
--help | -h)
	sed -n '2,40p' "$HERE/run.sh"
	exit 0
	;;
*)
	printf 'FATAL: unknown argument: %s\n' "$1" >&2
	exit 2
	;;
esac

CADDY_BIN="${CADDY_BIN:-}"
XRAY_SERVER="${E2E_XRAY_SERVER_BIN:-}"
XRAY_CLIENT="${E2E_XRAY_CLIENT_BIN:-}"
SNI="${E2E_REALITY_SNI:-}"
DEST="${E2E_REALITY_DEST:-}"
TARGET="${E2E_TARGET:-}"
TARGET_MARKER="${E2E_TARGET_MARKER:-}"
WORKDIR="${E2E_WORKDIR:-$REPO_ROOT/.gate/e2e}"
TIMEOUT="${E2E_TIMEOUT:-25}"
CONTROL_TIMEOUT="${E2E_CONTROL_TIMEOUT:-90}"

# Measured on hw-gz against this Caddy build. caddy-l4's proxy handler writes
# the address the client dialled, not the loopback upstream it forwards to.
PROXYV2_DEST="${E2E_PROXYV2_DEST:-127.0.0.1:8443}"

REALITY_PORT=8443
SERVER_PORT=19099
BACKEND_PORT=18080
TARGET_PORT=18081
SOCKS_PORT=10802
NAIVE_TARGET_MARKER="E2E-NAIVE-TARGET-MARKER"
TARGET_COUNT="$WORKDIR/target-count.jsonl"

# The naive smoke needs a target the delivery ACL allows. The built-in deny
# list is 10/8, 127/8, 172.16/12, ::1/128 and fe80::/10 (read from the pinned
# forwardproxy source), so a TEST-NET-3 address is allowed and still local
# once it is bound to `lo`. That keeps the counting target real without adding
# an `acl` directive to the config under test -- E2E-05c still exercises the
# unmodified deny list.
SMOKE_TARGET_IP="${E2E_SMOKE_TARGET_IP:-203.0.113.10}"
SMOKE_TARGET_PORT="${E2E_SMOKE_TARGET_PORT:-18082}"
SMOKE_TARGET_COUNT="$WORKDIR/smoke-target-count.jsonl"
SMOKE_IP_ADDED=0

REQUIRED_VARS=(
	CADDY_BIN
	E2E_XRAY_SERVER_BIN
	E2E_XRAY_CLIENT_BIN
	E2E_REALITY_SNI
	E2E_REALITY_DEST
	E2E_TARGET
	E2E_TARGET_MARKER
)
KEY_VARS=(
	E2E_REALITY_UUID
	E2E_REALITY_PRIVATE_KEY
	E2E_REALITY_PUBLIC_KEY
	E2E_REALITY_SHORT_ID
)

PASSED=0
FAILED=0
CLIENT_PID=""
SERVER_PID=""
CADDY_PID=""
BACKEND_PID=""
STUB_PID=""
TARGET_PID=""
SMOKE_TARGET_PID=""

cleanup_all() {
	cleanup "$CLIENT_PID" "$SERVER_PID" "$CADDY_PID" "$BACKEND_PID" "$STUB_PID" "$TARGET_PID" "$SMOKE_TARGET_PID"
	if [ "$SMOKE_IP_ADDED" -eq 1 ]; then
		ip addr del "$SMOKE_TARGET_IP/32" dev lo 2>/dev/null
	fi
}
trap cleanup_all EXIT

fatal() {
	printf 'FATAL: %s\n' "$*" >&2
	printf 'E2E: FAIL\n' >&2
	exit 2
}

sed_replacement() {
	printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

json_field() { # $1=json file $2=field
	python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh).get(sys.argv[2]))
' "$1" "$2"
}

# The SNI probe writes JSONL, one `E2E-07 BASELINE ` prefix per line, so the
# single-document `json_field` above cannot read it. `$2` is 1-based.
baseline_field() { # $1=jsonl file $2=line number $3=field
	python3 -c '
import json, sys
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
record = json.loads(lines[int(sys.argv[2]) - 1][lines[int(sys.argv[2]) - 1].index("{"):])
value = record.get(sys.argv[3])
print("" if value is None else value)
' "$1" "$2" "$3"
}

# ------------------------------------------------------------------ preflight
preflight_vars() {
	require_env "${REQUIRED_VARS[@]}" || return 2

	case "$SNI" in
	*[!A-Za-z0-9.-]*) fatal "E2E_REALITY_SNI must be a hostname, got '$SNI'" ;;
	esac
	case "$DEST" in
	*:*) ;;
	*) fatal "E2E_REALITY_DEST must be host:port, got '$DEST'" ;;
	esac
	case "${DEST##*:}" in
	'' | *[!0-9]*) fatal "E2E_REALITY_DEST must be host:port, got '$DEST'" ;;
	esac
	case "$TARGET" in
	http://* | https://*) ;;
	*) fatal "E2E_TARGET must be an http(s) URL, got '$TARGET'" ;;
	esac

	# The four key variables are all-or-nothing. Zero means "generate at run
	# time"; a partial set is a hard failure, never a silent top-up.
	local var set_count=0 missing=0
	for var in "${KEY_VARS[@]}"; do
		if declare -p "$var" >/dev/null 2>&1; then
			set_count=$((set_count + 1))
			if [ -z "${!var}" ]; then
				printf 'missing %s\n' "$var" >&2
				missing=1
			fi
		fi
	done
	if [ "$set_count" -gt 0 ] && [ "$set_count" -lt "${#KEY_VARS[@]}" ]; then
		for var in "${KEY_VARS[@]}"; do
			declare -p "$var" >/dev/null 2>&1 || printf 'missing %s\n' "$var" >&2
		done
		missing=1
	fi
	[ "$missing" -eq 0 ] || return 2

	KEY_MODE=injected
	[ "$set_count" -eq 0 ] && KEY_MODE=generate
	return 0
}

resolve_keys() {
	UUID="${E2E_REALITY_UUID:-}"
	PRIVATE_KEY="${E2E_REALITY_PRIVATE_KEY:-}"
	PUBLIC_KEY="${E2E_REALITY_PUBLIC_KEY:-}"
	SHORT_ID="${E2E_REALITY_SHORT_ID:-}"
	[ "$KEY_MODE" = injected ] && return 0

	UUID="$("$XRAY_SERVER" uuid 2>/dev/null)" || fatal "could not generate a UUID with $XRAY_SERVER uuid"
	[ -n "$UUID" ] || fatal "the Xray binary printed an empty UUID"

	local pair
	pair="$("$XRAY_SERVER" x25519 2>/dev/null)" || fatal "could not generate an x25519 key with $XRAY_SERVER x25519"
	# Xray 26 prints `PrivateKey: ...` and `<label> (PublicKey): ...`; older
	# builds print `Private key: ...` and `Public key: ...`. Parse both, and
	# derive the public key from its parenthesised label rather than from the
	# label text, so the parser does not depend on wording.
	PRIVATE_KEY="$(printf '%s\n' "$pair" |
		sed -nE 's/^PrivateKey:[[:space:]]*//p; s/^[Pp]rivate[[:space:]]*[Kk]ey[[:space:]]*:[[:space:]]*//p' |
		head -n1)"
	PUBLIC_KEY="$(printf '%s\n' "$pair" |
		sed -nE 's/.*[(]PublicKey[)]:[[:space:]]*//p; s/^[Pp]ublic[[:space:]]*[Kk]ey[[:space:]]*:[[:space:]]*//p' |
		head -n1)"
	[ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ] || fatal "could not parse the x25519 key pair"

	SHORT_ID="$(openssl rand -hex 4)" || fatal "could not generate a shortId with openssl rand"
	return 0
}

render_overlay() {
	local overlay="$WORKDIR/Caddyfile"
	local reversed="$WORKDIR/Caddyfile.reversed"
	USER_TOKEN="e2e-user-$RANDOM$RANDOM"
	PASS_TOKEN="e2e-pass-$RANDOM$RANDOM"

	literal_replace '<NAIVE_USER>' "$USER_TOKEN" <"$REPO_ROOT/deploy/Caddyfile" |
		literal_replace '<NAIVE_PASSWORD>' "$PASS_TOKEN" |
		literal_replace $'\torder forward_proxy before reverse_proxy' \
			$'\tdebug\n\torder forward_proxy before reverse_proxy' |
		literal_replace 'probe_resistance example.com' 'probe_resistance localhost' |
		literal_replace 'servers :443 {' 'servers :8443 {' |
		literal_replace ':443, a.test {' ':8443, a.test:8443 {' |
		literal_replace 'b.test {' 'b.test:8443 {' |
		literal_replace '@reality tls sni b.test' "@reality tls sni $SNI" |
		literal_replace 'upstream 127.0.0.1:19098' 'upstream 127.0.0.1:19099' |
		literal_replace 'reverse_proxy 127.0.0.1:8080' 'reverse_proxy 127.0.0.1:18080' \
			>"$overlay" || return 2

	# `debug` is a test-only line. Strip it before the reverse diff; the
	# forward diff still proves every other line is a literal substitution.
	sed '/^[[:space:]]*debug[[:space:]]*$/d' "$overlay" |
		literal_replace 'reverse_proxy 127.0.0.1:18080' 'reverse_proxy 127.0.0.1:8080' |
		literal_replace 'upstream 127.0.0.1:19099' 'upstream 127.0.0.1:19098' |
		literal_replace "@reality tls sni $SNI" '@reality tls sni b.test' |
		literal_replace 'b.test:8443 {' 'b.test {' |
		literal_replace ':8443, a.test:8443 {' ':443, a.test {' |
		literal_replace 'servers :8443 {' 'servers :443 {' |
		literal_replace 'probe_resistance localhost' 'probe_resistance example.com' |
		literal_replace "$USER_TOKEN" '<NAIVE_USER>' |
		literal_replace "$PASS_TOKEN" '<NAIVE_PASSWORD>' \
			>"$reversed" || return 2

	if ! diff -q "$REPO_ROOT/deploy/Caddyfile" "$reversed" >/dev/null; then
		printf 'FATAL: overlay is not a pure substitution\n' >&2
		diff -u "$REPO_ROOT/deploy/Caddyfile" "$reversed" >&2
		return 2
	fi

	# F-01 guard: a non-443 fixture must spell the site address as
	# `:port, host:port`, and the protocol pin must survive the derivation.
	grep -qE '^[[:space:]]*debug[[:space:]]*$' "$overlay" || {
		printf 'FATAL: test overlay is missing the debug log pin\n' >&2
		return 2
	}
	grep -q ':8443,' "$overlay" || {
		printf 'FATAL: overlay lost the `:port, host:port` address shape\n' >&2
		return 2
	}
	grep -q 'protocols h1 h2' "$overlay" || {
		printf 'FATAL: overlay lost the protocols h1 h2 pin\n' >&2
		return 2
	}
	if grep -qE '^[[:space:]]*servers[[:space:]]+:443[[:space:]]*\{' "$overlay"; then
		printf 'FATAL: overlay still binds the servers block to :443\n' >&2
		return 2
	fi
	if grep -qE '^[[:space:]]*:443,' "$overlay"; then
		printf 'FATAL: overlay still has a :443 site address\n' >&2
		return 2
	fi
	if grep -q 'upstream 127.0.0.1:19098' "$overlay"; then
		printf 'FATAL: overlay still forwards to the delivery upstream port\n' >&2
		return 2
	fi
	if grep -q 'reverse_proxy 127.0.0.1:8080' "$overlay"; then
		printf 'FATAL: overlay still forwards to the delivery backend port\n' >&2
		return 2
	fi
	return 0
}

render_xray() {
	sed -e "s|<E2E_REALITY_UUID>|$(sed_replacement "$UUID")|g" \
		-e "s|<E2E_REALITY_SNI>|$(sed_replacement "$SNI")|g" \
		-e "s|<E2E_REALITY_PRIVATE_KEY>|$(sed_replacement "$PRIVATE_KEY")|g" \
		-e "s|<E2E_REALITY_SHORT_ID>|$(sed_replacement "$SHORT_ID")|g" \
		-e "s|<E2E_REALITY_DEST>|$(sed_replacement "$DEST")|g" \
		"$HERE/xray-server.tpl.json" >"$WORKDIR/xray-server.json" || return 2
	sed -e "s|<E2E_REALITY_UUID>|$(sed_replacement "$UUID")|g" \
		-e "s|<E2E_REALITY_SNI>|$(sed_replacement "$SNI")|g" \
		-e "s|<E2E_REALITY_PUBLIC_KEY>|$(sed_replacement "$PUBLIC_KEY")|g" \
		-e "s|<E2E_REALITY_SHORT_ID>|$(sed_replacement "$SHORT_ID")|g" \
		"$HERE/xray-client.tpl.json" >"$WORKDIR/xray-client.json" || return 2

	local file
	for file in "$WORKDIR/xray-server.json" "$WORKDIR/xray-client.json"; do
		if grep -q '<E2E_' "$file"; then
			printf 'FATAL: unreplaced placeholder in %s\n' "$file" >&2
			grep -n '<E2E_' "$file" >&2
			return 2
		fi
		if ! python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$file"; then
			printf 'FATAL: %s is not valid JSON\n' "$file" >&2
			return 2
		fi
	done
	return 0
}

preflight() {
	local tool port
	preflight_vars || return 2
	printf 'PREFLIGHT VARS: PASS\n'
	for tool in curl openssl python3 ss; do
		command -v "$tool" >/dev/null || fatal "$tool not found"
	done
	[ -x "$CADDY_BIN" ] || fatal "no executable Caddy at $CADDY_BIN"
	[ -x "$XRAY_SERVER" ] || fatal "no executable Xray server at $XRAY_SERVER"
	[ -x "$XRAY_CLIENT" ] || fatal "no executable Xray client at $XRAY_CLIENT"
	[ -f "$REPO_ROOT/deploy/Caddyfile" ] || fatal "deploy/Caddyfile missing"
	for port in "$REALITY_PORT" "$SERVER_PORT" "$BACKEND_PORT" "$TARGET_PORT" "$SMOKE_TARGET_PORT" "$SOCKS_PORT"; do
		if port_busy "$port"; then
			fatal "port $port is already in use; this harness needs it free"
		fi
	done

	mkdir -p "$WORKDIR" || fatal "cannot create $WORKDIR"
	rm -f "$WORKDIR"/xray-server.log "$WORKDIR"/xray-client.log "$WORKDIR"/caddy.log \
		"$WORKDIR"/backend.log "$WORKDIR"/target.log "$WORKDIR"/*.jsonl \
		"$WORKDIR"/adapt.json "$WORKDIR"/adapt.err
	render_overlay || fatal "overlay render failed"
	bash "$REPO_ROOT/tests/fixtures/check.sh" "$WORKDIR/Caddyfile" ||
		fatal "fixture guard rejected the rendered overlay"
	"$CADDY_BIN" adapt --config "$WORKDIR/Caddyfile" --adapter caddyfile \
		>"$WORKDIR/adapt.json" 2>"$WORKDIR/adapt.err" || {
		cat "$WORKDIR/adapt.err" >&2
		fatal "caddy adapt rejected the overlay"
	}
	resolve_keys
	render_xray || fatal "Xray config render failed"
	printf 'PREFLIGHT: PASS\n'
	return 0
}

# ------------------------------------------------------- preflight tablature
negative_preflight() {
	local var out rc expected failures=0
	local -a all_vars=("${REQUIRED_VARS[@]}" "${KEY_VARS[@]}")
	local -a child_env=()

	base_value() { # $1=variable name -> a syntactically complete placeholder
		case "$1" in
		CADDY_BIN) printf '%s' /nonexistent/caddy ;;
		E2E_XRAY_SERVER_BIN) printf '%s' /nonexistent/server ;;
		E2E_XRAY_CLIENT_BIN) printf '%s' /nonexistent/client ;;
		E2E_REALITY_SNI) printf '%s' a.test ;;
		E2E_REALITY_DEST) printf '%s' example.com:443 ;;
		E2E_TARGET) printf 'http://127.0.0.1:%s/inner' "$BACKEND_PORT" ;;
		E2E_TARGET_MARKER) printf '%s' E2E-INNER-MARKER ;;
		E2E_REALITY_UUID) printf '%s' control-uuid-placeholder ;;
		E2E_REALITY_PRIVATE_KEY) printf '%s' control-private-key-placeholder ;;
		E2E_REALITY_PUBLIC_KEY) printf '%s' control-public-key-placeholder ;;
		E2E_REALITY_SHORT_ID) printf '%s' 00ff00ff ;;
		*) return 1 ;;
		esac
	}

	run_child() { # $1=variable under test $2=extra assignment (optional)
		local name
		child_env=()
		for name in "${all_vars[@]}"; do
			[ "$name" = "$1" ] && continue
			child_env+=("$name=$(base_value "$name")")
		done
		[ -n "${2:-}" ] && child_env+=("$2")
		# -u first: an inherited value must not satisfy the check, and the
		# assignment list above never re-adds the variable under test.
		env -u "$1" "${child_env[@]}" E2E_CHILD_PREFLIGHT=1 \
			bash "$HERE/run.sh" --preflight-only 2>&1
	}

	for var in "${REQUIRED_VARS[@]}"; do
		expected="missing $var"
		out="$(run_child "$var")"
		rc=$?
		if [ "$rc" -eq 2 ] &&
			printf '%s\n' "$out" | grep -Fqx "$expected" &&
			[ "$(printf '%s\n' "$out" | grep -c '^missing ')" -eq 1 ] &&
			! printf '%s\n' "$out" | grep -q 'PREFLIGHT VARS: PASS'; then
			printf 'PREFLIGHT %s PASS\n' "$var"
		else
			printf 'PREFLIGHT %s FAIL rc=%s\n' "$var" "$rc"
			printf '%s\n' "$out" | sed 's/^/  /' >&2
			failures=1
		fi
	done

	for var in "${KEY_VARS[@]}"; do
		expected="missing $var"
		out="$(run_child "$var" "$var=")"
		rc=$?
		if [ "$rc" -eq 2 ] &&
			printf '%s\n' "$out" | grep -Fqx "$expected" &&
			! printf '%s\n' "$out" | grep -q 'PREFLIGHT VARS: PASS'; then
			printf 'PREFLIGHT %s empty PASS\n' "$var"
		else
			printf 'PREFLIGHT %s empty FAIL rc=%s\n' "$var" "$rc"
			printf '%s\n' "$out" | sed 's/^/  /' >&2
			failures=1
		fi
	done

	# A key set that is only partly injected must not be topped up silently.
	out="$(run_child E2E_REALITY_PUBLIC_KEY)"
	rc=$?
	if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -Fqx 'missing E2E_REALITY_PUBLIC_KEY'; then
		printf 'PREFLIGHT key-pair partial PASS\n'
	else
		printf 'PREFLIGHT key-pair partial FAIL rc=%s\n' "$rc"
		printf '%s\n' "$out" | sed 's/^/  /' >&2
		failures=1
	fi

	if [ "$failures" -eq 0 ]; then
		printf 'PREFLIGHT CONTROLS: PASS\n'
		return 0
	fi
	printf 'PREFLIGHT CONTROLS: FAIL\n'
	return 1
}

if [ "$MODE" = negative-preflight ]; then
	negative_preflight || exit 1
	exit 0
fi

preflight || {
	printf 'E2E: FAIL\n' >&2
	exit 2
}
if [ "$MODE" = preflight ]; then
	printf 'E2E PREFLIGHT: PASS\n'
	exit 0
fi

socks_get() { # $1=out prefix [$2=timeout] -> sets SOCKS_RC / SOCKS_CODE / SOCKS_SIZE
	local max_time="${2:-$TIMEOUT}"
	rm -f "$1.body" "$1.hdr" "$1.out" "$1.err"
	curl -sS --max-time "$max_time" --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
		-o "$1.body" -D "$1.hdr" \
		-w '%{http_code} %{size_download}\n' "$TARGET" \
		>"$1.out" 2>"$1.err"
	SOCKS_RC=$?
	SOCKS_CODE="$(awk '{print $1}' "$1.out" 2>/dev/null)"
	SOCKS_SIZE="$(awk '{print $2}' "$1.out" 2>/dev/null)"
}

# Xray opens its inbound and SOCKS sockets before REALITY has finished
# settling, so a request immediately after `wait_port` can be lost. Poll the
# same pair with backoff instead of restarting it: a restart resets the very
# initialization the wait is meant to absorb. Callers still assert their own
# request afterwards; this only removes startup noise from a functional check.
wait_reality() { # $1=output prefix [$2=attempts]
	local prefix="$1" attempts="${2:-8}" attempt
	for attempt in $(seq 1 "$attempts"); do
		socks_get "$WORKDIR/$prefix-$attempt" 8
		if [ "$SOCKS_CODE" = "200" ] &&
			grep -qx "$TARGET_MARKER" "$WORKDIR/$prefix-$attempt.body" 2>/dev/null; then
			return 0
		fi
		printf 'XRAY %s attempt %s not ready yet; retrying\n' "$prefix" "$attempt" >&2
		[ "$attempt" -eq "$attempts" ] || sleep 3
	done
	return 1
}

# ---------------------------------------------------------------------- stack
printf 'E2E: START\n'

WEB_PORT="$BACKEND_PORT" E2E_INNER_PATH=/inner setsid python3 "$HERE/site-backend.py" \
	>"$WORKDIR/backend.log" 2>&1 </dev/null &
BACKEND_PID=$!

TARGET_PORT="$TARGET_PORT" TARGET_COUNT_FILE="$TARGET_COUNT" \
	setsid python3 "$HERE/backend-counting.py" \
	>"$WORKDIR/target.log" 2>&1 </dev/null &
TARGET_PID=$!

if ! ip -o -4 addr show dev lo 2>/dev/null | grep -q " $SMOKE_TARGET_IP/"; then
	ip addr add "$SMOKE_TARGET_IP/32" dev lo 2>"$WORKDIR/smoke-ip.err" || {
		cat "$WORKDIR/smoke-ip.err" >&2
		fatal "could not add $SMOKE_TARGET_IP to lo for the naive smoke target"
	}
	SMOKE_IP_ADDED=1
fi
TARGET_BIND="$SMOKE_TARGET_IP" TARGET_PORT="$SMOKE_TARGET_PORT" \
	TARGET_COUNT_FILE="$SMOKE_TARGET_COUNT" \
	setsid python3 "$HERE/backend-counting.py" \
	>"$WORKDIR/smoke-target.log" 2>&1 </dev/null &
SMOKE_TARGET_PID=$!

XDG_DATA_HOME="$WORKDIR/data" setsid "$CADDY_BIN" run \
	--config "$WORKDIR/Caddyfile" --adapter caddyfile \
	>"$WORKDIR/caddy.log" 2>&1 </dev/null &
CADDY_PID=$!

for port in "$REALITY_PORT" "$BACKEND_PORT" "$TARGET_PORT" "$SMOKE_TARGET_PORT"; do
	wait_port "$port" 30 || {
		printf 'FATAL: nothing is listening on %s after 30s\n' "$port" >&2
		tail -n 20 "$WORKDIR/caddy.log" >&2
		tail -n 20 "$WORKDIR/backend.log" >&2
		tail -n 20 "$WORKDIR/target.log" >&2
		tail -n 20 "$WORKDIR/smoke-target.log" >&2
		printf 'E2E: FAIL\n' >&2
		exit 2
	}
done
sleep 1

CA="$WORKDIR/data/caddy/pki/authorities/local/root.crt"
[ -f "$CA" ] || fatal "Caddy internal CA not found at $CA"

# Prove the counting fixture itself works before using a zero delta as
# evidence. This direct request never crosses the proxy and is discarded.
if ! curl -fsS --noproxy '*' --max-time "$TIMEOUT" \
	"http://127.0.0.1:$TARGET_PORT/counter-control" \
	-o "$WORKDIR/target-control.body" 2>"$WORKDIR/target-control.err"; then
	fatal "the counting target did not answer a direct request"
fi
if ! grep -qx "$NAIVE_TARGET_MARKER" "$WORKDIR/target-control.body" ||
	[ "$(records "$TARGET_COUNT")" -ne 1 ]; then
	fatal "the counting target did not record exactly one direct request"
fi
: >"$TARGET_COUNT"
printf 'COUNTER CONTROL: PASS\n'

# --------------------------------------------------------------------- E2E-03
# The PROXY v2 capture needs the layer4 upstream port, so it runs before the
# real Xray server binds it. Starting the stub and then the one real server
# avoids a stop/restart cycle that can leave the REALITY listener delayed.
setsid python3 "$HERE/proxyv2.py" --port "$SERVER_PORT" --sni "$SNI" \
	--out "$WORKDIR/proxyv2.jsonl" --connections 1 \
	>"$WORKDIR/proxyv2.log" 2>&1 </dev/null &
STUB_PID=$!
wait_port "$SERVER_PORT" 20 || fatal "the PROXY v2 stub did not start"

timeout "$TIMEOUT" openssl s_client -connect "127.0.0.1:$REALITY_PORT" \
	-servername "$SNI" -alpn h2 </dev/null >"$WORKDIR/proxyv2-client.out" 2>&1
wait_records "$WORKDIR/proxyv2.jsonl" 1 >/dev/null

proxy_ok=1
check_field() { # $1=label $2=actual $3=expected
	if [ "$2" = "$3" ]; then
		printf 'PROXY %s OK\n' "$1"
		return 0
	fi
	printf 'PROXY %s MISMATCH actual=%s expected=%s\n' "$1" "$2" "$3"
	return 1
}
if [ "$(records "$WORKDIR/proxyv2.jsonl")" -ne 1 ]; then
	printf 'PROXY records MISMATCH actual=%s expected=1\n' "$(records "$WORKDIR/proxyv2.jsonl")"
	proxy_ok=0
else
	check_field signature "$(json_field "$WORKDIR/proxyv2.jsonl" signature_hex)" \
		"0d 0a 0d 0a 00 0d 0a 51 55 49 54 0a" || proxy_ok=0
	check_field version_command "$(json_field "$WORKDIR/proxyv2.jsonl" version_command)" "0x21" || proxy_ok=0
	check_field family_protocol "$(json_field "$WORKDIR/proxyv2.jsonl" family_protocol)" "0x11" || proxy_ok=0
	check_field address_length "$(json_field "$WORKDIR/proxyv2.jsonl" address_length)" "12" || proxy_ok=0
	check_field destination "$(json_field "$WORKDIR/proxyv2.jsonl" destination)" "$PROXYV2_DEST" || proxy_ok=0
	check_field client_hello "$(json_field "$WORKDIR/proxyv2.jsonl" client_hello)" "True" || proxy_ok=0
	check_field sni_present "$(json_field "$WORKDIR/proxyv2.jsonl" sni_present)" "True" || proxy_ok=0
	case "$(json_field "$WORKDIR/proxyv2.jsonl" source)" in
	127.0.0.1:[0-9]*) printf 'PROXY source OK\n' ;;
	*)
		printf 'PROXY source MISMATCH actual=%s expected=127.0.0.1:<port>\n' \
			"$(json_field "$WORKDIR/proxyv2.jsonl" source)"
		proxy_ok=0
		;;
	esac
fi
if [ "$proxy_ok" -eq 1 ]; then item E2E-03 PASS; else
	item E2E-03 FAIL
	cat "$WORKDIR/proxyv2.jsonl" >&2 2>/dev/null
fi

# ------------------------------------------------------------------------ E2E-07
# Decision (2026-11-07): an unmatched or absent SNI is REJECTED. The handshake
# fails, no certificate is presented, and the connection never reaches the
# layer4 upstream. This is the posture the delivery file already has -- it
# carries no catch-all site and no `tls` fallback for unmatched names -- so the
# assertion below freezes measured behaviour rather than inventing it. A change
# that starts handing out a certificate turns this item red.
#
# Measured while the PROXY v2 stub is still the layer4 upstream, so each record
# delta is observable rather than inferred from the absence of a log line.
#
# The empty-SNI case is a documented client limitation: the probe's TLS client
# refuses to build a zero-length server_name extension, so nothing leaves the
# process. It is asserted as that limitation, never as a server-side verdict.
python3 "$HERE/probe-sni.py" \
	--connect-host 127.0.0.1 --connect-port "$REALITY_PORT" \
	--count-file "$WORKDIR/proxyv2.jsonl" --timeout "$TIMEOUT" \
	>"$WORKDIR/e2e07-baseline.jsonl" 2>"$WORKDIR/e2e07-baseline.err" ||
	fatal "the unknown/empty/absent SNI baseline could not be measured"
baseline_count="$(grep -c '^E2E-07 BASELINE ' "$WORKDIR/e2e07-baseline.jsonl" 2>/dev/null || true)"
[ "$baseline_count" -eq 3 ] ||
	fatal "expected three E2E-07 baseline records, got ${baseline_count:-0}"
cat "$WORKDIR/e2e07-baseline.jsonl"

e2e07_ok=1
sni_case_ok() { # $1=line $2=case name $3=expected error fragment
	local handshake delta field
	handshake="$(baseline_field "$WORKDIR/e2e07-baseline.jsonl" "$1" handshake)"
	delta="$(baseline_field "$WORKDIR/e2e07-baseline.jsonl" "$1" layer4_records_delta)"
	if [ "$handshake" != "False" ]; then
		printf 'E2E-07 %s MISMATCH handshake=%s expected=False\n' "$2" "$handshake"
		e2e07_ok=0
	fi
	if [ "$delta" != "0" ]; then
		printf 'E2E-07 %s MISMATCH layer4_records_delta=%s expected=0\n' "$2" "$delta"
		e2e07_ok=0
	fi
	# A rejected handshake presents no certificate at all. Any of these fields
	# becoming non-empty means the listener started answering instead.
	for field in subject san issuer sha256; do
		if [ -n "$(baseline_field "$WORKDIR/e2e07-baseline.jsonl" "$1" "$field")" ]; then
			printf 'E2E-07 %s MISMATCH %s is set; a rejected handshake presents no certificate\n' \
				"$2" "$field"
			e2e07_ok=0
		fi
	done
	if ! baseline_field "$WORKDIR/e2e07-baseline.jsonl" "$1" error | grep -qi -- "$3"; then
		printf 'E2E-07 %s MISMATCH error lacks %s: %s\n' "$2" "$3" \
			"$(baseline_field "$WORKDIR/e2e07-baseline.jsonl" "$1" error)"
		e2e07_ok=0
	fi
}

sni_case_ok 1 unknown alert
sni_case_ok 2 empty servername
sni_case_ok 3 absent alert

if [ "$e2e07_ok" -eq 1 ]; then
	printf 'E2E-07 POSTURE: reject\n'
	item E2E-07 PASS
else
	item E2E-07 FAIL
	cat "$WORKDIR/e2e07-baseline.jsonl" >&2
fi

stop_pid "$STUB_PID"
STUB_PID=""
for _ in $(seq 1 40); do
	port_busy "$SERVER_PORT" || break
	sleep 0.25
done
port_busy "$SERVER_PORT" && fatal "the PROXY v2 stub did not release $SERVER_PORT"

setsid "$XRAY_SERVER" run -c "$WORKDIR/xray-server.json" \
	>"$WORKDIR/xray-server.log" 2>&1 </dev/null &
SERVER_PID=$!
setsid "$XRAY_CLIENT" run -c "$WORKDIR/xray-client.json" \
	>"$WORKDIR/xray-client.log" 2>&1 </dev/null &
CLIENT_PID=$!
for port in "$SERVER_PORT" "$SOCKS_PORT"; do
	wait_port "$port" 30 || fatal "nothing is listening on $port after 30s"
done
wait_reality xray-warmup ||
	fatal "the Xray pair did not answer within the readiness window"
printf 'XRAY WARMUP: PASS\n'

start_client() { # $1=config $2=log
	stop_pid "$CLIENT_PID"
	CLIENT_PID=""
	for _ in $(seq 1 20); do
		port_busy "$SOCKS_PORT" || break
		sleep 0.25
	done
	setsid "$XRAY_CLIENT" run -c "$1" >"$2" 2>&1 </dev/null &
	CLIENT_PID=$!
	wait_port "$SOCKS_PORT" 20 || return 1
	return 0
}

log_from() { # $1=log $2=byte offset
	tail -c +"$(( $2 + 1 ))" "$1" 2>/dev/null
}

naive_probe() { # $1=json output $2=auth mode $3=expect mode $4=target
	python3 "$HERE/naive-tunnel.py" \
		--connect-host 127.0.0.1 --connect-port "$REALITY_PORT" \
		--sni a.test --ca "$CA" --target "$4" \
		--auth "$2" --expect "$3" --user "$USER_TOKEN" --password "$PASS_TOKEN" \
		--timeout "$TIMEOUT" >"$1" 2>"$1.err"
}

# --------------------------------------------------------------------- E2E-01
inner_ok=0
for attempt in 1 2 3; do
	caddy_offset=$(wc -c <"$WORKDIR/caddy.log" 2>/dev/null || printf '0')
	socks_get "$WORKDIR/inner-$attempt"
	attempt_ok=1
	[ "$SOCKS_RC" -eq 0 ] || attempt_ok=0
	[ "$SOCKS_CODE" = "200" ] || attempt_ok=0
	[ "${SOCKS_SIZE:-0}" -gt 0 ] 2>/dev/null || attempt_ok=0
	grep -qx "$TARGET_MARKER" "$WORKDIR/inner-$attempt.body" 2>/dev/null || attempt_ok=0
	grep -qi '^x-site: e2e-inner' "$WORKDIR/inner-$attempt.hdr" 2>/dev/null || attempt_ok=0
	if grep -q 'alert 40' "$WORKDIR/xray-client.log" 2>/dev/null; then attempt_ok=0; fi
	if log_from "$WORKDIR/caddy.log" "$caddy_offset" | grep -q 'layer4.*EOF'; then attempt_ok=0; fi
	if [ "$attempt_ok" -eq 1 ]; then
		inner_ok=1
		cp "$WORKDIR/inner-$attempt.body" "$WORKDIR/inner.body"
		cp "$WORKDIR/inner-$attempt.hdr" "$WORKDIR/inner.hdr"
		break
	fi
	printf '  E2E-01 attempt %s failed; retrying\n' "$attempt" >&2
	[ "$attempt" -eq 3 ] || sleep 2
done
if [ "$inner_ok" -eq 1 ]; then
	item E2E-01 PASS
else
	item E2E-01 FAIL
	printf '  curl exit=%s code=%s size=%s\n' "$SOCKS_RC" "${SOCKS_CODE:-<none>}" "${SOCKS_SIZE:-<none>}" >&2
	head -c 400 "$WORKDIR/inner-3.body" >&2 2>/dev/null
	cat "$WORKDIR/inner-3.err" >&2 2>/dev/null
	tail -n 20 "$WORKDIR/xray-client.log" >&2 2>/dev/null
fi

# --------------------------------------------------------------------- E2E-05
naive_count_before="$(records "$TARGET_COUNT")"
naive_probe "$WORKDIR/naive-wrong.json" wrong decoy "localhost:$TARGET_PORT"
naive_wrong_rc=$?
naive_count_after="$(records "$TARGET_COUNT")"
naive_wrong_ok=1
[ "$naive_wrong_rc" -eq 0 ] || naive_wrong_ok=0
[ "$naive_count_before" = "$naive_count_after" ] || naive_wrong_ok=0
grep -q '"decoy_page": true' "$WORKDIR/naive-wrong.json" 2>/dev/null || naive_wrong_ok=0
grep -q '"target_marker": false' "$WORKDIR/naive-wrong.json" 2>/dev/null || naive_wrong_ok=0
if [ "$naive_wrong_ok" -eq 1 ]; then
	item E2E-05a PASS
else
	item E2E-05a FAIL
	printf '  counter before=%s after=%s rc=%s\n' \
		"$naive_count_before" "$naive_count_after" "$naive_wrong_rc" >&2
	cat "$WORKDIR/naive-wrong.json" >&2 2>/dev/null
	cat "$WORKDIR/naive-wrong.json.err" >&2 2>/dev/null
fi

naive_count_before="$(records "$TARGET_COUNT")"
naive_probe "$WORKDIR/naive-missing.json" missing decoy "localhost:$TARGET_PORT"
naive_missing_rc=$?
naive_count_after="$(records "$TARGET_COUNT")"
naive_missing_ok=1
[ "$naive_missing_rc" -eq 0 ] || naive_missing_ok=0
[ "$naive_count_before" = "$naive_count_after" ] || naive_missing_ok=0
grep -q '"decoy_page": true' "$WORKDIR/naive-missing.json" 2>/dev/null || naive_missing_ok=0
grep -q '"target_marker": false' "$WORKDIR/naive-missing.json" 2>/dev/null || naive_missing_ok=0
if [ "$naive_missing_ok" -eq 1 ]; then
	item E2E-05b PASS
else
	item E2E-05b FAIL
	printf '  counter before=%s after=%s rc=%s\n' \
		"$naive_count_before" "$naive_count_after" "$naive_missing_rc" >&2
	cat "$WORKDIR/naive-missing.json" >&2 2>/dev/null
	cat "$WORKDIR/naive-missing.json.err" >&2 2>/dev/null
fi

naive_count_before="$(records "$TARGET_COUNT")"
caddy_offset=$(wc -c <"$WORKDIR/caddy.log" 2>/dev/null || printf '0')
naive_probe "$WORKDIR/naive-private.json" correct not-target "127.0.0.1:$TARGET_PORT"
naive_private_rc=$?
naive_count_after="$(records "$TARGET_COUNT")"
sleep 1
caddy_delta="$(log_from "$WORKDIR/caddy.log" "$caddy_offset")"
naive_private_ok=1
[ "$naive_private_rc" -eq 0 ] || naive_private_ok=0
[ "$naive_count_before" = "$naive_count_after" ] || naive_private_ok=0
grep -q '"target_marker": false' "$WORKDIR/naive-private.json" 2>/dev/null || naive_private_ok=0
printf '%s\n' "$caddy_delta" | grep -q 'no allowed IP addresses for 127.0.0.1' ||
	naive_private_ok=0
printf '%s\n' "$caddy_delta" | grep -q '"status":403' ||
	naive_private_ok=0
if ! grep -q '"decoy_page": true' "$WORKDIR/naive-private.json" 2>/dev/null &&
	! grep -q '"body_bytes": 0' "$WORKDIR/naive-private.json" 2>/dev/null; then
	naive_private_ok=0
fi
if [ "$naive_private_ok" -eq 1 ]; then
	item E2E-05c PASS
else
	item E2E-05c FAIL
	printf '  counter before=%s after=%s rc=%s\n' \
		"$naive_count_before" "$naive_count_after" "$naive_private_rc" >&2
	cat "$WORKDIR/naive-private.json" >&2 2>/dev/null
	cat "$WORKDIR/naive-private.json.err" >&2 2>/dev/null
	printf '%s\n' "$caddy_delta" | tail -n 20 >&2
fi

# --------------------------------------------------------------------- E2E-02
cert_ok=1
rm -f "$WORKDIR/cert-probe.json"
: >"$WORKDIR/cert-probe.log"
probe_ready=0
for attempt in 1 2 3; do
	if python3 "$HERE/probe-cert.py" fetch --connect "127.0.0.1:$REALITY_PORT" \
		--sni "$SNI" --alpn h2 --timeout 30 --out "$WORKDIR/cert-probe.json" \
		>>"$WORKDIR/cert-probe.log" 2>&1; then
		probe_ready=1
		break
	fi
	printf 'CERT probe attempt %s failed; retrying\n' "$attempt" >&2
	[ "$attempt" -eq 3 ] || sleep 2
done
if [ "$probe_ready" -ne 1 ]; then
	cert_ok=0
	printf '  probe through the listener failed:\n' >&2
	sed 's/^/    /' "$WORKDIR/cert-probe.log" >&2
fi
for index in 1 2 3; do
	fetched=0
	for attempt in 1 2 3; do
		if python3 "$HERE/probe-cert.py" fetch --connect "$DEST" \
			--sni "$SNI" --alpn h2 --timeout 30 \
			--out "$WORKDIR/cert-direct-$index.json" \
			>>"$WORKDIR/cert-probe.log" 2>&1; then
			fetched=1
			break
		fi
		printf '  direct fetch %s of %s attempt %s failed; retrying\n' \
			"$index" "$DEST" "$attempt" >&2
		[ "$attempt" -eq 3 ] || sleep 2
	done
	if [ "$fetched" -ne 1 ]; then
		cert_ok=0
		printf '  direct fetch %s of %s failed after three attempts\n' "$index" "$DEST" >&2
		tail -n 5 "$WORKDIR/cert-probe.log" >&2
	fi
done
if [ "$cert_ok" -eq 1 ]; then
	if ! python3 "$HERE/probe-cert.py" compare --probe "$WORKDIR/cert-probe.json" \
		--expected "$WORKDIR/cert-direct-1.json" \
		--expected "$WORKDIR/cert-direct-2.json" \
		--expected "$WORKDIR/cert-direct-3.json" \
		>"$WORKDIR/cert-compare.log" 2>&1; then
		cert_ok=0
	fi
	sed 's/^/  /' "$WORKDIR/cert-compare.log" >&2
fi
if [ "$cert_ok" -eq 1 ]; then item E2E-02 PASS; else
	item E2E-02 FAIL
	printf '  probe cert: %s\n' "$(tr -d '\n' <"$WORKDIR/cert-probe.json" 2>/dev/null)" >&2
fi

# --------------------------------------------------------------------- E2E-04
baseline_ok=0
for baseline_attempt in 1 2 3; do
	socks_get "$WORKDIR/baseline-$baseline_attempt"
	if [ "$SOCKS_CODE" = "200" ] &&
		grep -qx "$TARGET_MARKER" "$WORKDIR/baseline-$baseline_attempt.body" 2>/dev/null; then
		printf 'POSITIVE CONTROL: PASS\n'
		baseline_ok=1
		break
	fi
	printf 'POSITIVE CONTROL: attempt %s failed code=%s\n' \
		"$baseline_attempt" "${SOCKS_CODE:-<none>}"
	[ "$baseline_attempt" -eq 3 ] || sleep 3
done
if [ "$baseline_ok" -ne 1 ]; then
	printf 'POSITIVE CONTROL: FAIL code=%s\n' "${SOCKS_CODE:-<none>}"
fi

E2E_XRAY_CLIENT_BIN="$XRAY_CLIENT" \
	E2E_REALITY_UUID="$UUID" \
	E2E_REALITY_PUBLIC_KEY="$PUBLIC_KEY" \
	E2E_REALITY_SHORT_ID="$SHORT_ID" \
	bash "$HERE/negative-controls.sh" "$WORKDIR/xray-client.json" "$WORKDIR/controls" \
	>"$WORKDIR/controls.list" 2>"$WORKDIR/controls.err" ||
	fatal "could not render the negative controls (see $WORKDIR/controls.err)"

run_control() { # $1=item id $2=control name
	local id="$1" name="$2" config log server_offset server_delta
	config="$WORKDIR/controls/client-$name.json"
	log="$WORKDIR/control-$name.log"
	if [ "$baseline_ok" -ne 1 ]; then
		item "$id" FAIL
		printf '  the positive control failed in the same run; the negative control is not attributable\n' >&2
		return
	fi
	server_offset=$(wc -c <"$WORKDIR/xray-server.log" 2>/dev/null || printf '0')
	start_client "$config" "$log" || {
		item "$id" FAIL
		printf '  the %s client never listened on %s\n' "$name" "$SOCKS_PORT" >&2
		tail -n 10 "$log" >&2
		return
	}
	# A rejected UUID can spend longer than the ordinary 25s budget in the
	# client's REALITY retry loop before the server names the rejection.
	socks_get "$WORKDIR/control-$name" "$CONTROL_TIMEOUT"
	local started=1
	kill -0 "$CLIENT_PID" 2>/dev/null || started=0
	local marker_seen=0
	grep -qx "$TARGET_MARKER" "$WORKDIR/control-$name.body" 2>/dev/null && marker_seen=1
	# A wrong UUID is rejected by the VLESS server after the REALITY handshake
	# succeeds, so the failure is named in the server log, not the client log.
	# A wrong publicKey or shortId fails earlier and is named by the client.
	# Both windows are scoped to this control, never the whole log.
	local classified=0
	grep -qiE 'reality|handshake|tls|EOF|reset|closed|rejected|invalid' "$log" 2>/dev/null &&
		classified=1
	server_delta="$(log_from "$WORKDIR/xray-server.log" "$server_offset")"
	if printf '%s\n' "$server_delta" |
		grep -qiE 'reality|handshake|tls|EOF|reset|closed|rejected|invalid'; then
		classified=1
	fi
	if [ "$started" -eq 1 ] && [ "$SOCKS_RC" -ne 0 ] && [ "$marker_seen" -eq 0 ] && [ "$classified" -eq 1 ]; then
		item "$id" PASS
	else
		item "$id" FAIL
		printf '  control=%s curl_exit=%s code=%s marker=%s client_alive=%s log_classified=%s\n' \
			"$name" "$SOCKS_RC" "${SOCKS_CODE:-<none>}" "$marker_seen" "$started" "$classified" >&2
		tail -n 10 "$log" >&2
		printf '%s\n' "$server_delta" | tail -n 10 >&2
	fi
}

run_control E2E-04a uuid
run_control E2E-04b public_key
run_control E2E-04c short_id

start_client "$WORKDIR/xray-client.json" "$WORKDIR/xray-client.log" ||
	fatal "the passing client did not come back for the closing positive control"
wait_reality closing-warmup ||
	fatal "the Xray pair did not answer before the closing positive control"
closing_ok=0
for closing_attempt in 1 2 3; do
	socks_get "$WORKDIR/closing-$closing_attempt" 15
	if [ "$SOCKS_CODE" = "200" ] &&
		grep -qx "$TARGET_MARKER" "$WORKDIR/closing-$closing_attempt.body" 2>/dev/null; then
		printf 'POSITIVE CONTROL CLOSING: PASS\n'
		closing_ok=1
		break
	fi
	printf 'POSITIVE CONTROL CLOSING: attempt %s failed code=%s\n' \
		"$closing_attempt" "${SOCKS_CODE:-<none>}"
	[ "$closing_attempt" -eq 3 ] || sleep 3
done
if [ "$closing_ok" -ne 1 ]; then
	printf 'POSITIVE CONTROL CLOSING: FAIL\n'
fi

# --------------------------------------------------------------------- E2E-08
# Stability is measured, not inferred from one lucky request. Thirty serial and
# eight concurrent requests go through each leg; every request is a fresh
# client unit and the smoke has no retry path. The client counts are
# corroborated on the server side: the reality requests must appear in the site
# backend's request log, and every naive request must be recorded by the
# counting target it tunnels to. A client that bypassed the listener could not
# move both counters.
smoke_ok=1
smoke_reality_expected=$((30 + 8))
smoke_naive_expected=$((30 + 8))
backend_inner_before="$(grep -c '^"GET /inner HTTP/1\.1" 200' "$WORKDIR/backend.log" 2>/dev/null || true)"
backend_inner_before="${backend_inner_before:-0}"
naive_total_before="$(records "$SMOKE_TARGET_COUNT")"

smoke_run() { # $1=leg $2=mode $3=expected request count
	local leg="$1" mode="$2" expected="$3" out rc line
	out="$(E2E_SMOKE_CONNECT_PORT="$REALITY_PORT" \
		E2E_SMOKE_SOCKS_PORT="$SOCKS_PORT" \
		E2E_SMOKE_SNI="a.test" \
		E2E_SMOKE_CA="$CA" \
		E2E_SMOKE_USER="$USER_TOKEN" \
		E2E_SMOKE_PASS="$PASS_TOKEN" \
		E2E_SMOKE_NAIVE_TARGET="$SMOKE_TARGET_IP:$SMOKE_TARGET_PORT" \
		E2E_SMOKE_WORKDIR="$WORKDIR/smoke-$leg-$mode" \
		E2E_TARGET="$TARGET" \
		E2E_TARGET_MARKER="$TARGET_MARKER" \
		bash "$HERE/smoke.sh" "$leg" "$mode" 2>"$WORKDIR/smoke-$leg-$mode.err")"
	rc=$?
	line="$(printf '%s\n' "$out" | grep '^SMOKE ' | tail -n1)"
	if [ -n "$line" ]; then printf '%s\n' "$line"; fi
	if [ "$rc" -ne 0 ] ||
		! printf '%s\n' "$line" | grep -q "count=$expected failures=0"; then
		smoke_ok=0
		printf '  smoke %s/%s rc=%s expected=%s\n' "$leg" "$mode" "$rc" "$expected" >&2
		tail -n 10 "$WORKDIR/smoke-$leg-$mode.err" >&2 2>/dev/null
	fi
}

smoke_run reality serial 30
smoke_run reality concurrent 8
smoke_run naive serial 30
smoke_run naive concurrent 8

backend_inner_after="$(grep -c '^"GET /inner HTTP/1\.1" 200' "$WORKDIR/backend.log" 2>/dev/null || true)"
backend_inner_after="${backend_inner_after:-0}"
naive_total_after="$(records "$SMOKE_TARGET_COUNT")"
smoke_reality_delta=$((backend_inner_after - backend_inner_before))
smoke_naive_delta=$((naive_total_after - naive_total_before))
printf 'SMOKE UPSTREAM reality_requests=%s naive_records=%s\n' \
	"$smoke_reality_delta" "$smoke_naive_delta"
if [ "$smoke_reality_delta" -lt "$smoke_reality_expected" ]; then
	smoke_ok=0
	printf '  the site backend recorded %s of %s reality smoke requests\n' \
		"$smoke_reality_delta" "$smoke_reality_expected" >&2
fi
if [ "$smoke_naive_delta" -lt "$smoke_naive_expected" ]; then
	smoke_ok=0
	printf '  the counting target recorded %s of %s naive smoke requests\n' \
		"$smoke_naive_delta" "$smoke_naive_expected" >&2
fi
if [ "$smoke_ok" -eq 1 ]; then item E2E-08 PASS; else
	item E2E-08 FAIL
	tail -n 5 "$WORKDIR/caddy.log" >&2 2>/dev/null
fi

# ------------------------------------------------------------------- verdict
# Eleven items: E2E-01, 02, 03, 04a/b/c, 05a/b/c, 07, 08. The count is pinned so a
# block that silently stops running cannot still print a green verdict.
if [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq 11 ] && [ "$closing_ok" -eq 1 ]; then
	printf 'E2E: PASS\n'
	exit 0
fi
printf 'E2E: FAIL (passed=%s failed=%s)\n' "$PASSED" "$FAILED"
exit 1
