local SPEED = 8 -- base forward drift along the bow (studs/s); 0 = hold position
local PADDLE_BOOST = 10 -- extra m/s added to base speed during a paddle stroke (×2: paddle felt weak)
local PADDLE_DECAY = 1.5 -- seconds for paddle boost to decay
local PADDLE_COURSE_NUDGE = math.rad(6) -- max course rotation per paddle stroke (×2: paddle felt weak)

-- Strength of the velocity correction. Higher = the raft locks onto its
-- bow-aligned target velocity faster (kills sideways drift more aggressively).
local VELOCITY_GAIN = 6
local Y_KP = 25            -- пружина к ватерлинии (студ/с² на стад), см. вертикальный ПД-регулятор
local Y_KD = 10            -- демпфер = 2·√KP: критическое затухание, без качки

-- Custom buoyancy: fully counteracts gravity so the raft hovers at waterY,
-- then a spring-damper corrects any displacement. Without gravity
-- compensation, the spring alone would need enormous stiffness to fight
-- the 196.2 studs/s² gravity — at stiffness 8 the raft sinks ~25 studs.
-- (the old BUOYANCY spring constants are gone: vertical hold is now a rigid Y-axis AlignPosition
-- constraint — see below — after the hand-rolled spring kept resonating with standing players)

-- ─── Wind event ───
-- Ветер включается с 3-го дня. Приходит СЛУЧАЙНО раз в 1.5–3 суток (не по
-- фиксированному таймеру, иначе игроки выучивают расписание и просто ждут его).
-- Сутки = день+ночь из DayNightCircle (380+120 = 500с); поменяешь длину дня —
-- обнови и здесь (это отдельный файл, автоматически не подтянется).
local WIND_START_DAY = 3 -- wind is unlocked at the start of this day
local WIND_CYCLE        = 380 + 120 -- цикл суток (день 380 + ночь 120)
local WIND_INTERVAL_MIN = 1.5 * WIND_CYCLE -- 750с
local WIND_INTERVAL_MAX = 3   * WIND_CYCLE -- 1500с
local WIND_DURATION = 15 -- seconds the wind blows
local WIND_PLAYER_ACCEL = 400 -- studs/s² horizontal force applied to players standing on the raft
local WIND_AIRBORNE_ACCEL = 30 -- much smaller force while the player is in the air, so a jump doesn't launch them
local WIND_SHELTER_DISTANCE = 50 -- studs; max distance the upwind shelter probe checks
local WIND_SHELTER_BOX_SIZE = Vector3.new(3, 5, 3) -- approximate character cross-section for the Blockcast
local TURN_SPEED = 0.6 -- radians/sec for big course changes (wind)
local PADDLE_TURN_RATE = math.rad(1.8) -- deg/sec for small (paddle-sized) course corrections: a 6°
                       -- stroke turns LINEARLY over ~3.5s — visible the whole time. The earlier
                       -- exponential ease faded below what the eye can see and read as "the turn
                       -- ended early". Rates blend between the two tiers by remaining angle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do
	task.wait(0.1)
end

local primaryPart = boat.PrimaryPart

-- Capture water surface Y while the raft is still anchored at its placed
-- position. This is the target height for the buoyancy spring.
local waterY = primaryPart.Position.Y

-- Collision groups (T29/T34). Floating resources (logs / leaves /
-- plastic canisters) are kept in "FloatingResource" so they drift
-- past the raft AND past players without applying contact impulses.
-- The raft + everything ever welded onto it lives in "Raft", and
-- "FloatingResource" is configured non-collidable against both Raft
-- AND Default — so anything not tagged Raft (most things in the
-- world, including players and any not-yet-tagged raft part) also
-- ignores resources. Resources keep CanCollide = true so terrain
-- water buoyancy keeps them floating.
local PhysicsService = game:GetService("PhysicsService")
local function ensureGroup(name)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end
ensureGroup("Raft")
ensureGroup("FloatingResource")
pcall(function()
	PhysicsService:CollisionGroupSetCollidable("Raft", "FloatingResource", false)
end)
-- Previously we also disabled Default ↔ FloatingResource collisions so
-- characters / mercenaries wouldn't get bumped by passing logs. That
-- side-effect, though, was that resources also stopped interacting with
-- TERRAIN (terrain lives in the Default group) — including the water
-- voxels — so Roblox's native water buoyancy never applied and every
-- spawned resource dropped through the surface to the seabed. Keep
-- only the Raft-vs-Resource and Resource-vs-Resource rules so the
-- water still pushes them up.
pcall(function()
	PhysicsService:CollisionGroupSetCollidable("FloatingResource", "FloatingResource", false)
end)

local ownerPending, ownerScheduled = {}, false
local function reassertOwner()
	ownerScheduled = false
	local parts = ownerPending
	ownerPending = {}
	-- по одному вызову на сборку: обычно это одна сборка плота, а отдельная
	-- (не приваренная) деталь внутри Raft получает своего владельца, как раньше
	local done = {}
	for part in pairs(parts) do
		if part.Parent and not part.Anchored then
			local root = part.AssemblyRootPart or part
			if not done[root] and not root.Anchored then
				done[root] = true
				pcall(function()
					if root:GetNetworkOwner() ~= nil or root:GetNetworkOwnershipAuto() then
						root:SetNetworkOwner(nil)
					end
				end)
			end
		end
	end
end

local function tagRaftPart(part)
	if part and part:IsA("BasePart") then
		part.CollisionGroup = "Raft"
		-- no terrain-water buoyancy/drag on the hull: vertical support is the exact gravity
		-- compensation below; extra fluid lift made the raft creep upward every frame and the
		-- height correction had to keep re-writing its position ("teleporting" movement)
		pcall(function() part.EnableFluidForces = false end)
		-- Pin NetworkOwner to the server (T33). Without this, Roblox
		-- can reassign physics ownership of newly-welded parts to a
		-- nearby player; replication jitter from the player's client
		-- then pumps the buoyancy spring through the rigid welds and
		-- the raft slowly bobs. BuildingSystem's wall placement has
		-- always done this in unanchorAndPin — that's exactly why
		-- walls don't bounce the raft and items did. Deferred because
		-- a part that's anchored at the moment we tag it (placement
		-- systems use Pass 0 force-anchor) errors on SetNetworkOwner.
		--[[ ⚠️ ОДИН РАЗ НА ПАЧКУ И ТОЛЬКО ЕСЛИ ВЛАДЕЛЕЦ СБИЛСЯ. SetNetworkOwner у
		     любой детали — это владение ВСЕЙ сборкой плота. Рыбацкое место — ~60
		     деталей: 60 переназначений владения подряд, и каждое — рывок репликации
		     плота у клиентов. Теперь новые детали собираются в пачку, и в конце
		     кадра один раз проверяем корень сборки. ]]
		ownerPending[part] = true
		if not ownerScheduled then
			ownerScheduled = true
			task.defer(reassertOwner)
		end
	end
end

-- Ensure all raft parts are unanchored so physics (buoyancy, movement) work.
-- SpawnLocations are anchored by default in Studio; if any part in a welded
-- assembly is anchored the entire raft is frozen in place.
for _, desc in boat:GetDescendants() do
	if desc:IsA("BasePart") then
		desc.Anchored = false
		tagRaftPart(desc)
		pcall(function()
			desc:SetNetworkOwner(nil)
		end)
	end
end
primaryPart.Anchored = false
tagRaftPart(primaryPart)

-- Auto-tag every BasePart welded onto the raft as it gets added,
-- so placements (workbench / sawmill / planks / etc.) inherit the
-- raft's CollisionGroup without each placement system having to
-- know about it.
boat.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") then tagRaftPart(d) end
end)

-- Lock the raft as server-controlled. Without this, Roblox auto-assigns
-- network ownership to the nearest player, and any time a new part is
-- welded into the raft assembly the ownership gets recomputed — that
-- transition causes a brief replication desync where the raft visibly
-- disappears and teleports for one frame on every placement.
pcall(function()
	primaryPart:SetNetworkOwner(nil)
end)

-- Store the initial rotation as a full CFrame to avoid gimbal lock.
-- With a PrimaryPart oriented at 90° pitch (e.g. SpawnLocation with
-- Orientation 90,0,0), Euler decomposition via ToEulerAnglesYXZ hits
-- a singularity where yaw and roll become indistinguishable. By keeping
-- the initial rotation as a CFrame and applying yaw changes via direct
-- rotation composition (pre-multiplying a world-Y rotation), the
-- AlignOrientation stays stable at any pitch angle.
local initialRotation = primaryPart.CFrame.Rotation
local _, initialYaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw

-- Store the rest CFrame (used by BuildingSystem for stable placement).
-- The Y component is updated every heartbeat to the raft's actual current Y;
-- we do NOT cache the initial Y, because if the raft happens to spawn above
-- the water surface it still has to fall and settle, and a cached boot-time
-- Y would pin RestCFrame.Y to that stale (non-settled) position forever.
-- BuildingSystem uses RestCFrame.Y to place the cursor projection plane, so
-- a stale Y makes the client think the raft is at a coordinate different
-- from where it actually is, creating a dead strip for the build cursor.
primaryPart:SetAttribute("RestCFrame", primaryPart.CFrame)
primaryPart:SetAttribute("RestYaw", lockedYaw)

-- RemoteEvents
local paddleEvent = Instance.new("RemoteEvent")
paddleEvent.Name = "PaddleAction"
paddleEvent.Parent = ReplicatedStorage

local currentEvent = Instance.new("RemoteEvent")
currentEvent.Name = "OceanCurrentChanged"
currentEvent.Parent = ReplicatedStorage

local windEvent = Instance.new("RemoteEvent")
windEvent.Name = "WindUpdate"
windEvent.Parent = ReplicatedStorage

local attachment = Instance.new("Attachment")
attachment.Parent = primaryPart

local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = attachment
vectorForce.ApplyAtCenterOfMass = true
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.Force = Vector3.new(0, 0, 0)
vectorForce.Parent = primaryPart

-- VERTICAL HOLD: a Y-axis-only AlignPosition constraint. The old hand-rolled buoyancy spring
-- (gravity compensation + spring-damper recomputed once per Heartbeat) reacted to the physics one
-- frame LATE — with a player standing aboard, the player's own Humanoid hip-spring and our spring
-- pumped each other into the endless "raft jumps in place" bug (period ~0.8s, confirmed by the
-- probe even with clean welds and no hitches). A constraint is solved INSIDE every physics substep —
-- zero lag, nothing to resonate. RigidityEnabled pins deck height absolutely; X/Z force is zero so
-- sailing/steering is untouched.
-- (No AlignPosition here: PerAxis force limits live in attachment axes — a nightmare on this
-- rotated-cylinder PrimaryPart, and RigidityEnabled bypasses the limits anyway, which shoved the
-- raft sideways. The vertical hold is done with exact gravity compensation + a per-frame Y clamp
-- in the Heartbeat below — a clamp is not a spring, so there is NOTHING that can resonate.)

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Attachment0 = attachment
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
-- RIGID orientation: the raft is a gameplay platform and must NEVER pitch/roll. The old soft mode
-- (torque-limited, Responsiveness 5) let contact impulses — a walking client-owned player, a server
-- hitch when a big island clones in, anything wedged against the hull — tilt it up to a full capsize
-- (RaftTiltProbe logged 42°/66°/87° events). Rigid mode holds the target orientation as hard as the
-- solver allows every step, so tilt can never accumulate; translation (sailing + buoyancy) is
-- unaffected. Yaw still turns smoothly because the TARGET rotation itself changes slowly (TURN_SPEED).
alignOrientation.RigidityEnabled = true
alignOrientation.MaxTorque = 500000
alignOrientation.Responsiveness = 5
alignOrientation.Parent = primaryPart

-- ─── Direction helpers ───

-- The raft's PrimaryPart is oriented so that its LookVector points along the
-- visible bow of the model. For a CFrame built with Euler order YXZ, the
-- horizontal projection of the LookVector at yaw Y is always (-sin Y, 0, -cos Y),
-- regardless of pitch and roll — so we don't need to rebuild the CFrame here.
local function computeVisualFront(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Inverse: yaw such that computeVisualFront(yaw) == dir.
local function yawFromVisualFront(dir)
	return math.atan2(-dir.X, -dir.Z)
end

local function randomHorizontalDirection()
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- ─── Course state ───
-- The course only changes during a wind event. Outside of wind events the
-- raft holds its current heading.
local currentDirection = computeVisualFront(lockedYaw) -- start matching the raft's current heading
-- ⚠️ Рядом с курсом, а не ниже по файлу: обе переменные пишет _G.SetRaftCourse,
-- и локальная, объявленная после него, для него бы не существовала.
local forwardDirection = computeVisualFront(lockedYaw)

local function broadcastCurrent()
	currentEvent:FireAllClients(currentDirection)
end

--[[ ⚠️ ЕДИНСТВЕННЫЙ СПОСОБ РАЗВЕРНУТЬ ПЛОТ СНАРУЖИ.
     Курс плота живёт здесь и больше нигде: lockedYaw гонится за
     currentDirection каждый кадр, а поворот модели задаёт alignOrientation по
     lockedYaw. Развернуть плот, просто повернув модель, нельзя — этот цикл
     вернёт его обратно в ближайший же кадр.
     Зовёт это карта, когда рейс переносит плот к острову: иначе плот приезжает
     к берегу боком или кормой и тут же начинает уплывать прочь, потому что
     идёт он всегда носом вперёд.
     snap = true разворачивает мгновенно (плот в этот момент под шторкой, и
     видеть поворот некому); без него плот доворачивается сам, как при ветре. ]]
_G.SetRaftCourse = function(dir, snap)
	if typeof(dir) ~= "Vector3" then return false end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.001 then return false end
	currentDirection = flat.Unit
	if snap then
		lockedYaw = yawFromVisualFront(currentDirection)
		forwardDirection = computeVisualFront(lockedYaw)
	end
	broadcastCurrent()
	return true
end

-- ─── Wind state ───
local windActive = false
local windRemainingTime = 0
local windDirection = Vector3.new(0, 0, -1)
-- player -> { force = VectorForce, attach = Attachment }
local affectedPlayers = {}

local function startWindEvent()
	windDirection = randomHorizontalDirection()
	-- The wind redirects the raft's course immediately. The raft will rotate
	-- toward this new heading via the existing turn logic.
	currentDirection = windDirection
	windActive = true
	windRemainingTime = WIND_DURATION

	for _, plr in Players:GetPlayers() do
		plr:SetAttribute("WindActive", true)
	end

	windEvent:FireAllClients(true, WIND_DURATION, WIND_DURATION, windDirection)
	broadcastCurrent()
	print(string.format("[Wind] Wind event started, direction (%.2f, %.2f)", windDirection.X, windDirection.Z))
end

local function detachWindForce(plr)
	local data = affectedPlayers[plr]
	if not data then return end
	if data.force then data.force:Destroy() end
	if data.attach then data.attach:Destroy() end
	affectedPlayers[plr] = nil
end

local function attachWindForce(plr, hrp)
	if affectedPlayers[plr] then return end
	local attach = Instance.new("Attachment")
	attach.Name = "WindAttach"
	attach.Parent = hrp

	local force = Instance.new("VectorForce")
	force.Name = "WindForce"
	force.Attachment0 = attach
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = windDirection * hrp.AssemblyMass * WIND_PLAYER_ACCEL
	force.Parent = hrp

	affectedPlayers[plr] = {force = force, attach = attach, hrp = hrp}
end

-- Reusable raycast params for the shelter check (filter is set per call).
local shelterRayParams = RaycastParams.new()
shelterRayParams.FilterType = Enum.RaycastFilterType.Exclude

-- A player is sheltered if a Blockcast the size of their body, swept from
-- their HRP toward the wind source (i.e. opposite of the wind direction),
-- hits any obstacle. We use a Blockcast instead of a single ray so a wall
-- that's slightly off-center from the HRP still counts as cover, and we
-- give it enough range to cover any reasonable raft layout.
local function isShelteredFromWind(hrp, char)
	if not hrp or not hrp.Parent then return false end
	shelterRayParams.FilterDescendantsInstances = {char}
	local cf = CFrame.new(hrp.Position)
	local result = workspace:Blockcast(cf, WIND_SHELTER_BOX_SIZE, -windDirection * WIND_SHELTER_DISTANCE, shelterRayParams)
	return result ~= nil
end

-- Update force magnitude based on whether the player is grounded and exposed.
-- The grounded force is large (so the wind feels strong while walking), but
-- when the Humanoid leaves the floor (jump / fall) we drop it to a small
-- value so the player doesn't get launched off the raft. If the player is
-- behind an obstacle (wall, log, etc.) on the upwind side, the force is zero.
-- SMOOTHED: the target accel used to SNAP 400↔30↔0 the instant FloorMaterial or the
-- shelter Blockcast flickered (which the bouncing raft itself causes). Each step change
-- kicked the raft through the player's feet → the buoyancy spring rang → more flicker —
-- a self-feeding pump that started with the first wind event. Now the airborne state is
-- debounced (must persist 0.12s) and the accel ramps exponentially (~0.2s) — no steps.
local function updateWindForces(dt)
	for plr, data in pairs(affectedPlayers) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = data.hrp
		if hum and hrp and data.force and data.force.Parent then
			local target
			if isShelteredFromWind(hrp, char) then
				target = 0
			else
				if hum.FloorMaterial == Enum.Material.Air then
					data.airTime = (data.airTime or 0) + dt
				else
					data.airTime = 0
				end
				local airborne = (data.airTime or 0) > 0.12
				target = airborne and WIND_AIRBORNE_ACCEL or WIND_PLAYER_ACCEL
			end
			data.accel = (data.accel or 0) + (target - (data.accel or 0)) * math.clamp(dt * 8, 0, 1)
			data.force.Force = windDirection * hrp.AssemblyMass * data.accel
		end
	end
end

local function releaseAffectedPlayers()
	for plr in pairs(affectedPlayers) do
		detachWindForce(plr)
	end
end

local function endWindEvent()
	windActive = false
	windRemainingTime = 0
	releaseAffectedPlayers()
	for _, plr in Players:GetPlayers() do
		plr:SetAttribute("WindActive", false)
	end
	windEvent:FireAllClients(false, 0, WIND_DURATION, windDirection)
end

task.spawn(function()
	-- Don't blow any wind until the players have lived through the first five
	-- days. DayCount is populated by DayNightCycle.server.lua.
	local dayCount = ReplicatedStorage:WaitForChild("DayCount")
	while dayCount.Value < WIND_START_DAY do
		dayCount:GetPropertyChangedSignal("Value"):Wait()
	end

	-- Ждём ПЕРЕД первым ветром, а не после: иначе он задувал ровно в секунду
	-- наступления 3-го дня — самое предсказуемое событие в игре, при том что
	-- весь смысл рандома был в обратном.
	local windRng = Random.new()
	while true do
		task.wait(windRng:NextNumber(WIND_INTERVAL_MIN, WIND_INTERVAL_MAX))
		startWindEvent()
	end
end)

-- Re-broadcast on player join
Players.PlayerAdded:Connect(function(plr)
	task.wait(2)
	currentEvent:FireClient(plr, currentDirection)
	if windActive then
		plr:SetAttribute("WindActive", true)
		windEvent:FireClient(plr, true, windRemainingTime, WIND_DURATION, windDirection)
	end
end)

-- ─── Player push (raycast filter set up once) ───
local windRayParams = RaycastParams.new()
windRayParams.FilterType = Enum.RaycastFilterType.Include
windRayParams.FilterDescendantsInstances = {boat}

-- ─── Paddle state ───
local paddleBoostRemaining = 0

-- Посадочное удержание входит и выходит ПЛАВНО (см. блок в updateBoat).
-- ⚠️ РАЗГОН КОРОЧЕ (было 2.5). Пока плот набирает ход, персонаж на палубе
-- едет на РЕПЛИЦИРУЕМОЙ платформе: её скорость меняется, а клиент между
-- пакетами дотягивает по прошлой — это и есть «первые секунды рывками».
-- На ровном ходу интерполяция точная. Чем короче разгон, тем короче дрожь.
local RAMP_UP   = 1.2   -- секунд на разгон после удержания
local BOARD_CREEP = 0.35  -- доля хода на посадке (smoothstep → ~28% скорости)
local RAMP_DOWN = 0.8   -- секунд на остановку, когда удержание включилось
local holdRamp  = 0     -- 0 = стоим, 1 = полный ход
local paddleDirection = Vector3.zero

-- Water splash where the paddle blade meets the sea. NOTE: ParticleEmitter:Emit() called on the
-- SERVER does not replicate — clients never see those particles. So the burst is made by enabling
-- the emitters (Rate/Enabled are replicated properties) for a short window instead. No sound —
-- the paddle already has its own.
local Debris = game:GetService("Debris")
local function paddleSplash(pos)
	local a = Instance.new("Part")
	a.Anchored = true; a.CanCollide = false; a.CanQuery = false; a.CanTouch = false
	a.Transparency = 1; a.Size = Vector3.new(1, 1, 1)
	a.CFrame = CFrame.new(pos); a.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = a

	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(190, 225, 245), Color3.fromRGB(235, 248, 255))
	spray.LightEmission = 0.25
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.3, 0.55)
	spray.Speed = NumberRange.new(7, 13)
	spray.SpreadAngle = Vector2.new(55, 55)
	spray.Acceleration = Vector3.new(0, -14, 0)
	spray.Rate = 90
	spray.Parent = att

	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drops.Color = ColorSequence.new(Color3.fromRGB(205, 235, 255))
	drops.LightEmission = 0.5
	drops.Size = NumberSequence.new(0.35, 0.1)
	drops.Lifetime = NumberRange.new(0.35, 0.6)
	drops.Speed = NumberRange.new(14, 22)
	drops.SpreadAngle = Vector2.new(40, 40)
	drops.Acceleration = Vector3.new(0, -60, 0)
	drops.Rate = 120
	drops.Parent = att

	task.delay(0.2, function() -- a ~0.2s enabled window ≈ one juicy burst on every client
		spray.Enabled = false
		drops.Enabled = false
	end)
	Debris:AddItem(a, 1.2)
end

-- Гребок засчитываем ТОЛЬКО тому, кто стоит НА ПЛОТУ. Раньше проверки не было:
-- можно было плавать рядом в воде, грести — и плот послушно разворачивался.
-- Луч вниз из-под ног: попал в деталь плота (палуба, постройка на ней) → свой.
local function isStandingOnRaft(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true -- вода не должна «подпирать» пловца вместо палубы
	local res = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), params)
	return res ~= nil and res.Instance ~= nil and res.Instance:IsDescendantOf(boat)
end

--[[ ⚠️ КУЛДАУН ГРЕБКА ЖИВЁТ И НА СЕРВЕРЕ, А НЕ ТОЛЬКО НА КЛИЕНТЕ.
     На клиенте он есть (PaddleController, COOLDOWN = 1), но клиент — не
     ограничитель: ремоут можно звать с любой частотой. А каждый гребок здесь
     стоит дорого: рейкаст, рассылка курса всем клиентам и ВОСЕМЬ новых
     инстансов всплеска в Workspace. Инстансы в Workspace, в свою очередь, будят
     глобальные подписки других систем (топливо, карта, стабилизатор животных) —
     то есть один гребок множится на число слушателей.
     Полсекунды — половина клиентского кулдауна: честные гребки проходят все,
     а поток из шестидесяти в секунду срезается в стену.
     ⚠️ Проверка стоит ПЕРВОЙ, до рейкаста: иначе спам всё равно оплачивался бы
     лучом на каждое сообщение. ]]
local PADDLE_MIN_GAP = 0.5
local lastPaddleAt = {}
Players.PlayerRemoving:Connect(function(plr) lastPaddleAt[plr] = nil end)

paddleEvent.OnServerEvent:Connect(function(player, direction)
	local now = os.clock()
	if now - (lastPaddleAt[player] or 0) < PADDLE_MIN_GAP then return end
	lastPaddleAt[player] = now
	if typeof(direction) ~= "Vector3" then return end
	if not isStandingOnRaft(player.Character) then return end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 then return end
	paddleDirection = flat.Unit
	paddleBoostRemaining = PADDLE_DECAY

	-- splashes when the blade actually dips: the row animation strokes TWICE, so one splash
	-- mid-first-swing and a second one a second later, each at the water surface just ahead of
	-- where the player is facing at that moment
	local function splashAtBlade()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local look = hrp.CFrame.LookVector
		local lx, lz = look.X, look.Z
		local m = math.sqrt(lx * lx + lz * lz)
		if m < 0.05 then lx, lz = 0, -1 else lx, lz = lx / m, lz / m end
		paddleSplash(Vector3.new(hrp.Position.X + lx * 3.2, waterY + 0.4, hrp.Position.Z + lz * 3.2))
	end
	task.delay(0.35, splashAtBlade)
	task.delay(0.75, splashAtBlade) -- second stroke follows 0.4s after the first

	-- Apply a tiny rotation to the current direction toward where the player paddled.
	-- This is the only way the player can influence the course, and it's intentionally minimal.
	local curAngle = math.atan2(currentDirection.X, currentDirection.Z)
	local pAngle = math.atan2(paddleDirection.X, paddleDirection.Z)
	local diff = math.atan2(math.sin(pAngle - curAngle), math.cos(pAngle - curAngle))
	local nudge = math.clamp(diff, -PADDLE_COURSE_NUDGE, PADDLE_COURSE_NUDGE)
	local cosA = math.cos(nudge)
	local sinA = math.sin(nudge)
	currentDirection = Vector3.new(
		currentDirection.X * cosA + currentDirection.Z * sinA,
		0,
		-currentDirection.X * sinA + currentDirection.Z * cosA
	).Unit
	broadcastCurrent()
end)

-- Initial broadcast after a brief delay so clients can subscribe
task.delay(2, broadcastCurrent)

-- (объявлен выше, рядом с currentDirection: его пишет _G.SetRaftCourse)

RunService.Heartbeat:Connect(function(dt)
	if not primaryPart or not primaryPart.Parent then
		return
	end

	-- Steer locked yaw toward the yaw that points the bow at the current direction.
	-- LINEAR, always-visible rotation: paddle-sized corrections (≤6°) turn at PADDLE_TURN_RATE the
	-- whole way; big course changes (wind) run at TURN_SPEED and blend down to the slow rate over
	-- the last degrees — a natural ease-out that never drops below eye-visible speed.
	local desiredYaw = yawFromVisualFront(currentDirection)
	local diff = desiredYaw - lockedYaw
	diff = math.atan2(math.sin(diff), math.cos(diff))
	local absDiff = math.abs(diff)
	if absDiff < math.rad(0.05) then
		lockedYaw = desiredYaw
	else
		local t = math.clamp((absDiff - math.rad(6)) / (math.rad(30) - math.rad(6)), 0, 1)
		local rate = PADDLE_TURN_RATE + (TURN_SPEED - PADDLE_TURN_RATE) * t
		lockedYaw = lockedYaw + math.sign(diff) * math.min(absDiff, rate * dt)
	end

	-- The raft moves along its current bow direction. The bow rotates smoothly
	-- toward the ocean current (above), so during a turn the velocity simply
	-- arcs along with the bow — the raft can never end up moving sideways or
	-- backwards relative to its front.
	forwardDirection = computeVisualFront(lockedYaw)

	-- HITCH GUARD: after a long server stall (autosave burst, island clone, GC…) just kill any
	-- vertical velocity picked up during the frozen frame; the rigid AlignPosition re-holds waterY
	-- by itself inside the next physics step.
	if dt > 0.25 then
		local v = primaryPart.AssemblyLinearVelocity
		primaryPart.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		return
	end

	local totalMass = primaryPart.AssemblyMass
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	-- Target velocity: constant SPEED along the bow.
	local targetSpeed = SPEED
	if paddleBoostRemaining > 0 then
		targetSpeed = targetSpeed + PADDLE_BOOST * (paddleBoostRemaining / PADDLE_DECAY)
		paddleBoostRemaining = math.max(0, paddleBoostRemaining - dt)
	end
	-- Anchor drag: below 70% depth the anchor doesn't bite at all.
	-- Between 70% and 100% the raft's speed ramps linearly down to 0,
	-- so fully-deployed anchor = full stop and the last ~30% of the
	-- rope produces a natural-feeling braking arc.
	local anchorDepth = boat:GetAttribute("AnchorDepth") or 0
	if anchorDepth > 0.7 then
		local brake = math.clamp((anchorDepth - 0.7) / 0.3, 0, 1)
		targetSpeed = targetSpeed * (1 - brake)
	end
	--[[ ⚠️ ПОСАДОЧНОЕ УДЕРЖАНИЕ: ПЛОТ СТОИТ, ПОКА НЕ ЗАГРУЗИЛИСЬ ВСЕ.
	     Игрок со слабым каналом просыпался в открытой воде: пока его клиент
	     грузится, физику персонажа никто не считает — он висит в мировых
	     координатах, а палуба уходит восемь студов в секунду. Держать одного
	     персонажа оказалось мало: при долгой загрузке удержание кончалось
	     раньше, чем оживал клиент. Поэтому стоит сам плот.
	     Атрибут ставит и снимает SpawnOnRaft — там же таймауты на случай, если
	     кто-то не догрузится никогда, и там же признак готовности от клиента.
	     Ставим ПОСЛЕ якоря и весла: удержание сильнее любого разгона. ]]
	--[[ ⚠️ ТРОГАЕМСЯ И ВСТАЁМ ПЛАВНО, А НЕ РЫВКОМ.
	     Удержание снималось одним кадром: скорость прыгала с нуля до восьми, и
	     сервокоррекция ниже выдавала в этот кадр огромную силу. На клиенте,
	     который только что догрузился, это читалось как телепорт плота — «первые
	     две секунды дёргает». Обратный переход не лучше: мгновенное торможение
	     сдвигает всех, кто стоит на палубе.
	     Поэтому между «стоим» и «полный ход» ездит holdRamp, и скорость идёт по
	     сглаженной кривой: медленно трогается, медленно выходит на режим.
	     Само удержание ставит и снимает SpawnOnRaft — там же таймауты на тех, кто
	     не догрузился, и признак готовности от клиента. ]]
	-- ⚠️ ДВА РАЗНЫХ СТОПА, И ОБА НУЖНЫ.
	-- BoardingHold держит плот, пока в сервер заходят игроки, и ведёт его
	-- SpawnOnRaft: он переставляет атрибут по своему усмотрению каждый цикл.
	-- SailHold ставит карта на время рейса — если бы рейс писал в тот же
	-- атрибут, посадочный цикл снял бы его на первой же итерации, и плот поехал
	-- бы прямо посреди телепорта.
	--[[ ⚠️ НА ПОСАДКЕ ПЛОТ НЕ СТОИТ, А ПОЛЗЁТ (BOARD_CREEP).
	     Зонд показал: дрожь на клиенте длится ~6 с после старта при разгоне в
	     1.2 с — то есть дело не в кривой разгона, а в том, что клиент заново
	     настраивает интерполяцию сборки, которая до этого не двигалась вовсе.
	     Ползущий плот реплицируется всё время загрузки, и к моменту «пошёл»
	     интерполяция уже установилась. Персонажа на палубе держит SpawnOnRaft
	     (ставит со скоростью плота), так что малый ход ему не вредит.
	     SailHold (рейс по карте) по-прежнему полный стоп. ]]
	local wantRamp = 1
	if boat:GetAttribute("SailHold") then
		wantRamp = 0
	elseif boat:GetAttribute("BoardingHold") then
		wantRamp = BOARD_CREEP
	end
	--[[ ⚠️ ЯКОРЬ НАКОНЕЦ ТОРМОЗИТ ПЛОТ.
	     Атрибут AnchorDepth (0..1) выставляет AnchorInteraction — его читал
	     только UI, а движение о якоре не знало вовсе: игрок опускал якорь и
	     продолжал плыть. Отсюда и половина ощущения «якорь не работает».
	     Скорость падает пропорционально глубине, а не выключается щелчком: на
	     половине троса плот идёт вполсилы — это и даёт лебёдке смысл шага в
	     четверть, иначе в ней было бы два положения вместо пяти. ]]
	local anchorDepth = tonumber(boat:GetAttribute("AnchorDepth")) or 0
	wantRamp = wantRamp * (1 - math.clamp(anchorDepth, 0, 1))
	if holdRamp < wantRamp then
		holdRamp = math.min(wantRamp, holdRamp + dt / RAMP_UP)
	elseif holdRamp > wantRamp then
		holdRamp = math.max(wantRamp, holdRamp - dt / RAMP_DOWN)
	end
	if holdRamp < 1 then
		targetSpeed = targetSpeed * (holdRamp * holdRamp * (3 - 2 * holdRamp))   -- smoothstep
	end
	local desiredVelocity = forwardDirection * targetSpeed

	-- Velocity correction force. This simultaneously:
	--   • kills any lateral velocity (sideways drift)
	--   • kills any backwards velocity
	--   • holds forward speed constant at SPEED regardless of turning
	local velocityError = desiredVelocity - flatVelocity
	local horizontalForce = velocityError * totalMass * VELOCITY_GAIN

	-- VERTICAL HOLD, spring-free: exact gravity compensation makes the raft weightless (hull fluid
	-- forces are disabled in tagRaftPart, so the compensation really is exact). Height is held by a
	-- first-order VELOCITY servo: the vertical velocity is COMMANDED toward waterY each frame.
	--   • a velocity write replicates through the physics channel → motion stays smooth (a per-frame
	--     CFrame write looked like teleporting)
	--   • it erases any contact-injected vertical impulse every frame
	--   • a first-order servo cannot overshoot or resonate by construction — no spring, no bounce
	--[[ ⚠️ ВЫСОТУ ДЕРЖИТ СИЛА, А НЕ ЗАПИСЬ СКОРОСТИ.
	     Зонд показал: пока плот ползёт на посадке, клиент 45 из 60 кадров его не
	     двигает и с каждым пакетом дёргает — и ровно тогда сервер каждый кадр
	     писал AssemblyLinearVelocity (персонаж на палубе, удерживаемый SpawnOnRaft,
	     толкал плот по Y, скорость отличалась от нуля, и запись шла снова). Каждая
	     запись скорости — для клиента как телепорт: интерполяция сбрасывается.
	     На полном ходу записи прекращались, и через ~2 с плот шёл гладко. Игрок,
	     стоящий на дёргающейся палубе, и видел «трясёт вверх-вниз».
	     Поэтому вертикаль — ПД-регулятор силой через тот же VectorForce: пружина
	     к ватерлинии плюс демпфер по скорости, критическое затухание
	     (KD = 2·√KP), резонировать нечему. Скорость плоту не пишем вовсе, кроме
	     страховки на длинный кадр выше. ]]
	local vNow = primaryPart.AssemblyLinearVelocity
	local yDrift = waterY - primaryPart.Position.Y
	local lift = totalMass * (workspace.Gravity + math.clamp(Y_KP * yDrift - Y_KD * vNow.Y, -60, 60))
	vectorForce.Force = Vector3.new(horizontalForce.X, lift, horizontalForce.Z)

	-- Scale torque with raft mass so it always rotates, even with many tiles
	alignOrientation.MaxTorque = totalMass * 500
	-- Compose the target rotation from the initial rotation + a world-Y yaw
	-- change. This avoids the Euler gimbal lock at 90° pitch that made
	-- CFrame.fromEulerAnglesYXZ(π/2, yaw, 0) unstable.
	local yawDelta = lockedYaw - initialYaw
	local targetRotation = CFrame.Angles(0, yawDelta, 0) * initialRotation
	if alignOrientation.CFrame ~= targetRotation then alignOrientation.CFrame = targetRotation end

	-- Update RestCFrame so building systems use the current yaw. Use the
	-- live pos.Y (not a captured init-time value) so the rest frame always
	-- tracks the raft's real vertical position, even if the raft spawned
	-- above or below its settled water-level Y.
	primaryPart:SetAttribute("RestCFrame", CFrame.new(primaryPart.Position) * targetRotation)
	primaryPart:SetAttribute("RestYaw", lockedYaw)

	-- ─── Wind event: apply a horizontal force to players standing on the raft ───
	-- Using a VectorForce (instead of overriding velocity) lets the Humanoid
	-- walk controller still respond to player input — they get pushed but can
	-- walk against the wind.
	if windActive then
		windRemainingTime = math.max(0, windRemainingTime - dt)
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local origin = hrp.Position
					local result = workspace:Raycast(origin, Vector3.new(0, -8, 0), windRayParams)
					if result then
						attachWindForce(plr, hrp)
					end
				end
			end
		end
		updateWindForces(dt)
		if windRemainingTime <= 0 then
			endWindEvent()
		end
	end
end)

-- Clean up if a player leaves mid-wind
Players.PlayerRemoving:Connect(function(plr)
	detachWindForce(plr)
end)
--[[ ⚠️ СТОРОЖ ВЛАДЕНИЯ И ЗОНД КАЧКИ.
     Плот прыгал вверх-вниз (вернулся старый баг T33): стоит физике плота уйти
     к клиенту, его рывки репликации раскачивают вертикальный регулятор. Метки
     на новых деталях (tagRaftPart) ловят не всё — к сборке приварены и NPC вне
     Raft (водолаз, механик, рыбак). Поэтому раз в 0,5 с проверяем владельца
     самой сборки и возвращаем серверу.
     Заодно меряем размах по высоте за 2 с: если плот всё равно скачет — пишем,
     кто владелец, масса, скорость по Y и что твёрдое трётся о днище. ]]
task.spawn(function()
	local lo, hi, t0, lastWarn = math.huge, -math.huge, os.clock(), 0
	while primaryPart.Parent do
		task.wait(0.5)
		local root = primaryPart.AssemblyRootPart or primaryPart
		local owner = nil
		pcall(function() owner = root:GetNetworkOwner() end)
		if owner ~= nil and not root.Anchored then
			pcall(function() root:SetNetworkOwner(nil) end)
			warn(("[Плот] владение сборкой ушло к %s — вернул серверу"):format(owner.Name))
		end
		local y = primaryPart.Position.Y
		lo, hi = math.min(lo, y), math.max(hi, y)
		if os.clock() - t0 >= 2 then
			if hi - lo > 0.4 and os.clock() - lastWarn > 20 then
				lastWarn = os.clock()
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { boat }
				local cf, size = boat:GetBoundingBox()
				local hits = {}
				for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size + Vector3.new(0, 2, 0), params)) do
					if p.CanCollide and #hits < 8 then table.insert(hits, p:GetFullName()) end
				end
				warn(("[Плот] качка по высоте %.2f стада за 2 с | waterY %.2f, сейчас %.2f, vY %.2f | масса %.0f | владелец %s | твёрдое рядом: %s")
					:format(hi - lo, waterY, y, primaryPart.AssemblyLinearVelocity.Y, primaryPart.AssemblyMass,
						owner and owner.Name or "сервер", #hits > 0 and table.concat(hits, ", ") or "ничего"))
			end
			lo, hi, t0 = math.huge, -math.huge, os.clock()
		end
	end
end)
