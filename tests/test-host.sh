#!/usr/bin/env bash
# Tests super-board-host.sh — zcode is the only host; no sign means exit 65 so the run
# asks for a host instead of guessing.
set -euo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
S="$KIT/scripts/super-board-host.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
# A clean env, so the test answers the same inside ZCode or CI.
host() { env -i PATH="$PATH" "$@" bash "$S"; }

[ "$(host SUPER_BOARD_HOST=zcode)" = zcode ] || fail 'override forces zcode'
rc=0; host SUPER_BOARD_HOST=claude >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "claude override must exit 64 (zcode-only pack), got $rc"
rc=0; host SUPER_BOARD_HOST=codex >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "codex override must exit 64 (zcode-only pack), got $rc"

# No sign and no override: empty stdout, a hint on stderr, exit 65 — never a guess.
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
nohost() {
  local rc=0 out
  out=$(host "$@" 2>"$ERR") || rc=$?
  [ "$rc" = 65 ] || fail "'$*' should exit 65, got $rc"
  [ -z "$out" ] || fail "'$*' should print nothing to stdout, got '$out'"
  grep -q SUPER_BOARD_HOST "$ERR" || fail "'$*' should explain SUPER_BOARD_HOST on stderr"
}
nohost
nohost CLAUDECODE=1                                # a leaked Claude sign is not this pack's host
nohost CODEX_THREAD_ID=01a1                        # a leaked Codex sign is not this pack's host
nohost OPENCODE=1
nohost CODEX_HOME=/x CODEX_SANDBOX=seatbelt        # not host signs
nohost ZCODE_APP_VERSION=                          # empty value is not a sign
nohost ZCODE_ENV=production ZCODE_BASE_URL=https://zcode.z.ai  # zcode signs we do not use

# ZCode 3.16.3 exports ZCODE_APP_VERSION. The override still wins over it.
[ "$(host ZCODE_APP_VERSION=3.16.3)" = zcode ] || fail 'ZCODE_APP_VERSION means zcode'
[ "$(host ZCODE_APP_VERSION=3.16.3 CLAUDECODE=1)" = zcode ] || fail 'ZCode under a Claude parent is zcode'
[ "$(host SUPER_BOARD_HOST=zcode ZCODE_APP_VERSION=3.16.3)" = zcode ] || fail 'override beats the ZCode sign'

# Config `host` (top-level key): used only when no override and no env sign is present.
T=$(mktemp -d); trap 'rm -f "$ERR"; rm -rf "$T"' EXIT
printf '{"host":"zcode"}' > "$T/zcode.json"
printf '{"worker_backend":"workflow"}' > "$T/none.json"
printf '{"host":"claude"}' > "$T/bad.json"
cfg() { local f=$1; shift; env -i PATH="$PATH" "$@" bash "$S" --config "$f"; }
[ "$(cfg "$T/zcode.json")" = zcode ] || fail 'config host zcode prints zcode'
[ "$(cfg "$T/zcode.json" ZCODE_APP_VERSION=3.16.3)" = zcode ] || fail 'an env sign matches config host zcode'
[ "$(cfg "$T/zcode.json" SUPER_BOARD_HOST=zcode)" = zcode ] || fail 'override beats config host'
for f in none missing; do
  rc=0; out=$(cfg "$T/$f.json" 2>/dev/null) || rc=$?
  [ "$rc" = 65 ] && [ -z "$out" ] || fail "config $f without host should exit 65, got $rc '$out'"
done
rc=0; cfg "$T/bad.json" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "a non-zcode config host exits 64, got $rc"
echo "PASS: super-board-host"
