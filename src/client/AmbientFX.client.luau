--!nonstrict
--[[
	AmbientFX — "burning valley" ambient atmosphere (LocalScript in StarterPlayerScripts)

	WHAT IT IS
	  A purely-cosmetic, asset-free client particle field that makes the golden-hour
	  forest-fire valley feel alive as you fly: drifting warm EMBERS, falling ASH, and
	  (optionally) very-faint golden HAZE motes catching the light. No meshes, no
	  textures, no server calls — just three ParticleEmitters riding an invisible
	  camera-following host part, emitting into WORLD space so the field drifts past you.

	ISOLATION
	  This is a SEPARATE, self-contained script. It does NOT touch BirdController
	  (the LOCKED control/camera/aim/kernel file), GameUI, or any shared logic. It only
	  reads GameConfig.Ambient. Deleting this file + its rojo mapping fully removes it.

	LEGIBILITY CONSTRAINT (subordinate to kid-legibility — SIGNED OFF, must NOT regress)
	  The particles are SUBTLE, SPARSE, PERIPHERAL mood — never a screen-filling storm
	  that obscures gameplay. Low rates, small sizes, high transparency, warm glow. A kid
	  must still instantly spot a squirrel/beacon through them. Erring toward too-subtle
	  is CORRECT here. Tune DOWN, not up (GameConfig.Ambient).

	KILL SWITCH
	  GameConfig.Ambient.enabled == false → this script early-returns and creates ZERO
	  instances (no host part, no emitters, no RenderStepped hook). One-flag revert.

	PERF
	  Exactly ONE per-frame action: a single CFrame write on the host part (no allocation,
	  no queries, no other work). Total live-particle budget is intentionally modest so an
	  always-on-screen effect never regresses the "renders in slow" history.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

-- Config + defaults (script works even if the Ambient table is absent).
local cfg         = GameConfig.Ambient or {}
local ENABLED     = cfg.enabled
if ENABLED == nil then ENABLED = true end        -- default enabled if the flag is missing
local EMBER_RATE  = cfg.emberRate or 10
local ASH_RATE    = cfg.ashRate or 8
local HAZE_ON     = cfg.hazeEnabled
if HAZE_ON == nil then HAZE_ON = true end
local HAZE_RATE   = cfg.hazeRate or 4
local VOLUME      = cfg.volume or 320

-- KILL SWITCH — do nothing, create nothing.
if not ENABLED then
	return
end

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Camera-following host part. Invisible, inert, massless. The emitters are parented
-- to the PART (not a point Attachment) so they emit from its BOUNDING-BOX VOLUME —
-- a wide, somewhat-flat box centered on the camera. That distributes particles at
-- VARIED DEPTHS around/past the view instead of clustering at the lens (dead-center,
-- over the squirrel/beacon), which is the exact near-lens legibility risk we avoid.
-- Because every emitter is LockedToPart = false, spawned particles live in WORLD
-- space and drift independently as the camera moves — a continuous ambient field.
--------------------------------------------------------------------------------
local host = Instance.new("Part")
host.Name         = "AmbientFXHost"
host.Anchored     = true
host.CanCollide   = false
host.CanQuery     = false
host.CanTouch     = false
host.CastShadow   = false
host.Massless     = true
host.Transparency = 1
host.Size         = Vector3.new(VOLUME, VOLUME * 0.625, VOLUME)  -- wide, flatter emission volume around the view
host.Locked       = true

--------------------------------------------------------------------------------
-- Emitter helpers. All emitters:
--   • LockedToPart = false          -> particles decouple into world space
--   • Drag > 0                      -> velocities ease out (soft, floaty)
--   • high Transparency, small size -> peripheral, never foreground clutter
--------------------------------------------------------------------------------

-- 1) EMBERS — small warm orange→amber glowing motes on a soft breeze.
local embers = Instance.new("ParticleEmitter")
embers.Name         = "AmbientEmbers"
embers.Color        = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 40)),   -- orange
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 205, 120)),  -- amber
})
embers.LightEmission = 0.6                                        -- additive glow (warm, not gory)
embers.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   1.0),
	NumberSequenceKeypoint.new(0.5, 2.4),                         -- gentle flicker in scale
	NumberSequenceKeypoint.new(1,   0.6),
})
embers.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   0.4),
	NumberSequenceKeypoint.new(0.7, 0.6),                         -- flicker in opacity
	NumberSequenceKeypoint.new(1,   1.0),                         -- fade fully out
})
embers.Lifetime      = NumberRange.new(3, 6)
embers.Rate          = EMBER_RATE
embers.Speed         = NumberRange.new(1, 3)
embers.SpreadAngle   = Vector2.new(180, 180)                     -- all around the view
embers.Acceleration  = Vector3.new(6, -2, 3)                     -- soft constant breeze, slight rise loss
embers.Drag          = 0.6
embers.Rotation      = NumberRange.new(0, 360)
embers.RotSpeed      = NumberRange.new(-20, 20)
embers.LockedToPart  = false
embers.Parent        = host

-- 2) ASH — tiny gray specks drifting slowly DOWN.
local ash = Instance.new("ParticleEmitter")
ash.Name         = "AmbientAsh"
ash.Color        = ColorSequence.new(Color3.fromRGB(120, 114, 108), Color3.fromRGB(90, 86, 82))
ash.LightEmission = 0
ash.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 1.5),
})
ash.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   0.5),
	NumberSequenceKeypoint.new(0.8, 0.7),
	NumberSequenceKeypoint.new(1,   1.0),
})
ash.Lifetime      = NumberRange.new(4, 7)
ash.Rate          = ASH_RATE
ash.Speed         = NumberRange.new(1, 2)
ash.SpreadAngle   = Vector2.new(180, 180)
ash.Acceleration  = Vector3.new(4, -5, 2)                        -- settles downward on a light breeze
ash.Drag          = 0.8
ash.Rotation      = NumberRange.new(0, 360)
ash.RotSpeed      = NumberRange.new(-15, 15)
ash.LockedToPart  = false
ash.Parent        = host

-- 3) HAZE — very faint, larger golden dust motes catching the light. Optional; the
--    faintest of the three (0.85→1 transparency) so it never fogs gameplay.
if HAZE_ON then
	local haze = Instance.new("ParticleEmitter")
	haze.Name         = "AmbientHaze"
	haze.Color        = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	haze.LightEmission = 0.35
	haze.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 8),
		NumberSequenceKeypoint.new(1, 16),
	})
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.92),
		NumberSequenceKeypoint.new(0.5, 0.85),                     -- peak is still barely visible
		NumberSequenceKeypoint.new(1,   1.0),
	})
	haze.Lifetime      = NumberRange.new(4, 8)
	haze.Rate          = HAZE_RATE
	haze.Speed         = NumberRange.new(0.5, 1.5)                 -- barely moving
	haze.SpreadAngle   = Vector2.new(180, 180)
	haze.Acceleration  = Vector3.new(1, -0.5, 1)
	haze.Drag          = 1.0
	haze.LockedToPart  = false
	haze.Parent        = host
end

-- Parent the host once the camera exists.
host.Parent = Workspace

--------------------------------------------------------------------------------
-- The ONE per-frame action: keep the host at the camera. Single CFrame write —
-- no allocation, no raycasts, no other work.
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local cam = Workspace.CurrentCamera
	if cam then
		host.CFrame = cam.CFrame
	end
end)

-- Tidy up if the player leaves (avoids a dangling host part in edge cases).
Players.PlayerRemoving:Connect(function(plr)
	if plr == localPlayer and host then
		host:Destroy()
	end
end)
