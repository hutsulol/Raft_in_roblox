--[[
	НАГРАДА С РЕЙДА (лодочник) + РЕКЛАМА ЗА НАГРАДУ — все числа и флаги
	(хендофф raft-reward-ads, этапы P1+P2).
	Сервер: RewardAdService.server. Клиент: RewardAdsController.client. UI: RewardAds/UI.

	Табличка лодочника: награда ОДНА на рейд — «Бесплатно» (только обычные)
	или «R$» (dev product RaidAll: обычные + премиум). После любой — лодочник уходит.
]]
return {
	-- ═══════════ реклама ═══════════
	-- ⚠️ ИГРА ПОКА НЕ ДОПУЩЕНА К REWARDED-РЕКЛАМЕ: false — ролики не показываются
	-- вовсе. Табличка лодочника от рекламы не зависит (FreeRequiresAd = false).
	AdsEnabled = false,
	-- «Бесплатно» у лодочника: true — через ролик, false — сразу (с тем же cooldown)
	FreeRequiresAd = false,

	-- Developer Product «Ad Reward — Resources» (награда за ролик). 0 = не создан
	DevProductId = 0,
	PlacementId = 0,
	-- ТОЛЬКО в Studio: «Смотреть» сразу выдаёт награду, без ролика — проверить UI
	DebugFakeAds = true,

	-- ═══════════ Robux у лодочника ═══════════
	-- ⚠️ ID DEV PRODUCTS (Creator Hub → игра → Monetization → Developer Products).
	-- 0 = не созданы: в опубликованной игре кнопки «R$» нет, остаётся «Бесплатно».
	-- Цену задаёт сам dev product — в UI она приходит из GetProductInfo.
	RaidAllProductId = 0,      -- обычные + премиум
	RaidPremiumProductId = 0,  -- не используется (премиум отдельно не продаётся)
	-- ТОЛЬКО в Studio и пока ID = 0: «R$» сразу выдаёт покупку, цены — эти
	DebugFakePurchases = true,
	DebugPriceAll = 49,
	DebugPricePremium = 35,

	-- ⚠️ СОСТАВ НАГРАДЫ РЕЙДА — ЗАГЛУШКА (игра пока не считает добычу рейда).
	-- Сервер берёт freeCount случайных из free и premiumCount из premium.
	RaidReward = {
		freeCount = 2,
		premiumCount = 2,
		-- id — как в InventoryManager (RESOURCE_NAMES); "Pirates" — монеты
		free = {
			{ id = "Log",     min = 15, max = 25 },
			{ id = "Plank",   min = 8,  max = 14 },
			{ id = "Rope",    min = 3,  max = 6 },
			{ id = "Plastic", min = 4,  max = 8 },
			{ id = "Stone",   min = 6,  max = 10 },
		},
		premium = {
			{ id = "Iron_Ingot", min = 3,   max = 5 },
			{ id = "Pirates",    min = 120, max = 200 },
			{ id = "Dry_Brick",  min = 6,   max = 10 },
		},
	},

	-- правила показа роликов (диздок, раздел 4.1) — считает сервер
	MinGapSeconds = 180,
	PerHour = 6,
	PerDay = 20,             -- ⚠️ пока в пределах сессии (без DataStore)
	NewbieGraceSeconds = 300, -- первые 5 минут новичка — никакой рекламы (в Studio не действует)
	CombatGraceSeconds = 10,  -- урон за последние 10 с = бой

	-- табличка над лодочником
	BillboardFullDistance = 20,   -- ближе — полная табличка, дальше — пилюля
	BillboardHysteresis = 2,
	BillboardMaxDistance = 60,
	BillboardDismissSeconds = 300,
	BillboardBob = true,          -- покачивание ±4px
	OfferLifetime = 600,

	-- потолки на любой оффер (RewardCap)
	RewardCap = { Log = 30, Plank = 20, Iron_Ingot = 5, Rope = 8, Plastic = 10, Stone = 12, Dry_Brick = 12, Pirates = 200 },
	-- чек пришёл, а оффера нет ни в памяти, ни в DataStore — выдаём это
	FallbackReward = { { id = "Log", amount = 10 }, { id = "Pirates", amount = 50 } },
}
