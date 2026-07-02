--!nonstrict
--[[
	Boids — Reynolds steering for the 3 AI crows of a 4-crow squad.

	ARCHITECTURE (Reynolds: steering -> locomotion). This module is pure math and
	does TWO things, kept deliberately separate:

	  1. computeSteering(...)  -> a world-space DESIRED direction/acceleration vector
	     (separation + alignment + cohesion + goal pull), weighted by
	     GameConfig.Squad.boids and scaled per-formation (tight vs loose).

	  2. steeringToInput(...)  -> converts that desired direction into the SAME input
	     table the player feeds FlightPhysics: {pitch, roll, yaw, flap, dive}. The AI
	     crow therefore flies through the identical flight engine as the player — the
	     boids do not move the bird, they only fly it.

	NO RunService, NO Remotes, NO instances. Robust to nil / empty neighbors and
	zero-length vectors.
]]

local GameConfig = require(script.Parent.GameConfig)
local B = GameConfig.Squad.boids

local Boids = {}

local EPS = 1e-4

local function clamp(x, lo, hi)
	if x < lo then return lo elseif x > hi then return hi else return x end
end

-- Safe unit vector: returns zero vector for (near) zero-length input.
local function safeUnit(v)
	local m = v.Magnitude
	if m < EPS then return Vector3.new() end
	return v / m
end

-- Clamp a vector's magnitude to at most `maxMag`.
local function clampMagnitude(v, maxMag)
	local m = v.Magnitude
	if m > maxMag and m > EPS then
		return v * (maxMag / m)
	end
	return v
end

--------------------------------------------------------------------------------
-- 1. computeSteering
--    self         = { position = Vector3, velocity = Vector3 }
--    neighbors    = array of { position = Vector3, velocity = Vector3 }
--    goalPoint    = Vector3 | nil  (squad convergence point)
--    formationCfg = GameConfig.Squad.formations entry { spacing, cohesionMul, separationMul,
--                   alignmentMul? } (Squad.mob.steering passes alignmentMul/cohesionMul = 0)
--    returns a world-space desired acceleration vector, clamped to maxSteerForce.
--------------------------------------------------------------------------------
function Boids.computeSteering(self, neighbors, goalPoint, formationCfg)
	local pos = self.position
	local vel = self.velocity or Vector3.new()

	-- Formation scaling: spacing drives the separation distance, the muls bias the
	-- tight<->loose trade. Fall back to neutral if no formation supplied.
	local spacing = (formationCfg and formationCfg.spacing) or B.neighborRadius * 0.25
	local cohesionMul = (formationCfg and formationCfg.cohesionMul) or 1
	local separationMul = (formationCfg and formationCfg.separationMul) or 1
	-- alignmentMul: lets a steering profile scale/zero the alignment term the same way the
	-- cohesion/separation muls work (mob mode passes 0 — independent attackers don't match
	-- squadmate headings). Lua: 0 is truthy, so an explicit 0 survives the `or 1` fallback.
	local alignmentMul = (formationCfg and formationCfg.alignmentMul) or 1

	-- Perception cone: neighbors within neighborRadius AND inside neighborFovDeg of
	-- the bird's forward (its velocity direction). A bird with no speed perceives all.
	local fovCos = math.cos(math.rad(B.neighborFovDeg * 0.5))
	local forward = safeUnit(vel)
	local hasForward = forward.Magnitude > EPS

	local sep = Vector3.new()   -- steer away from close neighbors (1/dist weighted)
	local aliCount = 0
	local cohCount = 0
	local aliSum = Vector3.new() -- sum of neighbor velocities
	local cohSum = Vector3.new() -- sum of neighbor positions

	if neighbors then
		for _, n in ipairs(neighbors) do
			if n and n.position then
				local offset = n.position - pos
				local dist = offset.Magnitude
				if dist > EPS and dist <= B.neighborRadius then
					-- FOV filter (skip when this bird has no heading to define a cone).
					local inFov = true
					if hasForward then
						inFov = forward:Dot(offset / dist) >= fovCos
					end
					if inFov then
						-- SEPARATION: push directly away, stronger the closer we are.
						-- Scaled so the "want this much gap" is `spacing`.
						local push = (n.position - pos)
						-- weight ~ how far inside the desired spacing we are
						local closeness = math.max(EPS, dist)
						sep = sep - safeUnit(push) * (spacing / closeness)

						-- ALIGNMENT: match neighbor headings.
						if n.velocity then
							aliSum = aliSum + n.velocity
							aliCount = aliCount + 1
						end

						-- COHESION: steer toward the local centroid.
						cohSum = cohSum + n.position
						cohCount = cohCount + 1
					end
				end
			end
		end
	end

	-- Build each steering component as a UNIT direction so the GameConfig weights actually
	-- govern the blend. `sep` was accumulated at physical magnitude (spacing/dist per
	-- neighbor), so without this it dwarfed the unit alignment/cohesion/goal terms by ~5-10x
	-- whenever crows neared formation spacing — pinning steering to "flee neighbors" and
	-- making separationWeight/alignmentWeight/cohesionWeight inert. The closeness-weighted
	-- accumulation still biases the DIRECTION toward avoiding the nearest crow.
	local separation = safeUnit(sep)

	local alignment = Vector3.new()
	if aliCount > 0 then
		alignment = safeUnit(aliSum / aliCount)
	end

	local cohesion = Vector3.new()
	if cohCount > 0 then
		local centroid = cohSum / cohCount
		cohesion = safeUnit(centroid - pos)
	end

	-- GOAL pull: converge on the squad target (possessed crow / its target).
	local goal = Vector3.new()
	if goalPoint then
		goal = safeUnit(goalPoint - pos)
	end

	-- Weighted sum (GameConfig weights * per-formation muls).
	local steer = Vector3.new()
	steer = steer + separation * (B.separationWeight * separationMul)
	steer = steer + alignment  * (B.alignmentWeight * alignmentMul)
	steer = steer + cohesion   * (B.cohesionWeight * cohesionMul)
	-- Goal (eagle-chase) uses its OWN weight — the mobbing lever — so it can DOMINATE
	-- separation and pull the swarm onto the eagle (was pinned to cohesionWeight=1.0, which
	-- separation overpowered at close range → the crows scattered). Not formation-scaled so
	-- crows still rally hard when spread out. Falls back to cohesionWeight if goalWeight unset.
	steer = steer + goal * (B.goalWeight or B.cohesionWeight)

	-- Clamp to the max steering force the flight model can meaningfully chase.
	return clampMagnitude(steer, B.maxSteerForce)
end

--------------------------------------------------------------------------------
-- 2. steeringToInput
--    currentCFrame   = CFrame (the crow's orientation; FlightPhysics.orientation)
--    currentVelocity = Vector3
--    desiredDir      = Vector3 (output of computeSteering; need not be unit)
--    profile         = GameConfig.Profiles.Crow (for glideSpeed reference)
--    returns { pitch, roll, yaw, flap, dive } with all scalars in [-1, 1].
--
--  MAPPING (direction -> controls):
--    - Decompose the heading error (current LookVector -> desiredDir) into a
--      HORIZONTAL (yaw) component and a VERTICAL (pitch) component in bird space.
--    - Horizontal error -> ROLL (banking is how birds turn) + a smaller coordinating
--      YAW in the same direction. Kernel convention: +roll/+yaw = LEFT, so a
--      rightward error (yawError > 0) maps to NEGATIVE roll/yaw (see S25 note below).
--    - Vertical error   -> PITCH (nose up to climb, down to descend).
--    - flap = true when it must gain energy: desired heading is upward OR airspeed is
--      below the profile glide speed.
--    - dive = true when the desired direction points sharply downward.
--------------------------------------------------------------------------------
function Boids.steeringToInput(currentCFrame, currentVelocity, desiredDir, profile)
	local input = { pitch = 0, roll = 0, yaw = 0, flap = false, dive = false }

	local dir = safeUnit(desiredDir or Vector3.new())
	if dir.Magnitude < EPS then
		-- No desired direction: hold attitude, flap only if very slow.
		local sp = currentVelocity and currentVelocity.Magnitude or 0
		local glide = (profile and profile.glideSpeed) or 0
		input.flap = sp < glide * 0.85
		return input
	end

	local look = currentCFrame.LookVector
	local right = currentCFrame.RightVector
	local up = currentCFrame.UpVector

	-- Horizontal (yaw-plane) error: how far left/right the target is.
	-- Project both look and desired onto the world-horizontal plane for a clean
	-- left/right signal that is independent of current bank.
	local lookFlat = safeUnit(Vector3.new(look.X, 0, look.Z))
	local dirFlat = safeUnit(Vector3.new(dir.X, 0, dir.Z))

	local yawError = 0       -- -1 target hard left .. +1 target hard right
	if lookFlat.Magnitude > EPS and dirFlat.Magnitude > EPS then
		-- signed: right component of the desired heading
		local side = right.X * dirFlat.X + right.Z * dirFlat.Z
		local fwd = clamp(lookFlat:Dot(dirFlat), -1, 1)
		local angle = math.acos(fwd)              -- 0..pi magnitude of horizontal error
		yawError = clamp(angle / (math.pi * 0.5), 0, 1) * (side >= 0 and 1 or -1)
	else
		-- Degenerate (target straight up/down): fall back to body-relative right.
		yawError = clamp(right:Dot(dir), -1, 1)
	end

	-- Turn by BANKING: roll proportional to horizontal error, coordinating yaw smaller.
	-- ⚠️ SIGN (S25 — the "they always fly away" root cause): the kernel applies
	-- CFrame.Angles(pitch, yaw, roll) about LOCAL axes, so +roll RAISES the right wing (banks
	-- LEFT) and +yaw swings the nose LEFT — see BirdController's key map (A=+1 "bank left") and
	-- the mouse-aim's negated horizontal command. yawError is +1 for a target on the RIGHT, so
	-- both channels must be NEGATED to turn TOWARD it. The original un-negated mapping turned
	-- every AI crow AWAY from its goal — and "goal dead astern" is the STABLE equilibrium of an
	-- inverted controller, so crows flew calmly straight away from the eagle forever (6 playtests
	-- of "they scatter and fly away / I can only catch them"; no goal-side tune could make them
	-- converge on a target while the mapping pointed them away from it).
	input.roll = clamp(-yawError, -1, 1)
	input.yaw = clamp(-yawError * 0.35, -1, 1)

	-- Vertical (pitch) error: nose up when target is above current heading.
	-- Compare desired vertical component against current look vertical component.
	local pitchError = clamp((dir.Y - look.Y) * 1.5, -1, 1)
	-- FlightPhysics pitches about local X; positive input pitches nose up given the
	-- engine's CFrame.Angles(pitch, ...). Sign chosen so +pitchError -> climb.
	input.pitch = pitchError

	-- Reduce climb authority slightly while heavily banked so the bird carves the
	-- turn instead of fighting itself (purely a quality-of-flight nicety).
	local bankFactor = math.abs(up.Y) -- 1 wings-level .. 0 knife-edge
	input.pitch = clamp(input.pitch * (0.4 + 0.6 * bankFactor), -1, 1)

	-- FLAP: gain energy when climbing or when slow relative to glide speed.
	local sp = currentVelocity and currentVelocity.Magnitude or 0
	local glide = (profile and profile.glideSpeed) or 0
	input.flap = (dir.Y > 0.15) or (sp < glide)

	-- DIVE: desired direction points sharply down. Don't dive while also wanting flap
	-- to climb; a sharp downward goal wins. FlightPhysics only treats it as a dive if
	-- the nose is actually below horizontal, so this is a request, not a guarantee.
	if dir.Y < -0.4 then
		input.dive = true
		input.flap = false -- diving is the energy source here; let gravity work
	end

	return input
end

return Boids
