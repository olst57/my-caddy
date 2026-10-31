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
# NOTE ON DEVIATIONS FROM THE SPEC TEXT (reported, not waived). Four of the
# spec's jq expressions address JSON paths that do not exist in the pinned
# module source. Each check below uses the path the modules actually emit, and
# the deviation is recorded in the transcript and in docs/VERIFY.md:
#
#   S3-7, S3-11  l4proxy.Handler encodes upstreams as `upstreams: [{dial: [...]}]`
#                (modules/l4proxy/proxy.go @ f607cce, `Upstreams UpstreamPool
#                json:"upstreams,omitempty"`; modules/l4proxy/upstream.go,
#                `Dial []string json:"dial,omitempty"`). There is no singular
#                `upstream` string in the adapted JSON.
#   S3-9         caddy v2.11.7 registers the provider as `http_basic`
#                (modules/caddyhttp/caddyauth/caddyfile.go @ v2.11.7,
#                `ProvidersRaw: caddy.ModuleMap{"http_basic": ...}`), not
#                `http_basic_auth`.
#   S7-3         `.[0]` at the document root indexes an object; the reality
#                inbound is `.inbounds[0]`.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

CADDY_BIN="${CADDY_BIN:-dist/caddy-linux-amd64}"
CADDYFILE="${CADDYFILE:-deploy/Caddyfile}"
XRAY_CONFIG="${XRAY_CONFIG:-deploy/xray/config.json}"

FAILED=0
emit() { # $1=ID $2=PASS|FAIL
	printf 'ITEM %s %s\n' "$1" "$2"
	[ "$2" = PASS ] || FAILED=1
}

fatal() {
	printf 'VERIFY: FAIL\n' >&2
	printf 'FATAL: %s\n' "$*" >&2
	exit 2
}

# ------------------------------------------------------------------- preflight
# Fail closed before any check runs. Silent skip is forbidden.
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
# One forward_proxy server on :443, basic_auth present, no forward_proxy.upstream.
# Deviation: the provider key is http_basic, not http_basic_auth.
if jq -e '([.apps.http.servers[] | select(any(..; .handler? == "forward_proxy"))] | length == 1)
	and ([.apps.http.servers[] | select(any(..; .handler? == "forward_proxy"))
		| .listen | index(":443")] | .[0] != null)
	and ([.. | objects | select(.handler? == "forward_proxy") | has("upstream")] | any | not)
	and ([.. | objects | select(.handler? == "authentication"
		and (.providers.http_basic? != null))] | length >= 1)' \
	"$ADAPTED" >/dev/null 2>&1; then
	emit S3-9 PASS
else
	emit S3-9 FAIL
	printf '  naive preconditions not met\n' >&2
	jq -c '[.. | objects | select(.handler? == "forward_proxy")]' "$ADAPTED" >&2
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
	bad=$(git ls-files '.env*' | grep -v '^\.env\.example$' || true)
	if [ -z "$bad" ]; then
		emit S7-1 PASS
	else
		emit S7-1 FAIL
		printf '  unexpected tracked env files: %s\n' "$bad" >&2
	fi
fi

# ---------------------------------------------------------------- S7-2
uuid_hits=$(git grep -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
	-- . 2>/dev/null || true)
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
	<(printf 'a.test\nb.test\nexample.com\n' | sort -u) >/dev/null 2>&1; then
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

# ------------------------------------------------------------------- verdict
if [ "$FAILED" -eq 0 ]; then
	printf 'VERIFY: PASS\n'
	exit 0
fi
printf 'VERIFY: FAIL\n'
exit 1
