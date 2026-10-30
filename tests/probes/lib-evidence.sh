#!/usr/bin/env bash
# Evidence writer for Gate 0 probes (format: spec section 14 / appendix D).
# Sourced by the probe scripts; not executed on its own.
#
#   evidence_init <file> <item> <env>       open the evidence file, reset assertions
#   ev_block <command> <exit> <output-file> record one command + exit code + key output
#   ev_note <text>                          record a non-assertion remark
#   ev_assert <name> <PASS|FAIL|NOT-TESTED> [detail]
#                                           record one expectation. NOT-TESTED does
#                                           not fail the item, but it never counts
#                                           as PASS either (spec 4.0 convention 3).
#   evidence_finish <PASS|FAIL> [note]      flush the per-item list and the verdict

evidence_init() {
	EVIDENCE_FILE="$1"
	ASSERT_LOG="${GATE_DIR:?}/asserts.$(basename "$1")"
	ASSERT_FAIL=0
	ASSERT_NT=0
	mkdir -p "$(dirname "$EVIDENCE_FILE")"
	: > "$ASSERT_LOG"
	{
		printf '[条目] %s\n' "$2"
		printf '[时间] %s\n' "$(date -u +%FT%TZ)"
		printf '[环境] %s\n' "$3"
	} > "$EVIDENCE_FILE"
}

ev_block() {
	local cmd="$1" code="$2" out="$3" n
	{
		printf '[命令] %s\n' "$cmd"
		printf '[退出码] %s\n' "$code"
		printf '[关键输出]\n'
		if [ -f "$out" ]; then
			n=$(wc -l < "$out" | tr -d ' ')
			if [ "$n" -le 7 ]; then
				cat "$out"
			else
				head -n 3 "$out"
				printf '... (%s lines total) ...\n' "$n"
				tail -n 3 "$out"
			fi
		else
			printf '%s\n' "$out"
		fi
		printf '\n'
	} >> "$EVIDENCE_FILE"
}

ev_note() {
	printf '[备注] %s\n' "$*" >> "$EVIDENCE_FILE"
}

ev_assert() {
	local name="$1" verdict="$2" detail="${3:-}"
	printf '%s: %s%s\n' "$name" "$verdict" "${detail:+ -- $detail}" >> "$ASSERT_LOG"
	case "$verdict" in
	PASS) ;;
	NOT-TESTED) ASSERT_NT=$((ASSERT_NT + 1)) ;;
	*) ASSERT_FAIL=1 ;;
	esac
}

evidence_finish() {
	{
		printf '[逐项]\n'
		cat "$ASSERT_LOG"
		printf '[判定] %s\n' "$1"
	} >> "$EVIDENCE_FILE"
	if [ -n "${2:-}" ]; then
		printf '[备注] %s\n' "$2" >> "$EVIDENCE_FILE"
	fi
	if [ "$ASSERT_NT" -gt 0 ]; then
		printf '[备注] %s sub-item(s) NOT-TESTED; they are not counted as PASS\n' "$ASSERT_NT" >> "$EVIDENCE_FILE"
	fi
	return 0
}
