--!nonstrict
--[[
	RescueRules.luau — the ONE source of truth for the Eagles-to-the-Rescue catch/score/phase math.

	PURE module (ReplicatedStorage.RescueRules). No Instances, services, clock (os/tick), task, or
	side-effecting globals. Inputs are numbers / strings / plain tables / Vector3 (datatype ops only:
	.Magnitude / :Dot / .Unit / arithmetic). The caller supplies `now` where a clock is needed.

	This is packet A2.1 (the keystone EXTRACTION). It is behavior-preserving: every function transcribes
	LIVE logic out of BirdController.client.luau and RescueServer.server.luau VERBATIM — including every
	`or`-fallback literal, which is load-bearing (the live call sites depend on those defaults). Line
	cites below point at the source of record. Nothing consumes this module in A2.1 (A2.2 = server, A2.3
	= client, A2.4 = sticky seats) so the game's runtime stays byte-identical.

	Contracts kept (design §1/§2):
	  • eligibility() is the ONE catch predicate, mode "predict" (client per-frame, TIGHT) | "accept"
	    (server at receipt, LOOSE — acceptEnvelope ONLY, no effectiveRadius / no ftue / no closing gate).
	  • acceptEnvelope is `triggerRadius·catchGateMult + speed·catchGateLatency` and NEVER references
	    effectiveRadius (re-deriving it from R_eff resurrects bug 2c). See the A2 AMENDMENT.

	Every fn takes `cfg = GameConfig.Rescue`; it is never re-typed literals — the `or`-fallbacks match
	the live call sites so a config with a field absent reproduces today's number.
]]

local RescueRules = {}

--------------------------------------------------------------------------------
-- CLIENT PREDICT GEOMETRY (transcribed from BirdController.client.luau)
--------------------------------------------------------------------------------

-- effectiveRadius — the client's per-frame predict sphere radius.
-- LIVE: BirdController:1911-1916.
--   effRadius = (RES.triggerRadius or 28)
--   if isFtue then effRadius = effRadius * (RES.ftueRadiusMult or 1.5) end
--   effRadius = effRadius * (1 + clamp((flightEngine.speed - glideSp) / max(1, glideSp), 0, 1) * (RES.scoopSpeedGain or 0.25))
-- `isFtue` derives from catchCount (BirdController:1897): isFtue = catchCount < (RES.ftueCatches or 3).
-- The scoop widens on TOTAL airspeed (flightEngine.speed), NOT closing (doc §ground-truth correction).
function RescueRules.effectiveRadius(cfg, speed, glideSpeed, catchCount)
	cfg = cfg or {}
	local isFtue = (catchCount or 0) < (cfg.ftueCatches or 3)
	local effRadius = (cfg.triggerRadius or 28)
	if isFtue then
		effRadius = effRadius * (cfg.ftueRadiusMult or 1.5)
	end
	local glideSp = glideSpeed or 130
	local scoop = math.clamp((speed - glideSp) / math.max(1, glideSp), 0, 1) * (cfg.scoopSpeedGain or 0.25)
	return effRadius * (1 + scoop)
end

-- closingGate — the client's closing-speed floor. LIVE: BirdController:1897-1899.
--   isFtue = catchCount < (RES.ftueCatches or 3)
--   gateFrac = isFtue and (RES.ftueGateFrac or RES.closingGateFrac or 0.3) or (RES.closingGateFrac or 0.3)
--   gate = gateFrac * eagleGlide()
function RescueRules.closingGate(cfg, glideSpeed, catchCount)
	cfg = cfg or {}
	local isFtue = (catchCount or 0) < (cfg.ftueCatches or 3)
	local gateFrac = isFtue and (cfg.ftueGateFrac or cfg.closingGateFrac or 0.3) or (cfg.closingGateFrac or 0.3)
	return gateFrac * (glideSpeed or 130)
end

-- hasRoom — capacity check. LIVE client: BirdController:1903-1904
--   inFlight = (catch and 1 or 0) + #crewCatches
--   haveRoom = (#riders + inFlight) < (rescueState.capacity or RES.carryCapacity or 3)
-- LIVE server: RescueServer:541  ps.carry >= (R.carryCapacity or 3)  (i.e. room = carry < cap; inFlight=0).
-- `capacity` here is the resolved cap (rescueState.capacity or cfg.carryCapacity or 3) — the caller passes it.
function RescueRules.hasRoom(carried, inFlight, capacity)
	return ((carried or 0) + (inFlight or 0)) < (capacity or 3)
end

--------------------------------------------------------------------------------
-- SERVER ACCEPT ENVELOPE (transcribed from RescueServer.server.luau)
--------------------------------------------------------------------------------

-- acceptEnvelope — the SERVER's LOOSE distance gate. THE §3.1 amendment term.
-- LIVE: RescueServer:552
--   gate = (R.triggerRadius or 28) * (R.catchGateMult or 3.5) + speed * (R.catchGateLatency or 0.25)
-- ⚠️ DO NOT re-derive from effectiveRadius — the server gate is DELIBERATELY looser than the client
-- predict radius. catchGateMult 3.5 exists because the S36 diag observed *legit* catches at server-dist
-- 80–110: replication lag + the birdScale-2.3 eagle flies on after the client triggers. Implementing the
-- old `R_eff + speed·latency` line re-tightens the gate (~117 vs the live ~212 @ maxSpeed) and resurrects
-- the "8–9/10 don't count" class — the one bug that broke the sacred guaranteed catch (P1). catchGateMult
-- stays a NAMED term carrying the birdScale-2.3 slack; this fn takes no catchCount and never calls
-- effectiveRadius. At live values: envelope(0)=42·3.5=147 ≥ max predict radius (~79); at speed 260,
-- 147+65=212 (covers the observed 80–110 legit band).
function RescueRules.acceptEnvelope(cfg, speed)
	cfg = cfg or {}
	return (cfg.triggerRadius or 28) * (cfg.catchGateMult or 3.5) + (speed or 0) * (cfg.catchGateLatency or 0.25)
end

--------------------------------------------------------------------------------
-- THE ONE ELIGIBILITY FUNCTION (design §1/§2) — both authorities call this.
--------------------------------------------------------------------------------
-- Verdict = { eligible, reason, dist, closing, speed, radius, gate }.
-- reason ∈ "ok" | "phase" | "gone" | "full" | "tooFar" | "tooSlow".
-- Reason precedence: phase → gone → full → tooFar → (predict only) tooSlow → ok.
--
-- args = {
--   mode      = "predict" | "accept",
--   phase     = string,                 -- current round phase
--   state     = string | nil,           -- squirrel State ("stranded" required); nil in predict tolerated
--   dist      = number,                 -- eagle→squirrel distance (studs)
--   closing   = number | nil,           -- vel:Dot(dir); predict needs it, accept ignores it
--   speed     = number,                 -- total airspeed (server: body speed; client: flightEngine.speed)
--   glideSpeed= number,                 -- eagleGlide()
--   catchCount= number | nil,           -- client ftue counter (predict only)
--   carried   = number,                 -- riders (client) / ps.carry (server)
--   inFlight  = number | nil,           -- in-flight catches (client only; server passes 0)
--   capacity  = number,                 -- resolved cap
-- }
function RescueRules.eligibility(cfg, args)
	cfg = cfg or {}
	local mode = args.mode or "predict"
	local dist = args.dist or 0
	local closing = args.closing
	local speed = args.speed or 0

	-- phaseAccepts.catch — client checks phase=="active"; server checks phase=="active" (grace does
	-- NOT accept a catch, only a deliver). See phaseAccepts() below.
	local pa = RescueRules.phaseAccepts(args.phase)

	local radius, gate
	if mode == "accept" then
		radius = RescueRules.acceptEnvelope(cfg, speed)
		gate = nil -- server never checks closing
	else
		radius = RescueRules.effectiveRadius(cfg, speed, args.glideSpeed, args.catchCount)
		gate = RescueRules.closingGate(cfg, args.glideSpeed, args.catchCount)
	end

	local function verdict(eligible, reason)
		return {
			eligible = eligible,
			reason = reason,
			dist = dist,
			closing = closing,
			speed = speed,
			radius = radius,
			gate = gate,
		}
	end

	-- precedence: phase → gone → full → tooFar → tooSlow(predict) → ok
	if not pa.catch then
		return verdict(false, "phase")
	end
	-- squirrel "stranded" required. In accept the server gate is `s.state ~= "stranded"` (RescueServer:539).
	-- In predict the scan only iterates State=="stranded" models (BirdController:1923) — a nil/absent state
	-- passed to predict means "not a stranded squirrel", so we treat non-"stranded" as gone in both modes.
	if args.state ~= nil and args.state ~= "stranded" then
		return verdict(false, "gone")
	end
	if not RescueRules.hasRoom(args.carried, args.inFlight, args.capacity) then
		return verdict(false, "full")
	end
	if dist > radius then
		return verdict(false, "tooFar")
	end
	if mode == "predict" and (closing or 0) < (gate or 0) then
		return verdict(false, "tooSlow")
	end
	return verdict(true, "ok")
end

--------------------------------------------------------------------------------
-- PHASE PREDICATES (design §1) — one home for the two-authority phase checks.
--------------------------------------------------------------------------------
-- LIVE: catch accepted only in "active" (server RescueServer:536; client BirdController:1906/1909).
--       deliver accepted in "active" OR "grace" (server RescueServer:612; client BirdController:2114).
function RescueRules.phaseAccepts(phase)
	return {
		catch = phase == "active",
		deliver = phase == "active" or phase == "grace",
	}
end

--------------------------------------------------------------------------------
-- CLAIM TTL DEDUP (S35c) — client-side one-fire-per-squirrel guard.
--------------------------------------------------------------------------------
-- LIVE: BirdController:1357-1363 (isClaimed) + :1512/:1665 (markClaim = claimedIds[id] = os.clock()).
-- claims = { [id] = time }. Caller passes `now` (purity: no os.clock here).
--   isClaimed: at = claims[id]; if not at then false; if now-at > (RES.claimTTL or 3) then clear+false; else true.
function RescueRules.claimActive(claims, id, now, cfg)
	cfg = cfg or {}
	local at = id and claims[id]
	if not at then
		return false
	end
	if now - at > (cfg.claimTTL or 3) then
		claims[id] = nil
		return false
	end
	return true
end

-- markClaim — claim BEFORE anything else (one fire per squirrel, ever). LIVE: BirdController:1512/1665.
function RescueRules.markClaim(claims, id, now)
	claims[id] = now
	return claims
end

--------------------------------------------------------------------------------
-- COMBO (Chad S34) — consecutive catches within comboWindow build a ×2..×comboMax streak.
--------------------------------------------------------------------------------
-- LIVE: RescueServer:577-587.
--   now = os.clock()
--   if now - (ps.lastCatchAt or -1e9) <= (R.comboWindow or 4) then
--     ps.combo = min((ps.combo or 0) + 1, R.comboMax or 6)
--   else ps.combo = 1 end
--   ps.lastCatchAt = now
--   ps.loadCombo = max(ps.loadCombo or 1, ps.combo)
-- Returns (combo, loadCombo). Caller stores them + stamps lastCatchAt = now.
function RescueRules.comboOnCatch(cfg, now, lastCatchAt, combo, loadCombo)
	cfg = cfg or {}
	local newCombo
	if now - (lastCatchAt or -1e9) <= (cfg.comboWindow or 4) then
		newCombo = math.min((combo or 0) + 1, cfg.comboMax or 6)
	else
		newCombo = 1
	end
	local newLoadCombo = math.max(loadCombo or 1, newCombo)
	return newCombo, newLoadCombo
end

--------------------------------------------------------------------------------
-- SPEED TIER + CATCH SCORE
--------------------------------------------------------------------------------
-- speedTier — LIVE (client sends it): BirdController:1520-1522 / :1673-1675.
--   tier = ""
--   if closing >= (RES.blazingFrac or 0.9) * glide then tier = "BLAZING"
--   elseif closing >= (RES.swiftFrac or 0.6) * glide then tier = "SWIFT" end
function RescueRules.speedTier(cfg, closing, glideSpeed)
	cfg = cfg or {}
	local glide = glideSpeed or 130
	if (closing or 0) >= (cfg.blazingFrac or 0.9) * glide then
		return "BLAZING"
	elseif (closing or 0) >= (cfg.swiftFrac or 0.6) * glide then
		return "SWIFT"
	end
	return ""
end

-- catchScore — the per-catch points. LIVE: RescueServer:570-588.
--   mult = clamp(styleMult or 1, 1, R.styleMultMax or 3)
--   rarityMult = s.rarity.mult or 1
--   energyMult = 1; BLAZING → R.blazingMult or 2.0; SWIFT → R.swiftMult or 1.5
--   pts = floor(R.basePoints * rarityMult * mult * energyMult + 0.5)
-- The combo is NOT applied per-catch (Chad S36: it pays at DELIVER). rarityMult and styleMult are passed;
-- speedTier is the resolved tier string.
function RescueRules.catchScore(cfg, rarityMult, styleMult, speedTier)
	cfg = cfg or {}
	-- NaN GUARD (S45 audit). math.clamp is `v < min ? min : (v > max ? max : v)` and EVERY comparison
	-- with NaN is false — so a NaN styleMult sails through both rails, math.floor(NaN) is NaN, and
	-- `ps.score += pts` poisons the score for the rest of the round (the HUD then renders "nan"
	-- acorns). styleMult is client-supplied, so the clamp is the only thing standing here. Same
	-- `x ~= x` test fireRoarVolume already uses.
	if styleMult ~= styleMult then styleMult = 1 end
	if rarityMult ~= rarityMult then rarityMult = 1 end
	local mult = math.clamp(styleMult or 1, 1, cfg.styleMultMax or 3)
	local rarity = rarityMult or 1
	local energyMult = 1
	if speedTier == "BLAZING" then
		energyMult = cfg.blazingMult or 2.0
	elseif speedTier == "SWIFT" then
		energyMult = cfg.swiftMult or 1.5
	end
	return math.floor((cfg.basePoints or 100) * rarity * mult * energyMult + 0.5)
end

--------------------------------------------------------------------------------
-- DELIVER PAYOUT + PERFECT-TEN FINALE
--------------------------------------------------------------------------------
-- deliverPayout — the math-delivery bonus. LIVE: RescueServer:625-626/:629-630.
--   cmb = max(1, floor(ps.loadCombo or 1))
--   ps.score += n * n * (R.acornValue or 10) * cmb   -- n = ps.carry
--   ps.deliverN = n; ps.deliverCombo = cmb
-- Returns {points, n, combo} — the client sentence renders from these SERVER-truth values (never the
-- local rider count; red-team B1: the sentence must never lie).
function RescueRules.deliverPayout(cfg, carry, loadCombo)
	cfg = cfg or {}
	local n = carry or 0
	local combo = math.max(1, math.floor(loadCombo or 1))
	local points = n * n * (cfg.acornValue or 10) * combo
	return { points = points, n = n, combo = combo }
end

-- perfectFactor — the TIME FACTOR ladder. LIVE (identical at RescueServer:640-643 AND :689-694).
--   f = 2; if timeLeft >= (R.timeFactor4At or 60) then f = 4 elseif timeLeft >= (R.timeFactor3At or 30) then f = 3 end
-- `timeLeftAtTenth` = ps.perfectAt (the clock the moment the 10th rescue landed).
function RescueRules.perfectFactor(cfg, timeLeftAtTenth)
	cfg = cfg or {}
	local t = timeLeftAtTenth or 0
	if t >= (cfg.timeFactor4At or 60) then
		return 4
	elseif t >= (cfg.timeFactor3At or 30) then
		return 3
	end
	return 2
end

-- quantizeAcorns — round score to WHOLE ACORNS (so the finale sentence is EXACTLY true; red-team B1).
-- LIVE: RescueServer:686  ps.score = floor(ps.score / av + 0.5) * av   (av = R.acornValue or 10).
function RescueRules.quantizeAcorns(cfg, score)
	cfg = cfg or {}
	local av = cfg.acornValue or 10
	return math.floor((score or 0) / av + 0.5) * av
end

-- finaleApply — quantize FIRST, then multiply by the banked time factor (bug-12: quantize-before-factor).
-- LIVE: RescueServer:686-697.  ps.score = quantize(ps.score); ps.preFactorScore = ps.score; ps.score *= f.
-- Returns {preFactorScore, finalScore}. Because quantize happens first, banked (shown at deliver) ==
-- finale (single source of truth — the "BANKED ×N" can never differ from the finale ×N).
function RescueRules.finaleApply(cfg, score, factor)
	cfg = cfg or {}
	local quantized = RescueRules.quantizeAcorns(cfg, score)
	return { preFactorScore = quantized, finalScore = quantized * (factor or 1) }
end

--------------------------------------------------------------------------------
-- F3 STICKY SEATS (design §1) — deterministic seat assignment (A2.4 consumes this).
--------------------------------------------------------------------------------
-- occupied = { [seatIndex] = true }. seatAssign returns the LOWEST free seat in [1, capacity], or nil
-- if full. This is the packet's ONE intentional behavior change (cosmetic seat stability): a rider's
-- seat never re-indexes when another rider leaves (the live `#riders + 1` derivation at
-- BirdController:1615/:1681 shifts every seat when the array compacts — bug F3). Pure set ops here.
function RescueRules.seatAssign(occupied, capacity)
	local cap = capacity or 0
	for seat = 1, cap do
		if not occupied[seat] then
			return seat
		end
	end
	return nil
end

function RescueRules.seatRelease(occupied, seat)
	if seat ~= nil then
		occupied[seat] = nil
	end
	return occupied
end

function RescueRules.highestOccupied(occupied)
	local hi = 0
	for seat in pairs(occupied) do
		if seat > hi then
			hi = seat
		end
	end
	return hi
end

--------------------------------------------------------------------------------
-- ROUND PHASE MACHINE (design §1) — the intermission→active→grace→results loop.
--------------------------------------------------------------------------------
-- LIVE: RescueServer:1006-1058 (the while-true round loop). phaseStep is a PURE state advance: it does
-- NOT resample wall-clock — the live task.wait cadence + pushAll rhythm stay at the call site (design §6
-- secondary guard). Duration source (RescueServer): intermission=R.intermission(6),
-- active=R.roundLength(120), grace=R.buzzerGrace(4), results=R.resultsHold(8).
RescueRules.PHASES = { "intermission", "active", "grace", "results" }

-- `roundIndex` (optional, 1-based) exists for ONE reason: the FIRST intermission after a server boot.
-- S44 BootDiag, Chad "it just takes a while at the start for everything to render" — the timestamps
-- named it exactly: the world builds in 4 MILLISECONDS, then the valley sits DELIBERATELY EMPTY for
-- the full 6s intermission while the player already has a bird (~1.9s in) and nothing to fly at.
-- Squirrels then all appear in one frame at 6.2s, which reads as "everything rendered in late".
-- Between rounds that pause is right — it is the breather after the results screen. At BOOT there is
-- no previous round to break from, so it is pure dead air. Callers that don't pass roundIndex get
-- the old behaviour exactly.
function RescueRules.phaseDuration(cfg, phase, roundIndex)
	cfg = cfg or {}
	if phase == "intermission" then
		if roundIndex == 1 and cfg.firstIntermission then
			return cfg.firstIntermission
		end
		return cfg.intermission or 6
	elseif phase == "active" then
		return cfg.roundLength or 120
	elseif phase == "grace" then
		return cfg.buzzerGrace or 4
	elseif phase == "results" then
		return cfg.resultsHold or 8
	end
	return 0
end

-- phaseStep — advance the phase machine by dt. Returns (phase, timeLeft, transitioned).
-- When timeLeft runs out, roll to the NEXT phase (wrapping results→intermission) and reset its clock
-- to phaseDuration. `transitioned` is true on the frame the phase changed. Mirrors the live loop's
-- ordering intermission→active→grace→results→(loop). Pure: dt is supplied, not measured.
local PHASE_NEXT = {
	intermission = "active",
	active = "grace",
	grace = "results",
	results = "intermission",
}
function RescueRules.phaseStep(phase, timeLeft, dt, cfg)
	local t = (timeLeft or 0) - (dt or 0)
	if t > 0 then
		return phase, t, false
	end
	local nextPhase = PHASE_NEXT[phase] or "intermission"
	return nextPhase, RescueRules.phaseDuration(cfg, nextPhase), true
end

-- triageTick — the fake-fire beacon-expiry cadence. LIVE: RescueServer:1029-1043.
--   if timeLeft <= (hz.triageAt or R.triageAt or 60):
--     triageBucket += dt
--     if triageBucket >= (hz.cadence or 4): triageBucket = 0
--       if #stranded > (hz.minStranded or 2): expire one
-- Pure form: caller passes `bucket`, dt, timeLeft, strandedCount, and a `hazard` table (triageAt,
-- cadence, minStranded, with the shipped literals as fallbacks). Returns (bucket, expire) where
-- `expire` is true when a squirrel should be balloon-lifted this tick. Never expires below minStranded.
function RescueRules.triageTick(bucket, dt, timeLeft, strandedCount, hazard)
	hazard = hazard or {}
	local triageAt = hazard.triageAt or 60
	if (timeLeft or 0) > triageAt then
		return bucket or 0, false
	end
	local b = (bucket or 0) + (dt or 0)
	if b >= (hazard.cadence or 4) then
		b = 0
		if (strandedCount or 0) > (hazard.minStranded or 2) then
			return b, true
		end
	end
	return b, false
end

--------------------------------------------------------------------------------
-- STAGE 3c — FIRE ROAR volume curve (kid-legibility Stage 3, channel (c)).
-- Pure, stateless, per-frame: the client recomputes the roar's Volume every frame from its distance
-- to the nearest burning cell. This is the S37/S38 stateless-projection architecture that closed the
-- audio saga — there is NO envelope, NO tween, NO stop-timer and NO state to desync, so "the fire
-- kept roaring after it burned out" is ARITHMETICALLY impossible: no burning cells ⇒ dist is huge ⇒
-- Volume is 0 that same frame.
--
-- Shape: silent at/beyond roarFarR, full at/inside roarNearR, and a gamma-shaped swell between so the
-- roar comes up as you commit toward the fire rather than fading linearly across the whole valley.
-- Monotone NON-INCREASING in distance by construction (t is monotone, gamma > 0 preserves order).
--------------------------------------------------------------------------------
function RescueRules.fireRoarVolume(cfg, dist)
	cfg = cfg or {}
	local nearR = cfg.roarNearR or 200
	local farR = cfg.roarFarR or 900
	local maxVol = cfg.roarMaxVol or 0.35
	if not dist or dist ~= dist or dist >= farR then
		return 0 -- beyond earshot, or no fire at all (dist = math.huge), or NaN-guard
	end
	if dist <= nearR then
		return maxVol
	end
	local t = (farR - dist) / math.max(1e-3, farR - nearR) -- 0 at farR → 1 at nearR
	return maxVol * t ^ (cfg.roarGamma or 1.5)
end

--------------------------------------------------------------------------------
-- B5 — SQUIRREL SQUEAKS (Chad S42 directive #2: "little squirrel sounds and music even the better").
-- Two pure curves so the FEEL envelope is headless-gateable before anyone hears it (the S41 FX
-- feel-gate rule: verify the MOTION/ENVELOPE, not the pixels or the waveform).
--
-- Unlike the fire roar, a squeak is a DISCRETE one-shot, not a continuous loop — so the stateless
-- projection law does not apply and cannot be faked. The "sound that won't stop" class is impossible
-- here by construction anyway: a one-shot has no sustain to leak. What must be bounded instead is the
-- RATE (never a chirp-storm) and the RANGE (a squirrel you cannot see must not be shouting in your ear).
--------------------------------------------------------------------------------

-- Volume by distance: silent at/beyond squeakHearR, full at/inside squeakFullR, linear between.
-- Deliberately gentler than the fire roar's gamma swell: a squeak is a LOCATOR, so it should fade in
-- early and evenly enough to steer by, rather than staying quiet until you have already committed.
function RescueRules.squeakVolume(cfg, dist)
	cfg = cfg or {}
	local hearR = cfg.squeakHearR or 260
	local fullR = cfg.squeakFullR or 60
	local maxVol = cfg.squeakMaxVol or 0.5
	if not dist or dist ~= dist or dist >= hearR then
		return 0
	end
	if dist <= fullR then
		return maxVol
	end
	return maxVol * ((hearR - dist) / math.max(1e-3, hearR - fullR))
end

-- Seconds between one squirrel's squeaks, by its Stage-3a Danger level. STRICTLY decreasing: a
-- frightened critter calls out more often, which is the whole point — the ear learns triage before
-- the eye does. Calm chirping is deliberately sparse so 15 squirrels read as a living wood, not a mob.
function RescueRules.squeakInterval(cfg, danger)
	cfg = cfg or {}
	if (danger or 0) >= 2 then
		return cfg.squeakIntervalPanic or 1.2
	elseif (danger or 0) >= 1 then
		return cfg.squeakIntervalWorried or 3.0
	end
	return cfg.squeakIntervalCalm or 7.0
end

--[[
	squeakSchedule(cfg, idn, now, nextAt, danger, budget) -> fired, newNextAt, pitch

	The RATE machinery, extracted (red-team F2). It first lived inline in BirdController, which put it
	outside Tier-4's reach — and a mutation deleting the per-frame cap passed the whole suite. That is
	the S40 finding ("~70% of playtest churn was headless-testable logic") walked backwards, so the
	schedule lives here where it can be gated.

	  • nextAt == nil        → SEED with a per-squirrel stagger, don't fire. The stagger scales with the
	                           CURRENT danger, so a panicking squirrel entering earshot is heard within
	                           ~1s instead of being silent for up to a calm interval (F7) — first
	                           contact is exactly when "hear a critter you haven't spotted" earns its keep.
	  • badly overdue        → RESEED, don't fire (F3). A squirrel out of earshot has a frozen clock, so
	                           on re-approach every squirrel in the grove would satisfy now >= nextAt on
	                           the SAME frame — a machine-gun volley on every return, which is precisely
	                           what the stagger exists to prevent.
	  • budget <= 0          → don't fire and DON'T reschedule: the per-frame cap defers a chirp, it
	                           never silently eats one.
	  • otherwise, when due  → fire, and reschedule from NOW (never from the stale deadline, or a
	                           returning squirrel would chirp repeatedly to catch up).
]]
function RescueRules.squeakSchedule(cfg, idn, now, nextAt, danger, budget)
	cfg = cfg or {}
	idn = idn or 0
	now = now or 0
	danger = danger or 0
	local interval = RescueRules.squeakInterval(cfg, danger)
	-- deterministic per-squirrel offset (golden ratio on the id — never math.random, house rule)
	local stagger = ((idn * 0.6180339887) % 1) * interval

	if nextAt == nil then
		return false, now + stagger, nil
	end
	if now - nextAt > interval then
		return false, now + stagger, nil
	end
	if now < nextAt then
		return false, nextAt, nil
	end
	if (budget or 1) <= 0 then
		return false, nextAt, nil
	end

	local jit = cfg.squeakJitter or 0.35
	local frac = ((idn * 0.6180339887 + now * 0.113) % 1) * 2 - 1   -- -1..1, deterministic
	local floor = cfg.squeakMinInterval or 0.6
	local newNext = now + math.max(floor, interval * (1 + jit * frac))
	local pitch = 1
		+ (((idn * 0.381) % 1) * 2 - 1) * (cfg.squeakPitchSpread or 0.22)
		+ ((danger >= 2) and (cfg.squeakPitchDanger or 0.18) or 0)
	return true, newNext, pitch
end

--------------------------------------------------------------------------------
-- catchChime — should THIS catch play the celebration chord?
-- Chad S43: *"the sounds pinging me after I catch just a few squirrels — it should only ping when I
-- have 10/10."* The rising chord used to fire on every catch, so the celebration was cheap and it
-- nagged. It now fires exactly once per load, on the catch that FILLS the back.
--
-- It lives here rather than inline in the client for the reason the squeak red-team proved earlier
-- this session: a rule with no home in a pure module has no home in a test either, and a mutation
-- deleting it passed the whole suite.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- B4.1 — SOLID TREES. Two pure predicates so the truth tables are headless-gated (world-gen itself
-- lives in a server script no Lune tier can fly, so at minimum the DECISIONS it makes are testable).
--
-- Fable's B4 finding dissolved the "lethal tree" fear: Rescue.nonLethalTerrain forces both crash
-- gates to 1e9, so a solid tree is a graze-slide surface, never a killer. This only decides WHICH tree
-- parts the eagle's swept-sphere can hit, and how a bonk is FLAVOURED — never lethality (unchanged).
--------------------------------------------------------------------------------

-- treeQueryable — should a tree part of this KIND ("Trunk" | "Canopy") be a collision surface?
--   "off"    → neither (byte-identical to the pre-B4 ghost forest)
--   "trunks" → wood is solid, leaves are soft (the kid-kind fallback)
--   "full"   → both, so skimming the canopy roof charges the style meter (the flight hypothesis)
function RescueRules.treeQueryable(cfg, kind)
	local mode = (cfg and cfg.treeCollision) or "off"
	if mode == "full" then
		return kind == "Trunk" or kind == "Canopy"
	elseif mode == "trunks" then
		return kind == "Trunk"
	end
	return false
end

-- surfaceKind — classify a hit part NAME into the FX flavour of its bonk. Canopy scatters leaves; every
-- other solid (trunk, mesa, ground/terrain) throws the certified feather oof. Presentation only — it
-- changes what you SEE on a graze, never the graze itself.
function RescueRules.surfaceKind(name)
	if name == "Canopy" then
		return "leaf"
	end
	return "feather"
end

--------------------------------------------------------------------------------
-- B4.2 — TREE STYLE SCORING, decoupled from tree COLLISION.
--
-- Chad kept the ghost forest at S45c (treeCollision="off": *"trees I dont collide with which is a
-- positive. Makes it more simple."*). That one flag was doing two jobs: it also leaves trees
-- CanQuery=false, and the style meter finds terrain by RAYCAST — so the meter was blind to trees and
-- canopy-threading, the advertised skill-ceiling verb, paid NOTHING. These two pure functions give
-- the SCORER its own source (canopy POSITIONS) so the ceiling exists without a single tree ever
-- becoming a collision surface. The ghost forest is untouched.
--
-- ⚠️ THE SHELL, NOT THE BALL — the red-team BLOCK that rewrote this packet, recorded so nobody
-- "simplifies" it back. The obvious form, max(0, centreDist - radius), returns 0 everywhere INSIDE a
-- canopy ⇒ closeness 1.0 through the whole interior. The trees are GHOSTS, so flying through them is
-- free — meaning that form pays MAXIMUM for barging straight through the middle of a crown and LESS
-- for threading between them. An exact inversion of the mechanic it exists to reward, and it would
-- have pinned styleMult at its 3.0 cap on essentially every catch (the grove disc saturates).
-- The line is the canopy SURFACE. So the distance is |centreDist - radius| and the score falls off
-- on BOTH sides of it: skim the roof and you score, barge through the middle and you do not.
--------------------------------------------------------------------------------

-- canopyRadius — the TRUE drawn radius of a canopy Part.
-- A Roblox Ball is always a real sphere and its radius is half the SMALLEST Size component, not half
-- X. Canopies are built Size = (d, d*0.8, d) (RescueServer.buildTree), so the drawn radius is 0.4*d.
-- Reading Size.X/2 would score a sphere 25% wider than the one on screen — a 5.6-stud invisible
-- skirt, the one thing that would turn an honest decoupling into an actual feel lie.
function RescueRules.canopyRadius(size)
	return math.min(size.X, size.Y, size.Z) * 0.5
end

-- shellCloseness — the 0..1 style charge from ONE canopy, measured off its SURFACE (see above).
-- centreDist = |eaglePos - canopyCentre|. Peaks at 1.0 on the skin, decays to 0 at proxDist on EITHER
-- side of it, and is flat 0 beyond. sweetSpot is the half-width of the knife-edge plateau.
function RescueRules.shellCloseness(centreDist, radius, proxDist, sweetSpot)
	local shell = math.abs(centreDist - (radius or 0))
	if shell >= proxDist then return 0 end
	return math.clamp((proxDist - shell) / math.max(1, proxDist - (sweetSpot or 0)), 0, 1)
end

--------------------------------------------------------------------------------
-- beatActive — is a sacred presentation beat running right now?
-- The codebase's rule for "never stomp a beat" is THREE flags (see the pose ladder): the slow-mo
-- catch, any crew catch still in flight, and the hop-off tally ceremony. A first attempt at the
-- terrain-oof suppression checked only `catch` and was rightly blocked — crew-catch timers outlive
-- the sacred beat and the hop-off ceremony is its own protected ritual.
--------------------------------------------------------------------------------
function RescueRules.beatActive(catchActive, crewCount, hopOffActive)
	if catchActive then return true end
	if (crewCount or 0) > 0 then return true end
	if hopOffActive then return true end
	return false
end

function RescueRules.catchChime(cfg, ridersAfter, capacity)
	cfg = cfg or {}
	if cfg.chimeEveryCatch then
		return true   -- the pre-S43 behaviour, kept as a one-flag comparison
	end
	return (ridersAfter or 0) >= (capacity or cfg.carryCapacity or 10)
end

--------------------------------------------------------------------------------
-- THE PING LAW (S44) — the fix for the complaint Chad has now made SIX times:
-- *"I hear pinging after picking up 6. I asked for this only on 10/10."*
--
-- WHY EVERY PREVIOUS FIX MISSED. Chad's word "ping" names an ASSET —
-- rbxasset://sounds/electronicpingshort.wav — not any one function. S38 gated the music build
-- layers; S43 gated `catchChime`/playChord. Both times the OTHER emitters of that same asset kept
-- ringing: playGotcha (every catch, vol 0.6 — LOUDER than the chord S43 removed), playWoohoo (every
-- catch), the crew choir (every ~1.7s from the first rider) and playCount/the deliver chord on
-- PARTIAL loads. To a player who cannot tell one wav from another, nothing changed. Each session
-- fixed the symbol whose NAME matched the complaint instead of inventorying what actually emits.
--
-- THE STRUCTURAL FIX. Which ASSET CLASS each audible event uses is now a pure decision made HERE,
-- swept by `SOUND_EVENTS` in the spec. The law: no cue may be "ping" class below a full load. The
-- test sweeps every event × every carry, so a NEW event added to SOUND_EVENTS is automatically
-- under the law — you cannot add a bell below 10/10 and stay green. A companion source-text gate in
-- the spec stops anyone hand-wiring an inline ping in the client to bypass this module entirely.
--
-- A catch must still LAND, so this RE-VOICES rather than silences (volume/pitch/timing stay in the
-- client — presentation; only the timbre is decided here):
--   • the catch accent → SNAP ("switch.wav"): a closing talon IS a snap, not a chime.
--   • the woohoo       → SWOOSH: the pull-up after the grab is a rising rush of air.
--   • the crew chirp   → SNAP, pitched high: rapid clicks read as squirrel chitter (and this is the
--                        seam the real squeak asset drops into if one is ever previewed).
-- The bell then exists ONLY at 10/10 — which is exactly what makes 10/10 feel like the jackpot.
--------------------------------------------------------------------------------

-- Every audible one-shot event on the rescue path. The spec sweeps THIS list, so the law covers any
-- event added here — keep it exhaustive when adding a voice.
RescueRules.SOUND_EVENTS = {
	"catchStart",      -- the leap's effort swoosh (playHup)
	"catchContact",    -- the pillow-thump at the talon (playPomf)
	"catchAccent",     -- the success sting on the contact frame (was playGotcha's two pings)
	"woohoo",          -- the delayed "wheee!" after the snap-back
	"climbWhip",       -- the scramble-up whip
	"riderLatch",      -- the settle-hop arrival on the back
	"crewContact",     -- a crew catch landing in the crew's arms
	"chirp",           -- crew-choir rider chatter (the continuous one)
	"fillChime",       -- THE earned fanfare: the catch that FILLS the back
	"jingle",          -- the "get to the waterfall!" two-note, full load only
	"deliverFanfare",  -- the payout chord at the waterfall
	"countNote",       -- one note per rider dismount (the skip-count tally)
}

-- soundClass — which asset class does this event speak in right now?
--   "ping"   = the bell (electronicpingshort) — LEGAL ONLY AT A FULL LOAD
--   "snap"   = switch.wav (talon snap / chitter click)
--   "swoosh" = action_falling.ogg (effort, air, rush)
-- ctx = { carry = the load in play at the moment of the sound, capacity = the resolved cap }.
-- The three `*OnPing` flags each restore ONE legacy voice for A/B comparison; all ship false.
function RescueRules.soundClass(cfg, event, ctx)
	cfg = cfg or {}
	ctx = ctx or {}
	local cap = ctx.capacity or cfg.carryCapacity or 10
	local full = (ctx.carry or 0) >= cap

	-- The sanctioned bells. Conditioned on `full` HERE rather than trusting the caller's own gate, so
	-- a future miswiring degrades to a snap instead of reintroducing the exact complaint.
	if event == "fillChime" or event == "jingle" or event == "deliverFanfare" or event == "countNote" then
		return full and "ping" or "snap"
	end

	-- The re-voiced per-catch layer (the actual offenders).
	-- catchAccent: SWOOSH, not snap. S44 first pass voiced it as a two-note switch.wav and Chad flew it:
	-- *"catching a squirrel now sounds like a RELOAD."* Correct — two bright clicks 0.08s apart IS a
	-- gun-reload gesture. The impact is already carried by playPomf (a low SNAP thump); what the accent
	-- must add is the "GOT you!" lift, and with only three rbxasset voices available the organic one is
	-- air. A rising airy zip over the thump reads as thump-ZIP, not click-CLACK.
	if event == "catchAccent" then return cfg.gotchaOnPing and "ping" or "swoosh" end
	if event == "woohoo"      then return cfg.woohooOnPing and "ping" or "swoosh" end
	if event == "chirp"       then return cfg.chirpOnPing  and "ping" or "snap" end

	-- Always-legal texture: these never spoke in bells to begin with.
	if event == "catchStart" or event == "climbWhip" then return "swoosh" end
	return "snap"   -- catchContact / riderLatch / crewContact
end

--------------------------------------------------------------------------------
-- THE SKY GEM (S44) — the fix for Chad's *"I can barely see the squirrels, they render in after
-- 30s."* Nothing renders late: all 15 spawn on the round's FIRST frame. He simply cannot SEE them
-- until he is close, and flying blind to the first grove takes about thirty seconds.
--
-- WHY THE CURRENT SIGNAL FAILS. Every Stage-1 marker is a fixed WORLD-size object, but acquisition
-- happens at 600–2,600 studs. At 70° FOV / 1080p (≈771 px per radian) the 2.2-stud chevron is ~2.4 px
-- at a typical 1,140-stud approach and subpixel beyond; the flat 20-stud halo foreshortens to a
-- ~13×6 px smudge and — for the 45% of perches that sit UNDER the canopy — lives entirely beneath
-- the leaves along with the critter. Stage 1 was gated on the DIVE-IN read ("does your eye land on a
-- waving animal") and never carried a range term; it traded the old shaft's weak-but-real long-range
-- line for nothing. This is that regression, quantified.
--
-- WHY THIS TECHNIQUE AND NOT THE OTHERS (SOP: vet the approach, don't offer a menu of mediocre ones):
--   • emoji BillboardGui — TOMBSTONED (Chad S39 "drop the icons"); reads as a UI sticker and abandons
--     "the critter IS the landmark".
--   • fat neon cylinder — TOMBSTONED (Chad S40 "its just a light cylinder, I don't even see
--     squirrels"); any world-fixed column readable at 2 km engulfs the critter at 70 studs.
--   • reverting the thin shaft — ~1 px wide at 1,140 studs, and its top still sits INSIDE the crown
--     band for under-canopy perches. Ceiling below the read.
--   • a bigger halo — a flat disc foreshortens by sin(elevation) and is under the leaves anyway.
--   • particles — Roblox caps particle size at 10 studs ⇒ ≤4 px at 2 km.
--   • Highlight — outlining a subpixel silhouette is subpixel.
-- The ONE technique whose ceiling reaches the read is to keep the certified Stage-1 gem and make it a
-- DISTANCE PROJECTION: constant ANGULAR size (so it is the same ~11 px at any range, like a real nav
-- marker) and a lift that clears the tree envelope at distance, descending back onto the critter's
-- head as you close. Far: an unmissable rarity-coloured kite floating over the canopy. Near: byte-
-- identical to today's gem, so occluding the critter is geometrically impossible. The descent itself
-- guides you under the crown to the hidden squirrels — F2 fixed without touching perch placement.
--
-- Stateless per frame (the project's proven projection law — no tweens, no stored state), and INERT
-- until `Rescue.skyGem` is true: with the flag false this returns the identity and the Stage-1 frame
-- is byte-identical.
--------------------------------------------------------------------------------

-- skyGemProjection — where and how big is the head chevron for an eagle `dist` studs away?
--   baseSize = the gem's BUILT base size in studs (rarity-scaled by the server; the client caches it)
--   baseY    = the gem's Stage-1 centre Y this frame (head + chevronY + bob)
-- Returns { size, y, t } where t is the 0..1 far-ness the caller also blends transparency with.
function RescueRules.skyGemProjection(cfg, dist, baseSize, baseY)
	cfg = cfg or {}
	baseSize = baseSize or (cfg.chevronSize or 2.2)
	baseY = baseY or 0
	if not cfg.skyGem then
		return { size = baseSize, y = baseY, t = 0 }   -- INERT: exactly today's Stage-1 gem
	end
	local near = cfg.skyGemNear or 70
	local far = cfg.skyGemFar or 260
	local t = math.clamp(((dist or 0) - near) / math.max(1, far - near), 0, 1)

	-- Constant angular size: studs of gem per stud of distance. 0.015 rad ≈ 11.6 px at 1080p/FOV70.
	-- Clamped below by the built size (never SHRINK a near gem) and above by skyGemMaxSize so a
	-- 2 km gem cannot become a billboard filling the sky.
	--
	-- SCALED BY THE GEM'S OWN BASE. The server builds gold/rainbow gems 1.35× (buildBeacon), and a
	-- naive `dist × k` throws that away the instant the projection takes over — every gem converges
	-- to one size and triage-by-value dies exactly where it matters most: PICKING a target from
	-- altitude. Carrying the ratio keeps a rare gem 1.35× at every range. (The spec caught this.)
	local rarityMul = baseSize / (cfg.chevronSize or 2.2)
	local farSize = math.clamp((dist or 0) * (cfg.skyGemStudsPerStud or 0.015) * rarityMul,
		baseSize, (cfg.skyGemMaxSize or 34) * rarityMul)
	local size = baseSize + (farSize - baseSize) * t

	-- Lift so the gem's BOTTOM clears the worst-case tree envelope (buildTree: crownY up to 115 +
	-- blob 35 = 150; skyGemClearY 160 keeps a margin). The gem is built 1.6× tall and rolled 45°, so
	-- its half-height is size·aspect/2. Never pulls a gem DOWN — max(0, …).
	local targetY = (cfg.skyGemClearY or 160) + size * (cfg.chevronAspect or 1.6) * 0.5
	local y = baseY + t * math.max(0, targetY - baseY)

	return { size = size, y = y, t = t }
end

--------------------------------------------------------------------------------
-- THE WAYFINDER TARGET (S45) — "I don't even know where to fly at the start" (Chad).
--
-- The game HAS a compass and has already certified its read: the faint gold streamer that points at
-- the waterfall while you carry (BirdController updateWayfinder, Fable §D, "a diegetic compass, ZERO
-- UI"). The bug is WHEN it is lit. It was gated on `#riders > 0`, so it is dark at spawn and dark
-- again after every delivery — it switches OFF at exactly the moments the player is empty-handed and
-- scanning, which is the only time anyone is actually lost. Two independent audits ranked un-gating it
-- the single highest-value change in the game, and it is ~20 lines on a mechanism that already ships.
--
-- The policy is here (pure) rather than inline in the client because the interesting part is not the
-- geometry, it is the TARGET CHOICE, and that choice has a failure mode a headless test can catch:
-- a beam that re-picks its target every frame flickers between two equidistant groves and reads as
-- broken. Hence hysteresis — a challenger must be `wayfindSwap` fraction CLOSER to steal the ribbon.
--
-- Deliberately NEAREST, not "best". Triage-by-rarity, by fire danger, by route is the skill ceiling
-- (§3.2 pays a skilled round 6.7× a casual one) and it stays entirely the player's: a 5-year-old
-- follows the ribbon, a 15-year-old ignores it and flies the valuable line. Pointing at the
-- highest-value critter would hand the ceiling's decision to the game.
--
-- INERT until `Rescue.wayfindEmpty`: with the flag false an empty-handed eagle returns "off", which is
-- byte-identical to the pre-S45 gate.
--------------------------------------------------------------------------------

-- wayfindTarget — what should the gold streamer point at this frame?
--   args = {
--     phase      = the round phase ("active" is the only phase that lights the beam),
--     carrying   = #riders aboard,
--     bestId     = id of the NEAREST catchable stranded squirrel (nil if none), and
--     bestDist   = its distance,
--     currentId  = the id the beam pointed at last frame (nil if none), and
--     currentDist= its distance THIS frame, or nil if it is no longer a valid candidate
--                  (caught, claimed, expired, folder gone) — nil is how the caller says "it's gone".
--   }
-- Returns { mode = "waterfall" | "squirrel" | "off", id = <squirrel id or nil> }.
function RescueRules.wayfindTarget(cfg, args)
	cfg = cfg or {}
	args = args or {}
	local OFF = { mode = "off", id = nil }

	-- The beam has only ever existed during the active round; grace/results/intermission stay dark.
	if args.phase ~= "active" then return OFF end

	-- Carrying: today's behaviour, untouched. The waterfall outranks every critter — once you have
	-- passengers, "where do I fly" has exactly one answer and the ribbon must not argue with it.
	if (args.carrying or 0) > 0 then return { mode = "waterfall", id = nil } end

	-- KILL SWITCH: false ⇒ empty-handed is dark, exactly as it was before S45.
	if not cfg.wayfindEmpty then return OFF end

	local bestId, bestDist = args.bestId, args.bestDist
	local curId, curDist = args.currentId, args.currentDist

	-- HYSTERESIS. If the held target is still valid, a challenger must be meaningfully closer to take
	-- the ribbon. Without this, two groves at ~equal range trade the beam every frame and it strobes.
	if curId ~= nil and curDist ~= nil then
		if bestId == nil or bestId == curId then
			return { mode = "squirrel", id = curId }
		end
		local swap = cfg.wayfindSwap or 0.2
		if (bestDist or math.huge) >= curDist * (1 - swap) then
			return { mode = "squirrel", id = curId }   -- not enough of an improvement: hold.
		end
	end

	if bestId == nil then return OFF end   -- nothing catchable anywhere: dark, never a lying arrow.
	return { mode = "squirrel", id = bestId }
end

--------------------------------------------------------------------------------
-- THE CARRIER-LOSS RESET (S45) — the respawn carry desync, found independently by two auditors.
--
-- The server zeroed `carry` in exactly two places: startRound and a successful deliver. Nothing zeroed
-- it when the player's BIRD was destroyed — but the client wipes every rider on any bird teardown
-- (teardownDrive → releaseRiders). So pressing R (the documented reset key) while carrying 7 left the
-- client showing 0/10 and the server still believing 7.
--
-- What that costs, concretely: the next 3 catches fill the server to 10, and every catch after that is
-- REJECTed as FULL while the client still plays the entire sacred catch beat and mounts a rider. The
-- reconciler only ever trims riders DOWN, so it cannot heal this. The player sees "4/10, plenty of
-- room", nothing counts, and the first waterfall pass then pays for TEN squirrels he never carried.
-- That is precisely the "a lot of my catches don't get counted" complaint S35/S36 burned two sessions
-- chasing — reachable from one keypress.
--
-- Pure here so the invariant is the testable part: a lost bird clears what you were CARRYING and
-- nothing you EARNED. Score, delivered, rescued and the Perfect-Ten stamps must survive a respawn —
-- zeroing those would turn a desync bug into a punishment.
--------------------------------------------------------------------------------

-- carryOnReset — the player's state after their bird is destroyed. Returns a NEW table (pure).
function RescueRules.carryOnReset(ps)
	local out = {}
	for k, v in pairs(ps or {}) do out[k] = v end
	out.carry = 0          -- the riders are gone from the player's back; the server must agree.
	out.loadCombo = nil    -- the chain those riders were building died with them.
	return out
end

return RescueRules
