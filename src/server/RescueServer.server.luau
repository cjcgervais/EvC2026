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

local GameConfig  = require(ReplicatedStorage:WaitForChild("GameConfig"))
local BirdBuilder = require(ReplicatedStorage:WaitForChild("BirdBuilder"))

local R = GameConfig.Rescue
if not (R and R.enabled) then
	return -- rescue mode off; do nothing (combat/other modes own the server)
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

-- Precompute perches from tree crowns (treetop) + low clearings (under-canopy).
local function buildWorld()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "RescueWorld"
	worldFolder.Parent = Workspace

	buildWaterfall()

	-- Trees scattered in the valley, avoiding the waterfall mesa footprint.
	local placed = 0
	local guard = 0
	while placed < (R.treeCount or 40) and guard < 500 do
		guard += 1
		local ang = rng:NextNumber() * math.pi * 2
		local rad = 140 + rng:NextNumber() * (R.valleyRadius - 140)
		local pos = Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
		if (Vector3.new(pos.X - R.deliverPos.X, 0, pos.Z - R.deliverPos.Z)).Magnitude < 340 then
			continue -- keep clear of the mesa
		end
		local crownY = buildTree(pos)
		placed += 1
		-- A treetop perch on ~55% of trees; the rest seed a low clearing perch nearby.
		if rng:NextNumber() < 0.55 then
			perchList[#perchList + 1] = { pos = Vector3.new(pos.X, crownY + 6, pos.Z), underCanopy = false }
		else
			perchList[#perchList + 1] = { pos = Vector3.new(pos.X + (rng:NextNumber() - 0.5) * 40, 22 + rng:NextNumber() * 16, pos.Z + (rng:NextNumber() - 0.5) * 40), underCanopy = true }
		end
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
	local model = BirdBuilder.BuildSquirrel(2.4, { body = rarity.body })
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
		ps = { score = 0, carry = 0, delivered = 0, rescued = 0 }
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
	if phase ~= "active" then return end
	if typeof(squirrelId) ~= "number" then return end
	local s = squirrels[squirrelId]
	if not s or s.state ~= "stranded" then return end
	local ps = stateFor(player)
	if ps.carry >= (R.carryCapacity or 3) then return end   -- full — must deliver first
	-- Distance sanity: the eagle must actually be near the squirrel (bounds teleport-catching).
	local body = eagleBodyOf(player)
	if body and s.model and s.model.PrimaryPart then
		if (body.Position - s.model.PrimaryPart.Position).Magnitude > (R.triggerRadius or 28) * 2.5 then
			return
		end
	end

	-- Accept the catch.
	s.state = "caught"
	ps.carry += 1

	-- Score: base × rarity × style, plus a speed-stamp bonus. Style/speed come from the client
	-- (Phase-0 feel trust); clamped to sane bounds so a bad packet can't inflate the score.
	local mult = math.clamp(tonumber(styleMult) or 1, 1, R.styleMultMax or 3)
	local rarityMult = s.rarity.mult or 1
	local pts = math.floor((R.basePoints or 100) * rarityMult * mult + 0.5)
	if speedTier == "BLAZING" or speedTier == "SWIFT" then
		pts += (R.speedStampBonus or 50)
	end
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
	ps.score += n * (R.deliverBonus or 25)
	ps.carry = 0
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
		-- keep `rescued` as the running crowd across rounds
	end
	pushAll()
end

local function endRound()
	phase = "results"
	pushAll()
end

local triageBucket = 0
local function RescueRoundLoop()
	buildWorld()
	squirrelsFolder = Instance.new("Folder")
	squirrelsFolder.Name = "Squirrels"
	squirrelsFolder.Parent = Workspace

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
			if timeLeft <= (R.triageAt or 60) then
				if not triageStarted then triageStarted = true end
				triageBucket += dt
				if triageBucket >= 4 then
					triageBucket = 0
					-- pick a random stranded squirrel to expire
					local candidates = {}
					for id, s in pairs(squirrels) do
						if s.state == "stranded" then candidates[#candidates + 1] = id end
					end
					if #candidates > 2 then -- always leave a couple to catch
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
