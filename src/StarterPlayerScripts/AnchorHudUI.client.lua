local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[═══════════════════════════════════════════════════════════════════════════
	ЯКОРЬ ПЛОТА — ЭКРАННЫЕ КНОПКИ «ВВЕРХ» / «ВНИЗ».

	Дизайн взят из хендоффа «Anchor HUD» (README.md + Anchor HUD.dc.html): цвета,
	размеры, шрифтовые кегли и тайминги — оттуда дословно. Отступ «36 px от низа»
	из хендоффа НЕ взят: см. ниже про хотбар — на этом экране низ уже занят.

	⚠️ ГЛУБИНА ЯКОРЯ — ЧУЖОЕ ЗНАЧЕНИЕ, КЛИЕНТ ЕГО НЕ СЧИТАЕТ.
	Считает сервер, сюда приходит готовое число. Рисовать «на опережение» нельзя:
	за один якорь может взяться двое, и предсказанная высота разошлась бы с
	настоящей ровно в тот момент, когда игрок на неё смотрит. Гасить кнопку на
	крайнем значении при этом можно и нужно — это блокировка лишнего нажатия по
	уже известному состоянию, а не догадка о будущем.

	Контракт с серверной частью (RemoteEvent RaftAnchorAction в ReplicatedStorage):
	    клиент → серверу:  FireServer("step", delta),  delta = -25 поднять, +25 опустить
	    сервер → клиенту:  ("state", { depth = 0..100, inZone = boolean })
	«state» приходит и на входе в зону, и на каждом изменении глубины, и на выходе.
═══════════════════════════════════════════════════════════════════════════]]

local Players           = game:GetService("Players")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Присваивается в самом конце файла, когда интерфейс уже собран (там же объяснено,
-- почему не здесь). Объявлена тут, чтобы обработчики кнопок видели ту же переменную.
local anchorEvent

-- ── размеры макета ──
local BTN_W, BTN_H = 172, 70
local DROP     = 5    -- «объёмная» тень под кнопкой: box-shadow 0 5px 0
local PRESS    = 4    -- на сколько кнопка проваливается при нажатии
local MARGIN   = 6    -- запас холста вокруг кнопки, см. про CanvasGroup ниже
local ROW_GAP  = 14   -- между кнопками
local COL_GAP  = 12   -- между текстом высоты и рядом кнопок
local CARD_PAD = 8
local LABEL_H  = 26
local ARROW_W, ARROW_H = 22, 15
-- ⚠️ Шаг обязан совпадать с серверным (AnchorInteraction, ANCHOR_STEP): сервер
-- принимает ровно это число и молча игнорирует любое другое — кнопки просто
-- перестанут работать, без единой ошибки в логе.
local STEP = 5

local ROW_W  = BTN_W * 2 + ROW_GAP
local ROW_H  = BTN_H + DROP
local CARD_W = ROW_W + CARD_PAD * 2
local CARD_H = LABEL_H + COL_GAP + ROW_H + CARD_PAD + MARGIN

--[[ ⚠️ ВЫСОТА НАД ХОТБАРОМ — ТА ЖЕ, ЧТО У ДИАЛОГОВ.
     Число 112 живёт в DialogueUI (HOTBAR_CLEAR) и продублировано в RadiationUI по
     той же причине: всё, что встаёт «над хотбаром», обязано вставать на одну
     линию, иначе один блок садится на слоты, а другой висит в воздухе.
     Это запасное значение — обычно верх меряется по факту, см. ceilingY(). ]]
local HOTBAR_CLEAR = 112
--[[ ⚠️ ЛЕБЁДКА СТОИТ НИЖЕ ОСТАЛЬНЫХ: ЕЙ НЕ НУЖЕН ЗАПАС НА СОСЕДЕЙ.
     HOTBAR_CLEAR — общая для игры высота «над хотбаром», и она с запасом:
     под ней уживаются шкала топлива, уведомления и прочее. У кнопок якоря
     соседей нет, а владелец дважды просил опустить — карточка стояла
     заметно выше хотбара и висела посреди экрана.
     Опускаем на HUD_DROP и добавляем обратно MARGIN — внутренний отступ
     холста, из-за которого видимый низ кнопок и так выше самой карточки. ]]
local HUD_DROP = 8
local CARD_GAP     = 4    -- зазор до того, над чем стоим (плюс нижний отступ карточки)

local RISE       = 30     -- сдвиг Y на появлении/исчезании, из хендоффа
local SHOW_INFO  = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DIM_OFF    = 0.55   -- opacity 0.45 у выключенной кнопки

-- ── палитра (Design Tokens хендоффа) ──
local INK        = Color3.fromHex("1A1626")
local WHITE      = Color3.new(1, 1, 1)
local SHADOW_INK = Color3.new(0, 0, 0)

local GREEN = {
	top  = Color3.fromHex("9BE86A"),
	mid  = Color3.fromHex("4DB43A"),
	bot  = Color3.fromHex("2F8A2A"),
	drop = Color3.fromHex("143D1A"),
}
local BLUE = {
	top  = Color3.fromHex("7ED0FF"),
	mid  = Color3.fromHex("2F8BE6"),
	bot  = Color3.fromHex("1B5FB8"),
	drop = Color3.fromHex("0F2F66"),
}

--[[ Rubik 900 в Roblox нет. GothamBlack берём по той же причине, что и остальной
     проект (DialogueUI, DayNight): он такой же тяжёлый и, в отличие от половины
     списка шрифтов, гарантированно рисует кириллицу. ]]
local TEXT_FONT = Enum.Font.GothamBlack

-- ── мелкие помощники ──
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then o.Parent = parent end
	return o
end

-- radius 999 из макета = «пилюля». UDim.new(1, 0) даёт ровно половину меньшей
-- стороны, то есть тот же результат, но не разъедется при смене размера кнопки.
local function pill(o)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, o)
	return o
end

--[[ Надпись с тенью «0 2px 0» из макета: та же строка чёрным на два пикселя ниже.
     UIStroke вместо копии не годится — он кладёт обводку вокруг всей буквы, а в
     макете тень только снизу.

     ⚠️ ТЕНЬ — СОСЕД НАДПИСИ, А НЕ ЕЁ РЕБЁНОК. При ZIndexBehavior.Sibling
     потомок рисуется поверх родителя ВСЕГДА, какой ему ZIndex ни ставь, и
     чёрная копия просто закрыла бы белый текст. Поэтому обе строки лежат в
     общей коробке, тень — первой по дереву.
     Коробка тянется по тексту (AutomaticSize.X), так что раскладка кнопки
     по-прежнему центрирует надпись по её настоящей ширине, а не по угаданной.

     Возвращается ВИДИМАЯ надпись: её Text меняют снаружи, тень подхватывает. ]]
local function shadowedText(parent, order, height, size, text, shadowT)
	local box = new("Frame", {
		Name = "Text",
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
	}, parent)

	local function line(name, colour, transparency, dy, z)
		return new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, dy),
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = TEXT_FONT,
			TextSize = size,
			TextColor3 = colour,
			TextTransparency = transparency,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
			ZIndex = z,
		}, box)
	end

	local shadow = line("Shadow", SHADOW_INK, shadowT, 2, 1)
	local main   = line("Main", WHITE, 0, 0, 2)
	main:GetPropertyChangedSignal("Text"):Connect(function()
		shadow.Text = main.Text
	end)
	return main
end

--[[ ⚠️ ТРЕУГОЛЬНИК СОБРАН ИЗ ПОЛОСОК, А НЕ НАПИСАН СИМВОЛОМ «▲».
     Хендофф разрешает оба способа, но проект на символе уже обжигался: см.
     комментарий в Quests/TrackerCard.client.lua — глиф ▲/▼ есть не во всех
     шрифтах Roblox, и вместо стрелки выходит пустое место. Завести картинку
     нельзя: rbxassetid не выдумывается.
     Цена решения: пятнадцать фреймов на стрелку и лесенка шириной в пиксель по
     косой грани. На кнопке высотой 70 px её не разглядеть, зато стрелка есть
     всегда и держит ровно те пропорции, что в макете (основание 22, высота 15). ]]
local function makeTriangle(parent, up, colour, transparency, dy, z)
	local box = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, dy),
		Size = UDim2.fromOffset(ARROW_W, ARROW_H),
		ZIndex = z,
	}, parent)
	for i = 1, ARROW_H do
		-- i = 1 — ряд у острия, i = ARROW_H — основание
		local w = math.max(1, math.floor(ARROW_W * i / ARROW_H + 0.5))
		new("Frame", {
			BackgroundColor3 = colour,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, up and (i - 1) or (ARROW_H - i)),
			Size = UDim2.fromOffset(w, 1),
		}, box)
	end
	return box
end

-- ── корень интерфейса ──
local gui = new("ScreenGui", {
	Name = "AnchorHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,   -- та же система координат, что у хотбара и диалога
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	--[[ Выше диалога (40) и выше плашек опасности (45): пока игрок держит палец
	     на кнопке якоря, ничто не должно оказаться поверх неё. Ниже полноэкранных
	     меню (90+) — открытая карта или инвентарь важнее. ]]
	DisplayOrder = 46,
	Enabled = false,
}, playerGui)

--[[ ⚠️ ЭТОТ HUD НЕ ЗАБИРАЕТ УПРАВЛЕНИЕ — И ЭТО ГЛАВНОЕ ОТЛИЧИЕ ОТ МЕНЮ.
     Здесь стоял атрибут ModalUI: ModalUIUnlocker вешает по нему невидимую
     Modal-кнопку и освобождает курсор, чтобы по кнопкам можно было попасть
     от первого лица. Для окна, которое игрок сам открыл, это правильно —
     для HUD, который просто висит, пока стоишь на клетке, нет: обзор
     переставал крутиться, а клики уходили в никуда, хотя игрок ничего не
     открывал.
     Поэтому модального режима нет вовсе. Мешает игроку теперь только сама
     карточка — прямоугольник в две кнопки над хотбаром; всё остальное
     кликается и крутится как обычно.
     Цена: в режиме от первого лица (курсор заперт в центре) по кнопкам не
     попасть. Это осознанный размен — так просил владелец. ]]

--[[ Держатель отвечает ТОЛЬКО за место на экране, карточка внутри — только за
     анимацию. Иначе твин появления и покадровая подгонка высоты дрались бы за
     одно и то же свойство Position и HUD дёргался бы при открытии диалога. ]]
local holder = new("Frame", {
	Name = "Holder",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -(HOTBAR_CLEAR - HUD_DROP - MARGIN)),
	Size = UDim2.fromOffset(CARD_W, CARD_H),
}, gui)

local holderScale = new("UIScale", { Scale = 1 }, holder)

--[[ ⚠️ CanvasGroup — ЧТОБЫ ПОЯВЛЕНИЕ БЫЛО ОДНИМ ТВИНОМ, А НЕ ДВАДЦАТЬЮ.
     В макете появление — это opacity всей карточки. Поэлементно это полсотни
     прозрачностей (фоны, обводки, блики, тени, надписи), и любая забытая
     проявляется ярким пятном на прозрачном HUD.
     Цена: холст режет всё, что вылезло за его границы, поэтому размеры карточки
     считаются с запасом (CARD_PAD/MARGIN), а не «впритык по кнопкам».
     Размер тут фиксированный — AutomaticSize на CanvasGroup ставить нельзя, эта
     пара ведёт себя непредсказуемо (см. RadiationUI.client.lua). ]]
local card = new("CanvasGroup", {
	Name = "Card",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, RISE),
	Size = UDim2.new(1, 0, 1, 0),
	GroupTransparency = 1,
}, holder)

new("UIPadding", {
	PaddingTop    = UDim.new(0, CARD_PAD),
	PaddingLeft   = UDim.new(0, CARD_PAD),
	PaddingRight  = UDim.new(0, CARD_PAD),
	PaddingBottom = UDim.new(0, MARGIN),
}, card)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, COL_GAP),
}, card)

-- ── текст высоты ──
-- 0.4 = тень rgba(0,0,0,.6) из макета, переведённая в прозрачность Roblox
local heightLabel = shadowedText(card, 1, LABEL_H, 20, "Высота: 100%", 0.4)

--[[ Второй тени из макета — «0 0 6px rgba(0,0,0,.5)», мягкому ореолу — в Roblox
     соответствия нет: размытие делается картинкой, а новых ассетов заводить
     нельзя. Ближайшая честная замена — обводка букв: она так же отрывает белый
     текст от светлого неба, только жёстким краем вместо размытого.
     Contextual здесь уместен: на надписи он обводит именно буквы (на кнопке с
     пустым текстом он не рисует ничего — там нужен Border, см. ниже). ]]
new("UIStroke", {
	Thickness = 2,
	Color = SHADOW_INK,
	Transparency = 0.5,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
}, heightLabel)

-- ── ряд кнопок ──
local row = new("Frame", {
	Name = "Buttons",
	LayoutOrder = 2,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(ROW_W, ROW_H),
}, card)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, ROW_GAP),
}, row)

local function makeButton(order, palette, up, caption, delta)
	local self = { enabled = true }

	local btn = new("TextButton", {
		Name = caption,
		LayoutOrder = order,
		AutoButtonColor = false,   -- ⚠️ hover-состояний в макете нет: это тап-интерфейс
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BTN_W, ROW_H),
	}, row)

	--[[ Своя CanvasGroup на кнопку — по той же причине, что и на карточку:
	     disabled в макете это opacity 0.45 на ВСЮ кнопку, одним числом.
	     Холст на MARGIN больше кнопки с каждой стороны, иначе трёхпиксельная
	     обводка обрезалась бы по краю. ]]
	local dim = new("CanvasGroup", {
		Name = "Dim",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, MARGIN * 2, 1, MARGIN * 2),
	}, btn)

	local stack = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(BTN_W, ROW_H),
	}, dim)

	--[[ Объёмная тень — та же пилюля на DROP пикселей ниже. Нажатие двигает
	     ТОЛЬКО тело кнопки, поэтому видимая полоска тени сама ужимается с 5 px
	     до 1 — ровно то, что в макете записано двумя разными box-shadow. ]]
	pill(new("Frame", {
		Name = "Drop",
		BackgroundColor3 = palette.drop,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, DROP),
		Size = UDim2.fromOffset(BTN_W, BTN_H),
		ZIndex = 1,
	}, stack))

	local body = pill(new("Frame", {
		Name = "Body",
		BackgroundColor3 = palette.mid,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(BTN_W, BTN_H),
		ZIndex = 2,
	}, stack))

	new("UIGradient", {
		Rotation = 90,   -- сверху вниз = linear-gradient(180deg, …) из макета
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, palette.top),
			ColorSequenceKeypoint.new(0.55, palette.mid),
			ColorSequenceKeypoint.new(1, palette.bot),
		}),
	}, body)

	-- ⚠️ Border, а не Contextual: у кнопки текст пустой (надпись — отдельный
	-- лейбл внутри), и Contextual обвёл бы пустоту, то есть ничего.
	new("UIStroke", {
		Thickness = 3,
		Color = INK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, body)

	-- глянцевый блик
	pill(new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.65,   -- rgba(255,255,255,.35)
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 5),
		Size = UDim2.new(1, -28, 0, 18),
		ZIndex = 3,
	}, body))

	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 3,
	}, body)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, content)

	-- стрелка: тёмная копия на 2 px ниже + белая поверх — та же тень, что у текста
	local arrowBox = new("Frame", {
		Name = "Arrow",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(ARROW_W, ARROW_H),
	}, content)
	makeTriangle(arrowBox, up, SHADOW_INK, 0.55, 2, 1)
	makeTriangle(arrowBox, up, WHITE, 0, 0, 2)

	-- 0.55 = тень rgba(0,0,0,.45) из макета
	shadowedText(content, 2, BTN_H, 24, caption, 0.55)

	local function press(down)
		if not self.enabled then down = false end
		TweenService:Create(body, PRESS_INFO, {
			Position = UDim2.fromOffset(0, down and PRESS or 0),
		}):Play()
	end

	-- MouseButton1Down/Up приходят и от пальца, и от мыши — отдельная ветка для
	-- тача не нужна. MouseLeave здесь не hover-состояние, а страховка: увёл палец
	-- с кнопки, не отпустив, — она обязана подняться обратно.
	btn.MouseButton1Down:Connect(function() press(true) end)
	btn.MouseButton1Up:Connect(function() press(false) end)
	btn.MouseLeave:Connect(function() press(false) end)

	btn.Activated:Connect(function()
		if not self.enabled or not anchorEvent then return end
		anchorEvent:FireServer("step", delta)
		--[[ Мах рукой — тот же, что при ударе по ресурсам в море
		     (ResourcePull, _G.PlayResourceSwing). Играем СРАЗУ, не дожидаясь
		     ответа сервера: ответ идёт полкруга по сети, и рука дёргалась бы
		     заметно позже нажатия. Отказ сервера ничего не портит — игрок
		     просто махнёт рукой, а ворот не повернётся. ]]
		if typeof(_G.PlayResourceSwing) == "function" then
			_G.PlayResourceSwing()
		end
	end)

	self.dim = dim
	return self
end

-- delta по контракту: минус — поднять (глубина уменьшается), плюс — опустить
local upBtn   = makeButton(1, GREEN, true,  "ВВЕРХ", -STEP)
local downBtn = makeButton(2, BLUE,  false, "ВНИЗ",   STEP)

--[[ Геймпад: крестовина ↑/↓ = те же кнопки. Идём через тот же путь, что и
     нажатие: проверка enabled, отправка шага, мах рукой. dir = -1 поднять,
     +1 опустить (знак как у delta кнопок). Зовёт GamepadAdapter. ]]
_G.AnchorHudStep = function(dir)
	if not gui.Enabled or not anchorEvent then return end
	local b = (dir < 0) and upBtn or downBtn
	if not b.enabled then return end
	anchorEvent:FireServer("step", (dir < 0) and -STEP or STEP)
	if typeof(_G.PlayResourceSwing) == "function" then _G.PlayResourceSwing() end
end

local function setEnabled(b, on)
	b.enabled = on
	b.dim.GroupTransparency = on and 0 or DIM_OFF
end

-- ── появление и скрытие ──
local shown = false

local function setShown(want)
	if want == shown then return end
	shown = want

	if want then
		-- Если предыдущий уход ещё не доиграл, стартуем с текущего кадра: сброс в
		-- «прозрачно и на 30 ниже» дал бы моргание на быстром вход-выход-вход.
		if not gui.Enabled then
			card.GroupTransparency = 1
			card.Position = UDim2.new(0.5, 0, 1, RISE)
			gui.Enabled = true
		end
		TweenService:Create(card, SHOW_INFO, {
			GroupTransparency = 0,
			Position = UDim2.new(0.5, 0, 1, 0),
		}):Play()
	else
		local out = TweenService:Create(card, SHOW_INFO, {
			GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, RISE),
		})
		out:Play()
		out.Completed:Once(function()
			-- за 300 мс игрок мог вернуться в зону — тогда выключать уже нечего
			if not shown then gui.Enabled = false end
		end)
	end
end

local depth = 0

local function applyState(payload)
	if type(payload) ~= "table" then return end

	if type(payload.depth) == "number" then
		depth = math.clamp(payload.depth, 0, 100)
	end
	heightLabel.Text = string.format("Высота: %d%%", math.floor(100 - depth + 0.5))

	setEnabled(upBtn,   depth > 0)
	setEnabled(downBtn, depth < 100)

	-- nil трактуем как «про зону ничего не сказали» и оставляем как было: в
	-- контракте inZone есть всегда, но терять HUD из-за чужой опечатки не хочется.
	if payload.inZone ~= nil then
		setShown(payload.inZone == true)
	end
end

--[[ ⚠️ HUD ВСТАЁТ НАД ХОТБАРОМ, А ПРИ ОТКРЫТОМ ДИАЛОГЕ — НАД ДИАЛОГОМ.
     Приём не выдуман здесь, а взят у CupPurifier.client.lua (кнопки «Выпить /
     Вылить») и RadiationUI.client.lua (плашки опасности): у обоих та же беда —
     их место внизу по центру уже занято окном разговора.
     Меряем ФАКТИЧЕСКИЙ верх того, над чем стоим, а не вписываем число: колонка
     диалога растёт от длины реплики и числа вариантов ответа, и любая заранее
     подобранная константа разъехалась бы на первой же длинной фразе.
     Сравнивать координаты можно: у всех трёх ScreenGui IgnoreGuiInset = true,
     то есть они живут в одной системе отсчёта. ]]
local function guiPart(...)
	local node = playerGui
	for _, name in ipairs({ ... }) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

--[[ ⚠️ ПУСТОЙ КОНТЕЙНЕР — НЕ ПОВОД ПОДНИМАТЬСЯ.
     Проверялись только Visible и высота, а этого мало: у диалога и у плашек
     опасности контейнеры живут всегда, они Visible и растянуты по экрану —
     просто пустые. HUD принимал их за занятое место и уезжал на середину
     экрана, хотя внизу было чисто.
     Теперь требуем три вещи: сам ScreenGui включён, у контейнера есть ВИДИМЫЙ
     ребёнок с ненулевым размером, и он действительно в нижней половине
     экрана. Последнее — страховка: интерфейс управления якорем не может
     оказаться выше середины, что бы там ни намерил чужой контейнер. ]]
local function hasVisibleContent(node)
	for _, d in ipairs(node:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.Y > 1
			and (d.BackgroundTransparency < 1
				or (d:IsA("TextLabel") and d.Text ~= "")
				or d:IsA("ImageLabel") or d:IsA("ImageButton")) then
			return true
		end
	end
	return false
end

local function topOf(guiName, frameName)
	local node = guiPart(guiName, frameName)
	if not (node and node:IsA("GuiObject")) then return nil end
	local screen = node:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not screen.Enabled then return nil end
	if not (node.Visible and node.AbsoluteSize.Y > 1) then return nil end
	if not hasVisibleContent(node) then return nil end
	local cam = workspace.CurrentCamera
	local vpY = cam and cam.ViewportSize.Y or 0
	if vpY > 1 and node.AbsolutePosition.Y < vpY * 0.5 then return nil end
	return node.AbsolutePosition.Y
end

--[[ Порядок проверок = порядок этажей внизу экрана, сверху вниз. Плашки опасности
     (RadiationUI) сами встают над диалогом, поэтому они и есть самый верхний
     этаж; спрошенные раньше диалога, они не дадут HUD залезть им под низ. ]]
--[[ ⚠️ ПО УМОЛЧАНИЮ СТОИМ НАД ХОТБАРОМ ПО КОНСТАНТЕ, А НЕ ПО ЗАМЕРУ.
     Замер чужих контейнеров оказался ненадёжен: у хотбара и у плашек
     опасности рамки выше своего содержимого, и HUD уезжал к середине экрана,
     хотя внизу было пусто. Константа HOTBAR_CLEAR = 112 — ровно то, чем
     пользуются DialogueUI и RadiationUI, то есть высота хотбара уже учтена
     и проверена ими.
     Поднимаемся ВЫШЕ только из-за диалога: он единственный, что реально
     занимает место над хотбаром, и его высота меняется от длины реплики —
     тут без замера никак. Плашки опасности из лестницы убраны: они узкие,
     живут по центру и с кнопками якоря не пересекаются. ]]
local function ceilingY()
	return topOf("DialogueGui", "Column")
end

--[[ Масштаб — по общей формуле проекта (InventoryUI.computeUIScale, та же в
     DialogueUI): вверх не растём никогда, вниз — по меньшей стороне вьюпорта.
     Своя формула здесь была бы ошибкой: HUD стоит вплотную к хотбару и диалогу,
     и сжиматься он обязан ровно с ними, иначе на телефоне ряд кнопок шириной
     358 px просто вылезет за края экрана. ]]
local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.Y < 1 then return 1 end
	return math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.45, 1)
end

-- Один покадровый проход вместо подписок на Visible каждого чужого фрейма: окно
-- диалога меняет высоту прямо во время печати текста, и ловить это событиями
-- дороже, чем два сравнения в кадр. Пока HUD скрыт — выходим сразу.
RunService.RenderStepped:Connect(function()
	if not gui.Enabled then return end

	holderScale.Scale = fitScale()

	local ceiling = ceilingY()
	if ceiling then
		holder.Position = UDim2.new(0.5, 0, 0, ceiling - CARD_GAP + MARGIN)
	else
		holder.Position = UDim2.new(0.5, 0, 1, -(HOTBAR_CLEAR - HUD_DROP - MARGIN))
	end
end)

--[[ ⚠️ RemoteEvent ЖДЁМ В КОНЦЕ ФАЙЛА, КОГДА ИНТЕРФЕЙС УЖЕ СОБРАН.
     WaitForChild усыпляет скрипт целиком: стой он наверху, при задержке
     репликации HUD не существовал бы вовсе. Гонки тут нет — кнопки до первого
     «state» не показаны, а «state» приходит по этому же событию. ]]
anchorEvent = ReplicatedStorage:WaitForChild("RaftAnchorAction")

--[[ ⚠️ ДВЕ СТРОКИ В ЛОГ — ЭТО НЕ МУСОР, А ЕДИНСТВЕННЫЙ СПОСОБ ОТЛИЧИТЬ
     «скрипт не запустился» от «сервер молчит». Оба случая выглядят одинаково:
     игрок стоит у лебёдки, интерфейса нет. Первая строка говорит, что клиент
     жив и ремоут нашёл; вторая — что состояние доехало, и с какими числами.
     Печатается ОДИН раз за сессию, потоком лога не станет. ]]
print("[Якорь/клиент] интерфейс готов — жду сигнала зоны")

local firstStateLogged = false
anchorEvent.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "state" then return end
	if not firstStateLogged then
		firstStateLogged = true
		print(("[Якорь/клиент] пришло состояние: глубина %s, в зоне %s")
			:format(tostring(type(payload) == "table" and payload.depth),
				tostring(type(payload) == "table" and payload.inZone)))
	end
	applyState(payload)
end)
