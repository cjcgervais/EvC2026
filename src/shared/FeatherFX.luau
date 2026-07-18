--!nonstrict
--[[
	FeatherFX.luau — the brief IMPACT ACCENT ParticleEmitter for terrain-crash "oof".

	S41 ROLE CHANGE: this emitter is now the SMACK at the contact instant — a short, pale, dust-
	scuff puff that reads "hit" (born hazy, gone in ~0.5s). The FEATHERS are now discrete anchored
	PARTS (see FeatherBurst.luau + BirdController's FP pool), which are structurally incapable of
	blending into a brown ball. The old role of this module (a lingering brown feather CLOUD) is
	RETIRED; FeatherBurst owns that visual.

	WHY THE ROLE CHANGED:
	  The lingering soft-sprite cloud was iterated 3× and always blended into a fuzzy brown BALL —
	  overlapping semi-transparent round sprites alpha-blend into a cloud regardless of tuning.
	  The fix is structural: discrete PARTS for the feathers (FeatherBurst), this emitter for the
	  brief pale scuff at impact. Nothing brown ever lingers as a mass again.

	HONEST LIMIT: this gates the physics/persistence envelope of the accent. Whether the accent
	reads as a "smack" to a human eye is still a Studio glance.

	PRESENTATION ONLY: touches only the ParticleEmitter it is handed. No kernel / camera / input /
	flight / Workspace. `fx` is GameConfig.Combat.fx (the shared tunable dials); nil → fallbacks.

	CONTRACT:
	  FeatherFX.TEXTURE                       -> the sprite asset string.
	  FeatherFX.apply(emitter, fx) -> emitter   Sets the ACCENT properties on `emitter`; returns it.
	                                            Color is NOT set here (it is per-burst in burstFeathers).
]]

local FeatherFX = {}

-- Soft tuft sprite — fine for a quick dust scuff; swap for a dedicated impact decal if art lands.
FeatherFX.TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Author the BRIEF IMPACT ACCENT envelope onto `emitter`.
-- Fallbacks match GameConfig.Combat.fx S41 values so the spec and the client always agree.
function FeatherFX.apply(emitter, fx)
	local lifeMin = (fx and fx.featherLifeMin) or 0.4   -- s; a blink — the smack, not the linger
	local lifeMax = (fx and fx.featherLifeMax) or 0.6   -- s; gone before the feather ring even peaks
	local speed   = (fx and fx.featherSpeed)   or 18    -- studs/s; sharp fast opening — reads as impact
	local gravity = (fx and fx.featherGravity) or 2     -- irrelevant over 0.5s; near-zero
	local fsz     = (fx and fx.featherSize)    or 1.6   -- small scuff puff — the accent, not the read

	emitter.Texture = FeatherFX.TEXTURE
	emitter.Rate = 0                                     -- burst-only, via :Emit
	emitter.Lifetime = NumberRange.new(lifeMin, lifeMax)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -gravity, 0)  -- accent; near-zero gravity so the scuff hangs briefly
	emitter.Drag = 5                                     -- puff opens ~2 studs then dies fast
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)          -- mild spin; accent is round (not a feather vane)
	emitter.Squash = NumberSequence.new(0)               -- dust is round; the vane trick is retired (feathers are PARTS)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    fsz * 0.6),     -- born small
		NumberSequenceKeypoint.new(0.15, fsz),           -- quick pop to full
		NumberSequenceKeypoint.new(1,    fsz * 0.7),     -- slight decay
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.25),   -- born hazy (pale, not brown-feather solid)
		NumberSequenceKeypoint.new(0.5, 0.5),    -- already dying
		NumberSequenceKeypoint.new(1,   1),      -- gone
	})
	emitter.LightEmission = 0.1                          -- faint lift; accent should read pale/neutral
	return emitter
end

return FeatherFX
