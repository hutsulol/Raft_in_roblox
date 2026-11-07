local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- CanonPlacer.client.lua
-- Unified building placer (Cannon, Deffender/ПВО, …) — same pattern as the Furnace /
-- Workbench placers. Equip a building's tool → a green ghost follows the mouse on the
-- raft → click/tap to place. A circular dial gives FULL 360° rotation: drag the knob
-- (touch-friendly) or scroll the mouse wheel. Equipped-tool detection is poll-based
-- (char.ChildAdded misses some inventory flows like reward grants).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

--[[ ⚠️ ПОСТАНОВКА НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Прицел здесь один на все постройки — луч из курсора. Курсора на телефоне
     нет, поэтому там прицел даёт тап, а подтверждает кнопка. Вся механика лежит
     в TouchPlace, здесь только три точки подключения: луч, начало сеанса и
     конец. На компьютере модуль не делает ничего. ]]
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

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

-- tool name → ReplicatedStorage template model name (add more to make them placeable)
local BUILDINGS = {
	Cannon = "Cannon",
	Deffender = "Deffender",
	MagmaCannon = "MagmaCannon",
	Big_Magma_Cannon = "Big_Magma_Cannon",
	Pulemet_lvl_1 = "Pulemet_lvl_1", -- пулемёт: ставится призраком+циферблатом, как пушки
	Pulemet_lvl_2 = "Pulemet_lvl_2", -- эпический пулемёт
}
local WHEEL_STEP = 10 -- degrees per mouse-wheel notch
local DIAL_R = 52     -- knob orbit radius (px)

-- объявлена заранее: её зовёт createGhost (сеанс TouchPlace), а определена она в конце файла
local onPlaceClick

local ghost = nil
local placing = false
local currentName = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local rotationAngle = 0
local savedMinZoom, savedMaxZoom
local lastPlacedTool = nil

-- ── rotation dial UI ──
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local dialGui = new("ScreenGui", { Name = "BuildRotateDial", ResetOnSpawn = false, Enabled = false, DisplayOrder = 30 }, playerGui)
local dial = new("TextButton", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -110), Size = UDim2.fromOffset(132, 132),
	BackgroundColor3 = Color3.fromRGB(20, 24, 32), BackgroundTransparency = 0.35, Text = "", AutoButtonColor = false,
}, dialGui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, dial)
new("UIStroke", { Color = Color3.fromRGB(120, 170, 230), Thickness = 2, Transparency = 0.2 }, dial)
local readout = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 28),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "0°",
}, dial)
local knob = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = Color3.fromRGB(120, 200, 255), Text = "", AutoButtonColor = false,
}, dial)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
new("UIStroke", { Color = Color3.fromRGB(20, 40, 70), Thickness = 2 }, knob)
local hint = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(180, 18),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(210, 220, 235),
	Text = "Крути — угол   •   ЛКМ — поставить",
}, dial)


--[[ ⚠️ НА ТЕЛЕФОНЕ МЕСТО КРУГОВ БЕРЁМ У САМОЙ КНОПКИ СТРОЙКИ, А НЕ ПО ЧИСЛАМ.
     Две попытки развести их числами провалились, и обе одинаково: круги
     сперва наезжали на кнопку, потом улетели в угол экрана. Причина одна —
     числа врали. Отступы кнопки живут в её файле, её ScreenGui считает
     координаты БЕЗ полосы Roblox (IgnoreGuiInset), а поверх всего этого
     висел множитель, который на деле не применялся: UIScale был положен в
     ScreenGui, а он действует только внутри GuiObject.
     Поэтому больше не считаем, а СМОТРИМ: спрашиваем у кнопки её настоящие
     экранные координаты и встаём слева от неё, вровень по центру. Кнопку
     подвинут или переименуют — круги поедут за ней сами, а если её нет
     вовсе (не телефон, стройка не в режиме), останется прежний угол. ]]
local DIAL_GAP = 18

local function buildButtonFrame()
	local gui = playerGui:FindFirstChild("BuildingGui")
	if not (gui and gui:IsA("ScreenGui") and gui.Enabled) then return nil end
	local slot = gui:FindFirstChild("BuildSlot", true)
	if not (slot and slot:IsA("GuiObject") and slot.Visible) then return nil end
	if slot.AbsoluteSize.Y < 1 then return nil end
	return slot
end

do
	local ok, Hud = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale", 5))
	end)
	if ok and Hud and Hud.isPhone and Hud.isPhone() then
		--[[ ⚠️ ОБА ОКНА СЧИТАЮТ КООРДИНАТЫ ОДИНАКОВО.
		     У кнопки стройки IgnoreGuiInset = true: её AbsolutePosition отсчитан
		     от самого верха экрана, а не от нижней кромки полосы Roblox. Чтобы
		     ставить круги по её числам без поправок, включаем то же самое и у
		     себя — иначе они сядут ниже ровно на высоту полосы. ]]
		dialGui.IgnoreGuiInset = true

		local function placeDial()
			local slot = buildButtonFrame()
			--[[ ⚠️ КНОПКИ СТРОЙКИ МОЖЕТ НЕ БЫТЬ — пушка ставится не из режима
			     молотка, и BuildingGui в этот момент отсутствует. Раньше тогда
			     функция выходила, и диск оставался на своей ПК-позиции
			     (правый нижний угол) — ровно поверх кнопки стройки и прыжка.
			     Без кнопки ставим диск туда, где он стоял бы рядом с ней:
			     левее её столбца, на её высоте. ]]
			if not slot then
				dial.AnchorPoint = Vector2.new(1, 1)
				dial.Position = UDim2.new(1, -(184 + 132 + DIAL_GAP), 1, -190)
				return
			end
			local size = dial.AbsoluteSize
			if size.X < 1 then size = Vector2.new(132, 132) end
			dial.AnchorPoint = Vector2.new(0, 0)
			dial.Position = UDim2.fromOffset(
				slot.AbsolutePosition.X - DIAL_GAP - size.X,
				slot.AbsolutePosition.Y + (slot.AbsoluteSize.Y - size.Y) / 2)
		end

		--[[ Пересчитываем каждый кадр показа, а не один раз: кнопка стройки
		     появляется вместе с режимом стройки и живёт в своём ScreenGui, то
		     есть в момент загрузки её может не быть вовсе. Кадр стоит дёшево,
		     а «круги встали не туда, потому что мерили рано» — дорого. ]]
		RunService.RenderStepped:Connect(function()
			if dialGui.Enabled then placeDial() end
		end)
	end
end
local function updateDial()
	knob.Position = UDim2.new(0.5, math.cos(rotationAngle) * DIAL_R, 0.5, math.sin(rotationAngle) * DIAL_R)
	readout.Text = (math.floor(math.deg(rotationAngle) % 360 + 0.5)) .. "°"
end

-- ── ghost ──
-- ⚠️ findPrefix, а не find — иначе призрак собирался из одной детали крепления
-- турели вместо всей модели. Тот же случай, что на сервере (CanonSystem).
local function findTemplate(name)
	return AssetFind.findPrefix(name)
end

local function createGhost(templateName)
	if ghost then ghost:Destroy(); ghost = nil end
	local template = findTemplate(templateName)
	if not template then return end
	ghost = template:Clone()
	ghost.Name = "BuildGhost"
	if ghost:IsA("Model") then
		-- ⚠️ PrimaryPart НАДО СНЯТЬ, ИНАЧЕ WorldPivot НИЧЕГО НЕ ЗНАЧИТ.
		-- У модели с заданным PrimaryPart пивот — это сам PrimaryPart, а WorldPivot
		-- движок игнорирует. У пушек он стоит далеко от центра (ствол, лафет), и
		-- призрак вращался вокруг точки где-то в стороне, а по клику уезжал туда же:
		-- PivotTo ставит в точку прицела ПИВОТ, а не геометрию.
		-- Снимаем — и пивотом становится наш центр габарита.
		ghost.PrimaryPart = nil
		local bbCF = ghost:GetBoundingBox()
		ghost.WorldPivot = CFrame.new(bbCF.Position)
	end
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
		elseif part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		elseif part:IsA("ParticleEmitter") or part:IsA("Fire") or part:IsA("Smoke") or part:IsA("Sparkles") then
			part.Enabled = false
		end
	end
	ghost.Parent = workspace
	--[[ ⚠️ ПОМЕЧАЕМ ПРИЗРАК, ЧТОБЫ ЕГО НЕ ПРИНЯЛИ ЗА ПОСТРОЙКУ.
	     Призрак — полная копия модели, с тем же именем. Чужие системы ищут свои
	     объекты именно по имени и находили его: подсказка плавильни начиналась,
	     когда печь ещё в руках, а не на плоту. Метка стоит копейки и снимает
	     целый класс таких путаниц. ]]
	ghost:SetAttribute("PlacementGhost", true)

	--[[ ⚠️ СЕАНС УСТАНОВКИ НАЧИНАЕМ ЗДЕСЬ, А НЕ В ВЕТКАХ ЭКИПИРОВКИ.
	     Призрак создаётся ровно тогда, когда игрок взял любую из построек, —
	     одна точка вместо перечисления, и новая пушка получит телефонную схему
	     даром. Подтверждение определено ниже по файлу, поэтому зовём его через
	     обёртку: к моменту нажатия оно уже на месте.
	     rotate не передаём намеренно: поворот у построек живёт на циферблате, а
	     он с самого начала тянется пальцем (Touch в beginDrag) — вторая кнопка
	     поворота спорила бы с ним и урезала бы 360° до шагов. ]]
	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		-- призрак заслоняет палубу: без этого тап упирался бы в него самого
		ignore  = function() return ghost end,
	})
end

local function destroyGhost()
	if ghost then ghost:Destroy(); ghost = nil end
	lastGhostValid = false
	lastGhostRaftOffset = nil
	-- сеанс закончился: убрать кнопку телефона и забыть точку тапа
	TouchPlace.finish()
end

local function setGhostColor(valid)
	lastGhostValid = valid
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if ghost then
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then part.Color = color end
		end
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

--[[ ⚠️ ЧТО СЧИТАЕТСЯ ЗАНЯТОЙ КЛЕТКОЙ. СПИСОК ОДИН И ТОТ ЖЕ ВО ВСЕХ СТАВИЛКАХ.
     Здесь ИМЕНА МОДЕЛЕЙ В МИРЕ, а не имена тулов, и списки успели разъехаться:
     у каждой ставилки был свой, отставший на разное число построек. Грядка
     давно ставится моделью Raft_planter, кровать — Raft_bed_leaf, а монолита,
     ремонтной станции, плавильни и мангала-бочки не знал почти никто. Что не
     названо — то не «занято», поэтому мангал спокойно вставал в бочку с водой,
     а грядка — в монолит.
     Добавляя новую постройку, впиши её сюда — и во ВСЕ файлы разом (общий
     модуль под это завести нельзя: новый файл до запущенной сессии Rojo
     доезжает не всегда, на этом уже обожглись с постановкой). ]]
local PLACED_NAMES = {
	-- старые имена: часть моделей ещё встречается в сохранениях
	WorkBench = true, Purifier = true, Garden = true, Bed_T = true,
	Bed = true, Destitalor = true, bush = true, Sawmill = true,
	Furnace = true, FireCamp = true,
	-- нынешние модели построек плота
	Raft_planter = true, Raft_bed_leaf = true, Raft_smelter = true, Raft_scarecrow = true,
		Raft_chair = true, Raft_chair_leaf = true, Raft_table_leaves = true,   -- декор (DecorPlace)
	Raft_grill = true, Raft_grill_barrel = true, Raft_collector = true,
	-- переносимые: перекрывать их тоже нельзя
	Monolit_Aquamen = true, Raft_repair_station = true,
}

local function isPlacementBlocked(placeCF, ghostSize)
	local raft = workspace:FindFirstChild("Raft")
	if not raft then return true end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { ghost, player.Character }
	local parts = workspace:GetPartBoundsInBox(placeCF, ghostSize * 0.7, overlapParams)
	for _, part in parts do
		if part:IsDescendantOf(raft) then
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and (PLACED_NAMES[current.Name] or current.Name:sub(1, 10) == "Deffender_") then
					return true
				end
				current = current.Parent
			end
		end
	end
	return false
end

local function updateGhost()
	if not ghost then return end
	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then setGhostColor(false); return end
	-- прицел: на компьютере из курсора, на телефоне — в точку тапа (TouchPlace)
	local unitRay = TouchPlace.ray(mouse)
	-- телефон до первого тапа: целиться некуда — ведём себя как при промахе луча
	if not unitRay then setGhostColor(false); return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result or not result.Instance then setGhostColor(false); return end
	local hitOnRaft = result.Instance:IsDescendantOf(raft)
	local hitPos = result.Position
	local ghostSize = ghost:GetExtentsSize()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z) * CFrame.Angles(0, restYaw + rotationAngle, 0)
	ghost:PivotTo(placeCF)
	if hitOnRaft then
		lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
		setGhostColor(not isPlacementBlocked(placeCF, ghostSize))
	else
		setGhostColor(false)
	end
end

-- ── start / stop placing ──
local function startPlace(templateName, name)
	placing = true
	currentName = name
	rotationAngle = 0
	createGhost(templateName)
	updateDial()
	dialGui.Enabled = true
	-- lock zoom so the wheel rotates instead of zooming the camera
	savedMinZoom, savedMaxZoom = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local z = hrp and math.clamp((camera.CFrame.Position - hrp.Position).Magnitude, 4, 100) or 12
	player.CameraMinZoomDistance = z
	player.CameraMaxZoomDistance = z
end

local function stopPlace()
	placing = false
	currentName = nil
	destroyGhost()
	dialGui.Enabled = false
	if savedMinZoom then
		player.CameraMinZoomDistance = savedMinZoom
		player.CameraMaxZoomDistance = savedMaxZoom
		savedMinZoom, savedMaxZoom = nil, nil
	end
end

local function syncPlacing()
	local char = player.Character
	local equipped = char and char:FindFirstChildWhichIsA("Tool")
	if equipped ~= lastPlacedTool then lastPlacedTool = nil end -- the just-placed tool is gone now
	local templateName = equipped and BUILDINGS[equipped.Name]
	if templateName and not placing and equipped ~= lastPlacedTool then
		startPlace(templateName, equipped.Name)
	elseif (not templateName or equipped == lastPlacedTool) and placing then
		stopPlace()
	end
end

RunService.RenderStepped:Connect(function()
	syncPlacing()
	if placing and ghost then
		updateGhost()
		updateDial()
	end
end)

-- ── dial interaction (drag knob / rim) ──
local dragging = false
local function setAngleFromInput(pos)
	local c = dial.AbsolutePosition + dial.AbsoluteSize / 2
	local dx, dy = pos.X - c.X, pos.Y - c.Y
	if dx * dx + dy * dy > 9 then -- ignore tiny jitter at the centre
		rotationAngle = math.atan2(dy, dx)
		updateDial()
	end
end
local function beginDrag(input)
	if not placing then return end
	if GamepadInput.isPrimary(input) then
		dragging = true
		setAngleFromInput(input.Position)
	end
end
dial.InputBegan:Connect(beginDrag)
knob.InputBegan:Connect(beginDrag)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		setAngleFromInput(input.Position)
	elseif placing and input.UserInputType == Enum.UserInputType.MouseWheel then
		rotationAngle = rotationAngle + input.Position.Z * math.rad(WHEEL_STEP)
		updateDial()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if GamepadInput.isPrimary(input) then
		dragging = false
	end
end)

-- ── place (click / tap on the raft; ignored if the press was on the dial UI) ──
-- Тело общее: на компьютере его зовёт ЛКМ, на телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	if not placing or not ghost or not currentName then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end
	cupActionEvent:FireServer("placeBuilding", currentName, lastGhostRaftOffset)
	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
	local char = player.Character
	lastPlacedTool = char and char:FindFirstChildWhichIsA("Tool") -- don't re-arm until it's gone
	stopPlace() -- restores camera zoom + hides the dial
end

--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТАВИТ — ОН ВЫБИРАЕТ МЕСТО.
     Касание приходит сюда тем же InputBegan, что и ЛКМ, поэтому первый же тап
     ставил пушку по координатам ПРЕДЫДУЩЕГО касания: игрок ещё целился, а она
     уже стояла не там. Пока идёт сеанс установки, тап отдаём модулю (он двигает
     прицел), а ставит кнопка «ПОСТАВИТЬ». Условие про сеанс, а не про телефон
     вообще: без ставящегося тула в руках тап работает как прежде. ]]
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end -- press was consumed by UI (e.g. the dial)
	if GamepadInput.isPrimary(input) then
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
