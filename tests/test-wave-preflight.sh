#!/usr/bin/env bash
# Source contract for the Builder pre-flight wiring in
# .zcode/workflows/super-board-wave.dwf.ts. The ZCode engine compiles the
# workflow body (top-level return), so node cannot eval it here; the behavior
# was verified end to end on 2026-10-24 (.audit/zcode-host.tsv). These checks
# guard the wiring every pre-flight relies on: no Ready card reaches the build
# lane without a verdict that says go, and non-go verdicts surface in the
# card's history instead of being dropped.
set -euo pipefail
cd "$(dirname "$0")"
W=../.zcode/workflows/super-board-wave.dwf.ts
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f "$W" ] || fail "$W is missing"

grep -q "preflightGo" "$W" || fail "pre-flight verdicts must gate the build lane"
grep -qE "verdict === 'proceed'" "$W" || fail "only a proceed verdict builds"
grep -q "verdict === 'sequence'" "$W" || fail "a sequence verdict staying in Ready must build"
grep -q "preflightExit" "$W" || fail "a non-go verdict must be recorded, never silently dropped"
grep -q "not built unchecked" "$W" || fail "a missing verdict must fall back to skipped, retried next wave"
grep -q "preflight:\${batch" "$W" || grep -q 'preflight:${batch' "$W" || grep -q "preflight:\`" "$W" || fail "pre-flight must batch its agent calls"
grep -q "runLane('build'" "$W" || fail "the build lane must be dispatched by the wave"
grep -q -- "--host zcode" "$W" || fail "the skills check inside the wave must pass --host zcode"
echo "PASS: test-wave-preflight.sh (source contract)"
