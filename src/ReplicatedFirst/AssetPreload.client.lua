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
	-- Sand Bag stage textures (must match SandBagUI.client.lua's
	-- FILL_STAGES and InventoryUI.client.lua's SAND_BAG_STAGES).
	"rbxassetid://107012847180882",  -- 0 % (empty)
	"rbxassetid://87535824644391",   -- 10 %
	"rbxassetid://102984915310557",  -- 30 %
	"rbxassetid://132918131694676",  -- 50 %
	"rbxassetid://135545427179049",  -- 70 %
	"rbxassetid://76170913773356",   -- 100 %

	-- Shared close-button art (used by QuestMenu + SandBagUI).
	"rbxassetid://76127527205295",
}

-- PreloadAsync is synchronous (yields). Running it here in
-- ReplicatedFirst means the asset fetch happens during the loading
-- screen — the player can't see the hotbar / open a bag until this
-- returns. pcall guards against a single bad ID failing the whole
-- batch.
pcall(function()
	ContentProvider:PreloadAsync(ASSETS)
end)
