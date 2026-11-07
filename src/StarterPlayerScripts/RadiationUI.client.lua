local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Shared status icon slot coordination ───
-- See WindUI.client.lua for the full description. Whichever status icon
-- claims a slot first occupies the leftmost position; later ones sit to
-- its right. When the leftmost icon is released the others shift left.
local SLOTS = _G.StatusIconSlots
if not SLOTS then
	SLOTS = {
		order = {},
		hooks = {},
	}
	_G.StatusIconSlots = SLOTS
end

local function takeSlot(name)
	for _, entry in ipairs(SLOTS.order) do
		if entry.name == name then return end
	end
	table.insert(SLOTS.order, {name = name})
end

local function releaseSlot(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then
			table.remove(SLOTS.order, i)
			return
		end
	end
end

local function getSlotIndex(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then return i - 1 end
	end
	return -1
end

local function notifyAll()
	for _, fn in ipairs(SLOTS.hooks) do
		pcall(fn)
	end
end

local BASE_X = 16
-- Sits 10 px above the mana bar's top edge. The mana container in
-- UIManager is anchored to the screen bottom at y=-102 with height
-- 36, so its top is at screen_bottom - 138. We want the icon's
-- bottom (anchor 0,1) at screen_bottom - 148 → 10 px gap above
-- the bar.
local BASE_Y_OFFSET = -148
local SLOT_STRIDE = 44 -- 36px icon + 8px gap

-- ─── UI Setup ───
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RadiationUI"
screenGui.DisplayOrder = 16
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Mirror UIManager's HUD scale so the radiation icon shrinks in
-- lockstep with the mana / hunger / health bars. Without this the
-- bars scale down on narrow viewports while the icon stays at its
-- full -188 offset — the icon then floats far above the (scaled)
-- mana bar instead of sitting just above it. Constants must stay in
-- sync with UIManager.HUD_REF_WIDTH / HUD_REF_HEIGHT / clamps.
local HUD_REF_WIDTH  = 1400
local HUD_REF_HEIGHT = 720
local HUD_MIN_SCALE  = 0.35
local HUD_MAX_SCALE  = 1.0

local hudScale = Instance.new("UIScale")
hudScale.Parent = screenGui

local function recomputeScale()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(HUD_REF_WIDTH, HUD_REF_HEIGHT)
	local s = math.min(vp.X / HUD_REF_WIDTH, vp.Y / HUD_REF_HEIGHT)
	hudScale.Scale = math.clamp(s, HUD_MIN_SCALE, HUD_MAX_SCALE)
end
recomputeScale()

local function hookCamera(cam)
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(recomputeScale)
end
hookCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(workspace.CurrentCamera)
	recomputeScale()
end)

-- Radiation icon (positioned above the three stat bars)
local icon = Instance.new("ImageLabel")
icon.Name = "RadiationIcon"
icon.AnchorPoint = Vector2.new(0, 1)
icon.Position = UDim2.new(0, BASE_X, 1, BASE_Y_OFFSET)
icon.Size = UDim2.new(0, 36, 0, 36)
icon.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
icon.BackgroundTransparency = 0.3
icon.Image = "rbxassetid://97523366830633"
icon.ScaleType = Enum.ScaleType.Stretch
icon.Visible = false
icon.Parent = screenGui

icon.ClipsDescendants = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = icon

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 60, 30)
stroke.Thickness = 2
stroke.Parent = icon

-- ─── Cooldown overlay (grows top→bottom as radiation expires) ───
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.Name = "CooldownOverlay"
cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
cooldownOverlay.Size = UDim2.new(1, 0, 0, 0) -- starts hidden
cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.5
cooldownOverlay.BorderSizePixel = 0
cooldownOverlay.ZIndex = 2
cooldownOverlay.Parent = icon

-- ─── Tooltip (hover description) ───
-- Parented to screenGui (not icon) to avoid ClipsDescendants clipping
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.Position = UDim2.new(0, BASE_X + 36 + 8, 1, BASE_Y_OFFSET)
-- ⚠️ Высота под ТРИ строки текста: в подсказку добавилась фраза «пройдёт
-- сама», и в прежние 60 пикселей она не влезала — обрезалась на полуслове.
tooltip.Size = UDim2.new(0, 200, 0, 76)
tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tooltip.BackgroundTransparency = 0.15
tooltip.Visible = false
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(120, 80, 30)
tooltipStroke.Thickness = 1.5
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Size = UDim2.new(1, -12, 0, 20)
tooltipTitle.Position = UDim2.new(0, 6, 0, 4)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = "Лучевая болезнь"
tooltipTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Size = UDim2.new(1, -12, 0, 46)
tooltipBody.Position = UDim2.new(0, 6, 0, 24)
tooltipBody.BackgroundTransparency = 1
-- ⚠️ Про «пройдёт само» тут тоже: ролик игрок увидит один раз и в панике, а
-- значок на HUD висит всю болезнь — именно к нему возвращаются с вопросом
-- «что мне теперь делать».
tooltipBody.Text = "Головная боль, голод растёт быстрее. Пройдёт сама, "
	.. "лечиться не нужно — просто переждите"
tooltipBody.TextColor3 = Color3.fromRGB(200, 200, 200)
tooltipBody.TextSize = 12
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextWrapped = true
tooltipBody.Parent = tooltip

icon.MouseEnter:Connect(function()
	if icon.Visible then
		tooltip.Visible = true
	end
end)

icon.MouseLeave:Connect(function()
	tooltip.Visible = false
end)

-- ─── Headache Visual Effect ───
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "RadiationCC"
colorCorrection.Enabled = false
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Name = "RadiationBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

-- ─── Radiation timer tracking ───
local RADIATION_DURATION = 60
local radiationStartTime = 0

local radiationEvent = game:GetService("ReplicatedStorage"):WaitForChild("RadiationUpdate", 10)

if radiationEvent then
	radiationEvent.OnClientEvent:Connect(function(active, remaining, duration)
		if active then
			RADIATION_DURATION = duration or 60
			radiationStartTime = tick() - (RADIATION_DURATION - (remaining or RADIATION_DURATION))
		end
	end)
end

-- ─── Position refresh (slot-aware) ───
local function refreshPosition()
	local slot = getSlotIndex("radiation")
	if slot < 0 then
		icon.Visible = false
		tooltip.Visible = false
		return
	end
	-- ⚠️ СВОЕЙ ИКОНКИ У РАДИАЦИИ БОЛЬШЕ НЕТ.
	-- Болезнь встроена в блок здоровья (UIManager, вариант 5b): само сердце
	-- становится значком болезни, а полоска зеленеет. Отдельная иконка рядом с
	-- ней стала вторым сообщением об одном и том же и путала — по ТЗ убрана.
	-- Скрипт остаётся жив ради ЭФФЕКТА ГОЛОВНОЙ БОЛИ (ColorCorrection + Blur
	-- ниже) и слежения за атрибутом; наружу он теперь ничего не рисует.
	-- Место в общем ряду статусов при этом занимать незачем — освобождаем.
	icon.Visible = false
	tooltip.Visible = false
	do return end
	local x = BASE_X + slot * SLOT_STRIDE
	icon.Position = UDim2.new(0, x, 1, BASE_Y_OFFSET)
	tooltip.Position = UDim2.new(0, x + 36 + 8, 1, BASE_Y_OFFSET)
end

table.insert(SLOTS.hooks, refreshPosition)

-- ─── Watch the RadiationSick attribute directly ───
--[[ ⚠️ ФЛАГ БОЛЕЗНИ ДЕРЖИМ ОТДЕЛЬНО ОТ ИКОНКИ.
     Пульсация ниже начиналась со строки «если иконка не видна — выходим», а
     иконку по ТЗ убрали (см. refreshPosition): эффект головной боли включался,
     но значения ему никто не выставлял — на экране не менялось ничего.
     Теперь пульс смотрит на саму болезнь. ]]
local sickNow = false

local function onRadiationChanged()
	local sick = player:GetAttribute("RadiationSick") == true
	sickNow = sick
	colorCorrection.Enabled = sick
	blur.Enabled = sick

	if sick then
		-- If we don't have a start time yet, assume just started
		if radiationStartTime == 0 then
			radiationStartTime = tick()
		end
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		takeSlot("radiation")
	else
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		blur.Size = 0
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		radiationStartTime = 0
		releaseSlot("radiation")
	end

	notifyAll()
end

-- Connect to attribute changes
player:GetAttributeChangedSignal("RadiationSick"):Connect(onRadiationChanged)

-- Check initial state
onRadiationChanged()

-- ─── Headache pulsing effect + cooldown overlay while sick ───
game:GetService("RunService").Heartbeat:Connect(function()
	if not sickNow then return end

	local pulse = math.sin(tick() * 3) * 0.5 + 0.5
	colorCorrection.Saturation = -0.4 - pulse * 0.2
	colorCorrection.Contrast = 0.1 + pulse * 0.15
	colorCorrection.TintColor = Color3.fromRGB(
		255,
		math.floor(230 - pulse * 40),
		math.floor(220 - pulse * 50)
	)
	blur.Size = 3 + pulse * 4

	-- Update cooldown overlay (grows from top to bottom)
	local elapsed = tick() - radiationStartTime
	local progress = math.clamp(elapsed / RADIATION_DURATION, 0, 1)
	cooldownOverlay.Size = UDim2.new(1, 0, progress, 0)
end)
--═══════════════════════════════════════════════════════════════════════════
-- ПРЕДУПРЕЖДЕНИЯ: РАДИАЦИЯ В ВОДЕ И КРИТИЧЕСКИЙ ГОЛОД/ЖАЖДА
--
-- Дизайн — «Предупреждения.dc.html»: плашка-стикер со значком в кружке,
-- тёмной обводкой и лёгким покачиванием. Две штуки:
--   • жёлтая «ОПАСНОСТЬ! Вода радиоактивна!» — сверху, когда игрок попал в воду;
--   • красная «ГОЛОД!/ЖАЖДА!» — над хотбаром, там же, где идут реплики
--     диалогов, когда запас упал ниже 10%.
--
-- ⚠️ ЖИВЁТ В ЭТОМ ФАЙЛЕ, А НЕ В СВОЁМ.
-- Rojo не всегда доносит НОВЫЕ файлы до уже подключённой сессии Studio: правки
-- существующих синхронизируются сразу, новый скрипт появляется только после
-- переподключения. Радиационный клиент — ближайший по смыслу (он и так про
-- опасность), поэтому плашки живут здесь.
--
-- ⚠️ ПРО «ОДИН РАЗ» У ГОЛОДА И ЖАЖДЫ.
-- Владелец просил: предупредить в ПЕРВЫЙ раз, а когда игрок восполнит запас —
-- больше не показывать. Поэтому флаг снимается только вместе с сессией: это
-- обучающая подсказка, а не сигнализация. Второй раз человек уже знает, что
-- полоска внизу слева значит.
--═══════════════════════════════════════════════════════════════════════════

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local HudScale
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudScale", 10))
	end)
	HudScale = ok and mod or nil
end

-- Множитель уведомлений: на телефоне плашка ужимается вместе с остальными
-- всплывающими сообщениями, на ПК остаётся в исходных пикселях макета.
local function noticeK()
	if HudScale and HudScale.noticeFactor then
		local ok, k = pcall(HudScale.noticeFactor)
		if ok and type(k) == "number" and k > 0 then return k end
	end
	return 1
end

local INK = Color3.fromRGB(20, 38, 26)   -- #14261a: общая тёмная обводка макета

-- ⚠️ ТА ЖЕ ВЫСОТА, ЧТО У ДИАЛОГОВ (DialogueUI, HOTBAR_CLEAR).
-- Владелец просил показывать предупреждение «над хотбаром, там где диалоги».
-- Число держим одинаковым: разъедутся — плашка сядет либо на хотбар, либо
-- поверх реплики.
local HOTBAR_CLEAR = 112

local warnGui = Instance.new("ScreenGui")
warnGui.Name = "HazardWarnings"
warnGui.DisplayOrder = 45          -- выше диалогов (40), ниже полноэкранных меню
warnGui.IgnoreGuiInset = true
warnGui.ResetOnSpawn = false
warnGui.Parent = playerGui

--[[ ⚠️ ОБЕ ПЛАШКИ ЖИВУТ В ОДНОЙ СТОПКЕ НАД ХОТБАРОМ.
     Владелец просил показывать предупреждения там же, где идут диалоги, —
     радиацию в том числе (в макете она сверху, но на экране верх занят
     «Днём N» и подсказкой квеста). Две плашки могут понадобиться разом:
     плаваешь в отраве и при этом голодный. Раскладка снизу вверх сама
     разведёт их по строкам, а спрятанную (Visible = false) UIListLayout
     пропускает — дырки на её месте не остаётся. ]]
local warnStack = Instance.new("Frame")
warnStack.Name = "Stack"
warnStack.BackgroundTransparency = 1
warnStack.AnchorPoint = Vector2.new(0.5, 1)
warnStack.Position = UDim2.new(0.5, 0, 1, -HOTBAR_CLEAR)
warnStack.Size = UDim2.fromOffset(0, 0)
warnStack.AutomaticSize = Enum.AutomaticSize.XY
warnStack.Parent = warnGui

--[[ ⚠️ КОГДА ОТКРЫТО ОКНО ДИАЛОГА — ВСТАЁМ НАД НИМ, А НЕ ПОВЕРХ.
     Плашка и реплика метят в одну точку: обе стоят над хотбаром. Пока говорит
     механик, предупреждение ложилось прямо на его слова.
     ⚠️ НИЗ СТОПКИ НЕ ВЫЧИСЛЯЕМ, А МЕРЯЕМ — тем же приёмом, что и сам диалог
     (DialogueUI.anchorToHotbar). У стопки AutomaticSize, и предсказать, куда
     движок положит нижнюю грань, нельзя: читаем фактическую AbsolutePosition и
     подтягиваем смещение на разницу. Ошибка гасится за кадр-два.
     Координаты сравнивать можно: у обоих ScreenGui IgnoreGuiInset = true, то
     есть они живут в одной системе координат. ]]
local STACK_GAP = 8       -- зазор до окна диалога или до слотов хотбара
local stackY = -HOTBAR_CLEAR

local function guiPart(...)
	local node = playerGui
	for _, name in ipairs({ ... }) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- верх того, над чем встаём: окно диалога важнее хотбара
local function stackCeiling()
	local column = guiPart("DialogueGui", "Column")
	if column and column:IsA("GuiObject") and column.Visible and column.AbsoluteSize.Y > 0 then
		return column.AbsolutePosition.Y
	end
	local bar = guiPart("HotbarGui", "Hotbar")
	if bar and bar:IsA("GuiObject") and bar.AbsoluteSize.Y > 0 then
		return bar.AbsolutePosition.Y
	end
	return nil
end

game:GetService("RunService").RenderStepped:Connect(function()
	if warnStack.AbsoluteSize.Y < 1 then return end   -- ничего не показано
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.Y < 1 then return end

	local ceiling = stackCeiling()
	local want = ceiling and (ceiling - STACK_GAP) or (vp.Y - HOTBAR_CLEAR)
	local bottom = warnStack.AbsolutePosition.Y + warnStack.AbsoluteSize.Y
	local err = bottom - want
	if math.abs(err) > 0.5 then
		stackY -= err
		warnStack.Position = UDim2.new(0.5, 0, 1, stackY)
	end
end)
local stackList = Instance.new("UIListLayout")
stackList.FillDirection = Enum.FillDirection.Vertical
stackList.HorizontalAlignment = Enum.HorizontalAlignment.Center
stackList.VerticalAlignment = Enum.VerticalAlignment.Bottom
stackList.SortOrder = Enum.SortOrder.LayoutOrder
stackList.Padding = UDim.new(0, 8)
stackList.Parent = warnStack

-- ── сборка плашки по макету ──
local function buildBanner(cfg)
	local K = noticeK()
	local function P(n) return math.max(1, math.floor(n * K + 0.5)) end

	--[[ ⚠️ ОБЫЧНЫЙ Frame, А НЕ CanvasGroup.
	     У группы есть GroupTransparency — гасить плашку одним твином удобнее. Но
	     она рисует детей в отдельную текстуру, и в паре с AutomaticSize это
	     ведёт себя непредсказуемо: размер может остаться нулевым, и плашки
	     просто не будет видно. Здесь важнее, чтобы она ТОЧНО появилась, поэтому
	     прозрачность гасим поэлементно — список ниже собирается при сборке. ]]
	local root = Instance.new("Frame")
	root.Name = cfg.name
	root.LayoutOrder = cfg.order
	root.Size = UDim2.fromOffset(0, 0)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundColor3 = cfg.bgTop
	root.BackgroundTransparency = 0
	root.Rotation = -1
	root.Visible = false
	root.Parent = warnStack

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(cfg.bgTop, cfg.bgBottom)
	grad.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, P(16))
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = P(4)
	stroke.Color = INK
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, P(8))
	pad.PaddingBottom = UDim.new(0, P(8))
	pad.PaddingLeft   = UDim.new(0, P(16))
	pad.PaddingRight  = UDim.new(0, P(22))
	pad.Parent = root

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, P(12))
	row.Parent = root

	-- значок в кружке
	local badge = Instance.new("Frame")
	badge.LayoutOrder = 1
	badge.Size = UDim2.fromOffset(P(44), P(44))
	badge.BackgroundColor3 = cfg.badgeTop
	badge.BorderSizePixel = 0
	badge.Parent = root

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)   -- круг
	badgeCorner.Parent = badge

	local badgeGrad = Instance.new("UIGradient")
	badgeGrad.Rotation = 90
	badgeGrad.Color = ColorSequence.new(cfg.badgeTop, cfg.badgeBottom)
	badgeGrad.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Thickness = P(3)
	badgeStroke.Color = cfg.badgeBorder
	badgeStroke.Parent = badge

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(P(30), P(30))
	icon.Image = cfg.icon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = badge

	-- две строки текста
	local col = Instance.new("Frame")
	col.LayoutOrder = 2
	col.BackgroundTransparency = 1
	col.Size = UDim2.fromOffset(0, 0)
	col.AutomaticSize = Enum.AutomaticSize.XY
	col.Parent = root

	local colList = Instance.new("UIListLayout")
	colList.FillDirection = Enum.FillDirection.Vertical
	colList.SortOrder = Enum.SortOrder.LayoutOrder
	colList.Padding = UDim.new(0, P(1))
	colList.Parent = col

	--[[ ⚠️ ШРИФТ GothamBlack, А НЕ ШРИФТ МАКЕТА.
	     В макете Fredoka/Baloo — в них нет кириллицы, и «ОПАСНОСТЬ!» приехало бы
	     квадратами. GothamBlack — тот же жирный гротеск, которым в проекте
	     набраны все русские заголовки. ]]
	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.Size = UDim2.fromOffset(0, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = P(24)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = cfg.title
	title.Parent = col

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = P(2)
	titleStroke.Color = cfg.titleInk
	titleStroke.Parent = title

	local body = Instance.new("TextLabel")
	body.LayoutOrder = 2
	body.BackgroundTransparency = 1
	body.AutomaticSize = Enum.AutomaticSize.XY
	body.Size = UDim2.fromOffset(0, 0)
	body.Font = Enum.Font.GothamBold
	body.TextSize = P(17)
	body.TextColor3 = INK
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.Text = cfg.body
	body.Parent = col

	-- что гасим при появлении и уходе: у каждого элемента своё свойство
	local fade = {
		{ obj = root,        prop = "BackgroundTransparency" },
		{ obj = stroke,      prop = "Transparency" },
		{ obj = badge,       prop = "BackgroundTransparency" },
		{ obj = badgeStroke, prop = "Transparency" },
		{ obj = icon,        prop = "ImageTransparency" },
		{ obj = title,       prop = "TextTransparency" },
		{ obj = titleStroke, prop = "Transparency" },
		{ obj = body,        prop = "TextTransparency" },
	}

	return {
		root = root, grad = grad, badge = badge, badgeGrad = badgeGrad,
		badgeStroke = badgeStroke, icon = icon,
		title = title, titleStroke = titleStroke, body = body,
		fade = fade, token = 0, shake = nil,
	}
end

--[[ Показать плашку на seconds секунд.
     token отсекает старое скрытие: если предупреждение пришло второй раз, пока
     первое ещё висит, спрятать его должен только последний показ. ]]
local function setFade(b, t)
	for _, e in ipairs(b.fade) do
		e.obj[e.prop] = t
	end
end

local function tweenFade(b, t, time)
	for _, e in ipairs(b.fade) do
		TweenService:Create(e.obj, TweenInfo.new(time), { [e.prop] = t }):Play()
	end
end

--[[ Показать плашку на seconds секунд.
     token отсекает старое скрытие: если предупреждение пришло второй раз, пока
     первое ещё висит, спрятать его должен только последний показ. ]]
local function showBanner(b, seconds)
	b.token += 1
	local my = b.token

	if b.shake then b.shake:Cancel() end
	setFade(b, 1)
	b.root.Visible = true
	b.root.Rotation = -3
	tweenFade(b, 0, 0.22)
	TweenService:Create(b.root,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = -1 }):Play()

	-- лёгкое покачивание, как в макете (dangerShake)
	b.shake = TweenService:Create(b.root,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.22),
		{ Rotation = 1 })
	b.shake:Play()

	task.delay(seconds, function()
		if b.token ~= my then return end
		if b.shake then b.shake:Cancel() end
		tweenFade(b, 1, 0.25)
		task.wait(0.3)
		if b.token == my then b.root.Visible = false end
	end)
end
-- ── плашка радиации ──
local radBanner = buildBanner({
	name = "RadiationWarning",
	order = 1,          -- верхняя строка стопки
	bgTop = Color3.fromRGB(240, 210, 77),   -- #f0d24d
	bgBottom = Color3.fromRGB(232, 168, 32), -- #e8a820
	badgeTop = Color3.fromRGB(208, 240, 136),
	badgeBottom = Color3.fromRGB(106, 168, 30),
	badgeBorder = Color3.fromRGB(77, 125, 18),
	titleInk = Color3.fromRGB(158, 31, 31),  -- #9e1f1f
	icon = "rbxassetid://127337495800958",   -- та же иконка радиации, что в HUD
	title = "ОПАСНОСТЬ!",
	body = "Вода радиоактивна!",
})

-- ── плашка голода/жажды (над хотбаром, где диалоги) ──
local needBanner = buildBanner({
	name = "NeedWarning",
	order = 2,          -- нижняя строка, ближе к хотбару
	bgTop = Color3.fromRGB(240, 106, 106),   -- #f06a6a
	bgBottom = Color3.fromRGB(196, 52, 52),  -- #c43434
	badgeTop = Color3.fromRGB(255, 217, 138),
	badgeBottom = Color3.fromRGB(209, 136, 26),
	badgeBorder = Color3.fromRGB(168, 106, 16),
	titleInk = Color3.fromRGB(112, 20, 20),  -- #701414
	icon = "rbxassetid://85208348940307",    -- мясо (иконка голода из HUD)
	title = "ГОЛОД!",
	body = "Уровень голода крайне низок, нужно поесть!",
})

local NEED_LOOK = {
	hunger = {
		icon = "rbxassetid://85208348940307",
		badgeTop = Color3.fromRGB(255, 217, 138),
		badgeBottom = Color3.fromRGB(209, 136, 26),
		badgeBorder = Color3.fromRGB(168, 106, 16),
		title = "ГОЛОД!",
		body = "Уровень голода крайне низок, нужно поесть!",
	},
	thirst = {
		icon = "rbxassetid://107900227969593",
		badgeTop = Color3.fromRGB(255, 255, 255),
		badgeBottom = Color3.fromRGB(168, 204, 240),
		badgeBorder = Color3.fromRGB(21, 96, 168),
		title = "ЖАЖДА!",
		body = "Уровень жажды крайне низок, нужно попить!",
	},
}

local function showNeed(kind)
	local look = NEED_LOOK[kind]
	if not look then return end
	needBanner.icon.Image = look.icon
	needBanner.badge.BackgroundColor3 = look.badgeTop
	needBanner.badgeGrad.Color = ColorSequence.new(look.badgeTop, look.badgeBottom)
	needBanner.badgeStroke.Color = look.badgeBorder
	needBanner.title.Text = look.title
	needBanner.body.Text = look.body
	showBanner(needBanner, 5)
end

-- ── триггер 1: попал в воду ──
--[[ Сигнал шлёт ToxicWater в момент входа в воду — там же, где считается урон,
     и с теми же исключениями: в маске и во сне предупреждения нет, потому что
     нет и урона. Свой таймер на клиенте — страховка от частых заплывов. ]]
local RAD_MIN_GAP = 12
local lastRadAt = 0

local hazardEvent = ReplicatedStorage:WaitForChild("HazardWarning", 30)
if hazardEvent then
	hazardEvent.OnClientEvent:Connect(function(kind)
		if kind ~= "radiation" then return end
		if tick() - lastRadAt < RAD_MIN_GAP then return end
		lastRadAt = tick()
		showBanner(radBanner, 4)
	end)
end

-- ── триггер 2: голод или жажда ниже 10% ──
local NEED_THRESHOLD = 0.10
local needWarned = { hunger = false, thirst = false }

local function watchNeed(kind, remoteName)
	local ev = ReplicatedStorage:WaitForChild(remoteName, 30)
	if not ev then return end
	ev.OnClientEvent:Connect(function(value, max)
		max = math.max(1, tonumber(max) or 100)
		local ratio = (tonumber(value) or max) / max
		if ratio > NEED_THRESHOLD then return end
		if needWarned[kind] then return end
		needWarned[kind] = true
		showNeed(kind)
	end)
end

watchNeed("hunger", "HungerUpdate")
watchNeed("thirst", "ThirstUpdate")

--═══════════════════════════════════════════════════════════════════════════
-- ЦИФРЫ УРОНА НАД ГОЛОВОЙ («-5 ❤»)
--
-- Из того же макета: получил по здоровью — над головой всплывает красное число
-- с сердцем и уезжает вверх. Работает на ЛЮБОЙ урон, не только на воду: отраву,
-- пиратов, падение — игрок видит, сколько именно у него сняли.
--
-- ⚠️ СЕРДЦЕ — КАРТИНКОЙ, А НЕ СИМВОЛОМ.
-- В макете стоит эмодзи ❤️. Roblox рисует эмодзи не всеми шрифтами и не на всех
-- платформах — где-то вместо сердца был бы квадрат. Берём ту же иконку здоровья,
-- что стоит в HUD (UIManager, ICONS.health): и не отвалится, и выглядит своим.
--
-- ⚠️ РЕГЕНЕРАЦИЯ ЧИСЕЛ НЕ РИСУЕТ.
-- Показываем только падение здоровья и только заметное (от единицы): иначе
-- лечение и мелкие тики сыпали бы нолями поверх головы.
--═══════════════════════════════════════════════════════════════════════════

local DMG_MIN        = 1        -- меньше единицы не показываем
local DMG_RISE       = 1.6      -- на сколько студов уезжает вверх
local DMG_TIME       = 0.9      -- секунд на весь полёт
local DMG_START_UP   = 2.6      -- стартовая высота над головой, студов
local DMG_MAX_ONSCREEN = 6      -- больше шести чисел разом — уже каша

local HEART_ICON = "rbxassetid://96378076686911"   -- та же иконка, что в HUD
local DMG_RED    = Color3.fromRGB(255, 90, 90)     -- #ff5a5a из макета

local liveNumbers = 0

--[[ ⚠️ БЛИЗКИЕ ТИКИ СКЛАДЫВАЕМ В ОДНО ЧИСЛО.
     Источников урона несколько, и самый частый — захлёбывание под маской
     (DiverAir бьёт каждые 0.25 секунды). Отдельная цифра на каждый тик — это
     четыре числа в секунду, экран превращается в кашу. Пока живёт последнее
     число и с его появления прошло меньше MERGE_WINDOW, просто прибавляем к
     нему: игрок видит растущую цифру, а не очередь мелких. ]]
local MERGE_WINDOW = 0.45
local lastPop = nil   -- { at = os.clock(), label = TextLabel, amount = число }

local function popDamage(head, amount)
	-- добавка к ещё живому числу вместо нового
	if lastPop and lastPop.label.Parent and (os.clock() - lastPop.at) < MERGE_WINDOW then
		lastPop.amount += amount
		lastPop.label.Text = "-" .. tostring(math.floor(lastPop.amount + 0.5))
		return
	end
	if liveNumbers >= DMG_MAX_ONSCREEN then return end
	liveNumbers += 1

	local K = noticeK()
	local function P(n) return math.max(1, math.floor(n * K + 0.5)) end

	local bb = Instance.new("BillboardGui")
	bb.Name = "DamagePop"
	bb.Size = UDim2.fromOffset(P(160), P(52))
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	-- разводим соседние числа по горизонтали: подряд идущие тики отравы иначе
	-- ложатся друг на друга и читаются как одно
	bb.StudsOffsetWorldSpace = Vector3.new(math.random(-9, 9) / 10, DMG_START_UP, 0)
	bb.Adornee = head
	bb.Parent = playerGui

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromOffset(0, 0)
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Parent = bb

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, P(4))
	list.Parent = row

	local num = Instance.new("TextLabel")
	num.LayoutOrder = 1
	num.BackgroundTransparency = 1
	num.AutomaticSize = Enum.AutomaticSize.XY
	num.Size = UDim2.fromOffset(0, 0)
	num.Font = Enum.Font.GothamBlack
	num.TextSize = P(30)
	num.TextColor3 = DMG_RED
	num.Text = "-" .. tostring(math.floor(amount + 0.5))
	num.Parent = row

	local ink = Instance.new("UIStroke")
	ink.Thickness = P(3)
	ink.Color = INK
	ink.Parent = num

	local heart = Instance.new("ImageLabel")
	heart.LayoutOrder = 2
	heart.BackgroundTransparency = 1
	heart.Size = UDim2.fromOffset(P(26), P(26))
	heart.Image = HEART_ICON
	heart.ScaleType = Enum.ScaleType.Fit
	heart.Parent = row

	local info = TweenInfo.new(DMG_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, {
		StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, DMG_RISE, 0),
	}):Play()
	TweenService:Create(num, info, { TextTransparency = 1 }):Play()
	TweenService:Create(ink, info, { Transparency = 1 }):Play()
	TweenService:Create(heart, info, { ImageTransparency = 1 }):Play()

	lastPop = { at = os.clock(), label = num, amount = amount }

	task.delay(DMG_TIME + 0.05, function()
		bb:Destroy()
		liveNumbers = math.max(0, liveNumbers - 1)
	end)
end

local function watchHealth(character)
	local hum = character:WaitForChild("Humanoid", 10)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 10)
	if not (hum and head) then return end

	local last = hum.Health
	hum.HealthChanged:Connect(function(hp)
		local drop = last - hp
		last = hp
		-- смерть отдельным числом не показываем: там своя катсцена и экран
		if drop >= DMG_MIN and hp > 0 then
			popDamage(head, drop)
		end
	end)
end

if player.Character then
	task.spawn(watchHealth, player.Character)
end
player.CharacterAdded:Connect(function(character)
	task.spawn(watchHealth, character)
end)

--═══════════════════════════════════════════════════════════════════════════
-- «ВЫ ЗАБОЛЕЛИ ЛУЧЕВОЙ БОЛЕЗНЬЮ!» — объявление во весь экран
--
-- Из макета «Предупреждения.dc.html», состояние sickOn: тёмно-зелёная заливка
-- поверх экрана, огромный знак радиации влетает с разворотом, под ним зелёный
-- заголовок и белая вторая строка. Через 3.5 секунды всё схлопывается и гаснет.
--
-- ⚠️ БЕЗ UIScale, ХОТЯ В МАКЕТЕ ЭТО transform: scale().
-- UIScale масштабирует содержимое от ЛЕВОГО ВЕРХНЕГО угла элемента, а не от
-- центра: заголовок при анимации уезжал бы в сторону. Поэтому размеры гоним
-- напрямую — картинке Size, надписям TextSize, — а центрирование держит
-- AnchorPoint 0.5. Так масштаб идёт ровно от середины.
--
-- ⚠️ ЗАЛИВКА ПЛОСКАЯ, А НЕ РАДИАЛЬНАЯ.
-- В макете radial-gradient от 0.55 к 0.75 по краям. UIGradient в Roblox только
-- линейный, радиального нет; разница между 0.55 и 0.75 на глаз почти не видна,
-- поэтому берём среднее одной заливкой — дешевле и без лишней картинки.
--═══════════════════════════════════════════════════════════════════════════

local SICK_ICON   = "rbxassetid://127337495800958"   -- знак радиации из HUD
local SICK_GREEN  = Color3.fromRGB(184, 232, 88)     -- #b8e858 из макета
local SICK_HOLD   = 2.5      -- сколько висит до ухода (было 3.5 — по просьбе короче)
local SICK_FADE   = 0.45     -- сколько уходит

local sickGui = Instance.new("ScreenGui")
sickGui.Name = "RadiationSickAnnounce"
sickGui.DisplayOrder = 60          -- выше плашек (45), ниже экрана загрузки
sickGui.IgnoreGuiInset = true
sickGui.ResetOnSpawn = false
sickGui.Enabled = false
sickGui.Parent = playerGui

local sickBg = Instance.new("Frame")
sickBg.Name = "Tint"
sickBg.BackgroundColor3 = INK          -- #14261a, как в макете
sickBg.BackgroundTransparency = 1
sickBg.BorderSizePixel = 0
sickBg.Size = UDim2.fromScale(1, 1)
sickBg.Parent = sickGui

local SICK_K = noticeK()
local function SP(n) return math.max(1, math.floor(n * SICK_K + 0.5)) end

local ICON_BASE = SP(140)

local sickIcon = Instance.new("ImageLabel")
sickIcon.Name = "Mark"
sickIcon.BackgroundTransparency = 1
sickIcon.AnchorPoint = Vector2.new(0.5, 0.5)
sickIcon.Position = UDim2.fromScale(0.5, 0.38)
sickIcon.Size = UDim2.fromOffset(0, 0)
sickIcon.Image = SICK_ICON
sickIcon.ScaleType = Enum.ScaleType.Fit
sickIcon.Parent = sickGui

local TITLE_BASE = SP(52)
local SUB_BASE   = SP(38)

local sickTitle = Instance.new("TextLabel")
sickTitle.Name = "Title"
sickTitle.BackgroundTransparency = 1
sickTitle.AnchorPoint = Vector2.new(0.5, 0.5)
sickTitle.Position = UDim2.fromScale(0.5, 0.56)
sickTitle.Size = UDim2.new(1, 0, 0, SP(64))
sickTitle.Font = Enum.Font.GothamBlack
sickTitle.TextSize = TITLE_BASE
sickTitle.TextColor3 = SICK_GREEN
sickTitle.Text = "ВЫ ЗАБОЛЕЛИ"
sickTitle.Parent = sickGui

local sickTitleInk = Instance.new("UIStroke")
sickTitleInk.Thickness = SP(4)
sickTitleInk.Color = INK
sickTitleInk.Parent = sickTitle

local sickSub = Instance.new("TextLabel")
sickSub.Name = "Sub"
sickSub.BackgroundTransparency = 1
sickSub.AnchorPoint = Vector2.new(0.5, 0.5)
sickSub.Position = UDim2.fromScale(0.5, 0.645)
sickSub.Size = UDim2.new(1, 0, 0, SP(48))
sickSub.Font = Enum.Font.GothamBlack
sickSub.TextSize = SUB_BASE
sickSub.TextColor3 = Color3.new(1, 1, 1)
sickSub.Text = "ЛУЧЕВОЙ БОЛЕЗНЬЮ!"
sickSub.Parent = sickGui

local sickSubInk = Instance.new("UIStroke")
sickSubInk.Thickness = SP(3)
sickSubInk.Color = INK
sickSubInk.Parent = sickSub

--[[ ⚠️ ТРЕТЬЯ СТРОКА — ПРО ТО, ЧТО ДЕЛАТЬ ДАЛЬШЕ.
     Первые две сообщают беду и на этом бросают игрока: экран зелёный, голод
     бежит быстрее, а лекарства в игре нет — и человек ищет несуществующее
     решение вместо того, чтобы просто переждать. Пишем прямо: пройдёт само.
     Время берём из того же числа, что прислал сервер (RADIATION_DURATION в
     событии радиации), а не пишем «минуту» словом: поменяют длительность —
     надпись соврёт, и заметят это не скоро. ]]
local HINT_BASE = SP(22)

local sickHint = Instance.new("TextLabel")
sickHint.Name = "Hint"
sickHint.BackgroundTransparency = 1
sickHint.AnchorPoint = Vector2.new(0.5, 0.5)
sickHint.Position = UDim2.fromScale(0.5, 0.715)
sickHint.Size = UDim2.new(1, 0, 0, SP(30))
sickHint.Font = Enum.Font.GothamMedium
sickHint.TextSize = HINT_BASE
sickHint.TextColor3 = Color3.fromRGB(226, 236, 220)
sickHint.Text = ""
sickHint.Parent = sickGui

local sickHintInk = Instance.new("UIStroke")
sickHintInk.Thickness = SP(2)
sickHintInk.Color = INK
sickHintInk.Parent = sickHint

-- «60 сек» читается хуже, чем «минуту»: переводим в человеческий вид, но
-- ровно из того числа, что пришло с сервера
local function sickWaitText(sec)
	sec = math.max(1, math.floor((tonumber(sec) or 60) + 0.5))
	if sec >= 60 then
		local m = math.floor(sec / 60 + 0.5)
		if m == 1 then return "минуту" end
		return ("%d мин"):format(m)
	end
	return ("%d сек"):format(sec)
end

local sickToken = 0

local function sickReset()
	sickBg.BackgroundTransparency = 1
	sickIcon.Size = UDim2.fromOffset(0, 0)
	sickIcon.Rotation = -180
	sickIcon.ImageTransparency = 0
	sickTitle.TextSize = TITLE_BASE * 3
	sickTitle.TextTransparency = 1
	sickTitleInk.Transparency = 1
	sickSub.TextSize = SUB_BASE * 3
	sickSub.TextTransparency = 1
	sickSubInk.Transparency = 1
	sickHint.TextTransparency = 1
	sickHintInk.Transparency = 1
end

--[[ Полный проход анимации из макета:
       0.00  экран темнеет, знак влетает с разворотом и перелётом (1.25 → 1);
       0.35  надписи схлопываются с тройного размера до своего (3 → 0.92 → 1);
       1.00  три коротких «вдоха» знаком и текстом;
       3.50  всё сжимается и гаснет.
     Каждый показ увеличивает sickToken: если болезнь пришла второй раз, пока
     играет первый ролик, старые отложенные шаги молча выходят. ]]
local function showSick()
	sickToken += 1
	local my = sickToken

	sickReset()
	sickHint.Text = ("Пройдёт сама примерно за %s — просто переждите")
		:format(sickWaitText(RADIATION_DURATION))
	sickGui.Enabled = true

	TweenService:Create(sickBg, TweenInfo.new(0.3), { BackgroundTransparency = 0.35 }):Play()

	-- знак: влёт с перелётом, потом осадка в размер
	TweenService:Create(sickIcon,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(ICON_BASE * 1.25, ICON_BASE * 1.25), Rotation = 8 }):Play()
	task.delay(0.45, function()
		if sickToken ~= my then return end
		TweenService:Create(sickIcon, TweenInfo.new(0.25),
			{ Size = UDim2.fromOffset(ICON_BASE, ICON_BASE), Rotation = 0 }):Play()
	end)

	-- надписи: с тройного размера в свой, с лёгким перелётом
	task.delay(0.35, function()
		if sickToken ~= my then return end
		for _, e in ipairs({
			{ label = sickTitle, ink = sickTitleInk, base = TITLE_BASE },
			{ label = sickSub,   ink = sickSubInk,   base = SUB_BASE },
		}) do
			TweenService:Create(e.label,
				TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ TextSize = math.floor(e.base * 0.96), TextTransparency = 0 }):Play()
			TweenService:Create(e.ink, TweenInfo.new(0.4), { Transparency = 0 }):Play()
			task.delay(0.4, function()
				if sickToken ~= my then return end
				TweenService:Create(e.label, TweenInfo.new(0.2), { TextSize = e.base }):Play()
			end)
		end
	end)

	-- ⚠️ ОДИН «ВДОХ», А НЕ ТРИ, КАК В МАКЕТЕ.
	-- Ролик укоротили до 2.5 секунды: три вдоха по секунде в него уже не влезают
	-- и обрывались бы затуханием на полпути. Один влезает целиком.
	-- подсказка приходит последней: сперва человек читает, ЧТО случилось
	task.delay(0.75, function()
		if sickToken ~= my then return end
		TweenService:Create(sickHint, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
		TweenService:Create(sickHintInk, TweenInfo.new(0.35), { Transparency = 0 }):Play()
	end)

	task.delay(1.05, function()
		if sickToken ~= my then return end
		local pulse = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		TweenService:Create(sickIcon, pulse,
			{ Size = UDim2.fromOffset(ICON_BASE * 1.06, ICON_BASE * 1.06) }):Play()
		TweenService:Create(sickTitle, pulse, { TextSize = math.floor(TITLE_BASE * 1.06) }):Play()
	end)

	-- уход: всё сжимается и гаснет
	task.delay(SICK_HOLD, function()
		if sickToken ~= my then return end
		local out = TweenInfo.new(SICK_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(sickBg, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(sickIcon, out, {
			Size = UDim2.fromOffset(ICON_BASE * 0.55, ICON_BASE * 0.55),
			ImageTransparency = 1,
		}):Play()
		TweenService:Create(sickTitle, out,
			{ TextSize = math.floor(TITLE_BASE * 0.55), TextTransparency = 1 }):Play()
		TweenService:Create(sickTitleInk, out, { Transparency = 1 }):Play()
		TweenService:Create(sickHint, out, { TextTransparency = 1 }):Play()
		TweenService:Create(sickHintInk, out, { Transparency = 1 }):Play()
		TweenService:Create(sickSub, out,
			{ TextSize = math.floor(SUB_BASE * 0.55), TextTransparency = 1 }):Play()
		TweenService:Create(sickSubInk, out, { Transparency = 1 }):Play()

		task.delay(SICK_FADE + 0.05, function()
			if sickToken ~= my then return end
			sickGui.Enabled = false
			sickReset()
		end)
	end)
end

sickReset()

--[[ ⚠️ СЛУШАЕМ АТРИБУТ САМИ, А НЕ ВСТРАИВАЕМСЯ В onRadiationChanged.
     Там своя забота — эффект головной боли, и он срабатывает и на выздоровление
     тоже. Ролик нужен ровно на переход «здоров → заболел», поэтому отдельная
     подписка с проверкой значения. Болезнь ставит ToxicWater после третьего
     тика урона в воде (applyRadiation), она же снимается по смерти и по
     таймеру — на снятие ролик не играем. ]]
player:GetAttributeChangedSignal("RadiationSick"):Connect(function()
	if player:GetAttribute("RadiationSick") == true then
		showSick()
	end
end)
