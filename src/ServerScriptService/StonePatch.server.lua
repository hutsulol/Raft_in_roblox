-- StonePatch.server.lua
-- 1) Fixes rock tagging: only parts named "Rock" in islands should be mineable
-- 2) Ensures mining always gives exactly 3 stones
-- Runs after PickAxeSystem and continuously watches for bad tags

local ISLAND_NAMES = { Island_1 = true, Island_2 = true }

-- ─── Fix tags on an island: only "Rock" parts should be Mineable ───
local function fixIslandTags(island)
	for _, part in island:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "Rock" then
				-- Ensure it IS tagged
				if not part:GetAttribute("Mineable") then
					part:SetAttribute("Mineable", true)
					part:SetAttribute("MineHealth", 5)
				end
			else
				-- Remove tag from anything NOT named "Rock"
				if part:GetAttribute("Mineable") then
					part:SetAttribute("Mineable", nil)
					part:SetAttribute("MineHealth", nil)
				end
			end
		end
	end
end

-- ─── Watch for attribute changes: if PickAxeSystem re-tags, we re-fix ───
local function watchIslandParts(island)
	for _, part in island:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Rock" then
			part:GetAttributeChangedSignal("Mineable"):Connect(function()
				if part:GetAttribute("Mineable") then
					part:SetAttribute("Mineable", nil)
					part:SetAttribute("MineHealth", nil)
				end
			end)
		end
	end
end

-- ─── Setup island ───
local function setupIsland(island)
	-- Wait longer than PickAxeSystem (0.1s) to override its tags
	task.wait(0.3)
	fixIslandTags(island)
	watchIslandParts(island)
end

-- Watch for new islands
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end)

-- Fix existing islands
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end

-- ═══════════════════════════════════════════════════════
-- Fix stone reward: ensure exactly 3 stones per rock mined
-- ═══════════════════════════════════════════════════════
local rs = game:GetService("ReplicatedStorage")
local mineRockEvent = rs:WaitForChild("MineRock", 30)
if not mineRockEvent then return end

local STONE_PER_ROCK = 3
local playerStoneSnapshot = {}

mineRockEvent.OnServerEvent:Connect(function(player, rockPart)
	if not rockPart or not rockPart:IsA("BasePart") then return end
	if not rockPart:GetAttribute("Mineable") then return end

	local health = rockPart:GetAttribute("MineHealth") or 1

	-- Only act when rock is about to die (health = 1, PickAxeSystem will bring to 0)
	if health <= 1 then
		-- Snapshot stone before PickAxeSystem processes
		local inv = _G.GetInventory and _G.GetInventory(player)
		if inv then
			playerStoneSnapshot[player] = inv.Stone or 0
		end

		-- Wait for PickAxeSystem to finish processing
		task.defer(function()
			task.wait(0.15)
			local inv2 = _G.GetInventory and _G.GetInventory(player)
			if inv2 and playerStoneSnapshot[player] ~= nil then
				local before = playerStoneSnapshot[player]
				local current = inv2.Stone or 0
				local given = current - before
				local needed = STONE_PER_ROCK - given

				if needed > 0 then
					inv2.Stone = current + needed
					if _G.SendInventory then
						_G.SendInventory(player)
					end
				end
			end
			playerStoneSnapshot[player] = nil
		end)
	end
end)
