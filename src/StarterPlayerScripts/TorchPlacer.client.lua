local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- TorchPlacer.client.lua
-- Постановка ФАКЕЛА (Tool "Torch"). Пока игрок ДЕРЖИТ факел в руке — в левом-верхнем
-- углу (там же, где кнопка доната дерева) появляется круглая кнопка «Поставить». Клик →
-- режим постройки: зелёный призрак-факел следует за мышью, ставится на плот И НА СТЕНЫ
-- (ориентируется по нормали поверхности), а ДВА круга вращения задают наклон по осям X и Z
-- (как круг у пушки, только два). Клик по миру → сервер варит факел к плоту (CanonSystem),
-- сам факел остаётся в инвентаре.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse     = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera    = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

--[[ ⚠️ ПОСТАНОВКА НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Факел целится той же единственной строкой, что и остальные ставилки, — лучом
     из курсора, которого на телефоне нет вовсе. Там прицел даёт тап, а
     подтверждает кнопка; вся эта механика лежит в TouchPlace, здесь только три
     точки подключения: луч, начало сеанса и конец. На компьютере модуль не
     делает ничего. ]]
--[[ ⚠️ МЕХАНИКУ БЕРЁМ ИЗ HudScale, А ЖДЁМ — С ТАЙМАУТОМ. ДВЕ ЛОВУШКИ РАЗОМ.
     Первая: WaitForChild без второго аргумента ждёт ВЕЧНО, и не доехавший
     модуль остановил бы ВЕСЬ этот скрипт — предмет в руках есть, а поставить
     нельзя ничем и нигде, причём молча.
     Вторая, из-за которой правка и не работала на телефоне: НОВЫЙ файл до
     запущенной сессии Rojo доезжает не всегда. Правки существующих файлов
     синкаются, а новый инстанс появляется в плейсе только после
     переподключения — и ставилки честно откатывались на мышь, то есть на то
     самое поведение, от которого уходили.
     Поэтому спрашиваем сначала HudScale: он в плейсе давно и синкается штатно,
     а вся механика постановки живёт теперь в нём (HudScale.Place). Отдельный
     TouchPlace остаётся запасным именем — кто его нашёл, получит то же самое.
     Не нашли ни того, ни другого — работаем по-старому, мышью. ]]
-- касание без мыши = телефон. Считаем сами: запрет ставить пальцем не
-- должен зависеть от того, поднялся ли общий модуль
local IS_TOUCH = game:GetService("UserInputService").TouchEnabled
	and not game:GetService("UserInputService").MouseEnabled

local TouchPlace do
	local rs = game:GetService("ReplicatedStorage")
	local function grab(name, field)
		local mod = rs:FindFirstChild(name) or rs:WaitForChild(name, 5)
		if not mod then return nil end
		local ok, res = pcall(require, mod)
		if not ok then return nil end
		if field then res = (type(res) == "table") and res[field] or nil end
		return (type(res) == "table") and res or nil
	end

	TouchPlace = grab("HudScale", "Place") or grab("TouchPlace") or {
		isPhone = function() return false end,
		ray = function(m)
			local cam = workspace.CurrentCamera
			if not (cam and m) then return nil end
			return cam:ViewportPointToRay(m.X, m.Y)
		end,
		setHit = function() end,
		begin  = function() end,
		finish = function() end,
		active = function() return false end,
	}
	if not TouchPlace.begin or TouchPlace.isPhone() == nil then
		warn("[Установка] механика постановки не найдена — ставим по-старому, мышью")
	end
end

local TOOL_NAME   = "Torch"
local BUTTON_ICON = "rbxassetid://85393768788266" -- круглая иконка кнопки (в руке)
local DIAL_R      = 46
local GREEN       = Color3.fromRGB(80, 255, 80)
local RED         = Color3.fromRGB(255, 80, 80)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ── состояние ──
-- объявлена заранее: её зовёт createGhost, а определена она ниже по файлу
local onPlaceClick

local placing = false
local ghost = nil
local tiltX, tiltZ = 0, 0            -- радианы наклона по осям X и Z
local lastValid, lastLocalCF = false, nil
local HAMMER_TOOL = "Hammer"
local function holdingHammer()
	local char = player.Character
	local tl = char and char:FindFirstChildWhichIsA("Tool")
	return tl ~= nil and tl.Name == HAMMER_TOOL
end

local savedMinZoom, savedMaxZoom

-- ══════════ КНОПКА «ПОСТАВИТЬ» (пока держим факел) ══════════
local btnGui = new("ScreenGui", { Name = "TorchPlaceButton", ResetOnSpawn = false, DisplayOrder = 12, Enabled = false }, playerGui)
local btnHolder = new("Frame", {
	Position = UDim2.new(0.18, 0, 0.1, 0), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1,
}, btnGui)
local btn = new("ImageButton", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.44, 0), Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, Image = BUTTON_ICON, ScaleType = Enum.ScaleType.Fit, ZIndex = 1,
}, btnHolder)
local btnScale = new("UIScale", {}, btn)
local btnLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.86, 0), Size = UDim2.new(1.4, 0, 0, 20),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "Поставить", TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
}, btnHolder)
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2.5 }, btnLabel)

-- НАШЕ: НА ТЕЛЕФОНЕ КНОПКА МЕНЬШЕ И НЕ НА ТРЕКЕРЕ КВЕСТА. В исходном месте
-- (18% ширины, 10% высоты) она ложилась на полосу «Собери брёвна» и была
-- крупнее соседних иконок HUD. Ставим справа от столбика кнопок (Квесты /
-- Магазин) и ужимаем до их размера.
do
	local UIS = game:GetService("UserInputService")
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		btnHolder.Position = UDim2.new(0, 214, 0, 150)
		new("UIScale", { Scale = 0.65 }, btnHolder)
	end
end
btn.MouseEnter:Connect(function() btnScale.Scale = 1.1 end)
btn.MouseLeave:Connect(function() btnScale.Scale = 1 end)

-- ══════════ ДВА КРУГА ВРАЩЕНИЯ (наклон X и Z) ══════════
local dialGui = new("ScreenGui", { Name = "TorchTiltDials", ResetOnSpawn = false, DisplayOrder = 30, Enabled = false }, playerGui)

local function makeDial(rightOffset, title, colorRim)
	local dial = new("TextButton", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, rightOffset, 1, -110), Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Color3.fromRGB(20, 24, 32), BackgroundTransparency = 0.35, Text = "", AutoButtonColor = false,
	}, dialGui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, dial)
	new("UIStroke", { Color = colorRim, Thickness = 2, Transparency = 0.2 }, dial)
	local titleLbl = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(120, 16),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = colorRim, Text = title,
	}, dial)
	local readout = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 26),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = Color3.new(1, 1, 1), Text = "0°",
	}, dial)
	local knob = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = colorRim, Text = "", AutoButtonColor = false,
	}, dial)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	new("UIStroke", { Color = Color3.fromRGB(20, 40, 70), Thickness = 2 }, knob)
	return { dial = dial, knob = knob, readout = readout, angle = 0, dragging = false }
end

local dialX = makeDial(-150, "Наклон X", Color3.fromRGB(255, 150, 120))
local dialZ = makeDial(-18, "Наклон Z", Color3.fromRGB(120, 200, 255))

--[[ ⚠️ НА ТЕЛЕФОНЕ КРУГИ ПОВОРОТА УЕЗЖАЮТ НАВЕРХ.
     Они стояли в правом нижнем углу — ровно там, где на телефоне живёт кнопка
     постройки (та самая, круглая, с молотком). Друг на друга садились не
     числами, а масштабами: меню стройки сжимается инвентарным множителем, а
     круги рисовались в полный размер, и палец попадал то в поворот, то в
     постановку.
     Верх справа во время стройки свободен: полоска оружия там появляется
     только с оружием в руках, а строят молотком. Заодно ужимаем сами круги —
     сто тридцать пикселей на экране в четыреста это треть высоты. ]]
do
	local ok, Hud = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale", 5))
	end)
	if ok and Hud and Hud.isPhone and Hud.isPhone() then
		for _, d in ipairs(dialGui:GetChildren()) do
			if d:IsA("GuiObject") then
				d.AnchorPoint = Vector2.new(1, 0)
				-- X оставляем прежним (круги стоят рядом друг с другом), меняем только
				-- привязку по вертикали: от низа к верху
				d.Position = UDim2.new(1, d.Position.X.Offset, 0, 150)
			end
		end
		Hud.applyScaleLive(dialGui, Hud.iconFactor)
	end
end


local function updateDial(d)
	d.knob.Position = UDim2.new(0.5, math.cos(d.angle) * DIAL_R, 0.5, math.sin(d.angle) * DIAL_R)
	d.readout.Text = (math.floor(math.deg(d.angle) % 360 + 0.5)) .. "°"
end

-- ══════════ ПРИЗРАК ФАКЕЛА ══════════
local function createGhost()
	if ghost then ghost:Destroy(); ghost = nil end
	-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
	local tpl = AssetFind.find(TOOL_NAME)
	if not tpl then return end
	local clone = tpl:Clone()
	ghost = Instance.new("Model")
	ghost.Name = "TorchGhost"
	for _, d in ipairs(clone:GetChildren()) do
		if d:IsA("BasePart") then d.Parent = ghost end
	end
	clone:Destroy()
	local handle = ghost:FindFirstChild("Handle") or ghost:FindFirstChildWhichIsA("BasePart")
	if not handle then ghost:Destroy(); ghost = nil; return end
	ghost.PrimaryPart = handle
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 0.5; p.CanCollide = false; p.Anchored = true; p.Color = GREEN
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		elseif p:IsA("ParticleEmitter") or p:IsA("Fire") or p:IsA("Smoke") or p:IsA("Sparkles") then
			p.Enabled = false
		end
	end
	ghost.Parent = workspace
	--[[ ⚠️ ПОМЕЧАЕМ ПРИЗРАК, ЧТОБЫ ЕГО НЕ ПРИНЯЛИ ЗА ПОСТРОЙКУ.
	     Призрак — полная копия модели, с тем же именем. Чужие системы ищут свои
	     объекты именно по имени и находили его: подсказка плавильни начиналась,
	     когда печь ещё в руках, а не на плоту. Метка стоит копейки и снимает
	     целый класс таких путаниц. ]]
	ghost:SetAttribute("PlacementGhost", true)

	--[[ ⚠️ СЕАНС УСТАНОВКИ НАЧИНАЕМ ЗДЕСЬ: призрак живёт ровно столько же.
	     Кнопку поворота модулю не даём — наклон здесь задают два круга, а они
	     тянутся пальцем и без него.
	     onPlaceClick определена ниже по файлу, поэтому зовём её через обёртку:
	     к моменту нажатия кнопки она уже на месте. ]]
	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		-- призрак заслоняет палубу: без этого тап упирался бы в него самого
		ignore  = function() return ghost end,
	})
end

local function setGhostColor(valid)
	lastValid = valid
	if not ghost then return end
	local color = valid and GREEN or RED
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then p.Color = color end
	end
	--[[ ⚠️ ЦВЕТ ДЕТАЛЕЙ НА ТЕКСТУРНОЙ МОДЕЛИ НЕ ВИДЕН — НУЖНА ПОДСВЕТКА.
	     Выше мы красим сами детали, и на однотонных примитивах этого хватает. Но
	     мангал, бочка, плавильня и грядка — меши со своей текстурой: заданный
	     цвет по ним почти не читается, и призрак выглядел обычным предметом. У
	     очистителя подсветка была, у остальных нет — отсюда и «подсвечивается
	     только он».
	     Highlight поверх всей модели красит силуэт независимо от текстуры и
	     работает одинаково у всех. Создаём при первом обращении: призрак
	     пересоздаётся, и держать ссылку негде. ]]
	if ghost then
		local hl = ghost:FindFirstChild("GhostHighlight")
		if not hl then
			hl = Instance.new("Highlight")
			hl.Name = "GhostHighlight"
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = ghost
			hl.Parent = ghost
		end
		local hlColor = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
		hl.FillColor = hlColor
		hl.OutlineColor = hlColor
		hl.FillTransparency = 0.15
		hl.OutlineTransparency = 0
	end
end

-- построить ориентацию, где локальный +Y смотрит вдоль нормали поверхности
local function cfFromUp(pos, up)
	up = up.Unit
	local fwd = Vector3.new(0, 0, -1)
	if math.abs(up:Dot(fwd)) > 0.99 then fwd = Vector3.new(1, 0, 0) end
	local right = up:Cross(fwd).Unit
	fwd = right:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up, fwd)
end

local function updateGhost()
	if not ghost then return end
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then setGhostColor(false); return end
	-- Луч прицела: на компьютере из курсора, на телефоне — в точку тапа (TouchPlace)
	local unitRay = TouchPlace.ray(mouse)
	-- телефон, места ещё не выбрали: показывать призрак негде — как при промахе луча
	if not unitRay then setGhostColor(false); return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 250, params)
	if not result or not result.Instance then setGhostColor(false); return end
	local onRaft = result.Instance:IsDescendantOf(raft)
	local half = ghost:GetExtentsSize().Y / 2
	-- база: +Y факела вдоль нормали (пол → вверх, стена → в бок), приподняли над поверхностью
	local base = cfFromUp(result.Position + result.Normal * half, result.Normal)
	-- наклон по X и Z от двух кругов
	local finalCF = base * CFrame.Angles(tiltX, 0, tiltZ)
	ghost:PivotTo(finalCF)
	if onRaft then
		lastLocalCF = raft.PrimaryPart.CFrame:ToObjectSpace(finalCF)
		setGhostColor(true)
	else
		setGhostColor(false) -- ставить можно только на плот/его стены
	end
end

-- ══════════ старт / стоп ══════════
local function startPlace()
	if placing then return end
	placing = true
	tiltX, tiltZ = 0, 0
	dialX.angle, dialZ.angle = 0, 0
	updateDial(dialX); updateDial(dialZ)
	createGhost()
	dialGui.Enabled = true
	btnGui.Enabled = false
	savedMinZoom, savedMaxZoom = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local z = hrp and math.clamp((camera.CFrame.Position - hrp.Position).Magnitude, 4, 100) or 12
	player.CameraMinZoomDistance = z
	player.CameraMaxZoomDistance = z
end

local function stopPlace()
	placing = false
	if ghost then ghost:Destroy(); ghost = nil end
	lastValid, lastLocalCF = false, nil
	-- сеанс кончился: убрать кнопку телефона и забыть точку тапа
	TouchPlace.finish()
	dialGui.Enabled = false
	if savedMinZoom then
		player.CameraMinZoomDistance = savedMinZoom
		player.CameraMaxZoomDistance = savedMaxZoom
		savedMinZoom, savedMaxZoom = nil, nil
	end
end

local function holdingTorch()
	local char = player.Character
	local t = char and char:FindFirstChildWhichIsA("Tool")
	return t and t.Name == TOOL_NAME
end

-- ── подбор поставленного факела: рядом с ним та же кнопка превращается в «Подобрать» ──
local PICKUP_RADIUS = 8
local nearTorch = nil
local lastScan = 0

local function findNearPlacedTorch()
	local raftM = workspace:FindFirstChild("Raft")
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not raftM or not hrp then return nil end
	local best, bestD
	for _, c in ipairs(raftM:GetChildren()) do
		if c:IsA("Model") and c.Name:sub(1, 11) == "PlacedTorch" then
			local d = (c:GetPivot().Position - hrp.Position).Magnitude
			if d <= PICKUP_RADIUS and (not bestD or d < bestD) then best, bestD = c, d end
		end
	end
	return best
end

RunService.RenderStepped:Connect(function()
	local hold = holdingTorch()
	if not hold and placing then stopPlace() end
	-- скан поставленных факелов — не чаще 5 раз/с
	if os.clock() - lastScan > 0.2 then
		lastScan = os.clock()
		nearTorch = findNearPlacedTorch()
	end
	if placing then
		btnGui.Enabled = false
	elseif hold then
		btnLabel.Text = "Поставить"
		btnGui.Enabled = true
	elseif nearTorch and holdingHammer() then
		--[[ ⚠️ ПОДБОР — ТОЛЬКО ПОД МОЛОТКОМ.
		     Кнопка загоралась от одного соседства с факелом: игрок идёт мимо, а
		     ему предлагают его разобрать. Постановки это не касается — там факел
		     уже в руках, и предложение уместно. ]]
		btnLabel.Text = "Подобрать"
		btnGui.Enabled = true
	else
		btnGui.Enabled = false
	end
	if placing and ghost then updateGhost() end
end)

btn.Activated:Connect(function()
	if placing then return end
	if holdingTorch() then
		startPlace()
	elseif nearTorch and nearTorch.Parent then
		cupActionEvent:FireServer("pickupTorch", nearTorch)
	end
end)

-- ── перетаскивание кругов ──
local function angleFromInput(d, pos)
	local c = d.dial.AbsolutePosition + d.dial.AbsoluteSize / 2
	local dx, dy = pos.X - c.X, pos.Y - c.Y
	if dx * dx + dy * dy > 9 then
		d.angle = math.atan2(dy, dx)
		updateDial(d)
	end
end
local function bindDial(d, setter)
	local function beginDrag(input)
		if not placing then return end
		if GamepadInput.isPrimary(input) then
			d.dragging = true
			angleFromInput(d, input.Position)
			setter(d.angle)
		end
	end
	d.dial.InputBegan:Connect(beginDrag)
	d.knob.InputBegan:Connect(beginDrag)
	return d
end
bindDial(dialX, function(a) tiltX = a end)
bindDial(dialZ, function(a) tiltZ = a end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if dialX.dragging then angleFromInput(dialX, input.Position); tiltX = dialX.angle end
	if dialZ.dragging then angleFromInput(dialZ, input.Position); tiltZ = dialZ.angle end
end)
UserInputService.InputEnded:Connect(function(input)
	if GamepadInput.isPrimary(input) then
		dialX.dragging = false; dialZ.dragging = false
	end
end)

-- ── постановка по клику в мир (не по UI) + отмена по Esc ──
-- Тело общее: на компьютере его зовёт ЛКМ/тап, на телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	if not placing or not ghost then return end
	if not lastValid or not lastLocalCF then return end
	cupActionEvent:FireServer("placeBuilding", TOOL_NAME, lastLocalCF)
	stopPlace() -- факел тратится при установке — выходим из режима постройки
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Escape and placing then stopPlace(); return end
	if not placing or not ghost then return end
	if gameProcessed then return end -- клик ушёл в UI (круг/кнопка)
	if GamepadInput.isPrimary(input) then
		--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТАВИТ — ОН ВЫБИРАЕТ МЕСТО.
		     Касание приходит сюда как Touch (и как Button1Down заодно), поэтому
		     раньше первый же тап варил факел по точке ПРЕДЫДУЩЕГО касания: игрок
		     ещё целился, а факел уже стоял. Пока идёт сеанс, тап отдаём модулю —
		     он двигает прицел, — а ставит кнопка. Отмена по Esc выше этой
		     проверки и работает как прежде. ]]
		--[[ ⚠️ ПАЛЕЦ НЕ СТАВИТ НИКОГДА, ПОКА ВИСИТ ПРИЗРАК.
	     Здесь стояла проверка через модуль (isPhone и active). Она верна по
	     смыслу, но зависит от того, что модуль поднялся и сеанс открылся, — а
	     если хоть одно не сложилось, тап снова ставил предмет. Игрок крутит
	     камеру пальцем, и КАЖДЫЙ поворот превращался в постройку.
	     Поэтому спрашиваем СВОЁ состояние: висит призрак — значит идёт установка,
	     и палец в ней только целится. Ставит кнопка, она зовёт onPlaceClick
	     напрямую и мимо этой проверки. Хуже возможного исхода нет: не поднялся
	     модуль — предмет не поставится, но и не встанет туда, куда не целились. ]]
	if IS_TOUCH and ghost then return end
		onPlaceClick()
	end
end)
