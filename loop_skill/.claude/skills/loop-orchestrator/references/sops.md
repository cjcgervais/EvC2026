# SOPs — Standard Operating Procedures for the Loop

These are **mandatory**. Each is traceable to a source in `RESEARCH.md`. The
orchestrator must follow all of them; profiles may tighten them but never relax
SOP-1, SOP-2, SOP-3, or SOP-7.

## SOP-1 — Define "done" before you start
Write **measurable, checkable** success criteria into the loop-state file before
iteration 1. "Make it better" is not a criterion; "frame time < 16 ms on the test
place" or "all 12 acceptance tests pass" is. If the user hasn't given checkable
criteria, ask. *(Source: Building Effective Agents — clear evaluation criteria.)*

## SOP-2 — Set a budget before you start
No budget → no loop. Record at minimum `max_iterations` and a
`no_improvement_streak` threshold; add a cost/wallclock ceiling for unattended
runs. Scale the budget to task complexity (trivial fix ≈ 1–3 iterations; broad
improvement ≈ 5–10; research sweep ≈ more, with fan-out). Where available, bind
the budget to **native controls** rather than relying on self-restraint:
`maxTurns` / `maxBudgetUsd` on the run and per-worker `maxTurns`/`effort` on
`AgentDefinition`. *(Source: Multi-Agent Research System — scale effort to
complexity; Agent SDK — explicit stopping conditions / budget controls.)*

## SOP-3 — Verify against external ground truth every iteration
Acceptance is decided by an **external signal**, never by the model asserting it's
done. The profile names the ground-truth command/check. Escalate cheapest-first:
1. **Rules-based** — build, type-check, lint, unit/acceptance tests, schema/geometry checks.
2. **Visual** — render/screenshot diff (CAD render, game screenshot, plot).
3. **LLM-as-judge** — a rubric scored by a *separate* agent (highest cost; last resort).
*(Source: Building Agents with the Claude Agent SDK — three verification mechanisms;
"the best feedback is clearly defined rules + explaining which failed and why.")*

**Make the gate non-bypassable when it matters.** For unattended or high-stakes
loops, enforce verify with a **hook**, not just an instruction: a `Stop`/
`SubagentStop` hook that returns `{"decision":"block"}` until the verify command
exits 0, or a `PostToolBatch` hook (exit code 2) as a per-iteration checkpoint.
The harness enforces hooks, so the loop cannot rationalize past them.

## SOP-4 — One meaningful change per iteration
Change one thing, then verify, so the metric move is attributable. Batching
changes hides which one helped or broke things. Exception: independent changes
may be fanned out to parallel subagents and verified separately.

## SOP-5 — Checkpoint before risk; roll back on regression
Before a risky change, record a checkpoint (commit, file copy, or saved artifact
+ the metric). If an iteration regresses the metric below a prior checkpoint, or
the same error appears twice, **roll back** and change strategy — do not pile
fixes on a broken state. *(Source: LangGraph checkpoints; Long-Running Agents.)*

## SOP-6 — Reflect on failure (Reflexion)
When an iteration fails to meet criteria, append 1–3 lines to the state file:
*what* failed, the likely *cause*, and the *next thing to try*. Feed that
reflection into the next iteration's plan. Profiles may set the reflection mode
(`none | last_attempt | reflexion | both`). *(Source: arXiv:2303.11366;
noahshinn/reflexion strategy enum.)*

## SOP-7 — Independence & anti-reward-hacking
The verifier must be **independent of the optimizer**. The loop may **never**:
- weaken, delete, or skip success criteria or tests to make them pass;
- mark itself "done" without the ground-truth check passing;
- hard-code outputs to satisfy a check rather than solve the task.
If the only way to pass is to change the test, **stop and surface it to the user**.
*(Note: no primary source directly covers anti-reward-hacking — see `RESEARCH.md`
Open Questions. This SOP is reasoned best-practice from the evaluator-optimizer
separation, and is best **enforced with a hook**, not left to the optimizer's
discretion.)*

## SOP-8 — Context hygiene
Keep the orchestrator's context lean so judgment stays sharp over a long run:
- Persist state to disk (`references/state-and-memory.md`); don't keep everything in context.
- Summarize completed iterations to a line or two in the state file.
- Delegate heavy reading/building/searching to **subagents with isolated context**;
  bring back only the conclusion. *(Source: Multi-Agent Research System; Agent SDK.)*

## SOP-9 — Resumability & auditability
The on-disk loop-state file is the **single source of truth**. Write it every
iteration so any run can be stopped and resumed, and so a human can audit what
happened and why it stopped. *(Source: Agent SDK resumable sessions.)*

## SOP-10 — Decide explicitly, every iteration
End each iteration with one of `CONTINUE | CONVERGED | DIMINISHING | BUDGET |
STUCK` and record it. Never drift into an unbounded loop by forgetting to decide.
*(Source: Building Effective Agents — explicit stop conditions; Multi-Agent —
adaptive termination.)*

---

### Pre-flight checklist (gate before iteration 1)
- [ ] Success criteria are written and **checkable**.
- [ ] Budget (`max_iterations`, `no_improvement_streak`, optional cost/time) is set.
- [ ] Ground-truth verification command is named and runnable.
- [ ] Architecture chosen and justified.
- [ ] Loop-state file created from the template.
- [ ] User confirmed the frame (if criteria/budget were ambiguous).
