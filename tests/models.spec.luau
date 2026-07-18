--!nonstrict
--[[
	tests/models.spec.luau — headless MODEL-BUILD quality gate.

	WHY this exists (Chad, S40): "its just a light cylinder, I don't even see squirrels … this is
	supposed to be an autonomous programmatic build. It needs to have quality standards before I judge it."
	A Fable code-audit certified the S39 visuals "faithful to spec" while the RENDERED result was an
	invisible squirrel (a fat opaque beacon engulfed it) and a talon that only rotated. A code audit
	can't see geometry; THIS can. @lune/roblox builds the REAL procedural models (BirdBuilder is
	Instance.new-based), so we build them headlessly and assert STRUCTURE + VISIBILITY + the
	beacon-doesn't-occlude-the-squirrel invariant — the exact class of bug that reached Chad.

	Honest limit: this gate proves a model is present, visible, non-degenerate, and correctly placed.
	It does NOT judge beauty — that stays Chad's Play (Tier 5). But nothing structurally broken or
	invisible should ever reach him again.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local BirdBuilder = Loader.load("BirdBuilder")
local R = GameConfig.Rescue

-- Oriented-box AABB half-extent along world Y for one part (exact for a box; conservative for a ball).
local function halfY(part)
	local cf, sz = part.CFrame, part.Size
	return 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
end

local function eachRenderPart(model, fn)
	for _, d in ipairs(model:GetDescendants()) do
		local c = d.ClassName
		if c == "Part" or c == "WedgePart" or c == "MeshPart" or c == "TrussPart" then
			fn(d)
		end
	end
end

-- Vertical extent of a model in its build frame (Body built at origin), over VISIBLE parts only.
local function visibleTopBottom(model)
	local top, bottom = -math.huge, math.huge
	eachRenderPart(model, function(p)
		if p.Transparency < 1 then
			local y, h = p.CFrame.Position.Y, halfY(p)
			top = math.max(top, y + h)
			bottom = math.min(bottom, y - h)
		end
	end)
	return top, bottom
end

H.test("squirrel: builds visible + non-degenerate at the shipped scale", function()
	local sq = BirdBuilder.BuildSquirrel(R.squirrelScale or 4.4, {})
	H.ok(sq.PrimaryPart ~= nil and sq.PrimaryPart.Name == "Body", "squirrel has a Body PrimaryPart")
	local total, visible = 0, 0
	eachRenderPart(sq, function(p)
		total += 1
		-- no degenerate geometry: finite, positive size; finite placement
		H.ok(p.Size.X > 0 and p.Size.Y > 0 and p.Size.Z > 0, "part '" .. p.Name .. "' has positive size")
		H.finite(p.CFrame.Position.X, p.Name .. " posX")
		H.finite(p.CFrame.Position.Y, p.Name .. " posY")
		H.finite(p.CFrame.Position.Z, p.Name .. " posZ")
		if p.Transparency < 1 then
			visible += 1
		end
	end)
	-- an invisible squirrel (the S39 regression) or a stripped model fails here
	H.ok(visible >= 12, ("squirrel has >=12 visible parts (got %d of %d)"):format(visible, total))
	local top, bottom = visibleTopBottom(sq)
	H.between(top - bottom, 4, 20, "squirrel overall height is sane (not collapsed / not exploded)")
end)

H.test("beacon must NOT occlude the squirrel (the S39 'light cylinder' bug)", function()
	local sq = BirdBuilder.BuildSquirrel(R.squirrelScale or 4.4, {})
	local top = select(1, visibleTopBottom(sq)) -- squirrel top in Body-origin frame
	local baseY = R.beaconBaseY or 8
	-- The beacon's BASE (RescueServer.buildBeacon builds it at body*CFrame.new(0, baseY+height/2, 0),
	-- so its bottom edge is exactly baseY above the Body origin) must clear the squirrel's head/tail
	-- with margin, or it engulfs the critter as it did in S39.
	H.ok(baseY > top + 1.5, ("beacon base (%.1f) must clear squirrel top (%.1f) + margin"):format(baseY, top))
	-- and it must read as a thin MARKER beam, not a fat tube standing over the squirrel
	local width = R.beaconWidth or 1.6
	H.ok(width <= 2.5, ("beacon is thin (width %.1f <= 2.5)"):format(width))
end)

H.test("eagle: builds with the talon rig joints present", function()
	local eg = BirdBuilder.Build(GameConfig.Profiles.Eagle, Loader.Vector3.new(0, 200, 0))
	local body = eg.PrimaryPart
	H.ok(body ~= nil, "eagle has a PrimaryPart")
	for _, j in ipairs({ "LeftHipJoint", "RightHipJoint", "LeftFootJoint", "RightFootJoint" }) do
		local m = body:FindFirstChild(j)
		H.ok(m ~= nil and m:IsA("Motor6D"), "eagle has Motor6D " .. j)
	end
	local parts = 0
	eachRenderPart(eg, function()
		parts += 1
	end)
	H.ok(parts >= 30, ("eagle has a full body (>=30 parts, got %d)"):format(parts))
end)

H.test("AnimateTalons is a safe no-op on a jointless model (crow / old models)", function()
	local crow = BirdBuilder.Build(GameConfig.Profiles.Crow, Loader.Vector3.new(0, 200, 0))
	-- must not error even though the crow has no talon joints
	BirdBuilder.AnimateTalons(crow, 1, 1, 1 / 60)
	H.ok(true, "AnimateTalons tolerated a jointless model")
end)
