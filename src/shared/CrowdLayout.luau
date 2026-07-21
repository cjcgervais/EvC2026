--!nonstrict
--[[
	CrowdLayout — B5a. Where the SAVED CROWD stands. Pure geometry, no Instances, no Roblox types.

	THE READ (Fable's consult, in Chad's words): *"The meadow is filling up with everyone I saved —
	that crowd IS my score."* A five-year-old reads their score with zero numerals.

	Approaches killed on the way here, by the ceiling they cannot reach:
	  • a bigger HUD number — it is a numeral, so the pre-reading kid-floor fails by definition.
	  • a static heap of props — a motionless pile habituates to scenery inside one round (the exact
	    failure Stage 1 killed in the static beacon pillar) and merges to a brown blob at flight
	    distance (the S41 feather lesson: discreteness must be STRUCTURAL, not hoped for — which is
	    why minimum spacing is a machine-asserted property of this module and not a wish).
	  • growing the crowd silently between rounds — if the kid never WITNESSES a squirrel arrive, it
	    is décor, not a scoreboard. Growth is one-per-hop-beat, synchronised with the tally.

	THE PROPERTY THAT MAKES IT A SCOREBOARD: seat i depends ONLY on i. So layout(n) is a strict
	prefix of layout(n+1) and **nobody ever relocates when the crowd grows** — the meadow accretes
	the way a real crowd does. A layout that reshuffled on every delivery would read as a flock
	milling about, not as a record of what you did.

	Geometry: a crescent band on the safe pad, radius [crowdRadiusMin, crowdRadiusMax], with a
	wedge excluded around the waterfall/updraft bearing so the crowd is dead ahead as you crest the
	falls but NEVER in the climb-out line and never over the pad centre. Seats sit on a ring lattice,
	so minimum spacing is guaranteed by construction rather than hoped for from a hash.

	Returns plain numbers (offsets from the pad centre) — the caller adds `deliverPos` and builds the
	CFrames. Keeping Roblox datatypes out is what makes this trivially testable headlessly.
]]

local CrowdLayout = {}

local TAU = math.pi * 2

-- Ring radii + per-ring slot counts, derived from the config band. Pure; called by layout().
local function rings(cfg)
	local rMin = cfg.crowdRadiusMin or 45
	local rMax = cfg.crowdRadiusMax or 85
	local gap = cfg.crowdRingGap or 12
	local spacing = cfg.crowdSlotSpacing or 13
	local excludeDeg = cfg.crowdExcludeDeg or 120          -- total excluded wedge (±60°)
	local allowedRad = math.rad(360 - excludeDeg)

	local out = {}
	local r = rMin
	while r <= rMax + 1e-6 do
		-- how many seats fit on this ring's allowed arc at the target spacing?
		local arcLen = r * allowedRad
		local slots = math.max(1, math.floor(arcLen / spacing))
		out[#out + 1] = { r = r, slots = slots }
		r = r + gap
	end
	return out
end

--[[
	layout(cfg, n) -> array of { dx, dz, yaw, phase }

	dx/dz  = offset from the pad centre, in studs.
	yaw    = radians; the crowd member faces the pad centre (they watch you land).
	phase  = a stable per-seat animation phase so the crowd never poses in unison.

	n is clamped to cfg.crowdMax. Deterministic: same (cfg, n) always yields the same array, and
	the first k entries never change as n grows.
]]
function CrowdLayout.layout(cfg, n)
	cfg = cfg or {}
	local out = {}
	local maxN = cfg.crowdMax or 24
	n = math.min(math.max(0, math.floor(n or 0)), maxN)
	if n == 0 then
		return out
	end

	local ringList = rings(cfg)
	local excludeDeg = cfg.crowdExcludeDeg or 120
	local bearing = math.rad(cfg.crowdExcludeBearingDeg or 180)  -- the waterfall/updraft side to avoid
	local allowedRad = math.rad(360 - excludeDeg)
	-- the allowed arc is centred OPPOSITE the excluded bearing
	local centre = bearing + math.pi

	-- Seats are emitted ring-by-ring in rotation (ring 1 slot 1, ring 2 slot 1, … then slot 2 …) so a
	-- growing crowd fills as a WEDGE rather than completing one lonely arc first. Within a ring, slots
	-- alternate outward from the centre line, so the crowd grows symmetrically around your approach.
	local emitted = 0
	local slotIdx = 0
	while emitted < n do
		local placedThisPass = false
		for _, ring in ipairs(ringList) do
			if slotIdx < ring.slots and emitted < n then
				placedThisPass = true
				-- alternate: 0, +1, -1, +2, -2, … so seat order radiates from the centre line
				local k = math.floor((slotIdx + 1) / 2)
				local sign = (slotIdx % 2 == 1) and 1 or -1
				local step = allowedRad / math.max(1, ring.slots)
				local ang = centre + sign * k * step
				emitted = emitted + 1
				out[emitted] = {
					dx = math.cos(ang) * ring.r,
					dz = math.sin(ang) * ring.r,
					-- face the pad centre: the inward bearing is the seat angle + pi
					yaw = ang + math.pi,
					-- stable, well-spread animation phase (golden ratio on the seat index)
					phase = ((emitted * 0.6180339887) % 1) * TAU,
				}
			end
		end
		slotIdx = slotIdx + 1
		if not placedThisPass then
			break -- every ring is full: the lattice cannot seat more than this (crowdMax should be ≤ this)
		end
	end

	return out
end

-- Total seats the lattice can physically hold at this config (so callers/tests can prove crowdMax fits).
function CrowdLayout.capacity(cfg)
	local total = 0
	for _, ring in ipairs(rings(cfg or {})) do
		total = total + ring.slots
	end
	return total
end

return CrowdLayout
