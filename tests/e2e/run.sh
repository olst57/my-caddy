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
SOCKS_PORT=10802

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

cleanup_all() {
	cleanup "$CLIENT_PID" "$SERVER_PID" "$CADDY_PID" "$BACKEND_PID" "$STUB_PID"
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
		literal_replace 'servers :443 {' 'servers :8443 {' |
		literal_replace ':443, a.test {' ':8443, a.test:8443 {' |
		literal_replace 'b.test {' 'b.test:8443 {' |
		literal_replace '@reality tls sni b.test' "@reality tls sni $SNI" |
		literal_replace 'upstream 127.0.0.1:19098' 'upstream 127.0.0.1:19099' |
		literal_replace 'reverse_proxy 127.0.0.1:8080' 'reverse_proxy 127.0.0.1:18080' \
			>"$overlay" || return 2

	literal_replace 'reverse_proxy 127.0.0.1:18080' 'reverse_proxy 127.0.0.1:8080' <"$overlay" |
		literal_replace 'upstream 127.0.0.1:19099' 'upstream 127.0.0.1:19098' |
		literal_replace "@reality tls sni $SNI" '@reality tls sni b.test' |
		literal_replace 'b.test:8443 {' 'b.test {' |
		literal_replace ':8443, a.test:8443 {' ':443, a.test {' |
		literal_replace 'servers :8443 {' 'servers :443 {' |
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
	for port in "$REALITY_PORT" "$SERVER_PORT" "$BACKEND_PORT" "$SOCKS_PORT"; do
		if port_busy "$port"; then
			fatal "port $port is already in use; this harness needs it free"
		fi
	done

	mkdir -p "$WORKDIR" || fatal "cannot create $WORKDIR"
	rm -f "$WORKDIR"/xray-server.log "$WORKDIR"/xray-client.log "$WORKDIR"/caddy.log \
		"$WORKDIR"/backend.log "$WORKDIR"/*.jsonl "$WORKDIR"/adapt.json "$WORKDIR"/adapt.err
	render_overlay || fatal "overlay render failed"
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

# ---------------------------------------------------------------------- stack
printf 'E2E: START\n'

WEB_PORT="$BACKEND_PORT" E2E_INNER_PATH=/inner setsid python3 "$HERE/site-backend.py" \
	>"$WORKDIR/backend.log" 2>&1 </dev/null &
BACKEND_PID=$!

XDG_DATA_HOME="$WORKDIR/data" setsid "$CADDY_BIN" run \
	--config "$WORKDIR/Caddyfile" --adapter caddyfile \
	>"$WORKDIR/caddy.log" 2>&1 </dev/null &
CADDY_PID=$!

setsid "$XRAY_SERVER" run -c "$WORKDIR/xray-server.json" \
	>"$WORKDIR/xray-server.log" 2>&1 </dev/null &
SERVER_PID=$!

setsid "$XRAY_CLIENT" run -c "$WORKDIR/xray-client.json" \
	>"$WORKDIR/xray-client.log" 2>&1 </dev/null &
CLIENT_PID=$!

for port in "$REALITY_PORT" "$SERVER_PORT" "$BACKEND_PORT" "$SOCKS_PORT"; do
	wait_port "$port" 30 || {
		printf 'FATAL: nothing is listening on %s after 30s\n' "$port" >&2
		tail -n 20 "$WORKDIR/caddy.log" >&2
		tail -n 20 "$WORKDIR/xray-server.log" >&2
		tail -n 20 "$WORKDIR/xray-client.log" >&2
		printf 'E2E: FAIL\n' >&2
		exit 2
	}
done
sleep 1

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

start_server() {
	stop_pid "$SERVER_PID"
	SERVER_PID=""
	setsid "$XRAY_SERVER" run -c "$WORKDIR/xray-server.json" \
		>"$WORKDIR/xray-server.log" 2>&1 </dev/null &
	SERVER_PID=$!
	wait_port "$SERVER_PORT" 20 || return 1
	return 0
}

socks_get() { # $1=out prefix [$2=timeout] -> sets SOCKS_RC / SOCKS_CODE / SOCKS_SIZE
	local max_time="${2:-$TIMEOUT}"
	curl -sS --max-time "$max_time" --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
		-o "$1.body" -D "$1.hdr" \
		-w '%{http_code} %{size_download}\n' "$TARGET" \
		>"$1.out" 2>"$1.err"
	SOCKS_RC=$?
	SOCKS_CODE="$(awk '{print $1}' "$1.out" 2>/dev/null)"
	SOCKS_SIZE="$(awk '{print $2}' "$1.out" 2>/dev/null)"
}

log_from() { # $1=log $2=byte offset
	tail -c +"$(( $2 + 1 ))" "$1" 2>/dev/null
}

# --------------------------------------------------------------------- E2E-01
caddy_offset=$(wc -c <"$WORKDIR/caddy.log" 2>/dev/null || printf '0')
socks_get "$WORKDIR/inner"
inner_ok=1
[ "$SOCKS_RC" -eq 0 ] || inner_ok=0
[ "$SOCKS_CODE" = "200" ] || inner_ok=0
[ "${SOCKS_SIZE:-0}" -gt 0 ] 2>/dev/null || inner_ok=0
grep -qx "$TARGET_MARKER" "$WORKDIR/inner.body" 2>/dev/null || inner_ok=0
grep -qi '^x-site: e2e-inner' "$WORKDIR/inner.hdr" 2>/dev/null || inner_ok=0
if grep -q 'alert 40' "$WORKDIR/xray-client.log" 2>/dev/null; then inner_ok=0; fi
if log_from "$WORKDIR/caddy.log" "$caddy_offset" | grep -q 'layer4.*EOF'; then inner_ok=0; fi
if [ "$inner_ok" -eq 1 ]; then
	item E2E-01 PASS
else
	item E2E-01 FAIL
	printf '  curl exit=%s code=%s size=%s\n' "$SOCKS_RC" "${SOCKS_CODE:-<none>}" "${SOCKS_SIZE:-<none>}" >&2
	head -c 400 "$WORKDIR/inner.body" >&2 2>/dev/null
	cat "$WORKDIR/inner.err" >&2 2>/dev/null
	tail -n 20 "$WORKDIR/xray-client.log" >&2 2>/dev/null
fi

# --------------------------------------------------------------------- E2E-02
cert_ok=1
if ! python3 "$HERE/probe-cert.py" fetch --connect "127.0.0.1:$REALITY_PORT" \
	--sni "$SNI" --alpn h2 --out "$WORKDIR/cert-probe.json" \
	>"$WORKDIR/cert-probe.log" 2>&1; then
	cert_ok=0
	printf '  probe through the listener failed:\n' >&2
	sed 's/^/    /' "$WORKDIR/cert-probe.log" >&2
fi
for index in 1 2 3; do
	if ! python3 "$HERE/probe-cert.py" fetch --connect "$DEST" \
		--sni "$SNI" --alpn h2 --out "$WORKDIR/cert-direct-$index.json" \
		>>"$WORKDIR/cert-probe.log" 2>&1; then
		cert_ok=0
		printf '  direct fetch %s of %s failed\n' "$index" "$DEST" >&2
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

# --------------------------------------------------------------------- E2E-03
stop_pid "$SERVER_PID"
SERVER_PID=""
stop_pid "$CLIENT_PID"
CLIENT_PID=""
for _ in $(seq 1 20); do port_busy "$SERVER_PORT" || break; sleep 0.25; done

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

stop_pid "$STUB_PID"
STUB_PID=""
start_server || fatal "the Xray server did not come back on $SERVER_PORT"

# --------------------------------------------------------------------- E2E-04
start_client "$WORKDIR/xray-client.json" "$WORKDIR/xray-client.log" ||
	fatal "the passing client did not come back on $SOCKS_PORT"
socks_get "$WORKDIR/baseline"
if [ "$SOCKS_CODE" = "200" ] && grep -qx "$TARGET_MARKER" "$WORKDIR/baseline.body" 2>/dev/null; then
	printf 'POSITIVE CONTROL: PASS\n'
	baseline_ok=1
else
	printf 'POSITIVE CONTROL: FAIL code=%s\n' "${SOCKS_CODE:-<none>}"
	baseline_ok=0
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
socks_get "$WORKDIR/closing"
closing_ok=1
if [ "$SOCKS_CODE" = "200" ] && grep -qx "$TARGET_MARKER" "$WORKDIR/closing.body" 2>/dev/null; then
	printf 'POSITIVE CONTROL CLOSING: PASS\n'
else
	printf 'POSITIVE CONTROL CLOSING: FAIL\n'
	closing_ok=0
fi

# ------------------------------------------------------------------- verdict
if [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq 6 ] && [ "$closing_ok" -eq 1 ]; then
	printf 'E2E: PASS\n'
	exit 0
fi
printf 'E2E: FAIL (passed=%s failed=%s)\n' "$PASSED" "$FAILED"
exit 1
