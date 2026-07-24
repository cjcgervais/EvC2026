--!nonstrict
--[[
	tests/worldgen.spec.luau — the Tier-4 gates for packet M1 (the Terrain valley + lighting rig).

	These run entirely against WorldGen.plan (the PURE half) — NEVER WorldGen.build, which touches
	Terrain/Lighting/Workspace that @lune/roblox cannot model. Each gate pins one of the M1
	invariants so the world's LOOK can be tuned later (M3) without any of them silently regressing:

	  1. datum          — the playable floor is flat at Y=0 across every load-bearing site, and the
	                       surround rises to a broken foothill crest then genuinely falls away (open
	                       horizon, not an enclosing wall).
	  2. water-P3       — every water body has a solid floor far above the -200 failsafe, so
	                       BirdCollision's IgnoreWater blindness can't drop a bird past it.
	  3. canopy         — this module builds no "Canopy" part and re-seats the groves at datum.
	  4. drift          — every decorative Part is CanQuery=false, except the documented CatchFloor
	                       exception (S51: the P3 catch floor moved off terrain onto a Part — see 4b).
	  5. coplanarity    — no two overlapping Parts share a top-face Y (V0's z-fight test idea).
	  6. contract       — the birth contract (gravity + streamingEnabled + lighting keys) and
	                       determinism, plus kill-switch honesty.
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Enum = Loader.Enum

local WorldGen = Loader.load("WorldGen")
local GameConfig = Loader.load("GameConfig")

local GROUND_FAILSAFE_Y = -200 -- GameServer.server.luau:74 — the deep kill line the water floors must clear.
local DATUM_BAND = 8           -- studs; the playable floor must read within this of Y=0.

--------------------------------------------------------------------------------
-- 1. DATUM — the playable floor is flat at datum, and the surround rises then genuinely falls away.
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

H.test("datum: the surround RISES then FALLS AWAY — open horizon, not an enclosing wall", function()
	local plan = WorldGen.plan(GameConfig)
	-- Sampled outward on the +X axis (outside the west arc): still flat near the playable edge, rises to
	-- a broken foothill crest, then genuinely falls away past it (no wall holding the ground up).
	H.between(plan.heightAt(3200, 0), -DATUM_BAND, DATUM_BAND, "the thermal-ring radius must still be flat")
	local crestY = plan.heightAt(4200, 0)
	H.between(crestY, 80, 400,
		("the foothill crest at r=4200 reads Y=%.0f — expected 80..400 (a broken hill crest, not a rim wall)"):format(crestY))
	local farY = plan.heightAt(6500, 0)
	H.ok(farY < crestY, ("the ground at r=6500 (Y=%.0f) must sit below the foothill crest (Y=%.0f) — it must FALL AWAY"):format(farY, crestY))
	H.ok(farY < 0, ("the ground at r=6500 reads Y=%.0f — expected <0, visibly dropped toward the haze"):format(farY))
	-- The declared WEST_ARC (due west) must read low relative to the crest elsewhere — the true open
	-- sightline to the WestSea, not just a saddle in a wall.
	local westY = plan.heightAt(math.cos(math.rad(180)) * 4200, math.sin(math.rad(180)) * 4200)
	H.ok(westY < crestY * 0.5,
		("west-arc crest at r=4200 reads Y=%.0f, not low relative to the non-west crest (Y=%.0f) — the west opening isn't reading as open"):format(westY, crestY))
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
	-- (b) P3 coverage: the catch slab must reach at least 500 studs past the outermost distant-mountain
	-- geometry, so no reachable void gap — including just beyond the mountain backdrop, the S51
	-- red-team's P3 safety hole — can drop a bird past -200. §2 bar packet: the mountains are now
	-- sculpted TERRAIN, not Parts (plan.parts holds only the CatchFloor), so this reads
	-- plan.mountainMaxR (computed live by buildMountainRange) instead of deriving it from plan.parts —
	-- a future mountain-radius tune can never go stale against this gate.
	H.ok(plan.mountainMaxR and plan.mountainMaxR > 0, "expected plan.mountainMaxR to compute the reachable-radius margin from")
	H.ok(plan.reachableRadius >= plan.mountainMaxR + 500,
		("reachableRadius=%.0f must cover at least 500 studs past the outermost mountain geometry (mountainMaxR=%.0f)")
			:format(plan.reachableRadius, plan.mountainMaxR))
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
-- 4. DRIFT (style-economy) — the style meter only sees CanQuery=true parts. Every DECORATIVE part
-- MUST be CanQuery=false or styleProxDist can drift. S51: the P3 catch floor is now a Part (moved off
-- terrain to cut sculpt cost) and is the ONE documented invariant-④ exception — it MUST be
-- CanQuery=true or BirdCollision's Spherecast can't see it — so this gate carves it out by name
-- instead of going vacuous or false-failing.
--------------------------------------------------------------------------------
H.test("drift: every decorative part is CanQuery=false (except the documented CatchFloor exception)", function()
	local plan = WorldGen.plan(GameConfig)
	local sawCatchFloor = false
	for _, p in ipairs(plan.parts) do
		if p.name == "CatchFloor" then
			sawCatchFloor = true
			H.eq(p.canQuery, true, "CatchFloor must be CanQuery=true or BirdCollision's Spherecast can't see it")
		else
			H.eq(p.canQuery, false,
				("part %q is queryable — the style meter would see it and styleProxDist(40) could drift")
					:format(tostring(p.name)))
		end
	end
	H.ok(sawCatchFloor, "expected a CatchFloor part in plan.parts (the P3 catch floor)")
end)

--------------------------------------------------------------------------------
-- 4b. CATCH FLOOR PART (S51) — the P3 catch floor invariant re-encoded on plan.parts data now that it's
-- a Part instead of a terrain fill: a solid, queryable slab spans at least ±reachableRadius, with its
-- top face exactly at CATCH_FLOOR_Y (plan.catchFloorY), which in turn clears GROUND_FAILSAFE_Y with
-- margin (asserted separately by the water-P3 catch-floor test above). Better than the old source-grep:
-- this is real geometry the lune harness can check.
--------------------------------------------------------------------------------
H.test("catch floor: the CatchFloor part is a solid, queryable, opaque slab spanning the reachable world", function()
	local plan = WorldGen.plan(GameConfig)
	local catchFloor
	for _, p in ipairs(plan.parts) do
		if p.name == "CatchFloor" then catchFloor = p end
	end
	H.ok(catchFloor ~= nil, "expected a CatchFloor part in plan.parts")
	H.eq(catchFloor.canQuery, true, "CatchFloor must be CanQuery=true so BirdCollision's Spherecast sees it")
	H.ok(catchFloor.transparency == 0, "CatchFloor must be opaque (Transparency=0) — a gap above it must read as ground, not skybox")
	H.ok(catchFloor.color ~= nil, "CatchFloor must set a color (dark rock, not the default gray)")
	H.eq(catchFloor.material, Enum.Material.Slate, "CatchFloor must be Slate to read as rock")
	H.ok(catchFloor.size.X >= plan.reachableRadius * 2 and catchFloor.size.Z >= plan.reachableRadius * 2,
		("CatchFloor is %.0f×%.0f — must span at least ±reachableRadius (%.0f) on X/Z")
			:format(catchFloor.size.X, catchFloor.size.Z, plan.reachableRadius))
	local top = catchFloor.pos.Y + catchFloor.size.Y / 2
	H.approx(top, plan.catchFloorY, 0.01, ("CatchFloor's top face is at Y=%.2f, must equal plan.catchFloorY=%.2f"):format(top, plan.catchFloorY))
end)

--------------------------------------------------------------------------------
-- 5. COPLANARITY — V0's surviving idea: no two overlapping Parts may share a top-face Y (terrain
-- itself cannot z-fight, but any Part can). With only the CatchFloor part today there is no overlapping
-- pair to check, but the loop stays live for whenever a second Part is added.
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

H.test("contract: plan is deterministic — identical heightAt + water + parts + M1.5 content across two calls", function()
	local a = WorldGen.plan(GameConfig)
	local b = WorldGen.plan(GameConfig)
	-- heightAt: identical over a spread of samples (incl. the foothill/falloff band).
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
	-- M1.5 content is DATA in plan(); the new gates would be meaningless if any of it drifted.
	H.eq(#a.sculptOps, #b.sculptOps, "sculptOps count drifted between calls")
	H.eq(a.fillOpCount, b.fillOpCount, "fillOpCount drifted between calls")
	H.eq(#a.paintZones, #b.paintZones, "paintZones count drifted between calls")
	H.eq(#a.foothills, #b.foothills, "foothill count drifted between calls")
	H.eq(#a.relief.mounds, #b.relief.mounds, "relief mound count drifted between calls")
	H.eq(#a.relief.outcrops, #b.relief.outcrops, "relief outcrop count drifted between calls")
	H.eq(#a.river.points, #b.river.points, "river polyline drifted between calls")
	-- a representative sculpt-op, foothill crest, and mountain op are byte-identical.
	H.eq(a.sculptOps[1].mat, b.sculptOps[1].mat, "sculptOps[1].mat drifted")
	H.eq(a.foothills[1].crest, b.foothills[1].crest, "foothill crest drifted between calls")
	-- §2 bar packet: the distant mountains are sculpted TERRAIN ops (feature="mountain"), not Parts, so
	-- the determinism pin reads the first such op instead of the first non-CatchFloor plan.parts entry.
	local function firstMountainOp(sculptOps)
		for _, o in ipairs(sculptOps) do
			if o.feature == "mountain" then return o end
		end
		return nil
	end
	local aMtn, bMtn = firstMountainOp(a.sculptOps), firstMountainOp(b.sculptOps)
	H.ok(aMtn ~= nil and bMtn ~= nil, "expected at least one feature==\"mountain\" op in plan.sculptOps")
	H.eq(aMtn.mat, bMtn.mat, "first mountain op's mat drifted between calls")
	H.eq(aMtn.y, bMtn.y, "first mountain op's y drifted between calls")
	local aExtent = aMtn.rad or aMtn.sy
	local bExtent = bMtn.rad or bMtn.sy
	H.eq(aExtent, bExtent, "first mountain op's rad/sy drifted between calls")
	H.eq(a.paintZones[1].mat, b.paintZones[1].mat, "paintZones[1].mat drifted between calls")
end)

H.test("contract: the kill switch exists (honest flag)", function()
	H.ok(GameConfig.Map ~= nil, "GameConfig.Map is missing")
	H.ok(GameConfig.Map.worldV2 ~= nil,
		"GameConfig.Map.worldV2 is nil — the kill switch must exist so flag-off restores the legacy path")
end)

--------------------------------------------------------------------------------
-- 7. FOOTHILL-VARIATION (open-horizon packet) — the surround is a BROKEN ring of low hills, not a
-- wall: distinct crest heights, a real tall/short contrast, every crest well under wall height, and at
-- least one hill forced near-zero as a sightline gap. Materials fold the old "consistently Rock" check
-- into a Grass/Ground pin (the foothills' declared material set).
--------------------------------------------------------------------------------
H.test("foothill-variation: ≥6 distinct crest heights, a ≥2.5 tall/short ratio, every crest <400, ≥1 gap hill", function()
	local plan = WorldGen.plan(GameConfig)
	local hills = plan.foothills
	H.ok(hills and #hills > 0, "plan.foothills is empty — the foothill gate would be vacuous")
	local distinct, nDistinct = {}, 0
	local tallLo, tallHi = math.huge, -math.huge -- tall/short ratio over the NON-gap population only
	local sawGap = false
	for _, h in ipairs(hills) do
		H.finite(h.crest, "a foothill has a non-finite crest height")
		H.ok(h.crest < 400, ("foothill at az=%.0f crests at Y=%.0f (>=400) — that reads as a wall, not a broken hill ring"):format(h.ad, h.crest))
		local bucket = math.floor(h.crest / 20 + 0.5)
		if not distinct[bucket] then distinct[bucket] = true; nDistinct += 1 end
		if h.gap then
			sawGap = true
			H.ok(h.crest < 50, ("gap hill at az=%.0f crests at Y=%.0f — expected near-zero (<50)"):format(h.ad, h.crest))
		else
			tallLo = math.min(tallLo, h.crest); tallHi = math.max(tallHi, h.crest)
		end
	end
	H.ok(nDistinct >= 6, ("the foothill ring has only %d distinct crest heights (<6) — it reads as uniform"):format(nDistinct))
	H.ok(tallHi / tallLo >= 2.5, ("foothill tall/short ratio is %.2f (<2.5) — no silhouette variation"):format(tallHi / tallLo))
	H.ok(sawGap, "expected at least one foothill forced near-zero as a sightline gap")
end)

H.test("foothill restyle: hills read Grass/Ground (folds the old 'consistently Rock' rim check)", function()
	local plan = WorldGen.plan(GameConfig)
	for _, h in ipairs(plan.foothills) do
		H.ok(h.mat == "Grass" or h.mat == "Ground",
			("foothill at az=%.0f is material %q, expected Grass or Ground"):format(h.ad, tostring(h.mat)))
	end
end)

H.test("distant mountains: sculpted backdrop clusters exist with a sky gap and snow-capped far peaks", function()
	local plan = WorldGen.plan(GameConfig)
	-- §2 bar packet: the backdrop is now sculpted TERRAIN (feature="mountain" sculptOps), not Parts —
	-- the old WedgePart-based gate (parts minus CatchFloor) is replaced by filtering sculptOps directly.
	local mtnOps = {}
	for _, o in ipairs(plan.sculptOps) do
		if o.feature == "mountain" then mtnOps[#mtnOps + 1] = o end
	end
	H.ok(#mtnOps >= 150, ("only %d mountain sculpt ops (<150) — the backdrop would read sparse"):format(#mtnOps))
	local sawSnow, sawFar = false, false
	for _, o in ipairs(mtnOps) do
		H.ok(o.mat == "Rock" or o.mat == "Snow", ("mountain op mat %q, expected Rock or Snow"):format(tostring(o.mat)))
		local r = math.sqrt(o.x * o.x + o.z * o.z)
		H.between(r, 5500, 9500, ("mountain op is at r=%.0f, outside the declared 5500-9500 backdrop band"):format(r))
		if o.mat == "Snow" then sawSnow = true end
		if r > 7000 then sawFar = true end
	end
	H.ok(sawSnow, "expected at least one snow-capped tall far peak")
	H.ok(sawFar, "expected at least one far-range mountain cluster (r>7000)")
	-- ≥1 empty azimuth arc ≥30° wide (sky gap): same longest-run-over-sorted-azimuths algorithm as the
	-- old Part-based gate, now swept over mountain op positions.
	local azList = {}
	for _, o in ipairs(mtnOps) do
		azList[#azList + 1] = math.deg(math.atan2(o.z, o.x)) % 360
	end
	table.sort(azList)
	local longestGap = 0
	for i = 1, #azList do
		local a, b = azList[i], azList[(i % #azList) + 1]
		local gap = (i == #azList) and (b + 360 - a) or (b - a)
		longestGap = math.max(longestGap, gap)
	end
	H.ok(longestGap >= 30, ("longest empty azimuth arc between mountain clusters is %.0f° (<30°) — no real sky gap"):format(longestGap))
end)

H.test("foothill toe blend: a Grass/LeafyGrass band exists so the hills grow out of the meadow", function()
	local plan = WorldGen.plan(GameConfig)
	local toe = plan.foothillToe
	H.ok(toe and #toe > 0, "plan.foothillToe is empty — no meadow-blend band at the foothill base")
	for _, t in ipairs(toe) do
		H.ok(t.mat == "Grass" or t.mat == "LeafyGrass",
			("foothill-toe fill at (%.0f,%.0f) is material %q, expected Grass/LeafyGrass"):format(t.x, t.z, tostring(t.mat)))
		H.between(t.sz, 80, 150, ("foothill-toe radial extent %.0f is outside the declared 80-150 stud rise band"):format(t.sz))
	end
end)

--------------------------------------------------------------------------------
-- 8. RIVER / POOL CLEARANCE (M1.5) — the water threading the datum must never reach a load-bearing
-- site (a grove/pad/spawn sample in the river or pool is an unearned bath), and every carve floors
-- above the conservative line with a shallow (≤8) depth.
--------------------------------------------------------------------------------
local function pointSegDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local L2 = dx * dx + dz * dz
	if L2 < 1e-9 then return math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2) end
	local t = math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / L2))
	return math.sqrt((px - (ax + t * dx)) ^ 2 + (pz - (az + t * dz)) ^ 2)
end

H.test("river/pool clearance: every datum sample stays clear of every river segment and water carve", function()
	local plan = WorldGen.plan(GameConfig)
	local riv, pool, lake = plan.river, plan.river.pool, plan.lakeCarve
	local segMargin = riv.halfWidth + 40
	for _, s in ipairs(plan.datumSamples) do
		-- (a) river segments — point-to-segment ≥ halfWidth+40.
		for i = 1, #riv.points - 1 do
			local a, b = riv.points[i], riv.points[i + 1]
			local d = pointSegDist(s.x, s.z, a[1], a[2], b[1], b[2])
			H.ok(d >= segMargin,
				("%s (%.0f,%.0f) is %.0f from river segment %d (need ≥%d) — the river would flood it"):format(s.label, s.x, s.z, d, i, segMargin))
		end
		-- (b) circular carves (pool + lake cylinders) — centre distance ≥ radius+40.
		for _, group in ipairs({ pool.cyls, lake.cyls }) do
			for _, c in ipairs(group) do
				local d = math.sqrt((s.x - c.x) ^ 2 + (s.z - c.z) ^ 2)
				H.ok(d >= c.r + 40,
					("%s (%.0f,%.0f) is %.0f from a water carve at (%.0f,%.0f) r%d (need ≥%d)"):format(s.label, s.x, s.z, d, c.x, c.z, c.r, c.r + 40))
			end
		end
	end
	-- (c) floors above -40, depth ≤ 8.
	for _, w in ipairs({ { n = "river", f = riv.floorY, s = riv.surfaceY }, { n = "pool", f = pool.floorY, s = pool.surfaceY }, { n = "lake", f = lake.floorY, s = lake.surfaceY } }) do
		H.ok(w.f > -40, ("%s floors at Y=%.0f — must be > -40"):format(w.n, w.f))
		H.ok(w.s - w.f <= 8, ("%s depth %.0f exceeds 8"):format(w.n, w.s - w.f))
		H.ok(w.s > w.f, ("%s surface must sit above its floor"):format(w.n))
	end
end)

--------------------------------------------------------------------------------
-- 9. RELIEF SAFETY (M1.5) — the playable floor stays MICRO (invariant ①). Mounds ≤6 studs; outcrops
-- (the only exception inside the playable band) live in the r1700-3000 arcs and ≥120 from every datum.
--------------------------------------------------------------------------------
H.test("relief safety: mounds are micro (≤6) and outcrops sit in the r1700-3000 arc ≥120 from every datum", function()
	local plan = WorldGen.plan(GameConfig)
	local rel = plan.relief
	H.ok(rel and #rel.mounds > 0 and #rel.outcrops > 0, "relief tables are empty — the gate would be vacuous")
	for _, m in ipairs(rel.mounds) do
		H.ok(m.protrude <= 6, ("mound at (%.0f,%.0f) protrudes %.2f (>6) — that is macro relief on the datum floor"):format(m.x, m.z, m.protrude))
	end
	for _, o in ipairs(rel.outcrops) do
		local r = math.sqrt(o.x * o.x + o.z * o.z)
		H.between(r, 1700, 3000, ("outcrop at (%.0f,%.0f) is at r=%.0f, outside the declared r1700-3000 arc"):format(o.x, o.z, r))
		local nearest = math.huge
		for _, s in ipairs(plan.datumSamples) do
			nearest = math.min(nearest, math.sqrt((o.x - s.x) ^ 2 + (o.z - s.z) ^ 2))
		end
		H.ok(nearest >= 120, ("outcrop at (%.0f,%.0f) is only %.0f from a datum sample (need ≥120)"):format(o.x, o.z, nearest))
	end
end)

--------------------------------------------------------------------------------
-- 10. CLOSURE-CUE COVERAGE (M1.5, extended M3) — the deleted uniform LeafyGrass disc is replaced by an
-- ORGANIC patchwork (M3: FillCylinder patches, not the checkerboard FillBlock grid) with genuine
-- material variety at every scale, no single material dominating, and (new) real radius/coverage/
-- clustering invariants pinning the new organic-patch shape so it can't silently regress back toward
-- either the uniform-plane bug or the rigid grid.
--------------------------------------------------------------------------------
H.test("closure-cue coverage: the paint patchwork is varied (≥3 mats <r1500, ≥4 <r2600) and unclustered", function()
	local plan = WorldGen.plan(GameConfig)
	local cells = plan.paintZones
	H.ok(#cells > 0, "paintZones is empty — the map would be a uniform plane again (the S45 bug)")
	local function distinct(maxR)
		local set, n = {}, 0
		for _, c in ipairs(cells) do
			if math.sqrt(c.x * c.x + c.z * c.z) < maxR then
				if not set[c.mat] then set[c.mat] = true; n += 1 end
			end
		end
		return n
	end
	H.ok(distinct(1500) >= 3, ("only %d distinct paint materials within r<1500 (need ≥3)"):format(distinct(1500)))
	H.ok(distinct(2600) >= 4, ("only %d distinct paint materials within r<2600 (need ≥4)"):format(distinct(2600)))
	local counts = {}
	for _, c in ipairs(cells) do counts[c.mat] = (counts[c.mat] or 0) + 1 end
	for mat, n in pairs(counts) do
		H.ok(n / #cells <= 0.60, ("material %s is %.0f%% of cells (>60%%) — a near-uniform plane"):format(mat, 100 * n / #cells))
	end
end)

H.test("organic meadow (M3): patches are organic (≥N, radius 50-180, no straight-edge grid) with real coverage", function()
	local plan = WorldGen.plan(GameConfig)
	local cells = plan.paintZones
	H.ok(#cells >= 150, ("only %d paint patches (<150) — the organic meadow needs real density to read as a patchwork"):format(#cells))
	local totalArea = 0
	for _, c in ipairs(cells) do
		H.ok(c.r ~= nil, "a paint patch is missing its radius — M3 organic patches must carry r")
		H.between(c.r, 50, 180, ("patch at (%.0f,%.0f) has radius %.1f, outside the declared 50-180 organic-patch range"):format(c.x, c.z, c.r))
		totalArea += math.pi * c.r * c.r
	end
	-- Coverage FRACTION (not a cell-count pin, since overlap makes exact footprint unmeasurable here):
	-- the summed patch area relative to the painted disc (r<2600) should land in a "real patchwork, not
	-- sparse specks and not a solid blanket" band. This replaces any exact-count assumption from the
	-- old grid so the density can keep being tuned by look-dev without re-deriving a cell count.
	local discArea = math.pi * 2600 * 2600
	local coverageFrac = totalArea / discArea
	H.between(coverageFrac, 0.25, 1.5,
		("paint coverage fraction %.2f is outside the [0.25, 1.5] band (0=nothing painted, 1.0=disc-area-equivalent counting overlap)")
			:format(coverageFrac))
end)

H.test("organic meadow (M3): like materials cluster — some adjacent patches (<250 studs) share a material", function()
	local plan = WorldGen.plan(GameConfig)
	local cells = plan.paintZones
	local clusteredPairs = 0
	for i = 1, #cells do
		for j = i + 1, #cells do
			local a, b = cells[i], cells[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
			if d < 250 and a.mat == b.mat then clusteredPairs += 1 end
		end
	end
	H.ok(clusteredPairs >= 20,
		("only %d nearby (<250 studs) same-material patch pairs — the meadow should read as clustered patches, not an alternating checkerboard")
			:format(clusteredPairs))
end)

H.test("organic meadow (M3): scatterPlan-style determinism — WorldGen.plan's paint patchwork is byte-identical across calls", function()
	local a = WorldGen.plan(GameConfig).paintZones
	local b = WorldGen.plan(GameConfig).paintZones
	H.eq(#a, #b, "paint patch count drifted between calls — buildPaint must be pure (no math.random)")
	for i = 1, #a do
		H.eq(a[i].mat, b[i].mat, ("paintZones[%d].mat drifted between calls"):format(i))
		H.approx(a[i].x, b[i].x, 1e-9, ("paintZones[%d].x drifted between calls"):format(i))
		H.approx(a[i].z, b[i].z, 1e-9, ("paintZones[%d].z drifted between calls"):format(i))
		H.approx(a[i].r, b[i].r, 1e-9, ("paintZones[%d].r drifted between calls"):format(i))
	end
end)

--------------------------------------------------------------------------------
-- 11. FILL BUDGET (M1.5) — the sculptOps list is the whole world's fill cost; keep it bounded and
-- honestly recorded (fillOpCount must equal the list it claims to count).
--------------------------------------------------------------------------------
H.test("fill budget: total sculpt fill ops ≤1100 (recorded)", function()
	local plan = WorldGen.plan(GameConfig)
	H.eq(plan.fillOpCount, #plan.sculptOps, "plan.fillOpCount does not match #plan.sculptOps — the recorded budget is a lie")
	print(("        [fill-budget] WorldGen sculpts %d terrain fill ops"):format(#plan.sculptOps))
	-- Cap raised 1000→1400 (M1.5 VOLUME hotfix), then 1400→1800 (M3 look-dev round), then tightened
	-- 1800→1100 (rim-shell packet). Open-horizon packet: the rim wall (88 shelled blocks + snow/talus/
	-- foot bands + a 4-slab apron) is GONE, replaced by a much cheaper broken foothill ring + a thin
	-- falloff collar + zero-terrain-cost distant mountain Parts — count dropped to roughly ~330 ops.
	-- 1100 stays the recorded ceiling (comfortable headroom, no need to re-tighten it this packet) and
	-- is still comfortably under the HARD GATE ceiling of 2600 ops; still a one-time BOOT cost (sculpt
	-- runs once), amortized by the time-budget yield, not a per-frame cost.
	H.ok(#plan.sculptOps <= 1100, ("WorldGen sculpts %d fill ops (>1100) — the terrain build is over budget"):format(#plan.sculptOps))
	H.ok(#plan.sculptOps <= 2600, ("WorldGen sculpts %d fill ops (>2600) — exceeds the project HARD GATE ceiling"):format(#plan.sculptOps))
end)

--------------------------------------------------------------------------------
-- 11b. SCULPT VOLUME BUDGET — the open-horizon packet pinned the pre-mountain-terrain B-op volume; the
-- §2 bar packet adds real sculpted mountain terrain (feature="mountain" ops, B+W+L), so the budget is
-- now two gates: (a) the mountain-volume gate alone, pinning the new content's cost directly (target
-- ~2.8-3.0e10 studs³, ceiling trimmed from a naive ≈3.5e10 via MOUNTAIN_BASE_FRAC/BODY_N/H_MAX — see
-- WorldGen's buildMountainRange comment); (b) a whole-world, all-op-type total so a regression anywhere
-- (mountains OR the pre-existing floor/foothill/collar/water content) still trips something. Volume per
-- op type mirrors the fill extent+volume gate below: B/W = sx*sy*sz, C = pi*rad^2*h, L = (4/3)*pi*rad^3.
--------------------------------------------------------------------------------
local function opVolume(o)
	if o.op == "B" or o.op == "W" then
		return o.sx * o.sy * o.sz
	elseif o.op == "C" then
		return math.pi * o.rad * o.rad * o.h
	elseif o.op == "L" then
		return (4 / 3) * math.pi * o.rad ^ 3
	end
	return 0
end

H.test("sculpt volume: mountain-op volume lands in the §2 bar-packet budget band", function()
	local plan = WorldGen.plan(GameConfig)
	local mtnVol, worldVol = 0, 0
	for _, o in ipairs(plan.sculptOps) do
		local v = opVolume(o)
		worldVol = worldVol + v
		if o.feature == "mountain" then mtnVol = mtnVol + v end
	end
	print(("        [sculpt-volume] mountain op volume = %.3e studs^3, world total = %.3e studs^3"):format(mtnVol, worldVol))
	H.ok(mtnVol >= 2.4e10, ("mountain-op volume %.3e is below the §2 bar-packet floor (2.4e10) — the mountains may have shrunk/vanished"):format(mtnVol))
	H.ok(mtnVol <= 3.6e10, ("mountain-op volume %.3e is above the §2 bar-packet ceiling (3.6e10) — apply the budget trims (base fraction/body-ball count/height ceiling)"):format(mtnVol))
	H.ok(worldVol >= 1.8e10, ("world sculpt-op volume %.3e is implausibly low (<1.8e10) — the world may be missing terrain"):format(worldVol))
	H.ok(worldVol <= 4.2e10, ("world sculpt-op volume %.3e (>4.2e10) — over the whole-world sculpt-volume budget"):format(worldVol))
end)

--------------------------------------------------------------------------------
-- 12. FILL EXTENT + VOLUME (M1.5 hotfix) — the bug lune couldn't see, twice over. Roblox Terrain fills
-- throw "Extents are too large" past ~4096 studs on ANY axis, AND past a region-VOLUME limit even when
-- every axis is individually small — only the real-engine M2 capture caught either class on boot (10
-- rotated rim-PEAK blocks, dims sx=sz≈1231.5 sy=1593-2044, every axis under 4000 but sx*sy*sz≈2.4-3.1e9
-- studs³). The ORIGINAL version of this gate only checked per-axis extent, which is exactly why it
-- MISSED the volume bug — it is extended here to also assert volume, so a future oversized fill (rotated
-- or not) can never regress past the assembler's tiler again.
--
-- S50 audit FIX 3: assembleOps' W()/C()/L() builders now error() at PLAN TIME on these same bounds
-- (B() already self-tiled) — closing the bypass where only B was gated. This loop is the regression
-- net over every op type, and now also checks the Y-axis extent (ey) for B/W, which the original only
-- checked on X/Z.
--------------------------------------------------------------------------------
H.test("fill extent+volume: no sculpt op exceeds the Terrain per-axis OR region-volume fill limit", function()
	local plan = WorldGen.plan(GameConfig)
	local MAX = plan.maxFillExtent
	local MAXV = plan.maxFillVolume
	H.ok(MAX and MAX <= 4096, ("maxFillExtent=%s must exist and stay under Roblox's ~4096 limit"):format(tostring(MAX)))
	H.ok(MAXV and MAXV <= 3.84e8, ("maxFillVolume=%s must exist and stay under the proven-passing 3.84e8 bound"):format(tostring(MAXV)))
	for i, o in ipairs(plan.sculptOps) do
		local ex, ey, ez, vol
		if o.op == "B" or o.op == "W" then
			ex, ey, ez = o.sx, o.sy, o.sz
			vol = o.sx * o.sy * o.sz
		elseif o.op == "C" then
			ex, ey, ez = o.rad * 2, o.h, o.rad * 2
			vol = math.pi * o.rad * o.rad * o.h
		elseif o.op == "L" then
			ex, ey, ez = o.rad * 2, o.rad * 2, o.rad * 2
			vol = (4 / 3) * math.pi * o.rad ^ 3
		end
		H.ok(ex ~= nil, ("sculptOps[%d] has op %q with no known extents"):format(i, tostring(o.op)))
		H.ok(ex <= MAX and ey <= MAX and ez <= MAX,
			("sculptOps[%d] (op %q, mat %s) is %.0f×%.0f×%.0f — exceeds the %d per-axis Terrain fill limit ('Extents are too large')")
				:format(i, tostring(o.op), tostring(o.mat), ex, ey, ez, MAX))
		H.ok(vol <= MAXV,
			("sculptOps[%d] (op %q, mat %s) is %.0f studs³ — exceeds the %.0f region-volume Terrain fill limit ('Extents are too large')")
				:format(i, tostring(o.op), tostring(o.mat), vol, MAXV))
	end
end)

H.test("fill volume regression: zero B ops exceed MAX_FILL_VOLUME (the rim-PEAK bug, explicitly)", function()
	local plan = WorldGen.plan(GameConfig)
	local MAXV = plan.maxFillVolume
	local overCount, maxVol = 0, 0
	for _, o in ipairs(plan.sculptOps) do
		if o.op == "B" then
			local vol = o.sx * o.sy * o.sz
			if vol > maxVol then maxVol = vol end
			if vol > MAXV then overCount = overCount + 1 end
		end
	end
	H.eq(overCount, 0, ("%d FillBlock op(s) still exceed MAX_FILL_VOLUME=%.0f (max seen %.0f) — the rim-PEAK tiler regressed"):format(overCount, MAXV, maxVol))
end)

--------------------------------------------------------------------------------
-- 13. SCATTER (M4-B) — WorldGen.scatterPlan bounds: inside the valley, clear of every exclusion zone,
-- y sampled from heightAt, within budget, and deterministic for a fixed seed.
--------------------------------------------------------------------------------
local SCATTER_VALLEY_R = 3400 -- FLAT_R; every scatter point (rim-base ring included) stays inside it
local SCATTER_BUDGET = 140

H.test("scatter: every point sits inside the valley radius, with y sampled from heightAt", function()
	local plan = WorldGen.plan(GameConfig)
	H.ok(#plan.scatter > 0, "plan.scatter is empty — the scatter gate would be vacuous")
	for _, p in ipairs(plan.scatter) do
		local r = math.sqrt(p.x * p.x + p.z * p.z)
		H.ok(r <= SCATTER_VALLEY_R,
			("%s at (%.0f,%.0f) is at r=%.0f, outside the %d valley radius"):format(p.role, p.x, p.z, r, SCATTER_VALLEY_R))
		H.eq(p.y, plan.heightAt(p.x, p.z), ("%s at (%.0f,%.0f): y must equal heightAt(x,z)"):format(p.role, p.x, p.z))
		H.ok(p.role == "rock" or p.role == "bush" or p.role == "log",
			("unexpected scatter role %q — MeshFactory role mapping only covers rock/bush/log"):format(tostring(p.role)))
	end
end)

H.test("scatter: no point falls inside the spawn core, the pad approach, or any water carve", function()
	local plan = WorldGen.plan(GameConfig)
	local coreHalf = GameConfig.Map.coreHalfExtent or 1200
	local d = GameConfig.Rescue.deliverPos
	local padR = GameConfig.Rescue.padClearRadius or 400
	for _, p in ipairs(plan.scatter) do
		H.ok(not (math.abs(p.x) <= coreHalf and math.abs(p.z) <= coreHalf),
			("%s at (%.0f,%.0f) sits inside the ±%d spawn core"):format(p.role, p.x, p.z, coreHalf))
		local pd = math.sqrt((p.x - d.X) ^ 2 + (p.z - d.Z) ^ 2)
		H.ok(pd >= padR, ("%s at (%.0f,%.0f) is %.0f from the delivery pad (need >= %d)"):format(p.role, p.x, p.z, pd, padR))
		for _, c in ipairs(plan.lakeCarve.cyls) do
			local wd = math.sqrt((p.x - c.x) ^ 2 + (p.z - c.z) ^ 2)
			H.ok(wd >= c.r, ("%s at (%.0f,%.0f) is inside the lake carve at (%.0f,%.0f)"):format(p.role, p.x, p.z, c.x, c.z))
		end
		for _, c in ipairs(plan.river.pool.cyls) do
			local wd = math.sqrt((p.x - c.x) ^ 2 + (p.z - c.z) ^ 2)
			H.ok(wd >= c.r, ("%s at (%.0f,%.0f) is inside the pool carve at (%.0f,%.0f)"):format(p.role, p.x, p.z, c.x, c.z))
		end
		for i = 1, #plan.river.points - 1 do
			local a, b = plan.river.points[i], plan.river.points[i + 1]
			local wd = pointSegDist(p.x, p.z, a[1], a[2], b[1], b[2])
			H.ok(wd >= plan.river.halfWidth,
				("%s at (%.0f,%.0f) is %.0f from river segment %d — inside the river channel"):format(p.role, p.x, p.z, wd, i))
		end
	end
end)

H.test("scatter: total count stays within the M4-B budget (<= 140)", function()
	local plan = WorldGen.plan(GameConfig)
	H.ok(#plan.scatter <= SCATTER_BUDGET, ("scatter has %d points (>%d budget)"):format(#plan.scatter, SCATTER_BUDGET))
end)

H.test("scatter: deterministic for a fixed seed", function()
	local a = WorldGen.scatterPlan(GameConfig, 42)
	local b = WorldGen.scatterPlan(GameConfig, 42)
	H.eq(#a, #b, "scatter point count drifted between calls with the same seed")
	for i = 1, #a do
		H.eq(a[i].role, b[i].role, ("scatter[%d].role drifted"):format(i))
		H.approx(a[i].x, b[i].x, 1e-9, ("scatter[%d].x drifted"):format(i))
		H.approx(a[i].z, b[i].z, 1e-9, ("scatter[%d].z drifted"):format(i))
		H.approx(a[i].rotY, b[i].rotY, 1e-9, ("scatter[%d].rotY drifted"):format(i))
	end
	-- a different seed must (almost certainly) produce a different layout — proves seed is load-bearing.
	local c = WorldGen.scatterPlan(GameConfig, 43)
	local anyDiff = (#a ~= #c)
	if not anyDiff then
		for i = 1, #a do
			if math.abs(a[i].x - c[i].x) > 1e-6 or math.abs(a[i].z - c[i].z) > 1e-6 then anyDiff = true; break end
		end
	end
	H.ok(anyDiff, "changing the seed produced an identical scatter layout — seed is not load-bearing")
end)

H.test("scatter readability (M3): rim-ring rocks carry a bigger sizeMul than shore/meadow rocks", function()
	local plan = WorldGen.plan(GameConfig)
	local sawBigRock, sawDefaultMul = false, false
	for _, p in ipairs(plan.scatter) do
		H.ok(p.sizeMul ~= nil and p.sizeMul > 0, ("%s at (%.0f,%.0f) is missing a positive sizeMul"):format(p.role, p.x, p.z))
		local r = math.sqrt(p.x * p.x + p.z * p.z)
		if p.role == "rock" and r > 3000 then
			sawBigRock = sawBigRock or p.sizeMul > 1.0
		end
		if p.role ~= "rock" then
			sawDefaultMul = sawDefaultMul or p.sizeMul == 1.0
		end
	end
	H.ok(sawBigRock, "no rim-ring rock (r>3000) carries sizeMul > 1.0 — rim rocks should read bigger than shore/meadow rocks")
	H.ok(sawDefaultMul, "expected bushes/logs to carry the default sizeMul=1.0")
end)

H.test("scatter: the kill switch exists (honest flag)", function()
	H.ok(GameConfig.Map.meshScatter ~= nil, "GameConfig.Map.meshScatter is nil — the kill switch must exist")
	H.ok(GameConfig.Map.meshTrees ~= nil, "GameConfig.Map.meshTrees is nil — the kill switch must exist")
	H.ok(GameConfig.Map.meshSky ~= nil, "GameConfig.Map.meshSky is nil — the kill switch must exist")
end)

--------------------------------------------------------------------------------
-- 14. SOURCE-GATE (M4-B) — plantTree/buildTree still mint parts named "Canopy" and "Trunk", and the
-- meshTrees path sets Transparency = 1 rather than deleting/renaming the contract parts. Grep-style,
-- like the P3 catch-floor gate above — this pins RescueServer.server.luau's SHAPE, not its behavior
-- (Lune cannot run a script that touches Workspace/Players).
--------------------------------------------------------------------------------
H.test("source-gate: RescueServer's buildTree still mints \"Trunk\"/\"Canopy\" parts", function()
	local src = require("@lune/fs").readFile("src/server/RescueServer.server.luau")
	H.ok(src:find('uprightCylinder%("Trunk"') ~= nil, "buildTree must still mint a part named \"Trunk\"")
	H.ok(src:find('anchoredPart%("Canopy"') ~= nil, "buildTree must still mint parts named \"Canopy\"")
end)

H.test("source-gate: the meshTrees path sets Transparency=1 rather than deleting the contract parts", function()
	local src = require("@lune/fs").readFile("src/server/RescueServer.server.luau")
	H.ok(src:find("meshTrees") ~= nil, "buildTree must read a meshTrees flag")
	-- trunk.Transparency = 1 and blob.Transparency = 1 must both appear; neither Trunk nor Canopy may
	-- ever be :Destroy()'d by the mesh-swap path.
	H.ok(src:find("trunk%.Transparency%s*=%s*1") ~= nil, "the meshTrees path must set trunk.Transparency = 1")
	H.ok(src:find("blob%.Transparency%s*=%s*1") ~= nil, "the meshTrees path must set blob.Transparency = 1")
	H.ok(src:find("trunk:Destroy%(%)") == nil, "the mesh-swap path must NEVER destroy the trunk contract part")
	H.ok(src:find("blob:Destroy%(%)") == nil, "the mesh-swap path must NEVER destroy a Canopy contract part")
end)

H.test("source-gate: every MeshFactory.build call site sets Anchored/CanCollide/CanQuery/CanTouch/CastShadow=false", function()
	local src = require("@lune/fs").readFile("src/shared/MeshFactory.luau")
	for _, flag in ipairs({ "Anchored = true", "CanCollide = false", "CanQuery = false", "CanTouch = false", "CastShadow = false" }) do
		H.ok(src:find(flag, 1, true) ~= nil, ("MeshFactory.build must set %s on every part it creates"):format(flag))
	end
end)

--------------------------------------------------------------------------------
-- M4-V review fix #1 (rng-stream isolation): the mesh-visual pine/variant picks in buildTree must
-- draw from a dedicated position-derived meshRng, NEVER the shared round `rng` — a shared-rng draw
-- there would shift every later rng:Next* call, making trunk/canopy/perch layout and CanopyCount
-- diverge flag-on vs flag-off for Map.meshTrees. Pin the SHAPE: extract the mesh-swap block and
-- assert it contains no draw on the shared `rng` (case-sensitive: "meshRng:" does not match "rng:").
--------------------------------------------------------------------------------
H.test("source-gate: the meshTrees mesh-pick path never draws from the shared round rng", function()
	local src = require("@lune/fs").readFile("src/server/RescueServer.server.luau")
	local startI = src:find("trunk%.Transparency%s*=%s*1")
	local endI = src:find("MeshFactory%.build%(variant", startI)
	H.ok(startI ~= nil and endI ~= nil, "expected the meshTrees mesh-swap block (trunk.Transparency=1 .. MeshFactory.build) to be present")
	local block = src:sub(startI, endI)
	H.ok(block:find("rng:") == nil, "the mesh-visual pick block must not draw from the shared round `rng` — use a position-derived meshRng instead")
	H.ok(block:find("meshRng") ~= nil, "the mesh-visual pick block must use a dedicated meshRng derived from the tree position")
end)

--------------------------------------------------------------------------------
-- M4-V review fix #2 (boot-yield hardening, S49 crash class): each planted tree can mint up to ~10
-- mesh parts, so an un-yielded loop across the grove+backdrop tree budget is the same script-timeout
-- shape that crashed WorldGen's 554-fill terrain sculpt (docs: reference-worldgen-p3-catch-floor).
-- Pin that the planting loops yield periodically, mirroring WorldGen's every-24-ops rule.
--------------------------------------------------------------------------------
H.test("source-gate: the grove/backdrop tree-planting loops yield periodically (S49 boot-crash class)", function()
	local src = require("@lune/fs").readFile("src/server/RescueServer.server.luau")
	H.ok(src:find("task%.wait%(%)") ~= nil, "the tree-planting loops must call task.wait() periodically to avoid a script-timeout boot crash")
	H.ok(src:find("%% 8 == 0") ~= nil, "the yield must trigger on a fixed cadence (every 8 trees, mirroring WorldGen's every-N-ops rule)")
end)
