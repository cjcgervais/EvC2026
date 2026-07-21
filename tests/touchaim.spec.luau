--!nonstrict
--[[
	tests/touchaim.spec.luau — the B7-P1 gate for the pure TouchAimAdapter.

	The adapter's whole claim is that touch is a DELTA SOURCE, not a new control law: whatever it
	returns is fed to the same locked read at BirdController:2495 that the mouse feeds. So the gate
	that matters is a PARITY ORACLE — a scripted drag must produce exactly the delta stream the mouse
	would have produced for the same displacement — plus the band properties, plus the guarantee that
	no lift can leave the cursor turning (the touch analog of the "sound that won't stop" class).

	This runs BEFORE the adapter is wired to anything (`Controls.touchAim = false`, no seam exists
	yet), which is the point: B7-P2's one-line seam is the CHAD GATE, and nothing past it gets built
	until he flies the proof-of-feel and answers DRAG-vs-TAP.

	What this CANNOT judge: whether a finger-drag FEELS like "my eagle chasing my cursor". That is
	P2, in the Studio device emulator, in Chad's hands. Numbers can only prove the adapter is honest.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local GameConfig = Loader.load("GameConfig")
local Touch = Loader.load("TouchAimAdapter")

local CFG = GameConfig.Controls

local function down(x, y) return { active = true, x = x, y = y } end
local UP = { active = false, x = 0, y = 0 }

--------------------------------------------------------------------------------
-- 1) THE PARITY ORACLE — inside the dead-band, a drag IS the mouse.
--------------------------------------------------------------------------------
H.test("PARITY: a drag inside the band yields exactly the mouse's delta (displacement × gain)", function()
	local st = Touch.newState()
	local gain = CFG.touchDragGain or 1.4
	local band = CFG.touchBandPx or 60

	-- land, then walk a path that stays strictly inside the band so the hold regime never engages.
	local path = { { 100, 100 }, { 104, 103 }, { 111, 99 }, { 120, 108 }, { 133, 118 }, { 140, 125 } }
	local dx0, dy0 = Touch.step(st, down(path[1][1], path[1][2]), 1 / 60, CFG)
	H.eq(dx0, 0, "the touch-DOWN frame emits nothing (landing a finger is not a swipe)")
	H.eq(dy0, 0, "the touch-DOWN frame emits nothing (y)")

	local sumX, sumY = 0, 0
	for i = 2, #path do
		local p = path[i]
		-- stay honest: every sample must actually be inside the band, or this is not a parity test.
		local ox, oy = p[1] - path[1][1], p[2] - path[1][2]
		H.ok(math.sqrt(ox * ox + oy * oy) <= band, "fixture sample " .. i .. " stayed inside the dead-band")
		local dx, dy = Touch.step(st, down(p[1], p[2]), 1 / 60, CFG)
		-- THE REAL ORACLE IS PER-FRAME (red-team #4). Downstream is NOT a linear integrator of summed
		-- pixels: each frame's delta becomes an axis-angle rotation about the CAMERA'S CURRENT axes,
		-- then a per-frame cone clamp and the S26 circle clamp — rotations don't commute and the camera
		-- moves between frames, so "equal sums ⇒ equal cursor" is false in general. What makes this
		-- genuinely mouse-parity is the STRONGER property: every frame emits exactly gain × THAT
		-- FRAME'S displacement, which is literally what a mouse tracing the same path emits.
		H.approx(dx, (p[1] - path[i - 1][1]) * gain, 1e-9, "frame " .. i .. " dx == this frame's displacement × gain")
		H.approx(dy, (p[2] - path[i - 1][2]) * gain, 1e-9, "frame " .. i .. " dy == this frame's displacement × gain")
		sumX, sumY = sumX + dx, sumY + dy
	end

	-- Secondary (implied by the per-frame property, kept as a cheap end-to-end sanity check).
	local expX = (path[#path][1] - path[1][1]) * gain
	local expY = (path[#path][2] - path[1][2]) * gain
	H.approx(sumX, expX, 1e-9, "summed dx equals total displacement × gain")
	H.approx(sumY, expY, 1e-9, "summed dy equals total displacement × gain")
end)

H.test("PARITY: path-independence — the integrated delta depends only on start and end", function()
	local gain = CFG.touchDragGain or 1.4
	local band = CFG.touchBandPx or 60
	local function walk(samples)
		local st = Touch.newState()
		local sx, sy = 0, 0
		for i, p in ipairs(samples) do
			-- assert the fixture, don't assume it: if a sample strayed outside the band the hold
			-- stream would contaminate this into a non-parity test (red-team #5).
			local ox, oy = p[1] - samples[1][1], p[2] - samples[1][2]
			H.ok(math.sqrt(ox * ox + oy * oy) <= band, "walk sample " .. i .. " stayed inside the dead-band")
			local dx, dy = Touch.step(st, down(p[1], p[2]), 1 / 60, CFG)
			if i > 1 then sx, sy = sx + dx, sy + dy end
		end
		return sx, sy
	end
	-- two very different routes from (200,200) to (240,225), both inside the band.
	-- NOTE the two-name capture: `local a = walk(...)` silently TRUNCATED the multi-return and made
	-- this test check dx only — it proved half of what its name claimed (red-team #5).
	local ax, ay = walk({ { 200, 200 }, { 240, 225 } })
	local bx, by = walk({ { 200, 200 }, { 210, 190 }, { 230, 215 }, { 205, 205 }, { 240, 225 } })
	H.approx(ax, 40 * gain, 1e-9, "direct route dx")
	H.approx(ay, 25 * gain, 1e-9, "direct route dy")
	H.approx(bx, ax, 1e-9, "a wandering route integrates to the same dx as the direct one")
	H.approx(by, ay, 1e-9, "a wandering route integrates to the same dy as the direct one")
end)

--------------------------------------------------------------------------------
-- 2) BAND PROPERTIES — no drift inside, a monotone rim-pin stream outside.
--------------------------------------------------------------------------------
H.test("band: a STATIONARY finger inside the dead-band emits nothing (no drift, no creep)", function()
	local band = CFG.touchBandPx or 60
	-- Two cases. AT the anchor is the easy one (offset 0). The one that matters is stationary but
	-- OFF-anchor yet still inside the band — red-team noted that a "band is a no-op" regression would
	-- slip past the at-anchor case entirely (mag = 0 either way).
	for _, off in ipairs({ 0, math.floor(band * 0.8) }) do
		local st = Touch.newState()
		Touch.step(st, down(500, 500), 1 / 60, CFG)
		if off > 0 then Touch.step(st, down(500 + off, 500), 1 / 60, CFG) end
		for _ = 1, 120 do
			local dx, dy = Touch.step(st, down(500 + off, 500), 1 / 60, CFG)
			H.eq(dx, 0, ("stationary %dpx off-anchor inside the band must emit zero dx"):format(off))
			H.eq(dy, 0, ("stationary %dpx off-anchor inside the band must emit zero dy"):format(off))
		end
	end
end)

--------------------------------------------------------------------------------
-- 2b) FRAME-RATE COHERENCE — the module's central design claim, and the axis the
--     first draft of this spec was completely blind on (every call used 1/60, so a
--     dt-dependent DRAG and a dt-IGNORING hold both passed). DRAG must be
--     displacement-based (dt must not appear); HOLD must be a true rate (its
--     integral over a second is equal at any frame rate). Same class as the mouse.
--------------------------------------------------------------------------------
H.test("dt: DRAG output is frame-rate INDEPENDENT (dt must not appear in the drag term)", function()
	local path = { { 0, 0 }, { 12, 7 }, { 25, 15 }, { 33, 22 } }
	local ref
	for _, dt in ipairs({ 1 / 30, 1 / 60, 1 / 144, 1 / 240 }) do
		local st = Touch.newState()
		local out = {}
		for _, p in ipairs(path) do
			local dx, dy = Touch.step(st, down(p[1], p[2]), dt, CFG)
			out[#out + 1] = dx; out[#out + 1] = dy
		end
		if ref then
			for i = 1, #out do
				H.approx(out[i], ref[i], 1e-9,
					("drag delta %d changed with frame rate (dt=%.5f) — parity with the mouse is broken"):format(i, dt))
			end
		else
			ref = out
		end
	end
end)

H.test("dt: the HOLD stream is a true RATE — its 1-second integral is equal at 30/60/144 fps", function()
	local band = CFG.touchBandPx or 60
	local target = band + 120
	local ref
	for _, fps in ipairs({ 30, 60, 144, 240 }) do
		local dt = 1 / fps
		local st = Touch.newState()
		Touch.step(st, down(0, 0), dt, CFG)
		Touch.step(st, down(target, 0), dt, CFG)   -- the drag frame that gets us out past the band
		local sum = 0
		for _ = 1, fps do                          -- exactly one second of HOLDING still
			sum = sum + (Touch.step(st, down(target, 0), dt, CFG))
		end
		if ref then
			H.approx(sum, ref, 1e-6,
				("one second of hold emitted %.4f at %dfps but %.4f at the reference rate — the hold is"
					.. " per-FRAME, not per-SECOND"):format(sum, fps, ref))
		else
			ref = sum
		end
		H.ok(sum > 0, "the hold actually streamed at " .. fps .. "fps")
	end
end)

H.test("band: held PAST the band, a stationary finger emits a steady stream (the rim-pin analog)", function()
	local st = Touch.newState()
	local band = CFG.touchBandPx or 60
	Touch.step(st, down(0, 0), 1 / 60, CFG)
	-- jump well past the band, then HOLD still: a mouse would still be travelling, so must we.
	Touch.step(st, down(band + 100, 0), 1 / 60, CFG)
	local dx, dy = Touch.step(st, down(band + 100, 0), 1 / 60, CFG)
	H.ok(dx > 0, "a finger held past the band keeps feeding delta (else you cannot hold a turn)")
	H.approx(dy, 0, 1e-9, "a purely horizontal hold emits no vertical delta")
	-- and it is STEADY (stateless in the overshoot, not an accelerating ramp)
	local dx2 = Touch.step(st, down(band + 100, 0), 1 / 60, CFG)
	H.approx(dx2, dx, 1e-9, "the hold stream is steady while the finger is still")
end)

H.test("band: the hold rate is MONOTONE in overshoot and clamped at touchHoldMaxPxPerSec", function()
	local band = CFG.touchBandPx or 60
	local prev = -1
	for _, over in ipairs({ 1, 5, 20, 60, 150, 400, 3000 }) do
		local st = Touch.newState()
		Touch.step(st, down(0, 0), 1 / 60, CFG)
		Touch.step(st, down(band + over, 0), 1 / 60, CFG)   -- move there (drag frame)
		local dx = Touch.step(st, down(band + over, 0), 1 / 60, CFG)  -- then hold still: pure stream
		H.finite(dx, "hold delta is finite at overshoot " .. over)
		H.ok(dx >= prev - 1e-9, ("hold rate must not DECREASE as overshoot grows (at %d)"):format(over))
		H.ok(dx <= (CFG.touchHoldMaxPxPerSec or 1400) * (1 / 60) + 1e-9,
			("hold rate exceeded the clamp at overshoot %d"):format(over))
		prev = dx
	end
end)

--------------------------------------------------------------------------------
-- 3) LIFT — the touch analog of "the sound that won't stop". A released finger
--    must NEVER keep steering, no matter how far past the band it was held.
--------------------------------------------------------------------------------
H.test("lift: releasing a finger held far past the band emits ZERO, forever", function()
	local st = Touch.newState()
	local band = CFG.touchBandPx or 60
	Touch.step(st, down(0, 0), 1 / 60, CFG)
	Touch.step(st, down(band + 500, band + 500), 1 / 60, CFG)
	local held = Touch.step(st, down(band + 500, band + 500), 1 / 60, CFG)
	H.ok(held > 0, "fixture check: it WAS streaming before the lift")

	for _ = 1, 240 do
		local dx, dy = Touch.step(st, UP, 1 / 60, CFG)
		H.eq(dx, 0, "a lifted finger must never steer")
		H.eq(dy, 0, "a lifted finger must never steer (y)")
	end
	-- and the next touch starts clean, anchored where it lands
	local dx, dy = Touch.step(st, down(900, 900), 1 / 60, CFG)
	H.eq(dx, 0, "the next touch-down re-anchors and emits nothing")
	H.eq(dy, 0, "the next touch-down re-anchors and emits nothing (y)")
end)

H.test("identity: a FINGER SWAP re-anchors and emits nothing (not a screen-wide drag)", function()
	local st = Touch.newState()
	local gain = CFG.touchDragGain or 1.4
	local A, B = "fingerA", "fingerB"
	Touch.step(st, { active = true, x = 100, y = 100, id = A }, 1 / 60, CFG)
	local dx = Touch.step(st, { active = true, x = 120, y = 100, id = A }, 1 / 60, CFG)
	H.approx(dx, 20 * gain, 1e-9, "same finger: a normal drag")

	-- finger A lifts and B becomes primary, way across the screen. WITHOUT identity this is one frame
	-- of ~2300px × gain — a violent cursor yank to the rim in an arbitrary direction.
	local sx, sy = Touch.step(st, { active = true, x = 1400, y = 900, id = B }, 1 / 60, CFG)
	H.eq(sx, 0, "a finger swap must emit ZERO dx, not a 2000px teleport-drag")
	H.eq(sy, 0, "a finger swap must emit ZERO dy")
	-- and B is now anchored where it landed, so it drags normally from there
	local dx2 = Touch.step(st, { active = true, x = 1410, y = 900, id = B }, 1 / 60, CFG)
	H.approx(dx2, 10 * gain, 1e-9, "the new finger drags from ITS OWN anchor")
end)

--------------------------------------------------------------------------------
-- 4) ROBUSTNESS — no NaN can ever reach the locked aim law; determinism.
--------------------------------------------------------------------------------
H.test("robustness: NaN/inf touches and bad dt emit zero, never a poisoned delta", function()
	local st = Touch.newState()
	Touch.step(st, down(10, 10), 1 / 60, CFG)
	for _, bad in ipairs({ 0 / 0, math.huge, -math.huge }) do
		local dx, dy = Touch.step(st, down(bad, 10), 1 / 60, CFG)
		H.eq(dx, 0, "a non-finite touch x emits zero")
		H.eq(dy, 0, "a non-finite touch x emits zero (y)")
		local dx2, dy2 = Touch.step(st, down(10, bad), 1 / 60, CFG)
		H.eq(dx2, 0, "a non-finite touch y emits zero")
		H.eq(dy2, 0, "a non-finite touch y emits zero (y)")
	end
	-- bad dt must not poison the hold stream either
	local st2 = Touch.newState()
	local band = CFG.touchBandPx or 60
	Touch.step(st2, down(0, 0), 1 / 60, CFG)
	Touch.step(st2, down(band + 200, 0), 1 / 60, CFG)
	for _, badDt in ipairs({ 0 / 0, math.huge, -1, 0 }) do
		local dx, dy = Touch.step(st2, down(band + 200, 0), badDt, CFG)
		H.finite(dx, "hold delta stays finite with dt=" .. tostring(badDt))
		H.finite(dy, "hold delta stays finite with dt=" .. tostring(badDt))
	end
	H.eq(select(1, Touch.step(st2, nil, 1 / 60, CFG)), 0, "a nil touch emits zero")
	H.eq(select(1, Touch.step(nil, down(1, 1), 1 / 60, CFG)), 0, "a nil state emits zero (no crash)")
end)

H.test("determinism: the same scripted gesture replays to bit-identical deltas", function()
	local function run()
		local st = Touch.newState()
		local out = {}
		local pts = { { 0, 0 }, { 30, 10 }, { 90, 40 }, { 200, 120 }, { 200, 120 }, { 210, 130 } }
		for _, p in ipairs(pts) do
			local dx, dy = Touch.step(st, down(p[1], p[2]), 1 / 60, CFG)
			out[#out + 1] = dx
			out[#out + 1] = dy
		end
		return out
	end
	local a, b = run(), run()
	H.eq(#a, #b, "same sample count")
	for i = 1, #a do
		H.eq(a[i], b[i], "delta " .. i .. " is bit-identical across replays")
	end
end)

--------------------------------------------------------------------------------
-- 5) THE INERT GATE — this is B7-P1; nothing may consume it until Chad's P2 verdict.
--------------------------------------------------------------------------------
H.test("B7-P1 ships INERT: Controls.touchAim is false and no seam consumes the adapter yet", function()
	H.eq(CFG.touchAim, false, "touchAim must ship false — B7-P2's seam is the CHAD GATE (DRAG vs TAP)")
	H.ok((CFG.touchBandPx or 0) > 0, "the dead-band must be positive or the hold regime is undefined")
	H.ok((CFG.touchDragGain or 0) > 0, "drag gain must be positive or the cursor moves backwards")
end)
