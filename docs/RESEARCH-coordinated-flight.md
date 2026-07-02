# RESEARCH — Coordinated flight via the mouse-aim instructor (S28)

**Question:** How should a War-Thunder-style mouse-aim "instructor" over a no-auto-level 6DOF
kernel be STRUCTURED to achieve smooth, deterministic coordinated flight — snappy for small aim
errors, rate-limited-but-smooth coordinated catch-up for large errors, NO heading overshoot, NO
jitter — replacing three independent per-axis PD servos?

**Method:** deep-research workflow, 2026-07-02 (run `wf_46dddd98-a2e`): 5 research angles → 21
primary sources fetched → 102 claims extracted → top 25 adversarially verified by 3-voter panels
→ **22 confirmed, 3 over-claims refuted (0-3 / 1-2)**. This report is the verified synthesis.
Commissioned by Chad's S28 standing directive after S27's servo patches rubberbanded (HANDOFF
COLD START; the S27 porpoise research is `docs/RESEARCH-instructor-turn.md` and stays valid —
its bank→pitch feedforward is a component of this architecture).

---

## The verdict (one paragraph)

The literature converges on ONE architecture: a mouse instructor should be a **cascaded, coupled
bank-to-turn (BTT) controller**, not three per-axis servos. An **outer guidance law** converts
the aim error into a commanded turn RATE through a **shaped command model** (ArduPilot's
"sqrt-controller": linear for small errors = snappy; sub-linear with a bounded deceleration for
large errors = cannot overshoot). A **middle stage** inverts the coordinated-turn kinematics
(`φ_d = atan(V·ψ̇_d / g)`) to get ONE commanded bank from that turn rate, with the bank command
itself **rate-limited so the outer law respects the roll loop's lag** — the Georgia Tech
backstepping paper shows mis-knowing this lag is exactly what produces low-damped heading
overshoot (our "reticle sails past the cursor"). An **inner law** then servos the BANK to the
command (bank error — NOT cursor error), adds coordinating yaw from the SAME turn command, and
the KEPT `(sec(bank)−1)` pitch feedforward is the elevator/load-factor term that sustains the
turn. Coordination becomes an *achieved property of the coupled design* (Lin & Yueh; NASA CBTT),
damping lives in the *command trajectory* instead of derivative-on-error (which is what removes
both the jitter amplification and the snap-vs-overshoot tradeoff), and the tuning surface
collapses to ~3 knobs (aggressiveness, arrival accel limit, small-error cone).

## Verified findings (all 3-0 unless noted)

1. **BTT autopilots are structurally COUPLED multivariable controllers.** Cross-coupling
   roll/yaw/pitch is the central design fact; coordination (near-zero sideslip) is an achieved
   property of the coupled design, not a per-axis tuning outcome. Directly indicts our
   3-independent-servo structure. — NASA CR 19830004802 (JHU/APL 1982, CBTT); Lin & Yueh, ACC
   ("truly multivariable plant model… pitch-yaw cross-coupling in the design… good turn
   coordination").
2. **The coordinated-turn law is the exact bank/elevator coupling:** `ψ̇ = (g/V)·tan(φ)`;
   inverted, **`φ_d = atan(V·ψ̇_d / g)`** gives ONE commanded bank from a commanded turn rate
   (speed-scaled); the sustaining load factor `n = 1/cos(φ)` is the elevator term — precisely
   the shape of the KEPT S27 feedforward, now placed as the inner law's elevator coupling
   rather than a standalone patch. — Jung & Tsiotras (IFAC 2008); ArduPilot navigation-tuning
   docs (PTCH2SRV_RLL). *Caveat: steady-state level-turn relation; the command-model rate
   limiting covers transients.*
3. **THE OVERSHOOT MECHANISM, DIAGNOSED:** when the outer law commands bank/heading while
   ignoring the roll loop's first-order lag `φ̇ = (1/τ)(φ_c − φ)`, the closed loop is "sluggish
   and low damped" — oscillatory. Heading overshoot is a *structural* property of an outer law
   blind to bank-response lag. The fix is a cascade designed knowing the inner lag — NOT more
   per-axis damping. — Jung & Tsiotras, verified verbatim (wrong τ ⇒ Fig. 4 oscillates about
   the reference).
4. **The structural precedent is ArduPilot's own migration:** it REPLACED per-axis PID-servo
   navigation (Nav_Roll PID + crosstrack gain) with the **L1 guidance law** — one outer law
   turning the angle between velocity and desired path into one bank command pursuing a sliding
   reference point. The multi-gain tuning trap collapsed to essentially one time-constant knob.
   — ArduPilot PR #101 (2013); Park/Deyst/How AIAA 2004-4900 (`a_cmd = 2V²/L1 · sin(η)`).
   *(2-1 on "one knob" — NAVL1_DAMPING also exists; inner PIDs still tuned separately.)*
5. **Snap-vs-smoothness is tuned by TWO outer-loop knobs, not per-axis gains:** NAVL1_PERIOD
   (smaller = sharper) + NAVL1_DAMPING (ζ, default 0.75, rarely <0.6). Post-turn "weaving" —
   the exact sails-past symptom — is documented as fixed by RAISING the outer period: a
   one-dimensional aggressiveness-vs-overshoot tradeoff. — ArduPilot docs; source `K_L1 = 4ζ²`.
6. **No-overshoot arrival under rate limits = shape the COMMAND, don't damp the error:**
   ArduPilot's attitude cascade converts angle error → desired RATE via a **sqrt-controller**
   (linear small = snappy; `√(2·a_lim·err)` large = bounded deceleration into the target) plus
   accel/jerk limiting via one smoothing constant. It **never differentiates the noisy input**
   — solving mouse-jitter amplification structurally. — ArduPilot attitude-control docs +
   `AC_AttitudeControl.h` source, verified verbatim.
7. **War Thunder's Mouse Aim is a DIRECTION mode** — the mouse never drives axes; it sets a
   desired flight direction and the Instructor assumes full 3-axis control within the
   airframe's limits (AoA capped below critical, g-rate limited). Large errors are satisfied by
   a rate/load-limited coordinated catch-up, not proportional deflection — exactly Chad's spec.
   — Gaijin's instructor doc + patent US20130252208A1.
8. **MouseFlight (canonical Unity WT-style reference) contributes two reusable patterns and
   nothing more:** (a) the **aim/response split** — the world aim direction is rotated RAW by
   the mouse, never smoothed; the vehicle/camera chase it (= keep our CS-8 world cursor,
   unfiltered); (b) the **small/large error mode blend** — roll is a `Lerp(wingsLevel,
   bankIntoTarget, InverseLerp(0, ~10°, angleOffTarget))`: small errors go direct pitch/yaw
   (snap), large errors trigger bank-then-pull. Its inner loop is demo-grade proportional and
   overshoot-prone — **take the structure, not the servo** (two over-claims about it were
   refuted 0-3; do not cite it for the inner law).
9. **Biological anchor (honest, no fabricated constants):** Harris' hawks steer with ONE
   coupled turn-rate command from line-of-sight geometry — a mixed PN + proportional-pursuit
   law (`turn rate = N·(delayed LOS rate) − K·(delayed deviation angle)`, 228 motion-captured
   pursuits) — not independent axes. Biology confirms the SHAPE (one turn command); the LAW
   comes from the guidance literature.

## Refuted over-claims (for honesty)

- ✗ (1-2) "Gaijin says mouse aim is IMPOSSIBLE without an instructor" — their doc only says the
  design replaces per-axis control with direction command.
- ✗ (0-3) "MouseFlight's author warns its proportional autopilot overshoots and recommends PID
  per axis" — not in the source.
- ✗ (0-3) "MouseFlight deliberately leaves the inner loop to the developer" — it ships one; it's
  just demo-grade.

## THE RECOMMENDED STRUCTURE for `computeMouseAim` (the deliverable)

*(Synthesis — every component individually 3-0-verified, but no source implements this exact
stack over a no-auto-level grip kernel with a world cursor; the composition is engineering
judgment, MEDIUM confidence pending Chad's playtest.)*

**REPLACE** the roll/yaw cursor-error servos with a 3-stage cascade, blended in only for
LARGE, HORIZONTAL errors:

1. **OUTER — aim error → commanded turn rate.** Signed horizontal-plane angle between nose and
   cursor (`headingErr`, + = right) through a sqrt-controller:
   `ψ̇_d = headingErr·P` inside the linear region (`|err| ≤ A/P²`), else
   `ψ̇_d = sign·√(2A·(|err| − A/2P²))`, capped at the profile's real pull limit (pitchRate).
   Knobs: `aimTurnP` (aggressiveness ≈ 1/NAVL1_PERIOD), `aimTurnAccel` (A, the bounded arrival
   deceleration — the no-overshoot knob).
2. **MIDDLE — turn rate → ONE commanded bank.** `φ_d = atan(V·ψ̇_d / g_kernel)` clamped to
   `aimMaxBankDeg`, then SLEW-LIMITED (`aimBankSlew` rad/s) so the command respects the roll
   loop's lag (finding 3). `g_kernel = GameConfig.Flight.GRAVITY` (already GRAVITY_G-scaled).
3. **INNER — coupled outputs from the one command.**
   - roll = servo on **bank error** `−K_bank·(φ_d − bank_now) − aimRollDamp·rollRate` (rate
     damping on the body rate is fine — it is not derivative-of-error);
   - yaw = coordinating, `∝ ψ̇_d` (the SAME command — one command drives both);
   - pitch = **unchanged**: the existing PD on the body-frame vertical error (speed-scaled P,
     stall-gated) + the KEPT `(sec(bank)−1)·0.35` feedforward — the elevator that pulls the
     turn and pays its altitude. The body-frame error decomposition naturally rotates the
     horizontal error into the pitch axis as the bank develops (bank+yaw lead, elevator
     sustains — Chad's sequence).

**MODE BLEND (finding 8b):** `w = clamp((errAngle − cone)/cone, 0, 1) × horizontality ×
uprightness`, `cone = aimDirectConeDeg ≈ 10°`. Below the cone (and for near-vertical errors —
loops — and inverted flight) the OLD direct law runs verbatim: small-input snap, loop
commitment, and top-centre-cursor straight-up behavior are numerically IDENTICAL to the
S26-loved baseline. The coordinated cascade phases in only where the old law rubberbanded.

**KEEP unchanged:** the world-anchored cursor (CS-8, never smoothed — finding 8a), the
keyboard aim-gate (CS-1, outside this function), free-look suspend, no-auto-level (CS-5: the
bank command exists only under mouse-aim with a live error; zero error ⇒ direct mode ⇒ the old
behavior), the whole pitch channel incl. the S27 feedforward, deadzone/expo shaping, the
`aimResponse` output ease, and exact zero output at wings-level/cursor-centred.

**Why this kills each symptom, structurally:**
- *Sail-past:* ψ̇_d ∝ err near arrival ⇒ φ_d rolls the bank OUT before the nose reaches the
  cursor, deceleration bounded by A (findings 3, 5, 6) — deterministic arrival.
- *Arrival lag vs snap:* small errors never enter the cascade — the direct law (which never
  lagged) handles them (finding 8b); large-error smoothness comes from the command model, not
  from damping that would also slow small inputs (finding 6).
- *Jitter:* nothing differentiates the mouse; small errors run the old non-derivative law; the
  cascade's inputs are smooth geometry and φ_d is slew-limited (finding 6).

## Open questions (carried to the playtest / next sessions)

1. The Eagle's true roll-response lag τ and achievable turn rates under the kernel — worth a
   scripted step-response measurement in Studio if tuning fights back (finding 3's wrong-τ
   warning).
2. Near-vertical aim (loops): handled by blending OUT the cascade (horizontality factor) — is
   the handoff seamless in play?
3. Aim re-entry after the keyboard gate / free-look: the bank command re-seeds from the current
   bank whenever the cascade is inactive — verify no step transient in play.
4. A PN (LOS-rate) term for moving targets (mobbing crows) — deferred; the world cursor is
   already the player's lead indicator.

## Sources (primary, load-bearing)

- NASA CR 19830004802 — JHU/APL coordinated BTT study (1982). *(OCR artifact in abstract noted.)*
- Lin & Yueh — multivariable BTT autopilot with turn coordination (IEEE/ACC).
- Jung & Tsiotras — fixed-wing path following, backstepping with roll-loop lag (IFAC 2008), dcsl.gatech.edu/papers/ifac08.pdf.
- ArduPilot PR #101 (L1 replaces PID navigation) + `AP_L1_Control.cpp` + navigation-tuning docs.
- ArduPilot attitude-control docs + `AC_AttitudeControl.h` (sqrt-controller, command model).
- Gaijin: "How the instructor works" (old-wiki.warthunder.com) + patent US20130252208A1.
- brihernandez/MouseFlight (aim/response split + roll-mode blend; inner law refuted as precedent).
- Brighton & Taylor lab — Harris' hawk mixed PN/PP guidance (PMC10265027).
