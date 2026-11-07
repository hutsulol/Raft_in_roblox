-- LeechSystem.server.lua
-- ЗАРАЖЁННОЕ БРЕВНО (Infected_Log) и живущая в нём ПИЯВКА (leech_rigged).
--
-- Жизненный цикл:
--   1) ДРЕЙФ      — бревно плывёт как обычный ресурс, пиявка спит (idle).
--   2) В СЕТИ      — бревно поймано сетью → пиявка грызёт полотно (eat).
--                    Сгрызла всё HP сети (NET_MAX_HP) → сеть отрывается от плота и
--                    тонет вместе с уловом и пиявкой.
--   3) АГР         — игрок ударил пиявку → она спрыгивает (jump) на палубу.
--   4) ОХОТА       — to_walk → Walk (луп) → игрок в радиусе → end_walk → attack.
--   5) АТАКА       — изо рта (кость DEF-body_01) вылетает заряд яда в игрока.
--   6) СМЕРТЬ      — HP кончились → death → тело убирается.
--
-- Почему Humanoid: топор, револьвер и ручная пушка наносят урон ТОЛЬКО объектам
-- с Humanoid. Меш пиявки анимируется костями через AnimationController, поэтому
-- Humanoid добавляется чисто как «мишень со здоровьем», а анимации по-прежнему
-- играются через свой Animator. Двигаем пиявку вручную (CFrame): это не риг R15,
-- Humanoid:MoveTo для неё не работает.

-- ВРЕМЕННАЯ ДИАГНОСТИКА. LEECH_DEBUG = true печатает раз в секунду, в каком
-- состоянии пиявка, держит ли её что-то, находит ли она под собой палубу и
-- насколько разошлись её высота и высота опоры. Выключить, когда поведение
-- устаканится. Метка сборки в первой строке — по ней сразу видно, дошла ли
-- правка до запущенного места или Studio крутит старую копию скрипта.
local LEECH_BUILD = "труп приколочен к плоту после посадки"
local LEECH_DEBUG = true

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local EnemyHealthBar = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))
local RaftDetach     = require(ReplicatedStorage:WaitForChild("RaftDetach"))

--══════════════════════ КОНФИГ ══════════════════════
local LEECH_HP        = 30    -- здоровье пиявки
-- ЗДОРОВЬЕ СЕТИ. Тот же атрибут ObstacleHP и та же полоска ObstacleHPBar, что у
-- построек, которые ломают абордажники, — поэтому МЕХАНИК чинит сеть сам, без
-- отдельной логики. Максимум 120 = SwimmingPirate.OBSTACLE_HP (там же и лимит,
-- на который чинит EngineerSystem).
local NET_MAX_HP      = 120
local NET_DPS         = 8     -- урон одной пиявки в секунду: 120/8 = 15 сек в одиночку.
                              -- Две пиявки грызут независимо → вдвое быстрее, и т.д.
local EAT_TICK        = 0.5   -- как часто откусывает
local ATTACK_RANGE    = 14    -- с какой дистанции пиявка бьёт ядом
local CHASE_SPEED     = 7     -- скорость ползанья по палубе, студов/с
local FALL_SPEED      = 14    -- с какой скоростью оседает к воде, если под ней пусто
local RISE_SPEED      = 8     -- и с какой подтягивается вверх, если оказалась под полом
local HP_FLOOR        = 1000  -- скрытый запас HP, чтобы Humanoid формально не умирал
local BAR_SHOW_DIST   = 50    -- с какого расстояния показываем шкалу здоровья
local HITBOX_MIN      = 6     -- минимальный габарит зоны попадания, студов
local TURN_SPEED      = 6     -- скорость доворота к цели, рад/с
local ATTACK_COOLDOWN = 2.5   -- пауза между плевками
local POISON_DAMAGE   = 8     -- урон от заряда яда
local POISON_SPEED    = 55    -- скорость снаряда
local POISON_LIFETIME = 4
-- Прыжка на игрока больше нет: пиявка атакует с места, а на палубу её выводит
-- обычная ходьба. Анимация LEECH_Jump осталась только для перелаза на сеть.
-- Присасывания больше нет: пиявка — дистанционный стрелок, вплотную тоже плюётся.
-- Анимация LEECH_Latch в риге осталась, но не используется.
local CORPSE_LINGER   = 4     -- сколько труп лежит после анимации смерти
local LOSE_DISTANCE   = 90    -- дальше этого пиявка теряет игрока и замирает
local SINK_SPEED      = 6     -- как быстро тонет оторванная сеть
local SINK_TIME       = 12    -- через сколько убрать утонувшее

-- Имена внутри модели. Если что-то переименуешь в Studio — правь здесь.
local LEECH_NAME  = "leech_rigged"
local MESH_NAME   = "Leech"
local MOUTH_BONE  = "DEF-body_01" -- кость, от которой летит яд
local NET_NAME     = "Net_Part"
local NET_HUB_NAME = "Net" -- деталь-полотно ВНУТРИ модели сети: на неё переползает пиявка

--══════════════════════ ХЕЛПЕРЫ ══════════════════════

local function findLeech(logModel)
	return logModel:FindFirstChild(LEECH_NAME, true)
end

-- Animator пиявки.
-- ВАЖНО: Humanoid и AnimationController в одной модели КОНФЛИКТУЮТ — Roblox
-- отдаёт анимацию Humanoid'у, и дорожки, запущенные через Animator контроллера,
-- молча не играют. Мы добавляем Humanoid ради урона, поэтому анимации обязаны
-- идти через ЕГО Animator. Контроллер при этом сносим, чтобы не спорил.
local function getAnimator(leech)
	local hum = leech:FindFirstChildWhichIsA("Humanoid")
	if hum then
		local ac = leech:FindFirstChildOfClass("AnimationController")
		if ac then ac:Destroy() end
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		return animator
	end
	local ac = leech:FindFirstChildOfClass("AnimationController")
	if not ac then
		ac = Instance.new("AnimationController")
		ac.Parent = leech
	end
	local animator = ac:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = ac
	end
	return animator
end

-- Загружаем дорожки по именам Animation-объектов внутри модели.
-- Недостающие (ещё не сделанные) просто отсутствуют — вызовы их пропускают.
-- Имена Animation-объектов ищем по нескольким вариантам: в Blender клипы названы
-- LEECH_Jump / LEECH_Eat / LEECH_Latch / LEECH_Death, а старые уже лежат как
-- idle / Walk / attack. Берём первое совпадение, так что переименовывать ничего
-- не нужно — работают оба стиля.
local ANIM_ALIASES = {
	idle     = { "idle", "Idle", "LEECH_Idle" },
	to_walk  = { "to_walk", "ToWalk", "LEECH_ToWalk", "LEECH_To_Walk" },
	Walk     = { "Walk", "walk", "LEECH_Walk" },
	end_walk = { "end_walk", "EndWalk", "LEECH_EndWalk", "LEECH_End_Walk" },
	attack   = { "attack", "Attack", "LEECH_Attack" },
	jump     = { "jump", "Jump", "LEECH_Jump" },
	eat      = { "eat", "Eat", "LEECH_Eat" },
	latch    = { "latch", "Latch", "LEECH_Latch" },
	death    = { "death", "Death", "LEECH_Death" },
}

local function loadTracks(leech, animator)
	local tracks = {}
	for key, names in pairs(ANIM_ALIASES) do
		for _, name in ipairs(names) do
			local anim = leech:FindFirstChild(name, true)
			if anim and anim:IsA("Animation") then
				local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
				if ok and tr then
					tracks[key] = tr
					break
				end
			end
		end
	end
	-- зацикленные состояния
	if tracks.idle  then tracks.idle.Looped  = true end
	if tracks.Walk  then tracks.Walk.Looped  = true end
	if tracks.eat   then tracks.eat.Looped   = true end
	if tracks.latch then tracks.latch.Looped = true end
	-- одноразовые: поза должна замирать на последнем кадре, а не сбрасываться
	if tracks.jump  then tracks.jump.Looped  = false end
	if tracks.death then tracks.death.Looped = false end
	return tracks
end

local function stopAll(tracks, except)
	for name, tr in pairs(tracks) do
		if name ~= except then pcall(function() tr:Stop(0.15) end) end
	end
end

local function playTrack(tracks, name, fade)
	local tr = tracks[name]
	if not tr then return nil end
	stopAll(tracks, name)
	pcall(function() tr:Play(fade or 0.15) end)
	return tr
end

-- корневая деталь пиявки (сам скиннутый меш)
local function leechRoot(leech)
	return leech:FindFirstChild(MESH_NAME, true)
		or leech.PrimaryPart
		or leech:FindFirstChildWhichIsA("BasePart", true)
end

-- Точка рта. Bone наследует Attachment, а TransformedWorldCFrame учитывает позу
-- ТЕКУЩЕЙ анимации — поэтому яд вылетает точно из пасти, а не из центра модели.
local function mouthCF(leech)
	local bone = leech:FindFirstChild(MOUTH_BONE, true)
	if bone and bone:IsA("Bone") then
		local ok, cf = pcall(function() return bone.TransformedWorldCFrame end)
		if ok and cf then return cf end
		local ok2, cf2 = pcall(function() return bone.WorldCFrame end)
		if ok2 and cf2 then return cf2 end
	end
	-- запасной вариант: деталь с именем Mouth, если решишь её добавить
	local part = leech:FindFirstChild("Mouth", true)
	if part and part:IsA("BasePart") then return part.CFrame end
	local root = leechRoot(leech)
	return root and root.CFrame or CFrame.new()
end

--══════════════════════ ЗВУКИ ══════════════════════
-- Встроенные ассеты Roblox: в неопубликованной Studio загружаемые ID падают с
-- «no access permission», а эти играют всегда. Меняй id/pitch под свой вкус.
-- Только rbxasset://sounds/* — эти лежат в самом движке и играют даже в
-- неопубликованной Studio (загружаемые ID у нас валятся с «no access permission»).
local SOUNDS = {
	bite  = { id = "rbxasset://sounds/snap.mp3",          vol = 2.0, pitch = 1.7 },  -- грызёт сеть
	jump  = { id = "rbxasset://sounds/impact_water.mp3",  vol = 1.8, pitch = 1.4 },  -- прыжок/перелаз
	spit  = { id = "rbxasset://sounds/splat.mp3",         vol = 2.6, pitch = 1.7 },  -- плевок ядом: вязкий сгусток
	-- смерть: низкий мокрый шлепок. skip срезает тихое начало сэмпла — на
	-- замедлении оно растягивалось, и удар звучал с опозданием на ~0.3с.
	death = { id = "rbxasset://sounds/splat.mp3",         vol = 3.0, pitch = 0.55, skip = 0.12 },
	hurt  = { id = "rbxasset://sounds/splat.mp3",         vol = 2.0, pitch = 1.25 }, -- получила урон: мокрый шлепок
}

-- ЗВУКИ СОЗДАЮТСЯ ОДИН РАЗ при спавне пиявки и живут на её меше. Раньше каждый
-- вызов создавал НОВЫЙ Sound: клиенту он сперва реплицировался, потом грузился —
-- отсюда стабильные ~0.2с опоздания, а короткие звуки (смерть, плевок) вообще
-- успевали отзвучать на сервере до того, как клиент их получал, — казалось, что
-- их нет. Предсозданный инстанс уже загружен у клиента, Play() срабатывает сразу.
local function ensureSounds(part)
	for key, cfg in pairs(SOUNDS) do
		local name = "LeechSnd_" .. key
		if not part:FindFirstChild(name) then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = cfg.id
			s.Volume = cfg.vol
			s.PlaybackSpeed = cfg.pitch
			-- ЛИНЕЙНОЕ затухание: при стандартном Inverse звук от мелкого объекта
			-- глохнет уже в паре студов, из-за чего пиявку не было слышно вообще.
			s.RollOffMode = Enum.RollOffMode.Linear
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 150
			s.Parent = part
		end
	end
end

local function playSound(part, key)
	local cfg = SOUNDS[key]
	if not (cfg and part and part:IsA("BasePart")) then return end
	local s = part:FindFirstChild("LeechSnd_" .. key)
	if not s then
		ensureSounds(part)
		s = part:FindFirstChild("LeechSnd_" .. key)
		if not s then return end
	end
	s.PlaybackSpeed = cfg.pitch * (0.93 + math.random() * 0.14) -- лёгкий разброс тона
	s:Play() -- повторный вызов перезапускает с начала
	if cfg.skip then s.TimePosition = cfg.skip end -- пропустить тихое вступление сэмпла
end

local function nearestPlayer(pos, maxDist)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if (not bestD or d < bestD) and (not maxDist or d <= maxDist) then
				best, bestD = plr, d
			end
		end
	end
	return best, bestD
end

local function raftModel()
	return workspace:FindFirstChild("Raft")
end

-- ГАБАРИТЫ ПЛОТА. Обходить модель каждый кадр дорого, поэтому кэшируем на полсекунды.
-- Нужны как ЗАПАСНОЙ ОТВЕТ на вопросы «над плотом ли она» и «где палуба»: луч вниз
-- на это полагаться не даёт — он мажет на краю доски, в ячейке сетки и между брёвен,
-- а от одного его промаха у пиявки разом отваливались и гравитация, и езда с плотом.
local raftBox = { at = -1, ok = false, radius = 0, deckY = 0, floor = {} }

-- ТОЛЬКО ПОЛ. Детали клеток настила: доски, сетка, построенные тайлы. Луч опоры
-- бьём ИСКЛЮЧИТЕЛЬНО по ним. Раньше он бил по всему подряд и цеплялся то за
-- постройку, то за игрока, то за улов — пиявку от такого попадания вздёргивало
-- вверх, и она оставалась стоять «над плотом».
local function collectFloor(raft)
	local parts = {}
	for _, child in ipairs(raft:GetChildren()) do
		local isFloor = child:GetAttribute("BuildType") == "raft"
			or child.Name == "Raft_part" or child.Name == "Net_Part"
		if isFloor then
			if child:IsA("BasePart") then
				parts[#parts + 1] = child
			else
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then parts[#parts + 1] = d end
				end
			end
		end
	end
	return parts
end

local function floorYAt(pos, floor)
	if not floor or #floor == 0 then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = floor
	params.IgnoreWater = true
	local res = workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -60, 0), params)
	return res and res.Position.Y or nil
end

local function raftInfo()
	if os.clock() - raftBox.at <= 0.5 then
		return raftBox.ok and raftBox or nil
	end
	raftBox.at = os.clock()
	raftBox.ok = false
	local raft = raftModel()
	local rp = raft and raft.PrimaryPart
	if not rp then return nil end
	local ok, ext = pcall(function() return raft:GetExtentsSize() end)
	raftBox.radius = (ok and ext) and (math.max(ext.X, ext.Z) * 0.5 + 2) or 40
	raftBox.center = rp.Position
	raftBox.floor = collectFloor(raft)
	-- УРОВЕНЬ ПАЛУБЫ меряем лучом по самому полу. Брать его от PrimaryPart нельзя:
	-- по логам он оказался на 5.5 студа выше настила, и запасная «плоскость пола»
	-- вздёргивала пиявку в воздух над плотом.
	raftBox.deckY = floorYAt(rp.Position, raftBox.floor) or rp.Position.Y
	raftBox.ok = true
	return raftBox
end

-- УРОВЕНЬ ВОДЫ. Луч сквозь воду только по Terrain (как в InfiniteOcean), кэш 2с —
-- океан плоский, одного замера хватает на всех пиявок.
local waterCache = { at = -1, y = nil }
local function waterYAt(pos)
	if os.clock() - waterCache.at > 2 then
		waterCache.at = os.clock()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		params.IgnoreWater = false
		local res = workspace:Raycast(Vector3.new(pos.X, pos.Y + 120, pos.Z), Vector3.new(0, -500, 0), params)
		waterCache.y = (res and res.Material == Enum.Material.Water) and res.Position.Y or nil
	end
	return waterCache.y
end

-- над плотом ли точка (по горизонтали)
local function overRaft(pos)
	local info = raftInfo()
	if not info then return false end
	local dx, dz = pos.X - info.center.X, pos.Z - info.center.Z
	return dx * dx + dz * dz <= info.radius * info.radius
end

-- высота палубы под точкой (чтобы пиявка ползала по полу, а не парила)
local function deckYAt(pos)
	local info = raftInfo()
	return info and floorYAt(pos, info.floor) or nil
end

--══════════════════════ ЯД ══════════════════════

local function spitPoison(leech, targetPos)
	local cf = mouthCF(leech)
	local dir = (targetPos - cf.Position)
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	playSound(leechRoot(leech), "spit") -- вылет заряда

	local blob = Instance.new("Part")
	blob.Name = "LeechPoison"
	blob.Shape = Enum.PartType.Ball
	blob.Size = Vector3.new(1.1, 1.1, 1.1)
	blob.Color = Color3.fromRGB(120, 220, 70)
	blob.Material = Enum.Material.Neon
	blob.CanCollide = false
	blob.CanQuery = false
	blob.Massless = true
	blob.CFrame = CFrame.new(cf.Position + dir * 1.5)
	blob.AssemblyLinearVelocity = dir * POISON_SPEED
	blob.Parent = workspace

	local trail0 = Instance.new("Attachment"); trail0.Position = Vector3.new(0.3, 0, 0); trail0.Parent = blob
	local trail1 = Instance.new("Attachment"); trail1.Position = Vector3.new(-0.3, 0, 0); trail1.Parent = blob
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = trail0, trail1
	trail.Lifetime = 0.25
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 240, 90), Color3.fromRGB(60, 140, 30))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = blob

	local hit = false
	blob.Touched:Connect(function(other)
		if hit then return end
		local char = other:FindFirstAncestorWhichIsA("Model")
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local plr = char and Players:GetPlayerFromCharacter(char)
		if hum and plr and hum.Health > 0 then
			hit = true
			hum:TakeDamage(POISON_DAMAGE)
			blob:Destroy()
		end
	end)

	Debris:AddItem(blob, POISON_LIFETIME)
end

--══════════════════════ ПОЛОСКА HP СЕТИ ══════════════════════
-- Структура один-в-один с ObstacleHPBar у построек (SwimmingPirate.showObstacleHP),
-- потому что EngineerSystem обновляет и убирает именно её, когда чинит.
local function setNetBar(model, hp, maxHP)
	local main, height
	if model:IsA("Model") then
		main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		local _, size = model:GetBoundingBox()
		height = size.Y
	else
		main, height = model, model.Size.Y
	end
	if not main then return end
	local bb = model:FindFirstChild("ObstacleHPBar")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "ObstacleHPBar"
		bb.Size = UDim2.fromOffset(100, 12)
		bb.AlwaysOnTop = true
		bb.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 1.5, 0)
		bb.Adornee = main
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		bg.BorderSizePixel = 0
		bg.Parent = bb
		local fl = Instance.new("Frame")
		fl.Name = "Fill"
		fl.BackgroundColor3 = Color3.fromRGB(225, 80, 60)
		fl.BorderSizePixel = 0
		fl.Parent = bg
		bb.Parent = model
	end
	local bg = bb:FindFirstChildWhichIsA("Frame")
	local fl = bg and bg:FindFirstChild("Fill")
	if fl then fl.Size = UDim2.fromScale(math.clamp(hp / maxHP, 0, 1), 1) end
end

--══════════════════════ ОТРЫВ СЕТИ ══════════════════════
-- Сеть, которую догрызли: снимаем все стыки с плотом и топим вместе с уловом.

local function sinkNet(net)
	if not net or not net.Parent then return end
	if net:GetAttribute("Sinking") then return end
	net:SetAttribute("Sinking", true)

	local bar = net:FindFirstChild("ObstacleHPBar")
	if bar then bar:Destroy() end

	-- КАСКАД: тонет не только сама сеть, но и всё, что держалось ЧЕРЕЗ неё —
	-- отрезанные от центра тайлы и постройки, стоящие на них.
	local raft = raftModel()
	local n = 0
	if raft then
		local ok, res = pcall(function() return RaftDetach.detachTile(raft, net) end)
		n = (ok and res) or 0
	end
	print(("[Leech] сеть догрызена — оторвано кусков: %d, идут ко дну"):format(n))
end

--══════════════════════ ПИЯВКА ══════════════════════

local handled = setmetatable({}, { __mode = "k" })

local function setupLeech(logModel)
	if handled[logModel] then return end
	local leech = findLeech(logModel)
	if not leech then
		warn("[Leech] в " .. logModel:GetFullName() .. " нет модели '" .. LEECH_NAME .. "' — пиявки не будет")
		return
	end
	handled[logModel] = true

	local root = leechRoot(leech)
	if not root then
		warn("[Leech] нет меша '" .. MESH_NAME .. "' в " .. logModel:GetFullName())
		return
	end
	ensureSounds(root) -- прогреваем звуки сразу: к первому событию они уже у клиента

	-- ПИЯВКА НЕ ДОЛЖНА ВЕСИТЬ. Она сидит верхом на бревне, и её масса смещала
	-- центр тяжести — бревно кренилось и заваливалось набок. Massless убирает вес,
	-- CanCollide = false убирает контакты с самим бревном (иначе меш враспор
	-- толкает его даже без массы). Держится она на сварке, а не на трении.
	for _, p in ipairs(leech:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = true
			p.CanCollide = false
		end
	end
	if leech:IsA("BasePart") then
		leech.Massless = true
		leech.CanCollide = false
	end

	-- ВЫНОСИМ ПИЯВКУ ИЗ МОДЕЛИ БРЕВНА. Она была ЕГО потомком, а у бревна стоит тег
	-- «ресурс» — отсюда всё сразу: луч добычи попадал в пиявку и считал её бревном,
	-- подсветка охватывала обеих, а уничтожение собранного бревна уносило пиявку.
	-- Теперь это два независимых объекта, связанных только сваркой: бревно можно
	-- спокойно добыть, а пиявка останется и пойдёт за игроком.
	local logPart = logModel.PrimaryPart or logModel:FindFirstChildWhichIsA("BasePart")
	if logPart and logPart:IsDescendantOf(leech) then
		logPart = nil
		for _, p in ipairs(logModel:GetChildren()) do
			if p:IsA("BasePart") then logPart = p break end
		end
	end

	leech.Parent = workspace
	if logPart and not root:FindFirstChild("LeechWeld") then
		local w = Instance.new("WeldConstraint")
		w.Name = "LeechWeld"
		w.Part0, w.Part1 = logPart, root
		w.Parent = root
	end

	-- Humanoid СНАЧАЛА: getAnimator ниже должен увидеть его и взять именно его
	-- Animator, иначе анимации уйдут в AnimationController и молча не сыграют.
	local hum = leech:FindFirstChildWhichIsA("Humanoid")
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Name = "Humanoid"
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.Parent = leech
	end
	-- СКРЫТЫЙ ЗАПАС ЗДОРОВЬЯ. Мёртвый Humanoid глушит свой Animator — анимация
	-- смерти после Health = 0 просто не проигрывается, пиявка «умирала» стоя.
	-- Поэтому формально она не умирает никогда: реальные HP считаем как
	-- Health - HP_FLOOR, а смерть объявляем сами, когда этот остаток дошёл до нуля.
	hum.MaxHealth = LEECH_HP + HP_FLOOR
	hum.Health = LEECH_HP + HP_FLOOR
	hum.BreakJointsOnDeath = false
	hum.PlatformStand = true -- Humanoid не должен пытаться «стоять», двигаем сами

	local animator = getAnimator(leech)
	local tracks = loadTracks(leech, animator)

	-- какие анимации реально нашлись (по ним видно, что ещё не завезли)
	local found = {}
	for key in pairs(tracks) do found[#found + 1] = key end
	table.sort(found)
	print(("[Leech] готова на %s | анимации: %s"):format(
		logModel:GetFullName(), (#found > 0 and table.concat(found, ", ") or "НЕТ НИ ОДНОЙ")))

	-- ДИАГНОСТИКА ВИДИМОСТИ: если пиявку «не видно», причина почти всегда одна из
	-- трёх — нулевой размер, полная прозрачность или меш ушёл под бревно.
	do
		local logPos = logModel:GetPivot().Position
		local rel = root.Position - logPos
		print(("[Leech] меш '%s': размер=%s прозрачность=%.2f смещение от бревна=(%.1f, %.1f, %.1f)")
			:format(root.Name, tostring(root.Size), root.Transparency, rel.X, rel.Y, rel.Z))
		local hidden = 0
		for _, p in ipairs(leech:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency >= 1 then hidden += 1 end
		end
		if hidden > 0 then
			warn(("[Leech] у пиявки %d полностью прозрачных деталей — их не будет видно"):format(hidden))
		end
	end

	-- ЗОНА ПОПАДАНИЯ. Сам меш узкий и извивается — попасть по нему из револьвера
	-- почти невозможно. Вешаем невидимый короб покрупнее: лучи оружия бьют в него,
	-- а Humanoid ищется вверх по модели, так что урон приходит той же пиявке.
	if not leech:FindFirstChild("LeechHitbox") then
		local hb = Instance.new("Part")
		hb.Name = "LeechHitbox"
		hb.Size = Vector3.new(
			math.max(root.Size.X, HITBOX_MIN),
			math.max(root.Size.Y, HITBOX_MIN),
			math.max(root.Size.Z, HITBOX_MIN))
		hb.CFrame = root.CFrame
		hb.Transparency = 1
		hb.CanCollide = false
		hb.CanTouch = false -- иначе ловит чужие Touched и мешает физике улова
		hb.CanQuery = true  -- ради него всё и затевалось: лучи должны в него попадать
		hb.Massless = true
		hb.Anchored = false
		hb.Parent = leech
		local w = Instance.new("WeldConstraint")
		w.Name = "LeechHitboxWeld"
		w.Part0, w.Part1 = root, hb
		w.Parent = hb
	end

	-- детали тела — нужны часто (якорь, гашение скорости), собираем один раз
	local bodyParts = {}
	for _, p in ipairs(leech:GetDescendants()) do
		if p:IsA("BasePart") then bodyParts[#bodyParts + 1] = p end
	end
	if leech:IsA("BasePart") then bodyParts[#bodyParts + 1] = leech end

	--── ПОЗА. Двигаем пиявку через PivotTo, а собственный поворот пивота модели с
	-- осями меша не совпадает: CFrame.lookAt() разворачивал её «на попа» — она
	-- вставала вертикально крючком. Один раз замеряем, КАК меш лежит в системе
	-- пивота (где у неё нос и какой стороной она кверху), и дальше только
	-- доворачиваем по курсу, сохраняя эту посадку.
	local poseCF, poseAt
	local bodyLift = math.min(root.Size.X, root.Size.Y, root.Size.Z) * 0.5
	do
		-- Ось меша, ближайшая к заданному направлению. Позу снимаем с живой модели,
		-- лежащей на круглом бревне, — она всегда чуть завалена. Округление до
		-- «родной» оси убирает этот перекос, иначе пиявка потом дралась на боку.
		local function snapAxis(v)
			local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
			if ax >= ay and ax >= az then return Vector3.new(v.X >= 0 and 1 or -1, 0, 0) end
			if ay >= az then return Vector3.new(0, v.Y >= 0 and 1 or -1, 0) end
			return Vector3.new(0, 0, v.Z >= 0 and 1 or -1)
		end
		-- КУДА СМОТРИТ. Берём направление от центра меша к кости рта — это и есть
		-- «вперёд» самой пиявки. По габаритному коробу так делать нельзя: он даёт
		-- только ось, но не сторону, а у свёрнутой калачиком модели ещё и путает
		-- длинную сторону с высокой — из-за этого голова смотрела в пол.
		local fMesh
		local mouth = leech:FindFirstChild(MOUTH_BONE, true)
		if mouth then
			pcall(function()
				local lp = root.CFrame:PointToObjectSpace(mouth.TransformedWorldCFrame.Position)
				if lp.Magnitude > 0.15 then fMesh = lp.Unit end
			end)
		end
		if not fMesh then
			-- кости рта нет — запасной вариант: самая длинная сторона короба
			local s = root.Size
			if s.X >= s.Y and s.X >= s.Z then fMesh = Vector3.xAxis
			elseif s.Z >= s.Y then fMesh = Vector3.zAxis
			else fMesh = Vector3.yAxis end
		end
		-- какой стороной она сейчас кверху — такой и должна остаться
		local uMesh = snapAxis(root.CFrame:VectorToObjectSpace(Vector3.yAxis))
		fMesh = snapAxis(fMesh)
		if math.abs(fMesh:Dot(uMesh)) > 0.5 then
			-- нос и спина легли на одну ось — берём под спину любую перпендикулярную
			uMesh = (math.abs(fMesh.Y) > 0.5) and Vector3.zAxis or Vector3.yAxis
		end

		-- переводим обе оси в систему пивота: это соотношение постоянно, PivotTo
		-- двигает модель целиком и меша относительно пивота не смещает
		local rel = leech:GetPivot():ToObjectSpace(root.CFrame)
		local f = rel:VectorToWorldSpace(fMesh)
		f = (f.Magnitude > 1e-4) and f.Unit or Vector3.zAxis
		local u = rel:VectorToWorldSpace(uMesh)
		u = u - f * u:Dot(f) -- ортогонализуем к продольной оси
		u = (u.Magnitude > 1e-4) and u.Unit or Vector3.yAxis
		local restBasis = CFrame.fromMatrix(Vector3.zero, f:Cross(u), u, -f)

		-- где находится меш относительно пивота (в системе пивота) — константа
		local meshOff = leech:GetPivot():ToObjectSpace(root.CFrame).Position

		-- CFrame пивота, при котором пиявка лежит плашмя носом вдоль dir
		function poseCF(pos, dir)
			local fw = Vector3.new(dir.X, 0, dir.Z)
			fw = (fw.Magnitude > 1e-4) and fw.Unit or Vector3.zAxis
			local rt = fw:Cross(Vector3.yAxis)
			rt = (rt.Magnitude > 1e-4) and rt.Unit or Vector3.xAxis
			local up = rt:Cross(fw).Unit
			return CFrame.new(pos) * (CFrame.fromMatrix(Vector3.zero, rt, up, -fw) * restBasis:Inverse())
		end

		-- ТО ЖЕ, НО ЦЕЛИМСЯ САМИМ МЕШЕМ. PivotTo ставит в точку ПИВОТ, а положение
		-- мы каждый кадр считываем по мешу — если пивот от меша смещён, пиявка за
		-- кадр уезжала ровно на эту разницу и накапливала её. Со стороны это и
		-- выглядело как «сносит течением»: она уползала с плота сама по себе.
		function poseAt(meshPos, dir)
			local rot = poseCF(Vector3.zero, dir)
			return poseCF(meshPos - rot:VectorToWorldSpace(meshOff), dir)
		end
	end

	-- ОПОРА ПОД ТОЧКОЙ: высота, на которой должен оказаться центр меша. Есть палуба
	-- — встаём на неё, нет — на уровень воды у плота.
	local function groundY(at)
		local deck = deckYAt(at)
		if deck then return deck + bodyLift end
		-- луч промазал — значит под ней нет пола: уровень настила у борта
		local info = raftInfo()
		if info then return info.deckY + bodyLift end
		return at.Y
	end

	-- Шаг к опоре за кадр. ВВЕРХ — ТОЛЬКО ШАЖКОМ: мгновенный подъём оказался
	-- ловушкой. Хватало одного кадра, где луч поймал не пол, а что-то выше, чтобы
	-- пиявку забросило наверх, — и оттуда она уже не спускалась, потому что
	-- следующий такой кадр возвращал её обратно быстрее, чем она успевала упасть.
	local function stepY(curY, targetY, dt)
		if curY < targetY then return math.min(curY + RISE_SPEED * dt, targetY) end
		return math.max(curY - FALL_SPEED * dt, targetY)
	end

	-- НОВАЯ ВЫСОТА ЦЕНТРА. Луч по полу — истина. Его РАЗОВЫЙ промах над плотом не
	-- повод дёргаться: высоту держим прежней, перенос с плотом сам ведёт её вместе
	-- с палубой. Раньше промах переключал цель на запасную плоскость настила,
	-- замеренную до полусекунды назад, — на волне цель прыгала туда-сюда на каждом
	-- кадре, и пиявку заметно трясло.
	local function settleY(at, curY, dt)
		local deck = deckYAt(at)
		if deck then return stepY(curY, deck + bodyLift, dt) end
		if overRaft(at) then return curY end
		local info = raftInfo()
		if info then return stepY(curY, info.deckY + bodyLift, dt) end
		return curY
	end

	-- ЧЕМ ДЕРЖИТСЯ. Живая сварка с чем-то вне самой пиявки: бревно или полотно сети.
	local function isHeld()
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("WeldConstraint") and d.Enabled then
				local other = (d.Part0 == root) and d.Part1 or d.Part0
				if other and other:IsDescendantOf(workspace) then return true end
			end
		end
		return false
	end

	-- (Humanoid создан выше, до аниматора — см. комментарий там)
	local state = "onLog" -- onLog → eating → hunting → dead
	local moving = false  -- идёт ручной перелаз: сторож опоры не вмешивается
	local hpBar
	local nextAttack = 0

	playTrack(tracks, "idle")

	--── HP-бар появляется при первом уроне ──
	-- реальные HP: у Humanoid они лежат поверх скрытого запаса HP_FLOOR
	local function realHP()
		return math.clamp(hum.Health - HP_FLOOR, 0, LEECH_HP)
	end

	local function ensureBar()
		if hpBar then return end
		local head = root
		local ok = pcall(function()
			hpBar = EnemyHealthBar.new({
				name = "ПИЯВКА",
				maxHp = LEECH_HP,
				cur = realHP(),
				surface = true,
			})
			hpBar.attach(head, 2.2, "EnemyHP")
		end)
		if not ok then hpBar = nil end
	end

	--── СМЕРТЬ ──
	local function die()
		if state == "dead" then return end
		state = "dead"
		-- ГЛУШИМ ВСЁ ЯВНО. Дорожки death в риге может не быть (LEECH_Death ещё не
		-- добавлена) — playTrack тогда выходит ДО своего stopAll, и труп продолжал
		-- махать анимацией атаки. Сначала останавливаем всё, потом death, если есть.
		stopAll(tracks, nil)
		playTrack(tracks, "death")
		playSound(root, "death") -- сразу: свою задержку сэмпл добирает вступлением
		if hpBar then pcall(hpBar.destroy) end

		-- ПАДЕНИЕ ТЕЛА. В охоте детали заякорены и позу ведём вручную, поэтому
		-- убитая в прыжке пиявка так и оставалась висеть в воздухе. Роняем её до
		-- палубы или до воды — физику включать нельзя, она безмассовая и без
		-- столкновений, то есть просто провалилась бы сквозь плот.
		task.spawn(function()
			-- сначала отцепить и заякорить: приваренный к сети труп, который мы
			-- двигаем через PivotTo, дёргал бы за собой весь плот
			local inLeech = {}
			for _, p in ipairs(bodyParts) do inLeech[p] = true end
			for _, scope in ipairs({ logModel, raftModel(), leech }) do
				if scope then
					for _, d in ipairs(scope:GetDescendants()) do
						if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Snap") then
							local a = d.Part0 and inLeech[d.Part0]
							local b = d.Part1 and inLeech[d.Part1]
							if (a or b) and not (a and b) then d:Destroy() end
						end
					end
				end
			end
			for _, p in ipairs(bodyParts) do p.Anchored = true end

			-- ТРУП ЕДЕТ С ПЛОТОМ до самого исчезновения. Раньше цикл только ронял
			-- вниз и выходил — плот уплывал из-под тела, и труп «уносило течением».
			--
			-- ПОСЛЕ ПРИЗЕМЛЕНИЯ — ПРИКОЛАЧИВАЕМ. Пока карри и оседание работают
			-- вдвоём, труп на круглых брёвнах мелко трясёт: качка сдвигает его на
			-- волосок вбок, луч попадает в другую точку кривой поверхности бревна,
			-- цель по высоте меняется — и оседание дёргает тело каждый кадр.
			-- Поэтому, как только он сел, запоминаем позу В СИСТЕМЕ ПЛОТА и дальше
			-- просто держим её — труп жёстко приколочен к палубе, дрожать нечему.
			local lastCF
			local fallT0 = os.clock()
			while leech.Parent do
				local dt = RunService.Heartbeat:Wait()
				local raft = raftModel()
				local rp = raft and raft.PrimaryPart

				-- падает: везём с плотом и опускаем к палубе
				if rp then
					if lastCF then
						local delta = rp.CFrame * lastCF:Inverse()
						pcall(function() leech:PivotTo(delta * leech:GetPivot()) end)
					end
					lastCF = rp.CFrame
				end
				local p = root.Position
				local ny = settleY(p, p.Y, dt)
				local settled = math.abs(ny - p.Y) <= 0.1
				local timedOut = os.clock() - fallT0 > 1.2

				if settled or timedOut then
					-- СЕЛ — ПРИВАРИВАЕМ К ПЛОТУ И СНИМАЕМ ЯКОРЬ. Держать анкерный
					-- труп руками нельзя: CFrame, которые сервер пишет каждый кадр,
					-- реплицируются клиенту БЕЗ сглаживания — труп дрожал, как его
					-- ни прибивай. Приваренный безмассовый кусок сборки плота клиент
					-- интерполирует сам, идеально плавно.
					if rp then
						local w = Instance.new("WeldConstraint")
						w.Name = "LeechCorpseWeld"
						w.Part0, w.Part1 = rp, root
						w.Parent = root
						for _, bp in ipairs(bodyParts) do
							bp.Anchored = false
							bp.Massless = true
							bp.CanCollide = false
						end
					end
					break
				end

				pcall(function() leech:PivotTo(leech:GetPivot() + Vector3.new(0, ny - p.Y, 0)) end)
			end
		end)
		-- LEECH_Death ≈ 2.96с и с 60-го кадра уже замирает: даём анимации доиграть,
		-- потом труп ещё лежит CORPSE_LINGER секунд и только затем исчезает.
		local animLen = (tracks.death and tracks.death.Length > 0) and tracks.death.Length or 0.6
		task.delay(animLen + CORPSE_LINGER, function()
			if leech.Parent then leech:Destroy() end
		end)
		print("[Leech] убита")
	end

	--── УТОПЛЕНИЕ: попала в воду — умирает сразу и уходит на дно ──
	local function drown()
		if state == "dead" then return end
		state = "dead"
		stopAll(tracks, nil)
		playSound(root, "death")
		if hpBar then pcall(hpBar.destroy) end

		-- отцепляем от всего (бревно пусть плывёт дальше) и топим сами
		local inLeech = {}
		for _, p in ipairs(bodyParts) do inLeech[p] = true end
		for _, scope in ipairs({ logModel, raftModel(), leech }) do
			if scope then
				for _, d in ipairs(scope:GetDescendants()) do
					if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Snap") then
						local a = d.Part0 and inLeech[d.Part0]
						local b = d.Part1 and inLeech[d.Part1]
						if (a or b) and not (a and b) then d:Destroy() end
					end
				end
			end
		end
		for _, p in ipairs(bodyParts) do p.Anchored = true end

		-- КАМНЕМ ВНИЗ: тонет сразу и быстро, без зависания у поверхности.
		task.spawn(function()
			local t0 = os.clock()
			local sink = 0
			while leech.Parent and os.clock() - t0 < 2 and sink < 25 do
				local dt = RunService.Heartbeat:Wait()
				local step = 14 * dt
				sink += step
				pcall(function() leech:PivotTo(leech:GetPivot() * CFrame.new(0, -step, 0)) end)
			end
			if leech.Parent then leech:Destroy() end
		end)
		print("[Leech] утонула")
	end

	--── ОХОТА: отцепилась и поползла к игроку ──
	local function startHunt(targetPlr)
		if state ~= "onLog" and state ~= "eating" then return end
		state = "hunting"
		print("[Leech] агр — идёт к игроку")

		-- ОТЦЕПЛЯЕМ ПОЛНОСТЬЮ. Сначала рвём все связи с бревном и сетью: ниже мы
		-- ЯКОРИМ пиявку, а заякоренная деталь, оставшаяся приваренной к плоту,
		-- делает из него неподвижную точку опоры — плот кувыркается.
		do
			local inLeech = {}
			for _, p in ipairs(leech:GetDescendants()) do
				if p:IsA("BasePart") then inLeech[p] = true end
			end
			for _, scope in ipairs({ logModel, workspace:FindFirstChild("Raft"), leech }) do
				if scope then
					for _, d in ipairs(scope:GetDescendants()) do
						if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
							local a = d.Part0 and inLeech[d.Part0]
							local b = d.Part1 and inLeech[d.Part1]
							if (a or b) and not (a and b) then d:Destroy() end
						end
					end
				end
			end
		end

		leech.Parent = workspace -- дальше живёт сама, вне модели бревна
		for _, p in ipairs(leech:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true -- позицию ведём вручную
				p.CanCollide = false
				p.Massless = true
			end
		end

		-- БЕЗ ПРЫЖКА: атакует с места. Разгоняем ходьбу и дальше всё ведёт главный
		-- цикл охоты — он же сам опустит её на палубу, если она осталась в воде.
		task.spawn(function()
			local st = playTrack(tracks, "to_walk")
			if st then
				st.Stopped:Wait()
				if state == "hunting" then playTrack(tracks, "Walk") end
			else
				playTrack(tracks, "Walk")
			end
		end)
	end

	--── УРОН по пиявке: первый удар = агр ──
	-- Реагируем только на РЕАЛЬНЫЙ УРОН. HealthChanged срабатывает и на выставление
	-- здоровья при инициализации — без этой проверки пиявка «обижалась» бы сразу
	-- при спавне и кидалась на игрока, не будучи задетой.
	local lastHP = hum.Health
	local function onHealth(h)
		if state == "dead" then return end
		local damaged = h < lastHP - 0.01
		lastHP = h

		if h - HP_FLOOR <= 0 then
			die()
			return
		end
		if not damaged then return end

		ensureBar()
		if hpBar then pcall(function() hpBar.setHP(realHP(), LEECH_HP) end) end
		playSound(root, "hurt")

		if state ~= "hunting" then
			-- Ударили оружием → бросает бревно/сеть и идёт за обидчиком.
			-- (Клик мышью сюда не попадает: пиявка исключена из добычи ресурса.)
			local plr = nearestPlayer(root.Position, LOSE_DISTANCE)
			startHunt(plr)
		end
	end
	hum.HealthChanged:Connect(onHealth)

	-- ОПРОС ЗДОРОВЬЯ. На одном HealthChanged полагаться нельзя: осколочный урон
	-- пушки прилетал двумя источниками в один кадр (прямое попадание + разлёт), и
	-- пиявка успевала умереть раньше, чем шкала вообще появлялась. Раз в 0.15с
	-- сверяем здоровье сами — полоса вылезет при ЛЮБОМ источнике урона.
	task.spawn(function()
		while leech.Parent and state ~= "dead" do
			task.wait(0.15)
			-- ШКАЛА ЗАРАНЕЕ. Пушка снимает 100 урона — это гарантированный ваншот
			-- по 30 HP, и полоса «по первому урону» не успевала появиться вообще
			-- ни разу. Поэтому показываем её, как только игрок подошёл достаточно
			-- близко, чтобы вообще увидеть пиявку.
			if not hpBar and state ~= "dead" and nearestPlayer(root.Position, BAR_SHOW_DIST) then
				ensureBar()
				if hpBar then pcall(function() hpBar.setHP(realHP(), LEECH_HP) end) end
			end
			onHealth(hum.Health)
		end
	end)

	-- ДИАГНОСТИКА СОСТОЯНИЯ (LEECH_DEBUG)
	if LEECH_DEBUG then
		task.spawn(function()
			while leech.Parent and state ~= "dead" do
				task.wait(1)
				local p = root.Position
				local deck = deckYAt(p)
				local raft = raftModel()
				local _, dist = nearestPlayer(p, 1e6)
				local rp = raft and raft.PrimaryPart
				local raftV = rp and rp.AssemblyLinearVelocity.Magnitude or 0
				print(("[Leech] %s | якорь=%s держит=%s луч=%s надПлотом=%s Y=%.1f опора=%.1f игрок=%s плот=%.1f%s")
					:format(state,
						tostring(root.Anchored),
						tostring(isHeld()),
						deck and ("%.1f"):format(deck) or "МИМО",
						tostring(overRaft(p)),
						p.Y, groundY(p),
						dist and ("%.0f"):format(dist) or "нет",
						raftV,
						raft and "" or " (ПЛОТ НЕ НАЙДЕН)"))
			end
		end)
	end

	-- СТОРОЖ ОПОРЫ. Пиявку может оставить болтаться в пустоте: сварку с полотном
	-- сносит чужая уборка стыков (RaftDetach рвёт связи уходящего куска плота с
	-- внешним миром), а бревно под ней тем временем собрали. Без опоры она не
	-- заякорена и её просто уносит течением. Опоры нет две проверки подряд —
	-- значит держаться не за что, пора охотиться.
	task.spawn(function()
		local loose = 0
		local bump = 0 -- сколько проверок подряд бревно упирается в плот мимо сетей
		while leech.Parent and state ~= "dead" do
			task.wait(0.5)

			-- УТОНУЛА? Центр меша ушёл под поверхность воды — смерть сразу.
			-- НО: пока она НА БРЕВНЕ и бревно живо, вода ей не страшна — она и
			-- должна плыть по поверхности, а качка на волне окунала её на кадр
			-- и убивала 9 из 10 пиявок ещё в дрейфе. Тонет только оставшаяся
			-- без бревна.
			local wy = waterYAt(root.Position)
			if wy and root.Position.Y < wy - 0.3
				and not (state == "onLog" and logModel.Parent) then
				drown()
				break
			end

			-- АГРИЛАСЬ В ОТКРЫТОЙ ВОДЕ. Охота держит высоту палубы, и вдали от
			-- плота подстреленная пиявка шла бы к нему «по воздуху» над водой —
			-- воды она при этом не касается никогда. Плота под ней нет — тонет.
			if state == "hunting" and not overRaft(root.Position)
				and not deckYAt(root.Position) then
				drown()
				break
			end

			-- БРЕВНО УПЁРЛОСЬ В ПЛОТ МИМО СЕТЕЙ. Сеть ловит бревно за секунды;
			-- если бревно уже секунду толчётся в габаритах плота и так и не
			-- поймано — оно врезалось в корпус, пиявке некуда деться, тонет.
			if state == "onLog" and logModel.Parent and not logModel:GetAttribute("CaughtInNet") then
				local raft = raftModel()
				local lp = logModel.PrimaryPart or logModel:FindFirstChildWhichIsA("BasePart")
				if raft and lp then
					local op = OverlapParams.new()
					op.FilterType = Enum.RaycastFilterType.Include
					op.FilterDescendantsInstances = { raft }
					local touching = workspace:GetPartBoundsInBox(lp.CFrame, lp.Size + Vector3.new(1, 1, 1), op)
					if #touching > 0 then
						bump += 1
						if bump >= 2 then
							drown()
							break
						end
					else
						bump = 0
					end
				end
			else
				bump = 0
			end

			if state ~= "onLog" and state ~= "eating" then
				loose = 0
			elseif moving or isHeld() or root.Anchored then
				loose = 0
			else
				loose += 1
				if loose >= 2 then
					loose = 0
					print("[Leech] потеряла опору — переходит в охоту")
					local plr = nearestPlayer(root.Position, LOSE_DISTANCE)
					if plr then startHunt(plr) elseif leech.Parent then leech:Destroy() end
				end
			end
		end
	end)

	--── ПОЙМАНА СЕТЬЮ: грызёт полотно, 15 секунд на спасение ──
	local function watchNet()
		local nv = logModel:FindFirstChild("CaughtNet")
		local net = nv and nv.Value
		if not net then return end
		if state ~= "onLog" then return end
		state = "eating"

		-- ПЕРЕПОЛЗАЕТ НА СЕТЬ. Грызть надо полотно, а не бревно, на котором
		-- приплыла: снимаем сварку с бревна, перебираемся на сетку и варимся уже
		-- к ней — дальше пиявка живёт на сети, даже если бревно уберут.
		local hub = net:FindFirstChild(NET_HUB_NAME, true)
		if not (hub and hub:IsA("BasePart")) then
			hub = net.PrimaryPart or net:FindFirstChildWhichIsA("BasePart", true)
		end
		if hub then
			-- СНИМАЕМ ВСЕ ВНЕШНИЕ СВЯЗИ. Одной своей сварки мало: ловушка сети
			-- (ResourceSpawner) тоже скрепляет детали улова между собой, и пиявка
			-- оставалась намертво прикована к бревну.
			-- ЯКОРИТЬ НЕЛЬЗЯ: заякоренная деталь, приваренная к плоту, превращается
			-- в неподвижную точку опоры — плот от этого кувыркался. Поэтому пиявка
			-- остаётся физической, а позу ведём вручную каждый кадр.
			local leechParts = {}
			for _, p in ipairs(leech:GetDescendants()) do
				if p:IsA("BasePart") then leechParts[#leechParts + 1] = p end
			end
			local inLeech = {}
			for _, p in ipairs(leechParts) do inLeech[p] = true end

			local scanRoots = { logModel, workspace:FindFirstChild("Raft"), leech }
			for _, scope in ipairs(scanRoots) do
				if scope then
					for _, d in ipairs(scope:GetDescendants()) do
						if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
							local a = d.Part0 and inLeech[d.Part0]
							local b = d.Part1 and inLeech[d.Part1]
							-- рвём только связи «пиявка ↔ не-пиявка», внутренние не трогаем
							if (a or b) and not (a and b) then d:Destroy() end
						end
					end
				end
			end

			-- САЖАЕМ НА ПОЛОТНО, А НЕ В ЕГО ЦЕНТР. Раньше точку брали от Position
			-- детали сети — это её середина, и пиявка грызла сеть, вися над ней.
			-- Ищем лучом верхнюю грань полотна и кладём её ровно на неё.
			local hubParams = RaycastParams.new()
			hubParams.FilterType = Enum.RaycastFilterType.Include
			hubParams.FilterDescendantsInstances = { net }
			hubParams.IgnoreWater = true
			local hubHit = workspace:Raycast(hub.Position + Vector3.new(0, 20, 0),
				Vector3.new(0, -40, 0), hubParams)
			local topY = hubHit and hubHit.Position.Y or (hub.Position.Y + hub.Size.Y * 0.5)
			local fromCF = leech:GetPivot()
			local toPos = Vector3.new(hub.Position.X, topY + bodyLift, hub.Position.Z)
			local toCF = poseAt(toPos, hub.CFrame.LookVector)

			-- короткий перелаз, чтобы не телепортировалась рывком
			playTrack(tracks, "to_walk")
			playSound(root, "jump")
			local CRAWL = 0.45
			local t0 = os.clock()
			moving = true -- пока ползёт вручную, сторож опоры молчит
			while os.clock() - t0 < CRAWL and leech.Parent and net.Parent and state == "eating" do
				RunService.Heartbeat:Wait()
				local a = math.clamp((os.clock() - t0) / CRAWL, 0, 1)
				pcall(function() leech:PivotTo(fromCF:Lerp(toCF, a)) end)
			end
			moving = false
			-- АГР ВО ВРЕМЯ ПЕРЕЛАЗА: startHunt уже отцепил и ЗАЯКОРИЛ её. Доварить
			-- сетку сейчас — значит сделать заякоренную пиявку неподвижной опорой
			-- плота: его разворачивало, пока она ходила, и отпускало с её смертью.
			if state ~= "eating" then return end
			if not (leech.Parent and net.Parent) then return end
			pcall(function() leech:PivotTo(toCF) end)

			-- варим к полотну (без якоря — иначе плот кувыркается)
			local nw = Instance.new("WeldConstraint")
			nw.Name = "LeechNetWeld"
			nw.Part0, nw.Part1 = hub, root
			nw.Parent = root
		else
			warn("[Leech] в сети " .. net:GetFullName() .. " не нашёл полотно '"
				.. NET_HUB_NAME .. "' — переползти некуда, грызу на месте")
		end

		playTrack(tracks, "eat")
		playSound(root, "bite")
		print(("[Leech] переползла на сеть %s и грызёт (%.0f урона/сек)"):format(net.Name, NET_DPS))

		task.spawn(function()
			while state == "eating" and leech.Parent and net.Parent do
				task.wait(EAT_TICK)
				if state ~= "eating" or not leech.Parent or not net.Parent then return end

				-- СТРАХОВКА КРЕПЛЕНИЯ. Сварку с сетью может снести чужой код (уборка
				-- стыков при добыче бревна, разбор улова и т.п.). Без неё пиявка —
				-- свободное тело и её уносит течением. Проверяем и привариваем заново.
				if not root:FindFirstChild("LeechNetWeld") then
					local hub2 = net:FindFirstChild(NET_HUB_NAME, true)
					if not (hub2 and hub2:IsA("BasePart")) then
						hub2 = net.PrimaryPart or net:FindFirstChildWhichIsA("BasePart", true)
					end
					if hub2 then
						for _, p in ipairs(leech:GetDescendants()) do
							if p:IsA("BasePart") then p.AssemblyLinearVelocity = Vector3.zero end
						end
						local nw2 = Instance.new("WeldConstraint")
						nw2.Name = "LeechNetWeld"
						nw2.Part0, nw2.Part1 = hub2, root
						nw2.Parent = root
					end
				end

				-- Урон КАЖДОЙ пиявки идёт в общий счётчик сети: две грызут — вдвое
				-- быстрее. Атрибут тот же, что у построек, поэтому МЕХАНИК увидит
				-- повреждение и придёт чинить, как только пиявок не станет.
				local hp = (net:GetAttribute("ObstacleHP") or NET_MAX_HP) - NET_DPS * EAT_TICK
				if hp <= 0 then
					net:SetAttribute("ObstacleHP", 0)
					sinkNet(net)                             -- не спасли: сеть уходит на дно
					if leech.Parent then leech:Destroy() end -- пиявка тонет вместе с ней
					return
				end
				net:SetAttribute("ObstacleHP", hp)
				setNetBar(net, hp, NET_MAX_HP)
				playSound(root, "bite")
			end
		end)
	end

	-- БРЕВНО СОБРАЛИ ИЛИ ОНО ПРОПАЛО. Пиявка теперь живёт отдельно, поэтому не
	-- исчезает вместе с ним: если она ещё сидела на бревне — «дом» разрушен,
	-- бросается на ближайшего игрока; если рядом никого нет — уходит под воду.
	logModel.Destroying:Connect(function()
		if state == "dead" or not leech.Parent then return end
		-- УЖЕ ГРЫЗЁТ СЕТЬ или охотится — бревно ей больше не нужно, не трогаем.
		-- Раньше здесь безусловно срывало пиявку с сети: она теряла сварку с
		-- полотном и уплывала по течению свободным телом.
		if state == "eating" or state == "hunting" then return end

		-- Сидела на бревне, и его собрали: «дом» разрушен.
		local plr = nearestPlayer(root.Position, LOSE_DISTANCE)
		if plr then
			task.defer(function() startHunt(plr) end)
		else
			leech:Destroy() -- некого атаковать — уходит под воду вместе с бревном
		end
	end)

	logModel:GetAttributeChangedSignal("CaughtInNet"):Connect(function()
		if logModel:GetAttribute("CaughtInNet") then
			task.defer(watchNet) -- ObjectValue CaughtNet кладётся тем же кадром
		end
	end)
	if logModel:GetAttribute("CaughtInNet") then task.defer(watchNet) end

	--── ГЛАВНЫЙ ЦИКЛ ОХОТЫ ──
	task.spawn(function()
		local lastRaftCF
		while leech.Parent and state ~= "dead" do
			local dt = RunService.Heartbeat:Wait()
			if state ~= "hunting" then
				lastRaftCF = nil
				continue
			end

			-- ЯКОРЬ ОБЯЗАТЕЛЕН. Позу в охоте ведём вручную, и стоит хоть одной детали
			-- остаться физической — пиявку сносит течением мимо плота.
			for _, p in ipairs(bodyParts) do
				if not p.Anchored then p.Anchored = true end
			end

			-- ЕДЕТ ВМЕСТЕ С ПАЛУБОЙ. Плот всё время плывёт, а позу пиявки мы задаём
			-- в мировых координатах — палуба просто уходила из-под неё. Игрок стоит
			-- на плоту физикой, у заякоренной пиявки этого нет, поэтому переносим её
			-- тем же сдвигом, что и плот. Только когда она реально над палубой: в
			-- открытой воде тащить её за плотом незачем.
			do
				local raft = raftModel()
				local rp = raft and raft.PrimaryPart
				if rp then
					-- ПЕРЕНОС БЕЗУСЛОВНЫЙ, пока идёт охота. Раньше он работал только
					-- «пока она над плотом» — и это была ловушка без выхода: стоило ей
					-- на один кадр вывалиться за габариты (а на корме это неизбежно,
					-- плот уходит вперёд быстрее, чем она ползёт), перенос выключался
					-- НАВСЕГДА, и её честно оставляло позади. Охотится она только на
					-- плоту, так что везти её вместе с ним можно всегда.
					if lastRaftCF then
						local delta = rp.CFrame * lastRaftCF:Inverse()
						pcall(function() leech:PivotTo(delta * leech:GetPivot()) end)
					end
					lastRaftCF = rp.CFrame
				end
			end

			local plr, dist = nearestPlayer(root.Position, LOSE_DISTANCE)
			local char = plr and plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				playTrack(tracks, "idle")
				-- Цель пропала — не оставляем её парить там, где застал прыжок:
				-- оседает на палубу (или к воде) и ждёт там.
				local p = root.Position
				local ny = settleY(p, p.Y, dt)
				if math.abs(ny - p.Y) > 0.01 then
					pcall(function()
						leech:PivotTo(poseAt(Vector3.new(p.X, ny, p.Z), leech:GetPivot().LookVector))
					end)
				end
				continue
			end

			local pos = root.Position
			local flat = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
			local d = flat.Magnitude

			-- ПРИСАСЫВАНИЯ БОЛЬШЕ НЕТ: пиявка — стрелок. Ходит по плоту и бьёт ядом
			-- издали; вплотную — просто продолжает стрелять, а не виснет на игроке.
			--
			-- ВАЖНО: в этом цикле НИЧЕГО НЕ ЖДЁМ. Прежние ew.Stopped:Wait() /
			-- atk.Stopped:Wait() замораживали цикл на всю анимацию (1.5–3с) — вместе
			-- с ним замирал и перенос с плотом: плот уезжал на 8 студов/с, пиявка
			-- отставала и «уносилась течением», потом догоняла рывком.
			if d > ATTACK_RANGE then
				-- ПОЛЗЁТ: держим цикл ходьбы и подтягиваемся к игроку
				if tracks.Walk and not tracks.Walk.IsPlaying and not (tracks.to_walk and tracks.to_walk.IsPlaying)
					and not (tracks.attack and tracks.attack.IsPlaying) then
					playTrack(tracks, "Walk")
				end
				local dir = (d > 0.01) and flat.Unit or Vector3.new(0, 0, 1)
				local nextPos = pos + dir * CHASE_SPEED * dt
				local y = settleY(nextPos, pos.Y, dt)
				pcall(function()
					leech:PivotTo(poseAt(Vector3.new(nextPos.X, y, nextPos.Z), dir))
				end)
			else
				-- ДОСТАЛА: стоит на полу лицом к цели и плюётся по кулдауну
				pcall(function()
					leech:PivotTo(poseAt(
						Vector3.new(pos.X, settleY(pos, pos.Y, dt), pos.Z), flat))
				end)
				if os.clock() >= nextAttack then
					nextAttack = os.clock() + ATTACK_COOLDOWN
					local atk = playTrack(tracks, "attack") -- сам глушит Walk через stopAll
					-- плюём в середине анимации (или сразу, если её ещё нет)
					local delay = atk and math.min(atk.Length * 0.4, 0.6) or 0.15
					task.delay(delay, function()
						if state == "hunting" and leech.Parent and hrp.Parent then
							spitPoison(leech, hrp.Position + Vector3.new(0, 1, 0))
						end
					end)
					-- после клипа вернуться в idle — БЕЗ ожидания в главном цикле
					if atk then
						task.delay(math.max(atk.Length, 0.2), function()
							if state == "hunting" and leech.Parent
								and not (tracks.attack and tracks.attack.IsPlaying)
								and not (tracks.Walk and tracks.Walk.IsPlaying) then
								playTrack(tracks, "idle")
							end
						end)
					end
				end
			end
		end
	end)
end

--══════════════════════ ПОДКЛЮЧЕНИЕ ══════════════════════
-- Заражённые брёвна помечает ResourceSpawner (атрибут Infected). Ловим и уже
-- лежащие в мире, и вновь заспавненные.

local function tryHook(inst)
	if not inst:IsA("Model") then return end
	if inst.Name ~= "Infected_Log" and not inst:GetAttribute("Infected") then return end
	task.defer(function()
		if inst.Parent then setupLeech(inst) end
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do tryHook(d) end
workspace.DescendantAdded:Connect(tryHook)

print("[LeechSystem] loaded — сборка: " .. LEECH_BUILD)
