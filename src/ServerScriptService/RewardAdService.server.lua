--[[
	НАГРАДА С РЕЙДА + РЕКЛАМА ЗА НАГРАДУ — сервер (хендофф raft-reward-ads, этап P2).

	Табличка лодочника ("boatman"): система игры кладёт оффер (_G.RewardAdsSetOffer)
	= { free = обычные, premium = премиум }. Клиент рисует табличку и шлёт ТОЛЬКО
	placement:
	  • RewardAds_Watch("boatman") — «Бесплатно»: выдаёт ТОЛЬКО free (сразу, или
	    через ролик, если Config.FreeRequiresAd и реклама включена) и закрывает
	    оффер — лодочник сразу уходит.
	  • RewardAds_Buy("boatman") — «R$ N»: PromptProductPurchase RaidAll —
	    выдаёт free + premium и закрывает оффер.
	⚠️ НАГРАДА ОДНА НА РЕЙД: либо бесплатное, либо всё за Robux. Таймеров нет.

	⚠️ КЛИЕНТ НЕ ПРИСЫЛАЕТ НИ КОЛИЧЕСТВ, НИ ФАКТА ПОКУПКИ. Выдаёт только чек.
	⚠️ ProcessReceipt НА ИГРУ ОДИН (WoodBoostProducts): регистрируемся в его
	реестре _G.RegisterProductHandler, не переназначаем.
	⚠️ ПОКУПКА ПЕРЕЖИВАЕТ ПЕРЕЗАХОД: перед окном покупки состав кладётся в
	DataStore; чек (Roblox повторит его, когда игрок вернётся) выдаёт оттуда.
	Идемпотентность — PurchaseId в том же DataStore, отмечается ДО выдачи.
	⚠️ В Studio: DebugFakePurchases (пока ID продуктов = 0) — «R$» выдаёт сразу;
	DebugFakeAds — ролик не нужен.

	Правила показа роликов (диздок 4.1, числа в Config) — только когда в потоке
	есть реклама. Табличку в любом случае прячем в бою, катсцене, ночной волне,
	у мёртвого.
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local Lighting           = game:GetService("Lighting")
local AdService          = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")

local LOG = "[Реклама]"
local Config = require(ReplicatedStorage:WaitForChild("RewardAds"):WaitForChild("Config"))

local function remote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local OfferChanged = remote("RewardAds_OfferChanged")
local Watch        = remote("RewardAds_Watch")
local Buy          = remote("RewardAds_Buy")
local Dismiss      = remote("RewardAds_Dismiss")
local Granted      = remote("RewardAds_Granted")

local IS_STUDIO = RunService:IsStudio()
local FAKE_ADS = IS_STUDIO and Config.DebugFakeAds == true
-- ролик реально может быть показан
local function adsLive() return Config.AdsEnabled == true and ((Config.DevProductId or 0) > 0 or FAKE_ADS) end
-- «Бесплатно» идёт через ролик
local function freeNeedsAd() return Config.FreeRequiresAd == true end

local PRODUCT = { all = Config.RaidAllProductId or 0, premium = Config.RaidPremiumProductId or 0 }
local function fakeBuy(kind) return IS_STUDIO and Config.DebugFakePurchases == true and PRODUCT[kind] <= 0 end
local function canBuy(kind) return PRODUCT[kind] > 0 or fakeBuy(kind) end

local function now() return workspace:GetServerTimeNow() end

-- ═══════════ учёт игрока ═══════════
local stats = {}      -- [player] = { joinAt, last, hour = {t…}, day, lastHurt }
local offers = {}     -- [player] = { [placement] = offer }
local busy = {}       -- [player] = placement, пока идёт ролик / открыто окно покупки
local busySince = {}
local nextId = 0
-- ⚠️ ЗАДЕРЖАННЫЙ ЧЕК: пока окно покупки / ролик не закрыт, крестик и таймаут
-- лодочника не отменяют доставку. Но чек может не прийти вовсе —
-- через BUSY_MAX секунд перестаём держать.
local BUSY_MAX = 120
_G.RewardAdsIsBusy = function(player)
	if busy[player] and os.clock() - (busySince[player] or 0) > BUSY_MAX then busy[player] = nil end
	return busy[player] ~= nil
end
local function setBusy(player, placement)
	busy[player] = placement
	busySince[player] = os.clock()
end

local function st(player)
	local s = stats[player]
	if not s then
		s = { joinAt = os.clock(), last = -1e9, hour = {}, day = 0, lastHurt = -1e9 }
		stats[player] = s
	end
	return s
end

local function hookHurt(player)
	local function onChar(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		local prev = hum.Health
		hum.HealthChanged:Connect(function(h)
			if h < prev - 0.5 then st(player).lastHurt = os.clock() end
			prev = h
		end)
	end
	player.CharacterAdded:Connect(onChar)
	if player.Character then task.spawn(onChar, player.Character) end
end

local function nightWave()
	local ct = Lighting.ClockTime
	if not (ct >= 18 or ct < 6) then return false end
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	local day = dc and tonumber(dc.Value) or 1
	return day >= 5
end

-- почему сейчас нельзя (nil — можно). forAd — добавляет правила именно для роликов
local function blockedWhy(player, forAd)
	local s = st(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return "dead" end
	if player:GetAttribute("InCutscene") then return "cutscene" end
	if os.clock() - s.lastHurt < Config.CombatGraceSeconds then return "combat" end
	if nightWave() then return "night" end
	if forAd then
		if not IS_STUDIO and os.clock() - s.joinAt < Config.NewbieGraceSeconds then return "newbie" end
		if s.day >= Config.PerDay then return "day" end
	end
	return nil
end

-- перезарядка роликов: до какого серверного времени (0 — готово)
local function adCooldownUntil(player)
	local s = st(player)
	local t = os.clock()
	for i = #s.hour, 1, -1 do if t - s.hour[i] > 3600 then table.remove(s.hour, i) end end
	local untilClock = s.last + Config.MinGapSeconds
	if #s.hour >= Config.PerHour then untilClock = math.max(untilClock, s.hour[1] + 3600) end
	if untilClock <= t then return 0 end
	return now() + (untilClock - t)
end

-- ═══════════ цены dev products (кэш) ═══════════
local priceCache = {}  -- [productId] = цена или false (не удалось)
local function priceOf(kind)
	if fakeBuy(kind) then return kind == "all" and Config.DebugPriceAll or Config.DebugPricePremium end
	local id = PRODUCT[kind]
	if id <= 0 then return nil end
	if priceCache[id] == nil then
		priceCache[id] = false
		task.spawn(function()
			local ok, info = pcall(function() return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product) end)
			if ok and info and info.PriceInRobux then
				priceCache[id] = info.PriceInRobux
			else
				warn(("%s цена dev product %d не получена: %s"):format(LOG, id, tostring(info)))
				task.delay(30, function() if priceCache[id] == false then priceCache[id] = nil end end)
			end
		end)
	end
	return priceCache[id] or nil
end

-- состояние оффера → клиенту
local function freeAvailable(o)
	if #o.free == 0 or o.claimed then return false end
	if freeNeedsAd() then return adsLive() end
	return true
end
local function buyKind(o)
	if #o.premium == 0 then return nil end
	local kind = "all" -- премиум отдельно не продаётся: бесплатное закрывает оффер
	return canBuy(kind) and kind or nil
end

local function push(player, placement)
	local o = offers[player] and offers[player][placement]
	if not o then
		OfferChanged:FireClient(player, placement, nil)
		return
	end
	local kind = buyKind(o)
	local ready = freeNeedsAd() and adCooldownUntil(player) or 0
	OfferChanged:FireClient(player, placement, {
		id = o.id,
		free = o.free,
		premium = o.premium,
		claimed = o.claimed == true,               -- бесплатное этого рейда уже забрано
		freeReadyAt = ready > now() and ready or 0, -- только пауза между роликами
		freeEnabled = freeAvailable(o),
		buyKind = kind,                             -- "all" | "premium" | nil (кнопки R$ нет)
		price = kind and priceOf(kind) or nil,
		blocked = blockedWhy(player, freeNeedsAd()),
		busy = busy[player] == placement,
	})
end

-- ═══════════ API для систем игры ═══════════
local function capList(list)
	local out = {}
	for _, r in ipairs(list or {}) do
		local n = math.floor(tonumber(r.amount) or 0)
		local cap = Config.RewardCap[r.id]
		if cap then n = math.min(n, cap) end
		if n > 0 then table.insert(out, { id = r.id, amount = n }) end
	end
	return out
end
local function concat(a, b)
	local out = table.clone(a)
	for _, r in ipairs(b) do table.insert(out, r) end
	return out
end
local function listText(list)
	local t = {}
	for _, r in ipairs(list) do table.insert(t, r.id .. "×" .. r.amount) end
	return table.concat(t, ", ")
end

--[[ reward: { free = {Resource}, premium = {Resource} } (или просто список = free)
     ctx: {
       validate  = function(player) -> ok, why   — оффер ещё в силе (лодочник ждёт, игрок рядом)
       onFree    = function(player, list)        — забрал бесплатное (оффер остаётся ради премиума)
       onGranted = function(player, list)        — оффер закрыт выдачей (покупка / бесплатное без премиума)
       onDismiss = function(player, claimed)     — закрыл ✕ (claimed — бесплатное уже забрано)
     } ]]
_G.RewardAdsSetOffer = function(player, placement, reward, ctx)
	offers[player] = offers[player] or {}
	nextId += 1
	local free, premium
	if reward and (reward.free or reward.premium) then
		free, premium = capList(reward.free), capList(reward.premium)
	else
		free, premium = capList(reward), {}
	end
	offers[player][placement] = { id = nextId, player = player, free = free, premium = premium,
		ctx = ctx or {}, expiresAt = os.clock() + Config.OfferLifetime }
	push(player, placement)
	-- диагностика «табличка не появилась»: что ушло клиенту
	print(("%s %s: оффер %s #%d — бесплатно [%s], за R$ [%s], блок=%s"):format(LOG, player.Name, placement, nextId,
		listText(free), listText(premium), tostring(blockedWhy(player, freeNeedsAd()))))
	return nextId
end

_G.RewardAdsClearOffer = function(player, placement)
	if offers[player] and offers[player][placement] then
		offers[player][placement] = nil
		push(player, placement)
	end
end

_G.RewardAdsIsFreeClaimed = function(player, placement)
	local o = offers[player] and offers[player][placement]
	return o ~= nil and o.claimed == true
end

-- награда рейда (заглушка из Config.RaidReward): n случайных из пула
local function pick(pool, n)
	local idx = {}
	for i = 1, #pool do idx[i] = i end
	local out = {}
	for k = 1, math.min(n, #pool) do
		local j = math.random(k, #idx)
		idx[k], idx[j] = idx[j], idx[k]
		local r = pool[idx[k]]
		table.insert(out, { id = r.id, amount = math.random(r.min, r.max) })
	end
	return out
end
_G.RewardAdsRaidLoot = function()
	local R = Config.RaidReward
	return { free = capList(pick(R.free, R.freeCount or 2)), premium = capList(pick(R.premium, R.premiumCount or 2)) }
end

-- ═══════════ выдача ═══════════
local function giveList(player, list)
	for _, r in ipairs(list) do
		if r.id == "Pirates" then
			if typeof(_G.AddPirate) == "function" then _G.AddPirate(player, r.amount) end
		elseif typeof(_G.AddResourceToInventory) == "function" then
			_G.AddResourceToInventory(player, r.id, r.amount, nil)
		end
	end
	if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
end

local function callCtx(o, name, ...)
	local fn = o and o.ctx[name]
	if typeof(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn(("%s ctx.%s упал: %s"):format(LOG, name, tostring(err))) end
end

-- бесплатное: только обычные ресурсы, оффер закрывается (награда одна на рейд)
local function grantFree(player, placement)
	local o = offers[player] and offers[player][placement]
	if not o or o.claimed then return end
	giveList(player, o.free)
	o.claimed = true
	offers[player][placement] = nil
	Granted:FireClient(player, placement, o.free, "free")
	print(("%s %s: бесплатное (%s): %s"):format(LOG, player.Name, placement, listText(o.free)))
	callCtx(o, "onGranted", player, o.free)
	push(player, placement)
end

-- оплаченное: список уже посчитан (из оффера или DataStore)
local function grantPaid(player, placement, list, kind)
	giveList(player, list)
	Granted:FireClient(player, placement, list, kind)
	print(("%s %s: куплено %s (%s): %s"):format(LOG, player.Name, kind, placement, listText(list)))
	local o = offers[player] and offers[player][placement]
	if o then
		offers[player][placement] = nil
		callCtx(o, "onGranted", player, list)
	end
	busy[player] = nil
	push(player, placement)
end

-- ═══════════ DataStore покупок ═══════════
local store
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore("RewardAdsRaid_v1") end)
	if ok then store = res else warn(LOG .. " DataStore недоступен: " .. tostring(res)) end
end
local function key(userId) return "u" .. tostring(userId) end

-- состав покупки — ДО окна оплаты: чек может прийти после перезахода
local function savePending(player, kind, placement, list)
	if not store then return false end
	local ok, err = pcall(function()
		store:UpdateAsync(key(player.UserId), function(rec)
			rec = rec or {}
			rec.pending = rec.pending or {}
			rec.pending[kind] = { placement = placement, list = list, at = os.time() }
			return rec
		end)
	end)
	if not ok then warn(LOG .. " не сохранил оффер покупки: " .. tostring(err)) end
	return ok
end

-- отмечает PurchaseId и забирает сохранённый состав. → status ("new"|"dup"|"fail"), pending
local doneLocal = {} -- запасной учёт, если DataStore лёг (только Studio)
local function claimReceipt(userId, purchaseId, kind)
	if not store then
		if doneLocal[purchaseId] then return "dup" end
		doneLocal[purchaseId] = true
		return IS_STUDIO and "new" or "fail"
	end
	local status, pending = "new", nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(userId), function(rec)
			rec = rec or {}
			rec.done = rec.done or {}
			if table.find(rec.done, purchaseId) then status = "dup" return nil end
			status = "new"
			table.insert(rec.done, purchaseId)
			while #rec.done > 30 do table.remove(rec.done, 1) end
			pending = rec.pending and rec.pending[kind]
			if rec.pending then rec.pending[kind] = nil end
			return rec
		end)
	end)
	if not ok then
		warn(LOG .. " DataStore чека: " .. tostring(err))
		if IS_STUDIO and not doneLocal[purchaseId] then
			doneLocal[purchaseId] = true
			return "new", nil
		end
		return "fail", nil
	end
	return status, pending
end

-- что выдать по чеку: живой оффер → сохранённый состав → запасной
local function receiptList(player, kind, pending)
	local placement = (pending and pending.placement) or busy[player] or "boatman"
	local o = offers[player] and offers[player][placement]
	if o then
		return placement, kind == "all" and concat(o.free, o.premium) or o.premium
	end
	if pending and type(pending.list) == "table" then return placement, capList(pending.list) end
	warn(("%s %s: чек %s без оффера — выдаю запасную награду"):format(LOG, player.Name, kind))
	return placement, capList(Config.FallbackReward)
end

local function onReceipt(kind)
	return function(player, receipt)
		local status, pending = claimReceipt(player.UserId, receipt.PurchaseId, kind)
		if status == "dup" then return true end
		if status == "fail" then return false end -- Roblox повторит чек позже
		local placement, list = receiptList(player, kind, pending)
		grantPaid(player, placement, list, kind)
		return true
	end
end

for kind, id in pairs(PRODUCT) do
	if id > 0 then
		task.spawn(function()
			local deadline = os.clock() + 30
			while typeof(_G.RegisterProductHandler) ~= "function" and os.clock() < deadline do task.wait(0.2) end
			if typeof(_G.RegisterProductHandler) ~= "function" then
				warn(LOG .. " реестр ProcessReceipt не поднялся — покупка награды рейда не будет выдаваться")
				return
			end
			_G.RegisterProductHandler(id, onReceipt(kind))
		end)
	end
end

-- окно покупки закрыто без оплаты — табличка остаётся как была
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if isPurchased then return end -- ждём чек
	local player = Players:GetPlayerByUserId(userId)
	if not player or not busy[player] then return end
	if productId ~= PRODUCT.all and productId ~= PRODUCT.premium then return end
	local placement = busy[player]
	busy[player] = nil
	push(player, placement)
end)

-- ═══════════ кнопки ═══════════
local function liveOffer(player, placement)
	local o = offers[player] and offers[player][placement]
	if not o then push(player, placement) return nil end
	if os.clock() > o.expiresAt then _G.RewardAdsClearOffer(player, placement) return nil end
	if typeof(o.ctx.validate) == "function" then
		local ok, why = o.ctx.validate(player)
		if not ok then push(player, placement) warn(("%s %s: отказ (%s)"):format(LOG, player.Name, tostring(why))) return nil end
	end
	return o
end

local lastClick = {}
local function throttled(player)
	if os.clock() - (lastClick[player] or -100) < 1 then return true end
	lastClick[player] = os.clock()
	return false
end

-- «Бесплатно»
Watch.OnServerEvent:Connect(function(player, placement)
	if type(placement) ~= "string" or busy[player] or throttled(player) then return end
	local o = liveOffer(player, placement)
	if not o or not freeAvailable(o) then return end
	local why = blockedWhy(player, freeNeedsAd())
	if why then push(player, placement) return end

	if not freeNeedsAd() then grantFree(player, placement) return end

	-- через ролик
	if adCooldownUntil(player) > 0 then push(player, placement) return end
	local function countAd()
		local s = st(player)
		s.last = os.clock()
		table.insert(s.hour, s.last)
		s.day += 1
	end
	if FAKE_ADS and (Config.DevProductId or 0) <= 0 then
		print(("%s %s: Studio, DebugFakeAds — выдаю без ролика"):format(LOG, player.Name))
		countAd()
		grantFree(player, placement)
		return
	end
	setBusy(player, placement)
	push(player, placement)
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(Config.DevProductId)
		local pl = Config.PlacementId or 0
		return AdService:ShowRewardedVideoAdAsync(player, reward, pl > 0 and pl or nil)
	end)
	-- награда придёт чеком (DevProductId ниже); busy снимаем там или по неуспеху
	if ok and result == Enum.ShowAdResult.ShowCompleted then
		countAd()
	else
		busy[player] = nil
		if not ok then warn(LOG .. " ролик не показался: " .. tostring(result)) end
		push(player, placement)
	end
end)

-- «R$ N»
Buy.OnServerEvent:Connect(function(player, placement)
	if type(placement) ~= "string" or busy[player] or throttled(player) then return end
	local o = liveOffer(player, placement)
	if not o then return end
	local kind = buyKind(o)
	if not kind then push(player, placement) return end
	if blockedWhy(player, false) then push(player, placement) return end
	local list = kind == "all" and concat(o.free, o.premium) or o.premium

	if fakeBuy(kind) then
		print(("%s %s: Studio, DebugFakePurchases — «покупка» %s без Robux"):format(LOG, player.Name, kind))
		grantPaid(player, placement, list, kind)
		return
	end
	setBusy(player, placement)
	push(player, placement)
	task.spawn(function()
		savePending(player, kind, placement, list)
		if player.Parent ~= Players then return end
		local ok, err = pcall(function() MarketplaceService:PromptProductPurchase(player, PRODUCT[kind]) end)
		if not ok then
			warn(LOG .. " окно покупки не открылось: " .. tostring(err))
			busy[player] = nil
			push(player, placement)
		end
	end)
end)

Dismiss.OnServerEvent:Connect(function(player, placement)
	if type(placement) ~= "string" or _G.RewardAdsIsBusy(player) then return end
	local o = offers[player] and offers[player][placement]
	if not o then return end
	if typeof(o.ctx.validate) == "function" and not o.ctx.validate(player) then return end
	_G.RewardAdsClearOffer(player, placement)
	callCtx(o, "onDismiss", player, o.claimed == true)
	print(("%s %s закрыл табличку %s"):format(LOG, player.Name, tostring(placement)))
end)

-- чек за ролик: бесплатная часть оффера
if (Config.DevProductId or 0) > 0 then
	local done = {}   -- PurchaseId → true (в пределах сессии: ролик ничего не стоит)
	task.spawn(function()
		local deadline = os.clock() + 30
		while typeof(_G.RegisterProductHandler) ~= "function" and os.clock() < deadline do task.wait(0.2) end
		if typeof(_G.RegisterProductHandler) ~= "function" then
			warn(LOG .. " реестр ProcessReceipt не поднялся — награда за рекламу не будет выдаваться")
			return
		end
		_G.RegisterProductHandler(Config.DevProductId, function(player, receipt)
			if done[receipt.PurchaseId] then return true end
			local placement = busy[player] or "boatman"
			busy[player] = nil
			done[receipt.PurchaseId] = true
			grantFree(player, placement)
			return true
		end)
	end)
end

-- ═══════════ жизненный цикл ═══════════
Players.PlayerAdded:Connect(function(p) st(p) hookHurt(p) end)
for _, p in ipairs(Players:GetPlayers()) do st(p) hookHurt(p) end
Players.PlayerRemoving:Connect(function(p)
	stats[p], offers[p], busy[p], busySince[p], lastClick[p] = nil, nil, nil, nil, nil
end)

-- блокировки меняются сами (бой кончился, ночь прошла), цена догружается — освежаем
task.spawn(function()
	while true do
		task.wait(2)
		for player, list in pairs(offers) do
			for placement, o in pairs(list) do
				if os.clock() > o.expiresAt and not busy[player] then _G.RewardAdsClearOffer(player, placement)
				else push(player, placement) end
			end
		end
	end
end)

print(("%s готов: реклама %s, «Бесплатно» %s, R$ all=%d premium=%d%s"):format(LOG,
	adsLive() and "включена" or "ВЫКЛЮЧЕНА", freeNeedsAd() and "через ролик" or "сразу",
	PRODUCT.all, PRODUCT.premium,
	(fakeBuy("all") or fakeBuy("premium")) and ", Studio: DebugFakePurchases" or ""))
