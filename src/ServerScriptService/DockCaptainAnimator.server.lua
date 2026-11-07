--[[
	КАПИТАН В ПРИЧАЛЕ (Boat_3x) — цикл простоя.

	idle_1 крутится 5–10 раз подряд (число выбирается заново каждый круг), затем
	ОДИН раз idle_2 — и всё сначала.

	Подготовка рига один в один как у механика (EngineerSystem): Humanoid + Animator,
	стейт-машина выключена, детали невесомы и без коллизий, корень держит Weld к
	плоту. Держаться этой схемы важно — на анкоре и на приваренных конечностях
	Motor6D не работает и анимация молча не проигрывается.

	Анимации ищем по ИМЕНИ среди детей модели (их туда положил дизайнер), а не по
	фиксированному пути: капитана внутри причала можно перекладывать как угодно.

	Ловим причалы и при постройке, и при загрузке сейва.
]]

local Workspace = game:GetService("Workspace")

local DOCK_NAME  = "Boat_3x"
local IDLE_MAIN  = "idle_1"
local IDLE_BREAK = "idle_2"
local MIN_REPEAT, MAX_REPEAT = 5, 10
local FADE = 0.25

-- модель может доехать в Workspace не за один кадр (например, при восстановлении
-- сейва), поэтому пробуем зацепиться несколько раз
local ATTEMPTS, RETRY_DELAY = 5, 1

local running = {}   -- [Model] = true, чтобы не запустить два цикла на один причал

-- ── плот ──
local function raft() return Workspace:FindFirstChild("Raft") end
local function rpp() local r = raft(); return r and r.PrimaryPart end

-- ── риг ──
local function findRig(model)
	if model:FindFirstChild("Torso") or model:FindFirstChild("Head") then return model end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChild("Torso") or d:FindFirstChild("Head")) then return d end
	end
	return model
end

-- капитан = риг с анимацией idle_1 внутри причала
local function findCaptain(dock)
	local anim
	for _, d in ipairs(dock:GetDescendants()) do
		if d:IsA("Animation") and d.Name:lower() == IDLE_MAIN:lower() and d.AnimationId ~= "" then
			anim = d
			break
		end
	end
	if not anim then return nil end
	local p = anim.Parent
	while p and p ~= dock do
		if p:IsA("Model") then return findRig(p) end
		p = p.Parent
	end
	return findRig(dock)
end

local function ensureHumanoid(rig)
	local hum = rig:FindFirstChildWhichIsA("Humanoid", true)
	if not hum then
		if not rig:FindFirstChildWhichIsA("BasePart") then return nil, nil end
		hum = Instance.new("Humanoid")
		hum.Parent = rig
	end
	hum.BreakJointsOnDeath = false
	local hrp = rig:FindFirstChild("HumanoidRootPart") or hum.RootPart
		or rig:FindFirstChild("Torso") or rig:FindFirstChildWhichIsA("BasePart")
	return hum, hrp
end

-- корень капитана держится на плоту вельдом, поза берётся ТЕКУЩАЯ (как её поставил
-- причал), поэтому капитан остаётся ровно там, где сидит в лодке
local function ensureRaftWeld(hrp)
	local w = hrp:FindFirstChild("_DockCaptainWeld")
	if w and w:IsA("Weld") and w.Part0 and w.Part0.Parent then return w end
	if w then w:Destroy() end
	local base = rpp()
	if not base then return nil end
	-- Причал при постройке уже приваривает корень к плоту (BuildingSystem варит всё,
	-- кроме управляемых Motor6D деталей). Второй вельд поверх не нужен.
	for _, d in ipairs(hrp:GetChildren()) do
		if (d:IsA("WeldConstraint") and (d.Part0 == base or d.Part1 == base))
			or (d:IsA("Weld") and (d.Part0 == base or d.Part1 == base)) then
			hrp.Anchored = false
			return d
		end
	end
	hrp.Anchored = false
	w = Instance.new("Weld")
	w.Name = "_DockCaptainWeld"
	w.Part0 = base
	w.Part1 = hrp
	w.C1 = CFrame.new()
	w.C0 = base.CFrame:Inverse() * hrp.CFrame
	w.Parent = hrp
	return w
end

-- Ровно как setupNpc у механика: без коллизий, невесом, свои скрипты выключены,
-- стейт-машина humanoid'а не мешает анимации.
local function setupCaptain(rig)
	local hum, hrp = ensureHumanoid(rig)
	if not hum or not hrp then return nil, nil end
	hrp = hum.RootPart or hrp
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			pcall(function() d.EnableFluidForces = false end)
			d.Anchored = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
	pcall(function() rig.PrimaryPart = hrp end)
	hum.EvaluateStateMachine = false
	hum.AutoRotate = false
	hum.PlatformStand = true
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	rig:SetAttribute("WaterImmune", true)
	rig:SetAttribute("RaftFriendly", true)
	ensureRaftWeld(hrp)
	pcall(function() hrp:SetNetworkOwner(nil) end)
	return hum, hrp
end

-- анимация по имени из детей модели (как loadNamed у механика)
local function loadNamed(hum, model, name)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") and d.AnimationId ~= "" and d.Name:lower() == name:lower() then
			local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
			if ok and tr then
				tr.Priority = Enum.AnimationPriority.Action
				tr.Looped = false   -- повторы считаем сами, циклом
				return tr
			end
		end
	end
	return nil
end

-- Length появляется не сразу: анимация ещё грузится с серверов Roblox.
local function waitForLength(track)
	if track.Length > 0 then return track.Length end
	for _ = 1, 60 do
		task.wait(0.1)
		if track.Length > 0 then return track.Length end
	end
	return 0
end

-- Ждём длину трека, а не событие Stopped: пропущенный Stopped вешает цикл намертво.
local function playOnce(track)
	pcall(function() track:Play(FADE) end)
	local len = waitForLength(track)
	if len <= 0 then
		pcall(function() track:Stop(FADE) end)
		return false
	end
	task.wait(len)
	return true
end

local function startDock(dock)
	if running[dock] then return true end
	if not rpp() then return false end   -- плот ещё не собран, попробуем позже

	local rig = findCaptain(dock)
	if not rig then return false end

	local hum = setupCaptain(rig)
	if not hum then return false end

	local t1 = loadNamed(hum, rig, IDLE_MAIN)
	if not t1 then return false end
	local t2 = loadNamed(hum, rig, IDLE_BREAK)
	if not t2 then
		warn(("[Причал] у капитана нет %s — крутим только %s"):format(IDLE_BREAK, IDLE_MAIN))
	end

	running[dock] = true
	task.spawn(function()
		while dock.Parent do
			for _ = 1, math.random(MIN_REPEAT, MAX_REPEAT) do
				if not dock.Parent then break end
				if not playOnce(t1) then task.wait(2) end
			end
			if t2 and dock.Parent then
				if not playOnce(t2) then task.wait(2) end
			end
		end
		running[dock] = nil
	end)
	return true
end

local function tryStart(dock, left)
	if startDock(dock) then return end
	if left > 1 and dock.Parent then
		task.delay(RETRY_DELAY, tryStart, dock, left - 1)
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name == DOCK_NAME then
		tryStart(d, ATTEMPTS)
	end
end

Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == DOCK_NAME then
		task.defer(tryStart, inst, ATTEMPTS)
	end
end)
