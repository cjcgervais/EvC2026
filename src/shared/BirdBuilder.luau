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

-- Per-model idle-bob phase accumulator. Kept in a WEAK-KEYED Lua table (not a model
-- Attribute) because AnimateWings runs every frame: a SetAttribute every frame replicates
-- ~180×/s per AI crow to every client — pure network waste for a purely cosmetic local bob.
-- Weak keys let entries be collected automatically when a bird Model is destroyed.
local idlePhase = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Shared cosmetic-part defaults: massless, no-collide/query/touch, smooth. Every appendage
-- (feathers included) uses these so ONLY the Body ever participates in physics/collision.
local function applyBirdDefaults(p, name, size, color, material)
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

-- Create a Part with sane defaults for a bird body segment.
local function makePart(name, size, color, material)
	return applyBirdDefaults(Instance.new("Part"), name, size, color, material)
end

-- Create a WedgePart (tapered: full height at -Z, knife-edge at +Z) for streamlining and
-- brow ridges. Same cosmetic defaults as makePart.
local function makeWedge(name, size, color, material)
	return applyBirdDefaults(Instance.new("WedgePart"), name, size, color, material)
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

	-- Palette: brown/gold bald-eagle vs black/dark crow, each with its UI accent.
	-- Extra detail colors (eyes / talons / feather tips) push the silhouette toward the
	-- concept sheets while staying inside the same 5-part rig contract.
	local bodyColor, wingColor, accent, headColor, tailColor
	local eyeColor, talonColor, tipColor, eyeMaterial
	if isEagle then
		bodyColor = Color3.fromRGB(96, 64, 38)        -- brown
		wingColor = Color3.fromRGB(74, 50, 30)        -- darker brown
		headColor = Color3.fromRGB(236, 231, 221)     -- pale bald-eagle head
		tailColor = Color3.fromRGB(244, 244, 240)     -- bright white tail fan (bald-eagle signature)
		accent = GameConfig.UI.eagleAccent            -- gold beak/talons
		talonColor = Color3.fromRGB(224, 176, 48)     -- gold talons
		tipColor = Color3.fromRGB(30, 22, 14)         -- near-black primary-feather tips
		eyeColor = Color3.fromRGB(255, 214, 92)       -- glowing gold eye (sheet: "Glow Eyes")
		eyeMaterial = Enum.Material.Neon
	else
		bodyColor = Color3.fromRGB(24, 24, 28)        -- near-black
		wingColor = Color3.fromRGB(16, 16, 20)        -- darker
		headColor = Color3.fromRGB(30, 30, 36)
		tailColor = Color3.fromRGB(16, 16, 20)        -- crow tail: dark, same as wings
		accent = GameConfig.UI.crowAccent             -- accent beak
		talonColor = Color3.fromRGB(12, 12, 14)       -- dark talons
		tipColor = Color3.fromRGB(10, 10, 12)         -- slightly darker wing tips
		eyeColor = Color3.fromRGB(90, 20, 20)         -- faint dark-red eye glint
		eyeMaterial = Enum.Material.Glass
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

	-- CHEST: a rounded breast in front of the Body to lose the boxy front (cosmetic, welded).
	local chest = makePart("Chest", Vector3.new(bodyWidth * 1.04, bodyHeight * 0.95, bodyLen * 0.55), bodyColor)
	chest.Shape = Enum.PartType.Ball
	chest.CFrame = body.CFrame * CFrame.new(0, -bodyHeight * 0.06, -bodyLen * 0.26)
	chest.Parent = model
	weldTo(body, chest)

	-- RUMP: a wedge that tapers the dorsal line down into the tail (tall at the body, knife
	-- edge aft). Default WedgePart orientation already tapers -Z(tall)→+Z(thin) = front→rear.
	local rumpLen = bodyLen * 0.5
	local rump = makeWedge("Rump", Vector3.new(bodyWidth * 0.92, bodyHeight * 0.8, rumpLen), bodyColor)
	rump.CFrame = body.CFrame * CFrame.new(0, -bodyHeight * 0.1, bodyLen * 0.5 + rumpLen * 0.5 - bodyLen * 0.08)
	rump.Parent = model
	weldTo(body, rump)

	-- NECK: a short connector from the shoulders to the head. On the eagle it's pale (the
	-- bald-eagle white runs onto the neck); on the crow it stays body-dark.
	local neckColor = isEagle and headColor or bodyColor
	local neck = makePart("Neck", Vector3.new(bodyWidth * 0.6, bodyHeight * 0.55, bodyLen * 0.4), neckColor)
	neck.Shape = Enum.PartType.Ball
	neck.CFrame = body.CFrame * CFrame.new(0, bodyHeight * 0.12, -bodyLen * 0.5)
	neck.Parent = model
	weldTo(body, neck)

	-- HEAD: forward (-Z is LookVector forward in Roblox). Slightly raised. The eagle's pale
	-- head reads a touch larger than the crow's, matching the sheets' proportions.
	local headScale = isEagle and 0.78 or 0.62
	local head = makePart("Head", Vector3.new(r * headScale, r * headScale, r * (headScale + 0.1)), headColor)
	head.Shape = Enum.PartType.Ball
	head.CFrame = body.CFrame * CFrame.new(0, r * 0.25, -(bodyLen * 0.5 + r * 0.25))
	head.Parent = model
	weldTo(body, head)

	-- BEAK: a hooked raptor beak = a forward wedge plus a small down-curved tip (the raptor
	-- "hook"). The crow's is slimmer and straighter. Forward = -Z.
	local beakLen = isEagle and 0.55 or 0.50
	local beak = makePart("Beak", Vector3.new(r * 0.24, r * 0.30, r * beakLen), accent)
	beak.CFrame = head.CFrame * CFrame.new(0, -r * 0.04, -(r * headScale * 0.5 + r * beakLen * 0.5))
	beak.Parent = model
	weldTo(body, beak)
	local hook = makePart("BeakTip", Vector3.new(r * 0.18, r * 0.20, r * 0.20), accent)
	hook.CFrame = beak.CFrame * CFrame.new(0, -r * 0.12, -r * beakLen * 0.45) * CFrame.Angles(math.rad(-35), 0, 0)
	hook.Parent = model
	weldTo(body, hook)

	-- EYES: two small parts on the head. Neon on the eagle (the sheet's glow eyes); a faint
	-- glassy glint on the crow. Cosmetic, welded to the hub, no-collide/no-query.
	for _, s in ipairs({ -1, 1 }) do
		local eye = makePart("Eye", Vector3.new(r * 0.16, r * 0.16, r * 0.16), eyeColor, eyeMaterial)
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = head.CFrame * CFrame.new(s * r * headScale * 0.42, r * 0.10, -r * headScale * 0.32)
		eye.Parent = model
		weldTo(body, eye)
	end

	-- BROW RIDGE: a small wedge angled down over each eye — the raptor scowl. Pronounced on
	-- the eagle, subtle on the crow. Wedge tall face forward so the brow juts over the eye.
	local browDrop = isEagle and math.rad(28) or math.rad(16)
	for _, s in ipairs({ -1, 1 }) do
		local brow = makeWedge("Brow", Vector3.new(r * 0.26, r * 0.14, r * 0.34), headColor)
		brow.CFrame = head.CFrame
			* CFrame.new(s * r * headScale * 0.40, r * 0.24, -r * headScale * 0.30)
			* CFrame.Angles(browDrop, 0, s * math.rad(8))
		brow.Parent = model
		weldTo(body, brow)
	end

	-- TAIL: rear (+Z), a flattened, broad fan. Proportioned to a real raptor: ~⅔ a wing's chord wide and
	-- about as long front-to-back, thin top-to-bottom. White on the eagle (the bald-eagle tail fan), dark on
	-- the crow. Overlaps the body rear so there's no gap.
	local tailWidth = isEagle and 1.5 or 1.05
	local tailLen = isEagle and 1.05 or 1.25
	local tail = makePart("Tail", Vector3.new(r * tailWidth, r * 0.16, r * tailLen), tailColor)
	tail.CFrame = body.CFrame * CFrame.new(0, r * 0.08, bodyLen * 0.5 + r * 0.35)
	tail.Parent = model
	weldTo(body, tail)

	-- RECTRICES: individual tail feathers fanned about the vertical axis, laid just over the
	-- tail slab so the fan reads as separate feathers. Broad white set on the eagle, a
	-- narrower darker wedge on the crow.
	local rectrices = isEagle and 4 or 3
	local rectSpread = isEagle and math.rad(52) or math.rad(38)
	local rectLen = r * (isEagle and 1.15 or 1.3)
	local tailBase = tail.CFrame * CFrame.new(0, r * 0.02, -r * tailLen * 0.35)
	for i = 0, rectrices - 1 do
		local t = rectrices > 1 and (i / (rectrices - 1)) or 0.5
		local ang = (t - 0.5) * rectSpread
		local feather = makePart("TailFeather", Vector3.new(r * 0.24, r * 0.10, rectLen), tailColor)
		feather.CFrame = tailBase * CFrame.Angles(0, ang, 0) * CFrame.new(0, 0, rectLen * 0.5)
		feather.Parent = model
		weldTo(body, feather)
	end

	-- TALONS: a small pair of legs + gripping claws tucked under the rear belly (the sheets'
	-- "talon mechanism", static here — a moving talon-strike rig is the later Path-A upgrade).
	for _, s in ipairs({ -1, 1 }) do
		local leg = makePart("Leg", Vector3.new(r * 0.14, r * 0.34, r * 0.14), talonColor)
		leg.CFrame = body.CFrame * CFrame.new(s * r * 0.22, -r * 0.55, r * 0.05)
		leg.Parent = model
		weldTo(body, leg)
		local claw = makePart("Talon", Vector3.new(r * 0.20, r * 0.14, r * 0.34), talonColor)
		claw.CFrame = leg.CFrame * CFrame.new(0, -r * 0.22, -r * 0.10)
		claw.Parent = model
		weldTo(body, claw)
	end

	-- WINGS: the arm wing (broad inner slab) carries a covert feather row on top and a fan of
	-- individual PRIMARY feathers past its tip. The whole wing is ONE moving part (the inner
	-- slab, Part1 of the Motor6D) with everything welded to it, so it flaps as a rigid piece
	-- and AnimateWings still only drives the two named joints.
	local innerSpan  = r * 1.15
	local innerChord = isEagle and (bodyLen * 0.85) or (bodyLen * 0.60)
	local wingThick  = r * 0.09
	-- Primary flight feathers: eagle = broad, splayed slots ("fingers"); crow = fewer, longer,
	-- swept to a sharper point.
	local primaryCount = isEagle and 4 or 3
	local primaryLen   = isEagle and (r * 1.5) or (r * 1.85)
	local primaryChord = isEagle and (r * 0.5) or (r * 0.4)
	local primarySplay = isEagle and math.rad(9) or math.rad(4)   -- vertical slot spacing
	local baseSweep    = isEagle and math.rad(18) or math.rad(34) -- overall aft sweep

	-- The joint pivots at the wing ROOT (inner edge near the body), so the wing
	-- sweeps up/down about the bird's forward (Z) axis like a real flap.
	local function buildWing(side) -- side: -1 left, +1 right
		local sideName = side < 0 and "LeftWing" or "RightWing"
		-- Moving part = the broad INNER arm wing (kept named LeftWing/RightWing: the client's
		-- wingtip vortex trails and this Motor6D both key off that exact name).
		local wing = makePart(sideName, Vector3.new(innerSpan, wingThick, innerChord), wingColor)

		-- Root attachment point on the body side; inner wing extends outward from there.
		local rootOffset = CFrame.new(side * (bodyWidth * 0.5), r * 0.15, 0)
		-- Inner-wing centroid sits half its span outward from the root.
		local wingLocal = rootOffset * CFrame.new(side * (innerSpan * 0.5), 0, 0)
		wing.CFrame = body.CFrame * wingLocal
		wing.Parent = model

		-- COVERTS: a short shoulder-feather row along the leading edge, slightly raised & lighter,
		-- to break up the flat top of the arm wing. Welded to the wing so they flap with it.
		local covertColor = wingColor:Lerp(Color3.new(1, 1, 1), isEagle and 0.14 or 0.05)
		for c = 0, 1 do
			local cov = makePart(sideName .. "Covert",
				Vector3.new(innerSpan * 0.7, wingThick * 0.7, innerChord * 0.34), covertColor)
			cov.CFrame = wing.CFrame * CFrame.new(side * innerSpan * 0.02, wingThick * 0.6, -innerChord * (0.28 - c * 0.16))
			cov.Parent = model
			weldTo(wing, cov)
		end

		-- PRIMARIES: individual flight feathers fanned out past the arm-wing tip. On the eagle
		-- they splay into the slotted "fingers"; on the crow they sweep to a sharper point.
		local tipAnchor = wing.CFrame * CFrame.new(side * (innerSpan * 0.5), wingThick * 0.2, 0)
		for i = 0, primaryCount - 1 do
			local t = primaryCount > 1 and (i / (primaryCount - 1)) or 0.5   -- 0 = leading, 1 = trailing
			local chordPos = (t - 0.5) * innerChord * 0.6                     -- spread across the chord
			local sweep = baseSweep + t * math.rad(12)                        -- rear fingers sweep more
			local splay = (i - (primaryCount - 1) / 2) * primarySplay         -- vertical slot spacing
			local len = primaryLen * (1 - 0.10 * i)                           -- outer fingers a touch shorter
			local feather = makePart(sideName .. "Primary",
				Vector3.new(len, wingThick * 0.8, primaryChord), tipColor)
			feather.CFrame = tipAnchor
				* CFrame.new(0, 0, chordPos)
				* CFrame.Angles(0, -side * sweep, side * splay)
				* CFrame.new(side * len * 0.5, 0, 0)
			feather.Parent = model
			weldTo(wing, feather)
		end

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

	-- Advance an internal idle phase (used only when not flapping/diving). Stored in a
	-- weak Lua table keyed by the model — never replicated (see idlePhase declaration).
	local idle = ((idlePhase[model] or 0) + dt * IDLE_FREQUENCY) % (math.pi * 2)
	idlePhase[model] = idle

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
