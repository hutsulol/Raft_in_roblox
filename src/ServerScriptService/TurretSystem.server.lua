-- TurretSystem.server.lua
-- Пулемёт-турель (модель "Pulemet_lvl_1", и другие "Pulemet_*"). Обслуживается СНАРУЖИ
-- модели (Rojo её не контролирует). Структура модели:
--   Pushka (MeshPart) → bullet_1..bullet_6 (стволы, прозрачные копии-снаряды)
--   stul → Seat (сиденье), main (НЕПОДВИЖНАЯ опора), Corpus
--
-- Что делает:
--   • main приварен к плоту (едет с ним) и НЕ вращается; всё остальное — вращающаяся
--     сборка на Motor6D (main→Pushka), поворот влево-вправо = смена Motor6D.C0 (реплицируется);
--   • игрок садится (ProximityPrompt → Seat:Sit) → становится наводчиком; клиент
--     (TurretClient) берёт управление, камеру-прицел и UI;
--   • ЛКМ → выстрел ПООЧЕРЁДНО из bullet_1..6 по кругу: клон ствола становится ВИДИМЫМ,
--     летит по прямой с баллистикой (гравитация). Назван "Bullet_Cannon" + creator →
--     урон кораблям/врагам считает ShipCombat (единый путь).
--
-- Направление стрельбы = ось Pushka (по умолчанию LookVector). Если снаряды летят не туда —
-- атрибуты на модели: AimAxis ("X"/"Y"/"Z", деф "Z"), AimSign (1/-1, деф -1),
-- AimPitchDeg (доп. подъём ствола в градусах, деф 0). BulletSpeed (деф 200), YawSpeedDeg (деф 75).

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

-- ЗАМОРОЗКА — САМОЕ ПЕРВОЕ ДЕЙСТВИЕ, до require/WaitForChild ниже: они ЙЕЛДЯТ,
-- а физика в это время уже идёт. Турель из редактора лежит без якорей и стыков
-- (шаблон рассчитан на CanonSystem, который варит при постановке), и за эти
-- кадры её детали осыпались — потом setup собирал шарниры по упавшим позам.
-- Анкорим всё сразу; сборка ниже сама снимет якоря, когда построит стыки.
-- ⚠️ ТУЛЫ НЕ ТРОГАЕМ: заякоренный инструмент в руках намертво прибил бы персонажа
-- к месту. Инструмент постановки зовётся ровно как модель — подробности у
-- isPlacedTurret ниже.
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and not d:IsA("Tool") and d.Name:sub(1, 8) == "Pulemet_"
		and not Players:GetPlayerFromCharacter(d.Parent) then
		for _, p in ipairs(d:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true end
		end
		print("[Turret] заморозил до сборки: " .. d:GetFullName())
	end
end

local CombatSounds  = require(ReplicatedStorage:WaitForChild("CombatSounds"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))

local TURRET_PREFIX = "Pulemet_"
local SIT_ANIM      = "rbxassetid://106166282537805"
local FIRE_COOLDOWN = 0.12   -- сек между выстрелами (дефолт; per-модель — ниже)
-- Темп НА МОДЕЛЬ: первый уровень стреляет вдвое реже второго.
-- Переопределяется атрибутом FireCooldown на самой модели; setup копирует итог
-- в атрибут, откуда его читает клиент (темп клика и скорость проворота стволов).
local TURRET_COOLDOWN = {
	Pulemet_lvl_1 = 0.24,
	Pulemet_lvl_2 = 0.12,
}
-- Урон на модель (ShipCombat: гуманоиду = 100*DmgMult, кораблю — зонный по тому же множителю).
-- Переопределяется атрибутом DmgMult на самой модели.
local TURRET_DMG = {
	Pulemet_lvl_1 = 0.15, -- 15 урона за попадание
	Pulemet_lvl_2 = 0.35, -- эпический: больше чем вдвое (35 за попадание)
}
local DEFAULT_DMG_MULT = 0.15
-- звук выстрела на модель (категория CombatSounds); переопределяется атрибутом FireSound
local TURRET_SFX = {
	Pulemet_lvl_1 = "woodShot", -- стреляет деревяшками → деревянный «тук»
	Pulemet_lvl_2 = "mgShot",   -- эпический: характерная пулемётная очередь
}
local DEFAULT_SFX = "woodShot"
local DEFAULT_SPEED = 200
local DEFAULT_YAW   = 75     -- град/с поворота (влево-вправо)
local DEFAULT_PITCH_SPEED = 50 -- град/с наклона (вверх-вниз)
local DEFAULT_PITCH_LIMIT = 20 -- макс. наклон ствола, град
local DEFAULT_SPIN_SHOT   = 60 -- на столько градусов Pushka проворачивается за выстрел
                               -- (6 стволов × 60° = полный оборот — эффект Гатлинга)

-- ── remotes ──
local function ensure(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local rEnter = ensure("TurretEnter") -- сервер→наводчик: {model, sitAnim}
local rExit  = ensure("TurretExit")  -- сервер→бывший наводчик
local rInput = ensure("TurretInput") -- наводчик→сервер: dir (-1/0/1) поворота
local rFire  = ensure("TurretFire")  -- наводчик→сервер: выстрел

local turrets = {}          -- [model] = state
local gunnerOf = {}         -- [player] = state (кем управляет)
local setupDone = setmetatable({}, { __mode = "k" })

-- направление выстрела из Pushka + атрибуты модели (клиент считает так же)
local function axisVec(cf, name)
	if name == "X" then return cf.RightVector end
	if name == "Y" then return cf.UpVector end
	return cf.LookVector
end
local function fireDir(model, pushka)
	local axis = model:GetAttribute("AimAxis") or "Z"
	local sign = model:GetAttribute("AimSign") or 1 -- LookVector уже «вперёд»
	local pitch = math.rad(model:GetAttribute("AimPitchDeg") or 0)
	local d = axisVec(pushka.CFrame, axis) * sign
	if pitch ~= 0 then
		-- подъём вокруг горизонтальной оси, перпендикулярной направлению
		local right = Vector3.new(d.Z, 0, -d.X)
		if right.Magnitude > 1e-3 then
			d = (CFrame.fromAxisAngle(right.Unit, pitch) * d)
		end
	end
	return d.Unit
end

-- Поза турели двумя шарнирами:
--   TurretYaw   (main→carrier): поворот вокруг мачты + наклон — несёт корпус, стул, игрока;
--   GatlingSpin (carrier→Pushka): ПРОВОРОТ только блока стволов вокруг СВОЕГО pivot.
local function applyMotor(state)
	state.motor.C0 = CFrame.Angles(0, state.yaw, 0) * state.C0base
		* CFrame.Angles(state.pitch, 0, 0) -- наклон вокруг локального X
	if state.spinMotor then
		-- вокруг pivot самой Pushka (PivotOffset — тот же, что показывает гизмо в Studio)
		local po = state.pushka.PivotOffset
		local ax = state.model:GetAttribute("SpinAxis") or "Z"
		local rot = (ax == "X" and CFrame.Angles(state.spin, 0, 0))
			or (ax == "Y" and CFrame.Angles(0, state.spin, 0))
			or CFrame.Angles(0, 0, state.spin)
		state.spinMotor.C0 = state.spinBase * po * rot * po:Inverse()
	end
end

local function clearJoints(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("ManualWeld") then
			d:Destroy()
		end
	end
end

-- защита от «развалилась»: жёстко приварить ВСЕ части к плоту (используется на любом
-- аварийном выходе — деталь без стыка = упавшая деталь).
local function weldAllToRaft(model, rpp)
	-- Сначала СНИМАЕМ старые стыки: сюда можно попасть после того, как pcall успел
	-- создать Motor6D, и жёсткий велд поверх живого мотора даёт переопределённую
	-- связь — солвер начинает дёргать сборку.
	clearJoints(model)
	-- скорость плота: снимок до и возврат после (+ RaftShake: второй раз после шага физики)
	local linVel, angVel = rpp.AssemblyLinearVelocity, rpp.AssemblyAngularVelocity
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			-- ТЕ ЖЕ свойства, что и в штатной сборке. Без них аварийная приварка
			-- возвращает баг «плот не едет»: деталь турели с обычной массой и
			-- RootPriority 0 может стать КОРНЕМ сборки, и тогда силы BoatMovement,
			-- приложенные к raft.PrimaryPart, перестают её двигать. А включённые
			-- EnableFluidForces ломают точную компенсацию гравитации у плота.
			d.Massless = true
			d.RootPriority = -127
			pcall(function() d.EnableFluidForces = false end)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = rpp, d
			w.Parent = d
		end
	end
	rpp.AssemblyLinearVelocity = linVel
	rpp.AssemblyAngularVelocity = angVel
	RaftShake.notify()
end

-- Стартовое сканирование идёт СИНХРОННО при загрузке скрипта, поэтому модель может
-- быть ещё не дореплицирована целиком (нет Seat, не все стволы, у плота нет
-- PrimaryPart). Раньше такая турель помечалась обработанной навсегда и оставалась
-- глухим куском металла до перезапуска сервера. Теперь пробуем ещё несколько раз.
local MAX_SETUP_ATTEMPTS = 5
local SETUP_RETRY_DELAY  = 2
local setupAttempts = setmetatable({}, { __mode = "k" })

local function setup(model)
	if setupDone[model] then return end
	local raft = workspace:FindFirstChild("Raft")
	local rpp  = raft and raft.PrimaryPart

	-- структура ещё не готова → страхуемся приваркой и пробуем позже
	local function retryLater(reason)
		local n = (setupAttempts[model] or 0) + 1
		setupAttempts[model] = n
		-- пока ждём, детали не должны рассыпаться (weldAllToRaft сам снимает
		-- прошлые стыки, так что повторы не копят велды друг на друга)
		if rpp then weldAllToRaft(model, rpp) end
		if n >= MAX_SETUP_ATTEMPTS then
			setupDone[model] = true
			warn(("[Turret] %s: %s — сдаюсь после %d попыток, осталась приваренной к плоту")
				:format(model:GetFullName(), reason, n))
			return
		end
		warn(("[Turret] %s: %s — попытка %d/%d, повтор через %ds")
			:format(model:GetFullName(), reason, n, MAX_SETUP_ATTEMPTS, SETUP_RETRY_DELAY))
		task.delay(SETUP_RETRY_DELAY, function()
			if model.Parent then setup(model) end
		end)
	end

	local pushka = model:FindFirstChild("Pushka", true)
	local main   = model:FindFirstChild("main", true)
	local seat   = model:FindFirstChildWhichIsA("Seat", true) or model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not (pushka and pushka:IsA("BasePart") and main and main:IsA("BasePart") and seat) then
		retryLater(("нет Pushka/main/Seat (pushka=%s main=%s seat=%s)")
			:format(tostring(pushka ~= nil), tostring(main ~= nil), tostring(seat ~= nil)))
		return
	end
	-- ⚠️ СИДЕНЬЕ НЕ ДОЛЖНО ХВАТАТЬ ТОГО, КТО ТОЛЬКО ЧТО ПОСТАВИЛ ТУРЕЛЬ.
	-- Пулемёт ставится ровно туда, куда игрок целился, — то есть рядом с ним, а
	-- нередко прямо под ним. Seat в Roblox сажает любого, кто его КОСНУЛСЯ, поэтому
	-- строитель мгновенно оказывался пристёгнутым к ещё не собранной турели: со
	-- стороны это выглядело как «персонаж застыл лёжа над плотом».
	-- Гасим сиденье на пару секунд: за это время игрок отходит, а сборка турели
	-- (шарниры, сварки) успевает закончиться. Сесть можно будет по промпту, как и
	-- задумано, — этот путь Disabled не трогает.
	if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
		seat.Disabled = true
		task.delay(2, function()
			if seat and seat.Parent then seat.Disabled = false end
		end)
	end

	-- стволы bullet_1.. по порядку
	local bullets = {}
	local i = 1
	while true do
		local b = model:FindFirstChild("bullet_" .. i, true)
		if not b or not b:IsA("BasePart") then break end
		bullets[i] = b
		i += 1
	end
	if #bullets == 0 then
		retryLater("нет стволов bullet_N")
		return
	end
	if not rpp then
		retryLater("у плота ещё нет PrimaryPart")
		return
	end

	-- структура на месте — фиксируем, дальше идёт настоящая сборка
	setupDone[model] = true
	print(("[Turret] структура OK (%s): стволов %d — собираю"):format(model.Name, #bullets))

	-- ── СТОП ПАДЕНИЮ + ВОЗВРАТ АВТОРСКОЙ ПОЗЫ ──
	-- Турель, поставленная в РЕДАКТОРЕ, лежит в Workspace без якорей и стыков
	-- (шаблон рассчитан на CanonSystem, который варит при постановке). Физика
	-- стартует раньше, чем загрузятся скрипты, и детали успевают ОСЫПАТЬСЯ.
	-- Если после этого построить шарниры по текущим позициям, C0 навсегда
	-- запомнит осевшую позу — турель стоит «развалившейся» с самого старта.
	-- Поэтому: замораживаем детали и возвращаем их взаимное расположение из
	-- шаблона в ReplicatedStorage (клоны сохраняют порядок GetDescendants).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	local template = ReplicatedStorage:FindFirstChild(model.Name)
	local tMain = template and template:FindFirstChild("main", true)
	if not (tMain and tMain:IsA("BasePart")) then
		warn(("[Turret] %s: шаблон в ReplicatedStorage не найден или без main (template=%s) — позу не восстановить")
			:format(model.Name, template and template.ClassName or "nil"))
	end
	if tMain and tMain:IsA("BasePart") then
		local tParts, mParts = {}, {}
		for _, d in ipairs(template:GetDescendants()) do
			if d:IsA("BasePart") then tParts[#tParts + 1] = d end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then mParts[#mParts + 1] = d end
		end
		-- База — main: это нижняя опора, при осыпании она падает вертикально
		-- на палубу и почти не уезжает, остальное строим от неё по шаблону.
		local baseCF = main.CFrame
		local fixed = 0
		if #tParts == #mParts then
			-- клоны сохраняют порядок GetDescendants → восстанавливаем попарно
			for i, mp in ipairs(mParts) do
				local tp = tParts[i]
				if tp.Name == mp.Name and mp ~= main then
					mp.CFrame = baseCF * tMain.CFrame:Inverse() * tp.CFrame
					fixed += 1
				end
			end
			print(("[Turret] %s: поза восстановлена из шаблона (%d деталей)"):format(model.Name, fixed))
		else
			-- модель разошлась с шаблоном → восстанавливаем хотя бы детали с
			-- УНИКАЛЬНЫМИ именами (Pushka, bullet_N, стул, сиденье — ключевой скелет)
			local tByName, dup = {}, {}
			for _, tp in ipairs(tParts) do
				if tByName[tp.Name] then dup[tp.Name] = true else tByName[tp.Name] = tp end
			end
			for _, mp in ipairs(mParts) do
				local tp = tByName[mp.Name]
				if tp and not dup[mp.Name] and mp ~= main then
					mp.CFrame = baseCF * tMain.CFrame:Inverse() * tp.CFrame
					fixed += 1
				end
			end
			warn(("[Turret] %s: шаблон не совпал по числу деталей (%d vs %d) — восстановил %d уникальных по имени")
				:format(model.Name, #tParts, #mParts, fixed))
		end
	end

	-- Всю пересборку — в pcall с FALLBACK: если что-то сломается посреди рерига, СВАРИВАЕМ
	-- все части к плоту, чтобы турель НИКОГДА не рассыпалась (clearJoints уже снял стыки).
	local motor, spinMotor, spinBase
	local ok, err = pcall(function()
	-- ── сборка: чистим все стыки, строим заново ──
	clearJoints(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true -- не мешаем физике плота (как placeable-пушки)
			-- КРИТИЧНО (как у пушек, CannonControl): Motor6D двигает БОЛЕЕ ЛЁГКУЮ сторону
			-- шарнира. Без низкого RootPriority турель становится корнем сборки — тогда
			-- поворот крутил бы ПЛОТ, а силы BoatMovement (приложенные к raft.PrimaryPart)
			-- перестают его двигать → плот стоит на месте. -127 = плот всегда корень.
			d.RootPriority = -127
			-- вода не должна давить на турель: вертикальное удержание плота построено на
			-- ТОЧНОЙ компенсации гравитации (у корпуса и ящиков дайвера — так же)
			pcall(function() d.EnableFluidForces = false end)
		end
	end
	-- main → плот (едет, не вращается)
	local wMain = Instance.new("WeldConstraint")
	wMain.Part0, wMain.Part1 = rpp, main
	wMain.Parent = main

	-- ДВА уровня движения:
	--   carrier (Corpus + стул + сиденье) — поворот/наклон, БЕЗ проворота (иначе игрока катало бы);
	--   Pushka + стволы — ещё и ПРОВОРОТ вокруг собственного pivot (Гатлинг);
	--   main — неподвижен.
	local isSpin = { [pushka] = true }
	for _, b in ipairs(bullets) do isSpin[b] = true end

	local carrier = model:FindFirstChild("Corpus", true)
	if not (carrier and carrier:IsA("BasePart")) or carrier == main or isSpin[carrier] then
		carrier = nil
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= main and not isSpin[d] then carrier = d break end
		end
	end

	-- Исходные позы снимаем ДО создания шарниров: Motor6D, попав в игру, сразу тянет Part1
	-- к Part0*C0 — если парентить с ещё не выставленным C0 (identity), Pushka скакнёт в
	-- систему координат carrier (тот самый уход на 90°). Считаем всё от этих снимков.
	local mainCF0    = main.CFrame
	local pushkaCF0  = pushka.CFrame
	local carrierCF0 = carrier and carrier.CFrame or nil

	motor = Instance.new("Motor6D") -- поворот+наклон (внешняя переменная — переживёт pcall)
	motor.Name = "TurretYaw"
	motor.Part0 = main
	motor.C1 = CFrame.new()

	if carrier then
		-- корпус/стул/сиденье — жёстко к carrier (крутятся только по yaw/наклону)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= main and d ~= carrier and not isSpin[d] then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = carrier, d
				w.Parent = carrier
			end
		end
		-- стволы — жёстко к Pushka (проворачиваются вместе с ней)
		for _, b in ipairs(bullets) do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = pushka, b
			w.Parent = pushka
		end
		-- сначала ПОЛНОСТЬЮ настраиваем шарнир (C0 от снимков), и только потом парентим
		motor.Part1 = carrier
		motor.C0 = mainCF0:Inverse() * carrierCF0
		motor.Parent = main

		spinBase = carrierCF0:Inverse() * pushkaCF0 -- поза Pushka в покое
		spinMotor = Instance.new("Motor6D")         -- ПРОВОРОТ: carrier → Pushka
		spinMotor.Name = "GatlingSpin"
		spinMotor.Part0 = carrier
		spinMotor.Part1 = pushka
		spinMotor.C0 = spinBase
		spinMotor.C1 = CFrame.new()
		spinMotor.Parent = carrier -- парентим ПОСЛЕДНИМ, C0 уже верный
	else
		-- отдельного корпуса нет: всё на Pushka, проворота не будет (некому оставаться на месте)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= pushka and d ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = pushka, d
				w.Parent = pushka
			end
		end
		motor.Part1 = pushka
		motor.C0 = mainCF0:Inverse() * pushkaCF0
		motor.Parent = main
		warn("[Turret] " .. model:GetFullName() .. ": нет Corpus — проворот стволов отключён")
	end
	end) -- конец pcall пересборки

	-- FALLBACK: если пересборка упала (или мотор не создался) — не оставляем детали висеть
	-- без стыков (это и есть «турель развалилась»). Свариваем ВСЁ жёстко к плоту и выходим.
	if not ok or not motor then
		warn("[Turret] сборка не удалась: " .. tostring(err) .. " — свариваю всё к плоту (fallback)")
		-- weldAllToRaft сам снимает полусозданные Motor6D (иначе жёсткий велд поверх
		-- живого мотора = переопределённая связь) и ставит Massless/RootPriority
		weldAllToRaft(model, rpp)
		return
	end

	local state = {
		model = model, pushka = pushka, main = main, seat = seat, bullets = bullets,
		motor = motor, C0base = motor.C0,
		spinMotor = spinMotor, spinBase = spinBase,
		yaw = 0, yawInput = 0, pitch = 0, pitchInput = 0,
		spin = 0, spinTarget = 0, -- проворот стволов: цель растёт на 60° за выстрел
		dmgMult = model:GetAttribute("DmgMult") or TURRET_DMG[model.Name] or DEFAULT_DMG_MULT,
		sfx = model:GetAttribute("FireSound") or TURRET_SFX[model.Name] or DEFAULT_SFX,
		cooldown = model:GetAttribute("FireCooldown") or TURRET_COOLDOWN[model.Name] or FIRE_COOLDOWN,
		nextBarrel = 1, lastFire = 0, gunner = nil,
	}
	model:SetAttribute("FireCooldown", state.cooldown) -- клиент читает отсюда темп клика
	turrets[model] = state

	-- ── СТОРОЖ РАЗВАЛА: ловим, КОГДА детали разъезжаются ПОСЛЕ успешной сборки ──
	-- Сборка заканчивается «готов», но что-то позже убивает стыки (это и есть тот
	-- самый «развалился» — детали россыпью). Сторож раз в 2с сверяет расстояние
	-- каждой детали до main: при повороте турели расстояния НЕ меняются (вращение
	-- вокруг main), а при развале — меняются. Поймал → печатает виновную деталь
	-- (по этой строке видно, в какой момент и после чего умерли стыки) и чинит:
	-- возвращает позу сборки и полностью пересобирает турель.
	do
		local rel = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= main then
				rel[d] = main.CFrame:ToObjectSpace(d.CFrame)
			end
		end
		local myState = state
		task.spawn(function()
			while model.Parent and main.Parent do
				task.wait(2)
				if turrets[model] ~= myState then break end -- турель пересобрали → сторож устарел
				local worstDrift, worstPart = 0, nil
				for d, r in pairs(rel) do
					if d.Parent then
						local cur = main.CFrame:ToObjectSpace(d.CFrame).Position.Magnitude
						local drift = math.abs(cur - r.Position.Magnitude)
						if drift > worstDrift then worstDrift, worstPart = drift, d end
					end
				end
				if worstDrift > 4 and worstPart then
					warn(("[Turret] %s РАЗВАЛИЛАСЬ после сборки: %s уехал на %.1f стадов — чиню и пересобираю")
						:format(model.Name, worstPart.Name, worstDrift))
					-- замораживаем, возвращаем позу сборки, пересобираем с нуля
					for d in pairs(rel) do
						if d.Parent then d.Anchored = true end
					end
					main.Anchored = true
					for d, r in pairs(rel) do
						if d.Parent then d.CFrame = main.CFrame * r end
					end
					if myState.gunner then gunnerOf[myState.gunner] = nil end
					turrets[model] = nil
					setupDone[model] = nil
					setupAttempts[model] = nil
					setup(model)
					break
				end
			end
		end)
	end

	-- ── посадка: ProximityPrompt на сиденье ──
	local prompt = seat:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Сесть за пулемёт"
		prompt.ObjectText = "Пулемёт"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
	end
	prompt.Triggered:Connect(function(player)
		if state.gunner then return end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then pcall(function() seat:Sit(hum) end) end
	end)

	-- ── занятость сиденья → наводчик ──
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local plr = occ and Players:GetPlayerFromCharacter(occ.Parent)
		if plr then
			state.gunner = plr
			gunnerOf[plr] = state
			prompt.Enabled = false
			rEnter:FireClient(plr, model, SIT_ANIM)
		else
			local prev = state.gunner
			state.gunner = nil
			state.yawInput = 0
			prompt.Enabled = true
			if prev then
				gunnerOf[prev] = nil
				rExit:FireClient(prev)
			end
		end
	end)

	print("[Turret] готов: " .. model:GetFullName() .. (" (стволов: %d)"):format(#bullets))
end

-- ── ввод: поворот (yawDir) + наклон (pitchDir) ──
rInput.OnServerEvent:Connect(function(player, yawDir, pitchDir)
	local state = gunnerOf[player]
	if not state then return end
	state.yawInput   = math.clamp(tonumber(yawDir) or 0, -1, 1)
	state.pitchInput = math.clamp(tonumber(pitchDir) or 0, -1, 1)
end)

-- ── выстрел ──
rFire.OnServerEvent:Connect(function(player)
	local state = gunnerOf[player]
	if not state then return end
	local now = os.clock()
	if now - state.lastFire < (state.cooldown or FIRE_COOLDOWN) then return end
	state.lastFire = now

	local barrel = state.bullets[state.nextBarrel]
	state.nextBarrel = (state.nextBarrel % #state.bullets) + 1
	if not (barrel and barrel.Parent) then return end

	-- ГАТЛИНГ: каждый выстрел проворачивает блок стволов на 60° (Heartbeat доводит плавно,
	-- успевая ровно за темп стрельбы) — следующий ствол встаёт на место отстрелявшего
	local flip = state.model:GetAttribute("SpinFlip") and -1 or 1
	local per = math.rad(state.model:GetAttribute("SpinPerShotDeg") or DEFAULT_SPIN_SHOT)
	state.spinTarget = state.spinTarget + per * flip

	local dir = fireDir(state.model, state.pushka)
	local speed = state.model:GetAttribute("BulletSpeed") or DEFAULT_SPEED
	local muzzle = barrel.Position + dir * (barrel.Size.Magnitude * 0.5 + 0.5)

	local shell = barrel:Clone()
	shell.Name = "Bullet_Cannon" -- ShipCombat ловит по имени
	shell:ClearAllChildren()
	shell.Transparency = 0 -- прозрачный ствол → ВИДИМЫЙ снаряд
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = true
	shell.Anchored = false
	shell.Massless = false
	shell.CFrame = CFrame.lookAt(muzzle, muzzle + dir)

	-- ТРАССЕР (как у Cannon): яркий Trail за снарядом, чтобы было видно, куда летят патроны.
	-- Аттачменты разведены по ЛОКАЛЬНОЙ оси X (RightVector) — она перпендикулярна полёту при
	-- любом наклоне ствола, так лента всегда с шириной; длина следа = Lifetime × скорость.
	local a0 = Instance.new("Attachment"); a0.Name = "T0"; a0.Position = Vector3.new(0.09, 0, 0); a0.Parent = shell
	local a1 = Instance.new("Attachment"); a1.Name = "T1"; a1.Position = Vector3.new(-0.09, 0, 0); a1.Parent = shell
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Lifetime = 0.12 -- короткий хвост: длина следа = Lifetime × скорость снаряда
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 232, 150), Color3.fromRGB(255, 150, 40))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = shell

	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"; creator.Value = player; creator.Parent = shell
	-- прокачка турели, купленная в лобби (WUpg_<id>): +15% урона за уровень
	local upStars = UpgradeConfig.starsOf(player, state.model.Name)
	shell:SetAttribute("DmgMult", state.dmgMult * UpgradeConfig.multFor(upStars))
	shell:SetAttribute("NoExplode", true)
	-- Скорость — ДО парента: иначе первый реплицированный кадр летит с нулевой
	-- скоростью и снаряд «вылетает с лагом», рывком догоняя настоящую траекторию.
	shell.AssemblyLinearVelocity = dir * speed -- гравитация даёт баллистику сама
	shell.Parent = workspace
	-- Симуляцию пули отдаём СТРЕЛКУ: его клиент ведёт её локально на 60 fps вместо
	-- серверной репликации ~20 Гц — полёт плавный. Он же применяет затухание
	-- скорости (TurretClient, BULLET_DRAG) — тем же коэффициентом, что и маркер.
	pcall(function() shell:SetNetworkOwner(player) end)
	Debris:AddItem(shell, 6)

	CombatSounds.play(state.sfx, muzzle) -- звук своей модели, из дула (3D, с разбросом питча)
end)

-- ── поворот+наклон сборки (только когда есть ввод; Motor6D сам едет с плотом) ──
-- C0 = Yaw(вокруг оси main, у его центра) * C0base * Pitch(вокруг оси Pushka, у её центра).
-- Наклон крутит Pushka.CFrame → стрельба/камера/траектория (все берут Pushka) подхватят угол.
RunService.Heartbeat:Connect(function(dt)
	for model, state in pairs(turrets) do
		-- турель могли подобрать/удалить → выкидываем из учёта, чтобы не дёргать мёртвый Motor6D
		if not model.Parent or not state.motor.Parent then
			if state.gunner then gunnerOf[state.gunner] = nil end
			turrets[model] = nil
		else
		local m = state.model
		local changed = false

		if state.gunner and (state.yawInput ~= 0 or state.pitchInput ~= 0) then
			local ysp = math.rad(m:GetAttribute("YawSpeedDeg") or DEFAULT_YAW)
			local psp = math.rad(m:GetAttribute("PitchSpeedDeg") or DEFAULT_PITCH_SPEED)
			local plim = math.rad(m:GetAttribute("PitchLimitDeg") or DEFAULT_PITCH_LIMIT)
			local pflip = m:GetAttribute("PitchFlip") and -1 or 1
			state.yaw = state.yaw - state.yawInput * ysp * dt -- знак инвертирован: A/D были зеркальны
			state.pitch = math.clamp(state.pitch + state.pitchInput * pflip * psp * dt, -plim, plim)
			changed = true
		end

		-- ПРОВОРОТ СТВОЛОВ: догоняем цель со скоростью «60° за один интервал стрельбы» —
		-- при очереди блок крутится непрерывно, на последнем выстреле доводит шаг и встаёт
		if state.spin ~= state.spinTarget then
			local per = math.rad(m:GetAttribute("SpinPerShotDeg") or DEFAULT_SPIN_SHOT)
			-- скорость проворота привязана к СВОЕМУ темпу: медленный пулемёт крутит
			-- блок стволов медленнее, доводя ровно к следующему выстрелу
			local rate = per / (state.cooldown or FIRE_COOLDOWN)
			local d = state.spinTarget - state.spin
			state.spin = state.spin + math.sign(d) * math.min(math.abs(d), rate * dt)
			changed = true
		elseif math.abs(state.spin) > math.pi * 4 then
			-- не копим угол бесконечно (точность float): сбрасываем целый оборот
			local w = math.floor(state.spin / (math.pi * 2)) * math.pi * 2
			state.spin, state.spinTarget = state.spin - w, state.spinTarget - w
		end

		if changed then applyMotor(state) end
	end
	end
end)

-- ⚠️ ТУЛ В РУКАХ — НЕ ТУРЕЛЬ, ХОТЯ ЗОВЁТСЯ ТАК ЖЕ.
-- Инструмент постановки называется ровно как модель — «Pulemet_lvl_1», — и когда
-- игрок берёт его в руки, он оказывается ВНУТРИ персонажа, то есть в Workspace. По
-- одному имени мы хватали именно его: сборка не находила ни Pushka, ни Seat, пять
-- раз повторяла, а между попытками звала weldAllToRaft — и приваривала К ПЛОТУ тул,
-- который держит персонаж. Игрок оказывался пришпилен и не мог сойти с места.
-- Именно это выглядело как «поставил пулемёт — не могу ходить».
-- Поэтому берём только то, что действительно СТОИТ в мире: не Tool и не внутри
-- чьего-то персонажа.
local function isPlacedTurret(d)
	if not (d:IsA("Model") and d.Name:sub(1, #TURRET_PREFIX) == TURRET_PREFIX) then
		return false
	end
	if d:IsA("Tool") then return false end
	local node = d
	while node and node ~= workspace do
		if node:IsA("Tool") then return false end
		if Players:GetPlayerFromCharacter(node) then return false end
		node = node.Parent
	end
	return true
end

-- ── поиск турелей ──
for _, d in ipairs(workspace:GetDescendants()) do
	if isPlacedTurret(d) then setup(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if isPlacedTurret(d) then task.defer(setup, d) end
end)

Players.PlayerRemoving:Connect(function(plr) gunnerOf[plr] = nil end)

print("[TurretSystem] loaded")
