local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- TrackerCard.client.lua
-- HUD-трекер активного квеста — дизайн по хендоффу design_handoff_quest_tracker:
-- компактный виджет в ВЕРХНЕМ ЛЕВОМ углу, ПОД роблоксовским топбаром (IgnoreGuiInset
-- выключен — системный инсет отступает сам). Без плашки-подложки — чистый текст с
-- чёрной обводкой поверх игры + тонкий прогресс-бар:
--   • заголовок квеста: 23px, белый, обводка ~2.5 (кириллица → GothamBlack);
--   • кнопка «?» 26×26: синяя #4a90dc, рамка 2px, скругление 8, тень-подложка снизу;
--     клик открывает меню квестов (_G.OpenQuestMenu);
--   • бар 13px: фон чёрный 55%, рамка 2px, заливка — зелёный вертикальный градиент
--     #6fdc5f → #35b435 → #1f7a24, ширина твинится 0.35s при изменении прогресса;
--   • счётчик «2/5»: 20px, белый с обводкой, справа от бара;
--   • таймер испытаний — красная метка в строке заголовка (логика прежнего трекера).
-- Данные — тот же QuestState RemoteEvent, что у меню (первый квест с q.tracked == true).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local function waitForQuestStateEvent(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local evt = ReplicatedStorage:FindFirstChild("QuestState")
		if evt and evt:IsA("RemoteEvent") then
			return evt
		end
		task.wait(0.1)
	end
	return nil
end

-- ── геометрия/палитра (из хендоффа) ──
local TRACKER_W = 300
local MARGIN_X, MARGIN_Y = 14, 10
local TITLE_H = 28
local BAR_H = 13
local BAR_Y = TITLE_H + 8 -- отступ ряда прогресса от заголовка

local BLUE       = Color3.fromRGB(74, 144, 220)  -- #4a90dc — кнопка «?»
local FILL_TOP   = Color3.fromRGB(111, 220, 95)  -- #6fdc5f
local FILL_MID   = Color3.fromRGB(53, 180, 53)   -- #35b435
local FILL_DARK  = Color3.fromRGB(31, 122, 36)   -- #1f7a24
local TIMER_RED  = Color3.fromRGB(255, 107, 90)
local FONT = Enum.Font.GothamBlack -- кириллица; для латиницы хендофф предлагал FredokaOne

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ── ScreenGui + контейнер ──
local screenGui = new("ScreenGui", {
	Name = "QuestTrackerGui", ResetOnSpawn = false,
	IgnoreGuiInset = false, -- сидим ПОД топбаром Roblox: инсет отступает сам
	DisplayOrder = 80,      -- ниже QuestMenu (110) / кнопки входа (90) / телефона (200)
	Enabled = false,        -- включается, когда есть отслеживаемый квест
}, localPlayer:WaitForChild("PlayerGui"))

local container = new("Frame", {
	Name = "Tracker", AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, MARGIN_X, 0, MARGIN_Y),
	Size = UDim2.fromOffset(TRACKER_W, BAR_Y + BAR_H + 4),
	BackgroundTransparency = 1, BorderSizePixel = 0,
}, screenGui)

-- ⚠️ НА ТЕЛЕФОНЕ ТРЕКЕР СЖИМАЕМ ЦЕЛИКОМ.
-- Ширина TRACKER_W и кегль подбирались под монитор. На телефоне карточка занимала
-- почти полэкрана в ширину и наезжала на столбик кнопок слева (на скриншоте
-- название квеста лежало прямо на «Квестах» и «Карте»). Один UIScale на контейнер:
-- внутренняя вёрстка (ряд заголовка, «?», полоса прогресса) остаётся прежней.
-- ⚠️ ВЕШАТЬ НА container, А НЕ НА screenGui: UIScale работает только внутри
-- GuiObject, на ScreenGui он не применяется вовсе.
--[[ ⚠️ МНОЖИТЕЛЬ ТРЕКЕРНЫЙ, А НЕ ПАНЕЛЬНЫЙ.
     Вызов шёл без второго аргумента, то есть брал factor() по умолчанию — 0.55,
     придуманный для МЕНЮ во весь экран. На телефоне он ещё умножается на долю
     высоты, и карточка выходила около 0.4: сто двадцать пикселей ширины и
     строка, которую не прочесть. А это единственное место, где написано, что
     игроку делать прямо сейчас.
     Своё число (см. trackerFactor в HudScale) поднимает её примерно в полтора
     раза и при этом оставляет запас до столбика кнопок под ней — просто
     карточный множитель 0.85 упёрся бы в «Квесты» на низком экране.
     Функцией, а не числом: при повороте телефона пересчитается сама. ]]
do
	local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))
	Hud.applyScaleLive(container, Hud.trackerFactor)
end

-- ── строка заголовка: [название][?][таймер] в ряд с зазором 9 ──
local titleRow = new("Frame", {
	Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundTransparency = 1,
}, container)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 9),
}, titleRow)

local title = new("TextLabel", {
	LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 0, TITLE_H), BackgroundTransparency = 1,
	Font = FONT, TextSize = 23, TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	-- БЕЗ ClipsDescendants: он срезал чёрную обводку у последней буквы (рамка текста
	-- меряется без учёта UIStroke). Сверхдлинные названия ужимаются многоточием.
	TextTruncate = Enum.TextTruncate.AtEnd,
}, titleRow)
new("UISizeConstraint", { MaxSize = Vector2.new(TRACKER_W - 26 - 9, TITLE_H) }, title)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5 }, title)

-- «?»: тень-подложка снизу + синяя кнопка (открывает меню квестов)
local helpWrap = new("Frame", {
	LayoutOrder = 2, Size = UDim2.fromOffset(26, 29), BackgroundTransparency = 1,
}, titleRow)
local helpShadow = new("Frame", { -- тень-подложка 2.5px под кнопкой
	Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, helpShadow)
-- аура-свечение за «?» (как у редкой награды в меню квестов): «дышит», пока
-- включена подсветка брёвен — видно, что режим в работе
local helpAura = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(13, 13),
	Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(90, 180, 255),
	BackgroundTransparency = 0.5, BorderSizePixel = 0, Visible = false, ZIndex = 0,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, helpAura)
local helpAuraTween = TweenService:Create(helpAura,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.1, Size = UDim2.fromOffset(42, 42) })

-- ⚠️ СОСТОЯНИЙ ДВА, А ВИДНО БЫЛО ТОЛЬКО ОДНО.
-- Аура выше зажигается, когда подсказка УЖЕ включена, то есть отвечает на вопрос
-- «режим идёт». А на главный вопрос — «тут вообще есть кнопка?» — не отвечал
-- никто: выключённый «?» стоял неподвижным синим квадратиком у названия квеста,
-- и его просто не замечали. Поэтому у выключенного состояния теперь свой зов:
-- от кнопки расходится кольцо, как круг по воде, а сама она медленно дышит.
-- Зов НАРОЧНО редкий, с паузой между кругами: непрерывное мельтешение в углу
-- экрана начинает раздражать быстрее, чем успевает привлечь.
local helpPing = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(13, 13),
	Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1,
	BorderSizePixel = 0, Visible = false, ZIndex = 0,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, helpPing)
local pingStroke = new("UIStroke", {
	Color = Color3.fromRGB(130, 205, 255), Thickness = 2, Transparency = 0.1,
}, helpPing)

-- Кольцо и его прозрачность идут ОДНИМ таймингом: разъедутся — круг то догонит
-- собственное затухание, то отстанет, и вместо волны получится мигание.
local PING_INFO = TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
	-1, false, 1.4)   -- -1 = бесконечно, false = не назад, 1.4 — пауза между кругами
local pingGrow = TweenService:Create(helpPing, PING_INFO, { Size = UDim2.fromOffset(56, 56) })
local pingFade = TweenService:Create(pingStroke, PING_INFO, { Transparency = 1 })

local helpBtn = new("TextButton", {
	Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = BLUE, Text = "?", Font = FONT, TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true, ZIndex = 2,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, helpBtn)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, helpBtn)

-- Дыхание самой кнопки — вторая половина «зова». Кольцо ловит взгляд движением
-- по краю, а качающийся размер говорит, что двигается именно КНОПКА, а не блик
-- рядом с ней. Амплитуда маленькая: «?» стоит вплотную к названию квеста, и
-- крупный размах наезжал бы на текст.
local helpScale = new("UIScale", { Scale = 1 }, helpBtn)
local helpBreath = TweenService:Create(helpScale,
	TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.12 })

local timerLabel = new("TextLabel", {
	LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 0, TITLE_H), BackgroundTransparency = 1,
	Font = FONT, TextSize = 18, TextColor3 = TIMER_RED,
	Text = "", Visible = false,
}, titleRow)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, timerLabel)

-- ── ряд прогресса: бар (гибкая ширина) + счётчик справа, зазор 10 ──
local COUNTER_W = 46
local track = new("Frame", {
	Position = UDim2.new(0, 0, 0, BAR_Y), Size = UDim2.new(1, -(COUNTER_W + 10), 0, BAR_H),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, -- rgba(0,0,0,0.55)
	BorderSizePixel = 0, ClipsDescendants = true,
}, container)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, track)

local fill = new("Frame", {
	Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = FILL_MID, BorderSizePixel = 0,
}, track)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, FILL_TOP),
		ColorSequenceKeypoint.new(0.5, FILL_MID),
		ColorSequenceKeypoint.new(1, FILL_DARK),
	}),
}, fill)

local counter = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, BAR_Y - 4),
	Size = UDim2.fromOffset(COUNTER_W, 20), BackgroundTransparency = 1,
	Font = FONT, TextSize = 20, TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Right, Text = "",
}, container)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, counter)

local questStateEvent = waitForQuestStateEvent(30)
if not questStateEvent then
	warn("[TrackerCard] QuestState RemoteEvent missing; tracker disabled")
	return
end

-- ── реактивная отрисовка: первый q.tracked == true из снапшота QuestState ──
local trackedQuest
local trackedDeadline

local function fmtSeconds(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

-- ── подсветка БРЁВЕН в океане (онбординг-квест First Timber) ──
-- Пока отслеживается onboarding_logs, кнопка «?» ВКЛЮЧАЕТ/ВЫКЛЮЧАЕТ золотую подсветку
-- всех плавающих брёвен (ресурсы с атрибутом ResourceType == "Log"), включая те, что
-- заспавнятся позже. При смене/завершении квеста подсветка гаснет сама.
local ONBOARDING_ID = "onboarding_logs"
-- Второй онбординг-квест (Fresh Water): «?» включает пошаговую подсказку
-- с подсветкой UI — логика живёт в PurifierQuestHint.client.lua и
-- публикуется через _G.PurifierHintSetEnabled / _G.PurifierHintEnabled.
local PURIFIER_ID = "onboarding_purifier"
-- Третий онбординг-квест (Ночлег): «?» так же включает пошаговую подсказку —
-- логика в BedQuestHint.client.lua, ручки _G.BedHintSetEnabled / _G.BedHintEnabled.
local BED_ID = "onboarding_bed"
-- Четвёртый (Водолаз): «?» подсвечивает монолит — DiverQuestHint.client.
local DIVER_ID = "onboarding_diver"
-- Расширение плота: «?» ведёт по шагам молоток → руки → клетка пола.
local RAFT_ID = "onboarding_raft"
-- Свой огород: «?» ведёт по шагам грядка → установка → полив → посадка свёклы
-- (BeetQuestHint.client.lua).
local BEET_ID = "onboarding_beet"
-- «Место для вещей»: ящик по первому переполнению рюкзака (StorageQuestHint.client)
local STORAGE_ID = "storage_box"
-- Цепочка стартового острова: «?» подсвечивает то, что нужно на текущем шаге —
-- корову (а после охоты упавшее мясо) и путь до жареного мяса. Подсветка коровы —
-- StartIsleQuestHint.client.lua, шаги мангала — StartIsleGrillHint.client.lua.
-- У первого квеста подсказки нет: подсвечивать остров целиком нечего, он и так
-- стоит по курсу.
local ISLE_COW_ID   = "startisle_cow"
local ISLE_MEAT_ID  = "startisle_meat"
local GOLD = Color3.fromRGB(255, 210, 58)
local logsGlowOn = false   -- тумблер «?» первого квеста (сама подсветка — в resGlow)

-- «дышащая» аура вокруг «?» — общий индикатор «режим подсказки включён»
-- (подсветка брёвен у квеста #1 или пошаговая подсказка у квеста #2)
-- on = подсказка включена. Включена — ровная аура «режим работает» и никакого
-- зова: звать уже некуда, игрок нажал. Выключена — наоборот.
local function setHelpAura(on)
	helpAura.Visible = on
	helpPing.Visible = not on

	if on then
		pingGrow:Cancel()
		pingFade:Cancel()
		helpBreath:Cancel()
		helpScale.Scale = 1
		helpAuraTween:Play()
	else
		helpAuraTween:Cancel()
		helpAura.BackgroundTransparency = 0.5
		helpAura.Size = UDim2.fromOffset(34, 34)
		-- ⚠️ ПЕРЕД ЗАПУСКОМ ВОЗВРАЩАЕМ НАЧАЛЬНЫЕ ЗНАЧЕНИЯ РУКАМИ.
		-- Cancel останавливает твин ТАМ, ГДЕ ЗАСТАЛ, и повторный Play поехал бы от
		-- полурастянутого и полупрозрачного кольца: первый круг после выключения
		-- подсказки выходил бы обрубком.
		helpPing.Size = UDim2.fromOffset(26, 26)
		pingStroke.Transparency = 0.1
		pingGrow:Play()
		pingFade:Play()
		helpBreath:Play()
	end
end

local function purifierHintEnabled()
	return typeof(_G.PurifierHintEnabled) == "function" and _G.PurifierHintEnabled() == true
end

local function bedHintEnabled()
	return typeof(_G.BedHintEnabled) == "function" and _G.BedHintEnabled() == true
end

-- Любая пошаговая подсказка: аура «?» отражает их все разом.
local function diverHintEnabled()
	return typeof(_G.DiverHintEnabled) == "function" and _G.DiverHintEnabled() == true
end

local function raftHintEnabled()
	return typeof(_G.RaftHintEnabled) == "function" and _G.RaftHintEnabled() == true
end

local function storageHintEnabled()
	return typeof(_G.StorageHintEnabled) == "function" and _G.StorageHintEnabled() == true
end
local function beetHintEnabled()
	return typeof(_G.BeetHintEnabled) == "function" and _G.BeetHintEnabled() == true
end

-- Подсказки цепочки острова: ручки одни на три квеста по форме, но каждая своя.
local function isleHintEnabled(getName)
	return typeof(_G[getName]) == "function" and _G[getName]() == true
end

local function anyIsleHintOn()
	return isleHintEnabled("StartIsleCowHintEnabled")
		or isleHintEnabled("StartIsleGrillHintEnabled")
end

local function anyHintOn()
	return purifierHintEnabled() or bedHintEnabled()
		or diverHintEnabled() or raftHintEnabled() or beetHintEnabled()
		or storageHintEnabled() or anyIsleHintOn()
end

-- Все пошаговые подсказки одной таблицей: id квеста → как её включить и как
-- спросить состояние. Ручки живут в _G и появляются, когда загрузится их скрипт,
-- поэтому храним ИМЯ, а не саму функцию.
-- (Подсветка брёвен у первого квеста устроена иначе — она целиком внутри этого
-- файла, см. setLogsGlow, и в таблицу не входит.)
local HINTS = {
	[PURIFIER_ID] = { set = "PurifierHintSetEnabled", get = purifierHintEnabled },
	[BED_ID]      = { set = "BedHintSetEnabled",      get = bedHintEnabled },
	[DIVER_ID]    = { set = "DiverHintSetEnabled",    get = diverHintEnabled },
	[RAFT_ID]     = { set = "RaftHintSetEnabled",     get = raftHintEnabled },
	[BEET_ID]     = { set = "BeetHintSetEnabled",     get = beetHintEnabled },
	[STORAGE_ID]  = { set = "StorageHintSetEnabled",  get = storageHintEnabled },
	-- «Земли по курсу» здесь нет намеренно: подсвечивать остров целиком нечего,
	-- он и так стоит по курсу и виден с плота. Её «?» открывает меню квестов.
	[ISLE_COW_ID]   = { set = "StartIsleCowHintSetEnabled",
		get = function() return isleHintEnabled("StartIsleCowHintEnabled") end },
	-- «Мясо на углях» — пошаговая подсказка, отдельным скриптом
	-- (StartIsleGrillHint.client.lua): собрать мангал → поставить → разжечь →
	-- положить мясо. Подсветкой предмета тут не обойтись — мангала ещё нет.
	[ISLE_MEAT_ID]  = { set = "StartIsleGrillHintSetEnabled",
		get = function() return isleHintEnabled("StartIsleGrillHintEnabled") end },
	-- сюжет торговца: первый житель → «Команда» → рыбацкое место (TeamQuestHint.client)
	["story_assign_fisher"] = { set = "TeamHintSetEnabled",
		get = function() return typeof(_G.TeamHintEnabled) == "function" and _G.TeamHintEnabled() == true end },
	-- сюжет торговца: подарок → в руки → поставить на край плота (FishingPlaceHint.client)
	["story_fishing_place"] = { set = "FishingPlaceHintSetEnabled",
		get = function() return typeof(_G.FishingPlaceHintEnabled) == "function" and _G.FishingPlaceHintEnabled() == true end },
}

-- ── РЕЖИМ ТУТОРИАЛА ──
-- Пока true, каждый новый квест приходит с уже зажжённой подсказкой. Гаснет
-- НАВСЕГДА (на забег), как только игрок выключит подсказку кнопкой «?»: раз он
-- знает, где эта кнопка, и она ему не нужна — навязываться больше незачем.
-- Включить обратно можно тем же «?», но сам себя туториал уже не предлагает.
-- Живёт в пределах сессии: новая игра — снова с нуля, как и сами квесты.
local tutorialOn = true

-- ⚠️ ЗЕЛЁНЫЙ, А НЕ ЗОЛОТОЙ.
-- Золото на воде под солнцем сливалось с бликами: на скриншоте бревно и блик
-- различить было нельзя. Зелёный на синем читается издалека.
local LOG_GREEN = Color3.fromRGB(70, 235, 90)

-- Иконка-указатель над ресурсом (исходник: test/quest_arrow/Quest_arrow_down.png).
-- Пусто = запасной ромб (см. ниже), он рисуется без ассетов.
local ARROW_ICON = "rbxassetid://78628006161298"

-- ⚠️ СТРЕЛКУ ВЕШАЕМ НА СЕРЕДИНУ ГАБАРИТА, А НЕ НА САМ ОБЪЕКТ.
-- BillboardGui считает смещение от начала координат того, к чему привязан, а у
-- импортированного бревна оно на торце — стрелка и висела сбоку. Ставим внутрь
-- Attachment ровно в центр габарита: тогда «над» действительно означает над.
-- ⚠️ ВЕШАЕМ НА САМУЮ КРУПНУЮ ДЕТАЛЬ, БЕЗ ВСЯКИХ СМЕЩЕНИЙ.
-- Прошлые заходы считали центр габарита модели и клали его в локальные
-- координаты якоря. У плавающего бревна это не работает в принципе: оно
-- переворачивается на волне, локальные оси едут вместе с ним, и «центр» уползает
-- вбок тем дальше, чем круче крен. Начало координат любой BasePart и так лежит в
-- середине её габарита, поэтому берём самую большую деталь бревна и держимся за
-- неё — без пересчётов, без дрейфа, при любом положении.
local function centreAttachment(inst)
	local part, size
	if inst:IsA("BasePart") then
		part, size = inst, inst.Size
	elseif inst:IsA("Model") then
		local best, bestVol = nil, -1
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bestVol then best, bestVol = d, v end
			end
		end
		-- ⚠️ У ОСЬМИНОГА PrimaryPart — НЕПОДВИЖНЫЙ ЯКОРЬ.
		-- Это невидимый кубик 1×1×1, он заанкорен, а качается, всплывает и тонет
		-- голова: её двигает сустав. Стрелка на пивоте висела бы на месте, пока
		-- туша ходит вверх-вниз. Самая крупная деталь у него — как раз голова.
		part = (not inst:GetAttribute("IsOctopus") and inst.PrimaryPart) or best
		size = part and part.Size
	end
	if not (part and size) then return nil end

	-- ⚠️ ЯКОРЬ СТАВИМ РОВНО В ЦЕНТР, БЕЗ ПОДЪЁМА.
	-- Подъём вверх зашивать сюда нельзя: координаты якоря ЛОКАЛЬНЫЕ, и когда
	-- бревно переворачивается на волне, вместе с ним поворачивается и смещение —
	-- стрелку уносило вбок и под воду. Высоту даёт StudsOffsetWorldSpace у самого
	-- билборда: она мировая и повороту не подвластна.
	--
	-- ⚠️ И СНАЧАЛА ПРИКРЕПИТЬ, ПОТОМ ЗАДАВАТЬ ПОЗИЦИЮ.
	-- У Attachment без родителя мировых координат нет вовсе.
	-- Подъём считаем по самой длинной стороне: бревно лежит боком, и «половина
	-- высоты» у него — это половина толщины, стрелка утыкалась бы в само бревно.
	local span = math.max(size.X, size.Y, size.Z)
	local lift = span * 0.5 + 1.1
	-- ⚠️ ОСЬМИНОГУ ПОДЪЁМ БОЛЬШЕ, ЧЕМ ДАЁТ ОБЩАЯ ФОРМУЛА.
	-- Билборд со стрелкой 3.4 стада высотой и центрируется на подъёме — нижний
	-- край уходит на 1.7 стада НИЖЕ него. Плоскому бревну этого хватало, а у
	-- осьминога над центром головы ещё корона, да и сам он качается на волне:
	-- стрелка въезжала прямо в него. Прибавка, а не замена формулы — у бревна
	-- высота выверена отдельно, и трогать её незачем.
	if inst:GetAttribute("IsOctopus") then lift += 2.2 end
	part:SetAttribute("ArrowLift", lift)
	return part
end

-- Состояние подсветки ПО ТИПУ РЕСУРСА: [resType] = { glows = {...}, addedConn }
-- Отсутствие записи = подсветка этого типа выключена.
-- Типов больше одного, потому что в те же брёвна упирается расширение плота, а в
-- канистры — очиститель воды: подсказки этих квестов зовут ту же подсветку через
-- _G.ResourceGlowSetEnabled, а не заводят свою.
local resGlow = {}

local function glowResource(resType, inst)
	local st = resGlow[resType]
	if not st or st.glows[inst] then return end
	if inst:GetAttribute("ResourceType") ~= resType then return end
	local hl = Instance.new("Highlight")
	-- ⚠️ ТОЛЬКО КОНТУР, БЕЗ ЗАЛИВКИ.
	-- Заливка перекрашивала само бревно в зелёное, и было не понять, что это
	-- бревно: на воде плавали зелёные плашки. Обводка показывает, ЧТО подсвечено,
	-- не подменяя предмет.
	hl.FillTransparency = 1
	hl.OutlineColor = LOG_GREEN
	hl.OutlineTransparency = 0
	-- ⚠️ Occluded, А НЕ AlwaysOnTop.
	-- С AlwaysOnTop контур пробивался сквозь волны и плот: бревно за гребнем
	-- читалось как висящее в воздухе кольцо. Occluded прячет обводку за тем, что
	-- реально закрывает бревно, — за место подсветки отвечает стрелка.
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = inst
	hl.Parent = inst
	st.glows[inst] = hl

	-- ⚠️ СТРЕЛКА НАД БРЕВНОМ, А НЕ ТОЛЬКО КОНТУР.
	-- Контур говорит «вот оно», но на ряби из десятка бликов глаз всё равно ищет.
	-- Стрелка сверху показывает НАПРАВЛЕНИЕ и, покачиваясь, ловит взгляд движением
	-- там, где всё остальное неподвижно.
	local att = centreAttachment(inst)
	if not att then return end

	-- ⚠️ РАЗМЕР В СТУДАХ (Scale), А НЕ В ПИКСЕЛЯХ (Offset).
	-- У BillboardGui offset — это ПОСТОЯННЫЙ размер на экране: стрелка над
	-- бревном у горизонта рисовалась ровно такой же, как над соседним, и
	-- закрывала пол-неба. Scale задаёт величину в мире, и указатель ведёт себя
	-- как предмет: вблизи крупный, вдали мелкий.
	-- ⚠️ AlwaysOnTop ВЫКЛЮЧЕН.
	-- С ним стрелка рисовалась поверх всего, включая собственное бревно, и от
	-- этого казалась ещё и «наклеенной на экран».
	local lift = att:GetAttribute("ArrowLift") or 3.2
	local bb = Instance.new("BillboardGui")
	bb.Name = "QuestArrow"
	bb.Size = UDim2.fromScale(3.4, 3.4)      -- студа
	-- ⚠️ ПОДЪЁМ ЧЕРЕЗ StudsOffset, А НЕ StudsOffsetWorldSpace.
	-- Вопреки названию, «world space» отсчитывается ОТ ОСЕЙ САМОГО АДОРНИ. Бревно
	-- плавает лёжа, его собственный «вверх» смотрит вбок — и стрелку уносило
	-- вбок ровно на величину подъёма, сколько центр ни пересчитывай. StudsOffset
	-- задаётся в системе самого билборда, а тот всегда развёрнут к камере: его +Y
	-- это «вверх на экране», то есть над бревном при любом его положении.
	bb.StudsOffset = Vector3.new(0, lift, 0)
	bb.StudsOffsetWorldSpace = Vector3.zero
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	bb.Adornee = att
	bb.Parent = att       -- уходит вместе с якорем, а тот — вместе с подсветкой

	-- ⚠️ КАРТИНКА, А НЕ СИМВОЛ «▼».
	-- Первый заход рисовал стрелку текстом, и её не было видно вовсе: этот глиф
	-- есть не во всех шрифтах Roblox, и вместо стрелки получалась пустота.
	-- Иконка нарисована (test/quest_arrow/Quest_arrow_down.png); пока её id не
	-- вписан, показываем ромб из повёрнутого квадрата — он рисуется всегда.
	if ARROW_ICON ~= "" then
		local arrow = Instance.new("ImageLabel")
		arrow.Size = UDim2.fromScale(1, 1)
		arrow.BackgroundTransparency = 1
		arrow.Image = ARROW_ICON
		arrow.ScaleType = Enum.ScaleType.Fit
		arrow.Parent = bb
	else
		local dia = Instance.new("Frame")
		dia.AnchorPoint = Vector2.new(0.5, 0.5)
		dia.Position = UDim2.fromScale(0.5, 0.5)
		dia.Size = UDim2.fromScale(0.62, 0.62)
		dia.Rotation = 45
		dia.BackgroundColor3 = LOG_GREEN
		dia.BorderSizePixel = 0
		dia.Parent = bb
		local ds = Instance.new("UIStroke")
		ds.Thickness = 3
		ds.Color = Color3.new(0, 0, 0)
		ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ds.Parent = dia
	end

	-- покачивание: вверх-вниз, бесконечно
	local bob = TweenService:Create(bb,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, lift + 0.8, 0) })
	bob:Play()

	-- якорь стрелки живёт ровно столько же, сколько подсветка
	-- ⚠️ УБИРАЕМ БИЛБОРД, А НЕ ТО, К ЧЕМУ ОН ПРИКРЕПЛЁН.
	-- Держимся мы за саму деталь бревна — уничтожить её значило бы уничтожить
	-- добычу. Гасим ровно то, что создали.
	hl.Destroying:Connect(function()
		if bb.Parent then bb:Destroy() end
	end)
end

local function setResourceGlow(resType, on)
	local st = resGlow[resType]
	if on then
		if st then return end
		st = { glows = {} }
		resGlow[resType] = st
		for _, inst in ipairs(CollectionService:GetTagged("Resource")) do
			glowResource(resType, inst)
		end
		-- то, что всплывёт позже, подсвечивается сразу
		st.addedConn = CollectionService:GetInstanceAddedSignal("Resource"):Connect(function(inst)
			glowResource(resType, inst)
		end)
	else
		if not st then return end
		if st.addedConn then st.addedConn:Disconnect() end
		for _, hl in pairs(st.glows) do
			if hl.Parent then hl:Destroy() end
		end
		resGlow[resType] = nil
	end
end

local function setLogsGlow(on)
	logsGlowOn = on
	-- состояние тумблера — синее «дышащее» свечение вокруг «?» (кнопка не заливается)
	setHelpAura(on)
	setResourceGlow("Log", on)
end

-- Подсветка нужна не только первому квесту: расширение плота упирается в те же
-- брёвна, а очиститель — в канистры. Отдаём наружу ГОТОВУЮ, с зелёным контуром и
-- стрелкой, а не пересобираем вторую такую же в каждой подсказке. Владелец у неё
-- по-прежнему один, этот файл.
_G.ResourceGlowSetEnabled = function(resType, on)
	if typeof(resType) ~= "string" then return end
	setResourceGlow(resType, on and true or false)
end
_G.ResourceGlowEnabled = function(resType)
	return resGlow[resType] ~= nil
end

-- Брёвна первого квеста ходят через свою ручку: она заодно ведёт тумблер «?»
-- (logsGlowOn) и его ауру, а не только сами подсветки.
_G.LogsGlowSetEnabled = function(on)
	setLogsGlow(on and true or false)
end
_G.LogsGlowEnabled = function() return logsGlowOn end

-- появление/уход: короткий слайд от ЛЕВОГО края (виджет теперь слева)
local OPEN_INFO  = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HIDDEN_X   = -(TRACKER_W + 24)

local function slideIn()
	container.Position = UDim2.new(0, HIDDEN_X, 0, MARGIN_Y)
	TweenService:Create(container, OPEN_INFO,
		{ Position = UDim2.new(0, MARGIN_X, 0, MARGIN_Y) }):Play()
end

local function slideOutAndHide()
	local tween = TweenService:Create(container, CLOSE_INFO,
		{ Position = UDim2.new(0, HIDDEN_X, 0, MARGIN_Y) })
	tween:Play()
	tween.Completed:Connect(function()
		if not trackedQuest then
			screenGui.Enabled = false
		end
	end)
end

local wasVisible = false

-- бета-онбординг: трекер появляется через 10 секунд после входа — первые секунды
-- игрок осматривается, HUD не наваливается сразу. Пока «спим», снапшоты всё равно
-- запоминаются (trackedQuest), и по истечении задержки карточка выезжает сама.
local BOOT_DELAY = 10
local bootMuted  = true
task.delay(BOOT_DELAY, function()
	bootMuted = false
	if trackedQuest then
		screenGui.Enabled = true
		slideIn()
		wasVisible = true
	end
end)

local function paint(q)
	local previous = trackedQuest
	trackedQuest = q

	-- ⚠️ ВКЛЮЧЁННАЯ ПОДСКАЗКА РОВНО ОДНА — ЧЬЯ УГОДНО, КРОМЕ ОТСЛЕЖИВАЕМОЙ, ГАСНЕТ.
	-- Баннеры всех подсказок висят в одной точке экрана, и две включённые сразу
	-- давали нечитаемую кашу из наложенных строк. Гасим безусловно, а не «если
	-- квест сменился»: так лишняя подсказка не переживёт ни один снапшот, каким бы
	-- путём она ни включилась.
	for id, h in pairs(HINTS) do
		if h.get() and (not q or q.id ~= id) then
			local fn = _G[h.set]
			if typeof(fn) == "function" then fn(false) end
		end
	end
	if logsGlowOn and (not q or q.id ~= ONBOARDING_ID) then
		setLogsGlow(false)
	end

	-- ⚠️ КВЕСТ ОТКРЫВАЕТСЯ С УЖЕ ВКЛЮЧЁННОЙ ПОДСКАЗКОЙ — ПОКА ИДЁТ ТУТОРИАЛ.
	-- Игрок в первый раз не знает ни про кнопку «?», ни про то, что она вообще
	-- что-то делает. Ждать, пока он сам догадается её нажать, — значит смотреть,
	-- как он бродит по плоту. Выключил руками хоть раз (см. helpBtn ниже) —
	-- туториал считается пройденным, и следующие квесты приходят молча.
	-- Срабатывает только на СМЕНЕ квеста, иначе выключенная подсказка зажигалась
	-- бы обратно на каждом снапшоте.
	if tutorialOn and q and (not previous or previous.id ~= q.id) then
		if q.id == ONBOARDING_ID then
			if not logsGlowOn then setLogsGlow(true) end
		else
			local h = HINTS[q.id]
			if h then
				-- ⚠️ ЧЕРЕЗ КАДР, А НЕ СРАЗУ.
				-- Подсказки слушают тот же снапшот QuestState и по нему решают, жив
				-- ли их квест. Порядок обработчиков не задан: включи мы подсказку
				-- прямо здесь, она могла бы получить сигнал раньше своего скрипта и
				-- отказаться — «квеста ещё нет». Ждём, пока снапшот разойдётся всем.
				local wantId = q.id
				task.defer(function()
					-- ⚠️ СРАВНИВАЕМ ID, А НЕ ТАБЛИЦЫ.
					-- Каждый снапшот приносит НОВЫЕ таблицы квестов, поэтому проверка
					-- «trackedQuest ~= q» была истинной даже для того же самого квеста —
					-- и включение отменялось почти всегда.
					if not tutorialOn then return end
					if not trackedQuest or trackedQuest.id ~= wantId then return end
					local fn = _G[h.set]
					if typeof(fn) == "function" and not h.get() then
						fn(true)
						setHelpAura(logsGlowOn or anyHintOn())
					end
				end)
			end
		end
	end

	-- аура «?» отражает фактическое состояние подсказок (они могут погаснуть
	-- сами — например, квест выполнен)
	setHelpAura(logsGlowOn or anyHintOn())

	if not q then
		if wasVisible then
			slideOutAndHide()
			wasVisible = false
		else
			screenGui.Enabled = false
		end
		trackedDeadline = nil
		return
	end

	if bootMuted then
		-- «тихий» период после входа: карточку покажет task.delay выше
		screenGui.Enabled = false
		wasVisible = false
	elseif not previous or previous.id ~= q.id then
		screenGui.Enabled = true
		slideIn()
		wasVisible = true
	else
		screenGui.Enabled = true
		wasVisible = true
	end

	-- на трекере — ЗАДАЧА, которую надо выполнить, а не название квеста. Задачи
	-- отображаются ПО ОЧЕРЕДИ (первая незакрытая, потом следующая...), но сервер
	-- засчитывает прогресс ВСЕМ одновременно: если закрыть вторую раньше первой,
	-- к моменту её показа она уже будет полной и очередь перескочит дальше.
	-- Бар и счётчик — прогресс ИМЕННО текущей показанной задачи, не сумма всех.
	local objs = q.objectives or {}
	local activeObj = objs[#objs] -- всё закрыто → остаётся последняя (строка не пустеет)
	for _, obj in ipairs(objs) do
		local p = tonumber(obj.progress) or 0
		local g = tonumber(obj.goal) or 0
		if p < g then
			activeObj = obj
			break
		end
	end
	title.Text = (activeObj and (activeObj.label or activeObj.eventType)) or q.title or q.id or ""
	local prog = activeObj and (tonumber(activeObj.progress) or 0) or 0
	local goal = activeObj and (tonumber(activeObj.goal) or 0) or 0

	-- заливка твинится (~0.35s из хендоффа), счётчик — «2/5»
	local pct = (goal > 0) and math.clamp(prog / goal, 0, 1) or 0
	TweenService:Create(fill,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(pct, 0, 1, 0) }):Play()
	counter.Text = string.format("%d/%d", prog, goal)

	-- таймер — только для запущенных отслеживаемых испытаний
	if q.kind == "challenge" and q.startedAt and q.secondsRemaining
		and not q.rewardPending then
		timerLabel.Visible = true
		timerLabel.Text    = fmtSeconds(q.secondsRemaining)
		trackedDeadline    = os.clock() + q.secondsRemaining
	else
		timerLabel.Visible = false
		trackedDeadline    = nil
	end
end

questStateEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "state" then return end
	if type(payload) ~= "table" then return end
	local picked
	for _, q in ipairs(payload.quests or {}) do
		if q.tracked then picked = q; break end
	end
	paint(picked)
end)

-- «?»: во время онбординга #1 — ТУМБЛЕР подсветки брёвен в океане;
-- во время онбординга #2 — ТУМБЛЕР пошаговой подсказки (подсветка кнопки
-- инвентаря → вкладки крафта → рецепта → установка/заливка очистителя);
-- после них — как раньше, открывает меню квестов
helpBtn.Activated:Connect(function()
	local id = trackedQuest and trackedQuest.id

	-- Выключение РУКАМИ закрывает туториал: дальше квесты приходят молча.
	-- Смотрим на НАМЕРЕНИЕ, а не на факт: setEnabled может отказаться включаться
	-- (квест уже закрыт), и по факту получилось бы «выключено» — туториал сняли бы
	-- с игрока, который его о том не просил.
	local function toggled(want)
		if not want then tutorialOn = false end
		setHelpAura(logsGlowOn or anyHintOn())
	end

	if id == ONBOARDING_ID then
		local want = not logsGlowOn
		setLogsGlow(want)
		toggled(want)
		return
	end

	local h = id and HINTS[id]
	if h then
		local fn = _G[h.set]
		if typeof(fn) == "function" then
			local want = not h.get()
			fn(want)
			toggled(want)
			return
		end
	end

	local opener = _G.OpenQuestMenu
	if typeof(opener) == "function" then
		pcall(opener)
	end
end)

--[[ ⚠️ ПОКА ИДЁТ ОТСЧЁТ ОСТРОВА — «?» СПРЯТАН, НО ТАЙМЕР НЕ ЗДЕСЬ.
     IslandQuestCard публикует _G.IslandQuestClock (секунды до конца бонуса) и
     сам рисует таймер на СВОЕЙ карточке. Раньше он дублировался и на главной
     карточке («Собери брёвна 2:57»), и выглядело так, будто основной квест
     ограничен по времени. Владелец: таймер — только у второстепенного с
     островом. Здесь на время отсчёта лишь прячем подсказку «?»: бонус — за
     самостоятельную зачистку. ]]
local islandClock = false
local function islandClockLeft()
	local fn = _G.IslandQuestClock
	if typeof(fn) ~= "function" then return nil end
	local ok, left = pcall(fn)
	return (ok and type(left) == "number" and left > 0) and left or nil
end
_G.TrackerIslandClockActive = function() return islandClock end

-- живой отсчёт таймера между серверными пушами + пинг серверу на истечении
local sentExpiryPing = false
RunService.Heartbeat:Connect(function()
	local left = islandClockLeft()
	--[[ ⚠️ «?» ОСНОВНОГО КВЕСТА ОСТАЁТСЯ ВСЕГДА. Здесь он прятался на время
	     отсчёта острова — но отсчёт относится к КАРТОЧКЕ ОСТРОВА, а не к этой:
	     с двумя активными квестами игрок терял кнопку и не мог выключить
	     подсказки основного (владелец). Запрет подсказок на время таймера ведёт
	     сама карточка острова; здесь только помним, что отсчёт идёт. ]]
	if left then
		islandClock = true
	elseif islandClock then
		islandClock = false
	end
	if not helpWrap.Visible and not trackedDeadline then helpWrap.Visible = true end
	if not trackedQuest or not trackedDeadline then return end
	if trackedQuest.rewardPending then return end
	local remaining = trackedDeadline - os.clock()
	if remaining <= 0 then
		timerLabel.Text = "0:00"
		if not sentExpiryPing then
			sentExpiryPing = true
			questStateEvent:FireServer("getState")
		end
	else
		timerLabel.Text = fmtSeconds(remaining)
		sentExpiryPing = false
	end
end)
