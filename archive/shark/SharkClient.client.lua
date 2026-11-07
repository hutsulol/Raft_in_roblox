--[[
	АКУЛА — клиентская половина: она и крутит суставы.

	⚠️ ПОЧЕМУ ЭТО ВООБЩЕ НА КЛИЕНТЕ.
	Motor6D.Transform НЕ РЕПЛИЦИРУЕТСЯ. Roblox передаёт анимацию только через
	Animator с загруженным AnimationTrack, а здешняя акула анимируется
	процедурно — поворотами суставов, без опубликованных клипов. Крути мы их
	серверным скриптом, у игроков она висела бы столбом в позе покоя, и В ЛОГЕ
	БЫЛО БЫ ТИХО. Сами Motor6D при этом собирает СЕРВЕР (SharkRig.setup): они
	инстансы и реплицируются, поэтому риг у всех одинаковый, а расходится только
	движение. В Play Solo разницы не видно — там сервер и клиент один процесс.

	Сервер сообщает только СОСТОЯНИЕ, атрибутами на модели:
	  Clip / ClipT           — цикл; пишется только при СМЕНЕ имени;
	  ClipOnce / ClipOnceT   — разовый; метка пишется КАЖДЫЙ раз.
	Разовые ловим ПО СМЕНЕ МЕТКИ, а не по наличию атрибута, иначе второй укус
	подряд не проиграется. Тот же протокол у пиратов, зверей и вышки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- ⚠️ ПАПКУ МОДУЛЕЙ ИЩЕМ ПО СОДЕРЖИМОМУ, А НЕ ПО ИМЕНИ.
-- WaitForChild("Shark") отдаёт ПЕРВОГО ребёнка с этим именем, а их может быть
-- двое: папка модулей и сама модель из 3D Importer. Порядок детей у сервера и
-- у клиента разный.
local folder
do
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		for _, c in ipairs(ReplicatedStorage:GetChildren()) do
			if c:FindFirstChild("SharkAnimator") then folder = c break end
		end
		if folder then break end
		task.wait(0.2)
	end
end
if not folder then
	warn("[Акула/клиент] в ReplicatedStorage нет модулей рига — анимации не будет")
	return
end

local Animator = require(folder.SharkAnimator)
local Data = require(folder.SharkRigData)

-- дорожка Root у Gnaw строится из точки шеи, а её знает только RigData
Animator.build(Data.Neck)

local JOINT_NAMES = { Root = true }
for _, j in ipairs(Data.Joints) do JOINT_NAMES[j.name] = true end
local WANT = 0
for _ in pairs(JOINT_NAMES) do WANT += 1 end

-- ⚠️ КЛЮЧ В КЛИПЕ ≠ ИМЯ ИНСТАНСА. Корневой сустав называется по роблоксовому
-- соглашению RootJoint, а дорожка в клипе — Root. Без этой карты корень просто
-- не находится: «привязано 4 из 5», и туша не качается, хотя хвост машет.
local ALIAS = { RootJoint = "Root" }

local bound = {}          -- model -> { animator, clipT, onceT }

--[[ ⚠️ СУСТАВЫ ДОЕЗЖАЮТ ПОЗЖЕ МОДЕЛИ.
     Сервер строит Motor6D при спавне, а клиент видит модель раньше, чем они
     доедут по репликации. Кэш с неполным списком раньше жил вечно — «0 из 5»
     оставалось навсегда. Поэтому: пока привязано не всё, пересобираем. ]]
local function collect(model)
	local motors = {}
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			local key = ALIAS[d.Name] or d.Name
			if JOINT_NAMES[key] then
				motors[key] = d
				n += 1
			end
		end
	end
	return motors, n
end

--[[ Имя цикла берём с модели, но только если такой базовый клип реально есть:
     атрибут ставит сервер, а опечатка в нём уронила бы клиент целиком на
     assert'е внутри setBase — вместе со всеми остальными акулами. ]]
local function baseName(model)
	local want = model:GetAttribute("Clip")
	if want and Animator.Clips[want] and not Animator.Clips[want].additive then
		return want
	end
	if want then
		warn(("[Акула] %s: неизвестный цикл %q — включаю Swim"):format(model.Name, want))
	end
	return "Swim"
end

local function attach(model)
	local motors, n = collect(model)
	if n == 0 then return nil end
	local a = Animator.new(motors)
	a:setBase(baseName(model), 0)
	print(("[Акула] %s: привязано суставов %d из %d%s"):format(
		model.Name, n, WANT,
		n < WANT and " — ждём остальные" or " — анимация пошла"))
	return { animator = a, motors = motors, count = n,
		clipT = model:GetAttribute("ClipT"), onceT = model:GetAttribute("ClipOnceT") }
end

local function pump(model, st, dt)
	-- досбор суставов, если в прошлый раз доехали не все
	if st.count < WANT then
		local motors, n = collect(model)
		if n > st.count then
			st.motors, st.count = motors, n
			st.animator.motors = motors
			print(("[Акула] %s: суставы доехали (%d из %d)"):format(model.Name, n, WANT))
		end
	end

	local clipT = model:GetAttribute("ClipT")
	if clipT ~= st.clipT then
		st.clipT = clipT
		st.animator:setBase(baseName(model))
	end

	local onceT = model:GetAttribute("ClipOnceT")
	if onceT ~= st.onceT then
		st.onceT = onceT
		local name = model:GetAttribute("ClipOnce")
		if name and Animator.Clips[name] and Animator.Clips[name].additive then
			st.animator:fire(name)
		end
	end

	st.animator:step(dt)
end

local function scan()
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("SharkRig") and not bound[m] then
			local st = attach(m)
			if st then bound[m] = st end
		end
	end
end

local since = 1
RunService.Heartbeat:Connect(function(dt)
	-- перескан троттлим: раз в секунду, а не каждый кадр
	since += dt
	if since >= 1 then
		since = 0
		scan()
	end
	for model, st in pairs(bound) do
		if model.Parent then
			pump(model, st, dt)
		else
			-- ⚠️ Труп надо распустить один раз: атрибут Clip остаётся с
			-- последнего тика ИИ, и цикл продолжал бы крутить суставы убитой.
			bound[model] = nil
		end
	end
end)
