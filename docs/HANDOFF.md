# HANDOFF — Eagles vs Crows

Read this first. It tells the next agent exactly where the project stands, the one decision that's already been made for you, and the prioritized work queue. Pair it with `CLAUDE.md` (architecture + contracts), `docs/RESEARCH.md` (why the numbers are what they are), and project memory (`MEMORY.md` index).

---

## Status (2026-06-23)

A complete v1 skeleton exists as real, version-controlled Luau source under `src/`, wired for [Rojo](https://rojo.space) via `default.project.json`. **It has NOT been run in Roblox Studio yet** — there is no Luau toolchain in this environment, so nothing has been syntax-checked or playtested. Treat "it runs cleanly" as unverified until you open it in Studio.

| File | Lines | State |
|------|-------|-------|
| `src/shared/GameConfig.luau` | ~217 | **Solid.** Research-backed tunables; the shared contract. Authored directly, coherent. |
| `src/shared/FlightPhysics.luau` | ~250 | **Solid.** 6DOF engine (lift/drag/stall, banking turn, two-turn-param model, stamina). Authored directly. |
| `src/shared/BirdBuilder.luau` | ~240 | Subagent-built. Procedural Eagle/Crow models + `AnimateWings`. Skim before trusting. |
| `src/shared/Boids.luau` | ~229 | Subagent-built. `computeSteering` + `steeringToInput`. Skim. |
| `src/server/GameServer.server.luau` | ~956 | Subagent-built. Authoritative combat, collisions, AI crows, rounds. **Largest risk surface.** |
| `src/client/BirdController.client.luau` | ~428 | Subagent-built. Flight loop, camera, free-look, input. **Has the integration mismatch below.** |
| `src/client/GameUI.client.luau` | ~411 | Subagent-built. Full HUD. **Has the integration mismatch below.** |

---

## ⚠️ THE ONE DECISION ALREADY MADE — read before touching the client

The server (`GameServer`) deliberately sets `player.CharacterAutoLoads = false` and represents each player's bird(s) as **standalone Models in `Workspace.Birds`** — NOT as a Roblox Character with a `HumanoidRootPart`.

**This is the correct architecture and is now canonical.** Do not revert it. Reason: a Crow player controls **4 separate bird bodies** with possession-swapping — a single Roblox Character cannot represent that. The eagle is just the 1-body case of the same model.

**The problem:** the two client scripts were written against the *old* character assumption. They still listen for `player.CharacterAdded` and `character:WaitForChild("HumanoidRootPart")`, which will never fire under the standalone-model design. **This is integration task #1.**

### The contract to implement (both sides must agree)
- **Server** (verify/finish): tag each spawned bird so the client can find it. Recommended: `model:SetAttribute("OwnerUserId", player.UserId)` on every bird, plus `model:SetAttribute("Possessed", true)` on the active one (and keep it updated on `SwapCrow`). Network ownership of the possessed bird's `Body` part goes to the player (already done via `SetNetworkOwner`). Health already lives as a `"Health"` Attribute on each model's `PrimaryPart` (`Body`).
- **Client `BirdController`:** replace the `CharacterAdded` path with: on `TeamAssigned`, scan `Workspace.Birds` for the model(s) whose `OwnerUserId == player.UserId`; drive the one with `Possessed == true` (re-acquire on `SwapCrow` / when the attribute changes). Drive its `PrimaryPart` (`Body`) `CFrame` + `AssemblyLinearVelocity` instead of `HumanoidRootPart`. Drop `humanoid.PlatformStand` (no humanoid).
- **Client `GameUI`:** read speed/altitude/health from the possessed bird's `Body` part (and its `"Health"` Attribute), not `player.Character.HumanoidRootPart`.

Do this first, in Studio, with one Eagle and one Crow player (use a second Studio player or a bot) — nothing else can be tested until birds actually fly.

---

## Prioritized work queue

1. **Fix the character/standalone-model integration (above).** Blocks everything.
2. **First Studio smoke test.** Build with Rojo (`rojo serve` → connect the Studio plugin, or `rojo build -o EaglesVsCrows.rbxlx`). Fix syntax/runtime errors. Confirm: a bird spawns, flies with WASD/Shift, the camera + free-look (Space) work, the HUD updates.
3. **Tune the flight feel** (`FlightPhysics` + `GameConfig.Profiles`). The numbers are research-grounded *starting points*, not final. Verify the energy-fighter (eagle) vs angles-fighter (crow) feel emerges. Watch for: birds that can't pull out of dives, stalls that feel punishing-vs-fun, banking turns that are too wide/tight.
4. **Tune the lose-lose collision** (`GameServer.processCollisions` + `GameConfig` collision numbers). This is the biggest *unverified* design (no research backing). Target: ~4 full-speed crow rams kill an eagle while each ramming crow dies, so it's a true trade the skilled eagle avoids by picking off stragglers. See open-questions memory.
5. **Possession ↔ boids handoff polish.** Swapping crows should be seamless; the released crow rejoins the swarm via `Boids` with no visible snap.
6. **Anti-cheat envelope** (server-side movement validation) — see RESEARCH §7. Must not false-positive dives/loops/thermals.
7. **Performance at scale** — Parallel Luau actors for boids/aero (RESEARCH §6), LOD/replication throttling for distant swarms (open-questions #5). Only after it's fun.

---

## How to work here (process)
- **Refine incrementally, don't regenerate.** The codebase is modular for exactly this. Change one module/feature at a time and Studio-test it.
- **Honor the thesis:** any flight-number change is a balance change and vice-versa (`feedback-flight-balance-inseparable` memory). Reason about the 1-eagle-vs-4-crow matchup on every tuning edit.
- **Keep contracts stable:** `GameConfig` keys, the `FlightPhysics` API, and the Remotes list are consumed across files — grep before renaming. The Remotes contract is documented in `CLAUDE.md`.
- **Update memory** (`C:\Users\Chad\.claude\projects\D--eaglesvscrows2026\memory\`) when a design question gets resolved or a new constraint appears.
- WebSearch/WebFetch are allowlisted in `.claude/settings.json` (the deep-research workflow needed them).

## Continuation prompt (paste into a fresh session if needed)
> You are continuing "Eagles vs Crows", a physics aerial-combat game on Roblox (Luau). Read `CLAUDE.md`, `docs/HANDOFF.md`, and `docs/RESEARCH.md`, plus the project memory index `MEMORY.md`. The v1 skeleton is built (`src/`, Rojo). Start with integration task #1 in HANDOFF (the standalone-bird-model vs character mismatch in the client scripts), then do a Studio smoke test. Refine incrementally; do not regenerate the codebase. Remember the core thesis: flight physics and asymmetric balance are one system.
