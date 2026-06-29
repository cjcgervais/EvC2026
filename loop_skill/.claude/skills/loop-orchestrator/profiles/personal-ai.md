# Profile: Personal AI tooling

> Iterate on personal AI software — prompts, agents, skills, pipelines, RAG, evals.

## When to use this profile
Building or improving prompts, agents/skills, LLM pipelines, or retrieval — where
"better" means measurable behavior on a set of cases, not vibes.

## Default architecture
**Evaluator-optimizer** — a prompt/agent is the optimizer; an **independent**
eval (rules + LLM-judge with a fixed rubric) is the verifier (SOP-7). Escalate to
**Reflexion** when failures cluster and reflections speed convergence, or
**orchestrator-worker** to evaluate many cases / variants in parallel.

## Ground truth (SOP-3)
- **Primary check (rules-based):** a **held-out eval set** of input→expected (or
  input→assertion) cases; score = pass rate / exact-match / regex / schema-valid
  JSON / tool-call-correctness. This set is **frozen** — the loop tunes the
  system, never the eval (SOP-7).
- **LLM-as-judge:** for open-ended outputs, a separate judge agent scores against
  a written rubric; keep the rubric and judge fixed across iterations.
- **Typical metrics:** eval pass rate ↑, judge score ↑, tokens/cost per task ↓,
  latency ↓, regression count = 0 on previously-passing cases.

## Default budget (SOP-2)
- max_iterations: 10
- no_improvement_streak: 3
- cost/time ceiling: set a token/$ ceiling — eval loops can be expensive

## Reflection mode (SOP-6)
**both** (last_attempt + reflexion) — keep prior failing cases and the lesson learned.

## Domain guardrails
- **Never edit the eval set or judge rubric to raise the score** (SOP-7). Add new
  cases only as a separate, announced step.
- Guard against regressions: a change that fixes new cases but breaks previously-
  passing ones is a STUCK/rollback (SOP-5), not progress.
- Watch for judge reward-hacking (outputs that flatter the judge but don't solve
  the task) — spot-check judged "wins" against rules-based checks.
- Use the latest capable Claude models; pin the model id so eval scores are comparable.

## Success-criteria starters
- "≥ <X>% pass rate on the frozen eval set, with 0 regressions on prior passes."
- "Average judge score ≥ <X>/5 on the rubric across the eval set."
- "Median cost per task ≤ <$/tokens>; p95 latency ≤ <ms>."

## Notes / tools
- See the `claude-api` skill for current model ids, pricing, tool-use, caching,
  and token counting before tuning cost/latency.
- Version each prompt/agent variant under `artifacts/` and record which scored best.
