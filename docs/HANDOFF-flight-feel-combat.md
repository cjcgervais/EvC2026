# HANDOFF — Flight-feel polish + the directional-strike combat rework

**Created 2026-06-30** (Playtest-3 / "I found the secret" session). For an agent with **cleared context.**
Pair with `CLAUDE.md` (architecture + contracts), `docs/HANDOFF.md` (full history + the one locked decision),
`docs/HANDOFF-flight-sandbox.md` (the prior grind — some items carried over below), and the memories called
out under *Guardrails*. **Pressing Play in Studio is the only real test on this project — the player is the
human verifier.**

> **The eagle flight model is loved and locked** (`v1.0-eagle-flight`, human-verified). The player has been
> living in it and now knows it well enough to ask for *specific* feel + combat upgrades. His words this
> session: *"this is getting good… the team is going on a roll."* Six asks, grouped below. Five are
> feel/QoL/camera (low risk, mostly independent); **one is a real combat redesign** (P6 — the directional
> strike) that is **balance-critical** and must be reasoned against the 1-eagle-vs-4-crow matchup on every
> number. Land them and the game goes from "great to fly" to "great to *fight* in." 🦅

---

## ✅ ALL SIX ASKS LANDED — night shift 2026-06-30 (build-green, UNPLAYTESTED — needs Chad's Studio pass)
A fresh cleared-context agent worked the whole P1→P6 queue. `.\build.ps1` green throughout; none touch the
`v1.0-eagle-flight` aero kernel (input/camera/HUD/config + server-combat only). Two commits on `master`:
- **P1–P5 (commit `317f56b`)** — the low-risk feel/QoL pass, also the **checkpoint before P6** (revert here to
  drop just the combat rework):
  - **P1 HUD SPACE hint** — `GameUI` control hint is now a RichText line with **SPACE** gold-bold as the
    headline ("toggle FREE-LOOK"), un-staled from the old "hold SPACE"; every binding listed matches the build.
  - **P4 RMB aim/zoom** — right-click freed from "beak" → **hold RMB to zoom** (chase distance + FOV pulled in),
    works in chase AND free-look. Camera-only; mouse-aim cursor read untouched. New `Camera.aimFOV` (45),
    `aimDistance` (18), `aimZoomLerp` (0.22).
  - **P5 free-look "unstick"** — the orbit no longer inherits the heavy chase lerp: while free-looking it tracks
    near-1:1 via new `Camera.freeLookSmoothing` (1.0 — **the main fix**), `freeLookSensitivity` 0.35→0.7, and
    the orbit pivot pulled in via `Camera.freeLookDistance` (45) so sweeps aren't huge distant arcs.
  - **P2/P3 flap power + stamina (Eagle, reason 1-v-4)** — `flapThrust` 600→800, `flapClimbForce` 400→500;
    `maxStamina` 240→320, `staminaFlapCost` 6→5, `staminaRegen` 14→16. Mass kept 16 (momentum = identity);
    **Crow untouched** (its flap/stamina is a matchup lever). Shipped Option A (continuous force); **Option B —
    a wingbeat-phase "felt surge" per downstroke — is the juicy follow-up to prototype live** (watch porpoising).
- **P6 directional strike (commit `0df2a37`)** — see the P6 section below; full design in the
  `combat-directional-strike` memory. LMB-only; the eagle's **bank** picks left/right/forward; server reads the
  authoritative bank; each strike has its own startup→duration→cooldown + an offset cone that **parries a ram
  AND deals offensive damage** (one catch-or-hit/window). HUD = single STRIKE bar + L/F/R armed-dir chips.

**▶ WHAT CHAD MUST PLAYTEST / TUNE (the only real gate):**
1. **P5** — does free-look now feel crisp/near-1:1 (no "stuck")? If still laggy, raise `Camera.freeLookSmoothing`.
2. **P4** — RMB zoom reads cleanly in chase + free-look, releases back, doesn't fight the steering cursor?
3. **P2/P3** — flap has more punch + a longer leash, but stamina still ends the climb (not "free" power)?
4. **P6 — the big one (balance-critical, reason 1-v-4 on every number):** banking L/R/level + LMB throws the
   right strike with a visibly distinct window/downtime; a strike covers/kills a crow on that side but **leaves
   the other sides open** (2-angle test); the eagle **cannot spam-cover all sides**; the **offensive damage**
   (the lever to watch hardest) doesn't make 1-v-4 too eagle-favored — if it does, drop damage/reach/duration in
   `GameConfig.Combat.strikes`, or zero the offensive pass (defense-only) first. Tune the three
   windows/downtimes/cones live. Then commit the tuned numbers + re-tag if it earns it.

*(Carried-over still open, fold in opportunistically: `StreamingEnabled=false`, richer sandbox / Sandbox mode.)*

---

## ✅ Landed earlier 2026-06-30 (build-green — mouse-aim feel + cameras, PLAYER-CONFIRMED)
A live tuning pass with the player. All `.\build.ps1`-verified; none touch the aero kernel (input-shaping +
camera-only). **Where noted PLAYER-CONFIRMED, don't regress.**
1. **Mouse-aim: tiny deadzone, FULLY LINEAR ramp, more authority.** Player walked this live: *"too big a
   deadzone… more linearity… way less deadzone, full linearity, more mouse authority."* Final
   `GameConfig.Controls`: `aimBankDeadzone`/`aimPitchDeadzone` `0.10/0.05 → 0.006` (a hair); `aimBankExpo`/
   `aimPitchExpo` `→ 1.0` (linear, force ∝ offset — walked 1.8→2.5→1.5→1.0); gains up for authority
   `aimPitchGain 2.6→3.3`, `aimRollGain 2.0→2.6`, `aimYawGain 0.6→0.78`. Shaper is `BirdController.shapeAxis`.
   Tuning: jitter at centre → deadzone ~0.012; oscillation on a pull → raise `aimPitchDamp`/`aimRollDamp`.
2. **Aim cursor clamped to a big CENTRED circle.** Player: *"the cursor should not go beyond a certain
   circle… it should cover ~7/8 of the screen by AREA and be centred."* `computeMouseAim` clamps the reticle
   to a circle at the viewport centre with radius `√(aimCursorAreaFrac·W·H/π)`; new
   `GameConfig.Controls.aimCursorAreaFrac = 0.875`. Clamping `mouse` feeds both the steering ray and the drawn
   reticle. Tuning: smaller circle → lower the frac. *(If centring ever reads low, `GetMouseLocation` excludes
   the inset on that setup → change the clamp centre `cy` from `inset.Y+vp.Y/2` to `vp.Y/2`.)*
3. **Free-look HORIZON LOCK — PLAYER-CONFIRMED.** Player: *"when I bank, the free-look camera falls to the
   side."* `updateCamera` free-look branch rebuilds the up FRESH as world-up ⟂ the orbited view direction →
   free-look horizon is **world-level by construction**, can't inherit the bird's roll.
4. **Loop TURN-OVER (chase/mouse-aim) — PLAYER-CONFIRMED "perfect".** Player: *"in mouse mode, doing a loop
   the camera should turn over smoother/better."* Over a fast loop **crest** the camera now leans its up
   toward the **bird's own up** (`Camera.loopFollowUp = 0.8`) so it rolls *around with* the bird and arcs over
   the top, instead of the horizon staying world-flat while the bird inverts. Gated by the crest rate → **zero
   effect in normal flight** (horizon stays level there). `chaseDir` (the no-snap basis) untouched, so no
   azimuth-snap regression. Tuning: more follow → toward 1.0; less → toward 0.4; 0 = old behavior.
5. **Free-look pitch direction (mouse-up = look UP) + wider pole range — PLAYER-CONFIRMED.** He toggled the
   pitch sign twice and settled on **mouse-up = look UP** (mouse + arrows in sync). `FREE_LOOK_PITCH_LIMIT
   1.54→1.70` rad (~88°→~97°) so you can look straight up/down + a touch past, both ways, still well under π
   (no wrap/spin). If the horizon ever rolls at the very extreme, the pole is being crossed → trim the `1.70`
   constant down a few degrees.
6. **Central crosshair dot more transparent — PLAYER-CONFIRMED.** `GameUI` crosshair `BackgroundTransparency
   0.4→0.8` (faint dead-centre dot).
7. **Eagle given a proper WHITE TAIL — PLAYER-CONFIRMED.** `BirdBuilder` now has a per-bird `tailColor`
   (eagle = bright white `244,244,240`, the bald-eagle signature; crow stays dark) and a reproportioned fan
   (broader `r×1.5`, ~square plan `r×1.05`, thin, overlapping the body rear).

These are **independent of** P5 below (free-look pan "unstick"/smoothing) — that crisp-pan work is still open.

---

## The six asks (verbatim intent, decoded)

1. **Free-look motion "gets stuck."** *"I want to improve the motion around free look, it feels like it gets
   stuck."* → make the pan crisp/near-1:1 (refines P2 of the sandbox handoff with a sharper symptom).
2. **More power per flap.** *"more power for flaps."*
3. **More stamina for flapping.** *"more stamina for flapping."* (A deliberate shift — the player now wants a
   longer leash, not just punch.)
4. **Controls HUD must call out SPACE as the critical button.** *"hitting the space bar to toggle between
   views helps awareness a lot. So I'll make the controls HUD tell of this critical button."* (And the hint is
   currently **stale** — it says "hold SPACE" but free-look is a **toggle**.)
5. **Right-click = AIM (zoom).** *"implement right click is aim (zoom)… you can zoom anywhere with a right
   click. Depending on how you're flying / what you are watching you may want to zoom in."* (Frees right-click
   from its current "beak" binding.)
6. **Directional strike on left-click.** *"right click was talon strike — left click will serve for both. If
   the banking side the bird is flying to: left talon strike, right talon strike, or forward will determine
   the type of strike and its duration and downtime."* → **one attack button (LMB); the bird's bank picks
   which of three strikes fires, each with its own active duration + downtime.**

---

## Guardrails (read before touching numbers)

- **Flight physics and balance are ONE system** (`feedback-flight-balance-inseparable`). P2/P3 (flap power +
  stamina) and **P6 (the strike rework)** are **Eagle/combat** changes → reason about the **1-v-4** on every
  edit. The camera/HUD asks (P1/P4/P5) are feel-neutral but keep the eagle legible.
- **Do NOT reopen the flight kernel.** Every task here is input-layer, camera, HUD, config, or server-combat —
  the aero kernel (`FlightPhysics` lift/drag/grip math) and the eagle `Profiles.Eagle` flight numbers are
  human-verified (`v1.0-eagle-flight`). P2/P3 only touch the *flap/stamina* sub-block, which is a tunable, not
  kernel structure. `cl0` must stay > 0 (the precondition that makes the grip model safe).
- **Server stays authoritative for all combat** (anti-cheat). The client sends *intent* edges only; the
  server owns every timer and every hit test, reading its own authoritative `Body.CFrame`. Don't move hit
  detection or strike-type classification onto the client (P6 detail below).
- **All Luau files start with `--!nonstrict`. Refine incrementally; do not regenerate modules.**
- `.\build.ps1` is the wiring check (it does **not** syntax-check Luau or run anything). Studio Play is ground
  truth. Drive each item via the **`loop-orchestrator` skill** (`loop_skill/`, `roblox-game` profile) per
  CLAUDE.md; after each change → `build.ps1` green → player Play-test → tune.

---

## Suggested order (low-risk → high-risk; they're largely independent)

1. **P1 — HUD SPACE hint** (minutes, no logic). Unstale it + make SPACE prominent.
2. **P4 — Right-click aim/zoom** (camera-only; also *frees right-click* which P6 needs).
3. **P5 — Free-look "unstick"** (camera-only; the main feel ask).
4. **P2 + P3 — flap power + stamina** (Eagle config; tune live, reason 1-v-4).
5. **P6 — directional strike rework** (the big one: combat + balance + server authority). Do last, most
   playtest.

Do P4 before P6 (right-click must be free of "beak" before the strike rework collapses attacks onto LMB).

---

## P1 — Controls HUD: make SPACE the headline, and unstale it  ⬅ do first, trivial

**Why:** the player discovered that toggling free-look with SPACE is his key situational-awareness tool and
wants it surfaced. **And the current hint is wrong:** free-look became a **toggle** (session: redesign) but the
HUD still says *"hold SPACE."*

**Current code —** `GameUI.client.luau` ~line 458–469, the `controlHint` `TextLabel`:
```
controlHint.Text = "MOUSE aims (cross chases cursor)  ·  SHIFT/CTRL flap throttle  ·  hold SPACE free-look"
```

**Fix:**
- Reword to a **toggle** and lead with SPACE, e.g.:
  `"SPACE — toggle FREE-LOOK (look around!)   ·   RIGHT-CLICK aim/zoom   ·   LEFT-CLICK strike   ·   SHIFT/CTRL flap"`
- **Emphasize SPACE** so it reads as critical: brighter color, or split it onto its own brighter line above
  the rest (the label is bottom-center at `Position (0.5,-230),(1,-34)` — a second taller label or a richer
  string is fine; keep it `TextScaled`).
- Disambiguate "aim": the **mouse already steers flight** (`mouseAim = true`, the WT cursor-chase), and now
  **right-click also "aims"=zooms**. Word them distinctly — e.g. *"MOUSE steers"* for flight vs *"RIGHT-CLICK
  zoom"* — so the player isn't confused which "aim" is which.
- Add the LEFT-CLICK strike line only once P6 lands (until then keep it accurate to current combat).

**Acceptance:** the hint names SPACE as the toggle, stands out, and every binding shown matches what the build
actually does.

---

## P4 — Right-click = aim/zoom (works anywhere, incl. free-look)  ⬅ do before P6

**Player:** *"right click is aim (zoom)… you can zoom anywhere with a right click… you may want to zoom in."*

**Current state:** right-click (`MouseButton2`) is bound to **beak** in `BirdController` `InputBegan`/`InputEnded`
(~lines 328 & 354 → `setWeaponHold("beak", …)`). P6 removes the L/R weapon-hold scheme entirely, so **right-click
is being freed.** Repoint it to a hold-to-zoom.

**Design:** **hold RMB → zoom in** (a closer look at whatever you're flying toward / watching), **release →
return.** It must work in **both** the normal chase cam **and** free-look ("zoom anywhere"). Implement as a
tweened zoom factor folded into the camera step — pull the chase distance toward a near value and/or narrow the
FOV. This is purely a *camera* change; it must not touch flight input or grab the cursor differently (the
mouse-aim cursor read in `onFlightStep` must keep working — verify RMB-hold doesn't fight `LockCenter`).

**Where:**
- Input: `BirdController` `InputBegan`/`InputEnded` — replace the `MouseButton2 → setWeaponHold("beak", …)`
  pair with `aimZoom.active = true/false` (add an `aimZoom = { active = false, factor = 0 }` state next to
  `cameraState`/`freeLook`).
- Camera: in `updateCamera` (~line 432+), where `targetDistance` is computed from `speedBase + userZoom`, also
  blend toward a near aim distance when `aimZoom.active` (lerp a `aimZoom.factor` 0→1 by `Camera.aimZoomLerp`
  per frame), e.g. `targetDistance = lerp(targetDistance, Camera.aimDistance, aimZoom.factor)`, and blend FOV
  toward `Camera.aimFOV`. In the **free-look branch** (~line 491) apply the same factor to the orbit pivot
  radius (`dist`) so RMB tightens a free-look inspection too.
- Config: add to `GameConfig.Camera`: `aimFOV = 45` (from `baseFOV 70`), `aimDistance = 18` (or a fraction of
  base), `aimZoomLerp = 0.25`. Keep it clamped within `[minDistance, maxDistance]`.

**Note vs existing FOV logic:** `Camera` already sets `baseFOV/diveFOV/climbFOV` — make sure the aim-zoom FOV
blend composes with (doesn't get stomped by) the speed/attitude FOV. Simplest: compute the attitude FOV first,
then `Lerp` toward `aimFOV` by the aim factor last.

**Acceptance:** holding RMB smoothly zooms in for a closer read of a target/horizon and releases back, in both
chase and free-look, without disturbing flight or the steering cursor.

---

## P5 — Free-look "gets stuck": make the pan crisp & near-1:1  ⬅ the main feel ask

**Player (Playtest-3):** *"it feels like it gets stuck."*  **(Playtest-2):** *"hard to smoothly navigate all
around… I want War-Thunder-arcade feel… it feels limiting."* Same target as the sandbox-handoff **P2**, now
with a sharper word: **"stuck."**

**Root cause — the orbit reuses the heavy chase smoothing.** In `updateCamera` the final
`camera.CFrame = camera.CFrame:Lerp(targetCF, alpha)` uses `alpha` derived from `followSmoothing = 0.18`
(~16%/frame toward target). In free-look that lag reads as **molasses / "stuck"** — you move the mouse and the
view crawls after it. Compounding: **`freeLookSensitivity = 0.35`** (·0.01 in the handler ≈ 0.0035 rad/px) is
low, and the **orbit pivot = full chase distance** (far back at speed) so sweeps are big distant arcs.

**Fix — all gated on `freeLook.active`, all camera-only (don't touch flight, don't regress the no-flip loop cam):**
1. **Crisp orbit smoothing.** Add `Camera.freeLookSmoothing` (~0.6–1.0) and use it for the final lerp **only**
   when `freeLook.active` (so the orbit tracks the mouse near-1:1; chase keeps its 0.18). This is the single
   biggest "unstick."
2. **Higher sensitivity.** Raise `freeLookSensitivity` (try 0.6–0.9); consider separate yaw/pitch values and a
   gentle accel curve. **Keep the corrected pitch sign + the arrow-key parity** from
   `docs/HANDOFF-freelook-fixes.md` (mouse `+Delta.Y`, arrows flipped to match) — **don't reinvert them.**
3. **Pull the orbit pivot in.** While free-looking, clamp the orbit radius (`dist` in the free-look branch,
   ~line 491) to a comfortable near value so the sweep is controllable, not a huge twitchy arc around a distant
   pivot.
4. **Check the pitch clamp.** `FREE_LOOK_PITCH_LIMIT` (~88°) — confirm hitting straight-up/down feels like a
   natural stop, not a jarring "stuck." Leave as-is unless it reads bad after 1–3 (the smoothing lag is the
   real culprit).
5. *(Optional WT polish)* a touch of pan **ease-out momentum** on the orbit.

**Design call (already recommended):** stay **orbit-the-bird** (what WT arcade actually does) and just make it
crisp — lower risk than a head-look rewrite. Only explore head-look if the player still wants it after 1–3.

**Acceptance:** the player can whip the view around to "check six" and back **smoothly, 1:1, no stuck/lag**,
the bird stays legible enough to keep flying, and free-look no longer "feels limiting." (Mouse-aim chase cam +
the no-flip loop camera unchanged.)

---

## P2 — More power per flap (Eagle; reason 1-v-4)

**Player:** *"more power for flaps."*

**How flap works today** (`FlightPhysics:Update`): the sticky flap throttle (Shift up / Ctrl down) → `flapPow ∈
[0,1]` scales a **continuous** forward force `flapThrust` along the nose, plus a vertical `flapClimbForce` when
nose-up. The wingbeat animation is cosmetic — thrust is a steady force. Eagle numbers in
`GameConfig.Profiles.Eagle`: `flapThrust = 600·GRAV_SCALE`, `flapClimbForce = 400·GRAV_SCALE`, `mass = 16`.

**Fix:**
- **Option A (simple):** raise `Eagle.flapThrust` (600 → **~800**) and/or `flapClimbForce` (400 → ~500) for
  more punch and climb. **Do NOT lower `mass`** — mass is the eagle's momentum / energy retention and its
  boom-and-zoom identity (raised 8→16 on purpose). Punch comes from thrust, not lightness.
- **Option B (juicy, recommended to prototype):** modulate thrust by the **wingbeat phase** (`flapPhase`) so
  each downstroke is a **felt surge** — literally "power *per flap*." Localized change in the flap branch; keep
  the *average* thrust sane and gate behind playtest (watch for porpoising; `PHUGOID_DAMPING` helps).

**Balance:** flap power is the eagle's **energy engine** — more of it = faster re-acceleration after a
turn/zoom = stronger boom-and-zoom = harder for crows to catch. The 1-v-4 counter-levers live with the **crows**
(numbers, possession, formation, collision trades) — **do not auto-scale Crow flap** with the eagle's.

---

## P3 — More stamina for flapping (Eagle; longer leash, still a limiter)

**Player:** *"more stamina for flapping."* A deliberate shift: he now wants to flap longer, not just harder.

**Today** (`Profiles.Eagle`): `maxStamina = 240`, `staminaFlapCost = 6/s`, `staminaRegen = 9/s` → ~23 s
sustained flapping (the current limiter). The flap/stamina drain lives in `FlightPhysics:Update`.

**Fix:** widen the budget — e.g. `maxStamina 240 → ~320`, and/or `staminaFlapCost 6 → ~5`, `staminaRegen` up a
touch → noticeably longer sustained flapping with quicker recovery. **Keep stamina the limiter** (not infinite
outside Sandbox mode): "more power" (P2) must not become "more *free* power" — if P2 adds punch, the longer
stamina should still end from fatigue or the ceiling, not never. **Eagle-only** — changing **Crow** stamina
shifts the 1-v-4, so leave it for the dedicated matchup pass.

**Acceptance (P2+P3 together):** a flap gives a satisfying *felt* surge (P2) and you can sustain flapping
meaningfully longer before fatigue (P3), while the boom-and-zoom identity and "stamina is the leash" both
survive. Re-read `research-flight-balance-findings` before settling the numbers; tune live in Studio.

---

## P6 — Directional strike on left-click (THE combat rework — balance-critical) ⬅ do last, most playtest

**Player:** *"left click will serve for both. The banking side the bird is flying to — left talon strike, right
talon strike, or forward — determines the type of strike and its duration and downtime."*

This is the session's **big** change and it is **pure central-thesis**: *the way you fly chooses your attack.*
It replaces the current two-button hold-to-extend defense with **one button (LMB) whose effect is selected by
the eagle's bank.**

### What it replaces (current combat — read first)
`GameConfig.Combat` + `GameServer` (`updateEagleWeapons`/`stepWeapon`/`onWeaponHold`/`tryParry`/`processCollisions`):
- Crow's only attack = **suicide ram**: a committed eagle↔crow contact above `COLLISION_SPEED_MIN` **always
  kills the crow** and costs the eagle one of `eagleHits` (= `health/eagleHits` = 33) **unless parried.**
- Eagle parries by **holding** a weapon extended — **LMB = talon** (wide 100° cone), **RMB = beak** (narrow
  50° cone). While `active` (past `startup`) and not-yet-`caught`, a crow inside the cone dies, eagle unharmed;
  **one catch per window**; release/drain → `cooldown`. All timers server-owned; client sends `WeaponHold`.
- HUD: two meter rows, TALON (left) + BEAK (right), fed by `Talon/BeakMeter`/`…Active` Body attributes
  (`GameUI` ~line 571–620, 781–783).

### The new model
- **LMB triggers a STRIKE** (an edge / tap, not a hold). The strike **type** is chosen by the eagle's **current
  bank angle** at the instant of the click:
  - bank **left** (beyond a threshold) → **LEFT talon strike** (cover cone offset to the bird's left-front)
  - bank **right** → **RIGHT talon strike** (cone offset right-front)
  - roughly **level** → **FORWARD strike** (narrow front cone — the committed head-on, beak-flavored)
- **Each type has its own `startup` → active `duration` → `cooldown` (downtime)** — exactly the player's "its
  duration and downtime." Forward = quick/narrow/short window; left/right talon = the bread-and-butter (wider
  cone, tuned window/reset).
- During a strike's **active window**, the covered cone both **parries an incoming ram** (crow dies, eagle
  unharmed — the old catch) **and** (recommended) **deals offensive damage** to any crow inside the cone within
  reach (revives the dormant `talonDamage`/`beakDamage` so the eagle can *hunt*, not only counter). One
  catch/hit per window stays.

### Why this is good balance (1-v-4) — the reasoning you must preserve
The eagle can only be banked **one way at a time**, so it can cover/strike **one angle per commitment**. Four
crows attacking from spread angles → striking left leaves right/rear open → **the swarm still wins by
saturation**, which is the whole asymmetry. Directionality *sharpens* the existing "one catch per window /
multi-angle beats one parry" lever instead of weakening it. Tune the three windows/downtimes so a skilled eagle
covers a read but **cannot spam-cover all sides** (the research guardrail: >50% single-angle uptime = the
"always-on" trap). The offensive-damage option is the lever to watch hardest — it gives the eagle a *proactive*
kill; if it makes 1-v-4 too eagle-favored, dial damage/reach/duration down or make LMB defense-only first and
add offense in a follow-up.

### Implementation (keep the server authoritative)
1. **Client (`BirdController`):** remove the `MouseButton1→talon` / `MouseButton2→beak` hold mappings (RMB went
   to P4 zoom). On **LMB press edge**, fire a new **`Strike` RemoteEvent** (intent only — no direction, no hit
   claim). Optionally show a local "armed direction" reticle from the live bank for feel, but **send nothing
   the server must trust.**
2. **Server (`GameServer`)** owns everything:
   - On `Strike` from the possessed eagle (rate-limited like the old attack/`ATTACK_COOLDOWN`), read the
     **authoritative** roll from `entry.body.CFrame` to classify `left | right | forward` against
     `Combat.bankStrikeThresholdDeg`. **Never trust a client-sent direction.**
   - Run a per-type timer state machine (generalize `stepWeapon`/`newWeaponState` to a single `strike` slot
     with the chosen type's `startup/duration/cooldown`; ignore new triggers while in `cooldown`).
   - Generalize `tryParry` so the active cone is **offset** by the strike type (`coneOffsetDeg`: left −X°,
     right +X°, forward 0°) with that type's `coverHalfAngleDeg`. A ramming crow inside the *offset* cone is
     caught. Add the offensive pass (if chosen): any crow inside the offset cone within `reachFraction × reach`
     takes `talonDamage`/`beakDamage`.
3. **Config (`GameConfig.Combat`):** replace `weapons = { talon, beak }` with `strikes` keyed by type, plus a
   bank threshold. Starting points (PLAYTEST-PROVISIONAL — reason 1-v-4):
   ```lua
   bankStrikeThresholdDeg = 18,   -- |roll| beyond this picks a side; within = forward
   strikes = {
     left    = { startup = 0.12, duration = 0.45, cooldown = 1.2, coverHalfAngleDeg = 70, coneOffsetDeg = -55, damage = "talon", reachFraction = 0.7 },
     right   = { startup = 0.12, duration = 0.45, cooldown = 1.2, coverHalfAngleDeg = 70, coneOffsetDeg =  55, damage = "talon", reachFraction = 0.7 },
     forward = { startup = 0.10, duration = 0.30, cooldown = 1.6, coverHalfAngleDeg = 40, coneOffsetDeg =   0, damage = "beak",  reachFraction = 0.8 },
   }
   ```
   (Keep `eagleHits`, the suicide-ram model, `COLLISION_SPEED_MIN`, and the per-attacker cooldown.)
4. **HUD (`GameUI`):** replace the two TALON/BEAK rows with a **single STRIKE meter** (ready / active /
   cooldown) and ideally an **armed-direction indicator** (◀ L / ▲ F / R ▶) lit by the current bank, so the
   player can see which strike a click will throw. Repoint the Body attributes the server mirrors (one
   `StrikeMeter`/`StrikeActive`/`StrikeArmedDir` instead of `Talon/Beak…`).
5. **Remotes contract (update `CLAUDE.md`):** add `Strike` (C→S, edge). Retire/neutralize `WeaponHold` and the
   legacy `AttackRequest` (leave harmless or remove + delete their server handlers). Grep `WeaponHold`,
   `onWeaponHold`, `tryParry`, `Talon`, `Beak` before deleting.

**Acceptance:** banking left + LMB throws a left talon strike, banking right a right strike, level a forward
strike — each with a visibly distinct active window + downtime; a strike covers/kills a crow on that side and
**leaves the other sides open** (a 2-angle test: cover one, the other still rams home); the eagle cannot
spam-cover all angles; the 1-v-4 still feels like the crows can win by swarming. Server-authoritative (no
client can fake a direction or an always-on cone). **This needs the most playtest — tune the three
windows/downtimes/damage live against the matchup.**

---

## Carried over from `docs/HANDOFF-flight-sandbox.md` (still open — lower priority, don't lose)

These weren't done before this session and remain valuable; fold in opportunistically:
- **Streaming / render-at-speed (old P1):** `Workspace.StreamingEnabled` is never set → likely defaulting ON →
  late map pop-in at stoop speed. Set it **false** (only ~26 anchored map parts; streaming gives zero benefit).
  `default.project.json` `Workspace.$properties` or server-side in `BuildMap`. *(If the player still reports
  pop-in after P5, this is the fix.)*
- **Richer sandbox map + Sandbox mode (old P3):** mid-field parallax/texture for a *sense of speed* + a
  `GameConfig.Sandbox = { enabled, … }` flag that skips AI-crow spawn / round flow / makes stamina forgiving so
  flight feel can be tuned without combat noise. **A Sandbox mode would make P2/P3/P5 testing much cleaner — consider doing it early.**

---

## Pointers (exact)
- **Input / strike / zoom / free-look:** `src/client/BirdController.client.luau` — `InputBegan` (~line 326,
  the MouseButton1/2 mappings to replace), `InputEnded` (~line 352), `InputChanged` free-look + wheel
  (~line 362), arrow-key free-look (~line 382), `setFreeLook` (~line 264), `updateCamera` (~line 432,
  free-look branch ~line 491), `setWeaponHold` (~line 95 — retire). Mouse-aim cursor read in `onFlightStep`
  (~line 681, 794) — verify P4 zoom doesn't fight it.
- **Camera tunables:** `GameConfig.Camera` (~line 457): `followSmoothing 0.18`, `freeLookSensitivity 0.35`,
  `baseDistance/minDistance/maxDistance`, `baseFOV/diveFOV/climbFOV`. Add `freeLookSmoothing`, `aimFOV`,
  `aimDistance`, `aimZoomLerp`.
- **Flap / stamina:** `FlightPhysics.luau` `:Update` (flap & stamina branches); numbers in
  `GameConfig.Profiles.Eagle` (`flapThrust 600`, `flapClimbForce 400`, `maxStamina 240`, `staminaFlapCost 6`,
  `staminaRegen 9`, `mass 16`). **Eagle only.**
- **Combat (P6):** `GameConfig.Combat` (~line 300–334, the `weapons` table → `strikes`); `GameServer` —
  `newWeaponState`/`stepWeapon`/`updateEagleWeapons` (~line 844–902), `onWeaponHold` (~905), `tryParry`
  (~915), `processCollisions` (~944), Remotes setup (~line 373 `event("WeaponHold")`), `onAttackRequest`
  (~796, legacy). HUD: `GameUI.client.luau` weapon meters (~line 571–620, 781–783) + control hint (~458).
- **Context:** `docs/HANDOFF.md` (history + the locked standalone-bird decision), `docs/RESEARCH.md`
  (§v3 real-scale, §v4 camera/instructor), `docs/HANDOFF-freelook-fixes.md` (the 3 confirmed free-look fixes —
  **don't regress**). Memories: `flight-vertical-envelope`, `flight-camera-redesign-handoff`,
  `mouse-aim-pursuit-model`, `feedback-flight-balance-inseparable`, `research-flight-balance-findings`,
  `project-realscale-flight-goal`.

## How to work
Drive each item through the **`loop-orchestrator` skill** (roblox-game profile). `.\build.ps1` green is the
wiring gate; **Studio Play with the player is the only behavioral gate.** Commit P1–P5 as they land (low risk);
**checkpoint before P6** (it's a combat/balance redesign — easy revert if a number wrecks the matchup). Update
project memory + the `CLAUDE.md` Remotes contract when P6's `Strike` event lands. Honor flight==balance on
every combat/flap/stamina number. **Don't regress the loved kernel, the confirmed free-look fixes, or the
no-flip loop camera.**
