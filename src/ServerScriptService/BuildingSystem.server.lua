local rs = game:GetService("ReplicatedStorage")

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

local raftPartTemplate = rs:WaitForChild("Raft_part")
local beamTemplate = rs:FindFirstChild("beam")
local wallPanelTemplate = rs:FindFirstChild("wall_model_wood")
local wallArchTemplate = rs:FindFirstChild("wall_model_wood_arch")
local doorWoodTemplate = rs:FindFirstChild("Door_Wood")

-- Measure grid size from the actual template bounding box
local GRID_SIZE
if raftPartTemplate:IsA("Model") then
	local size = raftPartTemplate:GetExtentsSize()
	GRID_SIZE = math.max(size.X, size.Z)
elseif raftPartTemplate:IsA("BasePart") then
	GRID_SIZE = math.max(raftPartTemplate.Size.X, raftPartTemplate.Size.Z)
else
	GRID_SIZE = 6
end
raftPartTemplate:SetAttribute("GridSize", GRID_SIZE)

-- Measure beam dimensions
local BEAM_HEIGHT = 0
local BEAM_FOOTPRINT = 0
if beamTemplate then
	if beamTemplate:IsA("Model") then
		local size = beamTemplate:GetExtentsSize()
		BEAM_HEIGHT = size.Y
		BEAM_FOOTPRINT = math.max(size.X, size.Z)
	elseif beamTemplate:IsA("BasePart") then
		BEAM_HEIGHT = beamTemplate.Size.Y
		BEAM_FOOTPRINT = math.max(beamTemplate.Size.X, beamTemplate.Size.Z)
	end
end
local BEAM_INSET = BEAM_FOOTPRINT / 2
raftPartTemplate:SetAttribute("BeamHeight", BEAM_HEIGHT)
raftPartTemplate:SetAttribute("BeamInset", BEAM_INSET)

-- Measure wall panel height
local PANEL_HEIGHT = 0
if wallPanelTemplate then
	if wallPanelTemplate:IsA("Model") then
		PANEL_HEIGHT = wallPanelTemplate:GetExtentsSize().Y
	elseif wallPanelTemplate:IsA("BasePart") then
		PANEL_HEIGHT = wallPanelTemplate.Size.Y
	end
end
raftPartTemplate:SetAttribute("PanelHeight", PANEL_HEIGHT)

local ARCH_HEIGHT = 0
if wallArchTemplate then
	if wallArchTemplate:IsA("Model") then
		ARCH_HEIGHT = wallArchTemplate:GetExtentsSize().Y
	elseif wallArchTemplate:IsA("BasePart") then
		ARCH_HEIGHT = wallArchTemplate.Size.Y
	end
end
raftPartTemplate:SetAttribute("ArchHeight", ARCH_HEIGHT)

local DOOR_HEIGHT = 0
if doorWoodTemplate then
	if doorWoodTemplate:IsA("Model") then
		DOOR_HEIGHT = doorWoodTemplate:GetExtentsSize().Y
	elseif doorWoodTemplate:IsA("BasePart") then
		DOOR_HEIGHT = doorWoodTemplate.Size.Y
	end
end
raftPartTemplate:SetAttribute("DoorHeight", DOOR_HEIGHT)

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

local RAFT_COST = 2
local BEAM_COST = 1
local WALL_PANEL_COST = 3
local WALL_ARCH_COST = 3
local DOOR_WOOD_COST = 2

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

local function getFloorOffsets(raft)
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

-- Beam corner: at least one adjacent floor tile must exist
local function cornerHasFloor(offsets, cx, cz)
	return isFloorOccupied(offsets, cx - 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
end

-- Compute inset to keep beam within raft boundaries
-- Shifts the beam toward the raft interior on edges where no tile exists beyond
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

local function makeWallPanelKey(cx1, cz1, cx2, cz2)
	if cx1 > cx2 or (cx1 == cx2 and cz1 > cz2) then
		cx1, cz1, cx2, cz2 = cx2, cz2, cx1, cz1
	end
	return string.format("wp_%.1f_%.1f_%.1f_%.1f", cx1, cz1, cx2, cz2)
end

local function getBeamKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local bk = child:GetAttribute("BeamKey")
		if bk then keys[bk] = true end
	end
	return keys
end

local function getWallPanelKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallPanelKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getWallArchKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		if child:GetAttribute("BuildType") == "wall_arch" then
			local wk = child:GetAttribute("WallArchKey")
			if wk then keys[wk] = true end
		end
	end
	return keys
end

local function getDoorKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		if child:GetAttribute("BuildType") == "door_wood" then
			local dk = child:GetAttribute("DoorKey")
			if dk then keys[dk] = true end
		end
	end
	return keys
end

-- Convert local studs position to world position.
-- Position is computed via the stable RestCFrame approach (same as the save
-- system) so the local offset captured by the WeldConstraint is always the
-- same regardless of current wave-induced tilt. Returned yaw is RestYaw so
-- beams/walls stay perfectly aligned to the build grid.
local function localToWorld(raft, studX, studZ)
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX, 0, studZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return (primaryCF * CFrame.new(localOffset)).Position, restYaw
end

local function weldToRaft(obj, raft, shouldSkipWeld)
	-- Weld FIRST while still anchored, then unanchor in a second pass.
	-- If we unanchor first, each part briefly exists as a zero-velocity body
	-- before the weld attaches it to the moving raft. Welding while still
	-- anchored captures the relative pose without any free-physics step.
	-- After unanchoring we also pin network ownership to the server so
	-- Roblox doesn't reassign ownership of the raft assembly mid-placement.
	local function unanchorAndPin(part)
		part.Anchored = false
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end
	if obj:IsA("Model") then
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				if not (shouldSkipWeld and shouldSkipWeld(desc)) then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = desc
					weld.Part1 = raft.PrimaryPart
					weld.Parent = desc
				end
			end
		end
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				unanchorAndPin(desc)
			end
		end
	elseif obj:IsA("BasePart") then
		if not (shouldSkipWeld and shouldSkipWeld(obj)) then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = obj
			weld.Part1 = raft.PrimaryPart
			weld.Parent = obj
		end
		unanchorAndPin(obj)
	end
end

local function prepareDoorForAnimation(model)
	if not model or not model:IsA("Model") then return end
	local hinge = model:FindFirstChild("Hinge", true)
	if not hinge or not hinge:IsA("BasePart") then return end

	-- If the template contains prebuilt rigid joints to the hinge, they lock
	-- the leaf in place and TweenService CFrame changes won't rotate it.
	for _, desc in model:GetDescendants() do
		if desc:IsA("WeldConstraint") and (desc.Part0 == hinge or desc.Part1 == hinge) then
			desc:Destroy()
		elseif desc:IsA("JointInstance") and (desc.Part0 == hinge or desc.Part1 == hinge) then
			desc:Destroy()
		end
	end

	hinge.Anchored = false
	pcall(function()
		hinge:SetNetworkOwner(nil)
	end)
end

local function setDoorGhostState(model, isOpen)
	local hinge = model and model:FindFirstChild("Hinge", true)
	if hinge and hinge:IsA("BasePart") then
		hinge.Transparency = isOpen and 1 or 0
		hinge.CanCollide = not isOpen
	end
	model:SetAttribute("DoorIsOpen", isOpen)
end

local function installDoorPromptLogic(model)
	if not model or not model:IsA("Model") then return end
	if model:GetAttribute("DoorPromptHooked") then return end

	local legacyScript = model:FindFirstChildWhichIsA("Script", true)
	if legacyScript then
		legacyScript.Disabled = true
	end

	local base = model:FindFirstChild("Base", true)
	local prompt = base and base:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end

	local function refreshPromptText()
		prompt.ActionText = (model:GetAttribute("DoorIsOpen") and "Close") or "Open"
	end

	model:SetAttribute("DoorPromptHooked", true)
	if model:GetAttribute("DoorIsOpen") == nil then
		model:SetAttribute("DoorIsOpen", false)
	end
	setDoorGhostState(model, model:GetAttribute("DoorIsOpen"))
	refreshPromptText()

	prompt.Triggered:Connect(function()
		local openNow = not model:GetAttribute("DoorIsOpen")
		setDoorGhostState(model, openNow)
		refreshPromptText()
	end)
end

-- Welding a new part with mass into the moving raft assembly causes Roblox
-- to equilibrate momentum: the combined velocity = (M*V + m*0)/(M+m), so
-- the raft loses a factor of m/M of its forward velocity. Across many
-- placements this manifests as the player visibly desyncing from the raft.
-- We snapshot the raft's velocity before the weld and restore it after, so
-- the assembly's velocity is unaffected by the addition.
local function placeWithVelocityPreserved(raft, doPlace)
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity
	doPlace()
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
end

placeBlockEvent.OnServerEvent:Connect(function(player, buildType, ...)
	if type(buildType) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Hammer" then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	if buildType == "raft" then
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end
		if (inv.Log or 0) < RAFT_COST then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		-- Use the stable RestCFrame approach so the WeldConstraint captures the
		-- same local offset as all other tiles, regardless of current tilt.
		local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raft.PrimaryPart.CFrame
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
		local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		inv.Log = inv.Log - RAFT_COST

		local newPart = raftPartTemplate:Clone()
		newPart:SetAttribute("GridX", gx)
		newPart:SetAttribute("GridZ", gz)
		newPart:SetAttribute("BuildType", "raft")

		if newPart:IsA("Model") then
			newPart:PivotTo(worldCF)
		elseif newPart:IsA("BasePart") then
			newPart.CFrame = worldCF
		end
		placeWithVelocityPreserved(raft, function()
			newPart.Parent = raft
			weldToRaft(newPart, raft)
		end)

	elseif buildType == "beam" then
		if not beamTemplate then return end
		local cx, cz = ...
		if type(cx) ~= "number" or type(cz) ~= "number" then return end
		if (inv.Log or 0) < BEAM_COST then return end

		cx = math.floor(cx) + 0.5
		cz = math.floor(cz) + 0.5

		local offsets = getFloorOffsets(raft)
		if not cornerHasFloor(offsets, cx, cz) then return end

		local bk = makeBeamKey(cx, cz)
		if getBeamKeys(raft)[bk] then return end

		local insetX, insetZ = computeBeamInset(offsets, cx, cz)
		local studX = cx * GRID_SIZE + insetX + BEAM_X_OFFSET
		local studZ = cz * GRID_SIZE + insetZ
		local worldPos, restYaw = localToWorld(raft, studX, studZ)
		worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - BEAM_COST

		local newBeam = beamTemplate:Clone()
		newBeam:SetAttribute("BuildType", "beam")
		newBeam:SetAttribute("BeamKey", bk)
		newBeam:SetAttribute("CornerX", cx)
		newBeam:SetAttribute("CornerZ", cz)

		local beamCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)
		if newBeam:IsA("Model") then
			newBeam:PivotTo(beamCF)
		else
			newBeam.CFrame = beamCF
		end
		placeWithVelocityPreserved(raft, function()
			newBeam.Parent = raft
			weldToRaft(newBeam, raft)
		end)

	elseif buildType == "wall_panel" or buildType == "wall_arch" or buildType == "door_wood" then
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		local wpk = makeWallPanelKey(cx1, cz1, cx2, cz2)
		local panelKeys = getWallPanelKeys(raft)
		local archKeys = getWallArchKeys(raft)
		local doorKeys = getDoorKeys(raft)
		local beamKeys = getBeamKeys(raft)

		local cost = WALL_PANEL_COST
		local template = wallPanelTemplate
		local attrBuildType = "wall_panel"
		local keyAttrName = "WallPanelKey"
		local elementHeight = PANEL_HEIGHT

		if buildType == "door_wood" then
			if not doorWoodTemplate then return end
			if not archKeys[wpk] then return end
			if doorKeys[wpk] then return end
			cost = DOOR_WOOD_COST
			template = doorWoodTemplate
			attrBuildType = "door_wood"
			keyAttrName = "DoorKey"
			elementHeight = DOOR_HEIGHT
		else
			if not beamKeys[makeBeamKey(cx1, cz1)] or not beamKeys[makeBeamKey(cx2, cz2)] then return end
			if panelKeys[wpk] or archKeys[wpk] then return end
			if buildType == "wall_arch" then
				if not wallArchTemplate then return end
				cost = WALL_ARCH_COST
				template = wallArchTemplate
				attrBuildType = "wall_arch"
				keyAttrName = "WallArchKey"
				elementHeight = ARCH_HEIGHT
			else
				if not wallPanelTemplate then return end
			end
		end

		if (inv.Log or 0) < cost then return end

		local offsets = getFloorOffsets(raft)
		local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
		local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
		local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
		local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = worldPos + Vector3.new(0, elementHeight / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - cost

		local newWall = template:Clone()
		newWall:SetAttribute("BuildType", attrBuildType)
		newWall:SetAttribute(keyAttrName, wpk)
		newWall:SetAttribute("BeamCX1", cx1)
		newWall:SetAttribute("BeamCZ1", cz1)
		newWall:SetAttribute("BeamCX2", cx2)
		newWall:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local wallCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newWall:IsA("Model") then
			newWall:PivotTo(wallCF)
		else
			newWall.CFrame = wallCF
		end
		if attrBuildType == "door_wood" then
			prepareDoorForAnimation(newWall)
		end
		placeWithVelocityPreserved(raft, function()
			newWall.Parent = raft
			local skipWeld = nil
			if attrBuildType == "door_wood" then
				skipWeld = function(part)
					return part.Name == "Hinge"
				end
			end
			weldToRaft(newWall, raft, skipWeld)
			if attrBuildType == "door_wood" then
				task.defer(function()
					if newWall.Parent then
						prepareDoorForAnimation(newWall)
					end
				end)
			end
		end)
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
