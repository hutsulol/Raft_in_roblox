-- VillagersHUD.client.lua
-- Счётчик валюты «жители» (Villagers) справа вверху экрана. Читает атрибут игрока
-- "Villagers" и обновляется при его изменении (его ставит/меняет сервер —
-- VillagersCurrency.server.lua).

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VillagersHUD"
screenGui.DisplayOrder = 11
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Chip"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -14, 0, 14)
frame.Size = UDim2.fromOffset(168, 40)
frame.BackgroundColor3 = Color3.fromRGB(61, 40, 23)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(176, 138, 92)
stroke.Thickness = 2
stroke.Parent = frame

-- Иконка (эмодзи; при желании замени на ImageLabel со своим ассетом).
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.BackgroundTransparency = 1
icon.Position = UDim2.new(0, 8, 0, 0)
icon.Size = UDim2.new(0, 28, 1, 0)
icon.Text = "\u{1F465}" -- 👥
icon.TextSize = 22
icon.Font = Enum.Font.GothamBold
icon.TextColor3 = Color3.fromRGB(218, 199, 160)
icon.Parent = frame

local label = Instance.new("TextLabel")
label.Name = "Count"
label.BackgroundTransparency = 1
label.Position = UDim2.new(0, 40, 0, 0)
label.Size = UDim2.new(1, -48, 1, 0)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(245, 235, 215)
label.Text = "Жители: 0"
label.Parent = frame

local function refresh()
	label.Text = "Жители: " .. tostring(player:GetAttribute("Villagers") or 0)
end

player:GetAttributeChangedSignal("Villagers"):Connect(refresh)
refresh()
