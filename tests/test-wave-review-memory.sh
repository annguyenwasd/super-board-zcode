#!/usr/bin/env bash
# Source contract for the review-memory wiring in
# .zcode/workflows/super-board-wave.dwf.ts. The ZCode engine compiles the
# workflow body (top-level return), so node cannot eval it here; the behavior
# was verified end to end on 2026-10-24 (.audit/zcode-host.tsv). The rule:
# a second review round must grade every prior finding and bounce on any
# not-fixed one, editing the existing report instead of posting a new one.
set -euo pipefail
cd "$(dirname "$0")"
W=../.zcode/workflows/super-board-wave.dwf.ts
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f "$W" ] || fail "$W is missing"

grep -q "super-review:report -->" "$W" || fail "the reviewer must load the newest prior report comment"
grep -q "fixed / not fixed / no longer applies" "$W" || fail "round 1 must grade every prior finding"
grep -q "any not fixed .> bounce\|not fixed → bounce" "$W" || grep -q "not fixed → bounce" "$W" || fail "a not-fixed finding must bounce"
grep -q "never post a second one" "$W" || fail "the report must be edited in place"
grep -q "priorFindings" "$W" || fail "the lane result must carry priorFindings counts"
grep -qE "fixed: number|notFixed: number|noLongerApplies: number" "$W" || fail "all three grade counts must be declared"
echo "PASS: test-wave-review-memory.sh (source contract)"
