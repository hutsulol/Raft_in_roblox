--[[
	SheepRig — приводит ЛЮБУЮ модель овцы к одному рису суставов, который умеет
	играть SheepAnimator (клиент, PirateIslandAnim.ANIMAL_MOTORS.Sheep):

		HumanoidRootPart --RootJoint--> <туша>
			<туша> --Neck----------------> <голова>
			<туша> --HipFL/FR/RL/RR------> <ноги>
			<туша>/<голова> --<Имя>Joint-> всё остальное (шерсть, уши, глаза, хвост)

	⚠️ ДВА ВХОДА, ОДИН ВЫХОД.
	  • Модель уже с суставами (авторский риг на 25 деталей: BodyWool, HeadWool,
	    TailWool, глаза, уши…): Motor6D НЕ сносим — раньше сборка удаляла их все
	    и соединяла только семь деталей старой овцы, остальное падало (владелец).
	    Суставы только ПЕРЕИМЕНОВЫВАЕМ по роли детали, чтобы клиент нашёл их по
	    каноническим именам.
	  • Модель без суставов (нарезка из FBX, SheepRigData): собираем сами. Известные
	    семь деталей — по долям из SheepRigData, всё прочее — жёстко к туше или
	    голове по центру детали.
	Роли: туша — «Torso»/«Body» (не шерсть) или самая крупная не-шерстяная деталь;
	голова — «Head» (не шерсть); ноги — по слову leg/foot/hoof, сторона и перед/зад
	— ПО ПОЛОЖЕНИЮ относительно туши и головы, а не по буквам в имени (FL, LF,
	FrontLeft, LeftFront читаются одинаково).

	⚠️ Суставы строятся ПО ТЕКУЩЕЙ ПОЗЕ — звать setup ДО перестановки модели.
	⚠️ Корень смотрит В СТОРОНУ ГОЛОВЫ: код движения работает обычным lookAt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage:WaitForChild("SheepRigData"))

local SheepRig = {}

local function lower(s) return string.lower(s) end
local function isWoolName(n) return lower(n):find("wool", 1, true) ~= nil or lower(n):find("fleece", 1, true) ~= nil end
local function isHeadish(n)
	n = lower(n)
	for _, k in ipairs({ "head", "eye", "ear", "muzzle", "jaw", "mouth", "nose", "horn", "snout" }) do
		if n:find(k, 1, true) then return true end
	end
	return false
end
local function isLegName(n)
	n = lower(n)
	return n:find("leg", 1, true) ~= nil or n:find("foot", 1, true) ~= nil or n:find("hoof", 1, true) ~= nil
		or n:find("hip", 1, true) ~= nil
end

local function volume(p) return p.Size.X * p.Size.Y * p.Size.Z end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- Роли деталей
local function classify(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then table.insert(parts, d) end
	end
	local torso = model:FindFirstChild("Torso", true)
	if not (torso and torso:IsA("BasePart")) then
		torso = nil
		for _, p in ipairs(parts) do
			local n = lower(p.Name)
			if not isWoolName(p.Name) and (n == "body" or n == "torso" or n:find("torso", 1, true) or n == "body_main") then
				torso = p break
			end
		end
	end
	if not torso then
		local best = 0
		for _, p in ipairs(parts) do
			if not isWoolName(p.Name) and not isHeadish(p.Name) and not isLegName(p.Name) and volume(p) > best then
				best, torso = volume(p), p
			end
		end
	end
	if not torso then
		local best = 0
		for _, p in ipairs(parts) do if volume(p) > best then best, torso = volume(p), p end end
	end
	local head = model:FindFirstChild("Head", true)
	if not (head and head:IsA("BasePart")) then
		head = nil
		local best = 0
		for _, p in ipairs(parts) do
			if p ~= torso and isHeadish(p.Name) and not isWoolName(p.Name) and lower(p.Name):find("head", 1, true)
				and volume(p) > best then
				best, head = volume(p), p
			end
		end
	end
	return parts, torso, head
end

-- направление «к голове» и «вправо» в мире
local function axes(torso, head)
	local fwd = flat(torso.CFrame.LookVector)
	if head then
		local d = flat(head.Position - torso.Position)
		if d.Magnitude > 0.05 then fwd = d end
	end
	if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local right = Vector3.new(-fwd.Z, 0, fwd.X)   -- поворот на 90° по часовой сверху
	return fwd, right
end

-- Имя сустава ноги по положению детали относительно туши
local function legJointName(part, torso, fwd, right)
	local d = part.Position - torso.Position
	local f = d:Dot(fwd) >= 0 and "F" or "R"
	local s = d:Dot(right) >= 0 and "R" or "L"
	return "Hip" .. f .. s
end

local function setPhysics(part, isTorso)
	part.Anchored = false
	part.CanCollide = isTorso
	part.Massless = not isTorso
	part.CanTouch = false
end

function SheepRig.setup(model)
	-- чужие контроллеры и скрипты — вон: зверя ведёт код через CFrame, а модель с
	-- AnimationController без Humanoid ещё и обезвреживает AnimalStabilizer
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("AnimationController") or d:IsA("Animator") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local parts, torso, head = classify(model)
	assert(torso, "SheepRig: в модели нет ни одной детали — " .. model.Name)
	local fwd, right = axes(torso, head)

	-- корень: есть — берём, нет — создаём размером с тушу
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Transparency = 1
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.Size = Vector3.new(torso.Size.X * 0.9, torso.Size.Y * 0.9, torso.Size.Z * 0.9)
		root.CFrame = CFrame.lookAt(torso.Position, torso.Position + fwd)
		root.Parent = model
	end
	model.PrimaryPart = root

	-- уже есть суставы? тогда это авторский риг
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then table.insert(motors, d) end
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			-- сварки авторского рига не мешают, оставляем
		end
	end
	local authored = #motors > 0

	if not authored then
		-- ── сборка с нуля ──
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Weld") or d:IsA("WeldConstraint") then d:Destroy() end
		end
		local rj = Instance.new("Motor6D")
		rj.Name = "RootJoint"
		rj.Part0 = root
		rj.Part1 = torso
		rj.C0 = root.CFrame:Inverse() * torso.CFrame
		rj.C1 = CFrame.identity
		rj.Parent = root

		local known = {}   -- детали, чьи точки крепления знает SheepRigData
		if model:FindFirstChild("Torso", true) == torso then
			for name, j in pairs(Data.Joints) do
				local part = model:FindFirstChild(name, true)
				if part and part:IsA("BasePart") and part ~= torso then known[part] = j end
			end
		end
		for _, part in ipairs(parts) do
			if part ~= torso then
				local parent = torso
				local at
				local jname
				local j = known[part]
				if j then
					at = torso.CFrame * CFrame.new(torso.Size.X * j.torso[1], torso.Size.Y * j.torso[2], torso.Size.Z * j.torso[3])
					jname = (part == head) and "Neck" or (isLegName(part.Name) and legJointName(part, torso, fwd, right)) or (part.Name .. "Joint")
				elseif part == head then
					at = head.CFrame * CFrame.new(0, -head.Size.Y * 0.25, -head.Size.Z * 0.4)
					jname = "Neck"
				elseif isLegName(part.Name) then
					at = part.CFrame * CFrame.new(0, part.Size.Y * 0.5, 0)   -- верх ноги
					jname = legJointName(part, torso, fwd, right)
				else
					if head and isHeadish(part.Name) then parent = head end
					at = part.CFrame
					jname = part.Name .. "Joint"
				end
				local m = Instance.new("Motor6D")
				m.Name = jname
				m.Part0 = parent
				m.Part1 = part
				m.C0 = parent.CFrame:Inverse() * at
				m.C1 = part.CFrame:Inverse() * at
				m.Parent = parent
			end
		end
	else
		-- ── авторский риг: суставы на месте, только имена по ролям ──
		local rootJoint
		for _, m in ipairs(motors) do
			local p0, p1 = m.Part0, m.Part1
			if (p0 == root and p1 == torso) or (p0 == torso and p1 == root) then
				rootJoint = m
				m.Name = "RootJoint"
			elseif p1 == head or (p1 ~= torso and head == nil and isHeadish(p1.Name) and not isWoolName(p1.Name)) then
				if p1 == head then m.Name = "Neck" end
			elseif p1 ~= root and p1 ~= torso and isLegName(p1.Name) and not isWoolName(p1.Name) then
				-- нога — только «большая» деталь ноги, крепящаяся к туше
				if p0 == torso or p0 == root then
					m.Name = legJointName(p1, torso, fwd, right)
				end
			end
		end
		if not rootJoint then
			local rj = Instance.new("Motor6D")
			rj.Name = "RootJoint"
			rj.Part0 = root
			rj.Part1 = torso
			rj.C0 = root.CFrame:Inverse() * torso.CFrame
			rj.C1 = CFrame.identity
			rj.Parent = root
			rootJoint = rj
		end
		-- корень должен смотреть на голову: разворачиваем его, не трогая тушу
		if rootJoint.Part0 == root then
			local look = flat(root.CFrame.LookVector)
			if look.Magnitude < 0.01 or look.Unit:Dot(fwd) < 0.9 then
				local jointWorld = root.CFrame * rootJoint.C0
				local newRoot = CFrame.lookAt(root.Position, root.Position + fwd)
				rootJoint.C0 = newRoot:Inverse() * jointWorld
				root.CFrame = newRoot
			end
		end
	end

	-- физика: корень якорный, туша сталкивается, всё прочее невесомо
	root.Anchored = true
	setPhysics(torso, true)
	for _, part in ipairs(parts) do
		if part ~= torso then setPhysics(part, false) end
	end

	-- высота корня над копытами
	local bottom = math.huge
	for _, d in ipairs(parts) do
		bottom = math.min(bottom, d.Position.Y - d.Size.Y * 0.5)
	end
	if bottom < math.huge then model:SetAttribute("FootOffset", root.Position.Y - bottom) end
	model:SetAttribute("RigAuthored", authored)
	return model
end

-- Все детали шерсти модели (для стрижки): { part = размер до стрижки }
function SheepRig.woolParts(model)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and isWoolName(d.Name) then out[d] = d.Size end
	end
	return out
end

return SheepRig
