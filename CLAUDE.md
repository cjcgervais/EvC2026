# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> ⚠️ **SUPERSESSION (read before anything below).** The section "What this is" describes **combat**
> (1-eagle-vs-4-crows, LMB strike, crow squads). **Combat has been SHELVED since S32.** The live game is
> **EAGLES TO THE RESCUE** — a forest-fire critter rescue loop: `Rescue.enabled=true`,
> `activeMission="ember_valley"`, `RescueServer` owns the round, and the HUD hides HP/AoA. The flight
> KERNEL, controls and camera below are still accurate and still LOCKED. See
> `docs/EAGLES-TO-THE-RESCUE-plan.md` and the `project-updraft-direction` memory for the real product.

## Orientation (read these first)
- **Run `/evc-loop`** — the governing session harness for this project. It runs a
  SOP-tuned loop (orient → one-change → verify → red-team → memory → handoff →
  approved commit), protects the LOCKED control specs, and guarantees a clean
  context-clear handoff. Lives at `.claude/skills/evc-loop/`; a SessionStart hook
  reminds you at every start. **This is the primary way to work the codebase.**
- `docs/HANDOFF.md` — current status, the one architecture decision already locked in, and the prioritized work queue. **Start here.**
- **How to continue:** invoke **`/evc-loop`** (above). It specializes the generic **`loop-orchestrator` skill** in `loop_skill/` (`roblox-game` profile) with this game's real SOPs, and composes the **`deep-research`** skill for the research half. See the `reference-evc-loop-skill` and `reference-loop-orchestrator-skill` memories.
- `docs/RESEARCH.md` — why every flight/balance number is what it is (verified deep-research pass).
- Project memory index: `C:\Users\Chad\.claude\projects\D--EvC2026\memory\MEMORY.md`.
- `EaglesVsCrows.txt` — the original recovered transcript (older versions of the client/UI/server). Historical reference; the live code is under `src/`.

## What this is
A physics-based aerial melee combat game for **Roblox** (Luau): **Eagles vs Crows**. Asymmetric 1-vs-many dogfights — one high-endurance **Eagle** (boom-and-zoom energy fighter) vs a **Crow** player's squad of **4** (angles fighters; possession + adjustable tight/loose formation; trade/sacrifice collisions). Combat is beak, talon, or a full-speed lose-lose collision. See the `project-goal` memory for the full vision.

**Central design thesis (do not violate):** flight physics and asymmetric balance are **one system** — every flight number is also a balance number. Performance is a hard constraint on both. Reason about the 1-eagle-vs-4-crow matchup on every tuning edit. (`feedback-flight-balance-inseparable` memory.)

## Build & run
It's Luau deployed to Roblox — there's no compiler/linter/test runner, and Roblox isn't headless, so **the only real validation is pressing Play in Studio.** The project syncs via **[Rojo](https://rojo.space)** using `default.project.json`.

**Rojo is automated — no manual install needed.** The wrapper scripts self-bootstrap a pinned Rojo binary (`tools/Bootstrap-Rojo.ps1` downloads v7.6.1 into `tools/bin/`, gitignored, on first use). From the repo root in PowerShell:
- **`.\serve.ps1`** — live-sync into Studio (then connect the Rojo plugin; install it once with `.\rojo.ps1 plugin install`).
- **`.\build.ps1`** — one-shot place build → `EaglesVsCrows.rbxlx` (gitignored). `-Watch` to rebuild on change.
- **`.\rojo.ps1 <args>`** — raw passthrough to the bootstrapped binary (e.g. `.\rojo.ps1 sourcemap`).
- **`.\verify.ps1`** — *optional* headless verify ladder: self-bootstraps `luau-lsp analyze` + `selene` (best-effort) and runs the Rojo build. This DOES catch what the plain build can't — broken `require`s, renamed-contract mismatches, nil/field errors, lint smells — with zero human. Each analysis tier degrades to `UNAVAILABLE` if its binary can't be fetched; the build floor always runs. See `.claude/skills/evc-loop/references/verify-ladder.md`.
- VS Code: **Run Task… → "Rojo: Serve / Build / Build + watch / Install Studio plugin"** (`.vscode/tasks.json`).

`build.ps1` succeeding confirms the project wiring resolves and scripts map to the right classes (Script/LocalScript/ModuleScript), but it does **not** syntax-check Luau or run anything — `verify.ps1`'s analysis tier covers some of that gap, but **behavior and feel are still validated only by a Studio smoke test / Chad's Play.**

## Architecture — module map (Rojo `src/` → Roblox services)

| File | Roblox location | Role |
|------|-----------------|------|
| `src/shared/GameConfig.luau` | `ReplicatedStorage.GameConfig` | **The contract + all tunables.** Profiles (Eagle/Crow), Squad/formations, Thermals, Round, Camera, UI. |
| `src/shared/FlightPhysics.luau` | `ReplicatedStorage.FlightPhysics` | Pure 6DOF aerodynamic engine. No instances touched. The core. |
| `src/shared/BirdBuilder.luau` | `ReplicatedStorage.BirdBuilder` | Procedurally builds Eagle/Crow Models; `AnimateWings`. |
| `src/shared/Boids.luau` | `ReplicatedStorage.Boids` | Reynolds boids → flight-input for AI crows. |
| `src/shared/BirdCollision.luau` | `ReplicatedStorage.BirdCollision` | Swept-sphere obstacle/ground collision (`workspace:Spherecast`) — the only shared module that touches Workspace. Replaces the old `Y<4` tunneling stopgap. |
| `src/shared/SpatialHash.luau` | `ReplicatedStorage.SpatialHash` | Uniform-grid broad-phase; backs the server's `findNearestEnemy`/`processCollisions` so proximity stays near-linear as swarms grow. |
| `src/server/GameServer.server.luau` | `ServerScriptService.GameServer` | **Authority:** spawning, combat, collisions, AI crows, rounds, scoring, anti-cheat, Remotes. |
| `src/client/BirdController.client.luau` | `StarterPlayerScripts.BirdController` | Client flight loop, input, camera, free-look FX. |
| `src/client/GameUI.client.luau` | `StarterPlayerScripts.GameUI` | HUD (built entirely in code). In StarterPlayerScripts, NOT StarterGui: with `CharacterAutoLoads=false` StarterGui never copies to PlayerGui, so a HUD script there would never run. |

### Authority / replication model
- **Client owns its bird's physics.** Server hands network ownership of the possessed bird's `Body` part to the controlling client (`SetNetworkOwner`), which runs `FlightPhysics` locally and writes `Body.CFrame` + `AssemblyLinearVelocity`. This is latency-free flight AND the CPU-scaling mechanism.
- **Server owns everything that matters for fairness:** damage, scoring, collisions, AI crows, round flow. Client input/positions are untrusted — a server-side **anti-cheat envelope is now implemented** (`GameServer.processAntiCheat`, tunables in `GameConfig.Security`): server-observed speed from position deltas, leaky-bucket sustained-speed check + per-frame teleport gate, response ladder (rubber-band → reclaim ownership → kick). PLAYTEST-PROVISIONAL thresholds.
- **Obstacle/ground collision** is real (not the old `Y<4` stopgap): `BirdCollision.resolve` sweeps a `Spherecast` along each step. AI crows resolve inline in `updateAICrows`; the client-owned possessed bird slides on grazes locally (feel) while the server authoritatively detects lethal crashes from its replicated position delta (`processCrashes`). A head-on map impact above `GameConfig.Flight.CRASH_SPEED` is lethal; a graze slides. Deep failsafe `Y < -40` still kills anything that tunnels far below the world.
- **AI crows** (the 3 unpossessed) are server-simulated: `Boids.computeSteering` → `Boids.steeringToInput` → `FlightPhysics:Update`, same engine as the player.

### Player representation — IMPORTANT canonical decision
The server sets `CharacterAutoLoads = false` and represents each player's bird(s) as **standalone Models in `Workspace.Birds`**, NOT a Roblox Character/`HumanoidRootPart` (a 4-crow squad can't be one character). **The client scripts still contain the old character-based acquisition and must be reconciled to this** — this is integration task #1 in `docs/HANDOFF.md`. Do not revert the standalone-model decision.

### Contracts that span files (grep before renaming)
- **`FlightPhysics` API:** `.new(profile, position)`; `:Update(dt, input)` with `input = {pitch, roll, yaw, flap, dive}`; `:SetThermalForce(v)`; `:SetWind(v)`. Readable fields: `orientation` (CFrame), `velocity`, `speed`, `verticalSpeed`, `stamina`, `isFlapping`, `isDiving`, `isStalling`, `flapPhase`, `aoaDeg`.
- **`GameConfig`** tables consumed by name across client/server: `Profiles.Eagle/.Crow`, `Flight`, `Squad`, `Thermals`, `Round`, `Camera`, `UI`. Eagle/Crow profiles are kept structurally identical so `FlightPhysics` is class-agnostic — **all asymmetry is in the numbers.**
- **Remotes** (`ReplicatedStorage.Remotes`, created by `GameServer` at startup):
  - RemoteEvents: `TeamAssigned`(S→C: teamName, profile), `Strike`(C→S: fire EDGE, no args — server reads the eagle's authoritative bank to pick left/right/forward strike), `AttackRequest`(C→S: legacy click-melee, kept harmless), `TakeDamage`(S→C: attackerName, target, damage), `ScoreUpdate`(S→C: scores), `GameNotification`(S→C: text, color), `SwapCrow`(C→S: index), `SetFormation`(C→S: formationName), `Respawn`(C→S: manual self-reset, debounced). *(Retired: `WeaponHold` — the old hold-to-extend talon/beak, replaced by `Strike`.)*
  - RemoteFunction: `GetThermals`(C→S) → array of `{position, radius, minHeight, maxHeight, strength}`.
- **UI `_G` hooks:** `GameUI` exposes `_G.UpdateStaminaUI(ratio)` and `_G.SetStallWarning(isStalling)`; `BirdController` calls them.

### Controls (as implemented in `BirdController`)
W/S = pitch, A/D = roll (banking), Q/E = yaw, **LeftShift** = flap, **LeftCtrl** = dive, **Space** = free rotational camera (TOGGLE — orbits while the bird holds its flight path), **MouseButton1** = directional STRIKE (the eagle's bank at the click picks LEFT/RIGHT talon or a FORWARD strike; server-authoritative), **MouseButton2** = aim/zoom (hold to pull the camera in), **1–4** = possess crow N, **F** = toggle tight/loose formation, **R** = manual respawn/reset.

## Working conventions
- **Refine incrementally; do not regenerate the codebase.** It's modular for exactly this — change one module/feature, then Studio-test.
- All Luau files start with `--!nonstrict`.
- The flight numbers in `GameConfig` are research-grounded *starting points*, not final — tune by playtest, always reasoning about the matchup.
- WebSearch/WebFetch are allowlisted in `.claude/settings.json`.
- When a design question is resolved or a new constraint appears, update the project memory.
