# Eagles vs Crows — Single-Bird-Kernel Master Specification

**Reconstruction-grade specification.** If all source were lost, this one document is enough to
rebuild the flight kernel, the controls, the camera, the server authority model, and the complete
tunable set — and to understand *why* every number and control is what it is.

- **Snapshot:** GitHub branch `single-bird-kernel`, commit `52a929c` (2026-06-30). Tags
  `v1.0-eagle-flight` (pure kernel), `v1.1-eagle-flight-feel`.
- **Engine/target:** Roblox, Luau (`--!nonstrict` / `--!strict` per file). Synced via Rojo
  (`default.project.json`). No compiler/linter/test-runner; **ground truth is Studio Play**.
- **State at capture:** eagle flight / control / camera feel **signed off** by the designer
  ("the flight model of the eagle is largely finished. I'm having a great experience"). Frontier =
  combat + the 1-v-4 + the crow.
- **Provenance of this doc:** reverse-engineered from the live `src/`, `docs/RESEARCH.md`, the
  project design-memory, and the full playtest/session history.

> **One correction surfaced while writing this spec:** the master loft knob is currently
> **`GRAVITY_G = 1.3`** (documented sweep `2.0 → 1.5 → 1.3`), *not* 2.0 as some older handoff notes
> state. `GRAVITY_G` is a free tuning knob, **not** an invariant — the invariant is that
> `AIR_DENSITY` scales with it in lockstep (`GRAV_SCALE`) so `stall < spawn < cruise` is preserved at
> any value. Use 1.3 as the current value.

## Contents
- **Part I** — Game vision & the central design thesis
- **Part II** — Research foundation (why the numbers are what they are)
- **Part III** — Architecture & code setup (module map, Rojo, authority/replication, build/run)
- **Part IV** — The flight physics kernel (`FlightPhysics.luau`)
- **Part V** — GameConfig: the complete tunables reference
- **Part VI** — Client: controls, mouse-aim, cameras (`BirdController` / `GameUI`)
- **Part VII** — Server authority + shared helpers (`GameServer`, `Boids`, `BirdCollision`, `SpatialHash`, `BirdBuilder`)
- **Part VIII** — The LOCKED CONTROL SPECS registry (CS-1 … CS-9)
- **Part IX** — Flight-model evolution & lessons learned
- **Part X** — Reconstruction checklist & acceptance criteria
- **Part XI** — Open frontier

---

# Part I — Game vision & the central design thesis

## Game vision & win condition

**Eagles vs Crows** is a physics-based aerial melee combat game for **Roblox (Luau)**. It is an
**asymmetric 1-vs-many dogfight**:

- **EAGLE** — one bird per player. A **boom-and-zoom energy fighter**: high mass/momentum, keeps its
  energy, wide turns, high dive cap, high endurance (≈ 4 crows' worth of staying power), powerful
  diving attacks, climbs higher. Wins by **attrition**.
- **CROWS** — a squad of **4** per player. An **angles fighter**: low wing-loading, tight turns,
  cheap turns, low stall, low dive cap. The player **possesses** one main-attacker crow at a time;
  the other 3 hold an **adjustable formation (tight ↔ loose)** and support. The player can **swap**
  which crow is controlled. The crow player stays alive while **≥ 1 crow survives**. Crows
  out-maneuver the eagle and **trade / sacrifice via collisions**.
- **Combat** — close-range natural melee only: **beak**, **foot/talon**, or a full-speed **lose-lose
  collision**. Crows sacrifice themselves in collisions; the eagle wins the attrition math.
- **Flight** — superb 6DOF: banking, head-led yaw, wing-angle pitch with trailing tail, stalls,
  thermals/lift, loops and barrel rolls at speed.
- **Tech constraint** — client-authoritative flight (`SetNetworkOwner` to the controlling client),
  server-authoritative for damage/score. Must scale to many simultaneous swarms and "run extremely
  well."

**Definition of "done" (v1 playable):** two teams spawn as birds, fly with the 6DOF model, attack
via beak/talon/collision, the 4-crow possession + formation loop works, rounds start/score/end, and
it holds framerate with multiple swarms. "Working" is not "good" — the balance unknowns (Part XI)
gate *good*.

## Central design thesis — flight and balance are ONE system

This is the load-bearing design law. **Do not violate it.**

> *"The flight mechanics/physics and the balancing of the 4-corvid formation vs the eagle are
> inseparable — they are a single system."* — Chad (designer/player)

**Why:** who can cut off, out-turn, or dive on whom is decided *entirely* by the flight model — turn
radius vs closure speed, energy state, climb ceiling. Balance therefore lives **inside the physics
numbers**, not in a separate stats layer bolted on top. **Every flight number is also a balance
number.**

**Two hard corollaries:**
1. **Performance is a hard constraint on both**, not a separate concern — "it has to run extremely
   well."
2. **On every tuning edit, reason about the 1-eagle-vs-4-crow matchup.** Change a flight parameter →
   immediately ask how it shifts the 1-v-4; balance the matchup → change it *through* the flight
   model, not via arbitrary HP/damage tweaks.

**The asymmetry, expressed as physics:**

| | Eagle (energy fighter) | Crow (angles fighter) |
|---|---|---|
| Wing loading | High → fast, **wide** turns, strong dive | Low → **tight** turns, fast roll, cheap turns |
| Energy | Keeps E; boom-and-zoom; high dive cap; climbs highest | Bleeds E faster; low dive cap; can't loiter high |
| Sustained turn | Weaker | **Wins the prolonged turn fight** |
| Role | Force isolation; pick off loners; win attrition | Mob, dilute, trade collisions, out-angle |

The whole game is a great **asymmetric energy fight** — the eagle keeping energy through a zoom-climb
(an ascending defensive spiral over lower-energy crows), balanced against 4 crows that win by
**saturation**.

---

# Part II — Research foundation (why the numbers are what they are)

Grounded by a verified deep-research pass (**108 agents, 25 sources, 24/25 claims survived
adversarial verification**; v2/v3/v4 implementation passes added more). Full report in
`docs/RESEARCH.md`. Every claim below drove a number in `GameConfig.luau`.

**1. The master lever is energy/altitude.** Altitude is convertible potential energy (gliding spends
it as drag; thermals restore it). Energy-Maneuverability theory gives **one** tunable currency:
`Ps = V·(T−D)/W` (specific excess power ∝ climb/sink rate). Balance both classes through it.

**2. The dive must be priced.** Real data (Brighton et al. 2021, Swainson's hawks): a stoop
**tripled** capture odds — **3.46×** (CI 1.43–8.82) vs level flight → `Eagle.diveAttackMultiplier =
3.46`. But a **missed** dive must dump the bird into a low-energy state = the crows' counterplay
window (`staminaDiveCost`, stall risk).

**3. Two turn parameters, not one** (verifier caveat). High wing loading helps the *instantaneous*
turn while **hurting** the *sustained* turn — so the model needs **both** `wingLoading` (lift
equation) AND a separate `sustainedTurnRate` (coordinated-turn cap). A crow can lose the merge but
win the prolonged turn fight.

**4. 1-v-many balance is GEOMETRY, not stats.** Hawk-vs-swarm data: lone/peripheral individuals were
attacked ~10% of the time despite ~0.2% of population (order-of-magnitude over-targeting); **no
confusion effect** — protection is pure **dilution / safety-in-numbers**. ⇒ **Formation tightness is
the crow player's core risk knob** (tight = protected + concentrated offense but catastrophic
collision/dive exposure; loose = coverage/resilience but creates stragglers). The eagle's job is to
**force isolation**.

**5. Squad AI = Reynolds boids on the same flight engine.** Separation/alignment/cohesion over a
local distance+FOV neighborhood. Reynolds' decomposition (action-selection → steering → locomotion)
means boids output **control signals** consumed by the *same* `FlightPhysics` as the player — AI
crows fly identically.

**6. Induced drag ∝ load-factor².** Drag polar `CD = CD0 + K·CL²`, `K = 1/(π·AR·e)`. Because lift ∝
CL and g-load ∝ CL, induced drag ∝ n² — hard turns bleed energy. The principled E-M cost for free.

## The real-scale calibration crux (the deepest "why")

North-star: "make Eagles vs Crows the best flight model on Roblox" via real raptor scale — **2 km
eagle ceiling, much bigger map, real dive speeds**. All three shared **one** root cause: the world
was built at Roblox's default gravity (196.2 studs/s²), which at the canonical **1 stud = 0.28 m** is
**≈5.6× real g** — exactly why dives felt "too punchy with no room to develop a stoop."

The fix rests on a **recalibration theorem**: drop gravity by factor *k* **and** drop `AIR_DENSITY`
by the same *k*, and every equilibrium that defines the flight envelope is **invariant** because *k*
cancels:
- **Stall speed** `v_stall = √(g·wingLoading / (clMax·ρ))` → g↓k, ρ↓k cancel → **unchanged**. The
  **`stall < spawn < cruise`** invariant is therefore *structurally guaranteed at any k* (verified
  identical at `GRAVITY_G ∈ {1, 2, 3}`).
- **Cruise trim AoA**, **terminal velocity**, **glide ratio/sink rate** → unchanged (pure CL/CD
  geometry).
- What *does* change by design: **accelerations get gentler ×k** (fixes "punchy"), **turn radius
  grows ×k**, **dives need ×k more distance** to develop → so the world must grow ~k (hence the 2 km
  ceiling + 16k arena).

Implemented as **one knob**: `GameConfig` derives gravity from `METERS_PER_STUD = 0.28` ×
**`GRAVITY_G`** (fraction of real g), and scales every gravity-coupled force (`flapThrust`,
`flapClimbForce`, `Thermals.strength`, `AIR_DENSITY`) by `GRAV_SCALE = GRAVITY/196.2`. **`GRAVITY_G`
was swept 2.0 → 1.5 → 1.3 (current 1.3)** for more loft and less climb-speed bleed. Speeds, all rad/s
rates, `TERMINAL_VELOCITY = 400`, `diveSpeedCap = 320` are scale-free and stay.

**Already biologically accurate at 0.28 m/stud** (don't touch the speeds): golden-eagle stoop 240–320
studs/s (`diveSpeedCap 320`), peregrine ~382 (`TERMINAL 400`), eagle cruise/soar 130/46 (`glideSpeed
130`), soaring altitude 1350–2000 m → ~4800–7150 studs (`SERVICE_CEILING ≈ 7143`).

**Two research claims REFUTED — heed them:**
- "Server authority prevents speedhacks for free" **failed**. Client authority is an unverifiable
  attack surface — the **server must own all damage/score** and validate movement with an envelope
  that does **not** false-positive intended dives/loops/thermals.
- "Corner velocity = the Ps=0 sustained point" is wrong — corner is the **instantaneous** point
  (`V_corner = V_stall·√(n_max)`); sustained is `Ps = 0`.

**Honest caveats:** the quantitative data is hawks-vs-**bats**, not eagles-vs-crows (mechanism
transfers, not a literal measurement). The signature **lose-lose collision** mechanic has **no source
backing** — unverified design (placeholder numbers; tune by playtest). Roblox's Server Authority /
`SetPredictionMode` is the *opposite* of our client-authoritative default and is **mutually exclusive
with `SetNetworkOwner`** — a future spike, not adopted.

---

# Part III — Architecture & code setup

## Module map (Rojo `src/` → Roblox services)

| File | Roblox location | Role |
|------|-----------------|------|
| `src/shared/GameConfig.luau` | `ReplicatedStorage.GameConfig` | **The contract + all tunables.** Profiles, Flight, Controls, Camera, Squad, Thermals, Round, Combat, Security, UI. |
| `src/shared/FlightPhysics.luau` | `ReplicatedStorage.FlightPhysics` | Pure 6DOF aerodynamic engine. Touches no instances. The core. |
| `src/shared/BirdBuilder.luau` | `ReplicatedStorage.BirdBuilder` | Procedurally builds Eagle/Crow Models; `AnimateWings`. |
| `src/shared/Boids.luau` | `ReplicatedStorage.Boids` | Reynolds boids → flight-input for AI crows. |
| `src/shared/BirdCollision.luau` | `ReplicatedStorage.BirdCollision` | Swept-sphere obstacle/ground collision (`workspace:Spherecast`). The only shared module that touches Workspace. |
| `src/shared/SpatialHash.luau` | `ReplicatedStorage.SpatialHash` | Uniform-grid broad-phase backing proximity queries. |
| `src/server/GameServer.server.luau` | `ServerScriptService.GameServer` | **Authority:** spawning, combat, collisions, AI crows, rounds, scoring, anti-cheat, Remotes. |
| `src/client/BirdController.client.luau` | `StarterPlayerScripts.BirdController` | Client flight loop, input, camera, free-look FX. |
| `src/client/GameUI.client.luau` | `StarterPlayerScripts.GameUI` | HUD (built entirely in code). |

**Rojo project (`default.project.json`)** maps `src/shared/*` → `ReplicatedStorage`, `src/server/*` →
`ServerScriptService`, `src/client/*` → `StarterPlayer.StarterPlayerScripts`. File suffix sets the
Roblox class: `*.server.luau` → `Script`, `*.client.luau` → `LocalScript`, `*.luau` →
`ModuleScript`. Both client scripts live in **StarterPlayerScripts, NOT StarterGui**: with
`CharacterAutoLoads=false`, StarterGui is never copied to PlayerGui, so a HUD script there would never
run.

## Authority / replication model

- **Client owns its bird's physics.** The server hands network ownership of the possessed bird's
  `Body` part to the controlling client (`SetNetworkOwner`), which runs `FlightPhysics` locally and
  writes `Body.CFrame` + `AssemblyLinearVelocity`. Latency-free flight AND the CPU-scaling mechanism.
- **Server owns everything fairness-critical:** damage, scoring, collisions, AI crows, round flow,
  and a movement anti-cheat envelope. Client CFrame/velocity is untrusted — the server measures
  motion from **position deltas only**, never client velocity.
- **Player representation — the canonical decision:** `CharacterAutoLoads = false`; each player's
  bird(s) are **standalone Models in `Workspace.Birds`**, NOT a Roblox Character / `HumanoidRootPart`
  (a 4-crow squad can't be one character). The entire client-acquisition + handoff-safety contract is
  three Model attributes (`OwnerUserId`, `Team`, `Possessed`) plus the PrimaryPart's `NetOwner` /
  `Health` / strike-HUD attributes. **Do not revert the standalone-model decision.**
- **Obstacle/ground collision is real** (not the old `Y<4` stopgap): `BirdCollision.resolve` sweeps a
  `Spherecast` along each step. Any code that moves a bird by CFrame must route through
  `BirdCollision` or it tunnels.
- **AI crows** (the 3 unpossessed) are server-simulated on the SAME `FlightPhysics` as the player.

## Contracts that span files (grep before renaming)

- **`FlightPhysics` API:** `.new(profile, position)`; `:Update(dt, input)` with `input =
  {pitch, roll, yaw, flap/flapThrottle, dive}`; `:SetThermalForce(v)`; `:SetWind(v)`. Readable
  fields: `orientation` (CFrame), `velocity`, `speed`, `verticalSpeed`, `stamina`, `isFlapping`,
  `isDiving`, `isStalling`, `flapPhase`, `aoaDeg`, `flapThrottle`, `flapPower`, `flapFreqHz`,
  `pitchVel`/`rollVel`/`yawVel`.
- **`GameConfig`** tables consumed by name across client/server: `Profiles.Eagle/.Crow`, `Flight`,
  `Controls`, `Camera`, `Squad`, `Thermals`, `Round`, `Combat`, `Security`, `UI`. Eagle/Crow profiles
  are structurally identical — **all asymmetry is in the numbers**.
- **Remotes** (`ReplicatedStorage.Remotes`, created by `GameServer`): see Part VII §7.
- **UI `_G` hooks:** `GameUI` exposes `_G.UpdateStaminaUI(ratio)`, `_G.SetStallWarning(isStalling)`,
  `_G.SetIncidence(deg)`, `_G.UpdateFlapUI(throttle, freqHz, power)`; `BirdController` calls them.

## Build & run

Luau deployed to Roblox — no compiler/linter/test runner, Roblox isn't headless, so **the only real
validation is pressing Play in Studio.** Rojo sync via `default.project.json`; wrapper scripts
self-bootstrap a pinned Rojo binary (`tools/Bootstrap-Rojo.ps1` downloads v7.6.1 into `tools/bin/`,
gitignored, on first use):
- **`.\serve.ps1`** — live-sync into Studio (connect the Rojo plugin).
- **`.\build.ps1`** — one-shot place build → `EaglesVsCrows.rbxlx` (gitignored). `-Watch` to rebuild
  on change.
- **`.\rojo.ps1 <args>`** — raw passthrough to the bootstrapped binary.

`build.ps1` succeeding confirms the project wiring resolves and scripts map to the right classes, but
does **not** syntax-check Luau or run anything. First task after any change is still a Studio smoke
test.

---

# Part IV — The flight physics kernel (`FlightPhysics.luau`)

## 0. Purpose & conventions

`FlightPhysics` (v2 — deterministic 6DOF aerodynamic engine) is a **pure simulation module**: it
touches **no Roblox instances**. Callers feed it an `input` table each frame via `:Update(dt, input)`
and read back `orientation` (CFrame) and `velocity` (Vector3) to drive a `BasePart`. `orientation`
and `velocity` are **externally-authoritative**: a caller may overwrite them (e.g. after a collision
sweep) and the engine reads them fresh at the top of the next step. First line is `--!nonstrict`.

Metatable class (`FlightPhysics.__index = FlightPhysics`). Requires `GameConfig`; `local F =
GameConfig.Flight`. Every `F.*` is a field of `GameConfig.Flight`; every `p.*`/`profile.*` is a field
of the profile (`GameConfig.Profiles.Eagle`/`.Crow`). Module constant `EPS = 1e-4`.

## 1. Helper functions

**`clamp(x, lo, hi)`** — branchy clamp.

**`rotateTowards(from, to, maxRad)`** — rotate unit `from` toward unit `to` by ≤ `maxRad`, returning
a **unit** vector (normalized lerp, not slerp). `d=clamp(from·to,-1,1)`; `angle=acos(d)`; if
`angle<EPS` return `to`; `t=clamp(maxRad/angle,0,1)`; `result=from*(1-t)+to*t`; antipodal guard →
`to`; else `result.Unit`. Used to redirect velocity toward the nose (grip/turn).

**`rotateLookToward(cf, target, maxRad)`** — rigidly rotate an orientation CFrame so its LookVector
turns toward unit `target` by ≤ `maxRad`, carrying roll/bank and **preserving position** (the
weathervane). Position preservation is essential — left-multiplying a rotation onto a CFrame swings
its position about the world origin (a teleport):
```
if maxRad < EPS then return cf end
look=cf.LookVector; d=clamp(look·target,-1,1); angle=acos(d)
if angle<EPS then return cf end
axis=look×target; if axis.Magnitude<EPS then return cf end     -- parallel guard
r=CFrame.fromAxisAngle(axis.Unit, min(angle,maxRad))
pos=cf.Position; return r*(cf-pos)+pos                          -- basis rotation about pos
```

**`computeCL(p, aoaDeg)`** — the **lift curve**, signed. Baseline `cl0` at zero AoA (THE "not enough
lift" fix), linear slope to `clMax` at stall, then forgiving linear roll-off to `postStallCl` over a
`stallPadDeg` band (mush, not cliff):
```
linear = p.cl0 + p.liftSlopePerDeg*aoaDeg
mag = abs(aoaDeg)
if mag <= p.stallAngleDeg then return clamp(linear, -p.clMax, p.clMax) end
over = mag - p.stallAngleDeg
t = clamp(over / max(EPS, p.stallPadDeg), 0, 1)
clMag = p.clMax + (p.postStallCl - p.clMax)*t
return (linear >= 0) and clMag or -clMag
```

**`FlightPhysics:_authority()`** — airspeed-driven control authority in `[0,1]`:
`clamp((self.speed - F.CONTROL_AUTHORITY_MIN_SPEED) / max(EPS, F.CONTROL_AUTHORITY_FULL_SPEED -
F.CONTROL_AUTHORITY_MIN_SPEED), 0, 1)`.

## 2. Constructor `FlightPhysics.new(profile, position)`

| Field | Init |
|---|---|
| `self.profile` | `profile` |
| `self.orientation` | `CFrame.new(position or Vector3.new(0,200,0))` (LookVector = `(0,0,-1)`) |
| `self.velocity` | `orientation.LookVector * (profile.glideSpeed * 0.9)` — **spawn speed = 0.9×glideSpeed**, above stall |
| `self.stamina` | `profile.maxStamina` |
| `self.speed` | `velocity.Magnitude` |
| `self.verticalSpeed` | `velocity.Y` |
| `self.aoaDeg` | `0` |
| `self.isFlapping / isDiving / isStalling` | `false` |
| `self.flapPhase` | `0` |
| `self._rollVel / _pitchVel / _yawVel` | `0` |
| `self._thermal` | `Vector3.new()` |
| `self._wind` | `F.WIND_BASE` |

Setters: `:SetThermalForce(v)` → `_thermal = v or Vector3.new()`; `:SetWind(v)` → `_wind = v or
Vector3.new()`.

## 3. `:Update(dt, input)` — full pipeline, in order

**Preamble:** `dt = min(dt, 1/30)` (spike guard); read `inPitch/inRoll/inYaw` (default 0).

**(1) Flap-throttle interpretation.** Continuous path (player) uses `input.flapThrottle ∈ [-1,1]`;
legacy boolean path (AI crows, `flapThrottle` nil) uses `input.flap`/`input.dive`:
```
throttle = input.flapThrottle
if throttle ~= nil then
    flapPow  = min(1, abs(throttle))
    wantFlap = (throttle > 0.02) and self.stamina > 0
    wantDive = (input.dive == true) or (throttle < -0.02)
else
    flapPow = 1; wantFlap = input.flap and self.stamina > 0; wantDive = input.dive == true
end
```
`flapPow` scales thrust, powered-climb lift floor, climb assist, stamina cost, wingbeat frequency.

**(2) Vertical envelope: service ceiling & flap authority floor.**
```
ceiling   = F.SERVICE_CEILING * (p.climbCeilingBonus or 1)
altFactor = clamp((ceiling - cf.Position.Y) / max(EPS, F.CEILING_BAND), 0, 1)
if wantFlap then authority = max(authority, F.FLAP_AUTHORITY_FLOOR * altFactor) end
```
`altFactor` = 1 below the ceiling, → 0 at it. Flapping floors authority so a low-airspeed climb is
still commandable — it then ends from **fatigue** (stamina→0 → `wantFlap` false) or the ceiling.

**(3) Rotational control with inertia (local-space).** Frame-rate-independent smoothing:
```
inertia = p.rollInertia; blend = 1 - inertia^(dt*60)
smooth(cur,tgt) = cur + (tgt-cur)*blend
self._rollVel  = smooth(self._rollVel,  inRoll *p.rollRate *authority)
self._pitchVel = smooth(self._pitchVel, inPitch*p.pitchRate*authority)
self._yawVel   = smooth(self._yawVel,   inYaw  *p.yawRate  *authority)
rot = CFrame.Angles(self._pitchVel*dt, self._yawVel*dt, self._rollVel*dt)  -- X pitch, Y yaw, Z roll
cf = self.orientation * rot   -- LOCAL-space (right-multiply); look=cf.LookVector; up=cf.UpVector
```
No auto-level here → loops and rolls at speed.

**(4) Aerodynamics (world-space accels).**
```
airVel = self.velocity - self._wind; speed = airVel.Magnitude; accel = Vector3.new()
accel += Vector3.new(0, -F.GRAVITY, 0)          -- persistent gravity
```
If `speed > EPS`:
- *AoA (signed, about wing axis; + when nose above path):*
  `velDir=airVel.Unit; cosA=clamp(look·velDir,-1,1); aoa=acos(cosA); if up·velDir>0 then aoa=-aoa;`
  `self.aoaDeg=deg(aoa); self.isStalling = |aoaDeg| > p.stallAngleDeg`.
- *Lift + powered-climb floor:*
  ```
  cl = computeCL(p, self.aoaDeg)
  if wantFlap and altFactor>0 and |aoaDeg|>p.stallAngleDeg then
      powered = p.clMax * F.FLAP_LIFT_FLOOR * altFactor * flapPow
      if powered > |cl| then cl = (aoaDeg>=0) and powered or -powered end
  end
  q = F.AIR_DENSITY * speed*speed                 -- q = ρ·v² (the ½ folded into coefficients)
  liftAccel = (cl*q) / p.wingLoading              -- mass-INDEPENDENT; wingLoading is the lever
  liftDir = up - velDir*(up·velDir); if liftDir.Magnitude>EPS then accel += liftDir.Unit*liftAccel end
  ```
- *Drag polar (a force → /mass):*
  ```
  dragMag = (p.parasiticDrag + p.inducedDragK*cl*cl) * q
  if wantFlap and look.Y > -0.2 and p.flapDragRetention then          -- non-dive only
      dragMag = dragMag * (1 - clamp(p.flapDragRetention*flapPow, 0, 0.95))
  end
  accel -= velDir * (dragMag / p.mass)
  ```
- *Energy-retention gravity cancel (the "War Thunder ARCADE" term)* — the dominant climb bleed is
  gravity along the flight path (`GRAVITY·velDir.Y`), not drag. Add back a fraction, **climb-only**
  so the dive/stoop is untouched; capped `<0.95` (never noclip); persistent (NOT flap-gated):
  ```
  if p.energyRetention and velDir.Y > EPS then
      gAlongClimb = F.GRAVITY * velDir.Y
      accel += velDir * (clamp(p.energyRetention, 0, 0.95) * gAlongClimb)
  end
  ```
Else (`speed<=EPS`): `self.isStalling=true; self.aoaDeg=0`.

**(5) Thrust, powered-climb assist, thermal, phugoid.**
```
self.isFlapping = wantFlap and true or false
self.isDiving   = look.Y < -0.2                       -- dive from nose attitude alone
if wantFlap or (wantDive and self.isDiving) then
    thrust = (wantFlap and p.flapThrust or p.flapThrust*0.5) * flapPow   -- dive-key-only = half
    if self.isDiving then
        thrust *= p.diveThrustBonus
        band = (F.FLAP_DIVE_FADE_BAND or 0.4) * p.diveSpeedCap
        fade = clamp((p.diveSpeedCap - self.velocity.Magnitude)/max(1,band), F.FLAP_DIVE_FLOOR or 0.1, 1)
        thrust *= fade                                 -- full bite low/mid dive, fades near cap
    end
    accel += look * (thrust * altFactor / p.mass)      -- along nose, ceiling-throttled, /mass
end
if wantFlap and look.Y > 0 then                        -- powered-climb assist (mass-INDEPENDENT)
    accel += Vector3.new(0, (p.flapClimbForce or 0)*flapPow*look.Y*altFactor, 0)
end
accel += self._thermal
release = 1 - clamp(abs(inPitch),0,1); if self.isDiving then release = 0 end
if release>0 and speed>EPS then                         -- phugoid damping (released by pitch, off in dive)
    q01 = clamp((speed*speed)/(p.glideSpeed*p.glideSpeed), 0, 1)
    accel += Vector3.new(0, -self.velocity.Y * F.PHUGOID_DAMPING * release * q01, 0)
end
```

**(6) Velocity integration:** `self.velocity += accel*dt`.

**(7) Static aerodynamic stability (weathervane) + aerobatic suppression** — gated on
`self.velocity.Magnitude > F.CONTROL_AUTHORITY_MIN_SPEED`:
```
vDir = self.velocity.Unit
stabRad = (F.STABILITY_RATE * p.stabilityRate * authority) * dt      -- STABILITY_RATE = 0 → no auto-level
if self.isStalling then
    over = (|aoaDeg| - p.stallAngleDeg)/max(EPS,p.stallAngleDeg)
    stabRad += (p.recoverNoseDownRate * clamp(over,0,2) * authority) * dt   -- recoverNoseDownRate = 0
end
aero = clamp((velMag - F.AEROBATIC_MIN_SPEED)/max(EPS,F.AEROBATIC_SPEED_BAND),0,1)
cmd  = max(|inPitch|,|inRoll|)
stabRad *= (1 - aero*cmd)                                            -- fast + aggressive = suppress weathervane
cf = rotateLookToward(cf, vDir, stabRad); look=cf.LookVector; up=cf.UpVector
```

**(8) GRIP / alignment ("flies where you point")** — redirect velocity toward the nose in EVERY
attitude; isotropic base + bank-scaled sustained-turn term (the eagle-wide/crow-tight lever). Same
speed-gate block:
```
bank = 1 - |up.Y|                                          -- 0 wings-level .. 1 knife-edge
trackRate = (F.GRIP_RATE + p.sustainedTurnRate*bank) * authority
if trackRate > EPS then
    vMag = self.velocity.Magnitude
    self.velocity = rotateTowards(self.velocity.Unit, look, trackRate*dt) * vMag
end
```

**(9) Speed caps:**
```
cap = self.isDiving and p.diveSpeedCap or p.maxLevelSpeed; cap = min(cap, F.TERMINAL_VELOCITY)
sp = self.velocity.Magnitude; hardCap = self.isDiving and p.diveSpeedCap or F.TERMINAL_VELOCITY
if sp > hardCap then self.velocity = self.velocity.Unit * hardCap
elseif (not self.isDiving) and (not wantFlap) and sp > cap then
    self.velocity = self.velocity.Unit * (cap + (sp-cap)*max(0, 1 - dt*0.5))   -- gentle glide bleed
end
```

**(10) Position integration & orientation rebuild:**
```
newPos = cf.Position + self.velocity*dt
self.orientation = CFrame.fromMatrix(newPos, cf.RightVector, cf.UpVector, -cf.LookVector)  -- 3rd arg = -Look
```

**(11) Stamina — "a dive is a rest" (CS-9):**
```
if wantFlap and not self.isDiving then
    self.stamina = max(0, self.stamina - p.staminaFlapCost*flapPow*dt)
else
    self.stamina = min(p.maxStamina, self.stamina + p.staminaRegen*dt)   -- glide AND dive regen
end
```
`staminaDiveCost` is present in config but **no longer read**.

**(12) Derived readouts & animation phase:**
```
self.speed=velMag; self.verticalSpeed=velocity.Y
flapFreq = self.isFlapping and (2 + 9*flapPow) or 2       -- 2 Hz idle .. 11 Hz full flap
self.flapPhase = (self.flapPhase + dt*flapFreq) % (2π)
self.flapThrottle = throttle or (wantFlap and 1 or 0)
self.flapFreqHz = flapFreq; self.flapPower = flapPow
self.pitchVel = self._pitchVel; self.rollVel = self._rollVel; self.yawVel = self._yawVel   -- for PD mouse-aim
return self
```

---

# Part V — GameConfig: the complete tunables reference

File header `--!strict`. Units: studs, seconds. **This is the single source of truth for all
numbers.**

## Scale / gravity derivation (module-local constants)

| Const | Value | Meaning |
|---|---|---|
| `METERS_PER_STUD` | `0.28` | Roblox canonical scale; `meters(m)=m/0.28`. |
| `REAL_G` | `9.81` | Real gravity m/s². |
| `GRAVITY_G` | `1.3` | **THE sweep knob** (fraction of real g; swept 2.0→1.5→1.3). |
| `GRAVITY` | `REAL_G*GRAVITY_G/METERS_PER_STUD` | ≈ **45.6 studs/s²** at 1.3. Server sets Workspace.Gravity to match. |
| `LEGACY_GRAVITY` | `196.2` | Gravity the v2 feel was originally calibrated at. |
| `GRAV_SCALE` | `GRAVITY/LEGACY_GRAVITY` | ≈ **0.232** at 1.3. Multiplies every gravity-coupled force. |
| `GameConfig.MetersPerStud` | `0.28` | Exposed for real-unit readouts. |

**GRAV_SCALE is applied to exactly four values** (holds their ratio to weight): `AIR_DENSITY`,
Eagle/Crow `flapThrust`, `flapClimbForce`, `Thermals.strength`. Everything scale-free (all speeds,
control-authority speeds, every rad/s rate, `TERMINAL_VELOCITY`, `CRASH_SPEED`) is **unchanged**. The
`AIR_DENSITY` base literal (0.044) is the loft lever; sweep `GRAVITY_G` for accel punch.

## `GameConfig.Flight`

| Field | Value | Meaning |
|---|---|---|
| `GRAVITY` | ≈45.6 | studs/s². |
| `GRAVITY_G` | `1.3` | Echoed for tooling. |
| `GRAV_SCALE` | ≈0.232 | Echoed. |
| `AIR_DENSITY` | `0.044 * GRAV_SCALE` (≈0.0102) | Abstract scalar folding ½ρ·wingArea into lift/drag. |
| `WIND_BASE` | `Vector3.new(0,0,0)` | Ambient wind. |
| `CONTROL_AUTHORITY_MIN_SPEED` | `20` | studs/s where control ≈ 0. |
| `CONTROL_AUTHORITY_FULL_SPEED` | `90` | studs/s where control is full. |
| `AEROBATIC_MIN_SPEED` | `60` | Airspeed above which aerobatics unlock (near-cosmetic now STABILITY_RATE=0). |
| `TERMINAL_VELOCITY` | `400` | Hard top speed; anti-cheat basis. |
| `STABILITY_RATE` | `0` | Weathervane strength — **zeroed** (no auto-level). |
| `GRIP_RATE` | `2.2` | Grip/alignment assist (rad/s base, airspeed-scaled). |
| `PHUGOID_DAMPING` | `2.1` | Vertical stabilizer; released by pitch, off in dive. |
| `SERVICE_CEILING` | `meters(2000)` ≈7143 | Envelope top (eagle, climbCeilingBonus=1). |
| `CEILING_BAND` | `meters(170)` ≈607 | Band below ceiling over which flap fades to 0. |
| `FLAP_AUTHORITY_FLOOR` | `0.6` | Min authority while flapping. |
| `FLAP_LIFT_FLOOR` | `0.55` | Fraction of clMax retained past stall while flapping. |
| `FLAP_DIVE_FADE_BAND` | `0.4` | Top fraction of diveSpeedCap over which dive flap thrust fades. |
| `FLAP_DIVE_FLOOR` | `0.1` | Min dive flap thrust fraction at the top end. |
| `AEROBATIC_SPEED_BAND` | `40` | studs/s band over which aerobatic freedom ramps in. |
| `CRASH_SPEED` | `45` | Closing speed at/above which a map impact is lethal. |

*(No `PATH_TRACK_RATE` — replaced by `STABILITY_RATE`/`GRIP_RATE`.)*

## `GameConfig.Profiles` — Eagle vs Crow

Structurally identical; `flapThrust`/`flapClimbForce` stored as `literal * GRAV_SCALE`.

| Field | Eagle | Crow | Meaning |
|---|---|---|---|
| `displayName` | `"Eagle"` | `"Crow"` | |
| `mass` | `16` | `3.0` | Momentum / energy retention. |
| `wingLoading` | `1.0` | `0.55` | HIGH eagle wide turns; LOW crow tight turns/low stall. |
| `cl0` | `0.30` | `0.30` | **Baseline lift at zero AoA — never set to 0.** |
| `liftSlopePerDeg` | `0.11` | `0.11` | Lift-curve slope. |
| `clMax` | `1.95` | `1.6` | Peak lift. |
| `postStallCl` | `0.70` | `0.90` | Lift retained past stall (crow more forgiving). |
| `stallPadDeg` | `6` | `8` | Roll-off band beyond stall angle. |
| `parasiticDrag` | `0.020` | `0.045` | Low eagle = great glide/dive. |
| `inducedDragK` | `0.58` | `0.55` | CD_i = k·CL². |
| `stallAngleDeg` | `27` | `24` | Critical AoA. |
| `stabilityRate` | `1.0` | `0.7` | Weathervane multiplier (moot while STABILITY_RATE=0). |
| `recoverNoseDownRate` | `0` | `0` | Past-stall auto-recovery DISABLED. |
| `flapThrust` | `900*GRAV_SCALE` (≈209) | `185*GRAV_SCALE` (≈43) | Forward force per flap. |
| `flapClimbForce` | `500*GRAV_SCALE` (≈116) | `200*GRAV_SCALE` (≈46) | Powered-climb lift (mass-indep). |
| `flapDragRetention` | `0.6` | `0.4` | Drag bleed cancelled while flapping (level/climb). |
| `energyRetention` | `0.7` | `0.4` | Persistent climb gravity-cancel; eagle higher (1-v-4 lever). |
| `glideSpeed` | `130` | `95` | Cruise. |
| `maxLevelSpeed` | `170` | `140` | Top level speed. |
| `diveThrustBonus` | `1.6` | `1.25` | Thrust × while diving. |
| `diveSpeedCap` | `320` | `220` | Top dive speed. |
| `rollRate` | `3.2` | `5.0` | rad/s instantaneous roll. |
| `pitchRate` | `2.0` | `3.6` | rad/s pitch. |
| `yawRate` | `1.1` | `1.8` | rad/s head-led yaw. |
| `sustainedTurnRate` | `1.0` | `2.1` | rad/s sustained-turn ceiling (eagle wide, crow tight). |
| `rollInertia` | `0.55` | `0.20` | 0..1 sluggishness. |
| `maxStamina` | `320` | `70` | Stamina budget. |
| `staminaFlapCost` | `5` | `6` | Per second full up-throttle flapping. |
| `staminaDiveCost` | `4` | `5` | **Legacy/unused** (dives no longer cost stamina). |
| `staminaRegen` | `16` | `9` | Per second gliding/diving. |
| `climbCeilingBonus` | `1.0` | `0.7` | × SERVICE_CEILING (crow ~5000). |
| `health` | `99` | `25` | Eagle = 3 clean hits. |
| `beakDamage` | `22` | `9` | Close peck. |
| `talonDamage` | `34` | `12` | Grab/strike. |
| `diveAttackMultiplier` | `3.46` | `2.0` | Stoop lethality × (research). |
| `collisionDamageDealt` | `60` | `30` | Damage to the rammed bird. |
| `collisionDamageTaken` | `0.85` | `1.4` | Vulnerability × on incoming ram. |
| `bodyRadius` | `4.5` | `2.2` | Collision/attack reach (studs). |

## `GameConfig.Combat`

`eagleHits = 3`; `bankStrikeThresholdDeg = 18` (**legacy/unused** — zone now picked by proximity);
`strikeSelectRange = 200`. **`strikes`** sub-table (server owns all timers + zone pick):

| Strike | startup | duration | cooldown | axis | coverHalfAngleDeg | damage | reachFraction |
|---|---|---|---|---|---|---|---|
| `talon` | 0.10 | 4.0 | 2.0 | `"belly"` (swings with bank) | 70 | `"talon"` | 0.85 |
| `beak` | 0.10 | 2.0 | 4.0 | `"forward"` | 35 | `"beak"` | 0.85 |

During the active window the cone parries an incoming ram AND deals offensive damage (one
catch-or-hit). ⚠️ talon 4s/2s ≈ 67% uptime — near the ">50% always-on" guardrail.

## `GameConfig.Squad`

`size=4`, `defaultFormation="loose"`, `engageRadius=45`, `swapCooldown=0.35`.
**`boids`**: `separationWeight=1.5`, `alignmentWeight=1.0`, `cohesionWeight=1.0`, `neighborRadius=60`,
`neighborFovDeg=270`, `maxSteerForce=220`.
**`formations`**: tight `{spacing=8, cohesionMul=1.6, separationMul=0.7, collisionRisk=1.5}`; loose
`{spacing=26, cohesionMul=0.8, separationMul=1.4, collisionRisk=0.7}`.
**`avoidance`** (AI crows only): `lookaheadTime=1.5`, `minDistance=60`, `maxDistance=350`,
`spherePad=10`, `weight=3.0`.

## `GameConfig.Thermals`

`count=8`, `radius=meters(110)≈393`, `minHeight=meters(30)≈107`, `maxHeight=meters(1800)≈6428`,
`strength=140*GRAV_SCALE≈32.5`.

## `GameConfig.Round`

`intermission=8`, `roundLength=240`, `respawnDelay=4`. (Eagle dead → crows win; all 4 crows dead →
eagle wins.)

## `GameConfig.Security` (anti-cheat)

`enabled=true`, `speedAllowMult=1.25`, `teleportMult=1.5`, `pingPadStuds=30`, `bucketCapacity=120`,
`bucketLeak=200`, `graceSeconds=0.5`, `reclaimStrikes=3`, `kickStrikes=6`, `strikeDecaySeconds=12`.

## `GameConfig.Camera`

| Field | Value | | Field | Value |
|---|---|---|---|---|
| `baseDistance` | 40 | | `freeLookSensitivity` | 0.7 |
| `mouseAimDistance` | 135 | | `freeLookPitchLimitDeg` | 85 |
| `aimHeadingLag` | 1.4 | | `freeLookSmoothing` | 1.0 |
| `baseFOV` | 70 | | `aimFOV` | 22 |
| `diveFOV` | 95 | | `aimFadeBird` | 0.85 |
| `climbFOV` | 62 | | `aimZoomLerp` | 0.22 |
| `speedDistanceFactor` | 0.06 | | `zoomStep` | 24 |
| `bankTiltFactor` | 0.6 | | `minDistance` | 10 |
| `followSmoothing` | 0.18 | | `maxDistance` | 800 |
| `shakeAtSpeed` | 200 | | `heightFactor` | 0.35 |
| `shakeMagnitude` | 0.6 | | `zoomTopDownHeight` | 0.55 |
| `crestAngRate` | 3.0 | | `crestDamp` | 0.85 |
| `horizonLevelRate` | 2.0 | | `loopVertStart` | 0.5 |
| `loopVertBand` | 0.4 | | `chaseTurnRate` | 3.6 |
| `lookAheadFactor` | 0.3 | | `loopFollowUp` | 0.0 (legacy/unused) |

## `GameConfig.Controls`

**Legacy mouse-steer (disabled):** `mouseSteer=false`, `mouseSensitivity=1.0`, `mouseReturnRoll=3.0`,
`mouseReturnPitch=0.4`, `mouseExpo=1.7`, `invertPitch=false`.
**Keyboard tap→ramp:** `pitchTapFraction=0.30`, `pitchRampTime=0.55`, `bankTapFraction=0.22`,
`bankRampTime=0.50`.
**Mouse-aim (active instructor):** `mouseAim=true`, `aimMouseSensitivity=1.0`,
`aimAnglePerPixel=0.0035`, `aimLeadScreenFrac=0.95`, `aimMaxLeadDeg=70`, `aimResponse=13.0`,
`aimPitchDeadzone=0.006`, `aimPitchExpo=1.0`, `aimBankDeadzone=0.006`, `aimBankExpo=1.0`,
`aimCursorAreaFrac=0.5`, `aimRollGain=4.5`, `aimPitchGain=5.0`, `aimYawGain=1.0`, `aimLevelGain=0.9`,
`aimPitchDamp=0.45`, `aimRollDamp=0.40`, `aimStallBandDeg=4`, `invertPitch=false`,
`flapThrottleRate=1.1`. **Reticle:** `beakReticleDistance=90`, `talonReticleDistance=70`,
`talonArcSpreadDeg=60`. **Legacy/unused:** `aimCursorRadiusFrac=0.9`, `aimRecenterRate=0.0`,
`aimMarkerDistance=600`.

## `GameConfig.UI`

`hudColor=RGB(18,20,28)`, `hudTransparency=0.35`, `font=GothamBold`, `fontMedium=GothamMedium`,
`eagleAccent=RGB(220,170,70)`, `crowAccent=RGB(150,120,220)`, `healthBarColor=RGB(90,200,110)`,
`staminaBarColor=RGB(90,170,230)`.

## Other tables

`GameConfig.Visual = { birdScale = 1.8 }` (cosmetic only; combat uses `bodyRadius`).
`GameConfig.Debug = { soloFlight = true, aiCrowOpponents = true }` (dev aids; set false for prod).

---

# Part VI — Client: controls, mouse-aim, cameras

*Files: `src/client/BirdController.client.luau` (flight/input/camera/FX),
`src/client/GameUI.client.luau` (HUD). Both `LocalScript`s in `StarterPlayerScripts`. Canonical config
values are in Part V; inline `X or default` fallbacks below are code defaults, not the live values.*

## 1. The frame loop & bird acquisition

One persistent loop: `RunService.RenderStepped:Connect(onFlightStep)`. `onFlightStep(dt)` early-returns
unless `isAlive and flightEngine and rootPart and rootPart.Parent`. **Exact order (do not reorder):**
1. Thermals+wind → engine (`SetThermalForce(computeThermalForce(pos))`, `SetWind(Flight.WIND_BASE)`).
2. Mouse-mode lock (free-look OR aim → `MouseBehavior=LockCenter`, `MouseIconEnabled=false`).
3. Keyboard tap→ramp → `kbPitch/kbRoll/kbYaw`.
4. Mouse-aim autopilot + reticle: ease `aimApplied.*` toward `computeMouseAim(dt)` (steering) or → 0
   (free-look/RMB-zoom/aim-off).
5. **CS-1 global gate + input assembly.**
6. Flap throttle (Shift/Ctrl sticky) → `inputState.flapThrottle`.
7. `flightEngine:Update(dt, inputState)`.
8. Local collision slide (`BirdCollision.resolve`).
9. Write body: `rootPart.CFrame = engine.orientation`; `AssemblyLinearVelocity = engine.velocity`;
   `AssemblyAngularVelocity = Vector3.new()`.
10. `BirdBuilder.AnimateWings(...)`; `updateVortexTrails()`.
11. `updateCamera(dt)`.
12. `pushUI()`.

**Bird acquisition (no Character):** `findMyPossessedBird()` scans `Workspace.Birds` for a Model with
`OwnerUserId==player.UserId` and `Possessed==true`. `acquire()` (task.spawn): guards with an
`acquireGen` counter; re-arms free-look to the physically-held Space key; waits for
`Body:GetAttribute("NetOwner")==player.UserId` (5s best-effort) **before driving** (else client CFrame
writes fight the server sim → spawn rubber-band); then seeds the engine from the live body
CFrame/velocity so a swap doesn't snap. Re-acquire on `TeamAssigned`, the `Possessed` attribute
changing, and `Birds.ChildAdded/ChildRemoved`. `teardownDrive()` nils the camera basis so it snaps to
the new pose.

## 2. Control mapping (CS-7) & tap→ramp

Raw `kb = {pitch, roll, yaw}` (each −1/0/+1), separate from `inputState`:

| Key | axis | value | | Key | axis | value |
|---|---|---|---|---|---|---|
| W | pitch | −1 (nose down) | | A | roll | +1 (bank left) |
| S | pitch | +1 (nose up) | | D | roll | −1 (bank right) |
| Q | yaw | +1 (left) | | E | yaw | −1 (right) |

`InputEnded` zeroes an axis only if the released key still owns the current direction (opposed pairs
don't cancel). Shift/Ctrl = sticky flap throttle (ramped from held key each frame, no decay). Space =
free-look TOGGLE. LMB = `fireStrike()` (0.12s local debounce). RMB = `aimZoom.active`. Wheel =
`userZoom`. 1–4 = `SwapCrow`. F = `SetFormation` (toggle tight/loose). R = `Respawn`.

**`rampAxis`** — tap gives a small deflection, hold ramps to full; **release snaps mag to 0** (no
auto-level → attitude then holds):
```
if target ~= 0 then
    if state.sign ~= target then state.sign=target; state.mag=tapFrac
    else state.mag = min(1, state.mag + ((1-tapFrac)/max(0.01,rampTime))*dt) end
else state.sign, state.mag = 0, 0 end
return state.sign * state.mag
```
pitch uses `pitchTapFraction 0.30 / pitchRampTime 0.55`; roll & yaw use `bankTapFraction 0.22 /
bankRampTime 0.50`.

## 3. CS-1 — GLOBAL keyboard-over-aim gate (LOCKED)

```lua
local aimGate = (kb.pitch ~= 0 or kb.roll ~= 0 or kb.yaw ~= 0) and 0 or 1
inputState.pitch = clamp(kbPitch + aimApplied.pitch * aimGate, -1, 1)
inputState.roll  = clamp(kbRoll  + aimApplied.roll  * aimGate, -1, 1)
inputState.yaw   = clamp(kbYaw   + aimApplied.yaw   * aimGate, -1, 1)
```
Gate from **raw `kb.*`**, so it's immediate. **Global, not per-axis** — the whole point: while ANY
flight key is held, zero mouse-aim on **all three** axes so a held-S loop is straight. The old
per-axis form (`aimApplied.axis*(1-|kb.axis|)`) left roll/yaw aim-pull live and curved the loop off.
Do not re-add per-axis blending; do not re-anchor the cursor.

## 4. Mouse-aim — NOSE-CHASES-WORLD-CURSOR (`computeMouseAim(dt)`)

The cursor is a **world-anchored direction**; the nose chases it. Because it's world-fixed the nose
can catch it and the command → 0 (a screen-anchored cursor never resolves under a re-centring chase
cam). Pipeline:
1. **Swing the world cursor** by mouse delta (LockCenter + GetMouseDelta): `aimTargetDir` rotated
   about the CAMERA's screen axes (`dYaw=-delta.X*sens`, `dPitch=∓delta.Y*sens`,
   `sens=aimMouseSensitivity*aimAnglePerPixel`).
2. **Clamp to a reachable cone** around the nose: `maxLead = min(rad(aimMaxLeadDeg),
   atan(tan(FOV/2)*aimLeadScreenFrac))`; if outside, pin `aimTargetDir` at the cone edge → a held
   mouse = sustained lead = a turn/loop.
3. **Resolve into the BODY frame** (`localTarget = cf:VectorToObjectSpace(aimTargetDir)`): `rgt=.X`
   (horizontal), `upc=.Y` (vertical). Cursor-on-nose → 0 → straight.
4. **Deadzone+expo shaping** on both axes (`shapeAxis`), gentle near centre, full authority at edge.
5. **Ride-the-edge stall protection** (`aoaHead`): full nose-up until within `aimStallBandDeg` of
   stall; **suspended while powered** (`flapThrottle>0.05`) so a powered loop always commits.
6. **Elevator (PD):** `pitch = vCmd*aimPitchGain - aimPitchDamp*clamp(pitchVel/pitchRate,-1,1)`;
   nose-up scaled by `aoaHead`.
7. **Coordinated bank + rudder + level-assist (PD):** `roll = -hCmd*aimRollGain + levelAssist -
   aimRollDamp*clamp(rollVel/rollRate,-1,1)`; `yaw = -hCmd*aimYawGain`. The bank rolls the lift vector
   onto the target so the side error nulls *as it banks* (kills corkscrew); `levelAssist` rolls wings
   level only when there's no bank demand and only while upright (`max(0, cf.UpVector.Y)`).

`computeMouseAim` output is eased into `aimApplied.*` (`resp = clamp(aimResponse*dt,0,1)`). In
free-look / RMB-zoom / aim-off the target is **0** so the bird HOLDS attitude (must ease to 0, not
freeze a nonzero rate — that noses over into a dive). RMB-zoom suspends steering so FOV can't feed
back into flight.

**Reticle GUI** (`AimReticle` ScreenGui): `noseMarker` (amber boresight at `pos + birdLook*4000`),
`aimDot` (green world-cursor ring at `pos + aimTargetDir*4000`), 7 `talonPips` forming a belly arc in
the roll plane (eagle-only, swings with bank), `paintStrikeReticles(armed)` lights the server-chosen
zone (read from `Body:GetAttribute("StrikeArmedDir")`).

## 5. FREE-LOOK camera — upright spherical orbit (CS-2 revised / CS-3)

Space toggle (`setFreeLook`): resets `freeLook.yaw/pitch=0`, locks mouse; survives crow-swap; focus
loss force-clears. Accumulate `freeLook.yaw -= delta.X*s; freeLook.pitch -= delta.Y*s` (INVERTED:
mouse-up looks down). In `updateCamera` when active:
```lua
maxPitch = rad(CAM.freeLookPitchLimitDeg or 85)
freeLook.pitch = clamp(freeLook.pitch, -maxPitch, maxPitch)     -- write-back, no wind-up past vertical
behind = Vector3.new(chaseDir.X, 0, chaseDir.Z).Unit           -- frozen chaseDir flattened to horizontal
yawCF     = CFrame.fromAxisAngle(Vector3.yAxis, freeLook.yaw)
pitchAxis = yawCF:VectorToWorldSpace(Vector3.xAxis)
orbit = CFrame.fromAxisAngle(pitchAxis, freeLook.pitch) * yawCF
cameraOffset = orbit:VectorToWorldSpace(behind) * dist
camUp = Vector3.yAxis                                           -- HARD world-up: operator never rolls/inverts
```
`camUp` hard world-up → `CFrame.lookAt` keeps the horizon level for any non-vertical view; the ±85°
clamp holds the view off the exact pole (no degeneration/jitter). Deliberately does NOT orbit
over-the-top (the S12 unbounded version flipped upside down). Free-look uses `freeLookSmoothing`
(near-1:1). Reticle+cursor FUSE on the beak.

## 6. CHASE camera (`updateCamera`)

`Scriptable`. Distance: `speedBase = baseDistance + speed*speedDistanceFactor`; clamped; **fixed
`mouseAimDistance` in aim mode**. Follow: `followDir = lookVec` blended toward `velocity.Unit`
(`lookAheadFactor`) when moving; in aim mode replaced by an **exponentially-lagged heading**
(`aimHeadingLag`) so the world-cursor hangs out and the nose visibly chases it. `desiredChase =
-headingRef`. **Rate-limited chase basis** (`chaseDir` slewed by `chaseTurnRate`, FROZEN while
free-looking) — never rebuilt from a discontinuous azimuth, so a 360° loop arcs with no flip.
**Parallel-transport up:** carry `camUp` along the chaseDir rotation each frame, re-orthogonalize,
self-level toward world-up **faded out as the path goes vertical** (`loopVertStart/loopVertBand`) so it
never yanks to the degenerate reference over the top. Offset `= chaseDir*dist +
camUp*(dist*heightRatio)`. Bank tilt (chase only) `CFrame.Angles(0,0, bankAngle*bankTiltFactor*
uprightFade)`. Crest damping softens the follow at a loop crest. Frame-rate-independent lerp
`alpha=1-exp(-smoothing*60*dt)`. High-speed shake above `shakeAtSpeed`. FOV: base/dive/climb by
attitude, then aim-zoom, clamped [12,110].

## 7. RMB awareness zoom

`aimZoom.factor` eases toward 0/1 (`aimZoomLerp`). Narrows FOV toward `aimFOV`; swings the look far
along the **live beak** (`cf.LookVector*2000`) so the zoom centre follows the reticle; fades the eagle
locally (`LocalTransparencyModifier`, `aimFadeBird`); **steering suspended** so it can't fly you.
Wheel = eagle-distance (`userZoom`), works in chase AND free-look.

## 8. Local collision slide & housekeeping

`BirdCollision.resolve(rootPart.Position, engine.orientation.Position, engine.velocity, bodyRadius,
params, Flight.CRASH_SPEED)`: on a survivable graze, slide locally (zero-latency feel); a lethal
impact is NOT clamped — the server's `processCrashes` reads the clean position delta and kills it
(client/server never disagree). `resetInput()` zeros everything on acquire/focus-loss;
`WindowFocusReleased` clears held input + free-look (Roblox drops `InputEnded` across alt-tab).

## 9. UI hooks & GameUI

`pushUI()` calls (guarded): `_G.UpdateStaminaUI(stamina/maxStamina)`, `_G.SetStallWarning(isStalling)`,
`_G.SetIncidence(pitchDeg)`, `_G.UpdateFlapUI(flapThrottle, flapFreqHz, flapPower)`. **GameUI** builds
the whole HUD in code, parents its own ScreenGui to PlayerGui, reads the possessed bird from
`Workspace.Birds`, pulls HP/speed/alt + eagle strike attributes, draws on-screen enemy boxes /
off-screen edge arrows, and empties readouts (not freezes) during the death→respawn gap. It lives in
StarterPlayerScripts because with `CharacterAutoLoads=false` StarterGui never reaches PlayerGui.

---

# Part VII — Server authority + shared helpers

All files `--!nonstrict`.

## 1. Authority / replication (recap)

`CharacterAutoLoads=false`; birds are standalone Models in `Workspace.Birds`. Client owns its
possessed bird's physics via `SetNetworkOwner(player)`; server owns damage/scoring/collisions/AI/
rounds/anti-cheat and measures motion from position deltas only. AI crows run the same `FlightPhysics`.

**Model attribute contract** (set BEFORE parenting so they replicate atomically): `OwnerUserId`
(number|0), `Team` (string), `Possessed` (bool). On PrimaryPart `Body`: `Health`, `MaxHealth`,
`NetOwner` (UserId when client-owned, 0 when server-owned — the definitive handoff signal), and eagle
strike HUD mirror `StrikeMeter`/`StrikeActive`/`StrikeArmedDir`.

## 2. Constants
```
ATTACK_BUFFER=3.0  TALON_ALIGN_DOT=0.5  TALON_RANGE_FRACTION=0.6  DIVE_SPEED_THRESHOLD=120
DIVE_VY_THRESHOLD=-60  COLLISION_SPEED_MIN=90  COLLISION_SPEED_REF=260  COLLISION_COOLDOWN=0.4
ATTACK_COOLDOWN=0.6  AI_HEARTBEAT_DT_CAP=1/30  SPAWN_HEIGHT=600  GROUND_FAILSAFE_Y=-200
RESPAWN_COOLDOWN=1.5  SPATIAL_CELL=64  MAX_BODY_RADIUS=max(prof.bodyRadius)
```

## 3. State
`Birds` (keyed by Model): `{model, body, player, team, profileName, profile, isAI, possessed, squad,
engine, _lastPos, _acLastPos, _acBucket, _acGraceUntil, strike}`. `PlayerData` (per player): `{team,
profileName, profile, birds, squad, _acStrikes, _acStrikeAt}`. `Squads` (per player or
`BOT_SQUAD_KEY`): `{player, formationName, possessedIndex, members, aggressive}`. `Scores =
{Eagles=0, Crows=0}`. Debounce books: `lastAttackAt`, `lastCollisionAt[pairKey]`, `lastSwapAt`,
`lastRespawnAt`.

## 4. Small helpers
`getHealth/setHealth` (Body `Health` attribute), `pairKey(a,b)` (order-independent), `isBirdAlive`,
`getActiveBird(player)` (possessed & alive only — no "first living bird" fallback),
`trySetNetworkOwner(body,player)` (pcall: SetNetworkOwner + `NetOwner`=UserId),
`setServerOwned(body)` (SetNetworkOwner(nil) + `NetOwner`=0), `markServerMove(entry)` (clears
anti-cheat baseline + grace window — called after every legit server move; strikes persist).

## 5. World setup
`SetupLighting()` (midday, thin Atmosphere so distant terrain renders). `BuildMap()` sets
`Workspace.Gravity = Flight.GRAVITY`, `StreamingEnabled=false`, and rebuilds a ~26-part `Map` (16000×
16000 baseplate top at Y=0, sea, patches, lake/desert, river, three concentric mountain rings Foot
R≈3600 / Mid R≈5400 / Peak R≈7400, buttes, four Neon cardinal beacon pillars at ±4200).
`CreateThermals()` builds `ThermalList` from `GameConfig.Thermals` on a ring R=3200.

## 6. Combat broad-phase
`birdIndex = SpatialHash.new(64)`, rebuilt at the top of each Heartbeat.
`findNearestEnemy(entry, maxRange)` → `birdIndex:nearest` (filter: enemy team & alive).
`findNearestEnemyLinear(entry)` → O(n) scan, NO radius (aggressive bots hunt across the whole 16k map
without a map-spanning hash query that would walk millions of empty cells).

## 7. Remotes contract (`CreateRemotes`)

| Remote | Dir | Args |
|--------|-----|------|
| `TeamAssigned` | S→C | `teamName`, `profile` |
| `AttackRequest` | C→S | none (**legacy**, kept harmless) |
| `Strike` | C→S | **none** (fire EDGE; server reads bank/proximity to pick side) |
| `TakeDamage` | S→C | `attackerName`, `targetPlayer`, `damage` (FireAllClients) |
| `ScoreUpdate` | S→C | `scores` (FireAllClients) |
| `GameNotification` | S→C | `text`, `color` (FireAllClients) |
| `SwapCrow` | C→S | `index` |
| `SetFormation` | C→S | `formationName` |
| `Respawn` | C→S | none (debounced) |
| `GetThermals` | C→S (RemoteFunction) | returns `ThermalList` array of `{position, radius, minHeight, maxHeight, strength}` |

**Retired:** `WeaponHold`.

## 8. Spawning
`spawnBird(player, team, profileName, spawnPos, isAI)`: build Model via `BirdBuilder.Build`; `body =
PrimaryPart`; cosmetic `ScaleTo(Visual.birdScale)`; `PivotTo` + random yaw; seed
`AssemblyLinearVelocity = LookVector*(glideSpeed*0.9)`; `setHealth(profile.health)`, `MaxHealth`; set
`OwnerUserId/Team/Possessed` **before** parenting; if AI → `engine=FlightPhysics.new`, `setServerOwned`;
else → `trySetNetworkOwner` + `markServerMove`. `spawnEagle` (1, non-AI). `spawnCrowSquad`
(`Squad.size`=4; index 1 possessed, 2–4 AI). `spawnFor` dispatches by team then fires `TeamAssigned`.
Solo-test bot squad (`Debug.aiCrowOpponents`): all-AI aggressive squad ~700 studs off the eagle,
respawned in waves.

## 9. Damage & death
`applyDamage(target, amount, attacker, cause)`: subtract Health; `TakeDamage:FireAllClients`; on
`hp<=0` remove from `Birds`, `Destroy`, **prune the dead model from `rec.birds`** (else solo respawn
never fires), `autoRepossess`, notify. `autoRepossess(squad)` promotes the next living crow to
possessed/client-owned (bot squads skipped — no human).

## 10. Eagle directional STRIKE (server-owned)
LMB → `Strike` edge. `strikeAxis(body,cfg)`: `"belly"` = `-Body.UpVector` (swings with bank), default
= LookVector. `enemyZone(entry,none)`: AUTO-PICK by nearest enemy within `strikeSelectRange` — `"talon"`
if `d·(-Up) > d·Look` else `"beak"`; `none` if none in range. `stepStrike`: ready → active (startup
then duration) → cooldown → ready. `onStrike`: possessed **Eagle** only; requires `state=="ready"`;
`stype=enemyZone`. `updateEagleStrikes(dt)`: step, then offensive cone pass — within
`reach=(bodyRadius+MAX_BODY_RADIUS+ATTACK_BUFFER)*reachFraction`, if `dir·axis >=
cos(coverHalfAngleDeg)`, deal beak/talon damage, `caught=true` (ONE catch-or-hit per window). Mirrors
strike HUD attributes. `tryStrikeCatch(eagle,crow)` = the defensive parry.

## 11. Collisions / trades (`processCollisions`)
Snapshot living birds; per pair (via `birdIndex:forEachInRadius`, once per unordered pair): touch if
`sep <= rA+rB`; per-pair `COLLISION_COOLDOWN`; skip if `relSpeed < COLLISION_SPEED_MIN`. **Asymmetric
trade:** if `tryStrikeCatch(eagle,crow)` → crow dies, eagle unharmed. Else UNPARRIED ram → eagle takes
`health/eagleHits` (one of 3 hits), crow dies regardless. Each simultaneous ram is its own pair → its
own hit (how multi-angle swarming beats one parry).

## 12. Crash detection (`processCrashes`)
`pos.Y < GROUND_FAILSAFE_Y (-200)` → doomed. Else for non-AI birds, `observedVel = (pos -
_lastPos)/dt` (server-observed, never client velocity) → `BirdCollision.resolve(_lastPos, pos,
observedVel, bodyRadius, params, Flight.CRASH_SPEED)`; `crashed` → doomed. Kill via `applyDamage(...,
"crash")`.

## 13. AI crows (`updateAICrows`)
Per AI member: sync engine from part; `steer = Boids.computeSteering(self, neighbors, goal,
formationCfg)`; add obstacle-avoidance nudge (`avoidObstacle` forward Spherecast × `Squad.avoidance.
weight` × urgency, no floor so the eagle-chase dominates until a wall is imminent); `input =
Boids.steeringToInput(...)`; `SetThermalForce(thermalForceAt(pos))`; `engine:Update(fdt, input)`;
resolve with `BirdCollision.resolve(..., crashSpeed=math.huge)` — **AI crows NEVER crash on terrain**
(a bot must not suicide before the player engages); write back CFrame/velocity; `AnimateWings`.
`squadGoal`: possessed crow pos, overridden by nearest enemy (aggressive → `findNearestEnemyLinear`;
player squads → `findNearestEnemy(possessed, engageRadius)`). **Known issue:** the gentle avoidance
makes bots arc/flee rather than *mob* — they should swarm. `thermalForceAt` must match the client's
`computeThermalForce` exactly.

## 14. Squad commands
`onSwapCrow` (validated, `swapCooldown` debounce): demote possessed → AI (rebuild engine,
setServerOwned), promote target → possessed/client-owned. `onRespawn` (`RESPAWN_COOLDOWN`): clearBirds
+ spawnFor. `onSetFormation` (validated against `formations`).

## 15. Anti-cheat (`processAntiCheat`)
Gated by `Security.enabled`; non-AI player birds only. `terminal=400`; `speedCeil=terminal*
speedAllowMult`; `teleportStep=terminal*teleportMult*dt + pingPadStuds`. Strike decay
`floor(elapsed/strikeDecaySeconds)`. Grace/no-baseline → seed & skip. Else `observed=|pos-_acLastPos|
/dt`: **teleport gate** (`moved>teleportStep` → violation); **leaky bucket** (`over=observed-speedCeil`;
`over>0` → bucket += over·dt else drains by `bucketLeak·dt`; `bucket>bucketCapacity` → violation).
**Response ladder:** rubber-band (snap Body back to `last`, zero velocity, don't accept bad pos) +
`_acStrikes+=1`; at `kickStrikes(6)` → Kick; else at `reclaimStrikes(3)` → `setServerOwned`. Observed
speed is always position-delta-derived.

## 16. Rounds & lifecycle
`promoteToEagleIfNeeded` (promote a crow if no eagle exists). `startRound`/`resolveRound`
(`eagleDown`→Crows+1, `crowsDown`→Eagles+1, `tie`→draw)/`RoundLoop` (intermission 8 → round 240 →
resolve → respawn 4). `onPlayerAdded` (assign team, `CharacterAutoLoads=false`, spawn/announce).
`onPlayerRemoving` (clearBirds; if leaver was eagle → `promoteToEagleIfNeeded`).

## 17. Heartbeat order (`onHeartbeat`, only when `roundActive`)
1. `rebuildBirdIndex()` — one shared broad-phase.
2. `updateAICrows(dt)`.
3. `updateEagleStrikes(dt)` (before collisions, so `tryStrikeCatch` reads fresh state).
4. `processAntiCheat(dt)` (before crash sweep, so a rubber-band corrects the read position).
5. `processCollisions()`.
6. `processCrashes(dt)`.

**Init order:** `SetupLighting → BuildMap → CreateThermals → CreateRemotes → connectRemotes → spawn
existing + connect PlayerAdded/Removing → connect Heartbeat → task.spawn(RoundLoop)`.

## 18. Shared helper — `Boids`
`local B = GameConfig.Squad.boids`; `safeUnit(v)` → zero for near-zero length.
- **`computeSteering(self, neighbors, goalPoint, formationCfg) → Vector3`** (world accel, clamped to
  `maxSteerForce`). Perception: within `neighborRadius` AND inside `neighborFovDeg` half-angle of
  forward. **Separation** accumulates `-safeUnit(push)*(spacing/dist)` then `safeUnit`s to a UNIT
  direction (so config weights govern the blend). **Alignment** = `safeUnit(mean neighbor vel)`.
  **Cohesion** = `safeUnit(centroid-pos)`. **Goal** = `safeUnit(goal-pos)`. Weighted sum:
  `sep*(separationWeight*separationMul) + align*alignmentWeight + coh*(cohesionWeight*cohesionMul) +
  goal*cohesionWeight` (goal reuses cohesion weight, NOT formation-scaled, so crows still rally when
  spread).
- **`steeringToInput(cf, vel, desiredDir, profile) → {pitch, roll, yaw, flap, dive}`**. Turn by
  banking: `roll = yawError` (signed horizontal error), `yaw = yawError*0.35`. `pitch =
  clamp((dir.Y-look.Y)*1.5,-1,1)`, reduced while banked. `flap = dir.Y>0.15 or speed<glide`. `dive =
  dir.Y<-0.4` → dive true, flap false (gravity is the energy source).

## 19. Shared helper — `BirdCollision`
The ONLY shared module touching Workspace. `SKIN=0.15`.
- **`makeParams(ignore) → RaycastParams`** (Exclude, IgnoreWater, filter = the Birds folder, so
  bird-vs-bird is never reported here).
- **`lookAhead(fromPos, dir, distance, radius, params) → RaycastResult|nil`** — forward sphere sweep
  (used by AI steering).
- **`resolve(fromPos, toPos, velocity, radius, params, crashSpeed) → newPos, newVel, crashed, hit`** —
  sweep a sphere along `toPos-fromPos`. No hit → `(toPos, velocity, false)`. Hit: `surfacePos =
  hit.Position + normal*(radius+SKIN)`, `closing = -velocity·normal`; `closing>=crashSpeed` →
  `(surfacePos, velocity, true)` (velocity kept so a delta-measuring server still sees full closing
  speed); else graze → `(surfacePos, velocity - normal*(velocity·normal), false)` (slide).

## 20. Shared helper — `SpatialHash`
Uniform XZ grid (default cell 64). **Broad-phase only** — `forEachInRadius` visits a SUPERSET; the
caller does the exact distance test. API: `new(cellSize)`, `clear()`, `insert(position, data)`,
`forEachInRadius(position, radius, fn)`, `nearest(position, radius, filterFn) → data, distance`.

## 21. Shared helper — `BirdBuilder`
Animation constants: `FLAP_AMPLITUDE=rad(45)`, `IDLE_AMPLITUDE=rad(8)`, `IDLE_FREQUENCY=1.5`,
`DIVE_SWEEP=rad(60)`, `SMOOTH=10`. `idlePhase = setmetatable({}, {__mode="k"})` — per-model idle-bob
phase in a WEAK-KEYED table, NOT an attribute (per-frame SetAttribute would replicate ~180×/s per
crow).
- **`Build(teamName, profile) → Model`** — species from name contains "eagle". `r =
  profile.bodyRadius`. Eagle brown/gold body + **bright white tail fan** (`RGB 244,244,240`, bald-eagle
  signature); crow near-black. Structure: Model named `teamName` with **`Body`** (PrimaryPart, size
  `(r, r*1.1, r*2.2)`, the ONLY massed/collidable/queryable part), `Head`/`Beak`/`Tail` welded
  massless no-collide, and `LeftWing`/`RightWing` via **Motor6D** joints (`Part0=Body`, `C0` at wing
  root, `C1` so identity Transform rests neutral, attribute `FlapSign` −1/+1).
- **`AnimateWings(model, isFlapping, isDiving, flapPhase, dt)`** — dihedral angle: diving →
  `-DIVE_SWEEP` (wings tucked/folded); flapping → `sin(flapPhase)*FLAP_AMPLITUDE`; else idle bob. Eases
  each joint's `Transform` toward `CFrame.Angles(0,0, sign*angle)` by `alpha=clamp(dt*SMOOTH,0,1)`.

### Cross-cutting invariants (preserve on re-implementation)
- Health lives ONLY on Body's `Health` attribute; tables hold metadata keyed by Model.
- All asymmetry is in `GameConfig` numbers — profiles are structurally identical (engine/builder/boids
  are class-agnostic).
- The server never simulates possessed/eagle flight (client-owned); it reads their replicated Body and
  validates via position deltas. It only simulates AI crows it owns.
- `NetOwner`/`Possessed` attributes are the entire client-acquisition + handoff-safety contract.

---

# Part VIII — The LOCKED CONTROL SPECS registry (CS-1 … CS-9)

Protected control contracts. Grep/read before ANY control/camera/input edit; reason about interactions
with every row first. Status — **LOCKED**: player-confirmed, do not change · **SPECIFIED**: Chad-asked,
implement exactly, pending verify · **MUST-FIX**: specified but code violates it.

- **CS-1 — Keyboard fully overrides mouse-aim (cursor has ZERO pull while any flight key is held).**
  While ANY of Q/W/E/A/S/D is held, the cursor exerts no pull on ANY axis (a held S makes a *straight*
  loop); on full release, mouse-aim resumes. **SPECIFIED — FIXED S13** (GLOBAL gate `aimGate =
  (kb.pitch~=0 or kb.roll~=0 or kb.yaw~=0) and 0 or 1`). Do NOT re-add per-axis blending or re-anchor
  the cursor. **"Can't change anymore."**
- **CS-2 — Free-look is an UPRIGHT spherical orbit:** full 360° yaw; pitch soft-stops just shy of
  straight-up/down; operator stays WORLD-UPRIGHT (horizon level, never inverts). REVISED S13 (the S12
  over-the-top orbit flipped upside down). `camUp=Vector3.yAxis` + pitch clamp `freeLookPitchLimitDeg`
  (85°). **SPECIFIED (S13; unplaytested).**
- **CS-3 — Free-look vertical is INVERTED** (mouse-up = look down). **SPECIFIED** (one-line sign at the
  input site if it ever reads wrong, independent of CS-2).
- **CS-4 — Free-look toggles on SPACE** (tap on/off; not hold), survives crow-swap. **LOCKED.**
- **CS-5 — NO auto-leveling.** Nose stays where pointed; AoA changes only on input (`STABILITY_RATE=0`,
  both `recoverNoseDownRate=0`). **LOCKED.**
- **CS-6 — Grip model "flies where you point"** (velocity follows the nose; requires `cl0>0` — never
  set `cl0=0`). **LOCKED (`v1.0-eagle-flight`).**
- **CS-7 — Control mapping:** A=bank left/D=bank right; Q=yaw left/E=yaw right; W=nose-down/S=nose-up;
  Shift=throttle up / Ctrl=down (sticky); LMB=strike; RMB=awareness zoom; wheel=eagle-distance zoom;
  F=formation; R=respawn; 1–4=possess crow. **LOCKED.**
- **CS-8 — Mouse-aim = nose-chases-WORLD-cursor** (world-anchored direction; nose reticle chases &
  resolves; camera lags the heading). **LOCKED (player-tuned).**
- **CS-9 — A DIVE is a REST: no stamina cost + stamina REGENS while diving.** A diving bird tucks its
  wings, so a dive spends NO stamina and RECOVERS it (gains both speed AND stamina), even with
  Shift/Ctrl held. Stamina drains only for active flapping in NON-dive flight. Impl: cost gated on
  `wantFlap and not self.isDiving`; `staminaDiveCost` legacy/unused. **LOCKED — PLAYTEST-CONFIRMED
  S13** ("the wings tuck in a dive and it looks right and the stamina goes up! excellent game
  feature").

> **Process rule:** add new locked specs here as Chad confirms/specifies them. **Never silently drop
> or reinterpret a row.**

---

# Part IX — Flight-model evolution & lessons learned

## Evolution (narrative)

**v1 — force-core + path-tracking (structural failure).** A force core + a per-frame path-tracker
(`PATH_TRACK_RATE`) rotating velocity toward the nose. "Not enough lift, constantly stalls" was
**structural**: lift was `∝ sin(AoA)` → **zero lift at zero AoA** (`CL0=0`), forcing permanent
nose-high flight a few degrees from stall; the path-tracker drove AoA→0 (the no-lift point) → a
self-reinforcing stall spiral. Number-tuning couldn't fix it.

**v2 — lift-curve + weathervane rewrite** (session 6). Drop-in (same API). Three fixes together:
real lift curve with **baseline lift `cl0=0.30` (THE fix)** capped at `clMax`, forgiving lerp to
nonzero `postStallCl`; **static weathervane stability** (orientation rotates toward airflow) replacing
path-tracking; **drag polar `CD0 + k·CL²`** → induced drag ∝ g-load² (E-M emerges free). Established
**stall < spawn < cruise** as a hard invariant.

**GRIP "flies where you point"** (session 7). `GRIP_RATE` rotates velocity toward the nose in every
attitude → point up, path follows up (climb, not stall). **Invariant reversal:** v2 had *banned* this
(it caused the v1 spiral), but with `cl0>0`, AoA→0 still makes lift, so grip is safe and is now the
core feel — **`cl0>0` is load-bearing.** Added **powered climb** (`flapClimbForce` set *above*
gravity — a deliberate arcade climb; authority/lift floors alone were NOT enough), **phugoid damping**
(released by pitch, killed in dive — keep it underdamped), **service ceiling**, **loop**
(`AEROBATIC_MIN_SPEED`). **Auto-level ELIMINATED** (session 9, explicit ask): `STABILITY_RATE=0`, both
`recoverNoseDownRate=0` — grip (`cl0>0`) is now the only thing preventing stall. Session 9: "one of
the coolest flight experiences I have experienced." Tagged **`v1.0-eagle-flight`**.

**Mouse-aim — a chain of REVERSALS** (the most-iterated subsystem). Through-line lesson: **a chase
camera that re-centres the heading breaks every screen-space cursor scheme.** (1) attitude-command →
(2) screen-gap pursuit **corkscrewed** → fixed by driving in the **body frame** → (3) absolute-screen
cursor **turned forever** (chase cam re-centres the nose) → (4) self-centering virtual stick felt like
a joystick → (5) screen-cursor vs screen-centre didn't align → (6) **SETTLED:
NOSE-CHASES-WORLD-CURSOR** — a world-anchored cursor the nose chases and resolves on (world-fixed → error
→ 0). "It's good there."

**Camera parallel-transport fix.** Loops snapped/pole-flipped — root cause was the *target* (chase
direction rebuilt each frame from the horizontal heading, which reverses over the loop top), not the
Lerp. Fix: single persistent rate-limited 3D chase direction + **parallel-transported up vector**.

**Energy-retention arcade term** (session 13, top ask). Insight that stopped agents flailing on drag:
the dominant climb bleed is **gravity along the flight path**, not drag. Lever: per-profile persistent
`energyRetention` (Eagle 0.7 / Crow 0.4) adds back `energyRetention × GRAVITY·velDir.Y` **climb-only**;
capped `<0.95`. Eagle > Crow = the 1-v-4 energy lever.

**Dive-rest stamina (CS-9, session 13).** A diving bird tucks its wings → stamina drains only on
`wantFlap and not isDiving`; a stoop gains both speed and stamina. Playtest-confirmed. Post-session-13:
"The flight model of the eagle is largely finished. I'm having a great experience." — the eagle flight
/ control / camera feel is **SIGNED OFF**; do not reopen its calibration without a fresh ask.

## Lessons learned

- **Ground truth is Studio Play.** No compiler/linter/test-runner; `build.ps1` resolves wiring but
  does NOT run Luau. Reason hard, ONE change at a time, keep build green, **checkpoint before kernel
  edits**, tee up a playtest checklist.
- **"Not enough lift" was structural, not a value.** When a symptom recurs after several tuning
  passes, suspect **structure**, not the value.
- **Birds have no Roblox collision.** A CFrame-driven part tunnels through everything; the `Y<4`
  stopgap was replaced by real swept-sphere `BirdCollision` (a *sphere* — a point ray skips thin
  spires at 260+ studs/s). **Any new code that moves a bird by CFrame must route through
  `BirdCollision` or it tunnels again.**
- **Protect the integrator from frame spikes:** `dt = min(dt, 1/30)`.
- **A world-space rotation on the LEFT of a CFrame teleports it** about the origin — rotate the basis
  only and re-add position (`(cf-pos)+pos`).
- **The LOCKED-SPEC process directive — origin.** Collateral changes kept regressing loved feel: the
  canonical failure was adding keyboard-authority with a **per-axis** gate that silently **curved
  Chad's loops** (held S suppressed pitch aim but roll/yaw still pulled to the cursor). Directive:
  "significant aspects of the control need to be maintained and protected… we have to foresee and not
  compromise on the control of flight. My testing needs to be logged." Sub-lessons: the fix was
  **per-axis → GLOBAL**; and **Chad rejected the clever guess** ("re-anchor the cursor") in favor of
  his literal ask — **implement exactly what he asked.**
- **"More freedom" is not automatically better feel.** CS-2's unbounded over-the-top orbit flipped the
  view upside-down; the revision *stops at vertical* and stays upright.
- Standing rules: **ASK, don't guess** on control feel; **LOG every playtest**; **refine
  incrementally, do NOT regenerate**.
- **Kernel invariants that MUST survive:** `cl0>0` (grip); auto-level OFF (`STABILITY_RATE=0`, both
  `recoverNoseDownRate=0`); keyboard-first; **stall < spawn < cruise**; `GRAVITY_G` is the master loft
  knob (currently 1.3) scaled in lockstep with `AIR_DENSITY` (`GRAV_SCALE`) so the stall/cruise/dive
  ordering holds at any value.

---

# Part X — Reconstruction checklist & acceptance criteria

**Rebuild order (dependencies):** `GameConfig` → `FlightPhysics` → `BirdBuilder` / `Boids` /
`BirdCollision` / `SpatialHash` → `GameServer` → `BirdController` / `GameUI`. Wire via Rojo
(`default.project.json`); file suffix sets class.

**Kernel invariants (never violate):**
1. `cl0 > 0` in both profiles (grip safety; without it, grip re-creates the v1 stall spiral).
2. Auto-level OFF: `STABILITY_RATE = 0`, both profiles' `recoverNoseDownRate = 0`.
3. `stall < spawn < cruise` per profile (structurally guaranteed if `AIR_DENSITY` scales with
   `GRAVITY` via `GRAV_SCALE`). Spawn = `0.9 × glideSpeed`.
4. `dt = min(dt, 1/30)` in `:Update`.
5. Any CFrame-driven bird movement routes through `BirdCollision`.
6. Server owns damage/score; client owns possessed-bird physics via `SetNetworkOwner`; the client
   waits for `NetOwner == its UserId` before driving.

**Behavioral acceptance (Studio Play):**
- Eagle cruises with margin; nosing down accelerates; pulling up climbs/recovers; a stall is a
  recoverable mush, not a death spiral.
- A held **S** makes a **straight** loop while the mouse-cursor is off-centre (CS-1).
- Free-look: pan all the way up/down (soft-stops near vertical, never inverts) and spin fully around;
  horizon stays level (CS-2).
- Dive with Shift held: stamina bar **rises**; non-dive climbing **drains** it (CS-9); wings visibly
  tuck in the dive.
- After a dive, a ~30° climb without hard-turning bleeds speed slowly and zooms back near start
  altitude; the crow bleeds faster (energy asymmetry).
- Mouse-aim: the nose reticle chases the world-cursor and resolves on it; the camera lags the heading
  so the cursor visibly hangs out (CS-8).
- A full 360° loop shows no camera azimuth-snap or pole-flip.
- 4 AI crows spawn, fly the same engine, and can pressure the eagle; collisions trade (crow dies,
  eagle takes one of 3 hits unless it parries with a strike).
- Holds framerate with multiple swarms.

**Process:** ONE change at a time; checkpoint (commit/tag) before kernel edits; log every playtest in
`docs/HANDOFF.md`; never change a LOCKED CONTROL SPEC collaterally; ASK, don't guess.

---

# Part XI — Open frontier

With eagle flight signed off, the frontier is **COMBAT + the 1-v-4 + the CROW.** Prioritized:

1. **Make the AI crows MOB.** They still scatter / flee / crash instead of swarming ("they are
   around, can be really fast and fly away, get scared and crash"). Re-weight `updateAICrows` +
   `Squad.avoidance` + boids weights so the 3 AI crows close in and pressure the eagle. **A 1-v-4 that
   can't mob isn't a real 4.** (Related: boids still lack an obstacle-avoidance *steering* term, so
   crows fly into lethal spires.)
2. **Verify the BEAK strike path + 1-v-4 balance.** TALON is playtest-confirmed (first kill landed);
   **BEAK is untested.** ⚠️ talon 4s/2s ≈ 67% uptime flirts with the ">50% always-on" guardrail — if
   eagle-favoured, cut talon `duration` / widen `cooldown` / drop offensive damage first
   (`Combat.strikes`). Preserve the guarantee: the eagle presents **one zone at a time** (belly OR
   nose) so 4 crows from spread angles still win by saturation.
3. **Tune the Crow profile + collision trades** (the last big design frontier). The lose-lose
   collision has **no research backing** (placeholder numbers). Current formula: damage to each bird =
   the OTHER's `collisionDamageDealt` × speed-scale × this bird's `collisionDamageTaken` (tuned so a
   crow ram ≈ 4 rams to kill the eagle while the crow dies — a true trade). Newly relevant: the eagle
   now keeps more climb-energy AND refuels stamina in dives, so **re-check 4 crows can still corner/mob
   it.**

**Longer-tail:** possession↔boids handoff polish; anti-cheat thresholds are PLAYTEST-PROVISIONAL (must
not false-positive honest aerobatics); LOD/replication throttling for many swarms; Parallel-Luau actors
for per-crow boids+aero (only after it's fun); re-verify Roblox Server Authority only after GA (currently
mutually exclusive with `SetNetworkOwner`).

**On every one of these, honor the thesis:** reason about the whole 1-eagle-vs-4-crow fight on every
number, and remember that ground truth is Chad's Studio Play.

---

*End of master specification. Frozen source: GitHub branch `single-bird-kernel` @ `52a929c`.*
