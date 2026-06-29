# loop-orchestrator

A universal, customizable **Claude Code Skill** for running disciplined agentic
loops: iterate on any goal until it meets explicit, externally-verified criteria —
or a budget stops it. Built from research into proven agentic-loop patterns
(Anthropic Agent SDK loop, evaluator-optimizer, Reflexion, Tree-of-Thoughts,
multi-agent orchestration). See [`RESEARCH.md`](RESEARCH.md) for the cited basis.

## The loop

```
FRAME → PLAN → ACT → VERIFY → SCORE → REFLECT → DECIDE
                        │                          │
            external ground-truth check    CONVERGED | DIMINISHING | BUDGET | STUCK
```

Every iteration is verified against an **external** signal (tests, build, render,
eval, cited sources) — never the model's own say-so — and recorded to a resumable
on-disk state file.

## Use it

In this repo the skill auto-loads. Ask Claude Code to *improve / optimize /
research / "keep going until <criteria>"* and it will frame the loop, pick a
profile, set a budget, and iterate. To use it everywhere, copy
`.claude/skills/loop-orchestrator/` to `~/.claude/skills/`.

## What's inside

| Path | Purpose |
|---|---|
| `.claude/skills/loop-orchestrator/SKILL.md` | Entry point — the universal loop & how to run it |
| `…/references/sops.md` | Mandatory quality rules (define done, budget, verify, no reward-hacking) |
| `…/references/architectures.md` | Loop-pattern menu + how to choose + execution modes |
| `…/references/state-and-memory.md` | Resumable loop-state file, checkpoints, context hygiene |
| `…/profiles/` | Per-domain config: `roblox-game`, `openscad`, `personal-ai`, `landuse-research`, `_template` |
| `…/templates/loop-state.template.md` | Copy to `.loop/<task>/state.md` to start a run |
| `RESEARCH.md` | Cited research the design is grounded in |
| `CLAUDE.md` | Guidance for Claude Code working in this repo |

## Customize

Copy `profiles/_template.md` to `profiles/<your-domain>.md` and fill in the
ground-truth verify command, default architecture, budget, and guardrails. That's
the whole customization surface — the SOPs and loop engine stay the same.
