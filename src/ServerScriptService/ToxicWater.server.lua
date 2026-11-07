local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local Config = require(rs:WaitForChild("WeaponUpgradeConfig"))

local DAMAGE_PERCENT = 0.10  -- 10% of max health per second
local CHECK_INTERVAL = 1
--[[ ⚠️ ИММУНИТЕТ ПОСЛЕ СПАВНА — ТОЛЬКО НА СУШЕ.
     Пять секунд задумывались как защита от нелепой смерти в момент появления:
     персонаж падает на плот, физика подбрасывает, мир ещё грузится. К плаванию
     это отношения не имеет, а на воде превращалось в бесплатные секунды —
     упал сразу после респавна и плыви. Океан отравлен: щадящих секунд в нём
     нет ни одной. ]]
local SPAWN_IMMUNITY = 5     -- сек неуязвимости после спавна, НА СУШЕ

--[[ ⚠️ БЕЗ ФОРЫ: УРОН С ПЕРВОГО ЖЕ ТИКА В ВОДЕ.
     Было две секунды «на подумать» — вместе с иммунитетом спавна и десятью
     секундами до нуля здоровья это давало около двадцати секунд свободного
     плавания, и вода перестала быть преградой. Плавать в этом океане можно
     только в маске (или дайвером) — а с ними урон не считается вовсе, ветка
     выше отсекает их раньше. ]]
local WATER_GRACE = 0        -- сек в воде до начала урона
local MAX_VIGNETTE_TIME = 10 -- seconds in water for max vignette intensity
local RADIATION_HIT_THRESHOLD = 3
local RADIATION_DURATION = 60

local vignetteEvent = rs:FindFirstChild("WaterVignette")
if not vignetteEvent then
	vignetteEvent = Instance.new("RemoteEvent")
	vignetteEvent.Name = "WaterVignette"
	vignetteEvent.Parent = rs
end

-- Create the RadiationUpdate RemoteEvent here so it definitely exists
local radiationEvent = rs:FindFirstChild("RadiationUpdate")
if not radiationEvent then
	radiationEvent = Instance.new("RemoteEvent")
	radiationEvent.Name = "RadiationUpdate"
	radiationEvent.Parent = rs
end

--[[ ⚠️ ПРЕДУПРЕЖДЕНИЕ О ВОДЕ — ОТДЕЛЬНЫЙ КАНАЛ, А НЕ ВИНЬЕТКА.
     Виньетка шлётся только когда МЕНЯЕТСЯ интенсивность, а в первую секунду
     заплыва она равна нулю — то есть момент входа по ней не поймать. Плашке
     «ОПАСНОСТЬ! Вода радиоактивна!» (RadiationUI на клиенте) нужен именно
     момент входа, поэтому у неё свой ремоут. ]]
local hazardEvent = rs:FindFirstChild("HazardWarning")
if not hazardEvent then
	hazardEvent = Instance.new("RemoteEvent")
	hazardEvent.Name = "HazardWarning"
	hazardEvent.Parent = rs
end

-- Чтобы прыжки в воду и обратно не превращались в мигание плашки.
local WARN_COOLDOWN = 12
local lastWarnAt = {}   -- [player] = tick() последнего предупреждения

local spawnTimes = {}  -- player -> time they spawned/respawned
local waterTimes = {}  -- humanoid -> time they entered water
local waterHitCounts = {} -- player -> number of ocean damage ticks
local radiationData = {} -- player -> { active, endTime }
local lastVignette = {}  -- player -> last intensity sent (fire only on change, not every second)

-- ─── Apply radiation sickness directly ───
local function applyRadiation(player)
	if radiationData[player] and radiationData[player].active then
		-- Already sick — reset timer
		radiationData[player].endTime = tick() + RADIATION_DURATION
		radiationEvent:FireClient(player, true, RADIATION_DURATION, RADIATION_DURATION)
		return
	end

	radiationData[player] = {
		active = true,
		endTime = tick() + RADIATION_DURATION,
	}

	player:SetAttribute("RadiationSick", true)
	radiationEvent:FireClient(player, true, RADIATION_DURATION, RADIATION_DURATION)

	-- Timer loop
	task.spawn(function()
		while radiationData[player] and radiationData[player].active do
			task.wait(1)
			if not player.Parent then break end

			-- ⚠️ ПЕРЕПРОВЕРКА ПОСЛЕ ОЖИДАНИЯ.
			-- За эту секунду игрок мог умереть, и clearRadiation обнулил бы
			-- запись — обращение к .endTime падало с «attempt to index nil».
			-- Условие цикла проверяется ДО wait и от этого не спасает.
			local data = radiationData[player]
			if not data or not data.active then break end

			local remaining = data.endTime - tick()
			if remaining <= 0 then
				data.active = false
				player:SetAttribute("RadiationSick", false)
				radiationEvent:FireClient(player, false, 0, RADIATION_DURATION)
				break
			end

			radiationEvent:FireClient(player, true, remaining, RADIATION_DURATION)

			-- Extra hunger drain while sick
			if _G.DrainHunger then
				_G.DrainHunger(player, 1)
			end
		end
	end)
end

-- СМЕРТЬ ЛЕЧИТ ЛУЧЕВУЮ БОЛЕЗНЬ.
--
-- Радиация — состояние ПЕРСОНАЖА, а не аккаунта: игрок нахватался её в воде,
-- умер и возродился с новым телом. Раньше таймер продолжал тикать через смерть,
-- а вместе с ним висел зелёный экран и шёл лишний расход голода — снять это
-- было нечем, оставалось только ждать целую минуту.
--
-- Гасим и таймер, и атрибут, и картинку у клиента: цикл в applyRadiation
-- проверяет radiationData[player].active на каждом шаге и завершится сам.
local function clearRadiation(player)
	local data = radiationData[player]
	if data then data.active = false end
	radiationData[player] = nil
	-- waterTimes ключуется ГУМАНОИДОМ, а не игроком: старый вместе с телом
	-- уже уничтожен, запись отвалится сама по слабой ссылке на инстанс.
	player:SetAttribute("RadiationSick", false)
	radiationEvent:FireClient(player, false, 0, RADIATION_DURATION)
	-- Виньетку «в воде» тоже сбрасываем: без этого экран мог остаться
	-- подкрашенным до следующего входа в воду.
	lastVignette[player] = 0
	vignetteEvent:FireClient(player, 0)
end

Players.PlayerAdded:Connect(function(player)
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
		waterHitCounts[player] = 0
		clearRadiation(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	spawnTimes[player] = nil
	waterHitCounts[player] = nil
	radiationData[player] = nil
	lastWarnAt[player] = nil
end)

for _, player in Players:GetPlayers() do
	spawnTimes[player] = tick()
	player.CharacterAdded:Connect(function()
		spawnTimes[player] = tick()
		waterHitCounts[player] = 0
		clearRadiation(player)
	end)
end

-- ═══ КАСАНИЕ ВОДЫ, А НЕ «ПОД НОГАМИ ПУСТО» ═══
--
-- Раньше здесь был один луч вниз от HumanoidRootPart: не попал ни во что или
-- попал в Terrain — значит «над водой», получай урон. На плоту это давало
-- ложные срабатывания: доски настила лежат с ЩЕЛЯМИ, луч проходил между ними и
-- игрок травился, стоя посреди сухого плота.
--
-- Теперь спрашиваем то, что нужно на самом деле: КАСАЕТСЯ ЛИ ИГРОК ВОДЫ.
--   1) Humanoid стоит на любом полу → он на чём-то твёрдом, вода исключена.
--      Это само по себе закрывает случай со щелями: капсула персонажа шире
--      щели, и опора у него есть, даже когда луч уходит в пустоту.
--   2) Состояние Swimming → Roblox сам определил, что персонаж в воде.
--   3) Иначе проверяем материал вокселя террейна в точке НОГ. Воксельный тест
--      не зависит от геометрии над водой и не путает щели с океаном.

local VOXEL = 4 -- размер вокселя террейна (как в DiverAir)

local function isPointInWater(pos)
	local region = Region3.new(
		pos - Vector3.new(2, 2, 2),
		pos + Vector3.new(2, 2, 2)
	):ExpandToGrid(VOXEL)
	local ok, materials, occupancies = pcall(function()
		return workspace.Terrain:ReadVoxels(region, VOXEL)
	end)
	if not ok or not materials then return false end
	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = (occupancies[1] and occupancies[1][1] and occupancies[1][1][1]) or 0
	return material == Enum.Material.Water and occupancy > 0.5
end

local function isInWater(humanoid, rootPart)
	if not humanoid or not rootPart then return false end

	-- 1) Есть опора под ногами — не в воде.
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		-- Единственное исключение: полом оказалась сама вода (мелководье).
		return humanoid.FloorMaterial == Enum.Material.Water
	end

	-- 2) Персонаж плывёт.
	local ok, state = pcall(function() return humanoid:GetState() end)
	if ok and state == Enum.HumanoidStateType.Swimming then return true end

	-- 3) В точке ног действительно вода.
	local feet = rootPart.Position - Vector3.new(0, rootPart.Size.Y * 0.5 + 1, 0)
	return isPointInWater(feet)
end

local function damageHumanoid(humanoid, rootPart, player)
	if not humanoid or humanoid.Health <= 0 then return end
	if not rootPart then return end

	-- ⚠️ СПЯЩИЙ В КРОВАТИ НЕ ТОНЕТ.
	-- У лежащего игрока PlatformStand = true: опоры под ногами нет, FloorMaterial
	-- становится Air, а «точка ног» в проверке ниже отсчитывается ВНИЗ от корня —
	-- у лежащего это уровень палубы, то есть вплотную к воде. В итоге все три
	-- признака дружно решали, что человек в океане, и травили его прямо в постели.
	-- Флаг ставит BedCrafting на время сна, его же читает SleepPose на клиенте.
	local char = rootPart.Parent
	if char and char:GetAttribute("Sleeping") == true then
		waterTimes[humanoid] = nil
		return
	end

	--[[ ⚠️ ЗАЩИЩАЕТ ТОЛЬКО МАСКА — КЛАСС ДАЙВЕРА БОЛЬШЕ НЕТ.
	     Раньше выбранный класс давал полный иммунитет к отраве, и игрок без
	     маски плавал сколько угодно. Океан отравлен для всех одинаково: маска —
	     единственный пропуск под воду, и это же правило теперь в DiverAir,
	     где убрана выдача воздуха за класс.
	     ⚠️ Заряд маски проверяет сама DivingMaskSystem: кончился — _G.HasDivingMask
	     вернёт false, и урон пойдёт немедленно, без всякого запаса. ]]
	local maskOn = (player and _G.HasDivingMask ~= nil) and _G.HasDivingMask(player) or false
	if player and maskOn then
		waterTimes[humanoid] = nil
		return
	end

	local inWater = isInWater(humanoid, rootPart)

	-- иммунитет спавна действует только вне воды: см. оговорку у SPAWN_IMMUNITY
	if not inWater and player and spawnTimes[player] then
		if tick() - spawnTimes[player] < SPAWN_IMMUNITY then
			return
		end
	end

	if inWater then
		if not waterTimes[humanoid] then
			waterTimes[humanoid] = tick()
			--[[ Вошёл в воду. Предупреждаем ровно здесь, а не в начале функции:
			     выше уже отсеяны маска и сон, то есть те случаи, когда урона нет.
			     Предупреждать о том, что не вредит, — обманывать игрока. ]]
			if player and (tick() - (lastWarnAt[player] or 0)) >= WARN_COOLDOWN then
				lastWarnAt[player] = tick()
				hazardEvent:FireClient(player, "radiation")
			end
		end
		if tick() - waterTimes[humanoid] >= WATER_GRACE then
			local damage = humanoid.MaxHealth * DAMAGE_PERCENT
			humanoid:TakeDamage(damage)

			if player then
				waterHitCounts[player] = (waterHitCounts[player] or 0) + 1
				if waterHitCounts[player] >= RADIATION_HIT_THRESHOLD then
					waterHitCounts[player] = 0
					applyRadiation(player)
				end
			end
		end
	else
		waterTimes[humanoid] = nil
	end
end

-- СЕЙВ: остаток отравления переживает выход (иначе «выйти-зайти» лечило)
_G.GetRadiationLeft = function(player)
	local d = radiationData[player]
	if d and d.active then return math.max(0, d.endTime - tick()) end
	return 0
end
_G.SetRadiationLeft = function(player, seconds)
	seconds = tonumber(seconds) or 0
	if seconds <= 0 then return end
	applyRadiation(player)
	if radiationData[player] then
		radiationData[player].endTime = tick() + seconds
		radiationEvent:FireClient(player, true, seconds, RADIATION_DURATION)
	end
end

while true do
	task.wait(CHECK_INTERVAL)

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildWhichIsA("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			damageHumanoid(hum, hrp, player)

			local intensity = 0
			if hum and waterTimes[hum] then
				--[[ ⚠️ ЭФФЕКТ ВИДЕН С ПЕРВОГО ТИКА, А НЕ ЧЕРЕЗ ДЕСЯТЬ СЕКУНД.
				     Интенсивность росла с нуля: первые секунды в отраве экран выглядел
				     обычным, хотя здоровье уже сыпалось — урон приходил «из ниоткуда».
				     Нижний порог 0.45 зажигает кромки сразу, дальше они наливаются до
				     максимума за те же десять секунд. ]]
				local timeInWater = tick() - waterTimes[hum]
				intensity = math.clamp(0.45 + (timeInWater / MAX_VIGNETTE_TIME) * 0.55, 0, 1)
			end
			-- only fire when the value actually changed — a constant stream of identical zeros
			-- floods the remote queue if the client listener isn't ready ("invocation queue exhausted")
			if math.abs(intensity - (lastVignette[player] or -1)) > 0.005 then
				lastVignette[player] = intensity
				vignetteEvent:FireClient(player, intensity)
			end
		end
	end

	for _, obj in workspace:GetChildren() do
		-- WaterImmune models (e.g. swimming pirates that live in the sea) take no ocean damage
		if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) and not obj:GetAttribute("WaterImmune") then
			local hum = obj:FindFirstChildWhichIsA("Humanoid")
			if hum then
				local hrp = obj:FindFirstChild("HumanoidRootPart")
				damageHumanoid(hum, hrp, nil)
			end
		end
	end
end