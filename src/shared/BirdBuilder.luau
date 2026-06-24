--!nonstrict
--[[
	BirdBuilder — procedural construction + wing animation for bird Models.

	Pure construction and joint animation ONLY. No RunService loops, no Remotes,
	no requiring FlightPhysics. We MAY require GameConfig for colors/sizes.

	The flight system drives the model's PrimaryPart ("Body"). Everything else is
	welded to Body and Massless so the assembly behaves as one rigid body. Wings
	are attached with Motor6D joints whose Transform we animate every frame.

	Model structure produced by Build():
		Model (named teamName)
		├─ Body        (PrimaryPart, the only massed part, CanCollide true)
		├─ Head        (forward, welded, massless, no-collide)
		├─ Tail        (rear, welded, massless, no-collide)
		├─ LeftWing    (Motor6D "LeftWingJoint" Part0=Body, massless, no-collide)
		└─ RightWing   (Motor6D "RightWingJoint" Part0=Body, massless, no-collide)

	Animate with BirdBuilder.AnimateWings(model, isFlapping, isDiving, flapPhase, dt).
]]

local GameConfig = require(script.Parent.GameConfig)

local BirdBuilder = {}

--------------------------------------------------------------------------------
-- Tunables for the animation. Stored at the joint's C0 baseline so AnimateWings
-- can rotate relative to a neutral pose regardless of how it was built.
--------------------------------------------------------------------------------
local FLAP_AMPLITUDE = math.rad(45)   -- peak up/down sweep while flapping
local IDLE_AMPLITUDE = math.rad(8)    -- gentle glide bob
local IDLE_FREQUENCY = 1.5            -- radians/sec for idle bob (uses dt accumulator)
local DIVE_SWEEP = math.rad(60)       -- wings swept back/folded while diving
local SMOOTH = 10                     -- how quickly the wing eases toward its target

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Create a Part with sane defaults for a bird body segment.
local function makePart(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	return p
end

-- Weld `part` rigidly to `body` at the part's current CFrame.
local function weldTo(body, part)
	local weld = Instance.new("Weld")
	weld.Name = part.Name .. "Weld"
	weld.Part0 = body
	weld.Part1 = part
	-- C0/C1 chosen so the weld holds the part exactly where we positioned it.
	weld.C0 = body.CFrame:ToObjectSpace(part.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = body
	return weld
end

-- Linear blend of two CFrames' rotation (good enough for small wing angles).
local function approachCFrame(current, target, alpha)
	return current:Lerp(target, math.clamp(alpha, 0, 1))
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
-- BirdBuilder.Build(teamName, profile) -> Model
--   teamName : string used to name the Model and pick a palette ("Eagle"/"Crow").
--   profile  : a GameConfig.Profiles entry (.bodyRadius, .displayName, ...).
function BirdBuilder.Build(teamName, profile)
	profile = profile or {}
	local name = tostring(teamName or profile.displayName or "Bird")

	-- Decide species from the name/displayName (case-insensitive contains "eagle").
	local probe = string.lower(name .. " " .. tostring(profile.displayName or ""))
	local isEagle = string.find(probe, "eagle") ~= nil

	-- Scale everything off bodyRadius so eagles (4.5) are visibly bigger than crows (2.2).
	local r = tonumber(profile.bodyRadius) or (isEagle and 4.5 or 2.2)

	-- Palette: brown/gold eagle vs black/dark crow, each with its UI accent.
	local bodyColor, wingColor, accent, headColor
	if isEagle then
		bodyColor = Color3.fromRGB(96, 64, 38)        -- brown
		wingColor = Color3.fromRGB(74, 50, 30)        -- darker brown
		headColor = Color3.fromRGB(232, 226, 214)     -- pale eagle head
		accent = GameConfig.UI.eagleAccent            -- gold beak/talons
	else
		bodyColor = Color3.fromRGB(24, 24, 28)        -- near-black
		wingColor = Color3.fromRGB(16, 16, 20)        -- darker
		headColor = Color3.fromRGB(30, 30, 36)
		accent = GameConfig.UI.crowAccent             -- accent beak
	end

	local model = Instance.new("Model")
	model.Name = name

	-- BODY: the central, massed, primary part. Size roughly proportional to radius.
	local bodyLen = r * 2.2
	local bodyHeight = r * 1.1
	local bodyWidth = r * 1.0
	local body = makePart("Body", Vector3.new(bodyWidth, bodyHeight, bodyLen), bodyColor)
	body.Massless = false          -- the ONLY massed part
	body.CanCollide = true         -- Body may collide; appendages do not
	body.CanQuery = true
	body.CanTouch = true
	body.Shape = Enum.PartType.Block
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- HEAD: forward (-Z is LookVector forward in Roblox). Slightly raised.
	local head = makePart("Head", Vector3.new(r * 0.7, r * 0.7, r * 0.8), headColor)
	head.Shape = Enum.PartType.Ball
	head.CFrame = body.CFrame * CFrame.new(0, r * 0.25, -(bodyLen * 0.5 + r * 0.3))
	head.Parent = model
	weldTo(body, head)

	-- BEAK: small accent wedge in front of the head (forward = -Z).
	local beak = makePart("Beak", Vector3.new(r * 0.25, r * 0.3, r * 0.5), accent)
	beak.Material = Enum.Material.SmoothPlastic
	beak.CFrame = head.CFrame * CFrame.new(0, -r * 0.05, -(r * 0.4 + r * 0.25))
	beak.Parent = model
	weldTo(body, beak)

	-- TAIL: rear (+Z), flattened fan for pitch feel.
	local tail = makePart("Tail", Vector3.new(r * 1.2, r * 0.18, r * 1.1), wingColor)
	tail.CFrame = body.CFrame * CFrame.new(0, r * 0.1, bodyLen * 0.5 + r * 0.45)
	tail.Parent = model
	weldTo(body, tail)

	-- WINGS: long, thin, flat slabs to the sides. Attached via Motor6D so the
	-- joint can be rotated to flap. Wing span scales with radius (eagles broader).
	local wingSpan = r * 2.6
	local wingChord = bodyLen * 0.7   -- front-to-back depth
	local wingThick = r * 0.12
	local wingSize = Vector3.new(wingSpan, wingThick, wingChord)

	-- The joint pivots at the wing ROOT (inner edge near the body), so the wing
	-- sweeps up/down about the bird's forward (Z) axis like a real flap.
	local function buildWing(side) -- side: -1 left, +1 right
		local sideName = side < 0 and "LeftWing" or "RightWing"
		local wing = makePart(sideName, wingSize, wingColor)

		-- Root attachment point on the body side; wing extends outward from there.
		local rootOffset = CFrame.new(side * (bodyWidth * 0.5), r * 0.15, 0)
		-- Wing centroid sits half a span outward from the root.
		local wingLocal = rootOffset * CFrame.new(side * (wingSpan * 0.5), 0, 0)
		wing.CFrame = body.CFrame * wingLocal
		wing.Parent = model

		local motor = Instance.new("Motor6D")
		motor.Name = sideName .. "Joint"
		motor.Part0 = body
		motor.Part1 = wing
		-- C0: body-space frame located at the wing ROOT (pivot point).
		motor.C0 = rootOffset
		-- C1: wing-space frame so that, with Transform = identity, the wing rests
		-- at its neutral built position. C1 = wingFrame relative to root frame.
		motor.C1 = rootOffset:ToObjectSpace(wingLocal)
		motor.Transform = CFrame.new()
		motor.Parent = body

		-- Stamp the neutral so AnimateWings is independent of build details.
		motor:SetAttribute("FlapSign", side) -- +/- so wings flap symmetrically
		return motor
	end

	buildWing(-1)
	buildWing(1)

	-- A persistent idle phase accumulator lives on the model (no external state).
	model:SetAttribute("IdlePhase", 0)

	return model
end

--------------------------------------------------------------------------------
-- AnimateWings
--------------------------------------------------------------------------------
-- BirdBuilder.AnimateWings(model, isFlapping, isDiving, flapPhase, dt)
--   Rotates the wing Motor6D joints. Safe to call with missing joints.
--   - isFlapping : sine flap driven by flapPhase (radians, from FlightPhysics).
--   - isDiving   : hold wings swept back/folded.
--   - else       : gentle idle glide bob.
function BirdBuilder.AnimateWings(model, isFlapping, isDiving, flapPhase, dt)
	if not model then return end
	dt = tonumber(dt) or (1 / 60)
	flapPhase = tonumber(flapPhase) or 0

	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then return end

	-- Advance an internal idle phase (used only when not flapping/diving).
	local idle = (model:GetAttribute("IdlePhase") or 0) + dt * IDLE_FREQUENCY
	model:SetAttribute("IdlePhase", idle % (math.pi * 2))

	-- Compute the dihedral (up/down) angle for this frame, shared by both wings.
	local angle
	if isDiving then
		-- Swept/folded: wings angle downward and back for a tucked dive silhouette.
		angle = -DIVE_SWEEP
	elseif isFlapping then
		-- Sine flap about neutral; flapPhase comes from the physics engine.
		angle = math.sin(flapPhase) * FLAP_AMPLITUDE
	else
		-- Gentle idle glide: small slow bob.
		angle = math.sin(idle) * IDLE_AMPLITUDE
	end

	-- Apply symmetrically to each wing joint (rotate about local Z = forward axis,
	-- which sweeps the wing up/down). FlapSign mirrors left vs right.
	local function drive(jointName)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		local sign = motor:GetAttribute("FlapSign") or 1
		-- Rotate about the joint's Z axis so positive angle lifts both wing tips.
		local target = CFrame.Angles(0, 0, sign * angle)
		-- Ease toward the target for smooth motion (and graceful state changes).
		local alpha = math.clamp(dt * SMOOTH, 0, 1)
		motor.Transform = approachCFrame(motor.Transform, target, alpha)
	end

	drive("LeftWingJoint")
	drive("RightWingJoint")
end

return BirdBuilder
