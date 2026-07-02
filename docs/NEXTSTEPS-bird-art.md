# NEXTSTEPS — Bird Art / Model Work (handoff)

**Date:** 2026-07-01 · **Scope:** the visual bird models (Eagle + Crows) and their wing animation.
**Owner memory:** `C:\Users\Chad\.claude\projects\D--EvC2026-Art\memory\bird-art-pipeline-decision.md` (read it — it has the full decision log).
**Concept art:** `D:\EvC2026_Art\*.png` (Gemini sheets: bald eagle, crow, spec).

---

## TL;DR for the next agent

The procedural bird models were pushed to their **procedural ceiling**, the eagle was **re-proportioned from verified raptor research**, a **5-agent red-team audit** was run and its fixes applied (including a real latent rig bug), and **remote wing replication was fixed**. **None of it has been Play-tested in Studio yet** — that is the #1 next action. Everything is cosmetic/animation only; no gameplay/balance numbers were touched.

---

## Session 2 update (2026-07-01) — cosmetic eagle upgrade (flight untouched)

Five graceful, **physics-safe** eagle additions in `BirdBuilder.luau`, grounded in a fresh verified deep-research brief. Verified first that `FlightPhysics` derives `isDiving` from orientation only and reads **no** wing/feather geometry, so every change below (including the dive *pose*) is cosmetic.

1. **Full-length swept wingtips** — `primaryLen` r×1.05→**r×1.34**, `fingerFan` 20°→**26°**, new `primaryTaper`=0.045 so the outer primary "fingers" stay full and form a swept point. Leading edge stays straight (the soaring plank).
2. **Swept-V dive pose** in `AnimateWings` (both local + remote call it) — old `-DIVE_SWEEP` droop replaced by `DIVE_ANHEDRAL`=20° (tip drop) **+** `DIVE_SWEEPBACK`=42° aft yaw (about the joint Y axis, sign `-side*sweep`). The swept-V is the DIVE, not the static mesh (research: eagle = broad-winged glide-dive, not a peregrine tuck).
3. **Fuller fan tail** — rectrices 5→**9**, spread 56°→**78°**, `wedgeBias` 0.7→0.5 (rounded-wedge), new `rectWidth` overlap, wider slab.
4. **Curved raptor beak** — box+hook replaced by a segment chain hung below a smooth **culmen** line (straight over basal ⅔ then curving down), a near-vertical overhanging **hook**, and a **lower mandible** it overhangs (deep "hatchet").
5. **Longer two-segment legs** for the future talon-strike rig — feathered thigh + bare **tarsus** (≈2× prior length), foot = 3 splayed **toes** + rear **hallux**, held in a ready forward tuck. No joints yet (Path-A adds them).

Rig contract fully intact (Body / `LeftWing`·`RightWing` / `*WingJoint` / `FlapSign` / C0-C1 untouched); all new parts massless, no-collide/query, shadowless. ~54 parts/eagle. **Still Studio-unvalidated** — Play-test knobs: `primaryLen`, `fingerFan`, `DIVE_SWEEPBACK`, `DIVE_ANHEDRAL`, `rectrices`, `rectSpread`, `thighLen`/`tarsusLen`, and the `beakSpec` table. If the diving wings clip the tail too hard, drop `DIVE_SWEEPBACK`; if legs dangle too far, trim `tarsusLen`.

## The plan this work sits in

- **Staged B → A.** Path B (now): high-quality visuals on the EXISTING 5-part Motor6D rig — drop-in, zero physics change. Path A (later): upgrade the **hero eagle** to a skinned mesh + baked talon-strike/death anims; the 4 crows stay on the cheap rig (they die by ramming).
- **Blender/DCC deferred.** Blender + `uv` + blender-mcp are NOT installed (Python 3.11 is). We stayed pure-procedural in Luau so it ships in Studio today. Tier 3 (real MeshPart + 1024² PBR texture) is the next big visual jump and needs the toolchain.

## The rig contract — DO NOT BREAK (everything above depends on it)

- PrimaryPart named **`Body`** = the ONLY massed + collidable part (the suicide-ramming collider). Everything else is `Massless`, `CanCollide=false`, `CanQuery=false`, welded.
- Wings are the two `Motor6D` joints **`LeftWingJoint`/`RightWingJoint`** (Part0=Body), each with a `FlapSign` attribute. `BirdBuilder.AnimateWings` rotates ONLY those two joints. Feathers are welded to the moving wing part (`LeftWing`/`RightWing`) so they flap for free.
- The client's wingtip vortex trail (`BirdController.buildVortexTrails`) looks up `LeftWing`/`RightWing` by name and reads `wing.Size.X` — keep those names.
- **`bodyRadius` (r) is a BALANCE number** (feeds FlightPhysics/collision). Never change it for looks — scale cosmetics off it instead.

---

## What was done (files touched)

### `src/shared/BirdBuilder.luau` — the model geometry
1. **Tier-2 procedural detail:** chest ball + wedge rump + eagle pale neck (streamlining); hooked beak (wedge tip); eyes; wedge **brow-ridge scowl**; wing **coverts** + fanned individual **primary "finger" feathers**; fanned **tail rectrices**; legs + talons. ~31–39 parts/bird, all massless welds; still only 2 Motor6Ds animate.
2. **Eagle re-proportioned from verified deep-research** (Cornell/raptor-ID; see "Research findings" below): `innerSpan` r×1.15→**r×1.6** (wider plank), `primaryCount` 4→**6** finger-slots, `primarySplay` 9°→**2°** (wings held DEAD FLAT — the key eagle-vs-vulture cue), `baseSweep` 18°→10° + new `fingerFan` 20°, wedge tail via center-longest rectrices (`wedgeBias`), longer sleeker rump. Cosmetic wingspan ≈ **2.85× body length**.
3. **Red-team fixes applied** (see audit summary below):
   - 🔴 **`motor.C1` inversion fixed** (latent, pre-existing bug): `rootOffset:ToObjectSpace(wingLocal)` → **`wingLocal:ToObjectSpace(rootOffset)`**. The old value placed each wing ~`innerSpan` *inward*, crossing through the body. Confirmed by 3 independent derivations. Cosmetic (wings massless).
   - 🔴 **WedgePart orientation fixed:** the true convention is tall face at **+Z**, knife at −Z (my comments had it backwards). **Rump** and **Brow** wedges each got a 180° Y yaw so they taper the right way.
   - **Perf:** `CastShadow=false` on all cosmetic parts (in `applyBirdDefaults`); Body keeps one grounding shadow. Crow eye `Glass`→`SmoothPlastic`.
   - **Art/ornithology:** darker eagle body/wings for white-head contrast; pale-yellow Neon iris (not sci-fi gold) + **black pupil**; **yellow feet + black claws** (split `talonColor`/`clawColor`); crow cool-cast black + purple-blue covert sheen + dark eye w/ Neon catchlight; rectrices lifted onto the tail slab.

### `src/client/BirdController.client.luau` — remote wing animation
- **New `animateOtherBirds(dt)`** pass on RenderStepped: animates every bird in `Workspace.Birds` EXCEPT the locally-flown one (that one keeps exact engine state in `onFlightStep`). Derives state from **replicated** motion — `isDiving` is EXACT (`body.CFrame.LookVector.Y < -0.2`, same rule FlightPhysics uses), `isFlapping` is a cosmetic guess (`not diving and (velY>2 or speed<55)`), `flapPhase` advanced locally per-model (weak table) at ~2/~8 rad/s. Render loop now calls `onFlightStep(dt)` then `animateOtherBirds(dt)`.

### `src/server/GameServer.server.luau` — dead-code removal
- Removed the server-side `BirdBuilder.AnimateWings(...)` call (~line 1527). `Motor6D.Transform` doesn't replicate, so it was invisible to all clients — pure wasted CPU. Clients now animate all AI crows locally. (`BirdBuilder` require stays; still used for `Build`.)

---

## ⚠️ #1 NEXT ACTION — Play-test (nothing here is validated yet)

There is no compiler/linter and Roblox isn't headless — **the only real validation is pressing Play in Studio.**

```powershell
cd D:\EvC2026 ; .\serve.ps1     # then connect the Rojo plugin and press Play
```

Check specifically:
1. **Wings sit correctly** (out to the sides, not crossed through the body) — this validates the `motor.C1` fix. **If wings look crossed/inward, the C1 fix was wrong for this engine build → revert that one line.** (Math says it's right; verify visually.)
2. **Rump tapers into the tail** and **brow juts over the eyes** (not a blunt wall / inverted) — validates the WedgePart 180° yaws. If either is wrong, remove that part's `CFrame.Angles(0, math.rad(180), 0)`.
3. **Eagle reads majestic:** wide flat plank wings, 6 spread fingertips, wedge tail, pale eye with a pupil, white head popping against the dark body.
4. **Remote flapping:** best tested with **2 players** (Studio → Test → Clients & Servers = 2). Confirm the AI crows flap/tuck/glide, and a second player's bird flaps on your screen. Solo: the 3 AI crows you aren't flying should animate.

---

## Deferred / next steps (priority order)

1. **Play-test + tune** (above). All the eagle knobs are single-line constants in `BirdBuilder.luau`: `innerSpan`, `primaryCount`, `fingerFan`, `primarySplay`, `baseSweep`, `wedgeBias`. Nudge to taste after seeing it.
2. **Art additions gated on the Play-test** (deferred because they depend on the now-corrected WedgePart convention — confirm the rump/brow look right FIRST): beak-as-wedge (raptor culmen), `CornerWedgePart` swept wing leading-edge tips. Both were proposed by the art red-team; skipped to avoid gambling on unseen geometry.
3. **LOD for AI/swarm birds** — add an optional `lite`/`detail` flag to `BirdBuilder.Build(teamName, profile, lite)` that skips feather fans/coverts/eyes/legs (Body+Head+Beak+2 wings ≈ 7 parts) for non-hero birds; pass `lite=true` from `GameServer` spawn for AI crows. ~4× part-count cut on background birds, zero gameplay impact. (Real bird count is ~5, so this is polish, not urgent.)
4. **Frame-rate-independent flap smoothing** — in `AnimateWings`, replace `alpha = clamp(dt*SMOOTH,0,1)` with `alpha = 1 - math.exp(-SMOOTH*dt)` (the repo already uses this form in `BirdController`).
5. **Minor:** the vortex trail attaches to the inner-wing part, so it emits slightly inboard of the true (welded feather) wingtip — one-line client tweak if it bugs anyone.
6. **Tier 3 (the real leap) — stand up Blender when ready.** Install Blender 4.x + `uv` + `blender-mcp` (register in Claude `mcpServers`), then sculpt one MeshPart + 1024² PBR texture per bird ON the existing rig (Path B). Must satisfy the **Asset contract** in the memory file (PrimaryPart `Body`, −Z forward, bbox ∝ `bodyRadius`, wing joints `LeftWingJoint`/`RightWingJoint` + `FlapSign`, ≤1024² maps, tri budget + an LOD, glow eyes as Neon). Then graduate the hero eagle to Path A (skinned mesh + baked talon-strike/death anims).

---

## Reference: verified research findings (raptor-ID, 3-0 adversarial votes)

- Wingspan ≈ **2.4× body length**; wings are a **long BROAD low-aspect "plank"** with a nearly straight leading edge.
- Held **DEAD FLAT** (no dihedral V) — the single most reliable eagle-vs-vulture silhouette cue.
- **~6 splayed primary "finger" slots** at the tip (sources say 6–7 typical; not pinned to an exact count).
- Tail **short, broad, wedge**; big **white head/neck projects forward** past the wings.
- Crow contrast: ~½ the size, span ratio ~2.0, broad rounded finger-slotted wingtips, **short rounded/square tail** (not wedge).
- Colors: eagle body/wings very dark brown, head+tail white, **feet yellow, claws black, iris pale yellow** (not glowing gold). Crow glossy black with blue/purple structural sheen.

## Reference: the 5 red-team audits (what each covered)

1. **Perf/rendering** — found the CastShadow win (applied) + Glass cost (applied); recommended LOD (deferred #3) and animating at render rate not 180Hz (partly addressed — remote pass is on RenderStepped). Confirmed the massless-assembly + CanQuery-off design is FINE.
2. **Physics/assembly** — found the `motor.C1` inversion (applied) + the non-replicating Transform (fixed via remote pass). Confirmed assembly root = Body, feather-welded-to-wing, and SetNetworkOwner are all FINE.
3. **CFrame/geometry** — found the WedgePart-convention reversal on rump + brow (applied). VERIFIED the primary-feather fan, clipping margins, flap arc, and tail wedge are all mathematically CORRECT (do not "fix" them).
4. **Art fidelity** — drove the color/material/pupil fixes (applied); proposed beak-wedge + corner-wedge tips (deferred #2). Warned AGAINST a pale shoulder / dark tail band (would make it look juvenile/golden — don't add).
5. **Luau/API** — confirmed no nil-derefs, div-by-zero guards hold, duplicate sibling names are safe, manual Motor6D.Transform w/o Animator is valid. Flagged the same replication issue (fixed).

## How to continue

- Drive further module work through the repo's `loop-orchestrator` skill (`loop_skill/`, `roblox-game` profile) per `CLAUDE.md`.
- Keep updating the memory file `bird-art-pipeline-decision.md` as decisions land.
- Every visual change: **Studio Play-test** — that's the only real check.
