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

local function countClass(part, className)
	local n = 0
	for _, d in ipairs(part:GetDescendants()) do
		if d.ClassName == className then n += 1 end
	end
	return n
end

H.test("buildCellSet: one burning marker = 1 Neon Part + 1 smoke emitter + 1 PointLight, non-degenerate", function()
	local folder = newContainer()
	local set = FireVisuals.buildCellSet(GameConfig.Fire, 60, folder)
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
	local ctrl = FireVisuals.new(FireGrid, GameConfig.Fire, grid.cellSize, folder)
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
