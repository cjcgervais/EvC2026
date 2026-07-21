--!nonstrict
--[[
	tests/crowd.spec.luau — the B5a gate for CrowdLayout (the SAVED CROWD).

	The read is "the meadow is filling up with everyone I saved — that crowd IS my score." Two of the
	three ways that read dies are STRUCTURAL, so they are machine-provable here rather than left to a
	playtest: (1) if seats reshuffle as the crowd grows it reads as a flock milling about instead of a
	record of what you did; (2) if seats can land on top of each other the crowd merges into a brown
	blob at flight distance (the S41 feather lesson — discreteness must be structural, not hoped for).
	The third — whether Chad GLANCES at the crowd instead of the HUD number — is his Play alone.

	Also pinned: the crowd must never sit on the pad centre or in the waterfall climb-out line, which
	is the "don't bait a collision / don't block the landing" rail.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local Crowd = Loader.load("CrowdLayout")

local R = GameConfig.Rescue
local MAXN = R.crowdMax or 24

local function dist(a, b)
	local dx, dz = a.dx - b.dx, a.dz - b.dz
	return math.sqrt(dx * dx + dz * dz)
end

H.test("crowd: every seat sits inside the pad band and never on the pad centre", function()
	local seats = Crowd.layout(R, MAXN)
	H.eq(#seats, MAXN, "a full crowd seats everyone")
	local rMin, rMax = R.crowdRadiusMin or 45, R.crowdRadiusMax or 85
	for i, s in ipairs(seats) do
		local r = math.sqrt(s.dx * s.dx + s.dz * s.dz)
		H.finite(r, "seat " .. i .. " radius is finite")
		H.between(r, rMin - 1e-6, rMax + 1e-6, "seat " .. i .. " is inside the crowd band")
		H.ok(r >= 40, "seat " .. i .. " must never crowd the landing pad centre")
	end
end)

H.test("crowd: no seat sits in the waterfall climb-out wedge (never in the flight line)", function()
	local seats = Crowd.layout(R, MAXN)
	local bearing = math.rad(R.crowdExcludeBearingDeg or 180)
	local halfWedge = math.rad((R.crowdExcludeDeg or 120) / 2)
	for i, s in ipairs(seats) do
		local ang = math.atan2(s.dz, s.dx)
		-- signed angular distance from the excluded bearing, wrapped to [-pi, pi]
		local d = (ang - bearing + math.pi) % (math.pi * 2) - math.pi
		H.ok(math.abs(d) >= halfWedge - 1e-6,
			("seat %d is %.1f° from the climb-out bearing — inside the excluded wedge")
				:format(i, math.deg(math.abs(d))))
	end
end)

H.test("crowd: PREFIX STABILITY — growing the crowd never relocates anyone", function()
	-- This is the property that makes it a scoreboard rather than a flock. Assert it for every
	-- crowd size, not just the full one.
	local full = Crowd.layout(R, MAXN)
	for n = 0, MAXN do
		local seats = Crowd.layout(R, n)
		H.eq(#seats, n, "layout(" .. n .. ") seats exactly n")
		for i = 1, n do
			H.approx(seats[i].dx, full[i].dx, 1e-12, ("seat %d moved in x when the crowd was %d"):format(i, n))
			H.approx(seats[i].dz, full[i].dz, 1e-12, ("seat %d moved in z when the crowd was %d"):format(i, n))
			H.approx(seats[i].yaw, full[i].yaw, 1e-12, ("seat %d turned when the crowd was %d"):format(i, n))
		end
	end
end)

H.test("crowd: minimum spacing is structural — no two saved squirrels merge into a blob", function()
	local seats = Crowd.layout(R, MAXN)
	local worst, wi, wj = math.huge, -1, -1
	for i = 1, #seats do
		for j = i + 1, #seats do
			local d = dist(seats[i], seats[j])
			if d < worst then worst, wi, wj = d, i, j end
		end
	end
	print(("      [crowd] %d seats · min pairwise spacing %.2f studs (seats %d,%d) · lattice capacity %d")
		:format(#seats, worst, wi, wj, Crowd.capacity(R)))
	-- a crowd squirrel at crowdScale is a couple of studs across; 8 studs keeps clear daylight
	-- between individuals at flight distance, which is what stops the brown-blob read.
	H.ok(worst >= 8, ("closest pair is %.2f studs — they will read as one blob, not individuals"):format(worst))
end)

H.test("crowd: seats face the pad centre, and phases are spread (never posing in unison)", function()
	local seats = Crowd.layout(R, MAXN)
	local buckets = {}
	for i, s in ipairs(seats) do
		-- yaw must point back toward the centre: the inward vector is (-dx, -dz)
		local want = math.atan2(-s.dz, -s.dx)
		local d = (s.yaw - want + math.pi) % (math.pi * 2) - math.pi
		H.approx(d, 0, 1e-9, "seat " .. i .. " does not face the pad centre")
		H.finite(s.phase, "seat " .. i .. " phase is finite")
		H.between(s.phase, 0, math.pi * 2 + 1e-9, "seat " .. i .. " phase is in range")
		local b = math.floor(s.phase / (math.pi * 2) * 8)
		buckets[b] = (buckets[b] or 0) + 1
	end
	local used = 0
	for _ in pairs(buckets) do used += 1 end
	H.ok(used >= 5, "animation phases must spread across the cycle, or the crowd poses in lockstep")
end)

H.test("crowd: capacity covers crowdMax, and the count is clamped + deterministic", function()
	H.ok(Crowd.capacity(R) >= MAXN,
		("the lattice holds %d seats but crowdMax is %d — someone would be left standing")
			:format(Crowd.capacity(R), MAXN))
	H.eq(#Crowd.layout(R, MAXN + 50), MAXN, "an over-large count clamps to crowdMax")
	H.eq(#Crowd.layout(R, -3), 0, "a negative count yields an empty crowd, not a crash")
	H.eq(#Crowd.layout(R, nil), 0, "a nil count yields an empty crowd, not a crash")
	local a, b = Crowd.layout(R, 11), Crowd.layout(R, 11)
	for i = 1, 11 do
		H.eq(a[i].dx, b[i].dx, "seat " .. i .. " x is deterministic across calls")
		H.eq(a[i].dz, b[i].dz, "seat " .. i .. " z is deterministic across calls")
	end
end)

H.test("B5a: the savedCrowd gate exists as a real one-line revert", function()
	-- S43 flipped this LIVE for Chad's flight (the S41 flameStyle pattern: headless-gate the read, then
	-- hand him a working result instead of a flag to hunt for). So this pins the GATE, not a value —
	-- a test asserting "false" would fail the moment the feature was handed over, which is the same
	-- inverted-gate mistake the squeak asset-list assert made.
	H.eq(type(R.savedCrowd), "boolean", "the one-line revert gate exists and is a boolean")
	-- and the layout is PURE: the gate can only stop the crowd being rendered, never move a seat.
	local saved = R.savedCrowd
	local a = Crowd.layout(R, 7)
	R.savedCrowd = not saved
	local b = Crowd.layout(R, 7)
	R.savedCrowd = saved
	for i = 1, 7 do
		H.eq(a[i].dx, b[i].dx, "seat " .. i .. " must not depend on the gate")
		H.eq(a[i].dz, b[i].dz, "seat " .. i .. " must not depend on the gate")
	end
end)
