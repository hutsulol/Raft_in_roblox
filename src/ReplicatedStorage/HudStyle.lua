-- HudStyle.lua  (ReplicatedStorage, shared module)
-- Единый премиальный стиль верхнего HUD: панель-«оправа» из дерева с золотой окантовкой,
-- чёрной обводкой и верхним бликом + подписи в одном стиле. Используют RaftHealthHUD,
-- VillagersHUD, DayNight — чтобы все три плашки выглядели как один набор.

local HudStyle = {}

HudStyle.WOOD_TOP  = Color3.fromRGB(96, 63, 38)   -- верх градиента дерева
HudStyle.WOOD_BOT  = Color3.fromRGB(43, 27, 15)   -- низ (темнее — объём)
HudStyle.GOLD      = Color3.fromRGB(224, 182, 108) -- акцент/иконки
HudStyle.GOLD_DARK = Color3.fromRGB(122, 86, 42)  -- золотая окантовка
HudStyle.CREAM     = Color3.fromRGB(248, 236, 210) -- основной текст
HudStyle.CREAM_DIM = Color3.fromRGB(214, 188, 150) -- второстепенный
HudStyle.BLACK     = Color3.fromRGB(0, 0, 0)
HudStyle.TRACK_BG  = Color3.fromRGB(24, 15, 8)    -- тёмная «яма» под полосой HP

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end
HudStyle.corner = corner

-- Премиальная панель-оправа. opts: { parent, size, position?, anchor?, radius? }
function HudStyle.panel(opts)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.Size = opts.size
	if opts.position then f.Position = opts.position end
	if opts.anchor then f.AnchorPoint = opts.anchor end
	f.Parent = opts.parent
	local r = opts.radius or 12
	corner(f, r)

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(HudStyle.WOOD_TOP, HudStyle.WOOD_BOT)
	g.Parent = f

	-- две обводки: жирная чёрная снаружи + тонкая золотая поверх (эффект оправы)
	local blk = Instance.new("UIStroke")
	blk.Color = HudStyle.BLACK; blk.Thickness = 3; blk.Parent = f
	local gold = Instance.new("UIStroke")
	gold.Color = HudStyle.GOLD_DARK; gold.Thickness = 1.5; gold.Transparency = 0.1; gold.Parent = f

	-- верхний блик (стекло)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.8
	gloss.BorderSizePixel = 0
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.new(0.5, 0, 0, 3)
	gloss.Size = UDim2.new(1, -14, 0, math.max(4, math.floor(r * 0.5)))
	gloss.ZIndex = 2
	corner(gloss, math.max(3, math.floor(r * 0.55)))
	gloss.Parent = f

	return f
end

-- Подпись в общем стиле. opts: { parent, text?, size?, position?, anchor?, font?, textSize?, color?, xAlign?, strokeT?, zIndex? }
function HudStyle.label(opts)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = opts.size or UDim2.fromScale(1, 1)
	if opts.position then l.Position = opts.position end
	if opts.anchor then l.AnchorPoint = opts.anchor end
	l.Font = opts.font or Enum.Font.GothamBlack
	l.TextSize = opts.textSize or 18
	l.TextColor3 = opts.color or HudStyle.CREAM
	l.TextStrokeColor3 = HudStyle.BLACK
	l.TextStrokeTransparency = opts.strokeT or 0.35
	l.Text = opts.text or ""
	l.TextXAlignment = opts.xAlign or Enum.TextXAlignment.Center
	l.ZIndex = opts.zIndex or 3
	l.Parent = opts.parent
	return l
end

-- цвета заливки HP по остатку: light / mid / dark (для вертикального градиента)
function HudStyle.hpColors(pct)
	if pct > 0.5 then
		return Color3.fromRGB(120, 226, 112), Color3.fromRGB(56, 182, 66), Color3.fromRGB(28, 120, 40)
	elseif pct > 0.25 then
		return Color3.fromRGB(255, 216, 120), Color3.fromRGB(236, 186, 60), Color3.fromRGB(168, 120, 30)
	else
		return Color3.fromRGB(246, 122, 106), Color3.fromRGB(216, 56, 56), Color3.fromRGB(140, 28, 28)
	end
end

return HudStyle
