# RESEARCH — the mouse-aim instructor hard-turn nose-dip (coordinated-turn feedforward)

**Session 27, 2026-07-02.** Deep-research pass on Chad's standing directive: the
War-Thunder-style mouse-aim "instructor" over our 6DOF no-auto-level kernel
NOSE-DIPS / porpoises in hard banked turns at low-to-mid speed ("it goes down to
keep the speed… throws you off target when trying to merge with the crows").
Method: fan-out web search → source fetch → **3-vote adversarial verification per
claim** (69 claims verified high-confidence non-refuted; 6 over-claims refuted).
The refuted set is cited too — it's where the honest caveats live.

> **Bottom line.** The fix is a **bank-proportional pitch FEEDFORWARD**: add nose-up
> pitch as a function of *bank angle* (not of cursor error), so the instructor pays
> the altitude cost of the turn AS it banks instead of after the sag shows up as
> cursor error. This is (a) exactly what real autopilots do (ArduPilot
> `PTCH2SRV_RLL`), (b) what a real raptor does (tail-twist nose-up pitch coordinated
> with the bank — but only qualitatively; the biology gives the SHAPE, not a
> number), and (c) provably won't re-introduce the porpoise the way raising P-gain
> would, because feedforward is open-loop and adds no closed-loop phase lag.

---

## Q1 — How real mouse-aim instructors / autopilots hold altitude in banked turns

**They use a bank→pitch FEEDFORWARD, not error feedback.** The canonical, documented
example is **ArduPilot Plane's `PTCH2SRV_RLL`** (newer name `PTCH_RLL_FF`), a
dedicated *"Roll to Pitch Compensation"* term that *"compensates pitch in turns to
avoid altitude loss due to loss of lift caused by the roll"* and *"controls how much
elevator to add in turns to keep the nose level."* Default **1.0**, valid range
**0.7–1.4**, tuned by rolling to max bank both ways until *"the nose stays fairly
level during the turns without significant gain or loss of altitude"* — reduce it if
the model *gains* height in turns. [verified V1–V5, V8, V10, V12, V14; official
ArduPilot docs, `new-roll-and-pitch-tuning.html`]

- **Functional form (important):** ArduPilot's term is **not** strictly linear in
  bank — it's a **load-factor / airspeed-scheduled** form, ≈ `tan(bank)·sin(bank)/airspeed`
  (ArduPilot GitHub issue #16098). i.e. it grows faster than linear with bank and is
  larger at low airspeed. This corroborates using a `sec(bank)−1` (load-factor) shape
  rather than a plain `∝ bank`. [V10, V12, V14]
- **ArduPilot's own architecture** calls the feedforward the PRIMARY surface-deflection
  term: *"Normally, most the demanded rate is attained using the FF, or feedforward,
  term… much like the human pilot deflects the control surface directly"*; the P/D
  terms only *"act on any errors."* FF is explicitly *"an open loop gain."* [V2, V5, V8]
- **War Thunder's instructor** (the mouse-aim mode itself) is documented as **AoA/stall
  envelope protection**: it prevents *"maneuvers that are too sharp… extreme angles of
  attack that could lead to a stall or a spin."* So a shipped mouse-aim instructor pairs
  its turn assistance with an AoA limiter — not an unconstrained pitch pull. [V6, V7, V15;
  official War Thunder wiki]
- **Airbus A320 Normal Law** is the reference envelope-protection scheme: two-stage
  high-AoA protection (α-prot: pitch becomes AoA-proportional to stick + autotrim
  freezes; α-max: *cannot be exceeded even with full aft stick* → *"the aircraft cannot
  be stalled in Normal Law"*) plus a hard **load-factor limiter** (−1/+2.5g clean).
  [V41, V43, V44, V47, V49, V51]

**Takeaway:** the professional answer is a bank-proportional (load-factor-shaped) pitch
feedforward, applied as the bank develops, **AoA/load-factor-limited** at the boundary.
Our AI-crow autopilot already does the simple version (`turnPitchUp`: up-elevator ∝ bank);
the player instructor is the only controller in the repo missing it.

## Q2 — Adding feedforward to a PD loop WITHOUT re-introducing oscillation

**Verified, strongly and repeatedly:** feedforward is **open-loop** — a function of the
reference/known state, injected in parallel (summed onto the PD output, the standard
"PIDF" architecture used by Betaflight/ArduPilot/WPILib). Because it **does not appear in
the closed-loop characteristic equation**, it **cannot move the closed-loop poles or erode
phase/gain margin** — unlike raising P-gain, which is inside the loop and does exactly
that. So feedforward *"has no effect on system stability"* in the pole sense and adds **no
closed-loop phase lag**. [V27, V29, V31, V33–V36, V38–V40, V42, V45, V52, V56, V67–V71;
MIT OCW 10.450, Seborg Ch.15, WPILib, control.com]

**This is the crux of why it fixes the porpoise instead of worsening it:** the porpoise is
the PD loop chasing a lift-sag error that keeps re-appearing. Feedforward *cancels the
known part of that sag before it becomes error*, so the PD loop has **less** to chase, not
a higher gain fighting its own damping.

**Two honest caveats (refuted over-claims — do not ignore):**
- The "free pass / no stability effect" theorem holds strictly for **reference-based**
  feedforward on a **linear, non-saturating** plant. Our term is a function of **bank
  (a measured state)**, so it is technically a mild feedback coupling, and the AoA-limit
  is a **saturation nonlinearity** — either can, *in principle*, affect stability. [R46]
- Mitigation is exactly the standard one: **keep the gain modest and bounded, and
  AoA/load-factor-limit it** (which we do). The practical conclusion — *a bounded
  bank-feedforward is far less porpoise-prone than raising P-gain* — is mainstream and
  correct; it is just not literally "free." [R46, V56 saturation qualifier]

## Q3 — Reconciling altitude-hold feedforward with the stall boundary

**AoA/load-factor limiting is the standard reconciliation** (A320 α-max, War Thunder
instructor). The feedforward must **ease off as the wing approaches stall** so it can't
force the nose past the critical AoA at low speed — which is precisely where the crow-merge
fight lives. [V6, V7, V15, V41, V43, V49]

- **Why low speed is the hard case:** stall speed scales as `Vs·√n` (n = load factor). A
  60° bank → n = 2 → **+41%** stall speed; 75° → n = 4 → **doubled**. Because lift ∝ v²,
  the AoA increment needed to make the turn's extra lift is **larger at low speed** — the
  turn crowds the stall boundary exactly when you're slow. [V48, V50, V53–V55, V57, V61,
  V64, V66]
- **Design consequence:** don't *boost* the feedforward at low speed (ArduPilot does, but
  it has an independent stall protection). Instead hold the feedforward **bank-only** (load
  factor n = 1/cos(bank) is itself airspeed-independent — V58/V60/V65) and let the
  **AoA-limit gate** decide how much of it the wing can actually cash at the current speed.
  Our existing `aoaHead` stall-band factor already IS this gate.

## Q4 — Physics of the coordinated level turn

- **Load factor** in a level coordinated turn: **n = 1/cos(bank)**, depends only on bank
  (airspeed, weight, altitude cancel). 30°→1.15g, 45°→1.41g, 60°→2g. [V58, V60, V65]
- **The altitude cost:** vertical lift = L·cos(bank) < W, so to hold altitude the wing must
  make **n× the lift**, i.e. **extra lift ∝ (sec(bank) − 1)** — zero at wings-level, growing
  with bank. Producing it requires a higher **AoA**, which raises induced drag and bleeds
  airspeed unless power is added. [V59, V62, V63]
- **Why lift ∝ v² makes it worse slow:** the AoA increment to make that extra lift is
  larger at low speed, so the turn crowds CL_max / stall. [V48–V66]

**⇒ The physically-faithful feedforward magnitude is a load-factor form: nose-up ∝
(sec(bank) − 1)** — zero at wings-level, rising with bank, matching the real lift deficit.

---

## The biological angle — honest reporting (does it map?)

**It maps at the level of SHAPE, not number.** The strongest raptor-turn source is
**Phan & Floreano, "A twist of the tail in turning maneuvers of bird-inspired drones,"
Science Robotics 2024** (bioRxiv 2023.12.29.573672, PMID 39565865): in a raptor's banked
turn the tail is **twisted AS the bird banks**, which *"induces a nose-up pitch moment that
increases the angle of attack of the wings, thereby generating more lift to compensate for
losses caused by the banking motion."* The same input supplies the coordinating roll+yaw
AND the compensating pitch — i.e. a **coordinated, feedforward-like** action applied
together with the bank, not an after-the-fact error correction. [V9, V11, V13, V21, V22,
V24, V25] The morphing-drone LisEagle study (Comms. Engineering 2022, PMC10956009) shows
the same mechanism quantitatively on hardware: tail-up → +pitch moment → higher AoA →
higher CL sustains the bank; extended wing/tail reaches higher bank/load factor (peak g
1.46→3.3). [V16–V20, V23, V26, V30, V32]

**But the biology does NOT give a usable number, and I will not fabricate one:**
- These are **bird-INSPIRED DRONES** + steady-soaring observation, **not live-eagle force
  telemetry**. [R28, R37 — refuted over-claims that leaned on them as literal eagle data]
- **Real eagle/hawk turns are wing+tail COORDINATED, not tail-only.** The live-bird
  literature — **Gillies, Thomas & Taylor 2011** (steppe eagle *Aquila nipalensis*, onboard
  IMU: *"a continuous sequence of banked turns interrupted by occasional wing tucks and
  roll-over manoeuvres,"* recording body, wings AND tail), **KleinHeerenbrink et al.**
  (Harris' hawk: *"complex wing–tail shape changes coordinated with whole-body rotations"*)
  — describes coordinated wing+tail morphing and gives **no bank-proportional pitch number,
  no turning-flight load factor.** [R37 counter-sources]
- The IJRASET eagle paper documents tail-lowering/spreading in the initial bank phase and
  AoA **qualitatively only** — no load factor, framed for yaw/roll stability, not a
  pitch-pays-altitude law. [R72, R73, R74]

**Conclusion (per Chad's explicit fallback instruction):** the raptor literature
**confirms the shape and the sequence** Chad described — *bank + coordinating yaw for
stability, THEN a nose-up AoA increment applied WITH the bank to pay the altitude the bank
costs* — but it **does not map to a tuning constant.** So we take the **shape from biology
and the physics (∝ sec(bank)−1, AoA-limited)** and set the **magnitude by engineering**
(ArduPilot's near-unity, playtest-tuned precedent). This is the "simplest tuning that
removes the dip" Chad authorized, and it is honestly grounded, not reverse-justified.

---

## Recommendation — the surgical change

Add ONE bank-proportional pitch feedforward term to the mouse-aim pitch command in
`BirdController.computeMouseAim`, injected **before** the existing stall gate and clamp:

```
-- nose-up feedforward that pays the altitude cost of the current bank (coordinated turn).
sinBank = clamp(-cf.RightVector.Y, -1, 1)          -- +/- roll, pitch-attitude independent
cosBank = sqrt(max(1 - sinBank^2, 0.04))           -- floor => sec capped at 5 (~78 deg), no blow-up
bankFF  = (1/cosBank - 1) * aimBankFeedforward      -- >= 0, ZERO at wings-level, grows with bank
pitch   = pitch + bankFF                            -- add to the PD nose-up command...
if pitch > 0 then pitch = pitch * aoaHead end       -- ...existing AoA/stall gate now limits the FF too
pitch   = clamp(pitch, -1, 1)
```

**Why it satisfies every constraint:**
- **Zero at wings-level** — `sinBank≈0 ⇒ cosBank≈1 ⇒ bankFF≈0`. Straight flight and the
  signed-off snap feel are numerically untouched. [Q4 shape]
- **Mouse-aim only** — it lives inside `computeMouseAim`, which returns 0,0,0 in free-look;
  and the CS-1 aim gate in `onFlightStep` zeroes the whole `aimApplied` contribution while
  any flight key is held. So CS-1, CS-5 (no auto-level — this only acts under mouse aim),
  CS-8 (world cursor unchanged) all hold.
- **Won't porpoise** — it's a function of BANK, not cursor error; open-loop, so it adds no
  closed-loop phase lag. It cancels the known lift-sag so the PD loop chases LESS. [Q2]
- **Respects the stall boundary** — routed through the existing `aoaHead` gate, it eases to
  zero within `aimStallBandDeg` of stall (and is bypassed when powered, like the rest).
  Bank-only magnitude + AoA-limited cashing = the correct low-speed behavior. [Q3]
- **Kernel untouched** — pure client instructor + one config knob.

**Starting gain:** `aimBankFeedforward ≈ 0.35` (at 60° bank, `sec−1 = 1.0` → +0.35 nose-up
before AoA-limiting; at 45° → +0.14; at 30° → +0.05, so gentle turns are barely affected —
this is a HARD-turn fix by construction). ArduPilot's tuned analogue sits near unity on a
comparably-shaped term; our command is normalized to [−1,1], so 0.35 is a conservative
first pass. **Tuning:** raise toward 0.5–0.6 if the nose still dips in a hard bank; lower
toward 0.2 if the nose now *balloons up* (climbs) in turns (ArduPilot's own
reduce-if-it-gains-height rule). PLAYTEST-PROVISIONAL.
