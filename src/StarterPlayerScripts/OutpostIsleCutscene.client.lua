local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	КАТСЦЕНА ПОЯВЛЕНИЯ ОСТРОВА-АВАНПОСТА + ФОНОВАЯ МУЗЫКА СЦЕНЫ.

	Сервер (OutpostIsleStory.server.lua) поднимает остров на третий день и шлёт
	сюда его координату. Камера уходит к острову, сужается угол обзора, потом всё
	возвращается на место, игрок думает вслух — и с этой же секунды тихо
	начинает играть музыка. Гаснет она, когда остров зачищен.

	⚠️ СДЕЛАНО ПО ОБРАЗЦУ СТАРТОВОГО ОСТРОВА, И ЭТО НЕ ЛЕНЬ.
	Тамошний playCutscene — файловая локальная функция, наружу не отдана; общего
	у двух сцен ровно три вещи (плавный вход, ручной прогон CFrame по кадрам,
	аккуратный возврат камеры), и они повторены здесь сознательно, вместе с уже
	собранными там граблями — см. giveCameraBack.

	⚠️ ИГРОКА НЕ ЗАМОРАЖИВАЕМ. Ни туман, ни обе островные сцены не отбирают
	управление: катсцена с отобранными ногами читается как зависание игры.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local BLEND_IN     = 0.7    -- вход в сцену
local SHOT_TIME    = 7.0    -- сам пролёт; чуть длиннее стартового: остров крупнее
local BLEND_OUT    = 0.9    -- возврат к игроку
local TRAVEL       = 260    -- на сколько студов камера уходит к острову
local LIFT_FROM    = 7
local LIFT_TO      = 34
local FOV_FROM     = 70     -- штатный угол
local FOV_TO       = 40     -- «приближаем» остров: иначе это точка на горизонте
local THOUGHT_WAIT = 2.5    -- через сколько после возврата камеры игрок думает вслух

--[[ ⚠️ ID МУЗЫКИ ВСТАВЛЯЕТСЯ СЮДА РУКАМИ.
     Пустая строка = музыки нет, и это не поломка: у сцены тумана точно так же
     пустые MYSTERY_SOUND_ID и THUNDER_SOUND_ID. Свой трек нельзя ни сочинить,
     ни угадать — чужой id дал бы ту же тишину, только молча. Вставишь свой —
     заиграет само, править больше нечего.
     Громкость намеренно низкая: по сценарию музыка идёт ФОНОМ, под мысль
     игрока, а не поверх неё. ]]
local MUSIC_ID     = ""
local MUSIC_VOLUME = 0.18
local MUSIC_FADE   = 4      -- секунд на разгорание и на затухание

local player = Players.LocalPlayer
local sceneEvent = ReplicatedStorage:WaitForChild("OutpostIsleEvent")

-- Один раз за сессию: остров появляется однажды, а повторный вызов посреди
-- первого дрался бы с ним за камеру.
local played = false
local music = nil

-- Нижняя строка, как «Туман поднимается…»: держится, пока идёт пролёт.
local function toast(text)
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "OutpostIsleToastGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = pg

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.72)
	lbl.Size = UDim2.fromOffset(720, 50)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextSize = 32
	lbl.TextColor3 = Color3.fromRGB(236, 240, 226)
	lbl.TextStrokeColor3 = Color3.fromRGB(15, 22, 30)
	lbl.TextStrokeTransparency = 1
	lbl.TextTransparency = 1
	lbl.Parent = gui

	TweenService:Create(lbl, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.35 }):Play()
	task.delay(SHOT_TIME - 0.5, function()
		TweenService:Create(lbl, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(1.3)
		gui:Destroy()
	end)
end

-- ── музыка сцены ──
-- ⚠️ ЗВУК ЖИВЁТ В SoundService, А НЕ НА ПЕРСОНАЖЕ.
-- На персонаже он умирает вместе с ним при первой же смерти — а музыка должна
-- идти всю сцену, включая респавн. SoundService переживает и смерть, и смену
-- персонажа, и это ровно то место, где положено лежать нелокальному звуку.
local function startMusic()
	if MUSIC_ID == "" then
		print("[Аванпост] музыка сцены не задана (MUSIC_ID пуст) — играем без неё")
		return
	end
	if music then return end
	music = Instance.new("Sound")
	music.Name = "OutpostIsleTheme"
	music.SoundId = MUSIC_ID
	music.Looped = true
	music.Volume = 0
	music.Parent = SoundService
	music:Play()
	TweenService:Create(music, TweenInfo.new(MUSIC_FADE), { Volume = MUSIC_VOLUME }):Play()
end

local function stopMusic()
	if not music then return end
	local s = music
	music = nil
	local fade = TweenService:Create(s, TweenInfo.new(MUSIC_FADE), { Volume = 0 })
	fade:Play()
	fade.Completed:Once(function()
		s:Stop()
		s:Destroy()
	end)
end

-- ⚠️ ВОЗВРАЩАЕМ И УГОЛ ОБЗОРА, А НЕ ТОЛЬКО ТИП КАМЕРЫ.
-- FieldOfView живёт на камере и переживает возврат в Custom: забудь его тут — и
-- игрок доиграет сессию в «прицеле», не понимая, почему мир стал ближе.
-- Про CameraSubject: если игрок умер посреди сцены, одного CameraType мало —
-- subject остаётся у уничтоженного Humanoid, и камера залипает на месте смерти.
local function giveCameraBack()
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = FOV_FROM
	end
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		local cam2 = Workspace.CurrentCamera
		if hum and cam2 then cam2.CameraSubject = hum end
	end)
end

local function playCutscene(islandPos)
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and hrp and islandPos) then return end

	-- направление на остров по горизонтали: подъём камеры задаём сами
	local toIsle = Vector3.new(islandPos.X - hrp.Position.X, 0, islandPos.Z - hrp.Position.Z)
	local look = (toIsle.Magnitude > 1) and toIsle.Unit or Vector3.new(0, 0, -1)
	local side = Vector3.new(-look.Z, 0, look.X)

	-- Куда возвращаться: запоминаем камеру ОТНОСИТЕЛЬНО игрока, а не в мире —
	-- плот всё это время плывёт, и абсолютная точка за семь секунд уезжает.
	local relReturn = hrp.CFrame:ToObjectSpace(cam.CFrame)
	local function playerCamCF() return hrp.CFrame * relReturn end

	local function sceneCF(e)
		local p = hrp.Position
		local travel  = -10 + TRAVEL * e
		local lateral = (e * 2 - 1) * 8
		local lift    = LIFT_FROM + (LIFT_TO - LIFT_FROM) * e
		local camPos  = p + Vector3.new(0, lift, 0) + look * travel + side * lateral
		-- смотрим на остров и чуть выше, чтобы в кадр попала вода перед ним
		return CFrame.lookAt(camPos, islandPos + Vector3.new(0, 8, 0))
	end

	cam.CameraType = Enum.CameraType.Scriptable
	toast("Остров побольше…")

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not (hrp.Parent and cam) then
			conn:Disconnect()
			giveCameraBack()   -- игрок умер посреди сцены: камеру — новому персонажу
			return
		end
		local t = os.clock() - t0
		if t < BLEND_IN then
			local a = t / BLEND_IN
			a = a * a * (3 - 2 * a)
			cam.CFrame = playerCamCF():Lerp(sceneCF(0), a)
			cam.FieldOfView = FOV_FROM
		elseif t < BLEND_IN + SHOT_TIME then
			local e = (t - BLEND_IN) / SHOT_TIME
			e = e * e * (3 - 2 * e)
			cam.CFrame = sceneCF(e)
			cam.FieldOfView = FOV_FROM + (FOV_TO - FOV_FROM) * e
		elseif t < BLEND_IN + SHOT_TIME + BLEND_OUT then
			local a = (t - BLEND_IN - SHOT_TIME) / BLEND_OUT
			a = a * a * (3 - 2 * a)
			cam.CFrame = sceneCF(1):Lerp(playerCamCF(), a)
			cam.FieldOfView = FOV_TO + (FOV_FROM - FOV_TO) * a
		else
			conn:Disconnect()
			giveCameraBack()
			-- сцена доиграла: игрок думает вслух, и под мысль заходит музыка
			task.delay(THOUGHT_WAIT, function()
				if _G.StartLocalDialogue then
					_G.StartLocalDialogue("OutpostSightThought")
				end
				startMusic()
			end)
		end
	end)
end

sceneEvent.OnClientEvent:Connect(function(kind, islandPos)
	if kind == "cleared" then
		-- остров зачищен: тревожный фон больше не про что
		stopMusic()
		return
	end
	if kind ~= "found" then return end
	if played then return end
	played = true
	-- Персонаж на входе в сцену обязателен: без него неоткуда взять точку
	-- отсчёта и некуда возвращать камеру. Ждём его недолго — если игрок как раз
	-- респавнится, лучше показать сцену на секунду позже, чем не показать.
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		if not char:FindFirstChild("HumanoidRootPart") then
			char:WaitForChild("HumanoidRootPart", 5)
		end
		task.wait(0.6)
		playCutscene(islandPos)
	end)
end)
