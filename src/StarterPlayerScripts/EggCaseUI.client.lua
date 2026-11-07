-- EggCaseUI.client.lua
-- "Egg purchase" (Приключенское яйцо) case window — reproduced from the exported
-- design (Дизайн яйца/project/Окно яйца-кейса.dc.html). Visual first version:
-- close works; side buttons (Удача / Супер-удача / АВТО / Много) and Buy are
-- placeholders while the feature is built. A temporary dev button toggles it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
-- TweenService здесь больше не нужен: его единственным потребителем были твины
-- роста крестика на наведении, а сам крестик теперь целиком собирает UITheme
-- (подсветка нажатия там своя, через AutoButtonColor).
-- отсюда берётся кнопка закрытия: она общая для всех меню (UITheme.closeButton)
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("UITheme"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EGG_IMAGE = "rbxassetid://86084953353748"
-- Optional soft-glow PNG (radial). Leave "" to use the procedural stacked glow.
local GLOW_IMAGE = ""
-- Side-button icons
local LUCK_ICON       = "rbxassetid://105014206019921"
local SUPER_LUCK_ICON = "rbxassetid://82556485976124"
local AUTO_ICON       = "rbxassetid://128066450042247"

-- ── Palette (from the design) ────────────────────────────────────────────────
local PANEL_TOP    = Color3.fromHex("54a7ec")
local PANEL_BOT    = Color3.fromHex("3a7fd0")
local FRAME        = Color3.fromHex("1c4f8f")
local LIGHT_TOP    = Color3.fromHex("a9d6f7")
local LIGHT_BOT    = Color3.fromHex("8fc3ec")
local LABEL_DIM    = Color3.fromHex("cfe8ff")
local WHITE        = Color3.fromHex("ffffff")
local STAGE_TOP    = Color3.fromHex("2e6bb4")
local STAGE_BOT    = Color3.fromHex("1c4f8f")
local STAGE_EDGE   = Color3.fromHex("143a6b")
local COIN_TOP     = Color3.fromHex("ffd95a")
local COIN_BOT     = Color3.fromHex("f5b73c")
local COIN_EDGE    = Color3.fromHex("b07a14")
local CLOVER_LUCK  = Color3.fromHex("d7f0c2")
local CLOVER_SUPER = Color3.fromHex("c9b6f5")
local SHADOW       = Color3.fromRGB(8, 24, 48)

-- GothamBlack renders Cyrillic crisply (FredokaOne went muddy at small sizes).
local FONT = Enum.Font.GothamBlack

-- Rarity columns: {odds, border, innerTop, innerBot, eggColor, highlight}
local RARITIES = {
	{ "50%",  Color3.fromHex("e8eef5"), Color3.fromHex("c9dcf0"), Color3.fromHex("aac5e0"), Color3.fromHex("8aa0b8"), false },
	{ "30%",  Color3.fromHex("5fe07a"), Color3.fromHex("cdeed4"), Color3.fromHex("a7d8b2"), Color3.fromHex("4e9d63"), false },
	{ "17%",  WHITE,                    Color3.fromHex("a9d6f7"), Color3.fromHex("6fb0e6"), Color3.fromHex("2e6bb4"), true  },
	{ "2.5%", Color3.fromHex("b07ef0"), Color3.fromHex("ddc9f3"), Color3.fromHex("c0a3e6"), Color3.fromHex("7a45b8"), false },
	{ "0.5%", Color3.fromHex("f5a93c"), Color3.fromHex("f7dcae"), Color3.fromHex("ecc079"), Color3.fromHex("c98a2a"), false },
}

-- ── helpers ──────────────────────────────────────────────────────────────────
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(inst, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, inst) end
local function stroke(inst, color, thickness) new("UIStroke", { Color = color, Thickness = thickness }, inst) end

-- flat 2-stop gradient
local function gradient(inst, top, bot, rot)
	new("UIGradient", { Color = ColorSequence.new(top, bot), Rotation = rot or 90 }, inst)
end
-- candy gradient: light top → color → darker bottom (fake bottom bevel)
local function candyGradient(inst, top, bot)
	local darker = bot:Lerp(Color3.new(0, 0, 0), 0.28)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.72, bot),
		ColorSequenceKeypoint.new(1, darker),
	}) }, inst)
end

local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	if props.TextStrokeTransparency == nil then props.TextStrokeTransparency = 0.7 end
	props.TextStrokeColor3 = props.TextStrokeColor3 or Color3.new(0, 0, 0)
	return new("TextLabel", props, parent)
end

-- candy button: wrapper holds a drop-shadow + the button (3D look). Returns button.
local function candyButton(opts)
	local radius = opts.radius or 16
	local wrap = new("Frame", { Name = (opts.name or "Btn") .. "Wrap", BackgroundTransparency = 1,
		Size = opts.size }, opts.parent)
	if opts.position then wrap.Position = opts.position end
	if opts.anchorPoint then wrap.AnchorPoint = opts.anchorPoint end
	if opts.layoutOrder then wrap.LayoutOrder = opts.layoutOrder end
	-- shadow (created first → renders behind the button)
	local sh = new("Frame", { Name = "Shadow", BackgroundColor3 = SHADOW,
		BackgroundTransparency = opts.shadowTransparency or 0.55,
		Position = UDim2.new(0, 0, 0, opts.shadowOffset or 6), Size = UDim2.fromScale(1, 1) }, wrap)
	corner(sh, radius)
	local btn = new("TextButton", { Name = opts.name or "Btn", Text = "", AutoButtonColor = false,
		BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1) }, wrap)
	corner(btn, radius)
	stroke(btn, opts.strokeColor or FRAME, opts.strokeThickness or 4)
	candyGradient(btn, opts.gradTop or PANEL_TOP, opts.gradBot or PANEL_BOT)
	return btn
end

local function setBtnText(btn, text, size)
	btn.Text = text; btn.Font = FONT; btn.TextSize = size; btn.TextColor3 = WHITE
	btn.TextStrokeColor3 = Color3.new(0, 0, 0); btn.TextStrokeTransparency = 0.65
end

-- image icon centred in the upper part of a side button
local function iconImage(parent, image)
	return new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.33, 0), Size = UDim2.fromOffset(48, 48) }, parent)
end

-- 4-blob clover icon
local function clover(parent, color)
	local h = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(36, 32),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 0) }, parent)
	local function blob(px, py)
		local b = new("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(15, 15),
			Position = UDim2.fromOffset(px, py) }, h)
		corner(b, 8)
	end
	blob(10, 0); blob(0, 10); blob(21, 10); blob(10, 17)
end

-- drawn refresh ring + arrow for АВТО (the ↻ glyph doesn't render)
local function drawRefresh(parent, color)
	local h = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0) }, parent)
	local ring = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, h)
	corner(ring, 15)
	new("UIStroke", { Color = color, Thickness = 4 }, ring)
	local arrow = new("Frame", { BackgroundColor3 = color, Rotation = 45, Size = UDim2.fromOffset(9, 9),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.92, 0, 0.12, 0) }, h)
	corner(arrow, 2)
end

-- ── root GUI ─────────────────────────────────────────────────────────────────
local screen = new("ScreenGui", { Name = "EggCaseGui", ResetOnSpawn = false, DisplayOrder = 40,
	IgnoreGuiInset = true, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local backdrop = new("TextButton", { Name = "Backdrop", Text = "", AutoButtonColor = false, Modal = true,
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 }, screen)

local PANEL_W = 760
local modal = new("Frame", { Name = "Modal", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W, 600), AutomaticSize = Enum.AutomaticSize.Y }, screen)
local uiScale = new("UIScale", { Scale = 1 }, modal)
local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(vp.X / 1000, vp.Y / 760), 0.5, 1)
end
fitScale()

-- panel drop shadow (created before panel → behind it)
local panelShadow = new("Frame", { Name = "PanelShadow", BackgroundColor3 = SHADOW,
	BackgroundTransparency = 0.5, Position = UDim2.new(0, 0, 0, 14), Size = UDim2.fromScale(1, 1) }, modal)
corner(panelShadow, 26)

-- ── side controls ────────────────────────────────────────────────────────────
local leftCol = new("Frame", { Name = "LeftCol", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, -16, 0, 96), Size = UDim2.fromOffset(88, 200) }, modal)
local luckBtn = candyButton({ parent = leftCol, name = "Luck", size = UDim2.fromOffset(88, 88),
	position = UDim2.fromOffset(0, 0), radius = 18 })
iconImage(luckBtn, LUCK_ICON)
label({ Text = "Удача", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0.6, 0),
	TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center }, luckBtn)
local superBtn = candyButton({ parent = leftCol, name = "SuperLuck", size = UDim2.fromOffset(88, 88),
	position = UDim2.fromOffset(0, 104), radius = 18 })
iconImage(superBtn, SUPER_LUCK_ICON)
label({ Text = "Супер-\nудача", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0.56, 0),
	TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center }, superBtn)

local rightCol = new("Frame", { Name = "RightCol", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(1, 16, 0, 96), Size = UDim2.fromOffset(88, 200) }, modal)
local autoBtn = candyButton({ parent = rightCol, name = "Auto", size = UDim2.fromOffset(88, 88),
	position = UDim2.fromOffset(0, 0), radius = 18, gradTop = LIGHT_TOP, gradBot = LIGHT_BOT })
iconImage(autoBtn, AUTO_ICON)
label({ Text = "АВТО", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0.6, 0),
	TextSize = 15, TextColor3 = FRAME, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center }, autoBtn)
-- (Много button removed — not needed.)

-- ── main panel ───────────────────────────────────────────────────────────────
local panel = new("Frame", { Name = "Panel", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y }, modal)
corner(panel, 26)
stroke(panel, FRAME, 5)
gradient(panel, PANEL_TOP, PANEL_BOT)
new("UIPadding", { PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 28),
	PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26) }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 20),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, panel)

-- header
local header = new("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 1 }, panel)
label({ Text = "ПОКУПКА ЯЙЦА", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 2),
	TextSize = 14, TextColor3 = LABEL_DIM, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.8 }, header)
label({ Text = "Приключенское яйцо", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 20),
	TextSize = 29, TextXAlignment = Enum.TextXAlignment.Center }, header)
--[[ ⚠️ КРЕСТИК ЗАКРЫТИЯ — ОДИН НА ВСЕ МЕНЮ ОКЕАНА, ЭТАЛОН — ИНВЕНТАРЬ.
     Здесь стояла своя картинка 62 px с твинами роста на наведении, и рядом с
     инвентарём это читалось как два разных элемента управления. Владелец
     потребовал одинаковый крестик везде, эталоном назвал инвентарь — поэтому
     кнопку целиком делает UITheme.closeButton, а не этот файл.
     Размер здесь не задаётся НАМЕРЕННО: он живёт в UITheme.CLOSE_SIZE, иначе
     меню снова разъедутся — так это и вышло в прошлый раз.
     Посадку тоже не передаём: умолчание модуля (правый верхний угол с отступом)
     и есть посадка инвентаря.
     Родитель — modal, а не шапка: у панели UIPadding по 26 px, поэтому шапка до
     угла окна не достаёт, а любой её сосед по панели попал бы в UIListLayout и
     встал бы в колонку. У modal ровно те же границы, что у панели (панель
     растянута на всю его ширину и прижата к верху), и ClipsDescendants нигде по
     пути не стоит — кнопку не обрежет.
     ZIndex = 2 сохранён от прежней кнопки: перекладины креста модуль кладёт на
     слой выше, а панель со всем содержимым остаётся на 1. ]]
local closeBtn = UITheme.closeButton({ parent = modal, zIndex = 2 })

-- rarity odds row
local rarityRow = new("Frame", { Name = "Rarity", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 152), LayoutOrder = 2 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, rarityRow)
for i, r in ipairs(RARITIES) do
	local odds, border, innerTop, innerBot, eggColor, highlight = r[1], r[2], r[3], r[4], r[5], r[6]
	local cell = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = highlight and 0.76 or 0.84,
		Size = UDim2.new(0.2, -8, 1, 0), LayoutOrder = i }, rarityRow)
	corner(cell, 14)
	stroke(cell, border, 3)
	if highlight then new("UIStroke", { Color = PANEL_TOP, Thickness = 3, Transparency = 0.3 }, cell) end
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, cell)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, cell)
	local inner = new("Frame", { Name = "Inner", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 1, -28), LayoutOrder = 1 }, cell)
	corner(inner, 10)
	gradient(inner, innerTop, innerBot)
	local egg = new("Frame", { BackgroundColor3 = eggColor, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(30, 44) }, inner)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, egg)
	label({ Text = odds, Size = UDim2.new(1, 0, 0, 20), TextSize = 16, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center }, cell)
end

-- egg display stage
local stage = new("Frame", { Name = "Stage", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 250),
	LayoutOrder = 3, ClipsDescendants = true }, panel)
corner(stage, 20)
stroke(stage, STAGE_EDGE, 4)
gradient(stage, STAGE_TOP, STAGE_BOT)
-- soft glow behind the egg: a PNG if provided, else a stack of fading circles.
-- Collected into glowParts so the animation loop can make them breathe.
local glowParts = {}
if GLOW_IMAGE ~= "" then
	local img = new("ImageLabel", { BackgroundTransparency = 1, Image = GLOW_IMAGE, ImageColor3 = LIGHT_TOP,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 360) }, stage)
	table.insert(glowParts, { inst = img, base = 360 })
else
	for _, g in ipairs({ { 360, 0.9 }, { 320, 0.85 }, { 280, 0.79 }, { 240, 0.71 }, { 200, 0.61 }, { 160, 0.48 }, { 120, 0.32 } }) do
		local c = new("Frame", { BackgroundColor3 = LIGHT_TOP, BackgroundTransparency = g[2],
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(g[1], g[1]) }, stage)
		corner(c, g[1] / 2)
		table.insert(glowParts, { inst = c, base = g[1] })
	end
end
local sparkles = {}
local function sparkle(pos, size, phase)
	local s = new("Frame", { BackgroundColor3 = LABEL_DIM, Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos, Size = UDim2.fromOffset(size, size) }, stage)
	corner(s, math.max(2, math.floor(size / 4)))
	table.insert(sparkles, { inst = s, base = size, phase = phase })
end
sparkle(UDim2.fromScale(0.12, 0.18), 14, 0)
sparkle(UDim2.fromScale(0.86, 0.82), 10, 2.1)
sparkle(UDim2.fromScale(0.80, 0.30), 8, 4.0)
local eggImg = new("ImageLabel", { Name = "Egg", BackgroundTransparency = 1, Image = EGG_IMAGE, ScaleType = Enum.ScaleType.Fit,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(200, 230) }, stage)

-- cost + buy
local footer = new("Frame", { Name = "Footer", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 110), LayoutOrder = 4 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 14),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, footer)
local costRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 36), LayoutOrder = 1 }, footer)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder }, costRow)
local coin = new("TextLabel", { Text = "$", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = COIN_EDGE,
	BackgroundColor3 = WHITE, Size = UDim2.fromOffset(32, 32), LayoutOrder = 1 }, costRow)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, coin)
stroke(coin, COIN_EDGE, 3)
gradient(coin, COIN_TOP, COIN_BOT)
label({ Text = "35", Size = UDim2.fromOffset(70, 36), TextSize = 32, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left }, costRow)
local buyBtn = candyButton({ parent = footer, name = "Buy", size = UDim2.fromOffset(380, 60), layoutOrder = 2, radius = 16, shadowOffset = 7 })
setBtnText(buyBtn, "Купить · 1", 26)
buyBtn.TextStrokeTransparency = 1 -- white, no outline (per request)

-- ── open / close wiring ──────────────────────────────────────────────────────
local function setOpen(open) screen.Enabled = open end
-- Let other scripts (e.g. the pedestal prompt) open this menu.
_G.OpenEggMenu = function() setOpen(true) end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
backdrop.MouseButton1Click:Connect(function() setOpen(false) end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
end

-- Animate the backdrop behind the egg while the menu is open: the glow breathes
-- (grows/shrinks) and the sparkles twinkle (scale + fade) out of phase.
local fxTime = 0
RunService.RenderStepped:Connect(function(dt)
	if not screen.Enabled then return end
	fxTime += dt
	local gs = 1 + 0.13 * math.sin(fxTime * 1.7)
	for _, g in ipairs(glowParts) do
		g.inst.Size = UDim2.fromOffset(g.base * gs, g.base * gs)
	end
	for _, s in ipairs(sparkles) do
		local a = 0.5 + 0.5 * math.sin(fxTime * 2.6 + s.phase) -- 0..1
		local k = 0.7 + 0.45 * a
		s.inst.Size = UDim2.fromOffset(s.base * k, s.base * k)
		s.inst.BackgroundTransparency = (1 - a) * 0.55
	end
	-- egg: gentle multi-frequency wobble + a sharp jolt every ~2.4s — like
	-- something inside is bumping to get out (non-linear).
	local wob = math.sin(fxTime * 2.3) * 2.2 + math.sin(fxTime * 5.7) * 1.1
	local cyc = fxTime % 2.4
	local jolt = (cyc < 0.45) and (math.sin(cyc * 46) * 10 * math.exp(-cyc * 8)) or 0
	eggImg.Rotation = wob + jolt
	eggImg.Position = UDim2.new(0.5, math.sin(fxTime * 3.1) * 3 + jolt * 0.5, 0.5,
		math.sin(fxTime * 2.0) * 2 + math.abs(jolt) * 0.3)
end)

-- Кнопка «🥚 Яйцо» убрана к бета-тесту: меню открывается только через
-- _G.OpenEggMenu (пьедестал яйца), в HUD ничего не добавляем.
