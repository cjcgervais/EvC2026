# Session protocol — START / loop / CLOSE

This is the full lifecycle the `evc-loop` skill runs. It specializes the generic
`loop-orchestrator` (`loop_skill/`) for Eagles vs Crows. Keep your own context
lean: read the state files, hold the *thread* (goal, FRAME, last decision, next
plan) in context, and delegate heavy reading/building to subagents.

---

## START — orient before you touch anything (do every session)

1. **Read the state**, in this order:
   - `docs/HANDOFF.md` → the **COLD START box** (top) + the newest **SESSION block**.
   - `C:\Users\Chad\.claude\projects\D--EvC2026\memory\MEMORY.md` (the index), then
     follow pointers you need.
   - The **LOCKED CONTROL SPECS registry** (CS-1…CS-9) in `docs/HANDOFF.md`.
   - `CLAUDE.md` (architecture + contracts) if you'll touch code you don't already know.
2. **Confirm the frontier.** State, in one or two lines, which item from the
   HANDOFF frontier queue you're taking this session. If Chad named a different
   goal, take that instead.
3. **Set the FRAME (SOP-1 + SOP-2).** Write down:
   - **Done** = a *checkable* success criterion. For feel/combat that usually
     terminates in a **Chad Studio-Play confirmation** — name exactly what he
     should observe. ("Build green" is a floor, never the definition of done.)
   - **Budget** = max iterations (default 3–6 for a feature; 1–2 for a fix) and a
     no-improvement-streak (default 2). Say it out loud before iterating.
4. **Open a session log.** Copy `templates/session-log.template.md` to
   `.loop/<session-slug>/state.md` (the `.loop/` dir is gitignored). Fill in goal,
   FRAME, budget, and the baseline. This is the resumable source of truth.
5. **If criteria or intent are ambiguous, ASK Chad before iterating.** A wrong
   target wastes the whole loop, and control feel is his call (prime directive 2).

---

## THE LOOP — one change at a time

Each iteration is PLAN → ACT → VERIFY → RED-TEAM → SCORE → REFLECT → DECIDE.
Append one entry to the session log per iteration.

### PLAN
- Decide the **single** next change (SOP-4). If you're tempted to do two, split
  them into two iterations.
- **Trip the LOCKED-SPEC GATE** if the change touches control / camera / input /
  flight-feel / the aero kernel. Do not proceed past the gate on a guess — read
  `references/locked-specs-gate.md` and, if intent is fuzzy, **ASK**.
- **Checkpoint before risk (SOP-5).** Before any kernel edit or systemic change,
  ensure there's a clean revert point: a commit hash or tag. Revert points of
  record: tag `v1.0-eagle-flight` (pure kernel), tag `v1.1-eagle-flight-feel`,
  branch `single-bird-kernel`, plus the last session commit.

### ACT
- Make the one change. Prefer editing a single module (see the module map in
  `CLAUDE.md`). **Refine, don't regenerate** (prime directive 6).
- Delegate heavy reading/searching/building to a subagent so your context stays
  lean (SOP-8); bring back only the conclusion.
- Keep Eagle/Crow profiles structurally identical — asymmetry lives in the
  numbers, so `FlightPhysics` stays class-agnostic.

### VERIFY (`references/verify-ladder.md`)
- Run the ladder cheapest-first: `build.ps1` (or `verify.ps1` for the optional
  headless analysis tier) must be green.
- Remember the hard truth: **the build does not run or syntax-check Luau. Only
  Chad's Studio Play validates behavior and feel.** So for anything behavioral,
  produce a **crisp playtest checklist** (exact inputs → expected observation +
  the knob to turn if it's off). That checklist IS your ground-truth request.

### RED-TEAM (`references/red-team.md`)
- Before you *propose* a change that touches controls, the kernel, combat, or the
  1-v-4 balance, spawn the **`red-team-reviewer`** subagent to attack it against
  the SOPs (LOCKED specs, no-collateral, one-change, flight==balance, build-green,
  no-regenerate). Fix what it finds, or surface the disagreement to Chad. Skip
  red-team only for pure docs/memory edits.

### SCORE
- Record the verify result and pass/fail against the FRAME, with the metric delta
  vs. the last iteration, in the session log.

### REFLECT (Reflexion — SOP-6)
- If it didn't meet the criterion, write 1–3 lines: *what* failed, the likely
  *cause*, the *next* thing to try. Carry that into the next PLAN. (Playtest
  failures are especially informative — that's how the crow-AI fix was found.)

### DECIDE (SOP-10)
- End every iteration with exactly one: **CONVERGED / DIMINISHING / BUDGET /
  STUCK / CONTINUE**. On STUCK or a regression, roll back to the last checkpoint
  and change strategy — do not stack fixes on a broken state.

---

## CLOSE — leave the codebase better than a cold start expects

Do this before ending a session (or when Chad says to wrap up / clear context).
The goal: **a cleared-context agent invoked next inherits everything it needs.**
Full detail in `references/memory-and-handoff.md`.

1. **Update project memory.** For every resolved design question, new constraint,
   confirmed preference, or playtest outcome: write/update the relevant memory
   file (correct frontmatter + type) and update the one-line pointer in
   `MEMORY.md`. Prefer updating an existing file over creating a duplicate.
2. **Log the playtest results** into the CS registry rows and/or the session block
   (prime directive 7) — verbatim where Chad's words matter.
3. **Refresh `docs/HANDOFF.md`:** append a new SESSION block (what landed, why,
   build/playtest status, commits) AND update the **COLD START box** — current
   state, the frontier queue, and the next-agent playtest checklist — so the top
   of the file is always true *right now*.
4. **Propose commit/push.** Prepare a clear commit (message ending with the
   Co-Authored-By line the repo uses). The PreToolUse hook makes git **ask** —
   Chad approves the commit and the push. Never push without his go-ahead.
5. **Close the session log** with a final summary (outcome, best result, what's
   left) and mark the loop's stop condition.

### The context-clear guarantee (the whole point)
Before you consider a session closed, sanity-check: *if I cleared context right
now and a fresh agent ran `/evc-loop`, would it know exactly where we are, what's
locked, what's next, and how to verify?* If not, fix the HANDOFF/memory until the
answer is yes. That is the definition of a clean close.
