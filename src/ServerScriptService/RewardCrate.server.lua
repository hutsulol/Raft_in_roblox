-- RewardCrate.server.lua
-- The post-wave reward crate. ONE random ship of each night's wave carries it (WaveDirector marks
-- that ship with the CrateNight attribute). When the player DESTROYS that ship, ShipCombat calls
-- _G.EjectRewardCrate(center, night, burstDir): the crate bursts out of the wreck alongside the
-- coins/pirates — same fling arc, same white comet trail — splashes down, then spins and homes in
-- on the nearest player. The instant it reaches them it pops and opens THAT player's weapon
-- roulette (RewardRoll.client) via the OpenWeaponCrate remote, carrying the night number so the
-- roulette applies the right day rules.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

-- server→client: "the crate reached you — spin your weapon roulette now"
local openEvent = ReplicatedStorage:FindFirstChild("OpenWeaponCrate")
if not openEvent then
	openEvent = Instance.new("RemoteEvent")
	openEvent.Name = "OpenWeaponCrate"
	openEvent.Parent = ReplicatedStorage
end

-- ── tuning ──
-- ejection arc — the SAME numbers the coin burst uses (ShipCombat), so they fly together
local ARC_GRAVITY = 150          -- studs/s^2, hand-integrated like the coins
local ARC_SIDE_MIN, ARC_SIDE_MAX = 30, 55 -- horizontal fling speed
local ARC_UP_MIN, ARC_UP_MAX     = 28, 44 -- upward fling speed
local ARC_MAX_TIME = 4           -- safety: end the arc after this long no matter what
local SETTLE_PAUSE = 0.5         -- seconds bobbing on the water before flying to the player
-- homing flight
local HOME_SPEED  = 55   -- studs/second the crate flies toward the player
local SPIN_SPEED  = 4    -- radians/second it tumbles as it flies
local ARRIVE_DIST = 6    -- studs from the player it counts as "arrived"
local HOVER_Y     = 4    -- floats this high above the player's torso
local TIMEOUT     = 25   -- safety: still open the roulette (and clean up) after this long

-- the living player nearest to `pos` (only players who can actually receive the crate)
local function nearestPlayer(pos)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if not bestD or d < bestD then best, bestD = plr, d end
		end
	end
	return best
end

-- ⚠️ ПРИЗ ЛЕТИТ ОДНОЙ ДЕТАЛЬЮ, А НЕ МОДЕЛЬЮ.
-- Весь полёт ниже написан по детали: CFrame каждый кадр, вложения следа, Destroy.
-- Отдай сюда Model — и сломается всё разом. Поэтому из лаки-блока берём его МЕШ и
-- дальше живём как раньше: подменилась только внешность, поведение то же.
local CRATE_SIZE = 3.4
local LUCKY_NAMES = { "LuckyBlock", "Lucky_Block", "Lucky block" }

-- ⚠️ ИЩЕМ И В ReplicatedStorage, И В Workspace.
-- Правильное место для шаблона — ReplicatedStorage: оттуда его берут все и он не
-- живёт в мире. Но лаки-блок положили на плот, прямо в Workspace, и требовать
-- переноса в обмен на «ничего не работает» — плохой размен. Берём откуда есть,
-- о неправильном месте предупреждаем один раз.
local warnedLucky = false
local function findLuckyMesh()
	local function scan(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") then
				for _, n in ipairs(LUCKY_NAMES) do
					if d.Name == n then return d end
				end
			end
		end
		return nil
	end
	local found = scan(ReplicatedStorage)
	if found then return found end
	found = scan(Workspace)
	if found and not warnedLucky then
		warnedLucky = true
		warn("[RewardCrate] лаки-блок найден в Workspace (" .. found:GetFullName()
			.. ") — перенеси его в ReplicatedStorage, из мира он может пропасть")
	end
	return found
end

-- Приз: лаки-блок, если он есть, иначе прежний деревянный ящик. И тот и другой —
-- тёплый свет плюс искры, чтобы читался как награда, а не как обломок.
local function buildCrate()
	local crate
	local lucky = findLuckyMesh()

	if lucky then
		crate = lucky:Clone()
		-- Габарит приводим к прежнему: от него отсчитаны и вложения следа, и
		-- скорость подлёта. Меш при смене Size масштабируется целиком.
		local biggest = math.max(crate.Size.X, crate.Size.Y, crate.Size.Z)
		if biggest > 0.01 then
			crate.Size = crate.Size * (CRATE_SIZE / biggest)
		end
		-- всё лишнее из шаблона (скрипты, прошлые эффекты) в полёте не нужно
		for _, d in ipairs(crate:GetChildren()) do
			if not d:IsA("SpecialMesh") then d:Destroy() end
		end
	else
		crate = Instance.new("Part")
		crate.Size = Vector3.new(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE)
		crate.Material = Enum.Material.WoodPlanks
		crate.Color = Color3.fromRGB(150, 103, 56)

		local rim = Instance.new("SelectionBox") -- glowing gold edges
		rim.Adornee = crate
		rim.LineThickness = 0.06
		rim.Color3 = Color3.fromRGB(255, 205, 90)
		rim.SurfaceColor3 = Color3.fromRGB(255, 190, 70)
		rim.SurfaceTransparency = 0.85
		rim.Parent = crate
	end

	crate.Name = "WeaponRewardCrate"
	crate.Anchored = true
	crate.CanCollide = false
	crate.CanQuery = false
	crate.CanTouch = false
	crate.CastShadow = false

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 110)
	light.Brightness = 3
	light.Range = 16
	light.Parent = crate

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 224, 150))
	sparkle.Lifetime = NumberRange.new(0.4, 0.8)
	sparkle.Rate = 22
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.6)
	sparkle.Rotation = NumberRange.new(0, 360)
	sparkle.Parent = crate

	return crate, sparkle
end

-- the same white comet trail the burst coins wear (ShipCombat.spawnCoins), spanned for the crate
local function addCometTrail(crate)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1.4, 0); a0.Parent = crate
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1.4, 0); a1.Parent = crate
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),   -- nearly opaque at the crate (start)
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),      -- fully transparent at the tail (end)
	})
	trail.Lifetime = 0.55
	trail.LightEmission = 0                    -- normal blend, so the fade shows (not solid white)
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),    -- wide at the crate
		NumberSequenceKeypoint.new(1, 0),      -- tapers to a point
	})
	trail.Parent = crate
	return trail
end

-- fly the crate to the nearest player; the moment it reaches them, open their roulette
local function homeToPlayer(crate, sparkle, night)
	local target = nearestPlayer(crate.Position)
	local t0 = os.clock()
	local spin = 0
	while crate.Parent do
		local dt = RunService.Heartbeat:Wait()
		spin += dt * SPIN_SPEED

		-- re-acquire if the target left / died mid-flight
		local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			target = nearestPlayer(crate.Position)
			hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		end
		if not hrp then break end -- nobody left to deliver to → clean up below

		local goal = hrp.Position + Vector3.new(0, HOVER_Y, 0)
		local toGoal = goal - crate.Position
		local dist = toGoal.Magnitude
		local step = math.min(HOME_SPEED * dt, dist)
		local newPos = (dist > 0.001) and (crate.Position + toGoal.Unit * step) or crate.Position
		crate.CFrame = CFrame.new(newPos) * CFrame.Angles(spin * 0.6, spin, spin * 0.3)

		if dist <= ARRIVE_DIST or (os.clock() - t0) > TIMEOUT then
			openEvent:FireClient(target, night)  -- ← opens that player's roulette
			if sparkle then sparkle:Emit(28) end -- a little burst as it pops
			break
		end
	end
	task.wait(0.25) -- let the sparkle burst show before it vanishes
	if crate.Parent then crate:Destroy() end
end

-- the crate bursts OUT of the destroyed carrier ship together with its coins/pirates: same fling,
-- same gravity, same comet trail. ShipCombat calls this from destroyShip with the wreck centre and
-- the fatal hit's knockback direction; `night` rides along to the roulette's day rules.
_G.EjectRewardCrate = function(fromPos, night, burstDir)
	if typeof(fromPos) ~= "Vector3" then return end
	print(("[RewardCrate] ящик из %s, ночь %s; кто выдал:\n%s"):format(tostring(fromPos), tostring(night), debug.traceback("", 2)))
	local crate, sparkle = buildCrate()
	addCometTrail(crate) -- stays on for the whole flight (arc + homing), like the coins' trails
	crate.CFrame = CFrame.new(fromPos)
	crate.Parent = Workspace

	task.spawn(function()
		-- sea level: the raft's deck height, same source the coin burst uses
		local raft = Workspace:FindFirstChild("Raft")
		local waterY = (raft and raft.PrimaryPart and raft.PrimaryPart.Position.Y) or (fromPos.Y - 6)

		-- fling outward + up like the coins, leaning the way the fatal hit knocked the ship
		local ang = math.random() * math.pi * 2
		local hdir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		if typeof(burstDir) == "Vector3" then
			local b = Vector3.new(burstDir.X, 0, burstDir.Z)
			if b.Magnitude > 0.1 then hdir = (hdir + b.Unit * 0.5).Unit end
		end
		local vel = hdir * math.random(ARC_SIDE_MIN, ARC_SIDE_MAX)
			+ Vector3.new(0, math.random(ARC_UP_MIN, ARC_UP_MAX), 0)

		-- hand-integrated gravity arc (smooth per frame), ends on splashdown
		local pos = crate.Position
		local spin, t = 0, 0
		while crate.Parent do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			spin += dt * SPIN_SPEED * 2 -- tumbles faster while it's flung
			vel -= Vector3.new(0, ARC_GRAVITY * dt, 0)
			pos += vel * dt
			if (pos.Y <= waterY + 1 and vel.Y < 0) or t > ARC_MAX_TIME then -- splashdown
				pos = Vector3.new(pos.X, math.max(pos.Y, waterY + 1), pos.Z)
				crate.CFrame = CFrame.new(pos) * CFrame.Angles(spin * 0.6, spin, spin * 0.3)
				break
			end
			crate.CFrame = CFrame.new(pos) * CFrame.Angles(spin * 0.6, spin, spin * 0.3)
		end
		if not crate.Parent then return end

		task.wait(SETTLE_PAUSE) -- a beat on the water so the delivery reads
		homeToPlayer(crate, sparkle, night)
	end)
end

print("[RewardCrate] loaded")
