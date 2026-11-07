#!/usr/bin/env bash
# Serial and concurrent smoke for one leg of the REALITY harness.
#
# Usage: bash tests/e2e/smoke.sh <reality|naive> <serial|concurrent>
#
# Each request is a complete client unit: a fresh SOCKS fetch for the REALITY
# leg, or a fresh TLS + CONNECT + GET for the naive leg. There is no warm
# tunnel and no retry: one failed request makes the run red.
#
# It prints exactly one machine-readable line:
#
#   SMOKE leg=<leg> mode=<mode> count=<n> failures=<n> p50_ms=<n> p95_ms=<n> first_fail=<index|->
#
# `count` is the number of requests whose result was recorded, `p50_ms` and
# `p95_ms` are nearest-rank percentiles over every recorded request (failed
# ones included), and `first_fail` is the 1-based index of the first failure
# or `-`.
#
# Environment (all supplied by run.sh; the defaults fit its fixture):
#   E2E_SMOKE_SERIAL      serial request count (30)
#   E2E_SMOKE_CONCURRENT  concurrent request count (8)
#   E2E_SMOKE_TIMEOUT     per-request timeout in seconds (20)
#   E2E_SMOKE_WORKDIR     scratch directory ($E2E_WORKDIR/smoke)
#   E2E_SMOKE_CONNECT_PORT  Caddy listener port (8443)
#   E2E_SMOKE_SOCKS_PORT    Xray client SOCKS port (10802)
#   E2E_SMOKE_SNI           site SNI on the listener (a.test)
#   E2E_SMOKE_CA            Caddy internal root certificate
#   E2E_SMOKE_USER/E2E_SMOKE_PASS  naive credentials
#   E2E_SMOKE_NAIVE_TARGET  host:port the naive CONNECT asks for
#   E2E_TARGET              URL fetched through the SOCKS inbound
#   E2E_TARGET_MARKER       body marker only the target produces
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

SERIAL="${E2E_SMOKE_SERIAL:-30}"
CONCURRENT="${E2E_SMOKE_CONCURRENT:-8}"
TIMEOUT="${E2E_SMOKE_TIMEOUT:-20}"
WORK="${E2E_SMOKE_WORKDIR:-${E2E_WORKDIR:-$REPO_ROOT/.gate/e2e}/smoke}"
CONNECT_PORT="${E2E_SMOKE_CONNECT_PORT:-8443}"
SOCKS_PORT="${E2E_SMOKE_SOCKS_PORT:-10802}"
SNI="${E2E_SMOKE_SNI:-a.test}"
CA="${E2E_SMOKE_CA:-}"
USER="${E2E_SMOKE_USER:-}"
PASS="${E2E_SMOKE_PASS:-}"
NAIVE_TARGET="${E2E_SMOKE_NAIVE_TARGET:-}"
TARGET="${E2E_TARGET:-}"
MARKER="${E2E_TARGET_MARKER:-}"

usage() {
	printf 'usage: smoke.sh <reality|naive> <serial|concurrent>\n' >&2
	exit 2
}

LEG="${1:-}"
MODE="${2:-}"
case "$LEG" in reality | naive) ;; *) usage ;; esac
case "$MODE" in serial | concurrent) ;; *) usage ;; esac
[ "$#" -eq 2 ] || usage

if [ "$LEG" = reality ]; then
	[ -n "$TARGET" ] || { printf 'FATAL: E2E_TARGET is required for the reality leg\n' >&2; exit 2; }
	[ -n "$MARKER" ] || { printf 'FATAL: E2E_TARGET_MARKER is required for the reality leg\n' >&2; exit 2; }
else
	if [ -z "$CA" ] || [ -z "$USER" ] || [ -z "$PASS" ] || [ -z "$NAIVE_TARGET" ]; then
		printf 'FATAL: E2E_SMOKE_CA, E2E_SMOKE_USER, E2E_SMOKE_PASS and E2E_SMOKE_NAIVE_TARGET are required for the naive leg\n' >&2
		exit 2
	fi
	[ -f "$CA" ] || { printf 'FATAL: CA file not found at %s\n' "$CA" >&2; exit 2; }
fi

rm -rf "$WORK"
mkdir -p "$WORK" || { printf 'FATAL: cannot create %s\n' "$WORK" >&2; exit 2; }

ONCE_MS=0
ONCE_REASON=""

reality_once() { # $1=index
	local idx="$1" start end rc code
	start="$(date +%s%N)"
	curl -sS --max-time "$TIMEOUT" --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
		-o "$WORK/body-$idx" -D "$WORK/hdr-$idx" -w '%{http_code}' \
		"$TARGET" >"$WORK/code-$idx" 2>"$WORK/err-$idx"
	rc=$?
	end="$(date +%s%N)"
	ONCE_MS=$(((end - start) / 1000000))
	code="$(cat "$WORK/code-$idx" 2>/dev/null)"
	if [ "$rc" -ne 0 ]; then
		ONCE_REASON="curl_exit=$rc"
		return 1
	fi
	if [ "$code" != "200" ]; then
		ONCE_REASON="http_code=${code:-<none>}"
		return 1
	fi
	if ! grep -qx "$MARKER" "$WORK/body-$idx" 2>/dev/null; then
		ONCE_REASON="marker_missing"
		return 1
	fi
	return 0
}

naive_once() { # $1=index
	local idx="$1" start end rc
	start="$(date +%s%N)"
	python3 "$HERE/naive-tunnel.py" \
		--connect-host 127.0.0.1 --connect-port "$CONNECT_PORT" \
		--sni "$SNI" --ca "$CA" --target "$NAIVE_TARGET" \
		--auth correct --user "$USER" --password "$PASS" \
		--expect target --timeout "$TIMEOUT" \
		>"$WORK/tunnel-$idx.json" 2>"$WORK/tunnel-$idx.err"
	rc=$?
	end="$(date +%s%N)"
	ONCE_MS=$(((end - start) / 1000000))
	if [ "$rc" -ne 0 ]; then
		ONCE_REASON="tunnel_exit=$rc"
		return 1
	fi
	if ! grep -q '"target_marker": true' "$WORK/tunnel-$idx.json" 2>/dev/null; then
		ONCE_REASON="marker_missing"
		return 1
	fi
	return 0
}

run_index() { # $1=index
	local idx="$1"
	if [ "$LEG" = reality ]; then
		if reality_once "$idx"; then
			printf 'ok %s\n' "$ONCE_MS" >"$WORK/$idx.result"
		else
			printf 'fail %s %s\n' "$ONCE_MS" "${ONCE_REASON:-unknown}" >"$WORK/$idx.result"
		fi
	else
		if naive_once "$idx"; then
			printf 'ok %s\n' "$ONCE_MS" >"$WORK/$idx.result"
		else
			printf 'fail %s %s\n' "$ONCE_MS" "${ONCE_REASON:-unknown}" >"$WORK/$idx.result"
		fi
	fi
}

if [ "$MODE" = serial ]; then
	TOTAL="$SERIAL"
	for index in $(seq 1 "$TOTAL"); do
		run_index "$index"
	done
else
	TOTAL="$CONCURRENT"
	for index in $(seq 1 "$TOTAL"); do
		run_index "$index" &
	done
	wait
fi

COUNT=0
FAILURES=0
FIRST_FAIL="-"
: >"$WORK/timings"
for index in $(seq 1 "$TOTAL"); do
	result="$WORK/$index.result"
	if [ ! -f "$result" ]; then
		FAILURES=$((FAILURES + 1))
		[ "$FIRST_FAIL" = "-" ] && FIRST_FAIL="$index"
		printf 'SMOKE FAIL leg=%s mode=%s index=%s reason=no_result\n' "$LEG" "$MODE" "$index" >&2
		continue
	fi
	# The reason field is optional, so read the first two columns explicitly
	# rather than letting a three-column line lose its status.
	status="$(awk '{print $1}' "$result")"
	ms="$(awk '{print $2}' "$result")"
	reason="$(awk '{print $3}' "$result")"
	COUNT=$((COUNT + 1))
	printf '%s\n' "$ms" >>"$WORK/timings"
	if [ "$status" != "ok" ]; then
		FAILURES=$((FAILURES + 1))
		[ "$FIRST_FAIL" = "-" ] && FIRST_FAIL="$index"
		printf 'SMOKE FAIL leg=%s mode=%s index=%s ms=%s reason=%s\n' \
			"$LEG" "$MODE" "$index" "$ms" "${reason:-unknown}" >&2
	fi
done

p50_index=$(((TOTAL * 50 + 99) / 100))
p95_index=$(((TOTAL * 95 + 99) / 100))
[ "$p50_index" -ge 1 ] || p50_index=1
[ "$p95_index" -ge 1 ] || p95_index=1
P50="$(sort -n "$WORK/timings" 2>/dev/null | sed -n "${p50_index}p")"
P95="$(sort -n "$WORK/timings" 2>/dev/null | sed -n "${p95_index}p")"
printf 'SMOKE leg=%s mode=%s count=%s failures=%s p50_ms=%s p95_ms=%s first_fail=%s\n' \
	"$LEG" "$MODE" "$COUNT" "$FAILURES" "${P50:-0}" "${P95:-0}" "$FIRST_FAIL"

if [ "$COUNT" -ne "$TOTAL" ] || [ "$FAILURES" -ne 0 ]; then
	exit 1
fi
exit 0
