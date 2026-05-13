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

-- Per-tree drop budgets. Sized so the total pool stays ≤ 10 items —
-- with the 2-items-per-swing cap below, 5 swings × 2 = 10 is the
-- maximum we can dispense without leaving anything behind on the
-- final hit.
--   range = { min, max }
local DROP_BUDGETS = {
	Log     = { 2, 4 },
	Leaves  = { 1, 2 },
	Sapling = { 1, 2 },   -- per user brief: 1-2 seeds per tree
	Fruit   = { 1, 2 },   -- per user brief: 1-2 fruits per tree
}

-- Hard cap on items dispensed in a single swing — per user request:
-- "максимум 2 одновременно". The pool budgets above are tuned so the
-- pool empties cleanly within 5 swings × 2 cap.
local MAX_DROPS_PER_HIT = 2

-- Fruit + seed species vary with tree species. Default falls back to
-- the palm pair so chopping a planted bed-tree (wrapper named
-- Bed_Garden_For_Tree, not "Palm Tree") still yields a sensible
-- Coconut + Coconut_Seed pair.
local FRUIT_BY_TREE = {
	["Banana Tree"] = "Banana",
	["Palm Tree"]   = "Coconut",
}
local SEED_BY_TREE = {
	["Banana Tree"] = "Banana_Seed",
	["Palm Tree"]   = "Coconut_Seed",
}
local DEFAULT_FRUIT = "Coconut"
local DEFAULT_SEED  = "Coconut_Seed"

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

	-- Resolve fruit + seed species once; client doesn't need to know.
	-- Planted bed-trees (wrapper named "Bed_Garden_For_Tree") carry a
	-- PlantedSeed attribute that hints at the seed kind chosen, which
	-- we honour here so a Banana-seeded planted tree drops bananas
	-- instead of coconuts. Otherwise fall through to the per-tree
	-- table, then the default palm pair.
	local plantedSeed = treeModel:GetAttribute("PlantedSeed")
	local fruitName = FRUIT_BY_TREE[treeModel.Name]
	local seedName  = SEED_BY_TREE[treeModel.Name]
	if plantedSeed then
		if plantedSeed == "Banana_Seed" then
			fruitName = fruitName or "Banana"
			seedName  = seedName  or "Banana_Seed"
		elseif plantedSeed == "Pineapple_Seed" then
			fruitName = fruitName or "Pineapple"
			seedName  = seedName  or "Pineapple_Seed"
		elseif plantedSeed == "Coconut_Seed" then
			fruitName = fruitName or "Coconut"
			seedName  = seedName  or "Coconut_Seed"
		end
	end
	treeModel:SetAttribute("DropFruitName", fruitName or DEFAULT_FRUIT)
	treeModel:SetAttribute("DropSeedName",  seedName  or DEFAULT_SEED)
end

-- Pulls AT MOST `MAX_DROPS_PER_HIT` items from the remaining pool —
-- one per distinct resource bucket (Log / Leaves / Sapling / Fruit).
-- Picks buckets that are "behind schedule" (more remaining vs hits
-- left) preferentially, so the pool empties evenly across the 5
-- swings instead of all-saplings then all-logs. On the final swing
-- (hitsLeftIncludingThis == 1) we still respect the 2-cap, so any
-- pool that grew past 10 will leave items behind by design.
local function dispensePool(treeModel, hitsLeftIncludingThis)
	local drops = {}

	-- Collect non-empty buckets along with their "pressure" — a
	-- ratio of how much the pool needs to release this swing to
	-- finish on time. ceil(remaining / hitsLeft) is the per-swing
	-- pace; high pressure = forced to drop, low = optional.
	local buckets = {}
	for kind, _ in pairs(DROP_BUDGETS) do
		local poolKey  = "Drop" .. kind
		local remaining = treeModel:GetAttribute(poolKey) or 0
		if remaining > 0 then
			local pressure = math.ceil(remaining / math.max(1, hitsLeftIncludingThis))
			-- Tiny random jitter so equal-pressure buckets don't
			-- always pick in the same alphabetical order.
			pressure = pressure + math.random() * 0.5
			table.insert(buckets, { kind = kind, pressure = pressure })
		end
	end

	if #buckets == 0 then return drops end

	-- Sort highest-pressure first so each swing prioritises whatever
	-- pool is most behind schedule.
	table.sort(buckets, function(a, b) return a.pressure > b.pressure end)

	for i = 1, math.min(MAX_DROPS_PER_HIT, #buckets) do
		local kind     = buckets[i].kind
		local poolKey  = "Drop" .. kind
		local remaining = treeModel:GetAttribute(poolKey)
		-- "Sapling" / "Fruit" buckets translate to a per-tree resource
		-- name (Banana_Seed vs Coconut_Seed, Banana vs Coconut, etc.)
		-- resolved once in ensureDropPool. Logs / Leaves keep their
		-- bucket name verbatim because they're tree-agnostic.
		local resName
		if kind == "Fruit" then
			resName = treeModel:GetAttribute("DropFruitName") or DEFAULT_FRUIT
		elseif kind == "Sapling" then
			resName = treeModel:GetAttribute("DropSeedName") or DEFAULT_SEED
		else
			resName = kind
		end
		drops[resName] = 1
		treeModel:SetAttribute(poolKey, remaining - 1)
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
		-- Planted tree on a raft bed: the wrapper Model IS the tree-bed,
		-- destroying it would also remove the bed. Hand it off to
		-- GardenSystem instead, which swaps the bed back to its dry
		-- empty state. Falls back to Destroy() for world-spawned trees
		-- that have no bed under them.
		if treeModel:GetAttribute("IsPlantedTree") and typeof(_G.OnPlantedTreeChopped) == "function" then
			pcall(_G.OnPlantedTreeChopped, treeModel)
		else
			treeModel:Destroy()
		end
	end
end)
