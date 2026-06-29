# Architectures — choosing & running the loop

Pick the **least complex** architecture that fits; escalate only when the task
shape demands it. (Source detail in `RESEARCH.md`.)

## The menu

### 1. Iterative refinement — *default*
Single track: produce → check → improve, repeat until criteria or budget.
**Use when:** criteria are checkable and one line of attack is enough.
**Cost:** lowest. **Start here unless a trigger below applies.**

### 2. Evaluator-optimizer (generator-critic)
One agent produces; a **separate** agent evaluates against the rubric and returns
specific feedback; loop. The two roles must be distinct (SOP-7).
**Trigger:** a clear rubric exists and feedback measurably improves output
(writing quality, design review, code review, research answers).

### 3. Reflexion (refinement + persisted memory)
Like refinement, but each failure produces a written reflection that is carried
into later attempts as episodic memory.
**Trigger:** failures are *informative* and you get multiple attempts (debugging,
puzzle-like tasks, "it compiled but behaves wrong"). Set reflection mode in the profile.

### 4. ReAct (plan-act-observe)
Interleave reasoning and tool calls; observe the environment after each act and
let observations drive the next step.
**Trigger:** heavy tool/environment interaction where ground truth only comes from
acting (running the game, rendering a model, querying data).

### 5. Tree search (LATS — Language Agent Tree Search)
Generate N candidate approaches, self-evaluate each, keep the best, **backtrack**
and prune dead branches. Formally this is MCTS adapted to LM agents (LATS, ICML
2024): nodes are states (input + action/observation history), and because LM
environments are *reversible* you can "reset to any step by copy-pasting the
historical text" — no learned world model needed. LATS folds a **Reflection** step
(SOP-6) into the search, so failed branches leave verbal lessons behind.
**Trigger:** wide solution space where a single greedy path is unreliable
(architecture/design choices, parameter search, "which approach?"). Most expensive
pattern — **bound branching factor and depth in the budget** (SOP-2).

### 6. Orchestrator-worker (fan-out / fan-in)
Lead agent decomposes the goal into independent subtasks, spawns specialized
subagents in **parallel** (isolated context), then synthesizes their results.
**Trigger:** the task splits into independent parts (research many sources, audit
many files, sweep many parameter sets). Scale worker count to complexity (SOP-2).
Each worker runs its own mini gather→act→verify; the lead owns the stop decision.

## Decision guide

```
Is the task naturally parallel / decomposable?        → Orchestrator-worker (6)
Wide solution space, one path likely wrong?           → Tree search / LATS (5)
Ground truth only from running tools/environment?     → ReAct (4)
Failures informative & multiple attempts available?   → Reflexion (3)
Clear rubric where a critic adds measurable value?    → Evaluator-optimizer (2)
Otherwise                                             → Iterative refinement (1)
```
Patterns compose: e.g. an orchestrator-worker where each worker runs Reflexion,
or refinement with an evaluator-optimizer verify step. Compose deliberately, and
keep the stop decision with the top-level loop.

## Execution modes (how the loop actually runs)

- **Interactive (default)** — you drive iterations in-session, confirming the
  frame and reporting at stop.
- **In-session paced** — use the **`/loop`** skill to reinvoke "advance
  `.loop/<task>/state.md` by one iteration" on an interval or self-paced. Good for
  polling-style or steady-cadence work.
- **Unattended / recurring** — use the **`schedule`** skill (scheduled tasks /
  cron) for runs that fire without you present. Always set a hard budget (SOP-2)
  and a cost ceiling for these.
- **Deterministic gates (Claude Code hooks)** — the model can rationalize its way
  past a soft instruction; it cannot bypass a hook, because the *harness* enforces
  hooks. Use them to hard-enforce SOP-3/SOP-7. The loop-relevant events:
  - **`Stop` / `SubagentStop`** — return `{"decision":"block","reason":"..."}` to
    *refuse to stop* until a gate passes (doc example: "tests must pass before
    stopping"). A `stop_hook_active` flag prevents infinite re-fire.
  - **`PostToolBatch`** — fires after a batch of parallel tool calls resolves and
    *before the next model call*; **exit code 2 stops the loop there** → a native
    per-iteration verification checkpoint.
  - **`PreToolUse`** — allow / deny / ask / defer (or rewrite args via
    `updatedInput`) before a tool runs; use to fence risky actions.
  - **`continue:false`** stops Claude entirely and takes precedence over
    event-specific decisions. *(Field names tied to Claude Code v2.1.x — confirm
    against current docs; see `RESEARCH.md` caveats.)*
- **Heavy steps & workers** — delegate to **subagents** for isolated context
  (SOP-8); for parallel file edits use worktree isolation. A skill can itself run
  as an isolated worker via **`context: fork`** (its body becomes the subagent
  prompt, no access to chat history). Tune workers via **`AgentDefinition`**:
  `maxTurns` (turn cap = budget), `model`, `effort` (scale to complexity),
  `tools` (least privilege), `background` (non-blocking).

## Anti-patterns
- Looping with no external verify step (you're just re-rolling the dice).
- Letting the generator grade its own work (violates SOP-7).
- No budget → runs until it wanders or burns cost.
- Carrying full prior outputs in context instead of a summarized state file.
- Tree-search with unbounded branching/depth.
