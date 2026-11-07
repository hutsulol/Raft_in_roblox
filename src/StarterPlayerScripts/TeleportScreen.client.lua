--[[
	ЭКРАН ПЕРЕМЕЩЕНИЯ ПЛОТА — полноэкранная шторка на время телепорта.

	Сервер шлёт по RemoteEvent «MapTeleport»:
	    ("start", { island = id, name = "имя", kind = "forest"|"iron"|"oil" })
	    ("done")
	Между ними он дёргает плот, и в этот момент игрок обязан видеть чёрное, а не
	мир, который прыгает на километр вбок.

	Числа и тайминги — из хендофа (README.md в корне) и прототипа «Телепорт.dc.html».
	Рантайм прототипа (image-slot.js) в игру не переносится, повторяется только вид.

	⚠️ ТРИ СРОКА, КОТОРЫЕ ДЕРЖАТ ВСЮ МЕХАНИКУ, И НИ ОДИН НЕ ДЕКОРАТИВНЫЙ.
	1. Вход 0.45 с. Сервер дёргает плот через 1.4 с после «start», значит к рывку
	   у нас почти секунда запаса даже на кривой сети. Растянешь вход до полутора
	   секунд — игрок увидит телепорт сквозь полупрозрачную шторку.
	2. Удержание не меньше 2 с. «done» приходит и через 0.3 с (сервер уже держал
	   плот у цели): без нижней границы экран мигнул бы и погас, и это читается
	   как баг, а не как перемещение.
	3. Аварийный сход через 12 с. Если «done» не придёт вовсе (серверный скрипт
	   упал, ремоут не долетел), без этого таймера игрок остаётся в чёрном
	   навсегда — и не может даже выйти из игры осмысленно.

	⚠️ КАРТИНКИ — ТОЛЬКО ТЕ, ЧТО ЗАЛИЛ ВЛАДЕЛЕЦ (таблица ASSETS ниже).
	Лодка и острова — PNG владельца. Тайлы волн лежат в uploads/teleport и ждут
	загрузки; пока их ID пустые, волны рисуются отрезками. Силуэты из плашек
	оставлены запасным вариантом: битый или пустой ID иначе дал бы пустое место.

	⚠️ ГРУППОВОЙ ПРОЗРАЧНОСТИ НЕТ, ГАСИМ ПОШТУЧНО ПО РЕЕСТРУ.
	CanvasGroup.GroupTransparency в этом проекте обжигал дважды (RewardReveal:
	«на части клиентов молча не применялся»; InventoryNotify: «гасил только фон»).
	Поэтому все гаснущие элементы один раз собираются в список
	{объект, свойство, базовая прозрачность}, и переходы пишут по нему. Список
	трогается ТОЛЬКО во время входа и выхода: на удержании множитель не меняется,
	и цикл по четырёмстам фреймам не крутится впустую.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ═══════════ цвета ═══════════

local WHITE    = Color3.new(1, 1, 1)
local BG_EDGE  = Color3.fromRGB(5, 6, 7)     -- #050607, края
local BG_CORE  = Color3.fromRGB(13, 15, 18)  -- #0D0F12, центр
-- Цвет фона под волнами: им гасится яркая часть волн у носа лодки (см. veil).
-- Взято среднее между краем и центром — разница в 8 из 255 на экране не читается.
local VEIL_C   = Color3.fromRGB(9, 11, 14)

-- ═══════════ примитивы: отрезок и плашка ═══════════

--[[ ⚠️ ЛИНИЙ И ТРЕУГОЛЬНИКОВ В ROBLOX UI НЕТ ВООБЩЕ.
     Всё, что в хендофе нарисовано path'ом, здесь собирается из повёрнутых
     прямоугольников. box — система координат макета (иконка острова 64×44,
     лодка 32×26): позиция и размер считаются в Scale, а не в Offset, потому что
     Offset целочисленный и срезал бы дробные доли — на отрезке длиной 4.9 px
     это ломает и наклон, и стык с соседним. ]]
local function bar(parent, box, x1, y1, x2, y2, thick)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x1 + x2) * 0.5 / box.X, (y1 + y2) * 0.5 / box.Y),
		Size = UDim2.fromScale(len / box.X, thick / box.Y),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	return f
end

-- round задаётся в долях меньшей стороны, а не в пикселях: пиксельный радиус не
-- поехал бы вместе с UIScale, и на телефоне углы стали бы вдвое круглее.
local function slab(parent, box, cx, cy, w, h, round)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx / box.X, cy / box.Y),
		Size = UDim2.fromScale(w / box.X, h / box.Y),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2,
	}, parent)
	if round and round > 0 then
		new("UICorner", { CornerRadius = UDim.new(round, 0) }, f)
	end
	return f
end

-- ═══════════ тайминги ═══════════

-- Свёрнуты в таблицу не для красоты: Luau не компилирует функцию, в которой
-- больше 200 локальных переменных, а тело скрипта — тоже функция. Поля таблицы
-- в этот счёт не входят (на этом уже споткнулась карта архипелага).
local T = {
	ENTER      = 0.45,   -- fade-in чёрного, хендофф
	TITLE_WAIT = 0.30,   -- задержка всплытия заголовка
	BLOCK_WAIT = 0.45,   -- задержка всплытия блока волн
	RISE       = 0.50,   -- длительность всплытия
	RISE_UP    = 24,     -- на сколько пикселей блок всплывает снизу
	MIN_HOLD   = 2.00,   -- минимум удержания после входа
	EXPECT_HOLD = 3.00,  -- holdSeconds по умолчанию: по нему считается ход лодки
	DOCK       = 0.30,   -- доводка лодки до острова, когда «done» пришёл рано
	EXIT       = 0.60,   -- fade-out
	FAILSAFE   = 12.00,  -- полный срок жизни экрана без «done»
	DOT        = 0.45,   -- шаг бегущих точек
	BOB        = 1.40,   -- покачивание лодки
	GLOW       = 2.40,   -- пульс свечения острова
}

-- ═══════════ геометрия ═══════════

--[[ ⚠️ БЛОК ВЫШЕ МАКЕТНЫХ 74, ПОТОМУ ЧТО ЛОДКА И ОСТРОВ КРУПНЕЕ.
     В макете это картинки: у ⛵ и у SVG острова по краям пустое поле, и на
     экране они читались меньше своих коробок. Здесь обе фигуры нарисованы
     фреймами во всю коробку, поэтому в исходных 32×26 и 64×44 они выглядели
     мелко — владелец так и сказал. Увеличены в полтора раза, а высота блока
     поднята ровно настолько, чтобы остров в 66 пикселей стоял на своём месте
     (низ в шести пикселях от кромки) и не вылезал за блок.
     Ширина блока и вся волновая механика не тронуты: волны и их период —
     единственное, что в макете задано не картинкой, и там числа точные. ]]
local BLOCK_W, BLOCK_H = 440, 96
local WAVE_H      = 26               -- окно волн внутри блока
local WAVE_BOTTOM = 4                -- отступ окна волн от низа блока
-- ход лодки: конец пути сдвинут на прибавку ширины лодки (было 416 при ширине
-- 32) — иначе увеличенный корпус уезжал бы носом за правую кромку блока
local BOAT_RUN    = 384
local BOAT_BASE   = BLOCK_H - 18     -- низ лодки по хендофу (bottom: 18px)
local FADE_BAND   = 28               -- размытие границы «пройдено / впереди»
-- CAP_H оставлен нулём, а не удалён: от него считаются позиции ниже, и ноль
-- дешевле, чем править каждую формулу. Подписи с именем острова больше нет —
-- в макете её не было, владелец попросил убрать.
local TITLE_H, CAP_H, GAP = 68, 0, 22
local STACK_H     = TITLE_H + CAP_H + GAP + BLOCK_H

-- ⚠️ ×1.5 к макету. Хелперы bar/slab кладут фигуры в долях коробки, поэтому
-- одного этого множителя хватает: вся геометрия иконок масштабируется сама.
local ISLE_BOX = Vector2.new(96, 66)
local BOAT_BOX = Vector2.new(64, 52)   -- ×2 к макету: владелец просил крупнее

--[[ ⚠️ ШРИФТ ОБЯЗАН ЗНАТЬ КИРИЛЛИЦУ.
     Стоял PermanentMarker — рукописный, но без русских букв: движок молча
     подставлял системный гротеск, и «Перемещаемся» выходило прямым и тонким,
     ничего общего с макетным Caveat. Caveat в Roblox нет вовсе; ближайшее с
     кириллицей и наклоном — Ubuntu Bold Italic: живой, с характерными
     хвостами, читается как рукописный курсив макета. ]]
local TITLE_FONT = Font.new("rbxasset://fonts/families/Ubuntu.json",
	Enum.FontWeight.Bold, Enum.FontStyle.Italic)
local TITLE_TEXT = "Перемещаемся"
local TITLE_SIZE = 54

--[[ ═══════════ КАРТИНКИ ═══════════
     Хендофф рисует лодку и острова картинками, и плашками их не повторить:
     волна из повёрнутых отрезков не обрезается окном (Roblox не клипует
     повёрнутых потомков) и превращается в цепочку, а парус и скала из
     прямоугольников читаются лесенкой. Лодку и острова залил владелец — ID
     ниже. Тайлы волн лежат в uploads/teleport/waveA.png и waveB.png: залей их
     и впиши ID — пока поле пустое, волны рисуются отрезками, как раньше.
     Картинка острова выбирается по имени модели (info.model) или по атрибуту
     MapIcon на модели: palm / outpost / ruins / danger / castle. ]]
local ASSETS = {
	BOAT   = "rbxassetid://99577060087788",
	WAVE_A = "",     -- uploads/teleport/waveA.png, 136×48 (период 34, высота 12 ×4)
	WAVE_B = "",     -- uploads/teleport/waveB.png, 152×56 (период 38, высота 14 ×4)
	ISLAND = {
		palm    = "rbxassetid://101183178515971",
		outpost = "rbxassetid://98554463703228",
		ruins   = "rbxassetid://118071010845243",
		danger  = "rbxassetid://88425015892709",
		castle  = "rbxassetid://127170088777369",
	},
}
-- имя модели → картинка; чего нет в списке — по типу ресурса (forest/iron/oil)
local ISLAND_ICON_BY_MODEL = {
	TropicIsland_SCENE = "palm", StartIsle_SCENE = "palm", SmallIsle_SCENE = "palm",
	OutpostIsle_SCENE  = "outpost",
	ShipIsle_SCENE     = "ruins", RockIsle_SCENE = "ruins",
	PirateIsland_SCENE = "danger",
	TerraceIsle_SCENE  = "castle",
}
local ISLAND_ICON_BY_KIND = { forest = "palm", iron = "ruins", oil = "outpost" }

--[[ ⚠️ ВОЛНА — СИНУСОИДА ИЗ КОРОТКИХ ПОВЁРНУТЫХ ФРЕЙМОВ.
     Хендофф просит две линии SVG-дуг (период 34/38, высота 9/10, штрих 2.4/2.6).
     Кривых в Roblox UI нет, поэтому каждая линия ломается на отрезки — тот же
     приём, что у пунктира маршрута в MapMenu (redrawRoute), только пул здесь
     строится ОДИН раз и потом не пересчитывается вовсе: волна не меняет форму,
     она только едет, а ехать дешевле сдвигом одного родителя.
     Семь отрезков на период — компромисс: погрешность хорды ≈ 0.7 px при штрихе
     2.4 px её не видно, а десять отрезков стоили бы ещё сотню инстансов.
     dim/hot — прозрачности (1 − opacity из хендофа: 0.22/0.28 впереди лодки,
     0.85/1.0 позади). ]]
--[[ ⚠️ АМПЛИТУДА — ПОЛОВИНА ВЫСОТЫ КОНТРОЛЬНОЙ ТОЧКИ, А НЕ ОНА САМА.
     Путь макета «M0 10 Q8.5 1 17 10» — квадратичная Безье: контрольная точка на
     y=1, но сама кривая поднимается только до y≈5.5, то есть гребень 4.5 px.
     Раньше стояли 9 и 10 — волна вдвое выше макетной, и при периоде 34 это уже
     не дуга, а острый зуб; на экране читалось как ряд «^^^». С 4.5/5 гребень
     широкий и покатый, как в макете. Отрезков на период 12 вместо 7: на пологой
     дуге излом хорды виден сильнее, чем на крутой. ]]
local WAVE_SAMPLES = 12
local WAVE = {
	{ period = 34, amp = 4.5, thick = 2.4, h = 12, rise = 11, cycle = 9, dim = 0.78, hot = 0.15, image = ASSETS.WAVE_A },
	{ period = 38, amp = 5,   thick = 2.6, h = 14, rise = 0,  cycle = 6, dim = 0.72, hot = 0.00, image = ASSETS.WAVE_B },
}

--[[ ⚠️ ЛОДКА НЕ ДОПЛЫВАЕТ ДО ОСТРОВА, ПОКА СЕРВЕР НЕ ОТВЕТИЛ.
     В прототипе прогресс линеен за (0.45 + holdSeconds), потому что там hold
     известен заранее. В игре он не известен вовсе: экран висит до «done».
     Линейный ход упёрся бы в единицу через 3.45 с, и дальше лодка стояла бы
     носом в остров — «всё загрузилось, но игру не отдают». Поэтому до ответа
     она идёт линейно до CRUISE, а потом ползёт по затухающей и единицы не
     достигает никогда; доводит её до берега уже приход «done». ]]
local CRUISE = 0.88

-- ═══════════ реестр гаснущих элементов ═══════════

local fadeGroups = { title = {}, block = {} }

-- Обходим уже построенное поддерево, а не регистрируем поштучно при создании:
-- иначе каждую из четырёхсот строк отрисовки пришлось бы дублировать вызовом.
-- Полностью прозрачные фреймы (контейнеры, окна отсечения) пропускаем — писать
-- им прозрачность бессмысленно, а в цикле перехода они стоили бы четверть кадра.
local function register(group, root)
	local list = fadeGroups[group]
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			list[#list + 1] = { d, "TextTransparency", d.TextTransparency }
		elseif d:IsA("ImageLabel") then
			list[#list + 1] = { d, "ImageTransparency", d.ImageTransparency }
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			list[#list + 1] = { d, "BackgroundTransparency", d.BackgroundTransparency }
		end
	end
end

-- k = 1 — элемент виден как задумано, k = 0 — растворён полностью.
local function applyFade(group, k)
	for _, e in ipairs(fadeGroups[group]) do
		local base = e[3]
		e[1][e[2]] = base + (1 - base) * (1 - k)
	end
end

-- ═══════════ каркас ═══════════

--[[ ⚠️ DisplayOrder 10000 — ЭТО НЕ «ПОБОЛЬШЕ НА ВСЯКИЙ СЛУЧАЙ».
     Экран обязан перекрыть ВСЁ, включая то, что открыто в момент нажатия: карта
     архипелага сидит на 95, телефонное меню на 200, предупреждения на 250,
     админка на 999–1000. Любое число из этого ряда однажды окажется ниже нового
     меню, и игрок увидит кусок интерфейса поверх шторки ровно в тот кадр, когда
     мир прыгает. 10000 уже занят шторкой загрузки места (ReplicatedFirst),
     и это ровно тот же смысловой слой — «мир не показывать»; пересечься они не
     могут, та живёт только до конца входа в игру. ]]
local gui = new("ScreenGui", {
	Name = "TeleportScreen", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
}, playerGui)

-- Active = true — шторка съедает клики. Без этого игрок вслепую тыкает по
-- кнопкам мира под ней и, например, успевает открыть строительство во время рейса.
local bgEdge = new("Frame", {
	Name = "Bg", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Active = true,
	BackgroundColor3 = BG_EDGE, BackgroundTransparency = 1, ZIndex = 1,
}, gui)

--[[ Радиального градиента у UIGradient нет — он только линейный. Центр собран
     эллипсом (UICorner 0.5) с мягкими боками; вертикально эллипс выходит за
     экран, поэтому сверху и снизу граница жёсткая. Цена подмены нулевая:
     #0D0F12 и #050607 различаются на 8 из 255, такой стык не виден ни на одном
     мониторе — а вот полностью убрать градиент нельзя, чёрный «в ноль» читается
     как вылет игры. ]]
local bgCore = new("Frame", {
	Name = "BgCore", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.95, 1.35), BorderSizePixel = 0,
	BackgroundColor3 = BG_CORE, BackgroundTransparency = 1, ZIndex = 2,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bgCore)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, bgCore)

-- Центральный блок: UIScale = ViewportSize.Y / 1080, но не мельче 0.7 — ниже
-- заголовок в 54 px превращается в нечитаемую кашу, и лучше пусть блок займёт
-- пол-экрана телефона, чем станет мелким.
local stack = new("Frame", {
	Name = "Stack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(BLOCK_W, STACK_H), BackgroundTransparency = 1, ZIndex = 3,
}, gui)
local stackScale = new("UIScale", { Scale = 1 }, stack)

-- ═══════════ заголовок ═══════════

local titleGroup = new("Frame", {
	Name = "Title", Size = UDim2.fromOffset(BLOCK_W, TITLE_H + CAP_H),
	Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 3,
}, stack)

--[[ ⚠️ ЗАГОЛОВОК ВЫРОВНЕН ПО ЛЕВОМУ КРАЮ, А ЦЕНТРИРОВАНО СЛОВО.
     Точки бегут 1→2→3, и у центрированной строки от этого дёргается всё слово:
     каждые 450 мс «Перемещаемся» прыгает влево-вправо на треть точки. Поэтому
     ширина слова меряется один раз, метка ставится так, чтобы по центру стояло
     именно оно, а точки прирастают вправо в пустоту.
     TextScaled по той же причине не годится: он подгонял бы кегль под длину
     строки, и заголовок пульсировал бы в размере на каждый тик. ]]
-- GetTextSize принимает только Enum.Font; для Font-объекта нужен
-- GetTextBoundsAsync с параметрами. Он может кинуть, пока шрифт не подгружен —
-- на этот случай запасная оценка по числу букв.
local function textWidth(s)
	local ok, v = pcall(function()
		local p = Instance.new("GetTextBoundsParams")
		p.Text, p.Font, p.Size, p.Width = s, TITLE_FONT, TITLE_SIZE, 4096
		return TextService:GetTextBoundsAsync(p)
	end)
	if ok and v and v.X > 0 then return v.X end
	return (utf8.len(s) or #s) * TITLE_SIZE * 0.5
end

local wordW = textWidth(TITLE_TEXT)
local fullW = textWidth(TITLE_TEXT .. "...")

local title = new("TextLabel", {
	Name = "Word", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(math.floor(BLOCK_W * 0.5 - wordW * 0.5), 0),
	Size = UDim2.fromOffset(math.ceil(fullW) + 12, TITLE_H),
	FontFace = TITLE_FONT, TextSize = TITLE_SIZE, TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	Text = TITLE_TEXT .. ".", ZIndex = 3,
}, titleGroup)

-- Подписи «к острову …» нет намеренно: в макете только «Перемещаемся…».
-- Поле name в «start» сервер по-прежнему шлёт — его читают другие клиенты
-- (например, тост на карте), здесь оно просто не нужно.

register("title", titleGroup)

-- ═══════════ блок «волны + лодка + остров» ═══════════

local block = new("Frame", {
	Name = "Voyage", Size = UDim2.fromOffset(BLOCK_W, BLOCK_H),
	Position = UDim2.fromOffset(0, TITLE_H + CAP_H + GAP),
	BackgroundTransparency = 1, ZIndex = 3,
}, stack)

local waveWindow = new("Frame", {
	Name = "Waves", Size = UDim2.fromOffset(BLOCK_W, WAVE_H),
	Position = UDim2.fromOffset(0, BLOCK_H - WAVE_H - WAVE_BOTTOM),
	BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1,
}, block)

--[[ ⚠️ ЯРКАЯ ЧАСТЬ ВОЛН — ВТОРОЙ КОМПЛЕКТ ОТРЕЗКОВ ПОД ОТСЕЧЕНИЕМ, А НЕ
     ПЕРЕКРАШИВАНИЕ ПЕРВОГО.
     Прозрачность у каждого отрезка своя, и «сделать яркими те, что позади
     лодки» означало бы писать её всем 190 фреймам каждый кадр — 11 тысяч
     присваиваний в секунду ровно тогда, когда клиент занят стримингом мира.
     Второй комплект стоит памяти (ещё 190 фреймов), но за кадр меняется ровно
     одно свойство: ширина этого контейнера. ]]
local brightClip = new("Frame", {
	Name = "Travelled", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 1,
	ClipsDescendants = true, ZIndex = 1,
}, waveWindow)

-- Свечение пройденного следа. Хендофф просит запечённый в PNG blur 6–12 px;
-- размытия в Roblox UI нет вовсе, поэтому вместо ореола у каждой волны —
-- одна общая полоса, мягкая по вертикали за счёт градиента. Читается как
-- подсвеченный след за кормой, стоит один фрейм вместо второго слоя волн.
local glow = new("Frame", {
	Name = "Wake", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
	BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, ZIndex = 1,
}, brightClip)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, glow)

--[[ ⚠️ ГРАНИЦА «ПРОЙДЕНО / ВПЕРЕДИ» РАЗМЫТА ЗАСВЕТКОЙ ФОНОМ, А НЕ МАСКОЙ.
     В прототипе край яркого слоя съеден mask-image на 28 px. Масок в Roblox UI
     нет: UIGradient красит только тот объект, на котором висит, на детей он не
     распространяется. Поэтому поверх яркого слоя лежит полоса цвета фона с
     градиентом «прозрачно → плотно» — она гасит яркие волны ровно на тех же
     28 px. Тусклый слой нарочно лежит ВЫШЕ полосы (ZIndex 3 против 2), иначе
     полоса выедала бы и его, и впереди лодки появлялась бы чёрная проплешина. ]]
local veil = new("Frame", {
	Name = "Blend", Size = UDim2.fromScale(FADE_BAND / BLOCK_W, 1),
	BackgroundColor3 = VEIL_C, BorderSizePixel = 0, ZIndex = 2,
}, waveWindow)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, veil)

local faintHolder = new("Frame", {
	Name = "Ahead", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3,
}, waveWindow)

--[[ ⚠️ ПОЛОСА ШИРЕ ОКНА РОВНО НА ОДИН ПЕРИОД, И ЭТО ДАЁТ БЕСШОВНЫЙ ЦИКЛ.
     Синусоида повторяется каждые period пикселей, поэтому сдвиг ровно на период
     возвращает картинку в исходное положение — шва нет по построению. В
     прототипе полоса вдвое шире окна и едет на 50 %, и там стык на стыке цикла
     заметен, потому что 440 не делится на 34 нацело. Скорость при этом взята
     оттуда же: 440 px за cycle секунд, чтобы движение выглядело как в макете.
     Вертикальное отсечение (ClipsDescendants у line) повторяет прототип: нижняя
     половина синуса уходит под край окна, и на экране остаются гребни. ]]
local function buildLine(parent, cfg, alpha)
	local span = BLOCK_W + cfg.period + 8
	local line = new("Frame", {
		Name = "Line", BackgroundTransparency = 1, ClipsDescendants = true,
		Size = UDim2.fromOffset(span, cfg.h),
		Position = UDim2.fromOffset(0, WAVE_H - cfg.rise - cfg.h),
		ZIndex = 1,
	}, parent)
	-- Картинка волны: один период тайлом на всю полосу. Обрезка снизу уже
	-- запечена в PNG, поэтому никакого клипа повёрнутых фреймов не нужно.
	if cfg.image and cfg.image ~= "" then
		return new("ImageLabel", {
			Name = "Strip", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Image = cfg.image, ImageColor3 = WHITE, ImageTransparency = alpha,
			ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(cfg.period, cfg.h),
			ZIndex = 1,
		}, line)
	end
	local strip = new("Frame", {
		Name = "Strip", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
	}, line)

	-- имя нарочно не step: ниже так называется кадровый цикл, и совпадение имён
	-- в файле такого размера читается как ошибка
	local sampleStep = cfg.period / WAVE_SAMPLES
	local base = cfg.h - 2                      -- базовая линия, как y=10 в SVG 34×12
	local count = math.ceil(span / sampleStep)
	local px, py = 0, base
	for i = 1, count do
		local x = i * sampleStep
		local y = base - cfg.amp * math.sin(x * 2 * math.pi / cfg.period)
		local dx, dy = x - px, y - py
		local len = math.sqrt(dx * dx + dy * dy)
		-- Отрезки нарочно длиннее хорды на 0.7 толщины: стык перекрывается, и
		-- скруглять концы (UICorner на каждый) не нужно — это сэкономило ещё
		-- 380 инстансов, а настоящие концы полилинии всё равно срезаны окном.
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((px + x) * 0.5 / span, (py + y) * 0.5 / cfg.h),
			Size = UDim2.fromScale((len + cfg.thick * 0.7) / span, cfg.thick / cfg.h),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = WHITE, BackgroundTransparency = alpha,
			BorderSizePixel = 0, ZIndex = 1,
		}, strip)
		px, py = x, y
	end
	return strip
end

local strips = {}
for _, cfg in ipairs(WAVE) do
	strips[#strips + 1] = {
		faint  = buildLine(faintHolder, cfg, cfg.dim),
		bright = buildLine(brightClip, cfg, cfg.hot),
		period = cfg.period,
		span   = BLOCK_W + cfg.period + 8,
		speed  = BLOCK_W / cfg.cycle,
	}
end

--[[ ⚠️ ЛОДКА — ГЕОМЕТРИЯ ВМЕСТО PNG (и вместо эмодзи ⛵ из прототипа).
     Эмодзи в Roblox рисуется цветным системным шрифтом, обесцветить его нельзя:
     в макете это делает CSS-фильтр grayscale+brightness, которого здесь нет.
     Поэтому корпус, палуба, мачта, а парус — лесенкой из пяти плашек: залитого
     треугольника в UI не существует. Со стороны это читается как силуэт лодки;
     потеряны скруглённый нос и глоу. ]]
local boat = new("Frame", {
	Name = "Boat", AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.fromOffset(BOAT_BOX.X, BOAT_BOX.Y),
	BackgroundTransparency = 1, ZIndex = 4,
}, block)
if ASSETS.BOAT ~= "" then
	new("ImageLabel", {
		Name = "Pic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = ASSETS.BOAT, ScaleType = Enum.ScaleType.Fit, ZIndex = 4,
	}, boat)
else
slab(boat, BOAT_BOX, 16, 22, 21, 6, 0.4)        -- корпус
slab(boat, BOAT_BOX, 16, 18.5, 26, 3, 0.4)      -- палуба
bar(boat, BOAT_BOX, 16, 18, 16, 3, 2)           -- мачта
--[[ Парус — треугольник из четырнадцати тонких плашек вместо пяти толстых.
     Пять ступеней по 3 px читались как лесенка, а не как парус; при шаге в
     один пиксель ступени сливаются в ровную гипотенузу. Плюс девять фреймов —
     на общем счёте в четыреста это ничто. ]]
do
	local top, bottom, mastX, foot = 4.5, 17.5, 16, 14
	local steps = 14
	local stepH = (bottom - top) / steps
	for i = 1, steps do
		local w = foot * (i / steps)
		slab(boat, BOAT_BOX, mastX + w * 0.5, top + (i - 0.5) * stepH, w, stepH + 0.3, 0)
	end
end
end

-- Реестр собирается ДО постройки иконок острова: у острова своя пульсация
-- прозрачности, и попади он в общий список — вход и пульс дрались бы за одно
-- свойство, а иконка мигала бы рывками.
register("block", block)

-- ═══════════ иконка острова ═══════════

--[[ ⚠️ ТРИ СИЛУЭТА ВМЕСТО ШЕСТИ ИЛЛЮСТРАЦИЙ ХЕНДОФА — ЭТО СОЗНАТЕЛЬНОЕ УРЕЗАНИЕ.
     Хендофф рисует шесть островов (пальма, вулкан, маяк, джунгли, военная и
     пиратская базы) и выбирает их по id. Сервер же шлёт kind из трёх значений —
     forest / iron / oil, и связи «id → какая из шести картинок» в протоколе нет
     вовсе. Придумывать её на клиенте нельзя: разъедется с сервером на первом же
     новом острове. Поэтому три силуэта по типу ресурса: пальма, скала, вышка.
     Внутри каждого — грубее, чем в макете: вырезов (окна, кратер, череп) нет,
     они требуют цвета фона поверх белого, а фон под иконкой — градиент, и
     «вырез» выдал бы себя пятном. ]]
local isleHolder = new("Frame", {
	Name = "Island", AnchorPoint = Vector2.new(0, 1),
	-- right: −66px, bottom: 6px из хендофа — остров стоит ЗА концом волн
	-- вылет за конец волн тоже ×1.5 (было 66): иначе увеличенный остров залез бы
	-- на волны вместо того, чтобы стоять за ними
	Position = UDim2.fromScale((BLOCK_W + 99 - ISLE_BOX.X) / BLOCK_W, (BLOCK_H - 6) / BLOCK_H),
	Size = UDim2.fromOffset(ISLE_BOX.X, ISLE_BOX.Y),
	BackgroundTransparency = 1, ZIndex = 3,
}, block)

-- Картинка острова (см. ASSETS.ISLAND). Силуэты из плашек ниже остаются
-- запасным вариантом на случай, если для острова картинки нет.
local islePic = new("ImageLabel", {
	Name = "Pic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	Image = "", ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = 3,
}, isleHolder)

local isleSets = {}

local function makeIcon(name, draw)
	local root = new("Frame", {
		Name = name, Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Visible = false, ZIndex = 2,
	}, isleHolder)
	draw(root)
	local parts = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Frame") then parts[#parts + 1] = d end
	end
	isleSets[name] = { root = root, parts = parts }
end

makeIcon("forest", function(root)
	slab(root, ISLE_BOX, 32, 36, 52, 12, 0.5)     -- отмель: полукруг заменён капсулой
	bar(root, ISLE_BOX, 30, 38, 31, 26, 3)        -- ствол: кривая — двумя коленами
	bar(root, ISLE_BOX, 31, 26, 33, 13, 3)
	bar(root, ISLE_BOX, 33, 12, 18, 16, 3.4)      -- четыре листа
	bar(root, ISLE_BOX, 33, 12, 48, 14, 3.4)
	bar(root, ISLE_BOX, 33, 12, 21, 5, 3.4)
	bar(root, ISLE_BOX, 33, 12, 45, 4, 3.4)
	slab(root, ISLE_BOX, 37, 15, 3.6, 3.6, 0.5)   -- кокосы
	slab(root, ISLE_BOX, 33, 17.5, 3.6, 3.6, 0.5)
end)

makeIcon("iron", function(root)
	slab(root, ISLE_BOX, 32, 36, 52, 12, 0.5)
	--[[ Гора — как вулкан в макете: ровный конус с плоской вершиной и дымком.
	     Раньше пик собирался из шести ступеней по 5 px и читался как лесенка;
	     теперь ступени по 1.3 px, и склон выходит прямой. Кратер и лавовый язык
	     макета опущены: это вырезы цветом фона, а под иконкой градиент. ]]
	do
		local apexY, baseY, cx = 12, 34, 30
		local topW, baseW = 10, 40
		local steps = 17
		local stepH = (baseY - apexY) / steps
		for i = 1, steps do
			local w = topW + (baseW - topW) * (i / steps)
			slab(root, ISLE_BOX, cx, apexY + (i - 0.5) * stepH, w, stepH + 0.3, 0)
		end
	end
	slab(root, ISLE_BOX, 31, 8, 5.5, 5.5, 0.5)    -- дым: три облачка по макету
	slab(root, ISLE_BOX, 36, 4.5, 4.4, 4.4, 0.5)
	slab(root, ISLE_BOX, 40, 2, 3, 3, 0.5)
end)

makeIcon("oil", function(root)
	slab(root, ISLE_BOX, 32, 36, 52, 12, 0.5)
	bar(root, ISLE_BOX, 20, 34, 28, 8, 3)         -- ноги вышки
	bar(root, ISLE_BOX, 44, 34, 36, 8, 3)
	bar(root, ISLE_BOX, 22.6, 26, 41.4, 26, 2.2)  -- пояса
	bar(root, ISLE_BOX, 25.4, 17, 38.6, 17, 2.2)
	bar(root, ISLE_BOX, 22.6, 26, 38.6, 17, 1.8)  -- раскосы
	bar(root, ISLE_BOX, 41.4, 26, 25.4, 17, 1.8)
	slab(root, ISLE_BOX, 32, 7, 13, 3.4, 0.4)     -- площадка
	bar(root, ISLE_BOX, 32, 6, 32, 2, 2.4)        -- шпиль
	slab(root, ISLE_BOX, 11, 32, 9, 8, 0.25)      -- бочка у подножия
end)

-- ═══════════ состояние ═══════════

local conn      = nil    -- подписка на RenderStepped живёт только пока экран виден
local t0        = 0      -- момент «start»
local exitAt    = nil    -- когда начинать выход; nil = ждём сервер
local outAt     = nil    -- когда выход начался
local dockFrom  = 0      -- прогресс лодки на момент прихода «done»
local dockStart = 0
local progress  = 0
local isleParts = nil
local lastDots, lastTitleA, lastBlockA, lastScale = -1, -1, -1, -1

-- Картинка: явный MapIcon с модели → имя модели → тип ресурса. Нет картинки
-- (ID пустой или ключ неизвестен) — показываем силуэт из плашек по типу.
local function setIsland(info)
	local kind  = typeof(info) == "table" and info.kind or nil
	local model = typeof(info) == "table" and info.model or nil
	local icon  = typeof(info) == "table" and info.icon or nil
	local key = (type(icon) == "string" and ASSETS.ISLAND[icon] and icon)
		or (type(model) == "string" and ISLAND_ICON_BY_MODEL[model])
		or ISLAND_ICON_BY_KIND[kind]
		or "palm"
	local image = ASSETS.ISLAND[key] or ""

	if image ~= "" then
		islePic.Image = image
		islePic.Visible = true
		for _, s in pairs(isleSets) do s.root.Visible = false end
		isleParts = nil
		return
	end
	islePic.Visible = false
	local set = isleSets[kind] or isleSets.forest
	for _, s in pairs(isleSets) do s.root.Visible = (s == set) end
	isleParts = set.parts
end

local function hide()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	gui.Enabled = false
	exitAt, outAt = nil, nil
end

--[[ ⚠️ ОДИН ЦИКЛ НА ВЕСЬ ЭКРАН, И В НЁМ НЕТ НИ ОДНОГО Instance.new.
     Всё построено заранее; кадр только двигает и гасит. Твинов тоже нет
     намеренно: их пришлось бы отменять при досрочном «done», а ход лодки
     вообще меняет цель на лету — ручной счётчик от os.clock проще и не
     оставляет висящих Tween'ов, если экран убрали в середине анимации. ]]
local function step()
	local now = os.clock()
	local el = now - t0

	-- 1. решение о выходе
	if not outAt then
		if exitAt and now >= exitAt then
			outAt = now
		elseif not exitAt and el >= T.FAILSAFE - T.EXIT then
			--[[ «done» не пришёл вовсе — сервер упал или ремоут не долетел.
			     Гасим так, чтобы к FAILSAFE экрана УЖЕ не было: обещание
			     «12 секунд» — про то, когда игрок увидит мир, а не про то,
			     когда начнётся затухание.
			     Условие «not exitAt» обязательно: без него честный «done»,
			     пришедший на 11.3 с, затирался бы аварийным сроком, и лодка
			     прыгала бы к острову вместо доводки. ]]
			exitAt, dockFrom, dockStart = now + T.EXIT, progress, now
			outAt = now
		end
	end

	-- 2. ход лодки
	if exitAt then
		local span = math.max(exitAt - dockStart, 0.001)
		progress = dockFrom + (1 - dockFrom) * math.clamp((now - dockStart) / span, 0, 1)
	else
		local ramp = T.ENTER + T.EXPECT_HOLD
		if el <= ramp then
			progress = CRUISE * (el / ramp)
		else
			-- половинное приближение к берегу: лодка всегда чуть-чуть движется,
			-- поэтому долгое ожидание сервера не выглядит зависанием
			progress = 1 - (1 - CRUISE) * 0.5 ^ ((el - ramp) / 2.5)
		end
	end

	-- 3. шторка. Ноль прозрачности достигается на 0.45 с — за 0.95 с до того,
	-- как сервер дёрнет плот; этот зазор и есть вся защита от рывка на экране.
	local curtain = math.clamp(el / T.ENTER, 0, 1)
	if outAt then
		curtain = 1 - math.clamp((now - outAt) / T.EXIT, 0, 1)
	end
	bgEdge.BackgroundTransparency = 1 - curtain
	bgCore.BackgroundTransparency = 1 - curtain

	-- 4. всплытие заголовка и блока (ease-out, как в хендофе)
	local outK = outAt and (1 - math.clamp((now - outAt) / T.EXIT, 0, 1)) or 1
	local rawT = math.clamp((el - T.TITLE_WAIT) / T.RISE, 0, 1)
	local rawB = math.clamp((el - T.BLOCK_WAIT) / T.RISE, 0, 1)
	local easeT = 1 - (1 - rawT) * (1 - rawT)
	local easeB = 1 - (1 - rawB) * (1 - rawB)
	local alphaT = easeT * outK
	local alphaB = easeB * outK

	if math.abs(alphaT - lastTitleA) > 0.002 then
		lastTitleA = alphaT
		applyFade("title", alphaT)
		titleGroup.Position = UDim2.fromOffset(0, math.floor(T.RISE_UP * (1 - easeT) + 0.5))
	end
	if math.abs(alphaB - lastBlockA) > 0.002 then
		lastBlockA = alphaB
		applyFade("block", alphaB)
		block.Position = UDim2.fromOffset(0,
			TITLE_H + CAP_H + GAP + math.floor(T.RISE_UP * (1 - easeB) + 0.5))
	end

	-- 5. бегущие точки
	local dots = 1 + math.floor(el / T.DOT) % 3
	if dots ~= lastDots then
		lastDots = dots
		title.Text = TITLE_TEXT .. string.rep(".", dots)
	end

	-- 6. волны: сдвиг ровно одного родителя на линию
	for _, s in ipairs(strips) do
		local off = -((el * s.speed) % s.period) / s.span
		s.faint.Position = UDim2.fromScale(off, 0)
		s.bright.Position = UDim2.fromScale(off, 0)
	end
	brightClip.Size = UDim2.fromScale(progress, 1)
	veil.Position = UDim2.fromScale((progress * BLOCK_W - FADE_BAND) / BLOCK_W, 0)

	-- 7. лодка: качка ±3° и ±4 px за 1.4 с. Крен и подъём разведены по фазе
	-- (sin/cos), иначе лодка ныряет и кренится одновременно — выглядит как рывок.
	local ph = el * 2 * math.pi / T.BOB
	boat.Rotation = math.sin(ph) * 3
	boat.Position = UDim2.fromScale(
		(10 + progress * BOAT_RUN) / BLOCK_W,
		(BOAT_BASE - math.cos(ph) * 4) / BLOCK_H)

	-- 8. пульс острова 0.45↔1 за 2.4 с. Множится на всплытие блока: иначе на
	-- входе иконка проявилась бы отдельно от волн, поверх ещё пустого места.
	local pulse = (0.45 + 0.55 * (0.5 - 0.5 * math.cos(el * 2 * math.pi / T.GLOW))) * alphaB
	if islePic.Visible then
		islePic.ImageTransparency = 1 - pulse
	elseif isleParts then
		local tr = 1 - pulse
		for _, f in ipairs(isleParts) do f.BackgroundTransparency = tr end
	end

	-- 9. подгонка под экран
	local cam = Workspace.CurrentCamera
	if cam then
		local k = math.max(cam.ViewportSize.Y / 1080, 0.7)
		if math.abs(k - lastScale) > 0.001 then
			lastScale = k
			stackScale.Scale = k
		end
	end

	if outAt and (now - outAt) >= T.EXIT then hide() end
end

local function show(info)
	local now = os.clock()
	t0, exitAt, outAt = now, nil, nil
	dockFrom, dockStart, progress = 0, now, 0
	lastDots, lastTitleA, lastBlockA = -1, -1, -1

	setIsland(info)

	-- Первый кадр считаем ДО включения экрана: иначе один кадр видно прошлое
	-- состояние — доплывшую лодку и полностью проявленный заголовок.
	step()
	gui.Enabled = true
	if not conn then conn = RunService.RenderStepped:Connect(step) end
end

-- exitAt в условии — защита от повторного «done» (сервер шлёт его и по таймеру,
-- и по факту прибытия): второй вызов отодвигал бы выход ещё на DOCK, и экран
-- жил бы дольше, чем нужно, на каждом дубле.
local function finish()
	if not conn or outAt or exitAt then return end
	local now = os.clock()
	dockFrom, dockStart = progress, now
	-- Нижняя граница удержания и доводка лодки: что позже, то и берём. Без DOCK
	-- лодка телепортировалась бы к острову в последний кадр перед затуханием.
	exitAt = math.max(t0 + T.ENTER + T.MIN_HOLD, now + T.DOCK)
end

-- ═══════════ связь с сервером ═══════════

-- WaitForChild уже после постройки интерфейса: если ремоут почему-то не
-- появится, экран всё равно собран и ничем не мешает, а не «скрипт застрял на
-- первой строке». Собираем сразу при входе в игру осознанно — четыреста
-- фреймов в момент нажатия «Переместиться» дали бы фриз ровно там, где экран
-- обязан появиться мгновенно.
local remote = ReplicatedStorage:WaitForChild("MapTeleport")

remote.OnClientEvent:Connect(function(action, info)
	if action == "start" then
		show(info)
	elseif action == "done" then
		finish()
	end
end)
