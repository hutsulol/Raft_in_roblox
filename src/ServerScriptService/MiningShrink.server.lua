-- MiningShrink.server.lua
-- 1) Proper grounded shrinking for Rock (tagged by PickAxeSystem)
-- 2) Full Iron_Ore mining system: tagging, health, shrinking, rewards

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- ─── Config ───
local ROCK_MAX_HITS = 5
local ROCK_MIN_SCALE = 0.7

local IRON_HITS = 20
local IRON_MIN_SCALE = 0.75
local IRON_REWARD = 1
local MINE_RANGE = 15

-- ─── Dig sound (from Shovel tool) ───
local function playDigSound(atPart)
	if not atPart or not atPart.Parent then return end
	local shovel = rs:FindFirstChild("Shovel")
	if not shovel then return end
	local handle = shovel:FindFirstChild("Handle")
	if not handle then return end
	local dig = handle:FindFirstChild("Dig")
	if not dig or not dig:IsA("Sound") then return end
	local clone = dig:Clone()
	clone.Parent = atPart
	clone:Play()
	Debris:AddItem(clone, (clone.TimeLength > 0 and clone.TimeLength or 2) + 0.5)
end

-- ─── RemoteEvents ───
local mineRockEvent = rs:WaitForChild("MineRock") -- used by PickAxeSystem for rocks

local mineOreEvent = Instance.new("RemoteEvent")
mineOreEvent.Name = "MineOre"
mineOreEvent.Parent = rs

-- ─── Store originals ───
local originalSizes = {}
local originalBottomY = {}
local originalRotation = {}
local originalX = {}
local originalZ = {}

local function storeOriginal(part)
	if not originalSizes[part] then
		originalSizes[part] = part.Size
		originalBottomY[part] = part.Position.Y - part.Size.Y / 2
		originalRotation[part] = part.CFrame - part.CFrame.Position
		originalX[part] = part.Position.X
		originalZ[part] = part.Position.Z
	end
end

local function shrinkPart(part, fraction, minScale)
	local origSize = originalSizes[part]
	local bottomY = originalBottomY[part]
	local rot = originalRotation[part]
	local ox = originalX[part]
	local oz = originalZ[part]
	if not origSize or not bottomY or not rot then return end

	local scale = minScale + (1 - minScale) * fraction
	local newSize = origSize * scale
	part.Size = newSize
	-- Keep grounded at original position, using stored rotation
	part.CFrame = CFrame.new(ox, bottomY + newSize.Y / 2, oz) * rot
end

local function cleanupPart(part)
	originalSizes[part] = nil
	originalBottomY[part] = nil
	originalRotation[part] = nil
	originalX[part] = nil
	originalZ[part] = nil
end

-- ═══════════════════════════════════════════
-- PART 1: Rock shrinking (PickAxeSystem handles health/reward/destroy)
-- We watch MineHealth attribute changes to shrink properly
-- ═══════════════════════════════════════════

local function watchRockHealth(part)
	storeOriginal(part)
	-- Use PickAxeSystem's MineHealth as the max (it sets initial health = max hits)
	local initHealth = part:GetAttribute("MineHealth") or ROCK_MAX_HITS
	part:SetAttribute("MineMaxHealth", initHealth)
	part:SetAttribute("OreType", "Rock")

	part:GetAttributeChangedSignal("MineHealth"):Connect(function()
		local health = part:GetAttribute("MineHealth")
		if not health then return end
		local maxH = part:GetAttribute("MineMaxHealth") or ROCK_MAX_HITS
		if health > 0 then
			shrinkPart(part, health / maxH, ROCK_MIN_SCALE)
		end
	end)
end

-- Watch for rocks tagged by PickAxeSystem (Mineable attribute appears)
local function checkAndWatchRock(part)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("Mineable") and not part:GetAttribute("OreType") then
		watchRockHealth(part)
	end
end

-- Scan existing
for _, desc in workspace:GetDescendants() do
	checkAndWatchRock(desc)
end

-- Watch new parts and attribute changes
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("BasePart") then
		-- Wait a moment for PickAxeSystem to tag it
		task.wait(0.2)
		checkAndWatchRock(desc)
	end
end)

-- Also watch attribute additions on existing parts
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("BasePart") then
		desc:GetAttributeChangedSignal("Mineable"):Connect(function()
			if desc:GetAttribute("Mineable") and not desc:GetAttribute("OreType") then
				watchRockHealth(desc)
			end
		end)
	end
end)

-- ═══════════════════════════════════════════
-- PART 2: Iron_Ore - full system
-- Uses MineableOre attribute (NOT Mineable) to avoid PickAxeSystem conflict
-- ═══════════════════════════════════════════

local function protectIronOre(part)
	-- Remove Mineable if PickAxeSystem tagged it by material
	if part:GetAttribute("Mineable") then
		part:SetAttribute("Mineable", nil)
	end
	-- Watch for PickAxeSystem re-tagging by material
	part:GetAttributeChangedSignal("Mineable"):Connect(function()
		if part:GetAttribute("Mineable") and part:GetAttribute("MineableOre") then
			part:SetAttribute("Mineable", nil)
		end
	end)
end

local function tagIronOreInModel(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Iron_Ore" then
			part:SetAttribute("MineableOre", true)
			part:SetAttribute("OreType", "Iron_Ore")
			part:SetAttribute("MineHealth", IRON_HITS)
			part:SetAttribute("MineMaxHealth", IRON_HITS)
			storeOriginal(part)
			protectIronOre(part)
		end
	end
end

-- Watch for islands
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2") then
		task.wait(0.1)
		tagIronOreInModel(child)
	end
end)

for _, child in workspace:GetChildren() do
	if child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2") then
		tagIronOreInModel(child)
	end
end

-- Handle Iron_Ore mining via MineOre event
mineOreEvent.OnServerEvent:Connect(function(player, orePart)
	if not orePart or not orePart:IsA("BasePart") then return end
	if not orePart:GetAttribute("MineableOre") then return end

	-- Check player has Pick-Axe equipped
	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Pick-Axe" then return end

	-- Check distance
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - orePart.Position).Magnitude > MINE_RANGE then return end

	-- Decrease health
	local health = orePart:GetAttribute("MineHealth") or IRON_HITS
	health = health - 1
	orePart:SetAttribute("MineHealth", health)

	-- Play Dig sound on each successful hit
	playDigSound(orePart)

	-- Shrink
	if health > 0 then
		shrinkPart(orePart, health / IRON_HITS, IRON_MIN_SCALE)
		mineOreEvent:FireClient(player, "hit", health)
	else
		-- Destroyed: give Iron_Ore reward
		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		inv.Iron_Ore = (inv.Iron_Ore or 0) + IRON_REWARD

		if _G.SendInventory then
			_G.SendInventory(player)
		end

		mineOreEvent:FireClient(player, "destroyed", IRON_REWARD, "Iron_Ore")

		cleanupPart(orePart)
		orePart:Destroy()
	end
end)

-- Clean up tracking on destroy
workspace.DescendantRemoving:Connect(function(desc)
	cleanupPart(desc)
end)

-- ─── Ensure Iron_Ore exists in player inventories ───
local function ensureIronOre(player)
	task.wait(2)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if inv and inv.Iron_Ore == nil then
		inv.Iron_Ore = 0
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(ensureIronOre, p) end)
for _, p in Players:GetPlayers() do task.spawn(ensureIronOre, p) end
