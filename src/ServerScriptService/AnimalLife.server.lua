--[[
	ЖИЗНЬ ЖИВОТНЫХ ЛАГЕРЯ: корова и куры (НОВЫЕ Motor6D-риги «Cow» / «Chicken»).

	Поведение по ТЗ острова:
	  • КОРОВА пасётся в радиусе выпаса: чередует Eat и переход Walk к новой точке,
	    между ними Idle. Игрок близко — испуг (ShockRun) и, если не отошёл, галоп прочь.
	  • КУРЫ клюют часто и коротко, перебегают. Игрок близко — подпрыг (Jump),
	    затем панический бег (Panic) в сторону.

	⚠️ ДВИЖЕНИЕ — CFrame'ом якорного HumanoidRootPart, а не Humanoid'ом: зверя
	ведёт код, конечности держит Motor6D. Сервер ставит только АБСТРАКТНОЕ имя
	состояния в атрибуты (Clip = Idle/Walk/Run/Eat, ClipOnce = React + ClipOnceT):
	в конкретный клип рига его переводит КЛИЕНТ (PirateIslandAnim → карта clips в
	Defs.ANIMAL_LIFE), потому что Motor6D.Transform с сервера не реплицируется.

	Высота берётся лучом по грунту каждый шаг: остров не плоский, и животное,
	идущее по прямой, иначе уходило бы в склон.

	СМЕРТЬ. Клипа смерти у ригов нет — тушку укладывает сервер: корень плавно
	заваливается набок (клиент к этому моменту снял анимацию), рядом высыпаются
	дропы из Defs (окорочок и перья с курицы, шкура с коровы), труп исчезает
	через минуту.
]]

local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))
local ResourceNamesRu = require(ReplicatedStorage:WaitForChild("ResourceNamesRu"))

local TURN_RATE  = 3.5    -- радиан в секунду: разворот не мгновенный
local DEATH_TIP  = 0.45   -- за сколько секунд туша заваливается набок
local CORPSE_TTL = 60     -- сколько лежит труп
local DROP_TTL   = 300    -- сколько живёт несобранный дроп

-- ── анимации: только имена состояний ──
local function loop(model, name)
	if model:GetAttribute("Clip") ~= name then
		model:SetAttribute("Clip", name)
	end
end

-- Разовая реакция на игрока (у коровы ShockRun, у курицы Jump). Возвращает
-- длину клипа из конфига — на неё встаёт таймер состояния.
local function react(model, life)
	model:SetAttribute("ClipOnce", "React")
	model:SetAttribute("ClipOnceT", workspace:GetServerTimeNow())
	return life.reactLen or 1.2
end

-- ── мир ──
-- ⚠️ ЗЕМЛЯ — ТОЛЬКО ПО ТАЙЛАМ РЕЛЬЕФА (Island_terrain_* / Island_seabed).
-- Фильтр по CanCollide не помог: трава на острове КОЛЛИДНАЯ, и луч честно вставал
-- на неё, а корова — на траву. Единственный надёжный признак «это земля» здесь —
-- имя тайла, поэтому луч пускаем ТОЛЬКО по ним; трава, пальмы и постройки для
-- него не существуют.
local terrainCache = setmetatable({}, { __mode = "k" })

local function terrainParts(island)
	local list = terrainCache[island]
	if list then return list end
	list = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name:lower()
			if n:find("island_terrain", 1, true) or n:find("island_seabed", 1, true) then
				table.insert(list, d)
			end
		end
	end
	terrainCache[island] = list
	return list
end

local function groundY(pos, model, island)
	local params = RaycastParams.new()
	params.IgnoreWater = true
	local terrain = island and terrainParts(island)
	if terrain and #terrain > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = terrain
	else
		-- рельеф по именам не нашёлся (другой остров?) — старый путь с запасом
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true
	end
	local hit = Workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or nil
end

-- Низ модели по мировым осям (запасной путь, если атрибут FootOffset со спавна
-- не доехал): GetBoundingBox ориентирован по пивоту и у вытянутого зверя врёт.
local function worldBottomY(model)
	local bottom
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local half = 0.5 * (math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z)
			local b = cf.Position.Y - half
			if not bottom or b < bottom then bottom = b end
		end
	end
	return bottom
end

-- ⚠️ СТЕНЫ — ОТДЕЛЬНЫМ ГОРИЗОНТАЛЬНЫМ ЛУЧОМ. Луч земли видит только рельеф, и
-- вместе с высотой пропала бы и преграда: курица шла сквозь палатки и бочки.
-- Перед каждым шагом смотрим по курсу: впереди что-то коллидное и не
-- декоративное (не трава) — шаг не делается, животное выбирает новую точку.
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Exclude
blockParams.IgnoreWater = true
blockParams.RespectCanCollide = true   -- неколлидное не преграда по определению

local function isDecor(part)
	local n = part.Name:lower()
	return n:find("plants", 1, true) ~= nil
		or n:find("grass", 1, true) ~= nil
		or n:find("island_terrain", 1, true) ~= nil
		or n:find("island_seabed", 1, true) ~= nil
end

local function rayBlocked(model, from, dir, len)
	blockParams.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(from, dir * len, blockParams)
	if not hit then return false end
	if isDecor(hit.Instance) then return false end
	local m = hit.Instance:FindFirstAncestorWhichIsA("Model")
	if m and Players:GetPlayerFromCharacter(m) then return false end   -- игрок не стена
	return true
end

local function blockedAhead(model, primary, dir, dist)
	-- Старт — ОТ НОСА, а не от центра: тело длинное, и луч из центра стартовал
	-- уже ПОЗАДИ препятствия, когда морда в него воткнулась. И на ДВУХ высотах —
	-- корпус и голень: низкие ящики проходили ПОД лучом на уровне корпуса,
	-- поэтому зверь и шёл сквозь них.
	local halfLen = math.max(primary.Size.X, primary.Size.Z) * 0.5
	local origin = primary.Position + dir * halfLen
	local foot = model:GetAttribute("FootOffset") or (primary.Size.Y * 0.5)
	local shinY = primary.Position.Y - foot + 0.35
	local len = dist + 0.8
	return rayBlocked(model, origin, dir, len)
		or rayBlocked(model, Vector3.new(origin.X, shinY, origin.Z), dir, len)
end

local function nearestPlayer(pos, maxDist)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < (bestD or maxDist) then best, bestD = hrp, d end
		end
	end
	return best, bestD
end

-- ── дропы с туши ──
-- Названия шаблонов задал автор ассетов: Chicken_drumstick, Chicken_feather,
-- Cow_Hide — MeshPart'ы на общем атласе, лежат в ReplicatedStorage. Подбор —
-- ProximityPrompt, предмет уходит в инвентарь через _G.AddResourceToInventory.
local warnedDrop = {}

local function spawnDrops(model, life, island)
	if not life.drops then return end
	local origin = (model.PrimaryPart and model.PrimaryPart.Position) or model:GetPivot().Position
	--[[ ⚠️ СГОРЕЛА ОТ ОГНЕМЁТА — МЯСО ПАДАЕТ УЖЕ ЖАРЕНЫМ.
	     Флаг KilledByFire ставит FlamethrowerSystem в момент смертельного урона
	     огнём. Сырое мясо коровы и окорочок курицы при этом оборачиваются
	     «Meat_Cooked»: шаблон жареного, если он есть, иначе шаблон сырого с
	     жареным видом (_G.SetFoodVisualCooked). Шкура и перья не горят. ]]
	local byFire = model:GetAttribute("KilledByFire") == true
	if byFire then print(("[Живность] %s сгорела — мясо жареное"):format(model.Name)) end

	for rawName, count in pairs(life.drops) do
		local itemName, tplName = rawName, rawName
		if byFire and (rawName == "Meat" or rawName == "Chicken_drumstick") then
			itemName = "Meat_Cooked"
			tplName = ReplicatedStorage:FindFirstChild("Meat_Cooked", true) and "Meat_Cooked" or "Meat"
		end
		local tpl = ReplicatedStorage:FindFirstChild(tplName, true)
		if not tpl then
			if not warnedDrop[itemName] then
				warnedDrop[itemName] = true
				warn(("[Живность] дропа «%s» нет в ReplicatedStorage — с туши ничего не упало"):format(itemName))
			end
			continue
		end
		for i = 1, count do
			local drop = tpl:Clone()
			local prim = drop:IsA("BasePart") and drop
				or drop.PrimaryPart or drop:FindFirstChildWhichIsA("BasePart", true)
			if not prim then
				drop:Destroy()
				continue
			end

			-- разбросать вокруг туши и посадить на грунт
			local a = math.random() * math.pi * 2
			local r = 1.2 + math.random() * 1.8
			local pos = origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local gy = groundY(pos, model, island)
			local lift = prim.Size.Y * 0.5 + 0.05
			local cf = CFrame.new(pos.X, (gy or pos.Y) + lift, pos.Z)
				* CFrame.Angles(0, math.random() * math.pi * 2, 0)

			for _, d in ipairs(drop:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
				end
			end
			if drop:IsA("BasePart") then
				drop.Anchored = true
				drop.CanCollide = false
				drop.CFrame = cf
			else
				drop:PivotTo(cf)
			end
			if itemName == "Meat_Cooked" then
				drop.Name = "Meat_Cooked"
				drop:SetAttribute("Cooked", true)
				drop:SetAttribute("ResourceType", "Meat_Cooked")
				if typeof(_G.SetFoodVisualCooked) == "function" then pcall(_G.SetFoodVisualCooked, drop, true) end
			end

			-- ⚠️ ДРОП СВЕТИТСЯ, А НЕ ЛЕЖИТ СЕРЫМ КАМНЕМ В ТРАВЕ.
			-- Кусок мяса размером с ладонь падает на глину рядом с тушей и в этой
			-- траве попросту теряется: игрок отходит, не поняв, что с коровы
			-- вообще что-то упало. Контур сквозь стены (AlwaysOnTop) виден и
			-- издалека, и с обратной стороны валуна.
			local glow = Instance.new("Highlight")
			glow.Name = "DropGlow"
			glow.FillColor = Color3.fromRGB(255, 210, 58)
			glow.FillTransparency = 0.7
			glow.OutlineColor = Color3.fromRGB(255, 210, 58)
			glow.OutlineTransparency = 0
			glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			glow.Parent = drop

			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Подобрать"
			prompt.ObjectText = ResourceNamesRu[itemName] or itemName:gsub("_", " ")
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = prim
			prompt.Triggered:Connect(function(player)
				-- явный false от инвентаря (нет места) — предмет остаётся лежать
				local ok, res = pcall(function()
					return _G.AddResourceToInventory(player, itemName, 1)
				end)
				if ok and res ~= false then
					-- ⚠️ КВЕСТУ СООБЩАЕМ ИМЕННО ЗДЕСЬ.
					-- _G.AddResourceToInventory сам событий не шлёт — их шлёт
					-- каждый добытчик отдельно. Без этой строки цель «подбери
					-- мясо» не двигалась бы вовсе, сколько ни собирай с туш.
					if typeof(_G.OnQuestResource) == "function" then
						pcall(_G.OnQuestResource, player, itemName, 1)
					end
					drop:Destroy()
				end
			end)

			drop.Parent = island
			Debris:AddItem(drop, DROP_TTL)
		end
	end
end

-- ── состояние ──
local state = setmetatable({}, { __mode = "k" })   -- [model] = {…}

local function home(model)
	return Vector3.new(model:GetAttribute("HomeX") or 0, 0, model:GetAttribute("HomeZ") or 0)
end

local function pickGrazePoint(model)
	local r = model:GetAttribute("GrazeRadius") or 15
	local a = math.random() * math.pi * 2
	local d = math.sqrt(math.random()) * r      -- равномерно по кругу, а не к центру
	local h = home(model)
	return Vector3.new(h.X + math.cos(a) * d, 0, h.Z + math.sin(a) * d)
end

local function step(model, dt, island)
	local kind = model:GetAttribute("AnimalRig")
	local life = kind and Defs.ANIMAL_LIFE[kind]
	if not life then return end

	local st = state[model]
	if not st then
		st = { mode = "idle", timer = 0 }
		state[model] = st
	end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then return end
	local pos = primary.Position
	local pos0 = pos   -- откуда шагали в этом кадре: сюда откатываемся у препятствий

	-- СМЕРТЬ: сервер снимает клипы, заваливает тушу набок и сыплет дропы.
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.Health <= 0 then
		if not st.dead then
			st.dead = true
			model:SetAttribute("Clip", nil)
			model:SetAttribute("ClipOnce", nil)

			-- труп — не преграда: живого зверя держит коллидная коробка корня,
			-- но спотыкаться о лежащую тушу игрок не должен
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.CanCollide = false end
			end

			-- лечь на бок: поворот вокруг оси взгляда, высота — по полуширине
			-- торса, чтобы бок оказался на земле, а не в ней
			local torso = model:FindFirstChild("Torso", true)
				or model:FindFirstChild("chicken_torso", true) or primary
			local halfW = (torso.Size.X * 0.5)
			local gy = groundY(pos, model, island)
			local baseY = gy or (pos.Y - (model:GetAttribute("FootOffset") or 0))
			local side = (math.random(2) == 1) and 1 or -1
			st.deathT = 0
			st.deathCF0 = primary.CFrame
			st.deathCF1 = CFrame.new(pos.X, baseY + halfW + 0.1, pos.Z)
				* st.deathCF0.Rotation * CFrame.Angles(0, 0, math.pi / 2 * side)

			spawnDrops(model, life, island)
			Debris:AddItem(model, CORPSE_TTL)
		end
		if st.deathT and st.deathT <= DEATH_TIP then
			st.deathT += dt
			local a = math.clamp(st.deathT / DEATH_TIP, 0, 1)
			primary.CFrame = st.deathCF0:Lerp(st.deathCF1, a * a * (3 - 2 * a))
		end
		return
	end

	-- ИСПУГ важнее любого текущего занятия (но не перебивает атаку и бегство)
	local threat = nearestPlayer(pos, life.scare)
	if threat and st.mode ~= "flee" and st.mode ~= "react" and st.mode ~= "charge" then
		st.mode, st.timer = "react", react(model, life)
		st.threat = threat
	end

	st.timer -= dt

	if st.mode == "react" then
		-- стоим лицом к игроку, пока играет реакция
		if st.threat and st.threat.Parent then
			local to = st.threat.Position - pos
			st.face = Vector3.new(to.X, 0, to.Z)
		end
		if st.timer <= 0 then
			-- не отошёл: трус убегает, корова идёт в атаку; отошёл — все по делам
			local still = st.threat and st.threat.Parent
				and (st.threat.Position - pos).Magnitude < life.scare * 1.4
			if still and life.charge then
				st.mode, st.timer = "charge", life.chargeTime or 6
			elseif still then
				local away = pos - st.threat.Position
				away = Vector3.new(away.X, 0, away.Z)
				away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(1, 0, 0)
				st.goal = pos + away * life.flee
				st.mode, st.timer = "flee", 4
			else
				st.mode, st.timer = "idle", math.random() * life.idleMax
			end
		end

	elseif st.mode == "charge" then
		-- РАЗГОН В ИГРОКА: галоп прямо на него; догнала — рывок ShockRun читается
		-- как удар рогами, урон и короткий отдых перед новым заходом
		loop(model, "Run")
		local target = st.threat
		if not (target and target.Parent) or st.timer <= 0 then
			st.mode, st.timer = "idle", 1.5
		else
			local to = target.Position - pos
			to = Vector3.new(to.X, 0, to.Z)
			local d = to.Magnitude
			local speed = life.chargeSpeed or life.runSpeed
			if d <= (life.hitRange or 3) then
				react(model, life)   -- рывок = боднула
				local thum = target.Parent:FindFirstChildWhichIsA("Humanoid")
				if thum and thum.Health > 0 then
					thum:TakeDamage(life.hitDamage or 10)
				end
				st.face = to
				st.mode, st.timer = "idle", 2.5   -- отдышаться
			elseif d > life.scare * 4 then
				st.mode, st.timer = "idle", 1     -- игрок сбежал далеко — остыла
			elseif blockedAhead(model, primary, to.Unit, speed * dt) then
				st.mode, st.timer = "idle", 0.5   -- упёрлась — атака сорвалась
			else
				st.face = to
				pos = pos + to.Unit * speed * dt
			end
		end

	elseif st.mode == "flee" then
		loop(model, "Run")
		local to = st.goal and (st.goal - pos) or Vector3.zero
		to = Vector3.new(to.X, 0, to.Z)
		if to.Magnitude < 2 or st.timer <= 0 then
			st.mode, st.timer = "idle", math.random() * life.idleMax
		elseif blockedAhead(model, primary, to.Unit, life.runSpeed * dt) then
			st.mode, st.timer = "idle", 0.3   -- упёрся в стену — бег окончен
		else
			st.face = to
			pos = pos + to.Unit * life.runSpeed * dt
		end

	elseif st.mode == "walk" then
		loop(model, "Walk")
		local to = st.goal and (st.goal - pos) or Vector3.zero
		to = Vector3.new(to.X, 0, to.Z)
		if to.Magnitude < 1.5 then
			st.mode = "eat"
			st.timer = life.eatMin + math.random() * (life.eatMax - life.eatMin)
		elseif blockedAhead(model, primary, to.Unit, life.walkSpeed * dt) then
			st.goal, st.mode, st.timer = nil, "idle", 0.4   -- препятствие — новая точка
		else
			st.face = to
			pos = pos + to.Unit * life.walkSpeed * dt
		end

	elseif st.mode == "eat" then
		loop(model, "Eat")
		if st.timer <= 0 then
			st.mode, st.timer = "idle", life.idleMin + math.random() * (life.idleMax - life.idleMin)
		end

	else -- idle
		loop(model, "Idle")
		if st.timer <= 0 then
			st.goal = pickGrazePoint(model)
			st.mode = "walk"
		end
	end

	-- Разворот плавный, а не рывком. st.yaw — это курс НОСА; ось «вперёд» у
	-- корня после импорта бывает развёрнута (у коровы LookVector смотрел в
	-- хвост, и она ходила задом) — расхождение спавнер записал в YawFlip, здесь
	-- оно довинчивается при выставлении CFrame.
	local flip = model:GetAttribute("YawFlip") or 0
	if not st.yaw then
		local lv = primary.CFrame.LookVector
		st.yaw = math.atan2(-lv.X, -lv.Z) - flip
	end
	if st.face and st.face.Magnitude > 0.05 then
		local wantYaw = math.atan2(-st.face.X, -st.face.Z)
		local dy = math.atan2(math.sin(wantYaw - st.yaw), math.cos(wantYaw - st.yaw))
		local maxTurn = TURN_RATE * dt
		st.yaw += math.clamp(dy, -maxTurn, maxTurn)
	end

	-- Высота — ноги на грунт каждый шаг. Отступ «корень → копыта» посчитан при
	-- спавне в авторской позе (атрибут FootOffset) и при рыскании не меняется.
	-- ⚠️ В ГОРУ ВЫШЕ СТУПЕНЬКИ НЕ ЛЕЗЕМ: резкий подъём впереди — это ствол
	-- пальмы или валун; у препятствия зверь остаётся на месте и разворачивается.
	local gy = groundY(pos, model, island)
	if gy then
		st.toBottom = st.toBottom or model:GetAttribute("FootOffset")
			or (pos0.Y - (worldBottomY(model) or pos0.Y))
		local newY = gy + st.toBottom
		if newY - pos0.Y > 3 then
			pos = pos0
			st.goal, st.mode, st.timer = nil, "idle", 0.4
		else
			pos = Vector3.new(pos.X, newY, pos.Z)
		end
	end

	primary.CFrame = CFrame.new(pos) * CFrame.Angles(0, st.yaw + flip, 0)
end

-- ── общий цикл ──
-- ⚠️ ДВИГАЕМ КАЖДЫЙ КАДР. Раньше шаг был раз в 0.1 с, и животное переставлялось
-- рывками по полстуда — со стороны это читалось как телепортация по кадрам, а не
-- ходьба. Решения (куда идти, испугаться ли) всё так же принимаются редко, дорогой
-- здесь только луч по грунту, и он один на животное.
--
-- Один поток на всех: животных четыре, и по корутине на каждое — это те же
-- вычисления плюс лишние переключения.
RunService.Heartbeat:Connect(function(dt)
	local step_dt = math.min(dt, 0.1)   -- на просадке кадра не отправляем в стену

	-- ⚠️ ЖИВНОСТЬ ИЩЕМ ПО ПАПКЕ, А НЕ ПО ИМЕНИ ОСТРОВА.
	-- Здесь стояла проверка island.Name == Defs.ISLAND_NAME, то есть жизнь была
	-- только у зверей пиратского лагеря. Корова стартового острова стояла бы
	-- статуей: не пасётся, не пугается, а главное — не падает и не роняет мясо,
	-- потому что смерть обрабатывается ровно в этом цикле. Папка Animals и есть
	-- признак: её заводит тот, кто ставит зверей.
	for _, island in ipairs(Workspace:GetChildren()) do
		if island:IsA("Model") then
			local folder = island:FindFirstChild("Animals")
			if folder then
				for _, animal in ipairs(folder:GetChildren()) do
					if animal:IsA("Model") then
						local ok, err = pcall(step, animal, step_dt, island)
						if not ok then warn("[Живность] " .. tostring(err)) end
					end
				end
			end
		end
	end
end)
