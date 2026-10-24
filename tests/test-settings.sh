#!/usr/bin/env bash
# Tests super-board-settings.py zcode-hooks — install.sh's guard wiring: merge
# each hook once per event + matcher, keep every existing key, set the enabled
# flag ZCode requires only when something was added.
set -euo pipefail
cd "$(dirname "$0")"
S="$PWD/../scripts/super-board-settings.py"
fail() { echo "FAIL: $1" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# 1 — zcode-hooks: same snippets, one level deeper (hooks.events.<Event>) plus the
#     enabled flag ZCode requires; existing keys kept; a no-op re-run leaves
#     enabled:false alone; invalid JSON untouched.
SNIP="$T/snippet.json"
cat > "$SNIP" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard-x.py"}]}]}}
EOF
Z="$T/proj/.zcode/config.json"; mkdir -p "$T/proj/.zcode"
echo '{"mcp":{"servers":{"s":{}}}}' > "$Z"
python3 "$S" zcode-hooks "$Z" "$SNIP" >/dev/null
jq -e '.hooks.enabled == true and (.hooks.events.PreToolUse | length) == 1 and
       .hooks.events.PreToolUse[0].hooks[0].command == "guard-x.py" and
       .mcp.servers.s == {}' "$Z" >/dev/null || fail "zcode-hooks merge wrong: $(cat "$Z")"
python3 "$S" zcode-hooks "$Z" "$SNIP" | grep -q "already present" || fail "second zcode-hooks run should change nothing"
jq -e '.hooks.events.PreToolUse | length == 1' "$Z" >/dev/null || fail "second run duplicated entries"
jq '.hooks.enabled = false' "$Z" > "$Z.tmp" && mv "$Z.tmp" "$Z"
python3 "$S" zcode-hooks "$Z" "$SNIP" >/dev/null
jq -e '.hooks.enabled == false' "$Z" >/dev/null || fail "a no-op re-run must not flip enabled back on"
printf '{ nope' > "$Z"; RC=0; python3 "$S" zcode-hooks "$Z" "$SNIP" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || fail "invalid zcode config must exit 2 (rc $RC)"

echo "PASS: test-settings.sh (1 scenario)"
