# CONSULT PACKET — visual quality, runtime, and how this project is being built

**For:** the incoming strategy agent (Fable), with Chad in the room.
**From:** the S46 implementation agent (Opus), 2026-07-22.
**Status of this document:** this is a **consult brief, not a plan.** It exists because Chad stopped
the loop and asked for a strategy conversation instead of another patch. Nothing here should be
"fixed" before that conversation happens — the point is to decide *how* we work, not to close tickets.

---

## 1. The complaint (Chad, verbatim — this IS the spec)

> "the waterfall looks fake. Why are we building such terrible looking maps.. The waterfall looks like
> a pice of glass stood up. The grass ground looks terrible and is flashing. Why do I have to go
> through all of this minutiua. Im back on auto graphics and it still takes forever to load the map
> terrain. Whe it does its flashing all over. .. Everything looks cheap and broken fi we are building
> the map the fire the squirrels, the waterfall the trees we have to start building for quality and
> good runtime at the same time. It feels like this project is treated as a dead end already but the
> kind of work that is being done. Like it is for throw away, curiosity sake. I almost crashed into
> the terrain tring to go down so it would render. There has been this issue, the pinging (finally
> solved) but there is also audio such as the fire no sounding, the squirrels not sounding... Every
> fix I try to get done takes 7 or 8 passes and is a waste of tokens."

**Do not treat this as a bug list.** Every specific claim below checked out on inspection. The
substantive charge is about *method*, and it is correct.

---

## 2. What I verified before writing this (mechanism, not opinion)

### 2.1 The flashing is Z-FIGHTING, and we shipped it ourselves — `GameServer.server.luau:336-343`
All **133** `GroundDetail` patches are emitted with `Size = Vector3.new(w, 4, l)` at
`Position = Vector3.new(x, 0.6, z)`. Every patch is therefore 4 studs thick with its **top face at
exactly Y = 2.6**. The three bands (`coarse` 420–760 studs wide, `mid` 150–320, `fine` 48–118 —
`GroundDetail.luau:64-66`) are *designed* to overlap spatially across the same ±1200 box.

⇒ **Overlapping patches share an exact depth plane.** That is the textbook z-fighting configuration:
the GPU cannot order two coplanar surfaces, so it flickers between them per-pixel as the camera moves.
From 600 studs up looking down at ~133 overlapping coplanar slabs, that reads as *"flashing all over."*

This was added in **S45b** to fix a real defect (Chad diving into a featureless plane with no altitude
cue). It fixed that and introduced this. **Kill switch: `Map.coreDetail = false`** restores a
byte-identical map today. A 3-line alternative — give each band its own Y (e.g. 0.4 / 0.8 / 1.2) so no
two overlapping patches are ever coplanar — keeps the altitude cue *and* kills the flicker.

### 2.2 The waterfall is, literally, a stood-up piece of glass — `RescueServer.server.luau:199`
```lua
local fall = anchoredPart("Waterfall", Vector3.new(6, R.deliverPadY, 120),
    Color3.fromRGB(150, 210, 255), Enum.Material.Glass, worldFolder)
fall.Transparency = 0.45
```
One static Part. No motion, no particles, no texture, no normal variation, no spray, no sound.
**Chad's description is not hyperbole — it is an accurate reading of the source.**

### 2.3 "Renders in slow" is NOT solved. ⚠️ REOPEN IT.
S45c convicted quality-scaled render distance, shipped two real fixes (`CastShadow` on 78 Map parts;
the 108-million-square-stud Glass Sea), and Chad confirmed once — *"yep graphics worked."* **He is now
back on Auto graphics and reports it still takes forever AND flashes.**

**I marked this "SOLVED AND CONFIRMED" in the HANDOFF cold-start earlier today. That was premature and
is now falsified.** The fixes were real and should stay; the root cause is not closed.

⚠️ **And note the trap we may have walked into for the fourth time:** the *flashing* (§2.1) is a
**separate defect that produces a similar complaint**. S44/S45 burned three sessions on exactly this
pattern — several plausible mechanisms, more than one of them a genuine bug, only one of them *the*
bug. Before any new render work: **separate "the world arrives late" from "the world flickers once it
is here."** They may have nothing to do with each other. (See `feedback-when-a-fix-fails-reinstrument`.)

### 2.4 The entire game is untextured primitives — this is the strategic finding
`grep` across all of `src/`: **zero `MeshPart`, zero `MeshId`, zero `SurfaceAppearance`, zero `Decal`,
zero `Texture`** (the single hit is one particle sprite in `FeatherFX`). Concretely:
- A **tree** = one cylinder + 2–3 spheres (`RescueServer.buildTree`).
- A **mountain** = a box. The **sea**, **lake** and **waterfall** = transparent boxes.
- The **ground** = a 16,000-stud box baseplate + 133 flat colour patches.
- **Squirrels / eagle** = procedurally assembled primitives (`BirdBuilder`).

This is a **gray-box prototype that has been treated as shippable for ~14 sessions.** No session ever
set a visual quality bar, so there has never been a definition of "good" to fail against — which is
exactly why Chad's "terrible" has no actionable opposite yet. **That is the gap the consult must close
first.**

### 2.5 Fire and squirrels are silent *by configuration*, blocked on Chad — `GameConfig:1436, 1047`
`Fire.roarAssetIds = { }` and `Rescue.squeakAssetIds = { }` ship **empty**. The playback plumbing is
built, tested and live; both print a how-to in Output at boot asking Chad to paste Toolbox asset IDs.
**We built the machine and handed the last mile to the person with the least time.** That is a process
failure, not an audio bug, and it is why "the fire doesn't sound" has survived multiple sessions.

### 2.6 Concept art exists and was never used
`EvC2026_Art/` holds 3 Gemini concept images, logged in memory since ~S20 as *"for a later model
pass."* Later never arrived. If the consult picks a target look, this is the only existing reference.

---

## 3. Why every fix takes 7–8 passes (the real charge, and it lands)

1. **Ground truth is Chad's flight, and nothing else.** Every perceptual question costs a full session
   round-trip. There is no cheaper instrument for "does this look right."
2. **The verify ladder is excellent at LOGIC and totally blind to APPEARANCE.** 205 headless tests,
   mutation-tested gates, a register-headroom gate, source gates that read code not prose — genuinely
   strong engineering, and **not one of them can see a z-fighting plane, a flat-shaded waterfall, or a
   flickering meadow.** We built a rigorous test culture around the half of the problem a test can see,
   and then reported "green" to Chad as if it meant the game was good. §2.1 shipped through all 205.
3. **The unit of work is wrong for a world.** "One change, config-gated, revertible" is right for a
   flight kernel and wrong for art direction. You cannot gray-box-patch your way to "looks good," and
   14 sessions of disciplined single-knob changes is how a placeholder world becomes permanent.
4. **Directive #8 was applied too narrowly.** `evc-loop` already says: vet the *approach* before
   building any perceptual change, reject techniques whose ceiling is below the read, bring Chad a
   vetted working result. That was honoured for **particles** and never once applied to **the world**.
5. **Deferred-to-Chad accumulates.** touchAim (DRAG vs TAP), fire audio IDs, squirrel audio IDs, the
   tree-collision call, the Phase C green-light. Each was individually reasonable; together they mean
   Chad is the bottleneck on five open threads while also being the only quality instrument.

---

## 4. The questions the consult needs to answer

1. **What is the target look?** Roblox-native stylized? Painterly? The concept art in `EvC2026_Art/`?
   Nothing is written down, so nothing can be judged. **This blocks everything else.**
2. **Build order.** Does the world get rebuilt for quality *before* more mechanics, or in parallel?
   Chad's phrasing — *"quality and good runtime at the same time"* — reads as: stop deferring.
3. **Asset strategy.** Primitives are the current ceiling. MeshParts? Toolbox? `SurfaceAppearance`?
   Roblox Terrain instead of a box baseplate? **Who sources assets, given Chad's time is the scarcest
   resource in this project?**
4. **Perf budget, set deliberately.** Shadow and Sea costs were found *reactively*, after a
   three-session hunt. What is the actual part/draw/frame budget, on what target device? Note mobile
   interest is on record (B7) and the primary audience is a child on unknown hardware.
5. **How do we judge appearance without spending a Chad session per look?** Options worth weighing:
   headless screenshot capture via the existing Studio smoke tier (4.5), a one-time recorded flythrough
   Chad supplies, a static reference sheet, or an explicit "art passes are batched, not incremental."
6. **Scope honesty.** Chad's read is that the work implies *"throwaway curiosity."* Is this a game we
   are shipping? The answer changes the correct engineering standard, and it should be said out loud
   before the next packet.

---

## 5. Constraints any strategy must respect (do not relitigate these)

- **The flight kernel, camera and aim law are SIGNED OFF and LOCKED** (CS-1…CS-9). Rescue is built
  *around* them. Chad has also ruled that the kernel's non-realism is a **feature**, not a bug to fix.
- **The core loop is CONFIRMED FUN** (S42: *"addictive and fun… actually fun!"*). **The problem is
  presentation, not design.** Do not redesign the game.
- **Kid-floor and skill-ceiling in the same mechanic; never lethal** (P3).
- **Runtime is a first-class constraint**, per Chad — not a later optimisation pass.
- Config-gate with a kill switch; mutation-test every gate; `build.ps1` does not run Luau.
- **Seven changes are live and UNJUDGED** (see HANDOFF cold start). Any new work stacks on unflown
  ground — worth resolving early in the consult.

---

## 6. Cheap, real wins available immediately (flagged, deliberately NOT done)

Held back because Chad asked for a strategy conversation, not another patch. Each is small and
independently revertible:
- **Kill the flashing:** either `Map.coreDetail = false` (one word, loses the altitude cue) or give
  each `GroundDetail` band its own Y so overlapping patches are never coplanar (~3 lines, keeps it).
- **The two audio IDs** — if the strategy is "we source assets ourselves," these stop being Chad's job.
- **Waterfall:** the current Part cannot read as water at any distance. Any real fix is a technique
  choice (animated texture / particles / Beam / mesh), i.e. exactly a directive-#8 approach-vetting
  question — which is why it belongs in the consult and not in a quick patch.
