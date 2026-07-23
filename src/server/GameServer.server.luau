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
local GroundDetail   = require(ReplicatedStorage:WaitForChild("GroundDetail"))
local WorldGen       = require(ReplicatedStorage:WaitForChild("WorldGen"))

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
-- Spawn LOW (≈600 studs ≈ 170 m AGL) so the ground and the spires are right there as spatial
-- reference and reachable obstacles — Chad at 2000 reported "no floor to the map and nothing to
-- collide with" (the floor was a distant speck 2000 studs down and the spires were far below).
-- The energy game is to CLIMB from here into the tall sky (~6500 studs of headroom to the 7143
-- ceiling) and stoop back down — spawning mid-void skipped that. The 16k world is still wide-open
-- so this does NOT reintroduce "too easy to crash" (that was the old cramped 520-ceiling map).
local SPAWN_HEIGHT           = 600    -- default spawn altitude (studs)
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
-- squad = { player, formationName, possessedIndex, members = {Model,...}, aggressive = bool }
local Squads = {}

-- Solo-test AI crow squad (no human owner). Keyed in `Squads` under this sentinel so
-- updateAICrows steps it like any other squad. See GameConfig.Debug.aiCrowOpponents.
local BOT_SQUAD_KEY = "__BOT_CROWS__"

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
	-- BRIGHT, HIGH-CONTRAST midday sky tuned so distant terrain/landmarks render crisply for the
	-- OODA read (Chad): low atmosphere density + ColorCorrection contrast = legible features far out.
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(120, 132, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(155, 165, 185)
	Lighting.FogEnd = 1e6 -- Atmosphere governs view distance; keep classic fog from clipping far features
	Lighting.FogColor = Color3.fromRGB(190, 208, 230)
	Lighting.GeographicLatitude = 25
	Lighting.ShadowSoftness = 0.2

	-- VERY LOW density so you can SEE THE WHOLE ENVIRONMENT FROM FAR AWAY (player ask 2026-06-30: "increase
	-- render distance big time"). Atmosphere density is the real view-distance limiter here (FogEnd is already
	-- off at 1e6, and with StreamingEnabled = false every part renders) — it hazes distant parts to the sky
	-- colour, so a high value reads as a short render distance. Dropped 0.18 → 0.05 + Haze 0.6 → 0.12 so the
	-- perimeter mountain ring (R≈6600) and the far map edges stay crisp from across the 16k arena. Keep a
	-- whisper for aerial-perspective depth so distance still reads (it hazes the far peak ring R≈7400 bluer —
	-- the intended depth cue). Raise toward 0.1 if the far edge looks bare; lower if the far peaks read too soft.
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.03  -- "EAGLE VISION" — even thinner so distant terrain reads from across the whole arena
	atmo.Offset = 0.1
	atmo.Haze = 0.07
	atmo.Glare = 0.1
	atmo.Color = Color3.fromRGB(210, 222, 240)
	atmo.Decay = Color3.fromRGB(120, 150, 190)
	atmo.Parent = Lighting

	-- Higher contrast + a touch more saturation = features pop and read at a glance (OODA).
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.03
	cc.Contrast = 0.18
	cc.Saturation = 0.12
	cc.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

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
-- v4 ENVIRONMENT (Chad: real terrain mountains/canyons + scale/OODA reference, bright & high
-- contrast so it renders far). Built from LARGE anchored parts (not voxel Terrain) so distant
-- features never LOD-cull, colours are fully controllable for contrast/orientation, and there is
-- zero per-voxel loop (build-safe). Bounded ~26 parts. World-bounds stay soft (a mountain ring you
-- can see the edge of, not hard walls). AI crows now steer around all of it (queue #8 avoidance).
local function BuildMap()
	-- Keep the Roblox engine's own gravity coherent with the flight model's (birds are CFrame-driven
	-- so they read GameConfig.Flight.GRAVITY directly, but this keeps debris/landings/ragdolls sane).
	Workspace.Gravity = GameConfig.Flight.GRAVITY

	-- STREAMING OFF (fixes "the eagle doesn't render when I zoom out" + lets the whole environment render
	-- far away). With CharacterAutoLoads = false there's NO character, so StreamingEnabled uses the CAMERA as
	-- the replication focus — a far zoomed-out camera then streams the (now distant) eagle + map OUT until you
	-- zoom back in. The arena is only ~26 anchored parts + a handful of birds, so streaming buys nothing here.
	-- Baked false in default.project.json too; this runtime set is the belt-and-suspenders for a live serve.
	pcall(function() Workspace.StreamingEnabled = false end)

	local map = Workspace:FindFirstChild("Map")
	if map then map:Destroy() end
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	local cheapScenery = not (GameConfig.Map and GameConfig.Map.cheapScenery == false)

	local function addPart(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		-- S45c — CONVICTED CAUSE of "everything renders in so slow". The probe proved every part is on
		-- the client at t=1s and simply not DRAWN; Chad then set graphics to Manual/max and it was fixed.
		-- That is quality-scaled render distance: Roblox's Automatic mode throttles how far it draws
		-- based on the frame budget, so the cure is to stop spending the budget. This line is the single
		-- biggest item — `addPart` never cleared CastShadow, so all 78 Map parts cast shadows, including
		-- a 16,000-stud baseplate and 45 mountains up to 3,400 tall. RescueServer's own builder has ALWAYS
		-- set CastShadow=false on every part it makes, so the trees already cast nothing: this was an
		-- INCONSISTENCY, not an art choice — the world has no shadow vocabulary for these to join.
		-- Set BEFORE the props loop so an explicit CastShadow in props still wins.
		if cheapScenery then p.CastShadow = false end
		for k, v in pairs(props) do p[k] = v end
		p.Parent = map
		return p
	end

	-- GROUND: vast, brighter, higher-contrast floor (≈4.5 km square at 0.28 m/stud). Top sits at Y=0.
	addPart({
		Name = "Baseplate", Size = Vector3.new(16000, 40, 16000),
		Position = Vector3.new(0, -20, 0), Material = Enum.Material.Grass,
		Color = Color3.fromRGB(96, 142, 74),
	})

	-- A distant SEA beyond the western mountains — a real coastline/horizon for "I can see where I'm flying"
	-- depth. A huge thin water plane PAST the ring so it reads as the edge of the world without touching combat.
	-- S45c: this is a 6,000 × 18,000 stud plane — 108 MILLION square studs of GLASS with Reflectance,
	-- i.e. a transparent, reflective surface spanning the whole western horizon that the GPU blends
	-- every frame you can see it (which, from 600 studs up, is always). Glass is among the most
	-- expensive materials Roblox has. At 11,000 studs away it reads as "ocean" regardless, so
	-- SmoothPlastic at the same colour is visually ~identical and costs a fraction. Second-biggest item
	-- on the quality-throttle list after shadows. Revert: Map.cheapScenery = false.
	addPart({ Name = "Sea", Size = Vector3.new(6000, 14, 18000), Position = Vector3.new(-11000, -4, 0),
		Material = cheapScenery and Enum.Material.SmoothPlastic or Enum.Material.Glass,
		Color = Color3.fromRGB(48, 104, 168),
		Transparency = cheapScenery and 0 or 0.18,
		Reflectance = cheapScenery and 0 or 0.25 })

	-- GROUND COLOUR PATCHES (thin, at Y≈1): break up the uniform grass so altitude/speed/heading read at a
	-- glance from far up (a flat green plain gives no perspective cue). Deterministic; all clear of the ±1200 core.
	local patches = {
		{ n = "Forest",    x = -2600, z = -3400, w = 2800, l = 2200, c = Color3.fromRGB(54, 96, 58),   m = Enum.Material.Grass },
		{ n = "Plateau",   x =  4200, z =  2600, w = 3000, l = 2400, c = Color3.fromRGB(168, 150, 104), m = Enum.Material.Ground },
		{ n = "Snowfield", x = -1200, z =  5200, w = 3200, l = 2600, c = Color3.fromRGB(226, 232, 240), m = Enum.Material.Snow },
		{ n = "Marsh",     x =  2400, z = -4600, w = 2200, l = 2000, c = Color3.fromRGB(86, 120, 92),   m = Enum.Material.LeafyGrass },
	}
	for _, p in ipairs(patches) do
		addPart({ Name = p.n, Size = Vector3.new(p.w, 6, p.l), Position = Vector3.new(p.x, 1, p.z),
			Material = p.m, Color = p.c })
	end

	-- CORE GROUND DETAIL (S45) — the cure, applied where the patient actually is. Every block above and
	-- below this one is explicitly "clear of the ±1200 spawn core", which left the box the player flies
	-- in a uniform plane with NO closure cue — Chad flew into it repeatedly. GroundDetail returns a
	-- deterministic multi-scale scatter; each patch is non-queryable so BirdCollision's Spherecast
	-- cannot see it and the crash surface stays exactly the baseplate. Kill switch: Map.coreDetail.
	for _, d in ipairs(GroundDetail.patches(GameConfig.Map)) do
		addPart({
			Name = d.name, Size = Vector3.new(d.w, 4, d.l),
			Position = Vector3.new(d.x, 0.6, d.z),   -- below the Y=1 landmark layer, above the baseplate top
			Material = Enum.Material.Grass, Color = Color3.fromRGB(d.r, d.g, d.b),
			CanCollide = d.canCollide, CanQuery = d.canQuery, CanTouch = d.canTouch, CastShadow = d.castShadow,
		})
	end

	-- Distinct ground LANDMARKS you fly over (a lake + a desert basin).
	addPart({ Name = "Lake", Size = Vector3.new(2600, 8, 1900), Position = Vector3.new(-3800, 1, 2600),
		Material = Enum.Material.Glass, Color = Color3.fromRGB(58, 120, 190), Transparency = 0.25 })
	addPart({ Name = "Desert", Size = Vector3.new(3000, 10, 3000), Position = Vector3.new(3600, 1, -3200),
		Material = Enum.Material.Sand, Color = Color3.fromRGB(216, 194, 142) })

	-- A RIVER winding down into the lake — thin water segments at Y≈1. Pure scenery/orientation that threads
	-- BETWEEN landmarks (not the spawn core); deterministic rotated segments so it snakes rather than runs straight.
	local river = {
		{ x = 1400,  z = 3800, w = 340, l = 2400, rot = 18 },
		{ x = -200,  z = 2950, w = 340, l = 2200, rot = 70 },
		{ x = -1900, z = 2650, w = 340, l = 1800, rot = 92 },
	}
	for i, r in ipairs(river) do
		addPart({ Name = "River" .. i, Size = Vector3.new(r.w, 6, r.l),
			CFrame = CFrame.new(r.x, 1, r.z) * CFrame.Angles(0, math.rad(r.rot), 0),
			Material = Enum.Material.Glass, Color = Color3.fromRGB(64, 128, 196), Transparency = 0.25 })
	end

	-- LAYERED MOUNTAINS for depth & perspective: three concentric rings at increasing radius + height with
	-- offset phases so the ranges OVERLAP and read as real depth from altitude (the thin Atmosphere hazes the
	-- far ring bluer — aerial perspective). Deterministic varied heights/widths (no rng → no surprises).
	local function ringMtns(o)
		for i = 1, o.count do
			local a = (i / o.count) * math.pi * 2 + o.phase
			local h = o.hBase + (i * o.hStep) % o.hSpan
			local w = o.wBase + (i * 53) % o.wSpan
			local px, pz = math.cos(a) * o.r, math.sin(a) * o.r
			addPart({
				Name = o.name .. i, Size = Vector3.new(w, h, w),
				Position = Vector3.new(px, h * 0.5 - 20, pz),
				Material = o.material or Enum.Material.Rock, Color = o.color(i),
			})
			if o.snow then -- a smaller white summit block so the far peaks read from kilometres out
				addPart({
					Name = o.name .. i .. "Cap", Size = Vector3.new(w * 0.6, h * 0.18, w * 0.6),
					Position = Vector3.new(px, h - 20, pz),
					Material = Enum.Material.Snow, Color = Color3.fromRGB(232, 238, 246),
				})
			end
		end
	end

	-- FOOTHILLS: a low green-brown apron ringing the open basin (R≈3600) — the near-perspective layer. Low
	-- enough (≤~720) that combat (eagle spawns Y=600 and climbs into the tall sky) happens ABOVE them.
	ringMtns({ name = "Foot", count = 18, r = 3600, phase = 0.0, hBase = 360, hStep = 47, hSpan = 360,
		wBase = 520, wSpan = 360, material = Enum.Material.Ground,
		color = function(i) return Color3.fromRGB(96, 110, 76 + (i * 7) % 24) end })
	-- MID RANGE: brown rock mountains (R≈5400), the middle layer, phase-offset from the foothills so they layer.
	ringMtns({ name = "Mid", count = 14, r = 5400, phase = 0.22, hBase = 1300, hStep = 137, hSpan = 760,
		wBase = 760, wSpan = 460, material = Enum.Material.Rock,
		color = function(i) return Color3.fromRGB(104 + (i * 13) % 40, 92, 84) end })
	-- FAR PEAKS: tall, snow-capped, cool-toned (aerial perspective) range at the rim (R≈7400) — the far horizon
	-- the player gauges "where am I flying" against.
	ringMtns({ name = "Peak", count = 13, r = 7400, phase = 0.42, hBase = 2200, hStep = 211, hSpan = 1200,
		wBase = 980, wSpan = 560, material = Enum.Material.Rock, snow = true,
		color = function() return Color3.fromRGB(120, 128, 150) end })

	-- INTERIOR MESAS/BUTTES — sparse rock blocks to fly through (canyon feel) and use as cover.
	local buttes = {
		{ x = -2000, z = 1300,  w = 520, h = 900  }, -- kept clear of the ±1200 spawn zone
		{ x = 1900,  z = -1500, w = 620, h = 1300 },
		{ x = 200,   z = 2200,  w = 460, h = 720  },
		{ x = -2300, z = -1800, w = 720, h = 1500 },
		{ x = 2600,  z = 1900,  w = 540, h = 1000 },
	}
	for i, b in ipairs(buttes) do
		addPart({
			Name = "Butte" .. i, Size = Vector3.new(b.w, b.h, b.w),
			Position = Vector3.new(b.x, b.h * 0.5 - 20, b.z),
			Material = Enum.Material.Rock, Color = Color3.fromRGB(120, 104, 92),
		})
	end

	-- CARDINAL BEACONS — four tall, bright, distinctly-coloured Neon pillars at N/E/S/W. They glow
	-- (render from far) so the pilot always knows heading at a glance — the core OODA reference.
	local cardinals = {
		{ n = "N", pos = Vector3.new(0, 0, -4200), c = Color3.fromRGB(230, 70, 70) },   -- red   = North
		{ n = "E", pos = Vector3.new(4200, 0, 0),  c = Color3.fromRGB(80, 150, 245) },  -- blue  = East
		{ n = "S", pos = Vector3.new(0, 0, 4200),  c = Color3.fromRGB(245, 205, 70) },  -- gold  = South
		{ n = "W", pos = Vector3.new(-4200, 0, 0), c = Color3.fromRGB(235, 235, 240) }, -- white = West
	}
	for _, c in ipairs(cardinals) do
		local h = 2200
		addPart({
			Name = "Beacon" .. c.n, Size = Vector3.new(220, h, 220),
			Position = c.pos + Vector3.new(0, h * 0.5 - 20, 0),
			Material = Enum.Material.Neon, Color = c.c,
		})
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
	event("AttackRequest")    -- C->S  (legacy click-melee; superseded by Strike, kept harmless)
	event("Strike")           -- C->S: fire EDGE (no args). Server reads the eagle's bank -> left/right/forward strike
	event("TakeDamage")       -- S->C: attackerName, targetPlayer, damage
	event("ScoreUpdate")      -- S->C: scores
	event("GameNotification") -- S->C: text, color
	event("CombatFX")         -- S->C: cause, position, victimTeam, killed — contact JUICE (feathers/pose); FX only, no gameplay
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

	-- VISUAL scale-up so birds read clearly at range (Chad). Collision + attack reach still use
	-- profile.bodyRadius (a config number, unchanged), so this is cosmetic — no balance effect.
	local vscale = (GameConfig.Visual and GameConfig.Visual.birdScale) or 1
	if vscale ~= 1 then pcall(function() model:ScaleTo(vscale) end) end

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

-- Spawn a fully AI-controlled crow squad with NO human owner, for solo testing
-- (GameConfig.Debug.aiCrowOpponents). EVERY member is AI; the squad is flagged `aggressive`
-- so squadGoal hunts the eagle from any range. Stored under BOT_SQUAD_KEY in Squads so
-- updateAICrows steps it like a normal squad.
local function spawnAICrowSquad()
	-- Spawn the wave a few hundred studs off the eagle (if any) so it engages quickly, instead of
	-- a random map corner it might never reach. Fall back to a random point at SPAWN_HEIGHT.
	local center
	for _, e in pairs(Birds) do
		if e.team == "Eagles" and isBirdAlive(e) then
			local ep = e.body.Position
			local ang = math.random() * math.pi * 2
			center = ep + Vector3.new(math.cos(ang) * 700, math.random(-80, 160), math.sin(ang) * 700)
			break
		end
	end
	center = center or Vector3.new(math.random(-1200, 1200), SPAWN_HEIGHT, math.random(-1200, 1200))
	local squad = {
		player = nil,
		formationName = GameConfig.Squad.defaultFormation or "loose",
		possessedIndex = 1,
		members = {},
		aggressive = true,
	}
	local size = GameConfig.Squad.size or 4
	for i = 1, size do
		local offset = Vector3.new((i - (size + 1) / 2) * 12, (i % 2) * 6, 0)
		local entry = spawnBird(nil, "Crows", "Crow", center + offset, true) -- isAI = true for ALL
		if entry then
			entry.squad = squad
			table.insert(squad.members, entry.model)
		end
	end
	Squads[BOT_SQUAD_KEY] = squad
	return squad
end

-- Tear down the bot squad + its birds (when a real match can be fielded, or to reset).
local function clearBotSquad()
	local squad = Squads[BOT_SQUAD_KEY]
	if not squad then return end
	for _, model in ipairs(squad.members) do
		if Birds[model] then Birds[model] = nil end
		if model then pcall(function() model:Destroy() end) end
	end
	Squads[BOT_SQUAD_KEY] = nil
end

-- Keep a living bot wave on the field: if every member of the current squad is dead (or there
-- is no squad), wipe it and spawn a fresh wave of `Squad.size` so the solo player always has
-- crows to parry. Called from the soloFlight branch of the round loop.
local function ensureBotCrowSquad()
	local squad = Squads[BOT_SQUAD_KEY]
	if squad then
		for _, model in ipairs(squad.members) do
			if isBirdAlive(Birds[model]) then return end -- at least one alive: keep this wave
		end
		clearBotSquad() -- whole wave down -> respawn a fresh one
	end
	spawnAICrowSquad()
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

-- Nearest enemy by a DIRECT linear scan (no spatial hash, no radius). Bird counts are tiny, so
-- this is cheap — and it lets an aggressive bot squad hunt the eagle across the whole 16k map
-- WITHOUT asking the hash for a map-spanning radius (a huge radius makes forEachInRadius walk
-- millions of empty cells and hangs the server — that bug froze Studio once already).
local function findNearestEnemyLinear(attackerEntry)
	local team = attackerEntry.team
	local pos = attackerEntry.body.Position
	local best, bestD2
	for _, e in pairs(Birds) do
		if e.team ~= team and isBirdAlive(e) then
			local d = (e.body.Position - pos).Magnitude
			local d2 = d * d
			if not bestD2 or d2 < bestD2 then best, bestD2 = e, d2 end
		end
	end
	return best
end

-- If a squad has no living possessed crow, promote the next living member so the
-- crow player keeps flying without a manual swap (also the seam for queue item #5).
-- The client re-acquires automatically off the "Possessed" attribute flip.
local function autoRepossess(squad)
	if not squad then return end
	-- Ownerless bot squads have no human to repossess to — leave every member AI (promoting
	-- one would set isAI=false with no network owner, freezing it out of updateAICrows).
	if not squad.player then return end
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

-- CROW SPIRAL-DEATH (S31 juice, Chad "the bird spirals down dead"): a killed crow is detached and
-- tumbles/spirals down for GameConfig.Combat.fx.tumbleDuration before despawning, so a kill READS
-- instead of the model just vanishing. Anchors the parts (we own the CFrame — a client network owner
-- can't fight it) then CFrame-animates a gravity fall + tumble spin. Purely cosmetic; the entry is
-- already removed from Birds before this runs, so the corpse takes NO further part in combat/AI/rounds.
local function spiralCrowDeath(model, lastVel)
	local body = model and (model.PrimaryPart or model:FindFirstChild("Body"))
	if not (model and body) then
		if model then pcall(function() model:Destroy() end) end
		return
	end
	local fx = GameConfig.Combat and GameConfig.Combat.fx
	local dur = (fx and fx.tumbleDuration) or 1.4
	local spin = (fx and fx.tumbleSpin) or 9
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	-- Seed the fall from the crow's last velocity (a downed bird keeps some momentum), damped.
	local vel = (typeof(lastVel) == "Vector3") and (lastVel * 0.4) or Vector3.zero
	task.spawn(function()
		local cf = model:GetPivot()
		local t = 0
		while t < dur and model.Parent do
			local dt = task.wait()
			t += dt
			vel = Vector3.new(vel.X * 0.98, vel.Y - 60 * dt, vel.Z * 0.98) -- gravity + horizontal drag
			local rot = (cf - cf.Position) * CFrame.Angles(spin * 0.4 * dt, spin * dt, spin * 0.6 * dt)
			cf = CFrame.new(cf.Position + vel * dt) * rot
			model:PivotTo(cf)
		end
		pcall(function() model:Destroy() end)
	end)
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
		-- CONTACT JUICE (S31): fire a purely-cosmetic CombatFX event at the contact point so clients can
		-- burst feathers / play the hit pose. Read the victim position NOW (the death branch below may
		-- Destroy the model this frame). cause is "beak"/"talon" (strike), "collision" (ram), "crash".
		-- FX only — no gameplay, no damage; clients gate it on GameConfig.Combat.fx + camera distance.
		local fxEvent = Remotes:FindFirstChild("CombatFX")
		if fxEvent and targetEntry.body then
			fxEvent:FireAllClients(cause, targetEntry.body.Position, targetEntry.team, hp <= 0)
		end
	end

	if hp <= 0 then
		-- This bird is dead — remove its model. Round resolution checks player liveness.
		local victimName = targetEntry.player and targetEntry.player.Name or "A bird"
		local killerName = attackerEntry and attackerEntry.player and attackerEntry.player.Name or nil

		local deadSquad = targetEntry.squad
		local deadModel = targetEntry.model
		local deadPlayer = targetEntry.player
		local deadVel = targetEntry.body and targetEntry.body.AssemblyLinearVelocity
		Birds[deadModel] = nil
		-- CROW SPIRAL-DEATH juice: tumble a killed crow down instead of vanishing (feathers already burst
		-- via CombatFX above). Crows only + gated; everything else despawns immediately as before.
		local fxCfg = GameConfig.Combat and GameConfig.Combat.fx
		if fxCfg and fxCfg.crowTumble and targetEntry.team == "Crows" then
			spiralCrowDeath(deadModel, deadVel)
		else
			pcall(function() deadModel:Destroy() end)
		end

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
-- EAGLE DIRECTIONAL STRIKE (left/right talon · forward) — server-owned timers + bank classify
--------------------------------------------------------------------------------
-- The eagle taps LEFT-CLICK to fire a strike (client sends the Strike EDGE only — no direction,
-- no hit claim). The SERVER reads the authoritative bank from the Body and picks the strike type
-- (GameConfig.Combat.bankStrikeThresholdDeg), runs the per-type startup→duration→cooldown timers,
-- and owns the offset coverage cone. During the active window (past startup) the offset cone BOTH
-- parries an incoming ram (tryStrikeCatch, from processCollisions: crow dies, eagle unharmed) AND
-- deals offensive damage to a crow inside the cone within reach (the proactive hunt). ONE
-- catch-or-hit per window (the `caught` flag). State + a HUD meter/armed-zone are mirrored onto the
-- eagle Body as attributes (StrikeMeter 0..1, StrikeActive bool, StrikeArmedDir "beak"|"talon"|"none").

-- The world-space axis of a strike's coverage cone (read from the Body's CFrame — authoritative, never a
-- client value). "belly" = the bird's DOWN (-Up): it SWINGS as you roll, so the talon zone naturally tracks
-- where the talons reach; "forward" (default) = the nose, for the beak jab.
local function strikeAxis(body, cfg)
	if cfg.axis == "belly" then return -body.CFrame.UpVector end
	return body.CFrame.LookVector
end

-- Which strike ZONE the nearest enemy is in (Chad 2026-06-30 — the proximal zone makes the strike; the old
-- bank-chosen LEFT/RIGHT dichotomy is GONE). "talon" when the enemy is more aligned with the BELLY (down) axis
-- than the nose, else "beak"; returns `none` when no enemy is within strikeSelectRange. Banking tilts the belly
-- axis sideways, so a hard bank swings the talon zone onto a side-low crow. Authoritative; client only mirrors
-- this (StrikeArmedDir) to LIGHT the matching reticle. `none` lets onStrike default to beak but the HUD stay dark.
local function enemyZone(entry, none)
	local range = (GameConfig.Combat and GameConfig.Combat.strikeSelectRange) or 200
	local target = findNearestEnemy(entry, range)
	if not target then return none end
	local d = target.body.Position - entry.body.Position
	if d.Magnitude < 1e-3 then return none end
	d = d.Unit
	-- Bias the belly(-Up) side so front/side-low crows arm the wide 70° talon instead of the narrow beak
	-- (Chad "can't get 'em"; Stage-7 showed the talon was never picked). bias = 0 is byte-for-byte today.
	local bias = (GameConfig.Combat and GameConfig.Combat.talonPickBias) or 0
	return (d:Dot(-entry.body.CFrame.UpVector) + bias > d:Dot(entry.body.CFrame.LookVector)) and "talon" or "beak"
end

local function newStrikeState()
	return { state = "ready", stype = nil, startupLeft = 0, durationLeft = 0, cooldownLeft = 0, caught = false }
end

-- Advance one strike state machine: ready -> active (startup→duration) -> cooldown -> ready.
local function stepStrike(s, dt)
	local strikes = GameConfig.Combat and GameConfig.Combat.strikes
	if s.state == "cooldown" then
		s.cooldownLeft -= dt
		if s.cooldownLeft <= 0 then s.state, s.stype = "ready", nil end
	elseif s.state == "active" then
		local cfg = (strikes and strikes[s.stype]) or {}
		if s.startupLeft > 0 then s.startupLeft = math.max(0, s.startupLeft - dt) end
		s.durationLeft -= dt
		if s.durationLeft <= 0 then
			s.state = "cooldown"
			s.cooldownLeft = cfg.cooldown or 1.2
		end
	end
end

-- A Strike EDGE from a client: classify the bank, then (if idle) start that strike type. Rate-limited
-- like the old attack; the state machine's cooldown is the real re-fire gate. Only the possessed eagle
-- can strike; crows have no strikes (their attack is the suicide ram), so the server ignores them.
local function onStrike(player)
	if not roundActive then return end
	local now = os.clock()
	if lastAttackAt[player] and (now - lastAttackAt[player]) < ATTACK_COOLDOWN then return end
	local entry = getActiveBird(player)
	if not entry or entry.team ~= "Eagles" then return end
	entry.strike = entry.strike or newStrikeState()
	local s = entry.strike
	if s.state ~= "ready" then return end -- busy (startup/active/cooldown) — ignore the trigger
	local strikes = GameConfig.Combat and GameConfig.Combat.strikes
	local stype = enemyZone(entry, "beak") -- auto-pick by enemy proximity; default to the forward beak jab
	local cfg = strikes and strikes[stype]
	if not cfg then return end
	lastAttackAt[player] = now
	s.state = "active"
	s.stype = stype
	s.startupLeft = cfg.startup or 0
	s.durationLeft = cfg.duration or 0.3
	s.caught = false
end

--------------------------------------------------------------------------------
-- STAGE 7 STRIKE TELEMETRY (dev instrument — gated by GameConfig.Combat.strikeTelemetry)
--------------------------------------------------------------------------------
-- Attributes the both-sides-low contact-rate problem to a MECHANISM (crow pursuit-curve vs eagle cone
-- geometry vs the speed gate vs timing vs a contact-path bug) BEFORE any combat number is tuned. It
-- only READS state — never gates or alters a ram, a cooldown, damage, or tryStrikeCatch. Fully inert
-- when the flag is false: updateStrikeTelemetry early-returns with zero scan/allocation. Rows batch-
-- flush to the server log ~1 Hz (per-event, never summarized, so dive-bomb burst structure survives).
-- Dev/solo Studio ONLY (the near-miss scan adds frame work — see the armed-vs-unarmed A/B gate).
-- Revert: set GameConfig.Combat.strikeTelemetry=false, or delete this block + the two other delimited
-- STRIKE-TELEMETRY hunks (the updateEagleStrikes hook + the onHeartbeat call + updateStrikeTelemetry).
local TELEM_RADIUS       = 48    -- studs; near-miss window (captures the ~12-30 pursuit-curve cluster + margin)
local TELEM_FLUSH_PERIOD = 1.0   -- s; batch-print cadence
local telemArmed     = false     -- cached from the config flag each frame (also read by the strike hook)
local telemPairMin   = {}        -- pairKey -> {minSep, relAtMin, touch}: running closest-approach per eagle↔crow pair
local telemRows      = {}        -- buffered event rows (batch-flushed, never summarized)
local telemLastFlush = 0

-- Log ONE armed-strike frame vs the nearest enemy — hits AND clean misses, so cone/reach/timing
-- failures are visible, not just landings. Called (gated) from updateEagleStrikes' offensive pass.
local function telemStrike(eagle, cfg, target, dist, reach, covered, hit)
	local axisDot = -2
	if target then
		local dir = target.body.Position - eagle.body.Position
		if dir.Magnitude > 1e-3 then axisDot = dir.Unit:Dot(strikeAxis(eagle.body, cfg)) end
	end
	local s = eagle.strike
	local windowPhase = (s and cfg.duration and cfg.duration > 0) and (s.durationLeft / cfg.duration) or -1
	telemRows[#telemRows + 1] = string.format(
		"%.2f\tSTRIKE\t%s\tdist=%.1f\treach=%.1f\taxisDot=%.3f\tconeCos=%.3f\tcovered=%s\twindowPhase=%.2f\thit=%s",
		os.clock(), tostring(cfg.damage), dist or -1, reach, axisDot,
		math.cos(math.rad(cfg.coverHalfAngleDeg or 60)), tostring(covered), windowPhase, tostring(hit))
end

-- Step every eagle's strike timers once per Heartbeat, run the offensive cone pass, and mirror the
-- HUD attributes. Eagles are snapshot first so the offensive applyDamage (which removes Birds entries)
-- can't corrupt a live `pairs(Birds)` iteration.
local function updateEagleStrikes(dt)
	local strikes = GameConfig.Combat and GameConfig.Combat.strikes
	if not strikes then return end
	local eagles = {}
	for _, entry in pairs(Birds) do
		if entry.team == "Eagles" and isBirdAlive(entry) then eagles[#eagles + 1] = entry end
	end
	for _, entry in ipairs(eagles) do
		if isBirdAlive(entry) then
			entry.strike = entry.strike or newStrikeState()
			local s = entry.strike
			stepStrike(s, dt)

			-- AUTO-STRIKE (S31 accessibility, Chad "getting a hit is near impossible / a new kid won't time
			-- clicks"): if enabled and the strike is READY, auto-OPEN the window the instant a crow is actually
			-- inside the auto-picked zone's cone AND within reach — so a new player lands the hit without
			-- frame-perfect click timing. LMB still works and still feels like agency; this only fires when
			-- the geometry is genuinely satisfied. Cooldown + one-hit-per-window are unchanged, so it is NOT a
			-- death-ray. GameConfig.Combat.autoStrike = false is byte-for-byte today.
			if s.state == "ready" and GameConfig.Combat and GameConfig.Combat.autoStrike then
				local stype = enemyZone(entry, "none")
				local cfg = (stype ~= "none") and strikes[stype]
				if cfg then
					local p = entry.profile
					local reach = cfg.reachStuds or (p.bodyRadius + MAX_BODY_RADIUS + ATTACK_BUFFER) * (cfg.reachFraction or 0.7)
					reach = reach + (GameConfig.Combat.strikeReachBonus or 0)
					local target, dist = findNearestEnemy(entry, reach + 6)
					if target and dist and dist <= reach then
						local dir = target.body.Position - entry.body.Position
						if dir.Magnitude > 1e-3
							and dir.Unit:Dot(strikeAxis(entry.body, cfg)) >= math.cos(math.rad(cfg.coverHalfAngleDeg or 60)) then
							-- Open the window (as if the player clicked at the perfect moment); the offensive
							-- pass below lands it once startup elapses, sharing the same cooldown/caught rules.
							s.state = "active"
							s.stype = stype
							s.startupLeft = cfg.startup or 0
							s.durationLeft = cfg.duration or 0.3
							s.caught = false
						end
					end
				end
			end

			-- OFFENSIVE pass: while active (past startup) and not yet spent this window, a crow inside the
			-- zone's cone (beak=forward / talon=belly) within reach takes the strike's damage. One per window (shares `caught` with
			-- the defensive parry, so a strike lands EITHER a kill-catch OR an offensive hit, never both).
			if s.state == "active" and s.startupLeft <= 0 and not s.caught then
				local cfg = strikes[s.stype]
				if cfg then
					local p = entry.profile
					-- Explicit reachStuds (S17) is a believable swoop-and-strike range; fall back to the
					-- old point-blank formula only if a strike omits it.
					local reach = cfg.reachStuds or (p.bodyRadius + MAX_BODY_RADIUS + ATTACK_BUFFER) * (cfg.reachFraction or 0.7)
					-- STRIKE REACH BUFFER (Chad "need a bigger buffer to strike"): widen the offensive hunt
					-- sphere so a circling crow just past the nose still gets clipped. Offense only — the parry
					-- (tryStrikeCatch) and ram are untouched. 0 = byte-for-byte today. See GameConfig.Combat.
					reach = reach + ((GameConfig.Combat and GameConfig.Combat.strikeReachBonus) or 0)
					local target, dist = findNearestEnemy(entry, reach + 6)
					if target and dist and dist <= reach then
						local dir = target.body.Position - entry.body.Position
						if dir.Magnitude > 1e-3 then
							local axis = strikeAxis(entry.body, cfg)
							if dir.Unit:Dot(axis) >= math.cos(math.rad(cfg.coverHalfAngleDeg or 60)) then
								local dmg = (cfg.damage == "beak") and (p.beakDamage or 22) or (p.talonDamage or 34)
								s.caught = true
								applyDamage(target, dmg, entry, cfg.damage or "talon")
							end
						end
					end
					-- STRIKE TELEMETRY (Stage 7, gated + read-only): log this armed frame — hit OR clean miss.
					if telemArmed then
						local covered = false
						if target and dist and dist <= reach then
							local d2 = target.body.Position - entry.body.Position
							if d2.Magnitude > 1e-3 then
								covered = d2.Unit:Dot(strikeAxis(entry.body, cfg)) >= math.cos(math.rad(cfg.coverHalfAngleDeg or 60))
							end
						end
						telemStrike(entry, cfg, target, dist, reach, covered, s.caught)
					end
				end
			end

			-- HUD mirror: meter (0..1), whether it can parry/hit right now, and the LIVE armed direction
			-- (the strike a click would throw — picked by enemy proximity; lights the BEAK/TALON indicator).
			local meter, active = 1, false
			if s.state == "active" then
				local cfg = strikes[s.stype] or {}
				meter = (cfg.duration and cfg.duration > 0) and math.clamp(s.durationLeft / cfg.duration, 0, 1) or 0
				active = (s.startupLeft <= 0)
			elseif s.state == "cooldown" then
				local cfg = strikes[s.stype] or {}
				meter = (cfg.cooldown and cfg.cooldown > 0) and math.clamp(1 - s.cooldownLeft / cfg.cooldown, 0, 1) or 1
				active = false
			end
			entry.body:SetAttribute("StrikeMeter", meter)
			entry.body:SetAttribute("StrikeActive", active)
			entry.body:SetAttribute("StrikeArmedDir", enemyZone(entry, "none"))
		end
	end
end

-- Did the eagle's active strike catch this ramming crow? True if the strike is active (past startup),
-- hasn't already caught/hit this window, and its OFFSET cone covers the direction to the crow.
local function tryStrikeCatch(eagle, crow)
	local s = eagle.strike
	local strikes = GameConfig.Combat and GameConfig.Combat.strikes
	if not s or not strikes then return false end
	if s.state ~= "active" or s.startupLeft > 0 or s.caught then return false end
	local cfg = strikes[s.stype]
	if not cfg then return false end
	local dir = crow.body.Position - eagle.body.Position
	if dir.Magnitude < 1e-3 then return false end
	local axis = strikeAxis(eagle.body, cfg)
	if dir.Unit:Dot(axis) >= math.cos(math.rad(cfg.coverHalfAngleDeg or 60)) then
		s.caught = true
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- COLLISIONS (the signature lose-lose mechanic)
--------------------------------------------------------------------------------
-- Heartbeat proximity check between ENEMY birds (the only enemy pairing is eagle↔crow).
-- ASYMMETRIC MODEL (HANDOFF session 11 / GameConfig.Combat): a committed contact above
-- COLLISION_SPEED_MIN is a crow SUICIDE RAM — the crow ALWAYS dies, and the eagle takes one
-- of its `eagleHits` (= health/eagleHits damage). The parry that lets the eagle negate the
-- hit by covering the contact zone with an extended talon/beak lands in iteration 3; for now
-- every committed ram costs the eagle a hit. A simultaneous ram by another crow this frame is
-- a separate pair → its own hit, which is how multi-angle swarming will beat one parry (iter 3).
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

				-- Identify the eagle and the crow (the only enemy pairing). The crow's sole
				-- attack is the suicide ram, so a committed contact ALWAYS kills the crow; the
				-- eagle takes one of its `eagleHits` UNLESS it was covering this contact zone
				-- with an ACTIVE directional strike whose offset cone faces the crow (tryStrikeCatch).
				local eagle, crow
				if a.team == "Eagles" then eagle, crow = a, b else eagle, crow = b, a end

				if tryStrikeCatch(eagle, crow) then
					-- CAUGHT: the crow dies on the strike and the eagle takes NO hit.
					applyDamage(crow, 1e9, eagle, "talon")
				else
					-- UNPARRIED ram: one of the eagle's `eagleHits`; the crow dies regardless.
					local eagleHits = (GameConfig.Combat and GameConfig.Combat.eagleHits) or 3
					local hitDamage = (eagle.profile.health or 99) / eagleHits
					applyDamage(eagle, hitDamage, crow, "collision")
					if isBirdAlive(crow) then
						applyDamage(crow, 1e9, eagle, "collision")    -- the sacrifice
					end
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
	-- P3 non-lethal terrain (EAGLES TO THE RESCUE): a huge effective crash speed makes terrain impacts
	-- graze-slide (never kill). Mirrors the client gate in BirdController.onFlightStep so the two never
	-- disagree. Stored Flight.CRASH_SPEED is untouched. The Y<GROUND_FAILSAFE_Y kill still applies.
	local crashSpeed = (GameConfig.Rescue and GameConfig.Rescue.enabled and GameConfig.Rescue.nonLethalTerrain)
		and 1e9 or GameConfig.Flight.CRASH_SPEED
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

-- Stage 7 near-miss scan + batch flush. Runs per living eagle only (few), querying crows within
-- TELEM_RADIUS — O(eagles × neighbors), a handful of pairs/frame, NOT an all-birds O(n²) sweep — so
-- per-frame sampling keeps minSep accurate without a measurable frame cost. Fully inert when unarmed.
local function updateStrikeTelemetry()
	telemArmed = (GameConfig.Combat and GameConfig.Combat.strikeTelemetry) == true
	if not telemArmed then
		-- Inert path: no scan, no allocation. Drop any state so a later re-arm starts clean.
		if next(telemPairMin) then telemPairMin = {} end
		if #telemRows > 0 then telemRows = {} end
		return
	end
	local now = os.clock()

	-- Sample the closest approach of every eagle↔crow pair currently inside the near-miss window.
	local seen = {}
	for _, eagle in pairs(Birds) do
		if eagle.team == "Eagles" and isBirdAlive(eagle) then
			local epos = eagle.body.Position
			birdIndex:forEachInRadius(epos, TELEM_RADIUS, function(crow)
				if crow.team == eagle.team or not isBirdAlive(crow) then return end
				local sep = (epos - crow.body.Position).Magnitude
				if sep > TELEM_RADIUS then return end
				local key = pairKey(eagle.model, crow.model)
				seen[key] = true
				local st = telemPairMin[key]
				if not st or sep < st.minSep then
					local relSpeed = (eagle.body.AssemblyLinearVelocity - crow.body.AssemblyLinearVelocity).Magnitude
					telemPairMin[key] = {
						minSep = sep, relAtMin = relSpeed,
						touch = eagle.profile.bodyRadius + crow.profile.bodyRadius,
					}
				end
			end)
		end
	end

	-- Terminal event: any tracked pair that left the window (or whose bird died) this frame — emit its
	-- closest-approach row and drop it (self-pruning, so the state table cannot leak). CONTACT vs MISS
	-- reads into the decision table (a MISS at minSep 12-30 = the crow pursuit-curve fingerprint).
	for key, st in pairs(telemPairMin) do
		if not seen[key] then
			local outcome = (st.minSep <= st.touch) and "CONTACT" or "MISS"
			local gatePass = st.relAtMin >= COLLISION_SPEED_MIN
			telemRows[#telemRows + 1] = string.format(
				"%.2f\tMERGE\t%s\tminSep=%.1f\ttouch=%.1f\trelAtMin=%.0f\tgatePass=%s",
				now, outcome, st.minSep, st.touch, st.relAtMin, tostring(gatePass))
			telemPairMin[key] = nil
		end
	end

	-- Batch-flush ALL buffered rows once/sec (never summarized — the burst cadence IS a finding).
	if now - telemLastFlush >= TELEM_FLUSH_PERIOD then
		telemLastFlush = now
		if #telemRows > 0 then
			print(string.format("[EvC strikeTelem] --- %d rows @ %.2f ---\n%s",
				#telemRows, now, table.concat(telemRows, "\n")))
			telemRows = {}
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
	-- Aggressive (bot) squads HUNT: converge on the nearest eagle from ANY distance, via a LINEAR
	-- scan (NOT the spatial hash — a map-spanning hash radius walks millions of empty cells and
	-- hangs the server). Player squads swarm only once the possessed crow is within engageRadius
	-- (a cheap, bounded hash query; the human leads and squadmates support).
	local enemy
	if squad.aggressive then
		enemy = findNearestEnemyLinear(possessed)
	else
		enemy = findNearestEnemy(possessed, GameConfig.Squad.engageRadius)
	end
	if enemy then
		goal = enemy.body.Position
	end
	-- Also return the enemy entry: aggressive bot crows orbit it (mobOrbitTarget) rather than
	-- ram its centre. nil when no enemy is in range (fall back to plain rally-goal steering).
	return goal, possessed, enemy
end

-- MOBBING orbit target (increment 1) — real corvids CIRCLE a raptor at a standoff distance instead of
-- charging its centre (docs/RESEARCH-crow-mobbing.md). Given the eagle position and this crow's
-- position, return a boids goal POINT on an orbit shell that (a) pulls the crow IN to orbitRadius when
-- outside it / holds it OUT when inside, (b) leads tangentially so the crow circles the ring, and (c)
-- sits slightly above (attack-from-above prep). `handed` (±1) sets circling direction — a consistent
-- sign per crow means crows on the ring chase the same way and never close head-on.
local function mobOrbitTarget(eaglePos, crowPos, handed)
	local cfg = GameConfig.Squad.mob
	local orbitR = cfg.orbitRadius or 220
	-- Radial (eagle -> crow), flattened to horizontal so the ring is a level circle around the eagle.
	local radial = crowPos - eaglePos
	radial = Vector3.new(radial.X, 0, radial.Z)
	if radial.Magnitude < 1e-3 then
		radial = Vector3.new(1, 0, 0) -- degenerate: crow directly above/below → pick an arbitrary bearing
	end
	radial = radial.Unit
	-- Tangent = horizontal perpendicular to the radial; `handed` picks the circling direction.
	local tangent = radial:Cross(Vector3.yAxis)
	if tangent.Magnitude < 1e-3 then
		tangent = Vector3.new(0, 0, 1)
	end
	tangent = tangent.Unit * (handed >= 0 and 1 or -1)
	-- Station point on the shell at this crow's current bearing, + a tangential lead to keep it moving
	-- around the circle, + a small upward bias to sit above the eagle.
	local station = eaglePos + radial * orbitR
	local lead = tangent * (cfg.orbitLead or 170)
	return station + lead + Vector3.new(0, cfg.orbitHeightBias or 40, 0)
end

-- PEEL-OFF target (increment 2) — after a dive-bomb pass, the attacker breaks AWAY from the eagle and
-- CLIMBS to recover, instead of lingering in contact (which is a passive suicide-ram). Aim a point back
-- outward along the crow's current bearing, beyond the ring, and well above the eagle (regain the
-- attack-from-above energy for its next pass). handed unused here — the break is purely radial+up.
local function mobPeelTarget(eaglePos, crowPos)
	local cfg = GameConfig.Squad.mob
	local db = cfg.diveBomb or {}
	local orbitR = cfg.orbitRadius or 220
	local radial = crowPos - eaglePos
	radial = Vector3.new(radial.X, 0, radial.Z)
	if radial.Magnitude < 1e-3 then
		radial = Vector3.new(1, 0, 0)
	end
	radial = radial.Unit
	return eaglePos + radial * (orbitR * (db.peelRadiusMul or 1.6)) + Vector3.new(0, db.peelHeightBias or 120, 0)
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

-- Obstacle-avoidance steering for an AI crow (queue #8): a forward Spherecast look-ahead. If
-- terrain is in the bird's path, return a world-space steer-away UNIT direction (surface normal
-- + a tangential slide so it ARCS around instead of stalling head-on) and an urgency 0..1 that
-- rises as the hit nears. Returns nil when the path is clear. Called ONLY from updateAICrows, so
-- it never touches the player-controlled crow (Chad's rule: the crow you ram with gets none).
local function avoidObstacle(entry)
	local cfg = GameConfig.Squad.avoidance
	if not cfg then return nil end
	local body = entry.body
	local vel = body.AssemblyLinearVelocity
	local speed = vel.Magnitude
	if speed < 1 then return nil end
	local dir = vel / speed
	local look = math.clamp(speed * (cfg.lookaheadTime or 1.2), cfg.minDistance or 50, cfg.maxDistance or 320)
	local hit = BirdCollision.lookAhead(body.Position, dir, look, entry.profile.bodyRadius + (cfg.spherePad or 8), getCollisionParams())
	if not hit then return nil end
	local dist = (hit.Position - body.Position).Magnitude
	-- Urgency ramps with closeness (sqrt = a touch earlier than linear), but NO floor — far-away terrain
	-- detection gives ~0 avoidance, so the eagle-chase dominates until a wall is genuinely imminent. (A floor
	-- here made the bots veer off constantly and flee the map.)
	local urgency = math.sqrt(1 - math.clamp(dist / look, 0, 1))
	local normal = hit.Normal
	local tangent = dir - normal * dir:Dot(normal)
	local tm = tangent.Magnitude
	local tunit = (tm > 1e-3) and (tangent / tm) or Vector3.new()
	-- Favour the TANGENT (slide/arc around) over pure push-back so the crow curves past the wall while
	-- keeping speed toward the eagle, rather than braking head-on into it.
	local steerAway = normal * 0.55 + tunit * 0.7
	local sm = steerAway.Magnitude
	if sm < 1e-3 then return normal, urgency end
	return steerAway / sm, urgency
end

-- Step every AI crow once per Heartbeat: boids -> input -> light flight step -> apply.
local function updateAICrows(dt)
	local fdt = math.min(dt, AI_HEARTBEAT_DT_CAP)
	local formations = GameConfig.Squad.formations

	local now = os.clock()
	for _, squad in pairs(Squads) do
		local goal, _possessed, enemy = squadGoal(squad)
		local formationCfg = formations[squad.formationName] or formations.loose
		-- MOBBING (increment 1 orbit): an aggressive bot squad with a live eagle CIRCLES it at a
		-- standoff ring instead of ramming its centre (research: mobbing≠flocking — crows are
		-- independent attackers that orbit + dive-bomb, cohesion DROPS). Gated on Squad.mob.enabled.
		local mobbing = GameConfig.Squad.mob.enabled and squad.aggressive and enemy ~= nil
		local eaglePos = mobbing and enemy.body.Position or nil
		-- MOB STEERING (S24 scatter fix): while mobbing, swap the flocking blend for the
		-- independent-attacker profile (alignment/cohesion 0, separation high) — see the
		-- Squad.mob.steering comment in GameConfig for the full mechanism. Without this the
		-- clumped orbiters align/cohere with every departing attacker/peeler and the whole
		-- group drifts away ("they scatter and fly away"). AI-only: player squads are never
		-- `aggressive`, so their tight/loose formation blend is untouched.
		if mobbing and GameConfig.Squad.mob.steering then
			formationCfg = GameConfig.Squad.mob.steering
		end

		-- STAGGERED DIVE-BOMB SCHEDULER (increment 2): while mobbing, launch ONE attacker at a time on
		-- a round-robin so the crows TAKE TURNS committing a pass through the eagle and PEELING off,
		-- never all-4-at-once. Stamps _attackUntil/_peelUntil on the chosen crow; the member loop below
		-- reads those to pick its goal (dive at the eagle → peel out+up → back to the ring). AI-only.
		local db = GameConfig.Squad.mob.diveBomb
		if mobbing and db and db.enabled then
			local sched = squad._mobAttack
			if not sched then sched = { nextAt = 0, cursor = 0 }; squad._mobAttack = sched end
			if now >= sched.nextAt then
				-- Pick the next LIVING AI member (never the player's crow) as the sole attacker.
				local n = #squad.members
				local chosen = nil
				for step = 1, n do
					local i = (sched.cursor + step - 1) % n + 1
					local e = Birds[squad.members[i]]
					if e and e.isAI and isBirdAlive(e) then
						chosen = e; sched.cursor = i; break
					end
				end
				if chosen then
					chosen._attackUntil = now + (db.attackDuration or 1.6)
					chosen._peelUntil = chosen._attackUntil + (db.peelDuration or 1.4)
				end
				sched.nextAt = now + (db.attackPeriod or 3.0)
			end
		end

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
				-- Replace the raw eagle-centre goal with an orbit-shell station point so the crow
				-- circles the eagle at standoff distance (mob, don't ram). CONSISTENT circling
				-- direction for the whole squad → a rotating train spaced by separation, never a
				-- head-on closure; coverage from multiple bearings comes from their distinct start
				-- positions on the ring.
				local memberGoal = goal
				local isAttacking = false     -- true only for the crow committing a dive-bomb pass this frame
				if mobbing then
					-- Increment 2 mode select: this crow is either committing a dive-bomb pass (goal =
					-- eagle centre — the ONE time it closes the standoff), peeling off (goal = out past
					-- the ring + climb to recover), or holding the orbit ring (default). Timers set by the
					-- squad scheduler above; expire naturally back to ORBIT.
					if entry._attackUntil and now < entry._attackUntil then
						-- DIVE-BOMB: aim at a LED intercept (eaglePos + eagleVel·leadTime) so the pass connects
						-- instead of pursuit-curving behind a turning eagle and sliding past (Chad "they get away
						-- so fast"; Stage-7 pursuit-curve). leadTime = 0 ⟹ eaglePos, byte-for-byte today.
						local leadTime = (GameConfig.Squad.mob.diveBomb and GameConfig.Squad.mob.diveBomb.leadTime) or 0
						memberGoal = eaglePos + enemy.body.AssemblyLinearVelocity * leadTime -- commit through the eagle
						isAttacking = true
					elseif entry._peelUntil and now < entry._peelUntil then
						memberGoal = mobPeelTarget(eaglePos, body.Position) -- PEEL-OFF: break away + climb
					else
						memberGoal = mobOrbitTarget(eaglePos, body.Position, 1) -- ORBIT the standoff ring
					end
				end
				local steer = Boids.computeSteering(selfState, neighbors, memberGoal, formationCfg)
				-- Obstacle avoidance (#8): bias steering away from imminent terrain so the crow
				-- arcs around spires/ground instead of crashing while it hunts. AI-only by construction.
				local avoidDir, urgency = avoidObstacle(entry)
				if avoidDir then
					local base = steer.Magnitude
					if base < 1 then base = GameConfig.Squad.boids.maxSteerForce end
					steer = steer + avoidDir * base * (GameConfig.Squad.avoidance.weight or 3.5) * urgency
				end
				local input = Boids.steeringToInput(body.CFrame, body.AssemblyLinearVelocity, steer, entry.profile)

				-- AI FLIGHT GOVERNOR (increment 0): the boids mapping dives at its target and rockets to
				-- the dive-cap, so crows overshoot into terrain / sink into the ground (playtest 2026-07-01:
				-- "too fast, can't turn tight… fine then suddenly crash into terrain and the ground"). Keep
				-- them near a controllable combat speed and out of dives so their turn radius stays tight and
				-- they don't plow into the deck. AI-only (this loop never runs the player's crow).
				local af = GameConfig.Squad.aiFlight
				if af and af.enabled then
					local sp = body.AssemblyLinearVelocity.Magnitude
					-- A crow COMMITTING a dive-bomb pass gets a higher speed ceiling so it actually CLOSES
					-- the ~orbitRadius standoff and reaches ram range within its attack window (at the cruise
					-- cap it falls short and the pass whiffs). Still capped + suppressDive on, so it's a fast
					-- controlled closure, not a runaway stoop into terrain. Orbiting/peeling crows keep the
					-- normal cruise cap for tight, controllable turns.
					local speedMul = af.combatSpeedMul or 1.2
					if isAttacking then
						speedMul = (GameConfig.Squad.mob.diveBomb and GameConfig.Squad.mob.diveBomb.attackSpeedMul) or 1.8
					end
					local combatSpeed = (entry.profile.glideSpeed or 95) * speedMul
					if af.suppressDive then
						input.dive = false
					end
					if sp > combatSpeed then
						-- Too fast → bleed: stop flapping and don't hold a nose-down that would re-accelerate.
						input.flap = false
						if input.pitch < 0 then input.pitch = input.pitch * 0.3 end
					end
					-- Soft altitude floor: don't sink into the ground while banking hard.
					if body.Position.Y < (af.floorHeight or 250) then
						input.flap = true
						input.dive = false
						input.pitch = math.max(input.pitch, af.floorClimbPitch or 0.5)
					end

					-- AI AUTOPILOT: bank limit + turn coordination. The engine has no auto-level, so a
					-- hard chase-reversal rolls the crow to knife-edge → it loses vertical lift and falls
					-- ("crash when chased, losing control"). Cap the bank and coordinate the turn. AI-only.
					if af.autopilot then
						local cf = body.CFrame
						local upY = cf.UpVector.Y                 -- 1 wings-level, 0 knife-edge, <0 inverted
						-- Leveling roll command: +roll raises the right wing, so -RightVector.Y levels.
						local levelRoll = math.clamp(-cf.RightVector.Y * (af.levelAssist or 3.0), -1, 1)
						local maxBankCos = af.maxBankCos or 0.5
						if upY < maxBankCos then
							-- Past the bank limit → leveling dominates so it can't knife-edge/spin.
							input.roll = levelRoll
						elseif upY < 0.85 then
							-- Moderately banked → blend leveling in so it doesn't creep to knife-edge.
							input.roll = math.clamp(input.roll * 0.7 + levelRoll * 0.3, -1, 1)
						end
						-- Coordinated turn: add up-elevator ∝ bank so the turn holds altitude, not sinks.
						local bank = 1 - math.abs(upY)
						input.pitch = math.clamp(input.pitch + bank * (af.turnPitchUp or 0.5), -1, 1)
					end
				end

				-- Run the SAME flight engine the player uses, then write the result back
				-- to the server-owned part (server simulates these birds).
				entry.engine:SetThermalForce(thermalForceAt(body.Position))
				local fromPos = body.Position
				entry.engine:Update(fdt, input)

				-- Obstacle/ground collision: sweep the step. AI crows are server-owned, so we
				-- resolve here directly — a head-on map impact crashes the crow, a graze slides
				-- it along the surface (engine velocity is server-trusted; use it for the gate).
				local toPos = entry.engine.orientation.Position
				-- AI crows treat a terrain impact as NON-LETHAL: even a head-on hit just slides them along the
				-- surface (we pass a huge crashSpeed so resolve never flags `crashed`). A bot must never suicide
				-- on a building before the player can engage it (player ask 2026-06-30); its deaths come from the
				-- eagle's strikes/collisions (and the deep Y-failsafe). The PLAYER-flown crow is unaffected — its
				-- crashes run through processCrashes with the real CRASH_SPEED. Avoidance (above) still makes the
				-- bot arc around terrain so it doesn't just grind along a wall.
				local newPos, newVel = BirdCollision.resolve(
					fromPos, toPos, entry.engine.velocity, entry.profile.bodyRadius,
					getCollisionParams(), math.huge
				)
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

				-- Wings are NOT animated here: Motor6D.Transform does not replicate, so a
				-- server-side flap is invisible to every client (pure wasted CPU). Each client
				-- animates all AI crows locally from their replicated CFrame/velocity — see
				-- BirdController.animateOtherBirds.
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
	elseif reason == "tie" then
		-- The eagle's last hit and the last crow's death coincided — no score (a true draw).
		notify("Both fall — the round is a draw!", Color3.fromRGB(220, 220, 120))
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
			clearBotSquad() -- a real match preempts the solo-test bot crows
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
				local eAlive, cAlive = anyEagleAlive(), anyCrowAlive()
				if not eAlive and not cAlive then result = "tie" break end   -- both fell together
				if not eAlive then result = "eagleDown" break end
				if not cAlive then result = "crowsDown" break end
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
			-- Solo Eagle vs AI: keep a fresh wave of bot crows on the field to parry. They
			-- count for nothing in scoring; they exist only while a lone human eagle is here.
			if GameConfig.Debug.aiCrowOpponents and eaglesExist() and not crowsExist() then
				ensureBotCrowSquad()
			else
				clearBotSquad()
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
	Remotes.Strike.OnServerEvent:Connect(function(player)
		pcall(onStrike, player)
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
	-- Step eagle strike timers + offensive cone (before collisions, so tryStrikeCatch reads fresh state).
	pcall(updateEagleStrikes, dt)
	-- Anti-cheat movement validation (before crash sweep, so a rubber-band corrects the
	-- position the crash check then reads).
	pcall(processAntiCheat, dt)
	-- Signature collisions.
	pcall(processCollisions)
	-- Obstacle/ground crash deaths (feeds the respawn loop).
	pcall(processCrashes, dt)
	-- Stage 7 strike telemetry (dev instrument; inert unless GameConfig.Combat.strikeTelemetry).
	pcall(updateStrikeTelemetry)
end

--------------------------------------------------------------------------------
-- INITIALIZATION  (call order matters; everything below runs once at startup)
--------------------------------------------------------------------------------
-- S51 BOOT-BARRIER FIX (Chad: round 1 was over before the map ever rendered). RescueServer's round
-- loop free-runs on wall clock with no idea GameServer is still mid-boot: it 60s-waits on the `Birds`
-- folder (created lazily on first spawn) and races straight into round 1 while WorldGen.build is still
-- sculpting terrain. Two independent fixes:
--   (a) create Birds EAGERLY here (find-or-create — ensureBirdContainer is idempotent with spawnFor's
--       lazy path) so RescueServer's WaitForChild resolves in ms, not near its 60s timeout.
--   (b) publish Workspace:SetAttribute("WorldReady", true) once the world build (whichever of the 3
--       branches below runs) is done, so RescueServer can barrier its own boot on it instead of guessing.
local bootT0 = os.clock()
-- S50 audit FIX 1: Remotes exist BEFORE (and independent of) the world build. WorldGen.build sculpts a
-- real Terrain valley (~554 fills, yields every 24 ops — S49 boot-crash class) and previously ran
-- un-pcalled ahead of CreateRemotes/connectRemotes, so a WorldGen exception left every Remote missing
-- and every client stuck waiting forever. CreateThermals is pure math off GameConfig.Thermals (no
-- terrain/position sampling — see the per-i loop below), so it moves up with the Remotes.
CreateThermals()
CreateRemotes()
connectRemotes()
ensureBirdContainer() -- S51: eager Birds folder — see boot-barrier note above.
local remotesElapsed = os.clock() - bootT0

-- M1 (Phase V): behind GameConfig.Map.worldV2, WorldGen.build sets the birth contract
-- (Gravity + StreamingEnabled, matching legacy BuildMap:260/267), sculpts the Terrain valley +
-- mountain rim + water-with-solid-floors, and applies lighting rig v2. Flag off = the untouched
-- legacy gray-box path (SetupLighting + BuildMap — the exact pair the flag-off branch always ran).
-- pcall'd: a WorldGen failure now falls back to the legacy world instead of leaving Workspace half-built
-- with Remotes already up (the client can still join/see a world, even if not the intended one).
local worldT0 = os.clock()
if GameConfig.Map and GameConfig.Map.worldV2 then
	local okBuild, errBuild = pcall(WorldGen.build, Workspace, GameConfig)
	if not okBuild then
		warn("[Boot] WorldGen.build FAILED: " .. tostring(errBuild) .. " — falling back to legacy world")
		pcall(SetupLighting)
		pcall(BuildMap)
	end
else
	-- Kill-switch honesty: the flag-off path clears the worldV2 Terrain (harmless on a legacy boot —
	-- terrain is already empty and BuildMap rebuilds its own Map folder) so the comment is literally true.
	WorldGen.clear(Workspace)
	SetupLighting()
	BuildMap()
end
-- S51: WorldReady fires after ALL THREE branches above (worldV2 success, worldV2-pcall-failed
-- fallback, and worldV2=false legacy) — every path leaves Workspace in a playable state by here.
Workspace:SetAttribute("WorldReady", true)
local worldElapsed = os.clock() - worldT0
print(string.format("[BootClock] remotes=%.3fs worldbuild=%.3fs total=%.3fs", remotesElapsed, worldElapsed, os.clock() - bootT0))

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
