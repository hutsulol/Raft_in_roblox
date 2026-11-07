-- WeaponCollection.server.lua
-- Per-player backing for the weapon-collection menu (WeaponCollectionMenu.client):
--   • tracks which catalog weapons each player has OBTAINED (выбил) — a folder of
--     StringValues under the player, replicated for free; grant via _G.GrantWeaponObtained.
--   • gates DONATE weapons behind ownsDonateWeapon() — only the owner ever receives them.
--   • GetWeaponCollection RemoteFunction returns the player's visible list { {id, owned}, … }.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("WeaponCollectionCatalog"))

-- ── per-player "obtained" set ──
-- A folder of StringValues (Name = weapon id) under each Player. Replicates to the
-- client automatically and other systems can read it too.
local function obtainedFolder(player)
	local f = player:FindFirstChild("ObtainedWeapons")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ObtainedWeapons"
		f.Parent = player
	end
	return f
end

local function hasObtained(player, id)
	local f = player:FindFirstChild("ObtainedWeapons")
	return f ~= nil and f:FindFirstChild(id) ~= nil
end

Players.PlayerAdded:Connect(obtainedFolder)
for _, p in ipairs(Players:GetPlayers()) do obtainedFolder(p) end

-- Mark a weapon as obtained for a player. Call this from wherever a weapon is awarded
-- (crate/roulette drop, quest reward, etc.) so it stops showing as locked "archive".
_G.GrantWeaponObtained = function(player, id)
	if not player or not Catalog.ById[id] then return end
	local f = obtainedFolder(player)
	if not f:FindFirstChild(id) then
		local v = Instance.new("StringValue")
		v.Name = id
		v.Parent = f
	end
end

-- ── donate ownership hook ──
-- STUB: returns whether `player` owns the donate weapon `id`. Right now it reads a simple
-- attribute (set  player:SetAttribute("Donate_<id>", true)  to test). Wire your real
-- purchase here later — e.g. MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
-- using a passId from the catalog, or a purchased-set in a DataStore.
local function ownsDonateWeapon(player, id)
	return player:GetAttribute("Donate_" .. id) == true
end

-- ── per-player collection snapshot ──
local function getCollectionFor(player)
	local list = {}
	for _, w in ipairs(Catalog.Weapons) do
		local include = true
		if w.donate then
			include = ownsDonateWeapon(player, w.id) -- non-owners never see it at all
		end
		if include then
			local owned = hasObtained(player, w.id)
			if w.donate then owned = true end -- owning the donate = it's yours
			list[#list + 1] = { id = w.id, owned = owned }
		end
	end
	return list
end

-- ── remote ──
local rf = ReplicatedStorage:FindFirstChild("GetWeaponCollection")
if not rf then
	rf = Instance.new("RemoteFunction")
	rf.Name = "GetWeaponCollection"
	rf.Parent = ReplicatedStorage
end
rf.OnServerInvoke = function(player)
	return getCollectionFor(player)
end
