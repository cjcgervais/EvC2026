# CONSULT — Re-cut the master-loop strategy for a QUALITY BUILD (a real map)

> **Audience: a Fable strategy session.** **Deliverable (Chad, S48, 2026-07-22):** revise the
> **master-loop SKILL strategy** so it **sets our heading toward a quality build and MAINTAINS
> it** — the loop must never again spend a session polishing a rejected asset. Fable's output
> is (1) a revised `.claude/skills/master-loop/SKILL.md` strategy (and any `docs/MASTER-PLAN.md`
> Phase-V re-sequence it implies), and (2) a clean fresh-context **HANDOFF cold-start** that
> points the next Opus grind session at building the *real* map first.
>
> **How to run this:** next session → `/model` **Fable**, then work this consult. Fable produces
> the strategy + handoff; Opus/Sonnet then execute it. (Per execution-model v2: Fable owns
> strategy and plan surgery.)

---

## 1. The trigger (Chad, verbatim, S48)

Mid-loop, on the driver picking packet **V0 (kill the z-fighting on the current map)**:

> *"I want us to start the map to make it nice, like a really map. So far you have got that ugly
> map to stop flashing but **why are we fixing a rejected asset?** I want a plan for a better
> map."*

and:

> *"The master loop should not have said to fix the current map's flashing as I was clear I want
> a new strategy."*

He then halted and asked for a fresh context + this consult.

## 2. What actually happened

Phase V was ACTIVE. The loop, following the plan top-down, correctly picked **V0** — the plan
explicitly front-loads it ("Chad already judged the flashing, so it's falsified, not unjudged;
fix it now, it's 3 lines"). The driver built it cleanly (per-band planes + a 2×2 parity offset,
teeth-first pairwise gate, Tier-4 208/208, source-gates against false-green) and it worked — the
meadow stopped flashing.

**And that is exactly the problem.** The map it was making non-flashing is the flat-primitive
gray box Chad has already rejected wholesale. The loop did a technically clean job on the wrong
target. **V0 has been reverted** (uncommitted; full description preserved in the S48 ledger block
and git reflog). The tree is back at the committed baseline.

## 3. The diagnosis — why the strategy produced this

The current Phase-V order is **V0 z-fight → V1 WorldGen extraction → V2 screenshot harness → V3
look-dev slice → …**. Three observations:

1. **The heading is buried three packets deep.** Nothing the player would call "a nicer map"
   happens until **V3**. V0/V1/V2 are all *plumbing* — z-fight cleanup on the doomed geometry,
   a pure-module extraction (for testability/dedup), and a screenshot harness (to save Chad's
   flights). All real value, **none of it makes the map look better**, and the first two invest
   directly in geometry we are about to delete.
2. **The loop optimizes "advance the top unblocked packet to GREEN," not "advance the heading."**
   Its one metric is packets-to-green within the current phase. That metric cannot tell the
   difference between a packet that moves us toward a quality build and one that polishes a
   reject — both go green. This is the second time the *method* has produced motion on a doomed
   asset (S46 was the first: "fighting mediocrity rather than testing something competitive").
3. **This is a recurrence of the S47 rationale, not applied to itself.** MASTER-PLAN §5.5 note #5
   already parks "renders in slow" because *"the world that's slow to draw is the world V3/V4
   replaces wholesale."* The **same logic damns V0 and V1**, and the strategy didn't catch it.

## 4. The heading Chad wants

**Build a real, quality map — first, and visibly.** In Roblox terms the levers that actually make
a map read as *a real map*, and their cost/blockers:

- **Roblox Terrain** — sculpted, painted ground + real water instead of flat tinted planes. The
  single biggest lever. **Buildable in code today, zero assets** (`Terrain:FillBlock`/`FillRegion`
  /`PaintRegion`, water material). *(Note: Terrain is a different replication/collision system —
  the swept-sphere `BirdCollision` has `IgnoreWater=true`, so terrain water is invisible to it;
  the −40 deep-failsafe P3 risk from MASTER-PLAN §V4-② applies from day one, not just at V4.)*
- **A sky / atmosphere / lighting rig** — golden sun, `Atmosphere` haze for aerial depth, a real
  skybox, subtle bloom/color-grade. **Code today, zero assets.**
- **3D mesh props** (Synty-style low-poly trees/rocks/set pieces) — the one input that needs
  **Chad**: mesh packs cannot be conjured headlessly. Everything else can be built first and have
  meshes dropped in later.

So the fastest route to "nice" is a Terrain valley + lighting rig now (a large visual jump with
no assets), meshes folded in once sourced.

## 5. Open decisions for Fable to resolve or surface (do NOT hand Chad homework — decide-with-a-recommendation, or fold into the strategy)

- **D1 — Art source.** (a) Terrain + code now, meshes later [starts immediately, unblocked];
  (b) Chad provides mesh packs (`assets/` — currently holds only audio) before mesh work;
  (c) pull free creator-store assets by ID [needs Chad's OK; licensing/quality varies].
- **D2 — How we iterate the look without burning Chad's flights.** (a) Stand up the screenshot
  "eyes" (the V2 harness — the Smoke-Boot sentinel pattern already exists) so Fable can image-audit
  the map to good *before* Chad flies; (b) build the slice and Chad judges in Studio. Note: the
  whole S47 case for image gates was *not burning Chad's flights* — dropping the eyes trades his
  time for speed-to-first-look.
- **D3 — What happens to the V1 extraction / V2 harness plumbing.** Keep, defer, or fold into the
  map build? (Extraction has genuine anti-bug-multiplication value but isn't on the critical path
  to "nice.")
- **D4 — Region-first order.** The bible is a forest-fire rescue valley; which slice is the
  look-dev target and how does the ratified look roll out (the old V3→Gate V-LOOK→V4 shape, or a
  new one)?

## 6. Constraints Fable must honor (unchanged invariants)

- Kernel / controls / camera / aim law LOCKED (CS-1..CS-9). The map is built AROUND them; the
  ground **datum** (spawn Y, `deliverPadY=250`, perch band, thermal ring, fire annulus,
  anti-cheat, crash numbers) is tuned to the current plane — relief must respect it (MASTER-PLAN
  §V4-①).
- Non-lethal always (P3) — see the terrain-water/−40 failsafe note in §4.
- `docs/VISUAL-QUALITY-BAR.md` is the gate document ("built to publish"); the honesty rule stands
  (every report says which halves were verified — LOGIC/APPEARANCE/FEEL; "green" alone is banned).
- The asset-ID problem is real and recurring (the S43 roar tombstone) — any strategy that depends
  on asset IDs must name how they're verified/sourced, not assume them.
- One-change-at-a-time remains law for kernel/logic; art passes may batch (the S47 finding).

## 7. Expected output from Fable

1. **Revised `master-loop` strategy** — an amended SKILL that makes "are we advancing the quality
   heading?" a first-class gate on packet selection (so the loop cannot again grind a rejected
   asset to green), and states the heading + how it is maintained across context clears.
2. **Any MASTER-PLAN Phase-V re-sequence** the above implies (e.g. what happens to V0/V1/V2 vs a
   pulled-forward Terrain look-dev slice).
3. **A fresh-context HANDOFF cold-start** that a new Opus session can execute without re-deriving
   any of this — with D1/D2 either decided (with rationale) or teed up as the single first
   Chad-decision, batched with a recommendation.

## 8. Pointers

- `docs/MASTER-PLAN.md` §5.5 (Phase V) + §8 (execution model v2) — the strategy under revision.
- `docs/CONSULT-VISUAL-QUALITY.md` — the S47 quality consult that created Phase V (context).
- `docs/VISUAL-QUALITY-BAR.md` — the gate document.
- `.loop/rescue-phase0/state.md` — S48 ledger block has the full V0 build+revert record.
- The map builders live in `GameServer.server.luau` (`BuildMap`, `SetupLighting`) and
  `RescueServer.server.luau` (waterfall/pad/trees) — flat primitives today, zero MeshParts/Terrain.
