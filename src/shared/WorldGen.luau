--!nonstrict
--[[
	WorldGen.luau — the Terrain valley + lighting rig (Phase V, packet M1). A FRESH build that
	replaces the legacy gray-box `Map` (GameServer.BuildMap) with a real sculpted valley bowl, a
	Terrain mountain RIM, water bodies with solid floors, and a golden-hour lighting rig.

	WHY THE SPLIT (this is what makes the world headlessly gated):
	Lune's @lune/roblox cannot build Terrain or set Lighting, so WorldGen is two halves —

	  • WorldGen.plan(cfg) → a PURE data table. No Instances, no services, no workspace, no
	    math.random; deterministic given cfg. This is the ONLY half the Tier-4 specs exercise.
	    It carries the whole world as data: the bowl profile `heightAt(x,z)`, the water bodies
	    (each with a SOLID floor), any decorative parts, the lighting property values, the
	    load-bearing `datumSamples`, and the birth contract (gravity + streamingEnabled).

	  • WorldGen.build(target, cfg) → APPLIES the plan (touches Terrain/Lighting/Workspace).
	    Called ONLY by GameServer (and the future M2 edit-mode harness) — NEVER by a test. Kept
	    THIN and obviously-correct: it is not machine-tested beyond rojo-build + luau-lsp + the
	    optional Studio smoke, so its correctness is "it calls the right APIs in the right order".

	THE INVARIANTS (each a LOGIC fact wearing art clothes; each with its machine gate in
	tests/worldgen.spec.luau):
	  ① DATUM — ground datum is Y=0 (the legacy baseplate top). Spawn (±1200 @ Y=600), the fire
	    grove annulus, the pad approach toward (1150,0), the perch band and the y=0 thermal ring
	    are ALL tuned to it, so the playable floor must stay near-flat at datum. Relief is spent on
	    the mountain RIM, which begins OUTSIDE the playable area (r > FLAT_R) and climbs to a ring.
	  ② WATER P3 — BirdCollision.luau:41 sets IgnoreWater=true, so terrain water is INVISIBLE to
	    the bird's swept sphere: a bird over water falls to whatever SOLID is beneath, and Y<-200
	    kills it. Therefore EVERY water body gets a SOLID terrain floor well above the failsafe
	    (floors here sit at ~-10, far above both -40 and -200).
	  ③ CANOPY — the procedural groves (RescueServer) are KEPT and re-seated on the datum. This
	    module builds NO "Canopy" parts and does not touch CanopyCount.
	  ④ STYLE-ECONOMY DRIFT — the style meter only sees CanQuery=true parts; terrain is not a Part,
	    and every decorative `plan.parts` entry is emitted CanQuery=false, so styleProxDist cannot
	    drift.

	KILL SWITCH — GameConfig.Map.worldV2. Default TRUE (the new valley is the map now); false
	restores the untouched legacy SetupLighting()/BuildMap() path exactly, with Terrain cleared.
]]

local WorldGen = {}

--------------------------------------------------------------------------------
-- BOWL PROFILE — the pure height field. Y=0 is the datum. All relief is on the rim.
--------------------------------------------------------------------------------
-- Flat playable floor out to FLAT_R (past the y=0 thermal ring @3200 and every load-bearing
-- site), then a rock RIM rising to RIM_HEIGHT at RIM_PEAK_R, then falling to a low OUTER plain
-- where the distant sea sits. Tuned so heightAt is ~0 across the whole playable region and large
-- (> 300) by r≈4000 — the bowl is real, not a flat plane. M3 tunes the LOOK from screenshots.
local FLAT_R       = 3400   -- flat radius: spawn box, grove annulus, perch band, thermal ring(3200) all inside
local RIM_PEAK_R   = 5200   -- radius of the tallest rim ring
local RIM_OUTER_R  = 7200   -- radius where the rim falls back to the outer coastal plain
local RIM_HEIGHT   = 1800   -- rim crest height (studs above datum)
local OUTER_Y      = 30     -- the outer coastal plain the distant sea is carved into
local FLOOR_RELIEF = 4      -- max |dip| of the shallow playable bowl (kept < the datum gate's 8-stud band)

-- P3 CATCH FLOOR — the legacy Baseplate was a solid 16000² slab, so a bird could NEVER fall into
-- void. This valley fills solid only in the grass square + rim ring + water patches, which leaves
-- VOID in the axis-crescent gaps (r FLAT_R→rim) and past the rim. Rescue.nonLethalTerrain only
-- softens the crash-SPEED gate; the deep failsafe GROUND_FAILSAFE_Y=-200 (GameServer:74, fired
-- unconditionally ~:1323) still KILLS anything below -200 — so a graze-slide off the slab edge into
-- void would be an UNEARNED death (P3 violation). A single hidden global catch slab under the whole
-- reachable world means a bird over ANY reachable void falls at most to CATCH_FLOOR_Y and slides.
local CATCH_FLOOR_Y     = -120  -- top of the hidden catch slab: 80 studs above the -200 failsafe, well below the water floors
local CATCH_THICKNESS   = 40    -- slab thickness (occupies -160..-120)
local REACHABLE_RADIUS  = 8000  -- matches the legacy baseplate reach (±8000 XZ)

-- surfaceY(x,z) → the SOLID terrain surface height at world XZ. Pure; no state, no random.
local function surfaceY(x, z)
	local r = math.sqrt(x * x + z * z)
	if r <= FLAT_R then
		-- A shallow bowl: ~-FLOOR_RELIEF at the centre easing to 0 at the flat edge. Near-flat by
		-- construction (|value| ≤ FLOOR_RELIEF), so datum-tuned systems don't notice it.
		local t = r / FLAT_R
		return -FLOOR_RELIEF * (1 - t * t)
	elseif r <= RIM_PEAK_R then
		local u = (r - FLAT_R) / (RIM_PEAK_R - FLAT_R)
		local s = u * u * (3 - 2 * u) -- smoothstep 0→1
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
-- WATER — every body has a SOLID floor (invariant ②). Floors sit at ~-10: shallow, far above
-- both the -40 conservative line and the -200 GROUND_FAILSAFE_Y, so the swept sphere's
-- IgnoreWater blindness can never drop a bird past the failsafe.
--------------------------------------------------------------------------------
local function buildWater()
	return {
		-- A lake in the valley floor (inside the flat playable region). Solid rock floor at -10.
		{
			name = "ValleyLake", surfaceY = -2, floorY = -10,
			region = { minX = -2600, maxX = -1800, minZ = -2400, maxZ = -1600 },
		},
		-- The distant sea past the western rim (r > RIM_OUTER_R). Reads as the edge of the world;
		-- solid floor at -12, still far above the failsafe.
		{
			name = "WestSea", surfaceY = -2, floorY = -12,
			region = { minX = -13000, maxX = -7600, minZ = -9000, maxZ = 9000 },
		},
	}
end

--------------------------------------------------------------------------------
-- LIGHTING RIG v2 — golden low sun, atmosphere haze for aerial depth, subtle Bloom + CC. Data
-- only; applied in build(). Modest atmosphere density so the far rim still reads. M3 tunes these.
--------------------------------------------------------------------------------
local function buildLighting()
	return {
		ClockTime = 16.7,                                  -- low golden-hour sun
		Brightness = 2.4,
		ExposureCompensation = 0.1,
		Ambient = Color3.fromRGB(96, 92, 104),
		OutdoorAmbient = Color3.fromRGB(150, 140, 130),
		FogEnd = 1e6,                                      -- Atmosphere governs view distance, not classic fog
		FogColor = Color3.fromRGB(232, 208, 178),
		GeographicLatitude = 25,
		ShadowSoftness = 0.35,
		Atmosphere = {
			Density = 0.18, Offset = 0.15, Haze = 0.9, Glare = 0.35,
			Color = Color3.fromRGB(220, 205, 190),
			Decay = Color3.fromRGB(150, 120, 110),
		},
		ColorCorrection = {
			Brightness = 0.0, Contrast = 0.12, Saturation = 0.15,
			TintColor = Color3.fromRGB(255, 246, 232),
		},
		Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.05 },
		Sky = {}, -- Roblox default sky (ZERO assets — no texture ids); build() creates a bare Sky instance.
	}
end

--------------------------------------------------------------------------------
-- DATUM SAMPLES — the load-bearing sites the datum gate (①) checks. Every point here sits in the
-- playable region and must read within the datum band of Y=0. Radii are world-geometry facts:
-- spawn ±1200, deliverPos (1150,0), fire annulus 300..1400, perch band ≈1500, thermal ring 3200.
--------------------------------------------------------------------------------
local function ringPoints(out, r, n, label)
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		out[#out + 1] = { x = math.cos(a) * r, z = math.sin(a) * r, label = label }
	end
end

local function buildDatumSamples()
	local s = {}
	-- Fire-grove annulus rings (inner / mid / outer).
	ringPoints(s, 300, 8, "annulus-inner")
	ringPoints(s, 850, 12, "annulus-mid")
	ringPoints(s, 1400, 12, "annulus-outer")
	-- The four spawn-core corners (random spawn box is ±1200 XZ).
	for _, sx in ipairs({ -1200, 1200 }) do
		for _, sz in ipairs({ -1200, 1200 }) do
			s[#s + 1] = { x = sx, z = sz, label = "spawn-corner" }
		end
	end
	-- Pad approach toward deliverPos (1150,0).
	s[#s + 1] = { x = 1150, z = 0, label = "pad" }
	s[#s + 1] = { x = 800, z = 0, label = "pad-approach" }
	s[#s + 1] = { x = 1000, z = 120, label = "pad-approach" }
	-- Perch band ring (groves reach ≈ annulusOuter + groveRadius).
	ringPoints(s, 1500, 12, "perch-band")
	-- The y=0 thermal ring (CreateThermals radius = 3200).
	ringPoints(s, 3200, 12, "thermal-ring")
	return s
end

--------------------------------------------------------------------------------
-- plan(cfg) → the PURE world data table. Deterministic. This is what the specs exercise.
--------------------------------------------------------------------------------
function WorldGen.plan(cfg)
	cfg = cfg or {}
	local flight = cfg.Flight or {}

	return {
		-- Birth contract (must match legacy BuildMap: GameServer:260 Gravity, :267 StreamingEnabled).
		gravity = flight.GRAVITY,
		streamingEnabled = false,

		-- The bowl profile (invariant ①). Pure function of world XZ.
		heightAt = surfaceY,

		-- Water bodies, each with a solid floor (invariant ②).
		water = buildWater(),

		-- P3 catch floor (data): the hidden slab's top Y and the reachable span it must cover. Gated
		-- so it can never regress above the failsafe or above a lake floor.
		catchFloorY = CATCH_FLOOR_Y,
		reachableRadius = REACHABLE_RADIUS,

		-- Decorative Parts. Terrain does the work here, so this is EMPTY — but the field exists and
		-- the coplanarity/drift gates assert over it. Any future Part MUST be canQuery=false.
		parts = {},

		-- Lighting rig v2 (data only).
		lighting = buildLighting(),

		-- The load-bearing sites the datum gate checks.
		datumSamples = buildDatumSamples(),
	}
end

--------------------------------------------------------------------------------
-- build(target, cfg) → APPLIES the plan. Touches Terrain / Lighting / Workspace. Called ONLY by
-- GameServer + the M2 harness, NEVER by a test. THIN and obviously-correct.
--------------------------------------------------------------------------------
function WorldGen.sculpt(terrain, plan)
	-- CATCH SLAB (P3) — FIRST, under everything. A thin hidden rock slab spanning the whole
	-- reachable world (±REACHABLE_RADIUS, matching the legacy baseplate), top at CATCH_FLOOR_Y.
	-- Nothing that grazes off a solid edge into a void gap can fall past it, so the -200 failsafe
	-- can never fire on a reachable column. It sits far below the water floors (-10/-12), so lakes
	-- still read. This is the void-death fix — see the CATCH_FLOOR_Y comment above.
	terrain:FillBlock(
		CFrame.new(0, CATCH_FLOOR_Y - CATCH_THICKNESS / 2, 0),
		Vector3.new(REACHABLE_RADIUS * 2, CATCH_THICKNESS, REACHABLE_RADIUS * 2),
		Enum.Material.Rock)

	-- FLOOR — a flat grass slab, top at the datum Y=0, across the whole playable bowl.
	local floorTop, floorBottom = 0, -80
	terrain:FillBlock(
		CFrame.new(0, (floorTop + floorBottom) / 2, 0),
		Vector3.new(FLAT_R * 2, floorTop - floorBottom, FLAT_R * 2),
		Enum.Material.Grass)

	-- A leafy-grass inner disc for the fire-forest floor (cosmetic paint).
	terrain:FillBlock(
		CFrame.new(0, -1, 0),
		Vector3.new(2800, 4, 2800),
		Enum.Material.LeafyGrass)

	-- RIM — a ring of rock blocks whose height follows the bowl profile. Replaces the primitive
	-- mountain rings. Coarse by design; M3 refines. Each block is rotated to face the centre.
	local steps = 48
	local r = (FLAT_R + RIM_PEAK_R) / 2
	for i = 1, steps do
		local a = (i / steps) * math.pi * 2
		local px, pz = math.cos(a) * r, math.sin(a) * r
		local h = plan.heightAt(px, pz)
		local w = (2 * math.pi * r) / steps * 1.6
		terrain:FillBlock(
			CFrame.new(px, h / 2 - 40, pz) * CFrame.Angles(0, -a, 0),
			Vector3.new(w, h + 80, w),
			Enum.Material.Rock)
	end

	-- WATER — CARVE the column clear first (else the -80..0 grass slab lids the in-slab lake under
	-- a 2-stud grass roof → invisible water), THEN the solid floor (invariant ②), THEN the water.
	for _, body in ipairs(plan.water) do
		local reg = body.region
		local cx, cz = (reg.minX + reg.maxX) / 2, (reg.minZ + reg.maxZ) / 2
		local sx, sz = reg.maxX - reg.minX, reg.maxZ - reg.minZ
		local floorBase = body.floorY - 40 -- solid rock from here up to floorY
		-- 1) clear everything in the column from floorBase up to just above the surface.
		local carveTop = body.surfaceY + 2
		terrain:FillBlock(
			CFrame.new(cx, (floorBase + carveTop) / 2, cz),
			Vector3.new(sx, carveTop - floorBase, sz),
			Enum.Material.Air)
		-- 2) the solid floor.
		terrain:FillBlock(
			CFrame.new(cx, (body.floorY + floorBase) / 2, cz),
			Vector3.new(sx, body.floorY - floorBase, sz),
			Enum.Material.Rock)
		-- 3) the water column, its surface now exposed.
		terrain:FillBlock(
			CFrame.new(cx, (body.floorY + body.surfaceY) / 2, cz),
			Vector3.new(sx, body.surfaceY - body.floorY, sz),
			Enum.Material.Water)
	end
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

	-- TERRAIN — clear then sculpt the valley + rim + water.
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then
		terrain:Clear()
		WorldGen.sculpt(terrain, plan)
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

	-- LIGHTING RIG v2.
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
