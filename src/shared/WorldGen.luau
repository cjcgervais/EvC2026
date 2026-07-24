--!nonstrict
--[[
	WorldGen.luau — the Ember Valley Terrain world + lighting rig (Phase V). M1 built the CORRECT but
	plain valley (flat datum floor, a coarse rim, boxy lakes). M1.5 (the Content Pass) turned that plain
	bowl into a FINISHED-looking valley. The open-horizon packet then REMOVED the enclosing rim wall
	(Chad: "an arena instead of the outdoors") and replaced it with a BROKEN, OPEN surround: low rolling
	foothills that crest then fall away, a thin falloff collar dropping into the haze, distant non-solid
	backdrop mountains in clusters (real sky gaps between them), and a true open west sea horizon — a
	river from the waterfall to the lake, de-boxed water with beaches, deterministic material patchwork,
	micro relief, and a golden-hour rig, all WITHOUT touching any datum number. Every new feature is DATA
	produced by plan() and applied by sculpt()/build(); plan() stays pure and deterministic (no Instances,
	no services, NO math.random).

	WHY THE SPLIT (this is what makes the world headlessly gated):
	Lune's @lune/roblox cannot build Terrain or set Lighting, so WorldGen is two halves —

	  • WorldGen.plan(cfg) → a PURE data table. No Instances, no services, no workspace, no
	    math.random; deterministic given cfg. This is the ONLY half the Tier-4 specs exercise.
	    It carries the whole world as data: the bowl profile heightAt(x,z), the water bodies (each with
	    a SOLID floor), the broken foothill ring + falloff collar + distant mountain Parts, the river
	    polyline, the paint patchwork, the micro relief, the lighting + terrain-style property values,
	    the load-bearing datumSamples, and — the single source of truth for the fill-budget gate —
	    `sculptOps`, the flat ordered list of terrain fill primitives that sculpt() literally replays.

	  • WorldGen.sculpt/applyStyle/applyLighting/build → APPLY the plan (touch Terrain/Lighting/
	    Workspace). Called ONLY by GameServer (and the future M2 edit-mode harness), NEVER by a test.
	    THIN and obviously-correct: sculpt() is a dumb interpreter over plan.sculptOps.

	THE INVARIANTS (each a LOGIC fact wearing art clothes; each with its machine gate in
	tests/worldgen.spec.luau):
	  ① DATUM — ground datum is Y=0. Spawn (±1200), the fire-grove annulus, the pad approach toward
	    (1150,0), the perch band and the y=0 thermal ring are ALL tuned to it, so the playable floor
	    (r < FLAT_R) stays within ±8 of datum. Relief inside r<3400 is MICRO ONLY (mounds ≤6 studs);
	    outcrops are the exception, restricted to r1700-3000 and ≥120 from every datum sample. All big
	    relief lives on the broken foothill surround (r > FLAT_R), which crests low (≤~320) then falls
	    away — an open landscape, not an enclosing wall.
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
-- OPEN-HORIZON PROFILE (open-horizon packet) — the pure continuous height field. Y=0 is the datum.
-- heightAt backs the datum gate + thermals; the ENCLOSING RIM WALL is gone (Chad: "an arena instead
-- of the outdoors"). The surround now CRESTS at a low broken foothill height then FALLS AWAY toward a
-- hazed horizon, so the world reads as open outdoors, not a bowl with a lid. The discrete sculpted
-- foothills (buildFoothills) and the distant backdrop mountains (buildMountainRange, sculpted terrain)
-- carry the actual silhouette; this function is DATA for gates/thermals only — never sculpted directly.
--------------------------------------------------------------------------------
local FLAT_R       = 3400   -- flat playable radius: spawn box, grove annulus, perch band, thermal ring(3200) all inside
local FOOTHILL_R   = 4300   -- radius of the foothill crest (heightAt only; buildFoothills sculpts near here)
local FOOTHILL_CREST = 220  -- foothill crest height (studs above datum) at full, non-west-arc amplitude
local FALLOFF_R    = 6500   -- radius by which the ground has fallen back down to FALLOFF_Y
local FALLOFF_Y    = -90    -- Y the ground reaches at FALLOFF_R — visibly dropping, not walling off
local OUTER_FADE_R = 8500   -- radius by which the ground finishes settling at OUTER_FAR_Y
local OUTER_FAR_Y  = -120   -- far outer plain Y — meets the haze/catch-floor level
local FLOOR_RELIEF = 4      -- max |dip| of the shallow playable bowl (kept < the datum gate's 8-stud band)

-- P3 CATCH FLOOR — a single hidden global slab under the whole reachable world so a graze-slide off
-- any solid edge into a void gap falls at most to CATCH_FLOOR_Y (not past the -200 failsafe). S51
-- BootClock fix: this used to be a terrain FillBlock (the single biggest sculpt-time cost for geometry
-- that's NEVER SEEN); it's now a single invisible queryable Part (see buildCatchFloorPart below) —
-- CATCH_THICKNESS is that Part's Size.Y.
local CATCH_FLOOR_Y     = -120
local CATCH_THICKNESS    = 20
-- FIX 4 (S51 red-team, P3 safety hole): the far mountain clusters sit at r≈8200 with jitter/geometry
-- offset out to ≈8700-8750 (old WedgePart backdrop), but this used to be 8000 — the catch-floor Part
-- span (±REACHABLE_RADIUS) fell SHORT of the mountains it's supposed to backstop, so a bird lured out
-- past the backdrop that descends falls past the net straight to the unconditional -200 kill (the only
-- lethal mechanism in rescue). Raised with margin past the outermost mountain Part; the catch floor is a
-- single Part now (zero sculpt cost), so widening it costs nothing.
-- §2 bar packet: 9500 → 9800. buildMountainRange() now sculpts real terrain peaks (not Parts) whose
-- geometry reaches plan.mountainMaxR ≈ 9000 (radial jitter + footprint + body-ball jitter margin,
-- computed live, not eyeballed) — REACHABLE_RADIUS must clear that with the same ≥500-stud P3 margin.
local REACHABLE_RADIUS   = 9800

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

--------------------------------------------------------------------------------
-- PURE HASH — the one source of "randomness". Deterministic; NOT math.random (the world must be
-- byte-identical on every boot and inside the headless spec). n01(i) ∈ [0,1). Declared BEFORE
-- surfaceY/foothillAmp because both consume it (Lua locals must exist before an earlier-defined
-- function body can close over them as locals, not globals).
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

-- WEST_ARC — the declared open azimuth arc: the foothill/collar amplitude dips here so the WestSea
-- reads as a true open-water horizon instead of a peak gap in a wall. Centered due west (az180).
local WEST_ARC = { azMin = 150, azMax = 210, center = 180, halfWidth = 30 }

-- foothillAmp(ad) → azimuthal amplitude ∈ [WEST_ARC_MIN_AMP, 1.0] for the foothill crest at azimuth ad
-- (degrees). 1.0 everywhere except a smoothstepped dip centered on WEST_ARC, which bottoms out at
-- WEST_ARC_MIN_AMP directly west — that's the open sightline to the WestSea. Shared by surfaceY (the
-- continuous gate/thermal field) and buildFoothills (the discrete sculpted hills), so the two always
-- agree on WHERE the world opens up.
local WEST_ARC_MIN_AMP = 0.12
local function foothillAmp(ad)
	local d = math.abs(angDiff(ad, WEST_ARC.center))
	if d >= WEST_ARC.halfWidth then return 1.0 end
	local u = d / WEST_ARC.halfWidth -- 0 at due west ... 1 at the arc edge
	local s = u * u * (3 - 2 * u)
	return WEST_ARC_MIN_AMP + (1.0 - WEST_ARC_MIN_AMP) * s
end

-- surfaceY(x,z) → the SOLID terrain surface height at world XZ. Pure; no state, no random. Data for
-- gates/thermals only — the outer branches are NEVER sculpted directly (buildFoothills/
-- buildFalloffCollar/buildMountainRange carry the actual open-horizon geometry).
local function surfaceY(x, z)
	local r = math.sqrt(x * x + z * z)
	if r <= FLAT_R then
		local t = r / FLAT_R
		return -FLOOR_RELIEF * (1 - t * t)
	end
	local ad = math.deg(math.atan2(z, x)) % 360
	local crest = FOOTHILL_CREST * foothillAmp(ad)
	if r <= FOOTHILL_R then
		local u = (r - FLAT_R) / (FOOTHILL_R - FLAT_R)
		local s = u * u * (3 - 2 * u)
		return s * crest
	elseif r <= FALLOFF_R then
		local u = (r - FOOTHILL_R) / (FALLOFF_R - FOOTHILL_R)
		local s = u * u * (3 - 2 * u)
		return crest + (FALLOFF_Y - crest) * s
	elseif r <= OUTER_FADE_R then
		local u = (r - FALLOFF_R) / (OUTER_FADE_R - FALLOFF_R)
		local s = u * u * (3 - 2 * u)
		return FALLOFF_Y + (OUTER_FAR_Y - FALLOFF_Y) * s
	else
		return OUTER_FAR_Y
	end
end

--------------------------------------------------------------------------------
-- FOOTHILLS — the only new sculpted terrain (open-horizon packet). A BROKEN ring of low rolling
-- hillforms replaces the enclosing rim wall: an inner band near FOOTHILL_R and a lower, phase-offset
-- outer band behind it. Deliberately LOW (crest ≤ ~320) so it reads as landscape, not a wall — and the
-- WEST_ARC dips toward WEST_ARC_MIN_AMP so the WestSea is a genuine open horizon, not a gap in a ring.
-- A handful of hills are also forced near-zero regardless of azimuth (sightline gaps), so the ring
-- reads broken everywhere, not just at the west opening. Solid B() fills — low enough that the buried
-- core is cheap (no rim-shell hollowing needed here).
--------------------------------------------------------------------------------
local FOOTHILL_BASE_Y = -30 -- hill bases bury slightly below datum; crest is BASE_Y + crest/2 up
local FOOTHILL_INNER_R, FOOTHILL_INNER_N = 3950, 30
local FOOTHILL_OUTER_R, FOOTHILL_OUTER_N = 5100, 24

-- buildFoothills() → a flat array of hill records {x,y,z,sx,sy,sz,yaw,mat,crest,ad,band,gap}. Pure.
local function buildFoothills()
	local hills = {}

	-- Inner band: the primary broken ring, crest 60-320 (jittered + west-arc/gap dips).
	for i = 0, FOOTHILL_INNER_N - 1 do
		local ad = (i / FOOTHILL_INNER_N) * 360
		local a = math.rad(ad)
		local amp = foothillAmp(ad)
		local isGap = (i % 6 == 0) -- ~5 of 30 forced near-zero: sightline gaps independent of the west arc
		local crest
		if isGap then
			crest = 15 + n01(i * 11 + 5) * 20 -- 15..35, near-zero
		else
			local jitter = 0.6 + n01(i * 7 + 3) * 0.8 -- 0.6..1.4
			-- FIX 5 (S51 red-team, west berm): the +60 FLOOR used to sit OUTSIDE the amp scaling, so even at
			-- the west arc's amp≈0.12 minimum every hill still carried a continuous ~60-stud berm and the
			-- sea horizon read walled at low altitude. Scale the whole base by amp so west-arc hills nearly
			-- vanish (amp≈0.12 → ~8-15ish); the explicit gap hills (isGap, above) still force hard breaks.
			crest = math.clamp((60 + n01(i * 13 + 9) * 260 * jitter) * amp, 8, 320)
		end
		local px, pz = math.cos(a) * FOOTHILL_INNER_R, math.sin(a) * FOOTHILL_INNER_R
		local w = 850 * (0.85 + n01(i * 17 + 21) * 0.25)     -- footprint width, ≈850
		local depth = 700 * (0.85 + n01(i * 19 + 27) * 0.25) -- radial depth, ≈700
		local mat = (n01(i * 23 + 31) < 0.6) and "Grass" or "Ground" -- Grass/Ground blend; the toe gets LeafyGrass below
		hills[#hills + 1] = {
			x = px, z = pz, y = FOOTHILL_BASE_Y + crest / 2, sx = w, sy = crest - FOOTHILL_BASE_Y, sz = depth,
			yaw = -a, mat = mat, crest = crest, ad = ad, band = "inner", gap = isGap,
		}
	end

	-- Outer band: lower, phase-offset half a step so it layers behind the inner band, trending downward.
	for i = 0, FOOTHILL_OUTER_N - 1 do
		local ad = ((i + 0.5) / FOOTHILL_OUTER_N) * 360
		local a = math.rad(ad)
		local amp = foothillAmp(ad)
		local crest = math.clamp((40 + n01(i * 29 + 41) * 100) * amp, 15, 140)
		local px, pz = math.cos(a) * FOOTHILL_OUTER_R, math.sin(a) * FOOTHILL_OUTER_R
		local w = 780 * (0.85 + n01(i * 31 + 43) * 0.25)
		local depth = 600 * (0.85 + n01(i * 37 + 53) * 0.25)
		hills[#hills + 1] = {
			x = px, z = pz, y = FOOTHILL_BASE_Y + crest / 2, sx = w, sy = crest - FOOTHILL_BASE_Y, sz = depth,
			yaw = -a, mat = "Ground", crest = crest, ad = ad, band = "outer", gap = false,
		}
	end

	return hills
end

-- buildFoothillToe() → a thin LeafyGrass blend band right where the inner hills meet the meadow floor,
-- so the foothills grow OUT of the meadow instead of butting against it as a bare seam (kept from the
-- old rim's foot-band idea, resized to the foothills' much lower toe radius).
local function buildFoothillToe()
	local toe = {}
	local TOE_N, innerR = 32, FOOTHILL_INNER_R - 480
	for i = 0, TOE_N - 1 do
		local ad = (i / TOE_N) * 360
		local a = math.rad(ad)
		local band = 80 + n01(i * 41 + 5) * 70 -- 80..150 studs of radial rise, jittered per wedge
		local mid = innerR + band / 2
		local w = (2 * math.pi * mid) / TOE_N * 1.3
		local mat = (n01(i * 31 + 71) < 0.55) and "Grass" or "LeafyGrass"
		toe[#toe + 1] = { x = math.cos(a) * mid, y = -2, z = math.sin(a) * mid, sx = w, sy = 6, sz = band, yaw = -a, mat = mat }
	end
	return toe
end

-- S52 horizon-iterate-5 (machine-eyes captures/S52-mountains3, rim-nadir/overview: sunset-lit tile SIDE
-- faces read as bright red/pink rectangles along the annulus, and top-down seams showed straight through
-- to the void) — FIX: the 3 skin builders below (collar/groundSkin/midGroundSkin) all step down in Y
-- band-by-band; wherever a band's Y-drop from its neighbor exceeded that band's thickness, the lower
-- band's top face fell BELOW the upper band's bottom face and a top-down ray slipped through the gap (or
-- grazed the upper band's now-exposed, sunset-lit side wall). Two shared helpers fix this at the source
-- instead of hand-tuning each skin separately:
--   skinBandCount(innerY, outerY, thick) → the minimum radial band count so consecutive bands' Y step is
--     ALWAYS ≤ the band thickness (ceil(|range| / thick), floored at 2 so every skin keeps its gentle
--     multi-band descent rather than collapsing to one flat shelf) — the necessary-AND-SUFFICIENT no-gap
--     condition: a step of exactly `thick` still puts the lower band's top face exactly at the upper
--     band's bottom face (fully touching, zero seam). A tighter half-thickness margin was tried first but
--     is NOT achievable inside the immovable ≤1100 op / ≤4.2e10 volume budget at these thicknesses (the
--     op/volume cost scales with band count, and half-thickness needs ~2x the bands full-thickness does —
--     measured 1093→1135+ ops and 3.970e10→4.399e10 volume just from the collar+midSkin band counts that
--     rule demanded); full-thickness is the honest no-gap floor and lands the budget in range.
--   ringTileCount(rMid) → the minimum azimuthal tile count for a ring at radius rMid so each tile's
--     tangential chord (with SKIN_AZ_OVERLAP applied) stays at/under MAX_FILL_EXTENT — sized PER BAND
--     (not one shared N for the whole skin) so inner, shorter-circumference bands don't carry the outer
--     band's tile count. This is what keeps the extra bands the Y-step fix requires from blowing the
--     ≤1100 fill-op budget: a shared worst-case N would cost far more ops than right-sizing each ring.
local SKIN_AZ_OVERLAP = 1.25 -- widened from 1.15x (S52 FIX 3) — more tangential tile overlap, fewer seam reads
local function skinBandCount(innerY, outerY, thick)
	return math.max(2, math.ceil(math.abs(outerY - innerY) / thick))
end
local function ringTileCount(rMid)
	return math.max(6, math.ceil((2 * math.pi * rMid * SKIN_AZ_OVERLAP) / MAX_FILL_EXTENT))
end

--------------------------------------------------------------------------------
-- FALLOFF COLLAR (open-horizon packet, replaces the old APRON) — a thin Ground skin, r≈5400→6600,
-- descending ≈-40 → ≈-110 in several radial bands (see skinBandCount above) so the ground visibly falls
-- toward the haze with no Y-step gap. THIN by design: nothing is ever landed on out here (the P3 catch
-- floor backstops every void), so this only needs to read right from altitude, not hold weight — keeping
-- it a shallow skin (not a solid ramp) is what keeps its sculpt-volume cost bounded instead of the
-- ≈2-4e9 a full solid ramp would cost. Past r≈6600 the ground is OPEN (no more terrain) — haze + the
-- distant Part mountains carry the rest of the horizon.
--------------------------------------------------------------------------------
-- Volume-budget trim (order item 3): outer radius 6800→6600 (matched by GROUND_SKIN_INNER_R below, so
-- the collar and groundSkin still meet with no radial gap) — trims the collar's outermost, largest-rMid
-- band slices, part of the headroom needed to clear the world-total gate.
local FALLOFF_INNER_R, FALLOFF_OUTER_R = 5400, 6600
-- FIX 3 (S51 horizon-iterate-2, machine-eyes: "stepped green cliffs" in 13_mountains-backdrop): the 2
-- radial bands used to butt edge-to-edge at a fixed Y, so every band boundary read as a hard terraced
-- rectangular step. Sunk both ~15 studs deeper (below the sightline/haze), and the bands now overlap
-- radially instead of just touching (see FALLOFF_OVERLAP below) so there's no gap/step between them.
-- FIX 1 (S52 machine-eyes, "sunset-sky void glowing pink BETWEEN tiles" from top-down): the per-tile Y
-- jitter this used to carry (±6 studs) combined with the band gaps to let a top-down view see straight
-- through the seams to the sky below. Y jitter is REMOVED entirely — every tile in a band now sits at
-- the exact same yBase, and the bands are fully solid/overlapping (radially via FALLOFF_OVERLAP,
-- tangentially via the SKIN_AZ_OVERLAP chord widen below) so there is no gap anywhere in the collar from
-- any angle.
local FALLOFF_INNER_Y, FALLOFF_OUTER_Y = -55, -125
-- S52 horizon-iterate-5: THICK 14→20 (thicker skin = more Y slack before a step exposes a gap/side
-- face), OVERLAP 80→200 (radial overlap floor). BANDS is now DERIVED from skinBandCount so the Y step
-- between consecutive bands is always ≤ FALLOFF_THICK — was a fixed 2, now computed (lands at 4 for this
-- span/thickness). FALLOFF_N (fixed 28) is GONE: per-band tile count now comes from ringTileCount
-- (right-sized per band's own rMid) so the extra bands don't multiply the whole skin's op cost as much.
local FALLOFF_THICK = 20
local FALLOFF_OVERLAP = 200 -- radial overlap added to each tile's depth so neighboring bands overlap, not step
local FALLOFF_BANDS = skinBandCount(FALLOFF_INNER_Y, FALLOFF_OUTER_Y, FALLOFF_THICK)

-- buildFalloffCollar() → a flat array of thin skin records {x,y,z,sx,sy,sz,yaw,mat}. Pure.
local function buildFalloffCollar()
	local tiles = {}
	local bandDepth = (FALLOFF_OUTER_R - FALLOFF_INNER_R) / FALLOFF_BANDS
	local tileSz = bandDepth + FALLOFF_OVERLAP -- FIX 3(c): wider than the band's own slice → overlaps its neighbor
	for bi = 0, FALLOFF_BANDS - 1 do
		local rMid = FALLOFF_INNER_R + bandDepth * (bi + 0.5)
		local u = (bi + 0.5) / FALLOFF_BANDS
		local yBase = FALLOFF_INNER_Y + (FALLOFF_OUTER_Y - FALLOFF_INNER_Y) * u
		local n = ringTileCount(rMid)
		for i = 0, n - 1 do
			-- stagger each band's tile seams by half a step so neighboring rings' seams don't line up radially.
			local ad = ((i + bi * 0.5) / n) * 360
			local a = math.rad(ad)
			local chord = (2 * math.pi * rMid) / n * SKIN_AZ_OVERLAP
			local hSeed = bi * 1000 + i * 7 + 41
			-- FIX 3: blend the INNERMOST ring (bi==0, where the collar meets the foothill toe) toward Grass
			-- ~half the time so there's no hard green(foothill)→brown(Ground collar) ring; the outer bands
			-- (further from the foothills) stay pure Ground.
			local mat = (bi == 0 and n01(hSeed + 3) < 0.5) and "Grass" or "Ground"
			tiles[#tiles + 1] = {
				x = math.cos(a) * rMid, y = yBase, z = math.sin(a) * rMid,
				sx = chord, sy = FALLOFF_THICK, sz = tileSz, yaw = -a, mat = mat,
			}
		end
	end
	return tiles
end

--------------------------------------------------------------------------------
-- GROUND SKIN (S52 FIX 2) — a thin continuous Ground shell past the falloff collar's outer edge
-- (r≈6600) out to r≈8800 (under the mountain clusters), sealing every top-down sightline that would
-- otherwise fall straight through to void/skybox (machine-eyes: "top-down void past the collar reads
-- as glowing pink sky"). Descends gently from the collar's outer Y (-125) to -140, tiled azimuthally
-- the same overlapping way as the collar (bands derived so the Y step between them stays within a
-- thickness, radial overlap floor between bands). Nothing is ever landed on out here (P3 catch floor
-- backstops every void); this only needs to read right from altitude, kept thin for sculpt-volume cost.
--------------------------------------------------------------------------------
-- S52 horizon-iterate-5 volume-budget trim (order item 1, iterated further once measured): outer radius
-- 9600→9200→8800 — the mountains sit ≤8750 (see MOUNTAIN_FAR_R + reach below, and any outlier peak
-- reaching past 8800 is itself opaque terrain, so it self-seals), so 8800 still keeps the visible ground
-- covered beneath every mountain cluster while recovering the world-total volume headroom the thicker
-- skins below spend.
local GROUND_SKIN_INNER_R, GROUND_SKIN_OUTER_R = 6600, 8800
local GROUND_SKIN_INNER_Y, GROUND_SKIN_OUTER_Y = -125, -140
-- S52 horizon-iterate-5: THICK 8→16, OVERLAP 40→200. BANDS is now DERIVED (skinBandCount) instead of a
-- fixed 2 — lands at 2 (the floor) for this span/thickness (15-stud Y range needs a step ≤16, so 1 band
-- would technically clear it, but skinBandCount floors at 2 so the skin keeps its gentle multi-band
-- descent). GROUND_SKIN_N (fixed 18) is GONE: per-band tile count now comes from ringTileCount
-- (right-sized per band's own rMid).
-- Volume-budget trim (order item 2): THICK 16→12 — the Y-step gate only needs a band count of 2 either
-- way here (skinBandCount floors at 2, and even ceil(15/12)=2 clears it on its own), so this trim is a
-- pure volume win with zero op cost; still thicker than the pre-fix 8.
local GROUND_SKIN_THICK = 12
local GROUND_SKIN_OVERLAP = 200 -- radial overlap between the skin's own bands AND against the collar's outer edge
local GROUND_SKIN_BANDS = skinBandCount(GROUND_SKIN_INNER_Y, GROUND_SKIN_OUTER_Y, GROUND_SKIN_THICK)

-- buildGroundSkin() → a flat array of thin skin records {x,y,z,sx,sy,sz,yaw,mat}. Pure.
local function buildGroundSkin()
	local tiles = {}
	local bandDepth = (GROUND_SKIN_OUTER_R - GROUND_SKIN_INNER_R) / GROUND_SKIN_BANDS
	local tileSz = bandDepth + GROUND_SKIN_OVERLAP
	for bi = 0, GROUND_SKIN_BANDS - 1 do
		local rMid = GROUND_SKIN_INNER_R + bandDepth * (bi + 0.5)
		local u = (bi + 0.5) / GROUND_SKIN_BANDS
		local yBase = GROUND_SKIN_INNER_Y + (GROUND_SKIN_OUTER_Y - GROUND_SKIN_INNER_Y) * u
		local n = ringTileCount(rMid)
		for i = 0, n - 1 do
			-- stagger seams by half a step per band (matches the collar's staggering) so seams don't stack radially.
			local ad = ((i + bi * 0.5) / n) * 360
			local a = math.rad(ad)
			local chord = (2 * math.pi * rMid) / n * SKIN_AZ_OVERLAP -- same tangential overlap as the collar
			tiles[#tiles + 1] = {
				x = math.cos(a) * rMid, y = yBase, z = math.sin(a) * rMid,
				sx = chord, sy = GROUND_SKIN_THICK, sz = tileSz, yaw = -a, mat = "Ground",
			}
		end
	end
	return tiles
end

--------------------------------------------------------------------------------
-- MID GROUND SKIN (S52 FIX 2) — machine-eyes: top-down views over the annulus r≈3400→5400, BETWEEN the
-- discrete foothills, saw straight past every gap to the sunset-lit catch floor glowing pink far below —
-- the foothills are discrete hillforms (buildFoothills), not a continuous ring, so nothing sealed the
-- ground in between them. This is that seal: a thin continuous Ground band from just under the bowl's
-- flat-floor lip (r≈3350, tucking under the r=3400 playable edge at Y≈-8) descending to r≈5400 (meeting
-- the falloff collar's own top band, Y≈-55 near there — see FALLOFF_INNER_Y), tiled the same overlapping
-- way as buildFalloffCollar/buildGroundSkin (bands derived so the Y step between them is always ≤ the
-- skin's own thickness, tangential chord overlap, radial band overlap) so there is no gap anywhere in
-- the annulus from any azimuth. The dome foothill balls (FIX 1) then sit ON this skin — emitted after it
-- in assembleOps so their Grass reads on top at any overlap.
--------------------------------------------------------------------------------
-- Volume-budget trim: outer radius 5500→5400 (still overlaps the collar's own inner band via the radial
-- OVERLAP floor below, so there is no seam) — a small additional cut alongside the collar/groundSkin
-- trims above, needed to clear the world-total gate once the thicker skins were fully measured.
local MID_SKIN_INNER_R, MID_SKIN_OUTER_R = 3350, 5400
local MID_SKIN_INNER_Y, MID_SKIN_OUTER_Y = -8, -50
-- S52 horizon-iterate-5: THICK 10→16, OVERLAP 80→200. BANDS is now DERIVED (skinBandCount) instead of a
-- fixed 2 — the 42-stud Y range needs a step ≤16, so this lands at 3 bands. MID_SKIN_N (fixed 20) is
-- GONE: per-band tile count now comes from ringTileCount (right-sized per band's own rMid) so the extra
-- bands don't multiply this skin's op cost as much as a shared worst-case N would.
local MID_SKIN_THICK = 16
local MID_SKIN_OVERLAP = 200
local MID_SKIN_BANDS = skinBandCount(MID_SKIN_INNER_Y, MID_SKIN_OUTER_Y, MID_SKIN_THICK)

-- buildMidGroundSkin() → a flat array of thin skin records {x,y,z,sx,sy,sz,yaw,mat}. Pure.
local function buildMidGroundSkin()
	local tiles = {}
	local bandDepth = (MID_SKIN_OUTER_R - MID_SKIN_INNER_R) / MID_SKIN_BANDS
	local tileSz = bandDepth + MID_SKIN_OVERLAP
	for bi = 0, MID_SKIN_BANDS - 1 do
		local rMid = MID_SKIN_INNER_R + bandDepth * (bi + 0.5)
		local u = (bi + 0.5) / MID_SKIN_BANDS
		local yBase = MID_SKIN_INNER_Y + (MID_SKIN_OUTER_Y - MID_SKIN_INNER_Y) * u
		local n = ringTileCount(rMid)
		for i = 0, n - 1 do
			local ad = ((i + bi * 0.5) / n) * 360
			local a = math.rad(ad)
			local chord = (2 * math.pi * rMid) / n * SKIN_AZ_OVERLAP
			tiles[#tiles + 1] = {
				x = math.cos(a) * rMid, y = yBase, z = math.sin(a) * rMid,
				sx = chord, sy = MID_SKIN_THICK, sz = tileSz, yaw = -a, mat = "Ground",
			}
		end
	end
	return tiles
end

--------------------------------------------------------------------------------
-- MOUNTAIN RANGES (§2 bar-compliance packet — real terrain, not Parts). The old backdrop was ~75
-- WedgePart peaks (owner-rejected as "wedge slop" — not built to the visual-quality bar). This replaces
-- their EMISSION with layered Rock/Snow TERRAIN sculpt ops while INHERITING their LAYOUT exactly: a mid
-- ridge (r≈6200, warm Rock, no snow) and a farther, taller, snow-capped range (r≈8200), each in explicit
-- uneven clusters (not an even ring — the gaps BETWEEN clusters are the point) with the far range
-- phase-offset from the mid range so the sky gaps layer instead of stacking, and az=0 forced on the far
-- range (behind the mesa at (1150,0), the waterfall's backdrop peak). The old per-Part warm/cool color
-- ramp is DROPPED — terrain has no per-op color, only a material; Atmosphere's Decay (buildLighting)
-- now carries the near-warm/far-cool aerial-perspective cue on its own. Every mountain sculpt op is
-- tagged feature="mountain" (assembleOps' B/W/L below) so the mountain-volume gate and any future
-- mountain-scoped check can find them without re-deriving the cluster layout.
--------------------------------------------------------------------------------
local MOUNTAIN_MID_R, MOUNTAIN_FAR_R = 6200, 8200
-- Explicit, uneven cluster azimuths (not an evenly-spaced ring) — the gaps BETWEEN clusters are the
-- point. The far range is phase-offset from the mid range so their sky gaps don't stack, and az=0 is
-- forced on the far range: behind the mesa at (1150,0), the waterfall's backdrop peak.
local MOUNTAIN_MID_CLUSTERS = { 20, 95, 150, 230, 300, 345 }
local MOUNTAIN_FAR_CLUSTERS = { 0, 60, 130, 195, 260, 320 }
local MOUNTAIN_RADIAL_JITTER = 200 -- ± studs per peak off its cluster radius (TIGHTENED from ±250)
local MOUNTAIN_AZ_SPREAD = 9       -- ± degrees per peak off its cluster's center azimuth
local MOUNTAIN_FOOT_W_MIN, MOUNTAIN_FOOT_W_MAX = 900, 1500 -- tangential footprint
local MOUNTAIN_FOOT_D_MIN, MOUNTAIN_FOOT_D_MAX = 500, 700  -- radial footprint
local MOUNTAIN_MID_H_MIN, MOUNTAIN_MID_H_MAX = 700, 1400
-- Far height ceiling TRIMMED 2400→2200 (budget trim 3 of 3 — see buildMountainRange's volume note).
local MOUNTAIN_FAR_H_MIN, MOUNTAIN_FAR_H_MAX = 1600, 2200
-- Base-block height fraction TRIMMED 0.25→0.15 (budget trim 1 of 3; the measured Σ needed a deeper
-- cut than 0.20 to clear the whole-world total gate with real margin — see buildMountainRange's note).
-- S52 FIX 3 (machine-eyes: mountain base blocks read as giant flat green/grass walls, worst on the
-- az=0 waterfall-backdrop cluster — the rectangular base mass poked above the surrounding ground as a
-- sheer straight-edged slab): sunk further, from a flat 0.15*peakH fraction to min(0.08*peakH, 120) —
-- grounding-only, hidden under the body-spine's lowest balls, never part of the visible silhouette (the
-- ball spine + wedge cap carry that). MOUNTAIN_BASE_FRAC/MOUNTAIN_BASE_MAX are now the two terms of
-- that min(), applied directly in emitMountainPeak.
local MOUNTAIN_BASE_FRAC = 0.08
local MOUNTAIN_BASE_MAX = 120
-- Body-spine ball count. Far TRIMMED 7→6 to match mid (budget trim 2 of 3); both then TRIMMED 6→5
-- (measured Σ needed a deeper cut here too — the body spine is the dominant volume term). S52 FIX 3
-- shrank the base block (mountain-op volume 2.942e10 -> 2.723e10 measured), but that stayed
-- comfortably above the [2.4e10,3.6e10] gate's floor, so the far-peak body-ball count was NOT bumped
-- back to 6 (the spec's contingency for a floor breach that didn't happen — see the sculpt volume test).
local MOUNTAIN_MID_BODY_N, MOUNTAIN_FAR_BODY_N = 5, 5

-- localOffset(x,z,yaw,ox,oz) → world XZ of a local-frame offset (ox,oz) under a Y-yaw. Same right-hand
-- rotation convention assembleOps' B() tiler derives in detail (see its comment): local +X → world
-- (cos yaw, -sin yaw), local +Z → world (sin yaw, cos yaw). Shared with yawTangent below so mountain
-- body-spine jitter and B()'s tiler agree on what "yaw" means.
local function localOffset(x, z, yaw, ox, oz)
	local c, s = math.cos(yaw), math.sin(yaw)
	return x + ox * c + oz * s, z - ox * s + oz * c
end

-- yawTangent(az) → the yaw (radians) under which local +Z reads as WORLD TANGENTIAL and local +X reads
-- as WORLD RADIAL at azimuth az — the same convention the old WedgePart emitPeak used (yaw = -az), kept
-- so a peak's ridge line still runs tangential (a triangle silhouette from the play area) and its base
-- mass/jitter still run radial.
local function yawTangent(az) return -az end

-- mountainClusterPeaks(out, centerAz, r, hMin, hMax, snow, bodyN, seedBase) — appends 2-3 peak
-- descriptor records to `out` for one cluster. Pure. Mirrors the old emitCluster's spread/jitter/seed
-- pattern: overlapping peaks within ±9° of the cluster center read as one jagged ridge mass, not
-- separate boxes.
local function mountainClusterPeaks(out, centerAz, r, hMin, hMax, snow, bodyN, seedBase)
	local n = 2 + math.floor(n01(seedBase) * 2) -- 2..3 overlapping peaks per cluster
	for k = 1, n do
		local h1 = seedBase + k * 37
		local az = math.rad(centerAz + (n01(h1) - 0.5) * (2 * MOUNTAIN_AZ_SPREAD))
		local rr = r + (n01(h1 + 3) - 0.5) * (2 * MOUNTAIN_RADIAL_JITTER)
		local peakH = hMin + n01(h1 + 7) * (hMax - hMin)
		local footW = MOUNTAIN_FOOT_W_MIN + n01(h1 + 11) * (MOUNTAIN_FOOT_W_MAX - MOUNTAIN_FOOT_W_MIN)
		local footD = MOUNTAIN_FOOT_D_MIN + n01(h1 + 29) * (MOUNTAIN_FOOT_D_MAX - MOUNTAIN_FOOT_D_MIN)
		local baseY = -20 + (n01(h1 + 31) - 0.5) * 8 -- ±4, bury slightly into the foothill toe, varied
		local px, pz = math.cos(az) * rr, math.sin(az) * rr
		out[#out + 1] = {
			px = px, pz = pz, az = az, peakH = peakH, footW = footW, footD = footD,
			snow = snow, baseY = baseY, bodyN = bodyN, seed = h1,
			-- reach: how far this peak's own geometry can extend past its center radius — radial half-
			-- footprint, plus the body-spine's radial jitter margin, plus a flat safety pad.
			reach = rr + footD / 2 + 0.16 * footW + 400,
		}
	end
end

-- buildMountainRange() → { peaks = {...descriptors...}, maxR = number }. Pure. maxR is the outermost
-- reach any peak's geometry extends to; REACHABLE_RADIUS (P3) must clear it with margin. Volume budget:
-- the naive (untrimmed: base frac 0.25, far body-ball N=7, far H ceiling 2400) numbers measure ≈4.14e10
-- studs³ mountain / ≈5.19e10 world total across ≈278 mountain ops — over both the mountain gate
-- ([2.4e10, 3.6e10]) and the whole-world gate ([1.8e10, 4.2e10]). The design's 3 trims (far H ceiling
-- 2400→2200, far body-ball N 7→6) plus a measured-deeper base-fraction cut (0.25→0.15, not just →0.20 —
-- the body-spine balls turned out to be the dominant volume term, so the naive 0.20 stop still left the
-- world-total gate with almost no margin) and body-ball N dropped to 5 on BOTH ranges (not just far)
-- land it at mountainVol≈2.96e10 (inside the [2.8e10,3.0e10] target band) / worldVol≈4.02e10.
-- S52 FIX 3 (machine-eyes: mountain base blocks read as flat green/grass walls) then sunk the base
-- block from 0.15*peakH to min(0.08*peakH,120), which alone trims mountainVol; S52 FIX 2's new Ground
-- skin (buildGroundSkin, r≈6800→9600) added ≈1.2e9 of world-total volume, landing worldVol≈3.97e10.
-- S52 horizon-iterate-5 (thicker/overlapped collar+groundSkin+midSkin skins, see skinBandCount above)
-- then added another ≈2e9 despite the outer-radius/thickness trims documented on each skin, landing
-- worldVol≈4.19e10 (still inside [1.8e10,4.2e10], but with thin remaining headroom — see
-- tests/worldgen.spec.luau's "sculpt volume" gate for the live, test-asserted numbers). mountainVol is
-- unchanged by that packet (≈2.72e10, still comfortably inside [2.4e10,3.6e10]).
local function buildMountainRange()
	local peaks, maxR = {}, 0
	for ci, az in ipairs(MOUNTAIN_MID_CLUSTERS) do
		mountainClusterPeaks(peaks, az, MOUNTAIN_MID_R, MOUNTAIN_MID_H_MIN, MOUNTAIN_MID_H_MAX, false, MOUNTAIN_MID_BODY_N, ci * 500)
	end
	for ci, az in ipairs(MOUNTAIN_FAR_CLUSTERS) do
		mountainClusterPeaks(peaks, az, MOUNTAIN_FAR_R, MOUNTAIN_FAR_H_MIN, MOUNTAIN_FAR_H_MAX, true, MOUNTAIN_FAR_BODY_N, 3000 + ci * 500)
	end
	for _, p in ipairs(peaks) do
		if p.reach > maxR then maxR = p.reach end
	end
	return { peaks = peaks, maxR = maxR }
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
		-- The distant WestSea past the open west foothill arc — a true open-water horizon now that the
		-- rim wall is gone. Still a box carve (a coastline, not a pond).
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

	-- 1) Rocks along the foothill base ring (r 3150..3350, safely inside SCATTER_MAX_R). sizeMul 1.3:
	-- these rocks read bigger than shore/meadow rocks (both role "rock") at flight altitude.
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
		-- Open-horizon packet: Density/Haze bumped so the far foothill/mountain backdrop dissolves into
		-- aerial haze instead of reading as a hard cutoff. S51 horizon-iterate-2 (machine-eyes FIX 2):
		-- that first pass overshot — everything past the bowl, even near foothills, swam in salmon-pink.
		-- Pulled Density/Haze back down and shifted Decay cooler/bluer (less warm-pink, more cool blue-
		-- gray) so depth reads in distinct layers: warm golden-hour valley near, mid ridge still legible,
		-- far peaks half-dissolved into cool haze, and real sky gaps between clusters read as SKY, not
		-- pink soup.
		-- §2 bar packet: thinned again, 0.14→0.09 / 2.4→1.8 — the mountains are now real sculpted
		-- terrain out to r≈9000 (not WedgePart slop at ~8700), and the far-read criterion needs those
		-- ranges to stay LEGIBLE as layered ridgelines from altitude, not dissolve into a haze wall.
		-- Decay (70,88,150) is KEPT as-is — it's now the SOLE carrier of the near-warm/far-cool cue
		-- (the old per-Part color ramp is gone). ClockTime/Bloom/ColorCorrection/Brightness (locked
		-- golden-hour rig) stay untouched.
		Atmosphere = {
			Density = 0.09, Offset = 0.6, Haze = 1.8, Glare = 0.4,
			Color = Color3.fromRGB(255, 205, 165),
			Decay = Color3.fromRGB(70, 88, 150),
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
		-- S52 FIX 3 (machine-eyes: water reads hot pink under the sunset sky): WaterColor sunk deeper
		-- blue-teal (was 52,132,150 — still too light to hold its own hue against a warm sunset
		-- reflection) and WaterTransparency now explicitly set (was UNSET, so Terrain defaulted to
		-- 0.3 — a very see-through surface lets the pink sky/Atmosphere show straight through instead
		-- of the water's own color). WaterReflectance kept at 0.35 (already tuned) so the sunset still
		-- warms the surface without going full pink.
		water = { color = { 35, 110, 140 }, reflectance = 0.35, transparency = 0.15, waveSize = 0.12, waveSpeed = 14 },
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
-- FOOTHILL DOME EMISSION (S52 FIX 1) — machine-eyes: the old single-B()-block-per-hill emission read as
-- giant rectangular grass mesas with vertical ruler-straight walls up close (worst on the mountains-north
-- / fire-line vantages). This turns each hill record's LAYOUT (unchanged: buildFoothills still owns
-- x/z/crest/ad/band/gap — the counts, azimuths, crest heights and forced gaps are exactly as before) into
-- a rounded hillform instead: overlapping flattened L() balls (the same "sunk center so the PROTRUSION
-- above local ground equals a height" trick as the MOUNDS micro-relief, L(x, protrude-r, z, r, mat)) —
-- one tall ball at the hill's own center (apex = h.crest), an overlapping shoulder ball offset tangentially
-- (local +Z under h.yaw — the yawTangent convention shared with the mountain body-spine, so the shoulder
-- reads as spreading ALONG the ring, not radially in/out) for inner-band hills (closer, worst up close —
-- the ones machine-eyes actually flagged), and a wider, flatter Ground toe ball at every hill's base for
-- color grounding (Grass dome, Ground foot). Outer-band hills are trimmed to just the center ball + toe
-- (no shoulder) to hold the ≤1100 fill-budget gate — the outer band sits further out/lower priority.
-- Every ball radius is clamped [150,400] off the hill's own footprint so it individually clears
-- MAX_FILL_VOLUME on its own (no B()-style auto-tiling needed for L()). Pure; no Instances.
--------------------------------------------------------------------------------
-- Ball radius scales off the hill's own footprint per the 0.35-0.45x spec, but PULLED to the low end
-- (0.28, plus modest shoulder/toe multipliers below <1.0) — a FULL L() sphere's volume (4/3*pi*r^3)
-- is dramatically more expensive than the flattened block it replaces for the same visible footprint
-- (most of the sphere is buried, invisible, but still counted by the sculpt-volume gate), so hitting the
-- spec's literal 0.35-0.45x/1.18x toe multiplier blew the whole-world volume gate by ~1.2e10 studs³ in
-- practice (measured). Pulling the scale down keeps the rounded-dome READ (still radius-scaled off each
-- hill's own footprint, still clamped 150-400) while landing inside [1.8e10,4.2e10].
local FOOTHILL_BALL_MIN_R, FOOTHILL_BALL_MAX_R = 150, 400
local FOOTHILL_BALL_RADIUS_FRAC = 0.28

local function buildFoothillDome(hills)
	local balls = {}
	for hi, h in ipairs(hills) do
		local footprint = (h.sx + h.sz) / 2
		local baseRad = math.clamp(footprint * FOOTHILL_BALL_RADIUS_FRAC, FOOTHILL_BALL_MIN_R, FOOTHILL_BALL_MAX_R)

		-- Ball 1: hill CENTER, tallest — apex sits exactly at the hill's declared crest.
		balls[#balls + 1] = { x = h.x, y = h.crest - baseRad, z = h.z, rad = baseRad, mat = "Grass" }

		-- Ball 2 (inner band only): an overlapping shoulder, tangentially offset, apex lower than center —
		-- this is what makes the hill read as a ROLLING dome instead of one perfect sphere. Side alternates
		-- per hill via the hash for silhouette variety.
		if h.band == "inner" then
			local side = (n01(hi * 7 + 13) < 0.5) and -1 or 1
			local shoulderRad = baseRad * 0.78
			local shoulderCrest = math.max(h.crest * 0.60, 6)
			local sx, sz = localOffset(h.x, h.z, h.yaw, 0, side * baseRad * 0.6)
			balls[#balls + 1] = { x = sx, y = shoulderCrest - shoulderRad, z = sz, rad = shoulderRad, mat = "Grass" }
		end

		-- Ground toe ball — one wider, flatter ball at the hill's base for color grounding. "Wider" reads
		-- via its lower crest fraction (a shallower, broader cap breaking the surface, not a bigger sphere)
		-- rather than a bigger radius, which is what kept it off the volume gate.
		local toeRad = math.clamp(baseRad * 0.95, FOOTHILL_BALL_MIN_R, FOOTHILL_BALL_MAX_R)
		local toeCrest = math.max(h.crest * 0.22, 4)
		balls[#balls + 1] = { x = h.x, y = toeCrest - toeRad, z = h.z, rad = toeRad, mat = "Ground" }
	end
	return balls
end

--------------------------------------------------------------------------------
-- SCULPT-OP ASSEMBLY — flatten the whole world into the ordered primitive list sculpt() replays.
-- ops: B=FillBlock, W=FillWedge, C=FillCylinder(upright), L=FillBall. Materials are STRING keys
-- (sculpt maps them to Enum.Material) so plan() never constructs an Enum it doesn't need.
--------------------------------------------------------------------------------
local function assembleOps(foothills, foothillToe, falloffCollar, groundSkin, midGroundSkin, paintCells, water, mountains)
	local ops = {}
	-- B() — a FillBlock op. Roblox Terrain rejects a fill ("Extents are too large") if any axis exceeds
	-- MAX_FILL_EXTENT OR the region volume exceeds MAX_FILL_VOLUME — the volume check is the one that
	-- bites blocks whose every axis looks fine (the historical bug: the old rotated rim-PEAK blocks had
	-- sx=sz≈1231.5, sy 1593-2044, all < 4000, but sx*sy*sz ≈ 2.4-3.1e9 studs³). So tile ANY oversized block — axis-aligned or rotated,
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
	-- feature (optional, trailing) — an extra, purely descriptive tag carried on the op record (e.g.
	-- "mountain" for buildMountainRange's ops below). sculpt() and the extent/coplanarity-style gates
	-- iterate generically over op/mat/sx/sy/sz/rad fields and never touch it, so a nil feature on every
	-- other producer's ops is unaffected; it exists purely so a gate can `filter feature=="mountain"`.
	local function pushB(x, y, z, sx, sy, sz, mat, yaw, feature) ops[#ops + 1] = { op = "B", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw, feature = feature } end
	local function B(x, y, z, sx, sy, sz, mat, yaw, feature)
		local yw = yaw or 0
		if sx <= MAX_FILL_EXTENT and sy <= MAX_FILL_EXTENT and sz <= MAX_FILL_EXTENT and sx * sy * sz <= MAX_FILL_VOLUME then
			pushB(x, y, z, sx, sy, sz, mat, yaw, feature)
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
					pushB(wx, wy, wz, subX, subY, subZ, mat, yaw, feature)
				end
			end
		end
	end
	-- FIX 3 (S50 audit): B() tiles/gates itself (above), but W()/C()/L() pushed raw — a bypass for the
	-- exact "Extents are too large" class the rim-PEAK bug proved possible. These three now assert the
	-- same per-axis-extent + region-volume bounds AT PLAN TIME (pure error(), no Instances touched), so
	-- an oversized wedge/cylinder/ball is caught by Tier-4 the moment it's authored, never in a live boot.
	local function W(x, y, z, sx, sy, sz, mat, yaw, feature)
		if not (sx <= MAX_FILL_EXTENT and sy <= MAX_FILL_EXTENT and sz <= MAX_FILL_EXTENT and sx * sy * sz <= MAX_FILL_VOLUME) then
			error(("WorldGen W() wedge %.1fx%.1fx%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(sx, sy, sz, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, sx * sy * sz))
		end
		ops[#ops + 1] = { op = "W", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, mat = mat, yaw = yaw, feature = feature }
	end
	local function C(x, y, z, h, rad, mat)
		local vol = math.pi * rad * rad * h
		if not (h <= MAX_FILL_EXTENT and 2 * rad <= MAX_FILL_EXTENT and vol <= MAX_FILL_VOLUME) then
			error(("WorldGen C() cylinder h=%.1f rad=%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(h, rad, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, vol))
		end
		ops[#ops + 1] = { op = "C", x = x, y = y, z = z, h = h, rad = rad, mat = mat }
	end
	local function L(x, y, z, rad, mat, feature)
		local vol = (4 / 3) * math.pi * rad ^ 3
		if not (2 * rad <= MAX_FILL_EXTENT and vol <= MAX_FILL_VOLUME) then
			error(("WorldGen L() ball rad=%.1f (mat %s) exceeds MAX_FILL_EXTENT=%d or MAX_FILL_VOLUME=%.0f (vol=%.0f)")
				:format(rad, tostring(mat), MAX_FILL_EXTENT, MAX_FILL_VOLUME, vol))
		end
		ops[#ops + 1] = { op = "L", x = x, y = y, z = z, rad = rad, mat = mat, feature = feature }
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
	-- 4b) MID GROUND SKIN (S52 FIX 2) — a thin continuous Ground band under the whole foothill annulus
	-- (r≈3350→5500), emitted BEFORE the foothill domes so their Grass balls read on top of it at every
	-- overlap: seals the "no ground between the discrete hills" gap a top-down view used to see straight
	-- through to the catch floor below.
	for _, g in ipairs(midGroundSkin) do B(g.x, g.y, g.z, g.sx, g.sy, g.sz, g.mat, g.yaw) end
	-- 5) FOOTHILLS + toe blend — the broken low hill ring (replaces the old rim wall + apron). S52 FIX 1:
	-- each hill is now a rounded hillform (overlapping flattened L() balls: a tall center + shoulder,
	-- Grass, plus a wider flatter Ground toe ball) instead of one rectangular B() block, so it reads as a
	-- rolling dome up close instead of a mesa with ruler-straight walls. buildFoothillDome consumes the
	-- SAME hill records (layout untouched) and only changes the emission.
	for _, b in ipairs(buildFoothillDome(foothills)) do L(b.x, b.y, b.z, b.rad, b.mat) end
	for _, t in ipairs(foothillToe) do B(t.x, t.y, t.z, t.sx, t.sy, t.sz, t.mat, t.yaw) end
	-- 6) FALLOFF COLLAR — thin descending Ground skin past the foothills (r≈5400→6600) so the ground
	-- visibly falls away into the haze instead of ending at a hard edge.
	for _, c in ipairs(falloffCollar) do B(c.x, c.y, c.z, c.sx, c.sy, c.sz, c.mat, c.yaw) end
	-- 6b) GROUND SKIN (S52 FIX 2) — thin Ground shell past the collar (r≈6600→8800, under the mountain
	-- clusters) so a top-down sightline anywhere reachable sees ground fading into haze, never void/sky.
	for _, g in ipairs(groundSkin) do B(g.x, g.y, g.z, g.sx, g.sy, g.sz, g.mat, g.yaw) end
	-- 7) MICRO RELIEF — grass mounds (≤6 protrusion) then rock outcrops (r1700-3000 arcs).
	for _, m in ipairs(MOUNDS) do L(m.x, m.protrude - m.r, m.z, m.r, "Grass") end
	for _, o in ipairs(OUTCROPS) do L(o.x, o.protrude - o.r, o.z, o.r, "Rock") end

	-- 7b) MOUNTAIN RANGES (§2 bar packet) — layered Rock/Snow terrain clusters, replacing the old
	-- WedgePart backdrop. Every op tagged feature="mountain" so the mountain-volume gate can sum
	-- exactly this content without touching anything else in sculptOps. Each peak is 4 layers: a Rock
	-- base mass, a body "spine" of jittered balls (Rock below the snowline / Snow above it), a
	-- wedge-pair ridge cap (triangle silhouette from the play area), and — snow peaks only — a small
	-- Snow crown ball. Placed before water (never overlaps a carve; ordering doesn't matter here).
	local function emitMountainPeak(pk)
		local az, footW, footD, peakH, baseY, snow, bodyN, seed =
			pk.az, pk.footW, pk.footD, pk.peakH, pk.baseY, pk.snow, pk.bodyN, pk.seed
		local px, pz = pk.px, pk.pz
		local snowlineY = baseY + peakH * (snow and 0.66 or 2.0)
		local yaw = yawTangent(az)

		-- L1 base mass (Rock): a squat block under the peak, footW tangential x footD radial. S52 FIX 3:
		-- height capped at min(0.08*peakH, 120) (was a flat 0.15*peakH) so the base is grounding-only —
		-- its top sits low enough to hide under the body-spine's lowest balls instead of poking a flat
		-- rectangular slab above the surrounding ground. The center is naturally lower too, since it's
		-- still anchored at baseY (the block's bottom, unchanged).
		local baseSy = math.min(MOUNTAIN_BASE_FRAC * peakH, MOUNTAIN_BASE_MAX)
		local baseTopY = baseY + baseSy
		B(px, (baseY + baseTopY) / 2, pz, footW, baseSy, footD, "Rock", yaw, "mountain")

		-- L2 body spine: N jittered balls climbing the peak, Rock below the snowline / Snow above it.
		for kk = 0, bodyN - 1 do
			local t = kk / (bodyN - 1)
			local by = baseY + peakH * (0.15 + 0.80 * t)
			local rad = math.clamp(footW * (0.42 - 0.30 * t), 130, 400)
			local jt = (n01(seed + 41 + kk) - 0.5) * (2 * 0.16 * footW) -- tangential jitter
			local jr = (n01(seed + 53 + kk) - 0.5) * (2 * 0.14 * footD) -- radial jitter
			local jx, jz = localOffset(px, pz, yaw, jr, jt)
			local mat = (by > snowlineY) and "Snow" or "Rock"
			L(jx, by, jz, rad, mat, "mountain")
		end

		-- L3 ridge cap: two wedges back-to-back — height varies along tangential = a triangle read.
		local capY = baseY + peakH * 0.72
		local capMat = (capY > snowlineY) and "Snow" or "Rock"
		W(px, capY, pz, 0.30 * footD, 0.40 * peakH, 0.50 * footW, capMat, yaw, "mountain")
		W(px, capY, pz, 0.30 * footD, 0.40 * peakH, 0.50 * footW, capMat, yaw + math.pi, "mountain")

		-- L4 snow crown (snow peaks only): a small cap ball at the very top.
		if snow then
			local crownRad = math.clamp(0.14 * footW, 120, 220)
			L(px, baseY + peakH * 0.94, pz, crownRad, "Snow", "mountain")
		end
	end
	for _, pk in ipairs(mountains.peaks) do emitMountainPeak(pk) end

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
	-- 8d) WestSea box carve + coastal bluff + a Sand beach on the east edge, now the open west horizon
	-- (the foothill west arc + falloff collar are open there — see WEST_ARC). The unseen Rock floor
	-- beneath the water is never walked on or seen (the P3 catch floor backstops it), so it's thinned
	-- from 40 studs to 8 (open-horizon packet) — saves ≈3.1e9 studs³ of dead-weight sculpt volume with
	-- zero visible change (water-P3 invariant still holds: floorY stays -12, well above the failsafe).
	for _, body in ipairs(water) do
		if not body.deboxed then
			local reg = body.region
			local cx, cz = (reg.minX + reg.maxX) / 2, (reg.minZ + reg.maxZ) / 2
			local sx, sz = reg.maxX - reg.minX, reg.maxZ - reg.minZ
			local floorBase = body.floorY - 8
			local carveTop = body.surfaceY + 2
			B(cx, (body.floorY + carveTop) / 2, cz, sx, carveTop - body.floorY, sz, "Air")
			B(cx, (body.floorY + floorBase) / 2, cz, sx, body.floorY - floorBase, sz, "Rock")
			B(cx, (body.floorY + body.surfaceY) / 2, cz, sx, body.surfaceY - body.floorY, sz, "Water")
			-- Coast bluff: a Ground lip (Y -2..28) along the east sea edge (X = maxX).
			B(reg.maxX, 13, cz, 60, 30, sz, "Ground")
			-- Sand beach: an ~800-long wedge on the east edge, framing the open-water sightline (Z≈0).
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

	local foothills = buildFoothills()
	local foothillToe = buildFoothillToe()
	local falloffCollar = buildFalloffCollar()
	local groundSkin = buildGroundSkin()
	local midGroundSkin = buildMidGroundSkin()
	local paintCells = buildPaint()
	local water = buildWater()
	local mountains = buildMountainRange()
	local sculptOps = assembleOps(foothills, foothillToe, falloffCollar, groundSkin, midGroundSkin, paintCells, water, mountains)
	-- §2 bar packet: the distant-mountain backdrop is now sculpted TERRAIN (mountains.peaks, tagged
	-- feature="mountain" in sculptOps above), not Parts — plan.parts returns to just the P3 catch floor.
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
		-- §2 bar packet: the outermost radius any sculpted mountain peak's geometry reaches (computed
		-- live by buildMountainRange, not eyeballed) — the water-P3 catch-floor gate checks
		-- reachableRadius against THIS now that mountains are terrain, not Parts (parts-derived would
		-- read 0 for a mountain radius since only the CatchFloor Part remains in plan.parts).
		mountainMaxR = mountains.maxR,

		-- Decorative Parts: just the invisible P3 catch floor now (buildCatchFloorPart, canQuery=true —
		-- the documented invariant-④ exception). The distant backdrop mountains are sculpted TERRAIN
		-- (mountains.peaks, feature="mountain" ops in sculptOps), not Parts. Any FUTURE decorative Part
		-- added here MUST be canQuery=false.
		parts = parts,

		-- OPEN-HORIZON CONTENT — DATA consumed by sculpt/build, and read by the new gates. westArc is
		-- exposed alongside the hill records so a test/consumer can read the declared open azimuth
		-- without re-deriving it from foothillAmp.
		foothills = foothills,
		foothillToe = foothillToe,
		falloffCollar = falloffCollar,
		groundSkin = groundSkin,
		midGroundSkin = midGroundSkin,
		westArc = WEST_ARC,
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
		-- S52 FIX 3: WaterTransparency was previously never set (Terrain default ~0.3 let the sunset-pink
		-- sky show straight through the water instead of its own deep blue-teal color).
		if w.transparency then terrain.WaterTransparency = w.transparency end
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

-- opts.skipSculpt (bake pipeline): when Workspace.Terrain already carries baked SmoothGrid voxels
-- (stamped BakedByWorldGen=true by tools/Extract-Terrain.luau after a Studio bake — see
-- tools/Bake-World.ps1), build() must NOT terrain:Clear()+sculpt() over it — that would erase the
-- one thing Studio alone can produce and pay the ~sculpt-cost we baked specifically to avoid at
-- boot. applyStyle() is deliberately NOT gated by skipSculpt: it is a handful of SetMaterialColor/
-- Water* property writes (cheap, idempotent), and it is not certain every consumer of a baked rbxm
-- re-applies the exact same style pass (colors DO serialize onto the Terrain instance per the spike,
-- but re-asserting them here costs nothing and removes that uncertainty entirely) — see GameServer's
-- call site for the baked-marker check that sets skipSculpt.
function WorldGen.build(target, cfg, opts)
	opts = opts or {}
	-- S51 BOOT-CLOCK (Chad: "round 1 was over before the map ever rendered" — SOP: probe before
	-- optimizing). One always-on print at the end of build() naming where the ~63s boot actually goes,
	-- phase by phase, so a future slow-boot complaint has a named culprit instead of a guess.
	local tStart = os.clock()
	local plan = WorldGen.plan(cfg)
	local tPlan = os.clock()

	-- BIRTH CONTRACT — reproduce exactly what legacy BuildMap set (GameServer:260 / :267).
	target.Gravity = plan.gravity
	pcall(function() target.StreamingEnabled = false end)

	-- TERRAIN — clear then sculpt the valley + peaked rim + de-boxed water (skipped when baked),
	-- then always apply the style (cheap/idempotent — see the skipSculpt note above build()).
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then
		if not opts.skipSculpt then
			terrain:Clear()
			WorldGen.sculpt(terrain, plan)
		end
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
		-- FIX 1 (S51 horizon-iterate-2): the distant-mountain peaks are now WedgePart pairs (p.shape ==
		-- "Wedge"), not plain Parts — everything else about a plan.parts record (size/pos/canQuery/
		-- transparency/color/material) keeps working unchanged for both classes. p.yaw (radians, optional)
		-- rotates the instance about Y; every existing producer (e.g. CatchFloor) omits it and gets 0,
		-- identical to the old Position-only assignment.
		local part = Instance.new(p.shape == "Wedge" and "WedgePart" or "Part")
		part.Anchored = true
		part.Name = p.name
		part.Size = p.size
		part.CFrame = CFrame.new(p.pos) * CFrame.Angles(0, p.yaw or 0, 0)
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
		"[BootClock] plan=%.3fs sculpt=%.3fs parts=%.3fs prewarmScatter=%.3fs scatter=%.3fs lighting=%.3fs total=%.3fs baked=%s",
		tPlan - tStart, tSculpt - tPlan, tParts - tSculpt, tPrewarmScatter, tScatter - tParts, tLighting - tScatter,
		tLighting - tStart, tostring(opts.skipSculpt == true)))
end

-- clear(target) → honest flag-off: wipe the terrain and destroy the worldV2 "Map" folder.
function WorldGen.clear(target)
	local terrain = target:FindFirstChildOfClass("Terrain")
	if terrain then terrain:Clear() end
	local map = target:FindFirstChild("Map")
	if map then map:Destroy() end
end

return WorldGen
