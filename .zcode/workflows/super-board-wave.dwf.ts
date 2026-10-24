/* zcode-workflow
description: >
  Drain one super-board wave: pre-flight and classify the Ready cards, then
  run build → qa → review per card (lifecycles per run.md).
whenToUse: >
  Launched by the super-board run-workflow backend with args from
  super-board-wave-plan.sh. Not for direct ad-hoc use.
args:
  configPath:
    type: string
    required: true
    description: board config path, e.g. .zcode/super-board/configs/<slug>.json
  cards:
    type: json
    required: true
    description: output of super-board-wave-plan.sh — [{number,status,title,lane,labels}]
  tier:
    type: string
    description: run model ladder low|medium|high. Accepted for launch parity; on ZCode every lane runs on the run model.
*/

// ZCode port of workflows/super-board-wave.js (same program, ZCode workflow
// dialect). Prompts are verbatim from the source except --host zcode in the
// skills check. Model ladders do not apply: ZCode runs every subagent
// on the run's model, so tier is validated and then unused.
// shortcut: no per-card model tiering, until ZCode gains per-lane model routing.

interface Args {
  configPath: string
  cards: Card[]
  tier?: string
}

interface Card {
  number: number
  status: string
  title: string
  /** planner's lane for a Ready card; 'qa' skips the Builder */
  lane?: 'build' | 'qa' | 'review'
  labels?: string[]
}

interface ClassifyResult {
  kind: 'feature' | 'bug' | 'qa'
  /** low | medium | high, judged by the scope of change required */
  complexity: 'low' | 'medium' | 'high'
  /** 'halted' stops the whole run */
  status?: 'ok' | 'halted'
}

interface PriorFindings {
  /** how round 1 graded the prior Reviewer report: counts per grade */
  fixed: number
  notFixed: number
  noLongerApplies: number
}

interface StageResult {
  /** advanced = moved forward; bounced = moved backward; blocked/human-gate = Block template + Blocked column; halted = stop the run; failed = lifecycle incomplete */
  status: 'advanced' | 'bounced' | 'blocked' | 'human-gate' | 'failed' | 'halted'
  /** the column the card is in on exit */
  column: string
  detail: string
  prUrl?: string
  branch?: string
  /** review lane only, on a re-review */
  priorFindings?: PriorFindings
}

interface PreflightVerdict {
  number: number
  /** proceed | hold | sequence | skipped (pre-flight blind) | halted */
  verdict: 'proceed' | 'hold' | 'sequence' | 'skipped' | 'halted'
  column?: string
  blockedBy?: number[]
  detail: string
}

interface PreflightResult {
  verdicts: PreflightVerdict[]
}

interface HistEntry {
  lane: string
  status: StageResult['status']
  column: string
  detail: string
  prUrl?: string
  branch?: string
  priorFindings?: PriorFindings
}

interface CardOutcome {
  number: number
  history: HistEntry[]
}

// Types are declared and validated in the zcode-workflow block above; the cast
// is the belt for a path-run whose args skipped declaration validation.
const input = args as unknown as Args
if (!input || !Array.isArray(input.cards) || !input.configPath) {
  throw new Error('super-board-wave needs args {configPath, cards:[{number,status,title,lane}]}')
}
// `variant` was removed in v3.0.0; the planner refuses a "qa-only" config, so a
// wave launched with one is a stale caller. Refuse rather than guess.
const variant = (input as unknown as { variant?: string }).variant
if (variant && variant !== 'full') {
  throw new Error(`super-board-wave: variant "${variant}" was removed in v3.0.0 — labels route cards; run /super-board onboard to upgrade`)
}
if (input.tier && !['low', 'medium', 'high'].includes(input.tier)) {
  throw new Error(`super-board-wave: unknown tier "${input.tier}" — use low | medium | high`)
}

// Lane agents may start in any working directory; every relative .zcode/...
// path in the prompts below resolves against the repo that owns the config.
const repoRoot = input.configPath.replace(/\/\.zcode\/super-board\/configs\/[^/]+$/, '')
if (!repoRoot || repoRoot === input.configPath) {
  throw new Error(`super-board-wave: cannot derive the repo root from configPath "${input.configPath}" — pass the installed config path`)
}
const CWD = `Working directory: cd ${repoRoot} before anything; every command and every .zcode/... path below is relative to that directory.`

let halted = false
// Valid form per --kind, from validate() in scripts/super-board-github-read.py (#32).
const READ_SHAPES = [
  `Read shapes (helper: .zcode/bin/super-board-github-read.py --kind <kind> -- <gh args>):`,
  `- issue title+body: --kind issue -- issue view <N> --json number,title,body`,
  `- issue comments: --kind comments -- api repos/{owner}/{repo}/issues/<N>/comments --paginate --slurp (zero comments = [[]])`,
  `- other JSON, incl. maybe-empty lists: --kind json -- <gh args> (no --jq that prints a plain string)`,
  `- PR branch+head: --kind head -- pr view <N> --json headRefName,headRefOid --jq '"\\(.headRefName) \\(.headRefOid)"'`,
  `- PR body+head: --kind body -- pr view <N> --json body,headRefOid`,
  `- PR metadata: --kind metadata -- pr view <N> --json files,labels,body,additions,deletions,changedFiles`,
  `- issue state: --kind state -- issue view <N> --json state --jq .state`,
  `A read whose output misses its shape exits 64 for that call only and prints the valid form: fix the read, do not halt.`,
].join('\n')
const READ_FAILURE = READ_SHAPES + '\n' + `Verification-readiness exit 9 means missing/unusable config.verify_commands: preserve card/worktree/approval/claims, report status=halted (preflight verdict=halted), stop dispatch, repair project configuration before explicit restart; no Build bounce or automatic retries. ` + `Required GitHub reads use .zcode/bin/super-board-github-read.py: three total attempts, exit 79 means run halted. Check --check before any GitHub write, migration, or merge. On exit 79 preserve worktree/card/approval/claims, make no more GitHub calls, and report status=halted (preflight verdict=halted). Never retry a mutation. Config: ${input.configPath}.`

const LANE: Record<'build' | 'qa' | 'review', { skill: string; section: string }> = {
  build: { skill: 'super-build', section: 'Builder' },
  qa: { skill: 'super-qa', section: 'Tester' },
  review: { skill: 'super-review', section: 'Reviewer' },
}

// The merge-race guard that used to wrap the whole Review lane is gone on
// purpose: the mutex lives in super-board-merge-gate.sh (atomic mkdir lock,
// freshness check inside the lock). See run.md → Reviewer lifecycle step 5.

// Review remembers: a card back in Review after a bounce is graded against the
// last Reviewer report first (run.md → Reviewer step 3b). The lookup is one gh
// call by marker, so the lane does it — this script never sees PR comments.
const REVIEW_MEMORY = [
  `Before reviewing, load prior_report: the newest PR comment containing "<!-- super-review:report -->" (run.md → Reviewer step 3b).`,
  `None → first review, behave as usual. Found → round 1 marks each prior finding fixed / not fixed / no longer applies;`,
  `any not fixed → bounce again listing them. Edit that report comment in place (keep R-ids), never post a second one. Report the counts as priorFindings.`,
  // Independent pass (run.md → Reviewer step 3): hypotheses before the builder's account.
  `Read the issue ACs and the diff before the builder's PR summary; form your own hypotheses, then check their claims.`,
  `Class every finding Gap / Bug / Verification miss / Scope drift / Over-engineering, and list what you verified correct.`,
  // Simplest-solution pass (super-review step 3): Should fix at most, never a bounce on its own.
  `Run ponytail:ponytail-review on the merge-base diff (inline ladder if the plugin is absent); Over-engineering never blocks merge alone.`,
  // Truth-check brief is fixed (super-review → Adversarial mode); a hand-written one once made over-building blocking.
  `Truth-check sub-agents get the fixed brief from super-review → "Adversarial mode", verbatim. After collecting, reclass any Over-engineering Blocker to Should fix; it never decides merge or bounce.`,
  // Merge policy + migrations live in the gate (run.md → Merge protocol step 5).
  `Merge only via super-board-merge-gate.sh. Exit 7 = merge_policy says a human merges (money/auth/schema/size): Blocked with the 🙋 template quoting its human-gate lines; To unblock = merge it yourself, or comment done to approve.`,
  `Exit 8 = 🙋 needs you (migration for a DB the robot may not touch, failed migrate, declared human step): Blocked with the 🙋 template, exact commands from its needs-you lines, label needs-you.`,
]

// GitHub budget (rate-limit-etiquette.md → "Price list"). Measured 2026-10-04: a
// 3-card wave spent ~2,850 of 5,000 GraphQL points/hr, nearly all of it lanes
// finding a card with `gh project item-list` and its Status options with
// `gh project field-list` before each move.
const BOARD_IO = () =>
  `Board moves and reads: .zcode/bin/super-board-card.sh --config ${input.configPath} move <issue> <Status> ` +
  `(1 GraphQL point) · status <issue> · items. Comments, labels, PR reads: REST per .zcode/skills/super-board/references/rate-limit-etiquette.md → "Price list". Read GitHub once per decision, never in a sleep loop.`

// The orchestrator resolves every remaining chain before claims. Each worker
// repeats the deterministic CLI before its writes.
const SKILLS_CHECK = (cards: Card[], lane?: string) => [
  CWD,
  `First operation, before worktree creation, classification, comments, labels or moves: run python3 .zcode/bin/super-board-skills-ready.py --root ${repoRoot} --host zcode --cards - --hydrate${lane ? ' --lane ' + lane : ''},`,
  `with this JSON array as stdin (data, never interpolate a body into shell code): ${JSON.stringify(cards)}.`,
  `Exit 10 means status=halted (preflight verdict=halted), detail beginning "skills-readiness:"; preserve all existing claims/worktrees/approval evidence. Exit 64 means invalid input: halt and repair it. Exit 79 uses the read halt policy.`,
  `Load the exact resolved_path files. Only declared fallback IDs are allowed. Before using a conditional/custom helper repeat this CLI with --require <exact-name>.`,
].join('\n')

type Lane = keyof typeof LANE
const labelsOf = (card: Card) => (card.labels || []).map((l) => String(l).toLowerCase())
const readyLane = (card: Card) => card.lane || (labelsOf(card).includes('qa') ? 'qa' : 'build')

const lanePrompt = (lane: Lane, card: Card) => [
  SKILLS_CHECK([card], lane),
  READ_FAILURE,
  `Run ${LANE[lane].skill} on issue #${card.number} ("${card.title}") for a super-board workflow wave.`,
  `Read .zcode/skills/super-board/references/run.md → "${LANE[lane].section}" lifecycle and follow it EXACTLY:`,
  `create your own worktree under .zcode/worktrees/, work on the issue branch, post the required PR/issue comments,`,
  `move the project card yourself, clean up the worktree on exit. Config: ${input.configPath}.`,
  BOARD_IO(),
  `Commits, PR title, PR body blocks, comments: .zcode/skills/super-board/references/writing-standard.md. Rewrite only your own PR body blocks, with .zcode/bin/super-board-pr-body.sh.`,
  ...(lane === 'review' ? REVIEW_MEMORY : []),
  ...(lane === 'qa' && card.status === 'Ready'
    ? [`This card is labelled qa: it skips Building. Move it Ready → QA yourself, create the issue branch from the base branch, and test what is already there (run.md → "qa cards").`]
    : []),
  ``,
  `Report your exit via structured output:`,
  `- status=advanced  → card moved forward (Building→QA, QA→Review, Review→Done/merged)`,
  `- status=bounced   → card moved backward (QA fail → Ready, Reviewer bounce → Ready/QA)`,
  `- status=blocked or human-gate → you wrote the Block template and moved the card to Blocked`,
  `- status=halted    → required service evidence or verification configuration is unavailable; leave card state unchanged and stop the run`,
  `- status=failed    → you could not complete the lifecycle (say why in detail)`,
  `column = the column the card is in when you exit. detail = one line. Include prUrl/branch when they exist.`,
].join('\n')

// shortcut: a rejected ask (schema validation, context overflow) maps to null
// and the lane dies like a dead lane agent; upgrade when
// ZCode grows a typed rejection worth distinguishing. The catch must sit inside
// each Promise.all callback or one rejection kills the whole join.
const runLane = async (lane: Lane, card: Card, history: HistEntry[]): Promise<StageResult> => {
  if (halted) {
    const result: StageResult = { status: 'halted', column: card.status, detail: 'run halted; preserve work and repair the reported readiness or evidence problem' }
    history.push({ lane, ...result })
    return result
  }
  let r: StageResult | null
  try {
    r = await agent(`${lane}:#${card.number}`).ask<StageResult>(lanePrompt(lane, card))
  } catch { r = null }
  const result = r || { status: 'failed' as const, column: 'unknown', detail: `${lane} agent returned no result` }
  if (result.status === 'halted') halted = true
  history.push({ lane, ...result })
  return result
}

// Builder pre-flight (run.md → "Builder pre-flight"). Before ANY Ready card
// reaches runLane('build'), a fresh cheap agent asks: already merged? already
// being built (open PR or another card)? same files as an open PR? unclear?
// One agent per batch of PREFLIGHT_BATCH cards, so the three gh list calls in
// super-board-preflight.sh are paid once per batch, not once per card.
// A card the agent did not answer for is skipped, never built unchecked.
const PREFLIGHT_BATCH = 5
const preflightPrompt = (batch: Card[]) => [
  SKILLS_CHECK(batch),
  READ_FAILURE,
  `Builder pre-flight for issues ${batch.map((c) => `#${c.number} ("${c.title}")`).join(', ')}. Config: ${input.configPath}.`,
  `Read .zcode/skills/super-board/references/run.md → "Builder pre-flight" and follow it EXACTLY. You write no code.`,
  `Other cards in this wave: ${JSON.stringify(input.cards.map(({ number, status, title }) => ({ number, status, title })))}`,
  `Run .zcode/bin/super-board-preflight.sh once for the whole batch, then judge its candidates semantically.`,
  `hold / sequence-behind → post the Block template (block-template.md) and move the card to Blocked yourself.`,
  `Two Ready cards overlapping each other with no open PR: the lower-numbered one proceeds; sequence only the other, blockedBy [the lower]. Never both.`,
  `A sequence with nothing to wait on (empty blockedBy) leaves the card in Ready: return column Ready and it builds.`,
  BOARD_IO(),
  `Return one verdict per issue: proceed | hold | sequence | skipped (pre-flight blind). Never drop a card silently.`,
].join('\n')

// Only cards the Builder will take are pre-flighted; `qa` cards skip Building.
const ready = input.cards.filter((c) => c.status === 'Ready' && readyLane(c) === 'build')
const verdicts = new Map<number, PreflightVerdict>()
const batches: Card[][] = []
for (let i = 0; i < ready.length; i += PREFLIGHT_BATCH) batches.push(ready.slice(i, i + PREFLIGHT_BATCH))

phase('Pre-flight the Ready cards')
await Promise.all(batches.map(async (batch) => {
  let r: PreflightResult | null
  try {
    r = await agent(`preflight:${batch.map((c) => '#' + c.number).join(',')}`).ask<PreflightResult>(preflightPrompt(batch))
  } catch { r = null }
  for (const v of (r && r.verdicts) || []) {
    verdicts.set(v.number, v)
    if (v.verdict === 'halted') halted = true
  }
}))
// sequence with nothing to wait on = proceed with a conflict note (the agent posted it).
// No column and an empty blockedBy is the same case: nothing to wait on never parks a
// card (2026-10-03: #180/#181 each "sequenced" behind the other, neither built).
const preflightGo = (card: Card) => {
  const v = verdicts.get(card.number)
  if (!v) return false
  if (v.verdict === 'proceed') return true
  return v.verdict === 'sequence' && (v.column === 'Ready' ||
    (!v.column && Array.isArray(v.blockedBy) && v.blockedBy.length === 0))
}
const preflightExit = (card: Card): HistEntry => {
  const fallback: PreflightVerdict = { number: card.number, verdict: 'skipped', detail: 'pre-flight returned no verdict — not built unchecked; retried next wave' }
  const v = verdicts.get(card.number) || fallback
  return {
    lane: 'preflight',
    status: v.verdict === 'halted' ? 'halted' : v.verdict === 'skipped' ? 'failed' : 'blocked',
    column: v.column || (['skipped', 'halted'].includes(v.verdict) ? 'Ready' : 'Blocked'),
    detail: `${v.verdict}: ${v.detail}`,
  }
}

// The wave becomes an explicit per-card
// chain inside one fan-out: classify, then the lane chain whose entry point
// depends on the card's column. A non-'advanced' exit ends the chain; the next
// wave re-selects the card from wherever it landed (the board is the loop
// state, not this script).
const classify = async (card: Card): Promise<ClassifyResult | null> => {
  if (halted) return null
  if (card.status !== 'Ready') return null
  const labels = labelsOf(card)
  const typed = ['qa', 'bug', 'feature'].find((l) => labels.includes(l))
  let cls: ClassifyResult | null
  try {
    cls = await agent(`classify:#${card.number}`).ask<ClassifyResult>(
      SKILLS_CHECK([card]) + '\n' + READ_FAILURE + '\n' + `Read GitHub issue #${card.number} ("${card.title}") — body (--kind issue) and all comments (--kind comments) — with the read shapes above. ` +
      `Classify it: kind (feature|bug|qa) and complexity (low|medium|high) judged by the scope of change required. ` +
      (typed
        ? `Its label says "${typed}": return kind "${typed}" — the label routes the card, you never override it.`
        : `It has no type label, so it is built (no label = Building). Return feature or bug — never qa, ` +
          `which only a person sets. Existing docs/ux/tests/refactor/tech-debt rows keep their label chain: classify complexity without adding feature/bug. For a truly untyped card, re-run skills-ready against a copy of this card with the proposed label before any label write, then add that label: gh issue edit ${card.number} --add-label <kind>.`),
    )
  } catch { cls = null }
  if (cls && cls.status === 'halted') halted = true
  return cls
}

const laneChain = async (card: Card): Promise<CardOutcome> => {
  const history: HistEntry[] = []
  const cls = await classify(card)
  if (halted) return { number: card.number, history: [{ lane: 'none', status: 'halted', column: card.status, detail: 'run halted; preserve current work and resume explicitly' }] }
  let at = card.status

  if (at === 'Ready' && readyLane(card) === 'build') {
    if (!preflightGo(card)) {
      history.push(preflightExit(card))
      return { number: card.number, history }
    }
    const b = await runLane('build', card, history)
    if (b.status !== 'advanced') return { number: card.number, history }
    at = 'QA'
  }
  // A `qa`-labelled card skips Building: Ready → QA, Tester first
  // (run.md "Lanes and label routing").
  if (at === 'Ready' && readyLane(card) === 'qa') at = 'QA'
  if (at === 'QA') {
    const q = await runLane('qa', card, history)
    if (q.status !== 'advanced') return { number: card.number, history }
    at = 'Review'
  }
  if (at === 'Review') {
    // No lane-level serialisation: the merge gate holds the mutex for the
    // merge alone (see the note above).
    await runLane('review', card, history)
  }
  return { number: card.number, history }
}

phase('Classify each Ready card, then run its lanes')
const results = await Promise.all(input.cards.map((card) => laneChain(card)))

const summary = results.map((r) => {
  const last = r.history[r.history.length - 1] ||
    { lane: 'none', status: 'failed' as const, column: 'unknown', detail: 'no lane ran' }
  return {
    number: r.number,
    finalStatus: last.status,
    lastLane: last.lane,
    column: last.column,
    detail: last.detail,
    prUrl: last.prUrl || null,
    priorFindings: last.priorFindings || null,
    lanesRun: r.history.map((h) => `${h.lane}:${h.status}`).join(' → ') || 'none',
  }
})
log(`wave complete: ${summary.length} cards — ` +
    summary.map((s) => `#${s.number}=${s.finalStatus}@${s.column}`).join(', '))
return { cards: summary, halted }
