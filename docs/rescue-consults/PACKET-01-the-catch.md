# Fable Consult Packet 01 — THE CATCH (Phase 0)

> Fable 5 game-design consult, S32 (2026-07-13). Grounds the Phase-0 build of the
> sacred slow-mo auto-catch. Numbers are starting points (PLAYTEST-PROVISIONAL);
> ground truth is Chad's Play. Companion agent to continue: `aab9baea4a0b55c3a`.

## A) THE CATCH BEAT — timing table (all times REAL seconds; sim never dilates)

| T (real) | Beat | Numbers |
|---|---|---|
| T−0.40 | **THE TELL.** Squirrel stops waving, plants feet, wide eyes, "hup!" inhale | Fires on predicted time-to-trigger ≤ 0.40s (`distToSphereSurface/closingSpeed ≤ 0.4`) AND gate passes. LATCHES ≥1.2s once planted — a flickering tell kills the beat |
| T+0.00 | **TRIGGER.** Sphere entry | Radius **28 studs** (×1.5=42 FTUE catches 1-3). Gate: closing speed ≥ **52** (40% of 130 cruise), measured as rel-velocity component TOWARD squirrel. Re-check every frame inside. Gate on carry capacity too |
| +0.00→0.12 | Slow-mo ease-in to **0.25×** presentation; chord swells; wind ducks ~20%; desat ramps 0.15s | Ease-in 0.10-0.12s FAST attack (quad-out) |
| +0.05 | **LEAP.** Ballistic arc | Solved to intercept eagle's predicted talon pos **0.55-0.80s** ahead (scale airtime w/ closing speed, clamp 0.5-0.85). Apex **8-12 studs** above perch. Re-fit every frame, smooth target ~10Hz, cap per-frame correction; stronger homing only in final 0.15s |
| ~+0.40 | **APEX.** Starfish "I'M FLYING" pose (screenshot frame) | Hold pose ±0.15s |
| +0.60-0.80 | **CONTACT→POMF.** Scoop flourish, feather burst + gold ring, hit-stop, POMF | Contact = **arc-time-complete, NEVER a distance check**. Hit-stop **3 frames (~50ms)**. POMF + burst + hit-stop + visual contact all land the SAME frame. Scoop = 5-10° bank-dip added to RENDERED pose only |
| +0.05→0.25 | **SNAP-BACK.** Time whips to 1.0× over **0.20s** (quad-in), wind whoosh, saturation returns, GOTCHA stamp + points | Asymmetric: attack 0.12s, release 0.20s. The whip is the exclamation point |
| +0.25→0.65 | Squirrel scrambles to back (0.4s slide + mote trail) | gray-box teleport-with-trail ok |
| ~+1.10 | **"…woohoo!"** | Fixed 0.5s AFTER snap-back completes (comedy timing) |

**Load-bearing:** 0.4s latched tell · near-zero rel-motion at apex (free if intercept right) ·
single-frame POMF sync · hit-stop 2-4 frames (≥6 = lag) · 0.2s whip · 0.5s woohoo delay.
**Safe to guess:** sphere radius 24-32 · gate 40-50% · desat amount · FOV delta · cant · apex height · chord voicing.

## B) CLIENT-SIDE SLOW-MO WITHOUT TOUCHING THE SIM
**Core insight — slow-mo is nearly FREE:** camera chases the bird, so the only in-frame motion is
squirrel-relative-to-eagle. The intercept solve drives that rel-velocity → 0 at apex. A real-time
object with ~zero rel-motion wearing dilated animation **IS** slow-mo. **NEVER dilate world translation**
(that is the only thing that causes "eagle flies away while squirrel floats" — don't slow the squirrel's
real trajectory and it can't happen).
Dilate (all presentation): (1) animation playback 0.25×; (2) `ParticleEmitter.TimeScale=0.25`;
(3) audio `PlaybackSpeed 0.5` + EQ shelf off highs, duck wind to 20% — **catch chord EXEMPT** (plays real
tempo over slowed diegetics = the film-grammar contrast); (4) camera decoration **FOV −5°** + ease **~15%
closer** + **4° cant** + vignette + desaturate-all-but-pair; (5) desat+vignette+chord = the grammar the
brain reads as slow-mo.
**Camera decoration without fighting the LOCKED chase:** compute chase CFrame as today, then apply a PURE
post-transform `render = chase * CFrame.new(0,0,-dz) * CFrame.Angles(0,0,cant)` + FOV write. Offset is a
pure function of **beat-time** (ease-in 0.3s, hold, ease-home 0.4s), never reads input, never feeds aim/
control frame, always returns to identity. Cap magnitudes, clamp envelope to beat duration.
Caveat: at 390 dive pass the window is short + flow violent → push FOV to −8° for fast passes only; report back.

## C) KID FLOOR + SKILL CEILING (same mechanics)
**Floor (5-yo):** 28-stud sphere ≈ 3.5 wingspans, ×1.5 FTUE. Floor lives ABOVE canopy, depth UNDER it
(world design, not difficulty). Gate forbids hover-camping, not kids — flying AT the squirrel passes it.
Too-slow → cheerful "go around!" gesture, no fail sound/red. Catch guaranteed, arc self-fits, crashes bounce.
**Ceiling (15-yo):** style meter = existing Updraft line-riding scorer retargeted (skim/thread charges a
meter, ~2s decay half-life). On catch `styleMult = 1+meter` cap ×3. Speed tiers: ≥60% "SWIFT!", ≥90%
"BLAZING!". **Base points generous + identical for all; style lands as a SEPARATE 2nd stamp 0.3s after
GOTCHA.** Never gate catch/slow-mo on style. Beacon = vertical sparkle column (300+ studs, colorblind via
brightness) + spatial squeak + frantic-wave/orange near fire. Under-canopy squirrels get richer base value.

## D) PHASE-0 BUILD ORDER (validate the "aww" earliest)
1. **Kinematics, zero juice:** one bean-squirrel on a floating perch, empty sky. Trigger→arc→attach→back-ride.
   Fly it YANKING the stick violently — intercept must be unbreakable before juicing.
2. **Sound** (before slow-mo — half the aww, an hour of work): POMF + chord + hup on real beats.
3. **Slow-mo presentation layer** (anim dilation, TimeScale, FOV/desat envelope, snap-back whip).
4. **The 0.4s latched tell.**
5. GOTCHA stamp, back-ride wave, delayed woohoo.
6. 10 squirrels on primitive trees (2-3 under-canopy), waterfall Thermal column + pad + batch counter,
   2:00 clock + score, 1:00 scripted beacon expiry.

**Single most important:** the CONTACT FRAME — squirrel meets talon on the EXACT frame POMF/burst/hit-stop/
stamp fire. Sync IS the juice; 100ms slop reads broken forever.
**Most common failure:** last studs read as a SNAP (squirrel teleports into talon — contact was a distance
check firing early/late, or re-fit lagged a yank). Pre-empt: contact=arc-time-complete; solve to the TALON
not body center; blend final 10-15% with a guaranteed convergence lerp. 2nd: slow-mo overstaying — keep tight.

## E) SOUND — gray-box from Roblox-available audio
Two tricks: any tonal sample → any interval via `PlaybackSpeed` (major 3rd ×1.26, 5th ×1.5); tween
PlaybackSpeed while playing = pitch-bends.
- **Catch chord:** soft ping (`rbxasset://sounds/electronicpingshort.wav`) ×1.0 then ×1.26, 120ms apart,
  under Reverb, volume swell 0.6s.
- **"Hup!":** `swoosh.wav` / `action_jump` ×1.9-2.2, short quiet.
- **POMF:** `splat.wav` ×0.6 + EQ cut highs; layer `action_jump_land` ×0.8 + quiet `bass.wav`.
- **GOTCHA:** ping ×1.0 then ×1.5, 80ms apart + `flashbulb.wav` sparkle.
- **Woohoo:** tonal sample PlaybackSpeed tweened 1.2→2.0 over 0.3s; ±15% random per squirrel = voice variety.
- **Snap-back whip:** `swoosh.wav` ×1.2 on time-snap frame; wind loop pops to full.
- Verify each rbxasset id resolves in Studio (legacy list shifts); Creator Store free SFX strictly better if allowed.

## IF YOU ONLY GET THREE THINGS RIGHT
1. **Contact is ONE frame:** squirrel-meets-talon + POMF + burst + hit-stop + stamp, same frame, arc-time not distance.
2. **Never dilate world motion:** slow-mo = dilated anim/FX/audio + FOV/desat grammar over a real-time convergence whose rel-velocity naturally → 0. The intercept solve IS the slow-mo.
3. **The tell is 0.4s and latched:** predicted-time-based, holds once planted, built BEFORE calling the beat done — it's the heart and the piece everyone builds last and ruins.

## REPORT BACK for Packet 02
1. Airtime distribution cruise vs dive; does re-fit visibly bend under max yank?
2. Frame-count audit of POMF sync (visual contact vs audio vs burst).
3. Did slow-mo READ as slow-mo or "a vignette happened"? Chad's words on the tell (did he notice the squirrel seeing him?).
4. Catches per 2-min round; at which catch # did the ritual first feel long?
5. Did the closing-speed gate ever block an earnest kid approach? What did a full-dive catch look like (FOV/flow)?
6. Which rbxasset ids actually resolved.
