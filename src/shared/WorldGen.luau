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
	    plan.parts stays EMPTY, so styleProxDist cannot drift.

	KILL SWITCH — GameConfig.Map.worldV2. Default TRUE; false restores the untouched legacy
	SetupLighting()/BuildMap() path exactly, with Terrain cleared.
]]

local WorldGen = {}

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

-- P3 CATCH FLOOR — a single hidden global rock slab under the whole reachable world so a graze-slide
-- off any solid edge into a void gap falls at most to CATCH_FLOOR_Y (not past the -200 failsafe).
local CATCH_FLOOR_Y     = -120
local CATCH_THICKNESS    = 40
local REACHABLE_RADIUS   = 8000

-- Roblox Terrain fill has a ~4096-stud PER-AXIS extent limit ("Extents are too large" on FillBlock);
-- lune has no Terrain so only a REAL engine (the M2 capture smoke) sees it. The big axis-aligned slabs
-- (catch slab 16000², grass floor 6800², apron slabs, the WestSea carve 5400×18000) all blow it, so
-- the B() assembler tiles any oversized AXIS-ALIGNED block into a grid of sub-blocks ≤ this. A one-time
-- boot cost, not per-frame. The extent gate asserts no op ever exceeds it again.
local MAX_FILL_EXTENT   = 4000

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
		local mat = "Rock"
		if h < 1000 and n01(i * 3 + 7) < 0.33 then mat = "Slate" end -- ~1/3 of LOWER blocks → Slate
		blocks[#blocks + 1] = { x = px, z = pz, y = h / 2 - 40, sx = w, sy = h + 80, sz = w, yaw = -a, mat = mat, crest = h, ad = ad }
		if h > 1350 then
			snow[#snow + 1] = { x = px, z = pz, y = h * 0.94, sx = w, sy = h * 0.12 + 20, sz = w }
		end
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
		if h < 1000 and n01(i * 7 + 3) < 0.33 then mat = "Slate" end
		blocks[#blocks + 1] = { x = px, z = pz, y = h / 2 - 40, sx = w, sy = h + 80, sz = w, yaw = -a, mat = mat, crest = h, ad = ad }
		if h > 1350 then
			snow[#snow + 1] = { x = px, z = pz, y = h * 0.94, sx = w, sy = h * 0.12 + 20, sz = w }
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

	return blocks, snow, talus
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
-- MATERIAL PAINT (the S45 closure-cue fix). The single 2800 LeafyGrass disc — the uniform-plane bug —
-- is DELETED. In its place: a deterministic 300-stud-grid patchwork over r<2600. Per cell a weighted
-- hash picks {LeafyGrass45, Grass35, Ground12, Mud8}; cells near a water carve are skipped so the
-- beaches read. Each cell paints a 260-stud FillBlock 4 thick, top 0 (40-stud grass grout between).
--------------------------------------------------------------------------------
local PAINT_MATS = { "LeafyGrass", "Grass", "Ground", "Mud" }
local PAINT_WTS  = { 0.45, 0.35, 0.12, 0.08 }

local function pointSegDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local L2 = dx * dx + dz * dz
	if L2 < 1e-9 then return math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2) end
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / L2, 0, 1)
	return math.sqrt((px - (ax + t * dx)) ^ 2 + (pz - (az + t * dz)) ^ 2)
end

local function buildPaint()
	local cells = {}
	local function pick(h)
		local v = n01(h)
		local c = 0
		for i, w in ipairs(PAINT_WTS) do
			c = c + w
			if v < c then return PAINT_MATS[i] end
		end
		return PAINT_MATS[#PAINT_MATS]
	end
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
	for ix = -9, 9 do
		for iz = -9, 9 do
			local x, z = ix * 300, iz * 300
			if math.sqrt(x * x + z * z) < 2600 and not nearWater(x, z) then
				cells[#cells + 1] = { x = x, z = z, mat = pick(ix * 73856093 + iz * 19349663) }
			end
		end
	end
	return cells
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
			Grass = { 110, 160, 70 }, LeafyGrass = { 88, 142, 58 }, Ground = { 140, 110, 80 },
			Mud = { 96, 74, 56 }, Sand = { 218, 198, 152 }, Rock = { 130, 118, 106 },
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
local function assembleOps(rimBlocks, rimSnow, rimTalus, paintCells, water)
	local ops = {}
	-- B() — a FillBlock op. If the block is bigger than MAX_FILL_EXTENT on X or Z it would throw
	-- "Extents are too large" in a real engine (lune can't see this), so tile any oversized
	-- AXIS-ALIGNED block into a grid whose union EXACTLY covers the original extents (the last tile in
	-- each row/col is the remainder, so non-integer divisions are exact). Rotated blocks are never
	-- big enough to trigger this, but if one ever were, tiling in world XZ would be wrong — so error
	-- loudly rather than mis-tile. Pure/deterministic geometry.
	local function pushB(x, y, z, sx, sy, sz, mat, yaw) ops[#ops + 1] = { op = "B", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw } end
	local function B(x, y, z, sx, sy, sz, mat, yaw)
		if sx > MAX_FILL_EXTENT or sz > MAX_FILL_EXTENT then
			if yaw and yaw ~= 0 then
				error(("WorldGen: rotated block (%.0f×%.0f) exceeds MAX_FILL_EXTENT and cannot be safely tiled in world XZ"):format(sx, sz))
			end
			local nx, nz = math.ceil(sx / MAX_FILL_EXTENT), math.ceil(sz / MAX_FILL_EXTENT)
			local x0, z0 = x - sx / 2, z - sz / 2
			for ix = 0, nx - 1 do
				local tx = math.min(MAX_FILL_EXTENT, sx - ix * MAX_FILL_EXTENT)
				local cx = x0 + ix * MAX_FILL_EXTENT + tx / 2
				for iz = 0, nz - 1 do
					local tz = math.min(MAX_FILL_EXTENT, sz - iz * MAX_FILL_EXTENT)
					local cz = z0 + iz * MAX_FILL_EXTENT + tz / 2
					pushB(cx, y, cz, tx, sy, tz, mat, yaw)
				end
			end
		else
			pushB(x, y, z, sx, sy, sz, mat, yaw)
		end
	end
	local function W(x, y, z, sx, sy, sz, mat, yaw) ops[#ops + 1] = { op = "W", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw } end
	local function C(x, y, z, h, rad, mat) ops[#ops + 1] = { op = "C", x = x, y = y, z = z, h = h, rad = rad, mat = mat } end
	local function L(x, y, z, rad, mat) ops[#ops + 1] = { op = "L", x = x, y = y, z = z, rad = rad, mat = mat } end

	-- 1) CATCH SLAB (P3) — first, under everything.
	B(0, CATCH_FLOOR_Y - CATCH_THICKNESS / 2, 0, REACHABLE_RADIUS * 2, CATCH_THICKNESS, REACHABLE_RADIUS * 2, "Rock")
	-- 2) FLOOR — the flat grass slab, top at datum Y=0, across the playable bowl.
	B(0, -40, 0, FLAT_R * 2, 80, FLAT_R * 2, "Grass")
	-- 3) PAINT PATCHWORK — 260-stud tiles 4 thick, top 0 (replaces the deleted uniform LeafyGrass disc).
	for _, c in ipairs(paintCells) do
		B(c.x, -2, c.z, 260, 4, 260, c.mat)
	end
	-- 4) MESA SKIRT — a painted Mud/Ground ring (r 260→340) around the mesa footprint at datum. Zero height.
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		local rr = 300
		B(1150 + math.cos(a) * rr, -2, 0 + math.sin(a) * rr, 130, 4, 130, (i % 2 == 0) and "Mud" or "Ground", -a)
	end
	-- 5) APRON — four Ground slabs (Y -40..28) framing r≈4600→±8000 so no void reads past the rim.
	B(6300, -6, 0, 3400, 68, 16000, "Ground")
	B(-6300, -6, 0, 3400, 68, 16000, "Ground")
	B(0, -6, 6300, 9200, 68, 3400, "Ground")
	B(0, -6, -6300, 9200, 68, 3400, "Ground")
	-- 6) RIM blocks + snow caps + talus.
	for _, b in ipairs(rimBlocks) do B(b.x, b.y, b.z, b.sx, b.sy, b.sz, b.mat, b.yaw) end
	for _, s in ipairs(rimSnow) do B(s.x, s.y, s.z, s.sx, s.sy, s.sz, "Snow") end
	for _, t in ipairs(rimTalus) do W(t.x, t.y, t.z, t.sx, t.sy, t.sz, "Ground", t.yaw) end
	-- 7) MICRO RELIEF — grass mounds (≤6 protrusion) then rock outcrops (r1700-3000 arcs).
	for _, m in ipairs(MOUNDS) do L(m.x, m.protrude - m.r, m.z, m.r, "Grass") end
	for _, o in ipairs(OUTCROPS) do L(o.x, o.protrude - o.r, o.z, o.r, "Rock") end

	-- 8) WATER — LAST, so it carves through the floor/paint. Each carve is Air → Rock floor → Water.
	local function carveCyl(x, z, radius, surf, floor)
		local floorBase = floor - 20
		C(x, (floorBase + (surf + 2)) / 2, z, (surf + 2) - floorBase, radius, "Air")
		C(x, (floorBase + floor) / 2, z, floor - floorBase, radius, "Rock")
		C(x, (floor + surf) / 2, z, surf - floor, radius, "Water")
	end
	local function carveSeg(x1, z1, x2, z2, hw, surf, floor)
		local mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) + hw * 2
		local yaw = math.atan2(z2 - z1, x2 - x1)
		local floorBase = floor - 30
		B(mx, (floorBase + (surf + 2)) / 2, mz, len, (surf + 2) - floorBase, hw * 2, "Air", yaw)
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
			B(cx, (floorBase + carveTop) / 2, cz, sx, carveTop - floorBase, sz, "Air")
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

--------------------------------------------------------------------------------
-- plan(cfg) → the PURE world data table. Deterministic. This is what the specs exercise.
--------------------------------------------------------------------------------
function WorldGen.plan(cfg)
	cfg = cfg or {}
	local flight = cfg.Flight or {}

	local rimBlocks, rimSnow, rimTalus = buildRim()
	local paintCells = buildPaint()
	local water = buildWater()
	local sculptOps = assembleOps(rimBlocks, rimSnow, rimTalus, paintCells, water)

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

		-- Decorative Parts. Terrain does the work, so EMPTY — but the field exists and the drift/
		-- coplanarity gates assert over it. Any future Part MUST be canQuery=false.
		parts = {},

		-- M1.5 CONTENT — DATA consumed by sculpt/build, and read by the new gates.
		rimPeaks = { peaks = PEAKS, westPass = WEST_PASS, blocks = rimBlocks, snowCaps = rimSnow, talus = rimTalus },
		river = { halfWidth = RIVER.halfWidth, surfaceY = RIVER.surfaceY, floorY = RIVER.floorY, points = RIVER.points, pool = POOL },
		lakeCarve = LAKE_CARVE,
		paintZones = paintCells,
		relief = { mounds = MOUNDS, outcrops = OUTCROPS },
		terrainStyle = buildTerrainStyle(),

		-- The single source of truth for the fill-budget gate: the ordered fill primitives sculpt replays.
		sculptOps = sculptOps,
		fillOpCount = #sculptOps,
		maxFillExtent = MAX_FILL_EXTENT, -- the per-axis Terrain fill limit the extent gate enforces

		-- Lighting rig (data only).
		lighting = buildLighting(),

		-- The load-bearing sites the datum / clearance gates check.
		datumSamples = buildDatumSamples(),
	}
end

--------------------------------------------------------------------------------
-- APPLIERS — touch Terrain / Lighting / Workspace. Called ONLY by GameServer + the M2 harness.
--------------------------------------------------------------------------------
-- sculpt(terrain, plan) → a dumb interpreter over plan.sculptOps.
-- YIELDS every YIELD_EVERY ops: the ~554 Terrain fills run too long in one synchronous stretch and
-- Roblox kills the script for "exhausted allowed execution time" (Chad's S49 boot hit exactly this at
-- WorldGen:555). task.wait() resets the execution-time budget so no single stretch trips the guard; the
-- terrain just builds progressively over a handful of frames (invisible at boot; nothing downstream —
-- CreateThermals/Remotes, RescueWorld — depends on the terrain being finished first). Not called by the
-- lune tests (they exercise plan() only), so this engine-only yield can't touch Tier-4.
local YIELD_EVERY = 24
function WorldGen.sculpt(terrain, plan)
	for i, o in ipairs(plan.sculptOps) do
		local m = Enum.Material[o.mat]
		if o.op == "B" then
			terrain:FillBlock(CFrame.new(o.x, o.y, o.z) * CFrame.Angles(0, o.yaw or 0, 0), Vector3.new(o.sx, o.sy, o.sz), m)
		elseif o.op == "W" then
			terrain:FillWedge(CFrame.new(o.x, o.y, o.z) * CFrame.Angles(0, o.yaw or 0, 0), Vector3.new(o.sx, o.sy, o.sz), m)
		elseif o.op == "C" then
			terrain:FillCylinder(CFrame.new(o.x, o.y, o.z), o.h, o.rad, m)
		elseif o.op == "L" then
			terrain:FillBall(Vector3.new(o.x, o.y, o.z), o.rad, m)
		end
		if i % YIELD_EVERY == 0 then task.wait() end
	end
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

function WorldGen.applyLighting(L)
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

	if not Lighting:FindFirstChild("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.Parent = Lighting
	end
end

function WorldGen.build(target, cfg)
	local plan = WorldGen.plan(cfg)

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
		part.CanQuery = false -- invariant ④: never queryable, so the style meter can't drift
		part.CanTouch = false
		part.CastShadow = false
		if p.color then part.Color = p.color end
		if p.material then part.Material = p.material end
		part.Parent = map
	end

	-- LIGHTING RIG.
	WorldGen.applyLighting(plan.lighting)
end

-- clear(target) → honest flag-off: wipe the terrain and destroy the worldV2 "Map" folder.
function WorldGen.clear(target)
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then terrain:Clear() end
	local map = target:FindFirstChild("Map")
	if map then map:Destroy() end
end

return WorldGen
