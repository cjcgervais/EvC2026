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

function RescueRules.phaseDuration(cfg, phase)
	cfg = cfg or {}
	if phase == "intermission" then
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

return RescueRules
