local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

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
local FLOOR_ICON = "rbxassetid://114819085093343"
local WALL_ICON = "rbxassetid://103259353018381"
local BEAM_ICON = "rbxassetid://128953076654373"
local ARCH_ICON = "rbxassetid://90064054384398"

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
			{id = "beam", name = "Beam", icon = BEAM_ICON, cost = 1, costType = "Log", buildType = "beam"},
			{id = "wall_panel", name = "Wood Wall", icon = WALL_ICON, cost = 3, costType = "Log", buildType = "wall_panel"},
			{id = "wall_arch", name = "Door Arch", icon = ARCH_ICON, cost = 3, costType = "Log", buildType = "wall_arch"},
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
	local seen = {}
	local primary = raft.PrimaryPart

	-- Use a yaw-only CFrame for grid coordinate detection, matching the
	-- placement system (which uses restYaw). Using primary.CFrame directly
	-- would include pitch/roll that can mix world-Y into local X/Z and
	-- collapse multiple tiles to the same grid coordinate.
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") == "raft" then
			local key = gx .. "_" .. gz
			if not seen[key] then
				seen[key] = true
				table.insert(offsets, {x = gx, z = gz})
			end
		elseif child.Name == "Raft_part" or child == primary then
			-- Use GetPivot() for Models (what PivotTo aligns) for accuracy.
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				local gridX = math.round(localPos.X / GRID_SIZE)
				local gridZ = math.round(localPos.Z / GRID_SIZE)
				local key = gridX .. "_" .. gridZ
				if not seen[key] then
					seen[key] = true
					table.insert(offsets, {x = gridX, z = gridZ})
				end
			end
		end
	end

	if not seen["0_0"] then
		table.insert(offsets, {x = 0, z = 0})
	end

	return offsets
end

-- When PrimaryPart is not a Raft_part (e.g. a SpawnLocation), its orientation
-- differs from tile orientation. Returns a rotation correction so new tiles
-- match existing Raft_part orientation instead of PrimaryPart's.
local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			-- Use GetPivot() for Models since PivotTo() aligns to the pivot,
			-- not to any specific internal BasePart.
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				return primary.CFrame:ToObjectSpace(tileCF).Rotation
			end
		end
	end
	return CFrame.new()
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
-- restYaw for rotation so beams/walls face the right direction.
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

-- Returns the world position for a local stud offset on the raft AND the
-- restYaw for rotating beams/walls/doors to face raft-forward.
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
	local worldCF = primaryCF * CFrame.new(localOffset) * getTileRotationCorrection(raft)

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
	_G.BuildingScreenGui = nil
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

-- ===================== UI =====================

local CAT_W, CAT_H, CAT_PAD = 96, 40, 6      -- вкладки Floors/Walls
local CARD_W, CARD_H, CARD_PAD = 112, 150, 8 -- карточки блоков

-- Палитра «Океан» из редизайна (как инвентарь/крафт).
local UI_PANEL_TOP  = Color3.fromHex("54A7EC")
local UI_PANEL_BOT  = Color3.fromHex("3A7FD0")
local UI_FRAME      = Color3.fromHex("1C4F8F")
local UI_SLOT       = Color3.fromHex("A9D6F7")
local UI_GOLD_TOP   = Color3.fromHex("FFD95A")
local UI_GOLD       = Color3.fromHex("F5B73C")
local UI_GOLD_FRAME = Color3.fromHex("B07A14")
local UI_PRICE_OK   = Color3.fromHex("4CD964")
local UI_PRICE_NO   = Color3.fromHex("FF6B5A")

local function buildUI()
	if buildingUI then buildingUI:Destroy() end

	buildingUI = Instance.new("ScreenGui")
	buildingUI.Name = "BuildingGui"
	buildingUI.ResetOnSpawn = false
	buildingUI.DisplayOrder = 20
	buildingUI.Parent = playerGui

	-- Publish so QuestEntryButton (and any other side HUD that needs
	-- to step out of the way) can hide itself while the build UI is
	-- visible. Cleared in closeBuildMode below.
	_G.BuildingScreenGui = buildingUI

	local cat = categories[selectedCategory]

	-- Вкладки категорий (Floors/Walls): активная — золотая, остальные — синие.
	local catCount = #categories
	local catPanelH = catCount * (CAT_H + CAT_PAD) - CAT_PAD
	local catPanel = Instance.new("Frame")
	catPanel.Name = "CategoryPanel"
	catPanel.Size = UDim2.new(0, CAT_W, 0, catPanelH)
	catPanel.Position = UDim2.new(0, 12, 0.5, -catPanelH / 2)
	catPanel.BackgroundTransparency = 1
	catPanel.Parent = buildingUI

	for i, catData in categories do
		local isActive = (i == selectedCategory)

		local catBtn = Instance.new("TextButton")
		catBtn.Name = "Cat_" .. catData.name
		catBtn.Size = UDim2.new(1, 0, 0, CAT_H)
		catBtn.Position = UDim2.new(0, 0, 0, (i - 1) * (CAT_H + CAT_PAD))
		catBtn.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
		catBtn.BorderSizePixel = 0
		catBtn.Text = catData.name
		catBtn.TextColor3 = Color3.new(1, 1, 1)
		catBtn.Font = Enum.Font.GothamBlack
		catBtn.TextSize = 16
		catBtn.TextStrokeColor3 = Color3.new(0, 0, 0)
		catBtn.TextStrokeTransparency = 0.6
		catBtn.AutoButtonColor = false
		catBtn.Parent = catPanel

		local catGrad = Instance.new("UIGradient")
		catGrad.Rotation = 90
		catGrad.Color = isActive and ColorSequence.new(UI_GOLD_TOP, UI_GOLD)
			or ColorSequence.new(UI_PANEL_TOP, UI_PANEL_BOT)
		catGrad.Parent = catBtn

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 12)
		btnCorner.Parent = catBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = isActive and UI_GOLD_FRAME or UI_FRAME
		btnStroke.Thickness = 3
		btnStroke.Parent = catBtn

		catBtn.MouseButton1Click:Connect(function()
			if selectedCategory == i then return end
			selectedCategory = i
			selectedItem = categories[i].items[1]
			destroyPreview()
			buildUI()
			createPreview()
		end)
	end

	-- Карточки блоков: иконо-бокс + пилюля цены + имя; выбранная — золотая рамка.
	local items = cat.items
	local itemCount = #items
	local itemPanelW = itemCount * (CARD_W + CARD_PAD) - CARD_PAD

	local itemPanel = Instance.new("Frame")
	itemPanel.Name = "ItemPanel"
	itemPanel.Size = UDim2.new(0, itemPanelW, 0, CARD_H)
	itemPanel.Position = UDim2.new(0, 12 + CAT_W + 14, 0.5, -CARD_H / 2)
	itemPanel.BackgroundTransparency = 1
	itemPanel.Parent = buildingUI

	for i, item in items do
		local isActive = (selectedItem and selectedItem.id == item.id)
		local canAffordItem = (inventory[item.costType] or 0) >= item.cost

		local itemBtn = Instance.new("TextButton")
		itemBtn.Name = "Item_" .. item.id
		itemBtn.Size = UDim2.new(0, CARD_W, 0, CARD_H)
		itemBtn.Position = UDim2.new(0, (i - 1) * (CARD_W + CARD_PAD), 0, 0)
		itemBtn.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент
		itemBtn.BorderSizePixel = 0
		itemBtn.Text = ""
		itemBtn.AutoButtonColor = false
		itemBtn.Parent = itemPanel

		local cardGrad = Instance.new("UIGradient")
		cardGrad.Rotation = 90
		cardGrad.Color = ColorSequence.new(UI_PANEL_TOP, UI_PANEL_BOT)
		cardGrad.Parent = itemBtn

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 14)
		cardCorner.Parent = itemBtn

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = isActive and UI_GOLD or UI_FRAME
		cardStroke.Thickness = isActive and 4 or 3
		cardStroke.Parent = itemBtn

		-- иконка блока в светлом слот-боксе
		local boxSize = CARD_W - 28
		local iconBox = Instance.new("Frame")
		iconBox.Size = UDim2.new(0, boxSize, 0, boxSize)
		iconBox.Position = UDim2.new(0.5, -boxSize / 2, 0, 10)
		iconBox.BackgroundColor3 = UI_SLOT
		iconBox.BorderSizePixel = 0
		iconBox.Parent = itemBtn

		local iconBoxCorner = Instance.new("UICorner")
		iconBoxCorner.CornerRadius = UDim.new(0, 10)
		iconBoxCorner.Parent = iconBox

		local iconBoxStroke = Instance.new("UIStroke")
		iconBoxStroke.Color = UI_FRAME
		iconBoxStroke.Thickness = 2
		iconBoxStroke.Parent = iconBox

		local itemIcon = Instance.new("ImageLabel")
		itemIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		itemIcon.Size = UDim2.new(0.82, 0, 0.82, 0)
		itemIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		itemIcon.BackgroundTransparency = 1
		itemIcon.Image = item.icon
		itemIcon.ScaleType = Enum.ScaleType.Fit
		itemIcon.Parent = iconBox

		-- пилюля цены: зелёная если хватает, красная если нет
		local pill = Instance.new("Frame")
		pill.Name = "CostPill"
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 10 + boxSize + 5)
		pill.Size = UDim2.new(0, 0, 0, 20)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = canAffordItem and UI_PRICE_OK or UI_PRICE_NO
		pill.BorderSizePixel = 0
		pill.Parent = itemBtn

		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(1, 0)
		pillCorner.Parent = pill

		local pillPad = Instance.new("UIPadding")
		pillPad.PaddingLeft = UDim.new(0, 9)
		pillPad.PaddingRight = UDim.new(0, 9)
		pillPad.Parent = pill

		local pillText = Instance.new("TextLabel")
		pillText.AutomaticSize = Enum.AutomaticSize.X
		pillText.Size = UDim2.new(0, 0, 1, 0)
		pillText.BackgroundTransparency = 1
		pillText.Text = item.cost .. " " .. item.costType
		pillText.TextColor3 = Color3.new(1, 1, 1)
		pillText.Font = Enum.Font.GothamBold
		pillText.TextSize = 12
		pillText.TextStrokeColor3 = Color3.new(0, 0, 0)
		pillText.TextStrokeTransparency = 0.7
		pillText.Parent = pill

		-- имя блока внизу карточки
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -8, 0, 18)
		nameLbl.Position = UDim2.new(0, 4, 1, -24)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = item.name
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.Font = Enum.Font.GothamBlack
		nameLbl.TextSize = 13
		nameLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		nameLbl.TextStrokeTransparency = 0.6
		nameLbl.TextXAlignment = Enum.TextXAlignment.Center
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = itemBtn

		itemBtn.MouseButton1Click:Connect(function()
			selectedItem = item
			destroyPreview()
			buildUI()
			createPreview()
		end)
	end

	-- Подсказка — тёмная пилюля в левом нижнем углу (как в прототипе).
	local hint = Instance.new("Frame")
	hint.Name = "BuildHint"
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 12, 1, -12)
	hint.AutomaticSize = Enum.AutomaticSize.XY
	hint.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	hint.BackgroundTransparency = 0.25
	hint.BorderSizePixel = 0
	hint.Parent = buildingUI

	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(1, 0)
	hintCorner.Parent = hint

	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 12)
	hintPad.PaddingRight = UDim.new(0, 12)
	hintPad.PaddingTop = UDim.new(0, 6)
	hintPad.PaddingBottom = UDim.new(0, 6)
	hintPad.Parent = hint

	local hintText = Instance.new("TextLabel")
	hintText.AutomaticSize = Enum.AutomaticSize.XY
	hintText.Size = UDim2.new(0, 0, 0, 0)
	hintText.BackgroundTransparency = 1
	hintText.Text = "Click to place  ·  Unequip Hammer to exit"
	hintText.TextColor3 = Color3.fromRGB(235, 240, 245)
	hintText.Font = Enum.Font.GothamBold
	hintText.TextSize = 14
	hintText.Parent = hint
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
local function playPlaceSound()
	local folder = SoundService:FindFirstChild("Building")
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
end

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
		playPlaceSound()

	elseif selectedItem.buildType == "beam" then
		local cx, cz, _ = getBeamCornerFromMouse()
		if not cx then return end

		local offsets = getFloorOffsets()
		if not cornerHasFloor(offsets, cx, cz) then return end
		if getBeamKeys()[makeBeamKey(cx, cz)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("beam", cx, cz)
		playPlaceSound()

	elseif selectedItem.buildType == "wall_panel" then
		local cx1, cz1, cx2, cz2, side, _ = getWallPanelFromMouse()
		if not cx1 then return end

		local beams = getBeamKeys()
		if not beams[makeBeamKey(cx1, cz1)] or not beams[makeBeamKey(cx2, cz2)] then return end
		if getWallSpanKeys()[makeSpanKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_panel", cx1, cz1, cx2, cz2)
		playPlaceSound()

	elseif selectedItem.buildType == "wall_arch" then
		local cx1, cz1, cx2, cz2, side, _ = getWallArchFromMouse()
		if not cx1 then return end

		local beams = getBeamKeys()
		if not beams[makeBeamKey(cx1, cz1)] or not beams[makeBeamKey(cx2, cz2)] then return end
		if getWallSpanKeys()[makeSpanKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("wall_arch", cx1, cz1, cx2, cz2)
		playPlaceSound()

	elseif selectedItem.buildType == "door" then
		local cx1, cz1, cx2, cz2, side, _ = getDoorFromMouse()
		if not cx1 then return end

		if not getWallArchKeys()[makeWallArchKey(cx1, cz1, cx2, cz2)] then return end
		if getDoorKeys()[makeDoorKey(cx1, cz1, cx2, cz2)] then return end
		if (inventory[selectedItem.costType] or 0) < selectedItem.cost then return end

		placeBlockEvent:FireServer("door", cx1, cz1, cx2, cz2)
		playPlaceSound()
	end
end)

placeBlockEvent.OnClientEvent:Connect(function() end)
