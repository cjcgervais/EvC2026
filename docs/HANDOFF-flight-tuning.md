# HANDOFF — Flight mechanics + chase camera need a holistic, research-grounded redesign

**Created 2026-06-29.** For an agent with **cleared context**. Pair with `CLAUDE.md` (architecture/contracts),
`docs/RESEARCH.md` (how every flight number was grounded), `docs/HANDOFF.md` (overall status), and the
`mouse-aim-pursuit-model`, `flight-vertical-envelope`, `feedback-flight-balance-inseparable` memories.

## ✅ STATUS — IMPLEMENTED 2026-06-29 (awaiting human Studio verify)
The holistic redesign below was executed on a `deep-research` pass (now written up in **`docs/RESEARCH.md`
§v4** with citations). All six problems addressed: **P1** loop-commit (ride-the-edge AoA protection,
suspended while powered; aerobatic gate lowered) · **P2** symmetric deadzone+expo on both axes · **P3** PD
rate-damping in the instructor (engine now exposes `pitchVel/rollVel/yawVel`) · **P4** `inducedDragK 0.65→0.58`
(keeps the n² EM cost) · **P5** verified (nose-down + Shift already accelerates) · **P6** continuous
rate-limited full-3D chase direction + shortest-path `CFrame:Lerp` (no snap/flip through a 360° loop). Plus
the player's ask: **free-look is now a Space TOGGLE**. Remaining work = **press Play in Studio and validate
the acceptance criteria** (next section), tune against the §v4 targets, then re-tag the kernel. The original
brief is preserved below as the design record.

---

## Why this exists
Over this session the **mouse-aim control law**, the **energy/physics tuning**, and the **chase camera**
were iterated many times by live playtest feedback. We have reached the point where **band-aid tuning is
counter-productive** — each fix trades one symptom for another because the three systems are coupled and
none is grounded against explicit performance targets. The player has asked (correctly) to **stop patching
and do a holistic, deep-research-driven redesign**. **Do NOT band-aid. Model it. Ultrathink + deep-research,
then tune against targets.** Use the `loop-orchestrator` + `deep-research` skills per `CLAUDE.md`.

**Scope is the EAGLE solo-flight feel only** (the Crow + 1-v-4 balance pass is still downstream). But honor
the design thesis: every flight number is also a balance number (`feedback-flight-balance-inseparable`).

## The three coupled systems and where they live
| System | Code | Tunables |
|---|---|---|
| **Control law** (cursor → pitch/roll/yaw commands) | `src/client/BirdController.client.luau` → `computeMouseAim()` + the aim block in `onFlightStep()` | `GameConfig.Controls.aim*` |
| **Flight model** (lift/drag/grip/thrust/energy) | `src/shared/FlightPhysics.luau` → `:Update()` | `GameConfig.Flight.*` + `GameConfig.Profiles.Eagle` |
| **Chase camera** | `src/client/BirdController.client.luau` → `updateCamera()` | `GameConfig.Camera.*` |

### Current architecture (so you don't re-derive it)
- **Control law** is a *body-frame coordinated-flight autopilot*: the cursor's world direction (camera ray)
  is resolved into the bird's body frame as `localTarget`; ELEVATOR pulls toward its up-component, BANK +
  RUDDER roll the lift vector onto its right-component, with a wings-levelling term and an **AoA limiter**
  (`aimStallBandDeg`) that eases the pull near stall. Output is eased (`aimResponse`) and **summed with
  keyboard**. Two reticles: amber nose-cross (boresight) + green cursor ring. See `mouse-aim-pursuit-model`.
- **Flight model** is the v2 GRIP kernel (`flight-vertical-envelope`): real lift curve `CL=cl0+slope·a`
  with post-stall mush, drag polar `CD=CD0+k·CL²`, velocity-follows-nose **GRIP_RATE**, weathervane
  **STABILITY_RATE=0** (no auto-level), **aerobatic freedom** that suppresses the weathervane only **above
  `AEROBATIC_MIN_SPEED=110`** so loops are possible, powered climb + flap throttle, phugoid damping,
  service ceiling. Gravity is real-scaled (`GRAVITY_G`). **This kernel was HUMAN-VERIFIED earlier
  (`v1.0-eagle-flight`) but has since been retuned for "loft" — it is no longer in its verified state.**
- **Camera** is a *horizon-stabilised* chase: sits behind the bird's **horizontal heading** (`headBack`)
  and above it in world space, `CFrame.lookAt(..., worldUp)`, bank-tilt faded out when inverted, crest
  damping on fast facing-rotation.

---

## Problems to solve (player-reported, with root-cause hypotheses)

### P1 — Loops no longer complete ("now it cannot even loop")
**Hypothesis (three things gang up):** (a) the controller **AoA limiter** (`aimStallBandDeg`) cuts the
nose-up pull as AoA rises while climbing; (b) **energy bleeds in the pull** (induced drag, see P4) so the
bird slows fast in the climb; (c) FlightPhysics **disengages aerobatic freedom below `AEROBATIC_MIN_SPEED`
(110)** and the velocity-aligning grip/weathervane then auto-levels the nose toward the flight path → the
loop mushes out as speed decays. Net: slow → AoA up → pull cut → aerobatics off → no loop.
**Need:** a coherent *energy → loop-feasibility* model. Decide entry-speed for a clean loop, ensure the
controller **commits** to a started loop, and reconcile the AoA limiter with the aerobatic-speed gate so
they don't both fight the pull. Research: vertical-maneuver energy budgets, "corner speed", arcade-sim loop
handling.

### P2 — Vertical (pitch) needs the same deadzone + parabolic response curve as bank
Bank got a deadzone + expo ramp (`aimBankDeadzone`, `aimBankExpo`); pitch is currently near-linear. Player
wants **both axes on a consistent parabolic curve** — gentle near centre, **ramping up further from centre**
(War Thunder "nonlinearity", documented range ~1.0–2.5). Apply symmetrically **but** ensure the curve still
delivers full pitch authority at large deflection so it does not starve P1.

### P3 — Coordinated turn oscillates (climb+bank porpoise) instead of a sustained turn
**Hypothesis:** the control law is **pure proportional (P-only)** over an inertial plant (`rollInertia`,
smoothed control rates) plus the `aimApplied` easing plus the wings-levelling feedback loop = an
**underdamped 2nd-order system → limit-cycle oscillation** (reads as a porpoising climb/bank wobble).
**Need:** damping. Add **rate/derivative feedback (PD)** or design a critically-damped turn coordinator;
consider decoupling the leveller from the active turn. Research: aircraft turn-coordinator autopilots,
damped pursuit/PD controllers, avoiding pilot-induced oscillation.

### P4 — Energy retention too low, especially when pitching
Pulling = high CL = high induced drag = fast energy bleed; the player says pitching loses "way too much"
energy. **Tension with the EM design thesis** (hard maneuvers *should* cost energy) — so this is NOT "remove
drag", it's "**the magnitudes are mis-calibrated**". Re-derive the **lift curve + drag polar** against
explicit targets (cruise, corner speed, sustained-turn rate, loop entry speed, glide L/D) the way
`docs/RESEARCH.md` did originally, instead of eyeballing single knobs. This is the core deep-research item.

### P5 — Must be able to flap-thrust to GAIN SPEED in a negative (nose-down) attitude
Player wants: **nose-down + flap = accelerate.** Verify the throttle→thrust path (`FlightPhysics:Update`
flap/throttle block + `FLAP_DIVE_FADE_BAND`/`FLAP_DIVE_FLOOR`) lets a **positive** flap throttle accelerate
a dive and isn't being over-suppressed by the dive-flap fade. Define the intended thrust model across **all**
attitudes (climb, level, dive) and across the **sticky throttle** sign (`+`=up-thrust, `−`=down-thrust).

### P6 — Camera does a sudden ~180° snap arcing over the top of a loop
**Root cause:** `updateCamera()` bases the chase azimuth on the bird's **horizontal heading** (`headBack`).
Over the top of a loop the heading **reverses ~180°**, so `headBack` flips and the camera **snaps** to the
opposite side. (The `flat.Magnitude>0.08` guard holds heading through the vertical, but once past vertical
the heading is reversed → snap.) The earlier "behind the full-3D look" version instead **flipped over/under**
the bird at vertical — so the two naive references each have a discontinuity through a 360° loop.
**Need a holistic chase-camera model with NO discontinuity through a full loop**, "smooth, observable, and
controllable." Research 3rd-person flight-camera best practices and pick a principled one:
- **Spring-arm with position + rotation lag** (Unreal `CameraLag`/`CameraRotationLag`, Unity Cinemachine).
- **Critically-damped spring / `SmoothDamp`** on camera position toward a target offset.
- **Quaternion `slerp` of camera orientation with a max angular rate** (can't snap; rotates smoothly).
- A **continuous look-ahead / smoothed-orientation reference** (slerp the bird's full-3D orientation, then
  derive the offset) so there is no flatten-discontinuity and no heading-reversal snap.
Likely answer = rate-limited/critically-damped **position AND orientation**, decoupled, tuned so a full
loop reads smoothly and the player keeps situational awareness (the zoom-out to `maxDistance` already helps).

---

## Acceptance / desired feel (what "done" looks like)
1. From cruise/with throttle, **a clean vertical loop completes** and stays in a vertical plane.
2. **Both mouse axes** use a consistent parabolic response (deadzone + ramp), full authority at the edge.
3. A held side-cursor gives a **smooth, sustained, non-oscillating coordinated turn** (bank+yaw together).
4. **Energy retention** matches an explicit EM model (document the target numbers; maneuvers cost energy but
   not absurdly), and **flapping accelerates in any attitude**, including nose-down.
5. The chase camera is **smooth and controllable through a full 360° loop — no snap, no flip-over**.

## Current tunables & recent changes (uncommitted — `git diff` to see this session)
All changes this session are in the **working tree, uncommitted** (`git diff` the 6 `src/` files). The
flight/camera-relevant ones a redesign should rebase on or revert:
- `GameConfig.Flight`: `GRAVITY_G 2.0→1.3`, `AIR_DENSITY` base `0.033→0.044`. Unchanged but central:
  `AEROBATIC_MIN_SPEED=110`, `AEROBATIC_SPEED_BAND=40`, `GRIP_RATE=2.2`, `STABILITY_RATE=0`, `PHUGOID_DAMPING=2.1`.
- `Profiles.Eagle`: `clMax 1.6→1.95`, `stallAngleDeg 24→27`, `inducedDragK 0.85→0.65`, `flapThrust 520→600`,
  `maxStamina 140→240`, `staminaRegen 9→14` (×`GRAV_SCALE` where noted). `parasiticDrag=0.020`, `pitchRate=2.0`,
  `rollRate=3.2`, `rollInertia=0.55`, `glideSpeed=130`, `diveSpeedCap=320`.
- `Controls` (mouse aim): `aimMarkerDistance=600`, `aimResponse=9`, `aimDeadzone=0.02`, `aimBankDeadzone=0.12`,
  `aimBankExpo=2.2`, `aimRollGain=2.0`, `aimPitchGain=3.0`, `aimYawGain=0.6`, `aimLevelGain=0.9`,
  `aimStallBandDeg=7`, `flapThrottleRate=1.1`. (Removed older keys: aimMaxBankDeg/aimMaxPitchDeg/aimTurnHoldDeg/
  aimBankP/aimPitchP/aimTurnPull/aimExpo/aimZoneScale.)
- `Camera`: `maxDistance 340→800`, `zoomStep 16→24`, `crestAngRate 3.5→3.0`, `crestDamp 0.75→0.85`,
  `followSmoothing=0.18`, `bankTiltFactor=0.6`, `heightFactor=0.35`, `zoomTopDownHeight=0.55`.

Also added this session (keep/relocate as the redesign sees fit): **sticky flap throttle** (Shift up / Ctrl
down → `input.flapThrottle`, scales thrust/climb/dive/stamina/freq in the kernel; AI keeps the boolean path),
**flap HUD** (`_G.UpdateFlapUI`), **wingtip stall vortices** (`buildVortexTrails`/`updateVortexTrails`),
**free-look freeze** (holds the aim command so a maneuver continues while orbiting), **two-reticle mouse aim**.

## Suggested approach (per CLAUDE.md workflow)
1. **Deep-research first** (compose the `deep-research` skill): arcade-sim flight-model calibration & EM
   targets; mouse response curves / instructor design; turn-coordinator damping (avoid PIO); 3rd-person
   flight-camera math (spring arm, SmoothDamp, quaternion slerp, look-ahead). Cite, like `docs/RESEARCH.md`.
2. **Set explicit target numbers** (cruise, stall, corner speed, sustained/instantaneous turn rate, loop
   entry speed, glide L/D, climb rate) and derive the lift/drag/thrust constants from them — don't eyeball.
3. **Separate "instructor" from "plant":** tune the flight model alone (keyboard) to hit the targets, THEN
   layer the mouse autopilot (with damping + parabolic curves) on top, THEN the camera. Validate each in
   Studio (the only real test) before stacking the next.
4. Drive it through the **`loop-orchestrator`** skill (`roblox-game` profile), one system at a time.

> Interim note: the working tree currently **cannot complete a loop** (P1). If a playable interim is wanted
> before the redesign, the cheapest revert is to soften/disable the controller AoA limiter (`aimStallBandDeg`)
> and lower `AEROBATIC_MIN_SPEED`, but treat that as throwaway — the real fix is the holistic pass above.
