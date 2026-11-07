local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- MonolithRepairUI.client.lua
-- Меню монолита дайвера — ОДНА панель, ДВА состояния (починка ⇄ улучшения),
-- по эталону «Monolith Menu Roblox.dc.html» (тёмно-синие токены меню классов:
-- панель #0e1f30, шапка со стад-паттерном, оранжевый X, зелёные кнопки).
-- Паутина/старение (K.agingOverlay) и 3D-превью дайвера УБРАНЫ — чистая панель.
-- Функционал кнопок и серверные события сохранены 1:1:
--   MonolithUI  "openRepair"(cost, order) / "repaired" / "result"(a, b)
--   MonolithAction:FireServer("repair")
--   DiverShopEvent "open"(data) / "update"(data)  + :FireServer("upgrade", key)
--   InventoryUpdate — кэш ресурсов для проверки «хватает/нет».

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local uiEvent        = ReplicatedStorage:WaitForChild("MonolithUI")
local actionEvent    = ReplicatedStorage:WaitForChild("MonolithAction")
local shopEvent      = ReplicatedStorage:WaitForChild("DiverShopEvent")
local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

-- общая кнопка закрытия: одна на все меню океана (см. UITheme.closeButton)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

---------------------------------------------------------------- токены

local C = {
	panelBg    = Color3.fromHex("0e1f30"),
	headerBg   = Color3.fromHex("1a3a58"),
	itemBg     = Color3.fromHex("12293d"),
	itemOn     = Color3.fromHex("173654"),
	iconBg     = Color3.fromHex("0a1826"),
	black      = Color3.fromHex("000000"),
	white      = Color3.fromHex("ffffff"),
	gold       = Color3.fromHex("ffd23a"),
	nameMuted  = Color3.fromHex("b8d0e4"),
	blueLabel  = Color3.fromHex("7fa8c9"),
	green      = Color3.fromHex("35b435"),
	greenBright= Color3.fromHex("35d435"),
	orange     = Color3.fromHex("e2571f"),
	orangeHov  = Color3.fromHex("f06a30"),
	orangeText = Color3.fromHex("3d1205"),
	muted      = Color3.fromHex("5a7a96"),
	gray       = Color3.fromHex("6a7f93"),
	red        = Color3.fromHex("c93a3a"),
	wood       = Color3.fromHex("c98a4a"),
}

local FONT_LAT  = Font.fromEnum(Enum.Font.LuckiestGuy)
local FONT_CYR  = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BODY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.Heavy)
local FONT_800  = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.ExtraBold)

---------------------------------------------------------------- геометрия

local PANEL_W, PANEL_H = 720, 460
local HEAD_H   = 78
local PAD      = 20
local CONTENT_X = PAD
local CONTENT_W = PANEL_W - PAD * 2       -- 680
local CONTENT_Y = HEAD_H + 4 + 16         -- 98
local GROUP_H   = PANEL_H - CONTENT_Y - PAD -- 342

---------------------------------------------------------------- данные

-- реальные иконки ресурсов (asset id из InventoryUI)
local ICONS = {
	Log        = "rbxassetid://116178347748793",
	Leaves     = "rbxassetid://96691360298069",
	Stone      = "rbxassetid://96450657403376",
	Iron_Ingot = "rbxassetid://72890243946368",
	Plastic    = "rbxassetid://132919988751848",
	Rubbish    = "rbxassetid://134054228230432",   -- та же, что в инвентаре
}
-- Подписи ресурсов для ценников. Улучшения монолита стоят не только дерева
-- (см. DiverShop.PRICES), поэтому здесь должны быть все используемые там
-- ресурсы — иначе в ценнике вместо названия покажется сырой английский ключ.
local RES = {
	Log        = { name = "Дерево",  image = ICONS.Log },
	Leaves     = { name = "Листва",  image = ICONS.Leaves },
	Stone      = { name = "Камень",  image = ICONS.Stone },
	Plastic    = { name = "Пластик", image = ICONS.Plastic },
	Iron_Ingot = { name = "Слиток",  image = ICONS.Iron_Ingot },
	Rubbish    = { name = "Мусор",   image = ICONS.Rubbish },
}
-- что дайвер приносит с моря (реальные иконки, а не стикеры)
local REWARDS = {
	{ image = "rbxassetid://82715612463476",  name = "Патроны" },
	{ image = "rbxassetid://137747693080979", name = "Еда" },
	{ image = ICONS.Log,                       name = "Ресурсы" },
}
local UPGRADE_META = {
	treasure = { icon = "💎", name = "Шанс сокровищ" },
	divers   = { icon = "🤿", name = "Кол-во дайверов" },
	crate    = { icon = "📦", name = "Размер коробок" },
}
local UPGRADE_ORDER = { "treasure", "divers", "crate" }

local function fmtPct(x)
	if x % 1 == 0 then return ("%d%%"):format(x) end
	return ("%.1f%%"):format(x)
end

local function effectText(key, lvl, max)
	if key == "treasure" then
		local cur = math.min(5 + 2.5 * (lvl - 1), 15)
		if lvl >= max then return fmtPct(cur) .. " (макс)" end
		return fmtPct(cur) .. " → " .. fmtPct(math.min(5 + 2.5 * lvl, 15))
	elseif key == "divers" then
		if lvl >= max then return lvl .. " (макс)" end
		return lvl .. " → " .. (lvl + 1)
	else
		local function range(l) return 0.2 + 0.2 * (l - 1), 3.0 + 0.2 * (l - 1) end
		local a, b = range(lvl)
		if lvl >= max then return ("%.1f–%.1f кг (макс)"):format(a, b) end
		local c, d = range(lvl + 1)
		return ("%.1f–%.1f → %.1f–%.1f кг"):format(a, b, c, d)
	end
end

-- кэш инвентаря
local inv = {}
inventoryEvent.OnClientEvent:Connect(function(t) if type(t) == "table" then inv = t end end)
local function have(name) return tonumber(inv[name]) or 0 end

---------------------------------------------------------------- хелперы

local function stroke(inst, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or C.black
	s.ApplyStrokeMode = inst:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

-- текст с чёрной обводкой и жёсткой тенью
local function displayText(parent, p)
	local main = Instance.new("TextLabel")
	main.BackgroundTransparency = 1
	main.FontFace = p.font
	main.Text = p.text
	main.TextSize = p.textSize
	main.TextColor3 = p.color
	main.Size = p.size
	main.Position = p.pos
	main.AnchorPoint = p.anchor or Vector2.new(0, 0)
	main.TextXAlignment = p.xAlign or Enum.TextXAlignment.Center
	main.TextYAlignment = p.yAlign or Enum.TextYAlignment.Center
	main.TextWrapped = p.wrapped or false
	main.ZIndex = p.zIndex or 4
	if p.scaled then
		main.TextScaled = true
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = p.textSize
		cap.Parent = main
	end
	if p.shadowY and p.shadowY > 0 then
		local sh = main:Clone()
		sh.TextColor3 = C.black
		sh.Position = p.pos + UDim2.fromOffset(0, p.shadowY)
		sh.ZIndex = main.ZIndex - 1
		sh.Name = "Shadow"
		if p.strokeT then stroke(sh, p.strokeT, C.black) end
		sh.Parent = parent
	end
	if p.strokeT then stroke(main, p.strokeT, C.black) end
	main.Parent = parent
	return main
end

local function addStuds(parent, w, h, step, dotD, color, transparency)
	parent.ClipsDescendants = true
	local half = step / 2
	for y = half, h + half, step do
		for x = half, w + half, step do
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(dotD, dotD)
			dot.Position = UDim2.fromOffset(x - dotD / 2, y - dotD / 2)
			dot.BackgroundColor3 = color
			dot.BackgroundTransparency = transparency
			dot.BorderSizePixel = 0
			-- ВАЖНО: выше фона родителя, иначе точки прячутся под его заливкой
			-- (ZIndex глобальный: точка с меньшим ZIndex рисуется под кнопкой)
			dot.ZIndex = (parent.ZIndex or 1) + 1
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = dot
			dot.Parent = parent
		end
	end
end

-- тёмный квадрат с иконкой: opts = { image = "rbxassetid://…" } либо { emoji, emojiPx }
local function iconBox(parent, x, y, size, opts)
	local box = Instance.new("Frame")
	box.Position = UDim2.fromOffset(x, y)
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundColor3 = C.iconBg
	box.BorderSizePixel = 0
	box.ZIndex = 3
	box.Parent = parent
	stroke(box, 2, C.black)
	if opts.image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = opts.image
		img.ScaleType = Enum.ScaleType.Fit
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.76, 0.76)
		img.ZIndex = 4
		img.Parent = box
	else
		local e = Instance.new("TextLabel")
		e.BackgroundTransparency = 1
		e.Size = UDim2.fromScale(1, 1)
		e.FontFace = FONT_CYR
		e.Text = opts.emoji or ""
		e.TextSize = opts.emojiPx or math.floor(size * 0.55)
		e.TextColor3 = C.white
		e.ZIndex = 4
		e.Parent = box
	end
	return box
end

-- чип «[иконка]  5 Дерево» — иконка реальный ImageLabel. Возвращает root, label.
local function makePill(parent, opts)
	local root = Instance.new("Frame")
	root.BackgroundColor3 = opts.bg or C.itemBg
	root.BackgroundTransparency = opts.transparent and 1 or 0
	root.Size = UDim2.fromOffset(10, opts.h or 32)
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BorderSizePixel = 0
	root.ZIndex = 4
	root.Parent = parent
	if not opts.transparent then stroke(root, 2, C.black) end
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 6)
	lay.Parent = root
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = root
	if opts.image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = opts.image
		img.ScaleType = Enum.ScaleType.Fit
		local isz = (opts.h or 32) - 8
		img.Size = UDim2.fromOffset(isz, isz)
		img.LayoutOrder = 1
		img.ZIndex = 5
		img.Parent = root
	end
	local lbl = Instance.new("TextLabel")
	lbl.Name = "PillText"
	lbl.BackgroundTransparency = 1
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size = UDim2.fromOffset(0, opts.h or 32)
	lbl.FontFace = FONT_BODY
	lbl.Text = opts.text or ""
	lbl.TextSize = opts.textSize or 18
	lbl.TextColor3 = opts.textColor or C.white
	lbl.LayoutOrder = 2
	lbl.ZIndex = 5
	lbl.Parent = root
	stroke(lbl, 1.5, C.black)
	return root, lbl
end

-- кнопка (стад-паттерн опционально); api: btn, setColor, setText
local function makeButton(parent, opts)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(opts.w, opts.h)
	if opts.x then btn.Position = UDim2.fromOffset(opts.x, opts.y) end
	btn.BackgroundColor3 = opts.color or C.green
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = parent
	stroke(btn, opts.strokeT or 4, C.black)
	if opts.studs then
		-- шаг/размер точек подстраиваем под высоту кнопки; тёмные точки
		-- видимой плотности (как на эталоне)
		local st = (opts.h < 50) and 22 or 30
		local dd = (opts.h < 50) and 7 or 9
		addStuds(btn, opts.w, opts.h, st, dd, C.black, 0.7)
	end
	local lbl = displayText(btn, {
		text = opts.text, font = FONT_CYR, textSize = opts.textSize or 24, color = C.white,
		size = UDim2.fromOffset(opts.w - 20, opts.h - 12), pos = UDim2.fromOffset(10, 6),
		strokeT = 2, shadowY = 2, zIndex = 6, scaled = true,
	})
	local base = opts.color or C.green
	local api = { btn = btn, label = lbl }
	function api.setColor(col) base = col; btn.BackgroundColor3 = col end
	function api.setText(t)
		lbl.Text = t
		local sh = btn:FindFirstChild("Shadow")
		if sh then sh.Text = t end
	end
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Color3.new(math.min(base.R * 1.1, 1), math.min(base.G * 1.1, 1), math.min(base.B * 1.1, 1))
	end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = base end)
	return api
end

---------------------------------------------------------------- окно

local gui = Instance.new("ScreenGui")
gui.Name = "MonolithMenuGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 130   -- выше трекера квестов (80), подсказок (60) и меню квестов (110): окно модальное
gui.Enabled = false
gui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = C.black
backdrop.BackgroundTransparency = 0.45
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3 = C.panelBg
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
stroke(panel, 4, C.black)

local uiScale = Instance.new("UIScale")
uiScale.Parent = panel
local function fit()
	local vp = gui.AbsoluteSize
	if vp.X < 1 then return end
	-- ×0.88: владелец просил окно «чуть меньше»; вписывание в экран как было
	uiScale.Scale = math.clamp(math.min(vp.X / (PANEL_W + 80), vp.Y / (PANEL_H + 120)), 0.45, 1) * 0.88
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- шапка
local header = Instance.new("Frame")
header.Size = UDim2.fromOffset(PANEL_W, HEAD_H)
header.BackgroundColor3 = C.headerBg
header.BorderSizePixel = 0
header.Parent = panel
addStuds(header, PANEL_W, HEAD_H, 30, 8, C.white, 0.94)
local headerLine = Instance.new("Frame")
headerLine.Size = UDim2.fromOffset(PANEL_W, 4)
headerLine.Position = UDim2.fromOffset(0, HEAD_H)
headerLine.BackgroundColor3 = C.black
headerLine.BorderSizePixel = 0
headerLine.Parent = panel

local titleLbl = displayText(header, {
	text = "", font = FONT_CYR, textSize = 30, color = C.white,
	size = UDim2.fromOffset(PANEL_W - 110, 40), pos = UDim2.fromOffset(20, 8),
	xAlign = Enum.TextXAlignment.Left, strokeT = 1.5, shadowY = 3, zIndex = 4, scaled = true,
})
local subLbl = Instance.new("TextLabel")
subLbl.BackgroundTransparency = 1
subLbl.FontFace = FONT_800
subLbl.Text = ""
subLbl.TextSize = 16
subLbl.TextColor3 = C.blueLabel
subLbl.TextXAlignment = Enum.TextXAlignment.Left
subLbl.Position = UDim2.fromOffset(20, 50)
subLbl.Size = UDim2.fromOffset(PANEL_W - 110, 22)
subLbl.ZIndex = 4
subLbl.Parent = header

--[[ ⚠️ КРЕСТИК ЗАКРЫТИЯ ПРИХОДИТ ИЗ UITheme, СВОЙ ЗДЕСЬ НЕ РИСУЕМ.
     Владелец требует одинаковую кнопку закрытия во всех меню океана, эталоном
     назвал инвентарь — общая фабрика UITheme.closeButton повторяет именно его.
     Размера здесь нет намеренно: он живёт в UITheme.CLOSE_SIZE, и менять его
     нужно там, разом для всех меню. Стоит начать передавать свой размер из
     каждого окна — крестики снова разъедутся, ровно так это уже вышло раньше
     (тут была картинка 62 px, в других меню — 30 px и буква X шрифтом).
     Посадку тоже не передаём: умолчание модуля и есть посадка инвентаря.
     Родитель — сама панель, а не шапка header: на шапке включён
     ClipsDescendants (его ставит addStuds под стад-паттерн), и кнопку у самой
     кромки там подрезало бы.
     ZIndex 12 оставлен прежним — он поднимает крестик над шапкой и её точками
     стад-паттерна, которые рисуются с меньшим индексом. ]]
local closeBtn = UITheme.closeButton({ parent = panel, zIndex = 12 })

local function hide() gui.Enabled = false end
closeBtn.MouseButton1Click:Connect(hide)
backdrop.MouseButton1Click:Connect(hide)

local function setHeader(broken)
	if broken then
		titleLbl.Text = "ПОЧИНИ МОНОЛИТ ДАЙВЕРА"
		subLbl.Text = "Дайвер оживёт и будет приносить коробки с моря"
		subLbl.TextColor3 = C.blueLabel
	else
		titleLbl.Text = "МОНОЛИТ ДАЙВЕРА"
		subLbl.Text = "Работает! Улучшай его, чтобы получать больше добычи"
		subLbl.TextColor3 = C.greenBright
	end
	local sh = header:FindFirstChild("Shadow")
	if sh then sh.Text = titleLbl.Text end
end

---------------------------------------------------------------- состояние: ПОЧИНКА

local repairGroup = Instance.new("CanvasGroup")
repairGroup.BackgroundTransparency = 1
repairGroup.Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y)
repairGroup.Size = UDim2.fromOffset(CONTENT_W, GROUP_H)
repairGroup.Visible = false
repairGroup.Parent = panel

local msgLbl, pillRow, repairBtn
local curCost, curOrder = nil, nil
local busy, transitioning = false, false

do
	-- «Дайвер приносит с моря:»
	local lead = Instance.new("TextLabel")
	lead.BackgroundTransparency = 1
	lead.FontFace = FONT_BODY
	lead.Text = "ДАЙВЕР ПРИНОСИТ С МОРЯ:"
	lead.TextSize = 15
	lead.TextColor3 = C.blueLabel
	lead.TextXAlignment = Enum.TextXAlignment.Left
	lead.Position = UDim2.fromOffset(0, 0)
	lead.Size = UDim2.fromOffset(CONTENT_W, 20)
	lead.Parent = repairGroup

	-- карточка с иконками
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(0, 26)
	card.Size = UDim2.fromOffset(CONTENT_W, 150)
	card.BackgroundColor3 = C.itemBg
	card.BorderSizePixel = 0
	card.Parent = repairGroup
	stroke(card, 3, C.black)

	local function boxWithLabel(x, iconOpts, labelText, bg)
		local box = iconBox(card, x, 22, 84, iconOpts)
		if bg then box.BackgroundColor3 = bg end
		local lb = Instance.new("TextLabel")
		lb.BackgroundTransparency = 1
		lb.FontFace = FONT_BODY
		lb.Text = labelText
		lb.TextSize = 15
		lb.TextColor3 = C.nameMuted
		lb.TextXAlignment = Enum.TextXAlignment.Center
		lb.Position = UDim2.fromOffset(x - 20, 112)
		lb.Size = UDim2.fromOffset(124, 20)
		lb.ZIndex = 4
		lb.Parent = card
		stroke(lb, 1, C.black)
	end

	boxWithLabel(40, { emoji = "📦", emojiPx = 42 }, "Коробки", C.iconBg)
	-- стрелка
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.FontFace = FONT_CYR
	arrow.Text = "→"
	arrow.TextSize = 40
	arrow.TextColor3 = C.gold
	arrow.Position = UDim2.fromOffset(150, 44)
	arrow.Size = UDim2.fromOffset(50, 40)
	arrow.ZIndex = 4
	arrow.Parent = card
	stroke(arrow, 1, C.black)

	local rx = { 250, 400, 550 }
	for i, r in ipairs(REWARDS) do
		boxWithLabel(rx[i], { image = r.image }, r.name, C.itemOn)
	end

	-- строка ошибки над кнопкой
	msgLbl = Instance.new("TextLabel")
	msgLbl.BackgroundTransparency = 1
	msgLbl.FontFace = FONT_800
	msgLbl.Text = ""
	msgLbl.TextSize = 15
	msgLbl.TextColor3 = C.red
	msgLbl.TextXAlignment = Enum.TextXAlignment.Center
	msgLbl.Position = UDim2.fromOffset(0, 186)
	msgLbl.Size = UDim2.fromOffset(CONTENT_W, 20)
	msgLbl.Parent = repairGroup

	-- «Необходимо:» + чипы
	local needRow = Instance.new("Frame")
	needRow.BackgroundTransparency = 1
	needRow.Position = UDim2.fromOffset(0, 210)
	needRow.Size = UDim2.fromOffset(CONTENT_W, 42)
	needRow.Parent = repairGroup
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0, 10)
	rl.Parent = needRow

	local needLbl = Instance.new("TextLabel")
	needLbl.BackgroundTransparency = 1
	needLbl.Size = UDim2.fromOffset(10, 42)
	needLbl.AutomaticSize = Enum.AutomaticSize.X
	needLbl.FontFace = FONT_BODY
	needLbl.Text = "Необходимо:"
	needLbl.TextSize = 18
	needLbl.TextColor3 = C.blueLabel
	needLbl.LayoutOrder = 1
	needLbl.Parent = needRow

	pillRow = Instance.new("Frame")
	pillRow.BackgroundTransparency = 1
	pillRow.Size = UDim2.fromOffset(10, 42)
	pillRow.AutomaticSize = Enum.AutomaticSize.X
	pillRow.LayoutOrder = 2
	pillRow.Parent = needRow
	local pr = Instance.new("UIListLayout")
	pr.FillDirection = Enum.FillDirection.Horizontal
	pr.VerticalAlignment = Enum.VerticalAlignment.Center
	pr.Padding = UDim.new(0, 8)
	pr.Parent = pillRow

	-- кнопка ПОЧИНИТЬ (во всю ширину, стад-паттерн)
	repairBtn = makeButton(repairGroup, {
		text = "ПОЧИНИТЬ", w = CONTENT_W, h = 64, x = 0, y = GROUP_H - 64,
		textSize = 34, studs = true, color = C.green,
	})
	repairBtn.btn.MouseButton1Click:Connect(function()
		if busy or transitioning then return end
		busy = true
		actionEvent:FireServer("repair")
		task.delay(1.2, function() if not transitioning then busy = false end end)
	end)
end

---------------------------------------------------------------- состояние: УЛУЧШЕНИЯ

--[[ Ценник улучшения: пары «иконка · число», без подписей. Владелец: «в ценах
     не пиши дер./лист., только иконки». Раньше плашка рождалась с одной
     картинкой бревна и строкой текста — иконка листвы и не могла появиться. ]]
local function fillCostPill(pill, costs)
	for _, ch in ipairs(pill:GetChildren()) do
		if ch:IsA("GuiObject") and ch.Name ~= "PillText" then ch:Destroy() end
	end
	local h = pill.AbsoluteSize.Y > 0 and pill.AbsoluteSize.Y or 27
	local isz = h - 6
	for i, c in ipairs(costs) do
		local info = RES[c.res]
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = info and info.image or ""
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(isz, isz)
		img.LayoutOrder = i * 2
		img.ZIndex = 5
		img.Parent = pill
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.AutomaticSize = Enum.AutomaticSize.X
		lbl.Size = UDim2.fromOffset(0, h)
		lbl.FontFace = FONT_BODY
		lbl.Text = tostring(c.amount)
		lbl.TextSize = 14
		lbl.TextColor3 = C.white
		lbl.LayoutOrder = i * 2 + 1
		lbl.ZIndex = 5
		lbl.Parent = pill
		stroke(lbl, 1.5, C.black)
	end
end

local upgradeGroup = Instance.new("CanvasGroup")
upgradeGroup.BackgroundTransparency = 1
upgradeGroup.Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y)
upgradeGroup.Size = UDim2.fromOffset(CONTENT_W, GROUP_H)
upgradeGroup.Visible = false
upgradeGroup.Parent = panel

local upgradeRows = {} -- key -> { badge, effLbl, btnApi, pill }
local lastUpgradeData = nil

local function buildUpgradeRow(y, key)
	local meta = UPGRADE_META[key]
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.fromOffset(CONTENT_W, 92)
	row.BackgroundColor3 = C.itemBg
	row.BorderSizePixel = 0
	row.Parent = upgradeGroup
	stroke(row, 3, C.black)

	iconBox(row, 14, 15, 62, { emoji = meta.icon, emojiPx = 32 })

	displayText(row, {
		text = meta.name, font = FONT_CYR, textSize = 20, color = C.white,
		size = UDim2.fromOffset(300, 26), pos = UDim2.fromOffset(90, 14),
		xAlign = Enum.TextXAlignment.Left, strokeT = 1, shadowY = 2, zIndex = 5,
	})

	local badge = Instance.new("TextLabel")
	badge.BackgroundColor3 = C.iconBg
	badge.Position = UDim2.fromOffset(90, 50)
	badge.Size = UDim2.fromOffset(58, 26)
	badge.FontFace = FONT_BODY
	badge.Text = "Ур. 1"
	badge.TextSize = 14
	badge.TextColor3 = C.white
	badge.BorderSizePixel = 0
	badge.ZIndex = 5
	badge.Parent = row
	stroke(badge, 2, C.black)

	local effLbl = Instance.new("TextLabel")
	effLbl.BackgroundTransparency = 1
	effLbl.FontFace = FONT_800
	effLbl.Text = ""
	effLbl.TextSize = 14
	effLbl.TextColor3 = C.blueLabel
	effLbl.TextXAlignment = Enum.TextXAlignment.Left
	effLbl.Position = UDim2.fromOffset(158, 51)
	effLbl.Size = UDim2.fromOffset(230, 22)
	effLbl.ZIndex = 5
	effLbl.Parent = row

	-- правая колонка: кнопка УЛУЧШИТЬ + чип цены
	local col = Instance.new("Frame")
	col.BackgroundTransparency = 1
	col.AnchorPoint = Vector2.new(1, 0.5)
	col.Position = UDim2.new(1, -14, 0.5, 0)
	col.Size = UDim2.fromOffset(180, 74)
	col.ZIndex = 5
	col.Parent = row
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Vertical
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cl.VerticalAlignment = Enum.VerticalAlignment.Center
	cl.Padding = UDim.new(0, 6)
	cl.Parent = col

	local b = makeButton(col, { text = "УЛУЧШИТЬ", w = 176, h = 40, textSize = 18, strokeT = 3, color = C.green, studs = true })
	b.btn.LayoutOrder = 1
	local pillRoot, pillLbl = makePill(col, { text = "", bg = C.green, h = 27, textSize = 14 })
	pillLbl.Visible = false   -- цену рисуем парами «иконка + число», см. fillCostPill
	pillRoot.LayoutOrder = 2

	b.btn.MouseButton1Click:Connect(function()
		shopEvent:FireServer("upgrade", key)
	end)
	upgradeRows[key] = { badge = badge, effLbl = effLbl, btnApi = b, pill = pillRoot, pillLbl = pillLbl }
end

do
	local ry = { 6, 121, 236 }
	for i, key in ipairs(UPGRADE_ORDER) do
		buildUpgradeRow(ry[i], key)
	end
end

local function updateUpgradeRows(data)
	lastUpgradeData = data or lastUpgradeData
	if not lastUpgradeData then return end
	for _, entry in ipairs(lastUpgradeData) do
		local refs = upgradeRows[entry.key]
		if refs then
			refs.badge.Text = "Ур. " .. entry.lvl
			refs.effLbl.Text = effectText(entry.key, entry.lvl, entry.max)
			local maxed = entry.lvl >= entry.max
			if maxed then
				refs.btnApi.setText("МАКС")
				refs.btnApi.setColor(C.gray)
				refs.pill.Visible = false
			else
				--[[ ⚠️ ЦЕНА — СПИСОК, А НЕ ОДИН РЕСУРС (см. лестницу в DiverShop).
				     Хватает — только если хватает КАЖДОЙ позиции. Старый одиночный
				     costName/costAmount сервер шлёт по-прежнему, на него и падаем,
				     если списка нет (старый сервер). ]]
				local costs = entry.costs
				if type(costs) ~= "table" or #costs == 0 then
					costs = { { res = entry.costName, amount = entry.costAmount } }
				end
				local afford = true
				for _, c in ipairs(costs) do
					if have(c.res) < c.amount then afford = false end
				end
				refs.btnApi.setText("УЛУЧШИТЬ")
				refs.btnApi.setColor(C.green)
				refs.pill.Visible = true
				fillCostPill(refs.pill, costs)
				refs.pill.BackgroundColor3 = afford and C.green or C.red
			end
		end
	end
end

---------------------------------------------------------------- переключение состояний

-- пересобрать чипы «Необходимо» из curCost/curOrder + инвентарь
local function refresh()
	if not curCost then return end
	-- чистим СТАРЫЕ чипы (это Frame'ы), UIListLayout не трогаем. Раньше
	-- удалялись только TextLabel'ы — из-за этого чипы накапливались.
	for _, ch in ipairs(pillRow:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	local allOk = true
	for _, resName in ipairs(curOrder) do
		local needed = curCost[resName] or 0
		local ok = have(resName) >= needed
		if not ok then allOk = false end
		local info = RES[resName] or { name = resName }
		-- без плашки: только иконка + крупный текст (зелёный/красный по наличию)
		makePill(pillRow, {
			image = info.image, text = needed .. " " .. info.name,
			transparent = true, textColor = ok and C.greenBright or C.red,
			h = 46, textSize = 22,
		})
	end
	repairBtn.setColor(allOk and C.green or C.gray)
	return allOk
end

local function showRepair(cost, order)
	curCost, curOrder = cost, order or { "Log", "Leaves" }
	msgLbl.Text = ""
	busy, transitioning = false, false
	setHeader(true)
	repairGroup.GroupTransparency = 0
	repairGroup.Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y)
	repairGroup.Visible = true
	upgradeGroup.Visible = false
	refresh()
	gui.Enabled = true
end

local function showUpgrade()
	setHeader(false)
	repairGroup.Visible = false
	upgradeGroup.GroupTransparency = 0
	upgradeGroup.Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y)
	upgradeGroup.Visible = true
	gui.Enabled = true
end

-- переход починки → улучшения (без паутины): гасим ремонт, проявляем апгрейды
local function playRepairTransition()
	if transitioning then return end
	transitioning = true
	busy = true
	TweenService:Create(repairGroup, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 1 }):Play()
	task.delay(0.35, function()
		if not (gui and gui.Enabled) then transitioning = false; busy = false; return end
		repairGroup.Visible = false
		setHeader(false)
		upgradeGroup.GroupTransparency = 1
		upgradeGroup.Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y + 6)
		upgradeGroup.Visible = true
		TweenService:Create(upgradeGroup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0, Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y) }):Play()
		task.delay(0.3, function() transitioning = false; busy = false end)
	end)
end

local function shake()
	local base = UDim2.fromScale(0.5, 0.5)
	for i = 1, 4 do
		local dx = (i % 2 == 0) and 0.01 or -0.01
		TweenService:Create(panel, TweenInfo.new(0.05), { Position = base + UDim2.fromScale(dx, 0) }):Play()
		task.wait(0.05)
	end
	panel.Position = base
end

local function floatToast(text)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0.16, 0)
	t.Size = UDim2.fromOffset(380, 46)
	t.BackgroundColor3 = C.headerBg
	t.BorderSizePixel = 0
	t.FontFace = FONT_800
	t.Text = text
	t.TextSize = 18
	t.TextScaled = true
	t.TextColor3 = C.white
	t.ZIndex = 50
	t.Parent = gui
	stroke(t, 3, C.black)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 18
	cap.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = t
	gui.Enabled = true
	task.delay(1.6, function()
		TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.45)
		t:Destroy()
	end)
end

---------------------------------------------------------------- события

uiEvent.OnClientEvent:Connect(function(kind, a, b)
	if kind == "openRepair" then
		showRepair(a, b)
	elseif kind == "repaired" then
		if gui.Enabled and repairGroup.Visible then
			playRepairTransition()
		end
	elseif kind == "result" then
		if a == "success" then
			if gui.Enabled and repairGroup.Visible then
				playRepairTransition()
			end
		elseif a == "notEnough" then
			busy = false
			refresh()
			local parts = {}
			for _, resName in ipairs(curOrder or { "Log", "Leaves" }) do
				local m = b and b[resName]
				if m and m > 0 then
					table.insert(parts, (RES[resName] and RES[resName].name or resName) .. " " .. m)
				end
			end
			msgLbl.Text = "Не хватает: " .. table.concat(parts, ", ")
			shake()
		elseif a == "tooFar" then
			busy = false
			floatToast("Подойди ближе к монолиту")
		elseif a == "cutscene" then
			busy = false
			floatToast("Подожди, идёт сцена зачистки острова")
		elseif a == "already" then
			showUpgrade()
		else
			busy = false
			msgLbl.Text = "Не получилось, попробуй ещё раз"
		end
	end
end)

shopEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "open" then
		showUpgrade()
		updateUpgradeRows(data)
	elseif kind == "update" then
		updateUpgradeRows(data)
	end
end)

inventoryEvent.OnClientEvent:Connect(function()
	if gui.Enabled then
		if repairGroup.Visible and curCost then refresh() end
		if upgradeGroup.Visible then updateUpgradeRows(nil) end
	end
end)

print("[MonolithRepairUI] rebuilt (new design, no cobwebs)")
