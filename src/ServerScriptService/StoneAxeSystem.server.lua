-- StoneAxeSystem.server.lua
-- Handles Stone_Axe crafting (1 Log + 3 Stone + 1 Rope) and
-- progressive tree chopping on islands.
--
-- Per-hit drop model (Raft-style):
--   * Each tree pre-rolls a drop pool the first time it's hit
--     (Log / Leaves / Sapling / Fruit). Per the user's brief the
--     pool is constrained to 1-2 saplings and 1-2 fruits per tree;
--     logs and leaves are bulk drops with no hard cap.
--   * Each subsequent hit dispenses a fraction of the remaining
--     pool, so the player sees items dribble out across the 5
--     swings instead of one big payout at the end.
--   * Fruit species depends on tree: Banana Tree → "Banana",
--     Palm Tree → "Coconut".
--
-- The "ChopTree" RemoteEvent now sends a per-hit drops table back
-- to the client (e.g. { Log=2, Leaves=1 }) so StoneAxeClient can
-- show a Raft-style bottom-right notification stack.

local rs      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

-- ─── Config ───
local CHOP_HITS_REQUIRED = 5
local CHOP_RANGE         = 15

local CHOPPABLE_TREE_NAMES = {
	["Palm Tree"]   = true,
	["Banana Tree"] = true,
}

-- Per-tree drop budgets. The same budget keys hang on the tree as
-- attributes once the pool is rolled; each hit decrements them.
--   range = { min, max }
local DROP_BUDGETS = {
	Log     = { 5, 9 },
	Leaves  = { 2, 4 },
	Sapling = { 1, 2 },   -- per user brief: 1-2 seeds per tree
	Fruit   = { 1, 2 },   -- per user brief: 1-2 fruits per tree
}

-- Fruit species varies with tree species. Default = Coconut.
local FRUIT_BY_TREE = {
	["Banana Tree"] = "Banana",
	["Palm Tree"]   = "Coconut",
}
local DEFAULT_FRUIT = "Coconut"

-- ─── Wood-break sound (Log resource template's "Wood Break") ─────
local function playChopSound(atPosition)
	if not atPosition then return end
	local logTemplate = rs:FindFirstChild("Log")
	if not logTemplate then return end
	local sound = logTemplate:FindFirstChild("Wood Break", true)
	if not sound or not sound:IsA("Sound") then return end

	local attach = Instance.new("Attachment")
	attach.WorldPosition = atPosition
	attach.Parent = workspace.Terrain

	local clone = sound:Clone()
	clone.Parent = attach
	clone:Play()

	local lifetime = (clone.TimeLength > 0 and clone.TimeLength or 2) + 0.5
	Debris:AddItem(attach, lifetime)
end

-- ─── RemoteEvent ───
local chopTreeEvent = Instance.new("RemoteEvent")
chopTreeEvent.Name = "ChopTree"
chopTreeEvent.Parent = rs

local inventoryCraftEvent = rs:WaitForChild("InventoryCraft")

-- ─── Tag choppable tree models ───
local function tagTreesInModel(rootModel)
	for _, descendant in rootModel:GetDescendants() do
		if descendant:IsA("Model") and CHOPPABLE_TREE_NAMES[descendant.Name] then
			descendant:SetAttribute("Choppable", true)
			descendant:SetAttribute("TreeHealth", CHOP_HITS_REQUIRED)
		end
	end
end

workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child.Name:match("^Island") then
		task.wait(0.1)
		tagTreesInModel(child)
	end
end)

for _, child in workspace:GetChildren() do
	if child:IsA("Model") and child.Name:match("^Island") then
		tagTreesInModel(child)
	end
end

-- ─── Drop pool helpers ──────────────────────────────────────────────
local function ensureDropPool(treeModel)
	if treeModel:GetAttribute("DropPoolReady") then return end
	treeModel:SetAttribute("DropPoolReady", true)

	for kind, range in pairs(DROP_BUDGETS) do
		treeModel:SetAttribute("Drop" .. kind, math.random(range[1], range[2]))
	end

	-- Resolve fruit species once; client doesn't need to know.
	local fruitName = FRUIT_BY_TREE[treeModel.Name] or DEFAULT_FRUIT
	treeModel:SetAttribute("DropFruitName", fruitName)
end

-- Take a fair-but-randomised chunk out of each remaining pool. The
-- partition is `ceil(remaining / hitsLeft)` ± 1 so every hit feels
-- like a different mix instead of an even slice every time. The
-- final hit dumps anything still in the pool so total drops match
-- what was rolled.
local function dispensePool(treeModel, hitsLeftIncludingThis)
	local drops = {}
	for kind, _ in pairs(DROP_BUDGETS) do
		local poolKey  = "Drop" .. kind
		local remaining = treeModel:GetAttribute(poolKey) or 0
		if remaining > 0 then
			local thisHit
			if hitsLeftIncludingThis <= 1 then
				thisHit = remaining
			else
				local fair = math.ceil(remaining / hitsLeftIncludingThis)
				local lo   = math.max(0, fair - 1)
				local hi   = math.min(remaining, fair + 1)
				thisHit    = math.random(lo, hi)
			end
			if thisHit > 0 then
				local resName = (kind == "Fruit")
					and treeModel:GetAttribute("DropFruitName")
					or kind
				drops[resName] = thisHit
				treeModel:SetAttribute(poolKey, remaining - thisHit)
			end
		end
	end
	return drops
end

-- ─── Stone_Axe crafting ─────────────────────────────────────────────
inventoryCraftEvent.OnServerEvent:Connect(function(player, action, data)
	if action ~= "craft" or data ~= "Stone_Axe" then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 1 then return end
	if (inv.Stone or 0) < 3 then return end
	if (inv.Rope or 0) < 1 then return end

	if _G.RemoveResourceFromInventory then
		_G.RemoveResourceFromInventory(player, "Log",   1)
		_G.RemoveResourceFromInventory(player, "Stone", 3)
		_G.RemoveResourceFromInventory(player, "Rope",  1)
	else
		inv.Log   = inv.Log   - 1
		inv.Stone = inv.Stone - 3
		inv.Rope  = inv.Rope  - 1
	end

	local template = rs:FindFirstChild("Stone_Axe")
	if not template then
		warn("[StoneAxeSystem] Stone_Axe template missing in ReplicatedStorage")
		return
	end

	local cloned = template:Clone()
	local tool
	if cloned:IsA("Tool") then
		tool = cloned
	else
		tool = Instance.new("Tool")
		tool.Name = "Stone_Axe"
		tool.CanBeDropped = false
		if cloned:IsA("Model") then
			local handle = cloned:FindFirstChild("Handle")
				or cloned:FindFirstChildWhichIsA("BasePart", true)
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

	inventoryCraftEvent:FireClient(player, "success", "Stone_Axe")
end)

-- ─── Tree chopping ──────────────────────────────────────────────────
chopTreeEvent.OnServerEvent:Connect(function(player, treeModel)
	if not treeModel or not treeModel:IsA("Model") then return end
	if not treeModel:GetAttribute("Choppable") then return end

	-- Equip check
	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Stone_Axe" then return end

	-- Range check
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local treePos = treeModel:GetPivot().Position
	local dist = (hrp.Position - treePos).Magnitude
	if dist > CHOP_RANGE then return end

	-- Decrement tree health + ensure the drop pool exists for this tree.
	local healthBefore = treeModel:GetAttribute("TreeHealth") or CHOP_HITS_REQUIRED
	ensureDropPool(treeModel)
	local healthAfter = healthBefore - 1
	treeModel:SetAttribute("TreeHealth", healthAfter)

	-- Pull a slice out of the pool for THIS hit. hitsLeftIncludingThis
	-- counts the current hit, so on the final swing (healthAfter == 0)
	-- it equals 1 and dispensePool dumps the remainder.
	local hitsLeftIncludingThis = healthAfter + 1
	local drops = dispensePool(treeModel, hitsLeftIncludingThis)

	-- Award drops + run quest hooks per resource.
	for resName, count in pairs(drops) do
		_G.AddResourceToInventory(player, resName, count, treePos)
		if _G.OnQuestResource then
			_G.OnQuestResource(player, resName, count)
		end
	end

	-- Wood-break SFX every hit so swings always feel weighty.
	playChopSound(treePos)

	-- Notify the client so it can render bottom-right notifications +
	-- "N hits left" hint text. drops may be empty for an unlucky
	-- swing — the client filters that out.
	chopTreeEvent:FireClient(player, "drops", drops, healthAfter)

	if healthAfter <= 0 then
		treeModel:Destroy()
	end
end)
