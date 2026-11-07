--[[
	ПИРАТЫ ЛАГЕРЯ: поведение и анимации.

	ДВА РАЗНЫХ БОЯ, а не один на всех — это и была главная претензия к первой версии:
	  • СТРЕЛОК (револьвер) держит дистанцию: подходит на 60 студов, ближе 28 не
	    лезет, стреляет с проверкой линии огня. Урон, вспышка и звук — те же, что у
	    экипажа катеров, чтобы выстрел везде звучал одинаково.
	  • САБЛЯ идёт вплотную и бьёт с 5 студов. Урон в момент взмаха, а не при
	    касании: касание на R6 срабатывает как попало.

	АНИМАЦИИ — СВОИ КЛИПЫ, БЕЗ ПУБЛИКАЦИИ. Сервер называет клип, поза считается
	У КАЖДОГО КЛИЕНТА (PirateIslandAnim.client): Motor6D.Transform с сервера не
	реплицируется. Ассеты по AnimationId в неопубликованном плейсе не грузятся, а
	этот путь работает всегда — им же анимирован экипаж катеров.

	Клетку открывает смерть гарнизона: пока жив хоть один пират, семья сидит.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))
local CrewClips = require(ReplicatedStorage:WaitForChild("CrewClips"))
local C = Defs.COMBAT

-- ── анимация ──
-- ⚠️ СЕРВЕР ТОЛЬКО НАЗЫВАЕТ КЛИП, ПОЗУ СЧИТАЕТ КЛИЕНТ.
-- Motor6D.Transform, записанный на сервере, клиентам НЕ реплицируется — его шлёт
-- только Animator. Поэтому поза, посчитанная тут, была бы видна одному серверу, и
-- со стороны игрока пираты стояли бы столбами (что и происходило).
-- Здесь мы пишем в атрибуты имя клипа и момент старта, а PirateIslandAnim.client
-- у каждого игрока проигрывает его локально из той же таблицы.
local function setClip(model, name, once)
	if not name or not CrewClips.has(name) then return end
	if once then
		model:SetAttribute("ClipOnce", name)
		model:SetAttribute("ClipOnceT", workspace:GetServerTimeNow())
	elseif model:GetAttribute("Clip") ~= name then
		model:SetAttribute("Clip", name)
		model:SetAttribute("ClipT", workspace:GetServerTimeNow())
	end
end

-- Набор клипов по оружию: у сабли и револьвера разные простой, ходьба и удар.
local function clipSet(model)
	return Defs.ANIM[model:GetAttribute("WeaponKind") == "ranged" and "ranged" or "melee"]
end

-- ── ВАРИАНТЫ ПРОСТОЯ ──
-- Дежурный клип — <база>_Long (~15–20 с: база целиком + дыхание, перенос веса,
-- осмотр одной хореографией; собирается в хвосте PirateCrewClips). Он играет
-- РОВНО свой цикл, и на стыке циклов есть шанс на «действие» — один из коротких
-- вариантов (Look/Doze/Neck/Turn/Breathe/Sway), после которого пират
-- возвращается к дежурному. Все клипы семьи начинаются и заканчиваются одной
-- позой, а перекат происходит точно по длине клипа — стыки кадр-в-кадр.
local idleRoll = setmetatable({}, { __mode = "k" })
local chaseRoll = setmetatable({}, { __mode = "k" })   -- варианты бега погони

local ACTION_CHANCE = 0.45   -- шанс действия на стыке длинных циклов
local IDLE_ACTIONS = { "_Look", "_Doze", "_Neck", "_Turn", "_Breathe", "_Sway" }

-- длину клипа берём прямо из таблицы (CrewClips её не публикует)
local CLIP_TABLE = require(ReplicatedStorage:WaitForChild("PirateCrewClips")).clips
local function clipLen(name)
	local c = CLIP_TABLE[name]
	return c and c.length or 10
end

local function idleVariant(model, baseName)
	local now = os.clock()
	local r = idleRoll[model]
	if r and r.base == baseName and now < r.untilT then return r.name end

	local longName = baseName .. "_Long"
	local name = CrewClips.has(longName) and longName or baseName
	-- действие разыгрываем только НА СТЫКЕ дежурных циклов: после действия
	-- всегда возвращаемся к длинному, два действия подряд не идут
	if r and r.name == name and math.random() < ACTION_CHANCE then
		local suffix = IDLE_ACTIONS[math.random(#IDLE_ACTIONS)]
		if CrewClips.has(baseName .. suffix) then
			name = baseName .. suffix
		end
	end
	idleRoll[model] = { base = baseName, name = name, untilT = now + clipLen(name) }
	return name
end

local function loopAnim(model, key)
	-- ПЛЕННЫЙ. Руки связаны за спиной — это поза покоя, а не наложение поверх
	-- обычной, поэтому пиратский простой ему не годится: он бы двигался как
	-- охранник со связанными руками, и это видно сразу.
	if model:GetAttribute("Prisoner") then
		setClip(model, Defs.PRISONER_ANIM[key] or Defs.PRISONER_ANIM.idle)
		return
	end

	local set = clipSet(model)
	local name = set and set[key]
	-- на своём посту, пока никого не видит, у пирата своё занятие
	if key == "idle" then
		local post = model:GetAttribute("IslandPost")
		local busy = post and Defs.POST_IDLE[post]
		if busy and CrewClips.has(busy) then name = busy end
		-- разнообразие — только в мирное время: в бою «idle» — это стойка между
		-- выстрелами, и переминаться с ноги на ногу там не место
		if name and model:GetAttribute("Detected") ~= true then
			name = idleVariant(model, name)
		end
	end
	-- погоня тоже с вариантами: базовый бег и его пригнувшийся собрат чередуются
	if key == "run" and name then
		local now = os.clock()
		local r = chaseRoll[model]
		if not (r and r.base == name and now < r.untilT) then
			local pick = name
			if math.random() < 0.5 and CrewClips.has(name .. "_Lean") then
				pick = name .. "_Lean"
			end
			r = { base = name, name = pick, untilT = now + 4 + math.random() * 5 }
			chaseRoll[model] = r
		end
		name = r.name
	end
	setClip(model, name)
end

local function playOnce(model, key)
	if model:GetAttribute("Prisoner") then
		setClip(model, Defs.PRISONER_ANIM[key], true)
		return
	end
	local set = clipSet(model)
	setClip(model, (key == "attack") and set and set.attack or key, true)
end

-- ── цели ──
local function nearestPlayer(pos, maxDist)
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if d < (bestD or maxDist) then best, bestD = hrp, d end
		end
	end
	return best, bestD
end

local function lineOfSight(from, to, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return Workspace:Raycast(from, to - from, params) == nil
end

-- ── бой ──
local function faceTo(model, hrp, targetPos, maxTurn)
	local flat = Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
	if flat.Magnitude < 0.1 then return end
	-- ⚠️ ДОВОРОТ ПЛАВНЫЙ. Прямое CFrame.lookAt разворачивало пирата на цель
	-- МГНОВЕННО каждый тик — в выпаде это читалось как телепорт. Теперь крутим
	-- не больше maxTurn за тик (по умолчанию ≈160°/с); разовый полный доворот —
	-- передать math.pi (старт атаки).
	local lv = hrp.CFrame.LookVector
	local cur = math.atan2(-lv.X, -lv.Z)
	local want = math.atan2(-flat.X, -flat.Z)
	local dy = math.atan2(math.sin(want - cur), math.cos(want - cur))
	dy = math.clamp(dy, -(maxTurn or 0.55), maxTurn or 0.55)
	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, cur + dy, 0)
end

local function shoot(model, hrp, target)
	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local to = target.Position
	if not lineOfSight(origin, to, { model, target.Parent }) then return end

	playOnce(model, "attack")
	pcall(function()
		require(ReplicatedStorage:WaitForChild("MuzzleFX", 2))
			.burst(origin, (to - origin).Unit, { scale = 0.3, smoke = false })
	end)
	pcall(function()
		require(ReplicatedStorage:WaitForChild("CombatSounds", 2)).play("pistolShot", origin)
	end)

	local hum = target.Parent and target.Parent:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(model:GetAttribute("ShotDamage") or 15)
	end
end

-- ── САБЕЛЬНЫЕ ПАТТЕРНЫ ──
-- Урон НЕ мгновенный: атака объявляет клип, а урон засчитывается В МОМЕНТ УДАРА
-- этого клипа (hitAt согласован с ключами клипов в хвосте PirateCrewClips) и
-- только если клинок реально достал: дистанция проверяется в сам момент удара —
-- успел отбежать за замах, значит промах. На старте атаки — свист замаха,
-- «слэш» звучит только при попадании.
-- moveSpeed — с какой скоростью пират ДОНОСИТ атаку ногами: выпад делается
-- шагом вперёд (7), прыжок — на полном ходу (16), рубящие — стоя (0)
local SABRE_ATTACKS = {
	{ clip = "SabreSwing",   hitFrac = 0.45,            reachBonus = 1,   w = 0.40 },
	{ clip = "Sabre_Lunge",  hitAt = 0.45, len = 1.15,  reachBonus = 2.5, w = 0.32, moveSpeed = 7 },
	{ clip = "Sabre_Slash2", hitAt = 0.40, len = 0.95,  reachBonus = 1,   w = 0.28 },
}
-- прыжок с саблей: стартует с подлёта (Humanoid дорулит сближение сам), бьёт
-- сильнее и заметно реже
local SABRE_LEAP = { clip = "Sabre_Leap", hitAt = 0.78, len = 1.35, reachBonus = 2,
	moveSpeed = 16, dmgMult = 1.25 }

local atkSt = setmetatable({}, { __mode = "k" })

local function pickSabre()
	local roll, acc = math.random(), 0
	for _, def in ipairs(SABRE_ATTACKS) do
		acc += def.w
		if roll < acc and CrewClips.has(def.clip) then return def end
	end
	return SABRE_ATTACKS[1]
end

local function sfx(name, pos)
	pcall(function()
		require(ReplicatedStorage:WaitForChild("CombatSounds", 2)).play(name, pos)
	end)
end

local function startSabre(model, hrp, def, now, targetPos)
	local len = def.len or clipLen(def.clip)
	local hitAt = def.hitAt or (len * (def.hitFrac or 0.45))
	-- доворот на цель ОДИН РАЗ на старте замаха (полный): писать CFrame каждый
	-- тик нельзя — это и дёргало пирата «телепортами» во время выпада
	if targetPos then faceTo(model, hrp, targetPos, math.pi) end
	-- ⚠️ УДАР — НАЛОЖЕНИЕМ НА РУКУ, А НЕ ПОДМЕНОЙ ВСЕЙ ПОЗЫ.
	-- Полный клип подменял и ноги, поэтому пират ради взмаха вставал столбом.
	-- Канал ClipOverlay кладёт клип только на руку (см. PirateIslandAnim), и бег
	-- под ним продолжается: догоняет и рубит на ходу.
	model:SetAttribute("ClipOverlay", def.clip)
	model:SetAttribute("ClipOverlayT", workspace:GetServerTimeNow())
	sfx("sabreWhoosh", hrp.Position)
	atkSt[model] = {
		hitAt = now + hitAt,
		endAt = now + len,
		reach = C.meleeReach + (def.reachBonus or 1),
		moveSpeed = def.moveSpeed,
		dmgMult = def.dmgMult or 1,
	}
end

-- ── обход поста ──
-- Пираты из Defs.POST_WANDER в мирное время прохаживаются вокруг своей точки:
-- случайная цель в радиусе → дошёл → пауза с пост-идлом → следующая. Состояние
-- в слабой таблице: уехавший остров уносит записи сам.
local wanderSt = setmetatable({}, { __mode = "k" })

local function wanderStep(model, hum, hrp, home, radius, now)
	local ws = wanderSt[model]
	if not ws then
		ws = { waitUntil = now + math.random() * 4 }
		wanderSt[model] = ws
	end

	if ws.goal then
		local flat = Vector3.new(hrp.Position.X - ws.goal.X, 0, hrp.Position.Z - ws.goal.Z)
		if flat.Magnitude < 3 or now - (ws.startedAt or now) > 20 then
			-- дошёл (или застрял об декорацию — не тараним) → постоять со своим делом
			ws.goal = nil
			ws.waitUntil = now + 6 + math.random() * 9   -- стоит подолгу, гуляет изредка
		else
			hum.WalkSpeed = 5   -- прогулочный шаг, а не боевые перебежки
			hum:MoveTo(ws.goal)
			loopAnim(model, "walk")
			return
		end
	end

	if now >= (ws.waitUntil or 0) then
		local a = math.random() * math.pi * 2
		local d = (0.35 + 0.65 * math.random()) * radius
		ws.goal = Vector3.new(home.X + math.cos(a) * d, hrp.Position.Y, home.Z + math.sin(a) * d)
		ws.startedAt = now
		hum.WalkSpeed = 5
		hum:MoveTo(ws.goal)
		loopAnim(model, "walk")
	else
		hum:MoveTo(hrp.Position)
		loopAnim(model, "idle")   -- на паузе играет идл своего поста
	end
end

-- ── один шаг NPC ──
local function step(model, now)
	-- ⚠️ ГОРЯЩИЙ ОГЛУШЁН И ИИ ЕМУ НЕ ХОЗЯИН.
	-- Пока на человеке огонь, им целиком распоряжается FlamethrowerSystem: тот
	-- гоняет его к воде и крутит клипы паники. Без этого выхода пират продолжал
	-- бы гнаться и бить в упор прямо в пламени, а бег к воде спорил бы с боевым
	-- MoveTo — оба системы дёргали бы его в разные стороны.
	if model:GetAttribute("OnFire") then return end

	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	-- корень ищем ГЛУБОКО: риг может лежать под-моделью, прямой FindFirstChild его не видит
	local hrp = (hum and hum.RootPart)
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Torso", true)
	if not hum or not hrp or hum.Health <= 0 then return end

	local home = model:GetAttribute("HomeX") and
		Vector3.new(model:GetAttribute("HomeX"), hrp.Position.Y, model:GetAttribute("HomeZ"))

	-- ⚠️ ПОВОДОК С ГИСТЕРЕЗИСОМ, А НЕ ОДНИМ ПОРОГОМ.
	-- Раньше проверка была одна: дальше leash — домой, ближе — снова в погоню.
	-- Ровно на границе пират и дёргался: шаг назад — можно гнаться, шаг вперёд —
	-- пора домой, и так каждый тик. Со стороны это выглядело как стена перед ним.
	-- Теперь возврат — это СОСТОЯНИЕ: перешагнул поводок, идёт домой и не
	-- отвлекается, пока не вернётся заметно внутрь круга.
	if home then
		local dist = (hrp.Position - home).Magnitude
		local returning = model:GetAttribute("Returning") == true
		if dist > C.leash then
			returning = true
			model:SetAttribute("Returning", true)
		elseif returning and dist <= (C.leashBack or C.leash * 0.55) then
			returning = false
			model:SetAttribute("Returning", nil)
		end
		if returning then
			hum.WalkSpeed = 8
			hum:MoveTo(home)
			loopAnim(model, "walk")
			return
		end
	end

	-- ═══ ДО ОБНАРУЖЕНИЯ ═══
	-- ⚠️ АГРЕССИИ НЕТ ВООБЩЕ. Раньше пират сам аггрился на любого игрока в 90
	-- студах — без шкалы, сквозь стены. Шкалу подозрения ведёт IslandClearSystem
	-- (конус зрения, прямая видимость, день/ночь); здесь только читаем её итоги.
	if model:GetAttribute("Detected") ~= true then
		local track = model:GetAttribute("Track") or 0
		local sx, sz = model:GetAttribute("SeenX"), model:GetAttribute("SeenZ")
		local heardT = model:GetAttribute("HeardT")
		if track >= C.investigateAt and sx then
			-- полшкалы: идёт проверить место, где мелькнул игрок
			hum.WalkSpeed = 10   -- насторожен, но ещё не в бою
			hum:MoveTo(Vector3.new(sx, hrp.Position.Y, sz))
			loopAnim(model, "walk")
		elseif heardT and (now - heardT) <= C.hearCheck then
			-- СЛЫШАЛ ВЫСТРЕЛ (память пишет _G.PirateIslandShot): идёт к точке
			-- звука; дошёл — стоит и осматривается, пока память не остынет
			local spot = Vector3.new(model:GetAttribute("HeardX") or hrp.Position.X,
				hrp.Position.Y, model:GetAttribute("HeardZ") or hrp.Position.Z)
			if (hrp.Position - spot).Magnitude <= 5 then
				hum:MoveTo(hrp.Position)
				loopAnim(model, "idle")
			else
				hum.WalkSpeed = 9
				hum:MoveTo(spot)
				loopAnim(model, "walk")
			end
		else
			local wr = Defs.POST_WANDER and Defs.POST_WANDER[model:GetAttribute("IslandPost")]
			if wr and home then
				-- мирное время: этому посту положен обход, а не столб
				wanderStep(model, hum, hrp, home, wr, now)
			else
				hum.WalkSpeed = 8   -- спокойно вернуться на пост, без спринта
				hum:MoveTo(home or hrp.Position)
				loopAnim(model, (home and (hrp.Position - home).Magnitude > 4) and "walk" or "idle")
			end
		end
		return
	end

	-- ═══ БОЙ ═══
	-- Обнаружен, но НЕ всевидящий: стены обрывают зрение, память о последней точке
	-- живёт секунды. Потерял насовсем — остывает и возвращается к своим делам
	-- (IslandClearSystem увидит сброс Detected и вернёт шкалу слежки).
	hum.WalkSpeed = 16   -- бой: полная скорость (обход ходит прогулочной, 5)
	local target, dist = nearestPlayer(hrp.Position, C.aggro * 1.4)
	local sees = false
	if target then
		sees = lineOfSight(hrp.Position + Vector3.new(0, 1.5, 0), target.Position,
			{ model, target.Parent })
	end
	if sees then
		model:SetAttribute("SeenX", target.Position.X)
		model:SetAttribute("SeenZ", target.Position.Z)
		model:SetAttribute("SeenT", now)
		--[[ ⚠️ КРИК: ВИДИТ ИГРОКА — ЗОВЁТ СОСЕДЕЙ. Раньше сосед в двух шагах стоял
		     столбом, пока по нему не попадут или пока не заполнится его собственная
		     шкала (владелец). Теперь обнаруживший раз в shoutEvery секунд поднимает
		     всех своих в shoutRadius: Detected + точка, где игрок, чтобы бежали
		     туда, а не тыкались в стену. Пленных и мёртвых не будим. ]]
		if now - (model:GetAttribute("ShoutT") or 0) >= C.shoutEvery then
			model:SetAttribute("ShoutT", now)
			local folder = model.Parent
			if folder then
				for _, other in ipairs(folder:GetChildren()) do
					if other ~= model and other:IsA("Model") and other:GetAttribute("Detected") ~= true
						and not other:GetAttribute("Prisoner") then
						local oh = other:FindFirstChildWhichIsA("Humanoid", true)
						local orp = (oh and oh.RootPart) or other:FindFirstChild("HumanoidRootPart", true)
						if oh and oh.Health > 0 and orp
							and (orp.Position - hrp.Position).Magnitude <= C.shoutRadius then
							other:SetAttribute("SeenX", target.Position.X)
							other:SetAttribute("SeenZ", target.Position.Z)
							other:SetAttribute("SeenT", now)
							other:SetAttribute("AlertedBy", model.Name)
							other:SetAttribute("Detected", true)
						end
					end
				end
			end
		end
	elseif model:GetAttribute("SeenT") == nil then
		model:SetAttribute("SeenT", now)   -- обнаружен по ранению: точки ещё нет
	end
	local lost = now - (model:GetAttribute("SeenT") or now)

	if not target or lost > C.giveUp then
		model:SetAttribute("Detected", false)
		hum:MoveTo(home or hrp.Position)
		loopAnim(model, "walk")
		return
	end

	if not sees then
		-- цель за стеной: НЕ сквозь стену, а к последней точке, где её видел
		local sx, sz = model:GetAttribute("SeenX"), model:GetAttribute("SeenZ")
		if sx and lost <= C.forgetAfter then
			hum:MoveTo(Vector3.new(sx, hrp.Position.Y, sz))
		else
			hum:MoveTo(hrp.Position)   -- дошёл и никого: стоит насторожен, ждёт giveUp
		end
		loopAnim(model, "walk")
		return
	end

	local ranged = model:GetAttribute("WeaponKind") == "ranged"
	if ranged then
		-- ДЕРЖИТ ДИСТАНЦИЮ: далеко — подходит, близко — отступает, в вилке — стоит и стреляет
		if dist > C.rangedFire then
			hum:MoveTo(target.Position)
			loopAnim(model, "walk")
		elseif dist < C.rangedKeep then
			local away = (hrp.Position - target.Position)
			away = Vector3.new(away.X, 0, away.Z)
			hum:MoveTo(hrp.Position + (away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)) * 12)
			loopAnim(model, "walk")
		else
			hum:MoveTo(hrp.Position)
			loopAnim(model, "idle")
			faceTo(model, hrp, target.Position)
			if now - (model:GetAttribute("LastShot") or 0) >= C.shotCd then
				model:SetAttribute("LastShot", now)
				shoot(model, hrp, target)
			end
		end
	else
		-- САБЛЯ: паттерны. Начатый замах доигрывается, урон — в момент удара.
		local atk = atkSt[model]
		if atk then
			-- ⚠️ БЕЗ faceTo во время замаха: доворот сделан один раз на старте,
			-- дальше движущиеся атаки крутит AutoRotate самого Humanoid, а
			-- стоячие держат стойку. Ежетиковая запись CFrame дралась с физикой
			-- и читалась как телепорт.
			-- ⚠️ И БЕЗ ОСТАНОВКИ: удар наложен только на руку, ноги свободны —
			-- пират продолжает идти на цель, а не замирает ради взмаха.
			hum.WalkSpeed = atk.moveSpeed or 12
			hum:MoveTo(target.Position)
			loopAnim(model, (dist > C.meleeReach) and "run" or "walk")
			if not atk.hitDone and now >= atk.hitAt then
				atk.hitDone = true
				local hum2 = target.Parent and target.Parent:FindFirstChildWhichIsA("Humanoid")
				-- достал ли клинок — решается ЗДЕСЬ, в момент удара
				if hum2 and hum2.Health > 0
					and (target.Position - hrp.Position).Magnitude <= atk.reach then
					sfx("sabre", hrp.Position)
					hum2:TakeDamage((model:GetAttribute("MeleeDamage") or 10) * atk.dmgMult)
				end
			end
			if now >= atk.endAt then atkSt[model] = nil end
			return
		end

		local sinceSwing = now - (model:GetAttribute("LastSwing") or 0)
		-- ⚠️ ЗАМАХ НАЧИНАЕТСЯ НА ПОДБЕГЕ. Порог взят чуть шире дистанции удара:
		-- пока рука идёт в замах, ноги успевают донести пирата — и клинок
		-- встречает цель в движении, а не после остановки.
		if dist <= C.meleeReach * 1.6 and sinceSwing >= C.swingCd then
			-- обычный арсенал — мах, выпад или обратный рез
			model:SetAttribute("LastSwing", now)
			startSabre(model, hrp, pickSabre(), now, target.Position)
		elseif dist <= C.meleeReach * 2.6 and sinceSwing >= C.swingCd
			and now - (model:GetAttribute("LastLeap") or 0) >= 7 then
			-- ДОГНАЛ НА ПОДЛЁТЕ: прыжок с саблей вперёд
			model:SetAttribute("LastSwing", now)
			model:SetAttribute("LastLeap", now)
			hum:MoveTo(target.Position)
			startSabre(model, hrp, SABRE_LEAP, now, target.Position)
		elseif dist > C.meleeReach then
			hum:MoveTo(target.Position)
			loopAnim(model, "run")
		else
			-- вплотную, но сабля на перезарядке: держит стойку
			hum:MoveTo(hrp.Position)
			loopAnim(model, "idle")
			faceTo(model, hrp, target.Position)
		end
	end
end

-- ── общий цикл ──
-- Один цикл на всех: остров один, врагов полтора десятка, отдельный поток на
-- каждого — это те же вычисления плюс полтора десятка корутин.
-- ── СЛУХ ──
-- Оружие игрока зовёт сюда с точкой выстрела (см. RevolverServer): пираты в
-- C.hearRadius, ещё НЕ обнаружившие игрока, запоминают её и идут проверять —
-- ветка «до обнаружения» выше. Радиус нарочно небольшой: один хлопок с краю не
-- должен поднимать весь остров. Часы те же, что у step (os.clock).
_G.PirateIslandShot = function(pos)
	if typeof(pos) ~= "Vector3" then return end
	local now = os.clock()
	for _, island in ipairs(Workspace:GetChildren()) do
		if Defs.isCrewIsland(island) then
			local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
			if enemies then
				for _, npc in ipairs(enemies:GetChildren()) do
					if npc:IsA("Model") and npc:GetAttribute("Detected") ~= true then
						local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
						local hrp = (hum and hum.RootPart)
							or npc:FindFirstChild("HumanoidRootPart", true)
						if hum and hum.Health > 0 and hrp
							and (hrp.Position - pos).Magnitude <= C.hearRadius then
							npc:SetAttribute("HeardX", pos.X)
							npc:SetAttribute("HeardZ", pos.Z)
							npc:SetAttribute("HeardT", now)
						end
					end
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(C.tick)
		local now = os.clock()
		for _, island in ipairs(Workspace:GetChildren()) do
			if Defs.isCrewIsland(island) then
				local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
				if enemies then
					for _, npc in ipairs(enemies:GetChildren()) do
						if npc:IsA("Model") then
							local ok, err = pcall(step, npc, now)
							if not ok then warn("[ПиратОстров] ИИ: " .. tostring(err)) end
						end
					end
				end
			end
		end
	end
end)

-- Наружу: этим же играет idle пленным и анимирует их выход из клетки.
_G.PirateIslandAnim = { loop = loopAnim, once = playOnce }
