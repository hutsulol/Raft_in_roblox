-- FurnaceCraft.server.lua
-- Crafting, placement, ProximityPrompt, and smelting logic for the Furnace

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WORKBENCH_RANGE = 15
local SMELT_TIME = 20 -- seconds
local FURNACE_RANGE = 12
local FUEL_BURN_TIME = 5 -- seconds per wood
local FUEL_NEEDED = 4 -- 4 wood × 5s = 20s
local MAX_SLOT = 30 -- max items per furnace slot

-- ─── RemoteEvents ───
local craftEvent = rs:WaitForChild("CraftItem")
local cupActionEvent = rs:WaitForChild("CupAction")

local furnaceEvent = Instance.new("RemoteEvent")
furnaceEvent.Name = "FurnaceAction"
furnaceEvent.Parent = rs

local openFurnaceEvent = Instance.new("RemoteEvent")
openFurnaceEvent.Name = "OpenFurnace"
openFurnaceEvent.Parent = rs

-- ─── Smelting recipes ───
local SMELT_RECIPES = {
	Iron_Ore = { output = "Iron_Ingot", outputAmount = 1, time = SMELT_TIME },
}

-- ─── Track furnace smelting state ───
local furnaceStates = {} -- [furnaceModel] = { smelting, oreType, fuelCount, outputReady, outputType, ... }

-- ─── Find workbench ───
local function getWorkBenchPos()
	for _, v in workspace:GetDescendants() do
		if v:IsA("Model") and v.Name == "WorkBench" then
			if v.PrimaryPart then return v.PrimaryPart.Position end
			local part = v:FindFirstChildWhichIsA("BasePart", true)
			if part then return part.Position end
			return v:GetPivot().Position
		end
	end
	return nil
end

-- ─── Setup ProximityPrompt on a placed furnace ───
local function setupFurnacePrompt(furnaceModel)
	local part = furnaceModel.PrimaryPart or furnaceModel:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Smelt"
	prompt.ObjectText = "Furnace"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = FURNACE_RANGE
	prompt.RequiresLineOfSight = true
	prompt.Parent = part

	-- Init state
	furnaceStates[furnaceModel] = {
		smelting = false,
		oreType = nil, -- e.g. "Iron_Ore"
		fuelCount = 0, -- 0-4 logs loaded
		outputReady = false,
		outputType = nil,
		outputAmount = 0,
	}

	prompt.Triggered:Connect(function(player)
		local state = furnaceStates[furnaceModel]
		openFurnaceEvent:FireClient(player, furnaceModel, state)
	end)
end

-- ─── Find nearest furnace to player ───
local function findNearestFurnace(player)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local hrp = char.HumanoidRootPart

	local closest, closestDist = nil, FURNACE_RANGE
	for furnace in furnaceStates do
		local part = furnace.PrimaryPart or furnace:FindFirstChildWhichIsA("BasePart", true)
		if part then
			local dist = (hrp.Position - part.Position).Magnitude
			if dist < closestDist then
				closest = furnace
				closestDist = dist
			end
		end
	end
	return closest
end

-- ═══════════════════════════════════════════
-- CRAFTING: 10 Stone + 5 Log at workbench
-- ═══════════════════════════════════════════
craftEvent.OnServerEvent:Connect(function(player, action, data)
	if action ~= "craft" or data ~= "Furnace" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local wbPos = getWorkBenchPos()
	if not wbPos then return end
	if (char.HumanoidRootPart.Position - wbPos).Magnitude > WORKBENCH_RANGE then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Stone or 0) < 10 then return end
	if (inv.Log or 0) < 5 then return end

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Stone", 10)
		_G.RemoveResourceFromInventory(player, "Log", 5)
	else
		inv.Stone = inv.Stone - 10
		inv.Log = inv.Log - 5
	end

	-- Create placeable tool
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = "Furnace"
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Parent = tool

	if _G.GiveToolOrDrop then
		_G.GiveToolOrDrop(player, tool)
	else
		tool.Parent = backpack
	end

	if _G.SendInventory then _G.SendInventory(player) end
	craftEvent:FireClient(player, "success", "Furnace")
end)

-- ═══════════════════════════════════════════
-- PLACEMENT: Clone from RS, weld to raft
-- ═══════════════════════════════════════════
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeFurnace" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Furnace" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = rs:FindFirstChild("Furnace")
	if not template then return end

	local furnace = template:Clone()
	furnace.Name = "Furnace"

	-- Remove scripts from clone
	for _, desc in furnace:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Position
	if furnace:IsA("Model") then
		local bbCF = furnace:GetBoundingBox()
		furnace.WorldPivot = CFrame.new(bbCF.Position)
	end

	furnace:PivotTo(worldCF)
	furnace.Parent = raft

	-- T13/T15/T16: snapshot velocity, force-anchor (templates may be
	-- unanchored), weld while anchored, then unanchor.
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in furnace:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	for _, part in furnace:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
	for _, part in furnace:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel

	-- Setup interaction
	setupFurnacePrompt(furnace)

	tool:Destroy()
end)

-- ═══════════════════════════════════════════
-- SMELTING LOGIC
-- Any item can go in ore/fuel slots.
-- Fuel burns 1 wood every FUEL_BURN_TIME seconds.
-- Smelt can start with any amount of fuel.
-- If fuel runs out before smelt completes → process fails, ore lost.
-- ─── Auto-start smelting when ore + fuel are ready ───
local function tryAutoSmelt(furnace, state, player)
	if state.smelting then return end
	if not state.oreType or state.fuelCount <= 0 then return end
	if (state.outputAmount or 0) >= MAX_SLOT then return end

	local recipe = SMELT_RECIPES[state.oreType]
	if not recipe then return end

	state.smelting = true
	state.startTime = tick()
	state.smeltPlayer = player
	-- Increment smelt ID so old loops know they're stale
	state.smeltId = (state.smeltId or 0) + 1
	local mySmeltId = state.smeltId

	local totalTime = recipe.time
	furnaceEvent:FireClient(player, "smeltStart", totalTime, state.fuelCount)

	-- Fuel burn loop: burn 1 wood every FUEL_BURN_TIME
	task.spawn(function()
		local elapsed = 0

		while state.smelting and furnaceStates[furnace] and state.smeltId == mySmeltId do
			task.wait(FUEL_BURN_TIME)
			elapsed = elapsed + FUEL_BURN_TIME

			if not state.smelting or not furnaceStates[furnace] or state.smeltId ~= mySmeltId then break end

			state.fuelCount = state.fuelCount - 1

			-- Notify nearby players of fuel burn
			for _, p in Players:GetPlayers() do
				local c = p.Character
				if c and c:FindFirstChild("HumanoidRootPart") then
					local fpart = furnace.PrimaryPart or furnace:FindFirstChildWhichIsA("BasePart", true)
					if fpart and (c.HumanoidRootPart.Position - fpart.Position).Magnitude < FURNACE_RANGE then
						furnaceEvent:FireClient(p, "fuelBurn", state.fuelCount)
					end
				end
			end

			-- Check if smelt complete
			if elapsed >= totalTime then
				state.smelting = false
				state.outputReady = true
				state.outputType = recipe.output
				state.outputAmount = (state.outputAmount or 0) + recipe.outputAmount
				if state.outputAmount > MAX_SLOT then state.outputAmount = MAX_SLOT end
				state.oreType = nil
				state.smeltPlayer = nil

				for _, p in Players:GetPlayers() do
					local c = p.Character
					if c and c:FindFirstChild("HumanoidRootPart") then
						local fpart = furnace.PrimaryPart or furnace:FindFirstChildWhichIsA("BasePart", true)
						if fpart and (c.HumanoidRootPart.Position - fpart.Position).Magnitude < FURNACE_RANGE then
							furnaceEvent:FireClient(p, "smeltDone", state)
						end
					end
				end
				return
			end

			-- Fuel ran out before done
			if state.fuelCount <= 0 then
				state.smelting = false
				state.oreType = nil -- ore is consumed/lost
				state.smeltPlayer = nil

				for _, p in Players:GetPlayers() do
					local c = p.Character
					if c and c:FindFirstChild("HumanoidRootPart") then
						local fpart = furnace.PrimaryPart or furnace:FindFirstChildWhichIsA("BasePart", true)
						if fpart and (c.HumanoidRootPart.Position - fpart.Position).Magnitude < FURNACE_RANGE then
							furnaceEvent:FireClient(p, "smeltFailed", state)
						end
					end
				end
				return
			end
		end
	end)
end

-- ═══════════════════════════════════════════
furnaceEvent.OnServerEvent:Connect(function(player, action, data, data2)
	local furnace = findNearestFurnace(player)
	if not furnace or not furnaceStates[furnace] then return end

	local state = furnaceStates[furnace]
	local inv = _G.GetInventory and _G.GetInventory(player) or {}

	if action == "loadOre" then
		-- data = item name string (any inventory item)
		local itemName = data
		if typeof(itemName) ~= "string" then return end
		if state.smelting then return end
		if state.oreType then return end

		if (inv[itemName] or 0) < 1 then return end

		inv[itemName] = inv[itemName] - 1
		state.oreType = itemName

		if _G.SendInventory then _G.SendInventory(player) end
		furnaceEvent:FireClient(player, "stateUpdate", state)

		-- Auto-start smelting if fuel is also ready
		tryAutoSmelt(furnace, state, player)

	elseif action == "removeOre" then
		if not state.oreType then return end

		-- Check capacity before returning ore to inventory
		local cap = _G.GetInventoryCapacity and _G.GetInventoryCapacity(player, state.oreType) or 0
		if cap <= 0 then
			furnaceEvent:FireClient(player, "inventoryFull")
			return
		end

		-- Cancel smelting if in progress (ore returned, smelt aborted)
		if state.smelting then
			state.smelting = false
			state.smeltPlayer = nil
		end

		_G.AddResourceToInventory(player, state.oreType, 1, nil)
		state.oreType = nil

		furnaceEvent:FireClient(player, "stateUpdate", state)

	elseif action == "loadFuel" then
		-- data = item name, data2 = count (bulk load)
		local itemName = data
		if typeof(itemName) ~= "string" then return end

		-- Only wood is fuel
		if itemName ~= "Log" then return end
		if (inv.Log or 0) < 1 then return end

		local count = (typeof(data2) == "number") and math.floor(data2) or 1
		local space = MAX_SLOT - state.fuelCount
		if space <= 0 then return end
		count = math.clamp(count, 1, math.min(inv.Log, space))

		inv.Log = inv.Log - count
		state.fuelCount = state.fuelCount + count

		if _G.SendInventory then _G.SendInventory(player) end
		furnaceEvent:FireClient(player, "stateUpdate", state)

		-- Auto-start smelting if ore is also ready
		tryAutoSmelt(furnace, state, player)

	elseif action == "removeFuel" then
		if state.smelting or state.outputReady then return end
		if state.fuelCount <= 0 then return end

		-- Check capacity before returning fuel to inventory
		local cap = _G.GetInventoryCapacity and _G.GetInventoryCapacity(player, "Log") or 0
		if cap <= 0 then
			furnaceEvent:FireClient(player, "inventoryFull")
			return
		end

		-- data = count to remove (nil or 0 = all)
		local removeCount = (typeof(data) == "number" and data >= 1) and math.min(math.floor(data), state.fuelCount) or state.fuelCount
		-- Only return what fits in inventory
		removeCount = math.min(removeCount, cap)
		_G.AddResourceToInventory(player, "Log", removeCount, nil)
		state.fuelCount = state.fuelCount - removeCount
		furnaceEvent:FireClient(player, "stateUpdate", state)

	elseif action == "collectOutput" then
		if not state.outputReady or (state.outputAmount or 0) <= 0 then return end

		local outType = state.outputType or "Iron_Ingot"

		-- Check capacity before collecting — if inventory is full, refuse
		-- and keep the output in the furnace instead of force-dropping it.
		local cap = _G.GetInventoryCapacity and _G.GetInventoryCapacity(player, outType) or 0
		if cap <= 0 then
			furnaceEvent:FireClient(player, "inventoryFull")
			return
		end

		-- data = count to collect (nil or 0 = all); clamp to what fits
		local collectCount = (typeof(data) == "number" and data >= 1) and math.min(math.floor(data), state.outputAmount) or state.outputAmount
		collectCount = math.min(collectCount, cap)

		_G.AddResourceToInventory(player, outType, collectCount, nil)
		state.outputAmount = state.outputAmount - collectCount

		if state.outputAmount <= 0 then
			state.outputReady = false
			state.outputType = nil
			state.outputAmount = 0
		end

		if _G.OnQuestResource then _G.OnQuestResource(player, outType, collectCount) end
		furnaceEvent:FireClient(player, "stateUpdate", state)

	elseif action == "getState" then
		local elapsed = 0
		if state.smelting and state.startTime then
			elapsed = tick() - state.startTime
		end
		local recipe = state.oreType and SMELT_RECIPES[state.oreType]
		local totalTime = recipe and recipe.time or SMELT_TIME
		furnaceEvent:FireClient(player, "fullState", state, elapsed, totalTime)
	end
end)

-- ─── Ensure Iron_Ingot in inventories ───
local function ensureIronIngot(player)
	task.wait(2)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if inv and inv.Iron_Ingot == nil then
		inv.Iron_Ingot = 0
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(ensureIronIngot, p) end)
for _, p in Players:GetPlayers() do task.spawn(ensureIronIngot, p) end

-- ─── Setup existing furnaces in workspace ───
for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and child.Name == "Furnace" then
		setupFurnacePrompt(child)
	end
end
