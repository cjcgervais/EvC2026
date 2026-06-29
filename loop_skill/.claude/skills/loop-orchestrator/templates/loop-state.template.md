# Loop: <task title>

> Copy to `.loop/<task-slug>/state.md`. This file is the source of truth (SOP-9).
> Fill the Frame once; append to the Iteration Log every cycle; keep the Footer current.

## Frame
- **Slug:** <task-slug>
- **Goal:** <one sentence — what success looks like>
- **Profile:** <roblox-game | openscad | personal-ai | landuse-research | custom>
- **Architecture:** <iterative-refinement | evaluator-optimizer | reflexion | react | tree-of-thoughts | orchestrator-worker> — <why>
- **Reflection mode:** <none | last_attempt | reflexion | both>
- **Started:** <YYYY-MM-DD>

### Success criteria (measurable — SOP-1)
- [ ] <criterion 1, checkable>
- [ ] <criterion 2, checkable>

### Budget (SOP-2)
- max_iterations: <N>
- no_improvement_streak: <N>   <!-- stop after this many gainless iterations -->
- cost/time ceiling: <e.g. $X or N min — for unattended runs>
- effort tier: <low | medium | high | xhigh | max — scale to task complexity>
- workers (if fan-out): <count, e.g. 3-5> · per-worker maxTurns: <N>
- enforced by: <self | hook (Stop/PostToolBatch) | maxTurns/maxBudgetUsd>

### Ground truth (SOP-3)
- **Verify command / check:** <exact command or procedure that decides pass/fail>
- **Metric:** <the number this loop drives, + direction, e.g. "frame time ms ↓">
- **Baseline:** <metric value at iteration 0>

---

## Iteration log
<!-- Append one block per iteration. Keep each to a few lines (SOP-8). -->

### Iter 1 — <YYYY-MM-DD HH:MM>
- **Change:** <the single change made (SOP-4)>
- **Verify:** <result of the ground-truth check — pass/fail + key output>
- **Metric:** <value> (Δ vs prev: <+/->)
- **Checkpoint:** <commit/path if taken (SOP-5)>
- **Reflection:** <what failed, likely cause, next thing to try (SOP-6)>
- **Decision:** <CONTINUE | CONVERGED | DIMINISHING | BUDGET | STUCK> (SOP-10)

---

## Footer (keep current)
- **Current best:** <metric> @ <location/commit>
- **no_improvement_streak:** <N>
- **Status:** <RUNNING | CONVERGED | STOPPED:reason>

## Final summary (on stop)
- **Outcome:** <criteria met? which/why not>
- **Best result:** <what + where>
- **What's left / next:** <follow-ups, if any>
