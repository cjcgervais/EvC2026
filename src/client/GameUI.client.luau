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
local myTeam = nil  -- set from TeamAssigned; used to pick out ENEMY birds for the indicators

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
-- FLAP THROTTLE (Bottom Center, above the bars): the sticky flap throttle (Shift = up-thrust,
-- Ctrl = down-thrust). A centre-zero bar — green right = climb power, amber left = descent power —
-- plus the resulting wingbeat frequency + power-per-stroke. Fed by _G.UpdateFlapUI(throttle, freqHz, power).
--------------------------------------------------------------------------------
local flapFillUp, flapFillDown, flapText
do
	local flapFrame = Instance.new("Frame")
	flapFrame.Name = "FlapFrame"
	flapFrame.Size = UDim2.new(0, 300, 0, 46)
	flapFrame.Position = UDim2.new(0.5, -150, 1, -160) -- just above the HP/FLY bars
	flapFrame.BackgroundColor3 = UI.hudColor
	flapFrame.BackgroundTransparency = UI.hudTransparency
	flapFrame.BorderSizePixel = 0
	flapFrame.Parent = screenGui
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 8); fc.Parent = flapFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 60, 0, 18); title.Position = UDim2.new(0, 10, 0, 4)
	title.BackgroundTransparency = 1; title.Text = "FLAP"; title.Font = UI.font
	title.TextColor3 = Color3.fromRGB(200, 220, 235); title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true; title.Parent = flapFrame

	flapText = Instance.new("TextLabel")
	flapText.Size = UDim2.new(0, 170, 0, 18); flapText.Position = UDim2.new(1, -180, 0, 4)
	flapText.BackgroundTransparency = 1; flapText.Text = "GLIDE"; flapText.Font = UI.fontMedium
	flapText.TextColor3 = Color3.fromRGB(220, 230, 240); flapText.TextXAlignment = Enum.TextXAlignment.Right
	flapText.TextScaled = true; flapText.Parent = flapFrame

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -20, 0, 14); barBg.Position = UDim2.new(0, 10, 0, 26)
	barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30); barBg.BorderSizePixel = 0; barBg.Parent = flapFrame
	local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0, 4); bgc.Parent = barBg

	local tick = Instance.new("Frame") -- centre = glide reference
	tick.AnchorPoint = Vector2.new(0.5, 0.5); tick.Position = UDim2.new(0.5, 0, 0.5, 0)
	tick.Size = UDim2.new(0, 2, 1, 0); tick.BackgroundColor3 = Color3.fromRGB(120, 130, 140)
	tick.BorderSizePixel = 0; tick.ZIndex = 3; tick.Parent = barBg

	flapFillUp = Instance.new("Frame") -- climb power: grows RIGHT from centre
	flapFillUp.AnchorPoint = Vector2.new(0, 0.5); flapFillUp.Position = UDim2.new(0.5, 0, 0.5, 0)
	flapFillUp.Size = UDim2.new(0, 0, 1, 0); flapFillUp.BackgroundColor3 = Color3.fromRGB(90, 210, 120)
	flapFillUp.BorderSizePixel = 0; flapFillUp.Parent = barBg
	local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 4); uc.Parent = flapFillUp

	flapFillDown = Instance.new("Frame") -- descent power: grows LEFT from centre
	flapFillDown.AnchorPoint = Vector2.new(1, 0.5); flapFillDown.Position = UDim2.new(0.5, 0, 0.5, 0)
	flapFillDown.Size = UDim2.new(0, 0, 1, 0); flapFillDown.BackgroundColor3 = Color3.fromRGB(230, 160, 80)
	flapFillDown.BorderSizePixel = 0; flapFillDown.Parent = barBg
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 4); dc.Parent = flapFillDown
end

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
crosshair.BackgroundTransparency = 0.8 -- faint dead-centre dot (was 0.4 — player wanted it more transparent)
crosshair.BorderSizePixel = 0
crosshair.ZIndex = 3
crosshair.Parent = screenGui

local chCorner = Instance.new("UICorner")
chCorner.CornerRadius = UDim.new(1, 0)
chCorner.Parent = crosshair

--------------------------------------------------------------------------------
-- CONTROL HINT (bottom center) — headlines SPACE (the critical situational-awareness
-- toggle) and lists the live bindings. RichText so SPACE pops as the headline. Player ask
-- 2026-06-30: "the controls HUD [should] tell of this critical button"; and the old hint was
-- STALE ("hold SPACE" — free-look is a TOGGLE now). Every binding here matches the build:
-- SPACE = toggle free-look, MOUSE steers flight, LEFT-CLICK = strike, RIGHT-CLICK = aim/zoom,
-- SHIFT/CTRL = flap throttle.
--------------------------------------------------------------------------------
local controlHint = Instance.new("TextLabel")
controlHint.Name = "ControlHint"
controlHint.Size = UDim2.new(0, 620, 0, 24)
controlHint.Position = UDim2.new(0.5, -310, 1, -36)
controlHint.BackgroundTransparency = 1
controlHint.RichText = true
controlHint.Text = "<b><font color=\"#ffd24a\">SPACE</font></b> = toggle <b>FREE-LOOK</b> (look around!)   \194\183   MOUSE steers   \194\183   LEFT-CLICK strike   \194\183   RIGHT-CLICK aim/zoom   \194\183   SHIFT/CTRL flap"
controlHint.TextColor3 = Color3.fromRGB(235, 240, 245)
controlHint.TextStrokeTransparency = 0.5
controlHint.TextTransparency = 0.1
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
	myTeam = teamName
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

--------------------------------------------------------------------------------
-- STRIKE METER (eagle only) — the directional-strike gauge. One bar (ready / active / cooldown)
-- plus an ARMED-ZONE indicator (BEAK / TALON) whose lit chip = the strike a LEFT-CLICK would throw,
-- auto-picked by which zone the nearest enemy is in. Fed by the server via Body attributes StrikeMeter
-- (0..1), StrikeActive (bool), StrikeArmedDir ("beak"|"talon"|"none"). Hidden for crows (eagle-only attrs).
--------------------------------------------------------------------------------
local weaponsFrame
local strikeFill, armedChips
do
	weaponsFrame = Instance.new("Frame")
	weaponsFrame.Name = "StrikeFrame"
	weaponsFrame.Size = UDim2.new(0, 214, 0, 60)
	weaponsFrame.Position = UDim2.new(1, -229, 1, -85) -- bottom-right
	weaponsFrame.BackgroundColor3 = UI.hudColor
	weaponsFrame.BackgroundTransparency = UI.hudTransparency
	weaponsFrame.BorderSizePixel = 0
	weaponsFrame.Visible = false
	weaponsFrame.Parent = screenGui
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 8); fc.Parent = weaponsFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 70, 0, 20); title.Position = UDim2.new(0, 10, 0, 6)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(235, 235, 235); title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "STRIKE"; title.Parent = weaponsFrame

	-- Armed-zone chips (the lit one = the strike a LEFT-CLICK throws now, auto-picked by enemy proximity).
	armedChips = {}
	local order = { "beak", "talon" }
	local chipText = { beak = "\u{25B2} BEAK", talon = "TALON \u{25BC}" }
	for i, key in ipairs(order) do
		local chip = Instance.new("TextLabel")
		chip.Name = "Chip_" .. key
		chip.Size = UDim2.new(0, 58, 0, 18)
		chip.Position = UDim2.new(0, 88 + (i - 1) * 60, 0, 8)
		chip.BackgroundTransparency = 1
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 13
		chip.TextColor3 = Color3.fromRGB(90, 100, 110) -- dim until armed
		chip.Text = chipText[key]
		chip.Parent = weaponsFrame
		armedChips[key] = chip
	end

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, -20, 0, 16)
	bg.Position = UDim2.new(0, 10, 0, 36)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = weaponsFrame
	local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0, 4); bgc.Parent = bg

	strikeFill = Instance.new("Frame")
	strikeFill.Size = UDim2.new(1, 0, 1, 0)
	strikeFill.BackgroundColor3 = Color3.fromRGB(120, 200, 120)
	strikeFill.BorderSizePixel = 0
	strikeFill.Parent = bg
	local fillc = Instance.new("UICorner"); fillc.CornerRadius = UDim.new(0, 4); fillc.Parent = strikeFill
end

-- Paint the strike bar by state (green = active/can hit, blue = ready, amber = cooling down) and
-- light the armed-zone chip the server reports an enemy is engaging ("beak"/"talon"; "none" lights neither).
local function paintStrike(meter, active, armedDir)
	strikeFill.Size = UDim2.new(math.clamp(meter, 0, 1), 0, 1, 0)
	if active then
		strikeFill.BackgroundColor3 = Color3.fromRGB(90, 230, 120)
	elseif meter >= 1 then
		strikeFill.BackgroundColor3 = Color3.fromRGB(90, 160, 230)
	else
		strikeFill.BackgroundColor3 = Color3.fromRGB(220, 130, 70)
	end
	for key, chip in pairs(armedChips) do
		chip.TextColor3 = (key == armedDir) and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(90, 100, 110)
	end
end

--------------------------------------------------------------------------------
-- ENEMY INDICATORS — a box (with range) over each on-screen enemy bird, and an edge arrow
-- pointing toward each off-screen one, so the player can find/track crows in the big sky.
--------------------------------------------------------------------------------
local enemyMarkers = {}
local function getMarker(i)
	if enemyMarkers[i] then return enemyMarkers[i] end
	local f = Instance.new("Frame")
	f.Name = "EnemyMarker" .. i
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(40, 40)
	f.BackgroundTransparency = 1
	f.ZIndex = 6
	f.Visible = false
	f.Parent = screenGui

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 95, 95)
	stroke.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = box

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 28
	arrow.TextColor3 = Color3.fromRGB(255, 95, 95)
	arrow.Text = "\u{27A4}" -- ➤ (points +X at rotation 0)
	arrow.Visible = false
	arrow.Parent = f

	local dist = Instance.new("TextLabel")
	dist.Name = "Dist"
	dist.AnchorPoint = Vector2.new(0.5, 0)
	dist.Position = UDim2.new(0.5, 0, 1, 2)
	dist.Size = UDim2.fromOffset(80, 14)
	dist.BackgroundTransparency = 1
	dist.Font = Enum.Font.GothamBold
	dist.TextSize = 12
	dist.TextColor3 = Color3.fromRGB(255, 135, 135)
	dist.TextStrokeTransparency = 0.4
	dist.Text = ""
	dist.Parent = f

	enemyMarkers[i] = f
	return f
end

local function hideEnemyMarkers()
	for i = 1, #enemyMarkers do enemyMarkers[i].Visible = false end
end

local function updateEnemyMarkers(myPos)
	local cam = workspace.CurrentCamera
	if not (myTeam and cam) then hideEnemyMarkers() return end
	local vp = cam.ViewportSize
	local cx, cy = vp.X * 0.5, vp.Y * 0.5
	local used = 0
	for _, m in ipairs(birdsFolder:GetChildren()) do
		local team = m:IsA("Model") and m:GetAttribute("Team")
		if team and team ~= myTeam then
			local eb = m.PrimaryPart or m:FindFirstChild("Body")
			if eb then
				used += 1
				local marker = getMarker(used)
				marker.Visible = true
				local wp = eb.Position
				local sp = cam:WorldToViewportPoint(wp)
				local dist = math.floor((wp - myPos).Magnitude + 0.5)
				marker.Dist.Text = tostring(dist)
				local onScreen = sp.Z > 0 and sp.X >= 0 and sp.X <= vp.X and sp.Y >= 0 and sp.Y <= vp.Y
				if onScreen then
					marker.Box.Visible = true
					marker.Arrow.Visible = false
					marker.Position = UDim2.fromOffset(sp.X, sp.Y)
					local s = math.clamp(2600 / math.max(dist, 1), 16, 64)
					marker.Size = UDim2.fromOffset(s, s)
				else
					-- Off-screen or behind: pin an arrow to the screen edge pointing at it.
					local dx, dy = sp.X - cx, sp.Y - cy
					if sp.Z < 0 then dx, dy = -dx, -dy end
					if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then dy = 1 end
					local margin = 46
					local scale = math.min((cx - margin) / math.max(math.abs(dx), 1e-3),
						(cy - margin) / math.max(math.abs(dy), 1e-3))
					marker.Position = UDim2.fromOffset(cx + dx * scale, cy + dy * scale)
					marker.Size = UDim2.fromOffset(34, 34)
					marker.Box.Visible = false
					marker.Arrow.Visible = true
					marker.Arrow.Rotation = math.deg(math.atan2(dy, dx))
				end
			end
		end
	end
	for i = used + 1, #enemyMarkers do enemyMarkers[i].Visible = false end
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
		weaponsFrame.Visible = false
		hideEnemyMarkers()
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

	-- Strike meter (eagle only): the server sets StrikeMeter/StrikeActive/StrikeArmedDir on the eagle Body.
	local sMeter = body:GetAttribute("StrikeMeter")
	if typeof(sMeter) == "number" and not (GameConfig.Rescue and GameConfig.Rescue.enabled) then
		weaponsFrame.Visible = true
		paintStrike(sMeter, body:GetAttribute("StrikeActive") == true, body:GetAttribute("StrikeArmedDir"))
	else
		weaponsFrame.Visible = false
	end

	-- Enemy indicators (boxes over on-screen crows, edge arrows for off-screen ones).
	updateEnemyMarkers(body.Position)
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

-- Flap throttle readout: throttle (-1 down .. 0 glide .. +1 up), wingbeat freq (Hz), power per stroke (0..1).
function _G.UpdateFlapUI(throttle, freqHz, power)
	throttle = math.clamp(tonumber(throttle) or 0, -1, 1)
	if throttle >= 0 then
		flapFillUp.Size = UDim2.new(0.5 * throttle, 0, 1, 0)
		flapFillDown.Size = UDim2.new(0, 0, 1, 0)
	else
		flapFillDown.Size = UDim2.new(0.5 * (-throttle), 0, 1, 0)
		flapFillUp.Size = UDim2.new(0, 0, 1, 0)
	end
	if math.abs(throttle) < 0.02 then
		flapText.Text = "GLIDE"
	else
		local pct = math.floor((tonumber(power) or 0) * 100 + 0.5)
		local dir = throttle > 0 and "\u{25B2}" or "\u{25BC}" -- ▲ up-thrust / ▼ down-thrust
		flapText.Text = string.format("%s %.1fHz \194\183 %d%%", dir, tonumber(freqHz) or 0, pct)
	end
end

--------------------------------------------------------------------------------
-- EAGLES TO THE RESCUE HUD (S32) — timer, score, carry, style meter, and the big center STAMP.
-- Reads _G.RescueSnapshot() (set by BirdController) each frame; exposes _G.RescueStamp for the beat.
-- When rescue is enabled we hide the combat-specific readouts (team banner, Eagles/Crows score,
-- strike meter, combat control hint) so the HUD reads as a rescue game.
--------------------------------------------------------------------------------
local RESCUE_ON = GameConfig.Rescue and GameConfig.Rescue.enabled
if RESCUE_ON then
	teamBanner.Visible = false
	scoreFrame.Visible = false
	controlHint.Text = "<b><font color=\"#ffd24a\">FLY FAST past a squirrel</font></b> to catch it!   \194\183   Carry them up the <b><font color=\"#8fd8ff\">WATERFALL</font></b> to safety   \194\183   SPACE = look around"

	-- TIMER + PHASE (top center)
	local topFrame = Instance.new("Frame")
	topFrame.Name = "RescueTop"
	topFrame.AnchorPoint = Vector2.new(0.5, 0)
	topFrame.Size = UDim2.new(0, 360, 0, 84)
	topFrame.Position = UDim2.new(0.5, 0, 0, 8)
	topFrame.BackgroundColor3 = UI.hudColor
	topFrame.BackgroundTransparency = UI.hudTransparency
	topFrame.BorderSizePixel = 0
	topFrame.Parent = screenGui
	local tfc = Instance.new("UICorner"); tfc.CornerRadius = UDim.new(0, 12); tfc.Parent = topFrame

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(1, -16, 0, 44); timerLabel.Position = UDim2.new(0, 8, 0, 4)
	timerLabel.BackgroundTransparency = 1; timerLabel.Font = Enum.Font.GothamBlack; timerLabel.TextScaled = true
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255); timerLabel.TextStrokeTransparency = 0.4
	timerLabel.Text = "2:00"; timerLabel.Parent = topFrame

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "Score"
	scoreLabel.Size = UDim2.new(1, -16, 0, 30); scoreLabel.Position = UDim2.new(0, 8, 0, 50)
	scoreLabel.BackgroundTransparency = 1; scoreLabel.Font = Enum.Font.GothamBold; scoreLabel.TextScaled = true
	scoreLabel.TextColor3 = Color3.fromRGB(255, 214, 120); scoreLabel.TextStrokeTransparency = 0.5
	scoreLabel.Text = "🐿️ 0"; scoreLabel.Parent = topFrame

	-- CARRY + STYLE (bottom center, above the control hint)
	-- COMBO banner (Chad S34): consecutive catches build a x N combo — the SHOWN reward for boom-and-zoom
	-- (the speed-widened scoop is the hidden facilitator). Appears at x2, hotter toward x6, pulses.
	local comboLabel = Instance.new("TextLabel")
	comboLabel.Name = "RescueCombo"
	comboLabel.AnchorPoint = Vector2.new(0.5, 0)
	comboLabel.Size = UDim2.new(0, 340, 0, 46)
	comboLabel.Position = UDim2.new(0.5, 0, 0, 98)
	comboLabel.BackgroundTransparency = 1
	comboLabel.Font = Enum.Font.GothamBlack
	comboLabel.TextScaled = true
	comboLabel.TextStrokeTransparency = 0.3
	comboLabel.TextColor3 = Color3.fromRGB(255, 175, 60)
	comboLabel.Text = ""
	comboLabel.Visible = false
	comboLabel.ZIndex = 6
	comboLabel.Parent = screenGui

	local carryFrame = Instance.new("Frame")
	carryFrame.Name = "RescueCarry"
	carryFrame.AnchorPoint = Vector2.new(0.5, 1)
	carryFrame.Size = UDim2.new(0, 320, 0, 56)
	carryFrame.Position = UDim2.new(0.5, 0, 1, -64)
	carryFrame.BackgroundColor3 = UI.hudColor
	carryFrame.BackgroundTransparency = UI.hudTransparency
	carryFrame.BorderSizePixel = 0
	carryFrame.Parent = screenGui
	local cfc = Instance.new("UICorner"); cfc.CornerRadius = UDim.new(0, 10); cfc.Parent = carryFrame

	local carryLabel = Instance.new("TextLabel")
	carryLabel.Name = "Carry"
	carryLabel.Size = UDim2.new(0.5, -8, 1, -8); carryLabel.Position = UDim2.new(0, 8, 0, 4)
	carryLabel.BackgroundTransparency = 1; carryLabel.Font = Enum.Font.GothamBold; carryLabel.TextScaled = true
	carryLabel.TextColor3 = Color3.fromRGB(255, 255, 255); carryLabel.TextXAlignment = Enum.TextXAlignment.Left
	carryLabel.Text = "🐿️ 0/3"; carryLabel.Parent = carryFrame

	local styleLabel = Instance.new("TextLabel")
	styleLabel.Name = "Style"
	styleLabel.Size = UDim2.new(0.5, -8, 0, 22); styleLabel.Position = UDim2.new(0.5, 0, 0, 4)
	styleLabel.BackgroundTransparency = 1; styleLabel.Font = Enum.Font.GothamBold; styleLabel.TextScaled = true
	styleLabel.TextColor3 = Color3.fromRGB(150, 230, 255); styleLabel.TextXAlignment = Enum.TextXAlignment.Right
	styleLabel.Text = ""; styleLabel.Parent = carryFrame

	local styleBg = Instance.new("Frame")
	styleBg.Size = UDim2.new(0.5, -16, 0, 12); styleBg.Position = UDim2.new(0.5, 8, 1, -18)
	styleBg.BackgroundColor3 = Color3.fromRGB(30, 34, 40); styleBg.BorderSizePixel = 0; styleBg.Parent = carryFrame
	local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 4); sbc.Parent = styleBg
	local styleFill = Instance.new("Frame")
	styleFill.Size = UDim2.new(0, 0, 1, 0); styleFill.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
	styleFill.BorderSizePixel = 0; styleFill.Parent = styleBg
	local sfc = Instance.new("UICorner"); sfc.CornerRadius = UDim.new(0, 4); sfc.Parent = styleFill

	-- BIG CENTER STAMP (GOTCHA! / DELIVERED!)
	local stamp = Instance.new("TextLabel")
	stamp.Name = "RescueStamp"
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Size = UDim2.new(0, 640, 0, 120)
	stamp.Position = UDim2.new(0.5, 0, 0.4, 0)
	stamp.BackgroundTransparency = 1
	stamp.Font = Enum.Font.GothamBlack
	stamp.TextScaled = true
	stamp.TextColor3 = Color3.fromRGB(255, 230, 140)
	stamp.TextStrokeTransparency = 0.2
	stamp.TextTransparency = 1
	stamp.Text = ""
	stamp.ZIndex = 20
	stamp.Parent = screenGui

	local substamp = Instance.new("TextLabel")
	substamp.Name = "RescueSubStamp"
	substamp.AnchorPoint = Vector2.new(0.5, 0.5)
	substamp.Size = UDim2.new(0, 520, 0, 48)
	substamp.Position = UDim2.new(0.5, 0, 0.4, 74)
	substamp.BackgroundTransparency = 1
	substamp.Font = Enum.Font.GothamBold
	substamp.TextScaled = true
	substamp.TextColor3 = Color3.fromRGB(150, 230, 255)
	substamp.TextStrokeTransparency = 0.3
	substamp.TextTransparency = 1
	substamp.Text = ""
	substamp.ZIndex = 20
	substamp.Parent = screenGui

	local stampToken = 0
	local RARITY_COLOR = {
		Brown = Color3.fromRGB(255, 230, 140), Silver = Color3.fromRGB(220, 232, 245),
		Gold = Color3.fromRGB(255, 205, 80), Rainbow = Color3.fromRGB(255, 140, 210),
	}
	function _G.RescueStamp(kind, tier, rarity, mult, n, big)
		if kind == "gotcha" then
			big = math.clamp(tonumber(big) or 0, 0, 1)
			stampToken += 1
			local myTok = stampToken
			local prefix = (rarity and rarity ~= "Brown") and (string.upper(rarity) .. " ") or ""
			stamp.Text = prefix .. "GOTCHA!"
			-- Big (BLAZING / high-style) catches land GOLD and BIGGER — escalating spectacle (Fable #5).
			stamp.TextColor3 = (big >= 0.6) and Color3.fromRGB(255, 205, 80)
				or (RARITY_COLOR[rarity] or Color3.fromRGB(255, 230, 140))
			stamp.TextTransparency = 0
			local w0, h0 = 560 + big * 140, 110 + big * 30
			stamp.Size = UDim2.new(0, w0, 0, h0)
			TweenService:Create(stamp, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, w0 + 100 + big * 80, 0, h0 + 18 + big * 20) }):Play()
			TweenService:Create(stamp, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }):Play()
			-- Sub-stamp lands a beat LATER with a strict gap so stamps never pile up (Fable #6): the
			-- speed tier + STYLE (only when it actually popped, >×1.5) share ONE line at +0.4s; the
			-- "…woohoo!" is a sound 0.5s after snap-back (BirdController) so nothing ever triples up.
			local bits = {}
			-- ENERGY (Chad S34): a fast catch traded altitude for speed → the dive MULTIPLIES the rescue.
			-- Show the kid the speed→points link right on the beat (teach energy dynamics).
			if tier and tier ~= "" then
				local em = (tier == "BLAZING") and (GameConfig.Rescue.blazingMult or 2.0)
					or (GameConfig.Rescue.swiftMult or 1.5)
				bits[#bits + 1] = string.format("%s  ⚡×%g ENERGY", tier, em)
			end
			if mult and mult > 1.5 then bits[#bits + 1] = string.format("STYLE ×%.1f", mult) end
			if #bits > 0 then
				task.delay(0.4, function()
					if myTok ~= stampToken then return end
					substamp.Text = table.concat(bits, "   ")
					substamp.TextTransparency = 0
					TweenService:Create(substamp, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ TextTransparency = 1 }):Play()
				end)
			end
		elseif kind == "deliver" then
			stampToken += 1
			stamp.Text = "DELIVERED ×" .. tostring(n or 1) .. "!"
			stamp.TextColor3 = Color3.fromRGB(150, 235, 160)
			stamp.TextTransparency = 0
			stamp.Size = UDim2.new(0, 560, 0, 110)
			TweenService:Create(stamp, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }):Play()
		end
	end

	-- Per-frame rescue HUD update.
	RunService.RenderStepped:Connect(function()
		local snap = _G.RescueSnapshot and _G.RescueSnapshot()
		if type(snap) ~= "table" then return end
		local t = math.max(0, math.floor((snap.timeLeft or 0)))
		timerLabel.Text = string.format("%d:%02d", math.floor(t / 60), t % 60)
		if snap.phase == "active" then
			timerLabel.TextColor3 = (t <= 15) and Color3.fromRGB(255, 120, 110) or Color3.fromRGB(255, 255, 255)
		elseif snap.phase == "intermission" then
			timerLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
		else
			timerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		end
		scoreLabel.Text = "🐿️ " .. tostring(snap.score or 0) .. "   ·   Saved " .. tostring(snap.rescued or 0)
		local cap = snap.capacity or 3
		carryLabel.Text = "🐿️ " .. tostring(snap.carry or 0) .. "/" .. tostring(cap)
		carryLabel.TextColor3 = (snap.carry or 0) >= cap and Color3.fromRGB(255, 180, 90) or Color3.fromRGB(255, 255, 255)
		-- COMBO banner: show the streak from the server snapshot, hotter + pulsing toward ×comboMax.
		local combo = math.floor(tonumber(snap.combo) or 0)
		if combo >= 2 then
			local hot = math.clamp((combo - 2) / 4, 0, 1)
			comboLabel.Text = string.format("🔥 ×%d COMBO", combo)
			comboLabel.TextColor3 = Color3.fromRGB(255, 175, 60):Lerp(Color3.fromRGB(255, 60, 40), hot)
			local pulse = 1 + 0.06 * math.sin(os.clock() * 12)
			comboLabel.Size = UDim2.new(0, 340 * pulse, 0, 46 * pulse)
			comboLabel.Visible = true
		else
			comboLabel.Visible = false
		end
		local styleMult = 1 + (snap.style or 0)
		if styleMult > 1.05 then
			styleLabel.Text = string.format("STYLE ×%.1f", styleMult)
			styleFill.Size = UDim2.new(math.clamp((styleMult - 1) / 2, 0, 1), 0, 1, 0)
		else
			styleLabel.Text = ""
			styleFill.Size = UDim2.new(0, 0, 1, 0)
		end
	end)
end

print("Game UI Loaded!")
