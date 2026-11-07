--[[
	Общие числа и имена стен плота.

	⚠️ ЧИТАЮТ ТРИ МЕСТА: превью на клиенте (BuildingSystem.client), установка на
	сервере (BuildingSystem.server) и восстановление сейва (RaftSaveSystem).
	Держать эти значения врозь нельзя: стена встанет не туда, где нарисован
	призрак, и не туда, куда её положит загрузка. На высоте панели этим уже
	обожглись — там расхождение прожило до тех пор, пока не полезли в лог.
	Тот же приём, что у RaftReinforce.
]]

local Defs = {}

-- ⚠️ ЕДИНСТВЕННАЯ РУЧКА ВЫСОТЫ СТЕН.
-- Формула ставит ЦЕНТР стены на верх настила: deckTop + высота/2. По ней низ
-- обязан лечь ровно на доски — но габарит модели чуть выше самой геометрии, и
-- стена повисала над полом. Опускаем все стены одинаково: глухую, полустену,
-- листву, ограду, окно, проём и дверь. Больше в пол — увеличить число.
Defs.SINK = 0.35

-- ⚠️ ВАРИАНТЫ СТЕН НА РЕБРЕ КЛЕТКИ — ОДИН СПИСОК НА ВСЮ ИГРУ.
-- Ставятся по той же геометрии, что глухая стена, и отличаются ровно моделью и
-- ценой. У «Стены» и «Проёма» ветки свои: им нужны отдельные ключи (дверь ищет
-- проём) и событие квеста. Новая стена добавляется СТРОКОЙ ЗДЕСЬ — дальше её
-- сами подхватят меню молотка, установка и загрузка сейва.
-- Имена — как у моделей в ReplicatedStorage, по ним и ищется шаблон.
-- ⚠️ ЦЕНА — ТАБЛИЦА РЕСУРСОВ, А НЕ ОДНО ЧИСЛО.
-- Раньше стояло cost = N и подразумевалось дерево. У листвы цена из двух
-- ресурсов, и оставь мы одно число — сервер списывал бы только дерево, а листья
-- уходили бы бесплатно. Проверка и списание идут по всей таблице сразу.
-- ДЕРЖАТЬ РАВНЫМ ценам в меню (BuildingSystem.client, таблица categories).
Defs.EdgeWalls = {
	wall_window    = { names = { "raft_wall_window", "Raft_wall_window" },
		costs = { Log = 3 } },
	wall_leaf      = { names = { "raft_wall_leaf", "Raft_wall_leaf" },
		costs = { Log = 2, Leaves = 4 } },
	wall_leaf_half = { names = { "raft_wall_leaf_half", "Raft_wall_leaf_half" },
		costs = { Log = 2, Leaves = 2 } },   -- половина листвы от полной лиственной стены
	wall_half      = { names = { "raft_wall_half", "Raft_wall_half" },
		costs = { Log = 2 } },
}

-- Поиск не свой, а общий (AssetFind): он ищет по имени в любой папке, и это
-- нужно здесь по двум сразу причинам — модели стен приезжают вложенными в
-- raft_wall, а само хранилище разложено по папкам.
local AssetFind = require(script.Parent:WaitForChild("AssetFind"))

function Defs.findModel(_rs, names)
	return AssetFind.find(table.unpack(names))
end

--[[ ⚠️ МЕРЯЕМ ТОЛЬКО СОБСТВЕННУЮ ГЕОМЕТРИЮ ШАБЛОНА, БЕЗ ВЛОЖЕННЫХ МОДЕЛЕЙ.

     Model:GetExtentsSize() считает габарит ВМЕСТЕ со всем, что лежит внутри. А
     новые стены приезжают вложенными в raft_wall — и высота глухой стены
     получалась «по ним»: превью вставало заметно выше, чем стена реально
     ставилась. Причём формулы у превью и у постановки совпадали построчно, из-за
     чего расхождение и не находилось: врало одно и то же число, посчитанное в
     разные моменты. Сервер вложенные модели выносит при запуске и меряет уже
     очищенный шаблон, а клиент читает раньше — вот и вся разница.

     Поэтому габарит считаем сами и пропускаем всё, что лежит внутри вложенной
     модели. Тогда замер не зависит от того, успели вынести или нет. ]]
local function isOwnPart(model, part)
	local node = part.Parent
	while node and node ~= model do
		if node:IsA("Model") then return false end
		node = node.Parent
	end
	return true
end

--[[ Габарит по СВОИМ деталям: центр (CFrame) и размер. Мировые оси — детали
     могут быть повёрнуты, и собственный Y детали не обязан смотреть вверх. ]]
function Defs.ownBox(t)
	if not t then return nil, nil end
	if t:IsA("BasePart") then return t.CFrame, t.Size end
	if not t:IsA("Model") then return nil, nil end

	local lo, hi
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") and isOwnPart(t, d) then
			local cf, sz = d.CFrame, d.Size
			local ext = Vector3.new(
				math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y
					+ math.abs(cf.LookVector.X) * sz.Z,
				math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
					+ math.abs(cf.LookVector.Y) * sz.Z,
				math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y
					+ math.abs(cf.LookVector.Z) * sz.Z) * 0.5
			local p = d.Position
			lo = lo and lo:Min(p - ext) or (p - ext)
			hi = hi and hi:Max(p + ext) or (p + ext)
		end
	end
	if not lo then return nil, nil end
	return CFrame.new((lo + hi) * 0.5), (hi - lo)
end

function Defs.heightOf(t)
	local _, size = Defs.ownBox(t)
	return size and size.Y or 0
end

--[[ ⚠️ СТЕНУ СТАВИМ ПО ЦЕНТРУ ГЕОМЕТРИИ, А НЕ ПО ПИВОТУ.

     Формула высоты говорит буквально «ЦЕНТР стены на верх настила»:
     deckTop + высота/2. А PivotTo ставит ПИВОТ — точку, которую автор модели
     задал как придётся и которая с центром совпадать не обязана. Пока они
     совпадали, всё сходилось; стоило разойтись — призрак повис выше и в стороне.
     Ровно эта же беда у доски пола давно решена вручную (RAFT_PIVOT_DELTA в
     BuildingSystem), стенам просто не досталось.

     Хуже того, у модели БЕЗ явного пивота им служит центр габарита — то есть
     пивот уезжает, стоит вложить внутрь ещё одну модель. Именно это и случилось,
     когда новые стены приехали внутри raft_wall: сервер их оттуда выносит при
     запуске и получает один пивот, клиент видит другой.

     Поэтому считаем сами: возвращаем CFrame, который надо передать в PivotTo,
     чтобы ЦЕНТР СОБСТВЕННОЙ ГЕОМЕТРИИ оказался ровно в want.

     ⚠️ ПРАВИМ ТОЛЬКО СДВИГ, ПОВОРОТ НЕ ТРОГАЕМ.
     Первая версия считала полную разницу CFrame'ов, а рамка у ownBox выровнена
     по МИРОВЫМ осям — то есть в разницу попадал ещё и поворот пивота, и модель
     доворачивало на него: стена вставала завалившись. Нужен ровно перенос —
     где центр лежит относительно пивота, в осях пивота. ]]
function Defs.pivotForCentre(t, want)
	if not t or t:IsA("BasePart") then return want end
	local box = Defs.ownBox(t)
	if not box then return want end
	local offset = t:GetPivot():PointToObjectSpace(box.Position)
	return want * CFrame.new(-offset)
end

return Defs
