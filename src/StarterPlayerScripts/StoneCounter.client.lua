-- StoneCounter.client.lua
-- Displays Stone count in the inventory hotbar area

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STONE_ICON = "rbxassetid://134781813180973"

local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

-- ─── Build Stone counter UI ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StoneCounterGui"
screenGui.DisplayOrder = 8
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Position above the hotbar, to the right of existing resource slots
local container = Instance.new("Frame")
container.Name = "StoneContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 10, 1, -80)
container.Size = UDim2.new(0, 130, 0, 36)
container.BackgroundColor3 = Color3.fromRGB(139, 109, 63)
container.BackgroundTransparency = 0.2
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(100, 75, 40)
stroke.Thickness = 2
stroke.Parent = container

local icon = Instance.new("ImageLabel")
icon.Name = "StoneIcon"
icon.Size = UDim2.new(0, 28, 0, 28)
icon.Position = UDim2.new(0, 6, 0.5, -14)
icon.BackgroundTransparency = 1
icon.Image = STONE_ICON
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = container

local label = Instance.new("TextLabel")
label.Name = "StoneCount"
label.Size = UDim2.new(1, -40, 1, 0)
label.Position = UDim2.new(0, 38, 0, 0)
label.BackgroundTransparency = 1
label.Text = "Stone: 0"
label.TextColor3 = Color3.fromRGB(255, 245, 220)
label.TextSize = 16
label.Font = Enum.Font.GothamBold
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = container

-- ─── Update on inventory changes ───
inventoryEvent.OnClientEvent:Connect(function(inv)
	if inv and inv.Stone then
		label.Text = "Stone: " .. tostring(inv.Stone)
	end
end)
