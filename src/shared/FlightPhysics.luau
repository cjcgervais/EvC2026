--!nonstrict
--[[
	FlightPhysics v2 — deterministic 6DOF aerodynamic flight engine.

	Pure simulation: NO Roblox instances are touched here. The caller (BirdController
	for players, GameServer/Boids for AI crows) feeds it an input table each frame and
	reads back `orientation` (CFrame) and `velocity` (Vector3) to drive a BasePart.
	`.orientation` and `.velocity` are externally-authoritative state: callers may
	overwrite them after a BirdCollision sweep and the engine reads them fresh each step.

	WHY v2 (see docs/HANDOFF.md "flight kernel" + docs/RESEARCH.md): v1 produced "not
	enough lift, constant stalls" for two structural reasons that fought each other:
	  (1) lift was `Cl * q * sin(AoA)` — ZERO lift at zero angle of attack, so the bird
	      had to fly permanently nose-high just to hold altitude (a few degrees from stall).
	  (2) a per-frame path-tracker rotated VELOCITY toward the nose, i.e. it drove AoA->0,
	      which is exactly the no-lift condition. Any speed dip dropped control authority,
	      which weakened lift+control+tracking together -> a self-reinforcing stall spiral.

	v2 fixes both with the textbook game/aero model:
	  - REAL LIFT CURVE with a baseline coefficient: CL(a) = cl0 + slope*a, rising to
	    clMax at the stall angle, then a FORGIVING roll-off to postStallCl (never 0). With
	    cl0 > 0 the bird makes lift at zero AoA, so LEVEL CRUISE IS THE HANDS-OFF TRIM.
	  - DRAG POLAR CD = CD0 + k*CL^2: induced drag scales with lift^2 (~g-load^2), so hard
	    turns/climbs bleed energy -> Energy-Maneuverability emerges for free.
	  - STATIC AERODYNAMIC STABILITY (weathervane): the airframe gently rotates its
	    ORIENTATION toward the airflow (not velocity toward the nose). This self-limits AoA
	    (anti-stall) WITHOUT destroying lift, and the player's pitch input overrides it.
	    Past the stall a stronger nose-down-toward-airflow term makes "do nothing" recover.
	  - BANK-GATED coordinated turn (sustainedTurnRate): velocity is redirected toward the
	    nose ONLY while banked — the eagle-wide / crow-tight lever — never in the pitch
	    plane, so it cannot recreate the v1 AoA-killing bug.
	  - CONTROL AUTHORITY scales with airspeed: a slow/stalled bird can barely steer.

	API (consumed by BirdController / GameServer / Boids — do not change without callers):
	  FlightPhysics.new(profile, position) -> engine
	  engine:Update(dt, input)            input = {pitch, roll, yaw, flap, dive}
	  engine:SetThermalForce(Vector3)
	  engine:SetWind(Vector3)
	Readable fields: orientation (CFrame), velocity (Vector3), speed, verticalSpeed,
	  stamina, isFlapping, isDiving, isStalling, flapPhase, aoaDeg
]]

local GameConfig = require(script.Parent.GameConfig)
local F = GameConfig.Flight

local FlightPhysics = {}
FlightPhysics.__index = FlightPhysics

local EPS = 1e-4

local function clamp(x, lo, hi)
	if x < lo then return lo elseif x > hi then return hi else return x end
end

-- Smoothly rotate unit vector `from` toward unit vector `to` by at most `maxRad`.
local function rotateTowards(from, to, maxRad)
	local d = clamp(from:Dot(to), -1, 1)
	local angle = math.acos(d)
	if angle < EPS then return to end
	local t = clamp(maxRad / angle, 0, 1)
	local result = (from * (1 - t) + to * t)
	if result.Magnitude < EPS then return to end
	return result.Unit
end

-- Rigid-rotate an orientation CFrame so its LookVector turns toward `target` by at most
-- `maxRad` (the airframe weathervaning into the airflow). Roll/bank is carried along.
-- Position is PRESERVED: a world-space rotation is applied to the basis only (rotating on the
-- left of a CFrame would otherwise swing its position about the world origin -> teleport).
local function rotateLookToward(cf, target, maxRad)
	if maxRad < EPS then return cf end
	local look = cf.LookVector
	local d = clamp(look:Dot(target), -1, 1)
	local angle = math.acos(d)
	if angle < EPS then return cf end
	local axis = look:Cross(target)
	if axis.Magnitude < EPS then return cf end
	local r = CFrame.fromAxisAngle(axis.Unit, math.min(angle, maxRad))
	local pos = cf.Position
	return r * (cf - pos) + pos
end

-- LIFT CURVE: CL as a function of signed AoA (degrees). Baseline cl0 at zero AoA (this is
-- THE fix for "not enough lift"); linear slope to clMax at the stall angle; then a forgiving
-- lerp down to postStallCl over a stallPadDeg band (a mush, not a cliff). Symmetric in sign so
-- pushing the nose well below the airflow produces downforce rather than free lift.
local function computeCL(p, aoaDeg)
	local linear = p.cl0 + p.liftSlopePerDeg * aoaDeg
	local mag = math.abs(aoaDeg)
	if mag <= p.stallAngleDeg then
		return clamp(linear, -p.clMax, p.clMax)
	end
	local over = mag - p.stallAngleDeg
	local t = clamp(over / math.max(EPS, p.stallPadDeg), 0, 1)
	local clMag = p.clMax + (p.postStallCl - p.clMax) * t
	return (linear >= 0 and clMag) or -clMag
end

function FlightPhysics.new(profile, position)
	local self = setmetatable({}, FlightPhysics)
	self.profile = profile

	-- Kinematic state
	self.orientation = CFrame.new(position or Vector3.new(0, 200, 0))
	-- Spawn with cruise-ish forward speed, comfortably ABOVE stall speed (GameServer seeds the
	-- live Body velocity with the same factor; the client re-seeds from it on acquire).
	self.velocity = self.orientation.LookVector * (profile.glideSpeed * 0.9)

	-- Energy / status
	self.stamina = profile.maxStamina
	self.speed = self.velocity.Magnitude
	self.verticalSpeed = self.velocity.Y
	self.aoaDeg = 0

	-- FX / animation flags (read by BirdBuilder.AnimateWings + UI)
	self.isFlapping = false
	self.isDiving = false
	self.isStalling = false
	self.flapPhase = 0

	-- Smoothed control state (rollInertia gives controls weight)
	self._rollVel = 0
	self._pitchVel = 0
	self._yawVel = 0

	-- Environmental forces (set externally each frame)
	self._thermal = Vector3.new()
	self._wind = F.WIND_BASE
	return self
end

function FlightPhysics:SetThermalForce(v) self._thermal = v or Vector3.new() end
function FlightPhysics:SetWind(v) self._wind = v or Vector3.new() end

-- 0 (no control) .. 1 (full control) based on airspeed.
function FlightPhysics:_authority()
	return clamp(
		(self.speed - F.CONTROL_AUTHORITY_MIN_SPEED)
			/ math.max(EPS, F.CONTROL_AUTHORITY_FULL_SPEED - F.CONTROL_AUTHORITY_MIN_SPEED),
		0, 1
	)
end

function FlightPhysics:Update(dt, input)
	dt = math.min(dt, 1 / 30) -- guard against huge frame spikes blowing up integration
	local p = self.profile
	input = input or {}
	local inPitch = input.pitch or 0
	local inRoll = input.roll or 0
	local inYaw = input.yaw or 0
	local wantFlap = input.flap and self.stamina > 0
	local wantDive = input.dive == true

	local cf = self.orientation
	local authority = self:_authority()

	-- VERTICAL FLIGHT ENVELOPE: altFactor is 1 below this bird's service ceiling and fades to 0
	-- at it (climbCeilingBonus: eagle climbs higher than crow), throttling flap power + powered-
	-- climb lift near the top so the bird levels off there instead of climbing forever. While
	-- actively flapping, authority gets a floor so you can still command a climb at low airspeed
	-- -- the climb then ends from FATIGUE (stamina hits 0 -> wantFlap false -> floor gone) or the
	-- ceiling, not merely from bleeding speed. (See GameConfig.Flight "VERTICAL FLIGHT ENVELOPE".)
	local ceiling = F.SERVICE_CEILING * (p.climbCeilingBonus or 1)
	local altFactor = clamp((ceiling - cf.Position.Y) / math.max(EPS, F.CEILING_BAND), 0, 1)
	if wantFlap then
		authority = math.max(authority, F.FLAP_AUTHORITY_FLOOR * altFactor)
	end

	----------------------------------------------------------------------------
	-- 1. ROTATIONAL CONTROL (with inertia). Produces banking, pitch, yaw; no
	--    auto-leveling, so loops & barrel rolls are possible at speed.
	----------------------------------------------------------------------------
	-- Frame-rate-INDEPENDENT control smoothing: inertia^(dt*60) equals the original
	-- per-frame blend exactly at 60 FPS but keeps spool-up TIME constant at any framerate.
	local inertia = p.rollInertia
	local blend = 1 - inertia ^ (dt * 60)
	local function smooth(cur, target)
		return cur + (target - cur) * blend
	end
	self._rollVel  = smooth(self._rollVel,  inRoll  * p.rollRate  * authority)
	self._pitchVel = smooth(self._pitchVel, inPitch * p.pitchRate * authority)
	self._yawVel   = smooth(self._yawVel,   inYaw   * p.yawRate   * authority)

	-- Local-space rotation: pitch about X, yaw about Y, roll about Z.
	local rot = CFrame.Angles(self._pitchVel * dt, self._yawVel * dt, self._rollVel * dt)
	cf = self.orientation * rot
	local look = cf.LookVector
	local up = cf.UpVector

	----------------------------------------------------------------------------
	-- 2. AERODYNAMICS (world-space forces -> acceleration)
	----------------------------------------------------------------------------
	local airVel = self.velocity - self._wind
	local speed = airVel.Magnitude
	local accel = Vector3.new()

	-- gravity (persistent world force -> dive=accelerate / climb=decelerate fall out free)
	accel = accel + Vector3.new(0, -F.GRAVITY, 0)

	local cl = 0
	if speed > EPS then
		local velDir = airVel.Unit

		-- Angle of attack: signed angle between nose and airflow about the wing axis.
		-- Positive when the nose is ABOVE the flight path.
		local cosA = clamp(look:Dot(velDir), -1, 1)
		local aoa = math.acos(cosA)
		if up:Dot(velDir) > 0 then aoa = -aoa end
		self.aoaDeg = math.deg(aoa)

		self.isStalling = math.abs(self.aoaDeg) > p.stallAngleDeg

		-- LIFT: L/m_accel = CL(aoa) * rho * v^2 / wingLoading, perpendicular to airflow along
		-- the bird's up side. Mass-independent (lift balances weight, both scale with mass);
		-- wingLoading is the lever (low = more lift accel = lower stall + tighter turns = crow).
		cl = computeCL(p, self.aoaDeg)
		-- POWERED CLIMB: while flapping (and below the service ceiling) the beating wings keep
		-- making lift past the nominal stall, so a held climb mushes only when STAMINA runs out
		-- (fatigue) -- not merely when airspeed drops. Floors post-stall lift to FLAP_LIFT_FLOOR
		-- of clMax; altFactor fades it out at the ceiling. wantFlap is false once stamina hits 0,
		-- so the ordinary airspeed stall returns then (the fatigue stall the design wants).
		if wantFlap and altFactor > 0 and math.abs(self.aoaDeg) > p.stallAngleDeg then
			local powered = p.clMax * F.FLAP_LIFT_FLOOR * altFactor
			if powered > math.abs(cl) then
				cl = (self.aoaDeg >= 0) and powered or -powered
			end
		end
		local q = F.AIR_DENSITY * speed * speed
		local liftAccel = (cl * q) / p.wingLoading
		local liftDir = up - velDir * up:Dot(velDir)
		if liftDir.Magnitude > EPS then
			accel = accel + liftDir.Unit * liftAccel
		end

		-- DRAG polar: parasitic + induced(CL^2). Induced grows with lift^2 (~g-load^2), so
		-- hard turns/climbs bleed energy. Drag is a force -> /mass (heavier eagle keeps energy).
		local dragMag = (p.parasiticDrag + p.inducedDragK * cl * cl) * q
		accel = accel - velDir * (dragMag / p.mass)
	else
		self.isStalling = true
		self.aoaDeg = 0
	end

	-- THRUST. A DIVE is detected purely from nose attitude (nosed down) — no key needed to
	-- convert nose-down into acceleration. Flapping pushes along the nose (amplified diving);
	-- the dive key adds a powered tuck so you can drive the dive even without flapping.
	self.isFlapping = wantFlap and true or false
	self.isDiving = look.Y < -0.2
	if wantFlap or (wantDive and self.isDiving) then
		local thrust = wantFlap and p.flapThrust or (p.flapThrust * 0.5)
		if self.isDiving then thrust = thrust * p.diveThrustBonus end
		-- altFactor folds the service ceiling in: thrust fades to 0 at the envelope top, so you
		-- level off near the ceiling rather than flapping skyward forever (see _authority block).
		accel = accel + look * (thrust * altFactor / p.mass)
	end

	-- THERMAL (external upward force) — restores energy spent diving/turning.
	accel = accel + self._thermal

	-- PHUGOID DAMPING: the v2 drag polar gives a great glide but an almost undamped
	-- altitude<->speed oscillation (porpoising). Oppose vertical velocity with an
	-- aerodynamic force scaled by dynamic pressure (q ~ speed^2, normalized by glideSpeed
	-- so it's ~1 at cruise and fades to 0 when slow -- no free lift at rest/stall). RELEASE
	-- it under active pitch input and kill it while diving, so deliberate climbs and the
	-- stoop keep full authority; only hands-off level flight gets the smooth-glide assist.
	local release = 1 - clamp(math.abs(inPitch), 0, 1)
	if self.isDiving then release = 0 end
	if release > 0 and speed > EPS then
		local q01 = clamp((speed * speed) / (p.glideSpeed * p.glideSpeed), 0, 1)
		accel = accel + Vector3.new(0, -self.velocity.Y * F.PHUGOID_DAMPING * release * q01, 0)
	end

	----------------------------------------------------------------------------
	-- 3. INTEGRATE velocity
	----------------------------------------------------------------------------
	self.velocity = self.velocity + accel * dt

	----------------------------------------------------------------------------
	-- 4. STATIC AERODYNAMIC STABILITY (replaces v1 path-tracking) + bank-gated turn.
	--    Rotate the ORIENTATION toward the airflow so AoA self-limits (anti-stall) WITHOUT
	--    zeroing lift; the player's pitch input overrides this soft restoring tendency. Past
	--    the stall, add nose-down-toward-airflow so "do nothing" recovers the mush.
	----------------------------------------------------------------------------
	if self.velocity.Magnitude > F.CONTROL_AUTHORITY_MIN_SPEED then
		local vDir = self.velocity.Unit
		local stabRad = (F.STABILITY_RATE * p.stabilityRate * authority) * dt
		if self.isStalling then
			-- Stronger pull toward the airflow the deeper the stall (auto-recovery).
			local over = (math.abs(self.aoaDeg) - p.stallAngleDeg) / math.max(EPS, p.stallAngleDeg)
			stabRad = stabRad + (p.recoverNoseDownRate * clamp(over, 0, 2) * authority) * dt
		end
		-- AEROBATIC FREEDOM: above AEROBATIC_MIN_SPEED, an aggressive pitch/roll command suppresses
		-- the weathervane so the nose can swing away from the airflow — what lets a fast eagle pull
		-- a full LOOP or barrel roll instead of being auto-leveled out of it. Lift (perpendicular to
		-- airflow) is what then curves the velocity around the loop. Hands-off or slow flight keeps
		-- full stability, so this can never reintroduce the level-flight porpoising.
		local aero = clamp((self.velocity.Magnitude - F.AEROBATIC_MIN_SPEED)
			/ math.max(EPS, F.AEROBATIC_SPEED_BAND), 0, 1)
		local cmd = math.max(math.abs(inPitch), math.abs(inRoll))
		stabRad = stabRad * (1 - aero * cmd)
		cf = rotateLookToward(cf, vDir, stabRad)
		look = cf.LookVector
		up = cf.UpVector

		-- COORDINATED TURN (bank-gated): redirect velocity toward the nose ONLY while banked,
		-- capped by sustainedTurnRate (eagle wide vs crow tight). Never acts in the pitch plane,
		-- so it cannot recreate the v1 AoA-killing bug. Wings-level flight preserves AoA -> lift.
		local bank = 1 - math.abs(up.Y)               -- 0 wings-level .. 1 knife-edge
		local trackRate = p.sustainedTurnRate * bank * authority
		if trackRate > EPS then
			local vMag = self.velocity.Magnitude
			self.velocity = rotateTowards(self.velocity.Unit, look, trackRate * dt) * vMag
		end
	end

	-- Speed caps: dive cap when diving, level cap otherwise. Never exceed terminal.
	local cap = self.isDiving and p.diveSpeedCap or p.maxLevelSpeed
	cap = math.min(cap, F.TERMINAL_VELOCITY)
	local sp = self.velocity.Magnitude
	local hardCap = self.isDiving and p.diveSpeedCap or F.TERMINAL_VELOCITY
	if sp > hardCap then
		self.velocity = self.velocity.Unit * hardCap
	elseif (not self.isDiving) and (not wantFlap) and sp > cap then
		-- gentle bleed toward level cap while gliding
		self.velocity = self.velocity.Unit * (cap + (sp - cap) * math.max(0, 1 - dt * 0.5))
	end

	----------------------------------------------------------------------------
	-- 5. INTEGRATE position & rebuild orientation
	----------------------------------------------------------------------------
	local newPos = cf.Position + self.velocity * dt
	self.orientation = CFrame.fromMatrix(newPos, cf.RightVector, cf.UpVector, -cf.LookVector)

	----------------------------------------------------------------------------
	-- 6. ENERGY / STAMINA + animation phase
	----------------------------------------------------------------------------
	if wantFlap or (wantDive and self.isDiving) then
		local cost = self.isDiving and p.staminaDiveCost or p.staminaFlapCost
		self.stamina = math.max(0, self.stamina - cost * dt)
	else
		self.stamina = math.min(p.maxStamina, self.stamina + p.staminaRegen * dt)
	end

	self.speed = self.velocity.Magnitude
	self.verticalSpeed = self.velocity.Y
	local flapFreq = self.isFlapping and 9 or 2
	self.flapPhase = (self.flapPhase + dt * flapFreq) % (math.pi * 2)

	return self
end

return FlightPhysics
