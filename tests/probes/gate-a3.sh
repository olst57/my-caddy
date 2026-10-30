#!/usr/bin/env bash
# Gate 0 / sprint 1 / SP1-A3: PROXY protocol must be paired. One-off probe, not a delivery artifact.
#
#   (a) l4 sends the header   -> socat -x records PROXY v2 signature, 21, 11/21, 16 03 01
#   (b) xray only             -> connection refused, log has 'failed to accepted raw connections'
#   (c) both ends paired      -> accept-phase rejection count unchanged
#   (d) l4 sends, xray not    -> connection refused, 'accepting PROXY protocol' count is 0
#
# Usage: gate-a3.sh <repo-root>
# Required env: GATE_DIR XRAY_VERSION
#
# :443 is bound via cap_net_bind_service rather than `sudo caddy run &`: with sudo
# in front, `$!` is sudo's PID, so killing it orphans the real process and leaves
# :443 held, which would break the later phases of this same script.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/probes/lib-evidence.sh
. "$HERE/lib-evidence.sh"

REPO_ROOT="${1:?usage: gate-a3.sh <repo-root>}"
: "${GATE_DIR:?}" "${XRAY_VERSION:?}"

BIN="$GATE_DIR/caddy"
EVID="$REPO_ROOT/evidence/SP1-A3.txt"
L4_CONF="$GATE_DIR/a3-layer4.Caddyfile"
L4_CONF_REC="$GATE_DIR/a3-layer4-socat.Caddyfile"
XRAY_PAIRED="$HERE/xray-gate.json"
XRAY_NOPROXY="$HERE/xray-gate-noproxy.json"
XRAY_BIN="$GATE_DIR/xray/xray"
CADDY_PID=""
SOCAT_PID=""
XRAY_PID=""

stop() {
	local p="$1"
	if [ -n "$p" ]; then
		kill "$p" 2>/dev/null || true
		wait "$p" 2>/dev/null || true
	fi
}

cleanup() {
	stop "$CADDY_PID"
	stop "$SOCAT_PID"
	stop "$XRAY_PID"
}
trap cleanup EXIT

mkdir -p "$REPO_ROOT/evidence"
evidence_init "$EVID" "SP1-A3" "ubuntu-latest, $(go version), caddy $(head -n1 "$GATE_DIR/a1-version.log" 2>/dev/null || echo unknown), xray $XRAY_VERSION, :443 via cap_net_bind_service"

if [ ! -x "$BIN" ]; then
	ev_assert "probe binary" FAIL "no executable at $BIN"
	evidence_finish FAIL
	exit 1
fi

# ------------------------------------------------------------------- xray setup
mkdir -p "$GATE_DIR/xray"
curl -fsSL -o "$GATE_DIR/xray/xray.zip" \
	"https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-linux-64.zip" \
	> "$GATE_DIR/a3-xray-dl.log" 2>&1
c=$?
ev_block "curl -fsSL https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-linux-64.zip" "$c" "$GATE_DIR/a3-xray-dl.log"
if [ "$c" -ne 0 ]; then
	ev_assert "xray download" FAIL "could not fetch $XRAY_VERSION"
	evidence_finish FAIL "xray unavailable, A3 sub-items are NOT-TESTED"
	exit 1
fi
unzip -o -q "$GATE_DIR/xray/xray.zip" -d "$GATE_DIR/xray" >> "$GATE_DIR/a3-xray-dl.log" 2>&1
chmod +x "$XRAY_BIN"

"$XRAY_BIN" version > "$GATE_DIR/a3-xray-version.log" 2>&1
ev_block "$XRAY_BIN version" 0 "$GATE_DIR/a3-xray-version.log"
XV=$(head -n1 "$GATE_DIR/a3-xray-version.log")
ev_note "xray version first line: $XV"

# v1.x must be >= 1.8.0; calendar versions (v24/v25/...) always satisfy E6.
if printf '%s' "$XV" | grep -qE 'Xray [0-9]+\.[0-9]+\.[0-9]+'; then
	MAJ=$(printf '%s' "$XV" | sed -nE 's/.*Xray ([0-9]+)\.[0-9]+\.[0-9]+.*/\1/p')
	MIN=$(printf '%s' "$XV" | sed -nE 's/.*Xray [0-9]+\.([0-9]+)\.[0-9]+.*/\1/p')
	if [ "$MAJ" -ge 2 ]; then
		ev_assert "xray >= v1.8.0" PASS "major $MAJ satisfies E6 (calendar version form)"
	elif [ "$MAJ" -eq 1 ] && [ "$MIN" -ge 8 ]; then
		ev_assert "xray >= v1.8.0" PASS "1.$MIN >= 1.8.0"
	else
		ev_assert "xray >= v1.8.0" FAIL "1.$MIN < 1.8.0, REALITY absent"
	fi
else
	ev_assert "xray >= v1.8.0" FAIL "could not parse '$XV'"
fi

# real credentials for the probe configs (probe only, never committed)
UUID=$("$XRAY_BIN" uuid 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$UUID" ] || UUID=$(cat /proc/sys/kernel/random/uuid)
PRIV=$("$XRAY_BIN" x25519 2>/dev/null | sed -nE 's/^Private ?[Kk]ey: *//p' | head -n1 | tr -d '\r')
SHORTID=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
if [ -z "$UUID" ] || [ -z "$PRIV" ]; then
	ev_assert "probe credentials generated" FAIL "xray uuid/x25519 gave nothing"
	evidence_finish FAIL "cannot build REALITY probe config"
	exit 1
fi
ev_assert "probe credentials generated" PASS "uuid, x25519 private key and shortId generated (values not written to evidence)"

render_xray() { # $1=src $2=dst
	sed -e "s|<UUID>|$UUID|" -e "s|<REALITY_PRIVATE_KEY>|$PRIV|" -e "s|<SHORT_ID>|$SHORTID|" "$1" > "$2"
}
render_xray "$XRAY_PAIRED" "$GATE_DIR/xray-paired.json"
render_xray "$XRAY_NOPROXY" "$GATE_DIR/xray-noproxy.json"

# l4 probe configs: default upstream 19098, plus the socat recorder variant on 19099
cp "$HERE/gate-layer4.Caddyfile" "$L4_CONF"
sed 's|upstream 127.0.0.1:19098|upstream 127.0.0.1:19099|' "$HERE/gate-layer4.Caddyfile" > "$L4_CONF_REC"
if ! grep -q 'upstream 127.0.0.1:19099' "$L4_CONF_REC"; then
	ev_assert "socat recorder config" FAIL "could not rewrite upstream to 19099"
	evidence_finish FAIL
	exit 1
fi

sudo setcap cap_net_bind_service=+ep "$BIN" > "$GATE_DIR/a3-setcap.log" 2>&1
c=$?
ev_block "sudo setcap cap_net_bind_service=+ep $BIN" "$c" "$GATE_DIR/a3-setcap.log"
if [ "$c" -ne 0 ]; then
	ev_assert "cap_net_bind_service granted" FAIL "setcap failed; :443 cannot be bound unprivileged"
	evidence_finish FAIL
	exit 1
fi
ev_assert "cap_net_bind_service granted" PASS "binary can bind :443 as the runner user"

# `ss -ltn` prints the local endpoint in column 4. A service bound to a wildcard
# address shows up as `*:443` or `[::]:443`, never as `127.0.0.1:443`, so matching
# the whole line against `(:|127.0.0.1:)<port>` can never succeed for a wildcard
# bind. Anchor on the trailing `:PORT` instead, which covers `*:443`,
# `127.0.0.1:443` and `[::]:443` in one expression. The matched line is written to
# last-listen.log so the evidence records which address actually listened, making a
# false pass visible on inspection.
wait_port() { # $1=port
	local i line
	for i in $(seq 1 40); do
		line=$(ss -ltn 2>/dev/null | awk -v p=":$1" '$4 ~ (p "$")' | head -n1)
		if [ -n "$line" ]; then
			printf '%s\n' "$line" > "$GATE_DIR/last-listen.log"
			return 0
		fi
		sleep 1
	done
	return 1
}

# ------------------------------------------------------- A3(a) l4 really sends it
socat -x TCP-LISTEN:19099,reuseaddr,fork - > "$GATE_DIR/l4-bytes.log" 2>&1 &
SOCAT_PID=$!
if wait_port 19099; then
	ev_assert "socat recorder listening" PASS ":19099"
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "socat recorder listening" FAIL ":19099 never opened"
fi

"$BIN" run --config "$L4_CONF_REC" > "$GATE_DIR/a3a-caddy.log" 2>&1 &
CADDY_PID=$!
if wait_port 443; then
	ev_assert "caddy listening on :443 (a)" PASS
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "caddy listening on :443 (a)" FAIL "not opened"
fi

timeout 3 openssl s_client -connect 127.0.0.1:443 -servername b.test -quiet </dev/null > "$GATE_DIR/a3a-sclient.log" 2>&1
c=$?
ev_block "timeout 3 openssl s_client -connect 127.0.0.1:443 -servername b.test -quiet" "$c" "$GATE_DIR/a3a-sclient.log"
sleep 1
head -20 "$GATE_DIR/l4-bytes.log" > "$GATE_DIR/a3a-head.log" 2>&1
ev_block "head -20 l4-bytes.log" 0 "$GATE_DIR/a3a-head.log"

# socat -x emits a header line (timestamp, length=, from=/to=) before each chunk of
# bytes, followed by the hex dump and then a raw rendering of the same bytes. The
# raw rendering is genuinely binary, so grep must be told the input is text:
# without -a it classifies the whole file as binary and prints "Binary file ...
# matches" instead of the lines, which silently yields an empty data file. That
# was observed on the first CI run (dump reported "0 lines" while the head -20
# excerpt plainly contained the PROXY header).
#
# Two passes are needed:
#   1. drop the header lines to get the hex dump,
#   2. tokenise to 2-hex-digit bytes and concatenate into one continuous string.
# The reconstruction is kept alongside the raw dump so a reader can verify it.
grep -avE 'length=|from=|to=' "$GATE_DIR/l4-bytes.log" > "$GATE_DIR/a3a-data.log" 2>/dev/null || true

# Keep only lines that consist exclusively of 2-hex-digit byte tokens. socat -x
# follows each hex dump with a raw rendering of the same bytes; tokenising that
# rendering would inject characters that merely happen to look like hex, so it
# is discarded rather than parsed.
awk '
	{
		t = $0
		gsub(/^[ \t]+|[ \t]+$/, "", t)
		if (t == "") next
		n = split(t, f, /[ \t]+/)
		ok = 1
		for (i = 1; i <= n; i++) {
			if (f[i] !~ /^[0-9a-fA-F][0-9a-fA-F]$/) { ok = 0; break }
		}
		if (ok) print t
	}
' "$GATE_DIR/a3a-data.log" > "$GATE_DIR/a3a-hexlines.log"
tr -s ' \t' '\n' < "$GATE_DIR/a3a-hexlines.log" \
	| grep -E '^[0-9a-fA-F]{2}$' | tr 'A-F' 'a-f' | tr -d '\n' > "$GATE_DIR/a3a-hex.log"
{
	printf '[关键输出] socat dump with header lines removed (%s lines)\n' "$(wc -l < "$GATE_DIR/a3a-data.log" | tr -d ' ')"
	head -n 4 "$GATE_DIR/a3a-data.log"
	printf '[关键输出] byte stream reconstructed from the dump (first 120 hex chars)\n'
	head -c 120 "$GATE_DIR/a3a-hex.log"
	printf '\n'
} >> "$EVID"

if grep -q '0d0a0d0a000d0a515549540a' "$GATE_DIR/a3a-hex.log"; then
	ev_assert "PROXY v2 signature" PASS "0d 0a 0d 0a 00 0d 0a 51 55 49 54 0a present"
else
	ev_assert "PROXY v2 signature" FAIL "signature not found in the socat dump"
fi

if grep -q '0d0a0d0a000d0a515549540a21' "$GATE_DIR/a3a-hex.log"; then
	ev_assert "byte 13 is 21" PASS "version 2 / command PROXY, immediately after the signature"
else
	ev_assert "byte 13 is 21" FAIL "byte immediately after the signature is not 21"
fi

if grep -qE '0d0a0d0a000d0a515549540a21(11|21)' "$GATE_DIR/a3a-hex.log"; then
	ev_assert "byte 14 is 11 or 21" PASS "AF_INET+STREAM or AF_INET6+STREAM, after 21"
else
	ev_assert "byte 14 is 11 or 21" FAIL "neither 11 nor 21 follows 21"
fi

if grep -q '160301' "$GATE_DIR/a3a-hex.log"; then
	ev_assert "raw ClientHello follows" PASS "16 03 01 present after the PROXY header"
else
	ev_assert "raw ClientHello follows" FAIL "no 16 03 01 in the dump"
fi

stop "$CADDY_PID"
CADDY_PID=""
stop "$SOCAT_PID"
SOCAT_PID=""
sleep 1

# ------------------------------------------ A3(b) xray only -> accept must reject
"$XRAY_BIN" run -c "$GATE_DIR/xray-paired.json" > "$GATE_DIR/xray-a3b.log" 2>&1 &
XRAY_PID=$!
if wait_port 19098; then
	ev_assert "xray listening on :19098 (b)" PASS
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "xray listening on :19098 (b)" FAIL "not opened"
fi

timeout 5 openssl s_client -connect 127.0.0.1:19098 -servername b.test -quiet </dev/null > "$GATE_DIR/a3b-sclient.log" 2>&1
c=$?
ev_block "timeout 5 openssl s_client -connect 127.0.0.1:19098 -servername b.test -quiet" "$c" "$GATE_DIR/a3b-sclient.log"
if [ "$c" -ne 0 ]; then
	ev_assert "no PROXY header -> rejected" PASS "openssl exit $c"
else
	ev_assert "no PROXY header -> rejected" FAIL "openssl exit 0, connection was not rejected"
fi
if grep -qiE 'EOF|errno=|Connection reset|wrong version number|handshake failure|unexpected eof' "$GATE_DIR/a3b-sclient.log"; then
	ev_assert "rejection visible to the client" PASS "EOF/errno/reset/handshake-failure in client output"
else
	ev_assert "rejection visible to the client" FAIL "no EOF/errno/reset/handshake-failure in client output"
fi

sleep 1
# The REQUIRE policy does NOT fail inside Accept(): go-proxyproto's Listener.Accept
# returns the wrapped conn, and the "no header present" error surfaces on the
# first Read (protocol.go: ProxyHeaderPolicy == REQUIRE -> return
# ErrNoProxyProtocol). Xray's accept loop therefore never emits "failed to
# accepted raw connections" for this case; what appears instead is the read-side
# error propagated out of reality.Server, logged via errors.LogInfo. The probe
# configs run at loglevel debug so that line is captured.
#
# The assertion accepts any rejection trace rather than one exact string, because
# the load-bearing evidence is the client-side rejection asserted above; the log
# line is corroboration, and pinning it to a single wording would turn a
# go-proxyproto refactor into a false FAIL of the pairing claim.
if grep -qiE 'proxy protocol|proxyproto|failed to accept|tls:|handshake' "$GATE_DIR/xray-a3b.log"; then
	ev_assert "xray logs the PROXY rejection" PASS "a proxy-protocol or TLS-layer rejection trace is present"
else
	ev_assert "xray logs the PROXY rejection" FAIL "no proxy-protocol or TLS-layer rejection trace in the xray log"
fi

# --------------------------------------------- A3(c) both ends paired -> accepted
# Count any rejection trace, not just the accept-loop wording: the pairing claim
# is "no new rejection appears once both ends agree", so the counter must be able
# to see every form the rejection can take. Counting only one string would make
# this a tautological 0 == 0 check.
REJECT_RE='proxy protocol|proxyproto|failed to accept|tls:|handshake'
grep -ciE "$REJECT_RE" "$GATE_DIR/xray-a3b.log" > "$GATE_DIR/before.txt" 2>&1
BEFORE=$(tr -d ' \r\n' < "$GATE_DIR/before.txt")

"$BIN" run --config "$L4_CONF" > "$GATE_DIR/a3c-caddy.log" 2>&1 &
CADDY_PID=$!
if wait_port 443; then
	ev_assert "caddy listening on :443 (c)" PASS
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "caddy listening on :443 (c)" FAIL "not opened"
fi

timeout 8 openssl s_client -connect 127.0.0.1:443 -servername b.test -showcerts </dev/null > "$GATE_DIR/a3c.out" 2>&1
c=$?
ev_block "timeout 8 openssl s_client -connect 127.0.0.1:443 -servername b.test -showcerts" "$c" "$GATE_DIR/a3c.out"
sleep 1

grep -ciE "$REJECT_RE" "$GATE_DIR/xray-a3b.log" > "$GATE_DIR/after.txt" 2>&1
AFTER=$(tr -d ' \r\n' < "$GATE_DIR/after.txt")
{
	printf 'before=%s after=%s\n' "$BEFORE" "$AFTER"
} > "$GATE_DIR/a3c-count.log"
ev_block "grep -ciE '$REJECT_RE' xray-a3b.log (before/after)" 0 "$GATE_DIR/a3c-count.log"

if [ "$BEFORE" = "$AFTER" ]; then
	ev_assert "accept phase clean when paired" PASS "before=$BEFORE after=$AFTER"
else
	ev_assert "accept phase clean when paired" FAIL "before=$BEFORE after=$AFTER: the PROXY header was not consumed, pairing premise broken"
fi

# Certificate check. Spec 7.4 A3(c): if the REALITY dest is unreachable, record
# that the accept phase passed and the failure is in the REALITY/TLS layer, then
# defer the certificate evidence to SP5-C1 without claiming S5. That is a
# NOT-TESTED sub-item, not a FAIL of the pairing item, and not a PASS either.
#
# The previous version treated "a3c-cert.log is non-empty" as PASS. That was a
# false pass: when the REALITY handshake fails, openssl writes its own error text
# into the same file ("Could not read certificate from <stdin>"), so a non-empty
# file means "no certificate was produced", not "the certificate is not Caddy's".
# The branch now requires the file to actually contain a subject or issuer line.
openssl s_client -connect 127.0.0.1:443 -servername b.test -showcerts </dev/null 2>/dev/null \
	| openssl x509 -noout -subject -issuer > "$GATE_DIR/a3c-cert.log" 2>&1
c=$?
ev_block "openssl s_client ... | openssl x509 -noout -subject -issuer" "$c" "$GATE_DIR/a3c-cert.log"

HAVE_CERT=0
grep -qE '^(subject|issuer)=' "$GATE_DIR/a3c-cert.log" && HAVE_CERT=1

if [ "$HAVE_CERT" -eq 0 ]; then
	ev_assert "cert comes from REALITY dest, not Caddy" NOT-TESTED "no certificate was produced (REALITY dest unreachable). Accept phase passed; the failure is in the REALITY/TLS layer. Deferred to SP5-C1; S5 is NOT claimed here."
elif grep -q 'Caddy Local Authority' "$GATE_DIR/a3c-cert.log"; then
	ev_assert "cert comes from REALITY dest, not Caddy" FAIL "certificate is Caddy's local CA: B was terminated locally instead of passed through"
elif grep -q 'CN = b.test' "$GATE_DIR/a3c-cert.log"; then
	ev_assert "cert comes from REALITY dest, not Caddy" FAIL "certificate subject is CN = b.test: the probe site block answered"
else
	ev_assert "cert comes from REALITY dest, not Caddy" PASS "a real certificate was produced and it is neither Caddy's CA nor the probe site"
fi

stop "$CADDY_PID"
CADDY_PID=""
stop "$XRAY_PID"
XRAY_PID=""
sleep 1

# --------------------------------- A3(d) l4 sends, xray does not require -> reject
"$XRAY_BIN" run -c "$GATE_DIR/xray-noproxy.json" > "$GATE_DIR/xray-a3d.log" 2>&1 &
XRAY_PID=$!
if wait_port 19098; then
	ev_assert "xray listening on :19098 (d)" PASS
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "xray listening on :19098 (d)" FAIL "not opened"
fi

"$BIN" run --config "$L4_CONF" > "$GATE_DIR/a3d-caddy.log" 2>&1 &
CADDY_PID=$!
if wait_port 443; then
	ev_assert "caddy listening on :443 (d)" PASS
	ev_note "listen: $(cat "$GATE_DIR/last-listen.log")"
else
	ev_assert "caddy listening on :443 (d)" FAIL "not opened"
fi

timeout 5 openssl s_client -connect 127.0.0.1:443 -servername b.test -quiet </dev/null > "$GATE_DIR/a3d-sclient.log" 2>&1
c=$?
ev_block "timeout 5 openssl s_client -connect 127.0.0.1:443 -servername b.test -quiet" "$c" "$GATE_DIR/a3d-sclient.log"
sleep 1

if [ "$c" -ne 0 ]; then
	ev_assert "header sent but not required -> rejected" PASS "openssl exit $c"
else
	ev_assert "header sent but not required -> rejected" FAIL "openssl exit 0: l4 did not send the header, or xray consumed it, contradicting A3(a)"
fi
if grep -qiE 'EOF|errno=|Connection reset|wrong version number|handshake failure|unexpected eof' "$GATE_DIR/a3d-sclient.log"; then
	ev_assert "rejection visible to the client (d)" PASS "EOF/errno/reset/handshake-failure present"
else
	ev_assert "rejection visible to the client (d)" FAIL "no EOF/errno/reset/handshake-failure"
fi

grep -c 'accepting PROXY protocol' "$GATE_DIR/xray-a3d.log" > "$GATE_DIR/a3d-count.log" 2>&1
c=$?
ev_block "grep -c 'accepting PROXY protocol' xray-a3d.log" "$c" "$GATE_DIR/a3d-count.log"
if [ "$(tr -d ' \r\n' < "$GATE_DIR/a3d-count.log")" = "0" ]; then
	ev_assert "xray did not announce PROXY acceptance" PASS "count 0"
else
	ev_assert "xray did not announce PROXY acceptance" FAIL "count is not 0"
fi

grep -iE 'reality|tls|handshake|failed to' "$GATE_DIR/xray-a3d.log" > "$GATE_DIR/a3d-err.log" 2>&1
c=$?
ev_block "grep -iE 'reality|tls|handshake|failed to' xray-a3d.log" "$c" "$GATE_DIR/a3d-err.log"
if [ "$c" -eq 0 ]; then
	ev_assert "xray reports a TLS/REALITY parse error" PASS "matching line present"
else
	ev_assert "xray reports a TLS/REALITY parse error" FAIL "no TLS/REALITY error line"
fi

if [ "$ASSERT_FAIL" -eq 0 ]; then
	evidence_finish PASS
	exit 0
fi
evidence_finish FAIL
exit 1
