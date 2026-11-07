-- Strength.server.lua
-- СИЛА — УРОВЕНЬ, КОТОРЫЙ РАСТЁТ ОТ УДАРОВ, А НЕ ОЧКО ИЗ МЕНЮ.
--
-- Как это работает:
--   • за каждый удар по добываемому ресурсу игрок получает 1 очко опыта;
--   • очки копятся до порога, порог с каждым уровнем удваивается:
--     0→1 сто ударов, 1→2 двести, 2→3 четыреста и так далее;
--   • максимальный уровень — 10.
--
-- Что даёт уровень:
--   • каждые 2 уровня  → +1 слот в инвентаре;
--   • каждые 5 уровней → +1 удар за клик (на 5-м клик бьёт дважды, на 10-м трижды),
--     то есть бревно разваливается за вдвое меньше кликов.
--
-- ⚠️ РАНЬШЕ СИЛА БЫЛА ОЧКОМ ПРОКАЧКИ, И ЧИСЛО НИЧЕГО НЕ ДЕЛАЛО.
-- Значение поднималось из меню телефона за очки уровня, слот открывался каждые
-- 2 очка, удар рос каждые 3. Игрок этих чисел не зарабатывал и не видел, во что
-- они превращаются, — в HUD стояли две цифры через точку без подписей.
-- Теперь у силы есть собственный источник (удары), собственная шкала (уровень с
-- полосой) и понятная цена: следующий уровень стоит вдвое дороже предыдущего.
--
-- Наружу публикуется тремя способами, у каждого своя причина:
--   • IntValue в Characteristics — их читает интерфейс, репликация бесплатная;
--   • _G.GetHitPower(player)     — для серверных систем (ResourceSpawner);
--   • атрибут игрока "HitPower"  — клиенту, чтобы предсказание звука поломки
--     считало так же, как сервер, а не по одному очку за клик.

local Players = game:GetService("Players")

local HOTBAR_SLOTS     = 8
local BASE_GRID_SLOTS  = 5   -- always-unlocked first row
local MAX_GRID_SLOTS   = 20  -- 4 rows × 5 cols
local SLOTS_PER_LEVELS = 2   -- +1 слот инвентаря за каждые 2 уровня

-- Сила удара: база и цена одного дополнительного очка урона.
local BASE_HIT       = 1
local HIT_PER_LEVELS = 5     -- +1 к удару за каждые 5 уровней

--[[ ⚠️ ПОТОЛОК УРОВНЯ ЖЁСТКИЙ, И ЭТО ВАЖНО ДЛЯ ПОРОГОВ.
     Пороги удваиваются, поэтому без потолка десятый уровень стоил бы пятьдесят
     тысяч ударов, одиннадцатый сто — шкала перестаёт быть целью и становится
     насмешкой. Десять — то место, где рост ещё осмыслен. ]]
local MAX_LEVEL  = 10
local XP_BASE    = 100   -- ударов на первый уровень
local XP_GROWTH  = 2     -- каждый следующий уровень вдвое дороже

--[[ Сколько ударов нужно, чтобы уйти с этого уровня на следующий.
     На максимуме — ноль: копить больше некуда, и полоса стоит полной. ]]
local function xpForNext(level)
	if level >= MAX_LEVEL then return 0 end
	return math.floor(XP_BASE * (XP_GROWTH ^ level))
end

local function computeUnlockedSlots(level)
	local bonus = math.floor(level / SLOTS_PER_LEVELS)
	local grid  = math.min(BASE_GRID_SLOTS + bonus, MAX_GRID_SLOTS)
	return HOTBAR_SLOTS + grid
end

local function computeHitPower(level)
	return BASE_HIT + math.floor(level / HIT_PER_LEVELS)
end

local function intValue(folder, name, value)
	local v = folder:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Parent = folder
	end
	v.Value = value
	return v
end

-- Всё, что нужно знать про силу конкретного игрока, в одном месте.
local state = {}   -- [player] = { level, xp, required, unlocked, hitPower, folder }

--[[ ⚠️ СИЛА ЖИВЁТ В СЕЙВЕ ПЛОТА, А НЕ САМА ПО СЕБЕ.
     Первый заход я сделал ей отдельный DataStore — и это было неверно по сути
     игры: прогресс оказался бы «на аккаунте», и новый забег начинался бы сразу
     с прокачанной силой. Сила — часть конкретного плота: сохранил игру и
     вернулся к ней — сила при тебе; начал новую — качаешь заново.
     Поэтому хранилища здесь нет вовсе. Наружу отдаются две ручки, а записывает
     и читает их RaftSaveSystem вместе с инвентарём, инструментами и плотом. ]]

local function publish(player)
	local s = state[player]
	if not s then return end
	s.required.Value = xpForNext(s.level.Value)
	s.unlocked.Value = computeUnlockedSlots(s.level.Value)
	s.hitPower.Value = computeHitPower(s.level.Value)
	-- клиенту для предсказания звука поломки: он считает свои клики и должен
	-- знать цену удара, иначе «хруст» срывается раньше или позже времени
	player:SetAttribute("HitPower", s.hitPower.Value)
end

local function bindPlayer(player)
	-- Characteristics.server.lua создаёт папку и значения на PlayerAdded, но мы
	-- можем стартовать раньше — поэтому ждём.
	local folder = player:WaitForChild("Characteristics")
	local level  = folder:WaitForChild("Strength")   -- имя прежнее: его читает HUD и меню

	-- ссылку держим локально: её же кладём в state и отдаём наружу через ручки
	local s = {
		folder   = folder,
		level    = level,
		xp       = intValue(folder, "StrengthXP", 0),
		required = intValue(folder, "StrengthXPRequired", xpForNext(level.Value)),
		unlocked = intValue(folder, "UnlockedInventorySlots", computeUnlockedSlots(level.Value)),
		hitPower = intValue(folder, "HitPower", computeHitPower(level.Value)),
	}
	state[player] = s
	-- потолок шкалы — тоже значением, а не константой в клиенте: иначе полоска
	-- разъедется с балансом при первой же правке чисел выше
	intValue(folder, "StrengthMax", MAX_LEVEL)

	publish(player)
	-- уровень могут поднять и снаружи (тесты, админка) — пересчитываем следом
	level:GetPropertyChangedSignal("Value"):Connect(function() publish(player) end)

end

--[[ Что положить в сейв плота. nil — если игрок ещё не поднялся: писать нули
     поверх сохранённого прогресса нельзя. ]]
_G.GetStrengthSave = function(player)
	local s = state[player]
	if not s then return nil end
	return { level = s.level.Value, xp = s.xp.Value }
end

--[[ Что применить при загрузке сейва. Зовётся из RaftSaveSystem.
     ⚠️ ОПЫТ СВЕРЯЕМ С ТЕКУЩИМ ПОРОГОМ: правка баланса могла удешевить уровень,
     и старое число оказалось бы больше нового порога — полоса показала бы
     «больше полной» и застряла. ]]
_G.ApplyStrengthSave = function(player, data)
	local s = state[player]
	if not (s and type(data) == "table") then return end

	local lvl = math.clamp(math.floor(tonumber(data.level) or 0), 0, MAX_LEVEL)
	local xp  = math.max(math.floor(tonumber(data.xp) or 0), 0)
	local need = xpForNext(lvl)

	s.xp.Value = (need > 0) and math.min(xp, need - 1) or 0
	s.level.Value = lvl   -- publish пересчитает слоты, удар и порог
	publish(player)
	print(("[Сила] %s: из сейва восстановлен уровень %d (опыт %d)")
		:format(player.Name, lvl, s.xp.Value))
end

_G.AddStrengthXP = function(player, amount)
	if typeof(player) ~= "Instance" then return end
	local s = state[player]
	if not s then return end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return end

	if s.level.Value >= MAX_LEVEL then
		s.xp.Value = 0
		return
	end

	local xp = s.xp.Value + amount
	local level = s.level.Value
	local need = xpForNext(level)

	while need > 0 and xp >= need do
		xp -= need
		level += 1
		if level >= MAX_LEVEL then
			xp = 0
			break
		end
		need = xpForNext(level)
	end

	s.xp.Value = xp
	if level ~= s.level.Value then
		s.level.Value = level   -- сигнал изменения пересчитает остальное сам
		print(("[Сила] %s — уровень %d, следующий за %d ударов")
			:format(player.Name, level, xpForNext(level)))
	else
		s.required.Value = need
	end
end

-- Для серверных систем (ResourceSpawner). Возвращает 1, пока характеристик нет:
-- удар по ресурсу должен работать и до того, как всё поднялось.
_G.GetHitPower = function(player)
	if typeof(player) ~= "Instance" then return BASE_HIT end
	local folder = player:FindFirstChild("Characteristics")
	local hp = folder and folder:FindFirstChild("HitPower")
	local v = hp and tonumber(hp.Value)
	return (v and v > 0) and v or BASE_HIT
end

for _, p in Players:GetPlayers() do
	task.spawn(bindPlayer, p)
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(bindPlayer, p)
end)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)
