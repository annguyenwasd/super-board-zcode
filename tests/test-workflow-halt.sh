#!/usr/bin/env bash
# Source contract for halt propagation in .zcode/workflows/super-board-wave.dwf.ts.
# The ZCode engine compiles the workflow body, so node cannot eval it here; the
# behavior was verified end to end on 2026-10-24 (.audit/zcode-host.tsv).
set -euo pipefail
cd "$(dirname "$0")"
W=../.zcode/workflows/super-board-wave.dwf.ts
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f "$W" ] || fail "$W is missing"

grep -q "halted" "$W" || fail "the wave must track a halted flag"
grep -q "Verification-readiness" "$W" || fail "a verification-readiness halt must be named"
grep -q "skills-readiness" "$W" || fail "a skills-readiness halt must be named"
grep -q "exit 79\|79 means\|github-read" "$W" || fail "the GitHub read policy must be referenced"
grep -q "{ cards: summary, halted }" "$W" || fail "the wave must return the {cards, halted} summary"
echo "PASS: test-workflow-halt.sh (source contract)"
