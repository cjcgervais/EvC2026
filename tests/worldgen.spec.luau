--!nonstrict
--[[
	tests/worldgen.spec.luau — the Tier-4 gates for packet M1 (the Terrain valley + lighting rig).

	These run entirely against WorldGen.plan (the PURE half) — NEVER WorldGen.build, which touches
	Terrain/Lighting/Workspace that @lune/roblox cannot model. Each gate pins one of the M1
	invariants so the world's LOOK can be tuned later (M3) without any of them silently regressing:

	  1. datum          — the playable floor is flat at Y=0 across every load-bearing site, and the
	                       rim actually rises (the bowl is real, not a flat plane).
	  2. water-P3       — every water body has a solid floor far above the -200 failsafe, so
	                       BirdCollision's IgnoreWater blindness can't drop a bird past it.
	  3. canopy         — this module builds no "Canopy" part and re-seats the groves at datum.
	  4. drift          — every decorative Part is CanQuery=false, so the style meter can't drift.
	  5. coplanarity    — no two overlapping Parts share a top-face Y (V0's z-fight test idea).
	  6. contract       — the birth contract (gravity + streamingEnabled + lighting keys) and
	                       determinism, plus kill-switch honesty.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local WorldGen = Loader.load("WorldGen")
local GameConfig = Loader.load("GameConfig")

local GROUND_FAILSAFE_Y = -200 -- GameServer.server.luau:74 — the deep kill line the water floors must clear.
local DATUM_BAND = 8           -- studs; the playable floor must read within this of Y=0.

--------------------------------------------------------------------------------
-- 1. DATUM — the playable floor is flat at datum, and the rim genuinely rises.
--------------------------------------------------------------------------------
H.test("datum: every load-bearing site sits within the datum band of Y=0", function()
	local plan = WorldGen.plan(GameConfig)
	H.ok(#plan.datumSamples > 0, "plan.datumSamples is empty — the datum gate would be vacuous")
	for _, s in ipairs(plan.datumSamples) do
		local y = plan.heightAt(s.x, s.z)
		H.between(y, -DATUM_BAND, DATUM_BAND,
			("%s site at (%.0f, %.0f) reads Y=%.2f, outside the ±%d datum band — spawn/deliver/annulus/" ..
				"thermal numbers are all tuned to Y=0"):format(s.label, s.x, s.z, y, DATUM_BAND))
	end
end)

H.test("datum: the rim actually RISES — the bowl is real, not a flat plane", function()
	local plan = WorldGen.plan(GameConfig)
	-- Sampled outward on the +X axis: still flat near the playable edge, tall by r≈4000.
	H.between(plan.heightAt(3200, 0), -DATUM_BAND, DATUM_BAND, "the thermal-ring radius must still be flat")
	H.ok(plan.heightAt(4000, 0) > 300,
		("the rim only reached Y=%.0f at r=4000 — it must climb (>300) or there is no bowl, just a plane")
			:format(plan.heightAt(4000, 0)))
	-- And the crest is above the outer plain in every cardinal direction (a ring, not a wall).
	for _, dir in ipairs({ { 5200, 0 }, { -5200, 0 }, { 0, 5200 }, { 0, -5200 } }) do
		H.ok(plan.heightAt(dir[1], dir[2]) > 300, "the rim must ring the whole valley")
	end
end)

--------------------------------------------------------------------------------
-- 2. WATER-P3 — the P3 landmine. IgnoreWater=true means the bird falls through water to the solid
-- beneath; every water body must therefore floor WELL above the failsafe.
--------------------------------------------------------------------------------
H.test("water-P3: every water body has a solid floor far above the failsafe", function()
	local plan = WorldGen.plan(GameConfig)
	H.ok(#plan.water > 0, "plan.water is empty — a valley with no lake/sea, or the gate has gone vacuous")
	for _, b in ipairs(plan.water) do
		H.ok(b.floorY > -40,
			("%s floors at Y=%.0f — must be > -40 (the plan's conservative line)"):format(b.name, b.floorY))
		H.ok(b.floorY > GROUND_FAILSAFE_Y + 100,
			("%s floors at Y=%.0f — must clear the -200 failsafe with margin, or a bird over it (IgnoreWater) " ..
				"falls past -200 and dies"):format(b.name, b.floorY))
		H.ok(b.surfaceY > b.floorY, ("%s surface Y=%.0f must sit above its floor Y=%.0f"):format(b.name, b.surfaceY, b.floorY))
	end
end)

H.test("water-P3: the hidden CATCH FLOOR underlies the whole reachable world above the failsafe", function()
	local plan = WorldGen.plan(GameConfig)
	-- (a) the catch floor clears the -200 failsafe with margin, and sits BELOW every water floor
	-- (so it never occludes a lake).
	H.ok(plan.catchFloorY > GROUND_FAILSAFE_Y + 50,
		("catchFloorY=%.0f must clear the -200 failsafe with margin, or a graze into void still dies")
			:format(plan.catchFloorY))
	local minWaterFloor = math.huge
	for _, b in ipairs(plan.water) do minWaterFloor = math.min(minWaterFloor, b.floorY) end
	H.ok(plan.catchFloorY < minWaterFloor,
		("catchFloorY=%.0f must sit below the lowest water floor (%.0f) or it caps a lake"):format(plan.catchFloorY, minWaterFloor))
	-- (b) P3 coverage: the catch slab spans at least the reachable radius, so no reachable void gap
	-- (the axis crescents r=FLAT_R→rim, and everything past the rim) can drop a bird past -200.
	H.ok(plan.reachableRadius >= 8000,
		("reachableRadius=%.0f must cover the legacy baseplate reach (±8000) so no reachable void exists")
			:format(plan.reachableRadius))
end)

H.test("water-P3: sampling every water region, the solid floor never crosses the failsafe", function()
	local plan = WorldGen.plan(GameConfig)
	for _, b in ipairs(plan.water) do
		local reg = b.region
		-- The solid floor beneath a water column is the body's floorY (a constant terrain floor).
		-- Sweep a grid across the region and assert the surface→solid gap never crosses -200.
		for gx = reg.minX, reg.maxX, math.max(200, (reg.maxX - reg.minX) / 6) do
			for gz = reg.minZ, reg.maxZ, math.max(200, (reg.maxZ - reg.minZ) / 6) do
				H.ok(b.floorY > GROUND_FAILSAFE_Y,
					("%s column (%.0f,%.0f): solid floor %.0f is at/below the failsafe -200"):format(b.name, gx, gz, b.floorY))
				H.ok(b.surfaceY - b.floorY < math.abs(GROUND_FAILSAFE_Y),
					("%s column (%.0f,%.0f): surface→solid gap crosses the failsafe"):format(b.name, gx, gz))
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 3. CANOPY — the RescueWorld contract is untouched: no "Canopy" part is minted here, and the
-- grove-annulus datum samples stay flat (re-seated groves sit at datum).
--------------------------------------------------------------------------------
H.test("canopy: the plan builds ZERO Canopy parts (RescueWorld contract untouched)", function()
	local plan = WorldGen.plan(GameConfig)
	for _, p in ipairs(plan.parts) do
		H.ok(p.name ~= "Canopy" and not tostring(p.name):find("Canopy"),
			("WorldGen minted a part named %q — CanopyCount / B4.2 scoring is RescueServer's, not the map's")
				:format(tostring(p.name)))
	end
end)

H.test("canopy: the grove annulus stays flat so re-seated groves sit at datum", function()
	local plan = WorldGen.plan(GameConfig)
	for _, s in ipairs(plan.datumSamples) do
		if tostring(s.label):find("annulus") then
			H.between(plan.heightAt(s.x, s.z), -DATUM_BAND, DATUM_BAND,
				("grove annulus site (%.0f,%.0f) is not flat — groves built at Y=0 would float or sink")
					:format(s.x, s.z))
		end
	end
end)

--------------------------------------------------------------------------------
-- 4. DRIFT (style-economy) — the style meter only sees CanQuery=true parts. Every decorative part
-- MUST be CanQuery=false or styleProxDist can drift.
--------------------------------------------------------------------------------
H.test("drift: every decorative part is CanQuery=false", function()
	local plan = WorldGen.plan(GameConfig)
	for _, p in ipairs(plan.parts) do
		H.eq(p.canQuery, false,
			("part %q is queryable — the style meter would see it and styleProxDist(40) could drift")
				:format(tostring(p.name)))
	end
end)

--------------------------------------------------------------------------------
-- 5. COPLANARITY — V0's surviving idea: no two overlapping Parts may share a top-face Y (terrain
-- itself cannot z-fight, but any Part can). Trivially true while parts is empty; asserted anyway.
--------------------------------------------------------------------------------
H.test("coplanarity: no overlapping pair of parts shares a top-face Y", function()
	local plan = WorldGen.plan(GameConfig)
	if #plan.parts == 0 then
		H.ok(true, "plan.parts is empty — terrain does the work; nothing can z-fight")
		return
	end
	local function top(p) return p.pos.Y + p.size.Y / 2 end
	local function overlapXZ(a, b)
		return math.abs(a.pos.X - b.pos.X) < (a.size.X + b.size.X) / 2
			and math.abs(a.pos.Z - b.pos.Z) < (a.size.Z + b.size.Z) / 2
	end
	for i = 1, #plan.parts do
		for j = i + 1, #plan.parts do
			local a, b = plan.parts[i], plan.parts[j]
			if overlapXZ(a, b) then
				H.ok(math.abs(top(a) - top(b)) >= 0.05,
					("%q and %q overlap in XZ and share a top-face Y (%.3f) — that z-fights"):format(a.name, b.name, top(a)))
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 6. CONTRACT — the birth contract, the lighting keys, determinism, and kill-switch honesty.
--------------------------------------------------------------------------------
H.test("contract: gravity + streamingEnabled reproduce the legacy birth contract", function()
	local plan = WorldGen.plan(GameConfig)
	H.eq(plan.gravity, GameConfig.Flight.GRAVITY,
		"plan.gravity must equal GameConfig.Flight.GRAVITY (legacy BuildMap:260)")
	H.eq(plan.streamingEnabled, false, "plan.streamingEnabled must be false (legacy BuildMap:267)")
end)

H.test("contract: the lighting rig carries the expected effect tables", function()
	local plan = WorldGen.plan(GameConfig)
	local L = plan.lighting
	H.ok(L ~= nil, "plan.lighting is missing")
	H.ok(type(L.Atmosphere) == "table", "lighting.Atmosphere table is missing (aerial-depth haze)")
	H.ok(type(L.ColorCorrection) == "table", "lighting.ColorCorrection table is missing")
	H.ok(type(L.Bloom) == "table", "lighting.Bloom table is missing")
	H.finite(L.ClockTime, "lighting.ClockTime must be a number (the golden low sun)")
end)

H.test("contract: plan is deterministic — identical heightAt + water + parts across two calls", function()
	local a = WorldGen.plan(GameConfig)
	local b = WorldGen.plan(GameConfig)
	-- heightAt: identical over a spread of samples (incl. the rim).
	for _, pt in ipairs({ { 0, 0 }, { 1200, 1200 }, { 1150, 0 }, { 3200, 0 }, { 4000, 0 }, { -5200, 0 } }) do
		H.eq(a.heightAt(pt[1], pt[2]), b.heightAt(pt[1], pt[2]),
			("heightAt(%.0f,%.0f) drifted between calls — the plan must be pure"):format(pt[1], pt[2]))
	end
	H.eq(#a.water, #b.water, "water body count drifted between calls")
	for i = 1, #a.water do
		H.eq(a.water[i].floorY, b.water[i].floorY, "water floorY drifted between calls")
		H.eq(a.water[i].name, b.water[i].name, "water name drifted between calls")
	end
	H.eq(#a.parts, #b.parts, "parts count drifted between calls")
end)

H.test("contract: the kill switch exists (honest flag)", function()
	H.ok(GameConfig.Map ~= nil, "GameConfig.Map is missing")
	H.ok(GameConfig.Map.worldV2 ~= nil,
		"GameConfig.Map.worldV2 is nil — the kill switch must exist so flag-off restores the legacy path")
end)
