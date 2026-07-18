--!nonstrict
--[[
	FireVisuals.luau — the B2 RENDER layer for the FireGrid (Eagles-to-the-Rescue, packet B2).

	Turns the pure, simulation-tuned FireGrid state into a POOLED, budgeted set of Workspace
	Instances so "Ember Valley" becomes something Chad can see and fly. Built server-side (the fire
	is server-authoritative — same pattern as squirrels/beacons) so it replicates to all clients.

	INERT under waterfall_meadow: the server only calls FireVisuals.new / :sync when the active
	mission's hazard.kind=="fire". With the shipped triage mission there is NO folder, NO parts,
	ZERO cost — this module is never touched.

	POOLING is the whole perf story (§3.3: ≤30 BURNING cells, each ≤ 1 marker + 1 smoke emitter +
	1 PointLight, hard-capped): the pool is allocated ONCE at maxVisualBurning and REPOSITIONED /
	RECOLORED each render — NEVER create+destroy 30 parts per tick (that was the named perf killer).
	EMBER cells get a cheap charred-ground TINT (a color swap, no light/emitter) from a small pooled
	subset. Trees NEVER deform. The cut-off countdown RING pulses over a grove about to be
	ranger-rescued so the read is "grab who you can".

	This module is PURE-shape / Instance-only (no services, no clock, no task) so the loader can
	build one cell-set + a ring HEADLESSLY (tests/firevisuals.spec.luau — the S40 rule: a new visual
	element class ships a geometry test). Wall-clock/refresh CADENCE is the server's concern; here
	`sync` is called by the server and does the arithmetic + Instance property writes only.

	Seam it renders FROM (all reads, no writes back): FireGrid.burningCells(grid, maxN) → newest-first
	{x,z,age}; FireGrid.stateAt(grid,x,z); FireGrid.EMBER; grid.cellSize / grid.groves. Config lives
	in GameConfig.Fire (the *Visual* dials added in B2).
]]

local FireVisuals = {}
FireVisuals.__index = FireVisuals

-- Warm burn palette. Newest burning cell = bright orange; older = deep red (age = ignition order,
-- higher = newer). We normalize within the current burning set so the freshest edge always glows.
local ORANGE = Color3.fromRGB(255, 150, 40)
local RED = Color3.fromRGB(190, 40, 20)

-- age→color: t in [0,1] where 1 = newest. Newest orange, oldest red.
local function ageColor(t)
	t = math.clamp(t, 0, 1)
	return Color3.new(
		RED.R + (ORANGE.R - RED.R) * t,
		RED.G + (ORANGE.G - RED.G) * t,
		RED.B + (ORANGE.B - RED.B) * t
	)
end

--------------------------------------------------------------------------------
-- One BURNING-cell visual set: a neon marker column + ONE smoke emitter + ONE warm PointLight.
-- Built once, then repositioned/recolored by :sync. cellSize sizes the marker footprint.
--------------------------------------------------------------------------------
function FireVisuals.buildCellSet(cfg, cellSize, parent)
	local h = cfg.markerHeight or 34
	local w = math.max(6, (cellSize or 60) * 0.55)

	local part = Instance.new("Part")
	part.Name = "FireCell"
	part.Size = Vector3.new(w, h, w)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false          -- the eagle flies THROUGH the flame (no accidental crashes)
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = ORANGE
	part.Transparency = 0.1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local att = Instance.new("Attachment")
	att.Name = "SmokeAtt"
	att.Position = Vector3.new(0, h * 0.5, 0)
	att.Parent = part

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 62, 58), Color3.fromRGB(120, 110, 104))
	smoke.LightEmission = 0.1
	smoke.Size = NumberSequence.new(w * 0.6, w * 1.6)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.6, 2.6)
	smoke.Rate = cfg.smokeRate or 6
	smoke.Speed = NumberRange.new(24, 40)
	smoke.SpreadAngle = Vector2.new(16, 16)
	smoke.Acceleration = Vector3.new(0, 26, 0)
	smoke.Parent = att

	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = ORANGE
	light.Brightness = cfg.lightBrightness or 2.0
	light.Range = cfg.lightRange or 90
	light.Shadows = false
	light.Parent = part

	part.Parent = parent
	return { part = part, smoke = smoke, light = light }
end

--------------------------------------------------------------------------------
-- One EMBER tint patch: a flat charred-ground disc (NO emitter, NO light — a free color per §3.3).
--------------------------------------------------------------------------------
function FireVisuals.buildEmberPatch(cfg, cellSize, parent)
	local w = math.max(6, (cellSize or 60) * 0.9)
	local patch = Instance.new("Part")
	patch.Name = "EmberTint"
	patch.Size = Vector3.new(w, 1, w)
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CanTouch = false
	patch.CastShadow = false
	patch.Material = Enum.Material.Slate
	patch.Color = cfg.emberTint or Color3.fromRGB(46, 34, 28)
	patch.TopSurface = Enum.SurfaceType.Smooth
	patch.BottomSurface = Enum.SurfaceType.Smooth
	patch.Parent = parent
	return { part = patch }
end

--------------------------------------------------------------------------------
-- One cut-off countdown RING: a thin neon torus-ish ring (a flat cylinder outline) at a grove centre.
-- Reused per grove; :sync scales/pulses/hides it off fireGraceUntil.
--------------------------------------------------------------------------------
function FireVisuals.buildRing(cfg, radius, parent)
	local ring = Instance.new("Part")
	ring.Name = "CutOffRing"
	ring.Shape = Enum.PartType.Cylinder
	-- A thin flat disc: cylinder length (its X) is the disc THICKNESS; the round face has diameter 2*radius.
	ring.Size = Vector3.new(3, radius * 2, radius * 2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = cfg.ringColor or Color3.fromRGB(255, 90, 40)
	ring.Transparency = 0.35
	-- lay the disc flat (face up) — cylinder's length axis is X, rotate it onto Y.
	ring.CFrame = CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = parent
	return { part = ring }
end

--------------------------------------------------------------------------------
-- FireVisuals.new — allocate the whole POOL up front (server passes a Workspace Folder as `container`;
-- headless tests pass a plain Folder). No per-tick allocation ever happens after this. Returns a
-- controller with :sync and :destroy.
--------------------------------------------------------------------------------
function FireVisuals.new(FireGrid, cfg, cellSize, container)
	local self = setmetatable({}, FireVisuals)
	self.FireGrid = FireGrid
	self.cfg = cfg or {}
	self.cellSize = cellSize or 60
	self.container = container
	self.maxBurning = cfg.maxVisualBurning or 30
	self.maxEmber = cfg.maxVisualEmber or 40

	-- pooled burning-cell sets (allocated once).
	self.cellPool = {}
	for i = 1, self.maxBurning do
		self.cellPool[i] = FireVisuals.buildCellSet(cfg, self.cellSize, container)
		self.cellPool[i].part.Transparency = 1
		self.cellPool[i].part.CFrame = CFrame.new(0, -5000, 0) -- parked below the world until used
		self.cellPool[i].smoke.Enabled = false
		self.cellPool[i].light.Enabled = false
	end

	-- pooled ember tint patches.
	self.emberPool = {}
	for i = 1, self.maxEmber do
		self.emberPool[i] = FireVisuals.buildEmberPatch(cfg, self.cellSize, container)
		self.emberPool[i].part.Transparency = 1
		self.emberPool[i].part.CFrame = CFrame.new(0, -5000, 0)
	end

	-- one ring per grove (allocated from the grid's grove list; hidden until that grove is cut off).
	self.ringPool = {}
	self.tickN = 0

	return self
end

-- Allocate rings lazily to match the grove list (called on first sync once groves are known).
function FireVisuals._ensureRings(self, grid)
	if #self.ringPool > 0 or not grid.groves then return end
	for g, grove in ipairs(grid.groves) do
		local r = FireVisuals.buildRing(self.cfg, (grove.radius or 130), self.container)
		local c = grove.center or grove.centre
		r.center = c
		r.part.CFrame = CFrame.new((c and c.X) or 0, 4, (c and c.Z) or 0) * CFrame.Angles(0, 0, math.rad(90))
		r.part.Transparency = 1
		self.ringPool[g] = r
	end
end

--------------------------------------------------------------------------------
-- FireVisuals.sync — the per-render pass (server calls it every visualEvery fire-ticks). Repositions
-- and recolors the POOL from the grid; culls markers whose cell is no longer BURNING; tints EMBER
-- cells; drives the cut-off rings off graceUntil. Returns the number of burning cells drawn (for the
-- perf diag). `graceUntil` = {[g]=deadlineElapsed}; `elapsed` = round-elapsed seconds (for ring pulse).
--
-- PURE arithmetic + Instance property writes only (no allocation) — this is what keeps it ≤1.5ms.
--------------------------------------------------------------------------------
function FireVisuals.sync(self, grid, graceUntil, elapsed)
	local FireGrid = self.FireGrid
	self.tickN = (self.tickN or 0) + 1
	FireVisuals._ensureRings(self, grid)

	-- BURNING: newest-first, capped at maxBurning. Reposition/recolor the pool; park the rest.
	local burning = FireGrid.burningCells(grid, self.maxBurning)
	local n = #burning
	-- age normalization within this set (newest → orange). ages are monotone ignition ids.
	local minAge, maxAge = math.huge, -math.huge
	for i = 1, n do
		local a = burning[i].age
		if a < minAge then minAge = a end
		if a > maxAge then maxAge = a end
	end
	local span = math.max(1, maxAge - minAge)

	for i = 1, self.maxBurning do
		local set = self.cellPool[i]
		local b = burning[i]
		if b then
			local t = (b.age - minAge) / span
			local col = ageColor(t)
			set.part.CFrame = CFrame.new(b.x, (self.cfg.markerHeight or 34) * 0.5, b.z)
			set.part.Color = col
			set.part.Transparency = 0.1
			set.light.Color = col
			set.light.Enabled = true
			set.smoke.Enabled = true
		else
			-- cull: park + silence (no destroy)
			set.part.Transparency = 1
			set.light.Enabled = false
			set.smoke.Enabled = false
			set.part.CFrame = CFrame.new(0, -5000, 0)
		end
	end

	-- EMBER: a coarse pooled subset (§3.3 — a free tint, but instances aren't free, so cap at maxEmber).
	-- Sample the grid on a stride so a few charred patches read without matching the burning budget.
	local emberCount = 0
	if self.maxEmber > 0 then
		local cs = grid.cellSize
		local N = grid.N
		-- stride the grid so we visit at most ~maxEmber ember cells cheaply (coarse representation).
		local stride = math.max(1, math.floor((N * N) / math.max(1, self.maxEmber * 6)))
		local idx = 1
		while idx <= N * N and emberCount < self.maxEmber do
			if grid.state[idx] == FireGrid.EMBER then
				local cz = math.floor((idx - 1) / N) + 1
				local cx = (idx - 1) % N + 1
				local x = (cx - 1 + 0.5) * cs - grid.gridHalf
				local z = (cz - 1 + 0.5) * cs - grid.gridHalf
				emberCount = emberCount + 1
				local patch = self.emberPool[emberCount]
				patch.part.CFrame = CFrame.new(x, 0.5, z)
				patch.part.Transparency = 0.15
			end
			idx = idx + stride
		end
	end
	-- park unused ember patches
	for i = emberCount + 1, self.maxEmber do
		local patch = self.emberPool[i]
		if patch.part.Transparency < 1 then
			patch.part.Transparency = 1
			patch.part.CFrame = CFrame.new(0, -5000, 0)
		end
	end

	-- CUT-OFF RINGS: for each grove with an active grace deadline, show a pulsing shrinking ring.
	graceUntil = graceUntil or {}
	elapsed = elapsed or 0
	for g, r in ipairs(self.ringPool) do
		local deadline = graceUntil[g]
		if deadline and elapsed < deadline then
			-- pulse: transparency oscillates; scale shrinks toward the deadline (grab-who-you-can urgency).
			local remain = deadline - elapsed
			local pulse = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(elapsed * 6))
			r.part.Transparency = pulse
			r.part.Color = self.cfg.ringColor or Color3.fromRGB(255, 90, 40)
			-- keep it flat at the grove centre; visibility via transparency (no per-frame reflow cost).
			local c = r.center
			if c then
				r.part.CFrame = CFrame.new(c.X, 4, c.Z) * CFrame.Angles(0, 0, math.rad(90))
			end
			r._active = true
			r._remain = remain
		elseif r._active then
			r.part.Transparency = 1
			r._active = false
		end
	end

	return n
end

function FireVisuals.destroy(self)
	for _, set in ipairs(self.cellPool) do set.part:Destroy() end
	for _, p in ipairs(self.emberPool) do p.part:Destroy() end
	for _, r in ipairs(self.ringPool) do r.part:Destroy() end
	self.cellPool, self.emberPool, self.ringPool = {}, {}, {}
end

return FireVisuals
