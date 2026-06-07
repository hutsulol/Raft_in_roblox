local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local npc = script.Parent

-- ВЕСЬ КОНФИГ В ОДНОЙ ТАБЛИЦЕ — чтобы не упираться в лимит 200 локалов
-- Luau. Новые настройки добавляй сюда полями, а не отдельными local.
local CFG = {
	VISUAL_MESH_NAME = "Pirate",
	BODY_COLLIDERS_NAME = "BodyColliders",
	IDLE_ANIMATION_NAME = "Idle",
	WALK_ANIMATION_NAME = "Walk",
	RUN_ANIMATION_NAME = "Run",
	ATTACK_ANIMATION_NAME = "Attack",
	ROOT_COLLIDER_NAME = "TorsoCollider",
	UNIT_MAX_HEALTH = 15,
	DESTROY_ON_DEATH = true,
	DEATH_DESTROY_DELAY = 0.6, -- через сколько секунд после смерти убрать тело
	DEBUG_VISIBLE = false,
	MODEL_YAW_OFFSET_DEGREES = 180,
	MOVE_SPEED = 10,
	RUN_SPEED_MULTIPLIER = 1.5,
	ATTACK_RANGE = 4.2, -- зазор до поверхности тела (к нему прибавляется габарит торса)
	ATTACK_RANGE_BUFFER = 2,
	ATTACK_COOLDOWN = 1.4,
	ATTACK_DAMAGE = 20,
	ATTACK_HIT_DELAY = 0.35,
	FORCE_DIRECT_ROTATION = true,
	BEHAVIOR_VARIANT = "Guard",
	PATROL_POINTS_FOLDER_NAME = "PatrolPoints",
	GUARD_DURATION = 60,
	PATROL_POINT_REACH = 3,
	PATROL_PAUSE_MIN = 10,
	PATROL_PAUSE_MAX = 30,
	SIGHT_RANGE = 50,
	FOV_FRONT_DEGREES = 50,
	FOV_SIDE_DEGREES = 110,
	EYE_HEIGHT_OFFSET = 1,
	SUSPICION_GAIN_FRONT = 90,
	SUSPICION_GAIN_SIDE = 35,
	SUSPICION_DECAY = 25,
	SUSPICION_INVESTIGATE = 50,
	SUSPICION_ALERT = 100,
	SEARCH_DURATION = 15,
	GUARD_TAG = "PirateGuard",
	SQUAD_ALERT_RADIUS = 200,
	SQUAD_ENGAGE_RADIUS = 60,
	ALERT_MEMORY = 8,
	SHOUT_INTERVAL = 2,
	DEBUG_SQUAD = true,
	AGENT_RADIUS = 2,
	AGENT_HEIGHT = 5,
	PATH_RECOMPUTE_INTERVAL = 0.5,
	PATH_GOAL_MOVE_THRESHOLD = 5,
	WAYPOINT_REACH = 2,
	NAV_LOS_MARGIN = 4,
	TURN_SPEED_DEGREES = 420,
	LEG_GROUND_PADDING = 0.06,
	LEG_GROUND_RAYCAST_HEIGHT = 8,
	LEG_GROUND_RAYCAST_DEPTH = 16,
	MAX_GROUND_LIFT_PER_HEARTBEAT = 0.25,
	-- Авто-шаг: плавный заход на невысокие возвышенности без прыжка.
	STEP_ENABLED = true,             -- выключатель авто-шага (для диагностики: false → совсем не шагает)
	STEP_MAX_HEIGHT = 2.2,           -- макс. высота ступеньки (держим ниже MAX_HOVER_ABOVE_GROUND, чтобы заход не цеплял анти-подброс)
	STEP_MIN_RISE = 0.15,            -- ниже этого подъёма не считаем ступенькой (шум)
	STEP_PROBE_AHEAD = 1.6,          -- насколько вперёд от тела щупаем ступеньку
	STEP_CLIMB_SPEED = 14,           -- макс. вертикальная скорость захода на ступеньку, studs/сек
	STEP_CLIMB_MIN = 5,              -- мин. скорость подъёма (преодолеть гравитацию/трение)
	STEP_FORWARD_CLEARANCE = 1.8,    -- опора должна тянуться вперёд хотя бы на столько (иначе это тонкий гребень стены, не пол)
	STEP_TOP_MIN_NORMAL_Y = 0.93,    -- верх ступеньки должен быть ПЛОСКИМ (Normal.Y ≥ этого); отсекает скаты крыш/рампы/склоны
	STEP_CONTINUITY_TOL = 0.7,       -- на сколько за краем поверхность может просесть и ещё считаться сплошной
	RECOVER_DROP = 16,               -- если тело провалилось ниже последней валидной точки на земле на столько — вернуть назад
	-- Вода: плавания нет, но можно зайти в неё, а в воде — прыгать вперёд.
	WATER_WADE_DEPTH = 0.8,          -- ноги глубже этого под поверхностью → считаем, что в воде → прыгаем
	MAX_UPWARD_VELOCITY = 2.5,
	UNIT_TAG = "RaftMeleeUnit",
	SEPARATION_RADIUS = 4,
	SEPARATION_STRENGTH = 0.6,
	DEFAULT_WEAPON_DAMAGE = 10,
	HIT_REACH = 4.5,
	HIT_DEBOUNCE = 0.4,
	SHOW_HEALTH_BAR = true,
	MAX_HOVER_ABOVE_GROUND = 2.5,
}

--====================================================
-- НАСТРОЙКИ МОДЕЛИ
--====================================================





-- false = коллайдеры невидимые
-- true = коллайдеры видны для настройки

-- Если пират идёт спиной к игроку, пробуй 0 / 90 / -90 / 180

--====================================================
-- НАСТРОЙКИ ИИ
--====================================================



-- Если true, скрипт напрямую разворачивает TorsoCollider через CFrame.

--====================================================
-- ПОВЕДЕНИЕ: СТРАЖ / ЗРЕНИЕ / ПАМЯТЬ (Этап 1)
--====================================================

-- Вариант поведения (пока только «Страж»). Задел под будущие варианты.

-- ПАТРУЛЬ по ручным маркерам.
-- Внутри модели пирата создай Folder "PatrolPoints" и положи туда Part'ы
-- (или Attachment'ы) — пират обойдёт их по порядку имён и вернётся на пост.
-- Маркеры удобно сделать Anchored, CanCollide=false, Transparency=1.
-- Если папки нет/она пуста — пират просто охраняет точку спавна.

-- ЗРЕНИЕ (FOV + луч прямой видимости).

-- ПОДОЗРЕНИЕ 0..100.

-- ПАМЯТЬ / поиск.

-- ТРЕВОГА ОТРЯДА (Этап 2).

-- НАВИГАЦИЯ (Этап 3: PathfindingService — обход препятствий и воды).

-- Плавный разворот корпуса.

-- ПРЫЖОК через низкие препятствия — КИНЕМАТИЧЕСКИЙ (без Humanoid и без физических
-- импульсов: вся модель едет по дуге через CFrame). Всё в ОДНОЙ таблице, чтобы
-- не плодить локалы (в Luau лимит 200 локальных на скрипт).
local Jump = {
	HEIGHT = 6,            -- высота дуги, studs
	DISTANCE = 7,          -- на сколько вперёд перепрыгивает, studs
	DURATION = 0.55,       -- длительность прыжка, сек
	COOLDOWN = 1.0,        -- пауза между прыжками, сек
	CHECK_DISTANCE = 3.5,  -- препятствие ближе этого по курсу → прыжок
	CLEAR_HEIGHT = 5,      -- занято выше этого → преграда высокая, не прыгаем

	active = false,
	startClock = 0,
	lastClock = -math.huge,
	startPos = Vector3.zero,
	landPos = Vector3.zero,
	yaw = 0,
	canCollideBackup = {},
	offsets = {},
	assemblyParts = {},
	track = nil,
}

--====================================================
-- COLLISION GROUPS
--====================================================

local PLAYER_GROUP = "PlayerCharacters"
local NPC_BODY_GROUP = "PirateBody"
local NPC_LEGS_GROUP = "PirateLegs"
local NPC_GHOST_GROUP = "PirateGhost"
local DEFAULT_WORLD_GROUP = "Default"

-- Насколько выше пола держать низ коллайдеров ног.

-- Чтобы юниты не залезали друг на друга, помечаем их тегом. Это нужно для двух
-- вещей: (1) raycast «земли» игнорирует чужие хитбоксы (иначе юнит принимает
-- соседа за пол и встаёт на него как на ступеньку); (2) при движении юниты
-- мягко расходятся, а не занимают одну точку.

local COLLIDER_SETTINGS = {
	HeadCollider = {
		CanCollide = false,
		Group = NPC_GHOST_GROUP,
		Color = Color3.fromRGB(255, 80, 80),
	},

	TorsoCollider = {
		CanCollide = true,
		Group = NPC_BODY_GROUP,
		Color = Color3.fromRGB(0, 170, 255),
	},

	LeftLegCollider = {
		CanCollide = true,
		Group = NPC_LEGS_GROUP,
		Color = Color3.fromRGB(0, 255, 120),
	},

	RightLegCollider = {
		CanCollide = true,
		Group = NPC_LEGS_GROUP,
		Color = Color3.fromRGB(0, 255, 120),
	},

	LeftHandCollider = {
		CanCollide = false,
		Group = NPC_GHOST_GROUP,
		Color = Color3.fromRGB(255, 220, 0),
	},

	RightHandCollider = {
		CanCollide = false,
		Group = NPC_GHOST_GROUP,
		Color = Color3.fromRGB(255, 220, 0),
	},
}

local function registerCollisionGroup(groupName)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

registerCollisionGroup(PLAYER_GROUP)
registerCollisionGroup(NPC_BODY_GROUP)
registerCollisionGroup(NPC_LEGS_GROUP)
registerCollisionGroup(NPC_GHOST_GROUP)

PhysicsService:CollisionGroupSetCollidable(NPC_BODY_GROUP, PLAYER_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(NPC_LEGS_GROUP, PLAYER_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(NPC_GHOST_GROUP, PLAYER_GROUP, false)

-- Ноги должны быть физическими для земли, иначе Пират проваливается под пол.
-- При этом ноги всё ещё не сталкиваются с игроком, чтобы игрок не подкидывал NPC.
PhysicsService:CollisionGroupSetCollidable(NPC_LEGS_GROUP, DEFAULT_WORLD_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(NPC_BODY_GROUP, DEFAULT_WORLD_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(NPC_GHOST_GROUP, DEFAULT_WORLD_GROUP, false)

PhysicsService:CollisionGroupSetCollidable(NPC_BODY_GROUP, NPC_BODY_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(NPC_BODY_GROUP, NPC_LEGS_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(NPC_BODY_GROUP, NPC_GHOST_GROUP, false)

PhysicsService:CollisionGroupSetCollidable(NPC_LEGS_GROUP, NPC_LEGS_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(NPC_LEGS_GROUP, NPC_GHOST_GROUP, false)

PhysicsService:CollisionGroupSetCollidable(NPC_GHOST_GROUP, NPC_GHOST_GROUP, false)

local function setCharacterCollisionGroup(character)
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			object.CollisionGroup = PLAYER_GROUP
		end
	end

	character.DescendantAdded:Connect(function(object)
		if object:IsA("BasePart") then
			object.CollisionGroup = PLAYER_GROUP
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setCharacterCollisionGroup(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		setCharacterCollisionGroup(character)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setCharacterCollisionGroup(character)
	end)
end)

--====================================================
-- ПОИСК ОБЪЕКТОВ NPC
--====================================================

local visualMesh = npc:FindFirstChild(CFG.VISUAL_MESH_NAME, true)

if not visualMesh or not visualMesh:IsA("BasePart") then
	warn("[PirateUnitAI] Visual mesh not found:", CFG.VISUAL_MESH_NAME)
	return
end

local bodyColliders = npc:FindFirstChild(CFG.BODY_COLLIDERS_NAME)

if not bodyColliders then
	warn("[PirateUnitAI] BodyColliders not found")
	return
end

local colliders = {}

for _, object in ipairs(bodyColliders:GetDescendants()) do
	if object:IsA("BasePart") then
		table.insert(colliders, object)
	end
end

if #colliders == 0 then
	warn("[PirateUnitAI] No BasePart colliders found inside BodyColliders")
	return
end

local function findColliderPartByName(colliderName)
	for _, collider in ipairs(colliders) do
		if collider.Name == colliderName then
			return collider
		end
	end

	return nil
end

local rootCollider = findColliderPartByName(CFG.ROOT_COLLIDER_NAME)

if not rootCollider then
	warn("[PirateUnitAI] Root collider BasePart not found, using first collider:", colliders[1].Name)
	rootCollider = colliders[1]
end

local legColliders = {}

for _, collider in ipairs(colliders) do
	if collider.Name == "LeftLegCollider" or collider.Name == "RightLegCollider" then
		table.insert(legColliders, collider)
	end
end

if #legColliders == 0 then
	warn("[PirateUnitAI] Leg colliders not found. Create LeftLegCollider and RightLegCollider so Pirate can stand on the ground.")
end

npc.PrimaryPart = rootCollider

CollectionService:AddTag(npc, CFG.UNIT_TAG)
-- Отдельный тег только для пиратов — по нему идёт «крик» отряда (Этап 2).
CollectionService:AddTag(npc, CFG.GUARD_TAG)

--====================================================
-- HEALTH (без Humanoid)
--====================================================
-- ВАЖНО: Humanoid здесь НЕ используется специально.
-- Если добавить Humanoid в эту модель, он:
--   1) перехватывает воспроизведение анимаций у AnimationController
--      (у модели должен быть либо Humanoid, либо AnimationController,
--      но не оба сразу) — из-за этого анимации перестают играть;
--   2) запускает свою физическую state-machine (Running / Falling /
--      Ragdoll и т.д.), которая конфликтует с ручным движением через
--      AssemblyLinearVelocity, поворотом через AlignOrientation и
--      велдированными коллайдерами — из-за этого ломается физика.
-- Поэтому здоровье храним отдельно — в атрибутах модели, и даём
-- Humanoid-подобный API (TakeDamage / Heal / Died).

-- Подчищаем Humanoid, если он остался от прошлых экспериментов,
-- иначе анимации и физика снова сломаются.
for _, child in ipairs(npc:GetChildren()) do
	if child:IsA("Humanoid") then
		child:Destroy()
	end
end

local maxHealth = CFG.UNIT_MAX_HEALTH
npc:SetAttribute("MaxHealth", maxHealth)

do
	local startHealth = npc:GetAttribute("Health")
	if typeof(startHealth) ~= "number" then
		startHealth = maxHealth
	end
	npc:SetAttribute("Health", math.clamp(startHealth, 1, maxHealth))
end

local isDead = false

local function getHealth()
	local health = npc:GetAttribute("Health")
	return typeof(health) == "number" and health or 0
end

-- BindableEvent "Died": внешние системы (квесты, дроп лута) могут
-- слушать смерть юнита так же, как Humanoid.Died.
local diedEvent = npc:FindFirstChild("Died")
if not diedEvent or not diedEvent:IsA("BindableEvent") then
	diedEvent = Instance.new("BindableEvent")
	diedEvent.Name = "Died"
	diedEvent.Parent = npc
end

local function onDeath()
	if isDead then
		return
	end
	isDead = true

	npc:SetAttribute("Health", 0)

	if rootCollider.Parent then
		rootCollider.AssemblyLinearVelocity = Vector3.zero
		rootCollider.AssemblyAngularVelocity = Vector3.zero
	end

	diedEvent:Fire()

	if CFG.DESTROY_ON_DEATH then
		task.delay(CFG.DEATH_DESTROY_DELAY, function()
			if npc.Parent then
				npc:Destroy()
			end
		end)
	end
end

-- Любое изменение здоровья (через TakeDamage / Heal или напрямую
-- через атрибут Health из других скриптов) проходит здесь: держим
-- значение в границах 0..MaxHealth и ловим смерть.
npc:GetAttributeChangedSignal("Health"):Connect(function()
	if isDead then
		return
	end

	local health = npc:GetAttribute("Health")
	if typeof(health) ~= "number" then
		return
	end

	local clamped = math.clamp(health, 0, maxHealth)
	if clamped ~= health then
		-- SetAttribute снова вызовет этот обработчик, но уже с
		-- корректным значением, поэтому выходим.
		npc:SetAttribute("Health", clamped)
		return
	end

	if clamped <= 0 then
		onDeath()
	end
end)

-- Наносит урон юниту. Возвращает оставшееся здоровье.
local function takeDamage(amount)
	if isDead then
		return 0
	end

	amount = tonumber(amount) or 0
	if amount <= 0 then
		return getHealth()
	end

	npc:SetAttribute("Health", math.clamp(getHealth() - amount, 0, maxHealth))
	return getHealth()
end

-- Лечит юнита (добавляет HP). Возвращает текущее здоровье.
local function heal(amount)
	if isDead then
		return getHealth()
	end

	amount = tonumber(amount) or 0
	if amount <= 0 then
		return getHealth()
	end

	npc:SetAttribute("Health", math.clamp(getHealth() + amount, 0, maxHealth))
	return getHealth()
end

-- Humanoid-подобный API для оружия и других систем:
--   model.TakeDamage:Invoke(20)
--   model.Heal:Invoke(10)
local takeDamageFunction = npc:FindFirstChild("TakeDamage")
if not takeDamageFunction or not takeDamageFunction:IsA("BindableFunction") then
	takeDamageFunction = Instance.new("BindableFunction")
	takeDamageFunction.Name = "TakeDamage"
	takeDamageFunction.Parent = npc
end
takeDamageFunction.OnInvoke = takeDamage

local healFunction = npc:FindFirstChild("Heal")
if not healFunction or not healFunction:IsA("BindableFunction") then
	healFunction = Instance.new("BindableFunction")
	healFunction.Name = "Heal"
	healFunction.Parent = npc
end
healFunction.OnInvoke = heal

--====================================================
-- ХИТБОКС ПОЛУЧЕНИЯ УРОНА (по коллайдерам)
--====================================================
-- У юнита нет Humanoid, поэтому классический меч игрока
-- (Handle.Touched -> FindFirstChildOfClass("Humanoid")) не может его
-- ранить. Принимаем урон на стороне юнита: ловим взмах оружия игрока
-- (Tool.Activated) и проверяем, дотянулось ли оружие/игрок до любого
-- нашего коллайдера. Так не нужен Humanoid и не ломаются анимации/физика.
--
-- ВАЖНО: на collider.Touched полагаться нельзя — коллайдеры ног/головы/рук
-- лежат в коллизионных группах, несовместимых с группой игрока
-- (CollisionGroupSetCollidable = false), а это глушит и Touched. Поэтому
-- ловим попадание запросом по расстоянию до коллайдеров.

-- Урон по умолчанию, если у оружия не задан свой (атрибут/NumberValue "Damage").
-- На каком расстоянии до поверхности коллайдера засчитывается удар, studs.
-- Не чаще одного попадания от одного игрока за это время, сек.

local lastHitClock = {}
local hookedTools = setmetatable({}, { __mode = "k" })

local function getToolDamage(tool)
	local attribute = tool:GetAttribute("Damage")
	if typeof(attribute) == "number" and attribute > 0 then
		return attribute
	end

	local value = tool:FindFirstChild("Damage")
	if value and value:IsA("NumberValue") and value.Value > 0 then
		return value.Value
	end

	return CFG.DEFAULT_WEAPON_DAMAGE
end

-- Кратчайшее расстояние от точки до коробки коллайдера (OBB).
-- 0, если точка внутри коллайдера.
local function pointToColliderDistance(point, collider)
	local localPoint = collider.CFrame:PointToObjectSpace(point)
	local half = collider.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

-- Зазор от цели до ПОВЕРХНОСТИ ближайшего нашего коллайдера тела. Это тот же
-- расчёт, что и в хитбоксе игрока (pointToColliderDistance), поэтому «пират
-- дотянулся до тебя» симметрично «ты дотянулся до пирата». Не зависит от размера
-- и формы коллайдера — большой пират достаёт игрока, стоящего вплотную к нему,
-- даже когда центр коллайдера торса далеко.
local function targetGap(targetRoot)
	local point = targetRoot.Position
	local best = math.huge
	for _, collider in ipairs(colliders) do
		if collider.Parent then
			local d = pointToColliderDistance(point, collider)
			if d < best then
				best = d
			end
		end
	end
	return best
end

-- true, если оружие игрока (Handle) или сам игрок (HumanoidRootPart)
-- дотянулись до любого нашего коллайдера.
local function weaponReachesColliders(tool, character)
	local probeParts = {}

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		table.insert(probeParts, handle)
	end

	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		table.insert(probeParts, hrp)
	end

	if #probeParts == 0 then
		return false
	end

	for _, collider in ipairs(colliders) do
		if collider.Parent then
			for _, part in ipairs(probeParts) do
				if pointToColliderDistance(part.Position, collider) <= CFG.HIT_REACH then
					return true
				end
			end
		end
	end

	return false
end

local function onPlayerSwing(player, tool)
	if isDead then
		return
	end

	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return
	end

	local now = os.clock()
	if now - (lastHitClock[player] or 0) < CFG.HIT_DEBOUNCE then
		return
	end

	if not weaponReachesColliders(tool, character) then
		return
	end

	lastHitClock[player] = now
	takeDamage(getToolDamage(tool))
end

local function hookTool(tool)
	if not tool:IsA("Tool") or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	tool.Activated:Connect(function()
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player then
			onPlayerSwing(player, tool)
		end
	end)
end

local function hookCharacterTools(character)
	for _, child in ipairs(character:GetChildren()) do
		hookTool(child)
	end
	character.ChildAdded:Connect(hookTool)
end

local function registerPlayerForHitbox(player)
	if player.Character then
		hookCharacterTools(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacterTools)
end

for _, player in ipairs(Players:GetPlayers()) do
	registerPlayerForHitbox(player)
end

Players.PlayerAdded:Connect(registerPlayerForHitbox)

Players.PlayerRemoving:Connect(function(player)
	lastHitClock[player] = nil
end)

--====================================================
-- ПОЛОСКА ЗДОРОВЬЯ (HP BAR)
--====================================================
-- Полоска над головой, читает атрибут Health. Поставь false, чтобы скрыть.

if CFG.SHOW_HEALTH_BAR then
	local barAdornee = findColliderPartByName("HeadCollider") or rootCollider

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Adornee = barAdornee
	billboard.Size = UDim2.fromScale(4, 0.55)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Parent = barAdornee

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	background.BackgroundTransparency = 0.3
	background.BorderSizePixel = 0
	background.Parent = billboard

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0.5, 0)
	backgroundCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(60, 200, 75)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local function updateHealthBar()
		local ratio = math.clamp(getHealth() / maxHealth, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		-- Зелёный при полном HP, красный при низком.
		fill.BackgroundColor3 = Color3.fromRGB(
			math.floor(220 * (1 - ratio)) + 35,
			math.floor(200 * ratio) + 35,
			60
		)
		billboard.Enabled = getHealth() > 0
	end

	updateHealthBar()
	npc:GetAttributeChangedSignal("Health"):Connect(updateHealthBar)
end

--====================================================
-- ФИЗИКА NPC
--====================================================

for _, object in ipairs(npc:GetDescendants()) do
	if object:IsA("WeldConstraint") then
		if object.Name == "PirateColliderWeld" or object.Name == "PirateVisualWeld" then
			object:Destroy()
		end
	end
end

for _, object in ipairs(npc:GetDescendants()) do
	if object:IsA("BasePart") then
		if not object:IsDescendantOf(bodyColliders) then
			object.Anchored = false
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = true
			object.Massless = true
			object.CustomPhysicalProperties = PhysicalProperties.new(
				0.01,
				0.03,
				0,
				1,
				1
			)
		end
	end
end

rootCollider.Anchored = false
rootCollider.CanCollide = true
rootCollider.CanTouch = true
rootCollider.CanQuery = true
rootCollider.Massless = false
rootCollider.CollisionGroup = NPC_BODY_GROUP
rootCollider.Transparency = CFG.DEBUG_VISIBLE and 0.45 or 1
rootCollider.Color = Color3.fromRGB(0, 170, 255)

rootCollider.CustomPhysicalProperties = PhysicalProperties.new(
	0.18,
	0.03,
	0,
	1,
	1
)

for _, collider in ipairs(colliders) do
	local settings = COLLIDER_SETTINGS[collider.Name]

	collider.Anchored = false
	collider.CanTouch = true
	collider.CanQuery = true
	collider.Transparency = CFG.DEBUG_VISIBLE and 0.45 or 1

	if settings then
		collider.Color = settings.Color
		collider.CanCollide = settings.CanCollide
		collider.CollisionGroup = settings.Group
	else
		collider.Color = Color3.fromRGB(255, 170, 0)
		collider.CanCollide = false
		collider.CollisionGroup = NPC_GHOST_GROUP
	end

	if collider == rootCollider then
		collider.Massless = false
		collider.CanCollide = true
		collider.CollisionGroup = NPC_BODY_GROUP

		collider.CustomPhysicalProperties = PhysicalProperties.new(
			0.18,
			0.03,
			0,
			1,
			1
		)
	else
		-- Ноги остаются Massless, чтобы не перевешивать Пирата,
		-- но CanCollide + PirateLegs позволяют им отталкиваться от пола.
		collider.Massless = true

		if collider.Name == "LeftLegCollider" or collider.Name == "RightLegCollider" then
			collider.CanCollide = true
			collider.CollisionGroup = NPC_LEGS_GROUP
		end

		collider.CustomPhysicalProperties = PhysicalProperties.new(
			0.01,
			0.03,
			0,
			1,
			1
		)

		local weld = Instance.new("WeldConstraint")
		weld.Name = "PirateColliderWeld"
		weld.Part0 = rootCollider
		weld.Part1 = collider
		weld.Parent = collider
	end
end

local visualWeld = Instance.new("WeldConstraint")
visualWeld.Name = "PirateVisualWeld"
visualWeld.Part0 = rootCollider
visualWeld.Part1 = visualMesh
visualWeld.Parent = rootCollider

pcall(function()
	rootCollider:SetNetworkOwner(nil)
end)

-- Горизонтальное направление последней команды движения (для авто-шага). Берём
-- именно команду, а не AssemblyLinearVelocity: упираясь в край ступеньки, юнит
-- по факту стоит (солвер гасит скорость), но идти-то он хочет вперёд.
local moveCommandDir = nil

-- Идёт ли сейчас заход на ступеньку. Пока true — поднимаемся вертикальной
-- скоростью, а moveTowards не срезает вертикальную скорость своим лимитом.
local stepClimbActive = false

-- Последняя позиция, где пират нормально стоял на земле — для аварийного возврата,
-- если он провалится сквозь геометрию (тонкий пол/баг физики).
local lastGroundedPos = nil

local groundRaycastParams = RaycastParams.new()
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
groundRaycastParams.IgnoreWater = true

-- Тот же фильтр, но воду НЕ игнорируем — чтобы ловить кромку воды (материал Water).
local waterProbeParams = RaycastParams.new()
waterProbeParams.FilterType = Enum.RaycastFilterType.Exclude
waterProbeParams.IgnoreWater = false

local function updateGroundRaycastFilter()
	local filterList = { npc }

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end

	-- Игнорируем хитбоксы других юнитов: иначе наш raycast «земли» цепляет
	-- соседа и поднимает нас на него как на ступеньку (юниты стопками).
	for _, other in ipairs(CollectionService:GetTagged(CFG.UNIT_TAG)) do
		if other ~= npc then
			table.insert(filterList, other)
		end
	end

	groundRaycastParams.FilterDescendantsInstances = filterList
	waterProbeParams.FilterDescendantsInstances = filterList
end

local function getLegBottomY()
	local bottomY = math.huge

	for _, legCollider in ipairs(legColliders) do
		if legCollider.Parent then
			local legBottomY = legCollider.Position.Y - legCollider.Size.Y / 2

			if legBottomY < bottomY then
				bottomY = legBottomY
			end
		end
	end

	if bottomY == math.huge then
		return nil
	end

	return bottomY
end

local function getGroundYUnderLegs()
	updateGroundRaycastFilter()

	local bestGroundY = nil

	for _, legCollider in ipairs(legColliders) do
		if legCollider.Parent then
			local rayOrigin = legCollider.Position + Vector3.new(0, CFG.LEG_GROUND_RAYCAST_HEIGHT, 0)
			local rayDirection = Vector3.new(0, -(CFG.LEG_GROUND_RAYCAST_HEIGHT + CFG.LEG_GROUND_RAYCAST_DEPTH), 0)
			local result = workspace:Raycast(rayOrigin, rayDirection, groundRaycastParams)

			if result and result.Normal.Y >= 0.45 then
				if not bestGroundY or result.Position.Y > bestGroundY then
					bestGroundY = result.Position.Y
				end
			end
		end
	end

	return bestGroundY
end

-- Верх «ступеньки» прямо по курсу движения, на которую можно автоматически
-- зайти (как игрок переступает невысокий порог). Луч вниз чуть впереди по
-- направлению движения: если там ровная поверхность ВЫШЕ ног, но не выше
-- STEP_MAX_HEIGHT — это ступенька, возвращаем её Y. Иначе nil (ровно, спуск или
-- высокая стена). groundRaycastParams игнорирует игрока и юнитов, так что на них
-- забраться нельзя — только на геометрию мира.
-- Нет опоры под ногами (вода/обрыв) — хотя бы гасим резкий подброс вверх.
local function limitUpwardLaunch()
	local velocity = rootCollider.AssemblyLinearVelocity

	if velocity.Y <= CFG.MAX_UPWARD_VELOCITY then
		return
	end

	rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, CFG.MAX_UPWARD_VELOCITY, velocity.Z)
end

-- Верх «ступеньки» прямо по курсу движения, на которую можно автоматически
-- зайти. Чтобы НЕ лезть на стены (даже тонкие, но сплошные), требуем четыре условия:
--   1) На уровне щиколотки впереди ЕСТЬ блокер (иначе это просто пол, не уступ).
--   2) На уровне «выше ступеньки» впереди НЕТ блокера. Если есть — это высокая
--      стена, лезть нельзя (выше неё разберётся обычный прыжок).
--   3) За блокером есть ПЛОСКАЯ опора (Normal.Y высокий) в нужном диапазоне высот.
--      Плоскость отсекает СКАТЫ КРЫШ/рампы/склоны — иначе пират лез вверх по скату
--      крыши как по микро-ступенькам, переваливал конёк и падал под карту.
--   4) Опора ПРОДОЛЖАЕТСЯ вперёд и тоже плоская (это пол, а не тонкий гребень
--      стены/перил — иначе пират забирался на стену и проваливался по ту сторону).
-- groundRaycastParams игнорирует игроков и других юнитов → залезть на них нельзя.
local function getStepUpGroundY(legBottomY)
	if not CFG.STEP_ENABLED or not moveCommandDir then
		return nil -- авто-шаг выключен / стоим — не шагаем
	end

	updateGroundRaycastFilter()

	local origin = rootCollider.Position
	local ahead = math.max(rootCollider.Size.X, rootCollider.Size.Z) * 0.5 + CFG.STEP_PROBE_AHEAD
	local rayVec = moveCommandDir * ahead

	-- (1) Низкий блокер: что-то стоит прямо по курсу чуть выше ног.
	local lowStart = Vector3.new(origin.X, legBottomY + 0.3, origin.Z)
	if not workspace:Raycast(lowStart, rayVec, groundRaycastParams) then
		return nil -- путь у ног свободен → впереди не уступ, а просто пол/спуск
	end

	-- (2) Высокий блокер: если ВЫШЕ ступеньки тоже упёрлись — это стена, не лезем.
	local highStart = Vector3.new(origin.X, legBottomY + CFG.STEP_MAX_HEIGHT + 0.2, origin.Z)
	if workspace:Raycast(highStart, rayVec, groundRaycastParams) then
		return nil
	end

	-- (3) Высота опоры прямо за блокером.
	local probe = origin + rayVec
	local downOrigin = Vector3.new(probe.X, legBottomY + CFG.STEP_MAX_HEIGHT + 0.5, probe.Z)
	local result = workspace:Raycast(downOrigin, Vector3.new(0, -(CFG.STEP_MAX_HEIGHT + 0.7), 0), groundRaycastParams)

	if not result or result.Normal.Y < CFG.STEP_TOP_MIN_NORMAL_Y then
		return nil -- за блокером нет ПЛОСКОЙ опоры (склон/крыша/рампа/обрыв) → не ступенька
	end

	local stepY = result.Position.Y
	local rise = stepY - legBottomY
	if rise <= CFG.STEP_MIN_RISE or rise > CFG.STEP_MAX_HEIGHT then
		return nil
	end

	-- (4) ГЛАВНОЕ против стен: опора должна ПРОДОЛЖАТЬСЯ вперёд на ширину стопы.
	-- У настоящего порога/пола за краем тоже есть пол примерно на той же высоте; у
	-- тонкой (но сплошной) стенки/перил за верхним гребнем — обрыв вниз (внутрь
	-- дома) или пусто. Раньше такой гребень ≤ STEP_MAX_HEIGHT принимался за ступеньку,
	-- пират залезал на стену и проваливался по ту сторону.
	local far = origin + moveCommandDir * (ahead + CFG.STEP_FORWARD_CLEARANCE)
	local farResult = workspace:Raycast(Vector3.new(far.X, stepY + 1, far.Z), Vector3.new(0, -2.5, 0), groundRaycastParams)

	if not farResult
		or farResult.Normal.Y < CFG.STEP_TOP_MIN_NORMAL_Y
		or farResult.Position.Y < stepY - CFG.STEP_CONTINUITY_TOL then
		return nil -- за краем нет сплошной ПЛОСКОЙ опоры (обрыв/гребень/скат) → не заходим
	end

	return stepY
end

-- Если ноги поднялись выше нормальной высоты больше чем на столько —
-- считаем это баг-подбросом и жёстко возвращаем NPC к земле.

local function stabilizeOnGround()
	local legBottomY = getLegBottomY()

	if not legBottomY then
		limitUpwardLaunch()
		return
	end

	-- Аварийный возврат: тело оказалось НАМНОГО ниже последней валидной точки на
	-- земле → провалилось сквозь геометрию. Возвращаем на ту точку и гасим скорость.
	if lastGroundedPos and rootCollider.Position.Y < lastGroundedPos.Y - CFG.RECOVER_DROP then
		local yaw = select(2, rootCollider.CFrame:ToOrientation())
		rootCollider.CFrame = CFrame.new(lastGroundedPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, yaw, 0)
		rootCollider.AssemblyLinearVelocity = Vector3.zero
		rootCollider.AssemblyAngularVelocity = Vector3.zero
		stepClimbActive = false
		return
	end

	local groundY = getGroundYUnderLegs()

	-- Авто-шаг: впереди по курсу низкий уступ → поднимаемся на него ВЕРТИКАЛЬНОЙ
	-- СКОРОСТЬЮ, а не телепортом CFrame. Раньше CFrame загонял тело в геометрию, и
	-- солвер выталкивал его вниз сквозь пол. Скорость движок резолвит по
	-- столкновениям: тело едет вверх вдоль грани и сквозь пол не проваливается.
	local stepY = getStepUpGroundY(legBottomY)
	if stepY and (not groundY or stepY > groundY + 0.05) and legBottomY < stepY + CFG.LEG_GROUND_PADDING then
		local need = stepY + CFG.LEG_GROUND_PADDING - legBottomY
		local climb = math.clamp(need * 25, CFG.STEP_CLIMB_MIN, CFG.STEP_CLIMB_SPEED)
		local velocity = rootCollider.AssemblyLinearVelocity
		rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, climb, velocity.Z)
		stepClimbActive = true
		return -- во время подъёма обычные снапы (особенно вниз) пропускаем
	end

	stepClimbActive = false

	if not groundY then
		-- Под ногами нет опоры (вода/пропасть) — хотя бы не даём улетать вверх.
		limitUpwardLaunch()
		return
	end

	local targetBottomY = groundY + CFG.LEG_GROUND_PADDING
	local velocity = rootCollider.AssemblyLinearVelocity

	if legBottomY < targetBottomY then
		-- Просел под пол — плавно поднимаем (мелкий безопасный CFrame-доводчик).
		local liftAmount = math.min(targetBottomY - legBottomY, CFG.MAX_GROUND_LIFT_PER_HEARTBEAT)
		rootCollider.CFrame = rootCollider.CFrame + Vector3.new(0, liftAmount, 0)
		rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, math.clamp(velocity.Y, 0, CFG.MAX_UPWARD_VELOCITY), velocity.Z)
	elseif legBottomY > targetBottomY + CFG.MAX_HOVER_ABOVE_GROUND then
		-- Подбросило выше нормы (баг физики при контакте с поверхностью) —
		-- жёстко опускаем к земле и гасим вертикальную/угловую скорость,
		-- чтобы NPC не улетал в небо.
		rootCollider.CFrame = rootCollider.CFrame - Vector3.new(0, legBottomY - targetBottomY, 0)
		rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		rootCollider.AssemblyAngularVelocity = Vector3.zero
	else
		-- В пределах нормы — просто не даём резко взлетать.
		if velocity.Y > CFG.MAX_UPWARD_VELOCITY then
			rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, CFG.MAX_UPWARD_VELOCITY, velocity.Z)
		end
	end

	-- Запоминаем последнюю позицию, где стоим у самой земли (не подброшены) —
	-- сюда вернёмся, если провалимся сквозь геометрию.
	if legBottomY <= targetBottomY + CFG.MAX_HOVER_ABOVE_GROUND then
		lastGroundedPos = rootCollider.Position
	end
end

--====================================================
-- СТАБИЛИЗАЦИЯ И ПОВОРОТ
--====================================================

local attachment = rootCollider:FindFirstChild("BalanceAttachment")

if not attachment then
	attachment = Instance.new("Attachment")
	attachment.Name = "BalanceAttachment"
	attachment.Parent = rootCollider
end

local alignOrientation = rootCollider:FindFirstChild("BalanceAlignOrientation")

if not alignOrientation then
	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "BalanceAlignOrientation"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxTorque = 250000
	alignOrientation.Responsiveness = 45
	alignOrientation.Parent = rootCollider
end

local desiredYaw = 0
local currentDt = 1 / 60   -- dt текущего кадра (для плавного поворота)

local function getYawFacingPosition(targetPosition)
	local currentPosition = rootCollider.Position
	local flatTarget = Vector3.new(targetPosition.X, currentPosition.Y, targetPosition.Z)
	local offset = flatTarget - currentPosition

	if offset.Magnitude <= 0.05 then
		local _, currentYaw, _ = rootCollider.CFrame:ToOrientation()
		return currentYaw
	end

	local lookCFrame = CFrame.lookAt(currentPosition, flatTarget)
	local _, yaw, _ = lookCFrame:ToOrientation()

	yaw += math.rad(CFG.MODEL_YAW_OFFSET_DEGREES)

	return yaw
end

-- Поворот к цели — ПЛАВНЫЙ: тем же безопасным прямым CFrame, но малым шагом за
-- кадр (CFG.TURN_SPEED_DEGREES). Вызывается только в активных состояниях (НЕ в GUARD
-- и не на паузе патруля), поэтому покоящегося юнита это не крутит каждый кадр —
-- ровно тот случай, что раньше «взрывал» сборку.
local function faceTowards(targetPosition)
	desiredYaw = getYawFacingPosition(targetPosition)

	local _, currentYaw = rootCollider.CFrame:ToOrientation()
	local diff = (desiredYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	local maxStep = math.rad(CFG.TURN_SPEED_DEGREES) * currentDt
	local newYaw = currentYaw + math.clamp(diff, -maxStep, maxStep)

	alignOrientation.CFrame = CFrame.Angles(0, newYaw, 0)

	if CFG.FORCE_DIRECT_ROTATION then
		local position = rootCollider.Position
		local velocity = rootCollider.AssemblyLinearVelocity

		rootCollider.CFrame = CFrame.new(position) * CFrame.Angles(0, newYaw, 0)
		rootCollider.AssemblyLinearVelocity = velocity
		rootCollider.AssemblyAngularVelocity = Vector3.zero
	end
end

--====================================================
-- АНИМАЦИИ
--====================================================

local animationController = npc:FindFirstChildOfClass("AnimationController")

if not animationController then
	animationController = npc:FindFirstChild("AnimationController", true)
end

if not animationController then
	warn("[PirateUnitAI] AnimationController not found")
	return
end

local animator = animationController:FindFirstChildOfClass("Animator")

if not animator then
	animator = Instance.new("Animator")
	animator.Parent = animationController
end

local idleAnimation = npc:FindFirstChild(CFG.IDLE_ANIMATION_NAME, true)
local walkAnimation = npc:FindFirstChild(CFG.WALK_ANIMATION_NAME, true)
local runAnimation = npc:FindFirstChild(CFG.RUN_ANIMATION_NAME, true)
local attackAnimation = npc:FindFirstChild(CFG.ATTACK_ANIMATION_NAME, true)

if not idleAnimation or not idleAnimation:IsA("Animation") then
	warn("[PirateUnitAI] Idle animation not found")
	return
end

if not walkAnimation or not walkAnimation:IsA("Animation") then
	warn("[PirateUnitAI] Walk animation not found")
	return
end

if not attackAnimation or not attackAnimation:IsA("Animation") then
	warn("[PirateUnitAI] Attack animation not found")
	return
end

local idleTrack = animator:LoadAnimation(idleAnimation)
local walkTrack = animator:LoadAnimation(walkAnimation)
local attackTrack = animator:LoadAnimation(attackAnimation)

local runTrack = nil

if runAnimation and runAnimation:IsA("Animation") then
	runTrack = animator:LoadAnimation(runAnimation)
else
	warn("[PirateUnitAI] Run animation not found. Walk animation will be used as fallback.")
	runTrack = walkTrack
end

-- Анимация прыжка опциональна: объект Animation с именем "Jump" внутри модели.
-- Нет — прыжок просто без анимации (добавишь позже — заработает сам).
do
	local jumpAnim = npc:FindFirstChild("Jump", true)
	if jumpAnim and jumpAnim:IsA("Animation") then
		Jump.track = animator:LoadAnimation(jumpAnim)
		Jump.track.Looped = false
		Jump.track.Priority = Enum.AnimationPriority.Action
	end
end

idleTrack.Looped = true
walkTrack.Looped = true
runTrack.Looped = true
attackTrack.Looped = false

idleTrack.Priority = Enum.AnimationPriority.Idle
walkTrack.Priority = Enum.AnimationPriority.Movement
runTrack.Priority = Enum.AnimationPriority.Movement
attackTrack.Priority = Enum.AnimationPriority.Action

local currentAnimationState = nil

local function playIdle()
	if currentAnimationState == "Idle" then
		return
	end

	currentAnimationState = "Idle"

	walkTrack:Stop(0.2)

	if runTrack ~= walkTrack then
		runTrack:Stop(0.2)
	end

	attackTrack:Stop(0.1)

	if not idleTrack.IsPlaying then
		idleTrack:Play(0.2)
	end
end

local function playWalk()
	if currentAnimationState == "Walk" then
		return
	end

	currentAnimationState = "Walk"

	idleTrack:Stop(0.2)

	if runTrack ~= walkTrack then
		runTrack:Stop(0.2)
	end

	attackTrack:Stop(0.1)

	if not walkTrack.IsPlaying then
		walkTrack:Play(0.2)
	end
end

local function playRun()
	if currentAnimationState == "Run" then
		return
	end

	currentAnimationState = "Run"

	idleTrack:Stop(0.15)
	walkTrack:Stop(0.15)
	attackTrack:Stop(0.1)

	if not runTrack.IsPlaying then
		runTrack:Play(0.15)
	end
end

local function playAttack()
	currentAnimationState = "Attack"

	idleTrack:Stop(0.1)
	walkTrack:Stop(0.1)

	if runTrack ~= walkTrack then
		runTrack:Stop(0.1)
	end

	attackTrack:Stop(0)
	attackTrack:Play(0.05)
end

--====================================================
-- ПОИСК ЦЕЛИ
--====================================================

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { npc }
raycastParams.IgnoreWater = true

local function getCharacterRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character.PrimaryPart
end

local function getCharacterHumanoid(character)
	return character:FindFirstChildOfClass("Humanoid")
end

local function isAliveCharacter(character)
	local humanoid = getCharacterHumanoid(character)

	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

--====================================================
-- ДВИЖЕНИЕ И АТАКА
--====================================================

local lastAttackTime = 0
local isAttacking = false

local function stopMovement()
	moveCommandDir = nil -- стоим — авто-шаг выключаем
	local velocity = rootCollider.AssemblyLinearVelocity
	rootCollider.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
end

-- Вектор «прочь от соседних юнитов»: физически друг с другом они не
-- сталкиваются, поэтому расталкиваемся скриптом, чтобы не занимать одну точку.
local function getSeparationVector()
	local push = Vector3.zero

	for _, other in ipairs(CollectionService:GetTagged(CFG.UNIT_TAG)) do
		if other ~= npc and other.PrimaryPart then
			local away = rootCollider.Position - other.PrimaryPart.Position
			away = Vector3.new(away.X, 0, away.Z)
			local dist = away.Magnitude
			if dist > 0.05 and dist < CFG.SEPARATION_RADIUS then
				push = push + away.Unit * (1 - dist / CFG.SEPARATION_RADIUS)
			end
		end
	end

	return push
end

local function moveTowards(targetPosition, speed)
	-- Во время замаха стоим на месте: иначе пират проезжает сквозь игрока и
	-- «промахивается» мимо. Двигаемся только между ударами.
	if isAttacking then
		stopMovement()
		return
	end

	local currentPosition = rootCollider.Position
	local flatTarget = Vector3.new(targetPosition.X, currentPosition.Y, targetPosition.Z)
	local offset = flatTarget - currentPosition

	if offset.Magnitude <= 0.1 then
		stopMovement()
		return
	end

	-- К направлению на цель добавляем разведение от соседей, но чем БЛИЖЕ к цели,
	-- тем слабее — чтобы у игрока пираты сходились на удар, а не расталкивались.
	local sepScale = math.clamp(offset.Magnitude / 8, 0, 1)
	local direction = offset.Unit + getSeparationVector() * CFG.SEPARATION_STRENGTH * sepScale
	if direction.Magnitude < 0.05 then
		direction = offset.Unit
	else
		direction = direction.Unit
	end

	-- Во время захода на ступеньку вертикальную скорость НЕ срезаем (её задаёт
	-- stabilizeOnGround для подъёма); в норме держим лимит против подброса.
	local yVel = rootCollider.AssemblyLinearVelocity.Y
	local currentYVelocity = stepClimbActive and yVel or math.min(yVel, CFG.MAX_UPWARD_VELOCITY)

	rootCollider.AssemblyLinearVelocity = Vector3.new(
		direction.X * speed,
		currentYVelocity,
		direction.Z * speed
	)

	-- Куда реально идём — для авто-шага (direction уже плоский единичный вектор).
	moveCommandDir = Vector3.new(direction.X, 0, direction.Z)
end

local function attackTarget(targetRoot, targetHumanoid)
	if isAttacking then
		return
	end

	local now = os.clock()

	if now - lastAttackTime < CFG.ATTACK_COOLDOWN then
		return
	end

	lastAttackTime = now
	isAttacking = true

	stopMovement()
	faceTowards(targetRoot.Position)
	playAttack()

	task.delay(CFG.ATTACK_HIT_DELAY, function()
		if not targetRoot.Parent then
			return
		end

		if not targetHumanoid.Parent then
			return
		end

		if targetHumanoid.Health <= 0 then
			return
		end

		-- Тем же радиусом (зазор до коллайдера), что и вход/выход из атаки — раз
		-- удар начался, он должен попасть, если игрок не отбежал заметно за радиус.
		if targetGap(targetRoot) <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
			targetHumanoid:TakeDamage(CFG.ATTACK_DAMAGE)
		end
	end)

	local attackDuration = attackTrack.Length

	if attackDuration <= 0 then
		attackDuration = CFG.ATTACK_COOLDOWN
	end

	task.delay(math.min(attackDuration, CFG.ATTACK_COOLDOWN), function()
		isAttacking = false
	end)
end

--====================================================
-- ВОСПРИЯТИЕ (зрение + подозрение)
--====================================================

local headCollider = findColliderPartByName("HeadCollider")

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Куда «смотрит» пират (с учётом CFG.MODEL_YAW_OFFSET_DEGREES).
local function getLookDirection()
	local _, yaw = rootCollider.CFrame:ToOrientation()
	local faceYaw = yaw - math.rad(CFG.MODEL_YAW_OFFSET_DEGREES)
	return Vector3.new(-math.sin(faceYaw), 0, -math.cos(faceYaw))
end

local function getEyePosition()
	local base = headCollider and headCollider.Position or rootCollider.Position
	return base + Vector3.new(0, CFG.EYE_HEIGHT_OFFSET, 0)
end

-- Жёстко повернуть корпус на заданный yaw (для возврата на пост и т.п.).
local function faceYaw(yaw)
	desiredYaw = yaw
	alignOrientation.CFrame = CFrame.Angles(0, yaw, 0)

	if CFG.FORCE_DIRECT_ROTATION then
		local position = rootCollider.Position
		local velocity = rootCollider.AssemblyLinearVelocity
		rootCollider.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
		rootCollider.AssemblyLinearVelocity = velocity
		rootCollider.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Прямая видимость до персонажа: луч от глаз, стена/препятствие рвут обзор.
local function canSeeCharacter(targetRoot)
	local origin = getEyePosition()
	local direction = targetRoot.Position - origin
	local result = workspace:Raycast(origin, direction, raycastParams)

	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end

	return true
end

-- Состояние восприятия и памяти.
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

					-- Вплотную игрока «не заметить» нельзя (он стоит на пирате/бьёт его),
					-- поэтому в радиусе удара набираем подозрение по максимуму независимо
					-- от угла — иначе пират не понимает, что цель прямо перед ним.
					if targetGap(root) <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
						gain = CFG.SUSPICION_GAIN_FRONT
					end

					if gain and canSeeCharacter(root) then
						local distFactor = 1 - (dist / CFG.SIGHT_RANGE) * 0.6 -- ближе → быстрее
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

local suspicionAdornee = headCollider or rootCollider

local suspicionGui = Instance.new("BillboardGui")
suspicionGui.Name = "SuspicionBar"
suspicionGui.Size = UDim2.new(0, 80, 0, 8)
suspicionGui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
suspicionGui.AlwaysOnTop = true
suspicionGui.MaxDistance = 90
suspicionGui.Enabled = false
suspicionGui.Adornee = suspicionAdornee
suspicionGui.Parent = suspicionAdornee

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

local function collectPatrolPoints()
	local points = {}
	local folder = npc:FindFirstChild(CFG.PATROL_POINTS_FOLDER_NAME)

	if not folder then
		return points
	end

	local markers = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Attachment") then
			table.insert(markers, child)
		end
	end

	table.sort(markers, function(a, b)
		return a.Name < b.Name
	end)

	for _, marker in ipairs(markers) do
		if marker:IsA("Attachment") then
			table.insert(points, marker.WorldPosition)
		else
			table.insert(points, marker.Position)
		end
	end

	return points
end

local homePosition = rootCollider.Position
local homeYaw = select(2, rootCollider.CFrame:ToOrientation())
faceYaw(homeYaw)

local patrolPoints = collectPatrolPoints()
local patrolIndex = 1
local pauseUntil = 0
local atPoint = false
local patrolRng = Random.new()

--====================================================
-- НАВИГАЦИЯ (PathfindingService: обход препятствий и воды)
--====================================================

local AGENT_PARAMS = {
	AgentRadius = CFG.AGENT_RADIUS,
	AgentHeight = CFG.AGENT_HEIGHT,
	AgentCanJump = false,           -- перелаз препятствий пока выключен
	AgentCanClimb = false,
	WaypointSpacing = 2.5,
	Costs = { Water = math.huge },  -- вода непроходима
}

local navPath = PathfindingService:CreatePath(AGENT_PARAMS)
local pathWaypoints = {}
local waypointIndex = 1
local pathGoal = nil       -- цель, для которой посчитан путь
local pathComputeClock = 0
local pathOk = false
local pathComputing = false

-- Пересчёт пути идёт в отдельном потоке: ComputeAsync уступает (yield),
-- а Heartbeat ждать нельзя. При неудаче СТАРЫЙ путь не сбрасываем (идём по нём).
local lastPathWarnClock = 0

local function computePathAsync(goal)
	pathComputing = true
	task.spawn(function()
		local ok = pcall(function()
			navPath:ComputeAsync(rootCollider.Position, goal)
		end)

		if ok and navPath.Status == Enum.PathStatus.Success then
			pathWaypoints = navPath:GetWaypoints()
			waypointIndex = 1
			pathOk = true
			pathGoal = goal
		elseif os.clock() - lastPathWarnClock > 3 then
			lastPathWarnClock = os.clock()
			warn(string.format(
				"[PirateUnitAI] %s: путь не построен (%s). Проверь, что у препятствий есть CanCollide-парт, и габариты CFG.AGENT_RADIUS/CFG.AGENT_HEIGHT.",
				npc.Name,
				ok and tostring(navPath.Status) or "ошибка ComputeAsync"
			))
		end

		pathComputeClock = os.clock()
		pathComputing = false
	end)
end

-- Прямая видимость до точки на уровне корпуса тремя лучами (центр + бока на
-- ширину агента), чтобы не «продеть» взгляд в щель между столбами забора.
local function hasClearPath(toPos)
	local origin = rootCollider.Position
	local flat = Vector3.new(toPos.X - origin.X, 0, toPos.Z - origin.Z)
	local dist = flat.Magnitude
	if dist <= CFG.NAV_LOS_MARGIN then
		return true
	end

	local dir = flat.Unit
	local rayVec = dir * (dist - CFG.NAV_LOS_MARGIN)
	local side = Vector3.new(-dir.Z, 0, dir.X) * (CFG.AGENT_RADIUS + 1)

	for _, offset in ipairs({ Vector3.zero, side, -side }) do
		if workspace:Raycast(origin + offset, rayVec, raycastParams) then
			return false
		end
	end

	return true
end

--====================================================
-- ПРЫЖОК (кинематический — перепрыгнуть низкое препятствие)
--====================================================

-- Парты сборки (коллайдеры + меш), которые в прыжке двигаем ВМЕСТЕ как единое
-- тело. PatrolPoints сюда НЕ входят (маршрут не должен ехать с прыжком).
for _, collider in ipairs(colliders) do
	table.insert(Jump.assemblyParts, collider)
end
if visualMesh and not table.find(Jump.assemblyParts, visualMesh) then
	table.insert(Jump.assemblyParts, visualMesh)
end

-- Высота земли под точкой (XZ), либо nil (нет опоры / вода).
function Jump.groundYAt(position)
	updateGroundRaycastFilter()
	local result = workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -48, 0), groundRaycastParams)
	return result and result.Position.Y or nil
end

-- Анимация прыжка (если в модели есть объект Animation "Jump").
function Jump.playAnim()
	if not Jump.track or currentAnimationState == "Jump" then
		return
	end
	currentAnimationState = "Jump"
	idleTrack:Stop(0.05)
	walkTrack:Stop(0.05)
	if runTrack ~= walkTrack then
		runTrack:Stop(0.05)
	end
	Jump.track:Stop(0)
	Jump.track:Play(0.05)
end

-- На время прыжка выключаем столкновения тела (дуга чистая), на посадке вернём.
function Jump.setBodyCollision(enabled)
	if enabled then
		for collider, wasCollide in pairs(Jump.canCollideBackup) do
			if collider.Parent then
				collider.CanCollide = wasCollide
			end
		end
		Jump.canCollideBackup = {}
	else
		Jump.canCollideBackup = {}
		for _, collider in ipairs(colliders) do
			Jump.canCollideBackup[collider] = collider.CanCollide
			collider.CanCollide = false
		end
	end
end

-- Низкое препятствие вплотную по курсу к toPos, и за ним есть куда приземлиться?
function Jump.obstacleAhead(toPos)
	local origin = rootCollider.Position
	local flat = Vector3.new(toPos.X - origin.X, 0, toPos.Z - origin.Z)
	local dist = flat.Magnitude
	if dist < 0.5 then
		return false
	end

	local dir = flat.Unit

	local lowHit = workspace:Raycast(origin - Vector3.new(0, 1, 0), dir * Jump.CHECK_DISTANCE, raycastParams)
	if not lowHit then
		return false
	end

	local model = lowHit.Instance:FindFirstAncestorWhichIsA("Model")
	if model and Players:GetPlayerFromCharacter(model) then
		return false
	end

	local highHit = workspace:Raycast(origin + Vector3.new(0, Jump.CLEAR_HEIGHT, 0), dir * Jump.CHECK_DISTANCE, raycastParams)
	if highHit then
		return false
	end

	if not Jump.groundYAt(origin + dir * Jump.DISTANCE) then
		return false
	end

	return true, dir
end

-- Ставим ВСЮ сборку так, чтобы корень оказался в rootCF, сохраняя смещения.
function Jump.moveAssemblyTo(rootCF)
	for _, part in ipairs(Jump.assemblyParts) do
		if part.Parent then
			part.CFrame = rootCF * Jump.offsets[part]
		end
	end
	rootCollider.AssemblyLinearVelocity = Vector3.zero
	rootCollider.AssemblyAngularVelocity = Vector3.zero
end

function Jump.finish()
	Jump.active = false
	Jump.moveAssemblyTo(CFrame.new(Jump.landPos) * CFrame.Angles(0, Jump.yaw, 0))
	Jump.setBodyCollision(true)
	alignOrientation.CFrame = CFrame.Angles(0, Jump.yaw, 0)
	desiredYaw = Jump.yaw
end

function Jump.start(dir)
	local startPos = rootCollider.Position
	Jump.startPos = startPos

	-- Смещение «центр корня над опорой стоя» берём из геометрии тела (legBottom
	-- относительно корня), а не из (startPos.Y − groundY). Так корректно работает
	-- и из воды: иначе при плавучем старте Jump.groundYAt уходит на дно, rootOffset
	-- получается огромным и пират улетает высоко над берегом.
	local legBottom = getLegBottomY() or (startPos.Y - 2)
	local standHeight = startPos.Y - legBottom
	local landXZ = startPos + dir * Jump.DISTANCE
	local landGroundY = Jump.groundYAt(landXZ) or (startPos.Y - standHeight)
	Jump.landPos = Vector3.new(landXZ.X, landGroundY + standHeight, landXZ.Z)

	-- Запоминаем смещения ВСЕХ партов относительно корня (yaw-only поза корня).
	Jump.yaw = select(2, rootCollider.CFrame:ToOrientation())
	local rootCF = CFrame.new(startPos) * CFrame.Angles(0, Jump.yaw, 0)
	Jump.offsets = {}
	for _, part in ipairs(Jump.assemblyParts) do
		Jump.offsets[part] = rootCF:Inverse() * part.CFrame
	end

	Jump.active = true
	Jump.startClock = os.clock()
	Jump.lastClock = os.clock()

	Jump.setBodyCollision(false)
	Jump.playAnim()
end

-- Едем по дуге, двигая ВСЮ сборку разом (коллизии выключены — солверу нечего
-- ломать). По завершении дуги приземляемся.
function Jump.update()
	local t = (os.clock() - Jump.startClock) / Jump.DURATION
	if t >= 1 then
		Jump.finish()
		return
	end

	local base = Jump.startPos:Lerp(Jump.landPos, t)
	local arcY = Jump.HEIGHT * 4 * t * (1 - t)
	Jump.moveAssemblyTo(CFrame.new(base.X, base.Y + arcY, base.Z) * CFrame.Angles(0, Jump.yaw, 0))
end

-- Высота поверхности воды в точке (или nil, если там не вода).
local function waterSurfaceY(pos)
	updateGroundRaycastFilter()
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), waterProbeParams)
	if hit and hit.Material == Enum.Material.Water then
		return hit.Position.Y
	end
	return nil
end

-- В воде ли пират (ноги/корпус под поверхностью воды на WATER_WADE_DEPTH или глубже).
local function isInWater()
	local surface = waterSurfaceY(rootCollider.Position)
	if not surface then
		return false
	end
	local legBottom = getLegBottomY() or rootCollider.Position.Y
	return surface - legBottom >= CFG.WATER_WADE_DEPTH
end

-- Идти к goal. Видно цель напрямую — идём ровно прямо (без пасфайндинга и
-- виляния). На пути преграда — обходим её по маршруту PathfindingService.
local function navigateTo(goal, speed)
	-- В воде: вместо ходьбы прыгаем по курсу — короткими дугами скачем через
	-- воду или выскакиваем на берег. Анимаций нырка/плавания нет, обычный прыжок.
	if not Jump.active and os.clock() - Jump.lastClock >= Jump.COOLDOWN and isInWater() then
		local flat = Vector3.new(goal.X - rootCollider.Position.X, 0, goal.Z - rootCollider.Position.Z)
		if flat.Magnitude > 0.5 then
			Jump.start(flat.Unit)
			return
		end
	end

	-- Низкое препятствие вплотную по курсу → перепрыгиваем (а не упираемся). Но
	-- пока идёт заход на ступеньку (авто-шаг) — не прыгаем, чтобы не перебивать его.
	if not Jump.active and not stepClimbActive and os.clock() - Jump.lastClock >= Jump.COOLDOWN then
		local canJump, jumpAt = Jump.obstacleAhead(goal)
		if canJump then
			Jump.start(jumpAt)
			return
		end
	end

	if hasClearPath(goal) then
		faceTowards(goal)
		moveTowards(goal, speed)
		return
	end

	local needRecompute = (not pathOk)
		or (not pathGoal)
		or flatDistance(pathGoal, goal) > CFG.PATH_GOAL_MOVE_THRESHOLD
		or waypointIndex > #pathWaypoints
		or (os.clock() - pathComputeClock > CFG.PATH_RECOMPUTE_INTERVAL)

	if needRecompute and not pathComputing then
		computePathAsync(goal)
	end

	if pathOk and #pathWaypoints > 0 then
		while waypointIndex <= #pathWaypoints
			and flatDistance(rootCollider.Position, pathWaypoints[waypointIndex].Position) <= CFG.WAYPOINT_REACH do
			waypointIndex += 1
		end

		local moveTarget = (waypointIndex <= #pathWaypoints)
			and pathWaypoints[waypointIndex].Position
			or goal
		faceTowards(moveTarget)
		moveTowards(moveTarget, speed)
	else
		-- Обхода нет (путь ещё считается или не нашёлся) → НЕ тараним преграду и
		-- НЕ крутимся на месте: просто стоим. Появится путь — пойдём по нему.
		stopMovement()
	end
end

--====================================================
-- КОНЕЧНЫЙ АВТОМАТ (FSM)
--====================================================

local STATE = {
	GUARD = "Guard",             -- стоит на посту, играет Idle
	PATROL = "Patrol",           -- обходит маршрут по маркерам
	INVESTIGATE = "Investigate", -- подозрение >= 50%, идёт проверить
	CHASE = "Chase",             -- точно видит врага, бежит на него
	ATTACK = "Attack",           -- бьёт в радиусе атаки
	SEARCH = "Search",           -- потерял из виду, ищет у последней точки
	RETURN = "Return",           -- возвращается на пост
	ALERTED = "Alerted",         -- поднят по тревоге отряда (не знает, где игрок)
}

local currentState = STATE.GUARD
local stateClock = os.clock()

-- Тревога отряда (Этап 2): крик приходит через атрибут AlertClock на модели.
-- Память тревоги считаем по СВОИМ часам (по событию смены атрибута), чтобы не
-- зависеть от сравнения времени между скриптами.
local alertedUntil = 0
local alertPosition = nil
local alertUserId = nil
local lastShoutClock = 0

npc:GetAttributeChangedSignal("AlertClock"):Connect(function()
	alertedUntil = os.clock() + CFG.ALERT_MEMORY
	alertPosition = npc:GetAttribute("AlertPosition")
	alertUserId = npc:GetAttribute("AlertUserId")
	if CFG.DEBUG_SQUAD then
		print(string.format("[PirateSquad] %s услышал крик отряда", npc.Name))
	end
end)

local function setState(newState)
	if newState == currentState then
		return
	end
	currentState = newState
	stateClock = os.clock()
end

local function stateAge()
	return os.clock() - stateClock
end

-- Свежая тревога отряда (позиция) или nil.
local function getSquadAlert()
	if os.clock() < alertedUntil then
		return alertPosition
	end
	return nil
end

-- «Крик»: разослать позицию игрока и его UserId пиратам отряда в радиусе.
local function broadcastAlert()
	local pos = lastKnownPosition
	if not pos then
		return
	end

	local player = chaseTarget and Players:GetPlayerFromCharacter(chaseTarget)
	local userId = (player and player.UserId) or 0
	local now = os.clock()
	local count = 0

	for _, other in ipairs(CollectionService:GetTagged(CFG.GUARD_TAG)) do
		if other ~= npc and other.PrimaryPart
			and flatDistance(rootCollider.Position, other.PrimaryPart.Position) <= CFG.SQUAD_ALERT_RADIUS then
			other:SetAttribute("AlertPosition", pos)
			other:SetAttribute("AlertUserId", userId)
			other:SetAttribute("AlertClock", now)
			count += 1
		end
	end

	lastShoutClock = now

	if CFG.DEBUG_SQUAD then
		print(string.format("[PirateSquad] %s КРИК — оповещено пиратов: %d (в радиусе %d)",
			npc.Name, count, CFG.SQUAD_ALERT_RADIUS))
	end
end

-- Медленно осматриваемся, стоя на месте.
local function scan()
	local yaw = stateAge() * 1.2
	local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	faceTowards(rootCollider.Position + dir * 10)
end

-- ── Поведение состояний ───────────────────────────────────────────────

local function runGuard()
	stopMovement()
	playIdle()

	if #patrolPoints > 0 and stateAge() >= CFG.GUARD_DURATION then
		patrolIndex = 1
		pauseUntil = 0
		atPoint = false
		setState(STATE.PATROL)
	end
end

local function runPatrol()
	-- Стоим на точке, пока идёт случайная пауза (CFG.PATROL_PAUSE_MIN..MAX).
	if os.clock() < pauseUntil then
		stopMovement()
		playIdle()
		return
	end

	-- Пауза кончилась, а мы стоим на точке → решаем, куда дальше.
	if atPoint then
		atPoint = false
		if patrolIndex >= #patrolPoints then
			setState(STATE.RETURN)
		else
			patrolIndex += 1
		end
		return
	end

	-- Идём к текущей точке маршрута (обходя препятствия).
	local target = patrolPoints[patrolIndex]
	navigateTo(target, CFG.MOVE_SPEED)
	playWalk()

	-- Дошли до точки: стоим случайные 10..30 c, потом двинемся дальше.
	if flatDistance(rootCollider.Position, target) <= CFG.PATROL_POINT_REACH then
		atPoint = true
		pauseUntil = os.clock() + patrolRng:NextNumber(CFG.PATROL_PAUSE_MIN, CFG.PATROL_PAUSE_MAX)
	end
end

local function runInvestigate()
	local target = lastKnownPosition or homePosition

	if flatDistance(rootCollider.Position, target) > CFG.PATROL_POINT_REACH then
		navigateTo(target, CFG.MOVE_SPEED)
		playWalk()
	else
		stopMovement()
		playIdle()
		scan()

		if suspicion < CFG.SUSPICION_INVESTIGATE * 0.5 and not getSquadAlert() then
			setState(STATE.RETURN)
		end
	end
end

-- Ближайший живой игрок, чьё тело в пределах зазора maxGap от наших коллайдеров.
local function nearestPlayerInMelee(maxGap)
	local bestRoot, bestChar, bestGap = nil, nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and isAliveCharacter(character) then
			local root = getCharacterRoot(character)
			if root then
				local gap = targetGap(root)
				if gap <= maxGap and gap < bestGap then
					bestGap, bestRoot, bestChar = gap, root, character
				end
			end
		end
	end

	return bestRoot, bestChar
end

-- Единое боевое поведение: преследование И удар в одном месте, без отдельного
-- состояния ATTACK. Дальше радиуса удара — бежим к цели; в радиусе — стоим и
-- бьём (attackTarget сам держит кулдаун и наносит урон). Раньше удар жил в
-- отдельном состоянии, пират «застревал» между «бежать» и «бить» — забегал в
-- игрока и почти не атаковал. Теперь решает только дистанция, каждый кадр.
local function runEngage(visibleRoot)
	if not visibleRoot then
		setState(STATE.SEARCH)
		return
	end

	lastKnownPosition = visibleRoot.Position
	faceTowards(visibleRoot.Position)

	if targetGap(visibleRoot) <= CFG.ATTACK_RANGE then
		-- В зоне удара: стоим и бьём.
		stopMovement()
		local humanoid = getCharacterHumanoid(visibleRoot.Parent)
		if humanoid then
			attackTarget(visibleRoot, humanoid)
		end
		if not isAttacking then
			playIdle()
		end
	elseif isAttacking then
		-- Замах уже идёт — не уезжаем с него.
		stopMovement()
	else
		-- Далеко: бежим к игроку.
		navigateTo(visibleRoot.Position, CFG.MOVE_SPEED * CFG.RUN_SPEED_MULTIPLIER)
		playRun()
	end
end

local function runSearch()
	local target = lastKnownPosition or homePosition

	if flatDistance(rootCollider.Position, target) > CFG.PATROL_POINT_REACH then
		navigateTo(target, CFG.MOVE_SPEED)
		playWalk()
	else
		stopMovement()
		playIdle()
		scan()
	end

	-- Уходим, когда тревога полностью спала (уже проверив место) либо по
	-- сейфти-таймеру (если не смогли дойти до точки).
	if suspicion <= 0 or stateAge() >= CFG.SEARCH_DURATION then
		chaseTarget = nil
		setState(STATE.RETURN)
	end
end

local function runReturn()
	if flatDistance(rootCollider.Position, homePosition) > CFG.PATROL_POINT_REACH then
		navigateTo(homePosition, CFG.MOVE_SPEED)
		playWalk()
	else
		suspicion = 0
		chaseTarget = nil
		lastKnownPosition = nil
		faceYaw(homeYaw)
		setState(STATE.GUARD)
	end
end

-- Поднят по тревоге, но точной позиции игрока не знает: подтягивается к месту
-- крика, осматриваясь. Дойдя в зону боя (CFG.SQUAD_ENGAGE_RADIUS) — начинает
-- активно проверять место. Своё зрение работает: увидит игрока → погоня.
local function runAlerted()
	local target = getSquadAlert() or homePosition

	if flatDistance(rootCollider.Position, target) > CFG.SQUAD_ENGAGE_RADIUS then
		navigateTo(target, CFG.MOVE_SPEED)
		playWalk()
	else
		lastKnownPosition = target
		setState(STATE.INVESTIGATE)
		return
	end

	-- Тревога протухла, сами никого не увидели → возвращаемся на пост.
	if not getSquadAlert() then
		setState(STATE.RETURN)
	end
end

--====================================================
-- ГЛАВНЫЙ ЦИКЛ
--====================================================

playIdle()

RunService.Heartbeat:Connect(function(dt)
	currentDt = dt

	if not rootCollider.Parent then
		return
	end

	if isDead or getHealth() <= 0 then
		stopMovement()
		return
	end

	-- Кинематический прыжок: едем по дуге, физику/стабилизацию пропускаем.
	if Jump.active then
		Jump.update()
		return
	end

	pcall(function()
		if rootCollider:GetNetworkOwner() ~= nil then
			rootCollider:SetNetworkOwner(nil)
		end
	end)

	stabilizeOnGround()

	local visibleRoot, visibleChar = updatePerception(dt)

	-- Спад подозрения. Пока цель видно — держится/растёт. В погоне/атаке НЕ
	-- падает. В проверке/поиске падает только ПОСЛЕ прихода на последнюю
	-- известную точку — сначала проверить место, и лишь потом забывать.
	if not visibleRoot then
		local allowDecay = true
		if currentState == STATE.CHASE or currentState == STATE.ATTACK then
			allowDecay = false
		elseif currentState == STATE.INVESTIGATE or currentState == STATE.SEARCH then
			local spot = lastKnownPosition or homePosition
			allowDecay = flatDistance(rootCollider.Position, spot) <= CFG.PATROL_POINT_REACH
		end
		if allowDecay then
			suspicion = math.max(0, suspicion - CFG.SUSPICION_DECAY * dt)
		end
	end

	updateSuspicionBar()

	-- Эскалация по подозрению.
	if suspicion >= CFG.SUSPICION_ALERT and visibleRoot then
		chaseTarget = visibleChar
		if currentState ~= STATE.CHASE and currentState ~= STATE.ATTACK then
			broadcastAlert() -- первый крик отряду
		end
		setState(STATE.CHASE)
	elseif suspicion >= CFG.SUSPICION_INVESTIGATE
		and (currentState == STATE.GUARD or currentState == STATE.PATROL or currentState == STATE.RETURN) then
		setState(STATE.INVESTIGATE)
	end

	-- Пока бой идёт — перекрикиваем, обновляя позицию игрока для отряда.
	if (currentState == STATE.CHASE or currentState == STATE.ATTACK)
		and os.clock() - lastShoutClock >= CFG.SHOUT_INTERVAL then
		broadcastAlert()
	end

	-- Реакция на чужой крик, если сами ещё не в активном бою.
	local squadAlertPos = getSquadAlert()
	if squadAlertPos and currentState ~= STATE.CHASE and currentState ~= STATE.ATTACK then
		-- Знаем, на кого идём (из крика) — берём игрока целью, чтобы атаковать
		-- его при встрече, а не просто прийти на пустое место.
		local player = (alertUserId and alertUserId > 0) and Players:GetPlayerByUserId(alertUserId)
		if player and player.Character and isAliveCharacter(player.Character) then
			chaseTarget = player.Character
		end

		if flatDistance(rootCollider.Position, squadAlertPos) <= CFG.SQUAD_ENGAGE_RADIUS then
			lastKnownPosition = squadAlertPos
			if currentState ~= STATE.INVESTIGATE then
				setState(STATE.INVESTIGATE)
			end
		elseif currentState == STATE.GUARD or currentState == STATE.PATROL or currentState == STATE.RETURN then
			setState(STATE.ALERTED)
		end
	end

	-- Безусловный рефлекс ближнего боя: если рядом (в зоне удара + буфер) есть
	-- живой игрок — он наша цель, и мы немедленно в бою. Без подозрения, обзора и
	-- угла: «возле меня — значит бью». Это и делает атаку надёжной из любого
	-- состояния (страж/патруль/проверка) — пират не «думает», а сразу реагирует.
	local meleeRoot, meleeChar = nearestPlayerInMelee(CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER)
	if meleeRoot then
		chaseTarget = meleeChar
		if currentState ~= STATE.CHASE and currentState ~= STATE.ATTACK then
			broadcastAlert() -- на нас напали вплотную — сразу зовём отряд
			setState(STATE.CHASE)
		end
	end

	-- В режиме преследования цель «видна», если есть LOS и она в радиусе
	-- (без ограничения по FOV — пират активно следит и доворачивается).
	local chaseVisibleRoot = nil
	if chaseTarget then
		local root = getCharacterRoot(chaseTarget)
		if root and isAliveCharacter(chaseTarget) then
			-- Вплотную (в радиусе удара + буфер) цель «видна» ВСЕГДА: на дистанции
			-- удара LOS/FOV не нужны, иначе большой пират «теряет» игрока у себя под
			-- боком и срывается в SEARCH вместо удара. Дальше — обычная проверка обзора.
			if targetGap(root) <= CFG.ATTACK_RANGE + CFG.ATTACK_RANGE_BUFFER then
				chaseVisibleRoot = root
			elseif flatDistance(rootCollider.Position, root.Position) <= CFG.SIGHT_RANGE and canSeeCharacter(root) then
				chaseVisibleRoot = root
			end
		end
	end

	-- Есть назначенная цель и мы её ВИДИМ → сразу в бой. Так пираты, поднятые по
	-- тревоге, реально нападают на игрока, а не топчутся в проверке/готовности.
	if chaseVisibleRoot and currentState ~= STATE.CHASE and currentState ~= STATE.ATTACK then
		setState(STATE.CHASE)
	end

	if currentState == STATE.GUARD then
		runGuard()
	elseif currentState == STATE.PATROL then
		runPatrol()
	elseif currentState == STATE.INVESTIGATE then
		runInvestigate()
	elseif currentState == STATE.CHASE or currentState == STATE.ATTACK then
		runEngage(chaseVisibleRoot)
	elseif currentState == STATE.SEARCH then
		runSearch()
	elseif currentState == STATE.RETURN then
		runReturn()
	elseif currentState == STATE.ALERTED then
		runAlerted()
	end

	-- Анти-«бег на месте»: если по факту стоим (уперлись в воду/преграду и
	-- stopMovement обнулил скорость), показываем Idle вместо анимации бега.
	if not isAttacking and not stepClimbActive
		and (currentAnimationState == "Run" or currentAnimationState == "Walk") then
		local v = rootCollider.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude < 0.6 then
			playIdle()
		end
	end
end)

print(string.format(
	"[PirateUnitAI] Guard AI (Stage 1-3) loaded. Variant=%s PatrolPoints=%d Root=%s",
	CFG.BEHAVIOR_VARIANT,
	#patrolPoints,
	rootCollider:GetFullName()
))
