-- StoneAxeSystem.server.lua
-- Handles Stone_Axe crafting (1 Log + 3 Stone + 1 Rope) and tree
-- chopping on islands. Mirrors the Pick-Axe / rock-mining pipeline:
--   * `Choppable` + `TreeHealth` attributes get stamped on every Palm
--     Tree / Banana Tree under any "Island_*" model in workspace.
--   * The "ChopTree" RemoteEvent receives a tree Model from the
--     client; the server validates the equip + range, decrements
--     TreeHealth, plays a wood-break sound, and on the 5th hit
--     awards 2-4 Logs and destroys the tree.
--   * Crafting hooks the shared "InventoryCraft" remote — the same
--     event Pick-Axe / Hammer / Machete use — and consumes the
--     three resources atomically before handing the player a fresh
--     Stone_Axe Tool from ReplicatedStorage.

local rs      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

-- ─── Config ───
local CHOP_HITS_REQUIRED = 5
local LOG_REWARD_MIN     = 2
local LOG_REWARD_MAX     = 4
local CHOP_RANGE         = 15

-- Tree species we treat as choppable. Match by exact Model.Name to
-- avoid sweeping up decorative shrubs / pineapple leaves on the same
-- island. Adding a new species is a single-line change here.
local CHOPPABLE_TREE_NAMES = {
	["Palm Tree"]   = true,
	["Banana Tree"] = true,
}

-- Bananas drop alongside logs when a Banana Tree falls so the species
-- distinction reads in-game. Palm trees just give logs. Reward shape
-- per tree species: { resource = name, min, max }.
local EXTRA_REWARDS = {
	["Banana Tree"] = { resource = "Banana", min = 1, max = 2 },
}

-- ─── Wood-break sound (reuse the resource-pull / pirate-harvest one) ─
-- The "Wood Break" Sound ships as a child of the Log resource template
-- in ReplicatedStorage. Clone it onto a temporary Attachment at the
-- tree's position so the sound replicates spatially even after the
-- tree Model is destroyed on the final hit.
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

-- ─── Tag choppable trees ───
-- We tag the Tree MODEL (not its handle BasePart) because trees ship
-- as multi-part models — leaves, trunk, fruit. The Model is what
-- the client raycast resolves to via FindFirstAncestorOfClass, and
-- destroying it on the final hit cleans every child up at once.
local function tagTreesInModel(rootModel)
	for _, descendant in rootModel:GetDescendants() do
		if descendant:IsA("Model") and CHOPPABLE_TREE_NAMES[descendant.Name] then
			descendant:SetAttribute("Choppable", true)
			descendant:SetAttribute("TreeHealth", CHOP_HITS_REQUIRED)
		end
	end
end

-- Watch for new islands as they enter the world (initial save-load,
-- procedural placement). Same pattern PickAxeSystem uses for rocks.
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child.Name:match("^Island") then
		task.wait(0.1)
		tagTreesInModel(child)
	end
end)

-- Tag any islands already in the world at script init.
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and child.Name:match("^Island") then
		tagTreesInModel(child)
	end
end

-- ─── Stone_Axe crafting ───
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

	-- Mirror the Pick-Axe pattern: clone the template; if it landed
	-- as a Model (some user-authored rigs ship that way), wrap it in
	-- a Tool so the player can equip it.
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

-- ─── Tree chopping ───
chopTreeEvent.OnServerEvent:Connect(function(player, treeModel)
	if not treeModel or not treeModel:IsA("Model") then return end
	if not treeModel:GetAttribute("Choppable") then return end

	-- Equip check
	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Stone_Axe" then return end

	-- Range check (server-authoritative, matches the client cooldown's
	-- intent so a hand-crafted RemoteEvent can't farm trees from
	-- across the map).
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local treePos = treeModel:GetPivot().Position
	local dist = (hrp.Position - treePos).Magnitude
	if dist > CHOP_RANGE then return end

	-- Decrement hit counter
	local health = treeModel:GetAttribute("TreeHealth") or CHOP_HITS_REQUIRED
	health = health - 1
	treeModel:SetAttribute("TreeHealth", health)

	-- Wood-break sound on every successful hit (so the player gets
	-- audible feedback even for the in-progress 4 swings).
	playChopSound(treePos)

	if health <= 0 then
		-- Tree felled. Award logs + any species-specific extras.
		local logAmount = math.random(LOG_REWARD_MIN, LOG_REWARD_MAX)
		_G.AddResourceToInventory(player, "Log", logAmount, treePos)
		if _G.OnQuestResource then
			_G.OnQuestResource(player, "Log", logAmount)
		end

		local extras = EXTRA_REWARDS[treeModel.Name]
		local extraInfo
		if extras and extras.resource then
			local n = math.random(extras.min or 1, extras.max or 1)
			if n > 0 then
				_G.AddResourceToInventory(player, extras.resource, n, treePos)
				if _G.OnQuestResource then
					_G.OnQuestResource(player, extras.resource, n)
				end
				extraInfo = { resource = extras.resource, count = n }
			end
		end

		chopTreeEvent:FireClient(player, "destroyed", logAmount, extraInfo)
		treeModel:Destroy()
	else
		chopTreeEvent:FireClient(player, "hit", health)
	end
end)
