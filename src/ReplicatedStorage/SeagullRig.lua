--[[
	SeagullRig — превращает импортированную модель «Seagull» (12 MeshPart) в Motor6D-риг.
	Близнец CowRig: никаких костей, отдельные жёсткие детали на Motor6D, идемпотентно,
	можно звать на каждом клоне при спавне.

		HumanoidRootPart --RootJoint--> gull_torso
			gull_torso --Neck--------> gull_head --JawJoint--> gull_jaw
			gull_torso --ShoulderL/R-> gull_wing_l / _r
			gull_torso --TailJoint---> gull_tail
			gull_torso --HipL/R--> gull_thigh --KneeL/R--> gull_shin --AnkleL/R--> gull_foot

	Клипы (SeagullClips) ключуются ИМЕНЕМ ДЕТАЛИ, как у коровы:
		Torso→RootJoint, Head→Neck, Jaw→JawJoint, WingL/R→ShoulderL/R, Tail→TailJoint,
		ThighL/R→HipL/R, ShinL/R→KneeL/R, FootL/R→AnkleL/R        (Rig.MOTORS)

	Отличие от CowRig, и оно нужно из-за крыльев: у коровы рамка сустава берёт поворот
	ДЕТАЛИ (at = part.CFrame * offset). Здесь C0 и C1 снимаются с одной МИРОВОЙ рамки
	сустава, выставленной по осям шаблона (+X вправо, +Y вверх, -Z клюв). Клипы
	запечены именно в этих осях; если импорт запечёт в какую-то деталь свой поворот,
	крыло всё равно раскроется в стороны, а не куда придётся.

	⚠️ Суставы строятся ПО ТЕКУЩЕЙ ПОЗЕ: клон должен стоять так, как приехал из FBX
	(стоя, клювом по -Z, без поворота модели). Звать setup ДО перестановки модели.
]]

local Data = require(script.Parent:WaitForChild("SeagullRigData"))

local SeagullRig = {}
SeagullRig.Data = Data

-- ключ клипа → имя сустава (это же нужно клиентскому проигрывателю)
SeagullRig.MOTORS = { Torso = "RootJoint" }
for _, j in ipairs(Data.Joints) do
	SeagullRig.MOTORS[j.key] = j.joint
end

local function findPart(model, name)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.lower(d.Name) == name then
			return d
		end
	end
	return nil
end

function SeagullRig.setup(model)
	local torso = findPart(model, "gull_torso")
	assert(torso, "SeagullRig: в модели нет детали gull_torso — " .. model.Name)

	-- масштаб импорта меряем, а не верим константе: модель приезжает то крупнее, то мельче
	local scale = torso.Size.Y / Data.TorsoSize.Y
	local drift = math.abs(torso.Size.X / Data.TorsoSize.X - scale) / scale
	if drift > 0.08 then
		warn(("SeagullRig: торс растянут неравномерно (%.0f%%) — суставы могут съехать"):format(drift * 100))
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end

	local parts = {}
	for name in pairs(Data.Parts) do
		local p = findPart(model, name)
		if p then
			p.Anchored = false          -- якорь только на корне: заякоренная деталь игнорирует Motor6D
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			parts[name] = p
		else
			warn("SeagullRig: нет детали " .. name .. " в " .. model.Name)
		end
	end

	-- ⚠️ ОСИ МОДЕЛИ МЕРЯЕМ, А НЕ ПРЕДПОЛАГАЕМ.
	-- Первая версия считала, что после импорта клюв смотрит по -Z шаблона. Импорт
	-- развернул геометрию иначе: точки суставов легли зеркально (при клевке голова
	-- отрывалась от шеи), корпус в полёте клонился назад, крылья раскрывались внутрь.
	-- Теперь рамка модели (вправо / вверх / назад) подгоняется по ФАКТИЧЕСКОМУ
	-- расположению деталей: вправо — от левого крыла к правому, вверх-вперёд — от
	-- торса к голове (в данных известно, под каким углом она стоит). Заодно отсюда
	-- же берётся масштаб. Проверка — по всем двенадцати деталям сразу.
	local rootCF = CFrame.new(torso.Position)
	do
		local wl, wr, head = parts.gull_wing_l, parts.gull_wing_r, parts.gull_head
		if wl and wr and head then
			local hm = Data.Parts.gull_head
			local hlen = math.sqrt(hm.Y * hm.Y + hm.Z * hm.Z)
			local cy, cz = hm.Y / hlen, hm.Z / hlen
			local function fit(right)
				local v = head.Position - torso.Position
				local a = v - right * v:Dot(right)
				local s = a.Magnitude / hlen
				local aU = a.Unit
				local n = right:Cross(aU)
				local frame = CFrame.fromMatrix(torso.Position, right, aU * cy - n * cz, aU * cz + n * cy)
				local err = 0
				for name, at in pairs(Data.Parts) do
					if parts[name] then
						err = math.max(err, (frame * (at * s) - parts[name].Position).Magnitude / s)
					end
				end
				return frame, s, err
			end
			local right = (wr.Position - wl.Position).Unit
			local fA, sA, eA = fit(right)
			local fB, sB, eB = fit(-right)
			if eB < eA then
				-- правое и левое поменялись местами: импорт отзеркалил модель
				warn("SeagullRig: модель приехала зеркальной (gull_wing_l справа) — клипы сыграют, но лево/право поменяются")
				fA, sA, eA = fB, sB, eB
			end
			rootCF, scale = fA, sA
			local look = fA.LookVector
			print(("SeagullRig: оси подогнаны, клюв по (%.2f, %.2f, %.2f) шаблона, масштаб %.3f, расхождение %.3f ед. модели")
				:format(look.X, look.Y, look.Z, sA, eA))
			if eA > 0.02 then
				warn("SeagullRig: детали стоят не так, как в SeagullRigData (расхождение " .. string.format("%.3f", eA)
					.. ") — FBX и данные от разных сборок? Пересоберите gull.py и переимпортируйте")
			end
		else
			warn("SeagullRig: нет крыльев или головы — оси модели взяты мировыми, суставы могут лечь не туда")
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Transparency = 1
		root.Parent = model
	end
	root.Size = Vector3.new(0.20, 0.27, 0.30) * scale   -- он же хитбокс: по нему попадают лучи и Touched
	root.CFrame = rootCF
	root.PivotOffset = CFrame.new(0, -Data.TorsoHeight * scale, 0)   -- пивот модели — В ЛАПАХ: PivotTo ставит птицу на точку
	root.Anchored = true                                -- чайку возят кинематически, присваивая root.CFrame
	root.CanCollide = false
	root.CanTouch = true
	root.CanQuery = true
	model.PrimaryPart = root

	local function joint(name, p0, p1, at)
		local world = rootCF * CFrame.new(at * scale)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:Inverse() * world
		m.C1 = p1.CFrame:Inverse() * world
		m.Parent = p0
	end
	joint("RootJoint", root, torso, Vector3.zero)
	for _, j in ipairs(Data.Joints) do
		local p0, p1 = parts[j.part0], parts[j.part1]
		if p0 and p1 then
			joint(j.joint, p0, p1, j.at)
		end
	end

	model:SetAttribute("RigScale", scale)   -- проигрывателю: сдвиги в клипах — в единицах модели
	return model, scale
end

return SeagullRig
