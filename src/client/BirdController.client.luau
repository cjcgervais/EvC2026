--!nonstrict
--[[
	BirdController — Client-side flight, input, camera, and FX handler.

	Runs the FlightPhysics engine locally for zero-latency input response, then
	writes the result onto its standalone bird Model's PrimaryPart ("Body") — CFrame +
	assembly velocity — which the server has already given this client network ownership
	of. There is NO Roblox Character; the bird is found in Workspace.Birds by attribute.

	Control scheme (see GameConfig + project brief):
	  Mouse (move) -> WAR THUNDER MOUSE-AIM: a freely moveable CURSOR (desired direction of flight)
	                  and a NOSE CROSS projected out front of the bird (its boresight). The eagle steers
	                  so the nose cross ALWAYS APPROACHES the cursor; centre the cursor on it = fly
	                  straight. Hold the cursor at the screen EDGE = a sustained full turn / LOOP (the
	                  gap is unreachable -> the command stays saturated). Suspended while free-look
	                  (Space) is held. Tunables in GameConfig.Controls (aim*).
	  W / S        -> PITCH  (W nose-down to dive/accelerate, S nose-up to climb) — SMOOTHED tap->ramp
	  A / D        -> ROLL   (banking) — SMOOTHED tap->ramp; ADDS to the mouse-aim to tighten a turn
	  Q / E        -> YAW    (head-led) — smoothed. Keyboard is additive and dominates at full deflection.
	  Left Shift   -> FLAP THROTTLE up   (sticky: ramps UP-thrust/climb; holds where set)
	  Left Ctrl    -> FLAP THROTTLE down (sticky: ramps DOWN-thrust/descent; centre = glide)
	  Spacebar     -> FREE-LOOK camera (HOLD): hold to orbit the camera freely around the bird while
	                  the bird HOLDS its current flight input (aim autopilot suspended); RELEASE to resume aim.
	  Mouse Left   -> STRIKE (tap): the eagle's BANK at the click picks the strike — bank LEFT = left
	                  talon, bank RIGHT = right talon, ~LEVEL = forward — each with its own active window
	                  + downtime. The server reads the authoritative bank and owns all timing (anti-cheat).
	                  A strike covers/kills a ramming crow on that side AND hunts a crow in the cone.
	                  (Crows have no strike — their attack is the suicide ram.)
	  Mouse Right  -> AIM-ZOOM (hold): pull the camera in for a closer look (works in chase + free-look).
	  1-4          -> SwapCrow(index)
	  F            -> toggle formation tight/loose (SetFormation)
	  R            -> manual respawn / reset (Respawn)
]]

--------------------------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------------------------
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- SHARED MODULES
--------------------------------------------------------------------------------
local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local FlightPhysics = require(ReplicatedStorage:WaitForChild("FlightPhysics"))
local BirdBuilder   = require(ReplicatedStorage:WaitForChild("BirdBuilder"))
local BirdCollision = require(ReplicatedStorage:WaitForChild("BirdCollision"))

local CAM = GameConfig.Camera

--------------------------------------------------------------------------------
-- MATH HELPERS (shared by the mouse-aim instructor + the no-snap chase camera)
--------------------------------------------------------------------------------
local EPS = 1e-4
local function clamp(x, lo, hi)
	if x < lo then return lo elseif x > hi then return hi else return x end
end
-- Deadzone + EXPO shaper (War Thunder "nonlinearity"): zero inside the deadzone, then a curve that
-- is gentle near centre and ramps to FULL (±1) at the edge. expo 1 = linear, >1 = finer near centre.
local function shapeAxis(x, dead, expo)
	local a = math.abs(x)
	if a <= dead then return 0 end
	local n = (a - dead) / (1 - dead)         -- renormalise the live range to 0..1
	return (n ^ expo) * (x < 0 and -1 or 1)
end
-- Slew unit vector `from` toward unit vector `to` by at most `maxRad` (shortest path). Used to
-- rate-limit the chase direction so the camera can never snap through a loop. Mirrors FlightPhysics.
local function rotateTowards(from, to, maxRad)
	local d = clamp(from:Dot(to), -1, 1)
	local angle = math.acos(d)
	if angle < EPS then return to end
	local t = clamp(maxRad / angle, 0, 1)
	local result = from * (1 - t) + to * t
	if result.Magnitude < EPS then return to end
	return result.Unit
end

--------------------------------------------------------------------------------
-- REMOTES (created by the server)
--------------------------------------------------------------------------------
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned = Remotes:WaitForChild("TeamAssigned")
local AttackRequest = Remotes:WaitForChild("AttackRequest") -- legacy; superseded by Strike
local Strike       = Remotes:WaitForChild("Strike")
local SwapCrow     = Remotes:WaitForChild("SwapCrow")
local SetFormation = Remotes:WaitForChild("SetFormation")
local Respawn      = Remotes:WaitForChild("Respawn")
local GetThermals  = Remotes:WaitForChild("GetThermals")
local CombatFX     = Remotes:WaitForChild("CombatFX") -- S->C contact juice: cause, position, victimTeam, killed

-- Eagle strike input: LEFT-CLICK fires a strike EDGE (a tap, not a hold). We send NOTHING the server
-- must trust — no direction, no hit claim; the server reads the eagle's authoritative bank to pick
-- left/right/forward and owns every timer (anti-cheat). A tiny local debounce avoids double-fires on a
-- single press. The server ignores strikes from crows (their attack is the suicide ram).
local lastStrikeFire = 0
local function fireStrike()
	local t = os.clock()
	if t - lastStrikeFire < 0.12 then return end
	lastStrikeFire = t
	Strike:FireServer()
end

--------------------------------------------------------------------------------
-- PLAYER / CAMERA HANDLES
--------------------------------------------------------------------------------
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local flightEngine  = nil
local currentTeam   = nil
local currentProfile = nil
local birdModel     = nil
local rootPart      = nil
local isAlive       = false
local thermalData   = {}
local renderConn    = nil

-- RESCUE camera-decoration state (EAGLES TO THE RESCUE). `env` (0..1) is the slow-mo intensity the
-- catch beat drives; updateCamera reads it to apply a PURE beat-time post-transform (FOV narrow +
-- pull-in + cant) on the LOCKED chase's OUTPUT — identity when env=0, never feeds the control frame.
-- Forward-declared here so updateCamera (defined earlier than the rescue section) can see it.
local rescueCam = { env = 0 }

-- Live flight input the physics engine consumes every frame. pitch/roll/yaw are REBUILT
-- each frame in onFlightStep from `kb` (keyboard) + mouse-steer; flap/dive are set directly.
local inputState = {
	pitch = 0,
	roll  = 0,
	yaw   = 0,
	flap  = false,
	dive  = false,
}

-- Keyboard axis contributions (W/S pitch, A/D roll, Q/E yaw). Kept SEPARATE from inputState
-- so the keyboard and the analog mouse-steer don't clobber each other — they're summed each
-- frame (see onFlightStep). resetInput() clears both.
local kb = { pitch = 0, roll = 0, yaw = 0 }

-- Time-scaled pitch ramp: `sign` is the held direction (-1/0/+1), `mag` ramps from the tap
-- fraction up to 1 the longer the key is held (see onFlightStep). A quick tap only ever reaches
-- a small magnitude -> a precise AoA nudge; a sustained hold ramps to full pitch authority.
local pitchRamp = { sign = 0, mag = 0 }

-- Smoothed camera state. `userZoom` is the player's mouse-wheel offset (studs), folded
-- into the chase distance and clamped so the final distance stays in [min, max].
local cameraState = {
	currentDistance = CAM.baseDistance,
	userZoom = 0,
}

-- AIM-ZOOM (hold RIGHT-CLICK): pulls the chase distance + FOV in for a closer read of whatever
-- you're flying toward / watching. `active` is the held edge (set in InputBegan/Ended); `factor`
-- eases 0->1 toward active each frame in updateCamera (Camera.aimZoomLerp) and is folded into the
-- chase distance + FOV. Works in chase AND free-look. Camera-only — it NEVER touches flight input
-- or the steering cursor (verified: it doesn't change MouseBehavior, so the mouse-aim read is intact).
-- Module-level (not cleared by resetInput) so a held RMB survives a crow-swap.
local aimZoom = { active = false, factor = 0 }

-- Free-look (Spacebar) — LAW: hold Space to look ALL AROUND while flying. The camera
-- orbits the bird freely and MUST NEVER alter the flight input (it writes only freeLook.*,
-- never inputState.*; flight controls are keyboard-only and `isDiving` reads the bird's nose,
-- not the camera — keep it that way). BOTH yaw and pitch accumulate UNBOUNDED (player ask 2026-06-30:
-- "freelook all the way up and down, over and under") -> full 360° both ways. This is only safe because
-- the camera up is carried through the orbit itself (see updateCamera), which has NO pole singularity —
-- so there's nothing to clamp against and the view orbits smoothly through the whole vertical circle.
local freeLook = {
	active = false,
	yaw    = 0, -- radians, horizontal orbit (unbounded -> 360°)
	pitch  = 0, -- radians, vertical orbit (unbounded -> full over-the-top / under-the-belly)
}

-- Mouse-steer VIRTUAL STICK. The mouse is locked to center while flying; its deltas deflect
-- this stick (x = roll, y = pitch), clamped to [-1,1], and it springs back toward center at
-- Controls.mouseReturn. Starts at exactly 0 each life (reset in resetInput) so a bird can never
-- spawn already deflected (that caused the instant spiral crash). Read in computeMouseSteer.
local steer = { x = 0, y = 0 }

-- FLAP THROTTLE (sticky): -1 (full Ctrl down-thrust) .. 0 (glide) .. +1 (full Shift up-thrust). Ramped
-- from the held keys each frame in onFlightStep and fed to FlightPhysics as input.flapThrottle so you can
-- SET a climb power and fly hands-free on the mouse. resetInput() zeros it (between lives / focus loss).
local flapThrottle = 0

-- MOUSE-AIM reticle draw state: screen-space pixel positions for the two markers, written by
-- computeMouseAim each frame and consumed by the render block in onFlightStep. cursorX/Y = the free
-- mouse cursor (desired direction); noseX/Y = the projected nose cross (boresight), clamped to the
-- screen. x/y are legacy normalized fields kept only so resetInput's recentre is a no-op-safe write.
-- talonX/talonY = screen positions of the belly-arc pips (the talon strike zone, swings with bank);
-- armed = which zone an enemy is engaging ("beak"/"talon"/"none"), read from the Body's StrikeArmedDir attr.
local aimCursor = { x = 0, y = 0, cursorX = 0, cursorY = 0, noseX = 0, noseY = 0,
	talonX = {}, talonY = {}, armed = "none" }

-- The APPLIED mouse-aim input, eased toward the raw target each frame (Controls.aimResponse) so the
-- bird follows the reticle softly/flightily rather than snapping. Summed with keyboard in onFlightStep.
local aimApplied = { pitch = 0, roll = 0, yaw = 0 }

-- NOSE-CHASES-CURSOR aim (2026-06-30). aimTargetDir is the CURSOR as a WORLD direction: the mouse swings it away
-- from the nose (out to a big cone = the reachable circle) and it STAYS where you put it. The bird's NOSE — the
-- amber reticle, projected far out front — is the dependent thing: it chases the cursor and, when it catches up,
-- the beak points right at the cursor. nil until seeded to the current nose; resetInput() recentres it.
local aimTargetDir = nil

-- S28e turn-rate-lead washout state: 1 = lead fully active (arrival shaping), eased toward 0 while the
-- cursor is rim-pinned (sustained-turn command) or a flight key is held (CS-1 mute). See computeMouseAim.
local aimLeadScale = 1

-- Tap->ramp smoothing for roll and yaw (mirrors pitchRamp) so keyboard banking eases in.
local rollRamp = { sign = 0, mag = 0 }
local yawRamp  = { sign = 0, mag = 0 }

-- On-screen aim reticle (a zone circle + a cursor dot). Control-owned (GameUI's HUD is separate).
local playerGui = player:WaitForChild("PlayerGui")
local aimGui = Instance.new("ScreenGui")
aimGui.Name = "AimReticle"
aimGui.ResetOnSpawn = false
aimGui.IgnoreGuiInset = true
aimGui.Enabled = false
aimGui.Parent = playerGui
local aimZone = Instance.new("Frame") -- faint FIXED screen-centre tick (dead-ahead reference)
aimZone.Name = "Center"
aimZone.AnchorPoint = Vector2.new(0.5, 0.5)
aimZone.Position = UDim2.fromScale(0.5, 0.5)
aimZone.Size = UDim2.fromOffset(6, 6)
aimZone.BackgroundTransparency = 1
aimZone.Parent = aimGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = aimZone
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.fromRGB(180, 210, 255); s.Transparency = 0.7; s.Parent = aimZone
end
-- NOSE CROSS (boresight): where the bird is actually pointed, projected out front. The mouse-aim
-- steers so this marker chases the cursor dot below. Positioned each frame in onFlightStep from the
-- screen projection of birdPos + birdLook * aimMarkerDistance. Amber = the bird; cyan = your cursor.
local noseMarker = Instance.new("Frame")
noseMarker.Name = "Nose"
noseMarker.AnchorPoint = Vector2.new(0.5, 0.5)
noseMarker.Size = UDim2.fromOffset(18, 18) -- SMALL reticle: nests inside the larger cursor ring with a gap buffer
noseMarker.BackgroundTransparency = 1
noseMarker.Parent = aimGui
local noseStroke -- hoisted: the FORWARD strike lights this hot (see paintStrikeReticles)
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = noseMarker
	noseStroke = Instance.new("UIStroke"); noseStroke.Thickness = 2; noseStroke.Color = Color3.fromRGB(255, 200, 90); noseStroke.Transparency = 0.1; noseStroke.Parent = noseMarker
	local pip = Instance.new("Frame") -- centre dot so the boresight reads even against busy terrain
	pip.AnchorPoint = Vector2.new(0.5, 0.5)
	pip.Position = UDim2.fromScale(0.5, 0.5)
	pip.Size = UDim2.fromOffset(4, 4)
	pip.BorderSizePixel = 0
	pip.BackgroundColor3 = Color3.fromRGB(255, 200, 90)
	pip.Parent = noseMarker
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = pip
end
-- Cursor = a hollow GREEN LINE RING (not a solid dot) marking your desired direction of flight.
local aimDot = Instance.new("Frame")
aimDot.Name = "Cursor"
aimDot.AnchorPoint = Vector2.new(0.5, 0.5)
aimDot.Size = UDim2.fromOffset(48, 48) -- OUTER cursor ring: houses the small nose reticle inside it with a gap when aligned
aimDot.BackgroundTransparency = 1
aimDot.Parent = aimGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = aimDot
	local s = Instance.new("UIStroke"); s.Thickness = 2.5; s.Color = Color3.fromRGB(70, 255, 120); s.Transparency = 0; s.Parent = aimDot
end

-- TALON ARC (the belly strike zone). A hemispherical arc of pips UNDER the bird, in its roll plane, so BANKING
-- swings the arc around naturally — it shows where the talons reach. There is NO left/right dichotomy any more
-- (Chad 2026-06-30): ONE talon zone + ONE beak zone. Which strike a click throws is chosen SERVER-side by which
-- zone the nearest enemy is in (mirrored to the Body as StrikeArmedDir "talon"/"beak"/"none"); the lit reticle
-- previews it. Pip screen positions are written each frame in computeMouseAim. The talon has its own long
-- duration / short cooldown; the beak (nose cross) its short duration / long cooldown — see GameConfig.Combat.
local HOT_COLOR  = Color3.fromRGB(255, 95, 70)   -- the armed zone (the strike a click would throw now)
local BEAK_AMBER = Color3.fromRGB(255, 200, 90)  -- beak reticle, idle
local TALON_DIM  = Color3.fromRGB(150, 158, 172) -- talon arc, idle (cool so the hot state pops)
local talonPips = {}
for i = 1, 7 do
	local p = Instance.new("Frame")
	p.Name = "Talon" .. i
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(7, 7)
	p.BorderSizePixel = 0
	p.BackgroundColor3 = TALON_DIM
	p.BackgroundTransparency = 0.3
	p.Parent = aimGui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = p
	talonPips[i] = p
end

-- Light the zone the server reports an enemy is engaging: "beak" -> the nose cross goes hot; "talon" -> the
-- belly arc goes hot; "none" -> both idle.
local function paintStrikeReticles(armed)
	noseStroke.Color = (armed == "beak") and HOT_COLOR or BEAK_AMBER
	local talonHot = (armed == "talon")
	for _, p in ipairs(talonPips) do
		p.BackgroundColor3 = talonHot and HOT_COLOR or TALON_DIM
		p.BackgroundTransparency = talonHot and 0 or 0.35
		p.Size = talonHot and UDim2.fromOffset(9, 9) or UDim2.fromOffset(7, 7)
	end
end

-- Formation toggle state (crows).
local formationTight = false

--------------------------------------------------------------------------------
-- THERMAL DATA (fetched once from the server)
--------------------------------------------------------------------------------
task.spawn(function()
	local ok, result = pcall(function()
		return GetThermals:InvokeServer()
	end)
	if ok and type(result) == "table" then
		thermalData = result
	end
end)

--------------------------------------------------------------------------------
-- INPUT BINDINGS
--------------------------------------------------------------------------------
-- W = pitch +1 (nose down), S = pitch -1 (nose up). A/D roll, Q/E yaw.
local keyBindings = {
	[Enum.KeyCode.W] = { axis = "pitch", value = -1 }, -- nose DOWN (dive / accelerate)
	[Enum.KeyCode.S] = { axis = "pitch", value = 1 },  -- nose UP  (climb)
	[Enum.KeyCode.A] = { axis = "roll",  value = 1 },  -- bank left
	[Enum.KeyCode.D] = { axis = "roll",  value = -1 }, -- bank right
	[Enum.KeyCode.Q] = { axis = "yaw",   value = 1 },  -- yaw left  (reversed per playtest)
	[Enum.KeyCode.E] = { axis = "yaw",   value = -1 }, -- yaw right
}

local function setFreeLook(active)
	if active == freeLook.active then return end
	freeLook.active = active
	if active then
		-- Reset orbit so we begin from the chase position, then capture the mouse.
		freeLook.yaw = 0
		freeLook.pitch = 0
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		-- Returning to mouse-aim: recentre the virtual cursor so the bird doesn't lurch from a stale deflection,
		-- and re-lock the mouse (onFlightStep will keep it LockCenter'd for the relative-delta aim read).
		aimTargetDir = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		-- CS-2 EXIT SNAP (Chad 2026-07-02): on leaving free-look the camera used to LERP from the orbit pose
		-- back to the chase pose at the slow followSmoothing rate (~0.165/frame) — a ~3/4 s sweep through a
		-- side/perpendicular view that "costs reaction time due to disorientation." Flag a fast crisp return so
		-- updateCamera re-centres on the heading in ~50-80 ms (see the fast-return in updateCamera).
		-- snapT = the S28e time FAILSAFE for the flag (red-team F5): the dot>0.9995 consume test chases a
		-- MOVING target, and in a sustained fast turn (esp. a possessed crow) the steady tracking gap can
		-- exceed it — the flag would wedge ON and keep the aim cursor-circle clamp suspended indefinitely.
		cameraState.snapToChase = true
		cameraState.snapT = 0
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Flight axes (keyboard -> kb; summed with mouse-steer each frame in onFlightStep)
	local binding = keyBindings[input.KeyCode]
	if binding then
		kb[binding.axis] = binding.value
		return
	end

	-- Hold actions
	if input.KeyCode == Enum.KeyCode.LeftShift then
		-- up-thrust via the sticky flap throttle (ramped from held Shift in onFlightStep)
		return
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		-- down-thrust via the sticky flap throttle (ramped from held Ctrl in onFlightStep)
		return
	elseif input.KeyCode == Enum.KeyCode.Space then
		-- FREE-LOOK is HOLD-to-look (Chad 2026-07-13, reverted from the earlier toggle): HOLD Space to look
		-- all around hands-free while the bird HOLDS its maneuver; RELEASE snaps the aim back (InputEnded →
		-- setFreeLook(false)). The orbit resets each time it engages (in setFreeLook), so it always begins
		-- from the chase pose. Survives crow-swaps via acquire() re-arming to freeLook.active.
		setFreeLook(true)
		return
	elseif input.KeyCode == Enum.KeyCode.F then
		formationTight = not formationTight
		SetFormation:FireServer(formationTight and "tight" or "loose")
		return
	elseif input.KeyCode == Enum.KeyCode.R then
		-- Manual respawn / reset (no Roblox-character reset exists here).
		Respawn:FireServer()
		return
	end

	-- Possession swap (crow #1-4)
	local swapKeys = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
	}
	local swapIndex = swapKeys[input.KeyCode]
	if swapIndex then
		SwapCrow:FireServer(swapIndex)
		return
	end

	-- LEFT mouse = STRIKE (tap edge; the eagle's bank picks left/right/forward, server-owned).
	-- RIGHT mouse = AIM-ZOOM (hold to zoom the camera in; camera-only, no server intent). RMB was freed
	-- from "beak" per the 2026-06-30 control rework — it now zooms anywhere, in chase or free-look.
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		fireStrike()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimZoom.active = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local binding = keyBindings[input.KeyCode]
	if binding then
		-- Only zero the axis if the released key still owns the current direction.
		if kb[binding.axis] == binding.value then
			kb[binding.axis] = 0
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		inputState.flap = false
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		inputState.dive = false
	end
	-- FREE-LOOK is HOLD (Chad 2026-07-13): RELEASING Space turns it off and runs the CS-2 exit snap
	-- (setFreeLook(false) → recentre cursor + snapToChase). Focus loss (WindowFocusReleased) still
	-- force-clears it as a failsafe so you can never get stuck looking around.
	if input.KeyCode == Enum.KeyCode.Space then
		setFreeLook(false)
	end

	-- LEFT-CLICK is a tap (no release action). Release the aim-zoom on RMB-up.
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimZoom.active = false
	end
end)

-- Mouse delta routing: when free-looking (Space) it orbits the camera; otherwise it deflects
-- the steering virtual stick. Never reads absolute cursor position, so neutral is always well
-- defined (stick = 0). Both modes keep the mouse LockCenter'd (set in onFlightStep).
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	-- Mouse-wheel zoom: scroll up (Delta.Z > 0) pulls the camera IN, scroll down pushes OUT.
	-- Accumulate into a user offset; the camera step clamps the final distance to [min, max].
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if gameProcessed then return end
		cameraState.userZoom = cameraState.userZoom - input.Position.Z * (CAM.zoomStep or 6)
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	if freeLook.active then
		local s = CAM.freeLookSensitivity * 0.01
		freeLook.yaw   = freeLook.yaw   - input.Delta.X * s
		-- Free-look pitch INVERTED (player ask 2026-06-30 "invert the vertical component"): mouse-up looks
		-- DOWN, mouse-down looks up. UNBOUNDED (no clamp) so you can orbit all the way up/down and over/under
		-- (the orbit-derived up in updateCamera has no pole to flip on). Arrow-key pitch below stays in sync.
		freeLook.pitch = freeLook.pitch - input.Delta.Y * s
	end
	-- (Mouse-aim reads the per-frame GetMouseDelta straight in computeMouseAim; nothing to accumulate here.)
end)

-- Arrow keys also orbit the free-look camera (alternative to the mouse).
RunService.RenderStepped:Connect(function(dt)
	if not freeLook.active then return end
	local s = CAM.freeLookSensitivity * 2.5 * dt
	if UserInputService:IsKeyDown(Enum.KeyCode.Left)  then freeLook.yaw   = freeLook.yaw   + s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then freeLook.yaw   = freeLook.yaw   - s end
	-- Up/Down match the (now inverted) mouse pitch, also unbounded: Up key looks DOWN (+s), Down key looks UP (-s).
	if UserInputService:IsKeyDown(Enum.KeyCode.Up)    then freeLook.pitch = freeLook.pitch + s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down)  then freeLook.pitch = freeLook.pitch - s end
end)

--------------------------------------------------------------------------------
-- THERMAL FORCE — upward push when inside a thermal's radius & height band.
--------------------------------------------------------------------------------
local function computeThermalForce(position)
	local force = Vector3.new()
	for _, thermal in pairs(thermalData) do
		if thermal and thermal.position then
			local flat       = Vector3.new(position.X, 0, position.Z)
			local thermalFlat = Vector3.new(thermal.position.X, 0, thermal.position.Z)
			local dist = (flat - thermalFlat).Magnitude
			local minH = thermal.minHeight or 0
			local maxH = thermal.maxHeight or math.huge
			local radius = thermal.radius or 0
			if radius > 0 and dist < radius and position.Y > minH and position.Y < maxH then
				-- Stronger toward the core, falling off toward the height band edges.
				local centerFactor = 1 - (dist / radius)
				local mid  = (minH + maxH) * 0.5
				local span = math.max(1, maxH - minH)
				local heightFactor = 1 - math.abs((position.Y - mid) / span)
				heightFactor = math.clamp(heightFactor, 0, 1)
				force = force + Vector3.new(0, (thermal.strength or 0) * centerFactor * heightFactor, 0)
			end
		end
	end
	return force
end

--------------------------------------------------------------------------------
-- BIRD FADE (right-click telescope) — fade the eagle locally while zooming so its opaque body can't
-- block the outward view. LocalTransparencyModifier is CLIENT-ONLY (it doesn't replicate or change the
-- part's real Transparency), exactly what Roblox uses to fade your own character up close. Idempotent:
-- clears all modifiers once when the zoom releases. Driven by aimZoom.factor from updateCamera.
--------------------------------------------------------------------------------
local birdFadeApplied = false
local function applyBirdFade(factor)
	if not birdModel then birdFadeApplied = false return end
	if factor <= 0.02 then
		if birdFadeApplied then
			for _, p in ipairs(birdModel:GetDescendants()) do
				if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
			end
			birdFadeApplied = false
		end
		return
	end
	local m = math.clamp(factor * (CAM.aimFadeBird or 0.85), 0, 1)
	for _, p in ipairs(birdModel:GetDescendants()) do
		if p:IsA("BasePart") then p.LocalTransparencyModifier = m end
	end
	birdFadeApplied = true
end

--------------------------------------------------------------------------------
-- CAMERA — spectacular chase cam with speed pull-back, bank tilt, shake, and a
-- Spacebar free-look orbit that decouples the camera from the bird's heading.
--------------------------------------------------------------------------------
local function updateCamera(dt)
	if not flightEngine or not rootPart or not rootPart.Parent then return end
	camera.CameraType = Enum.CameraType.Scriptable

	local cf       = rootPart.CFrame
	local position = cf.Position
	local speed    = flightEngine.speed
	local velocity = flightEngine.velocity

	-- Distance grows with speed for a sense of velocity, plus the player's wheel-zoom
	-- offset, then clamped so the camera can't clip into the bird or run to infinity.
	local minDist = CAM.minDistance or 10
	local maxDist = CAM.maxDistance or 120
	-- Clamp userZoom against the speed-driven base so the wheel range stays meaningful at any speed.
	local speedBase = CAM.baseDistance + speed * CAM.speedDistanceFactor
	cameraState.userZoom = math.clamp(cameraState.userZoom, minDist - speedBase, maxDist - speedBase)
	local targetDistance = math.clamp(speedBase + cameraState.userZoom, minDist, maxDist)
	-- MOUSE-AIM = a STRICT FIXED chase distance (player ask): the wheel zoom must not change the view or the turn
	-- authority in aim mode. Free-look keeps the variable/zoomed distance.
	if GameConfig.Controls and GameConfig.Controls.mouseAim and not freeLook.active then
		targetDistance = CAM.mouseAimDistance or CAM.baseDistance or 40
	end
	cameraState.currentDistance = cameraState.currentDistance
		+ (targetDistance - cameraState.currentDistance) * 0.1

	local dist = cameraState.currentDistance

	-- RIGHT-CLICK = OUTWARD TELESCOPE (player ask 2026-06-30): right-click zooms toward where you're AIMING /
	-- LOOKING (narrows FOV + swings the look toward the reticle + fades the eagle so its opaque body can't
	-- block the view) — it does NOT dolly the camera into the eagle. Eagle-distance is the MOUSE WHEEL's job
	-- (`userZoom`, above), and it works in chase AND free-look (no special-casing — the wheel feeds `dist`
	-- directly). Here we only ease the zoom factor toward the held RMB state; the look/FOV/fade use it below.
	local zoomTarget = aimZoom.active and 1 or 0
	aimZoom.factor = aimZoom.factor + (zoomTarget - aimZoom.factor) * math.clamp(CAM.aimZoomLerp or 0.22, 0, 1)

	-- CONTINUOUS, RATE-LIMITED CHASE DIRECTION (the no-snap / anti-sickness fix, RESEARCH §v4). The old
	-- camera rebuilt its azimuth from the bird's HORIZONTAL heading, which REVERSES ~180° over the top of a
	-- loop and SNAPPED the view (the nausea bug). Instead we keep ONE persistent full-3D unit vector
	-- (bird->camera) and slew it toward "behind the bird's motion" at a CAPPED angular rate. It is never
	-- rebuilt from a discontinuous reference, so a full 360° loop arcs smoothly — no azimuth snap, no
	-- over/under pole flip. Roblox CFrame:Lerp (shortest-path quaternion slerp) finishes the smoothing.
	local lookVec = cf.LookVector
	local followDir = lookVec
	if speed > 12 and velocity.Magnitude > 1 then
		-- Blend the nose toward the VELOCITY vector (look-ahead): the camera reads the actual flight path.
		local blended = lookVec:Lerp(velocity.Unit, CAM.lookAheadFactor or 0.3)
		if blended.Magnitude > EPS then followDir = blended.Unit end
	end
	-- MOUSE-AIM CAMERA LAG: in aim mode the camera follows a LAGGED heading, so a quick cursor-driven turn leaves
	-- the world-anchored cursor OUT on screen (the nose visibly lags and chases it across the screen) instead of
	-- the view snapping to the new heading and dragging the cursor back to centre (player: "the cursor gets pulled
	-- back to the reticle — it should be a continuous lag/chase"). aimHeadingLag = how fast the camera catches up
	-- to the bird's heading (LOWER = the cursor hangs out there longer, the nose lags more). Free-look/chase-only
	-- flight are unaffected.
	local headingRef = followDir
	if GameConfig.Controls and GameConfig.Controls.mouseAim and not freeLook.active then
		-- EXPONENTIAL ease (not a constant-rate slew): the view glides toward the heading and eases out at the
		-- end instead of stopping abruptly, so the catch-up reads smooth (player: "the camera needs to be smoother").
		-- CS-8 SUPERSEDED (Stage 1, Chad-approved 2026-07-12): the camera lags the AIM, not the bird's
		-- heading, so the world-anchored cursor RE-CENTRES as the view catches aimTargetDir. Fall back to
		-- followDir (today's behavior, byte-for-byte) whenever the aim is NOT the active driver: no cursor
		-- yet (nil / post-swap), a flight key held (CS-1 mute — predicate mirrors the aimGate exactly), or
		-- RMB aim-zoom (awareness-only; must not move the view target). aimTargetDir is fresh here
		-- (computeMouseAim runs earlier in onFlightStep) and always Unit. RETARGET only — aimHeadingLag
		-- keeps its value and the fallback IS the inert/identity path. ⚠️ FIRST playtest gate: a rim-pinned
		-- sustained turn must not PULSE (the screen-circle clamp writes aimTargetDir and the camera now eases
		-- toward it — a damped loop; if it hunts, feed the ease from the PRE-clamp aim, do NOT raise lag).
		local keysHeld = (kb.pitch ~= 0 or kb.roll ~= 0 or kb.yaw ~= 0)
		local easeTarget = (aimTargetDir and not keysHeld and not aimZoom.active) and aimTargetDir or followDir
		local prevAim = cameraState.aimHeading or easeTarget
		local aAim = math.clamp(1 - math.exp(-(CAM.aimHeadingLag or 1.4) * dt), 0, 1)
		local blendedAim = prevAim:Lerp(easeTarget, aAim)
		cameraState.aimHeading = (blendedAim.Magnitude > EPS) and blendedAim.Unit or easeTarget
		headingRef = cameraState.aimHeading
	else
		cameraState.aimHeading = nil
	end
	local desiredChase = -headingRef
	cameraState.chaseDir = cameraState.chaseDir or desiredChase
	-- FREEZE the chase basis while free-looking so the view is WORLD-referenced (holds its aspect while the
	-- bird loops); only track the bird's motion when NOT free-looking. Without this the base offset kept
	-- following the bird's heading through the loop -> the ~180° flip even in free-look. On exit the slew
	-- resumes and rate-limits the basis back to "behind the bird" — smooth, no snap.
	if not freeLook.active then
		cameraState.chaseDir = rotateTowards(cameraState.chaseDir, desiredChase, (CAM.chaseTurnRate or 3.6) * dt)
	end
	local chaseDir = cameraState.chaseDir

	-- CREST RATE — how fast the bird's facing is rotating (rad/s). Computed HERE (before the up vector) so it
	-- can BOTH soften the follow lerp below AND roll the camera around with the bird over a loop. ~0 in normal
	-- flight; spikes toward 1·crestAngRate over a fast loop top.
	local angRate = 0
	if cameraState.prevLook then
		local d = math.clamp(cameraState.prevLook:Dot(cf.LookVector), -1, 1)
		angRate = math.acos(d) / math.max(dt, 1 / 240)
	end
	cameraState.prevLook = cf.LookVector
	local crestBlend = math.clamp(angRate / (CAM.crestAngRate or 3.0), 0, 1)

	-- CAMERA UP via PARALLEL TRANSPORT along the chase direction (2026-06-30 rework). Replaces (a) the world-up
	-- perpendicular construction that DEGENERATED at the pole and flipped the view over a loop, and (b) the
	-- cf.UpVector lean that made the camera SPIN during a barrel/snap roll. Each frame we carry the previous up
	-- along the ROTATION OF THE CHASE DIRECTION (the flight-path direction), then re-orthogonalize:
	--   • a LOOP rotates the flight path through vertical -> the up transports over the top -> NO flip;
	--   • a barrel/snap ROLL barely moves the flight-path direction -> the up holds steady -> you WATCH the bird
	--     roll instead of the camera spinning (player ask 2026-06-30); and there is NO pole singularity.
	-- A gentle relax toward world-level self-levels the horizon in ordinary flight, FADED OUT as the flight path
	-- goes vertical (verticality) so it can never yank the up to the degenerate world reference mid-loop.
	local prevChase = cameraState.chaseDirPrev or chaseDir
	local up = cameraState.camUp
	if not up then
		up = Vector3.yAxis - chaseDir * chaseDir.Y
		up = (up.Magnitude > 0.15) and up.Unit or Vector3.zAxis
	end
	local dotc = math.clamp(prevChase:Dot(chaseDir), -1, 1)
	if dotc < 0.999999 then
		local axis = prevChase:Cross(chaseDir)
		if axis.Magnitude > 1e-6 then
			up = CFrame.fromAxisAngle(axis.Unit, math.acos(dotc)):VectorToWorldSpace(up)
		end
	end
	up = up - chaseDir * up:Dot(chaseDir)               -- re-orthogonalize against the chase direction
	up = (up.Magnitude > 1e-4) and up.Unit or (cameraState.camUp or Vector3.yAxis)
	-- Self-level toward world-up (perp to the chase), faded out as the path goes vertical (a loop) so it never
	-- pulls the camera to the degenerate reference over the top. verticality = |followDir.Y| (0 level, 1 up/down).
	local levelRef = Vector3.yAxis - chaseDir * chaseDir.Y
	if not freeLook.active and levelRef.Magnitude > 0.15 then
		levelRef = levelRef.Unit
		local verticality = math.abs(followDir.Y)
		local levelGate = 1 - math.clamp((verticality - (CAM.loopVertStart or 0.5)) / math.max(0.05, CAM.loopVertBand or 0.4), 0, 1)
		local relax = math.clamp((CAM.horizonLevelRate or 2.0) * dt * levelGate, 0, 1)
		local blended = up:Lerp(levelRef, relax)
		up = (blended.Magnitude > 1e-4) and blended.Unit or up
	end
	cameraState.camUp = up
	cameraState.chaseDirPrev = chaseDir
	local camUp = up

	-- Height ratio grows with zoom for a higher, more top-down view when wheeled out.
	local hBase   = CAM.heightFactor or 0.25
	local hTop    = CAM.zoomTopDownHeight or 1.10
	local zoomFrac = math.clamp((dist - CAM.baseDistance) / math.max(1, maxDist - CAM.baseDistance), 0, 1)
	local heightRatio = hBase + (hTop - hBase) * zoomFrac

	local cameraOffset = chaseDir * dist + camUp * (dist * heightRatio)

	-- FREE-LOOK: orbit the offset (and its up) around the bird in a WORLD-referenced frame (yaw about world
	-- up, pitch about the world-horizontal right) so the view holds its ASPECT while the bird maneuvers — it
	-- no longer revolves with the bird's roll. WITHOUT touching flight input. (Toggle: Space.)
	if freeLook.active then
		-- CS-2 (REVISED by Chad 2026-06-30) — UPRIGHT SPHERICAL ORBIT. The camera operator stays WORLD-UPRIGHT
		-- at all times: the horizon is ALWAYS level and the view NEVER rolls or inverts ("I want to stay upright,
		-- not sideways or upside down"). Yaw orbits a full 360° around the bird; pitch tilts from level up/down to
		-- just shy of straight-up / straight-down — a SOFT STOP at vertical. It deliberately does NOT continue OVER
		-- the top to the far side (that unbounded over/under orbit was the S12 version whose orbit-derived up flipped
		-- the view upside down). camUp is hard WORLD-UP, so CFrame.lookAt keeps the horizon level for any non-
		-- vertical view; the pitch clamp holds the view off the exact pole so lookAt never degenerates (no jitter).
		local maxPitch = math.rad(CAM.freeLookPitchLimitDeg or 85)
		freeLook.pitch = math.clamp(freeLook.pitch, -maxPitch, maxPitch) -- write-back: bounded, no wind-up past vertical
		-- Bird->camera direction. Start from the frozen chase direction FLATTENED onto the horizontal plane, so
		-- pitch measures true elevation from the horizon (symmetric up/down, no built-in tilt bias); then yaw about
		-- world-up and elevate (pitch) about the yaw-rotated world-horizontal right axis. Same orbit construction /
		-- pitch sign as before, so the mouse->look mapping (CS-3) is preserved.
		local behind = Vector3.new(chaseDir.X, 0, chaseDir.Z)
		behind = (behind.Magnitude > EPS) and behind.Unit or Vector3.new(0, 0, 1)
		local yawCF = CFrame.fromAxisAngle(Vector3.yAxis, freeLook.yaw)
		-- Yaw-orbit the horizontal bird->camera direction about world-up.
		local dirH = yawCF:VectorToWorldSpace(behind)            -- horizontal, yaw-rotated
		-- Pitch (elevation) MUST rotate about THIS direction's own horizontal-right, not a fixed world-X.
		-- BUGFIX (2026-07-01): the old pitchAxis = yawCF*xAxis was tied to world-X, so when the bird's heading
		-- made `behind` line up with it, pitching rotated the view about its own axis and did nothing — up/down
		-- pan worked or not depending on heading ("I can't pan up/down… has to be consistent"). Deriving the
		-- axis from dirH makes elevation ALWAYS tilt up/down for any heading. Sign (yAxis × dirH) preserves the
		-- prior CS-3 up/down mapping; camUp stays hard world-up (CS-2 upright); the 85° soft-stop clamp is applied
		-- above. yaw orbit unchanged.
		local pitchAxis = Vector3.yAxis:Cross(dirH)
		pitchAxis = (pitchAxis.Magnitude > EPS) and pitchAxis.Unit or yawCF:VectorToWorldSpace(Vector3.xAxis)
		local dir = CFrame.fromAxisAngle(pitchAxis, freeLook.pitch):VectorToWorldSpace(dirH) -- bird->camera dir
		cameraOffset = dir * dist
		camUp = Vector3.yAxis -- hard world-up: operator never rolls/inverts (lookAt levels the horizon)
	end

	local camPos  = position + cameraOffset
	-- Look slightly AHEAD of the bird along its flight path (the bird then sits a touch low in frame for a
	-- forward-leaning, lead-the-target feel). camUp is the continuous up reference -> no inverted roll snap.
	-- In free-look, look straight at the bird (no flight-path lead) so the orbit is fully world-referenced
	-- and the look target doesn't wobble as the bird's heading swings through a loop; lead only in chase mode.
	-- Look target: centred on the HEADING (chase) / the bird (free-look). RIGHT-CLICK ZOOM FOCUSES INTO THE AIM
	-- RETICLE (player ask): as the zoom engages, the look swings to look FAR along the bird's BEAK direction
	-- (cf.LookVector — the reticle), so the telescope magnifies the AIM POINT and the bird (which fades) is no
	-- longer the focus. Using the LIVE beak direction (not the frozen aim cursor, which stops updating while zoom
	-- suspends steering) makes the zoom centre FOLLOW THE RETICLE as you fly. Steering is suspended while zooming,
	-- so this look swing can't feed back into flight.
	local lookTarget
	if freeLook.active then
		lookTarget = position
	else
		-- CHASE FRAMING (S30): raise the look target along camUp so the view tilts UP — the resting aim/nose lands
		-- at screen CENTRE and the bird sits LOWER in frame (Chad). camUp is the framing up (pre-bank-tilt). 0 = old.
		lookTarget = position + headingRef * (dist * 0.12) + camUp * (dist * (CAM.chaseLookUp or 0))
		if aimZoom.factor > 1e-3 then
			-- Look FAR along the beak so the telescope magnifies the aim point (distance matched to the reticle's
			-- 4000 projection). The zoom centres this exact world point; the aim reticle (shown during zoom in the
			-- input/render block) is drawn from the SAME point through the SAME camera, so they coincide on screen.
			lookTarget = lookTarget:Lerp(position + cf.LookVector * 4000, aimZoom.factor)
		end
	end
	local targetCF = CFrame.lookAt(camPos, lookTarget, camUp)

	-- Bank tilt: roll the camera slightly with the bird in a turn, but FADE it out as the bird inverts
	-- (uprightFade) so the loop crest doesn't whip the camera over.
	if not freeLook.active then
		local bankAngle = math.asin(math.clamp(cf.RightVector.Y, -1, 1))
		local uprightFade = math.clamp(cf.UpVector.Y, 0, 1)
		targetCF = targetCF * CFrame.Angles(0, 0, bankAngle * CAM.bankTiltFactor * uprightFade)
	end

	-- Crest damping: when the facing spikes (loop top) soften the follow so the camera glides through instead
	-- of whipping. crestBlend was computed above (it also drives the loop turn-over). Camera-only.
	local smoothing  = CAM.followSmoothing * (1 - crestBlend * (CAM.crestDamp or 0.75))
	-- FREE-LOOK CRISPNESS (P5 "it feels like it gets stuck"): the orbit used to inherit the heavy chase
	-- smoothing (0.18 ≈ 16%/frame) so the view crawled after the mouse. While free-looking, track near-1:1
	-- with the much higher freeLookSmoothing instead. The single biggest "unstick". Chase smoothing unchanged.
	if freeLook.active then
		smoothing = CAM.freeLookSmoothing or smoothing
	elseif cameraState.snapToChase then
		-- CS-2 EXIT SNAP (Chad 2026-07-02): on leaving free-look, re-centre on the heading with the CRISP
		-- free-look tracking rate for a few frames (~50-80 ms) instead of the slow followSmoothing sweep (a
		-- ~3/4 s disorienting swing through a side view). NOT a hard 1-frame teleport: during free-look the
		-- chase-up stops self-levelling, so after a fast loop the stored up can be tilted — a teleport would
		-- flash that tilted horizon for a frame. The fast ease lets the up re-level in step (no jarring cut).
		smoothing = CAM.freeLookSmoothing or smoothing
	end

	-- Frame-rate independent smoothing toward the target.
	local alpha = math.clamp(1 - math.exp(-smoothing * 60 * dt), 0, 1)
	camera.CFrame = camera.CFrame:Lerp(targetCF, alpha)
	-- Consume the exit-snap fast-return once the view has essentially reached the chase heading (or if
	-- free-look was re-armed). One-shot per exit; setFreeLook re-sets it on the next release. The 0.4 s
	-- time failsafe (S28e red-team F5) guarantees consumption even when a sustained fast turn keeps the
	-- moving-target dot test just out of reach (the fast-return itself completes in ~50-80 ms, so 0.4 s
	-- is far past any legitimate window).
	if cameraState.snapToChase then
		cameraState.snapT = (cameraState.snapT or 0) + dt
		if freeLook.active or camera.CFrame.LookVector:Dot(targetCF.LookVector) > 0.9995
			or cameraState.snapT > 0.4 then
			cameraState.snapToChase = nil
			cameraState.snapT = nil
		end
	end

	-- High-speed shake.
	if speed > CAM.shakeAtSpeed then
		local intensity = ((speed - CAM.shakeAtSpeed) / 100) * CAM.shakeMagnitude
		camera.CFrame = camera.CFrame * CFrame.new(
			(math.random() - 0.5) * intensity,
			(math.random() - 0.5) * intensity,
			0
		)
	end

	-- RESCUE SLOW-MO CAMERA DECORATION (beat-time only; identity when env=0). A PURE post-transform on
	-- the LOCKED chase's OUTPUT: pull the camera in and cant it during the catch. Never reads input,
	-- never feeds the aim/control frame; returns to identity as the beat ends. See rescueCam + the rescue
	-- section. This is the sanctioned layer-on decoration (rescue-gameplay-architect), NOT a chase edit.
	local rEnv = (GameConfig.Rescue and GameConfig.Rescue.enabled) and (rescueCam.env or 0) or 0
	if rEnv > 1e-3 then
		local RC = GameConfig.Rescue
		local pull = (RC.camPullIn or 0.15) * dist * rEnv
		local cant = math.rad(RC.camCant or 4) * rEnv
		camera.CFrame = camera.CFrame * CFrame.new(0, 0, -pull) * CFrame.Angles(0, 0, cant)
	end

	-- FOV by dive/climb/speed.
	local targetFOV = CAM.baseFOV
	if flightEngine.isDiving then
		targetFOV = CAM.diveFOV
	elseif flightEngine.verticalSpeed > 30 then
		targetFOV = CAM.climbFOV
	end
	-- AIM-ZOOM narrows the FOV LAST so it composes with (doesn't get stomped by) the attitude/speed FOV.
	if aimZoom.factor > 1e-3 then
		targetFOV = targetFOV + ((CAM.aimFOV or 45) - targetFOV) * aimZoom.factor
	end
	-- Rescue slow-mo FOV narrow (composes last; identity when env=0 — shrinks optic flow → reads as slow).
	if rEnv > 1e-3 then
		targetFOV = targetFOV + (GameConfig.Rescue.camFovDelta or -5) * rEnv
	end
	-- Floor lowered 50 -> 12 so the right-click zoom (aimFOV) can actually reach a strong telescope
	-- magnification (the old 50 floor was capping it). Normal dive/climb/base FOVs are all well above this.
	camera.FieldOfView = math.clamp(
		camera.FieldOfView + (targetFOV - camera.FieldOfView) * math.clamp(dt * 6, 0, 1),
		12, 110
	)

	-- Fade the eagle locally while right-click zooming so its opaque body can't block the telescoped
	-- outward view (this is the "the eagle is just big and in the way" fix).
	applyBirdFade(aimZoom.factor)
end

--------------------------------------------------------------------------------
-- UI HOOKS (exposed by GameUI via _G). Safe if the UI hasn't registered yet.
--------------------------------------------------------------------------------
local function pushUI()
	if type(_G.SetStallWarning) == "function" then
		pcall(_G.SetStallWarning, flightEngine.isStalling)
	end
	if type(_G.UpdateStaminaUI) == "function" then
		local maxStamina = (currentProfile and currentProfile.maxStamina) or 100
		pcall(_G.UpdateStaminaUI, flightEngine.stamina / math.max(1, maxStamina))
	end
	if type(_G.SetIncidence) == "function" then
		-- Body pitch: the angle of the bird's nose above/below the world horizon (0°).
		-- Pure attitude — nothing aerodynamic (no AoA, lift, or stall). + = nose up.
		local look = flightEngine.orientation.LookVector
		local pitchDeg = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
		pcall(_G.SetIncidence, pitchDeg)
	end
	if type(_G.UpdateFlapUI) == "function" then
		-- Sticky flap throttle readout: signed throttle (-1 down .. +1 up), wingbeat Hz, power-per-stroke.
		pcall(_G.UpdateFlapUI, flightEngine.flapThrottle or 0, flightEngine.flapFreqHz or 0, flightEngine.flapPower or 0)
	end
end

--------------------------------------------------------------------------------
-- COLLISION PARAMS — reused Spherecast filter that ignores all birds (so we only
-- sweep against the Map). Built lazily once Workspace.Birds exists (it does by the
-- time we're driving a bird that lives inside it).
--------------------------------------------------------------------------------
local collisionParams = nil
local function getCollisionParams()
	local birds = workspace:FindFirstChild("Birds")
	if not birds then return nil end
	if not collisionParams then
		collisionParams = BirdCollision.makeParams(birds)
	end
	return collisionParams
end

--------------------------------------------------------------------------------
-- WINGTIP STALL VORTICES — wispy vapor streaming off each wingtip that fades IN as the bird's AoA
-- nears the stall angle (a visible loss-of-lift cue). Client cosmetic on the possessed bird only;
-- driven each frame from flightEngine.aoaDeg vs the profile stall angle. Built once per acquired model.
--------------------------------------------------------------------------------
local vortexTrails = {}     -- array of Trail (one per wingtip)
local lastVortexT  = -1     -- last applied transparency, to skip redundant NumberSequence churn
local function buildVortexTrails(model)
	vortexTrails = {}
	lastVortexT = -1
	if not model then return end
	for _, side in ipairs({ "LeftWing", "RightWing" }) do
		local wing = model:FindFirstChild(side)
		if wing and wing:IsA("BasePart") then
			local existing = wing:FindFirstChild("VortexTrail")
			if existing then
				table.insert(vortexTrails, existing)
			else
				local sx = (side == "RightWing") and 1 or -1
				local a0 = Instance.new("Attachment"); a0.Name = "VortA0"
				a0.Position = Vector3.new(sx * wing.Size.X * 0.5, 0, -wing.Size.Z * 0.3); a0.Parent = wing
				local a1 = Instance.new("Attachment"); a1.Name = "VortA1"
				a1.Position = Vector3.new(sx * wing.Size.X * 0.5, 0,  wing.Size.Z * 0.3); a1.Parent = wing
				local tr = Instance.new("Trail")
				tr.Name = "VortexTrail"
				tr.Attachment0 = a0
				tr.Attachment1 = a1
				tr.Lifetime = 0.45
				tr.MinLength = 0
				tr.FaceCamera = true
				tr.LightEmission = 0.4
				tr.Color = ColorSequence.new(Color3.fromRGB(232, 240, 255))
				tr.Transparency = NumberSequence.new(1) -- invisible until near stall (set per frame)
				tr.WidthScale = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				})
				tr.Parent = wing
				table.insert(vortexTrails, tr)
			end
		end
	end
end

local function updateVortexTrails()
	if not (flightEngine and currentProfile) or #vortexTrails == 0 then return end
	local stallAngle = currentProfile.stallAngleDeg or 24
	local band = 8 -- degrees before stall over which the vapor fades in
	local f = math.clamp((math.abs(flightEngine.aoaDeg or 0) - (stallAngle - band)) / band, 0, 1)
	local t = 1 - 0.7 * f -- 1 (invisible) .. 0.3 (wispy but clearly visible) at/over the stall
	if math.abs(t - lastVortexT) < 0.02 then return end
	lastVortexT = t
	local seq = NumberSequence.new(t)
	for _, tr in ipairs(vortexTrails) do
		tr.Transparency = seq
	end
end

--------------------------------------------------------------------------------
-- CONTACT JUICE — FEATHERS (S31, phase 1). The server fires CombatFX(cause, position, victimTeam,
-- killed) at every contact/death (GameServer.applyDamage); here we burst a feather cloud at the point.
-- Pooled, distance-gated, zero per-hit Instance creation: a small ring of anchored emitter parts is
-- built once and reused round-robin, so a 4-crow melee never allocates. Purely cosmetic — no gameplay,
-- no kernel, no camera-law touch. Swap `FEATHER_TEXTURE` for a real feather decal when art lands.
--------------------------------------------------------------------------------
local FEATHER_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- soft placeholder; replace w/ feather decal
local featherPool   = {}     -- array of {part, emitter}
local featherCursor = 0
local FEATHER_POOL_N = 6

local function buildFeatherPool()
	if #featherPool > 0 then return end
	local fx = GameConfig.Combat and GameConfig.Combat.fx
	for _ = 1, FEATHER_POOL_N do
		local part = Instance.new("Part")
		part.Name = "FeatherFX"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Locked = true
		local em = Instance.new("ParticleEmitter")
		em.Texture = FEATHER_TEXTURE
		em.Rate = 0 -- burst-only, via :Emit
		em.Lifetime = NumberRange.new((fx and fx.featherLifeMin) or 0.8, (fx and fx.featherLifeMax) or 1.4)
		em.Speed = NumberRange.new(((fx and fx.featherSpeed) or 22) * 0.5, (fx and fx.featherSpeed) or 22)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Acceleration = Vector3.new(0, -((fx and fx.featherGravity) or 30), 0) -- flutter-fall, don't rocket off
		em.Drag = 4 -- air resistance so they slow and settle like real feathers
		em.Rotation = NumberRange.new(0, 360)
		em.RotSpeed = NumberRange.new(-200, 200)
		local fsz = (fx and fx.featherSize) or 1.5
		em.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, fsz),
			NumberSequenceKeypoint.new(1, fsz * 0.25),
		})
		em.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),    -- spawn fully opaque so the burst is unmissable
			NumberSequenceKeypoint.new(0.75, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		em.LightEmission = 0
		em.Parent = part
		part.Parent = workspace
		featherPool[#featherPool + 1] = { part = part, emitter = em }
	end
end

-- Burst `count` feathers of `color` at world `pos` using the next pooled emitter.
local function burstFeathers(pos, color, count)
	buildFeatherPool()
	if #featherPool == 0 then return end
	featherCursor = (featherCursor % #featherPool) + 1
	local slot = featherPool[featherCursor]
	slot.part.Position = pos
	slot.emitter.Color = ColorSequence.new(color)
	slot.emitter:Emit(count)
end

local FEATHER_CROW  = Color3.fromRGB(28, 28, 34)   -- crow victim: near-black
local FEATHER_EAGLE = Color3.fromRGB(96, 66, 40)   -- eagle victim: brown body feathers

CombatFX.OnClientEvent:Connect(function(cause, position, victimTeam, _killed)
	local fx = GameConfig.Combat and GameConfig.Combat.fx
	if not (fx and fx.enabled) or typeof(position) ~= "Vector3" then return end
	-- Distance gate: skip FX far from this client's view (swarm cost guard).
	if camera and (camera.CFrame.Position - position).Magnitude > (fx.range or 400) then return end
	local eagleVictim = (victimTeam == "Eagles")
	local color = eagleVictim and FEATHER_EAGLE or FEATHER_CROW
	local count
	if eagleVictim then
		count = fx.featherRam or 40           -- eagle took a ram
	elseif _killed then
		count = fx.featherCrowDeath or 42     -- a crow KILLED — the big payoff cloud
	else
		count = fx.featherStrike or 22        -- a strike that clipped but didn't kill
	end
	burstFeathers(position, color, count)
end)

--------------------------------------------------------------------------------
-- UPDRAFT PROXIMITY SCORE (S31 Phase 0 — "is line-riding FUN?"). Fly CLOSE to terrain → combo grows
-- (closer + faster + longer) → BANK it by pulling away clean, or LOSE it in a crash (feather puff, keep
-- flying — non-lethal). Client-computed for feel; a self-contained prototype HUD to fold into GameUI once
-- the loop is proven. Tunables live in GameConfig.Updraft. Reuses the feather pool + collision params.
--------------------------------------------------------------------------------
local updraft = { score = 0, combo = 0, mult = 1, awayTime = 0, riding = false }
local UP_DIRS = {
	Vector3.new(0, -1, 0),  Vector3.new(0, 1, 0),
	Vector3.new(1, 0, 0),   Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),   Vector3.new(0, 0, -1),
	Vector3.new(0.7, -0.7, 0),  Vector3.new(-0.7, -0.7, 0),
	Vector3.new(0, -0.7, 0.7),  Vector3.new(0, -0.7, -0.7),
}

-- Nearest terrain distance around the bird (min over a fan of rays), or math.huge if nothing within range.
local function computeProximity(pos, maxDist)
	local params = getCollisionParams()
	if not params then return math.huge end
	local best = math.huge
	for _, dir in ipairs(UP_DIRS) do
		local hit = workspace:Raycast(pos, dir * maxDist, params)
		if hit then
			local d = (hit.Position - pos).Magnitude
			if d < best then best = d end
		end
	end
	return best
end

-- Prototype score HUD (self-contained; moves into GameUI when the loop is proven).
local updraftGui, updraftScoreLbl, updraftComboLbl
local function buildUpdraftHUD()
	if updraftGui then return end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	updraftGui = Instance.new("ScreenGui")
	updraftGui.Name = "UpdraftHUD"
	updraftGui.ResetOnSpawn = false
	updraftGui.IgnoreGuiInset = true
	updraftGui.Parent = pg
	updraftScoreLbl = Instance.new("TextLabel")
	updraftScoreLbl.BackgroundTransparency = 1
	updraftScoreLbl.AnchorPoint = Vector2.new(0.5, 0)
	updraftScoreLbl.Position = UDim2.new(0.5, 0, 0.03, 0)
	updraftScoreLbl.Size = UDim2.new(0, 420, 0, 46)
	updraftScoreLbl.Font = Enum.Font.GothamBold
	updraftScoreLbl.TextScaled = true
	updraftScoreLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	updraftScoreLbl.TextStrokeTransparency = 0.4
	updraftScoreLbl.Text = "0"
	updraftScoreLbl.Parent = updraftGui
	updraftComboLbl = Instance.new("TextLabel")
	updraftComboLbl.BackgroundTransparency = 1
	updraftComboLbl.AnchorPoint = Vector2.new(0.5, 0)
	updraftComboLbl.Position = UDim2.new(0.5, 0, 0.115, 0)
	updraftComboLbl.Size = UDim2.new(0, 380, 0, 34)
	updraftComboLbl.Font = Enum.Font.GothamBold
	updraftComboLbl.TextScaled = true
	updraftComboLbl.TextColor3 = Color3.fromRGB(255, 210, 90)
	updraftComboLbl.TextStrokeTransparency = 0.5
	updraftComboLbl.Text = ""
	updraftComboLbl.Parent = updraftGui
end

local function updateUpdraftHUD(closeness)
	buildUpdraftHUD()
	updraftScoreLbl.Text = "🪶 " .. string.format("%d", math.floor(updraft.score + 0.5))
	if updraft.combo >= 1 then
		updraftComboLbl.Text = string.format("COMBO  x%.1f   +%d", updraft.mult, math.floor(updraft.combo))
		local c = math.clamp(closeness, 0, 1)
		updraftComboLbl.TextColor3 = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 170, 30), 0.35 + 0.65 * c)
		updraftComboLbl.TextTransparency = 0
	else
		updraftComboLbl.TextTransparency = 1
	end
end

-- Advance the line-riding score one frame. `crashed` comes from the collision resolve in onFlightStep.
local function updateUpdraft(dt, crashed)
	local U = GameConfig.Updraft
	if not (U and U.enabled) or not (rootPart and rootPart.Parent) then return end
	local pos = rootPart.Position
	local speed = (flightEngine and flightEngine.speed) or 0

	if crashed then
		if updraft.combo > 0 then
			updraft.combo = updraft.combo * (1 - (U.crashLoss or 1))
			updraft.mult = 1
			burstFeathers(pos, FEATHER_EAGLE, 30) -- crash puff — non-lethal, you keep flying
		end
		updraft.awayTime = 0
		updraft.riding = false
		updateUpdraftHUD(0)
		return
	end

	local minDist = computeProximity(pos, U.proximityDist or 45)
	local closeness = 0
	if minDist < (U.proximityDist or 45) then
		closeness = math.clamp((U.proximityDist - minDist) / math.max(1, (U.proximityDist or 45) - (U.sweetSpot or 8)), 0, 1)
	end

	if closeness > 0 and speed >= (U.minSpeed or 55) then
		local speedFactor = math.clamp(speed / (U.refSpeed or 160), 0, 1.5)
		updraft.combo = updraft.combo + closeness * speedFactor * (U.comboRate or 120) * dt
		updraft.mult = math.min(U.multMax or 8, updraft.mult + closeness * (U.multPerSec or 0.6) * dt)
		updraft.awayTime = 0
		updraft.riding = true
	else
		updraft.riding = false
		if updraft.combo > 0 then
			updraft.awayTime = updraft.awayTime + dt
			if updraft.awayTime >= (U.bankDelay or 0.8) then
				updraft.score = updraft.score + updraft.combo * updraft.mult -- BANK the line
				updraft.combo = 0
				updraft.mult = 1
				updraft.awayTime = 0
			end
		end
	end
	updateUpdraftHUD(closeness)
end

--------------------------------------------------------------------------------
-- EAGLES TO THE RESCUE (S32 Phase 0) — the SACRED slow-mo auto-catch, carry, deliver, style.
-- Design: docs/rescue-consults/PACKET-01-the-catch.md (Fable). Built AROUND the LOCKED kernel + camera
-- (detection + presentation ONLY; the sim + input run real-time). Fable's key insight: the intercept
-- solve drives the squirrel's RELATIVE velocity to ~0, so a real-time object wearing dilated FX READS
-- as slow-mo — we never dilate world motion. All numbers in GameConfig.Rescue.
--------------------------------------------------------------------------------
local RES = GameConfig.Rescue
local SoundService = game:GetService("SoundService")
local Lighting     = game:GetService("Lighting")

local function lerpN(a, b, t) return a + (b - a) * t end

-- Rescue remotes (RescueServer's OWN folder; wired in a task so WaitForChild can't stall startup).
local catchRemote, deliverRemote
local rescueState = {
	phase = "intermission", carry = 0, capacity = (RES and RES.carryCapacity) or 3,
	score = 0, delivered = 0, rescued = 0, timeLeft = 0, combo = 0,
	-- optional; the server sends these only once the PERFECT-TEN finale lands at results.
	timeFactor = nil :: number?, preFactorScore = nil :: number?,
}
task.spawn(function()
	if not (RES and RES.enabled) then return end
	local rr = ReplicatedStorage:WaitForChild("RescueRemotes", 30)
	if not rr then return end
	catchRemote   = rr:WaitForChild("CatchSquirrel")
	deliverRemote = rr:WaitForChild("DeliverSquirrels")
	rr:WaitForChild("RescueState").OnClientEvent:Connect(function(s)
		if type(s) == "table" then rescueState = s end
	end)
end)

local squirrelsFolder
task.spawn(function()
	if RES and RES.enabled then squirrelsFolder = workspace:WaitForChild("Squirrels", 30) end
end)

-- Presentation models (leaping squirrel + back-riders) live here — client-only, never queried.
local catchFxFolder
local function ensureCatchFx()
	if catchFxFolder and catchFxFolder.Parent then return catchFxFolder end
	catchFxFolder = Instance.new("Folder")
	catchFxFolder.Name = "RescueCatchFX"
	catchFxFolder.Parent = workspace
	return catchFxFolder
end

-- Desaturate grammar for slow-mo (Fable §B) — a local ColorCorrectionEffect, driven by the beat env.
local rescueCC
local function slowmoDesat(env)
	if not rescueCC then
		rescueCC = Instance.new("ColorCorrectionEffect")
		rescueCC.Name = "RescueSlowmoCC"
		rescueCC.Parent = Lighting
	end
	rescueCC.Enabled = env > 0.01
	rescueCC.Saturation = -0.55 * env
	rescueCC.Brightness = 0.03 * env
	rescueCC.Contrast   = 0.06 * env
end

--------------------------------------------------------------------------------
-- SOUND (gray-box — Fable §E: rbxasset content + PlaybackSpeed = intervals/pitch-bends). If an id
-- doesn't resolve in this build it simply stays silent (no error); Chad reports which resolved.
--------------------------------------------------------------------------------
local SFX_PING   = "rbxasset://sounds/electronicpingshort.wav"
-- S36 #14: swoosh.wav returns "Asset is not approved for the requester" (Chad's Output log ×70) so every
-- hup/whip/pomf-whoosh was silent. action_falling.ogg is a locally-shipped, moderation-immune wind whoosh
-- (the R15 falling sound) — it pitches the same way and doubles as the base WIND STEM in updateMusic.
local SFX_SWOOSH = "rbxasset://sounds/action_falling.ogg"
local SFX_SNAP   = "rbxasset://sounds/switch.wav"

local function playSound(id, vol, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.5
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(4, function() if s and s.Parent then s:Destroy() end end)
	return s
end
-- rising major-third "magic" chord: root then ×1.26.
local function playChord()
	playSound(SFX_PING, 0.5, 1.0)
	task.delay(0.12, function() playSound(SFX_PING, 0.5, 1.26) end)
end
local function playPomf()
	playSound(SFX_SNAP, 0.7, 0.55)          -- soft low pillow-thump
	playSound(SFX_SWOOSH, 0.35, 0.7)
end
local function playGotcha()
	playSound(SFX_PING, 0.6, 1.0)
	task.delay(0.08, function() playSound(SFX_PING, 0.6, 1.5) end)  -- bright two-note stinger
end
local function playHup()
	playSound(SFX_SWOOSH, 0.3, 2.0)         -- tiny-creature effort, pitched up
end
local function playWhip()
	playSound(SFX_SWOOSH, 0.45, 1.2)
end
local function playCount(i)
	-- MATH DELIVERY hop-off counting note: one ping per dismount, stepping UP each time so the
	-- skip-count is heard as a rising scale (the tally ticking toward n²).
	playSound(SFX_PING, 0.5, 1.0 + 0.12 * (math.max(1, i) - 1))
end
local function playWoohoo()
	-- a happy "wheee!" — one tone bent up 1.2 -> 2.0 while playing.
	local s = playSound(SFX_PING, 0.5, 1.2)
	if s then
		task.spawn(function()
			for i = 1, 8 do
				if not (s and s.Parent) then return end
				s.PlaybackSpeed = 1.2 + (0.8 * i / 8)
				task.wait(0.035)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- RESCUE STATE (client)
--------------------------------------------------------------------------------
local styleMeter = 0            -- 0..(styleMultMax-1); charges on line-riding, feeds styleMult = 1 + meter
local catchCount = 0            -- lifetime catches (FTUE generosity for the first few)
local squirrelPhase = 0         -- drives the wave animation
local tellId = nil              -- the squirrel currently showing the "determined survivor" tell
local tellTimer = 0             -- latch countdown (Fable: hold the tell ≥ tellHoldMin)
local softFailId = nil          -- a squirrel you flew INTO but too slow to catch (FTUE soft-fail wave)
local softFailTimer = 0         -- latch countdown for the "come back!" reaction
local lastFullHint = -1e9       -- os.clock() of the last "WINGS FULL" HUD nudge (debounce)
-- CLAIM GUARD (S35c): [SquirrelId] = os.clock() when we fired a catch for it. The world squirrel stays
-- in Workspace with State="stranded" until the server's Destroy REPLICATES (1+ frames) — without this
-- guard the very next frame re-triggered the SAME squirrel as a crew catch; the server silently rejected
-- the duplicate id and the phantom rider got reconcile-trimmed later (Chad: "went down from 9 to 8 after
-- a catch"). The old single-slot `not catch` lock hid this; Crew Catch v1 removed it. TTL'd so a squirrel
-- whose catch the server genuinely rejected becomes catchable again instead of permanently dead.
local claimedIds = {}
local function isClaimed(id)
	local at = id and claimedIds[id]
	if not at then return false end
	if os.clock() - at > (RES.claimTTL or 3) then claimedIds[id] = nil; return false end
	return true
end
local catch = nil               -- the SACRED talon catch beat (single; slow-mo) or nil
local hopOff = nil              -- MATH-DELIVERY dismount ceremony: { n, i, t } while riders hop off one
                                -- per beat at the safe pad (Packet-03 §3 layer 1), or nil
local crewCheer = 0             -- s left of the whole-crew "we got one!" cheer after a crew catch lands
local crewCatches = {}          -- CREW CATCHES (Crew Catch v1): overlapping LIGHT catches that fire while
                                -- the sacred `catch` is busy, so a fast chain never drops (no slow-mo). Each
                                -- = { sq, t, airtime, startPos, contactDone }; converts to a rider on contact.
local riders = {}               -- back-riders: array of { model = Model }
local deliverCooldown = 0

local function eagleGlide()
	return (currentProfile and currentProfile.glideSpeed) or 130
end

-- The eagle model is visually scaled up on the server (GameServer model:ScaleTo(birdScale)). The talon
-- and back-seat offsets multiply by the SAME factor so the leap target and the riders track the scaled
-- body — otherwise they sit embedded near the un-scaled centre (why riders read low before). Balance-
-- neutral: bodyRadius (collision/reach) is unchanged; this only moves cosmetic attach points.
local BIRD_SCALE = (GameConfig.Visual and GameConfig.Visual.birdScale) or 1

-- The talon "basket" — a point just under the belly the leap intercepts (scaled with the visual body).
local function talonPos()
	return rootPart.CFrame * (Vector3.new(0, -2.4, 0.3) * BIRD_SCALE)
end

-- Grid-packed seats on the back so up to `carryCapacity` (10) riders fit as a little pile of clinging
-- critters: SEAT_COLS across the spine, the rest stacking toward the tail (each back row sits a touch
-- higher). Rider `i` always maps to the same seat, so the climb path is stable per rider.
local SEAT_COLS = 4
-- Local (eagle-frame) seat position for rider `i` (1-based); the world seat = rootPart.CFrame * this.
local function seatLocalPos(i)
	local r = (((currentProfile and currentProfile.bodyRadius) or 4.5)) * BIRD_SCALE
	local idx = math.max(0, i - 1)
	local col = idx % SEAT_COLS
	local row = math.floor(idx / SEAT_COLS)
	local colOff = col - (SEAT_COLS - 1) * 0.5            -- centre the columns across the spine
	-- factors are relative to the SCALED radius, so the pile fits the bigger (scale 4.4) riders on the
	-- bigger (birdScale) back without fully overlapping.
	return Vector3.new(colOff * (r * 0.4), r * 0.7 + row * (r * 0.1), r * 0.2 + row * (r * 0.42))
end

-- Where rider `i` (1-based) sits on the back.
local function seatCFrame(i)
	return rootPart.CFrame * CFrame.new(seatLocalPos(i))
end

-- Quadratic Bézier p0→(p1)→p2 (used by the #9 climb-and-latch path).
local function bezier3(p0, p1, p2, t)
	local a = p0:Lerp(p1, t)
	local b = p1:Lerp(p2, t)
	return a:Lerp(b, t)
end

-- The talon "basket" in the eagle's LOCAL frame (matches talonPos()'s SCALED offset). Start of the climb.
local TALON_LOCAL   = Vector3.new(0, -2.4, 0.3) * BIRD_SCALE
local SCRAMBLE_FREQ = 26                 -- rad/s; how fast the limbs scurry during the climb-up.

-- LIVING BACK-RIDERS (Fable §C) — cosmetic per-rider life applied on TOP of the seat CFrame + ride pose.
-- Pure client presentation (client-only models in CatchFx); never touches control/camera/kernel.
local RIDER_BOB_AMP  = 0.35 * BIRD_SCALE  -- studs; breathing bob amplitude (off the eagle's wingbeat)
local RIDER_LEAN     = math.rad(5)      -- rad; gentle body lean that breathes with the bob
local RIDER_LOOK     = math.rad(22)     -- rad; slow independent look-around yaw amplitude
local RIDER_HOP_DUR  = 0.48             -- s; hop-and-settle duration when a rider first lands
local RIDER_HOP_AMP  = 1.1 * BIRD_SCALE   -- studs; peak of the landing hop (scales with the visual body)
local RIDER_GROW_DUR = 0.35             -- s; courage-growth ease (an instant ScaleTo snap reads as a glitch)

local FEATHER_GOLD = Color3.fromRGB(255, 210, 90)

-- A quick expanding gold ring at the catch (pooled-free; self-destructs). `scale` swells it for a
-- bigger beat on high-style / high-speed catches (Fable #5).
local function goldRing(pos, scale)
	scale = scale or 1
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, 4, 4)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = FEATHER_GOLD
	ring.Transparency = 0.1
	ring.Parent = ensureCatchFx()
	task.spawn(function()
		for i = 1, 12 do
			if not ring.Parent then return end
			local sc = (1 + i * 2.2) * scale
			ring.Size = Vector3.new(0.6, 4 * sc, 4 * sc)
			ring.Transparency = 0.1 + 0.9 * (i / 12)
			task.wait(0.02)
		end
		ring:Destroy()
	end)
end

-- Build the client-only presentation squirrel that leaps + then rides.
local function buildPresentationSquirrel(color)
	local sq = BirdBuilder.BuildSquirrel(RES.squirrelScale or 2.4, { body = color })
	for _, p in ipairs(sq:GetDescendants()) do
		if p:IsA("BasePart") then p.CanQuery = false; p.CanTouch = false; p.CanCollide = false end
	end
	if sq.PrimaryPart then sq.PrimaryPart.Anchored = true end
	-- gold mote trail off the body (dilated during slow-mo).
	local att = Instance.new("Attachment")
	att.Parent = sq.PrimaryPart
	local mote = Instance.new("ParticleEmitter")
	mote.Name = "Mote"
	mote.Color = ColorSequence.new(FEATHER_GOLD)
	mote.LightEmission = 0.8
	mote.Size = NumberSequence.new(0.9, 0.1)
	mote.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	mote.Lifetime = NumberRange.new(0.5, 0.9)
	mote.Rate = 40
	mote.Speed = NumberRange.new(2, 6)
	mote.Parent = att
	sq.Parent = ensureCatchFx()
	return sq
end

-- Slow-mo intensity for the active catch beat (Fable §A envelope).
local function catchEnv()
	if not catch then return 0 end
	local ei = RES.slowmoEaseIn or 0.11
	local contactEnd = catch.airtime + (RES.hitStopFrames or 3) / 60
	local sb = RES.slowmoSnapBack or 0.20
	local t = catch.t
	if t < ei then
		local x = t / ei; return 1 - (1 - x) * (1 - x)
	elseif t <= contactEnd then
		return 1
	elseif t <= contactEnd + sb then
		local x = (t - contactEnd) / sb; return 1 - x * x
	end
	return 0
end

-- BEGIN a catch on `sqModel` (a stranded world squirrel). Fires the authoritative catch to the server
-- (it removes the world squirrel + scores) and spins up the local presentation beat.
local function triggerCatch(sqModel, closing)
	local id = sqModel:GetAttribute("SquirrelId")
	if type(id) ~= "number" then return end
	claimedIds[id] = os.clock()      -- claim BEFORE anything else — one fire per squirrel, ever
	local body = sqModel.PrimaryPart
	local startPos = body and body.Position or (rootPart.Position + rootPart.CFrame.LookVector * 20)
	local color = (body and body.Color) or Color3.fromRGB(150, 96, 52)

	catchCount += 1
	local styleMult = clamp(1 + styleMeter, 1, RES.styleMultMax or 3)
	local glide = eagleGlide()
	local tier = ""
	if closing >= (RES.blazingFrac or 0.9) * glide then tier = "BLAZING"
	elseif closing >= (RES.swiftFrac or 0.6) * glide then tier = "SWIFT" end

	if catchRemote then catchRemote:FireServer(id, styleMult, tier) end

	local frac = clamp(closing / (glide * 1.2), 0, 1)
	local airtime = lerpN(RES.arcAirtimeMin or 0.5, RES.arcAirtimeMax or 0.85, frac)
	-- FIT-ONCE intercept (Fable §B2): predict where the talon WILL be at the end of the airtime and
	-- lock that as the leap's target NOW. The arc flies to this fixed point (a real ballistic jump),
	-- and only inside the converge window does it correct to the live talon — so the leap never
	-- looks like frame-by-frame homing (which reads fake and kills "the squirrel jumped to me").
	local aimPoint = talonPos() + flightEngine.velocity * airtime
	-- "Bigness" 0..1 (Fable #5): BLAZING/high-style catches earn a visibly bigger beat (deeper slow-mo,
	-- bigger burst, gold GOTCHA) — same guaranteed catch, escalating spectacle = the skill ceiling.
	local tierBig  = (tier == "BLAZING") and 1 or (tier == "SWIFT") and 0.5 or 0
	local styleBig = clamp((styleMult - 1) / math.max(1e-3, (RES.styleMultMax or 3) - 1), 0, 1)
	local big = clamp(math.max(tierBig, styleBig * 0.85), 0, 1)
	catch = {
		t = 0, airtime = airtime, startPos = startPos, aimPoint = aimPoint,
		sq = buildPresentationSquirrel(color), big = big,
		styleMult = styleMult, tier = tier, rarity = sqModel:GetAttribute("Rarity"),
		contactDone = false, converted = false,
	}
	styleMeter = 0            -- style is spent on the catch; re-earn a line for the next
	tellId = nil
	playHup()
	playChord()
	if _G.RescueStamp then _G.RescueStamp("tell") end
end

-- Advance the active catch beat one frame (arc → contact → hit-stop → rider → snap-back).
local function stepCatch(dt)
	if not catch then return end
	catch.t += dt
	local contactEnd = catch.airtime + (RES.hitStopFrames or 3) / 60
	local tp = talonPos()

	if catch.t < catch.airtime then
		-- LEAP: fly the FIXED fit-once intercept (set at launch). Only in the converge window blend to
		-- the LIVE talon so the catch still lands exactly on the moving eagle (that snap hides in the
		-- feather burst). No per-frame re-fit ⇒ reads as a real jump, not homing (Fable §B2).
		local u = clamp(catch.t / catch.airtime, 0, 1)
		local cf = RES.arcConvergeFrac or 0.85
		local target = catch.aimPoint or tp
		if u > cf then
			target = target:Lerp(tp, clamp((u - cf) / (1 - cf), 0, 1))
		end
		local flat = catch.startPos:Lerp(target, u)
		local apex = (RES.arcApexHeight or 10) * 4 * u * (1 - u)
		local pos = flat + Vector3.new(0, apex, 0)
		local look = rootPart.Position - pos
		local ori = (look.Magnitude > 1e-3) and CFrame.lookAt(pos, rootPart.Position) or CFrame.new(pos)
		if catch.sq and catch.sq.PrimaryPart then catch.sq:PivotTo(ori) end
		BirdBuilder.PoseSquirrel(catch.sq, "starfish", dt, 0)
	elseif catch.t < contactEnd then
		-- CONTACT + HIT-STOP: fire the juice ONCE, then hold frozen at the talon.
		if not catch.contactDone then
			catch.contactDone = true
			local big = catch.big or 0
			burstFeathers(tp, FEATHER_GOLD, 26 + math.floor(big * 34))     -- up to ~60 for a max catch
			goldRing(tp, 1 + big * 0.9)
			playPomf()
			playGotcha()
			if _G.RescueStamp then _G.RescueStamp("gotcha", catch.tier, catch.rarity, catch.styleMult, nil, big) end
			task.delay(contactEnd - catch.airtime + (RES.slowmoSnapBack or 0.2) + (RES.woohooDelay or 0.5), playWoohoo)
		end
		if catch.sq and catch.sq.PrimaryPart then catch.sq:PivotTo(CFrame.new(tp)) end  -- frozen
	else
		-- CLIMB-AND-LATCH (Chad's #9 vision: "eagle catches with talon → squirrel scrambles up to the
		-- eagle's back"). After the hit-stop the caught squirrel scurries up the flank from the talon to
		-- its destined back seat, then hands off to the #2 living-rider system. Runs in real time — the
		-- slow-mo snap-back (≤0.2s) rides down underneath the first part of the climb, so no extra tail.
		local climbDur = RES.climbDur or 0.5
		local ct = catch.t - contactEnd
		if not catch.climbStarted then
			catch.climbStarted = true
			catch.seatIndex = #riders + 1          -- the seat this rider is climbing toward (stable: single catch slot)
			playWhip()                             -- doubles as the slow-mo snap-back whip (same timing as before)
		end
		if ct < climbDur and catch.sq and catch.sq.PrimaryPart then
			local u = clamp(ct / climbDur, 0, 1)
			local e = u * u * (3 - 2 * u)          -- smoothstep ease
			-- talon → seat via a control point swung WIDE out to the flank and UP, so the scramble is
			-- silhouetted climbing up the side of the eagle (Chad: "make a bit more obvious of a climb")
			-- instead of hugging the belly out of sight.
			local p0 = TALON_LOCAL
			local p2 = seatLocalPos(catch.seatIndex)
			local r  = (((currentProfile and currentProfile.bodyRadius) or 4.5)) * BIRD_SCALE
			local sideX = (p2.X >= 0) and 1 or -1          -- centre-lane seats still swing out one side
			local p1 = Vector3.new(p2.X * 1.4 + sideX * r * 0.7, (p0.Y + p2.Y) * 0.5 + r * 0.3, -r * 0.3)
			local worldPos  = (rootPart.CFrame * CFrame.new(bezier3(p0, p1, p2, e))).Position
			local seatWorld = (rootPart.CFrame * CFrame.new(p2)).Position
			local dir = seatWorld - worldPos
			local ori = (dir.Magnitude > 1e-3)
				and CFrame.lookAt(worldPos, worldPos + dir, rootPart.CFrame.UpVector)
				or CFrame.new(worldPos)
			catch.sq:PivotTo(ori)
			BirdBuilder.PoseSquirrel(catch.sq, "scramble", dt, catch.t * SCRAMBLE_FREQ)
		end
		-- arrived on the back → become a living rider (the #2 substrate). HEIGHTEN THE RESOLVE (Chad): a
		-- full settle-hop + a little gold poof + a soft pomf so the latch reads as a satisfying arrival.
		if not catch.converted and ct >= climbDur then
			catch.converted = true
			local seatWorld = (rootPart.CFrame * CFrame.new(seatLocalPos(catch.seatIndex))).Position
			burstFeathers(seatWorld, FEATHER_GOLD, 14)
			playPomf()
			riders[#riders + 1] = {
				model  = catch.sq,
				phase  = math.random() * math.pi * 2,
				look   = math.random() * math.pi * 2,
				t      = 0,
				settle = RIDER_HOP_DUR,          -- full settle-hop = a clear "landed!" beat
			}
			catch.sq = nil
			catch = nil
		end
	end
end

-- CREW CATCH (Crew Catch v1): a squirrel that triggers WHILE the sacred `catch` is busy is NOT dropped —
-- the crew already on your back catches it. A quick LIGHT beat (no slow-mo, no camera env): a fast arc to
-- the talon, then it settles onto the back as a rider. This is what lets a fast chain build a combo. Fires
-- the same authoritative catch to the server, so it scores + increments the combo just like a talon catch.
local function triggerCrewCatch(sqModel, closing)
	local id = sqModel:GetAttribute("SquirrelId")
	if type(id) ~= "number" then return end
	claimedIds[id] = os.clock()      -- claim BEFORE anything else — one fire per squirrel, ever
	local body = sqModel.PrimaryPart
	local startPos = body and body.Position or (rootPart.Position + rootPart.CFrame.LookVector * 20)
	local color = (body and body.Color) or Color3.fromRGB(150, 96, 52)

	catchCount += 1
	local styleMult = clamp(1 + styleMeter, 1, RES.styleMultMax or 3)
	local glide = eagleGlide()
	local tier = ""
	if closing >= (RES.blazingFrac or 0.9) * glide then tier = "BLAZING"
	elseif closing >= (RES.swiftFrac or 0.6) * glide then tier = "SWIFT" end
	if catchRemote then catchRemote:FireServer(id, styleMult, tier) end
	styleMeter = 0
	tellId = nil
	-- v2 (Chad S35 "should be squirrels"): the newb leaps for the BACK, where the crew catches it —
	-- aim at the seat it's about to take (riders + everything already in flight ahead of it).
	local seatIdx = #riders + (catch and 1 or 0) + #crewCatches + 1
	crewCatches[#crewCatches + 1] = {
		sq = buildPresentationSquirrel(color), t = 0, seatIndex = seatIdx,
		airtime = RES.crewAirtime or 0.42, startPos = startPos, contactDone = false,
	}
	playHup()
end

-- Advance every in-flight crew catch: the newb arcs to the BACK, where the crew nets it (v2 — Chad S35
-- "should be squirrels") → light contact juice + a crew CHEER → becomes a rider on the spot.
local function stepCrewCatches(dt)
	for i = #crewCatches, 1, -1 do
		local cc = crewCatches[i]
		cc.t += dt
		-- the LIVE world position of the seat it's leaping for (the eagle keeps flying under it).
		local tp = (rootPart.CFrame * CFrame.new(seatLocalPos(cc.seatIndex or (#riders + 1)) + Vector3.new(0, 1.2, 0))).Position
		if cc.t < cc.airtime and cc.sq and cc.sq.PrimaryPart then
			local u = clamp(cc.t / cc.airtime, 0, 1)
			local flat = cc.startPos:Lerp(tp, u)
			local apex = (RES.arcApexHeight or 10) * 2.4 * u * (1 - u)   -- lower, snappier than the sacred leap
			local pos = flat + Vector3.new(0, apex, 0)
			local look = rootPart.Position - pos
			cc.sq:PivotTo((look.Magnitude > 1e-3) and CFrame.lookAt(pos, rootPart.Position) or CFrame.new(pos))
			BirdBuilder.PoseSquirrel(cc.sq, "starfish", dt, 0)
		elseif cc.t >= cc.airtime then
			-- contact IN THE CREW'S ARMS → light poof + pomf + the crew cheers ("CREW CATCH! +1").
			if not cc.contactDone then
				cc.contactDone = true
				burstFeathers(tp, FEATHER_GOLD, 16)
				playPomf()
				crewCheer = 0.9
				if _G.RescueStamp then _G.RescueStamp("crew") end
				-- P5 COURAGE IS VISIBLE (Packet-03): everyone already aboard helped haul this one in —
				-- each grows a step (eased in updateRiders) with a proud little re-settle hop. Capped so
				-- the carry-10 seat grid never overlaps. The NEW rider starts at stage 0 (it just got here).
				for _, r in ipairs(riders) do
					if (r.stage or 0) < (RES.courageStages or 3) then
						r.stage = (r.stage or 0) + 1
						r.growFrom = (r.model and r.model:GetScale()) or 1
						r.growTo = 1 + r.stage * (RES.courageStep or 0.08)
						r.growT = 0
						r.settle = math.max(r.settle or 0, RIDER_HOP_DUR * 0.5)
					end
				end
				riders[#riders + 1] = {
					model = cc.sq, phase = math.random() * math.pi * 2,
					look = math.random() * math.pi * 2, t = 0, settle = RIDER_HOP_DUR,
				}
				cc.sq = nil
			end
			table.remove(crewCatches, i)
		end
	end
end

-- Destroy every in-flight crew-catch presentation squirrel + clear the list (teardown / reconcile).
local function clearCrewCatches()
	for _, cc in ipairs(crewCatches) do
		if cc.sq then pcall(function() cc.sq:Destroy() end) end
	end
	crewCatches = {}
end

-- Keep the back-riders glued to the eagle's back and ALIVE (Fable §C): each breathes with the
-- wingbeat, looks around on its own clock, hops-and-settles as it lands, and flings its arms in a
-- dive. Cosmetic only — modulates the seat CFrame + ride pose; no control/camera/kernel effect.
local function updateRiders(dt)
	local fp = (flightEngine and flightEngine.flapPhase) or 0
	local diving = flightEngine and flightEngine.isDiving
	-- CREW CATCH v2 crowd-work: while a leaper is inbound, the riders nearest its seat (the tail-most —
	-- seats fill spine→tail, so the newcomers land by the newest riders) lean out ARMS-WIDE to net it;
	-- when it lands, the whole crew cheers for a beat.
	local reaching = #crewCatches > 0
	crewCheer = math.max(0, crewCheer - dt)
	for i, rider in ipairs(riders) do
		local m = rider.model
		if m and m.PrimaryPart then
			rider.t = (rider.t or 0) + dt
			-- breathing bob + lean, staggered per rider off the eagle's wingbeat.
			local br  = math.sin(fp + (rider.phase or 0))
			local bob = br * RIDER_BOB_AMP
			-- slow independent look-around.
			local look = math.sin(rider.t * 0.7 + (rider.look or 0)) * RIDER_LOOK
			-- hop-and-settle on first landing (a single up-and-back-down arc).
			local hop = 0
			if (rider.settle or 0) > 0 then
				local p = 1 - (rider.settle / RIDER_HOP_DUR)      -- 0 → 1 across the hop
				hop = math.sin(p * math.pi) * RIDER_HOP_AMP
				rider.settle = math.max(0, rider.settle - dt)
			end
			-- courage growth (P5): ease the model scale toward its stage over RIDER_GROW_DUR.
			local grown = rider.growTo or 1
			if rider.growT then
				rider.growT += dt
				local g = clamp(rider.growT / RIDER_GROW_DUR, 0, 1)
				local e = g * g * (3 - 2 * g)
				grown = (rider.growFrom or 1) + ((rider.growTo or 1) - (rider.growFrom or 1)) * e
				m:ScaleTo(grown)
				if g >= 1 then rider.growT = nil end
			end
			-- lift a grown rider by its extra half-height so it sits ON the back, not sunk into it.
			local lift = (grown - 1) * ((m:GetAttribute("SquirrelScale") or 2.4) * 0.575)
			local seat = seatCFrame(i)
				* CFrame.new(0, bob + hop + lift, 0)
				* CFrame.Angles(br * RIDER_LEAN, look, br * RIDER_LEAN * 0.5)
			m:PivotTo(seat)
			local pose = diving and "ridedive" or "ride"
			if reaching and i > #riders - 3 then
				pose = "reach"
			elseif crewCheer > 0 then
				pose = "waveBig"                       -- the whole crew cheers the catch
			end
			BirdBuilder.PoseSquirrel(m, pose, dt, fp + (rider.phase or 0))
		end
	end
end

local function releaseRiders()
	for _, rider in ipairs(riders) do
		local m = rider.model
		if m and m.PrimaryPart then
			burstFeathers(m.PrimaryPart.Position, FEATHER_GOLD, 14)
			m:Destroy()
		end
	end
	riders = {}
end

-- Trim the newest riders until the local count matches an authoritative target (self-heals a phantom
-- rider left by a server-rejected catch). Only ever called when NOT mid-catch.
local function trimRidersTo(target)
	while #riders > target do
		local rider = table.remove(riders)
		if rider and rider.model then rider.model:Destroy() end
	end
end

-- HARD reset of ALL rescue presentation — called on death/respawn/crow-swap (teardownDrive), so a catch
-- beat interrupted mid-flight can never strand the global slow-mo desaturation, the camera offset, or
-- orphan presentation models. (red-team BLOCK 1.) Safe to call anytime.
local function resetRescuePresentation()
	if catch and catch.sq then pcall(function() catch.sq:Destroy() end) end
	catch = nil
	hopOff = nil
	clearCrewCatches()
	releaseRiders()
	rescueCam.env = 0
	slowmoDesat(0)
	if catchFxFolder then
		for _, c in ipairs(catchFxFolder:GetChildren()) do c:Destroy() end
	end
end

-- WAYFINDING (Fable §D): while carrying ≥1, a faint gold streamer points from the eagle toward the
-- waterfall safe zone — a diegetic compass, ZERO UI. Client-only; two attachments on one anchored
-- CatchFx part so it's independent of the eagle Body's lifecycle (survives possession/respawn/teardown).
local wayfind   -- { part, a0, a1, beam } or nil
local function ensureWayfinder()
	if wayfind and wayfind.part.Parent then return wayfind end
	local part = Instance.new("Part")
	part.Name = "RescueWayfinder"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = ensureCatchFx()
	local a0 = Instance.new("Attachment"); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(FEATHER_GOLD)
	beam.LightEmission = 0.9
	beam.FaceCamera = true
	beam.Width0 = 3.0
	beam.Width1 = 0.4
	beam.Segments = 12
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),   -- faint at the eagle…
		NumberSequenceKeypoint.new(1, 1),      -- …fades out at the tip (a pointer, not a full line)
	})
	beam.Enabled = false
	beam.Parent = part
	wayfind = { part = part, a0 = a0, a1 = a1, beam = beam }
	return wayfind
end

local function updateWayfinder()
	local carrying = (#riders > 0) and (rescueState.phase == "active")
	if not carrying then
		if wayfind and wayfind.part.Parent then wayfind.beam.Enabled = false end
		return
	end
	local wf = ensureWayfinder()
	local eaglePos = rootPart.Position
	local toWF = (RES.deliverPos or Vector3.new(0, 250, 0)) - eaglePos
	local horiz = Vector3.new(toWF.X, 0, toWF.Z)
	local dist = horiz.Magnitude
	local dir = (dist > 1e-3) and horiz.Unit or rootPart.CFrame.LookVector
	local length = math.clamp(dist * 0.5, 40, 130)
	wf.a0.WorldPosition = eaglePos + Vector3.new(0, -1.5, 0)
	wf.a1.WorldPosition = eaglePos + dir * length + Vector3.new(0, 12, 0)   -- lift the tip → arcs up toward the mesa
	wf.beam.Enabled = true
end

-- Detect the TELL (predicted) + the TRIGGER (sphere entry) against stranded world squirrels.
local function scanSquirrels(dt)
	if not squirrelsFolder then return end
	squirrelPhase += dt * 3
	local eaglePos = rootPart.Position
	local vel = flightEngine.velocity
	-- FTUE eases the closing gate (Fable §D) so a slow/wobbly beginner still catches.
	local isFtue = catchCount < (RES.ftueCatches or 3)
	local gateFrac = isFtue and (RES.ftueGateFrac or RES.closingGateFrac or 0.3) or (RES.closingGateFrac or 0.3)
	local gate = gateFrac * eagleGlide()
	-- CREW CATCH v1: catches now OVERLAP — a trigger while the sacred `catch` is busy becomes a CREW catch
	-- (the single-slot lock that silently dropped chained catches is gone). haveRoom counts the sacred catch
	-- + every in-flight crew catch + the riders, so we never exceed carry capacity.
	local inFlight = (catch and 1 or 0) + #crewCatches
	local haveRoom = (#riders + inFlight) < (rescueState.capacity or RES.carryCapacity or 3)
	-- No new catches during the hop-off ceremony (riders are mid-dismount; the tally is counting).
	local canCatch = haveRoom and rescueState.phase == "active" and not hopOff
	-- Tells only when a catch could actually follow — a FULL eagle must not wind up squirrels it can't
	-- take (anticipation with no payoff reads as "my catch didn't count"; Chad S35).
	local roomForTell = haveRoom and not hopOff and rescueState.phase == "active"

	local effRadius = (RES.triggerRadius or 28)
	if isFtue then effRadius = effRadius * (RES.ftueRadiusMult or 1.5) end
	-- TRADE SECRET (Chad S34): flying FASTER widens the catch scoop a little — rewards boom-and-zoom
	-- without telling the player. 1× at glide → up to 1+scoopSpeedGain at ~2× glide. No UI, no announce.
	local glideSp = eagleGlide()
	effRadius = effRadius * (1 + clamp((flightEngine.speed - glideSp) / math.max(1, glideSp), 0, 1) * (RES.scoopSpeedGain or 0.25))

	local bestTellId, bestTellTime = nil, math.huge
	tellTimer = math.max(0, tellTimer - dt)
	softFailTimer = math.max(0, softFailTimer - dt)

	for _, m in ipairs(squirrelsFolder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("State") == "stranded" and m.PrimaryPart
			and not isClaimed(m:GetAttribute("SquirrelId")) then
			local toVec = m.PrimaryPart.Position - eaglePos
			local dist = toVec.Magnitude
			if dist < 260 then
				local dir = (dist > 1e-3) and toVec.Unit or rootPart.CFrame.LookVector
				local closing = vel:Dot(dir)
				if canCatch and dist <= effRadius and closing >= gate then
					if catch then triggerCrewCatch(m, closing) else triggerCatch(m, closing) end
					canCatch = false
					-- this trigger may have taken the LAST seat — recompute room so a second squirrel
					-- scanned this same frame can't plant a no-payoff tell (red-team F4).
					haveRoom = (#riders + (catch and 1 or 0) + #crewCatches) < (rescueState.capacity or RES.carryCapacity or 3)
					roomForTell = roomForTell and haveRoom
				elseif canCatch and dist <= effRadius and closing < gate then
					-- SOFT-FAIL (Fable §D): you flew right through the sphere but weren't closing fast
					-- enough — the squirrel waves "come back!" so the miss has a face, never silence.
					softFailId = m:GetAttribute("SquirrelId")
					softFailTimer = 1.3
				elseif (not haveRoom or hopOff) and rescueState.phase == "active"
					and dist <= effRadius and closing >= gate then
					-- FULL (or mid-hop-off): a REAL catch line (closing ≥ gate) flown with no room
					-- aboard. This was total silence — Chad S35: "around 7 to 10 a lot of the catches
					-- dont get counted". The squirrel waves "come back!" always; the HUD hint fires only
					-- when no catch beat is live (red-team F2: never stomp a GOTCHA), debounced, and
					-- reports riders+in-flight (red-team F1: the number that actually made it full).
					softFailId = m:GetAttribute("SquirrelId")
					softFailTimer = 1.3
					if not hopOff and not catch and #crewCatches == 0
						and os.clock() - lastFullHint > (RES.fullHintCooldown or 6) then
						lastFullHint = os.clock()
						if _G.RescueStamp then _G.RescueStamp("full", nil, nil, nil, #riders + inFlight) end
					end
					-- DIAG (S36): a REAL catch line was suppressed as full — is the client "full" at a count
					-- the SERVER doesn't share? (phantom-inflated #riders). Compare to the server carry.
					if RES.catchDiag then
						warn(string.format("[RescueDIAG-C] FULL-suppress: riders=%d inFlight=%d serverCarry=%s cap=%d",
							#riders, inFlight, tostring(rescueState.carry), rescueState.capacity or RES.carryCapacity or 3))
					end
				elseif roomForTell and closing >= gate then
					local toSurface = math.max(0, dist - effRadius)
					local tte = toSurface / math.max(closing, 1e-3)
					if tte <= (RES.tellLeadTime or 0.4) and tte < bestTellTime then
						bestTellTime = tte
						bestTellId = m:GetAttribute("SquirrelId")
					end
				end
			end
		end
	end
	if softFailTimer <= 0 then softFailId = nil end

	if bestTellId then
		tellId = bestTellId
		tellTimer = RES.tellHoldMin or 1.2
	elseif tellTimer <= 0 then
		tellId = nil
	end

	-- Animate every stranded squirrel: wave, or the planted tell. The active tell also FLARES its
	-- beacon (Fable #4) — the plant pose is tiny at ~78 studs, so the beacon is the signal that
	-- actually reads from the cockpit; brighten + swell it so the anticipation beat is seen.
	local flarePulse = 0.5 + 0.5 * math.sin(squirrelPhase * 2.2)   -- 0..1
	for _, m in ipairs(squirrelsFolder:GetChildren()) do
		if m:IsA("Model") and m.PrimaryPart then
			local st = m:GetAttribute("State")
			local sid = m:GetAttribute("SquirrelId")
			local isTell = (st == "stranded") and (sid == tellId)
			local isSoftFail = (st == "stranded") and (softFailTimer > 0) and (sid == softFailId)
			local pose = "wave"
			local phase = squirrelPhase
			if st == "expiring" then pose = "ride"
			elseif isTell then pose = "plant"
			elseif isSoftFail then pose = "waveBig"; phase = squirrelPhase * 2.4 end   -- fast excited wave
			BirdBuilder.PoseSquirrel(m, pose, dt, phase)
			-- Local cosmetic flare (client-only property writes; the server never re-touches these).
			local beacon = m:FindFirstChild("Beacon")
			if beacon then
				if isTell then
					beacon.Transparency = 0.05 + 0.15 * (1 - flarePulse)
					local w = 2.2 * (1.7 + 0.5 * flarePulse)
					beacon.Size = Vector3.new(w, 54, w)
				else
					beacon.Transparency = 0.55
					beacon.Size = Vector3.new(2.2, 44, 2.2)
				end
			end
		end
	end
end

-- Line-riding STYLE meter (Fable §C) — reuses computeProximity (terrain closeness). Charges when
-- flying fast + close; decays with a half-life so the line must be flown INTO the catch.
local function updateStyle(dt)
	local pd = RES.styleProxDist or 40
	local minDist = computeProximity(rootPart.Position, pd)
	local speed = flightEngine.speed
	if minDist < pd and speed >= (GameConfig.Rescue.minStyleSpeed or 60) then
		local closeness = clamp((pd - minDist) / math.max(1, pd - (RES.styleSweetSpot or 7)), 0, 1)
		styleMeter = math.min((RES.styleMultMax or 3) - 1, styleMeter + closeness * (RES.styleChargeRate or 0.9) * dt)
	else
		styleMeter = styleMeter * (0.5 ^ (dt / (RES.styleDecayHalf or 2.0)))
	end
end

-- Deliver a cargo when riding into the safe zone above the waterfall.
-- MATH DELIVERY hop-off ceremony (Packet-03 §3 layer 1): after a deliver, the riders dismount ONE PER
-- BEAT — each hop rings a rising note and ticks the tally by n (one ROW of the n×n acorn array), so the
-- child skip-counts (7…14…21…) straight into the multiplication sentence "7 × 7 = 49!". Presentation
-- only — the server already paid the authoritative n² when the deliver remote fired.
local function stepHopOff(dt)
	if not hopOff then return end
	hopOff.t += dt
	local beat = RES.hopBeat or 0.35
	if hopOff.t < beat then return end
	hopOff.t -= beat
	hopOff.i += 1
	local rider = table.remove(riders)               -- top of the pile leaves first
	if rider and rider.model and rider.model.PrimaryPart then
		local m = rider.model
		local side = (hopOff.i % 2 == 0) and 1 or -1   -- alternate dismount sides
		burstFeathers(m.PrimaryPart.Position, FEATHER_GOLD, 8)
		task.spawn(function()                          -- a little starfish dismount arc, then gone
			local pivot0 = m:GetPivot()
			local t = 0
			while t < 0.5 do
				local d = task.wait()
				t += d
				if not (m.Parent and m.PrimaryPart) then return end
				local u = clamp(t / 0.5, 0, 1)
				m:PivotTo(pivot0 * CFrame.new(side * u * 9, math.sin(u * math.pi) * 5 - u * 11, 0))
				BirdBuilder.PoseSquirrel(m, "starfish", d, 0)
			end
			m:Destroy()
		end)
	end
	playCount(hopOff.i)
	if _G.RescueStamp then _G.RescueStamp("tally", nil, nil, nil, hopOff.i * hopOff.n) end
	if hopOff.i >= hopOff.n then
		local n = hopOff.n
		hopOff = nil
		if _G.RescueStamp then _G.RescueStamp("sentence", nil, nil, nil, n) end
	end
end

local function updateDeliver(dt)
	deliverCooldown = math.max(0, deliverCooldown - dt)
	-- Don't deliver mid-catch (sacred OR crew — a crew catch still in flight would add a phantom rider
	-- to a cleared back), mid-hop-off (the ceremony is already paying this batch out), or outside an
	-- active round (a buzzer-beater the server would reject must not run a zero-payout ceremony —
	-- red-team R1; the riders just stay aboard into results).
	if #riders <= 0 or deliverCooldown > 0 or catch or #crewCatches > 0 or hopOff
		or rescueState.phase ~= "active" then return end
	local d = RES.deliverPos
	local flat = Vector3.new(rootPart.Position.X - d.X, 0, rootPart.Position.Z - d.Z).Magnitude
	if flat < (RES.deliverRadius or 70) and rootPart.Position.Y > (RES.deliverPadY or 250) - 50 then
		if deliverRemote then deliverRemote:FireServer() end
		hopOff = { n = #riders, i = 0, t = 0 }         -- riders now dismount one per beat (stepHopOff)
		deliverCooldown = #riders * (RES.hopBeat or 0.35) + 1.5
		playChord()
	end
end

--------------------------------------------------------------------------------
-- MUSIC ESCALATION (#14, Packet-03 §6) — ONE number, deliveredThisRound + carry, drives a layered
-- gray-box swell toward the Perfect Ten: base wind → +pizzicato@1 → +rhythm@4 → +brass@7 → @8-9 strip
-- to a heartbeat pulse; tempo tightens as the round builds. The crew is the choir (rider chatter scales
-- with crew size). AUDIO ONLY — reads rescue state, writes only Sound instances; touches NO control /
-- camera / kernel code (CS-1..9 untouched by construction). The looped WIND BED is a PERSISTENT Sound
-- (NOT routed through playSound, which self-destructs at 4s and would kill a loop); every other layer is
-- a beat-clocked ONE-SHOT (playSound's 4s cleanup is correct for those). The SWELL FEEL is Chad's FUN gate.
--------------------------------------------------------------------------------
local musicBed               -- persistent looped wind Sound (created lazily on first active frame)
local musicBeatTimer = 0     -- counts down to the next music beat
local musicBeatFlip  = false -- alternates each beat so rhythm can play OFFbeats vs pizzicato/brass ON-beats
local chirpTimer     = 0     -- counts down to the next crew-choir rider chirp

local function fadeMusic()
	if musicBed then musicBed.Volume = 0 end
end

local function updateMusic(dt)
	if not (RES and RES.musicEnabled ~= false) then return end
	local active = rescueState.phase == "active"
	-- WIND BED — a persistent LOOPED Sound; volume eased toward the floor while active, to 0 otherwise.
	if not musicBed then
		musicBed = Instance.new("Sound")
		musicBed.Name = "RescueWindBed"
		musicBed.SoundId = SFX_SWOOSH          -- action_falling.ogg pitched down into a rumble-wind bed
		musicBed.Looped = true
		musicBed.Volume = 0
		musicBed.PlaybackSpeed = 0.5
		musicBed.Parent = SoundService
		musicBed:Play()
	end
	local targetWind = active and (RES.musicWindVol or 0.10) or 0
	musicBed.Volume = musicBed.Volume + (targetWind - musicBed.Volume) * math.min(1, dt * 3)
	if not active then
		musicBeatTimer, chirpTimer = 0, 0
		return
	end

	-- THE DRAMA NUMBER — progress toward the Perfect Ten (delivered this round + what you're carrying).
	local prog = (rescueState.delivered or 0) + #riders
	local frac = clamp(prog / (RES.perfectTenAt or 10), 0, 1)

	-- BEAT CLOCK — tempo tightens from calm to driving as the round builds.
	local beatLen = (RES.musicBeatSlow or 0.75)
		+ ((RES.musicBeatFast or 0.34) - (RES.musicBeatSlow or 0.75)) * frac
	musicBeatTimer -= dt
	if musicBeatTimer <= 0 then
		musicBeatTimer += beatLen
		musicBeatFlip = not musicBeatFlip
		local vol = RES.musicLayerVol or 0.16
		if prog >= (RES.musicHeartAt or 8) then
			-- @8-9: STRIP the melody — a low double-thump heartbeat drives the tension toward ten.
			playSound(SFX_SNAP, vol * 1.1, 0.4)
			-- gate the off-beat thump so a round-end/death mid-beat can't leak one stray thump (audit NOTE).
			task.delay(beatLen * 0.5, function()
				if rescueState.phase == "active" then playSound(SFX_SNAP, vol * 0.8, 0.4) end
			end)
		else
			if prog >= (RES.musicPizzAt or 1) and not musicBeatFlip then
				playSound(SFX_PING, vol, 1.5)              -- PIZZICATO — soft ping on the downbeat
			end
			if prog >= (RES.musicRhythmAt or 4) and musicBeatFlip then
				playSound(SFX_PING, vol * 0.9, 2.0)        -- RHYTHM — an offbeat ping fills the groove
			end
			if prog >= (RES.musicBrassAt or 7) and not musicBeatFlip then
				playSound(SFX_SNAP, vol, 0.7)              -- BRASS — a low swell note on the downbeat
			end
		end
	end

	-- CREW CHOIR — rider chatter; a fuller back = busier chirping ("the crew is the choir").
	if #riders > 0 then
		chirpTimer -= dt
		if chirpTimer <= 0 then
			chirpTimer = math.max(RES.chirpMinGap or 0.5,
				(RES.chirpBase or 2.4) - (RES.chirpPerRider or 0.14) * (#riders - 1))
			local wobble = 1.6 + 0.5 * math.sin(prog * 1.3 + #riders)  -- pitch wanders so it's not a metronome
			playSound(SFX_PING, RES.chirpVol or 0.14, wobble)
		end
	else
		chirpTimer = 0
	end
end

-- MASTER rescue update, called once per flight frame from onFlightStep.
local function updateRescue(dt)
	if not (RES and RES.enabled) then return end
	if not (rootPart and rootPart.Parent and isAlive and flightEngine) then
		-- flying nothing (dead / between lives): tear the beat down cleanly.
		if catch and catch.sq then catch.sq:Destroy() end
		catch = nil
		hopOff = nil
		clearCrewCatches()
		if #riders > 0 then releaseRiders() end
		rescueCam.env = 0
		slowmoDesat(0)
		fadeMusic()
		return
	end
	updateStyle(dt)
	scanSquirrels(dt)
	if catch then stepCatch(dt) end
	stepCrewCatches(dt)
	updateRiders(dt)
	updateMusic(dt)
	stepHopOff(dt)
	updateDeliver(dt)
	updateWayfinder()
	-- Reconcile local riders to the server's authoritative carry when idle (heals a rejected-catch phantom).
	-- Only when NOTHING is in flight (sacred or crew) AND no hop-off ceremony is paying out — the server's
	-- carry is already 0 during hop-off, so reconciling then would insta-dump the whole dismount queue.
	if not catch and #crewCatches == 0 and not hopOff and type(rescueState.carry) == "number" and #riders > rescueState.carry then
		-- DIAG (S36): a phantom is being trimmed — the client showed more riders than the server counted.
		-- This is the "carry went 9->8 after a catch" event; the count above tells us how many were lost.
		if RES.catchDiag then
			warn(string.format("[RescueDIAG-C] TRIM riders %d -> serverCarry %d (%d phantom)",
				#riders, rescueState.carry, #riders - rescueState.carry))
		end
		trimRidersTo(rescueState.carry)
	end

	local env = catchEnv()
	-- Deeper beat for a bigger catch (Fable #5): scale the (env-gated, identity-at-0) desat + rescue
	-- camera envelope up a little. FOV is clamped and saturation stays legal at this reach, so a big
	-- catch just reads slower/richer. The envelope still returns to identity as the beat ends.
	local beatMul = 1 + (catch and catch.big or 0) * 0.4
	local envBig = env * beatMul
	rescueCam.env = envBig
	slowmoDesat(envBig)
	-- dilate the leaping squirrel's mote trail so the FX read slow while the sim runs on — deeper for a
	-- big catch (effective slow-mo scale drops toward 0.6× of the base).
	if catch and catch.sq and catch.sq.PrimaryPart then
		local effScale = (RES.slowmoScale or 0.25) * (1 - (catch.big or 0) * 0.4)
		local mote = catch.sq.PrimaryPart:FindFirstChildOfClass("Attachment")
		mote = mote and mote:FindFirstChildOfClass("ParticleEmitter")
		if mote then mote.TimeScale = lerpN(1, effScale, env) end
	end
end

-- Expose the current HUD-facing rescue snapshot for GameUI/the rescue HUD.
_G.RescueSnapshot = function()
	return {
		phase = rescueState.phase, timeLeft = rescueState.timeLeft,
		score = rescueState.score, delivered = rescueState.delivered, rescued = rescueState.rescued,
		carry = #riders, capacity = rescueState.capacity or (RES and RES.carryCapacity) or 3,
		style = styleMeter, combo = rescueState.combo or 0,
		timeFactor = rescueState.timeFactor, preFactorScore = rescueState.preFactorScore,
	}
end

--------------------------------------------------------------------------------
-- INPUT HELPERS — keyboard tap->ramp smoothing + the mouse-aim autopilot.
--------------------------------------------------------------------------------
-- Ease an axis from a tap fraction up to full deflection while a key is held (mirrors the pitch
-- ramp). `state` = {sign, mag}; `target` = -1/0/+1. A tap gives `tapFrac`; holding ramps to 1 over
-- `rampTime`; releasing snaps to 0 (the nose/bank then holds — there is no auto-level).
local function rampAxis(state, target, tapFrac, rampTime, dt)
	if target ~= 0 then
		if state.sign ~= target then
			state.sign = target
			state.mag = tapFrac
		else
			state.mag = math.min(1, state.mag + ((1 - tapFrac) / math.max(0.01, rampTime)) * dt)
		end
	else
		state.sign, state.mag = 0, 0
	end
	return state.sign * state.mag
end

-- MOUSE-AIM (War Thunder instructor model) — COORDINATED-FLIGHT autopilot. Two markers: the CURSOR
-- (your desired direction of flight) and the NOSE CROSS (boresight, projected out front). We resolve the
-- cursor's world direction into the bird's BODY frame and fly a REAL coordinated turn toward it: the
-- ELEVATOR pulls the nose toward the target (uncapped -> a held edge cursor loops), the BANK rolls the
-- lift vector onto the target so the side error nulls AS IT BANKS (this is what kills the perpetual-bank
-- corkscrew), and a little RUDDER coordinates. The nose-up pull eases off near stall so the bird climbs to
-- the stall edge and HOLDS there instead of yanking past it into a stalling dive. Returns 0,0,0 while
-- free-look (Space) suspends it. Writes aimCursor.* (marker screen positions) for the reticle render.
local function computeMouseAim(dt)
	local C = GameConfig.Controls
	if not (C and C.mouseAim) or freeLook.active then
		return 0, 0, 0
	end
	if not (rootPart and rootPart.Parent and camera and flightEngine) then return 0, 0, 0 end
	local vp = camera.ViewportSize
	if not vp or vp.Y < 2 then return 0, 0, 0 end

	-- NOSE-CHASES-CURSOR aim (2026-06-30). The CURSOR is a WORLD direction (aimTargetDir): the mouse swings it away
	-- from the nose, out to a big CONE (the reachable circle), and it STAYS where you put it. The bird's NOSE — the
	-- amber reticle, projected far out front — is the dependent thing: it CHASES the cursor and, when it catches up
	-- (at the bird's own turn/pitch/yaw rate — FlightPhysics rate-limits it), the beak points right at the cursor.
	-- Because the cursor is fixed in the WORLD (not the screen), the nose can actually CATCH it and the command
	-- falls to zero (a screen-anchored cursor can't — the chase cam re-centres the nose so it never catches).
	-- Command is body-relative to the NOSE, so cursor-on-nose = straight and the reticle lands exactly on the cursor.
	local cf = rootPart.CFrame
	local birdLook = cf.LookVector
	local inset = GuiService:GetGuiInset()

	-- Swing the cursor by the mouse delta (about the camera's screen axes), then clamp it to a big cone around the
	-- nose = the reachable circle. Holding the mouse out pins it at the cone edge (a sustained lead -> turn/loop).
	local camCF = camera.CFrame
	local delta = UserInputService:GetMouseDelta()
	local sens  = (C.aimMouseSensitivity or 1.0) * (C.aimAnglePerPixel or 0.006)
	local dYaw   = -delta.X * sens
	local dPitch = ((C.invertPitch and delta.Y) or -delta.Y) * sens
	aimTargetDir = aimTargetDir or birdLook
	local rotated = CFrame.fromAxisAngle(camCF.UpVector, dYaw) * CFrame.fromAxisAngle(camCF.RightVector, dPitch)
	local tdir = rotated:VectorToWorldSpace(aimTargetDir)
	aimTargetDir = (tdir.Magnitude > EPS) and tdir.Unit or birdLook
	local halfFovTan = math.tan(math.rad((camera.FieldOfView or 70) * 0.5))
	local maxLead = math.min(math.rad(C.aimMaxLeadDeg or 70), math.atan(halfFovTan * (C.aimLeadScreenFrac or 0.95)))
	if not C.aimFreeCursor and clamp(birdLook:Dot(aimTargetDir), -1, 1) < math.cos(maxLead) then
		local axis = birdLook:Cross(aimTargetDir)
		if axis.Magnitude > 1e-5 then
			aimTargetDir = CFrame.fromAxisAngle(axis.Unit, maxLead):VectorToWorldSpace(birdLook)
		end
	end
	-- SCREEN-CENTRED cursor circle (RESTORED S26 — this clamp was silently LOST in the 2026-06-30
	-- nose-chases-cursor rewrite, leaving aimCursorAreaFrac unread; Chad: "the cursor now goes all the
	-- way to the edges and corners; my cursor circle should be centered and take up only about 5/8 of
	-- the screen"). The nose-cone clamp above bounds the cursor's LEAD relative to the NOSE — but the
	-- aim camera LAGS the heading, so mid-turn the nose (and its whole cone) sits off-centre and the
	-- cursor could still reach the screen edges/corners. This second clamp bounds the cursor relative
	-- to the CAMERA: its projected position may never leave a circle CENTRED on the screen covering
	-- aimCursorAreaFrac of the screen area. World-anchored model preserved (CS-8): the cursor is still
	-- a world direction and the nose still catches it — this only limits how far off-centre it can be
	-- PUSHED. ⚠️ S28e: this circle is now the cursor's WORKING bound (the nose cone was widened to a pure
	-- safety — see aimLeadScreenFrac). Holding the mouse against this rim = the sustained-turn command:
	-- rimBinding below feeds the turn-rate lead's WASHOUT, so a rim-pinned turn runs at the full S26
	-- plant-capped rate (the lead only shapes ARRIVALS, when the cursor sits world-fixed INSIDE the circle).
	-- S28c GATE: stand the clamp down while the free-look EXIT fast-return is still in flight. On Space-exit
	-- the cursor is correctly re-seeded onto the nose, but for the first frames the camera still sits
	-- SIDEWAYS from the orbit — projecting the fresh cursor through that STALE camera put the nose far off
	-- the stale screen centre, and this clamp YANKED the cursor toward it = Chad's "aim jumps a few degrees
	-- left for no reason". cameraState.snapToChase is TRUE exactly for that window (set on free-look release,
	-- consumed by updateCamera only once the view has re-reached the chase heading, dot > 0.9995) — so this
	-- suspends the clamp for precisely the stale frames at ANY frame rate and NOTHING else: every normal
	-- mouse-aim state (incl. a possessed crow's max-rate turns, where camera↔nose legitimately diverge ~50°+)
	-- keeps the Chad-confirmed S26 circle exactly as before. (Red-team killed the first attempt — a
	-- camera↔nose dot>0.5 gate — as frame-rate-dependent AND clamp-disabling for fast crows; don't re-try it.)
	local rimBinding = false -- true while the player pins the cursor against the circle (= sustained-turn command)
	local areaFrac = C.aimCursorAreaFrac
	if areaFrac and areaFrac > 0 and not cameraState.snapToChase and not C.aimFreeCursor then
		local camLocal = camCF:VectorToObjectSpace(aimTargetDir)
		if camLocal.Z < -EPS then -- only meaningful in front of the camera (Roblox camera looks down -Z)
			local tx, ty = camLocal.X / -camLocal.Z, camLocal.Y / -camLocal.Z
			local pxScale = (vp.Y * 0.5) / halfFovTan            -- projection px per tan-unit (both axes)
			-- Radius from the AREA fraction, HARD-CAPPED to fit fully inside the screen (S26c, Chad: the
			-- circle "still hits the upper flat limit of my screen — when it does it's hard to control the
			-- direction of the turn"). An area-fraction circle can be taller than the screen (5/8 area on
			-- 16:9 ⇒ radius ≈ 1.19× half-height), so the rim went FLAT at the top/bottom edge = ambiguous
			-- turn direction at the rim. The cap keeps the rim round on every screen; margin covers the
			-- 48px cursor ring + the small bird-vs-camera projection parallax at the rim.
			local edgeMargin = C.aimCursorEdgeMarginPx or 48
			local rPx = math.min(
				math.sqrt(areaFrac * vp.X * vp.Y / math.pi),
				vp.Y * 0.5 - edgeMargin,
				vp.X * 0.5 - edgeMargin)
			if rPx < 50 then rPx = 50 end -- degenerate tiny-viewport floor
			local px = math.sqrt(tx * tx + ty * ty) * pxScale
			if px > rPx then
				local s = rPx / px
				local nd = camCF:VectorToWorldSpace(Vector3.new(tx * s, ty * s, -1))
				aimTargetDir = (nd.Magnitude > EPS) and nd.Unit or aimTargetDir
				rimBinding = true
			end
		end
	end
	local localTarget = cf:VectorToObjectSpace(aimTargetDir)

	-- Body-frame target (x = right, y = up; forward = -z). HORIZONTAL drives bank+yaw, VERTICAL drives pitch.
	local rgt = localTarget.X
	local upc = localTarget.Y

	-- S28e TURN-RATE LEAD — the horizontal channel's missing plant-rate feedback (full rationale at the
	-- BANK+RUDDER block below). Predict the horizontal error ONE aimLeadTime ahead using the eagle's ACTUAL
	-- heading rate from clean kernel body rates (+ = turning RIGHT: the banked pull pitchVel·sinB turns the
	-- nose toward the low wing; +yawVel = nose LEFT hence the minus). NOTHING differentiates the mouse —
	-- the S27c jitter trap stays dead. Upright-faded like the bank FF (inverted ⇒ pure S26 law); near-
	-- vertical attitudes self-annihilate it (wings level in a loop ⇒ sinB≈0 and the pull is vertical).
	-- Three corrections from the S28e red-team (all three were BLOCK-level — do not remove):
	--   1) ERROR-SPACE: d(rgt)/dt = −ψ̇·cosB·cosΔψ, so the lead is scaled by cosB·cosΔψ — without it the
	--      lead over-anticipates ~2× at combat banks and commands a full roll-OUT with the cursor still
	--      ~20° away (a mid-turn unload/re-roll bounce).
	--   2) RIM WASHOUT: while the cursor is PINNED against the screen circle (rimBinding — the player is
	--      COMMANDING a sustained turn) the lead fades to zero, so rim-pinned turns run at the full S26
	--      plant-capped rate (eagle ~1.8, crow ~3+ rad/s — the crow's turn identity preserved). A constant
	--      lead would silently cap sustained turns at ~half rate. When the throw ends, the camera catches
	--      up, the cursor drops INSIDE the circle (world-fixed), and the full lead shapes the arrival —
	--      which is exactly the sail-past case.
	--   3) KEYBOARD MUTE: while any flight key is held (the CS-1 gate set, mirrored here) the lead fades
	--      to zero — otherwise it pre-charges aimApplied with a saturated COUNTER-turn during a keyboard
	--      turn that SLAMS on key release (the S26d-certified combo seam). Fades back in over ~150 ms.
	local sinB = clamp(-cf.RightVector.Y, -1, 1)
	local cosB = math.sqrt(math.max(1 - sinB * sinB, 0))
	local headRate = ((flightEngine.pitchVel or 0) * sinB - (flightEngine.yawVel or 0) * cosB)
		* clamp(cf.UpVector.Y / 0.15, 0, 1)
	local sinDpsi = clamp(rgt / math.max(cosB, 0.2), -1, 1)
	local cosDpsi = math.sqrt(math.max(1 - sinDpsi * sinDpsi, 0))
	local keysHeld = (kb.pitch ~= 0 or kb.roll ~= 0 or kb.yaw ~= 0) -- mirrors the CS-1 aimGate exactly
	local leadTarget = (rimBinding or keysHeld) and 0 or 1
	aimLeadScale = aimLeadScale + (leadTarget - aimLeadScale) * math.clamp((C.aimLeadWashRate or 6) * dt, 0, 1)
	local hPred = clamp(rgt - headRate * (C.aimLeadTime or 0.28) * cosB * cosDpsi * aimLeadScale, -1, 1)

	-- SYMMETRIC shaping (deadzone + EXPO) on BOTH axes — WT "nonlinearity" (RESEARCH §v4). Gentle near
	-- centre for fine aim, ramping to FULL authority at the edge, so PITCH keeps full pull for a clean
	-- vertical loop AND a slight sideways cursor no longer snaps into a hard bank. Consistent feel both axes.
	local hCmd = shapeAxis(hPred, C.aimBankDeadzone or 0.10, C.aimBankExpo or 1.8)
	local vCmd = shapeAxis(upc, C.aimPitchDeadzone or 0.05, C.aimPitchExpo or 1.8)

	-- LOOP COMMIT vs stall protection. Ride the edge: the nose-up pull keeps FULL authority until |AoA|
	-- comes within aimStallBandDeg of stall, then eases — so a started loop finishes instead of mushing
	-- out early. SUSPENDED entirely while powered (flap throttle up), because the beating wings hold lift
	-- past stall then (FlightPhysics FLAP_LIFT_FLOOR) — a powered loop ALWAYS commits.
	local stallAngle = (currentProfile and currentProfile.stallAngleDeg) or 24
	local band = C.aimStallBandDeg or 4
	local powered = (flapThrottle or 0) > 0.05
	local aoaHead = powered and 1
		or math.clamp((stallAngle - math.abs(flightEngine.aoaDeg or 0)) / math.max(1, band), 0, 1)

	-- ELEVATOR (PD): P pulls the nose toward the target; D (aimPitchDamp · current pitch-rate) damps the
	-- climb/pull porpoise. The damp normalises the body rate by the profile pitchRate so it's ~[-1,1].
	-- Full deflection still saturates to 1 (loop authority intact); the damp only bites near equilibrium.
	-- LOW-SPEED TURN STABILITY (S26e, Chad: "at slower speeds the instructor causes oscillations up and
	-- down in the turn"). The instructor was SPEED-BLIND: it commanded the same nose-up pull at 80
	-- studs/s as at 300, but slow wings answer weakly and AoA rides the stall band, so the pitch loop
	-- overshot up, sagged, pulled again — the porpoise. Scale the pitch P-GAIN with airspeed: full gain
	-- at/above the profile glide speed (the loved snap at speed is UNCHANGED), easing to a floor as the
	-- bird slows. The D term is NOT scaled, so relative damping RISES at low speed = a sustainable slow
	-- turn instead of pumping. NOT a lift/kernel change (lift is signed-off; the plant was fine — the
	-- controller was over-driving it). Knobs: aimLowSpeedGainFloor (0.5), aimSpeedGainRef (×glideSpeed).
	local pitchRate = (currentProfile and currentProfile.pitchRate) or 2.0
	local pitchRate01 = clamp((flightEngine.pitchVel or 0) / math.max(0.1, pitchRate), -1, 1)
	local spdNow = flightEngine.speed or 0
	local spdRef = ((currentProfile and currentProfile.glideSpeed) or 95) * (C.aimSpeedGainRef or 1.0)
	local speedScale = clamp(spdNow / math.max(1, spdRef), C.aimLowSpeedGainFloor or 0.5, 1)
	local pitch = vCmd * (C.aimPitchGain or 2.6) * speedScale - (C.aimPitchDamp or 0.35) * pitchRate01
	-- COORDINATED-TURN FEEDFORWARD (S27, RESEARCH-instructor-turn.md). Pay the altitude cost of the CURRENT
	-- bank up front — a nose-up bias ∝ the load-factor excess (sec(bank)-1) the turn needs to hold altitude —
	-- instead of waiting for the sag to become cursor error (the porpoise). Bank is read from RightVector.Y
	-- (roll, independent of pitch attitude); cos is floored so sec caps at 5 (~78°) and can't blow up. This is
	-- ADDED to the PD command, then passes through the SAME aoaHead stall gate below (so it eases off near
	-- stall at low speed, and is bypassed when powered — like the rest of the nose-up pull). It is open-loop
	-- (a function of bank, NOT cursor error) so it adds no closed-loop phase lag; ZERO at wings-level so
	-- straight flight and the loved snap are untouched; and it only exists under mouse-aim (this function) so
	-- CS-1/CS-5/CS-8 hold. Knob + full rationale: GameConfig.Controls.aimBankFeedforward.
	-- Only UPRIGHT (UpVector.Y>0): the sec(bank) coordinated-turn model is derived for upright turns, so gate
	-- (don't attenuate) it off when inverted — same intent as levelAssist's inverted guard below, so it can't
	-- command wrong-signed nose-up at the top of a banked loop. A normal vertical loop keeps the wings level
	-- (sinBank≈0 ⇒ FF≈0) so this doesn't touch loop feel. Sign assumes the shipped invertPitch=false, exactly
	-- like the aoaHead gate on the next line (both act on the pre-invert command where pitch>0 = nose-up).
	local bankFF = C.aimBankFeedforward or 0
	if bankFF > 0 and cf.UpVector.Y > 0 then
		local sinBank = clamp(-cf.RightVector.Y, -1, 1)
		local cosBank = math.sqrt(math.max(1 - sinBank * sinBank, 0.04))
		-- KNIFE-EDGE TAPER (S30): the sec(bank) FF models the load factor of an ALTITUDE-HOLDING turn — valid to
		-- ~combat bank, but past that sec explodes (slope near vertical) and its magnitude saturates the elevator,
		-- so tiny bank wobbles PUMP the nose up/down (Chad: "the lateral knife edge produces up-and-down oscillation
		-- while turning"). Free-cursor made 65-85° banks reachable (the cone capped ~33° before), exposing this tail.
		-- Fade the FF to zero across a 15° shoulder as |bank| nears aimBankFFTaperDeg — keeps the loved S27 anti-dip
		-- in normal-to-hard turns, removes it only in the knife-edge band where it isn't modeling real lift anyway.
		-- 0 = no taper = byte-identical to today.
		local ffFade = 1
		local taperDeg = C.aimBankFFTaperDeg or 0
		if taperDeg > 0 then
			ffFade = clamp((taperDeg - math.deg(math.asin(math.abs(sinBank)))) / 15, 0, 1)
		end
		pitch = pitch + (1 / cosBank - 1) * bankFF * ffFade
	end
	if pitch > 0 then pitch = pitch * aoaHead end  -- ride-the-edge protection on the nose-UP pull (and the FF)
	pitch = clamp(pitch, -1, 1)

	-- BANK + RUDDER — S28e ONE-LAW TURN-RATE-LEAD coordination (Chad: "yaw, bank and pitch balanced so the
	-- reticle snaps to the cursor quickly and then gets it right to centre"). The S26 servo SHAPE below is
	-- verbatim (it IS the snap); the coordination lives in hPred above. Why this is the balanced form:
	--   · The VERTICAL channel never overshot because its damping is plant PITCH-RATE feedback. The
	--     horizontal channel's damp was on ROLL-rate — which settles the BANK, not the HEADING (the
	--     bank→turn→heading double integrator = every sail-past since S26). headRate is the missing
	--     HEADING-rate feedback: same medicine, right axis. (Jung & Tsiotras: an outer law blind to the
	--     inner loop's response IS the low-damped overshoot; the lead time is that awareness.)
	--   · REGIMES (set by the washout, see the lead block): RIM-PINNED cursor (or keys held) ⇒ lead = 0 ⇒
	--     the pure S26 law ⇒ full plant-capped sustained turn. Cursor held INSIDE the circle ⇒ settles at
	--     hPred = 0 ⇔ turn rate ≈ deflection/(τ·cosB·cosΔψ) — a steady proportional-rate fine turn.
	--     ARRIVAL (cursor world-fixed, error closing) ⇒ hPred crosses zero a lead-time EARLY → the command
	--     reverses and levelAssist unwinds the bank → the nose arrives ON the cursor. Deterministic.
	--     aimLeadTime is the ONE knob (the L1-period analogue — RESEARCH-coordinated-flight.md finding 5).
	--   ⚠️ The S28/S28b sqrt-controller→commanded-bank CASCADE (+ error-size mode blend) is REVERTED —
	--   Chad's playtest: the blend seam mushed 10-20° inputs ("yaws but won't bank, lost its snap") and the
	--   slew-limited bank fought the aggressive pitch on big swings ("over-delivering, up and around the
	--   cursor, porpoising"). Two controllers fighting across a seam is not coordination — do not re-try.
	-- Signs (keyBindings): bank/yaw RIGHT = negative roll/yaw input; a right bank (curBank > 0) is levelled
	-- with +roll. The roll-rate damp (aimRollDamp · current roll-rate) still kills the bank-axis wobble.
	local curBank = math.asin(clamp(-cf.RightVector.Y, -1, 1)) -- + = banked right (right wing down)
	-- ...only when upright (UpVector.Y>0) so it never fights the inverted top of a loop.
	local levelAssist = curBank * (C.aimLevelGain or 0.9)
		* (1 - math.min(1, math.abs(hCmd))) * math.max(0, cf.UpVector.Y)
	local rollRate = (currentProfile and currentProfile.rollRate) or 3.2
	local rollRate01 = clamp((flightEngine.rollVel or 0) / math.max(0.1, rollRate), -1, 1)
	-- STAGE A (S30) — HEADING-RATE DAMP (the porpoise / sail-past fix, Chad: "proper instruction to limit the
	-- porposing"). aimRollDamp above damps ROLL-rate (settles the BANK); the horizontal loop had NO feedback on
	-- HEADING-rate — and bank→turn→heading is a double integrator, so the nose coasts PAST the cursor after the
	-- bank has settled (every sail-past since S26). headRate (~line 1045, + = turning RIGHT, upright-faded) is
	-- that missing feedback; normalise by pitchRate (heading rate in a banked turn is elevator-delivered
	-- ≈ pitchVel·sinB, bounded by pitchRate — same divisor family as the loved vertical channel's pitchRate01).
	-- SIGN = + (SAME as levelAssist): a rightward heading swing (headRate>0) is arrested by +roll, which levels a
	-- right bank (see the signs note above). Added INSIDE the clamp AFTER the saturating P, so a rim-pinned
	-- full-deflection turn (|−hCmd·gain|≈7.5) stays clipped at ±1 = today's rate EXACTLY; the damp only bites near
	-- equilibrium (arrival), exactly like pitchRate01. Ships 0.45; 0 = byte-identical to today. ⚠️ if F7 shows
	-- overshoot GROWING not shrinking, the sign is inverted → flip to −. Revert: aimHeadDamp → 0.
	local headRate01 = clamp(headRate / math.max(0.1, pitchRate), -1, 1)
	-- INVERSION ENVELOPE (S30 Stage 1, FREE-CURSOR mode only). No auto-level (CS-5) → a freed far-corner
	-- cursor could hold roll saturated through vertical and REST INVERTED (the S28 tombstone). Fade ONLY the
	-- bank-DEEPENING part of the roll command as |bank| nears the ceiling; the leveling/damping part is left
	-- at full authority so recovery is always available; upright loops (bank≈0) are unaffected. SIGN: the
	-- kernel banks RIGHT on NEGATIVE roll (signs note above), so a right bank (curBank>0) DEEPENS when the
	-- roll command is negative ⇒ deepening ⟺ rollP·curBank < 0 (derived + scenario-checked; NOT the +sign the
	-- proposal assumed). Gated on aimFreeCursor so flag-off is byte-identical to the Stage-A baseline.
	local rollP = -hCmd * (C.aimRollGain or 2.0)
	local rollLevel = levelAssist - (C.aimRollDamp or 0.30) * rollRate01 + (C.aimHeadDamp or 0) * headRate01
	if C.aimFreeCursor then
		local ceilFade = clamp(((C.aimRollCeilingDeg or 180) - math.deg(math.abs(curBank))) / 20, 0, 1)
		if ceilFade < 1 and (rollP * curBank) < 0 then rollP = rollP * ceilFade end
	end
	local roll = clamp(rollP + rollLevel, -1, 1)
	local yaw  = clamp(-hCmd * (C.aimYawGain or 0.6), -1, 1)
	if C.invertPitch then pitch = -pitch end

	-- Marker screen positions for the render block.
	local margin = 24
	local function projWin(world) -- world -> window-space (incl. GUI inset), screen-centre fallback if behind
		local v = camera:WorldToViewportPoint(world)
		if v.Z <= 0 then return vp.X * 0.5 + inset.X, vp.Y * 0.5 + inset.Y end
		return math.clamp(v.X + inset.X, margin, vp.X + inset.X - margin),
		       math.clamp(v.Y + inset.Y, margin, vp.Y + inset.Y - margin)
	end
	-- CURSOR (green ring) = the WORLD-direction cursor you pilot (projected far). NOSE CROSS (amber) = the boresight
	-- (the bird's current heading, projected far). The nose chases the cursor; when it catches up they coincide and
	-- the beak points right at the cursor.
	aimCursor.cursorX, aimCursor.cursorY = projWin(cf.Position + aimTargetDir * 4000)
	aimCursor.noseX,   aimCursor.noseY   = projWin(cf.Position + birdLook * 4000)

	-- TALON ARC = a hemispherical arc of pips UNDER the bird, in its roll plane (the Up×Right plane). Each pip is
	-- a body-space direction swept from the left of the belly to the right; BANKING rotates Up & Right together,
	-- so the whole arc SWINGS naturally (it shows where the talons reach). NO left/right dichotomy — one arc, one
	-- belly zone; the server picks talon-vs-beak by which zone the enemy is in (read into aimCursor.armed below).
	local talonDist  = C.talonReticleDistance or 70
	local arcSpread  = math.rad(C.talonArcSpreadDeg or 60)
	local upV, rightV = cf.UpVector, cf.RightVector
	for i = 1, #talonPips do
		local t = (#talonPips > 1) and ((i - 1) / (#talonPips - 1) * 2 - 1) or 0 -- -1..1 across the arc
		local phi = t * arcSpread
		local dir = (-upV) * math.cos(phi) + rightV * math.sin(phi) -- belly-centred, sweeping side to side
		aimCursor.talonX[i], aimCursor.talonY[i] = projWin(cf.Position + dir * talonDist)
	end

	-- ARMED zone = which strike a LEFT-CLICK would throw RIGHT NOW. Chosen SERVER-side by enemy proximity to the
	-- beak (forward) vs talon (belly) zone and mirrored onto the Body as StrikeArmedDir ("beak"/"talon"/"none").
	-- Read it for the reticle lighting (the render block calls paintStrikeReticles). Authoritative; no bank read.
	aimCursor.armed = rootPart:GetAttribute("StrikeArmedDir") or "none"

	return pitch, roll, yaw
end

--------------------------------------------------------------------------------
-- MAIN FLIGHT STEP
--------------------------------------------------------------------------------
local function onFlightStep(dt)
	if not (isAlive and flightEngine and rootPart and rootPart.Parent) then
		return
	end
	_G.__evcDiagStep = (_G.__evcDiagStep or 0) + 1   -- DIAG: count guard-passing flight frames (see DIAG block)

	-- 1. Thermals -> engine.
	flightEngine:SetThermalForce(computeThermalForce(rootPart.Position))
	flightEngine:SetWind(GameConfig.Flight.WIND_BASE)

	-- 1b. Mouse mode. BOTH free-look and mouse-AIM now LOCK the mouse to centre: free-look orbits the camera off
	-- the delta, mouse-aim feeds the delta into the self-centering virtual cursor (so a deflection RESOLVES). The
	-- OS icon is hidden either way (our reticle replaces it). LockCenter is also what makes GetMouseDelta report.
	local C = GameConfig.Controls
	local aimOn = C and C.mouseAim and not freeLook.active
	if freeLook.active or aimOn then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		UserInputService.MouseIconEnabled = false
	end

	-- 1c. Keyboard tap->ramp smoothing for ALL THREE axes (eases input in; refines the banking so
	-- it's no longer all-or-nothing). A tap gives a small deflection; holding ramps to full.
	local tapP  = (C and C.pitchTapFraction) or 0.30
	local rampP = (C and C.pitchRampTime) or 0.55
	local tapB  = (C and C.bankTapFraction) or 0.22
	local rampB = (C and C.bankRampTime) or 0.50
	local kbPitch = rampAxis(pitchRamp, kb.pitch, tapP, rampP, dt)
	local kbRoll  = rampAxis(rollRamp,  kb.roll,  tapB, rampB, dt)
	local kbYaw   = rampAxis(yawRamp,   kb.yaw,   tapB, rampB, dt)

	-- 1d. Mouse-aim autopilot. While aiming: EASE the applied aim toward the live target and draw the
	-- reticle. While FREE-LOOK **or RIGHT-CLICK ZOOM** is active: NEUTRALISE the aim (ease to 0) so the bird
	-- HOLDS its current attitude — the plant has no auto-level (STABILITY_RATE=0), so zero rotational input
	-- keeps the nose/bank exactly where it is (flies where it points via grip). RIGHT-CLICK ZOOM is
	-- AWARENESS-ONLY (player ask: "the zoom right click cannot affect flying"): suspending steering here means
	-- the FOV change can't feed back through the camera-projection aim into pitch/bank. Keyboard SUMS on top
	-- below, so QWEASD still adjust the held attitude. Resumes mouse-aim cleanly on release/toggle-back.
	if aimOn and camera and not aimZoom.active then
		local aPitch, aRoll, aYaw = computeMouseAim(dt)
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (aPitch - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (aRoll  - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (aYaw   - aimApplied.yaw)   * resp
		aimGui.Enabled = true
		aimDot.Visible = true
		aimDot.Position    = UDim2.fromOffset(aimCursor.cursorX, aimCursor.cursorY) -- ring: your cursor (desired direction)
		noseMarker.Visible = true
		noseMarker.Position = UDim2.fromOffset(aimCursor.noseX, aimCursor.noseY)    -- amber: the beak boresight (cursor on it = level)
		aimZone.Visible = true -- restore the fixed centre tick (the RMB-zoom branch hides it; it never re-set true otherwise)
		local isEagle = (currentTeam == "Eagles") -- only the eagle strikes; crows keep just the boresight + cursor
		for i, p in ipairs(talonPips) do                                            -- belly arc: the talon strike zone (swings with bank)
			p.Visible = isEagle
			p.Position = UDim2.fromOffset(aimCursor.talonX[i] or 0, aimCursor.talonY[i] or 0)
		end
		paintStrikeReticles(aimCursor.armed) -- light the zone an enemy is engaging (server-chosen: beak/talon/none)
	else
		-- NOT actively steering (free-look, RMB zoom, or aim off): ease the aim command to 0 so the bird HOLDS
		-- its attitude (keyboard still sums on top). It must NOT keep applying the last command — a frozen rate
		-- (no auto-level to stop it) kept rotating the nose every frame -> a nose-over into a dive on release.
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (0 - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (0 - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (0 - aimApplied.yaw)   * resp
		-- FREE-LOOK reticles (player ask — "the crux"): keep BOTH markers on screen, but the CURSOR sits at the
		-- CENTRE of the free-look view (where you're looking) and the amber RETICLE stays on the eagle's BEAK
		-- direction (projected through the panned camera), so while you look around you see your heading vs your
		-- look. Steering stays suspended. RMB-zoom / aim-off keep the reticle hidden.
		if freeLook.active and camera and rootPart and rootPart.Parent then
			-- FREE-LOOK reticles (player ask, corrected): the CURSOR and the RETICLE stay LOCKED TOGETHER on the
			-- bird's pointing direction (the beak). As you look around, BOTH markers move together to show where the
			-- nose points relative to your look. (The roaming cursor with the reticle chasing it is the MOUSE-AIM
			-- mode — free-look keeps the two fused.)
			local vp = camera.ViewportSize
			local gi = GuiService:GetGuiInset()
			local bcf = rootPart.CFrame
			local bv = camera:WorldToViewportPoint(bcf.Position + bcf.LookVector * 4000)
			local onScreen = bv.Z > 0
			aimGui.Enabled = true
			noseMarker.Visible = onScreen
			aimDot.Visible = onScreen
			if onScreen then
				local bx = math.clamp(bv.X + gi.X, 24, vp.X + gi.X - 24)
				local by = math.clamp(bv.Y + gi.Y, 24, vp.Y + gi.Y - 24)
				noseMarker.Position = UDim2.fromOffset(bx, by)
				aimDot.Position    = UDim2.fromOffset(bx, by) -- cursor FUSED with the reticle on the beak
			end
			for _, p in ipairs(talonPips) do p.Visible = false end
			paintStrikeReticles("none")
		elseif aimZoom.active and camera and rootPart and rootPart.Parent then
			-- RMB ZOOM: SHOW the boresight reticle on the zoom's focal point (the beak, cf.LookVector*4000 — the
			-- exact world point updateCamera centres the telescope on) so "where you're aiming" is visible AT the
			-- zoom centre. Previously the reticle was HIDDEN during zoom, leaving only the faint HUD crosshair — so
			-- the magnified view had no aim reference and read as "zooming a bit above the reticle" (Chad 2026-07-02).
			-- The marker projects the SAME world point through the SAME camera, so it lands on the zoom centre by
			-- construction. Cursor ring + zone + strike pips hidden (steering is suspended) — just the clean boresight.
			local vp = camera.ViewportSize
			local gi = GuiService:GetGuiInset()
			local bcf = rootPart.CFrame
			local bv = camera:WorldToViewportPoint(bcf.Position + bcf.LookVector * 4000)
			aimGui.Enabled = true
			local onScreen = bv.Z > 0
			noseMarker.Visible = onScreen
			aimDot.Visible = false
			aimZone.Visible = false
			if onScreen then
				noseMarker.Position = UDim2.fromOffset(bv.X + gi.X, bv.Y + gi.Y)
			end
			for _, p in ipairs(talonPips) do p.Visible = false end
			paintStrikeReticles("none")
		else
			aimGui.Enabled = false
		end
	end
	-- CS-1 (LOCKED — Chad 2026-06-30, "this can't change anymore"): KEYBOARD FULLY OVERRIDES MOUSE-AIM.
	-- While ANY flight key (Q/W/E/A/S/D) is held, the mouse-aim cursor has ZERO pull on ALL THREE axes
	-- (full manual keyboard flight) — so a held S makes a STRAIGHT loop instead of the aim autopilot
	-- curving it back toward the cursor via roll/yaw. The instant every flight key is released, mouse-aim
	-- resumes on all axes (you re-find the cursor by moving the mouse — intended, NOT a bug).
	--   This is a GLOBAL gate, NOT per-axis. The previous per-axis version (1-|kb.axis|) suppressed only
	--   the KEYED axis's aim and left roll/yaw aim-pull live during a pure-pitch loop, curving it off —
	--   the exact bug Chad flagged. Do NOT re-add per-axis blending, and do NOT "solve" it by re-anchoring
	--   the cursor. Raw kb.* (±1/0) so the override is immediate; kbPitch/… keep the tap->ramp feel.
	local aimGate = (kb.pitch ~= 0 or kb.roll ~= 0 or kb.yaw ~= 0) and 0 or 1
	inputState.pitch = math.clamp(kbPitch + aimApplied.pitch * aimGate, -1, 1)
	inputState.roll  = math.clamp(kbRoll  + aimApplied.roll  * aimGate, -1, 1)
	inputState.yaw   = math.clamp(kbYaw   + aimApplied.yaw   * aimGate, -1, 1)

	-- 1e. FLAP THROTTLE (sticky): hold Shift to ramp UP-thrust, Ctrl to ramp DOWN-thrust; it HOLDS where
	-- you set it (no decay), so you can set a climb power and fly the spiral hands-free on the mouse.
	local thrRate = (C and C.flapThrottleRate) or 1.1
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)   then flapThrottle = math.min( 1, flapThrottle + thrRate * dt) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then flapThrottle = math.max(-1, flapThrottle - thrRate * dt) end
	inputState.flapThrottle = flapThrottle

	-- 2. Step the simulation with the live input.
	flightEngine:Update(dt, inputState)

	-- ==== BEGIN SCRATCH TELEMETRY (Wind Tunnel capture — DELETE after; non-committed) ====
	-- Captures the CLEAN internal state the flight_sim ToyPlant needs to be validated against.
	-- 1) flight_sim>  .\lune.ps1 run harness/capture_server.luau   (leave running)
	-- 2) In Studio command bar once:  game:GetService("HttpService").HttpEnabled = true
	-- 3) F8 start/stop buffering · F9 flush porpoise trace · F10 flush CFrame crossval
	-- REMOVE by deleting ONLY this delimited BEGIN..END block. Do NOT `git checkout` this file —
	-- it has other uncommitted (non-scratch) work that a checkout would destroy. Also delete
	-- src/server/_ScratchTele.server.luau and its ServerScriptService mapping in default.project.json.
	if _G.__evcScratchInit == nil then
		_G.__evcScratchInit = true
		_G.__evcBuf, _G.__evcCap = {}, false
		_G.__evcMetrics, _G.__evcStep = {}, nil  -- F7/F6 step-response instrument (Stage 0)
		local UIS = game:GetService("UserInputService")
		local RS = game:GetService("ReplicatedStorage")
		-- HttpService is SERVER-ONLY, so relay the CSV to a scratch server script that POSTs it.
		local remote = RS:FindFirstChild("_ScratchTele") or RS:WaitForChild("_ScratchTele", 10)
		local function post(name, body)
			if remote then
				remote:FireServer(name, body)
				print("[EvC scratch] sent " .. name .. " (" .. #body .. " bytes) -> server relay")
			else
				print("[EvC scratch] FAIL: _ScratchTele remote missing (server scratch script not synced?)")
			end
		end
		UIS.InputBegan:Connect(function(io, gp)
			if gp then return end
			if io.KeyCode == Enum.KeyCode.F8 then
				_G.__evcCap = not _G.__evcCap
				if _G.__evcCap then _G.__evcBuf = {} end
				print("[EvC scratch] capturing = " .. tostring(_G.__evcCap))
			elseif io.KeyCode == Enum.KeyCode.F9 then
				_G.__evcFlush = (_G.__evcFlush or 0) + 1
				local header = "dt,cmdP,cmdR,cmdY,wP,wR,wY,spd,aoa,aimX,aimY,aimZ,px,py,pz,r00,r01,r02,r10,r11,r12,r20,r21,r22"
				post("porpoise" .. _G.__evcFlush, header .. "\n" .. table.concat(_G.__evcBuf, "\n"))
				print("[EvC scratch] flushed " .. #_G.__evcBuf .. " rows -> porpoise" .. _G.__evcFlush)
				if #_G.__evcMetrics > 0 then
					post("metrics" .. _G.__evcFlush,
						"axis,stepDeg,settle_s,overshoot_deg,reversals,camTau_s\n" .. table.concat(_G.__evcMetrics, "\n"))
					print("[EvC scratch] flushed " .. #_G.__evcMetrics .. " step rows -> metrics" .. _G.__evcFlush)
				end
			elseif io.KeyCode == Enum.KeyCode.F10 then
				local rows = { "case,ax,ay,az" }
				local function add(tag, v) rows[#rows + 1] = string.format("%s,%.9f,%.9f,%.9f", tag, v.X, v.Y, v.Z) end
				local cf = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(90))
				add("yaw90.look", cf.LookVector); add("yaw90.right", cf.RightVector); add("yaw90.up", cf.UpVector)
				add("yaw90.vto", cf:VectorToObjectSpace(Vector3.new(0, 0, -1)))
				local cf2 = CFrame.fromAxisAngle(Vector3.new(1, 0, 0), math.rad(30)) * CFrame.fromAxisAngle(Vector3.new(0, 0, -1), math.rad(-20))
				add("c2.look", cf2.LookVector); add("c2.up", cf2.UpVector); add("c2.right", cf2.RightVector)
				add("c2.vto.up", cf2:VectorToObjectSpace(Vector3.new(0, 1, 0)))
				add("cross", Vector3.new(0, 0, -1):Cross(Vector3.new(0.259, 0, -0.966)))
				post("crossval", table.concat(rows, "\n"))
			elseif (io.KeyCode == Enum.KeyCode.F7 or io.KeyCode == Enum.KeyCode.F6) and camera and rootPart and rootPart.Parent then
				-- STEP-RESPONSE INJECTOR (Stage 0 instrument): snap the WORLD aim N deg off the current
				-- nose — F7 = lateral (the rubberbanding horizontal channel), F6 = vertical (the loved
				-- channel, a known-good baseline to calibrate the instrument against). Keep the mouse still
				-- and don't hold a flight key (CS-1 mutes aim): the instructor then chases a SCRIPTED step
				-- and the per-frame tracker below scores it into feel numbers. Purely a diagnostic input.
				local lateral = (io.KeyCode == Enum.KeyCode.F7)
				local cf = rootPart.CFrame
				local STEP_DEG = 30
				local axisV = lateral and cf.UpVector or cf.RightVector
				aimTargetDir = CFrame.fromAxisAngle(axisV, math.rad(STEP_DEG)):VectorToWorldSpace(cf.LookVector)
				local gap0 = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(aimTargetDir), -1, 1)))
				_G.__evcStep = {
					lateral = lateral, stepDeg = STEP_DEG, t = 0, prevErr = STEP_DEG, dSign = 0,
					reversals = 0, swing = 0, overshoot = 0, settleT = -1, inBand = 0,
					gap0 = math.max(gap0, 1e-3), gapTau = -1,
				}
				print(string.format("[EvC step] %s %d deg injected — keep mouse still", lateral and "LAT" or "VERT", STEP_DEG))
			end
		end)
	end
	if _G.__evcCap and rootPart and rootPart.Parent then
		local cf = rootPart.CFrame
		local a = aimTargetDir or cf.LookVector
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		_G.__evcBuf[#_G.__evcBuf + 1] = string.format(
			"%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.3f,%.4f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
			dt, inputState.pitch, inputState.roll, inputState.yaw,
			flightEngine.pitchVel or 0, flightEngine.rollVel or 0, flightEngine.yawVel or 0,
			flightEngine.speed or 0, flightEngine.aoaDeg or 0,
			a.X, a.Y, a.Z, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	-- STEP-RESPONSE TRACKER (Stage 0 instrument): scores an F7/F6 scripted step into feel NUMBERS —
	-- settle-time (to +/-2 deg, held 0.2s), overshoot (deg past the target), amplitude-gated reversal
	-- count (>1 deg swings), and the camera-gap decay time-constant. Inert unless a step is live.
	if _G.__evcStep and rootPart and rootPart.Parent and aimTargetDir and camera then
		local s = _G.__evcStep
		s.t = s.t + dt
		local lt = rootPart.CFrame:VectorToObjectSpace(aimTargetDir)       -- body frame, forward = -Z
		local err = s.lateral and math.deg(math.atan2(lt.X, -lt.Z)) or math.deg(math.atan2(lt.Y, -lt.Z))
		local d = err - s.prevErr                                          -- amplitude-gated reversal count
		local ns = (d > 0) and 1 or ((d < 0) and -1 or s.dSign)
		if ns ~= 0 and s.dSign ~= 0 and ns ~= s.dSign then
			if math.abs(s.swing) > 1 then s.reversals = s.reversals + 1 end
			s.swing = 0
		end
		s.swing = s.swing + d
		if ns ~= 0 then s.dSign = ns end
		s.prevErr = err
		if err < 0 then s.overshoot = math.max(s.overshoot, -err) end      -- past zero on the far side
		if math.abs(err) < 2 then                                          -- settle band +/-2 deg, held 0.2s
			s.inBand = s.inBand + dt
			if s.settleT < 0 and s.inBand >= 0.2 then s.settleT = s.t - 0.2 end
		else
			s.inBand = 0
		end
		if s.gapTau < 0 then                                               -- camera-gap decay time-constant
			local gap = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(aimTargetDir), -1, 1)))
			if gap <= 0.37 * s.gap0 then s.gapTau = s.t end
		end
		if (s.settleT >= 0 and s.inBand >= 0.2) or s.t > 3 then            -- done: settled, or 3s timeout
			local row = string.format("%s,%d,%.3f,%.2f,%d,%.3f", s.lateral and "lat" or "vert", s.stepDeg,
				(s.settleT >= 0) and s.settleT or -1, s.overshoot, s.reversals, (s.gapTau >= 0) and s.gapTau or -1)
			_G.__evcMetrics[#_G.__evcMetrics + 1] = row
			print("[EvC step] axis,stepDeg,settle_s,overshoot_deg,reversals,camTau_s = " .. row)
			_G.__evcStep = nil
		end
	end
	-- ==== END SCRATCH TELEMETRY ====

	-- 2b. Obstacle/ground collision (responsive grazing). On a survivable graze we slide the
	-- bird along the surface locally for zero-latency feel; a lethal head-on impact we do NOT
	-- clamp — the server's authoritative crash sweep (processCrashes) reads our clean position
	-- delta and kills us, so client and server never disagree on death.
	local crashedThisFrame = false
	local cparams = getCollisionParams()
	if cparams then
		local r = (currentProfile and currentProfile.bodyRadius) or 2.5
		local target = flightEngine.orientation.Position
		-- P3 non-lethal terrain (rescue): a huge effective crash speed makes every impact a graze-SLIDE
		-- (bounce), never a crash — so the eagle never dies on the forest. Stored CRASH_SPEED is untouched
		-- (combat byte-identical if un-shelved); the server mirrors this gate in processCrashes.
		local crashSpd = (GameConfig.Rescue and GameConfig.Rescue.enabled and GameConfig.Rescue.nonLethalTerrain)
			and 1e9 or GameConfig.Flight.CRASH_SPEED
		local newPos, newVel, crashed = BirdCollision.resolve(
			rootPart.Position, target, flightEngine.velocity, r, cparams, crashSpd
		)
		crashedThisFrame = crashed
		if (not crashed) and (newPos - target).Magnitude > 1e-3 then
			local cf = flightEngine.orientation
			flightEngine.orientation = (cf - cf.Position) + newPos
			flightEngine.velocity = newVel
		end
	end

	-- UPDRAFT line-riding score (legacy; disabled via config — SUPERSEDED by the rescue style meter).
	updateUpdraft(dt, crashedThisFrame)

	-- EAGLES TO THE RESCUE (S32): the catch loop + carry + deliver + style meter (all layered ON the
	-- flown path — never touches the kernel). Detection + slow-mo presentation live in updateRescue.
	updateRescue(dt)

	-- 3. Drive the character body from the engine state.
	rootPart.CFrame = flightEngine.orientation
	rootPart.AssemblyLinearVelocity = flightEngine.velocity
	rootPart.AssemblyAngularVelocity = Vector3.new()

	-- 4. Wing animation + wingtip stall vortices.
	if birdModel then
		BirdBuilder.AnimateWings(
			birdModel,
			flightEngine.isFlapping,
			flightEngine.isDiving,
			flightEngine.flapPhase,
			dt
		)
	end
	updateVortexTrails()

	-- 5. Camera + FOV.
	updateCamera(dt)

	-- 6. UI (stall warning + stamina).
	pushUI()
end

--------------------------------------------------------------------------------
-- BIRD ACQUISITION (standalone-model design — there is NO Roblox Character)
--
-- The server represents each player's bird(s) as standalone Models in
-- Workspace.Birds, tagged with attributes (the contract in docs/HANDOFF.md):
--   OwnerUserId (number) -- which player owns this bird
--   Possessed   (bool)   -- the single bird the player is actively flying
-- We find the Model owned by us with Possessed == true, take its PrimaryPart
-- ("Body") — which the server has handed us network ownership of — and drive it
-- locally with FlightPhysics. We re-acquire whenever possession moves (manual
-- SwapCrow, or server auto-repossess after a death) or a bird spawns/despawns.
--------------------------------------------------------------------------------
local birdsFolder = nil -- set once Workspace.Birds exists (server creates it on first spawn)
local attrConns  = {}   -- [model] = connection watching its "Possessed" attribute
local acquireGen = 0    -- guards against overlapping async acquisitions

local function resetInput()
	kb.pitch, kb.roll, kb.yaw = 0, 0, 0
	pitchRamp.sign, pitchRamp.mag = 0, 0
	rollRamp.sign, rollRamp.mag = 0, 0
	yawRamp.sign, yawRamp.mag = 0, 0
	steer.x, steer.y = 0, 0
	aimCursor.x, aimCursor.y = 0, 0
	aimTargetDir = nil
	aimLeadScale = 1
	aimApplied.pitch, aimApplied.roll, aimApplied.yaw = 0, 0, 0
	inputState.pitch, inputState.roll, inputState.yaw = 0, 0, 0
	inputState.flap, inputState.dive = false, false
	flapThrottle = 0
	inputState.flapThrottle = 0
end

local function teardownDrive()
	isAlive = false
	-- Kill any in-flight rescue catch beat so death/respawn/swap can't strand the global slow-mo
	-- desaturation, the camera offset, or orphan presentation squirrels (red-team BLOCK 1).
	resetRescuePresentation()
	flightEngine = nil
	birdModel = nil
	rootPart = nil
	-- Drop the persistent chase basis so the camera SNAPS to the new bird's pose on the first frame
	-- after a respawn/swap instead of visibly slewing in from the dead bird's last direction.
	cameraState.chaseDir = nil
	cameraState.camUpPrev = nil
	cameraState.camUp = nil          -- drop the parallel-transported up so it re-seeds level on the new bird
	cameraState.chaseDirPrev = nil
	cameraState.aimHeading = nil     -- drop the lagged aim heading so it re-seeds to the new bird's heading
	cameraState.prevLook = nil
	-- Release the mouse between lives; onFlightStep re-locks/hides it once we're driving again.
	if not freeLook.active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	aimGui.Enabled = false
	UserInputService.MouseIconEnabled = true
end

local function findMyPossessedBird()
	if not birdsFolder then return nil end
	for _, model in ipairs(birdsFolder:GetChildren()) do
		if model:IsA("Model")
			and model:GetAttribute("OwnerUserId") == player.UserId
			and model:GetAttribute("Possessed") == true then
			return model
		end
	end
	return nil
end

-- (Re)acquire the bird we should be flying. Safe to call repeatedly: no-ops if we
-- are already driving the right Model. Runs in its own thread (via reacquire) so it
-- can WaitForChild the Body part while the Model is still replicating in.
local function acquire()
	if not currentProfile then return end
	local target = findMyPossessedBird()
	if target == birdModel and isAlive then return end

	acquireGen += 1
	local myGen = acquireGen
	teardownDrive()
	resetInput()
	-- Free-look is LAW: it must survive a crow-swap. Don't force it off here — re-arm it to
	-- whether Space is still physically held, so swapping crows (1-4) while looking around keeps
	-- the look (and its current orbit, since setFreeLook no-ops when already active). Only a
	-- genuine release (or focus loss / death without Space) turns it off.
	setFreeLook(UserInputService:IsKeyDown(Enum.KeyCode.Space))

	-- Nothing to re-assert for the new bird: LEFT-CLICK strike is a tap (no held intent), and RMB
	-- aim-zoom is module-level camera state (a held RMB survives the swap on its own).

	if not target then return end

	local body = target.PrimaryPart or target:WaitForChild("Body", 5)
	-- A newer acquire() superseded us, or the Model despawned while we waited.
	if myGen ~= acquireGen then return end
	if not body or not target.Parent then return end

	-- Wait for the server to confirm it handed us network ownership (NetOwner attribute set
	-- in GameServer.trySetNetworkOwner). Driving the Body before ownership lands makes our
	-- CFrame writes fight the server's sim → the spawn/swap rubber-band. Best-effort: if the
	-- signal never arrives within the timeout we proceed anyway (better to fly than be stuck).
	local timeout = 5
	while body:GetAttribute("NetOwner") ~= player.UserId
		and myGen == acquireGen and target.Parent and timeout > 0 do
		timeout -= task.wait()
	end
	if myGen ~= acquireGen or not target.Parent then return end

	birdModel = target
	rootPart  = body

	-- Wingtip stall-vortex vapor for the bird we're now flying (idempotent per model).
	buildVortexTrails(target)

	-- Seed the engine from the body's LIVE state so swapping crows (or taking over a
	-- bird the server was flying) does not snap position/heading/velocity.
	flightEngine = FlightPhysics.new(currentProfile, body.Position)
	flightEngine.orientation   = body.CFrame
	flightEngine.velocity      = body.AssemblyLinearVelocity
	flightEngine.speed         = body.AssemblyLinearVelocity.Magnitude
	flightEngine.verticalSpeed = body.AssemblyLinearVelocity.Y

	isAlive = true
end

local acquiring = false
-- (Re)acquire in its own thread. Wrapped so we can (a) surface any error instead of leaving the flight
-- loop silently dead, and (b) expose an `acquiring` flag so the backstop poll never restarts an in-flight
-- attempt (which would reset acquire()'s NetOwner wait and could livelock a slow hand-off).
local function reacquire()
	task.spawn(function()
		acquiring = true
		local ok, err = pcall(acquire)
		acquiring = false
		if not ok then warn("[EvC] acquire() error: " .. tostring(err)) end
	end)
end

-- Watch ownership/possession flips on EVERY bird Model (not just ones we already own) so crow-swaps,
-- auto-repossess, AND the very first possession re-acquire. Attributes replicate SEPARATELY from the
-- Model, so OwnerUserId/Possessed can land AFTER ChildAdded / folder wire-up — the old code gated the
-- watcher on OwnerUserId being ours ALREADY, so a late attribute set triggered nothing and we could
-- get stuck never acquiring (default camera + free mouse + server-driven waver). acquire() no-ops when
-- we're already flying the right bird, so watching broadly is cheap and idempotent.
local function trackModel(model)
	if not model:IsA("Model") or attrConns[model] then return end
	attrConns[model] = model.AttributeChanged:Connect(function(attr)
		if attr == "Possessed" or attr == "OwnerUserId" or attr == "NetOwner" then
			reacquire()
		end
	end)
end

-- TeamAssigned carries our profile (Eagle/Crow). Connected SYNCHRONOUSLY (before any
-- yield) so we never miss the round-start event. Birds may already exist (joined
-- mid-round) or arrive afterward; either way, (re)acquire once we know the profile.
TeamAssigned.OnClientEvent:Connect(function(teamName, profile)
	currentTeam = teamName
	if profile then currentProfile = profile end
	reacquire()
end)

-- Roblox does not deliver InputEnded for keys still held when the window loses focus
-- (alt-tab, menu, click-out). Without this the bird keeps flapping/pitching with no key
-- down and flies off. Neutralize all held input and drop free-look on focus loss.
UserInputService.WindowFocusReleased:Connect(function()
	resetInput()
	setFreeLook(false)
end)

--------------------------------------------------------------------------------
-- REMOTE WING ANIMATION (every bird EXCEPT the one we're actively flying)
--
-- Motor6D.Transform does NOT cross the network boundary, so a bird only flaps on
-- the machine simulating it (its owning client, or the server for AI crows). To
-- make EVERY bird flap on EVERY screen, each client animates all the OTHER birds
-- itself, deriving the wing state from already-replicated motion (CFrame + velocity):
--   • isDiving is EXACT — FlightPhysics defines it as LookVector.Y < -0.2, and CFrame
--     replicates, so we reproduce the dive-tuck identically to the owner.
--   • isFlapping is a cosmetic guess from vertical/airspeed (climbing or slow ⇒ flap);
--     nobody can perceive flap-phase desync on a bird they don't control.
--   • flapPhase advances locally per-model at FlightPhysics' own rates (~2 rad/s gliding,
--     ~8 flapping) — zero per-frame network traffic (no SetAttribute spam).
-- The bird we ARE flying is animated with exact engine state in onFlightStep, so we
-- skip it here to avoid double-driving the joints.
--------------------------------------------------------------------------------
local remoteFlapPhase = setmetatable({}, { __mode = "k" }) -- [model] = phase; weak so it GCs with the model

local function animateOtherBirds(dt)
	if not birdsFolder then return end
	for _, model in ipairs(birdsFolder:GetChildren()) do
		if model ~= birdModel and model:IsA("Model") then
			local body = model.PrimaryPart
			if body then
				-- isDiving: EXACT match to FlightPhysics (nose pitched down past ~11°).
				local diving = body.CFrame.LookVector.Y < -0.2
				-- isFlapping: cosmetic — a bird beats its wings to climb or when slow, and
				-- glides when fast and level/descending.
				local v = body.AssemblyLinearVelocity
				local flapping = (not diving) and (v.Y > 2 or v.Magnitude < 55)
				local freq = flapping and 8 or 2
				local phase = ((remoteFlapPhase[model] or 0) + dt * freq) % (math.pi * 2)
				remoteFlapPhase[model] = phase
				BirdBuilder.AnimateWings(model, flapping, diving, phase, dt)
			end
		end
	end
end

-- One persistent flight loop: it drives whichever bird we currently hold (exact engine
-- state) and animates every other visible bird from replicated motion; idles cleanly
-- when we hold none (between deaths / round resets).
renderConn = RunService.RenderStepped:Connect(function(dt)
	onFlightStep(dt)
	animateOtherBirds(dt)
end)

-- Wire the bird folder once the server has created it (it does so on first spawn).
-- Deferred so the WaitForChild yield can't delay the TeamAssigned connection above.
task.spawn(function()
	birdsFolder = workspace:WaitForChild("Birds")

	birdsFolder.ChildAdded:Connect(function(child)
		trackModel(child)
		reacquire()
	end)
	birdsFolder.ChildRemoved:Connect(function(child)
		if attrConns[child] then
			attrConns[child]:Disconnect()
			attrConns[child] = nil
		end
		if child == birdModel then
			teardownDrive()
		end
		reacquire()
	end)
	for _, child in ipairs(birdsFolder:GetChildren()) do
		trackModel(child)
	end

	-- Acquire now in case TeamAssigned already fired and our birds already exist.
	reacquire()

	-- BACKSTOP: if an attribute-timing race ever leaves us NOT flying despite our bird existing and
	-- being possessed, poll a reacquire until we're driving. No-ops the instant we hold the right bird
	-- (acquire early-returns), stays quiet when there's legitimately nothing to fly (dead / between
	-- rounds → findMyPossessedBird returns nil), and skips while an acquire is already in flight.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if currentProfile and not isAlive and not acquiring and findMyPossessedBird() then
				reacquire()
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- ▼▼▼ DIAG BLOCK — read-only; delete once the "unplayable on Studio replay" bug is convicted. ▼▼▼
-- Writes NOTHING to control/camera/aim/kernel state. Pure reads + one on-screen label + a 1 Hz Output
-- print. Runs in its OWN RenderStepped so it reports even when onFlightStep early-returns. It discriminates
-- the three candidate causes (Fable consult a8323c48f8c02bf0a):
--   alive=false prof=NIL mouse=Default          → TeamAssigned/profile race (press R should recover)
--   alive=true  mouse=LockCenter  dmax huge (hand still) → Studio mouse-capture leak (a click may recover)
--   alive=true  dmax normal  net~=me or rxAge>0 pulsing   → server ownership fight ([AntiCheat] warns server-side)
-- Toggle DIAG=false to silence.
--------------------------------------------------------------------------------
do
	local DIAG = false   -- flip to true to re-arm the overlay if the "unplayable on replay" bug ever recurs
	if DIAG then
		local sg = Instance.new("ScreenGui")
		sg.Name = "EvCDiag"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.DisplayOrder = 100000
		sg.Parent = player:WaitForChild("PlayerGui")
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0, 560, 0, 96)
		lbl.Position = UDim2.new(0, 8, 0, 8)
		lbl.BackgroundTransparency = 0.35
		lbl.BackgroundColor3 = Color3.new(0, 0, 0)
		lbl.TextColor3 = Color3.fromRGB(0, 255, 120)
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 15
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.Text = "[EvC diag] starting…"
		lbl.Parent = sg

		local acc = 0
		local dmax, camSpin, birdSpin, spdMax = 0, 0, 0, 0
		local prevCamLook, prevBirdLook
		RunService.RenderStepped:Connect(function(dt)
			local ok, d = pcall(function() return UserInputService:GetMouseDelta().Magnitude end)
			if ok and d > dmax then dmax = d end
			-- OUTPUT-side (no input dependency): per-frame rotation of the camera AND the bird nose = the
			-- unambiguous "spinning / wavering" measure. If these are large with dmax~0 the aim/physics is
			-- self-driving; if spd explodes/NaNs the kernel blew up.
			local camLook = camera and camera.CFrame.LookVector
			if camLook and prevCamLook then
				local a = math.deg(math.acos(math.clamp(camLook:Dot(prevCamLook), -1, 1)))
				if a == a and a > camSpin then camSpin = a end   -- a==a rejects NaN
			end
			prevCamLook = camLook
			if flightEngine then
				local sp = flightEngine.speed
				if sp and sp > spdMax then spdMax = sp end
				local bl = flightEngine.orientation and flightEngine.orientation.LookVector
				if bl and prevBirdLook then
					local a = math.deg(math.acos(math.clamp(bl:Dot(prevBirdLook), -1, 1)))
					if a == a and a > birdSpin then birdSpin = a end
				end
				prevBirdLook = bl
			end
			acc += dt
			if acc < 0.25 then return end
			local hz = (_G.__evcDiagStep or 0) * 4
			_G.__evcDiagStep = 0
			acc = 0
			local net = rootPart and rootPart:GetAttribute("NetOwner")
			local ap = aimApplied or {}
			lbl.Text = string.format(
				"[EvC diag] alive=%s prof=%s bird=%s root=%s\nstepHz~=%d mouse=%s dmax=%.0f net=%s me=%d\nspd=%.0f  camSpin=%.0f/f  birdSpin=%.0f/f\naim(pry)=%.2f/%.2f/%.2f  camOK=%s freeLook=%s",
				tostring(isAlive), tostring(currentProfile ~= nil),
				tostring(birdModel ~= nil), tostring(rootPart ~= nil and rootPart.Parent ~= nil),
				hz, UserInputService.MouseBehavior.Name, dmax, tostring(net), player.UserId,
				spdMax, camSpin, birdSpin,
				ap.pitch or 0, ap.roll or 0, ap.yaw or 0,
				tostring(workspace.CurrentCamera == camera), tostring(freeLook.active)
			)
			dmax, camSpin, birdSpin, spdMax = 0, 0, 0, 0
		end)

		task.spawn(function()
			while true do
				task.wait(1)
				print(lbl.Text)
			end
		end)
	end
end
-- ▲▲▲ END DIAG BLOCK ▲▲▲
