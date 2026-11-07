--[[
	РЫБАЦКОЕ МЕСТО — СЕТКА ПЛОТА. Общие правила для призрака (FishingSpotPlace.client)
	и сервера (FishingSpotPlace.server, BuildingSystem).

	Станция (Raft_fishing_spot) стоит строго на ОДНОЙ клетке пола, как дом фермера
	на своих: основание (самая крупная деталь модели, ~9.9×9.5) — по центру
	клетки, низ — на верх настила, поворот — четвертями по сетке плота.

	Перед ней рыбак забрасывает удочку (направление от wp_sit к wp_sit_look,
	туда же над водой вынесено удилище). Поэтому станция занимает 1×2:
	  • её клетка — пол;
	  • клетка впереди — ВОДА: там не должно быть ни пола, ни сети, ни чего-либо
	    ещё с плота. Ставить станцию нельзя, пока впереди занято, а пол, сеть и
	    прочее нельзя строить на клетке впереди уже стоящей станции
	    (G.frontReserved — зовёт BuildingSystem.server).
	Клетка впереди считается по маркерам самой станции, поэтому резерв работает
	и для станций из сохранения.
]]

local G = {}

G.NAME = "Raft_fishing_spot"
G.GRID = 10
G.DEFAULT_QUARTER = 1   -- по умолчанию повёрнута на 90° (просил владелец); R — следующая четверть

function G.isTile(child, raft)
	if child == raft.PrimaryPart then return true end
	if child.Name == "Net_Part" then return false end
	return child.Name == "Raft_part" or child:GetAttribute("BuildType") == "raft"
end

function G.tilePos(tile)
	if tile:IsA("BasePart") then return tile.Position end
	if tile:IsA("Model") then
		if tile.PrimaryPart then return tile.PrimaryPart.Position end
		local best, vol = nil, -1
		for _, d in ipairs(tile:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > vol then best, vol = d, v end
			end
		end
		return best and best.Position
	end
	return nil
end

function G.flatFrame(raft)
	local primary = raft.PrimaryPart
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then
		local _, y = primary.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
end

-- прямой ребёнок плота, которому принадлежит деталь
function G.topTileOf(inst, raft)
	local node = inst
	while node and node.Parent ~= raft do
		node = node.Parent
		if node == nil or node == workspace then return nil end
	end
	return node
end

local function partTop(p)
	local cf, sz = p.CFrame, p.Size
	local up = Vector3.new(0, 1, 0)
	return cf.Position.Y + math.abs(cf.RightVector:Dot(up)) * sz.X * 0.5
		+ math.abs(cf.UpVector:Dot(up)) * sz.Y * 0.5 + math.abs(cf.LookVector:Dot(up)) * sz.Z * 0.5
end

-- верх настила клетки — по габаритам её видимых деталей (лучом на сервере ненадёжно)
function G.deckTop(tile)
	local best
	local parts = tile:IsA("BasePart") and { tile } or tile:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local y = partTop(p)
			if not best or y > best then best = y end
		end
	end
	return best
end

-- точка посадки станции с уровнями апгрейда: AssemblyOrigin — центр клетки на
-- уровне верха настила (хендофф RaftBuildings_Upgrades). У старой модели её нет.
function G.originOf(model)
	local o = model:FindFirstChild("AssemblyOrigin")
	return o and o:IsA("BasePart") and o or nil
end

-- основание станции — точка посадки, иначе самая крупная деталь (по ней и ставим в клетку)
function G.basePart(model)
	local origin = G.originOf(model)
	if origin then return origin end
	local best, vol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > vol then best, vol = d, v end
		end
	end
	return best
end

-- рыскание основания в шаблоне (наклон шаблона, если он есть, отбрасываем)
local yawCache = nil
function G.templateYaw()
	if yawCache then return yawCache end
	local ok, AssetFind = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("AssetFind"))
	local tpl = ok and AssetFind.find(G.NAME)
	local base = tpl and G.basePart(tpl)
	if not base then return CFrame.new() end
	local look = base.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if base.CFrame.UpVector.Y < 0.9 or flatLook.Magnitude < 0.05 then
		warn("[Рыбацкое место] основание в шаблоне наклонено — ставлю без его поворота")
		yawCache = CFrame.new()
	else
		flatLook = flatLook.Unit
		yawCache = CFrame.Angles(0, math.atan2(-flatLook.X, -flatLook.Z), 0)
	end
	return yawCache
end

--[[ Поставить модель на клетку tile в четверти quarter. Возвращает центр
     клетки впереди (на уровне настила) или nil. ]]
function G.pose(model, raft, tile, quarter)
	local c = G.tilePos(tile)
	local top = G.deckTop(tile)
	local base = G.basePart(model)
	if not (c and top and base) then return nil end
	local flat = G.flatFrame(raft)
	--[[ ⚠️ СТАНЦИЯ ВСЕГДА СТОИТ, А НЕ ЛЕЖИТ — ПОВОРОТ НЕ БЕРЁМ У КЛОНА.
	     Раньше поворот основания запоминался с клона (FS_BaseRot) и докручивался
	     четвертью — если клон приезжал повёрнутым, станция вставала на бок на 90°.
	     Теперь основание ставится ровно: его верх — мировой верх, поворот —
	     только рыскание плота + четверть (+ рыскание основания в шаблоне).
	     Модель двигаем разницей «где основание сейчас → где должно быть»:
	     сколько раз ни зови (призрак — каждый кадр), результат один и тот же. ]]
	local rot = flat.Rotation * CFrame.Angles(0, math.rad(90 * ((quarter or 0) % 4)), 0) * G.templateYaw()
	local target = G.originOf(model) and CFrame.new(c.X, top, c.Z) * rot   -- точка посадки — на верх настила
		or CFrame.new(c.X, top + base.Size.Y * 0.5, c.Z) * rot
	model:PivotTo(target * base.CFrame:Inverse() * model:GetPivot())
	return G.frontOf(model, raft, top)
end

-- центр клетки впереди станции: по маркерам рыбака, со снапом на ось сетки
function G.frontOf(model, raft, top)
	local sit = model:FindFirstChild("wp_sit", true)
	local look = model:FindFirstChild("wp_sit_look", true)
	local base = G.basePart(model)
	if not (sit and look and base and sit:IsA("BasePart") and look:IsA("BasePart")) then return nil end
	local flat = G.flatFrame(raft)
	local d = flat:VectorToObjectSpace(look.Position - sit.Position)
	-- к ближайшей оси сетки
	local dir = math.abs(d.X) > math.abs(d.Z) and Vector3.new(math.sign(d.X), 0, 0) or Vector3.new(0, 0, math.sign(d.Z))
	local c = base.Position
	local p = c + flat:VectorToWorldSpace(dir) * G.GRID
	return Vector3.new(p.X, top or (c.Y - base.Size.Y * 0.5), p.Z)
end

--[[ Что мешает воде впереди: nil — свободно, иначе причина для игрока.
     ignore — сама станция (и призрак). ]]
function G.frontProblem(raft, front, ignore)
	if not front then return "Не найдено, куда смотрит рыбак" end
	local flat = G.flatFrame(raft)
	local fl = flat:PointToObjectSpace(front)
	for _, child in ipairs(raft:GetChildren()) do
		if G.isTile(child, raft) then
			local p = G.tilePos(child)
			if p then
				local l = flat:PointToObjectSpace(p)
				if math.abs(l.X - fl.X) < 4 and math.abs(l.Z - fl.Z) < 4 then
					return "Перед рыбацким местом должна быть вода, а там пол"
				end
			end
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local box = CFrame.new(front + Vector3.new(0, 3, 0)) * flat.Rotation
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(8, 8, 8), params)) do
		if part:IsDescendantOf(raft) then
			local top = G.topTileOf(part, raft)
			if top and top.Name ~= G.NAME then
				return "Перед рыбацким местом занято: " .. top.Name
			end
		end
	end
	return nil
end

-- клетка (центр в мире) — вода впереди какой-то станции? Тогда строить на ней нельзя
function G.frontReserved(raft, pos, except)
	if not (raft and raft.PrimaryPart) then return false end
	local flat = G.flatFrame(raft)
	local pl = flat:PointToObjectSpace(pos)
	for _, child in ipairs(raft:GetChildren()) do
		if child.Name == G.NAME and child ~= except and not child:GetAttribute("PlacementGhost") then
			local front = G.frontOf(child, raft)
			if front then
				local fl = flat:PointToObjectSpace(front)
				if math.abs(fl.X - pl.X) < 4 and math.abs(fl.Z - pl.Z) < 4 then return true end
			end
		end
	end
	return false
end

return G
