--!nonstrict
--[[
	RescueServer — EAGLES TO THE RESCUE (S32 Phase 0) authority.

	Owns the RESCUE game layer; coexists with GameServer, which still owns the eagle/flight
	(SetNetworkOwner, kernel) and spawns the player. This script touches NO combat code —
	it builds the gray-box valley, spawns rescuable squirrels, runs the 2-minute round, keeps
	score, and exposes the rescue Remotes. All tunables in GameConfig.Rescue.

	Authority split (mirrors the project's client-feel / server-fairness model):
	  • Server: squirrel lifecycle, round clock, score, carry/deliver totals, triage expiry.
	  • Client (BirdController rescue section): the catch DETECTION + the whole slow-mo catch
	    PRESENTATION (client-side, latency-free feel). It fires CatchSquirrel/DeliverSquirrels;
	    the server validates and is authoritative for score + squirrel removal.

	Remotes (ReplicatedStorage.RescueRemotes — our OWN folder so GameServer's Remotes churn
	can't clobber it):
	  • RescueState     (S→C: per-player {phase,timeLeft,score,carry,capacity,delivered,rescued})
	  • CatchSquirrel   (C→S: squirrelId, styleMult, speedTier)
	  • DeliverSquirrels(C→S: — )
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")   -- THE FOX (#15b): drives the Y-locked patrol step

local GameConfig  = require(ReplicatedStorage:WaitForChild("GameConfig"))
local BirdBuilder = require(ReplicatedStorage:WaitForChild("BirdBuilder"))
local RescueRules = require(ReplicatedStorage:WaitForChild("RescueRules"))
local FireGrid    = require(ReplicatedStorage:WaitForChild("FireGrid"))  -- THE FIRE (B1): pure fire-cell clock; driven per-round only in fire missions (inert otherwise)
local FireVisuals = require(ReplicatedStorage:WaitForChild("FireVisuals"))  -- THE FIRE (B2): pooled server-side render layer; built per-round only in fire missions (inert otherwise)
local AssetManifest = require(ReplicatedStorage:WaitForChild("AssetManifest"))  -- M4-B: curated free-mesh prop data (pure)
local MeshFactory    = require(ReplicatedStorage:WaitForChild("MeshFactory"))   -- M4-B: variant -> mesh Model applier

local R = GameConfig.Rescue
if not (R and R.enabled) then
	return -- rescue mode off; do nothing (combat/other modes own the server)
end

-- MISSION FRAMEWORK (Packet-03 §4, queue #15). The active mission's data table drives the round's hazard /
-- deliver geometry / critter placement. Resolved once per round (RescueRoundLoop) into this module local so
-- buildWorld + the triage branch can read it. EVERY field falls back to the current Rescue literal, so an
-- absent/malformed mission = the shipped Waterfall Meadow round exactly (inert by construction). Missions
-- change how you FLY, never how you CATCH (P8); always non-lethal (P3).
local mission: any = {}
local function resolveMission()
	mission = (GameConfig.Missions and GameConfig.Missions[R.activeMission]) or {}
	return mission
end

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local function buildRemotes()
	local existing = ReplicatedStorage:FindFirstChild("RescueRemotes")
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "RescueRemotes"
	folder.Parent = ReplicatedStorage
	local function event(name)
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
		return e
	end
	return {
		folder          = folder,
		RescueState     = event("RescueState"),
		CatchSquirrel   = event("CatchSquirrel"),
		DeliverSquirrels= event("DeliverSquirrels"),
	}
end
local Remotes = buildRemotes()

--------------------------------------------------------------------------------
-- RARITY TABLE — mostly common; rares tint the squirrel + its beacon and score big.
--------------------------------------------------------------------------------
local RARITIES = {
	{ name = "Brown",   weight = 68, mult = 1,  body = Color3.fromRGB(150, 96, 52),  beacon = Color3.fromRGB(255, 214, 120) },
	{ name = "Silver",  weight = 20, mult = 2,  body = Color3.fromRGB(196, 202, 210), beacon = Color3.fromRGB(210, 224, 240) },
	{ name = "Gold",    weight = 9,  mult = 4,  body = Color3.fromRGB(226, 176, 58),  beacon = Color3.fromRGB(255, 196, 70) },
	{ name = "Rainbow", weight = 3,  mult = 8,  body = Color3.fromRGB(240, 120, 180), beacon = Color3.fromRGB(255, 120, 200) },
}
local RARITY_TOTAL = 0
for _, r in ipairs(RARITIES) do RARITY_TOTAL += r.weight end

local rng = Random.new(20260713)
local function rollRarity()
	local t = rng:NextNumber() * RARITY_TOTAL
	for _, r in ipairs(RARITIES) do
		t -= r.weight
		if t <= 0 then return r end
	end
	return RARITIES[1]
end

--------------------------------------------------------------------------------
-- WORLD — gray-box valley: trees (visual-only for Phase 0), the waterfall + safe pad + updraft VFX.
-- Trees are CanQuery=false (no collision) this phase so no accidental crashes and no threading skill
-- yet — the catch is the Phase-0 point. Phase 1 turns on real canopy collision once lethality is deleted.
--------------------------------------------------------------------------------
local worldFolder
local perchList = {}   -- array of { pos = Vector3, underCanopy = bool }
local groveList = {}   -- THE FOX (#15b): grove centres, hoisted from buildWorld so the fox can target a grove
-- THE FIRE (B1, Commit 2): per-round fire state + geometry, set only in a hazard.kind=="fire" mission (nil
-- otherwise → the shipped round is byte-identical). fireGroveRadius is the round's grove radius (parallels
-- groveList's centres 1:1) so FireGrid.new can build its {center,radius} grove records.
local fireState = nil
local fireGroveRadius = 130
local fireSeeded = false            -- seedUpwind fires exactly ONCE per round (at igniteAt)
local fireCutOffSeen = {}           -- [g] = true once we've reacted to grove g being cut off (diff latch)
local fireGraceUntil = {}           -- [g] = round-elapsed time at which grove g's stranded squirrels get lifted
local fireVisuals = nil             -- THE FIRE (B2): pooled FireVisuals controller (nil unless a fire mission)
local fireVisualsFolder = nil       -- Workspace.FireVisuals (replicates to clients); nil under waterfall_meadow
local fireVisualTick = 0            -- fire-tick counter for the visual refresh cadence (visualEvery)

-- `queryable=true` makes the part participate in the flight collision spherecast + the style/updraft
-- proximity rays (a SOLID surface the eagle slides on, non-lethally). Visual-only parts stay CanQuery=false
-- so the eagle flies through them (leaves, waterfall sheet, VFX). Birds are CFrame-driven, so CanCollide
-- is irrelevant to them — only CanQuery matters for detection; we leave CanCollide=false throughout.
local function anchoredPart(name, size, color, material, parent, queryable)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = queryable == true
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- uprightCylinder — the ONE place that knows a Cylinder's axis is local X AND that it needs standing
-- up. Owning Size, Shape and the rotation together is the point: a caller cannot get the axis wrong,
-- forget the rotation, or add a cylinder that skips the convention (the compile.spec gate asserts
-- Enum.PartType.Cylinder appears exactly once in this file — right here).
--   axial    = extent ALONG the axis: height for a pillar, thickness for a disc.
--   diameter = the round face.
--   legacy   = pass R.cylinderAxisFix == false ONLY at the four sites that had it wrong, so the kill
--              switch restores the old world byte-identically. The two sites that were ALWAYS correct
--              (UpdraftColumn, FoxFlare) never pass it, so the switch cannot break them.
local function uprightCylinder(name, axial, diameter, color, material, parent, queryable, pos, legacy)
	local x, y, z = RescueRules.cylinderSize(axial, diameter, legacy)
	local p = anchoredPart(name, Vector3.new(x, y, z), color, material, parent, queryable)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

-- The four sites S46 fixed pass this; it is `true` only while the kill switch is off.
local function legacyAxis()
	return R.cylinderAxisFix == false
end

-- pineBias: probability the mesh swap (Map.meshTrees) picks a treePine variant over treeLeafy. Groves
-- lean leafy (low bias, the default); backdrop trees mix in more pines for variety (buildWorld passes a
-- higher bias there). Purely a mesh-visual choice — inert when meshTrees is off.
local function buildTree(pos, pineBias)
	-- B4.1 SOLID TREES: the eagle's swept-sphere sees a tree part only when it is queryable. The mode
	-- knob decides per KIND (RescueRules.treeQueryable); "off" = the pre-B4 ghost forest, byte-identical.
	-- Nothing lethal changes — Rescue.nonLethalTerrain already makes every impact a graze-slide.
	local trunkQ = RescueRules.treeQueryable(R, "Trunk")
	local canopyQ = RescueRules.treeQueryable(R, "Canopy")
	local h = 60 + rng:NextNumber() * 55           -- trunk height
	-- S46: h is the AXIAL extent (the trunk's height), 7 the diameter. Passing (7, h) here is what
	-- rendered every trunk as a 7-stud-tall, h-wide pancake with its canopy floating at crownY.
	local trunk = uprightCylinder("Trunk", h, 7, Color3.fromRGB(96, 66, 40), Enum.Material.Wood, worldFolder, trunkQ,
		pos + Vector3.new(0, h * 0.5, 0), legacyAxis())
	-- Canopy: 2-3 green blobs clustered at the crown.
	local crownY = pos.Y + h
	local green = Color3.fromRGB(60 + rng:NextInteger(0, 30), 120 + rng:NextInteger(0, 40), 54 + rng:NextInteger(0, 24))
	local meshTrees = GameConfig.Map and GameConfig.Map.meshTrees
	local topY = crownY
	for _ = 1, rng:NextInteger(2, 3) do
		local d = 34 + rng:NextNumber() * 22
		local blob = anchoredPart("Canopy", Vector3.new(d, d * 0.8, d), green, Enum.Material.Grass, worldFolder, canopyQ)
		blob.Shape = Enum.PartType.Ball
		local by = crownY + (rng:NextNumber() - 0.5) * 14
		blob.CFrame = CFrame.new(pos.X + (rng:NextNumber() - 0.5) * 26, by, pos.Z + (rng:NextNumber() - 0.5) * 26)
		topY = math.max(topY, by + d * 0.5)
		if meshTrees then
			blob.Transparency = 1
		end
	end

	-- M4-B: swap the visible geometry for a curated mesh (behind Map.meshTrees). THE CONTRACT PARTS
	-- STAY: Trunk + every Canopy blob keep their exact names/sizes/positions/queryable registration
	-- (CanopyCount, canopyQ, RescueRules.canopyRadius, B4.2 scoring, perch placement all read them
	-- unchanged) — flag-on only sets Transparency=1 on them and adds a purely-visual mesh Model rooted
	-- at the trunk base, scaled to the SAME total visual height (crown top - base) so squirrel perches
	-- still sit in the mesh crown.
	if meshTrees then
		trunk.Transparency = 1
		local isPine = rng:NextNumber() < (pineBias or 0.15)
		local variants = isPine and AssetManifest.props.treePine or AssetManifest.props.treeLeafy
		if variants and #variants > 0 then
			local variant = variants[rng:NextInteger(1, #variants)]
			local targetHeight = math.max(4, topY - pos.Y)
			-- anchorBase=true: pos.Y is the trunk BASE (the trunk is built at pos + h/2), so the mesh
			-- must ground its lowest extent there — otherwise its trunk-centre origin sits at pos.Y and
			-- ~40% of the tree sinks below the terrain, dropping the crown below the perch canopies.
			MeshFactory.build(variant, CFrame.new(pos), targetHeight, worldFolder, true)
		end
	end
	return crownY
end

local function buildWaterfall()
	local d = R.deliverPos
	-- Mesa: a stack of shrinking green/grey discs up to the safe pad.
	for i = 0, 5 do
		local y = i * (R.deliverPadY / 6)
		local rad = 260 - i * 26
		-- S46: the DISC's axial extent is its thickness; `rad` is the face diameter. Swapped, each of
		-- these rendered as a ~260-tall blade only 43.7 thick instead of a stacked disc.
		uprightCylinder("Mesa", R.deliverPadY / 6 + 2, rad, Color3.fromRGB(120, 116, 96), Enum.Material.Rock, worldFolder, true,
			Vector3.new(d.X, y + (R.deliverPadY / 12), d.Z), legacyAxis())
	end
	-- Safe pad on top — bright green meadow disc (SOLID: the safe zone reads as ground you arrive on).
	-- S46: 6 = thickness, 200 = diameter. Swapped, this was a 200-tall, 6-thick WALL — which is why
	-- the client's crowd-seating raycast has always fallen through to its deliverPadY + 6 default.
	uprightCylinder("SafePad", 6, 200, Color3.fromRGB(96, 196, 96), Enum.Material.Grass, worldFolder, true,
		Vector3.new(d.X, R.deliverPadY + 3, d.Z), legacyAxis())
	-- Waterfall face — translucent blue sheet down the mesa front (visual; fly up beside it on the updraft).
	local fall = anchoredPart("Waterfall", Vector3.new(6, R.deliverPadY, 120), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, worldFolder)
	fall.Transparency = 0.45
	fall.CFrame = CFrame.new(d.X - 230, R.deliverPadY * 0.5, d.Z)
	-- Rim pool (solid).
	-- S46: 4 = thickness, 120 = diameter (was a 120-tall glass wall).
	local pool = uprightCylinder("RimPool", 4, 120, Color3.fromRGB(120, 190, 240), Enum.Material.Glass, worldFolder, true,
		Vector3.new(d.X, R.deliverPadY + 6, d.Z), legacyAxis())
	pool.Transparency = 0.35

	-- Waterfall MOTION FX (M4, asset-free: all GPU-side particles, no per-frame server loop).
	-- The `fall` sheet is 6(X) × 250(Y) × 120(Z) centred at (920, 125, 0): face normal ±X, the drop
	-- runs down Y, the sheet spans Z. These emitters give the static glass sheet motion, base spray and
	-- rising mist. Purely cosmetic — nothing here is queried, collided, or read by gameplay.
	-- (1) Falling water DOWN the sheet — emitter parented to the sheet part emits throughout its 250-tall
	-- volume; downward EmissionDirection + gravity-ish Acceleration streaks it down toward the pool.
	local fallFX = Instance.new("ParticleEmitter")
	fallFX.Name = "FallWaterFX"
	fallFX.Color = ColorSequence.new(Color3.fromRGB(220, 238, 255), Color3.fromRGB(255, 255, 255))
	fallFX.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 11), NumberSequenceKeypoint.new(1, 17) })
	fallFX.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1) })
	fallFX.Lifetime = NumberRange.new(3.2, 4.0)
	fallFX.Rate = 55
	fallFX.Speed = NumberRange.new(35, 55)
	fallFX.SpreadAngle = Vector2.new(6, 10)
	fallFX.Acceleration = Vector3.new(0, -70, 0)
	fallFX.EmissionDirection = Enum.NormalId.Bottom
	fallFX.LightEmission = 0.3
	fallFX.Parent = fall

	-- Base attachment at the plunge-pool surface (~world (920, 3, 0)); carries the spray + rising mist.
	local baseAtt = Instance.new("Attachment")
	baseAtt.Position = Vector3.new(0, -(R.deliverPadY * 0.5) + 3, 0)
	baseAtt.Parent = fall
	-- (2) Impact SPRAY / foam — short-lived white burst UP + outward where the fall hits the pool.
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "WaterfallSpray"
	spray.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.new(1, 1, 1))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.5, 1.1)
	spray.Rate = 50
	spray.Speed = NumberRange.new(20, 45)
	spray.SpreadAngle = Vector2.new(55, 55)
	spray.Acceleration = Vector3.new(0, -60, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.LightEmission = 0.4
	spray.Parent = baseAtt
	-- (3) Rising base MIST — soft, large, near-transparent haze creeping up so the base reads atmospheric.
	-- Complements the updraft's higher mist (below) rather than duplicating it.
	local baseMist = Instance.new("ParticleEmitter")
	baseMist.Name = "WaterfallBaseMist"
	baseMist.Color = ColorSequence.new(Color3.fromRGB(225, 240, 252))
	baseMist.Size = NumberSequence.new(34, 72)
	baseMist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	baseMist.Lifetime = NumberRange.new(3.0, 5.0)
	baseMist.Rate = 12
	baseMist.Speed = NumberRange.new(8, 16)
	baseMist.SpreadAngle = Vector2.new(40, 40)
	baseMist.Acceleration = Vector3.new(0, 6, 0)
	baseMist.EmissionDirection = Enum.NormalId.Top
	baseMist.LightEmission = 0.5
	baseMist.Parent = baseAtt

	-- Updraft column VFX — translucent cyan cylinder + rising mist so the ride reads. (Force is client-side.)
	-- This site was ALWAYS correct (height first); it is routed through the helper for uniformity and
	-- deliberately does NOT pass `legacy`, so the kill switch cannot break what was never broken.
	local col = uprightCylinder("UpdraftColumn", R.updraftTopY - R.updraftBaseY, R.updraftRadius * 2,
		Color3.fromRGB(200, 240, 255), Enum.Material.ForceField, worldFolder, nil,
		Vector3.new(d.X - 230, (R.updraftBaseY + R.updraftTopY) * 0.5, d.Z))
	col.Transparency = 0.85
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -(R.updraftTopY - R.updraftBaseY) * 0.5, 0)
	att.Parent = col
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	mist.Size = NumberSequence.new(18, 40)
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(2.5, 3.5)
	mist.Rate = 22
	mist.Speed = NumberRange.new(60, 90)
	mist.SpreadAngle = Vector2.new(12, 12)
	mist.Acceleration = Vector3.new(0, 40, 0)
	mist.LightEmission = 0.4
	mist.Parent = col
end

-- Keep clear of the waterfall mesa footprint (with an optional extra pad so grove trees stay off it).
local function mesaTooClose(pos, pad)
	return (Vector3.new(pos.X - R.deliverPos.X, 0, pos.Z - R.deliverPos.Z)).Magnitude < (340 + (pad or 0))
end

-- Build a tree at `pos` and seed a squirrel perch on it: a treetop perch on ~55% of trees, else a
-- low under-canopy clearing perch nearby. Shared by grove trees (backdrop trees skip this = no perch).
-- THE FIRE (B1): `groveIndex` tags each perch with the grove it belongs to, so a fire cut-off can map
-- grove→its stranded squirrels without a distance search (squirrel carries its perch → perch carries the
-- grove). nil for pure backdrop trees (which never get perches anyway). Inert for non-fire missions.
local function plantPerchTree(pos, groveIndex)
	local crownY = buildTree(pos)
	if rng:NextNumber() < 0.55 then
		perchList[#perchList + 1] = { pos = Vector3.new(pos.X, crownY + 6, pos.Z), underCanopy = false, groveIndex = groveIndex }
	else
		perchList[#perchList + 1] = { pos = Vector3.new(pos.X + (rng:NextNumber() - 0.5) * 40, 22 + rng:NextNumber() * 16, pos.Z + (rng:NextNumber() - 0.5) * 40), underCanopy = true, groveIndex = groveIndex }
	end
end

-- THE FOX (#15b): the den sits at valleyRadius*0.85 on the bearing OPPOSITE the waterfall — so den-watching
-- and waterfall trips occupy different sky sectors (the routing tension). Y = footY above the Y=0 baseplate top.
local function foxDenPos()
	local d = R.deliverPos
	local bearing = math.atan2(d.Z, d.X) + math.pi
	local rad = (R.valleyRadius or 1600) * 0.85
	local footY = (mission.hazard or {}).footY or 4
	return Vector3.new(math.cos(bearing) * rad, footY, math.sin(bearing) * rad)
end

-- Groves (Fable §B5): squirrels only ever spawn on grove perches, so they cluster into a few tight
-- clumps → catch chains + style continuity. Everything else is visual-only backdrop forest.
local function buildWorld()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "RescueWorld"
	worldFolder.Parent = Workspace
	table.clear(groveList)   -- THE FOX (#15b): rebuild the grove-centre list this round

	-- deliver geometry (mission.deliver.kind; only "waterfall" exists today — absent = waterfall).
	local dv = mission.deliver or {}
	if (dv.kind or "waterfall") == "waterfall" then
		buildWaterfall()
	end

	-- critter placement (mission.placement; falls back to the shipped grove literals).
	local pm = mission.placement or {}
	local groveCount   = pm.groveCount or R.groveCount or 4
	local perchPerGrove= pm.perchPerGrove or R.grovePerchCount or 5
	local groveRad     = pm.groveRadius or R.groveRadius or 130
	local groveGap     = pm.groveMinGap or R.groveMinGap or 520

	-- 1) Place grove CENTRES: spread apart, clear of the mesa, with the grove's radius kept in-bounds.
	local centreRadMax = math.max(200, (R.valleyRadius or 1600) - groveRad - 60)
	local groveCentres = {}
	local guard = 0
	while #groveCentres < groveCount and guard < 400 do
		guard += 1
		local ang = rng:NextNumber() * math.pi * 2
		local rad = 220 + rng:NextNumber() * (centreRadMax - 220)
		local c = Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
		if mesaTooClose(c, groveRad) then continue end
		local ok = true
		for _, other in ipairs(groveCentres) do
			if (Vector3.new(c.X - other.X, 0, c.Z - other.Z)).Magnitude < groveGap then ok = false; break end
		end
		if ok then
			groveCentres[#groveCentres + 1] = c
			groveList[#groveList + 1] = c   -- THE FOX (#15b): remember the centre so the fox can target this grove
		end
	end

	-- THE FOX (#15b): a den mound the fox trots home to (visual only — CanQuery=false, no collision). Only
	-- when the fox hazard is active; waterfall_meadow never builds it (inert-by-default).
	if (mission.hazard or {}).kind == "fox" then
		local den = foxDenPos()
		local mound = anchoredPart("FoxDen", Vector3.new(64, 26, 64), Color3.fromRGB(96, 74, 52), Enum.Material.Ground, worldFolder)
		mound.Shape = Enum.PartType.Ball
		mound.CFrame = CFrame.new(den.X, 2, den.Z)
	end

	-- 2) Each grove = a tight cluster of perch-trees around its centre. THE FIRE (B1): tag each perch with
	-- its grove index (gi) so cut-off can map grove→squirrels; also stash the grove radius for FireGrid.
	fireGroveRadius = groveRad
	local groveTrees = 0
	for gi, c in ipairs(groveCentres) do
		for _ = 1, perchPerGrove do
			-- disc-uniform offset within groveRad
			local a = rng:NextNumber() * math.pi * 2
			local r = groveRad * math.sqrt(rng:NextNumber())
			local pos = Vector3.new(c.X + math.cos(a) * r, 0, c.Z + math.sin(a) * r)
			plantPerchTree(pos, gi)
			groveTrees += 1
		end
	end

	-- 3) Backdrop forest: the remaining tree budget, scattered valley-wide, NO perches (visual density).
	local backdrop = math.max(0, (R.treeCount or 68) - groveTrees)
	local placed = 0
	guard = 0
	while placed < backdrop and guard < 800 do
		guard += 1
		local ang = rng:NextNumber() * math.pi * 2
		local rad = 140 + rng:NextNumber() * ((R.valleyRadius or 1600) - 140)
		local pos = Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
		if mesaTooClose(pos) then continue end
		buildTree(pos, 0.45)   -- no perch: pure backdrop; mixes in more pines than groves (mesh visual only)
		placed += 1
	end

	-- B4.2 — publish the authoritative canopy count so the CLIENT's style index can tell "fully
	-- replicated" from "still arriving". Replication is not atomic: a client that scans this folder
	-- early gets a SHORT forest and, because the index is built once, stays permanently and silently
	-- wrong — symptom "style feels weak today", which is exactly the invisible class S44/S45 burned
	-- two sessions on. With the count published the client simply waits for the numbers to agree.
	local canopies = 0
	for _, d in ipairs(worldFolder:GetDescendants()) do
		if d.Name == "Canopy" then canopies += 1 end
	end
	worldFolder:SetAttribute("CanopyCount", canopies)
end

--------------------------------------------------------------------------------
-- SQUIRRELS
--------------------------------------------------------------------------------
local squirrelsFolder
local squirrels = {}      -- [id] = { model, perch, rarity, state }
local nextSquirrelId = 0
local usedPerches = {}    -- [perchIndex] = true

local function pickFreePerch()
	if #perchList == 0 then return nil, nil end
	for _ = 1, 40 do
		local i = rng:NextInteger(1, #perchList)
		if not usedPerches[i] then
			usedPerches[i] = true
			return perchList[i], i
		end
	end
	return nil, nil
end

local function buildBeacon(model, rarity)
	local body = model.PrimaryPart
	if not body then return end
	-- Vertical sparkle column above the squirrel — visible from altitude.
	-- S39 (Chad "drop the icons"): the emoji billboard is gone, so this beacon is now the SOLE long-range
	-- read — a tall, bright neon shaft rising well above the squirrel/canopy (the client tell-loop pulses it).
	-- S40 FIX (Chad "its just a light cylinder, I don't even see squirrels"): the S39 beacon was a
	-- 3.2-wide × 110-tall near-opaque column centered +40 → its BASE sat at Y≈-15, BELOW the squirrel,
	-- so the glowing tube ENGULFED the critter. Now it's a THIN marker beam whose base sits ABOVE the
	-- squirrel's head (center +40, height 70 → base ≈ +5, clearing the ~+3 head/tail), and the client
	-- FADES it to invisible up close (see BirdController tell-loop) so the squirrel + its animation
	-- are never occluded. Long-range "fly to the glow" read is kept by the thin bright shaft.
	-- STAGE 1 (kid-legibility, docs/KID-LEGIBILITY-PLAN.md): beaconStyle "halo" replaces the pillar with
	-- a flat ground halo + a bobbing head chevron — the CRITTER becomes the landmark. "shaft" = byte-identical.
	if (R.beaconStyle or "shaft") == "halo" then
		-- 1) Ground halo: the flat disc primitive the fire rings use, tinted by rarity.
		local ringRec = FireVisuals.buildRing({ ringColor = rarity.beacon }, R.haloRadius or 10, model)
		local halo = ringRec.part
		halo.Name = "Halo"
		halo.Transparency = 0.35
		halo.CFrame = body.CFrame * CFrame.new(0, R.haloGroundY or -1.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		-- 2) Head chevron: one neon kite gem hovering above the head — anchored, NOT welded, so the
		-- client can bob it (and the squirrel's hop, which moves the welded Body assembly, leaves
		-- the halo planted on the ground — the critter bounces INSIDE its frame).
		local cs = R.chevronSize or 2.2
		if (rarity.mult or 1) >= 4 then cs = cs * 1.35 end   -- gold/rainbow: bigger gem = triage-at-a-glance
		local chev = Instance.new("Part")
		chev.Name = "Chevron"
		chev.Size = Vector3.new(cs, cs * 1.6, cs)
		chev.Anchored = true
		chev.CanCollide = false
		chev.CanQuery = false
		chev.CanTouch = false
		chev.CastShadow = false
		chev.Material = Enum.Material.Neon
		chev.Color = rarity.beacon
		chev.CFrame = body.CFrame * CFrame.new(0, R.chevronY or 14, 0) * CFrame.Angles(0, 0, math.rad(45))
		chev.Parent = model
	else
		-- SHAFT (identity default): the original thin pillar beam, byte-identical.
		local bw = R.beaconWidth or 1.6
		local bh = R.beaconHeight or 70
		local baseY = R.beaconBaseY or 8
		local pillar = Instance.new("Part")
		pillar.Name = "Beacon"
		pillar.Size = Vector3.new(bw, bh, bw)
		pillar.Anchored = false
		pillar.CanCollide = false
		pillar.CanQuery = false
		pillar.CanTouch = false
		pillar.CastShadow = false
		pillar.Massless = true
		pillar.Material = Enum.Material.Neon
		pillar.Color = rarity.beacon
		pillar.Transparency = 0.15
		pillar.CFrame = body.CFrame * CFrame.new(0, baseY + bh / 2, 0)   -- base = +baseY (above the squirrel)
		pillar.Parent = model
		local weld = Instance.new("Weld")
		weld.Part0 = body
		weld.Part1 = pillar
		weld.C0 = body.CFrame:ToObjectSpace(pillar.CFrame)
		weld.Parent = body
	end

	local att = Instance.new("Attachment")
	att.Parent = body
	att.Position = Vector3.new(0, 2, 0)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(rarity.beacon)
	sparkle.LightEmission = 0.8
	sparkle.Size = NumberSequence.new(1.6, 0.2)
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Lifetime = NumberRange.new(1.0, 1.6)
	sparkle.Rate = 14
	sparkle.Speed = NumberRange.new(18, 30)
	sparkle.SpreadAngle = Vector2.new(8, 8)
	sparkle.Acceleration = Vector3.new(0, 20, 0)
	sparkle.Parent = att

	-- S39 (Chad "drop the icons, lets go with animated squirrels"): the floating "🐿️!" emoji billboard
	-- is GONE — the animated squirrel itself (wave/plant/panic tell) + the neon beacon column + the
	-- rarity-tinted body/sparkle now carry the read. Rare squirrels still read by beacon HUE + body tint.
end

local function spawnSquirrel(perch)
	perch = perch or select(1, pickFreePerch())
	if not perch then return end
	local rarity = rollRarity()
	-- STAGE 1 (kid-legibility): under "halo" use a bigger squirrel so the critter reads at gameplay range.
	local sqScale = ((R.beaconStyle or "shaft") == "halo") and (R.haloSquirrelScale or 5.5) or (R.squirrelScale or 2.4)
	local model = BirdBuilder.BuildSquirrel(sqScale, { body = rarity.body })
	nextSquirrelId += 1
	local id = nextSquirrelId
	model.Name = "Squirrel_" .. id
	model:SetAttribute("SquirrelId", id)
	model:SetAttribute("Rarity", rarity.name)
	model:SetAttribute("RarityMult", rarity.mult)
	model:SetAttribute("State", "stranded")           -- client reads this to drive wave/plant/starfish poses
	model:SetAttribute("UnderCanopy", perch.underCanopy == true)
	-- Anchor as a world prop, faced a random way, sitting on the perch.
	local yaw = rng:NextNumber() * math.pi * 2
	-- halo: the 5.5 squirrel's legs reach ~1.3 studs deeper than 4.4's — lift the pivot so the
	-- bigger critter keeps today's exact sink depth on its perch (presentation-only).
	local sqLift = ((R.beaconStyle or "shaft") == "halo") and 1.3 or 0
	model:PivotTo(CFrame.new(perch.pos + Vector3.new(0, sqLift, 0)) * CFrame.Angles(0, yaw, 0))
	model.PrimaryPart.Anchored = true
	buildBeacon(model, rarity)
	model.Parent = squirrelsFolder
	squirrels[id] = { model = model, perch = perch, rarity = rarity, state = "stranded" }
end

-- Lift an uncaught squirrel to safety on a "Ranger Balloon" (triage; NEVER harmed) then despawn.
local function expireSquirrel(id)
	local s = squirrels[id]
	if not s or s.state ~= "stranded" then return end
	s.state = "expiring"
	local model = s.model
	if not (model and model.Parent) then squirrels[id] = nil; return end
	model:SetAttribute("State", "expiring")
	-- Detach the signal so it reads as "rescued by the ranger, off your board".
	for _, n in ipairs({ "Beacon", "Halo", "Chevron" }) do
		local sig = model:FindFirstChild(n)
		if sig then sig:Destroy() end
	end
	-- Balloon.
	local balloon = Instance.new("Part")
	balloon.Shape = Enum.PartType.Ball
	balloon.Size = Vector3.new(14, 18, 14)
	balloon.Color = Color3.fromRGB(240, 90, 90)
	balloon.Material = Enum.Material.SmoothPlastic
	balloon.Anchored = false
	balloon.CanCollide = false
	balloon.CanQuery = false
	balloon.Massless = true
	balloon.CFrame = model.PrimaryPart.CFrame * CFrame.new(0, 18, 0)
	balloon.Parent = model
	local weld = Instance.new("Weld")
	weld.Part0 = model.PrimaryPart
	weld.Part1 = balloon
	weld.C0 = model.PrimaryPart.CFrame:ToObjectSpace(balloon.CFrame)
	weld.Parent = model.PrimaryPart
	-- Float up and away, then despawn + free the perch.
	task.spawn(function()
		local base = model:GetPivot()
		for t = 0, 1, 0.02 do
			if not (model and model.Parent) then break end
			model:PivotTo(base * CFrame.new(0, t * 320, 0))
			task.wait(0.03)
		end
		if model then model:Destroy() end
		if s.perchIndex then usedPerches[s.perchIndex] = nil end
		squirrels[id] = nil
	end)
end

local function clearSquirrels()
	for id, s in pairs(squirrels) do
		if s.model then s.model:Destroy() end
		squirrels[id] = nil
	end
	usedPerches = {}
end

local function populateSquirrels()
	clearSquirrels()
	local want = (R.squirrelCount or 10)
	local got, fails, noPerch = 0, 0, 0
	for _ = 1, want do
		local perch, idx = pickFreePerch()
		if perch then
			-- Per-squirrel pcall (S41 STABILIZE): one bad squirrel can no longer zero out the whole
			-- population — the classic "empty map" failure. A failure warns with its cause; the rest spawn.
			local ok, err = pcall(function()
				spawnSquirrel(perch)
				-- record perch index on the freshest squirrel so we can free it on despawn
				local newest = squirrels[nextSquirrelId]
				if newest then newest.perchIndex = idx end
			end)
			if ok then got += 1 else fails += 1; warn("[Rescue] spawnSquirrel failed: " .. tostring(err)) end
		else
			noPerch += 1
		end
	end
	-- STABILIZE diag: ONE server-console line that turns an "empty map" into a 1-glance verdict.
	-- got>0  → squirrels ARE spawning (an empty VIEW is then a render/beacon/sync issue, not spawning).
	-- got==0 → a real spawn failure (read the warn above) or no free perches (noPerch=want → world/grove gen).
	print(string.format("[Rescue] populated %d/%d squirrels (%d spawn-fail, %d no-perch)", got, want, fails, noPerch))
end

--------------------------------------------------------------------------------
-- ROUND + SCORE STATE
--------------------------------------------------------------------------------
local phase = "intermission"     -- "intermission" | "active" | "results"
local timeLeft = R.intermission or 6
local playerState = {}           -- [player] = { score, carry, delivered, rescued }

local function stateFor(player)
	local ps = playerState[player]
	if not ps then
		ps = { score = 0, carry = 0, delivered = 0, rescued = 0, combo = 0, lastCatchAt = -1e9 }
		playerState[player] = ps
	end
	return ps
end

local function pushState(player)
	local ps = stateFor(player)
	Remotes.RescueState:FireClient(player, {
		phase = phase,
		timeLeft = math.max(0, math.floor(timeLeft + 0.5)),
		score = ps.score,
		carry = ps.carry,
		capacity = R.carryCapacity or 3,
		delivered = ps.delivered,
		rescued = ps.rescued,
		combo = ps.combo or 0,
		deliverN = ps.deliverN,           -- the authoritative n the LAST deliver paid (sentence renders from this)
		deliverCombo = ps.deliverCombo,   -- the combo the LAST deliver cashed in (the sentence card's ×N)
		timeFactor = ps.timeFactor,       -- nil until the PERFECT-TEN finale lands at round end
		preFactorScore = ps.preFactorScore, -- the round total BEFORE the time factor (the sentence's left side)
		perfectFactor = ps.perfectFactor, -- the ×N earned for a fast ten, sent AT the perfect-10 deliver (banked; tallied at endRound)
	})
end

local function pushAll()
	for _, player in ipairs(Players:GetPlayers()) do
		pushState(player)
	end
end

--------------------------------------------------------------------------------
-- CATCH / DELIVER handlers (client-detected, server-authoritative)
--------------------------------------------------------------------------------
-- Find the player's flyable bird Body (for the catch distance sanity check).
local function eagleBodyOf(player)
	local birds = Workspace:FindFirstChild("Birds")
	if not birds then return nil end
	local anyOwned
	for _, m in ipairs(birds:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
			local body = m.PrimaryPart or m:FindFirstChild("Body")
			if m:GetAttribute("Possessed") == true and body then return body end
			anyOwned = anyOwned or body
		end
	end
	return anyOwned
end

-- PHASE-0 TRUST: the client owns catch DETECTION + the whole presentation beat (latency-free feel), and
-- sends the resolved styleMult + speedTier. The server is authoritative for score + squirrel removal and
-- bounds every client value (clamp + a distance sanity gate below) — but does NOT fully re-simulate the
-- catch. Fine for solo Phase 0; a competitive build would move detection server-side. (red-team REVISE 3.)
Remotes.CatchSquirrel.OnServerEvent:Connect(function(player, squirrelId, styleMult, speedTier)
	-- CATCH DIAGNOSTIC (S36): log the exact outcome so Chad's "8-9/10 don't count" gets a named cause
	-- (SYNC check; zero behavior when R.catchDiag is off). ps may not exist yet on the earliest rejects.
	local function diag(reason, dist)
		if not R.catchDiag then return end
		local psx = playerState[player]
		warn(string.format("[RescueDIAG] %s  id=%s carry=%s/%d%s", reason, tostring(squirrelId),
			tostring(psx and psx.carry), R.carryCapacity or 3, dist and string.format(" dist=%.0f", dist) or ""))
	end
	-- Cheap type pre-guards stay local (Instance/type concerns, and they precede the `s` lookup live). Their
	-- order + diag strings are preserved exactly (phase → badId), then the accept envelope is delegated to
	-- RescueRules.eligibility (mode="accept": acceptEnvelope band ONLY — no ftue / no closing gate).
	if phase ~= "active" then diag("REJECT:phase"); return end
	if typeof(squirrelId) ~= "number" then diag("REJECT:badId"); return end
	local s = squirrels[squirrelId]
	-- `not s` (id already reaped) must read as gone — eligibility tolerates a nil state, so pre-catch it here
	-- to preserve the live `not s or s.state ~= "stranded"` gate + its exact diag string.
	if not s then diag("REJECT:gone(" .. tostring(nil) .. ")"); return end
	local ps = stateFor(player)
	-- eaglePos/eagleVel come from the possessed Body; squirrelPos from the world model. When there is no body
	-- or no squirrel PrimaryPart, the live code skipped the distance sanity entirely ("ACCEPT(nobody)"): we
	-- reproduce that by passing dist=0/speed=0 so the tooFar rung can never trigger — gone/full still gate.
	local body = eagleBodyOf(player)
	local hasGeom = body and s.model and s.model.PrimaryPart
	local dist, speed = 0, 0
	if hasGeom then
		dist = (body.Position - s.model.PrimaryPart.Position).Magnitude
		speed = body.AssemblyLinearVelocity.Magnitude
	end
	local verdict = RescueRules.eligibility(R, {
		mode = "accept",
		phase = phase,
		state = s.state,
		dist = dist,
		speed = speed,
		glideSpeed = GameConfig.Profiles.Eagle.glideSpeed,
		carried = ps.carry,
		inFlight = 0,
		capacity = R.carryCapacity or 3,
	})
	if not verdict.eligible then
		-- Preserve the live diag strings verbatim, keyed on verdict.reason.
		if verdict.reason == "gone" then
			diag("REJECT:gone(" .. tostring(s.state) .. ")")
		elseif verdict.reason == "full" then
			diag("REJECT:FULL")   -- full — must deliver first
		elseif verdict.reason == "tooFar" then
			diag(string.format("REJECT:dist(gate=%.0f)", verdict.radius), dist)
		end
		return
	end
	-- Accepted. The "nobody" branch (no body/PrimaryPart) keeps its own diag — an Instance concern, not rules.
	if hasGeom then
		diag("ACCEPT", dist)
	else
		diag("ACCEPT(nobody)")
	end

	-- Accept the catch.
	s.state = "caught"
	ps.carry += 1

	-- Score: base × rarity × style × ENERGY (RescueRules.catchScore). The ENERGY multiplier rewards a
	-- high-velocity retrieval — a fast catch means you converted altitude into speed (boom-and-zoom), so the
	-- dive multiplies the rescue (Chad S34: teach energy dynamics). Tiered: BLAZING > SWIFT. Style/speed come
	-- from the client (Phase-0 feel trust); catchScore clamps style to sane bounds so a bad packet can't
	-- inflate the score. `tonumber(styleMult)` coerces the untrusted client param before the module clamps it.
	local rarityMult = s.rarity.mult or 1
	local pts = RescueRules.catchScore(R, rarityMult, tonumber(styleMult), speedTier)
	-- COMBO (Chad S34): consecutive catches within comboWindow build a streak ×2..×comboMax (RescueRules.
	-- comboOnCatch). Boom-and-zoom (fast flight + the speed-widened scoop) keeps the chain alive; flying off
	-- to deliver lets it lapse. The clock stays os.clock() at the call site (purity: the module takes `now`).
	-- The combo now pays at DELIVER, not per-catch (Chad S36: "multiply the delivery"): comboOnCatch returns
	-- the PEAK combo reached during THIS carry load (max of loadCombo, combo); the deliver multiplies n² by it.
	local now = os.clock()
	ps.combo, ps.loadCombo = RescueRules.comboOnCatch(R, now, ps.lastCatchAt, ps.combo, ps.loadCombo)
	ps.lastCatchAt = now
	ps.score += pts

	-- Remove the world squirrel (the client already flew the catch locally) + schedule a fresh one.
	local model = s.model
	squirrels[squirrelId] = nil
	local perchIndex = s.perchIndex
	if model then model:Destroy() end
	task.delay(R.respawnDelay or 5, function()
		if phase == "active" then
			if perchIndex then usedPerches[perchIndex] = nil end
			local perch, idx = pickFreePerch()
			if perch then
				spawnSquirrel(perch)
				local newest = squirrels[nextSquirrelId]
				if newest then newest.perchIndex = idx end
			end
		end
	end)

	pushState(player)
end)

Remotes.DeliverSquirrels.OnServerEvent:Connect(function(player)
	-- Deliver accepted in "active" OR "grace" (buzzer-beater delivers, Chad S38) — RescueRules.phaseAccepts.
	if not RescueRules.phaseAccepts(phase).deliver then return end
	local ps = stateFor(player)
	if ps.carry <= 0 then return end
	local n = ps.carry
	ps.delivered += n
	ps.rescued += n
	-- MATH DELIVERY (Packet-03 §3): the deliver bonus IS a multiplication sentence — n squirrels × n
	-- = n² ACORNS (an acorn = acornValue points; the HUD divides so every number the kid sees is small
	-- and round). n² is the genius knob: two trips of 5 pay 50 acorns, one brave trip of 10 pays 100 —
	-- "one more before the waterfall?" becomes a computable lesson that multiplication beats addition.
	-- COMBO CASH-IN (Chad S36 "multiply the delivery"): × the PEAK combo you built while chaining this load
	-- → the drop pays n × n × combo acorns (RescueRules.deliverPayout). deliverN/deliverCombo are sent so the
	-- client sentence card is EXACTLY the payout — server truth, not the local rider count (red-team B1).
	local payout = RescueRules.deliverPayout(R, ps.carry, ps.loadCombo)
	ps.score += payout.points
	ps.deliverN = payout.n
	ps.deliverCombo = payout.combo
	ps.loadCombo = nil
	ps.carry = 0
	-- PERFECT TEN (Chad: "10/10 in good time"): stamp the clock the moment the 10th rescue lands;
	-- endRound turns it into the TIME FACTOR finale multiplier.
	if not ps.perfectAt and ps.delivered >= (R.perfectTenAt or 10) then
		ps.perfectAt = timeLeft
		-- Compute the earned TIME FACTOR now (RescueRules.perfectFactor) so the client can REVEAL "fast bonus
		-- ×N BANKED" at this delivery (Chad S38: make the quick-ten reward apparent at the moment). The actual
		-- score multiply stays DEFERRED to endRound; endRound reuses this exact value so the banked ×N can
		-- never differ from the finale ×N (ONE perfectFactor call replaces both copies of the ladder).
		ps.perfectFactor = RescueRules.perfectFactor(R, ps.perfectAt)
	end
	pushState(player)
end)

-- CARRIER LOSS → ZERO THE CARRY (S45). See RescueRules.carryOnReset for the full failure trace. The
-- client drops every rider whenever the bird model goes away (teardownDrive), so the server MUST agree
-- or it silently rejects the rest of the round's catches as FULL. Watching Birds.ChildRemoved (rather
-- than the Respawn remote alone) covers EVERY teardown path — R, death, crash, ownership reclaim —
-- which is the same event the client already keys its own reset off.
task.spawn(function()
	local birds = Workspace:WaitForChild("Birds", 60)
	if not birds then
		-- Loud, never silent: a dead guard here reads to the player as "my catches stopped counting".
		warn("[Rescue] Birds folder never appeared in 60s — the carrier-loss carry reset is NOT armed.")
		return
	end
	birds.ChildRemoved:Connect(function(model)
		if not (R.carryResetOnLoss ~= false) then return end   -- kill switch: false = pre-S45 behaviour
		local uid = model:GetAttribute("OwnerUserId")
		if not uid then return end
		local player = Players:GetPlayerByUserId(uid)
		if not player then return end
		local ps = stateFor(player)
		if (ps.carry or 0) <= 0 then return end
		local lost = ps.carry
		local reset = RescueRules.carryOnReset(ps)
		ps.carry, ps.loadCombo = reset.carry, reset.loadCombo
		if R.catchDiag then
			warn(("[RescueDIAG] carrier loss: %s lost their bird carrying %d — carry zeroed to match the client")
				:format(player.Name, lost))
		end
		pushState(player)
	end)
end)

--------------------------------------------------------------------------------
-- ROUND LOOP
--------------------------------------------------------------------------------
local function startRound()
	phase = "active"
	timeLeft = RescueRules.phaseDuration(R, "active")
	usedPerches = {}
	populateSquirrels()
	for _, player in ipairs(Players:GetPlayers()) do
		local ps = stateFor(player)
		ps.score = 0
		ps.carry = 0
		ps.delivered = 0
		ps.perfectAt = nil
		ps.perfectFactor = nil
		ps.timeFactor = nil
		ps.preFactorScore = nil
		ps.loadCombo = nil
		ps.deliverCombo = nil
		ps.deliverN = nil
		-- keep `rescued` as the running crowd across rounds
	end
	pushAll()
end

local function endRound()
	phase = "results"
	-- PERFECT TEN → TIME FACTOR (Packet-03 §3 layer 3): a player who delivered their 10th rescue with
	-- clock to spare gets the round total multiplied — staged as ONE last multiplication sentence the
	-- kid can verify in-head ("Round 380 × 2 = 760!"). Small whole numbers only: ×2 for making it,
	-- ×3 / rare ×4 for making it FAST. Server-authoritative; the client just displays the sentence.
	for _, player in ipairs(Players:GetPlayers()) do
		local ps = stateFor(player)
		if ps.perfectAt and not ps.timeFactor then
			-- Reuse the factor already banked at the perfect-10 deliver (single source of truth → the finale ×N
			-- always equals the "BANKED ×N" the player was shown). Fallback recompute (RescueRules.perfectFactor
			-- — the ONE ladder that also ran at the deliver) if it's somehow absent.
			local f = ps.perfectFactor or RescueRules.perfectFactor(R, ps.perfectAt)
			-- RescueRules.finaleApply quantizes to WHOLE ACORNS FIRST (style multipliers leave ragged points) so
			-- the finale sentence is EXACTLY true in acorns — a kid who verifies "139 × 2" in-head must never
			-- catch the game lying (red-team B1) — then multiplies by the banked factor.
			local finale = RescueRules.finaleApply(R, ps.score, f)
			ps.preFactorScore = finale.preFactorScore
			ps.timeFactor = f
			ps.score = finale.finalScore
		end
	end
	pushAll()
end

--------------------------------------------------------------------------------
-- THE FOX (#15b, Packet-03 slice 4) — a single Y-locked patrol that adds ROUTING PRESSURE. It trots from its
-- den to a grove; on APPROACH the grove FLARES orange + those squirrels go frantic (a separate attribute the
-- client renders as an urgent tell — they stay "stranded" and CATCHABLE, so you race the fox for them); if it
-- ARRIVES the squirrels SCATTER to fresh perches — a TIME cost (now farther/spread), NEVER lethal (P3). The fox
-- never touches a squirrel; it sits ("aw, missed 'em") then trots home. Server-authoritative. Inert unless the
-- active mission's hazard.kind == "fox": the Heartbeat step is only connected then, and first-line-gates on phase.
--------------------------------------------------------------------------------
local fox = nil   -- { model, pos, den, state, timer, target, flared, flare, bob }

local function distXZ(a, b)
	return (Vector3.new(a.X - b.X, 0, a.Z - b.Z)).Magnitude
end

local function buildFoxFlare(centre)
	-- Also ALWAYS correct (320 = the beam's height); routed through the helper for uniformity, and it
	-- does NOT pass `legacy` so the S46 kill switch cannot break it.
	local col = uprightCylinder("FoxFlare", 320, 7, Color3.fromRGB(255, 140, 40), Enum.Material.Neon, worldFolder, nil,
		Vector3.new(centre.X, 160, centre.Z))
	col.Transparency = 0.25
	local att = Instance.new("Attachment")
	att.Parent = col
	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new(Color3.fromRGB(255, 150, 50))
	em.LightEmission = 0.7
	em.Size = NumberSequence.new(7, 1)
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	em.Lifetime = NumberRange.new(1.0, 1.8)
	em.Rate = 30
	em.Speed = NumberRange.new(20, 45)
	em.SpreadAngle = Vector2.new(24, 24)
	em.Acceleration = Vector3.new(0, 24, 0)
	em.Parent = att
	return col
end

local function clearFoxFlare()
	if fox and fox.flare then
		fox.flare:Destroy()
		fox.flare = nil
	end
end

local function strandedNear(centre, radius)
	local n = 0
	for _, s in pairs(squirrels) do
		if s.state == "stranded" and s.model and s.model.PrimaryPart then
			if distXZ(s.model.PrimaryPart.Position, centre) <= radius then n += 1 end
		end
	end
	return n
end

-- Pick a grove worth a patrol (≥ minTargets stranded within franticRadius); nil = none this cycle.
local function pickFoxTarget(hz)
	local eligible = {}
	local fr = hz.franticRadius or 170
	for _, c in ipairs(groveList) do
		if strandedNear(c, fr) >= (hz.minTargets or 2) then eligible[#eligible + 1] = c end
	end
	if #eligible == 0 then return nil end
	return eligible[rng:NextInteger(1, #eligible)]
end

-- Layer Frantic=true on stranded squirrels near the target. Separate attribute → State stays "stranded" →
-- still catchable (the whole point: race the fox for the frantic ones).
local function setFranticNear(centre, radius)
	for _, s in pairs(squirrels) do
		if s.state == "stranded" and s.model and s.model.PrimaryPart then
			if distXZ(s.model.PrimaryPart.Position, centre) <= radius then
				s.model:SetAttribute("Frantic", true)
			end
		end
	end
end

-- Clear Frantic everywhere (red-team NOTE): a squirrel the fox flared but never relocated (caught, or the
-- round/patrol ended first) would otherwise keep panicking with no fox near it — a cosmetic lie. Called on
-- arrival (after the spook) and when the fox parks, so panic only ever shows while a patrol is live.
local function clearAllFrantic()
	for _, s in pairs(squirrels) do
		if s.model and s.model.Parent and s.model:GetAttribute("Frantic") then
			s.model:SetAttribute("Frantic", nil)
		end
	end
end

-- Scatter ONE squirrel to a fresh perch ≥ relocateMinDist from the fox — a TIME cost, never harm. It's
-- uncatchable ("relocating") for the ~scamperTime hop (client scan + server gate both exclude it), then
-- stranded again on the new perch. Mirrors the expireSquirrel task.spawn arc + guards model.Parent per step.
local function relocateSquirrel(id)
	local s = squirrels[id]
	if not (s and s.state == "stranded" and s.model and s.model.Parent) then return end
	s.state = "relocating"
	s.model:SetAttribute("State", "relocating")
	s.model:SetAttribute("Frantic", nil)
	-- STAGE 3a: fear is about WHERE YOU STAND, so it cannot survive being moved. Without this a
	-- squirrel relocated away from the fire arrives on a safe perch still rendering full panic until
	-- the next fire tick re-stamps it. Exact symmetry with the Frantic clear above.
	s.model:SetAttribute("Danger", nil)
	local hz = mission.hazard or {}
	local foxPos = (fox and fox.pos) or Vector3.new(0, 0, 0)
	local newPerch, newIdx
	for _ = 1, 30 do
		local perch, idx = pickFreePerch()
		if not perch then break end
		if distXZ(perch.pos, foxPos) >= (hz.relocateMinDist or 400) then
			newPerch, newIdx = perch, idx
			break
		else
			usedPerches[idx] = nil   -- too close; release and retry
		end
	end
	if not newPerch then newPerch, newIdx = pickFreePerch() end   -- fallback: any free perch
	if not newPerch then
		s.state = "stranded"                      -- valley full → settle back in place, still rescuable
		s.model:SetAttribute("State", "stranded")
		return
	end
	-- perch bookkeeping: free the OLD index, claim the NEW (the catch-respawn path frees s.perchIndex)
	if s.perchIndex then usedPerches[s.perchIndex] = nil end
	s.perchIndex = newIdx
	s.perch = newPerch
	local model = s.model
	local startCf = model:GetPivot()
	local yaw = rng:NextNumber() * math.pi * 2
	local endCf = CFrame.new(newPerch.pos) * CFrame.Angles(0, yaw, 0)
	local dur = math.max(0.2, hz.scamperTime or 0.9)
	task.spawn(function()
		local steps = math.max(1, math.floor(dur / 0.03))
		for i = 1, steps do
			if not (model and model.Parent) then return end
			local a = i / steps
			local pos = startCf.Position:Lerp(endCf.Position, a)
			local arc = math.sin(a * math.pi) * 16    -- a little hop
			model:PivotTo(CFrame.new(pos + Vector3.new(0, arc, 0)) * CFrame.Angles(0, yaw, 0))
			task.wait(0.03)
		end
		if not (model and model.Parent) then return end
		model:PivotTo(endCf)
		model:SetAttribute("UnderCanopy", newPerch.underCanopy == true)
		s.state = "stranded"
		s.model:SetAttribute("State", "stranded")
	end)
end

local function spookNear(centre, radius)
	local ids = {}
	for id, s in pairs(squirrels) do
		if s.state == "stranded" and s.model and s.model.PrimaryPart then
			if distXZ(s.model.PrimaryPart.Position, centre) <= radius then ids[#ids + 1] = id end
		end
	end
	for _, id in ipairs(ids) do relocateSquirrel(id) end
end

-- Move + face the fox toward dirUnit with a trot bob (Y locked to footY + the bounce).
local function pivotFox(dirUnit, dt)
	if not (fox and fox.model and fox.model.Parent) then return end
	local footY = (mission.hazard or {}).footY or 4
	fox.bob = (fox.bob or 0) + dt * 9
	local y = footY + math.abs(math.sin(fox.bob)) * 1.3
	local at = Vector3.new(fox.pos.X, y, fox.pos.Z)
	fox.model:PivotTo(CFrame.lookAt(at, at + dirUnit))
end

-- A tall danger beacon + 🦊 billboard welded to the fox so the player can TRACK the threat crossing the valley
-- from altitude (Chad S38: "no fox seen anywhere" — a scale-3 fox 1360 studs out on the ground is a speck).
local function buildFoxBeacon(model)
	local body = model.PrimaryPart
	if not body then return end
	local pillar = Instance.new("Part")
	pillar.Name = "FoxBeacon"
	pillar.Size = Vector3.new(3, 80, 3)
	pillar.Anchored = false
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Massless = true
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(255, 90, 40)   -- danger orange-red (distinct from the squirrels' warm beacons)
	pillar.Transparency = 0.3
	pillar.CFrame = body.CFrame * CFrame.new(0, 44, 0)
	pillar.Parent = model
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = pillar
	weld.C0 = body.CFrame:ToObjectSpace(pillar.CFrame)
	weld.Parent = body
	local bb = Instance.new("BillboardGui")
	bb.Name = "FoxLabel"
	bb.Size = UDim2.new(0, 110, 0, 110)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 3200
	bb.Parent = body
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 130, 70)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = "🦊"
	lbl.Parent = bb
end

local function spawnFox()
	if fox and fox.model then fox.model:Destroy() end
	local hz = mission.hazard or {}
	local den = foxDenPos()
	local model = BirdBuilder.BuildFox(hz.foxScale or 2.0)
	model.Name = "PatrolFox"
	model:PivotTo(CFrame.new(den))
	if model.PrimaryPart then model.PrimaryPart.Anchored = true end
	buildFoxBeacon(model)
	model.Parent = worldFolder
	fox = { model = model, pos = den, den = den, state = "den", timer = hz.cadence or 18, flared = false, bob = 0 }
end

-- Park the fox at its den (between rounds / not active) — no patrol, no flare left stranded.
local function parkFox()
	if not fox then return end
	clearFoxFlare()
	clearAllFrantic()   -- round ended / not active → no squirrel should be left panicking (red-team NOTE)
	fox.state = "den"
	fox.pos = fox.den
	fox.flared = false
	fox.timer = (mission.hazard or {}).cadence or 18
	if fox.model and fox.model.Parent then
		fox.model:PivotTo(CFrame.new(fox.den))
	end
end

-- The Heartbeat step (connected once, only in fox missions). O(1) + ≤squirrelCount distance checks; no raycasts.
local function stepFox(dt)
	if not (fox and fox.model and fox.model.Parent) then return end
	if phase ~= "active" then parkFox(); return end
	local hz = mission.hazard or {}
	local f = fox
	f.timer = (f.timer or 0) - dt

	if f.state == "den" then
		if timeLeft > (hz.firstAt or 100) then return end   -- calm opening: don't depart yet
		if f.timer <= 0 then
			local target = pickFoxTarget(hz)
			if target then
				f.target = target
				f.state = "approach"
				f.flared = false
			else
				f.timer = (hz.cadence or 18) * 0.5              -- nothing worth chasing; recheck soon
			end
		end
	elseif f.state == "approach" then
		local dir = Vector3.new(f.target.X - f.pos.X, 0, f.target.Z - f.pos.Z)
		local d = dir.Magnitude
		if not f.flared and d <= (hz.flareRange or 360) then
			f.flared = true
			f.flare = buildFoxFlare(f.target)
			setFranticNear(f.target, hz.franticRadius or 170)
		end
		if d <= (hz.arriveRange or 40) then
			spookNear(f.target, hz.franticRadius or 170)
			clearAllFrantic()   -- any flared-but-not-relocated squirrel stops panicking now (red-team NOTE)
			f.state = "sit"
			f.timer = hz.dwell or 3
		elseif d > 1e-3 then
			local u = dir.Unit
			f.pos = f.pos + u * math.min((hz.speed or 24) * dt, d)
			pivotFox(u, dt)
		end
	elseif f.state == "sit" then
		if f.timer <= 0 then
			clearFoxFlare()
			f.state = "return"
		end
	elseif f.state == "return" then
		local dir = Vector3.new(f.den.X - f.pos.X, 0, f.den.Z - f.pos.Z)
		local d = dir.Magnitude
		if d <= (hz.arriveRange or 40) then
			f.state = "den"
			f.timer = hz.cadence or 18
		elseif d > 1e-3 then
			local u = dir.Unit
			f.pos = f.pos + u * math.min((hz.speed or 24) * dt, d)
			pivotFox(u, dt)
		end
	end
end

--------------------------------------------------------------------------------
-- THE FIRE (B1, Commit 2) — wire the pure FireGrid clock into the round. INERT unless the active
-- mission's hazard.kind=="fire" (waterfall_meadow stays byte-identical: none of this runs). Per-ROUND
-- (unlike the fox's once-at-boot spawn) — the burn + wind reset each round. The fire is NON-LETHAL: a
-- cut-off grove's still-stranded squirrels leave on the EXISTING Ranger Balloon (expireSquirrel, verbatim)
-- after a short cutoffGraceS countdown. The wind is FICTIONAL — it NEVER touches FlightPhysics/WIND_BASE.
--------------------------------------------------------------------------------

-- Build the per-round fire state right after the squirrels populate. Called from startRound (fire missions
-- only). A fresh random wind bearing per round reshapes the burn (replayability); groves come from the
-- round's groveList centres + fireGroveRadius.
local function initFire()
	fireState = nil
	fireSeeded = false
	table.clear(fireCutOffSeen)
	table.clear(fireGraceUntil)
	local hz = mission.hazard or {}
	if hz.kind ~= "fire" then return end   -- inert guard (belt-and-braces; caller also gates)

	-- FICTIONAL wind bearing: a unit XZ direction from a per-round random angle. Shapes the burn ONLY —
	-- never fed to FlightPhysics:SetWind / GameConfig WIND_BASE. The kernel is untouched.
	local ang = rng:NextNumber() * math.pi * 2
	local wind = Vector3.new(math.cos(ang), 0, math.sin(ang))

	-- assemble the grove records {center, radius} from this round's centres (groveList) + radius.
	local groves = {}
	for _, c in ipairs(groveList) do
		groves[#groves + 1] = { center = c, radius = fireGroveRadius }
	end

	fireState = FireGrid.new(GameConfig.Fire, rng:NextInteger(1, 2 ^ 30), wind, groves, R.deliverPos)

	-- THE FIRE (B2): stand up the POOLED visual layer in a replicated Workspace folder (fire missions
	-- only — we're already past the hz.kind~="fire" guard above). The pool is allocated ONCE here; stepFire
	-- only repositions/recolors it (no per-tick create/destroy). Folder is dropped in teardownFire.
	fireVisualTick = 0
	fireVisualsFolder = Instance.new("Folder")
	fireVisualsFolder.Name = "FireVisuals"
	fireVisualsFolder.Parent = Workspace
	local ok, ctrl = pcall(FireVisuals.new, FireGrid, GameConfig.Fire, fireState.cellSize, fireVisualsFolder)
	if ok then
		fireVisuals = ctrl
	else
		warn("[Fire] FireVisuals.new failed: " .. tostring(ctrl))
		fireVisualsFolder:Destroy()
		fireVisualsFolder = nil
	end
end

-- Balloon-lift every STILL-stranded squirrel that belongs to grove `g` (its perch's groveIndex). Reuses
-- expireSquirrel VERBATIM (the Ranger Balloon — non-lethal; NEVER harms a squirrel).
local function liftGroveSquirrels(g)
	local ids = {}
	for id, s in pairs(squirrels) do
		if s.state == "stranded" and s.perch and s.perch.groveIndex == g then
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		expireSquirrel(id)
	end
end

-- One fire tick from the round loop's 0.25s cadence. `elapsed` = seconds since the round went active.
-- Steps the grid, seeds the upwind line ONCE at igniteAt, diffs newly-cut-off groves into a cutoffGraceS
-- countdown, and (once a grace elapses) lifts that grove's stranded squirrels via the Ranger Balloon.
local function stepFire(dt, elapsed)
	if not fireState then return end
	local hz = mission.hazard or {}

	local ticksRun = FireGrid.step(fireState, dt)

	-- seed the burn ONCE when the round clock passes igniteAt (a calm opening before the clock starts).
	if not fireSeeded and elapsed >= (hz.igniteAt or GameConfig.Fire.igniteAt or 10) then
		fireSeeded = true
		FireGrid.seedUpwind(fireState)
	end

	-- THE FIRE (B2): render the POOLED visuals off the grid every `visualEvery` fire-ticks. Decoupled from
	-- the 0.25s loop and the 2 Hz sim so the per-render cost (reposition/recolor ≤30 sets + a coarse ember
	-- pass, no allocation) stays well under the ≤1.5ms/tick server budget — at visualEvery=2 that's ~1 Hz.
	-- We only sync on ticks the sim actually advanced (a fresh burning set) and gate on the visual cadence.
	if fireVisuals and ticksRun > 0 then
		local every = math.max(1, GameConfig.Fire.visualEvery or 2)
		fireVisualTick += ticksRun
		if fireVisualTick >= every then
			fireVisualTick = 0
			local perf = GameConfig.Fire.perfDiag == true
			local t0 = perf and os.clock() or 0
			-- pcall-guard the render (symmetry with the guarded FireVisuals.new): a cosmetic visual error must
			-- NEVER kill the round-loop coroutine. On failure, tear the pool down and drop to logic-only fire.
			local okSync, cells = pcall(function() return fireVisuals:sync(fireState, fireGraceUntil, elapsed) end)
			if not okSync then
				warn("[Fire] visual sync failed, disabling fire visuals: " .. tostring(cells))
				pcall(function() fireVisuals:destroy() end)
				fireVisuals = nil
			elseif perf then
				print(("[Fire] tick %d cells=%d ms=%.2f"):format(
					fireState.tickCount or 0, cells or 0, (os.clock() - t0) * 1000))
			end
		end
	end

	-- STAGE 3a (kid-legibility): stamp each STRANDED squirrel's fear from the grid. Pure arithmetic on
	-- the authoritative fire (FireGrid.dangerAt — ≤121 cell reads each, ≤15 squirrels), written ONLY when
	-- the value changes, so replication traffic is a handful of attribute sets across a whole round. The
	-- client renders it; the server is the single authority for the fact, exactly like Frantic/State.
	-- Gate: urgencyTells=false ⇒ never written ⇒ every client branch is dead ⇒ byte-identical round.
	if GameConfig.Fire.urgencyTells and ticksRun > 0 then
		for _, s in pairs(squirrels) do
			local m = s.model
			if s.state == "stranded" and s.perch and m and m.Parent then
				local d = FireGrid.dangerAt(fireState, s.perch.pos.X, s.perch.pos.Z)
				if m:GetAttribute("Danger") ~= d then
					m:SetAttribute("Danger", d)
				end
			end
		end
	end

	-- diff cut-off groves: a NEWLY cut-off grove starts a cutoffGraceS countdown; when it elapses, lift.
	local cut = FireGrid.cutOffGroves(fireState)
	local graceS = hz.cutoffGraceS or 8
	for g, isCut in ipairs(cut) do
		if isCut and not fireCutOffSeen[g] then
			fireCutOffSeen[g] = true
			fireGraceUntil[g] = elapsed + graceS   -- B2 will draw the warning ring during this window
		end
	end
	for g, deadline in pairs(fireGraceUntil) do
		if elapsed >= deadline then
			fireGraceUntil[g] = nil
			liftGroveSquirrels(g)
		end
	end
end

-- Per-round teardown (grace/results): drop the fire state so nothing steps between rounds.
local function teardownFire()
	fireState = nil
	fireSeeded = false
	table.clear(fireCutOffSeen)
	table.clear(fireGraceUntil)
	-- STAGE 3a: the stamp loop stops with the fire, so without this the survivors freeze mid-panic —
	-- red flashing halos on a field whose flames were just destroyed, through grace + results.
	for _, s in pairs(squirrels) do
		if s.model and s.model.Parent then
			s.model:SetAttribute("Danger", nil)
		end
	end
	-- THE FIRE (B2): drop the pooled visuals + the replicated folder so nothing lingers between rounds.
	if fireVisuals then
		pcall(function() fireVisuals:destroy() end)
		fireVisuals = nil
	end
	if fireVisualsFolder then
		fireVisualsFolder:Destroy()
		fireVisualsFolder = nil
	end
	fireVisualTick = 0
end

-- S44 BOOT DIAG (Chad: "it just takes a while at the start for everything to render"). The audit
-- ruled out a frame-rate cliff, which leaves three very different candidates — Roblox replicating the
-- place at join, the client acquisition handshake, and the 6s intermission that deliberately EMPTIES
-- the valley before the round bursts ~600 instances in one frame. Guessing between them is exactly how
-- the ping bug survived five "fixes", so instead: one flight, timestamped milestones, the cause NAMED.
-- Zero behaviour; `Rescue.bootDiag=false` prints nothing. Server clock is relative to this script's start.
local BOOT_T0 = os.clock()
local function bootStamp(what)
	if not R.bootDiag then return end
	print(string.format("[BootDiag/server] %7.3fs  %s", os.clock() - BOOT_T0, what))
end

local triageBucket = 0
local function RescueRoundLoop()
	bootStamp("round loop entered")
	resolveMission()
	bootStamp("mission resolved: " .. tostring(R.activeMission or "?"))
	buildWorld()
	bootStamp(("world built (trees + waterfall) — RescueWorld has %d descendants SERVER-side")
		:format(#worldFolder:GetDescendants()))
	squirrelsFolder = Instance.new("Folder")
	squirrelsFolder.Name = "Squirrels"
	squirrelsFolder.Parent = Workspace
	bootStamp("Squirrels folder parented (the client's WaitForChild can now resolve)")

	-- THE FOX (#15b): spawn the patrol + connect its Heartbeat step ONCE, only if this mission's hazard is the
	-- fox. Inert-by-default: waterfall_meadow never enters here → no fox, no den, no step connected.
	if (mission.hazard or {}).kind == "fox" then
		local ok, err = pcall(spawnFox)
		if not ok then warn("[RescueFox] spawnFox failed: " .. tostring(err)) end
		RunService.Heartbeat:Connect(stepFox)
	end

	local roundIndex = 0
	while true do
		-- INTERMISSION
		roundIndex += 1
		phase = "intermission"
		-- roundIndex is passed for ONE reason: the FIRST intermission after boot is dead air (the world
		-- builds in 4ms, the player has a bird by ~1.9s, and the valley stays EMPTY until 6.2s — the
		-- S44 BootDiag named this as Chad's "takes a while at the start for everything to render").
		-- Between rounds the pause is correct; at boot there is no previous round to break from.
		timeLeft = RescueRules.phaseDuration(R, "intermission", roundIndex)
		clearSquirrels()
		bootStamp(("INTERMISSION #%d begins (%.1fs) — the valley is now EMPTY of squirrels")
			:format(roundIndex, timeLeft))
		pushAll()
		while timeLeft > 0 do
			task.wait(math.min(0.5, timeLeft))
			timeLeft -= 0.5
			pushAll()
		end

		-- ROUND
		startRound()
		bootStamp("ROUND ACTIVE — all squirrels populated in ONE frame")
		triageBucket = 0
		local triageStarted = false
		-- THE FIRE (B1): build this round's fire state after the squirrels populate (fire missions only —
		-- initFire self-gates on hazard.kind and leaves fireState nil otherwise → shipped round untouched).
		local roundActive = RescueRules.phaseDuration(R, "active")
		initFire()
		bootStamp("fire pool allocated (parked; seeds at igniteAt)")
		while timeLeft > 0 do
			local dt = task.wait(0.25)
			timeLeft -= dt
			-- THE FIRE (B1): step the burn from this same 0.25s tick. elapsed = seconds since round went
			-- active (the fire seeds/cuts off on elapsed, not on the countdown clock). No-op if fireState nil.
			if fireState then stepFire(dt, roundActive - timeLeft) end
			-- TRIAGE: once inside the last `triageAt` seconds, a stranded squirrel is balloon-lifted
			-- to safety every few seconds (fakes the fire cutting some off — Phase 1 replaces with the fire grid).
			-- Driven by mission.hazard (kind "triage"); falls back to the shipped literals.
			local hz = mission.hazard or {}
			if (hz.kind or "triage") == "triage" then
				if not triageStarted then triageStarted = true end
				-- Bucket arithmetic + the expire-decision go to RescueRules.triageTick (pure); candidate
				-- collection + the rng pick + expireSquirrel stay SERVER-side. The hazard table preserves the
				-- live fallback chains verbatim: triageAt = hz.triageAt or R.triageAt (module's `or 60` covers the
				-- final rung), cadence = hz.cadence, minStranded = hz.minStranded.
				local candidates = {}
				for id, s in pairs(squirrels) do
					if s.state == "stranded" then candidates[#candidates + 1] = id end
				end
				local expire
				triageBucket, expire = RescueRules.triageTick(triageBucket, dt, timeLeft, #candidates, {
					triageAt = hz.triageAt or R.triageAt,
					cadence = hz.cadence,
					minStranded = hz.minStranded,
				})
				if expire then
					expireSquirrel(candidates[rng:NextInteger(1, #candidates)]) -- always leave a couple to catch
				end
			end
			-- periodic state push (~1 Hz)
			pushAll()
		end

		-- BUZZER GRACE (Chad S38): the clock hit 0, but a deliver the player made JUST before 0:00 can still be
		-- arriving over the network, and its hop-off ceremony needs to finish. Don't rush to end — hold a grace
		-- window that still ACCEPTS delivers (and lets the ceremony play) before locking the scoreboard. There is
		-- no rush to end the game. (timeLeft stays 0, so a grace deliver still lands its base perfect-ten factor.)
		phase = "grace"
		teardownFire()   -- THE FIRE (B1): drop the fire state at round end (per-round teardown; no-op if nil)
		pushAll()
		task.wait(RescueRules.phaseDuration(R, "grace"))

		-- RESULTS — hold on the end-of-round SCREEN long enough to read it, then loop to intermission.
		endRound()
		task.wait(RescueRules.phaseDuration(R, "results"))
	end
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	stateFor(player)
	pushState(player)
end)
Players.PlayerRemoving:Connect(function(player)
	playerState[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	stateFor(player)
end

task.spawn(RescueRoundLoop)
