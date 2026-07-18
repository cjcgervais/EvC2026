--!nonstrict
--[[
	tests/featherburst.spec.luau — the READ GATE for discrete falling feather PARTS.

	This spec is the anti-mediocre gate: it must have teeth. The old soft-sprite feather
	cloud failed 3× because motion + discreteness cannot be checked by a code audit alone.
	This spec builds real Instances and simulates real kinematics to machine-assert the
	visual read BEFORE Chad ever flies.

	WHAT THIS SPEC GATES:
	  • GEOMETRY    — each Part is ELONGATED (aspect >= 6), thin, brown, and inert.
	  • DISCRETE+RING — N>=10 distinct feathers open into a real ring; pairwise minimum
	                    separation > threshold; no center clump; azimuthal gap <= 1.2 rad.
	  • FALL        — mean Y is clearly below spawn by end-of-life (they FELL); pops up first.
	  • FLUTTER     — at least half the feathers deviate from a straight radial line (the sway
	                  → flutter; no straight-drop regression).
	  • PERSISTENCE — feathers linger through holdFrac, then fade; life in Chad's 2.5-3.5s window.
	  • DETERMINISM — spawnState is pure/seedless; same index → identical state, always.
	  • TOMBSTONE   — N discrete elongated Parts, not a sprite cloud; the blob is banned.
]]

local H = require("./_harness")
local Loader = require("./_loader")
local Vector3  = Loader.Vector3
local Instance = Loader.Instance

local GameConfig    = Loader.load("GameConfig")
local FeatherBurst  = Loader.load("FeatherBurst")

local cfg = GameConfig.Rescue and GameConfig.Rescue.featherParts

-- Shared simulation helper: Euler-step all feathers in a burst to age T.
-- Returns array of final states (each is a kinematic snapshot).
local function simulateAll(T)
	local dt = 1 / 60
	local states = {}
	for i = 1, cfg.count do
		states[i] = FeatherBurst.spawnState(i, cfg.count, cfg)
	end
	local t = 0
	while t < T do
		for _, st in ipairs(states) do
			FeatherBurst.step(st, dt, cfg)
		end
		t = t + dt
	end
	return states
end

--------------------------------------------------------------------------------
-- 1. GEOMETRY: elongated, thin, brown, inert
--------------------------------------------------------------------------------
H.test("geometry: feather Part is elongated, thin, brown, and inert (parked)", function()
	local folder = Instance.new("Folder")
	local p = FeatherBurst.buildFeather(folder, cfg, 1)

	-- Sorted dims: min=thin x, mid=vane z, max=long y
	local sx, sy, sz = p.Size.X, p.Size.Y, p.Size.Z
	local dims = {sx, sy, sz}
	table.sort(dims)
	local dmin, dmax = dims[1], dims[3]

	H.ok(dmax / dmin >= 6,
		"elongated: max/min aspect ratio >= 6 (actual " .. string.format("%.1f", dmax/dmin) ..
		"). A ball is 1; feathers should be long + thin. Check cfg.size.")
	H.ok(dmin <= 0.25,
		"thin: smallest dim <= 0.25 studs (actual " .. tostring(dmin) .. "). Feathers are thin.")
	H.ok(dmax >= 1.8,
		"long: longest dim >= 1.8 studs (actual " .. tostring(dmax) .. "). Reads at flight camera.")

	-- Color: warm brown — R > G > B and (R-B) >= 0.1; works for both BROWN and BROWN_LITE tints.
	local r, g, b = p.Color.R, p.Color.G, p.Color.B
	H.ok(r > g and g > b and r >= 0.3 and (r - b) >= 0.1,
		"brown: color is warm brown (R>G>B, R>=0.3, R-B>=0.1). Got R="
		.. string.format("%.2f", r) .. " G=" .. string.format("%.2f", g) .. " B=" .. string.format("%.2f", b))

	H.ok(p.Anchored == true,         "Anchored = true (code-driven, no physics bodies)")
	H.ok(p.CanCollide == false,       "CanCollide = false (cosmetic only)")
	H.ok(p.CanQuery == false,         "CanQuery = false")
	H.ok(p.CanTouch == false,         "CanTouch = false")
	H.ok(p.Transparency == 1,         "Transparency = 1 (parked until a burst claims it)")
end)

--------------------------------------------------------------------------------
-- 2. DISCRETE + RING: mid-life, feathers open into a real ring
--------------------------------------------------------------------------------
H.test("discrete+ring: N feathers open into a ring with good separation (mid-life)", function()
	local T = cfg.life * 0.5
	local states = simulateAll(T)

	H.ok(cfg.count >= 10, "count >= 10 feathers (reads as a full ring), got " .. tostring(cfg.count))

	-- Every feather must have moved outward from center (no center clump)
	for i, st in ipairs(states) do
		local r = Vector3.new(st.pos.X, 0, st.pos.Z).Magnitude
		H.ok(r >= 5,
			"feather " .. i .. " horizontal radius >= 5 studs at mid-life (no center clump), got "
			.. string.format("%.1f", r))
	end

	-- Mean horizontal radius should be in the expected ring band
	local meanR = 0
	for _, st in ipairs(states) do
		meanR = meanR + Vector3.new(st.pos.X, 0, st.pos.Z).Magnitude
	end
	meanR = meanR / #states
	H.ok(meanR >= 7 and meanR <= 18,
		"mean ring radius in [7,18] studs at mid-life (actual " .. string.format("%.1f", meanR) .. ")")

	-- Pairwise minimum 3D separation > 1.5 studs
	for i = 1, #states do
		for j = i + 1, #states do
			local si, sj = states[i], states[j]
			local dx = si.pos.X - sj.pos.X
			local dy = si.pos.Y - sj.pos.Y
			local dz = si.pos.Z - sj.pos.Z
			local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
			H.ok(dist > 1.5,
				"feathers " .. i .. " and " .. j .. " are separated > 1.5 studs (no overlap), got "
				.. string.format("%.2f", dist))
		end
	end

	-- Azimuthal gap check: sort azimuths, max gap <= 1.2 rad (a full ring, not a one-sided spray)
	local azimuths = {}
	for _, st in ipairs(states) do
		azimuths[#azimuths + 1] = math.atan2(st.pos.Z, st.pos.X)
	end
	table.sort(azimuths)
	local maxGap = 0
	for i = 1, #azimuths - 1 do
		local gap = azimuths[i + 1] - azimuths[i]
		if gap > maxGap then maxGap = gap end
	end
	-- Wrap-around gap (from last back to first + 2pi)
	local wrapGap = (azimuths[1] + 2 * math.pi) - azimuths[#azimuths]
	if wrapGap > maxGap then maxGap = wrapGap end
	H.ok(maxGap <= 1.2,
		"azimuthal gap <= 1.2 rad (full ring, not a one-sided spray), max gap = "
		.. string.format("%.2f", maxGap))
end)

--------------------------------------------------------------------------------
-- 3. FALL: mean Y is below spawn at end-of-life; pops up first
--------------------------------------------------------------------------------
H.test("fall: feathers pop UP first, then FALL — mean Y clearly below spawn at end-of-life", function()
	-- At 25% of life, feathers should still be above (or near) spawn (pop + hang)
	local statesQuarter = simulateAll(cfg.life * 0.25)
	local meanYq = 0
	for _, st in ipairs(statesQuarter) do meanYq = meanYq + st.pos.Y end
	meanYq = meanYq / #statesQuarter
	H.ok(meanYq >= -1,
		"at 25% of life, mean Y >= -1 studs (feathers pop up first, not immediate drop), got "
		.. string.format("%.2f", meanYq))

	-- At end-of-life, feathers should be well below spawn
	local statesFull = simulateAll(cfg.life)
	local meanY = 0
	for _, st in ipairs(statesFull) do meanY = meanY + st.pos.Y end
	meanY = meanY / #statesFull
	H.ok(meanY <= -6,
		"at end-of-life, mean Y <= -6 studs (they FELL; actual "
		.. string.format("%.1f", meanY) .. "). This is machine-asserted 'falling feathers'.")
end)

--------------------------------------------------------------------------------
-- 4. FLUTTER: feathers deviate from a straight radial path (tangential sway)
--------------------------------------------------------------------------------
H.test("flutter: at least half the feathers deviate from straight radial path (sway → flutter)", function()
	-- Simulate step-by-step and track max tangential deviation for each feather.
	local dt = 1 / 60
	local states = {}
	local spawnStates = {}
	for i = 1, cfg.count do
		local s = FeatherBurst.spawnState(i, cfg.count, cfg)
		states[i] = s
		-- Record the initial sway direction (tangential, guaranteed off-radial)
		spawnStates[i] = { swayDir = s.swayDir }
	end

	local maxDevs = {}
	for i = 1, cfg.count do maxDevs[i] = 0 end

	local t = 0
	while t < cfg.life do
		for i, st in ipairs(states) do
			FeatherBurst.step(st, dt, cfg)
			-- Measure tangential (sway) deviation: |pos · swayDir| in the horizontal plane
			local dev = math.abs(
				st.pos.X * spawnStates[i].swayDir.X +
				st.pos.Z * spawnStates[i].swayDir.Z
			)
			if dev > maxDevs[i] then maxDevs[i] = dev end
		end
		t = t + dt
	end

	local deviators = 0
	for _, d in ipairs(maxDevs) do
		if d >= 0.75 then deviators = deviators + 1 end
	end
	H.ok(deviators >= cfg.count / 2,
		"flutter: at least " .. math.floor(cfg.count / 2) .. " of " .. cfg.count ..
		" feathers deviate >= 0.75 studs from a straight radial path (got " .. deviators ..
		"). swayAmp=" .. tostring(cfg.swayAmp) .. " should guarantee this each cycle.")
end)

--------------------------------------------------------------------------------
-- 5. PERSISTENCE: life in Chad's window; opaque through holdFrac, then fades
--------------------------------------------------------------------------------
H.test("persistence: life in 2.5-3.5s window; opaque through holdFrac, then fades to 1", function()
	H.ok(cfg.life >= 2.5 and cfg.life <= 3.5,
		"life in [2.5, 3.5] s (Chad's linger window), got " .. tostring(cfg.life))

	-- At holdFrac of life, transparency should be 0 (fully visible)
	local stHold = FeatherBurst.spawnState(1, cfg.count, cfg)
	stHold.age = cfg.life * (cfg.holdFrac or 0.75)
	local tHold = FeatherBurst.transparency(stHold, cfg)
	H.approx(tHold, 0, 1e-6, "transparency at holdFrac*life = 0 (fully opaque)")

	-- At 98% of life, nearly faded (>= 0.85)
	local stAlmost = FeatherBurst.spawnState(1, cfg.count, cfg)
	stAlmost.age = cfg.life * 0.98
	local tAlmost = FeatherBurst.transparency(stAlmost, cfg)
	H.ok(tAlmost >= 0.85,
		"transparency at 0.98*life >= 0.85 (nearly gone), got " .. string.format("%.3f", tAlmost))

	-- At exactly life, fully invisible
	local stDone = FeatherBurst.spawnState(1, cfg.count, cfg)
	stDone.age = cfg.life
	local tDone = FeatherBurst.transparency(stDone, cfg)
	H.approx(tDone, 1, 1e-6, "transparency at age=life = 1 (parked/invisible)")
end)

--------------------------------------------------------------------------------
-- 6. DETERMINISM: spawnState is seedless; same index → identical result always
--------------------------------------------------------------------------------
H.test("determinism: spawnState is pure — same index gives identical state twice", function()
	local s1 = FeatherBurst.spawnState(5, 12, cfg)
	local s2 = FeatherBurst.spawnState(5, 12, cfg)
	H.approx(s1.vel.X,      s2.vel.X,      1e-9, "vel.X identical (no hidden randomness)")
	H.approx(s1.vel.Y,      s2.vel.Y,      1e-9, "vel.Y identical")
	H.approx(s1.vel.Z,      s2.vel.Z,      1e-9, "vel.Z identical")
	H.approx(s1.swayPhase,  s2.swayPhase,  1e-9, "swayPhase identical")
end)

--------------------------------------------------------------------------------
-- 7. TOMBSTONE: N discrete elongated Parts — the brown ball cannot come back
--------------------------------------------------------------------------------
H.test("tombstone: burst produces N discrete elongated PARTS — soft-sprite cloud is banned (failed 3×)", function()
	local folder = Instance.new("Folder")
	for i = 1, cfg.count do
		FeatherBurst.buildFeather(folder, cfg, i)
	end
	local children = folder:GetChildren()
	H.ok(#children == cfg.count,
		"exactly cfg.count (" .. cfg.count .. ") parts in the folder, got " .. tostring(#children))

	-- Every child must be a Part with aspect >= 6
	for i, child in ipairs(children) do
		H.ok(child.ClassName == "Part",
			"child " .. i .. " is a Part (not a ParticleEmitter or other class), got " .. tostring(child.ClassName) ..
			". TOMBSTONE: the poof must be N discrete elongated PARTS. " ..
			"A soft-sprite cloud blends into a brown ball and is BANNED (failed 3×).")
		local sx, sy, sz = child.Size.X, child.Size.Y, child.Size.Z
		local dims = {sx, sy, sz}
		table.sort(dims)
		local aspect = dims[3] / dims[1]
		H.ok(aspect >= 6,
			"Part " .. i .. " aspect ratio >= 6 (elongated, never a ball), got "
			.. string.format("%.1f", aspect) ..
			". TOMBSTONE: if aspect < 6, the part is too ball-like — the blob regression is possible.")
	end
end)
