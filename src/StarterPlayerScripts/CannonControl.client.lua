-- CannonControl.client.lua
-- Aim mode for the player's cannon. While active the character is frozen and you
-- steer the barrel: A/D turn left/right, W/S tilt up/down (each capped at 25°).
-- A green arc previews the shot from the barrel's pivot. LMB fires, X cancels.
-- Power is fixed; only the barrel moves (the server keeps it mounted on the raft).

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))

local player = Players.LocalPlayer
local ctrlEvent = ReplicatedStorage:WaitForChild("CannonControl")

-- ⚠️ СЫРОЙ ВЕКТОР ВВОДА, А НЕ ДВИЖЕНИЕ ПЕРСОНАЖА.
-- Штатный PlayerModule отдаёт то, что игрок ЗАДАЛ стиком или клавишами, независимо
-- от того, может ли персонаж идти. Нам это и нужно: на время наводки сервер ставит
-- WalkSpeed = 0, и Humanoid.MoveDirection всё время нулевой.
-- Модуль берём лениво и через pcall: он появляется в PlayerScripts не мгновенно, а
-- падать из-за наводки пушки нельзя.
local controlsModule
local function moveVector()
	if not controlsModule then
		local ok, ctrls = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 5)
			return require(scripts:WaitForChild("PlayerModule", 5)):GetControls()
		end)
		if not ok or not ctrls then return Vector3.zero end
		controlsModule = ctrls
	end
	local ok, v = pcall(function() return controlsModule:GetMoveVector() end)
	return (ok and v) or Vector3.zero
end

local POWER = 240        -- fixed shot power (no longer adjustable)
local MUZZLE_CLEAR = 2   -- must match the server
local DOTS = 28
local BARREL_FLIP = false -- must match the server

-- aim limits (radians) + turn rates — must match the server's limits
local YAW_LIMIT = math.rad(25)
local PITCH_MIN, PITCH_MAX = -math.rad(25), math.rad(25)
local YAW_RATE = 0.6   -- rad/s while holding A/D
local PITCH_RATE = 0.6 -- rad/s while holding W/S

local aiming = false
local main, carriage, relRest = nil, nil, nil
local yaw, pitch = 0, 0
local dots = {}
local lastSend = 0

-- barrel's forward axis (longest side) — identical math to the server
local function forwardAxis(cf, size)
	local fwd
	if size.Z >= size.X and size.Z >= size.Y then fwd = cf.LookVector
	elseif size.X >= size.Y then fwd = cf.RightVector
	else fwd = cf.UpVector end
	if BARREL_FLIP then fwd = -fwd end
	return fwd
end
local barrelFlip = false -- per-cannon muzzle flip, sent by the server on enter
local aimZ = false       -- per-cannon: tilt around Z (length-along-X barrels), sent by the server

local function makeDots()
	for i = 1, DOTS do
		local d = Instance.new("Part")
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.new(0.7, 0.7, 0.7)
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = Color3.fromRGB(120, 255, 130)
		d.Transparency = 0.1
		d.Parent = workspace
		dots[i] = d
	end
end
local function clearDots()
	for _, d in ipairs(dots) do d:Destroy() end
	dots = {}
end

-- ── slim hint bar ──
local sg = Instance.new("ScreenGui")
sg.Name = "CannonControlUI"
sg.ResetOnSpawn = false
sg.Enabled = false
sg.Parent = player:WaitForChild("PlayerGui")
--[[ ⚠️ НА ТЕЛЕФОНЕ ПОДСКАЗКУ НАДО ПОДНИМАТЬ НАД ХОТБАРОМ.
     Внизу экрана у телефона живёт хотбар с предметами, и полоска подсказки,
     прижатая к нижней кромке, ложилась прямо на него — читать нельзя ни то, ни
     другое. Отступ считаем от ВЫСОТЫ ОКНА, а не фиксированным числом: у
     телефонов она разная, и на длинном экране жёсткие пиксели снова упрутся в
     хотбар. На клавиатуре хотбара внизу нет, там прежние 24 пикселя. ]]
local function hintBottomOffset()
	local onPhone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if not onPhone then return 24 end
	local cam = workspace.CurrentCamera
	local h = (cam and cam.ViewportSize.Y > 0) and cam.ViewportSize.Y or 720
	return math.max(130, h * 0.22)
end

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -hintBottomOffset())
-- Пересчитываем на смене размера окна: телефон могут повернуть, и доля высоты
-- станет другой. Один вызов при запуске оставил бы подсказку на старом месте.
do
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			panel.Position = UDim2.new(0.5, 0, 1, -hintBottomOffset())
		end)
	end
end

panel.Size = UDim2.fromOffset(430, 30)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BackgroundTransparency = 0.3
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local hintLbl = Instance.new("TextLabel")
hintLbl.BackgroundTransparency = 1
hintLbl.Size = UDim2.fromScale(1, 1)
hintLbl.Font = Enum.Font.GothamMedium
hintLbl.TextSize = 13
hintLbl.TextColor3 = Color3.fromRGB(210, 215, 225)
hintLbl.Text = (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	and "Поверните экран для поворота пушки"
	or "A/D — поворот   •   W/S — наклон   •   ЛКМ — выстрел   •   X — отмена"
hintLbl.Parent = panel

-- ⚠️ НА ТЕЛЕФОНЕ ВЫСТРЕЛ — ОТДЕЛЬНАЯ КНОПКА.
-- Огонь висел на ЛКМ, а её на телефоне нет вовсе: выстрелить было нельзя.
-- Место и вид те же, что у кнопки стройки, — игрок уже знает, где искать «действие»
-- в этом углу, и не приходится заводить второй язык интерфейса.
local onTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local fireGui, fireBtn
if onTouch then
	fireGui = Instance.new("ScreenGui")
	fireGui.Name = "CannonFireButton"
	fireGui.ResetOnSpawn = false
	fireGui.IgnoreGuiInset = true
	fireGui.DisplayOrder = 25
	fireGui.Enabled = false
	fireGui.Parent = player:WaitForChild("PlayerGui")

	fireBtn = Instance.new("ImageButton")
	fireBtn.Name = "Fire"
	fireBtn.AnchorPoint = Vector2.new(1, 1)
	fireBtn.Position = UDim2.new(1, -24, 1, -232)   -- как кнопка стройки
	fireBtn.Size = UDim2.fromOffset(132, 132)
	fireBtn.BackgroundTransparency = 1
	fireBtn.BorderSizePixel = 0
	fireBtn.AutoButtonColor = false
	fireBtn.Image = "rbxassetid://113911617603315"
	fireBtn.ImageTransparency = 0.25   -- непрозрачность 75%
	fireBtn.ScaleType = Enum.ScaleType.Fit
	fireBtn.Parent = fireGui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = fireBtn

	-- ⚠️ ТОТ ЖЕ МАСШТАБ, ЧТО У КНОПКИ СТРОЙКИ.
	-- Кнопка стройки живёт внутри BuildingGui, а ему выдан общий масштаб интерфейса
	-- (AttachInventoryUIScale). Эта своего масштаба не имела и потому выглядела
	-- заметно крупнее при том же числе пикселей. Подписываемся на тот же.
	if _G.AttachInventoryUIScale then _G.AttachInventoryUIScale(fireGui) end
end

local function stop()
	aiming = false
	game.Players.LocalPlayer:SetAttribute("OnTurret", false)   -- InventoryUI: хотбар возвращается
	sg.Enabled = false
	if fireGui then fireGui.Enabled = false end
	clearDots()
	main, carriage, relRest = nil, nil, nil
end

-- Выстрел один на оба входа: ЛКМ и кнопка. Две копии разъехались бы на первой же
-- правке (например, если добавится перезарядка).
local function fireNow()
	if not aiming then return end
	ctrlEvent:FireServer("fire", POWER, yaw, pitch)
	stop()
end

if fireBtn then
	-- Activated, а не MouseButton1Click: первое приходит и от касания, и от мыши
	fireBtn.Activated:Connect(fireNow)
end

ctrlEvent.OnClientEvent:Connect(function(action, _cannon, m, carr, rel, sy, sp, fl, az)
	if action == "enter" and m and carr and rel then
		main, carriage, relRest = m, carr, rel
		barrelFlip = fl == true
		aimZ = az == true
		yaw = sy or 0    -- resume from where the barrel is already aimed
		pitch = sp or 0
		aiming = true
		game.Players.LocalPlayer:SetAttribute("OnTurret", true)   -- InventoryUI: блок предметов, хотбар уезжает
		sg.Enabled = true
		if fireGui then fireGui.Enabled = true end
		makeDots()
	elseif action == "exit" then
		stop()
	end
end)

-- ⚠️ ТЕЛЕФОН: НАВОДКА СВАЙПОМ ПО ЭКРАНУ («Поверните экран…» в подсказке).
-- Считаем только касания, начатые НЕ по интерфейсу: палец на стике или на кнопке
-- огня (gameProcessed) наводку не дёргает. Смещение копим по позициям касания
-- между кадрами, а не по InputObject.Delta — у касаний оно приходит не везде.
local swipeTouches = {}            -- [касание] = прошлая позиция
local swipeAccum = Vector2.zero    -- пиксели с прошлого кадра
UserInputService.InputBegan:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.Touch and not gp and aiming then
		swipeTouches[input] = Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UserInputService.TouchMoved:Connect(function(input)
	local last = swipeTouches[input]
	if not last then return end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	swipeAccum += p - last
	swipeTouches[input] = p
end)
UserInputService.InputEnded:Connect(function(input)
	swipeTouches[input] = nil
end)
-- смещение пальца с прошлого вызова (пиксели), счётчик обнуляется
local function takeSwipe()
	local d = swipeAccum
	swipeAccum = Vector2.zero
	return d
end
local function clearSwipe()
	table.clear(swipeTouches)
	swipeAccum = Vector2.zero
end
-- пушку клиент наводит сам (угол), поэтому свайп — прямо в угол: рад на пиксель
local SWIPE_RAD = 0.004

RunService.RenderStepped:Connect(function(dt)
	if not aiming or not main or not main.Parent or not carriage or not carriage.Parent then clearSwipe() return end
	-- WASD steer the barrel (IsKeyDown ignores the movement controller swallowing the keys)
	local dy, dp = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dy += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dy -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dp += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dp -= 1 end

	-- ⚠️ ДЖОЙСТИК НАВОДИТ ТАК ЖЕ, КАК WASD.
	-- IsKeyDown на телефоне не даёт ничего: клавиш нет, и пушка была неуправляемой.
	-- Humanoid.MoveDirection тут тоже не подходит — на время наводки игроку ставят
	-- WalkSpeed = 0 (freeze на сервере), персонаж не движется, и MoveDirection нулевой.
	-- Берём СЫРОЙ вектор ввода у штатного модуля управления: он есть и у стика, и у
	-- клавиатуры, и не зависит от того, может ли персонаж идти.
	local mv = moveVector()
	if mv.Magnitude > 0.05 then
		-- вектор в осях камеры: +X вправо, -Z вперёд. Знаки те же, что у клавиш.
		dy -= mv.X
		dp -= mv.Z
	end
	-- свайп: вправо → ствол вправо (у пушки это минус yaw), вверх → ствол вверх
	local sw = takeSwipe()
	yaw -= sw.X * SWIPE_RAD
	pitch -= sw.Y * SWIPE_RAD
	yaw = math.clamp(yaw + dy * YAW_RATE * dt, -YAW_LIMIT, YAW_LIMIT)
	pitch = math.clamp(pitch + dp * PITCH_RATE * dt, PITCH_MIN, PITCH_MAX)
	-- tell the server the new aim (throttled)
	local now = os.clock()
	if now - lastSend > 0.04 then
		lastSend = now
		ctrlEvent:FireServer("aim", yaw, pitch)
	end
	-- predicted barrel pose (same formula the server uses) → trajectory from the pivot
	local aimCF = carriage.CFrame * relRest * (aimZ and CFrame.Angles(0, yaw, -pitch) or CFrame.Angles(pitch, yaw, 0))
	local fwd = forwardAxis(aimCF, main.Size) * (barrelFlip and -1 or 1)
	local origin = (aimCF * main.PivotOffset).Position + fwd * MUZZLE_CLEAR
	local g = workspace.Gravity
	local floorY = origin.Y - 90
	for i = 1, DOTS do
		local t = (i - 1) * 0.06
		local p = origin + fwd * (POWER * t) - Vector3.new(0, 0.5 * g * t * t, 0)
		dots[i].Position = p
		dots[i].Transparency = (p.Y < floorY) and 1 or 0.1
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if not aiming then return end
	if GamepadInput.isKey(input, Enum.KeyCode.X) then
		ctrlEvent:FireServer("cancel")
		stop()
	elseif GamepadInput.isPrimary(input) and not gp then
		fireNow()
	end
end)
