local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- RaftDetach.lua (ModuleScript, вызывается С СЕРВЕРА)
-- ОТРЫВ КУСКА ПЛОТА С КАСКАДОМ.
--
-- Когда тайл пола уходит (сеть догрызла пиявка, доску разбили и т.п.), вместе с
-- ним должно уйти ВСЁ, что держалось только через него: отрезанные от центра
-- тайлы и постройки, стоящие на них. Иначе в море остаётся висеть кусок палубы,
-- ни к чему не прикреплённый.
--
-- Как считаем: плот — это сетка клеток (атрибуты GridX/GridZ у тайлов, начальные
-- Raft_part вычисляются по позиции). Убираем упавшую клетку и обходим сетку в
-- ширину от центра (0,0). Всё, до чего не дошли, — отрезано и тонет.

local RunService = game:GetService("RunService")

local RaftDetach = {}

local GRID_SIZE = 10 -- как в BuildingSystem (шаг клетки палубы, новый плот 10x10)
local SINK_SPEED = 6
local SINK_TIME  = 12

-- НА КАКОМ РАССТОЯНИИ КЛЕТКИ СЧИТАЮТСЯ СОСЕДЯМИ. Чуть больше шага сетки, чтобы
-- пережить мелкие неточности установки, но заметно меньше диагонали (13.9).
local NEIGHBOR_DIST = GRID_SIZE * 1.25

local function tilePos(inst)
	local pos
	if inst:IsA("Model") then
		local ok = pcall(function() pos = inst:GetPivot().Position end)
		if not ok then pos = nil end
	elseif inst:IsA("BasePart") then
		pos = inst.Position
	end
	return pos
end

-- Все клетки пола: массив {model=…, pos=Vector3}.
--
-- Раньше здесь строилась СЕТКА координат: у построенных тайлов брались атрибуты
-- GridX/GridZ, у стартовых — номер клетки по позиции. Две нумерации считались
-- по-разному и разъезжались, граф связности рассыпался, и «отрезанным» оказывался
-- нормальный, ничем не задетый пол — плот ломался в стороне от дыры. Теперь
-- соседство определяется по реальному расстоянию между клетками: никакой общей
-- системы координат для этого не нужно, а значит и разъезжаться нечему.
local function collectTiles(raft)
	local tiles = {}
	for _, child in ipairs(raft:GetChildren()) do
		local isTile = child:GetAttribute("BuildType") == "raft"
			or child.Name == "Raft_part" or child.Name == "Net_Part"
		if isTile then
			local pos = tilePos(child)
			if pos then tiles[#tiles + 1] = { model = child, pos = pos } end
		end
	end
	return tiles
end

-- Клетки, ДОСТИЖИМЫЕ от корневой обходом в ширину по соседям вплотную.
local function reachableFrom(tiles, rootPos)
	local seen = {}
	if #tiles == 0 then return seen end

	-- корень — клетка, ближайшая к центру плота: ядро обязано выжить всегда
	local start, bestD
	for i, t in ipairs(tiles) do
		local dx, dz = t.pos.X - rootPos.X, t.pos.Z - rootPos.Z
		local d = dx * dx + dz * dz
		if not bestD or d < bestD then start, bestD = i, d end
	end

	local queue = { start }
	seen[start] = true
	while #queue > 0 do
		local cur = tiles[table.remove(queue)]
		for i, t in ipairs(tiles) do
			if not seen[i] then
				local dx, dz = t.pos.X - cur.pos.X, t.pos.Z - cur.pos.Z
				if dx * dx + dz * dz <= NEIGHBOR_DIST * NEIGHBOR_DIST then
					seen[i] = true
					queue[#queue + 1] = i
				end
			end
		end
	end
	return seen
end

-- Постройки, стоящие НА этих клетках (пушки, факелы, кровати и т.п.).
-- Определяем по горизонтальному расстоянию до центра клетки.
local function objectsOnTiles(raft, tileList)
	local found = {}
	for _, child in ipairs(raft:GetChildren()) do
		local isTile = child:GetAttribute("BuildType") == "raft"
			or child.Name == "Raft_part" or child.Name == "Net_Part"
		if not isTile and child ~= raft.PrimaryPart then
			local pos
			if child:IsA("Model") then
				local ok = pcall(function() pos = child:GetPivot().Position end)
				if not ok then pos = nil end
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				for _, t in ipairs(tileList) do
					local tp
					if t.model:IsA("Model") then
						local ok = pcall(function() tp = t.model:GetPivot().Position end)
						if not ok then tp = nil end
					else
						tp = t.model.Position
					end
					if tp then
						local dx, dz = pos.X - tp.X, pos.Z - tp.Z
						if (dx * dx + dz * dz) <= (GRID_SIZE * 0.6) ^ 2 then
							found[#found + 1] = child
							break
						end
					end
				end
			end
		end
	end
	return found
end

-- Утопить пачку моделей одним куском.
local function sinkAll(models, raft)
	local parts = {}
	local inSet = {}
	for _, m in ipairs(models) do
		if m:IsA("BasePart") then
			parts[#parts + 1] = m
			inSet[m] = true
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				parts[#parts + 1] = d
				inSet[d] = true
			end
		end
	end
	if #parts == 0 then return end

	-- рвём только стыки, связывающие уходящий кусок с ОСТАВШИМСЯ плотом
	if raft then
		for _, d in ipairs(raft:GetDescendants()) do
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
				local a = d.Part0 and inSet[d.Part0]
				local b = d.Part1 and inSet[d.Part1]
				if (a or b) and not (a and b) then d:Destroy() end
			end
		end
	end

	local folder = Instance.new("Model")
	folder.Name = "SinkingDebris"
	folder.Parent = workspace

	for _, m in ipairs(models) do
		-- освобождаем клетку в учёте пола, иначе туда нельзя будет строить
		m:SetAttribute("BuildType", nil)
		m:SetAttribute("GridX", nil)
		m:SetAttribute("GridZ", nil)
		m.Parent = folder
	end
	for _, p in ipairs(parts) do
		p.Anchored = true -- топим ровно и предсказуемо, без кувырков
		p.CanCollide = false
	end

	task.spawn(function()
		local t0 = os.clock()
		while folder.Parent and os.clock() - t0 < SINK_TIME do
			local dt = RunService.Heartbeat:Wait()
			pcall(function()
				folder:PivotTo(folder:GetPivot() * CFrame.new(0, -SINK_SPEED * dt, 0))
			end)
		end
		if folder.Parent then folder:Destroy() end
	end)
end

-- ГЛАВНОЕ: убрать тайл `lost` и утопить его вместе со всем отрезанным.
-- Возвращает количество утонувших моделей.
--
-- instant = true — не топить, а удалить сразу. Нужно разбору плота топором:
-- игрок ломает клетку и она исчезает, а не уплывает обломком; отрезанные
-- куски при этом всё равно считаются той же связностью, чтобы в море не
-- оставалось висеть ни к чему не прикреплённых досок.
function RaftDetach.detachTile(raft, lost, instant)
	if not (raft and lost and lost.Parent == raft) then return 0 end

	local all = collectTiles(raft)
	-- убираем уходящий тайл из набора: связность считаем уже без него
	local tiles = {}
	for _, t in ipairs(all) do
		if t.model ~= lost then tiles[#tiles + 1] = t end
	end
	local total = #tiles

	-- КОРЕНЬ ОБХОДА — клетка у центра плота: ядро обязано выжить всегда.
	local rootPos = (raft.PrimaryPart and raft.PrimaryPart.Position)
		or tilePos(lost) or Vector3.zero
	local reachable = reachableFrom(tiles, rootPos)

	local doomedTiles = {}
	for i, t in ipairs(tiles) do
		if not reachable[i] then doomedTiles[#doomedTiles + 1] = t end
	end

	-- ПРЕДОХРАНИТЕЛЬ. Потеря одной клетки не может отрезать треть плота: если
	-- насчитали столько — значит разметка пола врёт (тайл нестандартного размера,
	-- сдвинутая клетка, чужой пивот), и топить надо только сам потерянный тайл.
	-- Порог намеренно строгий: разбор топором уже один раз снёс игроку почти весь
	-- плот из-за ошибки связности. Утопить лишнюю доску не страшно, утопить
	-- игроку плот — катастрофа.
	if total > 0 and #doomedTiles * 3 >= total then
		warn(("[RaftDetach] обход насчитал %d отрезанных клеток из %d — похоже на сбой "
			.. "разметки пола; топим только %s"):format(#doomedTiles, total, lost.Name))
		doomedTiles = {}
	end

	local doomed = { lost }
	for _, t in ipairs(doomedTiles) do doomed[#doomed + 1] = t.model end

	-- постройки, стоящие на уходящих клетках
	local allDoomedTiles = { { model = lost } }
	for _, t in ipairs(doomedTiles) do allDoomedTiles[#allDoomedTiles + 1] = t end
	for _, obj in ipairs(objectsOnTiles(raft, allDoomedTiles)) do
		doomed[#doomed + 1] = obj
	end

	if instant then
		-- Рвём стыки с оставшимся плотом и удаляем без анимации.
		local inSet = {}
		for _, m in ipairs(doomed) do
			if m:IsA("BasePart") then inSet[m] = true end
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then inSet[d] = true end
			end
		end
		for _, d in ipairs(raft:GetDescendants()) do
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
				local a = d.Part0 and inSet[d.Part0]
				local b = d.Part1 and inSet[d.Part1]
				if (a or b) and not (a and b) then d:Destroy() end
			end
		end
		for _, m in ipairs(doomed) do
			if m.Parent then m:Destroy() end
		end
		return #doomed
	end

	sinkAll(doomed, raft)
	return #doomed
end

return RaftDetach
