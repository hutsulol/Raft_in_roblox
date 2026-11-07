--[[
	ПРЕДМЕТЫ ЗАГОНА (корыто, ящик для шерсти) — ГДЕ ИХ МОЖНО СТАВИТЬ.
	Общий модуль: одно правило и для призрака (DecorPlace.client), и для сервера
	(DecorPlace.server) — иначе призрак зелёный, а сервер отказывает.

	Правило: ТОЛЬКО НА ГРЯДКУ блока фермы (Raft_farm_block). Не на настил плота,
	не на забор, не в другой предмет. Проверяем:
	  1) под каждым углом основания и под центром луч вниз попадает в видимую
	     землю грядки (детали raft_farm_soil*) — значит предмет целиком на ней;
	  2) в объёме предмета нет ничего твёрдого, кроме самой земли: забор,
	     калитка, другое корыто — отказ. Овцы, люди и призраки не считаются.
]]

local FarmPropRules = {}

FarmPropRules.NAMES = { Raft_farm_trough = true, Raft_wool_bin = true }

local function isSoil(inst)
	return inst:IsA("BasePart") and inst.Name:sub(1, 14) == "raft_farm_soil" and inst.Transparency < 1
end
FarmPropRules.isSoil = isSoil

-- живое (овца, фермер, игрок) не мешает
local function isCreature(inst)
	local node = inst.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return true end
		if node.Name == "NetCaptureSheep" then return true end
		node = node.Parent
	end
	return false
end

--[[ model — уже поставленная в нужную позу модель (призрак или клон).
     ignore — что ещё пропускать (персонаж игрока). Возвращает ok, причина. ]]
function FarmPropRules.check(model, ignore)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok then return false, "нет габарита" end
	local exclude = { model }
	for _, v in ipairs(ignore or {}) do table.insert(exclude, v) end
	local sheep = workspace:FindFirstChild("NetCaptureSheep")
	if sheep then table.insert(exclude, sheep) end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	-- 1) основание целиком на грядке
	local hx, hz = size.X * 0.5 - 0.3, size.Z * 0.5 - 0.3
	local bottom = -size.Y * 0.5
	for _, c in ipairs({ { 0, 0 }, { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz } }) do
		local from = cf * Vector3.new(c[1], bottom + 2.5, c[2])
		local hit = workspace:Raycast(from, Vector3.new(0, -5, 0), params)
		if not hit then return false, "под предметом пусто" end
		if not isSoil(hit.Instance) then
			local n = hit.Instance.Name
			if n:find("fence", 1, true) or n:find("gate", 1, true) then return false, "на заборе нельзя" end
			return false, "ставится только на грядку фермы"
		end
	end

	-- 2) внутри объёма — ничего твёрдого, кроме земли
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = exclude
	local box = cf * CFrame.new(0, 0.25, 0)
	for _, p in ipairs(workspace:GetPartBoundsInBox(box, size * Vector3.new(0.92, 0.8, 0.92), op)) do
		if p.CanCollide and not isSoil(p) and not isCreature(p) then
			local n = p.Name
			if n:find("fence", 1, true) or n:find("gate", 1, true) then return false, "мешает забор" end
			return false, "место занято"
		end
	end
	return true
end

--[[ Высота, на которую ставить: верх ГОЛОЙ земли блока. У травы габарит
     раздут травинками — по лучу предмет висел бы над грядкой. ]]
function FarmPropRules.groundY(hitInst, fallbackY)
	local block = hitInst and hitInst:FindFirstAncestor("Raft_farm_block")
	local bare = block and block:FindFirstChild("raft_farm_soil", true)
	if bare and bare:IsA("BasePart") then return bare.Position.Y + bare.Size.Y * 0.5 end
	return fallbackY
end

--[[ ТОЧКА НА КЛЕТКАХ ФЕРМЫ ИЛИ ДОМА ФЕРМЕРА? (включая их границу — там забор
     и стены дома). Молоток по ней не пускает строить стены, проёмы и двери:
     иначе стена вставала прямо в забор фермы. Центр блока — по грядке, центр
     дома — по габариту деталей без створки двери (она открывается наружу). ]]
-- IslandHall (таверна): внутри неё молоток не строит ничего — ни стен, ни проёмов, ни лестниц
local FOOT = { Raft_farm_block = true, Raft_farmer_hut = true, IslandHall = true }
local function footprintCenter(model, fcf)
	-- постройки с уровнями (домик, таверна): центр 2×2 — точка посадки AssemblyOrigin.
	-- Габарит тут врёт: в него входят спрятанные детали будущих уровней.
	local origin = model:FindFirstChild("AssemblyOrigin")
	if origin and origin:IsA("BasePart") then return fcf:PointToObjectSpace(origin.Position) end
	if model.Name == "Raft_farm_block" then
		local soil = model:FindFirstChild("raft_farm_soil", true)
		if soil and soil:IsA("BasePart") then return fcf:PointToObjectSpace(soil.Position) end
	end
	local mn, mx
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(-5) ~= "_leaf" then
			local h = d.Size * 0.5
			for _, c in ipairs({ Vector3.new(h.X, h.Y, h.Z), Vector3.new(-h.X, h.Y, h.Z), Vector3.new(h.X, h.Y, -h.Z), Vector3.new(-h.X, h.Y, -h.Z) }) do
				local l = fcf:PointToObjectSpace(d.CFrame * c)
				mn = mn and mn:Min(l) or l
				mx = mx and mx:Max(l) or l
			end
		end
	end
	return mn and (mn + mx) * 0.5 or nil
end

function FarmPropRules.onFarmFootprint(raft, worldPos)
	local primary = raft and raft.PrimaryPart
	if not primary then return false end
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then
		local _, y = primary.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	local fcf = CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
	local p = fcf:PointToObjectSpace(worldPos)
	for _, m in ipairs(raft:GetChildren()) do
		if m:IsA("Model") and FOOT[m.Name] and not m:GetAttribute("PlacementGhost") then
			local c = footprintCenter(m, fcf)
			if c and math.abs(p.X - c.X) <= 10.5 and math.abs(p.Z - c.Z) <= 10.5 then return true end
		end
	end
	return false
end

return FarmPropRules
