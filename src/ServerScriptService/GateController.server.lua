--[[
	GateController.server.lua — калитки забора: открыть / закрыть.
	Работает с Raft_fence_gate, Raft_fence_gate_soil и с калиткой внутри Raft_soil*_fenced.

	Устроено как DoorController (дверь плота), и по тем же причинам:
	  * створка сидит на Motor6D, а не твинится по CFrame — она часть сборки плота и
	    едет вместе с ним, цель «открыто» не протухает, когда плот уплыл;
	  * качается motor.Transform, а не C0 — сборка не пересобирается каждый шаг.

	Чем отличается от двери:
	  * НИЧЕГО НЕ ПРЕДПОЛАГАЕТ ПРО ОСИ ИМПОРТА. У чайки риг верил, что модель после
	    импорта смотрит по -Z, и сломался. Здесь всё меряется по деталям:
	      - ось петли  = положение и длинная ось меша «<калитка>_hinge» (это сам штырь);
	      - куда открывать = в ту сторону, где стоит рама относительно створки
	        (столбы и жерди — с внутренней стороны, штакетник — снаружи);
	  * позу считает ещё и КЛИЕНТ (GateSwing.client): Motor6D.Transform с сервера
	    клиентам не реплицируется, а персонаж сталкивается с тем, что видит его клиент.
	    Сервер ставит атрибуты GateOpen / GateT, клиент по ним крутит тот же мотор.

	Имена мешей (не менять): «X» — рама, «X_hinge» — штырь петли, «X_leaf» — створка,
	где X = raft_fence_gate | raft_fence_gate_soil | raft_soil_gate | raft_farm_gate_<ребро>. Все три — в одной модели.

	Атрибуты на СТВОРКЕ (необязательные, можно ставить в Studio):
	  GateAngle   number   на сколько градусов открывать, по умолчанию 95
	  GateTime    number   секунд на открытие, по умолчанию 0.6
	  AutoClose   number   закрыть сама через столько секунд; 0 или нет — не закрывать
	  GateLocked  boolean  true — подсказка скрыта, калитка не открывается
	Служебные (пишет сервер): GateOpen, GateT, GateSign.
	Из других скриптов: _G.SetGate(leafOrModel, open: boolean)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LOG = "[GateController]"
-- створка = имя с «_gate» и окончанием «_leaf»: raft_fence_gate_leaf, raft_soil_gate_leaf, raft_farm_gate_n1_leaf …
local function isLeaf(name)
	return string.sub(name, -5) == "_leaf" and string.find(name, "_gate", 1, true) ~= nil
end
local DEFAULT_ANGLE, DEFAULT_TIME = 95, 0.6

local gates = {} -- leaf -> state

local function longestAxis(part)
	local s, cf = part.Size, part.CFrame
	if s.Y >= s.X and s.Y >= s.Z then return cf.UpVector end
	if s.X >= s.Z then return cf.RightVector end
	return -cf.LookVector
end

local function flat(v, up)
	return v - up * v:Dot(up)
end

local function freeLeaf(leaf, keep)
	-- стройка и RaftStaticWeld приваривают ВСЕ детали модели к плоту; створку сварка заклинит
	for _, j in ipairs(leaf:GetJoints()) do
		if j ~= keep and (j:IsA("WeldConstraint") or j:IsA("Weld") or j:IsA("ManualWeld")) then
			j:Destroy()
		end
	end
	for _, d in ipairs(leaf:GetChildren()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then d:Destroy() end
	end
end

local function setup(leaf)
	if gates[leaf] then return end
	local model = leaf.Parent
	if not model then return end
	local base = string.sub(leaf.Name, 1, #leaf.Name - #"_leaf")
	local frame, hinge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == base then frame = d elseif d.Name == base .. "_hinge" then hinge = d end
		end
	end
	if not frame then
		warn(LOG .. " у створки " .. leaf:GetFullName() .. " нет рамы «" .. base .. "» в той же модели — калитка не подключена")
		return
	end

	-- ── ось петли ──
	local up, hingePos
	if hinge then
		up = longestAxis(hinge)
		hingePos = hinge.Position
	else
		-- старый импорт без штыря: ось — вертикальное ребро створки, какое именно — не узнать
		warn(LOG .. " нет меша «" .. base .. "_hinge» — переимпортируйте FBX. Ось петли взята по краю створки наугад: "
			.. leaf:GetFullName())
		up = longestAxis(frame)
		local lf = leaf.CFrame
		local axes = { lf.RightVector * leaf.Size.X, lf.UpVector * leaf.Size.Y, -lf.LookVector * leaf.Size.Z }
		table.sort(axes, function(a, b) return math.abs(a:Dot(up)) < math.abs(b:Dot(up)) end) -- [1],[2] горизонтальны
		local thick, wide = axes[1], axes[2]
		if thick.Magnitude > wide.Magnitude then thick, wide = wide, thick end
		hingePos = leaf.Position - wide / 2
	end
	if up.Y < 0 then up = -up end

	-- ── куда открывать ──
	local w = flat(leaf.Position - hingePos, up) -- от петли к середине створки
	if w.Magnitude < 1e-4 then
		warn(LOG .. " петля в центре створки? " .. leaf:GetFullName())
		return
	end
	local wU = w.Unit
	local toFrame = flat(frame.Position - leaf.Position, up)
	local inboard = toFrame - wU * toFrame:Dot(wU) -- только поперёк створки
	local sign = 1
	if inboard.Magnitude > 0.002 * leaf.Size.Magnitude then
		sign = (up:Cross(w):Dot(inboard) >= 0) and 1 or -1
	else
		warn(LOG .. " рама стоит ровно в плоскости створки — сторона открывания взята наугад: " .. leaf:GetFullName())
	end

	-- ── сустав ──
	local hingeCF = CFrame.fromMatrix(hingePos, wU, up) -- X вдоль створки, Y — ось петли
	for _, d in ipairs(leaf:GetChildren()) do
		if d:IsA("Motor6D") and d.Name == "GateHinge" then d:Destroy() end
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "GateHinge"
	motor.Part0 = frame
	motor.Part1 = leaf
	motor.C0 = frame.CFrame:ToObjectSpace(hingeCF)
	motor.C1 = leaf.CFrame:ToObjectSpace(hingeCF)
	motor.Parent = leaf
	freeLeaf(leaf, motor)
	leaf.Anchored = false -- заякоренную деталь Motor6D не двигает; раму держит плот или якорь
	leaf.Massless = true
	pcall(function() leaf:SetNetworkOwner(nil) end)

	local prompt = leaf:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Калитка"
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Parent = leaf
	end

	local st = { leaf = leaf, motor = motor, prompt = prompt, sign = sign, open = false, token = 0 }
	gates[leaf] = st
	leaf:SetAttribute("GateSign", sign)
	leaf:SetAttribute("GateOpen", false)
	leaf:SetAttribute("GateT", workspace:GetServerTimeNow())

	local function apply(open)
		if st.open == open then return end
		st.open = open
		st.token += 1
		local token = st.token
		local angle = tonumber(leaf:GetAttribute("GateAngle")) or DEFAULT_ANGLE
		local dur = tonumber(leaf:GetAttribute("GateTime")) or DEFAULT_TIME
		prompt.ActionText = open and "Закрыть" or "Открыть"
		leaf:SetAttribute("GateOpen", open)
		leaf:SetAttribute("GateT", workspace:GetServerTimeNow())
		-- серверная поза: по ней сталкиваются НПС и всё, чем владеет сервер
		TweenService:Create(motor, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transform = open and CFrame.Angles(0, sign * math.rad(angle), 0) or CFrame.identity }):Play()
		local auto = tonumber(leaf:GetAttribute("AutoClose")) or 0
		if open and auto > 0 then
			task.delay(auto, function()
				if st.token == token and gates[leaf] == st then st.set(false) end
			end)
		end
	end
	st.set = apply
	prompt.ActionText = "Открыть"
	-- спрятанная калитка (FarmBlock ставит FarmHidden) не открывается и подсказку не показывает
	local function usable()
		return leaf:GetAttribute("GateLocked") ~= true and leaf:GetAttribute("FarmHidden") ~= true
	end
	prompt.Enabled = usable()
	prompt.Triggered:Connect(function()
		if not usable() then return end
		apply(not st.open)
	end)
	leaf:GetAttributeChangedSignal("GateLocked"):Connect(function() prompt.Enabled = usable() end)
	leaf:GetAttributeChangedSignal("FarmHidden"):Connect(function() prompt.Enabled = usable() end)
	leaf.AncestryChanged:Connect(function()
		if not leaf:IsDescendantOf(game) then gates[leaf] = nil end
	end)

	-- стройка приваривает детали уже ПОСЛЕ появления модели — снять сварку ещё раз
	task.delay(1, function() if gates[leaf] == st then freeLeaf(leaf, motor) end end)
	task.delay(4, function() if gates[leaf] == st then freeLeaf(leaf, motor) end end)

	print(("%s подключена %s: ось петли %s, открывается на %d° (знак %d)")
		:format(LOG, leaf:GetFullName(), hinge and "по штырю" or "НАУГАД", DEFAULT_ANGLE, sign))
end

local function discover(inst)
	if inst:IsA("BasePart") and isLeaf(inst.Name) then
		-- дать модели доехать целиком (рама и штырь могут появиться кадром позже створки)
		task.delay(0.2, function()
			if inst:IsDescendantOf(workspace) then setup(inst) end
		end)
	end
end

_G.SetGate = function(target, open)
	for leaf, st in pairs(gates) do
		if leaf == target or (typeof(target) == "Instance" and leaf:IsDescendantOf(target)) then
			st.set(open and true or false)
		end
	end
end

for _, d in ipairs(workspace:GetDescendants()) do discover(d) end
workspace.DescendantAdded:Connect(discover)

print(LOG .. " ready")
