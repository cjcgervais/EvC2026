--!nonstrict
--[[
	BounceFX.luau — the B3 terrain "oof" presentation, FACTORED OUT of BirdController.

	WHY a module: BirdController's main chunk is at Luau's 200-module-local ceiling (Studio Play compiles
	at debugLevel 2 = no register packing, so every top-level `local`/`local function` costs a register).
	B3 originally added ~8 top-level locals inline and tipped the chunk past 200 → BirdController failed to
	COMPILE at Play → the eagle was inert. All of that state + the three helpers now live here behind ONE
	BirdController local (`local BounceFX = require(...)`). The compile gate (tests/compile.spec.luau, debug 2)
	guards the ceiling from now on.

	PRESENTATION ONLY. `step` never touches flight velocity/orientation, the kernel, the camera, or input —
	it advances a cosmetic world-space "stars" halo over the bird and runs the debounced hard-contact gate,
	returning the impact hardness so the CALLER fires its own feather poof (the feather pool stays in
	BirdController). The graze-slide is entirely the caller's; this only reads the resolve output it's handed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BounceRules = require(ReplicatedStorage:WaitForChild("BounceRules"))

local STAR_TEX = "rbxasset://textures/particles/sparkles_main.dds" -- gray-box "stars"; swap for art later.

local BounceFX = {}

-- Per-client state (this ModuleScript is required once per client → one shared instance, like the bird).
local cooldown = 0        -- s left before another bounce may fire (debounce).
local grazeGap = true     -- true once a graze-free frame has passed since the last bounce (leave-terrain gate).
local dazeT = 0           -- s of daze remaining (>0 while the halo shows).
local gui = nil           -- the anchored world billboard (built once, reused).
local stars = nil         -- the orbiting star labels.

-- Build (once) a small anchored world part carrying a BillboardGui of orbiting "star" labels. Reused each
-- daze — never re-allocated. Cosmetic; anchored, no-collide, no-query — never affects physics.
local function buildGui(cfg)
	if gui then return end
	local n = (cfg and cfg.dazeStarCount) or 4
	local anchor = Instance.new("Part")
	anchor.Name = "DazeAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Locked = true
	local bb = Instance.new("BillboardGui")
	bb.Name = "DazeStars"
	bb.Size = UDim2.fromScale(6, 6)          -- world-space size (studs) — a small halo over the head.
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Parent = anchor
	local built = {}
	for i = 1, n do
		local s = Instance.new("ImageLabel")
		s.Name = "Star" .. i
		s.Size = UDim2.fromScale(0.28, 0.28)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.BackgroundTransparency = 1
		s.Image = STAR_TEX
		s.ImageColor3 = Color3.fromRGB(255, 240, 140)  -- cartoon "seeing stars" yellow.
		s.Parent = bb
		built[i] = s
	end
	anchor.Parent = workspace
	gui = anchor
	stars = built
end

-- Advance the daze halo one frame: hover over the bird's head and spin/fade the stars. World-space only.
local function updateHalo(dt, birdPos, cfg)
	if not gui then return end
	if dazeT <= 0 then
		for _, s in ipairs(stars or {}) do s.Visible = false end   -- hide, keep pooled.
		return
	end
	dazeT = math.max(0, dazeT - dt)
	gui.Position = birdPos or gui.Position
	local total = (cfg and cfg.dazeTime) or 1.5
	local fade = math.clamp(dazeT / math.max(0.01, total), 0, 1)   -- fade out as the daze ends.
	local list = stars or {}
	local spin = os.clock() * 4                                    -- orbit angular position.
	for i, s in ipairs(list) do
		s.Visible = true
		local ang = spin + (i / math.max(1, #list)) * math.pi * 2
		s.Position = UDim2.fromScale(0.5 + 0.35 * math.cos(ang), 0.35 + 0.18 * math.sin(ang * 2))
		s.ImageTransparency = 1 - fade
	end
end

-- The per-frame entry point. Advances cooldown + the daze halo, and runs the hard-contact gate.
--   dt          : frame delta.
--   birdPos     : world position to park the halo (bird head); pass rootPart.Position + up*5.
--   hitInfo     : the terrain graze hit from BirdCollision.resolve, OR nil if the caller decides no
--                 eligible contact this frame (nil re-arms the leave-terrain gate).
--   preSlideVel : the bird's velocity BEFORE the graze-slide stripped the into-surface component.
--   cfg         : GameConfig.Rescue (bounceMinSpeed / bounceDebounce / dazeTime / dazeStarCount).
-- Returns the impact hardness in [0,1] on the frame a bounce FIRES (the caller does the feather poof),
-- else nil. Never mutates flight/camera/input.
function BounceFX.step(dt, birdPos, hitInfo, preSlideVel, cfg)
	if cooldown > 0 then cooldown = math.max(0, cooldown - dt) end
	updateHalo(dt, birdPos, cfg)
	if not hitInfo then
		grazeGap = true    -- no contact this frame → re-arm the leave-terrain gate.
		return nil
	end
	-- Impact hardness = into-surface closing speed from the resolve output (the SAME quantity BirdCollision
	-- uses for its lethal gate). Read the PRE-slide velocity (the slide already stripped the into-surface part).
	local closing = BounceRules.closingSpeed(preSlideVel, hitInfo.Normal)
	local minSpd = (cfg and cfg.bounceMinSpeed) or 55
	if not BounceRules.shouldBounce(closing, minSpd, cooldown, grazeGap) then
		return nil
	end
	buildGui(cfg)
	dazeT = (cfg and cfg.dazeTime) or 1.5
	cooldown = (cfg and cfg.bounceDebounce) or 0.6
	grazeGap = false       -- must leave terrain (a graze-free frame) before the next bounce.
	return BounceRules.hardness01(closing, minSpd)
end

return BounceFX
