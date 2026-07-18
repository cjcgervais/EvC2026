---
name: evc-loop
description: >-
  The governing session harness for the Eagles vs Crows Roblox game. Run a
  disciplined, SOP-tuned work loop that protects the LOCKED control specs,
  changes ONE thing at a time, verifies against ground truth, red-teams the
  change before proposing it, keeps memory + HANDOFF current, and commits/pushes
  only on approval — so a cleared-context agent can pick up and succeed. Use when
  starting or continuing a work session on this game ("continue", "next session",
  "keep going on the crows / combat / 1-v-4", "work on EvC", "run the loop"),
  before ANY control/camera/flight-feel/kernel edit, and when closing out a
  session (update memory, prep the handoff, commit).
---

# EvC Loop — the governing orchestrator for Eagles vs Crows

This skill turns each work session into a bounded, auditable, self-correcting
loop tuned to *this* project's rules. It is the operational layer on top of the
generic `loop-orchestrator` (in `loop_skill/`): same FRAME→PLAN→ACT→VERIFY→
SCORE→REFLECT→DECIDE spine and the same non-negotiable SOPs, specialized with
Eagles-vs-Crows's LOCKED control specs, its verify reality (Studio Play is
ground truth), and its memory/handoff discipline.

**Read `CLAUDE.md` and `docs/HANDOFF.md` (the COLD START box) before acting — they
are the contract and the current state. This skill governs *how* you work them.**

## The prime directives (never violate — full text in the references)

1. **Protect the LOCKED CONTROL SPECS (CS-1…CS-9).** Grep/read the registry in
   `docs/HANDOFF.md` before ANY control/camera/input/flight-feel/kernel edit.
   Never change a locked behavior *collaterally* while building something else.
   → `references/locked-specs-gate.md`
2. **ASK, don't guess on control feel.** A wrong guess that ships is worse than a
   question. If intent is ambiguous, stop and ask Chad.
3. **ONE meaningful change per iteration.** Keep the build green; make the metric
   move attributable. Checkpoint (commit/tag) *before* any kernel edit.
4. **Ground truth is Chad's Studio Play.** `build.ps1` resolves wiring but does
   NOT run or syntax-check Luau. Never mark work "done" on your own assertion.
   → `references/verify-ladder.md`
5. **flight == balance.** Every flight number is also a balance number. Reason
   about the whole 1-eagle-vs-4-crow fight on every tuning edit.
6. **Refine incrementally; do NOT regenerate.** The codebase is modular for
   exactly this. Change one module/feature, then verify.
7. **LOG every playtest note + outcome** into the HANDOFF session block / CS
   registry so decisions are durable and never re-litigated.
8. **VET THE APPROACH before building any perceptual change (FX / animation /
   procedural geometry).** Reason away from mediocre techniques: name the *read*
   in Chad's words, kill any technique whose ceiling is below it (a soft particle
   puff can never be discrete falling feathers), headless-gate the one that can
   reach it, and bring Chad a vetted + gated WORKING result — not a menu of
   approaches, not an untested guess. "Which of two mediocre options?" is never a
   valid question; reason past both. Chad flies to confirm a *refinement*, never
   the viability of an approach. → `references/fx-approach-vetting.md`

## The session lifecycle (this is the loop)

Run these phases in order. Full checklists are in `references/session-protocol.md`.

```
START     → orient: read HANDOFF cold-start + MEMORY.md + the LOCKED CS registry.
            State the frontier item you're taking and the FRAME (done + budget).
            Open a session log from templates/session-log.template.md.
─── loop one change at a time ───────────────────────────────────────────────
PLAN      → the single next change. If it touches controls/kernel → LOCKED-SPEC
            GATE first; if it's a perceptual read (FX/animation/geometry) →
            APPROACH-VETTING gate first (reason away from mediocre techniques,
            fx-approach-vetting.md); if intent is fuzzy → ASK.
ACT       → make the one change (or delegate heavy work to a subagent).
VERIFY    → run the verify ladder (build/analysis) + write a crisp Chad-playtest
            checklist for anything only Studio can judge.
RED-TEAM  → before proposing a control/kernel/combat change, spawn the
            red-team-reviewer subagent to attack it against the SOPs. Fix or
            surface what it finds. → references/red-team.md
SCORE     → record result + pass/fail vs. the FRAME in the session log.
REFLECT   → if not done, 1–3 lines: what failed / what to try next.
DECIDE    → CONVERGED | DIMINISHING | BUDGET | STUCK → stop; else checkpoint → PLAN.
─── close ───────────────────────────────────────────────────────────────────
CLOSE     → update project memory + MEMORY.md index; append the HANDOFF session
            block and refresh the COLD START box + frontier queue so a
            cleared-context agent inherits everything; propose commit/push
            (Chad approves — the harness gates git). → references/memory-and-handoff.md
```

## Stop conditions (decide explicitly every iteration)

- **CONVERGED** — the FRAME's criteria are met by the ground-truth check (usually
  Chad's playtest confirms it). ✅
- **DIMINISHING** — N iterations with no metric gain → stop, report best.
- **BUDGET** — hit max iterations / cost / wallclock → stop.
- **STUCK / REGRESSING** — same error twice, or worse than a checkpoint → roll
  back to the last good checkpoint; change strategy or ask.

## What the harness enforces for you (hooks, see `.claude/settings.json`)

- **SessionStart** injects the HANDOFF cold-start so a fresh agent is oriented.
- **PreToolUse** makes `git commit` / `git push` **ask for Chad's approval** — you
  may prepare commits, but they land only when he says so.

These are safety nets, not substitutes for the discipline above.

## Files

- `references/session-protocol.md` — the full START / loop / CLOSE checklists.
- `references/locked-specs-gate.md` — the control-spec guardian: how to check an
  edit against CS-1…CS-9 before making it.
- `references/verify-ladder.md` — the testing SOP: what proves what, the optional
  headless static-analysis tier (`verify.ps1`), and writing a Studio-playtest checklist.
- `references/memory-and-handoff.md` — memory-maintenance + context-clear handoff SOPs.
- `references/red-team.md` — the adversarial-review protocol + the reviewer subagent.
- `references/fx-approach-vetting.md` — the PLAN-time gate for perceptual changes
  (FX/animation/geometry): vet the technique against the read, reject mediocre
  approaches, headless-gate + propose a working result instead of asking.
- `templates/session-log.template.md` — copy to `.loop/<session-slug>/state.md` to start.
