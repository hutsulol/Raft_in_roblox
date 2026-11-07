--[[
	SeagullAI.server.lua — чайки-вредители. Сервер ведёт птицу и НАЗЫВАЕТ клип,
	позу считает клиент (SeagullAnim.client): протокол атрибутов тот же, что у зверей —
	Clip (цикл, пишется только при смене имени) и ClipOnce + ClipOnceT (разовый, метка
	пишется каждый раз).

	Поведение:
	  * прилетает издалека, выбирает цель: если на плоту есть ПУГАЛО со свободным местом
	    (рука/рука/шляпа) — садится на него и клюёт его; иначе садится на ГРЯДКУ
	    (модель Raft_planter или атрибут IsPlanter, по возможности с посевом) и клюёт её;
	  * посидев, улетает сама;
	  * ударили (Humanoid потерял здоровье) — вскрик, взлёт, удирает;
	  * убили на насесте — валится замертво там, где стояла; убили в воздухе — падает камнем.

	Раскладка:
	  ReplicatedStorage/ Seagull (Model из Seagull.fbx), SeagullRig, SeagullRigData,
	                     SeagullClips, SeagullAnimator
	  ServerScriptService/ SeagullAI            StarterPlayerScripts/ SeagullAnim

	Крючки для игры (папка ReplicatedStorage.SeagullSignals, BindableEvent):
	  Pecked(target: Instance, gull: Model, total: number)  — каждый клевок. target — модель
	        грядки или модель пугала; total — сколько эта цель уже получила (атрибут GullPecks).
	        Порча урожая — на вашей стороне: PlanterService держит состояние грядки у себя.
	  Killed(gull: Model, killerUserId: number?)            — для дропа (перо, мясо).
	  _G.SpawnSeagull() — ручной спавн для теста.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SeagullRig = require(ReplicatedStorage:WaitForChild("SeagullRig"))
local Data = SeagullRig.Data

local CFG = {
	TEMPLATE = "Seagull",
	MAX_GULLS = 3,
	SPAWN_EVERY = { 25, 55 },   -- секунд между прилётами
	FIRST_SPAWN = 20,
	HEALTH = 60,                -- было 20: падала с одного удара (владелец)
	FLEE_HEALTH = 0.4,          -- улетает от удара, только когда здоровья осталось меньше этой доли
	-- добыча как у курицы (PirateIslandDefs.ANIMAL_LIFE.Chicken.drops)
	DROPS = { Chicken_drumstick = 1, Chicken_feather = 2 },
	-- ритм на грядке: клюёт → медленно поднимает голову и отдыхает → снова клюёт;
	-- изредка вместо отдыха медленно озирается (клип Idle на пониженной скорости)
	EAT_TIME = 10,              -- столько секунд КЛЕВАНИЯ — и посадка на грядке съедена, чайка улетает
	PECK_TIME = { 3.9, 6.5 },
	REST_TIME = { 4.5, 6.5 },
	LOOK_CHANCE = 0.3,
	LOOK_SPEED = 0.45,          -- скорость клипа Idle при озирании
	LOOK_TIME = 8.0,            -- = длина Idle (3.6) / LOOK_SPEED
	FLY_SPEED = 30,             -- студов/с
	FLEE_SPEED = 42,
	SPAWN_DIST = { 150, 210 },
	SPAWN_HEIGHT = { 35, 60 },
	GATE_BACK = 16,             -- «ворота» захода: столько студов не долетая до цели…
	GATE_UP = 9,                -- …и на столько выше неё
	LAND_TIME = 1.0,            -- = длина клипа Land
	TAKEOFF_TIME = 0.7,         -- = длина клипа TakeOff
	VISIT = { 30, 40 },         -- потолок визита; с грядки улетает раньше — как доест (EAT_TIME). Было 14–26: не успевала доесть         -- сколько сидит и клюёт
	PECK_PERIOD = 1.3,          -- = длина клипа Peck, в нём два клевка
	CORPSE_TIME = 25,
	SCARECROW_WEAR = 100,      -- секунд сидения чаек В СУММЕ — и пугало разваливается (владелец)
	-- горит (огнемёт, флаг OnFire от FlamethrowerSystem): мечется зигзагом,
	-- набирая высоту, быстрее обычного полёта; урон догорания — огнемёта
	PANIC_SPEED = 46,
	PANIC_TURN = 5.0,          -- рад/с: как резко меняет курс
	PANIC_CLIMB = 6,
	WATER_DROP = 10,            -- тушка исчезает, упав на столько ниже ПЛОТА (вода у нас на Y≈-384, а не у нуля)
}

local signals = ReplicatedStorage:FindFirstChild("SeagullSignals")
if not signals then
	signals = Instance.new("Folder")
	signals.Name = "SeagullSignals"
	signals.Parent = ReplicatedStorage
end
local function signal(name)
	local e = signals:FindFirstChild(name)
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = name
		e.Parent = signals
	end
	return e
end
local Pecked, Killed = signal("Pecked"), signal("Killed")

local folder = workspace:FindFirstChild("Seagulls")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Seagulls"
	folder.Parent = workspace
end

local gulls = {}
local taken = {} -- цель (Instance) → { [место] = gull }
local rng = Random.new()

-- ═════════════════════════════════════════════════ поиск
local function findTemplate()
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("Model") and string.lower(d.Name) == string.lower(CFG.TEMPLATE) then
			return d
		end
	end
	return nil
end

local function horizontal(v, up)
	local h = v - up * v:Dot(up)
	return (h.Magnitude > 1e-4) and h.Unit or nil
end

-- та же рамка пугала, что считает ScarecrowSway на клиенте (см. Raft_scarecrow_anim)
local PERCH = {
	Left = Vector3.new(-0.24, 0.02, 0.560),
	Right = Vector3.new(0.24, 0.02, 0.530),
	Head = Vector3.new(0.01, 0.02, 0.772),
}
local function scarecrowPerch(base, where)
	local root = base.Parent
	local body = root and root:FindFirstChild("raft_scarecrow_body", true)
	if not (body and body:IsA("BasePart")) then return nil end
	local s, cf = base.Size, base.CFrame
	local axes = { { cf.RightVector, s.X }, { cf.UpVector, s.Y }, { -cf.LookVector, s.Z } }
	local dXY, dXZ, dYZ = math.abs(s.X - s.Y), math.abs(s.X - s.Z), math.abs(s.Y - s.Z)
	local odd = 2
	if dXY < dXZ and dXY <= dYZ then odd = 3 elseif dYZ < dXZ and dYZ < dXY then odd = 1 end
	local up, height = axes[odd][1], axes[odd][2]
	if up.Y < 0 then up = -up end
	local scale = axes[odd % 3 + 1][2] / 0.32
	local bs, bcf = body.Size, body.CFrame
	local right = bcf.RightVector
	if bs.Y > bs.X and bs.Y > bs.Z then right = bcf.UpVector elseif bs.Z > bs.X and bs.Z > bs.Y then right = -bcf.LookVector end
	right = horizontal(right, up) or Vector3.xAxis
	local head = root:FindFirstChild("raft_scarecrow_head", true) -- знак оси рук меряем по голове, как ScarecrowSway
	if head and head:IsA("BasePart") and (head.Position - base.Position):Dot(right) < 0 then
		right = -right
	end
	local face = right:Cross(up)
	local p = PERCH[where]
	local at = base.Position - up * (height / 2) + (right * p.X + up * p.Z - face * p.Y) * scale
	return CFrame.fromMatrix(at, -right, up) -- ноги тут, клюв — туда же, куда лицо пугала
end

local function isPlanter(inst)
	return inst:IsA("Model") and (string.lower(inst.Name) == "raft_planter" or inst:GetAttribute("IsPlanter") == true)
end

local function planterBase(planter)
	local base = planter:FindFirstChild("Base", true)
	return (base and base:IsA("BasePart")) and base or nil
end

-- ⚠️ СНАЧАЛА ТОЧКА КЛЕВКА, ПОТОМ ЛАПЫ. Первая версия ставила птицу в случайное место
-- со случайным разворотом — клюв оказывался за бортиком, чайка клевала доски и воздух.
-- Теперь выбирается точка В ЗЕМЛЕ (средняя часть грядки), а лапы ставятся позади неё
-- ровно на вылет клюва в клипе Peck, и птица смотрит на эту точку.
local PECK_REACH = 0.08 -- ед. модели: в нижней точке клевка клюв уходит вперёд от лап примерно на столько (корпус наклонён, шея согнута вниз-назад)
local function planterSpot(planter, base, scale)
	local cf, size
	if base then
		cf, size = base.CFrame, base.Size
	else
		cf, size = planter:GetBoundingBox()
	end
	local hx, hz = size.X * 0.5, size.Z * 0.5
	local reach = PECK_REACH * scale
	local target, feet
	for _ = 1, 12 do
		target = Vector3.new((rng:NextNumber() - 0.5) * hx * 0.7, size.Y / 2, (rng:NextNumber() - 0.5) * hz * 0.7)
		local a = rng:NextNumber() * math.pi * 2
		feet = target - Vector3.new(math.cos(a), 0, math.sin(a)) * reach
		-- и лапы тоже внутри бортика (он занимает примерно крайние 12%)
		if math.abs(feet.X) < hx * 0.74 and math.abs(feet.Z) < hz * 0.74 then break end
		feet = nil
	end
	if not feet then -- грядка меньше вылета клюва: встать в центр, клевать куда достанет
		target = Vector3.new(0, size.Y / 2, 0)
		feet = Vector3.new(0, size.Y / 2, math.min(reach, hz * 0.5))
	end
	local rel = CFrame.lookAt(feet, target)
	-- место хранится ОТНОСИТЕЛЬНО грядки: плот плывёт, и точка посадки едет вместе с ним
	return cf * rel, rel
end

-- возвращает { kind, target (модель), place, feet = CFrame ног }
local function pickTarget()
	local scarecrows, planters = {}, {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name == "raft_scarecrow_base" then
			table.insert(scarecrows, d)
		elseif isPlanter(d) then
			table.insert(planters, d)
		end
	end
	-- ⚠️ ЧАЙКИ ЛЕТЯТ ТОЛЬКО К УРОЖАЮ (владелец). Нет ни одной грядки с посадкой —
	-- не прилетают вовсе, и пугало без огорода их не приманивает: приманка
	-- имеет смысл только когда есть что защищать.
	local anyCrop = false
	for _, p in ipairs(planters) do
		if p:GetAttribute("Crop") ~= nil then anyCrop = true break end
	end
	if not anyCrop then return nil end
	-- пугало — приманка: пока на нём есть место, грядки не трогают
	for _, base in ipairs(scarecrows) do
		local model = base.Parent
		local used = taken[model] or {}
		local free = {}
		for _, where in ipairs({ "Left", "Right", "Head" }) do
			if not used[where] then table.insert(free, where) end
		end
		if #free > 0 then
			local where = free[rng:NextInteger(1, #free)]
			local feet = scarecrowPerch(base, where)
			if feet then
				return { kind = "scarecrow", target = model, place = where, feet = feet }
			end
		end
	end
	local withCrop, empty = {}, {}
	for _, p in ipairs(planters) do
		if not (taken[p] and next(taken[p])) then
			table.insert((p:GetAttribute("Crop") ~= nil) and withCrop or empty, p)
		end
	end
	-- ⚠️ НА ПУСТУЮ ГРЯДКУ НЕ ЛЕТИМ (владелец): клевать там нечего. Только та, где
	-- что-то растёт или уже выросло (атрибут Crop ставит PlanterService).
	local pool = withCrop
	if #pool == 0 then return nil end
	local p = pool[rng:NextInteger(1, #pool)]
	local base = planterBase(p)
	local feet, rel = planterSpot(p, base, 1) -- начерно; точно — после рига, когда известен масштаб птицы
	return { kind = "planter", target = p, place = "Top", feet = feet, base = base, rel = rel }
end

-- ═════════════════════════════════════════════════ птица
local function setClip(g, name)
	if g.clip ~= name then
		g.clip = name
		g.model:SetAttribute("Clip", name)
	end
end

local function once(g, name)
	g.model:SetAttribute("ClipOnce", name)
	g.model:SetAttribute("ClipOnceT", os.clock())
end

local function rootFromFeet(g, feet)
	return feet * CFrame.new(0, Data.TorsoHeight * g.scale, 0)
end

local function refreshFeet(g)
	local goal = g.goal
	if goal.kind == "scarecrow" then
		local base = goal.target:FindFirstChild("raft_scarecrow_base", true)
		local feet = base and scarecrowPerch(base, goal.place)
		if feet then goal.feet = feet end
	elseif goal.base and goal.base.Parent then
		goal.feet = goal.base.CFrame * goal.rel
	end
end

local function targetGone(g)
	local t = g.goal and g.goal.target
	return not (t and t:IsDescendantOf(workspace))
end

-- ⚠️ СИДЯЩУЮ ПТИЦУ ВЕДЁТ КЛИЕНТ. Сервер переставлял её каждый кадр, а плот качается
-- (RaftShake): по сети позиция приходит рывками 20 раз в секунду и не совпадает с тем,
-- как плот плавно движется у клиента, — чайку трясло. Теперь сервер один раз называет
-- деталь, на которой она сидит (ObjectValue PerchPart), и позу корня относительно неё
-- (атрибут PerchRel), а SeagullAnim ставит корень от ЭТОЙ детали каждый кадр у себя.
-- Свою копию сервер подтягивает, только если она уехала дальше полутора студов
-- (она нужна лишь для попаданий по птице).
local function setPerch(g, part, rootCF)
	local ref = g.model:FindFirstChild("PerchPart")
	if not part then
		if ref then ref.Value = nil end
		g.model:SetAttribute("PerchRel", nil)
		return
	end
	if not ref then
		ref = Instance.new("ObjectValue")
		ref.Name = "PerchPart"
		ref.Parent = g.model
	end
	g.model:SetAttribute("PerchRel", part.CFrame:ToObjectSpace(rootCF))
	ref.Value = part
end

local function release(g)
	local t = g.goal
	if t and taken[t.target] then
		taken[t.target][t.place] = nil
	end
	if g.model.Parent ~= folder and g.model.Parent then
		g.model.Parent = folder -- слезла с пугала: ScarecrowSway больше её не возит и не считает вес
	end
	g.model:SetAttribute("Perch", nil)
end

local function flyAwayPoint(from)
	local a = rng:NextNumber() * math.pi * 2
	return from + Vector3.new(math.cos(a), 0, math.sin(a)) * 260 + Vector3.new(0, 70, 0)
end

local function flee(g, scared)
	if g.state == "takeoff" or g.state == "leaving" or g.dead then return end
	local wasDown = g.state == "perched" or g.state == "landing"
	if g.state == "perched" and not targetGone(g) then
		refreshFeet(g)
		g.root.CFrame = rootFromFeet(g, g.goal.feet) -- серверная копия могла отстать от плота: взлёт — с настоящего места
	end
	release(g)
	g.exit = flyAwayPoint(g.root.Position)
	g.speed = scared and CFG.FLEE_SPEED or CFG.FLY_SPEED
	setPerch(g, nil)
	if wasDown then
		g.state, g.t = "takeoff", 0
		g.from = g.root.CFrame
		once(g, "TakeOff")
		setClip(g, "Fly")
	else
		g.state = "leaving"
		if scared then once(g, "Hit") end
		setClip(g, "Fly")
	end
end

--[[ ⚠️ УРОВЕНЬ ВОДЫ — ОТ ПЛОТА, А НЕ КОНСТАНТОЙ. Здесь стояло WATER_Y = -4, а океан
     в этом плейсе лежит на Y≈-384: любая подбитая в воздухе чайка была «ниже воды»
     с первого же кадра падения и исчезала мгновенно — «труп сразу пропадает». ]]
local function waterY()
	local raft = workspace:FindFirstChild("Raft")
	local pp = raft and raft.PrimaryPart
	return (pp and pp.Position.Y or -384) - CFG.WATER_DROP
end

-- добыча: тем же путём, что выброшенный из рюкзака предмет (DropItem) — он сам
-- сажает её на плот, ставит подбор и срок жизни
local function spawnLoot(g)
	if g.looted then return end
	g.looted = true
	if typeof(_G.SpawnResourceDrop) ~= "function" then return end
	local pos = g.root.Position
	local owner = Players:GetPlayerByUserId(tonumber(g.model:GetAttribute("LastHitBy")) or 0)
	if not (owner and owner.Character) then
		owner = nil
		local bestD
		for _, plr in ipairs(Players:GetPlayers()) do
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if not bestD or d < bestD then owner, bestD = plr, d end
			end
		end
	end
	if not owner then return end
	local byFire = g.model:GetAttribute("KilledByFire") == true
	for item, n in pairs(CFG.DROPS) do
		local a = rng:NextNumber() * math.pi * 2
		-- сгорела от огнемёта — мясо падает уже жареным (как у кур, AnimalLife)
		if byFire and item == "Chicken_drumstick" then item = "Meat_Cooked" end
		pcall(_G.SpawnResourceDrop, owner, item, n, pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 1.5)
	end
end

--[[ ПУГАЛО ИЗНАШИВАЕТСЯ: каждая секунда, что на нём сидит чайка, пишется в
     атрибут GullWear модели (сумма по всем чайкам и визитам). Набралось
     SCARECROW_WEAR — рассыпается: сидящие птицы слетают, детали отваливаются и
     тают, модель убирается. Атрибут переживает сейв (RaftSave пишет атрибуты
     построек), так что «отдохнуть» пугалу перезаход не даст. ]]
local Debris = game:GetService("Debris")
local function breakScarecrow(model)
	if model:GetAttribute("Broken") then return end
	model:SetAttribute("Broken", true)
	model:SetAttribute("Hit", os.clock())   -- ScarecrowSway: солома и отшатывание
	for _, g in ipairs(gulls) do
		if g.goal and g.goal.target == model and not g.dead then flee(g, true) end
	end
	taken[model] = nil
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	task.delay(0.35, function()
		if not model.Parent then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then d:Destroy() end
		end
		for _, p in ipairs(parts) do
			if p.Parent then
				p.Anchored = false
				p.CanCollide = false
				p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(6, 12), rng:NextNumber(-6, 6))
				p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-4, 4), rng:NextNumber(-4, 4))
			end
		end
		task.spawn(function()
			local t0 = os.clock()
			while model.Parent and os.clock() - t0 < 1.6 do
				local a = (os.clock() - t0) / 1.6
				for _, p in ipairs(parts) do if p.Parent then p.Transparency = a end end
				task.wait()
			end
			if model.Parent then model:Destroy() end
		end)
	end)
	print("[SeagullAI] пугало развалилось: чайки просидели на нём " .. CFG.SCARECROW_WEAR .. " с")
	if typeof(_G.NotifyPlayer) == "function" then
		for _, plr in ipairs(Players:GetPlayers()) do
			pcall(_G.NotifyPlayer, plr, { type = "warn", icon = "no", title = "Пугало развалилось",
				body = "Чайки истрепали его — поставь новое" })
		end
	end
end

local function die(g)
	if g.dead then return end
	g.dead = true
	-- на грядке валится там, где стояла; с руки пугала — падает вниз, как подбитая в воздухе
	local grounded = g.state == "perched" and g.goal and g.goal.kind == "planter"
	local offPerch = g.state == "perched" and not grounded
	if g.state == "perched" and not targetGone(g) then
		refreshFeet(g)
		g.root.CFrame = rootFromFeet(g, g.goal.feet)
	end
	if not grounded then setPerch(g, nil) end -- тушка на грядке остаётся привязанной: плот её везёт
	release(g)
	g.model:SetAttribute("Dead", true)
	Killed:Fire(g.model, g.model:GetAttribute("LastHitBy"))
	if grounded then
		g.state, g.t = "corpse", 0
		spawnLoot(g)
		once(g, "DieGround")
		setClip(g, "Dead")
	else
		g.state, g.t = "falling", 0
		-- подбитую подбрасывает: короткий кувырок вверх, потом падение штопором
		g.vel = offPerch and (g.root.CFrame.LookVector * 3 + Vector3.new(0, 9, 0)) or ((g.vel or Vector3.zero) * 0.6 + Vector3.new(0, 7, 0))
		g.spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-4, 4), rng:NextNumber(-11, 11))
		setClip(g, "FallDead")
	end
end

--[[ РАНЕНЫЕ ВОЗВРАЩАЮТСЯ РАНЕНЫМИ (владелец). Чайка, улетевшая живой с неполным
     здоровьем, кладёт его в эту очередь, и следующая прилетевшая — «та же самая»:
     стартует с этим остатком. Иначе спугнутая птица возвращалась бы здоровой, и
     добить её было бы нельзя. Убитая из очереди выбывает сама — ей нечего класть. ]]
local wounded = {}

local function spawnGull()
	local template = findTemplate()
	if not template then
		warn("[SeagullAI] нет модели '" .. CFG.TEMPLATE .. "' в ReplicatedStorage — импортируйте Seagull.fbx и назовите модель Seagull")
		return nil
	end
	local goal = pickTarget()
	if not goal then return nil end -- ни пугала, ни грядки: чайкам тут нечего делать

	-- порядок из ANIMATIONS.md: клонировать → риг по авторской позе → Humanoid и атрибуты → в папку → на место
	local model = template:Clone()
	local _, scale = SeagullRig.setup(model)
	if goal.kind == "planter" then
		goal.feet, goal.rel = planterSpot(goal.target, goal.base, scale)
	end
	local root = model.PrimaryPart

	local hum = model:FindFirstChildWhichIsA("Humanoid") or Instance.new("Humanoid")
	hum.MaxHealth = CFG.HEALTH
	local startHealth = table.remove(wounded, 1) or CFG.HEALTH
	hum.Health = startHealth
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false          -- иначе движок сам убьёт птицу: у неё нет R6-шеи
	hum.EvaluateStateMachine = false  -- чайку ведёт код
	hum.PlatformStand = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = model

	model.Name = "Seagull"
	model:SetAttribute("Clip", "Fly")
	model:SetAttribute("Flammable", true)   -- огнемёт бьёт и поджигает (FlamethrowerSystem)
	model:SetAttribute("BurnSelf", true)    -- …но паникует по-своему, без гуманоидного бега
	CollectionService:AddTag(model, "Seagull")

	local a = rng:NextNumber() * math.pi * 2
	local dist = rng:NextNumber(CFG.SPAWN_DIST[1], CFG.SPAWN_DIST[2])
	local start = goal.feet.Position + Vector3.new(math.cos(a) * dist, rng:NextNumber(CFG.SPAWN_HEIGHT[1], CFG.SPAWN_HEIGHT[2]), math.sin(a) * dist)
	model.Parent = folder
	model:PivotTo(CFrame.lookAt(start, goal.feet.Position))

	local g = {
		model = model, root = root, hum = hum, scale = scale,
		state = "approach", clip = "Fly", goal = goal, speed = CFG.FLY_SPEED,
		t = 0, vel = Vector3.zero, lastHealth = startHealth, hum = hum, pecks = 0,
	}
	taken[goal.target] = taken[goal.target] or {}
	taken[goal.target][goal.place] = g

	hum.HealthChanged:Connect(function(h)
		if h < g.lastHealth then
			if h <= 0 then
				die(g)
			elseif g.model:GetAttribute("OnFire") == true then
				-- горит: паника уже идёт (step), взлёт не перезапускаем
			elseif h <= CFG.HEALTH * CFG.FLEE_HEALTH or g.state ~= "perched" then
				flee(g, true)
			else
				once(g, "Hit")            -- ещё держится: дёрнулась и клюёт дальше
			end
		end
		g.lastHealth = h
	end)
	table.insert(gulls, g)
	return g
end
_G.SpawnSeagull = spawnGull

-- лететь к точке; возвращает true, когда долетела
local function flyTo(g, point, dt, arrive)
	local pos = g.root.Position
	local to = point - pos
	local d = to.Magnitude
	if d < (arrive or 2) then return true end
	local want = to.Unit * g.speed
	g.vel = g.vel:Lerp(want, math.min(1, dt * 2.2)) -- плавный доворот вместо рывка
	local nextPos = pos + g.vel * dt
	local look = (g.vel.Magnitude > 0.1) and g.vel.Unit or to.Unit
	local flat = Vector3.new(look.X, 0, look.Z)
	-- крен в вираж: насколько желаемый курс уходит в сторону от текущего
	local turn = (flat.Magnitude > 0.01) and flat.Unit:Cross(Vector3.new(want.X, 0, want.Z).Unit).Y or 0
	g.root.CFrame = CFrame.lookAt(nextPos, nextPos + look) * CFrame.Angles(0, 0, math.clamp(turn * 1.2, -0.6, 0.6))
	return false
end

local function step(g, dt)
	g.t += dt
	-- ⚠️ ГОРИТ — ПАНИКА ПОВЕРХ ЛЮБОГО СОСТОЯНИЯ (кроме смерти). Слетает с
	-- насеста, мечется в воздухе зигзагом и вверх; потухла — уходит, как
	-- спугнутая. Клип Panic — быстрый взмах с креном (SeagullAnimator).
	if g.model:GetAttribute("OnFire") == true and not g.dead then
		if g.state ~= "panic" then
			if g.state == "perched" and not targetGone(g) then
				refreshFeet(g)
				g.root.CFrame = rootFromFeet(g, g.goal.feet)
			end
			release(g)
			setPerch(g, nil)
			g.state = "panic"
			g.panicHead = rng:NextNumber() * math.pi * 2
			g.panicTurnT = 0
			g.speed = CFG.PANIC_SPEED
			g.vel = (g.vel and g.vel.Magnitude > 1) and g.vel or (g.root.CFrame.LookVector * 8 + Vector3.new(0, 6, 0))
			g.exit = flyAwayPoint(g.root.Position)
			once(g, "Hit")
			setClip(g, "Panic")
		end
		g.panicTurnT -= dt
		if g.panicTurnT <= 0 then
			g.panicTurnT = rng:NextNumber(0.25, 0.7)
			g.panicHead += rng:NextNumber(-2.2, 2.2)
		end
		local dir = Vector3.new(math.cos(g.panicHead), 0, math.sin(g.panicHead)) * CFG.PANIC_SPEED
			+ Vector3.new(0, CFG.PANIC_CLIMB + math.sin(g.t * 9) * 4, 0)
		g.vel = g.vel:Lerp(dir, math.min(1, dt * CFG.PANIC_TURN))
		local nextPos = g.root.Position + g.vel * dt
		local look = g.vel.Unit
		g.root.CFrame = CFrame.lookAt(nextPos, nextPos + look) * CFrame.Angles(0, 0, math.sin(g.t * 11) * 0.7)
		return
	elseif g.state == "panic" then
		-- потухла: улетает как спугнутая
		g.state = "leaving"
		g.speed = CFG.FLEE_SPEED
		g.exit = flyAwayPoint(g.root.Position)
		setClip(g, "Fly")
	end
	if g.state == "approach" then
		if targetGone(g) then flee(g, false) return end
		refreshFeet(g) -- цель могла уехать вместе с плотом: точку посадки пересчитываем на лету
		local land = rootFromFeet(g, g.goal.feet).Position
		local back = horizontal(g.root.Position - land, Vector3.yAxis) or Vector3.xAxis
		local gate = land + back * CFG.GATE_BACK + Vector3.new(0, CFG.GATE_UP, 0)
		local far = (g.root.Position - gate).Magnitude
		setClip(g, (far < 60 and g.root.Position.Y > gate.Y + 4) and "Glide" or "Fly")
		if flyTo(g, gate, dt, 3) then
			g.state, g.t = "landing", 0
			g.from = g.root.CFrame
			once(g, "Land")
			setClip(g, "Idle")
		end
	elseif g.state == "landing" then
		if targetGone(g) then flee(g, false) return end
		refreshFeet(g)
		local a = math.clamp(g.t / CFG.LAND_TIME, 0, 1)
		local goalCF = rootFromFeet(g, g.goal.feet)
		local e = 1 - (1 - a) * (1 - a)                       -- быстро подошла, мягко села
		local pos = g.from.Position:Lerp(goalCF.Position, e) + Vector3.new(0, math.sin(a * math.pi) * 1.2, 0)
		g.root.CFrame = g.from.Rotation:Lerp(goalCF.Rotation, e) + pos
		if a >= 1 then
			g.state, g.t = "perched", 0
			g.leaveAt = rng:NextNumber(CFG.VISIT[1], CFG.VISIT[2])
			g.nextPeck = 0.4
			g.root.CFrame = goalCF
			setClip(g, "Peck")
			if g.goal.kind == "planter" and g.goal.base then
				setPerch(g, g.goal.base, goalCF)
			end
			if g.goal.kind == "scarecrow" then
				-- отдать птицу ScarecrowSway: он возит её вместе с наклоном руки и считает её вес
				local perched = g.goal.target:FindFirstChild("Perched")
				if not perched then
					perched = Instance.new("Folder")
					perched.Name = "Perched"
					perched.Parent = g.goal.target
				end
				g.model:SetAttribute("Perch", g.goal.place)
				g.model.Parent = perched
			end
		end
	elseif g.state == "perched" then
		if targetGone(g) then flee(g, false) return end
		refreshFeet(g)
		local want = rootFromFeet(g, g.goal.feet)
		if (g.root.Position - want.Position).Magnitude > 1.5 then
			g.root.CFrame = want -- редкая подтяжка серверной копии; у клиентов птицу ведёт SeagullAnim
		end
		-- клюёт сериями, между ними озирается
		g.actT = (g.actT or 0) - dt
		if g.actT <= 0 then
			if g.act == "peck" then
				local look = rng:NextNumber() < CFG.LOOK_CHANCE
				g.act = look and "look" or "rest"
				g.actT = look and CFG.LOOK_TIME or rng:NextNumber(CFG.REST_TIME[1], CFG.REST_TIME[2])
			else
				g.act = "peck"
				g.actT = rng:NextNumber(CFG.PECK_TIME[1], CFG.PECK_TIME[2])
			end
			g.model:SetAttribute("ClipSpeed", g.act == "look" and CFG.LOOK_SPEED or 1)
		end
		setClip(g, g.act == "peck" and "Peck" or (g.act == "look" and "Idle" or "Rest"))
		if g.goal.kind == "scarecrow" then
			local m = g.goal.target
			local wear = (tonumber(m:GetAttribute("GullWear")) or 0) + dt
			m:SetAttribute("GullWear", wear)
			if wear >= CFG.SCARECROW_WEAR then breakScarecrow(m) return end
		end
		if g.goal.kind == "planter" then
			-- урожай сняли из-под клюва — делать тут больше нечего
			if g.goal.target:GetAttribute("Crop") == nil then flee(g, false) return end
			if g.act == "peck" then
				g.eatT = (g.eatT or 0) + dt
				if g.eatT >= CFG.EAT_TIME then
					if typeof(_G.PlanterEatCrop) == "function" then pcall(_G.PlanterEatCrop, g.goal.target) end
					flee(g, false)
					return
				end
			end
		end
		g.nextPeck -= dt
		if g.nextPeck <= 0 and g.act == "peck" then
			g.nextPeck = CFG.PECK_PERIOD / 2
			g.pecks += 1
			local total = (g.goal.target:GetAttribute("GullPecks") or 0) + 1
			g.goal.target:SetAttribute("GullPecks", total)
			Pecked:Fire(g.goal.target, g.model, total)
		end
		if g.t >= g.leaveAt then flee(g, false) end
	elseif g.state == "takeoff" then
		local a = math.clamp(g.t / CFG.TAKEOFF_TIME, 0, 1)
		local out = horizontal(g.exit - g.from.Position, Vector3.yAxis) or Vector3.xAxis
		-- первые 40% клипа — присела и вскрикнула, стоит на месте; дальше прыжок вверх-вперёд
		local k = math.clamp((a - 0.4) / 0.6, 0, 1)
		local pos = g.from.Position + out * (k * k * 5) + Vector3.new(0, k * k * 6, 0)
		local face = CFrame.lookAt(pos, pos + out)
		g.root.CFrame = g.from.Rotation:Lerp(face.Rotation, k) + pos
		if a >= 1 then
			g.state = "leaving"
			g.vel = (out * 0.8 + Vector3.new(0, 0.6, 0)).Unit * g.speed * 0.6
		end
	elseif g.state == "leaving" then
		if flyTo(g, g.exit, dt, 12) then
			g.remove = true
		end
	elseif g.state == "falling" then
		g.vel += Vector3.new(0, -workspace.Gravity * 0.55, 0) * dt
		local pos = g.root.Position
		local nextPos = pos + g.vel * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { folder }
		local hit = workspace:Raycast(pos, nextPos - pos + Vector3.new(0, -0.6 * g.scale, 0), params)
		if hit and hit.Normal.Y > 0.5 then
			-- шлёпнулась: дальше лежит в позе Dead; корень ставим СТОЯ на точку — клип сам укладывает тушку набок
			local yaw = math.atan2(-g.vel.X, -g.vel.Z)
			g.root.CFrame = rootFromFeet(g, CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0))
			g.state, g.t = "corpse", 0
			setClip(g, "Dead")
			-- ⚠️ ТУШКА ЕДЕТ С ПЛОТОМ: без привязки она оставалась висеть в точке
			-- падения, а плот уходил из-под неё восемь студов в секунду
			if hit.Instance and not hit.Instance.Anchored then setPerch(g, hit.Instance, g.root.CFrame) end
			spawnLoot(g)
		elseif nextPos.Y < waterY() then
			g.remove = true
		else
			g.root.CFrame = (g.root.CFrame.Rotation * CFrame.Angles(g.spin.X * dt, g.spin.Y * dt, g.spin.Z * dt)) + nextPos
		end
	elseif g.state == "corpse" then
		if g.t > CFG.CORPSE_TIME then
			g.remove = true
		elseif g.t > CFG.CORPSE_TIME - 1 then
			local fade = g.t - (CFG.CORPSE_TIME - 1)
			for _, p in ipairs(g.model:GetDescendants()) do
				if p:IsA("BasePart") and p ~= g.root then p.Transparency = fade end
			end
		end
	end
end

-- ОДИН цикл на всех чаек
RunService.Heartbeat:Connect(function(dt)
	for i = #gulls, 1, -1 do
		local g = gulls[i]
		if not g.model.Parent then
			g.remove = true
		else
			local ok, err = pcall(step, g, dt)
			if not ok then
				warn("[SeagullAI] " .. tostring(err))
				g.remove = true
			end
		end
		if g.remove then
			if not g.dead and g.hum and g.hum.Health > 0 and g.hum.Health < CFG.HEALTH then
				table.insert(wounded, g.hum.Health)
			end
			release(g)
			if g.model.Parent then g.model:Destroy() end
			table.remove(gulls, i)
		end
	end
end)

task.spawn(function()
	task.wait(CFG.FIRST_SPAWN)
	while true do
		if #gulls < CFG.MAX_GULLS then
			spawnGull()
		end
		task.wait(rng:NextNumber(CFG.SPAWN_EVERY[1], CFG.SPAWN_EVERY[2]))
	end
end)

print(("[SeagullAI] ready (до %d чаек, прилёт каждые %d-%d с)"):format(CFG.MAX_GULLS, CFG.SPAWN_EVERY[1], CFG.SPAWN_EVERY[2]))
