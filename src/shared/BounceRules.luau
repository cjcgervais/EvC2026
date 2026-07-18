--!nonstrict
--[[
	BounceRules — PURE decision helpers for the Packet B3 terrain "oof" bounce presentation.

	WHY THIS EXISTS: the client's collision block decides WHEN a graze is a "hard" contact worth the
	cartoon oof (feather poof + dazed stars) and debounces it so a slope-scrape doesn't machine-gun the
	FX. That decision is pure arithmetic on the BirdCollision.resolve output (the into-surface closing
	speed + a cooldown/leave-terrain gate), so it lives here as a shared pure module the headless Tier-4
	suite can exit-code gate (tests/bouncerules.spec.luau) — the B-phase charter: extract the testable
	logic out of the un-loadable client script so a code audit isn't the only check.

	PRESENTATION ONLY: nothing here touches flight/velocity/orientation/camera/kernel — it only answers
	"is this graze a hard contact, and may we fire the oof right now?". No instances, no Workspace.

	CONTRACT:
	  BounceRules.closingSpeed(velocity, normal) -> number
	     Into-surface closing speed = -velocity·normal (studs/s). This is the SAME quantity BirdCollision
	     uses for its lethal gate — a glancing pass ≈ 0, a head-on faceplant is large = "impact hardness".

	  BounceRules.hardness01(closing, minSpeed) -> number in [0,1]
	     Normalized impact hardness: 0 at the trigger threshold, ramping to 1 at ~2× the threshold. Used
	     to scale the feather-poof count (a harder smack = a bigger puff).

	  BounceRules.shouldBounce(closing, minSpeed, cooldown, grazeGap) -> bool
	     Fire the oof iff the closing speed cleared the threshold AND the debounce cooldown has elapsed
	     (cooldown <= 0) AND the eagle has left terrain since the last bounce (grazeGap == true). The
	     caller owns the cooldown/grazeGap state; this is the pure predicate over it.
]]

local BounceRules = {}

-- Into-surface closing speed (studs/s): how hard we drove INTO the surface along -normal. Mirrors
-- BirdCollision.resolve's `closing`. A glancing/parallel pass ≈ 0; a head-on ram is large.
function BounceRules.closingSpeed(velocity, normal)
	if not velocity or not normal then return 0 end
	return -velocity:Dot(normal)
end

-- Normalized impact hardness in [0,1]: 0 at `minSpeed`, saturating to 1 at ~2× minSpeed. Scales the
-- poof size. Guards a zero/negative minSpeed so we never divide by ~0.
function BounceRules.hardness01(closing, minSpeed)
	local m = math.max(1, minSpeed or 0)
	return math.clamp(((closing or 0) - m) / m, 0, 1)
end

-- The pure fire/no-fire predicate. `cooldown` = seconds left on the debounce (fire only when <= 0);
-- `grazeGap` = has the eagle had a contact-free frame since the last bounce (leave-terrain gate).
function BounceRules.shouldBounce(closing, minSpeed, cooldown, grazeGap)
	if (closing or 0) < (minSpeed or 0) then return false end
	if (cooldown or 0) > 0 then return false end
	if not grazeGap then return false end
	return true
end

return BounceRules
