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
