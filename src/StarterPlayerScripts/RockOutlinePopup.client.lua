-- RockOutlinePopup.client.lua
-- Yellow outline only (no fill) on rocks + floating "+X stone" popup

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local mineRockEvent = ReplicatedStorage:WaitForChild("MineRock")

local STONE_ICON = "rbxassetid://134781813180973"
local ISLAND_NAMES = { Island_1 = true, Island_2 = true }

local currentHighlight = nil
local pickAxeEquipped = false
local lastRockPosition = nil

local function findMineableRock(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") and instance:GetAttribute("Mineable") then
		local current = instance.Parent
		while current and current ~= workspace do
			if current:IsA("Model") and ISLAND_NAMES[current.Name] then
				return instance
			end
			current = current.Parent
		end
	end
	return nil
end

local function killSelectionBoxes()
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("SelectionBox") then
			gui:Destroy()
		end
	end
end

local function highlightRock(rock)
	if currentHighlight and currentHighlight.Parent == rock then return end
	clearRockHighlight()

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1 -- no fill at all
	hl.OutlineColor = Color3.fromRGB(255, 200, 50) -- yellow outline
	hl.OutlineTransparency = 0
	hl.Parent = rock
	currentHighlight = hl
end

function clearRockHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
end

local function showStonePopup(worldPos, amount)
	local screenPos, onScreen = camera:WorldToScreenPoint(worldPos)
	if not onScreen then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 120, 0, 50)
	container.Position = UDim2.new(0, screenPos.X - 60, 0, screenPos.Y - 25)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 50, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ " .. tostring(amount)
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = container

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.Position = UDim2.new(0, 55, 0.5, -20)
	icon.BackgroundTransparency = 1
	icon.Image = STONE_ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = container

	local startY = screenPos.Y - 25
	TweenService:Create(container, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, screenPos.X - 60, 0, startY - 50),
	}):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	task.delay(1.2, function() screenGui:Destroy() end)
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pick-Axe" then pickAxeEquipped = true end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			pickAxeEquipped = false
			clearRockHighlight()
		end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Pick-Axe" then
			pickAxeEquipped = true
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if not pickAxeEquipped then return end
	killSelectionBoxes()

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if result and result.Instance then
		local rock = findMineableRock(result.Instance)
		if rock then
			highlightRock(rock)
			lastRockPosition = rock.Position
			return
		end
	end
	clearRockHighlight()
end)

mineRockEvent.OnClientEvent:Connect(function(action, value)
	if action == "destroyed" and lastRockPosition then
		showStonePopup(lastRockPosition, value)
		clearRockHighlight()
		lastRockPosition = nil
	end
end)
