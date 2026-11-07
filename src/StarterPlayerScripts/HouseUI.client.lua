local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	МЕНЮ УПРАВЛЕНИЯ ДОМОМ — по хендофу House Menu (README.md в корне).

	Открывается жёлтой кнопкой «Управление» на табличке дома. Слева список
	жителей и строка «Добавить жителя», справа карточка выбранного, сетка
	профессий и блок бонусов дома.

	⚠️ РЕШАЕТ СЕРВЕР, РИСУЕТ КЛИЕНТ.
	Заселение тратит жителя из общего населения, выселение возвращает, а замок на
	профессии — правило баланса. Всё это проверяется в HouseSystem; здесь только
	отправка действия и отрисовка ответа. Иначе профессию можно было бы выдать в
	обход замка, а жителя завести из воздуха.

	⚠️ HTML-ПРОТОТИП В ИГРУ НЕ ПЕРЕНОСИТСЯ — повторяется только внешний вид.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("HouseDefs"))
-- общий модуль оформления: отсюда берётся единая кнопка закрытия (UITheme.closeButton)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local menuEvent = ReplicatedStorage:WaitForChild("HouseMenu")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UI = Defs.UI2

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function outline(inst, thickness)
	return new("UIStroke", {
		Thickness = thickness or 3, Color = Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

local function textStroke(inst)
	return new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, inst)
end

local function gradient(inst, top, bottom, rotation)
	return new("UIGradient", {
		Rotation = rotation or 90,
		Color = ColorSequence.new(top, bottom),
	}, inst)
end

-- ═══════════ каркас ═══════════

local gui = new("ScreenGui", {
	Name = "HouseMenuGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 92, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
}, playerGui)
_G.HouseManageScreenGui = gui

local dim = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 20, 33),
	BackgroundTransparency = 0.35, BorderSizePixel = 0,
}, gui)

-- ⚠️ ПАНЕЛЬ ДЕТЕЙ НЕ РЕЖЕТ (ClipsDescendants = false).
-- Флаг достался от прежнего крестика: тот сидел центром в углу окна и половиной
-- картинки торчал наружу, обрезка оставила бы от него четверть. Общая кнопка
-- закрытия целиком внутри панели, так что резать теперь нечего — и включать
-- обрезку тоже незачем: за края не выходит ничего, а список жителей клипает
-- себя сам, он в ScrollingFrame.
local panel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(880, 520), BackgroundColor3 = UI.PANEL,
	BorderSizePixel = 0, ZIndex = 2, ClipsDescendants = false,
}, gui)
outline(panel, 4)
local panelScale = new("UIScale", { Scale = 1 }, panel)

-- ── шапка ──
local head = new("Frame", {
	Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = UI.HEAD_TOP,
	BorderSizePixel = 0, ZIndex = 3,
}, panel)
gradient(head, UI.HEAD_TOP, UI.HEAD_BOT)
new("Frame", {   -- border-bottom 4px
	Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4),
	BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 4,
}, head)

local headTitle = new("TextLabel", {
	Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -80, 0, 26),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", ZIndex = 4,
}, head)
textStroke(headTitle)

local headSub = new("TextLabel", {
	Position = UDim2.fromOffset(16, 33), Size = UDim2.new(1, -80, 0, 18),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = UI.MUTED, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", ZIndex = 4,
}, head)

--[[ ⚠️ КРЕСТИК ЗАКРЫТИЯ ОБЩИЙ, ЭТАЛОН ВЛАДЕЛЬЦА — ИНВЕНТАРЬ.
     Игрок считает крестик одним и тем же элементом управления во всех меню
     океана, а он от окна к окну был разный: здесь стояла своя картинка на 62 px,
     которая ещё и подрастала на наведении, в инвентаре — маленький красный
     квадрат. Разнобой читается как небрежность, поэтому кнопку целиком делает
     UITheme.closeButton, повторяющий инвентарный образец.
     Размер сюда не передаётся и передать его нельзя: он живёт в
     UITheme.CLOSE_SIZE. Понадобится другой — правится там одним числом сразу во
     всех меню, иначе крестики разъедутся снова, ровно как в прошлый раз.
     Посадку тоже не задаём: умолчание модуля (правый верхний угол панели) — это
     и есть посадка инвентаря.
     Родитель — САМА ПАНЕЛЬ, а не шапка, и ZIndex 5 сохранён: кнопка должна лежать
     поверх шапки (ZIndex 3) и её нижней кромки (4).
     Клик подключается ниже, где объявлен closeMenu. ]]
local closeBtn = UITheme.closeButton({ parent = panel, zIndex = 5 })

-- ── левая колонка ──
local left = new("Frame", {
	Position = UDim2.fromOffset(0, 62), Size = UDim2.new(0, 300, 1, -62),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.82,
	BorderSizePixel = 0, ZIndex = 3,
}, panel)
new("Frame", {   -- border-right 4px
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0, ZIndex = 4,
}, left)

local listTitle = new("TextLabel", {
	Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 15,
	TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Жители дома", ZIndex = 4,
}, left)
textStroke(listTitle)

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, -4, 1, -60),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 4,
}, left)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local listFoot = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -6),
	Size = UDim2.new(1, -24, 0, 18), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.MUTED2,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 4,
}, left)

-- ── правая часть ──
local right = new("Frame", {
	Position = UDim2.fromOffset(304, 62), Size = UDim2.new(1, -304, 1, -62),
	BackgroundTransparency = 1, ZIndex = 3,
}, panel)
new("UIPadding", {
	PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, right)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
}, right)

-- карточка выбранного
local cardTop = new("Frame", {
	LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, ZIndex = 4,
}, right)

local bigDot = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(0, 6),
	Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Color3.fromRGB(196, 154, 108),
	BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextSize = 28,
	TextColor3 = Color3.fromRGB(40, 28, 14), Text = "", ZIndex = 5,
}, cardTop)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, bigDot)
outline(bigDot, 3)

local bigName = new("TextLabel", {
	Position = UDim2.fromOffset(76, 8), Size = UDim2.new(1, -80, 0, 26),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", ZIndex = 5,
}, cardTop)
textStroke(bigName)

local chipRow = new("Frame", {
	Position = UDim2.fromOffset(76, 38), Size = UDim2.new(1, -80, 0, 26),
	BackgroundTransparency = 1, ZIndex = 5,
}, cardTop)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
}, chipRow)

local function chip(order, color, text)
	local c = new("Frame", {
		LayoutOrder = order, BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6, BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 24), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5,
	}, chipRow)
	outline(c, 2)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, c)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = color, Text = text, ZIndex = 6,
		Size = UDim2.fromOffset(10, 24), AutomaticSize = Enum.AutomaticSize.X,
	}, c)
	textStroke(l)
	return c, l
end

local chipType, chipTypeLbl = chip(1, UI.MUTED, "")
local chipAge, chipAgeLbl   = chip(2, Color3.new(1, 1, 1), "")
local chipEff, chipEffLbl   = chip(3, UI.GOLD, "")
local chipFarm, chipFarmLbl = chip(4, Color3.fromRGB(226, 214, 168), "")   -- назначенная ферма

local evictBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 10),
	Size = UDim2.fromOffset(120, 34), BackgroundColor3 = UI.BLUE_TOP,
	BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamBlack,
	TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = "Выселить", ZIndex = 6,
}, cardTop)
gradient(evictBtn, UI.BLUE_TOP, UI.BLUE_BOT)
outline(evictBtn, 3)

local typeBonus = new("TextLabel", {
	LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.MUTED,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 4,
}, right)

-- сетка профессий 3 колонки
local jobsGrid = new("Frame", {
	LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 190), BackgroundTransparency = 1, ZIndex = 4,
}, right)
new("UIGridLayout", {
	CellSize = UDim2.new(0.333, -8, 0, 58), CellPadding = UDim2.fromOffset(8, 8),
	SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 3,
}, jobsGrid)

-- бонусы дома
local bonusBox = new("Frame", {
	LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 4,
}, right)
outline(bonusBox, 3)
local bonusText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextWrapped = true,
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.MUTED, Text = "", ZIndex = 5,
}, bonusBox)

-- ── тост ──
local toast = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(10, 34), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
	BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14,
	TextColor3 = UI.GOLD, Text = "", Visible = false, ZIndex = 30,
}, gui)
-- золотая рамка тоста по хендофу — именно рамка, а не обводка букв
new("UIStroke", {
	Thickness = 2, Color = UI.GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toast)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
}, toast)

local toastToken = 0
local function showToast(text)
	toastToken += 1
	local mine = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(2.2, function()
		if toastToken == mine then toast.Visible = false end
	end)
end

-- ═══════════ состояние ═══════════

local house = nil        -- модель дома, чьё меню открыто
local data = nil         -- последний payload с сервера
local selectedId = nil
local refresh            -- объявлен заранее: на него ссылается клик по строке

local function unlockedSet()
	local set = {}
	for _, id in ipairs(data and data.unlocked or {}) do set[id] = true end
	return set
end

local function residentById(id)
	for _, r in ipairs(data and data.residents or {}) do
		if r.id == id then return r end
	end
	return nil
end

local function firstChar(name)
	if not name or name == "" then return "?" end
	return name:sub(1, utf8.offset(name, 2) - 1)
end

-- ═══════════ отрисовка ═══════════

local function drawList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	for i, r in ipairs(data.residents) do
		local chosen = (r.id == selectedId)
		local row = new("TextButton", {
			LayoutOrder = i, Size = UDim2.new(1, 0, 0, 56), AutoButtonColor = false,
			BackgroundColor3 = UI.GOLD, BackgroundTransparency = chosen and 0.88 or 1,
			BorderSizePixel = 0, Text = "", ZIndex = 5,
		}, list)
		new("Frame", {   -- border-bottom 2.5px
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0, ZIndex = 6,
		}, row)

		local dot = new("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Color3.fromRGB(196, 154, 108),
			BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextSize = 18,
			TextColor3 = Color3.fromRGB(40, 28, 14), Text = firstChar(r.name), ZIndex = 6,
		}, row)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		-- Border, а не Contextual: на TextLabel обводка по умолчанию ложится на
		-- БУКВУ, и вместо золотого кольца у выбранного жителя обводился инициал
		new("UIStroke", {
			Thickness = 3, Color = chosen and UI.GOLD or Color3.new(0, 0, 0),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, dot)

		local nm = new("TextLabel", {
			Position = UDim2.fromOffset(56, 9), Size = UDim2.new(1, -160, 0, 18),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			Text = ("%s %s"):format(r.name, string.rep("★", r.stars or 1)), ZIndex = 6,
		}, row)
		textStroke(nm)

		local job = Defs.jobById(r.job)
		new("TextLabel", {
			Position = UDim2.fromOffset(56, 29), Size = UDim2.new(1, -160, 0, 16),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = job.color, TextXAlignment = Enum.TextXAlignment.Left,
			Text = r.farmName and (job.name .. " · " .. r.farmName) or job.name, ZIndex = 6,   -- у фермера — и его ферма
		}, row)

		local t = Defs.TYPES[r.type] or Defs.TYPES.worker
		local badge = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(84, 24), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6, BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = t.color,
			Text = t.label, ZIndex = 6,
		}, row)
		outline(badge, 2)

		row.Activated:Connect(function()
			selectedId = r.id
			refresh()
		end)
	end

	-- строка «Добавить жителя» — прямо в списке, только при свободных местах
	if #data.residents < data.capacity then
		local add = new("TextButton", {
			LayoutOrder = 999, Size = UDim2.new(1, 0, 0, 56), AutoButtonColor = false,
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", ZIndex = 5,
		}, list)

		local circle = new("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = UI.GREEN,
			Text = "+", ZIndex = 6,
		}, add)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, circle)
		-- зелёное кольцо вокруг «+», а не обводка самого плюса
		new("UIStroke", {
			Thickness = 3, Color = UI.GREEN, Transparency = 0.25,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, circle)

		new("TextLabel", {
			Position = UDim2.fromOffset(56, 11), Size = UDim2.new(1, -70, 0, 18),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 14,
			TextColor3 = UI.GREEN, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Добавить жителя", ZIndex = 6,
		}, add)
		new("TextLabel", {
			Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -70, 0, 16),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = UI.MUTED2, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Цена: 1 житель", ZIndex = 6,
		}, add)

		add.Activated:Connect(function()
			menuEvent:FireServer("add", house)
		end)
	end

	listFoot.Text = ("Свободных мест: %d"):format(math.max(0, data.capacity - #data.residents))
end

local function drawJobs()
	for _, child in ipairs(jobsGrid:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local unlocked = unlockedSet()
	local res = residentById(selectedId)

	for i, job in ipairs(Defs.JOBS) do
		local open = unlocked[job.id] == true
		local active = res and res.job == job.id

		local cell = new("TextButton", {
			LayoutOrder = i, AutoButtonColor = false, BorderSizePixel = 0, Text = "",
			BackgroundColor3 = active and UI.GREEN or (open and UI.HEAD_BOT or UI.LOCKED),
			BackgroundTransparency = open and 0 or 0.08, ZIndex = 5,
		}, jobsGrid)
		outline(cell, 3)
		if active then gradient(cell, UI.GREEN, UI.GREEN_MID) end

		local icon = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(18, 18), BorderSizePixel = 0, ZIndex = 6,
			BackgroundColor3 = open and job.color or UI.STEEL,
		}, cell)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, icon)
		outline(icon, 2)

		local nm = new("TextLabel", {
			Position = UDim2.fromOffset(34, 10), Size = UDim2.new(1, -44, 0, 18),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 14,
			TextColor3 = open and Color3.new(1, 1, 1) or UI.STEEL,
			TextXAlignment = Enum.TextXAlignment.Left, Text = job.name, ZIndex = 6,
		}, cell)
		textStroke(nm)

		new("TextLabel", {
			Position = UDim2.fromOffset(34, 29), Size = UDim2.new(1, -44, 0, 16),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = active and Color3.fromRGB(255, 233, 160)
				or (open and UI.MUTED2 or UI.STEEL),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = open and job.effect or "Заблокировано", ZIndex = 6,
		}, cell)

		if not open then
			-- иконка замка в правом верхнем углу
			local lock = new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5),
				Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = UI.STEEL,
				Text = "🔒", ZIndex = 7,
			}, cell)
			textStroke(lock)
		end

		cell.Activated:Connect(function()
			if not selectedId then
				showToast("Сначала выберите жителя")
				return
			end
			if not open then
				showToast(("Профессия «%s» пока заблокирована"):format(job.name))
				return
			end
			menuEvent:FireServer("job", house, selectedId, job.id)
		end)
	end
end

refresh = function()
	if not data then return end

	local comfort = math.floor(data.level * Defs.COMFORT_PER_LEVEL * 100 + 0.5)
	headTitle.Text = ("%s — уровень %d"):format(data.houseName, data.level)
	headSub.Text = ("Жители: %d / %d • Комфорт: +%d%% к работе")
		:format(#data.residents, data.capacity, comfort)

	if selectedId and not residentById(selectedId) then selectedId = nil end
	if not selectedId and data.residents[1] then selectedId = data.residents[1].id end

	drawList()

	local res = residentById(selectedId)
	local has = res ~= nil
	bigDot.Visible = has; bigName.Visible = has; chipRow.Visible = has
	evictBtn.Visible = has; typeBonus.Visible = has

	if has then
		local t = Defs.TYPES[res.type] or Defs.TYPES.worker
		local age = Defs.AGES[res.age] or Defs.AGES.adult
		bigDot.Text = firstChar(res.name)
		bigName.Text = ("%s %s"):format(res.name, string.rep("★", res.stars or 1))
		chipTypeLbl.Text = t.label
		chipTypeLbl.TextColor3 = t.color
		chipAgeLbl.Text = ("%s, %d"):format(age.label, res.years or 0)
		chipEffLbl.Text = ("Эффективность: %d%%"):format(math.floor(res.eff * 100 + 0.5))
		chipFarm.Visible = res.farmName ~= nil
		chipFarmLbl.Text = res.farmName and ("🐑 " .. res.farmName) or ""
		typeBonus.Text = ("%s: %s"):format(t.label, t.bonus)
	end

	drawJobs()

	bonusBox.Visible = true
	bonusText.Text = ("Уровень %d: +%d%% к эффективности жителей • Вместимость %d • Следующий уровень: +%d%% и +1 место.")
		:format(data.level, comfort, data.capacity,
			math.floor((data.level + 1) * Defs.COMFORT_PER_LEVEL * 100 + 0.5))
end

-- ═══════════ открытие ═══════════

-- ⚠️ НА НИЗКИХ ЭКРАНАХ ПАНЕЛЬ НЕ ОБРЕЗАЕТСЯ, А УЖИМАЕТСЯ ЦЕЛИКОМ.
-- 880×520 — размер из хендофа; ниже него панель просто не влезет, и обрезка
-- съела бы сетку профессий снизу.
local function fitTarget()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.Y < 1 then return 1 end
	return math.clamp(math.min(vp.X * 0.92 / 880, vp.Y * 0.92 / 520), 0.5, 1)
end

local function fitScreen()
	panelScale.Scale = fitTarget()
end

local function openFor(model)
	house = model
	selectedId = nil
	gui.Enabled = true
	local target = fitTarget()
	-- открытие: scale 0.8 → 1 с лёгким перелётом, 0.35 с
	panelScale.Scale = target * 0.8
	TweenService:Create(panelScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = target }):Play()
	menuEvent:FireServer("open", model)
end

local function closeMenu()
	gui.Enabled = false
	house = nil
	menuEvent:FireServer("close")
end

closeBtn.Activated:Connect(closeMenu)
evictBtn.Activated:Connect(function()
	if selectedId then menuEvent:FireServer("evict", house, selectedId) end
end)

menuEvent.OnClientEvent:Connect(function(kind, arg)
	if kind == "data" then
		data = arg
		refresh()
	elseif kind == "toast" then
		showToast(tostring(arg))
	elseif kind == "select" then
		selectedId = arg
		refresh()
	end
end)

-- ═══════════ кнопка «Управление» на доме ═══════════

-- ⚠️ ДОМА ПОЯВЛЯЮТСЯ ПО ХОДУ ИГРЫ.
-- Их строят молотком, значит одного прохода по Workspace на старте мало.
-- Слушаем и то, что уже стоит, и то, что появится; SurfaceGui приходит с сервера
-- на кадр-другой позже самой модели, поэтому пробуем несколько раз.
local hooked = {}

-- ⚠️ ОСНОВНОЙ ВХОД — ПОДСКАЗКА У ДВЕРИ, КНОПКА НА ТАБЛИЧКЕ ВТОРИЧНА.
-- Табличка висит над крышей: попасть по ней курсором с земли нельзя, а клик по
-- SurfaceGui в мире и без того требует прямой видимости детали. Ждём
-- ProximityPrompt, который вешает сервер на дверь; кнопку подключаем тоже — если
-- по ней всё-таки кликнут, откроется то же меню.
local function hookHouse(model)
	if hooked[model] then return true end

	local prompt = model:FindFirstChild("HouseManagePrompt", true)
	if not prompt then return false end
	hooked[model] = true
	prompt.Triggered:Connect(function(who)
		if who == player then openFor(model) end
	end)

	local part
	for _, name in ipairs(Defs.INFO_NAMES) do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then part = p break end
	end
	local surface = part and part:FindFirstChild("HouseInfo")
	local btn = surface and surface:FindFirstChild("ManageBtn", true)
	if btn then
		btn.Activated:Connect(function() openFor(model) end)
	end
	return true
end

local function watch(inst)
	if inst:IsA("Model") and inst.Name == Defs.MODEL then
		task.spawn(function()
			for _ = 1, 40 do
				if hookHouse(inst) then return end
				task.wait(0.25)
			end
		end)
	end
end

for _, child in ipairs(Workspace:GetChildren()) do watch(child) end
Workspace.ChildAdded:Connect(watch)

task.spawn(function()
	local cam = Workspace.CurrentCamera
	while not cam do task.wait(0.2); cam = Workspace.CurrentCamera end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if gui.Enabled then fitScreen() end
	end)
end)

print("[Дом/клиент] меню управления готово")
