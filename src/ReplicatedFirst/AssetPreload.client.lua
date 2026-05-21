-- AssetPreload.client.lua
-- Lives in ReplicatedFirst, which runs BEFORE every other client
-- script — its yields happen during the default Roblox loading
-- screen rather than after the player spawns. By the time the
-- inventory UI / SandBag UI ever read a stage asset, the texture is
-- already cached in ContentProvider.
--
-- Add new assets here whenever a feature needs zero-flicker first
-- render. The list is intentionally just IDs (no per-feature import
-- to avoid yielding waits for downstream modules).

local ContentProvider = game:GetService("ContentProvider")

local ASSETS = {
	-- Sand Bag, sand-content stage textures.
	"rbxassetid://107012847180882",  -- 0 % (empty, shared with clay)
	"rbxassetid://87535824644391",   -- 10 % sand
	"rbxassetid://102984915310557",  -- 30 % sand
	"rbxassetid://132918131694676",  -- 50 % sand
	"rbxassetid://135545427179049",  -- 70 % sand
	"rbxassetid://76170913773356",   -- 100 % sand

	-- Sand Bag, clay-content stage textures.
	"rbxassetid://137121316772176",  -- 10 % clay
	"rbxassetid://94079996711573",   -- 30 % clay
	"rbxassetid://71260002598684",   -- 50 % clay
	"rbxassetid://85470636629483",   -- 70 % clay
	"rbxassetid://115968010442225",  -- 100 % clay

	-- Shared close-button art (used by QuestMenu + SandBagUI).
	"rbxassetid://76127527205295",
}

-- PreloadAsync is synchronous (yields). If we ran it inline here
-- in ReplicatedFirst we'd block the boot path on a dozen texture
-- downloads — adding seconds to the post-teleport black screen
-- before the player can actually interact. Spawn it instead so
-- the assets warm up in the background while the world loads.
-- Worst case the first SandBag open arrives a frame ahead of the
-- cache and the icon pops in; the trade-off is worth the much
-- snappier teleport.
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(ASSETS)
	end)
end)
