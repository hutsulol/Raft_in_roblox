-- StoneReward3.server.lua
-- Ensures mining rocks always gives exactly 3 stones total
-- PickAxeSystem gives random 1-3, this script tops up to 3

local rs = game:GetService("ReplicatedStorage")

local DESIRED_STONE = 3

local mineRockEvent = rs:WaitForChild("MineRock", 30)
if not mineRockEvent then return end

-- Track stone count before each mine action per player
local preMineStone = {}

mineRockEvent.OnServerEvent:Connect(function(player, rockPart)
	if not rockPart or not rockPart:IsA("BasePart") then return end
	if not rockPart:GetAttribute("Mineable") then return end

	local health = rockPart:GetAttribute("MineHealth") or 5

	-- If rock is about to be destroyed (health = 1, PickAxeSystem will set to 0)
	if health == 1 then
		-- Record current stone count BEFORE PickAxeSystem processes
		local inv = _G.GetInventory and _G.GetInventory(player)
		if inv then
			preMineStone[player] = inv.Stone or 0
		end

		-- Wait for PickAxeSystem to process and add its random amount
		task.defer(function()
			task.wait(0.1)
			local inv2 = _G.GetInventory and _G.GetInventory(player)
			if inv2 and preMineStone[player] then
				local stoneAdded = (inv2.Stone or 0) - preMineStone[player]
				local deficit = DESIRED_STONE - stoneAdded

				if deficit > 0 then
					inv2.Stone = (inv2.Stone or 0) + deficit
					if _G.SendInventory then
						_G.SendInventory(player)
					end
				end
			end
			preMineStone[player] = nil
		end)
	end
end)
