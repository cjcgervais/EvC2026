--!nonstrict
--[[
	GameServer — authoritative server for "Eagles vs Crows".

	Responsibilities (v1):
	  • Build the world (lighting, map, thermals) and the canonical Remotes folder.
	  • Assign players asymmetrically (1 Eagle vs Crow players) and spawn their birds:
	      - Eagle  -> ONE eagle Model.
	      - Crow   -> a SQUAD of 4 crow Models (one possessed, three AI).
	  • Hand network ownership of a bird's PrimaryPart to its controlling client so the
	    client-authoritative FlightPhysics engine drives it smoothly.
	  • Be AUTHORITATIVE for combat: validate AttackRequest server-side, range/aim checks,
	    apply beak/talon/dive damage, and maintain health.
	  • Detect the signature lose-lose high-speed bird-vs-bird COLLISIONS (mutual damage).
	  • Drive the 3 non-possessed AI crows of each squad with Boids + a light flight step.
	  • Run the round loop (intermission -> round -> resolve -> respawn) and keep score.

	DESIGN NOTE: this server never simulates the *possessed* birds' flight — those are
	client-owned (BirdController runs FlightPhysics locally). The server only reads their
	replicated PrimaryPart state (CFrame / AssemblyLinearVelocity) for combat & collisions,
	and only SIMULATES the AI crows it actually owns.

	HEALTH STORAGE: health is stored as a number Attribute "Health" on each bird Model's
	PrimaryPart (the "Body"). This keeps health attached to the instance (auto-cleaned on
	destroy), is replicated for client HUDs, and avoids a parallel table that can desync
	from model lifetime. A small server-side `Birds` registry table holds per-model metadata
	(owner player, profile, team, isAI, possessed flag, AI flight engine) keyed by the Model.
]]

--------------------------------------------------------------------------------
-- SERVICES & SHARED MODULES
--------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local FlightPhysics  = require(ReplicatedStorage:WaitForChild("FlightPhysics"))
local BirdBuilder    = require(ReplicatedStorage:WaitForChild("BirdBuilder"))
local Boids          = require(ReplicatedStorage:WaitForChild("Boids"))
local BirdCollision  = require(ReplicatedStorage:WaitForChild("BirdCollision"))
local SpatialHash    = require(ReplicatedStorage:WaitForChild("SpatialHash"))

--------------------------------------------------------------------------------
-- TUNING CONSTANTS local to the server (combat/collision feel knobs)
--------------------------------------------------------------------------------
-- TODO: deep balance tuning — these thresholds are first-pass guesses.
local ATTACK_BUFFER          = 3.0    -- extra studs added to (rA + rB) for attack reach
local TALON_ALIGN_DOT        = 0.5    -- look-vs-target alignment needed to use talons
local TALON_RANGE_FRACTION   = 0.6    -- talons only when very close (frac of max reach)
local DIVE_SPEED_THRESHOLD   = 120    -- speed above which a downward attack counts as a dive
local DIVE_VY_THRESHOLD      = -60    -- vertical velocity (studs/s) marking a real dive

local COLLISION_SPEED_MIN    = 90     -- relative speed (studs/s) below which rams are harmless
local COLLISION_SPEED_REF    = 260    -- relative speed at which collision damage is full-scale
local COLLISION_COOLDOWN     = 0.4    -- s; per-pair debounce so one ram is one hit
local ATTACK_COOLDOWN        = 0.6    -- s; per-attacker melee debounce

local AI_HEARTBEAT_DT_CAP    = 1 / 30 -- clamp dt fed to the AI flight engine
-- v3 REAL-SCALE: spawn ~560 m AGL (≈2000 studs) in the much taller sky — lots of dive room below
-- and ~5000 studs of climb headroom up to the 7143-stud ceiling. (Was 250 in the cramped 520-ceiling
-- world.) Solves "too easy to crash": the ground is now far away.
local SPAWN_HEIGHT           = 2000   -- default spawn altitude (studs)
-- Real obstacle/ground collision now goes through BirdCollision (swept Spherecast) — see
-- processCrashes / updateAICrows. This Y is only a DEEP FAILSAFE: anything that somehow
-- tunnels far below the world (baseplate top sits at Y=0) is killed unconditionally so it
-- can't sink forever and stall the respawn loop. Deepened for the bigger v3 world.
local GROUND_FAILSAFE_Y      = -200
local RESPAWN_COOLDOWN       = 1.5    -- s; debounce manual self-respawn requests

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local Remotes           -- ReplicatedStorage.Remotes folder (built at startup)
local ThermalList = {}  -- array of {position, radius, minHeight, maxHeight, strength}

-- Per-model registry. Keyed by the bird Model.
-- entry = {
--   model, body (PrimaryPart), player, team ("Eagles"/"Crows"), profileName, profile,
--   isAI (bool), possessed (bool), squad (Squad table | nil), engine (FlightPhysics | nil)
-- }
local Birds = {}

-- Per-player record.
-- record = { player, team, profileName, profile, birds = {Model,...}, squad = Squad|nil }
local PlayerData = {}

-- Per-crow-player squad.
-- squad = { player, formationName, possessedIndex, members = {Model,...} }
local Squads = {}

-- Score, shown via ScoreUpdate. Keys match client UI ("Eagles"/"Crows").
local Scores = { Eagles = 0, Crows = 0 }

-- Debounce books.
local lastAttackAt = {}     -- [player] = os.clock()
local lastCollisionAt = {}  -- ["modelA|modelB"] = os.clock()
local lastSwapAt = {}       -- [player] = os.clock()
local lastRespawnAt = {}    -- [player] = os.clock()

local roundActive = false

--------------------------------------------------------------------------------
-- SMALL HELPERS
--------------------------------------------------------------------------------
local function getHealth(body)
	if not body then return 0 end
	return tonumber(body:GetAttribute("Health")) or 0
end

local function setHealth(body, hp)
	if body then body:SetAttribute("Health", math.max(0, hp)) end
end

-- Stable key for a pair of models (order-independent) for collision debouncing.
local function pairKey(a, b)
	local ka, kb = tostring(a), tostring(b)
	if ka < kb then return ka .. "|" .. kb else return kb .. "|" .. ka end
end

-- Is this bird still alive (model present + Health > 0)?
local function isBirdAlive(entry)
	return entry ~= nil
		and entry.model ~= nil
		and entry.model.Parent ~= nil
		and entry.body ~= nil
		and getHealth(entry.body) > 0
end

-- The possessed bird Model a player currently controls (for attacks). Strictly the
-- POSSESSED bird — no "first living bird" fallback. The old fallback let a crow player
-- whose possessed bird had died (before autoRepossess promoted a survivor) fire an attack
-- that resolved from a server-simulated AI crow they weren't actually flying. Attacks must
-- only originate from the bird the player is in control of.
local function getActiveBird(player)
	local rec = PlayerData[player]
	if not rec then return nil end
	for _, model in ipairs(rec.birds) do
		local entry = Birds[model]
		if entry and entry.possessed and isBirdAlive(entry) then
			return entry
		end
	end
	return nil
end

-- Try to grant network ownership of a bird's PrimaryPart to a client. Robust per spec.
local function trySetNetworkOwner(body, player)
	if not body then return end
	pcall(function()
		if body.Anchored then return end
		if player and body:CanSetNetworkOwnership() then
			body:SetNetworkOwner(player)
			-- Definitive handoff signal for the client: it must NOT drive the Body until it
			-- sees this == its UserId, or its CFrame writes fight the server during the
			-- async ownership-transfer window (the spawn/swap rubber-band). Replicates.
			body:SetAttribute("NetOwner", player.UserId)
		end
	end)
end

-- Server-owned AI birds: clear ownership so the SERVER simulates them.
local function setServerOwned(body)
	if not body then return end
	pcall(function()
		if not body.Anchored and body:CanSetNetworkOwnership() then
			body:SetNetworkOwner(nil) -- nil = server authority
			body:SetAttribute("NetOwner", 0) -- 0 = server; clients stop driving it
		end
	end)
end

-- Reset the anti-cheat kinematic baseline after a LEGITIMATE server move (spawn / respawn /
-- swap / repossess). Without this the teleport gate would fire on the server's own reposition
-- or ownership handoff. Strikes (on the player record) deliberately persist — only the
-- per-bird position baseline and leaky bucket are cleared, with a short grace window.
local function markServerMove(entry)
	if not entry then return end
	entry._acLastPos = nil
	entry._acBucket = 0
	entry._acGraceUntil = os.clock() + (GameConfig.Security.graceSeconds or 0.5)
end

--------------------------------------------------------------------------------
-- WORLD SETUP
--------------------------------------------------------------------------------
local function SetupLighting()
	-- A clear, high-altitude sky so the aerial arena reads well.
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 130, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 170)
	Lighting.FogEnd = 16000 -- v3: see across the much bigger real-scale arena
	Lighting.FogColor = Color3.fromRGB(180, 200, 225)
	Lighting.GeographicLatitude = 30

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.3
		atmo.Haze = 1.2
		atmo.Color = Color3.fromRGB(199, 215, 235)
		atmo.Decay = Color3.fromRGB(106, 140, 180)
		atmo.Parent = Lighting
	end
	if not Lighting:FindFirstChild("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.Parent = Lighting
	end
end

-- Build the arena. v3 REAL-SCALE (docs/RESEARCH.md §v3, session 8): a vast floor and a sparse
-- scatter of tall, thin spires spread far apart, so the sky is open (boom-and-zoom room, fewer
-- crashes) and the spires are navigational landmarks/perches you soar AROUND rather than a dense
-- forest you clip in a turn. Sized in real metres at 0.28 m/stud. World-bounds are intentionally
-- soft (huge floor + fog) for now — hard perimeter walls are a later balance pass (they'd add the
-- very crash-frustration Chad asked to remove).
local function BuildMap()
	-- Keep the Roblox engine's own gravity coherent with the flight model's (birds are CFrame-driven
	-- so they read GameConfig.Flight.GRAVITY directly, but this keeps debris/landings/ragdolls sane).
	Workspace.Gravity = GameConfig.Flight.GRAVITY

	local map = Workspace:FindFirstChild("Map")
	if map then map:Destroy() end
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	-- Vast baseplate (≈4.5 km square at 0.28 m/stud) so the ground is rarely a hazard.
	local base = Instance.new("Part")
	base.Name = "Baseplate"
	base.Anchored = true
	base.Size = Vector3.new(16000, 40, 16000)
	base.Position = Vector3.new(0, -20, 0)
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(70, 110, 60)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = map

	-- Sparse tall spires spread across the arena (polar layout: angle, radius, height in studs).
	-- Heights reach into the mid soaring band; diameters are thin relative to the 16 000-stud world.
	local spires = {
		{ ang = 0.4,  rad = 1400, h = 1100 },
		{ ang = 1.7,  rad = 2600, h = 1700 },
		{ ang = 2.9,  rad = 1800, h = 800  },
		{ ang = 3.8,  rad = 3400, h = 2000 },
		{ ang = 4.6,  rad = 2200, h = 1300 },
		{ ang = 5.5,  rad = 3000, h = 1500 },
		{ ang = 6.0,  rad = 900,  h = 600  },
	}
	for i, s in ipairs(spires) do
		local base2D = Vector3.new(math.cos(s.ang) * s.rad, 0, math.sin(s.ang) * s.rad)
		local height = s.h
		local diameter = 90
		local spire = Instance.new("Part")
		spire.Name = "Spire" .. i
		spire.Anchored = true
		spire.Shape = Enum.PartType.Cylinder
		spire.Size = Vector3.new(height, diameter, diameter) -- cylinder long-axis is X; rotate upright
		spire.CFrame = CFrame.new(base2D + Vector3.new(0, height * 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		spire.Material = Enum.Material.Rock
		spire.Color = Color3.fromRGB(105, 100, 95)
		spire.Parent = map

		-- A flat perch cap on top of each spire.
		local perch = Instance.new("Part")
		perch.Name = "Perch" .. i
		perch.Anchored = true
		perch.Size = Vector3.new(diameter + 60, 12, diameter + 60)
		perch.Position = base2D + Vector3.new(0, height + 6, 0)
		perch.Material = Enum.Material.Slate
		perch.Color = Color3.fromRGB(85, 82, 80)
		perch.Parent = map
	end
end

-- Place thermals per GameConfig.Thermals; store for GetThermals.
local function CreateThermals()
	ThermalList = {}
	local cfg = GameConfig.Thermals
	local count = cfg.count or 6
	local ring = 3200 -- v3: spread thermals around the much bigger real-scale arena
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		table.insert(ThermalList, {
			position = pos,
			radius = cfg.radius,
			minHeight = cfg.minHeight,
			maxHeight = cfg.maxHeight,
			strength = cfg.strength,
		})
	end
end

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local function CreateRemotes()
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage

	local function event(name)
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
		return e
	end

	-- Exact canonical names other scripts depend on.
	event("TeamAssigned")     -- S->C: teamName, profile
	event("AttackRequest")    -- C->S
	event("TakeDamage")       -- S->C: attackerName, targetPlayer, damage
	event("ScoreUpdate")      -- S->C: scores
	event("GameNotification") -- S->C: text, color
	event("SwapCrow")         -- C->S: index
	event("SetFormation")     -- C->S: formationName
	event("Respawn")          -- C->S: request a fresh bird (manual reset; debounced)

	local getThermals = Instance.new("RemoteFunction") -- C->S -> thermal array
	getThermals.Name = "GetThermals"
	getThermals.OnServerInvoke = function()
		return ThermalList
	end
	getThermals.Parent = folder

	Remotes = folder
end

--------------------------------------------------------------------------------
-- NOTIFICATIONS / SCORE
--------------------------------------------------------------------------------
local function notify(text, color)
	if Remotes then
		Remotes.GameNotification:FireAllClients(text, color or Color3.fromRGB(255, 255, 255))
	end
end

local function pushScore()
	if Remotes then
		Remotes.ScoreUpdate:FireAllClients(Scores)
	end
end

--------------------------------------------------------------------------------
-- TEAM ASSIGNMENT
--------------------------------------------------------------------------------
-- Asymmetric: exactly ONE eagle exists; everyone else is a crow player.
local function countEagles()
	local n = 0
	for _, rec in pairs(PlayerData) do
		if rec.team == "Eagles" then n += 1 end
	end
	return n
end

local function pickTeamFor(player)
	-- First player (or whenever there is no living eagle) becomes the Eagle.
	if countEagles() < 1 then
		return "Eagles", "Eagle"
	end
	return "Crows", "Crow"
end

--------------------------------------------------------------------------------
-- BIRD SPAWNING
--------------------------------------------------------------------------------
local birdContainer -- Workspace folder holding all live bird models

local function ensureBirdContainer()
	if birdContainer and birdContainer.Parent then return birdContainer end
	local f = Workspace:FindFirstChild("Birds")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Birds"
		f.Parent = Workspace
	end
	birdContainer = f
	return f
end

-- Reusable RaycastParams for obstacle sweeps: ignore the entire Birds folder (a bird must
-- not "collide" with itself or other birds here — bird-vs-bird is processCollisions) so only
-- the Map (baseplate / spires / perches) reports. Built once the container exists.
local collisionParams
local function getCollisionParams()
	if not collisionParams then
		collisionParams = BirdCollision.makeParams(ensureBirdContainer())
	end
	return collisionParams
end

-- Build one bird model, register it, and position it at `spawnPos`.
local function spawnBird(player, team, profileName, spawnPos, isAI)
	local profile = GameConfig.Profiles[profileName]
	-- Build via BirdBuilder using the TEAM name so palette/species reads correctly,
	-- but pass the profile so sizes/radius match.
	local model = BirdBuilder.Build(profileName, profile)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then
		model:Destroy()
		return nil
	end

	-- Position & initial velocity (a little forward push so it starts flying).
	model:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	pcall(function()
		-- Spawn with cruise-ish energy, comfortably above stall speed (see FlightPhysics.new).
		body.AssemblyLinearVelocity = body.CFrame.LookVector * (profile.glideSpeed * 0.9)
	end)

	setHealth(body, profile.health)
	body:SetAttribute("MaxHealth", profile.health) -- lets the HUD compute a health ratio

	-- CLIENT CONTRACT (docs/HANDOFF.md): there is no Roblox Character, so the client
	-- finds and drives its bird by these attributes. Set them BEFORE parenting so they
	-- replicate together with the Model (the client's ChildAdded sees them immediately).
	model:SetAttribute("OwnerUserId", player and player.UserId or 0)
	model:SetAttribute("Team", team)
	model:SetAttribute("Possessed", not isAI)

	model.Parent = ensureBirdContainer()

	local entry = {
		model = model,
		body = body,
		player = player,
		team = team,
		profileName = profileName,
		profile = profile,
		isAI = isAI,
		possessed = not isAI,
		squad = nil,
		engine = nil,
		_lastPos = spawnPos, -- previous-frame position, for the authoritative crash sweep
	}

	-- AI birds are server-simulated: build a flight engine and take server ownership.
	if isAI then
		entry.engine = FlightPhysics.new(profile, spawnPos)
		entry.engine.orientation = body.CFrame
		setServerOwned(body)
	else
		-- Possessed bird: hand ownership to the controlling client.
		trySetNetworkOwner(body, player)
		markServerMove(entry)
	end

	Birds[model] = entry
	return entry
end

-- Spawn an Eagle player's single bird.
local function spawnEagle(player)
	local rec = PlayerData[player]
	if not rec then return end
	local spawnPos = Vector3.new(math.random(-1200, 1200), SPAWN_HEIGHT, math.random(-1200, 1200))
	local entry = spawnBird(player, "Eagles", "Eagle", spawnPos, false)
	if entry then
		rec.birds = { entry.model }
	end
end

-- Spawn a Crow player's squad of 4 (index 1 possessed, 2..4 AI).
local function spawnCrowSquad(player)
	local rec = PlayerData[player]
	if not rec then return end

	local center = Vector3.new(math.random(-1200, 1200), SPAWN_HEIGHT, math.random(-1200, 1200))
	local squad = {
		player = player,
		formationName = GameConfig.Squad.defaultFormation or "loose",
		possessedIndex = 1,
		members = {},
	}

	local size = GameConfig.Squad.size or 4
	for i = 1, size do
		-- Spread squad members out a bit around the center.
		local offset = Vector3.new((i - (size + 1) / 2) * 12, (i % 2) * 6, 0)
		local entry = spawnBird(player, "Crows", "Crow", center + offset, i ~= 1)
		if entry then
			entry.squad = squad
			table.insert(squad.members, entry.model)
		end
	end

	squad.possessedIndex = 1
	rec.squad = squad
	rec.birds = {}
	for _, m in ipairs(squad.members) do
		table.insert(rec.birds, m)
	end
	Squads[player] = squad
end

-- Spawn whatever this player's team needs.
local function spawnFor(player)
	local rec = PlayerData[player]
	if not rec then return end
	if rec.team == "Eagles" then
		spawnEagle(player)
	else
		spawnCrowSquad(player)
	end

	-- Tell the client its team + the matching profile.
	if Remotes then
		Remotes.TeamAssigned:FireClient(player, rec.team, rec.profile)
	end
end

-- Destroy all of a player's birds (used on death / round reset).
local function clearBirds(player)
	local rec = PlayerData[player]
	if not rec then return end
	for _, model in ipairs(rec.birds) do
		local entry = Birds[model]
		if entry then Birds[model] = nil end
		if model then pcall(function() model:Destroy() end) end
	end
	rec.birds = {}
	rec.squad = nil
	Squads[player] = nil
end

--------------------------------------------------------------------------------
-- COMBAT (server-authoritative)
--------------------------------------------------------------------------------
-- Spatial broad-phase shared by every proximity consumer (findNearestEnemy + processCollisions).
-- Rebuilt once per Heartbeat from living birds, so the per-pair sweep stays near-linear as the
-- swarm grows (queue #6a). Cell is much larger than any touch/engage radius, so a 3×3 cell scan
-- always covers the query — the callers still do the exact distance test (broad phase only).
local SPATIAL_CELL = 64
local birdIndex = SpatialHash.new(SPATIAL_CELL)

-- Largest body radius across profiles — the slack a collision broad-phase query needs so it
-- can't miss a large enemy at the edge of contact range.
local MAX_BODY_RADIUS = 0
for _, prof in pairs(GameConfig.Profiles) do
	MAX_BODY_RADIUS = math.max(MAX_BODY_RADIUS, prof.bodyRadius or 0)
end

local function rebuildBirdIndex()
	birdIndex:clear()
	for _, entry in pairs(Birds) do
		if isBirdAlive(entry) then
			birdIndex:insert(entry.body.Position, entry)
		end
	end
end

-- Lazy fallback so a player-triggered query (AttackRequest) before the first Heartbeat still
-- works. After the first populated Heartbeat the index is reused as-is (sub-frame staleness).
local function ensureBirdIndex()
	if next(birdIndex.buckets) == nil then
		rebuildBirdIndex()
	end
end

-- Find the nearest living ENEMY bird to `attackerEntry` within `maxRange` (grid broad-phase
-- + exact distance test inside SpatialHash:nearest).
local function findNearestEnemy(attackerEntry, maxRange)
	ensureBirdIndex()
	local team = attackerEntry.team
	return birdIndex:nearest(attackerEntry.body.Position, maxRange, function(entry)
		return entry.team ~= team and isBirdAlive(entry)
	end)
end

-- If a squad has no living possessed crow, promote the next living member so the
-- crow player keeps flying without a manual swap (also the seam for queue item #5).
-- The client re-acquires automatically off the "Possessed" attribute flip.
local function autoRepossess(squad)
	if not squad then return end
	local curModel = squad.members[squad.possessedIndex]
	local curEntry = curModel and Birds[curModel]
	if curEntry and curEntry.possessed and isBirdAlive(curEntry) then return end

	for idx, model in ipairs(squad.members) do
		local entry = Birds[model]
		if isBirdAlive(entry) then
			entry.possessed = true
			entry.isAI = false
			entry.engine = nil
			model:SetAttribute("Possessed", true)
			squad.possessedIndex = idx
			trySetNetworkOwner(entry.body, squad.player)
			markServerMove(entry)
			return
		end
	end
end

-- Apply damage to a bird; handle death + notifications. `attackerEntry` may be nil.
local function applyDamage(targetEntry, amount, attackerEntry, cause)
	if not isBirdAlive(targetEntry) then return end
	local hp = getHealth(targetEntry.body) - amount
	setHealth(targetEntry.body, hp)

	-- FX hook for clients.
	if Remotes then
		local attackerName = attackerEntry and attackerEntry.player and attackerEntry.player.Name or "World"
		Remotes.TakeDamage:FireAllClients(attackerName, targetEntry.player, amount)
	end

	if hp <= 0 then
		-- This bird is dead — remove its model. Round resolution checks player liveness.
		local victimName = targetEntry.player and targetEntry.player.Name or "A bird"
		local killerName = attackerEntry and attackerEntry.player and attackerEntry.player.Name or nil

		local deadSquad = targetEntry.squad
		local deadModel = targetEntry.model
		local deadPlayer = targetEntry.player
		Birds[deadModel] = nil
		pcall(function() deadModel:Destroy() end)

		-- Prune the dead model from the owner's birds list. Without this, rec.birds keeps a
		-- stale (destroyed) ref forever, so the solo-flight respawn check (#rec.birds == 0)
		-- never fires and the player is stuck unable to respawn — the reported bug.
		if deadPlayer then
			local rec = PlayerData[deadPlayer]
			if rec then
				for i = #rec.birds, 1, -1 do
					if rec.birds[i] == deadModel then table.remove(rec.birds, i) end
				end
			end
		end

		-- If a crow's possessed bird just died, hand control to a surviving squadmate.
		if deadSquad then
			autoRepossess(deadSquad)
		end

		if cause == "crash" then
			notify(victimName .. " crashed!", Color3.fromRGB(255, 140, 60))
		elseif cause == "collision" then
			notify(victimName .. " went down in a collision!", Color3.fromRGB(255, 140, 60))
		elseif killerName then
			notify(killerName .. " struck down a " .. targetEntry.profileName .. "!", Color3.fromRGB(255, 90, 90))
		end
	end
end

-- Handle an attack request from a client.
local function onAttackRequest(player)
	if not roundActive then return end
	local now = os.clock()
	if lastAttackAt[player] and (now - lastAttackAt[player]) < ATTACK_COOLDOWN then return end

	local attacker = getActiveBird(player)
	if not attacker then return end

	local p = attacker.profile
	-- Range = sum of body radii + buffer (target radius added per-candidate via nearest search;
	-- we use the largest plausible reach for the broad search then verify per-target).
	local maxReach = p.bodyRadius + ATTACK_BUFFER + 5 -- +5 covers the larger enemy radius
	local target, dist = findNearestEnemy(attacker, maxReach + 6)
	if not target then return end

	-- Precise reach check using the actual target radius.
	local reach = p.bodyRadius + target.profile.bodyRadius + ATTACK_BUFFER
	if dist > reach then return end

	lastAttackAt[player] = now

	-- Pick talon (heavy, needs proximity + alignment) vs beak (default peck).
	local body = attacker.body
	local toTarget = (target.body.Position - body.Position)
	local toTargetUnit = toTarget.Magnitude > 1e-3 and toTarget.Unit or body.CFrame.LookVector
	local align = body.CFrame.LookVector:Dot(toTargetUnit)

	local useTalon = (dist <= reach * TALON_RANGE_FRACTION) and (align >= TALON_ALIGN_DOT)
	local damage = useTalon and p.talonDamage or p.beakDamage

	-- Dive bonus: attacker is moving fast and dropping (a stoop).
	local vel = body.AssemblyLinearVelocity
	if vel.Magnitude >= DIVE_SPEED_THRESHOLD and vel.Y <= DIVE_VY_THRESHOLD then
		damage = damage * p.diveAttackMultiplier
	end

	applyDamage(target, damage, attacker, "attack")
end

--------------------------------------------------------------------------------
-- COLLISIONS (the signature lose-lose mechanic)
--------------------------------------------------------------------------------
-- Heartbeat proximity check between ENEMY birds. When two enemy bodies overlap at high
-- RELATIVE speed each bird RECEIVES the other's `collisionDamageDealt` (scaled by relative
-- speed), modified by its OWN `collisionDamageTaken` vulnerability multiplier. So a heavy
-- eagle shrugs off a single crow but four rams down it, while the fragile crow that rams it
-- dies in the trade — see the matchup math in GameConfig's collision comments.
-- TODO: deep balance tuning — the speed-scaling curve is still a first pass (queue item #3).
-- Target: ~4 full-speed crow rams kill an eagle while each ramming crow dies (a true trade).
local function processCollisions()
	local now = os.clock()

	-- Snapshot the outer set so applyDamage (which removes entries from Birds) can't corrupt a
	-- live `pairs(Birds)` iteration. The inner neighbor lookup uses the spatial grid built this
	-- Heartbeat — only birds in the few cells around `a` are considered, not every other bird.
	local list = {}
	for _, entry in pairs(Birds) do
		if isBirdAlive(entry) then
			list[#list + 1] = entry
		end
	end

	for _, a in ipairs(list) do
		if isBirdAlive(a) then
			local apos = a.body.Position
			local queryR = a.profile.bodyRadius + MAX_BODY_RADIUS
			birdIndex:forEachInRadius(apos, queryR, function(b)
				-- a may have died from an earlier pair this pass; bail if so.
				if not isBirdAlive(a) then return end
				if b == a or b.team == a.team or not isBirdAlive(b) then return end
				-- Handle each unordered pair exactly once per pass (replaces the old i<j guard):
				-- both `a` finding `b` and `b` finding `a` reach here, so let only one through.
				if tostring(a.model) >= tostring(b.model) then return end

				local bpos = b.body.Position
				local sep = (apos - bpos).Magnitude
				local touchDist = a.profile.bodyRadius + b.profile.bodyRadius
				if sep > touchDist then return end

				local key = pairKey(a.model, b.model)
				local last = lastCollisionAt[key]
				if last and (now - last) < COLLISION_COOLDOWN then return end

				-- Relative speed between the two bodies.
				local relSpeed = (a.body.AssemblyLinearVelocity - b.body.AssemblyLinearVelocity).Magnitude
				if relSpeed < COLLISION_SPEED_MIN then return end

				lastCollisionAt[key] = now
				-- Scale 0..1 from min->ref relative speed.
				local scale = math.clamp(
					(relSpeed - COLLISION_SPEED_MIN)
						/ math.max(1, (COLLISION_SPEED_REF - COLLISION_SPEED_MIN)),
					0, 1
				)
				-- Each bird RECEIVES the OTHER's collisionDamageDealt (scaled by relative speed),
				-- then modified by its OWN collisionDamageTaken vulnerability multiplier:
				--   eagle hit by crow:  30 * scale * 0.85  (≈26 full-speed -> ~4 rams kill it)
				--   crow  hit by eagle:  60 * scale * 1.40  (≈84 full-speed -> the crow dies)
				local aDmg = (b.profile.collisionDamageDealt * scale) * a.profile.collisionDamageTaken
				local bDmg = (a.profile.collisionDamageDealt * scale) * b.profile.collisionDamageTaken

				-- Apply to both; re-check B is alive in case A's hit cascaded a despawn.
				applyDamage(a, aDmg, b, "collision")
				if isBirdAlive(b) then
					applyDamage(b, bDmg, a, "collision")
				end
			end)
		end
	end
end

-- Authoritative crash detection. AI crows resolve their own collisions inline (updateAICrows),
-- but the possessed/eagle birds are CLIENT-owned — the server can't run their flight engine, so
-- it sweeps their replicated position delta each frame (Spherecast over last->current) and kills
-- on a high-speed map impact. Closing speed is measured from the SERVER-OBSERVED delta, not the
-- client's velocity (it's untrusted — ties into the anti-cheat philosophy). Plus a deep failsafe
-- so any bird that tunnels far below the world dies regardless.
local function processCrashes(dt)
	local params = getCollisionParams()
	local crashSpeed = GameConfig.Flight.CRASH_SPEED
	local invDt = 1 / math.max(dt, 1e-3)
	local doomed = {}
	for _, entry in pairs(Birds) do
		if isBirdAlive(entry) then
			local pos = entry.body.Position
			if pos.Y < GROUND_FAILSAFE_Y then
				table.insert(doomed, entry)
			elseif not entry.isAI and entry._lastPos then
				local observedVel = (pos - entry._lastPos) * invDt
				local _, _, crashed = BirdCollision.resolve(
					entry._lastPos, pos, observedVel, entry.profile.bodyRadius, params, crashSpeed
				)
				if crashed then table.insert(doomed, entry) end
			end
			entry._lastPos = pos
		end
	end
	for _, entry in ipairs(doomed) do
		if isBirdAlive(entry) then
			applyDamage(entry, getHealth(entry.body) + 1, nil, "crash")
		end
	end
end

--------------------------------------------------------------------------------
-- ANTI-CHEAT ENVELOPE (server-authoritative movement validation)
--------------------------------------------------------------------------------
-- The client OWNS its possessed bird's physics (SetNetworkOwner) for latency-free flight, so
-- the server cannot trust the CFrame/velocity it reads — a tampered client could fly at any
-- speed, teleport, or feed fake dive speeds to inflate stoop damage. We validate SERVER-OBSERVED
-- motion (position deltas, never client velocity) against a generous envelope:
--   • Teleport gate: a single-frame jump beyond TERMINAL×teleportMult (+ ping pad) → instant strike.
--   • Sustained-speed leaky bucket: observed speed over TERMINAL×speedAllowMult accumulates;
--     transient dive/lag spikes drain away, only a sustained hack overflows → strike.
-- Response ladder per player: rubber-band (snap to last good pos) every violation; reclaim
-- network ownership at reclaimStrikes; kick at kickStrikes. Strikes decay over clean time.
-- AI crows are server-simulated (trusted) and skipped. Legit server moves are whitelisted via
-- markServerMove (grace window + baseline reset). All knobs live in GameConfig.Security.
local function processAntiCheat(dt)
	local sec = GameConfig.Security
	if not sec or not sec.enabled then return end

	local now = os.clock()
	local invDt = 1 / math.max(dt, 1e-3)
	local terminal = GameConfig.Flight.TERMINAL_VELOCITY or 400
	local speedCeil = terminal * (sec.speedAllowMult or 1.25)
	local teleportStep = terminal * (sec.teleportMult or 1.5) * dt + (sec.pingPadStuds or 30)

	for _, entry in pairs(Birds) do
		if (not entry.isAI) and entry.player and isBirdAlive(entry) then
			local body = entry.body
			local pos = body.Position
			local rec = PlayerData[entry.player]

			-- Decay strikes after clean flight so an honest blip doesn't accrete to a kick.
			if rec and rec._acStrikes and rec._acStrikes > 0 then
				local elapsed = now - (rec._acStrikeAt or now)
				local forgive = math.floor(elapsed / (sec.strikeDecaySeconds or 12))
				if forgive >= 1 then
					rec._acStrikes = math.max(0, rec._acStrikes - forgive)
					rec._acStrikeAt = now
				end
			end

			if now < (entry._acGraceUntil or 0) or not entry._acLastPos then
				-- Whitelisted window or no baseline yet: (re)seed and skip checks this frame.
				entry._acLastPos = pos
				entry._acBucket = 0
			else
				local last = entry._acLastPos
				local moved = (pos - last).Magnitude
				local observed = moved * invDt
				local violated, reason = false, nil

				if moved > teleportStep then
					violated, reason = true, "teleport"
				else
					-- Leaky bucket on sustained over-speed.
					local over = observed - speedCeil
					local bucket = entry._acBucket or 0
					if over > 0 then
						bucket = bucket + over * dt
					else
						bucket = math.max(0, bucket - (sec.bucketLeak or 200) * dt)
					end
					entry._acBucket = bucket
					if bucket > (sec.bucketCapacity or 120) then
						violated, reason = true, "speed"
						entry._acBucket = 0
					end
				end

				if violated then
					-- RUBBER-BAND: snap back to the last good position (preserve orientation),
					-- zero velocity. Do NOT accept the bad position as the new baseline.
					pcall(function()
						local cf = body.CFrame
						body.CFrame = (cf - cf.Position) + last
						body.AssemblyLinearVelocity = Vector3.new()
					end)

					if rec then
						rec._acStrikes = (rec._acStrikes or 0) + 1
						rec._acStrikeAt = now
						local s = rec._acStrikes
						warn(string.format(
							"[AntiCheat] %s strike %d (%s): observed %.0f studs/s (ceil %.0f)",
							entry.player.Name, s, reason, observed, speedCeil))
						if s >= (sec.kickStrikes or 6) then
							pcall(function() entry.player:Kick("Movement validation failed.") end)
						elseif s >= (sec.reclaimStrikes or 3) then
							-- Reclaim authority: the client can no longer drive this body.
							setServerOwned(body)
						end
					end
				else
					entry._acLastPos = pos
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- AI CROWS (server-simulated; the 3 non-possessed members of each squad)
--------------------------------------------------------------------------------
-- Thermal lift at a position, sampled from ThermalList. MUST match BirdController's client
-- computeThermalForce so AI crows ride thermals identically to the possessed (client-driven)
-- crow — otherwise the server-simulated squadmates can't recover energy, sink, and crash,
-- skewing the 1-eagle-vs-4-crow matchup (flight == balance).
local function thermalForceAt(position)
	local force = Vector3.new()
	for _, t in ipairs(ThermalList) do
		if t and t.position then
			local dist = (Vector3.new(position.X, 0, position.Z)
				- Vector3.new(t.position.X, 0, t.position.Z)).Magnitude
			local minH, maxH, radius = t.minHeight or 0, t.maxHeight or math.huge, t.radius or 0
			if radius > 0 and dist < radius and position.Y > minH and position.Y < maxH then
				local centerFactor = 1 - (dist / radius)
				local mid = (minH + maxH) * 0.5
				local span = math.max(1, maxH - minH)
				local heightFactor = math.clamp(1 - math.abs((position.Y - mid) / span), 0, 1)
				force = force + Vector3.new(0, (t.strength or 0) * centerFactor * heightFactor, 0)
			end
		end
	end
	return force
end

-- Find the squad's goal point: the possessed crow, or its nearest enemy when engaging.
local function squadGoal(squad)
	local possessedModel = squad.members[squad.possessedIndex]
	local possessed = possessedModel and Birds[possessedModel]
	if not possessed or not isBirdAlive(possessed) then
		-- Possessed is gone; fall back to first living member as the rally point.
		for _, m in ipairs(squad.members) do
			local e = Birds[m]
			if isBirdAlive(e) then possessed = e break end
		end
	end
	if not possessed then return nil end

	local goal = possessed.body.Position
	-- If an enemy is within engageRadius of the possessed crow, converge on it.
	local enemy = findNearestEnemy(possessed, GameConfig.Squad.engageRadius)
	if enemy then
		goal = enemy.body.Position
	end
	return goal, possessed
end

-- Build the neighbor list (other living squad members) for boids.
local function squadNeighbors(squad, selfEntry)
	local neighbors = {}
	for _, m in ipairs(squad.members) do
		local e = Birds[m]
		if e and e ~= selfEntry and isBirdAlive(e) then
			table.insert(neighbors, {
				position = e.body.Position,
				velocity = e.body.AssemblyLinearVelocity,
			})
		end
	end
	return neighbors
end

-- Step every AI crow once per Heartbeat: boids -> input -> light flight step -> apply.
local function updateAICrows(dt)
	local fdt = math.min(dt, AI_HEARTBEAT_DT_CAP)
	local formations = GameConfig.Squad.formations

	for _, squad in pairs(Squads) do
		local goal = squadGoal(squad)
		local formationCfg = formations[squad.formationName] or formations.loose

		for idx, model in ipairs(squad.members) do
			local entry = Birds[model]
			if entry and entry.isAI and isBirdAlive(entry) and entry.engine then
				local body = entry.body
				-- Keep the engine's notion of state synced with the actual part each step
				-- (the part is the source of truth; the engine integrates from it).
				entry.engine.orientation = body.CFrame
				entry.engine.velocity = body.AssemblyLinearVelocity

				local selfState = {
					position = body.Position,
					velocity = body.AssemblyLinearVelocity,
				}
				local neighbors = squadNeighbors(squad, entry)
				local steer = Boids.computeSteering(selfState, neighbors, goal, formationCfg)
				local input = Boids.steeringToInput(body.CFrame, body.AssemblyLinearVelocity, steer, entry.profile)

				-- Run the SAME flight engine the player uses, then write the result back
				-- to the server-owned part (server simulates these birds).
				entry.engine:SetThermalForce(thermalForceAt(body.Position))
				local fromPos = body.Position
				entry.engine:Update(fdt, input)

				-- Obstacle/ground collision: sweep the step. AI crows are server-owned, so we
				-- resolve here directly — a head-on map impact crashes the crow, a graze slides
				-- it along the surface (engine velocity is server-trusted; use it for the gate).
				local toPos = entry.engine.orientation.Position
				local newPos, newVel, crashed = BirdCollision.resolve(
					fromPos, toPos, entry.engine.velocity, entry.profile.bodyRadius,
					getCollisionParams(), GameConfig.Flight.CRASH_SPEED
				)
				if crashed then
					applyDamage(entry, getHealth(body) + 1, nil, "crash")
				else
					if (newPos - toPos).Magnitude > 1e-3 then
						-- Re-seat the engine at the slid position (keep its rotation) + slid velocity.
						local cf = entry.engine.orientation
						entry.engine.orientation = (cf - cf.Position) + newPos
						entry.engine.velocity = newVel
					end
					pcall(function()
						body.CFrame = entry.engine.orientation
						body.AssemblyLinearVelocity = entry.engine.velocity
						body.AssemblyAngularVelocity = Vector3.new()
					end)

					-- Animate wings to match the AI state.
					BirdBuilder.AnimateWings(entry.model, entry.engine.isFlapping, entry.engine.isDiving, entry.engine.flapPhase, fdt)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- SQUAD COMMANDS: SwapCrow + SetFormation
--------------------------------------------------------------------------------
-- Re-point possession to crow `index`: that one becomes client-owned, the previous
-- possessed becomes a server-simulated AI.
local function onSwapCrow(player, index)
	local squad = Squads[player]
	if not squad then return end
	index = tonumber(index)
	if not index then return end
	if index < 1 or index > #squad.members then return end

	-- Anti-spam cooldown.
	local now = os.clock()
	local cd = GameConfig.Squad.swapCooldown or 0.35
	if lastSwapAt[player] and (now - lastSwapAt[player]) < cd then return end

	local targetModel = squad.members[index]
	local targetEntry = targetModel and Birds[targetModel]
	if not isBirdAlive(targetEntry) then return end
	if index == squad.possessedIndex then return end

	lastSwapAt[player] = now

	-- Demote the currently possessed crow -> AI.
	local prevModel = squad.members[squad.possessedIndex]
	local prevEntry = prevModel and Birds[prevModel]
	if prevEntry and isBirdAlive(prevEntry) then
		prevEntry.possessed = false
		prevEntry.isAI = true
		if not prevEntry.engine then
			prevEntry.engine = FlightPhysics.new(prevEntry.profile, prevEntry.body.Position)
		end
		prevEntry.engine.orientation = prevEntry.body.CFrame
		prevEntry.engine.velocity = prevEntry.body.AssemblyLinearVelocity
		setServerOwned(prevEntry.body)
		prevModel:SetAttribute("Possessed", false)
	end

	-- Promote the target -> possessed/client-owned.
	targetEntry.possessed = true
	targetEntry.isAI = false
	targetEntry.engine = nil
	targetModel:SetAttribute("Possessed", true)
	squad.possessedIndex = index
	trySetNetworkOwner(targetEntry.body, player)
	markServerMove(targetEntry)

	-- The demoted crow is now server-simulated; reset its AC baseline too (it changed owner).
	if prevEntry then markServerMove(prevEntry) end

	notify(player.Name .. " swapped crow", GameConfig.UI and GameConfig.UI.crowAccent)
end

-- Manual self-respawn: clear the player's birds and spawn a fresh set. Lets a player who
-- crashed or got stuck reset without leaving the game (there is no Roblox-character reset
-- because CharacterAutoLoads=false). Debounced. In a live scored round this is effectively a
-- free reset — fine for v1 testing; gate or cost it once competitive rounds matter (TODO).
local function onRespawn(player)
	local rec = PlayerData[player]
	if not rec then return end
	local now = os.clock()
	if lastRespawnAt[player] and (now - lastRespawnAt[player]) < RESPAWN_COOLDOWN then return end
	lastRespawnAt[player] = now
	clearBirds(player)
	spawnFor(player)
end

-- Store the squad's formation (tight/loose). Validated against config.
local function onSetFormation(player, formationName)
	local squad = Squads[player]
	if not squad then return end
	if type(formationName) ~= "string" then return end
	if not GameConfig.Squad.formations[formationName] then return end
	squad.formationName = formationName
end

--------------------------------------------------------------------------------
-- ROUND RESOLUTION
--------------------------------------------------------------------------------
-- A crow player is alive while >=1 of their crows live; eagle alive while its bird lives.
local function isPlayerAlive(player)
	local rec = PlayerData[player]
	if not rec then return false end
	for _, model in ipairs(rec.birds) do
		if isBirdAlive(Birds[model]) then return true end
	end
	return false
end

local function anyEagleAlive()
	for _, rec in pairs(PlayerData) do
		if rec.team == "Eagles" and isPlayerAlive(rec.player) then return true end
	end
	return false
end

local function anyCrowAlive()
	for _, rec in pairs(PlayerData) do
		if rec.team == "Crows" and isPlayerAlive(rec.player) then return true end
	end
	return false
end

local function eaglesExist()
	for _, rec in pairs(PlayerData) do
		if rec.team == "Eagles" then return true end
	end
	return false
end

local function crowsExist()
	for _, rec in pairs(PlayerData) do
		if rec.team == "Crows" then return true end
	end
	return false
end

-- Keep exactly one Eagle in the match. If the lone Eagle player leaves, the round loop
-- would otherwise wait forever (eaglesExist() == false) even with a full lobby of crows —
-- the match dead-ends. Promote a crow player to the Eagle so play continues. Re-fires their
-- TeamAssigned (new profile) and re-spawns them as an eagle if a round is live.
local function promoteToEagleIfNeeded()
	if eaglesExist() then return end
	for _, rec in pairs(PlayerData) do
		if rec.team == "Crows" then
			clearBirds(rec.player)
			rec.team = "Eagles"
			rec.profileName = "Eagle"
			rec.profile = GameConfig.Profiles.Eagle
			if roundActive then
				spawnFor(rec.player) -- spawnFor also re-fires TeamAssigned
			elseif Remotes then
				Remotes.TeamAssigned:FireClient(rec.player, rec.team, rec.profile)
			end
			notify(rec.player.Name .. " is now the Eagle!", GameConfig.UI and GameConfig.UI.eagleAccent)
			return
		end
	end
end

--------------------------------------------------------------------------------
-- ROUND LOOP
--------------------------------------------------------------------------------
local function startRound()
	-- Fresh spawn for everyone present.
	for _, rec in pairs(PlayerData) do
		clearBirds(rec.player)
	end
	for _, rec in pairs(PlayerData) do
		spawnFor(rec.player)
	end
	roundActive = true
	notify("Round start!", Color3.fromRGB(120, 220, 255))
end

local function resolveRound(reason)
	roundActive = false
	if reason == "eagleDown" then
		Scores.Crows += 1
		notify("Crows win the round!", GameConfig.UI and GameConfig.UI.crowAccent)
	elseif reason == "crowsDown" then
		Scores.Eagles += 1
		notify("Eagle wins the round!", GameConfig.UI and GameConfig.UI.eagleAccent)
	else
		notify("Round over.", Color3.fromRGB(220, 220, 220))
	end
	pushScore()
end

local function RoundLoop()
	local R = GameConfig.Round
	while true do
		-- Only run a scored round when both sides can actually be fielded.
		if eaglesExist() and crowsExist() then
			-- INTERMISSION before the round.
			roundActive = false
			notify("Intermission…", Color3.fromRGB(200, 200, 200))
			pushScore()
			task.wait(R.intermission or 8)

			-- A player may have left during intermission — re-check before spawning.
			if not (eaglesExist() and crowsExist()) then
				continue
			end

			startRound()

			-- ROUND: run until a win condition or the timer expires.
			local elapsed = 0
			local roundLen = R.roundLength or 240
			local result = "timeout"
			while elapsed < roundLen do
				task.wait(1)
				elapsed += 1
				if not roundActive then break end
				if not anyEagleAlive() then result = "eagleDown" break end
				if not anyCrowAlive() then result = "crowsDown" break end
			end

			resolveRound(result)

			-- RESPAWN / cleanup before next intermission.
			task.wait(R.respawnDelay or 4)
			for _, rec in pairs(PlayerData) do
				clearBirds(rec.player)
			end
		elseif GameConfig.Debug and GameConfig.Debug.soloFlight and next(PlayerData) ~= nil then
			-- DEBUG free-flight: not enough players for a scored match, but let whoever is
			-- present spawn and fly (AI crows + possession included) so the whole stack can be
			-- smoke-tested with a single client. Transitions into a real match when a second
			-- team joins (the both-exist branch above then clears & respawns everyone).
			for _, rec in pairs(PlayerData) do
				-- Respawn anyone with no LIVING bird (first spawn, or after a crash/death).
				-- Keying off isPlayerAlive (not #rec.birds) is what makes solo respawn actually
				-- fire — a dead crow squad has all members destroyed; a crashed eagle has none.
				if not isPlayerAlive(rec.player) then
					clearBirds(rec.player) -- purge any leftover/destroyed refs first
					spawnFor(rec.player)
				end
			end
			roundActive = true -- enable AI-crow sim + collisions for solo testing
			task.wait(2)
		else
			roundActive = false
			notify("Waiting for an Eagle and a Crow…", Color3.fromRGB(220, 220, 120))
			task.wait(2)
		end
	end
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
	local team, profileName = pickTeamFor(player)
	PlayerData[player] = {
		player = player,
		team = team,
		profileName = profileName,
		profile = GameConfig.Profiles[profileName],
		birds = {},
		squad = nil,
	}

	-- We do NOT use Roblox characters for flight; suppress the default avatar so the
	-- bird model is the player's representation. (Client camera follows the bird.)
	pcall(function() player.CharacterAutoLoads = false end)

	-- If a round is live, drop them in immediately; otherwise the loop spawns them.
	if roundActive then
		spawnFor(player)
	else
		-- Still tell them their team/profile so the HUD updates during intermission.
		if Remotes then
			Remotes.TeamAssigned:FireClient(player, team, PlayerData[player].profile)
		end
	end
	pushScore()
end

local function onPlayerRemoving(player)
	local wasEagle = PlayerData[player] and PlayerData[player].team == "Eagles"
	clearBirds(player)
	PlayerData[player] = nil
	lastAttackAt[player] = nil
	lastSwapAt[player] = nil
	lastRespawnAt[player] = nil
	Squads[player] = nil

	-- If the Eagle just left, hand the role to a remaining crow so the match continues
	-- instead of stalling on "Waiting for an Eagle…" with a full lobby of crows.
	if wasEagle then
		promoteToEagleIfNeeded()
	end
end

--------------------------------------------------------------------------------
-- WIRE UP REMOTE HANDLERS (after Remotes folder exists)
--------------------------------------------------------------------------------
local function connectRemotes()
	Remotes.AttackRequest.OnServerEvent:Connect(function(player)
		pcall(onAttackRequest, player)
	end)
	Remotes.SwapCrow.OnServerEvent:Connect(function(player, index)
		pcall(onSwapCrow, player, index)
	end)
	Remotes.SetFormation.OnServerEvent:Connect(function(player, formationName)
		pcall(onSetFormation, player, formationName)
	end)
	Remotes.Respawn.OnServerEvent:Connect(function(player)
		pcall(onRespawn, player)
	end)
end

--------------------------------------------------------------------------------
-- HEARTBEAT: collisions + AI, every frame the round is active.
--------------------------------------------------------------------------------
local function onHeartbeat(dt)
	if not roundActive then return end
	-- Rebuild the spatial broad-phase once, up front, so every proximity consumer this frame
	-- (squad targeting in updateAICrows, processCollisions) shares one near-linear index.
	rebuildBirdIndex()
	-- AI flight for server-owned crows.
	pcall(updateAICrows, dt)
	-- Anti-cheat movement validation (before crash sweep, so a rubber-band corrects the
	-- position the crash check then reads).
	pcall(processAntiCheat, dt)
	-- Signature collisions.
	pcall(processCollisions)
	-- Obstacle/ground crash deaths (feeds the respawn loop).
	pcall(processCrashes, dt)
end

--------------------------------------------------------------------------------
-- INITIALIZATION  (call order matters; everything below runs once at startup)
--------------------------------------------------------------------------------
SetupLighting()
BuildMap()
CreateThermals()
CreateRemotes()
connectRemotes()

-- Players already present (Studio play-solo edge case) + future joiners.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

RunService.Heartbeat:Connect(onHeartbeat)

-- Start the round loop.
task.spawn(RoundLoop)

print("Eagles vs Crows server initialized.")
