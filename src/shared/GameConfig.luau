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
	TERMINAL_VELOCITY = 420,  -- RAISED 400→420 (Chad 2026-07-02): this is the FLAP-achievable top speed. In
	                          -- FlightPhysics the non-diving hardCap = TERMINAL, and the glide-bleed-to-maxLevelSpeed
	                          -- is SKIPPED while flapping — so flapping out of a dive holds/boosts speed up to TERMINAL
	                          -- ("once the attitude is reached, the flap boosts"). 420 = the true top speed via flapping;
	                          -- a pure dive tops lower at Eagle.diveSpeedCap=390. (Anti-cheat ceiling scales with this,
	                          -- so the legit 420 stays inside the envelope. Crow can't approach it — flapThrust far lower.)
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
		-- ascending defensive spiral over a lower-energy target becomes flyable. 0.82 = the eagle keeps ~82% of the
		-- climb energy gravity would take (RAISED 0.7→0.82, Chad 2026-07-02: "I lose energy so fast if I zoom up —
		-- need more retention"). HIGHER than the crow (0.4) on purpose — the eagle IS the energy fighter; this
		-- asymmetry is the 1-v-4 lever. Capped <0.95 with a residual cost (never noclip); dives are untouched (only
		-- cancels while climbing). Stall/stamina/ceiling still bound it. PLAYTEST-PROVISIONAL.
		energyRetention = 0.82,
		-- GLIDE COAST (Chad 2026-07-02: "going to glide mode, keep my speed a LOT longer if I'm not turning or
		-- climbing, just staying aerodynamic"). Per-sec exponential decay of speed ABOVE cruise (maxLevelSpeed)
		-- while gliding hands-off — see FlightPhysics speed-cap block. This (NOT drag) was the dominant bleed:
		-- at the old hard-coded 0.5, a 420 eagle shed ~125 studs/s² and dropped to 250 in ~2 s. 0.15 = the excess
		-- decays ~3.3× slower, so an aerodynamic eagle COASTS (420→250 now ~7-8 s) — the boom-and-zoom holds its
		-- energy. LOWER = holds speed even longer (0 = never bleeds below terminal). Higher than crow's on purpose
		-- (energy-fighter identity, flight==balance). Stall/turn/climb still cost energy normally. PLAYTEST-PROVISIONAL.
		glideBleed = 0.15,
		glideSpeed = 130,       -- comfortable cruise (high)
		maxLevelSpeed = 170,
		diveThrustBonus = 1.6,  -- thrust multiplier while diving (gravity also assists)
		diveSpeedCap = 390,     -- RAISED 320→390 (Chad 2026-07-02): a pure dive now tops ~390 (was 320). Flapping OUT
		                        -- of the dive can push past it to TERMINAL_VELOCITY=420 (the true top). Crows (diveSpeedCap
		                        -- 220) still can't match it — the eagle's energy/dive dominance IS the 1-v-4 identity.

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
		beakDamage = 26,        -- close peck. RAISED 22→26 (S17): crow health is 25, so the old 22 could NOT
		                        -- kill a crow in one clean beak jab (left it at 3 HP) — that was the core of Chad's
		                        -- "I'm hitting them with the beak but they don't die." A committed head-on beak
		                        -- (narrow 35° cone, short 2s window, long 4s cd) now one-shots a crow like the talon
		                        -- does; the 1-v-4 balance stays in the saturation (one zone at a time), not in the
		                        -- beak being sub-lethal. flight==balance: still < talon; dial back toward 25 if too strong.
		talonDamage = 34,       -- grab/strike, the bread-and-butter eagle kill (one-shots a 25 HP crow)
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
		-- GLIDE COAST (see Eagle). Kept at the OLD default 0.5 (vs the eagle's 0.15): the crow's cruise stays
		-- tight — it does NOT coast far above its 140 level cap, so it can't hold a boom-and-zoom speed like the
		-- eagle. Structural symmetry + the eagle's coast advantage is a flight==balance lever. PLAYTEST-PROVISIONAL.
		glideBleed = 0.5,
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
	-- ⚠️ STRIKE REACH (S17): the offensive hunt reach was `(rEagle+rMax+ATTACK_BUFFER)*reachFraction` ≈
	-- (4.5+4.5+3)*0.85 ≈ 10.2 studs — barely past the 6.7-stud TOUCHING distance, i.e. you had to nearly
	-- collide to land a strike. Meanwhile the ARMED reticle lights at strikeSelectRange (200 studs), so a
	-- crow read as "on target" from 20× outside actual hit range → Chad: "pretty sure I'm hitting them but
	-- they don't die." Each strike now carries an explicit `reachStuds` (a believable swoop-and-strike range);
	-- if set it OVERRIDES the point-blank formula (GameServer.updateEagleStrikes). Cones/timers UNCHANGED, so
	-- the 1-v-4 saturation balance holds (one zone at a time, one hit per window). flight==balance: this is the
	-- eagle's EARNED hunt reach; if it turns eagle-favored, drop reachStuds / beakDamage / talon uptime FIRST.
	strikes = {
		-- TALON: wide belly cone (swings with bank), long active window + short reset — the workhorse grab.
		-- reachStuds kept CONSERVATIVE (24): the talon already one-shots + has a 70° cone at ~67% uptime, so a
		-- big reach here would be a death-ray (red-team #2). 24 is still a huge lift from the old ~10.2 point-blank.
		talon = { startup = 0.10, duration = 4.0, cooldown = 2.0, axis = "belly",   coverHalfAngleDeg = 70, damage = "talon", reachFraction = 0.85, reachStuds = 24 },
		-- BEAK: narrow forward cone, short active window + long reset — the committed head-on jab. Slightly LONGER
		-- reach (28) than the talon: the narrow 35° cone + short 2s window make it hard to land, so a committed
		-- head-on jab needs the range to actually connect — this is the strike Chad struggled with most.
		beak  = { startup = 0.10, duration = 2.0, cooldown = 4.0, axis = "forward", coverHalfAngleDeg = 35, damage = "beak",  reachFraction = 0.85, reachStuds = 28 },
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
		combatSpeedMul = 1.35, -- orbit/cruise speed cap = Crow.glideSpeed × this (95×1.35≈128). Above it, stop
		                       -- flapping to bleed (parasitic drag) → tighter turns, no overshoot.
		                       -- RAISED 1.05→1.35 (S19): the S18 cut to ~100 was the WRONG direction — the eagle cruises
		                       -- 130 (max 170), so crows at 100 could never stay with it → "mice and cat, I chase them."
		                       -- ~128 (just under the eagle's cruise + the crow's own 140 maxLevelSpeed cap) lets them
		                       -- press and stay on the eagle. Holdable on the 150 ring now that the bank cap is 72°:
		                       -- required bank atan(128²/(150·45.6))≈67° < 72° cap (≈5° margin). The crow's real edge is
		                       -- the TURN (2.1 rad/s) + dive, not level speed (it can't out-run the eagle) — so this keeps
		                       -- it close enough to convert to a turning/dive fight. ⚠️ if they still can't keep up when
		                       -- you run, the lever is a faster dive-bomb pass (raise Crow.maxLevelSpeed), not more cruise.
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
		maxBankCos    = 0.40,  -- cos(bank limit). 0.40 ≈ 66° max bank; below this uprightness, leveling takes over.
		                       -- RAISED 0.5→0.40 (60°→66°) S19: the 60° cap was THROTTLING the crow's designed turn
		                       -- advantage (Crow.sustainedTurnRate 2.1 rad/s vs Eagle 1.0) → on perturbation they hit the
		                       -- cap and understeered OUTWARD ("flock off / won't mob"). 66° lets them carve the turn WITH
		                       -- the eagle. Paired with orbitRadius 180 so the ring's required bank (~63° at v≈128) sits
		                       -- UNDER 66° with the S14 knife-edge safety margin mostly intact (66°→90° = 24° vs 72° = 18°).
		                       -- ⚠️ this is the exact cap that guards the S14 falling-crash (roll-past-vertical when chased);
		                       -- if that recurs, DON'T just lower the cap (66° < the 63° the ring needs → they spiral out) —
		                       -- WIDEN orbitRadius instead so a lower bank holds. Chad OK'd "a couple crashed" if they mob.
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
		orbitRadius   = 180,  -- studs; standoff shell radius the crows circle at (BETWEEN dive-bomb passes). 220 (orig)
		                      -- stood off too far ("flying away"); 150 (S18) was un-holdable — the required bank exceeded
		                      -- the cap and they spiraled out. 180 is the red-team sweet spot: at the keep-up speed v≈128
		                      -- the required bank is atan(128²/(180·45.6))≈63° < the 66° cap (maxBankCos 0.40) WITH the S14
		                      -- knife-edge margin mostly restored. ⚠️ COUPLED: orbitRadius, combatSpeedMul (128) and
		                      -- maxBankCos (66°) move together — holdable iff v ≤ √(tan(bankCap)·g·R). To bring the ring
		                      -- CLOSER, first widen the bank cap or slow them, or they understeer OUT again. NOTE: the
		                      -- "in your face" pressure is meant to come from the frequent dive-bomb PASSES, not a tight ring.
		orbitHeightBias = 40, -- studs; sit slightly ABOVE the eagle (attack-from-above prep for the dive-bomb in increment 2)
		orbitLead     = 60,   -- studs; tangential lead point along the ring → how fast they circle (0 = just hold station).
		                      -- LOWERED to 60 (S19): with the ring close (150) and the eagle moving, a big lead demanded
		                      -- excess bank on top of just following him; 60 = they hold close station + gently circle
		                      -- (surround/harass) rather than race around the ring and sling outward.
		-- MOB STEERING PROFILE (S24 — the scatter fix, hypothesis pending playtest confirmation).
		-- Research (docs/RESEARCH-crow-mobbing.md): mobbing ≠ flocking — real corvids switch to
		-- METRIC/independent-attacker mode; cohesion DROPS. That reframe was wired into the goal GEOMETRY
		-- (orbit shell) but NOT the steering blend: mobbing crows still ran full alignment(1.0)+cohesion(0.8).
		-- The bot wave spawns 12 studs apart and each stations at its OWN bearing, so the squad rings one
		-- narrow sector (separation spreads them only to ~the 60-stud perception edge ≈ 19° of a 180 ring) —
		-- "surround from multiple angles" never happened. And whenever the dive-bomb scheduler sends a crow
		-- OUT (peel target beyond the ring) or the eagle runs, alignment/cohesion (up to ~1.8 combined) drag
		-- the others along vs goalWeight 2.0 — the leading suspect for the 5-playtest "they scatter and fly
		-- away" (code-verified mechanism; that it's THE cause is confirmed only by Chad's next Play). This
		-- table is passed as the boids formationCfg while mobbing (updateAICrows): alignment/cohesion OFF
		-- (independent attackers), separation kept high (research-verified). Bearings should diffuse as passes
		-- and peels re-ring crows at new bearings with nothing re-syncing them — but the TIMESCALE is unproven;
		-- if playtest still shows one-sector attacks, the pre-registered fallback is explicit per-crow bearing
		-- offsets in mobOrbitTarget (the surgical version of what the old flag promised). AI-only; player
		-- squads keep their tight/loose formation blend. (Replaces `clumpSpread`, which NO code ever read.)
		-- ⚠️ S25 SUPERSEDES this as the PRIMARY scatter cause: steeringToInput's horizontal channels were
		-- SIGN-INVERTED (Boids.luau S25 note) — crows stably flew AWAY from every goal, so they never sat on
		-- the ring long enough for this flock-drift mechanism to be the driver. Keep this profile anyway: it
		-- is the research-correct mob blend (independent attackers), just demoted from "root cause" to
		-- "secondary/contributing." Set `steering = nil` to A/B the old flocking blend in isolation.
		steering = { spacing = 30, cohesionMul = 0, alignmentMul = 0, separationMul = 1.4 },

		-- INCREMENT 2 — STAGGERED DIVE-BOMB + PEEL-OFF (the mob's first TEETH).
		-- Research (docs/RESEARCH-crow-mobbing.md): real corvids don't sit on the ring — they take
		-- TURNS committing a fast pass THROUGH the raptor, throw the pass, then PEEL OFF to recover,
		-- never all-at-once (all-4-on-one-vector = the pile-up). Structurally: ONE crow attacks at a
		-- time (squad-level round-robin in GameServer.updateAICrows), the rest hold the standoff ring.
		-- On a committed pass the attacker aims at the eagle CENTRE and gets a raised speed cap
		-- (attackSpeedMul) so it actually reaches ram range; contact = the crow's sacrifice ram (eagle
		-- takes health/eagleHits), a miss = the eagle read/dodged it. Then it PEELS out+up to recover.
		-- AI-only; the player-possessed crow is never scheduled or overridden.
		-- NOTE (do NOT overclaim): this is the mob's TEETH + a CONTROLLED close-then-break replacing the
		-- constant passive drift-into-contact. It is NOT by itself an "attrition fix" — AI-crow waves
		-- respawn only when ALL are dead, and a landed pass is a deliberate sacrifice, so crows still
		-- trade themselves. Whether "attrites to ~1" is a bug or the intended sacrifice dynamic is a
		-- Chad design call (open question in the s16 playtest). flight==balance: this is timed pressure
		-- the eagle can read and beat, not a swarm pile-up. Flip `enabled=false` to fall back to pure orbit.
		-- ⚠️ CADENCE (REVISED S19 — the "mice/cat" strategy pivot): the old rule was "one attacker at a
		--    time" (attackDuration+peelDuration ≤ attackPeriod), which made a lone pass every 3.4s while 3
		--    crows circled — so the DOMINANT behavior was orbit-circling, which reads as EVASION ("they flock
		--    off, I chase them like mice"), not mobbing. Now attackPeriod is SHORT so a new attacker launches
		--    before the last finishes → ~1-2 crows are ALWAYS diving at the eagle, from DIFFERENT ring bearings
		--    (round-robin + the mob steering profile's pass-through bearing diffusion) → constant harassment =
		--    the mob FEEL. This is NOT the old pile-up
		--    (that was all-4 on ONE vector at uncontrolled speed); it's ≤2 controlled attackers from spread
		--    angles, separation keeping them apart. Concurrent-attacker count ≈ attackDuration/attackPeriod.
		--    ⚠️ don't push attackPeriod so low that 3-4 pile on at once — keep it ≥ ~1.0. flight==balance: more
		--    passes = more ram pressure on the eagle (each landed ram = health/eagleHits); raise attackPeriod
		--    if the 1-v-4 turns crow-favored, lower it toward mob harder.
		diveBomb = {
			enabled       = true,
			attackPeriod  = 1.4,  -- s between attack LAUNCHES. SHORT (was 3.4) so ~1 crow is always mid-dive + often a
			                      -- 2nd = the eagle is under near-continuous harassment from spread angles. See cadence note.
			attackDuration = 1.6, -- s the attacker commits toward the eagle (closes the standoff for the pass)
			peelDuration  = 1.4,  -- s the attacker breaks away+climbs to recover before rejoining the ring
			attackSpeedMul = 1.8, -- LIFTS the AI governor's cruise cap during the pass so the attacker flies as fast
			                      -- as the KERNEL allows and reaches ram range (vs the ~100 orbit cruise). ⚠️ It does NOT
			                      -- reach 95×1.8≈171: the attacker keeps suppressDive ON, so FlightPhysics clamps a
			                      -- non-diving crow at Crow.maxLevelSpeed=140. So the real pass tops ~140 studs/s — still
			                      -- easily crosses the tightened 150 orbit to contact. Anything above 1.47 (140/95) is a
			                      -- no-op here; to make the pass genuinely faster you'd raise Crow.maxLevelSpeed (a balance
			                      -- change — don't do it silently).
			peelRadiusMul = 1.15, -- peel-off aims back OUT to orbitRadius × this (beyond the ring) so it clears the eagle.
			                      -- LOWERED 1.6→1.15 (S18): 1.6 (×220 ≈ 352 studs) flung the attacker FAR out+up after
			                      -- every pass → read as "fleeing." 1.15 (×150 ≈ 172) just clears the ring so it re-engages.
			peelHeightBias = 50,  -- studs; climb this much above the eagle on the peel (regain attack-from-above E). LOWERED
			                      -- 120→50 (S18) so the peel is a tight re-engage, not a long flight up-and-away.
			-- suppressDive stays ON even during the pass for the first playtest (a controlled fast closure, not a
			-- stoop) so we don't reintroduce the dive-into-terrain overshoot; revisit once cadence feels right.
		},
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
	speedAllowMult = 1.25,    -- => ~525 studs/s sustained ceiling at TERMINAL 420 (legit flap-top 420 stays inside)
	teleportMult = 1.5,       -- per-frame teleport gate = TERMINAL × this (~630); single-frame jump
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
	mouseAimDistance = 230, -- STRICT FIXED chase distance while in mouse-aim mode (wheel zoom ignored there; pulled well
	                        -- back behind the bird — player ask). 135→200→230 (S26, Chad live-tuned: "zoom back ~50%…
	                        -- back up to 230, a little more — I need to see more around me in the turn"; 200 was
	                        -- "a lot better"). Revert toward 135 if the eagle reads too small to fly.
	-- MOUSE-AIM CAMERA HEADING LAG (rad/s): how fast the aim camera's view catches up to the bird's heading. LOW
	-- lag = when you fling the cursor and the bird turns, the view DOESN'T snap around, so the world-anchored
	-- cursor hangs out on screen and the nose visibly LAGS behind and chases it. Higher = the view
	-- tracks the heading tighter (cursor re-centres sooner). Too low and the bird drifts to the frame edge in a
	-- long hard turn. Only used in mouse-aim mode; chase-only/free-look use chaseTurnRate.
	-- ⚠️ PREFERENCE REVISED (Chad, for the record, 2026-07-02 S26c): "I don't like the aim heading lag —
	-- that is NOT my preference, I wanted it tighter… the reticle should snap tighter to the cursor."
	-- 1.4→2.6→4.0 (lag time-constant ~0.71s→0.38s→0.25s). S26d: 2.6 was good but mouse-aim COMBINED with
	-- full-deflection keystrokes still wanted more turn authority (the laggy view read as sluggish
	-- response during combo flying) → 4.0 per Chad. The old "cursor hangs out" framing is no longer a
	-- loved feature to protect — tighter tracking also reduces how far the cursor circle drifts in hard
	-- turns (it and the restored screen clamp are in tension — see Controls.aimCursorAreaFrac).
	aimHeadingLag = 4.0,
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
	aimAnglePerPixel    = 0.0024, -- radians the cursor swings per mouse unit (× aimMouseSensitivity). 0.006->0.0035->0.0024
	                              -- (S27b, Chad: "cursor movement is too sensitive" — kept as a standalone sensitivity ask;
	                              -- it's orthogonal to the coordination rework). Too sluggish now? back toward 0.003.
	aimLeadScreenFrac   = 0.95,  -- cursor-circle size: fraction of the way to the top/bottom edge the cursor can lead (0..1).
	                             -- ⚠️ S26 REVERTED 0.625→0.95 after Chad's play: shrinking this cone does NOT shrink the
	                             -- on-screen circle he sees (the cone follows the NOSE, which the lagging aim camera puts
	                             -- off-centre mid-turn) and it made the rubber-band WORSE (the nose catches the cursor ~40%
	                             -- faster → the sustained-turn deflection decays in pulses: "intermittent pulling, I have
	                             -- to keep moving the mouse"). The real fix for his centred-5/8-circle + sustained-edge-
	                             -- deflection ask is a MODEL question (screen-anchored stick vs world-anchored chase) —
	                             -- CS-8 territory, Chad's call (2026-07-02: he chose KEEP the model). Do NOT re-shrink
	                             -- this value to chase the circle size — the circle is bounded by aimCursorAreaFrac
	                             -- (camera-relative, restored S26), which ALSO caps sustained-turn lead — see its note.
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
	-- OUTER cursor bound: the cursor is CLAMPED so its projection never leaves a circle CENTRED on the
	-- screen covering this fraction of the screen AREA. radius = sqrt(areaFrac · W · H / π); the clamp is
	-- CAMERA-relative in computeMouseAim, so it holds even mid-turn when the lagging aim camera puts the
	-- nose (and its lead cone) off-centre. Past the rim the command just stays saturated (full turn/loop).
	-- ⚠️ S26 (2026-07-02): this knob had been silently UNREAD since the 2026-06-30 nose-chases-cursor
	-- rewrite (the old screen clamp was dropped — why the cursor roamed to the edges/corners again).
	-- RESTORED as the camera-relative clamp. S26c: back to 0.5 ("a little smaller" — 0.625 still hit the
	-- flat top of the screen) AND the code now hard-caps the radius to fit INSIDE the screen (round rim
	-- everywhere — the flat-edge rim made turn direction uncontrollable). On 16:9 the fit-inside cap
	-- binds (≈ half-height − 48px), so to shrink the circle further drop this below ~0.38; raising it
	-- past ~0.44 has no effect. PLAYTEST-PROVISIONAL.
	aimCursorAreaFrac = 0.5,
	-- Gains RAISED (player ask: "reticle catch-up snappy at short movements, rate-limited by the eagle's turn rate
	-- at big deflections"). Higher gain SATURATES the command for anything but a tiny error, so the bird turns at
	-- its MAX rate to close small/medium gaps fast (snappy), while big gaps still take the eagle's turn rate to
	-- sweep (rate-limited). Tiny errors stay sub-saturation for fine aim. PD damps the overshoot the gain adds.
	-- SNAPPIER (Chad 2026-07-02): "at close range it lags; small deflections should SNAP to the cursor in a
	-- fraction of a second — only a LARGE deflection has noticeable reticle catch-up." Raised the P-gains so the
	-- command saturates at a SMALLER error → the nose closes small/medium gaps at the eagle's max turn rate (a
	-- small angle at max rate = a fraction of a second = "snap"), while a big deflection still needs the full
	-- turn-rate sweep to catch up (the intended lag). Damping raised in step so the faster response doesn't ring.
	aimRollGain      = 7.5,   -- bank-to-turn strength (4.5->6.5->7.5: S26c "faster reticle catch-up, snap tighter")
	aimPitchGain     = 8.2,   -- elevator: pulls the nose toward the target (5.0->7.2->8.2: S26c snap; full deflection still saturates -> loop)
	aimYawGain       = 1.55,  -- rudder, coordinated WITH the bank (scaled with the gain bumps)
	aimLevelGain     = 0.9,   -- wings-levelling toward straight flight when there's no bank demand (anti stuck-in-bank)
	aimPitchDamp     = 0.64,  -- PD: nose-pitch-rate feedback (0.58->0.64: raised in ratio with the S26c gain bump)
	                          -- ⚠️ S27b tried 0.80 to fight reticle overshoot — REVERTED: didn't fix the horizontal
	                          -- sail-past (that's a coordination problem, not a damping one) and added arrival lag. The
	                          -- real fix is the coordinated-flight instructor rework — see HANDOFF S28 research directive.
	aimRollDamp      = 0.58,  -- PD: roll-rate feedback (0.52->0.58: raised in ratio with the S26c gain bump)
	                          -- ⚠️ S27b tried 0.72 + S27c added a derivative-on-error "aimHorizLeadDamp" — BOTH REVERTED:
	                          -- the derivative term amplified mouse jitter (small-input reticle "jumping around", Chad) and
	                          -- neither killed the horizontal sail-past. Root cause is that the instructor is 3 independent
	                          -- per-axis PD servos, NOT a coordinated-turn law — see the HANDOFF S28 research directive.
	aimStallBandDeg  = 7,     -- degrees below stall where the nose-up PULL eases. 4→7 (S26f, Chad: slow-turn porpoise
	                          -- "still oscillates a little"): the narrow 4° band gated the pull on/off almost bang-bang
	                          -- as AoA crossed it in a slow turn — 7° makes the ease gradual, killing the limit-cycle.
	                          -- Loop commit is protected by the POWERED bypass (flap throttle up ⇒ full pull past stall),
	                          -- so a powered loop still always commits; only unpowered near-stall pulls get gentler.
	-- LOW-SPEED INSTRUCTOR STABILITY (S26e — Chad: up/down oscillation in slow sustained turns). The aim
	-- pitch P-gain is scaled by airspeed/(glideSpeed·aimSpeedGainRef), clamped to [aimLowSpeedGainFloor, 1].
	-- At/above glide speed the feel is EXACTLY the tuned snap (scale = 1); below it the pull softens while
	-- the D-damping stays constant → relatively better damped → the slow turn sustains instead of pumping.
	-- Oscillates still: lower the floor toward 0.35 or widen aimStallBandDeg toward 7 (the stall-guard
	-- gating the pull on/off across its narrow 4° band is the other half of the porpoise mechanism).
	-- Slow turns feel too weak/mushy: raise the floor toward 0.7.
	aimLowSpeedGainFloor = 0.35, -- minimum pitch-gain multiplier at very low airspeed (0.5→0.35 S26f: residual slow-turn
	                             -- oscillation — softer floor + the wider stall band above. Slow turns too mushy: back to 0.5)
	aimSpeedGainRef      = 1.0,  -- speed at which full gain returns, as a multiple of profile glideSpeed
	-- COORDINATED-TURN PITCH FEEDFORWARD (S27, deep-research RESEARCH-instructor-turn.md). Chad: in a HARD
	-- banked mouse turn the nose DIPS/porpoises ("it goes down to keep the speed… throws you off target when
	-- merging with the crows"). Root cause: the instructor pulls the nose up ONLY after the bank's lift-sag
	-- shows up as cursor ERROR (a pure PD error loop), and the S26 stability concessions soften that pull
	-- exactly in the turn. The fix real autopilots use (ArduPilot PTCH2SRV_RLL) + real raptors use (tail-twist
	-- nose-up pitch applied WITH the bank; Science Robotics 2024) is a bank-proportional FEEDFORWARD: add
	-- nose-up pitch as a function of BANK, before the error develops. In a level turn the wing must make
	-- n=1/cos(bank) times the lift to hold altitude, so the extra-lift demand ∝ (sec(bank)-1) — ZERO at
	-- wings-level, growing with bank. computeMouseAim adds bankFF = (sec(bank)-1)·this to the pitch command
	-- BEFORE the AoA/stall gate (so it's stall-limited at low speed, exactly where the merge fight lives) and
	-- the CS-1 aim gate (mouse-aim only; keyboard still zeroes it). WHY IT DOESN'T RE-PORPOISE: feedforward is
	-- open-loop (function of bank, not cursor error) so it adds NO closed-loop phase lag — it CANCELS the known
	-- lift-sag so the PD loop chases LESS, unlike raising P-gain which fights its own damping. Zero at
	-- wings-level ⇒ straight flight + the signed-off snap feel are numerically UNTOUCHED. Kernel untouched.
	-- TUNING (ArduPilot's tuned analogue sits near unity on a comparable term; ours is normalized [-1,1], so
	-- 0.35 is conservative): nose still DIPS in a hard bank → raise toward 0.5-0.6; nose now BALLOONS/climbs
	-- in turns → lower toward 0.2 (ArduPilot's own reduce-if-it-gains-height rule). 0 = feature off. PROVISIONAL.
	aimBankFeedforward = 0.35,
	-- S28 COORDINATED-TURN CASCADE (deep-research RESEARCH-coordinated-flight.md — Chad's directive after
	-- the S27 servo patches rubberbanded). For LARGE HORIZONTAL aim errors the roll/yaw channels stop being
	-- servos on cursor error and become a bank-to-turn cascade: heading error → sqrt-shaped commanded turn
	-- RATE (linear small = snappy, bounded-deceleration large = cannot overshoot; ArduPilot sqrt-controller)
	-- → ONE commanded BANK (φ_d = atan(V·ψ̇_d/g), the coordinated-turn inversion, speed-scaled), slew-limited
	-- so the command respects the roll loop's lag (Jung & Tsiotras: ignoring that lag IS the overshoot) →
	-- roll servos the BANK to φ_d (bank error, not cursor error) + yaw coordinates from the SAME turn command.
	-- Below aimDirectConeDeg (and for near-vertical errors = loops, and inverted flight) the OLD direct law
	-- runs verbatim — the loved small-input snap, loop commitment, and straight-flight feel are numerically
	-- IDENTICAL to the S26 baseline. Pitch channel untouched (PD + speed scale + stall gate + bank FF above).
	aimDirectConeDeg = 10,   -- error cone (deg) where the direct law runs alone; blends to full cascade by 2×
	                         -- this. MouseFlight aggressiveTurnAngle precedent (~10°). Bigger = more old-feel
	                         -- range; smaller = coordination takes over sooner.
	aimTurnP         = 2.5,  -- rad/s of commanded turn rate per rad of heading error (the AGGRESSIVENESS knob,
	                         -- ≈ 1/NAVL1_PERIOD). Reticle closes big turns too slowly → raise; arrives too hot
	                         -- (relies on the accel limit) → lower.
	aimTurnAccel     = 2.0,  -- rad/s² bounded arrival deceleration of the sqrt-controller (the NO-OVERSHOOT
	                         -- knob). Reticle still sails past the cursor → LOWER this (gentler roll-out
	                         -- starts earlier); catch-up feels like it brakes too early → raise.
	aimMaxBankDeg    = 70,   -- bank ceiling the cascade may command (deg). The sec(bank) pitch FF above pays
	                         -- the altitude; past ~75° that demand explodes, so keep ≤ 72.
	aimBankSlew      = 2.0,  -- rad/s max slew of the COMMANDED bank — the outer law respecting the roll loop's
	                         -- lag (Eagle rollRate 3.2; command slower than the plant = the plant can track it).
	                         -- Bank command feels laggy entering turns → raise toward 2.6; wobbles → lower.
	aimBankGain      = 3.0,  -- inner bank-tracking servo P: full roll deflection at ~19° of bank error. Tracks
	                         -- a SMOOTH slewed command, so it doesn't need to be soft; aimRollDamp still damps.
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
