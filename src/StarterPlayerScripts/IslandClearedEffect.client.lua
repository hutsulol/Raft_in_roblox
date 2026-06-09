-- IslandClearedEffect.client.lua
-- Анимация награды «ОСТРОВ ЗАЧИЩЕН!»:
--   1) лёгкое затемнение мира;
--   2) золотой баннер «впрыгивает» сверху (Back/Out) с эффектом удара (scale-punch);
--   3) искры-частицы разлетаются вокруг баннера;
--   4) звук достижения (achievement_complete);
--   5) через ~1с — карточка-сводка наград сверху-справа (как выполненный квест)
--      со своим звуком (Level Complete).
--
-- Триггера в игре пока нет: внизу на правом крае добавлена небольшая ТЕСТ-кнопка,
-- по нажатию которой проигрывается вся анимация.
-- Запустить можно и из кода:  _G.PlayIslandClearedEffect()
-- Либо сервер создаёт RemoteEvent "IslandClearedEffect" в ReplicatedStorage и зовёт
-- :FireClient(player) / :FireAllClients() — анимация проиграется у клиента.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--====================================================
-- КОНФИГ
--====================================================

local BANNER_IMAGE  = "rbxassetid://116342589590502"
local BANNER_ASPECT = 1009 / 271   -- пропорции картинки (ширина/высота); Fit подстрахует

-- Звуки ищем по имени где угодно внутри SoundService.
local SOUND_BANNER = "achievement_complete" -- при влёте баннера
local SOUND_CARD   = "Level Complete"       -- при появлении карточки-сводки

-- Текст-оверлей поверх баннера (шаг 5). У присланного ассета текст УЖЕ впечатан в
-- картинку, поэтому по умолчанию ВЫКЛ (иначе текст задвоится). Если баннер без текста
-- (чистая лента) — поставь true, получишь отдельное проявление текста (fade + поворот).
local SHOW_OVERLAY_TEXT = false
local OVERLAY_TEXT      = "ОСТРОВ ЗАЧИЩЕН!"

-- Сводка наград сверху-справа (шаг 7): ТРИ отдельных тоста, появляются вместе.
local CARD_LINES   = {
	"🏴 Пиратский лагерь уничтожен",
	"👥 Освобождено жителей: +5",
	"📍 Доступна телепортация на остров",
}
local CARD_DELAY   = 5.0  -- через сколько после старта показать сводку (не «почти сразу»)
local CARD_DISPLAY = 5.0  -- сколько сводка висит до ухода

-- Сколько баннер держится перед уходом (до появления сводки).
local BANNER_HOLD  = 4.5

-- Тема карточки — как у уведомлений квестов (синяя панель), акцент золотой под баннер.
local COLOR_PANEL      = Color3.fromRGB(10, 25, 55)
local COLOR_PANEL_EDGE = Color3.fromRGB(80, 180, 255)
local COLOR_ACCENT     = Color3.fromRGB(255, 209, 102)
local COLOR_TEXT       = Color3.fromRGB(220, 240, 255)
local FONT_TITLE       = Enum.Font.GothamBold
local FONT_BODY        = Enum.Font.Gotham

--====================================================
-- ЗВУК
--====================================================

local function playSound(name)
	if not name or name == "" then return end
	local s = SoundService:FindFirstChild(name) or SoundService:FindFirstChild(name, true)
	if s and s:IsA("Sound") then
		s.TimePosition = 0
		s:Play()
	else
		warn("[IslandCleared] звук не найден в SoundService: " .. tostring(name))
	end
end

--====================================================
-- GUI (строим один раз; в простое ничего не видно)
--====================================================

local gui = Instance.new("ScreenGui")
gui.Name = "IslandClearedGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

-- 1) затемнение мира
local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Size = UDim2.fromScale(1, 1)
dim.ZIndex = 1
dim.Visible = false
dim.Parent = gui

-- 2) баннер
local banner = Instance.new("ImageLabel")
banner.Name = "Banner"
banner.BackgroundTransparency = 1
banner.Image = BANNER_IMAGE
banner.ScaleType = Enum.ScaleType.Fit
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, -0.2, 0) -- старт над экраном
banner.Size = UDim2.new(0.5, 0, 0, 0)        -- ширина 50% экрана; высота — по AspectRatio
banner.ZIndex = 3
banner.Visible = false
banner.Parent = gui

local bannerAspect = Instance.new("UIAspectRatioConstraint")
bannerAspect.AspectRatio = BANNER_ASPECT
bannerAspect.DominantAxis = Enum.DominantAxis.Width
bannerAspect.Parent = banner

-- Предзагрузка + диагностика: если картинка не загрузилась — почти всегда ID указывает
-- на Decal, а не на Image, либо ассет не одобрен/не принадлежит игре.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	pcall(function() ContentProvider:PreloadAsync({ banner }) end)
	if not banner.IsLoaded then
		warn("[IslandCleared] баннер НЕ загрузился: " .. BANNER_IMAGE ..
			" — проверь, что это ID картинки (Image/Texture), а не Decal, и что ассет одобрен и доступен игре.")
	end
end)

-- UIScale — отдельный «удар» масштаба, не трогая позицию.
local bannerScale = Instance.new("UIScale")
bannerScale.Scale = 0.8
bannerScale.Parent = banner

-- 5) текст-оверлей (по умолчанию выключен — см. SHOW_OVERLAY_TEXT)
local overlay = Instance.new("TextLabel")
overlay.Name = "Title"
overlay.BackgroundTransparency = 1
overlay.AnchorPoint = Vector2.new(0.5, 0.5)
overlay.Position = UDim2.fromScale(0.5, 0.46)
overlay.Size = UDim2.fromScale(0.82, 0.42)
overlay.Font = Enum.Font.FredokaOne
overlay.Text = OVERLAY_TEXT
overlay.TextScaled = true
overlay.TextColor3 = Color3.fromRGB(255, 255, 255)
overlay.TextStrokeColor3 = Color3.fromRGB(120, 60, 10)
overlay.TextStrokeTransparency = 0
overlay.TextTransparency = 1
overlay.Rotation = -5
overlay.ZIndex = 4
overlay.Visible = false
overlay.Parent = banner

-- 7) сводка наград сверху-справа — ТРИ отдельных тоста в стопке. Двигаем общий
-- контейнер, поэтому все три «выезжают» в одно время (как пачка квестов).
local notif = Instance.new("Frame")
notif.Name = "RewardToasts"
notif.AnchorPoint = Vector2.new(1, 0)
notif.Position = UDim2.new(1, 380, 0, 16) -- старт за правым краем
notif.Size = UDim2.new(0, 330, 0, 0)
notif.AutomaticSize = Enum.AutomaticSize.Y
notif.BackgroundTransparency = 1
notif.ZIndex = 10
notif.Visible = false
notif.Parent = gui

local notifList = Instance.new("UIListLayout")
notifList.SortOrder = Enum.SortOrder.LayoutOrder
notifList.Padding = UDim.new(0, 8)
notifList.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifList.Parent = notif

-- Один тост = одна строка-награда (отдельная карточка в стиле уведомлений квестов).
local function buildToast(text, order)
	local panel = Instance.new("Frame")
	panel.Name = "Toast" .. order
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.LayoutOrder = order
	panel.ZIndex = 11
	panel.Parent = notif

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_PANEL_EDGE
	stroke.Thickness = 1.5
	stroke.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft   = UDim.new(0, 12)
	pad.PaddingRight  = UDim.new(0, 12)
	pad.Parent = panel

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.Font = FONT_BODY
	lbl.TextSize = 16
	lbl.TextColor3 = COLOR_TEXT
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	lbl.ZIndex = 12
	lbl.Parent = panel
end

for i, line in ipairs(CARD_LINES) do
	buildToast(line, i)
end

--====================================================
-- ЧАСТИЦЫ (UI-искры вокруг баннера)
--====================================================

local SPARKLE_CHARS = { "✨", "⭐", "💥" }

local function spawnSparkles()
	local cx, cy = 0.5, 0.12 -- около баннера (его центр ~0.1)
	for _ = 1, 14 do
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Text = SPARKLE_CHARS[math.random(1, #SPARKLE_CHARS)]
		s.TextScaled = true
		s.TextColor3 = Color3.fromRGB(255, 210, 90)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(cx, cy)
		s.Size = UDim2.fromOffset(0, 0)
		s.ZIndex = 6
		s.Parent = gui

		local dx = (math.random() - 0.5) * 0.5  -- разлёт по ширине баннера
		local dy = (math.random() - 0.5) * 0.22 -- по высоте
		local sz = math.random(26, 46)
		local dest = UDim2.fromScale(cx + dx, cy + dy)

		TweenService:Create(s, TweenInfo.new(0.12), { Size = UDim2.fromOffset(sz, sz) }):Play()
		local fly = TweenService:Create(
			s,
			TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = dest, TextTransparency = 1, Rotation = math.random(-90, 90) }
		)
		fly:Play()
		fly.Completed:Once(function() s:Destroy() end)
	end
end

--====================================================
-- АНИМАЦИЯ
--====================================================

local playing = false

-- Сводка наград: вся стопка из трёх тостов въезжает справа в одно время, висит,
-- уезжает. По завершении снимает флаг.
local function showToasts()
	notif.Position = UDim2.new(1, 380, 0, 16)
	notif.Visible = true
	TweenService:Create(
		notif,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, -16, 0, 16) }
	):Play()

	task.delay(CARD_DISPLAY, function()
		local out = TweenService:Create(
			notif,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 380, 0, 16) }
		)
		out:Play()
		out.Completed:Once(function()
			notif.Visible = false
			playing = false
		end)
	end)
end

local function playIslandCleared()
	if playing then return end
	playing = true

	-- сброс в стартовое состояние
	dim.BackgroundTransparency = 1
	dim.Visible = true
	banner.Position = UDim2.new(0.5, 0, -0.2, 0)
	bannerScale.Scale = 0.8
	banner.Visible = true
	overlay.Visible = SHOW_OVERLAY_TEXT
	overlay.TextTransparency = 1
	overlay.Rotation = -5

	-- 1) затемнение 1 → 0.7 за 0.2с
	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.7 }):Play()

	-- 2) влёт баннера сверху (Back/Out 0.5с)
	TweenService:Create(
		banner,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.1, 0) }
	):Play()

	-- 3) удар масштаба 0.8 → 1.1 → 1
	local punch = TweenService:Create(
		bannerScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1.1 }
	)
	punch:Play()
	punch.Completed:Once(function()
		TweenService:Create(
			bannerScale,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)

	-- 6) звук достижения (вместе с влётом)
	playSound(SOUND_BANNER)

	-- 4) искры на подлёте баннера
	task.delay(0.18, spawnSparkles)

	-- 5) текст проявляется отдельно через 0.1с (если включён оверлей)
	if SHOW_OVERLAY_TEXT then
		task.delay(0.1, function()
			TweenService:Create(
				overlay,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, Rotation = 0 }
			):Play()
		end)
	end

	-- 7) сводка наград (три тоста в одно время) + её звук (через CARD_DELAY)
	task.delay(CARD_DELAY, function()
		showToasts()
		playSound(SOUND_CARD)
	end)

	-- уход баннера вверх + снятие затемнения
	task.delay(BANNER_HOLD, function()
		TweenService:Create(
			banner,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, -0.25, 0) }
		):Play()
		local fade = TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			dim.Visible = false
			banner.Visible = false
			overlay.Visible = false
		end)
	end)
end

_G.PlayIslandClearedEffect = playIslandCleared

--====================================================
-- ТЕСТ-КНОПКА (по центру правого края) — пока нет реального триггера
--====================================================

local btn = Instance.new("TextButton")
btn.Name = "IslandClearedTestBtn"
btn.AnchorPoint = Vector2.new(1, 0.5)
btn.Position = UDim2.new(1, -10, 0.5, 0)
btn.Size = UDim2.fromOffset(54, 54)
btn.BackgroundColor3 = Color3.fromRGB(245, 175, 40)
btn.AutoButtonColor = true
btn.Text = "🏆"
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.TextColor3 = Color3.fromRGB(40, 25, 0)
btn.ZIndex = 20
btn.Parent = gui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(1, 0)
btnCorner.Parent = btn

local btnStroke = Instance.new("UIStroke")
btnStroke.Color = Color3.fromRGB(120, 80, 0)
btnStroke.Thickness = 2
btnStroke.Parent = btn

btn.MouseButton1Click:Connect(playIslandCleared)

--====================================================
-- НЕОБЯЗАТЕЛЬНЫЙ ХУК ДЛЯ СЕРВЕРА (если появится RemoteEvent)
--====================================================

local function bindRemote(remote)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function()
			playIslandCleared()
		end)
	end
end

bindRemote(ReplicatedStorage:FindFirstChild("IslandClearedEffect"))
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "IslandClearedEffect" then
		bindRemote(child)
	end
end)
