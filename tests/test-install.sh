#!/usr/bin/env bash
# Tests install.sh against plain, linked, and self-vendored target layouts.
#
# THIS FILE EXISTS BECAUSE INSTALL.SH ONCE DELETED 190 DIRECTORIES.
#
# On 2026-08-20 a symlink-aware install path resolved its destination by hand:
#
#   resolved=$(cd "$(dirname "$dest")" && cd "$(readlink "$dest")" && pwd)
#
# `cd ""` SUCCEEDS in bash. It is a no-op that returns 0 and leaves you where you
# were. So when `readlink` produced nothing, `resolved` became the PARENT —
# .zcode/skills — and the `rm -rf "$dest"/*` that followed emptied the user's
# entire skills tree rather than one skill's contents.
#
# Every scenario below plants decoy directories beside the four skills and
# asserts they are still there afterwards. An installer is allowed to fail; it is
# never allowed to take the neighbours with it.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL="../install.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
plant_decoys() { for d in decoy-one decoy-two decoy-three; do mkdir -p "$1/.zcode/skills/$d"; touch "$1/.zcode/skills/$d/SKILL.md"; done; }
decoys_intact() { [ "$(ls "$1/.zcode/skills" | grep -c '^decoy')" -eq 3 ]; }

# Strip host signs a developer shell may leak, so the layout under test stays
# predictable (zcode is linked unconditionally now).
unset CODEX_THREAD_ID CODEX_SESSION_ID SUPER_BOARD_HOST OPENCODE ZCODE_APP_VERSION CLAUDECODE

SKILLS="super-board super-build super-qa super-review"
ALL_SKILLS="$SKILLS super-collect ui-refine-loop visual git-sync"

# 1 — a fresh project: plain directories, nothing to preserve. Every primary and
#     secondary skill lands, and both workflows.
T=$(mktemp -d)
"$INSTALL" "$T" >/dev/null 2>&1
for s in $ALL_SKILLS; do
  [ -f "$T/.zcode/skills/$s/SKILL.md" ] || fail "plain layout: $s/SKILL.md missing"
done
for w in super-board-wave.dwf.ts ui-refine-loop.dwf.ts; do
  [ -f "$T/.zcode/workflows/$w" ] || fail "workflow $w was not installed"
done
rm -rf "$T"

# 2 — a project that symlinks .zcode/skills/<name> at a real tree elsewhere.
#     The symlink must survive, the content must land at the target, and the
#     neighbours must be untouched.
T=$(mktemp -d)
mkdir -p "$T/.zcode/skills"
for s in $SKILLS; do
  mkdir -p "$T/.agents/skills/$s"
  ( cd "$T/.zcode/skills" && ln -s "../../.agents/skills/$s" "$s" )
done
plant_decoys "$T"
"$INSTALL" "$T" >/dev/null 2>&1
for s in $SKILLS; do
  [ -L "$T/.zcode/skills/$s" ] || fail "symlink layout: $s stopped being a symlink"
  [ -f "$T/.agents/skills/$s/SKILL.md" ] || fail "symlink layout: $s content did not reach the real path"
done
decoys_intact "$T" || fail "symlink layout: DECOYS DESTROYED — the 2026-08-20 regression is back"
rm -rf "$T"

# 3 — a symlink pointing nowhere. Skip it and say so; never guess, never delete.
T=$(mktemp -d)
mkdir -p "$T/.zcode/skills"
( cd "$T/.zcode/skills" && ln -s ../../nowhere/super-board super-board )
plant_decoys "$T"
OUT=$("$INSTALL" "$T" 2>&1 || true)
echo "$OUT" | grep -q "pointing nowhere" || fail "a dangling symlink should be reported, got: $OUT"
decoys_intact "$T" || fail "dangling symlink: DECOYS DESTROYED"
rm -rf "$T"

# 4 — the guard of last resort. Even if resolution goes wrong, a destination that
#     is not named after the skill is refused before anything is removed.
T=$(mktemp -d)
mkdir -p "$T/.zcode/skills" "$T/elsewhere"
( cd "$T/.zcode/skills" && ln -s ../../elsewhere super-board )
plant_decoys "$T"
OUT=$("$INSTALL" "$T" 2>&1 || true)
echo "$OUT" | grep -q "which is not a super-board directory" \
  || fail "a mis-resolved destination should be refused by name, got: $OUT"
[ "$(ls "$T/elsewhere" | wc -l | tr -d ' ')" -eq 0 ] || fail "the refused destination must not be written to"
decoys_intact "$T" || fail "mis-resolved destination: DECOYS DESTROYED"
rm -rf "$T"

# 4b — a vendored pack is already exposed through two layers of skill links.
#      Refreshing it must preserve the source and both links, on repeated runs.
T=$(mktemp -d)
PACK="$T/_skills/vendor/super-board"
mkdir -p "$PACK" "$T/.agents/skills" "$T/.zcode/skills"
cp -R ../install.sh ../VERSION ../skills ../scripts ../hooks "$PACK/"
for s in $ALL_SKILLS; do
  ln -s "../../_skills/vendor/super-board/skills/$s" "$T/.agents/skills/$s"
  ln -s "../../.agents/skills/$s" "$T/.zcode/skills/$s"
done
plant_decoys "$T"
for run in 1 2; do
  OUT=$("$PACK/install.sh" --no-hooks "$T" 2>&1) || fail "self-vendored refresh failed: $OUT"
  diff -qr ../skills "$PACK/skills" >/dev/null || fail "self-vendored refresh changed the source skills"
  for s in $ALL_SKILLS; do
    [ -L "$T/.zcode/skills/$s" ] && [ -L "$T/.agents/skills/$s" ] \
      || fail "self-vendored refresh replaced a link for $s"
    [ -f "$T/.zcode/skills/$s/SKILL.md" ] || fail "self-vendored refresh lost $s"
  done
  decoys_intact "$T" || fail "self-vendored refresh: DECOYS DESTROYED"
done
rm -rf "$T"

# 4c — individual helper links also point into the vendored pack. Both the full
#      hook install and the push-guard-only path must tolerate the same files.
T=$(mktemp -d)
PACK="$T/_skills/vendor/super-board"
mkdir -p "$PACK" "$T/.zcode/bin" "$T/.zcode/workflows" "$T/.zcode/hooks"
cp -R ../install.sh ../VERSION ../skills ../scripts ../hooks "$PACK/"
for group in scripts hooks; do
  case "$group" in scripts) dest=bin ;; *) dest="$group" ;; esac
  for src in "$PACK/$group/"*; do
    [ -f "$src" ] || continue
    ln -s "$src" "$T/.zcode/$dest/$(basename "$src")"
  done
done
for flags in '--protect-main' '--no-hooks --protect-main'; do
  OUT=$("$PACK/install.sh" $flags "$T" 2>&1) || fail "linked helper refresh failed: $OUT"
  for group in scripts hooks; do
    diff -qr "../$group" "$PACK/$group" >/dev/null || fail "linked helper refresh changed source $group"
  done
  for file in bin/super-board-host.sh hooks/guard-protected-push.py; do
    [ -L "$T/.zcode/$file" ] || fail "linked helper refresh replaced $file"
    [ -s "$T/.zcode/$file" ] || fail "linked helper refresh emptied $file"
  done
done
rm -rf "$T"

# 4d — a linked destination contains the pack itself. Refuse before clearing it.
T=$(mktemp -d)
PACK="$T/super-board/vendor"
mkdir -p "$PACK" "$T/.zcode/skills"
cp -R ../install.sh ../VERSION ../skills ../scripts ../hooks "$PACK/"
ln -s "$T/super-board" "$T/.zcode/skills/super-board"
plant_decoys "$T"
if OUT=$("$PACK/install.sh" --no-hooks "$T" 2>&1); then
  fail "a destination containing the source pack was accepted"
fi
diff -qr ../skills "$PACK/skills" >/dev/null || fail "overlapping destination erased source skills"
diff -qr ../scripts "$PACK/scripts" >/dev/null || fail "overlapping destination erased source scripts"
echo "$OUT" | grep -q 'overlap' || fail "source overlap should be explained: $OUT"
decoys_intact "$T" || fail "overlapping destination: DECOYS DESTROYED"
rm -rf "$T"

# 4e — copying a skill into a directory within itself is unsafe too. It must
#      fail before partially copying files or changing the original source.
T=$(mktemp -d)
PACK="$T/pack"
mkdir -p "$PACK" "$T/.zcode/skills"
cp -R ../install.sh ../VERSION ../skills ../scripts ../hooks "$PACK/"
mkdir -p "$PACK/skills/super-board/nested/super-board"
ln -s "$PACK/skills/super-board/nested/super-board" "$T/.zcode/skills/super-board"
cp -R "$PACK/skills" "$T/expected-skills"
plant_decoys "$T"
if OUT=$("$PACK/install.sh" --no-hooks "$T" 2>&1); then
  fail "a destination inside the source skill was accepted"
fi
diff -qr "$T/expected-skills" "$PACK/skills" >/dev/null || fail "nested destination changed source skills"
echo "$OUT" | grep -q 'overlap' || fail "nested source overlap should be explained: $OUT"
decoys_intact "$T" || fail "nested destination: DECOYS DESTROYED"
rm -rf "$T"

# 5 — every dispatcher script the skills reference is actually shipped. A verb
#     whose script was never installed fails only when a user reaches for it.
T=$(mktemp -d)
"$INSTALL" "$T" >/dev/null 2>&1
for s in super-board-stop.sh super-board-wave-plan.sh \
         super-board-card.sh super-board-throttle.sh super-board-host.sh \
         super-board-deps.sh super-board-preflight.sh super-board-merge-gate.sh super-board-pr-body.sh \
         super-review-file-refactor.sh super-qa-file-bug.sh; do
  [ -x "$T/.zcode/bin/$s" ] || fail "$s was not installed, or is not executable"
done
rm -rf "$T"

# 6 — guard hooks: scripts copied, settings merged into an existing file without
#     losing its keys or hooks, backed up first, and a second run adds nothing.
T=$(mktemp -d)
mkdir -p "$T/.zcode"
cat > "$T/.zcode/config.json" <<'JSON'
{"mcp":{"servers":{}},"hooks":{"enabled":true,"events":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo stop"}]}]}}}
JSON
"$INSTALL" "$T" >/dev/null 2>&1
for h in guard-worktree-path.py guard-secrets.py guard-key-literals.py guard-delete-outside.py guard-protected-push.py cleanup-wt.py; do
  [ -f "$T/.zcode/hooks/$h" ] || fail "hook $h was not installed"
done
[ ! -e "$T/.zcode/skills/cleanup-wt" ] || fail "cleanup-wt is a hook now, not a skill"
[ ! -e "$T/.zcode/hooks/dev" ] && [ ! -e "$T/.zcode/hooks/gate-skill-evals.py" ] || fail "hooks/dev/ (skill-eval gate) must never be installed into a target"
S="$T/.zcode/config.json"
jq -e '.mcp.servers == {}' "$S" >/dev/null || fail "existing config keys were lost"
jq -e '.hooks.enabled == true' "$S" >/dev/null || fail "hooks must end up enabled"
jq -e '[.hooks.events.PreToolUse[].hooks[].command] | index("echo mine") != null' "$S" >/dev/null || fail "existing PreToolUse hook was lost"
jq -e '.hooks.events.Stop[0].hooks[0].command == "echo stop"' "$S" >/dev/null || fail "existing Stop hook was lost"
jq -e '[.hooks.events.PreToolUse[] | select(.matcher == "Bash")] | length == 1' "$S" >/dev/null || fail "Bash matcher entry duplicated"
jq -e '[.hooks.events.SessionStart[].hooks[].command | select(contains("cleanup-wt.py --auto"))] | length == 1' "$S" >/dev/null \
  || fail "the cleanup-wt SessionStart hook is not wired by default"
jq -e '[.hooks.events[][].hooks[].command | select(contains("guard-protected-push"))] | length == 0' "$S" >/dev/null \
  || fail "the protected-push guard is opt-in: it must not be wired without --protect-main"
for h in guard-worktree-path guard-secrets guard-key-literals guard-delete-outside; do
  jq -e --arg h "$h" '[.hooks.events[][].hooks[].command | select(contains($h))] | length > 0' "$S" >/dev/null || fail "$h not wired in config"
done
ls "$T/.zcode/" | grep -q '^config.json.bak-' || fail "no backup written before changing config.json"
BEFORE=$(cat "$S")
OUT=$("$INSTALL" "$T" 2>&1)
[ "$(cat "$S")" = "$BEFORE" ] || fail "a second install changed config.json"
echo "$OUT" | grep -q "already present" || fail "a second install should report nothing to change, got: $OUT"
jq -e '[.hooks.events[] | [.[].hooks[].command] as $c | ($c | length) == ($c | unique | length)] | all' "$S" >/dev/null \
  || fail "a hook command appears twice in one event"
rm -rf "$T"

# 7 — --no-hooks: no hook scripts, no settings.json written.
T=$(mktemp -d)
"$INSTALL" --no-hooks "$T" >/dev/null 2>&1
[ ! -e "$T/.zcode/hooks" ] || fail "--no-hooks still installed hooks"
[ ! -e "$T/.zcode/config.json" ] || fail "--no-hooks still wrote config.json"
[ -f "$T/.zcode/skills/super-board/SKILL.md" ] || fail "--no-hooks must still install the skills"
rm -rf "$T"

# 7b — --no-hooks --protect-main: exactly the one guard, wired; no other hook.
#      Onboard names this command when protect-main finds no guard script.
T=$(mktemp -d)
"$INSTALL" --no-hooks --protect-main "$T" >/dev/null 2>&1
[ "$(ls "$T/.zcode/hooks")" = "guard-protected-push.py" ] || fail "--no-hooks --protect-main should install only the push guard, got: $(ls "$T/.zcode/hooks")"
jq -e '[.hooks.events[][].hooks[].command] == ["python3 \"${ZCODE_PROJECT_DIR}\"/.zcode/hooks/guard-protected-push.py"]' "$T/.zcode/config.json" >/dev/null \
  || fail "--no-hooks --protect-main should wire only the push guard"
rm -rf "$T"

# 8 — a config.json that is not valid JSON is left exactly as it was.
T=$(mktemp -d)
mkdir -p "$T/.zcode"; printf '{ not json' > "$T/.zcode/config.json"
OUT=$("$INSTALL" "$T" 2>&1 || true)
[ "$(cat "$T/.zcode/config.json")" = "{ not json" ] || fail "invalid config.json was modified"
echo "$OUT" | grep -q "not valid JSON" || fail "invalid config.json should be reported, got: $OUT"
rm -rf "$T"

# 10 — --protect-main wires the opt-in push guard, once, next to the defaults.
T=$(mktemp -d)
"$INSTALL" --protect-main "$T" >/dev/null 2>&1
S="$T/.zcode/config.json"
jq -e '[.hooks.events.PreToolUse[].hooks[].command | select(contains("guard-protected-push.py"))] | length == 1' "$S" >/dev/null \
  || fail "--protect-main did not wire guard-protected-push"
jq -e '[.hooks.events.PreToolUse[] | select(.matcher == "Bash")] | length == 1' "$S" >/dev/null || fail "--protect-main duplicated the Bash matcher"
OUT=$("$INSTALL" --protect-main "$T" 2>&1)
echo "$OUT" | grep -q "already present" || fail "a second --protect-main install should change nothing"
rm -rf "$T"

# 11 — AGENTS.md: a re-install refreshes only the managed block; a project without
#      a block is left alone; the last line names onboard as the one next step.
T=$(mktemp -d)
printf '# AGENTS.md\n\n- keep me\n<!-- super-board:begin v0.0.1 -->\nold\n<!-- super-board:end -->\n- and me\n' > "$T/AGENTS.md"
OUT=$("$INSTALL" --no-hooks "$T" 2>&1)
grep -q '^- keep me$' "$T/AGENTS.md" && grep -q '^- and me$' "$T/AGENTS.md" || fail "install changed AGENTS.md outside the markers"
grep -q '^old$' "$T/AGENTS.md" && fail "install should refresh the managed block"
grep -q "super-board:begin v$(cat ../VERSION)" "$T/AGENTS.md" || fail "block should carry the pack version"
[ "$(echo "$OUT" | tail -1)" = "👉 next: open ZCode here and run /super-board onboard" ] || fail "last line should name onboard, got: $(echo "$OUT" | tail -1)"
echo "$OUT" | grep -q "📜 AGENTS.md: super-board block refreshed" || fail "the block refresh should be one grouped line, got: $OUT"
rm -rf "$T"
# SUPER_BOARD_QUIET_NEXT=1 (set by get.sh, which prints its own header and next step)
# prints only the 🔧 installing group: one line per group of files, no per-file list.
T=$(mktemp -d)
OUT=$(SUPER_BOARD_QUIET_NEXT=1 "$INSTALL" "$T" 2>&1)
[ "$(echo "$OUT" | head -1)" = "🔧 installing" ] || fail "quiet mode should start at the installing group, got: $OUT"
echo "$OUT" | grep -q "next:" && fail "quiet mode must not print the next step"
echo "$OUT" | grep -q "✓ skills and scripts → .agents/" || fail "quiet mode should print the grouped files line"
echo "$OUT" | grep -q "🛡️  6 guard hooks → .zcode/config.json (new file)" || fail "guard line should count hooks, got: $OUT"
[ "$(echo "$OUT" | wc -l | tr -d ' ')" -le 3 ] || fail "grouped output should be ≤ 3 lines here, got: $OUT"
jq -e '.hooks.enabled == true and (.hooks.events.PreToolUse | length) == 3 and (.hooks.events.SessionStart | length) == 1' \
  "$T/.zcode/config.json" >/dev/null || fail "zcode hooks config wrong: $(cat "$T/.zcode/config.json")"
rm -rf "$T"

# 12 — upgrade record: an older super-board in the target is written to
#      .zcode/super-board/upgrade.json (from, to, the skills that are new) for onboard.
T=$(mktemp -d); mkdir -p "$T/.zcode/skills/super-board" "$T/.zcode/skills/super-build"
echo "1.8.2" > "$T/.zcode/skills/super-board/VERSION"
OUT=$("$INSTALL" --no-hooks "$T" 2>&1)
jq -e --arg v "$(cat ../VERSION)" '.from == "1.8.2" and .to == $v and (.added_skills | index("super-collect")) and (.added_skills | index("super-build") | not)' \
  "$T/.zcode/super-board/upgrade.json" >/dev/null || fail "upgrade.json wrong: $(cat "$T/.zcode/super-board/upgrade.json" 2>&1)"
echo "$OUT" | grep -q "⬆️  upgrade from 1.8.2" || fail "the upgrade should be one grouped line, got: $OUT"
"$INSTALL" --no-hooks "$T" >/dev/null 2>&1
jq -e '.from == "1.8.2"' "$T/.zcode/super-board/upgrade.json" >/dev/null || fail "a second install must keep the original from-version"
rm -rf "$T"
T=$(mktemp -d); "$INSTALL" --no-hooks "$T" >/dev/null 2>&1
[ -e "$T/.zcode/super-board/upgrade.json" ] && fail "a fresh install is not an upgrade"
rm -rf "$T"
T=$(mktemp -d); printf '# AGENTS.md\n- mine\n' > "$T/AGENTS.md"
"$INSTALL" --no-hooks "$T" >/dev/null 2>&1
[ "$(cat "$T/AGENTS.md")" = "$(printf '# AGENTS.md\n- mine')" ] || fail "install must not add a block uninvited"
for s in super-board-skills-ready.py super-board-host.sh super-board-env-check.sh super-board-merge-policy.py super-board-agents-md.py super-board-settings.py super-board-setup.py; do
  [ -x "$T/.zcode/bin/$s" ] || fail "$s was not installed"
done
rm -rf "$T"

# 13 — shared layout: the files live once under .agents/; .zcode/ reaches them through
#      links. zcode is the only host, and no other host folder appears.
resolves() { # <target> — .zcode paths reach the .agents/ copy
  for p in skills/super-board/SKILL.md skills/git-sync/SKILL.md bin/super-board-host.sh; do
    [ "$1/.zcode/$p" -ef "$1/.agents/$p" ] || fail "zcode: $p does not resolve to .agents/$p"
  done
}
T=$(mktemp -d)
OUT=$("$INSTALL" "$T" 2>&1)
[ -d "$T/.agents/skills/super-board" ] && [ ! -L "$T/.agents/skills/super-board" ] || fail "fresh: .agents/skills/super-board should be a real directory"
[ -f "$T/.agents/bin/super-board-host.sh" ] && [ ! -L "$T/.agents/bin/super-board-host.sh" ] || fail "fresh: .agents/bin should hold real files"
[ -x "$T/.agents/bin/super-board-host.sh" ] || fail "fresh: .agents/bin scripts must be executable"
resolves "$T"
[ -L "$T/.zcode/skills/super-board" ] || fail "fresh: .zcode/skills/super-board should be a link"
[ "$(readlink "$T/.zcode/skills/super-board")" = "../../.agents/skills/super-board" ] || fail "fresh: links must be relative, got $(readlink "$T/.zcode/skills/super-board")"
[ "$T/.zcode/hooks/guard-secrets.py" -ef "$T/.agents/hooks/guard-secrets.py" ] || fail "fresh: hooks should resolve to .agents/hooks"
[ ! -e "$T/.codex" ] && [ ! -e "$T/.opencode" ] && [ ! -e "$T/.claude" ] || fail "fresh: a claude/codex/opencode folder appeared"
echo "$OUT" | grep -q "✓ skills and scripts → .agents/ (linked from .zcode)" || fail "fresh: grouped line should name .agents/ and .zcode, got: $OUT"
rm -rf "$T"

# 14 — this pack is zcode-only: --hosts is gone and unknown options are refused.
T=$(mktemp -d)
if OUT=$("$INSTALL" --hosts zcode "$T" 2>&1); then fail "--hosts should be refused (zcode-only)"; fi
echo "$OUT" | grep -q "unknown option: --hosts" || fail "--hosts refusal should be named, got: $OUT"
[ ! -e "$T/.agents" ] || fail "a refused install must install nothing"
rm -rf "$T"

# 14b — install ships the .dwf.ts workflow definitions ZCode loads from
#       .zcode/workflows/, link or copy, content intact.
T=$(mktemp -d)
"$INSTALL" --no-hooks "$T" >/dev/null 2>&1 || fail "install failed"
for f in super-board-wave.dwf.ts ui-refine-loop.dwf.ts; do
  [ -f "$T/.zcode/workflows/$f" ] || fail "zcode host: .zcode/workflows/$f was not shipped"
  cmp -s "../.zcode/workflows/$f" "$T/.zcode/workflows/$f" || fail "zcode host: $f differs from the pack copy"
done
rm -rf "$T"

# 16 — upgrade a real-directory .zcode/ install: every path it had still resolves, super-board's
#      own entries become links, anything that is not super-board's stays exactly as it was.
T=$(mktemp -d)
mkdir -p "$T/.zcode/skills/super-board" "$T/.zcode/skills/super-qa" "$T/.zcode/skills/other-skill" \
         "$T/.zcode/bin" "$T/.zcode/workflows" "$T/.zcode/hooks"
echo "1.8.2" > "$T/.zcode/skills/super-board/VERSION"; echo old > "$T/.zcode/skills/super-board/SKILL.md"
echo old > "$T/.zcode/skills/super-board/stale-file.md"
echo mine > "$T/.zcode/skills/other-skill/SKILL.md"
echo old > "$T/.zcode/bin/super-board-host.sh"; echo mine > "$T/.zcode/bin/mine.sh"
echo mine > "$T/.zcode/hooks/my-hook.py"
echo old > "$T/.zcode/hooks/guard-secrets.py"
"$INSTALL" "$T" >/dev/null 2>&1 || fail "upgrade from a real-directory install failed"
resolves "$T"
for p in skills/super-board skills/super-qa bin/super-board-host.sh hooks/guard-secrets.py; do
  [ -L "$T/.zcode/$p" ] || fail "upgrade: .zcode/$p should now be a link into .agents/"
done
[ ! -e "$T/.agents/skills/super-board/stale-file.md" ] || fail "upgrade: stale files must not carry over"
[ "$(cat "$T/.zcode/skills/other-skill/SKILL.md")" = mine ] && [ ! -L "$T/.zcode/skills/other-skill" ] || fail "upgrade: other-skill was touched"
[ "$(cat "$T/.zcode/bin/mine.sh")" = mine ] && [ "$(cat "$T/.zcode/hooks/my-hook.py")" = mine ] || fail "upgrade: user bin/hooks were touched"
[ ! -e "$T/.agents/skills/other-skill" ] || fail "upgrade: other-skill must not move into .agents/"
jq -e '.from == "1.8.2"' "$T/.zcode/super-board/upgrade.json" >/dev/null || fail "upgrade: upgrade.json not recorded"
rm -rf "$T"

# 17 — a second run changes nothing (tree, link targets, file contents).
snapshot() { python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
for d, dirs, files in sorted(os.walk(root)):
    for n in sorted(dirs + files):
        p = os.path.join(d, n); r = os.path.relpath(p, root)
        if os.path.islink(p): print("L", r, os.readlink(p))
        elif os.path.isfile(p): print("F", r, hashlib.sha256(open(p, "rb").read()).hexdigest())
        else: print("D", r)
PY
}
T=$(mktemp -d)
"$INSTALL" "$T" >/dev/null 2>&1
BEFORE=$(snapshot "$T")
"$INSTALL" "$T" >/dev/null 2>&1
[ "$(snapshot "$T")" = "$BEFORE" ] || fail "a second install changed the tree: $(diff <(echo "$BEFORE") <(snapshot "$T"))"
rm -rf "$T"

# 18 — a host folder whose skills/ (or bin/) is itself a link into .agents/ is already shared:
#      nothing is replaced, nothing loops, the neighbours survive.
T=$(mktemp -d); mkdir -p "$T/.agents/skills" "$T/.agents/bin" "$T/.zcode"
ln -s ../.agents/skills "$T/.zcode/skills"; ln -s ../.agents/bin "$T/.zcode/bin"
plant_decoys "$T"
"$INSTALL" --no-hooks "$T" >/dev/null 2>&1 || fail "whole-folder link layout failed"
[ -d "$T/.agents/skills/super-board" ] && [ ! -L "$T/.agents/skills/super-board" ] || fail "whole-folder link: skill turned into a self-link"
[ -f "$T/.zcode/skills/super-board/SKILL.md" ] && [ -x "$T/.zcode/bin/super-board-host.sh" ] || fail "whole-folder link: files missing"
decoys_intact "$T" || fail "whole-folder link: DECOYS DESTROYED"
rm -rf "$T"

# 19 — no symlinks (Windows without symlink rights): copy instead, so every path still resolves.
T=$(mktemp -d); FAKE=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKE/ln"; chmod +x "$FAKE/ln"
for run in 1 2; do
  OUT=$(PATH="$FAKE:$PATH" "$INSTALL" "$T" 2>&1) || fail "no-symlink install failed: $OUT"
  [ -f "$T/.zcode/skills/super-board/SKILL.md" ] && [ -x "$T/.zcode/bin/super-board-host.sh" ] \
    && [ -f "$T/.zcode/hooks/guard-secrets.py" ] || fail "no-symlink install: .zcode paths missing"
  cmp -s "$T/.zcode/skills/super-board/SKILL.md" "$T/.agents/skills/super-board/SKILL.md" || fail "no-symlink: copy differs"
done
echo "$OUT" | grep -q "copied" || fail "no-symlink install should say it copied, got: $OUT"
rm -rf "$T" "$FAKE"

# 9 — the snippet the installer merges is the one hooks/README.md documents.
python3 - ../hooks/README.md ../hooks/settings-snippet.json <<'PY' || fail "hooks/README.md snippet and hooks/settings-snippet.json differ"
import json, re, sys
doc = re.search(r"```json\n(.*?)```", open(sys.argv[1]).read(), re.S).group(1)
sys.exit(0 if json.loads(doc) == json.load(open(sys.argv[2])) else 1)
PY

echo "PASS: test-install.sh (25 scenarios)"
