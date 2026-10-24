# Release notes — super-board-zcode

This is the ZCode-only fork of super-board. History older than the fork lives in
the [original pack](https://github.com/EricTechPro/super-board); these notes
cover the fork from its first ZCode-only release on.

## 3.1.2 — the ZCode-only port

- ZCode is the only host. Setup (get.sh / install.sh / super-board-setup.py)
  writes only `.zcode/` and the shared `.agents/` tree; every other agent host
  is refused (`super-board-host.sh` exits 64).
- The wave engine is the saved dynamic workflow
  `.zcode/workflows/super-board-wave.dwf.ts` (plus `ui-refine-loop.dwf.ts`),
  launched in-session with the Workflow tool. The legacy headless dispatcher,
  the headless cross-host lanes and the old `.js` workflows are gone.
- Guard hooks wire into `.zcode/config.json` (`hooks.events`, `enabled: true`)
  with `${ZCODE_PROJECT_DIR}` in commands.
- Host-specific extras that do not exist on ZCode are removed: the plan-usage
  guard, model tiers/ladders, and the extra instruction-file merge step.
- Full-card cycle verified end to end on ZCode 3.16.3 (2026-10-24, see
  `docs/hosts.md`): Ready → Building → QA → Review → Done with the merge gate.

## Upgrading from 2.x

An older install (a different `skills/super-board/VERSION`, or none) is
upgraded in place:

1. Run `./install.sh <project>` (or get.sh). Everything lands under
   `.agents/` linked into `.zcode/`; an upgrade record is written to
   `.zcode/super-board/upgrade.json`.
2. Run `/super-board onboard`. Its 🔍 Checks step finishes the upgrade with no
   question: migrates configs to the v3 keys, removes the old skill folders
   (super-refine, cleanup-wt, arch-loop), and migrates the GitHub board
   (columns, labels, Skipped → Done) with a full recovery record saved first.
3. Keep the board idle during the board migration; re-run the same command
   from the same project root to resume an interrupted one.

State the original pack kept in its own host folder is not carried over: copy
any config you still need into `.zcode/super-board/configs/` and re-run
onboard.
