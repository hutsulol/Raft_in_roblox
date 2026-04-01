-- RockTagFixer.server.lua
-- Fixes rock tagging: removes Mineable from non-rock parts, keeps only parts named "Rock"
-- Runs after PickAxeSystem tags everything by material (which is too aggressive)

local ISLAND_NAMES = { Island_1 = true, Island_2 = true }

local function fixIslandTags(island)
	for _, part in island:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "Rock" then
				-- Ensure rocks ARE tagged
				part:SetAttribute("Mineable", true)
				if not part:GetAttribute("MineHealth") then
					part:SetAttribute("MineHealth", 5)
				end
			else
				-- Remove Mineable from everything that is NOT named Rock
				if part:GetAttribute("Mineable") then
					part:SetAttribute("Mineable", nil)
					part:SetAttribute("MineHealth", nil)
				end
			end
		end
	end
end

-- Watch for new islands
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		-- Wait a bit longer than PickAxeSystem to override its tags
		task.wait(0.5)
		fixIslandTags(child)
	end
end)

-- Fix existing islands
task.wait(1)
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and ISLAND_NAMES[child.Name] then
		fixIslandTags(child)
	end
end
