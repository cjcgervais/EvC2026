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
-- DIVE POSE. A bald eagle stooping is a broad-winged glide-dive (NOT a peregrine teardrop tuck):
-- the "hand"/primaries sweep AFT into a swept-back arrowhead while the tips drop into a shallow
-- anhedral, so from above each wing reads as a swept V and from the front the pair makes a shallow
-- ∧ (tips-down tent; a dihedral ∨ would be tips-up). Verified deep-research ranges: ~30–45° aft
-- sweep, ~10–20° anhedral. These are cosmetic only
-- (Motor6D.Transform, which never feeds FlightPhysics), so they are free to be art-directed.
-- STAGED DIVE FOLD (S34 sandbox): instead of one binary dive pose, the wings UNFOLD through smooth
-- levels as the nose drops — first the primaries sweep aft a little (shallow dive), then deepen into the
-- full swept-back arrowhead stoop with a cupped anhedral + a subtle blade tilt (committed vertical
-- stoop). Driven by the body's own continuous nose-down depth, smoothstepped through 3 keyframes.
local DIVE_SWEEP_L1  = math.rad(24)   -- L1 (shallow): the hand/primaries begin to sweep aft
local DIVE_SWEEP_L2  = math.rad(54)   -- L2 (full stoop): dramatic swept-back arrowhead (the "sweet" line)
local DIVE_ANHED_L1  = math.rad(10)   -- L1: tips begin to dip
local DIVE_ANHED_L2  = math.rad(26)   -- L2: full cupped anhedral (tips down, toward prey)
local DIVE_BLADE     = math.rad(9)    -- L2 only: subtle leading-edge-down blade tilt = a bladed diving look
local DIVE_ONSET_Y   = -0.12          -- body LookVector.Y where the fold begins (level → shallow)
local DIVE_FULL_Y    = -0.92          -- LookVector.Y where it reaches the full committed stoop
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
	p.CastShadow = false   -- ~30 moving cosmetic parts/bird: skip the per-frame shadow pass (perf)
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

-- Smoothstep (Hermite) — eased 0→1 as x runs edge0→edge1 (edge0 may be > edge1 for a decreasing input).
local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Smoothly interpolate through THREE keyframes as x runs 0 → 0.5 → 1 — a "smooth step between multiple
-- levels of unfolding": k0 at rest, k1 at the half-dive, k2 at the full stoop.
local function staged3(x, k0, k1, k2)
	if x <= 0.5 then
		return k0 + (k1 - k0) * smoothstep(0, 0.5, x)
	end
	return k1 + (k2 - k1) * smoothstep(0.5, 1, x)
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
	local eyeColor, talonColor, clawColor, tipColor, eyeMaterial
	local pupilColor, pupilMaterial, pupilSize
	if isEagle then
		-- Adult bald eagle: DARK brown body/wings for maximum contrast with the white head/tail
		-- (that contrast is the whole silhouette). Feet yellow, claws black, iris pale yellow.
		bodyColor = Color3.fromRGB(74, 52, 34)        -- dark brown
		wingColor = Color3.fromRGB(54, 38, 26)        -- darker still (wings darker than body)
		headColor = Color3.fromRGB(244, 244, 241)     -- bright white head/neck
		tailColor = Color3.fromRGB(244, 244, 240)     -- bright white tail fan
		accent = GameConfig.UI.eagleAccent            -- yellow hooked beak
		talonColor = Color3.fromRGB(240, 196, 44)     -- bright yellow feet/legs
		clawColor = Color3.fromRGB(20, 18, 16)        -- black claws (real eagle claws are black)
		tipColor = Color3.fromRGB(30, 22, 14)         -- near-black primary-feather tips
		eyeColor = Color3.fromRGB(238, 224, 150)      -- pale-yellow iris (real eagle eye, not sci-fi gold)
		eyeMaterial = Enum.Material.Neon              -- soft stylized glow
		pupilColor = Color3.fromRGB(12, 12, 12)       -- black pupil (makes the eye read as alive)
		pupilMaterial = Enum.Material.SmoothPlastic
		pupilSize = r * 0.09
	else
		-- Crow: glossy black with a cool blue/purple cast (structural iridescence), faked with a
		-- cool tint + a purple sheen on the coverts + a bright catchlight in a dark eye.
		bodyColor = Color3.fromRGB(20, 20, 26)        -- cool-cast near-black
		wingColor = Color3.fromRGB(14, 14, 20)        -- darker
		headColor = Color3.fromRGB(24, 24, 30)
		tailColor = Color3.fromRGB(14, 14, 20)        -- dark, same as wings
		accent = GameConfig.UI.crowAccent             -- accent beak
		talonColor = Color3.fromRGB(14, 14, 16)       -- dark feet
		clawColor = Color3.fromRGB(8, 8, 10)          -- near-black claws
		tipColor = Color3.fromRGB(10, 10, 12)         -- slightly darker wing tips
		eyeColor = Color3.fromRGB(14, 14, 16)         -- dark eye
		eyeMaterial = Enum.Material.SmoothPlastic     -- (Glass was misuse on a tiny opaque ball)
		pupilColor = Color3.fromRGB(232, 232, 236)    -- bright catchlight glint
		pupilMaterial = Enum.Material.Neon
		pupilSize = r * 0.05
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
	body.CastShadow = true         -- one grounding shadow per bird (appendages stay shadowless)
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

	-- RUMP: a long, low wedge that tapers the dorsal AND belly lines down into the tail (tall at
	-- the body, knife edge aft) for a sleek streamlined rear. Default WedgePart orientation
	-- already tapers -Z(tall)→+Z(thin) = front→rear.
	local rumpLen = bodyLen * 0.6
	local rump = makeWedge("Rump", Vector3.new(bodyWidth * 0.9, bodyHeight * 0.72, rumpLen), bodyColor)
	-- WedgePart tall face defaults to +Z / knife edge to -Z; yaw 180° so the tall face meets the
	-- body and it knife-edges into the tail (verified via the wedge-orientation red-team audit).
	rump.CFrame = body.CFrame
		* CFrame.new(0, -bodyHeight * 0.12, bodyLen * 0.5 + rumpLen * 0.5 - bodyLen * 0.1)
		* CFrame.Angles(0, math.rad(180), 0)
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

	-- BEAK: a deep, down-curved raptor bill. Per raptor-bill research the culmen (top ridge) runs
	-- nearly straight over the basal two-thirds then curves down hard into an overhanging hook, and
	-- the bill is a DEEP "hatchet" (base depth ~0.65× its length) — not a slender cone. Built as a
	-- short chain of tapering segments hung BELOW a culmen line, so the top edge stays a smooth
	-- ridge while the belly deepens; a steep near-vertical tip plus a shorter lower mandible give
	-- the classic overhang. Forward = -Z. Duplicate "Beak" sibling names are safe.
	-- Each spec = {lenR, depthR, widthR, pitchAfterDeg}; pitchAfter tilts the culmen down for the NEXT link.
	local beakSpec = isEagle and {
		{ 0.26, 0.40, 0.30,  7 },   -- base over the cere: deep, culmen almost flat
		{ 0.20, 0.34, 0.25, 15 },   -- basal ridge: gentle convex
		{ 0.16, 0.26, 0.19, 30 },   -- distal third: the culmen begins to drop
	} or {
		{ 0.22, 0.26, 0.19, 12 },   -- crow: slimmer, straighter bill
		{ 0.18, 0.19, 0.14, 22 },
	}
	local culmen = head.CFrame * CFrame.new(0, r * 0.07, -r * headScale * 0.5)   -- top-front of the face
	for _, seg in ipairs(beakSpec) do
		local len, dep, wid = r * seg[1], r * seg[2], r * seg[3]
		culmen = culmen * CFrame.new(0, 0, -len * 0.5)
		local part = makePart("Beak", Vector3.new(wid, dep, len * 1.04), accent)
		part.CFrame = culmen * CFrame.new(0, -dep * 0.5, 0)   -- hang below the culmen (top) line
		part.Parent = model
		weldTo(body, part)
		culmen = culmen * CFrame.new(0, 0, -len * 0.5) * CFrame.Angles(-math.rad(seg[4]), 0, 0)
	end
	-- HOOK: a steep, near-vertical down-curved tip (points ~80° below horizontal) overhanging the bill.
	local hookLen = r * (isEagle and 0.32 or 0.22)
	local hookDep = r * (isEagle and 0.22 or 0.14)
	culmen = culmen * CFrame.Angles(-math.rad(isEagle and 30 or 22), 0, 0)
	local hook = makePart("BeakTip", Vector3.new(r * (isEagle and 0.15 or 0.10), hookDep, hookLen), accent)
	hook.CFrame = culmen * CFrame.new(0, -hookDep * 0.35, -hookLen * 0.5)
	hook.Parent = model
	weldTo(body, hook)
	-- LOWER MANDIBLE: a shorter, shallower bill floor. Ends short of the hook so the hook overhangs it.
	local lowerLen = r * (isEagle and 0.46 or 0.40)
	local lower = makePart("BeakLower", Vector3.new(r * (isEagle and 0.22 or 0.16), r * 0.15, lowerLen), accent)
	lower.CFrame = head.CFrame * CFrame.new(0, -r * 0.17, -(r * headScale * 0.5 + lowerLen * 0.5))
	lower.Parent = model
	weldTo(body, lower)

	-- EYES: two small parts on the head. Neon on the eagle (the sheet's glow eyes); a faint
	-- glassy glint on the crow. Cosmetic, welded to the hub, no-collide/no-query.
	for _, s in ipairs({ -1, 1 }) do
		local eye = makePart("Eye", Vector3.new(r * 0.16, r * 0.16, r * 0.16), eyeColor, eyeMaterial)
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = head.CFrame * CFrame.new(s * r * headScale * 0.42, r * 0.10, -r * headScale * 0.32)
		eye.Parent = model
		weldTo(body, eye)
		-- Pupil (eagle) / catchlight (crow): a tiny ball on the eye's forward face — the single
		-- cheapest thing that makes an eye read as alive rather than a flat bead.
		local pupil = makePart("Pupil", Vector3.new(pupilSize, pupilSize, pupilSize), pupilColor, pupilMaterial)
		pupil.Shape = Enum.PartType.Ball
		pupil.CFrame = eye.CFrame * CFrame.new(s * r * 0.02, 0, -r * 0.07)
		pupil.Parent = model
		weldTo(body, pupil)
	end

	-- BROW RIDGE: a small wedge angled down over each eye — the raptor scowl. Pronounced on
	-- the eagle, subtle on the crow. Wedge tall face forward so the brow juts over the eye.
	local browDrop = isEagle and math.rad(28) or math.rad(16)
	for _, s in ipairs({ -1, 1 }) do
		local brow = makeWedge("Brow", Vector3.new(r * 0.26, r * 0.14, r * 0.34), headColor)
		-- WedgePart tall face defaults to +Z; yaw 180° so it fronts the eye, then browDrop tilts
		-- it forward-and-down into a scowl (verified via the wedge-orientation red-team audit).
		brow.CFrame = head.CFrame
			* CFrame.new(s * r * headScale * 0.40, r * 0.24, -r * headScale * 0.30)
			* CFrame.Angles(0, math.rad(180), 0)
			* CFrame.Angles(browDrop, 0, -s * math.rad(8))
		brow.Parent = model
		weldTo(body, brow)
	end

	-- TAIL: rear (+Z), a flattened, broad fan. Proportioned to a real raptor: ~⅔ a wing's chord wide and
	-- about as long front-to-back, thin top-to-bottom. White on the eagle (the bald-eagle tail fan), dark on
	-- the crow. Overlaps the body rear so there's no gap.
	local tailWidth = isEagle and 1.7 or 1.05   -- eagle: broad slab under a fuller fan
	local tailLen = isEagle and 1.05 or 1.25
	local tail = makePart("Tail", Vector3.new(r * tailWidth, r * 0.16, r * tailLen), tailColor)
	tail.CFrame = body.CFrame * CFrame.new(0, r * 0.08, bodyLen * 0.5 + r * 0.35)
	tail.Parent = model
	weldTo(body, tail)

	-- RECTRICES: individual tail feathers fanned about the vertical axis, laid just over the tail
	-- slab so the fan reads as separate feathers. Research: the bald-eagle tail has 12 rectrices and
	-- spreads into a BROAD ROUNDED-WEDGE (centre longest, a gentle convex trailing edge — not a deep
	-- diamond, not square). A wider count + spread + overlapping feather widths make it read as a
	-- full fan rather than a few spokes. The crow's is a shorter, more even, rounded/square fan.
	local rectrices = isEagle and 9 or 5
	local rectSpread = isEagle and math.rad(78) or math.rad(46)   -- fuller fan spread
	local rectLen = r * (isEagle and 1.25 or 1.3)
	local rectWidth = r * (isEagle and 0.30 or 0.26)   -- wide enough to overlap into a solid fan
	local wedgeBias = isEagle and 0.5 or 0.2    -- gentle: rounded-wedge outer edge (not a sharp diamond)
	local tailBase = tail.CFrame * CFrame.new(0, r * 0.10, -r * tailLen * 0.35)   -- lifted to sit ON the tail slab
	for i = 0, rectrices - 1 do
		local t = rectrices > 1 and (i / (rectrices - 1)) or 0.5
		local ang = (t - 0.5) * rectSpread
		local flen = rectLen * (1 - math.abs(t - 0.5) * wedgeBias)   -- centre longest => wedge
		local feather = makePart("TailFeather", Vector3.new(rectWidth, r * 0.10, flen), tailColor)
		feather.CFrame = tailBase * CFrame.Angles(0, ang, 0) * CFrame.new(0, 0, flen * 0.5)
		feather.Parent = model
		weldTo(body, feather)
	end

	-- LEGS + TALONS: a longer two-segment leg (feathered "trouser" thigh + bare thick tarsus) ending
	-- in a foot of three splayed forward toes plus a rear hallux. Held in a ready, slightly-forward
	-- tuck with the talons curled — the length is deliberate so a future Path-A rig can swing the legs
	-- DOWN-AND-FORWARD and splay the talons for a strike (research: eagles drop the legs ahead of the
	-- breast, feet leading, toes splayed). Static + welded here; no joints yet. Forward = -Z.
	local hipY = -bodyHeight * 0.28
	local thighLen = r * 0.32
	local tarsusLen = r * 0.38
	local toeLen = r * 0.30
	-- The leg is now a Path-A RIG (S39 talon-catch anim): two Motor6Ds per side (HIP swings the whole leg
	-- down-and-forward for the reach; FOOT pitches the toes open→shut for splay/clench). At Transform = I
	-- the rest silhouette is byte-identical to the old static weld — BirdBuilder.AnimateTalons drives it,
	-- and nothing ever drives a crow's leg motors, so the crow (and any un-animated eagle) looks unchanged.
	for _, s in ipairs({ -1, 1 }) do
		local sideName = s < 0 and "Left" or "Right"
		-- HIP pivot: the body-space attach point (before the forward lean). The thigh becomes Part1 of the
		-- HIP joint (no longer welded to the body), so the whole leg swings about this point.
		local hipPivot = body.CFrame * CFrame.new(s * r * 0.22, hipY, -r * 0.04)
		-- THIGH: feathered upper leg (body colour), leaned slightly forward so the foot sits ahead of the vent.
		local thigh = makePart("Leg", Vector3.new(r * 0.22, thighLen, r * 0.22), bodyColor)
		thigh.CFrame = hipPivot
			* CFrame.Angles(math.rad(12), 0, 0)              -- lean the whole leg slightly forward
			* CFrame.new(0, -thighLen * 0.5, 0)
		thigh.Parent = model
		-- TARSUS: bare, thick, near-vertical shank (yellow on the eagle). Welded to the THIGH so it rides
		-- the hip swing rigidly (was welded to the body).
		local tarsus = makePart("Tarsus", Vector3.new(r * 0.16, tarsusLen, r * 0.16), talonColor)
		tarsus.CFrame = thigh.CFrame
			* CFrame.new(0, -thighLen * 0.5, 0)
			* CFrame.Angles(math.rad(-5), 0, 0)              -- straighten toward vertical below the "knee"
			* CFrame.new(0, -tarsusLen * 0.5, 0)
		tarsus.Parent = model
		weldTo(thigh, tarsus)
		-- FOOT hub: a small block at the ankle — the moving root of the toes (Part1 of the FOOT joint).
		-- Pitching it back "opens the hand" (toes flare forward); pitching down "snaps the grab" shut.
		local footHub = tarsus.CFrame * CFrame.new(0, -tarsusLen * 0.5, 0)
		local foot = makePart("Foot", Vector3.new(r * 0.20, r * 0.12, r * 0.26), talonColor)
		foot.CFrame = footHub
		foot.Parent = model
		-- THREE forward toes splayed across the foot, each now ARTICULATED into a proximal segment + a
		-- distal claw (S39b: a REAL grasp — the toe folds at a mid-knuckle, not a rigid paddle). Each toe
		-- box (old single length-toeLen box along -Z after the -45° curl) is SPLIT into two collinear
		-- boxes tiling the SAME volume: proximal 55% + distal 45%, laid end-to-end along the built axis,
		-- same r*0.09 cross-section. Their union at rest == the old box exactly, so the rest silhouette is
		-- unchanged. Each hangs off a Motor6D (no longer a weld) so it can OPEN/WRAP/CLENCH.
		local proxFrac = 0.55
		local distFrac = 1 - proxFrac
		local proxLen  = toeLen * proxFrac
		local distLen  = toeLen * distFrac
		for ti, yaw in ipairs({ -22, 0, 22 }) do
			-- knuckle = the toe base pivot (splay applied, BEFORE the -45° curl) = Part1 pivot of ToeJoint.
			local knuckle = footHub * CFrame.Angles(0, math.rad(yaw), 0)
			-- the built toe axis: curl -45° then run along -Z. The proximal segment centres proxLen*0.5 in.
			local curl = knuckle * CFrame.Angles(math.rad(-45), 0, 0)
			local prox = makePart("Talon", Vector3.new(r * 0.09, r * 0.09, proxLen), clawColor)
			prox.CFrame = curl * CFrame.new(0, 0, -proxLen * 0.5)
			prox.Parent = model
			-- mid-toe joint pivot = end of the proximal segment, on the same axis.
			local midPivot = curl * CFrame.new(0, 0, -proxLen)
			local claw = makePart("Talon", Vector3.new(r * 0.09, r * 0.09, distLen), clawColor)
			claw.CFrame = midPivot * CFrame.new(0, 0, -distLen * 0.5)
			claw.Parent = model
			-- ToeJoint: foot → proximal, world pivot at the knuckle. -1 curl sign (more-neg pitch = under).
			local toeJoint = Instance.new("Motor6D")
			toeJoint.Name = sideName .. "Toe" .. ti .. "Joint"
			toeJoint.Part0 = foot
			toeJoint.Part1 = prox
			toeJoint.C0 = foot.CFrame:ToObjectSpace(knuckle)
			toeJoint.C1 = prox.CFrame:ToObjectSpace(knuckle)
			toeJoint.Transform = CFrame.new()
			toeJoint:SetAttribute("Side", s)
			-- CurlSign +1: the OPEN/CLOSE pitch table is ALREADY signed in this joint's raw sense
			-- (open +deg UNCURLS/spreads the built -45° toe, close -deg folds it under). The pivot X is
			-- the knuckle's own axis, so no extra flip is needed. (Grasp-closure gate verified.)
			toeJoint:SetAttribute("CurlSign", 1)
			toeJoint:SetAttribute("OuterYawSign", (yaw > 0) and 1 or (yaw < 0) and -1 or 0)
			toeJoint.Parent = body
			-- ToeClawJoint: proximal → claw, world pivot at the mid-toe joint.
			local clawJoint = Instance.new("Motor6D")
			clawJoint.Name = sideName .. "Toe" .. ti .. "ClawJoint"
			clawJoint.Part0 = prox
			clawJoint.Part1 = claw
			clawJoint.C0 = prox.CFrame:ToObjectSpace(midPivot)
			clawJoint.C1 = claw.CFrame:ToObjectSpace(midPivot)
			clawJoint.Transform = CFrame.new()
			clawJoint:SetAttribute("Side", s)
			clawJoint:SetAttribute("CurlSign", 1)       -- same raw-signed sense as the proximal joint
			clawJoint:SetAttribute("OuterYawSign", 0)   -- the distal claw takes no yaw
			clawJoint.Parent = body
		end
		-- HALLUX: the rear "killing" claw, shorter, curling down-and-BACK (+Z), so +45° pitch here. Now on a
		-- Motor6D (foot → hallux) at the hallux base pivot = footHub, so it hooks under-forward on clench.
		local hallux = makePart("Talon", Vector3.new(r * 0.09, r * 0.09, r * 0.20), clawColor)
		hallux.CFrame = footHub * CFrame.Angles(math.rad(45), 0, 0) * CFrame.new(0, 0, r * 0.11)
		hallux.Parent = model
		local halluxJoint = Instance.new("Motor6D")
		halluxJoint.Name = sideName .. "HalluxJoint"
		halluxJoint.Part0 = foot
		halluxJoint.Part1 = hallux
		halluxJoint.C0 = foot.CFrame:ToObjectSpace(footHub)
		halluxJoint.C1 = hallux.CFrame:ToObjectSpace(footHub)
		halluxJoint.Transform = CFrame.new()
		halluxJoint:SetAttribute("Side", s)
		halluxJoint:SetAttribute("CurlSign", 1)   -- hallux extends along +Z: +pitch hooks it under-forward
		halluxJoint:SetAttribute("OuterYawSign", 0)
		halluxJoint.Parent = body
		-- HIP joint: body → thigh. World-pivot form (mirrors the squirrel buildLimb, which the wing-C1
		-- red-team proved is the safe pattern): body*C0 == thigh*C1 == hipPivot ⇒ Transform = I is the
		-- built rest pose exactly.
		local hip = Instance.new("Motor6D")
		hip.Name = sideName .. "HipJoint"
		hip.Part0 = body
		hip.Part1 = thigh
		hip.C0 = body.CFrame:ToObjectSpace(hipPivot)
		hip.C1 = thigh.CFrame:ToObjectSpace(hipPivot)
		hip.Transform = CFrame.new()
		hip:SetAttribute("Side", s)
		hip.Parent = body                                    -- parented to the Body so AnimateTalons finds it there
		-- FOOT joint: tarsus → foot. Same world-pivot form at footHub.
		local footJoint = Instance.new("Motor6D")
		footJoint.Name = sideName .. "FootJoint"
		footJoint.Part0 = tarsus
		footJoint.Part1 = foot
		footJoint.C0 = tarsus.CFrame:ToObjectSpace(footHub)
		footJoint.C1 = foot.CFrame:ToObjectSpace(footHub)
		footJoint.Transform = CFrame.new()
		footJoint:SetAttribute("Side", s)
		footJoint.Parent = body                              -- Part0 = tarsus; parent to Body for the same lookup
	end

	-- WINGS: the arm wing (broad inner slab) carries a covert feather row on top and a fan of
	-- individual PRIMARY feathers past its tip. The whole wing is ONE moving part (the inner
	-- slab, Part1 of the Motor6D) with everything welded to it, so it flaps as a rigid piece
	-- and AnimateWings still only drives the two named joints.
	-- Planform tuned from raptor-ID research: the bald eagle flies a long, BROAD, low-aspect
	-- "plank" with a nearly straight leading edge, held DEAD FLAT (no dihedral V — the key
	-- eagle-vs-vulture cue), tipped by ~6 splayed primary "finger" slots. Wingspan reads wide
	-- (~2.6–2.9× body length via the cosmetic parts; bodyRadius itself is a balance number and
	-- is left untouched). The crow stays smaller, slimmer-winged and more swept.
	local innerSpan  = isEagle and (r * 1.6) or (r * 1.15)   -- eagle arm-wing much longer/broader
	local innerChord = isEagle and (bodyLen * 0.82) or (bodyLen * 0.60)
	local wingThick  = r * 0.09
	local primaryCount = isEagle and 6 or 3
	local primaryLen   = isEagle and (r * 1.34) or (r * 1.85)      -- eagle: long full-length "fingers"
	local primaryChord = isEagle and (r * 0.42) or (r * 0.40)
	local primarySplay = isEagle and math.rad(2) or math.rad(4)    -- eagle ~flat: finger tips barely raised
	local baseSweep    = isEagle and math.rad(10) or math.rad(34)  -- eagle: straight leading edge, little sweep
	local fingerFan    = isEagle and math.rad(26) or math.rad(12)  -- extra aft sweep across the fingers -> swept tip
	local primaryTaper = isEagle and 0.045 or 0.07                -- gentler eagle taper keeps the tip full-length

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
		-- Coverts: a lighter shoulder on the eagle; a purple-blue iridescent sheen on the crow.
		local covertColor = isEagle
			and wingColor:Lerp(Color3.new(1, 1, 1), 0.14)
			or wingColor:Lerp(Color3.fromRGB(78, 66, 120), 0.22)
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
			local chordPos = (t - 0.5) * innerChord * 0.62                    -- spread across the chord
			local sweep = baseSweep + t * fingerFan                           -- fan: rear fingers sweep more
			local splay = (i - (primaryCount - 1) / 2) * primarySplay         -- near-flat finger separation
			local len = primaryLen * (1 - primaryTaper * i)                   -- gentle taper; keeps the tip full
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
		-- C1: the ROOT pivot expressed in wing-local space. Roblox solves the joint as
		-- Part0*C0*Transform == Part1*C1, so at rest (Transform = I) we need
		-- body*rootOffset == wing*C1  →  C1 = wingLocal:ToObjectSpace(rootOffset).
		-- (The operands were previously inverted, which crossed each wing through the body —
		-- caught by the Motor6D red-team audit.)
		motor.C1 = wingLocal:ToObjectSpace(rootOffset)
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

	-- Compute this frame's pose, shared by both wings:
	--   dihedral = up/down tip angle (about the joint's Z/forward axis)
	--   sweep    = aft yaw of the whole wing (about the joint's Y/up axis) — grows with dive depth
	--   blade    = leading-edge-down tilt (about X) — only at the deep stoop, for the bladed look
	-- BASE pose = flap or gentle idle bob, wings held out flat.
	local baseDihedral
	if isFlapping then
		baseDihedral = math.sin(flapPhase) * FLAP_AMPLITUDE
	else
		baseDihedral = math.sin(idle) * IDLE_AMPLITUDE
	end

	-- STAGED DIVE FOLD (S34 sandbox): read the body's own nose-down depth (continuous) and UNFOLD the
	-- wings through smooth levels — sweep the primaries aft, then deepen into the full swept arrowhead
	-- stoop with a cupped anhedral and a subtle blade tilt. `isDiving` is ignored here in favour of the
	-- continuous depth so the fold eases in progressively ("slowly sweeps its wings") instead of snapping.
	local ly = body.CFrame.LookVector.Y
	local diveAmt   = smoothstep(DIVE_ONSET_Y, DIVE_FULL_Y, ly)      -- 0 level → 1 near-vertical
	local sweep     = staged3(diveAmt, 0, DIVE_SWEEP_L1, DIVE_SWEEP_L2)
	local diveTipDrop = staged3(diveAmt, 0, DIVE_ANHED_L1, DIVE_ANHED_L2)
	local blade     = DIVE_BLADE * smoothstep(0.55, 1.0, diveAmt)    -- only the committed stoop blades over
	-- Blend the base pose out as the dive folds in; the dive's own anhedral drops the tips.
	local dihedral  = baseDihedral * (1 - diveAmt) - diveTipDrop

	-- STRIKE ATTACK POSE (S31): while the server marks this bird's strike ACTIVE (the replicated Body
	-- attribute StrikeActive), cup the wings up into a flare so the strike READS to every client. Purely
	-- cosmetic — Motor6D.Transform is client-local and never touches physics; the attribute is set only on
	-- eagles (GameServer.updateEagleStrikes) so crows are unaffected. The SMOOTH ease below swings the
	-- flare in on strike and back out on release. Gated + inert-able via GameConfig.Combat.fx.
	local fx = GameConfig.Combat and GameConfig.Combat.fx
	if fx and fx.strikePose and body:GetAttribute("StrikeActive") then
		dihedral = dihedral + math.rad(fx.strikePoseWingDeg or 0)
	end

	-- Apply symmetrically to each wing joint. The joint's C0 is a pure translation to the wing
	-- root, so the Transform's axes align with Body: rotate about Z to sweep the tip up/down
	-- (dihedral) and about Y to sweep the wing fore/aft. FlapSign (= side) mirrors left vs right;
	-- aft sweep is -side*sweep (same sign convention as the static primary-feather fan).
	local function drive(jointName)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		local sign = motor:GetAttribute("FlapSign") or 1
		-- Yaw aft first, then roll the dihedral, then a symmetric leading-edge-down blade tilt (deep dive).
		local target = CFrame.Angles(0, -sign * sweep, 0)
			* CFrame.Angles(0, 0, sign * dihedral)
			* CFrame.Angles(blade, 0, 0)
		-- Ease toward the target for smooth motion (and graceful state changes).
		local alpha = math.clamp(dt * SMOOTH, 0, 1)
		motor.Transform = approachCFrame(motor.Transform, target, alpha)
	end

	drive("LeftWingJoint")
	drive("RightWingJoint")
end

--------------------------------------------------------------------------------
-- AnimateTalons  (S39 — the eagle's talon CATCH animation)
--------------------------------------------------------------------------------
-- BirdBuilder.AnimateTalons(model, reach01, clench01, dt)
--   Swings the two leg rigs down-and-forward (reach) and snaps the toes open→shut (clench) for the
--   sacred squirrel catch. Cosmetic Motor6D.Transform ONLY — never touches physics/collision (Body is
--   the only massed part; FlightPhysics reads no instances). Safe on missing joints (crows, old models).
--   reach01  : 0 = legs tucked in the flight pose · 1 = fully swung down-and-forward, "hand" open.
--   clench01 : 0 = open · 1 = the grab (foot snaps under, hip pulls the snatch back through).
-- Sign convention verified from Build(): +X hip pitch swings the leg down-and-forward (the built +12°
-- forward lean); +X foot pitch flares the (built -45° curled) toes forward/open, -X curls them under.
local TALON_SMOOTH = 16   -- reach ease: the legs swing down smoothly.
local CLENCH_SNAP  = 40   -- clench ease: the fist must SNAP shut within ~2 frames of contact.
function BirdBuilder.AnimateTalons(model, reach01, clench01, dt)
	if not model then return end
	dt = tonumber(dt) or (1 / 60)
	reach01 = math.clamp(tonumber(reach01) or 0, 0, 1)
	clench01 = math.clamp(tonumber(clench01) or 0, 0, 1)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then return end
	-- Two eases: reach is smooth (TALON_SMOOTH); the digits close fast (CLENCH_SNAP) so the grasp reads
	-- as a snatch, not a slow squeeze. The digit target blends the two so a mid-close frame still tracks.
	local reachAlpha  = math.clamp(dt * TALON_SMOOTH, 0, 1)
	local clenchAlpha = math.clamp(dt * CLENCH_SNAP, 0, 1)
	local digitAlpha  = math.max(reachAlpha, clenchAlpha * clench01)   -- snap the closing, still smooth-open

	-- hip: swing down-and-forward as reach grows; the clench PULLS BACK slightly = the snatch-through.
	local hipX  = math.rad(58) * reach01 - math.rad(24) * clench01
	-- foot: REDUCED now that the digits carry the read — open a touch, then a small snap under on clench.
	local footX = math.rad(30) * reach01 * (1 - clench01) + math.rad(-18) * clench01

	-- Linear OPEN(reach=1,clench=0) → CLOSE(clench=1) for each digit angle. Open side scaled by reach01
	-- so the fingers only spread as the foot swings out. `lerpAngle` picks the pose from clench01.
	local function lerpAngle(openDeg, closeDeg)
		local open = math.rad(openDeg) * reach01
		return open + (math.rad(closeDeg) - open) * clench01
	end
	-- digit pitch magnitudes (before CurlSign): proximal +40 open / -35 close; distal claw +25 / -65.
	-- Applying CurlSign makes forward toes (-1) and the hallux (+1) both curl their TIPS toward one
	-- point below the foot: forward toes need a more-NEGATIVE pitch to fold under (CurlSign -1 flips the
	-- +open/-close sense so open SPREADS, close FOLDS UNDER); the hallux (+Z, CurlSign +1) hooks with +pitch.
	local proxPitch  = lerpAngle(54, -35)
	local clawPitch  = lerpAngle(32, -65)
	local halluxPitch = lerpAngle(-30, 55)   -- already in the hallux's +Z sense; CurlSign +1 = identity
	-- outer-toe yaw: fan the ±22° toes apart when open, converge when closed (OuterYawSign gives the side).
	local outerYaw   = lerpAngle(26, -8)

	local function driveHip(jointName)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		local side = motor:GetAttribute("Side") or 1
		local target = CFrame.Angles(hipX, 0, side * math.rad(6) * reach01)   -- slight outward set, feet apart
		motor.Transform = approachCFrame(motor.Transform, target, reachAlpha)
	end
	local function driveFoot(jointName)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		motor.Transform = approachCFrame(motor.Transform, CFrame.Angles(footX, 0, 0), reachAlpha)
	end
	-- driveDigit: one articulated toe/claw/hallux joint. `pitchMag` is the digit's pitch magnitude in the
	-- pivot's own sense; CurlSign folds it toward the grasp centre; OuterYawSign fans the outer toes.
	local function driveDigit(jointName, pitchMag, yawMag)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		local curl = motor:GetAttribute("CurlSign") or -1
		local yawSign = motor:GetAttribute("OuterYawSign") or 0
		local target = CFrame.Angles(curl * pitchMag, yawSign * (yawMag or 0), 0)
		motor.Transform = approachCFrame(motor.Transform, target, digitAlpha)
	end

	for _, side in ipairs({ "Left", "Right" }) do
		driveHip(side .. "HipJoint")
		driveFoot(side .. "FootJoint")
		for ti = 1, 3 do
			driveDigit(side .. "Toe" .. ti .. "Joint", proxPitch, outerYaw)   -- proximal (+ outer yaw)
			driveDigit(side .. "Toe" .. ti .. "ClawJoint", clawPitch, 0)       -- distal claw
		end
		driveDigit(side .. "HalluxJoint", halluxPitch, 0)
	end
end

--------------------------------------------------------------------------------
-- BuildSquirrel  (EAGLES TO THE RESCUE — the rescuable critter, gray-box)
--------------------------------------------------------------------------------
-- A charming bean-with-eyes squirrel. Cosmetic only (the world/rescue systems drive it):
--   Model
--   ├─ Body    (PrimaryPart; server anchors it as a world prop; no-collide/no-query so the
--   │           eagle flies THROUGH the trigger sphere and the flight spherecast ignores it)
--   ├─ Head + 2 Eyes(+pupils) + 2 Ears + Snout   (welded, cosmetic)
--   ├─ Tail    (the iconic big fluffy curl over the back — welded)
--   ├─ LeftArm/RightArm   (Motor6D "LeftArmJoint"/"RightArmJoint", hang down at rest)
--   └─ LeftLeg/RightLeg   (Motor6D "LeftLegJoint"/"RightLegJoint")
-- Pose it with BirdBuilder.PoseSquirrel(model, pose, dt, phase) — poses: idle/wave/plant/starfish/ride.
-- `palette` (optional) tints for rarity: { body, belly, eye }. Defaults to warm brown.
function BirdBuilder.BuildSquirrel(scale, palette)
	local s = tonumber(scale) or 2.2
	palette = palette or {}
	local bodyColor  = palette.body  or Color3.fromRGB(150, 96, 52)   -- warm brown
	local bellyColor = palette.belly or Color3.fromRGB(226, 198, 158)  -- cream belly/chest
	local irisColor  = palette.eye   or Color3.fromRGB(28, 22, 18)     -- big dark friendly eyes

	local model = Instance.new("Model")
	model.Name = "Squirrel"

	-- BODY: a plump upright bean. PrimaryPart, but purely cosmetic in the world (no collide/query).
	local body = makePart("Body", Vector3.new(s * 0.9, s * 1.15, s * 0.85), bodyColor)
	body.Shape = Enum.PartType.Ball
	body.Massless = false
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = true
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- BELLY: a lighter front so it reads as a critter, not a blob.
	local belly = makePart("Belly", Vector3.new(s * 0.72, s * 0.9, s * 0.55), bellyColor)
	belly.Shape = Enum.PartType.Ball
	belly.CFrame = body.CFrame * CFrame.new(0, -s * 0.05, -s * 0.34)
	belly.Parent = model
	weldTo(body, belly)

	-- HEAD: big relative to body (cuteness = large head). Slightly up and forward (-Z = forward).
	local head = makePart("Head", Vector3.new(s * 0.82, s * 0.82, s * 0.82), bodyColor)
	head.Shape = Enum.PartType.Ball
	head.CFrame = body.CFrame * CFrame.new(0, s * 0.72, -s * 0.12)
	head.Parent = model
	weldTo(body, head)

	-- SNOUT + tiny nose.
	local snout = makePart("Snout", Vector3.new(s * 0.34, s * 0.3, s * 0.34), bellyColor)
	snout.Shape = Enum.PartType.Ball
	snout.CFrame = head.CFrame * CFrame.new(0, -s * 0.08, -s * 0.42)
	snout.Parent = model
	weldTo(body, snout)
	local nose = makePart("Nose", Vector3.new(s * 0.14, s * 0.12, s * 0.12), Color3.fromRGB(60, 40, 40))
	nose.Shape = Enum.PartType.Ball
	nose.CFrame = snout.CFrame * CFrame.new(0, 0, -s * 0.18)
	nose.Parent = model
	weldTo(body, nose)

	-- EARS: two round ears up top (squirrel silhouette).
	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart("Ear", Vector3.new(s * 0.28, s * 0.34, s * 0.16), bodyColor)
		ear.Shape = Enum.PartType.Ball
		ear.CFrame = head.CFrame * CFrame.new(side * s * 0.34, s * 0.44, s * 0.04)
		ear.Parent = model
		weldTo(body, ear)
	end

	-- EYES: BIG friendly eyes with bright catchlight pupils (this is where the charm lives).
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart("Eye", Vector3.new(s * 0.3, s * 0.34, s * 0.24), Color3.fromRGB(245, 245, 245))
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = head.CFrame * CFrame.new(side * s * 0.26, s * 0.06, -s * 0.34)
		eye.Parent = model
		weldTo(body, eye)
		local pupil = makePart("Pupil", Vector3.new(s * 0.16, s * 0.2, s * 0.14), irisColor)
		pupil.Shape = Enum.PartType.Ball
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -s * 0.12)
		pupil.Parent = model
		weldTo(body, pupil)
		local glint = makePart("Glint", Vector3.new(s * 0.06, s * 0.07, s * 0.05), Color3.fromRGB(255, 255, 255))
		glint.Shape = Enum.PartType.Ball
		glint.Material = Enum.Material.Neon
		glint.CFrame = pupil.CFrame * CFrame.new(-side * s * 0.04, s * 0.04, -s * 0.08)
		glint.Parent = model
		weldTo(body, glint)
	end

	-- TAIL: the big fluffy curl arcing up over the back — three stacked balls sweeping up and forward.
	local tailColor = palette.tail or Color3.fromRGB(168, 112, 64)
	local tailSteps = {
		{ off = Vector3.new(0, s * 0.35, s * 0.35), sz = 0.62 },
		{ off = Vector3.new(0, s * 0.8,  s * 0.2),  sz = 0.72 },
		{ off = Vector3.new(0, s * 1.15, -s * 0.1), sz = 0.6 },
	}
	for _, step in ipairs(tailSteps) do
		local seg = makePart("TailSeg", Vector3.new(s * step.sz, s * step.sz, s * step.sz * 0.8), tailColor)
		seg.Shape = Enum.PartType.Ball
		seg.CFrame = body.CFrame * CFrame.new(step.off)
		seg.Parent = model
		weldTo(body, seg)
	end

	-- LIMBS via Motor6D so poses (wave/plant/starfish/ride) can animate them. Each limb part points
	-- DOWN (-Y) from its socket at rest; the Motor6D C0 sits at the socket pivot. PoseSquirrel rotates
	-- the joint Transform. Mirror sign stamped as "Side" (+1 right / -1 left).
	local function buildLimb(name, socket, length, thick, color, side)
		local limb = makePart(name, Vector3.new(thick, length, thick), color)
		limb.Shape = Enum.PartType.Ball
		-- position the limb hanging straight down from the socket (centre one half-length below it)
		limb.CFrame = body.CFrame * CFrame.new(socket) * CFrame.new(0, -length * 0.5, 0)
		limb.Parent = model
		local motor = Instance.new("Motor6D")
		motor.Name = name .. "Joint"
		motor.Part0 = body
		motor.Part1 = limb
		local pivot = body.CFrame * CFrame.new(socket)        -- world pivot at the socket
		motor.C0 = body.CFrame:ToObjectSpace(pivot)           -- body-space socket frame
		motor.C1 = limb.CFrame:ToObjectSpace(pivot)           -- limb-space socket frame (rest → Transform = I)
		motor.Transform = CFrame.new()
		motor:SetAttribute("Side", side)
		motor.Parent = body
		return motor
	end
	buildLimb("LeftArm",  Vector3.new(-s * 0.42, s * 0.2, -s * 0.16), s * 0.62, s * 0.24, bellyColor, -1)
	buildLimb("RightArm", Vector3.new( s * 0.42, s * 0.2, -s * 0.16), s * 0.62, s * 0.24, bellyColor,  1)
	buildLimb("LeftLeg",  Vector3.new(-s * 0.36, -s * 0.5, 0), s * 0.66, s * 0.3, bodyColor, -1)
	buildLimb("RightLeg", Vector3.new( s * 0.36, -s * 0.5, 0), s * 0.66, s * 0.3, bodyColor,  1)

	model:SetAttribute("SquirrelScale", s)
	return model
end

--------------------------------------------------------------------------------
-- BuildFox(scale, palette) — THE FOX (#15b): a friendly cartoon rascal for the ground patrol. A server-anchored
-- world prop moved by PivotTo (no Motor6D — the trot bob is applied by the server mover). PrimaryPart = Body,
-- -Z = forward (nose), so CFrame.lookAt(pos, pos+dir) faces it along its travel. P3 art rule: oversized friendly
-- eyes, rounded everything, NO teeth/claws — it must read as a mischief-maker who SCATTERS squirrels, never a
-- predator. `palette` optional: { body, belly, eye }.
--------------------------------------------------------------------------------
function BirdBuilder.BuildFox(scale, palette)
	local s = tonumber(scale) or 2.0
	palette = palette or {}
	local coat  = palette.body  or Color3.fromRGB(214, 110, 48)    -- rust orange
	local cream = palette.belly or Color3.fromRGB(244, 236, 220)   -- cream chest/snout/tail-tip
	local iris  = palette.eye   or Color3.fromRGB(40, 30, 22)

	local model = Instance.new("Model")
	model.Name = "Fox"

	-- BODY: a low horizontal bean (a trotting fox is longer than tall). PrimaryPart, cosmetic (no collide/query).
	local body = makePart("Body", Vector3.new(s * 0.95, s * 0.9, s * 1.7), coat)
	body.Shape = Enum.PartType.Ball
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = true
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- CHEST: cream front.
	local chest = makePart("Chest", Vector3.new(s * 0.7, s * 0.7, s * 0.8), cream)
	chest.Shape = Enum.PartType.Ball
	chest.CFrame = body.CFrame * CFrame.new(0, -s * 0.1, -s * 0.7)
	chest.Parent = model
	weldTo(body, chest)

	-- HEAD: forward + up.
	local head = makePart("Head", Vector3.new(s * 0.72, s * 0.7, s * 0.7), coat)
	head.Shape = Enum.PartType.Ball
	head.CFrame = body.CFrame * CFrame.new(0, s * 0.42, -s * 0.86)
	head.Parent = model
	weldTo(body, head)

	-- SNOUT (cream, pointed forward) + nose.
	local snout = makePart("Snout", Vector3.new(s * 0.34, s * 0.32, s * 0.5), cream)
	snout.Shape = Enum.PartType.Ball
	snout.CFrame = head.CFrame * CFrame.new(0, -s * 0.14, -s * 0.42)
	snout.Parent = model
	weldTo(body, snout)
	local nose = makePart("Nose", Vector3.new(s * 0.14, s * 0.12, s * 0.12), Color3.fromRGB(40, 28, 28))
	nose.Shape = Enum.PartType.Ball
	nose.CFrame = snout.CFrame * CFrame.new(0, 0, -s * 0.26)
	nose.Parent = model
	weldTo(body, nose)

	-- EARS: two upright triangle-ish blocks — the fox silhouette.
	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart("Ear", Vector3.new(s * 0.22, s * 0.4, s * 0.14), coat)
		ear.CFrame = head.CFrame * CFrame.new(side * s * 0.28, s * 0.46, s * 0.02)
		ear.Parent = model
		weldTo(body, ear)
	end

	-- EYES: big + friendly (the P3 charm — a rascal, not a hunter).
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart("Eye", Vector3.new(s * 0.24, s * 0.28, s * 0.2), Color3.fromRGB(245, 245, 245))
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = head.CFrame * CFrame.new(side * s * 0.24, s * 0.08, -s * 0.34)
		eye.Parent = model
		weldTo(body, eye)
		local pupil = makePart("Pupil", Vector3.new(s * 0.13, s * 0.16, s * 0.12), iris)
		pupil.Shape = Enum.PartType.Ball
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -s * 0.1)
		pupil.Parent = model
		weldTo(body, pupil)
	end

	-- TAIL: big fluffy brush with a cream tip, sweeping back and up.
	local tailA = makePart("TailSeg", Vector3.new(s * 0.55, s * 0.55, s * 0.6), coat)
	tailA.Shape = Enum.PartType.Ball
	tailA.CFrame = body.CFrame * CFrame.new(0, s * 0.2, s * 0.95)
	tailA.Parent = model
	weldTo(body, tailA)
	local tailB = makePart("TailTip", Vector3.new(s * 0.5, s * 0.5, s * 0.5), cream)
	tailB.Shape = Enum.PartType.Ball
	tailB.CFrame = body.CFrame * CFrame.new(0, s * 0.5, s * 1.25)
	tailB.Parent = model
	weldTo(body, tailB)

	-- LEGS: four short stubs (cosmetic; the trot bob is in the server mover).
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -0.55, 0.6 }) do
			local leg = makePart("Leg", Vector3.new(s * 0.22, s * 0.5, s * 0.22), Color3.fromRGB(60, 40, 28))
			leg.CFrame = body.CFrame * CFrame.new(x * s * 0.38, -s * 0.6, z * s)
			leg.Parent = model
			weldTo(body, leg)
		end
	end

	model:SetAttribute("FoxScale", s)
	return model
end

--------------------------------------------------------------------------------
-- PoseSquirrel(model, pose, dt, phase)
--   Eases the four limb Motor6Ds toward a named pose. Cosmetic; safe on missing joints.
--   poses: "idle" (limbs relaxed) · "wave" (both arms up, waving via phase) · "plant" (determined
--   brace — the tell) · "starfish" (all four spread — the apex "I'M FLYING") · "ride" (gripping seat) ·
--   "scramble" (hand-over-hand climb up to the back seat — the #9 catch-latch beat) ·
--   "reach" (rider leans out arms-wide to net an incoming CREW-CATCH leaper).
--   phase drives the wave oscillation (radians). dt eases the transition.
--------------------------------------------------------------------------------
local SQUIRREL_SMOOTH = 12
function BirdBuilder.PoseSquirrel(model, pose, dt, phase)
	if not model then return end
	dt = tonumber(dt) or (1 / 60)
	phase = tonumber(phase) or 0
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then return end
	local alpha = math.clamp(dt * SQUIRREL_SMOOTH, 0, 1)

	-- target rotation (about the socket) per joint, per pose. Sign mirrors L/R via the "Side" attr.
	-- Arms rotate mostly about X (raise fore/up) and Z (spread out); legs about X (kick down/out).
	local function target(jointName, isArm, side)
		if pose == "wave" then
			if isArm then
				local sway = math.sin(phase + (side > 0 and 0 or math.pi)) * math.rad(18)
				return CFrame.Angles(math.rad(155), 0, side * (math.rad(22) + sway)) -- both arms up, waving
			else
				return CFrame.Angles(math.rad(8), 0, 0)                              -- legs planted
			end
		elseif pose == "waveBig" then
			-- EXCITED "come back!" (the FTUE soft-fail face, Fable §D): both arms flung high overhead
			-- with a big fast sway so a young player's too-slow pass gets a reaction, never silence.
			if isArm then
				local sway = math.sin(phase + (side > 0 and 0 or math.pi)) * math.rad(34)
				return CFrame.Angles(math.rad(170), 0, side * (math.rad(30) + sway))
			else
				return CFrame.Angles(math.rad(8), 0, 0)
			end
		elseif pose == "plant" then
			-- braced, determined, LOUD (Fable #4): arms cocked back hard, legs set wide & deeply bent —
			-- an unmistakable "coiled to spring" read so the anticipation beat lands even at a glance.
			if isArm then return CFrame.Angles(math.rad(-40), 0, side * math.rad(16)) end
			return CFrame.Angles(math.rad(34), 0, side * math.rad(30))
		elseif pose == "starfish" then
			-- the apex "I'M FLYING" spread — all four limbs flung wide.
			if isArm then return CFrame.Angles(math.rad(70), 0, side * math.rad(95)) end
			return CFrame.Angles(math.rad(-20), 0, side * math.rad(70))
		elseif pose == "ride" then
			-- sitting on the back, arms up gripping — with a subtle phase-driven breathing sway so a
			-- carried rider never looks frozen (BirdController passes a live per-rider phase).
			local sway = math.sin(phase) * math.rad(6)
			if isArm then return CFrame.Angles(math.rad(120), 0, side * (math.rad(28) + sway)) end
			return CFrame.Angles(math.rad(55), 0, side * math.rad(24))
		elseif pose == "ridedive" then
			-- riding through a DIVE: arms flung wide overhead ("wheee!"), legs still bracing the seat.
			if isArm then return CFrame.Angles(math.rad(150), 0, side * math.rad(78)) end
			return CFrame.Angles(math.rad(55), 0, side * math.rad(24))
		elseif pose == "reach" then
			-- CREW CATCH v2 (Chad S35 "should be squirrels"): riders nearest the incoming leaper lean
			-- out ARMS-WIDE — a firefighter's net. Legs keep the seat grip; arms flung high and wide
			-- with a small eager tremble off `phase` so the crew visibly WANTS the catch.
			local eager = math.sin(phase * 3) * math.rad(7)
			if isArm then return CFrame.Angles(math.rad(105) + eager, 0, side * math.rad(85)) end
			return CFrame.Angles(math.rad(55), 0, side * math.rad(24))
		elseif pose == "scramble" then
			-- scrambling UP the eagle's body to the back seat (Chad's #9 catch-latch vision: "eagle
			-- catches with talon → squirrel scrambles up to the eagle's back"). A quick hand-over-hand
			-- climb: arms reach high and legs push, alternating L/R off `phase` (BirdController advances
			-- it fast) so it reads as clambering, not gliding. Big amplitude so the clamber is OBVIOUS.
			local scurry = math.sin(phase)
			if isArm then
				return CFrame.Angles(math.rad(125) + side * scurry * math.rad(55), 0, side * math.rad(38))
			else
				return CFrame.Angles(math.rad(25) - side * scurry * math.rad(45), 0, side * math.rad(30))
			end
		elseif pose == "leap" then
			-- THE JUMP (S39, Chad "animated squirrels jumping to be helped"): a real athletic leap toward
			-- the eagle's talons. `phase` carries arc progress u ∈ [0,1] (NOT radians). Launch push-off
			-- (arms flung back, continuous with `plant`'s -40° tell) → both arms sweeping OVERHEAD to reach
			-- for the talons; legs stream behind with a small kick. The leaper is already oriented look-at
			-- the eagle, so the overhead reach points AT it automatically. A tiny tremble keeps it alive.
			local u = math.clamp(phase, 0, 1)
			local k = math.clamp((u - 0.12) / 0.50, 0, 1)
			k = k * k * (3 - 2 * k)                                            -- smoothstep 0.12 → 0.62
			if isArm then
				local eager = math.sin(u * 24) * math.rad(5)
				return CFrame.Angles(math.rad(-38) + (math.rad(168) - math.rad(-38)) * k,
					0, side * (math.rad(26) - math.rad(11) * k) + side * eager)
			else
				local kick = math.sin(u * 22) * math.rad(6)
				return CFrame.Angles(math.rad(-42) + math.rad(20) * k + kick, 0, side * math.rad(12))
			end
		else -- idle
			if isArm then return CFrame.Angles(math.rad(6), 0, side * math.rad(8)) end
			return CFrame.Angles(0, 0, side * math.rad(6))
		end
	end

	local function drive(jointName, isArm)
		local motor = body:FindFirstChild(jointName)
		if not motor or not motor:IsA("Motor6D") then return end
		local side = motor:GetAttribute("Side") or 1
		motor.Transform = approachCFrame(motor.Transform, target(jointName, isArm, side), alpha)
	end
	drive("LeftArmJoint", true)
	drive("RightArmJoint", true)
	drive("LeftLegJoint", false)
	drive("RightLegJoint", false)
end

return BirdBuilder
