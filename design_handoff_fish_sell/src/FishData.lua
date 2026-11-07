-- ReplicatedStorage/FishData (ModuleScript)
-- Выручка (pirate) = вес × coef, clamp 0.5..15
-- Вес смещён к лёгкому: min + (max - min) * r^2

local FishData = {}

-- glow = цвет свечения и названия (ImageColor3 / TextColor3), spin = сек на оборот лучей
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

-- image = rbxassetid рендера рыбы (заполнить после загрузки)
FishData.Fish = {
	{ id = "sardine",    name = "Сардина",         rarity = "common",    minKg = 0.25, maxKg = 0.6,   coef = 2.0,  image = "rbxassetid://0" }, -- 0.50–1.20
	{ id = "mackerel",   name = "Скумбрия",        rarity = "common",    minKg = 0.45, maxKg = 1.0,   coef = 1.2,  image = "rbxassetid://0" }, -- 0.54–1.20
	{ id = "seabass",    name = "Морской окунь",   rarity = "common",    minKg = 0.65, maxKg = 1.5,   coef = 0.8,  image = "rbxassetid://0" }, -- 0.52–1.20
	{ id = "dorado",     name = "Дорадо",          rarity = "uncommon",  minKg = 1.0,  maxKg = 2.5,   coef = 0.8,  image = "rbxassetid://0" }, -- 0.80–2.00
	{ id = "bream",      name = "Морской лещ",     rarity = "uncommon",  minKg = 0.8,  maxKg = 2.0,   coef = 1.0,  image = "rbxassetid://0" }, -- 0.80–2.00
	{ id = "barracuda",  name = "Барракуда",       rarity = "rare",      minKg = 2.0,  maxKg = 4.6,   coef = 0.75, image = "rbxassetid://0" }, -- 1.50–3.45
	{ id = "tuna",       name = "Тунец",           rarity = "rare",      minKg = 5.0,  maxKg = 12.0,  coef = 0.3,  image = "rbxassetid://0" }, -- 1.50–3.60
	{ id = "swordfish",  name = "Рыба-меч",        rarity = "epic",      minKg = 12.0, maxKg = 20.0,  coef = 0.25, image = "rbxassetid://0" }, -- 3.00–5.00
	{ id = "goldfugu",   name = "Золотая фугу",    rarity = "epic",      minKg = 1.0,  maxKg = 1.6,   coef = 3.1,  image = "rbxassetid://0" }, -- 3.10–4.96
	{ id = "marlin",     name = "Синий марлин",    rarity = "legendary", minKg = 50.0, maxKg = 62.5,  coef = 0.08, image = "rbxassetid://0" }, -- 4.00–5.00
	{ id = "ghostray",   name = "Призрачный скат", rarity = "legendary", minKg = 8.0,  maxKg = 10.0,  coef = 0.5,  image = "rbxassetid://0" }, -- 4.00–5.00
	{ id = "krakenling", name = "Кракенёнок",      rarity = "mythic",    minKg = 30.0, maxKg = 75.0,  coef = 0.2,  image = "rbxassetid://0" }, -- 6.00–15.00
	{ id = "leviathan",  name = "Левиафан",        rarity = "mythic",    minKg = 60.0, maxKg = 150.0, coef = 0.1,  image = "rbxassetid://0" }, -- 6.00–15.00
}

FishData.FishById = {}
for _, f in ipairs(FishData.Fish) do FishData.FishById[f.id] = f end

local MIN_PAY, MAX_PAY = 0.5, 15

local byRarity = {}
for _, f in ipairs(FishData.Fish) do
	byRarity[f.rarity] = byRarity[f.rarity] or {}
	table.insert(byRarity[f.rarity], f)
end

-- Только на сервере. Возвращает { fishId, weight, pay }
function FishData.Roll(rng: Random?)
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
	local weight = fish.minKg + (fish.maxKg - fish.minKg) * t * t
	weight = math.floor(weight * 100 + 0.5) / 100
	local pay = math.clamp(weight * fish.coef, MIN_PAY, MAX_PAY)
	pay = math.floor(pay * 100 + 0.5) / 100
	return { fishId = fish.id, weight = weight, pay = pay }
end

-- "3,19"
function FishData.Format(n: number): string
	return (string.format("%.2f", n):gsub("%.", ","))
end

return FishData
