#!/usr/bin/env bash
# Gate 0 / sprint 1 / SP1-A2: explicit isolation of B. One-off probe, not a delivery artifact.
# Uses tests/probes/gate-b-isolation.Caddyfile (tls internal, no layer4) so B takes the fallback path.
#
# Usage: gate-a2.sh <repo-root>
# Required env: GATE_DIR
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/probes/lib-evidence.sh
. "$HERE/lib-evidence.sh"

REPO_ROOT="${1:?usage: gate-a2.sh <repo-root>}"
: "${GATE_DIR:?}"

BIN="$GATE_DIR/caddy"
CONF="$HERE/gate-b-isolation.Caddyfile"
EVID="$REPO_ROOT/evidence/SP1-A2.txt"
CADDY_PID=""

cleanup() {
	if [ -n "$CADDY_PID" ]; then
		kill "$CADDY_PID" 2>/dev/null || true
		wait "$CADDY_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT

mkdir -p "$REPO_ROOT/evidence"
evidence_init "$EVID" "SP1-A2" "ubuntu-latest, $(go version), caddy $(head -n1 "$GATE_DIR/a1-version.log" 2>/dev/null || echo unknown), port :443 (cap_net_bind_service, spec 7.4 A2 default port)"

if [ ! -x "$BIN" ]; then
	ev_assert "probe binary" FAIL "no executable at $BIN"
	evidence_finish FAIL
	exit 1
fi

curl -V > "$GATE_DIR/a2-curlv.log" 2>&1
ev_block "curl -V" 0 "$GATE_DIR/a2-curlv.log"

# :443 needs the low-port capability. setcap (the approach the naive README uses)
# is preferred over `sudo caddy run &`, because `$!` would then be sudo's PID and
# killing it would orphan the real caddy process.
sudo setcap cap_net_bind_service=+ep "$BIN" > "$GATE_DIR/a2-setcap.log" 2>&1
c=$?
ev_block "sudo setcap cap_net_bind_service=+ep $BIN" "$c" "$GATE_DIR/a2-setcap.log"
if [ "$c" -ne 0 ]; then
	ev_assert "cap_net_bind_service granted" FAIL "setcap failed; :443 cannot be bound unprivileged"
	evidence_finish FAIL
	exit 1
fi
ev_assert "cap_net_bind_service granted" PASS "binary can bind :443 as the runner user"

# ------------------------------------------------------------------ start caddy
"$BIN" run --config "$CONF" > "$GATE_DIR/a2-caddy.log" 2>&1 &
CADDY_PID=$!

ready=0
for _ in $(seq 1 60); do
	if curl -s -o /dev/null -m 2 --resolve a.test:443:127.0.0.1 -k https://a.test/; then
		ready=1
		break
	fi
	sleep 1
done
ev_block "wait for :443 to accept TLS (up to 60s)" "$((ready == 1 ? 0 : 1))" "$GATE_DIR/a2-caddy.log"
if [ "$ready" -ne 1 ]; then
	ev_assert "caddy listening on :443" FAIL "not reachable within 60s"
	evidence_finish FAIL
	exit 1
fi
ev_assert "caddy listening on :443" PASS

# ------------------------------------------------------------------- B request
curl -sk --resolve b.test:443:127.0.0.1 https://b.test/ -D "$GATE_DIR/a2-b.hdr" -o "$GATE_DIR/a2-b.body"
c1=$?
ev_block "curl -sk --resolve b.test:443:127.0.0.1 https://b.test/ -D - -o b.body" "$c1" "$GATE_DIR/a2-b.hdr"
# Spec 7.4 A2: both response headers must appear in the evidence verbatim, including
# the status line and content-type. ev_block truncates long output, so dump in full.
{
	printf '[关键输出] b.test response headers (verbatim)\n'
	cat "$GATE_DIR/a2-b.hdr"
	printf '[关键输出] b.body (%s bytes, verbatim)\n' "$(wc -c < "$GATE_DIR/a2-b.body" | tr -d ' ')"
	cat "$GATE_DIR/a2-b.body"
	printf '\n'
} >> "$EVID"

B_STATUS=$(head -n1 "$GATE_DIR/a2-b.hdr" | tr -d '\r')
if [ "$B_STATUS" = "HTTP/2 404" ]; then
	ev_assert "b.test status line" PASS "$B_STATUS"
elif [ "$B_STATUS" = "HTTP/1.1 404" ]; then
	ev_assert "b.test status line" PASS "$B_STATUS (curl built without HTTP/2; curl -V recorded above per spec 4.0 convention 1)"
else
	ev_assert "b.test status line" FAIL "got '$B_STATUS', want 'HTTP/2 404'"
fi

if grep -qi '^content-type:' "$GATE_DIR/a2-b.hdr"; then
	ev_assert "b.test response has content-type" PASS "content-type present, quoted in full above"
else
	ev_assert "b.test response has content-type" FAIL "no content-type header in the B response"
fi

if grep -q 'SITE-MARKER-v4' "$GATE_DIR/a2-b.body"; then
	ev_assert "b.body has no site marker" FAIL "SITE-MARKER-v4 present in b.body: catch-all won over the named host, D-2 isolation unusable as designed"
else
	ev_assert "b.body has no site marker" PASS "SITE-MARKER-v4 absent"
fi

# ------------------------------------------------------------------- A request
curl -sk --resolve a.test:443:127.0.0.1 https://a.test/ -D "$GATE_DIR/a2-a.hdr" -o "$GATE_DIR/a2-a.body"
c2=$?
ev_block "curl -sk --resolve a.test:443:127.0.0.1 https://a.test/ -D - -o a.body" "$c2" "$GATE_DIR/a2-a.hdr"
{
	printf '[关键输出] a.test response headers (verbatim)\n'
	cat "$GATE_DIR/a2-a.hdr"
	printf '[关键输出] a.body (%s bytes, verbatim)\n' "$(wc -c < "$GATE_DIR/a2-a.body" | tr -d ' ')"
	cat "$GATE_DIR/a2-a.body"
	printf '\n'
} >> "$EVID"

A_STATUS=$(head -n1 "$GATE_DIR/a2-a.hdr" | tr -d '\r')
if [ "$A_STATUS" = "HTTP/2 200" ] || [ "$A_STATUS" = "HTTP/1.1 200" ]; then
	ev_assert "a.test status line" PASS "$A_STATUS"
else
	ev_assert "a.test status line" FAIL "got '$A_STATUS', want 200"
fi

if grep -qi '^content-type:' "$GATE_DIR/a2-a.hdr"; then
	ev_assert "a.test response has content-type" PASS "content-type present, quoted in full above"
else
	ev_assert "a.test response has content-type" FAIL "no content-type header in the A response"
fi

printf 'SITE-MARKER-v4' > "$GATE_DIR/a2-a.want"
if cmp -s "$GATE_DIR/a2-a.want" "$GATE_DIR/a2-a.body"; then
	ev_assert "a.body equals marker" PASS "body is exactly SITE-MARKER-v4"
else
	ev_assert "a.body equals marker" FAIL "body differs from SITE-MARKER-v4"
fi

# --------------------------------------------------------------- B certificate
openssl s_client -connect 127.0.0.1:443 -servername b.test -showcerts </dev/null 2>/dev/null \
	| openssl x509 -noout -subject -issuer > "$GATE_DIR/a2-b-cert.log" 2>&1
c3=$?
ev_block "openssl s_client -connect 127.0.0.1:443 -servername b.test -showcerts | openssl x509 -noout -subject -issuer" "$c3" "$GATE_DIR/a2-b-cert.log"

if grep -q 'CN = b.test' "$GATE_DIR/a2-b-cert.log"; then
	ev_assert "B cert subject" PASS "CN = b.test"
else
	ev_assert "B cert subject" FAIL "subject does not contain CN = b.test"
fi
if grep -q 'Caddy Local Authority' "$GATE_DIR/a2-b-cert.log"; then
	ev_assert "B cert issuer" PASS "issuer is the local CA"
else
	ev_assert "B cert issuer" FAIL "issuer does not contain Caddy Local Authority"
fi
if grep -q 'CN = a.test' "$GATE_DIR/a2-b-cert.log"; then
	ev_assert "B cert is not A's" FAIL "subject/issuer mentions CN = a.test"
else
	ev_assert "B cert is not A's" PASS "no CN = a.test in subject or issuer"
fi

if [ "$ASSERT_FAIL" -eq 0 ]; then
	evidence_finish PASS
	exit 0
fi
evidence_finish FAIL
exit 1
