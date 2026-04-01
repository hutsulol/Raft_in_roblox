-- RockShrinkFix.server.lua
-- 10 hits to mine, shrinks from 100% to 50%, stays grounded

local TOTAL_HITS = 10
local MIN_SCALE = 0.5

local ISLAND_NAMES = { Island_1 = true, Island_2 = true }

local rockData = {}

local function setupRock(rockPart)
	if not rockPart:IsA("BasePart") then return end
	if rockData[rockPart] then return end

	task.wait(0.2)
	if not rockPart:GetAttribute("Mineable") then return end

	local origSize = rockPart.Size
	local bottomY = rockPart.Position.Y - origSize.Y / 2

	rockData[rockPart] = {
		origSize = origSize,
		bottomY = bottomY,
	}

	rockPart:SetAttribute("MineHealth", TOTAL_HITS)

	rockPart:GetAttributeChangedSignal("MineHealth"):Connect(function()
		local health = rockPart:GetAttribute("MineHealth")
		if not health or health <= 0 then
			rockData[rockPart] = nil
			return
		end

		local data = rockData[rockPart]
		if not data then return end

		local fraction = (health - 1) / (TOTAL_HITS - 1)
		local scale = MIN_SCALE + fraction * (1 - MIN_SCALE)

		local newSize = data.origSize * scale
		rockPart.Size = newSize

		local newY = data.bottomY + newSize.Y / 2
		rockPart.Position = Vector3.new(rockPart.Position.X, newY, rockPart.Position.Z)
	end)

	rockPart.Destroying:Connect(function()
		rockData[rockPart] = nil
	end)
end

local function setupIsland(island)
	task.wait(0.4)
	for _, child in island:GetDescendants() do
		if child.Name == "Rock" and child:IsA("BasePart") then
			setupRock(child)
		end
	end
end

workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end)

for _, child in workspace:GetChildren() do
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		task.spawn(setupIsland, child)
	end
end
