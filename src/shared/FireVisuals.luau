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

	STAGE 2 (kid-legibility, docs/KID-LEGIBILITY-PLAN.md §Stage-2):
	  flameStyle="flicker" enables teardrop two-tone shape + flame ParticleEmitter + leaning smoke
	  + ONE centroid mega-plume. All allocate-once at .new time. sync does arithmetic + property
	  writes only (no allocation). flameStyle="static" (default) is byte-identical to pre-Stage-2.

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
-- STAGE 2: under flameStyle="flicker", also builds teardrop Ball shape + inner yellow core +
-- flame ParticleEmitter + darker/bigger smoke. Under "static" (default) = byte-identical to
-- pre-Stage-2. core and flame are nil under "static".
--------------------------------------------------------------------------------
function FireVisuals.buildCellSet(cfg, cellSize, parent)
	local h = cfg.markerHeight or 34
	local w = math.max(6, (cellSize or 60) * 0.55)

	-- STAGE 2 identity gate: compute once at the top.
	local flicker = (cfg.flameStyle == "flicker")

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

	-- STAGE 2: teardrop outer shell replaces the box — a tall orange Ball reads as fire shape
	-- even frozen from altitude. CanCollide false so the sphere-collision caveat is moot.
	if flicker then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(w * 0.9, h, w * 0.9)
		part.Transparency = 0.25
	end

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

	-- STAGE 2: darker/bigger smoke so from altitude it's a visible smudge on the horizon.
	if flicker then
		smoke.Color = ColorSequence.new(Color3.fromRGB(45, 40, 37), Color3.fromRGB(95, 88, 83))
		smoke.Size = NumberSequence.new(w * 0.8, w * 2.2)
		smoke.Lifetime = NumberRange.new(2.5, 4.0)
	end

	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = ORANGE
	light.Brightness = cfg.lightBrightness or 2.0
	light.Range = cfg.lightRange or 90
	light.Shadows = false
	light.Parent = part

	-- STAGE 2: inner yellow core (the two-tone taper that kills "square" at distance).
	-- Parented under the shell for containment; sync drives its CFrame independently.
	local core = nil
	if flicker then
		local cr = cfg.teardropCoreRatio or 0.45
		core = Instance.new("Part")
		core.Name = "FlameCore"
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(w * 0.9 * cr, h * cr, w * 0.9 * cr)
		core.Anchored = true
		core.CanCollide = false
		core.CanQuery = false
		core.CanTouch = false
		core.CastShadow = false
		core.Material = Enum.Material.Neon
		core.Color = Color3.fromRGB(255, 235, 120)  -- hot yellow heart
		core.Transparency = 0
		core.Parent = part
	end

	-- STAGE 2: flame ParticleEmitter at the shell base so licks rise THROUGH the shape.
	-- Uses Roblox's built-in fire sprite for guaranteed kid-warm palette.
	-- CONTINGENCY (do not build now): if fire_main.dds misrenders in Studio, one-line swap:
	--   local fire = Instance.new("Fire"); fire.Parent = part
	-- (pool-capped by construction; the literal "kid sees fire" object).
	local flame = nil
	if flicker then
		local flameAtt = Instance.new("Attachment")
		flameAtt.Name = "FlameAtt"
		flameAtt.Position = Vector3.new(0, -h * 0.25, 0)
		flameAtt.Parent = part
		flame = Instance.new("ParticleEmitter")
		flame.Name = "Flame"
		flame.Texture = "rbxasset://textures/particles/fire_main.dds"  -- Roblox built-in fire sprite
		flame.LightEmission = 1                                        -- additive = glows, kid-warm not gory
		flame.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 120)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 35, 15)),
		})
		flame.Size = NumberSequence.new({                              -- grow-then-shrink lick
			NumberSequenceKeypoint.new(0, w * 0.35),
			NumberSequenceKeypoint.new(0.3, w * 0.55),
			NumberSequenceKeypoint.new(1, w * 0.1),
		})
		flame.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		flame.Lifetime = NumberRange.new(0.5, 0.9)  -- short = licking, not a smoke column
		flame.Rate = cfg.flameRate or 10
		flame.Speed = NumberRange.new(8, 14)         -- upward
		flame.SpreadAngle = Vector2.new(12, 12)      -- slight wander
		flame.Enabled = false                        -- sync enables exactly like smoke
		flame.Parent = flameAtt
	end

	part.Parent = parent

	-- Compute core vertical offset from the marker base (negative = below centre = sits at base).
	local coreOffsetY = core and (-h * 0.5 + core.Size.Y * 0.5) or 0

	return {
		part = part, smoke = smoke, light = light,
		core = core, flame = flame,
		baseW = part.Size.X, baseH = part.Size.Y,
		coreOffsetY = coreOffsetY,
	}
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
-- NOTE: buildRing is reused by Stage 1 at RescueServer L346 — do NOT touch its signature or behavior.
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
-- STAGE 2: ONE mega centroid plume — the long-range "there's a wildfire over THERE" read.
-- One invisible anchored anchor part + ONE big dark long-lived emitter, repositioned to the
-- burning-set centroid each sync; Rate grows with the burning count (urgency channel).
-- Allocated ONCE in FireVisuals.new, only under flameStyle=="flicker". ONE emitter total.
--------------------------------------------------------------------------------
function FireVisuals.buildCentroidPlume(cfg, parent)
	local anchor = Instance.new("Part")
	anchor.Name = "PlumeAnchor"
	anchor.Size = Vector3.new(4, 4, 4)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	local att = Instance.new("Attachment")
	att.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MegaPlume"
	emitter.Color = ColorSequence.new(Color3.fromRGB(55, 50, 48), Color3.fromRGB(110, 104, 100))
	emitter.LightEmission = 0
	emitter.Size = NumberSequence.new(cfg.plumeSizeMin or 20, cfg.plumeSizeMax or 80)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(6, 10)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(10, 16)
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.Enabled = false
	emitter.Parent = att
	anchor.Parent = parent
	return { part = anchor, emitter = emitter }
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

	-- STAGE 2: ONE centroid plume, allocated only under flicker. Under static: nil → container
	-- Instance tree is byte-identical to pre-Stage-2.
	self.flicker = (cfg.flameStyle == "flicker")
	self.plume = nil
	if self.flicker then
		self.plume = FireVisuals.buildCentroidPlume(cfg, container)
		self.plume.part.CFrame = CFrame.new(0, -5000, 0)
	end

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
-- STAGE 2: under flicker, also writes teardrop breathing + flame enable + smoke lean + plume drive.
-- Under static (default): every new code path is gated behind `if flicker then` → zero new writes.
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

	-- STAGE 2: precompute per-sync constants (only used under flicker; computed once here).
	local flicker = self.flicker
	local lean = self.cfg.smokeLeanStrength or 0
	local wx, wz = grid.windX or 0, grid.windZ or 0
	-- leanCF: rotation that tips the teardrop's up-vector toward the wind.
	-- axis = up × wind = (wz, 0, -wx) in XZ plane.
	local leanCF = nil
	if flicker then
		leanCF = CFrame.fromAxisAngle(Vector3.new(wz, 0, -wx), math.rad(self.cfg.teardropLeanDeg or 8))
	end
	local amp = self.cfg.flickerAmp or 0.15
	local cx, cz = 0, 0  -- centroid accumulator for the mega-plume

	for i = 1, self.maxBurning do
		local set = self.cellPool[i]
		local b = burning[i]
		if b then
			local t = (b.age - minAge) / span
			local col = ageColor(t)
			if flicker then
				-- STAGE 2: deterministic 1Hz breathing — phase from tickN + cell position (NO math.random).
				local ph = b.x * 0.013 + b.z * 0.007 + self.tickN * 1.3
				local s = 1 + amp * math.sin(ph)
				set.part.Size = Vector3.new(set.baseW, set.baseH * s, set.baseW)
				-- lean the teardrop downwind.
				local place = CFrame.new(b.x, (self.cfg.markerHeight or 34) * 0.5, b.z) * leanCF
				set.part.CFrame = place
				-- drive the inner core to its base position.
				set.core.CFrame = place * CFrame.new(0, set.coreOffsetY, 0)
				set.core.Color = Color3.fromRGB(255, 235, 120)
				set.core.Transparency = 0
				set.flame.Enabled = true
				-- accumulate centroid.
				cx += b.x; cz += b.z
			else
				set.part.CFrame = CFrame.new(b.x, (self.cfg.markerHeight or 34) * 0.5, b.z)
			end
			set.part.Color = col
			set.part.Transparency = 0.1
			set.light.Color = col
			set.light.Enabled = true
			set.smoke.Enabled = true
			-- STAGE 2: lean the smoke plume toward the wind.
			-- lean==0 → this branch never writes → Acceleration stays build-time (0,26,0) = identity.
			if lean ~= 0 then
				set.smoke.Acceleration = Vector3.new(wx * lean, 26, wz * lean)
			end
		else
			-- cull: park + silence (no destroy)
			set.part.Transparency = 1
			set.light.Enabled = false
			set.smoke.Enabled = false
			set.part.CFrame = CFrame.new(0, -5000, 0)
			if flicker then
				set.flame.Enabled = false
				set.core.Transparency = 1
				set.core.CFrame = set.part.CFrame
			end
		end
	end

	-- STAGE 2: drive the ONE centroid mega-plume (nil under static — no-op).
	if self.plume then
		if n > 0 then
			local px, pz = cx / n, cz / n
			self.plume.part.CFrame = CFrame.new(px, (self.cfg.markerHeight or 34), pz)
			self.plume.emitter.Rate = math.min(
				self.cfg.plumeRateMax or 20,
				(self.cfg.plumeRateBase or 2) + (self.cfg.plumeRatePerCell or 0.5) * n)
			self.plume.emitter.Acceleration = Vector3.new(wx * lean, self.cfg.plumeRise or 14, wz * lean)
			self.plume.emitter.Enabled = true
		else
			self.plume.emitter.Enabled = false
			self.plume.part.CFrame = CFrame.new(0, -5000, 0)
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
				local cz2 = math.floor((idx - 1) / N) + 1
				local cx2 = (idx - 1) % N + 1
				local x = (cx2 - 1 + 0.5) * cs - grid.gridHalf
				local z = (cz2 - 1 + 0.5) * cs - grid.gridHalf
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
	if self.plume then self.plume.part:Destroy(); self.plume = nil end
	self.cellPool, self.emberPool, self.ringPool = {}, {}, {}
end

return FireVisuals
