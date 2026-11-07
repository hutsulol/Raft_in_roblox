local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	ОСЬМИНОГ — клиентская половина: анимация щупалец.

	⚠️ ПОЧЕМУ ЭТО ВООБЩЕ НА КЛИЕНТЕ.
	Motor6D.Transform НЕ РЕПЛИЦИРУЕТСЯ. Roblox передаёт анимацию только через
	Animator, играющий загруженный AnimationTrack. Здешний осьминог анимируется
	процедурно — поворотами суставов, без опубликованных клипов, — значит крути мы
	их серверным скриптом, у игроков он висел бы неподвижно в позе покоя.
	Сами Motor6D при этом собирает СЕРВЕР: они инстансы и реплицируются, поэтому
	осьминог у всех собран одинаково, а расходится только движение.
	Симптом обманчивый: в Play Solo всё выглядит правильно, потому что сервер и
	клиент там один процесс. Поэтому каждый клиент держит СВОЙ экземпляр аниматора
	на той же модели и сам гоняет его в RenderStepped.

	Сервер (OctopusSpawner) сообщает по OctopusEvent только СОСТОЯНИЕ:
	  "emerge"   — всплыл, играем подъём и дальше плавание;
	  "hit"      — засчитан удар, кладём аддитивный вздрог поверх;
	  "break"    — разбит, играем разрушение;
	  "submerge" — уходит, играем погружение.
	Счётчик ударов и решения о смерти — его, здесь только картинка.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

-- Ждём не «ребёнка с именем», а «ребёнка, который подходит»: имена здесь
-- повторяются, и WaitForChild на них ловит не то.
local function waitFor(timeout, pick)
	local deadline = os.clock() + timeout
	while true do
		local found = pick()
		if found then return found end
		if os.clock() >= deadline then return nil end
		task.wait(0.2)
	end
end

-- ⚠️ ПАПКУ МОДУЛЕЙ ИЩЕМ ПО СОДЕРЖИМОМУ, А НЕ ПО ИМЕНИ.
-- WaitForChild("Octopus") отдаёт ПЕРВОГО ребёнка с этим именем, а их двое: папка
-- модулей и сама модель из 3D Importer. Порядок детей у сервера и у клиента
-- разный — сервер поднимался нормально, а здесь в логе висело «OctopusAnimator
-- не загрузился». Спрашиваем содержимое.
local folder = waitFor(30, function()
	for _, c in ipairs(ReplicatedStorage:GetChildren()) do
		if c:FindFirstChild("OctopusAnimator") then return c end
	end
	return nil
end)
if not folder then
	warn("[Осьминог/клиент] в ReplicatedStorage нет модулей рига — анимации не будет")
	return
end

-- pcall(require, …) вместо обёртки: так в лог попадает САМА ошибка модуля.
-- Прежняя строка «не загрузился» одинаково звучала и когда модуля нет, и когда
-- он падает при загрузке, — по ней нельзя было понять ничего.
local okAnim, Animator = pcall(require, folder.OctopusAnimator)
if not okAnim or not Animator then
	warn("[Осьминог/клиент] OctopusAnimator не загрузился: " .. tostring(Animator))
	return
end

-- ⚠️ КАНАЛ ИЩЕМ В ПАПКЕ, А НЕ ТОЛЬКО В КОРНЕ.
-- Сервер кладёт OctopusEvent рядом с модулями, внутрь ReplicatedStorage/Octopus.
-- Клиент ждал его в корне и не дожидался — в логе «нет OctopusEvent», а на экране
-- неподвижный осьминог. Рекурсивный поиск покрывает оба места.
local event = waitFor(20, function()
	return ReplicatedStorage:FindFirstChild("OctopusEvent", true)
end)
if not event then
	warn("[Осьминог/клиент] нет OctopusEvent — сервер не сможет сообщать состояния")
	return
end

-- ═══════════ живые экземпляры ═══════════
-- [модель] = { animator = ..., motors = ..., phase = ... }
local rigs = {}
local rigCount = 0

-- ═══════════ качка на волне ═══════════
-- ⚠️ ЭТО ИГРОВАЯ ПОДРОБНОСТЬ, А НЕ ЧАСТЬ РИГА.
-- У аниматора есть своё холостое покачивание, но оно про «висит в толще воды» —
-- сотые доли стада, на глаз ноль. Осьминог же торчит НА поверхности рядом с
-- плотом, и неподвижная туша рядом с качающейся водой читается как декорация.
-- Качку кладём здесь, поверх любого клипа: аниматор — общий модуль, понятия
-- «где вода» у него нет и заводить его там незачем.
local SWELL = {
	rise       = 0.75,   -- студов вверх-вниз на основной волне
	period     = 3.6,    -- секунд на волну
	chop       = 0.22,   -- мелкая рябь поверх, чтобы не читалось чистой синусоидой
	chopPeriod = 1.3,
	pitch      = 4.0,    -- градусов наклона на склоне волны
}

local function applySwell(rig, clock)
	local m = rig.motors and rig.motors.Root
	if not m then return end
	local a = clock * (2 * math.pi / SWELL.period) + rig.phase
	local b = clock * (2 * math.pi / SWELL.chopPeriod) + rig.phase * 2
	local y = math.sin(a) * SWELL.rise + math.sin(b) * SWELL.chop
	-- ⚠️ НАКЛОН БЕРЁМ ОТ СКОРОСТИ ПОДЪЁМА, А НЕ ОТ ВЫСОТЫ.
	-- Отсюда косинус: на гребне и во впадине тело ровное, а на склонах задрано
	-- или опущено. Наклон «по высоте» выглядел бы как качели, а не как волна.
	local pitch = math.cos(a) * SWELL.pitch
	-- ⚠️ ДОМНОЖАЕМ, А НЕ ПЕРЕЗАПИСЫВАЕМ.
	-- На Root уже лежит то, что положил клип: весь вертикальный ход Emerge и
	-- Submerge. Присваиванием мы стёрли бы всплытие и погружение целиком.
	m.Transform = m.Transform
		* CFrame.new(0, y, 0)
		* CFrame.Angles(math.rad(pitch), 0, math.rad(pitch * 0.35))
end

-- ⚠️ СОБИРАЕМ КАРТУ СУСТАВОВ, А НЕ КОСТЕЙ.
-- Осьминог переехал со скиннутого меша на жёсткий риг: теперь это 20 деталей,
-- связанных Motor6D (OCTOPUS_SETUP.md). Ключи в карте должны совпадать с именами
-- дорожек в клипах, а корневой сустав в клипах зовётся «Root», хотя сам инстанс
-- сервер называет «RootJoint» — эту одну подмену и делаем.
local function collectMotors(model)
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[(d.Name == "RootJoint") and "Root" or d.Name] = d
		end
	end
	return motors
end

-- ⚠️ СУСТАВЫ МОГУТ ПРИЕХАТЬ ПОЗЖЕ САМОЙ МОДЕЛИ.
-- Их создаёт сервер при сборке рига, и репликация не обязана привезти всё одним
-- пакетом; сигнал "emerge" идёт своим каналом и вполне может её обогнать.
local function attach(model)
	if rigs[model] then return rigs[model] end
	local motors = collectMotors(model)
	-- без корневого сустава клипы Emerge/Submerge двигать нечем: весь ход по
	-- вертикали лежит именно на нём
	if not motors.Root then return nil end

	-- фаза своя у каждого: два всплывших рядом не должны качаться в такт
	rigCount += 1
	local rig = {
		animator = Animator.new(motors),
		motors = motors,
		phase = (rigCount * 1.7) % (2 * math.pi),
	}
	rigs[model] = rig
	model.AncestryChanged:Connect(function()
		if not model.Parent then rigs[model] = nil end
	end)
	return rig
end

local function attachWhenReady(model, onReady)
	task.spawn(function()
		for _ = 1, 50 do            -- до ~5 секунд
			if not model.Parent then return end
			local rig = attach(model)
			if rig then
				if onReady then onReady(rig) end
				return
			end
			task.wait(0.1)
		end
		warn("[Осьминог/клиент] у модели так и не нашлось суставов Motor6D — "
			.. "риг на сервере не собрался?")
	end)
end

-- ═══════════ «вот сюда смотри» для самого первого ═══════════
-- ⚠️ ПОДСВЕТКУ БЕРЁМ ГОТОВУЮ, ИЗ ТРЕКЕРА КВЕСТОВ.
-- Зелёный контур со стрелкой над целью там уже сделан — им ведут к брёвнам и к
-- канистрам, и он умеет то, на чём эта затея спотыкается по третьему разу:
-- держаться над качающимся предметом, а не рядом с ним. Своя вторая такая же
-- означала бы два разных указателя в одной игре и второй такой же разбор
-- граблей. Подсветка идёт ПО ТИПУ ресурса, у осьминога это "Meat".
local GLOW_TYPE = "Meat"
local glowOn = false

local function setQuestGlow(on)
	if on == glowOn then return end
	if not _G.ResourceGlowSetEnabled then return end
	glowOn = on
	_G.ResourceGlowSetEnabled(GLOW_TYPE, on)
end

-- ═══════════ состояния от сервера ═══════════
event.OnClientEvent:Connect(function(state, model, first)
	if typeof(model) ~= "Instance" then return end

	if state == "emerge" then
		-- ⚠️ ЗАЖИГАЕМ ДО ТОГО, КАК ОСЬМИНОГ СТАНЕТ «Resource».
		-- Тег вешается только к концу всплытия — подсветка ловит его сама, через
		-- GetInstanceAddedSignal, и загорится ровно тогда, когда по нему можно бить.
		if first == true then setQuestGlow(true) end
		attachWhenReady(model, function(rig)
			-- Подъём, затем плавание. onBaseDone у аниматора одноразовый: он сам
			-- себя снимает, поэтому ставим заново на каждый переход.
			rig.animator:setBase("Emerge", 0)
			rig.animator.onBaseDone = function(name)
				if name ~= "Emerge" then return end
				rig.animator.onBaseDone = nil
				rig.animator:setBase("SwimIdle", 0.3)
			end
		end)
		return
	end

	-- Цель уходит — гасим указатель. Делаем это ДО проверки рига: если он у нас
	-- так и не собрался, стрелка иначе осталась бы висеть над пустой водой.
	if state == "break" or state == "submerge" then
		setQuestGlow(false)
	end

	local rig = rigs[model]
	if not rig then return end

	if state == "hit" then
		-- ⚠️ АДДИТИВНЫЙ СЛОЙ, А НЕ СМЕНА КЛИПА.
		-- Ударов сотня, и каждый должен ложиться ПОВЕРХ плавания, а не перебивать
		-- его. Разброс скорости — чтобы сто одинаковых вздрогов не читались как
		-- стрекот одной и той же дёрганой рамки.
		rig.animator:fire("Hit", 1 + math.random() * 0.25)
	elseif state == "break" then
		rig.animator.onBaseDone = nil
		rig.animator:setBase("BreakUp", 0.08)
	elseif state == "submerge" then
		rig.animator.onBaseDone = nil
		rig.animator:setBase("Submerge", 0.25)
	end
end)

-- ═══════════ покадровая работа ═══════════
-- ⚠️ ОДИН ОБЩИЙ ЦИКЛ НА ВСЕХ, А НЕ СОЕДИНЕНИЕ НА КАЖДОГО.
-- Каждый экземпляр со своим RenderStepped — это ровно тот случай, о котором
-- предупреждает бриф: на пятерых-шестерых осьминогах кадр начинает проседать.
local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	for model, rig in pairs(rigs) do
		if model.Parent then
			rig.animator:step(dt)
			applySwell(rig, clock)   -- строго ПОСЛЕ step: он перезаписывает Transform
		else
			rigs[model] = nil
		end
	end
end)

-- Осьминог мог всплыть до того, как этот скрипт поднялся (или игрок зашёл позже):
-- подхватываем всё, что уже плавает.
task.defer(function()
	for _, d in ipairs(Workspace:GetChildren()) do
		if d:IsA("Model") and d:GetAttribute("IsOctopus") then
			attachWhenReady(d, function(rig) rig.animator:setBase("SwimIdle", 0) end)
		end
	end
end)

print("[Осьминог/клиент] анимация готова: кости крутятся локально, состояния — с сервера")
