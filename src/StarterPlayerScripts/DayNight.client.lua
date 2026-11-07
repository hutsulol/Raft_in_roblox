-- DayNight.client.lua
-- СЧЁТЧИК ДНЯ/НОЧИ по макету из design_handoff_dialogue_ui (раздел 3).
--
-- Без подложки, прямо поверх неба: иконка ☀️/🌙 и надпись «День N» / «Ночь N».
-- При смене суток солнце и луна меняются ПЕРЕКРЁСТНО: уходящая иконка гаснет,
-- отворачиваясь на −120° и сжимаясь до 0.3; приходящая приезжает навстречу.
-- Текст кроссфейдится со сдвигом по вертикали. Всё 0.7 с с перелётом (Back/Out —
-- ближайший к overshoot-кривой макета).
--
-- Ночь определяем по ClockTime, как и весь остальной проект: день 6→18, ночь 18→6
-- (DayNightCircle.server.lua). Отдельного флага сервер не публикует.
--
-- Шрифт макета — Russo One; берём GothamBlack по той же причине, что и в диалогах:
-- гарантированная кириллица.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local dayCount  = ReplicatedStorage:WaitForChild("DayCount")

local WHITE       = Color3.fromRGB(255, 255, 255)
local SHADOW_BLUE = Color3.fromRGB(20, 60, 100)
local FONT        = Enum.Font.GothamBlack
local SWAP_TIME   = 0.7
local SHIFT       = 16      -- на сколько текст уезжает по вертикали при смене

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local gui = new("ScreenGui", {
	Name = "DayCounterUI", DisplayOrder = 10, IgnoreGuiInset = true, ResetOnSpawn = false,
}, playerGui)

local root = new("Frame", {
	Name = "DayNight", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X,
}, gui)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10),
}, root)

-- обе иконки живут в одном слоте: так они меняются перекрёстно, а не сдвигают текст
local iconSlot = new("Frame", {
	Name = "Icon", LayoutOrder = 1, BackgroundTransparency = 1,
	Size = UDim2.fromOffset(40, 40),
}, root)

local function makeIcon(char)
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1, Text = char, TextSize = 34, Font = Enum.Font.SourceSansBold,
		TextColor3 = WHITE, TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.6,
		Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}, iconSlot)
	return lbl, new("UIScale", { Scale = 1 }, lbl)
end

local sunLbl,  sunScale  = makeIcon("☀️")
local moonLbl, moonScale = makeIcon("🌙")

local textLbl = new("TextLabel", {
	Name = "Text", LayoutOrder = 2, BackgroundTransparency = 1,
	Font = FONT, TextSize = 32, TextColor3 = WHITE,
	TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.45,
	Text = "День " .. dayCount.Value,
	Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X,
}, root)

-- ═══ ВРЕМЯ ПОД ДНЁМ (хендофф HANDOFF.md, разд. 1) ═══
-- Игровые часы — общие Lighting.ClockTime (день 6→18, ночь 18→6), поэтому
-- время на экране совпадает с тем, по которому живут вышка и ферма.
local timeRow = new("Frame", {
	Name = "TimeRow", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10 + 44 + 2),
	Size = UDim2.fromOffset(120, 34),
}, gui)
local timeLbl = new("TextLabel", {
	Name = "Time", BackgroundTransparency = 1,
	Font = FONT, TextSize = 26, TextColor3 = WHITE,
	TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.45,
	Size = UDim2.fromScale(1, 1), Text = "06:00",
}, timeRow)

local lastMin = -1
RunService.Heartbeat:Connect(function()
	local t = Lighting.ClockTime
	local mins = math.floor(t * 60 + 0.5)
	if mins == lastMin then return end
	lastMin = mins
	timeLbl.Text = string.format("%02d:%02d", (mins // 60) % 24, mins % 60)
end)

-- ═══ НАЧИСЛЕНИЕ ЗА ЧАС (хендофф, разд. 2a) ═══
-- Сервер (PassiveIncome) шлёт HourlyIncome(money, oilMl) на границе игрового
-- часа. Под временем всплывает «[монета] +N  [капля] +M» и тает; баланс в HUD
-- сам подпрыгивает по атрибуту Pirate (UIManager).
local COIN_ICON = "rbxassetid://93617165412571"   -- та же монета, что в HUD
local DROP_ICON = "rbxassetid://91990135767096"   -- запасная капля (OilRigDefs.TEX_DROP)

-- ⚠️ КАПЛЯ — ТА ЖЕ, ЧТО НА ЭКРАНЕ БАКА. Владелец хочет чёрную каплю с
-- бочки; её картинка лежит в авторском SurfaceGui детали Oil_screen, id в
-- коде нет. Берём с самой детали, когда она доедет; не нашли — запасная.
local function findTankDrop()
	local screen = Workspace:FindFirstChild("Oil_screen", true)
	local gui = screen and screen:FindFirstChildWhichIsA("SurfaceGui")
	if not gui then return nil end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ImageLabel") and d.Image ~= "" then return d.Image end
	end
	return nil
end
task.spawn(function()
	for _ = 1, 60 do
		local img = findTankDrop()
		if img then DROP_ICON = img return end
		task.wait(1)
	end
end)

local function fmtGain(n)
	n = math.floor(n + 0.5)
	if n >= 1e6 then return (string.format("%.1f", n / 1e6):gsub("%.0$", "")) .. "M" end
	if n >= 1e3 then return (string.format("%.1f", n / 1e3):gsub("%.0$", "")) .. "K" end
	return tostring(n)
end

local function playGain(money, oil)
	local g = new("CanvasGroup", {
		Name = "Gain", BackgroundTransparency = 1, GroupTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
	}, timeRow)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, g)
	local sc = new("UIScale", { Scale = 0.6 }, g)
	local function item(order, icon, iconSize, text, color)
		local ic = new("ImageLabel", {
			LayoutOrder = order, BackgroundTransparency = 1, Image = icon,
			Size = UDim2.fromOffset(iconSize.X, iconSize.Y), ScaleType = Enum.ScaleType.Fit,
		}, g)
		new("TextLabel", {
			LayoutOrder = order + 1, BackgroundTransparency = 1, Font = FONT, TextSize = 24,
			TextColor3 = color, TextStrokeColor3 = SHADOW_BLUE, TextStrokeTransparency = 0.45,
			Text = text, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		}, g)
		return ic
	end
	local coin
	if money > 0 then coin = item(1, COIN_ICON, Vector2.new(28, 28), "+" .. fmtGain(money), Color3.fromRGB(255, 213, 74)) end
	if oil > 0 then item(3, DROP_ICON, Vector2.new(24, 30), "+" .. fmtGain(oil) .. " мл", WHITE) end

	-- ⚠️ ТЕМП ВДВОЕ МЕДЛЕННЕЕ ХЕНДОФФА (0.32/1.12/1.6 → 0.64/2.24/3.2 с):
	-- владелец: «слишком быстрая». Все фазы растянуты одним множителем.
	local K = 2
	local back = TweenInfo.new(0.32 * K, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(g, back, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, 4) }):Play()
	TweenService:Create(sc, back, { Scale = 1.1 }):Play()
	if coin then
		-- монета крутится: сжатие по X туда-обратно (0.9 с в хендоффе)
		TweenService:Create(coin, TweenInfo.new(0.45 * K, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, true),
			{ Size = UDim2.fromOffset(2, 28) }):Play()
	end
	task.delay(0.32 * K, function()
		if not g.Parent then return end
		TweenService:Create(sc, TweenInfo.new(0.8 * K, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		TweenService:Create(g, TweenInfo.new(0.8 * K, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, 8) }):Play()
	end)
	task.delay(1.12 * K, function()
		if not g.Parent then return end
		TweenService:Create(g, TweenInfo.new(0.48 * K, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1, Position = UDim2.new(0.5, 0, 1, 26) }):Play()
		TweenService:Create(sc, TweenInfo.new(0.48 * K, Enum.EasingStyle.Quad), { Scale = 0.9 }):Play()
	end)
	task.delay(1.6 * K, function() if g.Parent then g:Destroy() end end)

	-- искры: 8 точек разлетаются по эллипсу и тают
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local dot = new("Frame", {
			BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 213, 74) or WHITE,
			BorderSizePixel = 0, Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 16), BackgroundTransparency = 1,
		}, timeRow)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		task.delay(i * 0.06, function()
			if not dot.Parent then return end
			dot.BackgroundTransparency = 0
			TweenService:Create(dot, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(a) * 70 * 1.6, 1, 16 + math.sin(a) * 18 * 1.6 - 8),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(1.7, function() if dot.Parent then dot:Destroy() end end)
		end)
	end
end

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("HourlyIncome", 30)
	if remote then
		remote.OnClientEvent:Connect(function(money, oil)
			playGain(tonumber(money) or 0, tonumber(oil) or 0)
		end)
	end
end)

-- ── состояние ──
local function isNight()
	local t = Lighting.ClockTime
	return t < 6 or t >= 18
end

local night = isNight()

local function label()
	return (night and "Ночь " or "День ") .. dayCount.Value
end

-- мгновенно расставить иконки без анимации (стартовое состояние)
local function applyIcons()
	local shown = night and moonLbl or sunLbl
	local hidden = night and sunLbl or moonLbl
	shown.TextTransparency = 0
	shown.TextStrokeTransparency = 0.6
	shown.Rotation = 0
	;(night and moonScale or sunScale).Scale = 1
	hidden.TextTransparency = 1
	hidden.TextStrokeTransparency = 1
	;(night and sunScale or moonScale).Scale = 0.3
end
applyIcons()
textLbl.Text = label()

-- ── перекрёстная смена иконок ──
local function swapIcons()
	local outLbl   = night and sunLbl  or moonLbl
	local outScale = night and sunScale or moonScale
	local inLbl    = night and moonLbl or sunLbl
	local inScale  = night and moonScale or sunScale

	local fade  = TweenInfo.new(SWAP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local pop   = TweenInfo.new(SWAP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	TweenService:Create(outLbl, fade, { TextTransparency = 1, TextStrokeTransparency = 1, Rotation = -120 }):Play()
	TweenService:Create(outScale, pop, { Scale = 0.3 }):Play()

	inLbl.Rotation = 120        -- приходящая идёт навстречу уходящей
	inScale.Scale = 0.3
	TweenService:Create(inLbl, fade, { TextTransparency = 0, TextStrokeTransparency = 0.6, Rotation = 0 }):Play()
	TweenService:Create(inScale, pop, { Scale = 1 }):Play()
end

-- ── кроссфейд текста со сдвигом ──
local textBusy = false
local function swapText()
	if textBusy then
		textLbl.Text = label()   -- смена пришла посреди анимации: не копим очередь
		return
	end
	textBusy = true
	local half = TweenInfo.new(SWAP_TIME * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local up = TweenService:Create(textLbl, half,
		{ TextTransparency = 1, TextStrokeTransparency = 1 })
	up:Play()
	up.Completed:Connect(function()
		textLbl.Text = label()
		textLbl.Position = UDim2.fromOffset(0, -SHIFT)  -- заезжает сверху
		TweenService:Create(textLbl,
			TweenInfo.new(SWAP_TIME * 0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ TextTransparency = 0, TextStrokeTransparency = 0.45, Position = UDim2.fromOffset(0, 0) }):Play()
		task.delay(SWAP_TIME * 0.55, function() textBusy = false end)
	end)
end

-- ── подписки ──
-- ClockTime меняется каждый кадр, поэтому реагируем только на САМ ПЕРЕХОД день↔ночь.
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	local now = isNight()
	if now == night then return end
	night = now
	swapIcons()
	swapText()
end)

dayCount.Changed:Connect(function()
	swapText()
end)
