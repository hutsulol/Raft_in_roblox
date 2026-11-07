local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- TeleportLoadingScreen.client.lua (destination side)
-- Lives in ReplicatedFirst of the Ocean place so Roblox runs it
-- before any other client script and we can dismiss the default
-- loading screen + draw our own.
--
-- The Ocean place has StreamingEnabled, which means:
--   * game.Loaded fires once the initial replication chunk is in,
--     not "when the entire map is downloaded" — so it tends to
--     fire much faster than on a non-streaming place.
--   * Workspace continues to stream parts in around the player
--     for several more seconds after Loaded. If we tear down the
--     overlay the moment Loaded fires, the player can land on
--     half-streamed geometry (and sometimes through it before the
--     ocean's collision rolls in).
--
-- So the dismiss waits on three things rather than just Loaded:
--   1. game:IsLoaded()
--   2. LocalPlayer.Character + HumanoidRootPart exist
--   3. workspace:RequestStreamAroundAsync(hrp.Position) returned —
--      the StreamingMinRadius around the player is guaranteed in
--      memory before we drop the curtain.
-- The whole post-load handoff runs as fast as those three resolve:
-- no artificial 5 s fake-progress, no hold, only a 0.2 s fade.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local LOADING_BG_ASSET = "rbxassetid://111898515497348"
--[[ ⚠️ ФОН СНАЧАЛА ЦВЕТОМ, ПОТОМ КАРТИНКОЙ.
     Картинку шторки прогреть нельзя — она первая, до неё в кэше нет ничего.
     Пока она качается, ImageLabel показывает свой BackgroundColor3, и раньше
     это был чистый чёрный: игрок «заходил и ничего не видел». Тот же цвет, что
     у шторки лобби, читается как её продолжение и готов в первом же кадре. ]]
local LOADING_BG_COLOR = Color3.fromHex("0f0a28")

-- ⚠️ ШТАТНЫЙ ЭКРАН СНИМАЕМ НЕ ЗДЕСЬ, А ПОСЛЕ ТОГО, КАК ПОСТРОИЛИ СВОЙ.
-- Раньше он убирался до цикла ожидания LocalPlayer, и если тот не разрешался
-- за пять секунд, скрипт выходил по return — игрок оставался в мире вообще без
-- шторки, глядя на недогруженный плот.

-- ReplicatedFirst LocalScripts can start before LocalPlayer is
-- populated. Spin briefly until it is.
local player = Players.LocalPlayer
local waited = 0
while not player and waited < 5 do
	task.wait(0.05)
	waited += 0.05
	player = Players.LocalPlayer
end
if not player then
	warn("[DestLoadingScreen] LocalPlayer never resolved — aborting custom loader")
	return
end
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	warn("[DestLoadingScreen] PlayerGui не появился за 10с — оставляю штатный экран")
	return
end

-- ── Build the ScreenGui ────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "DestinationLoadingScreen"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 10000   -- выше всех игровых гуёв, включая предупреждения
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = playerGui

-- свой экран готов — теперь можно убирать штатный, без зазора между ними
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local bg = Instance.new("ImageLabel")
bg.Name                  = "Background"
bg.Size                  = UDim2.fromScale(1, 1)
bg.Position              = UDim2.fromScale(0, 0)
bg.BackgroundColor3      = LOADING_BG_COLOR
bg.BackgroundTransparency = 0
bg.Image                 = LOADING_BG_ASSET
bg.ScaleType             = Enum.ScaleType.Crop
--[[ ⚠️ ШТОРКА ЗАБИРАЕТ КАСАНИЯ СЕБЕ.
     Пока она висела полсекунды, клики сквозь неё были неважны. Теперь она ждёт
     контент и может провисеть десяток секунд — а тап сквозь неё попадает в
     штатный джойстик, персонаж «идёт», сервер считает игрока готовым и плот
     трогается, пока человек смотрит в шторку. Active перехватывает ввод. ]]
bg.Active                = true
bg.Parent                = screenGui

local loadingLabel = Instance.new("TextLabel")
loadingLabel.Name                = "LoadingLabel"
loadingLabel.AnchorPoint         = Vector2.new(0.5, 0.5)
loadingLabel.Position            = UDim2.new(0.5, 0, 0.85, 0)
loadingLabel.Size                = UDim2.new(0.5, 0, 0.08, 0)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Text                = "Загрузка"
loadingLabel.TextColor3          = Color3.new(1, 1, 1)
loadingLabel.TextStrokeColor3    = Color3.new(0, 0, 0)
loadingLabel.TextStrokeTransparency = 0.4
loadingLabel.Font                = Enum.Font.GothamBold
loadingLabel.TextScaled          = true
loadingLabel.Parent              = screenGui
do
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 56
	sc.MinTextSize = 24
	sc.Parent      = loadingLabel
end

local barBg = Instance.new("Frame")
barBg.Name             = "BarBg"
barBg.AnchorPoint      = Vector2.new(0.5, 0.5)
barBg.Position         = UDim2.new(0.5, 0, 0.93, 0)
barBg.Size             = UDim2.new(0.5, 0, 0.04, 0)
barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
barBg.BorderSizePixel  = 0
barBg.Parent           = screenGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent       = barBg
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(400, 20)
	sc.MaxSize = Vector2.new(900, 40)
	sc.Parent  = barBg
end

local barFill = Instance.new("Frame")
barFill.Name             = "BarFill"
barFill.AnchorPoint      = Vector2.new(0, 0.5)
barFill.Position         = UDim2.new(0, 0, 0.5, 0)
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(127, 200, 50)
barFill.BorderSizePixel  = 0
barFill.Parent           = barBg
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent       = barFill
end

-- ── Progress bar fake-fill ────────────────────────────────────
-- Run a short linear approach toward 85 % over 2.5 s — enough
-- visual motion to feel alive, short enough that StreamingEnabled
-- builds typically resolve before we'd otherwise overshoot.
--[[ ⚠️ ПОЛОСА ПОКАЗЫВАЕТ РЕАЛЬНУЮ ЗАГРУЗКУ, А НЕ ТАЙМЕР.
     Здесь стоял линейный твин на 2.5 секунды до 85% — «fake-fill», не связанный
     ни с одним счётчиком. Он доезжал до 85% и стоял там сколько угодно, а
     игрок не понимал, идёт ли что-то вообще.
     Теперь доля считается по двум источникам: сколько ассетов прогрето
     (AssetPreload пишет WarmupDone/WarmupTotal) и сколько шагов ожидания
     закрыто. Полоса не отматывается назад: берём максимум из достигнутого,
     иначе на добавлении новой пачки в счётчик она бы дёргалась влево. ]]
local progress = 0
local stepsDone, stepsTotal = 0, 1

local function setProgress(v)
	if v <= progress then return end
	progress = math.clamp(v, 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(progress, 0, 1, 0) }):Play()
end

task.spawn(function()
	while progress < 1 do
		local total = tonumber(ReplicatedFirst:GetAttribute("WarmupTotal")) or 0
		local done  = tonumber(ReplicatedFirst:GetAttribute("WarmupDone")) or 0
		-- половину полосы отдаём ассетам, половину — шагам ожидания
		local assets = (total > 0) and math.min(done / total, 1) or 0
		local steps  = stepsDone / math.max(stepsTotal, 1)
		setProgress(math.min(0.97, assets * 0.5 + steps * 0.5))
		task.wait(0.1)
	end
end)

-- ── Helpers for the StreamingEnabled-aware dismiss ────────────
local function waitForLoaded()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
end

local function waitForCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	-- HumanoidRootPart is replicated separately; on StreamingEnabled
	-- it can arrive a beat after the Model itself.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hrp = char:WaitForChild("HumanoidRootPart", 10)
	end
	return char, hrp
end

local function waitForStreamAround(hrp)
	-- RequestStreamAroundAsync forces the engine to stream the
	-- area around `position` and only returns when the
	-- StreamingMinRadius worth of content is resident. On a
	-- non-StreamingEnabled place this is a no-op that returns
	-- immediately.
	if not hrp then return end
	pcall(function()
		workspace:RequestStreamAroundAsync(hrp.Position)
	end)
end

local function fadeAndDestroy()
	local finishTween = TweenService:Create(
		barFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 1, 0) }
	)
	finishTween:Play()
	finishTween.Completed:Wait()

	local fadeChildren = {}
	for _, desc in screenGui:GetDescendants() do
		if desc:IsA("ImageLabel") or desc:IsA("Frame") then
			table.insert(fadeChildren, { obj = desc, prop = "BackgroundTransparency" })
			if desc:IsA("ImageLabel") then
				table.insert(fadeChildren, { obj = desc, prop = "ImageTransparency" })
			end
		elseif desc:IsA("TextLabel") then
			table.insert(fadeChildren, { obj = desc, prop = "TextTransparency" })
			table.insert(fadeChildren, { obj = desc, prop = "TextStrokeTransparency" })
		end
	end
	local fadeDuration = 0.2
	local fadeStart = os.clock()
	while os.clock() - fadeStart < fadeDuration do
		local t = (os.clock() - fadeStart) / fadeDuration
		for _, e in fadeChildren do
			pcall(function()
				e.obj[e.prop] = math.min(1, t)
			end)
		end
		RunService.RenderStepped:Wait()
	end
	screenGui:Destroy()
end

--[[ ⚠️ СНАЧАЛА ДОКЛАД СЕРВЕРУ, ПОТОМ ЗАНАВЕС.
     Плот стоит на месте, пока все вошедшие не доложат о готовности
     (ServerScriptService/SpawnOnRaft): раньше игрок со слабым каналом
     просыпался в открытой воде — пока он грузился, плот уходил за горизонт.
     Эта точка — самый честный момент доклада: игра загружена, персонаж есть и
     мир вокруг него догружен, то есть человек действительно в игре.
     Ремоут ждём с таймаутом и в отдельном потоке: не нашёлся — просто гасим
     экран, сервер всё равно отпустит плот по своему таймауту. ]]
local function reportReady()
	task.spawn(function()
		local ev = ReplicatedStorage:WaitForChild("RaftBoardingReady", 20)
		if ev and ev:IsA("RemoteEvent") then
			pcall(function() ev:FireServer() end)
		end
	end)
end

--[[ ⚠️ ЖДЁМ ПО-НАСТОЯЩЕМУ, НО НЕ ДОЛЬШЕ HARD_LIMIT.
     Раньше шторка гасла по трём условиям, и ни одно не про контент:
     game.Loaded (доехал первый чанк репликации), персонаж существует и
     RequestStreamAroundAsync (доехали ИНСТАНСЫ вокруг — но не их меши и
     текстуры). Отсюда и выход в мир на прозрачном плоту.
     Теперь к ним добавлены три настоящих: сервер закончил с плотом, прогреты
     иконки, прогрет сам плот. Плюс камера — иначе шторка снимется на кадре, где
     камера ещё летит к персонажу.
     ⚠️ ВСЕ ОЖИДАНИЯ ИДУТ ПАРАЛЛЕЛЬНО, каждое своим потоком со своим сроком:
     выстроенные в цепочку, их таймауты сложились бы в минуту.
     ⚠️ ПОТОЛОК 22 СЕКУНДЫ ВЗЯТ НЕ С ПОТОЛКА. Плот стоит на месте, пока грузятся
     игроки (SpawnOnRaft, BoardingHold), но не дольше MAX_WAIT = 60 с. Шторка
     обязана гаснуть с большим запасом до этого, иначе игрок выйдет в мир, когда
     плот уже уплыл — то есть ровно та беда, от которой удержание и делали. ]]
local HARD_LIMIT = 22    -- жёсткий потолок шторки
local MIN_SHOW   = 1.2   -- чтобы не мигала на быстром клиенте
local startClock = os.clock()

local dismissed = false
local function dismiss(why)
	if dismissed then return end
	dismissed = true
	-- сигнал «шторка уходит»: полка прогрева иконок под ней прячется сразу (ModelIcon)
	ReplicatedFirst:SetAttribute("CurtainLifting", true)
	setProgress(1)
	print(("[DestLoadingScreen] снимаю шторку (%s), прошло %.1fс"):format(why, os.clock() - startClock))
	reportReady()   -- ⚠️ доклад серверу и на аварийной ветке тоже, иначе плот будет ждать зря
	fadeAndDestroy()
end

-- страховка ставится ПЕРВОЙ, до любых ожиданий: что бы ни зависло, шторка уйдёт
task.delay(HARD_LIMIT, function() dismiss("вышло время ожидания") end)

local done = {}
local function step(name, timeout, fn)
	stepsTotal += 1
	task.spawn(function()
		local finished = false
		task.delay(timeout, function()
			if not finished and not done[name] then
				done[name] = true
				stepsDone += 1
				warn(("[DestLoadingScreen] шаг «%s» не уложился в %dс — иду дальше"):format(name, timeout))
			end
		end)
		fn()
		finished = true
		if not done[name] then
			done[name] = true
			stepsDone += 1
		end
	end)
end

local function waitAttr(holder, attr, seconds)
	local deadline = os.clock() + seconds
	while not holder:GetAttribute(attr) and os.clock() < deadline do
		task.wait(0.1)
	end
end

local hrpRef
stepsTotal = 0
step("loaded", 10, waitForLoaded)
step("char", 15, function() local _c, hrp = waitForCharacter(); hrpRef = hrp end)
step("stream", 6, function()
	local dl = os.clock() + 4
	while not hrpRef and os.clock() < dl do task.wait(0.1) end
	waitForStreamAround(hrpRef)
end)
step("плот собран", 12, function() waitAttr(workspace, "RaftReady", 12) end)
step("иконки", 10, function() waitAttr(ReplicatedFirst, "WarmupIconsDone", 10) end)
step("плот прогрет", 14, function() waitAttr(ReplicatedFirst, "WarmupRaftDone", 14) end)
--[[ ⚠️ ЖДЁМ, ПОКА ПЛОТ У ЭТОГО КЛИЕНТА ПОПЛЫВЁТ РОВНО.
     Зонд (RaftMotionProbe) показал: первые ~8–10 с после того, как плот доехал
     до клиента, тот двигается ШАГАМИ — 45 из 60 кадров стоит, с каждым сетевым
     пакетом прыгает на путь за пакет. Скорость при этом реплицируется верно,
     просто клиент ещё не интерполирует чужую физику — начальный стрим мира
     занимает канал. Через ~10 с всё гладко. Раньше плот шёл с нуля и этот
     прогрев проходил под шторкой; с посадочным удержанием он выпадал на глаза
     игрока — «первые секунды плот рывками». Поэтому шторка держится, пока
     плот не пройдёт 50 кадров подряд без остановки (на посадке он ползёт —
     BOARD_CREEP в BoatMovement, так что мерить есть что). ]]
step("плот плывёт ровно", 8, function()
	local RunService = game:GetService("RunService")
	local deadline = os.clock() + 8
	local streak, prev = 0, nil
	while os.clock() < deadline and streak < 40 do
		RunService.RenderStepped:Wait()
		local raft = workspace:FindFirstChild("Raft")
		local pp = raft and raft.PrimaryPart
		if pp then
			local pos = pp.Position
			if prev and pp.AssemblyLinearVelocity.Magnitude > 0.5 then
				if (pos - prev).Magnitude > 0.002 then streak += 1 else streak = 0 end
			end
			prev = pos
		end
	end
	print(("[DestLoadingScreen] плот плывёт ровно: серия %d кадров, ждали %.1fс"):format(streak, os.clock() - (deadline - 8)))
end)
-- камера физически подъехала к персонажу: иначе последний кадр шторки сменится
-- видом воды где-то в стороне, и это читается как «меня выкинуло»
step("камера", 4, function()
	local dl = os.clock() + 3
	while os.clock() < dl do
		local cam = workspace.CurrentCamera
		if cam and hrpRef and (cam.CFrame.Position - hrpRef.Position).Magnitude < 60 then break end
		task.wait(0.1)
	end
end)

task.spawn(function()
	while not dismissed do
		if stepsDone >= stepsTotal and os.clock() - startClock >= MIN_SHOW then
			dismiss("всё готово")
			return
		end
		task.wait(0.1)
	end
end)
