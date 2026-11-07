--[[
	ЛОДОЧНИК С НАГРАДОЙ РЕЙДА — сервер.

	Сценарий: после зачистки острова (или по запросу _G.RequestRaidCourier) рядом с
	плотом появляется лодка, догоняет плывущий плот, причаливает к борту, лодочник
	поднимает ящик, переходит на палубу, подходит к игроку — над ним «Награда с
	рейдов» и кнопка «Посмотреть рекламу» (RaidCourierClient).

	⚠️ СЕРВЕР ДВИЖЕНИЕ НЕ РИСУЕТ. Все детали лодочника заякорены, и их на каждом кадре
	ставит КЛИЕНТ относительно плота, который он видит плавным (как чайку на
	грядке). Сервер ведёт только логику и публикует её атрибутами модели:
	  State        Rowing | Docking | Pickup | Disembarking | Walking | Delivered | Leaving
	  BoatRel      CFrame лодки в кадре плота (меняется в погоне, дальше постоянен)
	  PickupT0 / DisT0      серверное время начала подъёма / высадки
	  DisFrom / DisTo       откуда и куда шагает с лодки (кадр плота)
	  RootRel / WalkSpeed   где стоит на палубе (кадр плота) и с какой скоростью идёт
	  RecipientUserId       кому доставка
	Если бы сервер двигал заякоренные детали, клиенты видели бы их рывками в 20 Гц
	поверх плавного плота. Приварить к плоту тоже нельзя: движение по палубе
	двигало бы сам плот, а лодка влияла бы на его физику.

	Кадр плота: позиция PrimaryPart + поворот RestYaw (тот же, что у сетки стройки).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local AdService         = game:GetService("AdService")

local LOG = "[Лодочник]"

--[[ ⚠️ ХУК ЗАЧИСТКИ СТАВИМ ПЕРВЫМ ДЕЛОМ, ДО ЛЮБОГО WaitForChild.
     _G.OnIslandCleared — цепочка из нескольких скриптов; каждый держит
     предыдущий и зовёт его. Уступи мы до присваивания — другой скрипт мог бы
     прочитать нас как «предыдущего» раньше, чем мы появились. ]]
local requestFromClear
local prevCleared = _G.OnIslandCleared
_G.OnIslandCleared = function(island)
	if typeof(prevCleared) == "function" then
		local ok, err = pcall(prevCleared, island)
		if not ok then warn(LOG .. " предыдущий обработчик зачистки: " .. tostring(err)) end
	end
	if requestFromClear then task.spawn(requestFromClear, island) end
end

local Config = require(ReplicatedStorage:WaitForChild("RaidCourier"):WaitForChild("Config"))

local folder = workspace:FindFirstChild("RaidCouriers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "RaidCouriers"
	folder.Parent = workspace
end

local function now() return workspace:GetServerTimeNow() end

-- ═══════════ плот ═══════════
local function raftPP()
	local raft = workspace:FindFirstChild("Raft")
	return raft, raft and raft.PrimaryPart
end

local function raftFrame()
	local raft, pp = raftPP()
	if not pp then return nil end
	local yaw = pp:GetAttribute("RestYaw")
	if type(yaw) ~= "number" then
		local _, y = pp.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(pp.Position) * CFrame.Angles(0, yaw, 0), raft, pp
end

local function isFloorTile(child, pp)
	return child == pp or child.Name == "Raft_part" or child.Name == "Net_Part"
		or child:GetAttribute("BuildType") == "raft"
end

-- центры клеток палубы в кадре плота
local function deckTiles(F, raft, pp)
	local list = {}
	for _, c in ipairs(raft:GetChildren()) do
		if (c:IsA("Model") or c:IsA("BasePart")) and isFloorTile(c, pp) then
			local pos = c:IsA("Model") and c:GetBoundingBox().Position or c.Position
			table.insert(list, F:PointToObjectSpace(pos))
		end
	end
	return list
end

-- высота палубы под точкой (кадр плота) — лучом вниз по плоту
local function deckY(F, raft, x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { raft }
	local origin = F * Vector3.new(x, (fromY or 0) + 6, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -14, 0), params)
	if not hit then return nil end
	return F:PointToObjectSpace(hit.Position).Y
end

-- стоит ли персонаж на плоту
local function onRaft(player)
	local F, raft = raftFrame()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (F and hrp) then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { raft }
	return workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), params) ~= nil
end

-- ═══════════ шаблон ═══════════
--[[ ⚠️ ШАБЛОН ДВУХ ВИДОВ. Либо контейнер BoatCourier целиком, либо (как положил
     владелец) две отдельные модели — лодочник (Raider) и лодка (Rowboat) — где
     угодно в ReplicatedStorage/ServerStorage. Во втором случае собираем контейнер
     сами. Лодочника узнаём не только по имени, но и по начинке (Humanoid +
     Carried_Box): имя «Raider» могут носить и чужие модели. ]]
local warned = false
local function findIn(roots, names, ok)
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and table.find(names, d.Name) and ok(d) then return d end
		end
	end
	return nil
end
local function findTemplate()
	local roots = { ServerStorage, ReplicatedStorage }
	local t = ServerStorage:FindFirstChild(Config.TEMPLATE_NAME, true)
		or ReplicatedStorage:FindFirstChild(Config.TEMPLATE_NAME, true)
	if t then return t end
	local rig = findIn(roots, Config.RIG_NAMES, function(m)
		return m:FindFirstChildOfClass("Humanoid") ~= nil and m:FindFirstChild("Carried_Box") ~= nil
	end)
	local boat = findIn(roots, { Config.BOAT_NAME }, function(m)
		return m:FindFirstChild("LeftOar") ~= nil or m:FindFirstChild("RightOar") ~= nil
	end)
	if rig and boat then
		local box = Instance.new("Model")
		box.Name = Config.TEMPLATE_NAME
		rig:Clone().Parent = box
		boat:Clone().Parent = box
		return box, true
	end
	if not warned then
		warned = true
		warn(LOG .. (" нет шаблона: ни контейнера «%s», ни пары моделей %s (Humanoid + Carried_Box) и %s (LeftOar/RightOar) в ReplicatedStorage/ServerStorage — найдено: лодочник %s, лодка %s")
			:format(Config.TEMPLATE_NAME, table.concat(Config.RIG_NAMES, "/"), Config.BOAT_NAME,
				rig and rig:GetFullName() or "нет", boat and boat:GetFullName() or "нет"))
	end
	return nil
end

-- клон без тестовой обвязки: остаются только лодочник и лодка
local function cloneCourier()
	local t, fresh = findTemplate()
	if not t then return nil end
	local m = fresh and t or t:Clone()
	local rig
	for _, n in ipairs(Config.RIG_NAMES) do
		rig = rig or m:FindFirstChild(n)
	end
	local boat = m:FindFirstChild(Config.BOAT_NAME)
	for _, c in ipairs(m:GetChildren()) do
		if c ~= rig and c ~= boat then c:Destroy() end
	end
	if not (rig and boat) then
		warn(LOG .. " в шаблоне нет лодочника (" .. table.concat(Config.RIG_NAMES, "/") .. ") или лодки " .. Config.BOAT_NAME)
		m:Destroy()
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false          -- не толкает плот и игроков
			d.CanTouch = false
			d.Massless = true
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local box = rig:FindFirstChild("Carried_Box")
	local joint = rig:FindFirstChild("Torso") and rig.Torso:FindFirstChild("CarryBoxJoint")
	if not (root and hum and box and joint and box:FindFirstChild("BoxRoot")) then
		warn(LOG .. " в " .. rig.Name .. " не хватает HumanoidRootPart / Humanoid / Carried_Box.BoxRoot / Torso.CarryBoxJoint")
		m:Destroy()
		return nil
	end
	-- ⚠️ НЕ «Raider»: по префиксу Raider огнемёт считает модель врагом. Внутри клона
	-- имя NormalDummy — его понимают и анимация, и клиент (RIG_NAMES)
	rig.Name = "NormalDummy"
	rig:SetAttribute("RaftFriendly", true)   -- топор не бьёт (AxeCombat)
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	root.Anchored = true
	hum.AutoRotate = false
	joint.Enabled = false
	box.BoxRoot.Anchored = true
	-- ⚠️ ВСЕГДА У КЛИЕНТА: стриминг иначе может выгрузить лодку, пока она плывёт к плоту
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return m, rig, boat, root, box, joint
end

-- ═══════════ доставки ═══════════
local active = {}      -- [player] = delivery
local pending = {}     -- [player] = { until = os.clock() }

local function finish(dl, why)
	if dl.done then return end
	dl.done = true
	if typeof(_G.RewardAdsClearOffer) == "function" then _G.RewardAdsClearOffer(dl.player, "boatman") end
	if active[dl.player] == dl then active[dl.player] = nil end
	-- борт свободен для яхты торговца, если лодочников больше нет
	if next(active) == nil then
		local r = raftPP()
		if r then r:SetAttribute("CourierSide", nil) end
	end
	print(("%s доставка %s: %s"):format(LOG, dl.player.Name, why))
	if dl.model.Parent then
		dl.model:SetAttribute("State", "Leaving")
		task.delay(1.2, function() if dl.model.Parent then dl.model:Destroy() end end)
	end
end

local function stillValid(dl)
	if dl.done or not dl.model.Parent then return false end
	if dl.player.Parent ~= Players then finish(dl, "игрок вышел") return false end
	local F = raftFrame()
	if not F then finish(dl, "плота нет") return false end
	return true
end

-- Return over the same raft-local route used on the way to the player.
local function depart(dl, rewarded)
 if dl.done or dl.departing then return end
 dl.departing = true
 local m = dl.model
 m:SetAttribute("CargoGranted", rewarded == true)
 m:SetAttribute("State", "Returning")
 if typeof(_G.RewardAdsClearOffer) == "function" then _G.RewardAdsClearOffer(dl.player, "boatman") end
 print(("%s %s: лодочник возвращается в лодку (%s), точек маршрута %d"):format(LOG, dl.player.Name,
  rewarded and "награда выдана" or "с ящиком", #dl.route))
 task.spawn(function()
  local ok, err = pcall(function()
   local cur = m:GetAttribute("RootRel").Position
   local started = os.clock()
   local stuckFor, forced = 0, false
   for i = #dl.route, 1, -1 do
    local target = dl.route[i]
    while (target - cur).Magnitude > 0.08 do
     local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
     if not stillValid(dl) then return end
     if os.clock() - started > Config.WALK_TIMEOUT * 2 then finish(dl, "return route blocked") return end
     local F, raft, pp = raftFrame()
     local delta = target - cur
     local nextPos = cur + delta.Unit * math.min(delta.Magnitude, Config.WALK_SPEED * dt)
     local y = deckY(F, raft, nextPos.X, nextPos.Z, cur.Y - Config.ROOT_HEIGHT)
     --[[ ⚠️ МАРШРУТ УЖЕ ПРОЙДЕН ТУДА — ЗНАЧИТ ПО НЕМУ МОЖНО ИДТИ И ОБРАТНО.
          Проверка шага (палуба под ногами, нет постройки) бывала ложной: луч
          проваливался в щель между досками или цеплял стык клеток, и лодочник
          молча стоял до таймаута. Если шаг запрещён дольше RETURN_FORCE секунд,
          идём по записанной точке без проверки: этот участок он прошёл сам. ]]
     local blocked = not forced and (not y or math.abs(y + Config.ROOT_HEIGHT - cur.Y) > 1.5)
     local op = OverlapParams.new()
     op.FilterType = Enum.RaycastFilterType.Include
     op.FilterDescendantsInstances = { raft }
     for _, part in ipairs(workspace:GetPartBoundsInBox(F * CFrame.new(nextPos), Vector3.new(1.6, 2.2, 1.6), op)) do
      local top = part
      while top.Parent and top.Parent ~= raft do top = top.Parent end
      if not forced and part.CanCollide and not isFloorTile(top, pp) then blocked = true break end
     end
     if blocked then
      stuckFor += dt
      if stuckFor > (Config.RETURN_FORCE or 1.5) then
       forced = true
       print(("%s %s: обратный путь — шаг запрещён %.1f с, иду по записанному маршруту"):format(LOG, dl.player.Name, stuckFor))
      end
     else
      stuckFor = 0
     end
     if not blocked then
      cur = nextPos
      local dir = Vector3.new(delta.X, 0, delta.Z)
      if dir.Magnitude > 0.001 then m:SetAttribute("RootRel", CFrame.lookAt(cur, cur + dir)) end
     end
     m:SetAttribute("WalkSpeed", blocked and 0 or Config.WALK_SPEED)
    end
   end
   m:SetAttribute("WalkSpeed", 0)
   local boatRel = m:GetAttribute("BoatRel")
   m:SetAttribute("DisFrom", m:GetAttribute("RootRel"))
   m:SetAttribute("DisTo", boatRel * CFrame.new(0, 3.05, -0.55))
   m:SetAttribute("DisT0", now())
   m:SetAttribute("State", "Boarding")
   task.wait(Config.DISEMBARK_TIME)
   if not stillValid(dl) then return end
   -- ⚠️ ЯЩИК ОТЦЕПЛЯЕМ РОВНО В НАЧАЛЕ УКЛАДКИ: дальше его ведёт поза Pickup
   -- (клиент), до этого — сустав у груди. Иначе на кадр он «прыгал».
   dl.joint.Enabled = false
   dl.box.BoxRoot.Anchored = true
   if not rewarded then
    -- укладка — только если ящик остался (крестик / таймаут)
    m:SetAttribute("PickupT0", now())
    m:SetAttribute("State", "Putdown")
    task.wait(Config.PUTDOWN_TIME)
    if not stillValid(dl) then return end
   end
   -- ⚠️ ПОСАДКА — ОТДЕЛЬНАЯ АНИМАЦИЯ, А НЕ ПОДЪЁМ ЗАДОМ НАПЕРЁД (v4):
   -- шаги к банке, опускание корпуса, сгиб ног, захват вёсел. Лодка всё это
   -- время стоит у борта вместе с плотом (BoatRel не меняется).
   m:SetAttribute("SitT0", now())
   m:SetAttribute("State", "Sitting")
   task.wait(Config.SIT_TIME)
   if not stillValid(dl) then return end
   m:SetAttribute("State", "OarsReady")
   task.wait(Config.OARS_READY_TIME)
   if not stillValid(dl) then return end
   m:SetAttribute("State", "Departing")
   local q = boatRel.Position
   local _, yaw = boatRel:ToEulerAnglesYXZ()
   local elapsed = 0
   -- курс отхода: от борта в свободную воду — проверяем остров/лодки по курсу
   local sx = dl.side or 1   -- отходим от своего борта наружу
   local direction = Vector3.new(sx, 0, -0.35).Unit
   do
    local F0, raft0 = raftFrame()
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = { raft0, m }
    for _, cand in ipairs({ Vector3.new(sx, 0, -0.35), Vector3.new(sx, 0, 0.35), Vector3.new(sx, 0, 0),
     Vector3.new(sx, 0, -0.9), Vector3.new(sx, 0, 0.9) }) do
     local dir = cand.Unit
     local mid = q + dir * (Config.DEPART_CLEAR * 0.5)
     local look = CFrame.lookAt(F0 * mid, F0 * (mid + dir))
     local blocked = false
     for _, part in ipairs(workspace:GetPartBoundsInBox(look + Vector3.new(0, 2, 0), Vector3.new(8, 5, Config.DEPART_CLEAR), op)) do
      if part.CanCollide then blocked = true break end
     end
     if not blocked then direction = dir break end
    end
   end
   while elapsed < Config.DEPART_TIME do
    local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
    if not stillValid(dl) then return end
    elapsed += dt
    local F, _, pp = raftFrame()
    local speed = Config.DEPART_SPEED * math.min(elapsed / 2.5, 1)
    local rv = F:VectorToObjectSpace(pp.AssemblyLinearVelocity)
    local velocity = direction * speed + Vector3.new(rv.X, 0, rv.Z)
    local targetYaw = math.atan2(-velocity.X, -velocity.Z)
    local diff = math.atan2(math.sin(targetYaw - yaw), math.cos(targetYaw - yaw))
    yaw += math.clamp(diff, -Config.TURN_RATE * dt, Config.TURN_RATE * dt)
    q += direction * speed * dt
    m:SetAttribute("BoatRel", CFrame.new(q) * CFrame.Angles(0, yaw, 0))
   end
   finish(dl, rewarded and "reward delivered, sailed away" or "sailed away with cargo")
  end)
  if not ok then warn(LOG .. tostring(err)); finish(dl, "return error") end
 end)
end

local function deliver(player)
	if active[player] then return false, "уже едет" end
	local F, raft, pp = raftFrame()
	if not F then return false, "нет плота" end
	local tiles = deckTiles(F, raft, pp)
	if #tiles == 0 then return false, "у плота нет палубы" end

	-- причал: правый (+X) борт, у клетки, ближайшей к середине по длине
	--[[ ⚠️ У правого борта может стоять яхта торговца (она тоже берёт его первым) —
	     тогда к левому (−X): лодка и яхта вставали в одну точку. Другой лодочник
	     уже у борта — туда же. s — знак борта по X. ]]
	local s = 1
	local yachtOut = typeof(_G.MerchantYachtOut) == "function" and _G.MerchantYachtOut() or nil
	if typeof(yachtOut) == "Vector3" and yachtOut.X > 0.5 then s = -1 end
	if type(raft:GetAttribute("CourierSide")) == "number" then s = raft:GetAttribute("CourierSide") end
	raft:SetAttribute("CourierSide", s)
	local maxX = -math.huge
	for _, t in ipairs(tiles) do maxX = math.max(maxX, t.X * s) end
	local best
	for _, t in ipairs(tiles) do
		if math.abs(t.X * s - maxX) < 1 and (not best or math.abs(t.Z) < math.abs(best.Z)) then best = t end
	end
	local edgeX = best.X + 5 * s
	local dockZ = best.Z
	local boatDock = CFrame.new(edgeX + s * Config.DOCK_SIDE_OFFSET, Config.BOAT_Y, dockZ)

	-- старт: сбоку и позади по ходу плота
	local vel = pp.AssemblyLinearVelocity
	local vLocal = F:VectorToObjectSpace(Vector3.new(vel.X, 0, vel.Z))
	local backSign = (vLocal.Z > 0.5) and -1 or ((vLocal.Z < -0.5) and 1 or 1)
	local startPos = Vector3.new(edgeX + s * Config.SPAWN_SIDE, Config.BOAT_Y, dockZ + backSign * Config.SPAWN_BACK)
	-- свободна ли вода (остров, другие лодки)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { raft, folder }
	for _, try in ipairs({ 1, -1 }) do
		local p = Vector3.new(edgeX + s * Config.SPAWN_SIDE, Config.BOAT_Y, dockZ + try * backSign * Config.SPAWN_BACK)
		local hits = workspace:GetPartBoundsInBox(F * CFrame.new(p + Vector3.new(0, 2, 0)), Vector3.new(8, 4, 12), overlap)
		local blocked = false
		for _, h in ipairs(hits) do if h.CanCollide then blocked = true break end end
		if not blocked then startPos = p break end
	end

	local m, rig, boat, root, box, joint = cloneCourier()
	if not m then return false, "нет шаблона" end
	m.Name = "RaidCourier_" .. player.UserId
	m:SetAttribute("RecipientUserId", player.UserId)
	local startYaw = math.atan2(-(boatDock.Position.X - startPos.X), -(boatDock.Position.Z - startPos.Z))
	local boatRel = CFrame.new(startPos) * CFrame.Angles(0, startYaw, 0)
	m:SetAttribute("BoatRel", boatRel)
	m:SetAttribute("State", "Rowing")
	-- серверная копия встаёт туда же, где её нарисует клиент (для стриминга и проверок)
	boat:PivotTo(F * boatRel)
	root.CFrame = F * boatRel * CFrame.new(0, 2.6, 0.8)
	box:PivotTo(F * boatRel * CFrame.new(0, 1.45, -2.6))
	m.Parent = folder

	local dl = { player = player, model = m, rig = rig, root = root, box = box, joint = joint, route = {}, side = s }
	active[player] = dl
	print(("%s %s: лодка вышла, до причала %.0f студов"):format(LOG, player.Name, (startPos - boatDock.Position).Magnitude))

	task.spawn(function()
		local ok, err = pcall(function()
			-- ── погоня (в кадре плота) ──
			local q = boatRel.Position
			local yaw = startYaw
			local relVel = Vector3.zero
			local t0 = os.clock()
			while true do
				local dt = RunService.Heartbeat:Wait()
				if not stillValid(dl) then return end
				if os.clock() - t0 > Config.CHASE_TIMEOUT then finish(dl, "не догнал плот") return end
				local F2, _, pp2 = raftFrame()
				local rv = pp2.AssemblyLinearVelocity
				local raftSpeed = Vector3.new(rv.X, 0, rv.Z).Magnitude
				local maxSpeed = math.max(Config.MIN_SPEED, raftSpeed * Config.SPEED_MULT + Config.SPEED_ADD)
				local relMax = math.max(2, maxSpeed - raftSpeed)
				local to = boatDock.Position - q
				to = Vector3.new(to.X, 0, to.Z)
				local dist = to.Magnitude
				if dist < Config.DOCK_EPS and relVel.Magnitude < 1.5 then break end
				-- ближе SLOW_RADIUS — плавно гасим относительную скорость (лодка идёт вровень с плотом)
				local want = dist > 0.01 and to.Unit * math.min(relMax, relMax * dist / Config.SLOW_RADIUS + 0.6) or Vector3.zero
				relVel = relVel:Lerp(want, math.min(1, dt * Config.ACCEL))
				q += relVel * dt
				-- курс: по мировому ходу лодки, у борта — выравнивается вдоль плота
				local worldVel = F2:VectorToObjectSpace(Vector3.new(rv.X, 0, rv.Z)) + relVel
				local wantYaw = (worldVel.Magnitude > 0.5) and math.atan2(-worldVel.X, -worldVel.Z) or yaw
				local align = math.clamp(1 - dist / Config.SLOW_RADIUS, 0, 1)
				local dockYaw = (math.cos(wantYaw) >= 0) and 0 or math.pi   -- вдоль плота, ближе к текущему курсу
				local target = wantYaw + math.atan2(math.sin(dockYaw - wantYaw), math.cos(dockYaw - wantYaw)) * align
				local diff = math.atan2(math.sin(target - yaw), math.cos(target - yaw))
				yaw += math.clamp(diff, -Config.TURN_RATE * dt, Config.TURN_RATE * dt)
				boatRel = CFrame.new(q.X, Config.BOAT_Y, q.Z) * CFrame.Angles(0, yaw, 0)
				m:SetAttribute("BoatRel", boatRel)
			end
			boatRel = CFrame.new(boatDock.Position) * CFrame.Angles(0, (math.cos(yaw) >= 0) and 0 or math.pi, 0)
			m:SetAttribute("BoatRel", boatRel)

			-- ── причалил, подъём ящика ──
			m:SetAttribute("State", "Docking")
			task.wait(Config.DOCKING_TIME)
			if not stillValid(dl) then return end
			m:SetAttribute("PickupT0", now())
			m:SetAttribute("State", "Pickup")
			task.wait(Config.PICKUP_TIME)
			if not stillValid(dl) then return end
			box.BoxRoot.Anchored = false     -- дальше ящик держит сустав CarryBoxJoint
			joint.Enabled = true

			-- ── высадка на палубу ──
			local F3, raft3 = raftFrame()
			local fromRel = boatRel * CFrame.new(0, 2.6 + 0.45, -0.55)
			local deckX = edgeX - 3 * s
			local dy = deckY(F3, raft3, deckX, dockZ, 2) or 0.8
			local toPos = Vector3.new(deckX, dy + Config.ROOT_HEIGHT, dockZ)
			local toRel = CFrame.lookAt(toPos, toPos + Vector3.new(-s, 0, 0))
			m:SetAttribute("DisFrom", CFrame.new(fromRel.Position) * CFrame.Angles(0, math.atan2(-(toPos.X - fromRel.Position.X), -(toPos.Z - fromRel.Position.Z)), 0))
			m:SetAttribute("DisTo", toRel)
			m:SetAttribute("DisT0", now())
			m:SetAttribute("State", "Disembarking")
			task.wait(Config.DISEMBARK_TIME)
			if not stillValid(dl) then return end

			-- ── по палубе к игроку ──
			dl.route = { toRel.Position }
			local cur = toRel.Position
			m:SetAttribute("RootRel", toRel)
			m:SetAttribute("WalkSpeed", 0)
			m:SetAttribute("State", "Walking")
			local walkT0 = os.clock()
			local lastPub = 0
			local stuckT = 0
			while true do
				local dt = RunService.Heartbeat:Wait()
				if not stillValid(dl) then return end
				local F4, raft4, pp4 = raftFrame()
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if not (hrp and hum and hum.Health > 0) then
					m:SetAttribute("WalkSpeed", 0)      -- ждём респавна на месте
				else
					local pl = F4:PointToObjectSpace(hrp.Position)
					local flat = Vector3.new(pl.X - cur.X, 0, pl.Z - cur.Z)
					if flat.Magnitude <= Config.STOP_DIST + 0.3 then break end
					if os.clock() - walkT0 > Config.WALK_TIMEOUT then
						if flat.Magnitude < 8 then break end
						finish(dl, "не дошёл до игрока") return
					end
					-- шаг: прямо к игроку; упёрлись в край или стену — обходим под углом
					local stepLen = Config.WALK_SPEED * dt
					local moved = false
					for _, ang in ipairs({ 0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5 }) do
						local dir = CFrame.Angles(0, ang, 0):VectorToWorldSpace(flat.Unit)
						local nx, nz = cur.X + dir.X * stepLen, cur.Z + dir.Z * stepLen
						local y = deckY(F4, raft4, nx, nz, cur.Y - Config.ROOT_HEIGHT)
						if y then
							local probe = F4 * CFrame.new(nx + dir.X * 0.8, y + 2.6, nz + dir.Z * 0.8)
							local op = OverlapParams.new()
							op.FilterType = Enum.RaycastFilterType.Include
							op.FilterDescendantsInstances = { raft4 }
							local blocked = false
							for _, part in ipairs(workspace:GetPartBoundsInBox(probe, Vector3.new(1.6, 2.2, 1.6), op)) do
								if part.CanCollide then
									local top = part
									while top.Parent and top.Parent ~= raft4 do top = top.Parent end
									if not isFloorTile(top, pp4) then blocked = true break end
								end
							end
							if not blocked then
								cur = Vector3.new(nx, y + Config.ROOT_HEIGHT, nz)
								if (cur - dl.route[#dl.route]).Magnitude >= 0.35 then table.insert(dl.route, cur) end
								local face = Vector3.new(dir.X, 0, dir.Z)
								local rel = CFrame.lookAt(cur, cur + face)
								if os.clock() - lastPub > 0.05 then
									lastPub = os.clock()
									m:SetAttribute("RootRel", rel)
									m:SetAttribute("WalkSpeed", Config.WALK_SPEED)
								end
								moved = true
								break
							end
						end
					end
					if moved then stuckT = 0 else
						stuckT += dt
						m:SetAttribute("WalkSpeed", 0)
						if stuckT > 6 then
							if flat.Magnitude < 8 then break end
							finish(dl, "застрял на палубе") return
						end
					end
				end
			end
			-- ── подошёл: лицом к игроку ──
			local F5 = raftFrame()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local face = hrp and F5:PointToObjectSpace(hrp.Position) or (cur + Vector3.new(-1, 0, 0))
			m:SetAttribute("RootRel", CFrame.lookAt(cur, Vector3.new(face.X, cur.Y, face.Z)))
			m:SetAttribute("WalkSpeed", 0)
			m:SetAttribute("State", "Delivered")
			dl.deliveredAt = os.clock()
			-- оффер «Награда с рейда» (RewardAdService): обычные (бесплатно) или всё
			-- (Robux); проверка — лодочник ещё ждёт и игрок рядом. После любой
			-- выдачи или ✕ он сразу уплывает
			if typeof(_G.RewardAdsSetOffer) == "function" then
				_G.RewardAdsSetOffer(player, "boatman", _G.RewardAdsRaidLoot(), {
					validate = function(pl)
						if dl.done or m:GetAttribute("State") ~= "Delivered" then return false, "лодочник не ждёт" end
						local F6 = raftFrame()
						local rel = m:GetAttribute("RootRel")
						local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
						if not (F6 and hrp and typeof(rel) == "CFrame") then return false, "нет позиции" end
						if ((F6 * rel).Position - hrp.Position).Magnitude > Config.AD_RADIUS + 6 then return false, "далеко" end
						return true
					end,
					onGranted = function() depart(dl, true) end,
					onDismiss = function() depart(dl, false) end,
				})
			end
			print(("%s %s: лодочник подошёл с ящиком"):format(LOG, player.Name))
			while not dl.done and not dl.departing do
				task.wait(1)
				if not stillValid(dl) then return end
				if not dl.departing and os.clock() - dl.deliveredAt > Config.DELIVERED_TIMEOUT
					and not (typeof(_G.RewardAdsIsBusy) == "function" and _G.RewardAdsIsBusy(player)) then
					depart(dl, false) return
				end
			end
		end)
		if not ok then
			warn(LOG .. " ошибка доставки: " .. tostring(err))
			finish(dl, "ошибка")
		end
	end)
	return true
end

-- ═══════════ очередь: доставка стартует, когда игрок на плоту ═══════════
local function request(player, why)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "нет игрока" end
	if active[player] then return false, "уже едет" end
	pending[player] = { untilT = os.clock() + Config.WAIT_ON_RAFT, why = why }
	print(("%s %s: доставка в очереди (%s) — ждёт, пока игрок на плоту"):format(LOG, player.Name, tostring(why)))
	return true
end
_G.RequestRaidCourier = request

task.spawn(function()
	while true do
		task.wait(1)
		for player, p in pairs(pending) do
			if player.Parent ~= Players or os.clock() > p.untilT then
				pending[player] = nil
			elseif not active[player] and onRaft(player) then
				pending[player] = nil
				local ok, why = deliver(player)
				if not ok then warn(("%s %s: доставка не началась — %s"):format(LOG, player.Name, tostring(why))) end
			end
		end
	end
end)

-- рейд = зачистка острова: награду везут тому, кто закрыл остров, иначе капитану
local clearedOnce = setmetatable({}, { __mode = "k" })
requestFromClear = function(island)
	if typeof(island) ~= "Instance" or clearedOnce[island] then return end
	clearedOnce[island] = true
	task.wait(Config.AFTER_CLEAR_DELAY)
	local who = Players:GetPlayerByUserId(tonumber(island:GetAttribute("LastActorId")) or 0)
	if not who then
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("RaftOwner") then who = p break end
		end
	end
	who = who or Players:GetPlayers()[1]
	if who then request(who, "зачищен " .. island.Name) end
end

Players.PlayerRemoving:Connect(function(p)
	pending[p] = nil
	local dl = active[p]
	if dl then finish(dl, "игрок вышел") end
end)

-- ═══════════ реклама ═══════════
-- ⚠️ ВСЯ РЕКЛАМА — В RewardAdService: здесь только оффер «boatman», когда
-- лодочник подошёл, и его проверка (тот ли игрок, рядом ли, ещё ждёт ли).

print(LOG .. " готов: после зачистки острова везёт награду на плот; _G.RequestRaidCourier(player)")
