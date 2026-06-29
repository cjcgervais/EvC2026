# Profile: <domain name>

> A profile customizes the universal loop for a domain. Copy this to
> `profiles/<domain>.md` and fill it in. The orchestrator reads the active profile
> at FRAME time to set defaults; SOPs still apply (and SOP-1/2/3/7 cannot be relaxed).

## When to use this profile
<one line: what kinds of tasks this profile fits>

## Default architecture
<which architecture from references/architectures.md, and why this domain favors it>

## Ground truth (SOP-3) — how we verify each iteration
- **Primary check:** <the cheapest reliable command/procedure that decides pass/fail>
- **Escalation:** <visual check, then LLM-judge rubric, if the primary is insufficient>
- **Typical metric(s):** <the number(s) the loop drives, with direction>

## Default budget (SOP-2)
- max_iterations: <N>
- no_improvement_streak: <N>
- cost/time ceiling: <if unattended>
- effort tier: <low | medium | high | xhigh | max>
- workers (if fan-out): <count> · enforce via: <self | hook | maxTurns/maxBudgetUsd>

## Reflection mode (SOP-6)
<none | last_attempt | reflexion | both> — <why>

## Domain guardrails
- <domain-specific rule, e.g. "never edit X", "always keep Y working", safety/cost limits>

## Success-criteria starters (make them measurable)
- <example checkable criterion the user will usually want>
- <another>

## Notes / tools
- <domain tools, file locations, commands, gotchas the loop should know>
