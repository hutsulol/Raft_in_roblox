--[[
	SharkRig — сваривает пять MeshPart'ов акулы в скелет из Motor6D.

		ReplicatedStorage/Shark/
			SharkRig        <- этот файл
			SharkRigData    <- сгенерирован build_shark2.py
			SharkAnimator
			Model           <- Model из Shark2.fbx (5 MeshPart)

		-- на СЕРВЕРЕ:
		local Rig = require(ReplicatedStorage.Shark.SharkRig)
		local shark = Rig.spawn(CFrame.new(0, 4, -60))
		shark:setClip("Swim")
		shark:notice()      -- заметила игрока
		shark:attack()      -- рывок с пастью
		shark:gnaw()        -- вцепилась в плот (цикл)

	Только жёсткие детали. Ничего не скинится и ничего не масштабируется на ходу:
	каждый клип — это повороты целых частей на суставах. Ровно это одинаково
	работает и в Studio, и на живом сервере, и на каждом клиенте.

	Скелет плоский: корпус — корень, от него вперёд голова (а от головы челюсть)
	и назад хвостовая секция с хвостом. Сегменты входят друг в друга с нахлёстом
	~0.2 стада, поэтому сустав на повороте не открывает щель.

	⚠️ РАЗДЕЛЕНИЕ СЕРВЕР/КЛИЕНТ. Сами Motor6D — инстансы, они реплицируются,
	поэтому собирает их СЕРВЕР. А Motor6D.Transform НЕ реплицируется, поэтому
	крутит суставы КАЖДЫЙ КЛИЕНТ у себя (SharkClient). Серверная половина только
	называет клип атрибутами Clip / ClipOnce, как у пиратов и зверей.
	В Play Solo разницы не видно — там сервер и клиент один процесс.
]]

local RunService = game:GetService("RunService")

local Data = require(script.Parent.SharkRigData)
local Animator = require(script.Parent.SharkAnimator)

-- дорожка Root у Gnaw строится из точки шеи, а её знает только RigData
Animator.build(Data.Neck)

local Rig = {}
Rig.__index = Rig

--[[ Смещения в RigData записаны в стадах для того импорта, которым их считали.
     Привезли модель крупнее или мельче — они уедут ровно во столько же раз.
     Масштаб считаем по самим деталям: их габариты в таблице тоже есть. ]]
local function importScale(parts)
	local sum, n = 0, 0
	for name, p in pairs(parts) do
		local want = Data.Parts[name] and Data.Parts[name].size
		if want and want.Magnitude > 1e-3 then
			sum += p.Size.Magnitude / want.Magnitude
			n += 1
		end
	end
	return (n > 0) and (sum / n) or 1
end

--[[ Превращает свежеимпортированную Model в риг. Безопасно звать на клоне.

     ⚠️ ОБЯЗАТЕЛЕН ТОЛЬКО КОРПУС, ОСТАЛЬНОЕ — ПО НАЛИЧИЮ.
     3D Importer вполне может не привезти мелочь, и терять из-за неё всю тушу
     несоразмерно: чего нет, того просто нет — сустав не создаётся, аниматор
     такую дорожку не находит и молча её пропускает. ]]
function Rig.setup(model: Model)
	local parts, missing = {}, {}
	for name in pairs(Data.Parts) do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = true
			p.Massless = true
			parts[name] = p
		else
			table.insert(missing, name)
		end
	end
	local body = parts[Data.Root]
	assert(body, "SharkRig: нет корневой детали " .. Data.Root)

	-- ⚠️ ПОЗУ ЗАПОМИНАЕМ ДО ПЕРВОГО СУСТАВА.
	-- По ней ниже считаются C1, а уже созданный сустав может подвинуть деталь —
	-- если модель к этому моменту в Workspace, замеры следующих звеньев поедут
	-- одно за другим. Снимок делает порядок сборки неважным.
	local rest = {}
	for name, p in pairs(parts) do rest[name] = p.CFrame end

	if #missing > 0 then
		table.sort(missing)
		warn("SharkRig: собран без деталей — " .. table.concat(missing, ", ")
			.. " (импортёр их не привёз; на остальное не влияет)")
	end

	-- Motor6D поверх сварки — это заклиненная деталь, а не сустав
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(1, 1, 1)
		root.Transparency = 1
		root.CanCollide = false
		root.CanQuery = false
		-- ⚠️ КОРЕНЬ СТАВИМ РОВНО ПО МИРУ, А НЕ ПО ПОВОРОТУ КОРПУСА.
		-- Всё, что кладётся на RootJoint, считается в осях ЭТОГО парта: и качка,
		-- и рывок при укусе. Возьми мы поворот корпуса (а импортёр разворачивает
		-- детали как ему удобно) — «вверх» поехало бы вбок. Поворот корпуса при
		-- этом не теряется: он уходит в C1 ниже.
		root.CFrame = CFrame.new(rest[Data.Root].Position)
		root.Parent = model
	end
	-- ⚠️ Заякоренная деталь ИГНОРИРУЕТ Motor6D. Якорь только на корне, всё
	-- остальное свободно, иначе половина рига стоит неподвижно.
	root.Anchored = true

	local motors = {}
	local rj = Instance.new("Motor6D")
	rj.Name = "RootJoint"
	rj.Part0, rj.Part1 = root, body
	rj.C1 = rest[Data.Root]:ToObjectSpace(root.CFrame)
	rj.Parent = root
	motors.Root = rj

	-- ⚠️ ТОЧКУ ВРАЩЕНИЯ БЕРЁМ ИЗ ДАННЫХ, А ПОЗУ ПОКОЯ — С САМОЙ МОДЕЛИ.
	-- Motor6D не «запоминает, где деталь стояла»: он ДВИГАЕТ Part1, пока не
	-- сойдётся Part0.CFrame * C0 == Part1.CFrame * C1. Пара чистых сдвигов
	-- требует вдобавок, чтобы обе детали смотрели ОДИНАКОВО, — а импортёр
	-- привозит каждую со своим поворотом, и детали слетаются в кучу под чужими
	-- углами. Поэтому из таблицы берём только C0, а C1 замеряем по текущей позе.
	local scale = importScale(parts)
	if math.abs(scale - 1) > 0.05 then
		print(("SharkRig: масштаб импорта ×%.3f — смещения суставов пересчитаны")
			:format(scale))
	end

	local maxDrift = 0
	for _, j in ipairs(Data.Joints) do
		local child = parts[j.part1]
		local parent = parts[j.part0]
		if child and parent then
			local childRest, parentRest = rest[j.part1], rest[j.part0]
			local m = Instance.new("Motor6D")
			m.Name = j.name
			m.Part0, m.Part1 = parent, child
			m.C0 = CFrame.new(j.c0 * scale)
			m.C1 = childRest:ToObjectSpace(parentRest * m.C0)
			m.Parent = parent
			motors[j.name] = m
			-- насколько замеры генератора расходятся с тем, как модель реально
			-- собрана: расходятся сильно — точка вращения не там
			local a = (parentRest * CFrame.new(j.c0 * scale)).Position
			local b = (childRest * CFrame.new(j.c1 * scale)).Position
			maxDrift = math.max(maxDrift, (a - b).Magnitude)
		end
	end
	if maxDrift > 0.5 then
		warn(("SharkRig: замеры суставов расходятся с моделью до %.2f стада — "
			.. "поза покоя правильная, но точки вращения смещены; перегенерируй "
			.. "SharkRigData под этот импорт"):format(maxDrift))
	end
	model.PrimaryPart = root

	local built = {}
	for name in pairs(motors) do table.insert(built, name) end
	table.sort(built)
	print(("[Акула] риг собран: %d суставов (%s), дрейф %.2f стада")
		:format(#built, table.concat(built, ", "), maxDrift))

	-- по этому атрибуту клиент находит акул в мире; ставим ПОСЛЕДНИМ, когда
	-- суставы уже на месте, иначе клиент привяжется к недособранной модели
	model:SetAttribute("SharkRig", true)

	return setmetatable({ model = model, root = root, parts = parts,
		motors = motors, clip = nil }, Rig)
end

--[[ Клонирует Model, лежащую рядом с модулем, и ставит её на место.
     ⚠️ Риг собирается ДО перемещения: C1 снимаются с авторской позы клона. ]]
function Rig.spawn(cframe: CFrame, parent: Instance?)
	local template = script.Parent:FindFirstChild("Model")
	assert(template, "SharkRig: рядом с модулем нет Model")
	local model = template:Clone()
	local shark = Rig.setup(model)
	model.Parent = parent or workspace
	model:PivotTo(cframe)
	return shark
end

--[[ Цикл. Сервер пишет ИМЯ, позу считает клиент — Transform не реплицируется.
     Атрибут трогаем только при СМЕНЕ имени: запись каждый кадр гонит по сети
     мусор, а клиент всё равно смотрит на имя. ]]
function Rig:setClip(name: string)
	if self.clip == name then return end
	self.clip = name
	self.model:SetAttribute("Clip", name)
	self.model:SetAttribute("ClipT", os.clock())
end

--[[ Разовый укус. Метку пишем КАЖДЫЙ раз, даже если имя то же: клиент ловит
     разовые по смене метки, а не по наличию атрибута — иначе второй укус
     подряд не проиграется. ]]
function Rig:fireOnce(name: string)
	self.model:SetAttribute("ClipOnce", name)
	self.model:SetAttribute("ClipOnceT", os.clock())
end

function Rig:attack()
	self:fireOnce("Attack")
end

function Rig:notice()
	self:fireOnce("Notice")
end

--[[ Вцепилась в плот: пасть держит, туша мотается вокруг неё. Это ЦИКЛ, а не
     разовый — держится, пока не позовут setClip("Swim"). ]]
function Rig:gnaw()
	self:setClip("Gnaw")
end

--[[ Кинематическое перемещение: корень заякорен, физика его не двигает. ]]
function Rig:moveTo(cframe: CFrame)
	self.model:PivotTo(cframe)
end

function Rig:destroy()
	self.model:Destroy()
end

--[[ Локальный прогон — для теста в Studio без клиентской половины. На живом
     сервере НЕ звать: Transform отсюда никуда не уедет. ]]
function Rig:bindLocal()
	assert(RunService:IsClient(), "SharkRig:bindLocal — только на клиенте")
	if self.conn then return end
	self.animator = self.animator or Animator.new(self.motors)
	self.animator:setBase("Swim", 0)
	self.conn = RunService.Heartbeat:Connect(function(dt)
		self.animator:step(dt)
	end)
end

return Rig
