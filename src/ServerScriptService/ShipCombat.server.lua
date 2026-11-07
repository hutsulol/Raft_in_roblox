-- ShipCombat.server.lua
-- Enemy ships (Ship_enemy_*) are destroyed by the player's cannon. The cannon
-- already fires a projectile named "Cannon Shot" carrying a "creator" ObjectValue
-- (the firing player). We detect that ball touching a ship and apply zone damage:
--   • bow / front (the side facing the raft)  -> DIRECT  -> 100% HP (one-shot)
--   • sides (борт)                            -> SIDE    -> 50% HP (two-shot)
-- On death: explosion FX + sink/fade, then N coins burst out, fly to the firer,
-- and credit the "Pirate" currency on contact.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local CollectionService= game:GetService("CollectionService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Debris           = game:GetService("Debris")
local TweenService     = game:GetService("TweenService")
local CombatSounds     = require(ReplicatedStorage:WaitForChild("CombatSounds"))
local EnemyHealthBar   = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))
local WaterSpawn       = require(ReplicatedStorage:WaitForChild("WaterSpawn"))
local AssetFind        = require(ReplicatedStorage:WaitForChild("AssetFind"))

-- ── tunables ──
local SHIP_NAME_PREFIX = "Ship_enemy" -- models whose name starts with this are enemy ships
local SHIP_TAG         = "EnemyShip"  -- ...or tag a model with this
local BALL_NAMES       = { ["Cannon Shot"] = true, ["Bullet_Cannon"] = true } -- cannon projectiles
local SHIP_HP          = 100
local DIRECT_DAMAGE    = 100          -- bow hit = one-shot
local SIDE_DAMAGE      = 50           -- side hit = two-shot
local HUMANOID_DAMAGE  = 100          -- cannon hit vs a humanoid (drowning pirate / NPC); 100 = one-shot
local COINS_PER_SHIP   = 10
local COIN_VALUE       = 1            -- Pirate per coin
local COIN_ICON        = "rbxassetid://93617165412571"
local COIN_ICON_PX     = 28           -- coin icon size (px) when close to the player
local COIN_MIN_PX      = 9            -- coin icon size (px) when far away — it grows as it nears you
local COIN_AIRTIME_MAX = 3.0          -- safety cap on the physics burst (incl. bounces) before settling
local COIN_SETTLE_TIME = 1.6          -- base seconds bobbing on the water before flying to you
local COIN_MAGNET_POP  = 26           -- initial pop speed when a coin lifts off the water
local COIN_GRAVITY         = 150      -- studs/s^2 for the hand-integrated arc (smooth, per frame)
local COIN_BOUNCES         = 3        -- times a coin bounces off the water before settling
local COIN_BOUNCE_DAMP     = 0.55     -- vertical speed kept per bounce (each bounce is lower)
local COIN_BOUNCE_FRICTION = 0.7      -- horizontal speed kept per bounce (it slows as it skips)
local COLLECT_DIST     = 3.5          -- studs from player to collect
local MAGNET_ACCEL     = 120          -- studs/s^2 the coin speeds up as it homes
local MAGNET_MAX_SPEED = 150
local MAGNET_TURN      = 4            -- how fast it steers onto you (lower = wider curve; it always converges)

-- Drowning pirates: a sunk ship may leave survivors that drift until killed.
local DROWNING_CHANCE   = 0.30        -- chance a sunk ship spawns them
local DROWNING_COUNT    = 2           -- how many
local DROWNING_COINS    = 5           -- coins each drops when killed
local DROWNING_TEMPLATE = "drowning_Pirate"
local DROWNING_Y_OFFSET = 1           -- lift above the water surface so the ring sits right

-- Enemy ships also shell the player's raft.
local SHIP_FIRE_INTERVAL = 5          -- seconds between a ship's shots at the raft
local SHIP_FIRE_RANGE    = 280        -- only shell the raft within this range
local SHIP_BASE_DAMAGE   = 30         -- level-1 ship damage to the raft (HP); ×ShipLevel
local SHIP_SHELL_SPEED   = 150        -- launch speed of a ship's shell (arcs via gravity)
-- attack waves: ships spawn off a random side, chase the raft, hold at bombard range
local SHIP_CHASE_SPEED    = 10        -- studs/s the ship moves (keep ABOVE the raft's ~8 so it can hold its distance)
local SHIP_TURN_RATE      = 1.8       -- rad/s the ship swings to face the raft
local SHIP_STANDOFF_GAP   = 85        -- gap (studs) kept between the ship's HULL and the raft's EDGE
local SHIP_SPAWN_DIST     = 200       -- ships appear this far from the raft
local SHIP_SPAWN_INTERVAL = 30        -- seconds between spawn attempts
local SHIP_MAX_ACTIVE     = 1         -- max simultaneous attackers (counts pre-placed too)
local SHELL_ARC          = 0.5        -- upward component of the lob (higher = steeper arc)

-- Magma ship: an enemy-ship variant (model named "Magma_Ship") that lobs a
-- "Magma_ball". Same HP / impact damage as a basic ship, but where the ball lands
-- it leaves a burning patch that keeps draining the raft's HP for a few seconds.
local MAGMA_SHIP_PREFIX   = "Magma_Ship"
local MAGMA_BALL_TEMPLATE = "Magma_ball" -- model in ReplicatedStorage (or workspace) cloned as the shell
local MAGMA_FIRE_DURATION = 5            -- seconds a burning patch lasts
local MAGMA_FIRE_RADIUS   = 4            -- радиус лужи в студах (было 7 — пол-палубы)
local MAGMA_BURN_DPS      = 3            -- raft HP drained per second while a patch burns on the raft
local MAGMA_WATER_DURATION= 0.7          -- a magma patch on water is weak + gone within ~1s (no damage)
local MAGMA_CANNON_BURN_TIME = 5         -- seconds a target hit by the player's magma cannon keeps burning
local MAGMA_CANNON_SHIP_DPS  = 12        -- ship HP drained per second while it burns
local MAGMA_CANNON_HUM_DPS   = 15        -- enemy humanoid HP per second while it burns

-- Ледяной корабль: вариант врага (модель "ice_ship"). Из парта "Front" (пасть) выдыхает
-- холодный воздух → снаряд-сгусток холода летит к плоту → на воде/палубе рождается МОРОЗНАЯ
-- ВОЛНА (расширяющееся кольцо льда), которая замедляет игроков в радиусе; попадание по плоту —
-- урон как у базового корабля. Пока плывёт — оставляет за собой ледяной след.
local FROST_SHIP_PREFIX  = "ice_ship"
local FROST_MUZZLE_NAME  = "Front"      -- парт-точка выдоха во рту (размещён игроком)
local FROST_SLOW_MULT    = 0.5          -- WalkSpeed игрока ×0.5 при попадании брызг
local FROST_SLOW_DUR     = 2.5          -- сколько держится заморозка, сек
local FROST_BREATH_AHEAD = 12           -- точка воды перед головой, где туман касается воды (там рождаются сосульки)
-- корабль держит дистанцию SHIP_STANDOFF_GAP (85) до плота, поэтому сосульки должны долетать
-- дальше этого, иначе разбиваются в воде, не дойдя до плота (урон бы не срабатывал).
local FROST_WAVE_TRAVEL  = 100          -- макс. дальность полёта сосульки ВПЕРЁД (перекрывает дистанцию)
local FROST_COLOR        = Color3.fromRGB(150, 220, 255)
local FROST_ICE_MODEL    = "Ice_bullet" -- 3D-модель сосульки в ReplicatedStorage (снаряд атаки)
-- дыхание: голова крутится вправо-влево по кривой (чуть вверх-вниз), пока идёт выдох
local FROST_BREATH_TIME  = 2.2          -- длительность выдоха, сек (продлён)
local FROST_SWEEP_YAW    = math.rad(35) -- размах поворота головы влево/вправо
local FROST_SWEEP_PITCH  = math.rad(9)  -- лёгкий наклон вверх/вниз (кривая)
local FROST_SWEEP_CYCLES = 2            -- сколько раз проходит влево-вправо за выдох
-- сосульки: рождаются из-под воды по мере касания тумана, СКОЛЬЗЯТ вперёд у поверхности
-- (часть над водой, часть под — не взлетают в воздух), и разбиваются в плоту / в воде.
local FROST_ICICLE_INTERVAL = 0.5       -- как часто рождается новая сосулька, сек (реже → их мало)
local FROST_ICICLE_MAX      = 3         -- не больше стольких за один выдох (пара штук)
local FROST_SPRAY_SPEED  = 48           -- скорость сосульки вперёд, студы/с
-- поворот МОДЕЛИ относительно направления полёта (кончик — по ходу). Значения = Orientation
-- модели из Studio. Если летит не так — поправь эти три угла (градусы).
local FROST_ICICLE_FACE  = CFrame.fromOrientation(math.rad(-20.459), math.rad(2.595), math.rad(-97.389))
local FROST_ICICLE_YAW_FIX = math.rad(75) -- доп. доворот носа влево (если ушло не туда — поставь -75)
-- ↑ РУЧНАЯ поза — теперь только ЗАПАСНОЙ вариант: если в модели Ice_bullet есть
-- парт-маркер в носу ("Front"/"Part"), перёд определяется по нему автоматически.
-- ── виляние сосульки при подлёте к плоту (змейка вместо прямой) ──
local FROST_WEAVE_DIST = 50 -- за столько студов до края плота начинает вилять
local FROST_WEAVE_AMP  = 5  -- амплитуда змейки, студы (в стороны от прямой)
local FROST_WEAVE_LEN  = 22 -- длина полного «зигзага», студы

-- ── coin pickup feedback (client shows "+N") ──
local coinPopupEvent = ReplicatedStorage:FindFirstChild("PirateCoinCollected")
if not coinPopupEvent then
	coinPopupEvent = Instance.new("RemoteEvent")
	coinPopupEvent.Name = "PirateCoinCollected"
	coinPopupEvent.Parent = ReplicatedStorage
end

-- ── ship helpers ──
local function isMagmaShip(m)
	return m:IsA("Model") and m.Name:sub(1, #MAGMA_SHIP_PREFIX) == MAGMA_SHIP_PREFIX
end

local function isFrostShip(m)
	return m:IsA("Model") and m.Name:sub(1, #FROST_SHIP_PREFIX) == FROST_SHIP_PREFIX
end

local function isEnemyShip(m)
	if not m:IsA("Model") then return false end
	return CollectionService:HasTag(m, SHIP_TAG)
		or m.Name:sub(1, #SHIP_NAME_PREFIX) == SHIP_NAME_PREFIX
		or isMagmaShip(m)
		or isFrostShip(m)
end

local function shipOf(part)
	local m = part
	while m and m ~= workspace do
		if isEnemyShip(m) then return m end
		m = m.Parent
	end
	return nil
end

local function setupShip(ship)
	if ship:GetAttribute("HP") == nil then
		-- WaveDirector may have stamped an HP multiplier before parenting (tougher on later nights)
		local mult = ship:GetAttribute("HPScale") or 1
		ship:SetAttribute("MaxHP", SHIP_HP * mult)
		ship:SetAttribute("HP", SHIP_HP * mult)
	end
	-- Anchor the hull: terrain-water buoyancy can't reliably float a heavy multi-part
	-- ship, so we drive it kinematically instead — chaseLoop moves it toward the raft
	-- via PivotTo and destroyShip sinks it the same way (anchored parts ride PivotTo).
	if not ship:GetAttribute("_Floated") then
		ship:SetAttribute("_Floated", true)
		for _, d in ipairs(ship:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
	end
end

-- The cannonball carries no "creator", so attribute loot to the player nearest
-- the ball's spawn (the cannon sits next to whoever fired it).
local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < bestD then best, bestD = plr, d end
		end
	end
	return best
end

-- Direct (bow) vs side, from the hit point in the ship's local space. The longer
-- horizontal dimension is the length (bow↔stern); a hit dominated by that axis is
-- a "direct" bow hit, otherwise it landed on a side (борт).
local function hitZone(ship, hitPos)
	local cf, size = ship:GetBoundingBox()
	local lp = cf:PointToObjectSpace(hitPos)
	local forwardIsZ = size.Z >= size.X
	local fwdHalf  = math.max((forwardIsZ and size.Z or size.X) / 2, 0.1)
	local sideHalf = math.max((forwardIsZ and size.X or size.Z) / 2, 0.1)
	local fwdN  = math.abs(forwardIsZ and lp.Z or lp.X) / fwdHalf
	local sideN = math.abs(forwardIsZ and lp.X or lp.Z) / sideHalf
	return (fwdN >= sideN) and "direct" or "side"
end

-- ── coin magnet loop ──
local activeCoins = {} -- { part, firer, state, t, from, to, speed }

-- burstDir (optional, horizontal): the way the ship was knocked — coins lean that
-- way as they scatter, like loot flying off a killed character in popular games.
-- opts (optional): { pop = velocity multiplier (1 = ship default), size = icon scale (1 = default),
--   follow = BasePart } — chest/crate drops use gentler, smaller coins without touching the mob-kill
-- feel. `follow` carries the whole burst along with a MOVING platform (the sailing raft): the
-- follow-part's frame-to-frame drift is added to each coin, so coins scatter/bounce AROUND the crate
-- instead of being left behind in the water.
local function spawnCoins(origin, firer, n, burstDir, opts)
	local popMult = (opts and opts.pop) or 1
	local sizeMult = (opts and opts.size) or 1
	local follow = opts and opts.follow
	local raft = workspace:FindFirstChild("Raft")
	local waterY = (raft and raft.PrimaryPart and raft.PrimaryPart.Position.Y) or (origin.Y - 12)
	local bias
	if typeof(burstDir) == "Vector3" then
		local b = Vector3.new(burstDir.X, 0, burstDir.Z)
		if b.Magnitude > 0.1 then bias = b.Unit end
	end
	for _ = 1, n do
		local coin = Instance.new("Part")
		coin.Name = "PirateCoin"
		coin.Shape = Enum.PartType.Ball
		coin.Size = Vector3.new(0.7, 0.7, 0.7)
		coin.Anchored = true   -- we hand-integrate the arc (smooth per frame) + bounce it
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CastShadow = false
		coin.Transparency = 1  -- the billboard icon below is the visual
		coin.CFrame = CFrame.new(origin + Vector3.new(math.random(-12, 12) / 10, math.random(0, 18) / 10, math.random(-12, 12) / 10))
		coin.Parent = workspace

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(COIN_ICON_PX, COIN_ICON_PX)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Parent = coin
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = COIN_ICON
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = bb

		-- white comet trail — on the whole time the coin moves (fall / bounce / fly-in)
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.45, 0); a0.Parent = coin
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.45, 0); a1.Parent = coin
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),   -- nearly opaque at the coin (start)
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(1, 1),      -- fully transparent at the tail (end)
		})
		trail.Lifetime = 0.55
		trail.LightEmission = 0                    -- normal blend, so the fade shows (not solid white)
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.3),    -- wide at the coin
			NumberSequenceKeypoint.new(1, 0),      -- tapers to a point
		})
		trail.Enabled = true
		trail.Parent = coin

		-- burst: fling OUTWARD to the sides (strong horizontal) with a moderate arc up,
		-- spread in all directions, leaning slightly toward the knockback
		local ang = math.random() * math.pi * 2
		local hdir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		if bias then hdir = (hdir + bias * 0.5).Unit end
		local vel = (hdir * math.random(30, 55) + Vector3.new(0, math.random(28, 44), 0)) * popMult
		table.insert(activeCoins, {
			part = coin, firer = firer, state = "physics", t = 0, vel = vel, waterY = waterY,
			trail = trail, bb = bb, settle = COIN_SETTLE_TIME + math.random() * 0.9,
			sizeMult = sizeMult,
			follow = follow, lastFollowPos = follow and follow.Position or nil,
		})
	end
end

RunService.Heartbeat:Connect(function(dt)
	for i = #activeCoins, 1, -1 do
		local c = activeCoins[i]
		local part = c.part
		if not part or not part.Parent then
			table.remove(activeCoins, i)
			continue
		end
		c.t += dt

		-- perspective size: small far away, grows toward normal as it nears the player
		local char = c.firer and c.firer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and c.bb then
			local f = math.clamp(((hrp.Position - part.Position).Magnitude - 6) / 74, 0, 1)
			local px = math.floor((COIN_ICON_PX + (COIN_MIN_PX - COIN_ICON_PX) * f) * (c.sizeMult or 1) + 0.5)
			c.bb.Size = UDim2.fromOffset(px, px)
		end

		-- ride the moving platform (crate coins on the sailing raft): add its per-frame drift while
		-- the coin arcs/bounces/drifts; once it's magnetized to the player this no longer matters
		if c.follow and c.follow.Parent and c.state ~= "magnet" then
			local fp = c.follow.Position
			if c.lastFollowPos then
				part.Position = part.Position + (fp - c.lastFollowPos)
			end
			c.lastFollowPos = fp
		end

		if c.state == "physics" then
			-- hand-integrated gravity arc — moved every frame, so it falls smoothly —
			-- that bounces off the water a few times (each lower), then settles to drift
			c.vel = c.vel - Vector3.new(0, COIN_GRAVITY * dt, 0)
			local np = part.Position + c.vel * dt
			if np.Y <= c.waterY then
				np = Vector3.new(np.X, c.waterY, np.Z)
				if c.vel.Y < -3 and (c.bounces or 0) < COIN_BOUNCES then
					c.bounces = (c.bounces or 0) + 1
					c.vel = Vector3.new(c.vel.X * COIN_BOUNCE_FRICTION, -c.vel.Y * COIN_BOUNCE_DAMP, c.vel.Z * COIN_BOUNCE_FRICTION)
					part.Position = np
				else
					part.Position = np
					c.state = "drift"
					c.driftT = 0
				end
			else
				part.Position = np
				if c.t >= COIN_AIRTIME_MAX then
					part.Position = Vector3.new(np.X, c.waterY, np.Z)
					c.state = "drift"
					c.driftT = 0
				end
			end
		elseif c.state == "drift" then
			-- bob on the surface for a while, then lift off and fly to you
			c.driftT += dt
			part.Position = Vector3.new(part.Position.X, c.waterY + math.sin((c.t + i) * 2.5) * 0.2, part.Position.Z)
			if c.driftT >= c.settle then
				c.state = "magnet"
				c.mvel = Vector3.new(math.random(-10, 10) / 10, 1.4, math.random(-10, 10) / 10).Unit * COIN_MAGNET_POP
				c.speed = COIN_MAGNET_POP
				c.magT = 0
			end
		else -- magnet: curve onto the firer and converge (never orbit), collect on contact
			if not hrp then
				part:Destroy()
				table.remove(activeCoins, i)
				continue
			end
			c.magT += dt
			local toP = hrp.Position - part.Position
			local dist = toP.Magnitude
			if dist <= COLLECT_DIST or c.magT > 4 then
				if _G.AddPirate then _G.AddPirate(c.firer, COIN_VALUE) end
				coinPopupEvent:FireClient(c.firer, COIN_VALUE)
				part:Destroy()
				table.remove(activeCoins, i)
			else
				c.speed = math.min(c.speed + MAGNET_ACCEL * dt, MAGNET_MAX_SPEED)
				-- rotate the velocity TOWARD you (Lerp bleeds off sideways momentum, so it
				-- curves in and converges instead of circling forever)
				c.mvel = c.mvel:Lerp(toP.Unit * c.speed, math.clamp(MAGNET_TURN * dt, 0, 1))
				part.Position = part.Position + c.mvel * dt
			end
		end
	end
end)

-- ── drowning pirates (optional survivors of a sunk ship) ──
local function drowningTemplate()
	return AssetFind.find(DROWNING_TEMPLATE) or workspace:FindFirstChild(DROWNING_TEMPLATE)
end

-- find the R6 sub-rig (the model holding Head/Torso) inside the pirate
local function findRig(pirate)
	if pirate:FindFirstChild("Torso") or pirate:FindFirstChild("Head") then return pirate end
	for _, d in ipairs(pirate:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChild("Torso") or d:FindFirstChild("Head")) then return d end
	end
	return pirate
end

-- It's a legless decorative model with no Humanoid, so weapons can't damage it.
-- Add a Humanoid (+ HumanoidRootPart) so it has HP and the game's weapons (which
-- damage Humanoids — that's how the other enemies die) can kill it.
local function ensureHumanoid(pirate)
	local existing = pirate:FindFirstChildWhichIsA("Humanoid", true)
	if existing then return existing end
	local rig = findRig(pirate)
	local torso = rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso") or rig:FindFirstChildWhichIsA("BasePart")
	if not torso then return nil end
	if not rig:FindFirstChild("HumanoidRootPart") then
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3.new(2, 2, 1)
		hrp.Transparency = 1
		hrp.CanCollide = false
		hrp.CFrame = torso.CFrame
		hrp.Parent = rig
	end
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.BreakJointsOnDeath = false
	hum.Parent = rig
	return hum
end

-- terrain-water surface Y at (x,z), so the pirate spawns ON the water (not above it)
local function waterSurfaceAt(x, z, fallbackY, ignore)
	local rp = RaycastParams.new()
	rp.IgnoreWater = false
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, fallbackY + 80, z), Vector3.new(0, -400, 0), rp)
	if res and res.Material == Enum.Material.Water then
		return res.Position.Y
	end
	return fallbackY
end

local function setupDrowningPirate(pirate)
	local hum = ensureHumanoid(pirate)

	-- HP-бар, как у остальных врагов в океане: Humanoid и 100 HP тут уже есть,
	-- урон по ним проходит обычной веткой, а полосы над головой не было вовсе —
	-- висел только штатный индикатор Roblox.
	local head = pirate:FindFirstChild("Head", true) or pirate:FindFirstChild("HumanoidRootPart", true)
	if hum and head and not pirate:FindFirstChild("PirateHP", true) then
		hum.DisplayDistanceType   = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType     = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.NameDisplayDistance   = 0
		hum.HealthDisplayDistance = 0
		local hb = EnemyHealthBar.new({
			name = "ТОНУЩИЙ ПИРАТ",
			maxHp = math.max(hum.MaxHealth, 1),
			cur = hum.Health,
			difficulty = 1,
			surface = true,
		})
		hb.attach(head, 2.4, "PirateHP")
		hum.HealthChanged:Connect(function() hb.setHP(hum.Health, hum.MaxHealth) end)
		hum.Died:Connect(function() task.delay(0.6, function() hb.destroy() end) end)
	end
	for _, d in ipairs(pirate:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	if hum then
		hum.PlatformStand = true       -- don't try to walk/stand while drifting
		hum.BreakJointsOnDeath = false -- we break it ourselves on death
	end

	local baseCF = pirate:GetPivot()
	local basePos, baseRot = baseCF.Position, baseCF.Rotation
	local driftDir = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	local dead = false

	-- gentle bob + slow drift on the surface while alive
	task.spawn(function()
		local t = 0
		while not dead and pirate.Parent do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			local pos = basePos + driftDir * (t * 0.5) + Vector3.new(0, math.sin(t * 1.4) * 0.35, 0)
			pcall(function() pirate:PivotTo(CFrame.new(pos) * baseRot * CFrame.Angles(0, math.sin(t * 0.4) * 0.12, 0)) end)
		end
	end)

	-- killed by a weapon (normal Humanoid HP) → coins, then come apart + sink
	if hum then
		hum.Died:Connect(function()
			if dead then return end
			dead = true
			local creator = hum.Parent and hum.Parent:FindFirstChild("creator")
			local killer = (creator and creator.Value) or nearestPlayer(pirate:GetPivot().Position)
			spawnCoins(pirate:GetPivot().Position, killer, DROWNING_COINS)

			-- break the rig so the pieces (incl. the life-ring mesh) separate
			for _, d in ipairs(pirate:GetDescendants()) do
				if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Snap") then
					d:Destroy()
				end
			end
			local parts, startY = {}, {}
			for _, d in ipairs(pirate:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CFrame = d.CFrame * CFrame.Angles(
						math.rad(math.random(-40, 40)),
						math.rad(math.random(-40, 40)),
						math.rad(math.random(-40, 40)))
					parts[#parts + 1] = d
					startY[d] = d.Position.Y
				end
			end
			task.spawn(function()
				local DURATION, sink, t = 2.2, 7, 0
				while t < DURATION and pirate.Parent do
					local dt = RunService.Heartbeat:Wait()
					t += dt
					local a = math.min(t / DURATION, 1)
					for _, p in ipairs(parts) do
						if p.Parent then
							p.Position = Vector3.new(p.Position.X, startY[p] - sink * a * a, p.Position.Z)
							p.Transparency = math.clamp(a, p.Transparency, 1)
						end
					end
				end
				if pirate.Parent then pirate:Destroy() end
			end)
		end)
	end
end

local function spawnDrowningPirates(center, ship)
	if math.random() > DROWNING_CHANCE then return end
	local template = drowningTemplate()
	if not template then
		warn("[ShipCombat] drowning_Pirate template not found — put the model in ReplicatedStorage")
		return
	end
	for _ = 1, DROWNING_COUNT do
		local ang = math.random() * math.pi * 2
		local x = center.X + math.cos(ang) * 6
		local z = center.Z + math.sin(ang) * 6
		local wy = waterSurfaceAt(x, z, center.Y - 6, { ship }) + DROWNING_Y_OFFSET
		local p = template:Clone()
		p.Parent = workspace
		pcall(function() p:PivotTo(CFrame.new(x, wy, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0)) end)
		setupDrowningPirate(p)
	end
end

-- ── destruction ──
local function destroyShip(ship, firer, hitPos)
	if ship:GetAttribute("Dead") then return end
	ship:SetAttribute("Dead", true)

	for _, d in ipairs(ship:GetDescendants()) do -- drop the HP bar
		if d.Name == "ShipHealthBar" then d:Destroy() end
	end

	local cf, size = ship:GetBoundingBox()
	local center = cf.Position

	CombatSounds.play("downed", center) -- ship destroyed; the sink sound follows shortly after
	task.delay(0.35, function() CombatSounds.play("sink", center) end)

	-- Anchor every part so the sink is controlled (leftover physics / water
	-- buoyancy can't float or tip the wreck) and collect them for fading. No need
	-- to unanchor the ship yourself — the sink below is kinematic.
	local parts = {}
	for _, d in ipairs(ship:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			table.insert(parts, d)
		end
	end

	-- visual explosion (no blast pressure → never flings the raft/player)
	local exp = Instance.new("Explosion")
	exp.Position = center
	exp.BlastRadius = math.max(size.X, size.Z) * 0.6
	exp.BlastPressure = 0
	exp.Parent = workspace

	-- coins burst from the fatal-hit point, leaning the way the hit knocked the ship
	local burstDir = hitPos and Vector3.new(center.X - hitPos.X, 0, center.Z - hitPos.Z) or nil
	spawnCoins(hitPos or center, firer, COINS_PER_SHIP, burstDir)
	spawnDrowningPirates(center, ship)
	-- this ship carried the wave's reward crate (WaveDirector marks one per night) — it bursts
	-- out of the wreck together with the coins/pirates and then flies to the player
	local crateNight = ship:GetAttribute("CrateNight")
	if crateNight and _G.EjectRewardCrate then
		_G.EjectRewardCrate(center, crateNight, burstDir)
	end

	-- sink: tip over and slide under the surface (accelerating), fading out.
	task.spawn(function()
		local DURATION = 2.2
		local sink = size.Y + 8
		local startCF = ship:GetPivot()
		local roll = math.rad(25) * ((math.random() < 0.5) and 1 or -1)
		local t = 0
		while t < DURATION and ship.Parent do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			local a = math.min(t / DURATION, 1)
			-- sink straight DOWN in world space (not the ship's local Y — the Magma ship
			-- is oriented so its local Y points sideways, which slid it left), + roll tilt
			local cf2 = CFrame.new(startCF.Position + Vector3.new(0, -sink * a * a, 0)) * startCF.Rotation * CFrame.Angles(0, 0, roll * a)
			pcall(function() ship:PivotTo(cf2) end)
			for _, p in ipairs(parts) do
				if p.Parent then p.Transparency = math.clamp(a, p.Transparency, 1) end
			end
		end
		if ship.Parent then ship:Destroy() end
	end)
end

-- ── apply a cannon hit ──
local function applyHit(ship, hitPos, firer, dmgMult)
	if not ship or ship:GetAttribute("Dead") then return end
	local zone = hitZone(ship, hitPos)
	local dmg = ((zone == "direct") and DIRECT_DAMAGE or SIDE_DAMAGE) * (dmgMult or 1)
	local hp = (ship:GetAttribute("HP") or SHIP_HP) - dmg
	ship:SetAttribute("HP", hp)
	if hp > 0 then
		CombatSounds.play("hit", hitPos) -- impact on a surviving ship (fatal hits play "downed" instead)
	else
		destroyShip(ship, firer, hitPos)
	end
end

-- find the enemy character a hit part belongs to: climb to the top-level model
-- under workspace, then locate its Humanoid (the rig may be a sub-model).
-- Ищем ТЕСНЕЙШУЮ модель-предка с Humanoid, а НЕ модель верхнего уровня. Раньше код шёл
-- вверх до прямого ребёнка Workspace: для врагов, ВЛОЖЕННЫХ в контейнер (Island_2.Enemies.
-- Pirate_lvl1), это возвращало Island_2 и его ПЕРВЫЙ попавшийся Humanoid — урон уходил не в
-- того пирата (по факту «не действовал»). Теперь останавливаемся на первом предке-Model,
-- в поддереве которого есть Humanoid, — это и есть сам персонаж.
local function humanoidOf(part)
	local inst = part
	while inst and inst ~= workspace do
		if inst:IsA("Model") then
			--[[ ⚠️ НЕ РЕКУРСИВНО. Поиск вглубь находил Humanoid у чужой модели:
			     деталь земли острова → предок «остров» → внутри него, в папке
			     Animals, корова. Замах у любой детали острова бил корову за
			     полкарты («корова умирает, когда машу топором в другом месте»).
			     Humanoid ищем только среди прямых детей каждой модели-предка;
			     вложенные риги всё равно найдутся — мы поднимаемся по цепочке. ]]
			local hum = inst:FindFirstChildWhichIsA("Humanoid")
			if hum then return hum, inst end
		end
		inst = inst.Parent
	end
	return nil
end

-- ── magma-cannon burn: the SPOT the shell hits catches fire (a fire part dropped at the
-- contact point, riding/sinking with the ship) and the target burns down over time —
-- distinct from the raft's magma patch. attachBurnVfx fires up a single part (used for
-- enemy humanoids); returns the instances it made so the caller can clear them.
local function attachBurnVfx(part, scale)
	if part:FindFirstChild("MagmaBurnFire") then return {} end
	local made = {}
	local fire = Instance.new("Fire")
	fire.Name = "MagmaBurnFire"
	fire.Size = math.clamp(part.Size.Magnitude * 0.35, 2, 9) * scale
	fire.Heat = 14
	fire.Color = Color3.fromRGB(255, 110, 25)
	fire.SecondaryColor = Color3.fromRGB(170, 30, 10)
	fire.Parent = part
	table.insert(made, fire)

	local flames = Instance.new("ParticleEmitter")
	flames.Name = "MagmaBurnParticles"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 160, 40), Color3.fromRGB(180, 25, 10))
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.4 * scale),
		NumberSequenceKeypoint.new(1, 0.3 * scale),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Lifetime = NumberRange.new(0.5, 0.95)
	flames.Rate = 22
	flames.Speed = NumberRange.new(2, 6)
	flames.SpreadAngle = Vector2.new(40, 40)
	flames.Acceleration = Vector3.new(0, 11, 0)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Parent = part
	table.insert(made, flames)
	return made
end

-- a fire part dropped right at the impact point on a ship. Parented to the ship + anchored
-- (enemy ships are anchored), so it sinks with the wreck on death and is cleaned up with it.
local function spawnContactFire(position, ship)
	local part = Instance.new("Part")
	part.Name = "MagmaImpactFire"
	part.Size = Vector3.new(2.5, 2.5, 2.5)
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Massless = true
	part.Parent = ship

	local fire = Instance.new("Fire")
	fire.Size = 8
	fire.Heat = 16
	fire.Color = Color3.fromRGB(255, 110, 25)
	fire.SecondaryColor = Color3.fromRGB(170, 30, 10)
	fire.Parent = part

	local flames = Instance.new("ParticleEmitter")
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 160, 40), Color3.fromRGB(180, 25, 10))
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Lifetime = NumberRange.new(0.5, 1.0)
	flames.Rate = 38
	flames.Speed = NumberRange.new(2, 7)
	flames.SpreadAngle = Vector2.new(45, 45)
	flames.Acceleration = Vector3.new(0, 12, 0)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Parent = part

	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(35, 30, 28)
	smoke.Size = 5
	smoke.RiseVelocity = 9
	smoke.Opacity = 0.4
	smoke.Parent = part
	return part
end

local function igniteShip(ship, hitPart, hitPos, firer, burnMult)
	hitPos = hitPos or (hitPart and hitPart:IsA("BasePart") and hitPart.Position) or ship:GetPivot().Position
	local firePart = spawnContactFire(hitPos, ship) -- fire exactly where the shell hit

	if ship:GetAttribute("Dead") then return end -- already going down: just the impact flame
	if ship:GetAttribute("_Burning") then
		-- already burning from an earlier hit — let this impact flame flicker, then clear it
		task.delay(MAGMA_CANNON_BURN_TIME, function() if firePart and firePart.Parent then firePart:Destroy() end end)
		return
	end
	ship:SetAttribute("_Burning", true)

	task.spawn(function()
		local t = 0
		while t < MAGMA_CANNON_BURN_TIME and ship.Parent and not ship:GetAttribute("Dead") do
			task.wait(1)
			t += 1
			local hp = (ship:GetAttribute("HP") or SHIP_HP) - MAGMA_CANNON_SHIP_DPS * (burnMult or 1)
			ship:SetAttribute("HP", hp)
			if hp <= 0 then
				destroyShip(ship, firer, hitPos)
				break
			end
		end
		-- if it died, leave the flame so the wreck sinks burning (destroyed with the ship)
		if not ship:GetAttribute("Dead") then
			if firePart and firePart.Parent then firePart:Destroy() end
			if ship.Parent then ship:SetAttribute("_Burning", false) end
		end
	end)
end

local function igniteHumanoid(hum, model, burnMult)
	if not model then return end
	local torso = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
		or model:FindFirstChild("UpperTorso") or model:FindFirstChildWhichIsA("BasePart", true)
	if not torso or torso:FindFirstChild("MagmaBurnFire") then return end
	local vfx = attachBurnVfx(torso, 0.6)
	task.spawn(function()
		local t = 0
		while t < MAGMA_CANNON_BURN_TIME and hum.Parent and hum.Health > 0 do
			task.wait(1)
			t += 1
			hum:TakeDamage(MAGMA_CANNON_HUM_DPS * (burnMult or 1))
		end
		for _, inst in ipairs(vfx) do if inst.Parent then inst:Destroy() end end
	end)
end

-- ── watch cannonballs ──
local function watchBall(ball)
	if not ball:IsA("BasePart") then return end
	if not BALL_NAMES[ball.Name] and not ball:FindFirstChild("creator") then return end
	local creatorVal = ball:FindFirstChild("creator")
	local firer = (creatorVal and creatorVal.Value) or nearestPlayer(ball.Position)
	local isMagma = ball:GetAttribute("Magma") == true -- fired by a magma cannon → ignites targets
	local dmgMult = ball:GetAttribute("DmgMult") or 1  -- Big_Magma_Cannon = 2×, etc.
	local burnMult = ball:GetAttribute("BurnMult") or 1
	local splash = ball:GetAttribute("SplashRadius") or 0 -- Big_Magma_Cannon: area blast on impact / water
	local used = false

	-- area blast: hurt every enemy humanoid in range (esp. pirates floating in the sea),
	-- never the player or units parented to the raft, + a visible explosion.
	local function detonateSplash(pos)
		if splash <= 0 then return end
		local raft = workspace:FindFirstChild("Raft")
		local done = {}
		for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, splash)) do
			local hum, model = humanoidOf(part)
			if hum and model and not done[model] and hum.Health > 0
				and not Players:GetPlayerFromCharacter(model)
				and not (raft and model:IsDescendantOf(raft)) then
				done[model] = true
				hum:TakeDamage(HUMANOID_DAMAGE * dmgMult)
				if isMagma then igniteHumanoid(hum, model, burnMult) end
			end
		end
		local exp = Instance.new("Explosion")
		exp.Position = pos
		exp.BlastPressure = 0
		exp.BlastRadius = splash
		exp.Parent = workspace
	end

	ball.Touched:Connect(function(hit)
		if used then return end
		if ball:GetAttribute("Resolved") then return end
		-- Small raiders use swept projectile impacts and per-part hull damage.
		-- Let RaiderCombat resolve their crew and hull exactly once.
		local ancestor = hit
		while ancestor and ancestor ~= workspace do
			if ancestor:GetAttribute("BoatType") == "RaiderL0" then return end
			ancestor = ancestor.Parent
		end
		-- enemy ship → zone damage (+ burn if magma)
		local ship = shipOf(hit)
		if ship then
			used = true
			applyHit(ship, ball.Position, firer, dmgMult)
			if isMagma then igniteShip(ship, hit, ball.Position, firer, burnMult) end
			detonateSplash(ball.Position)
			return
		end
		-- enemy humanoid (drowning pirate / NPC) → damage on contact, never players
		local hum, model = humanoidOf(hit)
		if hum and hum.Health > 0 and not Players:GetPlayerFromCharacter(model) then
			used = true
			hum:TakeDamage(HUMANOID_DAMAGE * dmgMult)
			if isMagma then igniteHumanoid(hum, model, burnMult) end
			detonateSplash(ball.Position)
			-- маленький «пшик» при прямом попадании у неразрывных снарядов; пули с
			-- флагом NoExplode (напр. револьвер) его пропускают — они не взрываются
			if splash <= 0 and not ball:GetAttribute("NoExplode") then
				local exp = Instance.new("Explosion")
				exp.Position = ball.Position
				exp.BlastPressure = 0
				exp.BlastRadius = 4
				exp.Parent = workspace
			end
			if ball.Parent then ball:Destroy() end
		end
	end)

	-- splash shells also burst on the water surface — easier to finish off pirates floating
	-- in the sea (terrain water never fires .Touched, so watch the ball descend to it).
	if splash > 0 then
		task.spawn(function()
			local raft = workspace:FindFirstChild("Raft")
			local waterY = (raft and raft.PrimaryPart and raft.PrimaryPart.Position.Y) or (ball.Position.Y - 60)
			while not used and ball.Parent do
				RunService.Heartbeat:Wait()
				if ball.Position.Y <= waterY then
					used = true
					detonateSplash(Vector3.new(ball.Position.X, waterY, ball.Position.Z))
					if ball.Parent then ball:Destroy() end
					break
				end
			end
		end)
	end
end

workspace.DescendantAdded:Connect(watchBall)
for _, d in ipairs(workspace:GetDescendants()) do
	watchBall(d)
end

-- ── enemy ships shelling the raft ──
-- Horizontal direction the cannon points. The Cannon part's LookVector may point
-- straight up (depending on how the pivot was set), so instead we take whichever of
-- the part's local axes is most horizontal AND points away from the ship's centre —
-- i.e. the way the barrel sticks out of the hull. This fires OUT the barrel, never
-- straight up, while still honouring how the cannon is oriented (incl. a slight tilt).
local function cannonForward(ship, cannonCF)
	local center = ship:GetBoundingBox().Position
	local outward = Vector3.new(cannonCF.Position.X - center.X, 0, cannonCF.Position.Z - center.Z)
	if outward.Magnitude < 0.1 then
		outward = Vector3.new(cannonCF.LookVector.X, 0, cannonCF.LookVector.Z)
	end
	if outward.Magnitude < 0.1 then
		outward = Vector3.new(0, 0, -1)
	end
	outward = outward.Unit
	local axes = {
		cannonCF.RightVector, -cannonCF.RightVector,
		cannonCF.UpVector, -cannonCF.UpVector,
		cannonCF.LookVector, -cannonCF.LookVector,
	}
	local best, bestDot = nil, -2
	for _, a in ipairs(axes) do
		local h = Vector3.new(a.X, 0, a.Z)
		if h.Magnitude > 0.25 then -- skip near-vertical axes so we never fire straight up
			local d = h.Unit:Dot(outward)
			if d > bestDot then
				bestDot = d
				best = a
			end
		end
	end
	return best or outward
end

-- Launch velocity to hit `to` from `from` at `speed` under gravity — the flatter (low)
-- arc. Returns nil if the target is out of ballistic range for that speed.
local function ballisticVelocity(from, to, speed)
	local g = workspace.Gravity
	local disp = to - from
	local flat = Vector3.new(disp.X, 0, disp.Z)
	local dx = flat.Magnitude
	if dx < 0.5 then return nil end
	local dy = disp.Y
	local s2 = speed * speed
	local disc = s2 * s2 - g * (g * dx * dx + 2 * dy * s2)
	if disc < 0 then return nil end
	local theta = math.atan((s2 - math.sqrt(disc)) / (g * dx))
	return flat.Unit * (speed * math.cos(theta)) + Vector3.new(0, speed * math.sin(theta), 0)
end

-- Aim at the raft, leading its horizontal drift so the arcing shell connects.
local function aimAtRaft(from, raftPart, speed)
	local lead = Vector3.new(raftPart.AssemblyLinearVelocity.X, 0, raftPart.AssemblyLinearVelocity.Z)
	local target, vel = raftPart.Position, nil
	for _ = 1, 4 do
		vel = ballisticVelocity(from, target, speed)
		if not vel then break end
		local horiz = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local dx = Vector3.new(target.X - from.X, 0, target.Z - from.Z).Magnitude
		local t = (horiz > 0.1) and (dx / horiz) or 0
		target = raftPart.Position + lead * t
	end
	return vel
end

-- Fires the ship's "Cannon" out the barrel (cannonForward), straight — it doesn't
-- need to hit the raft; the bombardment still chips raft HP on contact.
local function fireAtRaft(ship)
	local cannon = ship:FindFirstChild("Cannon", true)
	local muzzle
	if cannon and cannon:IsA("BasePart") then
		muzzle = cannon:GetPivot()
	else
		local from = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true)
		if not from then return end
		muzzle = from.CFrame
	end
	-- Lead the moving raft with an arcing shot so the bombardment actually connects;
	-- if it's out of ballistic range, fall back to a flat forward shot (so distant
	-- ships still fire — they have to close in to land hits).
	local raft = workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	local level = ship:GetAttribute("ShipLevel") or 1
	local launchVel = rp and aimAtRaft(muzzle.Position, rp, SHIP_SHELL_SPEED)
	if not launchVel then launchVel = cannonForward(ship, muzzle) * SHIP_SHELL_SPEED end
	launchVel = launchVel + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)) -- slight spread

	local shell = Instance.new("Part")
	shell.Name = "ShipShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(1.8, 1.8, 1.8)
	shell.Color = Color3.fromRGB(25, 25, 28)
	shell.Material = Enum.Material.Slate
	shell.CanCollide = false -- passes through, but .Touched still fires
	shell.CFrame = CFrame.new(muzzle.Position)
	shell.AssemblyLinearVelocity = launchVel -- unanchored → arcs under gravity
	shell.Parent = workspace
	CombatSounds.play("shipFire", muzzle.Position) -- enemy ship cannon report

	-- muzzle blast at the cannon
	local flash = Instance.new("Explosion")
	flash.Position = muzzle.Position
	flash.BlastPressure = 0
	flash.BlastRadius = 4
	flash.Parent = workspace

	-- damage the raft ONLY when the shell actually touches it (a miss does nothing)
	local hit = false
	local conn
	conn = shell.Touched:Connect(function(part)
		if hit or not raft then return end
		if part:IsDescendantOf(raft) then
			hit = true
			conn:Disconnect()
			local exp = Instance.new("Explosion")
			exp.Position = shell.Position
			exp.BlastPressure = 0
			exp.BlastRadius = 6
			exp.Parent = workspace
			if _G.DamageRaft then _G.DamageRaft(SHIP_BASE_DAMAGE * level) end
			shell:Destroy()
		end
	end)
	-- ⚠️ ЯДРО ПРОСКАКИВАЕТ ПРЕГРАДЫ. Оно неколлидное и быстрое: между шагами
	-- физики оно перепрыгивает и остров, и чужой корпус, а Touched при этом не
	-- срабатывает. Поэтому каждый кадр проверяем сам ОТРЕЗОК пути: упёрлось в
	-- твёрдое — там и взрывается (по плоту — с уроном, как при касании).
	task.spawn(function()
		local prev = shell.Position
		local t = 0
		while shell.Parent and not hit and t < 6 do
			t += RunService.Heartbeat:Wait()
			local now = shell.Position
			local ignore = { shell, ship }
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character then table.insert(ignore, plr.Character) end
			end
			local hitPos, hitPart = WaterSpawn.solidHit(prev, now, ignore)
			prev = now
			if hitPos then
				hit = true
				if conn then conn:Disconnect() end
				local exp = Instance.new("Explosion")
				exp.Position = hitPos
				exp.BlastPressure = 0
				exp.BlastRadius = 6
				exp.Parent = workspace
				if raft and hitPart and hitPart:IsDescendantOf(raft) and _G.DamageRaft then
					_G.DamageRaft(SHIP_BASE_DAMAGE * level)
				end
				shell:Destroy()
				break
			end
		end
	end)

	task.delay(6, function() if shell.Parent then shell:Destroy() end end) -- despawn on a miss
end

-- ── magma ship: lob a Magma_ball that leaves a burning patch ──
local function magmaBallTemplate()
	return AssetFind.find(MAGMA_BALL_TEMPLATE) or workspace:FindFirstChild(MAGMA_BALL_TEMPLATE)
end

-- ─── ПАЛИТРА МАГМЫ ───
-- ⚠️ СЮДА СТАВИТСЯ СВОЙ РИСУНОК ПЛАМЕНИ — ЭТО ЕДИНСТВЕННОЕ МЕСТО.
-- Сейчас стоит встроенный спрайт движка. Свой (magma_flame.png / magma_pool.png)
-- надо залить в Roblox: Asset Manager → Images → Add Images, дождаться
-- модерации, скопировать id. Подставишь сюда две строки — перекрасятся разом
-- все слои: язык, столб удара, хвосты осколков и сама лужа.
-- ⚠️ ВАРИАНТОВ ПЛАМЕНИ НЕСКОЛЬКО, И ЭТО НЕ УКРАШАТЕЛЬСТВО.
-- Когда все очаги горят одной картинкой, повтор бросается в глаза сразу — три
-- лужи рядом выглядят копипастой. Каждый очаг тянет свой лист из этого списка.
-- Пустые строки просто пропускаются, так что варианты можно заливать по одному.
local MAGMA_TEX_FLAMES = {
	"rbxassetid://121761887619279", -- A: три гребня
	"rbxassetid://85005932535550",  -- B: пять гребней, приземистее
	"rbxassetid://120839016179981", -- C: с отрывающимися язычками
}
local MAGMA_TEX_POOL  = "rbxassetid://113985642406580" -- кипящая лужа
local MAGMA_TEX_BREAK = "rbxassetid://136788697701760" -- раскол шара (OneShot)
local MAGMA_TEX_FALLBACK = "rbxasset://textures/particles/fire_main.dds"

-- ⚠️ АНИМАЦИЯ ГОРЕНИЯ — ЭТО ЛИСТ КАДРОВ (ФЛИПБУК), А НЕ ОДНА КАРТИНКА.
-- Сама по себе картинка в частице не шевелится: движется только частица.
-- Чтобы горело, нужен лист 4×4 из 16 кадров — движок листает его сам.
-- ⚠️ ВКЛЮЧАЕТСЯ САМО, КОГДА ПОДСТАВЛЕН СВОЙ ID. Встроенный спрайт движка
-- флипбуком не является: включи листание на нём — он порежется на 16 клеток
-- и превратится в мусор. Поэтому признак берём из самой ссылки, а не отдельной
-- галкой, которую забудут переключить.
-- ⚠️ ЛИСТ 8×8 = 64 КАДРА, А НЕ 16.
-- На шестнадцати кадрах и быстрой прокрутке цикл прощупывается: глаз запоминает
-- последовательность и видит повтор. 64 кадра при 1024×1024 — потолок текстуры
-- Roblox, больше в лист просто не влезет.
local MAGMA_GRID = 8                       -- кадров в ряду на листе
-- Лист кадров узнаём по ссылке: встроенный спрайт движка (rbxasset://) флипбуком
-- не является, включи на нём листание — порежется на 16 клеток и станет кашей.
local function isSheet(tex)
	return type(tex) == "string" and tex:match("^rbxassetid://") ~= nil
end
local MAGMA_POOL_ANIMATED = isSheet(MAGMA_TEX_POOL)

-- ⚠️ СВОЮ КАРТИНКУ СВЕРХУ НЕ КРАСЯТ.
-- ParticleEmitter.Color УМНОЖАЕТ цвет на текстуру. Пока спрайт был серым
-- встроенным, красить его было обязательно — иначе не огонь, а дым. Но на
-- нарисованном листе весь переход уже есть: ядро, золото, оранж, тёмный кант.
-- Наложи на него красный — и вся эта работа умножится в бурое пятно. Поэтому
-- для своих листов тон белый, а прежняя палитра остаётся запасному спрайту.
local WHITE_SEQ = ColorSequence.new(Color3.new(1, 1, 1))
local function flameTint(tex, a, b)
	if isSheet(tex) then return WHITE_SEQ end
	return ColorSequence.new(a, b)
end

local function pickFlameTex()
	local pool = {}
	for _, id in ipairs(MAGMA_TEX_FLAMES) do
		if isSheet(id) then table.insert(pool, id) end
	end
	if #pool == 0 then return MAGMA_TEX_FALLBACK end
	return pool[math.random(#pool)]
end
-- Быстрая прокрутка: цикл из 64 кадров пролетает примерно за полторы секунды.
-- Вразнобой — чтобы соседние языки не били в такт и не выглядели одним огнём.
local MAGMA_FPS = NumberRange.new(34, 44)

-- ⚠️ ВЫЗЫВАТЬ ПОСЛЕ .Texture: решение принимается по картинке самого эмиттера,
-- а не по отдельному флагу, который разъедется с реальностью.
local function applyFlipbook(emitter, mode, fps)
	if not isSheet(emitter.Texture) then return end
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	emitter.FlipbookFramerate = fps or MAGMA_FPS
	emitter.FlipbookMode = mode or Enum.ParticleFlipbookMode.Loop
	-- Loop крутится по кругу (горение), OneShot проигрывается один раз за жизнь
	-- частицы — это для раскола: шар не может колоться заново каждые полсекунды.
	if mode ~= Enum.ParticleFlipbookMode.OneShot then
		emitter.FlipbookStartRandom = true -- иначе все языки горят одним кадром
	end
end

-- ⚠️ НАРИСОВАННЫХ ТЕКСТУР ЗДЕСЬ НЕТ — только встроенный спрайт движка
-- (fire_main.dds), перекрашенный этими цветами. Хочешь свой рисунок пламени —
-- его надо залить в Roblox и подставить id вместо rbxasset-строк ниже.
-- ⚠️ И НЕТ ШТАТНОГО ОБЪЕКТА Fire. Он даёт узнаваемый рыжий «костёр» — ровно
-- то, что и так везде в игре. Магма должна читаться КРАСНОЙ, поэтому пламя
-- собрано слоями: раскалённая сердцевина + тёмно-красное тело + угли.
local MAGMA_CORE_A = Color3.fromRGB(255, 150, 40)  -- сердцевина, самая горячая
local MAGMA_CORE_B = Color3.fromRGB(215, 35, 10)
local MAGMA_BODY_A = Color3.fromRGB(230, 55, 18)   -- тело пламени, основной красный
local MAGMA_BODY_B = Color3.fromRGB(95, 8, 5)      -- край, уходящий в дым
local MAGMA_EMBER  = Color3.fromRGB(255, 125, 40)  -- искры
local MAGMA_LIGHT  = Color3.fromRGB(255, 65, 25)   -- отсвет на палубе

-- ── УДАР МАГМЫ: ОСКОЛКИ + СТОЛБ ОГНЯ ──
-- Раньше на месте попадания хлопал штатный Explosion — серый пыльный шар,
-- который к раскалённому снаряду отношения не имеет. Теперь удар собран вручную
-- из трёх слоёв, как на референсе: врозь летят осколки, вверх бьёт столб огня,
-- по палубе расходится низкий всплеск пламени.

-- ⚠️ РАСКОЛ РИСУЕТСЯ ЧАСТИЦАМИ, А НЕ ЛЕТЯЩИМИ ДЕТАЛЯМИ.
-- Сначала тут разлетались настоящие Part'ы. В кадре их почти не видно: они
-- мелкие, летят быстро и на фоне вспышки теряются, зато каждая — тело в
-- физике рядом с плотом, за которым надо следить (не толкнуть, не разбудить
-- чужие Touched, не поймать лучом). Один спрайт с анимацией скола показывает
-- то же событие честнее и не лезет в физику вообще.
-- ⚠️ OneShot, А НЕ Loop: шар колется ОДИН раз. На Loop он бы раскалывался
-- заново каждые полсекунды, пока частица жива.
local function magmaBreak(hub, scale)
	local tex = isSheet(MAGMA_TEX_BREAK) and MAGMA_TEX_BREAK or pickFlameTex()

	-- крупный скол по центру: собственно шар, разлетающийся на куски
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = tex
	burst.Color = ColorSequence.new(Color3.new(1, 1, 1))
	burst.LightEmission = 0.45
	burst.LightInfluence = 0
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 6 * scale),
		NumberSequenceKeypoint.new(1, 9.5 * scale),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- OneShot растягивает 64 кадра ровно на жизнь частицы — она же и задаёт темп
	burst.Lifetime = NumberRange.new(0.7, 0.7)
	burst.Rate = 0
	burst.Speed = NumberRange.new(0, 0.5)
	burst.Rotation = NumberRange.new(0, 360)
	burst.EmissionDirection = Enum.NormalId.Top
	-- 64 кадра скола под 0.55 c жизни: ровно один прогон, без обрыва и повтора
	applyFlipbook(burst, Enum.ParticleFlipbookMode.OneShot, NumberRange.new(116, 116))
	burst.Parent = hub

	-- и отдельные куски, которые уносит в стороны
	local bits = burst:Clone()
	bits.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.4 * scale),
		NumberSequenceKeypoint.new(1, 1.2 * scale),
	})
	-- разлёт во все стороны: скол остался единственным, что показывает удар
	bits.Lifetime = NumberRange.new(0.45, 0.8)
	bits.Speed = NumberRange.new(9 * scale, 22 * scale)
	bits.SpreadAngle = Vector2.new(180, 180)
	bits.Acceleration = Vector3.new(0, -45, 0) -- куски падают, а не висят
	bits.RotSpeed = NumberRange.new(-260, 260)
	bits.Parent = hub

	burst:Emit(1)
	bits:Emit(math.floor(16 * scale + 0.5))
	-- Диагностика: если скола не видно, первым делом надо знать, ТОТ ли лист
	-- взят. Пустой MAGMA_TEX_BREAK молча подставляет пламя — и раскол выглядит
	-- обычной вспышкой огня, ровно как жалуются.
	print(("[Магма] скол: лист %s, кадров %d×%d")
		:format(tex, MAGMA_GRID, MAGMA_GRID))
end

-- Вспышка удара: столб огня вверх + низкий всплеск по поверхности.
-- Emit() вместо Rate — нужен разовый выброс, а не ровная струя.
local function magmaImpactBurst(position, scale)
	scale = scale or 1
	local hub = Instance.new("Part")
	hub.Name = "MagmaBurst"
	hub.Size = Vector3.new(1, 1, 1)
	-- ⚠️ ПОДНИМАЕМ УЗЕЛ НАД ПАЛУБОЙ.
	-- Шар в поперечнике около трёх студов: он раскалывается НАД доской, а не
	-- в ней. На 0.5 студа половина спрайта скола уходила под настил, и от
	-- эффекта оставалась верхняя кромка.
	hub.CFrame = CFrame.new(position + Vector3.new(0, 1.8, 0))
	hub.Anchored = true        -- якорим: это вспышка на месте, её никуда не несёт
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CanQuery = false
	hub.CastShadow = false
	hub.Transparency = 1
	hub.Parent = workspace

	-- ⚠️ ОГНЕННОГО СТОЛБА НА УДАРЕ БОЛЬШЕ НЕТ.
	-- Он брал лист ПЛАМЕНИ и разбрасывал его отдельными спрайтами: в кадре это
	-- читалось бледными кляксами и перебивало сам раскол. Взрыв теперь целиком
	-- нарисован листом скола (MAGMA_TEX_BREAK) — шар разлетается кусками, а
	-- огонь появляется следом, когда занимается палуба (createFirePatch).

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 45, 40), Color3.fromRGB(25, 20, 20))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6 * scale),
		NumberSequenceKeypoint.new(1, 5 * scale),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.7, 1.1)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(2.5, 5)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = hub

	local flash = Instance.new("PointLight")
	flash.Color = MAGMA_LIGHT
	flash.Range = 26 * scale
	flash.Brightness = 8
	flash.Parent = hub

	magmaBreak(hub, scale)
	smoke:Emit(math.floor(12 * scale))

	task.spawn(function()
		for step = 1, 10 do
			if not hub.Parent then return end
			flash.Brightness = 8 * (1 - step / 10)
			task.wait(0.03)
		end
	end)
	Debris:AddItem(hub, 2.2) -- частицы должны дожить свой век, потом убрать
end

-- A patch of magma fire (built from Roblox's Fire + particles — no asset needed).
-- If rideOnPart is given (a raft part the ball landed on), the patch is massless +
-- welded so it rides the moving raft and drains raft HP each second while it burns;
-- otherwise it's a short cosmetic flame (e.g. on the water / a miss).
local function createFirePatch(position, rideOnPart)
	-- On the raft: full burn (rides the deck + drains HP). On water: a weak flame
	-- that's gone within ~1s and does no damage.
	local onRaft = rideOnPart ~= nil
	local scale = onRaft and 1 or 0.45        -- water fire is small / weak
	local lifeScale = onRaft and 1 or 0.5     -- ...and short-lived
	local duration = onRaft and MAGMA_FIRE_DURATION or MAGMA_WATER_DURATION
	local radius = MAGMA_FIRE_RADIUS * scale
	local brightness = 4 * scale

	-- один вариант на очаг: сердцевина и тело должны гореть одной картинкой,
	-- иначе внутри одной лужи получится два разных огня
	local flameTex = pickFlameTex()

	local patch = Instance.new("Part")
	patch.Name = "MagmaFire"
	patch.Size = Vector3.new(radius * 2, 0.4, radius * 2)
	patch.CFrame = CFrame.new(position)
	patch.Anchored = (rideOnPart == nil)
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CastShadow = false
	patch.Transparency = 1
	patch.Massless = true -- never perturb the raft assembly
	patch.Parent = workspace

	-- ⚠️ ЧАСТИЦЫ СЕЮТСЯ ПО ВСЕЙ ГРАНИ ДЕТАЛИ, А НАРИСОВАННАЯ ЛУЖА — КРУГЛАЯ.
	-- Деталь квадратная, пятно вписано в неё: языки из углов вставали за краем
	-- огня, прямо на голых досках. Дать эмиттеру СВОЮ площадку поменьше —
	-- единственный способ, у ParticleEmitter нет своей области рождения.
	-- Массы у неё нет и столкновений тоже, так что в сборку плота она добавляет
	-- ровно ничего — как и сама лужа.
	local flameHost = Instance.new("Part")
	flameHost.Name = "MagmaFireHost"
	flameHost.Size = Vector3.new(radius * 0.9, 0.2, radius * 0.9)
	flameHost.CFrame = patch.CFrame
	flameHost.Anchored = patch.Anchored
	flameHost.CanCollide = false
	flameHost.CanQuery = false
	flameHost.CanTouch = false
	flameHost.CastShadow = false
	flameHost.Transparency = 1
	flameHost.Massless = true
	flameHost.Parent = patch
	if not flameHost.Anchored then
		local hostWeld = Instance.new("WeldConstraint")
		hostWeld.Part0 = patch
		hostWeld.Part1 = flameHost
		hostWeld.Parent = flameHost
	end

	-- Сердцевина: узкая, быстрая, светится сама. Поверх неё ляжет тёмно-красное
	-- тело — из-за этого пламя читается объёмным, а не плоской рыжей кляксой.
	local core = Instance.new("ParticleEmitter")
	core.Texture = flameTex
	core.Color = flameTint(flameTex, MAGMA_CORE_A, MAGMA_CORE_B)
	-- ⚠️ LightEmission СМЕШИВАЕТ СПРАЙТ АДДИТИВНО: на единице рисунок выгорает
	-- в белое пятно с видимыми краями квадрата — ровно то, что было на скрине.
	-- Своя картинка уже яркая, ей нужен лишь лёгкий подсвет.
	core.LightEmission = isSheet(flameTex) and 0.35 or 1
	core.LightInfluence = 0
	core.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5 * scale),
		NumberSequenceKeypoint.new(0.45, 2.4 * scale),
		NumberSequenceKeypoint.new(1, 0.6 * scale),
	})
	core.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- ⚠️ ОГОНЬ ГОРИТ АНИМАЦИЕЙ, А НЕ ПОЛЁТОМ ЧАСТИЦ.
	-- Раньше тут был рой быстрых мелких спрайтов — он и читался роем искр,
	-- мельтешащим во все стороны. Теперь наоборот: НЕМНОГО КРУПНЫХ языков,
	-- почти неподвижных и живущих подольше, а горение даёт листание кадров.
	core.Lifetime = NumberRange.new(0.7 * lifeScale, 1.0 * lifeScale)
	core.Rate = math.max(3, radius * 1.4)
	-- ⚠️ ПОЧТИ НУЛЕВАЯ СКОРОСТЬ: языку некуда лететь.
	-- Даже 1.5 студа в секунду за секунду жизни уносят язык на полтора студа
	-- вверх, и в кадре видно, как огонь ОТРЫВАЕТСЯ от лужи и всплывает.
	-- Ощущение подъёма должна давать анимация кадров, а не полёт спрайта.
	core.Speed = NumberRange.new(0, 0.3)
	core.SpreadAngle = Vector2.new(3, 3)
	core.Acceleration = Vector3.new(0, 0.4, 0)
	-- ⚠️ И ДЕРЖИМ ИХ НА ДЕТАЛИ: плот плывёт, а частицы по умолчанию остаются
	-- там, где родились, — огонь размазывало бы шлейфом за кормой.
	core.LockedToPart = onRaft
	core.EmissionDirection = Enum.NormalId.Top
	-- ⚠️ НИКАКОГО ПОЛНОГО ОБОРОТА: У ПЛАМЕНИ ЕСТЬ ВЕРХ.
	-- Случайный угол 0..360 достался от бесформенного спрайта — там крутить было
	-- можно и нужно, чтобы клубы не повторялись. Нарисованный язык от этого
	-- ложится набок и вверх ногами. Разброс оставляем на пару градусов: живое
	-- покачивание есть, а огонь по-прежнему растёт вверх.
	core.Rotation = NumberRange.new(-7, 7)
	applyFlipbook(core)
	core.Parent = flameHost

	local flames = Instance.new("ParticleEmitter")
	flames.Texture = flameTex
	flames.Color = flameTint(flameTex, MAGMA_BODY_A, MAGMA_BODY_B)
	flames.LightEmission = isSheet(flameTex) and 0.25 or 0.55
	flames.LightInfluence = 0
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.0 * scale),
		NumberSequenceKeypoint.new(0.5, 3.2 * scale),
		NumberSequenceKeypoint.new(1, 0.8 * scale),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Lifetime = NumberRange.new(0.85 * lifeScale, 1.3 * lifeScale)
	flames.Rate = math.max(4, radius * 2)
	flames.Speed = NumberRange.new(0, 0.6)
	flames.SpreadAngle = Vector2.new(6, 6)
	flames.Acceleration = Vector3.new(0, 0.8, 0)
	flames.LockedToPart = onRaft
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Rotation = NumberRange.new(-10, 10)
	applyFlipbook(flames)
	flames.Parent = flameHost

	-- ⚠️ САМА ЛУЖА — ТЕКСТУРА НА ВЕРХНЕЙ ГРАНИ, А НЕ ЕЩЁ ОДНА ДЕТАЛЬ.
	-- Круглого «пятна» в Roblox нет: деталь всегда коробка. Текстура огня на
	-- верхней грани даёт рваное пятно нужной формы и, в отличие от лишней
	-- детали, ничего не добавляет в физическую сборку плота. Рисуется она и на
	-- полностью прозрачной детали: у Texture своя прозрачность, не детали.
	local pool = Instance.new("Texture")
	pool.Face = Enum.NormalId.Top
	pool.Texture = MAGMA_TEX_POOL
	-- то же и здесь: нарисованную лужу не подкрашиваем, иначе съедим её цвета
	pool.Color3 = MAGMA_POOL_ANIMATED and Color3.new(1, 1, 1) or Color3.fromRGB(255, 70, 25)
	-- ⚠️ У Texture ФЛИПБУКА НЕТ — ЛИСТАЕМ САМИ, СДВИГОМ ОКНА.
	-- Тайл делаем в MAGMA_GRID раз крупнее грани: тогда на грань попадает ровно
	-- одна клетка листа, а сдвиг на ширину грани переводит на соседний кадр.
	local tile = radius * 2 * (MAGMA_POOL_ANIMATED and MAGMA_GRID or 1)
	pool.StudsPerTileU = tile
	pool.StudsPerTileV = tile
	pool.Transparency = 0.15
	pool.Parent = patch

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(55, 42, 38), Color3.fromRGB(22, 18, 18))
	smoke.LightInfluence = 0.4
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2 * scale),
		NumberSequenceKeypoint.new(1, 8 * scale),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1, 1.8)
	-- на воде дыма нет: там пламя живёт меньше секунды, столб не успел бы встать
	smoke.Rate = onRaft and radius * 1.6 or 0
	smoke.Speed = NumberRange.new(4, 8)
	smoke.SpreadAngle = Vector2.new(25, 25)
	smoke.Acceleration = Vector3.new(0, 5, 0)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = flameHost

	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(MAGMA_EMBER)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.15 * scale)
	embers.Transparency = NumberSequence.new(0.2)
	embers.Lifetime = NumberRange.new(0.6 * lifeScale, 1.2 * lifeScale)
	embers.Rate = radius * 1.2
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(40, 40)
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = flameHost

	local light = Instance.new("PointLight")
	light.Color = MAGMA_LIGHT
	light.Range = radius * 2.5
	light.Brightness = brightness
	light.Parent = patch

	-- Ровный, как лампа, огонь сразу выдаёт подделку: лужа и свет должны дышать.
	-- ⚠️ КАДРЫ ЛУЖИ КРУТИМ ОТДЕЛЬНЫМ ЦИКЛОМ.
	-- Раньше шаг висел на дрожании света (11 раз в секунду) — на 16 кадрах это
	-- сходило, а на 64 цикл растянулся бы на шесть секунд и лужа выглядела бы
	-- застывшей. Свету частота ни к чему, а кадрам нужна.
	if MAGMA_POOL_ANIMATED then
		task.spawn(function()
			local f = 0
			while patch.Parent and core.Enabled do
				f = (f + 1) % (MAGMA_GRID * MAGMA_GRID)
				pool.OffsetStudsU = (f % MAGMA_GRID) * radius * 2
				pool.OffsetStudsV = math.floor(f / MAGMA_GRID) * radius * 2
				task.wait(1 / 32)
			end
		end)
	end

	task.spawn(function()
		while patch.Parent and core.Enabled do
			local f = math.random(80, 120) / 100
			light.Brightness = brightness * f
			pool.Transparency = 0.1 + (f - 0.8) * 0.5
			task.wait(0.09)
		end
	end)

	if rideOnPart then
		--[[ ⚠️ ВЛАДЕНИЕ — СЕРВЕРУ ДО СВАРКИ. Лужа с владением «авто» вваривается в
		     плот, сборка пересобирается и уходит ближайшему игроку — один рывок,
		     пока сторож не вернёт её серверу. Закреплённая заранее лужа сборку
		     не перекрашивает: обе стороны серверные, менять нечего. ]]
		pcall(function() patch:SetNetworkOwner(nil) end)
		pcall(function() flameHost:SetNetworkOwner(nil) end)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rideOnPart
		weld.Part1 = patch
		weld.Parent = patch
		local root = rideOnPart.AssemblyRootPart
		if root and not root.Anchored then pcall(function() root:SetNetworkOwner(nil) end) end
	end

	task.spawn(function()
		if onRaft then
			local t = 0
			while t < duration and patch.Parent do
				t += task.wait(1)
				if rideOnPart and rideOnPart.Parent and _G.DamageRaft then
					_G.DamageRaft(MAGMA_BURN_DPS) -- keep burning the raft
				end
			end
		else
			task.wait(duration) -- water: brief flame, no damage
		end
		core.Enabled = false
		flames.Enabled = false
		embers.Enabled = false
		smoke.Enabled = false
		local steps = onRaft and 10 or 3
		for i = 1, steps do
			if not patch.Parent then break end
			light.Brightness = brightness * (1 - i / steps)
			pool.Transparency = 0.15 + 0.85 * (i / steps) -- лужа остывает вместе со светом
			task.wait(0.1)
		end
		if patch.Parent then patch:Destroy() end
	end)
	return patch
end

local FIRE_IGNORE = { MagmaFire = true, PirateCoin = true, ShipShell = true, Bullet_Cannon = true, Magma_ball = true,
	MagmaBurst = true, -- вспышка своего же удара
	Frost_breath = true, FrostWave = true, FrostTrail = true }

-- ── ПОЛЁТ И ПОДРЫВ МАГМОВОГО СНАРЯДА ──
-- Отдельно от пушки: тем же кодом летит и боевой выстрел корабля, и тестовый
-- сброс с неба из настроек. Дублировать подрыв нельзя — эффект разошёлся бы с
-- боевым при первой же правке, и проверяли бы мы не то, что видит игрок.
-- ship = nil у теста: стрелявшего нет, и это учтено в фильтрах ниже.
local function launchMagmaBall(startPos, velocity, ship, level, waterY, opts)
	opts = opts or {}
	local raft = workspace:FindFirstChild("Raft")
	-- the projectile: clone Magma_ball (fall back to a glowing ball if missing)
	local template = magmaBallTemplate()
	local ball, ballPart
	if template then
		ball = template:Clone()
		if ball:IsA("BasePart") then
			ballPart = ball
		else
			ballPart = ball.PrimaryPart or ball:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	if not ballPart then
		if ball then ball:Destroy() end
		ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(3, 3, 3)
		ball.Color = Color3.fromRGB(255, 90, 20)
		ball.Material = Enum.Material.Neon
		ballPart = ball
	end
	ball.Name = "Magma_ball"
	for _, d in ipairs(ball:IsA("BasePart") and { ball } or ball:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false -- keep the ball out of the surface raycast
			if d ~= ballPart then
				local w = Instance.new("WeldConstraint") -- keep multi-part models together in flight
				w.Part0 = ballPart
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	if ball:IsA("Model") then
		if not ball.PrimaryPart then ball.PrimaryPart = ballPart end
		ball:PivotTo(CFrame.new(startPos))
	else
		ball.CFrame = CFrame.new(startPos)
	end
	ball.Parent = workspace
	ballPart.AssemblyLinearVelocity = velocity -- дальше его ведёт гравитация
	CombatSounds.play("magma", startPos)

	-- Дульная вспышка — только у пушки. У тестового снаряда, падающего с неба,
	-- стрелять неоткуда, и хлопок в пустоте выглядел бы обрывком чужого эффекта.
	if opts.muzzleFlash then
		local flash = Instance.new("Explosion")
		flash.Position = startPos
		flash.BlastPressure = 0
		flash.BlastRadius = 4
		flash.Parent = workspace
	end

	-- Detonate by finding the surface (raft deck / island / water) straight BELOW
	-- the ball and dropping the fire THERE — never floating in the air. If the ball
	-- bursts over the raft, the patch lands on the deck (so the raft burns, not the
	-- sky above it) and the burning DoT then drains the raft each second.
	local done = false
	local function detonate(fromPos)
		if done then return end
		done = true
		-- ignore the firing ship, the ball, and players so the ray finds the deck/water
		local filter = { ball }
		if ship then table.insert(filter, ship) end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then table.insert(filter, plr.Character) end
		end
		local rp = RaycastParams.new()
		rp.IgnoreWater = false
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = filter
		local res = workspace:Raycast(fromPos + Vector3.new(0, 4, 0), Vector3.new(0, -300, 0), rp)
		local hitInst = res and res.Instance
		local atPos = (res and res.Position) or Vector3.new(fromPos.X, waterY, fromPos.Z)
		local onRaft = hitInst ~= nil and raft ~= nil and hitInst:IsDescendantOf(raft)

		-- ⚠️ ШТАТНОГО Explosion ЗДЕСЬ БОЛЬШЕ НЕТ.
		-- Он рисует серый пыльный шар — от раскалённого снаряда ждут не этого.
		-- Свой удар: осколки веером, столб огня вверх, всплеск по палубе.
		-- Урон он всё равно не наносил (BlastPressure = 0), так что ничего,
		-- кроме картинки, не поменялось.
		magmaImpactBurst(atPos, onRaft and 1 or 0.6) -- по воде удар глуше

		if onRaft and _G.DamageRaft and not opts.noDamage then
			_G.DamageRaft(SHIP_BASE_DAMAGE * level) -- impact = same as a basic ship
		end

		-- ⚠️ ОГОНЬ РАЗГОРАЕТСЯ ПОСЛЕ СКОЛА, А НЕ ОДНОВРЕМЕННО С НИМ.
		-- Лужа начинала гореть в тот же кадр, в который шар раскалывался, и
		-- языки вставали ровно поверх обломков — скол был, но его не было видно.
		-- Порядок к тому же честнее по событию: сперва разлетается шар, потом
		-- занимается палуба.
		task.delay(0.16, function()
			if onRaft then
				if hitInst and hitInst.Parent then
					createFirePatch(atPos, hitInst) -- на палубе: едет с плотом и жжёт его
				end
			else
				createFirePatch(atPos, nil) -- вода / остров: просто пламя на поверхности
			end
		end)
		if ball.Parent then ball:Destroy() end
	end

	ballPart.Touched:Connect(function(hit)
		if (ship and hit:IsDescendantOf(ship)) or FIRE_IGNORE[hit.Name] then return end
		detonate(ballPart.Position)
	end)
	-- miss / open water: when the ball sinks to the surface, burst there.
	-- ⚠️ ЗАОДНО СЛЕДИМ ЗА ПРЕГРАДАМИ. Шар неколлидный и летит по дуге: остров
	-- или чужой корпус он между кадрами перепрыгивает, и Touched молчит. Луч по
	-- отрезку пути ловит это честно.
	task.spawn(function()
		local t = 0
		local prev = ballPart.Position
		while not done and ball.Parent and t < 8 do
			t += task.wait()
			local now = ballPart.Position
			local ignore = { ball }
			if ship then table.insert(ignore, ship) end
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character then table.insert(ignore, plr.Character) end
			end
			local hitPos = WaterSpawn.solidHit(prev, now, ignore)
			prev = now
			if hitPos then
				detonate(hitPos)
				break
			end
			if now.Y <= waterY then
				detonate(now)
				break
			end
		end
		if not done and ball.Parent then ball:Destroy() end
	end)
end

-- ТЕСТ ИЗ НАСТРОЕК: уронить шар магмы прямо на игрока, чтобы посмотреть удар.
-- Урона от попадания нет — кнопку жмут ради эффекта, а не чтобы топить плот;
-- горящая лужа при этом настоящая и палубу подъедает, как в бою.
local TEST_DROP_HEIGHT = 95   -- откуда падает: успеваешь увидеть подлёт
local TEST_DROP_SPEED  = 55
function _G.MagmaTestStrike(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "нет персонажа" end
	local raft = workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	local waterY = (rp and rp.Position.Y) or (hrp.Position.Y - 6)
	launchMagmaBall(hrp.Position + Vector3.new(0, TEST_DROP_HEIGHT, 0),
		Vector3.new(0, -TEST_DROP_SPEED, 0), nil, 0, waterY, { noDamage = true })
	return true
end

local function fireMagmaAtRaft(ship)
	local cannon = ship:FindFirstChild("Cannon", true)
	local muzzle
	if cannon and cannon:IsA("BasePart") then
		muzzle = cannon:GetPivot()
	else
		local from = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true)
		if not from then return end
		muzzle = from.CFrame
	end

	local raft = workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	local toR = (rp and (rp.Position - muzzle.Position)) or muzzle.LookVector
	local flat = Vector3.new(toR.X, 0, toR.Z)
	if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
	local launch = (flat.Unit + Vector3.new(math.random(-12, 12) / 100, SHELL_ARC, math.random(-12, 12) / 100)).Unit
	local level = ship:GetAttribute("ShipLevel") or 1
	local waterY = (rp and rp.Position.Y) or (muzzle.Position.Y - 10)

	launchMagmaBall(muzzle.Position, launch * SHIP_SHELL_SPEED, ship, level, waterY,
		{ muzzleFlash = true })
end

-- ── ЛЕДЯНОЙ КОРАБЛЬ ──

-- кратко замедлить игрока (не стакается, восстанавливается сам)
local function chillPlayer(char)
	if not char then return end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum or char:GetAttribute("_Chilled") then return end
	char:SetAttribute("_Chilled", true)
	local base = hum.WalkSpeed
	hum.WalkSpeed = base * FROST_SLOW_MULT
	task.delay(FROST_SLOW_DUR, function()
		if hum and hum.Parent then hum.WalkSpeed = base end
		if char then char:SetAttribute("_Chilled", nil) end
	end)
end

-- струя холодного воздуха из пасти. Возвращает {part, emit}: fireFrost сам крутит part.CFrame
-- каждый кадр (чтобы струя качалась вместе с головой) и гасит emit в конце выдоха.
local function makeFrostBreath()
	local p = Instance.new("Part")
	p.Name = "Frost_breath"
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Transparency = 1; p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = workspace
	local emit = Instance.new("ParticleEmitter")
	emit.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emit.Color = ColorSequence.new(FROST_COLOR, Color3.fromRGB(215, 242, 255))
	emit.LightEmission = 0.35
	emit.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	emit.Lifetime = NumberRange.new(0.5, 0.95)
	emit.Rate = 190
	emit.Speed = NumberRange.new(34, 50)
	emit.SpreadAngle = Vector2.new(15, 15)
	emit.EmissionDirection = Enum.NormalId.Front
	emit.Parent = p
	return p, emit
end

-- истинное «вперёд» ледяного корабля: направление на голову (Front). Модель едет боком
-- (её PrimaryPart смотрит не туда), поэтому один раз запоминаем УГОЛ между LookVector
-- корпуса и головой (_FrostFwdYaw) и дальше крутим LookVector на этот угол. Так «перёд»
-- стабилен, даже когда голова качается во время выдоха (тогда сам Front двигается, а
-- корпус — нет), и рулевой (chaseLoop) не дёргается вслед за качающейся башкой.
local function shipForward(ship)
	local base = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true)
	if not base then return Vector3.new(0, 0, 1) end
	local lv = base.CFrame.LookVector
	local baseDir = Vector3.new(lv.X, 0, lv.Z)
	baseDir = (baseDir.Magnitude > 0.1) and baseDir.Unit or Vector3.new(0, 0, 1)
	local off = ship:GetAttribute("_FrostFwdYaw")
	if not off then
		local front = ship:FindFirstChild(FROST_MUZZLE_NAME, true)
		if front and front:IsA("BasePart") then
			local d = Vector3.new(front.Position.X - base.Position.X, 0, front.Position.Z - base.Position.Z)
			if d.Magnitude > 0.1 then
				local hd = d.Unit
				off = math.atan2(baseDir:Cross(hd).Y, baseDir:Dot(hd))
				ship:SetAttribute("_FrostFwdYaw", off) -- запоминаем один раз (нейтральная поза)
			end
		end
		off = off or 0
	end
	return (CFrame.fromAxisAngle(Vector3.yAxis, off) * baseDir)
end


-- всплеск-РАЗБИВАНИЕ холодной воды в точке: вертикальный фонтан капель вверх + пена +
-- короткий водяной султан (столб). НЕ плоский круг. scale — размер (эмердж мельче удара).
-- Серверный :Emit НЕ реплицируется, поэтому «залп» = включённый Rate на короткое окно.
local function waterSplash(pos, scale)
	scale = scale or 1
	local host = Instance.new("Part")
	host.Name = "FrostWave"
	host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.CanTouch = false; host.CastShadow = false
	host.Transparency = 1; host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(pos)
	host.Parent = workspace

	-- КОРОНА капель: узкий конус ВВЕРХ, потом падают дугой (разбивание воды, не круг)
	local crown = Instance.new("ParticleEmitter")
	crown.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	crown.Color = ColorSequence.new(Color3.fromRGB(205, 238, 255), FROST_COLOR)
	crown.LightEmission = 0.5
	crown.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9 * scale), NumberSequenceKeypoint.new(0.6, 0.5 * scale), NumberSequenceKeypoint.new(1, 0) })
	crown.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	crown.Lifetime = NumberRange.new(0.35, 0.75)
	crown.Rate = 450
	crown.Speed = NumberRange.new(20 * scale, 44 * scale)
	crown.SpreadAngle = Vector2.new(42, 42) -- узкий фонтан вверх, а не плоский диск
	crown.Acceleration = Vector3.new(0, -80, 0) -- капли падают обратно → дуга
	crown.EmissionDirection = Enum.NormalId.Top
	crown.Parent = host

	-- ПЕНА у основания
	local foam = Instance.new("ParticleEmitter")
	foam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	foam.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255), FROST_COLOR)
	foam.LightEmission = 0.3
	foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2 * scale), NumberSequenceKeypoint.new(1, 3.6 * scale) })
	foam.Lifetime = NumberRange.new(0.3, 0.6)
	foam.Rate = 130
	foam.Speed = NumberRange.new(3, 9)
	foam.SpreadAngle = Vector2.new(38, 38)
	foam.Acceleration = Vector3.new(0, -14, 0)
	foam.EmissionDirection = Enum.NormalId.Top
	foam.Parent = host
	task.delay(0.05, function() crown.Enabled = false; foam.Enabled = false end)
	Debris:AddItem(host, 0.9)
end

-- РАЗБИВАНИЕ сосульки: водяной фонтан (waterSplash) + разлёт ледяной крошки + пара
-- реальных осколков льда с гравитацией + звук раскола. dir — куда преимущественно летят
-- осколки (по ходу полёта). Это заменяет прежний «прямоугольный» эффект.
local function iceShatter(pos, dir)
	waterSplash(pos) -- водяная часть удара (фонтан вверх)
	-- (звёздочки-«крошку» из спарклов убрали — крушение читается по осколкам и фонтану)

	-- несколько настоящих осколков льда (мелкие, разлетаются и падают)
	local out = dir and Vector3.new(dir.X, 0, dir.Z)
	out = (out and out.Magnitude > 0.1) and out.Unit or Vector3.new(0, 0, 0)
	for _ = 1, 5 do
		local sh = Instance.new("Part")
		sh.Name = "FrostWave"
		sh.CanCollide = false; sh.CanQuery = false; sh.CanTouch = false; sh.CastShadow = false
		sh.Material = Enum.Material.Ice
		sh.Color = Color3.fromRGB(200, 235, 255)
		sh.Transparency = 0.12
		sh.Size = Vector3.new(0.3 + math.random() * 0.4, 0.35 + math.random() * 0.7, 0.3 + math.random() * 0.4)
		sh.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		sh.Parent = workspace
		sh.AssemblyLinearVelocity = out * math.random(6, 14)
			+ Vector3.new((math.random() - 0.5) * 20, 10 + math.random() * 14, (math.random() - 0.5) * 20)
		Debris:AddItem(sh, 0.7)
	end

	CombatSounds.play("iceShatter", pos) -- хруст льда
	CombatSounds.play("iceBoom", pos)    -- + глухой взрыв под ним
end

-- клонирует и готовит 3D-модель сосульки Ice_bullet из ReplicatedStorage (заякорить, без
-- коллизий/рейкастов). ПЕРЁД определяется по парту-маркеру, который автор вставил в НОС
-- модели ("Front" или "Part"): направление «центр меша → маркер» и есть нос сосульки.
-- Возвращает (инстанс, размерВектор, face), где face = { f0 = мировой вектор носа в
-- эталонной позе, rot0 = эталонный поворот модели } — или face = nil, если маркера нет
-- (тогда полёт использует старые ручные константы FROST_ICICLE_FACE/YAW_FIX).
local function prepIceBullet()
	local tmpl = AssetFind.find(FROST_ICE_MODEL)
	if not tmpl then return nil, nil, nil end
	local c = tmpl:Clone()
	local size
	if c:IsA("Model") then
		if not c.PrimaryPart then c.PrimaryPart = c:FindFirstChildWhichIsA("BasePart", true) end
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			end
		end
		local _, s = c:GetBoundingBox()
		size = s
	elseif c:IsA("BasePart") then
		c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false; c.CastShadow = false
		size = c.Size
	else
		c:Destroy(); return nil, nil, nil
	end

	-- нос по маркеру: самый КРУПНЫЙ парт — тело сосульки, маркер — вставленный в нос парт
	local face = nil
	if c:IsA("Model") then
		local marker = c:FindFirstChild("Front", true) or c:FindFirstChild("Part", true)
		local body, bodyVol = nil, 0
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") and d ~= marker then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bodyVol then body, bodyVol = d, v end
			end
		end
		if marker and marker:IsA("BasePart") and body then
			marker.Transparency = 1 -- служебный, в игре не виден
			local f0 = marker.Position - body.Position
			if f0.Magnitude > 0.05 then
				face = { f0 = f0.Unit, rot0 = c:GetPivot().Rotation }
			end
		end
	end
	return c, size, face
end

-- двигает модель или парт единообразно
local function setCF(inst, cf)
	if inst:IsA("Model") then inst:PivotTo(cf) else inst.CFrame = cf end
end

-- минимальный поворот, переводящий единичный вектор a в единичный вектор b
local function rotBetween(a, b)
	local d = math.clamp(a:Dot(b), -1, 1)
	if d > 0.9999 then return CFrame.new() end
	if d < -0.9999 then -- противоположные: разворот на 180° вокруг любой перпендикулярной оси
		local axis = a:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-4 then axis = a:Cross(Vector3.xAxis) end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(d))
end

-- морозный шлейф полёта сосульки: за ней тянется ТА ЖЕ холодная струя, что и выдох
-- головы ледяного корабля (makeFrostBreath), + редкие ледяные искры и мягкая подсветка.
-- Никаких линий-Trail. Выключено при создании (сосулька рождается ПОД водой) — полёт
-- включает всё в момент выныривания. Возвращает (списокВключаемого, эмиттерВспышки,
-- партСтруи): парт струи полёт каждый кадр ставит в хвост сосульки носом назад.
local function addFrostFlightFX(ice, size)
	local host = ice
	if ice:IsA("Model") then
		local best, bv = nil, 0
		for _, d in ipairs(ice:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then -- маркер носа (прозрачный) не берём
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bv then best, bv = d, v end
			end
		end
		host = best or ice.PrimaryPart
	end
	if not host then return {}, nil, nil end

	local glint = Instance.new("ParticleEmitter") -- редкие кристаллики, ловящие свет
	glint.Name = "FrostGlint"
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255), Color3.fromRGB(160, 215, 255))
	glint.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	glint.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	glint.Lifetime = NumberRange.new(0.3, 0.6)
	glint.Rate = 12
	glint.Speed = NumberRange.new(0.5, 2)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.LightEmission = 1
	glint.LightInfluence = 0
	glint.Enabled = false
	glint.Parent = host

	-- струя-выдох (1:1 с makeFrostBreath — «воздух, которым дышит голова»): отдельный
	-- заякоренный парт; полёт каждый кадр ставит его в ХВОСТ сосульки носом назад, и
	-- струя дует назад по ходу
	local plume = Instance.new("Part")
	plume.Name = "IcicleBreath"
	plume.Anchored = true; plume.CanCollide = false; plume.CanQuery = false; plume.CanTouch = false
	plume.CastShadow = false
	plume.Transparency = 1
	plume.Size = Vector3.new(0.2, 0.2, 0.2)
	plume.Parent = workspace
	Debris:AddItem(plume, 9) -- бэкстоп на случай сбоя цикла полёта
	local jet = Instance.new("ParticleEmitter")
	jet.Texture = "rbxasset://textures/particles/smoke_main.dds"
	jet.Color = ColorSequence.new(FROST_COLOR, Color3.fromRGB(215, 242, 255))
	jet.LightEmission = 0.35
	jet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	-- почти как выдох головы (2→7 / 0.5-0.95 / 130), лишь САМУЮ МАЛОСТЬ меньше
	jet.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 6) })
	jet.Lifetime = NumberRange.new(0.45, 0.85)
	jet.Rate = 110
	jet.Speed = NumberRange.new(20, 30)
	jet.SpreadAngle = Vector2.new(14, 14)
	jet.EmissionDirection = Enum.NormalId.Front
	jet.Enabled = false
	jet.Parent = plume

	local glow = Instance.new("PointLight") -- мягкий холодный отсвет на воде
	glow.Color = Color3.fromRGB(170, 220, 255)
	glow.Brightness = 1.1
	glow.Range = 9
	glow.Enabled = false
	glow.Parent = host

	return { glint, jet, glow }, glint, plume
end

-- запускает ОДНУ сосульку (модель Ice_bullet): она ЗАРОЖДАЕТСЯ из-под воды в точке spawnPos
-- (где туман коснулся воды) и СКОЛЬЗИТ вперёд у самой поверхности — часть идёт НАД водой,
-- часть ПОД водой (не взлетает в воздух). Разбивается (iceShatter + звук) при попадании в
-- плот (урон — один раз на залп через volley) либо в воде по пределу дальности. Морозит рядом.
local function launchIcicle(spawnPos, dir, waterY, volley)
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = (dir.Magnitude > 0.1) and dir.Unit or Vector3.new(0, 0, 1)
	local ice, size, face = prepIceBullet()
	if not ice then return end
	local height = (size and size.Y) or 3
	local right = Vector3.new(-dir.Z, 0, dir.X)

	local speed   = FROST_SPRAY_SPEED * (0.85 + math.random() * 0.3)
	local lateral = (math.random() - 0.5) * 6
	-- уровень скольжения: примерно половина НАД водой (+), половина ПОД водой (−)
	local above = math.random() < 0.5
	local level = above and (0.4 + math.random() * 1.0) or -(0.8 + math.random() * 1.6)
	local bobAmp, bobFreq, bobPhase = 0.35 + math.random() * 0.4, 2 + math.random() * 1.5, math.random() * math.pi * 2
	local startLevel = -(math.min(height, 3) + 1) -- старт заметно ПОД водой
	local breachPeak = 0.9                          -- на выныривании чуть поднимается НАД воду (для всех)
	local emergeT = 0.28                            -- сколько поднимается НА МЕСТЕ, прежде чем лететь

	-- индивидуальная «змейка» этой сосульки: своя фаза и чуть своя амплитуда
	local weavePhase  = math.random() * math.pi * 2
	local weaveJitter = 0.7 + math.random() * 0.6

	local fxList, fxBurst, plume = addFrostFlightFX(ice, size) -- морозный шлейф (включим на выныривании)

	ice.Parent = workspace
	Debris:AddItem(ice, 7) -- бэкстоп на случай сбоя цикла
	-- вода расступается прямо в точке рождения — видно, что сосулька выходит ИЗ воды
	waterSplash(Vector3.new(spawnPos.X, waterY, spawnPos.Z), 0.8)

	task.spawn(function()
		local traveled, elapsed = 0, 0
		local fxOn = false
		local noseDir = dir  -- куда смотрит нос; плавно догоняет фактический ход (змейку)
		local prevPos = nil
		local prevStep = nil   -- откуда шагнули в этом кадре: по нему проверяем преграду
		while ice.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			-- 1) поднимается ИЗ-ПОД воды на месте (emergeT), пробивая поверхность; 2) потом летит вперёд
			local riseFrac = math.min(elapsed / emergeT, 1)                -- всплытие: startLevel → breachPeak
			local settle   = math.clamp((elapsed - emergeT) / 0.4, 0, 1)   -- оседание: breachPeak → level
			local fwdFrac  = math.clamp((elapsed - emergeT) / 0.25, 0, 1)  -- вперёд ТОЛЬКО после выныривания
			traveled += speed * fwdFrac * dt

			local raft = workspace:FindFirstChild("Raft")
			local rpp = raft and raft.PrimaryPart and raft.PrimaryPart.Position
			local raftRadius = (_G.GetRaftRadius and _G.GetRaftRadius()) or 14

			-- ЗМЕЙКА у плота: чем ближе к краю плота, тем сильнее виляние поперёк курса.
			-- Синус вокруг прямой (среднее = 0), так что в цель она всё равно приходит.
			local weave = 0
			if rpp then
				local ref = prevPos or spawnPos
				local distToRaft = Vector3.new(rpp.X - ref.X, 0, rpp.Z - ref.Z).Magnitude - raftRadius
				local ramp = math.clamp((FROST_WEAVE_DIST - distToRaft) / 18, 0, 1)
				ramp = ramp * ramp * (3 - 2 * ramp) -- плавный вход в змейку, без рывка
				weave = math.sin(traveled / FROST_WEAVE_LEN * math.pi * 2 + weavePhase)
					* FROST_WEAVE_AMP * weaveJitter * ramp * settle
			end

			local yBase = startLevel + (breachPeak - startLevel) * riseFrac
			yBase = yBase + (level - breachPeak) * settle
			local pos = spawnPos + dir * traveled + right * (lateral + weave)
			pos = Vector3.new(pos.X, waterY + yBase + math.sin(elapsed * bobFreq + bobPhase) * bobAmp * settle, pos.Z)

			-- нос — по ФАКТИЧЕСКОМУ ходу (вместе со змейкой), с плавным доворотом без дёрганья
			if prevPos then
				local mv = Vector3.new(pos.X - prevPos.X, 0, pos.Z - prevPos.Z)
				if mv.Magnitude > 1e-3 then
					local blend = math.min(dt * 10, 1)
					local nd = noseDir + (mv.Unit - noseDir) * blend
					if nd.Magnitude > 1e-3 then noseDir = nd.Unit end
				end
			end
			prevPos = pos

			-- ориентация: по парту-маркеру в носу (face), иначе — старые ручные константы
			local rotCF
			if face then
				rotCF = rotBetween(face.f0, noseDir) * face.rot0
			else
				local yaw = math.atan2(-noseDir.X, -noseDir.Z) + FROST_ICICLE_YAW_FIX
				rotCF = CFrame.Angles(0, yaw, 0) * FROST_ICICLE_FACE
			end
			pcall(function() setCF(ice, CFrame.new(pos) * rotCF) end)

			-- струя-выдох дует из ХВОСТА назад по ходу (как дыхание головы, только на лету)
			if plume and plume.Parent then
				local tail = pos - noseDir * (height * 0.5 + 0.6)
				plume.CFrame = CFrame.lookAt(tail, tail - noseDir)
			end

			-- морозный шлейф включается ровно в момент выныривания (под водой ему делать нечего)
			if not fxOn and riseFrac >= 1 then
				fxOn = true
				for _, e in ipairs(fxList) do e.Enabled = true end
				if fxBurst then fxBurst:Emit(10) end -- брызги кристалликов при пробое поверхности
			end

			for _, plr in ipairs(Players:GetPlayers()) do
				local ch = plr.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp and Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z).Magnitude <= 7 then
					chillPlayer(ch)
				end
			end

			-- ⚠️ ПРЕГРАДА НА ПУТИ. Сосулька двигается CFrame'ом, столкновений у неё
			-- нет вообще — поэтому она пролетала СКВОЗЬ острова и чужие корпуса.
			-- Проверяем сам отрезок пути: упёрлась в твёрдое — разбилась там.
			-- Игроков и сам снаряд исключаем: игрока сосулька морозит (выше), а
			-- плот разбирается отдельной проверкой ниже — по нему нужен ещё и урон.
			local blockIgnore = { ice }
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character then table.insert(blockIgnore, plr.Character) end
			end
			local hitPos, hitPart = WaterSpawn.solidHit(prevStep or spawnPos, pos, blockIgnore)
			prevStep = pos
			if hitPos then
				local onRaft = raft and hitPart and hitPart:IsDescendantOf(raft)
				iceShatter(hitPos, noseDir)
				if onRaft and volley and not volley.hitRaft then
					volley.hitRaft = true
					if _G.DamageRaft then _G.DamageRaft(SHIP_BASE_DAMAGE) end
				end
				ice:Destroy(); break
			end

			if rpp and Vector3.new(rpp.X - pos.X, 0, rpp.Z - pos.Z).Magnitude <= raftRadius then
				iceShatter(pos, noseDir) -- врезалась в плот
				if volley and not volley.hitRaft then
					volley.hitRaft = true
					if _G.DamageRaft then _G.DamageRaft(SHIP_BASE_DAMAGE) end
				end
				ice:Destroy(); break
			elseif traveled >= FROST_WAVE_TRAVEL or elapsed > 5 then
				iceShatter(Vector3.new(pos.X, waterY, pos.Z), noseDir) -- разбилась в воде на пределе дальности
				ice:Destroy(); break
			end
		end
		-- сосульки больше нет — глушим струю и даём уже выпущенному пару дотаять
		if plume and plume.Parent then
			for _, e in ipairs(plume:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			Debris:AddItem(plume, 1.2)
		end
	end)
end

-- атака: ПРОДЛЁННЫЙ выдох холода из головы (Front), при этом голова КРУТИТСЯ вправо-влево
-- по кривой (чуть вверх-вниз). Струя качается вместе с головой. Из выдоха в воде ПЕРЕД
-- кораблём формируется ВОЛНА, которая растёт и катится вперёд (не наводится на плот).
local function fireFrost(ship)
	if ship:GetAttribute("_Frosting") then return end
	local base = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true)
	if not base then return end
	local front = ship:FindFirstChild(FROST_MUZZLE_NAME, true)
	if not (front and front:IsA("BasePart")) then return end
	local head = front.Parent -- MeshPart-голова (Front лежит внутри неё)
	local canSweep = head and head:IsA("BasePart") and head:IsDescendantOf(ship) and head ~= base
	ship:SetAttribute("_Frosting", true)

	local raft = workspace:FindFirstChild("Raft")
	local waterY = (raft and raft.PrimaryPart and raft.PrimaryPart.Position.Y) or (front.Position.Y - 8)
	local fwd = shipForward(ship) -- стабильный «перёд» (не дёргается от качания головы)

	CombatSounds.play("frostBreath", front.Position) -- звук морозного выдоха

	task.spawn(function()
		-- поза головы относительно корпуса (жёсткая связка — chaseLoop каждый кадр ставит
		-- head = base.CFrame * headLocal; мы поверх добавляем поворот качания)
		local headLocal = canSweep and base.CFrame:ToObjectSpace(head.CFrame) or nil
		local breath, emit = makeFrostBreath()

		local volley = { hitRaft = false }               -- урон плоту — один раз на весь залп
		local nextIcicle = FROST_BREATH_TIME * 0.15       -- первую сосульку — чуть погодя (туман должен «дойти»)
		local iceCount = 0
		local t = 0
		while ship.Parent and not ship:GetAttribute("Dead") and t < FROST_BREATH_TIME do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			local phase = (t / FROST_BREATH_TIME) * FROST_SWEEP_CYCLES * math.pi * 2
			local yaw   = FROST_SWEEP_YAW * math.sin(phase)
			local pitch = FROST_SWEEP_PITCH * math.sin(phase * 2) -- двойная частота → кривая, задевает верх/низ

			-- крутим саму голову (применяем ПОСЛЕ PivotTo корабля → наш поворот побеждает)
			if canSweep then
				pcall(function()
					head.CFrame = (base.CFrame * headLocal) * CFrame.Angles(pitch, yaw, 0)
				end)
			end

			-- струя выдоха качается вместе с головой: целим в воду перед головой, повёрнутую на yaw
			local headPos = front.Position
			local sweptFwd = (CFrame.fromAxisAngle(Vector3.yAxis, yaw) * fwd)
			local aim = Vector3.new(headPos.X + sweptFwd.X * FROST_BREATH_AHEAD, waterY, headPos.Z + sweptFwd.Z * FROST_BREATH_AHEAD)
			breath.CFrame = CFrame.lookAt(headPos, aim)

			-- ПОСТЕПЕННО, по мере касания тумана воды, из-под воды рождаются сосульки. Спавним в
			-- точке касания (aim, качается со струёй), а летят они ПРЯМО вперёд от корабля (fwd).
			if iceCount < FROST_ICICLE_MAX and t >= nextIcicle and t <= FROST_BREATH_TIME * 0.95 then
				nextIcicle = nextIcicle + FROST_ICICLE_INTERVAL
				iceCount = iceCount + 1
				launchIcicle(aim, fwd, waterY, volley)
			end
		end

		emit.Enabled = false
		Debris:AddItem(breath, 1.3)
		-- вернуть голову в нейтраль (чтобы дальше PivotTo вёл её без рывка)
		if canSweep then
			pcall(function() head.CFrame = base.CFrame * headLocal end)
		end
		ship:SetAttribute("_Frosting", nil)
	end)
end

-- (ледяные диски frostTrail УДАЛЕНЫ: корабль почти стоит на позиции, и диски копились
-- кругами друг на друге. Ледяной след теперь — синий кильватер, см. makeWake.)

local function shipFireLoop(ship)
	local magma = isMagmaShip(ship)
	local frost = isFrostShip(ship)
	while ship.Parent and not ship:GetAttribute("Dead") do
		task.wait(SHIP_FIRE_INTERVAL + math.random() * 2)
		if not ship.Parent or ship:GetAttribute("Dead") then break end
		local raft = workspace:FindFirstChild("Raft")
		local rp = raft and raft.PrimaryPart
		local from = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true)
		if rp and from and (rp.Position - from.Position).Magnitude <= SHIP_FIRE_RANGE then
			if magma then fireMagmaAtRaft(ship)
			elseif frost then fireFrost(ship)
			else fireAtRaft(ship) end
		end
	end
end

-- ── floating HP bar above a ship ──
local function setupHealthBar(ship)
	if ship:GetAttribute("_HealthBar") then return end
	local base = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart", true) -- recursive: parts may be nested
	if not base then return end
	ship:SetAttribute("_HealthBar", true)

	local cf, size = ship:GetBoundingBox()
	local maxHP = math.max(ship:GetAttribute("MaxHP") or SHIP_HP, 1)
	local level = math.clamp(math.floor(ship:GetAttribute("ShipLevel") or 1), 1, 5)
	local hb = EnemyHealthBar.new({
		name = (isMagmaShip(ship) and "МАГМА-КОРАБЛЬ") or (isFrostShip(ship) and "ЛЕДЯНОЙ КОРАБЛЬ") or "ПИРАТСКИЙ КОРАБЛЬ",
		maxHp = maxHP,
		cur = ship:GetAttribute("HP") or maxHP,
		difficulty = level, -- звёзды = уровень корабля (1..5)
		maxDistance = 800,
	})
	hb.gui.Name = "ShipHealthBar" -- destroyShip ищет бар по этому имени
	hb.gui.StudsOffsetWorldSpace = (cf.Position - base.Position) + Vector3.new(0, size.Y / 2 + 3, 0)
	hb.gui.Parent = base

	local function update()
		hb.setHP(ship:GetAttribute("HP") or 0, math.max(ship:GetAttribute("MaxHP") or 1, 1))
	end
	ship:GetAttributeChangedSignal("HP"):Connect(update)
	ship:GetAttributeChangedSignal("MaxHP"):Connect(update)
	update()
end

-- Terrain water is flat, so its surface Y is constant — find it ONCE and cache it. Reusing
-- the cache means a floating log/leaf the ray happens to hit can never make the wake jump up.
local wakeWaterY = nil
local function wakeSurfaceY(x, z, fallback, ignore)
	if wakeWaterY then return wakeWaterY end
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, fallback + 120, z), Vector3.new(0, -500, 0), params)
	if res and res.Material == Enum.Material.Water then
		wakeWaterY = res.Position.Y
		return wakeWaterY
	end
	return fallback
end

-- Классический кильватер: две плоские ленты (порт + штирборт), тянущиеся за кормой и
-- изгибающиеся в поворотах. Цвет — по типу корабля: обычные оставляют белую пену,
-- ЛЕДЯНОЙ — синюю (вместо прежних ледяных дисков frostTrail, копившихся кругами).
-- Чейз-луп прижимает этот парт к КОРМЕ на поверхности воды каждый кадр.
local WAKE_COLOR_NORMAL = Color3.fromRGB(255, 255, 255) -- обычные корабли: белая пена
local WAKE_COLOR_FROST  = Color3.fromRGB(110, 180, 235) -- ледяной корабль: синий след

local function makeWake(color)
	local part = Instance.new("Part")
	part.Name = "ShipWake"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = workspace

	local SIDE, W = 2, 0.6 -- ленты у самого киля, узкие → лёгкая двойная дорожка
	for _, sign in ipairs({ -1, 1 }) do
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(sign * SIDE - W, 0, 0); a0.Parent = part
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(sign * SIDE + W, 0, 0); a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 1.6          -- короткие ленты (не длиннее корабля)
		trail.MinLength = 0
		trail.FaceCamera = false      -- лежат ПЛОСКО на воде, не крутятся за камерой
		trail.LightEmission = 0.1     -- едва подсвечены, без свечения
		trail.Color = ColorSequence.new(color or WAKE_COLOR_NORMAL)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),   -- лёгкая пена у кормы
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(1, 1),     -- растворяется
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		trail.Parent = part
	end
	return part
end

-- the raft's bow direction (horizontal). BoatMovement writes RestYaw each heartbeat; the bow at
-- yaw Y projects to (-sin Y, 0, -cos Y). Falls back to the PrimaryPart's facing.
local function getRaftFront(raft)
	local pp = raft and raft.PrimaryPart
	if not pp then return Vector3.new(0, 0, -1) end
	local yaw = pp:GetAttribute("RestYaw")
	if yaw then
		return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	end
	local lv = pp.CFrame.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	return (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
end

-- ── chase: each ship faces the raft and stations in front of it at bombard range ──
local function chaseLoop(ship)
	if ship:GetAttribute("_Chase") then return end
	ship:SetAttribute("_Chase", true)
	task.spawn(function()
		local wake = makeWake(isFrostShip(ship) and WAKE_COLOR_FROST or WAKE_COLOR_NORMAL)
		local _, bsize = ship:GetBoundingBox()
		local sternOffset = math.max(bsize.X, bsize.Z) * 0.2 -- modest: start near the hull, not way behind the wide sails
		local shipHalfLen = math.max(bsize.X, bsize.Z) * 0.5 -- hull half-extent → hold the HULL (not the pivot) off the raft
		while ship.Parent and not ship:GetAttribute("Dead") do
			local dt = RunService.Heartbeat:Wait()
			local raft = workspace:FindFirstChild("Raft")
			local rp = raft and raft.PrimaryPart
			if rp then
				local pivot = ship:GetPivot()
				local pos = pivot.Position
				local center = _G.GetRaftCenter() or rp.Position -- aim at the raft's centre, not a corner part
				local flat = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
				local dist = flat.Magnitude
				local want = (dist > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
				-- the hull's actual heading, flattened. Ледяной корабль плывёт НОСОМ (головой)
				-- вперёд: у него нет "Cannon", а PrimaryPart смотрит вбок, поэтому «перёд»
				-- берём по голове (shipForward, через кэшированный угол _FrostFwdYaw).
				local shipFwd
				if isFrostShip(ship) then
					shipFwd = shipForward(ship)
				else
					local cannon = ship:FindFirstChild("Cannon", true)
					local cf = (cannon and cannon:IsA("BasePart")) and cannon:GetPivot() or pivot
					shipFwd = cannonForward(ship, cf)
				end
				shipFwd = Vector3.new(shipFwd.X, 0, shipFwd.Z)
				shipFwd = (shipFwd.Magnitude > 0.01) and shipFwd.Unit or want
				if dist > 0.5 then
					-- face the raft (cannon trained on it), capped turn rate
					local ang = math.atan2(shipFwd:Cross(want).Y, shipFwd:Dot(want))
					local turn = math.clamp(ang, -SHIP_TURN_RATE * dt, SHIP_TURN_RATE * dt)
					-- STATION-KEEP IN FRONT OF THE RAFT: aim for a point STANDOFF studs off the raft's
					-- bow and hold there. As the raft sails forward that point moves with it, so the ship
					-- backs off to stay ahead at range instead of being rammed (it out-runs the raft).
					local raftFwd = getRaftFront(raft)
					-- hold the ship's HULL a fixed gap off the raft's EDGE (scales with raft & ship size)
					local raftRadius = (_G.GetRaftRadius and _G.GetRaftRadius()) or 14
					local holdDist = raftRadius + shipHalfLen + SHIP_STANDOFF_GAP
					local target = center + raftFwd * holdDist
					local toTarget = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
					local d = toTarget.Magnitude
					local newPos = pos
					if d > 0.01 then
						local step = math.min(SHIP_CHASE_SPEED * dt, d) -- never overshoot the station
						-- ОБХОД ОСТРОВОВ: если прямой путь к станции упирается в сушу острова,
						-- рулевой довернёт курс, и корабль обойдёт остров, а не протаранит его.
						-- Смотрим вперёд на корпус + запас; своё (корабль/плот) исключаем.
						local moveDir = WaterSpawn.steer(pos, toTarget.Unit, shipHalfLen + 40, { ship, raft })
						newPos = pos + moveDir * step
					end
					-- never cut ACROSS the raft on the way to the bow station: the straight line
					-- from the spawn side can pass right beside (or over) the deck. Keep the hull
					-- outside the hold ring at all times — pushed back onto the ring, the ship
					-- slides AROUND the raft to its station instead of through it.
					local off = Vector3.new(newPos.X - center.X, 0, newPos.Z - center.Z)
					if off.Magnitude < holdDist then
						local out = (off.Magnitude > 0.01) and off.Unit or -raftFwd
						newPos = Vector3.new(center.X, 0, center.Z) + out * holdDist
					end
					newPos = Vector3.new(newPos.X, pos.Y, newPos.Z) -- hold its float height
					pcall(function()
						ship:PivotTo(CFrame.new(newPos) * CFrame.fromAxisAngle(Vector3.yAxis, turn) * pivot.Rotation)
					end)
				end
				-- pin the twin wake to the STERN, on the (cached, flat) water surface, aligned
				-- with the hull so the two bands stream straight back and bend through turns
				local sp = ship:GetPivot().Position
				local wy = wakeSurfaceY(sp.X, sp.Z, sp.Y, { ship, wake, raft }) + 0.3
				local sternPos = Vector3.new(sp.X, wy, sp.Z) - shipFwd * sternOffset
				wake.CFrame = CFrame.lookAt(sternPos, sternPos + shipFwd)
			end
		end
		wake:Destroy()
	end)
end

-- ── register ships ──
local function register(d)
	if not isEnemyShip(d) then return end
	setupShip(d)
	setupHealthBar(d)
	chaseLoop(d)
	if not d:GetAttribute("_FireLoop") then
		d:SetAttribute("_FireLoop", true)
		task.spawn(function() shipFireLoop(d) end)
	end
end
workspace.DescendantAdded:Connect(register)
for _, d in ipairs(workspace:GetDescendants()) do
	register(d)
end

-- ── spawner: send attackers in from a random side, capped at SHIP_MAX_ACTIVE ──
local function isEnemyShipModel(m)
	return m:IsA("Model") and isEnemyShip(m) and not m:GetAttribute("Dead")
end
local function enemyShipCount()
	local n = 0
	for _, m in ipairs(workspace:GetDescendants()) do
		if isEnemyShipModel(m) then n += 1 end
	end
	return n
end
local function shipTemplates() -- every enemy-ship model anywhere in ReplicatedStorage (regular + Magma_Ship)
	local out = {}
	for _, c in ipairs(ReplicatedStorage:GetDescendants()) do
		if c:IsA("Model") and isEnemyShip(c) then table.insert(out, c) end
	end
	return out
end
-- a horizontal unit direction. With dirOverride → that side (plus a little angular jitter so a
-- multi-enemy wave fans out instead of stacking); without → a fully random side (old behaviour).
local function waveSideDir(dirOverride, spread)
	if dirOverride then
		local base = Vector3.new(dirOverride.X, 0, dirOverride.Z)
		if base.Magnitude > 0.05 then
			base = base.Unit
			local j = (math.random() - 0.5) * (spread or 0)
			local c, s = math.cos(j), math.sin(j)
			return Vector3.new(base.X * c - base.Z * s, 0, base.X * s + base.Z * c)
		end
	end
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local warnedNoTemplate = false
-- onlyFrost: секретная волна из настроек (код 67) — только ледяные корабли
local function spawnAttacker(dirOverride, hpMult, onlyFrost)
	local raft = workspace:FindFirstChild("Raft")
	local rp = raft and raft.PrimaryPart
	if not rp then return end
	local templates = shipTemplates()
	if onlyFrost then
		local frost = {}
		for _, t in ipairs(templates) do
			if isFrostShip(t) then table.insert(frost, t) end
		end
		if #frost == 0 then
			warn("[ShipCombat] ледяного корабля (" .. FROST_SHIP_PREFIX .. "*) нет в ReplicatedStorage — секретная волна пуста")
			return
		end
		templates = frost
	end
	if #templates == 0 then
		if not warnedNoTemplate then
			warnedNoTemplate = true
			warn("[ShipCombat] no enemy-ship templates in ReplicatedStorage (Ship_enemy*/Magma_Ship* models, or an EnemyShips folder) — can't spawn attackers")
		end
		return
	end
	local ship = templates[math.random(1, #templates)]:Clone()
	for _, a in ipairs({ "_Floated", "_FireLoop", "_HealthBar", "_Chase", "Dead", "_Burning", "HP", "MaxHP", "CrateNight" }) do
		ship:SetAttribute(a, nil) -- clear runtime state so register() sets it up fresh
	end
	-- stamp this night's HP multiplier BEFORE parenting so setupShip (fired via DescendantAdded,
	-- possibly deferred) reads it race-free when it initialises the ship's HP/MaxHP
	ship:SetAttribute("HPScale", hpMult or 1)
	if ship:IsA("Model") and not ship.PrimaryPart then
		ship.WorldPivot = CFrame.new(ship:GetBoundingBox().Position)
	end
	local authoredY = ship:GetPivot().Position.Y -- keep the template's OWN float height (not the raft's)
	local center = _G.GetRaftCenter() or rp.Position -- spawn around the raft's centre, not a corner part
	local dir = waveSideDir(dirOverride, 0.5)
	-- НЕ спавним корабль на суше острова: чистая вода в стороне шторма, иначе ближайшая
	local xz = WaterSpawn.pick(center, dir, SHIP_SPAWN_DIST, authoredY + 80, { rp.Parent })
	local spawnPos = Vector3.new(xz.X, authoredY, xz.Z)
	print(("[WaveDebug] ship: center=(%.0f, %.0f) spawn=(%.0f, %.0f) dir=(%.2f, %.2f)"):format(
		center.X, center.Z, spawnPos.X, spawnPos.Z, dir.X, dir.Z))
	pcall(function() ship:PivotTo(CFrame.lookAt(spawnPos, Vector3.new(center.X, authoredY, center.Z))) end)
	ship.Parent = workspace -- DescendantAdded → register() sets it up + starts its chase/fire loops
	return ship -- WaveDirector tracks wave participants until they're all dead
end

local SHIP_SPAWN_ENABLED = false -- TEMP: enemy ships OFF (set true to re-enable)
task.spawn(function()
	while true do
		task.wait(SHIP_SPAWN_INTERVAL)
		if SHIP_SPAWN_ENABLED and enemyShipCount() < SHIP_MAX_ACTIVE then
			spawnAttacker()
		end
	end
end)

-- wave control: WaveDirector spawns a ship on demand from a chosen side (continuous loop above stays off)
_G.SpawnEnemyShip = function(dir, hpMult, onlyFrost) return spawnAttacker(dir, hpMult, onlyFrost) end

-- expose the coin drop so other systems (e.g. swimming pirates) can drop Pirate coins too
_G.SpawnPirateCoins = function(origin, firer, n, burstDir, opts)
	if firer then spawnCoins(origin, firer, n or 1, burstDir, opts) end
end

-- The raft's true CENTRE (bounding-box centre) — enemies should aim at THIS, not the
-- PrimaryPart (which sits on one Raft_part and drifts off-centre as you build, so everything
-- funnels to that corner). Cached as a local offset from the PrimaryPart, refreshed every
-- 0.5s → cheap per frame, tracks the moving raft, and updates when you build. Shared with
-- SwimmingPirate via _G.
local raftCtrOffset, raftRad, raftSize, raftCtrAt = nil, 14, Vector3.new(24, 4, 24), 0
local function refreshRaftBox()
	local r = workspace:FindFirstChild("Raft")
	local rpp = r and r.PrimaryPart
	if not rpp then return nil end
	if not raftCtrOffset or os.clock() - raftCtrAt > 0.5 then
		-- box of the REAL raft only: Raft_part pieces that are still PHYSICALLY WELDED into the
		-- raft's assembly, at deck height. The model also collects strays (broken-off/sunken/
		-- drifted-away pieces) that keep the Raft_part name but are no longer attached — a raw
		-- GetBoundingBox stretched over them, dragging the "centre" into open water and inflating
		-- the spawn radius, so night waves spawned and attacked in the wrong place.
		local root = rpp.AssemblyRootPart or rpp
		local ppY = rpp.Position.Y
		local x1, y1, z1 = math.huge, math.huge, math.huge
		local x2, y2, z2 = -math.huge, -math.huge, -math.huge
		local found = false
		local function take(p)
			if p:IsA("BasePart") and p.CanCollide and p.Transparency < 0.5
				and p.AssemblyRootPart == root and math.abs(p.Position.Y - ppY) < 6 then
				-- world AABB of the ORIENTED part — the raft's yaw is arbitrary while sailing
				local cf, h = p.CFrame, p.Size * 0.5
				local rx = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
				local ry = math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z
				local rz = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
				local pos = p.Position
				x1 = math.min(x1, pos.X - rx); x2 = math.max(x2, pos.X + rx)
				y1 = math.min(y1, pos.Y - ry); y2 = math.max(y2, pos.Y + ry)
				z1 = math.min(z1, pos.Z - rz); z2 = math.max(z2, pos.Z + rz)
				found = true
			end
		end
		for _, c in ipairs(r:GetChildren()) do
			if c.Name == "Raft_part" then
				if c:IsA("BasePart") then
					take(c)
				else
					for _, p in ipairs(c:GetDescendants()) do take(p) end
				end
			end
		end
		local ctr, size
		if found then
			ctr = Vector3.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2)
			size = Vector3.new(x2 - x1, y2 - y1, z2 - z1)
		else -- no deck parts matched → fall back to the old whole-model box
			local cf, s = r:GetBoundingBox()
			ctr, size = cf.Position, s
		end
		raftCtrOffset = rpp.CFrame:PointToObjectSpace(ctr)
		raftRad = math.max(size.X, size.Z) * 0.5 -- recompute as the raft is built bigger
		raftSize = size
		raftCtrAt = os.clock()
	end
	return rpp
end
_G.GetRaftCenter = function()
	local rpp = refreshRaftBox()
	return rpp and rpp.CFrame:PointToWorldSpace(raftCtrOffset)
end
_G.GetRaftRadius = function()
	refreshRaftBox()
	return raftRad
end
-- The closest point on the raft's ACTUAL deck pieces (every Raft_part) to fromPos — enemies
-- head HERE, so they meet the nearest edge of the whole built raft (any shape, including
-- pieces you just placed) instead of one fixed part. Part list cached + refreshed every 0.5s.
local raftPieces, raftPiecesAt = {}, 0
_G.GetRaftNearestPoint = function(fromPos)
	local r = workspace:FindFirstChild("Raft")
	local rpp = r and r.PrimaryPart
	if not rpp then return nil end
	if #raftPieces == 0 or os.clock() - raftPiecesAt > 0.5 then
		raftPieces = {}
		-- Raft_part entries are MODELS of parts — collect their collidable parts, and only ones
		-- still welded into the raft's assembly (broken-off strays keep the name but drift away)
		local root = rpp.AssemblyRootPart or rpp
		local function take(p)
			if p:IsA("BasePart") and p.CanCollide and p.AssemblyRootPart == root then
				table.insert(raftPieces, p)
			end
		end
		for _, c in ipairs(r:GetChildren()) do
			if c.Name == "Raft_part" then
				if c:IsA("BasePart") then
					take(c)
				else
					for _, p in ipairs(c:GetDescendants()) do take(p) end
				end
			end
		end
		raftPiecesAt = os.clock()
	end
	local best, bestD
	for _, p in ipairs(raftPieces) do
		if p.Parent then
			local lp = p.CFrame:PointToObjectSpace(fromPos)
			local h = p.Size * 0.5
			local wp = p.CFrame:PointToWorldSpace(Vector3.new(
				math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z)))
			local d = (wp - fromPos).Magnitude
			if not bestD or d < bestD then best, bestD = wp, d end
		end
	end
	return best -- nil if no Raft_part → caller falls back to the centre
end
