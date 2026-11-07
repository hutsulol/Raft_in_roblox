-- EngineerSystem.server.lua (переписан С НУЛЯ)
-- МЕХАНИК (Workspace.Engeneer). Архитектурный принцип: у корня НПС есть РОВНО ОДИН
-- путь движения — маленький шаг за кадр в цикле ходьбы (не больше WALK_SPEED*dt).
-- В коде НЕТ ни одной операции «поставить корень в вычисленную точку» — телепорт
-- невозможен по построению. Анимации только позируют тело, код их не компенсирует.
--
-- Состояния: СПИТ (AFK-луп) → ПРОБУЖДЕНИЕ (толчок игрока → кроссфейд AFK→Alive →
-- Alive доигрывает → плавный фейд в стойку) → ДЕЖУРИТ: стоит у ремонтного стола
-- (парт Place в модели repair station); плоту не хватает ≥10 хп (или любая нехватка
-- дольше минуты) → идёт в случайную точку палубы → Start_remont → циклы remont
-- (0.6 с = +1 хп) до полного хп → end_remont → обратно на пост.
--
-- Транспорт: корень постоянно приварен к плоту (Weld, движение = смена C0) — как у
-- дайвера: жёстко едет с плотом, физику плота не трогает. Риг без коллизий, невесом.
--
-- Требования к клипам (в модели, Animation-объекты):
--   AFK   — лежит/спит НА МЕСТЕ, зациклен;
--   Alive — встаёт НА МЕСТЕ, БЕЗ перемещения персонажа, конец = обычная стойка;
--   WalkAnim — цикл ходьбы; player_tolkaet/Push — толчок (играется У ИГРОКА через remote).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ── настройки ──
local NPC_NAMES     = { "Engeneer", "Engeener", "Engineer" }
local PUSH_ANIM     = "rbxassetid://107525576000182" -- запасной id толчка (лучше Animation в модели)
local WALK_SPEED    = 9     -- студов/с по палубе
local Y_SPEED       = 6     -- максимальная ВЕРТИКАЛЬНАЯ скорость подстройки к палубе (плавно, без снапов)
local WANDER_RADIUS = 8     -- цели прогулки — вокруг ТЕКУЩЕЙ точки (не к центру плота)
local ARRIVE_DIST   = 1
local PAUSE_MIN, PAUSE_MAX = 1.2, 3.2
local PUSH_DELAY    = 0.35  -- толчок «долетает» до НПС
local PROMPT_TEXT, PROMPT_OBJ = "Разбудить", "Механик"
local DEBUG_POS     = false -- печать позиции корня на этапах пробуждения (охота на баг закрыта)

-- ── remote: толчок играется У ИГРОКА локально (EngineerPush.client) ──
local pushRemote = ReplicatedStorage:FindFirstChild("EngineerPush")
if not pushRemote then
	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = "EngineerPush"
	pushRemote.Parent = ReplicatedStorage
end

-- ── плот ──
local function raft() return workspace:FindFirstChild("Raft") end
local function rpp() local r = raft(); return r and r.PrimaryPart end

-- ── риг ──
local function findRig(model)
	if model:FindFirstChild("Torso") or model:FindFirstChild("Head") then return model end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChild("Torso") or d:FindFirstChild("Head")) then return d end
	end
	return model
end

local function ensureHumanoid(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	local rig = findRig(model)
	if not hum then
		local torso = rig:FindFirstChild("Torso") or rig:FindFirstChildWhichIsA("BasePart")
		if not torso then return nil, nil end
		hum = Instance.new("Humanoid")
		hum.Parent = rig
	end
	hum.BreakJointsOnDeath = false
	local hrp = rig:FindFirstChild("HumanoidRootPart") or hum.RootPart
	return hum, hrp
end

-- ── транспорт: постоянный вельд к плоту, движение = смена C0 ──
local function ensureRaftWeld(hrp)
	local w = hrp:FindFirstChild("_EngineerRaftWeld")
	if w and w:IsA("Weld") and w.Part0 and w.Part0.Parent then return w end
	if w then w:Destroy() end
	local base = rpp()
	if not base then return nil end
	hrp.Anchored = false
	w = Instance.new("Weld")
	w.Name = "_EngineerRaftWeld"
	w.Part0 = base
	w.Part1 = hrp
	w.C1 = CFrame.new()
	w.C0 = base.CFrame:Inverse() * hrp.CFrame -- держит ТЕКУЩУЮ мировую позу
	w.Parent = hrp
	pcall(function() base:SetNetworkOwner(nil) end)
	return w
end

-- ЕДИНСТВЕННЫЙ проводник движения. Используется ТОЛЬКО циклом ходьбы,
-- шаг ограничен маленькой дельтой за кадр.
local function setRootCF(hrp, cf)
	local w = ensureRaftWeld(hrp)
	if w and w.Part0 then
		w.C0 = w.Part0.CFrame:Inverse() * cf
	end
end

local function playT(t, f) if t then pcall(function() t:Play(f or 0.2) end) end end
local function stopT(t, f) if t then pcall(function() t:Stop(f or 0.2) end) end end

-- ── подготовка рига: без коллизий, невесом, свои скрипты выключены ──
local function setupNpc(npc)
	local hum, hrp = ensureHumanoid(npc)
	if not hum or not hrp then return nil end
	hrp = hum.RootPart or hrp
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			pcall(function() d.EnableFluidForces = false end)
			d.Anchored = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
	pcall(function() npc.PrimaryPart = hrp end)
	hum.EvaluateStateMachine = false
	hum.AutoRotate = false
	hum.PlatformStand = true
	npc:SetAttribute("WaterImmune", true)
	npc:SetAttribute("RaftFriendly", true)
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	return hum, hrp
end

-- анимация по имени из детей модели
local function loadNamed(hum, model, names, looped)
	local animator = hum:FindFirstChildOfClass("Animator")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") and d.AnimationId ~= "" then
			local ln = d.Name:lower()
			for _, nm in ipairs(names) do
				if ln == nm:lower() then
					local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
					if ok and tr then
						tr.Priority = Enum.AnimationPriority.Action
						tr.Looped = looped == true
						return tr, d
					end
				end
			end
		end
	end
	return nil, nil
end

-- ── главный поток ──
task.spawn(function()
	-- найти НПС
	local npc
	for _ = 1, 120 do
		for _, nm in ipairs(NPC_NAMES) do
			local m = workspace:FindFirstChild(nm, true)
			if m and m:IsA("Model") then npc = m break end
		end
		if npc then break end
		task.wait(0.5)
	end
	if not npc then
		warn("[EngineerSystem] модель механика не найдена")
		return
	end
	while not rpp() do task.wait(0.5) end

	local hum, hrp = setupNpc(npc)
	if not hum then
		warn("[EngineerSystem] у механика нет рига/Humanoid")
		return
	end
	ensureRaftWeld(hrp) -- закрепить на авторском месте: лежит, едет с плотом

	-- геометрия: рост из рига, уровень палубы — от центра плота
	local rig = findRig(npc)
	local leg = rig:FindFirstChild("Left Leg") or rig:FindFirstChild("LeftUpperLeg")
	local hip = hrp.Size.Y / 2 + (leg and leg.Size.Y or 2)
	local deckOffset = 0
	do
		local b = rpp()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { raft() }
		local res = workspace:Raycast(b.Position + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), params)
		if res then deckOffset = res.Position.Y - b.Position.Y end
	end
	local function deckYAt(x, z)
		local r, b = raft(), rpp()
		if not (r and b) then return nil end
		local refY = b.Position.Y + deckOffset
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { r }
		local res = workspace:Raycast(Vector3.new(x, refY + 8, z), Vector3.new(0, -16, 0), params)
		if res and math.abs(res.Position.Y - refY) <= 3 then return res.Position.Y end
		return nil
	end

	-- анимации
	local afkTrack   = loadNamed(hum, npc, { "AFK" }, true)
	local aliveTrack = loadNamed(hum, npc, { "Alive" }, false)
	local walkTrack  = loadNamed(hum, npc, { "WalkAnim", "Walk" }, true)
	local _, pushAnimObj = loadNamed(hum, npc, { "player_tolkaet", "Push", "PushAnim" }, false)
	-- ремонт: сел за работу → цикл ударов (0.6 с = +1 хп) → встал
	local startRemontTrack = loadNamed(hum, npc, { "Start_remont", "StartRemont" }, false)
	local remontTrack      = loadNamed(hum, npc, { "remont", "Remont" }, true)
	local endRemontTrack   = loadNamed(hum, npc, { "end_remont", "EndRemont" }, false)
	print(("[EngineerSystem] tracks: AFK=%s Alive=%s Walk=%s Push=%s Start_remont=%s remont=%s end_remont=%s"):format(
		afkTrack and "OK" or "MISSING",
		aliveTrack and "OK" or "MISSING",
		walkTrack and "OK" or "MISSING",
		pushAnimObj and pushAnimObj.AnimationId or ("константа " .. PUSH_ANIM),
		startRemontTrack and "OK" or "MISSING",
		remontTrack and "OK" or "MISSING",
		endRemontTrack and "OK" or "MISSING"))

	-- прогрев НЕзацикленных клипов ЗАРАНЕЕ и с почти нулевым весом (невидимо):
	-- длина ассета подгружается ещё на старте, и при пробуждении/ремонте не будет
	-- видимой «репетиции» клипа (раньше Alive грелся на Core-приоритете в момент
	-- пробуждения — суставы, не занятые AFK, показывали его насквозь, и казалось,
	-- что Alive играет дважды и налазит на AFK)
	task.spawn(function()
		for _, tr in ipairs({ aliveTrack, startRemontTrack, endRemontTrack }) do
			if tr and tr.Length <= 0.05 then
				pcall(function() tr:Play(0, 0.001, 1) end)
				local t0 = os.clock()
				while os.clock() - t0 < 8 and tr.Length <= 0.05 do task.wait(0.1) end
				pcall(function() tr:Stop(0) end)
			end
		end
	end)

	local function logPos(tag)
		if DEBUG_POS then
			-- координаты В СИСТЕМЕ ПЛОТА: движение самого плота (он плывёт ~8 студов/с)
			-- из чисел исключено — если эти числа не меняются, позиция стабильна
			local b = rpp()
			local p = b and b.CFrame:PointToObjectSpace(hrp.Position) or hrp.Position
			print(("[EngineerSystem] %s: root-local=(%.2f, %.2f, %.2f)"):format(tag, p.X, p.Y, p.Z))
		end
	end

	-- ── СПИТ: AFK-луп (переигрываем поздним игрокам — они не видят уже идущий цикл) ──
	local state = "asleep"
	local function playAfk()
		if state ~= "asleep" then return end
		stopT(afkTrack, 0)
		playT(afkTrack, 0.1)
	end
	playAfk()
	task.delay(1.2, playAfk)
	Players.PlayerAdded:Connect(function() task.delay(1.2, playAfk) end)

	-- ── ХОДЬБА: единственный проводник движения — маленький шаг за кадр к цели ──
	-- getWorld() возвращает ТЕКУЩУЮ мировую точку цели (пересчёт каждый кадр — цель
	-- едет вместе с плотом). ВАЖНО: PrimaryPart плота ПОВЁРНУТ (локальная ось Y смотрит
	-- вбок) — компоненты его локали никогда не обнуляем (JumpProbe ловил телепорт 11.76 ст).
	-- Возвращает true = дошёл, false = палуба кончилась / плот пропал.
	local function walkStepsTo(getWorld)
		local wt0 = getWorld()
		if not wt0 then return false end
		if Vector3.new(wt0.X - hrp.Position.X, 0, wt0.Z - hrp.Position.Z).Magnitude <= ARRIVE_DIST then
			return true -- уже на месте, ходьбу не дёргаем
		end
		playT(walkTrack)
		local ok = false
		while npc.Parent do
			local dt = RunService.Heartbeat:Wait()
			local wt = getWorld()
			if not wt then break end
			local dx, dz = wt.X - hrp.Position.X, wt.Z - hrp.Position.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= ARRIVE_DIST then ok = true break end
			-- ШАГ: не больше WALK_SPEED*dt по горизонтали и Y_SPEED*dt по вертикали
			local step = math.min(WALK_SPEED * dt, dist)
			local nx = hrp.Position.X + dx / dist * step
			local nz = hrp.Position.Z + dz / dist * step
			local dy = deckYAt(nx, nz)
			if not dy then break end -- край палубы
			local wantY = dy + hip
			local curY = hrp.Position.Y
			local ny = curY + math.clamp(wantY - curY, -Y_SPEED * dt, Y_SPEED * dt)
			local dirW = Vector3.new(dx, 0, dz)
			local pos = Vector3.new(nx, ny, nz)
			-- поворот к цели ПЛАВНЫЙ (мгновенный lookAt — рывок)
			local rot = hrp.CFrame.Rotation
			if dirW.Magnitude > 0.01 then
				local want = CFrame.lookAt(Vector3.zero, dirW.Unit)
				rot = rot:Lerp(want, math.min(1, 8 * dt))
			end
			setRootCF(hrp, CFrame.new(pos) * rot)
		end
		stopT(walkTrack)
		return ok
	end

	-- цель, приклеенная к плоту: мировая точка → ПОЛНАЯ 3D-локаль → мировая каждый кадр
	local function raftAnchoredTarget(worldPos)
		local b = rpp()
		if not b then return nil end
		local tLocal = b.CFrame:PointToObjectSpace(worldPos)
		return function()
			local bb = rpp()
			return bb and bb.CFrame:PointToWorldSpace(tLocal) or nil
		end
	end

	-- случайная точка на палубе: сперва по всему плоту (bounding box), потом вокруг себя
	local function randomDeckPoint()
		local r = raft()
		if r then
			local cf, size = r:GetBoundingBox()
			for _ = 1, 20 do
				local wx = cf.Position.X + (math.random() - 0.5) * size.X
				local wz = cf.Position.Z + (math.random() - 0.5) * size.Z
				local dy = deckYAt(wx, wz)
				if dy then return Vector3.new(wx, dy + hip, wz) end
			end
		end
		for _ = 1, 12 do
			local a = math.random() * math.pi * 2
			local d = 3 + math.random() * WANDER_RADIUS
			local wx, wz = hrp.Position.X + math.cos(a) * d, hrp.Position.Z + math.sin(a) * d
			local dy = deckYAt(wx, wz)
			if dy then return Vector3.new(wx, dy + hip, wz) end
		end
		return nil
	end

	-- плавно развернуться в горизонтальном направлении (без снапов)
	local function faceDir(dirW)
		dirW = Vector3.new(dirW.X, 0, dirW.Z)
		if dirW.Magnitude < 0.05 then return end
		local want = CFrame.lookAt(Vector3.zero, dirW.Unit)
		local t0 = os.clock()
		while npc.Parent and os.clock() - t0 < 0.6 do
			local dt = RunService.Heartbeat:Wait()
			local rot = hrp.CFrame.Rotation:Lerp(want, math.min(1, 10 * dt))
			setRootCF(hrp, CFrame.new(hrp.Position) * rot)
		end
	end

	-- проиграть НЕзацикленный трек целиком (конец — по TimePosition самого трека,
	-- никаких AdjustSpeed: он не реплицируется клиентам)
	local function playFull(track, fade)
		if not track then return end
		pcall(function()
			track.TimePosition = 0
			track:Play(fade or 0.15)
		end)
		local total = track.Length
		local t0 = os.clock()
		while npc.Parent do
			if track.Length > total then total = track.Length end
			if total > 0.05 and (not track.IsPlaying or track.TimePosition >= total - 0.05) then break end
			if os.clock() - t0 > math.max(total, 1) + 2 then break end
			RunService.Heartbeat:Wait()
		end
	end

	-- ── РЕМОНТ ПЛОТА ──
	local REPAIR_DEFICIT_NOW = 10  -- не хватает ≥10 хп → идёт чинить сразу
	local REPAIR_SMALL_WAIT  = 60  -- нехватка меньше 10 хп, но дольше минуты → тоже идёт
	local REPAIR_CYCLE       = 0.6 -- один цикл remont = 0.6 с = +1 хп плоту
	local REPAIR_MIN_FROM_ME      = 6 -- чинит не ближе этого к месту, где стоит сейчас
	local REPAIR_MIN_FROM_STATION = 7 -- и не вплотную к ремонтной станции

	local function raftDeficit()
		local r = raft()
		if not r then return 0 end
		return math.max(0, (r:GetAttribute("MaxHP") or 0) - (r:GetAttribute("HP") or 0))
	end

	local function healRaft(n)
		local r = raft()
		if not r then return end
		local hp = r:GetAttribute("HP") or 0
		local mx = r:GetAttribute("MaxHP") or 0
		r:SetAttribute("HP", math.min(hp + n, mx))
	end

	-- прозрачный парт "Place" перед ремонтным столом (пост механика)
	local function stationPlace()
		local r = raft()
		if not r then return nil end
		local st = r:FindFirstChild("repair station", true)
		local p = st and st:FindFirstChild("Place", true)
		if p and p:IsA("BasePart") then return p end
		p = r:FindFirstChild("Place", true) -- запасной путь: любой Place на плоту
		return (p and p:IsA("BasePart")) and p or nil
	end

	-- точка ремонта: не рядом с собой, не у ремонтной станции, с предпочтением подальше
	local function repairSpot()
		local r = raft()
		local place = stationPlace()
		local best, bestScore
		if r then
			local cf, size = r:GetBoundingBox()
			for _ = 1, 30 do
				local wx = cf.Position.X + (math.random() - 0.5) * size.X
				local wz = cf.Position.Z + (math.random() - 0.5) * size.Z
				local dy = deckYAt(wx, wz)
				if dy then
					local p = Vector3.new(wx, dy + hip, wz)
					local dMe = Vector3.new(p.X - hrp.Position.X, 0, p.Z - hrp.Position.Z).Magnitude
					local dSt = place
						and Vector3.new(p.X - place.Position.X, 0, p.Z - place.Position.Z).Magnitude
						or math.huge
					if dMe >= REPAIR_MIN_FROM_ME and dSt >= REPAIR_MIN_FROM_STATION then
						local score = dMe + math.random() * 4 -- дальше = лучше, чуть случайности
						if not bestScore or score > bestScore then best, bestScore = p, score end
					end
				end
			end
		end
		return best or randomDeckPoint() -- крохотный плот: ограничения смягчаются
	end

	-- ── ремонт ПОСТРОЕК, побитых пиратами ──
	-- SwimmingPirate при ударах вешает на постройку атрибут ObstacleHP (макс 120) и красный
	-- бар ObstacleHPBar; на нуле постройка разрушается (breakBuilding) — такую уже не вернуть.
	-- Механик чинит ПОВРЕЖДЁННЫЕ, но стоящие: восстанавливает ObstacleHP до полного и убирает бар.
	local OBSTACLE_HP_MAX         = 120 -- = SwimmingPirate.OBSTACLE_HP
	local BUILDING_HEAL_PER_CYCLE = 4   -- +HP за цикл remont (0.6 c): с нуля до полного ~18 c

	local function damagedBuilding()
		local r = raft()
		if not r then return nil end
		for _, child in ipairs(r:GetChildren()) do
			local hp = child:GetAttribute("ObstacleHP")
			if hp and hp < OBSTACLE_HP_MAX and not child:GetAttribute("Broken") then
				local part = child:IsA("BasePart") and child
					or (child:IsA("Model") and (child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")))
				if part then return child, part end
			end
		end
		return nil
	end

	-- обновить/убрать красный бар пиратов (та же структура, что в showObstacleHP)
	local function setObstacleBar(root, hp, max)
		local bb = root:FindFirstChild("ObstacleHPBar")
		if not bb then return end
		if hp >= max then bb:Destroy() return end
		local bg = bb:FindFirstChildWhichIsA("Frame")
		local fl = bg and bg:FindFirstChild("Fill")
		if fl then fl.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1) end
	end

	-- ── ДЕЖУРСТВО: стоит у стола → плот ранен → чинит в случайной точке → обратно ──
	local function duty()
		state = "duty"
		logPos("duty start")
		task.spawn(function()
			local damagedSince = nil -- с какого момента плот не фулловый
			while npc.Parent do
				local deficit = raftDeficit()
				if deficit > 0 then
					damagedSince = damagedSince or os.clock()
				else
					damagedSince = nil
				end

				local needRepair = deficit >= REPAIR_DEFICIT_NOW
					or (deficit > 0 and damagedSince and os.clock() - damagedSince >= REPAIR_SMALL_WAIT)

				if needRepair then
					-- 1) идёт чинить подальше: не рядом с собой и не у станции
					local spot = repairSpot()
					local target = spot and raftAnchoredTarget(spot)
					if target then walkStepsTo(target) end
					-- 2) приступает: сел за работу
					playFull(startRemontTrack)
					playT(remontTrack, 0.1)
					-- 3) один цикл (0.6 с) = +1 хп; НЕ встаёт, пока плот не фулловый
					while npc.Parent and raftDeficit() > 0 do
						task.wait(REPAIR_CYCLE)
						healRaft(1)
					end
					stopT(remontTrack, 0.15)
					-- 4) закончил: встал
					playFull(endRemontTrack)
					damagedSince = nil
					-- 5) обратно к ремонтной станции, встать по направлению парта Place
					local place = stationPlace()
					if place then
						walkStepsTo(function() return place.Position end)
						faceDir(place.CFrame.LookVector)
					end
				elseif damagedBuilding() then
					-- ── пираты побили постройку → идёт к ней и чинит на месте ──
					local b, bpart = damagedBuilding()
					if b and bpart then
						-- насколько отступить: за габарит постройки (не лезть внутрь)
						local brad
						if b:IsA("Model") then
							local _, s = b:GetBoundingBox()
							brad = math.max(s.X, s.Z) * 0.5
						else
							brad = math.max(bpart.Size.X, bpart.Size.Z) * 0.5
						end
						local standOff = brad + 2
						-- точка РЯДОМ с постройкой со своей стороны; пересчёт каждый кадр — едет с плотом
						walkStepsTo(function()
							if not bpart.Parent then return nil end
							local p = bpart.Position
							local d = Vector3.new(hrp.Position.X - p.X, 0, hrp.Position.Z - p.Z)
							d = (d.Magnitude > 0.1) and d.Unit or Vector3.new(1, 0, 0)
							return p + d * standOff
						end)
						if bpart.Parent and not b:GetAttribute("Broken") then
							faceDir(bpart.Position - hrp.Position)
							playFull(startRemontTrack)
							playT(remontTrack, 0.1)
							-- цикл 0.6 c = +BUILDING_HEAL_PER_CYCLE HP, пока постройка не целая
							while npc.Parent and b.Parent and not b:GetAttribute("Broken") do
								local hp = b:GetAttribute("ObstacleHP")
								if not hp or hp >= OBSTACLE_HP_MAX then break end
								task.wait(REPAIR_CYCLE)
								hp = math.min((b:GetAttribute("ObstacleHP") or OBSTACLE_HP_MAX)
									+ BUILDING_HEAL_PER_CYCLE, OBSTACLE_HP_MAX)
								setObstacleBar(b, hp, OBSTACLE_HP_MAX)
								if hp >= OBSTACLE_HP_MAX then
									-- целая: атрибут снимаем (пираты снова начнут с максимума)
									b:SetAttribute("ObstacleHP", nil)
									break
								end
								b:SetAttribute("ObstacleHP", hp)
							end
							stopT(remontTrack, 0.15)
							playFull(endRemontTrack)
						end
					end
					-- обратно на пост не идём напрямую: следующий виток цикла сам решит —
					-- чинить следующую постройку/плот или вернуться к столу (ветка else)
				else
					-- плот фулловый: пост у ремонтного стола (если унесло — вернуться)
					local place = stationPlace()
					if place then
						local d = place.Position - hrp.Position
						if Vector3.new(d.X, 0, d.Z).Magnitude > ARRIVE_DIST + 1.5 then
							walkStepsTo(function() return place.Position end)
							faceDir(place.CFrame.LookVector)
						end
					end
					task.wait(0.5)
				end
			end
		end)
	end

	-- ── ПРОБУЖДЕНИЕ ──
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WakeEngineerPrompt"
	prompt.ActionText = PROMPT_TEXT
	prompt.ObjectText = PROMPT_OBJ
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = hrp

	prompt.Triggered:Connect(function(player)
		if state ~= "asleep" then return end
		state = "waking"
		prompt.Enabled = false
		logPos("wake: до толчка")

		-- толчок у игрока (локальный Play через remote — серверный игроку не реплицируется)
		pushRemote:FireClient(player, (pushAnimObj and pushAnimObj.AnimationId) or PUSH_ANIM)
		task.wait(PUSH_DELAY)

		-- ═══ СЛОЁНАЯ СХЕМА (по мотивам reviveStarter дайвера, без заморозки) ═══
		-- Стык AFK→Alive прикрыт слоями: AFK держит позу СНИЗУ, Alive играет НА ПРИОРИТЕТ
		-- ВЫШЕ и переопределяет её; затем AFK гасится ПОД полным весом Alive (см. ниже —
		-- почему её нельзя оставлять живой до конца: авто-стоп Alive на клиенте).
		if afkTrack then pcall(function() afkTrack.Priority = Enum.AnimationPriority.Action end) end
		if aliveTrack then pcall(function() aliveTrack.Priority = Enum.AnimationPriority.Action2 end) end

		-- аварийный прогрев, если длина всё ещё не подгрузилась: с ПОЧТИ НУЛЕВЫМ весом,
		-- полностью невидим (Core-прогрев просвечивал сквозь AFK на незанятых суставах —
		-- выглядело как «Alive играет дважды»)
		if aliveTrack and aliveTrack.Length <= 0.05 then
			pcall(function() aliveTrack:Play(0, 0.001, 1) end)
			local t0 = os.clock()
			while os.clock() - t0 < 6 and aliveTrack.Length <= 0.05 do
				RunService.Heartbeat:Wait()
			end
			pcall(function() aliveTrack:Stop(0) end)
			RunService.Heartbeat:Wait()
		end

		-- дождаться границы цикла AFK: Alive нарисована продолжением её последнего кадра
		if afkTrack and afkTrack.IsPlaying and afkTrack.Length > 0 then
			local rem = afkTrack.Length - afkTrack.TimePosition
			if rem > 0.05 then task.wait(rem - 0.02) end
		end

		local total = (aliveTrack and aliveTrack.Length > 0.05) and aliveTrack.Length or 0
		print(("[EngineerSystem] alive: len=%.2f"):format(total))

		if aliveTrack and total > 0.05 then
			-- Alive ПОВЕРХ живой AFK (blend 0.12) — AFK прикрывает только СТЫК старта
			pcall(function()
				aliveTrack.TimePosition = 0
				aliveTrack:AdjustSpeed(1)
				aliveTrack:Play(0.12)
			end)

			-- ═══ РАЗГАДКА «ТЕЛЕПОРТА» ═══
			-- AdjustSpeed НЕ РЕПЛИЦИРУЕТСЯ клиентам (скорость уезжает только в момент Play).
			-- Серверная «заморозка финального кадра» на клиенте НЕ СУЩЕСТВОВАЛА: клиентский
			-- Alive доигрывал и авто-стопался, снизу снова проступал зацикленный AFK — тело
			-- ЛОЖИЛОСЬ ОБРАТНО на лежанку. Финальный стоп AFK схлопывал лежачую позу в нейтраль
			-- на корне → «телепорт» на константную дистанцию (= смещение лежачей позы), который
			-- сервер не видел (у него заморозка держала → torso-delta=0.00). Лечение: никакой
			-- заморозки; используем ТОЛЬКО реплицируемые команды (Play/Stop):
			--   1) AFK гасим СРАЗУ после того, как Alive набрала полный вес (0.3с > бленд
			--      0.12) — Stop реплицируется, «лежание» больше НИГДЕ не всплывёт;
			--   2) Alive отпускаем мягким Stop(0.15) чуть РАНЬШЕ авто-стопа — одинаковый
			--      плавный фейд в нейтральную стойку и на сервере, и на клиенте
			--      (вместо жёсткого среза кадра при авто-стопе).
			-- ═══ ВИНОВНИК «2 СТУДОВ ВПЕРЁД» ═══
			-- В Alive НЕТ канала торса (удалён при борьбе с ранним багом) — разворот
			-- «лежит→стоит» делает НЕ анимация, а исчезновение лежачей позы AFK. Быстрый
			-- стоп AFK разворачивал корпус рывком: масса тела (голова+торс, ~2 студа
			-- выноса у лежащего) перелетала к вертикали — «телепорт». Центр торса при
			-- повороте вокруг сустава почти не движется — потому torso-delta и врала 0.00.
			-- Лечение: AFK гасится ОДНОВРЕМЕННО со стартом Alive, но с фейдом длиной во
			-- весь клип — корпус поднимается плавно, синхронно с ногами/головой из Alive.
			local afkFade = math.max(0.4, total - 0.05)
			if afkTrack then pcall(function() afkTrack:Stop(afkFade) end) end

			-- доигрываем почти до конца по TimePosition самого трека
			local t0 = os.clock()
			while npc.Parent do
				if aliveTrack.Length > total then total = aliveTrack.Length end
				if not aliveTrack.IsPlaying or aliveTrack.TimePosition >= total - 0.12 then break end
				if os.clock() - t0 > total + 1 then break end
				RunService.Heartbeat:Wait()
			end

			-- контроль: смещена ли ПОЗА от корня в финале (должно быть ~0; если нет —
			-- компенсируем корнем, чтобы нейтраль встала ровно туда, где было тело)
			local rig2 = findRig(npc)
			local torso = rig2:FindFirstChild("Torso") or rig2:FindFirstChild("UpperTorso") or hrp
			local delta = torso.Position - hrp.Position
			delta = Vector3.new(delta.X, 0, delta.Z)
			print(("[EngineerSystem] release: torso-delta=(%.2f, %.2f) |%.2f| студов")
				:format(delta.X, delta.Z, delta.Magnitude))
			if delta.Magnitude > 0.1 then
				local px, pz = hrp.Position.X + delta.X, hrp.Position.Z + delta.Z
				local dy = deckYAt(px, pz)
				setRootCF(hrp, CFrame.new(px, dy and (dy + hip) or hrp.Position.Y, pz) * hrp.CFrame.Rotation)
			end

			pcall(function() aliveTrack:Stop(0.15) end) -- мягко в нейтральную стойку (реплицируется)
			task.wait(0.25)
			logPos("wake: конец Alive")
		else
			-- Alive не загрузилась — мягкий подъём: медленно растворяем лежачую позу
			warn("[EngineerSystem] Alive не загрузилась — плавный подъём без анимации")
			if afkTrack then pcall(function() afkTrack:Stop(1.0) end) end
			task.wait(1.0)
		end
		task.wait(0.2)
		logPos("wake: треки погашены")

		prompt:Destroy()

		-- ПЕРВЫЙ ДИАЛОГ: механик поднялся — сразу заговаривает с тем, кто его растолкал.
		-- Топор выдаёт сервер диалога по своим данным (DialogueService),
		-- здесь только команда «начать». duty() запускается ПОСЛЕ: он уходит в свой
		-- цикл дежурства и вернул бы управление сюда неизвестно когда.
		-- ⚠️ ЖДЁМ DialogueService, А НЕ ПРОВЕРЯЕМ ОДИН РАЗ.
		-- Промпт «Разбудить» уже уничтожен, других вызовов MechanicIntro в проекте
		-- нет: не поднялся сервер диалогов к этой секунде — игрок остался и без
		-- топора, и разбудить второй раз уже нечем. Мусор сюда больше не входит:
		-- он выдаётся на аванпосте, по заданию «Огнемёт» (OutpostIsleStory).
		for _ = 1, 20 do
			if typeof(_G.StartDialogue) == "function" then break end
			task.wait(0.5)
		end
		if typeof(_G.StartDialogue) == "function" then
			local ok, err = pcall(_G.StartDialogue, player, "MechanicIntro")
			if not ok then warn("[EngineerSystem] диалог MechanicIntro: " .. tostring(err)) end
		else
			warn("[EngineerSystem] DialogueService не поднялся — топор не выдан")
		end

		-- ⚠️ ОТСЮДА ОТСЧИТЫВАЕТСЯ КВЕСТ ПРО ДАЙВЕРА.
		-- «Через два дня после оживления механика» — значит нужен день, когда он
		-- поднялся. Пишем его в Workspace: DiverQuestWatcher читает оттуда, а не
		-- лезет в этот скрипт.
		local dc = ReplicatedStorage:FindFirstChild("DayCount")
		if dc and not workspace:GetAttribute("EngineerWokeDay") then
			workspace:SetAttribute("EngineerWokeDay", dc.Value)
		end

		duty() -- дежурство: пост у ремонтного стола, ремонт при уроне плота
	end)

	--[[ ВОССТАНОВЛЕНИЕ ИЗ СЕЙВА: механик уже был разбужен в прошлой сессии.
	     Без толчка, без подъёма и без вступительного диалога (топор игрок уже
	     получил тогда): гасим сон, убираем подсказку «Разбудить», записываем день
	     пробуждения и отправляем на дежурство. Зовёт RaftSaveSystem. ]]
	_G.RestoreEngineerAwake = function(wokeDay)
		if state ~= "asleep" then return end
		state = "waking"
		if prompt and prompt.Parent then prompt:Destroy() end
		if afkTrack then pcall(function() afkTrack:Stop(0.5) end) end
		if type(wokeDay) == "number" and not workspace:GetAttribute("EngineerWokeDay") then
			workspace:SetAttribute("EngineerWokeDay", wokeDay)
		end
		print("[EngineerSystem] разбужен из сейва — сразу на дежурство")
		task.spawn(duty)
	end

	print("[EngineerSystem] механик готов (rewrite): спит, ждёт пробуждения")
end)
