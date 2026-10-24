#!/usr/bin/env bash
# Source contract for the ui-refine loop in
# .zcode/workflows/ui-refine-loop.dwf.ts. The ZCode engine compiles the
# workflow body (top-level return), so node cannot eval it here. The rule:
# every round runs fresh, isolated checker and fixer agents; a closing check
# follows the last round; the fixer may only edit the declared targets.
set -euo pipefail
cd "$(dirname "$0")"
W=../.zcode/workflows/ui-refine-loop.dwf.ts
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f "$W" ] || fail "$W is missing"

grep -q "rounds" "$W" || fail "the workflow must be round-based"
grep -qi "checker" "$W" || fail "each round needs a checker that ranks typed problems"
grep -qi "fixer" "$W" || fail "each round needs a fixer"
grep -qi "impeccable" "$W" || fail "the fixer must chain Impeccable when present"
grep -q "closing check" "$W" || fail "a closing check must follow the last round"
grep -q "repo-relative paths the fixer may edit" "$W" || fail "fixer targets must be an explicit allowlist"
echo "PASS: test-ui-refine-loop-workflow.sh (source contract)"
