-- DailyQuests.server.lua
-- Generates and tracks the daily quest list shown in the phone menu.
--
-- Design notes
-- ============
--   * Quests are rolled once per real-world UTC day per player. If a
--     player joins again on the same date they see the SAME quest list
--     with their saved progress — not a freshly-rolled one.
--   * Each day a random 2 or 3 quests are picked (without repeats) from
--     the pool below. The more quests the better the XP reward.
--   * Every daily reward grants 2 iron ingots on top of the XP.
--
-- Persistence
-- ===========
--   Saved in a DataStore keyed by `v1_<userId>_<YYYYMMDD>`. The value is
--   a plain table:
--
--     {
--         questIds = { "logs", "stones", "iron" },
--         progress = { logs = 2, stones = 0, iron = 0 },
--         claimed  = false,
--         rewardXP = 50,
--         rewardIronIngots = 2,
--     }
--
--   Progress is autosaved a few seconds after it changes (debounced) so
--   we don't hammer the DataStore on every single resource pickup.
--
-- Replication
-- ===========
--   A `DailyQuests` Folder is created on each Player with one child
--   Folder per quest. The phone-menu client can read this folder and
--   subscribe to its IntValues the same way it already reads
--   Characteristics. The folder also exposes the reward and claimed
--   state via IntValues / a BoolValue so the menu can enable the
--   "Claim" button when every quest is complete.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

-- ─── DataStore ─────────────────────────────────────────────────────────
local questStore = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("DailyQuests_v1")
	end)
	if ok then
		questStore = result
	else
		warn("[DailyQuests] Failed to get DataStore: " .. tostring(result))
	end
end

local function storeKey(userId, dateStr)
	return "v1_" .. userId .. "_" .. dateStr
end

-- ─── Quest pool ────────────────────────────────────────────────────────
-- `resource` is the key inside the player's inventory that the progress
-- tracker watches. `target` is the amount that has to be gained. The
-- label is what the phone menu displays verbatim.
local QUEST_POOL = {
	{ id = "logs",    label = "Collect 5 logs",    resource = "Log",        target = 5 },
	{ id = "plastic", label = "Collect 5 plastic", resource = "Plastic",    target = 5 },
	{ id = "leaves",  label = "Collect 5 leaves",  resource = "Leaves",     target = 5 },
	{ id = "sand",    label = "Collect 2 sand",    resource = "Sand",       target = 2 },
	{ id = "stones",  label = "Collect 3 stones",  resource = "Stone",      target = 3 },
	{ id = "iron",    label = "Smelt 2 iron",      resource = "Iron_Ingot", target = 2 },
}

local QUEST_BY_ID = {}
for _, q in QUEST_POOL do
	QUEST_BY_ID[q.id] = q
end

-- ─── Roll helpers ──────────────────────────────────────────────────────

local MIN_QUESTS = 2
local MAX_QUESTS = 3

-- XP reward table — picked based on how many quests were rolled.
-- 2 quests get a random value from the "low" list, 3 quests always get
-- the top-tier reward. Every day also grants IRON_INGOT_REWARD iron
-- ingots on top of the XP regardless of count.
local XP_REWARDS_BY_COUNT = {
	[2] = { 10, 20 },
	[3] = { 50 },
}
local IRON_INGOT_REWARD = 2

-- Use UTC so the day boundary is the same for every player regardless
-- of where they live. `%Y%m%d` → e.g. "20260411".
local function todayDateString()
	return os.date("!%Y%m%d", os.time())
end

local function rollXPReward(questCount)
	local options = XP_REWARDS_BY_COUNT[questCount] or { 10 }
	return options[math.random(1, #options)]
end

local function rollQuestIds()
	-- Shuffle the pool indices and pick the first N entries.
	local indices = {}
	for i = 1, #QUEST_POOL do indices[i] = i end
	for i = #indices, 2, -1 do
		local j = math.random(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end

	local count = math.random(MIN_QUESTS, MAX_QUESTS)
	count = math.min(count, #QUEST_POOL)

	local ids = {}
	for i = 1, count do
		ids[i] = QUEST_POOL[indices[i]].id
	end
	return ids
end

local function generateDailySave()
	local questIds = rollQuestIds()
	local progress = {}
	for _, id in questIds do
		progress[id] = 0
	end
	return {
		questIds          = questIds,
		progress          = progress,
		claimed           = false,
		rewardXP          = rollXPReward(#questIds),
		rewardIronIngots  = IRON_INGOT_REWARD,
	}
end

-- ─── Per-player state ──────────────────────────────────────────────────

-- Everything we need to keep in memory for a live player:
--   date       : the YYYYMMDD string the current save belongs to
--   save       : the table that's mirrored to the DataStore
--   folder     : the replicated DailyQuests folder on the player
--   questFolders : map[id] -> Folder inside `folder` for that quest
--   inventory  : last-seen snapshot of the player's inventory counts
--                 so we can detect positive deltas from _G.SendInventory
--   saveDirty  : true when progress changed and hasn't been flushed yet
--   lastSaveAt : tick() when we last wrote to the DataStore
local state = {}

local AUTOSAVE_DEBOUNCE = 5 -- seconds between DataStore writes per player

local function markDirty(player)
	local s = state[player]
	if s then s.saveDirty = true end
end

-- ─── Folder replication ────────────────────────────────────────────────

local function stringValue(name, value, parent)
	local v = Instance.new("StringValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function intValue(name, value, parent)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function boolValue(name, value, parent)
	local v = Instance.new("BoolValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function buildFolder(player, save)
	-- Remove any previous DailyQuests folder so a new day wipes the
	-- stale UI state cleanly.
	local existing = player:FindFirstChild("DailyQuests")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "DailyQuests"

	stringValue("Date",             todayDateString(),      folder)
	intValue("RewardXP",            save.rewardXP or 0,     folder)
	intValue("RewardIronIngots",    save.rewardIronIngots or 0, folder)
	boolValue("Claimed",            save.claimed and true or false, folder)
	intValue("QuestCount",          #save.questIds,         folder)

	local questFolders = {}
	for i, id in save.questIds do
		local def = QUEST_BY_ID[id]
		if def then
			local qFolder = Instance.new("Folder")
			qFolder.Name = "Quest_" .. id
			stringValue("Id",        id,             qFolder)
			stringValue("Label",     def.label,      qFolder)
			stringValue("Resource",  def.resource,   qFolder)
			intValue("Target",       def.target,     qFolder)
			intValue("Progress",     save.progress[id] or 0, qFolder)
			boolValue("Completed",   (save.progress[id] or 0) >= def.target, qFolder)
			intValue("Order",        i,              qFolder)
			qFolder.Parent = folder
			questFolders[id] = qFolder
		end
	end

	folder.Parent = player
	return folder, questFolders
end

-- Push the current save table back into the replicated folder. Called
-- whenever progress or claimed state changes so the client sees the
-- update without us rebuilding the folder every time.
local function syncFolder(player)
	local s = state[player]
	if not s or not s.folder then return end
	local save = s.save

	local claimed = s.folder:FindFirstChild("Claimed")
	if claimed then claimed.Value = save.claimed and true or false end

	for id, qFolder in s.questFolders do
		local def = QUEST_BY_ID[id]
		if def then
			local cur = save.progress[id] or 0
			local progressVal = qFolder:FindFirstChild("Progress")
			if progressVal then progressVal.Value = cur end
			local completedVal = qFolder:FindFirstChild("Completed")
			if completedVal then completedVal.Value = cur >= def.target end
		end
	end
end

-- ─── Save / load ───────────────────────────────────────────────────────

local function readSave(userId, dateStr)
	if not questStore then return nil end
	local ok, value = pcall(function()
		return questStore:GetAsync(storeKey(userId, dateStr))
	end)
	if not ok then
		warn("[DailyQuests] GetAsync failed: " .. tostring(value))
		return nil
	end
	return value
end

local function writeSave(userId, dateStr, save)
	if not questStore then return end
	local ok, err = pcall(function()
		questStore:SetAsync(storeKey(userId, dateStr), save)
	end)
	if not ok then
		warn("[DailyQuests] SetAsync failed: " .. tostring(err))
	end
end

-- Validates a save table loaded from the DataStore. The quest pool is
-- allowed to change between deploys, so a save with an unknown quest id
-- is rejected — the player just gets a freshly rolled list for today.
local function validateSave(save)
	if typeof(save) ~= "table" then return false end
	if typeof(save.questIds) ~= "table" then return false end
	if #save.questIds < MIN_QUESTS or #save.questIds > MAX_QUESTS then return false end
	for _, id in save.questIds do
		if not QUEST_BY_ID[id] then return false end
	end
	if typeof(save.progress) ~= "table" then return false end
	return true
end

-- ─── Progress tracking ─────────────────────────────────────────────────
-- Instead of tracking inventory deltas (which would incorrectly count
-- dropped-item pickups, crafting side-effects, etc.), we expose a
-- dedicated `_G.OnQuestResource(player, resource, amount)` callback.
-- Only code paths that represent genuine gathering (sea collection,
-- mining, digging, smelting, fishing) call this function, so quest
-- progress accurately reflects real gameplay actions.

local function onQuestResource(player, resource, amount)
	local s = state[player]
	if not s then return end
	if type(resource) ~= "string" then return end
	amount = (type(amount) == "number" and amount > 0) and amount or 1

	local changed = false

	for _, id in s.save.questIds do
		local def = QUEST_BY_ID[id]
		if def and def.resource == resource then
			local prog = s.save.progress[id] or 0
			if prog < def.target then
				s.save.progress[id] = math.min(def.target, prog + amount)
				changed = true
			end
		end
	end

	if changed then
		syncFolder(player)
		markDirty(player)
	end
end

_G.OnQuestResource = onQuestResource

-- ─── Player lifecycle ──────────────────────────────────────────────────

local function loadForPlayer(player)
	local dateStr = todayDateString()

	local save = readSave(player.UserId, dateStr)
	if not validateSave(save) then
		save = generateDailySave()
		writeSave(player.UserId, dateStr, save)
	end

	local folder, questFolders = buildFolder(player, save)

	state[player] = {
		date         = dateStr,
		save         = save,
		folder       = folder,
		questFolders = questFolders,
		saveDirty    = false,
		lastSaveAt   = tick(),
	}
end

local function unloadForPlayer(player)
	local s = state[player]
	if not s then return end
	if s.saveDirty then
		writeSave(player.UserId, s.date, s.save)
	end
	state[player] = nil
end

for _, p in Players:GetPlayers() do
	task.spawn(loadForPlayer, p)
end
Players.PlayerAdded:Connect(loadForPlayer)
Players.PlayerRemoving:Connect(unloadForPlayer)
game:BindToClose(function()
	for player in state do
		unloadForPlayer(player)
	end
end)

-- ─── Debounced autosave ────────────────────────────────────────────────
-- Writes every dirty save at most once per AUTOSAVE_DEBOUNCE seconds so
-- rapid inventory pickups don't flood the DataStore.
task.spawn(function()
	while true do
		task.wait(1)
		local now = tick()
		for player, s in state do
			if s.saveDirty and (now - s.lastSaveAt) >= AUTOSAVE_DEBOUNCE then
				s.saveDirty  = false
				s.lastSaveAt = now
				-- Fire-and-forget: the actual DataStore call happens on
				-- a separate thread so the loop keeps ticking.
				task.spawn(writeSave, player.UserId, s.date, s.save)
			end
		end
	end
end)

-- ─── Date rollover ─────────────────────────────────────────────────────
-- When the real-world UTC day flips, reroll every online player so they
-- immediately see their new quest list without having to reconnect.
task.spawn(function()
	while true do
		task.wait(30)
		local today = todayDateString()
		for player, s in state do
			if s.date ~= today then
				unloadForPlayer(player)
				loadForPlayer(player)
			end
		end
	end
end)

-- ─── Claim reward ──────────────────────────────────────────────────────
-- Listens on the shared PhoneMenuAction RemoteEvent for the
-- "claimDailyReward" action. Grants the player their XP (via the
-- Characteristics.XP IntValue, which Characteristics.server.lua
-- re-uses to level the player) and stacks the iron-ingot reward into
-- the gameplay inventory through _G.GetInventory / _G.SendInventory.
local phoneMenuEvent = ReplicatedStorage:WaitForChild("PhoneMenuAction")

local function allQuestsComplete(save)
	for _, id in save.questIds do
		local def = QUEST_BY_ID[id]
		if not def then return false end
		if (save.progress[id] or 0) < def.target then
			return false
		end
	end
	return #save.questIds > 0
end

local function grantRewards(player, save)
	-- XP goes through the Characteristics folder's XP IntValue so
	-- Characteristics.server.lua's level-up loop handles any level
	-- gains automatically.
	local chFolder = player:FindFirstChild("Characteristics")
	if chFolder then
		local xp = chFolder:FindFirstChild("XP")
		if xp and save.rewardXP and save.rewardXP > 0 then
			xp.Value = xp.Value + save.rewardXP
		end
	end

	-- Iron ingots go into the gameplay inventory via the existing
	-- _G.GetInventory / _G.SendInventory hooks (same path Furnace
	-- smelting uses).
	if save.rewardIronIngots and save.rewardIronIngots > 0 then
		local getInv = _G.GetInventory
		local sendInv = _G.SendInventory
		if getInv then
			local inv = getInv(player)
			if inv then
				inv.Iron_Ingot = (inv.Iron_Ingot or 0) + save.rewardIronIngots
				if sendInv then sendInv(player) end
			end
		end
	end
end

phoneMenuEvent.OnServerEvent:Connect(function(player, action)
	if action == "claimDailyReward" then
		local s = state[player]
		if not s then return end
		if s.save.claimed then return end
		if not allQuestsComplete(s.save) then return end

		s.save.claimed = true
		grantRewards(player, s.save)
		syncFolder(player)

		-- Claiming is a meaningful milestone — flush it to the DataStore
		-- immediately so a crash or rejoin can't un-claim the reward.
		s.saveDirty  = false
		s.lastSaveAt = tick()
		task.spawn(writeSave, player.UserId, s.date, s.save)

	elseif action == "resetQuests" then
		-- DEV / testing: reroll quests as if a new day started. Wipes
		-- current progress and generates a fresh quest list.
		unloadForPlayer(player)
		local save = generateDailySave()
		local dateStr = todayDateString()
		writeSave(player.UserId, dateStr, save)
		local folder, questFolders = buildFolder(player, save)
		state[player] = {
			date         = dateStr,
			save         = save,
			folder       = folder,
			questFolders = questFolders,
			saveDirty    = false,
			lastSaveAt   = tick(),
		}
	end
end)
