# Issue #7 QA — mutation verification of the two port fixes

Branch `issue-7-verify-port-fixes` cut from `origin/main` @ `9f27099`. Both fixes under
test exist only on `main`; config `base_branch: selftest` has neither (drift, see Notes).

## AC1 — pr-body marker splice (fix 9f27099)

Input body-file, wrapped in markers itself:

```
<!-- sb:status -->
merged content
<!-- /sb:status -->
```

Existing PR body holds `sb:status` + `sb:ac` blocks; `gh` stubbed on PATH (REST form),
head pinned `3f9c2a1…`. Command (run from the worktree):

```
scripts/super-board-pr-body.sh --pr 7 --block status --expect-head 3f9c2a1 \
  --body-file wrapped.md --dry-run
```

Counts = `grep -c '^<!-- sb:status -->$'` and `grep -c '^<!-- /sb:status -->$'` over stdout.

| Script under test | exit | openers | closers | verdict |
|---|---|---|---|---|
| fixed (`9f27099`) | 0 | 1 | 1 | exactly one pair; `merged content` survives |
| mutated in place = `9f27099^` | 0 | 2 | 2 | doubled markers — the bug the fix guards |
| fixed restored, diff empty | 0 | 1 | 1 | green again |

## AC2 — install prune (fix 9078ccb)

Scenario per AC: fresh temp TARGET; planted stale `.agents/bin/super-board-removed.sh`
and `.agents/workflows/removed.js`; then `bash install.sh --no-hooks <TARGET>`.

| install.sh under test | planted bin | planted wf | live `super-board-card.sh` | live `super-board-wave.dwf.ts` | exit |
|---|---|---|---|---|---|
| fixed (`9078ccb`) | GONE | GONE | present | present | 0 |
| mutated in place = `9078ccb^` | SURVIVED | SURVIVED | present | present | 0 |
| fixed restored, diff empty | GONE | GONE | present | present | 0 |

## AC3 — suite + this report

- `bash tests/run-safety.sh` in the PR worktree: exit 0, `PASS: 53 safety suites`.
- This report: 55 lines (limit 60).

## Notes

- Non-visual ACs: no screenshots by design; the evidence is the commands and counts above.
- Mutants never reached a commit: each was restored in place and `git diff --stat`
  confirmed empty before the green re-run.
- Config drift for the Reviewer: `selftest.json` `base_branch` is `selftest`, but
  `9f27099` / `9078ccb` live only on `main`. This branch and its PR therefore target
  `main`. Set `base_branch: "main"` or converge the branches before the merge gate.
