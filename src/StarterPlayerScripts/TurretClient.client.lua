-- TurretClient.client.lua
-- Клиентское управление пулемётом-турелью (пара к TurretSystem.server):
--   • сел → играет анимация сидения, включается управление;
--   • ПРИЦЕЛ: камера уходит «в ствол», крестик по центру;
--   • 3-Е ЛИЦО: камера позади турели + МЕТКА, куда упадёт снаряд (баллистика), и линия траектории;
--   • A/D или ←/→ — поворот влево-вправо (сервер вращает сборку);
--   • ЛКМ (удержание) — очередь: сервер стреляет поочерёдно из bullet_1..6;
--   • переключатель режима «Прицел / 3-е лицо» внизу; выход — Пробел (встать).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local rEnter = ReplicatedStorage:WaitForChild("TurretEnter")
local rExit  = ReplicatedStorage:WaitForChild("TurretExit")
local rInput = ReplicatedStorage:WaitForChild("TurretInput")
local rFire  = ReplicatedStorage:WaitForChild("TurretFire")

local FIRE_INTERVAL = 0.12 -- как FIRE_COOLDOWN на сервере
local DEFAULT_SPEED = 200
-- НЕЛИНЕЙНАЯ скорость: горизонтальная составляющая затухает exp(-DRAG*t) — пуля
-- резко вылетает и замедляется к концу. Сервер отдаёт нам владение своими пулями
-- (SetNetworkOwner), поэтому затухание применяем МЫ — и ровно тем же коэффициентом
-- считаем траекторию маркера, чтобы метка попадания не врала.
local BULLET_DRAG = 0.5

-- ── состояние ──
local active = nil          -- модель турели, за которой сидим
local pushka = nil
local bullets = nil
local lastYaw, lastPitch = 0, 0
local firing = false
local fireAccum = 0
local fireInterval = FIRE_INTERVAL -- темп ЭТОЙ турели (сервер пишет в атрибут FireCooldown)
local sitTrack = nil

-- то же направление выстрела, что на сервере (Pushka + атрибуты модели)
local function axisVec(cf, name)
	if name == "X" then return cf.RightVector end
	if name == "Y" then return cf.UpVector end
	return cf.LookVector
end
local function fireDir()
	if not (active and pushka) then return Vector3.new(0, 0, -1) end
	local axis = active:GetAttribute("AimAxis") or "Z"
	local sign = active:GetAttribute("AimSign") or 1 -- LookVector уже «вперёд»
	local pitch = math.rad(active:GetAttribute("AimPitchDeg") or 0)
	local d = axisVec(pushka.CFrame, axis) * sign
	if pitch ~= 0 then
		local right = Vector3.new(d.Z, 0, -d.X)
		if right.Magnitude > 1e-3 then d = CFrame.fromAxisAngle(right.Unit, pitch) * d end
	end
	return d.Unit
end
local function muzzlePos()
	if not bullets or #bullets == 0 then return pushka and pushka.Position or Vector3.zero end
	local s = Vector3.zero
	for _, b in ipairs(bullets) do s += b.Position end
	return s / #bullets
end

-- ══════════ UI ══════════
local gui = Instance.new("ScreenGui")
gui.Name = "TurretHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.Enabled = false
gui.Parent = playerGui

-- (переключатель режимов и крестик прицела убраны: у обоих пулемётов только 3-е лицо)

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

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -hintBottomOffset())
-- Пересчитываем на смене размера окна: телефон могут повернуть, и доля высоты
-- станет другой. Один вызов при запуске оставил бы подсказку на старом месте.
do
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			hint.Position = UDim2.new(0.5, 0, 1, -hintBottomOffset())
		end)
	end
end

hint.Size = UDim2.fromOffset(420, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamBold
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(210, 222, 235)
hint.TextStrokeColor3 = Color3.fromRGB(0,0,0)
hint.TextStrokeTransparency = 0.4
local turretTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
hint.Text = turretTouch
	and "Поверните экран для поворота пулемёта"
	or "A/D — поворот   •   W/S — наклон   •   ЛКМ — огонь   •   Пробел — встать"
hint.Parent = gui

-- ⚠️ НА ТЕЛЕФОНЕ ОГОНЬ — ОТДЕЛЬНАЯ КНОПКА, УДЕРЖАНИЕМ.
-- ЛКМ на телефоне нет вовсе, стрелять было нечем. Место и вид те же, что у кнопки
-- стройки и у пушки: «действие» всегда в одном углу.
-- Очередь идёт, пока палец на кнопке, поэтому слушаем нажатие И отпускание, а не
-- Activated: Activated приходит уже после отпускания, и очередь была бы в один
-- выстрел.
local fireGui, fireBtn
if turretTouch then
	fireGui = Instance.new("ScreenGui")
	fireGui.Name = "TurretFireButton"
	fireGui.ResetOnSpawn = false
	fireGui.IgnoreGuiInset = true
	fireGui.DisplayOrder = 26
	fireGui.Enabled = false
	fireGui.Parent = playerGui

	fireBtn = Instance.new("ImageButton")
	fireBtn.Name = "Fire"
	fireBtn.AnchorPoint = Vector2.new(1, 1)
	fireBtn.Position = UDim2.new(1, -24, 1, -232)   -- как кнопка стройки и пушки
	fireBtn.Size = UDim2.fromOffset(132, 132)
	fireBtn.BackgroundTransparency = 1
	fireBtn.BorderSizePixel = 0
	fireBtn.AutoButtonColor = false
	fireBtn.Image = "rbxassetid://113911617603315"
	fireBtn.ImageTransparency = 0.25   -- непрозрачность 75%
	fireBtn.ScaleType = Enum.ScaleType.Fit
	fireBtn.Parent = fireGui
	-- ⚠️ ТОТ ЖЕ МАСШТАБ, ЧТО У КНОПКИ СТРОЙКИ.
	-- Кнопка стройки живёт внутри BuildingGui, а ему выдан общий масштаб интерфейса
	-- (AttachInventoryUIScale). Эта кнопка своего масштаба не имела и потому
	-- выглядела заметно крупнее при том же числе пикселей. Подписываемся на тот же.
	if _G.AttachInventoryUIScale then _G.AttachInventoryUIScale(fireGui) end
end

-- метка попадания (3-е лицо): яркий неоновый шарик в мире
local marker = Instance.new("Part")
marker.Name = "TurretAimMarker"
marker.Shape = Enum.PartType.Ball
marker.Size = Vector3.new(2.4, 2.4, 2.4)
marker.Color = Color3.fromRGB(255, 70, 70)
marker.Material = Enum.Material.Neon
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.Transparency = 1
marker.Parent = workspace
-- (BillboardGui с «✕» убран: глифа нет в GothamBlack → рисовался пустым красным
-- прямоугольником-тофу. Метка = сам неоновый шарик.)

-- пул «бусин» траектории
local beads = {}
for i = 1, 22 do
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball; p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.Color = Color3.fromRGB(255, 200, 90); p.Material = Enum.Material.Neon
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Transparency = 1; p.Parent = workspace
	beads[i] = p
end

local function hideAim()
	marker.Transparency = 1
	for _, p in ipairs(beads) do p.Transparency = 1 end
end

-- симуляция баллистики: точки траектории + точка падения (raycast по сегментам)
local function simulateTrajectory()
	local origin = muzzlePos()
	local speed = (active and active:GetAttribute("BulletSpeed")) or DEFAULT_SPEED
	local vel = fireDir() * speed
	local g = Vector3.new(0, -workspace.Gravity, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { active, player.Character, marker, table.unpack(beads) }
	local pos = origin
	local dt = 0.09
	local hitPos = nil
	local pts = {}
	local drag = math.exp(-BULLET_DRAG * dt) -- то же затухание, что у реальной пули
	for step = 1, 90 do
		local nextPos = pos + vel * dt + 0.5 * g * dt * dt
		vel = Vector3.new(vel.X * drag, vel.Y, vel.Z * drag) + g * dt
		local res = workspace:Raycast(pos, nextPos - pos, params)
		if step % 4 == 0 then pts[#pts + 1] = pos end
		if res then hitPos = res.Position; break end
		pos = nextPos
		if pos.Y < origin.Y - 400 then break end
	end
	return hitPos or pos, pts
end

-- метка падения снаряда (3-е лицо) + бусины траектории
local function updateAim()
	if not active then hideAim(); return end
	local land, pts = simulateTrajectory()
	marker.Position = land
	marker.Transparency = 0
	for i, p in ipairs(beads) do
		local src = pts[i]
		if src then p.Position = src; p.Transparency = 0.15 else p.Transparency = 1 end
	end
end

-- ══════════ камера: только 3-е лицо ══════════
-- Камера ОРБИТИТ за стволом — следует и за поворотом, и за наклоном (полный dir, а не
-- горизонтальная проекция). Целишь вверх — камера опускается за ствол и смотрит в небо;
-- целишь вниз — поднимается и смотрит на воду. Пушка не перекрывает вид, всё видно.
local function updateCamera()
	if not (active and pushka) then return end
	camera.CameraType = Enum.CameraType.Scriptable
	local dir = fireDir()
	local center = pushka.Position
	local eye = center - dir * 16 + Vector3.new(0, 6, 0)
	camera.CFrame = CFrame.lookAt(eye, center + dir * 10)
	camera.FieldOfView = 70
end

-- ══════════ вход / выход ══════════
local function playSit(animId)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not animId then return end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation"); anim.AnimationId = animId
	local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and tr then
		tr.Priority = Enum.AnimationPriority.Action
		tr.Looped = true
		tr:Play(0.2)
		sitTrack = tr
	end
end

local function enter(model, sitAnim)
	active = model
	fireInterval = model:GetAttribute("FireCooldown") or FIRE_INTERVAL
	pushka = model:FindFirstChild("Pushka", true)
	bullets = {}
	local i = 1
	while true do
		local b = model:FindFirstChild("bullet_" .. i, true)
		if not b then break end
		bullets[i] = b; i += 1
	end
	gui.Enabled = true
	if fireGui then fireGui.Enabled = true end
	playSit(sitAnim)
	-- InventoryUI: блок предметов хотбара + панель уезжает вниз
	game.Players.LocalPlayer:SetAttribute("OnTurret", true)
end

local function exit()
	if sitTrack then pcall(function() sitTrack:Stop(0.2) end) sitTrack = nil end
	active, pushka, bullets = nil, nil, nil
	firing = false
	lastYaw, lastPitch = 0, 0
	gui.Enabled = false
	if fireGui then fireGui.Enabled = false end
	hideAim()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	game.Players.LocalPlayer:SetAttribute("OnTurret", false)
end

rEnter.OnClientEvent:Connect(enter)
rExit.OnClientEvent:Connect(exit)

-- ── затухание СВОИХ пуль (сервер отдал нам их владение) ──
-- Горизонтальная скорость гаснет exp(-BULLET_DRAG*t): резкий вылет, замедление к
-- концу. Вертикаль не трогаем — гравитация остаётся честной, дуга не «плывёт».
local myShells = {}
workspace.ChildAdded:Connect(function(c)
	if c.Name ~= "Bullet_Cannon" then return end
	task.defer(function() -- creator появляется на кадр позже самой пули
		local cr = c:FindFirstChild("creator")
		if cr and cr.Value == player then myShells[c] = true end
	end)
end)
RunService.Heartbeat:Connect(function(dt)
	if not next(myShells) then return end
	local k = math.exp(-BULLET_DRAG * dt)
	for s in pairs(myShells) do
		if s.Parent then
			local v = s.AssemblyLinearVelocity
			s.AssemblyLinearVelocity = Vector3.new(v.X * k, v.Y, v.Z * k)
		else
			myShells[s] = nil
		end
	end
end)

-- Сырой вектор ввода штатного модуля управления — один в один как в CannonControl.
-- Берём лениво и через pcall: модуль появляется в PlayerScripts не мгновенно.
local turretControls
local function turretMoveVector()
	if not turretControls then
		local ok, ctrls = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 5)
			return require(scripts:WaitForChild("PlayerModule", 5)):GetControls()
		end)
		if not ok or not ctrls then return Vector3.zero end
		turretControls = ctrls
	end
	local ok, v = pcall(function() return turretControls:GetMoveVector() end)
	return (ok and v) or Vector3.zero
end

-- ⚠️ ТЕЛЕФОН: НАВОДКА СВАЙПОМ ПО ЭКРАНУ («Поверните экран…» в подсказке).
-- Считаем только касания, начатые НЕ по интерфейсу: палец на стике или на кнопке
-- огня (gameProcessed) наводку не дёргает. Смещение копим по позициям касания
-- между кадрами, а не по InputObject.Delta — у касаний оно приходит не везде.
local swipeTouches = {}            -- [касание] = прошлая позиция
local swipeAccum = Vector2.zero    -- пиксели с прошлого кадра
UserInputService.InputBegan:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.Touch and not gp and active then
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
-- пулемёт сервер крутит СКОРОСТЬЮ (-1..1): скорость пальца → скорость поворота.
-- SWIPE_FULL пикс/с = полная скорость; сглаживаем, чтобы ствол не дёргался по кадрам.
local SWIPE_FULL = 320
local swipeRate = Vector2.zero
local swipeClock = os.clock()

-- ── ввод: поворот A/D ←→ + наклон W/S ↑↓ (+ свайп на телефоне) ──
local function refreshInputDir()
	if not active then return end
	local nowC = os.clock()
	local sdt = math.max(nowC - swipeClock, 1 / 240)
	swipeClock = nowC
	local target = takeSwipe() / sdt / SWIPE_FULL
	if not next(swipeTouches) then target = Vector2.zero end   -- палец убран — стоп
	swipeRate = swipeRate:Lerp(target, math.min(1, sdt * 14))
	if swipeRate.Magnitude < 0.03 then swipeRate = Vector2.zero end
	local yaw, pitch = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then yaw -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then yaw += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then pitch += 1 end   -- ствол вверх
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then pitch -= 1 end -- ствол вниз

	-- ⚠️ ДЖОЙСТИК НАВОДИТ ТАК ЖЕ, КАК КЛАВИШИ (см. CannonControl, там то же самое).
	-- IsKeyDown на телефоне не даёт ничего, и пулемёт был неуправляемым. Берём сырой
	-- вектор ввода у штатного модуля: он есть и у стика, и у клавиатуры, и не зависит
	-- от того, может ли персонаж идти (за турелью он заморожен).
	-- Знаки ЗДЕСЬ ОБРАТНЫ пушечным: у турели вправо это yaw +1, а не -1.
	local mv = turretMoveVector()
	if mv.Magnitude > 0.05 then
		yaw += mv.X
		pitch -= mv.Z
	end

	-- свайп: вправо → вправо, вверх → ствол вверх (Y экрана растёт вниз)
	yaw += swipeRate.X
	pitch -= swipeRate.Y
	-- шаг 0.1: аналоговый свайп иначе слал бы ввод серверу каждый кадр
	yaw = math.floor(math.clamp(yaw, -1, 1) * 10 + 0.5) / 10
	pitch = math.floor(math.clamp(pitch, -1, 1) * 10 + 0.5) / 10

	if yaw ~= lastYaw or pitch ~= lastPitch then
		lastYaw, lastPitch = yaw, pitch
		rInput:FireServer(yaw, pitch)
	end
end
UserInputService.InputBegan:Connect(function(input, gp)
	if not active then return end
	if GamepadInput.isPrimary(input) and not gp then
		firing = true; fireAccum = fireInterval -- первый выстрел сразу
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if GamepadInput.isPrimary(input) then firing = false end
end)

if fireBtn then
	fireBtn.InputBegan:Connect(function(input)
		if not active then return end
		if input.UserInputType == Enum.UserInputType.Touch then
			firing = true; fireAccum = fireInterval   -- первый выстрел сразу
		end
	end)
	fireBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then firing = false end
	end)
end

RunService.RenderStepped:Connect(function(dt)
	if not active then clearSwipe() swipeRate = Vector2.zero return end   -- сошли — старый свайп не копим
	-- турель могла исчезнуть / игрок встал
	if not active.Parent then exit(); return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Sit == false then
		-- встал (или нет гуманоида) → выходим (сервер тоже пришлёт exit)
		exit(); return
	end
	refreshInputDir()
	updateCamera()
	updateAim()
	if firing then
		fireAccum += dt
		if fireAccum >= fireInterval then
			fireAccum = 0
			rFire:FireServer()
		end
	end
end)
