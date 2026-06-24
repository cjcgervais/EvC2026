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
