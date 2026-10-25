# QA report — issue #1 · v1

- **Worktree:** `.claude/worktrees/issue-1-qa` on `issue-1-test-install-zcode-dwf-shipping` @ `06824ed` (= PR #2 head at QA start)
- **Env:** darwin 25.5.0 arm64, `bash` (macOS system bash)
- **Scope:** the Builder diff — `tests/test-install.sh` scenario 14b (+ scenario-count line 24 → 25). No installer code changed.

## AC verdicts

| AC | Verdict | Evidence |
|---|---|---|
| 1. `test-install.sh` fails when the dwf shipping block is removed, passes with it | ✅ | With block: `bash tests/test-install.sh` → exit 0, `PASS: test-install.sh (25 scenarios)` (`test-install-pass.log`; same command/exit re-verified after restore). Without block: commented out `install.sh:276-287` (the ZCode `.dwf.ts` shipping block), re-ran → exit 1, `FAIL: zcode host: .zcode/workflows/super-board-wave.dwf.ts was not shipped` (`test-install-mutation-fail.log`). Restored with `git checkout -- install.sh` → pass again. |
| 2. Scenario follows existing conventions (numbered comment, `fail()` message) | ✅ | `tests/test-install.sh:348-349` numbered comment `# 14b — …` matching `# 14 —` (:327) / `# 15 —` (:358); `fail()` messages at :351, :353, :354; `mktemp -d` target + `rm -rf "$T"` matches the file's scenario pattern (:35-43). |
| 3. `bash tests/run-safety.sh` stays green | ✅ | Exit 0, `PASS: 62 safety suites`, writing-format 15/15 (`run-safety.log`). |

## Commands run (exact)

```bash
bash tests/test-install.sh                                   # exit 0 — PASS: 25 scenarios
sed -i '' '276,287s/^/#MUT# /' install.sh                    # scratch mutation, never committed
bash tests/test-install.sh                                   # exit 1 — FAIL: …super-board-wave.dwf.ts was not shipped
git checkout -- install.sh && bash tests/test-install.sh     # exit 0 — PASS: 25 scenarios
bash tests/run-safety.sh                                     # exit 0 — PASS: 62 safety suites
```

## Test-gap ledger (scope = the diff)

| AC | unit | component | harness (this repo's only rung) |
|---|---|---|---|
| 1 | n/a: repo test harness is shell suites; no unit/component rung exists | n/a | `tests/test-install.sh:348-356`, mutation-proven red |
| 2 | n/a | n/a | `tests/test-install.sh:348-354` (read) |
| 3 | n/a | n/a | `tests/run-safety.sh` (exit 0) |

Can the new test fail? Yes — demonstrated: removing the guarded block turns it red with its own `fail()` message. Oracle is the pack copy (`cmp` through `../.zcode/workflows/` after the file's own `cd "$(dirname "$0")"` at :19), not a recomputation by the code under test. Both link and copy installs pass `-f` + `cmp`; a broken symlink or drifted content is caught (:353-354).

## Test gaps (not written — non-blocking)

- `install.sh:284` leaves an already-present dest file alone; 14b uses a fresh target so that preserve-branch is unpinned (Medium).
- 14b pins the two shipped names only; a future third `.zcode/workflows/*.dwf.ts` that the block fails to ship would pass unnoticed (Low).

## Screenshots

None captured — no UI AC; this is a shell-installer test. Evidence is the logs above (intentional omission).
