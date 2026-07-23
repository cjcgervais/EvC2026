--!nonstrict
--[[
	tests/capture/world.capture.luau — M2 "THE EYES" edit-mode screenshot driver (Phase V).

	WHAT IT DOES: run-in-roblox injects this at PLUGIN security in EDIT mode (IsRunning=false,
	same proven vector as tests/smoke/boot.smoke.luau). It builds the NEW worldV2 Terrain valley
	directly via WorldGen.build(workspace, GameConfig) — regardless of the GameConfig.Map.worldV2
	flag, because M2 look-dev iterates the WorldGen world specifically — then steps
	workspace.CurrentCamera through a FIXED table of 14 vantage poses (open-horizon packet: 11→14),
	printing a stdout sentinel at each so tools/Capture-World.ps1 can grab the Studio window at the
	right moment.

	═══ THE HARD CONSTRAINT (deviation from the MASTER-PLAN M2 wording) ═══
	The plan's hardening ① calls for a "sentinel-FILE handshake". That is IMPOSSIBLE here:
	run-in-roblox gives a ONE-WAY channel only — Studio→PowerShell via stdout `print`. Luau at
	plugin security cannot READ files or receive stdin, so it can never receive a per-shot capture
	ACK. So this is a STDOUT-SIGNALLED capture with a fixed DWELL budget, not a bidirectional ack:
	  • the script sets each pose, prints `M2READY <i> <name>`, then task.wait(DWELL) to HOLD it;
	  • PowerShell tails stdout and, on each M2READY line, waits a short settle then screenshots.
	run-in-roblox CLOSES Studio the instant this script RETURNS, so the total held time (Σ DWELL)
	must comfortably exceed PowerShell's capture time — DWELL is deliberately generous (2.5s).

	═══ SCOPE (LOCKED for M2) ═══
	In edit mode the .server scripts are DORMANT, so RescueServer's groves / waterfall / squirrels
	do NOT exist — this script can only build what WorldGen builds. The M2 sheet is therefore the
	WorldGen TERRAIN + LIGHTING only. That is EXACTLY what M1/M3 look-dev iterates, so it is the
	correct scope. KNOWN LIMITATION: grove / waterfall / critter set-dressing is dormant in edit
	mode; a later capture enhancement (or a RescueWorld extraction that build() could call) could
	add it. The vantages below still AIM at where those will sit.

	This build() call also doubles as the applier's real-engine smoke: the FIRST time sculpt /
	FillBlock / applyLighting run in a real Roblox engine (Tier-4 lune cannot build Terrain), so a
	broken applier fails LOUD here with `[CAPTURE] FAIL`.
]]

local RS = game:GetService("ReplicatedStorage")

-- Mirror boot.smoke's `need`: fail loud (non-zero exit) with a greppable sentinel.
local function need(cond, msg)
	if not cond then
		print("[CAPTURE] FAIL: " .. msg)
		error("[CAPTURE] FAIL: " .. msg, 0)
	end
end

-- 1. Load the shared contract in the REAL engine (compile + load, not lune's approximation).
local okC, GameConfig = pcall(require, RS:WaitForChild("GameConfig", 10))
need(okC, "GameConfig failed to load: " .. tostring(GameConfig))
local okW, WorldGen = pcall(require, RS:WaitForChild("WorldGen", 10))
need(okW, "WorldGen failed to load: " .. tostring(WorldGen))

-- 2. Build the NEW valley in edit mode. We call build() DIRECTLY (not via the worldV2 flag): M2
--    exists to look-dev the WorldGen world, so we always want it. This is the applier's first
--    real-engine run — fail loud if it errors.
local okB, errB = pcall(function()
	WorldGen.build(workspace, GameConfig)
end)
need(okB, "WorldGen.build errored in real Studio: " .. tostring(errB))

-- 3. SETTLE — the Terrain render mesher lags the voxel writes asynchronously (build() only issues the
--    Fill* calls; the visual mesh regenerates on its own schedule), so shooting immediately after
--    build() races it — two runs of this same script rendered differently. Hold a fixed settle window
--    before the vantage loop so every capture run shoots the same converged mesh.
print("[CAPTURE] settling...")
for _ = 1, 12 do
	task.wait(1)
end

--------------------------------------------------------------------------------
-- FIXED VANTAGE TABLE (hardening ③): committed config. Changing a pose is a reviewable diff, so
-- no session can silently reframe flattering shots. Coordinates derive from world FACTS:
--   valley center (0,0), datum Y=0, spawn box ±1200 @ Y=600, deliverPos (1150,250,0),
--   fire-grove annulus r 300..1400, perch band ≈1500, foothill crest r≈4300 height≈220,
--   mid mountain clusters r≈6200, far mountain clusters r≈8200.
-- CFrame.lookAt(eye, target) for readability — each looks at what the region is ABOUT.
--------------------------------------------------------------------------------
local VANTAGES = {
	-- Near the spawn box, looking forward and down over the bowl (the player's first frame).
	{ name = "spawn",             cf = CFrame.lookAt(Vector3.new(0, 600, 0),      Vector3.new(900, 100, 0)) },
	-- High, angled ~600 studs back — the whole bowl + rim ring in one read.
	{ name = "overview",          cf = CFrame.lookAt(Vector3.new(0, 1400, -600),  Vector3.new(0, 0, 400)) },
	-- Low over the fire-grove annulus (where the trees + critters will sit).
	{ name = "grove-interior",    cf = CFrame.lookAt(Vector3.new(600, 120, 0),    Vector3.new(1100, 40, 300)) },
	-- Toward the delivery pad / waterfall (deliverPos 1150,250,0).
	{ name = "waterfall-approach",cf = CFrame.lookAt(Vector3.new(600, 320, 0),    Vector3.new(1150, 250, 0)) },
	-- A steep down-look dive line into the bowl.
	{ name = "dive-line",         cf = CFrame.lookAt(Vector3.new(0, 900, -400),   Vector3.new(0, 0, 200)) },
	-- Low across the annulus — the fire line read (smoke/flame region).
	{ name = "fire-line",         cf = CFrame.lookAt(Vector3.new(-400, 150, 900), Vector3.new(400, 40, 100)) },
	-- Behind and above the delivery pad, looking down at it (the delivery run).
	{ name = "delivery-run",      cf = CFrame.lookAt(Vector3.new(1500, 500, 0),   Vector3.new(1150, 250, 0)) },
	-- Low near the flat edge, looking OUT at the foothills + falloff collar + sky — the money shot: the
	-- ground should fall into the haze, with broken mountains against open sky, not a wall.
	{ name = "horizon",           cf = CFrame.lookAt(Vector3.new(0, 200, -2800),  Vector3.new(0, 900, -6000)) },
	-- Near-straight-down onto the foothill ring from above the crests — verifies the hills read rolling
	-- and broken (gaps between them), not a continuous ridge.
	{ name = "rim-nadir",         cf = CFrame.lookAt(Vector3.new(4600, 2800, 0),  Vector3.new(4600, 200, 0)) },
	-- Through the open WEST_ARC toward the WestSea — renamed from "west-pass": with the west foothill
	-- arc open (not a saddle in a wall), this is a true open-water horizon shot.
	{ name = "west-sea-horizon",  cf = CFrame.lookAt(Vector3.new(-1500, 250, 0), Vector3.new(-6000, 500, 0)) },
	-- High orbit outside the foothill ring looking back at the outer face + falloff collar — verifies
	-- the surround reads as open rolling terrain from outside, not an enclosing wall.
	{ name = "outside-in",        cf = CFrame.lookAt(Vector3.new(6500, 1500, 0), Vector3.new(4000, 600, 0)) },
	-- ADDED (open-horizon packet): low, looking north along the mid-ridge mountain clusters — reads the
	-- broken cluster silhouette + sky gaps between them.
	{ name = "mountains-north",   cf = CFrame.lookAt(Vector3.new(0, 140, -3200), Vector3.new(0, 700, -7000)) },
	-- ADDED: level with the mesa, looking at the forced az≈0 far-cluster peak — the waterfall backdrop.
	{ name = "mountains-backdrop",cf = CFrame.lookAt(Vector3.new(700, 300, 0),   Vector3.new(7000, 900, 0)) },
	-- ADDED: low, far out over the falloff collar — the eye-level haze read (Atmosphere Density/Haze).
	{ name = "eye-level-haze",    cf = CFrame.lookAt(Vector3.new(0, 120, 3000),  Vector3.new(0, 180, 7000)) },
}

-- DWELL: the sync budget. Held long enough that PowerShell's settle+screenshot completes before
-- the pose moves AND before this script returns (which closes Studio). See the header constraint.
local DWELL = 2.5

-- S50 FINDING: in EDIT mode the Studio viewport IGNORES CameraType.Scriptable (the S49 run captured
-- 8 identical default views). Plugins move the edit camera by writing CFrame/Focus directly on the
-- DEFAULT camera type — so no Scriptable here. The read-back print instruments whether the write
-- actually stuck (SOP: never fly the same failed fix twice without an instrument).
local cam = workspace.CurrentCamera
cam.FieldOfView = 70

for i, v in ipairs(VANTAGES) do
	cam.CFrame = v.cf
	cam.Focus = CFrame.new(v.cf.Position + v.cf.LookVector * 100)
	task.wait(0.1) -- let Studio process the property write before we read it back
	local stuck = (cam.CFrame.Position - v.cf.Position).Magnitude < 1
	print(("M2READY %d %s stuck=%s"):format(i, v.name, tostring(stuck)))
	task.wait(DWELL)
end

print(("M2DONE %d"):format(#VANTAGES))
