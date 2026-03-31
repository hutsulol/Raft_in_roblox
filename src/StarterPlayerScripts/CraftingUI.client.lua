local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local craftBush = ReplicatedStorage:WaitForChild("CraftBush")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CraftingGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local craftPanel = Instance.new("Frame")
craftPanel.Name = "CraftPanel"
craftPanel.AnchorPoint = Vector2.new(0, 0.5)
craftPanel.Position = UDim2.new(0, 10, 0.5, 0)
craftPanel.Size = UDim2.new(0, 180, 0, 0)
craftPanel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
craftPanel.BackgroundTransparency = 0.3
craftPanel.BorderSizePixel = 0
craftPanel.Visible = false
craftPanel.AutomaticSize = Enum.AutomaticSize.Y
craftPanel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = craftPanel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.Parent = craftPanel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = craftPanel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 25)
title.BackgroundTransparency = 1
title.Text = "Crafting"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.LayoutOrder = 0
title.Parent = craftPanel

local bushButton = Instance.new("TextButton")
bushButton.Name = "CraftBush"
bushButton.Size = UDim2.new(1, 0, 0, 35)
bushButton.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
bushButton.BorderSizePixel = 0
bushButton.Text = "Bush (1 Plank)"
bushButton.TextColor3 = Color3.new(1, 1, 1)
bushButton.TextSize = 14
bushButton.Font = Enum.Font.GothamBold
bushButton.LayoutOrder = 1
bushButton.Parent = craftPanel

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = bushButton

bushButton.MouseButton1Click:Connect(function()
	craftBush:FireServer()
end)

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "CraftToggle"
toggleButton.AnchorPoint = Vector2.new(0, 0.5)
toggleButton.Position = UDim2.new(0, 10, 0.5, -80)
toggleButton.Size = UDim2.new(0, 40, 0, 40)
toggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleButton.BackgroundTransparency = 0.3
toggleButton.BorderSizePixel = 0
toggleButton.Text = "\u{1F528}"
toggleButton.TextSize = 20
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

toggleButton.MouseButton1Click:Connect(function()
	craftPanel.Visible = not craftPanel.Visible
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.C then
		craftPanel.Visible = not craftPanel.Visible
	end
end)
