---
name: master-loop
description: >-
  The autonomous execution harness for docs/MASTER-PLAN.md — the S40 master plan
  that takes Eagles to the Rescue from the Phase-0 slice to a leveled, functioning
  game. Runs the plan packet-by-packet: pick the top unblocked packet, design
  (Fable) where tagged, implement via Opus subagents, red-team, verify with the
  ladder (incl. Tier-4 lune tests once A1 lands), ledger, commit-ready checkpoint,
  loop. Stops at phase gates and anything only Chad can decide. Use to start or
  continue plan execution ("run the master loop", "continue the plan", "next
  packet", "keep building the game"). Supersedes program.md as the outer driver;
  the SOP core is still evc-loop.
---

# Master Loop — execute docs/MASTER-PLAN.md

You are the orchestrator (Fable). **`docs/MASTER-PLAN.md` is the editable source
of truth** — Chad reorders, edits, retags, or `SKIP`s packets freely; re-read it
at the top of EVERY iteration and never cache the queue. This skill layers plan
execution on the evc-loop SOPs; on any conflict, the evc-loop prime directives
win (`.claude/skills/evc-loop/SKILL.md` + its `references/`).

**Goal (one metric):** advance MASTER-PLAN packets to GREEN (ladder-passing,
commit-ready checkpoints), top-down within the current phase, until a STOP fires.

## Orient (every session start)

1. Read `docs/MASTER-PLAN.md` (whole file — it's the program).
2. Read the `docs/HANDOFF.md` COLD START box + the LOCKED CS-1..9 registry.
3. Read the ledger tail: `.loop/rescue-phase0/state.md` (last session block).
4. `git status --short` — the tree must be clean OR every dirty file accounted
   for by the HANDOFF (e.g. a Chad-pending batch). An unexplained diff = STOP
   and surface; never build on it.
5. State the FRAME: current phase, the packet you're taking, done-criteria,
   session budget (default: 3-5 packets or the first STOP).

## Packet selection

- **Current phase** = the first phase (A→B→C→D) whose gate has not been passed.
  A phase's packets may not start until the PREVIOUS phase's gate is recorded
  as passed in the plan/HANDOFF (Gate 0 before A-packets, Gate A before B, …).
  Exception: a packet explicitly marked as its own track (e.g. B7 design consult)
  may run when its own preconditions are met.
- **Pick** = the top packet in the current phase that is not `✅ DONE`, not
  `SKIP`-marked by Chad, and whose stated `Blocked-on:` is satisfied.
- On completion, edit the packet's heading line in MASTER-PLAN.md to append
  `✅ DONE S<n> (<commit-ready|committed>)` — the plan is self-tracking.

## Per-packet iteration

1. **DESIGN** — parse the packet's `[model: … | gate: …]` tag:
   - `fable designs …` → spawn `rescue-gameplay-architect` (`model: fable`) with
     the packet text + relevant code; it returns the module API / design spec
     (the S37 "before" bracket). For control-adjacent work use
     `flight-controls-architect` instead.
   - plain `opus` → skip design; the packet text IS the spec.
2. **LOCKED-SPEC GATE** — if the packet comes anywhere near controls/camera/
   input/kernel: run `references/locked-specs-gate.md` (evc-loop). If a locked
   behavior would move → STOP and ASK Chad.
3. **IMPLEMENT** — spawn implementation subagent(s) with `model` from the tag
   (default **opus**; never silently upgrade to fable — Chad's token policy).
   The prompt = the packet verbatim + the design spec + acceptance criteria +
   file anchors + "refine, don't regenerate; all Luau starts `--!nonstrict`;
   report what you changed with file:line". One packet may fan out to parallel
   Opus agents ONLY for independent files (e.g. module + its spec files).
4. **RED-TEAM** — spawn `red-team-reviewer` when the packet touches server
   authority, scoring/balance, round flow, or anything control-adjacent; a
   documented self-red-team suffices for pure-cosmetic/docs/tooling packets.
   For `fable designs` packets, close the bracket: a Fable "after" audit
   (`rescue-gameplay-architect`, `model: fable`) checks faithfulness to spec.
   Fix every BLOCK; fix or explicitly defer every REVISE (reason in the ledger).
5. **VERIFY** — run `.\verify.ps1`. PASS = rojo-build PASS + **0 NEW** luau-lsp
   findings vs the documented baseline (judge by new findings, never exit code;
   selene 404 = UNAVAILABLE, fine). Once packet A1 lands, Tier 4 (`lune run
   tests/`) must ALSO exit 0 — and every `gate: tests`/`tests+SIM` packet must
   ship its spec files in the same checkpoint. A Tier-5 bug later found in Play
   that Tier 4 could have caught → write the failing test FIRST, then fix.
6. **LEDGER** — append to `.loop/rescue-phase0/state.md` under the session
   block: `## ✅ <packet-id> — <title>` with What/why · Change (files:lines) ·
   Design/red-team verdicts · Verify (tiers) · DECIDE · any Tier-5 items pushed
   to the phase-gate checklist.
7. **CHECKPOINT** — stage a commit-ready state + a 2-line message. **git
   commit/push stay ASK-gated — never commit unbidden.** One packet = one
   cohesive checkpoint (A2 may split per its stated commit plan).
8. **DECIDE** — STOP condition fired? If not → next packet (step: re-read
   MASTER-PLAN.md first).

## Feel batching (Tier 5)

Cosmetic/presentation packets are NOT per-item Play gates (the S39
ANIMATION-BATCH rule, generalized). Accumulate every "only Studio can judge
this" item into **one playtest checklist per phase gate**, kept at the top of
the current ledger session block. At the gate: STOP, present the checklist +
what changed since Chad's last flight, and wait.

## STOP conditions (check every DECIDE)

- **PHASE GATE** — next packet is in a gated-off phase, or the phase is done →
  present the batched checklist (Gate 0 / A / B / C per plan §8) and stop.
- **CHAD-DECISION** — the packet's gate says CHAD / design approval (e.g. B7
  touch input) → run the consult, present options, stop. Never decide feel or
  LOCKED-spec questions autonomously.
- **LOCKED-SPEC RISK** — can't build the packet without moving CS-1..9 or the
  kernel/camera/aim law → stop and ask.
- **STUCK** — same verify failure twice, or a red-team BLOCK you can't fix →
  revert to the last checkpoint, log, stop or re-strategize.
- **DIRTY TREE** it can't account for from HANDOFF → stop and surface.
- **BUDGET** — session FRAME exhausted → stop, report best.

On ANY stop: tree green, ledger + HANDOFF COLD-START refreshed (one `### ▶ S<n>`
block), commits prepared but un-landed, memory updated per
`references/memory-and-handoff.md`, and a one-glance "ready for Chad" summary.

## Failure policy

Verify red / new finding → fix trivially or revert the packet; never leave the
tree red. Subagent returns garbage → re-prompt once with the failure quoted;
twice → do it yourself (Fable) and note the token cost in the ledger. Crash or
ambiguous intent → ask, don't guess. Git is the undo button: checkpoint before
risky edits; each commit green on its own.
