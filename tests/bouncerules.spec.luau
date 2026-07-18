--!nonstrict
--[[
	tests/bouncerules.spec.luau — headless gate for the Packet B3 terrain-bounce DECISION logic.

	WHY: the "oof" bounce presentation lives in the un-loadable client script, but WHEN it fires is pure
	arithmetic on the BirdCollision.resolve output — impact hardness (into-surface closing speed) + the
	debounce gate. That predicate was extracted to src/shared/BounceRules.luau precisely so a code audit
	isn't the only check on it. These cases pin: (1) closing speed = -velocity·normal (glancing ≈ 0, head-on
	large), (2) hardness normalizes to [0,1], (3) the fire/no-fire gate respects threshold + cooldown +
	leave-terrain, so a slope-scrape can't machine-gun the FX. It does NOT judge how the oof LOOKS (Gate-B Play).
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Vector3 = Loader.Vector3

local BounceRules = Loader.load("BounceRules")
local GameConfig = Loader.load("GameConfig")

-- ---- closingSpeed = impact hardness measure ----

H.test("closingSpeed: head-on into a flat ground reads the full speed", function()
	-- Falling straight down at 120 onto a floor whose normal points up → closing = 120.
	local vel = Vector3.new(0, -120, 0)
	local normal = Vector3.new(0, 1, 0)
	H.approx(BounceRules.closingSpeed(vel, normal), 120, 1e-3, "head-on closing")
end)

H.test("closingSpeed: a glancing parallel pass is ~0 (always a quiet graze)", function()
	-- Flying horizontally along a vertical wall (normal horizontal, velocity perpendicular to it).
	local vel = Vector3.new(0, 0, 200)          -- moving along +Z…
	local normal = Vector3.new(1, 0, 0)         -- …wall faces +X → no into-surface component.
	H.approx(BounceRules.closingSpeed(vel, normal), 0, 1e-3, "glancing closing")
end)

H.test("closingSpeed: flying AWAY from a surface is negative (never a bounce)", function()
	local vel = Vector3.new(0, 80, 0)           -- climbing away from the floor…
	local normal = Vector3.new(0, 1, 0)
	H.ok(BounceRules.closingSpeed(vel, normal) < 0, "away = negative closing")
end)

H.test("closingSpeed: nil guards return 0 (no error)", function()
	H.eq(BounceRules.closingSpeed(nil, Vector3.new(0, 1, 0)), 0, "nil velocity")
	H.eq(BounceRules.closingSpeed(Vector3.new(0, -1, 0), nil), 0, "nil normal")
end)

-- ---- hardness01 normalization ----

H.test("hardness01: 0 at the threshold, ~1 at ~2x, clamped", function()
	local m = 55
	H.approx(BounceRules.hardness01(m, m), 0, 1e-6, "at threshold = 0")
	H.approx(BounceRules.hardness01(2 * m, m), 1, 1e-6, "at 2x = 1")
	H.eq(BounceRules.hardness01(10 * m, m), 1, "way past = clamped to 1")
	H.eq(BounceRules.hardness01(0, m), 0, "below threshold = clamped to 0")
end)

H.test("hardness01: guards a zero/nil minSpeed (no divide-by-zero, finite)", function()
	H.finite(BounceRules.hardness01(100, 0), "zero minSpeed finite")
	H.finite(BounceRules.hardness01(100, nil), "nil minSpeed finite")
end)

-- ---- shouldBounce gate ----

H.test("shouldBounce: fires on a hard contact when armed", function()
	H.ok(BounceRules.shouldBounce(120, 55, 0, true), "hard + cooldown-clear + gap = fire")
end)

H.test("shouldBounce: a soft graze below threshold never fires", function()
	H.ok(not BounceRules.shouldBounce(40, 55, 0, true), "below threshold = no fire")
end)

H.test("shouldBounce: cooldown active blocks (debounce)", function()
	H.ok(not BounceRules.shouldBounce(120, 55, 0.3, true), "cooldown>0 = blocked")
end)

H.test("shouldBounce: no leave-terrain gap blocks (slope-scrape can't machine-gun)", function()
	H.ok(not BounceRules.shouldBounce(120, 55, 0, false), "grazeGap false = blocked")
end)

-- ---- config sanity (the tunables the client reads exist and are sane) ----

H.test("Rescue bounce tunables are present and sane", function()
	local R = GameConfig.Rescue
	H.ok(R ~= nil, "Rescue table exists")
	H.ok(type(R.bounceMinSpeed) == "number" and R.bounceMinSpeed > 0, "bounceMinSpeed > 0")
	H.ok(type(R.bounceDebounce) == "number" and R.bounceDebounce > 0, "bounceDebounce > 0")
	H.ok(type(R.dazeTime) == "number" and R.dazeTime > 0, "dazeTime > 0")
	H.ok(type(R.bounceFeathers) == "number" and R.bounceFeathers > 0, "bounceFeathers > 0")
	H.ok(type(R.dazeStarCount) == "number" and R.dazeStarCount >= 1, "dazeStarCount >= 1")
end)
