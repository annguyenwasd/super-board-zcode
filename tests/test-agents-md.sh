#!/usr/bin/env bash
# Tests super-board-agents-md.py — the deterministic half of onboard's AGENTS.md
# step: detection, backup, the managed block (nothing outside the markers ever
# changes), rule-unit splitting and the lossless check.
set -euo pipefail
cd "$(dirname "$0")"
AM="$PWD/../scripts/super-board-agents-md.py"
fail() { echo "FAIL: $1" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
am() { python3 "$AM" "$@"; }

# 1 — detect: names the instruction files that exist; exactly the files and agents keys.
printf '# Rules\n\n- Use pnpm.\n' > "$T/GEMINI.md"
am detect --root "$T" | jq -e '(.files["GEMINI.md"]) and ((keys | sort) == ["agents","files"])' >/dev/null \
  || fail "detect must report exactly files and agents: $(am detect --root "$T")"

# 2 — backup copies every instruction file before anything is rewritten.
B=$(am backup --root "$T"); [ -f "$B/GEMINI.md" ] || fail "backup should hold GEMINI.md, got: $B"

# 3 — block --create starts AGENTS.md; a second run is a no-op.
[ "$(am block --root "$T" --create --version 9.9.9)" = created ] || fail "block --create should create"
grep -q '^<!-- super-board:begin v9.9.9' "$T/AGENTS.md" || fail "begin marker with version missing"
grep -q '^<!-- super-board:end -->' "$T/AGENTS.md" || fail "end marker missing"
[ "$(am block --root "$T" --version 9.9.9)" = unchanged ] || fail "re-running the same block must be a no-op"

# 4 — THE CONTRACT: a re-install rewrites only the managed block. Text above and
#     below it, including a user's edit, survives byte for byte.
{ echo "# AGENTS.md"; echo; echo "- user rule above"; sed -n '/super-board:begin/,/super-board:end/p' "$T/AGENTS.md"; echo "- user rule below"; } > "$T/A2"
mv "$T/A2" "$T/AGENTS.md"
sed -i.bak 's/^## Super Board$/## Super Board (hand-edited)/' "$T/AGENTS.md"; rm -f "$T/AGENTS.md.bak"
[ "$(am block --root "$T" --version 10.0.0)" = updated ] || fail "a new version should update the block"
grep -q '^- user rule above$' "$T/AGENTS.md" && grep -q '^- user rule below$' "$T/AGENTS.md" || fail "text outside the markers changed"
grep -q 'hand-edited' "$T/AGENTS.md" && fail "an edit inside the block should be overwritten"
[ "$(grep -c 'super-board:begin' "$T/AGENTS.md")" -eq 1 ] || fail "exactly one block after update"

# 5 — an existing AGENTS.md with no block gets one appended; two blocks or a
#     dangling begin marker are refused rather than guessed at.
printf '# AGENTS.md\n\n- mine\n' > "$T/AGENTS.md"
[ "$(am block --root "$T")" = inserted ] || fail "a block should be appended"
head -3 "$T/AGENTS.md" | grep -q '^- mine$' || fail "the user's text must stay first"
cat "$T/AGENTS.md" "$T/AGENTS.md" > "$T/dup.md"; mv "$T/dup.md" "$T/AGENTS.md"
RC=0; am block --root "$T" >/dev/null 2>&1 || RC=$?; [ "$RC" -eq 2 ] || fail "two blocks should be refused (2), got $RC"
printf '<!-- super-board:begin v1 -->\nx\n' > "$T/AGENTS.md"
RC=0; am block --root "$T" >/dev/null 2>&1 || RC=$?; [ "$RC" -eq 2 ] || fail "a dangling begin should be refused, got $RC"

# 6 — units: one per bullet / table row / paragraph, heading path kept, managed
#     block and table separators skipped.
printf '# R\n\n## Build\n\n- Use pnpm.\n  continued.\n- Run tests.\n\n| a | b |\n|---|---|\n| x | y |\n\nA paragraph.\n\n<!-- super-board:begin v1 -->\n- managed\n<!-- super-board:end -->\n' > "$T/R.md"
U=$(am units --file "$T/R.md")
echo "$U" | jq -e 'length == 5' >/dev/null || fail "expected 5 units, got: $U"
echo "$U" | jq -e '.[0].heading == "R > Build" and (.[0].text | test("continued"))' >/dev/null || fail "bullet + continuation + heading path: $U"
echo "$U" | jq -e 'all(.[]; .text | test("managed") | not)' >/dev/null || fail "managed block must be skipped"

# 7 — coverage: every unit maps to a real line or is dropped on purpose.
printf -- '- Use pnpm only.\n' > "$T/NEW.md"
echo '[{"id":"U1","text":"Use pnpm.","maps_to":"- Use pnpm only."},{"id":"U2","text":"old","dropped":"user: stale"}]' > "$T/u.json"
am coverage --units "$T/u.json" --target "$T/NEW.md" >/dev/null || fail "a fully mapped set should pass"
echo '[{"id":"U1","text":"Use pnpm.","maps_to":"- Use npm."},{"id":"U2","text":"Run tests."}]' > "$T/u.json"
RC=0; OUT=$(am coverage --units "$T/u.json" --target "$T/NEW.md" 2>/dev/null) || RC=$?
[ "$RC" -eq 1 ] || fail "unmapped units should exit 1, got $RC"
echo "$OUT" | grep -q '^U1: maps_to line not found' && echo "$OUT" | grep -q '^U2: no maps_to' || fail "each gap must be named: $OUT"

# 8 — check: ≤ max lines, one marker pair.
seq 1 201 > "$T/big.md"
RC=0; am check --file "$T/big.md" >/dev/null || RC=$?; [ "$RC" -eq 1 ] || fail "201 lines should fail the size check"
am block --root "$T" --file ok.md --create >/dev/null; am check --file "$T/ok.md" >/dev/null || fail "a fresh block file should pass check"

# 9 — the shipped block template fits the budget with room for the user's rules.
N=$(wc -l < ../skills/super-board/references/agents-md-block.md)
[ "$N" -le 40 ] || fail "the managed block is $N lines; keep it ≤ 40 so AGENTS.md stays under 200"

echo "PASS: test-agents-md.sh (9 scenarios)"
