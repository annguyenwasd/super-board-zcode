# super-board run — workflow backend contract

The ONLY backend: waves of the saved dynamic workflow
`.zcode/workflows/super-board-wave.dwf.ts`, launched in-session with the
Workflow tool (CreateWorkflow, source `saved`, name `super-board-wave`). This
file ONLY covers dispatch. Lane lifecycles, branch/PR model, comment cadence,
Block templates, halt gates, and done conditions are all inherited from `run.md`
unchanged.

**Unknown host halts.** Run `bash .zcode/bin/super-board-host.sh --config <config-path>`
before preconditions. Exit 65 (no host sign) halts before any claim, with one
line: `⛔ unknown host — set SUPER_BOARD_HOST=zcode and re-run`. Never guess.

The wave is launched with args `{ configPath, cards, humanApprovesMerge }` —
`cards` hydrated after the planner: each carries `lane` and `labels`, and a
`qa` card skips the Builder. The wave returns a `{cards, halted}` summary, so
plan, claim, reconcile, manifest, board/comment and throttle steps are
unchanged. Skill checks inside the wave pass `--host zcode` to
super-board-skills-ready.py. Stop with `x` on the run (TaskStop); the rest of
Stop/resume is unchanged. CreateWorkflow typechecks the saved workflow before
anything executes; a diagnostic means nothing ran.

## Required GitHub evidence and a paused run

Required reads use `.zcode/bin/super-board-github-read.py --kind <shape> -- <gh args>`.
Three total attempts means the first attempt plus two retries of that same read;
unrelated successful calls do not reset its failures. Invalid GraphQL queries,
authentication, and permission errors stop immediately. Do not retry mutations.
A payload that misses an agent-facing `--kind` shape (`READ_SHAPES` in
`.zcode/workflows/super-board-wave.dwf.ts`) exits 64 for that call only,
printing the valid form; it never halts the run. Fixed-command scripts set
`SB_GITHUB_READ_STRICT=1`.

Exit **79**, a workflow result with `halted: true`, or a failed `--check` ends this
run. Check the helper's `--check` before claims, board/comment writes, each new
wave, and all migration/merge steps. The marker is shared through the main
checkout's `.zcode/super-board/github-halt.json`, including linked worktrees.
Cancel active workflow agents with TaskStop; do not launch more lanes.
Already-running agents stop at their next checkpoint; this is not an
instantaneous process-wide kill. Preserve worktrees, claims, card statuses, and
approval evidence. Do not move cards to Done/Blocked or release claims using an
unavailable GitHub API. Report the local saved reason and what remains in flight.

After fixing access or the invalid query, explicitly resume with the helper's
`--resume`. It rechecks the failed read before clearing the marker and archives
the original reason. Failed recovery leaves the pause intact. When the caller's
query was corrected or PR metadata changed, supply its current read explicitly:
`--resume --kind <same-shape> [--meta <fresh-meta.json>] -- <corrected gh read args>`.
The replacement must pass the same evidence validator; the broken saved query
is retained in the archived record. This is a read-only recovery check. An uncertain write
has no automatic recovery probe: inspect the remote outcome first, then archive
the halt record explicitly; never rerun a migration/write as a health check. Then follow normal
run preflight/reconcile, inspect preserved worktrees, and start a fresh wave.
Do not schedule automatic retries of the stopped run.

## Orchestrator delegation contract (NON-NEGOTIABLE, adapted)

The interactive session that runs this backend is the orchestrator. It:
- polls the board, claims assignees, launches workflow waves, reconciles
  results, posts notifications, and reports to the user between waves;
- does NOT do product work, patch lane skills mid-run, or hold per-card
  build context. Workflow lane agents do all product work.

## Preconditions (before the first wave)

Run the same preconditions as `run.md` §Preconditions, minus PID checks:
1. Config exists and validates against `config-schema.json`. Run
   `python3 .zcode/bin/super-board-verification-ready.py --config <config>`; exit 9
   stops before dispatch until the owning project's verification commands are configured.
   Preserve work; repair setup and restart explicitly, never bounce to Build.
2. Production-merge guard: refuse `base_branch: main` + `human_approves_merge:
   false` when deploy markers exist (same rule as `run.md`).
3. Worktree check: if legacy `.worktrees/issue-*` exists, halt for inspection/move
   as described in run.md. Scan only board worktrees under `.zcode/worktrees/`;
   when their named branch is gone use `git worktree remove` without force. Preserve
   detached, dirty, locked, unregistered, and unrelated folders.
4. Wave marker FIRST, then the live-run check (lock-before-look closes the
   TOCTOU window where two orchestrators pass each other's checks at once):
   a. Atomically create `.zcode/super-board/inflight/workflow-wave.lock`
      (mkdir -p the directory) containing the config slug and start time:
      `(set -C; printf 'SLUG=%s\nSTARTED=%s\n' <slug> "$(date -u +%FT%TZ)" > <lock>)`.
      Before replacing an existing marker, check `/workflows` for a running
      super-board-wave. Only if no wave is active is the marker stale from a
      crashed run — replace it. Remove the lock when the run ends or stops.
   b. THEN verify no other run is active: `/workflows` shows no running
      super-board-wave for this repo. If another run is detected, remove the
      lock just created and stop — that run won.
5. Crash-recovery sweep: with no wave running, strip `bot_identity` from any
   Review/QA/Ready/Building card that still carries it
   (`gh issue edit <n> --remove-assignee <bot_identity>`). A crashed
   orchestrator releases nothing — leaked assignees make the planner skip
   those cards forever and the board silently stops draining.
6. Database reach: for every env in `migrations.allowed_envs` with a command, run its read-only
   `migrations.checks[env]` (e.g. `supabase migration list --db-url …`). A failure halts the run
   with the check's error — a broken URL caught here costs nothing; caught at merge time it
   strands a wave of reviewed PRs. An env with a command and no check: say so once, then go on.
   The URL resolves from the project's `.env`, never the session (config-schema → `migrations`).

## The wave loop

Repeat until a done condition or halt gate fires:

1. **Rate guard** — `sb_gh_guard_check 200` (super-board-gh-guard.sh; `gh api rate_limit` misreports GraphQL); if GraphQL remaining < 200, wait for
   reset (same thresholds as run.md). A failing `gh` call outranks the reading:
   right after a reset the REST reading has shown 4999 while calls still failed.
   With GraphQL dry, the orchestrator's own writes go over REST, a separate
   quota: `gh api repos/<o>/<r>/issues/<n>/comments -f body=…` for a comment,
   `gh api -X DELETE repos/<o>/<r>/issues/<n>/assignees -f 'assignees[]=<bot>'`
   to release a claim. Board moves have no REST route; they wait for the reset.
2. **Plan the wave** —
   `bash .zcode/bin/super-board-wave-plan.sh --config <config-path>` →
   Exit 9 is a verification-readiness halt: preserve work and claims, repair the
   owning project's `verify_commands`, then restart explicitly. No GitHub recovery probe,
   rebase, Build bounce, or automatic retry.
   **Skill readiness before any wave writes.** Hydrate every selected issue body
   read-only with `.zcode/bin/super-board-github-read.py --kind issue -- issue
   view <N> --json number,title,body`. Keep number, status, labels and literal body
   in a JSON array file. Run `python3 .zcode/bin/super-board-skills-ready.py
   --root <repo-root> --host zcode --cards <cards.json>` before
   sweep/resume/refresh/flag/stranded actions or Claim.
   Exit 10 names missing helpers: halt, preserve all state, repair the exact
   visible skill files and restart explicitly. Exit 64 means invalid input.
   GitHub hydration failure follows the existing exit-79 read policy.
   Empty selection checks no unused helpers. Pass hydrated bodies into the wave.
   Workers recheck their lane before writes and activate conditional helpers
   only after `--require <exact-name>` passes. Untyped Ready cards
   conservatively check bug and feature chains before classification. Existing
   docs/ux/tests/refactor rows keep their chain; check any proposed new label
   chain before writing that label.

   The planner returns `cards`, `sweep`, `resume`, `refreshApproval`, `flag` and `stranded`. **Act on
   `sweep`, `resume`, `refreshApproval`, `flag` and `stranded` BEFORE launching** (run.md → "The wave-start
   sweep"): move every swept card to `Ready` with a comment naming what cleared
   it, move every `resume` card (verified human approval of the current pinned
   request) to `Review`; `needs-you:done` is display-only. Move `refreshApproval`
   cards to `Review` solely to review the changed head and post a fresh human request;
   clear their stale `needs-you:done` display labels. They have no approval to merge.
   Comment on flagged cards asking for their
   `## Blocked by` line to be fixed, and return every stranded Building card to
   `Ready` (below). Swept, resumed, approval-refresh and stranded cards are NOT in this pass's
   `cards`; they join the next wave.

   **Stranded Building cards.** A card in Building with no assignee between
   waves has no live worker — a stopped or crashed wave left it mid-build. For
   each: find its branch (`git ls-remote --heads origin 'issue-<N>-*'`) and any
   leftover `.zcode/worktrees/issue-<N>-build/`. If its HEAD is detached, keep it:
   its commits may have no other ref. Otherwise remove it with `git worktree remove`
   without force. On detached HEAD or removal failure (dirty, locked, or unregistered),
   keep the folder and Building status, report the recovery path, and do not
   redispatch that card until its work is preserved. Otherwise keep the branch and PR,
   move the card to `Ready`, and comment:
   `[orchestrator] [report] ↩️ back to Ready · stranded in Building` / `Did: found no live
   worker` / `✅ Done: card moved to Ready · branch <name> kept` / `Next: builder`
   (writing-standard.md § 4). The next Builder continues on the branch.
   **Builder pre-flight.** No card goes Ready → Building unchecked. The wave's first phase
   (Pre-flight, before the build lanes) runs one cheap sub-agent per
   batch of up to 5 Ready cards: already merged? already in progress (open PR or another card)?
   same files as an open PR? unclear? It runs `super-board-preflight.sh`, posts the Block template
   and moves held/sequenced cards to Blocked itself (run.md → "Builder pre-flight"). The summary
   reports those as `preflight:blocked`; `preflight:failed` means pre-flight was blind and the card
   stays in Ready for the next wave. Sequenced cards carry a `blocked-by:` line, so this same sweep
   frees them when the overlapping PR's issue closes.
   Wave width is every card the dependency graph says is free, in flight
   first (Review → QA → Ready), cut to `max_workers` when it is set (0 or
   absent = no cap). `max_workers` is the GitHub-limit valve: step 5 lowers it
   after a wave that hit the hourly limit. If `cards` is empty and
   Building/QA/Review counts are 0 → done. If empty but cards sit in Blocked
   only → report and stop. This is unfinished work, not a completed-run calibration trigger.
3. **Claim** — for each card, `gh issue edit <n> --add-assignee <bot_identity>`,
   then VERIFY: re-read assignees (`gh issue view <n> --json assignees`) and
   proceed only if the list is exactly `[<bot_identity>]`. Adding an assignee
   does NOT fail when someone else already claimed (issues accept up to 10
   assignees), so the add alone is not a mutex — on any other assignee set,
   remove own assignee and skip the card (race lost). Skipped when
   bot_identity is unset — accepted single-orchestrator risk: without it
   there is no cross-session claim at all, so never run two orchestrators
   (or /loop re-entries) against the same board without bot_identity.
4. **Launch** — CreateWorkflow with source `saved`, name `super-board-wave`,
   `args: { configPath, cards, humanApprovesMerge }`. Runs in the background;
   the orchestrator stays responsive. `humanApprovesMerge` comes from the
   config; when false the workflow serializes Review-lane agents (merge-race
   guard, execution side).
5. **Reconcile** (when the run completes) — read the returned `cards`
   summary. If `halted: true`, any card is `halted`, or the GitHub helper's `--check`
   fails, preserve claims and stop. For verification-readiness (exit 9), repair
   `verify_commands` and restart explicitly; do not invoke GitHub evidence recovery.
   For a GitHub read halt, follow "Required GitHub evidence" above. Otherwise,
   for EVERY card in the wave, release the assignee
   (`gh issue edit <n> --remove-assignee <bot_identity>`, idempotent).
   Append one line per card to the run manifest
   `docs/super-board/runs/<date>-<slug>.md`:
   `| #N | <lanesRun> | <finalStatus> | <column> | <detail> |`.
   Then the GitHub-limit step-down: save the returned `cards` to a temp file and run
   `bash .zcode/bin/super-board-throttle.sh --config <config-path> --results <file>`.
   `hit: true` (GraphQL at 0, or a lane failed on the limit) has already written
   `max_workers` one lower into the config — unlimited → 3 → 2 → 1, floor 1 — so the
   next wave and the next run start narrower. Raising it again is the owner's call.
6. **Report** — one short block to the user per wave, in the session. Outcome
   first, one line per card that needs a human, then what happens next:

   ```
   Wave 3 · 5 cards → 2 merged · 1 bounced · 1 blocked · 1 failed
     🛡 #15 Blocked 🔐 missing STRIPE_TEST_KEY — owner: Eric
     ❌ #18 failed: build lane returned no result — retried next wave
   Next: wave 4 (3 cards)   |   ✅ board drained
   ```
   A throttle hit adds one line: `🐢 GitHub hourly limit hit — max_workers 3 → 2 (config saved)`.
   Merged and bounced cards are counts, not lines — they need nobody. Every
   `human-gate`/`blocked` card gets its line and its owner: that is the
   human's queue. Never report a card as done that is not on the base branch.
7. **Halt gates** — stop with a report if: 3 consecutive waves made zero
   progress (every card bounced/failed); block-rate exceeds
   `block_rate_alert_pct` of initial Ready; or the user says stop. The halt
   note is four lines: `🛑 halted — <gate>` · the evidence (counts, the cards
   that kept bouncing) · what is left in flight or claimed · `Resume:
   /super-board run <slug>` and who must act first.
8. Loop to 1. For unattended cadence, the user may wrap this loop in /loop;
   the orchestrator must still stop at halt gates.

After normal completion, confirm all selected waves and lane tasks have ended,
finish final reconciliation, and release only the `workflow-wave.lock` created
by this host for this run (match its saved slug/start identity). Never remove
a marker owned by another or uncertain run; preserve it and skip calibration.
The read-only adapter never removes markers. Then run the optional adapter in [`calibration.md`](calibration.md).
This is a separate post-run task, after all lane workers and pending selected work
are accounted for. Do not calibrate per wave, on a halt/partial delivery, or from
Done counts or process exit alone. When enabled and eligible, delegate the installed
skill automatically using the helper's scoped brief; check its actual diff before
accepting automatic edits. An unavailable skill/host or an ineligible receipt is
reported as skipped and does not change the completed product work.

## Stop / resume

- Stop: `x` on the run in `/workflows` (or TaskStop), then release assignees
  for in-flight cards and post "stopped mid-flight" comments (same protocol
  as `references/stop.md`). Remove `.zcode/super-board/inflight/workflow-wave.lock`.
- With GitHub available, `bash .zcode/bin/super-board-stop.sh <slug>` wraps the
  same claim/comment/lock protocol for ALL selected claimed cards, including
  queued cards. During a GitHub halt, preserve claims without GitHub writes.
- Resume: just run again — board state is the only state. A workflow stopped
  mid-wave can also be resumed in-session via `resumeFromRunId` (completed
  lane agents return cached results).
- Cards stranded in `Building` (wave stopped after the Builder moved
  Ready → Building) come back by themselves: the next run's crash-recovery
  sweep releases their claim and the planner reports them in `stranded`
  (wave loop step 2). No manual drag.

## Mid-run permission prompts

Lane agents inherit the session's permission mode. ZCode has no project
allowlist file, so whether waves stall on prompts is decided by the mode the
user runs the session in: an attended mode pauses on first-time commands (gh,
git push, the `.zcode/bin` helpers), a hands-off mode does not. Say once, at
run start, which mode the session is in and what it means for overnight runs.
Merging is never silent: the merge gate enforces `merge_policy` (money / auth /
destructive schema / over `auto_max_lines` → human, exit 7) and `migrations`
(live DB → 🙋 needs you, exit 8) regardless of the session mode.

> **Read this before starting an overnight wave (issue #9).** The settings
> interact, and the failure is silent. A board configured
> `"human_approves_merge": false` and `merge_policy.default: "auto"`, run in a
> permission mode that pauses on `gh pr merge`, will build,
> test and review cards all night and land **nothing** —
> each Reviewer stalls on an approval prompt nobody is there to click, and the
> card returns to Review to be re-reviewed on the next wave.
>
> Pick one deliberately:
>
> | Intent | Configuration | Session pauses on `gh pr merge` | Reviewer's terminal state |
> | --- | --- | --- | --- |
> | Attended — approve each merge command | `human_approves_merge: false`, `merge_policy.default: "auto"` | yes | pauses on a tool permission prompt |
> | Unattended auto-merge | `human_approves_merge: false`, `merge_policy.default: "auto"` | no | card → Done after confirmed merge; configured human gates → 🙋 Blocked |
> | Every PR requires human approval through the gate | `human_approves_merge: false`, `merge_policy.default: "human"` | only if the agent merges after approval | gate exits 7 → 🙋 Blocked until a human merges or approves the pinned request |
> | Legacy human-only switch | `human_approves_merge: true` | — | Reviewer stops before the gate; card stays in Review |
>
> Row 2 is the only combination that lands code with nobody watching, and it
> requires a non-production `base_branch` — the production-merge guard refuses
> to start otherwise. A tool permission prompt is separate from the gate's
> human-approval request; a permissive session mode does not bypass
> `merge_policy`. Whichever row you pick, the Reviewer still owes the full
> merge protocol in `run.md` → "Merge protocol": mark the draft PR ready,
> merge, **verify the merge commit is an ancestor of the base branch**, and
> only then move the card to Done. A merge-blocked PR goes to Blocked, not
> back to Review.

### Skill-readiness reconciliation

Exit 10 from a skill check or lane result with detail `skills-readiness:` is a
readiness halt. Stop new dispatch, stop only this runner's active workers,
and preserve claims, inflight records, worktrees, card state and approval
evidence. Repair the exact host-visible skills and restart explicitly. Do not
release claims, bounce a card or enter a retry loop on this halt. Existing
preselection crash recovery remains the discovery step; once missing skills
are known, recovery and wave writes stop.
