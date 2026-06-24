--!nonstrict
--[[
	GameUI — Polished HUD for Eagles vs Crows (LocalScript in StarterGui)

	Builds the entire HUD in code (no Studio assets) using GameConfig.UI for all
	colors/fonts/transparency. Runs safely before TeamAssigned fires.

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
flightDataFrame.Size = UDim2.new(0, 150, 0, 65)
flightDataFrame.Position = UDim2.new(0, 15, 1, -160)
flightDataFrame.BackgroundColor3 = UI.hudColor
flightDataFrame.BackgroundTransparency = UI.hudTransparency
flightDataFrame.BorderSizePixel = 0
flightDataFrame.Parent = screenGui

local dataCorner = Instance.new("UICorner")
dataCorner.CornerRadius = UDim.new(0, 8)
dataCorner.Parent = flightDataFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(1, -16, 0.5, -4)
speedLabel.Position = UDim2.new(0, 8, 0, 4)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "SPD: 0"
speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Font = UI.fontMedium
speedLabel.TextScaled = true
speedLabel.Parent = flightDataFrame

local altLabel = Instance.new("TextLabel")
altLabel.Name = "AltLabel"
altLabel.Size = UDim2.new(1, -16, 0.5, -4)
altLabel.Position = UDim2.new(0, 8, 0.5, 0)
altLabel.BackgroundTransparency = 1
altLabel.Text = "ALT: 0"
altLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
altLabel.TextXAlignment = Enum.TextXAlignment.Left
altLabel.Font = UI.fontMedium
altLabel.TextScaled = true
altLabel.Parent = flightDataFrame

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
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	-- Blink the stall warning while visible.
	if stallWarning.Visible then
		stallWarning.TextTransparency = math.abs(math.sin(tick() * 8)) * 0.6
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local primary = character.PrimaryPart

	-- Health: prefer PrimaryPart "Health" Attribute, else Humanoid.Health.
	local hpRatio
	if primary then
		local hpAttr = primary:GetAttribute("Health")
		if typeof(hpAttr) == "number" then
			-- Derive a max from a MaxHealth attribute if present, else assume 0..100.
			local maxAttr = primary:GetAttribute("MaxHealth")
			local maxHp = (typeof(maxAttr) == "number" and maxAttr > 0) and maxAttr or 100
			hpRatio = hpAttr / maxHp
		end
	end
	if hpRatio == nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MaxHealth > 0 then
			hpRatio = humanoid.Health / humanoid.MaxHealth
		end
	end
	if hpRatio ~= nil then
		healthBarFill.Size = UDim2.new(math.clamp(hpRatio, 0, 1), 0, 1, 0)
	end

	-- Flight data from HumanoidRootPart.
	if root then
		local speed = root.AssemblyLinearVelocity.Magnitude
		speedLabel.Text = "SPD: " .. tostring(math.floor(speed + 0.5))
		altLabel.Text = "ALT: " .. tostring(math.floor(root.Position.Y + 0.5))
	end
end)

--------------------------------------------------------------------------------
-- EXPOSED HOOKS (called by BirdController)
--------------------------------------------------------------------------------
-- Set the stamina fill, ratio 0..1.
function _G.UpdateStaminaUI(ratio)
	ratio = tonumber(ratio) or 0
	staminaBarFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
end

-- Toggle the blinking stall warning.
function _G.SetStallWarning(isStalling)
	stallWarning.Visible = isStalling and true or false
	if not isStalling then
		stallWarning.TextTransparency = 0
	end
end

print("Game UI Loaded!")
