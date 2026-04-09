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
local beamTemplate = ReplicatedStorage:FindFirstChild("beam")
local wallPanelTemplate = ReplicatedStorage:FindFirstChild("wall_model_wood")
local wallArchTemplate = ReplicatedStorage:FindFirstChild("wall_model_wood_arch")
local doorTemplate = ReplicatedStorage:FindFirstChild("Door_Wood")

local GRID_SIZE = raftPartTemplate:GetAttribute("GridSize")
if not GRID_SIZE then
	if raftPartTemplate:IsA("Model") then
		local size = raftPartTemplate:GetExtentsSize()
		GRID_SIZE = math.max(size.X, size.Z)
	elseif raftPartTemplate:IsA("BasePart") then
		GRID_SIZE = math.max(raftPartTemplate.Size.X, raftPartTemplate.Size.Z)
	else
		GRID_SIZE = 6
	end
end

local BEAM_HEIGHT = raftPartTemplate:GetAttribute("BeamHeight") or 0
local BEAM_INSET = raftPartTemplate:GetAttribute("BeamInset") or 0
local PANEL_HEIGHT = raftPartTemplate:GetAttribute("PanelHeight") or 0
local ARCH_HEIGHT = raftPartTemplate:GetAttribute("ArchHeight") or 0
local DOOR_HEIGHT = raftPartTemplate:GetAttribute("DoorHeight") or 0

-- Fallback measurements if attributes not set yet
if BEAM_HEIGHT == 0 and beamTemplate then
	if beamTemplate:IsA("Model") then
		local size = beamTemplate:GetExtentsSize()
		BEAM_HEIGHT = size.Y
		BEAM_INSET = math.max(size.X, size.Z) / 2
	elseif beamTemplate:IsA("BasePart") then
		BEAM_HEIGHT = beamTemplate.Size.Y
		BEAM_INSET = math.max(beamTemplate.Size.X, beamTemplate.Size.Z) / 2
	end
end
if PANEL_HEIGHT == 0 and wallPanelTemplate then
	if wallPanelTemplate:IsA("Model") then
		PANEL_HEIGHT = wallPanelTemplate:GetExtentsSize().Y
	elseif wallPanelTemplate:IsA("BasePart") then
		PANEL_HEIGHT = wallPanelTemplate.Size.Y
	end
end
if ARCH_HEIGHT == 0 and wallArchTemplate then
	if wallArchTemplate:IsA("Model") then
		ARCH_HEIGHT = wallArchTemplate:GetExtentsSize().Y
	elseif wallArchTemplate:IsA("BasePart") then
		ARCH_HEIGHT = wallArchTemplate.Size.Y
	end
end
if DOOR_HEIGHT == 0 and doorTemplate then
	if doorTemplate:IsA("Model") then
		DOOR_HEIGHT = doorTemplate:GetExtentsSize().Y
	elseif doorTemplate:IsA("BasePart") then
		DOOR_HEIGHT = doorTemplate.Size.Y
	end
end

local PREVIEW_COLOR_VALID = Color3.fromRGB(80, 200, 80)
local PREVIEW_COLOR_INVALID = Color3.fromRGB(200, 80, 80)

local LOG_ICON = "rbxassetid://110032041583533"
local FLOOR_ICON = "rbxassetid://93002853045949"

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

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
			{id = "beam", name = "Beam", icon = LOG_ICON, cost = 1, costType = "Log", buildType = "beam"},
			{id = "wall_panel", name = "Wood Wall", icon = LOG_ICON, cost = 3, costType = "Log", buildType = "wall_panel"},
			{id = "wall_arch", name = "Door Arch", icon = LOG_ICON, cost = 3, costType = "Log", buildType = "wall_arch"},
			{id = "door", name = "Wood Door", icon = LOG_ICON, cost = 2, costType = "Log", buildType = "door"},
		},
	},
}

local isBuilding = false
local selectedCategory = 1
local selectedItem = nil
local buildingUI = nil
local previewPart = nil
local inventory = { Log = 0 }
local renderConnection = nil
local hammerWatchConnection = nil

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
		if gx and gz and child:GetAttribute("BuildType") == "raft" then
			table.insert(offsets, {x = gx, z = gz})
		end
	end
	return offsets
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

local function cornerHasFloor(offsets, cx, cz)
	return isFloorOccupied(offsets, cx - 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
end

local function computeBeamInset(offsets, cx, cz)
	local insetX, insetZ = 0, 0

	local hasPlusX = isFloorOccupied(offsets, cx + 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusX = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)

	if hasMinusX and not hasPlusX then
		insetX = -BEAM_INSET
	elseif hasPlusX and not hasMinusX then
		insetX = BEAM_INSET
	end

	local hasPlusZ = isFloorOccupied(offsets, cx - 0.5, cz + 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusZ = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)

	if hasMinusZ and not hasPlusZ then
		insetZ = -BEAM_INSET
	elseif hasPlusZ and not hasMinusZ then
		insetZ = BEAM_INSET
	end

	return insetX, insetZ
end

local function makeBeamKey(cx, cz)
	return string.format("%.1f_%.1f", cx, cz)
end

local function makeSpanKey(cx1, cz1, cx2, cz2)
	if cx1 > cx2 or (cx1 == cx2 and cz1 > cz2) then
		cx1, cz1, cx2, cz2 = cx2, cz2, cx1, cz1
	end
	return string.format("%.1f_%.1f_%.1f_%.1f", cx1, cz1, cx2, cz2)
end

local function makeWallPanelKey(cx1, cz1, cx2, cz2)
	return "wp_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeWallArchKey(cx1, cz1, cx2, cz2)
	return "wa_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeDoorKey(cx1, cz1, cx2, cz2)
	return "dr_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function getBeamKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local bk = child:GetAttribute("BeamKey")
		if bk then keys[bk] = true end
	end
	return keys
end

local function getWallSpanKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local sk = child:GetAttribute("WallSpanKey")
		if sk then keys[sk] = true end
	end
	return keys
end

local function getWallPanelKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallPanelKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getWallArchKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallArchKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getDoorKeys()
	local raft = getRaft()
	if not raft then return {} end
	local keys = {}
	for _, child in raft:GetChildren() do
		local dk = child:GetAttribute("DoorKey")
		if dk then keys[dk] = true end
	end
	return keys
end

-- ===================== Coordinate conversion =====================

-- Both raycastToRaftPlane and localToWorld use RestYaw/RestCFrame so the
-- cursor → grid → world round-trip is consistent, giving stable grid coords
-- regardless of current wave-induced pitch/roll. localToWorld returns the
-- raft's ACTUAL physical yaw for rotation so beams/walls face the right
-- direction during a wind turn.
--
-- Cursor projection works in two stages:
--   1. Direct workspace raycast against the raft itself. When the cursor
--      is over an existing deck part, this gives us the exact world point
--      under the pointer with zero parallax.
--   2. Plane fallback for when the cursor is over water (extending the
--      raft). The plane is placed at the TOP of the PrimaryPart's world-Y
--      bounding box, not at its centre. The PrimaryPart is a sideways log
--      whose centre Y sits well below the walkable deck surface, so using
--      the raw centre causes an oblique camera to parallax-skew the cursor
--      hit away from the camera — a strip of cells in front of the player
--      would project backward onto the existing raft and hide the preview.
local raftRaycastParams = RaycastParams.new()
raftRaycastParams.FilterType = Enum.RaycastFilterType.Include
raftRaycastParams.IgnoreWater = true

local function raycastToRaftPlane()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end

	local cf = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or cf
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local hitWorld = nil

	-- Stage 1: direct raycast against the raft.
	raftRaycastParams.FilterDescendantsInstances = {raft}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, raftRaycastParams)
	if result then
		hitWorld = result.Position
	else
		-- Stage 2: plane fallback at the top of the PrimaryPart. Use the
		-- rest rotation so the plane Y doesn't wobble with waves.
		local size = raft.PrimaryPart.Size
		local restRotCF = restCF - restCF.Position
		local topOffset = -math.huge
		for xi = -1, 1, 2 do
			for yi = -1, 1, 2 do
				for zi = -1, 1, 2 do
					local corner = restRotCF * Vector3.new(xi * size.X / 2, yi * size.Y / 2, zi * size.Z / 2)
					if corner.Y > topOffset then
						topOffset = corner.Y
					end
				end
			end
		end
		local stableY = restCF.Position.Y + topOffset

		local denom = ray.Direction.Y
		if math.abs(denom) < 0.001 then return nil end
		local t = (stableY - ray.Origin.Y) / denom
		if t < 0 then return nil end
		hitWorld = ray.Origin + ray.Direction * t
	end

	-- Convert the world hit into the raft's yaw-aligned local frame. Only
	-- X and Z matter for grid snapping — the plane frame is rotated around
	-- the world Y axis, so the local XZ is independent of the frame's Y.
	local flatCF = CFrame.new(cf.Position.X, hitWorld.Y, cf.Position.Z) * CFrame.Angles(0, restYaw, 0)
	return flatCF:PointToObjectSpace(hitWorld)
end

local function localToWorld(studX, studZ)
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return Vector3.zero, 0 end
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX, 0, studZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return (primaryCF * CFrame.new(localOffset)).Position, restYaw
end

-- ===================== Floor grid =====================

local function getFloorGridFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil end

	local raft = getRaft()
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(
		math.round(localHit.X / GRID_SIZE) * GRID_SIZE, 0,
		math.round(localHit.Z / GRID_SIZE) * GRID_SIZE
	))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)
	local worldCF = primaryCF * CFrame.new(localOffset)

	return gx, gz, worldCF
end

-- ===================== Beam corner =====================

local function getBeamCornerFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil, nil, nil end

	local gridX = localHit.X / GRID_SIZE
	local gridZ = localHit.Z / GRID_SIZE
	local cx = math.floor(gridX) + 0.5
	local cz = math.floor(gridZ) + 0.5

	local offsets = getFloorOffsets()
	local insetX, insetZ = computeBeamInset(offsets, cx, cz)
	local studX = cx * GRID_SIZE + insetX + BEAM_X_OFFSET
	local studZ = cz * GRID_SIZE + insetZ

	local worldPos, restYaw = localToWorld(studX, studZ)
	worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT / 2, 0)
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)

	return cx, cz, worldCF
end

-- ===================== Wall panel between beams =====================

local function getWallPanelFromMouse()
	local localHit = raycastToRaftPlane()
	if not localHit then return nil end

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	local side
	if math.abs(dx) > math.abs(dz) then
		side = (dx > 0) and 3 or 2
	else
		side = (dz > 0) and 0 or 1
	end

	local cx1, cz1, cx2, cz2
	if side == 0 then
		cx1, cz1 = gx - 0.5, gz + 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	elseif side == 1 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz - 0.5
	elseif side == 2 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx - 0.5, gz + 0.5
	elseif side == 3 then
		cx1, cz1 = gx + 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	end

	local offsets = getFloorOffsets()
	local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
	local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
	local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
	local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2

	local worldPos, restYaw = localToWorld(midStudX, midStudZ)
	worldPos = worldPos + Vector3.new(0, PANEL_HEIGHT / 2, 0)

	local sideAngle = (side == 2 or side == 3) and math.rad(90) or 0
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

	return cx1, cz1, cx2, cz2, side, worldCF
end

-- ===================== Wall arch / Door (same beam-pair geometry) =====================

-- Shared computation: pick the cell side under the cursor and return both
-- the beam-pair coords AND the world position for an object of `height`
-- centered between those two beams.
local function getBeamPairFromMouse(height)
	local localHit = raycastToRaftPlane()
	if not localHit then return nil end

	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)

	local cellCenterX = gx * GRID_SIZE
	local cellCenterZ = gz * GRID_SIZE
	local dx = localHit.X - cellCenterX
	local dz = localHit.Z - cellCenterZ

	local side
	if math.abs(dx) > math.abs(dz) then
		side = (dx > 0) and 3 or 2
	else
		side = (dz > 0) and 0 or 1
	end

	local cx1, cz1, cx2, cz2
	if side == 0 then
		cx1, cz1 = gx - 0.5, gz + 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	elseif side == 1 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz - 0.5
	elseif side == 2 then
		cx1, cz1 = gx - 0.5, gz - 0.5
		cx2, cz2 = gx - 0.5, gz + 0.5
	elseif side == 3 then
		cx1, cz1 = gx + 0.5, gz - 0.5
		cx2, cz2 = gx + 0.5, gz + 0.5
	end

	local offsets = getFloorOffsets()
	local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
	local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
	local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
	local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2

	local worldPos, restYaw = localToWorld(midStudX, midStudZ)
	worldPos = worldPos + Vector3.new(0, height / 2, 0)

	local sideAngle = (side == 2 or side == 3) and math.rad(90) or 0
	local worldCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

	return cx1, cz1, cx2, cz2, side, worldCF
end

local function getWallArchFromMouse()
	return getBeamPairFromMouse(ARCH_HEIGHT)
end

local function getDoorFromMouse()
	return getBeamPairFromMouse(DOOR_HEIGHT)
end

-- ===================== Preview helpers =====================

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
	if item.buildType == "beam" then return beamTemplate or raftPartTemplate end
	if item.buildType == "wall_panel" then return wallPanelTemplate or raftPartTemplate end
	if item.buildType == "wall_arch" then return wallArchTemplate or raftPartTemplate end
	if item.buildType == "door" then return doorTemplate or raftPartTemplate end
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

		local catIcon = Instance.new("ImageLabel")
		catIcon.Size = UDim2.new(0.6, 0, 0.6, 0)
		catIcon.Position = UDim2.new(0.2, 0, 0.05, 0)
		catIcon.BackgroundTransparency = 1
		catIcon.Image = catData.icon
		catIcon.Parent = catBtn

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
			selectedItem = categories[i].items[1]
			destroyPreview()
			buildUI()
			createPreview()
		end)
	end

	local items = cat.items
	local itemCount = #items
	local itemPanelW = itemCount * (ITEM_SIZE + ITEM_PAD) + ITEM_PAD
	local itemPanelH = ITEM_SIZE + ITEM_PAD * 2 + 20

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

		local itemIcon = Instance.new("ImageLabel")
		itemIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
		itemIcon.Position = UDim2.new(0.15, 0, 0.02, 0)
		itemIcon.BackgroundTransparency = 1
		itemIcon.Image = item.icon
		itemIcon.Parent = itemBtn

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

	selectedCategory = 1
	selectedItem = categories[1].items[1]

	buildUI()
	createPreview()

	renderConnection = RunService.RenderStepped:Connect(function()
		if not isBuilding or not previewPart or not selectedItem then return end

		if selectedItem.buildType == "raft" then
			local gx, gz, worldCF = getFloorGridFromMouse()
			if not gx then hidePreview(); return end

			local offsets = getFloorOffsets()
			if isFloorOccupied(offsets, gx, gz) then hidePreview(); return end

			movePreview(worldCF)
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = isFloorAdjacent(offsets, gx, gz) and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "beam" then
			local cx, cz, worldCF = getBeamCornerFromMouse()
			if not cx then hidePreview(); return end

			movePreview(worldCF)
			local offsets = getFloorOffsets()
			local hasFloor = cornerHasFloor(offsets, cx, cz)
			local beamKey = makeBeamKey(cx, cz)
			local alreadyPlaced = getBeamKeys()[beamKey]
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = hasFloor and not alreadyPlaced and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "wall_panel" then
			local cx1, cz1, cx2, cz2, side, worldCF = getWallPanelFromMouse()
			if not cx1 then hidePreview(); return end

			movePreview(worldCF)
			local beams = getBeamKeys()
			local hasBeam1 = beams[makeBeamKey(cx1, cz1)]
			local hasBeam2 = beams[makeBeamKey(cx2, cz2)]
			local spanKey = makeSpanKey(cx1, cz1, cx2, cz2)
			local spanOccupied = getWallSpanKeys()[spanKey]
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = hasBeam1 and hasBeam2 and not spanOccupied and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "wall_arch" then
			local cx1, cz1, cx2, cz2, side, worldCF = getWallArchFromMouse()
			if not cx1 then hidePreview(); return end

			movePreview(worldCF)
			local beams = getBeamKeys()
			local hasBeam1 = beams[makeBeamKey(cx1, cz1)]
			local hasBeam2 = beams[makeBeamKey(cx2, cz2)]
			local spanKey = makeSpanKey(cx1, cz1, cx2, cz2)
			local spanOccupied = getWallSpanKeys()[spanKey]
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = hasBeam1 and hasBeam2 and not spanOccupied and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)

		elseif selectedItem.buildType == "door" then
			local cx1, cz1, cx2, cz2, side, worldCF = getDoorFromMouse()
			if not cx1 then hidePreview(); return end

			movePreview(worldCF)
			local hasArch = getWallArchKeys()[makeWallArchKey(cx1, cz1, cx2, cz2)]
			local doorExists = getDoorKeys()[makeDoorKey(cx1, cz1, cx2, cz2)]
			local canAfford = (inventory[selectedItem.costType] or 0) >= selectedItem.cost
			local valid = hasArch and not doorExists and canAfford
			setPreviewAppearance(valid and PREVIEW_COLOR_VALID or PREVIEW_COLOR_INVALID)
		end
	end)
end

local function hasEquippedHammer(character)
	if not character then return false end
	local equippedTool = character:FindFirstChildWhichIsA("Tool")
	return equippedTool and equippedTool.Name == "Hammer"
end

-- ─── Wind warning UI ─────────────────────────────────────────────────────────
-- When wind is active we block the building GUI entirely and instead show a
-- warning label just above the hotbar. The hotbar lives at the bottom-centre
-- of the screen (see InventoryUI.client.lua); these offsets match its top
-- edge so the warning sits 10px above it.
local HOTBAR_TOP_OFFSET = -82    -- -(SLOT_SIZE + SLOT_PAD*2) - 10 from InventoryUI
local WARNING_GAP = 10           -- vertical gap above the hotbar
local WARNING_HEIGHT = 36

local windWarningGui = nil
local windWarningLabel = nil

local function ensureWindWarningGui()
	if windWarningGui and windWarningGui.Parent then return end

	windWarningGui = Instance.new("ScreenGui")
	windWarningGui.Name = "BuildWindWarning"
	windWarningGui.ResetOnSpawn = false
	windWarningGui.DisplayOrder = 25 -- above hotbar (5) and build UI (20)
	windWarningGui.IgnoreGuiInset = true
	windWarningGui.Enabled = false
	windWarningGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, HOTBAR_TOP_OFFSET - WARNING_GAP)
	label.Size = UDim2.new(0, 460, 0, WARNING_HEIGHT)
	label.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = "Building during wind is dangerous"
	label.TextColor3 = Color3.fromRGB(255, 200, 120)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Parent = windWarningGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 120, 60)
	stroke.Thickness = 1.5
	stroke.Parent = label

	windWarningLabel = label
end

local function showWindWarning()
	ensureWindWarningGui()
	windWarningGui.Enabled = true
end

local function hideWindWarning()
	if windWarningGui then
		windWarningGui.Enabled = false
	end
end

-- ─── Wind state tracking ─────────────────────────────────────────────────────
local function isWindActive()
	return player:GetAttribute("WindActive") == true
end

local function syncBuildMode(character)
	local equipped = hasEquippedHammer(character)
	local windActive = isWindActive()

	if equipped and windActive then
		-- Hammer out during wind: block the build UI, show warning.
		if isBuilding then closeBuildMode() end
		showWindWarning()
	elseif equipped and not windActive then
		-- Safe to build.
		hideWindWarning()
		if not isBuilding then startBuildMode() end
	else
		-- Hammer not equipped: nothing to show.
		hideWindWarning()
		if isBuilding then closeBuildMode() end
	end
end

-- Re-sync whenever wind turns on/off so the warning appears/disappears
-- without the player having to re-equip the hammer.
player:GetAttributeChangedSignal("WindActive"):Connect(function()
	syncBuildMode(player.Character)
end)

local function onCharacterAdded(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Hammer" then
			syncBuildMode(character)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Hammer" then
			syncBuildMode(character)
		end
	end)

	-- Some inventory flows re-parent tools in a way that can miss ChildAdded/Removed
	-- transitions, so we keep a lightweight heartbeat sync as a safety net.
	if hammerWatchConnection then
		hammerWatchConnection:Disconnect()
	end
	hammerWatchConnection = RunService.Heartbeat:Connect(function()
		syncBuildMode(character)
	end)

	syncBuildMode(character)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if hammerWatchConnection then
				hammerWatchConnection:Disconnect()
				hammerWatchConnection = nil
			end
			closeBuildMode()
			hideWindWarning()
		end
	end)
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

	elseif selectedItem.buildType == "beam" then
		local cx, cz, _ = getBeamCornerFromMouse()
		if not cx then return end

		local offsets = getFloorOffsets()
		if not cornerHasFloor(offsets, cx, cz) then return end
		if getBeamKeys()[makeBeamKey(cx, cz)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("beam", cx, cz)

	elseif selectedItem.buildType == "wall_panel" then
		local cx1, cz1, cx2, cz2, side, _ = getWallPanelFromMouse()
		if not cx1 then return end

		local beams = getBeamKeys()
		if not beams[makeBeamKey(cx1, cz1)] or not beams[makeBeamKey(cx2, cz2)] then return end
		if getWallSpanKeys()[makeSpanKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_panel", cx1, cz1, cx2, cz2)

	elseif selectedItem.buildType == "wall_arch" then
		local cx1, cz1, cx2, cz2, side, _ = getWallArchFromMouse()
		if not cx1 then return end

		local beams = getBeamKeys()
		if not beams[makeBeamKey(cx1, cz1)] or not beams[makeBeamKey(cx2, cz2)] then return end
		if getWallSpanKeys()[makeSpanKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_arch", cx1, cz1, cx2, cz2)

	elseif selectedItem.buildType == "door" then
		local cx1, cz1, cx2, cz2, side, _ = getDoorFromMouse()
		if not cx1 then return end

		if not getWallArchKeys()[makeWallArchKey(cx1, cz1, cx2, cz2)] then return end
		if getDoorKeys()[makeDoorKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("door", cx1, cz1, cx2, cz2)
	end
end)

placeBlockEvent.OnClientEvent:Connect(function() end)
