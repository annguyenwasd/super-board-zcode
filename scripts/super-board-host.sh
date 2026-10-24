#!/usr/bin/env bash
# super-board-host.sh — which agent host is this shell inside. This pack is
# ZCode-only, so the only valid answer is `zcode`.
#
# WHY. Scripts and docs need to know the worker host exists and can run the
# wave workflow. ZCode is the only host this pack supports, so anything else is
# a misconfiguration, not a different mode to support.
#
# THE SIGNAL. ZCode sets ZCODE_APP_VERSION in every shell it runs. Observed
# 2026-10-24 on ZCode 3.16.3 (desktop env): ZCODE_APP_VERSION, ZCODE_ENV,
# ZCODE_BASE_URL, ZCODE_BUILD_COMMIT_ID. Not used: ZCODE_ENV (a shape other
# tools copy, like NODE_ENV), ZCODE_BASE_URL.
#
# ORDER. SUPER_BOARD_HOST, then ZCODE_APP_VERSION, then the config's top-level
# `host` key (--config <file>), else exit 65. A live env sign beats the saved
# config.
#
# Usage: super-board-host.sh [--config <config.json>]
#        prints `zcode`, exit 0
#        exit 65   no sign: nothing on stdout, how to choose on stderr
#        exit 64   SUPER_BOARD_HOST or config `host` is not zcode
# SUPER_BOARD_HOST=zcode forces the answer (tests, or a shell the check misreads).
set -euo pipefail

config=
case "${1:-}" in
  --config) config=${2:-} ;;
  '') ;;
  *) echo "usage: super-board-host.sh [--config <config.json>]" >&2; exit 64 ;;
esac

case "${SUPER_BOARD_HOST:-}" in
  zcode) echo zcode; exit 0 ;;
  '') ;;
  *) echo "super-board-host.sh: SUPER_BOARD_HOST must be zcode (this pack is ZCode-only)" >&2; exit 64 ;;
esac

if [ -n "${ZCODE_APP_VERSION:-}" ]; then
  echo zcode
elif saved=$( [ -f "$config" ] && jq -r '.host // empty' "$config" 2>/dev/null ) && [ -n "$saved" ]; then
  case "$saved" in
    zcode) echo zcode ;;
    *) echo "super-board-host.sh: config host must be zcode, got '$saved'" >&2; exit 64 ;;
  esac
else
  echo "super-board-host.sh: unknown agent host. This pack is ZCode-only: run it from a ZCode session, set SUPER_BOARD_HOST=zcode, or set \"host\": \"zcode\" in the board config" >&2
  exit 65
fi
