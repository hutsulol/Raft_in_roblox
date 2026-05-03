-- PickAxeSystem.server.lua
-- Handles Pick-Axe crafting (2 logs) and rock mining on islands

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- ─── Config ───
local MINE_HITS_REQUIRED = 5
local STONE_REWARD_MIN = 1
local STONE_REWARD_MAX = 3
local MINE_RANGE = 15

-- ─── Dig sound (from Shovel tool) ───
local function playDigSound(atPart)
	if not atPart then return end
	local shovel = rs:FindFirstChild("Shovel")
	if not shovel then return end
	local handle = shovel:FindFirstChild("Handle")
	if not handle then return end
	local dig = handle:FindFirstChild("Dig")
	if not dig or not dig:IsA("Sound") then return end
	-- Parent to a temporary attachment in workspace so the sound survives
	-- even if the mined part is destroyed on the final hit.
	local attach = Instance.new("Attachment")
	attach.WorldPosition = atPart.Position
	attach.Parent = workspace.Terrain
	local clone = dig:Clone()
	clone.Parent = attach
	clone:Play()
	local lifetime = (clone.TimeLength > 0 and clone.TimeLength or 2) + 0.5
	Debris:AddItem(attach, lifetime)
end

-- Rock materials to auto-tag as mineable
local ROCK_MATERIALS = {
	[Enum.Material.Slate] = true,
	[Enum.Material.Basalt] = true,
	[Enum.Material.Rock] = true,
	[Enum.Material.Granite] = true,
}

-- ─── RemoteEvents ───
local mineRockEvent = Instance.new("RemoteEvent")
mineRockEvent.Name = "MineRock"
mineRockEvent.Parent = rs

local inventoryCraftEvent = rs:WaitForChild("InventoryCraft")

-- ─── Tag rocks in a model ───
local function tagRocksInModel(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local nameL = part.Name:lower()
			local isRock = ROCK_MATERIALS[part.Material]
				or nameL:find("rock") ~= nil
				or nameL:find("stone") ~= nil
				or nameL:find("boulder") ~= nil

			if isRock then
				part:SetAttribute("Mineable", true)
				part:SetAttribute("MineHealth", MINE_HITS_REQUIRED)
			end
		end
	end
end

-- ─── Watch for new islands in workspace and tag their rocks ───
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2") then
		task.wait(0.1) -- let model fully load
		tagRocksInModel(child)
	end
end)

-- Tag rocks in any islands already in workspace
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2") then
		tagRocksInModel(child)
	end
end

-- ─── Handle Pick-Axe crafting ───
inventoryCraftEvent.OnServerEvent:Connect(function(player, action, data)
	if action ~= "craft" or data ~= "Pick-Axe" then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 2)
	else
		inv.Log = inv.Log - 2
	end

	local template = rs:FindFirstChild("Pick-Axe")
	if not template then return end

	local cloned = template:Clone()
	local tool

	if cloned:IsA("Tool") then
		tool = cloned
	else
		tool = Instance.new("Tool")
		tool.Name = "Pick-Axe"
		tool.CanBeDropped = false

		if cloned:IsA("Model") then
			local handle = cloned:FindFirstChild("Handle")
			if not handle then
				handle = cloned:FindFirstChildWhichIsA("BasePart", true)
			end
			for _, child in cloned:GetChildren() do
				child.Parent = tool
			end
			if handle and handle.Name ~= "Handle" then
				handle.Name = "Handle"
			end
		elseif cloned:IsA("BasePart") then
			cloned.Name = "Handle"
			cloned.Parent = tool
		end
		cloned:Destroy()
	end

	if _G.GiveToolOrDrop then
		_G.GiveToolOrDrop(player, tool)
	else
		local backpack = player:FindFirstChild("Backpack")
		if backpack then tool.Parent = backpack end
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	inventoryCraftEvent:FireClient(player, "success", "Pick-Axe")
end)

-- ─── Handle rock mining ───
mineRockEvent.OnServerEvent:Connect(function(player, rockPart)
	if not rockPart or not rockPart:IsA("BasePart") then return end
	if not rockPart:GetAttribute("Mineable") then return end

	-- Check player has Pick-Axe equipped
	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Pick-Axe" then return end

	-- Check distance
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local dist = (hrp.Position - rockPart.Position).Magnitude
	if dist > MINE_RANGE then return end

	-- Decrease health
	local health = rockPart:GetAttribute("MineHealth") or MINE_HITS_REQUIRED
	health = health - 1
	rockPart:SetAttribute("MineHealth", health)

	-- Play Dig sound on each successful hit
	playDigSound(rockPart)

	-- Shrinking is handled by MiningShrink.server.lua via MineHealth attribute

	-- Rock destroyed
	if health <= 0 then
		local stoneAmount = math.random(STONE_REWARD_MIN, STONE_REWARD_MAX)

		_G.AddResourceToInventory(player, "Stone", stoneAmount, rockPart.Position)
		if _G.OnQuestResource then
			_G.OnQuestResource(player, "Stone", stoneAmount)
		end

		-- Feedback to client
		mineRockEvent:FireClient(player, "destroyed", stoneAmount)

		-- Destroy the rock
		rockPart:Destroy()
	else
		mineRockEvent:FireClient(player, "hit", health)
	end
end)
