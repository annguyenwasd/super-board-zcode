# Agent host

super-board runs inside ZCode: the host whose session types `/super-board run`.
This pack is ZCode-only; `scripts/super-board-host.sh` (installed as
`.zcode/bin/super-board-host.sh`) names the host and refuses everything else.

| Host value | Tested version | Start a run | Sign-in | Gaps |
|---|---|---|---|---|
| `zcode` | ZCode 3.16.3 | `/super-board run` (workflow backend via the saved ZCode workflow `super-board-wave`) | sign in to ZCode's provider; `gh auth login` | Both workflows are ported to ZCode's facade and shipped by install.sh into `.zcode/workflows/`. Full-card cycle verified on 2026-10-24 (see `.audit/zcode-host.tsv`): card #1 went Ready → Building → QA → Review → Blocked (gate env-leak bug, filed and fixed as #3) → Review → Done with PR #2 squash-merged through the merge gate; 4 waves, ~15M tokens total. The run also surfaced and fixed two real pack bugs (merge-gate env leak into verify_commands; reply-less comment replies-read halting the run). Model ladders are flat on ZCode: every lane runs on the run's model. Guard hooks land in `.zcode/config.json` in ZCode's `hooks.events` shape with `enabled: true`. |

The host also needs `gh`, `jq`, bash 3.2+ and Python 3.9+.

## How the host is picked

`super-board-host.sh [--config <config.json>]` prints one value. First match wins:

1. `SUPER_BOARD_HOST=zcode`, the manual override. Any other value exits 64.
2. `ZCODE_APP_VERSION` → `zcode`. `ZCODE_ENV` and `ZCODE_BASE_URL` are ignored
   (shapes other tools copy).
3. The board config's top-level `host` key, when `--config` is given.
4. Nothing matched: empty stdout, a hint on stderr, exit 65. The run halts and
   asks for a host. It never guesses.

A live env sign beats the saved config.

Onboard always writes `host: "zcode"` into `.zcode/super-board/configs/<slug>.json`.
`super-board-setup.py fix` adds a missing one from `--host`; `check` flags any
other value.

## Evidence

- ZCode: env of a ZCode 3.16.3 desktop shell, 2026-10-24: `ZCODE_APP_VERSION`,
  `ZCODE_ENV`, `ZCODE_BASE_URL`, `ZCODE_BUILD_COMMIT_ID`.
