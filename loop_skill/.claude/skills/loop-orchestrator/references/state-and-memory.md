# State & Memory — making loops resumable and lean

The on-disk **loop-state file** is the single source of truth (SOP-9). Everything
needed to stop, resume, or audit a run lives there — not in the chat context.

## Layout

```
.loop/
  <task-slug>/
    state.md            # the source of truth (from templates/loop-state.template.md)
    checkpoints/        # saved artifacts/metrics per checkpoint (SOP-5)
      iter-03/          # e.g. a copy of the model, a build, a metric snapshot
    artifacts/          # outputs produced during the run (renders, logs, reports)
    reflections.md      # optional: longer Reflexion notes if they outgrow state.md
```

Use one `<task-slug>` directory per goal. Keep `state.md` short — it is read at
the start of every iteration, so it must stay cheap to load.

## What goes in `state.md`

Frame (written once): goal, measurable success criteria, budget, chosen
architecture, profile, ground-truth verify command, baseline metric.
Iteration log (appended each cycle): iteration #, the one change made, verify
result, metric (and delta vs. last), reflection, and the explicit decision.
Footer (updated each cycle): current best result + its location, and
`no_improvement_streak`.

## Checkpoints (SOP-5)

Before a risky change, snapshot enough to roll back: a git commit hash, a copy of
the artifact under `checkpoints/iter-NN/`, and the metric at that point. On a
regression, restore the last good checkpoint and change strategy. Record in
`state.md` which checkpoint is "current best."

## Context hygiene (SOP-8)

- **Summarize, don't accumulate.** Each completed iteration collapses to one or
  two lines in the log. Don't keep full diffs/outputs in context — they're on disk.
- **Delegate heavy work to subagents.** Reading a large codebase, building,
  rendering, or searching many sources runs in a subagent with isolated context;
  only the conclusion + metric returns to the orchestrator.
- **The orchestrator holds the thread**, not the data: goal, criteria, budget,
  last decision, next plan.

## Resuming a run

1. Read `.loop/<task-slug>/state.md`.
2. Reconstruct: criteria, budget remaining, current best, last reflection.
3. Verify the current best still passes the ground-truth check (state can drift).
4. Continue from the next planned action, or stop if a stop condition already holds.

Because the file captures the full frame and history, a fresh session — or a
scheduled/unattended run — can pick up exactly where the last left off.

## Relationship to native memory

This file-based state is deliberately tool-agnostic and complements Claude's
persistent memory and the Agent SDK's resumable `session_id`/fork mechanism
(`RESEARCH.md` §4): the session resumes the *conversation*; `state.md` resumes the
*loop* — its criteria, budget, metric history, and stop logic — independent of any
one session.
