/* zcode-workflow
description: >
  Check → fix loop on one UI target: each round a fresh design reviewer and a
  fresh detector (isolated, as Impeccable requires), a fresh checker that ranks
  typed problems, and a fresh fixer that chains the matching Impeccable
  commands; a fresh finish reviewer grades every fix at the end.
whenToUse: >
  Launched by the standalone /ui-refine-loop skill after it has read the target
  code, run the grill, built the worktree, started the dev server and taken
  round-0 shots. Not for direct ad-hoc use.
args:
  slug:
    type: string
    required: true
    description: board-style slug naming this refine run
  target:
    type: string
    required: true
    description: the UI target the user named
  scope:
    type: json
    required: true
    description: repo-relative paths the fixer may edit
  prompt:
    type: string
    required: true
    description: the user's words verbatim
  rounds:
    type: number
    description: fix rounds; a closing check follows the last (default 5)
    default: 5
  worktree:
    type: string
    required: true
    description: absolute path of the refine worktree
  runDir:
    type: string
    required: true
    description: absolute run dir (shots, auth, logs)
  skillDir:
    type: string
    required: true
    description: absolute path of the ui-refine-loop skill
  critic:
    type: string
    description: impeccable | rubric; rubric is the loud fallback when Impeccable is missing
  impeccable:
    type: json
    description: "{ layout, skillDir, reference, detect, context, version } from refine-setup.sh detect"
  tasteFile:
    type: string
    description: the grill's taste output; defaults to the skill's neutral references/taste.md
  checks:
    type: json
    required: true
    description: commands that must stay green, resolved by refine-setup.sh
  shootCmd:
    type: string
    required: true
    description: screenshot command line the fixer runs for AFTER shots
  baseUrl:
    type: string
    required: true
    description: dev server base URL
  route:
    type: string
    required: true
    description: route of the UI target
  context:
    type: string
    description: one-paragraph design context (code-area notes + Impeccable context)
  beforeShots:
    type: json
    required: true
    description: round-0 full shots and crops, absolute paths
  extraShots:
    type: json
    description: the user's own screenshots
  priorLedger:
    type: json
    description: earlier ledger lines, when resuming
  warnings:
    type: json
    description: detect warnings echoed into the result
  mode:
    type: string
    description: legacy; only "manual" is accepted, anything else is refused
*/

// ZCode port of workflows/ui-refine-loop.js (same program, ZCode workflow dialect).

interface Args {
  slug: string
  target: string
  scope: string[]
  prompt: string
  rounds?: number
  worktree: string
  runDir: string
  skillDir: string
  critic?: 'impeccable' | 'rubric'
  impeccable?: { layout?: string; skillDir: string; reference?: string; detect: string; context?: string; version?: string }
  tasteFile?: string
  checks: string[]
  shootCmd: string
  baseUrl: string
  route: string
  context?: string
  beforeShots: string[]
  extraShots?: string[]
  priorLedger?: string[]
  warnings?: string[]
  mode?: string
}

type Severity = 'P0' | 'P1' | 'P2' | 'P3'
type ProblemType =
  | 'cluttered' | 'bland' | 'too-loud' | 'dull-color' | 'spacing-hierarchy'
  | 'typography' | 'responsive' | 'performance' | 'first-run-empty' | 'confusing-copy'
  | 'edge-cases' | 'accessibility' | 'needs-motion' | 'personality' | 'drift' | 'polish'

interface Problem {
  /** stable key <area>-<problem>, reused across rounds for the same issue */
  id: string
  severity: Severity
  type: ProblemType
  title: string
  /** file:line (repo-relative) */
  location: string
  /** screenshot path + what is visible (theme, viewport, section), or the detector rule */
  evidence: string
  /** what done looks like, inside the existing visual world */
  fix: string
}

interface DesignDims {
  specificity: number
  hierarchy: number
  typography: number
  color: number
  composition: number
}

interface DetectDims {
  accessibility: number
  performance: number
  responsive: number
  theming: number
  integrity: number
}

interface DesignReview {
  dims: DesignDims
  /** sum of dims, out of 20 */
  designTotal: number
  problems: Problem[]
  strengths?: string[]
  openQuestions?: string[]
}

interface DetectReview {
  dims: DetectDims
  /** sum of dims, out of 20 */
  auditTotal: number
  /** verified detector hits (false positives dropped) */
  detectorCount: number
  detectorRan: boolean
  problems: Problem[]
}

interface CheckResult {
  /** merged and ranked, P0 first; at most 8 */
  problems: Problem[]
  /** baseline on the first check */
  vsBefore: 'baseline' | 'better' | 'same' | 'worse'
  /** one line: what changed against round-0, by section */
  vsBeforeNote?: string
  /** two sentences: overall state and the single biggest remaining problem */
  summary: string
  openQuestions?: string[]
}

interface Skipped {
  id: string
  reason: string
}

interface OutOfScope {
  file: string
  why: string
}

interface FixResult {
  status: 'committed' | 'reverted' | 'nothing-to-do'
  /** short sha, or empty */
  commit: string
  /** Impeccable commands run, in order (polish last) */
  commands: string[]
  /** problem ids fixed */
  fixed: string[]
  skipped: Skipped[]
  outOfScope: OutOfScope[]
  /** check command results, one line */
  checks: string
  /** every path the screenshot command printed */
  afterShots: string[]
  openQuestions?: string[]
}

interface Grade {
  id: string
  grade: 'fixed' | 'partial' | 'not-fixed'
  evidence: string
}

interface FinishResult {
  grades: Grade[]
  /** at most 3, introduced by the fixes */
  regressions: string[]
  /** one line: ready for review, or what stays open */
  disposition: string
}

interface Round {
  n: number
  visual: number
  design: number
  audit: number
  detectorCount: number
  detectorRan: boolean
  vsBefore: string
  vsBeforeNote: string
  counts: string
  problems: Problem[]
  summary: string
  fix?: FixResult
}

// Types are declared and validated in the zcode-workflow block above; the cast
// is the belt for a path-run whose args skipped declaration validation.
const input = args as unknown as Args
for (const k of ['slug', 'target', 'scope', 'prompt', 'worktree', 'runDir', 'skillDir', 'checks', 'shootCmd', 'baseUrl', 'route', 'beforeShots'] as const) {
  if (!input || input[k] == null) throw new Error(`ui-refine-loop needs args.${k} — see the header comment`)
}
// Standalone only: the board never runs this. An old `mode` arg other than manual is refused.
if (input.mode != null && input.mode !== 'manual') throw new Error(`ui-refine-loop: mode "${input.mode}" is gone — the loop is standalone (/ui-refine-loop) only`)
const IMP = input.impeccable && typeof input.impeccable === 'object' ? input.impeccable : null
const METHOD = input.critic ?? (IMP ? 'impeccable' : 'rubric')
if (METHOD === 'impeccable' && !(IMP && IMP.detect && IMP.skillDir)) {
  throw new Error('ui-refine-loop: critic "impeccable" needs args.impeccable = { skillDir, detect, … } from refine-setup.sh detect')
}
const ROUNDS = input.rounds ?? 5
const TASTE = input.tasteFile ?? `${input.skillDir}/references/taste.md`
const REF = `${input.skillDir}/references`
const DEGRADED = METHOD === 'rubric' ? 'Impeccable not installed: scored with the built-in rubric, not Impeccable' : null

// Problem type → the Impeccable command that fixes it. The fixer makes the
// final call; this is the default route (references/routing.md).
const ROUTES: Record<ProblemType, string> = {
  cluttered: 'distill',
  bland: 'bolder',
  'too-loud': 'quieter',
  'dull-color': 'colorize',
  'spacing-hierarchy': 'layout',
  typography: 'typeset',
  responsive: 'adapt',
  performance: 'optimize',
  'first-run-empty': 'onboard',
  'confusing-copy': 'clarify',
  'edge-cases': 'harden',
  accessibility: 'harden',
  'needs-motion': 'animate',
  personality: 'delight',
  drift: 'extract',
  polish: 'polish',
}
const SEV: readonly Severity[] = ['P0', 'P1', 'P2', 'P3']
// Distinct routes in severity order, polish always last.
const chainFor = (problems: Problem[]): string[] => {
  const seen: string[] = []
  for (const p of [...problems].sort((a, b) => SEV.indexOf(a.severity) - SEV.indexOf(b.severity))) {
    const c = ROUTES[p.type] ?? 'polish'
    if (c !== 'polish' && !seen.includes(c)) seen.push(c)
  }
  return [...seen, 'polish']
}

// shortcut: a rejected ask (schema validation, context overflow) maps to null
// and the round dies like a dead agent; upgrade when
// ZCode grows a typed rejection worth distinguishing. The catch must sit inside
// each Promise.all callback or one rejection kills the whole join.

const method = METHOD === 'impeccable'
  ? `Method: impeccable v${IMP?.version ?? '?'} (${IMP?.layout} layout). Skill folder: ${IMP?.skillDir}. Playbooks: ${IMP?.reference ?? `${IMP?.skillDir}/reference`}/. Detector: \`${IMP?.detect} <paths>\`.`
  : `Method: rubric. ${DEGRADED}. Use ${REF}/rubric.md in place of Impeccable's playbooks and detector.`

const common = () => [
  `Target: ${input.target} (route ${input.route} at ${input.baseUrl}).`,
  `Scope (repo-relative): ${input.scope.join(', ')}.`,
  `Worktree: ${input.worktree} — run every command there and edit files only under that path. The main checkout is another session's; never touch it.`,
  `Run dir (shots, auth, logs): ${input.runDir}.`,
  method,
  `Taste and direction file (read first; cite its ids): ${TASTE}.`,
  `Design context: ${input.context ?? 'no PRODUCT.md / DESIGN.md; the incumbent implementation is the design authority.'}`,
  `The brief, verbatim: """${input.prompt}"""`,
].join('\n')

const isSheet = (f: string) => /(^|\/)cmp-[^/]*\.png$/.test(f)
const isCrop = (f: string) => /-s\d+\.png$/.test(f)
const shotBlock = (current: string[], n: number | string): string => {
  const before = input.beforeShots
  const lines = [
    `Round-0 (before) shots: ${before.filter((f) => !isCrop(f)).join(', ')}`,
    `Round-0 section crops: ${before.filter(isCrop).join(', ') || '(none)'}`,
  ]
  if (current !== before) {
    lines.push(
      `Current shots (light and dark, desktop 1440 and mobile 390): ${current.filter((f) => !isSheet(f) && !isCrop(f)).join(', ')}`,
      `Current section crops: ${current.filter(isCrop).join(', ') || '(none)'}`,
      `Before | after sheets (read these first): ${current.filter(isSheet).join(', ') || '(none — compare the pairs above)'}`,
    )
  } else {
    lines.push(`Check ${n} is on the untouched surface: current = round-0.`)
  }
  if (input.extraShots && input.extraShots.length) lines.push(`The user's screenshots: ${input.extraShots.join(', ')}`)
  return lines.join('\n')
}
const ledgerText = (ledger: string[]) => (ledger.length ? ledger.join('\n') : '(first check — no ledger yet)')
const counts = (ps: Problem[]) => SEV.map((s) => `${s}×${ps.filter((p) => p.severity === s).length}`).join(' ')

const ledger = [...(input.priorLedger ?? [])]
const rounds: Round[] = []
const claims: (Problem & { round: number })[] = [] // problems a fixer said it fixed, for the finish review
const openQuestions: string[] = []
let shots = input.beforeShots
let finalLabel = 'round-0'
let cleanStreak = 0
let fixFails = 0
let stopReason = `ran all ${ROUNDS} rounds`

// Check n runs on the state left by fix n-1; check ROUNDS+1 is the closing
// check that scores the final state. Fix rounds never exceed ROUNDS.
for (let n = 1; n <= ROUNDS + 1; n++) {
  phase('Check')
  const shotsNow = shotBlock(shots, n)
  // Assessment A and B in isolated contexts, in parallel: neither sees the other.
  const [design, detect] = await Promise.all([
    (async (): Promise<DesignReview | null> => {
      try {
        return await agent(`design reviewer r${n}`).ask<DesignReview>(
          [`You are the check-${n} design reviewer. Read ${REF}/checker-brief.md, section "Design reviewer", and follow it exactly.`, common(), shotsNow, `Extra states only (a dialog open, a tab switched): \`${input.shootCmd} --label review-r${n} --sections none\``].join('\n\n'),
        )
      } catch { return null }
    })(),
    (async (): Promise<DetectReview | null> => {
      try {
        return await agent(`detector r${n}`).ask<DetectReview>(
          [`You are the check-${n} detector. Read ${REF}/checker-brief.md, section "Detector", and follow it exactly.`, common()].join('\n\n'),
        )
      } catch { return null }
    })(),
  ])
  if (!design) { stopReason = `design reviewer r${n} died`; break }
  if (!detect) { stopReason = `detector r${n} died`; break }

  let checker: CheckResult | null
  try {
    checker = await agent(`checker r${n}`).ask<CheckResult>(
      [
        `You are the check-${n} checker. Read ${REF}/checker-brief.md, section "Checker", and follow it exactly.`,
        common(),
        shotsNow,
        `Design review (assessment A):\n${JSON.stringify(design, null, 2)}`,
        `Detector and audit (assessment B):\n${JSON.stringify(detect, null, 2)}`,
        `Ledger of earlier checks:\n${ledgerText(ledger)}`,
      ].join('\n\n'),
    )
  } catch { checker = null }
  if (!checker) { stopReason = `checker r${n} died`; break }
  openQuestions.push(...(design.openQuestions ?? []), ...(checker.openQuestions ?? []))

  const problems = checker.problems.slice(0, 8)
  const visual = Math.round((design.designTotal + detect.auditTotal) * 10) / 10
  const blocking = problems.filter((p) => p.severity === 'P0' || p.severity === 'P1')
  const vsBefore = n === 1 ? 'baseline' : checker.vsBefore
  const round: Round = { n, visual, design: design.designTotal, audit: detect.auditTotal, detectorCount: detect.detectorCount, detectorRan: detect.detectorRan, vsBefore, vsBeforeNote: checker.vsBeforeNote ?? '', counts: counts(problems), problems, summary: checker.summary }
  rounds.push(round)
  const head = `C${n} · visual ${visual}/40 (design ${design.designTotal}/20 · audit ${detect.auditTotal}/20 · detector ${detect.detectorCount}) · ${vsBefore}`

  cleanStreak = blocking.length === 0 ? cleanStreak + 1 : 0
  if (cleanStreak >= 2) {
    ledger.push(`${head} · clean (2nd in a row) · ${round.counts}`)
    stopReason = 'two consecutive checks found no P0/P1'
    break
  }
  if (n === ROUNDS + 1) {
    ledger.push(`${head} · closing check · ${round.counts}`)
    break
  }
  if (problems.length === 0) {
    ledger.push(`${head} · clean, nothing to fix; next check confirms`)
    continue
  }

  phase('Fix')
  const plan = chainFor(problems)
  const routed = problems.map((p) => ({ ...p, route: ROUTES[p.type] ?? 'polish' }))
  // writing-standard.md § 1: `💄 [ui] <scope>: <subject>`; the fixer adds the bullets.
  const commitMsg = `💄 [ui] ${input.slug}: round ${n} — <what changed>`
  let fixer: FixResult | null
  try {
    fixer = await agent(`fixer r${n}`).ask<FixResult>(
      [
        `You are the round-${n} fixer. Read ${REF}/fixer-brief.md and ${REF}/routing.md, and follow them exactly.`,
        common(),
        `Checks that must stay green: ${input.checks.length ? input.checks.join(' && ') : '(none detected — say so in checks)'}.`,
        `Commit message: "${commitMsg}".`,
        `AFTER shots: \`${input.shootCmd} --label round-${n} --compare round-0\` — return every path it prints.`,
        `Suggested chain (routing.md defaults; you choose the final chain, polish always last): ${plan.join(' → ')}`,
        `Problems from check ${n}, ranked, each with its default route (fix P0 → P1 → P2; P3 only in files you already touch):\n${JSON.stringify(routed, null, 2)}`,
      ].join('\n\n'),
    )
  } catch { fixer = null }
  if (!fixer) { stopReason = `fixer r${n} died`; break }
  openQuestions.push(...(fixer.openQuestions ?? []))
  round.fix = fixer

  const oos = fixer.outOfScope.length ? ` · out-of-scope: ${fixer.outOfScope.map((o) => `${o.file} (${o.why})`).join('; ')}` : ''
  ledger.push(
    `${head} · ${round.counts} · ${fixer.status} ${fixer.commit || ''} [${fixer.commands.join(' → ')}]` +
      `\n  fixed: ${fixer.fixed.join(', ') || '—'} · skipped: ${fixer.skipped.map((s) => s.id).join(', ') || '—'}${oos}`,
  )
  log(ledger[ledger.length - 1].split('\n')[0])

  if (fixer.status === 'reverted') {
    fixFails++
    if (fixFails >= 2) { stopReason = 'two fix rounds in a row went red and were reverted'; break }
    continue
  }
  fixFails = 0
  if (fixer.status === 'committed') {
    for (const id of fixer.fixed) {
      const p = problems.find((x) => x.id === id)
      if (p) { const i = claims.findIndex((c) => c.id === id); if (i >= 0) claims.splice(i, 1); claims.push({ ...p, round: n }) }
    }
    if (fixer.afterShots.length) { shots = fixer.afterShots; finalLabel = `round-${n}` }
  }
}

// Finish review: a fresh context grades every claimed fix against the pixels.
let finish: FinishResult | null = null
if (claims.length && finalLabel !== 'round-0') {
  phase('Finish')
  try {
    finish = await agent('finish reviewer').ask<FinishResult>(
      [
        `You are the finish reviewer. Read ${REF}/finish-reviewer-brief.md and follow it exactly.`,
        common(),
        shotBlock(shots, 'final'),
        `Claimed fixes to grade (one grade each):\n${JSON.stringify(claims, null, 2)}`,
      ].join('\n\n'),
    )
  } catch { finish = null }
}

const first = rounds[0]
const last = rounds[rounds.length - 1]
const scoreLine = rounds.map((r) => `C${r.n} ${r.visual}/40${r.n > 1 ? ` (${r.vsBefore})` : ''}`).join(' → ')
return {
  method: METHOD,
  degraded: DEGRADED,
  warnings: input.warnings ?? [],
  stopReason,
  scoreLine,
  before: first ? first.visual : null,
  after: last ? last.visual : null,
  ledger,
  rounds,
  finalLabel,
  finalShots: shots,
  grades: finish ? finish.grades : [],
  regressions: finish ? finish.regressions : [],
  disposition: finish ? finish.disposition : claims.length ? 'finish reviewer died — fixes ungraded' : 'no fixes landed',
  openQuestions,
}
