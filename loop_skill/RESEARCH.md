# Research: Agentic Loop Orchestration for AI Coding Agents

**Question:** What are the latest, highest-leverage, proven patterns for orchestrating agentic loops with AI coding agents (Claude Code / Claude Agent SDK), to inform a universal, customizable "loop orchestrator" skill?

**Date:** 2026-06-24 · **Method:** Fan-out web research, 5 angles → 24 sources → 118 extracted claims → top 25 adversarially verified (3 independent verifier votes each).

> ✅ **Verification status: complete.** 25/25 verified claims **confirmed**, 0 refuted. All but one carried unanimous **3-0** votes; the lone **2-1** (subagent resumability) dissent cited a GitHub issue that on inspection *confirms* resumption. Every finding rests on a **primary source** (official Anthropic/Claude docs or a peer-reviewed paper). Numeric figures (e.g. "up to 90% faster") are flagged where source-hedged.
>
> ⚠️ **Two requested sub-topics lacked direct primary-source coverage** and are therefore *reasoned design*, not citation-backed: (a) **anti-reward-hacking** guardrails and (b) **per-domain config-profile structure**. These shaped SOP-7 and `profiles/` by analogy/best-practice — treat them as design decisions, not established findings. See Open Questions.

---

## TL;DR — what the sources converge on

1. **One canonical loop.** Build the orchestrator on the Claude Agent SDK loop: **gather context → take action → verify work → repeat**. Every refinement pattern below maps onto it. *(high, 3-0)*
2. **Patterns are a menu, not rivals.** Evaluator-optimizer, Reflexion, ReAct, LATS (tree search), and orchestrator-worker fan-out are selected by task shape and all sit on the canonical loop. *(high, 3-0)*
3. **Bound the loop explicitly.** Max-iteration / turn budgets and cost ceilings are standard production guardrails against runaway cost and context degradation. *(high, 3-0)*
4. **In Claude Code, make the gates *deterministic*.** Hooks are harness-enforced, not model-discretion: `Stop`/`SubagentStop` can **block** termination until a build/quality gate passes; `PostToolBatch` is a per-iteration checkpoint that can **stop the loop before the next model call**; `PreToolUse` guards each tool call. *(high, 3-0)*
5. **Verify cheapest-first.** Rules-based feedback ("which rule failed and why", e.g. linting) is best; visual feedback and LLM-as-judge are *supplementary*. *(high, 3-0)*
6. **State hygiene via isolation + resumability.** Subagents run in fresh, isolated context and return only their final message; capture a `session_id` and `resume` for stateful multi-iteration loops. *(high, 3-0 / 2-1)*
7. **Package as a Skill.** A `SKILL.md` directory with progressive disclosure; `context: fork` runs it as an isolated worker subagent; `AgentDefinition` exposes per-worker `maxTurns`/`model`/`effort`/`tools`/`background`. *(high, 3-0)*
8. **Proven orchestrator-worker template.** Lead agent + 3-5 parallel specialized subagents, **effort scaled to query complexity**; Anthropic reports up to ~90% faster for complex queries (best-case, multiple combined optimizations — not fan-out alone). *(high, 3-0)*

---

## 1. Core loop architectures

**The canonical loop** *(high, 3-0)* — Anthropic defines the agent feedback loop as **gather context → take action → verify work → repeat**, with live controls (`maxTurns`, `maxBudgetUsd`, hooks, compaction). *Caveat: "verify work" is a design-framing phase, not a hard-coded runtime step — the runtime loop is technically a tool-call cycle.* [Agent SDK; agent-loop docs]

| Pattern | What the source says | Use when | Confidence |
|---|---|---|---|
| **Evaluator-optimizer (generator-critic)** | "one LLM call generates a response while another provides evaluation and feedback in a loop" | a clear rubric exists and iterative refinement demonstrably improves outcomes | high, 3-0 |
| **Reflexion** | reinforce "not by updating weights, but through linguistic feedback"; reflective text in an **episodic memory buffer**; converts binary/scalar feedback into a verbal **"semantic gradient"** added as context for the next episode | failures are informative and you get multiple attempts | high, 3-0 |
| **ReAct (plan-act-observe)** | the autonomous loop is act-observe-feedback; ground truth comes from acting | heavy tool/environment interaction | high (corroborated) |
| **LATS (Language Agent Tree Search)** | adapts **Monte Carlo Tree Search** to unify reasoning/acting/planning; nodes are states `s=[x,a₁..ᵢ,o₁..ᵢ]`; exploits LM-environment **reversibility** ("reset to any step by copy-pasting historical text input") to avoid a learned world model; runs Selection, Expansion, Evaluation, Simulation, Backpropagation **+ Reflection** | wide solution space; a single greedy path is unreliable; you can afford search | high, 3-0 |
| **Orchestrator-worker (fan-out/fan-in)** | lead agent coordinates + delegates to specialized subagents running in parallel | task decomposes into independent subtasks | high, 3-0 |

*Sources:* Building Effective Agents; Reflexion (NeurIPS 2023, arXiv:2303.11366); LATS (ICML 2024, arXiv:2310.04406); Multi-Agent Research System.

## 2. Termination & convergence *(high, 3-0)*

- **Explicit stopping conditions** (e.g. max iterations) are standard to "maintain control"; corroborated by independent 2024-2026 sources (Oracle, Google ADK Loop Agents). [Building Effective Agents]
- **Deterministic, harness-enforced gates in Claude Code** (the key practical lever):
  - **`Stop` / `SubagentStop` hooks** — return `{"decision":"block","reason":...}` to *prevent stopping* until a gate passes (doc example: "Tests must pass before stopping"); a `stop_hook_active` flag prevents infinite re-fire. [hooks docs]
  - **`PostToolBatch` hook** — fires "after a full batch of parallel tool calls resolves, before the next model call"; **exit code 2 stops the agentic loop before the next model call** → a native per-iteration verification/convergence checkpoint. [hooks docs]
  - **Layered exit-code semantics** — exit 2 is event-dependent (block tool / prevent stop / stop loop); `continue:false` stops Claude entirely and **takes precedence** over event-specific decisions. [hooks docs]
- **Effort scaled to complexity** — "Simple fact-finding requires just 1 agent with 3-10 tool calls, direct comparisons might need 2-4 subagents with 10-15 calls each." [Multi-Agent Research System]

## 3. Quality SOPs & guardrails

- **Rules-based verification is best** *(high, 3-0)*: "the best form of feedback is providing clearly defined rules for an output, then explaining which rules failed and why" (linting cited). Visual feedback (UI/render) and **LLM-as-judge are supplementary**. [Agent SDK]
- **`PreToolUse` guardrails** *(high, 3-0)*: allow / deny / ask / defer, or modify args via `updatedInput`, before a tool runs. *Caveat: enterprise managed allow/deny-lists can override at the margins, so "deterministic" is slightly overstated in edge cases.* [hooks docs]
- **Anti-reward-hacking & regression checks** — ⚠️ **no primary source in the verified set directly addresses this.** SOP-7 (verifier independent of optimizer; never weaken criteria/tests to pass) is therefore *reasoned best-practice* derived from the evaluator-optimizer separation, not a cited finding. Flagged as an Open Question.

## 4. Loop state & memory *(high, 3-0 / 2-1)*

- **Isolation for context hygiene**: subagents serve parallelization **and** context management — "each subagent runs in its own fresh conversation. Intermediate tool calls and results stay inside the subagent; only its final message returns to the parent." *Nuance: a fresh context still inherits the subagent system prompt, CLAUDE.md, and tool defs; the parent may summarize the returned message.* [Agent SDK subagents]
- **Resumability** *(2-1, confirmed)*: a completed custom/general-purpose subagent returns an `agentId`; capture `session_id` and pass `resume: sessionId` to "pick up exactly where it stopped rather than starting fresh." *Caveat: built-in Explore/Plan agents are one-shot and do NOT return an agentId.* [Agent SDK subagents]
- Design rule (our synthesis): the **on-disk loop-state file is the orchestrator-level source of truth**, complementing per-subagent session resume — see Open Questions on cross-session orchestrator state.

## 5. Claude Code mechanisms (the native toolbox) *(high, 3-0)*

- **Skills**: "each skill is a directory with SKILL.md as the entrypoint"; progressive disclosure means "a skill's body loads only when it's used, so long reference material costs almost nothing until you need it." *(name+description metadata, ~100 tokens/skill, still loads at startup.)* [Skills docs]
- **Bundled `/loop` skill**: ships alongside `/code-review`, `/batch`, `/debug`, `/claude-api`; these are **prompt-based** — "they give Claude detailed instructions and let it orchestrate the work using its tools" (vs. fixed-logic commands). `/loop` runs a prompt/command on a recurring interval in-session. [Skills docs]
- **`context: fork`**: makes a skill run in an isolated worker subagent — "the skill content becomes the prompt that drives the subagent. It won't have access to your conversation history"; an `agent` field selects the execution environment; results are summarized back. "Only makes sense for skills with explicit instructions." [Skills docs]
- **`AgentDefinition` per-worker controls**: `maxTurns` (turn cap), `model` override (opus/sonnet/haiku/fable/inherit/full id), `tools` (restricted set), `effort` (low/medium/high/xhigh/max/number), `background` (non-blocking). *(Current to Claude Code v2.1.x.)* [Agent SDK subagents]
- **Concurrent fan-out**: "independent subtasks finish in the time of the slowest one rather than the sum of all of them." [Agent SDK subagents]

## 6. Generic-yet-customizable via profiles

⚠️ **No primary source directly prescribes per-domain profile structure** — this is reasoned design. The configurable surface is, however, grounded in cited knobs that *do* generalize: the verification command (rules-based per SOP-3), iteration/cost budget (§2), subagent count + `effort` tier (§5, scaled to complexity per Multi-Agent Research System), and reflection mode (Reflexion §1). Profiles bind those knobs per domain; the loop engine and SOPs stay fixed.

---

## Caveats & time-sensitivity

- **Fast-moving surface.** Claude Code / Agent SDK features (`maxTurns`, `maxBudgetUsd`, hooks, `PostToolBatch`, `context: fork`, bundled `/loop`, `AgentDefinition` fields) are tied to specific versions (cited docs reference **v2.1.x, 2026**). Model aliases (opus/sonnet/haiku/fable), the Task→Agent rename, and the merge of custom commands into skills all changed recently — **re-confirm exact field names/values against current docs before locking a spec.**
- **URL drift.** Several `anthropic.com` URLs now 301/302-redirect to `claude.com` / `code.claude.com`; content is unchanged.
- **"90% faster"** is a hedged best-case for complex queries attributable to *multiple combined* optimizations (parallel subagents *and* subagents using 3+ tools in parallel), not fan-out alone.
- **"Verify work"** in the canonical loop is design-framing, not a hard runtime step.
- **`PreToolUse` "deterministic"** control can be overridden by enterprise managed permission lists at the margins.

## Open questions (honest gaps for follow-up)

1. **Anti-reward-hacking / regression checks** — what concrete guardrails do production systems use to detect a loop gaming its own quality gate (editing tests to pass, declaring success without real verification)? No verified primary source covers this directly.
2. **Domain profile structure** — which knobs (verify command, gate thresholds, iteration/cost budget, subagent count, effort tier) truly generalize vs. need per-domain customization?
3. **Diminishing-returns heuristics** beyond max-iteration/cost (score-delta thresholds, repeated-failure detection, evaluator-confidence plateaus) — and whether any are natively supported by hooks.
4. **Orchestrator-level checkpoint/resumability** across sessions for long-running loops — durability/cost trade-offs of compaction vs. external state files.

---

## Sources (24 fetched; primary unless noted)

**Papers (peer-reviewed / arXiv)**
- Reflexion — arXiv:2303.11366 · https://arxiv.org/html/2303.11366 · OpenReview https://openreview.net/pdf?id=vAElhFcKW6
- LATS (Language Agent Tree Search) — arXiv:2310.04406 · https://arxiv.org/html/2310.04406v3 · https://par.nsf.gov/servlets/purl/10536241
- When Can LLMs Actually Correct Their Own Mistakes — TACL · https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00713/125177/
- arXiv:2410.20513 · arXiv:2405.06682 (reflection & search)

**Official Anthropic / Claude docs**
- Building Effective Agents — https://www.anthropic.com/research/building-effective-agents
- Building Agents with the Claude Agent SDK — https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
- Multi-Agent Research System — https://www.anthropic.com/engineering/multi-agent-research-system
- Effective Harnesses for Long-Running Agents — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Effective Context Engineering for AI Agents — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Equipping Agents for the Real World with Agent Skills — https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Managed Agents — https://www.anthropic.com/engineering/managed-agents
- Agent SDK subagents — https://docs.claude.com/en/docs/agent-sdk/subagents
- Agent SDK agent-loop — https://code.claude.com/docs/en/agent-sdk/agent-loop
- Hooks — https://docs.anthropic.com/en/docs/claude-code/hooks · https://code.claude.com/docs/en/hooks
- Skills — https://docs.claude.com/en/docs/claude-code/skills
- Context engineering cookbook — https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools

**Secondary / practitioner**
- LangChain — Reflection agents · https://blog.langchain.com/reflection-agents/
- Hugging Face — Design patterns for agentic workflows · https://huggingface.co/blog/dcarpintero/design-patterns-for-building-agentic-workflows
- AI coding agent guardrails (production) · https://www.mouhssinelakhili.com/en/blog/ai-coding-agent-guardrails-production-workflow
- How to build an agentic loop in Claude Code · https://www.mindstudio.ai/blog/how-to-build-agentic-loop-claude-code
- Agentic reasoning patterns · https://servicesground.com/blog/agentic-reasoning-patterns/
