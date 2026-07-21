--!nonstrict
--[[
	tests/perf.spec.luau — THE STANDING PERF ENVELOPE, machine-pinned (MASTER-PLAN §3.4).

	S42 Chad directive #4: *"shore it up, optimize."* The envelope was reasoned in prose (GameConfig.Fire
	comments) and partially pinned (firegrid.spec #11 bounds the sim's WORK; firevisuals.spec bounds the
	POOL COUNT) — but nothing pinned what S41 actually changed: the LIVE render config flipped to
	flameStyle="flicker" (+ a second emitter per marker, + the centroid plume), and no gate says what that
	costs. This spec closes that: it drives a REAL round with the LIVE GameConfig and asserts the three
	rails that decide whether the fire stays affordable — especially on the low-end/mobile target Chad
	signalled interest in (directive #3).

	WHAT IT ASSERTS (all deterministic — no wall-clock in any pass/fail):
	  1. PARTICLE BUDGET — worst-case steady-state alive particles across every ENABLED emitter, measured
	     in situ (sum of Rate x Lifetime.Max after a full-fire sync), <= PARTICLE_BUDGET.
	  2. DYNAMIC LIGHT BUDGET — PointLight count <= maxVisualBurning AND every one has Shadows=false
	     (a single Shadows=true light is the biggest single mobile perf cliff in the engine).
	  3. ALLOCATION-FREE SYNC — the container's Instance count is CONSTANT across 100 syncs of an evolving
	     fire. This is the "no per-tick Instance.new" rail: the pool is allocated once, forever.

	WHAT IT ONLY REPORTS (never fails): wall-clock ms for FireGrid.step and FireVisuals:sync. Timing on
	the Lune interpreter is not Roblox's VM and CI machines vary, so a timing assertion would be a flake
	factory. The numbers are PRINTED every run so a 10x regression is visible in the ladder output, and a
	generous SANITY rail (below) still catches a pathological blow-up.

	Honest limit (same class as models.spec / firevisuals.spec): this proves the fire's cost STRUCTURE is
	bounded. It does NOT prove the frame rate in Studio — that stays Chad's Play + GameConfig.Fire.perfDiag.
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Vector3 = Loader.Vector3
local Instance = Loader.Instance

local GameConfig = Loader.load("GameConfig")
local FireGrid = Loader.load("FireGrid")
local FireVisuals = Loader.load("FireVisuals")

--------------------------------------------------------------------------------
-- RAILS (derivations, not magic numbers). Each is ~35-50% above the measured live
-- value so an intentional dial nudge passes but a 2x regression fails loudly.
--------------------------------------------------------------------------------
-- Live worst case (flicker, 30 markers drawn): smoke 30 x 6/s x 4.0s life = 720,
-- flame 30 x 10/s x 0.9s = 270, centroid plume min(20, 2+0.5*30)=17/s x 10s = 170.
-- => ~1160 alive. Roblox desktop absorbs several thousand; ~1000-1500 is the sane
-- low-end/mobile ceiling, so the rail sits just above the live figure.
local PARTICLE_BUDGET = 1600

-- Pathological-only sanity rails on the Lune interpreter (NOT a Roblox budget).
-- Live measurements sit ~2 orders of magnitude below these.
local SANITY_TICK_MS = 50
local SANITY_SYNC_MS = 50

--------------------------------------------------------------------------------
-- Harness world: the 4-grove / r130 / gap520 placement the round actually ships
-- (GameConfig.Missions.ember_valley.placement), wind +X, live Fire config.
--------------------------------------------------------------------------------
local function harnessGroves()
	return {
		{ center = Vector3.new(700, 0, 0), radius = 130 },
		{ center = Vector3.new(-600, 0, 400), radius = 130 },
		{ center = Vector3.new(100, 0, -800), radius = 130 },
		{ center = Vector3.new(-300, 0, 900), radius = 130 },
	}
end

local function liveGrid(seed)
	return FireGrid.new(
		GameConfig.Fire, seed or 20260721, Vector3.new(1, 0, 0),
		harnessGroves(), GameConfig.Rescue.deliverPos)
end

-- Burn until the drawn-marker set is saturated (>= the pool cap, or the round ends).
local function saturatedFire()
	local grid = liveGrid()
	FireGrid.seedUpwind(grid)
	FireGrid.step(grid, 80) -- past smolder(15-25) + into a wide BURNING band
	return grid
end

local function descendantCount(container)
	return #container:GetDescendants()
end

local function collect(container, className)
	local out = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d.ClassName == className then out[#out + 1] = d end
	end
	return out
end

--------------------------------------------------------------------------------
-- 1) PARTICLE BUDGET — measured in situ at full fire under the LIVE config.
--------------------------------------------------------------------------------
H.test("§3.4 particle budget: worst-case alive particles under the LIVE fire config <= " .. PARTICLE_BUDGET, function()
	local container = Instance.new("Folder")
	local grid = saturatedFire()
	local vis = FireVisuals.new(FireGrid, GameConfig.Fire, GameConfig.Fire.cellSize, container)
	local drawn = vis:sync(grid, {}, 60)

	local alive, enabled = 0, 0
	for _, e in ipairs(collect(container, "ParticleEmitter")) do
		if e.Enabled then
			enabled += 1
			alive += (e.Rate or 0) * (e.Lifetime and e.Lifetime.Max or 0)
		end
	end

	print(("      [perf] fire particles: %d emitters enabled, ~%.0f alive worst-case (markers drawn %d, style=%s)")
		:format(enabled, alive, drawn or -1, tostring(GameConfig.Fire.flameStyle)))

	H.ok(drawn and drawn > 0, "the harness fire actually drew markers (else this rail is vacuous)")
	H.ok(alive <= PARTICLE_BUDGET,
		("alive particles %.0f exceeds the §3.4 budget %d — a rate/lifetime/cap dial went up; re-derive before shipping")
			:format(alive, PARTICLE_BUDGET))
end)

--------------------------------------------------------------------------------
-- 2) DYNAMIC LIGHT BUDGET — count capped AND no shadow-casting light anywhere.
--------------------------------------------------------------------------------
H.test("§3.4 light budget: PointLights <= maxVisualBurning and NONE cast shadows", function()
	local container = Instance.new("Folder")
	local grid = saturatedFire()
	local vis = FireVisuals.new(FireGrid, GameConfig.Fire, GameConfig.Fire.cellSize, container)
	vis:sync(grid, {}, 60)

	local lights = collect(container, "PointLight")
	local cap = GameConfig.Fire.maxVisualBurning or 30
	local shadowed = 0
	for _, l in ipairs(lights) do
		if l.Shadows == true then shadowed += 1 end
	end
	print(("      [perf] fire lights: %d (cap %d), shadow-casting %d"):format(#lights, cap, shadowed))

	H.ok(#lights > 0, "no fire lights at all — the rails below would pass vacuously")
	H.ok(#lights <= cap, ("PointLight count %d exceeds the pool cap %d"):format(#lights, cap))
	H.eq(shadowed, 0, "shadow-casting fire lights (the single biggest low-end/mobile perf cliff)")
end)

--------------------------------------------------------------------------------
-- 3) ALLOCATION-FREE SYNC — the pool is allocated ONCE; 100 syncs of an evolving
--    fire must not create or destroy a single Instance.
--------------------------------------------------------------------------------
H.test("§3.4 allocation-free: 100 syncs of an evolving fire create/destroy ZERO Instances", function()
	local container = Instance.new("Folder")
	local grid = liveGrid(777)
	FireGrid.seedUpwind(grid)
	local vis = FireVisuals.new(FireGrid, GameConfig.Fire, GameConfig.Fire.cellSize, container)

	-- first sync allocates the lazy per-grove rings; count AFTER it so the rail measures steady state.
	FireGrid.step(grid, 20)
	vis:sync(grid, {}, 20)
	local baseline = descendantCount(container)

	local elapsed = 20
	local drawnMin, drawnMax = math.huge, -math.huge
	for i = 1, 100 do
		FireGrid.step(grid, 1.0)
		elapsed += 1.0
		-- exercise the cut-off ring path too (a grove under countdown) — rings are the lazy-alloc risk.
		local drawn = vis:sync(grid, { [1] = elapsed + 4 }, elapsed) or 0
		if drawn < drawnMin then drawnMin = drawn end
		if drawn > drawnMax then drawnMax = drawn end
	end
	-- anti-vacuity: the fire must actually have EVOLVED across those syncs, else "no allocation" is
	-- just "nothing happened".
	H.ok(drawnMax > 0 and drawnMax ~= drawnMin,
		("the harness fire never evolved across 100 syncs (drawn %d..%d) — the rail would be vacuous")
			:format(drawnMin, drawnMax))

	local after = descendantCount(container)
	print(("      [perf] instances: %d after first sync, %d after 100 more (delta %d)")
		:format(baseline, after, after - baseline))
	H.eq(after, baseline, "FireVisuals:sync allocated or destroyed Instances (it must be property-writes only)")
end)

--------------------------------------------------------------------------------
-- 4) TIMING — reported every run, gated only against the pathological.
--------------------------------------------------------------------------------
H.test("§3.4 timing (reported; pathological-only rail)", function()
	local container = Instance.new("Folder")
	local grid = liveGrid(4242)
	local vis = FireVisuals.new(FireGrid, GameConfig.Fire, GameConfig.Fire.cellSize, container)

	local roundS = (GameConfig.Rescue and GameConfig.Rescue.roundSeconds) or 120
	local cadence = 0.25          -- the server round loop's real cadence
	local visualEvery = math.max(1, GameConfig.Fire.visualEvery or 2)

	local seeded = false
	local elapsed, visualTick = 0, 0
	local worstStep, sumStep, nStep = 0, 0, 0
	local worstSync, sumSync, nSync = 0, 0, 0
	local peakDrawn = 0

	while elapsed < roundS do
		local t0 = os.clock()
		local ran = FireGrid.step(grid, cadence)
		local dtStep = (os.clock() - t0) * 1000
		sumStep += dtStep; nStep += 1
		if dtStep > worstStep then worstStep = dtStep end

		elapsed += cadence
		if not seeded and elapsed >= (GameConfig.Fire.igniteAt or 10) then
			seeded = true
			FireGrid.seedUpwind(grid)
		end

		if ran > 0 then
			visualTick += ran
			if visualTick >= visualEvery then
				visualTick = 0
				local t1 = os.clock()
				local drawn = vis:sync(grid, {}, elapsed)
				local dtSync = (os.clock() - t1) * 1000
				sumSync += dtSync; nSync += 1
				if dtSync > worstSync then worstSync = dtSync end
				if (drawn or 0) > peakDrawn then peakDrawn = drawn end
			end
		end
	end

	print(("      [perf] FireGrid.step over a %ds round: worst %.2fms, mean %.3fms (%d calls)")
		:format(roundS, worstStep, sumStep / math.max(1, nStep), nStep))
	print(("      [perf] FireVisuals:sync: worst %.2fms, mean %.3fms (%d renders, peak markers %d)")
		:format(worstSync, sumSync / math.max(1, nSync), nSync, peakDrawn))
	print("      [perf] NOTE: Lune-interpreter timings, NOT Roblox — informational trend, not the 1.5ms budget.")

	H.ok(nSync > 0, "the round actually rendered the fire (else the timings are vacuous)")
	H.ok(worstStep < SANITY_TICK_MS,
		("FireGrid.step worst %.2fms exceeded the pathological rail %dms"):format(worstStep, SANITY_TICK_MS))
	H.ok(worstSync < SANITY_SYNC_MS,
		("FireVisuals:sync worst %.2fms exceeded the pathological rail %dms"):format(worstSync, SANITY_SYNC_MS))
end)
