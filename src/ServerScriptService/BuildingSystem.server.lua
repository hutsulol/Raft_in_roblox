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
local doorTemplate = rs:FindFirstChild("Door_Wood")

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

-- Measure wall arch height
local ARCH_HEIGHT = 0
if wallArchTemplate then
	if wallArchTemplate:IsA("Model") then
		ARCH_HEIGHT = wallArchTemplate:GetExtentsSize().Y
	elseif wallArchTemplate:IsA("BasePart") then
		ARCH_HEIGHT = wallArchTemplate.Size.Y
	end
end
raftPartTemplate:SetAttribute("ArchHeight", ARCH_HEIGHT)

-- Measure door height
local DOOR_HEIGHT = 0
if doorTemplate then
	if doorTemplate:IsA("Model") then
		DOOR_HEIGHT = doorTemplate:GetExtentsSize().Y
	elseif doorTemplate:IsA("BasePart") then
		DOOR_HEIGHT = doorTemplate.Size.Y
	end
end
raftPartTemplate:SetAttribute("DoorHeight", DOOR_HEIGHT)

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

local RAFT_COST = 2
local BEAM_COST = 1
local WALL_PANEL_COST = 3
local WALL_ARCH_COST = 3
local DOOR_COST = 2

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

local function getFloorOffsets(raft)
	local offsets = {}
	local seen = {}

	-- Scan all children of the raft for initial Raft_part tiles (no GridX/GridZ)
	-- and player-built tiles (with GridX/GridZ + BuildType == "raft").
	local primary = raft.PrimaryPart
	if not primary then return offsets end

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
			-- Player-built tile
			local key = gx .. "_" .. gz
			if not seen[key] then
				seen[key] = true
				table.insert(offsets, {x = gx, z = gz})
			end
		elseif child.Name == "Raft_part" or child == primary then
			-- Initial raft tile: compute grid coords from position.
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

	-- Guarantee (0,0) is always present
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

-- Normalized span between two beam corners (no prefix). Used as a shared
-- "this side of these two beams is occupied" key, so a wall panel and a wall
-- arch can never coexist on the same span.
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

local function getBeamKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local bk = child:GetAttribute("BeamKey")
		if bk then keys[bk] = true end
	end
	return keys
end

-- Returns the set of normalized spans currently occupied by ANY wall-like
-- object (wall_panel or wall_arch). Used to block placing two wall-types on
-- the same beam pair side.
local function getWallSpanKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local sk = child:GetAttribute("WallSpanKey")
		if sk then keys[sk] = true end
	end
	return keys
end

local function getWallArchKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallArchKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getDoorKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local dk = child:GetAttribute("DoorKey")
		if dk then keys[dk] = true end
	end
	return keys
end

-- Convert local studs position to world position.
-- Position is computed via the stable RestCFrame approach (same as the save
-- system) so the local offset captured by the WeldConstraint is always the
-- same regardless of current wave-induced tilt. Returns the restYaw for
-- rotating placed beams/walls/doors to face raft-forward.
local function localToWorld(raft, studX, studZ)
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX, 0, studZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return (primaryCF * CFrame.new(localOffset)).Position, restYaw
end

local function weldToRaft(obj, raft)
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
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = obj
		weld.Part1 = raft.PrimaryPart
		weld.Parent = obj
		unanchorAndPin(obj)
	end
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
	if not tool then return end

	-- Anchor placement uses the Anchor_part tool (crafted at the
	-- workbench). Every other buildType is hammer-driven.
	local requiredTool = (buildType == "anchor") and "Anchor_part" or "Hammer"
	if tool.Name ~= requiredTool then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	if buildType == "anchor" then
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		local anchorTemplate = rs:FindFirstChild("Anchor_part")
			or rs:FindFirstChild("Anchor_part", true)
		if not anchorTemplate then return end

		-- Anchor_part's PrimaryPart sits 2 studs to the right of the
		-- visible centre (A-frame opening). PivotTo would park the
		-- body 2 studs past the grid cell, so shift the target 2
		-- studs left along its own X axis to compensate.
		local ANCHOR_PIVOT_COMPENSATION = CFrame.new(-2, 0, 0)

		local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raft.PrimaryPart.CFrame
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
		local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft) * ANCHOR_PIVOT_COMPENSATION

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		local newAnchor = anchorTemplate:Clone()
		-- Tag it with the same grid coords as a raft tile so existing
		-- offset / occupancy / save logic counts the cell as filled and
		-- nothing else can be dropped on top of it.
		newAnchor:SetAttribute("GridX", gx)
		newAnchor:SetAttribute("GridZ", gz)
		newAnchor:SetAttribute("BuildType", "raft")
		newAnchor:SetAttribute("IsAnchor", true)

		if newAnchor:IsA("Model") then
			if not newAnchor.PrimaryPart then
				local p = newAnchor:FindFirstChildWhichIsA("BasePart", true)
				if p then newAnchor.PrimaryPart = p end
			end
			-- Anchor_part needs three pre-PivotTo compensations:
			--   * 90° Y rotation — template logs run on Z, raft on X.
			--   * XZ centred on BB middle — authored pivot is off-side.
			--   * 2·GRID_SIZE shift along the pivot's local Z — the
			--     anchor's hollow A-frame middle pushes the body away
			--     from the grid cell otherwise.
			local authored = newAnchor:GetPivot()
			local bbCF = newAnchor:GetBoundingBox()
			local pivotPos = Vector3.new(
				bbCF.Position.X,
				authored.Position.Y,
				bbCF.Position.Z
			)
			newAnchor.WorldPivot =
				CFrame.new(pivotPos)
				* CFrame.Angles(0, math.rad(90), 0)
				* CFrame.new(0, 0, 2 * GRID_SIZE)
			newAnchor:PivotTo(worldCF)
		elseif newAnchor:IsA("BasePart") then
			newAnchor.CFrame = worldCF
		end
		placeWithVelocityPreserved(raft, function()
			newAnchor.Parent = raft
			-- Weld the frame/sticks to the raft, but leave the inner
			-- `anchor` submodel (the Union that hangs from the rope)
			-- completely free — no welds, unanchored — so the
			-- RopeConstraint can actually swing it when the player
			-- lowers the rope with the E prompt.
			local hanging = newAnchor:FindFirstChild("anchor")
			for _, desc in newAnchor:GetDescendants() do
				if desc:IsA("BasePart") then
					if hanging and desc:IsDescendantOf(hanging) then
						desc.Anchored = false
						pcall(function() desc:SetNetworkOwner(nil) end)
					else
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = desc
						weld.Part1 = raft.PrimaryPart
						weld.Parent = desc
						desc.Anchored = false
						pcall(function() desc:SetNetworkOwner(nil) end)
					end
				end
			end
		end)

		-- Consume the Anchor_part tool — one craft = one placement.
		tool:Destroy()

		if _G.SendInventory then _G.SendInventory(player) end
		return

	elseif buildType == "raft" then
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
		local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)

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

		local spanKey = makeSpanKey(cx1, cz1, cx2, cz2)
		if getWallSpanKeys(raft)[spanKey] then return end
		local wpk = makeWallPanelKey(cx1, cz1, cx2, cz2)

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
		newWall:SetAttribute("WallSpanKey", spanKey)
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
		placeWithVelocityPreserved(raft, function()
			newWall.Parent = raft
			weldToRaft(newWall, raft)
		end)

	elseif buildType == "wall_arch" then
		if not wallArchTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < WALL_ARCH_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		local beamKeys = getBeamKeys(raft)
		if not beamKeys[makeBeamKey(cx1, cz1)] or not beamKeys[makeBeamKey(cx2, cz2)] then return end

		local spanKey = makeSpanKey(cx1, cz1, cx2, cz2)
		if getWallSpanKeys(raft)[spanKey] then return end
		local wak = makeWallArchKey(cx1, cz1, cx2, cz2)

		local offsets = getFloorOffsets(raft)
		local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
		local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
		local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
		local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = worldPos + Vector3.new(0, ARCH_HEIGHT / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - WALL_ARCH_COST

		local newArch = wallArchTemplate:Clone()
		newArch:SetAttribute("BuildType", "wall_arch")
		newArch:SetAttribute("WallArchKey", wak)
		newArch:SetAttribute("WallSpanKey", spanKey)
		newArch:SetAttribute("BeamCX1", cx1)
		newArch:SetAttribute("BeamCZ1", cz1)
		newArch:SetAttribute("BeamCX2", cx2)
		newArch:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local archCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newArch:IsA("Model") then
			newArch:PivotTo(archCF)
		else
			newArch.CFrame = archCF
		end
		placeWithVelocityPreserved(raft, function()
			newArch.Parent = raft
			weldToRaft(newArch, raft)
		end)

	elseif buildType == "door" then
		if not doorTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < DOOR_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		-- A door requires a wall_arch on the same span and no existing door.
		local wak = makeWallArchKey(cx1, cz1, cx2, cz2)
		if not getWallArchKeys(raft)[wak] then return end
		local dk = makeDoorKey(cx1, cz1, cx2, cz2)
		if getDoorKeys(raft)[dk] then return end

		local offsets = getFloorOffsets(raft)
		local inset1X, inset1Z = computeBeamInset(offsets, cx1, cz1)
		local inset2X, inset2Z = computeBeamInset(offsets, cx2, cz2)
		local midStudX = ((cx1 * GRID_SIZE + inset1X) + (cx2 * GRID_SIZE + inset2X)) / 2 + BEAM_X_OFFSET
		local midStudZ = ((cz1 * GRID_SIZE + inset1Z) + (cz2 * GRID_SIZE + inset2Z)) / 2
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = worldPos + Vector3.new(0, DOOR_HEIGHT / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - DOOR_COST

		local newDoor = doorTemplate:Clone()
		newDoor:SetAttribute("BuildType", "door")
		newDoor:SetAttribute("DoorKey", dk)
		newDoor:SetAttribute("BeamCX1", cx1)
		newDoor:SetAttribute("BeamCZ1", cz1)
		newDoor:SetAttribute("BeamCX2", cx2)
		newDoor:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local doorCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newDoor:IsA("Model") then
			newDoor:PivotTo(doorCF)
		else
			newDoor.CFrame = doorCF
		end
		placeWithVelocityPreserved(raft, function()
			newDoor.Parent = raft
			-- Doors need a Motor6D-based weld so the panel can swing without
			-- fighting the raft's rigid weld network. Fall back to the plain
			-- weld routine if the DoorController hasn't loaded yet.
			if _G.SetupDoor then
				_G.SetupDoor(newDoor, raft)
			else
				weldToRaft(newDoor, raft)
			end
		end)
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
