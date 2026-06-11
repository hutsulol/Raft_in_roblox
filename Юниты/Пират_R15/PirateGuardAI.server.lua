--[[
	PirateGuardAI v5-clean — сторож-пират на Humanoid (R6/R15). ПЕРЕПИСАН С НУЛЯ:
	без чужого кода, без PathfindingService (никаких NoPath), один аним-драйвер.

	КАК СТАВИТЬ: один ЭТОТ Script внутрь модели пирата. Штатный Animate удалить.
	Анимации лежат ПЛОСКО в любой папке модели (имена с альтернативами):
	  Animation1|Idle   — спокойная стойка (никого не преследует)
	  Animation2|Idle2  — тревожная стойка (есть цель преследования)
	  WalkAnim|Walk     — шаг (патруль/проверка/поиск/возврат)
	  RunAnim|Run       — бег (погоня)
	  JumpAnim / FallAnim — прыжок / полёт (опционально)
	  Attack            — Animation РЕБЁНКОМ этого скрипта (замах)

	ПОВЕДЕНИЕ:
	  • Зрение: конус (спереди быстро, сбоку медленно) + Raycast-LOS; шкала
	    подозрения 0..100 с полосой над головой; вплотную — мгновенная агрессия.
	  • УВИДЕЛ → сразу CHASE: бежит ПРЯМО на игрока (CHASE_SPEED + RunAnim),
	    в радиусе бьёт (анимация Attack + урон с задержкой под замах).
	  • Потерял из виду → SEARCH шагом к последней точке, осмотрелся → RETURN на пост.
	  • Подозрение 50+ без прямой видимости → INVESTIGATE шагом.
	  • Отряд: при старте погони кричит соседям с тегом PirateGuard — те идут
	    проверять точку крика.
	  • Патруль: папка PatrolPoints с партами внутри модели — ходит по кругу
	    с паузами; нет папки — стоит на посту.
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local npc = script.Parent

--====================================================
-- НАСТРОЙКИ
--====================================================

local CFG = {
	-- скорости
	WALK_SPEED  = 8,    -- шаг: патруль/проверка/поиск/возврат
	CHASE_SPEED = 18,   -- бег: только при видимой цели

	-- бой
	ATTACK_RANGE     = 6,
	ATTACK_COOLDOWN  = 1.2,
	ATTACK_DAMAGE    = 20,
	ATTACK_HIT_DELAY = 0.25, -- урон под замах анимации

	-- зрение/подозрение
	SIGHT_RANGE   = 50,
	FOV_FRONT_DEG = 50,   -- в этом конусе подозрение растёт быстро
	FOV_SIDE_DEG  = 110,  -- в этом — медленно; дальше не видит
	EYE_HEIGHT    = 1.5,
	GAIN_FRONT    = 90,   -- ед/сек на близкой дистанции
	GAIN_SIDE     = 35,
	DECAY         = 25,   -- спад подозрения вне видимости
	INVESTIGATE_AT = 50,  -- порог «пойти проверить»
	MELEE_REFLEX  = 8,    -- ближе этого — мгновенная агрессия (даже сзади)

	-- поиск/возврат
	SEARCH_DURATION = 8,  -- сколько осматривается у последней точки
	REACH           = 3,  -- «дошёл», если ближе

	-- патруль
	PATROL_FOLDER    = "PatrolPoints",
	PATROL_PAUSE_MIN = 8,
	PATROL_PAUSE_MAX = 20,

	-- отряд
	GUARD_TAG      = "PirateGuard",
	SHOUT_RADIUS   = 60,
	SHOUT_INTERVAL = 4,
	ALERT_FRESH    = 6,   -- сколько секунд чужой крик считается актуальным

	-- застревание
	STUCK_TIME     = 1.2, -- почти не двигаемся столько секунд → шаг вбок
	STUCK_DIST     = 0.5,
}

--====================================================
-- РИГ
--====================================================

local humanoid = npc:FindFirstChildOfClass("Humanoid")
do
	local waited = 0
	while not humanoid and waited < 5 do
		task.wait(0.1)
		waited += 0.1
		humanoid = npc:FindFirstChildOfClass("Humanoid")
	end
end
if not humanoid then
	warn("[PirateGuardAI] Humanoid не найден — скрипт не запущен")
	return
end

local rootPart = npc:FindFirstChild("HumanoidRootPart") or humanoid.RootPart
	or npc:WaitForChild("HumanoidRootPart", 5)
if not rootPart then
	warn("[PirateGuardAI] HumanoidRootPart не найден — скрипт не запущен")
	return
end

local head = npc:FindFirstChild("Head") or rootPart

if not npc.PrimaryPart then
	npc.PrimaryPart = rootPart
end

for _, d in ipairs(npc:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = false
	end
end
humanoid.WalkSpeed = CFG.WALK_SPEED
humanoid.AutoRotate = true
pcall(function()
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
end)

-- Физика всегда на сервере (иначе владение прыгает на клиента → рывки на бегу).
task.defer(function()
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
end)

CollectionService:AddTag(npc, CFG.GUARD_TAG)

-- Все анимации играем САМИ. Если в риге остался штатный Animate (или его копия) —
-- он дерётся за walk/run/idle и подсовывает свои (часто placeholder) анимации.
-- Убиваем его и гасим всё, что он успел запустить, чтобы остаться единственным
-- хозяином анимаций.
do
	local function looksLikeAnimate(s)
		local n = s.Name:lower()
		return n == "animate" or n:find("animate") ~= nil
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if (d:IsA("Script") or d:IsA("LocalScript")) and d ~= script and looksLikeAnimate(d)
			and not d:FindFirstAncestorOfClass("Tool") then
			warn("[PirateGuardAI] убираю конфликтующий Animate: " .. d:GetFullName())
			d.Disabled = true
			d:Destroy()
		end
	end
	local existingAnimator = humanoid:FindFirstChildOfClass("Animator")
	if existingAnimator then
		task.defer(function()
			for _, t in ipairs(existingAnimator:GetPlayingAnimationTracks()) do
				t:Stop(0)
			end
		end)
	end
end

local homePosition = rootPart.Position
local homeLook = rootPart.CFrame.LookVector

--====================================================
-- ХЕЛПЕРЫ
--====================================================

local function flatDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true
raycastParams.FilterDescendantsInstances = { npc }

local function getCharacterRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function isAliveCharacter(character)
	local h = character and character:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- Видна ли цель (стены рвут обзор).
local function canSee(targetRoot)
	local origin = head.Position + Vector3.new(0, CFG.EYE_HEIGHT - 1, 0)
	local result = workspace:Raycast(origin, targetRoot.Position - origin, raycastParams)
	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end
	return true
end

-- Развернуться к точке (по горизонтали), стоя на месте.
local function faceTowards(pos)
	local flat = Vector3.new(pos.X, rootPart.Position.Y, pos.Z)
	if (flat - rootPart.Position).Magnitude > 0.1 then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, flat)
	end
end

--====================================================
-- АНИМАЦИИ (всё играем сами; штатного Animate в риге НЕТ)
--====================================================

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local function findAnim(names)
	for _, want in ipairs(names) do
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("Animation") and d.Name == want then
				return d
			end
		end
	end
	return nil
end

local function loadTrack(label, names, priority, looped)
	local a = findAnim(names)
	if not a then
		warn(("[PirateGuardAI] анимация «%s» не найдена (искал: %s)"):format(label, table.concat(names, ", ")))
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if not ok or not track then
		warn(("[PirateGuardAI] не удалось загрузить «%s» (%s)"):format(label, a:GetFullName()))
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local idleCalmTrack  = loadTrack("idle спокойный", { "Animation1", "Idle", "IdleAnim" }, Enum.AnimationPriority.Idle, true)
local idleAlertTrack = loadTrack("idle тревожный", { "Animation2", "Idle2" },            Enum.AnimationPriority.Idle, true) or idleCalmTrack
local walkTrack      = loadTrack("ходьба",         { "WalkAnim", "Walk" },               Enum.AnimationPriority.Movement, true)
local runTrack       = loadTrack("бег",            { "RunAnim", "Run" },                 Enum.AnimationPriority.Movement, true) or walkTrack
local jumpTrack      = loadTrack("прыжок",         { "JumpAnim", "Jump" },               Enum.AnimationPriority.Movement, false)
local fallTrack      = loadTrack("падение",        { "FallAnim", "Fall" },               Enum.AnimationPriority.Movement, true)

local attackTrack = nil
do
	local attackAnim = script:FindFirstChild("Attack")
	if attackAnim and attackAnim:IsA("Animation") then
		local ok, track = pcall(function()
			return animator:LoadAnimation(attackAnim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			attackTrack = track
		end
	end
	if not attackTrack then
		warn("[PirateGuardAI] анимация «Attack» (ребёнок скрипта) не найдена — бой без замаха")
	end
end

-- Ровно ОДИН активный трек локомоции за раз — смешение walk+run исключено.
local currentLoco = nil
local function playLoco(track, fade)
	fade = fade or 0.15
	if currentLoco == track then
		if track and not track.IsPlaying then track:Play(fade) end
		return
	end
	if currentLoco and currentLoco.IsPlaying then
		currentLoco:Stop(fade)
	end
	currentLoco = track
	if track and not track.IsPlaying then
		track:Play(fade)
	end
end

local airborne = false
humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Jumping then
		airborne = true
		if jumpTrack then
			jumpTrack:Play(0.1)
		end
	elseif new == Enum.HumanoidStateType.Freefall then
		airborne = true
	elseif new == Enum.HumanoidStateType.Landed
		or new == Enum.HumanoidStateType.Running
		or new == Enum.HumanoidStateType.RunningNoPhysics then
		airborne = false
	end
end)

local chaseTarget = nil -- forward (нужен аниматору для тревожной стойки)

local stillSince = nil
local function updateAnimations()
	if airborne then
		stillSince = nil
		playLoco(fallTrack or runTrack or walkTrack, 0.1)
		return
	end

	if humanoid.MoveDirection.Magnitude > 0.05 then
		stillSince = nil
		local runMode = humanoid.WalkSpeed > (CFG.WALK_SPEED + CFG.CHASE_SPEED) / 2
		playLoco(runMode and runTrack or walkTrack)
		return
	end

	-- гистерезис остановки: микропаузы движения не мигают idle поверх бега
	stillSince = stillSince or os.clock()
	if os.clock() - stillSince < 0.15 then
		return
	end

	if attackTrack and attackTrack.IsPlaying then
		playLoco(nil, 0.1) -- замах (Action) играет сам
		return
	end

	playLoco((chaseTarget and idleAlertTrack) or idleCalmTrack, 0.2)
end

--====================================================
-- ДВИЖЕНИЕ (прямой MoveTo + прыжок через мелочь + анти-застревание)
--====================================================

local lastJumpCheck = 0
local function jumpCheck(goal)
	if os.clock() - lastJumpCheck < 0.5 then return end
	lastJumpCheck = os.clock()
	local dir = Vector3.new(goal.X - rootPart.Position.X, 0, goal.Z - rootPart.Position.Z)
	if dir.Magnitude < 0.1 then return end
	local origin = rootPart.Position + Vector3.new(0, -1.5, 0)
	if workspace:Raycast(origin, dir.Unit * 3, raycastParams) then
		humanoid.Jump = true
	end
end

local stuckPos, stuckSince = nil, nil
local function moveTo(goal, speed)
	humanoid.WalkSpeed = speed
	jumpCheck(goal)
	humanoid:MoveTo(goal)

	-- почти не двигаемся, а цель далеко → шаг вбок, чтобы соскочить с угла
	if stuckPos and (rootPart.Position - stuckPos).Magnitude > CFG.STUCK_DIST then
		stuckPos, stuckSince = rootPart.Position, os.clock()
	elseif not stuckPos then
		stuckPos, stuckSince = rootPart.Position, os.clock()
	elseif os.clock() - stuckSince > CFG.STUCK_TIME
		and flatDistance(rootPart.Position, goal) > CFG.REACH then
		local dir = (Vector3.new(goal.X, 0, goal.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z))
		if dir.Magnitude > 0.1 then
			local side = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X) * 4
			if math.random() < 0.5 then side = -side end
			humanoid.Jump = true
			humanoid:MoveTo(rootPart.Position + side)
		end
		stuckPos, stuckSince = rootPart.Position, os.clock()
	end
end

local function stopMoving()
	humanoid:MoveTo(rootPart.Position)
	stuckPos, stuckSince = nil, nil
end

--====================================================
-- ШКАЛА ПОДОЗРЕНИЯ (полоса над головой)
--====================================================

local suspicion = 0
local lastKnownPosition = nil

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
	if chaseTarget then
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	elseif suspicion >= CFG.INVESTIGATE_AT then
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
	else
		suspicionFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

--====================================================
-- ВОСПРИЯТИЕ (конус зрения + LOS)
--====================================================

-- Возвращает видимый root/character ближайшего игрока и копит подозрение.
local function updatePerception(dt)
	local bestRoot, bestChar, bestDist = nil, nil, math.huge
	local lookDir = rootPart.CFrame.LookVector

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local targetRoot = getCharacterRoot(character)
		if targetRoot and isAliveCharacter(character) then
			local offset = targetRoot.Position - head.Position
			local dist = offset.Magnitude
			if dist <= CFG.SIGHT_RANGE then
				local melee = dist <= CFG.MELEE_REFLEX
				local angle = math.deg(math.acos(math.clamp(
					lookDir:Dot(Vector3.new(offset.X, 0, offset.Z).Unit), -1, 1)))
				if (melee or angle <= CFG.FOV_SIDE_DEG / 2) and canSee(targetRoot) then
					local gain
					if melee then
						gain = 1000 -- вплотную — мгновенно
					elseif angle <= CFG.FOV_FRONT_DEG / 2 then
						gain = CFG.GAIN_FRONT
					else
						gain = CFG.GAIN_SIDE
					end
					local distFactor = 1 - 0.6 * math.clamp(dist / CFG.SIGHT_RANGE, 0, 1)
					suspicion = math.min(100, suspicion + gain * distFactor * dt)
					if dist < bestDist then
						bestRoot, bestChar, bestDist = targetRoot, character, dist
					end
				end
			end
		end
	end

	return bestRoot, bestChar
end

--====================================================
-- ОТРЯД (крик соседям с тем же тегом)
--====================================================

local lastShout = 0
local function broadcastShout(pos)
	if os.clock() - lastShout < CFG.SHOUT_INTERVAL then return end
	lastShout = os.clock()
	for _, other in ipairs(CollectionService:GetTagged(CFG.GUARD_TAG)) do
		if other ~= npc and other.Parent then
			local otherRoot = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart")
			if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude <= CFG.SHOUT_RADIUS then
				other:SetAttribute("SquadAlertPos", pos)
				other:SetAttribute("SquadAlertAt", os.clock())
			end
		end
	end
end

-- Свежий чужой крик (или nil).
local function getSquadAlert()
	local at = npc:GetAttribute("SquadAlertAt")
	if at and os.clock() - at <= CFG.ALERT_FRESH then
		return npc:GetAttribute("SquadAlertPos")
	end
	return nil
end

--====================================================
-- БОЙ
--====================================================

local lastAttack = 0
local function tryAttack(targetRoot, targetHumanoid)
	if os.clock() - lastAttack < CFG.ATTACK_COOLDOWN then return end
	lastAttack = os.clock()

	if attackTrack then
		attackTrack:Play(0.05)
	end
	task.delay(CFG.ATTACK_HIT_DELAY, function()
		if not targetRoot.Parent or not targetHumanoid.Parent then return end
		if targetHumanoid.Health <= 0 then return end
		if (targetRoot.Position - rootPart.Position).Magnitude <= CFG.ATTACK_RANGE + 2 then
			targetHumanoid:TakeDamage(CFG.ATTACK_DAMAGE)
		end
	end)
end

--====================================================
-- ПАТРУЛЬ
--====================================================

local patrolPoints = {}
do
	local folder = npc:FindFirstChild(CFG.PATROL_FOLDER)
	if folder then
		for _, p in ipairs(folder:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(patrolPoints, p.Position)
				p.Anchored = true
				p.CanCollide = false
				p.Transparency = 1
			end
		end
	end
end
local patrolIndex = 1
local patrolPauseUntil = 0

--====================================================
-- FSM
--====================================================

local STATE = { GUARD = "Guard", PATROL = "Patrol", INVESTIGATE = "Investigate",
	CHASE = "Chase", SEARCH = "Search", RETURN = "Return" }

local currentState = STATE.GUARD
local stateClock = os.clock()

local function setState(s)
	if currentState == s then return end
	currentState = s
	stateClock = os.clock()
end

local function stateAge()
	return os.clock() - stateClock
end

local function runGuard()
	stopMoving()
	if #patrolPoints > 0 and stateAge() > 4 then
		setState(STATE.PATROL)
	end
end

local function runPatrol()
	if #patrolPoints == 0 then
		setState(STATE.GUARD)
		return
	end
	local target = patrolPoints[patrolIndex]
	if flatDistance(rootPart.Position, target) > CFG.REACH then
		moveTo(target, CFG.WALK_SPEED)
		patrolPauseUntil = 0
	else
		stopMoving()
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
	if flatDistance(rootPart.Position, target) > CFG.REACH then
		moveTo(target, CFG.WALK_SPEED)
	else
		stopMoving()
		suspicion = math.max(0, suspicion - CFG.DECAY * 0.5 * (1 / 60))
		if suspicion < CFG.INVESTIGATE_AT * 0.5 then
			setState(STATE.RETURN)
		end
	end
end

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
		local h = visibleRoot.Parent and visibleRoot.Parent:FindFirstChildOfClass("Humanoid")
		if h then
			tryAttack(visibleRoot, h)
		end
	else
		-- цель видима → бежим ПРЯМО на неё (никакого pathfinding и зигзагов)
		moveTo(visibleRoot.Position, CFG.CHASE_SPEED)
	end
end

local function runSearch()
	local target = lastKnownPosition or homePosition
	if flatDistance(rootPart.Position, target) > CFG.REACH then
		moveTo(target, CFG.WALK_SPEED) -- игрок вне поля зрения → шагом
	else
		stopMoving()
	end
	if suspicion <= 0 or stateAge() >= CFG.SEARCH_DURATION then
		chaseTarget = nil
		setState(STATE.RETURN)
	end
end

local function runReturn()
	if flatDistance(rootPart.Position, homePosition) > CFG.REACH then
		moveTo(homePosition, CFG.WALK_SPEED)
	else
		stopMoving()
		faceTowards(rootPart.Position + homeLook)
		setState(STATE.GUARD)
	end
end

--====================================================
-- ГЛАВНЫЙ ЦИКЛ
--====================================================

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 or not rootPart.Parent then
		return
	end

	local visibleRoot, visibleChar = updatePerception(dt)

	-- спад подозрения вне видимости (в погоне не падает)
	if not visibleRoot and currentState ~= STATE.CHASE then
		suspicion = math.max(0, suspicion - CFG.DECAY * dt)
	end
	updateSuspicionBar()

	-- УВИДЕЛ → сразу погоня бегом + крик отряду
	if visibleRoot then
		chaseTarget = visibleChar
		if currentState ~= STATE.CHASE then
			setState(STATE.CHASE)
		end
		broadcastShout(visibleRoot.Position)
	elseif suspicion >= CFG.INVESTIGATE_AT
		and (currentState == STATE.GUARD or currentState == STATE.PATROL or currentState == STATE.RETURN) then
		setState(STATE.INVESTIGATE)
	end

	-- чужой крик: идём проверять, если сами не в бою
	local alertPos = getSquadAlert()
	if alertPos and currentState ~= STATE.CHASE then
		lastKnownPosition = alertPos
		suspicion = math.max(suspicion, CFG.INVESTIGATE_AT)
		if currentState ~= STATE.INVESTIGATE and currentState ~= STATE.SEARCH then
			setState(STATE.INVESTIGATE)
		end
	end

	updateAnimations()

	if currentState == STATE.GUARD then
		runGuard()
	elseif currentState == STATE.PATROL then
		runPatrol()
	elseif currentState == STATE.INVESTIGATE then
		runInvestigate()
	elseif currentState == STATE.CHASE then
		runChase(visibleRoot)
	elseif currentState == STATE.SEARCH then
		if visibleRoot then
			setState(STATE.CHASE)
		else
			runSearch()
		end
	elseif currentState == STATE.RETURN then
		runReturn()
	end
end)

--====================================================
-- ДИАГНОСТИКА
--====================================================

local function ts(t) return t and "OK" or "НЕТ" end
print(string.format(
	"[PirateGuardAI v6-anim] %s | PatrolPoints=%d Rig=%s | аним: idle1=%s idle2=%s walk=%s run=%s jump=%s fall=%s attack=%s",
	script:GetFullName(), #patrolPoints, npc.Name,
	ts(idleCalmTrack), ts(idleAlertTrack), ts(walkTrack), ts(runTrack),
	ts(jumpTrack), ts(fallTrack), ts(attackTrack)
))

-- Другой ИИ/Animate в этой же модели = драка за анимации/движение. Кричим.
local HARMLESS_SCRIPTS = {
	ChangeFaceOnDeath = true, ChangeFaceOnFullHealth = true,
	Ragdoller = true, Health = true, Sound = true, Respawn = true,
}
for _, d in ipairs(npc:GetDescendants()) do
	if (d:IsA("Script") or d:IsA("LocalScript")) and d ~= script
		and not HARMLESS_SCRIPTS[d.Name]
		and not d:FindFirstAncestorOfClass("Tool") then
		warn("[PirateGuardAI] ⚠ посторонний скрипт в модели: " .. d:GetFullName() ..
			" — если это другой ИИ или Animate, УДАЛИ/отключи его")
	end
end
