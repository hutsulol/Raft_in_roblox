-- WeaponUpgradeConfig.lua  (ReplicatedStorage, shared module)
-- ЕДИНЫЙ конфиг прокачки пушек за валюту «Pirate». Копия этого файла
-- живёт в ДВУХ проектах и должна совпадать байт-в-байт:
--   игра:  Desktop/Roblox/src/ReplicatedStorage/WeaponUpgradeConfig.lua
--   лобби: Desktop/Lobby_Loongoliers/src/Shared/WeaponUpgradeConfig.lua
--
-- Кто чем пользуется:
--   игра:  PirateProgression.server.lua (загрузка/сейв базы),
--          CannonControl / Pirate_Gun / AADefense (множитель урона)
--   лобби: WeaponUpgradeService.server.lua (покупка улучшений),
--          WeaponUpgradeUI.client.lua (меню прокачки)
--
-- База данных (общая на experience): DataStore "PirateProgress_v1",
-- ключ "player_<UserId>", данные { pirate, upgrades = {[id]=stars}, savedAt }.

local Config = {}

Config.DATASTORE_NAME = "PirateProgress_v1"
Config.KEY_PREFIX     = "player_"

-- атрибуты игрока (реплицируются на клиент автоматически)
Config.BALANCE_ATTR = "Pirate" -- тот же атрибут, что у PirateCurrency.server.lua
Config.ATTR_PREFIX  = "WUpg_"  -- WUpg_<weaponId> = купленные уровни (0..maxLevelsFor)

Config.DMG_PER_STAR = 0.15 -- +15% урона за уровень
Config.ROF_PER_STAR = 0.08 -- +8% скорострельности за уровень (там, где она есть)
-- сколько ЗВЁЗД (визуально) добавляет один купленный уровень:
-- 0.5 = половинка за уровень; отображение = baseStars + уровни × это
Config.STARS_PER_UPGRADE = 0.5
-- потолок звёзд у любой пушки (как рейтинг в меню коллекции)
Config.MAX_DISPLAY_STARS = 5

-- сколько уровней можно купить этой пушке: от родного рейтинга до
-- потолка в 5 звёзд (обычная 0.5★ → 9 уровней, эпик 2★ → 6 уровней)
function Config.maxLevelsFor(weapon)
	return math.max(0, math.floor(
		(Config.MAX_DISPLAY_STARS - (weapon.baseStars or 0)) / Config.STARS_PER_UPGRADE + 0.0001))
end

-- Список прокачиваемых пушек. id должен совпадать с именами моделей/тулов
-- в игре (CANNON_TYPES в CannonControl, тул Pirate_Gun, турели Deffender_*).
-- Иконки — из WeaponCollectionCatalog / RewardSystem.
-- baseStars — «родной» рейтинг пушки, как в WeaponCollectionCatalog
--   (0.5 = полузвезда); на плитке меню показывается baseStars + прокачка.
-- baseDmgPct/baseRofPct — проценты для длины полосок УРОН/ТЕМП в меню.
-- statDmg — РЕАЛЬНЫЙ урон прямого попадания (из ShipCombat: 100 × dmgMult);
--   в меню показывается statDmg × (1 + DMG_PER_STAR × уровни).
-- statRof — РЕАЛЬНАЯ скорострельность (выстр/мин), только у оружия,
--   где механика темпа существует (ручная пушка); растёт на ROF_PER_STAR.
-- basePrice — цена первой звезды; далее цена = basePrice * (звёзды + 1).
Config.Weapons = {
	{
		id = "Pirate_Gun", name = "РУЧНАЯ ПУШКА",
		rarity = "gray", rarityName = "ОБЫЧНЫЙ", color = "#9a9a9a",
		icon = "", -- иконки в проекте пока нет — в меню останется заглушка
		baseStars = 0.5, -- стартовая, в каталоге коллекции её нет
		baseDmgPct = 25, baseRofPct = 70, basePrice = 100,
		statDmg = 33, statRof = 60,
	},
	{
		id = "Cannon", name = "ПУШКА",
		rarity = "gray", rarityName = "ОБЫЧНЫЙ", color = "#9a9a9a",
		icon = "rbxassetid://118236242385241",
		baseStars = 0.5,
		baseDmgPct = 45, baseRofPct = 35, basePrice = 120,
		statDmg = 100,
	},
	{
		id = "Deffender", name = "ПВО",
		rarity = "green", rarityName = "НЕОБЫЧНЫЙ", color = "#4fc94f",
		icon = "rbxassetid://86928740553428",
		baseStars = 0.5,
		baseDmgPct = 30, baseRofPct = 55, basePrice = 150,
		-- урона не наносит: прокачка реально даёт +3% точности и
		-- +10% радиуса перехвата за уровень (AADefense)
	},
	{
		id = "MagmaCannon", name = "МАГМА-ПУШКА",
		rarity = "blue", rarityName = "РЕДКИЙ", color = "#3fa7e8",
		icon = "rbxassetid://97658619335375",
		baseStars = 0.5,
		baseDmgPct = 60, baseRofPct = 35, basePrice = 200,
		statDmg = 100, -- + поджог 12/с (тоже растёт с прокачкой)
	},
	{
		id = "Big_Magma_Cannon", name = "БОЛЬШАЯ МАГМА-ПУШКА",
		rarity = "epic", rarityName = "ЭПИЧЕСКИЙ", color = "#e86bc7",
		icon = "rbxassetid://90669361199026",
		baseStars = 2,
		baseDmgPct = 90, baseRofPct = 25, basePrice = 300,
		statDmg = 200, -- + поджог 24/с и взрыв по площади
	},
	-- Турели-пулемёты: урон применяет TurretSystem (statDmg = 100 × DmgMult).
	{
		id = "Pulemet_lvl_1", name = "ПУЛЕМЁТ",
		rarity = "blue", rarityName = "РЕДКИЙ", color = "#3fa7e8",
		icon = "rbxassetid://106277044945645",
		baseStars = 1.5,
		baseDmgPct = 35, baseRofPct = 95, basePrice = 220,
		statDmg = 15, -- 100 × DmgMult 0.15
	},
	{
		id = "Pulemet_lvl_2", name = "ПУЛЕМЁТ II",
		rarity = "epic", rarityName = "ЭПИЧЕСКИЙ", color = "#e86bc7",
		icon = "rbxassetid://79105833790080",
		baseStars = 3,
		baseDmgPct = 70, baseRofPct = 95, basePrice = 350,
		statDmg = 35, -- 100 × DmgMult 0.35
	},
}

Config.ById = {}
for _, w in ipairs(Config.Weapons) do
	Config.ById[w.id] = w
end

-- ─── Разблокировка пушек (магазин в меню лобби) ────────────────────────
-- Пушки из этого списка НЕДОСТУПНЫ с начала игры: они не выпадают из ночной
-- рулетки, пока игрок не купит разблокировку за пиратов в лобби. После покупки
-- пушка возвращается в пул, и проценты выпадения ВСЕХ призов пересчитываются
-- (RewardRoll.buildPool фильтрует пул, а % считается от суммы активного пула).
-- Данные лежат в ТОМ ЖЕ ключе PirateProgress_v1: data.unlocks = { [id] = true }.
Config.UNLOCK_ATTR_PREFIX = "WUnlock_" -- WUnlock_<id> = 1, если разблокировка куплена

--[[ ⚠️ ВЫБРАННАЯ ПУШКА — НОВОЕ ПОНЯТИЕ, ЕГО РАНЬШЕ НЕ БЫЛО.
     Меню арсенала показывало прокачку, но «какая пушка у меня в витрине и
     поедет в игру» нигде не хранилось. Держим как отдельное поле базы
     (data.selectedWeapon) и атрибут игрока: атрибут реплицируется сам, поэтому
     и меню лобби, и океан читают выбор без единого ремоута.
     Пустая строка = ничего не выбрано, показываем первую доступную. ]]
Config.WEAPON_SELECTED_ATTR = "WeaponSelected"

Config.Unlocks = {
	{ id = "Pulemet_lvl_2", name = "ПУЛЕМЁТ II", icon = "rbxassetid://79105833790080",
	  rarity = "epic", rarityName = "ЭПИЧЕСКИЙ", color = "#e86bc7", price = 10000,
	  description = "Эпическая турель: тот же Гатлинг, но урон вдвое выше." },
	{ id = "MagmaCannon", name = "МАГМА-ПУШКА", icon = "rbxassetid://97658619335375",
	  rarity = "blue", rarityName = "РЕДКИЙ", color = "#3fa7e8", price = 30000,
	  description = "Стреляет раскалённой магмой." },
}

Config.UnlockById = {}
for _, u in ipairs(Config.Unlocks) do
	Config.UnlockById[u.id] = u
end

-- true, если пушка доступна игроку: либо она вообще не требует разблокировки,
-- либо разблокировка куплена. Используют и лобби (витрина), и игра (рулетка).
function Config.isUnlocked(player, weaponId)
	if not Config.UnlockById[weaponId] then return true end -- не заблокирована в принципе
	if not player then return false end
	return (tonumber(player:GetAttribute(Config.UNLOCK_ATTR_PREFIX .. weaponId)) or 0) >= 1
end

-- Ежедневные награды (лобби): день 1 — 100, дни 2..7 — 500.
-- Понижены в 10 раз от прежних 1000/5000: столько монет за вход обесценивало
-- и прокачку пушек, и магазин.
-- После 7-го дня цикл начинается заново.
Config.DAILY_REWARDS  = { 100, 500, 500, 500, 500, 500, 500 }
Config.DAILY_COOLDOWN = 24 * 60 * 60 -- секунд между наградами

-- ─── Рекорд выживания ──────────────────────────────────────────────────
-- Сколько дней игрок продержался в лучшем заходе. Пишет ИГРА (океан) по
-- счётчику ReplicatedStorage.DayCount, показывает ЛОББИ — табличка над
-- головой. Живёт в том же ключе PirateProgress_v1, поле data.daysRecord.
--
-- ⚠️ РЕКОРД НИКОГДА НЕ УМЕНЬШАЕТСЯ. Любая запись идёт через math.max: заход
-- на один день не должен стирать прошлые тридцать, а гонка двух серверов
-- (игрок в океане, лобби дописывает свой ключ) не должна откатывать число.
-- ⚠️ И НЕ ЖДЁТ КОНЦА ЗАХОДА: фиксируется в момент наступления нового дня,
-- иначе вылет или закрытие клиента съедали бы весь прогресс сессии.
Config.DAYS_RECORD_ATTR = "DaysRecord"   -- атрибут игрока (реплицируется всем)
Config.DAYS_RECORD_ICON = "rbxassetid://139369971864551"
-- атрибуты игрока для UI ежедневки (ставит WeaponUpgradeService)
Config.DAILY_CLAIMED_ATTR = "DailyClaimed"   -- забрано дней в цикле (0..7)
Config.DAILY_LAST_ATTR    = "DailyLastClaim" -- os.time() последнего клейма

-- ─── Классы (общий конфиг, тот же DataStore/ключ) ──────────────────────
-- Данные класса живут в ТОМ ЖЕ ключе PirateProgress_v1:
--   data.class = { selected = "diver"/"survivor"/"", levels = {[id]=0..3} }
-- Покупка (0→1) стоит levelPrices[1], улучшения — levelPrices[2..3].
-- Атрибуты игрока (реплицируются на клиент автоматически):
Config.CLASS_SELECTED_ATTR = "ClassSelected"  -- id выбранного класса или ""
Config.CLASS_LEVEL_PREFIX  = "ClassLvl_"      -- ClassLvl_<id> = уровень 0..3
Config.MAX_CLASS_LEVEL     = 3

Config.Classes = {
	{ id = "diver",    name = "ДАЙВЕР",   levelPrices = { 10000, 20000, 50000 } },
	{ id = "survivor", name = "ВЫЖИВШИЙ", levelPrices = { 10000, 20000, 50000 } },
}

Config.ClassById = {}
for _, c in ipairs(Config.Classes) do
	Config.ClassById[c.id] = c
end

-- цена перехода на следующий уровень (currentLevel 0..2 → цена уровня +1)
function Config.classPriceFor(class, currentLevel)
	return class.levelPrices[(tonumber(currentLevel) or 0) + 1]
end

-- уровень класса у игрока (из атрибута), 0..MAX_CLASS_LEVEL
function Config.classLevelOf(player, classId)
	return math.clamp(math.floor(player:GetAttribute(Config.CLASS_LEVEL_PREFIX .. classId) or 0), 0, Config.MAX_CLASS_LEVEL)
end

-- id выбранного (активного) класса игрока, или nil
function Config.selectedClassOf(player)
	local s = player:GetAttribute(Config.CLASS_SELECTED_ATTR)
	return (type(s) == "string" and s ~= "") and s or nil
end

-- «активный» уровень класса: уровень, если класс ВЫБРАН, иначе 0.
-- Эффекты класса в игре работают только у выбранного класса.
function Config.activeClassLevel(player, classId)
	if Config.selectedClassOf(player) == classId then
		return Config.classLevelOf(player, classId)
	end
	return 0
end

-- Бонус урона класса «Выживший» (2 ур.): множитель к урону оружия
-- (ближний/дальний бой + пушки). Гейтится на ВЫБРАННОМ классе.
Config.SURVIVOR_DMG_MULT = 1.25
function Config.survivorWeaponMult(player)
	if not player then return 1 end -- пушка без стрелявшего игрока → без бонуса
	return (Config.activeClassLevel(player, "survivor") >= 2) and Config.SURVIVOR_DMG_MULT or 1
end

-- Админы (доступ к админ-панели в лобби: сброс баланса/уровней).
-- Владелец плейса — админ автоматически; сюда можно дописать UserId.
--[[ ⚠️ ОДИН КРЕСТИК ЗАКРЫТИЯ НА ВСЕ МЕНЮ ЛОББИ.
     Тот же арт, что в модале «Создать пати» (Lobby/LobbyMainUI, CROSS_IMAGE):
     красный квадрат с белым крестом, подложка и обводка нарисованы прямо на
     картинке — свои UICorner и UIStroke под него класть не нужно, получится
     квадрат под квадратом со сдвоенной кромкой.
     Посадка везде одна: AnchorPoint (0.5, 0.5) и Position (1, 0, 0, 0) —
     кнопка целиком ВНУТРИ панели, в правом верхнем углу с отступом 10 px.
     ⚠️ В океане тот же ассет лежит в ReplicatedStorage/UITheme.lua
     (UITheme.Icons.close): проекты разные, модули не общие. Меняешь арт —
     меняй в обоих. ]]
Config.CLOSE_ICON = "rbxassetid://138740812666533"

Config.ADMIN_USER_IDS = {
	1056989872, -- hutsulG
}

-- Паки магазина «Купить пираты» (лобби). ПОКА БЕЗ Robux: кнопка цены
-- просто начисляет amount (тестовая заглушка). Когда будут созданы
-- Developer Products — заменить начисление в PirateShopService на
-- MarketplaceService.ProcessReceipt по productId.
Config.SHOP_PACKS = {
	{ amount = 300000, robux = 1000 },
	{ amount = 90000,  robux = 360 },
	{ amount = 40000,  robux = 160 },
	{ amount = 10000,  robux = 40 },
}

-- цена следующей звезды
function Config.priceFor(weapon, currentStars)
	return weapon.basePrice * (currentStars + 1)
end

-- множитель урона за прокачку
function Config.multFor(stars)
	return 1 + Config.DMG_PER_STAR * (tonumber(stars) or 0)
end

-- множитель скорострельности за прокачку
function Config.rofMultFor(stars)
	return 1 + Config.ROF_PER_STAR * (tonumber(stars) or 0)
end

-- звёзды прокачки пушки у игрока (из атрибута)
function Config.starsOf(player, weaponId)
	return player:GetAttribute(Config.ATTR_PREFIX .. weaponId) or 0
end

--[[ ⚠️ ОДНО ПРАВИЛО «КТО АДМИН» НА ВСЕ ЭКРАНЫ ОБОИХ ПРОЕКТОВ.
     Правило уже жило в двух местах — SettingsMenuActions на сервере и
     SettingsMenu на клиенте — и оба файла носят приписку «обязано совпадать»,
     потому что расхождение даёт худший вид поломки: кнопка видна и мертва.
     Третью и четвёртую копию заводить нельзя, поэтому правило переехало сюда:
     этот модуль и так требуют обе стороны.
     Три источника, ровно те же, что были: список UserId, владелец плейса и
     Studio. У ГРУППОВОГО плейса CreatorId — это id группы, поэтому сравнение с
     UserId там не совпадёт никогда: проверяем рангом 255.
     ⚠️ Studio считается админом намеренно: без этого разработчик не может
     проверить ни один экран, где что-то даётся за админство. ]]
function Config.isAdmin(player)
	if not player then return false end
	if game:GetService("RunService"):IsStudio() then return true end
	if table.find(Config.ADMIN_USER_IDS or {}, player.UserId) then return true end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
		return (ok and rank == 255) or false
	end
	return false
end

return Config
