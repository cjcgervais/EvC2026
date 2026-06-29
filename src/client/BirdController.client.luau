--!nonstrict
--[[
	BirdController — Client-side flight, input, camera, and FX handler.

	Runs the FlightPhysics engine locally for zero-latency input response, then
	writes the result onto its standalone bird Model's PrimaryPart ("Body") — CFrame +
	assembly velocity — which the server has already given this client network ownership
	of. There is NO Roblox Character; the bird is found in Workspace.Birds by attribute.

	Control scheme (see GameConfig + project brief):
	  W / S        -> PITCH  (W nose-down to dive/accelerate, S nose-up to climb)
	  A / D        -> ROLL   (banking; turns are made by banking)
	  Q / E        -> YAW    (head-led)
	  Left Shift   -> FLAP   (hold, thrust)
	  Left Ctrl    -> DIVE   (hold, dive intent)
	  Mouse (move) -> STEER the nose: cursor offset from screen center = analog pitch/roll,
	                  SUMMED with W/S/A/D. Suspended while free-look (Space) is held.
	                  Tunables in GameConfig.Controls.
	  Spacebar     -> FREE-LOOK camera (hold): orbit the camera freely around the
	                  bird while the bird HOLDS its current flight input.
	  Mouse1       -> attack (AttackRequest)
	  1-4          -> SwapCrow(index)
	  F            -> toggle formation tight/loose (SetFormation)
	  R            -> manual respawn / reset (Respawn)
]]

--------------------------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------------------------
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
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
-- REMOTES (created by the server)
--------------------------------------------------------------------------------
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned = Remotes:WaitForChild("TeamAssigned")
local AttackRequest = Remotes:WaitForChild("AttackRequest")
local SwapCrow     = Remotes:WaitForChild("SwapCrow")
local SetFormation = Remotes:WaitForChild("SetFormation")
local Respawn      = Remotes:WaitForChild("Respawn")
local GetThermals  = Remotes:WaitForChild("GetThermals")

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

-- Smoothed camera state.
local cameraState = {
	currentDistance = CAM.baseDistance,
}

-- Free-look (Spacebar) — LAW: hold Space to look ALL AROUND while flying. The camera
-- orbits the bird freely and MUST NEVER alter the flight input (it writes only freeLook.*,
-- never inputState.*; flight controls are keyboard-only and `isDiving` reads the bird's nose,
-- not the camera — keep it that way). yaw accumulates unbounded -> full 360° horizontal; pitch
-- is clamped just short of the poles so you can look straight up/down/behind without gimbal flip.
local FREE_LOOK_PITCH_LIMIT = 1.54 -- radians (~88°): look nearly straight up/down
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
	[Enum.KeyCode.Q] = { axis = "yaw",   value = -1 },
	[Enum.KeyCode.E] = { axis = "yaw",   value = 1 },
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
		inputState.flap = true
		return
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		inputState.dive = true
		return
	elseif input.KeyCode == Enum.KeyCode.Space then
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

	-- Attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		AttackRequest:FireServer()
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
	elseif input.KeyCode == Enum.KeyCode.Space then
		setFreeLook(false)
	end
end)

-- Mouse delta routing: when free-looking (Space) it orbits the camera; otherwise it deflects
-- the steering virtual stick. Never reads absolute cursor position, so neutral is always well
-- defined (stick = 0). Both modes keep the mouse LockCenter'd (set in onFlightStep).
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	if freeLook.active then
		local s = CAM.freeLookSensitivity * 0.01
		freeLook.yaw   = freeLook.yaw   - input.Delta.X * s
		freeLook.pitch = math.clamp(freeLook.pitch - input.Delta.Y * s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT)
	else
		local C = GameConfig.Controls
		if C and C.mouseSteer then
			local s = (C.mouseSensitivity or 1) * 0.004
			steer.x = math.clamp(steer.x + input.Delta.X * s, -1, 1)
			steer.y = math.clamp(steer.y + input.Delta.Y * s, -1, 1)
		end
	end
end)

-- Arrow keys also orbit the free-look camera (alternative to the mouse).
RunService.RenderStepped:Connect(function(dt)
	if not freeLook.active then return end
	local s = CAM.freeLookSensitivity * 2.5 * dt
	if UserInputService:IsKeyDown(Enum.KeyCode.Left)  then freeLook.yaw   = freeLook.yaw   + s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then freeLook.yaw   = freeLook.yaw   - s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Up)    then freeLook.pitch = math.clamp(freeLook.pitch + s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down)  then freeLook.pitch = math.clamp(freeLook.pitch - s, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT) end
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

	-- Distance grows with speed for a sense of velocity.
	local targetDistance = CAM.baseDistance + speed * CAM.speedDistanceFactor
	cameraState.currentDistance = cameraState.currentDistance
		+ (targetDistance - cameraState.currentDistance) * 0.1

	local dist = cameraState.currentDistance
	local backward = -cf.LookVector
	local up       = cf.UpVector

	-- Base chase offset: behind and slightly above the bird.
	local cameraOffset = (backward * dist) + (up * (dist * 0.25))

	-- Velocity trail: let the camera drift behind the direction of motion. The
	-- original had a broken `local velDot = velDot = ...` self-reference — fixed.
	if speed > 10 then
		local velNorm = velocity.Unit
		local velDot  = backward:Dot(velNorm)
		cameraOffset = cameraOffset + (velNorm * velDot * speed * 0.05)
	end

	-- FREE-LOOK: orbit the offset around the bird (yaw about world up, pitch about
	-- the bird's right axis) WITHOUT touching flight input.
	if freeLook.active then
		local orbit = CFrame.Angles(0, freeLook.yaw, 0)
			* CFrame.fromAxisAngle(cf.RightVector, freeLook.pitch)
		cameraOffset = orbit:VectorToWorldSpace(cameraOffset)
	end

	local camPos  = position + cameraOffset
	local targetCF = CFrame.new(camPos, position)

	-- Bank tilt: roll the camera slightly with the bird (skip while free-looking).
	if not freeLook.active then
		local rightVec  = cf.RightVector
		local bankAngle = math.asin(math.clamp(rightVec.Y, -1, 1))
		targetCF = targetCF * CFrame.Angles(0, 0, bankAngle * CAM.bankTiltFactor)
	end

	-- Frame-rate independent smoothing toward the target.
	local alpha = math.clamp(1 - math.exp(-CAM.followSmoothing * 60 * dt), 0, 1)
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
	camera.FieldOfView = math.clamp(
		camera.FieldOfView + (targetFOV - camera.FieldOfView) * math.clamp(dt * 6, 0, 1),
		50, 110
	)
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
-- MOUSE STEERING — the bird's nose chases the cursor: offset from screen center maps to
-- analog pitch/roll (deadzone + expo curve), returned in [-1,1] and SUMMED with the keyboard
-- each frame in onFlightStep. Suspended while free-look (Space) holds the mouse for the camera.
--------------------------------------------------------------------------------
local function computeMouseSteer()
	local C = GameConfig.Controls
	if not (C and C.mouseSteer) or freeLook.active then return 0, 0 end
	local expo = C.mouseExpo or 1
	local function shape(v)
		local mag = math.clamp(math.abs(v), 0, 1) ^ expo
		return (v < 0 and -mag) or mag
	end
	-- stick RIGHT (steer.x>0) banks RIGHT (roll -1 by the keyBindings convention); stick UP
	-- (mouse moved up -> steer.y<0) pitches the nose UP (pitch +1) unless invertPitch.
	local roll  = -shape(steer.x)
	local pitch = -shape(steer.y)
	if C.invertPitch then pitch = -pitch end
	return pitch, roll
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

	-- 1b. Mouse-steer: keep the mouse captured (LockCenter) so movement reads as stick deltas
	-- and the cursor never leaves the window, then spring the stick back toward center.
	local C = GameConfig.Controls
	if C and C.mouseSteer then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		-- Spring the stick back to center, SPLIT by axis: roll self-levels (anti-spiral) while
		-- pitch barely returns so a held climb/dive persists without continuous mouse feed.
		local kr = math.clamp((C.mouseReturnRoll  or 0) * dt, 0, 1)
		local kp = math.clamp((C.mouseReturnPitch or 0) * dt, 0, 1)
		steer.x = steer.x - steer.x * kr
		steer.y = steer.y - steer.y * kp
	end

	-- 1c. Build the flight axes from BOTH input sources: analog mouse-steer + keyboard,
	-- summed and clamped. yaw stays keyboard-only (Q/E). Mouse contributes 0 while free-looking.
	local mPitch, mRoll = computeMouseSteer()
	inputState.pitch = math.clamp(kb.pitch + mPitch, -1, 1)
	inputState.roll  = math.clamp(kb.roll  + mRoll,  -1, 1)
	inputState.yaw   = kb.yaw

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

	-- 4. Wing animation.
	if birdModel then
		BirdBuilder.AnimateWings(
			birdModel,
			flightEngine.isFlapping,
			flightEngine.isDiving,
			flightEngine.flapPhase,
			dt
		)
	end

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
	steer.x, steer.y = 0, 0
	inputState.pitch, inputState.roll, inputState.yaw = 0, 0, 0
	inputState.flap, inputState.dive = false, false
end

local function teardownDrive()
	isAlive = false
	flightEngine = nil
	birdModel = nil
	rootPart = nil
	-- Release the mouse between lives; onFlightStep re-locks it once we're driving again.
	if not freeLook.active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
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
