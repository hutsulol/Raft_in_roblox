--[[
	Basic Monster by ArceusInator

	Information:
		Configurations.MaximumDetectionDistance (default 200)
			The monster will not detect players past this point.  If you set it to a negative number then the monster will be able to chase from any distance.
			
		Configurations.CanGiveUp (default true)
			If true, the monster will give up if its target goes past the MaximumDetectionDistance.  This is a pretty good idea if you have people teleporting around.
			
		Configurations.CanRespawn (default true)
			If true, the monster will respawn after it dies
			
		Configurations.AutoDetectSpawnPoint (default true)
			If true, the spawn point will be auto detected based on where the monster is when it starts
		
		Configurations.SpawnPoint (default 0,0,0)
			If Settings.AutoDetectSpawnPoint is disabled, this will be set to the monster's initial position.  This value will be used when the monster auto respawns to tell it where to spawn next.
			
		Configurations.FriendlyTeam (default Really black)
			The monster will not attack players on this team
		
		
		
		Mind.CurrentTargetHumanoid (Humanoid objects only)
			You can force the monster to follow a certain humanoid by setting this to that humanoid
		
		
		
		Monster.Respawn (Function)
			Arguments are: Vector3 point
			Info: Respawns the monster at the given point, or at the SpawnPoint setting if none if provided
		
		Monster.Died (Event)
			Info: Fired when the monster dies
		
		Monster.Respawned (Event)
			Info: Fired when the monster respawns
--]]

local Self = script.Parent
local Settings = Self:FindFirstChild'Configurations' -- Points to the settings.
local Mind = Self:FindFirstChild'Mind' -- Points to the monster's mind.  You can edit parts of this from other scripts in-game to change the monster's behavior.  Advanced users only.

--
-- Verify that everything is where it should be
assert(Self:FindFirstChild'Humanoid' ~= nil, 'Monster does not have a humanoid')
assert(Settings ~= nil, 'Monster does not have a Configurations object')
	assert(Settings:FindFirstChild'MaximumDetectionDistance' ~= nil and Settings.MaximumDetectionDistance:IsA'NumberValue', 'Monster does not have a MaximumDetectionDistance (NumberValue) setting')
	assert(Settings:FindFirstChild'CanGiveUp' ~= nil and Settings.CanGiveUp:IsA'BoolValue', 'Monster does not have a CanGiveUp (BoolValue) setting')
	assert(Settings:FindFirstChild'CanRespawn' ~= nil and Settings.CanRespawn:IsA'BoolValue', 'Monster does not have a CanRespawn (BoolValue) setting')
	assert(Settings:FindFirstChild'SpawnPoint' ~= nil and Settings.SpawnPoint:IsA'Vector3Value', 'Monster does not have a SpawnPoint (Vector3Value) setting')
	assert(Settings:FindFirstChild'AutoDetectSpawnPoint' ~= nil and Settings.AutoDetectSpawnPoint:IsA'BoolValue', 'Monster does not have a AutoDetectSpawnPoint (BoolValue) setting')
	assert(Settings:FindFirstChild'FriendlyTeam' ~= nil and Settings.FriendlyTeam:IsA'BrickColorValue', 'Monster does not have a FriendlyTeam (BrickColorValue) setting')
	assert(Settings:FindFirstChild'AttackDamage' ~= nil and Settings.AttackDamage:IsA'NumberValue', 'Monster does not have a AttackDamage (NumberValue) setting')
	assert(Settings:FindFirstChild'AttackFrequency' ~= nil and Settings.AttackFrequency:IsA'NumberValue', 'Monster does not have a AttackFrequency (NumberValue) setting')
	assert(Settings:FindFirstChild'AttackRange' ~= nil and Settings.AttackRange:IsA'NumberValue', 'Monster does not have a AttackRange (NumberValue) setting')
assert(Mind ~= nil, 'Monster does not have a Mind object')
	assert(Mind:FindFirstChild'CurrentTargetHumanoid' ~= nil and Mind.CurrentTargetHumanoid:IsA'ObjectValue', 'Monster does not have a CurrentTargetHumanoid (ObjectValue) mind setting')
assert(Self:FindFirstChild'Respawn' and Self.Respawn:IsA'BindableFunction', 'Monster does not have a Respawn BindableFunction')
assert(Self:FindFirstChild'Died' and Self.Died:IsA'BindableEvent', 'Monster does not have a Died BindableEvent')
assert(Self:FindFirstChild'Respawned' and Self.Died:IsA'BindableEvent', 'Monster does not have a Respawned BindableEvent')
assert(Self:FindFirstChild'Attacked' and Self.Died:IsA'BindableEvent', 'Monster does not have a Attacked BindableEvent')
assert(script:FindFirstChild'Attack' and script.Attack:IsA'Animation', 'Monster does not have a MonsterScript.Attack Animation')


--
--
local Info = {
	-- These are constant values.  Don't change them unless you know what you're doing.

	-- Services
	Players = Game:GetService 'Players',
	PathfindingService = Game:GetService 'PathfindingService',

	-- Advanced settings
	RecomputePathFrequency = 1, -- The monster will recompute its path this many times per second
	RespawnWaitTime = 5, -- How long to wait before the monster respawns
	JumpCheckFrequency = 1, -- How many times per second it will do a jump check
}
local Data = {
	-- These are variable values used internally by the script.  Advanced users only.

	LastRecomputePath = 0,
	Recomputing = false, -- Reocmputing occurs async, meaning this script will still run while it's happening.  This variable will prevent the script from running two recomputes at once.
	PathCoords = {},
	IsDead = false,
	TimeOfDeath = 0,
	CurrentNode = nil,
	CurrentNodeIndex = 1,
	AutoRecompute = true,
	LastJumpCheck = 0,
	LastAttack = 0,
	
	BaseMonster = Self:Clone(),
	AttackTrack = nil,
}

--====================================================
-- СИСТЕМА СЛЕЖКИ (шкала наблюдения)
--====================================================
-- Конус зрения: спереди замечает быстро, сбоку медленно, сзади не видит; стены
-- рвут обзор (Raycast). Шкала 0..100 с полосой над головой (белая→жёлтая→красная).
-- Цель назначается ТОЛЬКО при 100. Пока цель есть — ходьба ×SpeedMult (бега нет).
local Watch = {
	SightRange = 50,   -- дальность зрения
	FrontFov   = 50,   -- |угол| ≤ этого — быстрый набор (спереди)
	SideFov    = 110,  -- |угол| ≤ этого — медленный (сбоку); дальше не видит
	GainFront  = 90,   -- ед/сек вплотную спереди
	GainSide   = 35,
	Decay      = 25,   -- спад в секунду, когда никого не видит
	SpeedMult  = 1.3,  -- множитель скорости ходьбы, когда игрок замечен

	Suspicion  = 0,
	Candidate  = nil,  -- ближайший видимый персонаж в этом кадре
	LastSeenPos = nil, -- где ПОСЛЕДНИЙ раз видели игрока (для хода на проверку)
	InvestigateAt = 50,-- с этого порога идём проверять последнюю точку
	BaseSpeed  = nil,  -- обычная скорость (захватывается при старте)
	Gui = nil,
	Fill = nil,
}

--
--
local Monster = {} -- Create the monster class


function Monster:GetCFrame()
	-- Returns the CFrame of the monster's humanoidrootpart

	local humanoidRootPart = Self:FindFirstChild('HumanoidRootPart')

	if humanoidRootPart ~= nil and humanoidRootPart:IsA('BasePart') then
		return humanoidRootPart.CFrame
	else
		return CFrame.new()
	end
end

function Monster:GetMaximumDetectionDistance()
	-- Returns the maximum detection distance
	
	local setting = Settings.MaximumDetectionDistance.Value

	if setting < 0 then
		return math.huge
	else
		return setting
	end
end

function Monster:SearchForTarget()
	-- Цель назначается ТОЛЬКО когда шкала наблюдения заполнена (100) и кандидат
	-- всё ещё на виду — никакого мгновенного агра по дистанции.
	if Watch.Suspicion >= 100 and Watch.Candidate ~= nil then
		local humanoid = Watch.Candidate:FindFirstChild('Humanoid')
		if humanoid ~= nil and humanoid:IsA('Humanoid') and humanoid.Health > 0 then
			Mind.CurrentTargetHumanoid.Value = humanoid
		end
	end
end

-- Видим ли персонажа (стена рвёт обзор).
function Monster:CanSeeCharacter(character)
	local root = character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Torso')
	if root == nil then return false end
	local myPos = Monster:GetCFrame().p + Vector3.new(0, 1.5, 0)
	local hit = Workspace:FindPartOnRayWithIgnoreList(
		Ray.new(myPos, root.Position - myPos),
		{ Self, character }
	)
	return hit == nil
end

-- Копит/остужает шкалу по конусу зрения + LOS. Запоминает ближайшего видимого.
function Monster:UpdatePerception(dt)
	Watch.Candidate = nil

	-- Пока цель есть — шкала прижата к 100 (полоса горит красным).
	if Monster:TargetIsValid() then
		Watch.Suspicion = 100
		return
	end

	local myCF = Monster:GetCFrame()
	local look = Vector3.new(myCF.lookVector.X, 0, myCF.lookVector.Z).unit
	local bestDist = nil

	for _, player in ipairs(Info.Players:GetPlayers()) do
		if player.Neutral or player.TeamColor ~= Settings.FriendlyTeam.Value then
			local character = player.Character
			local humanoid = character and character:FindFirstChild('Humanoid')
			local root = character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Torso'))
			if humanoid ~= nil and humanoid.Health > 0 and root ~= nil then
				local offset = root.Position - myCF.p
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local dist = flat.magnitude
				if dist > 0.05 and dist <= Watch.SightRange then
					local angle = math.deg(math.acos(math.clamp(look:Dot(flat.unit), -1, 1)))
					local gain = nil
					if angle <= Watch.FrontFov then
						gain = Watch.GainFront
					elseif angle <= Watch.SideFov then
						gain = Watch.GainSide
					end
					-- Вплотную «не заметить» нельзя — независимо от угла.
					if dist <= Settings.AttackRange.Value + 2 then
						gain = Watch.GainFront * 3
					end
					if gain ~= nil and Monster:CanSeeCharacter(character) then
						local distFactor = 1 - (dist / Watch.SightRange) * 0.6
						Watch.Suspicion = math.min(100, Watch.Suspicion + gain * distFactor * dt)
						if bestDist == nil or dist < bestDist then
							bestDist = dist
							Watch.Candidate = character
							Watch.LastSeenPos = root.Position -- запоминаем точку, где видим
						end
					end
				end
			end
		end
	end

	-- Никого не видим — подозрение остывает.
	if Watch.Candidate == nil then
		Watch.Suspicion = math.max(0, Watch.Suspicion - Watch.Decay * dt)
	end
end

-- Полоса над головой. Пересоздаётся после респавна (голова уничтожается вместе с ней).
function Monster:CreateSuspicionBar()
	local head = Self:FindFirstChild('Head') or Self:FindFirstChild('HumanoidRootPart')
	if head == nil then return end
	if Watch.Gui ~= nil then Watch.Gui:Destroy() end

	local gui = Instance.new('BillboardGui')
	gui.Name = 'SuspicionBar'
	gui.Size = UDim2.new(0, 80, 0, 8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.Adornee = head
	gui.Parent = head

	local bg = Instance.new('Frame')
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.4
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local fill = Instance.new('Frame')
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	Watch.Gui = gui
	Watch.Fill = fill
end

function Monster:UpdateSuspicionBar()
	if Watch.Gui == nil or Watch.Gui.Parent == nil then return end
	Watch.Gui.Enabled = Watch.Suspicion > 1
	Watch.Fill.Size = UDim2.new(math.clamp(Watch.Suspicion / 100, 0, 1), 0, 1, 0)
	if Monster:TargetIsValid() or Watch.Suspicion >= 100 then
		Watch.Fill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	elseif Watch.Suspicion >= 50 then
		Watch.Fill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
	else
		Watch.Fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

-- Скорость: заметили игрока (цель есть) — обычная ходьба ×SpeedMult; иначе обычная.
function Monster:UpdateSpeed()
	local humanoid = Self:FindFirstChild('Humanoid')
	if humanoid == nil then return end
	if Watch.BaseSpeed == nil then
		Watch.BaseSpeed = humanoid.WalkSpeed
	end
	local want = Monster:TargetIsValid() and (Watch.BaseSpeed * Watch.SpeedMult) or Watch.BaseSpeed
	if humanoid.WalkSpeed ~= want then
		humanoid.WalkSpeed = want
	end
end

function Monster:TryRecomputePath()
	if Data.AutoRecompute or tick() - Data.LastRecomputePath > 1/Info.RecomputePathFrequency then
		Monster:RecomputePath()
	end
end

function Monster:GetTargetCFrame()
	local targetHumanoid = Mind.CurrentTargetHumanoid.Value
	
	if Monster:TargetIsValid() then
		return targetHumanoid.Torso.CFrame
	else
		return CFrame.new()
	end
end

function Monster:IsAlive()
	return Self.Humanoid.Health > 0 and Self.Humanoid.Torso ~= nil
end

function Monster:TargetIsValid()
	local targetHumanoid = Mind.CurrentTargetHumanoid.Value
	
	if targetHumanoid ~= nil and targetHumanoid:IsA 'Humanoid' and targetHumanoid.Torso ~= nil and targetHumanoid.Torso:IsA 'BasePart' then
		return true
	else
		return false
	end
end

function Monster:HasClearLineOfSight()
	-- Going to cast a ray to see if I can just see my target
	local myPos, targetPos = Monster:GetCFrame().p, Monster:GetTargetCFrame().p
	
	local hit, pos = Workspace:FindPartOnRayWithIgnoreList(
		Ray.new(
			myPos,
			targetPos - myPos
		),
		{
			Self,
			Mind.CurrentTargetHumanoid.Value.Parent
		}
	)
	
	
	if hit == nil then
		return true
	else
		return false
	end
end

function Monster:RecomputePath()
	if not Data.Recomputing then
		if Monster:IsAlive() and Monster:TargetIsValid() then
			if Monster:HasClearLineOfSight() then
				Data.AutoRecompute = true
				Data.PathCoords = {
					Monster:GetCFrame().p,
					Monster:GetTargetCFrame().p
				}
				
				Data.LastRecomputePath = tick()
				Data.CurrentNode = nil
				Data.CurrentNodeIndex = 2 -- Starts chasing the target without evaluating its current position
			else
				-- Do pathfinding since you can't walk straight
				Data.Recomputing = true -- Basically a debounce.
				Data.AutoRecompute = false
				
				
				local path = Info.PathfindingService:ComputeSmoothPathAsync(
					Monster:GetCFrame().p,
					Monster:GetTargetCFrame().p,
					500
				)
				Data.PathCoords = path:GetPointCoordinates()
				
				
				Data.Recomputing = false
				Data.LastRecomputePath = tick()
				Data.CurrentNode = nil
				Data.CurrentNodeIndex = 1
			end
		end
	end
end

function Monster:Update(dt)
	Monster:ReevaluateTarget()
	Monster:UpdatePerception(dt or 0.03)
	Monster:SearchForTarget()
	Monster:UpdateSuspicionBar()
	Monster:UpdateSpeed()

	if Monster:TargetIsValid() then
		-- Цель захвачена (100%) — обычная погоня по пути.
		Monster:TryRecomputePath()
		Monster:TravelPath()
	else
		-- Цели нет: при шкале ≥ порога идём проверить последнюю точку.
		Monster:Investigate()
	end
end

-- Нет цели, но подозрение ≥ InvestigateAt (50%) — идём проверить место, где
-- последний раз видели игрока. Прямой MoveTo (без пасфайндинга — проще). Дойдя,
-- забываем точку и осматриваемся; шкала тем временем остывает.
function Monster:Investigate()
	local humanoid = Self:FindFirstChild('Humanoid')
	if humanoid == nil or not humanoid:IsA('Humanoid') then return end

	if Watch.Suspicion >= Watch.InvestigateAt and Watch.LastSeenPos ~= nil then
		local myPos = Monster:GetCFrame().p
		local flat = (Watch.LastSeenPos - myPos) * Vector3.new(1, 0, 1)
		if flat.magnitude > 3 then
			humanoid:MoveTo(Watch.LastSeenPos) -- идём к месту замеченного движения
		else
			Watch.LastSeenPos = nil            -- дошли — осмотрелись, точку забыли
		end
	end
end

function Monster:TravelPath()
	local closest, closestDistance, closestIndex
	local myPosition = Monster:GetCFrame().p
	local skipCurrentNode = Data.CurrentNode ~= nil and (Data.CurrentNode - myPosition).magnitude < 3
	
	for i=Data.CurrentNodeIndex, #Data.PathCoords do
		local coord = Data.PathCoords[i]
		if not (skipCurrentNode and coord == Data.CurrentNode) then
			local distance = (coord - myPosition).magnitude
			
			if closest == nil then
				closest, closestDistance, closestIndex = coord, distance, i
			else
				if distance < closestDistance then
					closest, closestDistance, closestIndex = coord, distance, i
				else
					break
				end
			end
		end
	end
	
	
	--
	if closest ~= nil then
		Data.CurrentNode = closest
		Data.CurrentNodeIndex = closestIndex
		
		local humanoid = Self:FindFirstChild 'Humanoid'
		
		if humanoid ~= nil and humanoid:IsA'Humanoid' then
			humanoid:MoveTo(closest)
		end
		
		if Monster:IsAlive() and Monster:TargetIsValid() then
			Monster:TryJumpCheck()
			Monster:TryAttack()
		end
		
		if closestIndex == #Data.PathCoords then
			-- Reached the end of the path, force a new check
			Data.AutoRecompute = true
		end
	end
end

function Monster:TryJumpCheck()
	if tick() - Data.LastJumpCheck > 1/Info.JumpCheckFrequency then
		Monster:JumpCheck()
	end
end

function Monster:TryAttack()
	if tick() - Data.LastAttack > 1/Settings.AttackFrequency.Value then
		Monster:Attack()
	end
end

function Monster:Attack()
	local myPos, targetPos = Monster:GetCFrame().p, Monster:GetTargetCFrame().p
	
	if (myPos - targetPos).magnitude <= Settings.AttackRange.Value then
		Mind.CurrentTargetHumanoid.Value:TakeDamage(Settings.AttackDamage.Value)
		Data.LastAttack = tick()
		Data.AttackTrack:Play()
	end
end

function Monster:JumpCheck()
	-- Do a raycast to check if we need to jump
	local myCFrame = Monster:GetCFrame()
	local checkVector = (Monster:GetTargetCFrame().p - myCFrame.p).unit*2
	
	local hit, pos = Workspace:FindPartOnRay(
		Ray.new(
			myCFrame.p + Vector3.new(0, -2.4, 0),
			checkVector
		),
		Self
	)
	
	if hit ~= nil and not hit:IsDescendantOf(Mind.CurrentTargetHumanoid.Value.Parent) then
		-- Do a slope check to make sure we're not walking up a ramp
		
		local hit2, pos2 = Workspace:FindPartOnRay(
			Ray.new(
				myCFrame.p + Vector3.new(0, -2.3, 0),
				checkVector
			),
			Self
		)
		
		if hit2 == hit then
			if ((pos2 - pos)*Vector3.new(1,0,1)).magnitude < 0.05 then -- Will pass for any ramp with <2 slope
				Self.Humanoid.Jump = true
			end
		end
	end
	
	Data.LastJumpCheck = tick()
end

function Monster:Connect()
	Mind.CurrentTargetHumanoid.Changed:connect(function(humanoid)
		if humanoid ~= nil then
			assert(humanoid:IsA'Humanoid', 'Monster target must be a humanoid')
			
			Monster:RecomputePath()
		end
	end)
	
	Self.Respawn.OnInvoke = function(point)
		Monster:Respawn(point)
	end
end

function Monster:Initialize()
	Monster:Connect()
	
	if Settings.AutoDetectSpawnPoint.Value then
		Settings.SpawnPoint.Value = Monster:GetCFrame().p
	end
end

function Monster:Respawn(point)
	local point = point or Settings.SpawnPoint.Value
	
	for index, obj in next, Data.BaseMonster:Clone():GetChildren() do
		if obj.Name == 'Configurations' or obj.Name == 'Mind' or obj.Name == 'Respawned' or obj.Name == 'Died' or obj.Name == 'MonsterScript' or obj.Name == 'Respawn' then
			obj:Destroy()
		else
			Self[obj.Name]:Destroy()
			obj.Parent = Self
		end
	end
	
	Monster:InitializeUnique()
	
	Self.Parent = Workspace
	
	Self.HumanoidRootPart.CFrame = CFrame.new(point)
	Settings.SpawnPoint.Value = point
	Self.Respawned:Fire()
end

function Monster:InitializeUnique()
	Data.AttackTrack = Self.Humanoid:LoadAnimation(script.Attack)
	-- HP: снимаем ForceField, если он есть на риге. Игрок и наёмники бьют через
	-- Humanoid:TakeDamage, а он НЕ проходит сквозь ForceField — из-за этого пират
	-- казался бессмертным. Делается и при старте, и после респавна.
	for _, obj in ipairs(Self:GetDescendants()) do
		if obj:IsA('ForceField') then
			obj:Destroy()
		end
	end
	-- Слежка: полоса над головой (после респавна голова новая) + обычная скорость.
	Monster:CreateSuspicionBar()
	Watch.Suspicion = 0
	local humanoid = Self:FindFirstChild('Humanoid')
	if humanoid ~= nil and Watch.BaseSpeed == nil then
		Watch.BaseSpeed = humanoid.WalkSpeed
	end
end

function Monster:ReevaluateTarget()
	local currentTarget = Mind.CurrentTargetHumanoid.Value

	if currentTarget ~= nil and currentTarget:IsA'Humanoid' then
		local character = currentTarget.Parent

		if character ~= nil then
			local player = Info.Players:GetPlayerFromCharacter(character)

			if player ~= nil then
				if not player.Neutral and player.TeamColor == Settings.FriendlyTeam.Value then
					Mind.CurrentTargetHumanoid.Value = nil
					Watch.Suspicion = 0
				end
			end
		end

		-- Цель умерла — слежка с нуля.
		if currentTarget.Health <= 0 then
			Mind.CurrentTargetHumanoid.Value = nil
			Watch.Suspicion = 0
		end

		if currentTarget == Mind.CurrentTargetHumanoid.Value then
			local torso = currentTarget.Torso

			if torso ~= nil and torso:IsA 'BasePart' then
				if Settings.CanGiveUp.Value and (torso.Position - Monster:GetCFrame().p).magnitude > Monster:GetMaximumDetectionDistance() then
					-- Сдался (цель слишком далеко) — шкала остывает с нуля, скорость обычная.
					Mind.CurrentTargetHumanoid.Value = nil
					Watch.Suspicion = 0
				end
			end
		end
	end
end

--
--
Monster:Initialize()
Monster:InitializeUnique()

local lastUpdate = tick()
while true do
	local now = tick()
	local dt = now - lastUpdate
	lastUpdate = now

	if not Monster:IsAlive() then
		if Data.IsDead == false then
			Data.IsDead = true
			Data.TimeOfDeath = tick()
			Self.Died:Fire()
		end
		if Data.IsDead == true then
			if tick()-Data.TimeOfDeath > Info.RespawnWaitTime then
				Monster:Respawn()
				Data.IsDead = false
			end
		end
	end

	if Monster:IsAlive() then
		Monster:Update(dt)
	end

	wait()
end
