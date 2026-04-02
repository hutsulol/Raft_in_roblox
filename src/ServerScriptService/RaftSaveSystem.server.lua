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
		raftPosition = serializeCFrame(raftCF),
		floors = {},
		walls = {},
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

		elseif buildType == "wall" then
			local gx = child:GetAttribute("GridX")
			local gz = child:GetAttribute("GridZ")
			local wk = child:GetAttribute("WallKey")
			if gx and gz and wk then
				-- Parse side from WallKey "gx_gz_side"
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

	print("[RaftSave] Collected: " .. #data.floors .. " floors, " .. #data.walls .. " walls, " .. #data.objects .. " objects")
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

	local raftData = collectRaftData(player)
	local invData = collectInventoryData(player)
	local toolData = collectToolData(player)

	print("[RaftSave] Collecting data for " .. player.Name .. " - raft: " .. tostring(raftData ~= nil) .. ", tools: " .. #toolData)

	if not raftData and (not invData or next(invData) == nil) and #toolData == 0 then
		print("[RaftSave] No data to save for " .. player.Name)
		return
	end

	local saveData = {
		inventory = invData,
		tools = toolData,
		raft = raftData,
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

	-- Restore raft world position
	if raftData.raftPosition then
		local savedCF = deserializeCFrame(raftData.raftPosition)
		raft:PivotTo(savedCF)
		print("[RaftSave] Restored raft position to " .. tostring(savedCF.Position))
	end

	local raftCF = raft.PrimaryPart.CFrame

	-- Templates
	local floorTemplate = rs:FindFirstChild("Raft_part")
	local wallTemplate = rs:FindFirstChild("Wall") or rs:FindFirstChild("wall")

	-- Determine grid size from template
	local GRID_SIZE = 6
	if floorTemplate then
		if floorTemplate:IsA("Model") then
			local _, size = floorTemplate:GetBoundingBox()
			GRID_SIZE = math.max(size.X, size.Z)
		elseif floorTemplate:IsA("BasePart") then
			GRID_SIZE = math.max(floorTemplate.Size.X, floorTemplate.Size.Z)
		end
	end

	-- Place floors (skip origin 0,0 which already exists)
	if floorTemplate and raftData.floors then
		for _, floor in raftData.floors do
			if not (floor.gx == 0 and floor.gz == 0) then
				local localOffset = Vector3.new(floor.gx * GRID_SIZE, 0, floor.gz * GRID_SIZE)
				local worldCF = raftCF * CFrame.new(localOffset)

				local clone = floorTemplate:Clone()
				if clone:IsA("Model") then
					clone:PivotTo(worldCF)
				else
					clone.CFrame = worldCF
				end
				clone:SetAttribute("GridX", floor.gx)
				clone:SetAttribute("GridZ", floor.gz)
				clone:SetAttribute("BuildType", "raft")
				clone.Parent = raft

				-- Weld to raft
				if clone:IsA("Model") then
					for _, part in clone:GetDescendants() do
						if part:IsA("BasePart") then
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = raft.PrimaryPart
							weld.Part1 = part
							weld.Parent = part
						end
					end
				else
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = raft.PrimaryPart
					weld.Part1 = clone
					weld.Parent = clone
				end
			end
		end
	end

	-- Place walls
	if wallTemplate and raftData.walls then
		-- Compute wall CFrame using same logic as BuildingSystem
		local _, yaw, _ = raftCF:ToEulerAnglesYXZ()
		local flatCF = CFrame.new(raftCF.Position) * CFrame.Angles(0, yaw, 0)

		local WALL_HEIGHT = 6
		if wallTemplate:IsA("Model") then
			local _, ws = wallTemplate:GetBoundingBox()
			WALL_HEIGHT = ws.Y
		elseif wallTemplate:IsA("BasePart") then
			WALL_HEIGHT = wallTemplate.Size.Y
		end

		for _, wall in raftData.walls do
			local half = GRID_SIZE / 2
			local center = raftCF * CFrame.new(Vector3.new(wall.gx * GRID_SIZE, 0, wall.gz * GRID_SIZE))
			local wCF

			if wall.side == 0 then
				wCF = center * CFrame.new(0, WALL_HEIGHT / 2, -half)
			elseif wall.side == 1 then
				wCF = center * CFrame.new(0, WALL_HEIGHT / 2, half)
			elseif wall.side == 2 then
				wCF = center * CFrame.new(-half, WALL_HEIGHT / 2, 0) * CFrame.Angles(0, math.rad(90), 0)
			elseif wall.side == 3 then
				wCF = center * CFrame.new(half, WALL_HEIGHT / 2, 0) * CFrame.Angles(0, math.rad(90), 0)
			end

			if wCF then
				local clone = wallTemplate:Clone()
				local wallKey = wall.gx .. "_" .. wall.gz .. "_" .. wall.side
				clone:SetAttribute("WallKey", wallKey)
				clone:SetAttribute("BuildType", "wall")
				clone:SetAttribute("GridX", wall.gx)
				clone:SetAttribute("GridZ", wall.gz)

				if clone:IsA("Model") then
					clone:PivotTo(wCF)
				else
					clone.CFrame = wCF
				end
				clone.Parent = raft

				if clone:IsA("Model") then
					for _, part in clone:GetDescendants() do
						if part:IsA("BasePart") then
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = raft.PrimaryPart
							weld.Part1 = part
							weld.Parent = part
						end
					end
				else
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = raft.PrimaryPart
					weld.Part1 = clone
					weld.Parent = clone
				end
			end
		end
	end

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

				-- Weld all parts
				if clone:IsA("Model") then
					for _, part in clone:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = false
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = raft.PrimaryPart
							weld.Part1 = part
							weld.Parent = part
						end
					end
				else
					clone.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = raft.PrimaryPart
					weld.Part1 = clone
					weld.Parent = clone
				end
			end
		end
	end

	print("[RaftSave] Rebuilt raft for " .. player.Name)
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

-- ─── On player join: check teleport data for load flag ───
Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if teleportData and teleportData.loadSave then
		print("[RaftSave] Player " .. player.Name .. " loading save...")

		-- Load save data immediately (before character spawns)
		local saveData = loadPlayerData(player)
		if saveData then
			-- Rebuild raft at saved position BEFORE character spawns
			rebuildRaft(player, saveData)

			-- Wait for character to spawn, then move to raft and restore inventory/tools
			local char = player.Character or player.CharacterAdded:Wait()
			local hrp = char:WaitForChild("HumanoidRootPart", 10)

			local raft = workspace:FindFirstChild("Raft")
			if hrp and raft and raft.PrimaryPart then
				hrp.CFrame = raft.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
				print("[RaftSave] Moved " .. player.Name .. " to saved raft")
			end

			-- Wait a moment for _G.GetInventory to be ready
			task.wait(1)
			restoreInventory(player, saveData)
			restoreTools(player, saveData)
		end
	end
end)

-- ─── Save on player leaving ───
Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
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
