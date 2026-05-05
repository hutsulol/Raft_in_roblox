-- MercenarySkin.server.lua
-- Owned-skin persistence + equip RemoteEvent for the wardrobe page.
--
-- Mirrors MercenaryEquipment's pattern:
--   - per-player UnlockedSkins folder (StringValue children, replicated)
--   - per-merc EquippedSkin attribute on player.Mercenaries.<MercName>
--   - RemoteEvent "MercenarySkin" with actions:
--        getState (no args)  → server replies "state" with snapshot
--        equip    (mercName, skinId)
--
-- The snapshot is a single packet shaped like:
--   { ownedSkins = { skinId = true, ... },
--     equipped   = { mercName = skinId, ... }, }
-- so the client can repaint the whole wardrobe + detail panel from one
-- payload.
--
-- Skin application to live spawned mercs is folded in here too — when a
-- player equips, every SpawnedMercenary tagged model owned by them gets
-- its Shirt/Pants swapped in place so the change is visible without a
-- respawn.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local skinEvent = Instance.new("RemoteEvent")
skinEvent.Name = "MercenarySkin"
skinEvent.Parent = ReplicatedStorage

-- Wait briefly for SkinCatalog. It's a sibling Script that runs on the
-- same boot, but ordering isn't guaranteed; spin a short loop so this
-- file can survive being loaded first.
local function getCatalog()
	if _G.SkinCatalog then return _G.SkinCatalog end
	local deadline = os.clock() + 5
	while os.clock() < deadline do
		if _G.SkinCatalog then return _G.SkinCatalog end
		task.wait(0.1)
	end
	return _G.SkinCatalog
end

-- ─── Per-player UnlockedSkins folder ─────────────────────────────────

local function ensureFolder(player)
	local folder = player:FindFirstChild("UnlockedSkins")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "UnlockedSkins"
		folder.Parent = player
	end
	-- Grant every catalog entry flagged ownedByDefault. This is also how
	-- a freshly-recruited Pirate gets at least one skin in the wardrobe.
	local catalog = getCatalog()
	if catalog then
		for id, def in pairs(catalog.all()) do
			if def.ownedByDefault and not folder:FindFirstChild(id) then
				local sv = Instance.new("StringValue")
				sv.Name = id
				sv.Value = id
				sv.Parent = folder
			end
		end
	end
	return folder
end

local function isSkinUnlocked(player, skinId)
	local folder = ensureFolder(player)
	return folder:FindFirstChild(skinId) ~= nil
end

-- ─── Apply skin to a live merc rig (or a freshly-cloned one) ─────────
-- Looks up the catalog entry, finds the matching Shirt + Pants under
-- ReplicatedStorage.Skins, and replaces whatever clothing the rig is
-- currently wearing. Used both:
--   - by the equip handler below (live retro-fit on tagged mercs)
--   - by MercenarySpawner via _G.ApplyMercSkin (fresh clone before
--     parenting to workspace)
local function findSkinsFolder()
	return ReplicatedStorage:FindFirstChild("Skins")
end

local function cloneClothing(skinsFolder, name, classCheck)
	if not skinsFolder then return nil end
	local node = skinsFolder:FindFirstChild(name)
	if not node then return nil end
	if classCheck and not node:IsA(classCheck) then return nil end
	local wasArchivable = node.Archivable
	node.Archivable = true
	local copy = node:Clone()
	node.Archivable = wasArchivable
	return copy
end

local function applySkinToModel(model, skinId)
	local catalog = getCatalog()
	if not (model and skinId and catalog) then return end
	local def = catalog.get(skinId)
	if not def then return end
	local skinsFolder = findSkinsFolder()
	if not skinsFolder then
		warn("[MercenarySkin] ReplicatedStorage.Skins folder missing")
		return
	end

	-- Strip whatever Shirt/Pants the rig is already wearing so we never
	-- end up with two of either class on the same Humanoid.
	for _, child in model:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") then
			child:Destroy()
		end
	end

	local shirt = cloneClothing(skinsFolder, def.shirtName, "Shirt")
	if shirt then shirt.Parent = model end
	local pants = cloneClothing(skinsFolder, def.pantsName, "Pants")
	if pants then pants.Parent = model end
end

-- Exposed for MercenarySpawner to call before clone.Parent = workspace
-- so the rig is born already wearing the right skin.
_G.ApplyMercSkin = applySkinToModel

local function applyToLiveMercs(player, mercName, skinId)
	for _, model in CollectionService:GetTagged("SpawnedMercenary") do
		if model:GetAttribute("OwnerUserId") == player.UserId
			and model:GetAttribute("MercName") == mercName
			and model.Parent then
			applySkinToModel(model, skinId)
		end
	end
end

-- ─── Snapshot push ───────────────────────────────────────────────────

-- Build a flat client-friendly catalog projection. We can't ship the
-- live _G.SkinCatalog tables across RemoteEvent because shipping
-- closures / metatables would break replication, so we re-shape each
-- entry into a plain table the client can iterate directly.
local function buildCatalogPayload()
	local catalog = getCatalog()
	if not catalog then return {} end
	local out = {}
	for id, def in pairs(catalog.all()) do
		out[id] = {
			id          = def.id,
			mercName    = def.mercName,
			displayName = def.displayName,
			rarity      = def.rarity,
			category    = def.category,
			palette     = def.palette,
			setName     = def.setName,
			source      = def.source,
			description = def.description,
		}
	end
	return out
end

local function buildSnapshot(player)
	local owned = {}
	local folder = ensureFolder(player)
	for _, child in folder:GetChildren() do
		owned[child.Name] = true
	end
	local equipped = {}
	local mercFolder = player:FindFirstChild("Mercenaries")
	if mercFolder then
		for _, merc in mercFolder:GetChildren() do
			local cur = merc:GetAttribute("EquippedSkin")
			if typeof(cur) == "string" and cur ~= "" then
				equipped[merc.Name] = cur
			end
		end
	end
	return {
		catalog    = buildCatalogPayload(),
		ownedSkins = owned,
		equipped   = equipped,
	}
end

local function pushState(player)
	skinEvent:FireClient(player, "state", buildSnapshot(player))
end

-- ─── Default-equip on first sight of a merc ─────────────────────────
-- When the player recruits a new merc, set EquippedSkin to that merc's
-- ownedByDefault skin so the wardrobe + spawner have something coherent
-- to render even if the player never opens the menu.
local function ensureDefaultEquipped(mercEntry)
	local catalog = getCatalog()
	if not catalog then return end
	local cur = mercEntry:GetAttribute("EquippedSkin")
	if typeof(cur) == "string" and cur ~= "" then return end
	local def = catalog.defaultForMerc(mercEntry.Name)
	if def then
		mercEntry:SetAttribute("EquippedSkin", def.id)
	end
end

local function watchMercenaries(player)
	local mercFolder = player:FindFirstChild("Mercenaries")
		or player:WaitForChild("Mercenaries", 10)
	if not mercFolder then return end
	mercFolder.ChildAdded:Connect(function(merc)
		ensureDefaultEquipped(merc)
		pushState(player)
	end)
	for _, merc in mercFolder:GetChildren() do
		ensureDefaultEquipped(merc)
	end
end

-- ─── Player setup ────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	ensureFolder(player)
	task.spawn(watchMercenaries, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(function()
		ensureFolder(player)
		watchMercenaries(player)
	end)
end

-- ─── Request handler ────────────────────────────────────────────────

skinEvent.OnServerEvent:Connect(function(player, action, mercName, skinId)
	if typeof(action) ~= "string" then return end

	if action == "getState" then
		pushState(player)
		return
	end

	if action ~= "equip" then return end

	if typeof(mercName) ~= "string" or typeof(skinId) ~= "string" then return end

	local mercFolder = player:FindFirstChild("Mercenaries")
	if not mercFolder then return end
	local mercEntry = mercFolder:FindFirstChild(mercName)
	if not mercEntry then return end

	local catalog = getCatalog()
	if not catalog then return end
	local def = catalog.get(skinId)
	if not def then return end

	-- The skin must (a) exist in the catalog for this merc, (b) be
	-- unlocked for the requesting player. Both checks repeat the
	-- client-side filter so a hand-crafted RemoteEvent can't bypass
	-- the wardrobe gate.
	if def.mercName ~= mercName then return end
	if not isSkinUnlocked(player, skinId) then return end

	mercEntry:SetAttribute("EquippedSkin", skinId)
	applyToLiveMercs(player, mercName, skinId)
	pushState(player)
end)
