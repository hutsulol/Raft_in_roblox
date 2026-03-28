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
local raftPartTemplate = ReplicatedStorage:WaitForChild("Raft_part")
local wallTemplate = ReplicatedStorage:FindFirstChild("Wood_wall")

local GRID_SIZE = raftPartTemplate:GetAttribute("GridSize")
if not GRID_SIZE then
	if raftPartTemplate:IsA("Model") and raftPartTemplate.PrimaryPart then
		GRID_SIZE = raftPartTemplate.PrimaryPart.Size.X
	elseif raftPartTemplate:IsA("BasePart") then
		GRID_SIZE = raftPartTemplate.Size.X
	else
		GRID_SIZE = 6
	end
end

local FLOOR_HEIGHT = 0
if raftPartTemplate:IsA("Model") then
	local size = raftPartTemplate:GetExtentsSize()
	FLOOR_HEIGHT = size.Y
elseif raftPartTemplate:IsA("BasePart") then
	FLOOR_HEIGHT = raftPartTemplate.Size.Y
end

local WALL_HEIGHT = 0
if wallTemplate then
	if wallTemplate:IsA("Model") then
		local size = wallTemplate:GetExtentsSize()
		WALL_HEIGHT = size.Y
	elseif wallTemplate:IsA("BasePart") then
		WALL_HEIGHT = wallTemplate.Size.Y
	end
end

local PREVIEW_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local PREVIEW_COLOR_INVALID = Color3.fromRGB(200, 80, 80)

local LOG_ICON = "rbxassetid://110032041583533"
local FLOOR_ICON = "rbxassetid://93002853045949"

-- Building items organized by category
local categories = {
	{
		name = "Floors",
		icon = FLOOR_ICON,
		items = {
			{id = "raft", name = "Raft Floor", icon = FLOOR_ICON, cost = 2, costType = "Log", buildType = "raft"},
		},
	},
	{
		name = "Walls",
		icon = LOG_ICON,
		items = {
			{id = "wall", name = "Wood Wall", icon = LOG_ICON, cost = 3, costType = "Log", buildType = "wall"},
		},
	},
}

local isBuilding = false
local selectedCategory = 1
local selectedItem = nil -- reference to item table
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

local function getFloorOffsets()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local offsets = {}
	table.insert(offsets, {x = 0, z = 0})

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") ~= "wall" then
			table.insert(offsets, {x = gx, z = gz})
		end
	end

	return offsets
end

local function getWallKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function isFloorOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then return true end
	end
	return false
end

local function isFloorAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

local function raycastToRaftPlane()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end

	local primaryCF = raft.PrimaryPart.CFrame
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local planeNormal = primaryCF.UpVector
	local planePoint = primaryCF.Position

	local denom = ray.Direction:Dot(planeNormal)
	if math.abs(denom) < 0.001 then return nil end

	local t = (planePoint - ray.Origin):Dot(planeNormal) / denom
	if t < 0 then return nil end

	local hitWorld = ray.Origin + ray.Direction * t
	local localHit = primaryCF:PointToObjectSpace(hitWorld)
	return localHit
end

local function getFloorGridFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil end

	local raft = getRaft()
	local primaryCF = raft.PrimaryPart.CFrame

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)
	local localOffset = Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE)
	local worldCF = primaryCF * CFrame.new(localOffset)

	return gx, gz, worldCF
end

local function getWallFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil, nil end

	local raft = getRaft()
	local primaryCF = raft.PrimaryPart.CFrame

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	local side
	local half = GRID_SIZE / 2
	local absDx = math.abs(dx)
	local absDz = math.abs(dz)

	if absDx > absDz then
		if dx > 0 then side = 3 else side = 2 end
	else
		if dz > 0 then side = 0 else side = 1 end
	end

	local wallY = FLOOR_HEIGHT / 2
	local _, yaw, _ = primaryCF:ToEulerAnglesYXZ()
	local flatCF = CFrame.new(primaryCF.Position) * CFrame.Angles(0, yaw, 0)

	local localPos, localRot
	if side == 0 then
		localPos = Vector3.new(gx * GRID_SIZE, wallY, gz * GRID_SIZE + half)
		localRot = CFrame.Angles(0, math.rad(180), 0)
	elseif side == 1 then
		localPos = Vector3.new(gx * GRID_SIZE, wallY, gz * GRID_SIZE - half)
		localRot = CFrame.Angles(0, 0, 0)
	elseif side == 2 then
		localPos = Vector3.new(gx * GRID_SIZE - half, wallY, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(-90), 0)
	elseif side == 3 then
		localPos = Vector3.new(gx * GRID_SIZE + half, wallY, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(90), 0)
	end

	local worldCF = flatCF * CFrame.new(localPos) * localRot
	return gx, gz, side, worldCF
end

local function setPreviewAppearance(color)
	if not previewPart then return end
	local function applyToPart(part)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.5
		part.Color = color
	end
	if previewPart:IsA("Model") then
		for _, desc in previewPart:GetDescendants() do
			if desc:IsA("BasePart") then applyToPart(desc) end
		end
	elseif previewPart:IsA("BasePart") then
		applyToPart(previewPart)
	end
end

local function hidePreview()
	if not previewPart then return end
	if previewPart:IsA("Model") then
		for _, desc in previewPart:GetDescendants() do
			if desc:IsA("BasePart") then desc.Transparency = 1 end
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.Transparency = 1
	end
end

local function movePreview(cf)
	if not previewPart then return end
	if previewPart:IsA("Model") then
		previewPart:PivotTo(cf)
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = cf
	end
end

local function getTemplateForItem(item)
	if not item then return raftPartTemplate end
	if item.buildType == "wall" then
		return wallTemplate or raftPartTemplate
	end
	return raftPartTemplate
end

local function createPreview()
	if previewPart then previewPart:Destroy() end
	local template = getTemplateForItem(selectedItem)
	previewPart = template:Clone()
	previewPart.Name = "BuildPreview"
	setPreviewAppearance(PREVIEW_COLOR_VALID)
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

-- ===================== UI =====================

local CAT_SIZE = 50
local CAT_PAD = 4
local ITEM_SIZE = 60
local ITEM_PAD = 6
local PANEL_BG = Color3.fromRGB(139, 109, 63)
local PANEL_DARK = Color3.fromRGB(105, 80, 45)
local PANEL_SELECTED = Color3.fromRGB(170, 135, 75)
local PANEL_ITEM_BG = Color3.fromRGB(160, 128, 68)
local PANEL_ITEM_SEL = Color3.fromRGB(195, 160, 90)

local function buildUI()
	if buildingUI then buildingUI:Destroy() end

	buildingUI = Instance.new("ScreenGui")
	buildingUI.Name = "BuildingGui"
	buildingUI.ResetOnSpawn = false
	buildingUI.DisplayOrder = 20
	buildingUI.Parent = playerGui

	local cat = categories[selectedCategory]

	-- Category tabs (vertical, left side)
	local catCount = #categories
	local catPanelH = catCount * (CAT_SIZE + CAT_PAD) + CAT_PAD
	local catPanel = Instance.new("Frame")
	catPanel.Name = "CategoryPanel"
	catPanel.Size = UDim2.new(0, CAT_SIZE + CAT_PAD * 2, 0, catPanelH)
	catPanel.Position = UDim2.new(0, 10, 0.5, -catPanelH / 2)
	catPanel.BackgroundColor3 = PANEL_BG
	catPanel.BorderSizePixel = 0
	catPanel.Parent = buildingUI

	local catCorner = Instance.new("UICorner")
	catCorner.CornerRadius = UDim.new(0, 8)
	catCorner.Parent = catPanel

	local catStroke = Instance.new("UIStroke")
	catStroke.Color = PANEL_DARK
	catStroke.Thickness = 2
	catStroke.Parent = catPanel

	for i, catData in categories do
		local isActive = (i == selectedCategory)

		local catBtn = Instance.new("TextButton")
		catBtn.Name = "Cat_" .. catData.name
		catBtn.Size = UDim2.new(0, CAT_SIZE, 0, CAT_SIZE)
		catBtn.Position = UDim2.new(0, CAT_PAD, 0, CAT_PAD + (i - 1) * (CAT_SIZE + CAT_PAD))
		catBtn.BackgroundColor3 = isActive and PANEL_SELECTED or PANEL_DARK
		catBtn.BorderSizePixel = 0
		catBtn.Text = ""
		catBtn.AutoButtonColor = false
		catBtn.Parent = catPanel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = catBtn

		if isActive then
			local selStroke = Instance.new("UIStroke")
			selStroke.Color = Color3.fromRGB(255, 220, 100)
			selStroke.Thickness = 2
			selStroke.Parent = catBtn
		end

		-- Category icon
		local catIcon = Instance.new("ImageLabel")
		catIcon.Size = UDim2.new(0.6, 0, 0.6, 0)
		catIcon.Position = UDim2.new(0.2, 0, 0.05, 0)
		catIcon.BackgroundTransparency = 1
		catIcon.Image = catData.icon
		catIcon.Parent = catBtn

		-- Category name
		local catLabel = Instance.new("TextLabel")
		catLabel.Size = UDim2.new(1, 0, 0.35, 0)
		catLabel.Position = UDim2.new(0, 0, 0.65, 0)
		catLabel.BackgroundTransparency = 1
		catLabel.Text = catData.name
		catLabel.TextColor3 = Color3.new(1, 1, 1)
		catLabel.TextScaled = true
		catLabel.Font = Enum.Font.GothamBold
		catLabel.Parent = catBtn

		catBtn.MouseButton1Click:Connect(function()
			if selectedCategory == i then return end
			selectedCategory = i
			-- Default to first item in category
			selectedItem = categories[i].items[1]
			destroyPreview()
			buildUI()
			createPreview()
		end)
	end

	-- Items panel (horizontal, next to category tabs)
	local items = cat.items
	local itemCount = #items
	local itemPanelW = itemCount * (ITEM_SIZE + ITEM_PAD) + ITEM_PAD
	local itemPanelH = ITEM_SIZE + ITEM_PAD * 2 + 20 -- extra for name label

	local itemPanel = Instance.new("Frame")
	itemPanel.Name = "ItemPanel"
	itemPanel.Size = UDim2.new(0, itemPanelW, 0, itemPanelH)
	itemPanel.Position = UDim2.new(0, 10 + CAT_SIZE + CAT_PAD * 2 + 6, 0.5, -itemPanelH / 2)
	itemPanel.BackgroundColor3 = PANEL_BG
	itemPanel.BorderSizePixel = 0
	itemPanel.Parent = buildingUI

	local itemCorner = Instance.new("UICorner")
	itemCorner.CornerRadius = UDim.new(0, 8)
	itemCorner.Parent = itemPanel

	local itemStroke = Instance.new("UIStroke")
	itemStroke.Color = PANEL_DARK
	itemStroke.Thickness = 2
	itemStroke.Parent = itemPanel

	for i, item in items do
		local isActive = (selectedItem and selectedItem.id == item.id)

		local itemBtn = Instance.new("TextButton")
		itemBtn.Name = "Item_" .. item.id
		itemBtn.Size = UDim2.new(0, ITEM_SIZE, 0, ITEM_SIZE)
		itemBtn.Position = UDim2.new(0, ITEM_PAD + (i - 1) * (ITEM_SIZE + ITEM_PAD), 0, ITEM_PAD)
		itemBtn.BackgroundColor3 = isActive and PANEL_ITEM_SEL or PANEL_ITEM_BG
		itemBtn.BorderSizePixel = 0
		itemBtn.Text = ""
		itemBtn.AutoButtonColor = false
		itemBtn.Parent = itemPanel

		local iBtnCorner = Instance.new("UICorner")
		iBtnCorner.CornerRadius = UDim.new(0, 6)
		iBtnCorner.Parent = itemBtn

		if isActive then
			local iSelStroke = Instance.new("UIStroke")
			iSelStroke.Color = Color3.fromRGB(255, 220, 100)
			iSelStroke.Thickness = 2
			iSelStroke.Parent = itemBtn
		end

		-- Item icon
		local itemIcon = Instance.new("ImageLabel")
		itemIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
		itemIcon.Position = UDim2.new(0.15, 0, 0.02, 0)
		itemIcon.BackgroundTransparency = 1
		itemIcon.Image = item.icon
		itemIcon.Parent = itemBtn

		-- Cost label
		local costLbl = Instance.new("TextLabel")
		costLbl.Size = UDim2.new(1, 0, 0.28, 0)
		costLbl.Position = UDim2.new(0, 0, 0.72, 0)
		costLbl.BackgroundTransparency = 1
		costLbl.Text = item.cost .. " " .. item.costType
		costLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
		costLbl.TextScaled = true
		costLbl.Font = Enum.Font.Gotham
		costLbl.Parent = itemBtn

		itemBtn.MouseButton1Click:Connect(function()
			selectedItem = item
			destroyPreview()
			buildUI()
			createPreview()
		end)
	end

	-- Item name label below items
	if selectedItem then
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -ITEM_PAD * 2, 0, 18)
		nameLbl.Position = UDim2.new(0, ITEM_PAD, 1, -20)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = selectedItem.name
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = itemPanel
	end

	-- Hint text
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(0, 250, 0, 18)
	hint.Position = UDim2.new(0, 10, 0.5, catPanelH / 2 + 8)
	hint.BackgroundTransparency = 1
	hint.Text = "Click to place | Unequip Hammer to exit"
	hint.TextColor3 = Color3.fromRGB(200, 200, 200)
	hint.TextScaled = true
	hint.Font = Enum.Font.Gotham
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = buildingUI
end

-- ===================== Build Mode =====================

local function startBuildMode()
	if isBuilding then return end
	isBuilding = true

	-- Default selection
	selectedCategory = 1
	selectedItem = categories[1].items[1]

	buildUI()
	createPreview()

	renderConnection = RunService.RenderStepped:Connect(function()
		if not isBuilding or not previewPart or not selectedItem then return end

		if selectedItem.buildType == "raft" then
			local gx, gz, worldCF = getFloorGridFromMouse()
			if not gx then hidePreview(); return end

			movePreview(worldCF)

			local offsets = getFloorOffsets()
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = not isFloorOccupied(offsets, gx, gz) and isFloorAdjacent(offsets, gx, gz) and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "wall" then
			local gx, gz, side, worldCF = getWallFromMouse()
			if not gx then hidePreview(); return end

			movePreview(worldCF)

			local offsets = getFloorOffsets()
			local hasFloor = isFloorOccupied(offsets, gx, gz)
			local wallKey = gx .. "_" .. gz .. "_" .. side
			local walls = getWallKeys()
			local alreadyPlaced = walls[wallKey]
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = hasFloor and not alreadyPlaced and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)
		end
	end)
end

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
	if not isBuilding or not selectedItem then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	if selectedItem.buildType == "raft" then
		local gx, gz, _ = getFloorGridFromMouse()
		if not gx then return end

		local offsets = getFloorOffsets()
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("raft", gx, gz)

	elseif selectedItem.buildType == "wall" then
		local gx, gz, side, _ = getWallFromMouse()
		if not gx then return end

		local offsets = getFloorOffsets()
		if not isFloorOccupied(offsets, gx, gz) then return end
		local wallKey = gx .. "_" .. gz .. "_" .. side
		local walls = getWallKeys()
		if walls[wallKey] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall", gx, gz, side)
	end
end)

placeBlockEvent.OnClientEvent:Connect(function() end)
