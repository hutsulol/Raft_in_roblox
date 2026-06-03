-- PickAxeSystem.server.lua
-- Handles Pick-Axe crafting (2 logs) and rock mining on islands

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- ─── Config ───
local MINE_HITS_REQUIRED = 5
-- Per-hit drop chance: each swing independently rolls for one Stone, so
-- the player sees the resource arrive gradually across the rock's
-- lifetime (mirrors how tree-chopping dispenses 1-2 items per swing).
-- 0.75 averages to ~3.75 stones per rock, with 0..5 possible.
local STONE_DROP_CHANCE = 0.75
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

	-- Look up the template BEFORE deducting resources. The old flow
	-- pulled 2 Log first, then bailed silently when the template was
	-- missing — players watched their logs vanish with no Pick-Axe in
	-- hand. We also fall back to a recursive search so the template
	-- can live inside a sub-folder (e.g. ReplicatedStorage.Tools),
	-- matching how InventoryCrafting resolves recipes.
	local template = rs:FindFirstChild("Pick-Axe") or rs:FindFirstChild("Pick-Axe", true)

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log", 2)
	else
		inv.Log = inv.Log - 2
	end

	local tool

	if template then
		local cloned = template:Clone()

		if cloned:IsA("Tool") then
			tool = cloned
			if not tool:FindFirstChild("Handle") then
				local firstPart = tool:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then firstPart.Name = "Handle" end
			end
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
	else
		-- Missing template — still hand the player a working placeholder
		-- Tool with the right name + icon (mirrors InventoryCrafting's
		-- fallback for tool recipes). The Mining systems key off
		-- tool.Name == "Pick-Axe" so the placeholder is still functional
		-- for hitting rocks, just invisible.
		tool = Instance.new("Tool")
		tool.Name = "Pick-Axe"
		tool.CanBeDropped = false
		tool.TextureId = "rbxassetid://89809613033816"
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.Parent = tool
		warn("[PickAxeSystem] Pick-Axe template missing from ReplicatedStorage — handed placeholder Tool")
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

	-- Per-hit Stone reward: 75% chance for 1 Stone per swing. The
	-- InventoryNotify system handles the visual "+1 Stone" card from
	-- _G.AddResourceToInventory, so the player sees each successful
	-- chip-off in real time.
	local gained = 0
	if math.random() < STONE_DROP_CHANCE then
		gained = 1
		_G.AddResourceToInventory(player, "Stone", 1, rockPart.Position)
		if _G.OnQuestResource then
			_G.OnQuestResource(player, "Stone", 1)
		end
	end

	-- Track cumulative drops on the rock so the "destroyed" feedback
	-- can show the run total.
	local totalDropped = (rockPart:GetAttribute("StoneDropped") or 0) + gained
	rockPart:SetAttribute("StoneDropped", totalDropped)

	-- Shrinking is handled by MiningShrink.server.lua via MineHealth attribute

	-- Rock destroyed on the final swing — no extra batch reward, the
	-- per-hit rolls already covered everything.
	if health <= 0 then
		mineRockEvent:FireClient(player, "destroyed", totalDropped)
		rockPart:Destroy()
	else
		mineRockEvent:FireClient(player, "hit", health, gained)
	end
end)
