# VISUAL QUALITY BAR — the definition of "good" (S47 strategy consult)

> **Status: STRATEGY OF RECORD, pending Chad's ratification of the target look (Gate V-LOOK,
> judged FROM SCREENSHOTS — no flight required).** Written by Fable at the S47 consult in answer
> to `docs/CONSULT-VISUAL-QUALITY.md`. This document is the actionable opposite of "terrible":
> from now on, every player-visible thing either meets this bar or is explicitly flagged
> `PLACEHOLDER(expiry)` in code and in the plan. There is no third state. The flag has teeth:
> a Tier-4 source scan fails on any `PLACEHOLDER(...)` whose expiry (a phase gate or date)
> has passed — an expiry nothing checks is a euphemism.

---

## 0. Scope honesty (consult §4 Q6, answered out loud)

**This game is being built to PUBLISH.** The standard is: competitive with what a kid actually
sees on the Roblox front page in 2026. Concretely — a parent watching over a kid's shoulder
should read it as *a real game*, not a programmer prototype. "It works and the tests are green"
is half a standard; the other half is this document.

**The honesty rule (from `feedback-quality-bar-never-set`):** every status report states WHICH
halves were verified — LOGIC (tests), APPEARANCE (images), FEEL (flight). The word "green" alone
is banned.

## 1. Target look — RECOMMENDATION (Chad ratifies at Gate V-LOOK)

**"Vibrant stylized Roblox-native."** A saturated, sunlit forest valley with chunky readable
shapes, real materials and lighting doing the heavy lifting — not photoreal, not flat-shaded
primitives. The three pillars of the read, in priority order:

1. **The GROUND reads as land** — real Roblox Terrain (grass/rock/water voxels) with painted
   variation, not a box baseplate with color patches. Terrain is the single highest-leverage
   change in the project: it replaces the baseplate, the sea, the lake, the rivers, the patch
   system (and its z-fighting class *by construction* — voxels can't be coplanar), and the
   box mountains, all with engine-optimized, mobile-friendly geometry that ships with animated
   water for free.
2. **Light sells everything** — one deliberate golden-hour lighting rig (sun angle, Atmosphere,
   ColorCorrection, a real skybox) tuned as a *set*, judged from screenshots. Cheap, global,
   and the difference between "cheap" and "warm" at every altitude.
3. **Set pieces earn their close-up** — the waterfall, groves, and fire are the three things a
   player flies TO; each has a motion + sound + material definition of done below.

**References of record:** `EvC2026_Art/*.png` for bird palette/silhouette (the eagle sheet is a
production-spec model sheet — palette `#E8834E`/browns/white already extracted); no environment
concept exists, so the look-dev slice (packet V3) IS the environment concept — Chad picks from
rendered screenshots of the actual game, not from imagined references.

### 1.5 Technique decisions (verified against official docs + devforum, S47 — sources in the
research pass; each still gets prototyped in the look-dev slice before world-wide rollout)

- **Terrain (VERIFIED):** `Terrain:FillBlock/FillBall/FillRegion` + chunked `WriteVoxels`, all
  runtime-scriptable server-side; 4-stud voxels. Big primitive fills are fast (C++); per-column
  heightmaps are the slow path — chunk with yields. Water animates natively (`WaterWaveSize/
  Speed/Reflectance` — scriptable). Terrain material palette recolorable in code with ZERO
  assets via `Terrain:SetMaterialColor`. Generation wall-clock at valley scale has no official
  spec — **V3 measures it before V4 commits.**
- **Meshes (VERIFIED — the front-page ingredient):** the **Synty Nature Pack, Creator Store
  asset `6933438443`, published by Roblox itself, free, officially licensed, 200 MeshParts,
  0 scripts** — trees/rocks/nature set. Devforum art consensus: stylized front-page look =
  *mesh silhouettes + palette + lighting*; textures optional, meshes effectively mandatory.
  **Ingestion path:** try automated download (assetdelivery / Open Cloud) → `.rbxm` committed
  under `assets/` → Rojo maps it into `ReplicatedStorage.Assets` → world-gen `:Clone()`s.
  Fallback if download fails: ONE 5-minute Chad step (insert pack in Studio → Save-to-File
  `.rbxm` into the repo) — once, ever, not per-session. Runtime `InsertService/LoadAssetAsync`
  paths exist but are permission-fragile — the committed-`.rbxm` path has zero such surface.
- **Screenshot harness (VERIFIED with a boundary):** plugin-security scripts CAN set
  `workspace.CurrentCamera.CFrame` in edit mode; there is NO API that saves the viewport to
  disk — capture is OS-level (`System.Drawing.Graphics.CopyFromScreen` from PowerShell) on a
  fixed vantage schedule. Known-good architecture; the packet proves it end-to-end.
- **Audio (candidate IDs in hand, free/licensed, to be auditioned in-engine):** fire —
  `121442216641422` "Campfire Crackling", `9118030832` ProSoundEffects fire loop; squeaks —
  `5660185015` / `111105644516217` mouse squeaks (closest licensed match; squirrel-specific
  not found); music — `9047876673` APMOfficial "Happy Adventure" (+30s cut `9047880046`).
  Shipped as config lists so any swap is one number.
- **MaterialVariants:** need uploaded texture assets — NOT used in the first pass (Terrain
  colors + mesh palettes + lighting carry the look).

## 2. Per-set-piece definition of done

*"Judge" column: **M** = machine gate (headless test), **I** = image gate (Fable audits the
screenshot contact sheet), **F** = flight gate (Chad, batched at phase gates only).*

| Set piece | Definition of done (minimum bar) | Judge |
|---|---|---|
| **Ground** | Roblox Terrain; ≥3 materials blended (Grass/Ground/Rock); painted color variation; ZERO coplanar overlapping faces anywhere in the world (machine invariant); altitude cue survives (dive-judgement patches or terrain relief) | M+I+F |
| **Water (sea/lake/rivers)** | Terrain Water (animated, reflective natively) — no transparent boxes | I |
| **Waterfall** | Visible MOTION (scrolling Beam texture or equivalent) + spray/foam particles at base + rim mist + positional sound with rolloff; reads as water in a still from 300 studs | I+F |
| **Trees/groves** | Silhouette variation (≥2 canopy shapes) + color/material variation per tree; no naked cylinder+ball read at 100 studs; stays NON-COLLIDABLE (Chad's ghost-forest decision, LOCKED) | I |
| **Mountains** | Terrain rock (or mesh) — no bare boxes on the horizon | I |
| **Fire** | Existing flipbook/light/smoke system (§3.3 budgets LOCKED) restyled to the ratified palette; reads as danger at 400 studs **judged under the NEW lighting rig** (golden warmth reduces fire-orange contrast — the kid-legibility Stage 1+2 verdicts must survive it); HAS SOUND (see Audio) | I+F |
| **Sky/lighting** | Real skybox (not default); deliberate sun angle; Atmosphere + CC tuned as one rig; two stills (noon-golden + fire-glow) approved; **far-read criterion: a distant grove/beacon stays readable from the spawn vantage** — the current thin Atmosphere (Density 0.03) implements Chad's direct "eagle vision" ask, and a hazier golden rig may not regress it | I |
| **Audio** | `roarAssetIds`/`squeakAssetIds` FILLED by us with verified IDs + a music bed; **empty-asset-ID handoffs to Chad are BANNED** — a packet that ships plumbing without content is incomplete | M(smoke)+F |
| **Eagle/critters** | Current procedural rigs (Tier-2, already research-tuned) restyled to sheet palette only; mesh Tier-3 stays DEFERRED per `bird-art-pipeline-decision` — the world is 95% of pixels at altitude | I |
| **HUD/beacons/FX** | Harmonized with ratified palette; Neon gameplay markers (beacon/gem/wayfinder) KEEP their legibility contrast — kid-legibility Stage 1+2 verdicts are not to be regressed | I+F |

## 3. Perf budget (quality AND runtime, same table — PLAYTEST-PROVISIONAL numbers)

Per Chad: runtime is first-class, set deliberately, not found reactively.

| Budget | Value | Instrument |
|---|---|---|
| Boot → world DRAWN (Auto graphics, Chad's PC) | **< 5 s** | boot probe (exists, off — flies at Gate V) |
| Steady frame rate in Studio Play | 60 fps | gate flight |
| Total world Instances (excl. birds/FX pools) | **≤ 2× current** (~500 → hard cap 1,000; Terrain voxels are free) | headless count gate |
| Non-shadow PointLights | ≤ 30 (existing S43 cliff finding, LOCKED) | perf.spec |
| ParticleEmitters live | existing §3.4 caps | perf.spec |
| Unique texture/mesh assets | ≤ 20 world + 10 FX (mobile memory) | headless count gate |
| Server FireGrid tick | ≤ 1.5 ms (existing) | perf.spec |
| Target device honesty | Chad's PC now; mid-range phone BEFORE any B7 ship | gate checklist |

## 4. How appearance is judged without burning Chad (the instrument ladder)

1. **Machine (headless):** geometry invariants — the no-coplanar-faces test, budget counts,
   world-build parity. Runs in the existing Tier-4 lune lane once world-gen is extracted to a
   pure module (packet V1, the same extraction pattern that worked for RescueRules).
2. **Images (Fable):** the screenshot harness (packet V2) builds the world in Studio EDIT mode
   via run-in-roblox, positions the camera at ~8 standard vantage points (spawn view, 600-stud
   overview, grove interior, waterfall approach, dive line, fire line, delivery run, horizon),
   and captures a contact sheet. **Fable audits the sheet against §2** — iteration happens
   here, at zero Chad cost. Stills can't judge motion/feel; they catch exactly the class that
   burned S44–S46 (z-fighting, glass waterfalls, flat shading, scale errors).
3. **Flight (Chad):** ONE flight per phase gate, checklist ≤ 12 items, only after the image
   audit passes. Chad judges what only Chad can: fun, feel, motion, load time.

**Standing rule: a packet whose only conceivable gate is "Chad looks at it" is ILLEGAL outside
a phase gate.** It must carry a machine or image gate, or it waits.

## 5. What this bar does NOT touch

- The flight kernel, camera, aim law (CS-1..CS-9) — LOCKED, and the kernel's "incorrectness"
  is a signed-off feature.
- The core loop — CONFIRMED FUN (S42). This is presentation, not design.
- Non-lethal always (P3); kid-floor + skill-ceiling in the same mechanic.
- `Rescue.treeCollision = "off"` — Chad's design decision stands; visual trees stay ghosts.
- §3.3 fire simulation numbers and the §3.4 perf gates — restyle the look, never the budgets.
