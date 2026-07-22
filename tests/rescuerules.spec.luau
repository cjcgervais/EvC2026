--!nonstrict
--[[
	tests/rescuerules.spec.luau — the A2.1 regression suite for the extracted PURE RescueRules module.

	Two jobs (design §4/§6):
	  1. Encode the historical bugs 2a/2b/2c/6/8/9/10/11/12 + F3 sticky seats + the phase machine +
	     triageTick as permanent regression tests, plus the §3.1 catch-gate SIM (zero false rejects +
	     the empirical 80–110 server-dist band) and the §3.2 economy Monte-Carlo (seeded).
	  2. The PARITY ORACLE (design §6): restate the OLD inline formulas VERBATIM (copied from the live
	     lines, cited) as local functions and assert EXACT equality vs the new RescueRules functions over
	     a 1,000-point randomized sweep. A transcription that diverged fails here — that is the whole gate.

	Every assertion reads LIVE `GameConfig.Rescue` values (never re-typed literals) so a config edit can
	never silently drift the oracle. Vector3 comes off the loader (not a spec global).
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local RescueRules = Loader.load("RescueRules")
local Vector3 = Loader.Vector3

local R = GameConfig.Rescue
local GLIDE = GameConfig.Profiles.Eagle.glideSpeed -- eagleGlide() live value (130)

-- Deterministic seeded LCG so the sweeps are reproducible (no math.random seed dependence).
local function lcg(seed)
	local s = seed % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647 -- (0, 1)
	end
end

--------------------------------------------------------------------------------
-- BUG 2a — capacity silence (the "full" reason is NAMED, not silent).
--------------------------------------------------------------------------------
H.test("2a: a full carry yields reason 'full' (named, never silent)", function()
	local cap = R.carryCapacity
	local v = RescueRules.eligibility(R, {
		mode = "accept", phase = "active", state = "stranded",
		dist = 10, speed = GLIDE, carried = cap, inFlight = 0, capacity = cap,
	})
	H.eq(v.eligible, false, "full carry is ineligible")
	H.eq(v.reason, "full", "the reason is named 'full'")
	-- hasRoom directly: carry == cap is full; carry == cap-1 has room.
	H.eq(RescueRules.hasRoom(cap, 0, cap), false, "carry==cap is full")
	H.eq(RescueRules.hasRoom(cap - 1, 0, cap), true, "carry==cap-1 has room")
end)

--------------------------------------------------------------------------------
-- BUG 2b — chained catch up to capacity (cap 10) counts every one; the (cap)th is full.
--------------------------------------------------------------------------------
H.test("2b: chained catches fill exactly to capacity then block", function()
	local cap = R.carryCapacity
	H.eq(cap, 10, "live carryCapacity is 10 (cap-10 chained-catch fix)")
	for carried = 0, cap - 1 do
		H.eq(RescueRules.hasRoom(carried, 0, cap), true, "seat " .. carried .. " has room")
	end
	H.eq(RescueRules.hasRoom(cap, 0, cap), false, "the 10th catch aboard blocks the 11th")
	-- client-side room counts riders + inFlight together (BirdController:1903-1904).
	H.eq(RescueRules.hasRoom(cap - 2, 2, cap), false, "riders + inFlight sum to cap → full")
	H.eq(RescueRules.hasRoom(cap - 3, 2, cap), true, "riders + inFlight below cap → room")
end)

--------------------------------------------------------------------------------
-- BUG 2c — THE AMENDMENT unit test: acceptEnvelope must NOT be re-derived from effectiveRadius.
--------------------------------------------------------------------------------
H.test("2c: acceptEnvelope(0) == triggerRadius·catchGateMult (147), NOT R_eff-derived", function()
	local env0 = RescueRules.acceptEnvelope(R, 0)
	H.approx(env0, R.triggerRadius * R.catchGateMult, 1e-9, "envelope(0) is the flat base band")
	H.approx(env0, 147, 1e-9, "= 42·3.5 = 147 at live values")
	-- structural: the envelope has NO effectiveRadius/ftue term — it is INDEPENDENT of catchCount.
	-- (A re-derivation from R_eff would make it depend on ftue/scoop; here speed is the ONLY variable.)
	local envA = RescueRules.acceptEnvelope(R, 200)
	local envB = RescueRules.acceptEnvelope(R, 200)
	H.approx(envA, envB, 1e-9, "envelope depends only on speed (no hidden ftue/scoop state)")
	-- it is LOOSER than the max client predict radius (ftue + full scoop) so a legit catch is never
	-- rejected at receipt.
	local maxPredict = RescueRules.effectiveRadius(R, 2 * GLIDE, GLIDE, 0) -- ftue on + full scoop
	H.ok(env0 >= maxPredict, ("envelope(0) %.1f >= max predict radius %.1f"):format(env0, maxPredict))
end)

H.test("2c: the observed 80–110 server-dist band accepts (the bug-class tripwire)", function()
	-- The S36 diag observed LEGIT catches at server-dist 80–110 (replication lag + the 2.3× eagle flies
	-- on). At boom-and-zoom speed the envelope must cover the whole band. Even at speed 0, env0=147>110.
	for _, dist in ipairs({ 80, 95, 105, 110 }) do
		local v = RescueRules.eligibility(R, {
			mode = "accept", phase = "active", state = "stranded",
			dist = dist, speed = 0, carried = 0, inFlight = 0, capacity = R.carryCapacity,
		})
		H.eq(v.eligible, true, ("dist %d accepts at speed 0 (env0=147)"):format(dist))
		H.eq(v.reason, "ok", "reason ok")
	end
	-- and at a real dive speed the band is far inside the envelope.
	local vFast = RescueRules.eligibility(R, {
		mode = "accept", phase = "active", state = "stranded",
		dist = 110, speed = 260, carried = 0, inFlight = 0, capacity = R.carryCapacity,
	})
	H.eq(vFast.eligible, true, "dist 110 at speed 260 accepts (envelope ~212)")
	H.approx(vFast.radius, 147 + 260 * R.catchGateLatency, 1e-6, "envelope at 260 = 147 + 260·latency")
end)

--------------------------------------------------------------------------------
-- BUG 6 — claim TTL edge + idempotent accept (S35c dedup).
--------------------------------------------------------------------------------
H.test("6: claim TTL — active inside window, freed after claimTTL, idempotent mark", function()
	local ttl = R.claimTTL
	local claims = {}
	RescueRules.markClaim(claims, 7, 100.0)
	H.eq(RescueRules.claimActive(claims, 7, 100.0, R), true, "just-claimed is active")
	H.eq(RescueRules.claimActive(claims, 7, 100.0 + ttl, R), true, "at exactly TTL still active (<=)")
	-- just past TTL → freed (and the entry is cleared as a side effect).
	H.eq(RescueRules.claimActive(claims, 7, 100.0 + ttl + 0.001, R), false, "past TTL frees the claim")
	H.eq(claims[7], nil, "the expired claim entry is cleared")
	-- unknown id is never active.
	H.eq(RescueRules.claimActive(claims, 999, 100.0, R), false, "unknown id not claimed")
	-- idempotent accept: re-marking the same id just refreshes the timestamp (one fire per squirrel).
	RescueRules.markClaim(claims, 7, 200.0)
	RescueRules.markClaim(claims, 7, 200.0)
	H.eq(RescueRules.claimActive(claims, 7, 200.5, R), true, "re-mark refreshes, still one entry")
end)

--------------------------------------------------------------------------------
-- BUG 8 — phase predicates (deliver accepts grace; catch does not).
--------------------------------------------------------------------------------
H.test("8: phaseAccepts — catch only in active; deliver in active|grace", function()
	H.eq(RescueRules.phaseAccepts("active").catch, true, "catch in active")
	H.eq(RescueRules.phaseAccepts("active").deliver, true, "deliver in active")
	H.eq(RescueRules.phaseAccepts("grace").catch, false, "no catch in grace")
	H.eq(RescueRules.phaseAccepts("grace").deliver, true, "buzzer-grace deliver accepted (bug 8)")
	for _, p in ipairs({ "intermission", "results" }) do
		H.eq(RescueRules.phaseAccepts(p).catch, false, "no catch in " .. p)
		H.eq(RescueRules.phaseAccepts(p).deliver, false, "no deliver in " .. p)
	end
	-- eligibility routes through phaseAccepts.catch: a grace-phase catch is reason 'phase'.
	local v = RescueRules.eligibility(R, {
		mode = "accept", phase = "grace", state = "stranded",
		dist = 10, speed = GLIDE, carried = 0, inFlight = 0, capacity = R.carryCapacity,
	})
	H.eq(v.reason, "phase", "catch during grace rejected as 'phase'")
end)

--------------------------------------------------------------------------------
-- BUG 9 — combo ramp / reset / peak-hold.
--------------------------------------------------------------------------------
H.test("9: combo ramps within window, caps at comboMax, resets after window, loadCombo peak-holds", function()
	local win, cap = R.comboWindow, R.comboMax
	local combo, load = 0, 1
	local now = 100
	-- ramp: catch every (win-0.5)s keeps the chain; combo climbs 1,2,3,...
	combo, load = RescueRules.comboOnCatch(R, now, nil, combo, load)
	H.eq(combo, 1, "first catch → combo 1")
	H.eq(load, 1, "loadCombo starts at 1")
	local last = now
	for i = 2, cap + 3 do
		now = now + (win - 0.5)
		combo, load = RescueRules.comboOnCatch(R, now, last, combo, load)
		last = now
		H.between(combo, 1, cap, "combo bounded")
	end
	H.eq(combo, cap, "combo saturates at comboMax (" .. cap .. ")")
	H.eq(load, cap, "loadCombo holds the peak (" .. cap .. ")")
	-- reset: a catch after the window lapses → combo back to 1, but loadCombo (a prior load's peak) is
	-- max(loadCombo, combo) so within the SAME load it never regresses; a genuine gap resets combo.
	now = now + win + 5
	local c2, l2 = RescueRules.comboOnCatch(R, now, last, combo, load)
	H.eq(c2, 1, "combo resets after the window lapses")
	H.eq(l2, cap, "loadCombo peak-holds across the reset (max)")
	-- exactly-at-window is INSIDE (live uses <=).
	local c3 = RescueRules.comboOnCatch(R, 300, 300 - win, 2, 3)
	H.eq(c3, 3, "a catch exactly comboWindow later still chains (<=)")
end)

--------------------------------------------------------------------------------
-- BUG 10 — deliver payout 10→4000; superadditive; the n/combo it reports never lies.
--------------------------------------------------------------------------------
H.test("10: deliverPayout — n² · acornValue · combo, superadditive, honest n/combo", function()
	local av = R.acornValue
	-- one brave trip of 10 (combo 1) = 10·10·10 = 1000 points = 100 acorns.
	local p10 = RescueRules.deliverPayout(R, 10, 1)
	H.eq(p10.points, 10 * 10 * av * 1, "10-deliver combo1 = n²·acorn")
	H.eq(p10.n, 10, "reports n truthfully")
	H.eq(p10.combo, 1, "reports combo truthfully")
	-- with combo 4 → 4000 points.
	local p10c4 = RescueRules.deliverPayout(R, 10, 4)
	H.eq(p10c4.points, 10 * 10 * av * 4, "10-deliver combo4 = 4000")
	-- SUPERADDITIVE: one trip of 10 beats two trips of 5 (the n² lesson).
	local one10 = RescueRules.deliverPayout(R, 10, 1).points
	local two5 = RescueRules.deliverPayout(R, 5, 1).points * 2
	H.ok(one10 > two5, ("one 10-trip (%d) > two 5-trips (%d)"):format(one10, two5))
	-- combo floors at 1 even if a bad loadCombo (0 / fractional) arrives (max(1, floor(...))).
	H.eq(RescueRules.deliverPayout(R, 4, 0).combo, 1, "combo floors at 1")
	H.eq(RescueRules.deliverPayout(R, 4, 2.9).combo, 2, "combo floors the fraction (floor)")
end)

--------------------------------------------------------------------------------
-- BUG 11 — time-factor ladder boundaries + banked==finale identity.
--------------------------------------------------------------------------------
H.test("11: perfectFactor boundaries + banked==finale identity", function()
	local at3, at4 = R.timeFactor3At, R.timeFactor4At
	H.eq(RescueRules.perfectFactor(R, at4), 4, "timeLeft >= timeFactor4At → ×4")
	H.eq(RescueRules.perfectFactor(R, at4 - 0.001), 3, "just below ×4 → ×3")
	H.eq(RescueRules.perfectFactor(R, at3), 3, "timeLeft >= timeFactor3At → ×3")
	H.eq(RescueRules.perfectFactor(R, at3 - 0.001), 2, "just below ×3 → ×2")
	H.eq(RescueRules.perfectFactor(R, 0), 2, "no time bonus → ×2")
	-- banked-at-deliver factor == finale factor (single source of truth): compute the factor from the
	-- SAME perfectAt at both call sites → identical. The finale multiply uses the quantized score.
	local perfectAt = 42
	local bankedFactor = RescueRules.perfectFactor(R, perfectAt)
	local fin = RescueRules.finaleApply(R, 1387, bankedFactor)
	H.eq(fin.finalScore, fin.preFactorScore * bankedFactor, "finale = quantized × the SAME banked factor")
end)

--------------------------------------------------------------------------------
-- BUG 12 — quantize BEFORE the factor (the finale sentence is exactly true in acorns).
--------------------------------------------------------------------------------
H.test("12: quantize happens before the factor multiply", function()
	local av = R.acornValue
	-- a ragged score (style multipliers leave non-acorn points) quantizes to whole acorns FIRST.
	local ragged = 1387 -- not a multiple of 10
	local q = RescueRules.quantizeAcorns(R, ragged)
	H.eq(q % av, 0, "quantized score is a whole number of acorns")
	H.eq(q, math.floor(ragged / av + 0.5) * av, "quantize matches the live floor form")
	local fin = RescueRules.finaleApply(R, ragged, 3)
	H.eq(fin.preFactorScore, q, "preFactorScore is the quantized value")
	H.eq(fin.finalScore, q * 3, "finalScore = quantized × factor (not raw × factor)")
	-- the finale acorns are EXACTLY finalScore/acorn (no lie): finalScore is divisible by av.
	H.eq(fin.finalScore % av, 0, "finale is a whole number of acorns")
end)

--------------------------------------------------------------------------------
-- catchScore — the per-catch points (energy tiers + style clamp).
--------------------------------------------------------------------------------
H.test("catchScore: base × rarity × style(clamped) × energy tier", function()
	local base = R.basePoints
	H.eq(RescueRules.catchScore(R, 1, 1, ""), base, "plain catch = basePoints")
	H.eq(RescueRules.catchScore(R, 1, 1, "SWIFT"), math.floor(base * R.swiftMult + 0.5), "SWIFT energy mult")
	H.eq(RescueRules.catchScore(R, 1, 1, "BLAZING"), math.floor(base * R.blazingMult + 0.5), "BLAZING energy mult")
	-- style clamps to [1, styleMultMax]; rarity multiplies.
	H.eq(RescueRules.catchScore(R, 2, R.styleMultMax + 5, ""), math.floor(base * 2 * R.styleMultMax + 0.5), "style clamps at max, rarity 2×")
	H.eq(RescueRules.catchScore(R, 1, 0.2, ""), base, "style clamps up to 1")
end)

--------------------------------------------------------------------------------
-- speedTier — BLAZING / SWIFT / "" thresholds.
--------------------------------------------------------------------------------
H.test("speedTier: blazing/swift/none boundaries scale with glideSpeed", function()
	H.eq(RescueRules.speedTier(R, R.blazingFrac * GLIDE, GLIDE), "BLAZING", "at blazingFrac·glide → BLAZING")
	H.eq(RescueRules.speedTier(R, R.swiftFrac * GLIDE, GLIDE), "SWIFT", "at swiftFrac·glide → SWIFT")
	H.eq(RescueRules.speedTier(R, (R.swiftFrac - 0.01) * GLIDE, GLIDE), "", "below swiftFrac → none")
	H.eq(RescueRules.speedTier(R, (R.blazingFrac - 0.01) * GLIDE, GLIDE), "SWIFT", "just below blazing → SWIFT")
end)

--------------------------------------------------------------------------------
-- F3 STICKY SEATS — out-of-order release, no shared index across a sweep.
--------------------------------------------------------------------------------
H.test("F3: sticky seats — lowest-free assign, out-of-order release keeps seats stable", function()
	local cap = R.carryCapacity
	local occ = {}
	-- fill 5 seats
	local seats = {}
	for i = 1, 5 do
		seats[i] = RescueRules.seatAssign(occ, cap)
		occ[seats[i]] = true
	end
	H.eq(seats[1], 1, "first seat is 1")
	H.eq(seats[5], 5, "fifth seat is 5")
	-- release seat 2 (a middle rider leaves) — the OTHERS do not re-index (that's the F3 fix).
	RescueRules.seatRelease(occ, seats[2])
	H.eq(occ[2], nil, "seat 2 freed")
	H.eq(occ[1], true, "seat 1 unchanged (no re-index)")
	H.eq(occ[3], true, "seat 3 unchanged (no re-index)")
	-- next assign fills the freed seat 2, not seat 6.
	local reused = RescueRules.seatAssign(occ, cap)
	H.eq(reused, 2, "the next rider takes the freed seat 2 (lowest free)")
	-- highestOccupied tracks the top seat in use.
	H.eq(RescueRules.highestOccupied(occ), 5, "highest occupied is 5")
end)

H.test("F3: no two riders ever share a seat over a randomized add/remove sweep", function()
	local cap = R.carryCapacity
	local occ = {}
	local held = {} -- id -> seat
	local rnd = lcg(1337)
	local nextId = 1
	for _ = 1, 4000 do
		-- count held
		local n = 0
		for _ in pairs(held) do n = n + 1 end
		if rnd() < 0.5 and n < cap then
			local seat = RescueRules.seatAssign(occ, cap)
			H.ok(seat ~= nil, "assign returns a seat while below cap")
			H.eq(occ[seat], nil, "the assigned seat was FREE (no double-booking)")
			occ[seat] = true
			held[nextId] = seat
			nextId = nextId + 1
		elseif n > 0 then
			-- release a random held rider
			local pick = math.floor(rnd() * n) + 1
			local k = 0
			for id, seat in pairs(held) do
				k = k + 1
				if k == pick then
					RescueRules.seatRelease(occ, seat)
					held[id] = nil
					break
				end
			end
		end
		-- INVARIANT: the occupied set and the held set agree exactly (no ghost / no shared seat).
		local occCount = 0
		for _ in pairs(occ) do occCount = occCount + 1 end
		local heldCount = 0
		local seen = {}
		for _, seat in pairs(held) do
			H.eq(seen[seat], nil, "no two held riders share a seat")
			seen[seat] = true
			heldCount = heldCount + 1
		end
		H.eq(occCount, heldCount, "occupied count == held count (no leak)")
	end
end)

--------------------------------------------------------------------------------
-- PHASE MACHINE — two full cycles intermission→active→grace→results→loop.
--------------------------------------------------------------------------------
H.test("phase machine: two full cycles in order with correct durations", function()
	local order = { "intermission", "active", "grace", "results" }
	local phase = "intermission"
	local timeLeft = RescueRules.phaseDuration(R, phase)
	H.eq(timeLeft, R.intermission, "intermission duration")
	local seen = {}
	-- step until we transition, twice around the loop.
	local guard = 0
	for cycle = 1, 2 do
		for idx, expect in ipairs(order) do
			H.eq(phase, expect, ("cycle %d phase %d is %s"):format(cycle, idx, expect))
			H.approx(timeLeft, RescueRules.phaseDuration(R, phase), 1e-6, "duration matches phase")
			-- burn the clock down (dt bigger than the shortest phase; last step transitions)
			local transitioned = false
			guard = 0
			while not transitioned do
				phase, timeLeft, transitioned = RescueRules.phaseStep(phase, timeLeft, 1.0, R)
				guard = guard + 1
				H.ok(guard < 1000, "phaseStep terminates")
			end
			seen[expect] = true
		end
	end
	H.eq(phase, "intermission", "after two cycles, back to intermission")
	for _, p in ipairs(order) do
		H.eq(seen[p], true, "visited phase " .. p)
	end
end)

H.test("phase machine: a within-duration step does not transition", function()
	local phase, timeLeft, transitioned = RescueRules.phaseStep("active", 120, 0.25, R)
	H.eq(phase, "active", "still active")
	H.approx(timeLeft, 119.75, 1e-6, "clock ticked down by dt")
	H.eq(transitioned, false, "no transition mid-phase")
end)

--------------------------------------------------------------------------------
-- TRIAGE TICK — inert before triageAt, fires on cadence, never below minStranded.
--------------------------------------------------------------------------------
H.test("triageTick: inert before triageAt", function()
	-- timeLeft above triageAt → no accumulation, never fires.
	local bucket, expire = RescueRules.triageTick(0, 0.25, R.triageAt + 10, 15, {})
	H.eq(expire, false, "no triage before the window")
	H.eq(bucket, 0, "bucket does not accumulate before the window")
end)

H.test("triageTick: fires once per cadence inside the window", function()
	local hazard = { triageAt = R.triageAt, cadence = 4, minStranded = 2 }
	local bucket = 0
	local fires = 0
	local dt = 0.25
	-- run 16 seconds' worth of ticks inside the window (timeLeft below triageAt).
	for _ = 1, math.floor(16 / dt) do
		local expire
		bucket, expire = RescueRules.triageTick(bucket, dt, 30, 15, hazard)
		if expire then fires = fires + 1 end
	end
	-- 16s / 4s cadence = 4 expiries.
	H.eq(fires, 4, "one expiry per cadence over 16s")
end)

H.test("triageTick: never expires below minStranded (always leave a couple)", function()
	local hazard = { triageAt = R.triageAt, cadence = 4, minStranded = 2 }
	-- accumulate a full cadence but strandedCount is at the floor → no expire, bucket still resets.
	local bucket, expire = RescueRules.triageTick(3.9, 0.25, 30, 2, hazard)
	H.eq(expire, false, "at minStranded (>2 is false for count==2) does not expire")
	H.eq(bucket, 0, "bucket resets even when the expiry is withheld (matches live)")
	-- one above the floor → it fires.
	local _, expire2 = RescueRules.triageTick(3.9, 0.25, 30, 3, hazard)
	H.eq(expire2, true, "count 3 (> minStranded 2) expires")
end)

--------------------------------------------------------------------------------
-- §3.1 SIM — the catch-gate superset property (zero false rejects).
--------------------------------------------------------------------------------
H.test("§3.1 SIM: every client-eligible catch is accepted by the server (zero false rejects)", function()
	local cap = R.carryCapacity
	local rnd = lcg(20260717)
	local checked, falseRejects = 0, 0
	-- sweep speed × latency(≤250ms, folded into the fly-past distance) × approach angle.
	for _ = 1, 3000 do
		local speed = rnd() * (2.6 * GLIDE) -- 0 .. ~2.6× glide (into a real dive)
		local catchCount = (rnd() < 0.3) and 0 or 5 -- ftue on/off
		local radius = RescueRules.effectiveRadius(R, speed, GLIDE, catchCount)
		-- closing is at most `speed` (angle 0); pick a closing in [gate, speed] so the CLIENT accepts.
		local gate = RescueRules.closingGate(R, GLIDE, catchCount)
		if speed >= gate then
			local closing = gate + rnd() * math.max(0, speed - gate)
			-- client predicts eligible at a dist inside the predict radius.
			local dist = rnd() * radius
			local pv = RescueRules.eligibility(R, {
				mode = "predict", phase = "active", state = "stranded",
				dist = dist, closing = closing, speed = speed,
				glideSpeed = GLIDE, catchCount = catchCount,
				carried = 0, inFlight = 0, capacity = cap,
			})
			if pv.eligible then
				-- the server sees the eagle FLOWN ON: server-dist = client dist + speed·latency (≤250ms).
				local latency = rnd() * 0.25
				local serverDist = dist + speed * latency
				local av = RescueRules.eligibility(R, {
					mode = "accept", phase = "active", state = "stranded",
					dist = serverDist, speed = speed,
					carried = 0, inFlight = 0, capacity = cap,
				})
				checked = checked + 1
				if not av.eligible then falseRejects = falseRejects + 1 end
			end
		end
	end
	H.ok(checked > 500, "the sweep exercised a healthy sample (" .. checked .. " eligible catches)")
	H.eq(falseRejects, 0, "ZERO false rejects: the server accepts every client-eligible catch")
end)

--------------------------------------------------------------------------------
-- §3.2 ECONOMY — seeded Monte-Carlo: casual ~150–350, skilled ~1200–2200, ratio < 10:1.
--------------------------------------------------------------------------------
-- One round of income in ACORNS (points/acornValue), assembled from the SAME RescueRules functions the
-- server uses. Style/energy/combo profiles differ by skill; deliver dominates (n² is the headline).
-- catchGap is drawn per-catch in [gapLo, gapHi] so the combo chain BREAKS realistically (a skilled run
-- that has to reposition between clusters averages ~combo 4, matching the §3.2 worked example — not a
-- perfect 6-cap chain, which over-pays).
local function simRound(rnd, profile)
	local av = R.acornValue
	local points = 0
	local combo, load = 0, 1
	local lastCatchAt = -1e9
	local now = 0
	local carried = 0
	local delivered = 0
	local perfectAt = nil
	-- catch/deliver over the round.
	for _ = 1, profile.catches do
		now = now + profile.gapLo + rnd() * (profile.gapHi - profile.gapLo)
		-- combo chain (deliver-time payoff; per-catch score is combo-free).
		combo, load = RescueRules.comboOnCatch(R, now, lastCatchAt, combo, load)
		lastCatchAt = now
		-- per-catch score.
		local style = profile.styleLo + rnd() * (profile.styleHi - profile.styleLo)
		local tier = ""
		local roll = rnd()
		if roll < profile.blazingP then tier = "BLAZING"
		elseif roll < profile.blazingP + profile.swiftP then tier = "SWIFT" end
		points = points + RescueRules.catchScore(R, 1, style, tier)
		carried = carried + 1
		-- deliver when the load fills to the profile's bank size.
		if carried >= profile.bankAt then
			local pay = RescueRules.deliverPayout(R, carried, load)
			points = points + pay.points
			delivered = delivered + carried
			carried = 0
			load = 1
			combo = 0
			if not perfectAt and delivered >= R.perfectTenAt then
				perfectAt = profile.perfectAt -- seconds left when the 10th landed
			end
		end
	end
	-- final partial deliver.
	if carried > 0 then
		local pay = RescueRules.deliverPayout(R, carried, load)
		points = points + pay.points
		delivered = delivered + carried
		if not perfectAt and delivered >= R.perfectTenAt then
			perfectAt = profile.perfectAt
		end
	end
	-- perfect-ten finale (quantize before factor).
	if perfectAt then
		local factor = RescueRules.perfectFactor(R, perfectAt)
		points = RescueRules.finaleApply(R, points, factor).finalScore
	end
	return points / av -- acorns
end

H.test("§3.2 economy: casual ~150–350, skilled ~1200–2200, ratio < 10:1 (seeded MC)", function()
	local casual = {
		-- 8 catches, banked as one 8-deliver, low style, occasional swift; never reaches 10 → no finale.
		-- Gaps straddle comboWindow (4s) so a casual chain lands ~combo 2 (the §3.2 worked example ~230).
		catches = 8, bankAt = 8, gapLo = 3.0, gapHi = 6.0, styleLo = 1.1, styleHi = 1.5,
		swiftP = 0.3, blazingP = 0.08, perfectAt = 0,
	}
	local skilled = {
		-- gaps straddle comboWindow (4s) so the chain averages ~combo 4 (the §3.2 worked example),
		-- not a perfect 6-cap; one 10-deliver, ~35s left → ×3 time factor.
		catches = 10, bankAt = 10, gapLo = 2.5, gapHi = 5.0, styleLo = 1.4, styleHi = 2.0,
		swiftP = 0.4, blazingP = 0.2, perfectAt = 35,
	}
	local function meanOver(profile, seed0)
		local rnd = lcg(seed0)
		local sum = 0
		local N = 500
		for i = 1, N do
			-- re-seed per round for independence but deterministically.
			sum = sum + simRound(lcg(seed0 + i * 7919), profile)
		end
		return sum / N
	end
	local casualMean = meanOver(casual, 11)
	local skilledMean = meanOver(skilled, 999)
	print(("      [economy] casual ~%.0f acorns, skilled ~%.0f acorns, ratio %.2f")
		:format(casualMean, skilledMean, skilledMean / casualMean))
	H.between(casualMean, 150, 350, "casual round yields ~150–350 acorns")
	H.between(skilledMean, 1200, 2200, "skilled perfect-ten yields ~1200–2200 acorns")
	H.ok(skilledMean / casualMean < 10, ("skilled:casual ratio %.2f < 10:1"):format(skilledMean / casualMean))
end)

--------------------------------------------------------------------------------
-- THE PARITY ORACLE (design §6) — OLD inline formulas restated VERBATIM, EXACT equality vs RescueRules.
--------------------------------------------------------------------------------
-- Each `old_*` below is copied from the live line cited; asserted equal to the extracted function over a
-- 1,000-point randomized sweep. A transcription that diverged fails here — the whole point of the gate.
-- clamp helper matching the live clients' `clamp` (BirdController uses math.clamp under the alias).
local function clamp(x, lo, hi)
	return math.min(math.max(x, lo), hi)
end

-- OLD: server accept gate — RescueServer:552
local function old_serverGate(speed)
	return (R.triggerRadius or 28) * (R.catchGateMult or 3.5) + speed * (R.catchGateLatency or 0.25)
end

-- OLD: client effective radius — BirdController:1911-1916 (isFtue = catchCount < ftueCatches; :1897)
local function old_effRadius(speed, glideSp, catchCount)
	local isFtue = catchCount < (R.ftueCatches or 3)
	local effRadius = (R.triggerRadius or 28)
	if isFtue then effRadius = effRadius * (R.ftueRadiusMult or 1.5) end
	effRadius = effRadius * (1 + clamp((speed - glideSp) / math.max(1, glideSp), 0, 1) * (R.scoopSpeedGain or 0.25))
	return effRadius
end

-- OLD: client closing gate — BirdController:1897-1899
local function old_closingGate(glide, catchCount)
	local isFtue = catchCount < (R.ftueCatches or 3)
	local gateFrac = isFtue and (R.ftueGateFrac or R.closingGateFrac or 0.3) or (R.closingGateFrac or 0.3)
	return gateFrac * glide
end

-- OLD: client speedTier — BirdController:1520-1522
local function old_speedTier(closing, glide)
	local tier = ""
	if closing >= (R.blazingFrac or 0.9) * glide then tier = "BLAZING"
	elseif closing >= (R.swiftFrac or 0.6) * glide then tier = "SWIFT" end
	return tier
end

-- OLD: server per-catch score — RescueServer:570-588 (combo NOT applied per-catch)
local function old_catchScore(rarityMult, styleMult, speedTier)
	local mult = math.clamp(tonumber(styleMult) or 1, 1, R.styleMultMax or 3)
	local rarity = rarityMult or 1
	local energyMult = 1
	if speedTier == "BLAZING" then energyMult = R.blazingMult or 2.0
	elseif speedTier == "SWIFT" then energyMult = R.swiftMult or 1.5 end
	return math.floor((R.basePoints or 100) * rarity * mult * energyMult + 0.5)
end

-- OLD: server combo — RescueServer:577-587
local function old_combo(now, lastCatchAt, combo, loadCombo)
	local newCombo
	if now - (lastCatchAt or -1e9) <= (R.comboWindow or 4) then
		newCombo = math.min((combo or 0) + 1, R.comboMax or 6)
	else
		newCombo = 1
	end
	local newLoad = math.max(loadCombo or 1, newCombo)
	return newCombo, newLoad
end

-- OLD: server deliver payout — RescueServer:625-630
local function old_deliverPoints(carry, loadCombo)
	local cmb = math.max(1, math.floor(loadCombo or 1))
	return carry * carry * (R.acornValue or 10) * cmb, cmb
end

-- OLD: perfect-ten factor — RescueServer:640-643 / :689-694 (identical)
local function old_factor(perfectAt)
	local f = 2
	if perfectAt >= (R.timeFactor4At or 60) then f = 4
	elseif perfectAt >= (R.timeFactor3At or 30) then f = 3 end
	return f
end

-- OLD: quantize-before-factor — RescueServer:686
local function old_quantize(score)
	local av = R.acornValue or 10
	return math.floor(score / av + 0.5) * av
end

-- OLD: claim TTL — BirdController:1358-1363
local function old_claimActive(claims, id, now)
	local at = id and claims[id]
	if not at then return false end
	if now - at > (R.claimTTL or 3) then claims[id] = nil; return false end
	return true
end

H.test("PARITY ORACLE: RescueRules == the OLD inline formulas over a 1,000-point sweep", function()
	local rnd = lcg(424242)
	for i = 1, 1000 do
		local speed = rnd() * 320
		local glide = GLIDE
		local catchCount = (rnd() < 0.4) and math.floor(rnd() * 3) or (3 + math.floor(rnd() * 5))
		local closing = rnd() * 320
		local carry = 1 + math.floor(rnd() * 10)
		local loadCombo = 1 + math.floor(rnd() * 6)
		local rarity = 1 + math.floor(rnd() * 3)
		local style = 0.5 + rnd() * 3.5
		local now = rnd() * 500
		local lastCatchAt = now - rnd() * 10
		local combo = math.floor(rnd() * 6)
		local perfectAt = rnd() * 120
		local raggedScore = math.floor(rnd() * 5000)

		-- acceptEnvelope (integer-free, exact float) — EXACT equality.
		H.approx(RescueRules.acceptEnvelope(R, speed), old_serverGate(speed), 1e-9, "acceptEnvelope @" .. i)
		-- effectiveRadius — EXACT.
		H.approx(RescueRules.effectiveRadius(R, speed, glide, catchCount), old_effRadius(speed, glide, catchCount), 1e-9, "effRadius @" .. i)
		-- closingGate — EXACT.
		H.approx(RescueRules.closingGate(R, glide, catchCount), old_closingGate(glide, catchCount), 1e-9, "closingGate @" .. i)
		-- speedTier — string equality.
		H.eq(RescueRules.speedTier(R, closing, glide), old_speedTier(closing, glide), "speedTier @" .. i)
		-- catchScore — INTEGER path, EXACT.
		local tier = old_speedTier(closing, glide)
		H.eq(RescueRules.catchScore(R, rarity, style, tier), old_catchScore(rarity, style, tier), "catchScore @" .. i)
		-- combo — integer pair, EXACT.
		local nc, nl = RescueRules.comboOnCatch(R, now, lastCatchAt, combo, loadCombo)
		local onc, onl = old_combo(now, lastCatchAt, combo, loadCombo)
		H.eq(nc, onc, "combo @" .. i)
		H.eq(nl, onl, "loadCombo @" .. i)
		-- deliverPayout — INTEGER, EXACT.
		local pay = RescueRules.deliverPayout(R, carry, loadCombo)
		local oldPts, oldCmb = old_deliverPoints(carry, loadCombo)
		H.eq(pay.points, oldPts, "deliver points @" .. i)
		H.eq(pay.combo, oldCmb, "deliver combo @" .. i)
		H.eq(pay.n, carry, "deliver n @" .. i)
		-- perfectFactor — INTEGER, EXACT.
		H.eq(RescueRules.perfectFactor(R, perfectAt), old_factor(perfectAt), "factor @" .. i)
		-- quantize — EXACT.
		H.eq(RescueRules.quantizeAcorns(R, raggedScore), old_quantize(raggedScore), "quantize @" .. i)
		-- finaleApply == quantize-then-multiply (bug 12) — EXACT.
		local fin = RescueRules.finaleApply(R, raggedScore, old_factor(perfectAt))
		H.eq(fin.preFactorScore, old_quantize(raggedScore), "finale preFactor @" .. i)
		H.eq(fin.finalScore, old_quantize(raggedScore) * old_factor(perfectAt), "finale final @" .. i)
	end
	-- claim TTL parity across a couple of clock offsets (side-effecting clear must match too).
	for i = 1, 1000 do
		local newClaims, oldClaims = {}, {}
		local id = 1 + math.floor(rnd() * 5)
		local markAt = rnd() * 100
		newClaims[id] = markAt
		oldClaims[id] = markAt
		local now = markAt + rnd() * (2 * (R.claimTTL or 3))
		H.eq(RescueRules.claimActive(newClaims, id, now, R), old_claimActive(oldClaims, id, now), "claimActive @" .. i)
		-- the cleared/kept state must also match (both clear past TTL).
		H.eq(newClaims[id], oldClaims[id], "claim entry state @" .. i)
	end
end)

--------------------------------------------------------------------------------
-- S43 — catchChime. Chad: "the sounds pinging me after I catch just a few
-- squirrels — it should only ping when I have 10/10."
--------------------------------------------------------------------------------
H.test("catchChime: silent on every catch until the load FILLS, then fires exactly once", function()
	local R = GameConfig.Rescue
	local cap = R.carryCapacity or 10
	H.ok(cap >= 2, "fixture: capacity must be more than one or this rule is vacuous")
	local fired = 0
	for n = 1, cap do
		local ring = RescueRules.catchChime(R, n, cap)
		if n < cap then
			H.eq(ring, false, ("catch %d/%d must be SILENT — this is the nagging ping Chad rejected"):format(n, cap))
		else
			H.eq(ring, true, ("the catch that fills the load (%d/%d) must ring"):format(n, cap))
		end
		if ring then fired += 1 end
	end
	H.eq(fired, 1, "exactly ONE chime per full load, not one per squirrel")
end)

H.test("catchChime: capacity falls back sanely, and the legacy flag restores the old behaviour", function()
	local R = GameConfig.Rescue
	-- a nil server capacity must fall back to the config, never to a tiny default that would make the
	-- chime fire at 3/10 (the exact complaint, reintroduced by a fallback bug)
	H.eq(RescueRules.catchChime(R, 3, nil), false, "3 riders with an unknown capacity must not ring")
	H.eq(RescueRules.catchChime(R, R.carryCapacity or 10, nil), true, "a full load rings on the config fallback")
	local legacy = table.clone(R)
	legacy.chimeEveryCatch = true
	H.eq(RescueRules.catchChime(legacy, 1, 10), true, "the comparison flag restores the per-catch ping")
	H.eq(R.chimeEveryCatch, false, "…and it ships OFF, which is what Chad asked for")
end)

--------------------------------------------------------------------------------
-- S44 — THE PING LAW. The tests above are GREEN and were green through every one of
-- Chad's six complaints, because `catchChime` governs ONE of the game's bell emitters.
-- playGotcha (every catch, at a LOUDER 0.6), playWoohoo (every catch), the crew choir
-- (every ~1.7s from the first rider) and playCount/the deliver chord on PARTIAL loads
-- all rang the same electronicpingshort.wav. "Ping" names the ASSET, not a function.
--
-- So the law is asserted over the whole SET of emitters, not one predicate: sweep every
-- event in RescueRules.SOUND_EVENTS × every carry below capacity and demand that no cue
-- is ping-class. SOUND_EVENTS is owned by the module, so a newly-voiced event is under
-- the law automatically — you cannot add a bell below 10/10 and stay green.
--------------------------------------------------------------------------------
H.test("PING LAW: no sound event may ring a BELL below a full load", function()
	local R = GameConfig.Rescue
	local cap = R.carryCapacity or 10
	H.ok(#RescueRules.SOUND_EVENTS >= 8, "fixture: the event list must be populated or this sweep is vacuous")
	local checked = 0
	for _, ev in ipairs(RescueRules.SOUND_EVENTS) do
		for carry = 0, cap - 1 do
			local cls = RescueRules.soundClass(R, ev, { carry = carry, capacity = cap })
			H.ok(cls ~= "ping",
				("%s rings a PING at %d/%d — Chad's law, asked six times: bells ONLY at 10/10"):format(ev, carry, cap))
			checked += 1
		end
	end
	H.ok(checked >= 80, "the sweep must actually cover the event × carry space")
end)

H.test("PING LAW: the celebration is PRESERVED, not deleted — a full load DOES ring", function()
	local R = GameConfig.Rescue
	local cap = R.carryCapacity or 10
	for _, ev in ipairs({ "fillChime", "jingle", "deliverFanfare", "countNote" }) do
		H.eq(RescueRules.soundClass(R, ev, { carry = cap, capacity = cap }), "ping",
			ev .. " must ring at a FULL load — scarcity is what makes 10/10 the jackpot")
	end
	-- …and the per-catch layer is RE-VOICED, never silenced: a catch still lands hard.
	H.eq(RescueRules.soundClass(R, "catchAccent", { carry = 3, capacity = cap }), "snap",
		"the catch accent must still FIRE (as a talon snap) — a silent catch is not the fix")
	H.eq(RescueRules.soundClass(R, "woohoo", { carry = 3, capacity = cap }), "swoosh",
		"the woohoo must still fire, as a rising rush of air")
	H.eq(RescueRules.soundClass(R, "chirp", { carry = 6, capacity = cap }), "snap",
		"crew chatter must still fire, as chitter clicks — 'the crew is the choir' survives")
end)

H.test("PING LAW: the legacy A/B flags restore each old voice, and all three ship OFF", function()
	local R = GameConfig.Rescue
	local cap = R.carryCapacity or 10
	for flag, ev in pairs({ gotchaOnPing = "catchAccent", woohooOnPing = "woohoo", chirpOnPing = "chirp" }) do
		H.eq(R[flag], false, flag .. " must ship FALSE — that is the whole point of the fix")
		local legacy = table.clone(R)
		legacy[flag] = true
		H.eq(RescueRules.soundClass(legacy, ev, { carry = 1, capacity = cap }), "ping",
			flag .. " must restore the old bell for an A/B comparison")
	end
end)

-- THE ESCAPE HATCH. The law above only binds sounds that go THROUGH the policy. Hand-wiring a fresh
-- `playSound(SFX_PING, …)` inline in the client is the exact move that regressed this five times, and
-- no pure test can see it. So pin it by source text: SFX_PING may be NAMED (declaration + the class
-- map) but never PLAYED directly.
H.test("PING LAW: no inline playSound(SFX_PING) may bypass the policy in BirdController", function()
	local fs = require("@lune/fs")
	local src = fs.readFile("src/client/BirdController.client.luau")
	H.ok(#src > 1000, "fixture: the client source must actually have been read")
	local offenders = {}
	local n = 0
	for line in src:gmatch("[^\r\n]+") do
		n += 1
		-- comments may NAME the pattern (this rule is documented at the seam); only real code counts
		if not line:match("^%s*%-%-") and line:match("playSound%s*%(%s*SFX_PING") then
			offenders[#offenders + 1] = ("line %d: %s"):format(n, line:match("^%s*(.-)%s*$"))
		end
	end
	H.eq(#offenders, 0,
		"a bell is being played outside RescueRules.soundClass — route it through playCue instead:\n    "
			.. table.concat(offenders, "\n    "))
	-- and the seam itself must still exist (so deleting playCue can't make this test vacuously pass)
	H.ok(src:find("RescueRules.soundClass", 1, true) ~= nil,
		"BirdController must consume the pure policy — if this fails the law has no teeth")
end)

--------------------------------------------------------------------------------
-- S44 — THE SKY GEM. Chad: "I can barely see the squirrels, they render in after 30s."
-- The two halves of the read are asserted as GEOMETRY, before he ever flies:
--   "visible from altitude"   → angular size stays in a legible band across the whole approach
--   "never occludes up close" → at catch range the projection is bit-identical to Stage 1
-- Stage 1 shipped with neither (its gate was the dive-in read only), which is how the long-range
-- signal was traded away without anyone noticing.
--------------------------------------------------------------------------------
local PX_PER_RAD = 771   -- 1080p at Camera.baseFOV 70° vertical: (1080/2) / tan(35°) ≈ 771 px/radian

H.test("SKY GEM: ships INERT — with the flag off the Stage-1 gem is untouched at every range", function()
	local R = GameConfig.Rescue
	H.eq(R.skyGem, false, "skyGem must ship FALSE — Chad flies the change, he doesn't inherit it")
	for _, d in ipairs({ 0, 40, 70, 130, 260, 600, 1140, 2600 }) do
		local p = RescueRules.skyGemProjection(R, d, R.chevronSize or 2.2, 40)
		H.eq(p.size, R.chevronSize or 2.2, ("inert: size must not move at %d studs"):format(d))
		H.eq(p.y, 40, ("inert: the gem must not lift at %d studs"):format(d))
		H.eq(p.t, 0, "inert: the far-ness blend must be zero")
	end
end)

H.test("SKY GEM: never occludes the critter — at catch range it IS the Stage-1 gem", function()
	local R = table.clone(GameConfig.Rescue)
	R.skyGem = true
	local base = R.chevronSize or 2.2
	for _, d in ipairs({ 0, 10, 35, 69, 70 }) do
		local p = RescueRules.skyGemProjection(R, d, base, 40)
		H.eq(p.size, base, ("at %d studs (inside skyGemNear) the gem must be its BUILT size"):format(d))
		H.eq(p.y, 40, ("at %d studs the gem must sit on the critter's head, unlifted"):format(d))
	end
end)

H.test("SKY GEM: visible from altitude — angular size stays legible across the whole approach", function()
	local R = table.clone(GameConfig.Rescue)
	R.skyGem = true
	local base = R.chevronSize or 2.2
	local worst = math.huge
	for d = R.skyGemFar or 260, 2600, 20 do
		local p = RescueRules.skyGemProjection(R, d, base, 40)
		local px = PX_PER_RAD * (p.size / d)
		worst = math.min(worst, px)
		H.ok(px >= 8, ("at %d studs the gem is %.1f px — that is the ~2.4 px Chad could not see"):format(d, px))
		H.ok(px <= 40, ("at %d studs the gem is %.1f px — a marker, not a billboard"):format(d, px))
	end
	print(("      [skygem] worst on-screen size over 260-2600 studs: %.1f px (Stage 1 at 1140 studs: %.1f px)")
		:format(worst, PX_PER_RAD * (base / 1140)))
end)

H.test("SKY GEM: at range the gem CLEARS the worst-case tree — the under-canopy half becomes findable", function()
	local R = table.clone(GameConfig.Rescue)
	R.skyGem = true
	-- buildTree's worst case: trunk 115 + crown blob 35 = 150. An under-canopy perch sits at Y 22-38,
	-- so its Stage-1 gem (base + chevronY 14) lives at ~36-52 — entirely beneath the leaves.
	local TREE_TOP = 150
	for _, baseY in ipairs({ 36, 45, 52, 121 }) do           -- under-canopy perches … and a crown perch
		for _, d in ipairs({ 260, 600, 1140, 2600 }) do
			local p = RescueRules.skyGemProjection(R, d, R.chevronSize or 2.2, baseY)
			local bottom = p.y - p.size * (R.chevronAspect or 1.6) * 0.5
			H.ok(bottom >= TREE_TOP - 1e-6,
				("baseY %d @ %d studs: gem bottom %.1f is INSIDE the canopy (top %d) — still invisible")
					:format(baseY, d, bottom, TREE_TOP))
		end
	end
end)

H.test("SKY GEM: the projection is monotone, capped, and never pulls a gem DOWN", function()
	local R = table.clone(GameConfig.Rescue)
	R.skyGem = true
	local base = R.chevronSize or 2.2
	local prevSize, prevY = -1, -1
	for d = 0, 3000, 25 do
		local p = RescueRules.skyGemProjection(R, d, base, 45)
		H.ok(p.size >= prevSize - 1e-9, ("size must never shrink as you pull away (at %d)"):format(d))
		H.ok(p.y >= prevY - 1e-9, ("the gem must never sink as you pull away (at %d)"):format(d))
		H.ok(p.size <= (R.skyGemMaxSize or 34) + 1e-9, "size must respect skyGemMaxSize")
		H.ok(p.y >= 45 - 1e-9, "the projection must never pull a gem BELOW its Stage-1 height")
		prevSize, prevY = p.size, p.y
	end
	-- a gem already above the clear height is left alone (max(0, …)), not dragged down to it
	local high = RescueRules.skyGemProjection(R, 2000, base, 400)
	H.eq(high.y, 400, "a gem already above the treeline must not be pulled down to skyGemClearY")
end)

H.test("SKY GEM: rare gems keep their size ADVANTAGE at range (triage-by-value survives)", function()
	local R = table.clone(GameConfig.Rescue)
	R.skyGem = true
	-- the server builds gold/rainbow gems 1.35× (RescueServer.buildBeacon), so the projection must
	-- read each gem's OWN base, never a config literal — else every gem converges to one size far out
	-- and the rare read dies exactly where it matters most: choosing a target from altitude.
	local common = RescueRules.skyGemProjection(R, 900, R.chevronSize or 2.2, 40)
	local rare = RescueRules.skyGemProjection(R, 900, (R.chevronSize or 2.2) * 1.35, 40)
	H.ok(rare.size > common.size,
		"a rare gem must still read BIGGER at 900 studs — triage-by-value is the point of the hue+size channel")
end)

--------------------------------------------------------------------------------
-- B4.1 — SOLID TREES. World-gen runs in a server script no Lune tier can fly, but
-- the DECISIONS it makes (which parts are solid, how a bonk is flavoured) are pure
-- and gated here. The feel — delicious roof vs sticky ceiling — stays Chad's flight.
--------------------------------------------------------------------------------
H.test("treeQueryable: the three modes have exactly the right truth table", function()
	local function q(mode, kind) return RescueRules.treeQueryable({ treeCollision = mode }, kind) end
	-- off = the ghost forest, byte-identical to pre-B4
	H.eq(q("off", "Trunk"), false, "off: trunks are ghosts")
	H.eq(q("off", "Canopy"), false, "off: canopy is a ghost")
	-- trunks = wood solid, leaves soft
	H.eq(q("trunks", "Trunk"), true, "trunks: wood is solid")
	H.eq(q("trunks", "Canopy"), false, "trunks: leaves stay soft")
	-- full = both solid (the canopy roof)
	H.eq(q("full", "Trunk"), true, "full: trunk solid")
	H.eq(q("full", "Canopy"), true, "full: canopy solid")
	-- a nil / unknown mode must default to the safe ghost forest, never to solid
	H.eq(RescueRules.treeQueryable(nil, "Trunk"), false, "nil cfg → ghost (never accidentally solid)")
	H.eq(RescueRules.treeQueryable({ treeCollision = "wat" }, "Trunk"), false, "unknown mode → ghost")
	H.eq(q("full", "Beacon"), false, "only Trunk/Canopy are ever made solid — not other named parts")
end)

H.test("surfaceKind: canopy scatters leaves, every other solid throws the feather oof", function()
	H.eq(RescueRules.surfaceKind("Canopy"), "leaf", "a treetop bonk scatters leaves")
	H.eq(RescueRules.surfaceKind("Trunk"), "feather", "a trunk bonk is the certified feather oof")
	H.eq(RescueRules.surfaceKind("Mesa"), "feather", "the mesa is a feather oof")
	H.eq(RescueRules.surfaceKind("Terrain"), "feather", "the ground is a feather oof")
	H.eq(RescueRules.surfaceKind(""), "feather", "an unnamed/unknown surface falls back to feather, never errors")
end)

H.test("B4.1 ships INERT: treeCollision is off (the ghost forest, byte-identical)", function()
	H.eq(GameConfig.Rescue.treeCollision, "off",
		"treeCollision must ship off — solid trees are a Chad-flown feel question, one word to enable")
end)

--------------------------------------------------------------------------------
-- "Never stomp a beat" — the three-flag predicate behind the terrain-oof
-- suppression. A first attempt checked only `catch` and was red-team BLOCKED:
-- crew-catch timers outlive the sacred beat and hop-off is its own ritual.
--------------------------------------------------------------------------------
H.test("beatActive: ALL THREE sacred beats suppress, not just the slow-mo catch", function()
	H.eq(RescueRules.beatActive(nil, 0, nil), false, "no beat running → the oof is free to fire")
	H.eq(RescueRules.beatActive({}, 0, nil), true, "the slow-mo catch is a beat")
	H.eq(RescueRules.beatActive(nil, 1, nil), true, "a crew catch STILL IN FLIGHT is a beat (it outlives the catch)")
	H.eq(RescueRules.beatActive(nil, 3, nil), true, "several crew catches count")
	H.eq(RescueRules.beatActive(nil, 0, {}), true, "the hop-off tally ceremony is a beat")
	H.eq(RescueRules.beatActive({}, 2, {}), true, "all at once still suppresses")
	-- falsy inputs must never be read as truthy beats (the bug that would silence the oof forever)
	H.eq(RescueRules.beatActive(false, 0, false), false, "explicit false flags are not beats")
	H.eq(RescueRules.beatActive(nil, nil, nil), false, "a nil crew count is zero, not a permanent beat")
end)
