--[[
	UITheme — единый дизайн-модуль игры (см. src/GameDesign/UIRedesign_Plan.md).
	Кодирует спеку стиля и палитры тем из прототипа и даёт фабрики компонентов,
	чтобы все экраны (инвентарь, крафт, строительство, уведомления) выглядели
	одинаково и правились в одном месте.

	require:
		local UITheme = require(game.ReplicatedStorage:WaitForChild("UITheme"))
		local panel = UITheme.panel({ parent = gui, size = UDim2.fromOffset(360, 420) })
		local btn   = UITheme.button({ parent = panel, text = "Craft", color = UITheme.Notif.success })

	Активная тема — UITheme.Current ("Ocean"/"Sunset"/"Jungle"/"Grape").
--]]

local TweenService = game:GetService("TweenService")

local UITheme = {}

--====================================================
-- ПАЛИТРЫ И КОНСТАНТЫ (из спеки)
--====================================================

local function hex(h) return Color3.fromHex(h) end

-- панель верх→низ / рамка / слот
local THEMES = {
	Ocean  = { top = "54A7EC", bottom = "3A7FD0", frame = "1C4F8F", slot = "A9D6F7" },
	Sunset = { top = "F2A444", bottom = "DD7F20", frame = "7A4310", slot = "FBD9A4" },
	Jungle = { top = "66C25E", bottom = "3F9E3F", frame = "1E5C24", slot = "BCE8A8" },
	Grape  = { top = "9B6CE0", bottom = "7A48C8", frame = "4A2580", slot = "D7C2F5" },
}

UITheme.Current = "Ocean"

UITheme.Accent  = { top = hex("FFD95A"), bottom = hex("F5B73C"), frame = hex("B07A14") }
UITheme.PriceOk = hex("4CD964")
UITheme.PriceNo = hex("FF6B5A")

-- Цвета карточек уведомлений по типу (slot — светлый тон иконо-бокса из палитры).
UITheme.Notif = {
	info    = { top = "54A7EC", bottom = "3A7FD0", frame = "1C4F8F", slot = "A9D6F7" }, -- синий
	unlock  = { top = "9B6CE0", bottom = "7A48C8", frame = "4A2580", slot = "D7C2F5" }, -- фиолетовый
	success = { top = "66C25E", bottom = "3F9E3F", frame = "1E5C24", slot = "BCE8A8" }, -- зелёный
	reward  = { top = "FFD95A", bottom = "F5B73C", frame = "B07A14", slot = "FBD9A4" }, -- золото
	warn    = { top = "FF8A5A", bottom = "E2542F", frame = "8A2A12", slot = "FBD9A4" }, -- красный
}

UITheme.PANEL_CORNER, UITheme.PANEL_STROKE = 18, 4
UITheme.BTN_CORNER,   UITheme.BTN_STROKE   = 12, 3
UITheme.SLOT_CORNER,  UITheme.SLOT_STROKE  = 12, 3

-- Спека: Builder Sans Bold / GothamBlack. По умолчанию Gotham (есть везде); хочешь
-- ближе к прототипу — поставь Enum.Font.BuilderSansExtraBold / BuilderSansBold.
UITheme.FONT_TITLE = Enum.Font.GothamBlack
UITheme.FONT_BODY  = Enum.Font.GothamBold
UITheme.TEXT       = Color3.fromRGB(255, 255, 255)

-- Текущая тема как Color3-набор. opts.theme может переопределить.
function UITheme.colors(name)
	local t = THEMES[name or UITheme.Current] or THEMES.Ocean
	return { top = hex(t.top), bottom = hex(t.bottom), frame = hex(t.frame), slot = hex(t.slot) }
end

--====================================================
-- НИЗКОУРОВНЕВЫЕ ХЕЛПЕРЫ
--====================================================

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function gradient(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90 -- вертикально: светлее сверху, темнее снизу
	g.Parent = inst
	return g
end

-- Применить общие opts (size/position/anchorPoint/name/parent/zindex) к инстансу.
local function applyLayout(inst, opts)
	if opts.size then inst.Size = opts.size end
	if opts.position then inst.Position = opts.position end
	if opts.anchorPoint then inst.AnchorPoint = opts.anchorPoint end
	if opts.name then inst.Name = opts.name end
	if opts.zindex then inst.ZIndex = opts.zindex end
	if opts.layoutOrder then inst.LayoutOrder = opts.layoutOrder end
	if opts.parent then inst.Parent = opts.parent end
end

-- Цветовая тройка для компонента: accent | явный color {top,bottom,frame} | тема.
local function pickColors(opts)
	if opts.accent then
		return UITheme.Accent.top, UITheme.Accent.bottom, UITheme.Accent.frame
	elseif opts.color then
		return hex(opts.color.top), hex(opts.color.bottom), hex(opts.color.frame)
	end
	local c = UITheme.colors(opts.theme)
	return c.top, c.bottom, c.frame
end

-- Лёгкая «тень» текста (упрощённо — обводка; спека просит drop-shadow 0/2 30%).
function UITheme.textShadow(label)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.6
end

-- Hover-масштаб 1.05 за 0.1с (для кнопок).
function UITheme.hover(button)
	local scale = button:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
end

--====================================================
-- ФАБРИКИ КОМПОНЕНТОВ
--====================================================

-- Панель/карточка: градиент темы (или color), UICorner 18, UIStroke 4 рамкой.
-- ВАЖНО: UIGradient УМНОЖАЕТСЯ на BackgroundColor3 — под градиентом фон строго
-- белый, иначе хексы перемножаются сами с собой и темнеют (не совпадают со спекой).
function UITheme.panel(opts)
	opts = opts or {}
	local top, bottom, frameCol = pickColors(opts)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	gradient(f, top, bottom)
	corner(f, opts.corner or UITheme.PANEL_CORNER)
	stroke(f, opts.stroke or UITheme.PANEL_STROKE, frameCol)
	applyLayout(f, opts)
	return f
end

-- Текстовая надпись (тайтл/боди) с тенью.
function UITheme.label(opts)
	opts = opts or {}
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = opts.font or UITheme.FONT_BODY
	lbl.TextColor3 = opts.textColor or UITheme.TEXT
	lbl.Text = opts.text or ""
	lbl.TextXAlignment = opts.xAlign or Enum.TextXAlignment.Left
	lbl.TextYAlignment = opts.yAlign or Enum.TextYAlignment.Center
	lbl.TextWrapped = opts.wrapped ~= false
	if opts.textScaled then
		lbl.TextScaled = true
	else
		lbl.TextSize = opts.textSize or 16
	end
	UITheme.textShadow(lbl)
	applyLayout(lbl, opts)
	return lbl
end

-- Кнопка: градиент (accent/color/тема), UICorner 12, UIStroke 3, «грань» снизу, hover.
function UITheme.button(opts)
	opts = opts or {}
	local top, bottom, frameCol = pickColors(opts)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1) -- белый под градиент (см. panel)
	b.BorderSizePixel = 0
	b.Text = opts.text or ""
	b.Font = opts.font or UITheme.FONT_TITLE
	b.TextColor3 = opts.textColor or UITheme.TEXT
	if opts.textScaled then
		b.TextScaled = true
	else
		b.TextSize = opts.textSize or 18
	end
	UITheme.textShadow(b)
	gradient(b, top, bottom)
	corner(b, opts.corner or UITheme.BTN_CORNER)
	stroke(b, UITheme.BTN_STROKE, frameCol)

	-- «грань» снизу — тёмная полоска для объёма
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0.5, 1)
	edge.Position = UDim2.new(0.5, 0, 1, -3)
	edge.Size = UDim2.new(1, -10, 0, 5)
	edge.BackgroundColor3 = Color3.new(0, 0, 0)
	edge.BackgroundTransparency = 0.82
	edge.BorderSizePixel = 0
	corner(edge, 4)
	edge.Parent = b

	applyLayout(b, opts)
	if opts.hover ~= false then UITheme.hover(b) end
	if opts.onClick then b.MouseButton1Click:Connect(opts.onClick) end
	return b
end

-- Перекрасить кнопку в новые цвета (для вкладок: активная=accent, иначе тема).
function UITheme.recolor(button, opts)
	local top, bottom, frameCol = pickColors(opts)
	local g = button:FindFirstChildWhichIsA("UIGradient")
	if g then
		g.Color = ColorSequence.new(top, bottom) -- фон остаётся белым (см. panel)
	else
		button.BackgroundColor3 = bottom
	end
	local s = button:FindFirstChildWhichIsA("UIStroke")
	if s then s.Color = frameCol end
end

-- Вкладка: кнопка, активная — золотая. Возвращает кнопку; меняем состояние через
-- UITheme.recolor(tab, { accent = isActive } или { theme = ... }).
function UITheme.tab(opts)
	opts = opts or {}
	opts.accent = opts.active
	local b = UITheme.button(opts)
	b.Name = opts.name or "Tab"
	return b
end

-- Слот предмета: UICorner 12, UIStroke 3; пустой — заливка 35% прозрачности.
function UITheme.slot(opts)
	opts = opts or {}
	local c = UITheme.colors(opts.theme)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = c.slot
	f.BackgroundTransparency = opts.empty and 0.35 or 0
	f.BorderSizePixel = 0
	corner(f, opts.corner or UITheme.SLOT_CORNER)
	stroke(f, UITheme.SLOT_STROKE, c.frame)
	applyLayout(f, opts)
	return f
end

-- Иконо-бокс (квадрат со скруглением и иконкой-эмодзи/картинкой). Для карточек.
function UITheme.iconBox(opts)
	opts = opts or {}
	local c = UITheme.colors(opts.theme)
	local box = Instance.new("Frame")
	box.BackgroundColor3 = opts.fill or c.slot
	box.BackgroundTransparency = opts.transparency or 0
	box.BorderSizePixel = 0
	corner(box, opts.corner or 10)
	stroke(box, 2, opts.stroke or c.frame)
	applyLayout(box, opts)
	if opts.image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(0.74, 0.74)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Image = opts.image
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = box
	elseif opts.icon then
		local em = Instance.new("TextLabel")
		em.BackgroundTransparency = 1
		em.Size = UDim2.fromScale(1, 1)
		em.Text = opts.icon
		em.TextScaled = true
		em.Font = Enum.Font.GothamBold
		em.Parent = box
	end
	return box
end

-- Пилюля цены: зелёная если хватает, красная если нет. AutomaticSize по тексту.
function UITheme.pricePill(opts)
	opts = opts or {}
	local base = opts.canAfford and UITheme.PriceOk or UITheme.PriceNo
	local f = Instance.new("Frame")
	f.BackgroundColor3 = base
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.new(0, 0, 0, opts.height or 22)
	corner(f, 999)
	stroke(f, 2, base:Lerp(Color3.new(0, 0, 0), 0.35))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = f
	local lbl = UITheme.label({
		text = opts.text or "",
		font = UITheme.FONT_BODY,
		textSize = opts.textSize or 13,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = false,
		parent = f,
	})
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size = UDim2.new(0, 0, 1, 0)
	applyLayout(f, opts)
	return f
end

return UITheme
