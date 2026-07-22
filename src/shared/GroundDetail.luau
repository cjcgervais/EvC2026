--!nonstrict
--[[
	GroundDetail.luau — the SPAWN CORE's missing perspective cues. PURE module (no Instances, no
	services, no clock, no math.random): returns a deterministic list of flat ground-patch specs that
	the caller builds. Same shape as the rest of the shared/ pure modules so it is headless-gated.

	WHY THIS EXISTS (Chad, S45): "I nose down into the ground every time… I'm diving so the ground will
	render but it does so too late."

	He is not flying badly and it is not (only) a render bug. GameServer's BuildMap already knew the
	mechanism — its own comment says the ground patches exist to "break up the uniform grass so
	altitude/speed/heading read at a glance from far up (A FLAT GREEN PLAIN GIVES NO PERSPECTIVE CUE)".
	Then every single feature was placed OUTSIDE the player's box:
	    ground patches  "all clear of the ±1200 core"          (GameServer:298)
	    the river       "not the spawn core"                    (GameServer:316)
	    the buttes      "kept clear of the ±1200 spawn zone"    (GameServer:369)
	    lake / desert / three mountain rings — radius 3,000-7,400
	The eagle spawns at a random XZ inside ±1200 at Y=600. So the one region the player occupies is a
	2,400 × 2,400 stud UNIFORM PLANE. Diving it is the classic featureless-terrain problem: with no
	object of known size and no texture gradient, there is no closure cue, so altitude is unreadable
	until Roblox's material texture resolves at short range — which reads from the cockpit exactly as
	"the ground rendered too late".

	THE TECHNIQUE, and why the obvious alternatives are traps (SOP #8 — vet the APPROACH):
	  • MULTI-SCALE is the whole point. A cue helps only while it subtends a useful visual angle, so a
	    single patch size fixes exactly one altitude. Three bands (coarse/mid/fine) mean something is
	    always resolving as you descend — the gradient itself IS the altimeter, and the fine band is
	    what "blooms" during the last 150 studs of a dive, giving the flare cue that is missing today.
	  • Bigger/brighter patches only — a trap: scaling one band up helps at 600 and still leaves the
	    last 200 studs cueless, which is precisely where he hits.
	  • Roblox Terrain — the real long-term answer for "a proper map", but it is a different
	    replication/collision system entirely and would land on top of an unresolved render question.
	    Not while the probe is unflown.
	  • A texture/decal grid — needs an asset ID, and asset IDs are the one thing no headless gate in
	    this project can verify (the S43 roar tombstone). Parts are verifiable.
	  • Raising the spawn or slowing the dive — that is a FLIGHT change, and the kernel is LOCKED. The
	    defect is in the world, so the fix belongs in the world.

	PURELY COSMETIC BY CONSTRUCTION: every patch is emitted with canCollide/canQuery/canTouch FALSE and
	castShadow FALSE, so BirdCollision's Spherecast cannot see them and the crash geometry is
	bit-identical to today. This module can change how the ground READS; it cannot change what the
	ground DOES. The spec asserts that.
]]

local GroundDetail = {}

-- A tiny deterministic LCG. NOT math.random: the world must be identical on every boot and inside the
-- headless spec (the project's B1 determinism rule — see FireGrid).
local function lcg(seed)
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- The three bands, each laid on a JITTERED GRID (stratified), never uniform-random. Pure random
-- placement leaves clumps and holes, and a hole here is not cosmetic — it is a corridor the player can
-- dive through with no cue, i.e. the original bug, reintroduced by luck. A jittered grid guarantees
-- every cell has a patch while the jitter keeps it from reading as a checkerboard. `rows`×`cols` is
-- the count; sizes are tuned so each band resolves at a different slice of the descent from Y=600.
local BANDS = {
	{ key = "coarse", rows = 4, cols = 4, min = 420, max = 760, tone = 0.55 },  -- reads from 600+: "there is a floor"
	{ key = "mid",    rows = 6, cols = 6, min = 150, max = 320, tone = 0.75 },  -- reads through the middle of a dive
	{ key = "fine",   rows = 9, cols = 9, min = 48,  max = 118, tone = 1.00 },  -- blooms in the last ~150 studs = the flare cue
}

-- Earth-toned variations on BuildMap's baseplate green, RGB(96,142,74). Deliberately LOW contrast:
-- the job is a legible gradient, not a checkerboard that fights the rescue valley's look. `tone`
-- scales each patch's departure from the base so the fine band is the most distinct up close.
local PALETTE = {
	{ 78, 122, 62 },    -- shadowed meadow
	{ 112, 156, 84 },   -- sunlit meadow
	{ 128, 138, 82 },   -- dry grass
	{ 104, 116, 78 },   -- scrub
	{ 138, 128, 96 },   -- bare earth
	{ 86, 134, 88 },    -- damp hollow
}

-- patches(cfg) → array of {name, x, z, w, l, r, g, b, material, canCollide, canQuery, canTouch, castShadow}
-- cfg = GameConfig.Map. Returns an EMPTY list when coreDetail is off (kill switch ⇒ byte-identical map).
function GroundDetail.patches(cfg)
	cfg = cfg or {}
	if not cfg.coreDetail then return {} end

	local half = cfg.coreHalfExtent or 1200      -- the spawn box: GameServer spawns at random ±1200 XZ
	local rand = lcg(cfg.coreDetailSeed or 20260721)
	local out = {}

	-- APRON: lay the grid over a box ~15% wider than the core. Patch CENTRES are inset inside their
	-- cells, so a grid stopping exactly at ±half frays at the boundary — the coverage gate caught a
	-- 263-stud cueless gap at the box edge on the first run. Cues must not stop dead at an invisible
	-- line the player cannot see anyway; the apron also blends into the wider map instead of ending.
	local span = half * 1.15

	for _, band in ipairs(BANDS) do
		local cellW = (span * 2) / band.cols
		local cellL = (span * 2) / band.rows
		for row = 0, band.rows - 1 do
		for col = 0, band.cols - 1 do
			local i = row * band.cols + col + 1
			-- One patch per grid cell, jittered inside it. Jitter is kept to the middle 70% of the cell
			-- so a patch can never migrate far enough to open a hole in a neighbouring cell.
			local x = -span + (col + 0.15 + rand() * 0.7) * cellW
			local z = -span + (row + 0.15 + rand() * 0.7) * cellL
			local w = band.min + rand() * (band.max - band.min)
			local l = band.min + rand() * (band.max - band.min)

			local p = PALETTE[1 + math.floor(rand() * #PALETTE) % #PALETTE]
			-- Blend each palette entry toward the baseplate green by the band's tone, so coarse patches
			-- whisper and fine ones speak. Keeps the meadow reading as one surface.
			local baseR, baseG, baseB = 96, 142, 74
			local t = band.tone
			out[#out + 1] = {
				name = "CoreDetail_" .. band.key .. "_" .. i,
				x = x, z = z, w = w, l = l,
				r = math.floor(baseR + (p[1] - baseR) * t + 0.5),
				g = math.floor(baseG + (p[2] - baseG) * t + 0.5),
				b = math.floor(baseB + (p[3] - baseB) * t + 0.5),
				band = band.key,
				-- COSMETIC BY CONSTRUCTION. BirdCollision sweeps a Spherecast; a non-queryable part is
				-- invisible to it, so the crash surface stays exactly the baseplate it is today.
				canCollide = false,
				canQuery = false,
				canTouch = false,
				castShadow = false,
			}
		end
		end
	end
	return out
end

-- The band table, exposed so the spec can assert coverage per band without re-typing the numbers.
GroundDetail.BANDS = BANDS

return GroundDetail
