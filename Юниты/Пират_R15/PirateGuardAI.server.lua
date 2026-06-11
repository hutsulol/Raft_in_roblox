--[[
	PirateGuardAI — сторож-пират на ОБЫЧНОМ Humanoid (R6/R15).

	Та же система сторожа, что и у безхуманоидного пирата (Юниты/Пират), но вся
	физика/локомоция/анимации отданы Humanoid'у:
	  • ходьба/бег/прыжки и их анимации   → Humanoid:MoveTo + штатный Animate;
	  • обход препятствий                  → PathfindingService (с прямым LOS-срезом);
	  • перелаз/прыжки через мелочь        → Humanoid (AgentCanJump + JumpCheck).

	Мозг сторожа полностью свой:
	  • Зрение (Far Cry / AC): угол от «глаз» (Head) до игрока — спереди замечает
	    быстро, сбоку медленно, сзади не видит; обзор рвётся стеной (Raycast).
	  • Шкала подозрения 0..100 с полосой над головой (бело→жёлтый→красный).
	  • FSM: Guard / Patrol / Investigate / Chase+Attack / Search / Return / Alerted.
	  • Крик отряду: на 100% пират поднимает соседних пиратов с тегом PirateGuard.
	  • Патруль по маркерам из папки PatrolPoints (необязательно).

	Куда вставлять: обычный серверный Script внутрь модели пирата (рядом с Humanoid).
	Атака берёт инструмент (Tool, напр. ClassicSword) — Activate + наш TakeDamage;
	если есть дочерняя Animation "Attack" у скрипта — проигрываем её.
--]]

local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")

local npc = script.Parent

--====================================================
-- НАСТРОЙКИ
--====================================================

local CFG = {
	-- Движение (Humanoid.WalkSpeed)
	PATROL_SPEED = 8,
	CHASE_SPEED  = 18,

	-- Бой
	ATTACK_RANGE        = 6,    -- studs (центр-к-центру HRP)
	ATTACK_RANGE_BUFFER = 3,    -- гистерезис выхода из боя
	ATTACK_COOLDOWN     = 1.2,  -- сек между ударами
	ATTACK_DAMAGE       = 20,   -- урон по игроку за удар
	ATTACK_HIT_DELAY    = 0.25, -- задержка нанесения урона (под замах анимации)

	-- Поведение / память места
	BEHAVIOR_VARIANT  = "Guard",       -- Guard | Patrol
	PATROL_POINTS_FOLDER_NAME = "PatrolPoints",
	GUARD_DURATION    = 60,            -- сколько стоит на посту перед патрулём (Patrol-вариант)
	PATROL_POINT_REACH = 3,
	PATROL_PAUSE_MIN  = 10,
	PATROL_PAUSE_MAX  = 30,

	-- Зрение и подозрение
	SIGHT_RANGE        = 50,
	FOV_FRONT_DEGREES  = 50,   -- спереди (быстро замечает)
	FOV_SIDE_DEGREES   = 110,  -- сбоку (медленно)
	EYE_HEIGHT_OFFSET  = 1,
	SUSPICION_GAIN_FRONT = 90,
	SUSPICION_GAIN_SIDE  = 35,
	SUSPICION_DECAY      = 25,
	SUSPICION_INVESTIGATE = 50,  -- порог «пойти проверить»
	SUSPICION_ALERT       = 100, -- порог «в бой + крик»
	SEARCH_DURATION       = 15,  -- сколько искать у последней точки

	-- Отряд (крик соседям)
	GUARD_TAG          = "PirateGuard",
	SQUAD_ALERT_RADIUS = 200,  -- кого поднимаем криком
	SQUAD_ENGAGE_RADIUS = 60,  -- ближе — идут проверять, дальше — в готовность
	ALERT_MEMORY       = 8,    -- сколько помнить чужой крик
	SHOUT_INTERVAL     = 2,    -- как часто перекрикивать в бою
	DEBUG_SQUAD        = false,

	-- Навигация
	AGENT_RADIUS   = 2,
	AGENT_HEIGHT   = 5,
	AGENT_CAN_JUMP = true,
	PATH_RECOMPUTE_INTERVAL = 0.5,
	PATH_GOAL_MOVE_THRESHOLD = 6,  -- цель сдвинулась дальше — пересчёт
	WAYPOINT_REACH = 4,
	NAV_LOS_MARGIN = 4,            -- ближе этого считаем «видим напрямую»
	JUMP_CHECK_INTERVAL = 0.4,
}

--====================================================
-- РИГ: Humanoid / HumanoidRootPart / Head
--====================================================

-- Модель может реплицироваться/собираться не мгновенно — подождём ключевые части.
while not npc:IsDescendantOf(workspace) do
	npc.AncestryChanged:Wait()
end

local humanoid = npc:FindFirstChildOfClass("Humanoid")
do
	local waited = 0
	while not humanoid and waited < 5 do
		task.wait(0.1); waited += 0.1
		humanoid = npc:FindFirstChildOfClass("Humanoid")
	end
end
if not humanoid then
	warn("[PirateGuardAI] Humanoid не найден — скрипт не запущен")
	return
end

local rootPart = npc:FindFirstChild("HumanoidRootPart") or humanoid.RootPart
if not rootPart then
	rootPart = npc:WaitForChild("HumanoidRootPart", 5)
end
if not rootPart then
	warn("[PirateGuardAI] HumanoidRootPart не найден — скрипт не запущен")
	return
end

local head = npc:FindFirstChild("Head") or rootPart

-- PrimaryPart нужен, чтобы соседние сторожа находили нас по своему крику.
if not npc.PrimaryPart then
	npc.PrimaryPart = rootPart
end

-- Базовая настройка рига.
for _, d in ipairs(npc:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = false
	end
end
humanoid.WalkSpeed = CFG.PATROL_SPEED
humanoid.AutoRotate = true
pcall(function()
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
end)

CollectionService:AddTag(npc, CFG.GUARD_TAG)

-- Анимация атаки (необязательно): дочерняя Animation "Attack" у скрипта.
local attackTrack = nil
do
	local attackAnim = script:FindFirstChild("Attack")
	if attackAnim and attackAnim:IsA("Animation") then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local ok, track = pcall(function()
			return animator:LoadAnimation(attackAnim)
		end)
		if ok then attackTrack = track end
	end
end

--====================================================
-- ОБЩИЕ ХЕЛПЕРЫ
--====================================================

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true
raycastParams.FilterDescendantsInstances = { npc }

local function getCharacterRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character.PrimaryPart
end

local function getCharacterHumanoid(character)
	return character:FindFirstChildOfClass("Humanoid")
end

local function isAliveCharacter(character)
	local h = character and getCharacterHumanoid(character)
	return h ~= nil and h.Health > 0
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Куда «смотрит» пират (Humanoid сам поворачивается по движению).
local function getLookDirection()
	local look = rootPart.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function getEyePosition()
	return head.Position + Vector3.new(0, CFG.EYE_HEIGHT_OFFSET, 0)
end

-- Повернуть корпус к точке (для атаки/осмотра, когда не двигаемся).
local function faceTowards(position)
	local flatTarget = Vector3.new(position.X, rootPart.Position.Y, position.Z)
	if (flatTarget - rootPart.Position).Magnitude < 0.05 then
		return
	end
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, flatTarget)
end

-- Прямая видимость до персонажа: луч от глаз, стена рвёт обзор.
local function canSeeCharacter(targetRoot)
	local origin = getEyePosition()
	local result = workspace:Raycast(origin, targetRoot.Position - origin, raycastParams)
	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end
	return true
end

--====================================================
-- ВОСПРИЯТИЕ (зрение + подозрение)
--====================================================

local suspicion = 0
local lastKnownPosition = nil
local chaseTarget = nil

-- Обновляет подозрение по FOV + LOS. Возвращает ближайшего видимого игрока.
local function updatePerception(dt)
	local lookDir = getLookDirection()
	local eye = getEyePosition()
	local bestRoot, bestChar, bestDist = nil, nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and isAliveCharacter(character) then
			local root = getCharacterRoot(character)
			if root then
				local flat = Vector3.new(root.Position.X - eye.X, 0, root.Position.Z - eye.Z)
				local dist = flat.Magnitude
				if dist > 0.05 and dist <= CFG.SIGHT_RANGE then
					local angle = math.deg(math.acos(math.clamp(lookDir:Dot(flat.Unit), -1, 1)))
					local gain = nil
					if angle <= CFG.FOV_FRONT_DEGREES then
						gain = CFG.SUSPICION_GAIN_FRONT
					elseif angle <= CFG.FOV_SIDE_DEGREES then
						gain = CFG.SUSPICION_GAIN_SIDE
					end

					-- Вплотную «не заметить» нельзя — независимо от угла.
					if dist <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
						gain = CFG.SUSPICION_GAIN_FRONT
					end

					if gain and canSeeCharacter(root) then
						local distFactor = 1 - (dist / CFG.SIGHT_RANGE) * 0.6
						suspicion = math.min(100, suspicion + gain * distFactor * dt)
						if dist < bestDist then
							bestDist, bestRoot, bestChar = dist, root, character
						end
					end
				end
			end
		end
	end

	if bestRoot then
		lastKnownPosition = bestRoot.Position
	end
	return bestRoot, bestChar
end

--====================================================
-- ИНДИКАТОР ПОДОЗРЕНИЯ (полоса над головой)
--====================================================

local suspicionGui = Instance.new("BillboardGui")
suspicionGui.Name = "SuspicionBar"
suspicionGui.Size = UDim2.new(0, 80, 0, 8)
suspicionGui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
suspicionGui.AlwaysOnTop = true
suspicionGui.MaxDistance = 90
suspicionGui.Enabled = false
suspicionGui.Adornee = head
suspicionGui.Parent = head

local suspicionBg = Instance.new("Frame")
suspicionBg.Size = UDim2.new(1, 0, 1, 0)
suspicionBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
suspicionBg.BackgroundTransparency = 0.4
suspicionBg.BorderSizePixel = 0
suspicionBg.Parent = suspicionGui

local suspicionFill = Instance.new("Frame")
suspicionFill.Size = UDim2.new(0, 0, 1, 0)
suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
suspicionFill.BorderSizePixel = 0
suspicionFill.Parent = suspicionBg

local function updateSuspicionBar()
	suspicionGui.Enabled = suspicion > 1
	suspicionFill.Size = UDim2.new(math.clamp(suspicion / 100, 0, 1), 0, 1, 0)
	if suspicion >= CFG.SUSPICION_ALERT then
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	elseif suspicion >= CFG.SUSPICION_INVESTIGATE then
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
	else
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

--====================================================
-- ПАТРУЛЬ И ДОМ (память места)
--====================================================

local homePosition = rootPart.Position
local homeLook = getLookDirection()

local patrolPoints = {}
do
	local folder = npc:FindFirstChild(CFG.PATROL_POINTS_FOLDER_NAME)
	if folder then
		local markers = {}
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(markers, child)
			end
		end
		table.sort(markers, function(a, b) return a.Name < b.Name end)
		for _, m in ipairs(markers) do
			table.insert(patrolPoints, m.Position)
		end
	end
end
local patrolIndex = 1

--====================================================
-- ОТРЯД (крик соседним пиратам)
--====================================================

local alertedUntil = 0
local alertPosition = nil
local alertUserId = nil
local lastShoutClock = 0

local function broadcastAlert()
	if not chaseTarget then return end
	local player = Players:GetPlayerFromCharacter(chaseTarget)
	local userId = player and player.UserId or 0
	local pos = lastKnownPosition or rootPart.Position
	lastShoutClock = os.clock()

	local raised = 0
	for _, other in ipairs(CollectionService:GetTagged(CFG.GUARD_TAG)) do
		if other ~= npc then
			local otherRoot = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart")
			if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude <= CFG.SQUAD_ALERT_RADIUS then
				other:SetAttribute("AlertPosition", pos)
				other:SetAttribute("AlertUserId", userId)
				other:SetAttribute("AlertClock", os.clock()) -- меняем последним — триггерит реакцию
				raised += 1
			end
		end
	end
	if CFG.DEBUG_SQUAD then
		print(string.format("[PirateSquad] %s кричит отряду (поднято %d)", npc.Name, raised))
	end
end

npc:GetAttributeChangedSignal("AlertClock"):Connect(function()
	alertedUntil = os.clock() + CFG.ALERT_MEMORY
	alertPosition = npc:GetAttribute("AlertPosition")
	alertUserId = npc:GetAttribute("AlertUserId")
	if CFG.DEBUG_SQUAD then
		print(string.format("[PirateSquad] %s услышал крик отряда", npc.Name))
	end
end)

local function getSquadAlert()
	if os.clock() < alertedUntil then
		return alertPosition
	end
	return nil
end

--====================================================
-- НАВИГАЦИЯ (Humanoid:MoveTo + PathfindingService + LOS-срез)
--====================================================

local agentParams = {
	AgentRadius = CFG.AGENT_RADIUS,
	AgentHeight = CFG.AGENT_HEIGHT,
	AgentCanJump = CFG.AGENT_CAN_JUMP,
}

local path = nil
local pathWaypoints = {}
local waypointIndex = 1
local pathGoal = nil
local pathComputeClock = 0
local pathComputing = false
local lastJumpCheck = 0

-- Прямая видимость до точки (3 луча на ширину агента), чтобы идти ровно прямо.
local function hasClearPath(toPos)
	local origin = rootPart.Position
	local flat = Vector3.new(toPos.X - origin.X, 0, toPos.Z - origin.Z)
	local dist = flat.Magnitude
	if dist <= CFG.NAV_LOS_MARGIN then
		return true
	end
	local dir = flat.Unit
	local rayVec = dir * (dist - CFG.NAV_LOS_MARGIN)
	local side = Vector3.new(-dir.Z, 0, dir.X) * (CFG.AGENT_RADIUS + 1)
	for _, off in ipairs({ Vector3.zero, side, -side }) do
		if workspace:Raycast(origin + off, rayVec, raycastParams) then
			return false
		end
	end
	return true
end

local function computePathAsync(goal)
	pathComputing = true
	task.spawn(function()
		local p = PathfindingService:CreatePath(agentParams)
		local ok = pcall(function()
			p:ComputeAsync(rootPart.Position, goal)
		end)
		if ok and p.Status == Enum.PathStatus.Success then
			local wps = {}
			for _, wp in ipairs(p:GetWaypoints()) do
				table.insert(wps, wp)
			end
			path = p
			pathWaypoints = wps
			waypointIndex = 1
			pathGoal = goal
			pathComputeClock = os.clock()
		end
		pathComputing = false
	end)
end

-- Перепрыгнуть низкое препятствие на курсе (Humanoid сам прыгает).
local function jumpCheck(goal)
	if os.clock() - lastJumpCheck < CFG.JUMP_CHECK_INTERVAL then
		return
	end
	lastJumpCheck = os.clock()
	local origin = rootPart.Position
	local dir = Vector3.new(goal.X - origin.X, 0, goal.Z - origin.Z)
	if dir.Magnitude < 0.1 then return end
	local result = workspace:Raycast(origin + Vector3.new(0, -1.5, 0), dir.Unit * 3, raycastParams)
	if result then
		humanoid.Jump = true
	end
end

-- Идти к goal. Есть прямая видимость — идём прямо; иначе по маршруту.
local function navigateTo(goal, speed)
	humanoid.WalkSpeed = speed or CFG.PATROL_SPEED
	jumpCheck(goal)

	if hasClearPath(goal) then
		humanoid:MoveTo(goal)
		return
	end

	local needRecompute = (not pathGoal)
		or flatDistance(pathGoal, goal) > CFG.PATH_GOAL_MOVE_THRESHOLD
		or waypointIndex > #pathWaypoints
		or (os.clock() - pathComputeClock > CFG.PATH_RECOMPUTE_INTERVAL)

	if needRecompute and not pathComputing then
		computePathAsync(goal)
	end

	if #pathWaypoints > 0 then
		while waypointIndex <= #pathWaypoints
			and flatDistance(rootPart.Position, pathWaypoints[waypointIndex].Position) <= CFG.WAYPOINT_REACH do
			waypointIndex += 1
		end
		local wp = pathWaypoints[waypointIndex]
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(wp.Position)
		else
			humanoid:MoveTo(goal)
		end
	else
		humanoid:MoveTo(goal)
	end
end

local function stopMoving()
	humanoid:MoveTo(rootPart.Position)
end

--====================================================
-- АТАКА
--====================================================

local lastAttackTime = 0
local isAttacking = false

local function attackTarget(targetRoot, targetHumanoid)
	if isAttacking then return end
	local now = os.clock()
	if now - lastAttackTime < CFG.ATTACK_COOLDOWN then return end
	lastAttackTime = now
	isAttacking = true

	faceTowards(targetRoot.Position)

	if attackTrack then
		attackTrack:Play()
	end
	-- Инструмент (ClassicSword и т.п.): свой замах/звук.
	local tool = npc:FindFirstChildWhichIsA("Tool")
	if tool then
		pcall(function() tool:Activate() end)
	end

	task.delay(CFG.ATTACK_HIT_DELAY, function()
		if targetHumanoid and targetHumanoid.Parent and targetHumanoid.Health > 0 then
			local d = (targetRoot.Position - rootPart.Position).Magnitude
			if d <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
				targetHumanoid:TakeDamage(CFG.ATTACK_DAMAGE)
			end
		end
	end)

	task.delay(CFG.ATTACK_COOLDOWN, function()
		isAttacking = false
	end)
end

--====================================================
-- КОНЕЧНЫЙ АВТОМАТ (FSM)
--====================================================

local STATE = {
	GUARD = "Guard",
	PATROL = "Patrol",
	INVESTIGATE = "Investigate",
	CHASE = "Chase",          -- видит врага: бежит и бьёт (chase+attack слиты)
	SEARCH = "Search",        -- потерял из виду: ищет у последней точки
	RETURN = "Return",        -- возвращается на пост
	ALERTED = "Alerted",      -- поднят по тревоге отряда
}

local currentState = STATE.GUARD
local stateClock = os.clock()
local patrolPauseUntil = 0
local nextScanClock = 0
local scanYawTarget = nil

local function setState(newState)
	if currentState == newState then return end
	currentState = newState
	stateClock = os.clock()
	if newState ~= STATE.CHASE then
		-- Сбрасываем кэш пути при смене не-боевого состояния.
		pathGoal = nil
	end
end

local function stateAge()
	return os.clock() - stateClock
end

-- Осмотр по сторонам (поворот корпуса), когда стоим.
local function scan()
	if os.clock() >= nextScanClock then
		nextScanClock = os.clock() + math.random(12, 24) * 0.1
		local _, yaw = rootPart.CFrame:ToOrientation()
		scanYawTarget = yaw + math.rad(math.random(-70, 70))
	end
	if scanYawTarget then
		local _, yaw = rootPart.CFrame:ToOrientation()
		local diff = (scanYawTarget - yaw + math.pi) % (2 * math.pi) - math.pi
		local step = math.clamp(diff, -math.rad(2), math.rad(2))
		rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, yaw + step, 0)
	end
end

local function runGuard()
	stopMoving()
	scan()
	if suspicion < CFG.SUSPICION_INVESTIGATE * 0.5 and not getSquadAlert() then
		-- Patrol-вариант: спустя GUARD_DURATION уходит в обход.
		if CFG.BEHAVIOR_VARIANT == "Patrol" and #patrolPoints > 0 and stateAge() >= CFG.GUARD_DURATION then
			setState(STATE.PATROL)
		end
	end
end

local function runPatrol()
	if #patrolPoints == 0 then
		setState(STATE.GUARD)
		return
	end
	local target = patrolPoints[patrolIndex]
	if flatDistance(rootPart.Position, target) > CFG.PATROL_POINT_REACH then
		navigateTo(target, CFG.PATROL_SPEED)
		patrolPauseUntil = 0
	else
		stopMoving()
		scan()
		if patrolPauseUntil == 0 then
			patrolPauseUntil = os.clock() + math.random(CFG.PATROL_PAUSE_MIN, CFG.PATROL_PAUSE_MAX)
		elseif os.clock() >= patrolPauseUntil then
			patrolPauseUntil = 0
			patrolIndex = patrolIndex % #patrolPoints + 1
		end
	end
end

local function runInvestigate()
	local target = lastKnownPosition or homePosition
	if flatDistance(rootPart.Position, target) > CFG.PATROL_POINT_REACH then
		navigateTo(target, CFG.PATROL_SPEED)
	else
		stopMoving()
		scan()
		if suspicion < CFG.SUSPICION_INVESTIGATE * 0.5 and not getSquadAlert() then
			setState(STATE.RETURN)
		end
	end
end

-- Слитые Chase+Attack: дальше радиуса — бежим к цели; в радиусе — бьём.
local function runChase(visibleRoot)
	if not visibleRoot then
		setState(STATE.SEARCH)
		return
	end
	lastKnownPosition = visibleRoot.Position
	local dist = flatDistance(rootPart.Position, visibleRoot.Position)
	if dist <= CFG.ATTACK_RANGE then
		stopMoving()
		faceTowards(visibleRoot.Position)
		local character = visibleRoot.Parent
		local h = character and getCharacterHumanoid(character)
		if h then
			attackTarget(visibleRoot, h)
		end
	else
		navigateTo(visibleRoot.Position, CFG.CHASE_SPEED)
	end
end

local function runSearch()
	local target = lastKnownPosition or homePosition
	if flatDistance(rootPart.Position, target) > CFG.PATROL_POINT_REACH then
		navigateTo(target, CFG.CHASE_SPEED)
	else
		stopMoving()
		scan()
	end
	if suspicion <= 0 or stateAge() >= CFG.SEARCH_DURATION then
		chaseTarget = nil
		setState(STATE.RETURN)
	end
end

local function runReturn()
	if flatDistance(rootPart.Position, homePosition) > CFG.PATROL_POINT_REACH then
		navigateTo(homePosition, CFG.PATROL_SPEED)
	else
		stopMoving()
		faceTowards(rootPart.Position + homeLook)
		setState(STATE.GUARD)
	end
end

local function runAlerted()
	local pos = getSquadAlert()
	if not pos then
		setState(STATE.RETURN)
		return
	end
	if flatDistance(rootPart.Position, pos) > CFG.SQUAD_ENGAGE_RADIUS then
		navigateTo(pos, CFG.CHASE_SPEED)
	else
		lastKnownPosition = pos
		setState(STATE.INVESTIGATE)
	end
end

--====================================================
-- IDLE-СТОЙКА: спокойная (Animation1) / тревожная (Animation2)
--====================================================
-- Ходьбу/бег ведёт штатный Animate, а idle мы переопределяем сами: когда пират стоит
-- (не идёт и не бьёт) — играем нужный idle на приоритете Action (он перебивает
-- штатный случайный idle и не конфликтует с ходьбой, т.к. на ходу мы его гасим).
-- Спокойный — когда никого не преследует; тревожный — когда есть chaseTarget.

-- Найти idle-анимацию: сперва Animation у скрипта (Idle/Idle2), затем штатный
-- Animate — папка idle/<childName> (Animation1/Animation2).
local function resolveIdleAnim(scriptChild, animateChild)
	local a = script:FindFirstChild(scriptChild)
	if a and a:IsA("Animation") then return a end
	local animate = npc:FindFirstChild("Animate")
	local idleFolder = animate and animate:FindFirstChild("idle")
	local b = idleFolder and idleFolder:FindFirstChild(animateChild)
	if b and b:IsA("Animation") then return b end
	return nil
end

local idleCalmTrack, idleAlertTrack
do
	local calmAnim  = resolveIdleAnim("Idle",  "Animation1")
	local alertAnim = resolveIdleAnim("Idle2", "Animation2")
	if calmAnim then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		idleCalmTrack = animator:LoadAnimation(calmAnim)
		idleCalmTrack.Looped = true
		idleCalmTrack.Priority = Enum.AnimationPriority.Action
		if alertAnim then
			idleAlertTrack = animator:LoadAnimation(alertAnim)
			idleAlertTrack.Looped = true
			idleAlertTrack.Priority = Enum.AnimationPriority.Action
		else
			idleAlertTrack = idleCalmTrack
			warn("[PirateGuardAI] Второй idle (преследование) не найден — будет обычный idle")
		end
	else
		warn("[PirateGuardAI] Idle-анимация не найдена (script.Idle или Animate/idle/Animation1) — переключение idle отключено")
	end
end

-- Зовётся каждый кадр: на ходу/в атаке гасим свой idle (играет Animate/attack),
-- стоя — играем спокойный или тревожный по наличию цели преследования.
local function updateIdleAnim()
	if not idleCalmTrack then return end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local attacking = attackTrack and attackTrack.IsPlaying
	if moving or attacking then
		if idleCalmTrack.IsPlaying then idleCalmTrack:Stop(0.15) end
		if idleAlertTrack ~= idleCalmTrack and idleAlertTrack.IsPlaying then idleAlertTrack:Stop(0.15) end
		return
	end
	local want = (chaseTarget and idleAlertTrack) or idleCalmTrack
	local other = (want == idleCalmTrack) and idleAlertTrack or idleCalmTrack
	if other ~= want and other.IsPlaying then other:Stop(0.2) end
	if not want.IsPlaying then want:Play(0.2) end
end

--====================================================
-- ГЛАВНЫЙ ЦИКЛ
--====================================================

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 or not rootPart.Parent then
		return
	end

	updateIdleAnim() -- спокойный/тревожный idle по состоянию преследования

	local visibleRoot, visibleChar = updatePerception(dt)

	-- Спад подозрения (в погоне не падает; в проверке/поиске — после прихода на точку).
	if not visibleRoot then
		local allowDecay = true
		if currentState == STATE.CHASE then
			allowDecay = false
		elseif currentState == STATE.INVESTIGATE or currentState == STATE.SEARCH then
			local spot = lastKnownPosition or homePosition
			allowDecay = flatDistance(rootPart.Position, spot) <= CFG.PATROL_POINT_REACH
		end
		if allowDecay then
			suspicion = math.max(0, suspicion - CFG.SUSPICION_DECAY * dt)
		end
	end
	updateSuspicionBar()

	-- Эскалация по подозрению.
	if suspicion >= CFG.SUSPICION_ALERT and visibleRoot then
		chaseTarget = visibleChar
		if currentState ~= STATE.CHASE then
			broadcastAlert() -- первый крик
		end
		setState(STATE.CHASE)
	elseif suspicion >= CFG.SUSPICION_INVESTIGATE
		and (currentState == STATE.GUARD or currentState == STATE.PATROL or currentState == STATE.RETURN) then
		setState(STATE.INVESTIGATE)
	end

	-- Перекрикиваем в бою, обновляя позицию игрока для отряда.
	if currentState == STATE.CHASE and os.clock() - lastShoutClock >= CFG.SHOUT_INTERVAL then
		broadcastAlert()
	end

	-- Реакция на чужой крик, если сами ещё не в бою.
	local squadPos = getSquadAlert()
	if squadPos and currentState ~= STATE.CHASE then
		local player = (alertUserId and alertUserId > 0) and Players:GetPlayerByUserId(alertUserId)
		if player and player.Character and isAliveCharacter(player.Character) then
			chaseTarget = player.Character
		end
		if flatDistance(rootPart.Position, squadPos) <= CFG.SQUAD_ENGAGE_RADIUS then
			lastKnownPosition = squadPos
			if currentState ~= STATE.INVESTIGATE then
				setState(STATE.INVESTIGATE)
			end
		elseif currentState == STATE.GUARD or currentState == STATE.PATROL or currentState == STATE.RETURN then
			setState(STATE.ALERTED)
		end
	end

	-- Видим назначенную цель (LOS + радиус, без FOV) → сразу в бой.
	local chaseVisibleRoot = nil
	if chaseTarget then
		local root = getCharacterRoot(chaseTarget)
		if root and isAliveCharacter(chaseTarget) then
			local flat = flatDistance(rootPart.Position, root.Position)
			if flat <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
				chaseVisibleRoot = root
			elseif flat <= CFG.SIGHT_RANGE and canSeeCharacter(root) then
				chaseVisibleRoot = root
			end
		end
	end
	if chaseVisibleRoot and currentState ~= STATE.CHASE then
		setState(STATE.CHASE)
	end

	-- Безусловный рефлекс: игрок вплотную → сразу цель и бой.
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and isAliveCharacter(character) then
			local root = getCharacterRoot(character)
			if root and flatDistance(rootPart.Position, root.Position) <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
				chaseTarget = character
				chaseVisibleRoot = root
				if currentState ~= STATE.CHASE then
					broadcastAlert()
					setState(STATE.CHASE)
				end
				break
			end
		end
	end

	if currentState == STATE.GUARD then
		runGuard()
	elseif currentState == STATE.PATROL then
		runPatrol()
	elseif currentState == STATE.INVESTIGATE then
		runInvestigate()
	elseif currentState == STATE.CHASE then
		runChase(chaseVisibleRoot)
	elseif currentState == STATE.SEARCH then
		runSearch()
	elseif currentState == STATE.RETURN then
		runReturn()
	elseif currentState == STATE.ALERTED then
		runAlerted()
	end
end)

print(string.format(
	"[PirateGuardAI] Humanoid guard loaded. Variant=%s PatrolPoints=%d Rig=%s",
	CFG.BEHAVIOR_VARIANT, #patrolPoints, npc.Name
))
