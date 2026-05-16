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

local function tagPart(part)
	if not part:IsA("BasePart") then return end
	if part.Name ~= "Sand" and part.Name ~= "Clay" then return end
	if part:GetAttribute("Diggable") then return end

	part:SetAttribute("Diggable", true)
	part:SetAttribute("DigType", part.Name)
	part:SetAttribute("DigHealth", DIG_HITS_REQUIRED)
end

local function tagDiggablesInModel(model)
	for _, part in model:GetDescendants() do
		tagPart(part)
	end
end

local function isIsland(child)
	return child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2")
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
		part:Destroy()
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
