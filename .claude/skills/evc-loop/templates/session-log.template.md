# Session log — <session-slug>

> Copy to `.loop/<session-slug>/state.md` (gitignored). This is the resumable
> source of truth for the loop — keep it short; it's read at the start of every
> iteration. Summarize completed iterations to a line or two.

## FRAME (write once)
- **Date:** <YYYY-MM-DD>
- **Frontier item taken:** <which HANDOFF queue item / Chad's ask>
- **Goal (this session):** <one sentence>
- **Done =** <checkable criterion; usually terminates in a Chad Studio-Play
  confirmation — name exactly what he should observe>
- **Budget:** max_iterations = <N> · no_improvement_streak = <M> · <optional time/cost>
- **Architecture:** <iterative-refinement | reflexion | ReAct | orchestrator-worker | …>
- **Baseline / starting state:** <commit hash, current behavior, build status>
- **LOCKED specs / invariants in scope:** <CS-# rows + kernel invariants this touches>

## Iteration log (append one per cycle)

### Iter 1 — <short title>
- **PLAN (the ONE change):** <…>  · LOCKED-SPEC gate: <n/a | checked, clear | ASKED Chad>
- **ACT:** <what changed, which module>  · checkpoint: <commit/tag before edit>
- **VERIFY:** build.ps1 <green/red> · verify.ps1 <green/red/skipped> · playtest checklist handed to Chad: <yes/no>
- **RED-TEAM:** <verdict + any findings, or n/a>
- **SCORE:** <pass/fail vs. Done> · metric Δ vs last: <…>
- **REFLECT:** <what failed / likely cause / next thing to try — if not done>
- **DECIDE:** CONTINUE | CONVERGED | DIMINISHING | BUDGET | STUCK

### Iter 2 — …

## Footer (update each cycle)
- **Current best:** <state + where / commit>
- **no_improvement_streak:** <n>
- **Awaiting:** <Chad playtest of X | nothing>

## Final summary (on stop)
- **Outcome:** <CONVERGED/…> · **What landed:** <…> · **Build/playtest status:** <…>
- **What's left / next session:** <…>
- **CLOSE done?** memory updated <y/n> · MEMORY.md index <y/n> · HANDOFF session block + COLD START refreshed <y/n> · commit proposed <y/n>
