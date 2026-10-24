#!/usr/bin/env bash
# super-board-host.sh — which agent host is this shell inside: `claude`, `codex`, `opencode`
# or `zcode`.
#
# WHY. `/super-board run` launched from a Codex CLI session has no Claude Workflow tool, so the
# workflow backend cannot start. The orchestrator checks its own tool list first; this is the
# check a script can make, and the tie-breaker when the tool list is unclear. A shell with no
# known sign gets no answer (exit 65): guessing Claude there starts the wrong backend.
#
# THE SIGNALS.
# - Codex CLI sets CODEX_THREAD_ID (and CODEX_SESSION_ID, the same value) in every shell it
#   runs. Observed 2026-10-04 on codex-cli 0.160.0 with `codex exec -s read-only`:
#   CODEX_THREAD_ID, CODEX_SESSION_ID, CODEX_VERSION, CODEX_SANDBOX=seatbelt, CODEX_CI=1.
#   Not used: CODEX_HOME (people export it in their own profile), CODEX_SANDBOX (absent when
#   the sandbox is off). A Codex lane started from a Claude session also carries CLAUDECODE;
#   the Codex ids still win there, because the innermost host is the one running this shell.
# - OpenCode sets OPENCODE=1 (plus OPENCODE_SESSION_ID, OPENCODE_TERMINAL=1, AGENT=1) in the
#   shells it runs. Observed 2026-10-19 on opencode v2.0.22 (env diff of a `run` shell).
#   Checked before CLAUDECODE, which leaks into OpenCode started from a Claude session.
#   Not used: AGENT=1 (a generic name other tools set too).
# - ZCode sets ZCODE_APP_VERSION in every shell it runs. Observed 2026-10-24 on ZCode 3.16.3
#   (desktop env): ZCODE_APP_VERSION, ZCODE_ENV, ZCODE_BASE_URL, ZCODE_BUILD_COMMIT_ID and
#   no CLAUDECODE. Checked before CLAUDECODE for the same reason as OpenCode: ZCode started
#   from a Claude terminal still inherits CLAUDECODE, and the innermost host wins.
#   Not used: ZCODE_ENV (a shape other tools copy, like NODE_ENV), ZCODE_BASE_URL.
# - Claude Code sets CLAUDECODE=1.
#
# ORDER. SUPER_BOARD_HOST, Codex ids, OPENCODE, ZCODE_APP_VERSION, CLAUDECODE, then the
# config's top-level `host` key (--config <file>), else exit 65. A live env sign beats
# the saved config.
#
# Usage: super-board-host.sh [--config <config.json>]
#        prints `claude`, `codex`, `opencode` or `zcode`, exit 0
#        exit 65   no sign: nothing on stdout, how to choose on stderr
#        exit 64   SUPER_BOARD_HOST or config `host` is not one of the four
# SUPER_BOARD_HOST=claude|codex|opencode|zcode forces the answer (tests, or a host the check
# misreads).
set -euo pipefail

config=
case "${1:-}" in
  --config) config=${2:-} ;;
  '') ;;
  *) echo "usage: super-board-host.sh [--config <config.json>]" >&2; exit 64 ;;
esac

case "${SUPER_BOARD_HOST:-}" in
  claude|codex|opencode|zcode) echo "$SUPER_BOARD_HOST"; exit 0 ;;
  '') ;;
  *) echo "super-board-host.sh: SUPER_BOARD_HOST must be claude, codex, opencode or zcode" >&2; exit 64 ;;
esac

if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SESSION_ID:-}" ]; then
  echo codex
elif [ -n "${OPENCODE:-}" ]; then
  echo opencode
elif [ -n "${ZCODE_APP_VERSION:-}" ]; then
  echo zcode
elif [ -n "${CLAUDECODE:-}" ]; then
  echo claude
elif saved=$( [ -f "$config" ] && jq -r '.host // empty' "$config" 2>/dev/null ) && [ -n "$saved" ]; then
  case "$saved" in
    claude|codex|opencode|zcode) echo "$saved" ;;
    *) echo "super-board-host.sh: config host must be claude, codex, opencode or zcode, got '$saved'" >&2; exit 64 ;;
  esac
else
  echo "super-board-host.sh: unknown agent host. Pick one: SUPER_BOARD_HOST=claude|codex|opencode|zcode, or set \"host\" in the board config" >&2
  exit 65
fi
