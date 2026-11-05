#!/usr/bin/env bash
# Runtime coexistence test: one Caddy process, one :443, three roles.
#
# The offline verifier (scripts/verify.sh) reads configs. This test runs the
# built binary and asserts the behaviour those configs are supposed to produce,
# with a control next to every assertion:
#
#   CO-1  site leg      GET https://a.test/ -> 200, X-Site: v4, SITE-MARKER-v4,
#                       HTTP/2 (not 3), no Alt-Svc, no Proxy-Authenticate.
#   CO-2  REALITY leg   openssl s_client -servername b.test fails, and the
#                       upstream stub recorded exactly one connection carrying
#                       a PROXY v2 header followed by an untouched ClientHello
#                       with SNI b.test. Failure + record is what proves Caddy
#                       forwarded instead of terminating.
#   CO-3  unknown SNI   -servername unknown.test fails and adds NO record to the
#                       stub: the layer4 matcher did not claim it.
#   CO-4  naive leg     a CONNECT with Proxy-Authorization opens a real tunnel
#                       (TLS to the target inside it, 200, non-empty body), over
#                       HTTP/1.1 on the proxy hop.
#   CO-5  decoy control CONNECT to the probe_resistance domain returns the
#                       decoy page, not a tunnel. This is why CO-4's target
#                       must not be that domain, and it proves the control in
#                       CO-3 is not vacuous.
#   CO-6  h2 leg        the same naive entry point over HTTP/2 on the proxy hop:
#                       curl must report `CONNECT tunnel: HTTP/2 negotiated`,
#                       then a 200 and a non-empty body. CO-4 only proves the
#                       HTTP/1.1 leg, so without this the h2 claim in README
#                       would be untested.
#   CO-7  no QUIC       nothing may be listening on UDP :443 while the stack
#                       runs, and TCP :443 must still be listening in the same
#                       sample. CO-1 only proves no Alt-Svc header was emitted;
#                       this asserts the stronger claim the config makes -- the
#                       QUIC listener is never created. The TCP half is the
#                       control: a dead Caddy also has no UDP listener.
#   CO-8  decoy≠target  the `probe_resistance` domain must differ from the host
#                       the tunnel is asked to reach. In v0.4.0 they were the
#                       same host and the tunnelled request died with code=000 /
#                       CURL_EXIT=35, because the decoy answered instead of a
#                       tunnel. Equal or empty values fail the item.
#
# The overlay Caddyfile is DERIVED from deploy/Caddyfile by substituting the two
# credential placeholders and nothing else; the script proves that by reversing
# the substitution and diffing against the delivery file. tests/ is never
# imported by the config under test.
#
# Usage: bash tests/coexist/run.sh <repo-root>
# Env:   CADDY_BIN (dist/caddy-linux-amd64), WORKDIR (.gate/coexist),
#        CO_TARGET (www.apple.com:443), CO_TIMEOUT (25)
# Needs: root (bind :443), curl, openssl, python3, ss
set -uo pipefail

REPO_ROOT="${1:?usage: run.sh <repo-root>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CADDY_BIN="${CADDY_BIN:-$REPO_ROOT/dist/caddy-linux-amd64}"
WORKDIR="${WORKDIR:-$REPO_ROOT/.gate/coexist}"
TARGET="${CO_TARGET:-www.apple.com:443}"
TARGET_HOST="${TARGET%%:*}"
TIMEOUT="${CO_TIMEOUT:-25}"

USER_TOKEN="coexist-user-$RANDOM"
PASS_TOKEN="coexist-pass-$RANDOM"

PASSED=0
FAILED=0
CADDY_PID=""
STUB_PID=""
BACKEND_PID=""

item() {
	printf 'ITEM %s %s\n' "$1" "$2"
	case "$2" in
	PASS) PASSED=$((PASSED + 1)) ;;
	*) FAILED=$((FAILED + 1)) ;;
	esac
}

stop_pid() {
	local pid="$1"
	[ -n "$pid" ] || return 0
	kill "$pid" 2>/dev/null
	for _ in $(seq 1 20); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.25
	done
	kill -9 "$pid" 2>/dev/null
	return 0
}

cleanup() {
	stop_pid "$CADDY_PID"
	stop_pid "$STUB_PID"
	stop_pid "$BACKEND_PID"
}
trap cleanup EXIT

records() {
	if [ -f "$WORKDIR/upstream.jsonl" ]; then
		# `grep -c` prints `0` and exits 1 on an empty file. Without the
		# `|| true` the `||` branch would append a second `0` and every
		# numeric comparison on this value would fail with
		# "integer expression expected".
		local n
		n="$(grep -c . "$WORKDIR/upstream.jsonl" 2>/dev/null || true)"
		printf '%s\n' "${n:-0}"
	else
		printf '0\n'
	fi
}

# Wait until the stub has recorded exactly $1 connections, then print the count.
wait_records() {
	local want="$1" now
	for _ in $(seq 1 40); do
		now="$(records)"
		[ "$now" -ge "$want" ] && break
		sleep 0.25
	done
	records
}

port_busy() {
	ss -ltn 2>/dev/null | grep -q ":$1 "
}

# Print the first argument of the active probe_resistance directive, or nothing.
# Comment prose above the directive also mentions the keyword, so strip comments
# before matching; a line that is only a comment must never be parsed.
decoy_domain() {
	sed -e 's/#.*$//' "$REPO_ROOT/deploy/Caddyfile" |
		awk '$1 == "probe_resistance" { print $2; exit }'
}

# ------------------------------------------------------------------ preflight
mkdir -p "$WORKDIR"
rm -f "$WORKDIR/upstream.jsonl" "$WORKDIR"/*.log "$WORKDIR"/*.hdr "$WORKDIR"/*.body

for tool in curl openssl python3 ss; do
	command -v "$tool" >/dev/null || {
		printf 'FATAL: %s not found\n' "$tool" >&2
		printf 'COEXIST: FAIL\n'
		exit 2
	}
done
[ -x "$CADDY_BIN" ] || {
	printf 'FATAL: no executable Caddy at %s\n' "$CADDY_BIN" >&2
	printf 'COEXIST: FAIL\n'
	exit 2
}
[ -f "$REPO_ROOT/deploy/Caddyfile" ] || {
	printf 'FATAL: deploy/Caddyfile missing\n' >&2
	printf 'COEXIST: FAIL\n'
	exit 2
}
for p in 443 19098 8080; do
	if port_busy "$p"; then
		printf 'FATAL: port %s is already in use; this test needs it free\n' "$p" >&2
		printf 'COEXIST: FAIL\n'
		exit 2
	fi
done

# -------------------------------------------------------------------- overlay
OVERLAY="$WORKDIR/Caddyfile"
sed -e "s/<NAIVE_USER>/$USER_TOKEN/" \
	-e "s/<NAIVE_PASSWORD>/$PASS_TOKEN/" \
	"$REPO_ROOT/deploy/Caddyfile" >"$OVERLAY"
sed -e "s/$USER_TOKEN/<NAIVE_USER>/" \
	-e "s/$PASS_TOKEN/<NAIVE_PASSWORD>/" \
	"$OVERLAY" >"$WORKDIR/Caddyfile.reversed"
if ! diff -q "$REPO_ROOT/deploy/Caddyfile" "$WORKDIR/Caddyfile.reversed" >/dev/null; then
	printf 'FATAL: overlay is not a pure credential substitution\n' >&2
	printf 'COEXIST: FAIL\n'
	exit 2
fi
if ! "$CADDY_BIN" adapt --config "$OVERLAY" --adapter caddyfile >"$WORKDIR/adapt.json" 2>"$WORKDIR/adapt.err"; then
	printf 'FATAL: caddy adapt rejected the overlay\n' >&2
	cat "$WORKDIR/adapt.err" >&2
	printf 'COEXIST: FAIL\n'
	exit 2
fi

# ---------------------------------------------------------------------- start
XDG_DATA_HOME="$WORKDIR/data" setsid "$CADDY_BIN" run \
	--config "$OVERLAY" --adapter caddyfile \
	>"$WORKDIR/caddy.log" 2>&1 </dev/null &
CADDY_PID=$!

UPSTREAM_OUT="$WORKDIR/upstream.jsonl" setsid python3 "$HERE/stub-upstream.py" \
	>"$WORKDIR/stub.log" 2>&1 </dev/null &
STUB_PID=$!

WEB_PORT=8080 setsid python3 "$HERE/site-backend.py" >"$WORKDIR/backend.log" 2>&1 </dev/null &
BACKEND_PID=$!

ready=0
for _ in $(seq 1 60); do
	if port_busy 443 && port_busy 19098 && port_busy 8080; then
		ready=1
		break
	fi
	sleep 0.5
done
if [ "$ready" -ne 1 ]; then
	printf 'FATAL: stack did not come up\n' >&2
	tail -20 "$WORKDIR/caddy.log" >&2
	printf 'COEXIST: FAIL\n'
	exit 2
fi
sleep 1

CA="$WORKDIR/data/caddy/pki/authorities/local/root.crt"

# --------------------------------------------------------------------- CO-1
curl -sk --max-time "$TIMEOUT" --resolve a.test:443:127.0.0.1 \
	https://a.test/ -D "$WORKDIR/site.hdr" -o "$WORKDIR/site.body" \
	-w '%{http_version} %{http_code}\n' >"$WORKDIR/site.out" 2>"$WORKDIR/site.err"
site_rc=$?
site_line="$(cat "$WORKDIR/site.out" 2>/dev/null)"
site_ok=1
[ "$site_rc" -eq 0 ] || site_ok=0
[ "$site_line" = "2 200" ] || site_ok=0
grep -qi '^x-site: v4' "$WORKDIR/site.hdr" 2>/dev/null || site_ok=0
grep -qx 'SITE-MARKER-v4' "$WORKDIR/site.body" 2>/dev/null || site_ok=0
grep -qi '^alt-svc:' "$WORKDIR/site.hdr" 2>/dev/null && site_ok=0
grep -qi '^proxy-authenticate:' "$WORKDIR/site.hdr" 2>/dev/null && site_ok=0
if [ "$site_ok" -eq 1 ]; then item CO-1 PASS; else
	item CO-1 FAIL
	printf '  curl exit=%s line=%s\n' "$site_rc" "${site_line:-<none>}" >&2
	cat "$WORKDIR/site.err" >&2
	cat "$WORKDIR/site.hdr" >&2
fi

# --------------------------------------------------------------------- CO-2
timeout "$TIMEOUT" openssl s_client -connect 127.0.0.1:443 -servername b.test \
	</dev/null >"$WORKDIR/reality.out" 2>&1
reality_rc=$?
sleep 0.5
reality_count="$(wait_records 1)"
reality_rec="$(sed -n '1p' "$WORKDIR/upstream.jsonl" 2>/dev/null)"
reality_ok=1
[ "$reality_rc" -ne 0 ] || reality_ok=0
grep -q 'BEGIN CERTIFICATE' "$WORKDIR/reality.out" && reality_ok=0
[ "$reality_count" = "1" ] || reality_ok=0
if [ -n "$reality_rec" ]; then
	printf '%s' "$reality_rec" | grep -q '"proxy_signature": true' || reality_ok=0
	printf '%s' "$reality_rec" | grep -q '"version_command": "0x21"' || reality_ok=0
	printf '%s' "$reality_rec" | grep -q '"family_protocol": "0x11"' || reality_ok=0
	printf '%s' "$reality_rec" | grep -q '"client_hello": true' || reality_ok=0
	printf '%s' "$reality_rec" | grep -q '"sni_present": true' || reality_ok=0
else
	reality_ok=0
fi
if [ "$reality_ok" -eq 1 ]; then item CO-2 PASS; else
	item CO-2 FAIL
	printf '  openssl exit=%s records=%s\n' "$reality_rc" "$reality_count" >&2
	cat "$WORKDIR/upstream.jsonl" >&2
	tail -5 "$WORKDIR/reality.out" >&2
fi

# --------------------------------------------------------------------- CO-3
before="$(records)"
timeout "$TIMEOUT" openssl s_client -connect 127.0.0.1:443 -servername unknown.test \
	</dev/null >"$WORKDIR/unknown.out" 2>&1
unknown_rc=$?
sleep 1
after="$(records)"
unknown_ok=1
[ "$unknown_rc" -ne 0 ] || unknown_ok=0
[ "$after" = "$before" ] || unknown_ok=0
grep -q 'BEGIN CERTIFICATE' "$WORKDIR/unknown.out" && unknown_ok=0
kill -0 "$CADDY_PID" 2>/dev/null || unknown_ok=0
if [ "$unknown_ok" -eq 1 ]; then item CO-3 PASS; else
	item CO-3 FAIL
	printf '  openssl exit=%s records before=%s after=%s\n' \
		"$unknown_rc" "$before" "$after" >&2
	tail -5 "$WORKDIR/unknown.out" >&2
fi

# --------------------------------------------------------------------- CO-4
if [ ! -f "$CA" ]; then
	item CO-4 FAIL
	printf '  Caddy internal root not found at %s\n' "$CA" >&2
else
	python3 "$HERE/naive-tunnel.py" \
		--ca "$CA" --user "$USER_TOKEN" --password "$PASS_TOKEN" \
		--target "$TARGET" --timeout "$TIMEOUT" \
		>"$WORKDIR/tunnel.json" 2>"$WORKDIR/tunnel.err"
	tunnel_rc=$?
	if [ "$tunnel_rc" -eq 0 ]; then item CO-4 PASS; else
		item CO-4 FAIL
		printf '  tunnel client exit=%s\n' "$tunnel_rc" >&2
		cat "$WORKDIR/tunnel.json" >&2
		cat "$WORKDIR/tunnel.err" >&2
	fi
fi

# --------------------------------------------------------------------- CO-5
auth="$(printf '%s:%s' "$USER_TOKEN" "$PASS_TOKEN" | base64 -w0)"
{
	printf 'CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n'
	printf 'Proxy-Authorization: Basic %s\r\n\r\n' "$auth"
	sleep 5
} | timeout "$TIMEOUT" openssl s_client -connect 127.0.0.1:443 \
	-servername a.test -quiet >"$WORKDIR/decoy.out" 2>/dev/null
decoy_ok=1
grep -q 'Hidden Proxy Page' "$WORKDIR/decoy.out" || decoy_ok=0
if [ "$decoy_ok" -eq 1 ]; then item CO-5 PASS; else
	item CO-5 FAIL
	head -10 "$WORKDIR/decoy.out" >&2
fi

# --------------------------------------------------------------------- CO-6
# The same naive entry point, with HTTP/2 on the proxy hop. CO-4 speaks
# HTTP/1.1 only, so on its own it cannot tell whether the h2 claim is true:
# forwardproxy answering h1 while Caddy has h2 enabled for the site leg would
# look identical to CO-4 and to every offline item.
#
# Two details are load-bearing, both measured:
#
#   * `--proxy-cacert`, not `--cacert`: the proxy hop is the connection whose
#     certificate must be verified against Caddy's internal CA.
#   * the proxy URL must name `a.test`, not `127.0.0.1`: the certificate SAN
#     carries a.test only, and connecting by address fails the handshake.
#
# `-k` applies to the origin inside the tunnel, which is a real public host with
# a real certificate chain; disabling verification there keeps this test from
# depending on the runner's trust store. What is asserted is the proxy hop's
# negotiated protocol (from curl's verbose transcript, which names the hop
# explicitly), the tunnel status, and a non-empty body. `%{http_version}` is
# deliberately NOT asserted: it reports the ORIGIN's version, which says
# nothing about the hop under test.
if [ ! -f "$CA" ]; then
	item CO-6 FAIL
	printf '  Caddy internal root not found at %s\n' "$CA" >&2
else
	curl -skv --max-time "$TIMEOUT" --proxy-http2 \
		--proxy "https://$USER_TOKEN:$PASS_TOKEN@a.test:443" \
		--proxy-cacert "$CA" --resolve a.test:443:127.0.0.1 \
		"https://$TARGET/" -D "$WORKDIR/h2.hdr" -o "$WORKDIR/h2.body" \
		-w '%{http_version} %{http_code} %{size_download}\n' \
		>"$WORKDIR/h2.out" 2>"$WORKDIR/h2.err"
	h2_rc=$?
	h2_line="$(cat "$WORKDIR/h2.out" 2>/dev/null)"
	h2_ok=1
	[ "$h2_rc" -eq 0 ] || h2_ok=0
	grep -q 'CONNECT tunnel: HTTP/2 negotiated' "$WORKDIR/h2.err" || h2_ok=0
	[ "$(printf '%s' "$h2_line" | awk '{print $2}')" = 200 ] || h2_ok=0
	[ "$(printf '%s' "$h2_line" | awk '{print $3}')" -gt 0 ] 2>/dev/null || h2_ok=0
	grep -qi '^proxy-authenticate:' "$WORKDIR/h2.hdr" 2>/dev/null && h2_ok=0
	if [ "$h2_ok" -eq 1 ]; then item CO-6 PASS; else
		item CO-6 FAIL
		printf '  h2 proxy curl exit=%s line=%s\n' "$h2_rc" "${h2_line:-<none>}" >&2
		tail -15 "$WORKDIR/h2.err" >&2
	fi
fi

# --------------------------------------------------------------------- CO-7
# The protocol pin is a claim about listeners, not just about headers. With
# `protocols h1 h2` Caddy must not create the QUIC listener at all; CO-1 can
# only see its absence indirectly, as a missing Alt-Svc header on one response.
#
# Measured on hw-gz against this same binary: adding `h3` to the directive
# produces `UNCONN *:443` immediately, and removing it leaves no UDP listener.
# So the filter below is sensitive to the exact regression it is meant to catch.
#
# The TCP assertion is the control. `ss -lun` alone would also pass if Caddy
# had crashed, and the other items run earlier, so "no UDP 443" has to be
# paired with "the TLS listener is still there" in the SAME sample.
quic_udp="$(ss -lun 'sport = :443' 2>/dev/null | tail -n +2)"
tls_tcp="$(ss -lnt 'sport = :443' 2>/dev/null | tail -n +2)"
quic_ok=1
[ -n "$tls_tcp" ] || quic_ok=0
[ -n "$quic_udp" ] && quic_ok=0
kill -0 "$CADDY_PID" 2>/dev/null || quic_ok=0
if [ "$quic_ok" -eq 1 ]; then item CO-7 PASS; else
	item CO-7 FAIL
	printf '  tcp443=[%s]\n' "$(printf '%s' "$tls_tcp" | tr '\n' ';')" >&2
	printf '  udp443=[%s]\n' "$(printf '%s' "$quic_udp" | tr '\n' ';')" >&2
fi

# CO-8: the decoy and the target must be different hosts. Equality is the
# v0.4.0 failure mode, and an unparsed value must fail rather than pass by
# default, so both sides are required to be non-empty first.
DECOY_HOST="$(decoy_domain)"
DECOY_LOWER="$(printf '%s' "$DECOY_HOST" | tr '[:upper:]' '[:lower:]')"
TARGET_LOWER="$(printf '%s' "$TARGET_HOST" | tr '[:upper:]' '[:lower:]')"
if [ -n "$DECOY_LOWER" ] && [ -n "$TARGET_LOWER" ] && [ "$DECOY_LOWER" != "$TARGET_LOWER" ]; then
	item CO-8 PASS
else
	item CO-8 FAIL
	printf '  probe_resistance=[%s] target=[%s]\n' "$DECOY_HOST" "$TARGET_HOST" >&2
fi

# ------------------------------------------------------------------- verdict
if [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq 8 ]; then
	printf 'COEXIST: PASS\n'
	exit 0
fi
printf 'COEXIST: FAIL\n'
exit 1
