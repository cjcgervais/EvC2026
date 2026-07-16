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

local function buildTree(pos)
	local h = 60 + rng:NextNumber() * 55           -- trunk height
	local trunk = anchoredPart("Trunk", Vector3.new(7, h, 7), Color3.fromRGB(96, 66, 40), Enum.Material.Wood, worldFolder)
	trunk.Shape = Enum.PartType.Cylinder
	-- Cylinder's length is along X; rotate so it stands up along Y.
	trunk.CFrame = CFrame.new(pos + Vector3.new(0, h * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	-- Canopy: 2-3 green blobs clustered at the crown.
	local crownY = pos.Y + h
	local green = Color3.fromRGB(60 + rng:NextInteger(0, 30), 120 + rng:NextInteger(0, 40), 54 + rng:NextInteger(0, 24))
	for _ = 1, rng:NextInteger(2, 3) do
		local d = 34 + rng:NextNumber() * 22
		local blob = anchoredPart("Canopy", Vector3.new(d, d * 0.8, d), green, Enum.Material.Grass, worldFolder)
		blob.Shape = Enum.PartType.Ball
		blob.CFrame = CFrame.new(pos.X + (rng:NextNumber() - 0.5) * 26, crownY + (rng:NextNumber() - 0.5) * 14, pos.Z + (rng:NextNumber() - 0.5) * 26)
	end
	return crownY
end

local function buildWaterfall()
	local d = R.deliverPos
	-- Mesa: a stack of shrinking green/grey discs up to the safe pad.
	for i = 0, 5 do
		local y = i * (R.deliverPadY / 6)
		local rad = 260 - i * 26
		local mesa = anchoredPart("Mesa", Vector3.new(rad, R.deliverPadY / 6 + 2, rad), Color3.fromRGB(120, 116, 96), Enum.Material.Rock, worldFolder, true)
		mesa.Shape = Enum.PartType.Cylinder
		mesa.CFrame = CFrame.new(d.X, y + (R.deliverPadY / 12), d.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	-- Safe pad on top — bright green meadow disc (SOLID: the safe zone reads as ground you arrive on).
	local pad = anchoredPart("SafePad", Vector3.new(200, 6, 200), Color3.fromRGB(96, 196, 96), Enum.Material.Grass, worldFolder, true)
	pad.Shape = Enum.PartType.Cylinder
	pad.CFrame = CFrame.new(d.X, R.deliverPadY + 3, d.Z) * CFrame.Angles(0, 0, math.rad(90))
	-- Waterfall face — translucent blue sheet down the mesa front (visual; fly up beside it on the updraft).
	local fall = anchoredPart("Waterfall", Vector3.new(6, R.deliverPadY, 120), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, worldFolder)
	fall.Transparency = 0.45
	fall.CFrame = CFrame.new(d.X - 230, R.deliverPadY * 0.5, d.Z)
	-- Rim pool (solid).
	local pool = anchoredPart("RimPool", Vector3.new(120, 4, 120), Color3.fromRGB(120, 190, 240), Enum.Material.Glass, worldFolder, true)
	pool.Transparency = 0.35
	pool.Shape = Enum.PartType.Cylinder
	pool.CFrame = CFrame.new(d.X, R.deliverPadY + 6, d.Z) * CFrame.Angles(0, 0, math.rad(90))

	-- Updraft column VFX — translucent cyan cylinder + rising mist so the ride reads. (Force is client-side.)
	local col = anchoredPart("UpdraftColumn", Vector3.new(R.updraftTopY - R.updraftBaseY, R.updraftRadius * 2, R.updraftRadius * 2),
		Color3.fromRGB(200, 240, 255), Enum.Material.ForceField, worldFolder)
	col.Transparency = 0.85
	col.Shape = Enum.PartType.Cylinder
	col.CFrame = CFrame.new(d.X - 230, (R.updraftBaseY + R.updraftTopY) * 0.5, d.Z) * CFrame.Angles(0, 0, math.rad(90))
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
local function plantPerchTree(pos)
	local crownY = buildTree(pos)
	if rng:NextNumber() < 0.55 then
		perchList[#perchList + 1] = { pos = Vector3.new(pos.X, crownY + 6, pos.Z), underCanopy = false }
	else
		perchList[#perchList + 1] = { pos = Vector3.new(pos.X + (rng:NextNumber() - 0.5) * 40, 22 + rng:NextNumber() * 16, pos.Z + (rng:NextNumber() - 0.5) * 40), underCanopy = true }
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

	-- 2) Each grove = a tight cluster of perch-trees around its centre.
	local groveTrees = 0
	for _, c in ipairs(groveCentres) do
		for _ = 1, perchPerGrove do
			-- disc-uniform offset within groveRad
			local a = rng:NextNumber() * math.pi * 2
			local r = groveRad * math.sqrt(rng:NextNumber())
			local pos = Vector3.new(c.X + math.cos(a) * r, 0, c.Z + math.sin(a) * r)
			plantPerchTree(pos)
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
		buildTree(pos)   -- no perch: pure backdrop
		placed += 1
	end
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
	local pillar = Instance.new("Part")
	pillar.Name = "Beacon"
	pillar.Size = Vector3.new(2.2, 44, 2.2)
	pillar.Anchored = false
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Massless = true
	pillar.Material = Enum.Material.Neon
	pillar.Color = rarity.beacon
	pillar.Transparency = 0.55
	pillar.CFrame = body.CFrame * CFrame.new(0, 24, 0)
	pillar.Parent = model
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = pillar
	weld.C0 = body.CFrame:ToObjectSpace(pillar.CFrame)
	weld.Parent = body

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

	-- A friendly floating label so hidden ones read at a glance.
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.new(0, 90, 0, 44)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1400
	bb.Parent = body
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = rarity.beacon
	lbl.TextStrokeTransparency = 0.3
	lbl.Text = (rarity.name == "Brown") and "🐿️!" or ("🐿️ " .. string.upper(rarity.name) .. "!")
	lbl.Parent = bb
end

local function spawnSquirrel(perch)
	perch = perch or select(1, pickFreePerch())
	if not perch then return end
	local rarity = rollRarity()
	local model = BirdBuilder.BuildSquirrel(R.squirrelScale or 2.4, { body = rarity.body })
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
	model:PivotTo(CFrame.new(perch.pos) * CFrame.Angles(0, yaw, 0))
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
	-- Detach beacon so it reads as "rescued by the ranger, off your board".
	local beacon = model:FindFirstChild("Beacon")
	if beacon then beacon:Destroy() end
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
	for _ = 1, (R.squirrelCount or 10) do
		local perch, idx = pickFreePerch()
		if perch then
			spawnSquirrel(perch)
			-- record perch index on the freshest squirrel so we can free it on despawn
			local newest = squirrels[nextSquirrelId]
			if newest then newest.perchIndex = idx end
		end
	end
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
	if phase ~= "active" then diag("REJECT:phase"); return end
	if typeof(squirrelId) ~= "number" then diag("REJECT:badId"); return end
	local s = squirrels[squirrelId]
	if not s or s.state ~= "stranded" then diag("REJECT:gone(" .. tostring(s and s.state) .. ")"); return end
	local ps = stateFor(player)
	if ps.carry >= (R.carryCapacity or 3) then diag("REJECT:FULL"); return end   -- full — must deliver first
	-- Distance sanity: the eagle must actually be near the squirrel (bounds teleport-catching).
	local body = eagleBodyOf(player)
	if body and s.model and s.model.PrimaryPart then
		local dist = (body.Position - s.model.PrimaryPart.Position).Magnitude
		-- VELOCITY-AWARE gate (S36 fix): the client legitimately triggers within its ftue/scoop-widened
		-- radius, but by the time this fires the big (2.3×) eagle has flown on — at boom-and-zoom speed the
		-- server sees it much farther (diag: legit catches at dist 80-110, clipped by the old flat 105 gate
		-- → phantoms → "8-9/10 don't count"). Gate = base slack + how far the eagle travels during
		-- ~catchGateLatency. Still bounds a gross teleport-claim; scales with the actual cause (speed).
		local speed = body.AssemblyLinearVelocity.Magnitude
		local gate = (R.triggerRadius or 28) * (R.catchGateMult or 3.5) + speed * (R.catchGateLatency or 0.25)
		if dist > gate then
			diag(string.format("REJECT:dist(gate=%.0f)", gate), dist)
			return
		end
		diag("ACCEPT", dist)
	else
		diag("ACCEPT(nobody)")
	end

	-- Accept the catch.
	s.state = "caught"
	ps.carry += 1

	-- Score: base × rarity × style × ENERGY. The ENERGY multiplier rewards a high-velocity retrieval —
	-- a fast catch means you converted altitude into speed (boom-and-zoom), so the dive multiplies the
	-- rescue (Chad S34: teach energy dynamics). Tiered: BLAZING > SWIFT. Style/speed come from the client
	-- (Phase-0 feel trust); clamped to sane bounds so a bad packet can't inflate the score.
	local mult = math.clamp(tonumber(styleMult) or 1, 1, R.styleMultMax or 3)
	local rarityMult = s.rarity.mult or 1
	local energyMult = 1
	if speedTier == "BLAZING" then energyMult = R.blazingMult or 2.0
	elseif speedTier == "SWIFT" then energyMult = R.swiftMult or 1.5 end
	-- COMBO (Chad S34): consecutive catches within comboWindow build a streak ×2..×comboMax. Boom-and-zoom
	-- (fast flight + the speed-widened scoop) keeps the chain alive; flying off to deliver lets it lapse.
	local now = os.clock()
	if now - (ps.lastCatchAt or -1e9) <= (R.comboWindow or 4) then
		ps.combo = math.min((ps.combo or 0) + 1, R.comboMax or 6)
	else
		ps.combo = 1
	end
	ps.lastCatchAt = now
	-- The combo now pays at DELIVER, not per-catch (Chad S36: "multiply the delivery"). Bank the PEAK combo
	-- reached during THIS carry load; the deliver multiplies n² by it. Per-catch score stays combo-free so
	-- the streak's whole payoff lands at the waterfall — "bank now or keep chaining for a bigger drop?".
	ps.loadCombo = math.max(ps.loadCombo or 1, ps.combo)
	local pts = math.floor((R.basePoints or 100) * rarityMult * mult * energyMult + 0.5)
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
	if phase ~= "active" then return end
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
	-- → the drop pays n × n × combo acorns. deliverCombo is sent so the client sentence card is EXACTLY the
	-- payout (the sentence must never lie — red-team B1). Reset the streak for the next load.
	local cmb = math.max(1, math.floor(ps.loadCombo or 1))
	ps.score += n * n * (R.acornValue or 10) * cmb
	-- Send BOTH the authoritative n and the combo so the client sentence renders from SERVER truth, not the
	-- local rider count (which can diverge from ps.carry — red-team B1). The two land in the same push.
	ps.deliverN = n
	ps.deliverCombo = cmb
	ps.loadCombo = nil
	ps.carry = 0
	-- PERFECT TEN (Chad: "10/10 in good time"): stamp the clock the moment the 10th rescue lands;
	-- endRound turns it into the TIME FACTOR finale multiplier.
	if not ps.perfectAt and ps.delivered >= (R.perfectTenAt or 10) then
		ps.perfectAt = timeLeft
	end
	pushState(player)
end)

--------------------------------------------------------------------------------
-- ROUND LOOP
--------------------------------------------------------------------------------
local function startRound()
	phase = "active"
	timeLeft = R.roundLength or 120
	usedPerches = {}
	populateSquirrels()
	for _, player in ipairs(Players:GetPlayers()) do
		local ps = stateFor(player)
		ps.score = 0
		ps.carry = 0
		ps.delivered = 0
		ps.perfectAt = nil
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
			-- Quantize to WHOLE ACORNS first (style multipliers leave ragged points) so the finale
			-- sentence is EXACTLY true in acorns — a kid who verifies "139 × 2" in-head must never
			-- catch the game lying (red-team B1).
			local av = R.acornValue or 10
			ps.score = math.floor(ps.score / av + 0.5) * av
			local f = 2
			if ps.perfectAt >= (R.timeFactor4At or 60) then f = 4
			elseif ps.perfectAt >= (R.timeFactor3At or 30) then f = 3 end
			ps.preFactorScore = ps.score
			ps.timeFactor = f
			ps.score *= f
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
	local col = anchoredPart("FoxFlare", Vector3.new(320, 7, 7), Color3.fromRGB(255, 140, 40), Enum.Material.Neon, worldFolder)
	col.Shape = Enum.PartType.Cylinder
	col.Transparency = 0.25
	col.CFrame = CFrame.new(centre.X, 160, centre.Z) * CFrame.Angles(0, 0, math.rad(90))
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

local function spawnFox()
	if fox and fox.model then fox.model:Destroy() end
	local hz = mission.hazard or {}
	local den = foxDenPos()
	local model = BirdBuilder.BuildFox(hz.foxScale or 2.0)
	model.Name = "PatrolFox"
	model:PivotTo(CFrame.new(den))
	if model.PrimaryPart then model.PrimaryPart.Anchored = true end
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

local triageBucket = 0
local function RescueRoundLoop()
	resolveMission()
	buildWorld()
	squirrelsFolder = Instance.new("Folder")
	squirrelsFolder.Name = "Squirrels"
	squirrelsFolder.Parent = Workspace

	-- THE FOX (#15b): spawn the patrol + connect its Heartbeat step ONCE, only if this mission's hazard is the
	-- fox. Inert-by-default: waterfall_meadow never enters here → no fox, no den, no step connected.
	if (mission.hazard or {}).kind == "fox" then
		spawnFox()
		RunService.Heartbeat:Connect(stepFox)
	end

	while true do
		-- INTERMISSION
		phase = "intermission"
		timeLeft = R.intermission or 6
		clearSquirrels()
		pushAll()
		while timeLeft > 0 do
			task.wait(0.5)
			timeLeft -= 0.5
			pushAll()
		end

		-- ROUND
		startRound()
		triageBucket = 0
		local triageStarted = false
		while timeLeft > 0 do
			local dt = task.wait(0.25)
			timeLeft -= dt
			-- TRIAGE: once inside the last `triageAt` seconds, a stranded squirrel is balloon-lifted
			-- to safety every few seconds (fakes the fire cutting some off — Phase 1 replaces with the fire grid).
			-- Driven by mission.hazard (kind "triage"); falls back to the shipped literals.
			local hz = mission.hazard or {}
			if (hz.kind or "triage") == "triage" and timeLeft <= (hz.triageAt or R.triageAt or 60) then
				if not triageStarted then triageStarted = true end
				triageBucket += dt
				if triageBucket >= (hz.cadence or 4) then
					triageBucket = 0
					-- pick a random stranded squirrel to expire
					local candidates = {}
					for id, s in pairs(squirrels) do
						if s.state == "stranded" then candidates[#candidates + 1] = id end
					end
					if #candidates > (hz.minStranded or 2) then -- always leave a couple to catch
						expireSquirrel(candidates[rng:NextInteger(1, #candidates)])
					end
				end
			end
			-- periodic state push (~1 Hz)
			pushAll()
		end

		-- RESULTS
		endRound()
		task.wait(4)
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
