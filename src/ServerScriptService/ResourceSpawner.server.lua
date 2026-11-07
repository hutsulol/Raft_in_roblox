local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local rs = game:GetService("ReplicatedStorage")

local AssetFind = require(rs:WaitForChild("AssetFind"))
-- Улов приваривается к сети, а сеть — к плоту: каждый пойманный и каждый
-- выбитый предмет ПЕРЕСТРАИВАЕТ сборку плота. Как и всюду, где это происходит,
-- скорость плота снимаем до и возвращаем после, а игрока на палубе держит его
-- собственный клиент (см. RaftShake).
local RaftShake = require(rs:WaitForChild("RaftShake"))

-- Снимок хода сборки плота вокруг перестройки. Возвращает функцию-возврат:
--   local restore = holdRaft(hub)
--   ... привариваем / сносим ...
--   restore()
-- Скорость читается с ЛЮБОЙ детали сборки — Assembly*Velocity относится ко всей
-- сборке целиком, поэтому искать корень плота не нужно, хватает полотна сети.
local function holdRaft(part)
	if not (part and part:IsA("BasePart")) then
		return function() RaftShake.notify() end
	end
	local lin = part.AssemblyLinearVelocity
	local ang = part.AssemblyAngularVelocity
	return function()
		if part.Parent then
			part.AssemblyLinearVelocity = lin
			part.AssemblyAngularVelocity = ang
		end
		RaftShake.notify()
	end
end

local CLICKS_TO_COLLECT = 5
local LIFETIME = 120
local AREA_SIZE = 25
local MAX_PER_AREA = 25

-- Дальность, с которой можно бить по плавающему ресурсу (студы). Было 50 — с края
-- плота до бревна, проплывающего чуть в стороне, уже не дотягивалось, и клик
-- выглядел мёртвым. Проверка серверная: клиент только целится лучом, а решает —
-- этот порог, так что менять его надо здесь и только здесь.
local COLLECT_RANGE = 60
--[[ ⚠️ ЭТО ЖЕ ЧИСЛО НУЖНО КЛИЕНТУ, НО ВТОРОЙ КОПИИ БЫТЬ НЕ ДОЛЖНО.
     Клиент машет рукой ещё до отправки удара, и чтобы не махать впустую, ему
     надо знать, докуда игрок достаёт. Вписать 60 второй раз в клиентский файл —
     значит завести второй источник правды: следующая правка баланса разъедет их
     молча, и симптом вернётся зеркально (рука не машет там, где сервер удар
     принимает). Отдаём атрибутом: одно объявление, одно место правки. ]]
game:GetService("ReplicatedStorage"):SetAttribute("ResourceCollectRange", COLLECT_RANGE)

-- ─── ГДЕ ПОЯВЛЯЕТСЯ ПЛАВНИК ───
-- Дистанция по курсу и разброс поперёк него. Плот идёт 8 студов/с (BoatMovement),
-- так что дистанция — это ещё и время до встречи: 300..450 студов ≈ 37..56 секунд.
local SPAWN_AHEAD_MIN, SPAWN_AHEAD_MAX = 300, 450
local SPAWN_SIDE = 75   -- ± студов ПОПЕРЁК курса

-- ПЕРВЫЕ НЕСКОЛЬКО РЕСУРСОВ — БЛИЖЕ, дальше дистанция обычная.
-- Только ради старта: на общей дистанции первой добычи ждать почти минуту, и море
-- в начале игры выглядит пустым. Счётчик живёт от запуска сервера и не сбрасывается.
local FIRST_CLOSE_COUNT = 3
local CLOSE_AHEAD_MIN, CLOSE_AHEAD_MAX = 170, 260
local CLOSE_SIDE = 45
local spawnedTotal = 0

-- Per-resource click overrides (default = CLICKS_TO_COLLECT)
local CLICKS_BY_TYPE = {
	Leaves = 3,
	Compost = 8,   -- компост крепче листвы
}

-- ─── Raft collision damage config ───
-- Any contact with the raft is fatal: the resource shatters on the
-- first touch regardless of velocity. The per-resource guard below
-- keeps the multiple Touched events from a single collision frame
-- from double-firing :Destroy(), which would otherwise throw.
local COLLISION_COOLDOWN = 0.5     -- seconds between damage events per resource

local collectEvent = rs:FindFirstChild("CollectResource")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectResource"
	collectEvent.Parent = rs
end

local collectNotify = rs:FindFirstChild("CollectNotify")
if not collectNotify then
	collectNotify = Instance.new("RemoteEvent")
	collectNotify.Name = "CollectNotify"
	collectNotify.Parent = rs
end

-- Inventory is managed by InventoryManager.server.lua.
-- Wait for it to be ready before proceeding.
while not _G.GetInventory or not _G.SendInventory or not _G.AddResourceToInventory or not _G.GetInventoryCapacity do
	task.wait(0.1)
end

-- Spawn cycle counter for different spawn rates
local spawnCycle = 0

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

local LootBurstFX = require(rs:WaitForChild("LootBurstFX"))

local NET_MODEL_NAME = "Net_Part"
local NET_HUB_NAME   = "Net" -- деталь-полотно внутри модели
-- Улов в сети добывается ОДНОЙ кучей: клик по любому предмету бьёт по всей сети.
-- Цена = полная стоимость первого предмета + доля от каждого следующего
-- (пример: бревно 6 кликов, два бревна → 6 + ceil(6*0.2) = 8).
local NET_EXTRA_SHARE = 0.2
-- Иконки для «салюта» добычи. На СЕРВЕРЕ _G.GetItemIcon недоступен (он живёт в
-- клиентском InventoryUI), поэтому держим свою таблицу — те же ID, что у ящика
-- дайвера (DiverSystem, PRIZE_ICONS). Нет иконки — предмет просто не полетит.
-- ── ЗВУК ЛОВЛИ ──
-- Играет, когда сеть что-то поймала. Несколько вариантов на подбор: смени
-- NET_SOUND_VARIANT на 1..4 и послушай, какой лучше ложится.
local NET_SOUND_VARIANT = 1
local NET_SOUNDS = {
	-- 1: короткий плеск — «плюх» в воду
	{ id = "rbxasset://sounds/impact_water.mp3", volume = 0.55, pitch = 1.0 },
	-- 2: тот же плеск ниже и глуше — тяжёлый предмет
	{ id = "rbxasset://sounds/impact_water.mp3", volume = 0.65, pitch = 0.7 },
	-- 3: плеск повыше и звонче — мелочь вроде листвы
	{ id = "rbxasset://sounds/impact_water.mp3", volume = 0.45, pitch = 1.45 },
	-- 4: скрип снасти — верёвка натянулась, будто сеть поймала
	{ id = "rbxasset://sounds/snap.mp3", volume = 0.4, pitch = 0.55 },
}

local function playNetCatchSound(part)
	local cfg = NET_SOUNDS[NET_SOUND_VARIANT] or NET_SOUNDS[1]
	if not (part and part:IsA("BasePart")) then return end
	local s = Instance.new("Sound")
	s.SoundId = cfg.id
	s.Volume = cfg.volume
	-- лёгкий разброс тона, чтобы подряд пойманное не звучало одинаково
	s.PlaybackSpeed = cfg.pitch * (0.94 + math.random() * 0.12)
	s.RollOffMaxDistance = 90
	s.Parent = part
	s:Play()
	game:GetService("Debris"):AddItem(s, 4)
end

local NET_ICONS = {
	Log        = "rbxassetid://116178347748793",
	Leaves     = "rbxassetid://96691360298069",
	Plastic    = "rbxassetid://132919988751848",
	Compost    = "rbxassetid://78760258555926",
	Stone      = "rbxassetid://96450657403376",
	Iron_Ingot = "rbxassetid://72890243946368",
}
local netOf     = setmetatable({}, { __mode = "k" }) -- улов  → модель сети
local netCatch  = setmetatable({}, { __mode = "k" }) -- сеть  → множество уловов
local netClicks = setmetatable({}, { __mode = "k" }) -- сеть  → сделано кликов

-- живой улов сети (заодно вычищаем то, что уже собрали/удалили)
local function netGroup(net)
	local list, set = {}, netCatch[net]
	if not set then return list end
	for res in pairs(set) do
		if res.Parent and res:GetAttribute("CaughtInNet") then
			list[#list + 1] = res
		else
			set[res] = nil
		end
	end
	return list
end

local function clicksFor(res)
	return CLICKS_BY_TYPE[res:GetAttribute("ResourceType") or ""] or CLICKS_TO_COLLECT
end

-- сколько кликов нужно на всю кучу: первый предмет целиком, остальные по доле
local function groupClicksNeeded(list)
	local total = 0
	for i, res in ipairs(list) do
		local base = clicksFor(res)
		total += (i == 1) and base or math.ceil(base * NET_EXTRA_SHARE)
	end
	return math.max(total, 1)
end

local function getResourceFromPart(part)
	-- ПИЯВКА — НЕ РЕСУРС. Она сидит внутри модели заражённого бревна, у которой
	-- стоит тег Resource, поэтому клик по пиявке засчитывался как добыча бревна.
	-- Её нужно убивать оружием (топор/револьвер бьют по Humanoid), а не мышкой.
	if part:FindFirstAncestor("leech_rigged") then
		return nil
	end

	if CollectionService:HasTag(part, "Resource") then
		return part
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Resource") then
		return model
	end

	return nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- Unified HP system: both clicks and raft collisions reduce the same HP
-- pool. The progress bar updates for all clients from either source.
-- ═══════════════════════════════════════════════════════════════════════

local function damageResource(resource, amount)
	local hp = resource:GetAttribute("ResourceHP")
	local maxHP = resource:GetAttribute("ResourceMaxHP")
	if not hp or not maxHP or hp <= 0 then return 0 end

	hp = math.max(0, hp - amount)
	resource:SetAttribute("ResourceHP", hp)

	-- Notify all clients so everyone's progress bar updates
	local totalDamage = maxHP - hp
	collectNotify:FireAllClients("progress", resource, totalDamage, maxHP)

	return hp
end

-- ─── Hit feedback: a weak shake when the player strikes a drifting resource,
-- recoiling AWAY from the exact spot they clicked. Resources are server-owned
-- (SetNetworkOwner(nil)), so the impulse is applied here and replicates to all.
--[[ КИНЕМАТИКА ЛИСТВЫ И КОМПОСТА. Родную плавучесть террейна на детали не
     отключить, а рядом с водой она дерётся с любой своей пружиной (замеры
     12:29 и 12:33: дрожь и борьба). Поэтому эти два предмета — на якоре:
     высота фиксированная (по высоте движения нет), крен — тихая синусоида
     влево-вправо, удар кликом даёт короткую дрожь. Ведёт guardLoop ниже.
     Сеть при поимке снимает якорь и приваривает улов — запись отпадает сама. ]]
local kinematic = setmetatable({}, { __mode = "k" }) -- [res] = { base, offsets, phase, kick }
local KIN_ROLL  = 0.10   -- крен, радианы (~6°)
local KIN_SWAY  = 0.6    -- дрейф на месте: радиус хода вбок, студы (по высоте — ноль)
local KIN_YAW   = 0.14   -- медленное подворачивание вокруг вертикали, радианы (~8°)
local KIN_SPEED = 1.35   -- общий множитель темпа движения
local KIN_KICK_T, KIN_KICK_SHIFT, KIN_KICK_TILT = 0.55, 0.3, 0.2

local SHAKE_SPEED = 2.5  -- studs/s linear recoil away from the strike
local SHAKE_UP    = 1    -- small upward bob
local SHAKE_SPIN  = 4    -- rad/s rock/spin around the hit (the visible "shudder")

local function resourceRoot(resource)
	if resource:IsA("BasePart") then return resource end
	if resource:IsA("Model") then
		return resource.PrimaryPart or resource:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function applyHitShake(resource, hitPos, char)
	local root = resourceRoot(resource)
	if not root then return end
	local kin = kinematic[resource]
	if kin then
		-- листва/компост на якоре: дрожь рисует кинематический цикл
		local center = root.Position
		local from = (typeof(hitPos) == "Vector3") and hitPos
			or (char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position) or center
		local flat = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
		local dir = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, 1)
		kin.kick = { t = os.clock(), dir = dir, axis = Vector3.new(dir.Z, 0, -dir.X) }
		return
	end
	if root.Anchored then return end
	-- ПРИВАРЕННОЕ НЕ ТРЯСЁМ. Улов в сети приварен к полотну, то есть к плоту:
	-- прибавка скорости уходила ВСЕЙ сборке — сам плот сдвигало на каждый клик,
	-- по разу за каждый предмет в куче. Трясти можно только свободные тела.
	--
	-- ⚠️ СРАВНИВАЕМ СБОРКУ, А НЕ САМУ ДЕТАЛЬ.
	-- Здесь стояло `AssemblyRootPart ~= root` — и это отсекало не только приваренное
	-- к плоту, но и любую модель из НЕСКОЛЬКИХ деталей: корень сборки Roblox
	-- выбирает сам, и совпадать с PrimaryPart он не обязан. Так молча перестали
	-- трястись листва и пластик — у них деталей больше одной, а трясётся только
	-- одинокое бревно. Правильный признак другой: принадлежит ли корень сборки
	-- этому же ресурсу. Если да — тело свободное, трясём.
	local assemblyRoot = root.AssemblyRootPart
	if assemblyRoot and assemblyRoot ~= root
		and not assemblyRoot:IsDescendantOf(resource) then
		return
	end
	local center = root.Position
	local from = (typeof(hitPos) == "Vector3") and hitPos
		or (char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position)
		or center
	-- recoil AWAY from where it was struck (horizontal) + a small upward bob
	local flat = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
	local pushDir = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, 1)
	-- rock around the horizontal axis perpendicular to the push → it tips away from the hit
	local axis = Vector3.new(pushDir.Z, 0, -pushDir.X)
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + pushDir * SHAKE_SPEED + Vector3.new(0, SHAKE_UP, 0)
	root.AssemblyAngularVelocity = root.AssemblyAngularVelocity + axis * SHAKE_SPIN
end

collectEvent.OnServerEvent:Connect(function(player, targetPart, hitPos)
	if typeof(targetPart) ~= "Instance" then return end
	if not targetPart:IsDescendantOf(workspace) then return end

	-- Ignore dropped items — they use the DropItem pickup system which
	-- enforces slot-level fullness. Without this guard, a dropped log
	-- whose template carried a "Resource" tag could be collected here,
	-- bypassing the empty-slot check.
	if CollectionService:HasTag(targetPart, "DroppedItem") then return end
	local parentModel = targetPart:FindFirstAncestorOfClass("Model")
	if parentModel and CollectionService:HasTag(parentModel, "DroppedItem") then return end

	local resource = getResourceFromPart(targetPart)
	if not resource then return end

	-- БОЧКА: клик НЕ собирает её, а открывает замок-мини-игру (BarrelSystem).
	--
	-- Идём именно этим путём, а не своим ClickDetector'ом на бочке: клик по
	-- плавающему ресурсу уже проходит здесь, работает на 50 студов и не глохнет
	-- от экипированного инструмента. Своя обработка на 16 студах до бочки в море
	-- банально не дотягивалась, и клик выглядел мёртвым.
	if resource:GetAttribute("BarrelLocked") then
		if _G.StartBarrelLock then
			_G.StartBarrelLock(player, resource)
		else
			warn("[ResourceSpawner] _G.StartBarrelLock не найден — BarrelSystem не загрузился?")
		end
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local resourcePos
	if resource:IsA("Model") then
		resourcePos = resource:GetPivot().Position
	else
		resourcePos = resource.Position
	end

	local dist = (char.HumanoidRootPart.Position - resourcePos).Magnitude
	if dist > COLLECT_RANGE then return end

	-- ── УЛОВ В СЕТИ ДОБЫВАЕТСЯ КУЧЕЙ ──
	-- Клик по любому предмету в сети бьёт по всей куче сразу: игрок не выбивает
	-- предметы поштучно, а «вытряхивает» сеть целиком за чуть большее число кликов.
	local net = netOf[resource]
	if net and net.Parent then
		local group = netGroup(net)
		if #group > 1 then
			local need = groupClicksNeeded(group)
			-- Сила бьёт и по улову в сети: иначе качать её было бы невыгодно ровно
			-- там, где добычи больше всего.
			local power = _G.GetHitPower and _G.GetHitPower(player) or 1
			local done = (netClicks[net] or 0) + power
			netClicks[net] = done

			-- Опыт силы даём и здесь: ветка сети возвращается раньше общего
			-- начисления ниже, и без этой строки клики по самой богатой добыче
			-- не качали бы силу вовсе.
			if _G.AddStrengthXP then _G.AddStrengthXP(player, 1) end

			if done < need then
				-- недобили: трясём всю кучу и рисуем ОДИН общий прогресс-бар над
				-- сетью (адорнится к её полотну — это и есть центр между предметами)
				for _, res in ipairs(group) do applyHitShake(res, hitPos, char) end
				collectNotify:FireAllClients("progress", net, done, need)
				return
			end

			-- добили: убираем общий бар и выдаём всё разом
			netClicks[net] = nil
			collectNotify:FireAllClients("progressClear", net)
			local icons, totals, repOf = {}, {}, {}
			for _, res in ipairs(group) do
				local rType = res:GetAttribute("ResourceType") or "Log"
				local rAmount = res:GetAttribute("ResourceAmount") or 1
				local pos = res:IsA("Model") and res:GetPivot().Position or res.Position
				repOf[rType] = repOf[rType] or res -- представитель типа для звука

				local added = _G.AddResourceToInventory(player, rType, rAmount, pos)
				if added > 0 then
					totals[rType] = (totals[rType] or 0) + added
				else
					collectNotify:FireClient(player, "inventoryFull")
				end
				if _G.OnQuestResource then _G.OnQuestResource(player, rType, rAmount) end
			end

			-- Звук развала — ПО ОДНОМУ НА КАЖДЫЙ ТИП. Звуки листвы и бревна лежат
			-- внутри самих ресурсов, поэтому сигнал по одному лишь первому предмету
			-- глушил остальные: куча из бревна и листвы звучала только бревном.
			-- Три бревна при этом дадут один «хруст», а не три наложенных.
			for _, rep in pairs(repOf) do
				if rep.Parent then
					collectNotify:FireAllClients("broke", rep,
						rep:GetAttribute("ResourceType") or "Log")
				end
			end

			-- ОДНА ИКОНКА НА ТИП: три бревна дают одну иконку бревна (чуть крупнее),
			-- а не три одинаковых. Разные типы (бревно + листва) — разные иконки.
			for rType, cnt in pairs(totals) do
				local ic = NET_ICONS[rType]
				if ic then
					icons[#icons + 1] = { image = ic, scale = (cnt > 1) and 1.1 or 1 }
				end
			end

			-- САЛЮТ вместо обычного «+N»: иконки всего добытого вылетают из сети
			local hub = net:FindFirstChild(NET_HUB_NAME, true)
			if not (hub and hub:IsA("BasePart")) then
				hub = net.PrimaryPart or net:FindFirstChildWhichIsA("BasePart", true)
			end
			if hub and #icons > 0 then
				LootBurstFX.play(hub, icons, { heightOffset = 1.0 })
			end

			-- Снос улова — та же перестройка сборки, что и его поимка, только
			-- наоборот: из плота уходит сразу вся приваренная куча. Держим ход и
			-- игрока ровно так же (см. holdRaft в шапке).
			local restore = holdRaft(hub)
			for _, res in ipairs(group) do
				if netCatch[net] then netCatch[net][res] = nil end
				netOf[res] = nil
				res:Destroy()
			end
			restore()
			return
		end
	end

	-- ⚠️ УРОН ЗА КЛИК ЗАВИСИТ ОТ СИЛЫ ИГРОКА.
	-- Прокачанная сила выбивает бревно за меньшее число ударов — см.
	-- Characteristics/Stats/Strength.server.lua, там же и формула.
	local hp = damageResource(resource, _G.GetHitPower and _G.GetHitPower(player) or 1)

	--[[ ⚠️ СИЛА РАСТЁТ ЗА КЛИК, А НЕ ЗА СНЯТУЮ ПРОЧНОСТЬ.
	     Соблазн начислить опыт по нанесённому урону велик, но это петля: чем
	     выше сила, тем больше урона за клик, тем быстрее растёт сила. Игрок
	     платит за прокачку одним — своими нажатиями, и считать надо именно их.
	     Начисляем ЗДЕСЬ, после всех проверок (дистанция, тип цели, права):
	     выше по функции удар ещё может быть отброшен, и опыт за него был бы
	     выдан ни за что. ]]
	if _G.AddStrengthXP then
		_G.AddStrengthXP(player, 1)
	end

	-- weak hit-shake on every blow the resource survives (it's destroyed on the fatal one)
	if hp > 0 then
		applyHitShake(resource, hitPos, char)
	end

	if hp <= 0 then
		-- ⚠️ У ОСЬМИНОГА СВОЯ СМЕРТЬ: ОБЛОМКИ И СОСТАВНАЯ ДОБЫЧА.
		-- Он пользуется этой обвязкой ради наведения, полосы прочности и урона с
		-- учётом силы — всё это одинаковое. А вот выдача одним ресурсом ему не
		-- подходит, и разлёт кусков она не знает. Поэтому здесь развилка, а не
		-- вторая копия всей механики удара в OctopusSpawner.
		if resource:GetAttribute("OctopusClickable") ~= nil then
			collectNotify:FireAllClients("broke", resource,
				resource:GetAttribute("ResourceType") or "Meat")
			-- ⚠️ УНИЧТОЖЕНИЕМ ЗАНИМАЕТСЯ САМ ОСЬМИНОГ, А НЕ МЫ.
			-- Его обломки — это его же детали: риг разрывает суставы и раскидывает
			-- их. Снеси мы модель здесь, разлетаться было бы нечему.
			if _G.OctopusKilled then
				pcall(_G.OctopusKilled, player, resource)
			end
			return
		end

		-- Collected by player click: give reward. Routes through
		-- AddResourceToInventory so a full inventory doesn't silently
		-- eat the reward — overflow spawns as a world drop next to
		-- where the resource was.
		local resType = resource:GetAttribute("ResourceType") or "Log"
		local resAmount = resource:GetAttribute("ResourceAmount") or 1

		local added = _G.AddResourceToInventory(player, resType, resAmount, resourcePos)
		if added > 0 then
			collectNotify:FireClient(player, "collected", resource, resType, added)
		else
			collectNotify:FireClient(player, "inventoryFull")
		end
		collectNotify:FireAllClients("broke", resource, resType)

		if _G.OnQuestResource then
			_G.OnQuestResource(player, resType, resAmount)
		end

		-- ⚠️ ПОСЛЕДНИЙ ПРЕДМЕТ В СЕТИ ВЫБИВАЕТСЯ ЭТОЙ ЖЕ ВЕТКОЙ.
		-- Куча из двух и больше уходит выше, разом; а когда в сети остался один,
		-- дело доходит сюда. Он всё так же приварен к плоту, и его снос — та же
		-- перестройка сборки, что и всё остальное. Свободно плывущий мимо ресурс
		-- ни к чему не приварен, ему это ничего не стоит — держим только улов.
		local restore
		if resource:GetAttribute("CaughtInNet") then
			local net = netOf[resource]
			local hub = net and net:FindFirstChild(NET_HUB_NAME, true)
			restore = holdRaft(hub)
			netOf[resource] = nil
			if net and netCatch[net] then netCatch[net][resource] = nil end
		end
		resource:Destroy()
		if restore then restore() end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- Raft collision damage: resources lose HP when the raft runs into them.
-- A fatal collision destroys the resource without giving any reward.
-- ═══════════════════════════════════════════════════════════════════════

local collisionCooldowns = setmetatable({}, {__mode = "k"})

-- ═══════════════════════════════════════════════════════════════════════
-- СЕТЬ (Net_Part): ловит проплывающий ресурс вместо того, чтобы разбить его.
-- Физику делать не нужно — части сети, как и весь плот, лежат в коллизионной
-- группе "Raft", которая НЕ сталкивается с "FloatingResource" (BoatMovement).
-- Поэтому ресурс свободно проходит сквозь ячейки, а игрок по сети ходит.
-- Здесь только «залипание»: улов останавливается в центре сети и ждёт клика.
-- ═══════════════════════════════════════════════════════════════════════
-- (объявления сети живут выше, до обработчика клика)
-- Зазор между полотном и уловом. 0 = лежит вплотную; отрицательное — слегка
-- утоплен в ячейки (как в Raft). Правь здесь, если улов висит или проваливается.
local NET_LIFT_GAP   = 0.35   -- подъём улова над его океанской высотой, студы (владелец: «самую малость выше»)

local function netModelOf(part)
	local m = part
	while m and m ~= workspace do
		if m:IsA("Model") and m.Name == NET_MODEL_NAME then return m end
		m = m.Parent
	end
	return nil
end

-- ⚠️ СЕТЬ НЕ БЕЗДОННАЯ.
-- Улов складывается на полотно и висит там до клика. Без предела куча росла
-- бесконечно: десяток брёвен и кустов налезали друг на друга, торчали сквозь раму
-- и закрывали пол-экрана. Набралось шесть — сеть больше не ловит, и следующий
-- ресурс идёт обычным путём, то есть разбивается о плот.
local NET_CAPACITY = 6

local function netCount(net)
	local t = netCatch[net]
	if not t then return 0 end
	local n = 0
	for res in pairs(t) do
		-- таблица слабая, но уничтоженный улов может ещё висеть в ней до сборки
		-- мусора: считаем только тех, кто реально в мире
		if res.Parent then n += 1 else t[res] = nil end
	end
	return n
end

--[[ Возвращает true, если улов действительно пойман. false — сеть полна или не
     готова; вызывающий тогда пускает ресурс обычным путём (урон о плот). ]]
local function catchInNet(resource, net)
	if resource:GetAttribute("CaughtInNet") then return false end
	if netCount(net) >= NET_CAPACITY then return false end

	local hub = net:FindFirstChild(NET_HUB_NAME, true)
	if not (hub and hub:IsA("BasePart")) then
		hub = net.PrimaryPart or net:FindFirstChildWhichIsA("BasePart", true)
	end
	if not hub then return false end

	local root = resource:IsA("BasePart") and resource
		or resource.PrimaryPart or resource:FindFirstChildWhichIsA("BasePart", true)
	if not root then return false end

	resource:SetAttribute("CaughtInNet", true)

	-- все детали улова (модель может состоять из нескольких)
	local parts = {}
	if resource:IsA("BasePart") then parts[#parts + 1] = resource end
	for _, p in ipairs(resource:GetDescendants()) do
		if p:IsA("BasePart") then parts[#parts + 1] = p end
	end

	for _, p in ipairs(parts) do
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
		-- КРИТИЧНО: улов едет на плоту. Без Massless он утяжелит сборку, а вода
		-- не должна его выталкивать — вертикальное удержание плота построено на
		-- точной компенсации гравитации.
		p.Massless = true
		-- КОЛЛИЗИИ ПРОЧЬ: иначе улов упирается в раму сети и в палубу, физика
		-- бесконечно выталкивает его — отсюда была ДРОЖЬ и «задевает основание».
		p.CanCollide = false
		p.Anchored = false -- держит сварка, а не якорь (якорь + ручной сдвиг = тряска)
		pcall(function() p.EnableFluidForces = false end)
	end

	-- Кладём улов НА ПОЛОТНО: центр сети + подъём вдоль ЕЁ нормали на половину
	-- высоты улова, чтобы он лежал СВЕРХУ, а не утопал в раме.
	local ext = resource:IsA("Model") and resource:GetExtentsSize() or resource.Size
	-- Подъём над полотном = ПОЛОВИНА ТОЛЩИНЫ улова (наименьший габарит), а не
	-- половина длины: у лежащего бревна максимальный габарит — это длина, и по
	-- ней улов задирало высоко над сеткой. Толщина кладёт его ровно на полотно.
	local lift = math.min(ext.X, ext.Y, ext.Z) * 0.5 + NET_LIFT_GAP
	local up = hub.CFrame.UpVector
	-- разброс в ПЛОСКОСТИ полотна (по его собственным осям), чтобы улов не вылезал
	-- за раму: у сети рама по краям, поэтому берём только середину
	local spread = hub.CFrame.RightVector * ((math.random() - 0.5) * hub.Size.X * 0.3)
		+ hub.CFrame.LookVector * ((math.random() - 0.5) * hub.Size.Z * 0.3)
	-- СОХРАНЯЕМ ОРИЕНТАЦИЮ: берём только позицию, поворот оставляем прежним.
	-- Раньше тут был голый CFrame.new(pos) — он обнулял поворот, и бревно,
	-- попав в сеть, «переворачивалось» из своего положения в стандартное.
	local keepRot = (resource:IsA("Model") and resource:GetPivot() or root.CFrame).Rotation
	--[[ ВЫСОТУ НЕ МЕНЯЕМ. Владелец: «на каком уровне был в океане — на таком и
	     остаётся». Сеть стоит у воды, и всё, что плавало, ложится в неё само;
	     любой пересчёт подъёма (по толщине, по раме, по низу) выходил выше
	     или ниже полотна. В плоскости — к центру сети, по Y — как было. ]]
	local keepY = (resource:IsA("Model") and resource:GetPivot() or root.CFrame).Position.Y
	local flatPos = hub.Position + spread
	local target = CFrame.new(flatPos.X, keepY + NET_LIFT_GAP, flatPos.Z) * keepRot   -- самую малость выше воды
	if resource:IsA("Model") then resource:PivotTo(target) else resource.CFrame = target end

	-- СВАРКА, а не якорь: якорь + ручной сдвиг каждый кадр давали дрожь.
	-- Сначала скрепляем детали улова МЕЖДУ СОБОЙ (модель из нескольких частей
	-- иначе распадается — брёвна и листва как раз такие), затем весь улов к сети.
	-- ПИЯВКУ НЕ ВАРИМ: она живая, ей нужно уметь отцепиться от бревна и переползти
	-- на сетку (LeechSystem). Приваренная намертво, она грызла сеть, сидя на бревне.
	for _, p in ipairs(parts) do
		if p ~= root and not p:FindFirstAncestor("leech_rigged") then
			local wj = Instance.new("WeldConstraint")
			wj.Part0, wj.Part1 = root, p
			wj.Parent = root
		end
	end
	-- ⚠️ ВОТ ЗДЕСЬ УЛОВ ВХОДИТ В СБОРКУ ПЛОТА, И ПЛОТ ДЁРГАЕТ.
	-- До этой строки улов — отдельное тело; после неё он часть плота, и физика
	-- пересобирает сборку, отнимая у неё ход на шаг. Со стороны это рывок плота,
	-- а стоящего на палубе игрока уносит по доскам «по инерции» — тот самый
	-- эффект, что был у очистителя, грядки и стройки. Лечится так же (RaftShake).
	local restore = holdRaft(hub)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = hub, root
	w.Parent = root
	pcall(function() root:SetNetworkOwner(nil) end)
	restore()

	playNetCatchSound(hub) -- «плюх»: в сеть что-то попалось

	-- Ссылка на сеть ВНУТРИ улова: реплицируется клиенту, и тот может подсветить
	-- всю кучу разом при наведении на любой её предмет.
	if not resource:FindFirstChild("CaughtNet") then
		local nv = Instance.new("ObjectValue")
		nv.Name = "CaughtNet"
		nv.Value = net
		nv.Parent = resource
	end

	-- регистрируем улов за сетью: дальше он добывается вместе со всей кучей
	netOf[resource] = net
	netCatch[net] = netCatch[net] or setmetatable({}, { __mode = "k" })
	netCatch[net][resource] = true
	netClicks[net] = 0 -- новый предмет в куче → счётчик кликов начинается заново

	print(("[Net] поймал %s → сеть %s (%d/%d)")
		:format(resource.Name, net:GetFullName(), netCount(net), NET_CAPACITY))
	return true
end

-- ── АКТИВНЫЙ ЗАХВАТ ──
-- Touched между несталкивающимися группами срабатывает НЕНАДЁЖНО: бревно ловилось
-- через раз, а мелочь (листва, пластик) не ловилась вовсе — контакт не успевал
-- зарегистрироваться. Поэтому раз в NET_SCAN_STEP сами проверяем, кто оказался в
-- объёме сети. Ресурсов на воде немного (кап MAX_PER_AREA), сетей — единицы,
-- так что перебор дешевле любых region-запросов.
local NET_SCAN_STEP = 0.2
local NET_CATCH_BELOW = 6   -- ловим и то, что проплывает ПОД сетью (сеть на палубе,
local NET_CATCH_ABOVE = 3   -- ресурс — на воде, то есть заметно ниже)

local function resourceRoot(res)
	if res:IsA("BasePart") then return res end
	return res.PrimaryPart or res:FindFirstChildWhichIsA("BasePart", true)
end

task.spawn(function()
	while true do
		task.wait(NET_SCAN_STEP)
		local raft = getBoat()
		if raft then
			-- собираем полотна всех сетей на плоту
			local hubs = {}
			for _, m in ipairs(raft:GetChildren()) do
				if m:IsA("Model") and m.Name == NET_MODEL_NAME then
					-- габариты берём по ВСЕЙ модели сети: так зона захвата не зависит
					-- от того, какая деталь внутри считается полотном
					local ok, cf, size = pcall(function()
						local c, s = m:GetBoundingBox()
						return c, s
					end)
					if ok and cf then
						local r = math.max(size.X, size.Z) * 0.5
						hubs[#hubs + 1] = { model = m, center = cf.Position, radiusSq = r * r }
					end
				end
			end
			if #hubs > 0 then
				for _, res in ipairs(CollectionService:GetTagged("Resource")) do
					if res.Parent and not res:GetAttribute("CaughtInNet") then
						local root = resourceRoot(res)
						if root then
							local rp = root.Position
							for _, n in ipairs(hubs) do
								-- Считаем в МИРОВЫХ осях: полотно может быть повёрнуто как
								-- угодно, и его локальные X/Z не обязаны быть горизонталью.
								local c = n.center
								local dx, dz = rp.X - c.X, rp.Z - c.Z
								local dy = rp.Y - c.Y
								if (dx * dx + dz * dz) <= n.radiusSq
									and dy >= -NET_CATCH_BELOW and dy <= NET_CATCH_ABOVE then
									-- прерываемся только если РЕАЛЬНО поймали: полная сеть
									-- не должна мешать соседней подобрать этот же ресурс
									if catchInNet(res, n.model) then break end
								end
							end
						end
					end
				end
			end
		end
	end
end)

local function setupResourceCollision(resource, maxHP)
	resource:SetAttribute("ResourceHP", maxHP)
	resource:SetAttribute("ResourceMaxHP", maxHP)

	local function onTouched(resPart, otherPart)
		-- Only take damage from the Raft model
		local raft = getBoat()
		if not raft then return end
		if not otherPart:IsDescendantOf(raft) then return end

		-- СЕТЬ ловит, а не разбивает: коснулись Net_Part → улов застревает в ней.
		-- Но ПОЛНАЯ сеть не ловит, и тогда мы НЕ выходим, а падаем ниже, в обычный
		-- урон о плот, — то есть ресурс о неё разбивается.
		if resource:GetAttribute("CaughtInNet") then return end
		local net = netModelOf(otherPart)
		if net and catchInNet(resource, net) then return end

		-- Guard against multiple Touched events on the same collision
		-- reaching Destroy() twice (Roblox throws if we try).
		local now = tick()
		local lastHit = collisionCooldowns[resource]
		if lastHit and (now - lastHit) < COLLISION_COOLDOWN then return end
		collisionCooldowns[resource] = now

		if not resource.Parent then return end

		-- Бочка бьётся об корпус наравне со всем остальным: это и есть её
		-- таймер. Успел вскрыть, пока она подплывает, — забрал добычу; не
		-- успел — разбилась о плот и ушла ни с чем. BarrelSystem слушает
		-- удаление бочки и закрывает окно замка, чтобы оно не висело над
		-- пустым местом.

		-- Raft collision is always fatal: drain HP to 0 and shatter.
		resource:SetAttribute("ResourceHP", 0)
		resource:Destroy()
	end

	-- Connect Touched on every BasePart in the resource
	if resource:IsA("BasePart") then
		resource.Touched:Connect(function(other) onTouched(resource, other) end)
	end
	for _, part in resource:GetDescendants() do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(other) onTouched(part, other) end)
		end
	end
end

local reportedTemplate = {}

-- стартовая плотность листа (дерево); дальше самокоррекция по факту (spawnResource).
-- Объявлено ДО spawnResource: у Lua нет подъёма имён.
-- плотности по замерам 12:18: листва устоялась при 0.75–1.0, компост при 0.56;
-- подбор по факту остаётся страховкой и печатает «[Листва/подбор]»
local LEAVES_DENSITY  = 0.85
local COMPOST_DENSITY = 0.55

--[[ ОГРАНИЧИТЕЛЬ: РЕСУРС НЕ ВЗЛЕТАЕТ. Что бы ни выстрелило предмет вверх
     (выталкивание по коробке, зацеп, толчок), выше VY_MAX студов/с по вертикали
     он не разгонится, а оказавшись выше воды на LIFT_MAX — теряет подъём. Плоту и
     улову в сети это не касается: сваренное к чему-то чужому не трогаем. ]]
local VY_MAX, LIFT_MAX = 6, 2.5
game:GetService("RunService").Heartbeat:Connect(function(dt)
	local water = workspace:GetAttribute("WaterY")
	-- кинематика листвы и компоста: фиксированная высота, крен, дрожь от удара
	local now = os.clock()
	for res, kin in pairs(kinematic) do
		local rootP = res:IsA("BasePart") and res or (res:IsA("Model") and res.PrimaryPart)
		if not res.Parent or res:GetAttribute("CaughtInNet") or not rootP or not rootP.Anchored then
			kinematic[res] = nil
		else
			local t = (now - kin.t0) * KIN_SPEED
			-- дрейф на месте: медленный ход по маленькому кругу (только по горизонтали),
			-- подворачивание вокруг вертикали и крен — три разные частоты, чтобы
			-- движение не выглядело как заведённый маятник
			local tilt = CFrame.Angles(
				math.sin(t * 0.8 + kin.phase) * KIN_ROLL,
				math.sin(t * 0.23 + kin.phase * 0.7) * KIN_YAW,
				math.cos(t * 0.6 + kin.phase * 1.3) * KIN_ROLL)
			local shift = Vector3.new(math.cos(t * 0.35 + kin.phase), 0, math.sin(t * 0.28 + kin.phase * 1.7)) * KIN_SWAY
			local kick = kin.kick
			if kick then
				local k = (now - kick.t) / KIN_KICK_T
				if k >= 1 then kin.kick = nil
				else
					local env = (1 - k) * math.sin(k * math.pi * 3)
					shift = kick.dir * (KIN_KICK_SHIFT * env)
					tilt = tilt * CFrame.fromAxisAngle(kick.axis, KIN_KICK_TILT * env)
				end
			end
			local cf = (kin.base + shift) * tilt
			for part, off in pairs(kin.offsets) do
				if part.Parent then part.CFrame = cf * off end
			end
		end
	end
	for _, res in ipairs(CollectionService:GetTagged("Resource")) do
		local base = res:IsA("BasePart") and res or (res:IsA("Model") and res.PrimaryPart)
		-- корень СБОРКИ, а не PrimaryPart: у связки листьев корнем может быть
		-- второй лист, и проверка «root == корень» молча пропускала её
		local root = base and base.AssemblyRootPart or base
		if root and root.Parent and not root.Anchored and root:IsDescendantOf(res) then
			local v = root.AssemblyLinearVelocity
			--[[ МЯГКАЯ КАЧКА ДЛЯ ЛЁГКИХ И ШИРОКИХ (листва, компост): вода-пружина
			     качает их быстро и мелко (замер: ±2.5 студа/с при размахе 0.1),
			     как дрожь. Гасим вертикальную и угловую скорость по чуть-чуть
			     каждый кадр — остаётся медленное покачивание, как у бревна. ]]
			if v.Y > VY_MAX then
				root.AssemblyLinearVelocity = Vector3.new(v.X, VY_MAX, v.Z)
			elseif water and v.Y > 0 and root.Position.Y > water + LIFT_MAX then
				root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
			end
			-- всё-таки оказался высоко над водой (выстрел из наложения): вернуть на воду
			if water and root.Position.Y > water + LIFT_MAX * 3 then
				local cf = root.CFrame
				root.CFrame = CFrame.new(cf.Position.X, water + 0.3, cf.Position.Z) * cf.Rotation
				root.AssemblyLinearVelocity = Vector3.new(v.X * 0.2, 0, v.Z * 0.2)
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end)

local function spawnResource(templateName, resourceType, resourceAmount, boat)
	local root = boat.PrimaryPart
	local waterY = root.Position.Y
	-- Use raft's actual movement direction so resources always spawn ahead
	local velocity = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
	local forward
	if flatVel.Magnitude > 0.5 then
		forward = flatVel.Unit
	else
		-- Fallback when raft hasn't started moving yet
		local rawForward = root.CFrame.LookVector
		forward = Vector3.new(rawForward.X, 0, rawForward.Z).Unit
	end
	-- ⚠️ ДИСТАНЦИЮ КАТАЕМ ОДИН РАЗ, РАЗБРОС ДАЁМ ПОПЕРЁК КУРСА.
	-- Раньше math.random(300,450) стоял отдельно в X и отдельно в Z: по каждой оси
	-- выпадало своё число, и точка уезжала с курса тем сильнее, чем больше разница
	-- бросков. Разброс тоже шёл по мировым X/Z, а не поперёк носа. На четырёх сотнях
	-- студов это тонуло в общем разлёте, но вблизи ресурс оказывался бы сбоку от
	-- плота — то есть «ближе» без этой правки не заработало бы.
	local close = spawnedTotal < FIRST_CLOSE_COUNT
	local ahead = close
		and math.random(CLOSE_AHEAD_MIN, CLOSE_AHEAD_MAX)
		or math.random(SPAWN_AHEAD_MIN, SPAWN_AHEAD_MAX)
	local right = Vector3.new(forward.Z, 0, -forward.X)  -- перпендикуляр к курсу
	local side = (math.random() * 2 - 1) * (close and CLOSE_SIDE or SPAWN_SIDE)
	local spawnPos = Vector3.new(
		root.Position.X + forward.X * ahead + right.X * side,
		waterY,
		root.Position.Z + forward.Z * ahead + right.Z * side
	)
	--[[ ⚠️ НЕ СПАВНИМ ВНАХЛЁСТ. Два предмета из одного цикла (листва и компост)
	     ложились в одну точку, физика разводила их рывком — и компост улетал в
	     небо. Если рядом (MIN_GAP) уже есть ресурс, сдвигаемся вбок; не нашли
	     места с нескольких попыток — этот спавн пропускаем. ]]
	local MIN_GAP = 12
	local function crowded(pos)
		for _, res in CollectionService:GetTagged("Resource") do
			local r = res:IsA("BasePart") and res or (res:IsA("Model") and (res.PrimaryPart or res:FindFirstChildWhichIsA("BasePart", true)))
			if r and (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < MIN_GAP then
				return true
			end
		end
		return false
	end
	local tries = 0
	while crowded(spawnPos) and tries < 6 do
		tries += 1
		local shift = (math.random() < 0.5 and 1 or -1) * (MIN_GAP + math.random() * MIN_GAP)
		spawnPos = spawnPos + right * shift + forward * ((math.random() - 0.5) * MIN_GAP)
	end
	if crowded(spawnPos) then return nil, "crowded" end

	-- Don't spawn resources on islands
	local islandPositions = _G.IslandPositions or {}
	for _, island in islandPositions do
		local dx = spawnPos.X - island.center.X
		local dz = spawnPos.Z - island.center.Z
		if math.sqrt(dx * dx + dz * dz) < (island.radius or 100) + 20 then
			return
		end
	end

	-- Check density in the area around the spawn position
	local nearby = 0
	for _, res in CollectionService:GetTagged("Resource") do
		local resPos
		if res:IsA("Model") then
			resPos = res:GetPivot().Position
		else
			resPos = res.Position
		end
		if math.abs(resPos.X - spawnPos.X) < AREA_SIZE / 2 and math.abs(resPos.Z - spawnPos.Z) < AREA_SIZE / 2 then
			nearby = nearby + 1
		end
	end
	--[[ ⚠️ ОТКАЗ ОТДАЁМ ПРИЧИНОЙ, А НЕ МОЛЧАНИЕМ.
	     Предел на район нужен: иначе несобранные предметы копятся, и море
	     превращается в свалку. Но отказ был немым — вызывающий видел nil и не
	     мог отличить «в районе уже полно» от «шаблона нет». Из-за этого жалоба
	     «бочка не спавнится» не читалась по логу вообще: в нём просто не было
	     строки про бочку. ]]
	if nearby >= MAX_PER_AREA then return nil, "cap", nearby end

	-- ⚠️ ЗДЕСЬ ИЩЕМ ПО СТАРОМУ: СНАЧАЛА ТОЛЬКО ПРЯМЫЕ ДЕТИ КОРНЯ.
	-- Перевод на AssetFind сломал именно листву, и вот почему. Порядок в AssetFind:
	-- точное имя в корне → точное имя ВГЛУБЬ → без учёта регистра. Островной
	-- «leaves» совпадает ТОЧНО и потому выигрывает раньше, чем дело дойдёт до поиска
	-- без учёта регистра, — а океанская модель лежит в корне под другим регистром.
	-- Старый порядок (точное имя в корне → регистронезависимо в корне) находил
	-- именно её. Возвращаем его, а AssetFind оставляем ПОСЛЕДНИМ шагом: если в
	-- корне и правда ничего нет, пусть поищет вглубь, как для всех остальных.
	local template = rs:FindFirstChild(templateName)
	if not template then
		local lower = string.lower(templateName)
		for _, child in rs:GetChildren() do
			if string.lower(child.Name) == lower then
				template = child
				break
			end
		end
	end
	if not template then
		template = AssetFind.find(templateName)
	end
	-- новые модели листвы могли остаться в Workspace (положены руками в плейс):
	-- берём оттуда, но напоминаем, что им место в ReplicatedStorage
	if not template then
		local ws = workspace:FindFirstChild(templateName)
		if ws and (ws:IsA("Model") or ws:IsA("BasePart")) then
			template = ws
			if not reportedTemplate[templateName .. "@ws"] then
				reportedTemplate[templateName .. "@ws"] = true
				warn(("[ResourceSpawner] «%s» найден в Workspace, а не в ReplicatedStorage — перенеси модель в ReplicatedStorage"):format(templateName))
			end
		end
	end
	if not template then
		-- Case-insensitive fallback in case the model was renamed
		local lower = string.lower(templateName)
		for _, child in rs:GetChildren() do
			if string.lower(child.Name) == lower then
				template = child
				break
			end
		end
	end
	if not template then
		warn("[ResourceSpawner] template not found: " .. templateName)
		return
	end
	-- ВРЕМЕННО: печатаем ОДИН раз на имя — и выбранного, и ВСЕХ тёзок.
	-- Одного «что взяли» не хватило: когда взяли не то, надо ещё видеть, из чего
	-- выбирали, — иначе следующий шаг снова гадание.
	if not reportedTemplate[templateName] then
		reportedTemplate[templateName] = true
		local all = AssetFind.candidates(templateName)
		local list = {}
		for _, c in ipairs(all) do
			local s = c:IsA("Model") and c:GetExtentsSize() or c:IsA("BasePart") and c.Size
			table.insert(list, s
				and ("%s [%.1f×%.1f×%.1f]"):format(c:GetFullName(), s.X, s.Y, s.Z)
				or c:GetFullName())
		end
		print(("[ResourceSpawner] «%s» → ВЗЯТО %s | всего тёзок %d: %s")
			:format(templateName, template:GetFullName(), #all,
				#list > 0 and table.concat(list, " ; ") or "—"))
	end
	local clone = template:Clone()

	-- ⚠️ ШАБЛОН МОЖЕТ БЫТЬ ГОЛОЙ ДЕТАЛЬЮ (компост — MeshPart в корне
	-- ReplicatedStorage). У детали нет PrimaryPart, обращение к нему роняло
	-- весь цикл спавна: после первого компоста ресурсы переставали появляться.
	if clone:IsA("Model") then
		if not clone.PrimaryPart then
			local first = clone:FindFirstChildWhichIsA("BasePart", true)
			if first then
				clone.PrimaryPart = first
			end
		end
		-- Align the model's pivot with its PrimaryPart so PivotTo positions the
		-- visible part exactly where we want it (otherwise WorldPivot can be at
		-- the bounding box center and the part ends up far from the spawn point).
		if clone.PrimaryPart then
			clone.WorldPivot = clone.PrimaryPart.CFrame
		end
	end

	clone:SetAttribute("ResourceType", resourceType)
	clone:SetAttribute("ResourceAmount", resourceAmount)

	-- Lay logs flat (rotate 90° around Z) with a random spin so they look natural.
	-- ЗАРАЖЁННОЕ БРЕВНО — исключение: оно уже смоделировано лежащим, с пиявкой
	-- НА ВЕРХУ. Довернуть его на 90° значило поставить на ребро, и пиявка
	-- оказывалась под водой. Ему нужен только случайный разворот вокруг вертикали.
	if resourceType == "Log" then
		local yaw = math.random() * math.pi * 2
		local roll = (templateName == "Infected_Log") and 0 or math.rad(90)
		clone:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, yaw, roll))
	else
		clone:PivotTo(CFrame.new(spawnPos))
	end

	-- листву якорим ДО выхода в мир: иначе физика успевает шагнуть по
	-- сваренным листам, и связка выходит перекошенной
	clone.Parent = workspace

	-- Unanchor the clone itself if it's a BasePart (GetDescendants doesn't
	-- include the instance itself, so single-part resources stayed anchored).
	-- Tag every BasePart with the FloatingResource collision group (T29)
	-- so resources don't physically push the raft on contact. The
	-- collision group is registered in BoatForwardMovement at init and
	-- configured non-collidable against the Raft group. Resources keep
	-- CanCollide = true so Roblox terrain water buoyancy keeps them
	-- floating, and Touched still fires for the pickup + raft-collision
	-- damage paths.
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CollisionGroup = "FloatingResource"
		clone:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CollisionGroup = "FloatingResource"
			part:SetNetworkOwner(nil)
		end
	end

	--[[ ⚠️ ЛИСТВА И КОМПОСТ: ПЛОТНОСТЬ ДЕРЕВА, БЕЗ ПОДБОРА, С ЗАМЕРОМ.
	     Подбор плотности по высоте убран: лист улетал в небо (лог: +28, потом
	     +98 студов), подбор принимал это за «слишком лёгкий», утяжелял — и лист
	     тонул. Взлёт — не плавучесть покоя, а выстрел, и его глушит
	     ограничитель скорости ниже (guardLoop). Здесь только плотность дерева и
	     замер: первые секунды пишем массу сборки, высоту и скорость — по этим
	     числам видно, по какому объёму вода считает выталкивание. ]]
	if resourceType == "Leaves" or resourceType == "Compost" then
		local parts = {}
		if clone:IsA("BasePart") then table.insert(parts, clone) end
		for _, part in clone:GetDescendants() do if part:IsA("BasePart") then table.insert(parts, part) end end
		--[[ ДВА ЗАМЕРА: масса 0.4 на лист — выстрел вверх, масса 3.3 на лист —
		     камнем на дно. Объём, по которому вода держит меш с коробкой, где-то
		     между, и формулой его не взять. Стартуем с плотности LEAVES_DENSITY и
		     подстраиваем по факту раз в 3 с: тонет — легче, торчит над водой или
		     мечется — тяжелее. Итог печатается: его и впишем константой. ]]
		local startDensity = (resourceType == "Compost") and COMPOST_DENSITY or LEAVES_DENSITY
		for _, part in ipairs(parts) do
			part.CustomPhysicalProperties = PhysicalProperties.new(startDensity, 0.4, 0.2)
		end
		--[[ НА ЯКОРЕ, БЕЗ КОЛЛИЗИЙ, НИЗ НА ВОДЕ. Подбор — клик по лучу (CanQuery
		     остаётся), удар плотом — Touched (CanTouch остаётся), сеть снимает
		     якорь сама. Высота: низ связки на 0.1 ниже поверхности, дальше по
		     высоте ничего не двигается. ]]
		do
			local rootP = clone:IsA("BasePart") and clone or clone.PrimaryPart
			local minY = math.huge
			for _, part in ipairs(parts) do
				local cf, sz = part.CFrame, part.Size * 0.5
				local ext = math.abs(cf.XVector.Y) * sz.X + math.abs(cf.YVector.Y) * sz.Y + math.abs(cf.ZVector.Y) * sz.Z
				minY = math.min(minY, part.Position.Y - ext)
			end
			local water = workspace:GetAttribute("WaterY") or spawnPos.Y
			if minY < math.huge then
				local lift = (water - 0.1) - minY
				if clone:IsA("BasePart") then clone.CFrame = clone.CFrame + Vector3.new(0, lift, 0)
				else clone:PivotTo(clone:GetPivot() + Vector3.new(0, lift, 0)) end
			end
			for _, part in ipairs(parts) do
				part.Anchored = true
				part.CanCollide = false
				part.AssemblyLinearVelocity = Vector3.zero
			end
			if rootP then
				local base = CFrame.new(rootP.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
				local baseInv = base:Inverse()
				local offsets = {}
				for _, part in ipairs(parts) do offsets[part] = baseInv * part.CFrame end
				kinematic[clone] = { base = base, offsets = offsets, phase = math.random() * math.pi * 2, t0 = os.clock() }
			end
		end
		if not reportedTemplate[templateName .. "@probe"] then
			reportedTemplate[templateName .. "@probe"] = true
			task.spawn(function()
				local water = workspace:GetAttribute("WaterY") or spawnPos.Y
				local root = clone:IsA("BasePart") and clone or clone.PrimaryPart
				if not root then return end
				local rows = {}
				for i = 1, 8 do
					task.wait(0.75)
					if not clone.Parent or root.Anchored then break end
					table.insert(rows, ("t%.1f: y=%+.1f vy=%+.1f"):format(i * 0.75, root.Position.Y - water, root.AssemblyLinearVelocity.Y))
				end
				print(("[Листва/замер] %s: масса сборки %.2f, деталей %d, коллизия %s | %s"):format(
					templateName, root.AssemblyMass, #parts,
					root:IsA("MeshPart") and root.CollisionFidelity.Name or "-", table.concat(rows, " | ")))
			end)
		end
	end


	-- Give resources a small random drift so they move visibly on the water
	local driftAngle = math.random() * math.pi * 2
	local driftSpeed = math.random(2, 5)
	local driftVel = Vector3.new(math.cos(driftAngle) * driftSpeed, 0, math.sin(driftAngle) * driftSpeed)
	local rootPart = clone:IsA("BasePart") and clone or clone.PrimaryPart
	if rootPart then
		rootPart.AssemblyLinearVelocity = driftVel
	end

	CollectionService:AddTag(clone, "Resource")

	-- Set up collision damage so the raft can crush resources
	local maxHP = CLICKS_BY_TYPE[resourceType] or CLICKS_TO_COLLECT
	setupResourceCollision(clone, maxHP)

	task.delay(LIFETIME, function()
		-- пойманное сетью не протухает: улов ждёт игрока сколько угодно
		if clone and clone.Parent and not clone:GetAttribute("CaughtInNet") then
			clone:Destroy()
		end
	end)

	-- Считаем только РЕАЛЬНО выпущенное: выше есть ранние выходы (остров под точкой,
	-- превышена плотность, нет модели). Иначе отменённая попытка съедала бы ближний
	-- спавн, и до игрока доехало бы два предмета вместо трёх.
	spawnedTotal = spawnedTotal + 1

	return clone
end

-- БАЛАНС: было task.wait(3) + дерево И листва КАЖДЫЙ цикл (~40 объектов/мин —
-- слишком много). Теперь реже и вразнобой, чтобы море давало ресурс «на грани»:
--   дерево каждый цикл (~8.5/мин), листва вдвое реже (~4/мин),
--   пластик редко. Тонко правится тремя числами ниже.
-- ЗАРАЖЁННЫЕ БРЁВНА (с пиявкой внутри) — редкая поздняя угроза, а не фон.
--   • не раньше INFECTED_FIRST_DAY;
--   • шанс INFECTED_LOG_CHANCE на бревно;
--   • не больше INFECTED_PER_DAY штук за игровой день.
-- Всё остальное время приплывают обычные брёвна.
local INFECTED_FIRST_DAY  = 10
local INFECTED_LOG_CHANCE = 0.02
local INFECTED_PER_DAY    = 2

local infectedWarned = false -- чтобы предупреждение о нехватке модели не спамило
local infectedDay    = 0     -- день, для которого считаем лимит
local infectedToday  = 0

-- Номер игрового дня из DayNightCircle (IntValue в ReplicatedStorage).
local function currentDay()
	local dc = rs:FindFirstChild("DayCount")
	return (dc and tonumber(dc.Value)) or 1
end

-- Можно ли выпустить ещё одну пиявку прямо сейчас.
local function infectedAllowed()
	local day = currentDay()
	if day < INFECTED_FIRST_DAY then return false end
	if day ~= infectedDay then       -- новый день — счётчик с нуля
		infectedDay = day
		infectedToday = 0
	end
	if infectedToday >= INFECTED_PER_DAY then return false end
	return math.random() < INFECTED_LOG_CHANCE
end
local DRIFT_INTERVAL = 7    -- сек между циклами спавна (было 3)
local LEAVES_EVERY   = 2    -- листва раз в N циклов
local COMPOST_EVERY  = 4    -- компост: так же редко, как пластик, но в другие циклы
local PLASTIC_EVERY  = 4    -- пластик раз в N циклов

-- ─── БОЧКА ───
-- Приплывает как обычный предмет, но открывается замком (BarrelSystem).
--[[ Шанс за цикл спавна (DRIFT_INTERVAL = 7 с).
     Прошлый путь этого числа: 0.60 (тестовое, «почти каждый цикл») → 0.10 (раз в
     70 секунд, бочек не хватало на крафт) → 0.22 (море стало из них состоять) →
     0.13. Это примерно одна бочка в минуту: заметно чаще прежнего, но океан
     остаётся океаном, а не складом.
     Если хлама снова окажется мало, правильнее не задирать это число, а дать
     механику доносить недостающее под квест — тогда добыча не зависит от того,
     сколько раз повезло с бочкой. ]]
local BARREL_CHANCE = 0.13
local barrelWarned = false
local barrelCapAt = 0        -- когда последний раз жаловались на переполнение

while true do
	task.wait(DRIFT_INTERVAL)

	local boat = getBoat()
	if not boat then continue end

	spawnCycle = spawnCycle + 1

	-- Дерево: каждый цикл. С шансом INFECTED_LOG_CHANCE вместо обычного приплывает
	-- ЗАРАЖЁННОЕ бревно — с пиявкой внутри (Infected_Log). Добывается как бревно,
	-- но помечено атрибутом Infected: по нему система пиявки его и находит.
	local infTpl = AssetFind.find("Infected_Log")
	if not infTpl and not infectedWarned then
		infectedWarned = true
		warn("[ResourceSpawner] модели 'Infected_Log' нет в ReplicatedStorage — "
			.. "заражённые брёвна спавниться НЕ будут (сейчас она, вероятно, лежит в Workspace)")
	end
	if infTpl and infectedAllowed() then
		local inf = spawnResource("Infected_Log", "Log", 1, boat)
		if inf then
			inf:SetAttribute("Infected", true)
			infectedToday = infectedToday + 1
			print(("[ResourceSpawner] заражённое бревно (день %d, %d/%d за день)")
				:format(currentDay(), infectedToday, INFECTED_PER_DAY))
		end
	else
		spawnResource("Log", "Log", 1, boat)
	end

	-- Листва: реже дерева. Связка Leaves_2x — 2 листвы в рюкзак (ResourceAmount)
	if spawnCycle % LEAVES_EVERY == 0 then
		spawnResource("Leaves_2x", "Leaves", 2, boat)
	end

	-- Компост: редкость как у пластика, но со сдвигом на полцикла, чтобы не
	-- приплывали вместе. Идёт на грядку (4 дерева + 3 компоста)
	if spawnCycle % COMPOST_EVERY == 2 then
		spawnResource("compost", "Compost", 1, boat)
	end

	-- Пластик: редко
	if spawnCycle % PLASTIC_EVERY == 0 then
		-- новая модель канистры «canister» (ReplicatedStorage), даёт 2 пластика (было 3)
		spawnResource("canister", "Plastic", 2, boat)
	end

	-- Бочка: тот же дрейф и та же ловля сетью, но собрать кликами нельзя —
	-- атрибут BarrelLocked отключает обычный сбор, а вскрытием занимается
	-- BarrelSystem (замок с кольцом).
	if math.random() < BARREL_CHANCE then
		if not AssetFind.find("Barrel") then
			if not barrelWarned then
				barrelWarned = true
				warn("[ResourceSpawner] модели 'Barrel' нет в ReplicatedStorage — "
					.. "бочки спавниться не будут (сейчас она, вероятно, лежит в Workspace)")
			end
		else
			local b, why, nearby = spawnResource("Barrel", "Barrel", 1, boat)
			if b then
				b:SetAttribute("BarrelLocked", true)
				print("[ResourceSpawner] бочка выпущена в море")
			elseif why == "cap" and os.clock() - barrelCapAt > 30 then
				--[[ Не молчим: «бочка не появилась» и «бочку не выпустили, потому
				     что в районе уже предел» — разные беды с разным лечением.
				     Раз в полминуты, чтобы не залить лог. ]]
				barrelCapAt = os.clock()
				print(("[ResourceSpawner] бочку не выпустил: в районе спавна уже %d предметов из %d — собери или дай им уплыть")
					:format(nearby or 0, MAX_PER_AREA))
			end
		end
	end
end