-- FoliageNoQuery.server.lua
-- Decoration meshes on the islands (tall grass, ferns, leaf tufts)
-- physically sit between the camera and items the player drops on the
-- floor — so the pickup raycast in DropItem.client.lua hits the grass
-- mesh first and reports "nothing pickable here" even though a Stone
-- or crate is clearly visible inside the grass.
--
-- These decoration parts are already non-collidable so the player
-- walks straight through them. We simply mirror that for raycast
-- queries: any non-collidable BasePart inside an island model has
-- CanQuery flipped to false. The existing single-shot raycast in
-- DropItem.client.lua then passes through the foliage and lands on
-- the dropped item behind it without any UI-side changes.
--
-- Solid geometry (rocks, terrain, raft floor) keeps CanCollide=true
-- and is untouched — those should still block the raycast as before.

local SCAN_DELAY = 0.15  -- let IslandSpawner finish anchoring + parenting

local function disableQueryOnFoliage(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.CanCollide then
			part.CanQuery = false
		end
	end
end

local function isIsland(child)
	return child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2")
end

workspace.ChildAdded:Connect(function(child)
	if not isIsland(child) then return end
	task.wait(SCAN_DELAY)
	if child.Parent then
		disableQueryOnFoliage(child)
	end
end)

for _, child in workspace:GetChildren() do
	if isIsland(child) then
		disableQueryOnFoliage(child)
	end
end
