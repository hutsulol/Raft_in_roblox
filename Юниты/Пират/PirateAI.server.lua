local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local npc = script.Parent

--====================================================
-- НАСТРОЙКИ МОДЕЛИ
--====================================================

local VISUAL_MESH_NAME = "Pirate"
local BODY_COLLIDERS_NAME = "BodyColliders"

local IDLE_ANIMATION_NAME = "Idle"
local WALK_ANIMATION_NAME = "Walk"
local RUN_ANIMATION_NAME = "Run"
local ATTACK_ANIMATION_NAME = "Attack"

local ROOT_COLLIDER_NAME = "TorsoCollider"

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
-- Пират продолжает погоню до этой дистанции.
local CHASE_GIVE_UP_DISTANCE = 35

-- Если Пират в режиме погони приблизился к игроку до этой дистанции,
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

local visualMesh = npc:FindFirstChild(VISUAL_MESH_NAME, true)

if not visualMesh or not visualMesh:IsA("BasePart") then
	warn("[PirateUnitAI] Visual mesh not found:", VISUAL_MESH_NAME)
	return
end

local bodyColliders = npc:FindFirstChild(BODY_COLLIDERS_NAME)

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

local rootCollider = findColliderPartByName(ROOT_COLLIDER_NAME)

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

local groundRaycastParams = RaycastParams.new()
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
groundRaycastParams.FilterDescendantsInstances = { npc }
groundRaycastParams.IgnoreWater = true

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
	local bestGroundY = nil

	for _, legCollider in ipairs(legColliders) do
		if legCollider.Parent then
			local rayOrigin = legCollider.Position + Vector3.new(0, LEG_GROUND_RAYCAST_HEIGHT, 0)
			local rayDirection = Vector3.new(0, -(LEG_GROUND_RAYCAST_HEIGHT + LEG_GROUND_RAYCAST_DEPTH), 0)
			local result = workspace:Raycast(rayOrigin, rayDirection, groundRaycastParams)

			if result then
				if not bestGroundY or result.Position.Y > bestGroundY then
					bestGroundY = result.Position.Y
				end
			end
		end
	end

	return bestGroundY
end

local function liftPirateOutOfGround()
	local legBottomY = getLegBottomY()
	local groundY = getGroundYUnderLegs()

	if not legBottomY or not groundY then
		return
	end

	local targetBottomY = groundY + LEG_GROUND_PADDING

	if legBottomY >= targetBottomY then
		return
	end

	local liftAmount = math.clamp(targetBottomY - legBottomY, 0, 3)
	local velocity = rootCollider.AssemblyLinearVelocity

	rootCollider.CFrame = rootCollider.CFrame + Vector3.new(0, liftAmount, 0)
	rootCollider.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, 0), velocity.Z)
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
	warn("[PirateUnitAI] AnimationController not found")
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
	local currentYVelocity = rootCollider.AssemblyLinearVelocity.Y

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

	pcall(function()
		if rootCollider:GetNetworkOwner() ~= nil then
			rootCollider:SetNetworkOwner(nil)
		end
	end)

	liftPirateOutOfGround()

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

	-- 2. Если цель вышла дальше 35, Пират забывает игрока.
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

	-- 4. Если в режиме погони Пират приблизился до 5,
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

print("[PirateUnitAI] Pirate AI with chase mode loaded. Root:", rootCollider:GetFullName())
