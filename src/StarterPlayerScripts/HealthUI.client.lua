local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hide default Roblox health bar
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- ─── Create UI ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HealthUI"
screenGui.DisplayOrder = 15
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Share the inventory's responsive UIScale so this HUD shrinks on
-- phones / narrow screens instead of overflowing next to the hotbar.
task.spawn(function()
	local deadline = os.clock() + 5
	while not _G.AttachInventoryUIScale and os.clock() < deadline do
		task.wait()
	end
	if _G.AttachInventoryUIScale then
		_G.AttachInventoryUIScale(screenGui)
	end
end)

-- Container — bottom bar of the three (thirst, hunger, health)
local container = Instance.new("Frame")
container.Name = "HealthContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 12, 1, -84)
container.Size = UDim2.new(0, 200, 0, 28)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Icon background (brown circle)
local iconBg = Instance.new("Frame")
iconBg.Name = "IconBg"
iconBg.Size = UDim2.new(0, 28, 0, 28)
iconBg.Position = UDim2.new(0, 0, 0, 0)
iconBg.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
iconBg.BorderSizePixel = 0
iconBg.Parent = container

local iconBgCorner = Instance.new("UICorner")
iconBgCorner.CornerRadius = UDim.new(1, 0)
iconBgCorner.Parent = iconBg

local iconBgStroke = Instance.new("UIStroke")
iconBgStroke.Color = Color3.fromRGB(60, 40, 20)
iconBgStroke.Thickness = 1.5
iconBgStroke.Parent = iconBg

-- Icon
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Size = UDim2.new(1, 0, 1, 0)
icon.BackgroundTransparency = 1
icon.Text = "\u{2764}"
icon.TextSize = 16
icon.Font = Enum.Font.GothamBold
icon.TextColor3 = Color3.fromRGB(255, 255, 255)
icon.Parent = iconBg

-- Bar background (tan/wooden)
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, 34, 0.5, 0)
barBg.Size = UDim2.new(0, 160, 0, 20)
barBg.BackgroundColor3 = Color3.fromRGB(160, 130, 85)
barBg.BorderSizePixel = 0
barBg.Parent = container

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(0, 4)
barBgCorner.Parent = barBg

local barBgStroke = Instance.new("UIStroke")
barBgStroke.Color = Color3.fromRGB(90, 60, 30)
barBgStroke.Thickness = 2
barBgStroke.Parent = barBg

-- Bar fill
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(180, 45, 40)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = barFill

-- ─── Update from Humanoid Health ───
local function updateBar(health, maxHealth)
	local ratio = math.clamp(health / maxHealth, 0, 1)

	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	local color
	if ratio > 0.5 then
		color = Color3.fromRGB(180, 45, 40)
	elseif ratio > 0.25 then
		color = Color3.fromRGB(200, 100, 30)
	else
		color = Color3.fromRGB(150, 20, 20)
	end

	TweenService:Create(barFill, TweenInfo.new(0.3), {
		BackgroundColor3 = color
	}):Play()
end

local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")
	updateBar(hum.Health, hum.MaxHealth)

	hum.HealthChanged:Connect(function(newHealth)
		updateBar(newHealth, hum.MaxHealth)
	end)
end

local char = player.Character
if char then
	task.spawn(onCharacterAdded, char)
end
player.CharacterAdded:Connect(function(newChar)
	-- Reset to full on respawn
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(180, 45, 40)
	onCharacterAdded(newChar)
end)
