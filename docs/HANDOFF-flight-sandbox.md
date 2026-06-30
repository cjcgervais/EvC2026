# HANDOFF — Flight feel & sandbox grind (free-look pan · render distance · flap power · rich map)

**Created 2026-06-30** after the SECOND live playtest of `flight-camera-redesign-v4`. For an agent with
**cleared context.** Pair with `CLAUDE.md` (architecture/contracts) and the two design memories called out
under *Guardrails*. **Validate everything in Studio — pressing Play is the only real test on this project.**

> **You're inheriting a flight model the player LOVES.** His exact words this session: *"free look works,
> everything works… doing a loop looks amazing and the control is good. It's great for maneuvers."* The
> kernel is human-verified and tagged. **Your job is not to rebuild — it's to make a great thing feel
> incredible.** Four focused, mostly-independent improvements. Land them and the eagle goes from "great" to
> "I can't put it down." Knock it out of the park. 🦅

---

## Status coming in (what's already true)

- **The 3 free-look bugs from Playtest-1 are FIXED and PLAYER-CONFIRMED working** (attitude-hold on
  release, no camera 180° flip in a free-look loop, pitch no longer inverted). See
  `docs/HANDOFF-freelook-fixes.md` for what changed in `BirdController.client.luau`. **Do not regress these.**
  *(These edits are on the branch but may be uncommitted — check `git status`; a clean commit of the
  confirmed fixes is a fine first move before you start.)*
- The flight **kernel** (`FlightPhysics` + the grip/PD/loop-commit model) is human-verified — see the
  `flight-vertical-envelope` and `flight-camera-redesign-handoff` memories. **Don't reopen the kernel** to do
  any of the work below; every task here is an input-layer, camera, config, or map change.
- Branch `flight-camera-redesign-v4`. `master` is the last fully human-verified build. `.\build.ps1` is green.

---

## Guardrails (read before touching numbers)

- **Flight physics and balance are ONE system** (`feedback-flight-balance-inseparable` memory). The flap-power
  task (P4) is an **Eagle** change → reason about the **1-eagle-vs-4-crow** matchup on every edit. The
  camera / render / sandbox tasks (P1–P3) are feel/QoL and balance-neutral — but still keep the eagle legible.
- **All Luau files start with `--!nonstrict`.** Refine incrementally; do not regenerate modules.
- The player flies with the **angle-of-incidence (body-pitch) HUD indicator** as his primary instrument
  (`GameUI` `_G.SetIncidence`, fed from `BirdController.pushUI`). Keep it meaningful — don't break it.

---

## P1 — Map renders too late at speed (situational awareness)  ⬅ quick win, do first

**Player:** *"the map doesn't render in time at the speed you are going or distances, so it messes up your
perception."*

**Prime hypothesis — content streaming.** `Workspace.StreamingEnabled` is **never set** in the project
(`default.project.json` only sets `Gravity = 196.2`; grep found no Streaming config anywhere). Modern Roblox
places default streaming **ON** with a small target radius, so at real-scale stoop speeds the distant map
parts stream in **late → pop-in**. The arena is only **~26 large anchored parts** (`GameServer.BuildMap`,
~line 251) — streaming gives **zero** benefit here and only causes the symptom.

**Fix (try in this order, Studio-verify each):**
1. **Disable streaming.** Set `Workspace.StreamingEnabled = false` — either in `default.project.json`
   `Workspace.$properties` (next to `Gravity`) **or** in `BuildMap`/`SetupLighting` server-side
   (`Workspace.StreamingEnabled = false`). With ~26 parts the whole map replicates instantly. *First, in
   Studio, check the live value in Workspace's Properties to confirm it was on — that confirms the diagnosis.*
2. **If you keep streaming for some reason,** instead set a large `StreamTargetRadius` (e.g. ≥ the arena
   half-extent the player can see, several thousand studs) and `StreamingIntegrityMode`. But (1) is simpler
   and correct for this map.
3. **Secondary — atmosphere haze.** `SetupLighting` (`GameServer` ~line 211) sets `Atmosphere.Density = 0.18`,
   `Haze = 0.6`. If distance still reads murky after (1), drop `Density`/`Haze` a touch so the perimeter
   mountains and the N/E/S/W neon beacons stay crisp far out. `FogEnd` is already effectively off (1e6).

**Acceptance:** fly a full-speed dive across the arena — landmarks are present the whole way, **no pop-in**,
heading/altitude always readable.

---

## P2 — Free-look pan should feel like War Thunder arcade  ⬅ the main ask

**Player:** *"it's outside you looking in at the bird and it's hard to smoothly navigate all around… I'm used
to War Thunder arcade — I want that feel and ability to smoothly pan around. It feels limiting."*

The maneuver behaviour is right; the **pan itself feels heavy and slow**. Three compounding causes, all in
`BirdController.updateCamera` / the free-look input handlers — **none touch flight**:

1. **Free-look reuses the chase cam's heavy smoothing.** The final
   `camera.CFrame = camera.CFrame:Lerp(targetCF, alpha)` uses `alpha ≈ 1 - exp(-followSmoothing·60·dt)` with
   `followSmoothing = 0.18` → only ~16%/frame toward target → the pan **lags the mouse**. WT free-look is
   near 1:1. **→ When `freeLook.active`, use a much higher smoothing (add `CAM.freeLookSmoothing`, ~0.6–1.0,
   or bypass the lerp for the orbit) so the view tracks the mouse crisply.** This is likely the single
   biggest feel win.
2. **Sensitivity is low.** `CAM.freeLookSensitivity = 0.35`, applied as `·0.01` in the `InputChanged` handler
   (`BirdController` ~line 372) → ~0.0035 rad/px. **→ Raise it (try 0.6–1.0), and consider separate
   yaw/pitch sensitivity and/or a small mouse-accel curve.** (The corrected pitch sign + arrow keys from
   `HANDOFF-freelook-fixes.md` must stay.)
3. **Orbit radius = full chase distance.** At speed the camera sits far back (`baseDistance 40 +
   speed·0.06`, up to `maxDistance 800`), so the orbit sweeps a *distant* pivot → big, twitchy arcs.
   **→ Consider clamping the orbit radius to a comfortable look distance while `freeLook.active`** (pull in to
   a fixed, nearer pivot) so sweeping around the bird is controllable.

**Design fork to decide (and note in your handoff):** keep the current **orbit-the-bird** model (what WT
arcade actually does — just make it crisp + fast per above) **vs.** a **pan-in-place "head turn"** from the
camera's own position. Recommendation: **stay orbit, make it crisp** — it's less risk and matches WT. Only
explore head-look if the player still wants it after the smoothing+sensitivity pass. A little pan **momentum**
(ease-out on the orbit) is an optional polish that adds to the WT feel.

**Acceptance:** the player can whip the view around to "check six" and back **smoothly and 1:1**, the bird
stays legible/centred enough to keep flying, and it no longer feels limiting. (Don't regress the no-flip
loop camera or the mouse-aim chase cam — P2 changes should gate on `freeLook.active`.)

---

## P3 — A spacious sandbox with texture & parallax (sense of flight)

**Player:** *"I need a big spacious map sandbox with features and texture to get a good sense of the flight"*
(he's reading the angle-of-incidence indicator while doing this).

The arena is already big (16 000×16 000 floor, perimeter mountain ring R≈6600, 5 interior buttes, 4 cardinal
neon beacons, a lake + desert — `BuildMap`, ~line 251). What's missing for a **sense of speed** is **mid-field
parallax and texture** — things at *varied distances and altitudes* you whoosh past. Speed is *felt* through
nearby reference, not distant landmarks.

**Two parts:**

**(a) Enrich the map — more flyable features + texture (balance-neutral, but don't re-add crash-frustration).**
- Add **mid-field, varied-height features**: spire clusters, **arches / rings to fly through**, floating
  reference markers at **known altitudes** (great with the AoI/climb-dive read). Space them generously —
  the collision model **slides on grazes** but a head-on above `Flight.CRASH_SPEED` is lethal
  (`BirdCollision` / `processCrashes`). History warns: **landmarks to soar around, not a crash-forest**
  (`docs/HANDOFF.md`). Keep them off the ±1200 spawn scatter.
- Add **ground texture for a speed reference**: a grid / `MaterialVariant` / many small scattered ground
  features so the floor visibly streaks past at speed. The parts already use Grass/Rock/Sand materials —
  lean into texture/contrast (the OODA lighting in `SetupLighting` is tuned for legibility).
- Keep the deterministic build (no `Math.random` at build time per the existing pattern — varied via index).

**(b) Add a SANDBOX MODE so flight can be felt without combat noise (high value, low risk).**
For pure flight-feel testing, AI crows + the 240 s round + respawn flow are noise. Add a
`GameConfig.Sandbox = { enabled = true, ... }` flag that the server honours to: **skip AI-crow spawning, skip
round start/end, and make respawn/stamina forgiving** (or infinite stamina) so the player just *flies* the
rich map and tunes feel. This directly serves the ask and makes P2/P4 testing clean. Gate it so flipping
`enabled = false` restores the normal game exactly.

**Acceptance:** flying fast **feels** fast (constant nearby parallax), there's always something to gauge
speed **and altitude** against, and the player can free-fly the sandbox with no round/AI interference.

---

## P4 — More power & acceleration per flap (balance-aware)  ⬅ Eagle change, reason about 1-v-4

**Player:** *"more power and acceleration per flap, but balance it."*

**How flap works today** (`FlightPhysics:Update`, ~lines 155–286): the sticky flap **throttle** (Shift up /
Ctrl down, `BirdController` ramps it) becomes `flapPow ∈ [0,1]`, which scales a **continuous** forward force
`flapThrust` along the nose (`accel += look · thrust·altFactor/mass`, ~line 275) and a vertical
`flapClimbForce` when nose-up (~line 285). **The wingbeat itself is cosmetic — thrust is a steady force, not a
per-stroke impulse.** Current Eagle numbers (`GameConfig.Profiles.Eagle`, ~line 188+):
- `flapThrust = 600 · GRAV_SCALE` — forward accel = `thrust/mass`, `mass = 16`.
- `flapClimbForce = 400 · GRAV_SCALE` — climb accel (mass-independent).
- `maxStamina = 240`, `staminaFlapCost = 6/s` at full throttle → ~23 s sustained flapping (the limiter).
- For contrast, Crow `flapThrust = 150·GRAV_SCALE`, `flapClimbForce = 200·GRAV_SCALE` (crows aren't climbers).

**Two ways to give "more power per flap" — pick one or combine:**
- **Option A (simple, number):** raise `Eagle.flapThrust` (e.g. 600 → 750–900) and/or `flapClimbForce` for
  more punch and climb. **Do NOT lower `mass` to get punch** — mass is the eagle's momentum/energy retention
  (raised 8→16 deliberately in session 7); lowering it makes it twitchy and weakens the boom-and-zoom
  identity.
- **Option B (juicy, feel — recommended to prototype):** modulate thrust by the **wingbeat phase** so each
  flap is a **felt surge** (a downstroke power pulse synced to `flapPhase`, ~line 383) instead of a flat
  force. This literally makes "power *per flap*" real and is a localized change around lines 263–286. Risk:
  porpoising/jerk — gate it behind playtest and keep the *average* thrust sane.

**Balance reasoning (must do):** flap power is the **Eagle's energy engine** — more of it = faster
re-acceleration after a turn/zoom = stronger boom-and-zoom = harder for crows to catch in the energy game.
The 1-v-4 counter-levers live with the **crows** (numbers, possession, formation, collision trades), **not**
their flap — so **do not auto-scale the Crow numbers** with the eagle's. Keep **stamina the limiter**: if you
add punch, consider nudging `staminaFlapCost` up a touch so "more power" doesn't become "more *free* power."
Re-read the `research-flight-balance-findings` memory before settling numbers.

**Acceptance:** a flap gives a satisfying, *felt* surge of speed/climb; sustained flapping still ends from
fatigue (stamina) or the ceiling, not free forever; the boom-and-zoom identity is intact.

---

## Suggested order & how to work
1. **P1 streaming** (minutes, unblocks "I can see").  →  2. **P3(b) sandbox mode** (clean test bed)  →
   3. **P2 free-look feel** (the main ask)  →  4. **P3(a) map texture** + **P4 flap power** (tune live in the
   sandbox). They're largely independent — reorder freely, but P1 + P3(b) make testing the rest pleasant.
- Drive each via the **`loop-orchestrator` skill** (`loop_skill/`, `roblox-game` profile) per CLAUDE.md;
  `.\build.ps1` is the wiring check, **Studio Play is ground truth**, the player is the human verifier.
- After each change: `.\build.ps1` green → ask the player to Play-test → tune. Update the project memory when
  a design question resolves.

## Pointers (exact)
- Camera + free-look: `src/client/BirdController.client.luau` — `updateCamera` (~line 420), free-look input
  (`InputChanged` ~line 362, arrow keys ~line 380), `setFreeLook` (~line 264). Camera tunables:
  `GameConfig.Camera` (~line 457): `freeLookSensitivity`, `followSmoothing`, `baseDistance`, `maxDistance`.
- Render/lighting/map: `GameServer.server.luau` — `SetupLighting` (~line 196), `BuildMap` (~line 251),
  `CreateThermals` (~line 335). Streaming: `default.project.json` `Workspace.$properties`.
- Flap/thrust: `FlightPhysics.luau` `Update` (~lines 155–286); numbers in
  `GameConfig.Profiles.Eagle/.Crow` and `GameConfig.Flight` (flap/ceiling block ~line 114+).
- Don't-regress reference: `docs/HANDOFF-freelook-fixes.md` (the 3 confirmed fixes).
- Context: `docs/RESEARCH.md` (§v3 real-scale, §v4 camera/instructor), `docs/HANDOFF.md` (arena history),
  memories: `flight-vertical-envelope`, `flight-camera-redesign-handoff`, `mouse-aim-pursuit-model`,
  `feedback-flight-balance-inseparable`, `research-flight-balance-findings`, `project-realscale-flight-goal`.
</content>
</invoke>
