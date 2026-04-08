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

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

local RAFT_COST = 2
local BEAM_COST = 1
local WALL_PANEL_COST = 3

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

-- Convert local studs position to world position.
-- Position is computed via the stable RestCFrame approach (same as the save
-- system) so the local offset captured by the WeldConstraint is always the
-- same regardless of current wave-induced tilt. Only the returned yaw uses
-- the raft's ACTUAL physical value so beams/walls face the right direction
-- during a wind-driven turn (the fix from commit 9c15658).
local function localToWorld(raft, studX, studZ)
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX, 0, studZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	local _, actualYaw = primaryCF:ToEulerAnglesYXZ()
	return (primaryCF * CFrame.new(localOffset)).Position, actualYaw
end

local function weldToRaft(obj, raft)
	-- Order of operations matters here. We need to:
	--   1. Mark the new part Massless so it adds no inertia to the raft
	--      assembly. This is the key fix for the placement teleport: when
	--      a part with mass is welded into the moving raft, Roblox has to
	--      equilibrate the assembly's momentum and recompute its inertia
	--      tensor, which causes a one-frame physics hiccup that desyncs
	--      the player from the raft (visible as a teleport opposite to
	--      the raft's direction of travel). A massless part contributes
	--      nothing to either, so the assembly is undisturbed.
	--   2. Create the WeldConstraint while the part is still anchored, so
	--      the relative pose is captured without a free-physics step.
	--   3. Unanchor and pin network ownership to the server so Roblox
	--      doesn't reassign ownership of the raft assembly mid-placement.
	local function setupPart(part)
		part.Massless = true
	end
	local function unanchorAndPin(part)
		part.Anchored = false
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end
	if obj:IsA("Model") then
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				setupPart(desc)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = raft.PrimaryPart
				weld.Parent = desc
			end
		end
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				unanchorAndPin(desc)
			end
		end
	elseif obj:IsA("BasePart") then
		setupPart(obj)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = obj
		weld.Part1 = raft.PrimaryPart
		weld.Parent = obj
		unanchorAndPin(obj)
	end
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
		newPart.Parent = raft
		weldToRaft(newPart, raft)

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
		newBeam.Parent = raft
		weldToRaft(newBeam, raft)

	elseif buildType == "wall_panel" then
		if not wallPanelTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < WALL_PANEL_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		local beamKeys = getBeamKeys(raft)
		if not beamKeys[makeBeamKey(cx1, cz1)] or not beamKeys[makeBeamKey(cx2, cz2)] then return end

		local wpk = makeWallPanelKey(cx1, cz1, cx2, cz2)
		if getWallPanelKeys(raft)[wpk] then return end

		local offsets = getFloorOffsets(raft)
		local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
		local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
		local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
		local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = worldPos + Vector3.new(0, PANEL_HEIGHT / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - WALL_PANEL_COST

		local newWall = wallPanelTemplate:Clone()
		newWall:SetAttribute("BuildType", "wall_panel")
		newWall:SetAttribute("WallPanelKey", wpk)
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
		newWall.Parent = raft
		weldToRaft(newWall, raft)
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
