--[[
	УРОВНИ ПОСТРОЕК (0…3): рыбацкое место и домик фермера.
	Хендоффы: RaftBuildings_Upgrades (модели) + design_handoff_building_upgrade (табличка).

	В каждой модели лежат ВСЕ уровни сразу. Видимость детали — по атрибуту
	LevelMask: бит 2^level. 15 = уровни 0–3, 14 = 1–3, 12 = 2–3, 8 = только 3.
	Детали без маски (маркеры wp_*, леска, улов) этот модуль не трогает.

	⚠️ ПОСТРОЙКА ПРИВАРЕНА К ПЛОТУ. Сервер меняет только прозрачность, текстуру и
	свет — сборку плота это не перестраивает (как уровни улова в FarmFill). Полёт
	деталей — клиентские заякоренные копии (BuildingUpgradeFx.client), их место
	считается каждый кадр от текущего пивота модели: плот плывёт и поворачивает.

	Сервер: BuildingUpgradeServer. Клиент: BuildingUpgradeBillboard (табличка),
	BuildingUpgradeFx (сборка, звук).
]]

local L = {}

L.TAG = "UpgradableBuilding"
L.MAX = 3
-- множитель прибыли и цена перехода с уровня N на N+1 (pirate)
L.Mults = { [0] = 1, [1] = 1.5, [2] = 2, [3] = 3 }
L.Costs = { [0] = 500, [1] = 1500, [2] = 4000 }

L.KINDS = {
	Raft_fishing_spot = { name = "Рыбацкое место", textures = true },
	Raft_farmer_hut   = { name = "Домик фермера" },
	IslandHall        = { name = "Таверна", uiScale = 2.2 },   -- здание большое: табличка крупнее   -- уровень ускоряет подготовку жителя (IslandHallConfig)
}

-- тайминг сборки одного уровня (с): сначала уходят устаревшие детали, потом новые
-- прилетают по одной (GAP), летят FLY и «садятся» SETTLE
L.REMOVE = 0.52
L.LEAD = 0.35
L.GAP = 0.2
L.FLY = 0.88
L.SETTLE = 0.29
L.TAIL = 0.6

function L.present(mask, level)
	return type(mask) == "number" and bit32.band(mask, 2 ^ level) ~= 0
end

local cache = setmetatable({}, { __mode = "k" })
-- детали с LevelMask, по имени (у клиента и сервера порядок одинаковый)
function L.pieces(model)
	local list = cache[model]
	if list then return list end
	list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and type(d:GetAttribute("LevelMask")) == "number" then table.insert(list, d) end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	cache[model] = list
	return list
end

-- порядок сборки по зонам (как в reference-демо)
local function priority(model, part)
	local z = tostring(part:GetAttribute("Zone") or part.Name)
	if model.Name == "Raft_farmer_hut" then
		if z:find("Brace") or z:find("Corner") then return 1 end
		if z:find("Rail") or z:find("Bench") or z:find("Window") or z:find("Door") then return 2 end
		if z:find("Cupboard") or z:find("Tool") then return 3 end
		if z:find("Roof") or z:find("Ridge") then return 4 end
		return 5
	end
	if z:find("Rod_") then return 5 end
	if z:find("Organizer") or z:find("Chest") then return 4 end
	if z:find("Stool") then return 3 end
	if z:find("Crate") then return 1 end
	return 2
end

-- переход from → to (на один уровень): что прилетает, что уходит, что стоит
function L.diff(model, from, to)
	local added, removed, kept = {}, {}, {}
	for _, p in ipairs(L.pieces(model)) do
		local mask = p:GetAttribute("LevelMask")
		local was, will = L.present(mask, from), L.present(mask, to)
		if was and will then table.insert(kept, p)
		elseif will then table.insert(added, p)
		elseif was then table.insert(removed, p) end
	end
	table.sort(added, function(a, b)
		local pa, pb = priority(model, a), priority(model, b)
		if pa == pb then return a.Name < b.Name end
		return pa < pb
	end)
	return added, removed, kept
end

-- когда i-я новая деталь начинает лететь (от начала шага) и сколько длится шаг
function L.startOf(i, hasRemoved)
	return L.LEAD + (hasRemoved and L.REMOVE or 0) + (i - 1) * L.GAP
end
function L.duration(model, from, to)
	local added, removed = L.diff(model, from, to)
	return L.startOf(math.max(#added, 1), #removed > 0) + L.FLY + L.SETTLE + L.TAIL
end

-- откуда прилетает деталь: смещение и поворот в осях модели
function L.flightOffset(model, part, localCF)
	local z = tostring(part:GetAttribute("Zone") or part.Name)
	local x = localCF.X
	if model.Name == "Raft_farmer_hut" then
		if z:find("Roof") or z:find("Ridge") then return Vector3.new(0, 3.2, 1), Vector3.new(math.rad(-18), 0, math.rad(8)) end
		if z:find("Rail") or z:find("Brace") or z:find("Corner") then
			return Vector3.new(x < 0 and -2.4 or 2.4, 1.4, -0.6), Vector3.new(0, math.rad(25), math.rad(20))
		end
		if z:find("Sign") or z:find("Header") then return Vector3.new(0, 1.8, -2), Vector3.new(math.rad(-30), 0, 0) end
		return Vector3.new(0, 1.8, -1.1), Vector3.new(0, math.rad(35), math.rad(-12))
	end
	if z:find("Rod_") then return Vector3.new(-1.1, 1.65, -0.6), Vector3.new(0, 0, math.rad(115)) end
	if z:find("Organizer") then return Vector3.new(0, 2, 1), Vector3.new(math.rad(-25), 0, 0) end
	if z:find("Chest") then return Vector3.new(0, 0.8, -1.7), Vector3.new(0, math.rad(30), 0) end
	if z:find("Crate") then
		local dx = z:find("Left") and 1.65 or z:find("Right") and -1.65 or 0
		return Vector3.new(dx, 1.15, z:find("Front") and -1.3 or 1), Vector3.new(0, math.rad(30), math.rad(dx * 12))
	end
	return Vector3.new(x < 0 and -1 or 1, 1.65, -0.5), Vector3.new(math.rad(20), 0, math.rad(-25))
end

-- металлический звук на установке (остальное — дерево/киянка)
function L.isMetal(part)
	local z = tostring(part:GetAttribute("Zone") or part.Name)
	return z:find("Rod") or z:find("Lantern") or z:find("Equipment") or z:find("Sign")
end

function L.texture(model, level)
	local kind = L.KINDS[model.Name]
	if not (kind and kind.textures) then return nil end
	local t = model:GetAttribute("Texture" .. level)
	return type(t) == "string" and t ~= "" and t or nil
end

-- сразу показать уровень (сервер): прозрачность, коллизии/лучи у спрятанного, текстура, свет
function L.apply(model, level)
	local tex = L.texture(model, level)
	for _, p in ipairs(L.pieces(model)) do
		local on = L.present(p:GetAttribute("LevelMask"), level)
		p.Transparency = on and 0 or 1
		p.CanQuery = on
		p.CanTouch = false
		if not on then p.CanCollide = false end
		p.CastShadow = on
		if tex and p:IsA("MeshPart") then pcall(function() p.TextureID = tex end) end
		for _, l in ipairs(p:GetDescendants()) do
			if l:IsA("Light") then l.Enabled = on end
		end
	end
end

-- «7 000» / «×1,5»
function L.formatNum(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end
function L.formatMult(m)
	local s = (m % 1 == 0) and tostring(math.floor(m)) or string.format("%.1f", m)
	return "×" .. s:gsub("%.", ",")
end

return L
