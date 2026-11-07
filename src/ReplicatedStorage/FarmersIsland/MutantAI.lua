--[[
	МУТАНТ ОСТРОВА ФЕРМЕРОВ — НАШ ИИ (сервер). Модель и позы — из пакета
	(GiantInfected_Farmers, MutantPoses/MutantClient внутри острова); рантайм
	пакета водил его вяло: 46 студов зрения только по прямой видимости, один удар
	раз в 2.8 с, без разбега и без отброса — «слабый и плохо атакует» (владелец).

	КЛИЕНТ ЧИТАЕТ АТРИБУТЫ (MutantClient в модели острова), здесь мы их и пишем:
	  FarmersState   Idle | Walk | Attack | Dead
	  FarmersAction  '' | Run | MutantSlam | Sweep | Backhand   (+ FarmersActionT —
	                 серверное время начала, по нему клиент считает фазу клипа и
	                 момент удара о землю для трещин)
	  HurtTime / HurtVariant / HurtStrength — вздрагивание от урона
	Тайминги ударов — те же, что в MutantPoses.timing, чтобы урон приходил в тот
	кадр, где рука доходит до цели.

	⚠️ ДВА ВОДИТЕЛЯ — БЕДА. NPCController пакета мутанта пропускает (см. правку в
	копии), а в папку Enemies его класть нельзя: подхватит PirateIslandAI.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyHealthBar = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))

local M = {}

local CFG = {
	HEALTH = 300,
	WALK = 8,          -- патруль
	RUN = 15,          -- погоня
	AGGRO = 60,        -- радиус реакции (студов)
	AGGRO_KEEP = 85,   -- пока цель ближе этого — не отпускает
	LEASH = 130,       -- дальше этого от дома не уходит: возвращается
	DWELL = { 2, 5 },  -- пауза на точке маршрута
	-- удары: длительность/момент попадания — MutantPoses (Slam 2.8/1.25, Sweep 1.85/.78,
	-- Backhand 2.15/.90 при speed 1.85/2.1/2.1)
	ATTACKS = {
		Slam     = { action = "MutantSlam", dur = 2.8 / 1.85, hit = 1.25 / 1.85, dmg = 45, reach = 9,  aoe = 11, cd = 7,   knock = 55 },
		Sweep    = { action = "Sweep",      dur = 1.85 / 2.1, hit = 0.78 / 2.1,  dmg = 28, reach = 7,  aoe = 0,  cd = 0,   knock = 25 },
		Backhand = { action = "Backhand",   dur = 2.15 / 2.1, hit = 0.90 / 2.1,  dmg = 32, reach = 7,  aoe = 0,  cd = 0,   knock = 30 },
	},
	ATTACK_GAP = 0.6,  -- пауза между ударами сверх длительности клипа
	CORPSE = 8,        -- после вирусного выброса (.65 с) тело на клиентах уже невидимо
}

local function serverNow() return workspace:GetServerTimeNow() end

-- тот же бар, что у пиратов (IslandClearSystem.attachHealthBar), без сноса чужих
-- SurfaceGui: у мутанта на них нарисовано лицо
local function hpBar(model, hum)
	local head = model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
	if not head or model:FindFirstChild("EnemyHP", true) then return end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local hb = EnemyHealthBar.new({ name = "МУТАНТ", maxHp = math.max(hum.MaxHealth, 1), cur = hum.Health, surface = true })
	hb.attach(head, 3.2, "EnemyHP")
	hb.setVisible(true)
	hb.setHP(hum.Health, hum.MaxHealth)
	hum.HealthChanged:Connect(function(h) hb.setHP(h, hum.MaxHealth) end)
end

local function ordered(folder)
	local list = {}
	if folder then
		for _, p in ipairs(folder:GetChildren()) do if p:IsA("BasePart") then table.insert(list, p) end end
	end
	table.sort(list, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or 0) < (tonumber(b:GetAttribute("Order")) or 0)
	end)
	return list
end

function M.Start(island, model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return nil end

	pcall(function() PhysicsService:RegisterCollisionGroup("FarmersNPC") end)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanTouch = true   -- пули бьют через Touched; пакет касание выключал
			pcall(function() d.CollisionGroup = "FarmersNPC" end)
			pcall(function() d:SetNetworkOwner(nil) end)
		end
	end
	hum.MaxHealth = CFG.HEALTH
	hum.Health = CFG.HEALTH
	hum.WalkSpeed = CFG.WALK
	hum.BreakJointsOnDeath = false
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	model:SetAttribute("Hostile", true)
	model:SetAttribute("FarmersState", "Idle")
	model:SetAttribute("FarmersAction", "")
	model:SetAttribute("FarmersActionT", serverNow())
	hpBar(model, hum)

	local g = island:FindFirstChild("Gameplay")
	local routes = g and g:FindFirstChild("Routes")
	local route = ordered(routes and routes:FindFirstChild(model:GetAttribute("Route") or "MutantPatrol"))
	local home = root.Position
	local rng = Random.new()

	local st = {
		state = "patrol", idx = 1, dwellUntil = 0, busyUntil = 0, slamAt = -100,
		lastHealth = hum.Health, target = nil, lastMove = os.clock(), lastPos = root.Position,
		dead = false, alt = false,
	}

	local function setState(name)
		if model:GetAttribute("FarmersState") ~= name then model:SetAttribute("FarmersState", name) end
	end
	local function setAction(name)
		if model:GetAttribute("FarmersAction") ~= name then
			model:SetAttribute("FarmersAction", name)
			model:SetAttribute("FarmersActionT", serverNow())
		end
	end

	-- вздрагивание от урона — тем же способом, что задумал пакет
	hum.HealthChanged:Connect(function(h)
		if h < st.lastHealth and h > 0 then
			local dmg = st.lastHealth - h
			model:SetAttribute("HurtTime", serverNow())
			model:SetAttribute("HurtVariant", rng:NextInteger(1, 3))
			model:SetAttribute("HurtStrength", math.clamp(0.6 + dmg / 60, 0.65, 1.35))
			-- ударили — цель известна и без глаз
			if not st.target then st.aggroFrom = os.clock() end
			model:SetAttribute("Detected", true)
		end
		st.lastHealth = h
	end)

	local function playerTarget()
		local best, bestD
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if h and r and h.Health > 0 and not ch:FindFirstChildOfClass("ForceField") then
				local d = (r.Position - root.Position).Magnitude
				local limit = (st.target and st.target.model == ch) and CFG.AGGRO_KEEP or CFG.AGGRO
				if st.aggroFrom and os.clock() - st.aggroFrom < 6 then limit = CFG.AGGRO_KEEP end
				if d <= limit and math.abs(r.Position.Y - root.Position.Y) < 25
					and (r.Position - home).Magnitude < CFG.LEASH + 20 and (not bestD or d < bestD) then
					best, bestD = { model = ch, hum = h, root = r }, d
				end
			end
		end
		return best
	end

	local function moveTo(pos, run)
		hum.WalkSpeed = run and CFG.RUN or CFG.WALK
		hum:MoveTo(pos)
		setState("Walk")
		setAction(run and "Run" or "")
		if (root.Position - st.lastPos).Magnitude > 1 then st.lastMove, st.lastPos = os.clock(), root.Position end
	end

	local function strike(kind, target)
		local a = CFG.ATTACKS[kind]
		local now = os.clock()
		st.busyUntil = now + a.dur + CFG.ATTACK_GAP
		if kind == "Slam" then st.slamAt = now end
		hum:MoveTo(root.Position)
		setState("Attack")
		setAction(a.action)
		task.delay(a.hit, function()
			if st.dead or not model.Parent then return end
			local hitAny = false
			local function hurt(ch, h, r)
				if h.Health <= 0 or ch:FindFirstChildOfClass("ForceField") then return end
				h:TakeDamage(a.dmg)
				local away = (r.Position - root.Position)
				away = Vector3.new(away.X, 0, away.Z)
				away = away.Magnitude > 0.1 and away.Unit or root.CFrame.LookVector
				r.AssemblyLinearVelocity = away * a.knock + Vector3.new(0, a.knock * 0.6, 0)
				hitAny = true
			end
			if a.aoe > 0 then
				for _, plr in ipairs(Players:GetPlayers()) do
					local ch = plr.Character
					local h = ch and ch:FindFirstChildOfClass("Humanoid")
					local r = ch and ch:FindFirstChild("HumanoidRootPart")
					if h and r and (r.Position - root.Position).Magnitude <= a.aoe then hurt(ch, h, r) end
				end
			elseif target.root.Parent and (target.root.Position - root.Position).Magnitude <= a.reach + 2 then
				hurt(target.model, target.hum, target.root)
			end
			if not hitAny then return end
		end)
		task.delay(a.dur, function()
			if st.dead or not model.Parent then return end
			if model:GetAttribute("FarmersAction") == a.action then setAction("") end
			setState("Idle")
		end)
	end

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or not island:IsDescendantOf(workspace) then conn:Disconnect() return end
		if st.dead then return end
		if hum.Health <= 0 then
			st.dead = true
			setAction("")
			setState("Dead")
			model:SetAttribute("Detected", false)
			hum:MoveTo(root.Position)
			-- вирусный выброс рисует клиент (GiantEffects.virusDeath) на .65 с от DeathT
			model:SetAttribute("DeathT", serverNow())
			task.delay(CFG.CORPSE, function() if model.Parent then model:Destroy() end end)
			conn:Disconnect()
			return
		end
		local now = os.clock()
		if now < st.busyUntil then
			-- в ударе стоим и доворачиваемся к цели
			if st.target and st.target.root.Parent then
				local p = st.target.root.Position
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(p.X, root.Position.Y, p.Z))
			end
			return
		end
		if st.tick and now - st.tick < 0.15 then return end
		st.tick = now

		local fromHome = (root.Position - home).Magnitude
		local target = playerTarget()
		st.target = target
		model:SetAttribute("Detected", target ~= nil)

		if target then
			local d = (target.root.Position - root.Position).Magnitude
			local slamReady = now - st.slamAt >= CFG.ATTACKS.Slam.cd
			-- ⚠️ УДАР О ЗЕМЛЮ — ПЕРВЫМ, ЕСЛИ ОТКАТИЛСЯ. Раньше он шёл только в
			-- окне 7–9 студов, а погоня пролетала его за один тик — удара с
			-- трещинами почти никто не видел.
			if d <= CFG.ATTACKS.Slam.reach and slamReady then
				strike("Slam", target)
			elseif d <= CFG.ATTACKS.Sweep.reach then
				st.alt = not st.alt
				strike(st.alt and "Sweep" or "Backhand", target)
			elseif fromHome > CFG.LEASH then
				moveTo(home, true)
			else
				moveTo(target.root.Position, true)
			end
			return
		end

		-- мирное время: домой, если увело, иначе маршрут
		if fromHome > 30 and st.state ~= "patrol" then
			moveTo(home, false)
			if fromHome < 6 then st.state = "patrol" end
			return
		end
		st.state = "patrol"
		if #route == 0 then setState("Idle") setAction("") return end
		if now < st.dwellUntil then setState("Idle") setAction("") return end
		local p = route[st.idx].Position
		local flat = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Magnitude
		if flat < 4 or now - st.lastMove > 6 then
			st.idx = st.idx % #route + 1
			st.dwellUntil = now + rng:NextNumber(CFG.DWELL[1], CFG.DWELL[2])
			st.lastMove = now
			hum:MoveTo(root.Position)
			setState("Idle") setAction("")
		else
			moveTo(p, false)
		end
	end)

	return { stop = function() if conn then conn:Disconnect() end end }
end

return M
