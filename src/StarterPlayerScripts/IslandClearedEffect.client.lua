-- IslandClearedEffect.client.lua
-- Анимация награды «ОСТРОВ ЗАЧИЩЕН!»:
--   1) золотой баннер «впрыгивает» сверху (Back/Out) с эффектом удара (scale-punch);
--   2) искры-частицы разлетаются вокруг баннера; фоном — музыка (Music) с фейдами;
--   3) сводка наград сверху-справа (как выполненный квест) со звуком Level Complete.
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
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--====================================================
-- КОНФИГ
--====================================================

local BANNER_IMAGE  = "rbxassetid://117019798405949"
local BANNER_ASPECT = 1009 / 271   -- пропорции картинки (ширина/высота); Fit подстрахует

-- Звуки ищем по имени где угодно внутри SoundService.
local SOUND_CARD   = "Level Complete"       -- при появлении карточки-сводки

-- Текст-оверлей поверх баннера (шаг 5). У присланного ассета текст УЖЕ впечатан в
-- картинку, поэтому по умолчанию ВЫКЛ (иначе текст задвоится). Если баннер без текста
-- (чистая лента) — поставь true, получишь отдельное проявление текста (fade + поворот).
local SHOW_OVERLAY_TEXT = false
local OVERLAY_TEXT      = "ОСТРОВ ЗАЧИЩЕН!"

-- Уведомления по ходу катсцены показывает НОВЫЙ NotificationCenter (_G.Notify,
-- стиль редизайна: иконобокс + тайтл + боди, цвет по типу). Тут только содержимое.
local NOTIF_DURATION  = 6
local NOTIF_VILLAGERS = { type = "info",    icon = "👥", title = "Жителей: +5",
	body = "Освобождённые жители присоединились к лагерю", duration = NOTIF_DURATION }
local NOTIF_MONOLITH  = { type = "unlock",  icon = "🗿", title = "Древний монолит",
	body = "Открыто новое: Лесорубы", duration = NOTIF_DURATION }
local NOTIF_TELEPORT  = { type = "success", icon = "🎯", title = "Остров исследован!",
	body = "Теперь на остров можно телепортироваться", duration = NOTIF_DURATION }
local ISLAND_REWARD_VILLAGERS = 5 -- сколько жителей реально начислить

-- Сколько баннер держится перед уходом (до появления сводки).
local BANNER_HOLD  = 4.5

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

-- Звуки, которые лежат ДЕТЬМИ этого скрипта (Music, Tree_Farm_Spawn, Storage_Spawn …).
local function sfx(name)
	if not name then return nil end
	local s = script:FindFirstChild(name)
	return (s and s:IsA("Sound")) and s or nil
end

-- Сыграть звук-«ваншот» из детей скрипта (с начала).
local function playSfx(s)
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- Фоновая музыка: плавный заход в начале анимации и плавное затухание в КОНЦЕ
-- анимации (не звука). Родную громкость берём из самого Sound.
local MUSIC_FADE_IN  = 1.0
local MUSIC_FADE_OUT = 1.2
local music = sfx("Music")
local musicTarget = (music and music.Volume > 0) and music.Volume or 0.5

local function startMusic()
	if not music then return end
	music.Looped = true -- на случай, если анимация окажется длиннее трека
	music.Volume = 0
	music.TimePosition = 0
	music:Play()
	TweenService:Create(music, TweenInfo.new(MUSIC_FADE_IN), { Volume = musicTarget }):Play()
end

local function stopMusic()
	if not music then return end
	local fade = TweenService:Create(music, TweenInfo.new(MUSIC_FADE_OUT), { Volume = 0 })
	fade:Play()
	fade.Completed:Once(function()
		if music.Volume <= 0.001 then music:Stop() end -- не глушим, если уже перезапустили
	end)
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

-- баннер
local banner = Instance.new("ImageLabel")
banner.Name = "Banner"
banner.BackgroundTransparency = 1
banner.Image = BANNER_IMAGE
banner.ScaleType = Enum.ScaleType.Fit
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, -0.2, 0) -- старт над экраном
banner.Size = UDim2.fromScale(0.55, 0.22)    -- рамка; ScaleType.Fit впишет картинку без искажений
banner.ZIndex = 3
banner.Visible = false
banner.Parent = gui

-- Запасная лента: если картинка не загрузилась (неверный ID/Decal/модерация/нет доступа),
-- показываем стилизованную золотую ленту с текстом — анимация всё равно выглядит как надо.
local fallback = Instance.new("Frame")
fallback.Name = "Fallback"
fallback.Size = UDim2.fromScale(1, 1)
fallback.BackgroundColor3 = Color3.fromRGB(245, 176, 38)
fallback.BorderSizePixel = 0
fallback.Visible = false
fallback.ZIndex = 2
fallback.Parent = banner

local fbCorner = Instance.new("UICorner")
fbCorner.CornerRadius = UDim.new(0, 16)
fbCorner.Parent = fallback

local fbGrad = Instance.new("UIGradient")
fbGrad.Color = ColorSequence.new(Color3.fromRGB(255, 214, 92), Color3.fromRGB(231, 150, 28))
fbGrad.Rotation = 90
fbGrad.Parent = fallback

local fbStroke = Instance.new("UIStroke")
fbStroke.Color = Color3.fromRGB(120, 70, 10)
fbStroke.Thickness = 3
fbStroke.Parent = fallback

local fbText = Instance.new("TextLabel")
fbText.Name = "Text"
fbText.BackgroundTransparency = 1
fbText.AnchorPoint = Vector2.new(0.5, 0.5)
fbText.Position = UDim2.fromScale(0.5, 0.5)
fbText.Size = UDim2.fromScale(0.9, 0.55)
fbText.Font = Enum.Font.FredokaOne
fbText.Text = OVERLAY_TEXT
fbText.TextScaled = true
fbText.TextColor3 = Color3.fromRGB(255, 255, 255)
fbText.TextStrokeColor3 = Color3.fromRGB(120, 60, 10)
fbText.TextStrokeTransparency = 0
fbText.ZIndex = 3
fbText.Parent = fallback

-- Грузим картинку и СУДИМ ПО СТАТУСУ загрузки (Enum.AssetFetchStatus), а НЕ по
-- banner.IsLoaded: у ещё не отрисованного (Visible=false) ImageLabel IsLoaded может
-- быть false даже когда ассет успешно скачан. Success ⇒ картинка валидна — прячем
-- запасную; иначе показываем запасную ленту.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local status = Enum.AssetFetchStatus.None
	pcall(function()
		ContentProvider:PreloadAsync({ banner }, function(_, st)
			status = st
		end)
	end)
	if status == Enum.AssetFetchStatus.Success then
		fallback.Visible = false
		print("[IslandCleared] баннер OK: " .. BANNER_IMAGE)
	else
		fallback.Visible = true
		warn("[IslandCleared] баннер не загрузился, статус=" .. tostring(status) .. ": " .. BANNER_IMAGE ..
			" — Failure ⇒ неверный тип ID (Decal вместо Image)/приватный/модерация; TimedOut ⇒ слишком " ..
			"долго грузится. Показываю запасную ленту.")
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

-- Уведомления показывает НОВЫЙ NotificationCenter (карточки редизайна). Тут — тонкая
-- обёртка: звук + _G.Notify (ждём его, если NotificationCenter ещё не загрузился).
local function notify(opts)
	playSound(SOUND_CARD) -- чим уведомления (Level Complete из SoundService)
	task.spawn(function()
		local t0 = os.clock()
		while not _G.Notify and os.clock() - t0 < 5 do
			task.wait(0.1)
		end
		if _G.Notify then
			_G.Notify(opts)
		else
			warn("[IslandCleared] _G.Notify не найден — NotificationCenter.client.lua не загрузился")
		end
	end)
end

-- Реальное начисление жителей: валюта серверная, поэтому просим сервер (RemoteEvent
-- IslandClearedReward — его создаёт VillagersCurrency.server.lua). Раз за прогон.
local rewardRemote = ReplicatedStorage:WaitForChild("IslandClearedReward", 5)
local rewardGranted = false
local function grantVillagers()
	if rewardGranted then return end
	rewardGranted = true
	if rewardRemote then
		rewardRemote:FireServer()
	else
		warn("[IslandCleared] RemoteEvent 'IslandClearedReward' не найден — жители не начислятся")
	end
end

-- Готовые уведомления по событиям катсцены.
local function notifyVillagers() notify(NOTIF_VILLAGERS); grantVillagers() end
local function notifyMonolith() notify(NOTIF_MONOLITH) end
local function notifyTeleport() notify(NOTIF_TELEPORT) end

--====================================================
-- ЧАСТИЦЫ (UI-искры вокруг баннера)
--====================================================

local SPARKLE_COLOR = Color3.fromRGB(255, 222, 120)  -- золото под баннер

-- Одна искра: «вспыхивает» и гаснет (твинкл) в случайной точке ПО ВСЕЙ площади
-- баннера, ЗА ним (ZIndex 2 < баннер 3). Рисуем ФРЕЙМАМИ (крестик из двух полосок) —
-- никаких шрифтовых глифов: часть символов шрифт не поддерживал (рисовал прямоугольники).
local function spawnOneSparkle()
	local s = Instance.new("Frame")
	s.BackgroundTransparency = 1
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	-- распределяем по всей площади баннера (чуть шире его рамки), центр баннера ~ (0.5, 0.1)
	s.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.66, 0.10 + (math.random() - 0.5) * 0.30)
	s.Size = UDim2.fromOffset(0, 0)
	s.Rotation = math.random(0, 90)
	s.ZIndex = 2
	s.Parent = gui

	-- две скруглённые полоски крест-накрест = четырёхлучевая искра
	local bars = {}
	for _, barSize in ipairs({ UDim2.fromScale(0.24, 1), UDim2.fromScale(1, 0.24) }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = barSize
		bar.BackgroundColor3 = SPARKLE_COLOR
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel = 0
		bar.ZIndex = 2
		bar.Parent = s
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
		table.insert(bars, bar)
	end

	local sz = math.random(14, 32)
	-- вспышка: быстро проявиться с ростом…
	TweenService:Create(s,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(sz, sz) }):Play()
	for _, bar in ipairs(bars) do
		TweenService:Create(bar, TweenInfo.new(0.16), { BackgroundTransparency = 0 }):Play()
	end
	-- …затем мягко погаснуть, слегка разрастаясь (как затухающая искра)
	task.delay(0.18, function()
		TweenService:Create(s,
			TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.fromOffset(sz * 1.5, sz * 1.5), Rotation = s.Rotation + math.random(-40, 40) }):Play()
		for _, bar in ipairs(bars) do
			TweenService:Create(bar, TweenInfo.new(0.42), { BackgroundTransparency = 1 }):Play()
		end
		task.delay(0.45, function() s:Destroy() end)
	end)
end

-- Искры идут ВОЛНАМИ, пока виден баннер (а не один залп в центре).
local function runSparkles(duration)
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		for _ = 1, math.random(2, 4) do
			spawnOneSparkle()
		end
		task.wait(math.random(9, 16) / 100)
	end
end

--====================================================
-- АНИМАЦИЯ
--====================================================

local playing = false

local function playIslandCleared()
	if playing then return end
	playing = true

	-- сброс в стартовое состояние
	banner.Position = UDim2.new(0.5, 0, -0.2, 0)
	bannerScale.Scale = 0.8
	banner.Visible = true
	overlay.Visible = SHOW_OVERLAY_TEXT
	overlay.TextTransparency = 1
	overlay.Rotation = -5

	-- 1) влёт баннера сверху (Back/Out 0.5с)
	TweenService:Create(
		banner,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.1, 0) }
	):Play()

	-- 2) удар масштаба 0.8 → 1.1 → 1
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

	-- 3) искры волнами по всей площади баннера, пока он виден
	task.spawn(function()
		task.wait(0.12)
		runSparkles(BANNER_HOLD - 0.3)
	end)

	-- 4) текст проявляется отдельно через 0.1с (если включён оверлей)
	if SHOW_OVERLAY_TEXT then
		task.delay(0.1, function()
			TweenService:Create(
				overlay,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, Rotation = 0 }
			):Play()
		end)
	end

	-- (уведомления-награды теперь показывает катсцена по кадрам, см. playCutscene)

	-- уход баннера вверх
	task.delay(BANNER_HOLD, function()
		local up = TweenService:Create(
			banner,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, -0.25, 0) }
		)
		up:Play()
		up.Completed:Once(function()
			banner.Visible = false
			overlay.Visible = false
		end)
	end)
end

--====================================================
-- КАТСЦЕНА (камера по ЯКОРНЫМ партам острова — острова спавнятся в разных местах)
--====================================================
-- Кадр N: камера встаёт в Camera_N_Frame и смотрит на Camera_look_N_Frame. Если есть
-- Camera_N_N_Frame — за время выдержки камера ПЛАВНО ДРЕЙФУЕТ из Camera_N_Frame в
-- Camera_N_N_Frame (взгляд остаётся на look-точке), чтобы кадр не стоял на месте;
-- без него кадр статичный. Папку CutScene берём БЛИЖАЙШУЮ к игроку (на нужном
-- острове). Тайминги: держим кадры CUTSCENE_HOLDS, между кадрами — резкий Circular.
local CUTSCENE_FOLDER     = "CutScene"
local CUTSCENE_COUNT      = 3
local CUTSCENE_HOLDS      = { 5, 4, 3 }            -- сек на кадрах 1 / 2 / 3
local CUTSCENE_TRANSITION = 1.0                    -- длительность перехода (резкий)
local CUTSCENE_STYLE      = Enum.EasingStyle.Circular
local CUTSCENE_DRIFT_STYLE = Enum.EasingStyle.Linear -- дрейф внутри кадра (равномерный)

-- «Вырастающие» в катсцене постройки: кадр → имя модели. Когда камера приходит в
-- кадр, через GROW_DELAY модель растёт с ~0 до СВОЕГО родного Scale (читаем через
-- GetScale — никакого хардкода, работает на любом острове) за GROW_PORTION времени
-- выдержки. Прячутся (масштаб ~0) в момент старта катсцены.
local GROW_MODELS  = { [2] = "Tree_Farm", [3] = "Storage_Palm" }
local GROW_SOUNDS  = { [2] = "Tree_Farm_Spawn", [3] = "Storage_Spawn" } -- звук в момент роста
local GROW_DELAY   = 0.2  -- старт роста после прихода камеры в кадр
local GROW_PORTION = 0.5  -- доля выдержки кадра на рост (половина)
local GROW_STYLE   = Enum.EasingStyle.Back -- в конце чуть перерастает и «садится»

-- «Освобождённые жители»: в 1-м кадре появляются в палатке (каждый на своём
-- спавн-парте), сразу идут к парту Walk_Trigger и там растворяются — эффект
-- «игрок освободил людей». Модели — в ReplicatedStorage; клоны клиентские
-- (чистая кинематографика, на сервер не влияют).
local FREED_VILLAGERS = {
	{ model = "Villager",       spawn = "Men_Spawn"   },
	{ model = "Kid",            spawn = "Kid_Spawn"   },
	{ model = "Women_Villager", spawn = "Women_Spawn" },
}
local FREED_TRIGGER    = "Walk_Trigger"
local FREED_WALK_ANIM  = "rbxassetid://97110432876752" -- общая ходьба (в моделях своей нет)
local FREED_WALK_SPEED = 8    -- скорость хода жителей
local FREED_REACH      = 3    -- на сколько близко к триггеру = «дошёл»
local FREED_FADE_TIME  = 0.6  -- растворение по достижении триггера
local FREED_TIMEOUT    = 20   -- страховка, если житель застрял

-- Флаг лагеря: на FLAG_DELAY-й секунде 1-го кадра парт Color в модели Flag плавно
-- перекрашивается из чёрного в Navy blue — «лагерь сменил владельца».
local FLAG_MODEL = "Flag"
local FLAG_PART  = "Color"
local FLAG_DELAY = 2    -- секунда 1-го кадра
local FLAG_TIME  = 1.2  -- длительность перехода цвета
local FLAG_COLOR = BrickColor.new("Navy blue").Color

local function framePos(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok then return cf.Position end
	end
	return nil
end

-- Ближайшая к игроку папка CutScene (с Camera_1_Frame).
local function findCutscene()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = (hrp and hrp.Position) or Vector3.zero
	local best, bestD
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == CUTSCENE_FOLDER and (d:IsA("Folder") or d:IsA("Model"))
			and d:FindFirstChild("Camera_1_Frame") then
			local p = framePos(d:FindFirstChild("Camera_1_Frame"))
			if p then
				local dist = (p - origin).Magnitude
				if not bestD or dist < bestD then best, bestD = d, dist end
			end
		end
	end
	return best
end

-- Ближайшая к origin модель с именем name (постройки нужного острова).
local function findNearestModel(name, origin)
	local best, bestD
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == name then
			local ok, cf = pcall(function() return d:GetPivot() end)
			if ok then
				local dist = (cf.Position - origin).Magnitude
				if not bestD or dist < bestD then best, bestD = d, dist end
			end
		end
	end
	return best
end

-- Ближайший к origin ПАРТ с именем name (спавн-точки жителей, Walk_Trigger).
local function findNearestPart(name, origin)
	local best, bestD
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name then
			local dist = (d.Position - origin).Magnitude
			if not bestD or dist < bestD then best, bestD = d, dist end
		end
	end
	return best
end

-- Один освобождённый житель: клон → на спавн-парт → идёт к триггеру → растворяется.
-- Клон клиентский: Animate-скрипты внутри не работают, поэтому ходьбу играем сами
-- (общая анимация FREED_WALK_ANIM).
local function runFreedVillager(template, spawnPart, trigger)
	-- Archivable=false — классическая причина «модель не спавнится»: Clone() тихо
	-- возвращает nil. Чиним сами и говорим об этом.
	if not template.Archivable then
		template.Archivable = true
		warn("[IslandCleared] жители: у '" .. template.Name .. "' был Archivable=false — включил")
	end
	local npc = template:Clone()
	if not npc then
		warn("[IslandCleared] жители: Clone() не удался для '" .. template.Name .. "'")
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local hrp = (humanoid and humanoid.RootPart)
		or npc:FindFirstChild("HumanoidRootPart", true)
		or npc.PrimaryPart
		or npc:FindFirstChildWhichIsA("BasePart", true)
	if not (humanoid and hrp) then
		warn("[IslandCleared] жители: у модели '" .. template.Name .. "' нет " ..
			(humanoid and "корневого парта" or "Humanoid") .. " — пропускаю")
		npc:Destroy()
		return
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	pcall(function() humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)

	local target = trigger.Position
	npc:PivotTo(CFrame.lookAt(
		spawnPart.Position + Vector3.new(0, 3, 0),
		Vector3.new(target.X, spawnPart.Position.Y + 3, target.Z)
	))
	npc.Parent = workspace

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = FREED_WALK_ANIM
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Looped = true
		track:Play()
	end

	humanoid.WalkSpeed = FREED_WALK_SPEED
	local t0 = os.clock()
	while npc.Parent and humanoid.Health > 0 do
		local flat = Vector3.new(hrp.Position.X - target.X, 0, hrp.Position.Z - target.Z)
		if flat.Magnitude <= FREED_REACH then break end
		if os.clock() - t0 > FREED_TIMEOUT then break end
		humanoid:MoveTo(target)
		task.wait(0.2)
	end

	-- дошёл до триггера — растворяется (камера к этому моменту уже на другом кадре)
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			TweenService:Create(d, TweenInfo.new(FREED_FADE_TIME), { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	task.wait(FREED_FADE_TIME + 0.1)
	npc:Destroy()
end

-- Шаблон жителя в ReplicatedStorage: ищем именно MODEL с таким именем (на случай
-- тёзок другого типа, из-за которых FindFirstChild находил «не то»).
local function findTemplateModel(name)
	local direct = ReplicatedStorage:FindFirstChild(name)
	if direct and direct:IsA("Model") then return direct end
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("Model") and d.Name == name then return d end
	end
	return nil
end

-- Спавн всех освобождённых жителей (зовём при приходе камеры в кадр 1).
local function spawnFreedVillagers(origin)
	local trigger = findNearestPart(FREED_TRIGGER, origin)
	if not trigger then
		warn("[IslandCleared] жители: не нашёл парт '" .. FREED_TRIGGER .. "'")
		return
	end
	for _, info in ipairs(FREED_VILLAGERS) do
		local template = findTemplateModel(info.model)
		local spawnPart = findNearestPart(info.spawn, origin)
		if template and spawnPart then
			task.spawn(runFreedVillager, template, spawnPart, trigger)
		else
			warn(string.format("[IslandCleared] жители: %s — модель %s, спавн '%s' %s",
				info.model, template and "OK" or "НЕТ (Model) в ReplicatedStorage",
				info.spawn, spawnPart and "OK" or "НЕ найден"))
		end
	end
end

-- Плавная перекраска флага лагеря (парт Color в модели Flag) в цвет нового владельца.
local function recolorFlag(origin)
	local flag = findNearestModel(FLAG_MODEL, origin)
	local part = flag and findNearestPart(FLAG_PART, origin)
	-- предпочитаем парт ИМЕННО внутри модели Flag
	if flag then
		local inFlag = flag:FindFirstChild(FLAG_PART, true)
		if inFlag and inFlag:IsA("BasePart") then part = inFlag end
	end
	if not (part and part:IsA("BasePart")) then
		warn("[IslandCleared] флаг: не нашёл парт '" .. FLAG_PART .. "' (модель '" .. FLAG_MODEL .. "')")
		return
	end
	TweenService:Create(part,
		TweenInfo.new(FLAG_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Color = FLAG_COLOR }):Play()
end

-- Рост модели с ~0 до target за seconds. Model.Scale нельзя твинить — каждый кадр
-- зовём ScaleTo с easing-прогрессом (GROW_STYLE). onDone — по завершении.
local function growModel(model, target, seconds, onDone)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then conn:Disconnect() return end
		local a = math.min((os.clock() - t0) / seconds, 1)
		local eased = TweenService:GetValue(a, GROW_STYLE, Enum.EasingDirection.Out)
		model:ScaleTo(math.max(target * eased, 0.001))
		if a >= 1 then
			conn:Disconnect()
			model:ScaleTo(target)
			if onDone then onDone() end
		end
	end)
end

--====================================================
-- СКРЫТИЕ ПОСТРОЕК ДО КАТСЦЕНЫ
--====================================================
-- Постройки из GROW_MODELS спрятаны С САМОГО СТАРТА (масштаб ~0, промпты выключены) —
-- на острове их «нет», пока катсцена не вырастит. Реестр хранит родной Scale; после
-- роста revealBuilding включает функционал (промпт «Открыть» и т.п.).
local hiddenBuildings = {} -- [model] = { scale = родной Scale, conn = ... }

local function hideBuilding(m)
	if hiddenBuildings[m] then return end
	-- вложенные тёзки (Model внутри Model с тем же именем): прячем только ВНЕШНЮЮ,
	-- иначе двойной ScaleTo даст неверный масштаб после роста
	for hidden in pairs(hiddenBuildings) do
		if m:IsDescendantOf(hidden) then return end
	end
	local entry = { scale = m:GetScale() }
	-- промпт склада сервер добавляет позже — выключаем и те, что появятся
	entry.conn = m.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end
	hiddenBuildings[m] = entry
	m:ScaleTo(0.001)
end

local function revealBuilding(m)
	local e = hiddenBuildings[m]
	if not e then return end
	hiddenBuildings[m] = nil
	if e.conn then e.conn:Disconnect() end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("ProximityPrompt") then d.Enabled = true end
	end
end

-- Прячем все существующие и появляющиеся позже (новые острова). Небольшая задержка —
-- чтобы модель успела дореплицироваться целиком до масштабирования.
do
	local names = {}
	for _, n in pairs(GROW_MODELS) do names[n] = true end
	local function tryHide(d)
		if d:IsA("Model") and names[d.Name] then
			task.delay(0.3, function()
				if d.Parent then hideBuilding(d) end
			end)
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		tryHide(d)
	end
	workspace.DescendantAdded:Connect(tryHide)
end

-- Кадр idx: start = из Camera_idx_Frame, finish = из Camera_idx_idx_Frame (если есть);
-- обе точки смотрят на Camera_look_idx_Frame.
local function shotFrames(cs, idx)
	local pos  = framePos(cs:FindFirstChild("Camera_" .. idx .. "_Frame"))
	local look = framePos(cs:FindFirstChild("Camera_look_" .. idx .. "_Frame"))
	if not (pos and look) then return nil end
	local function cfAt(p)
		if (look - p).Magnitude < 1e-3 then return CFrame.new(p) end
		return CFrame.lookAt(p, look)
	end
	local driftPos = framePos(cs:FindFirstChild("Camera_" .. idx .. "_" .. idx .. "_Frame"))
	return { start = cfAt(pos), finish = driftPos and cfAt(driftPos) or nil }
end

-- Выдержка кадра: с конечной точкой — равномерный дрейф к ней на всё время выдержки
-- («живой» кадр), без неё — статичная пауза.
local function holdShot(cam, shot, seconds)
	if shot.finish then
		local drift = TweenService:Create(
			cam,
			TweenInfo.new(seconds, CUTSCENE_DRIFT_STYLE, Enum.EasingDirection.Out),
			{ CFrame = shot.finish }
		)
		drift:Play()
		drift.Completed:Wait()
	else
		task.wait(seconds)
	end
end

local cutscenePlaying = false

local function playCutscene(onComplete)
	if cutscenePlaying then return false end
	local cs = findCutscene()
	if not cs then
		warn("[IslandCleared] катсцена: не найдена папка '" .. CUTSCENE_FOLDER ..
			"' с Camera_1.." .. CUTSCENE_COUNT .. "_Frame на острове")
		return false
	end
	local frames = {}
	for i = 1, CUTSCENE_COUNT do
		local shot = shotFrames(cs, i)
		if not shot then
			warn("[IslandCleared] катсцена: нет Camera_" .. i .. "_Frame или Camera_look_" .. i .. "_Frame")
			return false
		end
		frames[i] = shot
	end

	-- «Вырастающие» постройки: ближайшие к острову катсцены. Они уже спрятаны со
	-- старта (реестр хранит родной Scale) — каждая вырастет в своём кадре.
	local origin = framePos(cs:FindFirstChild("Camera_1_Frame")) or Vector3.zero
	local grows = {}
	for shotIdx, modelName in pairs(GROW_MODELS) do
		local m = findNearestModel(modelName, origin)
		if m then
			hideBuilding(m) -- no-op, если уже спрятана; иначе спрячет и запомнит Scale
			grows[shotIdx] = { model = m, scale = hiddenBuildings[m].scale, sound = sfx(GROW_SOUNDS[shotIdx]) }
		else
			warn("[IslandCleared] катсцена: не нашёл модель '" .. modelName .. "' для кадра " .. shotIdx)
		end
	end

	cutscenePlaying = true
	task.spawn(function()
		local cam = workspace.CurrentCamera
		-- Запоминаем вид игрока ДО катсцены: и сам CFrame, и его смещение относительно
		-- персонажа — если игрок за катсцену сдвинулся, вернёмся к тому же ракурсу
		-- у его НОВОЙ позиции (без скачка при переключении на Custom).
		local startCF = cam.CFrame
		local hrp0 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local relCF = hrp0 and hrp0.CFrame:ToObjectSpace(startCF) or nil

		-- забираем управление камерой (повтор — на случай, если другой скрипт перебивает)
		repeat
			cam.CameraType = Enum.CameraType.Scriptable
			task.wait()
		until cam.CameraType == Enum.CameraType.Scriptable

		-- перенос: камера игрока → кадр 1
		cam.CFrame = startCF
		local twIn = TweenService:Create(
			cam,
			TweenInfo.new(CUTSCENE_TRANSITION, CUTSCENE_STYLE, Enum.EasingDirection.Out),
			{ CFrame = frames[1].start }
		)
		-- Рост постройки кадра i: через GROW_DELAY после прихода камеры, длится
		-- половину выдержки (идёт параллельно дрейфу камеры).
		local function startGrow(i)
			local g = grows[i]
			if not g then return end
			task.delay(GROW_DELAY, function()
				playSfx(g.sound) -- звук появления — синхронно с началом роста модели
				growModel(g.model, g.scale, (CUTSCENE_HOLDS[i] or 3) * GROW_PORTION, function()
					revealBuilding(g.model) -- рост закончен — включаем функционал (промпты)
				end)
			end)
		end

		twIn:Play()
		twIn.Completed:Wait()
		spawnFreedVillagers(origin) -- освобождённые жители выходят из палатки (кадр 1)
		task.delay(FLAG_DELAY, recolorFlag, origin) -- флаг: чёрный → Navy blue (2-я сек)
		notifyVillagers()                  -- кадр 1: «+5 жителей» (и реально начисляем)
		startGrow(1)
		holdShot(cam, frames[1], CUTSCENE_HOLDS[1] or 5)

		for i = 2, CUTSCENE_COUNT do           -- резкий переход → выдержка с дрейфом
			local tw = TweenService:Create(
				cam,
				TweenInfo.new(CUTSCENE_TRANSITION, CUTSCENE_STYLE, Enum.EasingDirection.Out),
				{ CFrame = frames[i].start }
			)
			tw:Play()
			tw.Completed:Wait()
			if i == 2 then notifyMonolith() end -- кадр 2: «Древний монолит / Лесорубы»
			startGrow(i)
			holdShot(cam, frames[i], CUTSCENE_HOLDS[i] or 3)
		end

		-- возврат: последний кадр → камера игрока (по текущему положению персонажа)
		local hrp1 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local backCF = (hrp1 and relCF) and (hrp1.CFrame * relCF) or startCF
		local twOut = TweenService:Create(
			cam,
			TweenInfo.new(CUTSCENE_TRANSITION, CUTSCENE_STYLE, Enum.EasingDirection.Out),
			{ CFrame = backCF }
		)
		twOut:Play()
		twOut.Completed:Wait()

		-- подстраховка: все «вырастающие» модели точно в родном масштабе и работают
		for _, g in pairs(grows) do
			if g.model.Parent then g.model:ScaleTo(g.scale) end
			revealBuilding(g.model)
		end

		cam.CameraType = Enum.CameraType.Custom -- конец — управление игроку
		notifyTeleport()                        -- конец анимации: «доступна телепортация»
		cutscenePlaying = false
		if onComplete then onComplete() end
	end)
	return true
end

-- Полный запуск по кнопке/ремоуту: музыка + анимация награды + катсцена. Музыка
-- затухает в КОНЦЕ анимации (конец катсцены; если её нет — после баннера/тостов).
local MUSIC_TAIL = 11.5
local effectRunning = false
local function playAll()
	if effectRunning then return end
	effectRunning = true
	rewardGranted = false -- разрешить начисление в этом прогоне
	startMusic()
	playIslandCleared()
	local started = playCutscene(function()
		stopMusic()
		effectRunning = false
	end)
	if not started then
		-- катсцены нет — показываем уведомления по таймеру (тосты обычно ведёт катсцена)
		task.delay(1, notifyVillagers)
		task.delay(5, notifyMonolith)
		task.delay(9, notifyTeleport)
		task.delay(MUSIC_TAIL, function()
			stopMusic()
			effectRunning = false
		end)
	end
end

_G.PlayIslandClearedEffect = playAll
_G.PlayIslandClearedCutscene = playCutscene

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

btn.MouseButton1Click:Connect(playAll)

--====================================================
-- НЕОБЯЗАТЕЛЬНЫЙ ХУК ДЛЯ СЕРВЕРА (если появится RemoteEvent)
--====================================================

local function bindRemote(remote)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function()
			playAll()
		end)
	end
end

bindRemote(ReplicatedStorage:FindFirstChild("IslandClearedEffect"))
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "IslandClearedEffect" then
		bindRemote(child)
	end
end)
