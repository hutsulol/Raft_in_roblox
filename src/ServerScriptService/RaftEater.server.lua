-- RaftEater.server.lua
-- "Zombie_Eater": a PvZ-style raft muncher. It spawns near the raft and swims toward it with REAL
-- physics (CanCollide = true), so it physically stops at the raft instead of teleporting to an
-- imagined point. Once its body touches the raft it welds on at that real contact and gnaws —
-- Eat_Raft every EAT_INTERVAL with Idle between — riding the moving raft. On death it ragdolls,
-- gets knocked back away from the shooter, floats on the water, then is cleared.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local EnemyHealthBar    = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))
local WaterSpawn        = require(ReplicatedStorage:WaitForChild("WaterSpawn"))
local AssetFind         = require(ReplicatedStorage:WaitForChild("AssetFind"))

local TEMPLATE          = "Zombie_Eater"
local SPAWN_INTERVAL    = 30     -- seconds between spawns
local MAX_ACTIVE        = 1      -- cap on live eaters
local SPAWN_MARGIN      = 100    -- how far BEYOND the raft's edge they surface (было 16 — спавнились вплотную)
local SWIM_Y_OFFSET     = 0.3    -- float height above the water surface
local SWIM_SPEED        = 12     -- swim velocity toward the raft: чуть быстрее плота (~8 ст/с),
                                 -- чтобы догонял сзади; вода часть скорости съедает
local CONTACT_DIST      = 4      -- a Raft_part this close ahead → it has reached the raft, latch on
-- ВЫСОТЫ КОНТАКТНОГО ЛУЧА. Луч идёт от HumanoidRootPart, а тот прибит к воде
-- (SWIM_Y_OFFSET). Новая палуба стоит ВЫШЕ ватерлинии, поэтому единственный
-- горизонтальный луч на уровне воды проходил ПОД плотом и контакт не находил
-- никогда: зомби доживал до аварийной прицепки по таймауту и приваривался в
-- нескольких студах от борта — «грыз воздух», и достать его ближним боем было
-- нельзя. Бьём веером по высоте, чтобы поймать борт независимо от осадки.
local CONTACT_HEIGHTS   = { 0, 1.5, 3, 4.5 }
local LATCH_SNAP        = 14     -- в этом радиусе ищем борт, чтобы прижать зомби вплотную
local LATCH_GAP         = 1.2    -- зазор от поверхности борта: касается, но не в нём
local STUCK_TIME        = 10     -- if it can't reach the raft in this long, force-latch (safety)
local EAT_INTERVAL      = 1.5    -- a bite every this many seconds
-- УРОН ЗА УКУС РАСТЁТ ПО ДНЯМ. В первые ночи у игрока нет ни стен, ни ремонтной
-- станции, и 5 HP за укус съедали плот быстрее, чем он успевал чиниться.
-- За пределами таблицы держится последнее значение.
local EAT_DAMAGE_BY_DAY = { 2, 2, 3, 4, 5 }
local EATER_HP          = 90
local COIN_DROP         = 2      -- Pirate coins dropped when a player kills an eater
local KNOCKBACK_SPEED   = 45     -- on death the corpse is flung this fast, away from the shooter
local KNOCKBACK_UP      = 20     -- + this much upward kick
local EATER_DENSITY     = 0.45   -- < 1 so it floats on the water; light so it barely shoves the raft
local FLOAT_TIME        = 4      -- seconds the dead body floats on the water
local SINK_SPEED        = 2.5    -- studs/s the dead body settles under — gentle, not like a rock
local SINK_DEPTH        = 12     -- how far below the surface it sinks before it's removed
local SINK_MAX_TIME     = 12     -- safety: remove after this long even if it never reaches SINK_DEPTH
-- bite effect: a burst of wood chips + a crunch sound at the spot it's gnawing
local BITE_SOUNDS       = { "rbxassetid://9120802004", "rbxassetid://9120804180" } -- Roblox "Wood Break" SFX (swap if you like)
local BITE_VOLUME       = 0.5    -- crunch loudness
local CHIP_COUNT        = 5      -- wood chips flung per bite
local CHIP_LIFETIME     = 0.6    -- seconds before a chip is cleared
local CHIP_SPEED        = 14     -- how fast chips spray off the bite

-- ── helpers ──
local function eatDamage()
	local dc = ReplicatedStorage:FindFirstChild("DayCount")
	local day = math.floor((dc and dc.Value) or 1)
	return EAT_DAMAGE_BY_DAY[math.clamp(day, 1, #EAT_DAMAGE_BY_DAY)]
end

local function ensureHumanoid(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") or (hum and hum.RootPart)
	return hum, hrp
end

-- ocean surface Y under (x,z); terrain water IS detected by raycasts (Material == Water)
local function waterSurfaceAt(x, z, fallbackY, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, fallbackY + 60, z), Vector3.new(0, -240, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return fallbackY
end

local function nearestPlayer(pos)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if not bestD or d < bestD then best, bestD = plr, d end
		end
	end
	return best
end

-- a bite landed: spray a few wood chips and play a crunch, at the exact raft surface it's gnawing
local function biteEffect(model, hrp)
	local head = model:FindFirstChild("Head") or hrp
	local look = hrp.CFrame.LookVector
	-- find the raft surface just ahead of the mouth → spawn point + matching wood colour
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(head.Position, look * 3, params)
	local raft = workspace:FindFirstChild("Raft")
	local onRaft = hit and hit.Instance and raft and hit.Instance:IsDescendantOf(raft)
	local point = (onRaft and hit.Position) or (head.Position + look)
	local colour = (onRaft and hit.Instance.Color) or Color3.fromRGB(120, 80, 45)
	local material = (onRaft and hit.Instance.Material) or Enum.Material.Wood

	-- wood chips: tiny parts flung off the bite; gravity pulls them down, Debris clears them.
	-- CanQuery off so a flying chip never disturbs the eaters' own raycasts.
	for _ = 1, CHIP_COUNT do
		local chip = Instance.new("Part")
		chip.Size = Vector3.new(0.2, 0.2, 0.35) * (0.7 + math.random() * 0.8)
		chip.CFrame = CFrame.new(point) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.Color = colour
		chip.Material = material
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		local spray = (-look + Vector3.new(0, 1.2, 0) + Vector3.new(math.random() - 0.5, math.random(), math.random() - 0.5)).Unit
		chip.AssemblyLinearVelocity = spray * CHIP_SPEED * (0.6 + math.random() * 0.8)
		chip.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		chip.Parent = workspace
		Debris:AddItem(chip, CHIP_LIFETIME)
	end

	-- crunch: positional sound at the bite, pitch varied so repeats don't sound identical
	local snd = Instance.new("Sound")
	snd.SoundId = BITE_SOUNDS[math.random(#BITE_SOUNDS)]
	snd.Volume = BITE_VOLUME
	snd.PlaybackSpeed = 0.9 + math.random() * 0.25
	snd.RollOffMaxDistance = 70
	snd.Parent = head
	snd:Play()
	Debris:AddItem(snd, 3)
end

-- load the model's named animation tracks (Eat_Raft / Idle / Swim) onto its Animator
local function loadTracks(hum, model)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = hum end
	local tracks = {}
	local want = { eat = "eat_raft", idle = "idle", swim = "swim" }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") then
			local nm = d.Name:lower()
			for key, want_nm in pairs(want) do
				if nm == want_nm and not tracks[key] then
					local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
					if ok and tr then tracks[key] = tr end
				end
			end
		end
	end
	if tracks.eat then tracks.eat.Priority = Enum.AnimationPriority.Action end
	if tracks.idle then tracks.idle.Priority = Enum.AnimationPriority.Idle end
	if tracks.swim then tracks.swim.Priority = Enum.AnimationPriority.Movement end
	return tracks
end

local function setupHealthBar(model, hum, hrp)
	local head = model:FindFirstChild("Head") or hrp
	if not head then return end
	local hb = EnemyHealthBar.new({
		name = "ЗОМБИ-ПОЖИРАТЕЛЬ",
		maxHp = math.max(hum.MaxHealth, 1),
		cur = hum.Health,
		difficulty = 2,
		surface = true, -- SurfaceGui: масштабируется с расстоянием (не раздувается издалека)
	})
	-- код смерти ищет бар по имени "EaterHP" (model:FindFirstChild) — attach варит парт в модель
	hb.attach(head, 2.2, "EaterHP")
	hum.HealthChanged:Connect(function(h)
		hb.setHP(h, hum.MaxHealth)
	end)
end

-- rig for physics: ALL parts collide (so it can't pass through the raft) and are light enough to
-- float; the Humanoid state machine is off so it doesn't fight us — we drive it by velocity.
local function setupRig(model)
	local hum, hrp = ensureHumanoid(model)
	if not hum or not hrp then return nil, nil end
	hrp = hum.RootPart or hrp
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true -- REAL collision: it stops at the raft instead of passing through
			d.Massless = false
			d.CustomPhysicalProperties = PhysicalProperties.new(EATER_DENSITY, 0.3, 0.5)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
	pcall(function() model.PrimaryPart = hrp end)
	hum.EvaluateStateMachine = false
	hum.AutoRotate = false
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false) end)
	hum.MaxHealth = EATER_HP; hum.Health = EATER_HP
	model:SetAttribute("WaterImmune", true) -- ToxicWater ignores it (it lives in the sea)
	return hum, hrp
end

-- ── per-eater AI ──
local function runEater(model, waterY)
	local hum, hrp = setupRig(model)
	if not hum or not hrp then model:Destroy(); return end
	setupHealthBar(model, hum, hrp)
	local tracks = loadTracks(hum, model)
	local weld -- the raft weld while latched; destroyed on death so the corpse drops

	local function raft() return workspace:FindFirstChild("Raft") end
	local function alive() return model.Parent and hum.Health > 0 end
	local function raftCenter()
		local r = raft()
		return (_G.GetRaftCenter and _G.GetRaftCenter()) or (r and r.PrimaryPart and r.PrimaryPart.Position)
	end
	-- a Raft_part within CONTACT_DIST straight ahead (toward `dir`)? → its body is up against the raft
	local function raftAhead(dir)
		local r = raft()
		if not r then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		-- веер по высоте: борт может оказаться и вровень с водой, и заметно выше её
		for _, dy in ipairs(CONTACT_HEIGHTS) do
			local origin = hrp.Position + Vector3.new(0, dy, 0)
			local res = workspace:Raycast(origin, dir * CONTACT_DIST, params)
			if res and res.Instance and res.Instance:IsDescendantOf(r) then
				return res.Position
			end
		end
		return nil
	end

	-- ТОЧКА НА ПОВЕРХНОСТИ БЛИЖАЙШЕГО БОРТА.
	-- Куда бы ни сработала прицепка — по контакту или по аварийному таймауту —
	-- перед сваркой зомби прижимается ВПЛОТНУЮ к настоящему борту. Иначе он
	-- застывал там, где его застало условие, то есть в паре студов от плота:
	-- визуально грыз воду, и ни топором, ни другим ближним оружием его было не
	-- достать. Точку берём на грани парта, а не в его центре, чтобы работало и с
	-- повёрнутыми деталями.
	local function nearestRaftSurface()
		local r = raft()
		if not r then return nil end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { r }
		local bestPoint, bestD
		for _, p in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, LATCH_SNAP, params)) do
			local lp = p.CFrame:PointToObjectSpace(hrp.Position)
			local h = p.Size * 0.5
			local clamped = Vector3.new(
				math.clamp(lp.X, -h.X, h.X),
				math.clamp(lp.Y, -h.Y, h.Y),
				math.clamp(lp.Z, -h.Z, h.Z)
			)
			local world = p.CFrame:PointToWorldSpace(clamped)
			local d = (world - hrp.Position).Magnitude
			if not bestD or d < bestD then bestPoint, bestD = world, d end
		end
		return bestPoint
	end
	-- есть ли парт плота в радиусе? СТРАХОВОЧНАЯ прицепка по таймауту разрешена ТОЛЬКО
	-- вплотную к плоту — иначе зомби, не доплыв (дальний спавн/убегающий плот), приваривался
	-- К ПУСТОТЕ посреди океана и «грыз» плот дистанционно
	local function nearRaft(maxDist)
		local r = raft()
		if not r then return false end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { r }
		return #workspace:GetPartBoundsInRadius(hrp.Position, maxDist or 8, params) > 0
	end

	local current
	local function play(track, looped)
		if not track or current == track then return end
		if current then current:Stop(0.2) end
		current = track
		track.Looped = looped ~= false
		track:Play(0.2)
	end

	task.spawn(function()
		-- 1) SWIM toward the raft by VELOCITY (physics) until it physically touches a Raft_part. It
		-- can't pass through (CanCollide), so it stops at the real surface — no imagined point.
		play(tracks.swim or tracks.idle, true)
		local t0 = os.clock()
		while alive() do
			RunService.Heartbeat:Wait()
			local center = raftCenter()
			if not center then break end
			local to = Vector3.new(center.X - hrp.Position.X, 0, center.Z - hrp.Position.Z)
			local dir = (to.Magnitude > 0.01) and to.Unit or hrp.CFrame.LookVector
			-- обход островов: не плывём сквозь сушу — рулевой доворачивает курс
			dir = WaterSpawn.steer(hrp.Position, dir, 18, { model, raft() })
			-- прицепка: коснулся плота, ЛИБО застрял у самого борта дольше STUCK_TIME
			-- (таймаут БЕЗ близости больше не цепляет — плывём дальше, скорость выше плота)
			if raftAhead(dir) or (os.clock() - t0 > STUCK_TIME and nearRaft(8)) then break end
			-- PIN it to the surface so it can never slip under the raft; drive horizontally and let
			-- CanCollide stop it at the raft. Setting Y here keeps it exactly on top of the water.
			local p = Vector3.new(hrp.Position.X, waterY, hrp.Position.Z)
			hrp.CFrame = CFrame.lookAt(p, p + dir)
			-- АДАПТИВНАЯ СКОРОСТЬ: постоянное СБЛИЖЕНИЕ независимо от манёвров плота
			-- (весло разворачивает его в любой момент): плот навстречу → зомби медленнее,
			-- плот убегает → быстрее (в пределах).
			local speed = SWIM_SPEED
			local rpB = raft() and raft().PrimaryPart
			if rpB then
				local rv = rpB.AssemblyLinearVelocity
				speed = math.clamp(SWIM_SPEED + Vector3.new(rv.X, 0, rv.Z):Dot(dir), 4, 18)
			end
			hrp.AssemblyLinearVelocity = Vector3.new(dir.X * speed, 0, dir.Z * speed)
		end
		if not alive() then return end

		-- 2) LATCH: stop, face the raft, and WELD at this REAL contact spot so it rides the moving raft
		local rp = raft() and raft().PrimaryPart
		if rp then
			local center = raftCenter() or rp.Position
			local dir = Vector3.new(center.X - hrp.Position.X, 0, center.Z - hrp.Position.Z)
			dir = (dir.Magnitude > 0.01) and dir.Unit or hrp.CFrame.LookVector
			-- ПРИЖИМАЕМ К БОРТУ перед сваркой: встаём в LATCH_GAP от найденной точки
			-- поверхности, со стороны воды. Высоту оставляем на ватерлинии — зомби
			-- плавающий, а не забирающийся на палубу.
			local surf = nearestRaftSurface()
			if surf then
				local snapped = surf - dir * LATCH_GAP
				hrp.CFrame = CFrame.lookAt(
					Vector3.new(snapped.X, waterY, snapped.Z),
					Vector3.new(snapped.X, waterY, snapped.Z) + dir)
			else
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = hrp, rp
			weld.Parent = hrp
			-- Once welded, the eater must NOT disturb the force-driven raft: make it MASSLESS (adds
			-- no mass/buoyancy to the raft assembly) and non-colliding (the weld holds it), and hand
			-- its physics to the server. Otherwise its buoyancy/mass fights BoatMovement's buoyancy
			-- spring and the raft bounces / flies off.
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Massless = true
					d.CanCollide = false
				end
			end
			pcall(function() hrp:SetNetworkOwner(nil) end)
		end

		-- 3) EAT: gnaw in place (the weld holds it on the raft) — an Eat_Raft bite every
		-- EAT_INTERVAL, Idle in between
		local eatLen = (tracks.eat and tracks.eat.Length > 0.1) and tracks.eat.Length or 0.8
		local biteAt, biting = os.clock() - EAT_INTERVAL, false -- first bite right away
		play(tracks.idle or tracks.swim, true)
		while alive() do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			if not biting and now - biteAt >= EAT_INTERVAL then
				biting, biteAt = true, now
				play(tracks.eat or tracks.idle, false) -- a bite
				if _G.DamageRaft then _G.DamageRaft(eatDamage()) end
				biteEffect(model, hrp) -- wood chips + crunch at the gnaw spot
			elseif biting and now - biteAt >= eatLen then
				biting = false
				play(tracks.idle or tracks.swim, true) -- idle until the next bite
			end
		end
	end)

	-- death: hide the HP bar, unweld, ragdoll, and fling the corpse AWAY from the shooter; it then
	-- floats on the water (buoyancy) and is cleared after a few seconds. Guarded so it fires once.
	local dead = false
	hum.HealthChanged:Connect(function(h)
		if h > 0 or dead then return end
		dead = true
		local bar = model:FindFirstChild("EaterHP")
		if bar then bar:Destroy() end -- HP bar gone the moment it dies
		if weld then weld:Destroy() end -- detach from the raft
		if _G.SpawnPirateCoins then -- drop Pirate coins for the killer (like swimming pirates)
			_G.SpawnPirateCoins(hrp.Position, nearestPlayer(hrp.Position), COIN_DROP)
		end
		-- restore mass so the corpse falls/sinks normally, but keep collision OFF so the dead body
		-- never shoves the raft on its way down
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Massless = false; d.CanCollide = false end
		end
		pcall(function() hum.PlatformStand = true end) -- the Humanoid no longer controls the body
		local animator = hum:FindFirstChildOfClass("Animator") -- drop the animation pose
		if animator then for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end end
		-- RAGDOLL: swap the limb joints for free ball sockets (kept the HRP↔Torso joint as the rigid
		-- core), so the limbs stay attached but swing on their own from the knockback's inertia
		for _, m in ipairs(model:GetDescendants()) do
			if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Part0 ~= hrp and m.Part1 ~= hrp then
				local a0 = Instance.new("Attachment"); a0.CFrame = m.C0; a0.Parent = m.Part0
				local a1 = Instance.new("Attachment"); a1.CFrame = m.C1; a1.Parent = m.Part1
				local bs = Instance.new("BallSocketConstraint"); bs.Attachment0, bs.Attachment1 = a0, a1; bs.Parent = m.Part0
				local ncc = Instance.new("NoCollisionConstraint"); ncc.Part0, ncc.Part1 = m.Part0, m.Part1; ncc.Parent = m.Part0
				m:Destroy()
			end
		end
		pcall(function() -- knockback: fling the core AWAY from the shooter + a tumble; limbs lag → flop
			local plr = nearestPlayer(hrp.Position)
			local src = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			local away = src and (hrp.Position - src.Position) or hrp.CFrame.LookVector * -1
			away = Vector3.new(away.X, 0, away.Z)
			away = (away.Magnitude > 0.01) and away.Unit or Vector3.new(0, 0, 1)
			hrp.AssemblyLinearVelocity = away * KNOCKBACK_SPEED + Vector3.new(0, KNOCKBACK_UP, 0)
			hrp.AssemblyAngularVelocity = Vector3.new(away.Z, 0.5, -away.X) * 7
		end)
		-- linger: float FLOAT_TIME (kept ON TOP of the water so a corpse never drifts under the
		-- raft), then settle SLOWLY under the surface and vanish
		task.spawn(function()
			local floatEnd = os.clock() + FLOAT_TIME
			while model.Parent and os.clock() < floatEnd do
				RunService.Heartbeat:Wait()
				if hrp.Position.Y < waterY then -- never let the body sink below the surface (→ under the raft)
					local v = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, 3), v.Z)
				end
			end
			if not model.Parent then return end
			-- SINK: settle UNDER slowly (not like a rock). Neutral-buoyancy density so the water no
			-- longer fights us, then drive the whole ragdoll straight down at SINK_SPEED each frame.
			-- Cleared once it's SINK_DEPTH below the surface (fully out of sight), or after SINK_MAX_TIME.
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5) end
			end
			local sinkStart = os.clock()
			while model.Parent do
				RunService.Heartbeat:Wait()
				if hrp.Position.Y <= waterY - SINK_DEPTH or os.clock() - sinkStart > SINK_MAX_TIME then break end
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						local v = d.AssemblyLinearVelocity
						d.AssemblyLinearVelocity = Vector3.new(v.X * 0.85, -SINK_SPEED, v.Z * 0.85)
					end
				end
			end
			if model.Parent then model:Destroy() end
		end)
	end)
end

-- ── spawner ──
local SPAWN_ENABLED = false -- TEMP: zombie eaters OFF (set true to re-enable)

local function activeCount()
	local n = 0
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name == TEMPLATE then n += 1 end
	end
	return n
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

local warned = false
local function spawnEater(dirOverride, hpMult)
	local r = workspace:FindFirstChild("Raft")
	local rp = r and r.PrimaryPart
	if not rp then return end
	local template = AssetFind.find(TEMPLATE)
	if not template then
		if not warned then warned = true
			warn("[RaftEater] no '" .. TEMPLATE .. "' model in ReplicatedStorage — can't spawn eaters")
		end
		return
	end
	local center = (_G.GetRaftCenter and _G.GetRaftCenter()) or rp.Position
	-- radius of the REAL welded raft (ShipCombat filters out broken-off strays); the whole-model
	-- bounding box stretches over drifted-away pieces and put spawns further out than the ships
	local rad = _G.GetRaftRadius and _G.GetRaftRadius()
	if not rad then
		local _, size = r:GetBoundingBox()
		rad = math.max(size.X, size.Z) * 0.5
	end
	local dir = waveSideDir(dirOverride, 0.6)
	-- НОРМИРУЕМ ВРЕМЯ ПОДХОДА (как у пиратов): плот навстречу → сближение быстрее → спавним
	-- дальше; плот убегает → ближе. Подход занимает ~одинаковое время с любой стороны.
	local APPROACH_TIME = 14
	local vel = rp.AssemblyLinearVelocity or Vector3.zero
	local closing = SWIM_SPEED + Vector3.new(vel.X, 0, vel.Z):Dot(Vector3.new(dir.X, 0, dir.Z).Unit)
	closing = math.max(closing, 2)
	local dist = rad + math.clamp(closing * APPROACH_TIME, 60, 280)
	-- НЕ спавним на суше острова: если точка по стороне шторма попала на остров,
	-- WaterSpawn подберёт ближайший чистый угол над открытой водой.
	local xz = WaterSpawn.pick(center, dir, dist, rp.Position.Y + 80, { r })
	local waterY = waterSurfaceAt(xz.X, xz.Z, rp.Position.Y, { r }) + SWIM_Y_OFFSET
	print(("[WaveDebug] eater: center=(%.0f, %.0f) rad=%.0f spawn=(%.0f, %.0f) dir=(%.2f, %.2f)"):format(
		center.X, center.Z, rad, xz.X, xz.Z, dir.X, dir.Z))

	local eater = template:Clone()
	eater.Name = TEMPLATE
	if eater:IsA("Model") and not eater.PrimaryPart then
		eater.WorldPivot = CFrame.new(eater:GetBoundingBox().Position)
	end
	local startPos = Vector3.new(xz.X, waterY, xz.Z)
	pcall(function() eater:PivotTo(CFrame.lookAt(startPos, Vector3.new(center.X, waterY, center.Z))) end)
	eater.Parent = workspace
	runEater(eater, waterY)
	-- tougher on later nights: WaveDirector passes an HP multiplier (the HP bar reads MaxHealth live)
	if hpMult and hpMult ~= 1 then
		local hum = eater:FindFirstChildOfClass("Humanoid") or eater:FindFirstChildWhichIsA("Humanoid", true)
		if hum then
			hum.MaxHealth = EATER_HP * hpMult
			hum.Health = hum.MaxHealth
		end
	end
	return eater -- WaveDirector tracks wave participants until they're all dead
end

task.spawn(function()
	while true do
		task.wait(SPAWN_INTERVAL)
		if SPAWN_ENABLED and activeCount() < MAX_ACTIVE then spawnEater() end
	end
end)

-- wave control: WaveDirector spawns an eater on demand from a chosen side (continuous loop above stays off)
_G.SpawnRaftEater = function(dir, hpMult) return spawnEater(dir, hpMult) end
