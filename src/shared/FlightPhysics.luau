--!nonstrict
--[[
	FlightPhysics — deterministic 6DOF aerodynamic flight engine.

	Pure simulation: NO Roblox instances are touched here. The caller (BirdController
	for players, GameServer/Boids for AI crows) feeds it an input table each frame and
	reads back `orientation` (CFrame) and `velocity` (Vector3) to drive a BasePart.

	The model is built on Energy-Maneuverability theory (see docs/RESEARCH.md):
	  - LIFT follows the bird's UP vector projected perpendicular to airflow, so BANKING
	    automatically produces a turn (tilt the lift vector sideways -> centripetal force).
	  - A COORDINATED-TURN assist rotates velocity toward the nose, capped by the profile's
	    `sustainedTurnRate`. This is the second, independent turn knob the research demands
	    (instantaneous roll vs sustained turn): eagles bank fast but sustain a WIDE turn;
	    crows sustain a TIGHT turn.
	  - STALL: past the critical angle of attack, lift collapses — punishing nose-yanking
	    at low speed and giving the dive its risk.
	  - CONTROL AUTHORITY scales with airspeed: a slow/stalled bird can barely steer, which
	    is what makes energy management matter and unlocks loops/rolls only at speed.

	API (consumed by BirdController — do not change without updating callers):
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
	-- spherical-ish lerp; good enough for steering
	local result = (from * (1 - t) + to * t)
	if result.Magnitude < EPS then return to end
	return result.Unit
end

function FlightPhysics.new(profile, position)
	local self = setmetatable({}, FlightPhysics)
	self.profile = profile

	-- Kinematic state
	self.orientation = CFrame.new(position or Vector3.new(0, 200, 0))
	-- Start with cruise-ish forward speed so the bird flies rather than drops. Must be
	-- comfortably ABOVE the profile's stall speed or it spawns on the edge of a stall
	-- (this bit the eagle, whose stall speed was ~spawn speed). GameServer seeds the live
	-- Body velocity with the same factor; the client re-seeds from it on acquire.
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
	local look = cf.LookVector
	local up = cf.UpVector
	local authority = self:_authority()

	----------------------------------------------------------------------------
	-- 1. ROTATIONAL CONTROL (with inertia). Produces banking, pitch, yaw; no
	--    auto-leveling, so loops & barrel rolls are possible at speed.
	----------------------------------------------------------------------------
	-- Frame-rate-INDEPENDENT control smoothing. The old `(1 - inertia)` was a fixed
	-- per-frame blend, so a 144 FPS player spooled up roll/pitch/yaw far faster (in seconds)
	-- than a 30 FPS player — and control feel is also a balance number. `inertia^(dt*60)`
	-- equals the original blend exactly at 60 FPS but keeps the spool-up TIME constant at any
	-- framerate. (inertia is in (0,1) for both profiles, so the power is well-defined.)
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
	look = cf.LookVector
	up = cf.UpVector

	----------------------------------------------------------------------------
	-- 2. AERODYNAMICS (world-space forces -> acceleration)
	----------------------------------------------------------------------------
	local airVel = self.velocity - self._wind
	local speed = airVel.Magnitude
	local accel = Vector3.new()

	-- gravity
	accel = accel + Vector3.new(0, -F.GRAVITY, 0)

	if speed > EPS then
		local velDir = airVel.Unit

		-- Angle of attack: signed angle between nose and airflow, about the wing axis.
		local cosA = clamp(look:Dot(velDir), -1, 1)
		local aoa = math.acos(cosA)
		-- sign: positive when nose is above the velocity vector
		if up:Dot(velDir) > 0 then aoa = -aoa end
		self.aoaDeg = math.deg(aoa)

		-- Stall: lift falls off past the critical AoA.
		local stallRad = math.rad(p.stallAngleDeg)
		local stallFactor = 1
		if math.abs(aoa) > stallRad then
			self.isStalling = true
			local over = (math.abs(aoa) - stallRad) / stallRad
			-- Soft stall: lift bleeds off past the critical AoA but never vanishes (floor 0.3),
			-- so a stall is a recoverable mush (ease off, regain speed) rather than an
			-- unrecoverable death spiral. Path tracking (below) redirects velocity regardless of
			-- lift, so pulling out of a fall works even mid-stall. Still costs you altitude/speed.
			stallFactor = math.max(0.3, 1 - over * 0.8)
		else
			self.isStalling = false
		end

		-- LIFT: magnitude ~ Cl * rho * v^2 * sin(AoA) / wingLoading, perpendicular to
		-- airflow along the bird's up side. wingLoading divides -> higher loading needs
		-- more speed for the same lift (eagle), lower loading turns tighter (crow).
		local q = F.AIR_DENSITY * speed * speed
		local liftMag = (p.liftCoefficient * q * math.sin(math.abs(aoa)) * stallFactor) / p.wingLoading
		-- lift direction = bird-up projected perpendicular to velocity
		local liftDir = up - velDir * up:Dot(velDir)
		if liftDir.Magnitude > EPS then
			accel = accel + liftDir.Unit * (liftMag / p.mass)
		end

		-- DRAG: parasitic + induced (induced grows with AoA -> turning costs energy).
		local sinA = math.sin(math.abs(aoa))
		local dragMag = (p.parasiticDrag + p.inducedDragK * sinA * sinA) * q
		accel = accel - velDir * (dragMag / p.mass)
	else
		self.isStalling = true
		self.aoaDeg = 0
	end

	-- THRUST. A DIVE is now detected purely from nose attitude (nosed down) — you no longer
	-- need to hold the dive key to convert nose-down into acceleration, which is what players
	-- expect ("point down = speed up"; the level-speed cap lifts to diveSpeedCap while diving).
	-- Flapping pushes along the nose (amplified in a dive); the dive key (wantDive) adds a
	-- powered tuck so you can actively drive the dive even without flapping.
	self.isFlapping = wantFlap and true or false
	self.isDiving = look.Y < -0.2
	if wantFlap or (wantDive and self.isDiving) then
		local thrust = wantFlap and p.flapThrust or (p.flapThrust * 0.5)
		if self.isDiving then thrust = thrust * p.diveThrustBonus end
		accel = accel + look * (thrust / p.mass)
	end

	-- THERMAL (external upward force) — restores the energy spent diving/turning.
	accel = accel + self._thermal

	----------------------------------------------------------------------------
	-- 3. INTEGRATE velocity
	----------------------------------------------------------------------------
	self.velocity = self.velocity + accel * dt

	-- COORDINATED TURN: the second, independent turn knob. Rotate the velocity
	-- direction toward the nose, capped by sustainedTurnRate and scaled by bank
	-- angle (you turn by banking). This makes sustainedTurnRate a direct tuning lever.
	local v = self.velocity
	local vMag = v.Magnitude
	if vMag > F.CONTROL_AUTHORITY_MIN_SPEED then
		local bank = 1 - math.abs(up.Y)         -- 0 wings-level .. 1 knife-edge
		-- PATH TRACKING: rotate the velocity vector toward the nose. A base rate
		-- (F.PATH_TRACK_RATE) makes pitch responsive in EVERY attitude, so nosing down
		-- accelerates you along the dive and pulling up actually redirects your motion upward
		-- (you can recover from a fall) — the old model only tracked ~25% unless banked, which
		-- is why diving stalled and recovery felt impossible. sustainedTurnRate adds tightness
		-- when BANKED (eagle wide vs crow tight — the turn-fight lever). Authority-scaled so a
		-- slow bird still mushes out and can stall (energy management preserved).
		local trackRate = (F.PATH_TRACK_RATE + p.sustainedTurnRate * bank) * authority
		local newDir = rotateTowards(v.Unit, look, trackRate * dt)
		self.velocity = newDir * vMag
	end

	-- Speed caps: dive cap when diving, level cap otherwise. Never exceed terminal.
	local cap = self.isDiving and p.diveSpeedCap or p.maxLevelSpeed
	cap = math.min(cap, F.TERMINAL_VELOCITY)
	-- allow gravity to push past level cap when not thrusting (free-fall dives),
	-- but always clamp to the dive cap / terminal.
	local sp = self.velocity.Magnitude
	local hardCap = self.isDiving and p.diveSpeedCap or F.TERMINAL_VELOCITY
	if sp > hardCap then
		self.velocity = self.velocity.Unit * hardCap
	elseif (not self.isDiving) and (not wantFlap) and sp > cap then
		-- gentle bleed toward level cap while gliding
		self.velocity = self.velocity.Unit * (cap + (sp - cap) * math.max(0, 1 - dt * 0.5))
	end

	----------------------------------------------------------------------------
	-- 4. INTEGRATE position & rebuild orientation
	----------------------------------------------------------------------------
	local newPos = cf.Position + self.velocity * dt
	self.orientation = CFrame.fromMatrix(newPos, cf.RightVector, cf.UpVector, -cf.LookVector)

	----------------------------------------------------------------------------
	-- 5. ENERGY / STAMINA + animation phase
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
