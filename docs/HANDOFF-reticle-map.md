# HANDOFF — strike reticles, beak-zone aim, and building out the map

**Created 2026-06-30** (end of the P1–P6 session, after live playtest notes from Chad). For an agent with
**cleared context.** Pair with `CLAUDE.md` (architecture + contracts), `docs/HANDOFF.md` (full history + the
locked standalone-bird decision), `docs/HANDOFF-flight-feel-combat.md` (the P1–P6 work this builds on), and the
memories under *Guardrails*. **Pressing Play in Studio is the only real test — Chad is the human verifier.**

> **State going in:** P1–P6 are landed + pushed (`origin/master`), and Chad has been live-testing them. The
> eagle flight kernel is loved & locked (`v1.0-eagle-flight` — do NOT reopen). The directional-strike combat
> (P6) works server-side; now it needs a **proper combat-aim UI** and the **map needs building out** so the
> player can see where they're flying. Three asks below, all from Chad's 2026-06-30 test session.

---

## ✅✅ LANDED next session (2026-06-30, build-green, **UNPLAYTESTED — Chad to verify in Studio**)
Two commits on `master` (not yet pushed — ask Chad):
- **Ask #1 — strike reticles + beak-zone aim DONE.** `BirdController` + `GameConfig.Controls`. The amber nose
  cross + two NEW side **talon reticles** are now drawn near the beak (`beakReticleDistance=70`, side offset
  `strikeReticleSideOffset=26`) instead of 600 studs out. The reticle the **live bank** arms LIGHTS UP
  (`paintStrikeReticles`) via the SAME inverted mapping as `classifyBank`, read client-side from
  `cf.RightVector.Y`: **bank RIGHT → LEFT lights, bank LEFT → RIGHT lights, level → nose cross (forward) lights.**
  DECOUPLED from `aimMarkerDistance` (still 600) so the steering feel is untouched. Green cursor ring unchanged.
  → **Verify:** banking lights the correct side, all three sit near the beak, no flight-feel regression. Tune
  `beakReticleDistance` / `strikeReticleSideOffset` to taste.
- **Ask #2 — map build-out DONE.** `GameServer.BuildMap`. Three depth-staggered mountain rings (foothills R3600 /
  mid R5400 / far snow-capped peaks R7400), a distant SEA/coastline, a winding river, varied ground colour
  patches (forest/plateau/snowfield/marsh). Kept buttes + cardinal beacons. ~78 anchored parts, deterministic,
  ±1200 core stays open. → **Verify:** deep legible horizon from altitude, perf fine, no new crash-frustration.
- **Ask #3 — code confirmed in the right state; needs a Play.** `avoidance.weight=3.0` (gentle, no urgency
  floor), non-lethal AI terrain slide (`resolve(...,math.huge)`), `squadGoal` hunts via `findNearestEnemyLinear`
  from any range. The mob behavior itself is a Studio-only check (see ask #3 below).

---

## ✅ Just landed (committed + pushed earlier this session, build-green, mostly UNPLAYTESTED)
Recent commits on `master` after the P1–P6 pass:
- **Zoom model fixed** (`737336a`): mouse WHEEL = zoom in/out w.r.t. the eagle (works in free-look now);
  RIGHT-CLICK = awareness-only outward telescope (FOV magnify + fades the eagle so it can't block) that does
  **not** affect flight (steering is suspended while zooming) and stays centred on the heading.
- **StreamingEnabled = false** (`737336a`): fixed the eagle vanishing when zoomed out (camera was the stream
  focus with no character). **Render distance** opened up via thinner Atmosphere.
- **Strike side INVERTED** (`2d5e8da`): banking LEFT bares/fires the RIGHT talon, banking RIGHT fires the LEFT
  (front stays front) — matches the wing that rises in a bank. In `GameServer.classifyBank`.
- **Cursor circle** tightened to **1/2** the screen (`aimCursorAreaFrac = 0.5`), zoom strengthened
  (`aimFOV = 22`, FOV clamp floor lowered 50→12), stronger right-click zoom.
- **AI crows no longer suicide on buildings** (`bbc87f0` + `a7201fd`): AI-crow terrain impacts are NON-LETHAL
  (they slide, not die — `updateAICrows` passes `crashSpeed = math.huge` to `BirdCollision.resolve`); and the
  obstacle avoidance was first over-tuned (made them FLEE 18–20 km away) then **reverted to GENTLE**
  (`Squad.avoidance.weight = 3`, short lookahead, no urgency floor) so the eagle-chase dominates and they MOB.

**⚠️ NEEDS PLAYTEST FIRST:** confirm the AI crows now **mob the player** (don't flee, don't crash-die) before
doing anything else — that was the blocker for testing strikes. If they still drift, the lever is
`GameConfig.Squad.avoidance.weight` (lower = chases harder) and `squadGoal` (bot squads hunt the nearest eagle
via `findNearestEnemyLinear` — already from any range). The non-lethal slide means terrain can't kill a bot.

---

## The three asks (Chad, 2026-06-30 — verbatim intent, decoded)

### 1. ⭐ STRIKE RETICLES + a beak-zone aim reticle (the headline — combat-aim UI)
> *"reticle needs to be closer to the beak… need strike reticles that light up for the left-click strike side
> whether banking right (left side reticle lights), banking left (right side lights), so that you can aim
> talons… map needs far vision… forward flight reticle will always follow the mouse cursor authority."*

**What it means — a three-reticle melee-aim HUD:**
- **FORWARD reticle** = the existing mouse cursor/aim reticle. It always follows the mouse (the cursor
  authority that already steers flight). This is the head-on strike aim. **Keep it.**
- **LEFT + RIGHT strike reticles** = two NEW markers, one on each side, near the beak. The one that **lights
  up** is chosen by the **bank**, matching the already-inverted strike mapping:
  - bank **RIGHT** → **LEFT-side reticle lights** (the left talon is armed)
  - bank **LEFT** → **RIGHT-side reticle lights** (the right talon is armed)
  - roughly **level** → the FORWARD reticle is the armed one.
  The player banks to arm a side, lines a crow up in the lit reticle, and LEFT-CLICKS to throw that side's
  talon strike. This is the visual timing/aiming aid for P6's directional strike.
- **Aim reticle CLOSE TO THE BEAK** (the "melee strike zone"): the nose-cross marker currently projects
  **600 studs** out front (`GameConfig.Controls.aimMarkerDistance = 600`) — way past the strike reach. Bring
  the reticle(s) in close to the beak so they read as the actual melee/talon zone.

**Where (all client — `src/client/BirdController.client.luau`):**
- Reticle GUI is built ~lines 187–235: `aimGui` (ScreenGui), `aimZone` (centre tick), `noseMarker` (the amber
  nose cross / boresight), `aimDot` (the green cursor ring). **Add two more markers** (left + right strike
  reticles) here, styled to read as talon zones.
- `computeMouseAim` (~line 752) projects `nosePoint = cf.Position + birdLook * aimMarkerDistance` and writes
  the marker screen positions (`aimCursor.noseX/Y`, `aimCursor.cursorX/Y`) consumed by the render block in
  `onFlightStep` (~line 932). Position the new side reticles here too (offset left/right of the beak; project
  a point near the beak + a sideways offset, or just screen-space offsets from the nose marker).
- **Bank read for lighting:** light the correct side **client-side** for zero latency — read the live bank
  from `rootPart.CFrame.RightVector.Y` (the client already computes `curBank` in `computeMouseAim` ~line 859),
  and apply the SAME inverted mapping as the server (`GameServer.classifyBank`): bank right → light LEFT, bank
  left → light RIGHT, level → forward. The threshold is `GameConfig.Combat.bankStrikeThresholdDeg` (18°).
  *(The server already mirrors `StrikeArmedDir` onto the eagle Body — the `GameUI` L/F/R chips read it — but a
  local bank read is snappier for the reticle. Keep the two in sync: both use the inverted mapping.)*
- **Beak-zone distance:** lower `GameConfig.Controls.aimMarkerDistance` (600 → ~40–90) so the cross sits near
  the beak. **⚠️ CAUTION (don't regress the loved feel):** `aimMarkerDistance` also feeds the mouse-aim ERROR
  geometry in `computeMouseAim` (the cursor-ray vs nose-cross-ray comparison). Moving it changes how the aim
  steers. If the steering feel shifts, **decouple them**: keep the aim-error math at its tuned projection and
  only move the DRAWN reticle in close. Re-verify against `feedback-camera-control-feel` (the player-confirmed
  feel — must not regress) and `mouse-aim-pursuit-model`.

**Acceptance:** banking arms + lights the correct side reticle (right-bank → left light, left-bank → right
light), the forward reticle tracks the mouse, all three sit near the beak as a melee zone, and the player can
line a crow into a lit reticle and LEFT-CLICK to land that side's strike. No flight-feel regression.

### 2. ⭐ BUILD OUT THE MAP — far-vision "eagle vision" + perspective
> *"map needs to be built with far vision rendering so I can see where I am flying… render the environment way
> better from way further away, eagle vision, eagle can see far away, we need to build a map for perspective."*

**What's done:** render distance is already opened up — `StreamingEnabled = false` (nothing unloads) and
`Atmosphere.Density 0.03` (very clear; far terrain renders). **What's needed:** the MAP itself has too little
to look at, so there's no sense of perspective/speed/place at altitude. **Build it out** for spatial reference:
- The current map is `GameServer.BuildMap` (~line 251): a 16k×16k baseplate, a perimeter mountain RING at
  R≈6600 (14 peaks), 5 interior buttes, a lake + a desert. It's sparse.
- **Add depth + perspective cues** the player can gauge flight against from far away: more layered/distant
  terrain (foothills → mid mountains → far peaks), rivers/canyons, varied ground colour patches, tall
  landmarks at different ranges, maybe a coastline. The goal is *"I can see where I'm flying"* — a legible,
  richly-featured world that reads at 1–5 km, gives a sense of speed/altitude, and orients the player.
- Keep it from anchored Parts (NOT voxel Terrain) per the existing rationale (no LOD-cull, controllable
  colours, build-safe — see the `BuildMap` comment). Bounded part count; deterministic placement (no rng).
- **Flight==balance:** a bigger/denser world reshapes the 1-v-4 (cover for crows, lanes for the eagle) — reason
  about it, and remember the PLAYER-flown crow has no terrain avoidance, so don't choke the combat lanes.
  Keep the spawn/combat zone (±1200) reasonably open.

**Acceptance:** flying high, the player sees a deep, legible landscape far into the distance that gives real
perspective and orientation; it doesn't tank perf (watch part count) and doesn't reintroduce crash-frustration
in the combat zone.

### 3. Verify AI crows MOB (regression just fixed — needs a Play)
Confirm the avoidance revert (above) makes the bots swarm the eagle without fleeing or crash-dying. If they
still don't press the attack, tune `Squad.avoidance.weight` down further and/or check `Boids` goal weighting.

---

## Guardrails (read before touching numbers)
- **Don't reopen the flight kernel** (`v1.0-eagle-flight`, human-verified) and **don't regress the confirmed
  camera/control feel** (`feedback-camera-control-feel`, `flight-camera-redesign-handoff`). The reticle work is
  HUD/input-layer; the aim-error math is the one place to be careful (ask #1 caution above).
- **Flight physics and balance are ONE system** (`feedback-flight-balance-inseparable`) — the map build-out and
  any crow tuning are balance changes; reason about the 1-v-4.
- **Server stays authoritative for combat** — the strike side/timing/hit live in `GameServer` (P6); the
  reticles are a client VISUAL aid only (read the local bank to light them; never send a strike direction).
- All Luau files start with `--!nonstrict`. **Refine incrementally; do not regenerate modules.**
- `.\build.ps1` is the wiring gate (it does NOT syntax-check Luau or run anything). **Studio Play is ground
  truth.** Commit as you land; update `CLAUDE.md`/memory when contracts change.

## Pointers (exact)
- **Reticles / aim:** `BirdController.client.luau` — reticle GUI build ~187–235, `computeMouseAim` ~752 (the
  `aimMarkerDistance` projection + `curBank` ~859), render block in `onFlightStep` ~932. Config:
  `GameConfig.Controls.aimMarkerDistance` (600), `aimCursorAreaFrac` (0.5), `Combat.bankStrikeThresholdDeg` (18).
- **Strike side mapping (server, already inverted):** `GameServer.classifyBank` (~860) + `StrikeArmedDir` Body
  attribute mirrored in `updateEagleStrikes`; HUD chips in `GameUI.client.luau` (`paintStrike`/`armedChips`).
- **Map:** `GameServer.BuildMap` (~251) + `SetupLighting` (~196, Atmosphere/Fog). `StreamingEnabled=false` in
  `default.project.json` + `BuildMap`.
- **AI crows:** `GameServer.updateAICrows` (~1307, the non-lethal slide), `avoidObstacle` (~1283),
  `squadGoal` (~1234), `GameConfig.Squad.avoidance`.
- **Memories:** `combat-directional-strike`, `feedback-camera-control-feel`, `mouse-aim-pursuit-model`,
  `flight-camera-redesign-handoff`, `feedback-flight-balance-inseparable`, `project-realscale-flight-goal`.

## How to work
Drive each item via the **`loop-orchestrator` skill** (roblox-game profile). `.\build.ps1` green is the wiring
gate; **Studio Play with Chad is the only behavioral gate.** Do the reticle UI (ask #1) and map build-out
(ask #2) as their own commits; verify the crow mob first (ask #3). Honor flight==balance and don't regress the
loved kernel/feel.
