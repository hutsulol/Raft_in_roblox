-- WaterSpawn.lua (ModuleScript)
-- Общий выбор точки спавна морского врага НАД ОТКРЫТОЙ ВОДОЙ.
--
-- Проблема: враги волны спавнятся в точке center + dir*dist от плота по стороне
-- шторма. Если рядом дрейфует остров и эта точка попадает на его сушу — враг
-- появляется ВНУТРИ острова, а не в воде. Этот модуль сдвигает точку на чистую
-- воду: сначала пробует заданное направление, потом сканирует углы вокруг плота
-- (ближайшие к нужному — первыми), и лишь если кольцо занято — отодвигает точку
-- дальше вдоль направления (за остров).
--
-- «Вода» = верхнее попадание луча ВНИЗ в этой точке имеет Material == Water. Остров
-- (меши/террейн-суша) стоит НАД водой, поэтому там луч сперва бьётся в сушу.

local WaterSpawn = {}

local RAY_DOWN = Vector3.new(0, -500, 0)

-- точка (x,z) над открытой водой? topY — старт луча заведомо выше поверхности.
local function isOpenWater(x, z, topY, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = false
	local res = workspace:Raycast(Vector3.new(x, topY, z), RAY_DOWN, params)
	return res ~= nil and res.Material == Enum.Material.Water
end

-- center: центр плота (Vector3). baseDir: желаемое направление (сторона шторма).
-- dist: расстояние от центра. topY: старт луча (напр. rp.Position.Y + 80).
-- ignore: массив инстансов-исключений (плот, сам враг).
-- Возвращает: worldXZ (Vector3, Y = topY-условный, бери воду отдельно), а также
-- фактическое направление (может отличаться от baseDir, если угол пришлось сменить).
function WaterSpawn.pick(center, baseDir, dist, topY, ignore)
	local d = Vector3.new(baseDir.X, 0, baseDir.Z)
	d = (d.Magnitude > 1e-3) and d.Unit or Vector3.new(0, 0, 1)

	local function pointAt(dir, dd)
		return center + dir * dd
	end

	-- 1) заданное направление
	local p = pointAt(d, dist)
	if isOpenWater(p.X, p.Z, topY, ignore) then
		return p, d
	end

	-- 2) скан углов вокруг плота, ближайшие к нужному — первыми (0,±15,±30,…,±165°)
	for step = 1, 11 do
		local ang = math.rad(15 * step)
		for _, sgn in ipairs({ 1, -1 }) do
			local dir = (CFrame.Angles(0, sgn * ang, 0) * d)
			local pp = pointAt(dir, dist)
			if isOpenWater(pp.X, pp.Z, topY, ignore) then
				return pp, dir
			end
		end
	end

	-- 3) кольцо занято (плот в бухте?) → отодвигаемся дальше по направлению за остров
	for extra = 1, 10 do
		local dd = dist + extra * 60
		local pp = pointAt(d, dd)
		if isOpenWater(pp.X, pp.Z, topY, ignore) then
			return pp, d
		end
	end

	-- 4) воды не нашли (не должно случаться при бесконечном океане) — как было
	return pointAt(d, dist), d
end

-- ── ОБХОД ОСТРОВОВ НА ДВИЖЕНИИ ──
-- Путь вперёд свободен? Горизонтальный луч из pos по dir на lookAhead: IgnoreWater,
-- поэтому вода не мешает — луч ловит только ТВЁРДОЕ (сушу/меши острова). Всё своё
-- (плот, сам враг, игроки) — в ignore.
local function blocked(pos, dir, lookAhead, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	return workspace:Raycast(pos, dir * lookAhead, params) ~= nil
end

-- Скорректировать курс, чтобы ОБОЙТИ остров. Если прямо по desiredDir чисто —
-- возвращаем его же. Иначе доворачиваем влево/вправо шагами, ближайший чистый курс
-- к желаемому — первым. Полностью заперт → возвращаем желаемый (пусть упрётся, но
-- обычно с воды такого не бывает).
-- pos — текущая позиция (на высоте корпуса), lookAhead — на сколько смотрим вперёд.
-- ── ПРЕГРАДА НА ПУТИ СНАРЯДА ──
-- Луч ОТ прошлой позиции К новой: снаряд, который двигают CFrame'ом, между
-- кадрами перепрыгивает через остров и любой корпус — никакой Touched тут не
-- сработает, потому что столкновения физически не было. Поэтому проверяем сам
-- отрезок пути.
--
-- ⚠️ ТВЁРДЫМ СЧИТАЕМ ТОЛЬКО КОЛЛИДНОЕ. Вокруг полно декора и эффектов
-- (частицы-парты, зоны, дым, брызги) с CanCollide = false — об них снаряд
-- разбиваться не должен. Такие попадания пропускаем и продолжаем луч дальше.
-- Возвращает (позицияПопадания, деталь) либо nil.
function WaterSpawn.solidHit(from, to, ignore)
	local dir = to - from
	if dir.Magnitude < 1e-4 then return nil end

	local skip = {}
	for _, v in ipairs(ignore or {}) do table.insert(skip, v) end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	for _ = 1, 6 do
		params.FilterDescendantsInstances = skip
		local res = workspace:Raycast(from, dir, params)
		if not res then return nil end
		if res.Instance.CanCollide then
			return res.Position, res.Instance
		end
		table.insert(skip, res.Instance)   -- декор: летим дальше
	end
	return nil
end

function WaterSpawn.steer(pos, desiredDir, lookAhead, ignore)
	local d = Vector3.new(desiredDir.X, 0, desiredDir.Z)
	d = (d.Magnitude > 1e-3) and d.Unit or Vector3.new(0, 0, 1)
	lookAhead = lookAhead or 40

	if not blocked(pos, d, lookAhead, ignore) then
		return d
	end
	for step = 1, 8 do
		local ang = math.rad(20 * step)
		for _, sgn in ipairs({ 1, -1 }) do
			local dir = (CFrame.Angles(0, sgn * ang, 0) * d)
			if not blocked(pos, dir, lookAhead, ignore) then
				return dir
			end
		end
	end
	return d
end

return WaterSpawn
