--!nonstrict
--[[
	tests/danger.spec.luau — the STAGE 3a headless gate (docs/KID-LEGIBILITY-PLAN.md §Stage-3).

	Stage 3 makes urgency VISCERAL by putting it on the critter: the server stamps a Danger 0/1/2
	attribute from pure fire-grid arithmetic (`FireGrid.dangerAt`) and the client renders it in Stage 1's
	shipped pose/halo vocabulary. The read is "that squirrel is TERRIFIED — get HIM first."

	The design's load-bearing claim is that danger measures distance to any NON-GREEN cell (not just
	BURNING), which makes escalation MONOTONE NON-DECREASING BY CONSTRUCTION — a squirrel that got
	scared cannot un-scare when the front passes and its cells cool to EMBER. These tests exist to prove
	that claim holds over real seeded burns, and that FEAR LEADS LOSS (panic must be pressure you can
	still act on, never a notification that a grove is already gone — the "theft" feeling Gate B rejected).

	What this CANNOT judge: whether fast waving + bigger hops + a red flashing halo READ as fear rather
	than excitement at dive speed. That is Chad's Play (Tier 5) — a refinement question, not viability.
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Vector3 = Loader.Vector3

local GameConfig = Loader.load("GameConfig")
local FireGrid = Loader.load("FireGrid")

local NEAR = GameConfig.Fire.dangerNearR or 140
local FAR = GameConfig.Fire.dangerFarR or 280

-- The shipped ember_valley placement shape (4 discs, r130).
local function groves()
	return {
		{ center = Vector3.new(700, 0, 0), radius = 130 },
		{ center = Vector3.new(-600, 0, 400), radius = 130 },
		{ center = Vector3.new(100, 0, -800), radius = 130 },
		{ center = Vector3.new(-300, 0, 900), radius = 130 },
	}
end

local function newGrid(seed, wind)
	return FireGrid.new(GameConfig.Fire, seed, wind or Vector3.new(1, 0, 0), groves(), GameConfig.Rescue.deliverPos)
end

--------------------------------------------------------------------------------
-- 1) THRESHOLD CORRECTNESS — the 0/1/2 bands are exactly where the dials say.
--------------------------------------------------------------------------------
H.test("dangerAt: bands land exactly on dangerNearR / dangerFarR from a single lit cell", function()
	local grid = newGrid(1)
	-- light one cell and recover its true centre, so probes are measured from the real geometry.
	H.ok(FireGrid.igniteAt(grid, 600, 0), "seed cell ignited (it must be burnable)")
	local lit = FireGrid.burningCells(grid, 1)
	-- it is SMOLDER not BURNING yet, so find the centre by scanning the touched cell instead.
	local cxCentre, czCentre
	for idx = 1, grid.N * grid.N do
		if grid.state[idx] ~= FireGrid.GREEN then
			local cz = math.floor((idx - 1) / grid.N) + 1
			local cx = (idx - 1) % grid.N + 1
			cxCentre = (cx - 1 + 0.5) * grid.cellSize - grid.gridHalf
			czCentre = (cz - 1 + 0.5) * grid.cellSize - grid.gridHalf
			break
		end
	end
	H.ok(cxCentre ~= nil, "found the lit cell's centre")
	H.eq(#lit, 0, "a freshly lit cell is SMOLDER, not BURNING (sanity on the fixture)")

	local eps = 4
	H.eq(FireGrid.dangerAt(grid, cxCentre, czCentre), 2, "at the fire itself = PANIC")
	H.eq(FireGrid.dangerAt(grid, cxCentre + NEAR - eps, czCentre), 2, "just inside dangerNearR = PANIC")
	H.eq(FireGrid.dangerAt(grid, cxCentre + NEAR + eps, czCentre), 1, "just outside dangerNearR = worried")
	H.eq(FireGrid.dangerAt(grid, cxCentre + FAR - eps, czCentre), 1, "just inside dangerFarR = worried")
	H.eq(FireGrid.dangerAt(grid, cxCentre + FAR + eps, czCentre), 0, "just outside dangerFarR = calm")
	H.eq(FireGrid.dangerAt(grid, cxCentre + 900, czCentre), 0, "far beyond the scan window = calm")
	H.eq(FireGrid.dangerAt(grid, 99999, 99999), 0, "outside the grid box entirely = calm (no crash)")
end)

--------------------------------------------------------------------------------
-- 2) MONOTONICITY — the named gate. Over many seeded burns, no probe's danger EVER
--    decreases, including as cells pass BURNING -> EMBER (the failure this design kills).
--------------------------------------------------------------------------------
H.test("dangerAt: escalation is MONOTONE non-decreasing over 24 seeded burns (incl. BURNING→EMBER)", function()
	local winds = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0.6, 0, 0.8), Vector3.new(-0.7, 0, -0.7) }
	-- probes: every grove centre + a ring through the burnable annulus (where the front actually goes).
	local probes = {}
	for _, g in ipairs(groves()) do probes[#probes + 1] = { g.center.X, g.center.Z } end
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2
		probes[#probes + 1] = { math.cos(a) * 1100, math.sin(a) * 1100 }
	end

	local rounds, everReached2, emberSeen = 0, 0, false
	for s = 1, 6 do
		for _, wind in ipairs(winds) do
			rounds += 1
			local grid = newGrid(s * 1013, wind)
			FireGrid.seedUpwind(grid)
			local last = {}
			for i = 1, #probes do last[i] = 0 end
			for _ = 1, 300 do
				FireGrid.step(grid, 1.0)
				for i, p in ipairs(probes) do
					local d = FireGrid.dangerAt(grid, p[1], p[2])
					H.ok(d >= last[i],
						("danger DECREASED at probe %d (%d -> %d) — the non-GREEN distance claim is broken")
							:format(i, last[i], d))
					if d == 2 then everReached2 += 1 end
					last[i] = d
				end
			end
			local st = FireGrid.stats(grid)
			if (st.ember or 0) > 0 then emberSeen = true end
		end
	end

	H.eq(rounds, 24, "ran every seed x wind combination")
	H.ok(emberSeen, "the burns actually produced EMBER cells (else the cool-down case went untested)")
	H.ok(everReached2 > 0, "at least one probe reached PANIC (else monotonicity passes vacuously)")
end)

--------------------------------------------------------------------------------
-- 3) FEAR LEADS LOSS — panic must arrive BEFORE the grove is cut off, so it is
--    pressure you can act on rather than a notification of theft.
--------------------------------------------------------------------------------
H.test("fear LEADS loss: the WORST-CASE perch in a grove panics before that grove is cut off", function()
	local winds = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0.6, 0, 0.8), Vector3.new(-0.7, 0, -0.7) }
	local observed, leads, leadSum, minLead = 0, 0, 0, math.huge

	-- RED-TEAM HARDENING: probe the grove RIM, not its centre. The game stamps danger at
	-- `s.perch.pos` (RescueServer stepFire) and perches sit anywhere in the disc, up to groveRadius
	-- from the centre — so a centre probe measures the EASIEST case and flatters the result (a
	-- cut-off grove's centre is panicking almost by geometry). A grove's panic time is therefore the
	-- time its LAST rim point reaches 2: the worst perch anyone could actually be standing on.
	local RIM = 130 -- = placement.groveRadius
	local function grovePanicked(grid, gv)
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2
			if FireGrid.dangerAt(grid, gv.center.X + math.cos(a) * RIM, gv.center.Z + math.sin(a) * RIM) ~= 2 then
				return false
			end
		end
		return true
	end

	for s = 1, 8 do
		for _, wind in ipairs(winds) do
			local grid = newGrid(s * 733 + 11, wind)
			FireGrid.seedUpwind(grid)
			local gs = groves()
			local panicAt, cutAt = {}, {}
			for t = 1, 300 do
				FireGrid.step(grid, 1.0)
				local cut = FireGrid.cutOffGroves(grid)
				for g, gv in ipairs(gs) do
					if not panicAt[g] and grovePanicked(grid, gv) then
						panicAt[g] = t
					end
					if not cutAt[g] and cut[g] then cutAt[g] = t end
				end
			end
			for g = 1, #gs do
				if cutAt[g] then
					observed += 1
					if panicAt[g] and panicAt[g] < cutAt[g] then
						leads += 1
						local lead = cutAt[g] - panicAt[g]
						leadSum += lead
						if lead < minLead then minLead = lead end
					end
				end
			end
		end
	end

	print(("      [danger] cut-off groves observed %d · worst-perch panic LED in %d · mean lead %.1fs · MIN lead %ds")
		:format(observed, leads, leads > 0 and (leadSum / leads) or 0, minLead < math.huge and minLead or -1))

	H.ok(observed > 0, "some grove actually got cut off (else this gate is vacuous)")
	H.eq(leads, observed, "every cut-off grove was PANICKING first — fear must never arrive after the loss")
	H.ok(leadSum / leads >= 10, ("mean warning lead %.1fs is under the 10s the design promises"):format(leadSum / leads))
	-- MIN floor, not just the mean (red-team: a mean-only gate let a mutant collapse worst-case warning
	-- to 1s while staying green). A worst-case perch must get SOME actionable warning, every time.
	H.ok(minLead >= 3, ("worst-case warning was only %ds — a perch can be lost with no time to react"):format(minLead))
end)

--------------------------------------------------------------------------------
-- 4) COST + DIAL SANITY — the §3.4 bound the design promised, and the revert gate.
--------------------------------------------------------------------------------
H.test("dangerAt: bounded scan window + coherent dials + the urgencyTells revert gate exists", function()
	local w = math.ceil(FAR / GameConfig.Fire.cellSize)
	local cells = (2 * w + 1) ^ 2
	print(("      [danger] scan window %dx%d = %d cells/call (near %d, far %d, cell %d)")
		:format(2 * w + 1, 2 * w + 1, cells, NEAR, FAR, GameConfig.Fire.cellSize))
	H.ok(cells <= 200, ("scan window %d cells exceeds the design's bounded-cost promise"):format(cells))
	H.ok(NEAR < FAR, "dangerNearR must be inside dangerFarR or the bands invert")
	H.ok(NEAR > 130, "PANIC radius must exceed the grove radius, else cut-off can beat panic (test 3)")
	H.eq(type(GameConfig.Fire.urgencyTells), "boolean", "the one-line revert gate exists and is a boolean")

	-- The gate is a SERVER write-gate, so its off-state cannot be exercised headlessly. What IS
	-- provable: dangerAt is a pure read that does not consult the gate — so flipping urgencyTells
	-- can only stop the attribute being written, never change the arithmetic underneath.
	local grid = newGrid(5)
	FireGrid.igniteAt(grid, 600, 0)
	local before = FireGrid.dangerAt(grid, 600, 0)
	local saved = GameConfig.Fire.urgencyTells
	GameConfig.Fire.urgencyTells = not saved
	H.eq(FireGrid.dangerAt(grid, 600, 0), before, "dangerAt is pure — the gate cannot alter its result")
	GameConfig.Fire.urgencyTells = saved
end)

--------------------------------------------------------------------------------
-- STAGE 3c — the fire ROAR volume curve. The audio ASSET cannot be verified headlessly
-- (Roblox's 2022 privacy purge means an id is a coin flip — the client prints a per-id
-- verdict instead). What IS provable is the curve: the stateless projection that makes
-- "the roar outlived its fire" arithmetically impossible.
--------------------------------------------------------------------------------
local RescueRules = Loader.load("RescueRules")

H.test("fireRoarVolume: silent with NO fire, silent beyond roarFarR, full inside roarNearR", function()
	local F = GameConfig.Fire
	local maxV = F.roarMaxVol or 0.35
	-- the no-fire case: the client passes math.huge when it finds zero burning cells. This is the
	-- whole audio-saga bug class ("it kept roaring after the fire went out") killed by arithmetic.
	H.eq(RescueRules.fireRoarVolume(F, math.huge), 0, "no burning cells ⇒ SILENT the same frame")
	H.eq(RescueRules.fireRoarVolume(F, 0 / 0), 0, "NaN distance ⇒ silent, never a NaN Volume")
	H.eq(RescueRules.fireRoarVolume(F, F.roarFarR), 0, "at roarFarR ⇒ silent")
	H.eq(RescueRules.fireRoarVolume(F, F.roarFarR + 500), 0, "beyond roarFarR ⇒ silent")
	H.approx(RescueRules.fireRoarVolume(F, F.roarNearR), maxV, 1e-6, "at roarNearR ⇒ full")
	H.approx(RescueRules.fireRoarVolume(F, 0), maxV, 1e-6, "inside the fire ⇒ full, never louder than max")
end)

H.test("fireRoarVolume: monotone non-increasing in distance, always within [0, roarMaxVol]", function()
	local F = GameConfig.Fire
	local maxV = F.roarMaxVol or 0.35
	local prev = math.huge
	for d = 0, (F.roarFarR or 900) + 200, 5 do
		local v = RescueRules.fireRoarVolume(F, d)
		H.finite(v, "volume is finite at d=" .. d)
		H.between(v, 0, maxV, "volume in range at d=" .. d)
		H.ok(v <= prev + 1e-9, ("volume ROSE as the fire got further away (d=%d)"):format(d))
		prev = v
	end
	-- and it must actually vary, else "monotone" passes on a constant.
	local mid = RescueRules.fireRoarVolume(F, (F.roarNearR + F.roarFarR) / 2)
	H.ok(mid > 0, "the mid-range swell is audible")
	-- SHAPE CLASS, not the knob value (red-team: replacing t^gamma with plain t survived every other
	-- assert). Linear gives exactly 0.5·maxVol at the midpoint; a >1 gamma gives less. This pins "the
	-- roar SWELLS as you commit" without freezing roarGamma, which is a feel dial Chad may move.
	H.ok(mid < maxV * 0.5,
		("mid-band volume %.3f ≥ half max — the curve went linear-or-faster, losing the commit swell"):format(mid))
end)

--------------------------------------------------------------------------------
-- B5 — SQUIRREL SQUEAK envelope. The waveform is Chad's ear; what a machine CAN
-- pin is the envelope: bounded range, bounded rate, and a cadence that tightens
-- with Danger so the ear learns triage the same way the eye does.
--------------------------------------------------------------------------------
H.test("squeakVolume: silent beyond squeakHearR, full inside squeakFullR, monotone between", function()
	local R = GameConfig.Rescue
	local maxV = R.squeakMaxVol or 0.5
	H.eq(RescueRules.squeakVolume(R, math.huge), 0, "no squirrel in range ⇒ silent")
	H.eq(RescueRules.squeakVolume(R, 0 / 0), 0, "NaN distance ⇒ silent, never a NaN Volume")
	H.eq(RescueRules.squeakVolume(R, R.squeakHearR), 0, "at the hearing radius ⇒ silent")
	H.eq(RescueRules.squeakVolume(R, R.squeakHearR + 400), 0, "well beyond ⇒ silent")
	H.approx(RescueRules.squeakVolume(R, R.squeakFullR), maxV, 1e-9, "at the full radius ⇒ full")
	H.approx(RescueRules.squeakVolume(R, 0), maxV, 1e-9, "on top of it ⇒ full, never louder")

	local prev = math.huge
	for d = 0, (R.squeakHearR or 260) + 100, 2 do
		local v = RescueRules.squeakVolume(R, d)
		H.finite(v, "finite at d=" .. d)
		H.between(v, 0, maxV, "in range at d=" .. d)
		H.ok(v <= prev + 1e-9, "volume ROSE with distance at d=" .. d)
		prev = v
	end
	-- A squeak must stay small, or it stops reading as a small animal. RED-TEAM F1: this was written as
	-- a RATIO against flapVolBase — but that dial is 1.6 today (Chad S38 "LOUDER again"), so the gate
	-- read 0.5 < 1.75 and a mutation setting the squeak to 1.6 sailed through. Pinned ABSOLUTELY now.
	H.ok(maxV <= 0.6, ("squeakMaxVol %.2f is too loud for a small animal (absolute ceiling 0.6)"):format(maxV))
end)

H.test("squeakInterval: STRICTLY tightens with Danger (the ear learns triage)", function()
	local R = GameConfig.Rescue
	local calm = RescueRules.squeakInterval(R, 0)
	local worried = RescueRules.squeakInterval(R, 1)
	local panic = RescueRules.squeakInterval(R, 2)
	print(("      [squeak] cadence calm %.1fs → worried %.1fs → panic %.1fs (%.1f× more often)")
		:format(calm, worried, panic, calm / panic))
	H.ok(calm > worried, "a worried squirrel must call out more often than a calm one")
	H.ok(worried > panic, "a panicking squirrel must call out more often than a worried one")
	H.ok(panic >= 0.8, "panic cadence must stay above a machine-gun chirp")
	H.ok(calm <= 12, "calm cadence must not be so sparse the wood sounds dead")
	H.eq(RescueRules.squeakInterval(R, nil), calm, "a missing Danger is treated as calm, never as panic")
	H.eq(RescueRules.squeakInterval(R, 5), panic, "danger above 2 clamps to the panic cadence")
end)

H.test("B5 dials are coherent and any configured squeak id is well-formed", function()
	local R = GameConfig.Rescue
	-- RED-TEAM F5: this used to assert the id list was EMPTY — which would have turned the ladder RED
	-- the moment Chad did exactly what the Output warning tells him to do (paste an id and re-Play).
	-- A gate must never fail because the feature started working. Shape is what matters; emptiness is
	-- a documented state, not an invariant.
	H.eq(type(R.squeakAssetIds), "table", "the id list exists")
	for i, id in ipairs(R.squeakAssetIds) do
		H.ok(type(id) == "number" and id > 0 and id == math.floor(id),
			("squeak asset id %d is malformed (%s) — it must be a positive integer asset id")
				:format(i, tostring(id)))
	end
	H.ok((R.squeakMaxPerFrame or 0) >= 1, "the per-frame start cap must be at least 1 or squeaks never fire")
	H.ok((R.squeakFullR or 0) < (R.squeakHearR or 0), "full-volume radius must sit inside the hearing radius")
	H.ok((R.squeakMaxLen or 0) > 0 and (R.squeakMaxLen or 0) <= 5,
		"the asset-length plausibility ceiling must be set and short enough to catch music")
end)

--------------------------------------------------------------------------------
-- B5 SCHEDULE — the rate machinery, now pure (red-team F2: it lived inline in the
-- client, so a mutation deleting the per-frame cap passed the whole suite).
--------------------------------------------------------------------------------
H.test("squeakSchedule: the per-frame BUDGET defers a chirp and never eats it", function()
	local R = GameConfig.Rescue
	local now = 1000
	-- overdue squirrel, but no budget left this frame
	local fired, nextAt = RescueRules.squeakSchedule(R, 7, now, now - 0.1, 2, 0)
	H.eq(fired, false, "with zero budget a squeak must not fire")
	H.approx(nextAt, now - 0.1, 1e-9, "a deferred chirp keeps its deadline — it fires next frame, not never")
	-- with budget it fires
	local fired2 = RescueRules.squeakSchedule(R, 7, now, now - 0.1, 2, 1)
	H.eq(fired2, true, "with budget the same squirrel fires")
end)

H.test("squeakSchedule: a squirrel returning to earshot RESEEDS instead of volleying", function()
	local R = GameConfig.Rescue
	local now = 5000
	-- gone for a minute: its deadline is far in the past. Firing immediately would make every squirrel
	-- in a grove chirp on the same frame the moment you fly back.
	local fired, nextAt = RescueRules.squeakSchedule(R, 3, now, now - 60, 2, 5)
	H.eq(fired, false, "a badly-overdue squirrel must reseed, not fire on the re-approach frame")
	H.ok(nextAt > now, "the reseeded deadline is in the future")
	H.ok(nextAt <= now + RescueRules.squeakInterval(R, 2) + 1e-9, "…and within one interval")
	-- different squirrels reseed to DIFFERENT times (that is the whole point)
	local _, a = RescueRules.squeakSchedule(R, 3, now, now - 60, 2, 5)
	local _, b = RescueRules.squeakSchedule(R, 8, now, now - 60, 2, 5)
	H.ok(math.abs(a - b) > 0.05, "two returning squirrels must not reseed to the same instant")
end)

H.test("squeakSchedule: first contact seeds by DANGER — a panicking newcomer is heard fast", function()
	local R = GameConfig.Rescue
	local now = 10
	local _, calmAt = RescueRules.squeakSchedule(R, 5, now, nil, 0, 5)
	local _, panicAt = RescueRules.squeakSchedule(R, 5, now, nil, 2, 5)
	H.ok(panicAt <= calmAt, "a panicking squirrel must not wait longer than a calm one for its first chirp")
	H.ok(panicAt - now <= RescueRules.squeakInterval(R, 2) + 1e-9,
		"first panic chirp must land within one panic interval, not one CALM interval")
	H.eq(select(1, RescueRules.squeakSchedule(R, 5, now, nil, 2, 5)), false, "seeding never fires immediately")
end)

H.test("squeakSchedule: the interval floor holds even at an absurd jitter, and pitch stays bounded", function()
	local R = GameConfig.Rescue
	local bad = table.clone(R)
	bad.squeakJitter = 3          -- would drive interval*(1+jit*frac) negative without the floor
	local floor = R.squeakMinInterval or 0.6
	for i = 1, 400 do
		local now = 100 + i * 0.37
		local fired, nextAt, pitch = RescueRules.squeakSchedule(bad, i, now, now - 0.01, 2, 5)
		if fired then
			H.ok(nextAt - now >= floor - 1e-9,
				("rescheduled only %.3fs ahead — under the %.2fs machine-gun floor"):format(nextAt - now, floor))
			H.finite(pitch, "pitch is finite")
			H.between(pitch, 0.6, 1.6, "pitch stays in a small-animal band")
		end
	end
end)

H.test("squeakSchedule: always reschedules from NOW, and is deterministic", function()
	local R = GameConfig.Rescue
	local now = 2000
	local fired, nextAt = RescueRules.squeakSchedule(R, 4, now, now - 0.5, 1, 5)
	H.eq(fired, true, "an overdue squirrel within one interval fires")
	H.ok(nextAt > now, "the new deadline is measured from NOW, never from the stale one (no catch-up chirping)")
	local f2, n2 = RescueRules.squeakSchedule(R, 4, now, now - 0.5, 1, 5)
	H.eq(n2, nextAt, "same inputs give the same schedule")
	H.eq(f2, fired, "same inputs give the same decision")
end)
