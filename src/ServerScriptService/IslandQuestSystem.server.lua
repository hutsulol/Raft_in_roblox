--[[ IslandQuestSystem — КВЕСТ «ЗАЧИСТИ ОСТРОВ» С ТАЙМЕРОМ И БОНУСОМ.

     Игрок ступает на остров с гарнизоном (папка Enemies, остров не зачищен) —
     у всех, кто рядом с островом, появляется карточка квеста (клиент:
     Quests/IslandQuestCard.client.lua). Первые TIMER_SEC секунд вместо «?» на
     ней таймер: успели зачистить остров до конца отсчёта — тот, чьё действие
     стало последним результативным (добил последнего пирата, сжёг последний
     куст, взорвал бочку), получает BONUS монет с анимацией над головой, которую
     видят все вокруг. Таймер вышел — бонуса нет, зато открывается «?» с
     пошаговыми подсказками (подсветка пиратов по одному, стрелки над бочками и
     полями) — это уже целиком на клиенте по состоянию отсюда.

     ⚠️ САМА ЗАЧИСТКА ЗДЕСЬ НЕ РЕШАЕТСЯ. Кто зачищен — говорит IslandClearSystem
     (живые в Enemies + ClearHold сценария), а флаг Cleared на модель ставит
     MapSystem по _G.OnIslandCleared. Мы только читаем факт и считаем прогресс,
     иначе два счётчика разъехались бы, как всегда бывает с копиями.

     ⚠️ КТО СДЕЛАЛ ПОСЛЕДНЕЕ ДЕЙСТВИЕ — АТРИБУТ ОСТРОВА LastActorId.
     Смерть пирата пишем сюда сами (по LastHitBy на модели — его ставят топор и
     огнемёт, — по classic-тегу creator в Humanoid или по ближайшему игроку);
     сгоревший куст и взорванную бочку пишет TerraceIsland, там известен
     поджигатель. Один атрибут — одно место правды для всех трёх механик. ]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LOG = "[ОстровКвест]"
local POLL        = 0.5
local TIMER_SEC   = 180     -- три минуты на бонус
local BONUS       = 30      -- монет за быструю зачистку
local CREDIT_RANGE = 80     -- ближайший игрок к трупу, если оружие не подписалось
local LAND_PREFIX = "island_terrain"
local DRUM_NAME   = "Virus_drum"
local CROP_NAME   = { "Virus_crop_sm", "GH_BurnCrop_" }   -- трава BurnGrass_ горит, но в квест не входит
local ENEMIES     = "Enemies"
local DONE_LINGER = 6       -- сколько секунд карточка «Остров зачищен» ещё висит

local remote = ReplicatedStorage:FindFirstChild("IslandQuest")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "IslandQuest"
	remote.Parent = ReplicatedStorage
end

-- [island] = { startedAt, deadline, total, done, doneAt, hooked = {}, cropsTotal, last = {} }
local quests = {}

-- зачистку ловим и по хуку, не только по атрибуту Cleared: сюжетный остров
-- (аванпост) в реестр карты может не входить, и атрибут ему никто не поставит
local clearedByHook = setmetatable({}, { __mode = "k" })
local prevCleared = _G.OnIslandCleared
_G.OnIslandCleared = function(model)
	clearedByHook[model] = true
	if prevCleared then pcall(prevCleared, model) end
end

-- ── остров под игроком ──
local function topModel(inst)
	local m = inst
	while m and m.Parent ~= Workspace do m = m.Parent end
	return (m and m:IsA("Model")) and m or nil
end

local function isHostileIsland(m)
	return m ~= nil and m:FindFirstChild(ENEMIES) ~= nil and not m:GetAttribute("Cleared")
end

-- центр и радиус суши: атрибуты спавнера, а без них — по плиткам рельефа
local landCache = setmetatable({}, { __mode = "k" })
local function landOf(island)
	local c, r = island:GetAttribute("LandCenter"), tonumber(island:GetAttribute("LandRadius"))
	if typeof(c) == "Vector3" and r then return c, r end
	if landCache[island] then return landCache[island].c, landCache[island].r end
	local lo, hi
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #LAND_PREFIX) == LAND_PREFIX then
			local half = d.Size * 0.5
			local a, b = d.Position - half, d.Position + half
			lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
			hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
		end
	end
	if not lo then c, r = island:GetPivot().Position, 300
	else c, r = (lo + hi) * 0.5, math.max(hi.X - lo.X, hi.Z - lo.Z) * 0.5 end
	landCache[island] = { c = c, r = r }
	return c, r
end

--[[ ⚠️ «НА ОСТРОВЕ» — ПО КРУГУ СУШИ, А НЕ ПО ЛУЧУ ПОД НОГАМИ.
     Луч упирался в то, на чём игрок стоит: камень, куст, доску причала — и
     плитку рельефа не видел, квест не стартовал. Круг по центру и радиусу суши
     плюс высота (не под водой и не в небе) надёжнее. ]]
local function islandUnderPlayer(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local pos = hrp.Position
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and isHostileIsland(m) then
			local c, r = landOf(m)
			local flat = (Vector3.new(c.X, 0, c.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
			if flat <= r and math.abs(pos.Y - c.Y) < 80 then return m end
		end
	end
	return nil
end

-- ── учёт врагов ──
local DEAD = Enum.HumanoidStateType.Dead
local function isAlive(m)
	if not m:IsA("Model") then return false end
	local h = m:FindFirstChildWhichIsA("Humanoid")
	if not h or h.Health <= 0 then return false end
	local ok, st = pcall(function() return h:GetState() end)
	return not (ok and st == DEAD)
end

-- враги острова фермеров (охрана, мутант) лежат в Gameplay/NPCs с атрибутом Hostile
local function hostileFolder(island)
	local g = island:FindFirstChild("Gameplay")
	return g and g:FindFirstChild("NPCs") or nil
end
local function aliveCount(island)
	local n = 0
	local f = island:FindFirstChild(ENEMIES)
	if f then
		for _, m in ipairs(f:GetChildren()) do if isAlive(m) then n += 1 end end
	end
	local h = hostileFolder(island)
	if h then
		for _, m in ipairs(h:GetChildren()) do if m:GetAttribute("Hostile") == true and isAlive(m) then n += 1 end end
	end
	return n
end

local function nearestPlayer(pos)
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < CREDIT_RANGE and (not bestD or d < bestD) then best, bestD = p, d end
		end
	end
	return best
end

-- кто добил: подпись оружия → classic-тег creator → ближайший
local function killerOf(model, hum)
	local id = tonumber(model:GetAttribute("LastHitBy"))
	if id and Players:GetPlayerByUserId(id) then return id end
	local tag = hum and hum:FindFirstChild("creator")
	if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then return tag.Value.UserId end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local p = root and nearestPlayer(root.Position)
	return p and p.UserId or nil
end

local function hookEnemies(island, q)
	local list = {}
	local f = island:FindFirstChild(ENEMIES)
	if f then for _, m in ipairs(f:GetChildren()) do table.insert(list, m) end end
	local h = hostileFolder(island)
	if h then for _, m in ipairs(h:GetChildren()) do if m:GetAttribute("Hostile") == true then table.insert(list, m) end end end
	for _, m in ipairs(list) do
		if m:IsA("Model") and not q.hooked[m] then
			local hum = m:FindFirstChildWhichIsA("Humanoid")
			if hum then
				q.hooked[m] = true
				hum.Died:Connect(function()
					q.killed += 1
					local id = killerOf(m, hum)
					if id then island:SetAttribute("LastActorId", id) end
				end)
			end
		end
	end
end

-- ── бочки и поля ──
local function countParts(island, prefix, skipAttr)
	local list = type(prefix) == "table" and prefix or { prefix }
	local n = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and not (skipAttr and d:GetAttribute(skipAttr)) then
			for _, pre in ipairs(list) do
				if d.Name:sub(1, #pre) == pre then n += 1 break end
			end
		end
	end
	return n
end

-- ── снимок для клиентов ──
local function snapshot(island, q)
	local alive = aliveCount(island)
	-- подкрепление (враг появился после старта) растит общее число, а не крадёт убитых
	q.total = math.max(q.total, q.killed + alive)
	local killed = q.killed
	local drums = countParts(island, DRUM_NAME, "Exploded")
	local cropsLeft = countParts(island, CROP_NAME, "Burnt")
	local hold = island:GetAttribute("ClearHold") == true
	local stage
	if q.done then stage = "done"
	elseif alive > 0 then stage = "pirates"
	elseif hold and cropsLeft > 0 then stage = (drums > 0) and "barrels" or "crops"
	else stage = "wait" end
	local now = Workspace:GetServerTimeNow()
	return {
		island = island, stage = stage,
		alive = alive, total = q.total, killed = killed,
		drums = drums, cropsLeft = cropsLeft, cropsTotal = q.cropsTotal,
		deadline = q.deadline, expired = now > q.deadline and not q.done,
		done = q.done, winner = q.winner, bonus = q.bonusGiven and BONUS or nil,
	}
end

local function startQuest(island)
	if quests[island] then return end
	local now = Workspace:GetServerTimeNow()
	local q = {
		startedAt = now, deadline = now + TIMER_SEC,
		total = aliveCount(island), killed = 0,
		cropsTotal = countParts(island, CROP_NAME, "Burnt"),
		hooked = {}, done = false,
	}
	quests[island] = q
	hookEnemies(island, q)
	print(("%s %s: старт, пиратов %d, кустов %d, бочек %d, таймер %d с"):format(
		LOG, island.Name, q.total, q.cropsTotal, countParts(island, DRUM_NAME, "Exploded"), TIMER_SEC))
end

local function finishQuest(island, q)
	q.done = true
	q.doneAt = Workspace:GetServerTimeNow()
	local inTime = q.doneAt <= q.deadline
	local winner = nil
	local id = tonumber(island:GetAttribute("LastActorId"))
	if id then winner = Players:GetPlayerByUserId(id) end
	if not winner then
		local c = island:GetAttribute("LandCenter")
		if typeof(c) == "Vector3" then
			local best, bestD
			for _, p in ipairs(Players:GetPlayers()) do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local d = (hrp.Position - c).Magnitude
					if not bestD or d < bestD then best, bestD = p, d end
				end
			end
			winner = best
		end
	end
	if inTime and winner then
		q.winner = winner.Name
		q.bonusGiven = true
		if _G.AddPirate then pcall(_G.AddPirate, winner, BONUS)
		else winner:SetAttribute("Pirate", (winner:GetAttribute("Pirate") or 0) + BONUS) end
		local rain = ReplicatedStorage:FindFirstChild("CoinRain")
		if rain and rain:IsA("RemoteEvent") then rain:FireClient(winner, BONUS) end
		-- анимацию над головой видят ВСЕ: событие всем клиентам, они сами найдут голову
		remote:FireAllClients("bonus", winner, BONUS)
		print(("%s %s: зачищен за %.0f с — бонус %d монет → %s"):format(
			LOG, island.Name, q.doneAt - q.startedAt, BONUS, winner.Name))
	else
		print(("%s %s: зачищен %s — бонуса нет (%s)"):format(LOG, island.Name,
			inTime and "вовремя" or "после таймера", winner and "" or "некому"))
	end
end

-- ── цикл ──
task.spawn(function()
	while true do
		task.wait(POLL)
		-- старт: кто-то ступил на враждебный остров
		for _, plr in ipairs(Players:GetPlayers()) do
			local island = islandUnderPlayer(plr)
			if island and not quests[island] and aliveCount(island) > 0 then
				startQuest(island)
			end
		end
		-- прогресс и завершение
		local now = Workspace:GetServerTimeNow()
		for island, q in pairs(quests) do
			if not island.Parent then
				quests[island] = nil
				remote:FireAllClients("gone", island)
			else
				if not q.done then
					hookEnemies(island, q)
					if island:GetAttribute("Cleared") or clearedByHook[island] then finishQuest(island, q) end
				elseif now - q.doneAt > DONE_LINGER then
					quests[island] = nil
					remote:FireAllClients("gone", island)
					continue
				end
				remote:FireAllClients("state", snapshot(island, q))
			end
		end
	end
end)

print(LOG .. " готов: таймер " .. TIMER_SEC .. " с, бонус " .. BONUS .. " монет последнему результативному")
