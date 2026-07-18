--!nonstrict
--[[
	tests/featherfx.spec.luau — headless gate for the BRIEF IMPACT ACCENT (FeatherFX.apply).

	S41 ROLE CHANGE: FeatherFX is now the brief pale "smack" scuff at the terrain-contact instant,
	NOT the lingering brown feather cloud. The feathers are now discrete anchored PARTS (FeatherBurst).
	Old LINGER/FLOAT/DRIFT tests are DELETED — they asserted the brown-ball cloud that failed 3×.
	New tests assert the ACCENT role: short life, small, quick fade, few particles.

	WHY THE OLD ROLE FAILED:
	  The lingering soft-sprite cloud was iterated 3× and always blended into a fuzzy brown BALL —
	  soft-sprite alpha-blend is structural, not a knob. Fix: discrete PARTS for the feathers
	  (FeatherBurst), this emitter for the brief pale scuff at impact.

	WHAT THIS SPEC GATES:
	  • AGREEMENT — emitter dials match GameConfig.Combat.fx (no two-authorities drift).
	  • BRIEF    — lifetime is short (a blink, not a linger).
	  • SMALL    — peak particle size is a scuff, not a cloud.
	  • QUICK FADE — born hazy, fades fast.
	  • FEW PARTICLES — bounceFeathers is an accent count, not a big cloud.
	  • TOMBSTONE — the lingering cloud and the brown ball must never return (feathers are PARTS).
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Instance = Loader.Instance

local GameConfig = Loader.load("GameConfig")
local FeatherFX  = Loader.load("FeatherFX")

local FX = GameConfig.Combat and GameConfig.Combat.fx

-- Build the exact emitter the client's buildFeatherPool builds.
local function builtEmitter()
	local em = Instance.new("ParticleEmitter")
	return FeatherFX.apply(em, FX)
end

-- Linear-interpolate a NumberSequence at t in [0,1].
local function evalNS(seq, t)
	local kps = seq.Keypoints
	if t <= kps[1].Time then return kps[1].Value end
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t <= b.Time then
			local span = b.Time - a.Time
			if span <= 0 then return b.Value end
			return a.Value + (b.Value - a.Value) * ((t - a.Time) / span)
		end
	end
	return kps[#kps].Value
end

local function peakNS(seq)
	local m = -math.huge
	for _, kp in ipairs(seq.Keypoints) do
		if kp.Value > m then m = kp.Value end
	end
	return m
end

--------------------------------------------------------------------------------
-- AGREEMENT: emitter dials match GameConfig.Combat.fx (guards "same fact in two authorities")
--------------------------------------------------------------------------------
H.test("agreement: emitter dials match GameConfig.Combat.fx (client ↔ config agree)", function()
	local em = builtEmitter()
	H.approx(em.Lifetime.Min, FX.featherLifeMin, 1e-4, "Lifetime.Min == fx.featherLifeMin")
	H.approx(em.Lifetime.Max, FX.featherLifeMax, 1e-4, "Lifetime.Max == fx.featherLifeMax")
	H.approx(em.Speed.Max, FX.featherSpeed, 1e-4, "Speed.Max == fx.featherSpeed")
	H.approx(-em.Acceleration.Y, FX.featherGravity, 1e-4, "Acceleration.Y == -fx.featherGravity")
end)

--------------------------------------------------------------------------------
-- BRIEF: the accent is a blink, not a linger
--------------------------------------------------------------------------------
H.test("brief: lifetime is short — a smack blink, not a hanging feather cloud", function()
	local em = builtEmitter()
	H.ok(em.Lifetime.Max <= 0.8, "Lifetime.Max <= 0.8s (a blink, not a linger), got " .. tostring(em.Lifetime.Max))
	H.ok(em.Lifetime.Min >= 0.2, "Lifetime.Min >= 0.2s (visible at all), got " .. tostring(em.Lifetime.Min))
end)

--------------------------------------------------------------------------------
-- SMALL: a scuff puff, not a cloud
--------------------------------------------------------------------------------
H.test("small: peak particle size is a scuff accent, not a big cloud", function()
	local em = builtEmitter()
	local peak = peakNS(em.Size)
	H.ok(peak <= 2.0, "peak feather size <= 2.0 studs (a scuff, not a cloud), got " .. tostring(peak))
end)

--------------------------------------------------------------------------------
-- QUICK FADE: born hazy, dies fast
--------------------------------------------------------------------------------
H.test("quick fade: born hazy, already dying at mid-life, gone at end", function()
	local em = builtEmitter()
	H.ok(evalNS(em.Transparency, 0) <= 0.4, "born hazy (transparency at t=0 <= 0.4), got " .. tostring(evalNS(em.Transparency, 0)))
	H.ok(evalNS(em.Transparency, 0.6) >= 0.3, "already dying at 60% of life (transparency >= 0.3), got " .. tostring(evalNS(em.Transparency, 0.6)))
	H.ok(evalNS(em.Transparency, 1.0) >= 0.9, "fully faded by end of life (transparency >= 0.9), got " .. tostring(evalNS(em.Transparency, 1.0)))
end)

--------------------------------------------------------------------------------
-- FEW PARTICLES: an accent, not a cloud
--------------------------------------------------------------------------------
H.test("few particles: bounceFeathers is an accent count, not a big cloud", function()
	local n = GameConfig.Rescue and GameConfig.Rescue.bounceFeathers or 0
	H.ok(n <= 16, "bounceFeathers <= 16 (an accent smack; feathers are PARTS now), got " .. tostring(n))
end)

--------------------------------------------------------------------------------
-- TOMBSTONE: the lingering brown cloud must NEVER come back
--------------------------------------------------------------------------------
H.test("tombstone: lingering brown cloud is dead; feathers are discrete PARTS (FeatherBurst)", function()
	local em = builtEmitter()
	-- The linger envelope: life >= 2.5s. If this trips, someone restored the old emitter role.
	H.ok(em.Lifetime.Max <= 0.8,
		"REGRESSION: Lifetime.Max = " .. tostring(em.Lifetime.Max) .. " — the lingering cloud is back. " ..
		"The feather-CLOUD emitter is RETIRED. If you need lingering feathers, they are PARTS — see FeatherBurst.")
	-- FeatherBurst must still be loadable (the parts, not sprites, are the feathers now).
	local ok, fb = pcall(function() return Loader.load("FeatherBurst") end)
	H.ok(ok and fb ~= nil,
		"REGRESSION: FeatherBurst module missing — the discrete feather PARTS are gone. " ..
		"If you need lingering feathers, they are PARTS — FeatherBurst — not sprites.")
end)
