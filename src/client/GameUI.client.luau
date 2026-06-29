--!nonstrict
--[[
	GameUI — Polished HUD for Eagles vs Crows (LocalScript in StarterPlayerScripts)

	Builds the entire HUD in code (no Studio assets) using GameConfig.UI for all
	colors/fonts/transparency. Runs safely before TeamAssigned fires.

	NOTE: lives in StarterPlayerScripts, NOT StarterGui. With CharacterAutoLoads=false
	(standalone-bird-model design) StarterGui is never copied to PlayerGui, so a HUD
	script there would never run. From StarterPlayerScripts it runs on join and parents
	its own ScreenGui to PlayerGui directly.

	Exposed hooks (called by BirdController):
		_G.UpdateStaminaUI(ratio)   -- 0..1 stamina fill
		_G.SetStallWarning(isStalling)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned   = Remotes:WaitForChild("TeamAssigned")
local ScoreUpdate    = Remotes:WaitForChild("ScoreUpdate")
local GameNotification = Remotes:WaitForChild("GameNotification")
local TakeDamage     = Remotes:WaitForChild("TakeDamage")

local player = Players.LocalPlayer
local UI = GameConfig.UI

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- HIT FLASH (full-screen red; flashed on TakeDamage when local player targeted)
--------------------------------------------------------------------------------
local hitFlash = Instance.new("Frame")
hitFlash.Name = "HitFlash"
hitFlash.Size = UDim2.new(1, 0, 1, 0)
hitFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
hitFlash.BackgroundTransparency = 1
hitFlash.BorderSizePixel = 0
hitFlash.ZIndex = 50
hitFlash.Parent = screenGui

--------------------------------------------------------------------------------
-- TEAM BANNER (Top Center)
--------------------------------------------------------------------------------
local teamBanner = Instance.new("Frame")
teamBanner.Name = "TeamBanner"
teamBanner.Size = UDim2.new(0, 300, 0, 60)
teamBanner.Position = UDim2.new(0.5, -150, 0, 10)
teamBanner.BackgroundColor3 = UI.hudColor
teamBanner.BackgroundTransparency = UI.hudTransparency
teamBanner.BorderSizePixel = 0
teamBanner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 10)
bannerCorner.Parent = teamBanner

local teamLabel = Instance.new("TextLabel")
teamLabel.Name = "TeamLabel"
teamLabel.Size = UDim2.new(1, -16, 1, -12)
teamLabel.Position = UDim2.new(0, 8, 0, 6)
teamLabel.BackgroundTransparency = 1
teamLabel.Text = "AWAITING ASSIGNMENT"
teamLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
teamLabel.TextScaled = true
teamLabel.Font = UI.font
teamLabel.Parent = teamBanner

--------------------------------------------------------------------------------
-- SCORE DISPLAY (Top Left)
--------------------------------------------------------------------------------
local scoreFrame = Instance.new("Frame")
scoreFrame.Name = "ScoreFrame"
scoreFrame.Size = UDim2.new(0, 250, 0, 50)
scoreFrame.Position = UDim2.new(0, 15, 0, 15)
scoreFrame.BackgroundColor3 = UI.hudColor
scoreFrame.BackgroundTransparency = UI.hudTransparency
scoreFrame.BorderSizePixel = 0
scoreFrame.Parent = screenGui

local scoreCorner = Instance.new("UICorner")
scoreCorner.CornerRadius = UDim.new(0, 8)
scoreCorner.Parent = scoreFrame

local eagleScoreLabel = Instance.new("TextLabel")
eagleScoreLabel.Name = "EagleScore"
eagleScoreLabel.Size = UDim2.new(0.5, -8, 1, -10)
eagleScoreLabel.Position = UDim2.new(0, 4, 0, 5)
eagleScoreLabel.BackgroundTransparency = 1
eagleScoreLabel.Text = "EAGLES 0"
eagleScoreLabel.TextColor3 = UI.eagleAccent
eagleScoreLabel.Font = UI.font
eagleScoreLabel.TextScaled = true
eagleScoreLabel.Parent = scoreFrame

local crowScoreLabel = Instance.new("TextLabel")
crowScoreLabel.Name = "CrowScore"
crowScoreLabel.Size = UDim2.new(0.5, -8, 1, -10)
crowScoreLabel.Position = UDim2.new(0.5, 4, 0, 5)
crowScoreLabel.BackgroundTransparency = 1
crowScoreLabel.Text = "0 CROWS"
crowScoreLabel.TextColor3 = UI.crowAccent
crowScoreLabel.Font = UI.font
crowScoreLabel.TextScaled = true
crowScoreLabel.Parent = scoreFrame

--------------------------------------------------------------------------------
-- STATUS BARS (Bottom Center): Health (HP) + Stamina (FLY)
--------------------------------------------------------------------------------
local barsFrame = Instance.new("Frame")
barsFrame.Name = "BarsFrame"
barsFrame.Size = UDim2.new(0, 300, 0, 70)
barsFrame.Position = UDim2.new(0.5, -150, 1, -85)
barsFrame.BackgroundColor3 = UI.hudColor
barsFrame.BackgroundTransparency = UI.hudTransparency
barsFrame.BorderSizePixel = 0
barsFrame.Parent = screenGui

local barsCorner = Instance.new("UICorner")
barsCorner.CornerRadius = UDim.new(0, 8)
barsCorner.Parent = barsFrame

-- Health Bar
local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthLabel"
healthLabel.Size = UDim2.new(0, 55, 0, 20)
healthLabel.Position = UDim2.new(0, 10, 0, 8)
healthLabel.BackgroundTransparency = 1
healthLabel.Text = "HP"
healthLabel.TextColor3 = UI.healthBarColor
healthLabel.Font = UI.font
healthLabel.TextScaled = true
healthLabel.Parent = barsFrame

local healthBarBg = Instance.new("Frame")
healthBarBg.Name = "HealthBarBg"
healthBarBg.Size = UDim2.new(1, -80, 0, 20)
healthBarBg.Position = UDim2.new(0, 70, 0, 8)
healthBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
healthBarBg.BorderSizePixel = 0
healthBarBg.Parent = barsFrame

local healthBgCorner = Instance.new("UICorner")
healthBgCorner.CornerRadius = UDim.new(0, 4)
healthBgCorner.Parent = healthBarBg

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "HealthBarFill"
healthBarFill.Size = UDim2.new(1, 0, 1, 0)
healthBarFill.BackgroundColor3 = UI.healthBarColor
healthBarFill.BorderSizePixel = 0
healthBarFill.Parent = healthBarBg

local healthFillCorner = Instance.new("UICorner")
healthFillCorner.CornerRadius = UDim.new(0, 4)
healthFillCorner.Parent = healthBarFill

-- Stamina Bar
local staminaLabel = Instance.new("TextLabel")
staminaLabel.Name = "StaminaLabel"
staminaLabel.Size = UDim2.new(0, 55, 0, 20)
staminaLabel.Position = UDim2.new(0, 10, 0, 38)
staminaLabel.BackgroundTransparency = 1
staminaLabel.Text = "FLY"
staminaLabel.TextColor3 = UI.staminaBarColor
staminaLabel.Font = UI.font
staminaLabel.TextScaled = true
staminaLabel.Parent = barsFrame

local staminaBarBg = Instance.new("Frame")
staminaBarBg.Name = "StaminaBarBg"
staminaBarBg.Size = UDim2.new(1, -80, 0, 20)
staminaBarBg.Position = UDim2.new(0, 70, 0, 38)
staminaBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
staminaBarBg.BorderSizePixel = 0
staminaBarBg.Parent = barsFrame

local staminaBgCorner = Instance.new("UICorner")
staminaBgCorner.CornerRadius = UDim.new(0, 4)
staminaBgCorner.Parent = staminaBarBg

local staminaBarFill = Instance.new("Frame")
staminaBarFill.Name = "StaminaBarFill"
staminaBarFill.Size = UDim2.new(1, 0, 1, 0)
staminaBarFill.BackgroundColor3 = UI.staminaBarColor
staminaBarFill.BorderSizePixel = 0
staminaBarFill.Parent = staminaBarBg

local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = UDim.new(0, 4)
staminaFillCorner.Parent = staminaBarFill

--------------------------------------------------------------------------------
-- FLIGHT DATA (Bottom Left): SPD + ALT
--------------------------------------------------------------------------------
local flightDataFrame = Instance.new("Frame")
flightDataFrame.Name = "FlightDataFrame"
flightDataFrame.Size = UDim2.new(0, 160, 0, 70)
flightDataFrame.Position = UDim2.new(0, 15, 1, -95)
flightDataFrame.BackgroundColor3 = UI.hudColor
flightDataFrame.BackgroundTransparency = UI.hudTransparency
flightDataFrame.BorderSizePixel = 0
flightDataFrame.Parent = screenGui

local dataCorner = Instance.new("UICorner")
dataCorner.CornerRadius = UDim.new(0, 8)
dataCorner.Parent = flightDataFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(1, -16, 0, 28)
speedLabel.Position = UDim2.new(0, 8, 0, 6)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "SPD: 0"
speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Font = UI.fontMedium
speedLabel.TextScaled = true
speedLabel.Parent = flightDataFrame

local altLabel = Instance.new("TextLabel")
altLabel.Name = "AltLabel"
altLabel.Size = UDim2.new(1, -16, 0, 28)
altLabel.Position = UDim2.new(0, 8, 0, 36)
altLabel.BackgroundTransparency = 1
altLabel.Text = "ALT: 0"
altLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
altLabel.TextXAlignment = Enum.TextXAlignment.Left
altLabel.Font = UI.fontMedium
altLabel.TextScaled = true
altLabel.Parent = flightDataFrame

--------------------------------------------------------------------------------
-- INCIDENCE GAUGE (Bottom Left, right of SPD/ALT): the bird BODY's pitch attitude vs
-- the world horizon. A fixed horizontal line = the horizon at 0°; the bright pointer =
-- the bird's body, rotated to its nose-up/nose-down angle. Pure attitude — it does NOT
-- measure AoA, lift, or stall. Numeric readout below. Pushed via _G.SetIncidence(deg).
--------------------------------------------------------------------------------
-- Persistent handles SetIncidence / the reset path mutate each frame. Built inside the
-- do-block below so the transient construction locals (corners, dial, title, hub, makeBar)
-- stay scoped there and don't add to the main chunk's local count.
local incPointer, incTip, incLabel
do
	local AOA_DIAL = 110 -- px square dial
	local aoaGauge = Instance.new("Frame")
	aoaGauge.Name = "IncidenceGauge"
	aoaGauge.Size = UDim2.new(0, 140, 0, 164)
	aoaGauge.Position = UDim2.new(0, 185, 1, -189)
	aoaGauge.BackgroundColor3 = UI.hudColor
	aoaGauge.BackgroundTransparency = UI.hudTransparency
	aoaGauge.BorderSizePixel = 0
	aoaGauge.Parent = screenGui

	local aoaGaugeCorner = Instance.new("UICorner")
	aoaGaugeCorner.CornerRadius = UDim.new(0, 8)
	aoaGaugeCorner.Parent = aoaGauge

	local aoaTitle = Instance.new("TextLabel")
	aoaTitle.Name = "Title"
	aoaTitle.Size = UDim2.new(1, -12, 0, 18)
	aoaTitle.Position = UDim2.new(0, 6, 0, 4)
	aoaTitle.BackgroundTransparency = 1
	aoaTitle.Text = "ANGLE OF INCIDENCE"
	aoaTitle.TextColor3 = Color3.fromRGB(180, 190, 205)
	aoaTitle.TextXAlignment = Enum.TextXAlignment.Left
	aoaTitle.Font = UI.fontMedium
	aoaTitle.TextScaled = true
	aoaTitle.Parent = aoaGauge

	-- The square dial that holds the rotating bars (center = pivot for everything inside).
	local aoaDial = Instance.new("Frame")
	aoaDial.Name = "Dial"
	aoaDial.AnchorPoint = Vector2.new(0.5, 0)
	aoaDial.Position = UDim2.new(0.5, 0, 0, 22)
	aoaDial.Size = UDim2.new(0, AOA_DIAL, 0, AOA_DIAL)
	aoaDial.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	aoaDial.BackgroundTransparency = 0.35
	aoaDial.BorderSizePixel = 0
	aoaDial.Parent = aoaGauge

	local aoaDialCorner = Instance.new("UICorner")
	aoaDialCorner.CornerRadius = UDim.new(1, 0) -- circular
	aoaDialCorner.Parent = aoaDial

	-- Helper: a bar that pivots about the dial center. `fromCenter` true => extends to the
	-- right only (a radial pointer/tick); false => a full line through the center.
	local function makeBar(name, length, thickness, color, transparency, fromCenter)
		local bar = Instance.new("Frame")
		bar.Name = name
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = transparency or 0
		if fromCenter then
			bar.AnchorPoint = Vector2.new(0, 0.5)
		else
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
		end
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.Size = UDim2.new(0, length, 0, thickness)
		bar.Parent = aoaDial
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = bar
		return bar
	end

	local radius = AOA_DIAL * 0.46
	local INC_COLOR = Color3.fromRGB(120, 210, 255) -- single neutral color (no stall meaning)
	-- Horizon reference: a full horizontal line through the center = 0° (level).
	makeBar("Horizon", radius * 2, 2, Color3.fromRGB(120, 140, 160), 0.15, false)
	-- The body pointer — rotates to the bird's nose-up/nose-down attitude.
	incPointer = makeBar("Pointer", radius, 5, INC_COLOR, 0, true)
	incPointer.ZIndex = 3
	-- Tip dot at the pointer's nose end (rides with the pointer's rotation as its child).
	incTip = Instance.new("Frame")
	incTip.Name = "Tip"
	incTip.AnchorPoint = Vector2.new(0.5, 0.5)
	incTip.Position = UDim2.new(1, 0, 0.5, 0)
	incTip.Size = UDim2.new(0, 12, 0, 12)
	incTip.BackgroundColor3 = INC_COLOR
	incTip.BorderSizePixel = 0
	incTip.ZIndex = 4
	incTip.Parent = incPointer
	local aoaTipCorner = Instance.new("UICorner")
	aoaTipCorner.CornerRadius = UDim.new(1, 0)
	aoaTipCorner.Parent = incTip
	-- Center hub.
	local aoaHub = Instance.new("Frame")
	aoaHub.Name = "Hub"
	aoaHub.AnchorPoint = Vector2.new(0.5, 0.5)
	aoaHub.Position = UDim2.new(0.5, 0, 0.5, 0)
	aoaHub.Size = UDim2.new(0, 10, 0, 10)
	aoaHub.BackgroundColor3 = Color3.fromRGB(210, 220, 235)
	aoaHub.BorderSizePixel = 0
	aoaHub.ZIndex = 5
	aoaHub.Parent = aoaDial
	local aoaHubCorner = Instance.new("UICorner")
	aoaHubCorner.CornerRadius = UDim.new(1, 0)
	aoaHubCorner.Parent = aoaHub

	-- Numeric readout (one decimal, signed).
	incLabel = Instance.new("TextLabel")
	incLabel.Name = "IncidenceValue"
	incLabel.Size = UDim2.new(1, -12, 0, 26)
	incLabel.Position = UDim2.new(0, 6, 1, -28)
	incLabel.BackgroundTransparency = 1
	incLabel.Text = "0.0\194\176"
	incLabel.TextColor3 = Color3.fromRGB(120, 210, 255)
	incLabel.TextXAlignment = Enum.TextXAlignment.Center
	incLabel.Font = UI.font
	incLabel.TextScaled = true
	incLabel.Parent = aoaGauge
end

--------------------------------------------------------------------------------
-- STALL WARNING (hidden by default; blinks while active)
--------------------------------------------------------------------------------
local stallWarning = Instance.new("TextLabel")
stallWarning.Name = "StallWarning"
stallWarning.Size = UDim2.new(0, 240, 0, 50)
stallWarning.Position = UDim2.new(0.5, -120, 0.32, 0)
stallWarning.BackgroundTransparency = 1
stallWarning.Text = "!! STALL !!"
stallWarning.TextColor3 = Color3.fromRGB(255, 50, 50)
stallWarning.Font = UI.font
stallWarning.TextScaled = true
stallWarning.Visible = false
stallWarning.ZIndex = 5
stallWarning.Parent = screenGui

--------------------------------------------------------------------------------
-- CROSSHAIR (screen center)
--------------------------------------------------------------------------------
local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 10, 0, 10)
crosshair.Position = UDim2.new(0.5, -5, 0.5, -5)
crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
crosshair.BackgroundTransparency = 0.4
crosshair.BorderSizePixel = 0
crosshair.ZIndex = 3
crosshair.Parent = screenGui

local chCorner = Instance.new("UICorner")
chCorner.CornerRadius = UDim.new(1, 0)
chCorner.Parent = crosshair

--------------------------------------------------------------------------------
-- CONTROL HINT (bottom center) — tells the player about free-look + camera pan.
--------------------------------------------------------------------------------
local controlHint = Instance.new("TextLabel")
controlHint.Name = "ControlHint"
controlHint.Size = UDim2.new(0, 460, 0, 22)
controlHint.Position = UDim2.new(0.5, -230, 1, -34)
controlHint.BackgroundTransparency = 1
controlHint.Text = "Hold SPACE to free-look  \194\183  move the MOUSE to pan the camera"
controlHint.TextColor3 = Color3.fromRGB(235, 240, 245)
controlHint.TextStrokeTransparency = 0.5
controlHint.TextTransparency = 0.15
controlHint.Font = UI.fontMedium
controlHint.TextScaled = true
controlHint.ZIndex = 4
controlHint.Parent = screenGui

--------------------------------------------------------------------------------
-- NOTIFICATION DISPLAY (Top Right)
--------------------------------------------------------------------------------
local notifFrame = Instance.new("Frame")
notifFrame.Name = "NotifFrame"
notifFrame.Size = UDim2.new(0, 300, 0, 40)
notifFrame.Position = UDim2.new(1, -315, 0, 80)
notifFrame.BackgroundColor3 = UI.hudColor
notifFrame.BackgroundTransparency = 0.5
notifFrame.BorderSizePixel = 0
notifFrame.Visible = false
notifFrame.Parent = screenGui

local notifCorner = Instance.new("UICorner")
notifCorner.CornerRadius = UDim.new(0, 8)
notifCorner.Parent = notifFrame

local notifLabel = Instance.new("TextLabel")
notifLabel.Name = "NotifLabel"
notifLabel.Size = UDim2.new(1, -16, 1, -8)
notifLabel.Position = UDim2.new(0, 8, 0, 4)
notifLabel.BackgroundTransparency = 1
notifLabel.Text = ""
notifLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
notifLabel.Font = UI.font
notifLabel.TextScaled = true
notifLabel.Parent = notifFrame

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------
TeamAssigned.OnClientEvent:Connect(function(teamName, profile)
	teamName = teamName or ""
	teamLabel.Text = "TEAM " .. string.upper(teamName)
	local isEagles = (teamName == "Eagles")
	teamLabel.TextColor3 = isEagles and UI.eagleAccent or UI.crowAccent
	teamBanner.BackgroundColor3 = isEagles and Color3.fromRGB(60, 50, 20) or Color3.fromRGB(30, 20, 45)
end)

ScoreUpdate.OnClientEvent:Connect(function(scores)
	if type(scores) ~= "table" then return end
	eagleScoreLabel.Text = "EAGLES " .. tostring(scores.Eagles or 0)
	crowScoreLabel.Text = tostring(scores.Crows or 0) .. " CROWS"
end)

local notifToken = 0
GameNotification.OnClientEvent:Connect(function(text, color)
	notifLabel.Text = tostring(text or "")
	notifLabel.TextColor3 = color or Color3.new(1, 1, 1)
	notifFrame.Visible = true

	notifToken += 1
	local myToken = notifToken
	task.delay(3, function()
		-- Only hide if no newer notification replaced this one.
		if myToken == notifToken then
			notifFrame.Visible = false
		end
	end)
end)

-- HitFlash on local-player damage (BirdController also drives this; supported here too).
TakeDamage.OnClientEvent:Connect(function(attackerName, targetPlayer, damage)
	if targetPlayer == player then
		hitFlash.BackgroundTransparency = 0.5
		TweenService:Create(
			hitFlash,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end
end)

--------------------------------------------------------------------------------
-- PER-FRAME UPDATE (Health / Speed / Altitude / stall blink)
--
-- No Roblox Character (standalone-model design): read the possessed bird's Body
-- from Workspace.Birds. Health/MaxHealth live as Attributes on the Body; speed and
-- altitude come from its AssemblyLinearVelocity / Position. (See docs/HANDOFF.md.)
--------------------------------------------------------------------------------
local birdsFolder = workspace:WaitForChild("Birds")

-- The bird this HUD reflects: prefer the possessed one, else any bird we own (so
-- HP still shows in the brief gap between a death and an auto-repossess).
local function findMyBird()
	local anyOwned
	for _, model in ipairs(birdsFolder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
			if model:GetAttribute("Possessed") == true then
				return model
			end
			anyOwned = anyOwned or model
		end
	end
	return anyOwned
end

RunService.RenderStepped:Connect(function()
	-- Blink the stall warning while visible.
	if stallWarning.Visible then
		stallWarning.TextTransparency = math.abs(math.sin(tick() * 8)) * 0.6
	end

	local model = findMyBird()
	local body = model and (model.PrimaryPart or model:FindFirstChild("Body"))
	if not body then
		-- No living/possessed bird (death → respawn gap): empty the readouts instead of
		-- freezing the last pre-death values, which read as a still-alive bird.
		healthBarFill.Size = UDim2.new(0, 0, 1, 0)
		staminaBarFill.Size = UDim2.new(0, 0, 1, 0)
		speedLabel.Text = "SPD: 0"
		altLabel.Text = "ALT: 0"
		incLabel.Text = "--"
		incPointer.Rotation = 0
		stallWarning.Visible = false
		return
	end

	-- Health from the Body's "Health" / "MaxHealth" Attributes.
	local hpAttr = body:GetAttribute("Health")
	if typeof(hpAttr) == "number" then
		local maxAttr = body:GetAttribute("MaxHealth")
		local maxHp = (typeof(maxAttr) == "number" and maxAttr > 0) and maxAttr or 100
		healthBarFill.Size = UDim2.new(math.clamp(hpAttr / maxHp, 0, 1), 0, 1, 0)
	end

	-- Flight data from the Body.
	local speed = body.AssemblyLinearVelocity.Magnitude
	speedLabel.Text = "SPD: " .. tostring(math.floor(speed + 0.5))
	altLabel.Text = "ALT: " .. tostring(math.floor(body.Position.Y + 0.5))
end)

--------------------------------------------------------------------------------
-- EXPOSED HOOKS (called by BirdController)
--------------------------------------------------------------------------------
-- Set the stamina fill, ratio 0..1.
function _G.UpdateStaminaUI(ratio)
	ratio = tonumber(ratio) or 0
	staminaBarFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
end

-- Set the body-incidence readout (degrees): the bird body's pitch above/below the world
-- horizon (0°). Rotates the pointer to that attitude so the visual gap from the horizon
-- line IS the angle. + = nose up. Measures nothing aerodynamic (no AoA/lift/stall).
function _G.SetIncidence(deg)
	deg = tonumber(deg) or 0
	incLabel.Text = string.format("%+.1f\194\176", deg)
	-- Nose-up (positive) rotates the rightward pointer up (counter-clockwise = negative
	-- Roblox Rotation). Clamp the SHOWN angle so it can't wrap past vertical.
	incPointer.Rotation = -math.clamp(deg, -90, 90)
end

-- Toggle the blinking stall warning.
function _G.SetStallWarning(isStalling)
	stallWarning.Visible = isStalling and true or false
	if not isStalling then
		stallWarning.TextTransparency = 0
	end
end

print("Game UI Loaded!")
