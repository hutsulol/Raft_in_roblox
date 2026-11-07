-- DiverShop.server.lua
-- The monolith UPGRADES (the working-monolith window). Three SHARED (global) upgrades, bought via
-- DiverShopEvent("upgrade", key):
--   treasure — special-crate chance: 5% + 2.5% per level, cap 15% (max lvl 5).
--              When a treasure procs it's 80% GOLDEN / 20% DIAMOND (DiverSystem).
--   divers   — each level spawns one more diver via _G.SpawnDiver (3 divers max → max lvl 3)
--   crate    — the crate weight range grows +0.2 min / +0.2 max per level (base 0.2–3.0)
-- DiverSystem reads the live effects through _G.GetMonolithUpgrades().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ ═══ ЭКОНОМИКА УЛУЧШЕНИЙ: ЛЕСТНИЦА ОТ ЦЕНЫ РЕМОНТА ═══

     Первая покупка стоила копейки (12 камня / 4 слитка / 10 дерева), а
     дальше росло линейно и вяло: игрок брал всё подряд, не задумываясь.
     Владелец задал форму лестницы прямо: первый шаг — вдвое дороже
     ремонта монолита, второй — втрое и уже с металлом, третий — вчетверо и
     с чем-то по-настоящему редким, дальше — только круче. Первый раз
     улучшить легко, каждый следующий — заметно труднее.

     ⚠️ ТОЧКА ОТСЧЁТА — РЕМОНТ МОНОЛИТА (MonolithRepair.COST: 8 дерева +
     8 листвы). Покупка номер n стоит (n + 1) × ремонт по дереву и листве.
     Со второй покупки добавляются слитки — их надо добыть киркой на острове
     (20 ударов за руду) и три минуты плавить на бревне; вес ветки задаёт,
     сколько: дайверы — самая сильная ветка (каждый уровень = ещё один
     дайвер, то есть +100 % добычи), у неё слитков больше всех. С третьей
     покупки добавляется мусор — своего источника у него нет, он выпадает
     из бочек одним видом из семи, и это самое «дорогое», что есть в игре.
     Клей не берём нарочно: водоросли в игре сейчас негде добыть, и цена в
     клее была бы ценой в никогда.

     Что выходит (дерево/листва + слитки + мусор):
       дайверы  (2 покупки):  16/16 · 24/24 + 4 сл.
       сокровища(4 покупки):  16/16 · 24/24 + 2 сл. · 32/32 + 4 сл. + 1 мус. · 40/40 + 6 сл. + 2 мус.
       ящики    (9 покупок):  16/16 · 24/24 + 1 сл. · … · 80/80 + 8 сл. + 7 мус.

     Подписи и иконки всех ресурсов отсюда должны быть в RES в
     MonolithRepairUI.client — иначе в ценнике покажется сырой ключ. ]]
local REPAIR_LOG, REPAIR_LEAVES = 8, 8   -- ⚠️ зеркало MonolithRepair.COST
local INGOT_WEIGHT = { divers = 4, treasure = 2, crate = 1 }

-- Цена покупки номер n (1 = переход с 1-го уровня на 2-й). Возвращает
-- УПОРЯДОЧЕННЫЙ список {res, amount}: порядок — это порядок в ценнике.
local function costsFor(key, n)
	local mult = n + 1
	local list = {
		{ res = "Log",    amount = REPAIR_LOG * mult },
		{ res = "Leaves", amount = REPAIR_LEAVES * mult },
	}
	if n >= 2 then
		table.insert(list, { res = "Iron_Ingot", amount = (INGOT_WEIGHT[key] or 1) * (n - 1) })
	end
	if n >= 3 then
		table.insert(list, { res = "Rubbish", amount = n - 2 })
	end
	return list
end

-- Совместимость: первая строка списка — для старых читателей ценника.
local function priceFor(key, lvl)
	local first = costsFor(key, lvl)[1]
	return first.res, first.amount
end

local UPGRADES = {
	treasure = { lvl = 1, max = 5 },
	divers   = { lvl = 1, max = 3 },
	crate    = { lvl = 1, max = 10 },
}
local ORDER = { "treasure", "divers", "crate" }

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local shopEvent = ensureRemote("DiverShopEvent")
local statusEvent = ensureRemote("DiverStatusEvent")

local function repaired() return _G.IsMonolithRepaired and _G.IsMonolithRepaired() == true end

local function treasureChance(lvl) return math.min(0.05 + 0.025 * (lvl - 1), 0.15) end
local function crateRange(lvl) return 0.2 + 0.2 * (lvl - 1), 3.0 + 0.2 * (lvl - 1) end

-- live effect values for DiverSystem
_G.GetMonolithUpgrades = function()
	local minKg, maxKg = crateRange(UPGRADES.crate.lvl)
	return {
		treasureChance = treasureChance(UPGRADES.treasure.lvl),
		crateMin = minKg,
		crateMax = maxKg,
		divers = UPGRADES.divers.lvl,
	}
end

local function upgradeData()
	local list = {}
	for _, key in ipairs(ORDER) do
		local u = UPGRADES[key]
		-- цена СЛЕДУЮЩЕГО уровня; на максимуме показываем цену последнего,
		-- чтобы ценник не мигал пустотой (кнопка там всё равно заблокирована)
		local n = math.min(u.lvl, u.max - 1)
		local res, amount = priceFor(key, n)
		table.insert(list, { key = key, lvl = u.lvl, max = u.max,
			costName = res, costAmount = amount, costs = costsFor(key, n) })
	end
	return list
end

-- уровни улучшений для сохранения (RaftSaveSystem)
_G.GetMonolithUpgradeLevels = function()
	return { treasure = UPGRADES.treasure.lvl, divers = UPGRADES.divers.lvl, crate = UPGRADES.crate.lvl }
end

-- восстановление уровней из сейва: ставим уровни и заново создаём
-- доп. дайверов (стартовый = дайвер 1, каждый уровень выше — ещё один).
_G.RestoreMonolithUpgrades = function(s)
	if type(s) ~= "table" then return end
	UPGRADES.treasure.lvl = math.clamp(math.floor(tonumber(s.treasure) or 1), 1, UPGRADES.treasure.max)
	UPGRADES.divers.lvl   = math.clamp(math.floor(tonumber(s.divers) or 1), 1, UPGRADES.divers.max)
	UPGRADES.crate.lvl    = math.clamp(math.floor(tonumber(s.crate) or 1), 1, UPGRADES.crate.max)
	if _G.SpawnDiver then
		for _ = 2, UPGRADES.divers.lvl do
			_G.SpawnDiver()
		end
	end
	shopEvent:FireAllClients("update", upgradeData())
	print(("[DiverShop] upgrades restored: treasure=%d divers=%d crate=%d")
		:format(UPGRADES.treasure.lvl, UPGRADES.divers.lvl, UPGRADES.crate.lvl))
end

_G.OpenDiverShop = function(plr)
	shopEvent:FireClient(plr, "open", upgradeData())
end

shopEvent.OnServerEvent:Connect(function(plr, action, key)
	-- во время катсцены покупки запрещены (флаг ставит IslandClearSystem)
	if plr:GetAttribute("InCutscene") then return end
	if action ~= "upgrade" then return end
	local u = UPGRADES[key]
	if not u or not repaired() then return end
	if u.lvl >= u.max then
		shopEvent:FireClient(plr, "update", upgradeData())
		return
	end
	if not (_G.GetInventory and _G.RemoveResourceFromInventory) then return end
	-- цена ТЕКУЩЕГО перехода: с уровня u.lvl на следующий
	--[[ ⚠️ СНАЧАЛА ПРОВЕРЯЕМ ВСЕ ПОЗИЦИИ, ПОТОМ СПИСЫВАЕМ ВСЕ.
	     Списывать по одной с проверкой на ходу нельзя: не хватило третьей —
	     первые две уже ушли, а уровень не вырос. ]]
	local costs = costsFor(key, u.lvl)
	local inv = _G.GetInventory(plr) or {}
	for _, c in ipairs(costs) do
		if (inv[c.res] or 0) < c.amount then
			shopEvent:FireClient(plr, "update", upgradeData()) -- pill shows red client-side anyway
			return
		end
	end
	for _, c in ipairs(costs) do
		_G.RemoveResourceFromInventory(plr, c.res, c.amount)
	end
	local costRes, costAmount = costs[1].res, costs[1].amount
	-- ⚠️ СПИСАНИЕ САМО ПО СЕБЕ КЛИЕНТУ НИЧЕГО НЕ ШЛЁТ.
	-- RemoveResourceFromInventory правит только серверную таблицу и копит дельту;
	-- показать это игроку — дело SendInventory, и его здесь не звали. В Studio
	-- сходилось потому, что инвентарь всё равно пересобирался по другим поводам,
	-- а в живой игре ресурс списывался молча и число на экране не менялось.
	if _G.SendInventory then _G.SendInventory(plr) end
	u.lvl = u.lvl + 1
	if key == "divers" and _G.SpawnDiver then
		_G.SpawnDiver() -- one more diver joins the crew
	end
	local paid = {}
	for _, c in ipairs(costs) do table.insert(paid, c.amount .. " " .. c.res) end
	print(("[DiverShop] %s → lvl %d за %s (%s)"):format(key, u.lvl, table.concat(paid, " + "), plr.Name))
	shopEvent:FireAllClients("update", upgradeData())
end)

-- delivery-timer status (opened from the monolith once the diver is working)
_G.OpenDiverStatus = function(plr)
	local left = (_G.DiverSecondsLeft and _G.DiverSecondsLeft()) or 0
	statusEvent:FireClient(plr, "open", left)
end
statusEvent.OnServerEvent:Connect(function(plr, action)
	if action == "skip" then
		if _G.SkipDiverTimer then _G.SkipDiverTimer() end -- free while testing; wire to a dev product for Robux
		statusEvent:FireClient(plr, "skipped")
	end
end)

print("[DiverShop] ready (upgrades)")
