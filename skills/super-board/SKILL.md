---
name: super-board
description: GitHub-Project-driven autonomous pipeline. Five verbs — onboard, lint, status, run, stop — that take a Project board from empty to drained across Build → QA → Review → Done lanes (labels qa · bug · feature route each card), with graceful shutdown / resume. Use when the user says "super-board", "/super-board", "drain my GitHub project", "set up the autonomous loop", "kick off the headless build/QA pipeline", or "stop super-board".
---

# super-board — autonomous GitHub Project pipeline

## Five verbs

| Verb | Where | What it does |
|---|---|---|
| `super-board onboard` | interactive | one-time setup wizard; writes `.zcode/super-board/configs/<slug>.json` |
| `super-board lint` | interactive | walks active-pipeline issues, flags vague ACs, runs pre-flight readiness |
| `super-board status` | interactive (read-only) | snapshot of active config, column counts, in-flight workers |
| `super-board run` | in-session | the autonomous loop: waves of the `super-board-wave` dynamic workflow (`.zcode/workflows/super-board-wave.dwf.ts`), run from this session via the Workflow tool. Also the resume command — state lives on the board, not in process memory. |
| `super-board stop` | interactive | graceful shutdown: posts "stopped mid-flight" comments on every in-flight issue + PR, releases assignee mutexes, kills workers. Next `super-board run` resumes. |

If invoked with no verb, ask which one.

`install.sh --user` installs the skills, worker helpers and guard hooks user-wide
(`~/.zcode/skills`, `~/.zcode/bin`, user config), so these verbs work in any
project; each project still owns its `.zcode/super-board/` state, worktrees and
GitHub Project — onboard creates those in the project.

## Routing

| If user says | Load |
|---|---|
| `super-board onboard ...` | `references/onboard.md` |
| `super-board lint ...` | `references/lint.md` |
| `super-board status ...` | `references/status.md` |
| `super-board run ...` | `references/run-workflow.md` (lane lifecycles still come from `references/run.md`) |
| `super-board stop ...` / "stop the run" / "pause the loop" / "kill super-board" | `references/stop.md` |
| "resume" / "pick up where I left off" / "restart after stop" | `references/stop.md` (resume = run; no separate verb) |
| Anything about Blocked exits, 🙋 needs you, or dropping a card | `references/block-template.md` |
| Optional learning after a successfully completed run | `references/calibration.md` (external installed skill; bounded receipt; explicit existing-skill edit paths) |
| Config structure questions | `references/config-schema.json` |
| Worker gh-call discipline / rate-limit recovery | `references/rate-limit-etiquette.md` (+ `scripts/super-board-gh-guard.sh`) |

## Orchestrator vs worker — the cardinal rule

super-board is an **autonomous trader**. The interactive ZCode session that invokes any of the five verbs is an **orchestrator**, not a worker. The orchestrator:

- Validates preconditions, then stays in-session and runs the wave loop in `references/run-workflow.md` (launch workflow, reconcile, repeat). The orchestrator never does product work itself.
- Delegates all build / QA / review work to workflow lane agents.
- Must NOT do product work itself, must NOT patch the dispatcher mid-run, must NOT wait for workers, must NOT hold context for multi-card progress.

If anything goes wrong during a run, the orchestrator captures the symptom and reports back — it does not silently expand the task into a fix. See `references/run.md` "Orchestrator delegation contract" for the full rule.
