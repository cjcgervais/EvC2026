--!nonstrict
--[[
	tests/grounddetail.spec.luau — S45.

	Chad: "I nose down into the ground every time… I'm diving so the ground will render but it does so
	too late." Root cause was in the MAP, not his flying: BuildMap places every landmark explicitly
	"clear of the ±1200 spawn core" (its own in-line comments say so three times), leaving the box the
	player spawns and flies in a uniform 2,400-stud plane with no closure cue.

	These gates assert the two things that make the fix trustworthy:
	  1. It CANNOT change the game — every patch is non-queryable, so BirdCollision's Spherecast cannot
	     see it and the crash surface is bit-identical to today.
	  2. It actually closes the hole — multi-scale coverage with NO gap wide enough to dive through,
	     which is the failure mode a naive random scatter would reintroduce by luck.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local GroundDetail = Loader.load("GroundDetail")

local MAP = GameConfig.Map

H.test("core detail: ships ON — the whole finding is that the spawn box had no cues", function()
	H.ok(MAP and MAP.coreDetail, "GameConfig.Map.coreDetail must be true or the fix is inert")
	H.ok(#GroundDetail.patches(MAP) > 0, "the live config must actually produce patches")
end)

H.test("core detail: KILL SWITCH — coreDetail=false returns an empty map (byte-identical)", function()
	local off = table.clone(MAP); off.coreDetail = false
	H.eq(#GroundDetail.patches(off), 0, "with the flag off the builder must emit nothing at all")
	H.eq(#GroundDetail.patches(nil), 0, "a nil config must not throw and must emit nothing")
end)

H.test("core detail: COSMETIC BY CONSTRUCTION — nothing is queryable, so collision cannot change", function()
	local patches = GroundDetail.patches(MAP)
	for _, d in ipairs(patches) do
		H.ok(d.canQuery == false, d.name .. ": canQuery must be FALSE — a queryable patch would enter " ..
			"BirdCollision's Spherecast and change the crash surface, which this change must never do")
		H.ok(d.canCollide == false, d.name .. ": canCollide must be FALSE")
		H.ok(d.canTouch == false, d.name .. ": canTouch must be FALSE")
		H.ok(d.castShadow == false, d.name .. ": castShadow must be FALSE (78 shadow-casting Map parts " ..
			"are already a measured cost; do not add more)")
	end
end)

H.test("core detail: patches stay on the spawn box (plus its coverage apron)", function()
	local half = MAP.coreHalfExtent or 1200
	local limit = half * 1.2   -- the 15% apron that closes the boundary fray, with a hair of slack
	local inside = 0
	for _, d in ipairs(GroundDetail.patches(MAP)) do
		H.ok(math.abs(d.x) <= limit and math.abs(d.z) <= limit,
			("%s at (%.0f, %.0f) drifted beyond the ±%.0f apron — it cues nothing where the player flies")
				:format(d.name, d.x, d.z, limit))
		if math.abs(d.x) <= half and math.abs(d.z) <= half then inside += 1 end
	end
	local total = #GroundDetail.patches(MAP)
	H.ok(inside >= total * 0.6,
		("only %d of %d patches sit INSIDE the ±%d core — the apron must frame the box, not replace it")
			:format(inside, total, half))
end)

H.test("core detail: MULTI-SCALE — three distinct bands, or it only fixes one altitude", function()
	local patches = GroundDetail.patches(MAP)
	local seen = {}
	for _, d in ipairs(patches) do
		seen[d.band] = seen[d.band] or { n = 0, min = math.huge, max = -math.huge }
		local s = seen[d.band]
		s.n += 1
		s.min = math.min(s.min, d.w, d.l)
		s.max = math.max(s.max, d.w, d.l)
	end
	for _, band in ipairs(GroundDetail.BANDS) do
		local s = seen[band.key]
		H.ok(s and s.n == band.rows * band.cols,
			("band %s must contribute %d patches"):format(band.key, band.rows * band.cols))
	end
	-- The bands must genuinely occupy different scales: a cue only helps while it subtends a useful
	-- visual angle, so overlapping bands would be one band wearing three names.
	H.ok(seen.fine.max < seen.mid.max and seen.mid.max < seen.coarse.max,
		("bands collapsed into one scale (fine≤%.0f mid≤%.0f coarse≤%.0f) — then the descent has a " ..
			"cue gap again"):format(seen.fine.max, seen.mid.max, seen.coarse.max))
	H.ok(seen.fine.max <= 120,
		"the FINE band must stay small — it is the last-150-studs flare cue, not more midground")
end)

H.test("core detail: NO DIVE CORRIDOR — no point in the core is far from a cue", function()
	local patches = GroundDetail.patches(MAP)
	local half = MAP.coreHalfExtent or 1200
	-- Sweep the whole core on a fine grid and find the worst distance to the nearest patch EDGE. This
	-- is the gate that a uniform-random scatter would fail: one unlucky hole is a corridor the player
	-- dives with no closure cue — the exact bug being fixed.
	local worst, wx, wz = -1, 0, 0
	for gx = -half, half, 60 do
		for gz = -half, half, 60 do
			local best = math.huge
			for _, d in ipairs(patches) do
				-- distance from the sample point to this patch's rectangle
				local dx = math.max(0, math.abs(gx - d.x) - d.w * 0.5)
				local dz = math.max(0, math.abs(gz - d.z) - d.l * 0.5)
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < best then best = dist end
			end
			if best > worst then worst, wx, wz = best, gx, gz end
		end
	end
	print(("      [ground] worst gap to a cue anywhere in the core: %.0f studs (at %.0f, %.0f)")
		:format(worst, wx, wz))
	H.ok(worst <= 220, ("a %.0f-stud cueless gap exists at (%.0f, %.0f). Diving that corridor gives the " ..
		"player no closure cue — which is the bug this module exists to fix"):format(worst, wx, wz))
end)

H.test("core detail: DETERMINISTIC — the valley is identical on every boot (B1 rule)", function()
	local a = GroundDetail.patches(MAP)
	local b = GroundDetail.patches(MAP)
	H.eq(#a, #b, "two calls must produce the same count")
	for i = 1, #a do
		H.eq(a[i].x, b[i].x, "patch " .. i .. " X drifted between calls — no math.random is allowed here")
		H.eq(a[i].z, b[i].z, "patch " .. i .. " Z drifted between calls")
		H.eq(a[i].w, b[i].w, "patch " .. i .. " width drifted between calls")
	end
	-- …and a different seed must actually produce a different valley (else the seed is decorative).
	local other = table.clone(MAP); other.coreDetailSeed = (MAP.coreDetailSeed or 0) + 12345
	local c = GroundDetail.patches(other)
	local differs = false
	for i = 1, #a do if a[i].x ~= c[i].x then differs = true break end end
	H.ok(differs, "changing coreDetailSeed must change the layout, or the knob is a lie")
end)
