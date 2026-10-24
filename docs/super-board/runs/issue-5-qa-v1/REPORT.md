# QA report — issue #5 · v1

- **Worktree:** `.zcode/worktrees/issue-5-qa` on `issue-5-record-the-post-port-live-run` @ `c1ad614` (= PR #6 head at QA start)
- **Env:** darwin 25.5.0 arm64, `bash` (macOS system bash)
- **Scope:** the Builder diff — `docs/hosts.md` +7 (new `## Integration run 2026-10-25 (post-port)` section), `tests/test-hosts-doc.sh` +8 (pins for that section). No product code changed.

## AC verdicts

| AC | Verdict | Evidence |
|---|---|---|
| 1. `## Integration run 2026-10-25 (post-port)` exists in `docs/hosts.md` after the Evidence section, with date, host version string, scope (one card, Ready → Done) and the wave/merge outcome | ✅ | `bash tests/test-hosts-doc.sh` → exit 0, `PASS: test-hosts-doc.sh (4 hosts)` — pins presence + `2026-10-25` + `ZCode 3.16.3` + `Ready → Done` (`tests/test-hosts-doc.sh:26-31`). Position: `## Evidence` at `docs/hosts.md:37`, the new section at `docs/hosts.md:45` — directly after. Scope line: "one card (#5), Ready → Done through the wave lanes build → QA → review". Outcome line: "passed QA and review and squash-merged into `selftest` through the merge gate" (`docs/hosts.md:49-50`; becomes literally true at this PR's own merge, as the Builder's risk block anticipates). |
| 2. Section ≤ 12 lines, follows the existing factual row style | ✅ | Measured 6 lines (header to EOF, conservative count — the section is last, so later additions would only grow it). Style matches the `## Evidence` bullets: dated facts, no adjectives. |
| 3. `bash tests/run-safety.sh` passes in the PR worktree | ✅ | Exit 0, `PASS: 62 safety suites` on `c1ad614`; `test-hosts-doc.sh` green inside the run. |

## Commands run (exact)

```bash
bash tests/test-hosts-doc.sh        # exit 0 — PASS: test-hosts-doc.sh (4 hosts)
bash tests/run-safety.sh            # exit 0 — PASS: 62 safety suites
sed -i '' 's/^## Integration run 2026-10-25 (post-port)$/## Integration run 2026-10-25 MUTATED/' docs/hosts.md
bash tests/test-hosts-doc.sh        # exit 1 — FAIL: integration run 2026-10-25 (post-port) section missing (mutation scratch, never committed)
git checkout -- docs/hosts.md && bash tests/test-hosts-doc.sh   # exit 0 — PASS again; `git status` clean
```

## Test-gap ledger (scope = the diff)

| AC | unit | component | harness (this repo's only rung) |
|---|---|---|---|
| 1 | n/a: docs-only change; repo test harness is shell suites | n/a | `tests/test-hosts-doc.sh:26-31`, mutation-proven red |
| 2 | n/a | n/a | `tests/test-hosts-doc.sh:28` (≤ 12 lines); style verified by read, not mechanizable without a style linter |
| 3 | n/a | n/a | `tests/run-safety.sh` (exit 0) |

Can the new pin fail? Yes — demonstrated: renaming the section header turns it red with its own `FAIL` message; restore turns it green. Facts in the assertions are independent literals, not recomputed from the doc.

## Test gaps (not written — non-blocking)

- The pin does not assert the section sits *after* `## Evidence` — awk matches the header anywhere in the file (Medium). Position verified by inspection this run (`docs/hosts.md:37` → `:45`); one grep line would pin it if the doc grows.
- "Follows the existing factual row style" is verified by review only; no style linter exists (Low).

## Screenshots

None captured — no UI AC; this is a docs-only change with shell-suite evidence (intentional omission).
