--!strict
--[[
	GameConfig — single source of truth for all tunable constants.

	DESIGN THESIS (do not violate): flight physics and asymmetric balance are ONE
	system. Every flight number below is also a balance number. Tune them together.
	See docs/RESEARCH.md and docs/HANDOFF.md.

	The flight model is built on Energy-Maneuverability theory: each bird's behaviour
	is governed by its ability to convert energy (altitude <-> speed) and to turn.
	- EAGLE  = energy fighter (boom-and-zoom): high wing loading -> fast, WIDE turns,
	           strong climb/dive, high endurance. Wins by attrition.
	- CROW   = angles fighter: low wing loading -> tight turns, fast roll, agile in a
	           swarm of 4. Trades/sacrifices collisions.

	Units: studs, seconds. Workspace.Gravity is 196.2 studs/s^2 (Roblox default).
]]

local GameConfig = {}

--------------------------------------------------------------------------------
-- GLOBAL FLIGHT ENVIRONMENT
--------------------------------------------------------------------------------
GameConfig.Flight = {
	GRAVITY = 196.2,            -- studs/s^2; matches Workspace.Gravity
	-- AIR_DENSITY is the abstract scalar that folds 0.5*rho*wingArea into the lift/drag terms.
	-- CALIBRATED for the v2 lift curve: with cl0~0.3 and these profiles, level cruise at each
	-- bird's glideSpeed trims at a few degrees AoA (lift ~= gravity), and stall speed sits well
	-- below spawn (0.9*glide) and cruise. See FlightPhysics.computeCL and the calibration note
	-- in project-open-questions. Raising it raises lift everywhere (lower stall speeds).
	AIR_DENSITY = 0.033,
	WIND_BASE = Vector3.new(0, 0, 0), -- ambient wind; per-map override allowed
	-- Control authority scales with airspeed: below MIN you can barely steer
	-- (this is what makes a stalled/slow bird helpless and gives speed meaning).
	CONTROL_AUTHORITY_MIN_SPEED = 20,  -- studs/s where control ~0
	CONTROL_AUTHORITY_FULL_SPEED = 90, -- studs/s where control is full
	-- Aerobatics (loop / barrel roll) unlock above this airspeed.
	AEROBATIC_MIN_SPEED = 110,
	TERMINAL_VELOCITY = 400,
	-- STATIC AERODYNAMIC STABILITY (rad/s base): how fast the airframe weathervanes its
	-- ORIENTATION toward the airflow. This self-limits angle-of-attack (anti-stall) WITHOUT
	-- destroying lift — it rotates the nose toward the path, not the path toward the nose, so
	-- the v2 kernel keeps lift while the player's pitch input still dominates. Per-profile
	-- `stabilityRate` multiplies this; `recoverNoseDownRate` adds extra pull past the stall.
	-- (Replaces v1's PATH_TRACK_RATE, which rotated VELOCITY toward the nose and thus drove
	-- AoA->0->no-lift — the root cause of the old constant-stall spiral.)
	-- Auto-leveling weathervane, now a WHISPER (was 1.5 -> 0.7 -> 0.15). The player asked to
	-- "eliminate auto-leveling"; the grip assist below (velocity follows the nose) is what now
	-- keeps AoA low / prevents stall, so the nose no longer needs to be dragged back to the
	-- airflow. A tiny residual keeps the craft from drifting weirdly at very low speed; the
	-- past-stall recoverNoseDownRate term still fires for stall safety. PLAYTEST-PROVISIONAL.
	STABILITY_RATE = 0.15,
	-- GRIP / ALIGNMENT ASSIST (rad/s base, airspeed-scaled). Research §v2: great arcade-sim
	-- flight = "force-based core + a grip/alignment assist". This rotates VELOCITY toward the
	-- nose in EVERY attitude so the bird flies where it points — point up, you climb (with lift),
	-- not stall. THE fix for the recurring "not enough lift / too much stall". Per-profile
	-- sustainedTurnRate adds the eagle-wide/crow-tight turn tightness ON TOP in banked turns.
	-- Higher = more "on rails" (toward noclip); lower = more loose/aerodynamic. PLAYTEST-PROVISIONAL.
	GRIP_RATE = 2.2,
	-- PHUGOID DAMPING (vertical-motion stabilizer, studs/s of vertical accel per stud/s of
	-- climb rate). A high-L/D wing (the eagle glides at L/D ~34) has an almost UNDAMPED
	-- phugoid: lift responds to speed, so the bird slowly trades altitude<->speed in a ~3s
	-- oscillation -> visible porpoising/bobbing, worst while flapping (overspeed balloons it).
	-- Real airframes shed this via pitch damping; here it's an aerodynamic force opposing
	-- vertical velocity, scaled by dynamic pressure so it fades at low speed and never makes
	-- free lift at rest. RELEASED by active pitch input and disabled while diving, so
	-- intentional climbs and the dive/stoop keep full authority. Higher = stiffer, more
	-- "on-rails" glide; 0 = pure (porpoising) aero. PLAYTEST-PROVISIONAL.
	PHUGOID_DAMPING = 2.1,
	-- VERTICAL FLIGHT ENVELOPE (powered climb + service ceiling). Design rule (Chad, session 6):
	-- "as long as you can flap you should be able to climb" — a sustained climb should end from
	-- FATIGUE (running out of stamina) or the ceiling, NOT merely from bleeding airspeed. While
	-- actively flapping, control authority gets a floor (so you can still command the climb at low
	-- speed) and the beating wings keep making lift past the nominal stall; when stamina hits 0 you
	-- can't flap, the floors vanish, and the airspeed stall returns (the fatigue stall).
	-- SERVICE_CEILING (× per-profile climbCeilingBonus — eagle climbs higher than crow) is the top
	-- of the envelope: flap power and powered-climb lift fade to 0 over CEILING_BAND studs below it,
	-- so the bird levels off near the top instead of climbing forever. Combat happens below
	-- Thermals.maxHeight (480); the eagle ceiling (520) sits just above so the wall is only felt at
	-- the very top. PLAYTEST-PROVISIONAL.
	SERVICE_CEILING = 520,      -- studs; envelope top for climbCeilingBonus = 1.0 (the eagle)
	CEILING_BAND = 140,         -- studs below the ceiling over which flap power fades to 0
	FLAP_AUTHORITY_FLOOR = 0.6, -- min control authority while flapping (lets you hold a slow climb without tumbling)
	FLAP_LIFT_FLOOR = 0.55,     -- fraction of clMax lift retained past stall WHILE FLAPPING (anti-mush)
	-- AEROBATIC FREEDOM: above AEROBATIC_MIN_SPEED, an aggressive pitch/roll command suppresses the
	-- weathervane so the nose can swing away from the airflow — this is what lets a fast eagle pull a
	-- full LOOP or barrel roll instead of being auto-leveled out of it. Ramps in over
	-- AEROBATIC_SPEED_BAND studs/s above the min; hands-off/slow flight keeps full stability (so it
	-- can never reintroduce the level-flight porpoising). PLAYTEST-PROVISIONAL.
	AEROBATIC_SPEED_BAND = 40,
	-- OBSTACLE COLLISION (BirdCollision, queue #4). Birds are CFrame-driven so they have NO
	-- native Roblox collision — the controllers sweep a Spherecast along each step instead.
	-- CRASH_SPEED is the CLOSING speed (studs/s, into a surface normal) at or above which a
	-- map impact is lethal; below it the bird slides along the surface (graze a spire, brush
	-- the ground) instead of dying. This is a flight==balance lever: low value = terrain is a
	-- deadly hazard the agile crow can thread but the fast wide-turning eagle clips in a turn
	-- fight. PLAYTEST-PROVISIONAL.
	CRASH_SPEED = 45,
}

--------------------------------------------------------------------------------
-- PER-CLASS FLIGHT + COMBAT PROFILES
-- FlightPhysics.new(profile, position) consumes a Profiles entry verbatim.
-- Keep these two profiles structurally identical (same keys) so the engine is
-- class-agnostic. ALL asymmetry lives in these numbers.
--------------------------------------------------------------------------------
GameConfig.Profiles = {
	--========================================================================
	Eagle = {
		displayName = "Eagle",

		-- AERODYNAMICS -------------------------------------------------------
		mass = 16,              -- raised session 7: speed accel/decel felt too twitchy; mass = momentum (thrust/mass & drag/mass both gentler -> energy fighter retains energy). Lift is mass-independent so trim/stall unchanged.
		wingLoading = 1.0,      -- HIGH: fast, wide turns, strong glide/dive (reference = 1.0)
		-- v2 LIFT CURVE: CL(a) = cl0 + liftSlopePerDeg*a, capped at clMax at the stall angle,
		-- then a forgiving roll-off to postStallCl over stallPadDeg. cl0 > 0 means the eagle
		-- makes lift at ZERO AoA, so level cruise (~130) is the hands-off trim instead of the
		-- old knife-edge stall. Calibrated so stall speed (~65) sits below spawn (0.9*glide=117)
		-- and cruise (130). See FlightPhysics.computeCL. PLAYTEST-PROVISIONAL.
		cl0 = 0.30,             -- baseline lift at zero AoA (THE fix for "not enough lift")
		liftSlopePerDeg = 0.11, -- lift-curve slope (~= 2*pi per radian, thin-airfoil theory)
		clMax = 1.6,            -- peak lift (raised session 7: more lift, more forgiving high-AoA, stall speed ~65->61)
		postStallCl = 0.70,     -- lift retained past the stall (a recoverable mush, not a cliff)
		stallPadDeg = 6,        -- degrees beyond stallAngle over which lift rolls off
		parasiticDrag = 0.020,  -- low parasitic drag -> great glide/dive
		inducedDragK = 0.85,    -- induced-drag coefficient (cost of lift: drag ~ k*CL^2)
		stallAngleDeg = 24,     -- critical AoA before lift rolls off (widened session 7: stalled too easily climbing)
		stabilityRate = 1.0,    -- weathervane strength (stable boom-and-zoom platform)
		recoverNoseDownRate = 1.5, -- extra nose-down toward airflow past the stall (auto-recovery)

		-- THRUST / SPEED -----------------------------------------------------
		-- flapThrust must overcome cruise drag so the eagle can hold level flight instead of
		-- decaying into a stall. At 130 cruise, drag decel ≈ 41 studs/s²; old 380/mass≈32 was
		-- short, so level flight bled speed until it stalled. 520/12≈43 lets it sustain/slowly
		-- gain at cruise. It still trades altitude for top speed (energy fighter) — the dive,
		-- not the flap, is its speed source. PLAYTEST-PROVISIONAL.
		flapThrust = 520,       -- forward force from a flap
		flapClimbForce = 300,   -- session 7: upward climb accel while flapping with the nose up. Set
		                        -- ABOVE gravity (196) so a flapping eagle keeps climbing even after a
		                        -- steep climb has bled its airspeed (lift ~0) — a real eagle muscles up
		                        -- on wingbeats, not airspeed. "Flap = climb" until stamina/ceiling. THE
		                        -- climb-rate knob; mass-independent so the momentum tuning doesn't sap it.
		glideSpeed = 130,       -- comfortable cruise (high)
		maxLevelSpeed = 170,
		diveThrustBonus = 1.6,  -- thrust multiplier while diving (gravity also assists)
		diveSpeedCap = 320,     -- crows cannot match this top-end dive speed

		-- TURN / CONTROL (TWO turn params — see RESEARCH caveat) -------------
		rollRate = 3.2,         -- rad/s instantaneous roll authority (banking)
		pitchRate = 2.0,        -- rad/s pitch (lowered session 7: nose-down felt too fast; mouse adds analog fine control)
		yawRate = 1.1,          -- rad/s head-led yaw (slow; turns are made by banking)
		sustainedTurnRate = 1.0,-- rad/s sustained level turn ceiling (LOW: wide turns)
		rollInertia = 0.55,     -- 0..1 sluggishness; higher = heavier-feeling controls

		-- ENERGY / STAMINA (flapping & hard manoeuvres cost stamina) ---------
		maxStamina = 100,
		staminaFlapCost = 9,    -- per second of flapping
		staminaDiveCost = 4,    -- per second of powered dive
		staminaRegen = 7,       -- per second when gliding
		climbCeilingBonus = 1.0,-- relative climb ceiling (eagle climbs higher)

		-- COMBAT / ENDURANCE -------------------------------------------------
		health = 100,           -- ~= 4 crows (see project-open-questions memory)
		beakDamage = 22,        -- close peck
		talonDamage = 34,       -- grab/strike, the bread-and-butter eagle kill
		diveAttackMultiplier = 3.46, -- RESEARCH: stoop ~3.46x level-flight lethality
		-- Collision: eagle is the heavy body; it survives trades better than a crow.
		collisionDamageDealt = 60,   -- damage IT inflicts on whatever bird it rams (full-speed)
		-- Vulnerability multiplier applied to the OTHER bird's incoming ram
		-- (see GameServer.processCollisions). Eagle is the heavy body: a full-speed crow
		-- ram (crow dealt 30) does 30*0.85 ≈ 26 to it, so ~4 rams kill the 100-HP eagle —
		-- the documented trade. PLAYTEST-PROVISIONAL (collision tuning = queue item #3).
		collisionDamageTaken = 0.85,
		bodyRadius = 4.5,           -- collision/attack reach (studs)
	},

	--========================================================================
	Crow = {
		displayName = "Crow",

		-- AERODYNAMICS -------------------------------------------------------
		mass = 3.0,
		wingLoading = 0.55,     -- LOW: more lift accel -> lower stall speed + tighter turns
		-- v2 LIFT CURVE (see Eagle for the model). Crow has higher clMax + later stall so it can
		-- point its nose harder and out-turn the eagle; low wingLoading gives it a very low stall
		-- speed (~47 < spawn 0.9*glide=85 < cruise 95). PLAYTEST-PROVISIONAL.
		cl0 = 0.30,             -- baseline lift at zero AoA
		liftSlopePerDeg = 0.11, -- lift-curve slope
		clMax = 1.6,            -- higher peak lift -> harder instantaneous turn (angles fighter)
		postStallCl = 0.90,     -- very forgiving post-stall (twitchy but recoverable)
		stallPadDeg = 8,        -- gentle, wide stall roll-off
		parasiticDrag = 0.045,  -- higher drag -> bleeds energy faster, worse glide/dive
		inducedDragK = 0.55,    -- cheaper to turn (pays less induced drag per unit lift)
		stallAngleDeg = 24,     -- stalls later -> can point nose harder without dropping
		stabilityRate = 0.7,    -- LESS weathervaning: holds AoA to point the nose (agile/twitchy)
		recoverNoseDownRate = 1.2, -- auto-recovery past the stall

		-- THRUST / SPEED -----------------------------------------------------
		flapThrust = 150,
		flapClimbForce = 200,   -- lower than the eagle: the crow is less of a climber (lower ceiling via climbCeilingBonus)
		glideSpeed = 95,
		maxLevelSpeed = 140,    -- slightly slower top end than eagle in level flight
		diveThrustBonus = 1.25,
		diveSpeedCap = 220,     -- much lower dive cap: cannot win a vertical energy fight

		-- TURN / CONTROL -----------------------------------------------------
		rollRate = 5.0,         -- very fast roll (swarm agility)
		pitchRate = 3.6,
		yawRate = 1.8,
		sustainedTurnRate = 2.1,-- HIGH sustained turn: wins the prolonged turn fight
		rollInertia = 0.20,     -- light, twitchy controls

		-- ENERGY / STAMINA ---------------------------------------------------
		maxStamina = 70,
		staminaFlapCost = 6,
		staminaDiveCost = 5,
		staminaRegen = 9,       -- regenerates fast
		climbCeilingBonus = 0.7,-- lower climb ceiling than eagle

		-- COMBAT / ENDURANCE -------------------------------------------------
		health = 25,            -- 4 crows ~= 1 eagle of HP
		beakDamage = 9,
		talonDamage = 12,
		diveAttackMultiplier = 2.0,  -- crows dive too, but it is not their identity
		-- The SACRIFICE: a crow ramming at full speed deals 30 to whatever it hits, and dies.
		-- It absorbs the eagle's heavy body (eagle dealt 60) * 1.4 = 84 >> 25 HP, so a ram is
		-- a true trade — ~4 crow rams down an eagle, and each ramming crow dies in the process.
		-- The eagle avoids the math by out-positioning and picking off stragglers.
		collisionDamageDealt = 30,
		collisionDamageTaken = 1.4,  -- >1: fragile body; a full-speed hit is fatal (it trades)
		bodyRadius = 2.2,
	},
}

--------------------------------------------------------------------------------
-- SQUAD / FORMATION (Crow only) — see RESEARCH: tightness is the core risk knob.
--------------------------------------------------------------------------------
GameConfig.Squad = {
	size = 4,
	-- Boids weights (Reynolds: separation / alignment / cohesion) for AI crows.
	boids = {
		separationWeight = 1.5,
		alignmentWeight = 1.0,
		cohesionWeight = 1.0,
		neighborRadius = 60,     -- studs; local perception
		neighborFovDeg = 270,    -- field-of-view angle of the perception cone
		maxSteerForce = 220,
	},
	-- Formation presets: spacing is the tight<->loose knob.
	-- TIGHT: protected + concentrated offense, but catastrophic dive/collision exposure.
	-- LOOSE: coverage + resilience, but exposes stragglers the eagle hunts.
	formations = {
		tight = { spacing = 8,  cohesionMul = 1.6, separationMul = 0.7, collisionRisk = 1.5 },
		loose = { spacing = 26, cohesionMul = 0.8, separationMul = 1.4, collisionRisk = 0.7 },
	},
	defaultFormation = "loose",
	-- How a non-possessed crow supports: it mirrors the squad heading and converges
	-- on the possessed crow's target when within engageRadius.
	engageRadius = 45,
	swapCooldown = 0.35,         -- seconds between possession swaps (anti-spam)
}

--------------------------------------------------------------------------------
-- THERMALS — restore energy (altitude currency). Placed by GameServer.
--------------------------------------------------------------------------------
GameConfig.Thermals = {
	count = 6,
	radius = 90,
	minHeight = 20,
	maxHeight = 480,
	strength = 140,   -- upward force at the core (studs/s^2-ish)
}

--------------------------------------------------------------------------------
-- DEBUG — development aids. `soloFlight` lets ONE player spawn and fly for a smoke
-- test WITHOUT a full Eagle-vs-Crow match (no scored round; AI crows + possession
-- still run so a solo crow can exercise the squad). It transitions cleanly into a
-- real scored match the moment a second team joins. Set false for production.
-- (Consumed by GameServer.RoundLoop.)
--------------------------------------------------------------------------------
GameConfig.Debug = {
	soloFlight = true,
}

--------------------------------------------------------------------------------
-- SECURITY — server-side anti-cheat envelope (GameServer.processAntiCheat). The client
-- OWNS its bird's physics (SetNetworkOwner) for latency-free flight, so the server cannot
-- trust the CFrame/velocity it reads. It instead measures SERVER-OBSERVED speed from
-- position deltas and validates against a generous envelope, using a leaky bucket so honest
-- dives/loops/lag spikes never false-positive. Response ladder: rubber-band → reclaim
-- ownership → kick, with strikes that decay over time. Tune conservatively — a false
-- positive on an honest player feels awful. See docs/HANDOFF.md queue #5.
--------------------------------------------------------------------------------
GameConfig.Security = {
	enabled = true,
	-- Sustained-speed ceiling = Flight.TERMINAL_VELOCITY × this. We base it on TERMINAL (not a
	-- profile's diveSpeedCap) because the honest FlightPhysics engine clamps top speed to
	-- TERMINAL, so an honest bird FREE-FALLING (not diving — diveSpeedCap doesn't apply) can
	-- legitimately approach TERMINAL. Basing the ceiling on diveSpeedCap would false-positive a
	-- plummeting crow. A real speed hack still blows past TERMINAL×1.25.
	speedAllowMult = 1.25,    -- => ~500 studs/s sustained ceiling at TERMINAL 400
	teleportMult = 1.5,       -- per-frame teleport gate = TERMINAL × this (~600); single-frame jump
	pingPadStuds = 30,        -- extra teleport-gate slack for replication jitter/lag
	bucketCapacity = 120,     -- accumulated overshoot (studs) before a strike is issued
	bucketLeak = 200,         -- bucket drains this many studs/sec (transient spikes forgiven)
	graceSeconds = 0.5,       -- ignore window right after a legit server move (spawn/swap/respawn)
	reclaimStrikes = 3,       -- strikes before the server reclaims network ownership
	kickStrikes = 6,          -- strikes before the player is kicked
	strikeDecaySeconds = 12,  -- one strike forgiven per this many seconds of clean flight
}

--------------------------------------------------------------------------------
-- ROUND / SCORING
--------------------------------------------------------------------------------
GameConfig.Round = {
	intermission = 8,
	roundLength = 240,
	respawnDelay = 4,
	-- Win conditions: eagle dead -> crows win; all 4 crows dead -> eagle wins.
}

--------------------------------------------------------------------------------
-- CAMERA — consumed by BirdController (do not rename keys; client reads these)
--------------------------------------------------------------------------------
GameConfig.Camera = {
	baseDistance = 26,
	baseFOV = 70,
	diveFOV = 95,
	climbFOV = 62,
	speedDistanceFactor = 0.06,
	bankTiltFactor = 0.6,
	followSmoothing = 0.18,
	shakeAtSpeed = 200,
	shakeMagnitude = 0.6,
	-- Spacebar free-look: orbit the camera while the bird holds its flight path.
	freeLookSensitivity = 0.35,
}

--------------------------------------------------------------------------------
-- CONTROLS — input scheme (consumed by BirdController). MOUSE STEERING: the mouse is locked
-- to screen center and drives a VIRTUAL STICK (mouse movement deflects it; it springs back
-- toward center at mouseReturn). The stick = analog pitch/roll, SUMMED with W/S/A/D. It starts
-- at exactly zero every life (NOT absolute cursor position — that spawned a spiral crash when
-- the real cursor wasn't centered). Free-look (hold Space) suspends steering and orbits the
-- camera. The lowered STABILITY_RATE is what lets your aim actually hold. PLAYTEST-PROVISIONAL.
--------------------------------------------------------------------------------
GameConfig.Controls = {
	mouseSteer      = false, -- DISABLED for now (session 7) — keyboard-only control while we tune flight feel. Flip back to true to re-enable mouse nose-aim.
	mouseSensitivity= 1.0,   -- mouse-delta -> virtual-stick gain (higher = nose moves more per mouse inch)
	-- Spring of the stick back to center (per-sec) when you stop moving the mouse. SPLIT by axis:
	-- ROLL self-centers fast (wings level themselves -> anti-spiral, arcade-friendly), but PITCH
	-- barely returns so you can HOLD a climb or dive without continuously feeding the mouse. Pitch
	-- ~0 = the nose stays where you aim it (this is what makes sustained climbing possible).
	mouseReturnRoll  = 3.0,
	mouseReturnPitch = 0.4,
	mouseExpo       = 1.7,   -- response curve: 1 = linear, >1 = finer control near center
	invertPitch     = false, -- false = mouse UP pitches nose UP (FPS-style). Set true for stick-style (pull back = up).
}

--------------------------------------------------------------------------------
-- UI — consumed by GameUI (do not rename keys; client reads these)
--------------------------------------------------------------------------------
GameConfig.UI = {
	hudColor = Color3.fromRGB(18, 20, 28),
	hudTransparency = 0.35,
	font = Enum.Font.GothamBold,
	fontMedium = Enum.Font.GothamMedium,
	eagleAccent = Color3.fromRGB(220, 170, 70),
	crowAccent = Color3.fromRGB(150, 120, 220),
	healthBarColor = Color3.fromRGB(90, 200, 110),
	staminaBarColor = Color3.fromRGB(90, 170, 230),
}

return GameConfig
