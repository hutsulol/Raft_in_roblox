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
local wallTemplate = ReplicatedStorage:FindFirstChild("Wood Wall")

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
local RAFT_COST = 2
local WALL_COST = 3

local isBuilding = false
local selectedType = "raft" -- "raft" or "wall"
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

-- For raft floor placement
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

-- For wall placement: find nearest edge of a floor tile
-- side: 0=front(+Z), 1=back(-Z), 2=left(-X), 3=right(+X)
local function getWallFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil, nil end

	local raft = getRaft()
	local primaryCF = raft.PrimaryPart.CFrame

	-- Find grid cell
	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	-- Local position within the cell (relative to cell center)
	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	-- Determine closest edge
	local side
	local half = GRID_SIZE / 2
	local absDx = math.abs(dx)
	local absDz = math.abs(dz)

	if absDx > absDz then
		-- Closer to left or right edge
		if dx > 0 then side = 3 else side = 2 end
	else
		-- Closer to front or back edge
		if dz > 0 then side = 0 else side = 1 end
	end

	-- Compute wall world CFrame
	local localPos, localRot
	if side == 0 then
		localPos = Vector3.new(gx * GRID_SIZE, WALL_HEIGHT / 2, gz * GRID_SIZE + half)
		localRot = CFrame.Angles(0, 0, 0)
	elseif side == 1 then
		localPos = Vector3.new(gx * GRID_SIZE, WALL_HEIGHT / 2, gz * GRID_SIZE - half)
		localRot = CFrame.Angles(0, math.rad(180), 0)
	elseif side == 2 then
		localPos = Vector3.new(gx * GRID_SIZE - half, WALL_HEIGHT / 2, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(90), 0)
	elseif side == 3 then
		localPos = Vector3.new(gx * GRID_SIZE + half, WALL_HEIGHT / 2, gz * GRID_SIZE)
		localRot = CFrame.Angles(0, math.rad(-90), 0)
	end

	local worldCF = primaryCF * CFrame.new(localPos) * localRot

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

local function createPreview()
	if previewPart then previewPart:Destroy() end

	local template = (selectedType == "wall" and wallTemplate) and wallTemplate or raftPartTemplate
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

local function buildUI()
	if buildingUI then buildingUI:Destroy() end

	buildingUI = Instance.new("ScreenGui")
	buildingUI.Name = "BuildingGui"
	buildingUI.ResetOnSpawn = false
	buildingUI.DisplayOrder = 20
	buildingUI.Parent = playerGui

	-- Panel - moved higher above hotbar
	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.Size = UDim2.new(0, 260, 0, 90)
	panel.Position = UDim2.new(0.5, -130, 1, -200)
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
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Position = UDim2.new(0, 0, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = "Building"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = panel

	-- Helper to create a build option button
	local function createBuildBtn(name, label, cost, xOffset, isSelected)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0, 70, 0, 50)
		btn.Position = UDim2.new(0.5, xOffset, 0, 30)
		btn.BackgroundColor3 = isSelected and Color3.fromRGB(140, 90, 40) or Color3.fromRGB(80, 55, 30)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = panel

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		if isSelected then
			local selStroke = Instance.new("UIStroke")
			selStroke.Color = Color3.fromRGB(255, 220, 100)
			selStroke.Thickness = 2
			selStroke.Parent = btn
		end

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0.5, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = label
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = btn

		local costLbl = Instance.new("TextLabel")
		costLbl.Size = UDim2.new(1, 0, 0.4, 0)
		costLbl.Position = UDim2.new(0, 0, 0.55, 0)
		costLbl.BackgroundTransparency = 1
		costLbl.Text = cost .. " Log"
		costLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
		costLbl.TextScaled = true
		costLbl.Font = Enum.Font.Gotham
		costLbl.Parent = btn

		return btn
	end

	local raftBtn = createBuildBtn("RaftBtn", "Raft", RAFT_COST, -80, selectedType == "raft")
	local wallBtn = createBuildBtn("WallBtn", "Wall", WALL_COST, 5, selectedType == "wall")

	local function selectType(newType)
		if selectedType == newType then return end
		selectedType = newType
		-- Rebuild UI first to update highlight, then recreate preview
		buildUI()
		destroyPreview()
		createPreview()
	end

	raftBtn.MouseButton1Click:Connect(function() selectType("raft") end)
	wallBtn.MouseButton1Click:Connect(function() selectType("wall") end)

	-- Hint text
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(0, 300, 0, 18)
	hint.Position = UDim2.new(0.5, -150, 1, -115)
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

		if selectedType == "raft" then
			local gx, gz, worldCF = getFloorGridFromMouse()
			if not gx then hidePreview(); return end

			movePreview(worldCF)

			local offsets = getFloorOffsets()
			local canAfford = (inventory.Log or 0) >= RAFT_COST
			local valid = not isFloorOccupied(offsets, gx, gz) and isFloorAdjacent(offsets, gx, gz) and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedType == "wall" then
			local gx, gz, side, worldCF = getWallFromMouse()
			if not gx then hidePreview(); return end

			movePreview(worldCF)

			local offsets = getFloorOffsets()
			local hasFloor = isFloorOccupied(offsets, gx, gz)
			local wallKey = gx .. "_" .. gz .. "_" .. side
			local walls = getWallKeys()
			local alreadyPlaced = walls[wallKey]
			local canAfford = (inventory.Log or 0) >= WALL_COST
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
	if not isBuilding then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	if selectedType == "raft" then
		local gx, gz, _ = getFloorGridFromMouse()
		if not gx then return end

		local offsets = getFloorOffsets()
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end
		if (inventory.Log or 0) < RAFT_COST then return end

		placeBlockEvent:FireServer("raft", gx, gz)

	elseif selectedType == "wall" then
		local gx, gz, side, _ = getWallFromMouse()
		if not gx then return end

		local offsets = getFloorOffsets()
		if not isFloorOccupied(offsets, gx, gz) then return end
		local wallKey = gx .. "_" .. gz .. "_" .. side
		local walls = getWallKeys()
		if walls[wallKey] then return end
		if (inventory.Log or 0) < WALL_COST then return end

		placeBlockEvent:FireServer("wall", gx, gz, side)
	end
end)

placeBlockEvent.OnClientEvent:Connect(function() end)
