local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local thirstEvent = ReplicatedStorage:WaitForChild("ThirstUpdate")

-- ─── Create UI ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ThirstUI"
screenGui.DisplayOrder = 15
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Container in bottom-left
local container = Instance.new("Frame")
container.Name = "ThirstContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 20, 1, -80)
container.Size = UDim2.new(0, 160, 0, 40)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Icon (water droplet)
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Size = UDim2.new(0, 30, 0, 30)
icon.Position = UDim2.new(0, 0, 0.5, 0)
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.BackgroundTransparency = 1
icon.Text = "\u{1F4A7}"
icon.TextSize = 22
icon.Font = Enum.Font.GothamBold
icon.TextColor3 = Color3.fromRGB(80, 180, 255)
icon.Parent = container

-- Bar background
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, 35, 0.5, 0)
barBg.Size = UDim2.new(0, 120, 0, 16)
barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
barBg.BorderSizePixel = 0
barBg.Parent = container

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(0, 6)
barBgCorner.Parent = barBg

local barBgStroke = Instance.new("UIStroke")
barBgStroke.Color = Color3.fromRGB(80, 80, 100)
barBgStroke.Thickness = 1.5
barBgStroke.Parent = barBg

-- Bar fill
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(60, 160, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = barFill

-- ─── Update Handler ───
local currentThirst = 100
local maxThirst = 100

local function updateBar(thirst, max)
	currentThirst = thirst
	maxThirst = max

	local ratio = math.clamp(thirst / max, 0, 1)

	-- Tween the fill bar
	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	-- Color: blue when full → red when empty
	local color
	if ratio > 0.5 then
		color = Color3.fromRGB(60, 160, 255)
	elseif ratio > 0.25 then
		color = Color3.fromRGB(255, 180, 50)
	else
		color = Color3.fromRGB(220, 50, 50)
	end

	TweenService:Create(barFill, TweenInfo.new(0.3), {
		BackgroundColor3 = color
	}):Play()
end

thirstEvent.OnClientEvent:Connect(function(thirst, max)
	updateBar(thirst, max)
end)
