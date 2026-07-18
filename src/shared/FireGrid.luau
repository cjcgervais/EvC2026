--!nonstrict
--[[
	FireGrid.luau — the PURE fire-cell-grid clock for Eagles-to-the-Rescue (packet B1, Commit 1).

	PURE module (ReplicatedStorage.FireGrid). No Instances, services, clock (os/tick), task, or
	Roblox.Random — every stochastic draw comes from an EMBEDDED Park-Miller LCG so lune (headless
	SIM) and Studio produce BIT-IDENTICAL burns given the same (cfg, seed, wind, groves, deliverPos).
	State is a plain serializable table (no metatable methods) — trivially loadable in the Tier-4
	loader, hashable for the determinism test, and cheap to replicate a summary of. Vector3 is used
	for READS only (deliverPos / grove centres); the module never constructs one.

	This is INERT in Commit 1 — nothing consumes it at runtime (mission wiring is Commit 2), so the
	game stays byte-identical. The fire is tuned by SIMULATION (tests/firegrid.spec.luau) to the
	§3.3 bands BEFORE it ever renders a flame (B2 is the visual layer; its seam = burningCells()/
	stateAt()). There is NO damage path here — loss is points-opportunity (P3 non-lethal); a cut-off
	grove's squirrels leave by the EXISTING Ranger Balloon triage, driven by the server, not by us.

	Design of record: docs/rescue-consults/B1-FireGrid-design.md (§0 derivation fix pinned below:
	spread is ACTIVE from SMOLDER through BURNING, not just BURNING — else the front is ~3× too slow
	and percolation-stalls). GameConfig.Fire holds the §2 dials.

	States: GREEN=0  SMOLDER=1  BURNING=2  EMBER=3.
	API:
	  FireGrid.new(cfg, seed, wind, groves, deliverPos) -> grid   (plain state table)
	  FireGrid.igniteAt(grid, x, z)                                (light a burnable cell → SMOLDER)
	  FireGrid.seedUpwind(grid, count)                             (seed on the UPWIND rim)
	  FireGrid.step(grid, dt) -> ticksRun                          (accumulate dt, run whole ticks)
	  FireGrid.stateAt(grid, x, z) -> state                        (world x,z → cell state)
	  FireGrid.cutOffGroves(grid) -> { bool }                      (monotone; per-grove)
	  FireGrid.stats(grid) -> { green, smolder, burning, ember, threatened, reach, activeCount }
	  FireGrid.burningCells(grid, maxN) -> { {x,z,age} }           (B2 seam; newest-first, ≤maxN)
]]

local FireGrid = {}

-- state enum (exported for the SIM + B2)
FireGrid.GREEN = 0
FireGrid.SMOLDER = 1
FireGrid.BURNING = 2
FireGrid.EMBER = 3

--------------------------------------------------------------------------------
-- Embedded Park-Miller LCG (identical constants to rescuerules.spec:28-29). Advancing the seeded
-- generator in a FIXED draw order is the whole determinism guarantee — no Roblox.Random, ever.
--------------------------------------------------------------------------------
local function lcgNext(grid)
	-- s = s * 16807 % 2147483647, returns (0,1). State lives on the grid so it serializes.
	grid.rngState = (grid.rngState * 16807) % 2147483647
	return grid.rngState / 2147483647
end

--------------------------------------------------------------------------------
-- Grid geometry helpers. Cells are a flat 1-based array of length N*N; (cx,cz) are 1-based cell
-- indices, world XZ maps through gridHalf/cellSize. idx = (cz-1)*N + cx.
--------------------------------------------------------------------------------
local function cellIndex(grid, cx, cz)
	return (cz - 1) * grid.N + cx
end

-- world XZ → 1-based cell indices (or nil,nil if outside the grid box)
local function worldToCell(grid, x, z)
	local cx = math.floor((x + grid.gridHalf) / grid.cellSize) + 1
	local cz = math.floor((z + grid.gridHalf) / grid.cellSize) + 1
	if cx < 1 or cx > grid.N or cz < 1 or cz > grid.N then
		return nil, nil
	end
	return cx, cz
end

-- cell centre → world XZ (centre of the cell)
local function cellToWorld(grid, cx, cz)
	local x = (cx - 1 + 0.5) * grid.cellSize - grid.gridHalf
	local z = (cz - 1 + 0.5) * grid.cellSize - grid.gridHalf
	return x, z
end

--------------------------------------------------------------------------------
-- FireGrid.new — build the state table. Burnable mask = annulus [annulusInner, annulusOuter]
-- MINUS a padClearRadius disc around deliverPos (the top-of-waterfall safe pad is SACRED). The
-- wind is normalized to a unit XZ vector (fictional — never touches FlightPhysics). Groves are
-- {center=Vector3, radius=number} records used only for the cut-off / threat readout.
--------------------------------------------------------------------------------
function FireGrid.new(cfg, seed, wind, groves, deliverPos)
	cfg = cfg or {}
	local cellSize = cfg.cellSize or 60
	local gridHalf = cfg.gridHalf or 1620
	local N = math.floor((2 * gridHalf) / cellSize + 0.5)

	-- seed the LCG (Park-Miller wants a state in [1, 2147483646]).
	local s = (seed or 1) % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end

	-- normalize wind to a unit XZ direction (a=d·w in the weighting). A zero wind → no bias.
	local wx = (wind and wind.X) or 1
	local wz = (wind and wind.Z) or 0
	local wm = math.sqrt(wx * wx + wz * wz)
	if wm > 1e-6 then
		wx, wz = wx / wm, wz / wm
	else
		wx, wz = 1, 0
	end

	local grid = {
		-- geometry / config snapshot (so the SIM + B2 read from the grid, not the live config)
		cfg = cfg,
		cellSize = cellSize,
		gridHalf = gridHalf,
		N = N,
		windX = wx,
		windZ = wz,
		-- tunables lifted onto the grid (fallbacks = §2 starting dials)
		tickHz = cfg.tickHz or 2,
		smolderMin = cfg.smolderMin or 15,
		smolderMax = cfg.smolderMax or 25,
		burnTime = cfg.burnTime or 20,
		spreadP = cfg.spreadP or 0.045,
		crossFrac = cfg.crossFrac or 0.333,
		cutoffCheckEvery = cfg.cutoffCheckEvery or 4,
		maxVisualBurning = cfg.maxVisualBurning or 30,
		-- rng + clock
		rngState = s,
		acc = 0, -- dt accumulator (whole ticks fire)
		tickCount = 0,
		nextIgniteId = 0, -- age ordering for burningCells (newest-first)
		-- flat arrays
		state = {}, -- [idx] = GREEN|SMOLDER|BURNING|EMBER
		timer = {}, -- [idx] = seconds remaining in the current active phase
		burnable = {}, -- [idx] = bool (annulus minus pad)
		igniteOrder = {}, -- [idx] = monotone id at the moment it left GREEN (for newest-first)
		burnableCount = 0,
		-- groves + cut-off cache (monotone)
		groves = groves or {},
		cutOff = {}, -- [g] = bool, monotone (never un-cuts)
		reach = 0, -- farthest ignited-cell distance from origin (studs), monotone
	}

	-- padded pad disc centre (XZ)
	local padX = (deliverPos and deliverPos.X) or 0
	local padZ = (deliverPos and deliverPos.Z) or 0
	local padR = cfg.padClearRadius or 400
	local inner = cfg.annulusInner or 300
	local outer = cfg.annulusOuter or 1400

	-- build the burnable mask + init states
	for cz = 1, N do
		for cx = 1, N do
			local idx = cellIndex(grid, cx, cz)
			local x, z = cellToWorld(grid, cx, cz)
			local r = math.sqrt(x * x + z * z)
			local dpx, dpz = x - padX, z - padZ
			local rPad = math.sqrt(dpx * dpx + dpz * dpz)
			local burnable = (r >= inner and r <= outer) and (rPad > padR)
			grid.burnable[idx] = burnable
			grid.state[idx] = FireGrid.GREEN
			grid.timer[idx] = 0
			grid.igniteOrder[idx] = 0
			if burnable then
				grid.burnableCount = grid.burnableCount + 1
			end
		end
	end

	-- init the cut-off cache to all-false
	for g = 1, #grid.groves do
		grid.cutOff[g] = false
	end

	return grid
end

--------------------------------------------------------------------------------
-- Ignition. A cell may only ignite from GREEN and only if burnable — the pad can NEVER catch.
--------------------------------------------------------------------------------
local function ignite(grid, idx)
	if not grid.burnable[idx] then
		return false
	end
	if grid.state[idx] ~= FireGrid.GREEN then
		return false
	end
	grid.state[idx] = FireGrid.SMOLDER
	-- smolder duration ∈ [smolderMin, smolderMax], drawn from the LCG (fixed order).
	grid.timer[idx] = grid.smolderMin + lcgNext(grid) * (grid.smolderMax - grid.smolderMin)
	grid.nextIgniteId = grid.nextIgniteId + 1
	grid.igniteOrder[idx] = grid.nextIgniteId
	return true
end

-- FireGrid.igniteAt — light the burnable cell containing world (x,z).
function FireGrid.igniteAt(grid, x, z)
	local cx, cz = worldToCell(grid, x, z)
	if not cx then
		return false
	end
	return ignite(grid, cellIndex(grid, cx, cz))
end

-- FireGrid.seedUpwind — seed `count` cells on the UPWIND rim (opposite the wind vector) of the
-- burnable annulus, so the front SWEEPS across the valley with the wind. Deterministic: it walks a
-- fixed angular fan centred on the upwind bearing, jittered by the LCG, and lights the outermost
-- burnable cell along each ray. Idempotent-ish (re-lighting an already-lit cell is a no-op).
function FireGrid.seedUpwind(grid, count)
	count = count or (grid.cfg.seedCount or 2)
	local outer = grid.cfg.annulusOuter or 1400
	local inner = grid.cfg.annulusInner or 300
	-- upwind bearing = opposite the wind direction.
	local ux, uz = -grid.windX, -grid.windZ
	local baseAng = math.atan2(uz, ux)
	local halfArc = math.rad((grid.cfg.seedArcDeg or 120) / 2)
	local lit = 0
	-- Seed a fire LINE, not a clump: `count` EVENLY-SPACED rays across a wide upwind arc, each lighting the
	-- outermost burnable cell along it. A broad ignition front (not a point cluster) is what the wind then
	-- blows downwind as a wall — hits the §3.3 grove-threat/cut-off bands WITHOUT flattening the wind
	-- character (Fable B1 after-audit: the real lever is seed GEOMETRY, not lateral spread physics).
	for i = 0, count - 1 do
		-- even slot in [0,1) + a small LCG jitter so the line isn't a perfect comb.
		local frac = (i + 0.5) / count + (lcgNext(grid) - 0.5) * 0.15
		local ang = baseAng + (frac * 2 - 1) * halfArc
		-- march inward from just inside the outer rim to the first burnable GREEN cell along this ray.
		local rr = outer - grid.cellSize * (0.25 + lcgNext(grid) * 0.5)
		while rr >= inner do
			local x = math.cos(ang) * rr
			local z = math.sin(ang) * rr
			if FireGrid.igniteAt(grid, x, z) then
				lit = lit + 1
				break
			end
			rr = rr - grid.cellSize
		end
	end
	return lit
end

--------------------------------------------------------------------------------
-- Wind-weighted per-neighbor ignition probability (§2 formula EXACTLY). For a source→neighbor
-- direction d (unit) and unit wind w, a = d·w. a≥0 → p = spreadP·(crossFrac + (1−crossFrac)·a);
-- a<0 → p = spreadP·crossFrac·(1+a). Hits p(downwind=+1)=spreadP, p(cross=0)=spreadP·crossFrac,
-- p(upwind=−1)=0. N4 only (the four axis neighbors), so the derivation (E[delay]=1/(2·spreadP))
-- holds; N8 would double the effective p and break the front-speed band.
--------------------------------------------------------------------------------
-- N4 unit directions (dx, dz): E, W, N(+z... treated as +Z), S. Sign(a) is all that matters.
local N4 = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
}

local function spreadProb(grid, dx, dz)
	local a = dx * grid.windX + dz * grid.windZ
	local sp = grid.spreadP
	local cf = grid.crossFrac
	if a >= 0 then
		return sp * (cf + (1 - cf) * a)
	else
		return sp * cf * (1 + a)
	end
end

--------------------------------------------------------------------------------
-- One 1/tickHz tick: advance every active cell's phase, and let SMOLDER+BURNING cells throw embers
-- to their N4 GREEN burnable neighbors (the §0 fix — active from SMOLDER). Deterministic: iterate
-- the active set in ascending cell-index order, then N/E/S/W (the N4 table order) — every draw is
-- from the embedded LCG so the sequence is replay-stable. Ignitions are DEFERRED to the end of the
-- tick (a freshly-lit cell does not spread on the same tick).
--------------------------------------------------------------------------------
local function tick(grid)
	local dt = 1 / grid.tickHz
	grid.tickCount = grid.tickCount + 1

	-- 1) collect the active set (SMOLDER or BURNING) in ascending index — snapshot BEFORE advancing.
	--    We iterate the whole grid once; cheap vs N*N and keeps the draw order canonical.
	local toIgnite = {} -- [idx] = true (deferred; applied after the sweep)
	local attempts = 0

	for idx = 1, grid.N * grid.N do
		local st = grid.state[idx]
		if st == FireGrid.SMOLDER or st == FireGrid.BURNING then
			-- spread: this active cell throws embers to its N4 GREEN burnable neighbors.
			-- decode cx,cz from idx (1-based)
			local cz = math.floor((idx - 1) / grid.N) + 1
			local cx = (idx - 1) % grid.N + 1
			for _, d in ipairs(N4) do
				local nx, nz = cx + d[1], cz + d[2]
				if nx >= 1 and nx <= grid.N and nz >= 1 and nz <= grid.N then
					local nidx = cellIndex(grid, nx, nz)
					if grid.burnable[nidx] and grid.state[nidx] == FireGrid.GREEN and not toIgnite[nidx] then
						attempts = attempts + 1
						local p = spreadProb(grid, d[1], d[2])
						if p > 0 and lcgNext(grid) < p then
							toIgnite[nidx] = true
						end
					end
				end
			end
		end
	end
	grid.lastAttempts = attempts

	-- 2) advance phases (timers). SMOLDER→BURNING keeps spreading; BURNING→EMBER goes inert.
	for idx = 1, grid.N * grid.N do
		local st = grid.state[idx]
		if st == FireGrid.SMOLDER then
			grid.timer[idx] = grid.timer[idx] - dt
			if grid.timer[idx] <= 0 then
				grid.state[idx] = FireGrid.BURNING
				grid.timer[idx] = grid.burnTime
			end
		elseif st == FireGrid.BURNING then
			grid.timer[idx] = grid.timer[idx] - dt
			if grid.timer[idx] <= 0 then
				grid.state[idx] = FireGrid.EMBER
				grid.timer[idx] = 0
			end
		end
	end

	-- 3) apply deferred ignitions (a new SMOLDER; contributes to spread next tick).
	for idx in pairs(toIgnite) do
		ignite(grid, idx)
	end

	-- 4) track reach (monotone farthest ignited-cell distance from origin).
	--    Only recompute against newly-changed cells is enough; a cheap full scan of active cells
	--    keeps it exact and is O(active).
	for idx = 1, grid.N * grid.N do
		if grid.state[idx] ~= FireGrid.GREEN then
			local cz = math.floor((idx - 1) / grid.N) + 1
			local cx = (idx - 1) % grid.N + 1
			local x, z = cellToWorld(grid, cx, cz)
			local r = math.sqrt(x * x + z * z)
			if r > grid.reach then
				grid.reach = r
			end
		end
	end

	-- 5) refresh the cut-off cache every cutoffCheckEvery ticks (BFS; monotone).
	if grid.tickCount % grid.cutoffCheckEvery == 0 then
		FireGrid.recomputeCutOff(grid)
	end
end

-- FireGrid.step — accumulate dt and run whole 1/tickHz ticks. Returns the number of ticks run
-- (the server calls this from its 0.25s loop; at tickHz 2 that's ~0 or 1 tick per call).
function FireGrid.step(grid, dt)
	grid.acc = grid.acc + (dt or 0)
	local period = 1 / grid.tickHz
	local ran = 0
	while grid.acc >= period do
		grid.acc = grid.acc - period
		tick(grid)
		ran = ran + 1
	end
	return ran
end

--------------------------------------------------------------------------------
-- FireGrid.stateAt — world (x,z) → cell state (GREEN outside the grid box).
--------------------------------------------------------------------------------
function FireGrid.stateAt(grid, x, z)
	local cx, cz = worldToCell(grid, x, z)
	if not cx then
		return FireGrid.GREEN
	end
	return grid.state[cellIndex(grid, cx, cz)]
end

--------------------------------------------------------------------------------
-- Cut-off = multi-source BFS from the NON-BURNABLE rim (the safe world outside the annulus, incl.
-- the pad) through GREEN cells only — SMOLDER/BURNING/EMBER all BLOCK the flood. A grove with no
-- flood-reached GREEN cell inside its disc is CUT OFF (the fire ring walls it off from safety).
-- Monotone: because EMBER blocks too, a cut-off ring never un-cuts (a cut-off grove stays cut off —
-- no embarrassing cancel). Runs O(N*N) every cutoffCheckEvery ticks; the result is cached on the
-- grid so cutOffGroves() is a cheap read.
--------------------------------------------------------------------------------
function FireGrid.recomputeCutOff(grid)
	local N = grid.N
	local reachable = {} -- [idx] = true (GREEN & flood-reached from the safe rim)
	-- BFS queue seeded from every GREEN cell on the grid border (the border is outside the annulus
	-- → non-burnable → safe). We seed from all non-burnable GREEN cells adjacent to the grid edge by
	-- simply seeding the whole outer ring, then flood inward through GREEN cells.
	local queue = {}
	local head = 1

	local function trySeed(cx, cz)
		local idx = cellIndex(grid, cx, cz)
		if grid.state[idx] == FireGrid.GREEN and not reachable[idx] then
			reachable[idx] = true
			queue[#queue + 1] = idx
		end
	end

	-- seed the four borders
	for cx = 1, N do
		trySeed(cx, 1)
		trySeed(cx, N)
	end
	for cz = 1, N do
		trySeed(1, cz)
		trySeed(N, cz)
	end

	-- flood through GREEN cells (N4)
	while head <= #queue do
		local idx = queue[head]
		head = head + 1
		local cz = math.floor((idx - 1) / N) + 1
		local cx = (idx - 1) % N + 1
		for _, d in ipairs(N4) do
			local nx, nz = cx + d[1], cz + d[2]
			if nx >= 1 and nx <= N and nz >= 1 and nz <= N then
				local nidx = cellIndex(grid, nx, nz)
				if grid.state[nidx] == FireGrid.GREEN and not reachable[nidx] then
					reachable[nidx] = true
					queue[#queue + 1] = nidx
				end
			end
		end
	end

	-- a grove is cut off if NO GREEN cell inside its disc is reachable from the safe rim.
	for g, grove in ipairs(grid.groves) do
		if not grid.cutOff[g] then -- monotone: once cut off, stay cut off
			local center = grove.center or grove.centre
			local gr = grove.radius or 130
			local cx0 = (center and center.X) or 0
			local cz0 = (center and center.Z) or 0
			-- scan the cells overlapping the grove disc
			local anyReachableGreen = false
			local anyCellInGrove = false
			local loX, hiX = cx0 - gr, cx0 + gr
			local loZ, hiZ = cz0 - gr, cz0 + gr
			local cxa = math.max(1, math.floor((loX + grid.gridHalf) / grid.cellSize) + 1)
			local cxb = math.min(N, math.floor((hiX + grid.gridHalf) / grid.cellSize) + 1)
			local cza = math.max(1, math.floor((loZ + grid.gridHalf) / grid.cellSize) + 1)
			local czb = math.min(N, math.floor((hiZ + grid.gridHalf) / grid.cellSize) + 1)
			for cz = cza, czb do
				for cx = cxa, cxb do
					local x, z = cellToWorld(grid, cx, cz)
					local ddx, ddz = x - cx0, z - cz0
					if ddx * ddx + ddz * ddz <= gr * gr then
						anyCellInGrove = true
						if reachable[cellIndex(grid, cx, cz)] then
							anyReachableGreen = true
						end
					end
				end
			end
			-- cut off only if the grove has cells AND none of its GREEN cells reach safety. A grove
			-- whose disc is entirely non-burnable (e.g. wholly inside the pad) is never "cut off".
			if anyCellInGrove and not anyReachableGreen then
				grid.cutOff[g] = true
			end
		end
	end

	return grid.cutOff
end

-- FireGrid.cutOffGroves — the cached per-grove cut-off flags (monotone). Recomputed inside step()
-- every cutoffCheckEvery ticks; this is a cheap read.
function FireGrid.cutOffGroves(grid)
	return grid.cutOff
end

--------------------------------------------------------------------------------
-- FireGrid.stats — a summary readout (counts + threat + reach). `threatened` = the fraction of
-- burnable cells that have LEFT green (smolder+burning+ember) — the "has been touched by fire"
-- coverage the SIM asserts as grove threat when scoped to a grove; here it's whole-grid coverage.
-- `groveThreat` = per-grove fraction of the grove's burnable cells that left green (mean over
-- groves) — the §3.3 "threatened ~35-50% of grove area" band.
--------------------------------------------------------------------------------
function FireGrid.stats(grid)
	local green, smolder, burning, ember = 0, 0, 0, 0
	local touched = 0
	for idx = 1, grid.N * grid.N do
		if grid.burnable[idx] then
			local st = grid.state[idx]
			if st == FireGrid.GREEN then
				green = green + 1
			elseif st == FireGrid.SMOLDER then
				smolder = smolder + 1
				touched = touched + 1
			elseif st == FireGrid.BURNING then
				burning = burning + 1
				touched = touched + 1
			elseif st == FireGrid.EMBER then
				ember = ember + 1
				touched = touched + 1
			end
		end
	end
	local activeCount = smolder + burning
	local coverage = 0
	if grid.burnableCount > 0 then
		coverage = touched / grid.burnableCount
	end

	-- per-grove threat: fraction of a grove's burnable cells that left green, meaned over groves.
	local groveThreatSum, groveN = 0, 0
	for _, grove in ipairs(grid.groves) do
		local center = grove.center or grove.centre
		local gr = grove.radius or 130
		local cx0 = (center and center.X) or 0
		local cz0 = (center and center.Z) or 0
		local N = grid.N
		local cxa = math.max(1, math.floor((cx0 - gr + grid.gridHalf) / grid.cellSize) + 1)
		local cxb = math.min(N, math.floor((cx0 + gr + grid.gridHalf) / grid.cellSize) + 1)
		local cza = math.max(1, math.floor((cz0 - gr + grid.gridHalf) / grid.cellSize) + 1)
		local czb = math.min(N, math.floor((cz0 + gr + grid.gridHalf) / grid.cellSize) + 1)
		local gTot, gTouched = 0, 0
		for cz = cza, czb do
			for cx = cxa, cxb do
				local x, z = cellToWorld(grid, cx, cz)
				local ddx, ddz = x - cx0, z - cz0
				if ddx * ddx + ddz * ddz <= gr * gr and grid.burnable[cellIndex(grid, cx, cz)] then
					gTot = gTot + 1
					if grid.state[cellIndex(grid, cx, cz)] ~= FireGrid.GREEN then
						gTouched = gTouched + 1
					end
				end
			end
		end
		if gTot > 0 then
			groveThreatSum = groveThreatSum + gTouched / gTot
			groveN = groveN + 1
		end
	end
	local groveThreat = (groveN > 0) and (groveThreatSum / groveN) or 0

	return {
		green = green,
		smolder = smolder,
		burning = burning,
		ember = ember,
		touched = touched,
		activeCount = activeCount,
		coverage = coverage,
		groveThreat = groveThreat,
		reach = grid.reach,
		burnableCount = grid.burnableCount,
		lastAttempts = grid.lastAttempts or 0,
		tickCount = grid.tickCount,
	}
end

--------------------------------------------------------------------------------
-- FireGrid.burningCells — up to maxN BURNING cells, NEWEST-FIRST (highest igniteOrder), each as
-- {x, z, age}. This is the B2 render seam: the visual layer picks the freshest burning cells to
-- decorate (flipbook + emitter + light), hard-capped at maxVisualBurning. B1 emits NO Instances.
--------------------------------------------------------------------------------
function FireGrid.burningCells(grid, maxN)
	maxN = maxN or grid.maxVisualBurning
	local list = {}
	for idx = 1, grid.N * grid.N do
		if grid.state[idx] == FireGrid.BURNING then
			local cz = math.floor((idx - 1) / grid.N) + 1
			local cx = (idx - 1) % grid.N + 1
			local x, z = cellToWorld(grid, cx, cz)
			list[#list + 1] = { x = x, z = z, order = grid.igniteOrder[idx] }
		end
	end
	-- newest-first by ignition order
	table.sort(list, function(a, b)
		return a.order > b.order
	end)
	local out = {}
	for i = 1, math.min(maxN, #list) do
		out[i] = { x = list[i].x, z = list[i].z, age = list[i].order }
	end
	return out
end

return FireGrid
