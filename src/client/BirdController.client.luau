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
	  Spacebar     -> FREE-LOOK camera (TOGGLE): tap to orbit the camera freely around the bird while
	                  the bird HOLDS its current flight input (aim autopilot suspended); tap again to resume aim.
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
-- not the camera — keep it that way). yaw accumulates unbounded -> full 360° horizontal; pitch
-- is clamped just short of the poles so you can look straight up/down/behind without gimbal flip.
local FREE_LOOK_PITCH_LIMIT = 1.70 -- radians (~97°): look straight up/down AND a touch past, both ways (player
                                   -- wanted more range toward the poles) — kept well under π so it never spins round
local freeLook = {
	active = false,
	yaw    = 0, -- radians, horizontal orbit (unbounded -> 360°)
	pitch  = 0, -- radians, vertical orbit (clamped to +/- FREE_LOOK_PITCH_LIMIT)
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
noseMarker.Size = UDim2.fromOffset(34, 34)
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
aimDot.Size = UDim2.fromOffset(22, 22)
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
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
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
		-- FREE-LOOK is a TOGGLE now (Chad: "change to toggle on/off by space, not press and hold").
		-- Tap to look all around hands-free while the bird HOLDS its maneuver; tap again to snap the
		-- aim back. The orbit resets each time it's toggled ON (in setFreeLook), so it always begins
		-- from the chase pose. Survives crow-swaps via acquire() re-arming to freeLook.active.
		setFreeLook(not freeLook.active)
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
	-- NOTE: Space no longer turns free-look off on key-release — it's a TOGGLE (handled in InputBegan).
	-- Focus loss (WindowFocusReleased) still force-clears it so you never get stuck looking around.

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
		-- Free-look pitch: mouse-up looks UP, mouse-down looks down (player re-inverted 2026-06-30). Yaw/pan
		-- unchanged. The arrow-key pitch below is kept in sync (Up = look up) so both inputs agree.
		freeLook.pitch = math.clamp(freeLook.pitch + input.Delta.Y * s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT)
	end
	-- (Mouse-aim reads the absolute cursor position in onFlightStep; nothing to accumulate here.)
end)

-- Arrow keys also orbit the free-look camera (alternative to the mouse).
RunService.RenderStepped:Connect(function(dt)
	if not freeLook.active then return end
	local s = CAM.freeLookSensitivity * 2.5 * dt
	if UserInputService:IsKeyDown(Enum.KeyCode.Left)  then freeLook.yaw   = freeLook.yaw   + s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then freeLook.yaw   = freeLook.yaw   - s end
	-- Up/Down match the mouse pitch (player re-inverted): Up key looks UP (-s), Down key looks DOWN (+s).
	if UserInputService:IsKeyDown(Enum.KeyCode.Up)    then freeLook.pitch = math.clamp(freeLook.pitch - s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down)  then freeLook.pitch = math.clamp(freeLook.pitch + s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT) end
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
	local desiredChase = -followDir
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

	-- Camera-up = world-up made perpendicular to the chase direction: keeps the horizon level in normal
	-- flight and tilts CONTINUOUSLY as the chase goes vertical (so CFrame.lookAt never degenerates). Near
	-- the pole (chase ~ straight up/down) we hold the last good up so it can't pop.
	local worldUp = Vector3.yAxis - chaseDir * chaseDir.Y
	if worldUp.Magnitude < 0.15 then
		worldUp = cameraState.camUpPrev or Vector3.yAxis
	else
		worldUp = worldUp.Unit
	end
	cameraState.camUpPrev = worldUp

	-- LOOP TURN-OVER (player ask 2026-06-30: "in mouse mode, doing a loop the camera should turn over
	-- smoother/better"). Over a fast loop CREST, lean the camera up toward the BIRD'S own up so the camera
	-- rolls AROUND with the bird and arcs over the top smoothly (bird stays oriented in frame), instead of the
	-- horizon staying world-flat while the bird inverts in front of you. crestBlend gates it: ZERO in normal
	-- flight (horizon stays perfectly level — no change there), ramping in only as the loop whips over the top.
	-- Camera-only; chaseDir (the no-snap basis) is untouched, so no azimuth snap is reintroduced.
	local camUp = worldUp
	if not freeLook.active and (CAM.loopFollowUp or 0) > 0 then
		local t = crestBlend * CAM.loopFollowUp
		if t > EPS then
			local blended = worldUp:Lerp(cf.UpVector, t)
			camUp = (blended.Magnitude > 0.05) and blended.Unit or (cameraState.camUpPrev or worldUp)
		end
	end

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
		local yawCF = CFrame.fromAxisAngle(Vector3.yAxis, freeLook.yaw)
		local pitchAxis = yawCF:VectorToWorldSpace(Vector3.xAxis) -- world-horizontal right, yaw-rotated
		local orbit = CFrame.fromAxisAngle(pitchAxis, freeLook.pitch) * yawCF
		cameraOffset = orbit:VectorToWorldSpace(cameraOffset)
		-- HORIZON LOCK (player ask 2026-06-30: "when I bank, the free-look camera falls to the side — I'm
		-- watching with my head tilted; if it could stay up that'd be great"). Rebuild the up vector FRESH
		-- as world-up made perpendicular to the actual (orbited) view direction, instead of carrying the
		-- chase up through the orbit. This makes the free-look horizon WORLD-LEVEL by construction — it can
		-- never inherit the bird's roll, no matter how hard you bank while looking around. Near a straight
		-- up/down look the projection degenerates, so we hold the last good up (no pop at the pole).
		local viewDir = (cameraOffset.Magnitude > EPS) and cameraOffset.Unit or camUp
		local level   = Vector3.yAxis - viewDir * viewDir.Y
		camUp = (level.Magnitude > 0.15) and level.Unit or (cameraState.camUpPrev or camUp)
		cameraState.camUpPrev = camUp
	end

	local camPos  = position + cameraOffset
	-- Look slightly AHEAD of the bird along its flight path (the bird then sits a touch low in frame for a
	-- forward-leaning, lead-the-target feel). camUp is the continuous up reference -> no inverted roll snap.
	-- In free-look, look straight at the bird (no flight-path lead) so the orbit is fully world-referenced
	-- and the look target doesn't wobble as the bird's heading swings through a loop; lead only in chase mode.
	-- The look target stays CENTRED ON THE HEADING (chase) / the panned view (free-look) — the right-click
	-- zoom does NOT swing it toward the cursor (that offset the zoom AND, because mouse-aim steers off the
	-- live camera projection, fed back into flight). The zoom is purely FOV magnify + eagle-fade now, and the
	-- steering is suspended while zooming (onFlightStep), so right-click is awareness-only — it never flies you.
	local lookTarget = freeLook.active and position or (position + followDir * (dist * 0.12))
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
	end

	-- Frame-rate independent smoothing toward the target.
	local alpha = math.clamp(1 - math.exp(-smoothing * 60 * dt), 0, 1)
	camera.CFrame = camera.CFrame:Lerp(targetCF, alpha)

	-- High-speed shake.
	if speed > CAM.shakeAtSpeed then
		local intensity = ((speed - CAM.shakeAtSpeed) / 100) * CAM.shakeMagnitude
		camera.CFrame = camera.CFrame * CFrame.new(
			(math.random() - 0.5) * intensity,
			(math.random() - 0.5) * intensity,
			0
		)
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
local function computeMouseAim()
	local C = GameConfig.Controls
	if not (C and C.mouseAim) or freeLook.active then
		return 0, 0, 0
	end
	if not (rootPart and rootPart.Parent and camera and flightEngine) then return 0, 0, 0 end
	local vp = camera.ViewportSize
	if not vp or vp.Y < 2 then return 0, 0, 0 end

	-- Project the BEAK RETICLE (boresight): a point just out front of the beak. Drawing the cross AND computing
	-- the aim error from the SAME point is what makes "cursor centred on the cross == straight & level flight"
	-- (the controller is differential: cursor relative to the cross = the commanded rotation; cursor ON the cross
	-- = zero rotation = hold attitude). This is COUPLED to beakReticleDistance now — moving it changes ONLY where
	-- the neutral cursor sits, NOT the per-pixel feel (the error is a screen-space angle between two camera rays,
	-- independent of the projection distance), so the loved gains carry over. (The old 600-stud DECOUPLED draw
	-- dove at centre: the cross was drawn at the beak but the error referenced 600 studs out — Chad's bug.)
	local cf = rootPart.CFrame
	local birdLook = cf.LookVector
	local nosePoint = cf.Position + birdLook * (C.beakReticleDistance or 90)
	local noseVP = camera:WorldToViewportPoint(nosePoint)
	local inFront = noseVP.Z > 0

	local inset = GuiService:GetGuiInset()
	local mouse = UserInputService:GetMouseLocation()

	-- CLAMP the aim cursor to a big CIRCLE CENTRED on the screen (player ask 2026-06-30: "it should cover ~7/8
	-- of the screen by AREA and be centred"). Centre = the viewport centre in window coords (matches the
	-- nose-cross's own screen-centre, since aimGui.IgnoreGuiInset = true). Radius is set from a target AREA
	-- fraction: r = sqrt(areaFrac · W · H / π) — at 7/8 this reaches the top/bottom edges and most of the
	-- width. Past the rim the reticle is pinned, so the command just stays saturated (sustained full turn/loop)
	-- instead of sliding to a corner. Clamping `mouse` here feeds BOTH the aim ray and the drawn reticle.
	local cx, cy = inset.X + vp.X * 0.5, inset.Y + vp.Y * 0.5
	local maxR   = math.sqrt(((C.aimCursorAreaFrac or 0.875) * vp.X * vp.Y) / math.pi)
	local dx, dy = mouse.X - cx, mouse.Y - cy
	local r = math.sqrt(dx * dx + dy * dy)
	if r > maxR and r > EPS then
		local k = maxR / r
		mouse = Vector2.new(cx + dx * k, cy + dy * k)
	end

	-- Resolve the cursor into a desired BODY-frame direction. Comparing the camera ray through the cursor
	-- with the camera ray through the CROSS makes "cursor on the cross" == zero error (no neutral bias from
	-- the chase camera's offset). Rotate the bird's actual nose by that same cross->cursor rotation.
	local localTarget
	if inFront then
		local aimDir  = camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y).Direction
		local noseDir = camera:ViewportPointToRay(noseVP.X, noseVP.Y).Direction
		local d = math.clamp(noseDir:Dot(aimDir), -1, 1)
		local targetLook = birdLook
		if d < 0.99999 then
			local axis = noseDir:Cross(aimDir)
			if axis.Magnitude > 1e-5 then
				targetLook = CFrame.fromAxisAngle(axis.Unit, math.acos(d)):VectorToWorldSpace(birdLook)
			end
		end
		localTarget = cf:VectorToObjectSpace(targetLook)
	else
		-- Cross behind the camera (over the top of a loop): the projection flips, so synthesise a target
		-- from the cursor's vertical offset so the bird KEEPS pulling through instead of snapping/reversing.
		local upAmt = ((vp.Y * 0.5 + inset.Y) - mouse.Y) / (vp.Y * 0.5) -- + = cursor above centre
		localTarget = Vector3.new(0, math.clamp(upAmt, -1, 1), -1).Unit
	end

	-- Body-frame target (x = right, y = up; forward = -z). HORIZONTAL drives bank+yaw, VERTICAL drives pitch.
	local rgt = localTarget.X
	local upc = localTarget.Y

	-- SYMMETRIC shaping (deadzone + EXPO) on BOTH axes — WT "nonlinearity" (RESEARCH §v4). Gentle near
	-- centre for fine aim, ramping to FULL authority at the edge, so PITCH keeps full pull for a clean
	-- vertical loop AND a slight sideways cursor no longer snaps into a hard bank. Consistent feel both axes.
	local hCmd = shapeAxis(rgt, C.aimBankDeadzone or 0.10, C.aimBankExpo or 1.8)
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
	local pitchRate = (currentProfile and currentProfile.pitchRate) or 2.0
	local pitchRate01 = clamp((flightEngine.pitchVel or 0) / math.max(0.1, pitchRate), -1, 1)
	local pitch = vCmd * (C.aimPitchGain or 2.6) - (C.aimPitchDamp or 0.35) * pitchRate01
	if pitch > 0 then pitch = pitch * aoaHead end  -- ride-the-edge protection on the nose-UP pull only
	pitch = clamp(pitch, -1, 1)

	-- BANK + RUDDER fire TOGETHER toward the target (coordinated flight), now PD-damped. When there's no
	-- bank demand (hCmd ~ 0) a wings-LEVELLING term rolls the wings level, so a top-centre cursor flies
	-- STRAIGHT UP instead of getting stuck in a bank. Signs (keyBindings): bank/yaw RIGHT = negative
	-- roll/yaw input; a right bank (curBank > 0) is levelled with +roll. The roll-rate damp (aimRollDamp ·
	-- current roll-rate) kills the bank oscillation that made a sustained coordinated turn wobble.
	local curBank = math.asin(clamp(-cf.RightVector.Y, -1, 1)) -- + = banked right (right wing down)
	-- ...only when upright (UpVector.Y>0) so it never fights the inverted top of a loop.
	local levelAssist = curBank * (C.aimLevelGain or 0.9)
		* (1 - math.min(1, math.abs(hCmd))) * math.max(0, cf.UpVector.Y)
	local rollRate = (currentProfile and currentProfile.rollRate) or 3.2
	local rollRate01 = clamp((flightEngine.rollVel or 0) / math.max(0.1, rollRate), -1, 1)
	local roll = clamp(-hCmd * (C.aimRollGain or 2.0) + levelAssist - (C.aimRollDamp or 0.30) * rollRate01, -1, 1)
	local yaw  = clamp(-hCmd * (C.aimYawGain or 0.6), -1, 1)
	if C.invertPitch then pitch = -pitch end

	-- Marker screen positions for the render block. The CURSOR (green ring) follows the mouse (the forward aim).
	local margin = 24
	aimCursor.cursorX, aimCursor.cursorY = mouse.X, mouse.Y
	local function projWin(world) -- world -> window-space (incl. GUI inset), screen-centre fallback if behind
		local v = camera:WorldToViewportPoint(world)
		if v.Z <= 0 then return vp.X * 0.5 + inset.X, vp.Y * 0.5 + inset.Y end
		return math.clamp(v.X + inset.X, margin, vp.X + inset.X - margin),
		       math.clamp(v.Y + inset.Y, margin, vp.Y + inset.Y - margin)
	end

	-- BEAK reticle = the same projected boresight point used for the aim error (noseVP), so "cursor on it = level".
	aimCursor.noseX, aimCursor.noseY = projWin(nosePoint)

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

	-- 1. Thermals -> engine.
	flightEngine:SetThermalForce(computeThermalForce(rootPart.Position))
	flightEngine:SetWind(GameConfig.Flight.WIND_BASE)

	-- 1b. Mouse mode. Free-look LOCKS the mouse to orbit the camera; otherwise mouse-AIM uses the
	-- absolute cursor (Default behavior). The OS icon is hidden either way (our reticle replaces it).
	local C = GameConfig.Controls
	local aimOn = C and C.mouseAim and not freeLook.active
	if freeLook.active then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		UserInputService.MouseIconEnabled = false
	elseif aimOn then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
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
		local aPitch, aRoll, aYaw = computeMouseAim()
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (aPitch - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (aRoll  - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (aYaw   - aimApplied.yaw)   * resp
		aimGui.Enabled = true
		aimDot.Position    = UDim2.fromOffset(aimCursor.cursorX, aimCursor.cursorY) -- ring: your cursor (desired direction)
		noseMarker.Position = UDim2.fromOffset(aimCursor.noseX, aimCursor.noseY)    -- amber: the beak boresight (cursor on it = level)
		local isEagle = (currentTeam == "Eagles") -- only the eagle strikes; crows keep just the boresight + cursor
		for i, p in ipairs(talonPips) do                                            -- belly arc: the talon strike zone (swings with bank)
			p.Visible = isEagle
			p.Position = UDim2.fromOffset(aimCursor.talonX[i] or 0, aimCursor.talonY[i] or 0)
		end
		paintStrikeReticles(aimCursor.armed) -- light the zone an enemy is engaging (server-chosen: beak/talon/none)
	else
		-- FREE-LOOK (or mouse-aim off): ease the aim command to 0 so the bird holds its attitude and is
		-- modifiable ONLY by keyboard. It must NOT keep applying the last command — a frozen rate (no auto-
		-- level to stop it) kept rotating the nose every frame -> the nose-over into a dive on release.
		local resp = math.clamp(((C and C.aimResponse) or 7) * dt, 0, 1)
		aimApplied.pitch = aimApplied.pitch + (0 - aimApplied.pitch) * resp
		aimApplied.roll  = aimApplied.roll  + (0 - aimApplied.roll)  * resp
		aimApplied.yaw   = aimApplied.yaw   + (0 - aimApplied.yaw)   * resp
		aimGui.Enabled = false
	end
	inputState.pitch = math.clamp(kbPitch + aimApplied.pitch, -1, 1)
	inputState.roll  = math.clamp(kbRoll  + aimApplied.roll,  -1, 1)
	inputState.yaw   = math.clamp(kbYaw   + aimApplied.yaw,   -1, 1)

	-- 1e. FLAP THROTTLE (sticky): hold Shift to ramp UP-thrust, Ctrl to ramp DOWN-thrust; it HOLDS where
	-- you set it (no decay), so you can set a climb power and fly the spiral hands-free on the mouse.
	local thrRate = (C and C.flapThrottleRate) or 1.1
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)   then flapThrottle = math.min( 1, flapThrottle + thrRate * dt) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then flapThrottle = math.max(-1, flapThrottle - thrRate * dt) end
	inputState.flapThrottle = flapThrottle

	-- 2. Step the simulation with the live input.
	flightEngine:Update(dt, inputState)

	-- 2b. Obstacle/ground collision (responsive grazing). On a survivable graze we slide the
	-- bird along the surface locally for zero-latency feel; a lethal head-on impact we do NOT
	-- clamp — the server's authoritative crash sweep (processCrashes) reads our clean position
	-- delta and kills us, so client and server never disagree on death.
	local cparams = getCollisionParams()
	if cparams then
		local r = (currentProfile and currentProfile.bodyRadius) or 2.5
		local target = flightEngine.orientation.Position
		local newPos, newVel, crashed = BirdCollision.resolve(
			rootPart.Position, target, flightEngine.velocity, r, cparams, GameConfig.Flight.CRASH_SPEED
		)
		if (not crashed) and (newPos - target).Magnitude > 1e-3 then
			local cf = flightEngine.orientation
			flightEngine.orientation = (cf - cf.Position) + newPos
			flightEngine.velocity = newVel
		end
	end

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
	aimApplied.pitch, aimApplied.roll, aimApplied.yaw = 0, 0, 0
	inputState.pitch, inputState.roll, inputState.yaw = 0, 0, 0
	inputState.flap, inputState.dive = false, false
	flapThrottle = 0
	inputState.flapThrottle = 0
end

local function teardownDrive()
	isAlive = false
	flightEngine = nil
	birdModel = nil
	rootPart = nil
	-- Drop the persistent chase basis so the camera SNAPS to the new bird's pose on the first frame
	-- after a respawn/swap instead of visibly slewing in from the dead bird's last direction.
	cameraState.chaseDir = nil
	cameraState.camUpPrev = nil
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

local function reacquire()
	task.spawn(acquire)
end

-- Watch Possessed flips on every Model we own so swaps / auto-repossess re-acquire.
local function trackModel(model)
	if not model:IsA("Model") or attrConns[model] then return end
	if model:GetAttribute("OwnerUserId") ~= player.UserId then return end
	attrConns[model] = model:GetAttributeChangedSignal("Possessed"):Connect(reacquire)
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

-- One persistent flight loop: it drives whichever bird we currently hold and idles
-- when we hold none (between deaths / round resets).
renderConn = RunService.RenderStepped:Connect(onFlightStep)

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
end)
