local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- WeaponCollectionMenu.client.lua
-- Меню коллекции по эталону «Collection Menu Roblox.dc.html» (тёмно-синие
-- токены меню классов). Две панели:
--   ЛЕВАЯ  — «КОЛЛЕКЦИЯ ПУШЕК»: сетка карточек (иконка + фон редкости +
--            звёзды), клик подсвечивает карточку. Данные: WeaponCollectionCatalog
--            + RemoteFunction GetWeaponCollection (как раньше).
--   ПРАВАЯ — «ПОКАЗАТЬ ИНФОРМАЦИЮ»: ВЫБРАННЫЙ КЛАСС игрока и какие баффы
--            СЕЙЧАС действуют (по уровню класса), + «НАЙДЕНЫ СОКРОВИЩА».
-- Класс читается из общих атрибутов (ClassSelected / ClassLvl_<id>), которые
-- ставит PirateProgression по данным из лобби.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Catalog   = require(ReplicatedStorage:WaitForChild("WeaponCollectionCatalog"))
local getColl   = ReplicatedStorage:WaitForChild("GetWeaponCollection")

local Config    = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
-- общая кнопка закрытия: один крестик на все меню (см. UITheme.closeButton)
local UITheme   = require(ReplicatedStorage:WaitForChild("UITheme"))

---------------------------------------------------------------- токены

local C = {
	panelBg   = Color3.fromHex("0e1f30"),
	headerBg  = Color3.fromHex("1a3a58"),
	itemBg    = Color3.fromHex("12293d"),
	iconBg    = Color3.fromHex("0a1826"),
	notOwned  = Color3.fromHex("1a2530"),
	black     = Color3.fromHex("000000"),
	white     = Color3.fromHex("ffffff"),
	gold      = Color3.fromHex("ffd23a"),
	goldText  = Color3.fromHex("3d2a05"),
	nameMuted = Color3.fromHex("b8d0e4"),
	blueLabel = Color3.fromHex("7fa8c9"),
	muted     = Color3.fromHex("5a7a96"),
	green     = Color3.fromHex("35d435"),
	orange    = Color3.fromHex("e2571f"),
	orangeHov = Color3.fromHex("f06a30"),
	orangeText= Color3.fromHex("3d1205"),
}

local FONT_LAT  = Font.fromEnum(Enum.Font.LuckiestGuy)
local FONT_CYR  = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BODY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.Heavy)
local FONT_800  = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.ExtraBold)

-- цвета рамок редкости (для карточек) — палитра эталона
local RARITY_BORDER = {
	gray      = Color3.fromHex("9aa5b0"),
	green     = Color3.fromHex("7fe07a"),
	blue      = Color3.fromHex("7fc0ff"),
	epic      = Color3.fromHex("c88fe8"),
	legendary = Color3.fromHex("c88fe8"),
}

-- баффы классов (то, что реально действует по уровню) + иконка/имя
local CLASS_BUFFS = {
	diver = {
		icon = "\u{2693}\u{FE0F}", -- ⚓
		name = "ДАЙВЕР",
		perks = {
			"Полная защита от радиации океана",
			"Дольше находишься под водой",
			"2× шанс редких сокровищ от дайверов",
		},
	},
	survivor = {
		icon = "\u{1F480}", -- 💀
		name = "ВЫЖИВШИЙ",
		perks = {
			"Медленнее расходуются голод и жажда",
			"Повышенный урон от оружия",
			"2× к населению при освобождении островов",
		},
	},
}

---------------------------------------------------------------- геометрия

local LEFT_W, RIGHT_W, GAP = 560, 380, 20
local PANEL_H  = 500
local L_HEAD_H = 64
local R_HEAD_H = 60
local COLS     = 5

---------------------------------------------------------------- хелперы

local function stroke(inst, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or C.black
	s.ApplyStrokeMode = inst:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

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
			dot.ZIndex = (parent.ZIndex or 1) + 1
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = dot
			dot.Parent = parent
		end
	end
end

-- зелёная галочка из фреймов (глиф ✔ рисуется тускло/как эмодзи — делаем сами)
local function drawCheck(parent, cx, cy, scale, color, z)
	scale = scale or 1
	color = color or C.green
	local function bar(x, y, len, thick, rot, col, zz)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(cx + x * scale, cy + y * scale)
		f.Size = UDim2.fromOffset(len * scale, thick * scale)
		f.Rotation = rot
		f.BackgroundColor3 = col
		f.BorderSizePixel = 0
		f.ZIndex = zz
		f.Parent = parent
	end
	bar(-4, 6, 16, 11, 45, C.black, z)
	bar(4, 0, 26, 11, -50, C.black, z)
	bar(-4, 5, 12, 6, 45, color, z + 1)
	bar(4, -1, 22, 6, -50, color, z + 1)
end

-- строка звёзд (полные + одна половинка) из иконок каталога
local function fillStars(parent, rating, size)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("ImageLabel") then c:Destroy() end
	end
	rating = math.clamp(tonumber(rating) or 0, 0, 5)
	local full  = math.floor(rating)
	local half  = (rating - full) >= 0.5
	local count = full + (half and 1 or 0)
	local gap   = 2
	parent.Size = UDim2.fromOffset(math.max(count * size + (count - 1) * gap, 0), size)
	for i = 1, count do
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Position = UDim2.fromOffset((i - 1) * (size + gap), 0)
		img.Size = UDim2.fromOffset(size, size)
		img.Image = (half and i == count) and Catalog.STAR_HALF or Catalog.STAR_FULL
		img.ZIndex = 8
		img.Parent = parent
	end
end

---------------------------------------------------------------- окно

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponCollection"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = C.black
backdrop.BackgroundTransparency = 0.45
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Visible = false
backdrop.Parent = gui

local container = Instance.new("Frame")
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.5)
container.Size = UDim2.fromOffset(LEFT_W + GAP + RIGHT_W, PANEL_H)
container.BackgroundTransparency = 1
container.Parent = backdrop

local uiScale = Instance.new("UIScale")
uiScale.Parent = container
local function fit()
	local vp = gui.AbsoluteSize
	if vp.X < 1 then return end
	uiScale.Scale = math.clamp(math.min(vp.X / (container.Size.X.Offset + 90), vp.Y / (PANEL_H + 120)), 0.4, 1)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

---------------------------------------------------------------- ЛЕВАЯ: коллекция

local left = Instance.new("Frame")
left.Position = UDim2.fromOffset(0, 0)
left.Size = UDim2.fromOffset(LEFT_W, PANEL_H)
left.BackgroundColor3 = C.panelBg
left.BorderSizePixel = 0
left.Active = true -- гасит клик, чтобы клик по панели не закрывал меню
left.Parent = container
stroke(left, 4, C.black)

local lHead = Instance.new("Frame")
lHead.Size = UDim2.fromOffset(LEFT_W, L_HEAD_H)
lHead.BackgroundColor3 = C.headerBg
lHead.BorderSizePixel = 0
lHead.Parent = left
addStuds(lHead, LEFT_W, L_HEAD_H, 30, 8, C.white, 0.94)
local lHeadLine = Instance.new("Frame")
lHeadLine.Size = UDim2.fromOffset(LEFT_W, 4)
lHeadLine.Position = UDim2.fromOffset(0, L_HEAD_H)
lHeadLine.BackgroundColor3 = C.black
lHeadLine.BorderSizePixel = 0
lHeadLine.Parent = left

-- жёлтый значок «?»
local badge = Instance.new("Frame")
badge.Size = UDim2.fromOffset(46, 46)
badge.Position = UDim2.fromOffset(16, (L_HEAD_H - 46) / 2)
badge.BackgroundColor3 = C.gold
badge.BorderSizePixel = 0
badge.ZIndex = 4
badge.Parent = lHead
stroke(badge, 3, C.black)
local badgeQ = Instance.new("TextLabel")
badgeQ.BackgroundTransparency = 1
badgeQ.Size = UDim2.fromScale(1, 1)
badgeQ.FontFace = FONT_LAT
badgeQ.Text = "?"
badgeQ.TextSize = 28
badgeQ.TextColor3 = C.goldText
badgeQ.ZIndex = 5
badgeQ.Parent = badge

displayText(lHead, {
	text = "КОЛЛЕКЦИЯ ПУШЕК", font = FONT_CYR, textSize = 30, color = C.white,
	size = UDim2.fromOffset(LEFT_W - 80, L_HEAD_H), pos = UDim2.fromOffset(74, 0),
	xAlign = Enum.TextXAlignment.Left, strokeT = 1.5, shadowY = 3, zIndex = 4, scaled = true,
})

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.fromOffset(18, L_HEAD_H + 4 + 14)
grid.Size = UDim2.new(1, -36, 1, -(L_HEAD_H + 4 + 14) - 16)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = left
local gridLayout = Instance.new("UIGridLayout")
local cell = math.floor((LEFT_W - 36 - (COLS - 1) * 12) / COLS)
gridLayout.CellSize = UDim2.fromOffset(cell, cell)
gridLayout.CellPadding = UDim2.fromOffset(12, 22)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

---------------------------------------------------------------- ПРАВАЯ: класс + сокровища

local right = Instance.new("Frame")
right.Position = UDim2.fromOffset(LEFT_W + GAP, 0)
right.Size = UDim2.fromOffset(RIGHT_W, PANEL_H)
right.BackgroundColor3 = C.panelBg
right.BorderSizePixel = 0
right.Active = true -- гасит клик, чтобы клик по панели не закрывал меню
right.Parent = container
stroke(right, 4, C.black)

local rHead = Instance.new("Frame")
rHead.Size = UDim2.fromOffset(RIGHT_W, R_HEAD_H)
rHead.BackgroundColor3 = C.headerBg
rHead.BorderSizePixel = 0
rHead.Parent = right
addStuds(rHead, RIGHT_W, R_HEAD_H, 30, 8, C.white, 0.94)
local rHeadLine = Instance.new("Frame")
rHeadLine.Size = UDim2.fromOffset(RIGHT_W, 4)
rHeadLine.Position = UDim2.fromOffset(0, R_HEAD_H)
rHeadLine.BackgroundColor3 = C.black
rHeadLine.BorderSizePixel = 0
rHeadLine.Parent = right
displayText(rHead, {
	text = "ПОКАЗАТЬ ИНФОРМАЦИЮ", font = FONT_CYR, textSize = 22, color = C.white,
	size = UDim2.fromOffset(RIGHT_W - 84, R_HEAD_H), pos = UDim2.fromOffset(18, 0),
	xAlign = Enum.TextXAlignment.Left, strokeT = 1, shadowY = 2, zIndex = 4, scaled = true,
})

--[[ ⚠️ КРЕСТИК ЗАКРЫТИЯ БЕРЁМ ИЗ UITheme, А НЕ РИСУЕМ СВОЙ.
     Владелец требует, чтобы кнопка закрытия во всех меню океана выглядела
     одинаково, и эталоном назвал инвентарь. Раньше здесь была своя картинка
     62 px с ростом на наведении — рядом с инвентарным крестиком она читалась
     как другой элемент управления. Размер и вид живут теперь в одном месте
     (UITheme.CLOSE_SIZE), меню его не переопределяет: как только меню начнут
     передавать свой size, крестики снова разъедутся.
     Посадка обычная (правый верхний угол), поэтому position/anchorPoint не
     передаём — умолчание модуля и есть посадка инвентаря.
     Родитель — сама панель `right`, а не её шапка rHead: на шапке стоит
     ClipsDescendants = true (его ставит addStuds под стад-паттерн), и кнопку
     там срезало бы. ZIndex 12 — чтобы кнопка была над шапкой и стадами. ]]
local closeBtn = UITheme.closeButton({ parent = right, zIndex = 12 })

-- блок класса (заполняется в refreshRight)
local classArea = Instance.new("Frame")
classArea.BackgroundTransparency = 1
classArea.Position = UDim2.fromOffset(0, R_HEAD_H + 4)
classArea.Size = UDim2.fromOffset(RIGHT_W, PANEL_H - (R_HEAD_H + 4) - 132)
classArea.Parent = right

-- нижний блок сокровищ
local TRE_H = 128
local treasure = Instance.new("Frame")
treasure.BackgroundTransparency = 1
treasure.AnchorPoint = Vector2.new(0, 1)
treasure.Position = UDim2.new(0, 0, 1, 0)
treasure.Size = UDim2.fromOffset(RIGHT_W, TRE_H)
treasure.Parent = right
local treLine = Instance.new("Frame")
treLine.Size = UDim2.new(1, 0, 0, 3)
treLine.BackgroundColor3 = C.itemBg
treLine.BorderSizePixel = 0
treLine.Parent = treasure
displayText(treasure, {
	text = "НАЙДЕНЫ СОКРОВИЩА", font = FONT_CYR, textSize = 20, color = C.white,
	size = UDim2.fromOffset(RIGHT_W - 40, 26), pos = UDim2.fromOffset(20, 14),
	xAlign = Enum.TextXAlignment.Left, strokeT = 1, shadowY = 2, zIndex = 4, scaled = true,
})
local TRE_SLOTS = 4
local treTiles = {}
do
	local pad, gap = 20, 10
	local size = math.floor((RIGHT_W - pad * 2 - (TRE_SLOTS - 1) * gap) / TRE_SLOTS)
	for i = 1, TRE_SLOTS do
		local t = Instance.new("Frame")
		t.Position = UDim2.fromOffset(pad + (i - 1) * (size + gap), 46)
		t.Size = UDim2.fromOffset(size, size)
		t.BackgroundColor3 = C.iconBg
		t.BorderSizePixel = 0
		t.Parent = treasure
		stroke(t, 3, C.black)
		local g = Instance.new("TextLabel")
		g.BackgroundTransparency = 1
		g.Size = UDim2.fromScale(1, 1)
		g.FontFace = FONT_CYR
		g.Text = "\u{25C8}" -- ◈
		g.TextSize = 26
		g.TextColor3 = C.muted
		g.Parent = t
		treTiles[i] = { frame = t, glyph = g }
	end
end
local treLbl = Instance.new("TextLabel")
treLbl.BackgroundTransparency = 1
treLbl.FontFace = FONT_800
treLbl.Text = "Найдено 0 из " .. TRE_SLOTS
treLbl.TextSize = 15
treLbl.TextColor3 = C.blueLabel
treLbl.TextXAlignment = Enum.TextXAlignment.Center
treLbl.AnchorPoint = Vector2.new(0.5, 1)
treLbl.Position = UDim2.new(0.5, 0, 1, -8)
treLbl.Size = UDim2.fromOffset(RIGHT_W - 40, 20)
treLbl.Parent = treasure

---------------------------------------------------------------- карточки коллекции

local selectedId = nil
local cardRefs = {}

local function refreshSelection()
	for id, ref in pairs(cardRefs) do
		local sel = id == selectedId
		ref.stroke.Color = sel and C.white or C.black
		ref.stroke.Thickness = sel and 4 or 3
	end
end

local function buildCard(w, order)
	local tile = Instance.new("TextButton")
	tile.Name = w.id
	tile.LayoutOrder = order
	tile.BackgroundColor3 = C.itemBg
	tile.BorderSizePixel = 0
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.Parent = grid
	local st = stroke(tile, 3, C.black)

	-- фон редкости (картинка каталога)
	local rbg = Catalog.RARITY_BG[w.rarity]
	if rbg then
		local bgImg = Instance.new("ImageLabel")
		bgImg.BackgroundTransparency = 1
		bgImg.Size = UDim2.fromScale(1, 1)
		bgImg.Image = rbg
		bgImg.ZIndex = 2
		bgImg.Parent = tile
	end
	-- иконка пушки
	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.82, 0.82)
	icon.BackgroundTransparency = 1
	icon.Image = w.icon or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 3
	icon.Parent = tile
	-- звёзды снизу (седлают нижнюю грань)
	local stars = Instance.new("Frame")
	stars.AnchorPoint = Vector2.new(0.5, 0.5)
	stars.Position = UDim2.new(0.5, 0, 1, 2)
	stars.Size = UDim2.fromOffset(0, 20)
	stars.BackgroundTransparency = 1
	stars.ZIndex = 8
	stars.Parent = tile
	fillStars(stars, w.stars or 0, 20)

	cardRefs[w.id] = { tile = tile, stroke = st }
	tile.MouseButton1Click:Connect(function()
		selectedId = w.id
		refreshSelection()
	end)
end

local function refreshGrid()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	cardRefs = {}
	local data = {}
	local ok, res = pcall(function() return getColl:InvokeServer() end)
	if ok and type(res) == "table" then data = res end
	table.sort(data, function(a, b)
		local wa, wb = Catalog.ById[a.id], Catalog.ById[b.id]
		if not wa or not wb then return false end
		local ra = Catalog.RARITY_ORDER[wa.rarity] or 0
		local rb = Catalog.RARITY_ORDER[wb.rarity] or 0
		if ra ~= rb then return ra > rb end
		return (wa.name or "") < (wb.name or "")
	end)
	for i, entry in ipairs(data) do
		local w = Catalog.ById[entry.id]
		if w then buildCard(w, i) end
	end
	refreshSelection()
end

---------------------------------------------------------------- правая инфа (класс + баффы)

local classChildren = {}
local function clearClassArea()
	-- в classArea нет постоянных детей — сносим всё (надёжнее ручного трекинга,
	-- тени displayText тоже уйдут, без накопления при повторных обновлениях)
	for _, ch in ipairs(classArea:GetChildren()) do ch:Destroy() end
	classChildren = {}
end

local function refreshRight()
	clearClassArea()

	local selected = player:GetAttribute(Config.CLASS_SELECTED_ATTR)
	if type(selected) ~= "string" or selected == "" then selected = nil end
	local buffs = selected and CLASS_BUFFS[selected]

	if not (selected and buffs) then
		-- нет класса
		local t = displayText(classArea, {
			text = "НЕТ КЛАССА ЭКИПИРОВАНО", font = FONT_CYR, textSize = 22, color = C.white,
			size = UDim2.fromOffset(RIGHT_W - 40, 30), pos = UDim2.fromOffset(20, 60),
			strokeT = 1, shadowY = 2, zIndex = 4, scaled = true,
		})
		table.insert(classChildren, t)
		local sh = classArea:FindFirstChild("Shadow")
		if sh then table.insert(classChildren, sh) end
		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.FontFace = FONT_800
		hint.Text = "Надеть класс в лобби"
		hint.TextSize = 16
		hint.TextColor3 = C.blueLabel
		hint.Position = UDim2.fromOffset(20, 98)
		hint.Size = UDim2.fromOffset(RIGHT_W - 40, 22)
		hint.Parent = classArea
		table.insert(classChildren, hint)
		return
	end

	local level = math.clamp(math.floor(player:GetAttribute(Config.CLASS_LEVEL_PREFIX .. selected) or 0), 0, Config.MAX_CLASS_LEVEL)

	-- иконка класса
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 14)
	box.Size = UDim2.fromOffset(84, 84)
	box.BackgroundColor3 = C.itemBg
	box.BorderSizePixel = 0
	box.Parent = classArea
	stroke(box, 3, C.black)
	table.insert(classChildren, box)
	local bi = Instance.new("TextLabel")
	bi.BackgroundTransparency = 1
	bi.Size = UDim2.fromScale(1, 1)
	bi.FontFace = FONT_CYR
	bi.Text = buffs.icon
	bi.TextSize = 44
	bi.Parent = box

	-- имя + уровень
	local nameLbl = displayText(classArea, {
		text = buffs.name, font = FONT_CYR, textSize = 24, color = C.white,
		size = UDim2.fromOffset(RIGHT_W - 40, 30), pos = UDim2.fromOffset(20, 106),
		strokeT = 1, shadowY = 2, zIndex = 4, scaled = true,
	})
	table.insert(classChildren, nameLbl)
	local nsh = nameLbl.Parent:FindFirstChild("Shadow")
	if nsh then table.insert(classChildren, nsh) end

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.FontFace = FONT_800
	hint.Text = "Уровень " .. level .. " • активен в бою"
	hint.TextSize = 16
	hint.TextColor3 = C.green
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(20, 138)
	hint.Size = UDim2.fromOffset(RIGHT_W - 40, 22)
	hint.Parent = classArea
	table.insert(classChildren, hint)

	-- заголовок баффов
	local bl = Instance.new("TextLabel")
	bl.BackgroundTransparency = 1
	bl.FontFace = FONT_BODY
	bl.Text = "АКТИВНЫЕ БАФФЫ:"
	bl.TextSize = 15
	bl.TextColor3 = C.blueLabel
	bl.TextXAlignment = Enum.TextXAlignment.Left
	bl.Position = UDim2.fromOffset(20, 172)
	bl.Size = UDim2.fromOffset(RIGHT_W - 40, 20)
	bl.Parent = classArea
	table.insert(classChildren, bl)

	-- строки баффов: активные (уровень >= i) — зелёная галка + белый текст,
	-- ещё не открытые — замок + приглушённый
	for i, perk in ipairs(buffs.perks) do
		local active = level >= i
		local y = 200 + (i - 1) * 32
		if active then
			local ch = Instance.new("Frame")
			ch.BackgroundTransparency = 1
			ch.Position = UDim2.fromOffset(16, y)
			ch.Size = UDim2.fromOffset(28, 28)
			ch.Parent = classArea
			drawCheck(ch, 14, 15, 0.95, C.green, 6)
		else
			local lock = Instance.new("TextLabel")
			lock.BackgroundTransparency = 1
			lock.FontFace = FONT_CYR
			lock.Text = "\u{1F512}"
			lock.TextSize = 16
			lock.TextColor3 = C.muted
			lock.Position = UDim2.fromOffset(16, y)
			lock.Size = UDim2.fromOffset(28, 28)
			lock.Parent = classArea
		end
		local txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.FontFace = FONT_800
		txt.Text = perk
		txt.TextSize = 17
		txt.TextColor3 = active and C.white or C.muted
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextYAlignment = Enum.TextYAlignment.Center
		txt.TextWrapped = true
		txt.Position = UDim2.fromOffset(46, y - 5)
		txt.Size = UDim2.fromOffset(RIGHT_W - 46 - 14, 34)
		txt.Parent = classArea
	end
end

local function refreshTreasures()
	local kf = player:FindFirstChild("FoundKeys")
	local found = kf and #kf:GetChildren() or 0
	found = math.clamp(found, 0, TRE_SLOTS)
	for i, ref in ipairs(treTiles) do
		local ok = i <= found
		ref.frame.BackgroundColor3 = ok and C.itemBg or C.iconBg
		ref.glyph.TextColor3 = ok and C.gold or C.muted
	end
	treLbl.Text = "Найдено " .. found .. " из " .. TRE_SLOTS
end

---------------------------------------------------------------- открытие/закрытие

local openBtn -- forward decl (кнопка создаётся ниже)
local updateOpenBtn -- forward decl (видимость: только ночью и пока меню закрыто)

local function setOpen(isOpen)
	backdrop.Visible = isOpen
	if updateOpenBtn then updateOpenBtn() end
	if isOpen then
		fit()
		refreshGrid()
		refreshRight()
		refreshTreasures()
	end
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
backdrop.MouseButton1Click:Connect(function() setOpen(false) end)

-- реагируем на смену класса/уровня (если поменялись пока открыто)
local function onClassChanged()
	if backdrop.Visible then refreshRight() end
end
player:GetAttributeChangedSignal(Config.CLASS_SELECTED_ATTR):Connect(onClassChanged)
for _, c in ipairs(Config.Classes or {}) do
	player:GetAttributeChangedSignal(Config.CLASS_LEVEL_PREFIX .. c.id):Connect(onClassChanged)
end

---------------------------------------------------------------- кнопка открытия

openBtn = Instance.new("TextButton")
openBtn.Name = "OpenCollection"
-- ПРАВЫЙ край, ПОД кнопкой квестов и её подписью «Квесты» (слева-посередине HUD
-- налазил друг на друга). Отступ -27 центрует 56px кнопку по оси с 78px квестами (-16).
openBtn.AnchorPoint = Vector2.new(1, 0.5)
openBtn.Position = UDim2.new(1, -27, 0.5, 74)
openBtn.Size = UDim2.fromOffset(56, 56)
openBtn.BackgroundColor3 = C.orange
openBtn.BorderSizePixel = 0
openBtn.FontFace = FONT_CYR
openBtn.Text = "\u{1F4E6}" -- 📦
openBtn.TextSize = 28
openBtn.TextColor3 = C.white
openBtn.AutoButtonColor = false
openBtn.Parent = gui
stroke(openBtn, 4, C.black)
openBtn.MouseEnter:Connect(function() openBtn.BackgroundColor3 = C.orangeHov end)
openBtn.MouseLeave:Connect(function() openBtn.BackgroundColor3 = C.orange end)
openBtn.MouseButton1Click:Connect(function() setOpen(true) end)

-- Кнопка коллекции (что выпадает с кейсов) видна ТОЛЬКО НОЧЬЮ — кейсы падают
-- с ночных кораблей, днём информация не нужна. Ночь по Lighting.ClockTime
-- (DayNightCircle: день 6→18, ночь 18→6).
local Lighting = game:GetService("Lighting")
local function isNight()
	local t = Lighting.ClockTime
	return t >= 18 or t < 6
end
updateOpenBtn = function()
	openBtn.Visible = isNight() and not backdrop.Visible
end
updateOpenBtn()
task.spawn(function()
	while true do
		task.wait(1)
		updateOpenBtn()
	end
end)

print("[WeaponCollectionMenu] rebuilt (new design + class buffs)")
