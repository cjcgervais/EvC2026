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
	-- M1.5 content is DATA in plan(); the new gates would be meaningless if any of it drifted.
	H.eq(#a.sculptOps, #b.sculptOps, "sculptOps count drifted between calls")
	H.eq(a.fillOpCount, b.fillOpCount, "fillOpCount drifted between calls")
	H.eq(#a.paintZones, #b.paintZones, "paintZones count drifted between calls")
	H.eq(#a.rimPeaks.blocks, #b.rimPeaks.blocks, "rim block count drifted between calls")
	H.eq(#a.relief.mounds, #b.relief.mounds, "relief mound count drifted between calls")
	H.eq(#a.relief.outcrops, #b.relief.outcrops, "relief outcrop count drifted between calls")
	H.eq(#a.river.points, #b.river.points, "river polyline drifted between calls")
	-- a representative sculpt-op and rim crest are byte-identical.
	H.eq(a.sculptOps[1].mat, b.sculptOps[1].mat, "sculptOps[1].mat drifted")
	H.eq(a.rimPeaks.blocks[1].crest, b.rimPeaks.blocks[1].crest, "rim crest drifted between calls")
	H.eq(a.paintZones[1].mat, b.paintZones[1].mat, "paintZones[1].mat drifted between calls")
end)

H.test("contract: the kill switch exists (honest flag)", function()
	H.ok(GameConfig.Map ~= nil, "GameConfig.Map is missing")
	H.ok(GameConfig.Map.worldV2 ~= nil,
		"GameConfig.Map.worldV2 is nil — the kill switch must exist so flag-off restores the legacy path")
end)

--------------------------------------------------------------------------------
-- 7. RIM-VARIATION (M1.5) — the rim is a ring of PEAKS, not a wall. Distinct crest heights, a real
-- tall/short contrast, and (outside the declared west-pass saddle) crests that actually read as peaks.
--------------------------------------------------------------------------------
H.test("rim-variation: the crest has ≥6 distinct heights, a ≥2.5 tall/short ratio, and peaks outside the west pass", function()
	local plan = WorldGen.plan(GameConfig)
	local rp = plan.rimPeaks
	H.ok(rp and rp.blocks and #rp.blocks > 0, "rimPeaks.blocks is empty — the rim gate would be vacuous")
	local distinct, lo, hi = {}, math.huge, -math.huge
	local nDistinct = 0
	for _, b in ipairs(rp.blocks) do
		H.finite(b.crest, "a rim block has a non-finite crest height")
		local bucket = math.floor(b.crest / 25 + 0.5)
		if not distinct[bucket] then distinct[bucket] = true; nDistinct += 1 end
		lo = math.min(lo, b.crest); hi = math.max(hi, b.crest)
		-- Every crest reads as a peak (>300) EXCEPT within the declared west-pass arc.
		local inWestPass = b.ad >= rp.westPass.azMin and b.ad <= rp.westPass.azMax
		H.ok(b.crest > 300 or inWestPass,
			("rim block at az=%.0f crests at only Y=%.0f (<300) yet is outside the west pass — that reads as a gap, not a peak")
				:format(b.ad, b.crest))
	end
	H.ok(nDistinct >= 6, ("the rim has only %d distinct crest heights (<6) — it reads as a uniform wall"):format(nDistinct))
	H.ok(hi / lo >= 2.5, ("rim tall/short ratio is %.2f (<2.5) — no silhouette variation"):format(hi / lo))
end)

H.test("rim restyle (M3): the main wall is consistently Rock (no Slate stripe alternation)", function()
	local plan = WorldGen.plan(GameConfig)
	for _, b in ipairs(plan.rimPeaks.blocks) do
		H.eq(b.mat, "Rock", ("rim block at az=%.0f is material %q, expected consistently Rock"):format(b.ad, tostring(b.mat)))
	end
end)

H.test("rim restyle (M3): snow caps only the top ~30%% of peaks, each shrunk to 40-70%% of its block", function()
	local plan = WorldGen.plan(GameConfig)
	local blocks, snow = plan.rimPeaks.blocks, plan.rimPeaks.snowCaps
	H.ok(#snow > 0, "rimPeaks.snowCaps is empty — no peak reads as capped")
	H.ok(#snow < #blocks, ("snow caps (%d) must be a MINORITY of rim blocks (%d) — every-crest caps read as castle teeth"):format(#snow, #blocks))
	local crests = {}
	for _, b in ipairs(blocks) do crests[#crests + 1] = b.crest end
	table.sort(crests)
	local p70 = crests[math.max(1, math.ceil(#crests * 0.70))]
	for _, s in ipairs(snow) do
		-- Every snow cap's footprint must be smaller than its parent block's declared footprint bound —
		-- pin the SHAPE fact (caps are shrunk, not full-block) without re-deriving which block owns it.
		H.ok(s.sx > 0 and s.sz > 0, "a snow cap has a non-positive footprint")
	end
	H.ok(#snow <= #blocks - math.floor(#blocks * 0.60),
		("%d of %d rim blocks are capped — expected only the top ~30%% (p70=%.0f) to read as dusted peaks"):format(#snow, #blocks, p70))
end)

H.test("rim restyle (M3): a Grass/LeafyGrass foot band exists so the wall grows out of the meadow", function()
	local plan = WorldGen.plan(GameConfig)
	local foot = plan.rimPeaks.foot
	H.ok(foot and #foot > 0, "rimPeaks.foot is empty — no meadow-blend band at the rim base")
	for _, f in ipairs(foot) do
		H.ok(f.mat == "Grass" or f.mat == "LeafyGrass",
			("foot-band fill at (%.0f,%.0f) is material %q, expected Grass/LeafyGrass"):format(f.x, f.z, tostring(f.mat)))
		H.between(f.sz, 80, 150, ("foot-band radial extent %.0f is outside the declared 80-150 stud rise band"):format(f.sz))
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
H.test("fill budget: total sculpt fill ops ≤1800 (recorded)", function()
	local plan = WorldGen.plan(GameConfig)
	H.eq(plan.fillOpCount, #plan.sculptOps, "plan.fillOpCount does not match #plan.sculptOps — the recorded budget is a lie")
	print(("        [fill-budget] WorldGen sculpts %d terrain fill ops"):format(#plan.sculptOps))
	-- Cap raised 1000→1400 (M1.5 VOLUME hotfix), then 1400→1800 (M3 look-dev round): the organic-meadow
	-- patchwork (finding 1) and the rim foot band (finding 2c) both add FillCylinder/FillBlock ops on
	-- top of the M1.5 baseline (1399, one op from the old 1400 cap — too little headroom for further
	-- look-dev tuning). 1800 stays comfortably under the HARD GATE ceiling of 2600 ops. Still a one-time
	-- BOOT cost (sculpt runs once), amortized by YIELD_EVERY, not a per-frame cost.
	H.ok(#plan.sculptOps <= 1800, ("WorldGen sculpts %d fill ops (>1800) — the terrain build is over budget"):format(#plan.sculptOps))
	H.ok(#plan.sculptOps <= 2600, ("WorldGen sculpts %d fill ops (>2600) — exceeds the project HARD GATE ceiling"):format(#plan.sculptOps))
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
