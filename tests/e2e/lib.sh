#!/usr/bin/env bash
# Shared helpers for the REALITY end-to-end harness in tests/e2e/.
#
# Sourcing this file defines functions only. It starts no process, writes no
# file, and reads no environment: every value is passed in by the caller. The
# harness keeps this split so a bug in one helper cannot leave a listener
# behind simply because the file was sourced.
#
# `item` increments PASSED/FAILED, which the caller must initialise. There is
# deliberately no default: a caller that forgets would otherwise see a silent
# counter reset instead of an unbound-variable error under `set -u`.

item() { # $1=id $2=PASS|FAIL
	printf 'ITEM %s %s\n' "$1" "$2"
	case "$2" in
	PASS) PASSED=$((PASSED + 1)) ;;
	*) FAILED=$((FAILED + 1)) ;;
	esac
}

stop_pid() { # $1=pid
	local pid="${1:-}"
	[ -n "$pid" ] || return 0
	kill "$pid" 2>/dev/null
	for _ in $(seq 1 20); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.25
	done
	kill -9 "$pid" 2>/dev/null
	return 0
}

cleanup() { # $@=pids
	local pid
	for pid in "$@"; do
		stop_pid "$pid"
	done
}

port_busy() { # $1=port -> 0 when something is listening on TCP
	ss -ltn 2>/dev/null | grep -q ":$1 "
}

records() { # $1=jsonl path -> number of records
	if [ -f "$1" ]; then
		# `grep -c .` prints 0 and exits 1 on an empty file; without the
		# `|| true` the `||` branch would append a second value.
		local n
		n="$(grep -c . "$1" 2>/dev/null || true)"
		printf '%s\n' "${n:-0}"
	else
		printf '0\n'
	fi
}

wait_records() { # $1=jsonl path $2=wanted count -> prints the count it saw
	local want="$2" now
	for _ in $(seq 1 40); do
		now="$(records "$1")"
		[ "$now" -ge "$want" ] && break
		sleep 0.25
	done
	records "$1"
}

wait_port() { # $1=port $2=seconds -> 0 once the port listens
	local port="$1" seconds="$2" tries
	tries=$((seconds * 4))
	for _ in $(seq 1 "$tries"); do
		port_busy "$port" && return 0
		sleep 0.25
	done
	return 1
}

# require_env prints every missing name on its own line and returns 2. It does
# not exit: the caller decides whether the failure is fatal, which keeps the
# helper usable from `--negative-preflight` inside a subshell.
#
# A variable that is set but empty counts as missing. That is the point of the
# helper: `VAR= bash run.sh` must fail exactly like `bash run.sh` without it,
# otherwise an empty export silently disables a leg of the run.
require_env() { # $@=variable names
	local name missing=0
	for name in "$@"; do
		if [ -z "${!name:-}" ]; then
			printf 'missing %s\n' "$name" >&2
			missing=1
		fi
	done
	[ "$missing" -eq 0 ] && return 0
	return 2
}

# literal_replace replaces every literal occurrence of $1 with $2 on every
# line. It is literal, not a regex: the REALITY SNI and the two fork SHAs are
# external values and a stray `.` must not become a wildcard.
literal_replace() { # $1=old $2=new  (reads stdin, writes stdout)
	local old="$1" new="$2"
	awk -v old="$old" -v new="$new" '
		{
			out = ""
			line = $0
			while ((i = index(line, old)) > 0) {
				out = out substr(line, 1, i - 1) new
				line = substr(line, i + length(old))
			}
			print out line
		}
	'
}
