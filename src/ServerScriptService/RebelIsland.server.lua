--[[
	ПОВСТАНЦЫ НА ЗАЧИЩЕННОМ ОСТРОВЕ.

	Пираты выбиты — на их посты выходят повстанцы и живут там: ходят между
	точками, переговариваются, тренируются с оружием. Это не гарнизон и не бой:
	они свои, их нельзя ни поджечь, ни ударить, и сами они ни на кого не лезут.

	⚠️ АНИМАЦИИ БЕЗ ПУБЛИКАЦИИ, ПО ТОЙ ЖЕ СХЕМЕ, ЧТО У ПИРАТОВ.
	ROBLOX_INTEGRATION.md (раздел 7) говорит прямо: R6-клипы из FBX Roblox не
	импортирует, единственный путь — KeyframeSequence из таблицы. У нас эта
	таблица уже есть (PirateCrewClips), и все 20 клипов Rebel* в неё влиты.
	Поэтому сервер лишь называет клип атрибутом, а позу считает каждый клиент
	(PirateIslandAnim) — публиковать и вписывать id не нужно вовсе.

	⚠️ НАБОР КЛИПОВ ЗАВИСИТ ОТ ОРУЖИЯ.
	У Кая и Лены сабли, у остальных винтовки. Стрелку нужны прицеливание,
	выстрел и перезарядка, мечнику — взмах; перепутать значит получить бойца,
	который целится пустой рукой.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))

local LOG = "[Повстанцы]"
local FOLDER = "Rebels"        -- папка внутри острова; её же обходит клиентский аниматор

-- Кто выходит и с чем. Порядок держим: первым идёт Кай, он же встаёт на место
-- капитана — пост у ворот заметнее прочих.
local CREW = {
	{ name = "Rebel_Kai",   melee = true  },
	{ name = "Rebel_Lena",  melee = true  },
	{ name = "Rebel_Bram",  melee = false },
	{ name = "Rebel_Diego", melee = false },
	{ name = "Rebel_Mara",  melee = false },
	{ name = "Rebel_Tomas", melee = false },
}

--[[ ⚠️ ВЫХОДЯТ НЕ ВСЕ ШЕСТЕРО, А ПЕРВЫЕ ДВОЕ.
     Шесть человек на маленьком острове — это толпа: они ходят, переговариваются
     и жестикулируют одновременно, и вместо «люди вернулись на свою землю»
     получается митинг. Двоих хватает, чтобы остров перестал быть пустым.
     Список оставлен целиком: он же задаёт ПОРЯДОК, а первыми в нём стоят Кай и
     Лена — те, кого игрок и так встречает по сюжету. Понадобится больше —
     меняется одно число, а не состав. ]]
local CREW_LIMIT = 2

-- Клипы по роли. Простой (idle) и «действия» разведены: действия играются
-- изредка поверх простоя, иначе шестеро в кадре двигаются как один механизм.
local SETS = {
	melee = {
		idle   = { "RebelIdle", "RebelIdleRest" },
		walk   = "RebelWalk",
		run    = "RebelRun",
		action = { "RebelMacheteSwing", "RebelTalk", "RebelPoint", "RebelGreet", "RebelCheer" },
	},
	rifle = {
		idle   = { "RebelIdle", "RebelIdleAlert" },
		walk   = "RebelWalk",
		run    = "RebelRun",
		action = { "RebelAim", "RebelFire", "RebelReload", "RebelTalk", "RebelPoint", "RebelBeckon" },
	},
}

local WALK_SPEED   = 8
local WANDER_RADIUS = 26     -- как далеко от своей точки отходит
local IDLE_MIN, IDLE_MAX = 3.5, 9      -- сколько стоит между переходами
local ACTION_CHANCE = 0.45   -- шанс, что вместо простого стояния сыграет действие

-- ── приветствие проходящему игроку ──
-- ⚠️ РЕДКО И ПО КУЛДАУНУ НА КАЖДОГО. Приветствие — это жест уважения, а не
-- реакция автомата: если играть его при каждом проходе, шестеро повстанцев
-- превратят остров в балаган из поклонов. Раз в две минуты на человека.
local GREET_RADIUS = 14
local GREET_EVERY  = 120
local GREET_CLIPS  = { "RebelGreet", "RebelCheer", "RebelPoint" }

local function nearbyPlayer(pos)
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - pos).Magnitude <= GREET_RADIUS then return hrp end
	end
	return nil
end

local live = {}   -- [island] = { модели }

local function findTemplate(name)
	for _, where in ipairs({ ReplicatedStorage, Workspace }) do
		local m = where:FindFirstChild(name)
		if m and m:IsA("Model") then return m end
	end
	return nil
end

-- ⚠️ ТОЧКИ БЕРЁМ ТЕ ЖЕ, ЧТО У ГАРНИЗОНА, А НЕ ВСЕ ПОДРЯД.
-- Первый заход хватал любую деталь с приставкой pt_ и селил повстанцев по
-- первым шести в порядке обхода дерева — вышло не на постах пиратов, а где
-- попало. Пост опознаётся по имени маркера (Defs.postName) и должен быть в
-- POST_CREW: ровно те места, где стояла охрана.
-- ⚠️ ОСТРОВА НАЗЫВАЮТ ПОСТЫ ПО-РАЗНОМУ, ПОЭТОМУ ИСТОЧНИКОВ ТРИ.
-- Пиратский остров держит посты из POST_CREW (Gate, Jetty, Tower_North…), а
-- терраса — свои (Pt_Farmer, Pt_Guard, Pt_Hauler…), которых в том списке нет.
-- Первый заход требовал именно POST_CREW и на террасе не находил НИЧЕГО:
-- «нет точек pt_* — селить некуда». Идём по порядку и берём первое, что есть:
--   1) маркеры известных постов — самое точное;
--   2) любые pt_-маркеры острова;
--   3) места, где лежат убитые пираты — буквально «на месте пиратов».
local function garrisonPoints(island)
	local known, any = {}, {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #Defs.MARKER_PREFIX) == Defs.MARKER_PREFIX then
			local post = Defs.postName(d.Name) or d.Name
			table.insert(any, { post = post, pos = d.Position })
			if Defs.POST_CREW[post] then
				table.insert(known, { post = post, pos = d.Position })
			end
		end
	end

	local pts = (#known > 0) and known or any
	local source = (#known > 0) and "посты гарнизона" or "маркеры острова"

	if #pts == 0 then
		-- ни одного маркера: берём тела выбитой охраны
		local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
		if enemies then
			for _, m in ipairs(enemies:GetChildren()) do
				if m:IsA("Model") then
					local ok, cf = pcall(function() return m:GetPivot() end)
					if ok then table.insert(pts, { post = m.Name, pos = cf.Position }) end
				end
			end
			source = "места убитых пиратов"
		end
	end

	-- порядок обхода дерева случаен — фиксируем по имени, чтобы расстановка была
	-- одинаковой от запуска к запуску
	table.sort(pts, function(a, b) return a.post < b.post end)
	return pts, source
end

local function groundAt(pos, island)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { island:FindFirstChild(FOLDER) }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or pos.Y
end

-- ⚠️ НАГРУДНИК ЖИВЁТ НА ТОРСЕ, А НЕ НА ГОЛОВЕ.
-- ROBLOX_INTEGRATION.md, раздел 4: косынку и нагрудник вешать именно на торс —
-- «на голове они поедут вместе с ней». Ровно это и было видно: жилет крутился
-- с головой и въезжал в грудь. Точку крепления в модели переименовываем в
-- BodyFrontAttachment, а сам аксессуар переподключаем — Roblox приваривает
-- аксессуар в момент, когда тот попадает в персонажа, поэтому его надо вынуть
-- и вернуть, иначе новое имя ничего не изменит.
local PLATE_HINTS = { "plate", "armour", "armor", "vest", "chest" }

local function fixPlate(model)
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
	if not torso then return end

	local front = torso:FindFirstChild("BodyFrontAttachment")
	if not front then
		front = Instance.new("Attachment")
		front.Name = "BodyFrontAttachment"
		front.Position = Vector3.new(0, 0.2, -0.55)   -- стандартная точка R6
		front.Parent = torso
	end

	for _, acc in ipairs(model:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local key = (acc.Name .. " " .. (handle and handle.Name or "")):lower()
			local isPlate = false
			for _, hint in ipairs(PLATE_HINTS) do
				if key:find(hint, 1, true) then isPlate = true break end
			end
			local att = handle and handle:FindFirstChildWhichIsA("Attachment")
			if isPlate and att and att.Name ~= "BodyFrontAttachment" then
				acc.Parent = nil
				att.Name = "BodyFrontAttachment"
				pcall(function() acc.AccessoryType = Enum.AccessoryType.Front end)
				acc.Parent = model
			end
		end
	end
end

local function setClip(model, name, once)
	if once then
		model:SetAttribute("ClipOnce", name)
		model:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
	else
		model:SetAttribute("Clip", name)
		model:SetAttribute("ClipT", Workspace:GetServerTimeNow())
	end
end

-- Один повстанец: стоит, изредка что-то делает, потом переходит на новое место
-- рядом со своей точкой. Никакой агрессии и никаких целей — это фон, а не бой.
local function runRebel(model, home, set)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	local hrp = (hum and hum.RootPart) or model:FindFirstChild("HumanoidRootPart", true)
	if not (hum and hrp) then return end

	hum.WalkSpeed = WALK_SPEED
	-- ⚠️ ШТАТНЫЙ Animate ГЛУШИМ. ROBLOX_INTEGRATION.md, раздел 7: клипы играются
	-- вручную, и стандартные состояния Humanoid их перебивают.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then d.Disabled = true end
	end

	-- приветствие: своя ветка, чтобы не ждать конца перехода — иначе поклон
	-- прилетал бы через полминуты после того, как игрок прошёл мимо
	task.spawn(function()
		local nextGreet = 0
		while model.Parent and hum.Health > 0 do
			task.wait(1)
			if os.clock() >= nextGreet then
				local target = nearbyPlayer(hrp.Position)
				if target then
					nextGreet = os.clock() + GREET_EVERY
					-- поворачиваемся к нему: приветствие спиной читается как насмешка
					local to = Vector3.new(target.Position.X - hrp.Position.X, 0,
						target.Position.Z - hrp.Position.Z)
					if to.Magnitude > 0.5 then
						hum:MoveTo(hrp.Position)   -- остановиться на месте
						hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + to.Unit)
					end
					setClip(model, GREET_CLIPS[math.random(#GREET_CLIPS)], true)
				end
			end
		end
	end)

	task.spawn(function()
		while model.Parent and hum.Health > 0 do
			setClip(model, set.idle[math.random(#set.idle)])
			task.wait(IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN))
			if not (model.Parent and hum.Health > 0) then break end

			if math.random() < ACTION_CHANCE then
				setClip(model, set.action[math.random(#set.action)], true)
				task.wait(1.6)
			else
				-- переход: точка в круге вокруг своей, высота — по земле
				local a = math.random() * math.pi * 2
				local r = 6 + math.random() * WANDER_RADIUS
				local goal = home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				goal = Vector3.new(goal.X, groundAt(goal, model.Parent.Parent) + 3, goal.Z)
				setClip(model, set.walk)
				hum:MoveTo(goal)
				local t0 = os.clock()
				repeat task.wait(0.2)
				until (hrp.Position - goal).Magnitude < 5 or os.clock() - t0 > 7
					or not model.Parent or hum.Health <= 0
			end
		end
	end)
end

local function spawnRebels(island)
	if not island or live[island] then return end
	local pts, source = garrisonPoints(island)
	if #pts == 0 then
		warn(LOG .. " на острове " .. island.Name
			.. " не нашлось ни маркеров, ни тел охраны — селить некуда")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = island

	local placed = {}
	for i, entry in ipairs(CREW) do
		if #placed >= CREW_LIMIT then break end
		local tpl = findTemplate(entry.name)
		if not tpl then
			warn(LOG .. " модель «" .. entry.name .. "» не найдена в ReplicatedStorage/Workspace")
		else
			local pos = pts[((i - 1) % #pts) + 1].pos
			local m = tpl:Clone()
			m.Name = entry.name
			m.Parent = folder

			-- ⚠️ СНИМАЕМ ЯКОРЬ. Модели стоят в мире декорацией, то есть
			-- заякоренными, и клон приходит таким же: анимация шага играет, а
			-- человек стоит на месте. Ровно это и было видно.
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = (d.Name == "HumanoidRootPart")
				end
			end

			-- ставим на землю и разворачиваем к центру острова: так шестеро не
			-- смотрят в одну сторону, как строй
			local ground = groundAt(pos, island)
			local look = island:GetPivot().Position
			local from = Vector3.new(pos.X, ground + 3, pos.Z)
			pcall(function()
				m:PivotTo(CFrame.lookAt(from, Vector3.new(look.X, from.Y, look.Z)))
			end)

			fixPlate(m)   -- жилет на торс, пока модель ещё не ожила

			-- свои: ни огнемёт, ни прочие системы их не трогают
			m:SetAttribute("Friendly", true)
			m:SetAttribute("HomeX", pos.X)
			m:SetAttribute("HomeZ", pos.Z)

			local hum = m:FindFirstChildWhichIsA("Humanoid", true)
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.NameDisplayDistance = 0
				hum.HealthDisplayDistance = 0
			end

			runRebel(m, Vector3.new(pos.X, ground, pos.Z), SETS[entry.melee and "melee" or "rifle"])
			table.insert(placed, m)
		end
	end

	live[island] = placed
	print(("%s вышли на остров %s: %d человек, точки — %s (%d шт.)")
		:format(LOG, island.Name, #placed, source, #pts))
end

--[[ ⚠️ ОБРАБОТЧИК ЗАЧИСТКИ НЕ ПЕРЕЗАПИСЫВАЕМ, А ДОБАВЛЯЕМ СВОЙ ЗВЕНОМ.
     _G.OnIslandCleared один на всю игру, и слушателей у него уже несколько
     (карта, сценарий аванпоста). Голое присваивание молча выбрасывало чужой
     обработчик — кто именно останется, решал порядок загрузки скриптов, а он
     в Roblox не определён. Держим предыдущий и зовём его вместе со своим. ]]
local prevCleared = _G.OnIslandCleared
_G.OnIslandCleared = function(island)
	if typeof(prevCleared) == "function" then
		local ok, err = pcall(prevCleared, island)
		if not ok then warn(LOG .. " предыдущий обработчик зачистки: " .. tostring(err)) end
	end
	if typeof(island) ~= "Instance" then return end
	-- ждём конца катсцены: повстанцы должны выйти на пустой остров, а не
	-- появиться в кадре поверх падающих пиратов
	task.delay(6, function()
		if island.Parent then spawnRebels(island) end
	end)
end

-- остров уплыл — забываем про него
task.spawn(function()
	while true do
		task.wait(20)
		for island in pairs(live) do
			if not island.Parent then live[island] = nil end
		end
	end
end)

print(LOG .. " готов: выходят на зачищенный остров, клипы Rebel* без публикации")
