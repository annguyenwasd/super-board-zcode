# Agent hosts

super-board runs inside an agent host: the CLI whose session types `/super-board run`.
`scripts/super-board-host.sh` (installed as `.claude/bin/super-board-host.sh`) names it.

| Host value | Tested version | Start a run | Sign-in | Gaps |
|---|---|---|---|---|
| `claude` | Claude Code 2.1.302 | `/super-board run` (Workflow backend) | `claude` then `/login`; `gh auth login` | None. The reference host. |
| `codex` | codex-cli 0.160.0 | `/super-board run` inside Codex runs as `--codex`; from Claude, `/super-board run --codex` | `codex login`; `gh auth login` | No Workflow tool, so every lane is headless `codex exec`. Review runs only with explicit `--codex` (a host-switched plain `run` counts). No Claude usage guard. |
| `opencode` | OpenCode v2.0.22 | Not supported yet: the run halts with a host-selection request | `opencode auth login`; `gh auth login` | No OpenCode lane backend yet. `permission.external_directory: deny` is not enforced in v2.0.22 (`patch` still writes outside the repo), so OpenCode runs stay attended-only once a backend lands. |
| `zcode` | ZCode 3.16.3 | `/super-board run` (workflow backend via the saved ZCode workflow `super-board-wave`) | sign in to ZCode's provider; `gh auth login` | Both workflows are ported to ZCode's facade and shipped by install.sh into `.zcode/workflows/`: `super-board-wave.dwf.ts` compiled and returned the empty-wave contract shape on 2026-10-24 (a full-card board run is not yet observed), and `ui-refine-loop.dwf.ts` ran a real 1-round loop (see `.audit/zcode-host.tsv`). Model ladders are flat on ZCode: every lane runs on the run's model, because Claude's haiku/sonnet/opus tiering is host-specific pricing. Guard hooks land in `.zcode/config.json` in ZCode's `hooks.events` shape with `enabled: true` (ZCode injects `${CLAUDE_PROJECT_DIR}` into hook commands, per its docs; a live hook fire in ZCode is not yet observed). |

Every host also needs `gh`, `jq`, bash 3.2+ and Python 3.9+.

## How the host is picked

`super-board-host.sh [--config <config.json>]` prints one value. First match wins:

1. `SUPER_BOARD_HOST=claude|codex|opencode|zcode`, the manual override. Any other value exits 64.
2. `CODEX_THREAD_ID` or `CODEX_SESSION_ID` → `codex`.
3. `OPENCODE=1` → `opencode`. Checked before `CLAUDECODE`, which leaks into an OpenCode
   session started from Claude Code. `AGENT=1` is ignored: other tools set it too.
4. `ZCODE_APP_VERSION` → `zcode`. Checked before `CLAUDECODE` for the same reason: a ZCode
   session started from a Claude terminal inherits `CLAUDECODE`. `ZCODE_ENV` and
   `ZCODE_BASE_URL` are ignored (shapes other tools copy).
5. `CLAUDECODE` → `claude`.
6. The board config's top-level `host` key, when `--config` is given.
7. Nothing matched: empty stdout, a hint on stderr, exit 65. The run halts and asks for a
   host. It never guesses Claude.

A live env sign beats the saved config, so a Codex lane started from a Claude-configured
board still answers `codex`.

Onboard always writes `host` into `.claude/super-board/configs/<slug>.json`.
`super-board-setup.py fix` adds a missing one from `--host`; `check` flags any other value.

## Evidence

- Codex: env of `codex exec -s read-only`, 2026-10-04 (recorded in the script header).
- OpenCode: env diff of an `opencode run` shell, 2026-10-19: `OPENCODE=1`,
  `OPENCODE_SESSION_ID`, `OPENCODE_TERMINAL=1`, `AGENT=1`.
- ZCode: env of a ZCode 3.16.3 desktop shell, 2026-10-24: `ZCODE_APP_VERSION`,
  `ZCODE_ENV`, `ZCODE_BASE_URL`, `ZCODE_BUILD_COMMIT_ID`, and no `CLAUDECODE`.

## Integration run 2026-10-25 (post-port)

- Date: 2026-10-25 (Asia/Ho_Chi_Minh), the first board run after `dad6f40` made the pack ZCode-only.
- Host: ZCode 3.16.3 (`ZCODE_APP_VERSION=3.16.3`), workflow backend, board `super-board self-test` (#2), base `selftest`.
- Scope: one card (#5), Ready → Done through the wave lanes build → QA → review.
- Outcome: this card's PR passed QA and review and squash-merged into `selftest` through the merge gate; no other cards were in the run.
