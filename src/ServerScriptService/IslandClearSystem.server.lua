-- IslandClearSystem.server.lua
-- Триггер катсцены «Остров зачищен»: следит за врагами в папке Enemies каждого
-- острова (например Island_1) и, когда ВСЕ они мертвы, шлёт клиентам RemoteEvent
-- IslandClearedEffect — тот запускает баннер + катсцену, а катсцена выращивает
-- постройки (Tree_Farm, Storage_Palm) и выводит освобождённых жителей.
--
-- Заодно чинит HP пиратов, чтобы зачистка вообще была возможна:
--   • снимаем ForceField (через него Humanoid:TakeDamage не проходит — пират
--     казался бессмертным);
--   • включаем скрипт Health, если он был Disabled (регенерация HP);
--   • выключаем скрипт Respawn — он клонировал пирата обратно через 20 сек после
--     смерти, поэтому остров не мог «зачиститься», а HP казалось «не работает»
--     (убил — а он вернулся). Для разовой зачистки смерть должна быть постоянной.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local Debris            = game:GetService("Debris")

-- ── СЛЕЖКА островных врагов ──
local TRACK_RANGE     = 70   -- дальше этого пират вообще не приглядывается
local TRACK_FILL_TIME = 2.5  -- сек до полного обнаружения (в упор, днём, в упор к центру конуса)
local TRACK_DECAY     = 0.05 -- за тик остывает, если игрока не видно
local TRACK_TICK      = 0.2
local TRACK_COS       = 0.35 -- косинус полуугла обзора (~110° общий конус)
local TRACK_INVESTIGATE = 0.5 -- с этой доли шкалы пират идёт к последней замеченной точке

local EnemyHealthBar    = require(ReplicatedStorage:WaitForChild("EnemyHealthBar"))

local ENEMIES_FOLDER = "Enemies"

-- наш единый HP-бар над головой островного врага (как у пиратов волны). Заодно убираем
-- «родной» красный бар из модели (BillboardGui, приходящий с шаблоном пирата).
-- ── СМЕРТЬ островного врага: рэгдолл + отброс от убийцы (как у зомби-пожирателя) ──
-- Живёт ЗДЕСЬ, а не в шаблоне ReplicatedStorage/Pirate lvl1: островные пираты —
-- отдельные модели в Workspace со своими копиями скриптов, правка шаблона их не
-- касается. Эта система патчит именно живые модели, поэтому смерть тоже тут.
local KNOCKBACK_SPEED = 45
local KNOCKBACK_UP    = 20
local CORPSE_LIFETIME = 12

local function setupDeath(model, humanoid)
	if model:GetAttribute("DeathRigged") then return end
	model:SetAttribute("DeathRigged", true)

	-- без этого Roblox сам рвёт все суставы при смерти и модель рассыпается
	humanoid.BreakJointsOnDeath = false

	humanoid.Died:Connect(function()
		local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
		if not hrp then return end

		-- поза больше не управляет телом
		local animate = model:FindFirstChild("Animate")
		if animate and animate:IsA("BaseScript") then animate.Disabled = true end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
		end
		pcall(function() humanoid.PlatformStand = true end)

		-- РЭГДОЛЛ: суставы конечностей → свободные шарниры. Сустав с HRP оставляем
		-- жёстким как «ядро», иначе тело складывается само в себя.
		-- АКСЕССУАРЫ НЕ ТРОГАЕМ: шляпа и одежда крепятся своими Motor6D, и если
		-- превратить их в шарниры — они повисают криво («одежда сидит не так»).
		local function isAccessoryPart(p)
			return p and (p:FindFirstAncestorWhichIsA("Accessory") or p:FindFirstAncestorWhichIsA("Tool")) ~= nil
		end
		for _, m in ipairs(model:GetDescendants()) do
			if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Part0 ~= hrp and m.Part1 ~= hrp
				and not isAccessoryPart(m.Part0) and not isAccessoryPart(m.Part1) then
				local a0 = Instance.new("Attachment"); a0.CFrame = m.C0; a0.Parent = m.Part0
				local a1 = Instance.new("Attachment"); a1.CFrame = m.C1; a1.Parent = m.Part1
				local bs = Instance.new("BallSocketConstraint")
				bs.Attachment0, bs.Attachment1 = a0, a1
				bs.Parent = m.Part0
				local ncc = Instance.new("NoCollisionConstraint")
				ncc.Part0, ncc.Part1 = m.Part0, m.Part1
				ncc.Parent = m.Part0
				m:Destroy()
			end
		end

		-- Коллизию НЕ выключаем: труп падает на землю и остаётся лежать.
		-- (У зомби она снимается, потому что он умирает над водой и держится на
		-- плавучести; на суше тело без коллизии проваливается сквозь остров и
		-- «исчезает» через долю секунды.)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Massless = false -- без массы отброс не сработает
				d.Anchored = false -- заякоренную деталь никакая скорость не сдвинет
				-- шляпа/оружие остаются без коллизии, чтобы не подкидывали тело
				local inAccessory = d:FindFirstAncestorWhichIsA("Accessory")
					or d:FindFirstAncestorWhichIsA("Tool")
				d.CanCollide = (inAccessory == nil)
			end
		end

		-- ОТБРОС от убийцы. Сервер должен владеть физикой трупа, иначе выставленная
		-- здесь скорость будет затёрта клиентом-владельцем и тело просто упадёт.
		pcall(function() hrp:SetNetworkOwner(nil) end)

		local best, bd = nil, math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local p = c and c:FindFirstChild("HumanoidRootPart")
			if p then
				local d = (p.Position - hrp.Position).Magnitude
				if d < bd then best, bd = p.Position, d end
			end
		end
		local away = best and (hrp.Position - best) or (hrp.CFrame.LookVector * -1)
		away = Vector3.new(away.X, 0, away.Z)
		away = (away.Magnitude > 0.01) and away.Unit or Vector3.new(0, 0, 1)

		-- Скорость задаём НА СЛЕДУЮЩЕМ кадре физики: в самый момент Died Humanoid ещё
		-- гасит скорости, и мгновенно выставленный импульс обнуляется — тело падало ровно.
		task.defer(function()
			if not hrp.Parent then return end
			hrp.AssemblyLinearVelocity = away * KNOCKBACK_SPEED + Vector3.new(0, KNOCKBACK_UP, 0)
			hrp.AssemblyAngularVelocity = Vector3.new(away.Z, 0.5, -away.X) * 7
		end)

		-- РЕСПАВН: скрипт «Respawn» клонирует пирата обратно. Отключения по имени
		-- не хватало (в клоне он приезжает снова включённым), поэтому у ТРУПА
		-- сносим ВСЕ скрипты — воскрешать его больше некому.
		for _, s in ipairs(model:GetDescendants()) do
			if s:IsA("Script") or s:IsA("LocalScript") then
				s.Disabled = true
				s:Destroy()
			end
		end

		-- ОРУЖИЕ ВЫПАДАЕТ ИЗ РУК. Ищем Tool на ЛЮБОЙ глубине (раньше смотрел только
		-- прямых детей модели и меч не находился). Шляпу и одежду не трогаем.
		local dropped = 0
		for _, tool in ipairs(model:GetDescendants()) do
			if tool:IsA("Tool") then
				for _, handle in ipairs(tool:GetDescendants()) do
					if handle:IsA("BasePart") then
						-- рвём стыки, которыми оружие держится в руке
						for _, d in ipairs(model:GetDescendants()) do
							if (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Snap"))
								and (d.Part0 == handle or d.Part1 == handle) then
								d:Destroy()
							end
						end
						handle.Parent = workspace
						handle.CanCollide = true
						handle.Anchored = false
						handle.Massless = false
						handle.AssemblyLinearVelocity = away * 8 + Vector3.new(0, 6, 0)
						handle.AssemblyAngularVelocity =
							Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3)
						Debris:AddItem(handle, CORPSE_LIFETIME)
						dropped += 1
					end
				end
				tool:Destroy()
			end
		end
		print(("[IslandClear] смерть %s: выброшено деталей оружия — %d"):format(model.Name, dropped))

		-- Уборка трупа ТОЛЬКО если он всё ещё мёртв: система умеет воскрешать
		-- пиратов, заспавнившихся мёртвыми, и безусловный Debris уносил уже
		-- ожившего врага прямо посреди боя.
		task.delay(CORPSE_LIFETIME, function()
			if model.Parent and humanoid.Health <= 0 then
				model:Destroy()
			end
		end)
	end)
end

local function attachHealthBar(model, humanoid)
	local head = model:FindFirstChild("Head", true) or model:FindFirstChildWhichIsA("BasePart")
	if not head then return end

	-- Гасим ШТАТНЫЙ дисплей Roblox: это он рисовал имя модели ("Pirate_lvl1") и
	-- зелёную полосу здоровья поверх нашего бара. None убирает и имя, и полосу.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	-- Снять ЧУЖИЕ бары из шаблона пирата (красная полоса над головой).
	-- Ловим и BillboardGui, И SurfaceGui: раньше проверялся только первый тип,
	-- поэтому чужая полоса продолжала висеть поверх нашей. Повторяем с задержкой —
	-- модель может дореплицироваться уже после первого прохода.
	local function stripForeignBars()
		if not model.Parent then return end
		for _, d in ipairs(model:GetDescendants()) do
			-- BossStar — НАШ: звезда начальника от PirateIsland, не трогать
			if (d:IsA("BillboardGui") or d:IsA("SurfaceGui"))
				and d.Name ~= "EnemyHP" and d.Name ~= "BossStar" then
				print(("[IslandClear] снял чужой бар: %s (%s) в %s")
					:format(d.Name, d.ClassName, d.Parent and d.Parent.Name or "?"))
				d:Destroy()
			end
		end
	end
	stripForeignBars()
	task.delay(1, stripForeignBars)
	task.delay(4, stripForeignBars)

	if model:FindFirstChild("EnemyHP", true) then return end -- наш уже добавлен
	local hb = EnemyHealthBar.new({
		name = "ПИРАТ",
		maxHp = math.max(humanoid.MaxHealth, 1),
		cur = humanoid.Health,
		surface = true, -- SurfaceGui: масштабируется с расстоянием (не раздувается издалека)
	})
	hb.attach(head, 2.4, "EnemyHP")

	-- ── СЛЕЖКА ──
	-- Над головой пусто, пока пират никого не изучает. Заметил движение —
	-- появляется жёлтая полоса и копится; заполнилась — пират идёт в атаку.
	-- Первый полученный урон переводит бар в режим HP НАВСЕГДА (и пират сразу
	-- знает, откуда бьют, — прятаться после выстрела уже поздно).
	local hpMode = false
	local track  = 0
	local lastSeen = nil -- последняя точка, где пират видел игрока

	local function upd()
		if hpMode then hb.setHP(humanoid.Health, humanoid.MaxHealth) end
	end
	-- Переключаемся ТОЛЬКО на снижении здоровья. Сравнение с MaxHealth не годилось:
	-- у пирата работает регенерация, и любой её тик при неполном HP (56/100) сразу
	-- переводил бар в режим здоровья, хотя игрок по нему ни разу не попал.
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(hp)
		if not hpMode and hp < lastHealth - 0.01 then
			hpMode = true            -- РАНЕН → бар навсегда становится полосой здоровья
			track = 1                -- и цель считается обнаруженной
			hb.setVisible(true)
			-- свой ИИ (PirateIslandAI) читает этот флаг и переходит в бой
			model:SetAttribute("Detected", true)
			-- Сразу вычисляем, откуда бьют, и бежим туда: попадание = раскрытие позиции.
			-- Цикл ниже подхватит преследование, но первый шаг делаем без задержки тика.
			local hrp0 = model:FindFirstChild("HumanoidRootPart")
			local best, bd = nil, math.huge
			if hrp0 then
				for _, plr in ipairs(Players:GetPlayers()) do
					local c = plr.Character
					local p = c and c:FindFirstChild("HumanoidRootPart")
					local h = c and c:FindFirstChildWhichIsA("Humanoid")
					if p and h and h.Health > 0 then
						local d = (p.Position - hrp0.Position).Magnitude
						if d < bd then best, bd = p.Position, d end
					end
				end
			end
			-- откуда прилетело — публикуем всем: свой ИИ пойдёт к этой точке сам
			if best then
				model:SetAttribute("SeenX", best.X)
				model:SetAttribute("SeenZ", best.Z)
				model:SetAttribute("SeenT", os.clock())
			end
			-- ⚠️ У КОГО ЕСТЬ СВОЙ ИИ — НЕ ТРОГАЕМ. Пираты лагеря (WeaponKind ставит
			-- PirateIsland) водятся PirateIslandAI: стрелок держит дистанцию,
			-- сабельник сближается. Второй MoveTo отсюда дёргал их в свою сторону —
			-- отсюда и рваная ходьба, и «стрелок всё равно бежит вплотную».
			if best and not model:GetAttribute("WeaponKind") then
				lastSeen = best
				humanoid:MoveTo(best)
				print("[IslandClear] пират ранен — пошёл на стрелка")
			end
		end
		lastHealth = hp
		upd()
	end)
	humanoid.Died:Connect(function() pcall(hb.destroy) end)

	hb.setVisible(false) -- до первой слежки над головой ничего нет
	hb.setTracking(0)

	task.spawn(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		while model.Parent and humanoid.Health > 0 do
			task.wait(TRACK_TICK)

			local hrp = model:FindFirstChild("HumanoidRootPart")
			local target, tdist = nil, math.huge
			if hrp then
				for _, plr in ipairs(Players:GetPlayers()) do
					local c = plr.Character
					local p = c and c:FindFirstChild("HumanoidRootPart")
					local h = c and c:FindFirstChildWhichIsA("Humanoid")
					if p and h and h.Health > 0 then
						local d = (p.Position - hrp.Position).Magnitude
						if d < tdist then target, tdist = c, d end
					end
				end
			end

			-- ── БОЙ: обнаружен или ранен → идём на игрока ──
			-- Раньше здесь стоял просто continue, и пират стоял столбом, пока по нему
			-- стреляют: его штатный AI на дальний огонь не реагирует. Теперь ведём сами.
			-- ⚠️ У КОГО ЕСТЬ СВОЙ ИИ — ВОДИТЬ НЕ НАШЕ ДЕЛО. Пираты лагеря (атрибут
			-- WeaponKind от PirateIsland) ходят по своим правилам: стрелок держит
			-- дистанцию, сабельник сближается. Отсюда мы им только считаем слежку и
			-- рисуем бар, а MoveTo оставляем одному водителю — иначе ходьба рваная.
			local ownAI = model:GetAttribute("WeaponKind") ~= nil

			-- ОСТЫВАНИЕ. Свой ИИ, потеряв игрока из виду, сбрасывает Detected —
			-- возвращаем пирата из «вечного боя» в слежку: насторожен (полшкалы),
			-- но уже не всевидящий. При новой встрече шкала дозаполнится штатно.
			if hpMode and ownAI and model:GetAttribute("Detected") == false then
				hpMode = false
				track = 0.4
				hb.setTracking(track)
				hb.setVisible(true)
			end
			-- ПОДНЯТ КРИКОМ СОСЕДА (PirateIslandAI ставит Detected снаружи): бар сразу
			-- в режим здоровья, шкала слежки полная — это бой, а не подкрадывание
			if not hpMode and model:GetAttribute("Detected") == true then
				hpMode = true
				track = 1
				hb.setVisible(true)
				hb.setHP(humanoid.Health, humanoid.MaxHealth)
			end

			if hpMode then
				if not ownAI then
					if target and hrp then
						local tp = target.HumanoidRootPart.Position
						lastSeen = tp
						humanoid:MoveTo(tp)
						-- разворачиваем корпус к цели, иначе анимация бега смотрит вбок
						local flat = Vector3.new(tp.X, hrp.Position.Y, tp.Z)
						if (flat - hrp.Position).Magnitude > 1 then
							humanoid.AutoRotate = true
						end
					elseif lastSeen then
						humanoid:MoveTo(lastSeen) -- игрок пропал → добегаем до последней точки
					end
				end
				continue
			end

			local gain = -TRACK_DECAY -- никого рядом → слежка остывает
			if target and tdist <= TRACK_RANGE then
				-- в поле зрения? (конус перед пиратом + прямая видимость)
				local tp = target.HumanoidRootPart.Position
				local toT = (tp - hrp.Position)
				local inCone = toT.Unit:Dot(hrp.CFrame.LookVector) >= TRACK_COS
				params.FilterDescendantsInstances = { model, target }
				local blocked = workspace:Raycast(hrp.Position, toT, params) ~= nil
				if inCone and not blocked then
					-- ближе — быстрее; ночью пират замечает вдвое медленнее
					local prox = 1 - (tdist / TRACK_RANGE) * 0.6
					local night = (Lighting.ClockTime >= 18 or Lighting.ClockTime < 6) and 0.5 or 1
					gain = TRACK_TICK / TRACK_FILL_TIME * prox * night
					lastSeen = tp -- запоминаем, где видели: туда пойдём проверять
					if ownAI then
						model:SetAttribute("SeenX", tp.X)
						model:SetAttribute("SeenZ", tp.Z)
						model:SetAttribute("SeenT", os.clock())
					end
				end
			end

			local prev = track
			track = math.clamp(track + gain, 0, 1)
			-- итог слежки — атрибутом: по нему свой ИИ решает, когда идти проверять.
			-- Публикуем с шагом 0.05, чтобы не гонять репликацию каждый тик.
			if ownAI and math.abs(track - (model:GetAttribute("Track") or 0)) >= 0.05 then
				model:SetAttribute("Track", track)
			end

			-- ШКАЛА ЗАПОЛНИЛАСЬ → игрок обнаружен: бар навсегда переключается в HP,
			-- дальше это уже бой, а не подкрадывание.
			if track >= 1 then
				hpMode = true
				hb.setVisible(true)
				hb.setHP(humanoid.Health, humanoid.MaxHealth)
				model:SetAttribute("Detected", true)   -- свой ИИ переходит в бой
				print("[IslandClear] пират обнаружил игрока — бар переключён в HP")
				continue
			end

			if track ~= prev then
				hb.setTracking(track)
				hb.setVisible(track > 0.02) -- ноль слежки → над головой снова пусто
			end

			-- ПОЛОВИНА ШКАЛЫ → пират идёт проверять последнее место, где видел игрока.
			-- Продолжает идти и после того, как игрок скрылся: цель — точка, а не игрок.
			if track >= TRACK_INVESTIGATE and lastSeen and not ownAI then
				humanoid:MoveTo(lastSeen)
			elseif track <= 0.02 then
				lastSeen = nil -- потерял интерес
			end
		end
	end)
end

-- RemoteEvent, который слушает IslandClearedEffect.client.lua.
local effectRemote = ReplicatedStorage:FindFirstChild("IslandClearedEffect")
if not effectRemote then
	effectRemote = Instance.new("RemoteEvent")
	effectRemote.Name = "IslandClearedEffect"
	effectRemote.Parent = ReplicatedStorage
end

-- Клиент сообщает сюда, что катсцена доигралась → снимаем блокировку покупок.
local CUTSCENE_MAX = 60 -- страховочный таймаут, если клиент не ответит (вышел, ошибка)
local cutsceneDone = ReplicatedStorage:FindFirstChild("CutsceneDone")
if not cutsceneDone then
	cutsceneDone = Instance.new("RemoteEvent")
	cutsceneDone.Name = "CutsceneDone"
	cutsceneDone.Parent = ReplicatedStorage
end
cutsceneDone.OnServerEvent:Connect(function(player)
	player:SetAttribute("InCutscene", false)
end)

local islands  = {}  -- [islandModel] = { model, armed, cleared, everHadLive }
local setupDone = setmetatable({}, { __mode = "k" })

--====================================================
-- Починка HP конкретного пирата
--====================================================
local function normalizeEnemy(model, humanoid)
	-- 1) ForceField рвёт TakeDamage — убираем любые.
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("ForceField") then
			obj:Destroy()
		end
	end
	-- 2) Скрипты HP/респавна внутри модели.
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Script") then
			local lname = obj.Name:lower()
			if obj.Name == "Health" and obj.Disabled then
				obj.Disabled = false          -- вернуть регенерацию
			elseif lname:find("respawn") then
				-- Только ВЫКЛЮЧАЕМ, не удаляем: ZombieScript ищет рядом объект
				-- с именем Respawn (BindableFunction) и без него сыпал ошибкой
				-- "Monster does not have a Respawn BindableFunction". Отключённый
				-- скрипт уже никого не воскрешает, а объект остаётся на месте.
				obj.Disabled = true
			elseif obj.Name == "DeathAnimation" or lname:find("ragdoll") then
				-- Родная смерть модели отрывала шляпу и оружие в отдельные части
				-- («пират распался надвое»). Глушим и делаем свою — с отбросом.
				obj.Disabled = true
				obj:Destroy()
			end
		end
	end
	setupDeath(model, humanoid)
	-- 3) Дегенеративный риг (сохранён с MaxHealth 0) — даём ему нормальное HP.
	if humanoid.MaxHealth <= 0 then
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end
	-- 4) ЗАЯКОРЕННЫЙ риг — неподвижная статуя: Humanoid не может ни ходить, ни падать,
	-- выглядит «недееспособным». В шаблоне пиратов часто якорят, чтобы не падали в
	-- ReplicatedStorage, — в мире якорь надо снять.
	local anchored = 0
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Anchored then
			anchored += 1
			obj.Anchored = false
		end
	end
	if anchored > 0 then
		print(("[IslandClear] %s: снят якорь с %d партов (заякоренный враг стоял статуей)")
			:format(model.Name, anchored))
	end
	-- 4.5) ФИЗИКА NPC — ТОЛЬКО НА СЕРВЕРЕ. Иначе владение телом автоматически
	-- уходит ближайшему клиенту, а PirateIslandAI пишет CFrame (довороты) с
	-- сервера — два хозяина дёргают тело в разные стороны, и со стороны это
	-- выглядит телепортами (особенно в выпадах). pcall: сеттер валиден только
	-- на корне сборки, остальным партам он просто откажет.
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and not obj.Anchored then
			pcall(obj.SetNetworkOwner, obj, nil)
		end
	end
	humanoid.PlatformStand = false
	humanoid.Sit = false
	-- 5) Прибрежный враг не должен травиться токсичной водой, если окажется в воде.
	model:SetAttribute("WaterImmune", true)
	-- 6) ЗАСПАВНИЛСЯ МЁРТВЫМ (шаблон сохранён с Health=0, или физика порвала суставы,
	-- когда пират спавнится утопленным в геометрию острова) — реанимируем как можем.
	if humanoid.Health <= 0 then
		humanoid.MaxHealth = math.max(humanoid.MaxHealth, 100)
		humanoid.Health = humanoid.MaxHealth
		pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
		warn(("[IslandClear] %s заспавнился МЁРТВЫМ — реанимирован. Проверь шаблон острова: "
			.. "пират не должен быть сохранён мёртвым и не должен быть утоплен в геометрию "
			.. "(поставь чуть ВЫШЕ поверхности)"):format(model:GetFullName()))
	end
	-- 7) наш HP-бар над головой (и снос старого красного)
	attachHealthBar(model, humanoid)
end

--====================================================
-- Зачистка определяется по ФАКТУ: сканируем папку Enemies на живых врагов.
-- НЕ полагаемся на событийный учёт (Died / AncestryChanged) — он рассинхронивается
-- с реальностью, когда остров спавнится далеко, и тогда остров ложно «зачищался»
-- сразу при спавне, хотя пираты ещё живы.
--====================================================
local DEAD_STATE = Enum.HumanoidStateType.Dead

-- Жив ли враг ПО ФАКТУ. Не доверяем только Health: включённый скрипт регенерации может
-- поднять Health у МЁРТВОГО Humanoid обратно выше 0 — поэтому проверяем ещё и состояние
-- (Dead «залипает» навсегда). Иначе труп считался бы живым и остров не зачищался.
local function isEnemyAlive(m)
	if not m:IsA("Model") then return false end
	local h = m:FindFirstChildWhichIsA("Humanoid")
	if not h or h.Health <= 0 then return false end
	local ok, state = pcall(function() return h:GetState() end)
	if ok and state == DEAD_STATE then return false end
	return true
end

--[[ ⚠️ ВРАГИ ОСТРОВА ФЕРМЕРОВ ЛЕЖАТ НЕ В Enemies. Охрану и мутанта там ведёт
     рантайм пакета в Gameplay/NPCs (атрибут Hostile); в Enemies их класть нельзя —
     их бы подхватил PirateIslandAI вторым водителем. Считаем и тех, и других. ]]
local function liveEnemyCount(islandModel)
	local n = 0
	local enemies = islandModel:FindFirstChild(ENEMIES_FOLDER)
	if enemies then
		for _, m in ipairs(enemies:GetChildren()) do
			if isEnemyAlive(m) then n += 1 end
		end
	end
	local g = islandModel:FindFirstChild("Gameplay")
	local npcs = g and g:FindFirstChild("NPCs")
	if npcs then
		for _, m in ipairs(npcs:GetChildren()) do
			if m:GetAttribute("Hostile") == true and isEnemyAlive(m) then n += 1 end
		end
	end
	return n
end

--[[ ⚠️ ПОТЕРЯННЫЙ ВРАГ НЕ ДОЛЖЕН ДЕРЖАТЬ ОСТРОВ «НЕЗАЧИЩЕННЫМ».
     Пират, упавший в воду под островом, провалившийся сквозь рельеф или
     ушедший за игроком в море, остаётся живым в папке Enemies — игрок перебил
     всех, кого видел, а зачистка не засчитывается. Враг, который дольше LOST_SEC
     находится вне суши острова (по LandCenter/LandRadius спавнера) или ниже
     её уровня, считается потерянным и добивается сервером. ]]
local LOST_SEC = 8
local function sweepLost(island)
	local enemies = island.model:FindFirstChild(ENEMIES_FOLDER)
	if not enemies then return end
	local center = island.model:GetAttribute("LandCenter")
	if typeof(center) ~= "Vector3" then center = island.model:GetPivot().Position end
	local radius = (tonumber(island.model:GetAttribute("LandRadius")) or 350) + 80
	island.lostSince = island.lostSince or {}
	local now = os.clock()
	for _, m in ipairs(enemies:GetChildren()) do
		if isEnemyAlive(m) then
			local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			local pos = hrp and hrp.Position
			local lost = pos and ((Vector3.new(pos.X, 0, pos.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude > radius
				or pos.Y < center.Y - 20)
			if lost then
				island.lostSince[m] = island.lostSince[m] or now
				if now - island.lostSince[m] > LOST_SEC then
					print(("[IslandClear] %s: %s потерян (%.0f, %.0f, %.0f) — добит сервером"):format(
						island.model.Name, m.Name, pos.X, pos.Y, pos.Z))
					local h = m:FindFirstChildWhichIsA("Humanoid")
					if h then h.Health = 0 end
					island.lostSince[m] = nil
				end
			else
				island.lostSince[m] = nil
			end
		end
	end
end

local function checkCleared(island)
	if island.cleared or not island.armed then return end
	sweepLost(island)
	local live = liveEnemyCount(island.model)

	-- ДИАГНОСТИКА (временно): лог при изменении числа живых — показывает Health + состояние
	-- каждого врага в папке, чтобы видеть, почему счётчик не доходит до 0.
	if live ~= island.lastLive then
		island.lastLive = live
		local enemies = island.model:FindFirstChild(ENEMIES_FOLDER)
		local parts = {}
		if enemies then
			for _, m in ipairs(enemies:GetChildren()) do
				local h = m:IsA("Model") and m:FindFirstChildWhichIsA("Humanoid")
				if h then
					local ok, st = pcall(function() return h:GetState().Name end)
					table.insert(parts, ("%s[h=%.0f %s]"):format(m.Name, h.Health, ok and st or "?"))
				else
					table.insert(parts, tostring(m.Name) .. "[no-hum]")
				end
			end
		end
		print(("[ICDBG] %s live=%d everHadLive=%s | %s"):format(
			island.model.Name, live, tostring(island.everHadLive),
			(#parts > 0 and table.concat(parts, ", ") or "<пусто>")))
	end

	if live > 0 then
		island.everHadLive = true -- остров реально был населён живыми врагами
		return
	end
	-- live == 0: зачищаем ТОЛЬКО если до этого видели живых (иначе пустой / ещё не
	-- населённый остров «зачистился» бы сам сразу при спавне).
	if not island.everHadLive then return end
	--[[ ⚠️ ОСТРОВ МОЖЕТ ПОПРОСИТЬ ПРИДЕРЖАТЬ ЗАЧИСТКУ.
	     На аванпосте мало перебить гарнизон: за частоколом остаётся поле вируса,
	     и «остров зачищен» до того, как его выжгли, — прямая ложь игроку, да ещё
	     и с баннером и повстанцами поверх недоигранного сюжета. Сценарий острова
	     ставит ClearHold, пока держит своё, и снимает его, когда дело сделано.
	     Возврат БЕЗ island.cleared намеренный: следующий проход проверит снова и
	     сам всё запустит, как только флаг снимут. ]]
	if island.model:GetAttribute("ClearHold") == true then return end
	--[[ ⚠️ ПИРАТЫ — НЕ ВСЁ. Остров зачищен, когда перебит гарнизон, ВЗОРВАНЫ все
	     бочки вируса и ВЫЖЖЕНО всё красное поле — ровно те три ступени, что ведёт
	     квест острова (IslandQuestSystem). Раньше баннер «Остров зачищен!» падал
	     после последнего пирата, а поле стояло нетронутым (владелец). Имена и
	     атрибуты те же, что у TerraceIsland: Virus_drum/Exploded, Virus_crop_sm/Burnt.
	     Острова без бочек и поля это не задерживает: считать там нечего. ]]
	local leftDrums, leftCrops = 0, 0
	for _, d in ipairs(island.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name:sub(1, 10) == "Virus_drum" and not d:GetAttribute("Exploded") then leftDrums += 1
			elseif (d.Name:sub(1, 13) == "Virus_crop_sm" or d.Name:sub(1, 12) == "GH_BurnCrop_")
				and not d:GetAttribute("Burnt") then   -- префиксы как в TerraceIsland.CROP_PREFIXES
				leftCrops += 1
			end
		end
	end
	if leftDrums > 0 or leftCrops > 0 then
		if not island.holdLogged then
			island.holdLogged = true
			print(("[IslandClear] %s: гарнизон перебит, но осталось бочек %d, поля %d — жду"):format(
				island.model.Name, leftDrums, leftCrops))
		end
		return
	end
	island.cleared = true
	print("[IslandClear] " .. island.model.Name .. " зачищен — запускаю катсцену")
	-- на освободившийся остров выходят повстанцы (RebelIsland сам выждет катсцену)
	if _G.OnIslandCleared then
		task.spawn(function()
			local ok, err = pcall(_G.OnIslandCleared, island.model)
			if not ok then warn("[IslandClear] повстанцы: " .. tostring(err)) end
		end)
	end
	-- Пока идёт катсцена, покупки заблокированы: камера уводится от игрока, но доски
	-- остаются кликабельными, и можно было случайно купить улучшение «вслепую».
	-- Флаг — атрибут игрока (реплицируется клиенту, там гасим кнопки), снимается по
	-- сигналу CutsceneDone от клиента; таймаут — страховка, если клиент не ответит.
	for _, plr in ipairs(Players:GetPlayers()) do
		plr:SetAttribute("InCutscene", true)
	end
	task.delay(CUTSCENE_MAX, function()
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr:GetAttribute("InCutscene") then plr:SetAttribute("InCutscene", false) end
		end
	end)

	effectRemote:FireAllClients(island.model:GetPivot().Position)
end

-- Привести врага в боеспособный/убиваемый вид (ForceField прочь, Respawn off, HP fix).
local function normalizeOne(model)
	if not model:IsA("Model") then return end
	task.spawn(function()
		local humanoid = model:FindFirstChildWhichIsA("Humanoid")
			or model:WaitForChild("Humanoid", 5)
		if humanoid then normalizeEnemy(model, humanoid) end
	end)
end

local function setupIsland(islandModel)
	if setupDone[islandModel] then return end
	local enemies = islandModel:FindFirstChild(ENEMIES_FOLDER)
	if not enemies or not enemies:IsA("Folder") then return end
	setupDone[islandModel] = true

	local island = { model = islandModel, armed = false, cleared = false, everHadLive = false }
	islands[islandModel] = island
	print(("[IslandClear] setup %s — врагов в папке: %d"):format(islandModel.Name, #enemies:GetChildren()))

	-- Нормализуем текущих и будущих врагов, чтобы их вообще можно было убить.
	for _, child in ipairs(enemies:GetChildren()) do normalizeOne(child) end
	enemies.ChildAdded:Connect(normalizeOne)

	-- Небольшая пауза, чтобы свежезаспавненные враги успели инициализироваться, затем
	-- ОПРАШИВАЕМ фактическое число живых врагов, пока остров реально не зачищен. Так
	-- детект не «защёлкивается» на мгновенном пустом наборе и не зависит от событий.
	task.delay(1, function() island.armed = true end)
	task.spawn(function()
		while not island.cleared and islandModel.Parent do
			checkCleared(island)
			task.wait(0.5)
		end
	end)
end

--====================================================
-- Поиск островов (размещённых и заспавненных IslandSpawner'ом)
--====================================================
local function scanModel(inst)
	if inst:IsA("Model") and inst:FindFirstChild(ENEMIES_FOLDER) then
		setupIsland(inst)
	end
end

for _, child in ipairs(Workspace:GetChildren()) do
	scanModel(child)
end

Workspace.ChildAdded:Connect(function(child)
	if not child:IsA("Model") then return end
	-- Папка Enemies может появиться на пару кадров позже самой модели.
	if child:FindFirstChild(ENEMIES_FOLDER) then
		setupIsland(child)
	else
		local conn
		conn = child.ChildAdded:Connect(function(sub)
			if sub.Name == ENEMIES_FOLDER and sub:IsA("Folder") then
				if conn then conn:Disconnect() end
				setupIsland(child)
			end
		end)
		-- Не держим соединение вечно.
		task.delay(10, function() if conn then conn:Disconnect() end end)
	end
end)