#!/usr/bin/env bash
# Static guard for the license conclusion. It does not provide legal advice;
# it makes the recorded texts, hashes, SPDX identifiers and repository notice
# fail closed when someone edits one half of the record.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

fail() {
	printf 'LICENSES: FAIL - %s\n' "$*" >&2
	exit 1
}

[ -f LICENSE ] || fail "missing LICENSE"
[ -f THIRD_PARTY_NOTICES.md ] || fail "missing THIRD_PARTY_NOTICES.md"
[ -f docs/LICENSING.md ] || fail "missing docs/LICENSING.md"

expected_hashes=$'Apache-2.0.txt cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30\nBSD-3-Clause-Go.txt 911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad\nMIT.txt 77d0b7b53e8abb84cf4dd3f9945a7fdf27044240d2e8023966a721a9a46fe96e\nMPL-2.0.txt 1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5'

while read -r file want; do
	[ -n "$file" ] || continue
	path="LICENSES/$file"
	[ -f "$path" ] || fail "missing $path"
	got=$(sha256sum "$path" | awk '{print $1}')
	[ "$got" = "$want" ] || fail "$path hash is $got, expected $want"
done <<<"$expected_hashes"

grep -qx 'SPDX-License-Identifier: LicenseRef-Proprietary' LICENSE \
	|| fail "LICENSE does not declare LicenseRef-Proprietary"
grep -qi 'all rights reserved' LICENSE \
	|| fail "LICENSE does not state the all-rights-reserved posture"

for spdx in Apache-2.0 MIT BSD-3-Clause MPL-2.0 LicenseRef-Proprietary; do
	grep -q "$spdx" docs/LICENSING.md \
		|| fail "docs/LICENSING.md does not name $spdx"
done

for component in \
	Caddy \
	caddy-l4 \
	forwardproxy \
	quic-go \
	'Go runtime' \
	xcaddy \
	Xray-core; do
	grep -q "$component" THIRD_PARTY_NOTICES.md \
		|| fail "THIRD_PARTY_NOTICES.md does not name $component"
done

grep -q 'patches/caddy-read-idle-timeout.patch' THIRD_PARTY_NOTICES.md \
	|| fail "the Caddy modification notice is missing"
grep -q 'v0.4.3' THIRD_PARTY_NOTICES.md \
	|| fail "THIRD_PARTY_NOTICES.md does not name the release it covers"

printf 'LICENSES: PASS\n'
