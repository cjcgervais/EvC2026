# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo **is a Claude Code Skill** (plus its research basis), not an application.
It delivers `loop-orchestrator`: a universal, customizable harness for running
disciplined **agentic loops** — iterate on a goal until it meets explicit,
externally-verified criteria or a budget is hit. There is no build/test toolchain;
the "product" is Markdown that Claude loads and follows.

- `RESEARCH.md` — the cited evidence base (Agent SDK canonical loop, evaluator-
  optimizer, Reflexion, LATS tree search, multi-agent orchestration, Claude Code
  hooks as deterministic gates). Verification is **complete**: 25/25 verified
  claims confirmed (mostly unanimous 3-0), all primary-source-backed. **Two
  sub-topics are reasoned design, not cited findings** — anti-reward-hacking
  (SOP-7) and per-domain profile structure — flagged in the doc's Open Questions.
  Keep `RESEARCH.md` and the skill in sync: a design change should cite a source.
  Note the doc's time-sensitivity caveat — hook/SDK field names are tied to Claude
  Code v2.1.x and should be re-confirmed before relying on exact names.
- `readme.md.txt` — the user's original goal note (kept for provenance).

## Architecture (read this before editing the skill)

The skill lives at `.claude/skills/loop-orchestrator/` and is built around two
ideas that must be preserved when editing:

1. **Progressive disclosure.** `SKILL.md` is the always-considered entry point and
   is kept lean (target < ~5k tokens). Depth lives in files loaded *on demand*:
   `references/` (how), `profiles/` (domain config), `templates/` (the state file).
   When adding detail, put it in a reference/profile file and link it from
   `SKILL.md` — do **not** inflate `SKILL.md` itself. The `description` frontmatter
   is what triggers the skill, so it must name both *what* it does and *when* to use it.

2. **SOP / architecture / profile separation of concerns:**
   - `references/sops.md` — the **mandatory rules** (the quality contract). SOP-1
     (define done), SOP-2 (budget), SOP-3 (external ground-truth verify), and
     SOP-7 (verifier independent of optimizer; never weaken criteria/tests to pass)
     are load-bearing and must not be relaxed by any profile.
   - `references/architectures.md` — the **menu** of loop shapes (iterative
     refinement → evaluator-optimizer → Reflexion → ReAct → tree-of-thoughts →
     orchestrator-worker) and how to choose + how to run (interactive, `/loop`,
     scheduled, hooks, subagents).
   - `references/state-and-memory.md` — the **on-disk loop-state file** is the
     single source of truth (resumability + context hygiene). Runtime state goes
     in `.loop/<task-slug>/` (gitignored), created from `templates/loop-state.template.md`.
   - `profiles/*.md` — per-domain customization (ground-truth command, default
     architecture, budget, guardrails) for the user's four domains: `roblox-game`,
     `openscad`, `personal-ai`, `landuse-research`, plus `_template.md`.

The universal loop every run follows: **FRAME → PLAN → ACT → VERIFY → SCORE →
REFLECT → DECIDE**, with the four stop conditions CONVERGED / DIMINISHING /
BUDGET / STUCK.

## How to extend

- **Add a domain profile:** copy `profiles/_template.md` to
  `profiles/<domain>.md`. The only hard requirement is a concrete **ground-truth
  verify command** (SOP-3) and a **budget** (SOP-2); everything else has defaults.
- **Change loop behavior:** edit the relevant `references/` file, then update the
  one-line pointers in `SKILL.md` and, if the rationale changed, the cited claim in
  `RESEARCH.md`.
- **Validate `SKILL.md` frontmatter:** `name` must be lowercase/numbers/hyphens,
  ≤64 chars, and contain neither "anthropic" nor "claude"; `description` non-empty,
  ≤1024 chars. Breaking these stops the skill from loading.

## Using the skill

- **In this repo:** it's auto-discovered as a project skill. Trigger it by asking to
  iterate/improve/optimize something until it meets criteria.
- **Install globally:** copy `.claude/skills/loop-orchestrator/` to
  `~/.claude/skills/loop-orchestrator/` to use it across all projects.
- **It composes with built-in skills**, by design: `deep-research` (the search/
  verify fan-out used by the research and land-use profiles), `/loop` (paced
  reinvocation), and `schedule` (unattended cron runs). Prefer composing these over
  reimplementing them.

## Environment

Windows; PowerShell is the primary shell (a Bash tool is also available — each
needs its own syntax). Not a git repository yet — `git init` before expecting
version control or commit-based checkpoints (SOP-5).
