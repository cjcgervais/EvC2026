--!nonstrict
--[[
	tests/talon.spec.luau — the GRASP-CLOSURE gate (Chad S40: "all the talons do is change angles …
	how does an eagle catch something in talons?").

	A rotating rigid paddle (the S39 rig, welded toes) and a real articulated GRASP look the same to a
	code audit. They do NOT look the same to geometry: a real grasp's toe TIPS spread apart when the
	foot opens and collapse toward a common point when it clenches; a rigid paddle's tips keep a constant
	relative spread no matter how the foot rotates. This gate builds the REAL eagle, drives
	BirdBuilder.AnimateTalons, resolves each toe-tip's WORLD position through the joint chain (Lune does
	not run the Roblox joint solver, so we do our own forward kinematics), and asserts the fist closes.

	These invariants are RATIO-based (scale-free) so they hold at any bird scale. The old welded rig fails
	invariants 1-3 by construction (rigid tips → spread ratio ≡ 1).
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local BirdBuilder = Loader.load("BirdBuilder")
local Vector3 = Loader.Vector3
local CFrame = Loader.CFrame

-- ---- forward kinematics: world CFrame of any part through Motor6D/Weld chain to the Body root ----
-- For a joint with Part0→Part1: Part1_world = Part0_world * C0 * Transform * C1^-1  (Weld: Transform = I).
local function buildJointIndex(model)
	local byPart1 = {}
	for _, d in ipairs(model:GetDescendants()) do
		local c = d.ClassName
		if (c == "Motor6D" or c == "Weld") and d.Part1 then
			byPart1[d.Part1] = d
		end
	end
	return byPart1
end

local function makeResolver(model)
	local root = model.PrimaryPart
	local byPart1 = buildJointIndex(model)
	local memo = {}
	local function worldOf(part)
		if part == root then
			return part.CFrame
		end
		if memo[part] then
			return memo[part]
		end
		local j = byPart1[part]
		if not j then
			return part.CFrame -- unjointed prop (shouldn't happen on the leg chain)
		end
		local transform = (j.ClassName == "Motor6D") and j.Transform or CFrame.new()
		local w = worldOf(j.Part0) * j.C0 * transform * j.C1:Inverse()
		memo[part] = w
		return w
	end
	return worldOf
end

-- The four digit tips of one foot (3 forward claws + hallux), in world space.
local function footTips(model, worldOf, sideName)
	local body = model.PrimaryPart
	local tips = {}
	for ti = 1, 3 do
		local clawJoint = body:FindFirstChild(sideName .. "Toe" .. ti .. "ClawJoint")
		local claw = clawJoint.Part1
		-- claw built along local -Z; far tip = local (0,0,-Size.Z/2)
		tips[ti] = (worldOf(claw) * CFrame.new(0, 0, -claw.Size.Z / 2)).Position
	end
	local halluxJoint = body:FindFirstChild(sideName .. "HalluxJoint")
	local hallux = halluxJoint.Part1
	-- hallux built along local +Z; tip = local (0,0,+Size.Z/2)
	tips[4] = (worldOf(hallux) * CFrame.new(0, 0, hallux.Size.Z / 2)).Position
	return tips
end

local function maxPairwise(tips)
	local m = 0
	for i = 1, #tips do
		for k = i + 1, #tips do
			m = math.max(m, (tips[i] - tips[k]).Magnitude)
		end
	end
	return m
end

local function centroidRadius(tips)
	local c = Vector3.new()
	for _, t in ipairs(tips) do
		c = c + t
	end
	c = c / #tips
	local r = 0
	for _, t in ipairs(tips) do
		r = math.max(r, (t - c).Magnitude)
	end
	return r
end

-- Fresh eagle + spread measurement at a given (reach, clench). dt=1 → AnimateTalons converges in one call.
local function spreadAt(sideName, reach, clench)
	local eagle = BirdBuilder.Build("Eagle", GameConfig.Profiles.Eagle)
	if reach ~= nil then
		BirdBuilder.AnimateTalons(eagle, reach, clench, 1)
	end
	local worldOf = makeResolver(eagle)
	local tips = footTips(eagle, worldOf, sideName)
	return maxPairwise(tips), centroidRadius(tips), tips
end

for _, sideName in ipairs({ "Left", "Right" }) do
	H.test(("grasp closes on the %s foot (a rotating paddle can't pass this)"):format(sideName), function()
		local restSpread = spreadAt(sideName, nil, nil)
		local openSpread = spreadAt(sideName, 1, 0)
		local closedSpread, closedRadius = spreadAt(sideName, 1, 1)

		-- 1. OPEN SPREAD — the hand visibly opens: tips fan wider than the flight-tuck rest. A rotating
		-- rigid paddle (the S39 rig) gives EXACTLY 1.0x here (rigid body → constant inter-tip distances),
		-- so any ratio > 1.0 rejects a paddle; 1.25x keeps a 25% margin and matches the real articulated
		-- geometry (the rest tuck is already somewhat splayed, so the fan is ~1.35x). The load-bearing
		-- anti-paddle guards are invariants 2 & 3 (a paddle also fails those at exactly 1.0x).
		H.ok(
			openSpread >= 1.25 * restSpread,
			("open spread (%.2f) must be >= 1.25x rest (%.2f)"):format(openSpread, restSpread)
		)
		-- 2. CLOSURE — the fist collapses: closed spread is a fraction of open, and tighter than rest.
		H.ok(
			closedSpread <= 0.55 * openSpread,
			("closed spread (%.2f) must be <= 0.55x open (%.2f)"):format(closedSpread, openSpread)
		)
		H.ok(
			closedSpread <= restSpread,
			("closed spread (%.2f) must be <= rest (%.2f)"):format(closedSpread, restSpread)
		)
		-- 3. CONVERGENCE — at clench the tips collapse toward a common point (the catch center).
		H.ok(
			closedRadius <= 0.6 * openSpread,
			("closed tips must converge (radius %.2f <= 0.6x open %.2f)"):format(closedRadius, openSpread)
		)
	end)
end

-- REST-POSE PRESERVATION: the world-pivot C0/C1 must reproduce the built CFrame at Transform=I for every
-- leg part — the exact invariant the Motor6D C1-inversion red-team guards. If C0/C1 were wrong the rig
-- would deform at rest (crossed toes) even before any animation.
H.test("rest pose is preserved (FK at Transform=I reproduces every built leg part)", function()
	local eagle = BirdBuilder.Build("Eagle", GameConfig.Profiles.Eagle)
	local body = eagle.PrimaryPart
	local worldOf = makeResolver(eagle)
	local names = {}
	for _, side in ipairs({ "Left", "Right" }) do
		for ti = 1, 3 do
			table.insert(names, side .. "Toe" .. ti .. "Joint")
			table.insert(names, side .. "Toe" .. ti .. "ClawJoint")
		end
		table.insert(names, side .. "HalluxJoint")
	end
	for _, jn in ipairs(names) do
		local j = body:FindFirstChild(jn)
		H.ok(j ~= nil, "joint present: " .. jn)
		local built = j.Part1.CFrame.Position
		local resolved = worldOf(j.Part1).Position
		H.ok(
			(built - resolved).Magnitude < 1e-3,
			("%s rest pose drift %.4f (C0/C1 world-pivot form broken)"):format(jn, (built - resolved).Magnitude)
		)
	end
end)

-- Diagnostics (measured, not asserted): opposition + absolute spreads, printed to inform TALON_LOCAL.
H.test("grasp diagnostics (informational)", function()
	local _, _, restTips = spreadAt("Left", nil, nil)
	local openS = spreadAt("Left", 1, 0)
	local closedS, closedR, closedTips = spreadAt("Left", 1, 1)
	print(("      [talon] Left rest=%.2f open=%.2f closed=%.2f closedRadius=%.2f")
		:format(maxPairwise(restTips), openS, closedS, closedR))
	-- opposition: forward-toe mean vs hallux tip (sign only; informational)
	local fwd = (closedTips[1] + closedTips[2] + closedTips[3]) / 3
	print(("      [talon] closed hallux<->fwd-toe gap = %.2f"):format((fwd - closedTips[4]).Magnitude))
	H.ok(true, "diagnostics printed")
end)
