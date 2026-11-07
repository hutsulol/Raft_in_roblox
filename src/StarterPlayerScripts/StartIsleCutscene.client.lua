--[[
	КАТСЦЕНА ПОЯВЛЕНИЯ СТАРТОВОГО ОСТРОВА.

	Сервер (StartIsleStory.server.lua) поднимает остров на второй день, на 30%
	дня, и шлёт сюда его координату. Мы забираем камеру, уводим её от игрока в
	сторону острова, сужаем угол обзора — остров стоит в шести сотнях студов, и
	без «зума» это точка на горизонте, — потом возвращаем всё как было и даём
	игроку подумать вслух (StartIsleThought).

	⚠️ СДЕЛАНО ПО ОБРАЗЦУ ТУМАНА (WaveTelegraph.client), И ЭТО НЕ ЛЕНЬ.
	Тамошний playCutscene — файловая локальная функция, наружу не отдана, и вся
	её математика прибита к «лететь в сторону компаса над водой». Общего у двух
	сцен ровно три вещи — плавный вход, ручной прогон CFrame по кадрам и
	аккуратный возврат камеры, — и они здесь повторены сознательно, вместе с
	теми граблями, которые там уже собраны (см. giveCameraBack).

	⚠️ ИГРОКА НЕ ЗАМОРАЖИВАЕМ. Ни туман, ни эта сцена не отбирают управление:
	катсцена на 7 секунд с отобранными ногами читается как зависание игры.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local BLEND_IN     = 0.7    -- вход в сцену
local SHOT_TIME    = 6.5    -- сам пролёт
local BLEND_OUT    = 0.9    -- возврат к игроку
local TRAVEL       = 240    -- на сколько студов камера уходит к острову
local LIFT_FROM    = 7
local LIFT_TO      = 30
local FOV_FROM     = 70     -- штатный угол
local FOV_TO       = 42     -- «приближаем» остров: иначе это точка на горизонте
local THOUGHT_WAIT = 2.5    -- через сколько после возврата камеры игрок думает вслух

local player = Players.LocalPlayer
local foundEvent = ReplicatedStorage:WaitForChild("StartIsleFound")

-- Один раз за сессию: остров появляется однажды, а повторный вызов посреди
-- первого дрался бы с ним за камеру.
local played = false

-- Нижняя строка, как «Туман поднимается…»: подпись держится, пока идёт пролёт.
local function toast(text)
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "StartIsleToastGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = pg

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.72)
	lbl.Size = UDim2.fromOffset(640, 50)
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
		local lateral = (e * 2 - 1) * 7
		local lift    = LIFT_FROM + (LIFT_TO - LIFT_FROM) * e
		local camPos  = p + Vector3.new(0, lift, 0) + look * travel + side * lateral
		-- смотрим ровно на остров и чуть выше него, чтобы в кадр попала вода перед ним
		return CFrame.lookAt(camPos, islandPos + Vector3.new(0, 6, 0))
	end

	cam.CameraType = Enum.CameraType.Scriptable
	toast("Земля на горизонте…")

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
			-- сцена доиграла: игрок думает вслух про найденную землю
			task.delay(THOUGHT_WAIT, function()
				if _G.StartLocalDialogue then
					_G.StartLocalDialogue("StartIsleThought")
				end
			end)
		end
	end)
end

foundEvent.OnClientEvent:Connect(function(islandPos)
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
