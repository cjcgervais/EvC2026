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
