local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local npc = script.Parent

--====================================================
-- НАСТРОЙКИ МОДЕЛИ
--====================================================

local VISUAL_MESH_NAME = "corsair"
local BODY_COLLIDERS_NAME = "BodyColliders"

local IDLE_ANIMATION_NAME = "Idle"
local WALK_ANIMATION_NAME = "Walk"
local RUN_ANIMATION_NAME = "Run"
local ATTACK_ANIMATION_NAME = "Attack"

local ROOT_COLLIDER_NAME = "TorsoCollider"

local UNIT_MAX_HEALTH = 100
local DESTROY_ON_DEATH = false

-- false = коллайдеры невидимые
-- true = коллайдеры видны для настройки
local DEBUG_VISIBLE = false

-- Если пират идёт спиной к игроку, пробуй 0 / 90 / -90 / 180
local MODEL_YAW_OFFSET_DEGREES = 180

--====================================================
-- НАСТРОЙКИ ИИ
--====================================================

-- Радиус обычного обнаружения.
local DETECTION_RADIUS = 20

-- Если игрок уже был замечен и убежал дальше 20,
-- Корсар продолжает погоню до этой дистанции.
local CHASE_GIVE_UP_DISTANCE = 35

-- Если Корсар в режиме погони приблизился к игроку до этой дистанции,
-- режим ускоренной погони выключается.
local CHASE_STOP_DISTANCE = 5

local MOVE_SPEED = 10
local RUN_SPEED_MULTIPLIER = 1.5

local ATTACK_RANGE = 4.2
local ATTACK_COOLDOWN = 1.4
local ATTACK_DAMAGE = 20
local ATTACK_HIT_DELAY = 0.35

-- Для теста лучше false.
-- Если true, пират будет проверять стены Raycast'ом.
local USE_LINE_OF_SIGHT = false

-- Если true, скрипт напрямую разворачивает TorsoCollider через CFrame.
local FORCE_DIRECT_ROTATION = true

--====================================================
-- COLLISION GROUPS
--====================================================

local PLAYER_GROUP = "PlayerCharacters"
local NPC_BODY_GROUP = "PirateBody"
local NPC_LEGS_GROUP = "PirateLegs"
local NPC_GHOST_GROUP = "PirateGhost"
local DEFAULT_WORLD_GROUP = "Default"

-- Насколько выше пола держать низ коллайдеров ног.
local LEG_GROUND_PADDING = 0.06
local LEG_GROUND_RAYCAST_HEIGHT = 8
local LEG_GROUND_RAYCAST_DEPTH = 16
local MAX_GROUND_LIFT_PER_HEARTBEAT = 0.25
local MAX_UPWARD_VELOCITY = 2.5

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

-- Ноги должны быть физическими для земли, иначе Корсар проваливается под пол.
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

local visualMesh = npc:FindFirstChild(VISUAL_MESH_NAME, true)

if not visualMesh or not visualMesh:IsA("BasePart") then
	warn("[PirateAI] Visual mesh not found:", VISUAL_MESH_NAME)
	return
end

local bodyColliders = npc:FindFirstChild(BODY_COLLIDERS_NAME)

if not bodyColliders then
	warn("[PirateAI] BodyColliders not found")
	return
end

local colliders = {}

for _, object in ipairs(bodyColliders:GetDescendants()) do
	if object:IsA("BasePart") then
		table.insert(colliders, object)
	end
end

if #colliders == 0 then
	warn("[PirateAI] No BasePart colliders found inside BodyColliders")
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

local rootCollider = findColliderPartByName(ROOT_COLLIDER_NAME)

if not rootCollider then
	warn("[PirateAI] Root collider BasePart not found, using first collider:", colliders[1].Name)
	rootCollider = colliders[1]
end

local legColliders = {}

for _, collider in ipairs(colliders) do
	if collider.Name == "LeftLegCollider" or collider.Name == "RightLegCollider" then
		table.insert(legColliders, collider)
	end
end

if #legColliders == 0 then
	warn("[PirateAI] Leg colliders not found. Create LeftLegCollider and RightLegCollider so Corsair can stand on the ground.")
end

npc.PrimaryPart = rootCollider

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

local maxHealth = UNIT_MAX_HEALTH
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

	if DESTROY_ON_DEATH then
		task.delay(3, function()
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
rootCollider.Transparency = DEBUG_VISIBLE and 0.45 or 1
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
	collider.Transparency = DEBUG_VISIBLE and 0.45 or 1

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
		-- Ноги остаются Massless, чтобы не перевешивать Корсара,
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

local groundRaycastParams = RaycastParams.new()
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
groundRaycastParams.IgnoreWater = true

local function updateGroundRaycastFilter()
	local filterList = { npc }

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end

	groundRaycastParams.FilterDescendantsInstances = filterList
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
			local rayOrigin = legCollider.Position + Vector3.new(0, LEG_GROUND_RAYCAST_HEIGHT, 0)
			local rayDirection = Vector3.new(0, -(LEG_GROUND_RAYCAST_HEIGHT + LEG_GROUND_RAYCAST_DEPTH), 0)
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

local function liftCorsairOutOfGround()
	local legBottomY = getLegBottomY()
	local groundY = getGroundYUnderLegs()

	if not legBottomY or not groundY then
		return
	end

	local targetBottomY = groundY + LEG_GROUND_PADDING

	if legBottomY >= targetBottomY then
		return
	end

	local liftAmount = math.clamp(targetBottomY - legBottomY, 0, MAX_GROUND_LIFT_PER_HEARTBEAT)
	local velocity = rootCollider.AssemblyLinearVelocity

	rootCollider.CFrame = rootCollider.CFrame + Vector3.new(0, liftAmount, 0)
	rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, math.clamp(velocity.Y, 0, MAX_UPWARD_VELOCITY), velocity.Z)
end

local function limitUpwardLaunch()
	local velocity = rootCollider.AssemblyLinearVelocity

	if velocity.Y <= MAX_UPWARD_VELOCITY then
		return
	end

	rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, MAX_UPWARD_VELOCITY, velocity.Z)
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

	yaw += math.rad(MODEL_YAW_OFFSET_DEGREES)

	return yaw
end

local function faceTowards(targetPosition)
	desiredYaw = getYawFacingPosition(targetPosition)

	alignOrientation.CFrame = CFrame.Angles(0, desiredYaw, 0)

	if FORCE_DIRECT_ROTATION then
		local position = rootCollider.Position
		local velocity = rootCollider.AssemblyLinearVelocity

		rootCollider.CFrame = CFrame.new(position) * CFrame.Angles(0, desiredYaw, 0)
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
	warn("[PirateAI] AnimationController not found")
	return
end

local animator = animationController:FindFirstChildOfClass("Animator")

if not animator then
	animator = Instance.new("Animator")
	animator.Parent = animationController
end

local idleAnimation = npc:FindFirstChild(IDLE_ANIMATION_NAME, true)
local walkAnimation = npc:FindFirstChild(WALK_ANIMATION_NAME, true)
local runAnimation = npc:FindFirstChild(RUN_ANIMATION_NAME, true)
local attackAnimation = npc:FindFirstChild(ATTACK_ANIMATION_NAME, true)

if not idleAnimation or not idleAnimation:IsA("Animation") then
	warn("[PirateAI] Idle animation not found")
	return
end

if not walkAnimation or not walkAnimation:IsA("Animation") then
	warn("[PirateAI] Walk animation not found")
	return
end

if not attackAnimation or not attackAnimation:IsA("Animation") then
	warn("[PirateAI] Attack animation not found")
	return
end

local idleTrack = animator:LoadAnimation(idleAnimation)
local walkTrack = animator:LoadAnimation(walkAnimation)
local attackTrack = animator:LoadAnimation(attackAnimation)

local runTrack = nil

if runAnimation and runAnimation:IsA("Animation") then
	runTrack = animator:LoadAnimation(runAnimation)
else
	warn("[PirateAI] Run animation not found. Walk animation will be used as fallback.")
	runTrack = walkTrack
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

local function hasLineOfSight(targetRoot)
	if not USE_LINE_OF_SIGHT then
		return true
	end

	local npcPosition = rootCollider.Position + Vector3.new(0, 2, 0)
	local targetPosition = targetRoot.Position + Vector3.new(0, 2, 0)
	local direction = targetPosition - npcPosition

	local result = workspace:Raycast(npcPosition, direction, raycastParams)

	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end

	return true
end

local function findNearestTargetInRadius(radius)
	local bestCharacter = nil
	local bestRoot = nil
	local bestHumanoid = nil
	local bestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character

		if character and isAliveCharacter(character) then
			local root = getCharacterRoot(character)
			local humanoid = getCharacterHumanoid(character)

			if root and humanoid then
				local distance = (root.Position - rootCollider.Position).Magnitude

				if distance <= radius and distance < bestDistance and hasLineOfSight(root) then
					bestDistance = distance
					bestCharacter = character
					bestRoot = root
					bestHumanoid = humanoid
				end
			end
		end
	end

	return bestCharacter, bestRoot, bestHumanoid, bestDistance
end

local function getTargetData(character)
	if not character then
		return nil, nil, math.huge
	end

	if not isAliveCharacter(character) then
		return nil, nil, math.huge
	end

	local root = getCharacterRoot(character)
	local humanoid = getCharacterHumanoid(character)

	if not root or not humanoid then
		return nil, nil, math.huge
	end

	local distance = (root.Position - rootCollider.Position).Magnitude

	return root, humanoid, distance
end

--====================================================
-- ДВИЖЕНИЕ И АТАКА
--====================================================

local lastAttackTime = 0
local isAttacking = false

local currentTargetCharacter = nil
local isChasingEscapedTarget = false

local function clearTarget()
	currentTargetCharacter = nil
	isChasingEscapedTarget = false
end

local function stopMovement()
	local velocity = rootCollider.AssemblyLinearVelocity
	rootCollider.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
end

local function moveTowards(targetPosition, speed)
	local currentPosition = rootCollider.Position
	local flatTarget = Vector3.new(targetPosition.X, currentPosition.Y, targetPosition.Z)
	local offset = flatTarget - currentPosition

	if offset.Magnitude <= 0.1 then
		stopMovement()
		return
	end

	local direction = offset.Unit
	local currentYVelocity = math.min(rootCollider.AssemblyLinearVelocity.Y, MAX_UPWARD_VELOCITY)

	rootCollider.AssemblyLinearVelocity = Vector3.new(
		direction.X * speed,
		currentYVelocity,
		direction.Z * speed
	)
end

local function attackTarget(targetRoot, targetHumanoid)
	if isAttacking then
		return
	end

	local now = os.clock()

	if now - lastAttackTime < ATTACK_COOLDOWN then
		return
	end

	lastAttackTime = now
	isAttacking = true

	stopMovement()
	faceTowards(targetRoot.Position)
	playAttack()

	task.delay(ATTACK_HIT_DELAY, function()
		if not targetRoot.Parent then
			return
		end

		if not targetHumanoid.Parent then
			return
		end

		if targetHumanoid.Health <= 0 then
			return
		end

		local distance = (targetRoot.Position - rootCollider.Position).Magnitude

		if distance <= ATTACK_RANGE + 1 then
			targetHumanoid:TakeDamage(ATTACK_DAMAGE)
		end
	end)

	local attackDuration = attackTrack.Length

	if attackDuration <= 0 then
		attackDuration = ATTACK_COOLDOWN
	end

	task.delay(math.min(attackDuration, ATTACK_COOLDOWN), function()
		isAttacking = false
	end)
end

--====================================================
-- ГЛАВНЫЙ ЦИКЛ
--====================================================

playIdle()

RunService.Heartbeat:Connect(function()
	if not rootCollider.Parent then
		return
	end

	if isDead or getHealth() <= 0 then
		stopMovement()
		return
	end

	pcall(function()
		if rootCollider:GetNetworkOwner() ~= nil then
			rootCollider:SetNetworkOwner(nil)
		end
	end)

	liftCorsairOutOfGround()
	limitUpwardLaunch()

	-- 1. Если текущей цели нет, ищем игрока в обычном радиусе 20.
	if not currentTargetCharacter then
		local character = nil
		local root = nil
		local humanoid = nil
		local distance = nil

		character, root, humanoid, distance = findNearestTargetInRadius(DETECTION_RADIUS)

		if character and root and humanoid then
			currentTargetCharacter = character
			isChasingEscapedTarget = false
		else
			stopMovement()
			playIdle()

			local _, yaw, _ = rootCollider.CFrame:ToOrientation()
			desiredYaw = yaw
			alignOrientation.CFrame = CFrame.Angles(0, desiredYaw, 0)

			return
		end
	end

	local targetRoot, targetHumanoid, distance = getTargetData(currentTargetCharacter)

	if not targetRoot or not targetHumanoid then
		clearTarget()
		stopMovement()
		playIdle()
		return
	end

	-- 2. Если цель вышла дальше 35, Корсар забывает игрока.
	if distance > CHASE_GIVE_UP_DISTANCE then
		clearTarget()
		stopMovement()
		playIdle()
		return
	end

	-- 3. Если цель вышла за 20, включаем ускоренную погоню.
	if distance > DETECTION_RADIUS then
		isChasingEscapedTarget = true
	end

	-- 4. Если в режиме погони Корсар приблизился до 5,
	-- выключаем ускоренную погоню.
	if isChasingEscapedTarget and distance <= CHASE_STOP_DISTANCE then
		isChasingEscapedTarget = false
	end

	faceTowards(targetRoot.Position)

	-- 5. Атака работает в любом режиме, если игрок близко.
	if distance <= ATTACK_RANGE then
		stopMovement()
		attackTarget(targetRoot, targetHumanoid)

		if not isAttacking then
			playIdle()
		end

		return
	end

	if isAttacking then
		stopMovement()
		return
	end

	-- 6. Движение:
	-- обычный режим = Walk
	-- игрок убежал за 20 после обнаружения = Run x1.5
	if isChasingEscapedTarget then
		moveTowards(targetRoot.Position, MOVE_SPEED * RUN_SPEED_MULTIPLIER)
		playRun()
	else
		moveTowards(targetRoot.Position, MOVE_SPEED)
		playWalk()
	end
end)

print("[PirateAI] Pirate AI with chase mode loaded. Root:", rootCollider:GetFullName())
