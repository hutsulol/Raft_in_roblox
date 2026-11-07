-- Handles Bed crafting and placement with sleep behavior
local rs = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local PlaceCheck = require(game:GetService("ReplicatedStorage"):WaitForChild("PlaceCheck"))   -- «место занято» — общая проверка

local RaftShake = require(rs:WaitForChild("RaftShake"))

local BED_COOLDOWN = 3

-- ─── Модель кровати ───
-- Новая модель заказчика. Старое имя оставлено запасным: если новой в проекте не
-- окажется, кровать всё равно построится, а в консоли будет видно почему.
local BED_TEMPLATE     = "Raft_bed_leaf"
local BED_TEMPLATE_OLD = "Bed"

-- Высота лежащего считается ОТ ПИВОТА КРОВАТИ (центра её габарита), а не от
-- верхней грани: у листвяной кровати верх габарита проходит по гребням листьев, и
-- игрок висел заметно выше самого матраса. Ручка для «высоко / провалился».
local LIE_LIFT = 0.5

-- ⚠️ РАЗВОРОТ ГОЛОВОЙ В ДРУГУЮ СТОРОНУ.
-- Длинную ось кровати мы находим по габариту, но у неё нет «переда»: направление
-- выпадает то в изголовье, то в ноги, и игрок лежал вверх ногами. Флагом решаем,
-- в какую сторону вдоль кровати смотрит голова; сменить — поменять на false.
local LIE_FLIP = true

local cupActionEvent = rs:WaitForChild("CupAction")

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn("[Кровать] " .. msg)
end

-- ⚠️ ШАБЛОН ЗАБИРАЕМ ИЗ WORKSPACE, ЕСЛИ ОН ТАМ.
-- Новые модели заказчик кладёт прямо на карту, а клонировать надо из хранилища:
-- иначе шаблон так и лежит посреди плота, и его же видно в игре. Переносим один
-- раз при первом обращении — дальше он живёт в ReplicatedStorage, как остальные.
local function bedTemplate()
	local t = rs:FindFirstChild(BED_TEMPLATE) or rs:FindFirstChild(BED_TEMPLATE, true)
	if t then return t end

	local inWorld = workspace:FindFirstChild(BED_TEMPLATE)
		or workspace:FindFirstChild(BED_TEMPLATE, true)
	if inWorld then
		inWorld.Parent = rs
		print(("[Кровать] шаблон %s перенесён из Workspace в ReplicatedStorage")
			:format(BED_TEMPLATE))
		return inWorld
	end

	local old = rs:FindFirstChild(BED_TEMPLATE_OLD)
	if old then
		warnOnce("fallback", ("модели %s нет ни в ReplicatedStorage, ни в Workspace — "
			.. "ставится старая %s"):format(BED_TEMPLATE, BED_TEMPLATE_OLD))
		return old
	end
	warnOnce("none", "шаблона кровати нет вообще — ставить нечего")
	return nil
end

-- ⚠️ ПОЗУ СЧИТАЕМ ПО ГЕОМЕТРИИ КРОВАТИ, А НЕ ЗАШИВАЕМ УГЛАМИ.
-- Здесь стоял поворот, подобранный руками под старую модель
-- (CFrame.Angles(90°, 0, -90°)). У новой другие пропорции и другая ось, и тот же
-- поворот уложил бы игрока поперёк или в воздухе. Считаем: длинная горизонтальная
-- сторона — вдоль тела, верх габарита — поверхность матраса.
-- У корня персонажа LookVector это «куда смотрит», UpVector — «куда голова».
-- Лежащему на спине нужно смотреть в небо, а голову держать вдоль кровати, —
-- ровно это и просит CFrame.lookAt третьим аргументом.
local function lieCFrame(bed)
	local cf, size
	if bed:IsA("Model") then
		cf, size = bed:GetBoundingBox()
	elseif bed:IsA("BasePart") then
		cf, size = bed.CFrame, bed.Size
	else
		return nil
	end

	local along = (size.X >= size.Z) and cf.RightVector or cf.LookVector
	along = Vector3.new(along.X, 0, along.Z)
	if along.Magnitude < 0.01 then along = Vector3.new(0, 0, 1) end
	along = along.Unit
	if LIE_FLIP then along = -along end

	local pos = cf.Position + Vector3.new(0, LIE_LIFT, 0)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 1, 0), along)
end

-- ⚠️ ВСТАЁМ СТРОГО ВЕРТИКАЛЬНО И НАД КРОВАТЬЮ.
-- Подъём делался как `bedPart.CFrame * поворот + (0,5,0)`, то есть НАСЛЕДОВАЛ
-- ориентацию детали. У импортированного меша она произвольная (у грядки, скажем,
-- «тонкая ось» вообще оказалась не Y) — персонаж вставал лёжа или боком, тут же
-- заваливался и проваливался под палубу, где его добивала вода. Считаем позу с
-- нуля: точка над верхом габарита кровати, ось строго вертикальная.
-- Насколько встающий поднимается над верхом кровати. Ровно чтобы не оказаться
-- внутри её геометрии: больше — заметный прыжок с высоты.
local STAND_LIFT = 2.0

local function standCFrame(bed)
	local cf, size
	if bed:IsA("Model") then
		cf, size = bed:GetBoundingBox()
	elseif bed:IsA("BasePart") then
		cf, size = bed.CFrame, bed.Size
	else
		return nil
	end
	local pos = Vector3.new(
		cf.Position.X,
		cf.Position.Y + size.Y * 0.5 + STAND_LIFT,
		cf.Position.Z)
	-- смотрим вдоль кровати, но строго горизонтально
	local look = (size.X >= size.Z) and cf.RightVector or cf.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then look = Vector3.new(0, 0, 1) end
	return CFrame.lookAt(pos, pos + look.Unit)
end

-- ⚠️ АНИМАЦИЮ ГЛУШИТ КЛИЕНТ, СЕРВЕР ТОЛЬКО СТАВИТ ФЛАГ.
-- Первый заход останавливал дорожки прямо здесь — и это не работало в принципе:
-- анимации персонажа проигрывает ЕГО клиент, на сервере Animator их даже не
-- видит, поэтому GetPlayingAnimationTracks возвращал пусто, а бег продолжался.
-- Флаг Sleeping реплицируется, а по нему SleepPose.client глушит Animate у себя.
-- Отключение самого Animate дублируем и отсюда: свойство тоже реплицируется, и
-- если клиентский скрипт почему-то не поднялся, новых дорожек всё равно не будет.
local function setIdleAnimations(character, on)
	local animate = character:FindFirstChild("Animate")
	if animate then animate.Disabled = not on end
	character:SetAttribute("Sleeping", not on)
end

local function isNight()
	local clock = Lighting.ClockTime
	return clock >= 18 or clock < 6
end

local function getSleepingCount()
	local val = rs:FindFirstChild("SleepingPlayers")
	if not val then
		val = Instance.new("IntValue")
		val.Name = "SleepingPlayers"
		val.Value = 0
		val.Parent = rs
	end
	return val
end

-- ─── Setup bed behavior on a placed bed ───
-- ⚠️ ОДНА КРОВАТЬ — ОДИН НАБОР ОБРАБОТЧИКОВ.
-- Установка из рюкзака зовёт эту функцию сама, и ТУТ ЖЕ срабатывает подхват по
-- DescendantAdded (он нужен для кроватей из сохранения). Без метки на детали
-- обработчики вешались дважды, и у одной кровати оказывалось два независимых
-- состояния «кто сейчас спит» — с разными представлениями о том, лежит игрок или
-- уже встал.
local function setupBedBehavior(bedPart)
	if bedPart:GetAttribute("BedWired") then return end
	bedPart:SetAttribute("BedWired", true)
	local currentPlayer = nil
	local callbackHandler = nil

	local function standUp()
		if currentPlayer ~= nil and bedPart:FindFirstChild("BedWeld") then
			local sc = getSleepingCount()
			sc.Value = math.max(0, sc.Value - 1)

			local cooldownTag = Instance.new("StringValue", currentPlayer)
			cooldownTag.Name = "BedCooldown"
			game.Debris:AddItem(cooldownTag, BED_COOLDOWN)

			bedPart:FindFirstChild("BedWeld"):Destroy()

			if callbackHandler then
				callbackHandler:Disconnect()
				callbackHandler = nil
			end

			local hum = currentPlayer.Humanoid
			local hrp = currentPlayer.HumanoidRootPart

			-- ⚠️ СНАЧАЛА ОТЦЕПИТЬСЯ, ПОТОМ ДВИГАТЬСЯ. РАЗНЫМИ КАДРАМИ.
			-- Сварку мы уже сняли строкой выше, но физика узнаёт о распаде сборки
			-- только на следующем шаге. Перенос корня в том же кадре шёл ещё по
			-- СТАРОЙ сборке — и тянул за собой весь плот. Ждём кадр.
			task.wait()

			hum.PlatformStand = false
			setIdleAnimations(currentPlayer, true)

			local bedModel = bedPart:FindFirstAncestorOfClass("Model")
			local up = (bedModel and standCFrame(bedModel)) or standCFrame(bedPart)
			-- та же страховка, что и при укладывании: предок мог найтись не тот
			if up and (up.Position - bedPart.Position).Magnitude > 20 then
				up = standCFrame(bedPart)
			end
			if up then hrp.CFrame = up end

			-- ⚠️ ЗАБИРАЕМ СКОРОСТЬ ПЛОТА, А НЕ ВСТАЁМ НЕПОДВИЖНО.
			-- Плот идёт 8 студов/с. Персонаж, отцепившийся с нулевой скоростью,
			-- мгновенно отстаёт от палубы — со стороны это «встал и провалился мимо
			-- плота». Наследуем ход плота, как это делает установка построек.
			local raft = workspace:FindFirstChild("Raft")
			local primary = raft and raft.PrimaryPart
			hrp.AssemblyLinearVelocity = primary and primary.AssemblyLinearVelocity
				or Vector3.zero
			-- крутящий момент от лежачей позы гасим: иначе персонаж встаёт и тут же
			-- заваливается на бок
			hrp.AssemblyAngularVelocity = Vector3.zero

			-- ⚠️ СОСТОЯНИЕ ГУМАНОИДА ПЕРЕВОДИМ РУКАМИ.
			-- После PlatformStand гуманоид остаётся «упавшим» и поднимается сам,
			-- физически, около секунды — это и был наклон на 90° вперёд. Явный
			-- перевод в GettingUp и затем в Running ставит его на ноги сразу.
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.wait()
			if hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
			currentPlayer = nil
		end
	end

	local function layDown(character)
		if character == nil or bedPart:FindFirstChild("BedWeld") then return end
		if not isNight() then return end

		currentPlayer = character
		-- Позу берём у ВСЕЙ модели кровати, а не у одной детали: у меша пивот в
		-- центре габарита, а лечь надо по длинной стороне и на поверхность.
		local bedModel = bedPart:FindFirstAncestorOfClass("Model")
		local cf = (bedModel and lieCFrame(bedModel)) or lieCFrame(bedPart)

		-- ⚠️ ПРОВЕРЯЕМ, ЧТО ЛОЖИМСЯ У КРОВАТИ, А НЕ ГДЕ-ТО В ОКЕАНЕ.
		-- Модель-предок ищется по дереву, и если кровать окажется вложена не туда
		-- (например, прямо в Raft, без своей модели), габарит посчитается у ВСЕГО
		-- плота — а его центр может быть в десятках студов от кровати. Игрока при
		-- этом уносило далеко в воду. Дешёвая проверка расстояния ловит любой такой
		-- случай, откуда бы он ни взялся, и откатывает к самой детали кровати.
		if cf and (cf.Position - bedPart.Position).Magnitude > 20 then
			warn(("[Кровать] поза вышла в %.0f студов от кровати — считаем по самой детали")
				:format((cf.Position - bedPart.Position).Magnitude))
			cf = lieCFrame(bedPart)
		end
		if cf then
			currentPlayer.HumanoidRootPart.CFrame = cf
		end
		currentPlayer.Humanoid.PlatformStand = true
		setIdleAnimations(currentPlayer, false)

		local weld = Instance.new("WeldConstraint")
		weld.Name = "BedWeld"
		weld.Part0 = bedPart
		weld.Part1 = character.HumanoidRootPart
		weld.Parent = bedPart

		local sc = getSleepingCount()
		sc.Value = sc.Value + 1

		callbackHandler = currentPlayer.Humanoid.Changed:Connect(function(property)
			if currentPlayer ~= nil and property == "Jump" then
				standUp()
			end
		end)

		-- Auto stand up when night ends
		task.spawn(function()
			while currentPlayer ~= nil do
				if not isNight() then
					standUp()
					break
				end
				task.wait(0.5)
			end
		end)
	end

	bedPart.Touched:Connect(function(hit)
		local character = hit.Parent
		if character and character:FindFirstChild("Humanoid") and currentPlayer == nil and not character:FindFirstChild("BedCooldown") then
			layDown(character)
		end
	end)
end

-- ─── Placement handler ───
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeBed" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Bed" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end
	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = bedTemplate()
	if not template then return end

	local bed = template:Clone()
	-- Имя остаётся прежним: по нему кровать ищут сохранение плота, квест ночлега
	-- и подсказка. Модель заменилась, договорённость об имени — нет.
	bed.Name = "Bed"

	-- Remove existing scripts from clone
	for _, desc in bed:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Reset WorldPivot
	if bed:IsA("Model") then
		local bbCF = bed:GetBoundingBox()
		bed.WorldPivot = CFrame.new(bbCF.Position)
	end

	bed:PivotTo(worldCF)
	if PlaceCheck.refuseIfBlocked(bed, raft, player) then return end   -- в предмет ставить нельзя
	bed.Parent = raft

	-- Find the main part for bed behavior
	local bedPart = bed.PrimaryPart or bed:FindFirstChildWhichIsA("BasePart", true)

	-- T13/T15/T16: snapshot raft velocity, force-anchor every part
	-- (templates may be authored unanchored), weld while anchored,
	-- then unanchor in a third pass so the new parts inherit the
	-- raft's velocity through the rigid weld instead of starting at
	-- zero. Without these guards, placing the bed (~5 parts) drains
	-- enough momentum out of the raft assembly to kick the buoyancy
	-- spring into a sustained vertical bob.
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
	for _, part in bed:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel
	-- игрока на палубе сервером не удержать — просим его клиент (RaftShake)
	RaftShake.notify()

	-- Setup bed sleep behavior directly
	if bedPart then
		setupBedBehavior(bedPart)
	end

	tool:Destroy()
end)

-- ⚠️ КРОВАТЬ ИЗ СОХРАНЕНИЯ ТОЖЕ ДОЛЖНА РАБОТАТЬ.
-- setupBedBehavior висит только на установке из рюкзака, а RaftSaveSystem
-- восстанавливает кровать своим кодом и про эту функцию не знает. Из-за этого
-- после перезахода на свою же кровать лечь было нельзя. Ловим появление любой
-- модели "Bed" на плоту — и ту, что вернуло сохранение, и ту, что поставит
-- второй игрок.
local wired = setmetatable({}, { __mode = "k" })
local function wireBed(inst)
	if inst.Name ~= "Bed" or wired[inst] then return end
	if not inst:IsDescendantOf(workspace) then return end
	local part = (inst:IsA("Model") and (inst.PrimaryPart
		or inst:FindFirstChildWhichIsA("BasePart", true)))
		or (inst:IsA("BasePart") and inst)
	if not part then return end
	wired[inst] = true
	setupBedBehavior(part)
end

task.defer(function()
	local raft = workspace:FindFirstChild("Raft")
	if raft then
		for _, d in ipairs(raft:GetChildren()) do wireBed(d) end
	end
end)
workspace.DescendantAdded:Connect(function(d)
	if d.Name == "Bed" then task.defer(wireBed, d) end
end)