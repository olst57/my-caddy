#!/bin/sh
# scripts/redact-evidence.sh -- turn a raw capture directory into a redacted copy.
#
#   redact-evidence.sh <IN_DIR> <OUT_DIR>
#
# Contract (SPEC v0.4.0-SP7, section B.6):
#   * reads only IN_DIR and writes only OUT_DIR;
#   * every token is either published literally because it is in the allowlist
#     of docs/REDACTION.md, or replaced by an alias taken from the alias map;
#     a token that is neither is a hard failure and no output is written at all;
#   * only tokens change: the line count of every output file equals the line
#     count of its source (E4), so nothing is rebuilt, reflowed or reordered;
#   * idempotent: the same input always yields the same bytes, and feeding an
#     already redacted directory back in is a no-op.
#
# Notes on the implementation:
#   * POSIX ERE only. `\s` is not a portable class, so `[[:space:]]` is used.
#   * The alias map lives outside git (default .gate/release/REDACTION-MAP.md)
#     because the very hostnames it maps must not appear in any tracked file:
#     S7-13 scans the whole tracked tree for exactly those tokens. Override the
#     location with the REDACTION_MAP environment variable.
#   * Everything is built in a private work directory and only published to
#     OUT_DIR once every file has been classified and rewritten, so a failure
#     can never leave a half-redacted tree behind.
#
# File selection: every regular file directly inside IN_DIR, except names that
# start with PM-, notes-, PUBLISH- or GRADE- (never published, E7), except
# *.md (the remaining documents are outside this round's evidence set), except
# the harness stop marker STOP.txt, and except subdirectories. On the round-7
# capture directory that yields exactly the 23 files of the must-publish list.

set -u
LC_ALL=C
export LC_ALL

prog=$(basename "$0")

die() {
	printf '%s: %s\n' "$prog" "$1" >&2
	exit "${2:-1}"
}

if [ "$#" -ne 2 ]; then
	die 'usage: redact-evidence.sh <IN_DIR> <OUT_DIR>' 64
fi

in_dir=$1
out_dir=$2

[ -d "$in_dir" ] || die "input directory not found: $in_dir" 66

# The allowlist is tracked, so it is safe to reference by path.
script_dir=$(cd "$(dirname "$0")" && pwd) || die 'cannot resolve the script directory' 70
root=$(cd "$script_dir/.." && pwd) || die 'cannot resolve the repository root' 70

allow_doc=$root/docs/REDACTION.md
map_doc=${REDACTION_MAP:-$root/.gate/release/REDACTION-MAP.md}

[ -f "$allow_doc" ] || die "allowlist not found: $allow_doc" 66
[ -f "$map_doc" ] || die "alias map not found: $map_doc" 66

work=$(mktemp -d "${TMPDIR:-/tmp}/redact-evidence.XXXXXX") || die 'cannot create a work directory' 73
trap 'rm -rf "$work"' EXIT HUP INT TERM

# --- allowlist -------------------------------------------------------------
# C1/C2/C3 are the three allowlisted classes; the C4 line is a negative
# control and must never be treated as publishable.
grep -E '^\[C[123]\][[:space:]]+' "$allow_doc" |
	sed -E -e 's/^\[C[123]\][[:space:]]+//' -e 's/[[:space:]]+$//' |
	sort -u > "$work/allow.txt"
[ -s "$work/allow.txt" ] || die "allowlist is empty: $allow_doc" 65

# --- alias map -------------------------------------------------------------
# Machine-readable rows have the shape: <ALIAS><whitespace><source-token>
grep -E '^<[A-Z][A-Z0-9_]*(-[0-9]+)?>[[:space:]]+[^[:space:]]+[[:space:]]*$' "$map_doc" |
	sed -E -e 's/[[:space:]]+$//' -e 's/[[:space:]]+/|/' > "$work/mapraw.txt"
[ -s "$work/mapraw.txt" ] || die "alias map has no machine-readable rows: $map_doc" 65

awk -F'|' '{ print $2 }' "$work/mapraw.txt" | sort -u > "$work/mapsrc.txt"
if [ "$(wc -l < "$work/mapraw.txt")" -ne "$(wc -l < "$work/mapsrc.txt")" ]; then
	die "alias map maps the same source token more than once: $map_doc" 65
fi

# Longest source first, so that a proper prefix can never shadow a longer match
# taken from the map itself.
while IFS='|' read -r al src; do
	printf '%d|%s|%s\n' "${#src}" "$src" "$al"
done < "$work/mapraw.txt" | sort -t'|' -k1,1nr > "$work/pairs.txt"

# --- file selection --------------------------------------------------------
: > "$work/selected.txt"
for f in "$in_dir"/*; do
	[ -f "$f" ] || continue
	base=${f##*/}
	case $base in
	PM-*|notes-*|PUBLISH-*|GRADE-*) continue ;;
	*.md) continue ;;
	STOP.txt) continue ;;
	esac
	printf '%s\n' "$f" >> "$work/selected.txt"
done
[ -s "$work/selected.txt" ] || die "no publishable files in $in_dir" 65

# --- pass 1: classify every token before touching any output ---------------
: > "$work/unclassified.txt"
: > "$work/dynips.txt"

while IFS= read -r f; do
	base=${f##*/}
	grep -hoE '[A-Za-z0-9][A-Za-z0-9.-]*\.(test|com|net|org|io)(/[A-Za-z0-9._-]+)?' "$f" 2>/dev/null |
		while IFS= read -r tok; do
			grep -qxF -- "$tok" "$work/allow.txt" && continue
			case $tok in
			*/.)
				# A URL whose path is exactly "/" is normalised to its host,
				# which then has to be allowlisted in its own right.
				grep -qxF -- "${tok%/.}" "$work/allow.txt" && continue
				;;
			esac
			grep -qxF -- "$tok" "$work/mapsrc.txt" && continue
			printf '%s|%s\n' "$base" "$tok" >> "$work/unclassified.txt"
		done
	grep -hoE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$f" 2>/dev/null |
		awk -F. '{ ok = 1; for (i = 1; i <= 4; i++) if ($i + 0 > 255) ok = 0; if (ok) print }' |
		while IFS= read -r ip; do
			case $ip in
			127.0.0.1|0.0.0.0) continue ;;
			esac
			grep -qxF -- "$ip" "$work/mapsrc.txt" && continue
			grep -qxF -- "$ip" "$work/dynips.txt" || printf '%s\n' "$ip" >> "$work/dynips.txt"
		done
done < "$work/selected.txt"

if [ -s "$work/unclassified.txt" ]; then
	printf '%s: token(s) that cannot be classified; refusing to write any output\n' "$prog" >&2
	sed -e 's/^/  /' "$work/unclassified.txt" >&2
	exit 1
fi

# Addresses that are neither exempt nor in the map are still classifiable as
# public addresses, so they are aliased in first-appearance order after the
# highest <PUBLIC_IP-n> already present in the map.
base_ip=$(awk -F'|' '
	$3 ~ /^<PUBLIC_IP-[0-9]+>$/ {
		n = $3
		gsub(/[^0-9]/, "", n)
		if (n + 0 > max) max = n + 0
	}
	END { print max + 0 }
' "$work/pairs.txt")
n=0
while IFS= read -r ip; do
	n=$((n + 1))
	printf '%d|%s|%s\n' "${#ip}" "$ip" "<PUBLIC_IP-$((base_ip + n))>" >> "$work/pairs.txt"
done < "$work/dynips.txt"
if [ "$n" -gt 0 ]; then
	sort -t'|' -k1,1nr -o "$work/pairs.txt" "$work/pairs.txt"
fi

# --- pass 2: build the rewrite program -------------------------------------
# Allowlisted module paths contain "/" and share a prefix with a mapped host,
# so they are parked behind a sentinel while the aliases are applied and then
# restored verbatim. Nothing else about them changes.
: > "$work/protect.txt"
p=0
while IFS= read -r tok; do
	case $tok in
	*/*)
		p=$((p + 1))
		printf '%s|@@REDACT-PROTECT-%d@@\n' "$tok" "$p" >> "$work/protect.txt"
		;;
	esac
done < "$work/allow.txt"

if grep -rlF '@@REDACT-PROTECT-' "$in_dir" >/dev/null 2>&1; then
	die 'input already contains the internal sentinel marker' 70
fi

esc_re() {
	printf '%s' "$1" | sed -e 's/[][\.^$*+?(){}|]/\\&/g'
}

: > "$work/sed.prog"
while IFS='|' read -r tok marker; do
	printf 's|%s|%s|g\n' "$(esc_re "$tok")" "$marker" >> "$work/sed.prog"
done < "$work/protect.txt"
while IFS='|' read -r _len src al; do
	printf 's|%s|%s|g\n' "$(esc_re "$src")" "$al" >> "$work/sed.prog"
done < "$work/pairs.txt"
while IFS='|' read -r tok marker; do
	printf 's|%s|%s|g\n' "$marker" "$tok" >> "$work/sed.prog"
done < "$work/protect.txt"

# A URL path of exactly "/" adds nothing to the evidence and would otherwise
# surface as a token that the tracked-tree allowlist does not carry.
printf '%s\n' 's~(\.(test|com|net|org|io))/\.([^A-Za-z0-9._-]|$)~\1\3~g' >> "$work/sed.prog"
# Credential values are replaced positionally, so no secret is ever written
# into this script.
printf '%s\n' 's|(NAIVE_PASSWORD)([[:space:]]*=[[:space:]]*)[^<[:space:]][^[:space:]]*|\1\2<NAIVE_PASSWORD>|g' >> "$work/sed.prog"
printf '%s\n' 's|(basic_auth[[:space:]]+)[^[:space:]]+[[:space:]]+[^[:space:]]+|\1<NAIVE_USER> <NAIVE_PASSWORD>|g' >> "$work/sed.prog"
printf '%s\n' 's|"auth_credentials":\["[^"]*"\]|"auth_credentials":["<NAIVE_CREDENTIALS>"]|g' >> "$work/sed.prog"
# A user name written as key + separator + value is replaced positionally as
# well. A value that already starts with "<" is a placeholder and is left
# untouched, so feeding an already redacted file back in changes nothing.
printf '%s\n' 's|([A-Za-z_]*USER)([[:space:]]*[=:][[:space:]]*)[^<[:space:]][^[:space:]]*|\1\2<NAIVE_USER>|g' >> "$work/sed.prog"

# Credential forms that carry no key at all: an authentication header, a
# command-line argument, a URL userinfo field and a bcrypt hash. Every rule
# matches a *role* plus a separator and replaces only the value, so no
# credential literal appears in this script. Values are matched with the same
# "a value that already starts with < is a placeholder" exclusion as above, so
# a second run is a byte-for-byte no-op.

# Proxy-Authorization: Basic <base64(user:pass)>. Only the base64 alphabet is
# consumed, so the `\n\r\n'` that follows the value in a captured command line
# keeps its quoting intact.
printf '%s\n' 's~(Proxy-Authorization:[[:space:]]*Basic[[:space:]]+)[A-Za-z0-9+/=]+~\1<NAIVE_BASIC_AUTH>~g' >> "$work/sed.prog"

# PASS / PASSWORD / PASSWD as a key-name suffix, in `key = value` or
# `key: value`. The keyword has to be a *suffix*, so the key must carry at
# least one character in front of it: an ordinary tally field such as
# `PASS=24 FAIL=0` is a bare label with no prefix and is therefore left alone.
# PASSWORD and PASSWD are additionally accepted with no prefix, because
# `<NAIVE_PASSWORD>` on its own is a real configuration key, while a bare
# `PASS` is the shape a test tally uses.
printf '%s\n' 's~([A-Za-z_]+(PASS|PASSWORD|PASSWD)[A-Za-z_]*)([[:space:]]*[=:][[:space:]]*)[^<[:space:]][^[:space:]]*~\1\3<NAIVE_PASSWORD>~g' >> "$work/sed.prog"
printf '%s\n' 's~((PASSWORD|PASSWD)[A-Za-z_]*)([[:space:]]*[=:][[:space:]]*)[^<[:space:]][^[:space:]]*~\1\3<NAIVE_PASSWORD>~g' >> "$work/sed.prog"

# scheme://user:<value>@host -- the value is a run credential that no key name
# announces, so the role is the userinfo field itself.
printf '%s\n' 's~(://[^[:space:]/@]*:)[^<[:space:]@]+@~\1<NAIVE_PASSWORD>@~g' >> "$work/sed.prog"

# bcrypt hashes verify a credential; they are not the credential itself.
printf '%s\n' 's~\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{20,}~<PASSWORD_HASH>~g' >> "$work/sed.prog"

# Quoted positional arguments of a printf that feeds base64 or sha256sum. Two
# arguments are a `user:pass` pair; a single argument is the credential alone.
# A double-quoted shell variable such as "$p" is not a literal and is left
# alone. Re-running these two rules rewrites a placeholder to itself, so they
# stay idempotent.
printf '%s\n' "s~(printf[[:space:]]+'[^']*'[[:space:]]+)'[^']*'([[:space:]]+)'[^']*'([[:space:]]*\|[[:space:]]*(base64|sha256sum))~\1'<NAIVE_USER>'\2'<NAIVE_PASSWORD>'\3~g" >> "$work/sed.prog"
printf '%s\n' "s~(printf[[:space:]]+'[^']*'[[:space:]]+)'[^']*'([[:space:]]*\|[[:space:]]*(base64|sha256sum))~\1'<NAIVE_PASSWORD>'\2~g" >> "$work/sed.prog"

# The one-line outputs of those commands are a reversible encoding (base64) or
# a verifier (sha256) of the same credential. They are recognised by shape
# only -- the two sha256 lines are byte-identical to each other and cannot be
# told apart by their command. One line in, one line out: the line count is
# unchanged, which is asserted below.
printf '%s\n' 's~^[0-9a-f]{64}  -$~<PASSWORD_SHA256>~' >> "$work/sed.prog"
printf '%s\n' 's~^[A-Za-z0-9+/]{24,}={0,2}$~<NAIVE_BASIC_AUTH>~' >> "$work/sed.prog"

# --- pass 3: rewrite into staging and verify -------------------------------
stage=$work/out
mkdir -p "$stage" || die 'cannot create the staging directory' 73

while IFS= read -r f; do
	base=${f##*/}
	sed -E -f "$work/sed.prog" "$f" > "$stage/$base" || die "rewrite failed: $base" 1
	if [ "$(wc -l < "$f")" -ne "$(wc -l < "$stage/$base")" ]; then
		die "line count changed: $base" 1
	fi
done < "$work/selected.txt"

: > "$work/survivors.txt"
while IFS= read -r f; do
	base=${f##*/}
	grep -hoE '[A-Za-z0-9][A-Za-z0-9.-]*\.(test|com|net|org|io)(/[A-Za-z0-9._-]+)?' "$stage/$base" 2>/dev/null |
		while IFS= read -r tok; do
			grep -qxF -- "$tok" "$work/allow.txt" ||
				printf '%s|%s|domain token survived redaction\n' "$base" "$tok" >> "$work/survivors.txt"
		done
	grep -hoE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$stage/$base" 2>/dev/null |
		awk -F. '{ ok = 1; for (i = 1; i <= 4; i++) if ($i + 0 > 255) ok = 0; if (ok) print }' |
		while IFS= read -r ip; do
			case $ip in
			127.0.0.1|0.0.0.0) continue ;;
			esac
			printf '%s|%s|address survived redaction\n' "$base" "$ip" >> "$work/survivors.txt"
		done
	# The complementary check of the four credential shapes added above: the
	# rules stop at a value that begins with "<" (that is what makes a second
	# run a no-op), so these rescans demand that nothing but a placeholder
	# follows the role separator. A shape the rules miss therefore fails the
	# run instead of being published as if it were redacted.
	grep -nE 'Proxy-Authorization:[[:space:]]*Basic[[:space:]]+[^<]' "$stage/$base" 2>/dev/null |
		while IFS= read -r hit; do
			printf '%s|%s|authentication header survived redaction\n' "$base" "$hit" >> "$work/survivors.txt"
		done
	grep -nE '://[^[:space:]/@]+:[^<[:space:]@]+@' "$stage/$base" 2>/dev/null |
		while IFS= read -r hit; do
			printf '%s|%s|URL userinfo value survived redaction\n' "$base" "$hit" >> "$work/survivors.txt"
		done
	grep -nE '\$2[aby]\$' "$stage/$base" 2>/dev/null |
		while IFS= read -r hit; do
			printf '%s|%s|hash survived redaction\n' "$base" "$hit" >> "$work/survivors.txt"
		done
	grep -nE '(PASS|PASSWORD|PASSWD)[[:space:]]*[=:][[:space:]]*[^<]' "$stage/$base" 2>/dev/null |
		while IFS= read -r hit; do
			printf '%s|%s|keyed value survived redaction\n' "$base" "$hit" >> "$work/survivors.txt"
		done
done < "$work/selected.txt"

if [ -s "$work/survivors.txt" ]; then
	printf '%s: redaction is incomplete; refusing to write any output\n' "$prog" >&2
	sed -e 's/^/  /' "$work/survivors.txt" >&2
	exit 1
fi

# --- pass 4: publish -------------------------------------------------------
mkdir -p "$out_dir" || die "cannot create the output directory: $out_dir" 73
while IFS= read -r f; do
	base=${f##*/}
	cp "$work/out/$base" "$out_dir/$base" || die "cannot write $out_dir/$base" 73
done < "$work/selected.txt"

printf '%s: %s file(s) redacted into %s\n' "$prog" "$(wc -l < "$work/selected.txt")" "$out_dir"
