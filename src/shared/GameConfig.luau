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
-- WORLD SCALE / GRAVITY — the master recalibration knob (session 8, "real-scale raptor
-- flight"). See docs/RESEARCH.md §v3. The whole v2 lift/drag model was implicitly pinned to
-- Roblox's DEFAULT gravity 196.2 studs/s², which at the canonical 0.28 m/stud is ≈5.6× real g
-- — so dives accelerated too punchily and there was no altitude to develop a real stoop.
--
-- THE FIX (proven invariant): drop gravity toward real AND drop AIR_DENSITY by the SAME factor.
-- Then v_stall = √(g·wingLoading / (clMax·ρ)) has g and ρ CANCEL, so stall/cruise/dive/terminal
-- speeds — and the `stall < spawn < cruise` invariant — are preserved EXACTLY at any gravity.
-- Only the ACCELERATIONS get gentler (real-scale "majesty") and turns/dives get proportionately
-- bigger (hence the larger world + 2 km ceiling). The other gravity-coupled forces (flapThrust,
-- flapClimbForce, Thermals.strength) are multiplied by GRAV_SCALE below to hold their ratio to
-- weight. Everything scale-free (all speeds, control-authority speeds, every rad/s rate,
-- TERMINAL_VELOCITY, CRASH_SPEED) is UNCHANGED — so the player-approved v2 feel character
-- (grip, powered climb, momentum, eagle-wide/crow-tight) survives untouched.
--
-- GRAVITY_G is the ONE knob to sweep in playtest:
--   1.0 = true real g at 0.28 m/stud (gravity ≈ 35; most majestic / longest stoop)
--   2.0 = "arcade-real" (gravity ≈ 70, ≈2.8× gentler than the old 196.2) — current default
--   3.0+ = punchier / arcadier.  The envelope & invariant cannot break across the whole range.
--------------------------------------------------------------------------------
local METERS_PER_STUD = 0.28           -- Roblox canonical scale (2019 World panel)
local REAL_G          = 9.81           -- m/s²
local GRAVITY_G       = 1.3            -- fraction of real gravity — THE sweep knob (2.0->1.5->1.3: more loft + less climb-speed bleed, since the along-climb gravity decel scales with this)
local GRAVITY         = REAL_G * GRAVITY_G / METERS_PER_STUD  -- studs/s² (≈70.1 at GRAVITY_G=2)
local LEGACY_GRAVITY  = 196.2          -- the gravity the v2 feel was originally calibrated at
local GRAV_SCALE      = GRAVITY / LEGACY_GRAVITY              -- multiplies every gravity-coupled force
local function meters(m) return m / METERS_PER_STUD end      -- real metres → studs (world sizing)

GameConfig.MetersPerStud = METERS_PER_STUD -- exposed for any UI/debug that wants real-unit readouts

--------------------------------------------------------------------------------
-- GLOBAL FLIGHT ENVIRONMENT
--------------------------------------------------------------------------------
GameConfig.Flight = {
	GRAVITY = GRAVITY,          -- studs/s^2 (DERIVED from scale above). Set Workspace.Gravity to match (GameServer).
	GRAVITY_G = GRAVITY_G,      -- echoed for tooling/HUD; edit the local above to retune
	GRAV_SCALE = GRAV_SCALE,    -- echoed: factor applied to all gravity-coupled forces
	-- AIR_DENSITY is the abstract scalar that folds 0.5*rho*wingArea into the lift/drag terms.
	-- CALIBRATED for the v2 lift curve: with cl0~0.3 and these profiles, level cruise at each
	-- bird's glideSpeed trims at a few degrees AoA (lift ~= gravity), and stall speed sits well
	-- below spawn (0.9*glide) and cruise. See FlightPhysics.computeCL and the calibration note
	-- in project-open-questions. Raising it raises lift everywhere (lower stall speeds).
	-- v3: scaled by GRAV_SCALE in lockstep with gravity so stall/cruise/terminal speeds stay put
	-- (the g and ρ in v_stall cancel — see the WORLD SCALE block). The BASE (the 0.0xx literal) is the
	-- real loft lever: it sets lift-vs-weight independent of gravity, so raising it lowers stall speeds
	-- and gives more loft / readier climb. Raised 0.033 -> 0.044 (session: "need more loft / go up more
	-- readily"). Sweep GRAVITY_G for accel "punch"; edit THIS base for outright lift/loft.
	AIR_DENSITY = 0.044 * GRAV_SCALE,
	WIND_BASE = Vector3.new(0, 0, 0), -- ambient wind; per-map override allowed
	-- Control authority scales with airspeed: below MIN you can barely steer
	-- (this is what makes a stalled/slow bird helpless and gives speed meaning).
	CONTROL_AUTHORITY_MIN_SPEED = 20,  -- studs/s where control ~0
	CONTROL_AUTHORITY_FULL_SPEED = 90, -- studs/s where control is full
	-- Aerobatics (loop / barrel roll) unlock above this airspeed. NOTE (session: holistic redesign):
	-- with STABILITY_RATE = 0 the weathervane this gate suppresses is already inert, so this is now a
	-- near-cosmetic safety hook — the GRIP assist (not a weathervane) governs the nose at all speeds.
	-- Lowered 110->60 so it can NEVER fight a slow loop top: loop COMMIT is owned by the controller's
	-- ride-the-edge AoA protection (Controls.aimStallBandDeg) + powered-lift floor, not by this number.
	AEROBATIC_MIN_SPEED = 60,
	TERMINAL_VELOCITY = 400,
	-- STATIC AERODYNAMIC STABILITY (rad/s base): how fast the airframe weathervanes its
	-- ORIENTATION toward the airflow. This self-limits angle-of-attack (anti-stall) WITHOUT
	-- destroying lift — it rotates the nose toward the path, not the path toward the nose, so
	-- the v2 kernel keeps lift while the player's pitch input still dominates. Per-profile
	-- `stabilityRate` multiplies this; `recoverNoseDownRate` adds extra pull past the stall.
	-- (Replaces v1's PATH_TRACK_RATE, which rotated VELOCITY toward the nose and thus drove
	-- AoA->0->no-lift — the root cause of the old constant-stall spiral.)
	-- Auto-leveling weathervane: ELIMINATED (1.5 -> 0.7 -> 0.15 -> 0). Chad: "get rid of any
	-- auto-levelling... have the AoA not change unless input is given by the user." The grip
	-- assist below (velocity follows the nose) is what now keeps AoA low / prevents stall, so the
	-- nose is NEVER dragged back toward the airflow on its own — it stays exactly where the player
	-- points it. The per-profile recoverNoseDownRate (past-stall auto-recovery) is also zeroed so
	-- nothing rotates the nose without input. PLAYTEST-PROVISIONAL (re-add a whisper if low-speed
	-- handling needs a safety net).
	STABILITY_RATE = 0,
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
	-- v3 REAL-SCALE: golden eagles soar/migrate at 1350–2000 m AGL (PMC9179650); 2 km ≈ 7150 studs
	-- at 0.28 m/stud. The eagle owns this tall sky (vertical/energy game); crows top out lower
	-- (climbCeilingBonus 0.7 → ~5000). The apex is reached via the powered climb + thermals over
	-- several energy cycles, not in one flap — that grind IS the energy game.
	SERVICE_CEILING = meters(2000), -- ≈7143 studs; envelope top for climbCeilingBonus = 1.0 (the eagle)
	CEILING_BAND = meters(170),     -- ≈607 studs below the ceiling over which flap power fades to 0
	FLAP_AUTHORITY_FLOOR = 0.6, -- min control authority while flapping (lets you hold a slow climb without tumbling)
	FLAP_LIFT_FLOOR = 0.55,     -- fraction of clMax lift retained past stall WHILE FLAPPING (anti-mush)
	-- FLAPPING IN A DIVE: flap thrust stays a useful accelerator through low/mid dive speed but
	-- naturally fades at the top of a stoop (you can't beat your wings fast enough at speed) —
	-- gravity still carries the dive. Full thrust until (1 - FADE_BAND) of diveSpeedCap, then
	-- ramps down to FLAP_DIVE_FLOOR by the cap. Level/climb flapping is untouched (no regression).
	FLAP_DIVE_FADE_BAND = 0.4, -- top fraction of diveSpeedCap over which dive flap thrust fades out
	FLAP_DIVE_FLOOR     = 0.1, -- min dive flap thrust fraction retained at the very top end
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
		clMax = 1.95,           -- peak lift (raised 1.6->1.95: "need more lift authority" — climbs/turns harder before stall)
		postStallCl = 0.70,     -- lift retained past the stall (a recoverable mush, not a cliff)
		stallPadDeg = 6,        -- degrees beyond stallAngle over which lift rolls off
		parasiticDrag = 0.020,  -- low parasitic drag -> great glide/dive
		inducedDragK = 0.58,    -- induced-drag coefficient. CD_i = k·CL² so a hard pull bleeds energy ∝ load-factor²
		                        -- (RESEARCH §v4 drag polar — the principled EM cost). 0.85->0.65->0.58: the eagle is the
		                        -- ENERGY fighter and should RETAIN energy through a pull, but the n² cost is deliberately
		                        -- NOT removed — pitching still costs energy, just no longer "way too much".
		stallAngleDeg = 27,     -- critical AoA before lift rolls off (24->27: pull harder before it lets go)
		stabilityRate = 1.0,    -- weathervane strength multiplier (moot while STABILITY_RATE = 0)
		recoverNoseDownRate = 0, -- past-stall auto-recovery DISABLED (no auto-level; nose stays where pointed)

		-- THRUST / SPEED -----------------------------------------------------
		-- flapThrust must overcome cruise drag so the eagle can hold level flight instead of
		-- decaying into a stall. At 130 cruise, drag decel ≈ 41 studs/s²; old 380/mass≈32 was
		-- short, so level flight bled speed until it stalled. 520/12≈43 lets it sustain/slowly
		-- gain at cruise. It still trades altitude for top speed (energy fighter) — the dive,
		-- not the flap, is its speed source. PLAYTEST-PROVISIONAL.
		-- P2 (player ask 2026-06-30 "more power for flaps"): flapThrust 600->800, flapClimbForce 400->500.
		-- Flap power is the eagle's ENERGY ENGINE — more of it = faster re-acceleration after a turn/zoom =
		-- stronger boom-and-zoom (harder for crows to catch). Punch comes from THRUST, not lightness — mass is
		-- deliberately kept at 16 (momentum / energy-retention = the eagle identity). The 1-v-4 counter-levers
		-- live with the CROWS (numbers, possession, formation, collision trades) — Crow flap is NOT auto-scaled.
		-- (Option B — a wingbeat-phase "felt surge" per downstroke — is the juicy follow-up to prototype live;
		-- kept as continuous force here so it's safe to ship UNPLAYTESTED. Watch for porpoising if you add it.)
		flapThrust = 900 * GRAV_SCALE,       -- forward force from a flap (800->900: "flapping should make you go a lot faster" — 2026-06-30)
		flapClimbForce = 500 * GRAV_SCALE,   -- raised 400->500 (P2: "more power for flaps" -> stronger climb). Base was
		                        -- ABOVE gravity (196); ×GRAV_SCALE keeps it above the new (lower) gravity by the same
		                        -- ratio, so a flapping eagle keeps climbing even after a
		                        -- steep climb has bled its airspeed (lift ~0) — a real eagle muscles up
		                        -- on wingbeats, not airspeed. "Flap = climb" until stamina/ceiling. THE
		                        -- climb-rate knob; mass-independent so the momentum tuning doesn't sap it.
		-- FLAP ENERGY RETENTION (player ask 2026-06-30, "BF-109 energy retention"): fraction of the
		-- drag bleed cancelled while actively flapping in level/climb flight (see FlightPhysics drag
		-- block). 0.6 = the eagle keeps ~60% more of its energy under power, so it HOLDS/builds speed
		-- through a soft (~14°) climb instead of washing out — the energy-fighter identity, dialled up.
		-- Higher than the crow's on purpose (flight==balance). Stamina still drains, so climbs end from
		-- fatigue, not become free. PLAYTEST-PROVISIONAL.
		flapDragRetention = 0.6,
		-- ENERGY RETENTION (player ask 2026-06-30, "War Thunder ARCADE energy retention" — the TOP ask). The
		-- dominant speed-bleed in a CLIMB is gravity's component ALONG the flight path (GRAVITY·sinθ), NOT drag.
		-- This is the persistent, always-on (NOT flap-gated) arcade term that adds back this fraction of that
		-- along-path gravity decel WHILE CLIMBING (see FlightPhysics energy block) — so after a dive you can BOOM
		-- then ZOOM back near your start altitude if you don't hard-turn, a 30° climb bleeds speed slowly, and an
		-- ascending defensive spiral over a lower-energy target becomes flyable. 0.7 = the eagle keeps ~70% of the
		-- climb energy gravity would take. HIGHER than the crow (0.4) on purpose — the eagle IS the energy fighter;
		-- this asymmetry is the 1-v-4 lever. Capped <1 with a residual cost (never noclip); dives are untouched
		-- (only cancels while climbing). Stall/stamina/ceiling still bound it. PLAYTEST-PROVISIONAL.
		energyRetention = 0.7,
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
		-- P3 (player ask 2026-06-30 "more stamina for flapping" — a deliberate shift: longer LEASH, not just
		-- punch): budget widened again. 320 cap / 5 cost ≈ 64s of sustained full-throttle flapping (was 240/6
		-- ≈ 40s), regen 16. Stamina STAYS the limiter (boom-and-zoom identity survives): with P2's stronger
		-- flap this must end from fatigue or the ceiling, not become "free" power. Eagle-only — Crow stamina is
		-- a 1-v-4 lever left for the matchup pass. Suits the eagle's energy-fighter / endurance identity.
		maxStamina = 320,       -- raised 240->320 (P3 "more stamina"); flap throttle scales cost by effort so partial throttle lasts even longer
		staminaFlapCost = 5,    -- per second at FULL up-throttle (6->5: longer leash); scaled by |throttle| in FlightPhysics
		staminaDiveCost = 4,    -- per second of powered dive / down-throttle
		staminaRegen = 16,      -- per second when gliding (14->16: recovers a touch faster between climbs)
		climbCeilingBonus = 1.0,-- relative climb ceiling (eagle climbs higher)

		-- COMBAT / ENDURANCE -------------------------------------------------
		health = 99,            -- 3 clean "hits": the discrete combat model (GameConfig.Combat.eagleHits)
		                        -- makes one UNPARRIED crow ram cost health/eagleHits = 33, so exactly
		                        -- 3 rams down the eagle. HP bar retained (reads as 3 chunks).
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
		stabilityRate = 0.7,    -- weathervane multiplier (moot while STABILITY_RATE = 0)
		recoverNoseDownRate = 0, -- past-stall auto-recovery DISABLED (no auto-level)

		-- THRUST / SPEED -----------------------------------------------------
		flapThrust = 185 * GRAV_SCALE,       -- 150->185 (player ask 2026-06-30: crows should "maintain speed when climbing some" too — modest; level cap 140 < eagle 170 still protects the matchup)
		flapClimbForce = 200 * GRAV_SCALE,   -- lower than the eagle: the crow is less of a climber (lower ceiling via climbCeilingBonus)
		-- FLAP ENERGY RETENTION (see Eagle). LOWER (0.4 vs 0.6): the crow can hold speed through a gentle
		-- climb "some" (player ask) but the eagle stays the superior energy fighter — the crow's game is
		-- the tight turn + the ram, not out-running/out-climbing the eagle. flight==balance. PLAYTEST-PROVISIONAL.
		flapDragRetention = 0.4,
		-- ENERGY RETENTION (see Eagle). LOWER (0.4 vs 0.7): the crow holds SOME climb energy so a squad can
		-- reposition vertically, but the eagle stays the superior energy fighter — the crow can't out-zoom or
		-- sustain the ascending spiral, so its game remains the tight turn + the ram. flight==balance. PROVISIONAL.
		energyRetention = 0.4,
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
-- COMBAT — the asymmetric talon/beak ↔ suicide-ram model (HANDOFF session 11).
--------------------------------------------------------------------------------
-- The contract (see docs/HANDOFF.md + .loop/talon-beak-combat/state.md):
--  • Eagle survives `eagleHits` UNPARRIED crow rams; one ram = health/eagleHits damage.
--  • A Crow's only attack is the suicide ram: a committed eagle↔crow contact ALWAYS
--    kills the crow, and costs the eagle one hit UNLESS the eagle was covering that
--    contact zone with the right extended weapon (talons/beak). [zone/parry = iter 3]
--  • Eagle wins: all crows dead & eagle alive.  Crows win: eagle takes its 3rd hit
--    (≥1 crow survives).  Tie: the eagle's last hit and the last crow's death coincide.
GameConfig.Combat = {
	eagleHits = 3,   -- unparried crow rams the eagle survives (1 ram = health/eagleHits)

	-- DIRECTIONAL STRIKE (eagle only) — REWORKED 2026-06-30 (Chad): drop the left/right talon dichotomy. There
	-- are now just TWO zones, and the GAME auto-picks which strike a LEFT-CLICK throws by which zone the nearest
	-- enemy is in (the proximal reticle makes the strike — GameServer.enemyZone), each with its own
	-- startup→active duration→cooldown and a coverage cone:
	--   • TALON — a wide BELLY zone (cone around the bird's DOWN/-Up axis, so it SWINGS as you roll/bank — the
	--             talon arc reticle shows it). LONG active window, SHORT reset: the bread-and-butter grab when a
	--             crow is below / below-to-the-side. (Chad: ~4 s effective duration, ~2 s cooldown.)
	--   • BEAK  — a narrow FORWARD zone (cone around the nose; the beak/boresight reticle). SHORT active window,
	--             LONG reset: a committed head-on jab. (Chad: ~2 s duration, ~4 s cooldown.)
	-- During a strike's ACTIVE window (past startup) the zone's cone BOTH parries an incoming crow ram (crow
	-- dies, eagle unharmed — tryStrikeCatch) AND deals offensive damage to a crow inside the cone within reach
	-- (the eagle can HUNT). ONE catch-or-hit per window. The client mirrors the picked zone live
	-- (Body attr StrikeArmedDir "beak"/"talon"/"none") to LIGHT the matching reticle.
	--
	-- WHY THIS IS BALANCED (1-v-4 — preserve this reasoning): the eagle presents ONE zone at a time (belly OR
	-- nose) → it covers/strikes ONE angle per commitment → four crows from spread angles still win by
	-- SATURATION (the whole asymmetry). ⚠️ WATCH (flight==balance): the talon's LONG active window (4 s active /
	-- 2 s cd ≈ 67% uptime) flirts with the research >50% single-angle "always-on" guardrail. If 1-v-4 turns
	-- eagle-favored, cut the talon duration / widen its cooldown / drop the offensive damage (or zero the
	-- offensive pass → defense-only) FIRST. Server owns every timer + the zone pick (anti-cheat): the client
	-- sends only a fire EDGE, never a direction. ALL PLAYTEST-PROVISIONAL (durations/cooldowns are Chad's asks).
	bankStrikeThresholdDeg = 18,  -- LEGACY (no longer used; the strike zone is picked by enemy proximity, not bank)
	strikeSelectRange = 200,      -- studs; an enemy within this range drives the zone pick + reticle lighting
	strikes = {
		-- TALON: wide belly cone (swings with bank), long active window + short reset — the workhorse grab.
		talon = { startup = 0.10, duration = 4.0, cooldown = 2.0, axis = "belly",   coverHalfAngleDeg = 70, damage = "talon", reachFraction = 0.85 },
		-- BEAK: narrow forward cone, short active window + long reset — the committed head-on jab.
		beak  = { startup = 0.10, duration = 2.0, cooldown = 4.0, axis = "forward", coverHalfAngleDeg = 35, damage = "beak",  reachFraction = 0.85 },
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
		-- GOAL (eagle-chase) weight — the MOBBING lever. Previously the goal term silently
		-- reused cohesionWeight (1.0), so at close range separation (1.5×separationMul, up to
		-- 2.1 in loose) OVERPOWERED the eagle-chase and the crows scattered instead of swarming
		-- (playtest: "they get scared and fly away"). Set ABOVE separation so the 3 AI crows
		-- close in and pressure the eagle from multiple angles; separation still spreads them
		-- enough to surround rather than pile onto one point. Tune live: raise to mob tighter,
		-- lower toward 1.0 if they clump/collide. flight==balance: this is a 1-v-4 pressure knob.
		-- 2.0 with the orbit ON (Squad.mob.enabled). Must beat separation (up to 2.1 in loose) so the orbit
		-- RING binds the crows to the eagle instead of them drifting off; SAFE to be strong because the goal
		-- is the shell, not the eagle centre (strong = follow-the-ring, not ram). Raise toward 2.5 if they
		-- still "flock off"; lower toward 1.5 if they clump on the ring.
		-- (Prior note:) Now SAFE to raise (2.0) because the aggressive-squad goal is no longer the eagle's CENTRE — it's
		-- an ORBIT-SHELL station point (see Squad.mob + GameServer mobOrbitTarget). So goal-seek being
		-- strong makes crows FOLLOW THE SHELL / circle, not ram-and-crash. (Cranking it while the goal was
		-- the eagle centre is what made 3 crash — 4 birds on one vector. Research: mobbing≠flocking, crows
		-- are independent attackers that orbit+dive-bomb, cohesion DROPS. docs/RESEARCH-crow-mobbing.md.)
		goalWeight = 2.0,
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

	-- OBSTACLE AVOIDANCE (AI crows only — queue #8). A forward Spherecast look-ahead steers the
	-- bird around spires/ground so it stops attriting itself on terrain (which let bot waves
	-- crash before reaching the eagle). Applied ONLY in updateAICrows, so it never affects the
	-- player-controlled crow (Chad's rule: the crow you fly into the eagle gets NO avoidance).
	-- GENTLE avoidance (re-tuned 2026-06-30 after the strong version made bots FLEE the map — player: "the AI
	-- crows fly away from me… 18-20 km away; they should be mobbing me"). The real anti-suicide guarantee is
	-- the NON-LETHAL AI-crow terrain slide in updateAICrows (a bot can't die on a building), so avoidance only
	-- needs to be a light nudge that peels a crow off a wall it's about to graze — NOT a hard override that
	-- fights the eagle-chase and sends it veering off into open sky. Weight back to 3.0, shorter lookahead, and
	-- NO urgency floor (far-away terrain ⇒ ~0 avoidance), so the chase goal dominates and the swarm closes in.
	-- (The PLAYER-flown crow still gets no avoidance and real terrain crashes — Chad's rule.)
	avoidance = {
		lookaheadTime = 1.5,  -- s; look-ahead distance = speed * this
		minDistance   = 60,   -- studs floor on the probe distance
		maxDistance   = 350,  -- studs ceiling
		spherePad     = 10,   -- extra studs of body radius for a wider berth
		weight        = 3.0,  -- light nudge off imminent terrain — does NOT dominate the eagle-chase
	},

	-- AI FLIGHT GOVERNOR (all AI crows) — INCREMENT 0: make them FLY CONTROLLED before any mob geometry.
	-- Playtest diagnosis (2026-07-01): crows fly "too fast — blow past, can't turn tight", then "fine, then
	-- suddenly crash" into "terrain/spires AND the ground". Root cause: the boids input DIVES at the target
	-- (dir.Y < -0.4 → dive → accelerates to the 220 dive-cap), so turn radius (v/ω) balloons and they overshoot
	-- into terrain / sink into the ground on the pull-out. Fix = keep them near a controllable combat speed and
	-- OUT of dives (diving is the eagle's game, not the crow's mob), + a soft altitude floor so a hard bank
	-- doesn't sink them into the deck. Applied to every AI crow in updateAICrows AFTER steeringToInput.
	aiFlight = {
		enabled       = true,
		combatSpeedMul = 1.2,  -- target speed = Crow.glideSpeed × this (95×1.2≈114). Above it, stop flapping to
		                       -- bleed speed (parasitic drag) → tighter turns, no overshoot. Lower for tighter/slower.
		suppressDive  = true,  -- crows never DIVE in the mob (that's what builds the runaway overshoot speed).
		floorHeight   = 250,   -- studs; below this the crow is forced to climb (flap + nose up) so it can't sink
		                       -- into flat ground while banking. (Spires are handled by horizontal avoidance.)
		floorClimbPitch = 0.5, -- nose-up pitch applied under the floor (+ = climb, per steeringToInput sign).

		-- AI AUTOPILOT — bank limit + turn coordination (fixes "crash when chased, losing control").
		-- The flight engine has NO auto-level (the eagle's locked feel; crows inherit it), so when the
		-- player chases, a crow rolls hard to reverse, reaches knife-edge, loses vertical lift and falls.
		-- A human corrects this; the bot can't. This AI-ONLY assist caps the bank and adds up-elevator in
		-- the turn so it stays controllable. Does NOT touch the player's no-auto-level (AI loop only).
		autopilot     = true,
		maxBankCos    = 0.5,   -- cos(bank limit). 0.5 ≈ 60° max bank; below this uprightness, leveling takes over.
		levelAssist   = 3.0,   -- leveling roll gain (higher = snaps back to wings-level harder).
		turnPitchUp   = 0.5,   -- up-elevator added ∝ bank so a banked turn holds altitude (coordinated turn).
	},

	-- MOBBING (aggressive bot crows only) — the biologically-grounded 1-v-4 model, INCREMENT 1.
	-- Research (docs/RESEARCH-crow-mobbing.md): real corvids don't ram a raptor — they CIRCLE it
	-- ("flying about the intruder") at a standoff distance and make staggered dive-bomb passes. So
	-- instead of goal-seeking the eagle's CENTRE (4 birds → one vector → the pile-up/crash Chad saw),
	-- each crow seeks a point on an ORBIT SHELL around the eagle and circles it (GameServer.mobOrbitTarget
	-- feeds this as the boids goalPoint). Increment 2 will add the staggered dive-bomb + peel-off passes.
	mob = {
		enabled       = true,  -- Increment 1 orbit. ON now that AI flight control is fixed (governor +
		                       -- autopilot → crows fly controlled, dogfight well). This binds each crow to a
		                       -- standoff ring around the eagle so they MOB instead of "flocking off and going
		                       -- far away" (playtest 2026-07-01). Needs goalWeight raised (below) to beat
		                       -- separation. See docs/HANDOFF SESSION 14.
		orbitRadius   = 220,  -- studs; standoff shell radius the crows circle at (tune: smaller = tighter/more pressure, larger = safer)
		orbitHeightBias = 40, -- studs; sit slightly ABOVE the eagle (attack-from-above prep for the dive-bomb in increment 2)
		orbitLead     = 170,  -- studs; tangential lead point along the ring → how fast they circle (0 = just hold station)
		clumpSpread   = true, -- give each crow its own bearing/handedness so they surround from multiple angles, not stack
	},
}

--------------------------------------------------------------------------------
-- THERMALS — restore energy (altitude currency). Placed by GameServer.
--------------------------------------------------------------------------------
-- v3 REAL-SCALE: thermals are the energy elevator into the high soaring band (up near the 2 km
-- ceiling). Wider cores so they're findable in the much bigger sky; maxHeight raised to carry the
-- eagle into the stoop-launch altitude. strength ×GRAV_SCALE keeps its ~0.7g ratio (a thermal
-- reduces sink / gives a gentle climb when combined with gliding lift — it doesn't levitate you).
-- WATCH-ITEM (RESEARCH §v3): real thermal climb is slow; if reaching the apex is tedious in
-- playtest, raise strength above the scaled value as a gameplay concession.
GameConfig.Thermals = {
	count = 8,
	radius = meters(110),     -- ≈393 studs
	minHeight = meters(30),   -- ≈107 studs
	maxHeight = meters(1800), -- ≈6428 studs (carries you into the high soaring band below the 7143 ceiling)
	strength = 140 * GRAV_SCALE, -- upward accel at the core (studs/s^2), ratio-to-gravity preserved
}

--------------------------------------------------------------------------------
-- DEBUG — development aids. `soloFlight` lets ONE player spawn and fly for a smoke
-- test WITHOUT a full Eagle-vs-Crow match (no scored round; AI crows + possession
-- still run so a solo crow can exercise the squad). It transitions cleanly into a
-- real scored match the moment a second team joins. Set false for production.
-- (Consumed by GameServer.RoundLoop.)
--------------------------------------------------------------------------------
-- VISUAL — cosmetic-only knobs (no gameplay/balance effect).
GameConfig.Visual = {
	birdScale = 1.8,  -- VISUAL scale of bird models so they read at range. Collision + attack reach
	                  -- still use profile.bodyRadius, so this does NOT change combat distances/balance.
}

GameConfig.Debug = {
	soloFlight = true,
	-- aiCrowOpponents: when a lone HUMAN Eagle is present with no human Crow, spawn a fully
	-- AI-controlled crow squad that HUNTS and rams the eagle, respawning in fresh waves of
	-- `Squad.size` so a solo player can practice the talon/beak parry without a second human.
	-- The bots count for NOTHING in scoring (round logic still keys off human players); they
	-- exist only in the soloFlight branch and are cleared the moment a real match can be fielded.
	aiCrowOpponents = true,
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
	baseDistance = 40,
	mouseAimDistance = 135, -- STRICT FIXED chase distance while in mouse-aim mode (wheel zoom ignored there; pulled well back behind the bird — player ask)
	-- MOUSE-AIM CAMERA HEADING LAG (rad/s): how fast the aim camera's view catches up to the bird's heading. LOW
	-- lag = when you fling the cursor and the bird turns, the view DOESN'T snap around, so the world-anchored
	-- cursor hangs out on screen and the nose visibly LAGS behind and chases it (player ask). Higher = the view
	-- tracks the heading tighter (cursor re-centres sooner). Too low and the bird drifts to the frame edge in a
	-- long hard turn. Only used in mouse-aim mode; chase-only/free-look use chaseTurnRate.
	aimHeadingLag = 1.4,
	baseFOV = 70,
	diveFOV = 95,
	climbFOV = 62,
	speedDistanceFactor = 0.06,
	bankTiltFactor = 0.6,
	followSmoothing = 0.18,
	shakeAtSpeed = 200,
	shakeMagnitude = 0.6,
	-- Spacebar free-look: orbit the camera while the bird holds its flight path.
	-- Raised 0.35 -> 0.7 (player ask 2026-06-30: free-look "gets stuck"/feels limiting — want a crisp,
	-- near-1:1 War-Thunder-arcade pan). Drives both the mouse orbit (·0.01) and the arrow-key orbit (·2.5).
	freeLookSensitivity = 0.7,
	-- FREE-LOOK VERTICAL LIMIT (CS-2 REVISED, Chad 2026-06-30): the free-look camera is an UPRIGHT spherical
	-- orbit — horizon always level, operator never rolls or inverts ("stay upright, not sideways or upside
	-- down"). Yaw is a full 360°; pitch tilts up/down to this many degrees short of straight-up/straight-down
	-- (a SOFT STOP at vertical — it does NOT continue over the top to the far side). Keeping it just under 90°
	-- holds the view off the exact pole so CFrame.lookAt (hard world-up) never degenerates. Raise toward 90 for
	-- a steeper straight-down/up look, lower if the extreme ever jitters. (BirdController updateCamera.)
	freeLookPitchLimitDeg = 85,
	-- FREE-LOOK CRISPNESS (player ask 2026-06-30 "it feels like it gets stuck"). The orbit used to reuse the
	-- heavy chase followSmoothing (0.18 ≈ 16%/frame) → the view crawled after the mouse ("molasses"). When
	-- free-look is active the final camera lerp uses THIS smoothing instead → near-1:1 tracking. It's the single
	-- biggest "unstick" knob: higher = crisper (toward 1:1), lower = floatier. ~1.0 ≈ 63%/frame at 60fps.
	freeLookSmoothing = 1.0,
	-- RIGHT-CLICK = AWARENESS ZOOM (player asks 2026-06-30: "zoom right click is for looking outward… it should
	-- zoom to the centre of where I'm heading"; "the zoom right click cannot affect flying, it is for awareness
	-- only"; "the mouse wheel is for zooming in and out with reference to eagle"). Hold RMB to MAGNIFY the view
	-- centred on your heading: it narrows the FOV toward aimFOV and FADES the eagle locally (aimFadeBird) so its
	-- opaque body can't block the view. It does NOT move the camera or swing the look (that offset the zoom and
	-- fed back into flight) — the look stays heading-centred and steering is SUSPENDED while zooming, so it's
	-- purely awareness. Eagle-distance is the MOUSE WHEEL's job (zoomStep/userZoom), in chase AND free-look.
	aimFOV          = 22,   -- narrower FOV while zoomed (from baseFOV 70) — the magnification (lower = stronger zoom). ~3.2x at 22
	aimFadeBird     = 0.85, -- how transparent the eagle goes at full zoom (0 = opaque, 1 = invisible) so it can't block
	aimZoomLerp     = 0.22, -- per-frame ease of the zoom factor toward 0/1 (higher = snappier zoom)
	-- Mouse-wheel zoom: scroll adjusts a user offset folded into the chase distance.
	-- The final distance is clamped to [minDistance, maxDistance] so you can't clip
	-- into the bird or fly the camera off to infinity.
	zoomStep      = 24,  -- studs of distance change per wheel notch (bigger range -> bigger step)
	minDistance   = 10,  -- closest the chase cam may sit
	maxDistance   = 800, -- farthest the chase cam may pull back (raised 340->800: zoom way out for situational awareness)
	-- Camera HEIGHT vs zoom: the chase cam rides at `heightFactor × dist` above the bird up close,
	-- rising toward `zoomTopDownHeight × dist` as you wheel out — so zoomed out gives a higher,
	-- more top-down view of the eagle.
	heightFactor     = 0.35, -- base height ratio when zoomed in (a little above the bird)
	zoomTopDownHeight = 0.55, -- height ratio at full zoom-out (a touch more top-down, but a happy medium — angles stay close)
	-- Loop/crest damping: when the bird's facing rotates fast (e.g. cresting a loop), the chase
	-- cam softens its follow so the view glides through the flip instead of whipping. crestAngRate
	-- is the facing angular speed (rad/s) at which damping reaches full; crestDamp is the max
	-- fraction by which follow smoothing is reduced. Camera-only — never touches flight.
	crestAngRate = 3.0,  -- facing rotation rate (rad/s) at which crest damping reaches full (lower = damps earlier)
	crestDamp    = 0.85, -- max fraction the follow is softened at the crest (higher = smoother loop top)
	-- CAMERA UP = PARALLEL TRANSPORT along the flight-path direction (BirdController.updateCamera). It carries the
	-- up vector WITH THE CHASE DIRECTION, so a LOOP arcs over the top with no pole-flip while a barrel/snap ROLL
	-- (which barely moves the flight path) leaves the camera steady so you WATCH the bird roll (player ask
	-- 2026-06-30). A gentle self-level pulls the horizon back to world-level in ordinary flight, FADED OUT as the
	-- flight path goes vertical (a loop) so it can't yank the camera to the degenerate world reference over the top.
	horizonLevelRate = 2.0, -- per-sec relax of the camera horizon back to world-level (0 = never self-levels; higher = snappier)
	loopVertStart = 0.5,    -- flight-path verticality (|dir.Y|, ~30°) at which the horizon self-level BEGINS fading out
	loopVertBand  = 0.4,    -- verticality span over which self-level fades fully off (start+band = 0.9 ≈ 64°, before the pole)
	loopFollowUp = 0.0,     -- LEGACY / unused (superseded by parallel transport — the old cf.UpVector lean spun the camera in rolls)
	-- NO-SNAP CHASE (deep-research RESEARCH §v4, anti motion-sickness). The chase direction is a single
	-- CONTINUOUS full-3D vector (bird->camera), slewed toward "behind the bird's motion" at a CAPPED
	-- angular rate — NOT rebuilt from the bird's horizontal heading (which reverses ~180° over a loop top
	-- and SNAPS the camera, the old nausea bug). Combined with Roblox CFrame:Lerp (shortest-path quaternion
	-- slerp), a full 360° loop arcs smoothly with no azimuth snap and no over/under pole flip.
	chaseTurnRate   = 3.6,  -- rad/s cap on how fast the chase direction slews (>= the bird's loop rate so it keeps up, but smooths fast flicks). THE no-snap knob.
	lookAheadFactor = 0.3,  -- how much the chase blends toward the VELOCITY vector vs the nose (0 = pure nose, 1 = pure velocity); a little lead reads the flight path
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
	-- TIME-SCALED PITCH (keyboard W/S): a TAP gives a small, precise AoA nudge; HOLDING ramps the
	-- pitch authority up to full over pitchRampTime. Lets you make fine attitude adjustments without
	-- losing strong authority on a sustained climb/dive. Releasing snaps the input to 0 (the nose
	-- then holds where you pointed it — there's no auto-level). PLAYTEST-PROVISIONAL.
	pitchTapFraction = 0.30, -- pitch authority on the first instant a key is pressed (the "tap" amount)
	pitchRampTime    = 0.55, -- seconds of holding to ramp from the tap fraction up to full (1.0)

	-- BANKING / YAW SMOOTHING (keyboard A/D, Q/E): the same tap->ramp shape as pitch so a tap eases
	-- the bank in (refined) instead of slamming to full deflection ("all or nothing"). Tone-down lever.
	bankTapFraction = 0.22, -- roll/yaw authority on the first instant the key is pressed
	bankRampTime    = 0.50, -- seconds of holding to ramp from the tap fraction up to full

	-- MOUSE-AIM (the default flight control; NOT free-look). WAR THUNDER instructor model: two
	-- on-screen markers — a freely MOVEABLE CURSOR (your desired direction of flight) and a NOSE
	-- CROSS projected out front of the bird (its boresight / where it actually points). The bird
	-- steers so the nose cross is ALWAYS APPROACHING the cursor; the control error is the screen-space
	-- gap between them. Centre the cursor on the cross = fly straight. Hold the cursor at the screen
	-- EDGE and the gap is unreachable (the chase cam keeps the heading near centre) -> the command
	-- stays saturated -> a sustained FULL TURN or LOOP (uncapped — this is the key difference from the
	-- old attitude-command model, which capped at an attitude and could not loop). Eased (aimResponse)
	-- so it feels soft & flighty; keyboard is ADDITIVE (tighten a turn / hard dodge, dominates at full).
	-- Hold SPACE to free-look (suspends aim, mouse drives the camera). Loops need cruise speed (>110,
	-- Flight.AEROBATIC_MIN_SPEED) — a slow bird mushes instead of looping (Energy-Maneuverability).
	-- ALL PLAYTEST-PROVISIONAL.
	mouseAim     = true,
	-- VIRTUAL CURSOR (relative mouse, 2026-06-30). The mouse delta moves the cursor as a DEFLECTION FROM THE NOSE
	-- CROSS (so its reachable zone is centred on the nose — symmetric up/down). The CURSOR stays where you put it
	-- and drives the bird's nose toward it (Chad: "the cursor moves the bird aim, not the bird aim moving the mouse
	-- against me"). aimRecenterRate is a GENTLE relax of the deflection back toward the nose so a held deflection
	-- eventually STRAIGHTENS instead of turning forever — soft enough not to rubber-band/fight you. 0 = fully
	-- persistent cursor (no relax); HIGHER = straightens out sooner. aimMouseSensitivity scales the cursor travel.
	aimMouseSensitivity = 1.0,  -- overall gain on cursor swing per mouse unit (multiplies aimAnglePerPixel)
	-- NOSE-CHASES-CURSOR aim (BirdController.computeMouseAim): the CURSOR is a world direction you swing with the
	-- mouse out to a big cone (the reachable circle); it stays where you put it. The bird's NOSE (amber reticle,
	-- out front) chases it and the beak lands on it when it catches up. aimAnglePerPixel = the cursor swing SPEED;
	-- aimLeadScreenFrac/aimMaxLeadDeg = the reachable-circle SIZE (how far the cursor can lead the nose before it's
	-- clamped — bigger = a bigger circle you can pilot before the nose catches up). Command is body-relative to the
	-- nose (so cursor-on-nose = straight) and zoom-independent; the camera is also fixed in aim mode.
	aimAnglePerPixel    = 0.0035, -- radians the cursor swings per mouse unit (× aimMouseSensitivity) — lowered 0.006->0.0035 (cursor was too sensitive)
	aimLeadScreenFrac   = 0.95,  -- cursor-circle size: fraction of the way to the top/bottom edge the cursor can lead (0..1)
	aimMaxLeadDeg       = 70,    -- hard cap on the lead half-angle (deg); the FOV-derived value governs below it
	-- LEGACY / unused by the nose-chases-cursor model.
	aimCursorRadiusFrac = 0.9,   -- legacy
	aimRecenterRate     = 0.0,   -- legacy
	aimMarkerDistance = 600,  -- LEGACY (unused since the beak reticle was coupled to beakReticleDistance, 2026-06-30)
	-- BEAK + TALON RETICLES (melee-aim UI, reworked 2026-06-30 per Chad). The amber BEAK cross is the boresight
	-- AND the head-on strike marker: it's drawn at beakReticleDistance out front, and the aim ERROR is computed
	-- from the SAME point — that COUPLING is what makes "cursor centred on the cross == straight & level flight"
	-- (the old decoupled draw at 70 vs error at 600 dove at centre). Distance only moves the neutral cursor, not
	-- the per-pixel feel (the error is a screen-angle), so the loved gains carry. The TALON reticle is a
	-- hemispherical ARC of pips UNDER the bird (talonReticleDistance below, spanning ±talonArcSpreadDeg in the
	-- roll plane) that SWINGS as you bank. NO left/right any more — one beak zone, one talon zone; the server
	-- picks which a click throws by enemy proximity (StrikeArmedDir) and the matching reticle lights.
	beakReticleDistance = 90,   -- studs out front the beak cross sits (also the coupled aim-error reference)
	talonReticleDistance = 70,  -- studs below the belly the talon arc is drawn
	talonArcSpreadDeg = 60,     -- half-spread of the talon arc to either side of straight-down (in the roll plane)
	aimResponse  = 13.0,      -- per-sec ease of the APPLIED input toward target. RAISED 9->13: the PD damping
	                          -- below now does the smoothing, so the ease no longer has to add lag (lag = phase =
	                          -- the porpoise). Faster ease = crisper, less floaty; PD keeps it from overshooting.
	-- COORDINATED-FLIGHT INSTRUCTOR (War Thunder mouse-aim model; deep-research RESEARCH §v4). The cursor
	-- direction is resolved into the bird's BODY frame; the controller flies a REAL coordinated turn toward
	-- it — BANK + RUDDER together roll the lift vector onto the target, ELEVATOR pulls the nose through it.
	-- TWO research-grounded upgrades over the old pure-proportional law:
	--   (1) SYMMETRIC deadzone + EXPO on BOTH axes (WT "nonlinearity", documented 1.0–2.5): gentle near
	--       centre for fine aim, ramping to FULL authority at the edge — so a clean vertical LOOP still
	--       gets full pitch, and a slight sideways cursor no longer snaps into a hard bank.
	--   (2) PD (rate/derivative) DAMPING: subtract a term proportional to the bird's current body rate
	--       (FlightPhysics.pitchVel/rollVel). Pure-P over this inertial plant is underdamped -> the
	--       coordinated-turn porpoise; the rate feedback critically-damps it WITHOUT killing loop authority
	--       (at full deflection the P term saturates anyway; the damp only bites near equilibrium).
	-- LOOP COMMIT: the nose-up pull is NOT faded early. It rides to the stall edge and the protection only
	-- bites within aimStallBandDeg of stall — and is SUSPENDED entirely while powered (flap throttle up),
	-- since the wings keep lift past stall then (FLAP_LIFT_FLOOR). This is what lets a started loop finish.
	-- DEADZONE = a hair around dead-centre, just enough to settle straight (player ask 2026-06-30: "way less
	-- deadzone, full linearity"). EXPO = 1.0 → the command is LINEAR in cursor offset (no easing), so the bird
	-- answers the mouse 1:1 right off centre. Equal on both axes (round neutral). PLAYTEST-PROVISIONAL: if the
	-- nose jitters / won't settle to straight at centre, nudge the deadzones up a hair (→ 0.012).
	aimPitchDeadzone = 0.006, -- PITCH deadzone: way smaller — almost no neutral zone
	-- EXPO — response curve of command vs how far the target LEADS the nose. 2.0 (a hard parabola) made the final
	-- approach CRAWL: as the nose neared the cursor the command fell off ∝ offset² and closed too slowly (Chad:
	-- "the reticle is slow to get to the cursor when close"). Dropped to 1.2 (near-linear) so the command stays
	-- strong through the close and the nose shuts the gap at the bird's FLIGHT-MODEL turn/pitch/yaw rate
	-- (FlightPhysics rate-limits it — so closing speed = the bird's agility, as asked). A hair above 1.0 keeps a
	-- little softness at dead-centre so straight flight isn't twitchy. Sweep 1.0 (crisp/linear)..1.6 (softer).
	aimPitchExpo     = 1.0,   -- PITCH ramp: LINEAR (1.2->1.0) so small movements aren't suppressed — snappy short catch-up
	aimBankDeadzone  = 0.006, -- BANK/YAW deadzone: matched to pitch (small round neutral)
	aimBankExpo      = 1.0,   -- BANK/YAW ramp: LINEAR, matched to pitch
	-- OUTER cursor bound: the aim reticle is CLAMPED to a circle CENTRED on the screen that covers this
	-- fraction of the screen AREA (0.5 = HALF the screen — player ask 2026-06-30, tightened 7/8 → 3/4 → 1/2).
	-- Past the rim the command just stays saturated (full turn/loop). radius = sqrt(areaFrac · W · H / π);
	-- BirdController.computeMouseAim does the clamp. Smaller = a tighter cursor circle. PLAYTEST-PROVISIONAL.
	aimCursorAreaFrac = 0.5,
	-- Gains RAISED (player ask: "reticle catch-up snappy at short movements, rate-limited by the eagle's turn rate
	-- at big deflections"). Higher gain SATURATES the command for anything but a tiny error, so the bird turns at
	-- its MAX rate to close small/medium gaps fast (snappy), while big gaps still take the eagle's turn rate to
	-- sweep (rate-limited). Tiny errors stay sub-saturation for fine aim. PD damps the overshoot the gain adds.
	aimRollGain      = 4.5,   -- bank-to-turn strength (2.6->4.5: snappier catch-up)
	aimPitchGain     = 5.0,   -- elevator: pulls the nose toward the target (3.3->5.0: snappier; full deflection still saturates -> loop)
	aimYawGain       = 1.0,   -- rudder, coordinated WITH the bank (0.78->1.0: scaled with the gain bump)
	aimLevelGain     = 0.9,   -- wings-levelling toward straight flight when there's no bank demand (anti stuck-in-bank)
	aimPitchDamp     = 0.45,  -- PD: nose-pitch-rate feedback (0.35->0.45: control the higher-gain overshoot)
	aimRollDamp      = 0.40,  -- PD: roll-rate feedback (0.30->0.40: control the higher-gain overshoot)
	aimStallBandDeg  = 4,     -- degrees below stall where the nose-up PULL eases (4, narrow: ride the edge -> loop commits)
	invertPitch      = false, -- false = cursor ABOVE the nose pitches UP (the cross rises to meet it)

	-- FLAP THROTTLE (sticky, NOT momentary): hold SHIFT to ramp UP-thrust (climb), CTRL to ramp DOWN-thrust
	-- (powered descent). It HOLDS where you set it so you can set a climb power and then fly a hands-free
	-- defensive climbing spiral on the mouse (War Thunder feel). 0 = glide (stamina regen). The HUD shows
	-- the resulting flap frequency + power-per-stroke. Feeds FlightPhysics via input.flapThrottle, which
	-- scales flap thrust / climb force / dive thrust / stamina cost / wingbeat frequency by the effort.
	flapThrottleRate = 1.1,   -- units/sec the throttle ramps while Shift/Ctrl held (full -1..1 sweep in ~1.8s)
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
