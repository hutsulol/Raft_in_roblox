--[[
	РЫБАЦКАЯ ЛОДКА (Boat_Skiff): проходит мимо плота, тонет и уходит на дно.

	Это НЕ боевая единица и не патруль: она не кружит у борта, не стреляет и
	никого не замечает. Появляется в стороне, идёт прямым курсом мимо плота, а
	отойдя достаточно далеко — набирает воду, погружается и исчезает.

	Состав модели (шаблон Boat_Skiff в ReplicatedStorage либо в Workspace):
	  boat_skiff              — корпус
	  boat_skiff_driver_seat  — МАРКЕР места водителя (в мир не попадает)
	  boat_skiff_fishnet      — сеть с уловом: подбирается игроком (ProximityPrompt)
	  Boat_Skiff_Chef         — сам моряк, R6-модель внутри лодки

	⚠️ ХОД СЧИТАЕТСЯ ПО СОСТОЯНИЮ, А НЕ ПИШЕТСЯ КАЖДЫЙ КАДР.
	Раньше сервер двигал детали CFrame'ом каждый кадр — и лодку трясло у всех,
	потому что свойства реплицируются реже, чем идут кадры. Теперь сервер
	публикует состояние (откуда, куда, когда вышла) в атрибутах, а положение по
	нему считают обе стороны сами: клиент — каждый кадр (гладко), сервер — редко,
	чтобы остальные игроки и его собственные запросы видели лодку на месте.
	Формула одна на всех, лежит в ReplicatedStorage.SkiffMotion.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local Motion = require(ReplicatedStorage:WaitForChild("SkiffMotion"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG = "[Лодка]"

-- ── настройки ──
local MODEL_NAME   = "Boat_Skiff"
local LIVE_NAME    = "Boat_Skiff_Live"
local HULL_NAME    = "boat_skiff"
local SEAT_NAME    = "boat_skiff_driver_seat"
local NET_NAME     = "boat_skiff_fishnet"
local CHEF_NAME    = "Boat_Skiff_Chef"

local SPEED        = 9      -- студов/с: неспешный ход рыбака
local SPAWN_DIST   = 190    -- на каком удалении появляется
local PASS_OFFSET  = 42     -- на сколько студов в сторону проходит мимо плота
local SINK_DIST    = 340    -- ушла дальше — начинает тонуть
local MAX_LIFE     = 420    -- страховка: дольше этого лодка не живёт
local SERVER_STEP  = 0.1    -- как часто сервер переставляет детали (клиент — каждый кадр)
local IDLE_CLIP    = "IdleSit"   -- моряк сидит за штурвалом и поглядывает вокруг

-- ⚠️ РАЗВОРОТ КОРПУСА. В брифе сказано «нос смотрит в −Z детали», но импорт
-- приехал наоборот — лодка шла кормой вперёд.
local HULL_YAW = math.pi
local CHEF_YAW = 0
local CHEF_LIFT = 2.0   -- корень R6 выше банки: маркер стоит на сиденье

-- Улов: 2–3 штуки ОДНОГО случайного вида из существующих сырых рыб
local FISH_KINDS = {
	"Blue_Fish", "Carp_Fish", "Foil_Fish", "Jelly_Fish",
	"Seabass_Fish", "Tilapia_Fish",
}
local CATCH_MIN, CATCH_MAX = 2, 3

-- ── освобождение моряка ──
local HAPPY_FACE   = "rbxassetid://89457811123003"
local JOY_CLIPS    = { "Freed", "Stretch" }
local LEAVE_AFTER  = 10    -- сколько радуется, прежде чем исчезнуть
local FADE_TIME    = 1.0   -- за сколько «испаряется»

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn(LOG .. " " .. msg)
end

local function findTemplate()
	-- по имени, а не по месту: модели разложены по папкам (см. AssetFind)
	local fromRS = AssetFind.find(MODEL_NAME)
	if fromRS and fromRS:IsA("Model") then return fromRS end
	for _, c in ipairs({ ServerStorage, Workspace }) do
		local t = c:FindFirstChild(MODEL_NAME)
		if t and t:IsA("Model") then return t end
	end
	return nil
end

-- ── улов ──
local function giveCatch(player, net)
	if net:GetAttribute("Taken") then return end
	net:SetAttribute("Taken", true)

	local kind = FISH_KINDS[math.random(#FISH_KINDS)]
	local count = math.random(CATCH_MIN, CATCH_MAX)
	if _G.AddResourceToInventory then
		_G.AddResourceToInventory(player, kind, count, net.Position)
	end
	if _G.SendInventory then _G.SendInventory(player) end
	print(("%s %s забрал улов: %s x%d"):format(LOG, player.Name, kind, count))
	net:Destroy()
end

-- ── сама лодка ──
local active = nil   -- одна лодка за раз: две сразу выглядят как флотилия

local function setFace(model, texture)
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Decal") or d:IsA("Texture")) and d.Name:lower():find("face", 1, true) then
			d.Texture = texture
		end
	end
end

local function fadeOut(model, seconds, done)
	task.spawn(function()
		local t0 = os.clock()
		while model.Parent do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = math.max(d.Transparency, a)
				elseif d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = a
				end
			end
			if a >= 1 then break end
			task.wait()
		end
		if done then done() end
		if model.Parent then model:Destroy() end
	end)
end

-- Всплывающее «+1 житель» над головой.
local function popupVillager(headPart)
	if not headPart then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VillagerPopup"
	bb.Size = UDim2.fromOffset(210, 52)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Adornee = headPart
	bb.Parent = headPart

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = bb

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = "🎉 +1 ЖИТЕЛЬ"
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeColor3 = Color3.fromRGB(8, 46, 20)
	lbl.TextStrokeTransparency = 0.15
	lbl.Parent = bb

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 150)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(140, 255, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 220, 120)),
	})
	grad.Parent = lbl

	task.spawn(function()
		local LIFE = 1.8
		local t0 = os.clock()
		while bb.Parent do
			local a = (os.clock() - t0) / LIFE
			if a >= 1 then break end
			local pop = (a < 0.25)
				and (0.4 + 0.75 * math.sin((a / 0.25) * math.pi * 0.5))
				or (1.15 - 0.15 * math.min(1, (a - 0.25) / 0.25))
			scale.Scale = pop
			bb.StudsOffset = Vector3.new(math.sin(a * math.pi * 2) * 0.12, 2.6 + a * 2.4, 0)
			local fade = math.max(0, (a - 0.5) / 0.5)
			lbl.TextTransparency = fade
			lbl.TextStrokeTransparency = 0.15 + fade * 0.85
			task.wait()
		end
		bb:Destroy()
	end)
end

-- Освободить моряка: +1 житель, радость, смена лица — и через LEAVE_AFTER он
-- растворяется. Лодка идёт дальше своим курсом уже пустой.
local function freeSailor(state, player)
	if state.freed then return end
	state.freed = true

	if _G.AddVillagers then
		pcall(_G.AddVillagers, player, 1)
	end
	setFace(state.chef, HAPPY_FACE)
	popupVillager(state.chef:FindFirstChild("Head", true))

	local clips = Motion.clips()
	if clips then
		for _, name in ipairs(JOY_CLIPS) do
			if clips[name] then
				state.folder:SetAttribute("ClipName", name)
				state.folder:SetAttribute("ClipStart", Workspace:GetServerTimeNow())
				break
			end
		end
	end

	if state.prompt then state.prompt:Destroy() state.prompt = nil end
	print(("%s %s освободил моряка: +1 житель"):format(LOG, player.Name))

	task.delay(LEAVE_AFTER, function()
		if not (state.chef and state.chef.Parent) then return end
		fadeOut(state.chef, FADE_TIME, function()
			state.rig = nil
		end)
	end)
end

local function raftModel() return Workspace:FindFirstChild("Raft") end

local function raftCenter(raft)
	if _G.GetRaftCenter then
		local ok, c = pcall(_G.GetRaftCenter)
		if ok and typeof(c) == "Vector3" then return c end
	end
	return raft.PrimaryPart and raft.PrimaryPart.Position or raft:GetPivot().Position
end

local function spawnSkiff()
	if active and active.folder.Parent then return false, "лодка уже в море" end
	local raft = raftModel()
	if not raft or not raft.PrimaryPart then return false, "плот ещё не собран" end

	local template = findTemplate()
	if not template then
		return false, ("модели «%s» нет ни в ReplicatedStorage, ни в Workspace"):format(MODEL_NAME)
	end

	local model = template:Clone()
	model.Name = LIVE_NAME
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end

	local hull = model:FindFirstChild(HULL_NAME, true)
	if not hull or not hull:IsA("BasePart") then
		model:Destroy()
		return false, ("в модели нет корпуса «%s»"):format(HULL_NAME)
	end

	-- курс: мимо плота, со случайной стороны и случайного борта
	local center = raftCenter(raft)
	local theta = math.random() * math.pi * 2
	local dir = Vector3.new(math.cos(theta), 0, math.sin(theta)).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X) * (((math.random() < 0.5) and 1 or -1) * PASS_OFFSET)
	local waterY = center.Y
	if _G.GetWaterLevel then
		local ok, y = pcall(_G.GetWaterLevel)
		if ok and type(y) == "number" then waterY = y end
	end

	local startPos = center + dir * SPAWN_DIST + side
	local heading = -dir

	local chef = model:FindFirstChild(CHEF_NAME, true)
	local seatMarker = model:FindFirstChild(SEAT_NAME, true)
	local net = model:FindFirstChild(NET_NAME, true)

	-- относительные позиции деталей лодки (моряк в список не идёт: его ведёт риг)
	local base = hull.CFrame * CFrame.Angles(0, HULL_YAW, 0)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not (chef and d:IsDescendantOf(chef)) then
			d.Anchored = true
			d.CanCollide = (d == hull)
			table.insert(parts, { part = d, rel = base:ToObjectSpace(d.CFrame) })
		end
	end

	local seatRel = seatMarker and base:ToObjectSpace(seatMarker.CFrame) or CFrame.new(0, 1.5, 0)
	if seatMarker then
		for i = #parts, 1, -1 do
			if parts[i].part == seatMarker then table.remove(parts, i) end
		end
		seatMarker:Destroy()
	end

	if net and net:IsA("BasePart") then
		net.CanCollide = false
		net.CanQuery = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CatchPrompt"
		prompt.ActionText = "Забрать улов"
		prompt.ObjectText = "Сеть с рыбой"
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = net
		prompt.Triggered:Connect(function(player) giveCatch(player, net) end)
	end

	local rig, chefRel
	if chef then
		for _, d in ipairs(chef:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		local hum = chef:FindFirstChildWhichIsA("Humanoid")
		if hum then
			hum.EvaluateStateMachine = false
			hum.PlatformStand = true
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
		rig = Motion.buildRig(chef)
		if not rig then
			warnOnce("chef_rig", ("«%s» не R6 (нет Torso/Motor6D) — моряк будет без анимации"):format(CHEF_NAME))
		end
		local seatPos = (seatRel * CFrame.new(0, CHEF_LIFT, 0)).Position
		chefRel = CFrame.new(seatPos) * CFrame.Angles(0, CHEF_YAW, 0)
	end

	-- ── ПУБЛИКУЕМ СОСТОЯНИЕ: по нему обе стороны считают ход ──
	local now = Workspace:GetServerTimeNow()
	model:SetAttribute("StartX", startPos.X)
	model:SetAttribute("StartZ", startPos.Z)
	model:SetAttribute("HeadX", heading.X)
	model:SetAttribute("HeadZ", heading.Z)
	model:SetAttribute("StartT", now)
	model:SetAttribute("Speed", SPEED)
	model:SetAttribute("WaterY", waterY)
	model:SetAttribute("ClipName", IDLE_CLIP)
	model:SetAttribute("ClipStart", now)
	if chefRel then model:SetAttribute("ChefRel", chefRel) end

	model.PrimaryPart = hull
	model.Parent = Workspace

	active = {
		folder = model, hull = hull, parts = parts,
		chef = chef, rig = rig, chefRel = chefRel,
		bornAt = now, nextStep = 0,
	}

	-- прочтение «Освободить» на самом моряке
	if chef then
		local host = chef:FindFirstChild("Torso", true) or chef:FindFirstChild("HumanoidRootPart", true)
		if host and host:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "FreeSailorPrompt"
			prompt.ActionText = "Освободить"
			prompt.ObjectText = "Моряк"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = host
			local st = active
			prompt.Triggered:Connect(function(player) freeSailor(st, player) end)
			active.prompt = prompt
		end
	end

	print(("%s вышла в море: старт в %d студах, идёт мимо плота"):format(LOG, SPAWN_DIST))
	return true
end

-- ── серверный такт ──
-- Детали переставляем РЕДКО (SERVER_STEP): это для остальных игроков и запросов.
-- Гладкую картинку каждому рисует клиент сам — по тем же атрибутам.
RunService.Heartbeat:Connect(function()
	local s = active
	if not s then return end
	if not s.folder.Parent then active = nil return end

	local now = Workspace:GetServerTimeNow()

	-- пора ли тонуть
	if not s.folder:GetAttribute("SinkAt") then
		local raft = raftModel()
		local origin = Motion.originCF(s.folder, now)
		if raft and origin then
			local center = raftCenter(raft)
			local away = flat(origin.Position - center).Magnitude
			local goingAway = flat(origin.LookVector):Dot(flat(origin.Position - center)) > 0
			if (goingAway and away > SINK_DIST) or (now - s.bornAt) > MAX_LIFE then
				s.folder:SetAttribute("SinkAt", now)
				if s.prompt then s.prompt:Destroy() s.prompt = nil end
				print(LOG .. " ушла далеко — набирает воду и идёт ко дну")
			end
		end
	else
		-- дотонула — убираем
		if now - s.folder:GetAttribute("SinkAt") > Motion.SINK_TIME + 0.5 then
			s.folder:Destroy()
			active = nil
			return
		end
	end

	if now < s.nextStep then return end
	s.nextStep = now + SERVER_STEP

	local origin = Motion.originCF(s.folder, now)
	if not origin then return end
	for _, e in ipairs(s.parts) do
		if e.part.Parent then e.part.CFrame = origin * e.rel end
	end
	if s.rig and s.chefRel and s.chef and s.chef.Parent then
		Motion.applyRig(s.rig, origin * s.chefRel, Motion.chefPose(s.folder, now))
	end
end)

-- ── внешний API (кнопка в настройках) ──
_G.SpawnFishingSkiff = function()
	local ok, why = spawnSkiff()
	if not ok then warn(LOG .. " не вышла: " .. tostring(why)) end
	return ok, why
end

print(LOG .. " готова (_G.SpawnFishingSkiff): проходит мимо плота, тонет и уходит; улов — 2-3 рыбы одного вида")
