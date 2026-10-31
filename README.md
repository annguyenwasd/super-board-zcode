<div align="center">

<img src="docs/assets/logo.svg" width="88" height="88" alt="super-board kanban logo">

<h1>super-board</h1>

<p><strong>Add tasks, walk away, get merged PRs with proof.</strong></p>

<p>8 skills (5 you type, 3 the board runs) · 9 commands · 6 guard hooks</p>

<p>
<img alt="Version" src="https://img.shields.io/badge/version-3.1.2-1f883d?style=flat-square">
<img alt="Host" src="https://img.shields.io/badge/ZCode-skills-blue?style=flat-square">
<img alt="License" src="https://img.shields.io/badge/license-MIT-0969da?style=flat-square">
</p>

<p><a href="#install">Install</a> · <a href="#quick-start">Quick start</a> · <a href="#how-it-works">How it works</a> · <a href="#skills">Skills</a> · <a href="#commands">Commands</a> · <a href="#guards--hooks">Guards</a></p>

</div>

## Install

This is the ZCode fork of super-board. Run this in your project folder:

```bash
curl -fsSL https://raw.githubusercontent.com/annguyenwasd/super-board-zcode/main/get.sh | bash
```

> [!IMPORTANT]
> There is no ZCode plugin and no `/plugin` command here. This installer works as plain skills: it copies skills and scripts into `.agents/`, links them into `.zcode/`, ships the `.dwf.ts` workflows into `.zcode/workflows/`, and writes the guard hooks into `.zcode/config.json`. Run state stays in `.zcode/super-board/`. Needs ZCode, `gh`, `jq`, bash 3.2+ and Python 3.9+; the installer checks. See [the host doc](docs/hosts.md) for the tested version and gaps.

To install for your user instead of one project, pass `--user`:

```bash
curl -fsSL https://raw.githubusercontent.com/annguyenwasd/super-board-zcode/main/get.sh | bash -s -- --user
```

User scope puts the real files in `~/.agents/{skills,bin,hooks,workflows}`, links them into `~/.zcode/`, and merges the guard hooks into `~/.zcode/cli/config.json`, so the guards run in every project. Nothing lands in any project folder; onboard still runs per project.

Optional post-run learning can delegate an already installed `calibrate` skill after
verified selected work completes. It applies only to explicitly permitted existing
canonical skill files; the package bundles no private skill. See
[post-run calibration](skills/super-board/references/calibration.md).

## Quick start

### 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/EricTechPro/super-board/main/get.sh | bash
```

### 2. Onboard

```
/super-board onboard
```

Checks · GitHub · Board · Branch · AGENTS.md · Policies · Bug sources · Review. <kbd>Enter</kbd> takes the recommended answer.

### 3. Run

```
/super-board run my-app
```

Add cards to `Ready`. The board drains on its own.

On ZCode this runs through the ported saved workflow `super-board-wave`, verified end to end on 2026-10-24: a real card went Ready → Building → QA → Review → Done with its PR merged through the merge gate. Every lane runs on the run's model; there is no tier ladder. Host details: [the host doc](docs/hosts.md).

## How it works

<p align="center"><a href="https://youtu.be/aggJvNZxfKA"><img src="https://i.ytimg.com/vi/aggJvNZxfKA/maxresdefault.jpg" alt="Watch I Built a Self-Improving Software Factory by Eric Tech on YouTube" width="100%"></a></p>
<p align="center"><a href="https://youtu.be/aggJvNZxfKA"><strong>▶ Watch on YouTube: I Built a Self-Improving Software Factory</strong></a></p>

## Skills

**8 skills (5 you type, 3 the board runs).** Uses [Matt Pocock skills](https://github.com/mattpocock/skills), ponytail, impeccable and humanizer.

<!-- skills:start -->
**You type — 5 skills**

| Skill | What it does |
|---|---|
| [`/super-board`](skills/super-board/README.md) | Orchestrator: plans waves, runs Build → QA → Review, merges when green. |
| [`/super-collect`](skills/super-collect/README.md) | Finds problems (Sentry, PostHog, issues, PRs, architecture) and files verified Backlog cards. |
| [`/ui-refine-loop`](skills/ui-refine-loop/README.md) | Critique → refine loop that polishes one page or component. |
| [`/visual`](skills/visual/README.md) | One HTML page: branch recap, plan, or codebase map with diagrams. |
| [`/git-sync`](skills/git-sync/README.md) | Commit per logical change, merge-pull, push without force, report. |

**The board runs — 3 lanes**

| Skill | What it does |
|---|---|
| [`/super-build`](skills/super-build/README.md) | Builder lane: worktree, smallest safe change, tests, draft PR. |
| [`/super-qa`](skills/super-qa/README.md) | Tester lane: evidence, test-gap check, screenshots, or bounce to Build. |
| [`/super-review`](skills/super-review/README.md) | Reviewer lane: own hypotheses, remembers prior findings, merge gate. |
<!-- skills:end -->

Each name links to that skill's README. Adding a skill? Write its `SKILL.md` and `README.md`, add a line to `skills/families.json`, and this table updates itself.

## Commands

```
/super-board onboard          # 8-step setup, resumes
/super-board lint             # vague ACs?
/super-board status           # read-only snapshot
/super-board run <slug>       # drain the board
/super-board stop             # stop workers
/super-collect [source]       # file problems to Backlog
/ui-refine-loop <route>       # polish one page
/visual [recap|plan|path]     # one HTML page
/git-sync                     # commit, pull, push
```

Flags: `super-collect --since 30d`

## Guards & hooks

Run automatically once installed. Python stdlib, JSON in, JSON out.

| | |
| --- | --- |
| [guard-worktree-path](hooks/guard-worktree-path.py) | Blocks `git worktree add` outside `.zcode/worktrees/` |
| [guard-secrets](hooks/guard-secrets.py) | Blocks reading or piping dotenv files, SSH keys and credential files; key names via `super-board-env-check.sh` |
| [guard-key-literals](hooks/guard-key-literals.py) | Blocks a live-looking API key written into a file; flags one already there |
| [guard-delete-outside](hooks/guard-delete-outside.py) | Blocks `rm`, `find -delete` and `git clean` aimed outside the project, `~` or `/` |
| [guard-protected-push](hooks/guard-protected-push.py) | Opt-in (`onboard` asks, or `install.sh --protect-main`): blocks direct and force pushes to main/master/base |
| [README sync](scripts/super-board-readme-sync.py) | Regenerates the skill table; pre-commit and PostToolUse hooks keep it fresh |
| [cleanup-wt](hooks/cleanup-wt.py) | Removes merged worktrees and branches after each merge and at session start, with a recovery file |
| [merge gate](scripts/super-board-merge-gate.sh) | Merges only after the current base plus your non-empty project `verify_commands` pass (missing checks halt setup), pinned to the reviewed commit; applies `merge_policy` and runs allowed DB migrations |

## Models

Every lane agent runs on the session's model — there is no model ladder on ZCode.
Pick the model by starting the ZCode session on it before `/super-board run`.

## Writing standard

Commits, tickets, PR bodies and comments all follow [one writing standard](skills/super-board/references/writing-standard.md), in the pack and in every project it is installed into.

<details>
<summary><strong>Upgrading from 2.x</strong></summary>

1. Re-run the install line.
2. Run `/super-board onboard`; step 1 upgrades for you and keeps a backup.
3. Try `board-migrate --dry-run` on a copy of your board first.

[Full notes](RELEASE-NOTES.md#upgrading-from-2x)

</details>

## Credits

Fork of [EricTechPro/super-board](https://github.com/EricTechPro/super-board) by Eric Tech, ported to ZCode. MIT.

---


### Worker skill availability

Setup and dispatch resolve real, nonempty `SKILL.md` files for the actual
detected host. Missing required skills halt before claims or workers;
lockfiles and arbitrary plugin caches do not count. The shared registry in
`scripts/super-board-skills-ready.py` owns lane dependencies, overrides and the
two declared ponytail fallbacks. Setup's full helper union may be red while a
selected card is runnable. Read-only checks never install; explicit onboard
repair rechecks files after installation.

The CLI accepts `--home <fixture-home>` and `--catalog <active-skills.json>`.
Launchers accept the same inventory through `SUPER_BOARD_SKILLS_HOME` and
`SUPER_BOARD_SKILLS_CATALOG`; neither changes the actual host. Catalog shape:
`{"host":"zcode","skills":[{"name":"vendor:skill","path":"/exact/SKILL.md",
"enabled":true,"scope":"project","project_root":"/exact/project"}]}`.
User entries use `scope:"user"`. Restart explicitly after repairing missing
skills; readiness certifies availability, not their content or external tools.
