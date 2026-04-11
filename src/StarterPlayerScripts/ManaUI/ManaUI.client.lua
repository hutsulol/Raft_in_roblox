-- ManaUI.client.lua
-- Mana bar HUD — lives in the TOP slot of the bottom-left HUD stack
-- (the position previously occupied by the standalone ThirstUI, which
-- has been folded into HungerUI as a half-width right-side bar). Style
-- matches HealthUI / HungerUI: a 28px brown circular icon badge on the
-- left with a 160×20 tan wooden bar to its right.
--
-- Driven by the replicated Characteristics.ManaCurrent / ManaMax
-- IntValues written by Characteristics.server.lua. The numeric label
-- sits on top of the filled portion and its X anchor is tweened in
-- parallel with the fill size so it always hovers over the center of
-- the filled region and slides smoothly as mana changes.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MANA_ICON_ASSET = "rbxassetid://131647230431306"

local COLOR_ICON_BG     = Color3.fromRGB(90, 60, 30)
local COLOR_ICON_STROKE = Color3.fromRGB(60, 40, 20)
local COLOR_BAR_BG      = Color3.fromRGB(160, 130, 85)
local COLOR_BAR_STROKE  = Color3.fromRGB(90, 60, 30)
local COLOR_FILL        = Color3.fromRGB(80, 160, 255)
local COLOR_TEXT        = Color3.fromRGB(255, 255, 255)

local TWEEN_TIME = 0.25

-- ─── Create UI ──────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ManaUI"
screenGui.DisplayOrder = 15
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Container — top slot of the left HUD stack (mana / hunger+water / health).
local container = Instance.new("Frame")
container.Name = "ManaContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 12, 1, -152)
container.Size = UDim2.new(0, 200, 0, 28)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- ─── Icon badge ─────────────────────────────────────────────────────────
local iconBg = Instance.new("Frame")
iconBg.Name = "IconBg"
iconBg.Size = UDim2.new(0, 28, 0, 28)
iconBg.Position = UDim2.new(0, 0, 0, 0)
iconBg.BackgroundColor3 = COLOR_ICON_BG
iconBg.BorderSizePixel = 0
iconBg.Parent = container

local iconBgCorner = Instance.new("UICorner")
iconBgCorner.CornerRadius = UDim.new(1, 0)
iconBgCorner.Parent = iconBg

local iconBgStroke = Instance.new("UIStroke")
iconBgStroke.Color = COLOR_ICON_STROKE
iconBgStroke.Thickness = 1.5
iconBgStroke.Parent = iconBg

local iconImage = Instance.new("ImageLabel")
iconImage.Name = "Icon"
iconImage.BackgroundTransparency = 1
iconImage.Image = MANA_ICON_ASSET
iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
iconImage.Position = UDim2.fromScale(0.5, 0.5)
iconImage.Size = UDim2.fromOffset(22, 22)
iconImage.Parent = iconBg

-- ─── Bar background + fill ──────────────────────────────────────────────
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, 34, 0.5, 0)
barBg.Size = UDim2.new(0, 160, 0, 20)
barBg.BackgroundColor3 = COLOR_BAR_BG
barBg.BorderSizePixel = 0
-- Don't clip: we want the text to stay readable even when the fill is
-- narrow and the centered label would otherwise extend past the left
-- edge of the bar's interior.
barBg.ClipsDescendants = false
barBg.Parent = container

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(0, 4)
barBgCorner.Parent = barBg

local barBgStroke = Instance.new("UIStroke")
barBgStroke.Color = COLOR_BAR_STROKE
barBgStroke.Thickness = 2
barBgStroke.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = COLOR_FILL
barFill.BorderSizePixel = 0
barFill.ZIndex = 1
barFill.Parent = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = barFill

-- Numeric label — parented to the bar bg (not the fill) so its X
-- position is tweened independently to sit over the center of the
-- currently filled portion.
local manaText = Instance.new("TextLabel")
manaText.Name = "ManaText"
manaText.BackgroundTransparency = 1
manaText.Font = Enum.Font.GothamBold
manaText.TextSize = 13
manaText.TextColor3 = COLOR_TEXT
manaText.TextStrokeTransparency = 0.25
manaText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
manaText.AnchorPoint = Vector2.new(0.5, 0.5)
manaText.Position = UDim2.fromScale(0.5, 0.5)
manaText.Size = UDim2.fromOffset(60, 16)
manaText.Text = "0"
manaText.ZIndex = 2
manaText.Parent = barBg

-- ─── Update logic ───────────────────────────────────────────────────────
local function updateManaDisplay(current, max, animate)
	local ratio = 0
	if max > 0 then
		ratio = math.clamp(current / max, 0, 1)
	end
	local fillGoal = UDim2.fromScale(ratio, 1)
	local textGoal = UDim2.fromScale(ratio / 2, 0.5)

	manaText.Text = tostring(current)

	if animate then
		local info = TweenInfo.new(
			TWEEN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
		TweenService:Create(barFill, info, { Size = fillGoal }):Play()
		TweenService:Create(manaText, info, { Position = textGoal }):Play()
	else
		barFill.Size = fillGoal
		manaText.Position = textGoal
	end
end

-- Subscribe to the replicated Characteristics mana values. First call
-- paints the bar instantly (no tween); subsequent changes animate.
task.spawn(function()
	local folder  = player:WaitForChild("Characteristics")
	local current = folder:WaitForChild("ManaCurrent")
	local max     = folder:WaitForChild("ManaMax")

	updateManaDisplay(current.Value, max.Value, false)

	local function refresh()
		updateManaDisplay(current.Value, max.Value, true)
	end
	current:GetPropertyChangedSignal("Value"):Connect(refresh)
	max:GetPropertyChangedSignal("Value"):Connect(refresh)
end)
