--[[
	ФЕРМА НА ПЛОТУ: дом фермера + блоки фермы → экономика, корыто, кормушка,
	табличка на воротах и живой фермер. Числа — ReplicatedStorage.RaftFarmConfig,
	рисует всё RaftFarmUI.client (хендофф farm-ui-design, «Яркий симулятор»).

	ФЕРМА = дом Raft_farmer_hut + связная группа Raft_farm_block, к которой он
	пристроен (FarmBlockPlace пускает дом только вплотную к ферме). Зона фермы —
	квадраты этих блоков внутри забора.

	Что происходит:
	  • овца (сеткомёт, workspace.NetCaptureSheep) зашла в зону → тег FarmSheep,
	    атрибуты Satiety / Level / IncomePerHour — над ней сразу появляется доход;
	  • доход овцы зависит от сытости (кормушка с сеном) и воды в корыте
	    (RaftFarmConfig.sheepIncome); копится в хранилище фермы (StoredCoins),
	    игрок забирает кнопкой «СОБРАТЬ» на табличке;
	  • фермер днём носит сено и воду из запаса дома, кормит овец с руки, рыхлит
	    землю мотыгой; ночью уходит спать в дом на кровать; раз в игровой час
	    получает зарплату из хранилища — не хватило → долг и забастовка.

	⚠️ СОСТОЯНИЕ — АТРИБУТАМИ НА ДОМЕ. Дом сохраняется RaftSaveSystem «1в1» с
	атрибутами, а корыто, кормушка, табличка и фермер — нет: их пересоздаёт этот
	скрипт при появлении дома (и после загрузки сохранения).

	⚠️ ФЕРМЕР И РЕКВИЗИТ НЕ В МОДЕЛИ ПЛОТА. Иначе RaftStaticWeld приварит их
	намертво, а сохранение попробует записать как постройку. Они лежат в
	workspace и держатся за плот Weld'ом (C0 = поза относительно PrimaryPart):
	клиент видит их частью плота, без дрожи на ходу. Двигать — только через C0.
	Фермер — прямой ребёнок workspace с атрибутом CrewAnim: так его находит
	PirateIslandAnim.client и играет клипы из атрибутов Clip / ClipOnce.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")

local C         = require(ReplicatedStorage:WaitForChild("RaftFarmConfig"))
local Defs      = require(ReplicatedStorage:WaitForChild("FarmDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG  = "[Ферма/плот]"
local GRID = 10

-- ── remotes ──
local remotes = ReplicatedStorage:FindFirstChild("FarmRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "FarmRemotes"
	remotes.Parent = ReplicatedStorage
end
local fillEvent = remotes:FindFirstChild("FillTrough")
if not fillEvent then
	fillEvent = Instance.new("RemoteEvent")
	fillEvent.Name = "FillTrough"
	fillEvent.Parent = remotes
end
local collectEvent = remotes:FindFirstChild("CollectCoins")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectCoins"
	collectEvent.Parent = remotes
end

local propsRoot = workspace:FindFirstChild("RaftFarmProps")
if not propsRoot then
	propsRoot = Instance.new("Folder")
	propsRoot.Name = "RaftFarmProps"
	propsRoot.Parent = workspace
end

local farms = {}   -- [hut] = farm

-- ═══════════ общее ═══════════

local function now() return workspace:GetServerTimeNow() end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function notify(player, kind, title, body)
	if typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = kind, icon = kind == "success" and "ok" or "no", title = title, body = body })
	end
end

local function setAttr(inst, name, value)
	if inst:GetAttribute(name) ~= value then inst:SetAttribute(name, value) end
end

local function night()
	local t = Lighting.ClockTime
	return t >= C.WORK_END or t < C.WORK_START
end

local function raftOf()
	local raft = workspace:FindFirstChild("Raft")
	return (raft and raft.PrimaryPart) and raft or nil
end

-- кадр решётки плота: позиция PrimaryPart, поворот только по RestYaw
local function flatFrame(raft)
	local primary = raft.PrimaryPart
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then
		local _, y = primary.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
end

local function part(model, name)
	local p = model:FindFirstChild(name, true)
	return (p and p:IsA("BasePart")) and p or nil
end

local function blockCenter(m)
	local soil = part(m, "raft_farm_soil")
	if soil then return soil.Position end
	return (m:GetBoundingBox()).Position
end

--[[ ⚠️ ЦЕНТР ДОМА = ЦЕНТР ЕГО КЛЕТОК 2×2. Два неверных способа уже были:
       • габарит всей модели — дверь открывается наружу на 95° и вылезает за
         стены, центр уезжал, дом переставал «касаться» фермы (ОВЦЫ 0/0);
       • пивот модели — он у импорта стоит не в центре: «дом в (−15, −19.9)»
         при клетках с центром −25, и фермер застревал на крыльце.
     Модель лежит ровно в своих четырёх клетках (RAFT_FARMER_HUT.md), поэтому
     берём габарит в осях решётки по всем деталям, КРОМЕ створки двери. Считаем
     один раз и храним относительно плота: дом к нему приварен. ]]
local hutRel = setmetatable({}, { __mode = "k" })
local function hutCenter(hut)
	local raft = workspace:FindFirstChild("Raft")
	local primary = raft and raft.PrimaryPart
	if not primary then return hut:GetPivot().Position end
	local rel = hutRel[hut]
	if not rel then
		local yaw = primary:GetAttribute("RestYaw")
		if not yaw then
			local _, y = primary.CFrame:ToEulerAnglesYXZ()
			yaw = y
		end
		local fcf = CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
		local mn, mx
		for _, d in ipairs(hut:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(-5) ~= "_leaf" then
				local h = d.Size * 0.5
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local l = fcf:PointToObjectSpace(d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
							mn = mn and mn:Min(l) or l
							mx = mx and mx:Max(l) or l
						end
					end
				end
			end
		end
		if not mn then return hut:GetPivot().Position end
		rel = primary.CFrame:PointToObjectSpace(fcf:PointToWorldSpace((mn + mx) * 0.5))
		hutRel[hut] = rel
	end
	return primary.CFrame * rel
end

-- соседи по стороне: центры в 20 студах по одной оси, не дальше клетки по другой
local function touching(flatCF, a, b)
	local la, lb = flatCF:PointToObjectSpace(a), flatCF:PointToObjectSpace(b)
	local ax, az = math.abs(la.X - lb.X), math.abs(la.Z - lb.Z)
	return (math.abs(ax - 2 * GRID) < 1.5 and az <= GRID + 1)
		or (math.abs(az - 2 * GRID) < 1.5 and ax <= GRID + 1)
end

-- связная группа блоков фермы, к которой пристроен дом
local function clusterOf(hut, raft)
	local fcf = flatFrame(raft)
	local all = {}
	for _, m in ipairs(raft:GetChildren()) do
		if m:IsA("Model") and m.Name == C.BLOCK then table.insert(all, m) end
	end
	local hc = hutCenter(hut)
	local inSet, list = {}, {}
	for _, m in ipairs(all) do
		if touching(fcf, hc, blockCenter(m)) then inSet[m] = true; table.insert(list, m) end
	end
	local i = 1
	while i <= #list do
		local cur = blockCenter(list[i])
		for _, m in ipairs(all) do
			if not inSet[m] and touching(fcf, cur, blockCenter(m)) then
				inSet[m] = true
				table.insert(list, m)
			end
		end
		i += 1
	end
	return list, inSet
end

-- точка внутри зоны фермы?
local function inZone(farm, pos)
	local raft = raftOf()
	if not raft then return false end
	local fcf = flatFrame(raft)
	local lp = fcf:PointToObjectSpace(pos)
	for _, m in ipairs(farm.blocks) do
		local lb = fcf:PointToObjectSpace(blockCenter(m))
		if math.abs(lp.X - lb.X) <= GRID and math.abs(lp.Z - lb.Z) <= GRID and math.abs(lp.Y - lb.Y) < 8 then
			return true
		end
	end
	return false
end

local function blockAt(farm, pos)
	local raft = raftOf()
	if not raft then return nil end
	local fcf = flatFrame(raft)
	local lp = fcf:PointToObjectSpace(pos)
	for _, m in ipairs(farm.blocks) do
		local lb = fcf:PointToObjectSpace(blockCenter(m))
		if math.abs(lp.X - lb.X) <= GRID and math.abs(lp.Z - lb.Z) <= GRID then return m end
	end
	return nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
-- предметы загона (корыто, ящик): по ним не ходят — ни фермер, ни луч высоты
local function isFarmProp(m)
	return m:IsA("Model") and (C.TROUGH_NAMES[m.Name] or C.FEEDER_NAMES[m.Name] or m.Name == "Raft_wool_bin")
end

--[[ ⚠️ ГДЕ ПРЕДМЕТ — ПО ЕГО КОРПУСУ, А НЕ ПО ГАБАРИТУ МОДЕЛИ. У корыта центр
     габарита уезжал на 16 студов от корпуса («стоит в (−11.8, −24.9)» при
     корпусе в −40.6): корыто то попадало в зону, то нет, и табличка мигала
     «Корыто 10 %» ↔ «НЕТ КОРЫТА». Корпус — меш с именем модели в нижнем
     регистре (raft_farm_trough, raft_wool_bin), иначе PrimaryPart или самая
     крупная деталь. ]]
local function propPart(m)
	local p = m:FindFirstChild(m.Name:lower(), true)
	if p and p:IsA("BasePart") then return p end
	if m.PrimaryPart then return m.PrimaryPart end
	local best, vol = nil, -1
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then best, vol = d, d.Size.X * d.Size.Y * d.Size.Z end
	end
	return best
end
local function propPos(m)
	local p = propPart(m)
	return p and p.Position or m:GetPivot().Position
end

local function refreshGroundFilter()
	local ex = { propsRoot }
	local raft = workspace:FindFirstChild("Raft")
	if raft then
		for _, m in ipairs(raft:GetChildren()) do
			if isFarmProp(m) then table.insert(ex, m) end
		end
	end
	local sheep = workspace:FindFirstChild("NetCaptureSheep")
	if sheep then table.insert(ex, sheep) end
	for _, f in pairs(farms) do if f.worker then table.insert(ex, f.worker) end end
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
	groundParams.FilterDescendantsInstances = ex
end

-- высота опоры под точкой (пол дома, грядка, настил)
local function groundAt(pos, from)
	-- ⚠️ старт невысоко (4): выше — луч упирается в скат крыши над крыльцом
	local hit = workspace:Raycast(pos + Vector3.new(0, from or 4, 0), Vector3.new(0, -((from or 4) + 8), 0), groundParams)
	return hit and hit.Position.Y or pos.Y
end

-- ═══════════ реквизит: табличка ═══════════

-- деталь, приваренная к плоту Weld'ом (двигается сменой C0)
local function weldToPrimary(p, primary, worldCF)
	p.Anchored = false
	p.Massless = true
	local w = p:FindFirstChild("RaftWeld")
	if not w then
		w = Instance.new("Weld")
		w.Name = "RaftWeld"
		w.Parent = p
	end
	w.Part0 = primary
	w.Part1 = p
	w.C0 = primary.CFrame:ToObjectSpace(worldCF)
	w.C1 = CFrame.new()
	return w
end

local function mk(class, props, parent)
	local p = Instance.new(class)
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- ═══════════ фермер: поза, клипы, реквизит в руках ═══════════

local function setClip(farm, key, once)
	local model = farm.worker
	if not model then return end
	local name = Defs.CLIPS[key] or key
	if once then
		model:SetAttribute("ClipOnce", name)
		model:SetAttribute("ClipOnceT", now())
	else
		setAttr(model, "Clip", name)
	end
end

local function setActivity(farm, text)
	if farm.worker then
		setAttr(farm.worker, "Activity", text)
		-- рыбак-житель на ферме: засыпает/просыпается лицом (FishermanFace)
		require(ReplicatedStorage.FishermanFace).Sleep(farm.worker, text == "СПИТ")
	end
end

-- поставить корень фермера в мировую позу (через C0 сварки с плотом)
local function setPose(farm, worldCF)
	farm.rel = farm.primary.CFrame:ToObjectSpace(worldCF)
	if farm.weld then farm.weld.C0 = farm.rel end
end

local function worldPose(farm)
	return farm.primary.CFrame * farm.rel
end

local function faceTo(farm, pos)
	local cf = worldPose(farm)
	local d = flat(pos - cf.Position)
	if d.Magnitude < 0.2 then return end
	setPose(farm, CFrame.lookAt(cf.Position, cf.Position + d.Unit))
end

local function interrupted(farm)
	return farm.dead or farm.talkWith ~= nil
end

-- ждать, пока не перебили разговором
local function wait_(farm, seconds)
	local t = 0
	while t < seconds do
		t += task.wait(0.1)
		if farm.dead then return false end
	end
	return true
end

-- разовый клип и дождаться его конца (длительность — FarmDefs.CLIP_LEN)
local function act(farm, key, seconds)
	setClip(farm, key, true)
	return wait_(farm, seconds or Defs.CLIP_LEN[key] or 1.5)
end

-- идти к точке мира (по земле). false — перебили
local walkTo   -- с обходом предметов загона; объявлен ниже, после segHitsRect
local function walkStraight(farm, target, speed, clipKey)
	if not farm.worker then return false end
	local gy = groundAt(target)
	local tgtWorld = Vector3.new(target.X, gy + farm.footOff, target.Z)
	local tgt = farm.primary.CFrame:PointToObjectSpace(tgtWorld)
	setClip(farm, clipKey or "Walk")
	local guard = 0
	while true do
		local dt = RunService.Heartbeat:Wait()
		guard += dt
		if farm.dead then return false end
		if farm.talkWith and not farm.carrying then return false end
		local cur = farm.rel.Position
		local d = tgt - cur
		if d.Magnitude < 0.25 or guard > 40 then break end
		local newPos = cur + d.Unit * math.min(d.Magnitude, (speed or C.WALK_SPEED) * dt)
		local wPos = farm.primary.CFrame * newPos
		local wT = farm.primary.CFrame * tgt
		local look = flat(wT - wPos)
		if look.Magnitude > 0.05 then
			setPose(farm, CFrame.lookAt(wPos, wPos + look))
		else
			setPose(farm, CFrame.new(wPos) * worldPose(farm).Rotation)
		end
	end
	setClip(farm, "Idle")
	return true
end

local function setHoeVisible(farm, on)
	if not farm.worker then return end
	for _, tool in ipairs(farm.worker:GetChildren()) do
		if tool:IsA("Tool") then
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("BasePart") then
					if d:GetAttribute("ShownT") == nil then d:SetAttribute("ShownT", d.Transparency) end
					d.Transparency = on and d:GetAttribute("ShownT") or 1
				end
			end
		end
	end
end

-- груз в руках: простые детали, приваренные к рукам (хват FarmDefs.GRIP)
local function holdProps(farm, kind)
	local w = farm.worker
	if not w then return end
	for _, p in ipairs(farm.held or {}) do p:Destroy() end
	farm.held = {}
	if not kind then setHoeVisible(farm, true) return end
	setHoeVisible(farm, false)
	local function attach(arm, props, grip)
		local a = w:FindFirstChild(arm)
		if not a then return end
		local p = mk("Part", props, w)
		p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true; p.Anchored = false
		p.CFrame = a.CFrame * grip
		local j = Instance.new("Weld")
		j.Part0 = a; j.Part1 = p; j.C0 = grip
		j.Parent = p
		table.insert(farm.held, p)
	end
	if kind == "hay" then
		attach("Right Arm", { Name = "HeldHay", Size = Vector3.new(1.6, 1.0, 1.4), Color = Color3.fromRGB(214, 178, 84),
			Material = Enum.Material.Grass }, Defs.GRIP.hay)
	elseif kind == "buckets" then
		local bucket = { Name = "HeldBucket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.9, 0.9),
			Color = Color3.fromRGB(110, 110, 118), Material = Enum.Material.Metal }
		local turn = CFrame.Angles(0, 0, math.rad(90))
		attach("Right Arm", bucket, Defs.GRIP.bucket * turn)
		attach("Left Arm", bucket, Defs.GRIP.bucket * turn)
	end
end

-- ═══════════ маршрут: дом ⇄ ферма через дверь и калитку ═══════════

local function hutPoint(farm, name)
	local p = part(farm.hut, name)
	return p and p.Position
end

-- калитка фермы, ближайшая к крыльцу дома: { leaf, inside, outside }
local function farmGate(farm)
	local door = hutPoint(farm, "wp_door") or hutCenter(farm.hut)
	local best, bestD
	for _, m in ipairs(farm.blocks) do
		for _, e in ipairs({ "n1", "n2", "e1", "e2", "s1", "s2", "w1", "w2" }) do
			if m:GetAttribute("Edge_" .. e) == "gate" then
				local frame = part(m, "raft_farm_gate_" .. e)
				if frame then
					local d = (flat(frame.Position) - flat(door)).Magnitude
					if not bestD or d < bestD then
						--[[ ⚠️ «ВНУТРЬ» — ПО ОСИ РЕШЁТКИ, А НЕ НА ЦЕНТР БЛОКА. Калитка стоит
						     на половине стороны: направление на центр выходило косым
						     (5 вдоль забора на 10 внутрь), и точки входа/выхода уезжали
						     мимо калитки — фермер «ходил сбоку». ]]
						local raft = raftOf()
						local fcf = raft and flatFrame(raft) or CFrame.new()
						local l = fcf:VectorToObjectSpace(blockCenter(m) - frame.Position)
						local axis = math.abs(l.X) >= math.abs(l.Z) and Vector3.new(math.sign(l.X), 0, 0)
							or Vector3.new(0, 0, math.sign(l.Z))
						local inward = fcf:VectorToWorldSpace(axis)
						--[[ ⚠️ ТОЧКИ — ОТНОСИТЕЛЬНО ПЛОТА, А НЕ МИРА. Плот плывёт 8 студ/с:
						     пока фермер шёл к калитке, «точка за калиткой» в мировых
						     координатах оставалась там, где плот был секунды назад, —
						     позади и снаружи. Он открывал калитку и уходил в обратную
						     сторону, в воду. Мировую точку берём в момент шага: gatePt. ]]
						local prim = farm.primary.CFrame
						best = { leaf = part(m, "raft_farm_gate_" .. e .. "_leaf"), frame = frame, block = m, inward = inward,
							insideRel = prim:PointToObjectSpace(frame.Position + inward * 3),
							outsideRel = prim:PointToObjectSpace(frame.Position - inward * 3.5) }
						bestD = d
					end
				end
			end
		end
	end
	return best
end

-- отрезок пересекает прямоугольник? (Лян — Барски, в осях решётки)
local function segHitsRect(ax, az, bx, bz, x0, x1, z0, z1)
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	for _, pq in ipairs({ { -dx, ax - x0 }, { dx, x1 - ax }, { -dz, az - z0 }, { dz, z1 - az } }) do
		local p, q = pq[1], pq[2]
		if p == 0 then
			if q < 0 then return false end
		else
			local r = q / p
			if p < 0 then
				if r > t1 then return false elseif r > t0 then t0 = r end
			else
				if r < t0 then return false elseif r < t1 then t1 = r end
			end
		end
	end
	return true
end

--[[ ИДТИ СНАРУЖИ ЗАГОНА В ОБХОД. Фермер без коллизии, и прямая от крыльца к
     калитке шла сквозь забор и грядку. Загон — прямоугольник блоков в осях
     решётки; если прямая его задевает, идём через его углы (с запасом 2.5 студа),
     выбирая самый короткий путь. Точки храним относительно плота: пока
     фермер идёт первый отрезок, плот уплывает. ]]
--[[ ФЕРМЕР ОБХОДИТ КОРЫТО И ЯЩИК. Он без коллизии и шёл по прямой прямо
     сквозь корыто. Если прямая задевает корпус предмета (с запасом 1.3
     студа), идём через его углы — самый короткий путь, предпочитая углы
     внутри загона. ]]
walkTo = function(farm, target, speed, clipKey)
	if not farm.worker then return false end
	local raft = raftOf()
	if raft then
		local from = worldPose(farm).Position
		for _, m in ipairs(raft:GetChildren()) do
			local body = isFarmProp(m) and propPart(m)
			if body then
				local cf = body.CFrame
				local hx, hz = body.Size.X * 0.5 + 1.3, body.Size.Z * 0.5 + 1.3
				local a, t = cf:PointToObjectSpace(from), cf:PointToObjectSpace(target)
				if segHitsRect(a.X, a.Z, t.X, t.Z, -hx + 0.1, hx - 0.1, -hz + 0.1, hz - 0.1) then
					local corners = { { -hx, -hz }, { hx, -hz }, { hx, hz }, { -hx, hz } }
					local A, B = { a.X, a.Z }, { t.X, t.Z }
					local best, bestLen
					local function consider(path)
						local len = 0
						for i = 1, #path - 1 do
							local p, q = path[i], path[i + 1]
							if segHitsRect(p[1], p[2], q[1], q[2], -hx + 0.1, hx - 0.1, -hz + 0.1, hz - 0.1) then return end
							len += math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
						end
						for i = 2, #path - 1 do
							if not inZone(farm, cf * Vector3.new(path[i][1], 0, path[i][2])) then len += 50 end
						end
						if not bestLen or len < bestLen then best, bestLen = path, len end
					end
					for i = 1, 4 do consider({ A, corners[i], B }) end
					for i = 1, 4 do
						local j = i % 4 + 1
						consider({ A, corners[i], corners[j], B })
						consider({ A, corners[j], corners[i], B })
					end
					if best then
						-- углы — относительно плота: пока идём, плот уплывает
						local prim = farm.primary.CFrame
						local legs = {}
						for k = 2, #best - 1 do
							table.insert(legs, prim:PointToObjectSpace(cf * Vector3.new(best[k][1], a.Y, best[k][2])))
						end
						local last = prim:PointToObjectSpace(target)
						for _, rel in ipairs(legs) do
							if not walkStraight(farm, farm.primary.CFrame * rel, speed, clipKey) then return false end
						end
						return walkStraight(farm, farm.primary.CFrame * last, speed, clipKey)
					end
				end
			end
		end
	end
	return walkStraight(farm, target, speed, clipKey)
end

local function walkAround(farm, target, speed, clip)
	local raft = raftOf()
	if not raft or #farm.blocks == 0 then return walkTo(farm, target, speed, clip) end
	local fcf = flatFrame(raft)
	local x0, x1, z0, z1
	for _, m in ipairs(farm.blocks) do
		local l = fcf:PointToObjectSpace(blockCenter(m))
		x0 = math.min(x0 or math.huge, l.X - GRID); x1 = math.max(x1 or -math.huge, l.X + GRID)
		z0 = math.min(z0 or math.huge, l.Z - GRID); z1 = math.max(z1 or -math.huge, l.Z + GRID)
	end
	local a = fcf:PointToObjectSpace(worldPose(farm).Position)
	local b = fcf:PointToObjectSpace(target)
	local M = 2.5
	local corners = { { x0 - M, z0 - M }, { x1 + M, z0 - M }, { x1 + M, z1 + M }, { x0 - M, z1 + M } }
	local A, B = { a.X, a.Z }, { b.X, b.Z }
	local sh = 0.3
	local best, bestLen
	local function consider(path)
		local len = 0
		for i = 1, #path - 1 do
			local p, q = path[i], path[i + 1]
			if segHitsRect(p[1], p[2], q[1], q[2], x0 + sh, x1 - sh, z0 + sh, z1 - sh) then return end
			len += math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
		end
		if not bestLen or len < bestLen then best, bestLen = path, len end
	end
	consider({ A, B })
	for i = 1, 4 do consider({ A, corners[i], B }) end
	for i = 1, 4 do
		local j = i % 4 + 1
		consider({ A, corners[i], corners[j], B })
		consider({ A, corners[j], corners[i], B })
	end
	best = best or { A, B }
	-- промежуточные точки — в осях PrimaryPart (едут вместе с плотом)
	local prim = farm.primary.CFrame
	local legs = {}
	for k = 2, #best - 1 do
		table.insert(legs, prim:PointToObjectSpace(fcf:PointToWorldSpace(Vector3.new(best[k][1], a.Y, best[k][2]))))
	end
	local last = prim:PointToObjectSpace(target)
	for _, rel in ipairs(legs) do
		if not walkTo(farm, farm.primary.CFrame * rel, speed, clip) then return false end
	end
	return walkTo(farm, farm.primary.CFrame * last, speed, clip)
end

-- точка калитки в мире — сейчас (плот едет)
local function gatePt(farm, gate, which)
	return farm.primary.CFrame * (which == "inside" and gate.insideRel or gate.outsideRel)
end

local function setGate(leaf, open)
	if leaf and typeof(_G.SetGate) == "function" then pcall(_G.SetGate, leaf, open) end
end

-- из дома (комната/кровать/крыльцо) на ферму
local function goToFarm(farm)
	if farm.where == "farm" then return true end
	if farm.where == "bench" then farm.where = "porch" end
	local hutLeaf = part(farm.hut, "raft_farmhut_gate_leaf")
	if farm.where == "room" then
		setGate(hutLeaf, true)
		task.wait(0.4)
		if not walkTo(farm, hutPoint(farm, "wp_door"), C.WALK_SPEED) then setGate(hutLeaf, false) return false end
		setGate(hutLeaf, false)
		farm.where = "porch"
	end
	local gate = farmGate(farm)
	if not gate then return false end
	if not walkAround(farm, gatePt(farm, gate, "outside"), C.WALK_SPEED, farm.carrying and farm.carryWalk or "WalkHoe") then return false end
	faceTo(farm, gate.frame.Position)
	setGate(gate.leaf, true)
	if not farm.carrying then act(farm, "OperateDoor", 0.7) else task.wait(0.5) end
	if not walkTo(farm, gatePt(farm, gate, "inside"), C.WALK_SPEED, farm.carrying and farm.carryWalk or "WalkHoe") then setGate(gate.leaf, false) return false end
	setGate(gate.leaf, false)
	farm.where = "farm"
	return true
end

-- с фермы к дому: dest = "porch" | "room"
local function goToHut(farm, dest)
	if farm.where == "bench" then farm.where = "porch" end
	if farm.where == "farm" then
		local gate = farmGate(farm)
		if gate then
			if not walkTo(farm, gatePt(farm, gate, "inside"), C.WALK_SPEED, farm.carrying and farm.carryWalk or "WalkHoe") then return false end
			faceTo(farm, gate.frame.Position)
			setGate(gate.leaf, true)
			task.wait(0.5)
			if not walkTo(farm, gatePt(farm, gate, "outside"), C.WALK_SPEED, farm.carrying and farm.carryWalk or "WalkHoe") then setGate(gate.leaf, false) return false end
			setGate(gate.leaf, false)
		end
		if not walkAround(farm, hutPoint(farm, "wp_door"), C.WALK_SPEED, farm.carrying and farm.carryWalk or "WalkHoe") then return false end
		farm.where = "porch"
	end
	if dest == "room" and farm.where == "porch" then
		local hutLeaf = part(farm.hut, "raft_farmhut_gate_leaf")
		setGate(hutLeaf, true)
		task.wait(0.4)
		if not walkTo(farm, hutPoint(farm, "wp_inside"), C.WALK_SPEED) then setGate(hutLeaf, false) return false end
		setGate(hutLeaf, false)
		farm.where = "room"
	end
	return true
end

-- случайная точка внутри зоны (не у самого забора)
local function zonePoint(farm)
	local raft = raftOf()
	if not raft or #farm.blocks == 0 then return nil end
	local fcf = flatFrame(raft)
	--[[ ⚠️ НЕ В КОРЫТЕ. Точка случайная, и фермер вставал прямо в корыто:
	     луч высоты находил его крышку, и он «работал» на нём сверху. Точки
	     ближе 2 студов к корыту/ящику отбрасываем. ]]
	local props = {}
	for _, p in ipairs(raft:GetChildren()) do
		if isFarmProp(p) then
			local pp = propPart(p)
			if pp then table.insert(props, { cf = pp.CFrame, half = pp.Size * 0.5 + Vector3.new(2, 0, 2) }) end
		end
	end
	for _ = 1, 10 do
		local m = farm.blocks[math.random(1, #farm.blocks)]
		local c = blockCenter(m)
		local pt = c + (fcf - fcf.Position) * Vector3.new(math.random() * 14 - 7, 0, math.random() * 14 - 7)
		local free = true
		for _, pr in ipairs(props) do
			local l = pr.cf:PointToObjectSpace(pt)
			if math.abs(l.X) <= pr.half.X and math.abs(l.Z) <= pr.half.Z then free = false break end
		end
		if free then return pt end
	end
	return nil
end

-- ═══════════ задачи фермера ═══════════

-- точка в 2.6 студа от предмета, со стороны центра ближайшего блока (внутри загона)
local function approach(farm, p)
	local best, bd
	for _, m in ipairs(farm.blocks) do
		local d = (flat(blockCenter(m)) - flat(p)).Magnitude
		if not bd or d < bd then best, bd = m, d end
	end
	local dir = best and flat(blockCenter(best) - p) or Vector3.zero
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	return p + dir * 2.6
end

local function sheepInZone(farm)
	local list = {}
	for s in pairs(farm.sheep) do
		if s.Parent and s.PrimaryPart then table.insert(list, s) end
	end
	return list
end

-- пополнить из запаса дома: "hay" → кормушка, "water" → корыто
local function taskRefill(farm, kind)
	local hut = farm.hut
	local storeAttr = kind == "hay" and "StoreHay" or "StoreWater"
	setActivity(farm, kind == "hay" and "НЕСЁТ СЕНО" or "НОСИТ ВОДУ")
	if not goToHut(farm, "porch") then return end
	local take = math.min(hut:GetAttribute(storeAttr) or 0, kind == "hay" and C.CARRY_HAY or C.CARRY_WATER)
	if take <= 0 then return end
	act(farm, kind == "hay" and "Scoop" or "PickUp")
	hut:SetAttribute(storeAttr, (hut:GetAttribute(storeAttr) or 0) - take)
	farm.carrying = { kind = kind, amount = take }
	farm.carryWalk = kind == "hay" and "HayShoulderWalk" or "BucketsWalk"
	holdProps(farm, kind == "hay" and "hay" or "buckets")
	if not goToFarm(farm) then return end
	local bin = kind == "hay" and farm.feederModel or farm.troughModel
	if bin and bin.Parent then
		local bp = propPos(bin)
		-- встать у ДЛИННОГО борта, со стороны загона (у торца — внутри корыта)
		local body = propPart(bin)
		local spot = approach(farm, bp)
		if body then
			local long = body.Size.X >= body.Size.Z
			local across = long and body.CFrame.LookVector or body.CFrame.RightVector
			across = Vector3.new(across.X, 0, across.Z).Unit
			local half = (long and body.Size.Z or body.Size.X) * 0.5 + 1.6
			local me = worldPose(farm).Position
			local best
			for _, sgn in ipairs({ 1, -1 }) do
				local p = bp + across * sgn * half
				if inZone(farm, p) and (not best or (p - me).Magnitude < (best - me).Magnitude) then best = p end
			end
			spot = best or spot
		end
		walkTo(farm, spot, C.CARRY_SPEED, farm.carryWalk)
		faceTo(farm, propPos(bin))   -- заново: плот уплыл, пока нёс
		act(farm, kind == "hay" and "PlaceHay" or "PourWater")
		local attr, max = kind == "hay" and "Hay" or "Water", kind == "hay" and C.FEEDER_MAX or C.TROUGH_MAX
		bin:SetAttribute(attr, math.min(max, (bin:GetAttribute(attr) or 0) + take))
	else
		-- корыто/кормушку убрали, пока нёс: груз обратно в запас
		hut:SetAttribute(storeAttr, (hut:GetAttribute(storeAttr) or 0) + take)
	end
	farm.carrying = nil
	holdProps(farm, nil)
end

local function taskHoe(farm)
	setActivity(farm, "РЫХЛИТ ЗЕМЛЮ")
	if not goToFarm(farm) then return end
	local p = zonePoint(farm)
	if not p or not walkTo(farm, p, C.WALK_SPEED, "WalkHoe") then return end
	act(farm, "HoeEnter")
	setClip(farm, "HoeLoop")
	wait_(farm, 1.6 * math.random(3, 5))
	act(farm, "HoeExit")
	if math.random() < 0.5 then act(farm, "WipeBrow") end
end

local function taskSheep(farm)
	local list = sheepInZone(farm)
	if #list == 0 then return false end
	table.sort(list, function(a, b) return (a:GetAttribute("Satiety") or 100) < (b:GetAttribute("Satiety") or 100) end)
	local s = list[1]
	setActivity(farm, "КОРМИТ ОВЕЦ")
	if not goToFarm(farm) then return true end
	local sp = s.PrimaryPart and s.PrimaryPart.Position
	if not sp then return true end
	-- подходить со стороны загона: к овце у забора — не снаружи
	if not walkTo(farm, approach(farm, sp), C.WALK_SPEED, "WalkHoe") then return true end
	if not (s.Parent and s.PrimaryPart) then return true end
	faceTo(farm, s.PrimaryPart.Position)
	if (s:GetAttribute("Satiety") or 100) < 70 and (farm.hut:GetAttribute("StoreHay") or 0) >= 2 then
		farm.hut:SetAttribute("StoreHay", (farm.hut:GetAttribute("StoreHay") or 0) - 2)
		act(farm, "FeedHand")
		s:SetAttribute("Satiety", math.min(100, (s:GetAttribute("Satiety") or 0) + C.FEED_BY_HAND))
	else
		act(farm, math.random() < 0.5 and "CalmAnimal" or "InspectAnimal")
	end
	return true
end

local IDLES = { "IdleLook", "WipeBrow", "StretchBack" }
local function taskIdle(farm)
	setActivity(farm, "ОТДЫХАЕТ")
	if math.random() < 0.35 then
		setClip(farm, "LeanTool")
		wait_(farm, 4 + math.random() * 3)
		setClip(farm, "Idle")
	else
		act(farm, IDLES[math.random(1, #IDLES)])
		wait_(farm, 1 + math.random() * 2)
	end
end

--[[ ЗАБАСТОВКА — НА ЛАВКЕ У КРЫЛЬЦА (wp_sit, лицом к wp_sit_look).
     Раньше он замирал там, где его застал долг, — обычно у калитки, на
     открытом плоту: «фермер не на ферме ходит, а сбоку». ]]
local function taskStrike(farm)
	setActivity(farm, "БАСТУЕТ")
	holdProps(farm, nil)
	if farm.where ~= "bench" then
		if not goToHut(farm, "porch") then return end
		local seat = hutPoint(farm, "wp_sit")
		if seat then
			walkTo(farm, seat, C.WALK_SPEED)
			act(farm, "Shrug")
			-- ⚠️ перечитать ПОСЛЕ ходьбы: плот уплыл, старые мировые точки устарели
			local look
			seat, look = hutPoint(farm, "wp_sit"), hutPoint(farm, "wp_sit_look")
			-- маркер — поверхность лавки; корень R6 сидя на студ выше неё
			local root = seat + Vector3.new(0, 1, 0)
			local dir = look and flat(look - seat) or Vector3.zero
			dir = dir.Magnitude > 0.05 and dir.Unit or worldPose(farm).LookVector
			setPose(farm, CFrame.lookAt(root, root + dir))
			setClip(farm, "House_Sit")
			farm.where = "bench"
		end
	end
	wait_(farm, 3)
end

-- встать с лавки обратно на крыльцо
local function leaveBench(farm)
	if farm.where ~= "bench" then return end
	local seat = hutPoint(farm, "wp_sit")
	setClip(farm, "Idle")
	if seat then
		local p = Vector3.new(seat.X, groundAt(seat) + farm.footOff, seat.Z)
		setPose(farm, CFrame.new(p) * worldPose(farm).Rotation)
	end
	farm.where = "porch"
end

-- разговор с игроком: остановился, повернулся, помахал, сказал, кивнул
local function taskTalk(farm)
	local player = farm.talkWith
	farm.talkWith = nil
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	setActivity(farm, "РАЗГОВАРИВАЕТ")
	faceTo(farm, hrp.Position)
	act(farm, "Wave")
	setClip(farm, "Talk")
	local hut = farm.hut
	local lines = {}
	local tm, fm = farm.troughModel, farm.feederModel
	if not tm then
		table.insert(lines, "Поставь в загоне корыто — без воды овцы дают вдвое меньше.")
	elseif (tm:GetAttribute("Water") or 0) / C.TROUGH_MAX * 100 < C.THIRSTY_BELOW then
		table.insert(lines, "Корыто почти пустое — налей воды кружкой.")
	end
	if not fm then
		table.insert(lines, "Кормушки нет — кормлю овец с руки из запаса у дома.")
	elseif (fm:GetAttribute("Hay") or 0) < 15 and (hut:GetAttribute("StoreHay") or 0) < 5 then
		table.insert(lines, "Сено кончается: положи листву в кормушку.")
	end
	if #sheepInZone(farm) == 0 then table.insert(lines, "Овец нет. Поймай овцу сеткомётом и отпусти за забором.") end
	if #lines == 0 then table.insert(lines, "Всё в порядке, хозяин! Овцы сыты, вода есть.") end
	--[[ ⚠️ «ПОГОВОРИТЬ» — ДИАЛОГОВОЕ ОКНО, КАК В КВЕСТАХ, А НЕ УВЕДОМЛЕНИЕ. Раньше
	     советы фермера всплывали плашкой с красным крестом — выглядело как ошибка.
	     Теперь каждая мысль — отдельная реплика, с портретом говорящего. ]]
	local spoken = false
	if typeof(_G.StartCustomDialogue) == "function" then
		local dl = {}
		for _, l in ipairs(lines) do table.insert(dl, { who = "npc", text = l }) end
		local name = hut:GetAttribute("WorkerName")
		spoken = _G.StartCustomDialogue(player, {
			npcName = (type(name) == "string" and name ~= "") and name or "Фермер",
			npcModel = farm.worker, lines = dl,
		}) == true
	end
	if not spoken then notify(player, "info", "Фермер", table.concat(lines, " ")) end
	wait_(farm, 2.5)
	act(farm, #lines == 1 and lines[1]:find("порядке") and "ThumbUp" or "Nod")
	setClip(farm, "Idle")
end

local function goSleep(farm)
	setActivity(farm, "ИДЁТ СПАТЬ")
	holdProps(farm, nil)
	if not goToHut(farm, "room") then return end
	local bed, head = hutPoint(farm, "wp_bed"), hutPoint(farm, "wp_bed_head")
	if bed and head then
		local toHead = flat(head - bed)
		toHead = toHead.Magnitude > 0.05 and toHead.Unit or Vector3.new(1, 0, 0)
		-- ⚠️ ЛИЦОМ К НОГАМ: клип House_Sleep кладёт тело назад (см. HouseSystem.lieCF)
		setPose(farm, CFrame.lookAt(bed, bed - toHead))
		setHoeVisible(farm, false)
		act(farm, "SleepEnter", 1.2)
		setClip(farm, "Sleep")
		farm.where = "bed"
	end
	setActivity(farm, "СПИТ")
end

local function wakeUp(farm)
	setClip(farm, "Idle")
	act(farm, "SleepExit", 1.2)
	local inside = hutPoint(farm, "wp_inside")
	if inside then
		setPose(farm, CFrame.lookAt(Vector3.new(inside.X, groundAt(inside) + farm.footOff, inside.Z),
			Vector3.new(inside.X, groundAt(inside) + farm.footOff, inside.Z) + flat((hutPoint(farm, "wp_door") or inside) - inside + Vector3.new(0.01, 0, 0)).Unit))
	end
	setHoeVisible(farm, true)
	farm.where = "room"
end

local function workerLoop(farm)
	while not farm.dead do
		local ok, err = pcall(function()
			local hut = farm.hut
			if farm.talkWith then taskTalk(farm) return end
			if night() then
				leaveBench(farm)
				if farm.where ~= "bed" then goSleep(farm) else wait_(farm, 2) end
				return
			end
			if farm.where == "bed" then wakeUp(farm) end
			if (farm.worker:GetAttribute("Debt") or 0) > 0 then taskStrike(farm) return end
			leaveBench(farm)
			-- носить есть куда, только если игрок поставил корыто / кормушку
			local tm, fm = farm.troughModel, farm.feederModel
			local feederPct = fm and (fm:GetAttribute("Hay") or 0) / C.FEEDER_MAX * 100 or 100
			local troughPct = tm and (tm:GetAttribute("Water") or 0) / C.TROUGH_MAX * 100 or 100
			if troughPct < C.REFILL_BELOW and (hut:GetAttribute("StoreWater") or 0) >= 1 then
				taskRefill(farm, "water")
			elseif feederPct < C.REFILL_BELOW and (hut:GetAttribute("StoreHay") or 0) >= 1 then
				taskRefill(farm, "hay")
			else
				local r = math.random()
				if r < 0.35 and taskSheep(farm) then return end
				if r < 0.75 then taskHoe(farm) else
					if farm.where ~= "farm" then goToFarm(farm) end
					taskIdle(farm)
				end
			end
		end)
		if not ok then
			warn(LOG .. " фермер: " .. tostring(err))
			if farm.carrying then
				-- груз не пропадает: вернуть в запас дома
				local attr = farm.carrying.kind == "hay" and "StoreHay" or "StoreWater"
				farm.hut:SetAttribute(attr, (farm.hut:GetAttribute(attr) or 0) + farm.carrying.amount)
				farm.carrying = nil
				holdProps(farm, nil)
			end
			task.wait(2)
		end
		task.wait(0.2)
	end
end

-- ═══════════ фермер: появление ═══════════

--[[ КТО РАБОТАЕТ НА ФЕРМЕ. По умолчанию — нанятый фермер (шаблон Farmer). Если
     игрок назначил сюда выжившего (SurvivorService, окно «Управление
     выжившими»), на доме атрибуты WorkerModel / WorkerName / WorkerWage /
     IncomeBonus: тогда вместо фермера появляется модель этого выжившего и
     работает тем же циклом. Атрибуты на доме сохраняются вместе с плотом. ]]
local function workerTemplate(farm)
	local custom = farm.hut:GetAttribute("WorkerModel")
	if type(custom) == "string" and custom ~= "" and typeof(_G.SurvivorTemplate) == "function" then
		local tpl = _G.SurvivorTemplate(custom)
		if tpl then return tpl, true end
		warn(LOG .. " модели выжившего «" .. custom .. "» нет — на ферме будет обычный фермер")
	end
	return AssetFind.find(C.FARMER), false
end

-- ставка работника в час: у выжившего — своя (зарплата в день / 24)
local function farmWage(farm)
	return farm.hut:GetAttribute("WorkerWage") or C.WAGE
end

local function spawnWorker(farm)
	local tpl, isSurvivor = workerTemplate(farm)
	if not (tpl and tpl:IsA("Model")) then
		warn(LOG .. " шаблона Farmer нет в ReplicatedStorage — фермера не будет")
		return
	end
	local inside = hutPoint(farm, "wp_inside")
	if not inside then
		warn(LOG .. " в доме нет маркера wp_inside — фермера ставить некуда")
		return
	end
	local m = tpl:Clone()
	m.Name = "RaftFarmer"
	if isSurvivor then
		-- свой R6 без стандартных поворотов суставов: клиент пересчитает клипы фермера
		if typeof(_G.SurvivorNeedsRetarget) ~= "function" or _G.SurvivorNeedsRetarget(farm.hut:GetAttribute("WorkerModel")) then
			m:SetAttribute("RigRetarget", "R6")
		end
		m:SetAttribute("SurvivorWorker", farm.hut:GetAttribute("WorkerModel"))
		m:SetAttribute("SurvivorFace", true)   -- мимика лица (SurvivorsUI.client)
		--[[ НА ФЕРМЕ — РАБОЧИЙ ИНСТРУМЕНТ, А НЕ САБЛЯ. Оружие капитана (Tool) снимаем
		     и выдаём инструменты нанятого фермера (мотыга и т.п.) из его шаблона.
		     Сварки внутри копии, смотрящие на руку шаблона фермера, убираем —
		     ниже (task.delay) инструмент приваривается к руке по хвату Defs.GRIP. ]]
		for _, d in ipairs(m:GetChildren()) do
			if d:IsA("Tool") then d:Destroy() end
		end
		local farmerTpl = AssetFind.find(C.FARMER)
		for _, tool in ipairs(farmerTpl and farmerTpl:GetChildren() or {}) do
			if tool:IsA("Tool") then
				local t = tool:Clone()
				for _, j in ipairs(t:GetDescendants()) do
					if (j:IsA("JointInstance") or j:IsA("WeldConstraint"))
						and not ((j.Part0 == nil or j.Part0:IsDescendantOf(t)) and (j.Part1 == nil or j.Part1:IsDescendantOf(t))) then
						j:Destroy()
					end
				end
				t.Parent = m
			end
		end
		m.ModelStreamingMode = Enum.ModelStreamingMode.Default
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not hrp then warn(LOG .. " у Farmer нет HumanoidRootPart") m:Destroy() return end
	m.PrimaryPart = hrp
	-- высота корня над ступнями — по ноге рига (R6: 3 студа)
	local leg = m:FindFirstChild("Left Leg")
	farm.footOff = leg and (hrp.Position.Y - (leg.Position.Y - leg.Size.Y * 0.5)) or 3
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d == hrp
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			d.RootPriority = -10   -- корнем сборки плота остаётся плот
		elseif (d:IsA("Script") or d:IsA("LocalScript")) and d:GetAttribute("KeepOnWorker") then
			d.Enabled = true   -- HD-лицо / аура жителя (метка SurvivorService) — не удаляем
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.RequiresNeck = false
		hum.BreakJointsOnDeath = false
		pcall(function() hum.EvaluateStateMachine = false end)
		hum.PlatformStand = true
	end
	m:SetAttribute("CrewAnim", true)
	m:SetAttribute("Role", isSurvivor and (farm.hut:GetAttribute("WorkerName") or "ВЫЖИВШИЙ") or "ФЕРМЕР")
	m:SetAttribute("Activity", "ПРОСНУЛСЯ")
	m:SetAttribute("WagePerHour", farmWage(farm))
	m:SetAttribute("Debt", farm.hut:GetAttribute("WorkerDebt") or 0)
	m:SetAttribute("NextPayAt", now() + 30)
	m:SetAttribute("FarmHut", farm.id)
	m:SetAttribute("Clip", Defs.CLIPS.Idle)

	local door = hutPoint(farm, "wp_door") or inside + Vector3.new(0, 0, -5)
	local look = flat(door - inside)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local base = Vector3.new(inside.X, groundAt(inside) + farm.footOff, inside.Z)
	m:PivotTo(CFrame.lookAt(base, base + look))
	m.Parent = workspace
	CollectionService:AddTag(m, "FarmWorker")

	farm.worker = m
	farm.rel = farm.primary.CFrame:ToObjectSpace(hrp.CFrame)
	local w = Instance.new("Weld")
	w.Name = "RaftFarmerWeld"
	w.Part0 = farm.primary
	w.Part1 = hrp
	w.C0 = farm.rel
	w.Parent = hrp
	farm.weld = w
	hrp.Anchored = false
	farm.where = "room"
	refreshGroundFilter()

	-- мотыга в руке: если у инструмента нет сварки с рукой — приварить по хвату
	task.delay(0.3, function()
		for _, tool in ipairs(m:GetChildren()) do
			local h = tool:IsA("Tool") and tool:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and #h:GetJoints() == 0 then
				local arm = m:FindFirstChild("Right Arm")
				if arm then
					local j = Instance.new("Weld")
					j.Part0 = arm; j.Part1 = h; j.C0 = Defs.GRIP.hoe or Defs.GRIP.rake
					j.Parent = h
				end
			end
		end
	end)

	-- разговор / выплата долга
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FarmerTalk"
	prompt.ObjectText = isSurvivor and (farm.hut:GetAttribute("WorkerName") or "Выживший") or "Фермер"
	prompt.ActionText = "Поговорить"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = hrp
	farm.talkPrompt = prompt
	prompt.Triggered:Connect(function(player)
		local debt = m:GetAttribute("Debt") or 0
		if debt > 0 then
			if typeof(_G.SpendPirate) == "function" and _G.SpendPirate(player, debt) then
				m:SetAttribute("Debt", 0)
				farm.hut:SetAttribute("WorkerDebt", 0)
				notify(player, "success", "Долг выплачен", ("Фермер снова работает (−%d)"):format(debt))
			else
				notify(player, "warn", "Не хватает монет", ("Долг фермеру: %d"):format(debt))
			end
			return
		end
		if farm.where == "bed" then
			notify(player, "info", "Фермер спит", "Утром снова выйдет на ферму")
			return
		end
		farm.talkWith = player
	end)

	task.spawn(workerLoop, farm)
	print(("%s фермер вышел на работу (дом %s)"):format(LOG, farm.id))
end

-- ═══════════ калитка, табличка, постройки игрока ═══════════

--[[ ТАБЛИЧКА — СБОКУ ОТ КАЛИТКИ, НАД ПЕРЕДНИМ ЗАБОРОМ. Калитку НЕ двигаем:
     ферма остаётся такой, какой её поставили (раньше дом разворачивал калитку к
     себе — «ферма оборачивается в сторону дома»). Доска висит над забором
     соседней клетки той же стороны, зеркально калитке, лицом наружу; она
     двусторонняя (клиент рисует обе стороны). ]]
local function placeSign(farm)
	local gate = farmGate(farm)
	if not (gate and farm.sign) then return end
	local bc = blockCenter(gate.block)
	local sideCenter = bc - gate.inward * GRID
	local off = flat(gate.frame.Position - sideCenter)
	if off.Magnitude < 1 then off = Vector3.new(-gate.inward.Z, 0, gate.inward.X) * (GRID * 0.5) end
	local spot = sideCenter - off
	local gy = groundAt(spot - gate.inward * 1.5)
	local pos = Vector3.new(spot.X, gy + 4.3 + farm.sign.Size.Y * 0.5, spot.Z) - gate.inward * 0.3
	farm.signWeld.C0 = farm.primary.CFrame:ToObjectSpace(CFrame.lookAt(pos, pos - gate.inward))
end

local function buildProps(farm)
	local folder = Instance.new("Folder")
	folder.Name = "Farm_" .. farm.id
	folder.Parent = propsRoot
	farm.folder = folder

	-- табличка: доска, SurfaceGui на неё вешает клиент (Adornee), ссылка на дом — ObjectValue
	local sign = mk("Part", { Name = "FarmSign", Size = Vector3.new(7.8, 5.6, 0.3), Color = Color3.fromRGB(96, 66, 40),
		Material = Enum.Material.WoodPlanks, CanCollide = false, CanQuery = false, CanTouch = false }, folder)
	farm.sign = sign
	farm.signWeld = weldToPrimary(sign, farm.primary, CFrame.new(hutCenter(farm.hut)))
	local link = Instance.new("ObjectValue")
	link.Name = "Farm"
	link.Value = farm.hut
	link.Parent = sign
	CollectionService:AddTag(sign, "FarmSign")

	--[[ ⚠️ ЗАПАС В ДОМЕ БЕЗ ПОДСКАЗОК. Кнопки «Листва в запас» / «Вода в запас
	     (кружка)» на домике убраны по просьбе: лишние кружки посреди фермы. Запас
	     (атрибуты StoreHay / StoreWater, по 30 на старте) остаётся — из него фермер
	     носит воду и сено в корыто и кормушку; пополнять ферму игрок может прямо
	     в корыто (кружкой) и в кормушку (листвой). ]]

end

--[[ КОРЫТО И КОРМУШКА — ПОСТРОЙКИ ИГРОКА (RaftFarmConfig.TROUGH_NAMES /
     FEEDER_NAMES). Сами не ставим: пока игрок не построил, их нет — воды 0 %,
     доход овец ×PENALTY, сено только с руки фермера. Уровень — атрибутом на
     самой постройке (Water / Hay), он сохраняется вместе с ней. ]]
local function setupBin(farm, model, water)
	if model:GetAttribute("FarmBinReady") then return end
	model:SetAttribute("FarmBinReady", true)
	local attr = water and "Water" or "Hay"
	if model:GetAttribute(attr) == nil then model:SetAttribute(attr, 0) end
	local anchor = model.PrimaryPart
	if not anchor then
		local vol = -1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then anchor, vol = d, d.Size.X * d.Size.Y * d.Size.Z end
		end
	end
	if not anchor then return end
	if water then
		CollectionService:AddTag(model, "FarmTrough")
		model:SetAttribute("WaterMax", C.TROUGH_MAX)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FarmBinPrompt"
	prompt.ObjectText = water and "Корыто" or "Кормушка"
	prompt.ActionText = water and "Налить воду" or ("Положить листву (+%d сена)"):format(C.HAY_PER_LEAF)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		local have = model:GetAttribute(attr) or 0
		local max = water and C.TROUGH_MAX or C.FEEDER_MAX
		if have >= max then notify(player, "warn", water and "Корыто полное" or "Кормушка полная", "Больше не влезет") return end
		if water then
			local char = player.Character
			local tool = char and char:FindFirstChildWhichIsA("Tool")
			local charges = tool and tonumber(tool:GetAttribute("CupCharges")) or 0
			-- ⚠️ ТОЛЬКО ПРЕСНАЯ: овцы и запас фермы солёную воду не берут (раньше через E заливалась морская)
			if tool and charges > 0 and tool:GetAttribute("CupState") == "salty" then
				notify(player, "warn", "Солёная вода", "Овцы морскую воду не пьют — сначала очисти её в очистителе")
				return
			end
			if not tool or charges <= 0 or tool:GetAttribute("CupState") ~= "fresh" then
				notify(player, "warn", "Нужна вода", "Возьми в руки кружку или бутылку с пресной водой")
				return
			end
			charges -= 1
			tool:SetAttribute("CupCharges", charges)
			if charges <= 0 and typeof(_G.SetCupState) == "function" then pcall(_G.SetCupState, tool, "empty") end
			model:SetAttribute(attr, math.min(max, have + C.WATER_PER_CUP))
		else
			local inv = (typeof(_G.GetInventory) == "function" and _G.GetInventory(player)) or {}
			if (inv[C.HAY_ITEM] or 0) < 1 then notify(player, "warn", "Нужна листва", ("1 листва → %d сена"):format(C.HAY_PER_LEAF)) return end
			_G.RemoveResourceFromInventory(player, C.HAY_ITEM, 1)
			if typeof(_G.SendInventory) == "function" then _G.SendInventory(player) end
			model:SetAttribute(attr, math.min(max, have + C.HAY_PER_LEAF))
		end
	end)
end

-- найти в загоне постройки игрока: первое корыто и первую кормушку
local function findBins(farm, raft)
	local trough, feeder
	for _, m in ipairs(raft:GetChildren()) do
		local isT, isF = C.TROUGH_NAMES[m.Name], C.FEEDER_NAMES[m.Name]
		if (isT or isF) and m:IsA("Model") and inZone(farm, propPos(m)) then
			if isT and not trough then trough = m; setupBin(farm, m, true) end
			if isF and not feeder then feeder = m; setupBin(farm, m, false) end
		end
	end
	farm.troughModel, farm.feederModel = trough, feeder
	-- ДИАГНОСТИКА: корыто нашлось / потерялось — в лог один раз на смену
	local state = trough and ("найдено " .. trough:GetFullName()) or "нет"
	if farm.lastTroughLog ~= state then
		farm.lastTroughLog = state
		print(("%s ферма %s: корыто %s"):format(LOG, farm.id, state))
		if not trough then
			local fcf = flatFrame(raft)
			for _, m in ipairs(raft:GetChildren()) do
				if C.TROUGH_NAMES[m.Name] then
					local l = fcf:PointToObjectSpace(propPos(m))
					local bl = {}
					for _, b in ipairs(farm.blocks) do
						local lb = fcf:PointToObjectSpace(blockCenter(b))
						table.insert(bl, ("(%.1f, %.1f, y%.1f)"):format(lb.X, lb.Z, lb.Y))
					end
					warn(("%s   %s стоит в (%.1f, %.1f, y%.1f) — вне зоны; блоки: %s"):format(LOG, m.Name, l.X, l.Z, l.Y, table.concat(bl, " ")))
				end
			end
		end
	end
end

-- ═══════════ экономика ═══════════

local function tickFarm(farm, dt, dh)
	local hut = farm.hut
	local raft = raftOf()
	if not raft then return end
	if farm.primary ~= raft.PrimaryPart then return end

	--[[ ЗОНА — ЗАНОВО КАЖДЫЙ ТИК. Пристроили блок к ферме — он сразу в зоне:
	     фермер рыхлит и там (zonePoint), обходит загон по новым границам
	     (walkAround), калитку ищет среди всех блоков, овцы в нём дают доход. ]]
	local n0 = #farm.blocks
	farm.blocks = clusterOf(hut, raft)
	if #farm.blocks ~= n0 then
		print(("%s ферма %s: блоков теперь %d"):format(LOG, farm.id, #farm.blocks))
		if #farm.blocks == 0 then
			local fcf = flatFrame(raft)
			local hc = fcf:PointToObjectSpace(hutCenter(hut))
			for _, m in ipairs(raft:GetChildren()) do
				if m:IsA("Model") and m.Name == C.BLOCK then
					local l = fcf:PointToObjectSpace(blockCenter(m))
					warn(("%s   блок в (%.1f, %.1f), дом в (%.1f, %.1f) — не вплотную"):format(LOG, l.X, l.Z, hc.X, hc.Z))
				end
			end
		end
		farm.propTimer = 99   -- табличку — к новой калитке сразу
	end
	farm.propTimer = (farm.propTimer or 0) + dt
	if farm.propTimer > 3 then farm.propTimer = 0; placeSign(farm) end
	findBins(farm, raft)

	-- овцы в зоне
	local sheepMax = #farm.blocks * C.SHEEP_PER_BLOCK
	local seen = {}
	local folder = workspace:FindFirstChild("NetCaptureSheep")
	if folder then
		for _, s in ipairs(folder:GetChildren()) do
			local root = s:IsA("Model") and s.PrimaryPart
			if root and s:GetAttribute("CarrierUserId") == nil and inZone(farm, root.Position) then
				seen[s] = true
			end
		end
	end
	for s in pairs(farm.sheep) do
		if not seen[s] then
			farm.sheep[s] = nil
			if s.Parent then
				CollectionService:RemoveTag(s, "FarmSheep")
				s:SetAttribute("IncomePerHour", nil)
				s:SetAttribute("FarmHut", nil)
			end
		end
	end

	local tm, fm = farm.troughModel, farm.feederModel
	local water = tm and (tm:GetAttribute("Water") or 0) or 0
	local hay = fm and (fm:GetAttribute("Hay") or 0) or 0
	local count = 0
	local income, satSum = 0, 0
	-- доход идёт первым SheepMax овцам — по порядку, в каком они зашли
	local list = {}
	for s in pairs(seen) do table.insert(list, s) end
	table.sort(list, function(a, b) return (farm.sheep[a] or math.huge) < (farm.sheep[b] or math.huge) end)
	local waterPct = water / C.TROUGH_MAX * 100
	for _, s in ipairs(list) do
		count += 1
		if not farm.sheep[s] then
			farm.joinN = (farm.joinN or 0) + 1
			farm.sheep[s] = farm.joinN
			CollectionService:AddTag(s, "FarmSheep")
			s:SetAttribute("FarmHut", farm.id)
			if s:GetAttribute("Satiety") == nil then s:SetAttribute("Satiety", 70) end
			if s:GetAttribute("Level") == nil then s:SetAttribute("Level", 1) end
		end
		if s:GetAttribute("Hydration") == nil then s:SetAttribute("Hydration", 70) end
		local sat = s:GetAttribute("Satiety") or 70
		sat -= C.SATIETY_DRAIN * dh
		if hay > 0 and sat < C.EAT_UNTIL then
			sat += C.EAT_GAIN * dh
			hay = math.max(0, hay - C.EAT_HAY * dh)
		end
		-- пасётся на траве своего блока — наедается сама (клип Graze ставит её ИИ)
		if s:GetAttribute("Clip") == "Graze" and sat < C.EAT_UNTIL then
			local b = blockAt(farm, s.PrimaryPart.Position)
			local g = b and C.GRAZE_GAIN[b:GetAttribute("Soil")]
			if g then sat += g * dh end
		end
		sat = math.clamp(sat, 0, 100)
		s:SetAttribute("Satiety", math.floor(sat * 10 + 0.5) / 10)
		local hyd = math.clamp((s:GetAttribute("Hydration") or 70) - C.HYDRATION_DRAIN * dh, 0, 100)
		s:SetAttribute("Hydration", math.floor(hyd * 10 + 0.5) / 10)
		local inc = count <= sheepMax and C.sheepIncome(s:GetAttribute("Level"), sat, hyd) or 0
		setAttr(s, "IncomePerHour", math.floor(inc + 0.5))
		income += inc
		satSum += sat
	end
	if tm then
		-- на сколько хватит: овца за игровой час выпивает DRINK_WATER * DRAIN/GAIN,
		-- в реальную минуту — умножить на скорость часов
		local perHour = C.DRINK_WATER * C.HYDRATION_DRAIN / C.DRINK_GAIN
		local hoursPerMin = (farm.clockRate or (1 / 31.7)) * 60
		setAttr(tm, "DrainPerMinute", math.floor(perHour * hoursPerMin * count * 10 + 0.5) / 10)
	end
	if fm then fm:SetAttribute("Hay", math.floor(hay * 100 + 0.5) / 100) end

	-- бонус выжившего на работе (+50% прибыли фермы и т.п.)
	income = income * (1 + (hut:GetAttribute("IncomeBonus") or 0))
	-- уровень домика (BuildingLevels, табличка улучшения): ×1 / ×1,5 / ×2 / ×3
	do
		local BL = require(game:GetService("ReplicatedStorage"):WaitForChild("BuildingLevels"))
		income = income * (BL.Mults[hut:GetAttribute("Level") or 0] or 1)
	end
	local stored = (hut:GetAttribute("StoredCoins") or 0) + income * dh
	hut:SetAttribute("StoredCoins", stored)

	-- зарплата — на границе игрового часа
	local worker = farm.worker
	--[[ ⚠️ ЗАРПЛАТА — ТОЛЬКО ПОКА НА ФЕРМЕ ЕСТЬ ОВЦЫ. Без овец ферма не
	     зарабатывает ни монеты, и уже через игровой час фермер уходил в долг и
	     бастовал — новый дом без овец всегда стоял с бастующим фермером. ]]
	if worker and farm.payHour ~= math.floor(Lighting.ClockTime) then
		if farm.payHour ~= nil and count > 0 then
			local debt = worker:GetAttribute("Debt") or 0
			local want = farmWage(farm) + debt
			if stored >= want then
				stored -= want
				debt = 0
			else
				debt = want - math.max(0, stored)
				stored = 0
			end
			hut:SetAttribute("StoredCoins", stored)
			worker:SetAttribute("Debt", math.ceil(debt))
			hut:SetAttribute("WorkerDebt", math.ceil(debt))
		end
		farm.payHour = math.floor(Lighting.ClockTime)
	end
	-- долг гасится из хранилища, как только там появились деньги
	if worker and (worker:GetAttribute("Debt") or 0) > 0 and stored >= worker:GetAttribute("Debt") then
		stored -= worker:GetAttribute("Debt")
		hut:SetAttribute("StoredCoins", stored)
		worker:SetAttribute("Debt", 0)
		hut:SetAttribute("WorkerDebt", 0)
	end
	--[[ ЗАРПЛАТА С БАЛАНСА ИГРОКА, ЕСЛИ ФЕРМЕ НЕ ХВАТИЛО. Сначала платит
	     хранилище фермы, остаток — баланс капитана плота (нет его в игре —
	     первого игрока на сервере). Забастовка — только если не хватило и там. ]]
	local debtNow = worker and (worker:GetAttribute("Debt") or 0) or 0
	if debtNow > 0 and typeof(_G.SpendPirate) == "function" then
		local payer
		for _, p in ipairs(Players:GetPlayers()) do
			if typeof(_G.IsRaftOwner) == "function" and _G.IsRaftOwner(p) then payer = p break end
		end
		payer = payer or Players:GetPlayers()[1]
		if payer and _G.SpendPirate(payer, debtNow) then
			worker:SetAttribute("Debt", 0)
			hut:SetAttribute("WorkerDebt", 0)
			print(("%s зарплата фермеру %d — с баланса %s (в хранилище фермы не хватило)"):format(LOG, debtNow, payer.Name))
		end
	end
	-- когда следующая выплата (реальное время): по скорости часов
	if worker and farm.clockRate and farm.clockRate > 0 then
		local left = (math.floor(Lighting.ClockTime) + 1 - Lighting.ClockTime) / farm.clockRate
		setAttr(worker, "NextPayAt", math.floor(now() + left))
	end
	if farm.talkPrompt then
		local debt = worker and worker:GetAttribute("Debt") or 0
		farm.talkPrompt.ActionText = debt > 0 and ("Выплатить долг (%d)"):format(debt) or "Поговорить"
	end

	-- для таблички (раздел 3 хендоффа)
	setAttr(hut, "Level", hut:GetAttribute("Level") or 1)
	setAttr(hut, "IncomePerHour", math.floor(income + 0.5))
	-- на табличке — ставка всегда (сама выплата идёт только при овцах, см. выше)
	setAttr(hut, "WagesPerHour", worker and farmWage(farm) or 0)
	setAttr(hut, "SheepCount", count)
	setAttr(hut, "SheepMax", sheepMax)
	setAttr(hut, "WorkerCount", worker and 1 or 0)
	setAttr(hut, "WorkerMax", C.WORKER_MAX)
	setAttr(hut, "AvgSatiety", count > 0 and math.floor(satSum / count + 0.5) or 0)
	setAttr(hut, "WaterPercent", math.floor(waterPct + 0.5))

	setAttr(hut, "HasTrough", tm ~= nil)
	setAttr(hut, "HasFeeder", fm ~= nil)
end

-- ═══════════ жизнь дома ═══════════

local function destroyFarm(hut)
	local farm = farms[hut]
	if not farm then return end
	farms[hut] = nil
	farm.dead = true
	for s in pairs(farm.sheep) do
		if s.Parent then
			CollectionService:RemoveTag(s, "FarmSheep")
			s:SetAttribute("IncomePerHour", nil)
			s:SetAttribute("FarmHut", nil)
		end
	end
	for _, p in ipairs(farm.hutPrompts) do p:Destroy() end
	if farm.worker then farm.worker:Destroy() end
	if farm.folder then farm.folder:Destroy() end
	print(("%s ферма %s убрана"):format(LOG, farm.id))
end

local function adoptHut(hut)
	if farms[hut] or hut:GetAttribute("PlacementGhost") then return end
	local raft = raftOf()
	if not (raft and hut.Parent == raft) then return end
	local id = hut:GetAttribute("FarmId")
	if not id then
		id = HttpService:GenerateGUID(false):sub(1, 8)
		hut:SetAttribute("FarmId", id)
	end
	for attr, v in pairs({ StoredCoins = 0, StoreHay = 30, StoreWater = 30, Level = 1, WorkerDebt = 0 }) do
		if hut:GetAttribute(attr) == nil then hut:SetAttribute(attr, v) end
	end
	CollectionService:AddTag(hut, "Farm")
	local farm = { hut = hut, id = id, primary = raft.PrimaryPart, sheep = {}, blocks = {}, hutPrompts = {}, footOff = 3 }
	farms[hut] = farm
	farm.blocks = clusterOf(hut, raft)
	refreshGroundFilter()
	buildProps(farm)
	placeSign(farm)
	findBins(farm, raft)
	spawnWorker(farm)
	hut.AncestryChanged:Connect(function()
		if not hut:IsDescendantOf(workspace) then destroyFarm(hut) end
	end)
	print(("%s ферма %s: блоков %d, фермер %s"):format(LOG, id, #farm.blocks, farm.worker and "есть" or "НЕТ"))
end

local function onRaftChild(inst)
	if inst:IsA("Model") and inst.Name == C.HUT then
		-- дать установке приварить дом и расставить блоки
		task.delay(0.8, function()
			if inst:IsDescendantOf(workspace) then adoptHut(inst) end
		end)
	end
end

local watchedRaft
local function watchRaft()
	local raft = raftOf()
	if not raft or raft == watchedRaft then return end
	watchedRaft = raft
	for _, c in ipairs(raft:GetChildren()) do onRaftChild(c) end
	raft.ChildAdded:Connect(onRaftChild)
end

--[[ API ДЛЯ ВЫЖИВШИХ (SurvivorService):
     _G.RaftFarmList() — фермы на плоту { hut, id, worker }
     _G.RaftFarmRespawnWorker(hut) — сменить работника по атрибутам дома: ферму
       пересобираем целиком (старый цикл фермера гаснет по farm.dead — он не
       сможет двигать новую модель), всё её состояние живёт атрибутами на доме. ]]
_G.RaftFarmList = function()
	local out = {}
	for hut, farm in pairs(farms) do
		if hut.Parent then table.insert(out, { hut = hut, id = farm.id, worker = farm.worker }) end
	end
	return out
end
_G.RaftFarmRespawnWorker = function(hut)
	if not (typeof(hut) == "Instance" and farms[hut]) then return false end
	destroyFarm(hut)
	adoptHut(hut)
	return farms[hut] ~= nil
end

-- «СОБРАТЬ» на табличке
collectEvent.OnServerEvent:Connect(function(player, hut)
	local farm = typeof(hut) == "Instance" and farms[hut]
	if not farm then return end
	if typeof(_G.IsRaftOwner) == "function" and not _G.IsRaftOwner(player) then
		-- гость плота тоже может собрать, если капитана нет в игре
		local owner = false
		for _, p in ipairs(Players:GetPlayers()) do
			if _G.IsRaftOwner(p) then owner = true break end
		end
		if owner then notify(player, "warn", "Не твоя ферма", "Собрать монеты может капитан плота") return end
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - farm.sign.Position).Magnitude > C.COLLECT_DIST then
		notify(player, "warn", "Далеко", "Подойди к табличке фермы")
		return
	end
	local coins = math.floor(farm.hut:GetAttribute("StoredCoins") or 0)
	if coins <= 0 then notify(player, "warn", "Пусто", "Ферма ещё ничего не накопила") return end
	farm.hut:SetAttribute("StoredCoins", (farm.hut:GetAttribute("StoredCoins") or 0) - coins)
	if typeof(_G.AddPirate) == "function" then _G.AddPirate(player, coins) end
	notify(player, "success", "Доход фермы", ("+%d монет"):format(coins))
	print(("%s %s собрал %d монет с фермы %s"):format(LOG, player.Name, coins, farm.id))
end)

-- ═══════════ овца пьёт из корыта (ИИ овцы: NetCapture/Server) ═══════════

local function farmOfSheep(model)
	for _, farm in pairs(farms) do
		if farm.sheep[model] then return farm end
	end
	return nil
end

--[[ Куда идти пить: точка у длинного борта корыта (со стороны овцы, внутри
     загона) и точка, куда смотреть. nil — пить не нужно или нечего. ]]
_G.SheepWantsWater = function(model)
	local farm = farmOfSheep(model)
	if not farm or (model:GetAttribute("Hydration") or 100) >= C.SEEK_WATER_BELOW then return nil end
	local tm = farm.troughModel
	if not (tm and tm.Parent) or (tm:GetAttribute("Water") or 0) < 1 then return nil end
	local root = model.PrimaryPart
	if not root then return nil end
	local body = propPart(tm)
	if not body then return nil end
	local cf, size = body.CFrame, body.Size
	-- длинная сторона корыта — вдоль неё и встаём, поперёк — отступ от борта
	local across = size.X >= size.Z and cf.LookVector or cf.RightVector
	local half = (size.X >= size.Z and size.Z or size.X) * 0.5
	across = Vector3.new(across.X, 0, across.Z).Unit
	local best
	for _, sgn in ipairs({ 1, -1 }) do
		local p = cf.Position + across * sgn * (half + 1.7)
		if inZone(farm, p) then
			local d = (p - root.Position).Magnitude
			if not best or d < best.d then best = { p = p, d = d } end
		end
	end
	if not best then return nil end
	return best.p, cf.Position
end

-- попила: овце +напоенность, в корыте −вода
_G.SheepDrank = function(model)
	local farm = farmOfSheep(model)
	local tm = farm and farm.troughModel
	if not (tm and tm.Parent) then return end
	local have = tm:GetAttribute("Water") or 0
	local take = math.min(have, C.DRINK_WATER)
	if take <= 0 then return end
	tm:SetAttribute("Water", math.floor((have - take) * 100 + 0.5) / 100)
	local gain = C.DRINK_GAIN * take / C.DRINK_WATER
	model:SetAttribute("Hydration", math.min(100, (model:GetAttribute("Hydration") or 0) + gain))
end

--[[ НАЛИТЬ ВОДУ ИЗ КРУЖКИ (ПКМ по корыту, на телефоне — тап). Клиент шлёт
     только корыто; всё остальное проверяем здесь: кружка в руках и с пресной
     водой, корыто на плоту и рядом. Выливаем все заряды, сколько влезет. ]]
fillEvent.OnServerEvent:Connect(function(player, trough)
	if typeof(trough) ~= "Instance" or not C.TROUGH_NAMES[trough.Name] then return end
	local raft = raftOf()
	if not (raft and trough:IsDescendantOf(raft)) then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (hrp and tool) then return end
	if (hrp.Position - propPos(trough)).Magnitude > 16 then return end
	local charges = tonumber(tool:GetAttribute("CupCharges")) or 0
	local state = tool:GetAttribute("CupState")
	if state == "salty" then
		notify(player, "warn", "Солёная вода", "Овцы морскую воду не пьют — очисти её в очистителе")
		return
	end
	if charges <= 0 or state ~= "fresh" then
		notify(player, "warn", "Нужна вода", "Возьми в руки кружку или бутылку с пресной водой")
		return
	end
	local max = trough:GetAttribute("WaterMax") or C.TROUGH_MAX
	local have = trough:GetAttribute("Water") or 0
	if have >= max then notify(player, "warn", "Корыто полное", "Больше не влезет") return end
	local used = math.min(charges, math.ceil((max - have) / C.WATER_PER_CUP))
	trough:SetAttribute("Water", math.min(max, have + used * C.WATER_PER_CUP))
	charges -= used
	tool:SetAttribute("CupCharges", charges)
	if charges <= 0 and typeof(_G.SetCupState) == "function" then pcall(_G.SetCupState, tool, "empty") end
	print(("%s %s налил в корыто %d л"):format(LOG, player.Name, used * C.WATER_PER_CUP))
end)

-- ═══════════ главный цикл ═══════════

task.spawn(function()
	local lastClock, lastT = Lighting.ClockTime, os.clock()
	local rate
	while true do
		local dt = task.wait(0.5)
		watchRaft()
		local clock = Lighting.ClockTime
		local dh = clock - lastClock
		if dh < -12 then dh += 24 end
		if dh < 0 or dh > 2 then dh = 0 end
		local realDt = os.clock() - lastT
		if realDt > 0 and dh > 0 then rate = dh / realDt end
		lastClock, lastT = clock, os.clock()
		refreshGroundFilter()
		for hut, farm in pairs(farms) do
			if hut.Parent then
				farm.clockRate = rate
				local ok, err = pcall(tickFarm, farm, dt, dh)
				if not ok then warn(LOG .. " " .. tostring(err)) end
			end
		end
	end
end)

print(LOG .. " готово: дом фермера рядом с фермой → фермер, корыто, кормушка, табличка, доход с овец")
