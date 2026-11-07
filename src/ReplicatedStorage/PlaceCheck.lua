--[[ PlaceCheck — ОДНА ПРОВЕРКА «МЕСТО ЗАНЯТО» ДЛЯ ВСЕХ УСТАНОВОК НА ПЛОТ.

     Мангал ставился прямо в лежанку, костёр — в очиститель: у каждой из
     двенадцати систем установки своя ручка «поставить», и ни одна не смотрела,
     что уже стоит в клетке. Владелец: «сделай, чтобы я не мог ставить предметы
     в предметы». Проверка одна, чтобы новая постройка получала её одной строкой.

     Как: у уже поставленного (и повёрнутого) клона берём габаритный бокс, чуть
     ужимаем (соседи впритык — не помеха) и спрашиваем физику, чьи детали в нём.
     Пол, корень плота и NPC (дайвер, механик) занятостью не считаются. Всё
     остальное, что стоит НА ПЛОТУ, — считается: предметы, стены, станции.

     Зовётся на сервере ПОСЛЕ PivotTo и ДО Parent = raft: клон ещё не в мире,
     так что сам себя не найдёт, а в случае отказа просто уничтожается. ]]

local PlaceCheck = {}

local FLOOR_NAMES = { Raft_part = true, Net_Part = true }
local SHRINK = 0.8   -- доля бокса: люфт на стык с соседом

local function isFloor(inst)
	return FLOOR_NAMES[inst.Name] == true or inst:GetAttribute("BuildType") == "raft"
end
--[[ ⚠️ ПОЛ ВТОРОГО ЭТАЖА — ТОЖЕ ПОЛ. Без этого слой «под предметом» (шаг 2)
     находил сам этот пол и отказывал: «Место занято: Raft_floor_upper», — и на
     второй этаж нельзя было поставить ни грядку, ни мебель. А стоящему на нём
     предмету под полом мешают верхушки стен первого этажа (опоры пола): слой
     толщиной 2.5 studs пробивает тонкий пол насквозь — их тоже не считаем. ]]
local function isUpperFloor(inst)
	return inst:GetAttribute("BuildType") == "floor_upper" or inst.Name == "Raft_floor_upper"
end
local function isGroundWall(inst)
	return inst:GetAttribute("WallSpanKey") ~= nil and inst:GetAttribute("Level") ~= 2
end
--[[ КОВРИК — НАСТИЛ, А НЕ ПРЕДМЕТ. На него можно ставить стул, стол, мангал:
     для них он как пол. А сам коврик ложится только на пол — для коврика
     другой коврик и любой предмет по-прежнему помеха. ]]
local FLOORING = { RaftDecor_rug = true }
PlaceCheck.FLOORING = FLOORING
--[[ СТОЛ — ПОДСТАВКА ДЛЯ МЕЛОЧИ. Цветок в банке и фонарь ставятся на стол:
     для них столешница — опора, а не «место занято». Остальным стол мешает. ]]
local TABLES   = { Raft_table_leaves = true, RaftDecor_spool_table = true }
local ON_TABLE = { RaftDecor_can_flower = true, RaftDecor_lantern = true }
PlaceCheck.TABLES, PlaceCheck.ON_TABLE = TABLES, ON_TABLE

-- прямой ребёнок плота, которому принадлежит деталь (или nil, если не на плоту)
local function raftChildOf(part, raft)
	local node = part
	while node and node.Parent ~= raft do
		node = node.Parent
		if node == nil or node == workspace then return nil end
	end
	return node
end

--[[ ВНУТРИ ТАВЕРНЫ НИЧЕГО НЕ СТАВИМ. Таверна (IslandHall) — готовый дом со своим
     интерьером и местом сборки жителя; ни декор, ни станции, ни грядки внутрь
     не ставятся. Возвращает таверну, если точка на её клетках 2×2 (от точки
     посадки AssemblyOrigin, в осях плота), иначе nil. ]]
local NO_BUILD_INSIDE = { IslandHall = true }
function PlaceCheck.insideHall(raft, pos, except)
	local primary = raft and raft.PrimaryPart
	if not primary then return nil end
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then local _, y = primary.CFrame:ToEulerAnglesYXZ(); yaw = y end
	local flat = CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
	local p = flat:PointToObjectSpace(pos)
	for _, m in ipairs(raft:GetChildren()) do
		if NO_BUILD_INSIDE[m.Name] and m ~= except and m:IsA("Model") and not m:GetAttribute("PlacementGhost") then
			local o = m:FindFirstChild("AssemblyOrigin")
			if o and o:IsA("BasePart") then
				local c = flat:PointToObjectSpace(o.Position)
				if math.abs(p.X - c.X) < 10 and math.abs(p.Z - c.Z) < 10 then return m end
			end
		end
	end
	return nil
end

--[[ Возвращает модель, которая мешает, либо nil. model — уже позиционированный
     клон (ещё не в мире или уже в нём — сам себя он не считает). ]]
function PlaceCheck.blocked(model, raft)
	if not (model and raft) then return nil end
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok or not cf then return nil end
	if model:IsA("BasePart") then cf, size = model.CFrame, model.Size end
	do
		local hall = PlaceCheck.insideHall(raft, cf.Position, model)
		if hall then return hall end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local function offender(parts, under)
		-- стоим на полу второго этажа → стены первого этажа под ним не помеха
		local onUpper = false
		if under then
			for _, part in ipairs(parts) do
				local top = raftChildOf(part, raft)
				if top and isUpperFloor(top) then onUpper = true break end
			end
		end
		for _, part in ipairs(parts) do
			local top = raftChildOf(part, raft)
			if top and top ~= raft.PrimaryPart and not isFloor(top)
				-- ⚠️ пол второго этажа не помеха и в ОБЪЁМЕ, а не только «под»: грядка на нём
				-- низом касается плиты, и ужатый бокс задевал её — «Место занято: Пол второго этажа»
				and not isUpperFloor(top)
				and not (onUpper and isGroundWall(top))
				and not (FLOORING[top.Name] and not FLOORING[model.Name])
				and not (TABLES[top.Name] and ON_TABLE[model.Name])
				and not (top:IsA("Model") and top:FindFirstChildWhichIsA("Humanoid", true)) then
				return top
			end
		end
		return nil
	end
	-- 1) пересечение объёмов
	local hit = offender(workspace:GetPartBoundsInBox(cf, size * SHRINK, params))
	if hit then return hit end
	--[[ 2) ОПОРА. Мангал вставал НА дистиллятор: постановка прицелилась в его
	     верх, объёмы лишь касались, и ужатая коробка касания не видела. Поэтому
	     смотрим тонкий слой под низом предмета: там может быть только пол. ]]
	local bottom = cf * CFrame.new(0, -size.Y * 0.5, 0)
	local underCF = CFrame.new(bottom.Position) * cf.Rotation
	local underSize = Vector3.new(size.X * SHRINK, 2.5, size.Z * SHRINK)
	return offender(workspace:GetPartBoundsInBox(underCF, underSize, params), true)
end

--[[ Деталь — пол плота (клетка, корень, пол второго этажа)? Для настила:
     коврик кладётся только туда, куда попал луч по полу. ]]
function PlaceCheck.isFloorPart(part, raft)
	local top = raftChildOf(part, raft)
	return top ~= nil and (top == raft.PrimaryPart or isFloor(top) or isUpperFloor(top))
end

-- под центром модели пол плота? (сервер, для настила)
function PlaceCheck.onFloor(model, raft)
	local cf, size = model:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, size.Y * 0.5 + 0.5, 0),
		Vector3.new(0, -(size.Y + 2), 0), params)
	return hit ~= nil and PlaceCheck.isFloorPart(hit.Instance, raft)
end

--[[ ══════════ НАСТЕННЫЙ ДЕКОР ══════════
     Штурвал, спасательный круг, полка, гирлянда вешаются ТОЛЬКО на стену плота —
     не на пол и не в пустоту. Одно правило для призрака и сервера (DecorPlace).
     ⚠️ Живёт здесь, а не отдельным модулем: новый файл до запущенной сессии Rojo
     доезжает не всегда, и require(WaitForChild) повесил бы установку декора.

     Стена — ребёнок плота с WallSpanKey (стена, окно, полустена, листва, ограда,
     проём). Предмет прижат тыльной стороной: тонкая горизонтальная ось — по
     нормали стены. R — другой стороной. Гирлянда (SNAP) сама встаёт по центру
     пролёта под верхний край — она ровно на одну клетку. ]]
PlaceCheck.WALL_NAMES = { RaftDecor_wheel = true, RaftDecor_lifebuoy = true,
	RaftDecor_shelf = true, RaftDecor_bunting = true }
local WALL_SNAP = { RaftDecor_bunting = true }
local WALL_GAP = 0.03   -- зазор от стены, чтобы не мерцали совпавшие грани

function PlaceCheck.wallOf(part, raft)
	local top = raftChildOf(part, raft)
	if top and top:GetAttribute("WallSpanKey") ~= nil then return top end
	return nil
end

local function thinAxis(size)
	if size.X < size.Z then return "X", size.X end
	return "Z", size.Z
end

--[[ Поза центра модели на стене (nil — попали в торец/верх, а не в бок).
     size — габарит модели в её осях, wall — стена (для привязки гирлянды). ]]
function PlaceCheck.wallCF(name, hitPos, normal, size, flip, wall)
	local n = Vector3.new(normal.X, 0, normal.Z)
	if n.Magnitude < 0.5 then return nil end
	n = n.Unit
	local axis, depth = thinAxis(size)
	local pos = hitPos + n * (depth * 0.5 + WALL_GAP)
	if WALL_SNAP[name] and wall then
		local wcf, wsize = wall:GetBoundingBox()
		if wall:IsA("BasePart") then wcf, wsize = wall.CFrame, wall.Size end
		local along = Vector3.new(-n.Z, 0, n.X)
		pos = pos - along * (pos - wcf.Position):Dot(along)
		local halfH = math.abs(wcf.RightVector.Y) * wsize.X * 0.5
			+ math.abs(wcf.UpVector.Y) * wsize.Y * 0.5
			+ math.abs(wcf.LookVector.Y) * wsize.Z * 0.5
		pos = Vector3.new(pos.X, wcf.Position.Y + halfH - size.Y * 0.5 - 0.15, pos.Z)
	end
	local cf = CFrame.lookAt(pos, pos + n)
	if axis == "X" then cf = cf * CFrame.Angles(0, math.rad(90), 0) end
	if flip then cf = cf * CFrame.Angles(0, math.pi, 0) end
	return cf
end

--[[ Сервер: за поставленной моделью стена плота? Лучи по тонкой оси в обе
     стороны — из центра и из точек по ширине (у окна середина бывает пустой). ]]
function PlaceCheck.hasWallBehind(model, raft, ignore)
	local cf, size = model:GetBoundingBox()
	local axis, depth = thinAxis(size)
	local dir  = axis == "X" and cf.RightVector or cf.LookVector
	local wide = axis == "X" and cf.LookVector or cf.RightVector
	local width = axis == "X" and size.Z or size.X
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, ignore }
	for _, k in ipairs({ 0, 0.3, -0.3 }) do
		local from = cf.Position + wide * (width * k)
		for _, sgn in ipairs({ 1, -1 }) do
			local hit = workspace:Raycast(from, dir * sgn * (depth * 0.5 + 1.2), params)
			if hit and PlaceCheck.wallOf(hit.Instance, raft) then return true end
		end
	end
	return false
end

--[[ ИМЯ ПРЕДМЕТА ДЛЯ ИГРОКА, А НЕ ИМЯ МОДЕЛИ. «Raft_grill_barrel» в уведомлении
     читать нельзя. Сначала общий справочник ItemNamesRu (он знает тулы и
     рецепты), затем свой список моделей плота, затем по подстроке. ]]
local ItemNamesRu = nil
pcall(function() ItemNamesRu = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemNamesRu", 5)) end)
local MODEL_RU = {
	raft_grill = "Мангал", grill = "Мангал",
	raft_bed_leaf = "Лежанка", bed = "Лежанка",
	raft_planter = "Грядка", garden = "Грядка",
	destitalor = "Очиститель воды", purifier = "Очиститель воды",
	raft_smelter = "Плавильня",
	raft_repair_station = "Ремонтная станция",
	monolit_aquamen = "Тотем водолазов",
	oilbarrel_scene = "Бак топлива", oil_barrel = "Бак топлива",
	net_part = "Сеть", raft_collector = "Сеть",
	raft_anchor = "Якорь", anchor_part = "Якорь", raft_anchor_winch = "Лебёдка",
	firecamp = "Костёр", campfire = "Костёр",
	workbench = "Верстак", sawmill = "Лесопилка",
	smallcontainer = "Ящик", plastic_container = "Контейнер", plasticcontainer = "Контейнер",
	torch = "Факел", wet_brick = "Сырой кирпич", dry_brick = "Кирпич",
	deffender_1 = "ПВО", cannon = "Пушка", canon = "Пушка",
	backpack = "Рюкзак", raft_part = "Клетка пола", raft_floor_upper = "Пол второго этажа",
}
local CONTAINS_RU = {
	{ "grill", "Мангал" }, { "bed", "Лежанка" }, { "planter", "Грядка" }, { "wall", "Стена" },
	{ "door", "Дверь" }, { "anchor", "Якорь" }, { "smelter", "Плавильня" }, { "container", "Контейнер" },
	{ "torch", "Факел" }, { "cannon", "Пушка" }, { "canon", "Пушка" }, { "turret", "Турель" },
	{ "brick", "Кирпич" }, { "net", "Сеть" }, { "crate", "Ящик" }, { "barrel", "Бочка" },
}
function PlaceCheck.displayName(raw)
	if type(raw) ~= "string" or raw == "" then return "предмет" end
	if ItemNamesRu and type(ItemNamesRu.lookup) == "function" then
		local ok, ru = pcall(ItemNamesRu.lookup, raw)
		if ok and type(ru) == "string" and ru ~= "" then return ru end
	end
	local low = raw:lower()
	if MODEL_RU[low] then return MODEL_RU[low] end
	-- «Raft_grill_barrel» → пробуем без хвоста: Raft_grill
	for key, ru in pairs(MODEL_RU) do
		if low:sub(1, #key) == key then return ru end
	end
	for _, pair in ipairs(CONTAINS_RU) do
		if low:find(pair[1], 1, true) then return pair[2] end
	end
	return raw
end

--[[ Удобная обёртка для серверных установок: если занято — уничтожает клон,
     говорит игроку, что мешает, и возвращает true. ]]
function PlaceCheck.refuseIfBlocked(model, raft, player)
	local by = PlaceCheck.blocked(model, raft)
	if not by then return false end
	if player and typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = "warn", icon = "no", title = "Место занято",
			body = "Сюда нельзя — место занято" })   -- без имени: оно бывает внутренним (IslandHall)
	end
	model:Destroy()
	return true
end

return PlaceCheck
