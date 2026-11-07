#!/usr/bin/env bash
# Guard the test-fixture address and protocol shapes that F-01 exposed.
#
# A non-443 listener must have a site block spelled `:port, host:port` and an
# explicit `protocols h1 h2`. Auxiliary host-specific blocks may share that
# listener, but they cannot satisfy the rule by themselves. The pin may live in
# the dual-form site block or in the global `servers :port` block that owns it;
# the rendered E2E overlay uses the latter.
# The delivery file is checked read-only, and its `:443, a.test` form is
# accepted because the second address inherits the first one's port.
#
# Usage:
#   bash tests/fixtures/check.sh        # tests/**/*.Caddyfile + deploy/Caddyfile
#   bash tests/fixtures/check.sh FILE   # explicit file(s), including rendered overlays
#
# Exit status: 0 only when every file passes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

files=()
if [ "$#" -gt 0 ]; then
	files=("$@")
else
	while IFS= read -r file; do
		files+=("$file")
	done < <(find "$REPO_ROOT/tests" -type f -name '*.Caddyfile' -print | sort)
	files+=("$REPO_ROOT/deploy/Caddyfile")
fi

if [ "${#files[@]}" -eq 0 ]; then
	printf 'FIXTURES: FAIL (no Caddyfiles found)\n'
	exit 1
fi

failed=0
for file in "${files[@]}"; do
	if [ ! -f "$file" ]; then
		printf 'FIXTURE %s FAIL\n' "$file"
		printf '  file does not exist\n' >&2
		failed=1
		continue
	fi
	if ! awk -v path="$file" '
	function trim(s) {
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
		return s
	}
	function port_of(a,  p) {
		a = trim(a)
		if (a ~ /^:[0-9]+$/)
			return substr(a, 2)
		if (a ~ /^[^:]+:[0-9]+$/) {
			p = a
			sub(/^.*:/, "", p)
			return p
		}
		if (a ~ /:/)
			return "bad"
		return "443"
	}
	function fail(msg) {
		file_bad = 1
		print "  " msg > "/dev/stderr"
	}
	BEGIN {
		depth = 0
		global = 0
		site = 0
		server = 0
		file_bad = 0
		server_count = 0
	}
	{
		line = $0
		sub(/#.*/, "", line)
		line = trim(line)
		if (line == "")
			next

		if (!global && depth == 0 && line == "{") {
			global = 1
			depth = 1
			next
		}

		if (global && depth == 1 && line ~ /^servers[[:space:]]+.*\{$/) {
			server = 1
			server_body = line
			sub(/[[:space:]]*\{[[:space:]]*$/, "", server_body)
			sub(/^servers[[:space:]]+/, "", server_body)
			server_addr = trim(server_body)
			server_has_protocols = 0
			server_ports = ""
			count = split(server_addr, parts, ",")
			for (i = 1; i <= count; i++) {
				p = port_of(parts[i])
				if (p == "bad" || p == "") {
					fail("cannot parse servers address: " parts[i])
					continue
				}
				server_ports = server_ports " " p
			}
			depth = 2
			next
		}

		if (!global && depth == 0 && line ~ /\{$/) {
			site = 1
			site_body = line
			sub(/[[:space:]]*\{[[:space:]]*$/, "", site_body)
			site_addr = trim(site_body)
			site_has_protocols = 0
			site_non443 = 0
			site_port = ""
			site_ports = ""
			site_bad = 0
			site_has_port_only = 0
			site_has_host_port = 0
			count = split(site_addr, parts, ",")
			for (i = 1; i <= count; i++) {
				a = trim(parts[i])
				if (a == "") {
					site_bad = 1
					continue
				}
				p = port_of(a)
				if (p == "bad" || p == "") {
					site_bad = 1
					continue
				}
				if (a ~ /^:[0-9]+$/)
					site_has_port_only = 1
				if (a ~ /^[^:]+:[0-9]+$/)
					site_has_host_port = 1
				if (p != "443") {
					site_non443 = 1
					if (site_ports !~ ("(^| )" p "( |$)"))
						site_ports = site_ports " " p
					if (site_port == "")
						site_port = p
					else if (site_port != p)
						site_bad = 1
				}
			}
			depth = 1
			next
		}

		opens = gsub(/\{/, "{", line)
		closes = gsub(/\}/, "}", line)
		depth += opens - closes

		if (site && depth == 1 && line == "protocols h1 h2")
			site_has_protocols = 1
		if (server && depth >= 2 && line == "protocols h1 h2")
			server_has_protocols = 1

		if (site && depth == 0) {
			if (site_bad)
				fail("cannot parse the site address: " site_addr)
			if (site_non443) {
				count = split(site_ports, ports, " ")
				for (i = 1; i <= count; i++) {
					if (ports[i] == "")
						continue
					non443_seen[ports[i]] = 1
					if (site_bad)
						non443_bad[ports[i]] = 1
					else if (site_has_port_only && site_has_host_port &&
						(site_has_protocols || server_proto[ports[i]] == 1))
						non443_ok[ports[i]] = 1
				}
			}
			site = 0
		}

		if (server && depth == 1) {
			if (server_has_protocols) {
				count = split(server_ports, ports, " ")
				for (i = 1; i <= count; i++)
					if (ports[i] != "")
						server_proto[ports[i]] = 1
			}
			server = 0
		}

		if (global && depth == 0)
			global = 0
	}
	END {
		if (site)
			fail("unclosed site block")
		if (server)
			fail("unclosed servers block")
		if (global)
			fail("unclosed global options block")
		for (p in non443_seen) {
			if (non443_bad[p])
				fail("cannot parse a non-443 site address on port " p)
			if (!non443_ok[p])
				fail("non-443 port " p " lacks `:port, host:port` with `protocols h1 h2`")
		}
		if (file_bad)
			printf "FIXTURE %s FAIL\n", path
		else
			printf "FIXTURE %s PASS\n", path
		exit file_bad ? 1 : 0
	}
	' "$file"; then
		failed=1
	fi
done

if [ "$failed" -eq 0 ]; then
	printf 'FIXTURES: PASS\n'
	exit 0
fi
printf 'FIXTURES: FAIL\n'
exit 1
