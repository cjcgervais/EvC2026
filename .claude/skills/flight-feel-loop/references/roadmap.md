# Flight-feel roadmap — the validated staged ladder

The end state (Chad's spec): a **decoupled deterministic-lag camera**, a **cascade
instructor** (screen-deflection → coordinated turn, damped on the right axes, with a
≤5° skid-snap and a target-derivative yaw kick, gains scheduled to airspeed), and a
**physics strike** (mass × velocity × timing × type). Grounded in two SEADS source docs
(`docs/roblox_crows_eagles_consult.md`, `Flight Controller Cascade Physics.txt`) and a
Fable 5 consult mapped onto EvC's CFrame kernel.

**Ordering law:** instrument → camera → cascade → strike. Each stage is ONE flyable,
revertable dial. Risk class: **[A]** pure-additive / ships inert (identity knob = today's
behavior) · **[F]** touches signed-off feel (extra care + explicit gate). The instrument
takes a BEFORE trace every stage so complaints attribute to a mechanism before Chad flies.

**Reconciliations baked in (don't re-derive these wrong):**
- Camera is NOT cleanly decoupled today — the aim reads camera state via the screen-
  circle clamp (BirdController ~945, ~981–1006). Stage 1 needs the fallback gate AND an
  instrument watch for a camera↔aim limit cycle.
- The ×3.46 dive bonus is LEGACY (`onAttackRequest`); the live strike is fully flat.
- Reuse the DEAD `COLLISION_SPEED_REF = 260` as the strike velocity anchor.
- Do NOT build: plant-inversion feedforward (no-op on this kernel), a rate-PI inner loop
  (the kernel IS the inner loop), an inertia probe (τ is analytic), or any micro-planet
  orbital physics (fiction on a flat world).

---

## Stage 0 — Finish the step-response instrument · [A] · DONE (needs Chad's zero-diff confirm)
- Change: F7 lateral / F6 vertical step injectors + a per-frame tracker (settle-time to
  ±2°, overshoot°, amplitude-gated reversals >1°, camera-gap τ), flushed via F9. In the
  delimited scratch block in `BirdController` + `_ScratchTele`.
- Knob: `STEP_DEG` (30). Instrument: validates itself — F6 (loved vertical channel)
  should show low overshoot / ~0 reversals; F7 (horizontal) should show the sail-past.
- Gate: press F7 in level flight → aim steps and a metrics row prints; with F7/F6 unused,
  normal feel is **identical** (zero-diff path). Revert: delete the delimited block.

## Stage 1 — Camera decouple · [F] · CHAD-GATED (supersedes CS-8's felt behavior)
- Change: retarget the camera ease (`BirdController ~581`) from `followDir` →
  `aimTargetDir`, with fallback to `followDir` when the aim is nil, **any flight key is
  held (CS-1)**, or `aimZoom.active`.
- Knob: `aimHeadingLag` (4.0). Instrument: the camera-gap channel decays as a clean
  exponential at rate ≈ `aimHeadingLag` (the "deterministic lag" proof); cursor
  screen-radius decays monotonically — any oscillation = the camera↔aim loop is live.
- Gate: rim-pinned sustained turn; arrival re-centres the cursor; **held-S keyboard loop
  with the cursor parked off-nose — camera must stay on the bird**; free-look exit still
  jump-free. Revert: retarget back (1 line).
- ⚠️ Requires Chad's sign-off first: it reverses the logged 2026-07-02 world-cursor
  hang-out decision (keeps the math; changes the feel to cursor-re-centres).

## Stage 2 — Heading-rate damping (THE fix) · [A] · ships aimHeadDamp = 0
- Change: add `− aimHeadDamp · headRate01` to the roll law (`~1125`), reusing the headRate
  math (`~1032–1035`) as **feedback added after the saturating P** (so rim-pinned
  full-deflection turns are untouched — no washout machinery). Normalize
  `headRate01 = clamp(headRate / profile.pitchRate, -1, 1)` — the same divisor family as
  the loved vertical channel's `pitchRate01` (in a banked coordinated turn heading rate is
  elevator-delivered, `≈ pitchVel·sinB`, bounded by `pitchRate`).
- Knob: `aimHeadDamp` (0 = identical to today). Instrument: 30° lateral step —
  overshoot and reversals fall (predict 1–2 reversals → 0–1, settle ≈ halves);
  **rim-pinned steady turn-rate UNCHANGED** on eagle AND possessed crow (saturation proof).
- Gate: "the nose lands on the cursor and stays — the sail-past is gone; small-input snap
  identical." Revert: knob → 0.

## Stage 3 — Retire the in-loop output-ease · [F]
- Change: split `aimResponse` → `aimResponseEngaged` for the aiming path (raise toward
  pass-through); keep 13 for the disengage ease-to-zero (`~1228–1231`, a safety behavior).
- Knob: `aimResponseEngaged`. Instrument: command→applied lag → ~0; per-frame applied-
  command delta RMS at rest must NOT spike (jitter proxy). Gate: crisper snap, no new
  twitch. Revert: knob → 13.

## Stage 4 — Skid-snap dual-mode (≤5°) · [F] · CHAD- + red-team-GATED (seam risk)
- ⚠️ **Corrected:** the live `aimBankDeadzone` is **0.006** (≈0.34°, GameConfig:905), NOT
  ~5°. So the skid band does NOT coincide with a zero-roll-P region — the ≤5° threshold is
  a genuine SEAM between two lateral laws, i.e. the S28b tombstone ("yaws but won't bank,
  lost its snap"). Design it as a SMOOTH blend (a weight ramping over a band, no step), and
  treat it as a real feel risk, not a free win.
- Change: over a smooth `|rgt|` blend band, add `yaw += −aimSkidGain·rgt − (ratio-locked
  damp)·yawRate01`, weight fading to 0 above the band. Roll law untouched; `levelAssist`
  gives the wings-level posture. (Yaw currently has NO rate damping — ship the damp
  ratio-locked to the P so it stays one knob.)
- Knob: `aimSkidGain` (0 = off). Instrument: 3° step settle time; sweep `rgt` across the
  band and confirm roll/yaw commands are CONTINUOUS (no step at the seam); centre reversal
  counter for limit cycles.
- Gate: "small deflections SNAP" with no mush at the seam; no wander at centred cursor.
  Revert: knob → 0.

## Stage 5 — Transient yaw kick · [A]
- Change: feedforward from the mouse cursor-swing `dYaw` (`~943` — the target's motion,
  NOT the error), first-order decay ~150 ms, active only in the skid band, capped so
  skid-P + kick ≤ 1.
- Knob: `aimYawKickGain` (0 = off). Instrument: snapshot latency (cursor jump 4° → nose
  within 1°); yaw-command jitter RMS unchanged when the mouse is still. Gate: snapshots
  line up immediately, no jitter. Revert: knob → 0.

## Stage 6 — Horizontal gain schedule · [A]
- Change: apply the loved S26e `speedScale` pattern (`~1074`) to the horizontal gains
  ("linked gains tied to forces on bodies").
- Knob: `aimTurnLowSpeedFloor` (1 = off). Instrument: matched step character at 80 vs 250
  studs/s. Gate: slow turns don't pump. Revert: knob → 1.

## Stage 7 — Strike telemetry · [A]
- Change: server per-contact log (relSpeed, `v_axis`, alignment, window position, dmg) in
  `updateEagleStrikes` / `processCollisions`. Knob: none. Gate: numbers sane in a normal
  fight. Revert: delete.

## Stage 8 — Velocity-direct strike scaling · [A] · ships strikeVelExponent = 0
- Change (`~1014`): `dmg = base × velFactor × directness × timing × massFactor`, anchored
  on `COLLISION_SPEED_REF = 260` so the reference closure returns today's 26/34 exactly;
  every exponent ships at its inert value. **Server-observed** velocity only (promote
  `processCrashes`' `_lastPos` delta), clamped to `diveSpeedCap` (anti-spoof).
- Knob: `strikeVelExponent`. Instrument: Stage-7 damage histogram vs the flat baseline;
  crow TTK unchanged at the anchor. Gate: stoop strikes feel meaty, lazy pecks weak; 4
  crows still win by mobbing (flight==balance). Revert: exponent → 0.

## Stage 9 — Talon axis + timing · [F] · CHAD-GATED (balance)
- Change (two flights): `talonAxisPitchDeg` (talon zone pitched below the velocity-centre,
  ~30–40°: `axis = Look·cosθ − Up·sinθ`), then `strikeTimingBonus`. Instrument: hit-rate +
  damage distribution from telemetry. Revert: each knob to its identity value.

## Stage 10 — Ram velocity band · flagged Chad decision · DEFAULT NO
- Keep the discrete `eagleHits` suicide-ram — its 3-ram readability is the signature
  lose-lose mechanic and is balance-critical. Only revisit on an explicit Chad ask.
