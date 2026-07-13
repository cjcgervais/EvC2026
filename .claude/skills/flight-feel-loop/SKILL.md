---
name: flight-feel-loop
description: >-
  The flight-feel tuning loop for Eagles vs Crows — a specialization of evc-loop
  for the mouse-aim instructor, the camera, and the physics-strike ladder. Runs
  ONE gated dial per iteration: propose (flight-controls-architect) → locked-spec
  gate → red-team → implement inert → build → INSTRUMENT capture (step-response
  metrics BEFORE Chad flies) → Chad's playtest verdict → keep-or-revert → ledger.
  Use when working the aim/camera/strike frontier ("fix the rubberband", "next
  flight-feel dial", "tune the strike model", "decouple the camera"), or when a
  feel complaint needs mechanism attribution before anyone touches a gain.
---

# Flight-feel loop — the aim / camera / strike tuning harness

This skill is the operational layer for the flight-feel frontier. It **specializes
`evc-loop`**: every one of that skill's prime directives applies here unchanged — this
skill only narrows the scope, adds the step-response **instrument** as a mechanism-
attribution gate, and carries a pre-validated **roadmap** so each session advances one
flyable stage instead of re-deriving the architecture.

**Read `docs/HANDOFF.md` (COLD START + the LOCKED CS registry) and
`references/roadmap.md` before acting.** The roadmap says which stage is next; the
`flight-controls-architect` subagent says which single dial within it.

## Why this skill exists (the lesson it encodes)
Four sessions (S26–S28) burned three coordinated-flight rewrites that each passed build
**and** red-team and each felt WORSE in Chad's hands. Root cause, now pinned: the
horizontal aim channel damps **roll-rate** (settles bank), not **heading-rate**
(settles the nose) — so it sails past — and a 77 ms in-loop output-ease lags the whole
command. The fix is a *staged* one — but the deeper fix is process: **feel must become a
number (the instrument) so a complaint attributes to a mechanism BEFORE Chad flies**,
and **every structural change ships inert behind a knob whose identity value reproduces
today's behavior**, so "never ship an untested structure" is enforced by construction.

## The prime directives (inherited from evc-loop — never violate)
1. **Protect the LOCKED CONTROL SPECS (CS-1…CS-9).** Grep the registry in
   `docs/HANDOFF.md` before ANY edit; never regress a locked behavior collaterally.
2. **ASK, don't guess on control feel.** A wrong guess that ships is worse than a
   question. (CS-8 is being superseded by Stage 1 — that needs Chad's explicit sign-off
   before Stage 1 flies.)
3. **ONE dial per iteration.** One attributable change; keep the build green.
4. **Ground truth is Chad's Studio Play.** The instrument *informs and attributes* — it
   never certifies feel, never auto-tunes to a number, never overrides his verdict.
5. **flight == balance.** The strike/collision stages change the 1-v-4 — reason about
   the whole fight; anchor every change so today's balance is the identity point.
6. **Refine, don't regenerate.** Add a term, not a new loop. Never touch the kernel.
7. **LOG every dial + instrument row + verdict** into the ledger and the HANDOFF block.

## The loop (one iteration = one dial)
```
ORIENT     → read the ledger tail + HANDOFF frontier + roadmap. State the stage + the
             ONE dial you intend (or the complaint you're attributing).
PROPOSE    → spawn flight-controls-architect. It returns EXACTLY one dial: mechanism
             attribution (file:line), law before→after, the knob + its inert value, a
             NUMERIC predicted instrument signature, the predicted felt change in
             Chad's words, CS interactions, and the revert. If it can't attribute the
             complaint, it returns an instrument capture to run instead — do that.
GATE       → locked-specs gate (check the dial against CS-1…CS-9 + kernel invariants;
             if it touches a locked behavior collaterally, STOP). Then spawn
             red-team-reviewer to attack it. Fix or surface what they find.
IMPLEMENT  → make the ONE change. A structural change MUST ship inert: the knob's
             identity value reproduces today's behavior. Nothing else moves.
VERIFY     → .\build.ps1 (green). Then .\verify.ps1 — judge by NEW findings vs the
             recorded pre-existing baseline (HANDOFF S28d: 18 findings), not exit code.
INSTRUMENT → have Chad capture a BEFORE and AFTER step (F7 lateral / F6 vertical) and
             flush (F9). Compare the AFTER row to the architect's predicted signature.
             A MISMATCH is a finding (the mechanism model is wrong) — NOT a cue to keep
             turning the knob.
CHAD FLIES → hand him a crisp checklist: setup → input → expected → the knob if off.
             ALWAYS re-confirm CS-1 (held key → zero cursor pull) and every touched CS
             row. His verdict is the only certification.
VERDICT    → KEEP (prepare the commit — the harness gates the push on his approval) or
             REVERT (knob → identity, or git checkout the touched block).
LEDGER     → append one row to .loop/flight-feel/results.tsv and one HANDOFF block
             (stage, dial, instrument numbers, Chad's quote, decision, next).
```

## Scope — the guardrails (this is what keeps it safe)
**MAY touch (only these):**
- `src/client/BirdController.client.luau` — only `computeMouseAim`, `updateCamera`, the
  onFlightStep aim-apply block, and the delimited scratch-telemetry / instrument block.
- `src/shared/GameConfig.luau` — only `Controls.aim*`, `Camera.*`, `Combat.strike*`.
- `src/server/GameServer.server.luau` — only the strike / collision block.
- `src/server/_ScratchTele.server.luau`, `.loop/flight-feel/*`, `docs/HANDOFF.md` blocks.

**MUST NOT touch:**
- `src/shared/FlightPhysics.luau` and every kernel invariant (`cl0>0`; auto-level OFF;
  `AIR_DENSITY`↔`GRAVITY` lockstep; stall<spawn<cruise). The kernel is signed-off.
- The keyboard path (`kb`, `rampAxis`, the CS-1 aim gate), the free-look CS-2 branch,
  the bird-profile flight numbers, `BirdCollision`, `Boids`, and the AI-crow path.

## The instrument (mechanism attribution)
F7 = 30° lateral step, F6 = 30° vertical step (the loved channel — a known-good
baseline), F8/F9 = capture/flush (see the scratch block in BirdController). Each step
prints and logs `settle_s, overshoot_deg, reversals, cam_tau_s`. Use it to (a) record a
BEFORE trace every stage, (b) confirm the architect's predicted signature, (c) attribute
any felt complaint to a term before proposing a change. It is a diagnostic aid: Chad's
hands still decide.

## Ledger
`.loop/flight-feel/results.tsv` (create from `templates/ledger.tsv`). One row per dial:
`date  stage  knob  from  to  settle_s  overshoot_deg  reversals  steady_turn_rads
cam_tau_s  signature_match  chad_verdict  decision  commit`. Plus a HANDOFF session
block per iteration so a cleared-context agent inherits the state.

## Failure policy / stop conditions
- The instrument + red-team + build **cannot certify feel** — only Chad's flight can.
- Regression on a dial → REVERT it the same session (knob → identity value).
- Two consecutive reverts on one stage → **STUCK** → stop tuning; put the architect's
  named next-candidates to Chad and let him choose the direction.
- Never weaken a gate to make a change "pass." Never ship a structure Chad hasn't flown.
- Stage 1 (camera decouple) and Stages 9–10 (strike balance) are **Chad-gated** — do
  not fly them without his explicit go (Stage 1 supersedes CS-8's felt behavior).

## Files
- `references/roadmap.md` — the validated staged ladder (Stage 0 instrument → 1 camera
  decouple → 2 heading-rate damp → 3 retire in-loop ease → 4 skid-snap → 5 yaw kick →
  6 gain schedule → 7–9 physics strike → 10 ram band). Each stage: the one change, the
  knob, the instrument signature, the Chad gate, the revert.
- `templates/ledger.tsv` — copy to `.loop/flight-feel/results.tsv`.
- Delegates to: `flight-controls-architect` (PROPOSE) and `red-team-reviewer` (GATE).
- Specializes: `.claude/skills/evc-loop/SKILL.md` (base: `loop_skill/`'s
  `loop-orchestrator`, `roblox-game` profile).
