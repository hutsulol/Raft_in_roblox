-- PickAxeSystem.server.lua
-- Handles Pick-Axe crafting (2 logs) and rock mining on islands

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ─── Config ───
local MINE_HITS_REQUIRED = 5
local STONE_REWARD_MIN = 1
local STONE_REWARD_MAX = 3
local MINE_RANGE = 15

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

	inv.Log = inv.Log - 2

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

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		tool.Parent = backpack
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

	-- Visual feedback: shrink slightly
	if health > 0 then
		local scale = health / MINE_HITS_REQUIRED
		rockPart.Size = rockPart.Size * (0.9 + 0.1 * scale) / (0.9 + 0.1 * (scale + 1 / MINE_HITS_REQUIRED))
		-- Small shake effect
		local origCF = rockPart.CFrame
		rockPart.CFrame = origCF * CFrame.new(
			(math.random() - 0.5) * 0.3,
			(math.random() - 0.5) * 0.3,
			(math.random() - 0.5) * 0.3
		)
	end

	-- Rock destroyed
	if health <= 0 then
		local stoneAmount = math.random(STONE_REWARD_MIN, STONE_REWARD_MAX)

		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		inv.Stone = (inv.Stone or 0) + stoneAmount

		if _G.SendInventory then
			_G.SendInventory(player)
		end

		-- Feedback to client
		mineRockEvent:FireClient(player, "destroyed", stoneAmount)

		-- Destroy the rock
		rockPart:Destroy()
	else
		mineRockEvent:FireClient(player, "hit", health)
	end
end)
