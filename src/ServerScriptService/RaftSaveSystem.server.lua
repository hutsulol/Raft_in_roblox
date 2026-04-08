-- RaftSaveSystem.server.lua
-- Saves and loads raft layout + inventory using DataStoreService.
-- Place in ServerScriptService of the OCEAN sub-place.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local raftStore = nil
local storeOk, storeErr = pcall(function()
	raftStore = DataStoreService:GetDataStore("RaftSaveData_v1")
end)
if not storeOk then
	warn("[RaftSave] Failed to get DataStore: " .. tostring(storeErr))
else
	print("[RaftSave] DataStore connected OK")
end

local AUTOSAVE_INTERVAL = 120 -- seconds

-- Keep the map's original raft transform so a "new game" (or missing save)
-- can always start from the intended spawn position.
local INITIAL_RAFT_CFRAME = nil
do
	local raft = workspace:FindFirstChild("Raft")
	if raft and raft.PrimaryPart then
		INITIAL_RAFT_CFRAME = raft.PrimaryPart.CFrame
	end
end

-- ─── Slot layout sync: client sends slot positions to server ───
local slotLayoutEvent = Instance.new("RemoteEvent")
slotLayoutEvent.Name = "SlotLayoutSync"
slotLayoutEvent.Parent = ReplicatedStorage

local cachedSlotLayouts = {} -- [player] = slotData table

slotLayoutEvent.OnServerEvent:Connect(function(player, slotLayout)
	if typeof(slotLayout) == "table" then
		cachedSlotLayouts[player] = slotLayout
	end
end)

-- ─── CFrame serialization ───
local function serializeCFrame(cf)
	return {cf:GetComponents()} -- 12 numbers
end

local function deserializeCFrame(t)
	if not t or #t < 12 then return CFrame.new() end
	return CFrame.new(unpack(t))
end

-- ─── Collect raft data ───
local function collectRaftData(player)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then
		warn("[RaftSave] No Raft model in workspace")
		return nil
	end
	if not raft.PrimaryPart then
		warn("[RaftSave] Raft has no PrimaryPart")
		return nil
	end
	print("[RaftSave] Found Raft with " .. #raft:GetChildren() .. " children")

	local raftCF = raft.PrimaryPart.CFrame
	local data = {
		floors = {},
		walls = {},
		beams = {},
		wallPanels = {},
		wallArches = {},
		doors = {},
		objects = {},
	}

	for _, child in raft:GetChildren() do
		local buildType = child:GetAttribute("BuildType")

		if buildType == "raft" then
			local gx = child:GetAttribute("GridX")
			local gz = child:GetAttribute("GridZ")
			if gx and gz then
				table.insert(data.floors, {gx = gx, gz = gz})
			end

		elseif buildType == "beam" then
			local cx = child:GetAttribute("CornerX")
			local cz = child:GetAttribute("CornerZ")
			if cx and cz then
				table.insert(data.beams, {cx = cx, cz = cz})
			end

		elseif buildType == "wall_panel" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.wallPanels, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
			end

		elseif buildType == "wall_arch" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.wallArches, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
			end

		elseif buildType == "door_wood" then
			local cx1 = child:GetAttribute("BeamCX1")
			local cz1 = child:GetAttribute("BeamCZ1")
			local cx2 = child:GetAttribute("BeamCX2")
			local cz2 = child:GetAttribute("BeamCZ2")
			if cx1 and cz1 and cx2 and cz2 then
				table.insert(data.doors, {cx1 = cx1, cz1 = cz1, cx2 = cx2, cz2 = cz2})
			end

		elseif buildType == "wall" then
			local gx = child:GetAttribute("GridX")
			local gz = child:GetAttribute("GridZ")
			local wk = child:GetAttribute("WallKey")
			if gx and gz and wk then
				local side = tonumber(wk:match("_(%d+)$"))
				if side then
					table.insert(data.walls, {gx = gx, gz = gz, side = side})
				end
			end

		elseif child:IsA("Model") or child:IsA("BasePart") then
			-- Placed objects (Furnace, WorkBench, Bed, Garden, Purifier/Destitalor, bush)
			local name = child.Name
			local knownObjects = {
				Furnace = true, WorkBench = true, Bed = true,
				Garden = true, Destitalor = true, Purifier = true, bush = true,
			}
			-- Also match purifier variants
			if knownObjects[name] or name:find("Destitalor") or name:find("Garden") then
				local objCF
				if child:IsA("Model") then
					objCF = child:GetBoundingBox()
				else
					objCF = child.CFrame
				end
				local localCF = raftCF:ToObjectSpace(objCF)

				local objData = {
					name = name,
					cf = serializeCFrame(localCF),
				}

				-- Save garden state
				if child:GetAttribute("IsGarden") then
					objData.isGarden = true
					objData.isWatered = child:GetAttribute("IsWatered") or false
				end

				-- Save purifier state
				if child:GetAttribute("WaterType") then
					objData.waterLevel = child:GetAttribute("WaterLevel") or 0
					objData.waterType = child:GetAttribute("WaterType") or "none"
				end

				table.insert(data.objects, objData)
			end
		end
	end

	print("[RaftSave] Collected: " .. #data.floors .. " floors, " .. #data.beams .. " beams, " .. #data.wallPanels .. " wallPanels, " .. #data.wallArches .. " wallArches, " .. #data.doors .. " doors, " .. #data.walls .. " walls(legacy), " .. #data.objects .. " objects")
	return data
end

-- ─── Collect inventory data ───
local function collectInventoryData(player)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return {} end

	local data = {}
	for key, value in inv do
		if typeof(value) == "number" then
			data[key] = value
		end
	end
	return data
end

-- ─── Collect tools from Backpack + Character ───
local function collectToolData(player)
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character

	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") then
				table.insert(tools, item.Name)
			end
		end
	end
	if char then
		for _, item in char:GetChildren() do
			if item:IsA("Tool") then
				table.insert(tools, item.Name)
			end
		end
	end

	print("[RaftSave] Collected " .. #tools .. " tools: " .. table.concat(tools, ", "))
	return tools
end

-- ─── Save player data ───
local function savePlayerData(player)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot save for " .. player.Name)
		return
	end

	-- Only the raft owner gets raft data saved (prevents duplication exploit)
	local isOwner = playerIsRaftOwner[player]
	if isOwner == nil then isOwner = true end -- fallback for direct joins

	local raftData = nil
	if isOwner then
		raftData = collectRaftData(player)
	else
		print("[RaftSave] Skipping raft save for " .. player.Name .. " (not owner, clearing old raft data)")
	end

	local invData = collectInventoryData(player)
	local toolData = collectToolData(player)

	print("[RaftSave] Collecting data for " .. player.Name .. " - raft: " .. tostring(raftData ~= nil) .. " (owner=" .. tostring(isOwner) .. "), tools: " .. #toolData)

	-- For owners: skip if there's truly nothing to save
	-- For non-owners: ALWAYS save to overwrite any old raft data they might have
	if isOwner and not raftData and (not invData or next(invData) == nil) and #toolData == 0 then
		print("[RaftSave] No data to save for " .. player.Name)
		return
	end

	local saveData = {
		inventory = invData,
		tools = toolData,
		slotLayout = cachedSlotLayouts[player] or {},
		raft = raftData, -- nil for non-owners, clears any previously saved raft
		savedAt = os.time(),
	}

	local key = "player_" .. player.UserId
	local success, err = pcall(function()
		raftStore:SetAsync(key, saveData)
	end)

	if success then
		print("[RaftSave] Saved data for " .. player.Name)
	else
		warn("[RaftSave] Failed to save for " .. player.Name .. ": " .. tostring(err))
	end
end

-- ─── Load player data ───
local function loadPlayerData(player)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot load for " .. player.Name)
		return nil
	end
	local key = "player_" .. player.UserId
	local success, data = pcall(function()
		return raftStore:GetAsync(key)
	end)

	if success and data then
		print("[RaftSave] Loaded save data for " .. player.Name .. " (saved at " .. tostring(data.savedAt) .. ")")
		return data
	elseif not success then
		warn("[RaftSave] DataStore read failed for " .. player.Name .. ": " .. tostring(data))
	else
		print("[RaftSave] No save data found for " .. player.Name)
	end
	return nil
end

-- ─── Rebuild raft from saved data ───
local function rebuildRaft(player, saveData)
	if not saveData or not saveData.raft then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	local rs = ReplicatedStorage
	local raftData = saveData.raft

	-- Always start from the map's initial raft position, even when loading a save.
	-- We persist raft layout and objects, but not world drift position.
	if INITIAL_RAFT_CFRAME then
		raft:PivotTo(INITIAL_RAFT_CFRAME)
		print("[RaftSave] Reset raft position to initial map spawn before rebuild")
	elseif raftData.raftPosition then
		-- Backward compatibility if initial CFrame wasn't captured for any reason.
		local savedCF = deserializeCFrame(raftData.raftPosition)
		raft:PivotTo(savedCF)
		print("[RaftSave] Restored raft position from legacy save to " .. tostring(savedCF.Position))
	end

	local raftCF = raft.PrimaryPart.CFrame
	-- Store RestCFrame and RestYaw for BuildingSystem (in case BoatForwardMovement hasn't set them yet)
	if not raft.PrimaryPart:GetAttribute("RestCFrame") then
		raft.PrimaryPart:SetAttribute("RestCFrame", raftCF)
	end
	if not raft.PrimaryPart:GetAttribute("RestYaw") then
		local _, iy, _ = raftCF:ToEulerAnglesYXZ()
		raft.PrimaryPart:SetAttribute("RestYaw", iy)
	end
	-- Use RestCFrame for stable grid offsets (same approach as BuildingSystem)
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raftCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)

	-- Templates
	local floorTemplate = rs:FindFirstChild("Raft_part")
	local wallTemplate = rs:FindFirstChild("Wood_wall")
	local beamTemplate = rs:FindFirstChild("beam")
	local wallPanelTemplate = rs:FindFirstChild("wall_model_wood")
	local wallArchTemplate = rs:FindFirstChild("wall_model_wood_arch")
	local doorWoodTemplate = rs:FindFirstChild("Door_Wood")

	-- Determine grid size and floor height from template
	local GRID_SIZE = 6
	local FLOOR_HEIGHT = 0
	if floorTemplate then
		if floorTemplate:IsA("Model") then
			local size = floorTemplate:GetExtentsSize()
			GRID_SIZE = math.max(size.X, size.Z)
			FLOOR_HEIGHT = size.Y
		elseif floorTemplate:IsA("BasePart") then
			GRID_SIZE = math.max(floorTemplate.Size.X, floorTemplate.Size.Z)
			FLOOR_HEIGHT = floorTemplate.Size.Y
		end
	end

	-- Beam measurements
	local BEAM_HEIGHT = 0
	local BEAM_INSET = 0
	if beamTemplate then
		if beamTemplate:IsA("Model") then
			local size = beamTemplate:GetExtentsSize()
			BEAM_HEIGHT = size.Y
			BEAM_INSET = math.max(size.X, size.Z) / 2
		elseif beamTemplate:IsA("BasePart") then
			BEAM_HEIGHT = beamTemplate.Size.Y
			BEAM_INSET = math.max(beamTemplate.Size.X, beamTemplate.Size.Z) / 2
		end
	end

	-- Wall panel measurements
	local PANEL_HEIGHT = 0
	if wallPanelTemplate then
		if wallPanelTemplate:IsA("Model") then
			PANEL_HEIGHT = wallPanelTemplate:GetExtentsSize().Y
		elseif wallPanelTemplate:IsA("BasePart") then
			PANEL_HEIGHT = wallPanelTemplate.Size.Y
		end
	end

	local ARCH_HEIGHT = 0
	if wallArchTemplate then
		if wallArchTemplate:IsA("Model") then
			ARCH_HEIGHT = wallArchTemplate:GetExtentsSize().Y
		elseif wallArchTemplate:IsA("BasePart") then
			ARCH_HEIGHT = wallArchTemplate.Size.Y
		end
	end

	local DOOR_HEIGHT = 0
	if doorWoodTemplate then
		if doorWoodTemplate:IsA("Model") then
			DOOR_HEIGHT = doorWoodTemplate:GetExtentsSize().Y
		elseif doorWoodTemplate:IsA("BasePart") then
			DOOR_HEIGHT = doorWoodTemplate.Size.Y
		end
	end

	-- Floor offsets for beam inset calculation
	local function isFloorOccupied(gx, gz)
		if gx == 0 and gz == 0 then return true end
		if raftData.floors then
			for _, f in raftData.floors do
				if f.gx == gx and f.gz == gz then return true end
			end
		end
		return false
	end

	local function computeBeamInset(cx, cz)
		local insetX, insetZ = 0, 0
		local hasPlusX = isFloorOccupied(cx + 0.5, cz - 0.5) or isFloorOccupied(cx + 0.5, cz + 0.5)
		local hasMinusX = isFloorOccupied(cx - 0.5, cz - 0.5) or isFloorOccupied(cx - 0.5, cz + 0.5)
		if hasMinusX and not hasPlusX then insetX = -BEAM_INSET
		elseif hasPlusX and not hasMinusX then insetX = BEAM_INSET end

		local hasPlusZ = isFloorOccupied(cx - 0.5, cz + 0.5) or isFloorOccupied(cx + 0.5, cz + 0.5)
		local hasMinusZ = isFloorOccupied(cx - 0.5, cz - 0.5) or isFloorOccupied(cx + 0.5, cz - 0.5)
		if hasMinusZ and not hasPlusZ then insetZ = -BEAM_INSET
		elseif hasPlusZ and not hasMinusZ then insetZ = BEAM_INSET end

		return insetX, insetZ
	end

	local function localToWorldPos(studX, studZ)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX, 0, studZ))
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		return (raftCF * CFrame.new(localOffset)).Position
	end

	local function prepareDoorForAnimation(model)
		if not model or not model:IsA("Model") then return end
		local hinge = model:FindFirstChild("Hinge", true)
		if not hinge or not hinge:IsA("BasePart") then return end

		for _, desc in model:GetDescendants() do
			if desc:IsA("WeldConstraint") and (desc.Part0 == hinge or desc.Part1 == hinge) then
				desc:Destroy()
			elseif desc:IsA("JointInstance") and (desc.Part0 == hinge or desc.Part1 == hinge) then
				desc:Destroy()
			end
		end
		hinge.Anchored = false
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

	local function weldAndUnanchor(clone)
		local skipHinge = clone:GetAttribute("BuildType") == "door_wood"
		if clone:IsA("Model") then
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") then
					if not (skipHinge and part.Name == "Hinge") then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = raft.PrimaryPart
						weld.Part1 = part
						weld.Parent = part
					end
				end
			end
			for _, part in clone:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored = false end
			end
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = raft.PrimaryPart
			weld.Part1 = clone
			weld.Parent = clone
			clone.Anchored = false
		end
	end

	-- Place floors (skip origin 0,0 which already exists)
	if floorTemplate and raftData.floors then
		for _, floor in raftData.floors do
			if not (floor.gx == 0 and floor.gz == 0) then
				local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(floor.gx * GRID_SIZE, 0, floor.gz * GRID_SIZE))
				local localOffset = restCF:VectorToObjectSpace(worldOffset)
				local worldCF = raftCF * CFrame.new(localOffset)

				local clone = floorTemplate:Clone()
				if clone:IsA("Model") then clone:PivotTo(worldCF) else clone.CFrame = worldCF end
				clone:SetAttribute("GridX", floor.gx)
				clone:SetAttribute("GridZ", floor.gz)
				clone:SetAttribute("BuildType", "raft")
				clone.Parent = raft
				weldAndUnanchor(clone)
			end
		end
	end

	-- Place beams
	if beamTemplate and raftData.beams then
		for _, beam in raftData.beams do
			local insetX, insetZ = computeBeamInset(beam.cx, beam.cz)
			local studX = beam.cx * GRID_SIZE + insetX + 1
			local studZ = beam.cz * GRID_SIZE + insetZ
			local worldPos = localToWorldPos(studX, studZ)
			worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT / 2, 0)

			local bCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)
			local clone = beamTemplate:Clone()
			clone:SetAttribute("BuildType", "beam")
			clone:SetAttribute("BeamKey", string.format("%.1f_%.1f", beam.cx, beam.cz))
			clone:SetAttribute("CornerX", beam.cx)
			clone:SetAttribute("CornerZ", beam.cz)
			if clone:IsA("Model") then clone:PivotTo(bCF) else clone.CFrame = bCF end
			clone.Parent = raft
			weldAndUnanchor(clone)
		end
	end

	-- Place wall panels
	if wallPanelTemplate and raftData.wallPanels then
		for _, wp in raftData.wallPanels do
			local inset1X, inset1Z = computeBeamInset(wp.cx1, wp.cz1)
			local inset2X, inset2Z = computeBeamInset(wp.cx2, wp.cz2)
			local midStudX = ((wp.cx1 * GRID_SIZE + inset1X) + (wp.cx2 * GRID_SIZE + inset2X)) / 2 + 1
			local midStudZ = ((wp.cz1 * GRID_SIZE + inset1Z) + (wp.cz2 * GRID_SIZE + inset2Z)) / 2
			local worldPos = localToWorldPos(midStudX, midStudZ)
			worldPos = worldPos + Vector3.new(0, PANEL_HEIGHT / 2, 0)

			local sideAngle = (wp.cx1 == wp.cx2) and math.rad(90) or 0
			local wCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

			local clone = wallPanelTemplate:Clone()
			local wpk = string.format("wp_%.1f_%.1f_%.1f_%.1f",
				math.min(wp.cx1, wp.cx2), math.min(wp.cz1, wp.cz2),
				math.max(wp.cx1, wp.cx2), math.max(wp.cz1, wp.cz2))
			clone:SetAttribute("BuildType", "wall_panel")
			clone:SetAttribute("WallPanelKey", wpk)
			clone:SetAttribute("BeamCX1", wp.cx1)
			clone:SetAttribute("BeamCZ1", wp.cz1)
			clone:SetAttribute("BeamCX2", wp.cx2)
			clone:SetAttribute("BeamCZ2", wp.cz2)
			if clone:IsA("Model") then clone:PivotTo(wCF) else clone.CFrame = wCF end
			if buildType == "door_wood" then
				prepareDoorForAnimation(clone)
			end
			clone.Parent = raft
			weldAndUnanchor(clone)
			if buildType == "door_wood" then
				task.defer(function()
					if clone.Parent then
						prepareDoorForAnimation(clone)
					end
				end)
			end
		end
	end

	-- Place objects
	local function placeWallLike(template, buildType, keyName, list, elementHeight)
		if not template or not list then return end
		for _, wp in list do
			local inset1X, inset1Z = computeBeamInset(wp.cx1, wp.cz1)
			local inset2X, inset2Z = computeBeamInset(wp.cx2, wp.cz2)
			local midStudX = ((wp.cx1 * GRID_SIZE + inset1X) + (wp.cx2 * GRID_SIZE + inset2X)) / 2 + 1
			local midStudZ = ((wp.cz1 * GRID_SIZE + inset1Z) + (wp.cz2 * GRID_SIZE + inset2Z)) / 2
			local worldPos = localToWorldPos(midStudX, midStudZ)
			worldPos = worldPos + Vector3.new(0, elementHeight / 2, 0)

			local sideAngle = (wp.cx1 == wp.cx2) and math.rad(90) or 0
			local wCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)

			local clone = template:Clone()
			local wpk = string.format("wp_%.1f_%.1f_%.1f_%.1f",
				math.min(wp.cx1, wp.cx2), math.min(wp.cz1, wp.cz2),
				math.max(wp.cx1, wp.cx2), math.max(wp.cz1, wp.cz2))
			clone:SetAttribute("BuildType", buildType)
			clone:SetAttribute(keyName, wpk)
			clone:SetAttribute("BeamCX1", wp.cx1)
			clone:SetAttribute("BeamCZ1", wp.cz1)
			clone:SetAttribute("BeamCX2", wp.cx2)
			clone:SetAttribute("BeamCZ2", wp.cz2)
			if clone:IsA("Model") then clone:PivotTo(wCF) else clone.CFrame = wCF end
			if buildType == "door_wood" then
				prepareDoorForAnimation(clone)
			end
			clone.Parent = raft
			weldAndUnanchor(clone)
			if buildType == "door_wood" then
				task.defer(function()
					if clone.Parent then
						prepareDoorForAnimation(clone)
					end
				end)
			end
		end
	end

	placeWallLike(wallArchTemplate, "wall_arch", "WallArchKey", raftData.wallArches, ARCH_HEIGHT)
	placeWallLike(doorWoodTemplate, "door_wood", "DoorKey", raftData.doors, DOOR_HEIGHT)

	-- Place objects
	if raftData.objects then
		for _, obj in raftData.objects do
			local template = rs:FindFirstChild(obj.name)
			if not template then
				-- Try common name variants
				if obj.name == "Purifier" then template = rs:FindFirstChild("Destitalor") end
			end
			if template then
				local clone = template:Clone()
				local localCF = deserializeCFrame(obj.cf)
				local worldCF = raftCF * localCF

				if clone:IsA("Model") then
					clone:PivotTo(worldCF)
				else
					clone.CFrame = worldCF
				end

				-- Restore attributes
				if obj.isGarden then
					clone:SetAttribute("IsGarden", true)
					clone:SetAttribute("IsWatered", obj.isWatered or false)
				end

				if obj.waterLevel then
					clone:SetAttribute("WaterLevel", obj.waterLevel)
					clone:SetAttribute("WaterType", obj.waterType or "none")
				end

				clone.Parent = raft
				weldAndUnanchor(clone)
			end
		end
	end

	print("[RaftSave] Rebuilt raft for " .. player.Name)
end

local function resetRaftToInitialPosition()
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart or not INITIAL_RAFT_CFRAME then return end

	raft:PivotTo(INITIAL_RAFT_CFRAME)
	raft.PrimaryPart:SetAttribute("RestCFrame", INITIAL_RAFT_CFRAME)
	local _, iy, _ = INITIAL_RAFT_CFRAME:ToEulerAnglesYXZ()
	raft.PrimaryPart:SetAttribute("RestYaw", iy)
	print("[RaftSave] Reset raft to initial map position")
end

-- ─── Restore inventory ───
local function restoreInventory(player, saveData)
	if not saveData or not saveData.inventory then return end

	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return end

	for key, value in saveData.inventory do
		if typeof(value) == "number" then
			inv[key] = value
		end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	print("[RaftSave] Restored inventory for " .. player.Name)
end

-- ─── Restore tools ───
local function restoreTools(player, saveData)
	if not saveData or not saveData.tools then return end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	-- Tools cloned from ReplicatedStorage templates
	local cloneableTools = {
		["Pick-Axe"] = true, ["Hammer"] = true, ["Axe"] = true,
		["Hook"] = true, ["Machete"] = true, ["Wooden_Spear"] = true,
		["Cup"] = true, ["Destitalor"] = true, ["Wood_Knife"] = true,
	}

	-- Placeholder tools (placement items) — create a simple Tool with transparent Handle
	local placeholderTools = {
		["WorkBench"] = true, ["Garden"] = true, ["Furnace"] = true,
		["Bed"] = true, ["bush"] = true,
	}

	for _, toolName in saveData.tools do
		if cloneableTools[toolName] then
			local template = ReplicatedStorage:FindFirstChild(toolName)
			if template then
				local clone = template:Clone()
				clone.Parent = backpack
				print("[RaftSave] Restored tool: " .. toolName)
			else
				warn("[RaftSave] Tool template not found: " .. toolName)
			end
		elseif placeholderTools[toolName] then
			-- Recreate placeholder placement tool
			local tool = Instance.new("Tool")
			tool.Name = toolName
			tool.CanBeDropped = false
			tool.RequiresHandle = true
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.CanCollide = false
			handle.Parent = tool
			tool.Parent = backpack
			print("[RaftSave] Restored placeholder tool: " .. toolName)
		else
			-- Unknown tool — try to clone from ReplicatedStorage anyway
			local template = ReplicatedStorage:FindFirstChild(toolName)
			if template then
				local clone = template:Clone()
				clone.Parent = backpack
				print("[RaftSave] Restored unknown tool: " .. toolName)
			else
				warn("[RaftSave] Could not restore tool: " .. toolName)
			end
		end
	end

	print("[RaftSave] Restored " .. #saveData.tools .. " tools for " .. player.Name)
end

-- Track whether the raft has already been rebuilt from a save (for group loads)
local raftRebuiltFromSave = false

-- Per-player ownership tracking (only the owner gets raft data saved)
local playerIsRaftOwner = {} -- [player] = true/false

-- ─── Load save data by UserId key ───
local function loadPlayerDataByUserId(userId)
	if not raftStore then
		warn("[RaftSave] No DataStore, cannot load for userId " .. tostring(userId))
		return nil
	end
	local key = "player_" .. userId
	local success, data = pcall(function()
		return raftStore:GetAsync(key)
	end)

	if success and data then
		print("[RaftSave] Loaded save data for userId " .. tostring(userId))
		return data
	elseif not success then
		warn("[RaftSave] DataStore read failed for userId " .. tostring(userId) .. ": " .. tostring(data))
	end
	return nil
end

-- ─── On player join: check teleport data for load flag ───
Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	-- Determine if this player is the raft owner
	if teleportData and teleportData.raftOwnerId then
		playerIsRaftOwner[player] = (teleportData.raftOwnerId == player.UserId)
		print("[RaftSave] Player " .. player.Name .. " isRaftOwner: " .. tostring(playerIsRaftOwner[player]) .. " (ownerId=" .. tostring(teleportData.raftOwnerId) .. ")")
	else
		-- No teleport data (direct join or testing) — treat as owner
		playerIsRaftOwner[player] = true
	end

	if teleportData and teleportData.loadSave then
		-- Determine whose save to load
		local saveOwnerId = teleportData.saveOwnerId
		local isOwner = (not saveOwnerId) or (saveOwnerId == player.UserId)

		print("[RaftSave] Player " .. player.Name .. " loading save (owner: " .. tostring(saveOwnerId or player.UserId) .. ", isOwner: " .. tostring(isOwner) .. ")")

		-- Load save data (owner's save for group, or own save for solo)
		local saveData
		if saveOwnerId and saveOwnerId ~= player.UserId then
			saveData = loadPlayerDataByUserId(saveOwnerId)
		else
			saveData = loadPlayerData(player)
		end

		-- If save-loading was requested but no save exists, force "new game"
		-- spawn position instead of leaving the raft in a stale runtime state.
		if not saveData then
			resetRaftToInitialPosition()
		end

		-- Rebuild raft only once (the first player to join triggers it)
		if saveData and not raftRebuiltFromSave then
			raftRebuiltFromSave = true
			rebuildRaft(player, saveData)
		end

		-- Wait for character to spawn, then move to raft
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)

		local raft = workspace:FindFirstChild("Raft")
		if hrp and raft and raft.PrimaryPart then
			hrp.CFrame = raft.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
			print("[RaftSave] Moved " .. player.Name .. " to saved raft")
		end

		-- Restore inventory and tools only for the save owner (or solo player)
		if saveData and isOwner then
			task.wait(1)
			restoreInventory(player, saveData)
			restoreTools(player, saveData)

			-- Send saved slot layout to client
			if saveData.slotLayout and next(saveData.slotLayout) then
				task.wait(0.5)
				slotLayoutEvent:FireClient(player, "restore", saveData.slotLayout)
				print("[RaftSave] Sent slot layout to " .. player.Name)
			end
		end
	end
end)

-- ─── Save on player leaving ───
Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	cachedSlotLayouts[player] = nil
	playerIsRaftOwner[player] = nil
end)

-- ─── Autosave ───
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in Players:GetPlayers() do
			task.spawn(savePlayerData, player)
		end
	end
end)

-- ─── Save on server shutdown ───
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		savePlayerData(player)
	end
end)
