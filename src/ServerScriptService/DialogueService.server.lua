-- DialogueService.server.lua
-- СЕРВЕРНАЯ ЧАСТЬ ДИАЛОГОВ: запуск окна у нужного игрока и ВЫДАЧА НАГРАД.
--
-- Реплики и тексты живут в ReplicatedStorage.DialogueDefs (их читают обе стороны),
-- но награда выдаётся ТОЛЬКО здесь и только после сверки с этими же данными:
-- клиент сообщает «я дошёл до реплики N», сервер сам смотрит, что у неё в rewards.
-- Плюс защёлка «этот диалог уже награждал этого игрока» — иначе тем же пакетом
-- можно было бы выпросить топор сколько угодно раз.
--
-- Запуск из любого места:  _G.StartDialogue(player, "MechanicIntro")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage:WaitForChild("DialogueDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local remote = ReplicatedStorage:FindFirstChild("DialogueEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "DialogueEvent"
	remote.Parent = ReplicatedStorage
end

-- [player] = { ["MechanicIntro:6"] = true } — что уже выдано
local claimed = {}
Players.PlayerRemoving:Connect(function(plr) claimed[plr] = nil end)

-- ── выдача одной награды ──
local function grant(player, reward)
	if reward.tool then
		local tpl = AssetFind.find(reward.tool)
		if not tpl or not tpl:IsA("Tool") then
			warn(("[Dialogue] Tool «%s» не найден в ReplicatedStorage — награда не выдана"):format(reward.tool))
			return false
		end
		local tool = tpl:Clone()
		-- ⚠️ НЕ ВЫПАДАТЬ ПРИ СМЕРТИ. Награда часто приходит игроку прямо в руки, а
		-- Roblox при смерти выбрасывает то, что в руках, на землю — топор от механика
		-- так и терялся: в рюкзак он не возвращался, а слепок KeepToolsOnDeath уже не
		-- заставал его ни в руках, ни в рюкзаке.
		tool.CanBeDropped = false
		if _G.GiveToolOrDrop then
			_G.GiveToolOrDrop(player, tool)   -- в хотбар, а если места нет — дропом под ноги
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
		if _G.SendInventory then _G.SendInventory(player) end
		return true

	elseif reward.resource then
		if _G.AddResourceToInventory then
			_G.AddResourceToInventory(player, reward.resource, reward.count or 1)
			if _G.SendInventory then _G.SendInventory(player) end
			return true
		end
		warn("[Dialogue] _G.AddResourceToInventory не найден — ресурс не выдан")
		return false
	end
	return false
end

-- ── клиент дошёл до реплики: проверяем и выдаём ──
remote.OnServerEvent:Connect(function(player, action, key, lineIndex, optionIndex)
	--[[ «ЗАБРАТЬ НАГРАДУ» — кнопка-вариант в диалоге с полем claim. Что выдать,
	     решает подписчик _G.OnDialogueClaim(player, key, claim) — сюжет
	     (MerchantStory). Один раз за сессию на реплику. ]]
	if action == "claim" then
		local dialogue = Defs.dialogues[key]
		local line = dialogue and dialogue.lines[tonumber(lineIndex) or 0]
		local opt = line and line.options and line.options[tonumber(optionIndex) or 0]
		if not (opt and opt.claim) then return end
		local tag = "claim:" .. key .. ":" .. tostring(lineIndex)
		claimed[player] = claimed[player] or {}
		if claimed[player][tag] then return end
		claimed[player][tag] = true
		--[[ ⚠️ «ЗАБРАЛ» ЗАСЧИТЫВАЕМ, ТОЛЬКО ЕСЛИ ВЫДАЧА ПРОШЛА (обработчик вернул true).
		     Раньше отметка ставилась до выдачи: сюжет отказал (не тот этап) — и
		     награда за реплику была потеряна до конца сессии, повтор не работал. ]]
		local ok, res = false, nil
		if typeof(_G.OnDialogueClaim) == "function" then ok, res = pcall(_G.OnDialogueClaim, player, key, opt.claim) end
		if not (ok and res == true) then
			claimed[player][tag] = nil
			warn(("[Dialogue] награда «%s» для %s не выдана: %s"):format(tostring(opt.claim), player.Name, tostring(res)))
		end
		return
	end
	if action ~= "reward" then return end
	local dialogue = Defs.dialogues[key]
	if not dialogue then return end
	local line = dialogue.lines[tonumber(lineIndex) or 0]
	if not line or not line.rewards then return end   -- у этой реплики наград нет

	local tag = key .. ":" .. tostring(lineIndex)
	claimed[player] = claimed[player] or {}
	if claimed[player][tag] then return end           -- уже получал
	claimed[player][tag] = true

	local given = {}
	for _, reward in ipairs(line.rewards) do
		if grant(player, reward) then
			table.insert(given, reward.name or reward.tool or reward.resource)
		end
	end
	if #given > 0 then
		print(("[Dialogue] %s: %s → %s"):format(player.Name, key, table.concat(given, ", ")))
	end
end)

-- ── запуск диалога ──
_G.StartDialogue = function(player, key)
	if not player or not player.Parent then return false, "нет игрока" end
	if not Defs.dialogues[key] then return false, "нет диалога " .. tostring(key) end
	remote:FireClient(player, "start", key)
	return true
end

--[[ ДИАЛОГ, СОБРАННЫЙ НА ЛЕТУ (без записи в DialogueDefs): реплики зависят от
     положения дел — фермер говорит про корыто, кормушку, овец. Окно то же, что
     у квестов (портрет, печать текста, «Далее»), наград нет.
     data = { npcName = "Фермер", npcModel = <Model в Workspace>, lines = { { who = "npc", text = "…" }, … } } ]]
_G.StartCustomDialogue = function(player, data)
	if not player or not player.Parent then return false, "нет игрока" end
	if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return false, "нет реплик" end
	remote:FireClient(player, "custom", data)
	return true
end

print("[Dialogue] ready (_G.StartDialogue, _G.StartCustomDialogue)")
