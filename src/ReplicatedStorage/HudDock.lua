--[[ HudDock — ОДНО МЕСТО, КОТОРОЕ ЗНАЕТ, ГДЕ КОНЧАЕТСЯ ДИАЛОГ.

     Низ экрана по центру занят дважды. Там стоит окно диалога (DialogueUI,
     колонка над хотбаром) и туда же почти все инструменты кладут свою строку
     подсказки: топор, кирка, лопата, мешки, кружка, мангал, факел. Пока
     диалога нет, это никому не мешает; стоит собеседнику заговорить — текст
     ложится на текст, и не читается ни тот, ни другой.

     ⚠️ ПОДНИМАЕТСЯ ПОДСКАЗКА, А НЕ ОПУСКАЕТСЯ ДИАЛОГ.
     Диалог привязан к хотбару и сам подгоняется под экран (anchorToHotbar в
     DialogueUI); двигать его — значит спорить с этой подгонкой каждый кадр.
     Подсказка же временная и своего места не имеет: ей и уступать.

     ⚠️ СЧИТАЕМ ОТ ИСХОДНОЙ ПОЗИЦИИ, А НЕ ОТ ТЕКУЩЕЙ.
     Соблазнительно каждый кадр смотреть на AbsolutePosition и сдвигать
     относительно неё. Так делать нельзя: собственный сдвиг попадёт в следующий
     замер, и подсказка уползёт за верхний край за пару секунд. Поэтому
     запоминаем позицию, с которой элемент создан, и каждый кадр решаем заново
     от неё.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local HudDock = {}

local player = Players.LocalPlayer
local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

--[[ Верхняя кромка диалогового окна в пикселях экрана — или nil, если диалога
     сейчас нет. Проверяем ТРИ вещи: включён ли сам ScreenGui, видима ли
     колонка и есть ли у неё размер. Одного Enabled мало: окно диалога живёт
     всегда, а прячется через Visible на колонке (см. DialogueUI). ]]
function HudDock.dialogueTop()
	if not playerGui then
		playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end
	end
	local gui = playerGui:FindFirstChild("DialogueGui")
	if not (gui and gui:IsA("ScreenGui") and gui.Enabled) then return nil end
	local column = gui:FindFirstChild("Column")
	if not (column and column:IsA("GuiObject") and column.Visible) then return nil end
	if column.AbsoluteSize.Y < 1 then return nil end

	-- ⚠️ СНАЧАЛА — ЧИСЛО ОТ САМОГО ДИАЛОГА. DialogueUI считает верх окна из своих
	-- констант и масштаба (атрибут VisualTop); это единственный источник, который
	-- не зависит от кривых AbsolutePosition в дереве с AutomaticSize + UIScale.
	-- Замер ниже остаётся запасным на случай старой версии DialogueUI.
	local published = gui:GetAttribute("VisualTop")
	if type(published) == "number" then return published end

	--[[ ⚠️ ВЕРХ МЕРЯЕМ ПО НАРИСОВАННОМУ, А НЕ ПО РАМКЕ КОЛОНКИ.
	     У колонки AutomaticSize и UIScale на одном фрейме, и её AbsolutePosition
	     отчитывается заметно выше реальной плашки: подсказки уезжали к середине
	     экрана, хотя над диалогом было пусто (AnchorHudUI обходил это проверкой
	     «выше половины экрана — не верим»). Поэтому идём по потомкам и берём
	     верх самого высокого видимого элемента, у которого есть что показать:
	     фон, картинка или текст. Прозрачные контейнеры-раскладки пропускаем. ]]
	-- Дети скрытой плашки («Получено», варианты ответа) сами по себе Visible —
	-- проверяем всю цепочку до колонки, иначе спрятанная награда поднимет подсказку.
	local function shown(d)
		while d and d ~= column do
			if not d.Visible then return false end
			d = d.Parent
		end
		return true
	end
	local top = nil
	for _, d in ipairs(column:GetDescendants()) do
		--[[ ⚠️ ЭЛЕМЕНТЫ С AutomaticSize НЕ МЕРЯЕМ ВОВСЕ. Плашка реплики тянется
		     по тексту тем же AutomaticSize, что и колонка, и её AbsolutePosition
		     так же уезжает вверх — подсказка вставала на 80 px выше окна.
		     Аватар, имя и строка текста — фиксированного размера, им верить можно. ]]
		if d:IsA("GuiObject") and d.AbsoluteSize.Y > 0 and shown(d)
			and d.AutomaticSize == Enum.AutomaticSize.None then
			local painted = d.BackgroundTransparency < 1
				or d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame")
				or ((d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "")
			if painted then
				local y = d.AbsolutePosition.Y
				if not top or y < top then top = y end
			end
		end
	end
	return top
end

--[[ Верх ПЕРВОГО СЛОТА хотбара, а не его рамки: рамка выше содержимого на
     несколько десятков пикселей (это уже ловил AnchorHudUI), и подсказки
     висели бы над пустым местом. Нет слота — берём рамку, нет рамки — nil. ]]
function HudDock.hotbarTop()
	if not playerGui then
		playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return nil end
	end
	local hg = playerGui:FindFirstChild("HotbarGui")
	if not (hg and hg:IsA("ScreenGui") and hg.Enabled) then return nil end
	local bar = hg:FindFirstChild("Hotbar")
	if not (bar and bar:IsA("GuiObject") and bar.Visible) then return nil end
	local slot = bar:FindFirstChild("HotbarSlot_1")
	local node = (slot and slot:IsA("GuiObject") and slot.AbsoluteSize.Y > 1) and slot or bar
	if node.AbsoluteSize.Y < 1 then return nil end
	return node.AbsolutePosition.Y
end

--[[ Держит нижнюю кромку элемента выше диалога, пока тот на экране.
     gap — зазор между ними в пикселях; без него подсказка касалась бы рамки.

     ⚠️ ЭЛЕМЕНТ ДОЛЖЕН БЫТЬ УЖЕ СОЗДАН И РАСПОЛОЖЕН: позиция, которая стоит на
     нём в момент вызова, и есть «родная». Зовите после настройки Position. ]]
--[[ Подсказка ставится НИЖЕ расчётного верха диалога на эту величину.
     Верх считает DialogueUI из своих констант, но между ним и реальной кромкой
     кружка аватара в игре осталось около двух десятков пикселей (сверка по
     скриншоту владельца). Крутить здесь, одним числом на все подсказки. ]]
HudDock.EXTRA_DROP = 26

-- Подложка тянется по тексту: у подсказок ширина была прибита гвоздями (300 px),
-- и длинная строка наполовину вылезала за фон. Одна правка здесь чинит все.
local function fitToText(label)
	if not label:IsA("TextLabel") then return end
	label.AutomaticSize = Enum.AutomaticSize.X
	if not label:FindFirstChildOfClass("UIPadding") then
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft  = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = label
	end
	-- Size.X теперь минимум, а не потолок: короткий текст остаётся в старой
	-- ширине, длинный расширяет фон.
	label.TextWrapped = false
end

--[[ obstacle — необязательный GuiObject, над которым подсказка тоже обязана
     держаться (например, ряд кнопок кружки «Выпить/Вылить»): его верх меряется
     по AbsolutePosition и учитывается наравне с диалогом, пока он виден и его
     ScreenGui включён. Поправка EXTRA_DROP к нему не применяется — она про
     расчётный верх диалога, а не про реальную кромку элемента. ]]
--[[ opts.ignoreDialogue = true — подсказка НЕ поднимается над диалогом, только
     над хотбаром и obstacle: живёт в щели между репликой и слотами. Так просил
     владелец для строки грядки («должно быть ниже диалога»). ]]
--[[ ОБЩИЕ ПРЕПЯТСТВИЯ. Ряд кнопок кружки «Выпить/Вылить» стоит над хотбаром, и
     о нём знала только подсказка кружки — подсказка грядки ложилась под него.
     Зарегистрированный элемент учитывают ВСЕ подсказки, пока он виден. ]]
local obstacles = {}
--[[ СТОПКА ПОДСКАЗОК. Две строки (кружка и грядка) вставали на одну полку над
     диалогом и накладывались. Каждая подсказка считает препятствием те, что
     зарегистрированы РАНЬШЕ неё и сейчас видны, — так они складываются
     столбиком, а не друг на друга. ]]
local stack = {}
function HudDock.registerObstacle(gui)
	if gui and gui:IsA("GuiObject") then obstacles[gui] = true end
end
local function elementTop(o)
	if not (o and o.Parent and o.Visible) then return nil end
	local sg = o:FindFirstAncestorWhichIsA("ScreenGui")
	if not (sg and sg.Enabled) then return nil end
	if o.AbsoluteSize.Y < 1 then return nil end
	return o.AbsolutePosition.Y
end

function HudDock.keepAbove(label, gap, obstacle, opts)	if not (label and label:IsA("GuiObject")) then return end
	local ignoreDialogue = type(opts) == "table" and opts.ignoreDialogue == true	gap = gap or 12
	fitToText(label)

	local function obstacleTop()
		if not (obstacle and obstacle.Parent and obstacle.Visible) then return nil end
		local sg = obstacle:FindFirstAncestorWhichIsA("ScreenGui")
		if not (sg and sg.Enabled) then return nil end
		if obstacle.AbsoluteSize.Y < 1 then return nil end
		return obstacle.AbsolutePosition.Y
	end

	local base = label.Position
	local conn
	table.insert(stack, label)

	local function fit()
		if not label.Parent then
			if conn then conn:Disconnect(); conn = nil end
			return
		end
		-- невидимую подсказку двигать незачем: она и не мешает никому
		if not label.Visible then return end

		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if not vp or vp.Y < 1 then return end

		--[[ Нижняя кромка в «родной» позиции. AnchorPoint учитываем честно:
		     у части подсказок он (0.5, 1) — тогда позиция и есть низ, — а у
		     части (0.5, 0.5) или (0.5, 0), и низ ниже на часть высоты. ]]
		local h = label.AbsoluteSize.Y
		--[[ ⚠️ ВЫСОТА — У ScreenGui ПОДСКАЗКИ, А НЕ У КАМЕРЫ. Доля Position.Y.Scale
		     считается от высоты ScreenGui; у гуя с IgnoreGuiInset = false она на
		     высоту верхней панели меньше экрана. Считая от камеры, мы думали, что
		     подсказка на 58 px ниже, чем есть, и поднимали её на те же 58 px выше
		     хотбара («всё ещё слишком высоко»). ]]
		local screenGui = label:FindFirstAncestorWhichIsA("ScreenGui")
		local guiH = (screenGui and screenGui.AbsoluteSize.Y > 1) and screenGui.AbsoluteSize.Y or vp.Y
		local baseBottom = guiH * base.Y.Scale + base.Y.Offset
			+ (1 - label.AnchorPoint.Y) * h
		local top = (not ignoreDialogue) and HudDock.dialogueTop() or nil
		if top then top += HudDock.EXTRA_DROP end
		local obst = obstacleTop()
		if obst and (not top or obst < top) then top = obst end
		for o in pairs(obstacles) do
			if o ~= label and not label:IsDescendantOf(o) then
				local t = elementTop(o)
				if t and (not top or t < top) then top = t end
			end
		end
		-- Хотбар — препятствие для всех: подсказки с «родной» позицией в долях
		-- экрана (0.8–0.85 высоты) на невысоком окне ложились прямо на слоты.
		local bar = HudDock.hotbarTop()
		if bar and (not top or bar < top) then top = bar end
		local want = baseBottom
		if top then
			--[[ ⚠️ ДВЕ СИСТЕМЫ КООРДИНАТ, И В ЭТОМ БЫЛА ВСЯ БЕДА.
			     AbsolutePosition у любого GuiObject отсчитывается от нижней кромки
			     верхней панели Roblox (GuiInset), а Position подсказки — от верха её
			     ScreenGui. Если у того IgnoreGuiInset = true, верх ScreenGui — это
			     самый верх экрана, и число из AbsolutePosition надо сдвинуть вниз на
			     высоту панели, иначе подсказка встаёт на 58 px выше, чем задумано.
			     Три версии замера подряд давали «слишком высоко» ровно поэтому. ]]
			local screen = label:FindFirstAncestorWhichIsA("ScreenGui")
			if screen and screen.IgnoreGuiInset then
				top += GuiService:GetGuiInset().Y
			end
			want = math.min(baseBottom, top - gap)
		end

		local offset = base.Y.Offset + (want - baseBottom)
		--[[ СТОПКА: НАЛОЖЕНИЕ МЕРЯЕМ ПО ЭКРАННЫМ ПРЯМОУГОЛЬНИКАМ.
		     ⚠️ Свои координаты ПРЕДСКАЗЫВАЕМ, а не читаем после установки: Roblox
		     пересчитывает AbsolutePosition только к следующему кадру, и чтение
		     «сразу после Position =» отдавало прошлое положение — сдвиг копился
		     кадр за кадром, строка улетала вверх и мерцала. Пиксель смещения
		     Position.Offset равен пикселю AbsolutePosition, поэтому будущий низ
		     = нынешний низ + (новый Offset − нынешний Offset). Позицию ставим
		     ОДИН раз за кадр. ]]
		local curOff = label.Position.Y.Offset
		local predictedBottom = label.AbsolutePosition.Y + h + (offset - curOff)
		local lift = 0
		for _, other in ipairs(stack) do
			if other == label then break end
			if elementTop(other) then
				local myBottom = predictedBottom - lift
				local myTop = myBottom - h
				local oTop = other.AbsolutePosition.Y
				local oBottom = oTop + other.AbsoluteSize.Y
				if myBottom + gap > oTop and myTop < oBottom + gap then
					lift += (myBottom + gap) - oTop
				end
			end
		end
		local finalOff = offset - lift
		if math.abs(curOff - finalOff) > 0.5 or label.Position.Y.Scale ~= base.Y.Scale then
			label.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, finalOff)
		end
	end

	conn = RunService.RenderStepped:Connect(fit)
	fit()
	return conn
end

return HudDock
