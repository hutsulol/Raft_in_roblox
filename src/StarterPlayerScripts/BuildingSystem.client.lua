local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local placeBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlock")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

local RAFT_PART_SIZE = 6
local PREVIEW_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local PREVIEW_COLOR_INVALID = Color3.fromRGB(200, 80, 80)
local LOG_COST = 2

local isBuilding = false
local buildingUI = nil
local previewPart = nil
local inventory = { Log = 0 }
local renderConnection = nil

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
end)

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Get occupied grid offsets in raft-local space
local function getOccupiedOffsets()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local primaryCF = raft.PrimaryPart.CFrame
	local offsets = {}

	-- Main raft at (0,0)
	table.insert(offsets, {x = 0, z = 0})

	for _, child in raft:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("RaftPart") then
			local localPos = primaryCF:PointToObjectSpace(child.Position)
			local gx = math.round(localPos.X / RAFT_PART_SIZE)
			local gz = math.round(localPos.Z / RAFT_PART_SIZE)
			table.insert(offsets, {x = gx, z = gz})
		end
	end

	return offsets
end

local function isOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then
			return true
		end
	end
	return false
end

local function isAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

-- Convert mouse screen position to raft-local grid coordinates
local function getGridFromMouse()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil, nil, nil end

	local primaryCF = raft.PrimaryPart.CFrame

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Intersect with raft's local XZ plane (world plane at raft height, matching raft orientation)
	-- The raft's up vector defines the plane normal
	local planeNormal = primaryCF.UpVector
	local planePoint = primaryCF.Position

	local denom = ray.Direction:Dot(planeNormal)
	if math.abs(denom) < 0.001 then return nil, nil, nil end

	local t = (planePoint - ray.Origin):Dot(planeNormal) / denom
	if t < 0 then return nil, nil, nil end

	local hitWorld = ray.Origin + ray.Direction * t

	-- Convert to raft-local space
	local localHit = primaryCF:PointToObjectSpace(hitWorld)

	-- Snap to grid in local space
	local gx = math.round(localHit.X / RAFT_PART_SIZE)
	local gz = math.round(localHit.Z / RAFT_PART_SIZE)

	-- Convert back to world CFrame for preview
	local localOffset = Vector3.new(gx * RAFT_PART_SIZE, 0, gz * RAFT_PART_SIZE)
	local worldCF = primaryCF * CFrame.new(localOffset)

	return gx, gz, worldCF
end

local function createPreview()
	if previewPart then previewPart:Destroy() end

	previewPart = Instance.new("Part")
	previewPart.Name = "BuildPreview"
	previewPart.Size = Vector3.new(RAFT_PART_SIZE, 1, RAFT_PART_SIZE)
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.Material = Enum.Material.Wood
	previewPart.Transparency = 0.5
	previewPart.Color = PREVIEW_COLOR_VALID
	previewPart.Parent = workspace
end

local function destroyPreview()
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end
end

local function closeBuildMode()
	isBuilding = false
	destroyPreview()
	if buildingUI then
		buildingUI:Destroy()
		buildingUI = nil
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function buildUI()
	if buildingUI then buildingUI:Destroy() end

	buildingUI = Instance.new("ScreenGui")
	buildingUI.Name = "BuildingGui"
	buildingUI.ResetOnSpawn = false
	buildingUI.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.Size = UDim2.new(0, 200, 0, 80)
	panel.Position = UDim2.new(0.5, -100, 1, -100)
	panel.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	panel.BorderSizePixel = 0
	panel.Parent = buildingUI

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(80, 80, 90)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 25)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.BackgroundTransparency = 1
	title.Text = "Building"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = panel

	local btn = Instance.new("Frame")
	btn.Name = "RaftPartBtn"
	btn.Size = UDim2.new(0, 60, 0, 40)
	btn.Position = UDim2.new(0.5, -30, 0, 33)
	btn.BackgroundColor3 = Color3.fromRGB(101, 67, 33)
	btn.BorderSizePixel = 0
	btn.Parent = panel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	local btnLabel = Instance.new("TextLabel")
	btnLabel.Size = UDim2.new(1, 0, 0.5, 0)
	btnLabel.Position = UDim2.new(0, 0, 0, 0)
	btnLabel.BackgroundTransparency = 1
	btnLabel.Text = "Raft"
	btnLabel.TextColor3 = Color3.new(1, 1, 1)
	btnLabel.TextScaled = true
	btnLabel.Font = Enum.Font.GothamBold
	btnLabel.Parent = btn

	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(1, 0, 0.4, 0)
	costLabel.Position = UDim2.new(0, 0, 0.55, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = LOG_COST .. " Log"
	costLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	costLabel.TextScaled = true
	costLabel.Font = Enum.Font.Gotham
	costLabel.Parent = btn

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(0, 300, 0, 20)
	hint.Position = UDim2.new(0.5, -150, 1, -30)
	hint.BackgroundTransparency = 1
	hint.Text = "Click to place | Unequip Hammer to exit"
	hint.TextColor3 = Color3.fromRGB(180, 180, 180)
	hint.TextScaled = true
	hint.Font = Enum.Font.Gotham
	hint.Parent = buildingUI
end

local function startBuildMode()
	if isBuilding then return end
	isBuilding = true

	buildUI()
	createPreview()

	renderConnection = RunService.RenderStepped:Connect(function()
		if not isBuilding or not previewPart then return end

		local gx, gz, worldCF = getGridFromMouse()
		if not gx then
			previewPart.Transparency = 1
			return
		end

		previewPart.CFrame = worldCF
		previewPart.Transparency = 0.5

		local offsets = getOccupiedOffsets()
		local canAfford = (inventory.Log or 0) >= LOG_COST
		local valid = not isOccupied(offsets, gx, gz) and isAdjacent(offsets, gx, gz) and canAfford
		previewPart.Color = valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID
	end)
end

-- Detect Hammer equip/unequip
local function onCharacterAdded(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Hammer" then
			startBuildMode()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Hammer" then
			closeBuildMode()
		end
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child.Name == "Hammer" then
			startBuildMode()
			break
		end
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Click to place
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not isBuilding then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local gx, gz, _ = getGridFromMouse()
	if not gx then return end

	local offsets = getOccupiedOffsets()
	if isOccupied(offsets, gx, gz) then return end
	if not isAdjacent(offsets, gx, gz) then return end
	if (inventory.Log or 0) < LOG_COST then return end

	-- Send grid coordinates (not world position)
	placeBlockEvent:FireServer(gx, gz)
end)

placeBlockEvent.OnClientEvent:Connect(function() end)
