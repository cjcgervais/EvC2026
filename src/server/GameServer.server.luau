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
local SPAWN_HEIGHT           = 250    -- default spawn altitude

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

-- The "active"/possessed bird Model a player currently controls (for attacks).
local function getActiveBird(player)
	local rec = PlayerData[player]
	if not rec then return nil end
	for _, model in ipairs(rec.birds) do
		local entry = Birds[model]
		if entry and entry.possessed and isBirdAlive(entry) then
			return entry
		end
	end
	-- Fallback: first living bird.
	for _, model in ipairs(rec.birds) do
		local entry = Birds[model]
		if isBirdAlive(entry) then return entry end
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
		end
	end)
end

-- Server-owned AI birds: clear ownership so the SERVER simulates them.
local function setServerOwned(body)
	if not body then return end
	pcall(function()
		if not body.Anchored and body:CanSetNetworkOwnership() then
			body:SetNetworkOwner(nil) -- nil = server authority
		end
	end)
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
	Lighting.FogEnd = 4000
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

-- Build a simple but real arena: a large baseplate + a few spires/perches.
local function BuildMap()
	local map = Workspace:FindFirstChild("Map")
	if map then map:Destroy() end
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	-- Large baseplate.
	local base = Instance.new("Part")
	base.Name = "Baseplate"
	base.Anchored = true
	base.Size = Vector3.new(4000, 20, 4000)
	base.Position = Vector3.new(0, -10, 0)
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(70, 110, 60)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = map

	-- A scatter of tall spires acting as perches / hazards to fly around.
	local spires = {
		Vector3.new(0, 0, 0),
		Vector3.new(600, 0, 400),
		Vector3.new(-550, 0, 300),
		Vector3.new(350, 0, -600),
		Vector3.new(-400, 0, -500),
		Vector3.new(900, 0, -200),
		Vector3.new(-850, 0, -150),
	}
	for i, base2D in ipairs(spires) do
		local height = 220 + (i % 3) * 90
		local spire = Instance.new("Part")
		spire.Name = "Spire" .. i
		spire.Anchored = true
		spire.Shape = Enum.PartType.Cylinder
		spire.Size = Vector3.new(height, 40, 40) -- cylinder long-axis is X; rotate upright
		spire.CFrame = CFrame.new(base2D + Vector3.new(0, height * 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		spire.Material = Enum.Material.Rock
		spire.Color = Color3.fromRGB(105, 100, 95)
		spire.Parent = map

		-- A flat perch cap on top of each spire.
		local perch = Instance.new("Part")
		perch.Name = "Perch" .. i
		perch.Anchored = true
		perch.Size = Vector3.new(70, 8, 70)
		perch.Position = base2D + Vector3.new(0, height + 4, 0)
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
	local ring = 900 -- spread thermals around the arena
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
		body.AssemblyLinearVelocity = body.CFrame.LookVector * (profile.glideSpeed * 0.6)
	end)

	setHealth(body, profile.health)

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
	}

	-- AI birds are server-simulated: build a flight engine and take server ownership.
	if isAI then
		entry.engine = FlightPhysics.new(profile, spawnPos)
		entry.engine.orientation = body.CFrame
		setServerOwned(body)
	else
		-- Possessed bird: hand ownership to the controlling client.
		trySetNetworkOwner(body, player)
	end

	Birds[model] = entry
	return entry
end

-- Spawn an Eagle player's single bird.
local function spawnEagle(player)
	local rec = PlayerData[player]
	if not rec then return end
	local spawnPos = Vector3.new(math.random(-300, 300), SPAWN_HEIGHT, math.random(-300, 300))
	local entry = spawnBird(player, "Eagles", "Eagle", spawnPos, false)
	if entry then
		rec.birds = { entry.model }
	end
end

-- Spawn a Crow player's squad of 4 (index 1 possessed, 2..4 AI).
local function spawnCrowSquad(player)
	local rec = PlayerData[player]
	if not rec then return end

	local center = Vector3.new(math.random(-300, 300), SPAWN_HEIGHT, math.random(-300, 300))
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
-- Find the nearest living ENEMY bird to `attackerEntry` within `maxRange`.
local function findNearestEnemy(attackerEntry, maxRange)
	local best, bestDist
	local aPos = attackerEntry.body.Position
	for model, entry in pairs(Birds) do
		if entry.team ~= attackerEntry.team and isBirdAlive(entry) then
			local d = (entry.body.Position - aPos).Magnitude
			if d <= maxRange and (not bestDist or d < bestDist) then
				best, bestDist = entry, d
			end
		end
	end
	return best, bestDist
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

		Birds[targetEntry.model] = nil
		pcall(function() targetEntry.model:Destroy() end)

		if cause == "collision" then
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
-- Heartbeat proximity check between ENEMY birds. When two enemy bodies overlap at
-- high RELATIVE speed, each deals collisionDamageDealt (scaled by relative speed) to
-- the other, and each also suffers collisionDamageTaken * (its own dealt) of self-harm.
-- TODO: deep balance tuning — the exact scaling curve below is a first pass. Target:
-- ~4 full-speed crow rams kill an eagle while each ramming crow dies (a true trade).
local function processCollisions()
	-- Snapshot living birds so we can index pairwise.
	local list = {}
	for _, entry in pairs(Birds) do
		if isBirdAlive(entry) then
			table.insert(list, entry)
		end
	end

	local now = os.clock()
	for i = 1, #list do
		local a = list[i]
		if isBirdAlive(a) then
			for j = i + 1, #list do
				local b = list[j]
				if isBirdAlive(a) and isBirdAlive(b) and a.team ~= b.team then
					local apos = a.body.Position
					local bpos = b.body.Position
					local sep = (apos - bpos).Magnitude
					local touchDist = a.profile.bodyRadius + b.profile.bodyRadius
					if sep <= touchDist then
						local key = pairKey(a.model, b.model)
						local last = lastCollisionAt[key]
						if not last or (now - last) >= COLLISION_COOLDOWN then
							-- Relative speed between the two bodies.
							local av = a.body.AssemblyLinearVelocity
							local bv = b.body.AssemblyLinearVelocity
							local relSpeed = (av - bv).Magnitude
							if relSpeed >= COLLISION_SPEED_MIN then
								lastCollisionAt[key] = now
								-- Scale 0..1 from min->ref relative speed.
								local scale = math.clamp(
									(relSpeed - COLLISION_SPEED_MIN)
										/ math.max(1, (COLLISION_SPEED_REF - COLLISION_SPEED_MIN)),
									0, 1
								)
								-- Each deals its profile's collision damage * scale to the other.
								local aDeals = a.profile.collisionDamageDealt * scale
								local bDeals = b.profile.collisionDamageDealt * scale
								-- Each also takes a fraction of its OWN dealt damage (self-harm).
								local aSelf = aDeals * a.profile.collisionDamageTaken
								local bSelf = bDeals * b.profile.collisionDamageTaken

								-- Apply: A receives B's dealt + A's self; B receives A's dealt + B's self.
								applyDamage(a, bDeals + aSelf, b, "collision")
								if isBirdAlive(b) then
									applyDamage(b, aDeals + bSelf, a, "collision")
								end
							end
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- AI CROWS (server-simulated; the 3 non-possessed members of each squad)
--------------------------------------------------------------------------------
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
				entry.engine:Update(fdt, input)
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
	end

	-- Promote the target -> possessed/client-owned.
	targetEntry.possessed = true
	targetEntry.isAI = false
	targetEntry.engine = nil
	squad.possessedIndex = index
	trySetNetworkOwner(targetEntry.body, player)

	notify(player.Name .. " swapped crow", GameConfig.UI and GameConfig.UI.crowAccent)
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
		-- INTERMISSION
		roundActive = false
		notify("Intermission…", Color3.fromRGB(200, 200, 200))
		pushScore()
		task.wait(R.intermission or 8)

		-- Only run a round if both sides can be fielded.
		if eaglesExist() and crowsExist() then
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
		else
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
	clearBirds(player)
	PlayerData[player] = nil
	lastAttackAt[player] = nil
	lastSwapAt[player] = nil
	Squads[player] = nil
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
end

--------------------------------------------------------------------------------
-- HEARTBEAT: collisions + AI, every frame the round is active.
--------------------------------------------------------------------------------
local function onHeartbeat(dt)
	if not roundActive then return end
	-- AI flight for server-owned crows.
	pcall(updateAICrows, dt)
	-- Signature collisions.
	pcall(processCollisions)
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
