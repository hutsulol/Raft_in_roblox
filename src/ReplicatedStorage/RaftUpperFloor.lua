--[[
	ПОЛ ВТОРОГО ЭТАЖА — общие правила для превью (BuildingSystem.client),
	установки (BuildingSystem.server) и сторожа опор (там же).

	Правило владельца: пол второго этажа кладётся ТОЛЬКО на клетку первого этажа,
	у которой на всех четырёх рёбрах стоят БОЛЬШИЕ стены. Полустена и ограда
	опорой не считаются. Высота — по верху этих стен.

	⚠️ ВСЁ СЧИТАЕМ ПО ЖИВЫМ СТЕНАМ, А НЕ ПО СЕТКЕ.
	Центр клетки = среднее центров четырёх стен (они стоят на серединах рёбер),
	высота = верх самой высокой из них. Так клиенту и серверу не нужна фаза сетки
	и замер палубы — на них превью стен уже расходилось с постановкой. Оба
	читают одни и те же экземпляры и получают одно и то же число.

	⚠️ ЭТО НЕ «ПОЛ» ДЛЯ ОСТАЛЬНЫХ СИСТЕМ. BuildType = "floor_upper", клетка лежит
	в UpperGX/UpperGZ, а не в GridX/GridZ: иначе сетка первого этажа, пиявки,
	спавн пиратов и сварка приняли бы его за доску плота. HP плоту он даёт
	отдельной строкой в RaftHealth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WallDefs  = require(ReplicatedStorage:WaitForChild("RaftWallDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local Upper = {}

Upper.NAMES      = { "Raft_floor_upper", "raft_floor_upper" }
Upper.BUILD_TYPE = "floor_upper"
Upper.COSTS      = { Log = 3, Rope = 1 }
Upper.GRID       = 10
-- на сколько утопить пол в верх стен, чтобы не было щели (габарит модели чуть
-- больше геометрии — та же история, что у WallDefs.SINK)
Upper.SINK       = 0.1
-- стены, на которые можно класть второй этаж
Upper.FULL_WALLS = { wall_panel = true, wall_window = true, wall_leaf = true, wall_arch = true }

function Upper.template()
	return AssetFind.find(table.unpack(Upper.NAMES))
end

local function spanKey(cx1, cz1, cx2, cz2)
	if cx1 > cx2 or (cx1 == cx2 and cz1 > cz2) then
		cx1, cz1, cx2, cz2 = cx2, cz2, cx1, cz1
	end
	return string.format("%.1f_%.1f_%.1f_%.1f", cx1, cz1, cx2, cz2)
end

-- четыре ребра клетки (gx, gz) в тех же ключах, что WallSpanKey у стен
function Upper.cellSpans(gx, gz)
	local a, b, c, d = gx - 0.5, gx + 0.5, gz - 0.5, gz + 0.5
	return {
		spanKey(a, c, b, c), spanKey(a, d, b, d),
		spanKey(a, c, a, d), spanKey(b, c, b, d),
	}
end

-- [spanKey] = стена (любая, с типом в BuildType)
local function wallsBySpan(raft)
	local map = {}
	for _, child in ipairs(raft:GetChildren()) do
		local sk = child:GetAttribute("WallSpanKey")
		if sk then map[sk] = child end
	end
	return map
end

function Upper.findAt(raft, gx, gz)
	for _, child in ipairs(raft:GetChildren()) do
		if child:GetAttribute("BuildType") == Upper.BUILD_TYPE
			and child:GetAttribute("UpperGX") == gx and child:GetAttribute("UpperGZ") == gz then
			return child
		end
	end
	return nil
end

--[[ Четыре большие стены клетки или nil + причина.
     hasFloor(gx, gz) — есть ли под клеткой пол первого этажа (у клиента и
     сервера свой замер сетки, сюда приходит готовый ответ). ]]
function Upper.supports(raft, gx, gz, hasFloor, map)
	if hasFloor and not hasFloor(gx, gz) then return nil, "nofloor" end
	map = map or wallsBySpan(raft)
	local walls = {}
	for _, key in ipairs(Upper.cellSpans(gx, gz)) do
		local w = map[key]
		if not w then return nil, "nowall" end
		if not Upper.FULL_WALLS[w:GetAttribute("BuildType")] then return nil, "lowwall" end
		table.insert(walls, w)
	end
	return walls
end

-- куда должен встать ЦЕНТР геометрии пола: над клеткой, на верх стен
function Upper.centreCF(raft, walls, thickness)
	local sum, top = Vector3.zero, -math.huge
	for _, w in ipairs(walls) do
		local cf, size = WallDefs.ownBox(w)
		if not cf then return nil end
		sum += cf.Position
		top = math.max(top, cf.Position.Y + size.Y * 0.5)
	end
	local c = sum / #walls
	local pp = raft.PrimaryPart
	local yaw = pp and pp:GetAttribute("RestYaw")
	if type(yaw) ~= "number" then yaw = 0 end
	return CFrame.new(c.X, top + thickness * 0.5 - Upper.SINK, c.Z) * CFrame.Angles(0, yaw, 0)
end

--[[ КЛИЕНТ: клетка под прицелом. Перебираем клетки у больших стен, у которых
     набралась вся четвёрка, и пересекаем луч с плоскостью ВЕРХА СТЕН — луч в
     палубу тут не годится: снаружи комнаты он упирается в стену, а изнутри
     игрок смотрит вверх. Возвращает gx, gz, centreCF ближайшей по лучу. ]]
function Upper.cellFromRay(raft, ray, hasFloor, thickness)
	local map = wallsBySpan(raft)
	local seen, best = {}, nil
	for key, w in pairs(map) do
		if Upper.FULL_WALLS[w:GetAttribute("BuildType")] then
			local x1, z1, x2, z2 = key:match("^(-?[%d%.]+)_(-?[%d%.]+)_(-?[%d%.]+)_(-?[%d%.]+)$")
			x1, z1, x2, z2 = tonumber(x1), tonumber(z1), tonumber(x2), tonumber(z2)
			if x1 then
				local mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
				local cells = (x1 == x2)
					and { { mx - 0.5, mz }, { mx + 0.5, mz } }
					or  { { mx, mz - 0.5 }, { mx, mz + 0.5 } }
				for _, cell in ipairs(cells) do
					local id = cell[1] .. "_" .. cell[2]
					if not seen[id] then
						seen[id] = true
						local walls = Upper.supports(raft, cell[1], cell[2], hasFloor, map)
						local cf = walls and Upper.centreCF(raft, walls, thickness)
						if cf and math.abs(ray.Direction.Y) > 0.001 then
							local t = (cf.Position.Y - ray.Origin.Y) / ray.Direction.Y
							if t > 0 then
								local l = cf:PointToObjectSpace(ray.Origin + ray.Direction * t)
								local half = Upper.GRID * 0.5
								if math.abs(l.X) <= half and math.abs(l.Z) <= half and (not best or t < best.t) then
									best = { t = t, gx = cell[1], gz = cell[2], cf = cf }
								end
							end
						end
					end
				end
			end
		end
	end
	if best then return best.gx, best.gz, best.cf end
	return nil
end

--[[ ═══════════ ВТОРОЙ ЭТАЖ КАК ПОЛ ═══════════
     На полу второго этажа строится всё то же, что на палубе: стены, проёмы,
     двери, грядки, мебель. Стены второго этажа носят Level = 2 и ключи пролёта
     с префиксом L2_ — тот же пролёт на первом этаже (опора второго) и на втором
     не должны занимать друг друга. Upper.supports/cellFromRay читают только
     ключи без префикса (шаблон «^число_…»), так что стены второго этажа
     опорами пола второго этажа не считаются. ]]
Upper.LEVEL_PREFIX = "L2_"

function Upper.key(key, level)
	return level == 2 and (Upper.LEVEL_PREFIX .. key) or key
end

-- пол второго этажа, к которому относится деталь (или nil)
function Upper.modelOf(raft, inst)
	local node = inst
	while node and node.Parent ~= raft do node = node.Parent end
	if node and node:GetAttribute("BuildType") == Upper.BUILD_TYPE then return node end
	return nil
end

function Upper.isUpperPart(inst)
	local node = inst
	while node do
		if node:GetAttribute("BuildType") == Upper.BUILD_TYPE then return true end
		node = node.Parent
		if node == workspace or node == game then return false end
	end
	return false
end

-- верх пола второго этажа (мировая Y)
function Upper.topY(model)
	local cf, size = WallDefs.ownBox(model)
	return cf and (cf.Position.Y + size.Y * 0.5) or nil
end

-- ребро (углы клеток) касается пола второго этажа → верх этого пола, иначе nil
function Upper.edgeTop(raft, cx1, cz1, cx2, cz2)
	local midX, midZ = (cx1 + cx2) / 2, (cz1 + cz2) / 2
	local cells = (cx1 == cx2) and { { midX - 0.5, midZ }, { midX + 0.5, midZ } }
		or { { midX, midZ - 0.5 }, { midX, midZ + 0.5 } }
	local top
	for _, c in ipairs(cells) do
		local m = Upper.findAt(raft, c[1], c[2])
		local y = m and Upper.topY(m)
		if y and (not top or y > top) then top = y end
	end
	return top
end

return Upper
