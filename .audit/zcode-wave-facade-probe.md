# ZCode workflow facade probe — super-board wave compatibility

Date: 2026-10-24. Method: `EvalWorkflowSnippet` (ZCode's workflow compiler, synchronous,
nothing executed on diagnostics) run inside a ZCode 3.16.3 session on the three
constructs `workflows/super-board-wave.js` and `workflows/ui-refine-loop.js` depend on.
The full 400-line file was not compiled; a minimal probe isolating its three load-bearing
constructs was, so the diagnostics name the construct and not line noise.

## Probe

```ts
export const meta = { name: 'probe' }
const r = await agent('x', { label: 'x', phase: 'P', schema: { type: 'object' } })
const out = await pipeline([1, 2], async (a) => a, async (prev, b) => prev + b)
return { r, out }
```

## Compiler output (verbatim)

```
L1:C1 `export` is not allowed in a workflow script: the script is compiled inside a function body. Remove `export` — the workflow's output is its final `return` value.
L2:C17 Cannot find name 'agent'.
L3:C19 Cannot find name 'pipeline'.
L3:C43 Parameter 'a' implicitly has an 'any' type.
L3:C59 Parameter 'prev' implicitly has an 'any' type.
L3:C65 Parameter 'b' implicitly has an 'any' type.

NOTE: The snippet was NOT executed — fix the errors above and call the tool again.
```

## Reading

- `export const meta` — illegal. ZCode saved workflows carry metadata in a
  `/* zcode-workflow` block or the SaveWorkflow fields, not an export.
- `agent(prompt, { label, phase, schema, model })` — ZCode's facade is
  `agent(name?, persona?)` returning an `Agent` whose `agent.ask<T>(instructions)`
  carries the prompt; JSON-Schema objects become TypeScript interfaces.
- `pipeline(items, stage1, stage2)` — no such callable. ZCode models stages with
  per-item chaining, `channel`/`future`, and `Promise.all`.
- `log(...)` exists in both facades and is not a blocker.
- ZCode also requires `phase("...")` markers, which neither workflow file has.

Conclusion: both workflow files need a real port (not a rename) before
`/super-board run` can drain a board from ZCode.
