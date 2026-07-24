--!nonstrict
--[[
	tests/capture/world.bake.luau — the bake pipeline's Studio-side driver (tools/Bake-World.ps1).

	WHAT IT DOES: run-in-roblox injects this at PLUGIN security in EDIT mode (same proven vector as
	world.capture.luau / boot.smoke.luau). It builds the LIVE worldV2 valley directly via
	WorldGen.build (terrain:Clear() then the real Fill* sculpt — build() always Clears first, so no
	project-flag gymnastics are needed here even though the CHECKED-IN project now consumes a baked
	artifact: the bake always re-sculpts from source; only the RUNTIME consumer skips sculpting), waits
	a settle window for the async Terrain mesher/voxel commit, then prints the BAKEREADY sentinel and
	DWELLS — giving tools/Bake-World.ps1 time to Ctrl+S the place (saving the sculpted SmoothGrid to the
	temp .rbxlx run-in-roblox opened) before run-in-roblox kills Studio on script return.

	This is a ONE-WAY channel (Studio -> PowerShell via stdout print, same constraint as M2's capture
	script): Luau at plugin security cannot read a file or receive stdin, so the wrapper cannot ACK a
	completed save back to this script. The DWELL is therefore a generous fixed budget, not a real
	handshake — tools/Bake-World.ps1 documents the same asymmetry.
]]

local RS = game:GetService("ReplicatedStorage")

local function need(cond, msg)
	if not cond then
		print("[BAKE] FAIL: " .. msg)
		error("[BAKE] FAIL: " .. msg, 0)
	end
end

-- 1. Load the shared contract in the REAL engine.
local okC, GameConfig = pcall(require, RS:WaitForChild("GameConfig", 10))
need(okC, "GameConfig failed to load: " .. tostring(GameConfig))
local okW, WorldGen = pcall(require, RS:WaitForChild("WorldGen", 10))
need(okW, "WorldGen failed to load: " .. tostring(WorldGen))

-- 2. Build the LIVE valley. Always the full (non-skipSculpt) build — a bake exists specifically to
--    produce real SmoothGrid voxels, so this must never consume a previously-baked shortcut. build()
--    already terrain:Clear()s before sculpting, so any Terrain wired in from the checked-in
--    (possibly-baked) assets/BakedTerrain.rbxm placeholder is simply overwritten with a fresh sculpt.
local okB, errB = pcall(function()
	WorldGen.build(workspace, GameConfig)
end)
need(okB, "WorldGen.build errored in real Studio: " .. tostring(errB))

-- 3. SETTLE — same reasoning as world.capture.luau: the Terrain render mesher / voxel commit lags the
--    Fill* writes asynchronously. A save immediately after build() risks capturing a not-yet-committed
--    voxel state. ~5s per the spec (shorter than M2's 12s look-dev settle: a bake only needs the voxel
--    data committed to disk-serializable state, not a converged RENDER for a screenshot).
print("[BAKE] settling...")
for _ = 1, 5 do
	task.wait(1)
end

-- 4. READY — tools/Bake-World.ps1 tails stdout for this exact sentinel, then Ctrl+S's the Studio
--    window (the place was opened by run-in-roblox from a temp .rbxlx path, so Ctrl+S saves in place
--    with no dialog) and copies the saved file out before this script returns.
print("BAKEREADY")

-- 5. DWELL — hold the process open long enough for the wrapper to detect+copy the save. run-in-roblox
--    closes Studio the instant this script RETURNS, so this budget must comfortably exceed the
--    wrapper's poll-for-LastWriteTime-change + copy time (Bake-World.ps1 polls up to 30s).
task.wait(40)

print("BAKEDONE")
