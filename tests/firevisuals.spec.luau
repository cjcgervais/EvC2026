--!nonstrict
--[[
	tests/firevisuals.spec.luau — headless GEOMETRY gate for the B2 fire render layer (FireVisuals.luau).

	WHY (the S40 rule, models.spec's charter): a new VISUAL element class ships a geometry test — a code
	audit can't see whether a marker is visible, whether the pool respects the ≤30 budget, or whether the
	cut-off ring is a real disc. @lune/roblox builds the REAL Instance tree FireVisuals emits, so we build a
	fire grid, burn it, render it, and assert STRUCTURE + the BUDGET CAP + non-degenerate geometry — the
	class of "invisible / unbudgeted fire" bug that would otherwise only surface in Chad's Play.

	Honest limit (same as models.spec): this proves present, visible, budgeted, correctly-shaped. It does NOT
	judge how the burn READS in motion — that's Gate-B Play (Tier 5) + the server perf-diag.

	STAGE 2 tests (7 new) assert:
	  - static path leaks NO Stage-2 instances and smoke stays straight-up (identity gate).
	  - flicker path: flame emitter present + correct; teardrop two-tone geometry; lean sign matches wind +
	    real spread direction (telegraph honesty); budget cap + allocate-once; exactly ONE centroid plume;
	    deterministic breathing.
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Vector3 = Loader.Vector3
local Instance = Loader.Instance
local Enum = Loader.Enum

local GameConfig = Loader.load("GameConfig")
local FireGrid = Loader.load("FireGrid")
local FireVisuals = Loader.load("FireVisuals")

-- A small container "Folder" (any Instance the builder can :Parent into).
local function newContainer()
	return Instance.new("Folder")
end

-- Build a burning grid: 3 groves, seed upwind, step well past igniteAt so a fat BURNING+EMBER set exists.
local function burningGrid()
	local groves = {
		{ center = Vector3.new(500, 0, 0), radius = 130 },
		{ center = Vector3.new(-500, 0, 300), radius = 130 },
		{ center = Vector3.new(0, 0, -600), radius = 130 },
	}
	local grid = FireGrid.new(GameConfig.Fire, 12345, Vector3.new(1, 0, 0), groves, GameConfig.Rescue.deliverPos)
	FireGrid.seedUpwind(grid)
	-- step ~60s so cells reach BURNING and some reach EMBER (smolder 15-25s + burn 20s).
	FireGrid.step(grid, 70)
	return grid
end

-- STAGE 2: flicker config helper. Clones GameConfig.Fire and enables the flicker path.
local function flickerCfg()
	local c = table.clone(GameConfig.Fire)
	c.flameStyle = "flicker"
	c.smokeLeanStrength = 22
	return c
end

-- STAGE 2: static (pre-Stage-2 identity) config. The LIVE default flipped to "flicker" in S41
-- (Chad-approved read), so the static/identity path must be requested explicitly here.
local function staticCfg()
	local c = table.clone(GameConfig.Fire)
	c.flameStyle = "static"
	c.smokeLeanStrength = 0
	return c
end

local function countClass(part, className)
	local n = 0
	for _, d in ipairs(part:GetDescendants()) do
		if d.ClassName == className then n += 1 end
	end
	return n
end

local function countNamed(part, className, name)
	local n = 0
	for _, d in ipairs(part:GetDescendants()) do
		if d.ClassName == className and d.Name == name then n += 1 end
	end
	return n
end

-- ── ORIGINAL 6 TESTS (must keep passing; the marker-structure ones pin the STATIC path — the
--    live default is now "flicker", so static is requested explicitly via staticCfg()) ───────────

H.test("buildCellSet: one burning marker = 1 Neon Part + 1 smoke emitter + 1 PointLight, non-degenerate", function()
	local folder = newContainer()
	local set = FireVisuals.buildCellSet(staticCfg(), 60, folder)
	H.ok(set.part and set.part.ClassName == "Part", "cell set has a Part marker")
	H.ok(set.part.Material == Enum.Material.Neon, "marker is Neon (glows)")
	H.ok(set.part.Size.X > 0 and set.part.Size.Y > 0 and set.part.Size.Z > 0, "marker has positive size")
	H.ok(set.part.CanQuery == false, "marker is CanQuery=false (eagle flies through the flame)")
	H.eq(countClass(set.part, "ParticleEmitter"), 1, "exactly ONE smoke emitter")
	H.eq(countClass(set.part, "PointLight"), 1, "exactly ONE PointLight")
end)

H.test("buildRing: cut-off ring is a real disc at grove radius", function()
	local folder = newContainer()
	local r = FireVisuals.buildRing(GameConfig.Fire, 130, folder)
	H.ok(r.part and r.part.Shape == Enum.PartType.Cylinder, "ring is a cylinder disc")
	-- the round face diameter is 2*radius on two axes; thickness is small on the third.
	local s = r.part.Size
	H.ok(math.max(s.X, s.Y, s.Z) >= 130 * 2 - 1, "ring face spans the grove diameter")
	H.ok(math.min(s.X, s.Y, s.Z) <= 6, "ring is a THIN disc (an outline, not a slab)")
end)

H.test("FireVisuals.new: pool is allocated at the budget cap (<=maxVisualBurning burning sets)", function()
	local folder = newContainer()
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, staticCfg(), grid.cellSize, folder)
	local cap = GameConfig.Fire.maxVisualBurning or 30
	H.eq(#ctrl.cellPool, cap, "cell pool sized exactly to maxVisualBurning")
	-- each pooled set is a full marker (part+emitter+light).
	for i = 1, #ctrl.cellPool do
		H.eq(countClass(ctrl.cellPool[i].part, "PointLight"), 1, "pool set " .. i .. " has its light")
		H.eq(countClass(ctrl.cellPool[i].part, "ParticleEmitter"), 1, "pool set " .. i .. " has its emitter")
	end
end)

H.test("sync: draws <=cap burning markers, all visible, matching the burning-cell count", function()
	local folder = newContainer()
	local grid = burningGrid()
	local cap = GameConfig.Fire.maxVisualBurning or 30
	local ctrl = FireVisuals.new(FireGrid, GameConfig.Fire, grid.cellSize, folder)
	-- grace ring active on grove 1 for the pulse path.
	local drawn = ctrl:sync(grid, { [1] = 999 }, 30)
	local expected = math.min(cap, #FireGrid.burningCells(grid, 1e9))
	H.eq(drawn, expected, "sync returns the number of burning cells actually drawn")
	H.ok(drawn > 0, "the burned grid actually has BURNING cells to draw (sanity)")
	H.ok(drawn <= cap, "never exceeds the ≤" .. cap .. " budget cap")

	-- exactly `drawn` markers are visible (Transparency<1), the rest parked/hidden.
	local visible = 0
	for i = 1, #ctrl.cellPool do
		local p = ctrl.cellPool[i].part
		if p.Transparency < 1 then
			visible += 1
			H.finite(p.CFrame.Position.X, "visible marker X finite")
			H.ok(p.CFrame.Position.Y > -100, "visible marker is in the world (not parked below)")
			H.ok(ctrl.cellPool[i].light.Enabled == true, "visible marker's light is on")
		else
			H.ok(ctrl.cellPool[i].light.Enabled == false, "hidden marker's light is OFF (culled, no cost)")
		end
	end
	H.eq(visible, drawn, "visible marker count == drawn count (no leaked/ghost markers)")

	-- the cut-off ring for grove 1 is showing (transparency < 1), other rings hidden.
	H.ok(ctrl.ringPool[1] ~= nil and ctrl.ringPool[1].part.Transparency < 1, "grove-1 cut-off ring is visible while grace is active")
end)

H.test("sync: markers are culled when there is nothing BURNING (park + lights off, no leak)", function()
	local folder = newContainer()
	-- first render a burning grid so the pool is populated + lit.
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, GameConfig.Fire, grid.cellSize, folder)
	local drawn0 = ctrl:sync(grid, {}, 30)
	H.ok(drawn0 > 0, "burning grid lit some markers first")

	-- now sync the SAME controller against an UNSEEDED grid (no fire yet → zero BURNING). Every marker
	-- that was lit must be culled: parked below the world, transparency full, light + smoke off.
	local coldGrid = FireGrid.new(GameConfig.Fire, 999, Vector3.new(1, 0, 0),
		{ { center = Vector3.new(500, 0, 0), radius = 130 } }, GameConfig.Rescue.deliverPos)
	local drawn = ctrl:sync(coldGrid, {}, 5)
	H.eq(drawn, 0, "no BURNING cells → nothing drawn")
	for i = 1, #ctrl.cellPool do
		H.ok(ctrl.cellPool[i].part.Transparency >= 1, "every marker culled (transparent)")
		H.ok(ctrl.cellPool[i].light.Enabled == false, "every light off after culling")
		H.ok(ctrl.cellPool[i].smoke.Enabled == false, "every emitter off after culling")
	end
end)

H.test("ember tint pool respects its cap and uses NO light/emitter (free tint per §3.3)", function()
	local folder = newContainer()
	local emberCap = GameConfig.Fire.maxVisualEmber or 40
	local set = FireVisuals.buildEmberPatch(GameConfig.Fire, 60, folder)
	H.eq(countClass(set.part, "PointLight"), 0, "ember patch has NO light")
	H.eq(countClass(set.part, "ParticleEmitter"), 0, "ember patch has NO emitter")
	local grid = burningGrid()
	FireGrid.step(grid, 120) -- everything to EMBER
	local ctrl = FireVisuals.new(FireGrid, GameConfig.Fire, grid.cellSize, folder)
	ctrl:sync(grid, {}, 150)
	local emberVisible = 0
	for i = 1, #ctrl.emberPool do
		if ctrl.emberPool[i].part.Transparency < 1 then emberVisible += 1 end
	end
	H.ok(emberVisible <= emberCap, "ember patches never exceed maxVisualEmber (" .. emberCap .. ")")
end)

-- ── STAGE 2 TESTS (7 new) ──────────────────────────────────────────────────────────────────────────

H.test("Stage-2 static identity: no Stage-2 instances leak under flameStyle=static (the revert gate)", function()
	-- Use a dedicated folder for the single-set check (separate from the ctrl folder).
	local setFolder = newContainer()
	local cfg = staticCfg()
	local set = FireVisuals.buildCellSet(cfg, 60, setFolder)
	H.ok(set.core == nil, "static: core is nil (no teardrop)")
	H.ok(set.flame == nil, "static: flame is nil (no flame emitter)")
	-- shape stays Block (default Part shape, not Ball).
	H.ok(set.part.Shape == Enum.PartType.Block, "static: part shape is Block (not teardrop Ball)")
	-- smoke Acceleration is the build-time straight-up value.
	local acc = set.smoke.Acceleration
	H.ok(acc.X == 0 and acc.Y == 26 and acc.Z == 0, "static: smoke Acceleration is (0,26,0) — straight up")
	-- full controller in its own folder: no plume, emitter count = maxVisualBurning (smoke only, no flame).
	local ctrlFolder = newContainer()
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, ctrlFolder)
	H.ok(ctrl.plume == nil, "static: no centroid plume allocated")
	-- sync twice and verify smoke still straight-up (lean==0 must never write Acceleration).
	ctrl:sync(grid, {}, 10)
	ctrl:sync(grid, {}, 20)
	for i = 1, #ctrl.cellPool do
		local smk = ctrl.cellPool[i].smoke
		local a = smk.Acceleration
		H.ok(a.X == 0 and a.Z == 0, "static after sync: smoke Acceleration XZ remains 0 (lean never written)")
	end
	-- total ParticleEmitters in ctrlFolder = maxVisualBurning (smoke only, no flame, no plume).
	local totalPE = countNamed(ctrlFolder, "ParticleEmitter", "Smoke")
	local cap = GameConfig.Fire.maxVisualBurning or 30
	H.eq(totalPE, cap, "static: total smoke emitters == maxVisualBurning (no flame or plume emitters)")
end)

H.test("Stage-2 flicker: flame emitter present + correct", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local set = FireVisuals.buildCellSet(cfg, 60, folder)
	-- part now has 2 ParticleEmitters: smoke + flame.
	H.eq(countClass(set.part, "ParticleEmitter"), 2, "flicker: exactly 2 ParticleEmitters (smoke + flame)")
	-- the flame emitter.
	H.ok(set.flame ~= nil, "flicker: flame emitter returned in set")
	H.ok(set.flame.Name == "Flame", "flicker: flame emitter named Flame")
	H.ok(set.flame.LightEmission == 1, "flicker: flame LightEmission==1 (additive glow)")
	H.ok(set.flame.Texture == "rbxasset://textures/particles/fire_main.dds", "flicker: flame uses built-in fire sprite")
	H.eq(set.flame.Rate, cfg.flameRate, "flicker: flame Rate == cfg.flameRate")
	H.ok(set.flame.Enabled == false, "flicker: flame Enabled=false at build (sync enables it)")
end)

H.test("Stage-2 flicker: teardrop two-tone geometry", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local set = FireVisuals.buildCellSet(cfg, 60, folder)
	-- outer shell is a Ball.
	H.ok(set.part.Shape == Enum.PartType.Ball, "flicker: outer shell is Ball (teardrop shape)")
	-- inner core exists and is also a Ball.
	H.ok(set.core ~= nil, "flicker: inner core exists")
	H.ok(set.core.Shape == Enum.PartType.Ball, "flicker: inner core is Ball")
	-- taper: core smaller than the outer shell (by teardropCoreRatio ~0.45, check <= 0.6 for margin).
	H.ok(set.core.Size.X <= set.part.Size.X * 0.6, "flicker: core X <= 60% of shell X (tapered)")
	H.ok(set.core.Size.Y <= set.part.Size.Y * 0.6, "flicker: core Y <= 60% of shell Y (tapered)")
	-- core sits at the BASE: coreOffsetY < 0 and magnitude < half the shell height.
	H.ok(set.coreOffsetY < 0, "flicker: coreOffsetY is negative (core sits at base, not top)")
	H.ok(math.abs(set.coreOffsetY) < set.part.Size.Y * 0.5, "flicker: core offset within shell (base, not outside)")
end)

H.test("Stage-2 flicker sync: lean sign matches wind AND the actual spread direction (telegraph honesty)", function()
	local folder = newContainer()
	local cfg = flickerCfg()  -- wind = unit +X (burningGrid seeds with Vector3.new(1,0,0))
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	ctrl:sync(grid, {}, 10)

	-- pick a visible marker and check smoke Acceleration.
	local checked = false
	for i = 1, #ctrl.cellPool do
		local set = ctrl.cellPool[i]
		if set.part.Transparency < 1 then
			local acc = set.smoke.Acceleration
			-- wind is unit +X; smokeLeanStrength=22 → Acceleration.X should be 22, Z should be 0, Y=26.
			H.ok(math.abs(acc.X - 22) < 0.01, "flicker: smoke Acceleration.X == 22 (lean along wind +X)")
			H.ok(math.abs(acc.Z) < 0.01, "flicker: smoke Acceleration.Z == 0 (no crosswind lean)")
			H.ok(math.abs(acc.Y - 26) < 0.01, "flicker: smoke Acceleration.Y == 26 (vertical preserved)")
			-- teardrop tips downwind: UpVector.X > 0 (leans toward +X wind).
			local up = set.part.CFrame.UpVector
			H.ok(up.X > 0, "flicker: teardrop UpVector.X > 0 (tips downwind)")
			-- lean magnitude matches teardropLeanDeg=8: sin(8°) ≈ 0.139.
			H.ok(math.abs(up.X - math.sin(math.rad(8))) < 0.02, "flicker: teardrop lean matches teardropLeanDeg=8")
			checked = true
			break
		end
	end
	H.ok(checked, "flicker: at least one visible marker to check lean")

	-- Telegraph honesty: the fire front really moves the way the smoke points.
	-- Compute the ignition-weighted centroid BEFORE stepping, then step 20 ticks.
	local burning1 = FireGrid.burningCells(grid, 1e9)
	local cx1, cz1 = 0, 0
	for _, b in ipairs(burning1) do cx1 += b.x; cz1 += b.z end
	if #burning1 > 0 then cx1 /= #burning1; cz1 /= #burning1 end

	FireGrid.step(grid, 20)

	local burning2 = FireGrid.burningCells(grid, 1e9)
	local cx2, cz2 = 0, 0
	for _, b in ipairs(burning2) do cx2 += b.x; cz2 += b.z end
	if #burning2 > 0 then cx2 /= #burning2; cz2 /= #burning2 end

	-- The front moved in the +X direction (wind = unit +X): centroid X increases.
	-- dot(delta, wind) > 0 means centroid moved downwind.
	local wx, wz = grid.windX or 0, grid.windZ or 0
	if #burning1 > 0 and #burning2 > 0 then
		local dot = (cx2 - cx1) * wx + (cz2 - cz1) * wz
		H.ok(dot > 0, "flicker telegraph: fire centroid moved downwind (smoke lean = correct spread forecast)")
		-- sign of centroid drift matches sign of smoke Acceleration.X
		local visible_acc_x = nil
		for i = 1, #ctrl.cellPool do
			if ctrl.cellPool[i].part.Transparency < 1 then
				visible_acc_x = ctrl.cellPool[i].smoke.Acceleration.X
				break
			end
		end
		if visible_acc_x then
			local same_sign = (visible_acc_x > 0) == (cx2 > cx1)
			H.ok(same_sign, "flicker telegraph: smoke Acceleration.X sign matches centroid drift sign")
		end
	end
end)

H.test("Stage-2 flicker: budget cap + allocate-once (no per-tick Instance creation)", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	-- pool size still == maxVisualBurning.
	local cap = cfg.maxVisualBurning or 30
	H.eq(#ctrl.cellPool, cap, "flicker: cell pool still sized to maxVisualBurning")

	-- snapshot descendant count after first sync, then sync 2 more times.
	ctrl:sync(grid, {}, 10)
	local desc1 = #folder:GetDescendants()
	ctrl:sync(grid, {}, 11)
	local desc2 = #folder:GetDescendants()
	ctrl:sync(grid, {}, 12)
	local desc3 = #folder:GetDescendants()
	H.eq(desc2, desc1, "flicker: descendant count unchanged between sync 1→2 (zero per-tick allocation)")
	H.eq(desc3, desc1, "flicker: descendant count unchanged between sync 1→3 (zero per-tick allocation)")

	-- drawn markers <= cap.
	local drawn = ctrl:sync(grid, {}, 13)
	H.ok(drawn <= cap, "flicker: drawn markers never exceed the budget cap")

	-- visible marker count == drawn count.
	local visible = 0
	for i = 1, #ctrl.cellPool do
		if ctrl.cellPool[i].part.Transparency < 1 then visible += 1 end
	end
	H.eq(visible, drawn, "flicker: visible count == drawn count (no ghost markers)")
end)

H.test("Stage-2 flicker: exactly ONE centroid plume, grows with fire, parks when cold", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local grid = burningGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)

	-- exactly one MegaPlume emitter in the container.
	local plumeCount = countNamed(folder, "ParticleEmitter", "MegaPlume")
	H.eq(plumeCount, 1, "flicker: exactly ONE MegaPlume emitter in container")

	-- total ParticleEmitters: maxVisualBurning*2 (smoke+flame each) + 1 (plume)
	--                        + S44 maxVisualSmolder (one wisp each, allocated only when smolderTell).
	local cap = cfg.maxVisualBurning or 30
	local smoldCap = (cfg.smolderTell ~= false) and (cfg.maxVisualSmolder or 14) or 0
	local totalPE = countClass(folder, "ParticleEmitter")
	H.eq(totalPE, cap * 2 + 1 + smoldCap,
		"flicker: total emitters = cap*2 (smoke+flame) + 1 (plume) + maxVisualSmolder (wisps)")

	-- after sync with burning cells: plume enabled, rate matches formula.
	local drawn = ctrl:sync(grid, {}, 10)
	H.ok(drawn > 0, "flicker plume test: grid has burning cells")
	H.ok(ctrl.plume.emitter.Enabled == true, "flicker: plume Enabled=true when burning cells exist")
	local expectedRate = math.min(cfg.plumeRateMax, cfg.plumeRateBase + cfg.plumeRatePerCell * drawn)
	H.approx(ctrl.plume.emitter.Rate, expectedRate, 0.01, "flicker: plume Rate matches formula")
	-- plume anchor Y is above -100 (in the world).
	H.ok(ctrl.plume.part.CFrame.Position.Y > -100, "flicker: plume anchor is in the world (not parked)")
	-- plume XZ is near the mean XZ of the visible markers (within one cellSize = 60).
	local mx, mz = 0, 0
	local mc = 0
	for i = 1, #ctrl.cellPool do
		if ctrl.cellPool[i].part.Transparency < 1 then
			mx += ctrl.cellPool[i].part.CFrame.Position.X
			mz += ctrl.cellPool[i].part.CFrame.Position.Z
			mc += 1
		end
	end
	if mc > 0 then
		mx /= mc; mz /= mc
		local pp = ctrl.plume.part.CFrame.Position
		-- centroid of the leaned CFrames may differ slightly from the unrotated XZ mean;
		-- allow 2 cellSizes tolerance.
		local dist = math.sqrt((pp.X - mx)^2 + (pp.Z - mz)^2)
		H.ok(dist <= cfg.cellSize * 2, "flicker: plume XZ near centroid of visible markers")
	end
	-- plume Acceleration.X = wx * lean = 1 * 22 = 22.
	local pa = ctrl.plume.emitter.Acceleration
	H.ok(math.abs(pa.X - 22) < 0.01, "flicker: plume Acceleration.X == 22 (leans downwind)")

	-- cold grid: plume disables and parks.
	local coldGrid = FireGrid.new(cfg, 999, Vector3.new(1, 0, 0),
		{ { center = Vector3.new(500, 0, 0), radius = 130 } }, GameConfig.Rescue.deliverPos)
	ctrl:sync(coldGrid, {}, 5)
	H.ok(ctrl.plume.emitter.Enabled == false, "flicker: plume Enabled=false when no burning cells")
	H.ok(ctrl.plume.part.CFrame.Position.Y < -100, "flicker: plume anchor parked when no burning cells")
end)

H.test("Stage-2 flicker: breathing is deterministic + bounded (no math.random)", function()
	local folder1 = newContainer()
	local folder2 = newContainer()
	local cfg = flickerCfg()
	local grid = burningGrid()

	-- two controllers from identical seeds.
	local ctrl1 = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder1)
	local ctrl2 = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder2)
	ctrl1:sync(grid, {}, 10)
	ctrl2:sync(grid, {}, 10)

	local cap = cfg.maxVisualBurning or 30
	local amp = cfg.flickerAmp or 0.15
	for i = 1, cap do
		local sz1 = ctrl1.cellPool[i].part.Size
		local sz2 = ctrl2.cellPool[i].part.Size
		-- identical: deterministic, no randomness.
		H.approx(sz1.Y, sz2.Y, 0.001, "flicker breathing: pool[" .. i .. "] Size.Y identical between two controllers (deterministic)")
		-- visible markers stay within the breathing bound.
		if ctrl1.cellPool[i].part.Transparency < 1 then
			local baseH = ctrl1.cellPool[i].baseH
			H.ok(sz1.Y >= baseH * (1 - amp - 1e-6), "flicker: Size.Y >= baseH*(1-amp) (lower bound)")
			H.ok(sz1.Y <= baseH * (1 + amp + 1e-6), "flicker: Size.Y <= baseH*(1+amp) (upper bound)")
		end
	end
end)

--------------------------------------------------------------------------------
-- S44 — THE SMOLDER TELL. Chad: "it takes a while for me to see fire too."
--
-- The convicted mechanism was that SMOLDER rendered NOTHING while spreading and while Stage-3a
-- fear keyed off it, so the first ~25-35s of a round looked fire-free. These gates assert the READ
-- ("I can see the fire starting") and the COST ("and it did not buy that with the mobile cliff"),
-- because a visual that ships without a range/cost gate is exactly how Stage 1 traded away the
-- long-range squirrel signal without anyone noticing.
--------------------------------------------------------------------------------

-- A grid stepped to the SMOLDER window: seeded, but well before any cell reaches BURNING
-- (smolderMin is 15s, so ~8s in the whole front is still smouldering).
local function smolderingGrid()
	local groves = {
		{ center = Vector3.new(500, 0, 0), radius = 130 },
		{ center = Vector3.new(-500, 0, 300), radius = 130 },
	}
	local grid = FireGrid.new(GameConfig.Fire, 4242, Vector3.new(1, 0, 0), groves, GameConfig.Rescue.deliverPos)
	FireGrid.seedUpwind(grid)
	FireGrid.step(grid, 8)
	return grid
end

H.test("SMOLDER TELL: the fire is VISIBLE during the window that used to render nothing", function()
	local grid = smolderingGrid()
	local stats = FireGrid.stats(grid)
	H.ok(stats.smolder > 0, "fixture: the grid must actually be smouldering or this gate is vacuous")
	H.eq(stats.burning, 0, "fixture: this is the pre-flame window — the exact gap Chad reported")

	local folder = newContainer()
	local cfg = flickerCfg()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	ctrl:sync(grid, {}, 8)

	local lit = 0
	for _, set in ipairs(ctrl.smolderPool) do
		if set.wisp.Enabled then
			lit += 1
			H.ok(set.part.CFrame.Position.Y > -100, "a lit wisp must be IN the world, not parked below it")
		end
	end
	H.ok(lit > 0,
		"nothing renders during the smolder window — this is the bug: an invisible fire spreading for 15-25s")
	print(("      [smolder] %d/%d wisps lit at t=8s with %d smouldering cells and ZERO flames")
		:format(lit, ctrl.maxSmolder, stats.smolder))
end)

H.test("SMOLDER TELL: costs NO lights and no flame emitters — the mobile cliff is untouched", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local grid = smolderingGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	ctrl:sync(grid, {}, 8)
	-- Lights live on FireCell parts only; a SmolderCell must never carry one.
	for _, set in ipairs(ctrl.smolderPool) do
		H.eq(#set.part:GetChildren(), 1, "a smolder set is ONE attachment and nothing else (no light, no core)")
		H.eq(set.part:FindFirstChildWhichIsA("PointLight"), nil,
			"a smouldering cell must never carry a PointLight — lights are the low-end/mobile cliff")
		H.eq(set.part.Transparency, 1, "the wisp anchor is invisible — the smoke IS the tell")
	end
	-- worst case: the ENTIRE pool alight must still fit the §3.4 particle rail alongside the flames.
	local perWisp = (cfg.smolderWispRate or 5) * (cfg.smolderWispLife or 3.2)
	local worst = ctrl.maxSmolder * perWisp
	H.ok(worst <= 300,
		("the smolder pool's worst case is %.0f alive particles — re-derive the §3.4 budget before raising it")
			:format(worst))
end)

H.test("SMOLDER TELL: a cell that IGNITES hands off cleanly — never wisp and flame at once", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	local grid = smolderingGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	ctrl:sync(grid, {}, 8)
	-- run the fire well past the smolder window so the front has ignited, then re-sync
	FireGrid.step(grid, 40)
	local drawn = ctrl:sync(grid, {}, 48)
	H.ok(drawn > 0, "fixture: the fire must have reached BURNING by now")

	-- every position rendering a flame must NOT also be rendering a wisp
	local flameXZ = {}
	for i = 1, drawn do
		local p = ctrl.cellPool[i].part.CFrame.Position
		flameXZ[("%d:%d"):format(math.floor(p.X + 0.5), math.floor(p.Z + 0.5))] = true
	end
	for _, set in ipairs(ctrl.smolderPool) do
		if set.wisp.Enabled then
			local p = set.part.CFrame.Position
			H.eq(flameXZ[("%d:%d"):format(math.floor(p.X + 0.5), math.floor(p.Z + 0.5))], nil,
				"a cell is showing a smolder wisp AND a flame — the escalation must be a handoff, not a stack")
		end
	end
end)

H.test("SMOLDER TELL: the kill switch restores the pre-S44 Instance tree exactly", function()
	local folder = newContainer()
	local cfg = flickerCfg()
	cfg.smolderTell = false
	local grid = smolderingGrid()
	local ctrl = FireVisuals.new(FireGrid, cfg, grid.cellSize, folder)
	H.eq(ctrl.maxSmolder, 0, "smolderTell=false must allocate NO wisp pool")
	H.eq(countNamed(folder, "ParticleEmitter", "Wisp"), 0, "no wisp emitters may exist under the kill switch")
	H.eq(countClass(folder, "ParticleEmitter"), (cfg.maxVisualBurning or 30) * 2 + 1,
		"under the kill switch the emitter tree is byte-identical to pre-S44")
	ctrl:sync(grid, {}, 8)   -- must not error with an empty pool
end)

H.test("SMOLDER TELL: ships LIVE (Chad asked for the fire to show up sooner)", function()
	H.eq(GameConfig.Fire.smolderTell, true, "smolderTell must ship ON — this is a reported bug, not an experiment")
	H.eq(GameConfig.Fire.smolderMin, 15, "the smolder DURATION must not have been cut — that races the whole front")
	H.eq(GameConfig.Fire.smolderMax, 25, "…and neither may the max: spread is active from SMOLDER (a balance change)")
end)

--------------------------------------------------------------------------------
-- S45 TEARDOWN SYMMETRY. destroy() freed cellPool/emberPool/ringPool/plume but NOT the S44 smolderPool
-- — the same create/teardown asymmetry class as the fire-roar bug that survived death and respawn.
-- Masked on the normal path (teardownFire destroys the whole folder), but the MID-ROUND FAILURE path
-- calls destroy() and deliberately KEEPS the folder to "drop to logic-only fire" — stranding up to 14
-- Enabled wisp emitters smoking at frozen positions while the real fire front moves on.
--------------------------------------------------------------------------------

H.test("destroy(): frees EVERY pool — a survivor is a leaked emitter smoking on a dead fire", function()
	local folder = newContainer()
	local grid = smolderingGrid()
	local ctrl = FireVisuals.new(FireGrid, flickerCfg(), grid.cellSize, folder)
	ctrl:sync(grid, {}, 8)

	-- anti-vacuity: there must BE smolder parts to leak, or this gate proves nothing.
	local built = #ctrl.smolderPool
	H.ok(built > 0, "fixture: the smolder pool must be allocated or this test is vacuous")

	local before = #folder:GetDescendants()
	H.ok(before > 0, "fixture: the container must hold the built pools")

	ctrl:destroy()

	-- The container is deliberately NOT destroyed here — that is exactly the mid-round failure path.
	local after = #folder:GetDescendants()
	H.eq(after, 0, ("destroy() left %d instances parented — the smolder pool is the known survivor"):format(after))
	H.eq(#ctrl.smolderPool, 0, "the smolder pool table must be emptied like every other pool")
end)
