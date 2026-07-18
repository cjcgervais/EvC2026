--!nonstrict
--[[
	A6 SMOKE BOOT (S41) - Tier 4.5 REAL-ENGINE load + build gate.

	run-in-roblox 0.3.0 runs at PLUGIN security in EDIT mode (IsRunning=false, verified S41),
	so the game's .server scripts stay DORMANT - we cannot observe the live server round from
	here. The live-runtime classes (squirrel population, Remotes ordering, client-overrides-
	server visuals, at-distance readability) therefore stay Tier 5 (Chad's Play) or a future
	Open Cloud packet. See MASTER-PLAN.md A6 for that honest boundary.

	What this DOES, and what lune Tier 4 canNOT: load the shared modules and build the real
	models in the REAL Roblox engine, catching load/compile/build errors and geometry
	regressions that lune's @lune/roblox approximation could miss. It is GREEN on a healthy
	build; a shared module that fails to load in real Studio, or a degenerate/absent model,
	turns it RED. error(...,0) -> non-zero process exit -> verify.ps1 marks the smoke FAIL.
]]

local RS = game:GetService("ReplicatedStorage")
local pass = {}
local function need(cond, msg) if not cond then error("[SMOKE] FAIL: " .. msg, 0) end end

-- 1. The shared contract loads in the REAL engine (compile + load, not lune's approximation).
local okC, GameConfig = pcall(require, RS:WaitForChild("GameConfig", 10))
need(okC, "GameConfig failed to load: " .. tostring(GameConfig))
local okB, BirdBuilder = pcall(require, RS:WaitForChild("BirdBuilder", 10))
need(okB, "BirdBuilder failed to load: " .. tostring(BirdBuilder))
local okF = pcall(require, RS:WaitForChild("FlightPhysics", 10))
need(okF, "FlightPhysics failed to load")
-- A2.1: the new PURE rescue-rules module must compile + load in the REAL engine too.
local okR = pcall(require, RS:WaitForChild("RescueRules", 10))
need(okR, "RescueRules failed to load")
-- B1: the fire grid must compile + load in the REAL engine too (RescueServer requires it at boot).
local okFG = pcall(require, RS:WaitForChild("FireGrid", 10))
need(okFG, "FireGrid failed to load")
-- B2: the fire visual layer must compile + load in the REAL engine (RescueServer requires it at boot).
local okFV = pcall(require, RS:WaitForChild("FireVisuals", 10))
need(okFV, "FireVisuals failed to load")
-- B3-fix: the terrain-oof FX module (BirdController requires it at boot; its require chain must resolve).
local okBFX = pcall(require, RS:WaitForChild("BounceFX", 10))
need(okBFX, "BounceFX failed to load")
pass[#pass + 1] = "shared modules load"

-- 2. A real squirrel builds, non-degenerate + sized (the "I see no squirrels" class at the BUILD layer).
local R = GameConfig.Rescue
local sq = BirdBuilder.BuildSquirrel(R.squirrelScale or 4.4, {})
need(sq and sq.PrimaryPart, "BuildSquirrel returned no PrimaryPart")
local sqParts = 0
for _, d in ipairs(sq:GetDescendants()) do if d:IsA("BasePart") then sqParts += 1 end end
need(sqParts >= 3, "squirrel degenerate: only " .. sqParts .. " part(s)")
local ext = sq:GetExtentsSize()
need(ext.Magnitude > 1, "squirrel extents degenerate: " .. tostring(ext))
pass[#pass + 1] = ("squirrel builds (%d parts, extents %.1f)"):format(sqParts, ext.Magnitude)

-- 3. The eagle builds WITH the talon rig joints present (the grasp path exists in real Studio).
--    Uses the GAME's real call form (GameServer:528 `Build(profileName, profile)`), NOT
--    talon.spec's malformed `Build(Profiles.Eagle, Vector3)` which passes only under lune's
--    lenient Vector3 and ERRORS in real Studio (a lune-vs-engine discrepancy this gate caught).
local eagle = BirdBuilder.Build("Eagle", GameConfig.Profiles.Eagle)
need(eagle and eagle.PrimaryPart, "BirdBuilder.Build(Eagle) returned no PrimaryPart")
local motors = 0
for _, d in ipairs(eagle:GetDescendants()) do if d:IsA("Motor6D") then motors += 1 end end
need(motors > 0, "eagle has no Motor6D joints (talon rig missing)")
pass[#pass + 1] = ("eagle builds (%d Motor6D joints)"):format(motors)

print("[SMOKE] PASS - real-engine load + build gate:")
for _, p in ipairs(pass) do print("  + " .. p) end
