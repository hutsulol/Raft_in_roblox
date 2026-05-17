-- ShovelSystem.server.lua
-- Tags Sand/Clay parts on islands and handles digging with the Shovel tool.
-- Unlike rocks, the part is NOT shrunk while being dug.

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local DIG_HITS_REQUIRED = 5
local DIG_RANGE = 15

local digDirtEvent = Instance.new("RemoteEvent")
digDirtEvent.Name = "DigDirt"
digDirtEvent.Parent = rs

-- ─── Dig sound (from Shovel tool in ReplicatedStorage) ───
local function playDigSound(atPart)
	if not atPart then return end
	local shovel = rs:FindFirstChild("Shovel")
	if not shovel then return end
	-- Look for Shoveling sound recursively in the Shovel tool
	local snd = shovel:FindFirstChild("Shoveling", true)
	if not snd or not snd:IsA("Sound") then return end
	local attach = Instance.new("Attachment")
	attach.WorldPosition = atPart.Position
	attach.Parent = workspace.Terrain
	local clone = snd:Clone()
	clone.Parent = attach
	clone:Play()
	local lifetime = (clone.TimeLength > 0 and clone.TimeLength or 2) + 0.5
	Debris:AddItem(attach, lifetime)
end

-- Resolves the dig type for a part. Returns "Sand", "Clay", or nil.
-- Two recognition rules:
--   1. The BasePart itself is named "Sand" or "Clay" (legacy shape —
--      e.g. flat ground patches).
--   2. The BasePart sits directly inside a Model named "Sand" or
--      "Clay" (new island art — clay clumps are a Model that wraps
--      one or more Union meshes). Each child mesh acts as its own
--      dig target so the player chips away one lump at a time.
local function resolveDigType(part)
	if part.Name == "Sand" or part.Name == "Clay" then
		return part.Name
	end
	local parent = part.Parent
	if parent and parent:IsA("Model") and (parent.Name == "Sand" or parent.Name == "Clay") then
		return parent.Name
	end
	return nil
end

local function tagPart(part)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("Diggable") then return end

	local digType = resolveDigType(part)
	if not digType then return end

	part:SetAttribute("Diggable", true)
	part:SetAttribute("DigType", digType)
	part:SetAttribute("DigHealth", DIG_HITS_REQUIRED)
end

local function tagDiggablesInModel(model)
	for _, part in model:GetDescendants() do
		tagPart(part)
	end
end

local function isIsland(child)
	if not child:IsA("Model") then return false end
	-- Accept any island variant: "Island", "Island_1", "Island_42", …
	return child.Name == "Island" or child.Name:match("^Island_%d+$") ~= nil
end

workspace.ChildAdded:Connect(function(child)
	if isIsland(child) then
		task.wait(0.1)
		tagDiggablesInModel(child)
	end
end)

for _, child in workspace:GetChildren() do
	if isIsland(child) then
		tagDiggablesInModel(child)
	end
end

digDirtEvent.OnServerEvent:Connect(function(player, part)
	if not part or not part:IsA("BasePart") then return end
	if not part:GetAttribute("Diggable") then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Shovel" then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - part.Position).Magnitude > DIG_RANGE then return end

	local health = part:GetAttribute("DigHealth") or DIG_HITS_REQUIRED
	health = health - 1
	part:SetAttribute("DigHealth", health)

	playDigSound(part)

	if health <= 0 then
		local digType = part:GetAttribute("DigType") or "Sand"
		if digType == "Sand" then
			-- Sand bypasses the main inventory and goes into the
			-- Sand Bag tool the player carries (per SandBagSystem).
			-- One pile = +15 % bag fill. Without a bag (or with all
			-- bags full) we spill the pile onto the ground as a
			-- physical drop so the player can pick it up later, after
			-- they craft / empty a bag.
			local hasFn = typeof(_G.AddSandPileToBag) == "function"
			print("[ShovelSystem] Sand dug. AddSandPileToBag exists?", hasFn,
				"PlayerHasSandBag?", typeof(_G.PlayerHasSandBag) == "function" and _G.PlayerHasSandBag(player),
				"BagSpace=", typeof(_G.GetSandBagSpace) == "function" and _G.GetSandBagSpace(player))
			local landed = hasFn and _G.AddSandPileToBag(player, part.Position)
			print("[ShovelSystem] AddSandPileToBag returned:", landed)
			if not landed and _G.SpawnResourceDrop then
				print("[ShovelSystem] Falling back to ground drop")
				_G.SpawnResourceDrop(player, "Sand", 1, part.Position)
			end
			if _G.OnQuestResource then
				_G.OnQuestResource(player, "Sand", 1)
			end
			digDirtEvent:FireClient(player, "destroyed", 1, "Sand")
		else
			-- Clay (and any future dig type) keeps the old behaviour:
			-- straight into the main inventory.
			_G.AddResourceToInventory(player, digType, 1, part.Position)
			if _G.OnQuestResource then
				_G.OnQuestResource(player, digType, 1)
			end
			digDirtEvent:FireClient(player, "destroyed", 1, digType)
		end
		-- Clean up the wrapper Model once its last lump is dug — a Clay
		-- clump (or Sand patch) is a Model containing N Union meshes,
		-- each of which is its own dig target. When the player chips
		-- away the final mesh the empty Model would otherwise linger
		-- in workspace forever.
		local parent = part.Parent
		part:Destroy()
		if parent and parent:IsA("Model")
			and (parent.Name == "Sand" or parent.Name == "Clay")
			and not parent:FindFirstChildWhichIsA("BasePart") then
			parent:Destroy()
		end
	else
		digDirtEvent:FireClient(player, "hit", health)
	end
end)

-- ─── Ensure Clay exists in player inventories ───
-- Sand was removed from the main inventory — it lives in the Sand
-- Bag (SandBagSystem) now. Clay still flows through the regular
-- inventory.
local function ensureFields(player)
	task.wait(2)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if inv then
		if inv.Clay == nil then inv.Clay = 0 end
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(ensureFields, p) end)
for _, p in Players:GetPlayers() do task.spawn(ensureFields, p) end
