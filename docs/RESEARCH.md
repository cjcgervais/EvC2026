# Eagles vs Crows — Research → Design Reference

Distilled from a verified deep-research pass (108 agents, 25 sources, 24/25 claims survived adversarial verification). Every claim below drove a number in `src/shared/GameConfig.luau`. **Thesis: flight physics and asymmetric balance are one system; performance is a hard constraint on both.**

## 1. The master lever — energy / altitude
Altitude is convertible potential energy (gliding spends it as drag; thermals restore it). Energy-Maneuverability theory gives **one** tunable currency: `Ps = V·(T−D)/W` (specific excess power ∝ climb/sink rate). Balance both classes through it.
- **Eagle = energy fighter** (boom-and-zoom): high climb ceiling, dive recovery.
- **Crow swarm = angles fighter**: wins at lower energy states via turn rate.
- *Config:* `Flight.CONTROL_AUTHORITY_*` (slow birds can't steer), `Profiles.*.glideSpeed/diveSpeedCap`, `Thermals.strength`.

## 2. The dive must be priced
Real data (Brighton 2021, Swainson's hawks): a stoop tripled capture odds (**3.46×**, CI 1.43–8.82) vs level flight. The eagle's dive is its kill identity — but a **missed** dive must dump it into a low-energy state = the crows' counterplay window.
- *Config:* `Profiles.Eagle.diveAttackMultiplier = 3.46`, `diveThrustBonus`, `staminaDiveCost`, stall risk via `stallAngleDeg`.

## 3. Two turn parameters, not one (verifier caveat)
Wing loading: high = fast + **wide** turns + strong dive (Eagle); low = **tight** turns + fast roll (Crow). BUT high wing loading helps the *instantaneous* turn while hurting the *sustained* turn — so the model needs **both** `wingLoading` (instantaneous, in the lift equation) AND a separate `sustainedTurnRate` (the coordinated-turn cap). That split lets a crow lose the merge but win the prolonged turn fight.
- *Config:* `Profiles.*.wingLoading`, `rollRate`, `rollInertia`, `sustainedTurnRate`. *Engine:* `FlightPhysics` applies wingLoading in lift, sustainedTurnRate in the coordinated-turn step.

## 4. 1-v-many balance is GEOMETRY, not stats
Hawk-vs-swarm data: lone/peripheral individuals attacked ~10% of attacks despite ~0.2% of population (order-of-magnitude over-targeted); **no confusion effect** — protection is pure dilution / safety-in-numbers.
- ⇒ **Formation tightness is the crow player's core risk knob.** Tight = protected members + concentrated offense, but catastrophic dive/collision exposure. Loose = coverage + resilience, but creates stragglers the eagle hunts. The eagle's job is to **force isolation**.
- *Config:* `Squad.formations.tight/loose` (spacing, cohesionMul, separationMul, collisionRisk).

## 5. Squad AI = Reynolds boids on the same flight engine
Separation / alignment / cohesion over a local distance + FOV-angle neighborhood. Reynolds' decomposition (action-selection → steering → locomotion) means boids output **control signals** consumed by the *same* `FlightPhysics` as the player — AI crows fly identically.
- *Code:* `src/shared/Boids.luau` → `computeSteering` then `steeringToInput` → `FlightPhysics:Update`.

## 6. Performance (the hard constraint — achievable)
- **`SetNetworkOwner`** to the controlling client = latency-free flight + splits physics CPU across clients (this is the scaling mechanism). Gated by `CanSetNetworkOwnership()`.
- **Parallel Luau actors** for boids/aero, BUT parallel code **cannot write the data model** — compute in the `task.desynchronize()` phase, batch CFrame writes in the `task.synchronize()` phase. (Not yet implemented; see HANDOFF.)

## 7. Anti-cheat (a REFUTED claim — heed it)
"Server authority prevents speedhacks for free" **failed** verification. Client authority is an unverifiable attack surface: the **server must own all damage/score** (it does — see GameServer) and validate movement with an envelope (max speed/climb/accel, teleport detection) that does **not** false-positive intended dives/loops/thermals. **Not yet built.**

## Caveats / freshness
- Quantitative data is hawks-vs-**bats**, not eagles-vs-crows — the mechanism transfers but isn't a literal measurement.
- The signature **lose-lose collision** mechanic has **no source backing** — it is unverified design (placeholder numbers in GameConfig; tune by playtest).
- Roblox **Server Authority + `RunService:SetPredictionMode()`** shipped Studio Beta 2025-12-09, GA "early 2026" — it is the *opposite* of our client-authoritative default. Re-verify current GA behavior before finalizing netcode.

## Sources (highest quality)
- PMC8177810 (Brighton et al. 2021) — stoop advantage, lone-target, no-confusion-effect
- arXiv 2409.03849 — wing loading ↔ turn radius/speed
- Wikipedia: Bird flight, Energy–maneuverability theory, Wing loading, Basic fighter maneuvers
- red3d.com/cwr (Reynolds) — boids & steering behaviors
- create.roblox.com/docs — network ownership, multithreading, server authority; security-tactics.md

---

# v2 — Game flight-model IMPLEMENTATION (deep-research pass, 2026-06-28)

This pass answered "how do you actually build a great arcade/sim flight kernel" (the biology/balance above answered "what should the matchup be"). It diagnosed and fixed the persistent "not enough lift, constantly stalls" complaint. Drove the **FlightPhysics v2 kernel** (see `docs/HANDOFF.md` session 6).

**Root cause (confirmed across sources):** a lift model with **no baseline lift coefficient** (`lift ∝ sin(AoA)`, `CL0=0`) makes zero lift at zero AoA, so the craft must fly nose-high and chronically near stall; as speed drops the required AoA climbs past stall → permanent near-stall. This is the textbook failure signature. v1 also rotated *velocity toward the nose* every frame, actively driving AoA→0 (the no-lift point) — the two flaws compounded.

**The canonical lift model (use this):** `CL(α) = CL0 + (dCL/dα)·α`, linear to a peak at the stall angle, then **roll off to a nonzero plateau** (≈50–60% of CLmax) over a few-degree pad — never a cliff. Pair with **rising drag past stall** so the stall self-recovers. Drag polar `CD = CD0 + k·CL²` (induced drag ∝ CL² ∝ g-load² — this is what makes hard turns bleed energy = E-M for free).

**Cross-checked starting numbers** (real units; our abstract `AIR_DENSITY` is recalibrated to 0.033 to match these to studs/s):
- `CL0 ≈ 0.3` (THE fix; 0 only for symmetric/aerobatic airfoils) — Aerofly TMD docs.
- `dCL/dα ≈ 2π/rad ≈ 0.11/deg` (thin-airfoil theory; gasgiant `liftSlope=6.28`).
- `CLmax ≈ 1.0–1.6`, stall ≈ **15–16°** physical (we use 18–20° eagle / 24° crow = deliberate arcade forgiveness; Vazgriz's *toy* curve even peaks at 30°).
- `CD0 ≈ 0.02–0.025`. Induced `CL²/(π·AR·e)`, games use `e=1` + a tuning multiplier.

**Three fixes applied together:** (a) baseline `CL0`; (b) **static pitch stability / weathervaning** — a restoring rotation of the nose toward the airflow + damping (we rotate orientation toward velocity, NOT velocity toward the nose); (c) **trim for cruise** — pick cruise speed, solve AoA where lift=weight (a few °, far under stall) so "no input" = stable level flight.

**Arcade vs force-based:** pure velocity-redirection feels "weightless / noclip" (Ace Combat 7 player complaints); pure force-based can feel mushy. Best games blend: **force-based core + a grip/alignment assist + airspeed-scaled authority + a G-limiter** (Vazgriz tunes +8/−4 G). The **grip dial is the Eagle-vs-Crow lever** (eagle low grip/high inertia = boom-and-zoom; crow high grip = angles). We implement grip as the bank-gated `sustainedTurnRate` coordinated turn. **Control authority ∝ dynamic pressure (V²)** — near-nil at low speed (mush), strong at speed; we use the existing speed→authority ramp.

**Forgiving stall/recovery:** the CL curve *is* the stall model (no state machine). Shallow post-peak downslope + nonzero residual lift = "mush + sink"; a **pitch-down moment ∝ (AoA − AoA_crit) past critical** makes recovery the default. Avoid spins by computing AoA from a **single body-frame value** (no per-wing asymmetry/yaw-coupling at high AoA) — game sources deliberately omit spins for playability; side with them.

**Energy-maneuverability:** dive=accelerate / climb=decelerate emerge FREE if **gravity is a persistent world force** (don't cancel it with a lift=weight shortcut) — gravity's component along velocity is `g·sin(flightPathAngle)`. Tune the two profiles so their Ps=0 sustained-turn envelopes **cross** (the E-M-diagram crossing is where neither dominates).

**Roblox specifics:** keep **CFrame-driven + `SetNetworkOwner`** for now (the canonical decision); `BirdCollision` Spherecast is mandatory because CFrame writes never collide. **Clamp `dt = min(dt, 1/30)`** (we do) — a frame spike otherwise tunnels/explodes the integrator. New **Server Authority / `SetPredictionMode`** reached Client Beta 2026-04-30 but **no dated GA confirmed as of late June 2026**; it is **mutually exclusive with `SetNetworkOwner`** and needs a yield-free `BindToSimulation` rewrite — treat as a future spike, NOT adopted now. Deprecated movers to never use: BodyVelocity/BodyGyro/BodyForce/BodyPosition (use VectorForce/LinearVelocity/AlignOrientation only if we ever leave CFrame).

## v2 sources (highest quality)
- vazgriz.com/346 (flight sim in Unity, Part 1) + vazgriz.com/762 (F-16) — lift curve, steering curve, G-limiter
- github.com/brihernandez/SimpleWings (copy-paste NACA-0015 CL curve) + ArcadeJetFlightExample (grip-as-drag)
- github.com/gasgiant/Aircraft-Physics (analytic Khan-Nahon model, defaults)
- aerofly.com TMD airfoil docs (CL0/ClAlpha/stall params, "CL0 affects cruise attitude")
- en.wikipedia.org: Lift coefficient, Zero-lift axis, Stall (fluid dynamics), Energy–maneuverability theory
- create.roblox.com/docs/projects/server-authority + devforum Server Authority beta threads
- gafferongames.com "Fix Your Timestep" — frame-rate-independent integration

---

# v3 — REAL-SCALE recalibration (deep-research pass, 2026-06-28, session 8)

Answers the session-7 north-star: "the best flight model on Roblox" via **real-scale raptor flight** (HANDOFF session-7 block; `project-realscale-flight-goal` memory). Chad's three asks — 2 km ceiling, bigger arena, real dive-acceleration — turned out to share **one** root: the world was built at Roblox's default gravity, which is wrong for the scale.

## The scale crux (measured, not assumed)
- **1 stud = 0.28 m** is Roblox's canonical scale (the 2019 World-panel definition). [roblox.fandom.com/wiki/Stud_(unit), devforum studs-to-metre]
- Therefore **real gravity at this scale = 9.81 / 0.28 ≈ 35 studs/s².** Roblox's default `Workspace.Gravity = 196.2` is **≈5.6× real g.** That 5.6× is exactly why dives felt "too punchy with no room to develop a stoop."

## What's ALREADY real at 0.28 m/stud (so don't touch the speeds)
The v2 speed envelope, converted, is already biologically accurate — only gravity and world-size were off:
| Quantity | Real | × (1/0.28) | Our config | 
|---|---|---|---|
| Golden-eagle stoop | 67–89 m/s (240–320 km/h) | 240–320 studs/s | `Eagle.diveSpeedCap = 320` ✅ (real top end) |
| Peregrine stoop | ~107 m/s (386 km/h) | 382 studs/s | `TERMINAL_VELOCITY = 400` ✅ |
| Eagle hunting glide | ~54 m/s (120 mph) | 193 studs/s | `maxLevelSpeed 170` (slightly low) |
| Eagle cruise/soar | ~36 / 13 m/s | 130 / 46 studs/s | `glideSpeed = 130` ✅ |
| Best-glide sink | 0.75 m/s (L/D ≈ 25–30) | 2.7 studs/s | eagle glides L/D ~34 (close) |
| Soaring / migration altitude | 1350–2000 m AGL | 4800–7150 studs | **`SERVICE_CEILING` was 520 ✗** → raise to ~7150 |
| Golden-eagle wingspan / mass | ~2 m / 3–6.7 kg | ~7 studs | `bodyRadius 4.5` ok |

Sources: birdsnews/britannica/eagles.org (eagle stoop & glide speeds), PMC5896925 + physicsworld (peregrine stoop physics, 25+ G pullout), PMC9179650 (instrumented golden-eagle soaring: 0.75 m/s sink, ~1350–2000 m AGL waves), dimensions.com + Wikipedia Golden_eagle (size/mass).

## The recalibration theorem (why this is SAFE, not scary)
Drop gravity by factor **k** and **drop `AIR_DENSITY` by the same k.** Then every equilibrium that defines the flight envelope is **invariant** — k cancels:
- **Stall speed** `v_stall = √(g·wingLoading / (clMax·ρ))` → g↓k, ρ↓k cancel → **unchanged.** (Eagle ~61, Crow ~45 — identical to v2.) The `stall < spawn < cruise` invariant is therefore *structurally guaranteed* at any k.
- **Cruise trim AoA** (`cl·ρ·v² / WL = g`) → unchanged. **Terminal velocity** (`CD·ρ·v² = m·g`) → unchanged. **Glide ratio / sink rate** → unchanged (pure CL/CD geometry).
- What DOES change, by design: **all accelerations get gentler ×k** (real-g dive/climb feel — fixes "punchy"), and **turn radius `v²/a_lift` grows ×k** and **dives need ×k more distance** to build → the world must grow ~k (hence the bigger arena + 2 km ceiling).

So the player-approved v2 feel *character* (grip, powered climb, momentum, the eagle-wide/crow-tight split) is preserved; only the scale/majesty changes. **The other gravity-coupled forces must scale by k too** to hold their ratios-to-weight: `flapThrust`, `flapClimbForce` (kept "above gravity"), and `Thermals.strength`. Everything else (speeds, control-authority speeds, all rad/s rates, `TERMINAL`, `CRASH_SPEED`) is scale-free and stays.

## Implementation: one knob
`GameConfig` now derives gravity from `METERS_PER_STUD = 0.28` and **`GRAVITY_G`** (fraction of real g — THE sweep knob; 1.0 = true real, higher = arcadier/punchier), and multiplies the coupled forces by `GRAV_SCALE = GRAVITY / 196.2`. World sizes are expressed in real metres (`/0.28`). Sweep `GRAVITY_G` in Studio to taste — the envelope/invariant can't break.

## Open watch-items for the playtest (flight==balance)
- **Floaty vs snappy:** full real-g (k=5.6) is the most majestic but a big jump from the tuned 196.2 — start `GRAVITY_G` partway (arcade-real) and sweep down. Reason about the 1-v-4 on the chosen value.
- **Reaching 2 km:** thermal climb at real ratios is slow; the eagle reaches the apex via the powered climb + thermals over several energy cycles (intended skill), but if it's tedious, strengthen thermals (a gameplay concession over realism) or lower the practical combat band.
- **Turn energy-bleed:** wider real-scale turns + lower induced drag (ρ↓) + the grip assist could wash out E-M turn-fighting; if speed stops mattering in dogfights, add a small grip-drag (already flagged in `flight-vertical-envelope`).

## v3 sources (highest quality)
- roblox.fandom.com/wiki/Stud_(unit) + devforum.roblox.com/t/studs-to-metre-conversion (0.28 m/stud canonical)
- pmc.ncbi.nlm.nih.gov/articles/PMC9179650 — instrumented golden-eagle long-distance flight (sink rate, soaring altitude)
- pmc.ncbi.nlm.nih.gov/articles/PMC5896925 + physicsworld.com/a/falcons-high-speed-dive — stoop physics, G-loads
- birdsnews.com/fastest-bird-species, britannica How-Fast-Can-Eagles-Fly, eagles.org golden-eagle-behavior — eagle stoop/glide/soar speeds
- en.wikipedia.org/wiki/Golden_eagle + dimensions.com golden-eagle — wingspan/mass/size

---

# §v4 — Holistic control-law + chase-camera redesign (2026-06-29, deep-research grounded)

**Why:** the mouse-aim control law, the energy tuning, and the chase camera had been iterated by live
playtest to the point where band-aid tuning traded one symptom for another (they're coupled). Per the
project workflow, a `deep-research` pass (5 angles → 26 sources → 25 claims adversarially verified, 23
confirmed) grounded the rebuild. The six problems (P1 loops won't complete, P2 pitch curve, P3 turn
porpoise, P4 energy bleed, P5 nose-down flap thrust, P6 camera loop-snap) and their root causes are in
`docs/HANDOFF-flight-tuning.md`.

## What the research established (and what it didn't)
- **WT mouse-aim is a "direction mode" Instructor.** The cursor sets a desired flight *direction*; the
  Instructor takes authority over all three axes to chase it **within the flight envelope — preventing
  critical AoA, stall, and spin** ("preserving lift"). That envelope clamp is *exactly* what makes a
  full-deflection turn or loop **commit** instead of mushing. Source: old-wiki.warthunder.com
  Instructor/How_the_instructor_works (primary, 3-0). **Gaijin does NOT publish the control-law internals**
  (P vs PD/PID, gains, deadzone) — so the damping choice is the implementer's.
- **Input shaping is documented:** per-axis **nonlinearity/expo 1.0–2.5** softens centre sensitivity while
  keeping full deflection at the edge. Source: wiki.warthunder.com/controls/4785 (3-0). → symmetric
  deadzone+expo on **both** pitch and bank (`aimPitchExpo=aimBankExpo=1.8`).
- **Energy-Maneuverability targets are first-principles:** instantaneous coordinated turn rate
  `ω = g·√(n²−1)/V`; the **corner point** (CLmax stall limit ∩ g-limit) gives peak instantaneous turn at
  `V_corner = V_stall·√(n_max)`; **sustained** turn is `Ps=0` i.e. `T=D(n)`; realistic sustained ~2.7–3 g
  vs ~6 g corner for piston-class craft. The **parabolic drag polar `CD = CD0 + K·CL²`, `K = 1/(π·AR·e)`**
  means **induced drag ∝ CL² ∝ load-factor²** — the principled "hard pulls cost energy but not absurdly"
  lever, and a max-g instantaneous turn is *meant* to decelerate. Sources: VT AOE3104 turningflight.pdf
  (primary), agodemar Flight-Mechanics drag-polar (primary), flyonspeed, Aces High trainer (all 3-0).
  *Refuted 0-3 — do not reintroduce:* "corner velocity = the Ps=0 sustained point" (it is the instantaneous
  point); "WT roll-isolates the instructor."
- **Camera (the anti-sickness core):** smooth **position and rotation as independent channels** (Unreal
  separate CameraLagSpeed/CameraRotationLagSpeed); use **frame-rate-independent damping**
  `Lerp(a,b,1−exp(−λ·dt))` (Rory Driscoll / lolengine, 3-0) — naive per-frame lerp is fps-dependent; and
  **shortest-path (quaternion) rotational interpolation** (dot<0 → negate to pick the short arc) survives a
  **360° loop with no azimuth snap and no pole flip** (josimard critically-damped quat spring, 3-0 on the
  math). Roblox `CFrame:Lerp` already does shortest-path slerp — so the snap was never the Lerp, it was the
  **target** (the old `headBack` azimuth from the bird's *horizontal heading*, which reverses ~180° over the
  loop top). Fix: a **single persistent full-3D chase direction, rate-limited** (`chaseTurnRate`) — never
  rebuilt from a discontinuous reference.
- **Free-look (pillar 4): unanswered by the corpus** — the project's own world-referenced orbit remains the
  reference. Player decision implemented: **Space = toggle**, not hold.

## What changed in code (tune against these, don't eyeball)
- **`FlightPhysics`**: exposes `pitchVel/rollVel/yawVel` (smoothed body rates) so the instructor can do PD.
- **`GameConfig.Controls`** (the instructor): `aimResponse 9→13` (PD now does the damping, ease needn't add
  lag); **symmetric** `aimPitchDeadzone=0.05/aimPitchExpo=1.8` + `aimBankDeadzone=0.10/aimBankExpo=1.8`
  (P2); **PD** `aimPitchDamp=0.35`, `aimRollDamp=0.30` (P3 — rate feedback critically-damps the porpoise);
  `aimStallBandDeg 7→4` + **suspend the AoA fade while powered** (flap throttle up) so a started loop
  commits (P1, "ride the edge"); `aimPitchGain 3.0→2.6` (full deflection still saturates → loop authority
  intact).
- **`GameConfig.Camera`**: `chaseTurnRate=3.6` (rad/s cap on chase-direction slew — THE no-snap knob, ≥ the
  bird's loop rate), `lookAheadFactor=0.3` (blend chase toward the velocity vector). `BirdController`
  rewrites `updateCamera` to the continuous rate-limited chase + world-up-perpendicular camera-up + slight
  look-ahead, all finished by `CFrame:Lerp` (P6).
- **`GameConfig.Flight/Eagle`**: `AEROBATIC_MIN_SPEED 110→60` (it gates a now-inert weathervane since
  `STABILITY_RATE=0`; lowered so it can't fight a slow loop top — loop commit is owned by the controller +
  powered-lift floor), `inducedDragK 0.65→0.58` (more energy retention through a pull while keeping the n²
  EM cost — P4). **P5 verified, no change**: nose-down + Shift (positive flap throttle) already accelerates
  via `accel += look·thrust·diveThrustBonus·fade`.

**Status: implemented; awaiting Studio human-verify** (the only real test). Acceptance criteria in
`docs/HANDOFF-flight-tuning.md`. Validate one system at a time: plant (keyboard loop/turn) → mouse
instructor (PD turn + loop commit) → free-look toggle → camera (full 360° loop with no snap/sickness).

## v4 sources (highest quality)
- old-wiki.warthunder.com/Instructor/How_the_instructor_works (primary — direction-mode + envelope protect)
- wiki.warthunder.com/controls/4785-setting-up-control-axis-and-sensitivity (expo 1.0–2.5)
- archive.aoe.vt.edu/lutze/AOE3104/turningflight.pdf (primary — turn rate, corner, load factor)
- agodemar.github.io/FlightMechanics4Pilots/mypages/drag-polar (primary — CD=CD0+K·CL², K=1/(π·AR·e))
- flyonspeed.org/basic-energy-management, trainers.hitechcreations.com/.../1076-turning (EM corner/sustained)
- rorydriscoll.com/2016/03/07/frame-rate-independent-damping-using-lerp + lolengine.net/blog/2015/05/03 (fps-independent damping)
- dev.epicgames.com/.../SpringArmComponent (independent position vs rotation lag channels)
- gist.github.com/josimard/5737f3488fdfa2d207d68de282904479 (critically-damped quat spring, shortest-path)
