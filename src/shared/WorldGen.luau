--!nonstrict
--[[
	WorldGen.luau — the Ember Valley Terrain world + lighting rig (Phase V). M1 built the CORRECT but
	plain valley (flat datum floor, a coarse rim, boxy lakes). M1.5 (the Content Pass) turns that plain
	bowl into a FINISHED-looking valley — a peaked mountain rim, a river from the waterfall to the lake,
	de-boxed water with beaches, deterministic material patchwork, micro relief, and a golden-hour rig —
	WITHOUT touching any datum number. Every new feature is DATA produced by plan() and applied by
	sculpt()/build(); plan() stays pure and deterministic (no Instances, no services, NO math.random).

	WHY THE SPLIT (this is what makes the world headlessly gated):
	Lune's @lune/roblox cannot build Terrain or set Lighting, so WorldGen is two halves —

	  • WorldGen.plan(cfg) → a PURE data table. No Instances, no services, no workspace, no
	    math.random; deterministic given cfg. This is the ONLY half the Tier-4 specs exercise.
	    It carries the whole world as data: the bowl profile heightAt(x,z), the water bodies (each with
	    a SOLID floor), the peaked rim, the river polyline, the paint patchwork, the micro relief, the
	    lighting + terrain-style property values, the load-bearing datumSamples, and — the single source
	    of truth for the fill-budget gate — `sculptOps`, the flat ordered list of terrain fill
	    primitives that sculpt() literally replays.

	  • WorldGen.sculpt/applyStyle/applyLighting/build → APPLY the plan (touch Terrain/Lighting/
	    Workspace). Called ONLY by GameServer (and the future M2 edit-mode harness), NEVER by a test.
	    THIN and obviously-correct: sculpt() is a dumb interpreter over plan.sculptOps.

	THE INVARIANTS (each a LOGIC fact wearing art clothes; each with its machine gate in
	tests/worldgen.spec.luau):
	  ① DATUM — ground datum is Y=0. Spawn (±1200), the fire-grove annulus, the pad approach toward
	    (1150,0), the perch band and the y=0 thermal ring are ALL tuned to it, so the playable floor
	    (r < FLAT_R) stays within ±8 of datum. Relief inside r<3400 is MICRO ONLY (mounds ≤6 studs);
	    outcrops are the exception, restricted to r1700-3000 and ≥120 from every datum sample. All big
	    relief lives on the mountain RIM (r > FLAT_R).
	  ② WATER P3 — BirdCollision.luau:41 sets IgnoreWater=true, so terrain water is INVISIBLE to the
	    bird's swept sphere: a bird over water falls to whatever SOLID is beneath, and Y<-200 kills it.
	    Therefore EVERY water body (lake, sea, river, pool) gets a SOLID terrain floor well above the
	    failsafe (floors here sit at -7..-12), and the hidden -120 catch slab backstops every void.
	  ③ CANOPY — the procedural groves (RescueServer) are KEPT and re-seated on the datum. This module
	    builds NO "Canopy" parts and does not touch CanopyCount.
	  ④ STYLE-ECONOMY DRIFT — the style meter only sees CanQuery=true PARTS; terrain is not a Part, and
	    every decorative plan.parts entry is CanQuery=false, so styleProxDist cannot drift. The lone
	    exception is the P3 catch floor (below): CanQuery=true (BirdCollision's Spherecast must see it),
	    but it's invisible (Transparency=1) and off the reachable ground plane (Y=-130).

	KILL SWITCH — GameConfig.Map.worldV2. Default TRUE; false restores the untouched legacy
	SetupLighting()/BuildMap() path exactly, with Terrain cleared.
]]

local WorldGen = {}

-- M4-B (Phase V mesh pass): AssetManifest is pure data (safe to require at module load — no Instances
-- touched); MeshFactory's applier touches `game`/Instance only inside function bodies, so requiring it
-- here is also safe under the Lune loader (module load never calls those functions).
local AssetManifest = require(script.Parent.AssetManifest)
local MeshFactory = require(script.Parent.MeshFactory)

--------------------------------------------------------------------------------
-- BOWL PROFILE — the pure continuous height field. Y=0 is the datum. heightAt backs the datum gate
-- and the "rim rises" gate; the PEAKED rim silhouette is separate discrete block DATA (buildRim).
--------------------------------------------------------------------------------
local FLAT_R       = 3400   -- flat playable radius: spawn box, grove annulus, perch band, thermal ring(3200) all inside
local RIM_PEAK_R   = 5200   -- radius of the tallest smoothed rim ring (heightAt only)
local RIM_OUTER_R  = 7200   -- radius where the smoothed rim falls back to the outer coastal plain
local RIM_HEIGHT   = 1800   -- rim crest height (studs above datum); shared by heightAt AND the peak blocks
local OUTER_Y      = 30     -- the outer coastal plain the distant sea is carved into
local FLOOR_RELIEF = 4      -- max |dip| of the shallow playable bowl (kept < the datum gate's 8-stud band)

-- P3 CATCH FLOOR — a single hidden global slab under the whole reachable world so a graze-slide off
-- any solid edge into a void gap falls at most to CATCH_FLOOR_Y (not past the -200 failsafe). S51
-- BootClock fix: this used to be a terrain FillBlock (the single biggest sculpt-time cost for geometry
-- that's NEVER SEEN); it's now a single invisible queryable Part (see buildCatchFloorPart below) —
-- CATCH_THICKNESS is that Part's Size.Y.
local CATCH_FLOOR_Y     = -120
local CATCH_THICKNESS    = 20
local REACHABLE_RADIUS   = 8000

-- Roblox Terrain fill has a ~4096-stud PER-AXIS extent limit ("Extents are too large" on FillBlock);
-- lune has no Terrain so only a REAL engine (the M2 capture smoke) sees it. The big axis-aligned slabs
-- (catch slab 16000², grass floor 6800², apron slabs, the WestSea carve 5400×18000) all blow it, so
-- the B() assembler tiles any oversized block into a grid of sub-blocks ≤ this. A one-time
-- boot cost, not per-frame. The extent gate asserts no op ever exceeds it again.
local MAX_FILL_EXTENT   = 4000

-- The engine limit is ALSO on region VOLUME, not just per-axis extent: 10 of the rotated rim PEAK
-- blocks (sx=sz≈1231.5, sy 1593-2044 — every axis well under MAX_FILL_EXTENT) still threw "Extents are
-- too large" in real Studio. The largest FillBlock proven to pass is the catch slab tile at
-- 4000×~24×4000 ≈ 3.84e8 studs³, so this budget sits comfortably under that proven-passing bound.
local MAX_FILL_VOLUME   = 3.0e8

-- surfaceY(x,z) → the SOLID terrain surface height at world XZ. Pure; no state, no random.
local function surfaceY(x, z)
	local r = math.sqrt(x * x + z * z)
	if r <= FLAT_R then
		local t = r / FLAT_R
		return -FLOOR_RELIEF * (1 - t * t)
	elseif r <= RIM_PEAK_R then
		local u = (r - FLAT_R) / (RIM_PEAK_R - FLAT_R)
		local s = u * u * (3 - 2 * u)
		return s * RIM_HEIGHT
	elseif r <= RIM_OUTER_R then
		local u = (r - RIM_PEAK_R) / (RIM_OUTER_R - RIM_PEAK_R)
		local s = u * u * (3 - 2 * u)
		return RIM_HEIGHT + (OUTER_Y - RIM_HEIGHT) * s
	else
		return OUTER_Y
	end
end

--------------------------------------------------------------------------------
-- PURE HASH — the one source of "randomness". Deterministic; NOT math.random (the world must be
-- byte-identical on every boot and inside the headless spec). n01(i) ∈ [0,1).
--------------------------------------------------------------------------------
local function n01(i)
	return (math.sin(i * 127.1) * 43758.5453) % 1
end

-- signed smallest angular difference a-b in degrees, wrapped to (-180,180].
local function angDiff(a, b)
	local d = (a - b) % 360
	if d > 180 then d = d - 360 end
	return d
end

--------------------------------------------------------------------------------
-- RIM = PEAKS, not a wall. A committed peak table drives a gaussian height field around the azimuth;
-- an inner ring (48) + a half-step-staggered outer ring (40) give silhouette depth; talus wedges
-- skirt the inner face; snow caps the tall blocks. All r > FLAT_R (invariant ①).
--------------------------------------------------------------------------------
local PEAKS = {
	{ az = 0,   mul = 1.00, w = 28 }, -- tallest cluster @ +X = the waterfall-cliff backdrop behind the mesa
	{ az = 42,  mul = 0.80, w = 22 },
	{ az = 85,  mul = 0.92, w = 25 },
	{ az = 128, mul = 0.72, w = 20 },
	{ az = 155, mul = 0.55, w = 15 },
	{ az = 180, mul = 0.30, w = 18 }, -- WEST PASS: a low saddle the WestSea glints through
	{ az = 205, mul = 0.60, w = 16 },
	{ az = 245, mul = 0.85, w = 24 },
	{ az = 290, mul = 0.95, w = 26 },
	{ az = 330, mul = 0.78, w = 21 },
}
local WEST_PASS = { azMin = 160, azMax = 200 } -- the declared low-crest arc (the rim-variation gate exempts it)

local function rimFrac(ad)
	local s = 0
	for _, pk in ipairs(PEAKS) do
		local d = angDiff(ad, pk.az)
		s = s + math.exp(-(d / pk.w) ^ 2) * (pk.mul - 0.30)
	end
	return math.clamp(0.30 + s, 0.30, 1.0)
end

-- buildRim() → blocks (each {x,z,y,sx,sy,sz,yaw,mat,crest,ad}), snowCaps, talus. Pure.
local function buildRim()
	local blocks, snow, talus = {}, {}, {}

	local INNER_R, INNER_N = 4300, 48
	for i = 0, INNER_N - 1 do
		local ad = (i / INNER_N) * 360
		local a = math.rad(ad)
		local h = RIM_HEIGHT * rimFrac(ad) * (1 + (n01(i + 1) - 0.5) * 0.16) -- ±8% jitter
		local px, pz = math.cos(a) * INNER_R, math.sin(a) * INNER_R
		local w = (2 * math.pi * INNER_R) / INNER_N * 1.6
		-- M3 rim restyle (a): the inner face reads consistently Rock (no Slate stripe alternation —
		-- that alternation was the "vertical striping" the audit flagged).
		local mat = "Rock"
		blocks[#blocks + 1] = { x = px, z = pz, y = h / 2 - 20, sx = w, sy = h + 40, sz = w, yaw = -a, mat = mat, crest = h, ad = ad }
	end

	local OUTER_R, OUTER_N = 4900, 40
	for i = 0, OUTER_N - 1 do
		local ad = ((i + 0.5) / OUTER_N) * 360 -- half-step staggered
		local a = math.rad(ad)
		local factor = 0.85 + n01(i * 5 + 11) * 0.25 -- 0.85..1.10× the inner height at that az
		local h = RIM_HEIGHT * rimFrac(ad) * factor
		local px, pz = math.cos(a) * OUTER_R, math.sin(a) * OUTER_R
		local w = (2 * math.pi * OUTER_R) / OUTER_N * 1.6
		local mat = "Rock"
		blocks[#blocks + 1] = { x = px, z = pz, y = h / 2 - 20, sx = w, sy = h + 40, sz = w, yaw = -a, mat = mat, crest = h, ad = ad }
	end

	-- M3 rim restyle (b): snow caps only the TOP ~30% of peaks by crest height (a real 70th-percentile
	-- cutoff over the whole crest population, not a fixed Y threshold), each capped at an irregular
	-- extent (40-70% of the block's own footprint) with a per-block jittered offset — a dusting on the
	-- highest peaks, not a uniform white block on every crest ("castle teeth").
	do
		local crests = {}
		for _, b in ipairs(blocks) do crests[#crests + 1] = b.crest end
		table.sort(crests)
		local p70 = crests[math.max(1, math.ceil(#crests * 0.70))]
		for bi, b in ipairs(blocks) do
			if b.crest >= p70 then
				local extent = 0.40 + n01(bi * 13 + 29) * 0.30 -- 40%..70% of the block's footprint
				local offX = (n01(bi * 17 + 3) - 0.5) * b.sx * 0.25
				local offZ = (n01(bi * 19 + 41) - 0.5) * b.sz * 0.25
				snow[#snow + 1] = {
					x = b.x + offX, z = b.z + offZ, y = b.crest * 0.94,
					sx = b.sx * extent, sy = b.crest * 0.12 + 20, sz = b.sz * extent,
				}
			end
		end
	end

	-- Talus: scree slopes on the inner face, toe r=3450 (Y≈0) rising to the block bases r≈4150.
	local TAL_N, toe, baseR = 24, 3450, 4150
	for i = 0, TAL_N - 1 do
		local ad = (i / TAL_N) * 360
		local a = math.rad(ad)
		local mid = (toe + baseR) / 2
		local px, pz = math.cos(a) * mid, math.sin(a) * mid
		local w = (2 * math.pi * mid) / TAL_N * 1.15
		talus[#talus + 1] = { x = px, y = 70, z = pz, sx = w, sy = 140, sz = baseR - toe, yaw = -a }
	end

	-- M3 rim restyle (c): a FOOT BAND of Grass/LeafyGrass fills right where the talus toe meets the
	-- meadow floor (the first ~80-150 studs of the rise), so the rim wall grows OUT of the meadow
	-- instead of butting against it as a bare seam.
	local foot = {}
	local FOOT_N, footInnerR = 32, toe - 90
	for i = 0, FOOT_N - 1 do
		local ad = (i / FOOT_N) * 360
		local a = math.rad(ad)
		local band = 80 + n01(i * 41 + 5) * 70 -- 80..150 studs of radial rise, jittered per wedge
		local mid = footInnerR + band / 2
		local w = (2 * math.pi * mid) / FOOT_N * 1.3
		local mat = (n01(i * 31 + 71) < 0.55) and "Grass" or "LeafyGrass"
		foot[#foot + 1] = { x = math.cos(a) * mid, y = -2, z = math.sin(a) * mid, sx = w, sy = 6, sz = band, yaw = -a, mat = mat }
	end

	return blocks, snow, talus, foot
end

--------------------------------------------------------------------------------
-- WATER — every body has a SOLID floor above -40 (invariant ②). The lake is DE-BOXED as overlapping
-- cylinders; the pool + river are carved from polyline/circle DATA. buildWater keeps the semantic
-- region records the LEGACY M1 gates read; the carve geometry lives in the river/lake/pool tables.
--------------------------------------------------------------------------------
local function buildWater()
	return {
		-- ValleyLake: floor -10. `region` kept so the M1 water-P3 gates still read it; the actual carve
		-- is the 3-cylinder de-box in plan().lakeCarve (deboxed=true tells sculpt to skip the box).
		{
			name = "ValleyLake", surfaceY = -2, floorY = -10, deboxed = true,
			region = { minX = -2600, maxX = -1800, minZ = -2400, maxZ = -1600 },
		},
		-- The distant WestSea past the western rim. Still a box carve (a coastline, not a pond).
		{
			name = "WestSea", surfaceY = -2, floorY = -12,
			region = { minX = -13000, maxX = -7600, minZ = -9000, maxZ = 9000 },
		},
	}
end

-- Lake de-box: 3 overlapping cylinders inside the ValleyLake region. surface -2, floor -10.
local LAKE_CARVE = {
	surfaceY = -2, floorY = -10,
	cyls = { { x = -2200, z = -2000, r = 350 }, { x = -2400, z = -2200, r = 280 }, { x = -2000, z = -1800, r = 240 } },
}

-- Plunge POOL at the waterfall base (fall sheet is at X≈920,Z0). Two small overlapped cylinders,
-- combined radius ~28 — deliberately SMALL so it clears the annulus-mid grove point at (850,0) by the
-- clearance gate's margin (a big pool there would swallow a grove). surface -2, rock floor -8.
local POOL = {
	surfaceY = -2, floorY = -8,
	cyls = { { x = 915, z = 0, r = 20 }, { x = 925, z = 0, r = 20 } },
}

-- RIVER (datum). Waypoints threaded through the annulus/spawn-corner gaps (solved so every datum
-- sample stays ≥ halfWidth+40 from every segment — the river-clearance gate). width 50, surface -2,
-- rock floor -7 (depth 5 ≤ 8). Mouth (-1900,-1750) lands inside the lake.
local RIVER = {
	halfWidth = 25, surfaceY = -2, floorY = -7,
	points = {
		{ 920, 0 }, { 860, -602 }, { -398, -1290 }, { -834, -1423 },
		{ -1200, -1537 }, { -1547, -1634 }, { -1900, -1750 },
	},
}

--------------------------------------------------------------------------------
-- MICRO RELIEF (invariant ①). Committed positions (generated + verified offline against the datum
-- samples). Mounds protrude ≤6; outcrops are the ONLY relief allowed inside the playable radius band,
-- restricted to r1700-3000 arcs (SW+NE) and ≥120 from every datum sample.
--------------------------------------------------------------------------------
local MOUNDS = {
	{ x = -1575.7, z = -555.3, r = 33.3, protrude = 4.37 }, { x = -1005.8, z = -1745.1, r = 30.5, protrude = 5.15 },
	{ x = 453.7, z = -1426.4, r = 31.3, protrude = 4.84 }, { x = 397.0, z = 2937.2, r = 35.3, protrude = 5.63 },
	{ x = 770.1, z = 270.0, r = 24.5, protrude = 3.61 }, { x = 930.4, z = -1408.3, r = 23.0, protrude = 3.99 },
	{ x = -980.9, z = 901.0, r = 33.3, protrude = 5.97 }, { x = 1960.5, z = 2300.0, r = 27.1, protrude = 3.73 },
	{ x = 1218.6, z = -1583.0, r = 35.2, protrude = 3.34 }, { x = 770.5, z = 1744.1, r = 32.4, protrude = 4.17 },
	{ x = -617.5, z = -58.4, r = 30.0, protrude = 5.77 }, { x = -2134.5, z = 1853.5, r = 37.2, protrude = 5.39 },
	{ x = -902.1, z = -434.3, r = 32.5, protrude = 3.46 }, { x = 571.3, z = 833.4, r = 36.6, protrude = 3.14 },
	{ x = -787.1, z = -2443.1, r = 27.8, protrude = 3.12 }, { x = 1320.1, z = 405.0, r = 31.9, protrude = 5.97 },
	{ x = 673.9, z = -124.7, r = 30.1, protrude = 5.31 }, { x = 425.8, z = 1167.6, r = 34.0, protrude = 4.61 },
	{ x = -2800.6, z = -757.5, r = 36.0, protrude = 4.75 }, { x = -1266.9, z = 2484.3, r = 24.3, protrude = 4.74 },
	{ x = 954.0, z = -512.0, r = 27.8, protrude = 5.54 }, { x = -392.3, z = -572.2, r = 28.6, protrude = 3.75 },
	{ x = -1695.5, z = -787.0, r = 23.6, protrude = 4.90 }, { x = 791.6, z = 2439.6, r = 26.3, protrude = 5.36 },
	{ x = 2441.8, z = -1001.0, r = 22.5, protrude = 5.94 }, { x = 2235.2, z = 1749.5, r = 26.0, protrude = 5.86 },
	{ x = -1455.7, z = 2332.4, r = 30.5, protrude = 4.64 }, { x = -614.9, z = -533.2, r = 23.9, protrude = 3.77 },
	{ x = -1140.9, z = 1503.8, r = 23.9, protrude = 3.77 }, { x = -1287.3, z = -220.1, r = 32.0, protrude = 4.90 },
	{ x = 2633.7, z = -65.1, r = 24.5, protrude = 5.46 }, { x = 141.2, z = -735.7, r = 25.9, protrude = 3.14 },
	{ x = -792.2, z = -2547.1, r = 27.8, protrude = 5.25 }, { x = 956.0, z = 1539.7, r = 23.4, protrude = 5.51 },
	{ x = -1662.0, z = 1186.0, r = 36.8, protrude = 3.83 }, { x = 1560.4, z = 552.2, r = 36.7, protrude = 6.00 },
}
local OUTCROPS = {
	{ x = 2025.6, z = 1550.8, r = 22.4, protrude = 13.05 }, { x = -1403.3, z = -2026.3, r = 22.6, protrude = 18.58 },
	{ x = 837.7, z = 1775.7, r = 18.4, protrude = 16.40 }, { x = -923.8, z = -1616.3, r = 15.7, protrude = 18.56 },
	{ x = 2513.2, z = 777.5, r = 15.2, protrude = 20.51 }, { x = -1003.5, z = -1821.6, r = 20.3, protrude = 15.94 },
	{ x = 1826.0, z = 1378.6, r = 25.4, protrude = 20.57 }, { x = -611.4, z = -1973.7, r = 24.4, protrude = 10.17 },
	{ x = 2043.1, z = 831.5, r = 14.5, protrude = 15.49 }, { x = -2288.3, z = -1418.7, r = 18.2, protrude = 18.90 },
	{ x = 2235.0, z = 1101.1, r = 22.7, protrude = 16.74 }, { x = -933.1, z = -1919.2, r = 15.1, protrude = 11.93 },
	{ x = 1083.8, z = 2457.8, r = 14.3, protrude = 14.78 }, { x = -2189.6, z = -1039.2, r = 24.1, protrude = 18.90 },
	{ x = 2571.5, z = 937.4, r = 23.7, protrude = 10.27 }, { x = -1914.1, z = -1001.2, r = 20.4, protrude = 19.62 },
}

--------------------------------------------------------------------------------
-- MATERIAL PAINT (M3 organic-meadow restyle). The old rigid 300-stud SQUARE-FillBlock grid — which
-- read as a farmland CHECKERBOARD from altitude (the audit's headline finding) — is REPLACED by
-- organic FillCylinder patches: hash-jittered centers off a coarse candidate grid (so nothing lands
-- on a straight line), radii 50-180 (round footprints, zero straight edges), and a coarse cluster
-- hash so 2-4 NEIGHBORING patches tend to share a material (the audit's "like materials cluster"
-- ask) instead of alternating cell-to-cell. Weights are biased toward LeafyGrass/Grass and away from
-- the stark Ground/Mud browns (the "pops like tilled fields" contrast complaint) — the smaller diff
-- than repainting terrainStyle's global material colors. Cells near a water carve are skipped so the
-- beaches read. Each patch is a thin (4-stud) FillCylinder, top at Y=0 (matches the old grid's top).
--------------------------------------------------------------------------------
local PAINT_MATS = { "LeafyGrass", "Grass", "Ground", "Mud" }
local PAINT_WTS  = { 0.52, 0.34, 0.08, 0.06 } -- more LeafyGrass/Grass, fewer stark Ground/Mud patches

local PATCH_GRID    = 220 -- candidate-center stride (jitter fills the gaps, so nothing grid-aligns)
local PATCH_JITTER   = 140 -- max +/- offset applied to each grid candidate (< grid/2, avoids collapse)
local PATCH_R_MIN    = 50
local PATCH_R_MAX    = 180
local PATCH_H        = 4  -- thin fill, same height as the old grid cells
local CLUSTER_CELL   = 380 -- coarse cell so ~2-4 neighboring patches likely share a cluster material
local CLUSTER_P      = 0.72 -- probability a patch inherits its cluster's material vs. rolling fresh

local function pointSegDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local L2 = dx * dx + dz * dz
	if L2 < 1e-9 then return math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2) end
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / L2, 0, 1)
	return math.sqrt((px - (ax + t * dx)) ^ 2 + (pz - (az + t * dz)) ^ 2)
end

local function paintPick(h)
	local v = n01(h)
	local c = 0
	for i, w in ipairs(PAINT_WTS) do
		c = c + w
		if v < c then return PAINT_MATS[i] end
	end
	return PAINT_MATS[#PAINT_MATS]
end

-- clusterMat(x,z) — the dominant material for the coarse cell a patch center falls in; neighboring
-- patch centers quantize to the same cell, so they draw the same hash and (usually) the same material.
local function clusterMat(x, z)
	local cxi = math.floor(x / CLUSTER_CELL + 0.5)
	local czi = math.floor(z / CLUSTER_CELL + 0.5)
	return paintPick(cxi * 92821 + czi * 68923 + 5)
end

local function buildPaint()
	local cells = {}
	local function nearWater(x, z)
		for _, c in ipairs(POOL.cyls) do
			if math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < c.r + 150 then return true end
		end
		for _, c in ipairs(LAKE_CARVE.cyls) do
			if math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < c.r + 150 then return true end
		end
		for i = 1, #RIVER.points - 1 do
			local a, b = RIVER.points[i], RIVER.points[i + 1]
			if pointSegDist(x, z, a[1], a[2], b[1], b[2]) < RIVER.halfWidth + 150 then return true end
		end
		return false
	end
	local n = 0
	local IMAX = math.ceil(2700 / PATCH_GRID)
	for ix = -IMAX, IMAX do
		for iz = -IMAX, IMAX do
			n = n + 1
			local gx, gz = ix * PATCH_GRID, iz * PATCH_GRID
			local jx = (n01(n * 3 + 1) - 0.5) * 2 * PATCH_JITTER
			local jz = (n01(n * 5 + 7) - 0.5) * 2 * PATCH_JITTER
			local x, z = gx + jx, gz + jz
			if math.sqrt(x * x + z * z) < 2600 and not nearWater(x, z) then
				local rad = PATCH_R_MIN + n01(n * 7 + 13) * (PATCH_R_MAX - PATCH_R_MIN)
				local mat
				if n01(n * 11 + 19) < CLUSTER_P then
					mat = clusterMat(x, z)
				else
					mat = paintPick(n * 97 + 41)
				end
				cells[#cells + 1] = { x = x, z = z, r = rad, mat = mat }
			end
		end
	end
	return cells
end

--------------------------------------------------------------------------------
-- SCATTER (M4-B) — decorative mesh-prop positions: rocks along the rim base ring + near the lake/pool
-- shores, bushes+logs sprinkled across the meadow annulus. PURE (no Instances, no game, no
-- math.random) — MeshFactory.build (engine) and WorldGen.build's scatter applier consume this. Nothing
-- here specifically avoids grove centres: the spec's "groves handled by trees already" means the
-- procedural groves (RescueServer) already occupy that space, not that this module knows where they are.
--------------------------------------------------------------------------------
local SCATTER_MAX_R = FLAT_R - 50 -- keep every scatter point safely inside the flat playable floor
local SCATTER_SEED = 20260722     -- S50; fixed so the scatter is identical on every boot (M4-B)
local SCATTER_BUDGET = 140

local function scatterHash(seed, i)
	return n01(seed * 977 + i * 131 + 17)
end

-- Exclusion: the spawn core box, the delivery-pad approach circle, and every water carve (with margin).
local function scatterExcluded(x, z, coreHalf, deliverPos, padClearR)
	if math.abs(x) <= coreHalf and math.abs(z) <= coreHalf then return true end
	if deliverPos then
		local dx, dz = x - deliverPos.X, z - deliverPos.Z
		if dx * dx + dz * dz < padClearR * padClearR then return true end
	end
	for i = 1, #RIVER.points - 1 do
		local a, b = RIVER.points[i], RIVER.points[i + 1]
		if pointSegDist(x, z, a[1], a[2], b[1], b[2]) < RIVER.halfWidth + 60 then return true end
	end
	for _, c in ipairs(LAKE_CARVE.cyls) do
		if math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < c.r + 60 then return true end
	end
	for _, c in ipairs(POOL.cyls) do
		if math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < c.r + 60 then return true end
	end
	return false
end

-- scatterPlan(cfg, seed) -> array of { role, x, y, z, rotY, vseed, hseed }. PURE; deterministic for a
-- fixed (cfg, seed) pair. `vseed`/`hseed` ∈ [0,1) let the applier deterministically pick an
-- AssetManifest variant + target height without this module knowing AssetManifest's internal shape.
-- role ∈ "rock" | "bush" | "log" (the roles the curated manifest actually has coverage for — treeLeafy/
-- treePine are handled by RescueServer's tree swap, not this scatter).
function WorldGen.scatterPlan(cfg, seed)
	seed = seed or SCATTER_SEED
	cfg = cfg or {}
	local rescue = cfg.Rescue or {}
	local deliverPos = rescue.deliverPos or Vector3.new(1150, 250, 0)
	local padClearR = rescue.padClearRadius or 400
	local coreHalf = (cfg.Map and cfg.Map.coreHalfExtent) or 1200

	local pts = {}
	local i = 0
	-- sizeMul: an EXTRA per-point size multiplier on top of the applier's role-based scale (M3
	-- readability pass). Only the rim-ring rocks use it (>1.0) so rim-ring rocks read bigger than
	-- shore/meadow ones, matching the audit's "rim-ring rocks can go bigger" ask.
	local function push(role, x, z, sizeMul)
		-- Shore rocks are offset from a water carve center, which can itself sit close to SCATTER_MAX_R
		-- (e.g. the ValleyLake), so the offset point must be re-checked against the valley radius too —
		-- not just the ring/annulus radii the callers below already stayed inside of.
		if math.sqrt(x * x + z * z) > SCATTER_MAX_R then return end
		if scatterExcluded(x, z, coreHalf, deliverPos, padClearR) then return end
		i = i + 1
		pts[#pts + 1] = {
			role = role, x = x, z = z, y = surfaceY(x, z),
			rotY = scatterHash(seed, i * 3 + 1) * 360,
			vseed = scatterHash(seed, i * 3 + 2),
			hseed = scatterHash(seed, i * 3 + 3),
			sizeMul = sizeMul or 1.0,
		}
	end

	-- 1) Rocks along the rim base ring (r 3150..3350, safely inside SCATTER_MAX_R). sizeMul 1.3: rim
	-- rocks read bigger than shore/meadow rocks (both role "rock") at flight altitude.
	local ROCK_RING_N = 44
	for k = 0, ROCK_RING_N - 1 do
		local ad = (k / ROCK_RING_N) * 360 + (scatterHash(seed, k) - 0.5) * 6
		local a = math.rad(ad)
		local r = 3150 + scatterHash(seed, k + 900) * 200
		push("rock", math.cos(a) * r, math.sin(a) * r, 1.3)
	end

	-- 2) Rocks near the lake + pool shores (just outside each carve's radius).
	local shoreCenters = {}
	for _, c in ipairs(LAKE_CARVE.cyls) do shoreCenters[#shoreCenters + 1] = c end
	for _, c in ipairs(POOL.cyls) do shoreCenters[#shoreCenters + 1] = c end
	local si = 0
	for _, c in ipairs(shoreCenters) do
		for _ = 0, 2 do
			si = si + 1
			local a = scatterHash(seed, si * 7 + 2000) * math.pi * 2
			local r = c.r + 90 + scatterHash(seed, si * 11 + 2500) * 70
			push("rock", c.x + math.cos(a) * r, c.z + math.sin(a) * r)
		end
	end

	-- 3) Bushes + logs sprinkled over the meadow annulus (r 300..2600).
	local MEADOW_BUSH_N, MEADOW_LOG_N = 50, 20
	for k = 0, MEADOW_BUSH_N - 1 do
		local a = scatterHash(seed, k + 4000) * math.pi * 2
		local r = 300 + scatterHash(seed, k + 4500) * 2300
		push("bush", math.cos(a) * r, math.sin(a) * r)
	end
	for k = 0, MEADOW_LOG_N - 1 do
		local a = scatterHash(seed, k + 6000) * math.pi * 2
		local r = 300 + scatterHash(seed, k + 6500) * 2300
		push("log", math.cos(a) * r, math.sin(a) * r)
	end

	-- Defensive budget cap (today's counts sum to 129, well under 140).
	while #pts > SCATTER_BUDGET do
		table.remove(pts)
	end

	return pts
end

--------------------------------------------------------------------------------
-- LIGHTING RIG (M1.5 target — ONE golden-hour starting point; do NOT blind-iterate further). Data
-- only; applied in applyLighting().
--------------------------------------------------------------------------------
local function buildLighting()
	return {
		ClockTime = 16.8,
		Brightness = 2.6,
		ExposureCompensation = 0.08,
		Ambient = Color3.fromRGB(96, 92, 104),
		OutdoorAmbient = Color3.fromRGB(150, 140, 130),
		FogEnd = 1e6, -- Atmosphere governs view distance, not classic fog
		FogColor = Color3.fromRGB(232, 208, 178),
		GeographicLatitude = 35,
		ShadowSoftness = 0.3,
		Atmosphere = {
			Density = 0.10, Offset = 0.6, Haze = 1.8, Glare = 0.4,
			Color = Color3.fromRGB(255, 205, 165),
			Decay = Color3.fromRGB(115, 95, 125),
		},
		ColorCorrection = {
			Brightness = 0.02, Contrast = 0.08, Saturation = 0.18,
			TintColor = Color3.fromRGB(255, 244, 228),
		},
		Bloom = { Intensity = 0.5, Size = 32, Threshold = 1.1 },
		Sky = {}, -- Roblox default sky (ZERO assets — no texture ids); build() creates a bare Sky instance.
	}
end

-- TERRAIN STYLE — per-material colours + water props, applied via Terrain:SetMaterialColor / the water
-- properties in applyStyle(). Data only (plain {r,g,b} + numbers); no Instance touched here.
local function buildTerrainStyle()
	return {
		materials = {
			-- M3 restyle: Ground/Mud nudged toward the grass luminance (was 140/110/80 and 96/74/56) so
			-- the meadow's brown patches read as muted earth tones, not tilled-field contrast pops.
			Grass = { 110, 160, 70 }, LeafyGrass = { 88, 142, 58 }, Ground = { 132, 122, 90 },
			Mud = { 104, 92, 66 }, Sand = { 218, 198, 152 }, Rock = { 130, 118, 106 },
			Slate = { 106, 100, 96 }, Snow = { 238, 232, 226 },
		},
		water = { color = { 52, 132, 150 }, reflectance = 0.35, waveSize = 0.12, waveSpeed = 14 },
	}
end

--------------------------------------------------------------------------------
-- DATUM SAMPLES — the load-bearing sites the datum gate (①) and the river/relief-clearance gates
-- check. Unchanged from M1: these are world-geometry facts, not art.
--------------------------------------------------------------------------------
local function ringPoints(out, r, n, label)
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		out[#out + 1] = { x = math.cos(a) * r, z = math.sin(a) * r, label = label }
	end
end

local function buildDatumSamples()
	local s = {}
	ringPoints(s, 300, 8, "annulus-inner")
	ringPoints(s, 850, 12, "annulus-mid")
	ringPoints(s, 1400, 12, "annulus-outer")
	for _, sx in ipairs({ -1200, 1200 }) do
		for _, sz in ipairs({ -1200, 1200 }) do
			s[#s + 1] = { x = sx, z = sz, label = "spawn-corner" }
		end
	end
	s[#s + 1] = { x = 1150, z = 0, label = "pad" }
	s[#s + 1] = { x = 800, z = 0, label = "pad-approach" }
	s[#s + 1] = { x = 1000, z = 120, label = "pad-approach" }
	ringPoints(s, 1500, 12, "perch-band")
	ringPoints(s, 3200, 12, "thermal-ring")
	return s
end

--------------------------------------------------------------------------------
-- SCULPT-OP ASSEMBLY — flatten the whole world into the ordered primitive list sculpt() replays.
-- ops: B=FillBlock, W=FillWedge, C=FillCylinder(upright), L=FillBall. Materials are STRING keys
-- (sculpt maps them to Enum.Material) so plan() never constructs an Enum it doesn't need.
--------------------------------------------------------------------------------
local function assembleOps(rimBlocks, rimSnow, rimTalus, rimFoot, paintCells, water)
	local ops = {}
	-- B() — a FillBlock op. Roblox Terrain rejects a fill ("Extents are too large") if any axis exceeds
	-- MAX_FILL_EXTENT OR the region volume exceeds MAX_FILL_VOLUME — the volume check is the one that
	-- bites blocks whose every axis looks fine (the rotated rim PEAKS: sx=sz≈1231.5, sy 1593-2044, all
	-- < 4000, but sx*sy*sz ≈ 2.4-3.1e9 studs³). So tile ANY oversized block — axis-aligned or rotated,
	-- on X/Y/Z alike — into equal-size sub-blocks split along the block's own LOCAL axes, each satisfying
	-- both limits. Equal-size children (not "full tile + remainder") means every sub-block is identical
	-- geometry, so no sliver fills and the union exactly reproduces the original volume.
	--
	-- World placement of a local offset (ox,oy,oz) under yaw: sculpt() applies
	-- `CFrame.new(x,y,z) * CFrame.Angles(0, yaw, 0)`, and Roblox's CFrame.Angles(0,ry,0) is the standard
	-- right-hand-rule rotation about +Y, whose matrix sends local +X → world (cos ry, 0, -sin ry) and
	-- local +Z → world (sin ry, 0, cos ry). So:
	--   wx = x + ox*cos(yaw) + oz*sin(yaw)
	--   wz = z - ox*sin(yaw) + oz*cos(yaw)
	--   wy = y + oy   (yaw only rotates about Y, so Y offsets are untouched)
	-- At yaw=0 this reduces to wx = x+ox, wz = z+oz — the plain axis-aligned case — so one code path
	-- covers both.
	local function pushB(x, y, z, sx, sy, sz, mat, yaw) ops[#ops + 1] = { op = "B", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw } end
	local function B(x, y, z, sx, sy, sz, mat, yaw)
		local yw = yaw or 0
		if sx <= MAX_FILL_EXTENT and sy <= MAX_FILL_EXTENT and sz <= MAX_FILL_EXTENT and sx * sy * sz <= MAX_FILL_VOLUME then
			pushB(x, y, z, sx, sy, sz, mat, yaw)
			return
		end
		local nx = math.max(1, math.ceil(sx / MAX_FILL_EXTENT))
		local ny = math.max(1, math.ceil(sy / MAX_FILL_EXTENT))
		local nz = math.max(1, math.ceil(sz / MAX_FILL_EXTENT))
		-- Per-axis extent is now satisfied; grow whichever local axis is currently largest until the
		-- sub-block volume also fits. Bounded iteration count — geometry here never needs more than a
		-- handful of splits per axis.
		for _ = 1, 64 do
			local subX, subY, subZ = sx / nx, sy / ny, sz / nz
			if subX * subY * subZ <= MAX_FILL_VOLUME then break end
			if subX >= subY and subX >= subZ then
				nx = nx + 1
			elseif subY >= subX and subY >= subZ then
				ny = ny + 1
			else
				nz = nz + 1
			end
		end
		local subX, subY, subZ = sx / nx, sy / ny, sz / nz
		local cosYw, sinYw = math.cos(yw), math.sin(yw)
		for ix = 0, nx - 1 do
			local ox = -sx / 2 + subX / 2 + ix * subX
			for iy = 0, ny - 1 do
				local oy = -sy / 2 + subY / 2 + iy * subY
				for iz = 0, nz - 1 do
					local oz = -sz / 2 + subZ / 2 + iz * subZ
					local wx = x + ox * cosYw + oz * sinYw
					local wz = z - ox * sinYw + oz * cosYw
					local wy = y + oy
					pushB(wx, wy, wz, subX, subY, subZ, mat, yaw)
				end
			end
		end
	end
	-- FIX 3 (S50 audit): B() tiles/gates itself (above), but W()/C()/L() pushed raw — a bypass for the
	-- exact "Extents are too large" class the rim-PEAK bug proved possible. These three now assert the
	-- same per-axis-extent + region-volume bounds AT PLAN TIME (pure error(), no Instances touched), so
	-- an oversized wedge/cylinder/ball is caught by Tier-4 the moment it's authored, never in a live boot.
	local function W(x, y, z, sx, sy, sz, mat, yaw)
		if not (sx <= MAX_FILL_EXTENT and sy <= MAX_FILL_EXTENT and sz <= MAX_FILL_EXTENT and sx * sy * sz <= MAX_FILL_VOLUME) then
			error(("WorldGen W() wedge %.1fx%.1fx%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(sx, sy, sz, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, sx * sy * sz))
		end
		ops[#ops + 1] = { op = "W", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw }
	end
	local function C(x, y, z, h, rad, mat)
		local vol = math.pi * rad * rad * h
		if not (h <= MAX_FILL_EXTENT and 2 * rad <= MAX_FILL_EXTENT and vol <= MAX_FILL_VOLUME) then
			error(("WorldGen C() cylinder h=%.1f rad=%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(h, rad, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, vol))
		end
		ops[#ops + 1] = { op = "C", x = x, y = y, z = z, h = h, rad = rad, mat = mat }
	end
	local function L(x, y, z, rad, mat)
		local vol = (4 / 3) * math.pi * rad ^ 3
		if not (2 * rad <= MAX_FILL_EXTENT and vol <= MAX_FILL_VOLUME) then
			error(("WorldGen L() ball rad=%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(rad, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, vol))
		end
		ops[#ops + 1] = { op = "L", x = x, y = y, z = z, rad = rad, mat = mat }
	end

	-- 1) CATCH SLAB (P3) — this used to be a terrain FillBlock here (tiled into ~36 sub-fills of ~4000²
	-- studs each, the single biggest chunk of sculpt cost, for a slab that is NEVER SEEN). S51 BootClock
	-- fix: it's never rendered, so it doesn't need to be terrain — it's now a single invisible queryable
	-- Part, built in plan.parts and applied by WorldGen.build's cheap Part loop instead of sculpt(). See
	-- buildCatchFloorPart() / the `parts` local below in plan().
	-- 2) FLOOR — the flat grass slab, top at datum Y=0, across the playable bowl.
	B(0, -25, 0, FLAT_R * 2, 50, FLAT_R * 2, "Grass")
	-- 3) PAINT PATCHWORK (M3) — organic FillCylinder patches, 4 thick, top 0 (replaces both the
	-- deleted uniform LeafyGrass disc AND the checkerboard FillBlock grid).
	for _, c in ipairs(paintCells) do
		C(c.x, -2, c.z, PATCH_H, c.r, c.mat)
	end
	-- 4) MESA SKIRT — a painted Mud/Ground ring (r 260→340) around the mesa footprint at datum. Zero height.
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		local rr = 300
		B(1150 + math.cos(a) * rr, -2, 0 + math.sin(a) * rr, 130, 4, 130, (i % 2 == 0) and "Mud" or "Ground", -a)
	end
	-- 5) APRON — four Ground slabs (Y 4..28) framing r≈4600→±8000 so no void reads past the rim.
	B(6300, 16, 0, 3400, 24, 16000, "Ground")
	B(-6300, 16, 0, 3400, 24, 16000, "Ground")
	B(0, 16, 6300, 9200, 24, 3400, "Ground")
	B(0, 16, -6300, 9200, 24, 3400, "Ground")
	-- 6) RIM blocks + snow caps + talus + the M3 grass foot band.
	-- RIM SHELL (not solid): a profiler + volume pass showed each rim block's buried core (everything
	-- below the visible crest, down to the deep catch floor) was 84% of ALL sculpt-op volume in the whole
	-- map — cost with zero visual return, since nothing is ever below the rim's outer/inner faces. Each
	-- block becomes 3 fills instead of 1: an inner-face wall and an outer-face wall (both RIM_WALL_T studs
	-- thick, spanning the full height from RIM_BASE_Y up to the crest), plus a full-footprint top skin
	-- (RIM_SKIN_T studs thick, spanning the block's whole sx×sz footprint at the crest). Every EXTERIOR
	-- surface — inner face, outer face, and crest — lands at the exact same world radius/height the solid
	-- block had; nothing visible changes. The full-footprint skins are the same footprint the solid tops
	-- were, so the two rings' skins still overlap exactly as before, sealing the inter-ring trench with no
	-- gap. The hollow interior this creates is sealed on every side: the two walls close it radially down
	-- to RIM_BASE_Y (-40, at/below the deep catch floor), the skin closes it from above, and neighboring
	-- blocks around the ring overlap tangentially the same way the solid blocks always did — so there is no
	-- opening a bird's swept-sphere collision could ever find (P3 stays intact; exterior geometry identical
	-- to the solid version). Capture-gated via the rim-nadir/west-pass/outside-in poses.
	local RIM_WALL_T, RIM_SKIN_T, RIM_BASE_Y = 100, 120, -40
	local function emitRimShell(b)
		local a  = math.atan2(b.z, b.x)
		local R  = math.sqrt(b.x * b.x + b.z * b.z)
		local w, h = b.sx, b.crest
		local inR, outR = R - w / 2, R + w / 2
		local wallY, wallSy = (h + RIM_BASE_Y) / 2, h - RIM_BASE_Y
		local ri, ro = inR + RIM_WALL_T / 2, outR - RIM_WALL_T / 2
		B(math.cos(a) * ri, wallY, math.sin(a) * ri, RIM_WALL_T, wallSy, b.sz, b.mat, b.yaw) -- inner face
		B(math.cos(a) * ro, wallY, math.sin(a) * ro, RIM_WALL_T, wallSy, b.sz, b.mat, b.yaw) -- outer face
		B(b.x, h - RIM_SKIN_T / 2, b.z, w, RIM_SKIN_T, b.sz, b.mat, b.yaw)                    -- full-footprint top skin
	end
	-- b.y and b.sy are unused by the emitter above (the shell derives its own Y-extents from b.crest and
	-- RIM_BASE_Y) — do NOT strip them from the block records: buildRim's snow-cap pass, the talus/foot
	-- bands, and the worldgen tests all still read fields off these same records.
	for _, b in ipairs(rimBlocks) do emitRimShell(b) end
	for _, s in ipairs(rimSnow) do B(s.x, s.y, s.z, s.sx, s.sy, s.sz, "Snow") end
	for _, t in ipairs(rimTalus) do W(t.x, t.y, t.z, t.sx, t.sy, t.sz, "Ground", t.yaw) end
	for _, f in ipairs(rimFoot) do B(f.x, f.y, f.z, f.sx, f.sy, f.sz, f.mat, f.yaw) end
	-- 7) MICRO RELIEF — grass mounds (≤6 protrusion) then rock outcrops (r1700-3000 arcs).
	for _, m in ipairs(MOUNDS) do L(m.x, m.protrude - m.r, m.z, m.r, "Grass") end
	for _, o in ipairs(OUTCROPS) do L(o.x, o.protrude - o.r, o.z, o.r, "Rock") end

	-- 8) WATER — LAST, so it carves through the floor/paint. Each carve is Air → Rock floor → Water.
	local function carveCyl(x, z, radius, surf, floor)
		local floorBase = floor - 20
		C(x, (floor + (surf + 2)) / 2, z, (surf + 2) - floor, radius, "Air")
		C(x, (floorBase + floor) / 2, z, floor - floorBase, radius, "Rock")
		C(x, (floor + surf) / 2, z, surf - floor, radius, "Water")
	end
	local function carveSeg(x1, z1, x2, z2, hw, surf, floor)
		local mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) + hw * 2
		local yaw = math.atan2(z2 - z1, x2 - x1)
		local floorBase = floor - 30
		B(mx, (floor + (surf + 2)) / 2, mz, len, (surf + 2) - floor, hw * 2, "Air", yaw)
		B(mx, (floorBase + floor) / 2, mz, len, floor - floorBase, hw * 2, "Rock", yaw)
		B(mx, (floor + surf) / 2, mz, len, surf - floor, hw * 2, "Water", yaw)
	end
	-- 8a) Lake de-box (3 cylinders).
	for _, c in ipairs(LAKE_CARVE.cyls) do carveCyl(c.x, c.z, c.r, LAKE_CARVE.surfaceY, LAKE_CARVE.floorY) end
	-- 8b) Plunge pool (2 cylinders).
	for _, c in ipairs(POOL.cyls) do carveCyl(c.x, c.z, c.r, POOL.surfaceY, POOL.floorY) end
	-- 8c) River polyline.
	for i = 1, #RIVER.points - 1 do
		local a, b = RIVER.points[i], RIVER.points[i + 1]
		carveSeg(a[1], a[2], b[1], b[2], RIVER.halfWidth, RIVER.surfaceY, RIVER.floorY)
	end
	-- 8d) WestSea box carve + coastal bluff + a Sand beach on the east edge near the west-pass sightline.
	for _, body in ipairs(water) do
		if not body.deboxed then
			local reg = body.region
			local cx, cz = (reg.minX + reg.maxX) / 2, (reg.minZ + reg.maxZ) / 2
			local sx, sz = reg.maxX - reg.minX, reg.maxZ - reg.minZ
			local floorBase = body.floorY - 40
			local carveTop = body.surfaceY + 2
			B(cx, (body.floorY + carveTop) / 2, cz, sx, carveTop - body.floorY, sz, "Air")
			B(cx, (body.floorY + floorBase) / 2, cz, sx, body.floorY - floorBase, sz, "Rock")
			B(cx, (body.floorY + body.surfaceY) / 2, cz, sx, body.surfaceY - body.floorY, sz, "Water")
			-- Coast bluff: a Ground lip (Y -2..28) along the east sea edge (X = maxX).
			B(reg.maxX, 13, cz, 60, 30, sz, "Ground")
			-- Sand beach: an ~800-long wedge on the east edge near the west-pass sightline (Z≈0).
			W(reg.maxX + 30, 6, 0, 800, 24, 120, "Sand", 0)
		end
	end

	return ops
end

-- buildCatchFloorPart() → the P3 catch floor as a decorative-Part record (S51 BootClock fix — see
-- CATCH_FLOOR_Y's comment). Pure: only Vector3/Color3 value construction, no Instances, matching every
-- other plan.parts producer's contract (build()'s Part-minting loop reads p.size/p.pos/p.canQuery/
-- p.transparency). CanQuery=true is the ONE documented exception to invariant ④ — BirdCollision's
-- Spherecast (workspace:Spherecast with an Exclude filter on the Birds folder only) must see it or a
-- graze-slide off any solid edge falls straight through to the -200 failsafe.
local function buildCatchFloorPart()
	return {
		name = "CatchFloor",
		size = Vector3.new(REACHABLE_RADIUS * 2, CATCH_THICKNESS, REACHABLE_RADIUS * 2),
		pos = Vector3.new(0, CATCH_FLOOR_Y - CATCH_THICKNESS / 2, 0), -- top face lands exactly at CATCH_FLOOR_Y
		canQuery = true, -- invariant ④ exception (documented above) — must be seen by the Spherecast
		-- S51: opaque, not invisible — a Transparency=1 floor showed bare skybox through any terrain gap
		-- above it (the old rock slab this replaces was solid). Dark slate rock so a graze/gap reads as
		-- ground, not a hole in the world.
		transparency = 0,
		color = Color3.fromRGB(91, 93, 105),
		material = Enum.Material.Slate,
	}
end

--------------------------------------------------------------------------------
-- plan(cfg) → the PURE world data table. Deterministic. This is what the specs exercise.
--------------------------------------------------------------------------------
function WorldGen.plan(cfg)
	cfg = cfg or {}
	local flight = cfg.Flight or {}

	local rimBlocks, rimSnow, rimTalus, rimFoot = buildRim()
	local paintCells = buildPaint()
	local water = buildWater()
	local sculptOps = assembleOps(rimBlocks, rimSnow, rimTalus, rimFoot, paintCells, water)
	local parts = { buildCatchFloorPart() }

	return {
		-- Birth contract (must match legacy BuildMap: GameServer:260 Gravity, :267 StreamingEnabled).
		gravity = flight.GRAVITY,
		streamingEnabled = false,

		-- The continuous bowl profile (invariant ①). Pure function of world XZ.
		heightAt = surfaceY,

		-- Water bodies, each with a solid floor (invariant ②) — semantic records for the M1 gates.
		water = water,

		-- P3 catch floor.
		catchFloorY = CATCH_FLOOR_Y,
		reachableRadius = REACHABLE_RADIUS,

		-- Decorative Parts. Terrain does the work for everything visible, so this holds exactly ONE entry
		-- today: the invisible P3 catch floor (buildCatchFloorPart above, canQuery=true — the documented
		-- invariant-④ exception). Any FUTURE decorative Part added here MUST be canQuery=false.
		parts = parts,

		-- M1.5 CONTENT — DATA consumed by sculpt/build, and read by the new gates.
		rimPeaks = { peaks = PEAKS, westPass = WEST_PASS, blocks = rimBlocks, snowCaps = rimSnow, talus = rimTalus, foot = rimFoot },
		river = { halfWidth = RIVER.halfWidth, surfaceY = RIVER.surfaceY, floorY = RIVER.floorY, points = RIVER.points, pool = POOL },
		lakeCarve = LAKE_CARVE,
		paintZones = paintCells,
		relief = { mounds = MOUNDS, outcrops = OUTCROPS },
		terrainStyle = buildTerrainStyle(),

		-- The single source of truth for the fill-budget gate: the ordered fill primitives sculpt replays.
		sculptOps = sculptOps,
		fillOpCount = #sculptOps,
		maxFillExtent = MAX_FILL_EXTENT, -- the per-axis Terrain fill limit the extent gate enforces
		maxFillVolume = MAX_FILL_VOLUME, -- the region-VOLUME Terrain fill limit the extent gate enforces

		-- Lighting rig (data only).
		lighting = buildLighting(),

		-- The load-bearing sites the datum / clearance gates check.
		datumSamples = buildDatumSamples(),

		-- M4-B — decorative mesh-prop scatter positions (rocks/bushes/logs). Always computed (pure,
		-- cheap); WorldGen.build only turns it into Instances when Map.meshScatter is true, so flag-off
		-- is honestly zero new Instances even though the plan data exists either way.
		scatter = WorldGen.scatterPlan(cfg, SCATTER_SEED),
	}
end

--------------------------------------------------------------------------------
-- APPLIERS — touch Terrain / Lighting / Workspace. Called ONLY by GameServer + the M2 harness.
--------------------------------------------------------------------------------
-- sculpt(terrain, plan) → a dumb interpreter over plan.sculptOps.
-- YIELDS on a TIME budget, not an op-count cadence: the ~554 Terrain fills run too long in one
-- synchronous stretch and Roblox kills the script for "exhausted allowed execution time" (Chad's S49
-- boot hit exactly this at WorldGen:555). The original fix yielded every YIELD_EVERY=24 ops, but Chad's
-- live [BootClock] showed that op-count cadence firing 58 times — each task.wait() lands on a churny
-- frame, so 58 yields cost ~most of a 66s sculpt phase. Ops vary wildly in real engine cost (a tiny
-- FillBall vs. a tiled 4000-stud FillBlock), so a FIXED op count either yields far more than the ~10s
-- script-exhaustion guard needs (slow) or not enough (unsafe) — a WALL-CLOCK budget is what the guard
-- itself is measuring, so budget against it directly: yield only once continuous work has run for
-- YIELD_BUDGET_S, comfortably under the ~10s guard (S49 landmine — see reference-worldgen-p3-catch-floor
-- memory). The yield PURPOSE is unchanged (reset the execution-time budget so no stretch trips the
-- guard); only the cadence that decides WHEN to pay for it changes. Not called by the lune tests (they
-- exercise plan() only), so this engine-only yield can't touch Tier-4.
-- S51: live [SculptProf] profiling showed yields were NOT the sculpt cost (65.9s → 68.9s after this
-- budget existed at 1.5s) — the fill calls themselves dominate. Tightened to 0.5s: same guard purpose,
-- but buys exhaustion-guard headroom for free since the yield cadence was never the bottleneck.
local YIELD_BUDGET_S = 0.5
function WorldGen.sculpt(terrain, plan)
	local lastYield = os.clock()
	-- S51 [SculptProf] — always-on per-op-class timing so a slow boot can be attributed to a specific
	-- fill type (or to yields) without re-instrumenting. Dead cheap: a few locals, no per-op tables.
	local bTime, bCount, wTime, wCount, cTime, cCount, lTime, lCount = 0, 0, 0, 0, 0, 0, 0, 0
	local yieldTime, yieldCount = 0, 0
	local slowestOp, slowestIdx, slowestTime = nil, 0, 0
	for i, o in ipairs(plan.sculptOps) do
		local m = Enum.Material[o.mat]
		local t0 = os.clock()
		if o.op == "B" then
			terrain:FillBlock(CFrame.new(o.x, o.y, o.z) * CFrame.Angles(0, o.yaw or 0, 0), Vector3.new(o.sx, o.sy, o.sz), m)
		elseif o.op == "W" then
			terrain:FillWedge(CFrame.new(o.x, o.y, o.z) * CFrame.Angles(0, o.yaw or 0, 0), Vector3.new(o.sx, o.sy, o.sz), m)
		elseif o.op == "C" then
			terrain:FillCylinder(CFrame.new(o.x, o.y, o.z), o.h, o.rad, m)
		elseif o.op == "L" then
			terrain:FillBall(Vector3.new(o.x, o.y, o.z), o.rad, m)
		end
		local opTime = os.clock() - t0
		if o.op == "B" then bTime, bCount = bTime + opTime, bCount + 1
		elseif o.op == "W" then wTime, wCount = wTime + opTime, wCount + 1
		elseif o.op == "C" then cTime, cCount = cTime + opTime, cCount + 1
		elseif o.op == "L" then lTime, lCount = lTime + opTime, lCount + 1 end
		if opTime > slowestTime then
			slowestOp, slowestIdx, slowestTime = o.op, i, opTime
		end
		if os.clock() - lastYield > YIELD_BUDGET_S then
			local ty0 = os.clock()
			task.wait()
			yieldTime, yieldCount = yieldTime + (os.clock() - ty0), yieldCount + 1
			lastYield = os.clock()
		end
	end
	print(string.format(
		"[SculptProf] B=%.2fs/%d W=%.2fs/%d C=%.2fs/%d L=%.2fs/%d yield=%.2fs/%d slowest=%s#%d %.2fs",
		bTime, bCount, wTime, wCount, cTime, cCount, lTime, lCount, yieldTime, yieldCount,
		slowestOp or "-", slowestIdx, slowestTime
	))
end

-- applyStyle(terrain, style) → per-material colours + water properties.
function WorldGen.applyStyle(terrain, style)
	for name, c in pairs(style.materials) do
		local mat = Enum.Material[name]
		if mat then
			pcall(function() terrain:SetMaterialColor(mat, Color3.fromRGB(c[1], c[2], c[3])) end)
		end
	end
	local w = style.water
	pcall(function()
		terrain.WaterColor = Color3.fromRGB(w.color[1], w.color[2], w.color[3])
		terrain.WaterReflectance = w.reflectance
		terrain.WaterWaveSize = w.waveSize
		terrain.WaterWaveSpeed = w.waveSpeed
	end)
end

function WorldGen.applyLighting(L, cfg)
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.ExposureCompensation = L.ExposureCompensation
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.FogEnd = L.FogEnd
	Lighting.FogColor = L.FogColor
	Lighting.GeographicLatitude = L.GeographicLatitude
	Lighting.ShadowSoftness = L.ShadowSoftness

	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	local A = L.Atmosphere
	atmo.Density, atmo.Offset, atmo.Haze, atmo.Glare = A.Density, A.Offset, A.Haze, A.Glare
	atmo.Color, atmo.Decay = A.Color, A.Decay
	atmo.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	local C = L.ColorCorrection
	cc.Brightness, cc.Contrast, cc.Saturation = C.Brightness, C.Contrast, C.Saturation
	if C.TintColor then cc.TintColor = C.TintColor end
	cc.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	local B = L.Bloom
	bloom.Intensity, bloom.Size, bloom.Threshold = B.Intensity, B.Size, B.Threshold
	bloom.Parent = Lighting

	-- M4-B: behind Map.meshSky, replace (or create) Lighting.Sky with AssetManifest.skybox's six
	-- textures + sun — it JOINS the golden-hour rig above (Atmosphere/ColorCorrection/Bloom), it
	-- doesn't replace it. Flag off (or missing cfg) = the plain default Sky, byte-identical to before.
	if cfg and cfg.Map and cfg.Map.meshSky then
		local existing = Lighting:FindFirstChild("Sky")
		if existing then existing:Destroy() end
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		local S = AssetManifest.skybox
		sky.SkyboxBk = S.bk
		sky.SkyboxDn = S.dn
		sky.SkyboxFt = S.ft
		sky.SkyboxLf = S.lf
		sky.SkyboxRt = S.rt
		sky.SkyboxUp = S.up
		sky.SunTextureId = S.sun
		sky.SunAngularSize = S.sunSize
		sky.Parent = Lighting
	elseif not Lighting:FindFirstChild("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.Parent = Lighting
	end
end

function WorldGen.build(target, cfg)
	-- S51 BOOT-CLOCK (Chad: "round 1 was over before the map ever rendered" — SOP: probe before
	-- optimizing). One always-on print at the end of build() naming where the ~63s boot actually goes,
	-- phase by phase, so a future slow-boot complaint has a named culprit instead of a guess.
	local tStart = os.clock()
	local plan = WorldGen.plan(cfg)
	local tPlan = os.clock()

	-- BIRTH CONTRACT — reproduce exactly what legacy BuildMap set (GameServer:260 / :267).
	target.Gravity = plan.gravity
	pcall(function() target.StreamingEnabled = false end)

	-- TERRAIN — clear then sculpt the valley + peaked rim + de-boxed water, then apply the style.
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then
		terrain:Clear()
		WorldGen.sculpt(terrain, plan)
		WorldGen.applyStyle(terrain, plan.terrainStyle)
	end
	local tSculpt = os.clock()

	-- DECORATIVE PARTS — under a fresh Workspace.Map folder so boot-diag still finds "Map".
	local map = target:FindFirstChild("Map")
	if map then map:Destroy() end
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = target
	for _, p in ipairs(plan.parts) do
		local part = Instance.new("Part")
		part.Anchored = true
		part.Name = p.name
		part.Size = p.size
		part.Position = p.pos
		part.CanCollide = false
		part.CanQuery = p.canQuery == true -- default false; the P3 catch floor is the sole documented exception
		part.CanTouch = false
		part.CastShadow = false
		if p.transparency then part.Transparency = p.transparency end
		if p.color then part.Color = p.color end
		if p.material then part.Material = p.material end
		part.Parent = map
	end
	local tParts = os.clock()

	-- SCATTER (M4-B) — decorative mesh Models (rocks/bushes/logs) behind Map.meshScatter. plan.scatter
	-- is always computed (pure); this loop is the only place Instances get minted, so flag-off is
	-- honestly zero new Instances. Respects the same time-budget yield rule as sculpt() (S49 landmine).
	local tPrewarmScatter = 0
	if cfg and cfg.Map and cfg.Map.meshScatter then
		local ROLE_TO_PROPS = { rock = AssetManifest.props.rock, bush = AssetManifest.props.bush, log = AssetManifest.props.log }
		-- S51 FIX: scatter used to cold-fetch every mesh it needed one-by-one inside the loop below via
		-- MeshFactory.build -> getTemplate -> InsertService:CreateMeshPartAsync, serialized behind the
		-- per-prop yield cadence — measured at 8.999s. RescueServer.MeshFactory.prewarm (run LATER, for
		-- 27/27 ids) proved warm fetches cost 0.20s total: the CDN round-trips just weren't parallelized
		-- yet. Prewarm the exact rock/bush/log mesh ids scatter is about to use, in parallel, BEFORE the
		-- loop runs — prewarm is idempotent/cached per mesh id (templateCache), so RescueServer's later
		-- call for the same ids becomes a free cache-hit no-op, same as it already is for a second call.
		local tPrewarmStart = os.clock()
		local scatterMeshIds = MeshFactory.uniqueMeshIds(ROLE_TO_PROPS)
		MeshFactory.prewarm(scatterMeshIds)
		tPrewarmScatter = os.clock() - tPrewarmStart
		-- M3 scatter-readability pass: rocks/bushes/logs read as specks from flight altitude. Scale
		-- each role's target height up; rim-ring rocks (pt.sizeMul > 1) go bigger still.
		local ROLE_SIZE_MUL = { rock = 1.8, bush = 1.5, log = 1.5 }
		local scatterFolder = Instance.new("Folder")
		scatterFolder.Name = "Scatter"
		scatterFolder.Parent = map
		local scatterLastYield = os.clock()
		for _, pt in ipairs(plan.scatter) do
			local variants = ROLE_TO_PROPS[pt.role]
			if variants and #variants > 0 then
				local variant = variants[math.max(1, math.min(#variants, math.floor(pt.vseed * #variants) + 1))]
				local roleMul = ROLE_SIZE_MUL[pt.role] or 1.0
				local targetHeight = math.max(2, variant.height * (0.7 + pt.hseed * 0.6) * roleMul * (pt.sizeMul or 1.0))
				local cf = CFrame.new(pt.x, pt.y, pt.z) * CFrame.Angles(0, math.rad(pt.rotY), 0)
				-- S50 audit FIX 4: one bad manifest entry (a dead meshId, a malformed variant) must never
				-- kill the boot — skip just that prop and keep scattering the rest.
				local okMesh, errMesh = pcall(MeshFactory.build, variant, cf, targetHeight, scatterFolder)
				if not okMesh then
					warn("[MeshProp] skipped " .. tostring(variant and variant.rootName) .. ": " .. tostring(errMesh))
				end
			end
			-- Same time-budget cadence as sculpt() above (S51 BootClock fix) rather than a fixed op count.
			if os.clock() - scatterLastYield > YIELD_BUDGET_S then
				task.wait()
				scatterLastYield = os.clock()
			end
		end
	end
	local tScatter = os.clock()

	-- LIGHTING RIG.
	WorldGen.applyLighting(plan.lighting, cfg)
	local tLighting = os.clock()

	print(string.format(
		"[BootClock] plan=%.3fs sculpt=%.3fs parts=%.3fs prewarmScatter=%.3fs scatter=%.3fs lighting=%.3fs total=%.3fs",
		tPlan - tStart, tSculpt - tPlan, tParts - tSculpt, tPrewarmScatter, tScatter - tParts, tLighting - tScatter,
		tLighting - tStart))
end

-- clear(target) → honest flag-off: wipe the terrain and destroy the worldV2 "Map" folder.
function WorldGen.clear(target)
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then terrain:Clear() end
	local map = target:FindFirstChild("Map")
	if map then map:Destroy() end
end

return WorldGen
