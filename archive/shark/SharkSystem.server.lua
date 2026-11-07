--[[
	АКУЛА У ПЛОТА — серверная половина.

	Кружит вокруг плота, раз в две минуты выбирает доску и грызёт её, снимая
	плоту прочность. Спавн — кнопкой в настройках (_G.SpawnShark).

	⚠️ АНИМАЦИЮ ЗДЕСЬ НИКТО НЕ КРУТИТ, И ЭТО НЕ ЛЕНЬ.
	Motor6D.Transform НЕ реплицируется: покрути мы суставы отсюда, у игроков
	акула висела бы столбом, причём молча. Сервер называет клип атрибутом
	(setClip / fireOnce), а позу считает каждый клиент у себя — SharkClient.
	Здесь только МАРШРУТ и УРОН.

	⚠️ ДВИЖЕНИЕ КИНЕМАТИЧЕСКОЕ, ЧЕРЕЗ PivotTo.
	Корень рига заякорен (SharkRig.setup), физика его не тянет. Это и нужно:
	акула ходит рядом с плотом, а плот — физическая сборка на воде. Толкни её
	физическим телом — и плот поедет, как было с бочкой в сетке.

	⚠️ НОС МОДЕЛИ СМОТРИТ НА -Z.
	Ровно туда же смотрит LookVector, поэтому CFrame.lookAt(откуда, куда)
	разворачивает акулу правильно без поправок. Это записано в SharkRigData
	(«Axes are Roblox's: nose on -Z»), и на другой модели проверять заново.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LOG = "[Акула]"

-- ── настройки ──
local ATTACK_PERIOD  = 120    -- секунд между нападениями
-- ⚠️ ПЕРВЫЙ БРОСОК — БЫСТРЕЕ ОСТАЛЬНЫХ, И ЭТО НАРОЧНО.
-- Акулу выпускают кнопкой, чтобы посмотреть, как она грызёт плот. Ждать ради
-- этого полные две минуты бессмысленно, а дальше она живёт своим ритмом.
local FIRST_ATTACK   = 15
local CRUISE_RADIUS  = 30     -- на каком удалении нарезает круги
local CRUISE_SPEED   = 13     -- студов в секунду по дуге
local CHARGE_SPEED   = 24     -- рывок к доске
local LEAVE_SPEED    = 20     -- отход после укуса
local BITE_STANDOFF  = 6      -- где встаёт носом к доске
local BITE_TIME      = 5      -- сколько грызёт
local BITE_DPS       = 3      -- прочности плота в секунду
local SWIM_DEPTH     = 1.8    -- насколько туша утоплена под поверхностью
local BITE_DEPTH     = 0.9    -- у плота всплывает: укус должно быть видно

-- ⚠️ ПАПКУ МОДУЛЕЙ ИЩЕМ ПО СОДЕРЖИМОМУ, А НЕ ПО ИМЕНИ — как и клиент.
-- FindFirstChild("Shark") отдаёт ПЕРВОГО ребёнка с таким именем, а их может
-- быть двое: папка модулей и модель из 3D Importer. Порядок детей у сервера и
-- клиента разный, так что по имени можно взять не ту.
local function moduleFolder()
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		for _, c in ipairs(ReplicatedStorage:GetChildren()) do
			if c:FindFirstChild("SharkAnimator") then return c end
		end
		task.wait(0.2)
	end
	return nil
end

local folder = moduleFolder()
if not folder then
	warn(LOG .. " в ReplicatedStorage нет модулей рига — акулы не будет")
	return
end
local Rig = require(folder.SharkRig)

--[[ Шаблон. Импортёр кладёт модель куда угодно, а ригу она нужна рядом с
     модулями, под именем Model. Требовать ручного переноса — значит молча
     ничего не спавнить, пока его не сделали, поэтому копию снимаем сами.
     Оригинал не трогаем: он мог быть положен туда намеренно.

     ⚠️ ИЩЕМ ПО ДЕТАЛИ shark_body1, А НЕ ПО ИМЕНИ МОДЕЛИ И НЕ ПО ОДНОМУ МЕСТУ.
     Первый заход искал модель с ребёнком shark_body1 только в Workspace — и не
     нашёл ничего, потому что акулу положили в ReplicatedStorage. Имя самой
     модели тоже ненадёжно: импортёр зовёт её то Shark2, то по имени файла.
     А вот деталь shark_body1 названа в риге (SharkRigData) и уникальна —
     от неё и пляшем, поднимаясь к её модели. ]]
local function findSource()
	for _, root in ipairs({ ReplicatedStorage, workspace }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "shark_body1" then
				local m = d.Parent
				-- Модель, положенную ВНУТРЬ папки модулей, тоже берём: не взять её
				-- было бы самой обидной осечкой — акула на месте, а поиск её
				-- пропускает. Мимо идёт только уже готовый шаблон Model.
				if m and m:IsA("Model") and m ~= folder:FindFirstChild("Model") then
					return m
				end
			end
		end
	end
	return nil
end

local function ensureTemplate()
	if folder:FindFirstChild("Model") then return true end

	local src = findSource()
	if not src then
		warn(("%s не нашёл деталь shark_body1 ни в ReplicatedStorage, ни в Workspace — "
			.. "положи туда модель акулы (пять деталей shark_*)"):format(LOG))
		return false
	end

	if not src.Archivable then src.Archivable = true end
	local copy = src:Clone()
	copy.Name = "Model"
	copy.Parent = folder
	print(("%s шаблон взят из %s → %s.Model; оригинал оставлен, его можно удалить")
		:format(LOG, src:GetFullName(), folder:GetFullName()))
	return true
end

-- ── плот ──
local function raftModel()
	local r = workspace:FindFirstChild("Raft")
	return (r and r:IsA("Model")) and r or nil
end

local function raftCenter()
	local r = raftModel()
	if not r then return nil end
	local ok, pivot = pcall(function() return r:GetPivot().Position end)
	return ok and pivot or nil
end

--[[ Уровень воды: луч сквозь воду рядом с плотом. Фолбэк — сам плот, его
     BoatMovement держит ровно на поверхности. ]]
local function waterLevel()
	local c = raftCenter()
	if not c then return nil end
	local rp = RaycastParams.new()
	rp.IgnoreWater = false
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { raftModel() }
	local res = workspace:Raycast(c + Vector3.new(0, 120, 0), Vector3.new(0, -500, 0), rp)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return c.Y - 0.5
end

--[[ Доски пола. Raft_part встречается и Моделью, и Деталью — берём позицию
     через GetPivot, он есть у обоих. ]]
local function raftPlanks()
	local r = raftModel()
	if not r then return {} end
	local out = {}
	for _, d in ipairs(r:GetDescendants()) do
		if d.Name == "Raft_part" and (d:IsA("Model") or d:IsA("BasePart")) then
			table.insert(out, d)
		end
	end
	return out
end

--[[ ⚠️ ЦЕЛЬ — БЛИЖАЙШАЯ ДОСКА, А НЕ СЛУЧАЙНАЯ.
     Случайная может оказаться в середине плота, и акула поплыла бы ГРЫЗТЬ
     СКВОЗЬ настил, заплывая под него. Ближайшая к акуле всегда с краю — с той
     стороны, откуда она подходит. ]]
local function nearestPlank(from)
	local best, bestD
	for _, p in ipairs(raftPlanks()) do
		local ok, pivot = pcall(function() return p:GetPivot().Position end)
		if ok then
			local d = (pivot - from).Magnitude
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best
end

-- ── одна акула на мир ──
local shark        -- риг
local angle = 0    -- где на круге
local state = "cruise"
local stateT = 0   -- сколько уже в этом состоянии
local nextAttack = 0
local target       -- доска, которую грызём
local biteAcc = 0  -- накопитель урона: DamageRaft зовём раз в секунду

local function clearShark()
	if shark then
		pcall(function() shark:destroy() end)
		shark = nil
	end
	target, state, biteAcc = nil, "cruise", 0
end

-- Плавное доведение позиции: без него рывок к цели выглядит телепортом.
local function approach(from, to, speed, dt)
	local delta = to - from
	local step = speed * dt
	if delta.Magnitude <= step then return to end
	return from + delta.Unit * step
end

--[[ Ставим акулу в точку и разворачиваем по ходу движения. Крен и покачивание
     добавляем поверх: без них кинематическое движение выглядит «по рельсам»,
     а сама анимация плавников этого не лечит — она про тело, не про курс. ]]
local function place(pos, lookDir, roll)
	if lookDir.Magnitude < 1e-3 then lookDir = Vector3.new(0, 0, -1) end
	local bob = math.sin(os.clock() * 1.6) * 0.35
	local cf = CFrame.lookAt(pos + Vector3.new(0, bob, 0), pos + lookDir.Unit * 10)
	shark:moveTo(cf * CFrame.Angles(0, 0, math.rad(roll or 0)))
end

local function startCruise()
	state, stateT, target = "cruise", 0, nil
	shark:setClip("Swim")
end

RunService.Heartbeat:Connect(function(dt)
	if not shark then return end
	if not shark.model.Parent then shark = nil return end

	local center = raftCenter()
	local surface = waterLevel()
	if not center or not surface then return end  -- плота нет: ждём, не дёргаемся

	stateT += dt
	local pos = shark.model:GetPivot().Position

	if state == "cruise" then
		-- нарезает круги: угловая скорость считается из линейной, иначе на
		-- большом радиусе акула ползёт, а на малом — носится
		angle += (CRUISE_SPEED / CRUISE_RADIUS) * dt
		local want = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * CRUISE_RADIUS
		want = Vector3.new(want.X, surface - SWIM_DEPTH, want.Z)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		place(approach(pos, want, CRUISE_SPEED * 1.4, dt), tangent, 6)

		if os.clock() >= nextAttack then
			target = nearestPlank(pos)
			if target then
				state, stateT = "charge", 0
				shark:notice()     -- заметила плот: разовый клип
			else
				nextAttack = os.clock() + 10  -- досок нет — вернёмся к вопросу позже
			end
		end

	elseif state == "charge" then
		if not (target and target.Parent) then startCruise() return end
		local tp = target:GetPivot().Position
		local dir = Vector3.new(tp.X - pos.X, 0, tp.Z - pos.Z)
		local flat = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0, 0, -1)
		-- встаём НЕ в доску, а поодаль от неё, носом к плоту
		local want = Vector3.new(tp.X, surface - BITE_DEPTH, tp.Z) - flat * BITE_STANDOFF
		place(approach(pos, want, CHARGE_SPEED, dt), flat, 0)

		if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(want.X, 0, want.Z)).Magnitude < 1.5
			or stateT > 8 then            -- ⚠️ таймаут: доска могла уехать под настил
			state, stateT, biteAcc = "bite", 0, 0
			shark:attack()                -- рывок пастью
			shark:gnaw()                  -- и дальше цикл «вцепилась»
		end

	elseif state == "bite" then
		if not (target and target.Parent) then startCruise() return end
		local tp = target:GetPivot().Position
		local dir = Vector3.new(tp.X - pos.X, 0, tp.Z - pos.Z)
		local flat = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0, 0, -1)
		place(pos, flat, math.sin(os.clock() * 7) * 8)  -- мотает башкой

		-- ⚠️ УРОН РАЗ В СЕКУНДУ, А НЕ КАЖДЫЙ КАДР.
		-- DamageRaft пишет прочность и дёргает UI: с Heartbeat это шестьдесят
		-- вызовов в секунду вместо одного.
		biteAcc += dt
		if biteAcc >= 1 then
			biteAcc -= 1
			if _G.DamageRaft then _G.DamageRaft(BITE_DPS) end
		end

		if stateT >= BITE_TIME then
			state, stateT = "leave", 0
			shark:setClip("Swim")
		end

	elseif state == "leave" then
		-- отходит на круг и успокаивается
		local out = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
		local dir = (out.Magnitude > 1e-3) and out.Unit or Vector3.new(0, 0, -1)
		local want = center + dir * CRUISE_RADIUS
		want = Vector3.new(want.X, surface - SWIM_DEPTH, want.Z)
		place(approach(pos, want, LEAVE_SPEED, dt), dir, 4)

		if (pos - want).Magnitude < 2 or stateT > 6 then
			-- угол круга подбираем под текущее место, иначе акулу дёрнет вбок
			angle = math.atan2(dir.Z, dir.X)
			nextAttack = os.clock() + ATTACK_PERIOD
			startCruise()
		end
	end
end)

--[[ Спавн. Одна акула на мир: вторая наматывала бы тот же круг в том же месте
     и выглядела бы дублем. Повторный вызов переставляет ту же особь. ]]
function _G.SpawnShark()
	if not ensureTemplate() then return false, "нет модели акулы" end
	local center = raftCenter()
	if not center then return false, "плота нет" end
	local surface = waterLevel() or center.Y

	clearShark()
	angle = math.random() * math.pi * 2
	local pos = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * CRUISE_RADIUS
	pos = Vector3.new(pos.X, surface - SWIM_DEPTH, pos.Z)

	local ok, made = pcall(function()
		return Rig.spawn(CFrame.lookAt(pos, center), workspace)
	end)
	if not ok or not made then return false, tostring(made) end

	shark = made
	shark.model.Name = "Shark"
	startCruise()
	nextAttack = os.clock() + FIRST_ATTACK
	return true
end

_G.DespawnShark = clearShark

print(("%s готова: круг %d студов, нападение раз в %d сек, укус %d/сек за %d сек")
	:format(LOG, CRUISE_RADIUS, ATTACK_PERIOD, BITE_DPS, BITE_TIME))
