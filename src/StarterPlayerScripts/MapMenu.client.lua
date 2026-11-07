local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	КАРТА АРХИПЕЛАГА — полноэкранное меню.

	Открывается кнопкой «Карта» (MapButton зовёт _G.OpenMapMenu). Композиция —
	один ряд по центру экрана: слева колонка панелей 268 px, справа лист
	пергамента с океаном. Внутри листа — только карта: сетка, острова, маршрут,
	плот, роза ветров. Панели на бумаге больше не лежат.

	Все числа — из хендофа (README.md в корне), модуль MapDefs. HTML-прототип в
	игру не переносится, повторяется только внешний вид.

	⚠️ ДАННЫЕ ТОЛЬКО С СЕРВЕРА.
	Туман, владение, доход и остаток нефти считает MapSystem. Клиент не решает
	ничего — иначе цена рейса на кнопке и списание разошлись бы.

	⚠️ ПОРОГ ДРАГА 5 ПИКСЕЛЕЙ.
	Без него клик по острову на дрожащей мыши уезжает в панораму, и карточка не
	открывается вовсе.

	⚠️ ДВА UIScale, ВЛОЖЕННЫХ ДРУГ В ДРУГА, И ЭТО НЕ ЛИШНЕЕ.
	Один объект держит ровно один UIScale, а масштабов нужно два: подгонка ряда
	под узкий экран (живёт всё время) и анимация открытия (живёт полсекунды).
	Слить их в один нельзя — открытие затирало бы подгонку, и на телефоне карта
	после анимации распухала бы за края экрана.

	⚠️ ОСТРОВА РАЗНЫЕ, НО НЕ СЛУЧАЙНЫЕ.
	Форма, поворот, наличие скального пика или лагуны считаются из id острова, а
	не берутся случайным числом: иначе остров менял бы вид при каждой пересборке
	узла. Кривых углов из хендофа в Roblox нет вовсе — чем именно они заменены,
	расписано у islandLook.

	⚠️ УЗЕЛ ОСТРОВА СТРОИТСЯ ОДИН РАЗ И ПОТОМ ПЕРЕКРАШИВАЕТСЯ.
	Снимок приходит раз в секунду; пересоздавать узел на каждый — терять
	анимации и моргать формой. Поэтому каждый узел оставляет в updaters функцию
	«перекрасься», и туман, владение и атака доезжают до картинки через неё.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local Map = require(ReplicatedStorage:WaitForChild("MapDefs"))
-- общая кнопка закрытия: один крестик на все меню (см. UITheme.closeButton)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local dataEvent = ReplicatedStorage:WaitForChild("MapData")
local sailEvent = ReplicatedStorage:WaitForChild("MapSail")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function stroke(inst, thickness, color)
	return new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

-- Обводка ТЕКСТА — режим по умолчанию (Contextual): на TextLabel он обводит
-- буквы, а не рамку. Путать с stroke() выше нельзя: тот рисует бордер панели.
local function textEdge(label, thickness)
	return new("UIStroke", { Thickness = thickness or 2, Color = Color3.new(0, 0, 0) }, label)
end

-- ═══════════ размеры ряда ═══════════

-- ⚠️ ЭТИ ТРИ ЧИСЛА ДЕРЖАТ ВСЮ КОМПОЗИЦИЮ.
-- Колонка ровно 268: в неё по ширине сажались карточка острова и чипы, и текст
-- в них подобран без переносов. Сузишь — «Плыть сюда — N нефти» уедет в две
-- строки, расширишь — лист карты начнёт сжиматься масштабом раньше времени.
-- Зазор 22 отделяет тёмные панели от светлой бумаги; убери его, и колонка
-- прочитается как поля листа, а не как отдельный блок.
local COLUMN_W   = 268
local ROW_GAP    = 22
local SCREEN_PAD = 26    -- поля экрана из хендофа (padding: 0 26px)

-- Ниже этого масштаба текст 12–13 px превращается в кашу, и уменьшать дальше
-- бессмысленно: лучше пусть край листа уйдёт за экран, чем панели станут
-- нечитаемыми. Число подобрано по самому узкому телефону из тестовых.
local MIN_FIT    = 0.55

-- ═══════════ каркас ═══════════

local gui = new("ScreenGui", {
	Name = "MapMenuGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 95, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
}, playerGui)
_G.MapMenuScreenGui = gui

-- Затемнение — кнопка, а не Frame: тап по свободному месту закрывает карту, как
-- в настройках и квестах. Лист лежит поверх и касание до подложки не пропускает.
local dim = new("TextButton", {
	Name = "Dim", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
	Text = "", AutoButtonColor = false,
	BackgroundColor3 = Color3.fromRGB(0, 5, 10), BackgroundTransparency = 1,
}, gui)

-- Ряд целиком: подгонка под экран висит здесь, потому что сжимать надо колонку
-- и лист ВМЕСТЕ. Сожмёшь их по отдельности — каждый уедет к своему якорю, и
-- между ними появится щель, которой в хендофе нет.
local row = new("Frame", {
	Name = "Row", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(880, 520),
	BackgroundTransparency = 1, ZIndex = 2,
}, gui)
local fitScale = new("UIScale", { Scale = 1 }, row)

-- Вложенный слой только ради второго UIScale — анимации открытия.
local stack = new("Frame", {
	Name = "Stack", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, ZIndex = 2,
}, row)
local openScale = new("UIScale", { Scale = 1 }, stack)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, ROW_GAP),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, stack)

-- ═══════════ левая колонка ═══════════

-- ⚠️ ZIndex 3 — ВЫШЕ ЛИСТА (у parchment 2), И ЭТО НЕ ЛИШНЕЕ ЧИСЛО.
-- Колонка и лист — соседи по ряду, а при ZIndexBehavior.Sibling равный ZIndex
-- у соседей разрешается порядком в дереве: колонка рождается первой, значит при
-- ничьей лист рисуется ПОВЕРХ неё вместе со всем своим содержимым. Сейчас они не
-- пересекаются (ряд ровно по сумме ширин), но стоит листу однажды вылезти за
-- свою ячейку — и карточка с чипами уедет под воду. Держим колонку выше явно.
local columnBox = new("Frame", {
	Name = "ColumnBox", LayoutOrder = 1, BackgroundTransparency = 1, ZIndex = 3,
	Size = UDim2.fromOffset(COLUMN_W, 520),
}, stack)

-- ⚠️ ТРЕК СКРОЛЛБАРА — ОТДЕЛЬНЫЙ ФРЕЙМ ПОЗАДИ ПОЛЗУНКА.
-- ScrollingFrame рисует только ползунок; дорожки под ним у Roblox нет вовсе.
-- Кладём её сюда, ниже по ZIndex, ровно там, где движок рисует полосу — по
-- правой кромке. Сдвинешь ширину полосы (ScrollBarThickness) — двигай и трек,
-- иначе тёмная дорожка вылезет из-под золота.
local scrollTrack = new("Frame", {
	Name = "ScrollTrack", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 10, 1, 0),
	BackgroundColor3 = Map.CHIP_BG, BackgroundTransparency = 0.1,
	BorderSizePixel = 0, ZIndex = 2, Visible = false,
}, columnBox)
stroke(scrollTrack, 2)

-- ⚠️ ЗОЛОТО НА ПОЛЗУНКЕ ПЛОСКОЕ, А НЕ ГРАДИЕНТНОЕ.
-- В хендофе ползунок залит #ffd96a→#f0b41e, но UIGradient вешается на GuiObject,
-- а полоса прокрутки — не объект, а картинка внутри ScrollingFrame. Красить её
-- можно только одним цветом (ScrollBarImageColor3), поэтому берём середину
-- градиента. Понадобится настоящий градиент — придётся рисовать свою полосу
-- фреймами и самому считать позицию, а это уже свой скроллбар.
local column = new("ScrollingFrame", {
	Name = "Column", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 3, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	ScrollBarThickness = 10, ScrollBarImageTransparency = 0,
	ScrollBarImageColor3 = Color3.fromRGB(248, 197, 68),
}, columnBox)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, column)
-- 14 = 10 полосы плюс 4 просвета: без отступа панели уезжают под золото.
new("UIPadding", { PaddingRight = UDim.new(0, 14) }, column)

-- Трек показываем, только когда прокрутка вообще есть: иначе тёмная дорожка
-- висит вдоль пустой колонки и читается как ещё одна панель.
local function syncTrack()
	scrollTrack.Visible = column.AbsoluteCanvasSize.Y > column.AbsoluteWindowSize.Y + 1
end
column:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(syncTrack)
column:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(syncTrack)

-- ── баннер атаки (самый верх колонки) ──

local banner = new("TextLabel", {
	Name = "AttackBanner", LayoutOrder = 1, Visible = false, ZIndex = 6,
	Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(96, 14, 10), BackgroundTransparency = 0.03,
	-- 12.5 — не округление 13-ти: баннер стоит первым в колонке 268 px, и на
	-- целом кегле «Мощность атаки: 100» уходит третьей строкой, растягивая
	-- красное пятно на треть колонки.
	BorderSizePixel = 0, Font = Map.FONT, TextSize = 12.5, LineHeight = 1.35,
	TextColor3 = Color3.fromRGB(255, 214, 210), Text = "", TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	-- ⚠️ ТЕНЬ ТЕКСТА ЗДЕСЬ СТАРАЯ, TextStroke*, А НЕ UIStroke.
	-- На одном объекте работает ровно один UIStroke, а он уже занят красной
	-- рамкой баннера. Повесишь вторым textEdge — движок молча выберет один из
	-- двух, и с равной вероятностью пропадёт именно рамка, ради которой всё.
	TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0,
}, column)
local bannerEdge = stroke(banner, 3, Map.RED)
new("UIPadding", {
	PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
	PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11),
}, banner)

-- ── чипы ресурсов ──

local chipRow = new("Frame", {
	Name = "Chips", LayoutOrder = 2, BackgroundTransparency = 1, ZIndex = 6,
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, column)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, chipRow)

-- ⚠️ ЗНАЧКИ ЧИПОВ НАРИСОВАНЫ ФРЕЙМАМИ, КАРТИНОК ТУТ НЕТ И БЫТЬ НЕ МОЖЕТ.
-- Новый rbxassetid выдумать нельзя, а чип без значка читается как обычная
-- строка текста и теряется среди остальных. Формы упрощены честно: капля в CSS
-- — круг с одним прямым углом, но UICorner скругляет все четыре угла разом,
-- отдельный не задать. Остаётся цвет и место — этого хватает, чтобы отличить
-- нефть от прибыли с одного взгляда.
local function iconDrop(chip)
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(29, 29, 29),
		BorderSizePixel = 0, ZIndex = 7,
	}, chip)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
	stroke(d, 2, Map.GOLD)
end

local function iconCoin(chip)
	-- Фон белый намеренно: UIGradient УМНОЖАЕТСЯ на BackgroundColor3, и на
	-- золотом фоне золотой градиент потемнел бы вдвое.
	local c = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 7,
	}, chip)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Map.GOLD, Color3.fromRGB(217, 164, 16)),
	}, c)
	stroke(c, 2)
end

local function iconPerson(chip)
	local head = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, 18, 0.5, -6),
		Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Map.LIGHT_BLUE,
		BorderSizePixel = 0, ZIndex = 7,
	}, chip)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, head)
	stroke(head, 1.5)
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, 18, 0.5, 1),
		Size = UDim2.fromOffset(10, 6), BackgroundColor3 = Map.LIGHT_BLUE,
		BorderSizePixel = 0, ZIndex = 7,
	}, chip)
	-- Плечи скруглены сверху и снизу разом: срезать только верхние углы
	-- UICorner не умеет, а фигурка на 10 пикселях от этого не страдает.
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, body)
	stroke(body, 1.5)
end

local function makeChip(order, color, text, drawIcon)
	local chip = new("Frame", {
		LayoutOrder = order, BackgroundColor3 = Map.CHIP_BG, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 34), ZIndex = 6,
	}, chipRow)
	stroke(chip, 3)
	drawIcon(chip)
	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 32, 0.5, 0),
		Size = UDim2.new(1, -44, 1, 0), BackgroundTransparency = 1,
		Font = Map.FONT, TextSize = 13, TextColor3 = color, Text = text,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
	}, chip)
	textEdge(label)
	return label
end

local chipOil    = makeChip(1, Map.GOLD, "Нефть: +0/день", iconDrop)
local chipProfit = makeChip(2, Map.GOLD, "Прибыль: +0/день", iconCoin)
-- ⚠️ Скрыты сразу, а не только в render: первый снимок приходит через секунду
-- после открытия, и всё это время игрок видел бы «+0/день» — ровно ту строку,
-- ради которой их и убрали. Оставлены в дереве, чтобы вернуть их одной правкой,
-- когда острова начнут приносить доход по-настоящему.
--[[ ⚠️ ПРЯЧЕМ СТРОКУ ЦЕЛИКОМ, А НЕ ПОДПИСЬ В НЕЙ.
     makeChip возвращает ПОДПИСЬ, а не рамку, и Visible = false у неё гасил
     только текст: на панели оставались две тёмные плашки с иконкой и
     пустотой вместо слов. Владелец так их и отметил — «текст нечитаем».
     Гасим родителя, то есть саму плашку. ]]
chipOil.Parent.Visible = false
chipProfit.Parent.Visible = false
local chipPeople = makeChip(3, Map.LIGHT_BLUE, "Жители: 0", iconPerson)

-- ── «Ваши владения» ──

local ownedBox = new("Frame", {
	Name = "Owned", LayoutOrder = 3, ZIndex = 8, BackgroundColor3 = Map.CHIP_BG,
	BackgroundTransparency = 0.04, BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, column)
stroke(ownedBox, 3)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
}, ownedBox)

local ownedHead = new("TextButton", {
	LayoutOrder = 1, ZIndex = 9, AutoButtonColor = false, BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7,
	Size = UDim2.new(1, 0, 0, 30), Text = "",
}, ownedBox)

-- Наведение подсвечивает шапку тем же белым 0.08, что и строки списка: шапка —
-- такая же кнопка, и разная реакция на курсор читалась бы как «здесь не нажать».
-- AutoButtonColor не годится: он красит BackgroundColor3, а он тут чёрный и
-- держит фон rgba(0,0,0,0.3) — движок осветлил бы сам фон, а не наложил блик.
ownedHead.MouseEnter:Connect(function()
	ownedHead.BackgroundColor3 = Color3.new(1, 1, 1)
	ownedHead.BackgroundTransparency = 0.92
end)
ownedHead.MouseLeave:Connect(function()
	ownedHead.BackgroundColor3 = Color3.new(0, 0, 0)
	ownedHead.BackgroundTransparency = 0.7
end)

local ownedTitle = new("TextLabel", {
	Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
	BackgroundTransparency = 1, Font = Map.FONT, TextSize = 13,
	TextColor3 = Color3.new(1, 1, 1), Text = "Ваши владения",
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
}, ownedHead)
textEdge(ownedTitle)

-- Стрелка отдельной надписью, а не хвостом заголовка: она другого цвета и
-- размера, а одна TextLabel красит всю строку разом.
local ownedArrow = new("TextLabel", {
	Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
	BackgroundTransparency = 1, Font = Map.FONT_BODY, TextSize = 11,
	TextColor3 = Map.BLUE_TEXT, Text = "▲ раскрыть",
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 10,
}, ownedHead)
textEdge(ownedArrow)

local ownedDivider = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 2.5), BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0, ZIndex = 11, Visible = false,
}, ownedHead)

local ownedList = new("ScrollingFrame", {
	LayoutOrder = 2, ZIndex = 9, Visible = false, BackgroundTransparency = 1,
	BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	ScrollBarThickness = 10, ScrollBarImageColor3 = Color3.fromRGB(248, 197, 68),
}, ownedBox)
-- Отступа между строками нет намеренно: разделитель рисуется ВНУТРИ строки, по
-- её нижней кромке (в хендофе это border-bottom). Добавишь сюда padding — между
-- полосой и следующей строкой появится щель, а высота списка перестанет
-- совпадать с ownedWantH, и список начнёт то обрезать последнюю строку, то
-- оставлять под ней пустоту.
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 0),
}, ownedList)
-- Своего трека у внутреннего списка нет и не нужно: под ползунком уже лежит
-- тёмная заливка самой панели «Ваши владения» — ровно того же цвета.
new("UIPadding", { PaddingRight = UDim.new(0, 12) }, ownedList)

-- ⚠️ ВЫСОТУ СПИСКА СЧИТАЕМ САМИ, А НЕ ЧЕРЕЗ AutomaticSize.
-- Хендоф просит «по содержимому, но не выше 168». AutomaticSize у ScrollingFrame
-- дерётся с AutomaticCanvasSize (одно меняет холст, второе — окно, и они гоняют
-- друг друга кадр за кадром), поэтому высота ставится числом из syncOwned().
-- 32 = поля 7 сверху и снизу из хендофа, строка 13-го кегля между ними и 2 на
-- разделитель по нижней кромке. Число одно на всех: по нему считается и высота
-- строки, и высота всего списка, — разведёшь их, и прокрутка начнёт
-- останавливаться, не дойдя до последней строки.
local OWNED_ROW_H  = 32
local OWNED_MAX_H  = 168
local ownedOpen  = false
local ownedWantH = 0

local function applyOwnedHeight()
	ownedList.Visible = ownedOpen
	ownedList.Size = UDim2.new(1, 0, 0, ownedOpen and math.min(ownedWantH, OWNED_MAX_H) or 0)
	ownedDivider.Visible = ownedOpen
	ownedArrow.Text = ownedOpen and "▼ скрыть" or "▲ раскрыть"
end

ownedHead.Activated:Connect(function()
	ownedOpen = not ownedOpen
	applyOwnedHeight()
end)

-- ── карточка выбранного острова ──

--[[ ⚠️ У КАРТОЧКИ ТРИ БЛОКА И НИ ОДНОГО ОБЩЕГО ОТСТУПА.
     Шапка залита своим фоном и обязана идти во всю ширину карточки. Оставь на
     карточке прежний UIPadding — и тёмная шапка окажется в светлой рамке из
     полей, которой в хендофе нет; поэтому поля теперь платит каждый блок сам.
     Полоса под шапкой — отдельная строка списка, а не «бордер снизу»: любой
     ребёнок фрейма с UIListLayout встаёт в тот же список, и линия, повешенная
     внутрь шапки, стала бы её третьей строкой вместо кромки. ]]
local card = new("Frame", {
	Name = "Card", LayoutOrder = 4, Visible = false, ZIndex = 12,
	BackgroundColor3 = Map.PANEL, BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 10), AutomaticSize = Enum.AutomaticSize.Y,
}, column)
stroke(card, 4)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 0),
}, card)

-- ── шапка: название и статус ──

local cardHead = new("Frame", {
	LayoutOrder = 1, ZIndex = 13, BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.75,
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, card)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, cardHead)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
}, cardHead)

local function headLine(order, size, color)
	local l = new("TextLabel", {
		LayoutOrder = order, BackgroundTransparency = 1, Font = Map.FONT,
		TextSize = size, TextColor3 = color, Text = "", ZIndex = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 4), AutomaticSize = Enum.AutomaticSize.Y,
	}, cardHead)
	textEdge(l)
	return l
end

-- ⚠️ ИМЯ ОСТРОВА ЖИВЁТ ТОЛЬКО ЗДЕСЬ, И RichText У ЭТОЙ НАДПИСИ ВЫКЛЮЧЕН.
-- Имя приходит из названия модели в Workspace, то есть из данных: включи тут
-- разметку — и первый же «<» в названии съест половину заголовка.
local cName   = headLine(1, 17, Color3.new(1, 1, 1))
local cStatus = headLine(2, 13, Map.NEUTRAL_TEXT)

new("Frame", {   -- кромка под шапкой: border-bottom 3px #000 из хендофа
	LayoutOrder = 2, ZIndex = 13, BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 3),
}, card)

-- ── тело: строки данных ──

local cardBody = new("Frame", {
	LayoutOrder = 3, ZIndex = 13, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, card)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, cardBody)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, cardBody)

-- Метка и значение в строке разного цвета, но надпись одна: RichText — штатный
-- механизм Roblox, и он дешевле пары TextLabel рядом. Разведёшь их по двум
-- объектам — придётся руками считать ширину метки, и значение поедет от длины
-- слова «Приносит прибыль».
local function cardLine(order, size, color, rich)
	local l = new("TextLabel", {
		LayoutOrder = order, BackgroundTransparency = 1, Font = Map.FONT_BODY,
		TextSize = size, TextColor3 = color, Text = "", ZIndex = 14,
		RichText = rich == true,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 4), AutomaticSize = Enum.AutomaticSize.Y,
	}, cardBody)
	textEdge(l)
	return l
end

-- #9fb7c9 — свой оттенок метки и примечания, глуше синего #7fa8c9. Возьмёшь
-- один на всё — метки сравняются по весу со значениями, и строка перестанет
-- читаться слева направо.
local CARD_MUTED = Color3.fromRGB(159, 183, 201)

local cKind    = cardLine(1, 13, Map.BLUE_TEXT)
local cIncome  = cardLine(2, 13, Map.GOLD)
local cSources = cardLine(3, 12, CARD_MUTED, true)
local cPeople  = cardLine(4, 13, Map.LIGHT_BLUE, true)
local cDefense = cardLine(5, 13, Map.BLUE_TEXT, true)
local cAttack  = cardLine(6, 13, Map.SALMON)
local cNote    = cardLine(7, 12, CARD_MUTED)

-- ── подвал: кнопка «Плыть сюда» ──

local SAIL_H     = 32   -- поля 7 сверху и снизу плюс строка 14-го кегля
local SAIL_DROP  = 4    -- box-shadow 0 4px 0: на столько тень торчит из-под кнопки
local SAIL_PRESS = 2    -- нажатая кнопка уезжает вниз, просвет тени схлопывается до 2

local cardFoot = new("Frame", {
	LayoutOrder = 4, ZIndex = 13, BackgroundTransparency = 1, Visible = false,
	Size = UDim2.new(1, 0, 0, SAIL_H + 10),
}, card)
new("UIPadding", {
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, cardFoot)

--[[ ⚠️ ТЕНЬ КНОПКИ — ОТДЕЛЬНЫЙ ФРЕЙМ ПОД НЕЙ, ДРУГОЙ ТЕНИ В ROBLOX UI НЕТ.
     Он лежит на 4 пикселя ниже кнопки и при нажатии НЕ двигается: вниз едет
     сама кнопка, и видимый просвет схлопывается с 4 до 2 — ровно то, что в
     хендофе делает пара translateY(2px) + box-shadow 0 2px. Поедет тень вместе
     с кнопкой — нажатие перестанет читаться вовсе.
     Обёртка нужна потому, что кнопка обязана иметь возможность вылезти за свою
     строку: в списке карточки она заняла бы место вместе со сдвигом, и на
     каждое нажатие карточка дёргалась бы по высоте. ]]
local sailWrap = new("Frame", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 13,
}, cardFoot)
new("Frame", {
	Position = UDim2.fromOffset(0, SAIL_DROP), Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
	BorderSizePixel = 0, ZIndex = 13,
}, sailWrap)

local sailBtn = new("TextButton", {
	ZIndex = 14, AutoButtonColor = false, BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 1, 0),
	Position = UDim2.fromOffset(0, 0),
	Font = Map.FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Text = "Плыть сюда",
	-- Тень текста — старая TextStroke*: UIStroke на кнопке уже занят чёрной
	-- рамкой 3 px, а вторым его вешать нельзя (движок применит только один).
	TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0,
}, sailWrap)

-- Фон белый под градиентом: UIGradient множится на BackgroundColor3, и зелёный
-- на зелёном ушёл бы в болото. Средняя точка 0.55 — из хендофа.
local SAIL_TOP = Map.GREEN
local SAIL_MID = Color3.fromRGB(47, 163, 47)
local SAIL_BOT = Color3.fromRGB(31, 125, 31)

local function sailSeq(k)
	local function lit(c)
		return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lit(SAIL_TOP)),
		ColorSequenceKeypoint.new(0.55, lit(SAIL_MID)),
		ColorSequenceKeypoint.new(1, lit(SAIL_BOT)),
	})
end

--[[ ⚠️ НАВЕДЕНИЕ СВЕТЛИТ ГРАДИЕНТ, А НЕ ФОН КНОПКИ.
     В хендофе это filter: brightness(1.12), а фильтров у 2D UI Roblox нет
     вовсе. Красить BackgroundColor3 нельзя: он белый и работает множителем
     градиента — тронешь его, и зелень уедет в другой оттенок целиком. Поэтому
     держим вторую готовую тройку цветов, умноженную на те же 1.12. ]]
local SAIL_NORMAL, SAIL_HOVER = sailSeq(1), sailSeq(1.12)
local sailGrad = new("UIGradient", { Rotation = 90, Color = SAIL_NORMAL }, sailBtn)
stroke(sailBtn, 3)

sailBtn.MouseEnter:Connect(function()
	sailGrad.Color = SAIL_HOVER
end)
-- Уход курсора снимает и подсветку, и нажатие: палец может уехать с кнопки, так
-- и не отпустив её, и без этого сброса кнопка осталась бы вдавленной навсегда.
sailBtn.MouseLeave:Connect(function()
	sailGrad.Color = SAIL_NORMAL
	sailBtn.Position = UDim2.fromOffset(0, 0)
end)
sailBtn.MouseButton1Down:Connect(function()
	sailBtn.Position = UDim2.fromOffset(0, SAIL_PRESS)
end)
sailBtn.MouseButton1Up:Connect(function()
	sailBtn.Position = UDim2.fromOffset(0, 0)
end)

-- ═══════════ лист карты ═══════════

local parchment = new("Frame", {
	Name = "Parchment", LayoutOrder = 2, BackgroundColor3 = Map.PARCHMENT_MID,
	BorderSizePixel = 0, ZIndex = 2, Size = UDim2.fromOffset(600, 400),
}, stack)
stroke(parchment, 3)
-- Угол и средняя точка живут в MapDefs: и бумага, и вода, и острова светятся с
-- одной стороны, иначе лист расслаивается на три несвязанных пятна.
new("UIGradient", {
	Rotation = Map.PARCHMENT_ROTATION,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Map.PARCHMENT_TOP),
		ColorSequenceKeypoint.new(Map.PARCHMENT_MID_POINT, Map.PARCHMENT_MID),
		ColorSequenceKeypoint.new(1, Map.PARCHMENT_BOT),
	}),
}, parchment)

-- океан: заливка плюс градиент глубины
-- ⚠️ Active = true: РАМКА ДОЛЖНА СЪЕДАТЬ КАСАНИЕ.
-- Обычный Frame касание НЕ перехватывает, и на телефоне тот же палец, которым
-- листают карту, доезжал до управления камерой — карта ехала, и мир за ней
-- поворачивался вместе с ней. Active заставляет рамку забрать касание себе.
local ocean = new("Frame", {
	Name = "Ocean", BackgroundColor3 = Map.OCEAN, BorderSizePixel = 0,
	Position = UDim2.fromOffset(Map.INSET, Map.INSET),
	Size = UDim2.new(1, -Map.INSET * 2, 1, -Map.INSET * 2),
	ClipsDescendants = true, ZIndex = 3, Active = true,
}, parchment)
stroke(ocean, 3)
-- Градиент воды: UIGradient красит только сам фрейм, до островов и плота внутри
-- он не достаёт, поэтому мелководье можно рисовать здесь, ничего не перекрашивая.
new("UIGradient", {
	Rotation = Map.OCEAN_ROTATION,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Map.OCEAN_TOP),
		ColorSequenceKeypoint.new(Map.OCEAN_MID_POINT, Map.OCEAN),
		ColorSequenceKeypoint.new(1, Map.OCEAN_BOT),
	}),
}, ocean)

-- мир: точка 1×1 в центре океана, дети висят на ней по своим координатам.
-- Панорама двигает эту точку, поэтому обрезкой занимается океан, а не мир.
local world = new("Frame", {
	Name = "World", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1, 1),
	BackgroundTransparency = 1, ZIndex = 3,
}, ocean)

-- ── координатная сетка ──

--[[ ⚠️ ЛИНИЙ КОНЕЧНОЕ ЧИСЛО, А СЕТКА БЕСКОНЕЧНАЯ.
     Океан панорамируется без границ, и честно нарисованная сетка кончилась бы
     через пару экранов — дальше вода пустая. Поэтому линий ровно столько,
     чтобы накрыть океан плюс пара клеток запаса, а весь их узел каждый кадр
     подтягивается к целому числу шагов от панорамы (см. RenderStepped ниже).
     Сдвиг кратен шагу, поэтому глазу подмену не видно: линия встаёт ровно туда,
     где была бы следующая. Уберёшь подтяжку — сетка уедет вместе с миром и
     оставит голую воду по краям. ]]
local GRID_HALF_X = (Map.MAX_W - Map.INSET * 2) * 0.5 + Map.GRID_STEP * 2
local GRID_HALF_Y = (Map.MAX_H - Map.INSET * 2) * 0.5 + Map.GRID_STEP * 2
local GRID_NX = math.ceil(GRID_HALF_X / Map.GRID_STEP)
local GRID_NY = math.ceil(GRID_HALF_Y / Map.GRID_STEP)
local GRID_SPAN_X = (GRID_NX * 2 + 2) * Map.GRID_STEP
local GRID_SPAN_Y = (GRID_NY * 2 + 2) * Map.GRID_STEP

local gridHolder = new("Frame", {
	Name = "Grid", Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, ZIndex = 2,
}, world)

for k = -GRID_NX, GRID_NX do
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(k * Map.GRID_STEP, 0),
		Size = UDim2.fromOffset(Map.GRID_THICKNESS, GRID_SPAN_Y),
		BackgroundColor3 = Map.GRID, BackgroundTransparency = Map.GRID_ALPHA,
		BorderSizePixel = 0, ZIndex = 2,
	}, gridHolder)
end
for k = -GRID_NY, GRID_NY do
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, k * Map.GRID_STEP),
		Size = UDim2.fromOffset(GRID_SPAN_X, Map.GRID_THICKNESS),
		BackgroundColor3 = Map.GRID, BackgroundTransparency = Map.GRID_ALPHA,
		BorderSizePixel = 0, ZIndex = 2,
	}, gridHolder)
end

-- ── внутренняя тень по кромке воды ──

--[[ ⚠️ ЧЕСТНАЯ ЗАМЕНА box-shadow: inset — ЕГО В ROBLOX UI НЕТ ВОВСЕ.
     Четыре полосы вдоль кромок океана с градиентом прозрачности внутрь. От
     настоящей inset-тени отличается углами: там затемнение сходится по радиусу,
     здесь две полосы просто накладываются и угол получается чуть темнее. На
     42 пикселях это не читается.
     Полосы намеренно НЕ Active: обычный фрейм ввод не перехватывает, и палец
     по-прежнему проходит сквозь них к океану. Включишь Active — панорама
     перестанет тянуться у краёв листа, ровно там, где её и хватают. ]]
local SHADOW_W     = 42
local SHADOW_COLOR = Color3.fromRGB(6, 38, 50)
local SHADOW_ALPHA = 0.45   -- 1 − 0.55 из rgba(6,38,50,0.55)

local function edgeShadow(size, position, anchor, rotation, flip)
	local f = new("Frame", {
		Size = size, Position = position, AnchorPoint = anchor,
		BackgroundColor3 = SHADOW_COLOR, BorderSizePixel = 0, ZIndex = 9,
	}, ocean)
	local a, b = SHADOW_ALPHA, 1
	if flip then a, b = 1, SHADOW_ALPHA end
	new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, a),
			NumberSequenceKeypoint.new(1, b),
		}),
	}, f)
	return f
end

edgeShadow(UDim2.new(1, 0, 0, SHADOW_W), UDim2.new(),            Vector2.new(0, 0), 90, false)
edgeShadow(UDim2.new(1, 0, 0, SHADOW_W), UDim2.new(0, 0, 1, 0),  Vector2.new(0, 1), 90, true)
edgeShadow(UDim2.new(0, SHADOW_W, 1, 0), UDim2.new(),            Vector2.new(0, 0),  0, false)
edgeShadow(UDim2.new(0, SHADOW_W, 1, 0), UDim2.new(1, 0, 0, 0),  Vector2.new(1, 0),  0, true)

-- ── роза ветров ──

--[[ ⚠️ РОЗА ПРИБИТА К УГЛУ ВОДЫ, А НЕ К ПАНОРАМИРУЕМОМУ МИРУ.
     В прототипе она лежит внутри мира и уплывает вместе с картой; здесь это
     оформление листа. Уехавшая за кромку роза выглядит потерянной, а
     ClipsDescendants океана её просто срежет. Перевесишь на world — верни ей и
     координаты в пикселях мира, иначе она сядет в центр архипелага.
     Прозрачности заданы поштучно: в CSS вся роза гасится общим opacity 0.85,
     а в Roblox группового альфа-канала у обычного фрейма нет — числа ниже это
     0.85 уже перемножены на собственную альфу каждой детали. ]]
local COMPASS_LIGHT = Color3.fromRGB(240, 250, 252)

local compass = new("Frame", {
	Name = "Compass", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(74, 74),
	BackgroundTransparency = 1, ZIndex = 10,
}, ocean)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, compass)
new("UIStroke", {
	Thickness = 2, Color = COMPASS_LIGHT, Transparency = 0.53,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, compass)

-- Второе кольцо в прототипе пунктирное. Пунктирной обводки в Roblox нет —
-- берём сплошную, но тоньше и бледнее: так она остаётся вторым кольцом, а не
-- дублирует первое.
local ring2 = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1, ZIndex = 10,
}, compass)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring2)
new("UIStroke", {
	Thickness = 1.5, Color = COMPASS_LIGHT, Transparency = 0.66,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, ring2)

new("Frame", {   -- перекладина запад–восток
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(46, 2), BackgroundColor3 = COMPASS_LIGHT,
	BackgroundTransparency = 0.575, BorderSizePixel = 0, ZIndex = 10,
}, compass)

-- ⚠️ СТРЕЛКА — ИГЛА, А НЕ ТРЕУГОЛЬНИК.
-- Треугольник без картинки не собрать: UICorner скругляет углы, но не срезает
-- их. Игла со скруглённым концом говорит то же самое.

--[[ ⚠️ ИГЛА ПОКАЗЫВАЕТ КУРС ПЛОТА, А НЕ СЕВЕР.
     Север на этой карте всегда вверх — лист не вращается, — поэтому стрелка,
     намертво торчащая вверх, не сообщала игроку ровно ничего: плот идёт вбок,
     а «компас» смотрит прямо. Красный конец теперь показывает, КУДА ПЛОТ
     ФАКТИЧЕСКИ ИДЁТ, светлый — откуда пришёл; кольцо, перекладина и буква N
     остаются неподвижными и держат стороны света.
     ⚠️ Курс берётся из СМЕЩЕНИЯ плота, а не из его LookVector: у PrimaryPart
     плота оси развёрнуты, и «вперёд» у него смотрит вбок — стрелка врала бы
     на девяносто градусов.
     ⚠️ ВРАЩАЕТСЯ ОБОЙМА, А НЕ КАЖДАЯ ИГЛА. Rotation крутит объект вокруг его
     собственной середины, а не вокруг точки крепления: игла длиной 28 сидит
     серединой в четырнадцати пикселях от оси розы, и поворот уводил её от
     хаба вбок. На экране это выглядело как две отвалившиеся стрелки, смотрящие
     в разные стороны. Обойма — квадрат по центру розы, её середина совпадает
     с осью, поэтому дети поворачиваются именно вокруг оси и остаются на одной
     прямой. ]]
local needleWrap = new("Frame", {
	Name = "Needles", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(74, 74),
	BackgroundTransparency = 1, ZIndex = 11,
}, compass)
local northNeedle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(5, 28), BackgroundColor3 = Color3.fromRGB(226, 86, 66),
	BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = 11,
}, needleWrap)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, northNeedle)

local southNeedle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(5, 28), BackgroundColor3 = COMPASS_LIGHT,
	BackgroundTransparency = 0.49, BorderSizePixel = 0, ZIndex = 11,
}, needleWrap)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, southNeedle)

local hub = new("Frame", {   -- ось
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromRGB(245, 233, 198),
	BackgroundTransparency = 0.235, BorderSizePixel = 0, ZIndex = 12,
}, compass)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, hub)

-- Буква сидит НАД кольцом, а не на нём: у розы 74 px внешний диаметр, и надпись
-- поверх обводки читалась бы как царапина на кольце.
new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(16, 14), BackgroundTransparency = 1, ZIndex = 11,
	Font = Map.FONT, TextSize = 12, TextColor3 = Color3.fromRGB(245, 233, 198),
	TextTransparency = 0.19, Text = "N",
}, compass)


-- ═══════════ крестик ═══════════

--[[ ⚠️ КНОПКА ЗАКРЫТИЯ — ОБЩАЯ, СВОЕЙ ЗДЕСЬ БОЛЬШЕ НЕТ.
     Владелец потребовал один и тот же крестик во всех меню океана и назвал
     эталоном инвентарь, поэтому кнопка приходит из UITheme.closeButton, а не
     собирается на месте. Размер и посадка живут в модуле (UITheme.CLOSE_SIZE):
     дай меню право задавать их самому — и через месяц крестики опять разъедутся,
     как это уже было.
     Посадка тут обычная, правый верхний угол, поэтому position/anchorPoint не
     передаём: умолчание модуля и есть повторение инвентаря.
     Родитель — parchment (сама рама), а НЕ океан: у океана стоит
     ClipsDescendants, и кнопка у кромки была бы срезана.
     ZIndex 20 задан явно: на раме лежит океан (3) со своими тенями и розой (9,
     10, 12), и крестик должен оставаться выше них. ]]
local closeBtn = UITheme.closeButton({ parent = parchment, zIndex = 20 })

-- ═══════════ состояние ═══════════

local snap = nil          -- последний снимок с сервера
local selected = nil      -- id выбранного острова
local pan = Vector2.zero  -- смещение мира в пикселях ЛИСТА (не экрана)
local originX, originZ = 0, 0   -- центр мира: позиция плота при открытии
local isOpen = false

local nodes = {}          -- [id] = Frame острова
local outlines = {}       -- [id] = UIStroke песчаного блоба: им подсвечиваем выбор
-- ⚠️ УЗЕЛ ОСТРОВА СТРОИТСЯ ОДИН РАЗ, А СНАПШОТ ПРИХОДИТ РАЗ В СЕКУНДУ.
-- Без этой таблицы остров, который сервер только что открыл из тумана или отдал
-- игроку, так и остался бы серым: перестраивать узел ради смены двух цветов
-- дорого (это гало, изобаты, три слоя и бирки), поэтому каждый узел оставляет
-- здесь функцию «перекрасься под свежие данные».
local updaters = {}       -- [id] = function(isle) — перекраска узла под снапшот
-- Клик по узлу значит разное до и после захвата: обычно выбор острова, а у
-- погасшей метки — «забыть навсегда». Держим действие снаружи, чтобы не плодить
-- второе соединение Activated на том же кнопочном узле.
local ghostAction = {}    -- [id] = что делать по клику вместо выбора
local forgotten = {}      -- [id] = true: остров захвачен, заново его не строим
-- Активный курс целиком: замороженная дуга плюс пул фреймов-штрихов. Объявлен
-- здесь, а не в разделе «маршрут», потому что снимать курс приходится и захвату
-- острова, и открытию карты — то есть коду по обе стороны от него.
local route = nil
local raftDot = nil
local centred = false     -- центр мира уже взят с плота?
--[[ ⚠️ ПОСЛЕ ПРОТЯЖКИ КЛИК НЕ ЗАСЧИТЫВАЕТСЯ.
     Порог драга защищал клик от панорамы, но не наоборот: нажал на остров,
     протащил карту, отпустил палец над тем же островом — и открывалась карточка
     острова, который игрок вовсе не выбирал. Кнопка узла шлёт Activated по
     отпусканию, то есть уже после того, как мир проехал.
     Объявлено здесь, а не рядом с обработчиками панорамы: читает его клик по
     острову, который живёт выше по файлу. ]]
local suppressClick = false
local render              -- объявлен заранее: на него ссылается клик по острову

local function toMap(x, z)
	return Vector2.new((x - originX) * Map.WORLD_SCALE, (z - originZ) * Map.WORLD_SCALE)
end

--[[ ⚠️ КУРС МЕРЯЕТСЯ РЕДКИМИ ЗАМЕРАМИ, А НЕ КАЖДЫЙ КАДР.
     Между двумя кадрами плот проезжает сотые доли студа, и на таком плече
     дрожание физики больше самого движения — стрелку крутило бы во все
     стороны. За четверть секунды набегает уже заметное смещение, и направление
     считается уверенно. Порог отсекает стоянку: плот у берега качается на
     месте, и курса у него нет — тогда игла просто остаётся где была. ]]
local COMPASS_SAMPLE = 0.25   -- как часто обновляем стрелку, секунд
local COMPASS_MIN    = 0.6    -- меньше этого за замер — плот стоит, студов
local COMPASS_SMOOTH = 0.25   -- доля нового направления в старом
-- Порог по скорости: плот идёт около шести студов в секунду (RaftController.SPEED),
-- а качка на волне даёт доли студа. Полтора — уверенно выше качки и втрое ниже
-- хода, так что ни ложного курса на стоянке, ни потери настоящего.
local COMPASS_MIN_SPEED = 1.5

local raftModel = nil          -- модель плота в мире, ищем лениво
local lastSample = nil         -- Vector2 позиции плота в мире (X, Z)
local sampleAt = 0
local heading = Vector2.new(0, -1)   -- пока не поплыли — на север

-- Плот ищем ровно так же, как это делает сервер в MapSystem.raftPos: имя Raft,
-- иначе первая деталь Raft_Part. Разойдутся способы — компас начнёт показывать
-- курс не того объекта, что рисуется точкой на карте.
local function raftWorldXZ()
	if not (raftModel and raftModel.Parent) then
		raftModel = Workspace:FindFirstChild("Raft")
			or Workspace:FindFirstChild("Raft_Part", true)
	end
	if raftModel then
		local ok, cf = pcall(function() return raftModel:GetPivot() end)
		if ok then return Vector2.new(cf.Position.X, cf.Position.Z) end
	end
	-- плота в мире не нашли — берём точку из снапшота: она обновляется раз в
	-- секунду, для стрелки этого хватает
	if snap and snap.raft then return Vector2.new(snap.raft.x, snap.raft.z) end
	return nil
end

--[[ ⚠️ СНАЧАЛА СКОРОСТЬ, И ТОЛЬКО ПОТОМ ЗАМЕРЫ.
     Плот в этой игре — физическая сборка, и её AssemblyLinearVelocity уже
     содержит ровно то, что нам нужно: куда она едет ПРЯМО СЕЙЧАС, в мировых
     координатах. Это точнее замеров по позиции и отзывчивее их на четверть
     секунды. Скорость безопаснее и другим боком: у PrimaryPart плота развёрнуты
     оси, поэтому его LookVector брать нельзя, а вектор скорости к местным осям
     отношения не имеет.
     Замеры оставлены запасным путём: плот могут двигать и скриптом, ставя
     позицию напрямую, — тогда скорость нулевая, а курс есть. ]]
local function raftVelocityXZ()
	if not (raftModel and raftModel.Parent) then return nil end
	local part = raftModel:IsA("BasePart") and raftModel or raftModel.PrimaryPart
	if not part then return nil end
	local v = part.AssemblyLinearVelocity
	local flat = Vector2.new(v.X, v.Z)
	if flat.Magnitude < COMPASS_MIN_SPEED then return nil end
	return flat.Unit
end

local function aimNeedles()
	-- Rotation в Roblox идёт по часовой от «вверх», а ось Y экрана смотрит
	-- вниз: отсюда atan2(x, -y), а не привычный atan2(y, x).
	needleWrap.Rotation = math.deg(math.atan2(heading.X, -heading.Y))
end

local function aimAt(dir)
	local mixed = heading:Lerp(dir, COMPASS_SMOOTH)
	-- курс развернулся ровно на 180° — середина между старым и новым
	-- направлением вырождается в ноль, и Unit от неё даёт NaN
	if mixed.Magnitude > 1e-3 then heading = mixed.Unit else heading = dir end
	aimNeedles()
end

local function updateCompass()
	local now = os.clock()
	if now - sampleAt < COMPASS_SAMPLE then return end
	sampleAt = now

	local vel = raftVelocityXZ()
	if vel then
		aimAt(vel)
		lastSample = raftWorldXZ()
		return
	end

	local pos = raftWorldXZ()
	if not pos then return end
	if lastSample then
		local d = pos - lastSample
		if d.Magnitude >= COMPASS_MIN then aimAt(d.Unit) end
	end
	lastSample = pos
end


--[[ ⚠️ ЦЕНТРИРОВАНИЕ ЛЕРПИТ ПЕРЕМЕННУЮ ПАНОРАМЫ, А НЕ ТВИНИТ САМ ФРЕЙМ.
     Положение мира переписывается КАЖДЫЙ кадр в RenderStepped, и твин, повешенный
     на world, тут же затирался бы там: игрок увидел бы прыжок вместо обещанных
     0.6 с. Поэтому анимируется pan, а кадр остаётся единственным местом, где
     положение мира вообще задаётся.
     CSS-ное ease заменено на Quad InOut: у обоих разгон и торможение, а разницу
     кривых на 0.6 с глазом не поймать. ]]
local panAnim = nil   -- { from, to, at } — пока идёт доводка

local function centerOn(target)
	panAnim = { from = pan, to = target, at = os.clock() }
end

--[[ ⚠️ ПЕРЕВОД «ЭКРАННЫЕ ПИКСЕЛИ → ПИКСЕЛИ ЛИСТА».
     Всё, что нарисовано внутри ряда, живёт в его собственных пикселях: движок
     сам домножает их на оба UIScale, поэтому острова, маршрут и панорама при
     сжатии не разъезжаются. А вот ввод приходит в ЭКРАННЫХ пикселях, и его
     приходится делить руками — иначе на телефоне карта уезжает под пальцем
     быстрее самого пальца ровно во столько раз, во сколько сжат ряд. ]]
local function screenToSheet()
	return math.max(0.01, fitScale.Scale * openScale.Scale)
end

-- ═══════════ маршрут ═══════════

local routeHolder = new("Frame", {
	Name = "Route", BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1), ZIndex = 3,
}, world)

-- Штрих 10, разрыв 8, толщина 3 — stroke-dasharray из хендофа. Период 18 задаёт
-- разом и рисунок линии, и цену кадра: срежешь разрыв вдвое — вдвое больше
-- фреймов придётся двигать каждый кадр плавания.
local DASH_LEN = 10
local DASH_GAP = 8
local DASH_W   = 3

--[[ ⚠️ ПУНКТИР — ЭТО ОТДЕЛЬНЫЕ ФРЕЙМЫ, ЛИНИЙ В ROBLOX UI НЕТ ВОВСЕ.
     Штрихи переиспользуются из пула, а не создаются заново: курс
     перерисовывается каждый кадр плавания, и полсотни Instance.new по 60 раз в
     секунду движок переживёт, а сборщик мусора — нет. Пул умирает вместе с
     курсом, поэтому течь ему некуда. ]]
local function dashFrame(pool, i)
	local f = pool[i]
	if not f then
		f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3,
			BackgroundColor3 = Map.ROUTE, BackgroundTransparency = Map.ROUTE_ALPHA,
		}, routeHolder)
		pool[i] = f
	end
	return f
end

local function clearRoute()
	if not route then return end
	for _, f in ipairs(route.pool) do f:Destroy() end
	route = nil
end

-- Снять курс мягко. Уже гаснущий не трогаем: иначе смена выбора обрывала бы
-- затухание на полпути, и вместо плавного ухода игрок видел бы рывок.
local function dropRoute()
	if route and not route.fadeAt then clearRoute() end
end

local function fadeRoute()
	if route and not route.fadeAt then route.fadeAt = os.clock() end
end

--[[ ⚠️ ДУГА ЗАМОРАЖИВАЕТСЯ ОДИН РАЗ НА ОСТРОВ.
     Пересчитывать её каждый кадр «от плота до цели» нельзя: контрольная точка
     привязана к СЕРЕДИНЕ отрезка, и по мере приближения плота дуга спрямляется —
     линия виляла бы под плотом на каждом кадре. Поэтому from/ctrl/to пишутся
     здесь и дальше не меняются, а движение отыгрывает сплит (см. redrawRoute).
     Цель — кромка острова со стороны плота (радиус + 14), а не центр: иначе
     пунктир втыкается острову в середину и прячется под зеленью. ]]
local function ensureRoute(isle, raftAt, radius)
	if route and route.id == isle.id and not route.fadeAt then return end
	clearRoute()
	local to = toMap(isle.x, isle.z)
	local dir = to - raftAt
	local reach = radius + 14
	--[[ ⚠️ КУРС КОРОЧЕ ОДНОГО ШТРИХА НЕ СТРОИМ ВОВСЕ, И МЕРЯЕМ ДО dock, А НЕ ПОСЛЕ.
	     Плот у самого берега даёт остаток ≈ 0, и тогда t сразу равен единице: курс
	     рождался бы, гас за полсекунды, а следующий снимок сервера строил бы его
	     заново — вечное мигание пунктира под плотом.
	     ⚠️ Считать это по длине уже посчитанного отрезка (dock − плот) нельзя:
	     dock отмеряется от ЦЕНТРА острова назад к плоту на reach, и стоит плоту
	     подойти ближе reach — точка причала уезжает ЗА него. Длина при этом снова
	     набегает, а знак теряется, и пунктир уходил от плота ПРОЧЬ от острова.
	     Поэтому порог стоит на расстоянии до центра и ДО построения dock. ]]
	if dir.Magnitude <= reach + DASH_LEN then return end
	local dock = to - dir.Unit * reach
	local span = (dock - raftAt).Magnitude
	route = {
		id       = isle.id,
		from     = raftAt,
		to       = dock,
		ctrl     = Map.routeControl(raftAt, dock),
		span     = span,
		pool     = {},
		lastT    = -1,      -- заведомо невозможное значение: первый кадр всегда рисует
		lastFrom = nil,
		fadeAt   = nil,
	}
end

--[[ ⚠️ t СЧИТАЕТСЯ ПО ПОЛОЖЕНИЮ ПЛОТА, А НЕ ПО ТАЙМЕРУ.
     Сервер плот пока НЕ ведёт: MapSystem зовёт _G.SetRaftDestination, а такой
     функции в проекте нет вовсе, и после «Плыть сюда» плот в снапшоте остаётся
     на месте. Значит t честно держится на нуле и курс виден целиком. Появится
     тот, кто двигает плот, — анимация «съедания» заработает сама, без единой
     правки здесь.
     Таймер вместо расстояния брать нельзя: при любой задержке сети пунктир
     съедался бы впереди плота, и линия оторвалась бы от точки. Погрешность
     «расстояние по прямой вместо длины дуги» безобидна — начало остатка всё
     равно берётся из фактических координат плота, а t правит только кривизну
     хвоста, на 8 пикселях прогиба это не видно. ]]
local function routeT(raftAt)
	if route.span < 0.001 then return 1 end
	return math.clamp((raftAt - route.from).Magnitude / route.span, 0, 1)
end

--[[ ⚠️ СПЛИТ ДЕ КАСТЕЛЬЖО, А НЕ ВТОРАЯ КРИВАЯ.
     Хвост квадратичной Безье от t до конца — это снова квадратичная Безье с
     контрольной точкой c + (to − c) × t и началом в точке плота. Формула
     отрезает от СТАРОЙ дуги пройденный кусок, а не строит новую: сама линия
     стоит неподвижно, «съедается» только её начало. Поставишь тут
     Map.routeControl(плот, цель) — получишь дугу с другим прогибом, и весь
     оставшийся курс будет вилять на каждом кадре.
     Штрихи режем по длине полилинии: хорда в 10 пикселей на нашей дуге (прогиб
     не больше 8 на весь курс) от кривой не отличается, поэтому штрих прямой. ]]
local function redrawRoute(raftAt, t)
	local pool = route.pool
	local a = raftAt
	local c = route.ctrl + (route.to - route.ctrl) * t
	local b = route.to

	local steps = math.clamp(math.floor((b - a).Magnitude / 3), 6, 240)
	local pts, acc = table.create(steps + 1), table.create(steps + 1)
	pts[1], acc[1] = a, 0
	local total, prev = 0, a
	for i = 1, steps do
		local p = Map.bezier(a, c, b, i / steps)
		total += (p - prev).Magnitude
		pts[i + 1], acc[i + 1] = p, total
		prev = p
	end

	-- Курсор по полилинии намеренно не сбрасывается между штрихами: следующий
	-- штрих начинается дальше конца предыдущего, поэтому обход линейный. Сбросишь
	-- его в 1 — получишь квадрат по числу штрихов на каждом кадре плавания.
	local cursor = 1
	local function pointAt(s)
		while cursor < steps and acc[cursor + 1] < s do cursor += 1 end
		local s0, s1 = acc[cursor], acc[cursor + 1]
		if not s1 or s1 <= s0 then return pts[cursor] end
		return pts[cursor]:Lerp(pts[cursor + 1], (s - s0) / (s1 - s0))
	end

	local used = 0
	local s = 0
	while s < total do
		local p1 = pointAt(s)
		local p2 = pointAt(math.min(s + DASH_LEN, total))
		local seg = p2 - p1
		local len = seg.Magnitude
		if len > 0.5 then
			used += 1
			local f = dashFrame(pool, used)
			local mid = (p1 + p2) * 0.5
			f.Position = UDim2.fromOffset(mid.X, mid.Y)
			f.Size = UDim2.fromOffset(math.ceil(len), DASH_W)
			f.Rotation = math.deg(math.atan2(seg.Y, seg.X))
			f.Visible = true
		end
		s += DASH_LEN + DASH_GAP
	end
	-- Хвост пула прячем, а не удаляем: штрихов по мере съедания курса становится
	-- меньше, но стоит выбрать остров подальше — понадобятся все обратно.
	for i = used + 1, #pool do pool[i].Visible = false end
end

--[[ ⚠️ ГАСНЕТ ЗАМОРОЖЕННЫЙ ОСТАТОК, А НЕ ЖИВОЙ.
     На пороге прибытия хвост вырождается в точку, и гасить было бы уже нечего.
     Поэтому на t = 1 геометрию перестаём трогать вовсе и только уводим
     прозрачность штрихов в единицу за ROUTE_FADE. Продолжишь перерисовывать во
     время затухания — курс исчезнет мгновенно, рывком, вместо обещанных
     полсекунды. ]]
local function updateRoute(raftAt)
	if not route then return end

	if route.fadeAt then
		local k = math.clamp((os.clock() - route.fadeAt) / Map.ROUTE_FADE, 0, 1)
		-- линейно, как в хендофе: непрозрачность 0.85 → 0, то есть
		-- прозрачность ROUTE_ALPHA → 1
		local alpha = Map.ROUTE_ALPHA + (1 - Map.ROUTE_ALPHA) * k
		for _, f in ipairs(route.pool) do f.BackgroundTransparency = alpha end
		if k >= 1 then clearRoute() end
		return
	end

	local t = routeT(raftAt)
	if t >= 0.999 then
		fadeRoute()
		return
	end
	-- Плот стоит — перерисовывать нечего: штрихи лежат в координатах мира и
	-- уезжают вместе с ним при панораме. Без этой проверки карта каждый кадр
	-- пересобирала бы полсотни фреймов ради нулевого сдвига.
	if math.abs(t - route.lastT) < 0.0005
		and route.lastFrom and (raftAt - route.lastFrom).Magnitude < 0.25 then
		return
	end
	route.lastT, route.lastFrom = t, raftAt
	redrawRoute(raftAt, t)
end

-- ═══════════ отрисовка мира ═══════════

local function islandRadius(isle)
	return (Map.SIZE_PX[isle.size] or 44) * 0.5
end

--[[ ⚠️ ЦВЕТА ОСТРОВНОГО СЛОЯ СВЁРНУТЫ В ТАБЛИЦУ, И ЭТО НЕ КОСМЕТИКА.
     Luau разрешает не больше 200 локальных переменных на функцию, а тело
     скрипта — тоже функция. После переноса карты на новый хендофф их стало 199:
     любая следующая константа на верхнем уровне уронила бы компиляцию целиком,
     ошибкой «too many local variables», которую rojo build не ловит — она
     всплыла бы уже в Studio. Поля таблицы регистров не занимают.
     Живут здесь, а не в MapDefs: сервер не знает ни про бирки, ни про изобаты,
     ни про кораблики, и тащить их в общий модуль значит грузить его чужими
     оттенками. ]]
local ISLE = {
	shoalNear = Color3.fromRGB(150, 232, 240),   -- центр гало отмели
	shoalFar = Color3.fromRGB(120, 214, 226),   -- край гало
	isobath = Color3.fromRGB(232, 250, 252),   -- изобаты
	badgeEdge = Color3.fromRGB( 16,  50,  62),   -- #10323e
	tagTop = Color3.fromRGB(253, 243, 214),   -- #fdf3d6
	tagBot = Color3.fromRGB(240, 226, 186),   -- #f0e2ba
	tagEdge = Color3.fromRGB( 18,  50,  64),   -- #123240
	tagText = Color3.fromRGB( 22,  50,  61),   -- #16323d
	incomeBg = Color3.fromRGB( 27,  58,  42),   -- #1b3a2a
	incomeEdge = Color3.fromRGB( 15,  36,  25),   -- #0f2419
	attackBg = Color3.fromRGB(106,  18,  14),   -- #6a120e
	attackText = Color3.fromRGB(255, 214, 210),   -- #ffd6d2
	flagPole = Color3.fromRGB( 29,  29,  29),   -- #1d1d1d
	peakEdge = Color3.fromRGB( 46,  52,  44),   -- rgba(46,52,44,0.45)
	lagoonTop = Color3.fromRGB( 79, 208, 220),   -- #4fd0dc
	lagoonBot = Color3.fromRGB( 28, 127, 156),   -- #1c7f9c
	lagoonEdge = Color3.fromRGB( 20,  70,  88),   -- rgba(20,70,88,0.5)
	shipSail = Color3.fromRGB( 58,  58,  58),   -- #3a3a3a
	shipHull = Color3.fromRGB( 90,  58,  34),   -- #5a3a22
	ghostInk = Color3.fromRGB( 35,  50,  60),   -- метка «сигнал потерян»
	ghostText = Color3.fromRGB( 91, 109, 120),   -- #5b6d78
}

-- Обводка зелёного массива: в хендофе она своя на каждый тип и полупрозрачная
-- (alpha 0.5–0.55). Одна общая тёмная линия склеила бы железный остров с
-- нефтяным — у них и так близкая зелень.
local LAND_LINE = {
	forest = Color3.fromRGB(50, 78, 28),
	iron   = Color3.fromRGB(44, 58, 38),
	oil    = Color3.fromRGB(38, 58, 26),
}

local ATTACK_PULSE = 1.2    -- полный цикл пульсации кольца атаки
local ATTACK_TWEEN = TweenInfo.new(ATTACK_PULSE * 0.5,
	Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SHIP_BOB = 2.1        -- качка ближнего корабля, дальний идёт своим ритмом

--[[ ⚠️ КАПС СВОЙ, ПОТОМУ ЧТО string.upper КИРИЛЛИЦУ НЕ ПОДНИМАЕТ.
     Luau работает с байтами, а не с юникодом: «Зелёный атолл» после string.upper
     останется «Зелёный атолл», и бумажная бирка окажется единственным местом
     карты, где капса нет. Таблица сдвигов короткая: латиница, а–я и ё.
     Имя острова приходит из названия модели в Workspace, и там может лежать что
     угодно, поэтому разбор обёрнут в pcall: битая строка вернётся как есть. ]]
local function upperCode(code)
	if code >= 97 and code <= 122 then return code - 32 end
	if code >= 0x430 and code <= 0x44F then return code - 0x20 end
	if code == 0x451 then return 0x401 end
	return code
end

local function upperRu(text)
	local ok, res = pcall(function()
		local out = {}
		for _, code in utf8.codes(text) do
			table.insert(out, utf8.char(upperCode(code)))
		end
		return table.concat(out)
	end)
	return ok and res or text
end

-- Первая буква — по той же таблице сдвигов. Название типа лежит в MapDefs
-- строчным: модуль общий с сервером и хранит слово, а не готовую строку меню. В
-- карточке это слово начинает предложение («Лесной остров, средний»), и поднять
-- букву дешевле, чем завести в модуле второе написание того же типа — два
-- написания однажды разойдутся.
local function capFirst(text)
	local ok, res = pcall(function()
		local head = utf8.char(upperCode(utf8.codepoint(text, 1)))
		local second = utf8.offset(text, 2)
		return second and (head .. text:sub(second)) or head
	end)
	return ok and res or text
end

--[[ ⚠️ ВСЯ ВАРИАТИВНОСТЬ ОСТРОВА ВИСИТ НА SEED-Е, А НЕ НА math.random.
     Так было раньше: скругление песка бралось случайным числом, и остров менял
     форму каждый раз, когда узел пересобирался. Здесь seed — сумма кодов
     символов id, то есть остров всегда один и тот же от захода к заходу.
     Наши id — числа от сервера (1, 2, 3…), поэтому соседние seed отличаются на
     единицу; все делители ниже (2, 3, 4, 5, 7) на такой последовательности дают
     разные остатки, и два острова подряд одинаковыми не выйдут.

     ⚠️ ЧЕТЫРЁХ РАЗНЫХ РАДИУСОВ УГЛОВ В ROBLOX НЕТ.
     В хендофе форма задана CSS-ом вида '44% 56% 50% 50% / 55% 45% …' — это
     восемь чисел на четыре угла, и именно они делают кляксу кляксой. UICorner
     держит ОДИН радиус на все углы, второго способа скруглить фрейм нет вовсе.
     Честная замена — три независимых от типа рычага: поворот от seed
     (−33…+33 через 11°), разброс пропорций песка ±10% и сам радиус скругления.
     Клякса из этого не получится, но одинаковыми острова быть перестают, а
     наклон и вытянутость дают ровно то ощущение рисованности, ради которого
     кривые углы и были. Уберёшь любой из трёх рычагов — архипелаг снова
     превратится в россыпь одинаковых кружков. ]]
local function islandLook(isle)
	local text = tostring(isle.id)
	local seed = 0
	for i = 1, #text do seed += string.byte(text, i) end

	local small = isle.size == "small"
	local big   = isle.size == "large"
	return {
		spin       = (seed % 7) * 11 - 33,
		wobbleW    = 1 + ((seed % 5) - 2) * 0.05,
		wobbleH    = 1 + ((math.floor(seed / 3) % 5) - 2) * 0.05,
		sandRadius = 0.38 + (seed % 4) * 0.04,
		landRadius = 0.42 + ((seed + 1) % 4) * 0.03,
		peakRadius = 0.40 + ((seed + 2) % 4) * 0.04,
		-- отступ зелени внутрь песка: у малого острова пляж шире, иначе зелень
		-- съедает песок целиком и остров читается кляксой одного цвета
		landInset  = small and 0.22 or (big and 0.12 or 0.16),
		hasPeak    = (not small) and seed % 3 ~= 0,
		hasLagoon  = small or seed % 5 == 0,
		peakX      = (seed % 2 ~= 0) and 0.26 or 0.38,
		peakY      = (seed % 3 ~= 0) and 0.20 or 0.30,
		peakW      = big and 0.38 or 0.30,
		peakH      = big and 0.34 or 0.26,
	}
end

-- Слой острова: заливка плюс градиент «светлый → тёмный». Градиент тут не
-- украшение — три плоские заливки друг на друге читаются как аппликация, а
-- перепад светлоты внутри каждого слоя и даёт остров с высотой.
-- UIGradient красит только сам фрейм, поэтому слои-соседи друг друга не тонируют.
-- Градиент возвращаем наружу: по нему узел перекрашивается, когда сервер
-- открывает остров из тумана.
local function shaded(parent, props, radius, top, bot)
	local f = new("Frame", props, parent)
	new("UICorner", { CornerRadius = UDim.new(radius, 0) }, f)
	local grad = new("UIGradient", {
		Rotation = Map.ISLE_GRADIENT_ROTATION,
		Color = ColorSequence.new(top, bot),
	}, f)
	return f, grad
end

local function buildIsland(isle)
	local px  = Map.SIZE_PX[isle.size] or 44
	local L   = islandLook(isle)
	-- Цвета берём по типу острова: лесной зелёный, железный серо-зелёный с
	-- каменным пиком, нефтяной тёмный. Незнакомый тип падает на лесную палитру —
	-- остров хотя бы отрисуется, а не исчезнет с чёрной заливкой.
	local pal = Map.ISLAND_PALETTE[isle.type] or Map.ISLAND_PALETTE.forest
	local t   = Map.TYPES[isle.type] or Map.TYPES.forest

	local node = new("TextButton", {
		Name = "Isle_" .. tostring(isle.id), AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(px, px), BackgroundTransparency = 1, Text = "",
		AutoButtonColor = false, ZIndex = 4,
	}, world)

	--[[ ⚠️ ГАЛО ОТМЕЛИ — ТРИ КОЛЬЦА ВМЕСТО РАДИАЛЬНОГО ГРАДИЕНТА.
	     В хендофе это radial-gradient с тремя стопами (0.5 → 0.22 → прозрачность),
	     а UIGradient умеет только линейный: радиального в Roblox нет вовсе.
	     Кладём три круга друг на друга и подбираем прозрачности так, чтобы их
	     произведение дало нужную плотность на каждом радиусе: в центре
	     1 − 0.92·0.85·0.64 ≈ 0.5, на середине 1 − 0.92·0.85 ≈ 0.22, с краю ≈ 0.08.
	     Ступеньки между кругами видно только вплотную; поменяешь любое число —
	     считай остальные заново, поодиночке они смысла не имеют. ]]
	local function shoal(scale, transparency, color)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale), BackgroundColor3 = color,
			BackgroundTransparency = transparency, BorderSizePixel = 0, ZIndex = 1,
		}, node)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	end
	shoal(1.92, 0.92, ISLE.shoalFar)
	shoal(1.42, 0.85, ISLE.shoalFar)
	shoal(1.05, 0.64, ISLE.shoalNear)

	-- ⚠️ ИЗОБАТЫ СПЛОШНЫЕ: ПУНКТИРНОЙ ОБВОДКИ В ROBLOX НЕТ.
	-- В хендофе внешняя точечная (alpha 0.45), внутренняя штриховая (0.30).
	-- Рисовать их точками — это десятки фреймов на остров, а их тут девять и
	-- больше; берём сплошные кольца с теми же альфами. Разница читается как
	-- «линия чуть плотнее», а не как другой элемент.
	local function isobath(scale, transparency)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale), BackgroundTransparency = 1, ZIndex = 2,
		}, node)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		new("UIStroke", {
			Thickness = 2, Color = ISLE.isobath, Transparency = transparency,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, f)
	end
	isobath(1.52, 0.55)
	isobath(1.26, 0.7)

	-- ⚠️ КОЛЬЦО АТАКИ ПУЛЬСИРУЕТ РАЗМЕРОМ, А НЕ БЕГУЩИМ ПУНКТИРОМ.
	-- В прототипе оно красное штриховое и «дышит» scale 1 → 1.12 с падением
	-- непрозрачности. Штрихов у нас нет, поэтому вся тревога держится на пульсе:
	-- уберёшь его — останется просто красный ободок, неотличимый от подсветки
	-- выбора, и игрок перестанет замечать, что остров под атакой.
	local attackRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.52, 1.52), BackgroundTransparency = 1,
		ZIndex = 3, Visible = false,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, attackRing)
	local attackStroke = new("UIStroke", {
		Thickness = 3, Color = Map.RED, Transparency = 0.05,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, attackRing)
	local attackScale = new("UIScale", { Scale = 1 }, attackRing)

	-- песок: единственный слой, который крутится. Бейдж, флажок и бирки — соседи
	-- по узлу, а не дети песка, иначе буква на бейдже завалилась бы вместе с ним.
	local sand, sandGrad = shaded(node, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.round(px * L.wobbleW), math.round(px * L.wobbleH)),
		BackgroundColor3 = pal.sandTop, BorderSizePixel = 0, ZIndex = 4,
		Rotation = L.spin,
	}, L.sandRadius, pal.sandTop, pal.sandBot)
	outlines[isle.id] = stroke(sand, 3, Map.ISLE_EDGE)

	local landSpan = 1 - L.landInset * 2
	local land, landGrad = shaded(sand, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(landSpan, landSpan), BackgroundColor3 = pal.landTop,
		BorderSizePixel = 0, ZIndex = 5,
	}, L.landRadius, pal.landTop, pal.landBot)
	local landStroke = new("UIStroke", {
		Thickness = 2, Transparency = 0.48,
		Color = LAND_LINE[isle.type] or LAND_LINE.forest,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, land)

	-- Пик и лагуна — дети песка: они должны заваливаться вместе с островом,
	-- иначе скала съезжает с берега при повороте.
	local peak, peakGrad
	if L.hasPeak then
		peak, peakGrad = shaded(sand, {
			Position = UDim2.fromScale(L.peakX, L.peakY),
			Size = UDim2.fromScale(L.peakW, L.peakH),
			BackgroundColor3 = pal.peakTop, BorderSizePixel = 0, ZIndex = 6,
		}, L.peakRadius, pal.peakTop, pal.peakBot)
		new("UIStroke", {
			Thickness = 2, Color = ISLE.peakEdge, Transparency = 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, peak)
	end

	-- Лагуна в хендофе залита радиальным градиентом от бирюзы к глубокой воде.
	-- Радиального нет — берём линейный под тем же углом, что и остальные слои:
	-- на 12 пикселях воды разница между «светлеет из центра» и «светлеет сверху»
	-- не видна, а свет по всему острову остаётся с одной стороны.
	local lagoon, lagoonGrad
	if L.hasLagoon then
		lagoon, lagoonGrad = shaded(sand, {
			Position = UDim2.fromScale(0.36, 0.40), Size = UDim2.fromScale(0.30, 0.26),
			BackgroundColor3 = ISLE.lagoonTop, BorderSizePixel = 0, ZIndex = 6,
		}, 0.5, ISLE.lagoonTop, ISLE.lagoonBot)
		new("UIStroke", {
			Thickness = 2, Color = ISLE.lagoonEdge, Transparency = 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, lagoon)
	end

	-- ⚠️ БЕЙДЖ СВЕШИВАЕТСЯ ЗА УГОЛ УЗЛА НА 8 ПИКСЕЛЕЙ — ЭТО НЕ ОПЕЧАТКА.
	-- Так он не наезжает на зелень и читается даже на самом мелком острове.
	-- Тень буквы — старая TextStroke*, а не второй UIStroke: на объекте работает
	-- ровно один UIStroke, и он уже занят рамкой бейджа.
	local badge = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 8, 1, 8),
		Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0, ZIndex = 7,
		BackgroundColor3 = t.color, Font = Map.FONT, TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1), Text = t.letter,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(0, 7) }, badge)
	stroke(badge, 2.5, ISLE.badgeEdge)

	-- ⚠️ ВЫМПЕЛ — ПРЯМОУГОЛЬНИК СО СКРУГЛЕНИЕМ, А НЕ ТРЕУГОЛЬНИК.
	-- В CSS он собран из border-ов: 12 px золота и два прозрачных клина по 4.5.
	-- Скошенных углов Roblox не умеет вовсе (UICorner скругляет, но не срезает),
	-- а картинку добавить нельзя — новый rbxassetid не выдумать. Флажок остаётся
	-- узнаваемым: тонкое чёрное древко плюс золотое полотнище справа от него.
	local flagPole = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(2.5, 18), BackgroundColor3 = ISLE.flagPole,
		BorderSizePixel = 0, ZIndex = 7, Visible = false,
	}, node)
	local pennant = new("Frame", {
		Position = UDim2.new(0, 2.5, 0, 0), Size = UDim2.fromOffset(12, 9),
		BackgroundColor3 = Map.GOLD, BorderSizePixel = 0, ZIndex = 7,
	}, flagPole)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, pennant)

	-- ⚠️ ПОДПИСИ СТОЯТ КОЛОНКОЙ, ВЫСОТУ СЧИТАЕТ UIListLayout.
	-- Раньше название и чип дохода висели на своих отступах от низа узла (1,2 и
	-- 1,18), и стоило добавить третью строку — плашку атаки — как числа пришлось
	-- бы пересчитывать вручную на каждый случай. Здесь порядок задан LayoutOrder,
	-- а скрытая строка просто не занимает места.
	local labels = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, ZIndex = 7,
	}, node)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 3),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, labels)

	local function plate(order, bg, edge, textColor, size, padY, padX)
		local l = new("TextLabel", {
			LayoutOrder = order, Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY, BorderSizePixel = 0,
			BackgroundColor3 = bg, Font = Map.FONT, TextSize = size,
			TextColor3 = textColor, Text = "", ZIndex = 7,
		}, labels)
		new("UIPadding", {
			PaddingTop = UDim.new(0, padY), PaddingBottom = UDim.new(0, padY),
			PaddingLeft = UDim.new(0, padX), PaddingRight = UDim.new(0, padX),
		}, l)
		new("UICorner", { CornerRadius = UDim.new(0, order == 1 and 3 or 4) }, l)
		stroke(l, 2, edge)
		return l
	end

	-- Бумажная бирка названия: светлая, чтобы читаться на тёмной воде, и
	-- единственный элемент острова с бумажной палитрой — она связывает остров с
	-- листом карты. Тени 0 2px 0 под ней нет: жёсткая тень в Roblox — это
	-- фрейм-двойник ровно того же размера, а размер бирки считает AutomaticSize
	-- по тексту, и держать двойника в синхроне пришлось бы каждый кадр.
	-- Межбуквенного интервала 0.4 px в TextLabel тоже нет.
	-- UIGradient множится и на текст, но обе точки бумаги почти белые (0.99 и
	-- 0.94), и тёмная надпись от этого уходит на пару единиц — не видно. Возьмёшь
	-- для бирки контрастный градиент — текст потащит его цвет за собой.
	local nameTag = plate(1, ISLE.tagTop, ISLE.tagEdge, ISLE.tagText, 12, 2, 10)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ISLE.tagTop, ISLE.tagBot) }, nameTag)

	local incomeTag = plate(2, ISLE.incomeBg, ISLE.incomeEdge, Map.GOLD, 11, 1, 8)
	incomeTag.Visible = false
	local attackTag = plate(3, ISLE.attackBg, Map.RED, ISLE.attackText, 11, 1, 8)
	attackTag.Visible = false

	--[[ ⚠️ КОРАБЛИКИ СТРОЯТСЯ ТОЛЬКО ПРИ ПЕРВОЙ АТАКЕ.
	     Сервер поле attack не заполняет, и построй мы их сразу — на карте висели
	     бы четыре мёртвых фрейма и две вечные корутины качки на каждый остров.
	     Парус тут прямоугольный: треугольник без картинки не собрать, а мачта
	     одной палочкой читается как обломок, а не как корабль. ]]
	local ships = nil
	local function buildShips()
		local made = {}
		local function ship(pos, hullW, hullH, sailW, sailH, period, wait0)
			local body = new("Frame", {
				Position = pos, Size = UDim2.fromOffset(hullW, hullH + sailH),
				BackgroundTransparency = 1, ZIndex = 3, Visible = false,
			}, node)
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(sailW, sailH), BackgroundColor3 = ISLE.shipSail,
				BorderSizePixel = 0, ZIndex = 3,
			}, body)
			local hull = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(hullW, hullH), BackgroundColor3 = ISLE.shipHull,
				BorderSizePixel = 0, ZIndex = 3,
			}, body)
			-- корпус в хендофе скруглён только снизу; UICorner так не умеет, и
			-- на 9 пикселях пилюля от лодки почти не отличается
			new("UICorner", { CornerRadius = UDim.new(0, math.floor(hullH * 0.9)) }, hull)
			stroke(hull, 2)
			-- качка: 4 пикселя вверх и наклон −2…+2, туда-обратно
			local up = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset - 4)
			task.spawn(function()
				if wait0 > 0 then task.wait(wait0) end
				local info = TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				while body.Parent do
					if body.Visible then
						TweenService:Create(body, info, { Position = up, Rotation = 2 }):Play()
					end
					task.wait(period)
					if body.Visible then
						TweenService:Create(body, info, { Position = pos, Rotation = -2 }):Play()
					end
					task.wait(period)
				end
			end)
			table.insert(made, body)
		end
		ship(UDim2.new(-0.62, 0, 0.04, 0), 26, 9, 10, 14, SHIP_BOB, 0)
		ship(UDim2.new( 1.02, 0, 0.58, 0), 22, 8,  8, 12, SHIP_BOB - 0.3, 0.4)
		return made
	end

	--[[ ⚠️ ВЕТКА АТАКИ ЖИВАЯ, НО СЕРВЕР ЕЁ НЕ ЗАЖИГАЕТ.
	     В снапшоте MapSystem поле attack всегда nil: событий атаки там пока нет
	     вовсе. Поэтому здесь ровно одна проверка на число — придёт поле, ветка
	     заработает сама, а до тех пор кольцо, плашка и кораблики просто скрыты.
	     Выдумывать мощность атаки на клиенте нельзя: цифра разошлась бы с той,
	     что однажды посчитает сервер. ]]
	local attackOn = false
	local pulsing  = false
	local function setAttack(power)
		local on = typeof(power) == "number" and power > 0
		attackOn = on
		attackRing.Visible = on
		attackTag.Visible = on
		if on then
			attackTag.Text = ("Атака: %d"):format(power)
			if not ships then ships = buildShips() end
		end
		if ships then
			for _, body in ipairs(ships) do body.Visible = on end
		end
		-- Кольцо возвращаем в исходное состояние руками: корутина пульса
		-- заканчивает текущий полуцикл и выходит, оставляя scale на 1.12. В
		-- следующую атаку оно вспыхнуло бы уже раздутым.
		if not on then
			attackScale.Scale = 1
			attackStroke.Transparency = 0.05
		end
		if on and not pulsing then
			pulsing = true
			task.spawn(function()
				while node.Parent and attackOn do
					TweenService:Create(attackScale, ATTACK_TWEEN, { Scale = 1.12 }):Play()
					TweenService:Create(attackStroke, ATTACK_TWEEN, { Transparency = 0.5 }):Play()
					task.wait(ATTACK_PULSE * 0.5)
					TweenService:Create(attackScale, ATTACK_TWEEN, { Scale = 1 }):Play()
					TweenService:Create(attackStroke, ATTACK_TWEEN, { Transparency = 0.05 }):Play()
					task.wait(ATTACK_PULSE * 0.5)
				end
				pulsing = false
			end)
		end
	end

	--[[ ⚠️ ПОД ТУМАНОМ ТИП НЕ ПРОСВЕЧИВАЕТ.
	     Слои разводим одной светлотой: дай неизученному острову его палитру — и
	     игрок прочитает тип по цвету, хотя сервер его ещё не открывал. Гасим и
	     лагуну: бирюза на сером выдаёт остров ярче любой зелени. Настоящее
	     обесцвечивание (filter: grayscale) в Roblox недостижимо — фильтров у 2D
	     UI нет, поэтому серый подставляется цветом, а не считается из палитры. ]]
	local function update(cur)
		local seen = cur.seen == true
		local mine = cur.owned == true and seen

		local white = Color3.new(1, 1, 1)
		local sandA, sandB = pal.sandTop, pal.sandBot
		local landA, landB = pal.landTop, pal.landBot
		local peakA, peakB = pal.peakTop, pal.peakBot
		local lagA,  lagB  = ISLE.lagoonTop, ISLE.lagoonBot
		if not seen then
			sandA, sandB = Map.FOG, Map.FOG
			landA, landB = Map.FOG:Lerp(white, 0.1), Map.FOG:Lerp(white, 0.1)
			peakA, peakB = Map.FOG:Lerp(white, 0.2), Map.FOG:Lerp(white, 0.2)
			lagA,  lagB  = Map.FOG:Lerp(white, 0.3), Map.FOG:Lerp(white, 0.3)
		end
		sand.BackgroundColor3 = sandA
		sandGrad.Color = ColorSequence.new(sandA, sandB)
		land.BackgroundColor3 = landA
		landGrad.Color = ColorSequence.new(landA, landB)
		landStroke.Transparency = seen and 0.48 or 0.75
		if peak then
			peak.BackgroundColor3 = peakA
			peakGrad.Color = ColorSequence.new(peakA, peakB)
		end
		if lagoon then
			lagoon.BackgroundColor3 = lagA
			lagoonGrad.Color = ColorSequence.new(lagA, lagB)
		end

		badge.BackgroundColor3 = seen and t.color or Map.FOG
		badge.Text = seen and t.letter or "?"

		-- Настоящее имя под туманом не показываем, но бирку оставляем: без неё
		-- пропадает и якорь для взгляда, и третья строка колонки подписей,
		-- а остров превращается в безымянное пятно, по которому неясно, кликать
		-- ли вообще. В прототипе на бирке ровно тот же текст.
		nameTag.Text = upperRu(seen and cur.name or "Неизвестный остров")

		flagPole.Visible = mine
		-- ⚠️ Плашка «+N/мин» над островом убрана по той же причине, что и строки
		-- дохода в карточке: остров ничего не приносит, показывать нечего. Флажок
		-- владения остаётся — он говорит правду.
		incomeTag.Visible = false

		setAttack(seen and cur.attack or nil)
	end
	update(isle)
	updaters[isle.id] = update

	node.Activated:Connect(function()
		-- палец приехал сюда после протяжки карты — это не выбор острова
		if suppressClick then return end
		-- у погасшего острова клик значит «забыть», а не «выбрать»
		local act = ghostAction[isle.id]
		if act then act(); return end
		selected = isle.id
		render()
	end)
	return node
end

-- ── плот ──
-- Своя зелень, а не Map.GREEN: та отвечает за статус «ваш остров» в тексте, и
-- связывать её с точкой плота значит однажды перекрасить одно, поправив другое.
-- Свёрнуто в таблицу по той же причине, что и ISLE выше: предел в 200 локалей.
local RAFT = {
	dot = 20,   -- диаметр точки
	halo = Color3.fromRGB( 78, 217,  78),   -- rgba(78,217,78,·): гало и кольцо
	edge = Color3.fromRGB( 13,  43,  28),   -- #0d2b1c
	light = Color3.fromRGB(182, 255, 156),   -- #b6ff9c
	mid = Color3.fromRGB( 78, 217,  78),   -- #4ed94e
	dark = Color3.fromRGB( 35, 132,  43),   -- #23842b
	text = Color3.fromRGB(141, 250, 125),   -- #8dfa7d
	drop = Color3.fromRGB(  6,  38,  50),   -- rgba(6,38,50,0.45), подложка
	ringPx = 26,
	ringFrom = 0.6,
	ringTo = 2.4,
	pulse = 1.8,
}

-- Кольцо 26 px внешнего диаметра, 0.6 → 2.4 за 1.8 с. Конечный размер (62 px)
-- ровно втрое больше точки: сожмёшь его — пульс потеряется под самой точкой,
-- растянешь — волна дотянется до бирки и будет резать её пополам.

--[[ ⚠️ ПЛОТ СОБРАН ИЗ ЧЕТЫРЁХ КРУГОВ, И ЛИШНИХ СРЕДИ НИХ НЕТ.
     В хендофе точка — один div: radial-gradient плюс две тени сразу,
     `0 0 0 4px rgba(78,217,78,0.25)` (гало) и `0 3px 0 rgba(6,38,50,0.45)`
     (жёсткая подложка). Ни теней, ни радиального градиента у Roblox UI нет
     вовсе, поэтому гало и подложка — отдельные круги ПОЗАДИ точки.

     ⚠️ ПОЗАДИ — ЗНАЧИТ СОСЕД ПО УЗЛУ, А НЕ РЕБЁНОК ТОЧКИ.
     При ZIndexBehavior.Sibling потомок рисуется ПОВЕРХ предка ВСЕГДА, каким бы
     ни был его ZIndex: ZIndex сравнивается только между соседями. Пока гало и
     подложка висели детьми самой точки, они ложились НА неё — зелёная плёнка и
     тёмный полумесяц поверх плота. Поэтому Raft теперь пустая обёртка ровно по
     размеру точки, а точка (dot) — такой же её ребёнок, как гало, кольцо и
     подложка, и порядок держит ZIndex среди них. Тот же приём уже стоит у тени
     кнопки «Плыть сюда»: тень — СОСЕД кнопки в sailWrap, а не её ребёнок.
     Вернёшь круги внутрь точки — плот снова превратится в зелёное пятно.
     Радиальный градиент заменён линейным под 45°: в хендофе блик смещён в
     верхний левый угол (circle at 34% 28%), и линейный свет с той же стороны
     читается так же — на 20 пикселях центр блика от края не отличить. ]]
local function buildRaft()
	-- ⚠️ ПОДЛОЖКА И ГАЛО МЕРЯЮТСЯ ОТ ТОЧКИ ВМЕСТЕ С РАМКОЙ, А НЕ ОТ ЕЁ SIZE.
	-- UIStroke в режиме Border рисуется НАРУЖУ границ объекта, поэтому точка
	-- Size = 20 занимает на воде 26 пикселей. Круги, посчитанные от голых 20,
	-- целиком прятались под этой рамкой: подложка со сдвигом 3 упиралась ровно в
	-- её нижнюю кромку, а гало 28 выглядывало на пиксель. В CSS обе тени тоже
	-- отмеряются от border-box, так что считаем от DISC.
	local EDGE = 3                        -- толщина рамки точки
	local DISC = RAFT.dot + EDGE * 2      -- видимый диаметр точки с рамкой

	local node = new("Frame", {
		Name = "Raft", AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(RAFT.dot, RAFT.dot), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 8,
	}, world)

	-- жёсткая подложка 0 3px 0: сдвинута вниз, потому что свет сверху
	local drop = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3),
		Size = UDim2.fromOffset(DISC, DISC), BackgroundColor3 = RAFT.drop,
		BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, drop)

	-- гало: тень-обод в 4 px вокруг точки, отсюда диаметр DISC + 4 × 2
	local halo = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DISC + 8, DISC + 8), BackgroundColor3 = RAFT.halo,
		BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 7,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)

	-- сама точка: последней по ZIndex среди соседей, поэтому лежит на гало,
	-- подложке и кольце. Фон белый: UIGradient МНОЖИТСЯ на BackgroundColor3, и
	-- зелёный по зелёному ушёл бы в болото — та же причина, что у «Плыть сюда».
	local dot = new("Frame", {
		Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RAFT.dot, RAFT.dot), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 8,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	new("UIGradient", {
		Rotation = 45,   -- свет из левого верхнего угла: CSS 135deg − 90
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RAFT.light),
			ColorSequenceKeypoint.new(0.52, RAFT.mid),
			ColorSequenceKeypoint.new(1, RAFT.dark),
		}),
	}, dot)
	-- ⚠️ РАМКА ТЁМНО-ЗЕЛЁНАЯ, А НЕ ЧЁРНАЯ (умолчание stroke).
	-- Чёрная сливала точку с обводками островов, и плот терялся среди них ровно
	-- тогда, когда стоял у берега — то есть чаще всего.
	stroke(dot, EDGE, RAFT.edge)

	--[[ ⚠️ ПУЛЬС РАСХОДИТСЯ СТРОГО ИЗ ЦЕНТРА ТОЧКИ.
	     Это отдельно оговорено в хендофе, потому что в прототипе кольцо сперва
	     расходилось из угла: у него стояло left/top 50% без translate(−50%,−50%),
	     и рост шёл вправо-вниз. Здесь центр держат AnchorPoint 0.5 вместе с
	     Position 0.5/0.5 — уберёшь якорь, и волна снова поедет из левого верхнего
	     угла плота.
	     Растёт именно UIScale, а не Size: он тянет за собой и толщину обводки,
	     как CSS-ный transform: scale() тянет border. Анимируешь Size — кольцо
	     останется ниткой в 3 px на диаметре в 62 и потеряется на воде. ]]
	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RAFT.ringPx, RAFT.ringPx), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 6,
	}, node)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	-- Прозрачность на старте — уже перемноженная: у кольца своя альфа 0.8
	-- (rgba(78,217,78,0.8)), а анимация ведёт его от 0.9 к 0, итого видно
	-- 0.8 × 0.9 = 0.72. Возьмёшь одно из двух чисел — кольцо станет либо ярче
	-- самой точки, либо невидимым на светлой отмели.
	local RING_START = 1 - 0.8 * 0.9
	local ringStroke = new("UIStroke", {
		Thickness = 3, Color = RAFT.halo, Transparency = RING_START,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, ring)
	local ringScale = new("UIScale", { Scale = RAFT.ringFrom }, ring)
	task.spawn(function()
		-- ease-out из CSS: волна выстреливает и замедляется у края
		local info = TweenInfo.new(RAFT.pulse, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		while ring.Parent do
			-- при закрытой карте пульс не нужен: два твина в 1.8 с стоят немного,
			-- но крутить их поверх выключенного ScreenGui незачем
			if not isOpen then task.wait(0.5) end
			ringScale.Scale = RAFT.ringFrom
			ringStroke.Transparency = RING_START
			TweenService:Create(ringScale, info, { Scale = RAFT.ringTo }):Play()
			TweenService:Create(ringStroke, info, { Transparency = 1 }):Play()
			task.wait(RAFT.pulse)
		end
	end)

	--[[ ⚠️ «НАШ ПЛОТ» — ПЛАШКА, А НЕ ГОЛЫЙ ТЕКСТ.
	     Светло-зелёные буквы прямо на воде тонули: #8dfa7d поверх #1c7f9c держит
	     контраст хуже, чем кажется, а на светлой отмели вокруг острова пропадал
	     совсем. Тёмный фон #1b3a2a с рамкой #0f2419 — ровно та же плашка, что у
	     дохода острова, поэтому подписи карты читаются одной семьёй.
	     Ширину считает AutomaticSize: задашь числом — плашка либо обрежет
	     надпись, либо повиснет пустым полем справа от неё. ]]
	local plate = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 7),
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = ISLE.incomeBg, BorderSizePixel = 0, ZIndex = 9,
		Font = Map.FONT, TextSize = 12, TextColor3 = RAFT.text, Text = "Наш плот",
	}, node)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9),
	}, plate)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, plate)
	-- Обводки текста тут нет намеренно: UIStroke на объекте работает ровно один,
	-- и он занят рамкой плашки — а без рамки плашка перестаёт быть плашкой.
	stroke(plate, 2, ISLE.incomeEdge)
	return node
end

-- ═══════════ сборка кадра ═══════════

local function isleById(id)
	if not snap then return nil end
	for _, isle in ipairs(snap.islands) do
		if isle.id == id then return isle end
	end
	return nil
end

-- Цвет статуса — из палитры хендофа, а не из цвета баннера: RED (#e14b4b) там
-- только обводка баннера атаки, текст же лососевый (#ff7a6a). Поставишь RED —
-- строка станет ядовитее заголовка и перетянет взгляд с названия острова.
-- Ветки «Захвачен пиратами» тут нет намеренно: снапшот отдаёт лишь owned, а
-- владельца-пирата в нём нет вовсе — выдуманный статус врал бы игроку.
local function statusOf(isle)
	if not isle.seen then return "Скрыт туманом", Map.FOG_TEXT end
	if isle.attack then return "ПОД АТАКОЙ!", Map.SALMON end
	if isle.owned then return "Ваш остров", Map.GREEN end
	return "Нейтральный", Map.NEUTRAL_TEXT
end

local SIZE_RU = { small = "малый", medium = "средний", large = "большой" }

-- ⚠️ В RichText-СТРОКИ ПОПАДАЮТ ТОЛЬКО НАШИ СЛОВА И ЧИСЛА СЕРВЕРА.
-- Разметку ломает любой «<» в подставленном тексте, а единственные данные с
-- вольным содержимым — имена островов — живут в шапке, где RichText выключен.
-- Понадобится подставить сюда имя — сперва экранируй «<».
local function labelled(label, value)
	return ('%s <font color="#e8f2f8">%s</font>'):format(label, value)
end

local function fillCard(isle)
	local raftAt = toMap(snap.raft.x, snap.raft.z)
	local at = toMap(isle.x, isle.z)

	cName.Text = isle.seen and isle.name or "Неизвестный остров"
	local status, color = statusOf(isle)
	cStatus.Text = status
	cStatus.TextColor3 = color

	-- Незнакомый тип падает на лесную палитру — как и сам узел острова: пусть
	-- строка соврёт про тип, чем карточка упадёт на nil и не покажет ничего.
	local t = Map.TYPES[isle.type] or Map.TYPES.forest
	cKind.Text = isle.seen
		and ("%s остров, %s"):format(capFirst(t.name), SIZE_RU[isle.size] or "неизвестный")
		or "???"
	--[[ ⚠️ ДОХОДА И «ЛЕСОПИЛКИ» В КАРТОЧКЕ НЕТ, ПОКА ИХ НЕТ В ИГРЕ.
	     Карточка обещала «Потенциальный доход: +6/мин» и «Приносит прибыль:
	     лесопилка ×3», а на острове не стоит ни одного здания и ни одна система
	     эти числа не начисляет: сервер считает их из размера острова
	     (SOURCES_BY_SIZE × INCOME_PER_SOURCE) — то есть это выдумка карты, а не
	     состояние мира. Владелец на это и указал.
	     Поля income и sources в снимке ОСТАВЛЕНЫ: появятся настоящие постройки —
	     вернуть строки будет нечего искать, они просто перестанут врать. ]]
	cIncome.Visible = false
	cSources.Visible = false

	--[[ ⚠️ СТРОКА ЖИТЕЛЕЙ СЕЙЧАС НЕ ЗАЖИГАЕТСЯ НИКОГДА, И ЭТО НЕ ЗАБЫТЫЙ КОД.
	     Снапшот MapSystem полей residents/residentsMax не отдаёт вовсе. Считать
	     их на клиенте нельзя: цифра разошлась бы с домами, которые заселяет
	     сервер, — поэтому строка скрыта целиком, а не показывает ноль. Придёт
	     поле — она зажжётся сама. Вместимость на этот случай берётся из MapDefs,
	     чтобы карточка и сервер считали её по одной таблице. ]]
	local pop = isle.seen and isle.residents or nil
	cPeople.Visible = typeof(pop) == "number"
	if cPeople.Visible then
		local cap = isle.residentsMax or Map.CAPACITY_BY_SIZE[isle.size]
		cPeople.Text = labelled("Жители:",
			cap and ("%d / %d"):format(pop, cap) or tostring(pop))
	end

	cDefense.Text = labelled("Защита:", isle.seen and tostring(isle.defense or 0) or "?")

	-- Мощность атаки показываем, только когда сервер её прислал: строки «Атака
	-- пиратов: 0» в хендофе нет, а ноль читался бы как «атака идёт, но слабая».
	local atk = isle.seen and isle.attack or nil
	cAttack.Visible = typeof(atk) == "number"
	if cAttack.Visible then cAttack.Text = ("Атака пиратов: %d"):format(atk) end

	-- ⚠️ К НЕИЗУЧЕННОМУ ОСТРОВУ КНОПКИ НЕТ ВОВСЕ.
	-- Хендоф: «добраться можно только вручную, по навигации». Скрытая кнопка,
	-- которая ругается при нажатии, — это не то же самое. Прячем весь подвал: у
	-- него свои поля, и без кнопки они оставили бы под карточкой пустую полосу.
	local moored = snap.mooredTo == isle.id
	-- ⚠️ БЕЗ ПРИЧАЛА КНОПКИ НЕТ ВОВСЕ.
	-- Сервер всё равно откажет, но кнопка, которая обещает рейс и каждый раз
	-- отвечает отказом, читается как поломка. Признак приходит снапшотом:
	-- решает по-прежнему сервер, клиент только не врёт заранее.
	local hasDock = snap.hasDock ~= false
	cardFoot.Visible = isle.seen and not moored and hasDock and not isle.near
	if not isle.seen then
		cNote.Text = "Остров не изучен — добраться можно только вручную, по навигации."
	elseif moored then
		cNote.Text = "Плот пришвартован у этого острова."
	elseif isle.near then
		-- рейс поставил бы плот ровно туда, где он и так стоит
		cNote.Text = "Плот и так у этого острова — плыть некуда."
	elseif not hasDock then
		cNote.Text = "Нужен причал с лодкой: скрафти его и поставь на плот."
	else
		cNote.Text = ""
		-- ⚠️ В СТУДАХ, А НЕ В ПИКСЕЛЯХ КАРТЫ: та же формула считает и на сервере,
		-- где никаких пикселей нет вовсе. Подставишь сюда at/raftAt — кнопка
		-- начнёт обещать одно, а сервер спишет другое.
		local cost = Map.sailCost(isle.x - snap.raft.x, isle.z - snap.raft.z)
		sailBtn.Text = ("Плыть сюда — %d нефти"):format(cost)
	end
	-- Пустое примечание прячем: невидимая строка не занимает места в списке, а
	-- видимая пустая оставила бы в карточке дыру в высоту строки.
	cNote.Visible = cNote.Text ~= ""

	-- ⚠️ КАРТОЧКА БОЛЬШЕ НИКУДА НЕ ЛЕТАЕТ.
	-- Раньше она открывалась внутри океана со стороны, противоположной острову, и
	-- считала свой X от ocean.AbsoluteSize — то есть от ЭКРАННОГО размера, который
	-- зависит от масштаба ряда. Теперь её место постоянное, четвёртым блоком в
	-- колонке: карточку не надо искать глазами, и один источник ошибок с
	-- масштабом исчез вместе с расчётом.
	card.Visible = true
end

-- ═══════════ список «Ваши владения» ═══════════

local OWNED_NAME  = Color3.fromRGB(232, 242, 248)   -- #e8f2f8
local OWNED_HOVER = 0.92                            -- rgba(255,255,255,0.08)

--[[ ⚠️ СТРОКИ ПЕРЕЖИВАЮТ СНИМОК, А НЕ ПЕРЕСОБИРАЮТСЯ ПОД НЕГО.
     Раньше список чистился целиком на каждый снапшот, то есть раз в секунду.
     Стоило игроку прокрутить его или занести палец над строкой — прокрутка
     возвращалась в начало, а нажатие уходило в уже уничтоженную кнопку и
     пропадало. Теперь строка живёт по ключу: приходят только новые, уходят
     только исчезнувшие, остальные меняют текст на месте — ровно так же, как это
     давно сделано для узлов островов.
     Ключ «isle:id» с приставкой не случаен: id островов — числа от сервера, и
     без приставки id 1 столкнулся бы с ключом плота, будь тот когда-нибудь
     числом.
     Действие клика лежит в поле go, а Activated подключён один раз при рождении
     строки: пересоединять его на каждый снимок значило бы копить соединения на
     одной и той же кнопке, и один клик отрабатывал бы десятками.
     ⚠️ ЛОКАЛЬ ЗОВЁТСЯ entry, А НЕ row: row выше — это весь ряд «колонка + лист».
     Затенишь его здесь — строка списка попробует стать всем экраном. ]]
local ownedRows = {}   -- [key] = { btn, name, tag, go }

local function buildOwnedRow(key, round, markColor)
	local btn = new("TextButton", {
		Name = "Row_" .. key, ZIndex = 10, AutoButtonColor = false,
		-- Фон белый, но полностью прозрачный: подсветка наведения только меняет
		-- прозрачность, и цвет ей менять уже не придётся.
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, Text = "", Size = UDim2.new(1, 0, 0, OWNED_ROW_H),
	}, ownedList)

	-- Флажок острова в хендофе — треугольный вымпел; треугольника без картинки
	-- не собрать, поэтому здесь золотая метка того же размера. Плот отличается
	-- от островов формой метки: круг против квадрата.
	local mark = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = markColor,
		BorderSizePixel = 0, ZIndex = 11,
	}, btn)
	if round then new("UICorner", { CornerRadius = UDim.new(1, 0) }, mark) end
	stroke(mark, 2)

	-- ⚠️ ИМЯ ОБРЕЗАЕТСЯ МНОГОТОЧИЕМ, А НЕ ПЕРЕНОСИТСЯ.
	-- Высота строки фиксированная (по ней считается высота всего списка), и
	-- перенос вылез бы за кромку. Ширина 1,-74 — это 30 слева под метку и 44
	-- справа под тег «+12»: сузишь запас, и длинный доход наедет на название.
	local nameLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0.5, 0),
		Size = UDim2.new(1, -74, 1, 0), BackgroundTransparency = 1, ZIndex = 11,
		Font = Map.FONT_BODY, TextSize = 13, TextColor3 = OWNED_NAME, Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, btn)
	textEdge(nameLbl, 1.5)

	local tagLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(40, 14), BackgroundTransparency = 1, ZIndex = 11,
		Font = Map.FONT, TextSize = 12, TextColor3 = Map.GOLD, Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, Visible = false,
	}, btn)
	textEdge(tagLbl, 1.5)

	-- Разделитель висит НА строке, по её нижней кромке: в отступе UIListLayout
	-- фрейму взяться неоткуда, а число строк меняется от снимка к снимку.
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 11,
	}, btn)

	local entry = { btn = btn, name = nameLbl, tag = tagLbl, go = nil }
	btn.MouseEnter:Connect(function() btn.BackgroundTransparency = OWNED_HOVER end)
	btn.MouseLeave:Connect(function() btn.BackgroundTransparency = 1 end)
	btn.Activated:Connect(function()
		if entry.go then entry.go() end
	end)
	ownedRows[key] = entry
	return entry
end

local function syncOwned()
	local live, order = {}, 0

	local function put(key, opts)
		order += 1
		live[key] = true
		local e = ownedRows[key] or buildOwnedRow(key, opts.round, opts.markColor)
		e.btn.LayoutOrder = order
		e.name.Text = opts.text
		e.name.TextColor3 = opts.color
		e.tag.Visible = opts.tag ~= nil
		if opts.tag then
			e.tag.Text = opts.tag
			e.tag.TextColor3 = opts.tagColor
		end
		-- Замыкание переписываем каждый снимок: внутри лежит остров ИЗ ЭТОГО
		-- снапшота, и старое звало бы центрирование на позапрошлые координаты.
		e.go = opts.onClick
	end

	put("raft", {
		round = true, markColor = Map.GREEN, color = Map.GREEN, text = "Наш плот",
		onClick = function()
			centerOn(-toMap(snap.raft.x, snap.raft.z))
		end,
	})
	for _, isle in ipairs(snap.islands) do
		if isle.owned then
			put("isle:" .. tostring(isle.id), {
				markColor = Map.GOLD, color = OWNED_NAME, text = isle.name,
				-- в теге остаётся только тревога: доход острова — выдумка карты
				tag = isle.attack and "!" or "",
				tagColor = isle.attack and Map.SALMON or Map.GOLD,
				onClick = function()
					selected = isle.id
					centerOn(-toMap(isle.x, isle.z))
					render()
				end,
			})
		end
	end

	for key, e in pairs(ownedRows) do
		if not live[key] then
			e.btn:Destroy()
			ownedRows[key] = nil
		end
	end

	ownedWantH = order * OWNED_ROW_H
	applyOwnedHeight()
end

render = function()
	if not snap then return end

	-- Острова: пересобираем только состав, положение двигаем каждый кадр, а
	-- содержимое узла обновляем на месте. Строить остров заново на каждый снимок
	-- нельзя: у него своя форма от seed, кораблики и корутина пульсации — узел
	-- моргал бы раз в секунду и терял бы анимации на полпути.
	local live = {}
	for _, isle in ipairs(snap.islands) do
		live[isle.id] = true
		-- захваченный остров сервер всё ещё присылает: он для него живой.
		-- Возвращать его на карту нельзя — метку «сигнал потерян» игрок уже убрал.
		if not forgotten[isle.id] then
			if not nodes[isle.id] then nodes[isle.id] = buildIsland(isle) end
			local refresh = updaters[isle.id]
			if refresh then refresh(isle) end
		end
	end
	for id, node in pairs(nodes) do
		if not live[id] then
			node:Destroy()
			nodes[id], outlines[id], updaters[id], ghostAction[id] = nil, nil, nil, nil
		end
	end
	if not raftDot then raftDot = buildRaft() end

	-- чипы
	-- ⚠️ ОБА ЧИПА СКРЫТЫ, А НЕ ОБНУЛЕНЫ.
	-- Суточные числа складываются из того же выдуманного дохода островов, что
	-- убран из карточки. Чип, который всегда показывает ноль, — это не честность,
	-- а недоделанный интерфейс: игрок ищет, чем его увеличить, и не находит.
	-- Появится настоящая добыча на островах — вернуть две строки.
	-- ⚠️ Тоже родителя: см. разбор у объявления чипов выше.
	chipOil.Parent.Visible = false
	chipProfit.Parent.Visible = false
	chipPeople.Text = ("Жители: %d"):format(snap.population)

	-- баннер атаки
	local underAttack = nil
	for _, isle in ipairs(snap.islands) do
		if isle.owned and isle.attack then underAttack = isle end
	end
	banner.Visible = underAttack ~= nil
	if underAttack then
		banner.Text = ("Остров «%s» под атакой! Мощность атаки: %d")
			:format(underAttack.name, underAttack.attack)
	end

	-- список владений: строки живут между снимками, см. syncOwned
	syncOwned()

	-- карточка и маршрут
	local isle = selected and isleById(selected)
	if isle then
		fillCard(isle)
		if isle.seen and snap.mooredTo ~= isle.id then
			-- Курс ставим только на новый остров: тот же ensureRoute вернёт
			-- готовую дугу, и она не дрогнет от прихода снимка.
			ensureRoute(isle, toMap(snap.raft.x, snap.raft.z), islandRadius(isle))
		elseif route and route.id == isle.id then
			-- Пришвартовались у цели: остаток гасим, а не срезаем. Сервер ставит
			-- mooredTo раньше, чем плот доедет до самой кромки, и обрыв линии на
			-- полпути читался бы как потеря курса.
			fadeRoute()
		else
			dropRoute()
		end
	else
		card.Visible = false
		dropRoute()
	end
end

-- положение объектов пересчитываем каждый кадр: панорама плавная, а острова и
-- плот могут ехать (плот двигается всегда)
RunService.RenderStepped:Connect(function()
	if not isOpen or not snap then return end

	-- Доводка панорамы идёт здесь же, до записи в world: pan — единственный
	-- источник положения мира, и подмешивать анимацию где-то ещё значит получить
	-- два хозяина у одной координаты.
	if panAnim then
		local k = math.clamp((os.clock() - panAnim.at) / Map.PAN_TIME, 0, 1)
		pan = panAnim.from:Lerp(panAnim.to,
			TweenService:GetValue(k, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
		if k >= 1 then panAnim = nil end
	end

	world.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)

	-- Сетка «догоняет» панораму целыми клетками: мир уже уехал на pan, а узел
	-- сетки внутри него откатывается назад на ближайшее кратное шагу. Остаток
	-- меньше клетки — он и создаёт видимое движение линий, а запас клеток по
	-- краям гарантирует, что пустой воды не покажется.
	local step = Map.GRID_STEP
	gridHolder.Position = UDim2.fromOffset(
		-math.round(pan.X / step) * step,
		-math.round(pan.Y / step) * step)

	for _, isle in ipairs(snap.islands) do
		local node = nodes[isle.id]
		if node then
			local p = toMap(isle.x, isle.z)
			node.Position = UDim2.fromOffset(p.X, p.Y)
			local out = outlines[isle.id]
			if out then
				out.Color = (selected == isle.id) and Map.GOLD or Map.ISLE_EDGE
			end
		end
	end
	updateCompass()
	if raftDot then
		local p = toMap(snap.raft.x, snap.raft.z)
		raftDot.Position = UDim2.fromOffset(p.X, p.Y)
		-- Курс догоняем здесь же и той же точкой: возьмёшь координаты плота
		-- отдельно (например, в своём соединении) — остаток отстанет от точки на
		-- кадр, и пунктир будет то отрываться от плота, то заезжать под него.
		updateRoute(p)
	end
end)

-- ═══════════ панорама ═══════════

local dragFrom, dragPan, dragging = nil, nil, false


ocean.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		-- Рука на карте отменяет доводку сразу, ещё до порога драга: иначе
		-- центрирование продолжало бы тянуть мир из-под пальца, а dragPan,
		-- снятый вот здесь, успел бы устареть на весь остаток пути.
		panAnim = nil
		dragFrom = Vector2.new(input.Position.X, input.Position.Y)
		dragPan = pan
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragFrom then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local now = Vector2.new(input.Position.X, input.Position.Y)
	local delta = now - dragFrom
	-- ⚠️ ПОРОГ СРАВНИВАЕМ ДО ДЕЛЕНИЯ НА МАСШТАБ.
	-- Дрожание руки — величина экранная, она не становится больше оттого, что
	-- карта сжата. Поделишь сначала — на телефоне порог вырастет в два раза, и
	-- короткие протяжки будут проглатываться как клики.
	if not dragging and delta.Magnitude < Map.DRAG_THRESHOLD then return end
	dragging = true
	-- океан бесконечный: границ нет намеренно
	pan = dragPan + delta / screenToSheet()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			suppressClick = true
			task.defer(function() suppressClick = false end)
		end
		dragFrom, dragPan = nil, nil
		dragging = false
	end
end)

-- ═══════════ открытие и закрытие ═══════════

--[[ ⚠️ РЯД ВСЕГДА ВЛЕЗАЕТ ЦЕЛИКОМ — ИНАЧЕ КОЛОНКА УХОДИТ ЗА КРАЙ ЭКРАНА.
     Лист по-прежнему берёт свои доли от экрана (0.62 × 0.70 из токенов), но
     рядом с ним теперь стоит колонка 268 плюс зазор 22, и на телефоне эта сумма
     шире экрана. Поэтому весь ряд дополнительно сжимается общим UIScale до тех
     пор, пока не влезет по ОБЕИМ сторонам. Считаем именно так, а не «по ширине»:
     доли по осям разные, и однажды поменяв SCREEN_FRAC_Y, легко получить лист,
     который влез по ширине и вылез сверху. ]]
local function fitScreen()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp then return end

	local sheetW = math.min(vp.X * Map.SCREEN_FRAC_X, Map.MAX_W)
	local sheetH = math.min(vp.Y * Map.SCREEN_FRAC_Y, Map.MAX_H)
	parchment.Size = UDim2.fromOffset(sheetW, sheetH)
	-- колонка ровно по высоте листа: в хендофе у неё max-height того же min(70vh, 740)
	columnBox.Size = UDim2.fromOffset(COLUMN_W, sheetH)

	local rowW = COLUMN_W + ROW_GAP + sheetW
	row.Size = UDim2.fromOffset(rowW, sheetH)

	local freeW = math.max(1, vp.X - SCREEN_PAD * 2)
	local freeH = math.max(1, vp.Y - SCREEN_PAD * 2)
	fitScale.Scale = math.clamp(math.min(freeW / rowW, freeH / sheetH), MIN_FIT, 1)
end

-- ⚠️ ПОКА КАРТА ОТКРЫТА, ШТАТНОЕ УПРАВЛЕНИЕ ВЫКЛЮЧЕНО.
-- Active на рамке океана забирает касание у камеры, но этого мало: экранные стики
-- и кнопка прыжка на телефоне остаются под картой и продолжают ловить палец, если он
-- заедет за край листа. ModalEnabled прячет их целиком — на время карты игрок и не
-- должен ходить. На ПК свойство ни на что не влияет, поэтому платформу не проверяем.
local function setControlsEnabled(on)
	pcall(function() UserInputService.ModalEnabled = not on end)
end

local function closeMap()
	if not isOpen then return end
	isOpen = false
	selected = nil
	setControlsEnabled(true)
	dataEvent:FireServer(false)
	-- лист из рук убираем тем же движением: закрыли карту — опустили бумагу.
	-- putAway окно не трогает, поэтому петли не будет.
	if typeof(_G.MapItemPutAway) == "function" then pcall(_G.MapItemPutAway) end
	local t = TweenInfo.new(Map.OPEN_TIME * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(openScale, t, { Scale = Map.OPEN_SCALE }):Play()
	TweenService:Create(dim, TweenInfo.new(Map.DIM_TIME * 0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(Map.OPEN_TIME * 0.6, function()
		if not isOpen then gui.Enabled = false end
	end)
end

--[[ ⚠️ НАКЛОНА rotateX ЗДЕСЬ НЕТ И НЕ БУДЕТ.
     В прототипе лист «лежит» на 45° и выпрямляется до 5° — это 3D-трансформ CSS,
     а Roblox 2D UI поворачивает только вокруг оси экрана (Rotation), перспективы
     у него нет вовсе. Подделывать наклон сжатием по вертикали не стали: у листа
     ровные прямые кромки, и неравномерное сжатие читается как баг разрешения, а
     не как разворот бумаги. Остаётся то, что переносится один в один: масштаб
     0.55 → 1 с лёгким перелётом (Back ≈ cubic-bezier(0.2,0.9,0.3,1.05)) и подъём.
     Масштаб живёт на stack, а НЕ на row: на row сидит подгонка под экран, и
     второй UIScale там просто не заработает. ]]
local function openMap()
	if isOpen then return end
	isOpen = true
	setControlsEnabled(false)
	fitScreen()
	gui.Enabled = true
	card.Visible = false
	clearRoute()

	--[[ ⚠️ ПАНОРАМА СБРАСЫВАЕТСЯ ПРИ КАЖДОМ ОТКРЫТИИ, И ЭТО НЕ ПРИДИРКА.
	     centred и pan переживали закрытие: центр мира оставался прибит к позиции
	     плота из ПЕРВОГО снимка за сессию, а смещение — к тому месту, куда карту
	     утащили в прошлый раз. Через полчаса плавания игрок открывал лист и видел
	     пустую воду там, где плота уже нет, — и это при обещании «карта открывается
	     от себя» строкой ниже. Сброс делает обещание правдой: следующий снимок
	     заново возьмёт центр с плота. ]]
	centred = false
	pan = Vector2.zero
	panAnim = nil

	-- центр мира — плот: карта открывается «от себя»
	dataEvent:FireServer(true)

	openScale.Scale = Map.OPEN_SCALE
	row.Position = UDim2.new(0.5, 0, 0.5, Map.OPEN_RISE)
	dim.BackgroundTransparency = 1
	local t = TweenInfo.new(Map.OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(openScale, t, { Scale = 1 }):Play()
	TweenService:Create(row, t, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	TweenService:Create(dim, TweenInfo.new(Map.DIM_TIME),
		{ BackgroundTransparency = Map.DIM_ALPHA }):Play()
end

closeBtn.Activated:Connect(closeMap)
--[[ ⚠️ ЗАКРЫВАЕМ ТОЛЬКО ПО КЛИКУ МИМО ЛИСТА.
     Подложка — кнопка на весь экран, а лист карты над ней — обычные фреймы.
     Roblox не отдаёт им нажатие «в собственность»: клик по листу проваливается
     до подложки, и карта закрывалась от любого клика по ней самой, в том
     числе при панорамировании. Поэтому смотрим, где был курсор в момент
     нажатия и в момент отпускания: попал хоть один в границы листа — не наше. ]]
local GuiService = game:GetService("GuiService")
local pressPos = nil
local function insideRow(pos)
	if not pos then return false end
	local inset = GuiService:GetGuiInset()
	local x, y = pos.X, pos.Y - inset.Y
	local p, s = row.AbsolutePosition, row.AbsoluteSize
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end
dim.MouseButton1Down:Connect(function()
	pressPos = UserInputService:GetMouseLocation()
end)
dim.Activated:Connect(function()
	local release = UserInputService:GetMouseLocation()
	local down = pressPos
	pressPos = nil
	if insideRow(down) or insideRow(release) then return end
	closeMap()
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then closeMap() end
end)

sailBtn.Activated:Connect(function()
	if selected then sailEvent:FireServer(selected) end
end)

dataEvent.OnClientEvent:Connect(function(payload)
	snap = payload
	-- ⚠️ ЦЕНТР МИРА БЕРЁМ ОДИН РАЗ.
	-- Если пересчитывать его каждый снимок, панорама будет уезжать вслед за
	-- плывущим плотом, и рука игрока никогда не удержит карту на месте.
	if not centred then
		centred = true
		originX, originZ = snap.raft.x, snap.raft.z
	end
	render()
end)

-- Баннер атаки мигает: opacity 1 ↔ 0.55 за полный цикл BANNER_BLINK, то есть по
-- половине цикла на затухание и на возврат. Гасим ВСЕ три слоя разом (фон, текст,
-- красную обводку): погасишь только текст — красная рамка останется гореть ровным
-- светом, и мигание прочитается как сбой отрисовки, а не как тревога.
local blinkHalf = Map.BANNER_BLINK * 0.5
local BANNER_BG = 0.03
local BANNER_DIM = 0.45
task.spawn(function()
	while true do
		if banner.Visible then
			TweenService:Create(banner, TweenInfo.new(blinkHalf), {
				TextTransparency = BANNER_DIM,
				TextStrokeTransparency = BANNER_DIM,
				BackgroundTransparency = BANNER_BG + BANNER_DIM * (1 - BANNER_BG),
			}):Play()
			TweenService:Create(bannerEdge, TweenInfo.new(blinkHalf),
				{ Transparency = BANNER_DIM }):Play()
			task.wait(blinkHalf)
			TweenService:Create(banner, TweenInfo.new(blinkHalf), {
				TextTransparency = 0, TextStrokeTransparency = 0,
				BackgroundTransparency = BANNER_BG,
			}):Play()
			TweenService:Create(bannerEdge, TweenInfo.new(blinkHalf),
				{ Transparency = 0 }):Play()
			task.wait(blinkHalf)
		else
			task.wait(0.5)
		end
	end
end)

sailEvent.OnClientEvent:Connect(function(action, id, cost)
	if action == "denied" then
		if _G.Notify then
			_G.Notify({ type = "warn", icon = "🗺️", title = "Не выйдет", body = tostring(id) })
		end
	elseif action == "sailing" then
		--[[ ⚠️ КАРТУ ЗАКРЫВАЕМ СРАЗУ, ДО ШТОРКИ.
		     Через полторы секунды сервер переставит плот, и поверх мира ляжет
		     полноэкранный экран перемещения. Оставить карту открытой значит
		     показать её поверх шторки, а после неё вернуть игрока в меню вместо
		     мира, куда он только что приплыл. ]]
		closeMap()
		if _G.Notify then
			_G.Notify({ type = "success", icon = "⛵", title = "Курс проложен",
				body = ("Списано нефти: %d"):format(cost or 0) })
		end
	end
end)

task.spawn(function()
	local cam = Workspace.CurrentCamera
	while not cam do task.wait(0.2); cam = Workspace.CurrentCamera end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen then fitScreen() end
	end)
end)

-- ═══════════ захват острова чужаками ═══════════

local CAPTURE_FALL = 1.2   -- падение острова: сжатие до 0.45 и растворение
local GHOST_FADE   = 0.7   -- метка гаснет по клику
local GHOST_BLINK  = 1.6   -- полный цикл мигания подписи «Сигнал потерян»

-- ⚠️ ГРУППОВОЙ ПРОЗРАЧНОСТИ У ОБЫЧНОГО ФРЕЙМА НЕТ.
-- CanvasGroup её умеет, но он рисует детей в текстуру своего размера и срезал бы
-- всё, что вылезает за узел: гало, бирки, флажок, бейдж. Поэтому гасим поштучно,
-- обходя поддерево. Порядок веток важен: TextButton — тоже GuiObject, и если
-- проверять GuiObject первым, у кнопок никогда не погаснет текст.
local function fadeAway(root, time)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function walk(inst)
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			TweenService:Create(inst, info, {
				BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1,
			}):Play()
		elseif inst:IsA("GuiObject") then
			TweenService:Create(inst, info, { BackgroundTransparency = 1 }):Play()
		elseif inst:IsA("UIStroke") then
			TweenService:Create(inst, info, { Transparency = 1 }):Play()
		end
		for _, child in ipairs(inst:GetChildren()) do walk(child) end
	end
	walk(root)
end

--[[ ⚠️ ЭТОТ ХУК СЕРВЕР ПОКА НЕ ЗОВЁТ, И ЭТО НЕ ЗАБЫТЫЙ КОД.
     MapSystem не шлёт события захвата вовсе: снапшот знает только owned и seen,
     а чужой владелец в нём не описан. Сам захват мы не реализуем — придумывать
     на клиенте, кто и когда отнял остров, значит рисовать игроку неправду.
     Наружу отдаём одну точку входа: сервер (или ручная проверка из консоли)
     зовёт _G.MapIslandCaptured(id), и карта отыгрывает падение острова.
     Штурма с тряской и расходящимися кольцами из хендофа здесь нет: он
     показывает ход боя, о котором клиенту никто не сообщает, и без данных
     превратился бы в декорацию, врущую про время атаки. ]]
_G.MapIslandCaptured = function(id)
	local node = nodes[id]
	if not node or forgotten[id] then return end
	forgotten[id] = true
	updaters[id] = nil
	-- обводку убираем из таблицы сразу: покадровый цикл красит её по выбору, а
	-- через мгновение песка не станет вовсе
	outlines[id] = nil
	if selected == id then
		selected = nil
		card.Visible = false
		clearRoute()
	end

	local fall = new("UIScale", { Scale = 1 }, node)
	TweenService:Create(fall, TweenInfo.new(CAPTURE_FALL, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { Scale = 0.45 }):Play()
	fadeAway(node, CAPTURE_FALL)

	task.delay(CAPTURE_FALL, function()
		if not node.Parent then return end
		-- вычищаем всё вместе с UIScale падения: узел должен вернуться к масштабу 1
		for _, child in ipairs(node:GetChildren()) do child:Destroy() end

		-- Метка «сигнал потерян»: в хендофе кольцо пунктирное, у нас сплошное и
		-- полупрозрачное — пунктира нет, а серый цвет и знак вопроса и так
		-- говорят, что связи с островом больше нет.
		local mark = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4,
		}, node)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, mark)
		new("UIStroke", {
			Thickness = 3, Color = ISLE.ghostInk, Transparency = 0.45,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, mark)
		new("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4,
			Font = Map.FONT, TextSize = 18, TextColor3 = ISLE.ghostInk,
			TextTransparency = 0.35, Text = "?",
		}, mark)

		local lost = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8),
			Size = UDim2.fromOffset(140, 14), BackgroundTransparency = 1, ZIndex = 4,
			Font = Map.FONT, TextSize = 12, TextColor3 = ISLE.ghostText, Text = "Сигнал потерян",
		}, node)
		task.spawn(function()
			local half = GHOST_BLINK * 0.5
			while lost.Parent do
				TweenService:Create(lost, TweenInfo.new(half), { TextTransparency = 0.45 }):Play()
				task.wait(half)
				TweenService:Create(lost, TweenInfo.new(half), { TextTransparency = 0 }):Play()
				task.wait(half)
			end
		end)

		-- Клик по метке гасит её сразу и навсегда: никаких подтверждений, как в
		-- хендофе. forgotten остаётся выставленным, поэтому следующий снимок
		-- сервера остров обратно не вернёт.
		ghostAction[id] = function()
			ghostAction[id] = nil
			fadeAway(node, GHOST_FADE)
			task.delay(GHOST_FADE, function()
				if nodes[id] then nodes[id]:Destroy() end
				nodes[id] = nil
			end)
		end
	end)
end

-- ⚠️ _G.OpenMapMenu ЗДЕСЬ НЕ ТРОГАЕМ.
-- Это имя принадлежит MapItem: он поднимает лист в руках и уже оттуда зовёт нас.
-- Объявив его и тут, мы бы снова получили гонку загрузки, из-за которой окно не
-- открывалось. Наружу отдаём свои имена.
_G.MapMenuOpen = openMap
_G.MapMenuClose = closeMap
_G.MapMenuIsOpen = function() return isOpen end

print("[Карта/клиент] меню готово: M или кнопка «Карта» открывают, крестик или Esc закрывают")
