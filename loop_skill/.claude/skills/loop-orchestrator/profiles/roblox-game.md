# Profile: Roblox game (e.g. "Eagles vs Crows")

> Iteratively research and improve a Roblox/Luau game. Tune the verify commands to
> your toolchain (Rojo, Wally, run-in-Studio, Luau tests) on first use.

## When to use this profile
Improving gameplay, balance, performance, or systems in a Roblox game; running a
research→change→playtest loop on a specific feature or metric.

## Default architecture
**ReAct (plan-act-observe)** as the spine — ground truth comes from *running* the
game. Escalate to **orchestrator-worker** when sweeping many balance/parameter
variants in parallel, or **evaluator-optimizer** for design-quality questions
(fun, clarity) judged against a rubric.

## Ground truth (SOP-3)
- **Primary check (rules-based):** Luau type-check + lint (e.g. `luau-analyze`,
  `selene`) and any unit tests (e.g. TestEZ) must pass; project builds with Rojo.
- **Behavioral check:** run the place (Studio Play / `run-in-roblox` or a headless
  test place) and assert the targeted behavior — server starts clean, no runtime
  errors in output, the feature does what the criterion says.
- **Visual:** screenshot/recording of the relevant scene for UI/feel changes.
- **Typical metrics:** client frame time / FPS (↓ frame ms), server step time,
  memory, network bytes/s, or a gameplay metric (e.g. round length, win-rate
  balance between Eagles vs Crows).

## Default budget (SOP-2)
- max_iterations: 8
- no_improvement_streak: 3
- cost/time ceiling: set per session for unattended balance sweeps

## Reflection mode (SOP-6)
**reflexion** — playtest failures are informative; carry "what broke and why" forward.

## Domain guardrails
- Never commit secrets / API keys; never disable a passing test to "win" (SOP-7).
- Keep a known-good place file as a checkpoint before risky systemic changes.
- Don't change two systems in one iteration (SOP-4) — balance regressions get
  un-attributable fast.
- Respect Roblox platform rules; no exploit/cheat tooling.

## Success-criteria starters
- "Eagles vs Crows win-rate within 50% ± 5% over N simulated/recorded rounds."
- "No runtime errors in server log across a full match."
- "Client frame time < 16 ms (60 FPS) on the test scene."
- "New ability behaves per spec: <explicit observable behavior>."

## Notes / tools
- Toolchain to confirm: Rojo (sync/build), Wally (deps), Selene/luau-analyze
  (lint/types), TestEZ (tests), run-in-roblox / Open Cloud (headless runs).
- Use the `deep-research` skill for the "research" half (mechanics, balance
  references, similar games) and feed conclusions into the loop's plan step.
