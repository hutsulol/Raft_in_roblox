-- WaveDirector.server.lua
-- Runs a fresh STORM every day, on a rotating world side (E / W / N / S). Independent of whether
-- last night's mobs were all killed:
--   • DAWN          → the old cloud clears; a FRESH side is rolled (always different from before)
--   • FOG_AT of day → the storm cloud rises on that side (WaveTelegraph.client shows the fog)
--   • DUSK          → this night's wave spawns from the cloud
--   • through night → the cloud stays up; it clears again at the next dawn
-- Published for everyone via workspace attributes:
--   • WaveDir       (Vector3) — the world direction the storm/wave comes from
--   • WaveTelegraph (bool)    — true once the cloud has risen (FOG_AT → next dawn), false otherwise
-- Spawning reuses each enemy spawner's OWN logic via globals (their continuous loops stay OFF):
--   _G.SpawnEnemyShip(dir, hpMult) / _G.SpawnRaftEater(dir, hpMult) / _G.SpawnSwimmingPirate(dir, hpMult)
-- The wave ramps across 5 nights (WAVES below): each night = MORE enemies with MORE HP (hpMult).
-- ONE random ship of each wave carries the reward crate (CrateNight attribute): destroying that
-- ship bursts the crate out of the wreck (ShipCombat → _G.EjectRewardCrate → RewardCrate.server).

local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local dayCount = ReplicatedStorage:WaitForChild("DayCount")

-- the four world directions a wave can come from (DayNightCircle: day = ClockTime 6→18)
local DIRECTIONS = {
	Vector3.new(1, 0, 0),   -- East
	Vector3.new(-1, 0, 0),  -- West
	Vector3.new(0, 0, 1),   -- South
	Vector3.new(0, 0, -1),  -- North
}

-- which enemies arrive on the night of each day, and how tough they are.
--   ships / zombies (Raft-Eaters) / pirates = how MANY of each spawn that night
--   hpMult                                  = every spawned enemy's HP is multiplied by this
-- The 5-night ramp: each night sends more enemies AND makes them tankier. A night with no entry
-- (day 6+) simply spawns nothing — add rows here to extend the siege further.
-- ВХОД В ОСАДУ МЯГКИЙ: первая ночь — только два зомби (без кораблей и абордажников),
-- вторая добавляет одного абордажника, и лишь третья выводит ПЕРВЫЙ корабль. У новичка
-- в первую ночь нет ни пушек, ни патронов, а корабль требует и того, и другого.
-- ⚠️ Ящик с наградой выпадает из УНИЧТОЖЕННОГО корабля, поэтому в ночи 1–2 его нет.
local WAVES = {
	[1] = { ships = 0, zombies = 2, pirates = 0, hpMult = 1.0 }, -- первая ночь — только два зомби
	[2] = { ships = 0, zombies = 2, pirates = 1, hpMult = 1.3 }, -- + один абордажник
	[3] = { ships = 1, zombies = 3, pirates = 2, hpMult = 1.6 }, -- первый корабль
	[4] = { ships = 2, zombies = 4, pirates = 3, hpMult = 2.0 },
	[5] = { ships = 3, zombies = 5, pirates = 4, hpMult = 2.5 }, -- пятая ночь — вал
}

-- ⚠️ ОСАДА НАЧИНАЕТСЯ С ПЯТОГО ДНЯ, ДО НЕГО МОРЕ ПУСТОЕ.
-- Первые четыре дня игроку дают обжиться: ни тумана, ни волн, ни мобов. Считать
-- это «нулевыми строками в WAVES» нельзя — тогда пропал бы мягкий вход в осаду,
-- который в таблице и записан. Поэтому таблица остаётся как есть, а номер ночи
-- пересчитывается: ночь 5 играет первую строку, ночь 6 — вторую и так далее.
local SIEGE_FROM_DAY = 5

-- ⚠️ СЕКРЕТНАЯ ВОЛНА (тест): код 67 в поле дня кнопки «Начать ночь» — ночь пятого
-- дня, но вместо штатной волны выходит ОДИН ледяной корабль и больше ничего.
-- Действует один раз, на ближайший закат.
local secretWave = nil
local SECRET_WAVES = {
	frost = { ships = 1, zombies = 0, pirates = 0, hpMult = 1.0, frostOnly = true },
}
_G.SetSecretWave = function(kind)
	secretWave = SECRET_WAVES[kind]
	print("[WaveDirector] секретная волна на ближайшую ночь: " .. tostring(kind))
	return secretWave ~= nil
end

local function waveFor(nightNumber)
	if secretWave then
		local w = secretWave
		secretWave = nil
		return w
	end
	if nightNumber < SIEGE_FROM_DAY then return nil end
	return WAVES[nightNumber - SIEGE_FROM_DAY + 1]
end

local SPAWN_GAP = 1.3 -- пауза между спавнами: враги появляются ПО ОДНОМУ, а не всей пачкой (было 0.4)

local function isDay()
	local t = Lighting.ClockTime
	return t >= 6 and t < 18
end

-- a dedicated seeded RNG: the shared math.random rolled the SAME first side every session
local rng = Random.new(os.clock() * 1e6)
-- the side the LAST wave came from — so a fresh roll always lands on a DIFFERENT side (the fog
-- never rises twice in a row from the same direction)
local lastSideIndex = nil
local function rollSide()
	local idx = lastSideIndex
	if #DIRECTIONS <= 1 then
		idx = 1
	else
		repeat idx = rng:NextInteger(1, #DIRECTIONS) until idx ~= lastSideIndex
	end
	lastSideIndex = idx
	Workspace:SetAttribute("WaveDir", DIRECTIONS[idx])
end

-- night 1 is pitch-dark on the raft — glow every enemy so the player can actually see the threat.
-- The Highlight renders independent of scene lighting, so it reads even with no light on the raft.
local function highlightEnemy(inst)
	if typeof(inst) ~= "Instance" then return end
	local hl = Instance.new("Highlight")
	hl.Adornee = inst
	hl.FillTransparency = 1 -- ТОЛЬКО обводка — никакой заливки поверх модели
	hl.OutlineColor = Color3.fromRGB(255, 255, 255) -- белый контур: максимально читается в темноте
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- visible even in the dark / behind cover
	hl.Parent = inst
end

-- ══════════════ УЧЁТ ЖИВЫХ ВРАГОВ ВОЛНЫ (для кровати) ══════════════
-- Сигнал ПОЛОЖИТЕЛЬНЫЙ: Workspace.WaveClearedNight = номер ночи, волна которой
-- уже зачищена. Кровать пускает спать, только если это ТЕКУЩАЯ ночь.
--
-- Почему не «флаг WaveActive»: он давал две дыры. Во-первых, гонку на закате —
-- ночь наступает мгновенно, а цикл фазировки опрашивает время раз в 0.5с, и в
-- это окно игрок успевал лечь до выставления флага. Во-вторых, состояние жило в
-- замыкании каждой волны, и смерть недобитого моба ПРОШЛОЙ ночи снимала флаг
-- посреди новой. Теперь состояние одно на модуль и относится строго к текущей ночи.
local waveEnemies  = {}    -- [instance] = true, только враги ТЕКУЩЕЙ ночи
local waveSpawning = false -- волна ещё выходит (враги идут по одному)
local waveNight    = 0

Workspace:SetAttribute("WaveClearedNight", 0)

local function trackWaveEnemy(inst)
	waveEnemies[inst] = true
end

-- Считаем живых ПО ФАКТУ, а не счётчиком: счётчик рассинхронизируется, если враг
-- исчез без события (выгрузка, уход за границу мира, удаление извне).
local function aliveWaveEnemies()
	local alive = 0
	for inst in pairs(waveEnemies) do
		local alive_ = inst.Parent ~= nil
		if alive_ then
			local hum = inst:FindFirstChildWhichIsA("Humanoid")
			if hum and hum.Health <= 0 then alive_ = false end
		end
		if alive_ then alive += 1 else waveEnemies[inst] = nil end
	end
	return alive
end

local function markClearedIfDone()
	if waveSpawning or waveNight <= 0 then return end
	if aliveWaveEnemies() == 0 then
		Workspace:SetAttribute("WaveClearedNight", waveNight)
	end
end

-- Периодическая сверка: ловит и обычную зачистку, и врагов, пропавших молча.
task.spawn(function()
	while true do
		task.wait(1)
		markClearedIfDone()
	end
end)

-- spawn the given night's wave from the current WaveDir side. ONE random ship of the wave is
-- marked as the crate carrier (1 ship → that one; several → any of them): when the player DESTROYS
-- it, the crate bursts out of the wreck together with its coins/pirates (ShipCombat calls
-- _G.EjectRewardCrate). No destroyed carrier → no crate that night; leftover mobs never block
-- the next day's storm or wave.
local function spawnWave(nightNumber)
	local wave = waveFor(nightNumber)
	if not wave then
		-- ночи без волны (6+): зачищать нечего — сразу помечаем ночь зачищенной,
		-- иначе кровать осталась бы заблокированной навсегда
		waveNight, waveSpawning, waveEnemies = nightNumber, false, {}
		Workspace:SetAttribute("WaveClearedNight", nightNumber)
		return
	end
	local dir = Workspace:GetAttribute("WaveDir")
	if typeof(dir) ~= "Vector3" then dir = nil end
	local hp = wave.hpMult or 1 -- this night's HP multiplier, applied to every enemy it spawns
	print(("[WaveDebug] night %d wave, storm side dir=%s hpMult=%.2f"):format(nightNumber, tostring(dir), hp))

	-- эта ночь ещё не зачищена: сбрасываем список на СВОИХ врагов (остатки прошлых
	-- ночей больше не учитываются — иначе один зависший моб блокировал бы кровать)
	waveNight, waveSpawning, waveEnemies = nightNumber, true, {}

	task.spawn(function()
		-- Спавн — в pcall: если _G.Spawn* бросит ошибку, корутина умрёт, не сняв
		-- waveSpawning, и ночь НИКОГДА не пометится зачищенной — кровать была бы
		-- мертва до перезапуска сервера.
		local ok, err = pcall(function()
		local glow = (nightNumber == 1) -- dark first night → outline the enemies
		local ships = {}
		local mobs = {} -- зомби + пираты (НЕ корабли) — кандидаты на дроп ящика с патронами
		for _ = 1, (wave.ships or 0) do
			if _G.SpawnEnemyShip then
				local ship = _G.SpawnEnemyShip(dir, hp, wave.frostOnly)
				if typeof(ship) == "Instance" then
					ships[#ships + 1] = ship
					trackWaveEnemy(ship)
					if glow then highlightEnemy(ship) end
				end
			end
			task.wait(SPAWN_GAP)
		end
		-- a random ship carries tonight's reward crate
		if #ships > 0 then
			ships[rng:NextInteger(1, #ships)]:SetAttribute("CrateNight", nightNumber)
		end
		for _ = 1, (wave.zombies or 0) do
			if _G.SpawnRaftEater then
				local z = _G.SpawnRaftEater(dir, hp)
				if typeof(z) == "Instance" then
					mobs[#mobs + 1] = z
					trackWaveEnemy(z)
					if glow then highlightEnemy(z) end
				end
			end
			task.wait(SPAWN_GAP)
		end
		for _ = 1, (wave.pirates or 0) do
			if _G.SpawnSwimmingPirate then
				local p = _G.SpawnSwimmingPirate(dir, hp)
				if typeof(p) == "Instance" then
					mobs[#mobs + 1] = p
					trackWaveEnemy(p)
					if glow then highlightEnemy(p) end
				end
			end
			task.wait(SPAWN_GAP)
		end

		-- ── ЯЩИК С ПАТРОНАМИ В ВОЛНЕ ──
		-- Заранее решаем (50%), будет ли в этой волне ящик с патронами. Если да — назначаем
		-- его СЛУЧАЙНОМУ мобу (не кораблю): при СМЕРТИ этого моба ящик выпадает в его точке
		-- и плавает в море (AmmoCaseSystem: mode "sea", не тонет).
		if _G.SpawnAmmoCase and #mobs > 0 and rng:NextNumber() < 0.5 then
			local mob = mobs[rng:NextInteger(1, #mobs)]
			local dropped = false
			local function dropCase()
				if dropped then return end
				dropped = true
				local part = mob.PrimaryPart or mob:FindFirstChild("HumanoidRootPart")
					or mob:FindFirstChildWhichIsA("BasePart")
				local pos = part and part.Position or mob:GetPivot().Position
				_G.SpawnAmmoCase(CFrame.new(pos + Vector3.new(0, 1, 0)), "sea")
				print("[WaveDebug] ящик с патронами выпал с моба " .. mob.Name)
			end
			local hum = mob:FindFirstChildWhichIsA("Humanoid")
			if hum then
				hum.Died:Once(dropCase)
			else
				mob.AncestryChanged:Connect(function(_, parent)
					if parent == nil then dropCase() end
				end)
			end
			print("[WaveDebug] в этой волне ящик с патронами — назначен мобу " .. mob.Name)
		end
		end) -- конец pcall спавна

		-- ВСЕГДА снимаем «волна ещё выходит», даже если спавн упал: иначе ночь
		-- никогда не пометится зачищенной и кровать будет заблокирована навсегда
		waveSpawning = false
		if not ok then
			warn("[WaveDirector] спавн волны упал: " .. tostring(err) .. " — волна считается выпущенной")
		end
		markClearedIfDone() -- волна могла быть добита прямо во время спавна
	end)
end

-- the fog telegraph rises at this fraction of the day — доля дня, поэтому окно
-- подготовки масштабируется вместе с длиной суток (при дне 500с туман встаёт на
-- 300-й секунде и на подготовку остаётся ~200с)
local FOG_AT = 0.6

-- 0→1 through the day (ClockTime 6→18), nil at night
local function dayProgress()
	local t = Lighting.ClockTime
	if t >= 6 and t < 18 then return (t - 6) / 12 end
	return nil
end

-- the storm cloud is up from FOG_AT of the day, through the whole night, until the next dawn
-- ⚠️ ДО ПЯТОГО ДНЯ ТУМАНА НЕТ ВООБЩЕ.
-- Он телеграфирует волну, а волны до этого дня не будет — поднятая стена без
-- атаки только пугала бы впустую. Ночь 5 наступает в конце пятого дня, и туман
-- поднимается в тот же день, за 40% до заката: игрок видит, что идёт первая.
local function stormUp()
	if dayCount.Value < SIEGE_FROM_DAY then return false end
	local p = dayProgress()
	return (p == nil) or (p >= FOG_AT) -- night → up; day → up only past FOG_AT (so it's OFF at dawn)
end

-- initial state
rollSide()
local wasDay = isDay()
Workspace:SetAttribute("WaveTelegraph", stormUp())

-- Day/night phasing — a fresh storm EVERY day, regardless of last night's leftovers:
--   dawn → stormUp() is already false early in the day, so the old cloud clears; roll a NEW side
--   FOG_AT of the day → stormUp() flips true and the cloud rises on that new side
--   dusk → tonight's wave spawns from the cloud (its OWN mobs, tracked separately for the crate)
task.spawn(function()
	while true do
		task.wait(0.5)
		local day = isDay()
		if day ~= wasDay then
			wasDay = day
			if day then
				rollSide()                -- DAWN: pick a fresh side for tonight's storm
				-- Ночь кончилась — снимаем блокировку кровати независимо от остатков.
				-- Иначе враг, который не умер и не удалился (застрял в геометрии,
				-- уплыл за границу мира), держал бы её бессрочно.
				waveSpawning, waveEnemies = false, {}
				if waveNight > 0 then
					Workspace:SetAttribute("WaveClearedNight", waveNight)
				end
			else
				spawnWave(dayCount.Value) -- DUSK: send this night's wave from the cloud
			end
		end
		Workspace:SetAttribute("WaveTelegraph", stormUp())
	end
end)
