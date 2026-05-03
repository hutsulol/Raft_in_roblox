--[[
	DayCounterUI.client.lua
	Shows current day number at top center of screen.
	Updates from DayCount IntValue in ReplicatedStorage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local dayCount = ReplicatedStorage:WaitForChild("DayCount")

-- ─── UI Setup ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DayCounterUI"
screenGui.DisplayOrder = 10
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Container
local container = Instance.new("Frame")
container.Name = "DayContainer"
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, 12)
container.Size = UDim2.new(0, 160, 0, 40)
container.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
container.BackgroundTransparency = 0.3
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 8)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(90, 60, 30)
containerStroke.Thickness = 2
containerStroke.Parent = container

-- Day label
local dayLabel = Instance.new("TextLabel")
dayLabel.Name = "DayLabel"
dayLabel.AnchorPoint = Vector2.new(0.5, 0.5)
dayLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
dayLabel.Size = UDim2.new(1, -16, 1, -8)
dayLabel.BackgroundTransparency = 1
dayLabel.Text = "Day " .. dayCount.Value
dayLabel.TextColor3 = Color3.fromRGB(220, 190, 130)
dayLabel.TextSize = 20
dayLabel.Font = Enum.Font.GothamBold
dayLabel.Parent = container

-- Update on change
dayCount.Changed:Connect(function(newValue)
	dayLabel.Text = "Day " .. newValue
end)
