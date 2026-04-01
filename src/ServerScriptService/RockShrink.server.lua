-- RockShrink.server.lua
-- Overrides rock mining to 10 hits with progressive shrinking
-- Stores original size and scales down linearly each hit

local TOTAL_HITS = 10
local MIN_SCALE = 0.1 -- 10% of original size at last hit

local ISLAND_NAMES = { Island_1 = true, Island_2 = true }

-- Store original sizes
local originalSizes = {}

local function setupRock(rockPart)
	if not rockPart:IsA("BasePart") then return end
	if originalSizes[rockPart] then return end -- already set up

	-- Wait for PickAxeSystem to tag it first
	task.wait(0.2)
	if not rockPart:GetAttribute("Mineable") then return end

	-- Store original size
	originalSizes[rockPart] = rockPart.Size

	-- Override health to 10
	rockPart:SetAttribute("MineHealth", TOTAL_HITS)

	-- Watch for health changes and scale accordingly
	rockPart:GetAttributeChangedSignal("MineHealth"):Connect(function()
		local health = rockPart:GetAttribute("MineHealth")
		if not health or health <= 0 then
			originalSizes[rockPart] = nil
			return
		end

		local origSize = originalSizes[rockPart]
		if not origSize then return end

		-- Scale from 1.0 (full health) down to MIN_SCALE (1 health)
		-- health goes from TOTAL_HITS down to 1
		local fraction = (health - 1) / (TOTAL_HITS - 1) -- 1.0 at full, 0.0 at 1 hit left
		local scale = MIN_SCALE + fraction * (1 - MIN_SCALE)

		rockPart.Size = origSize * scale
	end)

	-- Clean up when destroyed
	rockPart.Destroying:Connect(function()
		originalSizes[rockPart] = nil
	end)
end

local function setupIsland(island)
	task.wait(0.4) -- after PickAxeSystem tags at 0.1s
	for _, child in island:GetDescendants() do
		if child.Name == "Rock" and child:IsA("BasePart") then
			setupRock(child)
		end
	end
end

-- Watch for new islands
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end)

-- Setup existing islands
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end
