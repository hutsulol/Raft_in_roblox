--[[ СТОРОЖ КВЕСТА «МЕСТО ДЛЯ ВЕЩЕЙ» (storage_box).
     InventoryManager ставит игроку атрибут InventoryFullOnce, когда рюкзак
     впервые забит или что-то в него уже не влезло. Здесь по этому атрибуту:
     мысль StorageThought («В инвентаре уже нет места…») и следом квест на
     крафт малого контейнера. Пройденный квест второй раз не открываем. ]]
local Players = game:GetService("Players")

local QUEST_ID = "storage_box"
local THOUGHT  = "StorageThought"
local ATTR     = "InventoryFullOnce"
local LOG      = "[Квест/ящик]"

local function alreadyDone(player)
	local state = typeof(_G.GetQuestState) == "function" and _G.GetQuestState(player) or nil
	if type(state) ~= "table" then return false end
	if state.permanentlyCompleted and state.permanentlyCompleted[QUEST_ID] then return true end
	if state.unlocked and state.unlocked[QUEST_ID] then return true end
	return false
end

local function trigger(player)
	if not (player and player.Parent) then return end
	if alreadyDone(player) then return end
	if _G.StartDialogue then pcall(_G.StartDialogue, player, THOUGHT) end
	task.wait(1.5)
	if not player.Parent then return end
	if typeof(_G.TrackQuest) == "function" then
		pcall(_G.TrackQuest, player, QUEST_ID)
		print(LOG .. " " .. player.Name .. ": рюкзак впервые забит — выдан квест " .. QUEST_ID)
	else
		warn(LOG .. " _G.TrackQuest не найден — квест не выдан")
	end
end

local function watch(player)
	if player:GetAttribute(ATTR) then task.spawn(trigger, player) end
	player:GetAttributeChangedSignal(ATTR):Connect(function()
		if player:GetAttribute(ATTR) then task.spawn(trigger, player) end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do watch(p) end
print(LOG .. " следит: первое переполнение рюкзака → мысль и квест про контейнер")
