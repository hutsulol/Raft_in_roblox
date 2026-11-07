--[[
	НОВЫЙ ПЕРСОНАЖ! — полноэкранный попап, когда в команде появился выживший
	(хендофф design_handoff_new_character, тема «Океан»).
	Мир затемняется → заголовок → свечение цвета редкости (лучи крутятся, центр
	пульсирует, искры мерцают) → голова крутится в кольце → звёзды дугой по одной
	→ имя цветом редкости и белая метка редкости.

	Событие SurvivorUnlocked(defId) шлёт SurvivorService (_G.GrantSurvivor —
	в том числе кнопка в настройках). Данные: SurvivorDefs.CATALOG (name, stars,
	head) и SurvivorDefs.STAR_TIERS. Несколько подряд — очередью.
	Закрыть: клик, Space / A на геймпаде, иначе само через 3,5 с после звёзд.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local D = require(ReplicatedStorage:WaitForChild("SurvivorDefs"))
local Assets = require(ReplicatedStorage:WaitForChild("NewCharacterAssets"))
local Unlocked = ReplicatedStorage:WaitForChild("SurvivorUnlocked")

local OUTLINE = Color3.fromHex("0D2A4F")
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local SHOW_TIME = 3.5
local BACK = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local gui = Instance.new("ScreenGui")
gui.Name = "NewCharacterPopup"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 200
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function stroke(p, t) return new("UIStroke", { Color = OUTLINE, Thickness = t, LineJoinMode = Enum.LineJoinMode.Round }, p) end
local function centered(name, size, parent, z)
	return new("ImageLabel", { Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), ZIndex = z }, parent)
end

-- затемнение мира (клик = закрыть)
local dim = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = OUTLINE, BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1), ZIndex = 1 }, gui)

local root = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(380, 520), ZIndex = 2 }, gui)
local rootScale = new("UIScale", {}, root)
-- вёрстка в пикселях 1080p: под экран ниже — ужимаем целиком
local function fitScreen()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 1080
	return math.clamp(h / 900, 0.55, 1.2)
end

-- заголовок
local title = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, Text = "НОВЫЙ ПЕРСОНАЖ!", TextSize = 34,
	TextColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(380, 40), ZIndex = 10 }, root)
stroke(title, 3.5)
local titleScale = new("UIScale", {}, title)

-- сцена 380×300 (свечение + голова)
local stage = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(380, 300), ZIndex = 2 }, root)
local stageScale = new("UIScale", {}, stage)
local rays = centered("Rays", 380, stage, 2); rays.Image = Assets.GlowRays
local rays2 = centered("RaysCounter", 304, stage, 3); rays2.Image = Assets.GlowRaysThin; rays2.ImageTransparency = 0.35
local soft = centered("Soft", 266, stage, 4); soft.Image = Assets.GlowSoft

local SPARKS = { { -150, -110, 16, 0 }, { 155, -80, 12, 0.5 }, { -130, 90, 10, 0.9 }, { 140, 110, 14, 0.3 }, { 0, -170, 10, 1.2 }, { -60, 140, 12, 0.7 } }
local sparkles = {}
for i, s in ipairs(SPARKS) do
	local sp = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Sparkle, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, s[1], 0.5, s[2]), Size = UDim2.fromOffset(s[3], s[3]), ZIndex = 5 }, stage)
	sparkles[i] = { ui = sp, size = s[3], delay = s[4] }
end

-- голова 170: кольцо цвета редкости + тёмная обводка + картинка
local headHolder = centered("HeadHolder", 170, stage, 6)
headHolder.Image = ""
local headScale = new("UIScale", {}, headHolder)
local head = new("ImageLabel", { BackgroundColor3 = Color3.fromHex("A9D6F7"), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 6, ScaleType = Enum.ScaleType.Stretch }, headHolder)   -- Stretch, не Crop: при «повороте» ширина сжимается, и Crop обрезал картинку вместо сжатия — голова стояла, крутилось только кольцо
new("UICorner", { CornerRadius = UDim.new(1, 0) }, head)
new("UIStroke", { Color = OUTLINE, Thickness = 5 }, head)
local ring = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.HeadRing, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), ZIndex = 7 }, head)

-- звёзды (дуга)
local starRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 286), Size = UDim2.fromOffset(300, 56), ZIndex = 10 }, root)
local stars = {}
for i = 1, 5 do
	local st = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Star, AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(38, 38), ZIndex = 10, Visible = false }, starRow)
	stars[i] = { ui = st, scale = new("UIScale", {}, st) }
end

-- имя + метка редкости
local nameBlock = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 348), Size = UDim2.fromOffset(380, 80), ZIndex = 10 }, root)
local nameScale = new("UIScale", {}, nameBlock)
new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, nameBlock)
local nameLabel = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 36, AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0), LayoutOrder = 1, ZIndex = 10 }, nameBlock)
stroke(nameLabel, 3.5)
local pill = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2, ZIndex = 10 }, nameBlock)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
new("UIStroke", { Color = OUTLINE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, pill)
local rarityLabel = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 16, TextColor3 = OUTLINE,
	AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), ZIndex = 10 }, pill)

-- постоянная анимация
local t0, spin, showing = 0, 8, false
RunService.RenderStepped:Connect(function()
	if not showing then return end
	local t = os.clock() - t0
	rays.Rotation = (t / spin * 360) % 360
	rays2.Rotation = -(t / (spin * 1.6) * 360) % 360
	local k = 0.5 - 0.5 * math.cos(t / 1.6 * math.pi * 2)
	local s = 0.82 + 0.30 * k
	soft.Size = UDim2.fromOffset(266 * s, 266 * s)
	soft.ImageTransparency = 0.45 * (1 - k)
	for _, sp in ipairs(sparkles) do
		local q = 0.5 - 0.5 * math.cos((t + sp.delay) / 1.4 * math.pi * 2)
		local z = sp.size * (0.6 + 0.4 * q)
		sp.ui.Size = UDim2.fromOffset(z, z)
		sp.ui.ImageTransparency = 0.7 * (1 - q)
	end
	-- голова: оборот вокруг Y (3.2 c) после 0.7 c
	if t > 0.7 then
		local a = (t - 0.7) / 3.2 * math.pi * 2
		head.Size = UDim2.fromScale(math.max(math.abs(math.cos(a)), 0.04), 1)
		head.Position = UDim2.new(0.5, 0, 0.5, -8 * math.abs(math.sin(a)))
	end
end)

local function pop(scaleObj, delay, info)
	scaleObj.Scale = 0
	task.delay(delay, function() TweenService:Create(scaleObj, info or BACK, { Scale = 1 }):Play() end)
end

local queue, busy, closeSignal = {}, false, nil

local function play(defId)
	local c = D.CATALOG[defId]
	if not c then return end
	local n = math.clamp(tonumber(c.stars) or 1, 1, 5)
	local T = D.STAR_TIERS[c.tier or n] or D.STAR_TIERS[n]   -- tier: особый вид (Cold Cap — ультра-редкий)

	rays.ImageColor3, rays2.ImageColor3, soft.ImageColor3, ring.ImageColor3 = T.glow, T.glow, T.glow, T.glow
	rays2.Visible = T.counter
	for i, sp in ipairs(sparkles) do sp.ui.Visible = i <= T.sparkles; sp.ui.ImageColor3 = T.glow end
	head.Image = c.head or Assets.HeadPlaceholder
	head.Size = UDim2.fromScale(1, 1); head.Position = UDim2.fromScale(0.5, 0.5)
	nameLabel.Text = c.name; nameLabel.TextColor3 = T.text
	rarityLabel.Text = string.upper(T.name)
	spin = T.spin

	-- раскладка звёзд дугой: средняя крупнее и выше
	local gap = 6
	local sizes, total = {}, 0
	for i = 1, n do
		local off = math.abs(i - (n + 1) / 2)
		sizes[i] = off < 0.6 and 46 or 38
		total += sizes[i]
	end
	total += gap * (n - 1)
	local x = 150 - total / 2
	for i = 1, 5 do
		local st = stars[i]
		st.ui.Visible = i <= n
		if i <= n then
			local off = math.abs(i - (n + 1) / 2)
			st.ui.Size = UDim2.fromOffset(sizes[i], sizes[i])
			st.ui.Position = UDim2.fromOffset(x + sizes[i] / 2, 56 - (14 - off * off * 4))
			x += sizes[i] + gap
			st.ui.Rotation = -60
			pop(st.scale, 0.6 + 0.15 * (i - 1), TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
			task.delay(0.6 + 0.15 * (i - 1), function()
				TweenService:Create(st.ui, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
			end)
		end
	end

	-- вход
	gui.Enabled = true
	showing = true
	t0 = os.clock()
	rootScale.Scale = fitScreen()
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
	pop(titleScale, 0)
	pop(stageScale, 0, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	pop(headScale, 0.3)
	pop(nameScale, 0.6 + 0.15 * n + 0.2, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))

	-- ждём таймер или клик
	local done = false
	closeSignal = function() done = true end
	local start = os.clock()
	while not done and os.clock() - start < SHOW_TIME + 0.6 + 0.15 * n do task.wait() end
	closeSignal = nil

	-- выход
	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local tw = TweenService:Create(rootScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
	tw:Play(); tw.Completed:Wait()
	showing = false
	gui.Enabled = false
end

local function pump()
	if busy then return end
	busy = true
	while #queue > 0 do play(table.remove(queue, 1)) end
	busy = false
end

dim.Activated:Connect(function() if closeSignal then closeSignal() end end)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if closeSignal and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA) then closeSignal() end
end)

Unlocked.OnClientEvent:Connect(function(defId)
	table.insert(queue, defId)
	task.spawn(pump)
end)

--[[ ⚠️ ПОПАП ПОКАЗЫВАЕТСЯ ОДИН РАЗ — НЕДОГРУЗИВШАЯСЯ КАРТИНКА = ПРОПАЛА НАВСЕГДА.
     Поэтому все его картинки и головы всех выживших рисуются заранее скрыто на
     полке иконок (ModelIcon.warmImages — та же, что прогревает инвентарь):
     под шторкой загрузки в полный размер, потом точкой, полку не удаляем. ]]
task.spawn(function()
	local ids = {}
	for _, id in pairs(Assets) do table.insert(ids, id) end
	for _, def in pairs(D.CATALOG) do
		if type(def.head) == "string" then table.insert(ids, def.head) end
	end
	local ok, ModelIcon = pcall(require, ReplicatedStorage:WaitForChild("ModelIcon"))
	if ok and ModelIcon.warmImages then
		print(("[Новый персонаж/клиент] картинки прогреты на полке: %d"):format(ModelIcon.warmImages(ids)))
	end
	-- и скачать сразу, не дожидаясь отрисовки полки
	local list = {}
	for _, id in ipairs(ids) do
		local img = Instance.new("ImageLabel")
		img.Image = id
		table.insert(list, img)
	end
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
end)

print("[Новый персонаж/клиент] попап готов (событие SurvivorUnlocked)")
