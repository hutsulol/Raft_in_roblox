--[[
	АНИМАЦИЯ ПИРАТОВ И ЖИВНОСТИ ОСТРОВА — НА КЛИЕНТЕ.

	⚠️ ПОЧЕМУ ИМЕННО ЗДЕСЬ, А НЕ НА СЕРВЕРЕ.
	Motor6D.Transform с сервера НЕ реплицируется: движок шлёт клиентам состояние
	Animator'а, а не само поле. Поза, посчитанная на сервере, видна одному серверу —
	со стороны игрока пираты стоят столбами, и в логе при этом тихо, потому что
	формально всё отработало. Поэтому сервер только объявляет, ЧТО играть (атрибуты
	Clip / ClipOnce на модели), а позу считает каждый клиент у себя.

	ЛЮДИ (пираты, пленные): атрибут несёт ИМЯ КЛИПА из PirateCrewClips напрямую,
	играет CrewClips.

	ЖИВОТНЫЕ (новые Motor6D-риги «Cow» / «Chicken»): атрибут несёт АБСТРАКТНОЕ
	состояние (Idle/Walk/Run/Eat + React разово) — в клип конкретного рига его
	переводит карта clips из Defs.ANIMAL_LIFE, а играют CowAnimator /
	ChickenAnimator. Публикация анимаций не нужна: клипы лежат таблицами в
	ReplicatedStorage и приезжают клиенту вместе с игрой.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local CrewClips       = require(ReplicatedStorage:WaitForChild("CrewClips"))
local ChickenAnimator = require(ReplicatedStorage:WaitForChild("ChickenAnimator"))
local CowAnimator     = require(ReplicatedStorage:WaitForChild("CowAnimator"))
local SheepAnimator   = require(ReplicatedStorage:WaitForChild("SheepAnimator"))
local Defs            = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))

-- Какие Motor6D нужны проигрывателю каждого рига. Ключ — имя в данных клипа,
-- значение — имя сустава в модели (их создаёт CowRig / ChickenRig при спавне).
local ANIMAL_MOTORS = {
	Chicken = { Root = "RootJoint", Neck = "Neck", WingL = "WingL", WingR = "WingR",
		HipL = "HipL", HipR = "HipR" },
	Cow = { Torso = "RootJoint", Head = "Neck", LegFL = "HipFL", LegFR = "HipFR",
		LegRL = "HipRL", LegRR = "HipRR", Tail = "TailJoint" },
	-- овца фермы (SheepRig): туша, шерсть, голова, четыре ноги
	Sheep = { Torso = "RootJoint", Head = "Neck", LegFL = "HipFL",
		LegFR = "HipFR", LegRL = "HipRL", LegRR = "HipRR" },
}
-- ⚠️ У ОВЦЫ ОБЯЗАТЕЛЕН ТОЛЬКО КОРЕНЬ. Риг может быть авторским (25 деталей,
-- SheepRig лишь переименовывает суставы по ролям), и какой-то ноги по имени
-- может не найтись — без этого списка проигрыватель ждал бы ВСЕ суставы и
-- не анимировал овцу вовсе.
local ANIMAL_REQUIRED = { Sheep = { Torso = true } }
local ANIMAL_PLAYER = { Chicken = ChickenAnimator, Cow = CowAnimator, Sheep = SheepAnimator }

-- ── адаптер животного ──
-- Переводит абстрактные состояния в клипы рига и следит, чтобы разовая реакция
-- (React) не была задавлена цикловым состоянием: цикл вернётся, когда реакция
-- доиграет. Суставы могут доехать к клиенту позже модели — перепроверяем раз в
-- секунду, как CrewClips у пиратов.
local function attachAnimal(model, kind)
	local map = ANIMAL_MOTORS[kind]
	local clipsMap = (Defs.ANIMAL_LIFE[kind] or {}).clips or {}

	local a = {
		motors = {},        -- заполняется по мере репликации; аниматор держит ссылку
		missing = true,
		rescanT = 0,
		onceActive = false,
		wantLoop = nil,
		lastOnceT = nil,
	}
	local function rescan()
		local total, found = 0, 0
		for key, motorName in pairs(map) do
			total += 1
			if not (a.motors[key] and a.motors[key].Parent) then
				a.motors[key] = nil
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Motor6D") and d.Name == motorName then
						a.motors[key] = d
						break
					end
				end
			end
			if a.motors[key] then found += 1 end
		end
		a.missing = found < total
		local req = ANIMAL_REQUIRED[kind]
		if req then
			a.missing = false
			for key in pairs(req) do
				if not a.motors[key] then a.missing = true end
			end
		end
	end
	rescan()
	a.anim = ANIMAL_PLAYER[kind].new(a.motors)

	function a.setState(_, abstract)
		local clip = clipsMap[abstract]
		if not clip then return end
		a.wantLoop = clip
		if not a.onceActive then
			a.anim:play(clip, 0.12)
		end
	end

	function a.once(_, abstract)
		local clip = clipsMap[abstract]
		if not clip then return end
		a.onceActive = true
		a.anim:play(clip, 0.08)
	end

	function a.step(_, dt)
		if a.missing then
			a.rescanT -= dt
			if a.rescanT <= 0 then
				a.rescanT = 1
				rescan()
			end
			if a.missing then return end
		end
		a.anim:step(dt)
		-- реакция доиграла (finished бывает только у не-луповых) — вернуть цикл
		if a.onceActive and a.anim.finished then
			a.onceActive = false
			if a.wantLoop then a.anim:play(a.wantLoop, 0.12) end
		end
	end

	function a.stop(_)
		a.anim:stop()
	end

	return a
end

-- Какие суставы забирает наложенный клип удара: рука с оружием (и чуть плечо
-- через торс не берём — иначе бег начнёт спорить с ударом).
local ARM_ONLY = { ["Right Arm"] = true }

local players = {}   -- [model] = проигрыватель (CrewClips или адаптер животного)

local function playerFor(model)
	local p = players[model]
	if not p then
		local rig = model:GetAttribute("AnimalRig")
		p = (rig and ANIMAL_PLAYER[rig]) and attachAnimal(model, rig)
			or CrewClips.attach(model)
		players[model] = p
	end
	return p
end

-- Модели гарнизона, пленных и живности лежат в известных папках острова.
-- ⚠️ ПЛЮС ОДИНОЧКИ С ПОМЕТКОЙ CrewAnim.
-- Охранник, спрыгнувший с горящего катера, живёт в Workspace сам по себе: он
-- уже не экипаж (катер его не анимирует) и не гарнизон (не лежит в папке
-- острова). Без этой ветки он плыл, лез на плот и дрался совершенно неподвижным.
local function eachNpc(fn)
	for _, island in ipairs(Workspace:GetChildren()) do
		if island:IsA("Model") and island:GetAttribute("CrewAnim") then
			fn(island)
		elseif island:IsA("Model") and island:FindFirstChild("Rebels") then
			-- ⚠️ ЭКИПАЖ ПОСТРОЙКИ, А НЕ ОСТРОВА.
			-- Рабочие нефтевышки живут в папке Rebels внутри самой станции, и
			-- обход «только острова + одиночки в Workspace» их не находил —
			-- отсюда и «анимаций нет». Папка та же, поэтому проверяем её у
			-- любой модели в мире, а не только у островов.
			for _, npc in ipairs(island.Rebels:GetChildren()) do
				if npc:IsA("Model") then fn(npc) end
			end
		elseif Defs.isCrewIsland(island) then
			-- Rebels — те, кто занял остров после зачистки: анимируются тем же
			-- механизмом, что и гарнизон, просто клипы у них свои (Rebel*)
			for _, folderName in ipairs({ Defs.ENEMIES_FOLDER, "Prisoners", "Animals", "Rebels" }) do
				local folder = island:FindFirstChild(folderName)
				if folder then
					for _, npc in ipairs(folder:GetChildren()) do
						if npc:IsA("Model") then fn(npc) end
					end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	eachNpc(function(npc)
		-- ⚠️ МЁРТВЫХ НЕ АНИМИРУЕМ. У людей атрибут Clip остаётся на трупе с
		-- последнего тика ИИ, и цикл ходьбы крутил суставы убитого — распускаем
		-- позу один раз, дальше трупом занимается рэгдолл. У животных клипа
		-- смерти нет: сервер сам заваливает тушу набок, клиент лишь снимает
		-- анимацию, чтобы суставы не спорили с укладкой.
		local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
		if hum and hum.Health <= 0 then
			local p = players[npc]
			if p and not p.relaxed then
				p.relaxed = true
				if p.stop then p:stop() else p:relax() end
			end
			return
		end

		local p = playerFor(npc)

		-- разовый клип (удар, выстрел, испуг, освобождение) перебивает цикл
		local once = npc:GetAttribute("ClipOnce")
		local onceT = npc:GetAttribute("ClipOnceT")
		if once and onceT and onceT ~= p.lastOnceT then
			p.lastOnceT = onceT
			p:once(once)
		end

		-- НАЛОЖЕНИЕ: удар на бегу. Клип кладётся только на руку, поэтому бег под
		-- ним продолжается — пират не встаёт столбом ради взмаха.
		local ov = npc:GetAttribute("ClipOverlay")
		local ovT = npc:GetAttribute("ClipOverlayT")
		if ov and ovT and ovT ~= p.lastOverlayT and p.overlay then
			p.lastOverlayT = ovT
			p:overlay(ov, ARM_ONLY)
		end

		local loopName = npc:GetAttribute("Clip")
		if loopName then
			if p.setState then p:setState(loopName) else p:play(loopName) end
		end

		p:step(dt)
	end)
end)

-- Уехавший остров уносит с собой и записи: держать проигрыватели мёртвых моделей незачем.
task.spawn(function()
	while true do
		task.wait(5)
		for model in pairs(players) do
			if not model.Parent then players[model] = nil end
		end
	end
end)
