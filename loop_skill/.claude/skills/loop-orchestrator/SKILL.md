---
name: loop-orchestrator
description: >-
  Run a customizable, self-correcting agentic loop over any task — iteratively
  produce, verify against ground truth, reflect, and stop on convergence or
  budget. Use when the user wants to iterate on a goal until it meets explicit
  criteria (improve/refine/optimize/research/"keep going until"), run a
  repeatable improvement loop, or orchestrate multi-step work with quality
  gates. Supports per-domain profiles (game dev, OpenSCAD/CAD, personal-AI,
  land-use research) and picks the right loop architecture for the task.
---

# Loop Orchestrator

A universal harness for running disciplined agentic loops. It turns "keep
improving X until it's good" into a bounded, verifiable, resumable process
instead of an open-ended chat. Grounded in `RESEARCH.md` (Anthropic Agent SDK
loop, evaluator-optimizer, Reflexion, ToT, multi-agent orchestration).

## The universal loop

Every run follows one cycle. Do not skip steps — each maps to a quality SOP.

```
0. FRAME    → define done (success criteria) + budget, pick architecture & profile
1. PLAN     → decide the single next change / move for this iteration
2. ACT      → make the change (or delegate to a subagent)
3. VERIFY   → run the profile's ground-truth check (tests/build/lint/render/eval)
4. SCORE    → record the metric + pass/fail against criteria, vs. last iteration
5. REFLECT  → if not done, write 1-3 lines: what failed & what to try next
6. DECIDE   → CONVERGED | DIMINISHING | BUDGET | STUCK → stop; else checkpoint → goto 1
```

State for every iteration is written to a loop-state file (source of truth, see
below) so the run is auditable and resumable.

## How to run a loop

1. **Read the SOPs first.** Load `references/sops.md` — these are mandatory, not
   optional. The non-negotiables: verify against an *external* signal every
   iteration; the verifier must be independent of the optimizer; never weaken
   criteria/tests to pass; always set a budget before iterating.
2. **Pick a profile.** If the task matches a domain, load the matching file in
   `profiles/` (e.g. `profiles/roblox-game.md`). Otherwise copy
   `profiles/_template.md` and fill it in with the user. The profile supplies the
   ground-truth command, default architecture, budget, and domain guardrails.
3. **Pick the architecture.** Use `references/architectures.md` to choose by task
   shape. Default to **iterative refinement**; escalate to evaluator-optimizer,
   Reflexion, ReAct, tree-search, or orchestrator-worker fan-out as the task
   warrants. State the choice and why.
4. **Create the loop-state file.** Copy `templates/loop-state.template.md` to
   `.loop/<task-slug>/state.md`. Fill in goal, success criteria (measurable!),
   budget, architecture, and verification command. See `references/state-and-memory.md`.
5. **Confirm the frame with the user** before iterating if the success criteria
   or budget are ambiguous — a wrong target wastes the whole loop. Then iterate.
6. **Each iteration:** update the state file (append an iteration entry with
   action, verify result, metric, reflection, decision). Keep the orchestrator
   context lean — delegate heavy reading/building to subagents.
7. **On stop:** write a final summary to the state file (outcome, best result,
   what's left) and report it to the user.

## Stop conditions (decide every iteration)

- **CONVERGED** — all success criteria met by the ground-truth check. ✅
- **DIMINISHING** — `budget.no_improvement_streak` iterations with no measurable
  metric gain. Stop and report the best result.
- **BUDGET** — hit `max_iterations`, cost ceiling, or wallclock. Stop.
- **STUCK/REGRESSING** — metric worse than a prior checkpoint, or the same error
  twice. Roll back to the last good checkpoint; change strategy or stop and ask.

## Running unattended / on a schedule

For background or recurring loops, compose native mechanisms (see
`references/architectures.md` §"Execution modes"):
- **In-session, paced** — the `/loop` skill reinvokes a prompt on an interval or
  self-paced; point it at "advance the loop in `.loop/<task>/state.md` by one
  iteration."
- **Cron / unattended** — the `schedule` skill (scheduled tasks) for recurring runs.
- **Deterministic gates** — hooks to hard-enforce "verify must pass" around edits/commits.

## Guardrails (read `references/sops.md` for the full set)

- Set the budget **before** the first iteration. No budget → no loop.
- Ground truth is external (a command, a render, a test, a rubric a human signed
  off on) — never the model's own assertion that it's done.
- One meaningful change per iteration where feasible; checkpoint before risky moves.
- Escalate verification cheapest-first: rules-based → visual → LLM-judge.
- If the user hasn't defined "done," **ask** — don't invent a target.

## Files

- `references/sops.md` — the standard operating procedures (mandatory rules).
- `references/architectures.md` — loop-pattern menu + how to choose + execution modes.
- `references/state-and-memory.md` — loop-state file, checkpoints, resumability, context hygiene.
- `profiles/` — per-domain config (`_template.md` + four ready profiles).
- `templates/loop-state.template.md` — copy this to start a run.
