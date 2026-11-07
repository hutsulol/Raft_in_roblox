--[[
	МАГАЗИН СТРАНСТВУЮЩЕГО ТОРГОВЦА — сервер (хендофф design_handoff_roblox_ocean_ui,
	экран 1 «Магазин торговца»).

	Торговец приплывает на время (DURATION): у него одно ОСОБОЕ предложение со
	скидкой и несколько случайных товаров из пула, у каждого — лимит штук на
	игрока. Платят монетами («пираты», _G.SpendPirate).

	⚠️ ВСЯ ПРОВЕРКА — ЗДЕСЬ. Клиент шлёт только id товара: цену, остаток, «торговец
	ещё здесь» и баланс сервер считает сам.
	⚠️ ТОВАРЫ — НАСТОЯЩИЕ ПРЕДМЕТЫ ИГРЫ, а не тестовые из макета (гарпун, парус):
	ресурсы кладутся _G.AddResourceToInventory, инструменты — клоном шаблона из
	ReplicatedStorage (_G.GiveToolOrDrop). Инструмент без шаблона в пул не попадает.

	Remotes:
	  MerchantShop (RemoteFunction): "state" → состояние; "buy", id → результат
	  MerchantEvent (RemoteEvent, S→C): "arrive" (departAt), "leave", "open"
	_G.MerchantArrive(seconds?) — торговец приплыл (сейчас зовёт кнопка настроек).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local LOG = "[Торговец]"

local DURATION    = 300   -- сколько торговец стоит у плота, секунд
local OFFER_COUNT = 6     -- сколько обычных товаров из пула

-- ═══════════ товары ═══════════
-- rarity: common / uncommon / rare / epic / legend; category: tools / res / rare
local FEATURED = {
	id = "captain_chest", name = "Сундук капитана", desc = "Слитки, верёвка и брёвна разом",
	rarity = "legend", category = "rare", price = 299, oldPrice = 450, stock = 1, icon = "chest",
	res = { { "Iron_Ingot", 5 }, { "Rope", 10 }, { "Log", 30 } },
}
local POOL = {
	{ id = "net_launcher", name = "Сеткомёт",          rarity = "epic",     category = "tools", price = 180, stock = 1, tool = "Pirate_Net_Launcher" },
	{ id = "machete",      name = "Мачете",            rarity = "uncommon", category = "tools", price = 50,  stock = 1, tool = "Machete" },
	{ id = "stone_axe",    name = "Каменный топор",    rarity = "common",   category = "tools", price = 40,  stock = 2, tool = "Stone_Axe" },
	{ id = "paddle",       name = "Весло",             rarity = "common",   category = "tools", price = 30,  stock = 1, tool = "Paddle" },
	{ id = "mask",         name = "Маска для ныряния", rarity = "rare",     category = "tools", price = 60,  stock = 2, res = { { "DivingMask", 1 } } },
	{ id = "logs",         name = "Брёвна ×10",        rarity = "common",   category = "res",   price = 25,  stock = 10, res = { { "Log", 10 } } },
	{ id = "plastic",      name = "Пластик ×6",        rarity = "uncommon", category = "res",   price = 30,  stock = 8, res = { { "Plastic", 6 } } },
	{ id = "rope",         name = "Верёвка ×4",        rarity = "uncommon", category = "res",   price = 35,  stock = 5, res = { { "Rope", 4 } } },
	{ id = "stone",        name = "Камень ×6",         rarity = "common",   category = "res",   price = 20,  stock = 8, res = { { "Stone", 6 } } },
	{ id = "compost",      name = "Компост ×3",        rarity = "common",   category = "res",   price = 20,  stock = 6, res = { { "Compost", 3 } } },
	{ id = "ingots",       name = "Слитки ×3",         rarity = "rare",     category = "rare",  price = 90,  stock = 3, res = { { "Iron_Ingot", 3 } } },
	{ id = "bricks",       name = "Кирпичи ×10",       rarity = "epic",     category = "rare",  price = 150, stock = 1, res = { { "Dry_Brick", 10 } } },
	-- постройки фермы: тул-заготовка, ставится DecorPlace (только на грядку)
	{ id = "trough",       name = "Корыто",            rarity = "uncommon", category = "tools", price = 45,  stock = 2, placeable = "Raft_farm_trough" },
	{ id = "wool_bin",     name = "Ящик для шерсти",   rarity = "uncommon", category = "tools", price = 60,  stock = 1, placeable = "Raft_wool_bin" },
}

--[[ ПАК ФЕРМЕРА — постоянный товар (есть в каждый визит, не из случайного
     пула). Доход на овцах: 2 участка земли (блок фермы 2×2) + 1 домик фермера,
     те же тулы, что выдают кнопки админа (FarmBlockPlace: _G.GiveFarmBlock /
     _G.GiveFarmerHut). Цена — монеты И ресурсы: costs списываются с инвентаря
     вместе с монетами, при неудачной выдаче возвращается всё. ]]
local FARMER_PACK = {
	id = "farmer_pack", name = "Пак фермера",
	desc = "Доход на овцах — построй на плоту для прибыли! 2 участка земли и домик фермера",
	rarity = "epic", category = "rare", price = 500, stock = 1,
	model = "Raft_farmer_hut",   -- иконка — сам домик фермера
	costs = { { "Compost", 24 }, { "Log", 48 }, { "Leaves", 12 } },
	farmPack = { blocks = 2, huts = 1 },
	showcase = true,   -- большой карточкой: у строки нет места под описание
}

local function remote(class, name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local shopFn  = remote("RemoteFunction", "MerchantShop")
local shopEvt = remote("RemoteEvent", "MerchantEvent")

local function now() return workspace:GetServerTimeNow() end

local state = { present = false, departAt = 0, offers = {}, byId = {}, visit = 0 }
local purchases = {}   -- [UserId] = { [offerId] = куплено в этот визит }

local function toolTemplate(name)
	local t = AssetFind.find(name)
	return (t and t:IsA("Tool")) and t or nil
end

local function available(offer)
	if offer.tool then return toolTemplate(offer.tool) ~= nil end
	if offer.placeable then return AssetFind.find(offer.placeable) ~= nil end
	if offer.farmPack then
		return typeof(_G.GiveFarmBlock) == "function" and typeof(_G.GiveFarmerHut) == "function"
	end
	return true
end

local function pickOffers()
	--[[ СЮЖЕТ ТОРГОВЦА (MerchantStory.server) решает, что сегодня в лавке: одно
	     предложение по этапу истории (рыбацкое место → ферма → таверна).
	     Случайный ассортимент ниже — только если сюжета нет. ]]
	if typeof(_G.MerchantStoryOffers) == "function" then
		local ok, list = pcall(_G.MerchantStoryOffers)
		if ok and type(list) == "table" then return list end
	end
	local pool = {}
	for _, o in ipairs(POOL) do
		if available(o) then table.insert(pool, o) end
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local list = { FEATURED }
	if available(FARMER_PACK) then table.insert(list, FARMER_PACK) end   -- постоянный товар
	for i = 1, math.min(OFFER_COUNT, #pool) do table.insert(list, pool[i]) end
	return list
end

-- хватает ли ресурсов из costs (монеты — отдельно, _G.SpendPirate)
local function hasCosts(player, offer)
	if not offer.costs then return true end
	local inv = typeof(_G.GetInventory) == "function" and _G.GetInventory(player) or nil
	if not inv then return false end
	for _, c in ipairs(offer.costs) do
		if (inv[c[1]] or 0) < c[2] then return false end
	end
	return true
end

local function leftFor(player, offer)
	local bought = purchases[player.UserId] and purchases[player.UserId][offer.id] or 0
	return math.max(0, offer.stock - bought)
end

local function publicState(player)
	local offers = {}
	for _, o in ipairs(state.offers) do
		table.insert(offers, {
			id = o.id, name = o.name, desc = o.desc, rarity = o.rarity, category = o.category,
			price = o.price, oldPrice = o.oldPrice, featured = o == FEATURED,
			left = (o.canBuy and not o.canBuy(player)) and 0 or leftFor(player, o), tool = o.tool or o.placeable, item = o.res and o.res[1][1] or nil, icon = o.icon,
			model = o.model, showcase = o.showcase, isGift = o.isGift == true,
			costs = o.costs and (function()
				local out = {}
				for _, c in ipairs(o.costs) do table.insert(out, { id = c[1], n = c[2] }) end
				return out
			end)() or nil,
			resOk = hasCosts(player, o),
		})
	end
	return {
		present = state.present and now() < state.departAt,
		departAt = state.departAt,
		offers = offers,
		balance = player:GetAttribute("Pirate") or 0,
	}
end

local function give(player, offer)
	if offer.give then   -- сюжетный товар выдаёт себя сам (подарок, ферма, таверна)
		local ok, res = pcall(offer.give, player)
		if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
		return ok and res == true
	end
	if offer.placeable then
		-- как крафт «placeable»: пустой тул с именем модели, иконка — сама модель
		if not AssetFind.find(offer.placeable) then return false end
		local tool = Instance.new("Tool")
		tool.Name = offer.placeable
		tool.CanBeDropped = false
		tool:SetAttribute("PreviewModel", offer.placeable)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		if typeof(_G.GiveToolOrDrop) == "function" then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
	end
	if offer.tool then
		local tpl = toolTemplate(offer.tool)
		if not tpl then return false end
		local tool = tpl:Clone()
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BaseScript") and d:GetAttribute("TransferEnabled") ~= nil then
				d.Enabled = d:GetAttribute("TransferEnabled") ~= false
			end
		end
		if typeof(_G.GiveToolOrDrop) == "function" then
			_G.GiveToolOrDrop(player, tool)
		else
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
	end
	if offer.farmPack then
		for _ = 1, offer.farmPack.blocks do
			if not _G.GiveFarmBlock(player) then return false end
		end
		for _ = 1, offer.farmPack.huts do
			if not _G.GiveFarmerHut(player) then return false end
		end
	end
	for _, r in ipairs(offer.res or {}) do
		if typeof(_G.AddResourceToInventory) == "function" then
			_G.AddResourceToInventory(player, r[1], r[2], nil)
		end
	end
	if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
	return true
end

local busy = {}
shopFn.OnServerInvoke = function(player, action, id)
	if action == "state" then return publicState(player) end
	if action ~= "buy" or type(id) ~= "string" then return { ok = false, why = "bad" } end
	if busy[player] then return { ok = false, why = "busy" } end
	busy[player] = true
	local result = (function()
		if not state.present or now() >= state.departAt then return { ok = false, why = "Торговец уже уплыл" } end
		-- покупка — только у прилавка пришвартованной яхты (MerchantYacht.server)
		if typeof(_G.MerchantYachtNear) == "function" and not _G.MerchantYachtNear(player) then
			return { ok = false, why = "Подойди к прилавку торговца" }
		end
		local offer = state.byId[id]
		if not offer then return { ok = false, why = "Такого товара нет" } end
		if leftFor(player, offer) <= 0 then return { ok = false, why = "Продано" } end
		if offer.canBuy then   -- сюжет: подарок — один на весь плот
			local can, why = offer.canBuy(player)
			if not can then return { ok = false, why = why or "Продано" } end
		end
		if not hasCosts(player, offer) then return { ok = false, why = "Не хватает ресурсов" } end
		if typeof(_G.SpendPirate) ~= "function" or not _G.SpendPirate(player, offer.price) then
			return { ok = false, why = "Не хватает монет" }
		end
		-- ресурсы списываем вместе с монетами (проверены выше, под busy — без гонок)
		for _, c in ipairs(offer.costs or {}) do
			_G.RemoveResourceFromInventory(player, c[1], c[2])
		end
		if not give(player, offer) then
			if typeof(_G.AddPirate) == "function" then _G.AddPirate(player, offer.price) end   -- вернуть деньги
			for _, c in ipairs(offer.costs or {}) do   -- и ресурсы
				if typeof(_G.AddResourceToInventory) == "function" then _G.AddResourceToInventory(player, c[1], c[2], nil) end
			end
			if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
			return { ok = false, why = "Товар недоступен" }
		end
		purchases[player.UserId] = purchases[player.UserId] or {}
		purchases[player.UserId][offer.id] = (purchases[player.UserId][offer.id] or 0) + 1
		print(("%s %s купил «%s» за %d"):format(LOG, player.Name, offer.name, offer.price))
		if typeof(_G.MerchantYachtPurchase) == "function" then _G.MerchantYachtPurchase() end   -- монеты → вещь → спасибо
		if typeof(_G.MerchantStoryOnBuy) == "function" then task.spawn(_G.MerchantStoryOnBuy, player, offer) end
		return { ok = true }
	end)()
	busy[player] = nil
	result.state = publicState(player)
	return result
end

--[[ ЛАВКА ОТКРЫВАЕТСЯ, КОГДА ЯХТА ВСТАЛА У БОРТА (MerchantYacht.server).
     Пока она идёт к плоту, торговли нет; время стоянки (DURATION) считается с
     момента швартовки. Нет модели яхты — торговец «приплывает» сразу, как раньше. ]]
local function openShop(seconds)
	state.coming = false
	state.present = true
	state.departAt = now() + (tonumber(seconds) or DURATION)
	state.offers = pickOffers()
	state.byId = {}
	for _, o in ipairs(state.offers) do state.byId[o.id] = o end
	state.visit += 1
	purchases = {}
	shopEvt:FireAllClients("arrive", state.departAt)
	print(("%s приплыл на %d с, товаров %d"):format(LOG, math.floor(state.departAt - now()), #state.offers))
	local visit = state.visit
	task.delay(state.departAt - now(), function()
		if state.visit ~= visit then return end
		state.present = false
		shopEvt:FireAllClients("leave")
		if typeof(_G.MerchantYachtLeave) == "function" then _G.MerchantYachtLeave() end
		print(LOG .. " уплыл")
	end)
	return true
end

_G.MerchantArrive = function(seconds)
	if state.coming or (state.present and now() < state.departAt) then return false, "торговец уже здесь" end
	if typeof(_G.MerchantYachtVisit) == "function" then
		state.coming = true
		state.call = (state.call or 0) + 1
		local call = state.call
		-- отмена СТАРОГО рейса (его обрывает новый) не должна сбрасывать «плывёт» у нового
		local ok, why = _G.MerchantYachtVisit(function() if state.call == call then openShop(seconds) end end,
			function() if state.call == call then state.coming = false end end)
		if ok then return true end
		state.coming = false
		if why ~= "нет модели" then return false, why end   -- борта закрыты / нет плота: визит отменён
	end
	return openShop(seconds)
end

-- админ-тест: оборвать текущий визит (лавка закрывается, яхта убирается) и вызвать заново
_G.MerchantForceArrive = function(seconds)
	if state.present or state.coming then
		state.visit += 1   -- таймер ухода прошлого визита больше не сработает
		state.present = false
		state.coming = false
		shopEvt:FireAllClients("leave")
	end
	return _G.MerchantArrive(seconds)
end

-- сюжет: торговец уплывает сейчас (рыбак назначен, сделка закрыта)
_G.MerchantDepart = function()
	if not state.present then return false end
	state.visit += 1   -- плановый уход этого визита уже не нужен
	state.present = false
	shopEvt:FireAllClients("leave")
	if typeof(_G.MerchantYachtLeave) == "function" then _G.MerchantYachtLeave() end
	print(LOG .. " уплыл (сюжет)")
	return true
end
_G.MerchantPresent = function() return state.present == true or state.coming == true end

_G.MerchantOpenFor = function(player)
	if not state.present then return end
	shopEvt:FireClient(player, "open")
end

--[[ РАСПИСАНИЕ ВИЗИТОВ: по номеру дня, как пиратские катера (у тех чётные дни
     в 40% дня — торговец приходит в нечётные, утром, чтобы не встречаться). ]]
local VISIT_FIRST_DAY       = 3
local VISIT_EVERY_DAYS      = 2
local VISIT_AT_DAY_FRACTION = 0.20
task.spawn(function()
	local dayValue = ReplicatedStorage:WaitForChild("DayCount", 20)
	if not dayValue then
		warn(LOG .. " нет ReplicatedStorage.DayCount — торговец приплывает только по кнопке")
		return
	end
	local Lighting = game:GetService("Lighting")
	local lastDay = 0
	while true do
		task.wait(3)
		if _G.MerchantStoryActive then continue end   -- визитами правит сюжет (MerchantStory.server)
		local day, t = dayValue.Value, Lighting.ClockTime
		local p = (t >= 6 and t < 18) and (t - 6) / 12 or nil
		if p and p >= VISIT_AT_DAY_FRACTION and day ~= lastDay and day >= VISIT_FIRST_DAY
			and (day - VISIT_FIRST_DAY) % VISIT_EVERY_DAYS == 0 then
			lastDay = day
			local ok, why = _G.MerchantArrive()
			print(("%s расписание: день %d → %s"):format(LOG, day, ok and "плывёт" or ("нет: " .. tostring(why))))
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
print(LOG .. " готов: _G.MerchantArrive(seconds) — торговец приплывает, окно — MerchantShopUI")
