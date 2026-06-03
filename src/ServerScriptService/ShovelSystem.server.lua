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
		-- Sand and Clay both live in the unified Sand Bag (one bag holds
		-- one type at a time — see SandBagSystem). One dug pile fills
		-- 15 % of a compatible bag. No bag / no room → ground drop, so
		-- the resource is never lost.
		if digType == "Sand" or digType == "Clay" then
			local landed = typeof(_G.AddPileToBag) == "function"
				and _G.AddPileToBag(player, digType, part.Position)
			if not landed and _G.SpawnResourceDrop then
				_G.SpawnResourceDrop(player, digType, 1, part.Position)
			end
			if _G.OnQuestResource then
				_G.OnQuestResource(player, digType, 1)
			end
			digDirtEvent:FireClient(player, "destroyed", 1, digType)
		else
			-- Future dig types (none yet) fall back to plain inventory.
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

-- Both Sand and Clay now live exclusively in the Sand Bag — neither
-- gets a backing inventory entry, so there's nothing to seed on
-- player-join. The old per-player ensureFields hook used to add
-- inv.Clay = 0 here; remove it now that crafting drains directly from
-- the bag (see InventoryCrafting).
