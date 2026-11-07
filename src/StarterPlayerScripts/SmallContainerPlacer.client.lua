local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- SmallContainerPlacer.client.lua
-- Ghost preview + placement click for the SmallContainer tool. Follows
-- the exact pattern the WorkBench placement uses in
-- StarterPlayerScripts/CupPurifier.client.lua — only the tool name,
-- template lookup, and server action differ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))
local camera = workspace.CurrentCamera

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

--[[ ⚠️ ПОСТАНОВКА НА ТЕЛЕФОНЕ ИДЁТ ЧЕРЕЗ ОБЩИЙ МОДУЛЬ.
     Контейнер целится тем же лучом из курсора, что и остальные ставилки, а
     курсора на телефоне нет: там прицел даёт тап, подтверждает кнопка. Вся
     механика лежит в TouchPlace, здесь только три точки подключения — луч,
     начало сеанса и конец. На компьютере модуль не делает ничего. ]]
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

local TEMPLATE_NAME = "Container_empty"
local TOOL_NAME = "SmallContainer"
local ACTION_NAME = "placeSmallContainer"

-- объявлены заранее: их зовёт createGhost, а определены они ниже по файлу
local onPlaceClick, rotatePlacement

local ghost = nil
local placing = false
local currentTool = nil
local lastGhostValid = false
local lastGhostRaftOffset = nil
local rotationAngle = 0
local ghostTemplateRotation = CFrame.new()

local function findTemplate()
	local folder = ReplicatedStorage:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild(TEMPLATE_NAME)
	if not tmpl then
		tmpl = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME, true)
	end
	return tmpl
end

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = findTemplate()
	if not template then return end

	ghost = template:Clone()
	ghost.Name = "SmallContainerGhost"

	-- Reset WorldPivot to bounding box center with identity rotation —
	-- exactly what CupPurifier.client.lua does for WorkBench / Furnace /
	-- Destitalor / Bed / Garden / Sawmill (every non-bush placeable).
	local bbCF = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)
	ghostTemplateRotation = CFrame.new()

	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.Color = Color3.fromRGB(80, 255, 80)
		end
		if part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	ghost.Parent = workspace
	--[[ ⚠️ ПОМЕЧАЕМ ПРИЗРАК, ЧТОБЫ ЕГО НЕ ПРИНЯЛИ ЗА ПОСТРОЙКУ.
	     Призрак — полная копия модели, с тем же именем. Чужие системы ищут свои
	     объекты именно по имени и находили его: подсказка плавильни начиналась,
	     когда печь ещё в руках, а не на плоту. Метка стоит копейки и снимает
	     целый класс таких путаниц. ]]
	ghost:SetAttribute("PlacementGhost", true)

	--[[ ⚠️ СЕАНС УСТАНОВКИ НАЧИНАЕМ ЗДЕСЬ, У ПРИЗРАКА.
	     Призрак появляется ровно в тот момент, когда игрок взял контейнер, —
	     значит и кнопкам телефона самое время появиться вместе с ним.
	     Функции подтверждения и поворота определены ниже по файлу, поэтому
	     зовём их через обёртки: к моменту нажатия они уже на месте. ]]
	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		rotate  = function() if rotatePlacement then rotatePlacement() end end,
		-- призрак заслоняет палубу: без этого тап упирался бы в него самого
		ignore  = function() return ghost end,
	})
end

local function destroyGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	lastGhostValid = false
	lastGhostRaftOffset = nil
	-- сеанс установки закончился: убрать кнопки телефона и забыть точку тапа
	TouchPlace.finish()
end

local function setGhostColor(valid)
	lastGhostValid = valid
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	if ghost then
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = color
			end
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

	local checkSize = ghostSize * 0.7
	local parts = workspace:GetPartBoundsInBox(placeCF, checkSize, overlapParams)

	for _, part in parts do
		if part:IsDescendantOf(raft) then
			local current = part
			while current and current ~= raft do
				if current:IsA("Model") and PLACED_NAMES[current.Name] then
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
	if not raft or not raft.PrimaryPart then
		setGhostColor(false)
		return
	end

	-- Луч прицела: на компьютере из курсора, на телефоне — в точку тапа (TouchPlace)
	local unitRay = TouchPlace.ray(mouse)
	if not unitRay then
		-- телефон, места ещё не выбрали: показывать призрак негде
		setGhostColor(false)
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result or not result.Instance then
		setGhostColor(false)
		return
	end

	local hitOnRaft = result.Instance:IsDescendantOf(raft)
	local hitPos = result.Position
	local ghostSize = ghost:GetExtentsSize()
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0

	-- Identical formula to WorkBench / Furnace / Bed / Sawmill placement
	-- in CupPurifier.client.lua. No extra axis flips — if the model sits
	-- the way it was authored, it will sit the same way on the raft.
	local placeCF = CFrame.new(hitPos.X, hitPos.Y + ghostSize.Y / 2, hitPos.Z)
		* CFrame.Angles(0, restYaw + rotationAngle, 0)
		* ghostTemplateRotation

	ghost:PivotTo(placeCF)

	if hitOnRaft then
		lastGhostRaftOffset = raft.PrimaryPart.CFrame:ToObjectSpace(placeCF)
		local blocked = isPlacementBlocked(placeCF, ghostSize)
		setGhostColor(not blocked)
	else
		setGhostColor(false)
	end
end

local function onToolEquipped(tool)
	currentTool = tool
	if tool.Name == TOOL_NAME then
		placing = true
		rotationAngle = 0
		createGhost()
	end
end

local function onToolUnequipped(tool)
	if tool and tool.Name == TOOL_NAME then
		placing = false
		destroyGhost()
	end
	if currentTool == tool then
		currentTool = nil
	end
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolUnequipped(child)
		end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if placing and ghost then
		updateGhost()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Only block R when an actual TextBox has the focus (chat, search
	-- field, etc.). The broader `gameProcessed` guard was also true
	-- when any GUI element claimed the keyboard for *other* reasons,
	-- which broke ghost rotation after the workbench's Search TextBox
	-- entered the focus chain.
	if UserInputService:GetFocusedTextBox() then return end
	if GamepadInput.isKey(input, Enum.KeyCode.R) and placing then
		rotatePlacement()
	end
end)

-- поворот на четверть — общий для клавиши R и для экранной кнопки на телефоне
function rotatePlacement()
	rotationAngle = rotationAngle + math.rad(90)
end

-- Тело общее: на компьютере его зовёт ЛКМ, на телефоне — кнопка «ПОСТАВИТЬ».
function onPlaceClick()
	if not placing or not ghost then return end
	if not lastGhostValid or not lastGhostRaftOffset then return end

	cupActionEvent:FireServer(ACTION_NAME, lastGhostRaftOffset)

	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end

	destroyGhost()
	placing = false
end

--[[ ⚠️ НА ТЕЛЕФОНЕ ТАП НЕ СТАВИТ — ОН ВЫБИРАЕТ МЕСТО.
     Roblox превращает касание экрана в тот же Button1Down, поэтому раньше первый
     же тап мгновенно ставил контейнер по координатам ПРЕДЫДУЩЕГО касания: игрок
     ещё целился, а вещь уже стояла не там. Пока идёт сеанс установки, тап отдаём
     модулю (он двигает прицел), а ставит кнопка «ПОСТАВИТЬ». ]]
GamepadInput.onPrimary(mouse, function()
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
end)
