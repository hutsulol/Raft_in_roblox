local rs = game:GetService("ReplicatedStorage")

local placeBlockEvent = rs:FindFirstChild("PlaceBlock")
if not placeBlockEvent then
	placeBlockEvent = Instance.new("RemoteEvent")
	placeBlockEvent.Name = "PlaceBlock"
	placeBlockEvent.Parent = rs
end

-- ШАБЛОН ПО НЕСКОЛЬКИМ ИМЁНАМ. Модели плота переименовывались (стена стала
-- raft_wall вместо wall_model_wood), и жёсткое имя молча давало nil — стройка
-- подставляла запасной шаблон, из-за чего вместо стены вставала плита пола.
-- ⚠️ ШАБЛОНЫ ИЩЕМ ПО ИМЕНИ, А НЕ ПО МЕСТУ (AssetFind).
-- Модели в хранилище раскладывают по папкам, и прямое FindFirstChild от этого
-- ломается. Особенно скверно у WaitForChild: скрипт не падает, а молча висит.
local AssetFind = require(rs:WaitForChild("AssetFind"))
local RaftShake = require(rs:WaitForChild("RaftShake"))
local findTemplateNamed = AssetFind.find

-- УКРЕПЛЕНИЕ ПОЛА: меш/текстура и правила лежат в общем модуле, чтобы сервер,
-- клиент и загрузка сейва делали одно и то же.
local RaftReinforce = require(rs:WaitForChild("RaftReinforce"))

local raftPartTemplate = AssetFind.wait(20, "Raft_part")
if not raftPartTemplate then
	warn("[BuildingSystem] в ReplicatedStorage нет модели Raft_part "
		.. "(искал во всех папках) — стройка выключена")
	return
end
-- Имена, поворот и имя поставленной клетки — в общем модуле: раньше поправка
-- поворота лежала числом в трёх файлах сразу (см. RaftNetFit).
local NetFit = require(rs:WaitForChild("RaftNetFit"))
local AnchorRig = require(rs:WaitForChild("AnchorRig"))
local netTemplate = AssetFind.find(table.unpack(NetFit.TEMPLATE_NAMES))
local beamTemplate = AssetFind.find("beam")
local wallPanelTemplate = findTemplateNamed("raft_wall", "Raft_wall", "wall_model_wood")
local wallArchTemplate = findTemplateNamed("raft_wall_arch", "Raft_wall_arch", "wall_model_wood_arch")
local doorTemplate = findTemplateNamed("raft_door", "Raft_door", "Door_Wood")

-- Варианты стен, их цены и общая просадка по высоте — в общем модуле: те же
-- числа читают превью на клиенте и загрузка сейва (см. RaftWallDefs).
local WallDefs = require(rs:WaitForChild("RaftWallDefs"))
local UpperFloor = require(rs:WaitForChild("RaftUpperFloor"))   -- пол второго этажа: общие правила
local FarmPropRules = require(rs:WaitForChild("FarmPropRules"))   -- клетки фермы и дома фермера: стен не строить

-- ⚠️ ВАРИАНТЫ СТЕН ВЫНОСИМ ИЗ ЧУЖОГО ШАБЛОНА.
-- Новые модели (лист, полулист, окно, полустена) приехали ВЛОЖЕННЫМИ в
-- raft_wall. Пока они там, обычная стена — это стена ВМЕСТЕ С НИМИ: клон тащит
-- их за собой, и на ребре вырастают пять построек разом. Поднимаем их в корень
-- ReplicatedStorage один раз при запуске — тот же приём, что с моделями, которые
-- заказчик кладёт прямо на карту (кровать, бутылка, осьминог).
local function liftTemplate(t, host)
	if t and host and t:IsDescendantOf(host) then
		t.Parent = rs
		print(("[Стройка] шаблон %s вынут из %s в ReplicatedStorage")
			:format(t.Name, host.Name))
	end
end
for _, def in pairs(WallDefs.EdgeWalls) do
	local t = WallDefs.findModel(rs, def.names)
	liftTemplate(t, wallPanelTemplate)
	liftTemplate(t, wallArchTemplate)
end
if not wallPanelTemplate then
	warn("[BuildingSystem] шаблон стены не найден в ReplicatedStorage "
		.. "(ищу raft_wall / Raft_wall / wall_model_wood) — стены не поставить")
end

-- Deck grid spacing in studs. НОВЫЙ ПЛОТ (переделка моделей): Raft_part ровно
-- 10x2.3x10, масштаб модели 1, origin без поворотов, пивот в центре тайла.
-- HARDCODED on purpose so the server and the client preview use the EXACT same
-- value — measuring it at runtime desynced the client (it loads before the raft
-- streams in). Keep EQUAL to the client copy (BuildingSystem.client.lua).
local GRID_SIZE = 10
raftPartTemplate:SetAttribute("GridSize", GRID_SIZE)

-- Шаблон Raft_part теперь СРАЗУ размером с клетку (10 студов) — масштабировать
-- нечего. Держать равным клиентской копии.
local TILE_SCALE = 1
-- Балки остались от старого плота (решётка 9.8428) — дотягиваем до новой
-- клетки: 1.26 * 10 / 9.8428 ≈ 1.28. Walls are NOT scaled.
local BEAM_SCALE = 1.28

-- Смещение ЦЕНТРА модели относительно её ПИВОТА (в осях пивота).
-- У Raft_part пивот сидит НЕ в центре тайла (сдвинут ~2 студа), у Net_Part — ровно
-- в центре. Клетка считается «под пивот доски», поэтому сеть по тому же CFrame
-- уезжала на величину этого смещения. Приводим обе к ЦЕНТРУ клетки.
-- ДЕРЖАТЬ РАВНЫМ клиентской копии (BuildingSystem.client.lua).
local function pivotCenterDelta(template, scale)
	if not template or not template:IsA("Model") then return Vector3.zero end
	local ok, delta = pcall(function()
		local bbCF = template:GetBoundingBox()
		return template:GetPivot():ToObjectSpace(bbCF).Position
	end)
	return ok and (delta * (scale or 1)) or Vector3.zero
end
local RAFT_PIVOT_DELTA = pivotCenterDelta(raftPartTemplate, TILE_SCALE)
local NET_PIVOT_DELTA  = pivotCenterDelta(netTemplate, 1)

-- Measure beam dimensions
local BEAM_HEIGHT = 0
local BEAM_FOOTPRINT = 0
if beamTemplate then
	if beamTemplate:IsA("Model") then
		local size = beamTemplate:GetExtentsSize()
		BEAM_HEIGHT = size.Y
		BEAM_FOOTPRINT = math.max(size.X, size.Z)
	elseif beamTemplate:IsA("BasePart") then
		BEAM_HEIGHT = beamTemplate.Size.Y
		BEAM_FOOTPRINT = math.max(beamTemplate.Size.X, beamTemplate.Size.Z)
	end
end
local BEAM_INSET = BEAM_FOOTPRINT / 2
raftPartTemplate:SetAttribute("BeamHeight", BEAM_HEIGHT)
raftPartTemplate:SetAttribute("BeamInset", BEAM_INSET)

-- Высоты меряем ОБЩИМ замером (RaftWallDefs.heightOf) — тем же, что у превью и у
-- загрузки сейва. Он считает только собственную геометрию шаблона: вложенные
-- модели раздували габарит, и превью вставало выше постановки.
local PANEL_HEIGHT = WallDefs.heightOf(wallPanelTemplate)
raftPartTemplate:SetAttribute("PanelHeight", PANEL_HEIGHT)

local ARCH_HEIGHT = WallDefs.heightOf(wallArchTemplate)
raftPartTemplate:SetAttribute("ArchHeight", ARCH_HEIGHT)

-- Шаблоны и высоты вариантов стен собираем из общего списка (RaftWallDefs): там
-- же цены и просадка, и оттуда их читают превью на клиенте и загрузка сейва.
-- Атрибуты высоты им не пишем намеренно: клиент меряет те же модели сам, а
-- атрибуты переживают сохранение плейса и устаревают при смене модели.
local EDGE_WALLS = {}
for kind, def in pairs(WallDefs.EdgeWalls) do
	local t = WallDefs.findModel(rs, def.names)
	EDGE_WALLS[kind] = { template = t, height = WallDefs.heightOf(t), costs = def.costs }
end

local DOOR_HEIGHT = WallDefs.heightOf(doorTemplate)
raftPartTemplate:SetAttribute("DoorHeight", DOOR_HEIGHT)

-- Beam/wall X-axis correction (pivot offset in template)
local BEAM_X_OFFSET = 1

-- Fine-tune for the FLOOR tile only (studs, raft-local X/Z), on top of the
-- auto-measured grid + phase. The grid already lines one axis up; nudge the
-- other here until the tile sits flush with the deck. Must stay identical to the
-- client copy. Updates live on save — flip sign or move to the other axis as needed.
local FLOOR_FINE_X = 0
local FLOOR_FINE_Z = 0

--[[ ⚠️ ПОЛ СТОИТ ТРЁХ РЕСУРСОВ, А НЕ ОДНИХ БРЁВЕН.
     Клетка пола — самая частая покупка в игре, и на одном дереве она была почти
     бесплатной: море подаёт около восьми брёвен в минуту, то есть плот рос
     быстрее, чем игрок успевал его заполнять. Пластик и верёвка добавлены
     затем, чтобы расширение конкурировало с остальной снарягой: пластик тот же,
     что идёт на кружку и очиститель, верёвка — это четыре листа.
     ⚠️ ЦЕНА ПРОДУБЛИРОВАНА У КЛИЕНТА: BuildingSystem.client.lua, пункт «Raft
     Floor» (поле costs). Разойдутся — меню покажет одно, а спишется другое.
     Подсказка квеста расширения (Quests/RaftQuestHint.client.lua, FLOOR_LOG_COST)
     считает только брёвна: она ведёт игрока к первой клетке и про остальное
     молчит намеренно. ]]
local RAFT_COSTS = { Log = 2, Plastic = 2, Rope = 1 }
--[[ ⚠️ ЯКОРЬ СТАВИТСЯ КРАФТОВЫМ ПРЕДМЕТОМ, А НЕ МОЛОТКОМ.
     Ветка молотка тут была и убрана: владелец попросил оставить якорь в
     инвентаре, как было раньше, — крафтишь предмет, берёшь в руки, ставишь.
     Новая модель Raft_anchor просто заменила собой старую Anchor_part в той же
     ветке anchor ниже. ]]
local ANCHOR_MODELS = { "Raft_anchor", "Anchor_part" }
local BEAM_COST = 1
local WALL_PANEL_COST = 3
local WALL_ARCH_COST = 3
local DOOR_COST = 2
-- СЕТЬ (Net_Part) — тот же тайл пола, что и Raft_part: та же сетка, то же
-- соседство, тот же размер. Отличие: стоит верёвку, а не брёвна.
local NET_COST = 2
local NET_COST_ITEM = "Rope"
-- Поправка поворота сети теперь МЕРИТСЯ по самому шаблону, а не задаётся числом:
-- смена модели на Raft_collector положила сеть на ребро именно потому, что
-- константа осталась от старой модели. Подробности и ручка SPIN_Y — в RaftNetFit.
local NET_ROT_FIX = NetFit.rotFix(netTemplate)

local function getRaft()
	return workspace:FindFirstChild("Raft")
end

-- ─── Grid lattice phase ───
-- The build grid's origin is the raft's PrimaryPart. If that part (often the
-- SpawnLocation) is not centred on a Raft_part tile — which happens when the
-- raft model is edited in Studio and the PrimaryPart drifts a fraction of a
-- cell — every tile reads at a fractional grid coord, so rounding misreads
-- existing tiles AND places new builds offset by that fraction. We snap the
-- grid origin back onto the real tile lattice by measuring the fractional
-- offset of an initial Raft_part tile and correcting for it everywhere.
-- Returns (0, 0) when the PrimaryPart is already aligned, so correctly built
-- rafts are completely unaffected.
local function getGridPhase(raft, gridSize)
	local primary = raft and raft.PrimaryPart
	if not primary then return 0, 0 end
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0)

	-- ГОЛОСОВАНИЕ БОЛЬШИНСТВОМ, как в getTileRotationCorrection. По «первой
	-- попавшейся» доске нельзя: криво поставленный в прошлых сессиях тайл (или
	-- другой порядок детей на клиенте) даёт превью и серверу РАЗНУЮ фазу — доска
	-- ставится со сдвигом относительно призрака. Фаза каждой доски приводится к
	-- канону (-g/2, g/2] с круговой корзиной, чтобы решётка с фазой у края не
	-- расщепляла голоса. (Держать равным копиям в клиенте и RaftSaveSystem.)
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" then
			local pos
			if child:IsA("Model") then
				-- живая геометрия, а не WorldPivot (см. getFloorOffsets)
				local pp = child.PrimaryPart
				if pp then
					pos = pp.Position
				else
					--[[ ⚠️ НЕ ПО ГАБАРИТНОМУ БОКСУ. У сети в модели есть деталь, уводящая
					     бокс на ~90 студов вперёд: клетка сети «числилась» на девять
					     клеток дальше, а её настоящая клетка выглядела свободной —
					     туда ставилась вторая сеть или пол. Берём деталь полотна
					     (raft_collector), иначе самую крупную деталь, и только потом бокс. ]]
					local anchor = nil
					local bestVol = -1
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then
							if d.Name:lower() == "raft_collector" then anchor = d break end
							local vol = d.Size.X * d.Size.Y * d.Size.Z
							if vol > bestVol then anchor, bestVol = d, vol end
						end
					end
					if anchor then
						pos = anchor.Position
					else
						local ok, bb = pcall(function() return child:GetBoundingBox() end)
						pos = ok and bb.Position or nil
					end
				end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local lp = flatCF:PointToObjectSpace(pos)
				local function canon(v)
					local p = (v - math.round(v / gridSize) * gridSize) % gridSize
					if p > gridSize / 2 then p -= gridSize end
					return p
				end
				local px, pz = canon(lp.X), canon(lp.Z)
				local key = (math.round(px * 4) % (gridSize * 4)) .. "_"
					.. (math.round(pz * 4) % (gridSize * 4))
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or { px, pz }
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	if bestKey then return reps[bestKey][1], reps[bestKey][2] end
	return 0, 0
end

local function getFloorOffsets(raft)
	local offsets = {}
	local seen = {}

	-- Scan all children of the raft for initial Raft_part tiles (no GridX/GridZ)
	-- and player-built tiles (with GridX/GridZ + BuildType == "raft").
	local primary = raft.PrimaryPart
	if not primary then return offsets end

	-- Use a yaw-only CFrame for grid coordinate detection, matching the
	-- placement system (which uses restYaw). Using primary.CFrame directly
	-- would include pitch/roll that can mix world-Y into local X/Z and
	-- collapse multiple tiles to the same grid coordinate.
	local restYaw = primary:GetAttribute("RestYaw")
	if not restYaw then
		local _, yaw, _ = primary.CFrame:ToEulerAnglesYXZ()
		restYaw = yaw
	end
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local flatCF = CFrame.new(primary.Position) * CFrame.Angles(0, restYaw, 0) * CFrame.new(phaseX, 0, phaseZ)

	-- КООРДИНАТА — ПО ФАКТИЧЕСКОМУ МЕСТУ, атрибуты только сверяем. Стартовые
	-- тайлы нового плота собраны в Studio копированием, и копия приносит ЧУЖИЕ
	-- GridX/GridZ: девять досок с одинаковыми атрибутами схлопывались в одну
	-- клетку, и система «видела» только центральную. Если атрибут расходится с
	-- позицией — верим позиции и чиним атрибут (самолечение).
	for _, child in raft:GetChildren() do
		local isTile = child:GetAttribute("BuildType") == "raft"
			or child.Name == "Raft_part" or child.Name == "Net_Part" or child == primary
		if isTile then
			-- ⚠️ ПОЗИЦИЯ ТАЙЛА — ТОЛЬКО ПО ЖИВОЙ ГЕОМЕТРИИ.
			--
			-- Здесь стоял child:GetPivot().Position. У модели БЕЗ PrimaryPart
			-- это WorldPivot — фиксированный мировой CFrame, который НЕ едет
			-- следом за деталями, когда плот плывёт. Такие тайлы уползали по
			-- решётке на клетку в секунду: (1,4) → (1,5) → (1,6)… — и соседняя
			-- с ними клетка оставалась «без соседа», то есть строить рядом было
			-- нельзя. Именно так ломалось место возле монолита.
			--
			-- У модели С PrimaryPart GetPivot возвращает его CFrame, поэтому
			-- первая ветка полностью повторяет прежнее поведение — меняется
			-- только судьба сломанных тайлов.
			-- (Держать равным клиентской копии.)
			local pos
			if child:IsA("Model") then
				local pp = child.PrimaryPart
				if pp then
					pos = pp.Position
				else
					--[[ ⚠️ НЕ ПО ГАБАРИТНОМУ БОКСУ. У сети в модели есть деталь, уводящая
					     бокс на ~90 студов вперёд: клетка сети «числилась» на девять
					     клеток дальше, а её настоящая клетка выглядела свободной —
					     туда ставилась вторая сеть или пол. Берём деталь полотна
					     (raft_collector), иначе самую крупную деталь, и только потом бокс. ]]
					local anchor = nil
					local bestVol = -1
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then
							if d.Name:lower() == "raft_collector" then anchor = d break end
							local vol = d.Size.X * d.Size.Y * d.Size.Z
							if vol > bestVol then anchor, bestVol = d, vol end
						end
					end
					if anchor then
						pos = anchor.Position
					else
						local ok, bb = pcall(function() return child:GetBoundingBox() end)
						pos = ok and bb.Position or nil
					end
				end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			-- ПРИЧАЛ ЗАНИМАЕТ НЕСКОЛЬКО КЛЕТОК, и берём их из АТРИБУТОВ, а не из
			-- позиции. По позиции нельзя: пивот у Boat_3x — центр габаритов, куда
			-- входят ещё лодка, столб и канат, и клетка вычислялась бы мимо. Атрибуты
			-- проставлены при установке и вместе с плотом не меняются.
			-- Без этого внутрь причала можно было бы воткнуть пол, а его крайние
			-- клетки не считались бы соседями для стройки вокруг.
			local dockSteps = child:GetAttribute("DockSteps")
			if dockSteps then
				local bx = child:GetAttribute("GridX") or 0
				local bz = child:GetAttribute("GridZ") or 0
				local sx = child:GetAttribute("DockDX") or 0
				local sz = child:GetAttribute("DockDZ") or 1
				for i = 0, dockSteps do
					local cx, cz = bx + sx * i, bz + sz * i
					local key = cx .. "_" .. cz
					if not seen[key] then
						seen[key] = true
						table.insert(offsets, { x = cx, z = cz })
					end
				end
			elseif pos then
				local localPos = flatCF:PointToObjectSpace(pos)
				local gridX = math.round(localPos.X / GRID_SIZE)
				local gridZ = math.round(localPos.Z / GRID_SIZE)
				local ax = child:GetAttribute("GridX")
				if ax ~= nil and (ax ~= gridX or child:GetAttribute("GridZ") ~= gridZ) then
					child:SetAttribute("GridX", gridX)
					child:SetAttribute("GridZ", gridZ)
				end
				local key = gridX .. "_" .. gridZ
				if not seen[key] then
					seen[key] = true
					table.insert(offsets, { x = gridX, z = gridZ })
				end
			end
		end
	end

	-- Guarantee (0,0) is always present
	if not seen["0_0"] then
		table.insert(offsets, {x = 0, z = 0})
	end

	return offsets
end

-- When PrimaryPart is not a Raft_part (e.g. a SpawnLocation), its orientation
-- differs from tile orientation. Returns a rotation correction so new tiles
-- match existing Raft_part orientation instead of PrimaryPart's.
-- ПОВОРОТ КЛЕТКИ — как у БОЛЬШИНСТВА досок палубы. Три подхода провалились:
-- «первая попавшаяся» доска заражала постройки своим ручным разворотом; чистое
-- тождество наследовало ориентацию PrimaryPart (лежащее на боку бревно) —
-- доска вставала вертикально; чистый rest-yaw тоже ставил её на бок, потому что
-- ПИВОТ модели Raft_part не совпадает с её «лежащей» геометрией, и эту конвенцию
-- знает только живая доска. Голосование большинством даёт конвенцию пивота И
-- отсекает одиночные ручные развороты. (Держать равным клиентской копии.)
local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				-- относительный поворот примари→доска постоянен (сварка), качка
				-- на него не влияет; ключ — оси поворота с округлением
				local rot = primary.CFrame:ToObjectSpace(tileCF).Rotation
				local xv, yv = rot.XVector, rot.YVector
				local key = string.format("%d,%d,%d|%d,%d,%d",
					math.round(xv.X * 10), math.round(xv.Y * 10), math.round(xv.Z * 10),
					math.round(yv.X * 10), math.round(yv.Y * 10), math.round(yv.Z * 10))
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or rot
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	return bestKey and reps[bestKey] or CFrame.new()
end

-- ВЫСОТА ЦЕНТРА ГАБАРИТОВ доски палубы над пивотом PrimaryPart — по мировой
-- вертикали покоя, голосованием большинством. Именно центр ГЕОМЕТРИИ, а не
-- пивот: у шаблона пивот в НИЗУ тайла, у досок палубы — другая конвенция, и
-- равнение по пивотам давало доску на 2.3 выше пола. Геометрия к геометрии —
-- конвенции пивотов сокращаются. (Держать равным клиентской копии.)
local function deckCenterRestY(raft)
	local primary = raft.PrimaryPart
	if not primary then return 0 end
	local restCF = primary:GetAttribute("RestCFrame") or primary.CFrame
	local restRot = restCF - restCF.Position
	local counts, reps = {}, {}
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local centerPos
			if child:IsA("Model") then
				local ok, bb = pcall(function() return child:GetBoundingBox() end)
				centerPos = ok and bb.Position or nil
			elseif child:IsA("BasePart") then
				centerPos = child.Position
			end
			if centerPos then
				local rel = primary.CFrame:PointToObjectSpace(centerPos)
				local y = restRot:VectorToWorldSpace(rel).Y
				local key = math.round(y * 4) -- корзина 0.25 студа
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or y
			end
		end
	end
	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	return bestKey and reps[bestKey] or 0
end

-- ⚠️ ВЫСОТУ НАСТИЛА БЕРЁМ ПРЯМО В МИРОВЫХ КООРДИНАТАХ.
-- Раньше она считалась смещением ОТНОСИТЕЛЬНО пивота плота и по дороге делала
-- круг: PointToObjectSpace брал вектор в ТЕКУЩИХ осях плота, а
-- VectorToWorldSpace разворачивал его через оси ПОКОЯ. Пока плот стоит ровно,
-- это одно и то же; качнулся — и вертикаль набирает вклад от горизонтальных
-- смещений досок, тем больший, чем дальше доска от центра.
-- Для вертикали круг не нужен вовсе: мировая Y верхней грани доски и есть
-- высота палубы. Оси покоя нужны только горизонтальной сетке.
-- Мода, а не первая попавшаяся доска: толщина у них разная, а порядок детей у
-- сервера и клиента свой. ДЕРЖАТЬ РАВНЫМ клиентской копии deckTopWorldY.
-- ⚠️ ВЫСОТУ НАСТИЛА ЛУЧШЕ ВСЕГО ИЗМЕРИТЬ, А НЕ ВЫВЕСТИ.
-- Через габариты досок она вычислялась трижды по-разному и трижды мимо: у
-- Raft_part габаритная коробка выше самого настила, и «верх коробки» оказывался
-- на пять стад выше палубы. Луч сверху вниз попадает в НАСТОЯЩУЮ поверхность, по
-- которой ходит игрок. Светим только по доскам пола, иначе поймали бы бочку.
-- ДЕРЖАТЬ РАВНЫМ клиентской копии deckTopAt.
local deckRayParams = RaycastParams.new()
deckRayParams.FilterType = Enum.RaycastFilterType.Include

local function deckTopAt(raft, x, z)
	local prim = raft and raft.PrimaryPart
	if not prim then return nil end
	local tiles = {}
	for _, c in ipairs(raft:GetChildren()) do
		if c.Name == "Raft_part" then table.insert(tiles, c) end
	end
	if #tiles == 0 then return nil end
	deckRayParams.FilterDescendantsInstances = tiles
	local from = Vector3.new(x, prim.Position.Y + 60, z)
	local hit = workspace:Raycast(from, Vector3.new(0, -160, 0), deckRayParams)
	return hit and hit.Position.Y or nil
end

-- Объявлено заранее: телу нужен localToWorld, а он определён ниже по файлу.
-- Без этого вызов уходил в nil, и стена не ставилась вовсе.
local deckTopForEdge
local lastDeckTop = nil   -- последний удачный замер палубы

-- Запасной путь, когда лучу не во что упереться: мода по верхним граням досок.
local function deckTopWorldY(raft)
	local counts, reps = {}, {}
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == "Raft_part" and child ~= raft.PrimaryPart then
			local pos, size
			if child:IsA("Model") then
				local ok, c, s = pcall(function()
					local a, b = child:GetBoundingBox()
					return a, b
				end)
				if ok and c and s then pos, size = c.Position, s end
			elseif child:IsA("BasePart") then
				pos, size = child.Position, child.Size
			end
			if pos and size then
				local top = pos.Y + size.Y * 0.5
				local key = math.round(top * 4)   -- корзина 0.25 стада
				counts[key] = (counts[key] or 0) + 1
				reps[key] = reps[key] or top
			end
		end
	end

	local bestKey, bestN
	for k, n in pairs(counts) do
		if not bestN or n > bestN then bestKey, bestN = k, n end
	end
	if bestKey then return reps[bestKey] end
	return raft.PrimaryPart and raft.PrimaryPart.Position.Y or 0
end

local function isFloorOccupied(offsets, gx, gz)
	for _, o in offsets do
		if o.x == gx and o.z == gz then return true end
	end
	return false
end

local function isFloorAdjacent(offsets, gx, gz)
	for _, o in offsets do
		if (math.abs(o.x - gx) == 1 and o.z == gz) or (math.abs(o.z - gz) == 1 and o.x == gx) then
			return true
		end
	end
	return false
end

-- ОПОРА СТЕНЫ — РЕБРО КЛЕТКИ, а не пара балок. Пара углов (cx1,cz1)-(cx2,cz2)
-- одинакова с обеих сторон ребра, поэтому осталась канонным адресом стены и
-- формат сохранений не изменился. Балки как требование убраны: достаточно,
-- чтобы к ребру примыкала хотя бы одна клетка пола.
-- (Держать равным клиентской копии edgeHasFloor.)
local function edgeHasFloorImpl(isOccupied, offsets, cx1, cz1, cx2, cz2)
	local midX, midZ = (cx1 + cx2) / 2, (cz1 + cz2) / 2
	if cx1 == cx2 then
		return isOccupied(offsets, midX - 0.5, midZ) or isOccupied(offsets, midX + 0.5, midZ)
	end
	return isOccupied(offsets, midX, midZ - 0.5) or isOccupied(offsets, midX, midZ + 0.5)
end

-- Beam corner: at least one adjacent floor tile must exist
local function cornerHasFloor(offsets, cx, cz)
	return isFloorOccupied(offsets, cx - 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)
		or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)
		or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
end

-- Compute inset to keep beam within raft boundaries
-- Shifts the beam toward the raft interior on edges where no tile exists beyond
local function computeBeamInset(offsets, cx, cz)
	local insetX, insetZ = 0, 0

	local hasPlusX = isFloorOccupied(offsets, cx + 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusX = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx - 0.5, cz + 0.5)

	if hasMinusX and not hasPlusX then
		insetX = -BEAM_INSET
	elseif hasPlusX and not hasMinusX then
		insetX = BEAM_INSET
	end

	local hasPlusZ = isFloorOccupied(offsets, cx - 0.5, cz + 0.5) or isFloorOccupied(offsets, cx + 0.5, cz + 0.5)
	local hasMinusZ = isFloorOccupied(offsets, cx - 0.5, cz - 0.5) or isFloorOccupied(offsets, cx + 0.5, cz - 0.5)

	if hasMinusZ and not hasPlusZ then
		insetZ = -BEAM_INSET
	elseif hasPlusZ and not hasMinusZ then
		insetZ = BEAM_INSET
	end

	return insetX, insetZ
end

local function makeBeamKey(cx, cz)
	return string.format("%.1f_%.1f", cx, cz)
end

-- Normalized span between two beam corners (no prefix). Used as a shared
-- "this side of these two beams is occupied" key, so a wall panel and a wall
-- arch can never coexist on the same span.
local function makeSpanKey(cx1, cz1, cx2, cz2)
	if cx1 > cx2 or (cx1 == cx2 and cz1 > cz2) then
		cx1, cz1, cx2, cz2 = cx2, cz2, cx1, cz1
	end
	return string.format("%.1f_%.1f_%.1f_%.1f", cx1, cz1, cx2, cz2)
end

local function makeWallPanelKey(cx1, cz1, cx2, cz2)
	return "wp_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeWallArchKey(cx1, cz1, cx2, cz2)
	return "wa_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function makeDoorKey(cx1, cz1, cx2, cz2)
	return "dr_" .. makeSpanKey(cx1, cz1, cx2, cz2)
end

local function getBeamKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local bk = child:GetAttribute("BeamKey")
		if bk then keys[bk] = true end
	end
	return keys
end

-- Returns the set of normalized spans currently occupied by ANY wall-like
-- object (wall_panel or wall_arch). Used to block placing two wall-types on
-- the same beam pair side.
local function getWallSpanKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local sk = child:GetAttribute("WallSpanKey")
		if sk then keys[sk] = true end
	end
	return keys
end

local function getWallArchKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local wk = child:GetAttribute("WallArchKey")
		if wk then keys[wk] = true end
	end
	return keys
end

local function getDoorKeys(raft)
	local keys = {}
	for _, child in raft:GetChildren() do
		local dk = child:GetAttribute("DoorKey")
		if dk then keys[dk] = true end
	end
	return keys
end

-- Convert local studs position to world position.
-- Position is computed via the stable RestCFrame approach (same as the save
-- system) so the local offset captured by the WeldConstraint is always the
-- same regardless of current wave-induced tilt. Returns the restYaw for
-- rotating placed beams/walls/doors to face raft-forward.
local function localToWorld(raft, studX, studZ)
	local primaryCF = raft.PrimaryPart.CFrame
	local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or primaryCF
	local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(studX + phaseX, 0, studZ + phaseZ))
	local localOffset = restCF:VectorToObjectSpace(worldOffset)
	return (primaryCF * CFrame.new(localOffset)).Position, restYaw
end

-- ⚠️ СВЕТИМ В СЕРЕДИНЫ КЛЕТОК, А НЕ В РЕБРО, И БЕРЁМ САМОЕ НИЗКОЕ ПОПАДАНИЕ.
-- Стена встаёт на ребро клетки, а на рёбрах у доски стоят столбы и перила: луч в
-- середину ребра попадал в их макушку и объявлял палубу на 3.4 стада выше, чем
-- она есть. Настил ровный в СЕРЕДИНЕ клетки. Берём обе клетки у ребра и выбираем
-- НИЖНЕЕ попадание: столб всегда выше пола, значит минимум — это пол.
-- Точек по клетке несколько: одна могла попасть в тот же столб или в дыру между
-- досками, и тогда замер терялся целиком.
-- ДЕРЖАТЬ РАВНЫМ клиентской копии deckTopForEdge.
local SAMPLE_SPREAD = 0.28   -- доля клетки, на которую разносим пробы

function deckTopForEdge(raft, cx1, cz1, cx2, cz2)
	if not raft then return nil end
	local midX, midZ = (cx1 + cx2) / 2, (cz1 + cz2) / 2
	local cells
	if cz1 == cz2 then
		cells = { { midX, cz1 - 0.5 }, { midX, cz1 + 0.5 } }
	else
		cells = { { cx1 - 0.5, midZ }, { cx1 + 0.5, midZ } }
	end

	local best
	for _, c in ipairs(cells) do
		for _, d in ipairs({ {0, 0}, {SAMPLE_SPREAD, 0}, {-SAMPLE_SPREAD, 0},
			{0, SAMPLE_SPREAD}, {0, -SAMPLE_SPREAD} }) do
			local wp = localToWorld(raft, (c[1] + d[1]) * GRID_SIZE, (c[2] + d[2]) * GRID_SIZE)
			local y = deckTopAt(raft, wp.X, wp.Z)
			if y and (not best or y < best) then best = y end
		end
	end
	-- последний удачный замер вместо расчёта по габаритам: палуба у плота одна,
	-- а расчёт даёт заведомо завышенное число (см. комментарий у deckTopWorldY)
	if best then lastDeckTop = best end
	return best or lastDeckTop
end

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
-- ⚠️ Кто именно висит на тросе, решает AnchorRig — одно правило на
-- постройку, призрак и саму лебёдку. Здесь была своя копия, и она
-- разошлась с остальными: приваривался якорь вместо рамы.
local function hangingPartOf(model)
	return AnchorRig.hangingPart(model)
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

local function weldToRaft(obj, raft)
	-- Weld FIRST while still anchored, then unanchor in a second pass.
	-- If we unanchor first, each part briefly exists as a zero-velocity body
	-- before the weld attaches it to the moving raft. Welding while still
	-- anchored captures the relative pose without any free-physics step.
	-- After unanchoring we also pin network ownership to the server so
	-- Roblox doesn't reassign ownership of the raft assembly mid-placement.
	-- БЕЗ МАССЫ — ЭТО ГЛАВНОЕ ПРОТИВ РЫВКА ПЛОТА ПРИ СТРОЙКЕ.
	-- Деталь с массой, приваренная в движущуюся сборку, бьёт по плоту дважды:
	--   1) Roblox уравнивает импульс: v_new = (M·v + m·0)/(M+m), то есть плот
	--      теряет долю скорости m/(M+m). Снимок скорости в placeWithVelocityPreserved
	--      от этого не спасает — сборка пересобирается уже на СЛЕДУЮЩЕМ шаге
	--      физики, после того как скорость восстановлена.
	--   2) BoatMovement компенсирует гравитацию силой totalMass * Gravity. Масса
	--      скакнула — кадр до пересчёта силы плот проседает.
	-- Оба эффекта вместе и читаются как «плот дёрнулся назад», а не «плавно
	-- построилось». Massless убирает причину целиком: сборка не замечает
	-- добавления. На коллизии и ходьбу это не влияет — сеть так ставится давно.
	local function stripMass(part)
		part.Massless = true
	end
	local function unanchorAndPin(part)
		part.Anchored = false
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end
	if obj:IsA("Model") then
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				stripMass(desc)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = raft.PrimaryPart
				weld.Parent = desc
			end
		end
		for _, desc in obj:GetDescendants() do
			if desc:IsA("BasePart") then
				unanchorAndPin(desc)
			end
		end
	elseif obj:IsA("BasePart") then
		stripMass(obj)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = obj
		weld.Part1 = raft.PrimaryPart
		weld.Parent = obj
		unanchorAndPin(obj)
	end
end

-- Welding a new part with mass into the moving raft assembly causes Roblox
-- to equilibrate momentum: the combined velocity = (M*V + m*0)/(M+m), so
-- the raft loses a factor of m/M of its forward velocity. Across many
-- placements this manifests as the player visibly desyncing from the raft.
-- We snapshot the raft's velocity before the weld and restore it after, so
-- the assembly's velocity is unaffected by the addition.
-- ⚠️ Одного восстановления СРАЗУ после doPlace() мало: Roblox пересобирает
-- сборку не в момент создания сварки, а на следующем шаге физики. Запись,
-- сделанная в том же кадре, достаётся ещё СТАРОЙ сборке — без новой детали, —
-- и уравнивание импульса всё равно происходит потом. Поэтому повторяем запись
-- один раз на следующем Heartbeat, когда деталь уже в сборке.
-- (С Massless в weldToRaft уравнивать нечего, но подстраховка ничего не стоит и
-- прикрывает детали, которым массу вернут вручную.)
-- ═══════════ ПРИЧАЛ (Boat_3x): геометрия установки ═══════════
-- Держать равным клиентской копии в BuildingSystem.client.lua — если формулы
-- разойдутся, призрак будет стоять не там, куда встанет постройка.

-- ВЕРХ НАСТИЛА ПЛОТА. Берём именно доску пола (raft_floor внутри Raft_part), а не
-- габарит всей клетки: у Raft_part внутри бывают балки, а BuildType="raft" носит и
-- якорь с его А-образной рамой — по ним причал взлетал на несколько студов вверх.
-- Возвращает верх доски пола И её толщину (Size.Y): доска пола 2.3, а настил причала
-- 2.099 — разницу учитываем при выравнивании по высоте.
local function raftDeckTopY(raft)
	-- МАКСИМУМ, а не «первая попавшаяся доска»: порядок GetChildren на сервере и на
	-- клиенте разный, и от «первой» превью и постройка вставали на разной высоте.
	local best, bestH
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" then
			local floor = child:IsA("BasePart") and child
				or child:FindFirstChild("raft_floor", true)
				or child:FindFirstChildWhichIsA("BasePart", true)
			if floor and floor:IsA("BasePart") then
				local top = floor.Position.Y + floor.Size.Y / 2
				if not best or top > best then best, bestH = top, floor.Size.Y end
			end
		end
	end
	return best, bestH
end

-- СДВИГ ПРИЧАЛА ОТНОСИТЕЛЬНО КЛЕТКИ (студы). Настил у Boat_3x — НЕ полная доска
-- пола: вдоль оси причала он 4.922 при клетке 10. Поэтому привязка (центр
-- Dock_deck_L) не совпадает с центром клетки, её надо подвинуть.
--   сдвиг = ширина настила − четверть клетки = 4.922 − 2.5 = 2.422
-- Считается ОТ МОДЕЛИ (dockAlongShift), а не вбито числом: если причал пересоберут
-- или перемасштабируют, поправка пересчитается сама. Знак минус — потому что дальше
-- значение умножается на направление L→R, а у Boat_3x это (-1, 0).
-- DOCK_SHIFT_FINE — ручная докрутка, если после всего останется небольшой промах.
-- ACROSS — поперёк оси причала. Держать равным клиентской копии.
local DOCK_SHIFT_FINE   = 0
local DOCK_SHIFT_ACROSS = 0
local function dockAlongShift(deckW)
	return -((deckW or GRID_SIZE / 2) - GRID_SIZE / 4) + DOCK_SHIFT_FINE
end

-- ОПОРА ПРИЧАЛА — ЕГО НАСТИЛЫ, снятые с самой модели:
--   deckTop  — от центра габаритов до верха настила (по нему ровняем высоту);
--   ax, az   — сдвиг от центра габаритов до центра Dock_deck_L: именно этот настил
--              ложится в клетку под курсором. Ни центр габаритов, ни середина между
--              настилами не годятся — в модель входят лодка, столб, канат и вёсла,
--              они тянут габарит в сторону, и причал вставал мимо клетки;
--   dx, dz   — единичное направление от L к R в осях модели;
--   steps    — сколько КЛЕТОК между настилами (обычно 2 → причал занимает 3);
--   deckW    — ширина настила ВДОЛЬ оси причала (у Boat_3x 4.922 против клетки 10);
--   deckH    — толщина настила (2.099 против 2.3 у доски пола).
local function dockMetrics(model)
	local bcf, bsize = model:GetBoundingBox()
	local l = model:FindFirstChild("Dock_deck_L", true)
	local r = model:FindFirstChild("Dock_deck_R", true)
	local deckTop = bsize.Y / 2
	local ax, az, dx, dz, steps = 0, 0, 0, 1, 2

	if l and l:IsA("BasePart") then
		deckTop = (l.Position.Y + l.Size.Y / 2) - bcf.Position.Y
		ax = l.Position.X - bcf.Position.X
		az = l.Position.Z - bcf.Position.Z
	end
	if l and r and l:IsA("BasePart") and r:IsA("BasePart") then
		local v = r.Position - l.Position
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 1 then
			-- направление прижимаем к оси решётки: настилы стоят по прямой
			if math.abs(flat.X) >= math.abs(flat.Z) then
				dx, dz = (flat.X > 0) and 1 or -1, 0
			else
				dx, dz = 0, (flat.Z > 0) and 1 or -1
			end
			steps = math.max(1, math.round(flat.Magnitude / GRID_SIZE))
		end
	end

	-- Габарит настила ВДОЛЬ оси причала. Проекцией граней, а не просто Size.X: если
	-- деталь окажется повёрнутой, размер всё равно посчитается по нужному направлению.
	local deckW, deckH
	if l and l:IsA("BasePart") then
		local axis, cf, s = Vector3.new(dx, 0, dz), l.CFrame, l.Size
		deckW = math.abs(cf.RightVector:Dot(axis)) * s.X
			+ math.abs(cf.UpVector:Dot(axis)) * s.Y
			+ math.abs(cf.LookVector:Dot(axis)) * s.Z
		deckH = s.Y
	end
	return deckTop, ax, az, dx, dz, steps, deckW, deckH
end

-- шаг решётки от настила L к настилу R с учётом поворота (0..3 → 0/90/180/270°)
local function dockStep(dx, dz, rot)
	if rot == 1 then return dz, -dx end
	if rot == 2 then return -dx, -dz end
	if rot == 3 then return -dz, dx end
	return dx, dz
end

-- клетки, которые займёт причал: от клетки под курсором вдоль его оси
local function dockCells(template, gx, gz, rot)
	local _, _, _, dx, dz, steps = dockMetrics(template)
	local sx, sz = dockStep(dx, dz, rot)
	local cells = {}
	for i = 0, steps do
		table.insert(cells, { gx + sx * i, gz + sz * i })
	end
	return cells
end

-- Мировой CFrame причала: РОВНО, по курсу плота, настилом вровень с полом, серединой
-- между настилами — в клетку под курсором.
-- Поправку getTileRotationCorrection здесь применять НЕЛЬЗЯ: она описывает пивот
-- доски пола (он развёрнут на 90°), а детали причала уже лежат ровно — от неё
-- причал вставал на попа.
local function dockWorldCF(raft, template, gx, gz, rot)
	local prim = raft.PrimaryPart
	if not prim then return nil end
	local restCF = prim:GetAttribute("RestCFrame") or prim.CFrame
	local restYaw = prim:GetAttribute("RestYaw") or 0
	local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
	local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
	local worldOffset = restFlat:VectorToWorldSpace(
		Vector3.new(gx * GRID_SIZE + phaseX + FLOOR_FINE_X, 0, gz * GRID_SIZE + phaseZ + FLOOR_FINE_Z))
	local pos = (prim.CFrame * CFrame.new(restCF:VectorToObjectSpace(worldOffset))).Position

	local deckTop, ax, az, dx, dz, _, deckW, deckH = dockMetrics(template)
	local top, floorH = raftDeckTopY(raft)
	-- ВЫСОТА. Верх настила ровняем по верху доски пола, но доски разной толщины
	-- (2.3 против 2.099), а меш у них один и тот же, просто сжатый. Значит видимая
	-- поверхность у тонкого настила лежит чуть выше его габарита — опускаем причал на
	-- половину разницы толщин (≈0.1), иначе он стоит еле заметной ступенькой.
	local lift = (deckH and floorH) and -(floorH - deckH) / 2 or 0
	local y = top and (top - deckTop + lift) or pos.Y
	-- Сдвиг привязки поворачивается вместе с моделью, поэтому идёт ПОСЛЕ поворота:
	-- так в клетку под курсором попадает настил Dock_deck_L при любом развороте.
	-- Ось причала в осях МОДЕЛИ — (dx, dz), по ней и раскладываем поправку.
	local along = dockAlongShift(deckW)
	local shiftX = dx * along + dz * DOCK_SHIFT_ACROSS
	local shiftZ = dz * along + dx * DOCK_SHIFT_ACROSS
	return CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, restYaw + rot * math.rad(90), 0)
		* CFrame.new(-ax + shiftX, 0, -az + shiftZ)
end

local function placeWithVelocityPreserved(raft, doPlace)
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	-- ⚠️ ИГРОКА ОТСЮДА НЕ УДЕРЖАТЬ — ЭТО ДЕЛАЕТ КЛИЕНТ.
	-- Плот и персонаж — разные сборки, и возврат скорости ниже спасает только
	-- плот: пока он на шаг физики теряет ход от пересборки, стоящий на нём игрок
	-- продолжает лететь с прежней скоростью и уезжает по палубе.
	-- Здесь стояла попытка вернуть персонажа на место записью в hrp.CFrame, и она
	-- не работала по устройству: персонаж принадлежит СВОЕМУ клиенту (network
	-- ownership), и серверная запись тут же перебивается его репликацией. Держать
	-- позицию должен владелец — см. RaftShake.
	doPlace()
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	-- ⚠️ ГОВОРИМ ВСЕМ, А НЕ ТОЛЬКО СТРОИТЕЛЮ.
	-- Свой клиент строитель удерживает сам, ещё до ответа сервера. А вот соседа,
	-- который просто стоял рядом на палубе, до сих пор утаскивало: он о постройке
	-- не знал вовсе.
	RaftShake.notify()

	-- Именно Heartbeat, а НЕ task.defer: defer резюмится в том же кадре, до шага
	-- физики, то есть до пересборки сборки — и повтор был бы бесполезен.
	-- Heartbeat наступает уже ПОСЛЕ шага физики.
	game:GetService("RunService").Heartbeat:Once(function()
		if not primary.Parent then return end
		-- Вертикаль НЕ трогаем: её каждый кадр ведёт сервопривод высоты в
		-- BoatMovement, и чужая запись по Y столкнула бы плот с ватерлинии.
		local v = primary.AssemblyLinearVelocity
		primary.AssemblyLinearVelocity = Vector3.new(linVel.X, v.Y, linVel.Z)
		primary.AssemblyAngularVelocity = angVel
	end)
end

placeBlockEvent.OnServerEvent:Connect(function(player, buildType, ...)
	if type(buildType) ~= "string" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local raft = getRaft()
	if not raft or not raft.PrimaryPart then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return end

	-- Anchor placement uses the Anchor_part tool (crafted at the
	-- workbench). Every other buildType is hammer-driven.
	-- ⚠️ Якорь принимаем под ОБОИМИ именами: рецепт теперь выдаёт Raft_anchor,
	-- но у игрока в рюкзаке мог остаться старый Anchor_part с прошлой сессии.
	local requiredTool = (buildType == "anchor")
		and ((tool.Name == "Raft_anchor") and "Raft_anchor" or "Anchor_part")
		or (buildType == "dock3") and "Boat_3x"
		or "Hammer"
	if tool.Name ~= requiredTool then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	--[[ АДМИН СТРОИТ БЕСПЛАТНО. Флаг DevLogs ставит сервер (DevLogFlag: Studio,
	     WeaponUpgradeConfig.ADMIN_USER_IDS, владелец плейса) — клиент его не
	     подделает. Вместо инвентаря подсовываем таблицу, где любого ресурса
	     «бесконечно», а списание пишется в неё же и до настоящего рюкзака не
	     доходит: все проверки и списания ниже работают без правок. ]]
	if player:GetAttribute("DevLogs") == true then
		inv = setmetatable({}, { __index = function() return math.huge end })
	end

	-- Короткая обёртка: установок ниже девять штук, и raft у всех один и тот же.
	local function place(fn)
		placeWithVelocityPreserved(raft, fn)
	end

	if buildType == "dock3" then
		-- ПРИЧАЛ С ЛОДКОЙ: по размеру равен ТРЁМ клеткам пола и встаёт вместо них.
		-- Клик приходит по СРЕДНЕЙ клетке, две остальные лежат вдоль оси span.
		local gridX, gridZ, rotArg = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end
		local rot = math.round(tonumber(rotArg) or 0) % 4
		local gx, gz = math.round(gridX), math.round(gridZ)

		local template = rs:FindFirstChild("Boat_3x") or rs:FindFirstChild("Boat_3x", true)
		if not template then
			warn("[Building] модель Boat_3x не найдена в ReplicatedStorage")
			return
		end

		-- ДИАГНОСТИКА: если причал не встаёт, в логе видно ПОЧЕМУ и какая у модели
		-- геометрия. Молча возвращаться нельзя — со стороны это «клик не работает».
		local dTop, dax, daz, ddx, ddz, dsteps, dW, dH = dockMetrics(template)
		local cells = dockCells(template, gx, gz, rot)
		local offsets = getFloorOffsets(raft)
		local touches = false
		for _, c in ipairs(cells) do
			if isFloorOccupied(offsets, c[1], c[2]) then
				warn(("[Причал] клетка (%d,%d) занята — не ставлю"):format(c[1], c[2]))
				return
			end
			if isFloorAdjacent(offsets, c[1], c[2]) then touches = true end
		end
		if not touches then
			warn(("[Причал] ни одна из %d клеток не примыкает к полу — не ставлю"):format(#cells))
			return
		end
		local _, dFloorH = raftDeckTopY(raft)
		print(("[Причал] ставлю: клетка (%d,%d), поворот %d, клеток %d, ось (%d,%d), настил→верх %.2f, привязка (%.2f, %.2f), настил %.3f×%.3f, пол %.3f, сдвиг %.3f")
			:format(gx, gz, rot, #cells, ddx, ddz, dTop, dax, daz,
				dW or -1, dH or -1, dFloorH or -1, dockAlongShift(dW)))
		local span = (rot % 2 == 0) and "z" or "x"

		local worldCF = dockWorldCF(raft, template, gx, gz, rot)
		if not worldCF then return end

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		local dock = template:Clone()
		-- ПИВОТ АВТОРСКОЙ МОДЕЛИ ПЕРЕКОШЕН: у Boat_3x WorldPivot повёрнут (крен −21°),
		-- потому что модель ставили руками, а PrimaryPart у неё не задан. PivotTo
		-- сохраняет этот перекос, и причал вставал боком и вразнос. Приводим пивот к
		-- центру габаритов БЕЗ поворота — тогда PivotTo работает предсказуемо.
		if dock:IsA("Model") then
			local bcf = dock:GetBoundingBox()
			dock.WorldPivot = CFrame.new(bcf.Position)
		end
		-- Считается полом: занимает клетки, вокруг него можно строить, а внутрь
		-- пол уже не воткнуть (см. DockSpan в getFloorOffsets).
		dock:SetAttribute("BuildType", "raft")
		dock:SetAttribute("GridX", gx)
		dock:SetAttribute("GridZ", gz)
		dock:SetAttribute("DockSpan", span)
		-- по этим трём getFloorOffsets разворачивает причал в его клетки
		local mdx, mdz, msteps
		do
			local _, _, _, dx, dz, steps = dockMetrics(template)
			mdx, mdz = dockStep(dx, dz, rot)
			msteps = steps
		end
		dock:SetAttribute("DockDX", mdx)
		dock:SetAttribute("DockDZ", mdz)
		dock:SetAttribute("DockSteps", msteps)
		if dock:IsA("Model") then
			-- ⚠️ PrimaryPart здесь НЕ НАЗНАЧАЕМ. У модели с PrimaryPart GetPivot
			-- возвращает CFrame ЭТОЙ ДЕТАЛИ, а не WorldPivot, — то есть выставленный
			-- выше нормализованный пивот просто игнорировался, и PivotTo считал от
			-- случайной детали (первой попавшейся, вроде вёсел). Призрак на клиенте
			-- PrimaryPart не имеет и крутится вокруг центра габаритов — из-за этого
			-- постройка и вставала не туда, где показывало превью.
			dock:PivotTo(worldCF)
		elseif dock:IsA("BasePart") then
			dock.CFrame = worldCF
		end

		-- ДЕТАЛИ ПОД УПРАВЛЕНИЕМ Motor6D (капитан в лодке) ВАРИТЬ НЕЛЬЗЯ: приваренная
		-- конечность не двигается, и анимация молча не проигрывается — ровно та же
		-- история, что была с якорем у пиратов. Варим только корень такой модели
		-- (в Motor6D он идёт как Part0 и в этот список не попадает), остальное держат
		-- суставы. Заякоренность снимаем со всего: якорь тоже убивает Motor6D.
		local driven = {}
		for _, d in dock:GetDescendants() do
			if d:IsA("Motor6D") and d.Part1 then driven[d.Part1] = true end
		end

		place(function()
			dock.Parent = raft
			for _, desc in dock:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = false
					if not driven[desc] then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = desc
						weld.Part1 = raft.PrimaryPart
						weld.Parent = desc
					end
					pcall(function() desc:SetNetworkOwner(nil) end)
				end
			end
		end)

		tool:Destroy()   -- один крафт = одна постройка, как у якоря
		if _G.SendInventory then _G.SendInventory(player) end
		return

	elseif buildType == "anchor" then
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		--[[ ⚠️ СНАЧАЛА НОВАЯ ЛЕБЁДКА, ПОТОМ СТАРЫЙ ЯКОРЬ.
		     Raft_anchor заменил Anchor_part, но старую модель из мира могли и не
		     убрать: если новой нет, ставим прежнюю — лучше старый якорь, чем
		     молчаливый отказ на кнопке. ]]
		local anchorTemplate, anchorKind
		for _, n in ipairs(ANCHOR_MODELS) do
			local t = rs:FindFirstChild(n) or rs:FindFirstChild(n, true)
			if t then anchorTemplate, anchorKind = t, n break end
		end
		if not anchorTemplate then return end

		-- ⚠️ Сдвиг на два студа — беда ТОЛЬКО старой модели: у Anchor_part
		-- PrimaryPart стоит в проёме A-образной рамы, в двух студах правее
		-- видимого центра, и PivotTo парковал тело мимо клетки. У новой лебёдки
		-- пивот на месте, и тот же сдвиг увёл бы её с доски.
		local ANCHOR_PIVOT_COMPENSATION = (anchorKind == "Anchor_part")
			and CFrame.new(-2, 0, 0) or CFrame.new()

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
		local ANCHOR_ROT_FIX = (anchorKind == "Raft_anchor")
			and CFrame.Angles(math.rad(-90), 0, 0) or CFrame.new()

		local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raft.PrimaryPart.CFrame
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
		local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
		local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
		-- ⚠️ УРОВЕНЬ НАСТИЛА ВХОДИТ В РАСЧЁТ — как у пола и у сети.
		-- Без этого слагаемого вертикаль клетки оставалась на уровне PrimaryPart
		-- (корпуса), и лебёдка вставала выше досок ровно на эту разницу.
		-- Старой модели слагаемое не даём: она и так стояла правильно.
		local deckY = (anchorKind == "Raft_anchor") and NetFit.deckCenterRestY(raft) or 0
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE + phaseX, 0, gz * GRID_SIZE + phaseZ))
			+ Vector3.new(0, deckY, 0)
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		-- ⚠️ ЭТОТ КАДР — УЖЕ ЦЕНТР ДОСКИ КЛЕТКИ. У пола к нему добавляют
		-- -RAFT_PIVOT_DELTA, чтобы получить ПИВОТ доски; нам нужен именно центр,
		-- поэтому ничего не вычитаем.
		local cellCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)
			* getTileRotationCorrection(raft) * ANCHOR_PIVOT_COMPENSATION
		local worldCF
		if anchorKind == "Raft_anchor" then
			local centerPos = cellCF.Position
			local rot = (cellCF * ANCHOR_ROT_FIX).Rotation
			worldCF = CFrame.new(centerPos + Vector3.new(0, ANCHOR_LIFT, 0)) * rot
				* CFrame.new(-anchorDeckDelta(anchorTemplate))
		else
			worldCF = cellCF
		end

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		-- Physical overlap check: probe the grid cell itself (without
		-- the X compensation) so adjacent placements on any side of
		-- the raft don't false-positive. We only care whether the
		-- cell the player chose is physically empty.
		do
			local cellCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset) * getTileRotationCorrection(raft)
			local probe = Vector3.new(GRID_SIZE * 0.75, GRID_SIZE * 0.75, GRID_SIZE * 0.75)
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { raft }
			local overlaps = workspace:GetPartBoundsInBox(cellCF, probe, params)
			if #overlaps > 0 then return end
		end

		local newAnchor = anchorTemplate:Clone()
		-- Tag it with the same grid coords as a raft tile so existing
		-- offset / occupancy / save logic counts the cell as filled and
		-- nothing else can be dropped on top of it.
		newAnchor:SetAttribute("GridX", gx)
		newAnchor:SetAttribute("GridZ", gz)
		newAnchor:SetAttribute("BuildType", "raft")
		newAnchor:SetAttribute("IsAnchor", true)

		if newAnchor:IsA("Model") then
			--[[ ⚠️ PrimaryPart НАЗНАЧАЕМ ТОЛЬКО СТАРОЙ МОДЕЛИ, И ЭТО НЕ ПРИДИРКА.
			     PivotTo у модели БЕЗ PrimaryPart работает от WorldPivot, а с ним — от
			     CFrame самой детали. Это разные системы отсчёта с разным поворотом.
			     Призрак (AnchorBuildSystem) PrimaryPart не ставит вовсе, поэтому
			     назначение здесь ломало ровно то, что игрок и увидел: на предпросмотре
			     лебёдка стоит правильно, а встаёт без поворота.
			     У Raft_anchor свой WorldPivot из FBX — его и слушаемся, как призрак. ]]
			if not newAnchor.PrimaryPart and anchorKind ~= "Raft_anchor" then
				local p = newAnchor:FindFirstChildWhichIsA("BasePart", true)
				if p then newAnchor.PrimaryPart = p end
			end
			-- Anchor's Z matches a regular raft tile; only X is offset
			-- (hollow centre), and worldCF already has the -2 X shift.
			-- No WorldPivot rework — just pivot to the compensated CF
			-- like a normal raft tile placement.
			-- ⚠️ Старую модель сажаем как раньше — пивотом: у Anchor_part он на месте,
			-- и посадка «низом» опустила бы её в настил на толщину основания.
			if anchorKind == "Raft_anchor" then
				-- высоту подбирать больше не нужно: worldCF уже посчитан так, что
				-- собственная доска лебёдки ложится на место доски клетки
				newAnchor:PivotTo(worldCF)
			else
				newAnchor:PivotTo(worldCF)
			end
		elseif newAnchor:IsA("BasePart") then
			newAnchor.CFrame = worldCF
		end
		place(function()
			newAnchor.Parent = raft
			-- Two groups stay free of raft welds so they can move:
			--   * the inner `anchor` submodel — the Union the rope
			--     lowers on — must hang freely.
			--   * every BasePart inside Wooden_Wheel except HingePart.
			--     HingePart gets the raft weld so the wheel stays put;
			--     the rotor spins via the template's HingeConstraint.
			--[[ ⚠️ ЧТО НЕ ПРИВАРИВАЕМ: груз, который висит на тросе.
			     Здесь стояла СВОЯ копия правила — «деталь, в которой лежит
			     RopeConstraint». В новой модели констрейнт лежит в раме, и копия
			     переворачивала смысл: рама оставалась свободной и уплывала от
			     плота, а якорь приваривался к палубе намертво.
			     Именно ради этого случая и заведён AnchorRig: правило одно на
			     постройку, призрак и лебёдку. Своих копий тут больше нет. ]]
			local hanging = AnchorRig.hangingPart(newAnchor)
			local wheel   = newAnchor:FindFirstChild("Wooden_Wheel")
			local hinge   = wheel and wheel:FindFirstChild("HingePart", true)
			-- ⚠️ Груз помечаем от СТРАХОВОЧНОГО СВАРЩИКА (RaftStaticWeld): он раз в
			-- запуск приваривает к плоту всё, что «висит само по себе», и якорь,
			-- который обязан свободно опускаться, попал бы под эту гребёнку после
			-- перезахода. Атрибут NoRaftWeld — его штатное исключение.
			if hanging then
				for _, d in ipairs(hanging:IsA("BasePart")
					and { hanging } or hanging:GetDescendants()) do
					if d:IsA("BasePart") then d:SetAttribute("NoRaftWeld", true) end
				end
			end
			for _, desc in newAnchor:GetDescendants() do
				if desc:IsA("BasePart") then
					--[[ ⚠️ САМА ДЕТАЛЬ ТОЖЕ СЧИТАЕТСЯ «ВИСЯЩЕЙ».
					     Здесь стояло только IsDescendantOf, и для СТАРОЙ модели этого
					     хватало: там груз — подмодель «anchor», а её детали ей потомки.
					     У новой лебёдки груз — ОДНА деталь, и сама себе потомком не
					     является: проверка давала false, деталь уходила в ветку «варим
					     к плоту», и якорь намертво прирастал к палубе. Снаружи это
					     выглядело как «якорь заанчорен и не опускается»: трос удлинялся,
					     а груз стоял. ]]
					local inHanging    = hanging
						and (desc == hanging or desc:IsDescendantOf(hanging))
					local inWheelRotor = wheel and desc:IsDescendantOf(wheel) and desc ~= hinge
					if inHanging or inWheelRotor then
						desc.Anchored = false
						pcall(function() desc:SetNetworkOwner(nil) end)
					else
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = desc
						weld.Part1 = raft.PrimaryPart
						weld.Parent = desc
						desc.Anchored = false
						pcall(function() desc:SetNetworkOwner(nil) end)
					end
				end
			end
			--[[ ⚠️ КОНТРОЛЬНЫЙ ПРОХОД: ГРУЗ ОБЯЗАН ОСТАТЬСЯ СВОБОДНЫМ.
			     Цикл выше мог до него не дойти (перебирает то, что нашёл в
			     модели), да и трос в новой модели приходит неподвязанным.
			     Один вызов закрывает оба случая сразу после постановки, а не
			     при первом нажатии кнопки. ]]
			AnchorRig.ensureRope(newAnchor)
			local freePart = AnchorRig.free(newAnchor)
			--[[ Одна строка на постановку: видно, какая деталь осталась свободной
			     и сколько приварено. «Свободна не та» — самая дорогая поломка
			     этой лебёдки, и без строки она видна только по тому, что модель
			     уплывает от плота. ]]
			local welded = 0
			for _, d in newAnchor:GetDescendants() do
				if d:IsA("WeldConstraint") and d.Part1 == raft.PrimaryPart then
					welded += 1
				end
			end
			print(("[Якорь] поставлено «%s»: свободен «%s», приварено к плоту %d")
				:format(newAnchor.Name, freePart and freePart.Name or "НИКТО", welded))
		end)

		-- Consume the Anchor_part tool — one craft = one placement.
		tool:Destroy()

		if _G.SendInventory then _G.SendInventory(player) end
		return

	elseif buildType == "raft" then
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end
		for res, need in pairs(RAFT_COSTS) do
			if (inv[res] or 0) < need then return end
		end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		-- Use the stable RestCFrame approach so the WeldConstraint captures the
		-- same local offset as all other tiles, regardless of current tilt.
		local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raft.PrimaryPart.CFrame
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
		local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
		local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE + phaseX + FLOOR_FINE_X, 0, gz * GRID_SIZE + phaseZ + FLOOR_FINE_Z))
			+ Vector3.new(0, deckCenterRestY(raft), 0) -- на уровень ЦЕНТРОВ геометрии досок
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		-- клетка = ЦЕНТР геометрии; пивот клона отводим на его смещение от центра,
		-- чтобы геометрия легла в клетку при любой конвенции пивота шаблона
		local worldCF = raft.PrimaryPart.CFrame * CFrame.new(localOffset)
			* getTileRotationCorrection(raft) * CFrame.new(-RAFT_PIVOT_DELTA)

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end
		-- клетка воды перед рыбацким местом — там рыбак забрасывает удочку (FishingSpotGrid)
		if typeof(_G.FishingFrontReserved) == "function" and _G.FishingFrontReserved((worldCF * CFrame.new(RAFT_PIVOT_DELTA)).Position) then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Здесь вода для рыбака", body = "Перед рыбацким местом строить нельзя" })
			end
			return
		end
		-- там стоит / идёт / отходит яхта торговца (MerchantYacht)
		if typeof(_G.MerchantYachtBlocks) == "function" and _G.MerchantYachtBlocks((worldCF * CFrame.new(RAFT_PIVOT_DELTA)).Position) then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Здесь яхта торговца", body = "Строй, когда она уплывёт" })
			end
			return
		end

		for res, need in pairs(RAFT_COSTS) do
			inv[res] = (inv[res] or 0) - need
		end

		local newPart = raftPartTemplate:Clone()
		newPart:SetAttribute("GridX", gx)
		newPart:SetAttribute("GridZ", gz)
		newPart:SetAttribute("BuildType", "raft")

		if newPart:IsA("Model") then
			-- ScaleTo НЕ вызываем при масштабе 1: он ставит АБСОЛЮТНЫЙ масштаб, и
			-- если у шаблона свой ScaleFactor ≠ 1 (после переделки моделей), клон
			-- раздувался до авторского размера — заметно больше шаблона.
			if TILE_SCALE ~= 1 then newPart:ScaleTo(TILE_SCALE) end
			newPart:PivotTo(worldCF)
		elseif newPart:IsA("BasePart") then
			newPart.CFrame = worldCF
		end
		place(function()
			newPart.Parent = raft
			weldToRaft(newPart, raft)
		end)

		-- Квест «Расширение плота» закрывается ровно здесь: клетка встала на плот.
		if typeof(_G.OnQuestEvent) == "function" then
			local ok, err = pcall(_G.OnQuestEvent, player, "built:RaftFloor", 1)
			print(("[Стройка] клетка (%d,%d) поставлена → квест built:RaftFloor: %s")
				:format(gx, gz, ok and "отправлено" or ("ОШИБКА " .. tostring(err))))
		else
			warn("[Стройка] _G.OnQuestEvent нет — квест расширения плота не засчитается")
		end

	elseif buildType == "stairs" then
		--[[ ЛЕСТНИЦА НА ВТОРОЙ ЭТАЖ (RaftStairs): на любую клетку пола. Клиент шлёт
		     сам тайл (как укрепление) и поворот; позу считает общий модуль, как у
		     призрака. Рампа — прозрачная, но твёрдая: по ней поднимается персонаж. ]]
		local tile, rot = ...
		if typeof(tile) ~= "Instance" or tile.Parent ~= raft then return end
		-- клетка первого этажа или пол второго (лестница на нём тоже ставится)
		if not (RaftReinforce.isFloorTile(tile) or tile.Name == "Raft_floor_upper"
			or tile:GetAttribute("BuildType") == "floor_upper") then return end
		rot = (type(rot) == "number") and (math.floor(rot) % 4) or 0
		local Stairs = require(rs:WaitForChild("RaftStairs"))
		for res, need in pairs(Stairs.COSTS) do
			if (inv[res] or 0) < need then return end
		end
		local template = AssetFind.find(Stairs.NAME)
		if not template then warn("[Стройка] нет модели Raft_stairs в ReplicatedStorage") return end
		local model = Stairs.prepare(template:Clone())
		model.Name = Stairs.NAME
		local cf = Stairs.placeCF(raft, tile, rot, model)
		if not cf then model:Destroy() return end
		if (char.HumanoidRootPart.Position - cf.Position).Magnitude > 80 then model:Destroy() return end
		if FarmPropRules.onFarmFootprint(raft, cf.Position) then model:Destroy() return end
		model:PivotTo(cf)
		if require(rs:WaitForChild("PlaceCheck")).refuseIfBlocked(model, raft, player) then model:Destroy() return end
		for res, need in pairs(Stairs.COSTS) do
			inv[res] = (inv[res] or 0) - need
		end
		local ramp = model:FindFirstChild(Stairs.RAMP, true)
		if ramp and ramp:IsA("BasePart") then
			ramp.Transparency = 1
			ramp.CanCollide = true
		end
		place(function()
			model.Parent = raft
			weldToRaft(model, raft)
		end)
		print(("[Стройка] %s поставил лестницу (поворот %d)"):format(player.Name, rot))

	elseif buildType == "reinforce" then
		-- УКРЕПЛЕНИЕ: новый тайл не ставится, у уже стоящей доски меняются меш и
		-- текстура. Клетка, сварка и координаты не трогаются вообще.
		--
		-- Клиент присылает САМУ ДОСКУ (он взял её рейкастом под курсором), а не
		-- координаты клетки: считать клетку заново незачем, да и на этом счёте
		-- ломались центр плота и место возле монолита. Проверяем, что это
		-- действительно доска ЭТОГО плота, — доверять присланному нельзя.
		local tile = ...
		if typeof(tile) ~= "Instance" or tile.Parent ~= raft then return end
		if not RaftReinforce.isFloorTile(tile) then return end
		if RaftReinforce.isReinforced(tile) then return end
		if (inv[RaftReinforce.COST_TYPE] or 0) < RaftReinforce.COST then return end

		local tilePos
		if tile:IsA("BasePart") then
			tilePos = tile.Position
		else
			local ok, bb = pcall(function() return tile:GetBoundingBox() end)
			tilePos = ok and bb.Position or nil
		end
		if not tilePos then return end
		if (char.HumanoidRootPart.Position - tilePos).Magnitude > 80 then return end

		inv[RaftReinforce.COST_TYPE] = (inv[RaftReinforce.COST_TYPE] or 0) - RaftReinforce.COST
		-- apply ЙИЛДИТ (грузит меш через AssetService), поэтому отдельным потоком:
		-- иначе обработчик ремоута висел бы на время загрузки ассета.
		task.spawn(function()
			if not RaftReinforce.apply(tile) then
				warn(("[Укрепление] в доске %s не нашлось меша настила"):format(tile:GetFullName()))
				return
			end
			-- укреплённый пол держит больше урона: пересчитать максимум ХП плота
			if _G.RecomputeRaftHP then _G.RecomputeRaftHP() end
		end)

	elseif buildType == "net" then
		-- СЕТЬ: та же клетка и то же соседство, что у доски (см. NET_COST выше).
		if not netTemplate then
			warn("[BuildingSystem] в ReplicatedStorage нет ни 'Raft_collector', ни 'Net_Part' — сеть не поставить")
			return
		end
		local gridX, gridZ = ...
		if type(gridX) ~= "number" or type(gridZ) ~= "number" then return end
		if (inv[NET_COST_ITEM] or 0) < NET_COST then return end

		local gx = math.round(gridX)
		local gz = math.round(gridZ)

		local offsets = getFloorOffsets(raft)
		if isFloorOccupied(offsets, gx, gz) then return end
		if not isFloorAdjacent(offsets, gx, gz) then return end

		local restCF = raft.PrimaryPart:GetAttribute("RestCFrame") or raft.PrimaryPart.CFrame
		local restYaw = raft.PrimaryPart:GetAttribute("RestYaw") or 0
		local restFlat = CFrame.new(Vector3.zero) * CFrame.Angles(0, restYaw, 0)
		local phaseX, phaseZ = getGridPhase(raft, GRID_SIZE)
		local worldOffset = restFlat:VectorToWorldSpace(Vector3.new(gx * GRID_SIZE + phaseX + FLOOR_FINE_X, 0, gz * GRID_SIZE + phaseZ + FLOOR_FINE_Z))
			+ Vector3.new(0, deckCenterRestY(raft), 0) -- на уровень ЦЕНТРОВ геометрии досок
		local localOffset = restCF:VectorToObjectSpace(worldOffset)
		-- CFrame клетки «под пивот доски»: как при постановке доски (ниже по коду
		-- из него обратно достаётся центр через +RAFT_PIVOT_DELTA)
		local raftCFforCell = raft.PrimaryPart.CFrame * CFrame.new(localOffset)
			* getTileRotationCorrection(raft) * CFrame.new(-RAFT_PIVOT_DELTA)
		-- ⚠️ ДВЕ РАЗНЫЕ ПОПРАВКИ, И НУЖНЫ ОБЕ: поворот (гасим поворот пивота модели,
		-- см. RaftNetFit) и центрирование (пивот сидит НЕ в центре геометрии, поэтому
		-- PivotTo по клетке уводит сеть по вертикали — она вставала ниже настила).
		-- ДЕРЖАТЬ РАВНЫМ клиентской копии netCFFromRaftCF.
		local centerPos = (raftCFforCell * CFrame.new(RAFT_PIVOT_DELTA)).Position
		-- клетка воды перед рыбацким местом (FishingSpotGrid) — сеть туда нельзя
		if typeof(_G.FishingFrontReserved) == "function" and _G.FishingFrontReserved(centerPos) then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Здесь вода для рыбака", body = "Перед рыбацким местом строить нельзя" })
			end
			return
		end
		if typeof(_G.MerchantYachtBlocks) == "function" and _G.MerchantYachtBlocks(centerPos) then
			if typeof(_G.NotifyPlayer) == "function" then
				_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Здесь яхта торговца", body = "Строй, когда она уплывёт" })
			end
			return
		end
		local worldCF = CFrame.new(centerPos) * (raftCFforCell * NET_ROT_FIX).Rotation
			* CFrame.new(-NET_PIVOT_DELTA)

		if (char.HumanoidRootPart.Position - worldCF.Position).Magnitude > 80 then return end

		inv[NET_COST_ITEM] = (inv[NET_COST_ITEM] or 0) - NET_COST

		local newPart = netTemplate:Clone()
		newPart.Name = NetFit.PLACED_NAME   -- имя в мире не зависит от имени шаблона
		newPart:SetAttribute("GridX", gx)
		newPart:SetAttribute("GridZ", gz)
		-- BuildType именно "raft": так вся уже существующая логика (занятость клетки,
		-- соседство, сохранение) считает сеть ПОЛНОЦЕННЫМ полом — вокруг неё можно
		-- строить и доски, и сети. TileKind различает их при загрузке сейва.
		newPart:SetAttribute("BuildType", "raft")
		newPart:SetAttribute("TileKind", "net")

		-- Масштаб НЕ трогаем: Net_Part в ReplicatedStorage уже размером с тайл
		-- (у доски клон приходит меньше сетки, поэтому ей нужен TILE_SCALE).
		if newPart:IsA("Model") then
			newPart:PivotTo(worldCF)
		elseif newPart:IsA("BasePart") then
			newPart.CFrame = worldCF
		end

		-- БЕЗ МАССЫ. BoatMovement каждый кадр компенсирует гравитацию силой
		-- totalMass * Gravity. Сеть — это пачка мешей, и её масса скачком меняет
		-- AssemblyMass: кадр между добавлением массы и пересчётом силы плот
		-- проседает, а стоящего на нём игрока подбрасывает по инерции. Massless
		-- убирает скачок совсем (ходить по сети это не мешает).
		for _, d in ipairs(newPart:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Massless = true
				d.CanCollide = true -- по сети ходят, коллизию оставляем
			end
		end
		if newPart:IsA("BasePart") then newPart.Massless = true end
		place(function()
			newPart.Parent = raft
			weldToRaft(newPart, raft)
		end)

	elseif buildType == "beam" then
		if not beamTemplate then return end
		local cx, cz = ...
		if type(cx) ~= "number" or type(cz) ~= "number" then return end
		if (inv.Log or 0) < BEAM_COST then return end

		cx = math.floor(cx) + 0.5
		cz = math.floor(cz) + 0.5

		local offsets = getFloorOffsets(raft)
		if not cornerHasFloor(offsets, cx, cz) then return end

		local bk = makeBeamKey(cx, cz)
		if getBeamKeys(raft)[bk] then return end

		local insetX, insetZ = computeBeamInset(offsets, cx, cz)
		local studX = cx * GRID_SIZE + insetX + BEAM_X_OFFSET
		local studZ = cz * GRID_SIZE + insetZ
		local worldPos, restYaw = localToWorld(raft, studX, studZ)
		worldPos = worldPos + Vector3.new(0, BEAM_HEIGHT * BEAM_SCALE / 2, 0)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end

		inv.Log = inv.Log - BEAM_COST

		local newBeam = beamTemplate:Clone()
		newBeam:SetAttribute("BuildType", "beam")
		newBeam:SetAttribute("BeamKey", bk)
		newBeam:SetAttribute("CornerX", cx)
		newBeam:SetAttribute("CornerZ", cz)

		local beamCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw, 0)
		if newBeam:IsA("Model") then
			newBeam:ScaleTo(BEAM_SCALE)
			newBeam:PivotTo(beamCF)
		else
			newBeam.CFrame = beamCF
		end
		place(function()
			newBeam.Parent = raft
			weldToRaft(newBeam, raft)
		end)

	elseif buildType == "wall_panel" then
		if not wallPanelTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < WALL_PANEL_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		-- Балок больше нет: нужен только примыкающий к ребру пол.
		-- Этаж 2 (5-й аргумент): ребро у пола второго этажа, высота — его верх.
		local level = (select(5, ...) == 2) and 2 or 1
		local upperTop = level == 2 and UpperFloor.edgeTop(raft, cx1, cz1, cx2, cz2) or nil
		if level == 2 then
			if not upperTop then return end
		elseif not edgeHasFloorImpl(isFloorOccupied, getFloorOffsets(raft), cx1, cz1, cx2, cz2) then return end

		local spanKey = UpperFloor.key(makeSpanKey(cx1, cz1, cx2, cz2), level)
		if getWallSpanKeys(raft)[spanKey] then return end
		local wpk = UpperFloor.key(makeWallPanelKey(cx1, cz1, cx2, cz2), level)

		-- Без балок: середина ребра прямо по сетке, без отступов под столбы.
		local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
		local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		-- высоту задаём абсолютно: localToWorld отвечает только за горизонталь
		local deckTop = upperTop or deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft)
		worldPos = Vector3.new(worldPos.X,
			deckTop + PANEL_HEIGHT / 2 - WallDefs.SINK, worldPos.Z)
		-- ВРЕМЕННАЯ ДИАГНОСТИКА: то же, что печатает клиент в превью.
		print(("[Стена/сервер] шаблон=%s высотаПанели=%.2f верхНастила=%.2f плотY=%.2f "
			.. "итогY=%.2f XZ=(%.1f, %.1f) клетка=(%.1f,%.1f)-(%.1f,%.1f)")
			:format(wallPanelTemplate and wallPanelTemplate.Name or "НЕТ",
				PANEL_HEIGHT, deckTop, raft.PrimaryPart.Position.Y,
				worldPos.Y, worldPos.X, worldPos.Z, cx1, cz1, cx2, cz2))

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end
		-- на клетках фермы и дома фермера стен нет: там забор (FarmPropRules)
		if level ~= 2 and FarmPropRules.onFarmFootprint(raft, worldPos) then return end

		inv.Log = inv.Log - WALL_PANEL_COST

		local newWall = wallPanelTemplate:Clone()
		newWall:SetAttribute("BuildType", "wall_panel")
		if level == 2 then newWall:SetAttribute("Level", 2) end
		newWall:SetAttribute("WallPanelKey", wpk)
		newWall:SetAttribute("WallSpanKey", spanKey)
		newWall:SetAttribute("BeamCX1", cx1)
		newWall:SetAttribute("BeamCZ1", cz1)
		newWall:SetAttribute("BeamCX2", cx2)
		newWall:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local wallCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newWall:IsA("Model") then
			newWall:PivotTo(WallDefs.pivotForCentre(newWall, wallCF))
		else
			newWall.CFrame = wallCF
		end
		place(function()
			newWall.Parent = raft
			weldToRaft(newWall, raft)
		end)

		-- Quest hook (Phase I): credit "Build N wall panels" objectives.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, "crafted:WallPanel", 1)
		end

	elseif buildType == "wall_arch" then
		if not wallArchTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < WALL_ARCH_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		-- Балок больше нет: нужен только примыкающий к ребру пол (или пол этажа 2).
		local level = (select(5, ...) == 2) and 2 or 1
		local upperTop = level == 2 and UpperFloor.edgeTop(raft, cx1, cz1, cx2, cz2) or nil
		if level == 2 then
			if not upperTop then return end
		elseif not edgeHasFloorImpl(isFloorOccupied, getFloorOffsets(raft), cx1, cz1, cx2, cz2) then return end

		local spanKey = UpperFloor.key(makeSpanKey(cx1, cz1, cx2, cz2), level)
		if getWallSpanKeys(raft)[spanKey] then return end
		local wak = UpperFloor.key(makeWallArchKey(cx1, cz1, cx2, cz2), level)

		-- Без балок: середина ребра прямо по сетке, без отступов под столбы.
		local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
		local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = Vector3.new(worldPos.X, (upperTop or deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft)) + ARCH_HEIGHT / 2 - WallDefs.SINK, worldPos.Z)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end
		-- на клетках фермы и дома фермера стен нет: там забор (FarmPropRules)
		if level ~= 2 and FarmPropRules.onFarmFootprint(raft, worldPos) then return end

		inv.Log = inv.Log - WALL_ARCH_COST

		local newArch = wallArchTemplate:Clone()
		newArch:SetAttribute("BuildType", "wall_arch")
		if level == 2 then newArch:SetAttribute("Level", 2) end
		newArch:SetAttribute("WallArchKey", wak)
		newArch:SetAttribute("WallSpanKey", spanKey)
		newArch:SetAttribute("BeamCX1", cx1)
		newArch:SetAttribute("BeamCZ1", cz1)
		newArch:SetAttribute("BeamCX2", cx2)
		newArch:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local archCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newArch:IsA("Model") then
			newArch:PivotTo(WallDefs.pivotForCentre(newArch, archCF))
		else
			newArch.CFrame = archCF
		end
		place(function()
			newArch.Parent = raft
			weldToRaft(newArch, raft)
		end)

	elseif EDGE_WALLS[buildType] then
		-- ⚠️ ТЕ ЖЕ КЛЮЧИ ПРОЛЁТА, ЧТО У СТЕНЫ И ПРОЁМА (WallSpanKey).
		-- Ребро клетки занимает что-то одно. Свой набор ключей означал бы две
		-- постройки внахлёст на одном ребре.
		local edge = EDGE_WALLS[buildType]
		if not edge.template then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		-- ⚠️ ПРОВЕРЯЕМ ВСЕ РЕСУРСЫ, А НЕ ТОЛЬКО ДЕРЕВО.
		-- У листвы цена из двух; прежняя проверка смотрела на одно поле cost и
		-- подразумевала Log, так что листья уходили бы даром.
		for res, need in pairs(edge.costs) do
			if (inv[res] or 0) < need then return end
		end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		local level = (select(5, ...) == 2) and 2 or 1
		local upperTop = level == 2 and UpperFloor.edgeTop(raft, cx1, cz1, cx2, cz2) or nil
		if level == 2 then
			if not upperTop then return end
		elseif not edgeHasFloorImpl(isFloorOccupied, getFloorOffsets(raft), cx1, cz1, cx2, cz2) then return end

		local spanKey = UpperFloor.key(makeSpanKey(cx1, cz1, cx2, cz2), level)
		if getWallSpanKeys(raft)[spanKey] then return end

		local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
		local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = Vector3.new(worldPos.X, (upperTop or deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft)) + edge.height / 2 - WallDefs.SINK, worldPos.Z)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end
		-- на клетках фермы и дома фермера стен нет: там забор (FarmPropRules)
		if level ~= 2 and FarmPropRules.onFarmFootprint(raft, worldPos) then return end

		for res, need in pairs(edge.costs) do
			inv[res] = (inv[res] or 0) - need
		end

		local newWall = edge.template:Clone()
		newWall:SetAttribute("BuildType", buildType)
		if level == 2 then newWall:SetAttribute("Level", 2) end
		newWall:SetAttribute("WallSpanKey", spanKey)
		newWall:SetAttribute("BeamCX1", cx1)
		newWall:SetAttribute("BeamCZ1", cz1)
		newWall:SetAttribute("BeamCX2", cx2)
		newWall:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local placeCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newWall:IsA("Model") then
			newWall:PivotTo(WallDefs.pivotForCentre(newWall, placeCF))
		else
			newWall.CFrame = placeCF
		end
		place(function()
			newWall.Parent = raft
			weldToRaft(newWall, raft)
		end)

	elseif buildType == UpperFloor.BUILD_TYPE then
		--[[ ПОЛ ВТОРОГО ЭТАЖА: только над клеткой первого этажа с четырьмя
		     БОЛЬШИМИ стенами, высота — по верху стен. Правила и геометрия —
		     RaftUpperFloor (их же читает превью). ]]
		local template = UpperFloor.template()
		if not template then warn("[Стройка] нет модели Raft_floor_upper в ReplicatedStorage") return end
		local gx, gz = ...
		if type(gx) ~= "number" or type(gz) ~= "number" then return end
		gx, gz = math.round(gx), math.round(gz)
		for res, need in pairs(UpperFloor.COSTS) do
			if (inv[res] or 0) < need then return end
		end
		if UpperFloor.findAt(raft, gx, gz) then return end
		local offsets = getFloorOffsets(raft)
		local walls, why = UpperFloor.supports(raft, gx, gz, function(x, z) return isFloorOccupied(offsets, x, z) end)
		if not walls then
			print(("[Стройка] второй этаж (%d,%d) отклонён: %s"):format(gx, gz, tostring(why)))
			return
		end
		local wantCF = UpperFloor.centreCF(raft, walls, WallDefs.heightOf(template))
		if not wantCF then return end
		if (char.HumanoidRootPart.Position - wantCF.Position).Magnitude > 80 then return end

		for res, need in pairs(UpperFloor.COSTS) do
			inv[res] = (inv[res] or 0) - need
		end
		local newFloor = template:Clone()
		newFloor:SetAttribute("BuildType", UpperFloor.BUILD_TYPE)
		newFloor:SetAttribute("UpperGX", gx)
		newFloor:SetAttribute("UpperGZ", gz)
		if newFloor:IsA("Model") then
			newFloor:PivotTo(WallDefs.pivotForCentre(newFloor, wantCF))
		else
			newFloor.CFrame = wantCF
		end
		place(function()
			newFloor.Parent = raft
			weldToRaft(newFloor, raft)
		end)
		if _G.RecomputeRaftHP then _G.RecomputeRaftHP() end
		print(("[Стройка] пол второго этажа поставлен над клеткой (%d,%d), Y=%.2f"):format(gx, gz, wantCF.Position.Y))

	elseif buildType == "door" then
		if not doorTemplate then return end
		local cx1, cz1, cx2, cz2 = ...
		if type(cx1) ~= "number" or type(cz1) ~= "number" or type(cx2) ~= "number" or type(cz2) ~= "number" then return end
		if (inv.Log or 0) < DOOR_COST then return end

		cx1 = math.floor(cx1) + 0.5
		cz1 = math.floor(cz1) + 0.5
		cx2 = math.floor(cx2) + 0.5
		cz2 = math.floor(cz2) + 0.5

		local dx = math.abs(cx1 - cx2)
		local dz = math.abs(cz1 - cz2)
		if not ((dx == 1 and dz == 0) or (dx == 0 and dz == 1)) then return end

		-- A door requires a wall_arch on the same span and no existing door.
		local level = (select(5, ...) == 2) and 2 or 1
		local upperTop = level == 2 and UpperFloor.edgeTop(raft, cx1, cz1, cx2, cz2) or nil
		if level == 2 and not upperTop then return end
		local wak = UpperFloor.key(makeWallArchKey(cx1, cz1, cx2, cz2), level)
		if not getWallArchKeys(raft)[wak] then return end
		local dk = UpperFloor.key(makeDoorKey(cx1, cz1, cx2, cz2), level)
		if getDoorKeys(raft)[dk] then return end

		-- Без балок: середина ребра прямо по сетке, без отступов под столбы.
		local midStudX = (cx1 + cx2) / 2 * GRID_SIZE
		local midStudZ = (cz1 + cz2) / 2 * GRID_SIZE
		local worldPos, restYaw = localToWorld(raft, midStudX, midStudZ)
		worldPos = Vector3.new(worldPos.X, (upperTop or deckTopForEdge(raft, cx1, cz1, cx2, cz2) or deckTopWorldY(raft)) + DOOR_HEIGHT / 2 - WallDefs.SINK, worldPos.Z)

		if (char.HumanoidRootPart.Position - worldPos).Magnitude > 80 then return end
		-- на клетках фермы и дома фермера стен нет: там забор (FarmPropRules)
		if level ~= 2 and FarmPropRules.onFarmFootprint(raft, worldPos) then return end

		inv.Log = inv.Log - DOOR_COST

		local newDoor = doorTemplate:Clone()
		newDoor:SetAttribute("BuildType", "door")
		if level == 2 then newDoor:SetAttribute("Level", 2) end
		newDoor:SetAttribute("DoorKey", dk)
		newDoor:SetAttribute("BeamCX1", cx1)
		newDoor:SetAttribute("BeamCZ1", cz1)
		newDoor:SetAttribute("BeamCX2", cx2)
		newDoor:SetAttribute("BeamCZ2", cz2)

		local sideAngle = (cx1 == cx2) and math.rad(90) or 0
		local doorCF = CFrame.new(worldPos) * CFrame.Angles(0, restYaw + sideAngle, 0)
		if newDoor:IsA("Model") then
			newDoor:PivotTo(WallDefs.pivotForCentre(newDoor, doorCF))
		else
			newDoor.CFrame = doorCF
		end
		place(function()
			newDoor.Parent = raft
			-- Doors need a Motor6D-based weld so the panel can swing without
			-- fighting the raft's rigid weld network. Fall back to the plain
			-- weld routine if the DoorController hasn't loaded yet.
			if _G.SetupDoor then
				_G.SetupDoor(newDoor, raft)
			else
				weldToRaft(newDoor, raft)
			end
		end)
	end

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	placeBlockEvent:FireClient(player, "placed")
end)
-- ПОДБОР ОТВАЛИВШИХСЯ ДОСОК. Одна из стартовых досок лежала не ВНУТРИ модели Raft,
-- а рядом в Workspace. Приваренная — плавает вместе с плотом и на вид ничем не
-- отличается, — но ни один обход плота её не видел: клетка считалась ПУСТОЙ (в неё
-- спокойно вставала новая доска), ХП плоту она не давала, в сейв не попадала и не
-- укреплялась. Забираем такие доски внутрь модели.
--
-- Признаков два, и оба обязательны: деталь в ОДНОЙ СБОРКЕ с плотом (то есть реально
-- приварена, а не просто рядом плавает) и в ней есть меш настила. Порядок проверок
-- важен: сборка проверяется первой, она дешёвая, а обход потомков — нет.
local function adoptStrayFloors(raft)
	local root = raft.PrimaryPart and raft.PrimaryPart.AssemblyRootPart
	if not root then return 0 end
	local adopted = 0
	for _, child in ipairs(workspace:GetChildren()) do
		if child ~= raft and (child:IsA("Model") or child:IsA("BasePart")) then
			local part = child:IsA("BasePart") and child
				or child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
			if part and part.AssemblyRootPart == root and RaftReinforce.isFloorTile(child) then
				child.Parent = raft
				adopted += 1
				warn(("[Плот] доска %s лежала ВНЕ модели Raft — забрал внутрь")
					:format(child.Name))
			end
		end
	end
	return adopted
end

-- САМОЛЕЧЕНИЕ АТРИБУТОВ ПРИ СТАРТЕ. Стартовые тайлы нового плота собраны в
-- Studio копированием, и копии приносят чужие GridX/GridZ: сейв и стройка
-- схлопывали девять досок в одну клетку. getFloorOffsets сверяет атрибуты с
-- фактической позицией и чинит расхождения — прогоняем один раз на старте,
-- чтобы вылечить пол ДО первого сохранения, а не при первой постройке.
task.spawn(function()
	local raft = workspace:WaitForChild("Raft", 30)
	if not raft then return end
	local t0 = os.clock()
	while not raft.PrimaryPart and os.clock() - t0 < 30 do task.wait(0.5) end
	if not raft.PrimaryPart then return end
	task.wait(2) -- дать BoatMovement выставить RestYaw
	local adopted = adoptStrayFloors(raft)   -- ДО сверки клеток: подобранные тоже лечим
	if adopted > 0 then
		print(("[Плот] подобрано досок вне модели: %d — пересчитываю клетки"):format(adopted))
		if _G.RecomputeRaftHP then _G.RecomputeRaftHP() end
	end
	getFloorOffsets(raft)
	print("[BuildingSystem] стартовая сверка клеток пола выполнена")
end)

--[[ СТОРОЖ ОПОР ВТОРОГО ЭТАЖА. Стену под полом может снести кто угодно: топор
     игрока, пиявка, ядро корабля — у каждого своя ручка удаления. Вместо правки
     каждой из них раз в секунду сверяем: стоит ли под полом второго этажа вся
     четвёрка больших стен и клетка первого этажа. Нет — пол рушится.
     ⚠️ ОТСРОЧКА GRACE: загрузка сейва ставит объекты по одному, и пол может
     приехать раньше своих стен. Свежий пол первые секунды не трогаем. ]]
task.spawn(function()
	local GRACE = 6
	local seenAt = setmetatable({}, { __mode = "k" })
	while true do
		task.wait(1)
		local raft = getRaft()
		if raft and raft.PrimaryPart then
			local offsets = nil
			for _, child in ipairs(raft:GetChildren()) do
				if child:GetAttribute("BuildType") == UpperFloor.BUILD_TYPE then
					seenAt[child] = seenAt[child] or os.clock()
					if os.clock() - seenAt[child] > GRACE then
						offsets = offsets or getFloorOffsets(raft)
						local gx, gz = child:GetAttribute("UpperGX"), child:GetAttribute("UpperGZ")
						local ok = type(gx) == "number" and type(gz) == "number"
							and UpperFloor.supports(raft, gx, gz, function(x, z) return isFloorOccupied(offsets, x, z) end)
						if not ok then
							print(("[Стройка] пол второго этажа (%s,%s) остался без опоры — рухнул"):format(tostring(gx), tostring(gz)))
							child:Destroy()
							if _G.RecomputeRaftHP then _G.RecomputeRaftHP() end
						end
					end
				end
				-- стены / проёмы / двери второго этажа без пола под ними падают вместе с ним
				if child:GetAttribute("Level") == 2 and child:GetAttribute("BeamCX1") then
					seenAt[child] = seenAt[child] or os.clock()
					if os.clock() - seenAt[child] > GRACE and not UpperFloor.edgeTop(raft,
						child:GetAttribute("BeamCX1"), child:GetAttribute("BeamCZ1"),
						child:GetAttribute("BeamCX2"), child:GetAttribute("BeamCZ2")) then
						print(("[Стройка] %s второго этажа осталась без пола — рухнула"):format(child.Name))
						child:Destroy()
					end
				end
			end
		end
	end
end)

--[[ ЛЕСТНИЦА: рампа — невидимая, но твёрдая. И у шаблона (из него рисуется
     иконка молотка), и у каждой лестницы на плоту, в том числе из сохранения
     (сейв клонирует шаблон). Всё в do-блоке: у файла лимит локалей. ]]
task.spawn(function()
	local function fixRamp(m)
		if not (m:IsA("Model") and m.Name == "Raft_stairs") then return end
		local r = m:FindFirstChild("raft_stairs_ramp", true)
		if r and r:IsA("BasePart") then
			r.Transparency = 1
			r.CanCollide = true
		end
	end
	local tpl = AssetFind.find("Raft_stairs")
	if tpl then fixRamp(tpl) end
	local raft = workspace:WaitForChild("Raft", 60)
	if not raft then return end
	for _, c in ipairs(raft:GetChildren()) do fixRamp(c) end
	raft.ChildAdded:Connect(function(c) task.defer(fixRamp, c) end)
end)
