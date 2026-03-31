local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local updateHunger = ReplicatedStorage:WaitForChild("UpdateHunger")
local updateThirst = ReplicatedStorage:WaitForChild("UpdateThirst")

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalBarsGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "BarsContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -20)
container.Size = UDim2.new(0, 260, 0, 50)
container.BackgroundTransparency = 1
container.Parent = screenGui

local function createBar(name, order, barColor, iconText)
	local barFrame = Instance.new("Frame")
	barFrame.Name = name
	barFrame.Size = UDim2.new(1, 0, 0, 20)
	barFrame.Position = UDim2.new(0, 0, 0, order * 25)
	barFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barFrame.BorderSizePixel = 0
	barFrame.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = barFrame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 30, 1, 0)
	icon.Position = UDim2.new(0, 5, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = iconText
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.TextSize = 14
	icon.Font = Enum.Font.GothamBold
	icon.TextXAlignment = Enum.TextXAlignment.Left
	icon.ZIndex = 3
	icon.Parent = barFrame

	local label = Instance.new("TextLabel")
	label.Name = "ValueLabel"
	label.Size = UDim2.new(1, -10, 1, 0)
	label.Position = UDim2.new(0, 5, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "100%"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextSize = 13
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.ZIndex = 3
	label.Parent = barFrame

	return fill, label
end

local hungerFill, hungerLabel = createBar("HungerBar", 0, Color3.fromRGB(210, 140, 50), "\u{1F357}")
local thirstFill, thirstLabel = createBar("ThirstBar", 1, Color3.fromRGB(50, 150, 220), "\u{1F4A7}")

local function updateBar(fill, label, current, max)
	local ratio = math.clamp(current / max, 0, 1)
	local percent = math.floor(ratio * 100)

	TweenService:Create(fill, TWEEN_INFO, {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()

	label.Text = percent .. "%"

	if ratio <= 0.2 then
		fill.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	elseif ratio <= 0.4 then
		fill.BackgroundColor3 = Color3.fromRGB(220, 160, 50)
	end
end

updateHunger.OnClientEvent:Connect(function(current, max)
	hungerFill.BackgroundColor3 = Color3.fromRGB(210, 140, 50)
	updateBar(hungerFill, hungerLabel, current, max)
end)

updateThirst.OnClientEvent:Connect(function(current, max)
	thirstFill.BackgroundColor3 = Color3.fromRGB(50, 150, 220)
	updateBar(thirstFill, thirstLabel, current, max)
end)
