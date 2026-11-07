local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- AnchorBuildSystem.client.lua
-- Standalone placement flow for the Anchor_part tool. Runs its own
-- ScreenGui, preview part, RenderStepped and click handler so it
-- can't conflict with BuildingSystem.client.lua's hammer state.
--
-- Uses the same grid math as the hammer (RestCFrame / rest-yaw,
-- nearest adjacent cell) so the anchor lands on the same integer
-- grid the raft tiles use; preview renders green when the chosen
-- cell is legal and red otherwise.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--[[ ⚠️ МОДУЛИ БЕРЁМ СО СРОКОМ ОЖИДАНИЯ, А НЕ «КОГДА-НИБУДЬ».
     Этот файл уже умирал именно так — ниже про Raft_part написано подробно:
     WaitForChild без срока ждёт вечно, и скрипт молча замирает ЦЕЛИКОМ. Ни
     призрака, ни постановки, а в логе одна строчка «Infinite yield possible»,
     которую легко не заметить среди прочего.
     Модуль AnchorRig я добавил сюда позже остальных, и он ровно такой же
     риск: в Studio он появляется только после того, как rojo доехал с новым
     файлом. Не доехал — раньше умерло бы всё, теперь просто предупреждаем и
     работаем без него: он нужен лишь для метки груза у СТАРОЙ модели.
     NetFit важнее — без него неоткуда взять уровень настила, — поэтому при
     его отсутствии призрак встаёт по старому правилу, а не исчезает. ]]
local function needModule(name)
	local inst = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:WaitForChild(name, 10)
	if not inst then
		warn(("[Стройка/якорь] в ReplicatedStorage нет модуля «%s» — работаю без "
			.. "него. Если это Studio: перезапусти rojo serve, файл не доехал.")
			:format(name))
		return nil
	end
	local ok, mod = pcall(require, inst)
	if not ok then
		warn(("[Стройка/якорь] модуль «%s» не загрузился: %s"):format(name, tostring(mod)))
		return nil
	end
	return mod
end

-- общий замер верха палубы: та же функция, что зовёт сервер
local NetFit = needModule("RaftNetFit")
local AnchorRig = needModule("AnchorRig")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local placeBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlock")

-- ⚠️ ШАБЛОН ИЩЕМ ПО ИМЕНИ, А НЕ ПО МЕСТУ.
-- Здесь стоял WaitForChild("Raft_part"). Когда модели разложили по папкам
-- (Buildings_Raft/Floor), прямого ребёнка с таким именем не стало — и скрипт
-- ЗАМЕР на этой строке навсегда: якорь просто перестал ставиться, а в логе была
-- только строчка «Infinite yield possible». Та же правка, что в BuildingSystem.
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))
local raftPartTemplate = AssetFind.wait(20, "Raft_part")
if not raftPartTemplate then
	warn("[Якорь] в ReplicatedStorage нет модели Raft_part (искал во всех папках) "
		.. "— установка якоря выключена")
	return
end

-- Resolved lazily so it picks up templates that land in
-- ReplicatedStorage after this LocalScript has loaded.
--[[ ⚠️ ЯКОРЯ ДВА: НОВАЯ ЛЕБЁДКА И СТАРАЯ РАМА.
     Рецепт теперь выдаёт Raft_anchor, но в мире может стоять и лежать в
     рюкзаке прежний Anchor_part. Этот файл ведёт ВЕСЬ предпросмотр и клик:
     не узнав имя тула, он молча ничего не делает — ровно то и вышло, когда
     рецепт переименовали, а сюда заглянуть забыли: предмет в руках есть,
     призрака нет, клик не ставит.
     Порядок в списке важен: первым идёт то, что ставим по умолчанию. ]]
local ANCHOR_NAMES = { "Raft_anchor", "Anchor_part" }

-- ⚠️ Найденный шаблон запоминаем: эту функцию зовёт и покадровый предпросмотр,
-- а FindFirstChild(name, true) — рекурсивный обход всего ReplicatedStorage.
-- Отрицательный ответ не кэшируем: модель может приехать позже нас.
local anchorTemplateCache = nil
local function getAnchorTemplate()
	if anchorTemplateCache and anchorTemplateCache.Parent then
		return anchorTemplateCache
	end
	anchorTemplateCache = nil
	for _, n in ipairs(ANCHOR_NAMES) do
		local t = ReplicatedStorage:FindFirstChild(n)
			or ReplicatedStorage:FindFirstChild(n, true)
		if t then
			anchorTemplateCache = t
			return t
		end
	end
	return nil
end

local function isAnchorTool(inst)
	if not (inst and inst:IsA("Tool")) then return false end
	for _, n in ipairs(ANCHOR_NAMES) do
		if inst.Name == n then return true end
	end
	return false
end
local PREVIEW_VALID    = Color3.fromRGB(80, 200, 80)
local PREVIEW_INVALID  = Color3.fromRGB(200, 80, 80)
local MAX_PLACE_RANGE  = 80   -- studs from player to candidate cell
local MAX_MOUSE_RAY    = 600

local GRID_SIZE = raftPartTemplate:GetAttribute("GridSize")
if not GRID_SIZE then
	if raftPartTemplate:IsA("Model") then
		local size = raftPartTemplate:GetExtentsSize()
		GRID_SIZE = math.max(size.X, size.Z)
	elseif raftPartTemplate:IsA("BasePart") then
		GRID_SIZE = math.max(raftPartTemplate.Size.X, raftPartTemplate.Size.Z)
	else
		GRID_SIZE = 6
	end
end

--[[ ⚠️ ПРИЗРАК МОЛЧА НЕ ПОЯВЛЯЕТСЯ — САМЫЙ ДОРОГОЙ ВИД ПОЛОМКИ.
     Причин ровно четыре: шаблона нет, плота нет, клетка занята (тогда мы
     прячем призрака НАМЕРЕННО) и слишком далеко от игрока. Снаружи все
     четыре выглядят одинаково — пустой экран, — и каждый раз это стоило
     круга «поставь-посмотри-расскажи».
     Поэтому причина печатается один раз на каждый заход в режим стройки:
     повторов в логе не будет, а первый же тест сразу говорит, куда смотреть. ]]
local sayOnce = {}
local function preview_log(key, fmt, ...)
	if sayOnce[key] then return end
	sayOnce[key] = true
	print("[Стройка/якорь] " .. string.format(fmt, ...))
end

local previewPart
local placing       = false
local touchAim      = nil          -- точка последнего тапа по миру (телефон)
local touchGui      = nil          -- кнопка «Построить» на телефоне
local renderConn
local lastGX, lastGZ
local lastValid     = false

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- Фаза сетки: дробное смещение изначального Raft_part от идеальной сетки.
-- СЕРВЕР (BuildingSystem) и превью молотка применяют её при расчёте позиции,
-- а превью якоря раньше НЕТ — из-за этого якорь ставился со сдвигом от зелёного
-- предпросмотра. Считаем так же, как сервер, чтобы превью = месту установки.
local function getGridPhase(raft, gridSize)
	local primary = raft and raft.PrimaryPart
	if not primary then return 0, 0 end
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child:GetAttribute("GridX") == nil then
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local lp = flatCF:PointToObjectSpace(pos)
				return lp.X - math.round(lp.X / gridSize) * gridSize,
					lp.Z - math.round(lp.Z / gridSize) * gridSize
			end
		end
	end
	return 0, 0
end

local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				return primary.CFrame:ToObjectSpace(tileCF).Rotation
			end
		end
	end
	return CFrame.new()
end

-- Same grid scan BuildingSystem.client.lua uses: attribute-tagged
-- tiles plus any initial Raft_part reprojected onto the rest-yaw
-- plane so wave tilt doesn't shift the grid.
local function getFloorOffsetMap()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return {} end

	local seen = {}
	local primary = raft.PrimaryPart
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	local function add(gx, gz)
		seen[gx .. "_" .. gz] = {x = gx, z = gz}
	end

	for _, child in raft:GetChildren() do
		local gx = child:GetAttribute("GridX")
		local gz = child:GetAttribute("GridZ")
		if gx and gz and child:GetAttribute("BuildType") == "raft" then
			add(gx, gz)
		elseif child.Name == "Raft_part" or child == primary then
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				add(math.round(localPos.X / GRID_SIZE), math.round(localPos.Z / GRID_SIZE))
			end
		end
	end
	if not seen["0_0"] then add(0, 0) end
	return seen
end

local function isOccupied(map, gx, gz)
	return map[gx .. "_" .. gz] ~= nil
end

local function isAdjacent(map, gx, gz)
	for _, cell in pairs(map) do
		if (math.abs(cell.x - gx) == 1 and cell.z == gz)
			or (math.abs(cell.z - gz) == 1 and cell.x == gx) then
			return true
		end
	end
	return false
end

-- Build the CFrame of the raw grid cell (no X compensation) so the
-- overlap check probes the cell itself instead of the anchor's
-- compensated body position — otherwise right-side placements
-- false-positive because the body shifts back toward the raft.
local function gridCellCF(raft, gx, gz)
	local primary = raft.PrimaryPart
	local restCF  = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restYaw = primary:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE + phaseX, 0, gz * GRID_SIZE + phaseZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return primary.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)
end

-- Reject placements whose grid cell physically intersects any raft
-- descendant — belt + suspenders on top of the grid adjacency check.
-- Probe size is one grid tile (shrunk a touch to ignore edges).
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local OVERLAP_PROBE_SIZE = Vector3.new(GRID_SIZE * 0.75, GRID_SIZE * 0.75, GRID_SIZE * 0.75)

local function overlapsRaft(raft, gx, gz)
	overlapParams.FilterDescendantsInstances = { raft }
	local cellCF = gridCellCF(raft, gx, gz)
	local parts = workspace:GetPartBoundsInBox(cellCF, OVERLAP_PROBE_SIZE, overlapParams)
	if previewPart then
		for _, p in parts do
			if not p:IsDescendantOf(previewPart) then return true end
		end
		return false
	end
	return #parts > 0
end

--[[ ⚠️ СДВИГ НА ДВА СТУДА — ЭТО ЛЕЧЕНИЕ СТАРОЙ МОДЕЛИ, А НЕ ОБЩЕЕ ПРАВИЛО.
     У Anchor_part PrimaryPart стоит в проёме A-образной рамы, в двух студах
     правее видимого центра, и PivotTo парковал тело мимо клетки. У новой
     лебёдки Raft_anchor пивот на месте, и тот же сдвиг увёл бы её с клетки —
     призрак стоял бы не там, куда встанет модель.
     ⚠️ Такое же ветвление есть на сервере (BuildingSystem, ветка anchor): они
     обязаны совпадать, иначе призрак и постройка разъедутся. ]]
local function pivotCompensationFor(template)
	if template and template.Name == "Anchor_part" then
		return CFrame.new(-2, 0, 0)
	end
	return CFrame.new()
end

--[[ ⚠️ ЛЕБЁДКУ РАЗВОРАЧИВАЕМ НА 90° ПО X — ТА ЖЕ БЕДА, ЧТО У СЕТИ.
     Модель приехала из FBX, и её пивот повёрнут: PivotTo кладёт лебёдку
     плашмя, как это было с Raft_collector (см. RaftNetFit, там поправка
     ровно такая же и по той же причине).
     Старый Anchor_part собирали в Studio, у него пивот нормальный — ему
     поправка не нужна, иначе он ляжет.
     ⚠️ ЧИСЛО ДУБЛИРУЕТСЯ У КЛИЕНТА И У СЕРВЕРА: призрак и постройка обязаны
     совпасть. Меняешь знак или ось — меняй в обоих местах.
     ⚠️ ЗНАК УЖЕ ПОДБИРАЛСЯ: при +90 лебёдка вставала развёрнутой ровно на 180°,
     поэтому здесь −90. Ось верная, трогать её не нужно. ]]
--[[ ⚠️ САЖАЕМ ЛЕБЁДКУ НИЗОМ РАМЫ, А НЕ НИЗОМ ГАБАРИТА.
     У модели из FBX пивот сидит не в основании, поэтому PivotTo по клетке
     ставит её в воздух. Первая попытка мерила общую габаритную коробку — и
     промахнулась ещё сильнее: в коробку входит ГРУЗ, висящий на тросе, он
     свисает ниже рамы, и «поставить низ коробки на клетку» означало поднять
     раму ровно на длину этого свеса.
     Поэтому груз из замера исключаем и ищем самую низкую точку остальных
     деталей. Число подбирать не нужно вовсе: правило переживёт и замену модели,
     и любой разворот.
     ⚠️ ТА ЖЕ ФУНКЦИЯ ЕСТЬ НА ДРУГОЙ СТОРОНЕ (призрак и постановка): разойдутся —
     призрак снова покажет не то, что встанет. ]]
-- ⚠️ Одно правило на всех: см. AnchorRig. Своя копия здесь уже расходилась
-- с серверной, и призрак садился не так, как встаёт постройка.
local function hangingPartOf(model)
	return AnchorRig and AnchorRig.hangingPart(model) or nil
end

local function lowestY(model, skip)
	local minY = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart")
			and not (skip and (d == skip or d:IsDescendantOf(skip))) then
			local c, sz = d.CFrame, d.Size
			-- деталь может быть повёрнута: мировую полувысоту берём проекцией её
			-- полуосей на вертикаль, а не половиной sz.Y
			local halfY = 0.5 * (math.abs(c.XVector.Y) * sz.X
				+ math.abs(c.YVector.Y) * sz.Y
				+ math.abs(c.ZVector.Y) * sz.Z)
			local bottom = c.Position.Y - halfY
			if not minY or bottom < minY then minY = bottom end
		end
	end
	return minY
end

--[[ ⚠️ ЛЕБЁДКУ СТАВИМ ПО ЕЁ СОБСТВЕННОЙ ДОСКЕ — ТАК ЖЕ, КАК СТАВИТСЯ СЕТЬ.
     Три предыдущие попытки подгоняли высоту (пивотом, низом габарита, низом
     без груза) и все три мазали: у модели в наборе ЕСТЬ своя доска настила
     (Raft_anchor_deck), и лебёдка должна встать так, чтобы эта доска легла
     ровно на место доски клетки — как ложится сеть, которая тоже приходит
     со своим настилом.
     Поэтому меряем смещение от пивота модели до центра ЕЁ доски и ставим
     модель так, чтобы это смещение попало в центр клетки. Высоту при этом
     подбирать не нужно вовсе: она следует из геометрии.
     Запасной путь — центр всей модели (как у сети): если доску переименуют,
     лебёдка встанет чуть иначе, но не улетит.
     ⚠️ ТА ЖЕ ФУНКЦИЯ ЕСТЬ НА ДРУГОЙ СТОРОНЕ (призрак и постройка). ]]
-- ⚠️ 0.1 СТУДА ВВЕРХ — ПОПРАВКА С ГЛАЗА, А НЕ ИЗ ГЕОМЕТРИИ.
-- По расчёту доска лебёдки ложится ровно на место доски клетки, но на глаз
-- она садилась на волосок ниже соседних досок и слегка резала их. Владелец
-- попросил «на 0.1 повыше» — это оно. Число мизерное и на сетку не влияет.
local ANCHOR_LIFT = 0.1
local ANCHOR_DECK_NAMES = { "Raft_anchor_deck", "Raft_anchor_Deck", "deck" }

local function anchorDeckDelta(template)
	if not template or not template:IsA("Model") then return Vector3.zero end
	local deckPart
	for _, n in ipairs(ANCHOR_DECK_NAMES) do
		local d = template:FindFirstChild(n, true)
		if d and d:IsA("BasePart") then deckPart = d break end
	end
	local ok, delta = pcall(function()
		if deckPart then
			return template:GetPivot():ToObjectSpace(deckPart.CFrame).Position
		end
		local bbCF = template:GetBoundingBox()
		return template:GetPivot():ToObjectSpace(bbCF).Position
	end)
	return ok and delta or Vector3.zero
end

local function seatOnCell(model, cf, groundY)
	if model:IsA("BasePart") then
		model.CFrame = cf
		return
	end
	model:PivotTo(cf)
	local minY = lowestY(model, hangingPartOf(model))
	if not minY then return end
	local target = groundY or cf.Position.Y
	model:PivotTo(model:GetPivot() + Vector3.new(0, target - minY, 0))
end

local function rotFixFor(template)
	if template and template.Name == "Raft_anchor" then
		return CFrame.Angles(math.rad(-90), 0, 0)
	end
	return CFrame.new()
end

--[[ ⚠️ ПРИЗРАК СЧИТАЕТ РОВНО ТО ЖЕ, ЧТО СЕРВЕР (ветка anchor в BuildingSystem).
     Два места, где они обязаны совпасть слово в слово: слагаемое уровня
     настила и опора модели — её собственная доска. Разойдётся любое — призрак
     снова покажет не то, что встанет. ]]
local function gridToWorldCF(raft, gx, gz)
	local primary = raft.PrimaryPart
	local restCF  = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restYaw = primary:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local tpl = getAnchorTemplate()
	local isWinch = tpl and tpl.Name == "Raft_anchor"
	-- ⚠️ Без NetFit слагаемое просто ноль: лебёдка встанет на уровень корпуса,
	-- как до правки высоты. Это заметно глазу, но лучше, чем мёртвый скрипт.
	local deckY = (isWinch and NetFit) and NetFit.deckCenterRestY(raft) or 0
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE + phaseX, 0, gz * GRID_SIZE + phaseZ))
		+ Vector3.new(0, deckY, 0)
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	local cellCF = primary.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)
		* pivotCompensationFor(tpl)
	if not isWinch then return cellCF end
	return CFrame.new(cellCF.Position + Vector3.new(0, ANCHOR_LIFT, 0))
		* (cellCF * rotFixFor(tpl)).Rotation * CFrame.new(-anchorDeckDelta(tpl))
end

-- Cursor → grid coord. Project mouse ray onto the raft plane, then
-- convert to integer grid. Returns nil outside a valid range.
local function getFloorGridFromMouse()
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return nil end
	local primary = raft.PrimaryPart

	-- ⚠️ НА ТЕЛЕФОНЕ ЦЕЛИМСЯ ТОЧКОЙ ПОСЛЕДНЕГО ТАПА, А НЕ «МЫШЬЮ».
	-- Та же договорённость, что у молотка (_G.BuildAim): палец с экрана уходит,
	-- и mouse.X/Y замирают где попало — призрак уезжал бы под кнопку «Построить».
	local ax, ay = mouse.X, mouse.Y
	if touchAim then ax, ay = touchAim.x, touchAim.y end
	local unitRay = camera:ViewportPointToRay(ax, ay)
	local origin, direction = unitRay.Origin, unitRay.Direction
	if math.abs(direction.Y) < 1e-4 then return nil end
	local t = (primary.Position.Y - origin.Y) / direction.Y
	if t <= 0 or t > MAX_MOUSE_RAY then return nil end
	local hit = origin + direction * t

	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local restFlat = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)
	local localHit = restFlat:PointToObjectSpace(hit)
	local gx = math.round(localHit.X / GRID_SIZE)
	local gz = math.round(localHit.Z / GRID_SIZE)
	return gx, gz
end

local function colourPreview(valid)
	lastValid = valid
	if not previewPart then return end
	local c = valid and PREVIEW_VALID or PREVIEW_INVALID
	if previewPart:IsA("Model") then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then d.Color = c end
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.Color = c
	end
end

local function setPreviewVisible(visible)
	if not previewPart then return end
	local alpha = visible and 0.5 or 1
	if previewPart:IsA("Model") then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then d.Transparency = alpha end
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.Transparency = alpha
	end
end

local function applyPreviewAppearance()
	if not previewPart then return end
	local function prep(p)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Transparency = 0.5
	end
	if previewPart:IsA("Model") then
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then prep(d) end
		end
	elseif previewPart:IsA("BasePart") then
		prep(previewPart)
	end
end

-- The Anchor_part template ships with RopeConstraint, HingeConstraint,
-- WeldConstraint and Motor6D instances that drive the rigged anchor and
-- wheel. On a hologram clone they serve no purpose, and any physics
-- systems the raft runs (buoyancy, waves) can still feed energy into
-- the preview's assembly through them — which is what was producing
-- the bouncing raft while the anchor tool was held. Strip every
-- physics-active instance so the preview is pure geometry.
local PHYSICS_CLASSES = {
	"RopeConstraint", "HingeConstraint", "WeldConstraint", "Weld",
	"Motor6D", "Motor", "SpringConstraint", "RodConstraint",
	"BallSocketConstraint", "CylindricalConstraint", "PrismaticConstraint",
	"UniversalConstraint", "LineForce", "Torque", "VectorForce",
	"AlignOrientation", "AlignPosition", "AngularVelocity",
	"BodyVelocity", "BodyAngularVelocity", "BodyForce", "BodyGyro",
	"BodyPosition", "BodyThrust", "BodyMover",
	"Humanoid", "VehicleSeat", "Seat",
}

local function stripPhysicsInstances(model)
	for _, d in model:GetDescendants() do
		for _, className in PHYSICS_CLASSES do
			if d:IsA(className) then
				d:Destroy()
				break
			end
		end
	end
end

local function createPreview()
	local anchorTemplate = getAnchorTemplate()
	if previewPart then previewPart:Destroy() end
	if not anchorTemplate then
		warn("[AnchorBuildSystem] Anchor_part missing in ReplicatedStorage")
		return
	end
	previewPart = anchorTemplate:Clone()
	previewPart.Name = "AnchorPreview"
	-- Strip any baked scripts so they can't run on the ghost.
	for _, d in previewPart:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	-- Kill every constraint/mover so the rigged anchor (rope) and wheel
	-- (hinge/motor) don't participate in physics while the preview is
	-- parented in workspace.
	-- ⚠️ Груз помечаем ДО снятия констрейнтов: сразу после stripPhysicsInstances
	-- родителя троса уже не вычислить, а посадка на клетку должна его исключать —
	-- иначе призрак сядет выше постройки ровно на длину свеса.
	local hang = AnchorRig and AnchorRig.hangingPart(previewPart)
	if hang and hang:IsA("BasePart") then hang:SetAttribute("AnchorHang", true) end
	stripPhysicsInstances(previewPart)
	-- Anchor's Z matches a regular raft tile exactly — only the X is
	-- offset because of the hollow centre, and gridToWorldCF already
	-- applies the -2 stud X compensation. No WorldPivot rework here.
	applyPreviewAppearance()
	-- Park offscreen until the first RenderStepped tick places it on
	-- a legal cell.
	if previewPart:IsA("Model") then
		previewPart:PivotTo(CFrame.new(0, -10000, 0))
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = CFrame.new(0, -10000, 0)
	end
	-- Parent under the local Camera instead of workspace: Camera-rooted
	-- parts render normally but are invisible to the physics engine,
	-- buoyancy probes and server replication, so the preview truly
	-- behaves as a hologram.
	previewPart.Parent = camera
end

local function destroyPreview()
	if previewPart then previewPart:Destroy(); previewPart = nil end
	lastValid = false
	lastGX, lastGZ = nil, nil
end

local function movePreviewToCell(raft, gx, gz)
	local worldCF = gridToWorldCF(raft, gx, gz)
	if previewPart:IsA("Model") then
		-- призрак садится по тем же правилам, что и постройка
		if previewPart.Name == "AnchorPreview"
			and (getAnchorTemplate() and getAnchorTemplate().Name == "Raft_anchor") then
			-- высоту подбирать не нужно: gridToWorldCF уже вернул кадр, в котором
			-- собственная доска лебёдки ложится на место доски клетки
			previewPart:PivotTo(worldCF)
		else
			previewPart:PivotTo(worldCF)
		end
	elseif previewPart:IsA("BasePart") then
		previewPart.CFrame = worldCF
	end
end

local function updatePreview()
	if not previewPart then return end
	local raft = getRaft()
	if not raft or not raft.PrimaryPart then
		preview_log("noraft", "призрака не видно: плот не найден")
		lastValid, lastGX, lastGZ = false, nil, nil
		return
	end

	local gx, gz = getFloorGridFromMouse()
	if not gx then
		-- Fall back to the legal cell closest to the player so the
		-- ghost doesn't teleport to weird spots when the cursor is
		-- over sky / open ocean.
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			lastValid, lastGX, lastGZ = false, nil, nil
			return
		end
		local primary = raft.PrimaryPart
		local restYaw = primary:GetAttribute("RestYaw")
		if not restYaw then
			local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
			restYaw = yaw
		end
		local restFlat = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)
		local localHrp = restFlat:PointToObjectSpace(hrp.Position)
		gx = math.round(localHrp.X / GRID_SIZE)
		gz = math.round(localHrp.Z / GRID_SIZE)
	end

	local map = getFloorOffsetMap()
	lastGX, lastGZ = gx, gz

	-- Hide the preview entirely when the cursor is over a cell that's
	-- already filled by a known raft tile. Physical overlap is still
	-- checked below as an extra red-colour gate, not a hide gate —
	-- the overlap probe was false-positiving and keeping the ghost
	-- off-screen whenever the player picked up the anchor tool.
	if isOccupied(map, gx, gz) then
		-- это НЕ поломка: лебёдка приносит свою доску и встаёт на пустую клетку
		preview_log("occupied", "призрак спрятан: клетка (%d, %d) уже занята — "
			.. "целься на свободную рядом с плотом", gx, gz)
		setPreviewVisible(false)
		lastValid = false
		return
	end
	setPreviewVisible(true)

	movePreviewToCell(raft, gx, gz)
	if previewPart:IsA("Model") then
		local pv = previewPart:GetPivot().Position
		preview_log("placed", "призрак показан на клетке (%d, %d), он в %.1f студах "
			.. "от плота", gx, gz, (pv - raft.PrimaryPart.Position).Magnitude)
	end

	if not isAdjacent(map, gx, gz) then
		colourPreview(false)
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local worldCF = gridToWorldCF(raft, gx, gz)
		if (hrp.Position - worldCF.Position).Magnitude > MAX_PLACE_RANGE then
			colourPreview(false)
			return
		end
	end

	colourPreview(true)
end

local closeBuildMode   -- определяется ниже (после кнопки телефона)
local function startBuildMode()
	if placing then return end
	placing = true
	sayOnce = {}   -- новый заход — новая порция объяснений
	createPreview()
	if previewPart then
		local n = 0
		for _, d in previewPart:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
		end
		preview_log("made", "призрак создан: шаблон «%s», деталей %d",
			getAnchorTemplate() and getAnchorTemplate().Name or "?", n)
	else
		preview_log("made", "призрак НЕ создан: шаблона нет в ReplicatedStorage")
	end
	renderConn = RunService.RenderStepped:Connect(updatePreview)
	touchAim = nil
	showTouchButton()
end

-- ⚠️ ПОСТАНОВКА ВЫНЕСЕНА: её зовут ЛКМ на компьютере и кнопка на телефоне.
local function placeNow()
	if not placing then return end
	if not lastValid or not lastGX or not lastGZ then return end
	placeBlockEvent:FireServer("anchor", lastGX, lastGZ)
	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
	closeBuildMode()
end

-- ⚠️ НА ТЕЛЕФОНЕ НЕТ ЛКМ — НУЖНА КНОПКА, КАК У МОЛОТКА.
-- Якорь ставится своим инструментом, мимо панели молотка, и его кнопка
-- «Построить» здесь не появлялась: с телефона якорь было не поставить вовсе.
-- Кнопка та же по виду и месту, что в BuildingSystem.client (круглая, над
-- «прыжком»), чтобы палец находил её там же. Тап по миру — прицел, кнопка — ставит.
local function showTouchButton()
	if touchGui then return end
	if not (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then return end
	touchGui = Instance.new("ScreenGui")
	touchGui.Name = "AnchorBuildGui"
	touchGui.ResetOnSpawn = false
	touchGui.IgnoreGuiInset = true
	touchGui.DisplayOrder = 21
	touchGui.Parent = player:WaitForChild("PlayerGui")
	local slot = Instance.new("Frame")
	slot.AnchorPoint = Vector2.new(1, 1)
	slot.Position = UDim2.new(1, -184, 1, -190)   -- как BuildSlot в молотке
	slot.Size = UDim2.fromOffset(132, 132)
	slot.BackgroundTransparency = 1
	slot.Parent = touchGui
	local btn = Instance.new("ImageButton")
	btn.Name = "BuildNow"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = false
	btn.Image = "rbxassetid://116668456372183"   -- та же картинка, что у молотка
	btn.ImageTransparency = 0.25
	btn.ScaleType = Enum.ScaleType.Fit
	btn.Parent = slot
	-- Activated, а не MouseButton1Click: второе на телефоне не срабатывает
	btn.Activated:Connect(placeNow)
end

local function hideTouchButton()
	if touchGui then touchGui:Destroy(); touchGui = nil end
end

closeBuildMode = function()
	placing = false
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	destroyPreview()
	hideTouchButton()
end

local function onToolEquipped(tool)
	if not isAnchorTool(tool) then return end
	startBuildMode()
end

local function onToolUnequipped(tool)
	if tool and not isAnchorTool(tool) then return end
	closeBuildMode()
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then onToolEquipped(c) end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then onToolUnequipped(c) end
	end)
	for _, c in char:GetChildren() do
		if isAnchorTool(c) then
			onToolEquipped(c)
			break
		end
	end
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then closeBuildMode() end
	end)
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

local function playPlaceSound()
	local folder = (SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true))
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not placing then return end
	-- тап по миру на телефоне = прицел; ставит кнопка
	if input.UserInputType == Enum.UserInputType.Touch then
		touchAim = { x = input.Position.X, y = input.Position.Y }
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	touchAim = nil
	placeNow()
end)