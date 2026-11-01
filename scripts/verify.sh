#!/usr/bin/env bash
# Offline verifier for the my-caddy v0.2.0 delivery kit.
#
# Runs the Sprint 3 and Sprint 7 machine checks against the built binary and the
# delivery configs. Fully offline: no network, no listener bind, no TLS handshake,
# no HTTP request, no caddy run, no xray start.
#
# Interface (spec section 2.1):
#   bash scripts/verify.sh
#
# Optional environment overrides:
#   CADDY_BIN     default dist/caddy-linux-amd64
#   CADDYFILE     default deploy/Caddyfile
#   XRAY_CONFIG   default deploy/xray/config.json
#
# Output: one "ITEM <ID> PASS|FAIL" line per check, then a final
# "VERIFY: PASS|FAIL". Exit 0 only when every line is PASS and the final line is
# "VERIFY: PASS".
#
# Fail-closed: a missing jq, a non-executable CADDY_BIN, or a missing input file
# is a hard error with a diagnostic, never a silent skip.
#
# NOTE ON DEVIATIONS FROM THE SPEC TEXT (reported, not waived). Three of the
# spec's jq expressions address JSON paths that do not exist in the pinned
# module source. Each check below uses the path the modules actually emit, and
# the deviation is recorded in the transcript and in docs/VERIFY.md:
#
#   S3-7, S3-11  l4proxy.Handler encodes upstreams as `upstreams: [{dial: [...]}]`
#                (modules/l4proxy/proxy.go @ f607cce, `Upstreams UpstreamPool
#                json:"upstreams,omitempty"`; modules/l4proxy/upstream.go,
#                `Dial []string json:"dial,omitempty"`). There is no singular
#                `upstream` string in the adapted JSON.
#   S7-3         `.[0]` at the document root indexes an object; the reality
#                inbound is `.inbounds[0]`.
#
# v0.2.1 CHANGES ONE ITEM, S3-9. Its v0.2.0 clause required an `authentication`
# handler with an `http_basic` provider. That clause protected no naive property
# and it demanded the very defect it was meant to guard against: the site-level
# basic_auth it required ran before `forward_proxy` and answered 401 to every
# request, plain GET and authenticated CONNECT alike. S3-9 now asserts the
# handler ORDER instead, which is the property that keeps naive reachable. The
# full ruling is .gate/release/PM-DECISIONS-3.md F-2.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

CADDY_BIN="${CADDY_BIN:-dist/caddy-linux-amd64}"
CADDYFILE="${CADDYFILE:-deploy/Caddyfile}"
XRAY_CONFIG="${XRAY_CONFIG:-deploy/xray/config.json}"

FAILED=0
PASSED=0
# Self-consistency invariant (SPEC v0.4.0-SP7 A.3 / B.5): the number of unique
# `emit S*-*` IDs in this file. Kept next to the items it counts on purpose.
EXPECTED_ITEMS=24
# The explicit ID set behind that number (SPEC A.3). S3-1..S3-11 and
# S7-1..S7-8 and S7-12..S7-15 and S7-18 emit; S7-9, S7-10, S7-11, S7-16 and
# S7-17 are script-external meta entries and deliberately never appear here —
# S7-11 in particular is the entry that *describes* this list, so emitting it
# would be circular.
ITEM_LIST='S3-1 S3-2 S3-3 S3-4 S3-5 S3-6 S3-7 S3-8 S3-9 S3-10 S3-11
S7-1 S7-2 S7-3 S7-4 S7-5 S7-6 S7-7 S7-8
S7-12 S7-13 S7-14 S7-15 S7-18'
EMITTED_IDS=""
emit() { # $1=ID $2=PASS|FAIL
	printf 'ITEM %s %s\n' "$1" "$2"
	EMITTED_IDS="$EMITTED_IDS$1"$'\n'
	if [ "$2" = PASS ]; then
		PASSED=$((PASSED + 1))
	else
		FAILED=$((FAILED + 1))
	fi
}

# The single FAIL verdict printer. `fatal()` reuses it so that the string
# "VERIFY: FAIL" is defined once; the PASS= summary line is deliberately NOT
# reachable from here (a fail-closed exit must never look like a full run).
verdict_fail() {
	printf 'VERIFY: FAIL\n'
}

fatal() {
	verdict_fail >&2
	printf 'FATAL: %s\n' "$*" >&2
	exit 2
}

# ------------------------------------------------------------------- preflight
# Fail closed before any check runs. Silent skip is forbidden.
# Part of the invariant: the declared ID list must be exactly EXPECTED_ITEMS
# long, or the three-way reconciliation has nothing to reconcile against.
item_list_count="$(printf '%s\n' $ITEM_LIST | wc -l | tr -d '[:space:]')"
[ "$item_list_count" -eq "$EXPECTED_ITEMS" ] \
	|| fatal "ITEM_LIST has $item_list_count entries; EXPECTED_ITEMS is $EXPECTED_ITEMS"
command -v jq >/dev/null 2>&1 || fatal "jq is required and was not found on PATH"
[ -f "$CADDYFILE" ] || fatal "CADDYFILE not found: $CADDYFILE"
[ -f "$XRAY_CONFIG" ] || fatal "XRAY_CONFIG not found: $XRAY_CONFIG"
[ -f "$CADDY_BIN" ] || fatal "CADDY_BIN not found: $CADDY_BIN"
[ -x "$CADDY_BIN" ] || fatal "CADDY_BIN is not executable: $CADDY_BIN"

ADAPTED="$(mktemp)"
ADAPTED_ERR="$(mktemp)"
trap 'rm -f "$ADAPTED" "$ADAPTED_ERR"' EXIT

adapt() {
	"$CADDY_BIN" adapt --config "$CADDYFILE" --adapter caddyfile \
		>"$ADAPTED" 2>"$ADAPTED_ERR"
}

# Adapt once; every C2 check reads the same document.
adapt || { cat "$ADAPTED_ERR" >&2; fatal "caddy adapt failed for $CADDYFILE"; }

# Helper: the layer4-wrapped :443 servers, as an array of their wrapper lists.
l4_wrapped() {
	jq -c '[.apps.http.servers[]
		| select((.listen // []) | index(":443"))
		| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)]' "$ADAPTED"
}

# ---------------------------------------------------------------- S3-1
# Built-binary provenance: version starts v2.11.7 and all four modules present.
n=$("$CADDY_BIN" list-modules 2>/dev/null \
	| grep -x -e http.handlers.forward_proxy -e layer4.handlers.proxy \
		-e caddy.listeners.layer4 -e layer4.matchers.quic | wc -l | tr -d ' ')
ver=$("$CADDY_BIN" version 2>/dev/null | head -1)
if [ "$n" -eq 4 ] && printf '%s' "$ver" | grep -q '^v2\.11\.7'; then
	emit S3-1 PASS
else
	emit S3-1 FAIL
	printf '  module_matches=%s version=%s\n' "$n" "$ver" >&2
fi

# ---------------------------------------------------------------- S3-2
# caddy validate accepts the delivery Caddyfile.
val_out=$(mktemp)
if "$CADDY_BIN" validate --config "$CADDYFILE" >"$val_out" 2>&1; then
	emit S3-2 PASS
else
	emit S3-2 FAIL
	tail -n 6 "$val_out" >&2
fi
rm -f "$val_out"

# ---------------------------------------------------------------- S3-3
# Sensitivity: validate must reject a file carrying an undefined directive.
#
# The mutation has to land where a bare token is parsed as a DIRECTIVE. At the
# top level of a Caddyfile a bare token is parsed as a site ADDRESS (a
# hostname), so appending `this_directive_does_not_exist` there is accepted and
# adapts into a host-less site -- validate exits 0 and the control is inert.
# Measured on ubuntu-latest with the built binary: top-level exit=0, inside a
# site block exit=1 "unrecognized directive". So the token is appended inside a
# site block, which is what makes the control sensitive. Recorded in
# docs/VERIFY.md and .gate/release/DEVIATIONS.md.
s33="$(mktemp).Caddyfile"
cp "$CADDYFILE" "$s33"
printf '\nverify_sensitivity_probe.test {\n\tthis_directive_does_not_exist\n}\n' >>"$s33"
if ! "$CADDY_BIN" validate --config "$s33" >/dev/null 2>&1; then
	emit S3-3 PASS
else
	emit S3-3 FAIL
	printf '  validate accepted a broken file (exit=0)\n' >&2
fi
rm -f "$s33"

# ---------------------------------------------------------------- S3-4
# Exactly one layer4-wrapped :443 server.
c=$(jq '[.apps.http.servers[]
	| select((.listen // []) | index(":443"))
	| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)] | length' "$ADAPTED")
if [ "$c" = 1 ]; then
	emit S3-4 PASS
else
	emit S3-4 FAIL
	printf '  layer4-wrapped :443 servers=%s\n' "$c" >&2
	jq -c '.apps.http.servers | to_entries
		| map({k:.key,l:.value.listen,w:[.value.listener_wrappers[]?.wrapper]})' "$ADAPTED" >&2
fi

# ---------------------------------------------------------------- S3-5
# layer4 precedes tls, and the pin is sensitive (swapped copy must fail).
ck() {
	jq -e '[.apps.http.servers[]
		| select((.listen // []) | index(":443"))
		| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)
		| [.listener_wrappers[]? | .wrapper]
		| (index("layer4") < index("tls"))]
		| (length == 1 and .[0])' "$1" >/dev/null 2>&1
}
swapped=$(mktemp)
jq '.apps.http.servers |= with_entries(.value.listener_wrappers |=
	(if (type == "array" and length == 2) then [.[1], .[0]] else . end))' \
	"$ADAPTED" >"$swapped"
if ck "$ADAPTED" && ! ck "$swapped"; then
	emit S3-5 PASS
else
	emit S3-5 FAIL
	printf '  order pin not satisfied or not sensitive\n' >&2
	jq -c '[.apps.http.servers[] | select((.listen//[])|index(":443"))
		| [.listener_wrappers[]? | .wrapper]]' "$ADAPTED" >&2
fi
rm -f "$swapped"

# ---------------------------------------------------------------- S3-6
# The layer4 route matcher is exactly tls sni b.test.
if jq -e '[.apps.http.servers[]
	| select((.listen // []) | index(":443"))
	| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)
	| .listener_wrappers[] | select(.wrapper == "layer4")
	| [.. | objects | select(has("sni"))]]
	| (length == 1) and (.[0] | length == 1) and (.[0][0].sni == ["b.test"])' \
	"$ADAPTED" >/dev/null 2>&1; then
	emit S3-6 PASS
else
	emit S3-6 FAIL
	printf '  sni matcher is not exactly ["b.test"]\n' >&2
	jq -c '[.. | objects | select(has("sni"))]' "$ADAPTED" >&2
fi

# ---------------------------------------------------------------- S3-7
# Exactly one proxy handler; proxy_protocol=v2; a fixed loopback upstream dial.
# Deviation: upstreams is an array of {dial:[...]}, not a singular string.
if jq -e '[.apps.http.servers[]
	| select((.listen // []) | index(":443"))
	| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)
	| .listener_wrappers[] | select(.wrapper == "layer4")
	| [.. | objects | select(.handler? == "proxy")]]
	| (length == 1)
	and (.[0][0].proxy_protocol == "v2")
	and ((.[0][0].upstreams | length) == 1)
	and ((.[0][0].upstreams[0].dial | length) == 1)
	and (.[0][0].upstreams[0].dial[0] | test("^127\\.0\\.0\\.1:[0-9]+$"))' \
	"$ADAPTED" >/dev/null 2>&1; then
	emit S3-7 PASS
else
	emit S3-7 FAIL
	printf '  need one proxy handler, proxy_protocol=v2, upstreams[0].dial[0]=127.0.0.1:<port>\n' >&2
	jq -c '[.. | objects | select(.handler? == "proxy")]' "$ADAPTED" >&2
fi

# ---------------------------------------------------------------- S3-8
# B answers 404, and B's 404 can never be reached by the naive forward_proxy
# handler.
#
# SPEC CONFLICT, reported not waived. The spec asks for the 404 to come from a
# server carrying NO layer4 wrapper. Real adapt output on ubuntu-latest shows
# that is unsatisfiable with this delivery config: every site keyed on :443 --
# including `b.test`, whose implicit scheme is https and whose default port is
# 443 -- consolidates into ONE server, `srv0`, and the global
# `servers :443 { listener_wrappers { layer4 {...} tls } }` block applies to
# that server. Measured: srv0 listen=[:443] wrappers=[layer4,tls]
# hosts=[b.test]. See .gate/release/adapted.json and DEVIATIONS.md.
#
# Asserting the wrapper clause would demand restructuring deploy/Caddyfile, and
# the split was measured to be unreachable from the Caddyfile at all: `b.test:443`
# and `https://b.test` both still merge into srv0. The only way to a second
# server is a different listener (:8443), which moves B off :443 and breaks the
# coexistence the delivery config is for. So the check asserts the property the
# wrapper clause was protecting -- B is never handled by the naive proxy -- which
# is observable in the real output: the b.test 404 route is `terminal` and
# ordered before the forward_proxy route in the same server.
if jq -e '
	[.apps.http.servers[]
		| . as $s
		| ($s.routes // []) as $r
		| [ range(0; ($r | length))
			| select(($r[.] | [.match[]?.host // [] | .[]]
				| index("b.test")) != null)
			| select($r[.] | any(..; .handler? == "static_response"
				and (.status_code? | tostring) == "404"))
			| select($r[.].terminal == true) ] as $b404
		| [ range(0; ($r | length))
			| select($r[.] | any(..; .handler? == "forward_proxy")) ] as $fp
		| select(($b404 | length) >= 1 and ($fp | length) == 1 and $b404[0] < $fp[0])
		| {server: (.listen // []), b404_at: $b404[0], forward_proxy_at: $fp[0]} ]
	| length >= 1
' "$ADAPTED" >/dev/null 2>&1; then
	emit S3-8 PASS
else
	emit S3-8 FAIL
	printf '  b.test 404 is missing, not terminal, or not ordered before forward_proxy\n' >&2
	jq -c '.apps.http.servers | to_entries
		| map({k:.key,l:.value.listen,w:[.value.listener_wrappers[]?.wrapper],
			routes:[.value.routes[]? | {host:[.match[]?.host // [] | .[]],
				handlers:[.. | objects | select(has("handler")) | .handler],
				terminal:.terminal}]})' "$ADAPTED" >&2
fi

# ---------------------------------------------------------------- S3-9
# One forward_proxy server on :443; no forward_proxy.upstream; and
# forward_proxy is ordered BEFORE reverse_proxy in the site's subroute.
#
# The ordering clause is the v0.2.1 replacement for v0.2.0's "an authentication
# handler with a http_basic provider exists" clause. It protects two things:
#
#   1. naive is reachable at all. `order forward_proxy before reverse_proxy` is
#      mandatory, and its absence is silent: measured, caddy adapt exits 0 and
#      emits ["reverse_proxy","forward_proxy"], so the website handler swallows
#      every request and no CONNECT ever reaches forward_proxy. A silent
#      misconfiguration is worse than a validation error, so it is pinned here.
#   2. the site role exists. The same subroute must carry a reverse_proxy: a
#      delivery config without a website handler serves no site, which is
#      exactly the v0.2.0 defect (PM-DECISIONS-3 F-1).
#
# Both handler directives compile into ONE subroute in the adapted JSON, so the
# ordered handler names are read from that subroute's route chain. If a future
# edit changes the shape so no such subroute exists, this fails loudly rather
# than passing vacuously.
if jq -e '
	[ .apps.http.servers[]
		| .routes[]?
		| . as $r
		| select(any(..; .handler? == "forward_proxy"))
		| ( [ $r | .. | objects | select(.handler? == "subroute")
			  | .routes[] | .handle[]? | .handler? ]
			| select(index("forward_proxy") != null) ) ] as $chain
	| ([.. | objects | select(.handler? == "forward_proxy")] | length == 1)
	and ([.apps.http.servers[] | select(any(..; .handler? == "forward_proxy"))] | length == 1)
	and ([.apps.http.servers[] | select(any(..; .handler? == "forward_proxy"))
		| .listen | index(":443")] | .[0] != null)
	and ([.. | objects | select(.handler? == "forward_proxy") | has("upstream")] | any | not)
	and (($chain | length) == 1)
	and (($chain[0] | index("reverse_proxy")) != null)
	and (($chain[0] | index("forward_proxy")) < ($chain[0] | index("reverse_proxy")))
' "$ADAPTED" >/dev/null 2>&1; then
	emit S3-9 PASS
else
	emit S3-9 FAIL
	printf '  naive preconditions not met (need one forward_proxy on :443, no\n' >&2
	printf '  forward_proxy.upstream, and forward_proxy ordered before\n' >&2
	printf '  reverse_proxy in the site subroute)\n' >&2
	jq -c '[.. | objects | select(.handler? == "forward_proxy")]' "$ADAPTED" >&2
	jq -c '[.apps.http.servers[] | .routes[]?
		| [.. | objects | select(.handler? == "subroute")
			| .routes[] | .handle[]? | .handler?]]' "$ADAPTED" >&2
fi

# ---------------------------------------------------------------- S3-10
if jq -e . "$XRAY_CONFIG" >/dev/null 2>&1; then
	emit S3-10 PASS
else
	emit S3-10 FAIL
	printf '  xray config is not valid JSON\n' >&2
fi

# ---------------------------------------------------------------- S3-11
# Bidirectional PROXY pairing, with a mutation control.
# Deviation: reads upstreams[0].dial[0] and the port from it.
#
# SNI flattening (measured on ubuntu-latest): the sni matcher inside the layer4
# wrapper is already an array, so collecting with an inner `[...]` produced
# $sni = [["b.test"]] and every equality against xray serverNames = ["b.test"]
# failed for the wrong reason. Collecting the scalars directly yields
# $sni = ["b.test"], which is what the cross-file equality means.
join() { # $1=xray json
	jq -e --slurpfile x "$1" '
		[.apps.http.servers[]
			| select((.listen // []) | index(":443"))
			| select(([.listener_wrappers[]? | .wrapper] | index("layer4")) != null)
			| .listener_wrappers[] | select(.wrapper == "layer4")
			| (.. | objects | select(has("sni")) | .sni[])] as $sni
		| [.. | objects | select(.handler? == "proxy")] as $px
		| ($x[0].inbounds[] | select(.streamSettings.security == "reality")) as $ri
		| (($px | length) == 1)
		and ($px[0].proxy_protocol == "v2")
		and ((($px[0].upstreams[0].dial[0]
			| capture("^127\\.0\\.0\\.1:(?<p>[0-9]+)$").p) | tonumber) == ($ri.port | tonumber))
		and ($ri.streamSettings.sockopt.acceptProxyProtocol == true)
		and (($ri.streamSettings.realitySettings.serverNames) == $sni)
		and (($sni | length) == 1)' "$ADAPTED" >/dev/null 2>&1
}
unpaired=$(mktemp)
jq '.inbounds[0].streamSettings.sockopt.acceptProxyProtocol = false' \
	"$XRAY_CONFIG" >"$unpaired"
if join "$XRAY_CONFIG" && ! join "$unpaired"; then
	emit S3-11 PASS
else
	emit S3-11 FAIL
	printf '  pairing not satisfied both ways, or not sensitive to acceptProxyProtocol\n' >&2
fi
rm -f "$unpaired"

# ---------------------------------------------------------------- S7-1
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
	emit S7-1 FAIL
	printf '  .env is tracked\n' >&2
else
	bad=$(git ls-files '.env*' | grep -v '^\.env\.example$')
	if [ -z "$bad" ]; then
		emit S7-1 PASS
	else
		emit S7-1 FAIL
		printf '  unexpected tracked env files: %s\n' "$bad" >&2
	fi
fi

# ---------------------------------------------------------------- S7-2
uuid_hits=$(git grep -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
	-- . 2>/dev/null)
if [ -z "$uuid_hits" ]; then
	emit S7-2 PASS
else
	emit S7-2 FAIL
	printf '%s\n' "$uuid_hits" >&2
fi

# ---------------------------------------------------------------- S7-3
# Deviation: reality inbound is .inbounds[0]; `.[0]` indexes the root object.
if jq -e '([.inbounds[] | select(.streamSettings.security == "reality")] | length == 1)
	and (.inbounds[0].streamSettings.realitySettings.privateKey == "<REALITY_PRIVATE_KEY>")
	and ((.inbounds[0].streamSettings.realitySettings.shortIds | length) == 1)
	and (.inbounds[0].streamSettings.realitySettings.shortIds[0] == "<REALITY_SHORT_ID>")' \
	"$XRAY_CONFIG" >/dev/null 2>&1; then
	emit S7-3 PASS
else
	emit S7-3 FAIL
	printf '  reality key material is not exactly the registered placeholders\n' >&2
	jq -c '[.inbounds[]? | select(.streamSettings.security == "reality")
		| {pk:.streamSettings.realitySettings.privateKey,
			ids:.streamSettings.realitySettings.shortIds}]' "$XRAY_CONFIG" >&2
fi

# ---------------------------------------------------------------- S7-4
host_set=$(git grep -hoE '[A-Za-z0-9._-]+\.(test|com|net|io|org)' \
	-- deploy/ ':!deploy/PLACEHOLDERS.md' 2>/dev/null | sort -u)
if diff <(printf '%s\n' "$host_set") \
	<(printf '%s\n' a.test b.test example.com | sort -u) >/dev/null 2>&1; then
	emit S7-4 PASS
else
	emit S7-4 FAIL
	printf '  hostname set in deploy/ differs from the allowlist\n' >&2
fi

# ---------------------------------------------------------------- S7-5
tok_deploy=$(git grep -hoE '<[A-Z_]+>' -- deploy/ ':!deploy/PLACEHOLDERS.md' \
	2>/dev/null | sort -u)
tok_register=$(git grep -hoE '<[A-Z_]+>' -- deploy/PLACEHOLDERS.md 2>/dev/null | sort -u)
if diff <(printf '%s\n' "$tok_deploy") <(printf '%s\n' "$tok_register") \
	>/dev/null 2>&1; then
	emit S7-5 PASS
else
	emit S7-5 FAIL
	printf '  placeholder register and deploy/ disagree\n' >&2
fi

# ---------------------------------------------------------------- S7-6
doc_ok=1
for f in docs/BUILD.md docs/VERIFY.md docs/XRAY.md; do
	[ -s "$f" ] || { printf '  missing or empty %s\n' "$f" >&2; doc_ok=0; }
done
grep -qE 'layer4.*before.*tls|tls.*after.*layer4' docs/VERIFY.md || doc_ok=0
grep -q 'listener_wrappers' docs/VERIFY.md || doc_ok=0
grep -q 'acceptProxyProtocol' docs/XRAY.md || doc_ok=0
grep -q 'proxy_protocol v2' docs/XRAY.md || doc_ok=0
grep -q 'serverNames' docs/XRAY.md || doc_ok=0
grep -q 'caddy-read-idle-timeout.patch' docs/BUILD.md || doc_ok=0
grep -q -- '--replace' docs/BUILD.md || doc_ok=0
grep -qE 'SAN.*subject|subject.*SAN' docs/BUILD.md docs/VERIFY.md docs/XRAY.md || doc_ok=0
grep -q 'NOT VERIFIED IN THIS SLICE' docs/BUILD.md docs/VERIFY.md docs/XRAY.md || doc_ok=0
if [ "$doc_ok" -eq 1 ]; then emit S7-6 PASS; else
	emit S7-6 FAIL
	printf '  a mandatory doc fact is missing\n' >&2
fi

# ---------------------------------------------------------------- S7-7
doc_cmds=$(awk '/^```bash/{f=1;next} /^```/{f=0}
	f && /^\$ /{sub(/^\$ /,""); sub(/ *# expect-fail.*$/,""); print}' \
	docs/BUILD.md docs/VERIFY.md docs/XRAY.md | sort -u)
rec_cmds=$(awk '/^\$ /{sub(/^\$ /,""); print}' docs/transcript-v0.2.0.txt | sort -u)
miss=$(comm -23 <(printf '%s\n' "$doc_cmds") <(printf '%s\n' "$rec_cmds"))
if [ -z "$miss" ]; then
	emit S7-7 PASS
else
	emit S7-7 FAIL
	printf '  doc commands with no transcript entry:\n%s\n' "$miss" >&2
fi

# ---------------------------------------------------------------- S7-8
if awk '
	FNR==NR {
		if (/^\[run\] exit=/) {
			e=$0; sub(/^\[run\] exit=/,"",e)
			getline; sub(/^\$ /,""); E[$0]=e
		}
		next
	}
	/^```bash/{f=1;next}
	/^```/{f=0}
	f && /^\$ /{
		line=$0; sub(/^\$ /,"",line)
		m=(line ~ /# expect-fail/)
		sub(/ *# expect-fail.*$/,"",line)
		if (!(line in E)) { print "UNRUN: " line; bad=1 }
		else if (m && E[line]=="0") { print "MARKED-FAIL-BUT-PASSED: " line; bad=1 }
		else if (!m && E[line]!="0") { print "PASSED-AS-FAIL: " line " exit=" E[line]; bad=1 }
	}
	END { exit bad?1:0 }
' docs/transcript-v0.2.0.txt docs/BUILD.md docs/VERIFY.md docs/XRAY.md >/dev/null 2>&1; then
	emit S7-8 PASS
else
	emit S7-8 FAIL
	printf '  doc verdicts disagree with recorded exit codes\n' >&2
fi

# ---------------------------------------------------------------- S7-12
# G1: no live-looking credential may exist in the tracked tree. The three
# patterns are the ones published verbatim in SPEC v0.4.0-SP7 B.1. POSIX ERE
# has no shorthand whitespace class, so `[[:space:]]` is used throughout, and
# the credential pattern is matched case-insensitively because an all-uppercase
# assignment would otherwise slip through untouched.
g1_p1='"privateKey"[[:space:]]*:[[:space:]]*"[^<"]'
g1_p2='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
g1_p3='(secret|password|passwd|passphrase)[[:space:]]*[:=][[:space:]]*[^<$[:space:]]'

g1_bad=0

# B.1 also forbids the PCRE whitespace shorthand (backslash followed by s)
# inside a regex: POSIX ERE defines no such class, so a pattern written with it
# would silently mean "a literal s, then anything" and pass forever. Any regex
# containing it is an immediate FAIL. The two-character sequence is assembled
# here instead of being spelled out, because SPEC B.1 criterion 5 greps this
# file for exactly that sequence and must come back empty.
g1_bs="$(printf '\\%s' 's')"
for g1_p in "$g1_p1" "$g1_p2" "$g1_p3"; do
	case "$g1_p" in
	*"$g1_bs"*)
		g1_bad=1
		printf '  G1 regex contains the PCRE whitespace shorthand, undefined in POSIX ERE: %s\n' "$g1_p" >&2
		;;
	esac
done

# Positive and negative controls. A tree scan that finds nothing proves nothing
# by itself: a broken regex produces exactly the same silence. So each pattern
# is run against a synthetic match (must match) and a synthetic placeholder
# (must not match), in a scratch directory required to live outside the repo.
g1_ctl_ok=1
g1_tmp="$(mktemp -d 2>/dev/null)" || g1_tmp=""
case "${g1_tmp:-}" in
'')
	g1_ctl_ok=0
	printf '  G1 controls: mktemp -d failed\n' >&2
	;;
"$REPO_ROOT"|"$REPO_ROOT"/*)
	g1_ctl_ok=0
	printf '  G1 controls: scratch dir is inside the repository: %s\n' "$g1_tmp" >&2
	;;
esac
g1_cleanup() { [ -n "${g1_tmp:-}" ] && rm -rf "$g1_tmp"; }
trap 'g1_cleanup; rm -f "$ADAPTED" "$ADAPTED_ERR"' EXIT

if [ "$g1_ctl_ok" -eq 1 ]; then
	# The bodies are assembled at run time on purpose. Spelling a
	# credential-shaped literal out in this tracked file would make G1 flag its
	# own verifier — the exact defect class G1 exists to catch.
	printf '"%s" : "%s"\n' 'privateKey' 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY' \
		> "$g1_tmp/pc1.json"
	printf '"%s": "%s"\n' 'privateKey' '<REALITY_PRIVATE_KEY>' > "$g1_tmp/nc1.json"
	printf 'id=%s-%s-%s-%s-%s\n' 3f2504e0 4f89 11d3 9a0c 0305e82c3301 \
		> "$g1_tmp/pc2.txt"
	printf 'id=%s\n' '<VLESS_UUID>' > "$g1_tmp/nc2.txt"
	g1_key_pre='NAIVE_PASS'
	g1_key_suf='WORD'
	printf '%s%s=%s\n' "$g1_key_pre" "$g1_key_suf" 'xyzzy-control-value' > "$g1_tmp/pc3.txt"
	printf '%s%s=%s\n' "$g1_key_pre" "$g1_key_suf" '<NAIVE_PASSWORD>' > "$g1_tmp/nc3.txt"

	g1_control() { # $1=label $2=regex $3=grep mode (s|i) $4=file $5=wanted exit
		if [ "$3" = i ]; then
			grep -qiE "$2" "$4"
		else
			grep -qE "$2" "$4"
		fi
		g1_rc=$?
		if [ "$g1_rc" -ne "$5" ]; then
			g1_bad=1
			printf '  G1 %s mismatch: regex=%s file=%s expected=exit %s actual=exit %s\n' \
				"$1" "$2" "${4##*/}" "$5" "$g1_rc" >&2
			printf '  G1 %s body: %s\n' "${4##*/}" "$(cat "$4")" >&2
		fi
	}
	g1_control p1-positive "$g1_p1" s "$g1_tmp/pc1.json" 0
	g1_control p1-negative "$g1_p1" s "$g1_tmp/nc1.json" 1
	g1_control p2-positive "$g1_p2" s "$g1_tmp/pc2.txt" 0
	g1_control p2-negative "$g1_p2" s "$g1_tmp/nc2.txt" 1
	g1_control p3-positive "$g1_p3" i "$g1_tmp/pc3.txt" 0
	g1_control p3-negative "$g1_p3" i "$g1_tmp/nc3.txt" 1
fi

g1_hits=""
for g1_p in "$g1_p1" "$g1_p2"; do
	g1_hits="$g1_hits$(git grep -nE "$g1_p" -- . 2>/dev/null)"
done
g1_hits="$g1_hits$(git grep -niE "$g1_p3" -- . 2>/dev/null)"
if [ "$g1_bad" -eq 0 ] && [ -z "$g1_hits" ]; then
	emit S7-12 PASS
else
	emit S7-12 FAIL
	if [ -n "$g1_hits" ]; then
		printf '  credential-shaped material in the tracked tree:\n%s\n' "$g1_hits" >&2
	fi
	if [ "$g1_bad" -ne 0 ]; then
		printf '  G1 regex self-test failed (see the mismatches above)\n' >&2
	fi
fi

# ---------------------------------------------------------------- S7-13
# G2: docs/REDACTION.md is the single source of truth for the redaction
# allowlist. Exact-token set comparison in both directions, plus the C4
# negative control and the forbidden hostname.
s13_ok=1
if [ ! -f docs/REDACTION.md ]; then
	s13_ok=0
	printf '  docs/REDACTION.md is missing\n' >&2
else
	s13_allow=$(grep -E '^\[C[123]\] ' docs/REDACTION.md | cut -d' ' -f2 | sort -u)
	s13_tree=$(git grep -hoE '[A-Za-z0-9][A-Za-z0-9.-]*\.(test|com|net|org|io)(/[A-Za-z0-9._-]+)?' \
		-- . 2>/dev/null | sort -u)
	s13_missing=$(comm -23 <(printf '%s\n' "$s13_tree") <(printf '%s\n' "$s13_allow"))
	if [ -n "$s13_missing" ]; then
		s13_ok=0
		printf '  tree tokens absent from the allowlist:\n%s\n' "$s13_missing" >&2
	fi
	s13_excess=$(comm -13 <(printf '%s\n' "$s13_tree") <(printf '%s\n' "$s13_allow") \
		| grep -vxE 'example\.(net|org)')
	if [ -n "$s13_excess" ]; then
		s13_ok=0
		printf '  allowlist entries neither present nor declared absent:\n%s\n' "$s13_excess" >&2
	fi
	[ "$(grep -cE '^\[C4\] ' docs/REDACTION.md)" -eq 1 ] || s13_ok=0
	if [ "$(grep -cxE '^\[C4\] nexample\\\.com$' docs/REDACTION.md)" -ne 1 ]; then
		s13_ok=0
	fi
	if printf '%s\n' "$s13_allow" | grep -qxE 'nexample\.com'; then
		s13_ok=0
		printf '  the C4 negative control leaked into the C1-C3 allowlist\n' >&2
	fi
	[ "$(printf '%s\n' "$s13_allow" | wc -l)" -eq 15 ] || s13_ok=0
	if git grep -qE 'ksc[-]test[.]com' -- . 2>/dev/null; then s13_ok=0; fi
	if grep -qE 'ksc[-]test[.]com' docs/REDACTION.md; then s13_ok=0; fi
fi
if [ "$s13_ok" -eq 1 ]; then emit S7-13 PASS; else
	emit S7-13 FAIL
	printf '  redaction allowlist is not consistent with the tree\n' >&2
fi

# ---------------------------------------------------------------- S7-14
# G3: .env.example carries exactly the five registered placeholders, one
# strict KEY=<TOKEN> per line, and .env itself is neither tracked nor
# un-ignored. `.env` existing on disk is NOT a failure: on a deployment host it
# is supposed to exist, and SPEC v0.4.0-SP7 B.3 only requires it to stay
# untracked and ignored.
s14_ok=1
if [ ! -f .env.example ]; then
	s14_ok=0
	printf '  .env.example is missing\n' >&2
else
	[ "$(grep -cE '^[A-Z_][A-Z0-9_]*=<[^>]+>$' .env.example)" -eq 5 ] || s14_ok=0
	[ "$(grep -cE '^[A-Z_][A-Z0-9_]*=<[^>]+>.*#' .env.example)" -eq 0 ] || s14_ok=0
	if ! diff <(grep -oE '^[A-Z_][A-Z0-9_]*' .env.example | sort -u) \
		<(git grep -hoE '<[A-Z_]+>' -- deploy/PLACEHOLDERS.md 2>/dev/null \
			| tr -d '<>' | sort -u) >/dev/null 2>&1; then
		s14_ok=0
		printf '  key set differs from deploy/PLACEHOLDERS.md\n' >&2
	fi
fi
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
	s14_ok=0
	printf '  .env is tracked\n' >&2
fi
if ! git check-ignore -q .env; then
	s14_ok=0
	printf '  .env is not git-ignored\n' >&2
fi
if [ "$s14_ok" -eq 1 ]; then emit S7-14 PASS; else
	emit S7-14 FAIL
fi

# ---------------------------------------------------------------- S7-15
# G4: the version-provenance paragraph must name the real source (#8121),
# record the misreference (#8264) as a misreference, carry both timestamps,
# and keep the tag name and its date on one physical line.
s15_ok=1
for s15_need in '8f549e6df151f6a947bc183200c5d26baefa8666' \
	'f355b8687d5582ea9fcc99f71598109d1e5b6ced' '#8121' '#8264' \
	'2026-10-03T05:06:18Z' '2026-10-03T12:18:42Z'; do
	grep -qF "$s15_need" docs/BUILD.md || s15_ok=0
done
grep -qE 'v2\.11\.7.*2026-10-03' docs/BUILD.md || s15_ok=0
if [ -n "$(git grep -nE 'All 19|19 items|19/19' -- docs/ 2>/dev/null)" ]; then
	s15_ok=0
	printf '  stale item counts remain in docs/\n' >&2
fi
if [ "$s15_ok" -eq 1 ]; then emit S7-15 PASS; else
	emit S7-15 FAIL
	printf '  docs/BUILD.md does not carry the G4 provenance facts\n' >&2
fi

# ---------------------------------------------------------------- S7-18
# C4: deploy/ is frozen at v0.3.0. Fail closed when the ref is missing —
# an unverifiable freeze must never read as a pass.
if git rev-parse --verify --quiet 'v0.3.0^{commit}' >/dev/null 2>&1; then
	s18_diff="$(git diff --name-only 'v0.3.0' -- deploy/ 2>/dev/null)"
	if [ -z "$s18_diff" ]; then
		emit S7-18 PASS
	else
		emit S7-18 FAIL
		printf '  deploy/ changed since v0.3.0:\n%s\n' "$s18_diff" >&2
	fi
else
	emit S7-18 FAIL
	printf '  v0.3.0 ref missing; deploy freeze unverifiable\n' >&2
fi

# ------------------------------------------------------------------- verdict
# Third leg of the invariant (SPEC A.3 / B.5): the IDs actually emitted, deduped
# and sorted, must equal the declared ITEM_LIST as a set. A mismatch here is a
# verifier self-consistency failure, so it goes through verdict_fail() and a
# nonzero exit — never a bare warning.
set_ok=1
if ! diff <(printf '%s' "$EMITTED_IDS" | sort -u) \
	<(printf '%s\n' $ITEM_LIST | sort -u) >/dev/null 2>&1; then
	set_ok=0
	printf '  emitted ID set differs from ITEM_LIST (expected 24 entries):\n' >&2
	diff <(printf '%s' "$EMITTED_IDS" | sort -u) \
		<(printf '%s\n' $ITEM_LIST | sort -u) >&2
fi

# The PASS=/FAIL= summary is emitted only here, after every item has had a
# chance to run; `fatal()` returns through `verdict_fail()` and can never
# reach it. `VERIFY: PASS|FAIL` stays the last line of output.
if [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq "$EXPECTED_ITEMS" ] && [ "$set_ok" -eq 1 ]; then
	printf 'PASS=%s FAIL=%s\n' "$PASSED" "$FAILED"
	printf 'VERIFY: PASS\n'
	exit 0
fi
printf 'PASS=%s FAIL=%s\n' "$PASSED" "$FAILED"
verdict_fail
exit 1
