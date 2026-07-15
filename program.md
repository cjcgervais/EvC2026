# program.md — Eagles to the Rescue: autonomous build loop

> **Launch prompt:** `Hi, have a look at program.md and let's continue the rescue build.`

This is the autonomous driver for the RESCUE Phase-0 queue. It runs the **`/evc-loop`**
SOP unattended, one queue item at a time, keeping the build green and the LOCKED
control specs untouched — and it **stops the moment it reaches something only Chad's
Play can judge.** Feel is not self-certifiable here; that boundary is the whole point
of this loop, not a limitation of it.

It does not replace `/evc-loop` — it *drives* it. Every iteration obeys the evc-loop
prime directives (`.claude/skills/evc-loop/SKILL.md`). This file is the outer loop:
what to build next, when to keep it, when to stop.

---

## Goal (one metric)

Advance the **RESCUE Phase-0 QUEUE** (`docs/HANDOFF.md` COLD START box) one gated
change per iteration, until the queue's **autonomously-buildable** items are exhausted
or an item hits a **FUN/feel gate** that needs Chad's Studio Play.

**A change is KEPT only if, after it:**
1. `.\verify.ps1` → **rojo-build PASS** and **ZERO NEW** `luau-lsp` findings vs the
   documented baseline (judge by *new findings*, never the exit code — the baseline
   exits 1; selene 404 = UNAVAILABLE, not a failure). See `references/verify-ladder.md`.
2. **CS-1…CS-9 are byte-untouched** (the LOCKED control specs — registry in `HANDOFF.md`).
3. It is **ONE** cohesive change with a **commit-ready checkpoint** logged to the ledger.

Otherwise: fix trivially or **revert** (git is the undo button) and log why.

---

## Setup (run once at the start of a session)

1. **Orient** (read in order, every cold start):
   - `docs/HANDOFF.md` COLD START box — current state + the **RESCUE PHASE-0 QUEUE**.
   - The **LOCKED CONTROL SPECS** registry (CS-1…CS-9) in `docs/HANDOFF.md`.
   - `CLAUDE.md` (architecture + contracts) · `MEMORY.md` index · the ledger
     `.loop/rescue-phase0/state.md` (the running session log).
   - `docs/EAGLES-TO-THE-RESCUE-plan.md` (creative bible) +
     `docs/rescue-consults/PACKET-03-growing-crew.md` (the sequenced roadmap for #14/#15).
2. **Branch:** work on **`updraft`** (no `auto/` branch — the project commits queue items
   directly, ASK-gated). Confirm a clean tree (`git status --short`). If dirty, stop and
   surface it — do not build on an unexpected diff.
3. **Ledger:** the ledger already exists at `.loop/rescue-phase0/state.md`. Append a new
   `# Session S<n>` block; do not start a fresh file.
4. **State the FRAME** for this session: which queue item(s) you're taking, done-criteria,
   and a budget (e.g. "3–4 iterations, stop on 2 no-improvement or the first FUN gate").

**The queue, in order (top-down):**
- **#14 MUSIC ESCALATION** (Packet-03 slice 3, *autonomous*) — layered stems crossfaded on
  `delivered + carry` progress-to-ten; crew chatter scales with crew size; **includes the
  `SFX_SWOOSH` replacement** (`rbxasset://sounds/swoosh.wav` = "Asset is not approved" ×70 —
  pomf/hup/whip are half-silent; find an approved id).
- **#15 MISSION FRAMEWORK + THE FOX** (Packet-03 slice 4) — build the framework autonomously;
  **the fox-pressure routing FUN is Chad-gated → STOP at that boundary.**
- **Cosmetic follow-up:** sticky per-rider seats (red-team **F3** one-seat pop when a crew
  catch lands during a sacred slow-mo climb).
- Then: feel-knob VALUES gated on Chad's Play, and the **#GATE** §E report-back → Fable Packet-04.

---

## Rules

**CAN touch** (everything is built *around* the LOCKED kernel):
- `src/server/RescueServer.server.luau` — world-gen, scoring, round flow, rescue remotes.
- `src/shared/GameConfig.luau` → the **`Rescue`** table (tunables) and rescue-only keys.
- `src/client/BirdController.client.luau` — the **rescue section only** (detection, catch
  presentation, riders, deliver, style meter, audio hooks).
- `src/client/GameUI.client.luau` — the **rescue HUD** (timer/score/carry/stamps).
- `src/shared/BirdBuilder.luau` — squirrel build + poses.
- New modules / audio assets that hook the above at documented seams.

**CANNOT touch** (grep the CS registry before ANY edit that comes near these):
- `FlightPhysics.luau` (the aero kernel), the **camera LAW**, the **aim law**.
- Any **CS-1…CS-9** behavior — never *collaterally* while building something else.
- Combat balance / the 1-v-4 levers (combat is SHELVED; do not drift back to it).

**Simplicity criterion:** prefer the change that adds the least — reuse the built substrate
(the S31 proximity scorer, Thermals, the squad/formation tech, the living-rider system, the
feather/tumble FX, SpatialHash). A change that deletes or reuses beats a change that adds.

**Invariant guardrails (from the SessionStart order — do not violate):**
- Eagle flight/control/camera feel + the flight KERNEL are **SIGNED OFF + LOCKED**. Rescue is
  built around them (triggers · presentation · world · meta), NEVER in the kernel/camera/aim law.
- **ONE change per iteration.** Keep the build green. Checkpoint before any kernel-adjacent edit.
- Every rescue step must clear the **kid-FLOOR** (a 5-yo succeeds) AND the **skill-CEILING**
  (a 15-yo shines) in the SAME mechanic. **Non-lethal always** (P3).
- The **Fable consult packet per turn** (`docs/rescue-consults/`) is the standing method for
  design-heavy items — spawn `rescue-gameplay-architect` (design attribution) before building
  a new mechanic; it reports, it never edits.

---

## The loop (one queue item per pass)

1. **PICK** the next buildable queue item (top of the queue that isn't blocked on Chad's Play).
   If the *only* remaining items are FUN-gated → go to **STOP**.
2. **DESIGN** — for a new mechanic, spawn **`rescue-gameplay-architect`** with the current code
   + the bible/Packet-03 to get the single next build-or-tune step (what to build, where it hooks
   `file:line`, the pillar it serves, kid-floor/kernel-safety, the predicted felt result, the
   revert). For a small tune, skip to 3.
3. **LOCKED-SPEC GATE** — if the change comes anywhere near controls/camera/input/kernel, grep the
   CS-1…CS-9 registry and confirm no locked behavior moves. If it must touch one → **STOP and ASK**.
4. **BUILD** the ONE change. Refine the module; do not regenerate. All Luau starts `--!nonstrict`.
5. **RED-TEAM** — spawn **`red-team-reviewer`** for anything touching control/camera/kernel/combat/
   balance, or a new server-authority path. For client-presentation-only edits, a self-red-team
   (documented in the ledger, the S33+ pattern) is sufficient. **Fix or surface every BLOCK/REVISE.**
6. **VERIFY** — run:
   ```
   .\verify.ps1
   ```
   PASS = **rojo-build PASS** + **0 NEW luau-lsp findings** vs the documented baseline
   (`GameConfig:48 m`, `BirdController cameraState` keys, the `vp` line that shifts with added
   lines). selene UNAVAILABLE (404) is expected, not a failure. If a NEW finding or a build break
   appears → fix it or revert this iteration.
7. **LOG** — append an iteration entry to `.loop/rescue-phase0/state.md`: what/why (+ the Packet-03
   / Chad citation), the change (files touched), the red-team verdict + fixes, the verify result,
   and a **DECIDE** line. Write a crisp **Chad playtest checklist** for whatever only Studio can judge.
8. **CHECKPOINT** — the change is a commit-ready checkpoint. **git commit/push stay ASK-gated** — the
   PreToolUse hook makes them ask Chad. Prepare the commit + a 2-line message; do not commit unbidden.
9. **DECIDE** — `CONVERGED` (buildable half done) | `DIMINISHING` | `BUDGET` | `STUCK` | `FUN-GATE`.
   If none fire → loop to 1. Else → **STOP**.

---

## Logging (reuse the project's real ledger — do NOT invent a TSV)

- **Ledger:** `.loop/rescue-phase0/state.md` — one iteration entry per change, in the established
  format (see any `## ✅ Iteration N` / `## ✅ #NN` block). Fields: **What/why · Change (files) ·
  Red-team · Verify · DECIDE · Playtest checklist.**
- **HANDOFF:** at session close, append a `### ▶ S<n>` block to the COLD START box in
  `docs/HANDOFF.md`, refresh the queue (mark items `[DONE S<n>]`), and update the frontier "NEXT".
- **Memory:** update `project-rescue-phase0.md` + its `MEMORY.md` index line so a cleared-context
  agent inherits the true state. → `.claude/skills/evc-loop/references/memory-and-handoff.md`.

Every kept iteration writes one ledger entry; every session writes one HANDOFF block. That is the
audit trail — a fresh agent must be able to cold-start from it and continue.

---

## STOP conditions (this loop's discipline is knowing when to hand off)

Unlike an autoresearch loop, this one **must not run forever** — feel is Chad's to certify. Stop and
report the moment ANY of these fires:

- **FUN-GATE** — the next item's payoff is *fun/feel/readability* (e.g. "does the fox routing feel
  fun?", a Chad-gated feel knob like `slowmoScale`, the **#GATE** §E report-back). Build the
  buildable substrate, then **STOP and write the playtest checklist.** Never self-certify FUN.
- **LOCKED-SPEC RISK** — a change cannot be made without touching CS-1…CS-9 or the kernel/camera/aim
  law. **STOP and ASK Chad** — do not guess on control feel.
- **QUEUE EXHAUSTED** — every remaining item is FUN-gated or needs Chad. Close the session.
- **STUCK / REGRESSING** — same verify failure twice, or worse than the last checkpoint → revert to
  the checkpoint, change strategy, or ask.
- **BUDGET** — hit the session's iteration/cost budget → stop, report best.

On any stop: leave the tree **build-green**, the ledger + HANDOFF current, commits **prepared but
ASK-gated**, and a one-glance summary of what's ready for Chad's Play.

## Failure policy

- **Verify red / new finding** → fix trivially (broken require, renamed contract, nil field) or
  **revert this iteration** and log it. Never leave the tree red.
- **Red-team BLOCK** → fix before proceeding. **REVISE** → address or explicitly defer with a reason
  in the ledger.
- **Crash / ambiguity in intent** → stop and ask, don't guess (prime directive #2).
- **git** → never commit or push unbidden; the hook gates it to Chad's approval. One commit per
  cohesive checkpoint; each commit must be green on its own (client falls back via `or` defaults if a
  config-only commit is reverted — the S33/S35 split pattern).
