--[[
	Basic Monster by ArceusInator — + СЛЕЖКА (зрение/подозрение) и ЗОВ НА ПОМОЩЬ (отряд)

	База — «Basic Monster» (структура Monster:Method(), Configurations / Mind /
	Respawn / Died / Respawned). Сохранены движение, преследование, прыжки и атака,
	которые тебе нравятся. Добавлено две системы из пирата-сторожа:

	  • СЛЕЖКА (стиль Far Cry / AC). Монстр НЕ агрится мгновенно на ближайшего
	    игрока. Он «замечает» по зрению: угол от глаз до игрока (спереди быстро,
	    сбоку медленно, сзади не видит) + луч-обзор (стена рвёт). Копится шкала
	    подозрения 0..100 (полоса над головой бело→жёлтый→красный). На 100% берёт
	    игрока целью (Mind.CurrentTargetHumanoid) — дальше работает прежняя погоня.

	  • ЗОВ НА ПОМОЩЬ (отряд). Заметив игрока (100%) или получив удар, монстр
	    «кричит»: соседним монстрам с тегом PirateGuard в радиусе ставит цель —
	    того же игрока, и они подтягиваются. Передача через атрибуты
	    AlertClock/AlertPosition/AlertUserId (реакция событийная).

	Дополнительно модернизировано под текущий Roblox:
	  • Пасфайндинг ComputeSmoothPathAsync (УДАЛЁН из API) → CreatePath/ComputeAsync.
	  • Устаревшие лучи FindPartOnRay* → workspace:Raycast.
	  • Цель ищется по HumanoidRootPart (а не только R6 .Torso) — работает и с R15.

	Куда вставлять: тот же серверный Script внутри модели монстра (как и раньше).
--]]

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService  = game:GetService("CollectionService")
local RunService         = game:GetService("RunService")

local Self     = script.Parent
local Settings = Self:FindFirstChild("Configurations")
local Mind     = Self:FindFirstChild("Mind")

--
-- Verify that everything is where it should be
assert(Self:FindFirstChild("Humanoid") ~= nil, "Monster does not have a humanoid")
assert(Settings ~= nil, "Monster does not have a Configurations object")
	assert(Settings:FindFirstChild("MaximumDetectionDistance") ~= nil and Settings.MaximumDetectionDistance:IsA("NumberValue"), "Monster does not have a MaximumDetectionDistance (NumberValue) setting")
	assert(Settings:FindFirstChild("CanGiveUp") ~= nil and Settings.CanGiveUp:IsA("BoolValue"), "Monster does not have a CanGiveUp (BoolValue) setting")
	assert(Settings:FindFirstChild("CanRespawn") ~= nil and Settings.CanRespawn:IsA("BoolValue"), "Monster does not have a CanRespawn (BoolValue) setting")
	assert(Settings:FindFirstChild("SpawnPoint") ~= nil and Settings.SpawnPoint:IsA("Vector3Value"), "Monster does not have a SpawnPoint (Vector3Value) setting")
	assert(Settings:FindFirstChild("AutoDetectSpawnPoint") ~= nil and Settings.AutoDetectSpawnPoint:IsA("BoolValue"), "Monster does not have a AutoDetectSpawnPoint (BoolValue) setting")
	assert(Settings:FindFirstChild("FriendlyTeam") ~= nil and Settings.FriendlyTeam:IsA("BrickColorValue"), "Monster does not have a FriendlyTeam (BrickColorValue) setting")
	assert(Settings:FindFirstChild("AttackDamage") ~= nil and Settings.AttackDamage:IsA("NumberValue"), "Monster does not have a AttackDamage (NumberValue) setting")
	assert(Settings:FindFirstChild("AttackFrequency") ~= nil and Settings.AttackFrequency:IsA("NumberValue"), "Monster does not have a AttackFrequency (NumberValue) setting")
	assert(Settings:FindFirstChild("AttackRange") ~= nil and Settings.AttackRange:IsA("NumberValue"), "Monster does not have a AttackRange (NumberValue) setting")
assert(Mind ~= nil, "Monster does not have a Mind object")
	assert(Mind:FindFirstChild("CurrentTargetHumanoid") ~= nil and Mind.CurrentTargetHumanoid:IsA("ObjectValue"), "Monster does not have a CurrentTargetHumanoid (ObjectValue) mind setting")
assert(Self:FindFirstChild("Respawn") and Self.Respawn:IsA("BindableFunction"), "Monster does not have a Respawn BindableFunction")
assert(Self:FindFirstChild("Died") and Self.Died:IsA("BindableEvent"), "Monster does not have a Died BindableEvent")
assert(Self:FindFirstChild("Respawned") and Self.Respawned:IsA("BindableEvent"), "Monster does not have a Respawned BindableEvent")

--
--
local Info = {
	-- Advanced settings
	RecomputePathFrequency = 1,
	RespawnWaitTime = 5,
	JumpCheckFrequency = 1,

	-- ── СЛЕЖКА (зрение / подозрение) ───────────────────────────────────
	SightRange        = 60,   -- дальше этого вообще не замечает (визуально)
	FovFrontDegrees   = 50,   -- спереди замечает быстро
	FovSideDegrees    = 110,  -- сбоку медленно; за этим — не видит
	EyeHeightOffset   = 1,
	SuspicionGainFront = 90,
	SuspicionGainSide  = 35,
	SuspicionDecay     = 25,
	SuspicionInvestigate = 50,  -- порог: идём ПРОВЕРИТЬ место (жёлтая полоса)
	SuspicionAlert       = 100, -- порог захвата цели + крика
	PointBlankRange    = 8,     -- ближе — замечает мгновенно, в любом угле
	InvestigateReach   = 4,     -- считаем, что «дошли до места»
	InvestigateTimeout = 12,    -- сколько держим тревогу по дороге к месту, если не видим
	InvestigateSpeed   = 10,    -- скорость шага к подозрительному месту

	-- ── ЗОВ НА ПОМОЩЬ (отряд) ──────────────────────────────────────────
	GuardTag        = "PirateGuard",
	SquadAlertRadius = 200,  -- кого поднимает крик
	AlertMemory      = 8,    -- сколько секунд помнить чужой крик
	ShoutInterval    = 2,    -- как часто перекрикивать в бою
	DebugSquad       = false,

	-- Пасфайндинг
	AgentRadius  = 2,
	AgentHeight  = 5,
	AgentCanJump = true,
}

local Data = {
	LastRecomputePath = 0,
	Recomputing = false,
	PathCoords = {},
	IsDead = false,
	TimeOfDeath = 0,
	CurrentNode = nil,
	CurrentNodeIndex = 1,
	AutoRecompute = true,
	LastJumpCheck = 0,
	LastAttack = 0,

	-- Слежка
	Suspicion = 0,
	LastKnownPos = nil,
	InvestigateDeadline = 0,
	GoalPos = nil,
	NextScanClock = 0,
	ScanYaw = nil,

	-- Отряд
	AlertedUntil = 0,
	AlertPos = nil,
	AlertUserId = nil,
	LastShout = 0,

	BaseWalkSpeed = 16,

	BaseMonster = Self:Clone(),
	AttackTrack = nil,
}

--
--
local Monster = {}

-- ── Базовые геттеры рига ───────────────────────────────────────────────

function Monster:GetHRP()
	return Self:FindFirstChild("HumanoidRootPart")
end

function Monster:GetHead()
	return Self:FindFirstChild("Head") or Monster:GetHRP()
end

function Monster:GetCFrame()
	local hrp = Monster:GetHRP()
	if hrp and hrp:IsA("BasePart") then
		return hrp.CFrame
	end
	return CFrame.new()
end

function Monster:GetMaximumDetectionDistance()
	local setting = Settings.MaximumDetectionDistance.Value
	if setting < 0 then return math.huge else return setting end
end

function Monster:IsAlive()
	return Self.Humanoid.Health > 0 and Monster:GetHRP() ~= nil
end

-- Корень персонажа: HumanoidRootPart (R6/R15) или Torso/UpperTorso.
local function characterRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character.PrimaryPart
end

function Monster:TargetIsValid()
	local targetHumanoid = Mind.CurrentTargetHumanoid.Value
	if targetHumanoid ~= nil and targetHumanoid:IsA("Humanoid") and targetHumanoid.Health > 0 then
		local character = targetHumanoid.Parent
		local root = character and characterRoot(character)
		return root ~= nil and root:IsA("BasePart")
	end
	return false
end

function Monster:GetTargetPosition()
	if not Monster:TargetIsValid() then return nil end
	return characterRoot(Mind.CurrentTargetHumanoid.Value.Parent).Position
end

--====================================================
-- СЛЕЖКА (зрение + подозрение)
--====================================================

function Monster:GetEyePosition()
	return Monster:GetHead().Position + Vector3.new(0, Info.EyeHeightOffset, 0)
end

function Monster:GetLookDirection()
	local look = Monster:GetCFrame().LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Прямая видимость до точки: луч от глаз, стена/препятствие рвут обзор.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true

function Monster:CanSeeCharacter(character, root)
	sightParams.FilterDescendantsInstances = { Self, character }
	local origin = Monster:GetEyePosition()
	local result = workspace:Raycast(origin, root.Position - origin, sightParams)
	return result == nil
end

-- Полоса подозрения над головой.
function Monster:CreateSuspicionBar()
	local head = Monster:GetHead()
	if not head then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "SuspicionBar"
	gui.Size = UDim2.new(0, 80, 0, 8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.Adornee = head
	gui.Parent = head

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.4
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	Data.SuspicionGui = gui
	Data.SuspicionFill = fill
end

function Monster:UpdateSuspicionBar()
	if not Data.SuspicionGui then return end
	Data.SuspicionGui.Enabled = Data.Suspicion > 1
	Data.SuspicionFill.Size = UDim2.new(math.clamp(Data.Suspicion / 100, 0, 1), 0, 1, 0)
	if Data.Suspicion >= Info.SuspicionAlert then
		Data.SuspicionFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	elseif Data.Suspicion >= Info.SuspicionInvestigate then
		Data.SuspicionFill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
	else
		Data.SuspicionFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

-- Игрок враждебен (не на дружественной команде)?
local function isHostilePlayer(player)
	return player.Neutral or player.TeamColor ~= Settings.FriendlyTeam.Value
end

-- Зрение: копит подозрение по FOV + LOS; на 100% берёт игрока целью и кричит.
-- Возвращает true, если кого-то видно в этот кадр (спад подозрения решает Update).
function Monster:UpdatePerception(dt)
	-- Уже есть цель — слежку не трогаем, погоня сама ведёт.
	if Monster:TargetIsValid() then
		Data.Suspicion = 100
		Monster:UpdateSuspicionBar()
		return true
	end

	local lookDir = Monster:GetLookDirection()
	local eye = Monster:GetEyePosition()
	local bestPlayer, bestRoot, bestDist = nil, nil, math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if isHostilePlayer(player) then
			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if character and hum and hum.Health > 0 then
				local root = characterRoot(character)
				if root then
					local flat = Vector3.new(root.Position.X - eye.X, 0, root.Position.Z - eye.Z)
					local dist = flat.Magnitude
					if dist > 0.05 and dist <= Info.SightRange then
						local angle = math.deg(math.acos(math.clamp(lookDir:Dot(flat.Unit), -1, 1)))
						local gain = nil
						if angle <= Info.FovFrontDegrees then
							gain = Info.SuspicionGainFront
						elseif angle <= Info.FovSideDegrees then
							gain = Info.SuspicionGainSide
						end
						-- Вплотную «не заметить» нельзя — в любом угле.
						if dist <= Info.PointBlankRange then
							gain = Info.SuspicionGainFront
						end
						if gain and Monster:CanSeeCharacter(character, root) then
							local distFactor = 1 - (dist / Info.SightRange) * 0.6
							Data.Suspicion = math.min(100, Data.Suspicion + gain * distFactor * dt)
							if dist < bestDist then
								bestDist, bestPlayer, bestRoot = dist, player, root
							end
						end
					end
				end
			end
		end
	end

	if bestRoot then
		-- Видим — запоминаем место и продлеваем «память» по дороге к нему.
		Data.LastKnownPos = bestRoot.Position
		Data.InvestigateDeadline = os.clock() + Info.InvestigateTimeout
	end

	-- Захват цели на 100%.
	if Data.Suspicion >= Info.SuspicionAlert and bestPlayer then
		Mind.CurrentTargetHumanoid.Value = bestPlayer.Character:FindFirstChildOfClass("Humanoid")
		Monster:BroadcastAlert() -- первый крик отряду
	end

	Monster:UpdateSuspicionBar()
	return bestRoot ~= nil
end

-- Лёгкий осмотр по сторонам, пока нет цели (чтобы замечать и сбоку/сзади).
function Monster:IdleScan()
	if Monster:TargetIsValid() then return end
	local hrp = Monster:GetHRP()
	if not hrp then return end
	if os.clock() >= Data.NextScanClock then
		Data.NextScanClock = os.clock() + math.random(15, 30) * 0.1
		local _, yaw = hrp.CFrame:ToOrientation()
		Data.ScanYaw = yaw + math.rad(math.random(-80, 80))
	end
	if Data.ScanYaw then
		local _, yaw = hrp.CFrame:ToOrientation()
		local diff = (Data.ScanYaw - yaw + math.pi) % (2 * math.pi) - math.pi
		local step = math.clamp(diff, -math.rad(1.5), math.rad(1.5))
		hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw + step, 0)
	end
end

--====================================================
-- ЗОВ НА ПОМОЩЬ (отряд)
--====================================================

function Monster:BroadcastAlert()
	local targetHum = Mind.CurrentTargetHumanoid.Value
	local character = targetHum and targetHum.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	local userId = player and player.UserId or 0
	local pos = Data.LastKnownPos or Monster:GetCFrame().Position
	Data.LastShout = os.clock()

	local raised = 0
	for _, other in ipairs(CollectionService:GetTagged(Info.GuardTag)) do
		if other ~= Self then
			local otherRoot = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart")
			if otherRoot and (otherRoot.Position - Monster:GetCFrame().Position).Magnitude <= Info.SquadAlertRadius then
				other:SetAttribute("AlertPosition", pos)
				other:SetAttribute("AlertUserId", userId)
				other:SetAttribute("AlertClock", os.clock()) -- меняем последним — триггерит реакцию
				raised += 1
			end
		end
	end
	if Info.DebugSquad then
		print(string.format("[Squad] %s кричит отряду (поднято %d)", Self.Name, raised))
	end
end

function Monster:ConnectSquad()
	Self:GetAttributeChangedSignal("AlertClock"):Connect(function()
		Data.AlertedUntil = os.clock() + Info.AlertMemory
		Data.AlertPos = Self:GetAttribute("AlertPosition")
		Data.AlertUserId = Self:GetAttribute("AlertUserId")
		if Info.DebugSquad then
			print(string.format("[Squad] %s услышал крик отряда", Self.Name))
		end
	end)
end

-- Реакция на чужой крик: если сами без цели — берём того же игрока и идём на него.
function Monster:ReactToSquad()
	if Monster:TargetIsValid() then return end
	if os.clock() >= Data.AlertedUntil then return end

	if Data.AlertUserId and Data.AlertUserId > 0 then
		local player = Players:GetPlayerByUserId(Data.AlertUserId)
		if player and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				Mind.CurrentTargetHumanoid.Value = hum
				Data.LastKnownPos = Data.AlertPos
				Data.Suspicion = math.max(Data.Suspicion, Info.SuspicionInvestigate)
			end
		end
	end
end

--====================================================
-- ПАСФАЙНДИНГ (модернизирован: CreatePath / ComputeAsync)
--====================================================

-- Фильтр луча: исключаем себя и (если есть) персонажа текущей цели, чтобы цель
-- сама не «загораживала» обзор/не считалась преградой для прыжка.
local function losFilter()
	local t = Mind.CurrentTargetHumanoid.Value
	if t and t.Parent then
		return { Self, t.Parent }
	end
	return { Self }
end

function Monster:HasClearLineOfSightTo(goalPos)
	local myPos = Monster:GetCFrame().Position
	sightParams.FilterDescendantsInstances = losFilter()
	local result = workspace:Raycast(myPos, goalPos - myPos, sightParams)
	return result == nil
end

-- Считаем маршрут к ПРОИЗВОЛЬНОЙ точке (игрок ИЛИ подозрительное место). Прямая
-- видимость → идём прямо; иначе обходим по PathfindingService.
function Monster:RecomputePathTo(goalPos)
	if Data.Recomputing then return end
	if not Monster:IsAlive() then return end

	local myPos = Monster:GetCFrame().Position
	if Monster:HasClearLineOfSightTo(goalPos) then
		Data.AutoRecompute = true
		Data.PathCoords = { myPos, goalPos }
		Data.LastRecomputePath = tick()
		Data.CurrentNode = nil
		Data.CurrentNodeIndex = 2
		return
	end

	Data.Recomputing = true
	Data.AutoRecompute = false
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = Info.AgentRadius,
			AgentHeight = Info.AgentHeight,
			AgentCanJump = Info.AgentCanJump,
		})
		local ok = pcall(function()
			path:ComputeAsync(Monster:GetCFrame().Position, goalPos)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local coords = {}
			for _, wp in ipairs(path:GetWaypoints()) do
				table.insert(coords, wp.Position)
			end
			Data.PathCoords = coords
			Data.CurrentNode = nil
			Data.CurrentNodeIndex = 1
		else
			-- Не нашли путь — идём напрямую.
			Data.PathCoords = { Monster:GetCFrame().Position, goalPos }
			Data.CurrentNode = nil
			Data.CurrentNodeIndex = 2
		end
		Data.Recomputing = false
		Data.LastRecomputePath = tick()
	end)
end

-- Идти к точке: ставит скорость, при необходимости пересчитывает путь и едет по
-- нему. doAttack=true — бьём цель в радиусе (только в погоне).
function Monster:NavigateTo(goalPos, speed, doAttack)
	Self.Humanoid.WalkSpeed = speed
	local goalMoved = Data.GoalPos and (Data.GoalPos - goalPos).Magnitude > 5
	Data.GoalPos = goalPos
	if Data.AutoRecompute or goalMoved or tick() - Data.LastRecomputePath > 1 / Info.RecomputePathFrequency then
		Monster:RecomputePathTo(goalPos)
	end
	Monster:TravelPath(doAttack)
end

--====================================================
-- ПРЫЖКИ / АТАКА / ДВИЖЕНИЕ (как в Basic Monster, на современных лучах)
--====================================================

local jumpParams = RaycastParams.new()
jumpParams.FilterType = Enum.RaycastFilterType.Exclude
jumpParams.IgnoreWater = true

function Monster:IsSwimming()
	return Self.Humanoid:GetState() == Enum.HumanoidStateType.Swimming
end

function Monster:JumpCheck()
	-- В воде прыгаем настойчиво — иначе Humanoid сам на плот/берег из воды не лезет.
	if Monster:IsSwimming() then
		Self.Humanoid.Jump = true
		Data.LastJumpCheck = tick()
		return
	end

	local myCFrame = Monster:GetCFrame()
	local goal = Data.GoalPos
	if not goal then return end

	local checkVector = (goal - myCFrame.Position)
	if checkVector.Magnitude < 0.1 then return end
	checkVector = checkVector.Unit * 2

	jumpParams.FilterDescendantsInstances = losFilter()
	local low = workspace:Raycast(myCFrame.Position + Vector3.new(0, -2.4, 0), checkVector, jumpParams)
	if low then
		local high = workspace:Raycast(myCFrame.Position + Vector3.new(0, -2.3, 0), checkVector, jumpParams)
		if high and high.Instance == low.Instance then
			if ((high.Position - low.Position) * Vector3.new(1, 0, 1)).Magnitude < 0.05 then
				Self.Humanoid.Jump = true
			end
		end
	end
	Data.LastJumpCheck = tick()
end

function Monster:TryJumpCheck()
	if tick() - Data.LastJumpCheck > 1 / Info.JumpCheckFrequency then
		Monster:JumpCheck()
	end
end

function Monster:Attack()
	local myPos = Monster:GetCFrame().Position
	local targetPos = Monster:GetTargetPosition()
	if not targetPos then return end

	if (myPos - targetPos).Magnitude <= Settings.AttackRange.Value then
		Mind.CurrentTargetHumanoid.Value:TakeDamage(Settings.AttackDamage.Value)
		Data.LastAttack = tick()
		if Data.AttackTrack then
			Data.AttackTrack:Play()
		end
		-- Если на риге есть оружие-Tool (ClassicSword и т.п.) — активируем тоже.
		local tool = Self:FindFirstChildWhichIsA("Tool")
		if tool then
			pcall(function() tool:Activate() end)
		end
	end
end

function Monster:TryAttack()
	if tick() - Data.LastAttack > 1 / Settings.AttackFrequency.Value then
		Monster:Attack()
	end
end

function Monster:TravelPath(doAttack)
	if #Data.PathCoords == 0 then return end
	local myPosition = Monster:GetCFrame().Position
	local skipCurrentNode = Data.CurrentNode ~= nil and (Data.CurrentNode - myPosition).Magnitude < 3

	local closest, closestDistance, closestIndex
	for i = Data.CurrentNodeIndex, #Data.PathCoords do
		local coord = Data.PathCoords[i]
		if not (skipCurrentNode and coord == Data.CurrentNode) then
			local distance = (coord - myPosition).Magnitude
			if closest == nil then
				closest, closestDistance, closestIndex = coord, distance, i
			elseif distance < closestDistance then
				closest, closestDistance, closestIndex = coord, distance, i
			else
				break
			end
		end
	end

	if closest ~= nil then
		Data.CurrentNode = closest
		Data.CurrentNodeIndex = closestIndex
		Self.Humanoid:MoveTo(closest)

		if Monster:IsAlive() then
			Monster:TryJumpCheck() -- прыгаем через мелкие преграды и в погоне, и при проверке места
			if doAttack and Monster:TargetIsValid() then
				Monster:TryAttack()
			end
		end

		if closestIndex == #Data.PathCoords then
			Data.AutoRecompute = true
		end
	end
end

--====================================================
-- ВЫБЫВАНИЕ ЦЕЛИ / ОБНОВЛЕНИЕ / ЖИЗНЕННЫЙ ЦИКЛ
--====================================================

function Monster:ReevaluateTarget()
	local currentTarget = Mind.CurrentTargetHumanoid.Value
	if currentTarget == nil or not currentTarget:IsA("Humanoid") then return end

	local character = currentTarget.Parent
	if character then
		local player = Players:GetPlayerFromCharacter(character)
		if player and not isHostilePlayer(player) then
			Mind.CurrentTargetHumanoid.Value = nil
			Data.Suspicion = 0
			return
		end
	end

	if currentTarget.Health <= 0 then
		Mind.CurrentTargetHumanoid.Value = nil
		Data.Suspicion = 0
		return
	end

	local root = character and characterRoot(character)
	if root and Settings.CanGiveUp.Value then
		if (root.Position - Monster:GetCFrame().Position).Magnitude > Monster:GetMaximumDetectionDistance() then
			Mind.CurrentTargetHumanoid.Value = nil
			Data.Suspicion = 0
		end
	end
end

local function decaySuspicion(dt)
	Data.Suspicion = math.max(0, Data.Suspicion - Info.SuspicionDecay * dt)
end

function Monster:Update(dt)
	Monster:ReevaluateTarget()
	Monster:ReactToSquad()
	local visible = Monster:UpdatePerception(dt)

	-- В воде каждый кадр жмём прыжок — так Humanoid выскакивает на плот/берег
	-- (сам он из воды на уступ не залезает). Направление даёт MoveTo ниже.
	if Monster:IsSwimming() then
		Self.Humanoid.Jump = true
	end

	-- 100%: захвачена цель — погоня и удар (как в Basic Monster).
	if Monster:TargetIsValid() then
		if os.clock() - Data.LastShout >= Info.ShoutInterval then
			Monster:BroadcastAlert() -- перекрикиваем, обновляя позицию игрока отряду
		end
		Monster:NavigateTo(Monster:GetTargetPosition(), Data.BaseWalkSpeed, true)
		return
	end

	-- 50..99%: цель не захвачена, но видели подозрительное — идём ПРОВЕРИТЬ место.
	if Data.Suspicion >= Info.SuspicionInvestigate and Data.LastKnownPos then
		local myP = Monster:GetCFrame().Position
		local flat = Vector3.new(Data.LastKnownPos.X - myP.X, 0, Data.LastKnownPos.Z - myP.Z)
		if flat.Magnitude > Info.InvestigateReach then
			-- В пути к месту. Память держим, пока не истёк таймаут с последнего «вижу»
			-- (иначе, если место недостижимо, в конце концов отпускаем).
			Monster:NavigateTo(Data.LastKnownPos, Info.InvestigateSpeed, false)
			if not visible and os.clock() >= Data.InvestigateDeadline then
				decaySuspicion(dt)
			end
		else
			-- Дошли до места — осматриваемся и начинаем забывать.
			Monster:IdleScan()
			if not visible then
				decaySuspicion(dt)
			end
			if Data.Suspicion < Info.SuspicionInvestigate * 0.5 then
				Data.LastKnownPos = nil
			end
		end
		return
	end

	-- Спокойно. Если упал в воду — плывём на пост (на сушу) и выпрыгиваем; иначе
	-- осматриваемся.
	if Monster:IsSwimming() then
		Monster:NavigateTo(Settings.SpawnPoint.Value, Data.BaseWalkSpeed, false)
	else
		Monster:IdleScan()
	end
	if not visible then
		decaySuspicion(dt)
	end
end

function Monster:InitializeUnique()
	local attackAnim = script:FindFirstChild("Attack")
	if attackAnim and attackAnim:IsA("Animation") then
		local ok, track = pcall(function()
			return Self.Humanoid:LoadAnimation(attackAnim)
		end)
		if ok then Data.AttackTrack = track end
	end
end

function Monster:Respawn(point)
	point = point or Settings.SpawnPoint.Value
	for _, obj in ipairs(Data.BaseMonster:Clone():GetChildren()) do
		if obj.Name == "Configurations" or obj.Name == "Mind" or obj.Name == "Respawned"
			or obj.Name == "Died" or obj.Name == "MonsterScript" or obj.Name == "Respawn"
			or obj.Name == script.Name then
			obj:Destroy()
		else
			local existing = Self:FindFirstChild(obj.Name)
			if existing then existing:Destroy() end
			obj.Parent = Self
		end
	end

	Monster:InitializeUnique()
	Monster:CreateSuspicionBar()
	Data.Suspicion = 0
	Mind.CurrentTargetHumanoid.Value = nil
	Data.IsDead = false

	Self.Parent = workspace
	Self.HumanoidRootPart.CFrame = CFrame.new(point)
	Settings.SpawnPoint.Value = point
	Self.Respawned:Fire()
end

function Monster:Initialize()
	Mind.CurrentTargetHumanoid.Changed:Connect(function(humanoid)
		if humanoid ~= nil and humanoid:IsA("Humanoid") then
			local tp = Monster:GetTargetPosition()
			if tp then Monster:RecomputePathTo(tp) end
		end
	end)

	Self.Respawn.OnInvoke = function(point)
		Monster:Respawn(point)
	end

	if Settings.AutoDetectSpawnPoint.Value then
		Settings.SpawnPoint.Value = Monster:GetCFrame().Position
	end

	-- Запоминаем «боевую» скорость рига (для проверки места идём медленнее).
	Data.BaseWalkSpeed = (Self.Humanoid.WalkSpeed and Self.Humanoid.WalkSpeed > 0) and Self.Humanoid.WalkSpeed or 16

	CollectionService:AddTag(Self, Info.GuardTag)
	if not Self.PrimaryPart then
		Self.PrimaryPart = Monster:GetHRP()
	end
	Monster:ConnectSquad()
	Monster:CreateSuspicionBar()
end

--
--
Monster:Initialize()
Monster:InitializeUnique()

local lastTick = tick()
while true do
	local now = tick()
	local dt = now - lastTick
	lastTick = now

	if not Monster:IsAlive() then
		if Data.IsDead == false then
			Data.IsDead = true
			Data.TimeOfDeath = tick()
			Self.Died:Fire()
		end
		if Data.IsDead == true and Settings.CanRespawn.Value then
			if tick() - Data.TimeOfDeath > Info.RespawnWaitTime then
				Monster:Respawn()
			end
		end
	end

	if Monster:IsAlive() then
		Monster:Update(dt)
	end

	RunService.Heartbeat:Wait()
end
