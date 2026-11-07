--[[
	ЦЕНА СМЕРТИ: каждая смерть = жизнь команды, при нуле жизней — конец.
	⚠️ ДЕЙСТВУЮЩЕЕ ПРАВИЛО: пиратов не снимаем вовсе, пул 1→3, 2→4, 3→5, 4→6, 5→7.
	Список ниже — прежняя редакция, оставлена для истории.

	Правила владельца:
	  • штраф зависит от дня: до 5-го −50, до 15-го −100, до 30-го −200,
	    до 50-го −300, дальше −500;
	  • пиратов хватает — списываем штраф; меньше штрафа, но больше нуля —
	    списываем всё до нуля, жизнь НЕ тратим; баланс ниже нуля не уходит;
	  • пиратов ноль — тратится ЖИЗНЬ КОМАНДЫ (пул общий на забег, размер от числа
	    игроков: 1→2, 2→3, 3→5, 4→6, 5→7);
	  • жизни кончились — предложение купить экстра-жизнь за Robux; отказ или
	    тишина — забег окончен, все уезжают в лобби.

	Сцены рисует клиент (DeathScreen.client.lua) по хендоффу
	design_handoff_death_screen: сюда летит один RemoteEvent DeathScene с
	таблицей { scene = "penalty"|"death"|"revive"|"lobby", … }.

	⚠️ ЖИЗНИ — ТРИ АТРИБУТА Workspace: TeamMaxPlayers, TeamLivesSpent,
	TeamLivesBonus (все в WS_FLAGS сейва RaftSaveSystem, переживают перезаход).
	TeamLives — производное для показа: пул(игроков) + куплено − потрачено.
	⚠️ ProcessReceipt НА ИГРУ ОДИН (WoodBoostProducts): свой продукт только
	регистрируем в его реестре через _G.RegisterProductHandler.
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace          = game:GetService("Workspace")

local LOG = "[Смерть]"

local CFG = {
	-- { до какого дня (не включая), штраф }
	PENALTIES = { { 5, 50 }, { 15, 100 }, { 30, 200 }, { 50, 300 } },
	PENALTY_MAX = 500,
	--[[ ⚠️ ЖИЗНИ — ОТ ЧИСЛА ИГРОКОВ, ОБЩИЕ НА СЕССИЮ (владелец).
	     Привязка к игроку обходилась бы перезаходом с другого аккаунта, поэтому
	     пул один на весь забег: [число игроков] → жизней. Считаем по МАКСИМУМУ
	     игроков, замеченному в окно посадки (COUNT_WINDOW секунд от старта
	     сервера): вышедший игрок жизней не уносит, а зашедший позже «твинк» их не
	     прибавляет. В сейв уходят три числа: максимум игроков, потрачено, куплено. ]]
	LIVES_BY_PLAYERS = { 3, 4, 5, 6, 7 },
	COUNT_WINDOW = 120,
	TEAM_LIVES = 3,
	-- ⚠️ ВПИСАТЬ id девпродукта «экстра-жизнь». Пока 0 — кнопки «Купить» у
	-- игроков нет (в Studio покупка условная и бесплатная, чтобы проверить сцену).
	EXTRA_LIFE_PRODUCT_ID = 0,
	EXTRA_LIFE_PRICE = 49,      -- число на кнопке; должно совпадать с ценой продукта
	OFFER_TIMEOUT = 30,         -- секунд на решение, потом лобби
}

local remote = ReplicatedStorage:FindFirstChild("DeathScene")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "DeathScene"
	remote.Parent = ReplicatedStorage
end
local action = ReplicatedStorage:FindFirstChild("DeathSceneAction")
if not action then
	action = Instance.new("RemoteEvent")
	action.Name = "DeathSceneAction"
	action.Parent = ReplicatedStorage
end

local serverT0 = os.clock()

local function attr(name, default)
	local v = Workspace:GetAttribute(name)
	if type(v) ~= "number" then v = default end
	return v
end

local function totalLives()
	local n = math.clamp(attr("TeamMaxPlayers", 1), 1, #CFG.LIVES_BY_PLAYERS)
	return CFG.LIVES_BY_PLAYERS[n] + attr("TeamLivesBonus", 0)
end

local function lives()
	local v = math.max(0, totalLives() - attr("TeamLivesSpent", 0))
	if Workspace:GetAttribute("TeamLives") ~= v then Workspace:SetAttribute("TeamLives", v) end
	return v
end

-- максимум игроков растёт только в окно посадки
local function countPlayers()
	if os.clock() - serverT0 > CFG.COUNT_WINDOW then return end
	local n = #Players:GetPlayers()
	if n > attr("TeamMaxPlayers", 0) then
		Workspace:SetAttribute("TeamMaxPlayers", n)
		print(("%s игроков в забеге %d → жизней команды %d"):format(LOG, n, lives()))
	end
end
task.spawn(function()
	while os.clock() - serverT0 <= CFG.COUNT_WINDOW do
		countPlayers()
		task.wait(2)
	end
	lives()
end)
lives()

local function penaltyForDay(day)
	for _, row in ipairs(CFG.PENALTIES) do
		if day < row[1] then return row[2] end
	end
	return CFG.PENALTY_MAX
end

local offerGen = 0       -- поколение предложения: покупка отменяет отложенное лобби
local offerOpen = false

local function toLobby()
	offerOpen = false
	remote:FireAllClients({ scene = "lobby" })
	task.delay(2.5, function()
		if typeof(_G.TeleportAllToLobby) == "function" then
			local ok = _G.TeleportAllToLobby()
			if not ok then warn(LOG .. " телепорт в лобби не запущен (Studio или лобби не определено)") end
		else
			warn(LOG .. " _G.TeleportAllToLobby не найден (RaftHealth не загружен?)")
		end
	end)
end

local function grantExtraLife(buyer)
	-- купленная жизнь — это +1 к пулу (бонус), а не перезапись счётчика
	Workspace:SetAttribute("TeamLivesBonus", attr("TeamLivesBonus", 0) + 1)
	lives()
	if not offerOpen then return true end   -- чек дошёл позже: жизнь просто прибавилась
	offerOpen = false
	offerGen += 1
	remote:FireAllClients({ scene = "revive" })
	print(("%s %s купил экстра-жизнь — забег продолжается"):format(LOG, buyer.Name))
	return true
end

local function openOffer()
	offerOpen = true
	offerGen += 1
	local gen = offerGen
	task.delay(CFG.OFFER_TIMEOUT, function()
		if offerOpen and gen == offerGen then
			print(LOG .. " предложение экстра-жизни истекло — в лобби")
			toLobby()
		end
	end)
end

local function onDied(player)
	local day = typeof(_G.GetDayCount) == "function" and _G.GetDayCount() or 1
	local penalty = penaltyForDay(day)
	local bal = typeof(_G.GetPirate) == "function" and _G.GetPirate(player) or 0

	--[[ ⚠️ ПИРАТОВ ЗА СМЕРТЬ НЕ СНИМАЕМ (владелец): смерть всегда стоит ЖИЗНИ
	     команды. Таблица PENALTIES и сцена penalty оставлены выключенными на случай
	     возврата правила, но отсюда не вызываются. ]]
	local _ = penalty, bal
	local before = lives()
	if before <= 0 then return end          -- забег уже окончен, сцена висит
	local after = before - 1
	Workspace:SetAttribute("TeamLivesSpent", attr("TeamLivesSpent", 0) + 1)
	lives()
	print(("%s %s: смерть — жизнь команды %d → %d"):format(LOG, player.Name, before, after))
	if after > 0 then
		remote:FireAllClients({ scene = "death", livesBefore = before, livesTotal = totalLives(), who = player.Name })
		return
	end
	local canBuy = CFG.EXTRA_LIFE_PRODUCT_ID > 0 or RunService:IsStudio()
	remote:FireAllClients({ scene = "death", livesBefore = before, livesTotal = totalLives(), who = player.Name,
		price = canBuy and CFG.EXTRA_LIFE_PRICE or nil })
	openOffer()
end

action.OnServerEvent:Connect(function(player, what)
	if not offerOpen then return end
	if what == "buy" then
		if CFG.EXTRA_LIFE_PRODUCT_ID > 0 then
			pcall(function() MarketplaceService:PromptProductPurchase(player, CFG.EXTRA_LIFE_PRODUCT_ID) end)
		elseif RunService:IsStudio() then
			print(LOG .. " Studio: продукта нет, экстра-жизнь выдана условно")
			grantExtraLife(player)
		end
	elseif what == "decline" then
		toLobby()
	end
end)

-- закрыл окно покупки без оплаты — это отказ
MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, purchased)
	if productId == CFG.EXTRA_LIFE_PRODUCT_ID and not purchased and offerOpen then
		toLobby()
	end
end)

if CFG.EXTRA_LIFE_PRODUCT_ID > 0 then
	task.spawn(function()
		local deadline = os.clock() + 30
		while _G.RegisterProductHandler == nil and os.clock() < deadline do task.wait(0.2) end
		if _G.RegisterProductHandler then
			_G.RegisterProductHandler(CFG.EXTRA_LIFE_PRODUCT_ID, function(buyer) return grantExtraLife(buyer) end)
		else
			warn(LOG .. " реестр продуктов не поднялся — экстра-жизнь не будет начисляться")
		end
	end)
end

local function bind(player)
	local function onChar(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		local done = false
		hum.Died:Connect(function()
			if done then return end
			done = true
			local ok, err = pcall(onDied, player)
			if not ok then warn(LOG .. " " .. tostring(err)) end
		end)
	end
	player.CharacterAdded:Connect(onChar)
	if player.Character then task.spawn(onChar, player.Character) end
end
for _, p in ipairs(Players:GetPlayers()) do bind(p) end
Players.PlayerAdded:Connect(bind)

-- наружу: админ-кнопки и сейв
_G.GetTeamLives = lives
_G.SetTeamLives = function(n)
	-- тестовая ручка: подгоняем «потрачено» под нужный остаток
	n = math.clamp(math.floor(tonumber(n) or totalLives()), 0, totalLives())
	Workspace:SetAttribute("TeamLivesSpent", totalLives() - n)
	lives()
end

print(("%s готов: смерть = жизнь команды, пиратов не снимаем; жизней %d (по числу игроков: 3/4/5/6/7)"):format(LOG, lives()))
