--!nonstrict
--[[
	FeatherBurst.luau — discrete anchored feather PARTS for the terrain-crash "oof" ring.

	WHY THIS EXISTS (3×-failed blob autopsy):
	  The old soft-sprite ParticleEmitter (FeatherFX) was tuned 3 times and always blended into
	  a brown BALL — overlapping semi-transparent round sprites alpha-blend into a fuzzy cloud no
	  matter how you tune count/size/speed. A soft-sprite cloud can NEVER read as discrete falling
	  feathers; that is structural, not a knob. This module replaces the "feathers" with discrete
	  anchored PARTS that are structurally incapable of merging into a blob.

	TECHNIQUE:
	  ~12 thin ELONGATED brown Parts burst OUTWARD in a RING, TUMBLE (spin on a random-ish axis),
	  FLUTTER DOWN (slow gravity + drag + tangential sinusoidal sway so the fall is not straight),
	  LINGER ~3s, then fade and park. FeatherFX is repurposed into a brief pale IMPACT ACCENT (the
	  "smack" at the contact instant); the parts are the aftermath.

	DESIGN:
	  • Deterministic: Math.random()/os.time()/argless Date are BANNED (lune env + headless tests).
	    All per-feather variation derived from the feather INDEX via a sin-hash.
	  • Pure: no Workspace/services touched here — the client BirdController owns the pool, writes
	    CFrames, and parents parts. This module is stateless math.
	  • Headless-gated: tests/featherburst.spec.luau asserts GEOMETRY / RING / FALL / FLUTTER /
	    PERSISTENCE / DETERMINISM / TOMBSTONE before a Studio flight is ever needed.
	  • PRESENTATION ONLY: no FlightPhysics kernel, camera law, input, BirdCollision, or kernel
	    tunables are touched. Anchored code-driven cosmetics only.

	CONTRACT:
	  FeatherBurst.buildFeather(folder, cfg, index)  -> Part
	  FeatherBurst.spawnState(index, count, cfg)      -> state table (pure)
	  FeatherBurst.step(state, dt, cfg)               -> state (mutates + returns)
	  FeatherBurst.partCFrame(state, origin)          -> CFrame
	  FeatherBurst.transparency(state, cfg)           -> number in [0,1]

	All dials come from cfg (GameConfig.Rescue.featherParts):
	  count, poolMax, life, ringSpeed, upSpeed, gravity, drag,
	  swayAmp, swayFreq, spinSpeed, size (Vector3), holdFrac.
]]

local FeatherBurst = {}

local TAU = 2 * math.pi
local BROWN      = Color3.fromRGB(96, 66, 40)    -- FEATHER_EAGLE body brown
local BROWN_LITE = Color3.fromRGB(141, 104, 64)  -- sun-caught vane; every 3rd feather — variation aids the discrete read

-- Deterministic per-index hash in [0,1) — NO math.random (banned in the lune env + headless gate).
-- Uses a sin-hash so every index yields a stable, distinct value across the [0,1) range.
local function h(i, k)
	return ((math.sin(i * k) * 43758.5453) % 1 + 1) % 1   -- always positive [0,1)
end

-- ONE anchored, thin, ELONGATED feather Part parented into `folder`.
-- Every 3rd feather tints lighter (sun-caught vane) so the ring reads as DISCRETE objects.
-- Parked (Transparency=1) until a burst claims it.
function FeatherBurst.buildFeather(folder, cfg, index)
	local size = (cfg and cfg.size) or Vector3.new(0.15, 2.4, 0.9)
	local p = Instance.new("Part")
	p.Name = "FeatherPart"
	p.Size = size
	p.Color = ((index or 0) % 3 == 0) and BROWN_LITE or BROWN
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1             -- parked until a burst claims it
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Locked = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- Deterministic initial state for feather #index of a `count` burst.
-- Pure — no instances touched. All variation is from the index, not Math.random.
function FeatherBurst.spawnState(index, count, cfg)
	local h1 = h(index, 12.9898)
	local h2 = h(index, 78.233)
	local h3 = h(index, 37.719)
	local h4 = h(index, 63.727)

	-- Angle: evenly spaced around a full circle, with a small per-feather jitter (±0.06 rad)
	-- so the ring reads organic but never collapses two feathers to the same slot.
	local angle = (index - 1) / count * TAU + (h1 - 0.5) * 0.12
	local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))

	return {
		pos = Vector3.new(0, 0, 0),   -- burst-local; the controller adds the world origin
		vel = radial * (cfg.ringSpeed * (0.85 + 0.3 * h2))
			+ Vector3.new(0, cfg.upSpeed * (0.85 + 0.3 * h3), 0),
		age = 0,
		-- Per-feather spin rates: each euler axis driven by a distinct hash value → lazy tumble,
		-- never a spin-blur. Scaled by spinSpeed from config.
		spinRates = Vector3.new(
			0.4 + 0.6 * h2,
			0.3 + 0.7 * h3,
			0.2 + 0.8 * h4
		) * cfg.spinSpeed,
		-- swayDir is TANGENTIAL to the radial direction so sway is guaranteed to deviate the
		-- feather's path AWAY from a straight radial line — this is the "flutter" read.
		swayDir = Vector3.new(-math.sin(angle), 0, math.cos(angle)),
		swayPhase = h1 * TAU,
		swayFreq = cfg.swayFreq * (0.8 + 0.4 * h4),
	}
end

-- Advance one feather's kinematic state by dt seconds.
-- Linear-drag gravity model: dv/dt = -gravity*Y - drag*v
-- Sway: analytic sinusoid delta so the flutter is dt-stable and not purely Euler.
function FeatherBurst.step(state, dt, cfg)
	-- Gravity + linear drag on velocity
	state.vel = state.vel + Vector3.new(0, -cfg.gravity, 0) * dt - state.vel * (cfg.drag * dt)

	-- Analytic sway delta: Δpos_sway = swayDir * swayAmp * (sin(newPhase) - sin(oldPhase))
	-- This gives dt-stable flutter without accumulating Euler integration drift.
	local s0 = math.sin(state.swayPhase)
	state.swayPhase = state.swayPhase + state.swayFreq * TAU * dt
	local s1 = math.sin(state.swayPhase)

	-- Advance position: velocity contribution + tangential sway delta
	state.pos = state.pos + state.vel * dt + state.swayDir * (cfg.swayAmp * (s1 - s0))

	state.age = state.age + dt
	return state
end

-- World CFrame: translate to (origin + local pos) + euler tumble from accumulated spin.
-- CFrame.fromEulerAnglesXYZ is supported by @lune/roblox.
function FeatherBurst.partCFrame(state, origin)
	local r = state.spinRates * state.age
	return CFrame.new(origin + state.pos) * CFrame.fromEulerAnglesXYZ(r.X, r.Y, r.Z)
end

-- Transparency ramp: fully opaque for holdFrac of life, then linear fade to 1.
-- Returns 1 (parked/invisible) when age >= life.
function FeatherBurst.transparency(state, cfg)
	local t = state.age / cfg.life
	if t >= 1 then return 1 end
	local hold = cfg.holdFrac or 0.75
	if t <= hold then return 0 end
	return (t - hold) / (1 - hold)
end

return FeatherBurst
