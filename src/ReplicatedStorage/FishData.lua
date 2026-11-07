--[[
	РЫБЫ УЛОВА (хендофф design_handoff_fish_sell, «Продажа улова»).
	Выручка (pirate) = вес × coef, рамки 0.5…15. Вес смещён к лёгкому:
	min + (max − min) · r². Внутри редкости рыбы выпадают поровну.
	Ролл — только на сервере (FishingService), попап — FishingEffects.client.

	model — имя 3D-модели рыбы (ReplicatedStorage.FishModels, пак Tripo).
	size  — длина рыбы в руке рыбака, студы (хендофф FishModels_Handheld/sizes.json).
	Её вытаскивает рыбак и она же крутится в попапе. Пока своей модели нет —
	берётся DEFAULT_MODEL («Legendary Fish»), иначе старая заглушка FishermanFish.
]]

local FishData = {}

-- glow = цвет свечения (ImageColor3), text = цвет названия, spin = сек на оборот лучей
FishData.Rarities = {
	{ id = "common",    name = "Обычная",     chance = 70,  glow = Color3.fromHex("C9D2DC"), text = Color3.fromHex("E3EBF3"), spin = 9   },
	{ id = "uncommon",  name = "Необычная",   chance = 20,  glow = Color3.fromHex("6CC0FF"), text = Color3.fromHex("8FD0FF"), spin = 8   },
	{ id = "rare",      name = "Редкая",      chance = 7.4, glow = Color3.fromHex("3F9BFF"), text = Color3.fromHex("5AAEFF"), spin = 7   },
	{ id = "epic",      name = "Эпическая",   chance = 2,   glow = Color3.fromHex("B26CFF"), text = Color3.fromHex("C792FF"), spin = 6   },
	{ id = "legendary", name = "Легендарная", chance = 0.5, glow = Color3.fromHex("FFC83A"), text = Color3.fromHex("FFD95A"), spin = 5   },
	{ id = "mythic",    name = "Мифическая",  chance = 0.1, glow = Color3.fromHex("FFC83A"), text = Color3.fromHex("FFD95A"), spin = 2.5 },
}
FishData.RarityById = {}
for _, r in ipairs(FishData.Rarities) do FishData.RarityById[r.id] = r end

-- модель-заглушка для всех рыб, пока пак моделей не добавлен
FishData.DEFAULT_MODEL = "Legendary Fish"

FishData.Fish = {
	{ id = "sardine",    name = "Сардина",         rarity = "common",    minKg = 0.25, maxKg = 0.6,   coef = 2.0,  model = "Fish_Sardine",    size = 1.35 }, -- 0.50–1.20
	{ id = "mackerel",   name = "Скумбрия",        rarity = "common",    minKg = 0.45, maxKg = 1.0,   coef = 1.2,  model = "Fish_Mackerel",   size = 1.65 }, -- 0.54–1.20
	{ id = "seabass",    name = "Морской окунь",   rarity = "common",    minKg = 0.65, maxKg = 1.5,   coef = 0.8,  model = "Fish_Seabass",    size = 1.9 }, -- 0.52–1.20
	{ id = "dorado",     name = "Дорадо",          rarity = "uncommon",  minKg = 1.0,  maxKg = 2.5,   coef = 0.8,  model = "Fish_Dorado",     size = 2 }, -- 0.80–2.00
	{ id = "bream",      name = "Морской лещ",     rarity = "uncommon",  minKg = 0.8,  maxKg = 2.0,   coef = 1.0,  model = "Fish_Bream",      size = 1.7 }, -- 0.80–2.00
	{ id = "barracuda",  name = "Барракуда",       rarity = "rare",      minKg = 2.0,  maxKg = 4.6,   coef = 0.75, model = "Fish_Barracuda",  size = 2.5 }, -- 1.50–3.45
	{ id = "tuna",       name = "Тунец",           rarity = "rare",      minKg = 5.0,  maxKg = 12.0,  coef = 0.3,  model = "Fish_Tuna",       size = 2.4 }, -- 1.50–3.60
	{ id = "swordfish",  name = "Рыба-меч",        rarity = "epic",      minKg = 12.0, maxKg = 20.0,  coef = 0.25, model = "Fish_Swordfish",  size = 2.8 }, -- 3.00–5.00
	{ id = "goldfugu",   name = "Золотая фугу",    rarity = "epic",      minKg = 1.0,  maxKg = 1.6,   coef = 3.1,  model = "Fish_GoldFugu",   size = 1.55 }, -- 3.10–4.96
	{ id = "marlin",     name = "Синий марлин",    rarity = "legendary", minKg = 50.0, maxKg = 62.5,  coef = 0.08, model = "Fish_Marlin",     size = 3 }, -- 4.00–5.00
	{ id = "ghostray",   name = "Призрачный скат", rarity = "legendary", minKg = 8.0,  maxKg = 10.0,  coef = 0.5,  model = "Fish_GhostRay",   size = 2.5 }, -- 4.00–5.00
	{ id = "krakenling", name = "Кракенёнок",      rarity = "mythic",    minKg = 30.0, maxKg = 75.0,  coef = 0.2,  model = "Fish_Krakenling", size = 2.2 }, -- 6.00–15.00
	{ id = "leviathan",  name = "Левиафан",        rarity = "mythic",    minKg = 60.0, maxKg = 150.0, coef = 0.1,  model = "Fish_Leviathan",  size = 3.2 }, -- 6.00–15.00
}
FishData.FishById = {}
for _, f in ipairs(FishData.Fish) do FishData.FishById[f.id] = f end

local MIN_PAY, MAX_PAY = 0.5, 15

local byRarity = {}
for _, f in ipairs(FishData.Fish) do
	byRarity[f.rarity] = byRarity[f.rarity] or {}
	table.insert(byRarity[f.rarity], f)
end

local function result(fish, weight)
	weight = math.floor(weight * 100 + 0.5) / 100
	local pay = math.clamp(weight * fish.coef, MIN_PAY, MAX_PAY)
	pay = math.floor(pay * 100 + 0.5) / 100
	return { fishId = fish.id, weight = weight, pay = pay }
end

-- только на сервере: { fishId, weight, pay }
function FishData.Roll(rng)
	rng = rng or Random.new()
	local x = rng:NextNumber() * 100
	local rarity = FishData.Rarities[1]
	for _, r in ipairs(FishData.Rarities) do
		if x < r.chance then rarity = r break end
		x -= r.chance
	end
	local pool = byRarity[rarity.id]
	local fish = pool[rng:NextInteger(1, #pool)]
	local t = rng:NextNumber()
	return result(fish, fish.minKg + (fish.maxKg - fish.minKg) * t * t)
end

-- заданная рыба (тест из настроек): вес — середина диапазона
function FishData.Fixed(fishId, rng)
	local fish = FishData.FishById[fishId]
	if not fish then return nil end
	rng = rng or Random.new()
	return result(fish, fish.minKg + (fish.maxKg - fish.minKg) * rng:NextNumber())
end

-- модель рыбы в ReplicatedStorage (своя, иначе DEFAULT_MODEL) или nil
function FishData.ModelFor(fish)
	local RS = game:GetService("ReplicatedStorage")
	-- сначала папка пака: тёзки могут лежать и в других моделях хранилища
	local pack = RS:FindFirstChild("FishModels")
	local own = pack and fish and fish.model and pack:FindFirstChild(fish.model)
	if own and (own:IsA("Model") or own:IsA("BasePart")) then return own end
	for _, name in ipairs({ fish and fish.model or "", FishData.DEFAULT_MODEL }) do
		-- модели лежат в папке (ReplicatedStorage.Fish), ищем по всему хранилищу
		local m = name ~= "" and RS:FindFirstChild(name, true)
		if m and (m:IsA("Model") or m:IsA("BasePart")) then return m end
	end
	return nil
end

-- "3,19"
function FishData.Format(n)
	return (string.format("%.2f", n):gsub("%.", ","))
end

return FishData
