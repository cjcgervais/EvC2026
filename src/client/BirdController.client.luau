--!nonstrict
--[[
	BirdController — Client-side flight, input, camera, and FX handler.

	Runs the FlightPhysics engine locally for zero-latency input response, then
	writes the result onto the character's HumanoidRootPart (CFrame + assembly
	velocity) which the server has already given this client network ownership of.

	Control scheme (see GameConfig + project brief):
	  W / S        -> PITCH  (W nose-down to dive/accelerate, S nose-up to climb)
	  A / D        -> ROLL   (banking; turns are made by banking)
	  Q / E        -> YAW    (head-led)
	  Left Shift   -> FLAP   (hold, thrust)
	  Left Ctrl    -> DIVE   (hold, dive intent)
	  Spacebar     -> FREE-LOOK camera (hold): orbit the camera freely around the
	                  bird while the bird HOLDS its current flight input.
	  Mouse1       -> attack (AttackRequest)
	  1-4          -> SwapCrow(index)
	  F            -> toggle formation tight/loose (SetFormation)
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

local CAM = GameConfig.Camera

--------------------------------------------------------------------------------
-- REMOTES (created by the server)
--------------------------------------------------------------------------------
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned = Remotes:WaitForChild("TeamAssigned")
local AttackRequest = Remotes:WaitForChild("AttackRequest")
local SwapCrow     = Remotes:WaitForChild("SwapCrow")
local SetFormation = Remotes:WaitForChild("SetFormation")
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

-- Live flight input the physics engine consumes every frame.
local inputState = {
	pitch = 0,
	roll  = 0,
	yaw   = 0,
	flap  = false,
	dive  = false,
}

-- Smoothed camera state.
local cameraState = {
	currentDistance = CAM.baseDistance,
}

-- Free-look (Spacebar): when active, the camera orbits the bird without altering
-- the flight input. We accumulate yaw/pitch offsets from mouse delta.
local freeLook = {
	active = false,
	yaw    = 0, -- radians, horizontal orbit
	pitch  = 0, -- radians, vertical orbit (clamped)
}

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
	[Enum.KeyCode.W] = { axis = "pitch", value = 1 },
	[Enum.KeyCode.S] = { axis = "pitch", value = -1 },
	[Enum.KeyCode.A] = { axis = "roll",  value = -1 },
	[Enum.KeyCode.D] = { axis = "roll",  value = 1 },
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

	-- Flight axes
	local binding = keyBindings[input.KeyCode]
	if binding then
		inputState[binding.axis] = binding.value
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
		if inputState[binding.axis] == binding.value then
			inputState[binding.axis] = 0
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

-- Mouse delta feeds the free-look orbit only (flight input is untouched).
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not freeLook.active then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local s = CAM.freeLookSensitivity * 0.01
		freeLook.yaw   = freeLook.yaw   - input.Delta.X * s
		freeLook.pitch = math.clamp(freeLook.pitch - input.Delta.Y * s, -1.3, 1.3)
	end
end)

-- Arrow keys also orbit the free-look camera (alternative to the mouse).
RunService.RenderStepped:Connect(function(dt)
	if not freeLook.active then return end
	local s = CAM.freeLookSensitivity * 2.5 * dt
	if UserInputService:IsKeyDown(Enum.KeyCode.Left)  then freeLook.yaw   = freeLook.yaw   + s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then freeLook.yaw   = freeLook.yaw   - s end
	if UserInputService:IsKeyDown(Enum.KeyCode.Up)    then freeLook.pitch = math.clamp(freeLook.pitch + s, -1.3, 1.3) end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down)  then freeLook.pitch = math.clamp(freeLook.pitch - s, -1.3, 1.3) end
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
-- MAIN FLIGHT STEP
--------------------------------------------------------------------------------
local function onFlightStep(dt)
	if not isAlive or not flightEngine or not rootPart or not rootPart.Parent then
		isAlive = false
		return
	end

	-- 1. Thermals -> engine.
	flightEngine:SetThermalForce(computeThermalForce(rootPart.Position))
	flightEngine:SetWind(GameConfig.Flight.WIND_BASE)

	-- 2. Step the simulation with the live input.
	flightEngine:Update(dt, inputState)

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
-- CHARACTER SETUP
--------------------------------------------------------------------------------
local function onCharacterAdded(character)
	if not character then return end

	-- Tear down any prior loop and reset transient state.
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	isAlive = false
	flightEngine = nil
	birdModel = nil
	rootPart = nil
	inputState.pitch, inputState.roll, inputState.yaw = 0, 0, 0
	inputState.flap, inputState.dive = false, false
	setFreeLook(false)

	-- Wait for the server-built character pieces.
	local hrp = character:WaitForChild("HumanoidRootPart", 20)
	local humanoid = character:WaitForChild("Humanoid", 20)
	if not hrp or not humanoid then return end
	rootPart = hrp

	-- Wait for team assignment: TeamAssigned fires (teamName, profile).
	local teamName, profile = TeamAssigned.OnClientEvent:Wait()
	currentTeam = teamName
	currentProfile = profile
	if not currentProfile then return end

	-- Find the bird Model the server welded into the character.
	birdModel = character:FindFirstChildWhichIsA("Model")

	-- Disable default Roblox locomotion; the flight engine drives the body.
	humanoid.PlatformStand = true

	-- Spin up the local flight engine seeded from the spawn CFrame.
	flightEngine = FlightPhysics.new(currentProfile, rootPart.Position)
	flightEngine.orientation = rootPart.CFrame

	isAlive = true
	renderConn = RunService.RenderStepped:Connect(onFlightStep)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

player.CharacterRemoving:Connect(function()
	isAlive = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	setFreeLook(false)
end)
