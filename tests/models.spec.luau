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

local GameConfig   = Loader.load("GameConfig")
local BirdBuilder  = Loader.load("BirdBuilder")
local FireVisuals  = Loader.load("FireVisuals")
local Instance     = Loader.Instance
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
	local eg = BirdBuilder.Build("Eagle", GameConfig.Profiles.Eagle)
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
	local crow = BirdBuilder.Build("Crow", GameConfig.Profiles.Crow)
	-- must not error even though the crow has no talon joints
	BirdBuilder.AnimateTalons(crow, 1, 1, 1 / 60)
	H.ok(true, "AnimateTalons tolerated a jointless model")
end)

-- Horizontal footprint radius (XZ) over visible parts — conservative OBB extents, same style as halfY.
local function footprintRadius(model)
	local r = 0
	eachRenderPart(model, function(p)
		if p.Transparency < 1 then
			local cf, sz = p.CFrame, p.Size
			local hx = 0.5 * (math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y + math.abs(cf.LookVector.X) * sz.Z)
			local hz = 0.5 * (math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y + math.abs(cf.LookVector.Z) * sz.Z)
			local horiz = math.sqrt(cf.Position.X ^ 2 + cf.Position.Z ^ 2) + math.max(hx, hz)
			r = math.max(r, horiz)
		end
	end)
	return r
end

H.test("halo style: ring frames the critter, chevron never occludes, critter is legible", function()
	local hs = R.haloSquirrelScale or 5.5
	local sq = BirdBuilder.BuildSquirrel(hs, {})
	local top, bottom = visibleTopBottom(sq)
	-- 1) LEGIBILITY: at the halo scale the critter itself must read at gameplay range.
	--    (4.4 builds ~11.2 tall → this would FAIL; 5.5 builds ~14.0 → the scale bump is enforced.)
	H.ok(top - bottom >= 12, ("halo squirrel height %.1f >= 12 (critter-as-landmark)"):format(top - bottom))
	-- 2) RING FRAMES: halo radius must exceed the squirrel's widest visible reach with margin —
	--    a frame around the animal, never a coin under it.
	local foot = footprintRadius(sq)
	H.ok((R.haloRadius or 10) >= foot + 1, ("haloRadius %.1f >= footprint %.1f + 1"):format(R.haloRadius or 10, foot))
	-- 3) RING NEVER COVERS THE FACE: disc top (centre + half of buildRing's 3-thick disc) stays
	--    below the head's bottom with margin — a glow pool at the shins.
	local head = sq:FindFirstChild("Head", true)
	H.ok(head ~= nil, "squirrel has a Head")
	local headBottom = head.CFrame.Position.Y - halfY(head)
	H.ok((R.haloGroundY or -1.5) + 1.5 <= headBottom - 1,
		("halo top %.1f below head bottom %.1f - 1"):format((R.haloGroundY or -1.5) + 1.5, headBottom))
	-- 4) CHEVRON CLEARS THE HEAD in the worst case: biggest (gold ×1.35) gem, at max downward
	--    gem-bob, over a squirrel at max hop. Gem halfY mirrors the build exactly: size
	--    (cs, 1.6cs, cs) rolled 45° about Z → 0.5*cos45*(cs + 1.6cs) = 0.9192*cs.
	local cs = (R.chevronSize or 2.2) * 1.35
	local gemBottom = (R.chevronY or 14) - 0.9192 * cs - (R.chevronBobAmp or 1.0) - (R.hopAmp or 1.0)
	H.ok(gemBottom >= top + 1, ("chevron worst-case bottom %.2f >= squirrel top %.2f + 1"):format(gemBottom, top))
	-- 5) The reused ring primitive really is a thin FLAT disc of the dialed radius.
	local rec = FireVisuals.buildRing({}, R.haloRadius or 10, Instance.new("Folder"))
	H.eq(rec.part.Size.Y, (R.haloRadius or 10) * 2, "ring face diameter = 2*haloRadius")
	H.ok(rec.part.Size.X <= 4, "ring is a thin disc, not a pillar")
end)

H.test("waveBig: both arms sweep overhead with a real wave (the kid 'HELP!' read)", function()
	-- PoseSquirrel eases with alpha = clamp(dt*12,0,1) → dt=1 SNAPS exactly to target: headless-exact.
	-- Motor6D Transform doesn't move Part1 outside the engine, so we assert on the Transform itself.
	local hs = R.haloSquirrelScale or 5.5
	local sq = BirdBuilder.BuildSquirrel(hs, {})
	BirdBuilder.PoseSquirrel(sq, "waveBig", 1, 0)
	local body = sq.PrimaryPart
	for _, j in ipairs({ "LeftArmJoint", "RightArmJoint" }) do
		local mt = body:FindFirstChild(j)
		H.ok(mt ~= nil and mt:IsA("Motor6D"), j .. " exists")
		-- 170° raise → joint UpVector.Y = cos170*cos30 ≈ -0.85; require < -0.7 (≥ ~144° overhead)
		H.ok(mt.Transform.UpVector.Y < -0.7, j .. " swept overhead (arms flung high)")
	end
	for _, j in ipairs({ "LeftLegJoint", "RightLegJoint" }) do
		local mt = body:FindFirstChild(j)
		H.ok(mt.Transform.UpVector.Y > 0.9, j .. " stays planted (standing, not starfishing)")
	end
	-- WAVE AMPLITUDE: phase 0 → π/2 swings the arm's sway term by rad(34) exactly → the joint
	-- RightVector rotates by exactly 34° (X-rotation preserves the angle). Threshold 20° with margin.
	local sq2 = BirdBuilder.BuildSquirrel(hs, {})
	BirdBuilder.PoseSquirrel(sq2, "waveBig", 1, math.pi / 2)
	local a = body:FindFirstChild("RightArmJoint").Transform.RightVector
	local b = sq2.PrimaryPart:FindFirstChild("RightArmJoint").Transform.RightVector
	local sweep = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
	H.ok(sweep >= 20, ("wave sway sweep %.1f deg >= 20"):format(sweep))
end)
