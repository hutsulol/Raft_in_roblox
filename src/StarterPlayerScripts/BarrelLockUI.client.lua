local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ВЗЛОМ БОЧКИ — циферблат по хендоффу (README.md + «Взлом бочки.dc.html»).

	Стрелка крутится без остановки; игрок жмёт, когда она в зелёной зоне. Три
	попадания подряд — бочка открыта, промах сбрасывает серию.

	⚠️ ПРАВ ЗДЕСЬ НЕТ: ЭТО ТОЛЬКО ПОКАЗ.
	Клиент шлёт серверу УГОЛ СТРЕЛКИ в момент нажатия, а попал он или нет —
	решает сервер (BarrelSystem, inSector). Здесь мы рисуем ответ, а не считаем
	его: иначе выиграть можно было бы правкой числа на своей машине.
	Протокол не менялся ни на байт — поменялась только картинка:
	    сервер → "begin" {barrel, sectorStart, sectorSize, speed, round, rounds}
	              "hit" (сколько сбито) · "miss" (сколько попыток осталось)
	              "sunk" · "opened" · "denied" (текст) · "cancel"
	    клиент → "stop" (угол) · "cancel"

	⚠️ ЦИФЕРБЛАТ ВИСИТ НАД БОЧКОЙ, А НЕ ПО ЦЕНТРУ ЭКРАНА.
	Экранный вариант я пробовал — стало непонятно, ЧТО именно вскрываешь: бочек
	рядом может быть несколько, и замок должен быть привязан к своей. Поэтому
	BillboardGui с Adornee на саму бочку: панель качается вместе с ней на волне.

	⚠️ РАЗМЕР ЗАДАЁМ В OFFSET, А НЕ В SCALE — ЭТО НЕ ПРИДИРКА.
	У BillboardGui доля Scale меряется в СТУДАХ (мельчает с расстоянием), а
	Offset — в ПИКСЕЛЯХ и на экране остаётся того же размера. В циферблат надо
	попадать мышью и пальцем, поэтому он не имеет права уезжать в точку.

	⚠️ ДУГИ В ROBLOX GUI НЕТ.
	Зелёную зону нельзя нарисовать одной фигурой. ТЗ само предлагает выход:
	шкала собирается из сорока повёрнутых сегментов, и «зона» — это те из них,
	что попали в её угол. Один механизм даёт и сегментацию, и зону, и подсветку.

	⚠️ ПОВОРОТ ВОКРУГ ЦЕНТРА — ЧЕРЕЗ ОБЁРТКУ.
	Rotation крутит объект вокруг его СОБСТВЕННОЙ точки привязки. Чтобы обвести
	что-то вокруг центра циферблата, сама деталь кладётся к верхнему краю
	прозрачной обёртки размером с циферблат, а крутится обёртка.
]]

local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lockEvent = ReplicatedStorage:WaitForChild("BarrelLock", 30)
if not lockEvent then
	warn("[Бочка] нет ремоута BarrelLock — взлом не откроется")
	return
end

-- ─── Палитра (Design Tokens из ТЗ) ───
local DARK      = Color3.fromHex("14261A")
local FACE      = Color3.fromHex("2B3550")
local FACE_WIN  = Color3.fromHex("1F4D2A")
local FACE_MISS = Color3.fromHex("5E2020")
local DISC      = Color3.fromHex("22304F")
local TRACK     = Color3.fromHex("39466B")
local ZONE      = Color3.fromHex("52C832")
local ZONE_HOT  = Color3.fromHex("8AFF5A")
local ZONE_DIM  = Color3.fromHex("3A8A28")
local GOLD_A    = Color3.fromHex("FFE14D")
local GOLD_B    = Color3.fromHex("F0A820")
local GOLD_LINE = Color3.fromHex("A86A10")
local GOLD_SH   = Color3.fromHex("7D4E0A")
local HUB_A     = Color3.fromHex("FFE9A8")
local HUB_B     = Color3.fromHex("D1881A")
local STICK_HIT_A, STICK_HIT_B = Color3.fromHex("7AE04D"), Color3.fromHex("48B428")
local STICK_MISS_A, STICK_MISS_B = Color3.fromHex("F06A6A"), Color3.fromHex("C43434")
local GOLD_TEXT = Color3.fromHex("FFE14D")

-- ─── Геометрия. Макет описан в системе 200×200, циферблат на экране 250. ───
local DIAL   = 220              -- размер ИЗ МАКЕТА; на экране см. refitDial()
local DIAL_FRACTION = 0.30      -- какую долю высоты окна занимает циферблат
local K      = DIAL / 200          -- множитель из макета в пиксели
local FACE_D = 184 * K             -- лицо: r=92
local RING_R = 78 * K              -- радиус кольца шкалы
local RING_T = 16 * K              -- толщина кольца
local DISC_D = 124 * K             -- внутренний диск: r=62
local HUB_D  = 44 * K
local NEEDLE_W, NEEDLE_H = 14 * K, 86 * K
local TICKS  = 40                  -- сегментов в шкале
local RESULT_HOLD = 0.7            -- сколько висит стикер попадания/промаха
local WIN_HOLD    = 1.6

-- Тексты стикеров — из ТЗ, случайный на каждый показ.
local HIT_WORDS  = { "ЕСТЬ!", "ТОЧНО!", "ЩЁЛК!", "В ЯБЛОЧКО!", "ЧЁТКО!" }
local MISS_WORDS = { "МИМО!", "ПРОМАХ!", "УПС!", "НЕ ТУДА!", "СОРВАЛОСЬ!" }

-- Звук: попадание — сухой щелчок штифта, промах — скрежет сорвавшейся отмычки.
-- Встроенные в движок: не грузятся по сети и не зависят от прав на ассет.
local SND_HIT_ID  = "rbxasset://sounds/switch3.wav"
local SND_MISS_ID = "rbxasset://sounds/metal.ogg"
local HIT_PITCH   = { 1.1, 1.3, 1.55 }

local function makeSound(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	return s
end
local sndHit  = makeSound(SND_HIT_ID, 0.6, 1.1)
local sndMiss = makeSound(SND_MISS_ID, 0.55, 0.62)
-- ⚠️ ЩЕЛЧОК НАЖАТИЯ — ТИШЕ И ВЫШЕ, ЧЕМ ЩЕЛЧОК ПОПАДАНИЯ.
-- Это два разных сообщения: «жму» и «попал». Дай им один звук — и промах будет
-- звучать как удача ровно до того момента, пока не прилетит скрежет.
local sndPress = makeSound("rbxasset://sounds/switch.wav", 0.3, 1.7)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function circle(inst) new("UICorner", { CornerRadius = UDim.new(1, 0) }, inst) end
local function outline(inst, thickness, color)
	return new("UIStroke", { Thickness = thickness, Color = color or DARK }, inst)
end

-- ─── Панель над бочкой ───
-- ⚠️ Adornee выставляется в "begin" — на ту бочку, которую вскрываем сейчас.
-- ⚠️ LightInfluence = 0: ночью и в тумане замок должен читаться так же ясно.
-- ⚠️ ExtentsOffsetWorldSpace, а не StudsOffset: подъём считается от ВЕРХА бочки
--    в мировых осях, поэтому панель не ныряет в неё, когда бочку кренит волной.
local board = new("BillboardGui", {
	Name = "BarrelLockGui",
	Size = UDim2.fromOffset(DIAL + 60, DIAL + 110),
	AlwaysOnTop = true,
	LightInfluence = 0,
	ExtentsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
	Active = true,
	Enabled = false,
	--[[ ⚠️ ПЕРЕЖИВАЕТ РЕСПАВН. По умолчанию ResetOnSpawn = true, и Roblox
	     УНИЧТОЖАЛ эту панель при смерти персонажа. Скрипт при этом жил дальше
	     и работал с мёртвым объектом: сервер слал «begin», мы ставили
	     Enabled = true в никуда, игрок ничего не видел, а следующий его клик
	     уходил как «stop» с наугад взятым углом — «мимо». Отсюда жалоба
	     «после смерти бочки не открываются, второй тык пишет мимо». ]]
	ResetOnSpawn = false,
}, playerGui)

local column = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, board)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10),
}, column)
--[[ ⚠️ РАЗМЕР СЧИТАЕМ ОТ ОКНА, А НЕ ДЕРЖИМ ЧИСЛОМ.
     Циферблат в 250 пикселей на большом мониторе смотрится нормально, а в
     оконном режиме занимает половину экрана и закрывает собой плот. Поэтому из
     макета берём ПРОПОРЦИИ, а итоговый размер — долю высоты окна.

     ⚠️ ПОТОЛОК ПОДНЯТ ВЫШЕ ЕДИНИЦЫ, И ЭТО НЕ ПРОТИВОРЕЧИТ ПРЕЖНЕЙ ЗАМЕТКЕ.
     Раньше здесь стояло «крупнее макета рисунок замылится» — так было бы, будь
     он картинкой. Циферблат нарисован фреймами и обводками, то есть тянется без
     потери резкости; замыливаться нечему. На обычном окне доля высоты и так
     упиралась в потолок, поэтому просто поднять DIAL_FRACTION было бы
     бесполезно — растёт именно потолок. ]]
--[[ ⚠️ НА ТЕЛЕФОНЕ ЦИФЕРБЛАТ УЖИМАЛСЯ ДВАЖДЫ, И ЭТО БЫЛО ПРОСТО ОШИБКОЙ.
     Доля высоты окна — это УЖЕ адаптация под маленький экран: на телефоне она
     сама даёт 0.54 вместо единицы. Сверху на неё домножался iconFactor (0.61),
     придуманный для иконок левого столбика, и итог выходил 0.33 — циферблат в
     72 пикселя, по которому надо попасть пальцем в узкий зелёный сектор.
     Здесь не иконка, а вся мини-игра: по ней целятся, её закрывает палец, и
     цена промаха — утонувшая бочка. Ей нужен размер, а не экономия места.
     Поэтому на телефоне своя, БОЛЬШАЯ доля высоты и никакого второго
     множителя. На компьютере не меняется ничего. ]]
local Hud = require(ReplicatedStorage:WaitForChild("HudScale"))
local DIAL_FRACTION_PHONE = 0.36   -- ≈ вдвое крупнее прежнего на телефоне
local fit = Instance.new("UIScale")
fit.Parent = column
local function refitDial()
	local cam = workspace.CurrentCamera
	local h = (cam and cam.ViewportSize.Y > 0) and cam.ViewportSize.Y or 720
	local frac = Hud.isPhone() and DIAL_FRACTION_PHONE or DIAL_FRACTION
	fit.Scale = math.clamp(h * frac / DIAL, 0.4, 1.18)
end
local camConn
local function watchCamera()
	if camConn then camConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refitDial)
	end
	refitDial()
end
-- камера пересоздаётся при респавне — иначе после смерти подгон отвалится
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

-- 1. счётчик этапа
local roundLbl = new("TextLabel", {
	LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = GOLD_TEXT, Text = "1 / 3",
}, column)
outline(roundLbl, 3)

-- 2. циферблат
local dial = new("Frame", {
	LayoutOrder = 2, Size = UDim2.fromOffset(DIAL, DIAL), BackgroundTransparency = 1,
}, column)

local faceShadow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6),
	Size = UDim2.fromOffset(FACE_D, FACE_D), BackgroundColor3 = DARK,
	BorderSizePixel = 0, ZIndex = 1,
}, dial)
circle(faceShadow)

local face = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(FACE_D, FACE_D), BackgroundColor3 = FACE,
	BorderSizePixel = 0, ZIndex = 2,
}, dial)
circle(face)
local faceStroke = outline(face, 7)

-- шкала: сорок сегментов по кругу. Каждый лежит в своей обёртке размером с
-- циферблат — крутим обёртку, сегмент обходит центр (см. шапку файла).
local ticks = {}
for i = 1, TICKS do
	local wrap = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DIAL, DIAL), BackgroundTransparency = 1,
		Rotation = (i - 1) * (360 / TICKS), ZIndex = 3,
	}, dial)
	local seg = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, -RING_R - RING_T / 2),
		Size = UDim2.fromOffset(7, RING_T), BackgroundColor3 = TRACK,
		BorderSizePixel = 0, ZIndex = 3,
	}, wrap)
	new("UICorner", { CornerRadius = UDim.new(0, 2) }, seg)
	ticks[i] = seg
end

local disc = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(DISC_D, DISC_D), BackgroundColor3 = DISC,
	BorderSizePixel = 0, ZIndex = 4,
}, dial)
circle(disc)
outline(disc, 5)

-- блик на диске: полупрозрачный овал слева сверху
local gloss = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.32),
	Size = UDim2.fromOffset(DISC_D * 0.5, DISC_D * 0.3),
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9,
	BorderSizePixel = 0, ZIndex = 5,
}, disc)
circle(gloss)

-- стрелка: та же обёртка-вертушка
local needleWrap = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(DIAL, DIAL), BackgroundTransparency = 1, ZIndex = 6,
}, dial)
local needle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(NEEDLE_W, NEEDLE_H), BackgroundColor3 = GOLD_A,
	BorderSizePixel = 0, ZIndex = 6,
}, needleWrap)
circle(needle)
outline(needle, 3, GOLD_LINE)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(GOLD_A, GOLD_B) }, needle)

-- хаб по центру
local hubShadow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3),
	Size = UDim2.fromOffset(HUB_D, HUB_D), BackgroundColor3 = GOLD_SH,
	BorderSizePixel = 0, ZIndex = 7,
}, dial)
circle(hubShadow)
local hub = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(HUB_D, HUB_D), BackgroundColor3 = HUB_A,
	BorderSizePixel = 0, ZIndex = 8,
}, dial)
circle(hub)
outline(hub, 3, GOLD_LINE)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(HUB_A, HUB_B) }, hub)
-- ⚠️ КЛЮЧ — ЭМОДЗИ-ЗАГЛУШКА, как и в макете. Появится своя картинка — заменить
-- на ImageLabel того же размера, остальное трогать не надо.
new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "🔑",
	TextSize = math.floor(HUB_D * 0.55), Font = Enum.Font.GothamBlack, ZIndex = 9,
}, hub)

-- 3. подсказка
local hintLbl = new("TextLabel", {
	LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
	Text = "Жми, когда стрелка в зелёной зоне!",
}, column)
outline(hintLbl, 2)

-- стикер результата — над циферблатом, поверх всего
local sticker = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.fromOffset(DIAL * 0.92, DIAL * 0.21), BackgroundColor3 = STICK_HIT_A,
	BorderSizePixel = 0, Rotation = -3, Visible = false, ZIndex = 20,
}, dial)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, sticker)
outline(sticker, 3)
local stickerGrad = new("UIGradient", {
	Rotation = 90, Color = ColorSequence.new(STICK_HIT_A, STICK_HIT_B),
}, sticker)
local stickerLbl = new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
	TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 21,
	-- «В ЯБЛОЧКО!» длиннее «УПС!» вдвое: даём тексту ужиматься под плашку,
	-- иначе длинные слова обрежутся ровно на самом эффектном моменте.
	TextScaled = true,
}, sticker)
new("UITextSizeConstraint", { MaxTextSize = 22 }, stickerLbl)
outline(stickerLbl, 2)
local stickerPop = new("UIScale", {}, sticker)

-- ⚠️ КЛИК ЛОВИТ ПРОЗРАЧНАЯ КНОПКА НА ВЕСЬ ЦИФЕРБЛАТ.
-- По ТЗ жать можно куда угодно по кругу, а не в саму стрелку: попасть в
-- крутящуюся полоску мышью, тем более пальцем, невозможно.
local hitBtn = new("TextButton", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
	AutoButtonColor = false, ZIndex = 15,
}, dial)

-- ⚠️ ВДАВЛИВАНИЕ ВЕШАЕМ НА ВЕСЬ ЦИФЕРБЛАТ, А НЕ НА ЕГО «ЛИЦО».
-- У лица нет детей: шкала, диск и стрелка лежат рядом с ним, в самом dial. Сожми
-- одно лицо — дрогнет подложка, а рисунок останется на месте, и нажатие
-- прочитается как дефект, а не как отклик. И это отдельный UIScale: подгонка под
-- размер окна живёт на колонке, а двух UIScale на одном объекте движок не
-- допускает — второй он молча игнорирует.
local pressPop = new("UIScale", {}, dial)

-- ─── Состояние ───
local active     = false      -- идёт раунд, клики принимаются
local angle      = 0          -- текущий угол стрелки
local speed      = 135        -- градусов в секунду (дефолт как первый раунд)
local zoneStart  = 0
local zoneSize   = 60
local spinning   = false      -- стрелка крутится (в т.ч. пока висит стикер)
local resultBusy = false      -- на экране висит «ЕСТЬ!» или «МИМО!»
local pendingCfg = nil        -- следующий раунд, отложенный до конца показа
-- «Последняя попытка!» — состояние сессии, а не реплика на один раунд:
-- предупреждение должно висеть, пока опасность не снята.
local warnHint   = nil

local EDGE_HIT  = Color3.fromHex("52C832")
local EDGE_MISS = Color3.fromHex("F06A6A")
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- отпускание после «вдавливания»: быстрое и с лёгким перелётом, иначе нажатие
-- читается как залипание кнопки
local PRESS_BACK = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Цвет вспышки при нажатии — НЕЙТРАЛЬНЫЙ. Зелёный или красный здесь был бы
-- обещанием результата, которого клиент ещё не знает: попал или нет, решает
-- сервер, и ответ приходит на кадр-другой позже.
local EDGE_PRESS = Color3.fromHex("E8ECF2")

-- Куда вешать панель: бочка приходит Моделью или Деталью, берём деталь.
-- Если детали нет (бочка ещё не доехала до клиента) — цепляемся к игроку,
-- чтобы окно взлома не оказалось невидимым и раунд не завис вслепую.
local function adorneeOf(barrel)
	if typeof(barrel) == "Instance" then
		if barrel:IsA("BasePart") then return barrel end
		if barrel:IsA("Model") then
			return barrel.PrimaryPart or barrel:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	local char = player.Character
	return char and (char:FindFirstChild("Head") or char.PrimaryPart)
end

-- Красим сегменты: те, что попали в зону, — зелёные.
local function paintZone(zoneColor)
	local step = 360 / TICKS
	for i = 1, TICKS do
		local a = (i - 1) * step
		local rel = (a - zoneStart + 360) % 360
		ticks[i].BackgroundColor3 = (rel < zoneSize) and zoneColor or TRACK
	end
end

local function setFace(color)
	face.BackgroundColor3 = color
end

local function showSticker(words, colorA, colorB)
	stickerLbl.Text = words[math.random(#words)]
	sticker.BackgroundColor3 = colorA
	stickerGrad.Color = ColorSequence.new(colorA, colorB)
	sticker.Visible = true
end

local function close()
	active = false
	spinning = false
	resultBusy = false
	pendingCfg = nil
	warnHint = nil
	board.Enabled = false
	board.Adornee = nil
	sticker.Visible = false
	setFace(FACE)
	faceStroke.Color = DARK
	faceStroke.Thickness = 7
end

-- Настроить циферблат на новый раунд.
-- ⚠️ СТРЕЛКУ НА НОЛЬ СБРАСЫВАЕМ ТОЛЬКО НА НОВОЙ БОЧКЕ.
-- Внутри сессии она обязана идти без разрывов (так в ТЗ), а сервер ставит
-- зону в 40..320° — то есть заведомо не под стартовым нулём стрелки.
local function applyRound(cfg)
	zoneStart = cfg.sectorStart or 0
	zoneSize  = cfg.sectorSize or 60
	speed     = cfg.speed or 135
	if not board.Enabled then
		angle = 0
		needleWrap.Rotation = 0
		board.Adornee = adorneeOf(cfg.barrel)
	end
	paintZone(ZONE)
	setFace(FACE)
	faceStroke.Color = DARK
	faceStroke.Thickness = 7
	sticker.Visible = false
	roundLbl.Text = ("%d / %d"):format(cfg.round or 1, cfg.rounds or 3)

	--[[ Осталась одна попытка — говорим об этом сразу, ещё до промаха.
	     При лимите в один промах сообщения «miss» уже не будет: бочка тонет
	     с первого раза, и предупредить после — значит не предупредить. ]]
	local left = tonumber(cfg.missesLeft)
	if left and left <= 1 then
		warnHint = "Один промах — бочка утонет!"
	end
	hintLbl.Text = warnHint or "Жми, когда стрелка в зелёной зоне!"
	board.Enabled = true
	spinning = true
	active = true
end

-- ⚠️ ПОКАЗ РЕЗУЛЬТАТА ДЕРЖИТ СЛЕДУЮЩИЙ РАУНД.
-- Сервер шлёт "hit"/"miss" и СРАЗУ ЖЕ "begin" следующего раунда — из-за этого
-- стикер и цветная рамка стирались в том же кадре, в котором появлялись, и
-- эффекта не было видно вообще. Теперь новый раунд кладётся в pendingCfg и
-- применяется, когда показ доиграл. Ждать безопасно: сервер раунд по времени
-- не гонит, он ждёт нашего клика, а клики на время показа выключены.
local function flashResult(words, colorA, colorB, edge)
	resultBusy = true
	active = false
	showSticker(words, colorA, colorB)
	faceStroke.Color = edge
	faceStroke.Thickness = 12   -- рамка вокруг циферблата вспыхивает цветом ответа
	stickerPop.Scale = 0.5      -- выскакивает, а не проявляется
	TweenService:Create(stickerPop, POP, { Scale = 1 }):Play()
	task.delay(RESULT_HOLD, function()
		if not board.Enabled then return end -- бочку уже закрыли/утопили
		resultBusy = false
		sticker.Visible = false
		setFace(FACE)
		faceStroke.Color = DARK
		faceStroke.Thickness = 7
		if pendingCfg then
			local cfg = pendingCfg
			pendingCfg = nil
			applyRound(cfg)
		end
	end)
end

-- Стрелка крутится НЕПРЕРЫВНО, в том числе пока висит стикер: по ТЗ она не
-- останавливается никогда. Клики в это время просто не принимаются (active).
RunService.RenderStepped:Connect(function(dt)
	if not spinning then return end
	-- Бочку могли утопить или собрать без нашего ведома: панель, повисшая на
	-- уничтоженной детали, осталась бы висеть мёртвым кругом.
	local ad = board.Adornee
	if ad and not ad:IsDescendantOf(workspace) then
		close()
		return
	end
	angle = (angle + speed * dt) % 360
	needleWrap.Rotation = angle
end)

--[[ ⚠️ ОТКЛИК НА НАЖАТИЕ РИСУЕТ КЛИЕНТ, НЕ ДОЖИДАЯСЬ СЕРВЕРА.
     Попал игрок или нет — решает сервер, и его ответ приходит кадром-другим
     позже, а на плохой связи заметно позже. Всё это время экран не отвечал на
     клик ничем, и жать приходилось наугад: непонятно даже, засчитался ли сам
     клик. Здесь говорится ровно одно — «нажатие принято»: циферблат
     вдавливается, обод коротко вспыхивает НЕЙТРАЛЬНЫМ светом и звучит сухой
     щелчок. Результат по-прежнему рисует flashResult, и цвет ответа мы не
     угадываем. ]]
local function pressFeedback()
	sndPress:Play()
	pressPop.Scale = 0.93
	TweenService:Create(pressPop, PRESS_BACK, { Scale = 1 }):Play()
	faceStroke.Color = EDGE_PRESS
	faceStroke.Thickness = 10
	-- Вспышку гасим сами, но только если ответ ещё не пришёл: он красит обод
	-- своим цветом, и наш возврат в тёмный стёр бы его на полуслове.
	task.delay(0.18, function()
		if board.Enabled and not resultBusy then
			faceStroke.Color = DARK
			faceStroke.Thickness = 7
		end
	end)
end

local function tryStop()
	if not active then return end
	active = false            -- один клик на раунд: ответ придёт с сервера
	pressFeedback()
	lockEvent:FireServer("stop", angle)
end

hitBtn.Activated:Connect(tryStop)

--[[ ⚠️ ЖМЁМ ГДЕ УГОДНО, А НЕ ТОЛЬКО ПО ЦИФЕРБЛАТУ.
     Клик засчитывался единственной кнопкой поверх круга. На мониторе это ещё
     терпимо, а на телефоне круг мелкий: игрок целится пальцем в кольцо вместо
     того, чтобы следить за стрелкой, и промахивается мимо самого нажатия —
     проигрывает не по реакции, а по попаданию в UI.
     Теперь удар засчитывает любое нажатие на экране, пока идёт раунд. Клавиши
     остаются: пробел — удар, Esc — выход.

     ⚠️ gp (gameProcessed) НЕ игнорируем.
     Это нажатия, которые движок уже отдал другому интерфейсу: чат, кнопки
     хотбара, сам циферблат. Перехватывать их значило бы бить по замку в момент,
     когда игрок пишет в чат или жмёт соседнюю кнопку. По циферблату при этом
     удар всё равно проходит — там своя кнопка (hitBtn), и она сработает первой. ]]
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not board.Enabled then return end

	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		tryStop()
	elseif input.KeyCode == Enum.KeyCode.Space then
		tryStop()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		lockEvent:FireServer("cancel")
		close()
	end
end)

lockEvent.OnClientEvent:Connect(function(action, a, b)
	if action == "begin" then
		local cfg = a or {}
		if resultBusy then
			pendingCfg = cfg   -- досмотрим «ЕСТЬ!»/«МИМО!», потом начнём раунд
		else
			applyRound(cfg)
		end

	elseif action == "hit" then
		-- Тон растёт с каждым попаданием серии: прогресс слышно, а не только видно.
		sndHit.PlaybackSpeed = HIT_PITCH[math.clamp((tonumber(a) or 1), 1, #HIT_PITCH)]
		sndHit:Play()
		paintZone(ZONE_HOT)
		flashResult(HIT_WORDS, STICK_HIT_A, STICK_HIT_B, EDGE_HIT)

	elseif action == "miss" then
		sndMiss:Play()
		paintZone(ZONE_DIM)
		setFace(FACE_MISS)
		flashResult(MISS_WORDS, STICK_MISS_A, STICK_MISS_B, EDGE_MISS)
		-- a = сколько ошибок ещё можно допустить. Игрок должен понимать, что
		-- следующий промах утопит бочку, ДО того как это случится.
		local left = tonumber(a)
		warnHint = (left and left <= 1) and "Последняя попытка!" or nil
		hintLbl.Text = warnHint or "Промах — серия сброшена"

	elseif action == "sunk" then
		close()
		if _G.Notify then
			_G.Notify({ type = "warn", icon = "🌊", title = "Бочка ушла на дно",
				body = "Замок сломался — содержимое потеряно" })
		end

	elseif action == "opened" then
		-- Уведомления тут НЕТ намеренно: что выпало, и так видно по салюту
		-- иконок над бочкой и по прибавке в инвентаре.
		sndHit.PlaybackSpeed = HIT_PITCH[#HIT_PITCH]
		sndHit:Play()
		setFace(FACE_WIN)
		paintZone(ZONE_HOT)
		roundLbl.Text = "3 / 3"
		faceStroke.Color = EDGE_HIT
		faceStroke.Thickness = 12
		showSticker({ "ОТКРЫТО! 🎉" }, STICK_HIT_A, STICK_HIT_B)
		stickerPop.Scale = 0.5
		TweenService:Create(stickerPop, POP, { Scale = 1 }):Play()
		active = false
		resultBusy = false
		task.delay(WIN_HOLD, close)

	elseif action == "denied" then
		close()
		if _G.Notify then
			_G.Notify({ type = "warn", icon = "🔒", title = "Замок",
				body = tostring(a or "Не получилось") })
		end

	elseif action == "cancel" then
		close()
	end
end)

print("[Бочка] интерфейс взлома собран по хендоффу (панель висит над бочкой)")
