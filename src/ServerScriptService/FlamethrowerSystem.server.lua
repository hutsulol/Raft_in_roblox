--[[
	ОГНЕМЁТ — сервер.

	Держит топливо, решает, можно ли жечь, считает попадания струи и ведёт
	горящих врагов. Всё, что видно глазом (сама струя, свет, звук), рисует
	клиент по атрибуту Firing на инструменте — так струю видят все игроки, а
	не только стрелок.

	ПРАВИЛА СТРЕЛЬБЫ (заданы заказчиком, менять только вместе с ним):
	  • полный бак = 25 секунд непрерывной струи;
	  • минимальная порция — 0.5 с: отпустил раньше, всё равно дожжёт;
	  • между порциями пауза 1 с.

	⚠️ В ВОДЕ НЕ ГОРИТ. Проверяем воксель воды под точкой, а не абсолютный
	уровень моря: плот дрейфует, а острова и трюмы стоят на своих высотах, и
	один общий Y здесь врал бы.

	⚠️ БОЧКИ НА ТЕРРАСЕ ОГНЁМ НЕ ВЗРЫВАЮТСЯ. Огнемёт поджигает только кусты —
	для этого TerraceIsland отдаёт отдельный вход (_G.TerraceIgniteAt), а не
	общий обработчик попадания, который умеет и подрывать.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("FlamethrowerDefs"))
local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG = "[Огнемёт]"

local fireEvent = ReplicatedStorage:FindFirstChild("FlamethrowerFire")
if not fireEvent then
	fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = "FlamethrowerFire"
	fireEvent.Parent = ReplicatedStorage
end

-- ═══════════ мелкие помощники ═══════════

-- ⚠️ ОРУЖИЙ НА ЭТОМ ДВИЖКЕ ДВА: ОГНЕМЁТ И РУКА КРАКЕНА.
-- Отличаются они только числами и цветом (Defs.VARIANTS), поэтому здесь всюду
-- спрашиваем «какой это вариант», а не «это огнемёт?». Вторая копия системы
-- разошлась бы с первой при первой же правке конуса или поджига.
local function variantOf(inst)
	return Defs.variant(inst)
end

local function isFlamethrower(inst)
	return variantOf(inst) ~= nil
end

local function heldFlamethrower(player)
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if isFlamethrower(t) then return t end
	end
	return nil
end

local function anyFlamethrower(player)
	local held = heldFlamethrower(player)
	if held then return held end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if isFlamethrower(t) then return t end
		end
	end
	return nil
end

local function muzzleOf(tool)
	local v = variantOf(tool)
	local m = tool:FindFirstChild(v and v.muzzle or Defs.MUZZLE, true)
	if m and m:IsA("BasePart") then return m end
	local h = tool:FindFirstChild("Handle")
	if h and h:IsA("BasePart") then return h end
	return tool:FindFirstChildWhichIsA("BasePart", true)
end

-- ⚠️ СОБИРАЕМ ИНСТРУМЕНТ ЗАНОВО ПРИ КАЖДОЙ ВЫДАЧЕ.
-- Roblox приваривает к руке ТОЛЬКО Handle, всё остальное в Tool должно держаться
-- своими сварками — а импортированная модель приходит с заякоренными деталями,
-- и якорь сильнее сварки. Из-за этого ствол оставался висеть там, где лежал
-- шаблон, и струя била из пустого места посреди моря.
--
-- Сварку перед перестановкой снимаем — WeldConstraint держит жёстко и двигал бы
-- вместе с деталью всю сборку.
-- ⚠️ ЭТАЛОН СМЕЩЕНИЙ БЕРЁМ ИЗ ШАБЛОНА, А НЕ ИЗ ЖИВОГО ИНСТРУМЕНТА.
-- Первый заход запоминал смещение «один раз, пока модель целая» — и это было
-- ошибкой: у уже собранного огнемёта ствол успел уехать (он был заякорен и
-- остался лежать на месте шаблона), а я запомнил и приварил именно эту кривизну.
-- Шаблон в ReplicatedStorage/Workspace всегда целый, поэтому мерка честная.
local function templateOffset(toolName, partName)
	for _, where in ipairs({ ReplicatedStorage, Workspace, game:GetService("StarterPack") }) do
		-- в хранилище ищем по имени, а не по месту: шаблоны разложены по папкам (см. AssetFind)
		local tpl = (where == ReplicatedStorage and AssetFind.find(toolName)) or where:FindFirstChild(toolName)
		if tpl and tpl:IsA("Tool") then
			local h = tpl:FindFirstChild("Handle")
			local p = tpl:FindFirstChild(partName, true)
			if h and p and h:IsA("BasePart") and p:IsA("BasePart") then
				return h.CFrame:Inverse() * p.CFrame
			end
		end
	end
	return nil
end

local SANE_REACH = 25   -- студов: дальше этого деталь оружия от рукояти не бывает

local function weldTool(tool)
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return end
	handle.Anchored = false
	handle.CanCollide = false

	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			local off = templateOffset(tool.Name, part.Name) or part:GetAttribute("GripOffset")
			if typeof(off) ~= "CFrame" then
				off = handle.CFrame:Inverse() * part.CFrame
			end

			-- ⚠️ УЖЕ СТОИТ ПРАВИЛЬНО — НЕ ТРОГАЕМ ВООБЩЕ.
			-- Инструмент в руках приварен к персонажу, и запись CFrame детали
			-- тянет за собой ВСЮ сборку: игрока телепортировало на пару метров
			-- назад ровно в момент взятия огнемёта. Пересобираем только то, что
			-- реально уехало.
			local now = handle.CFrame:Inverse() * part.CFrame
			local sameSpot = (now.Position - off.Position).Magnitude < 0.05
			if sameSpot and part:FindFirstChild("GripWeld") then
				continue
			end
			-- ни шаблона, ни вменяемого запомненного смещения: деталь уехала, и
			-- восстановить её не по чему — сажаем на рукоять, чтобы огонь шёл
			-- хотя бы из оружия, а не из точки посреди моря
			if off.Position.Magnitude > SANE_REACH then
				warn(("%s %s: смещение от рукояти %.0f студов — деталь была оторвана, сажаю на рукоять")
					:format(LOG, part.Name, off.Position.Magnitude))
				off = CFrame.new()
			end
			part:SetAttribute("GripOffset", off)

			-- ⚠️ РВЁМ ВСЕ СВЯЗИ ДЕТАЛИ, А НЕ ТОЛЬКО СВОЮ СВАРКУ.
			-- В импортированной модели есть собственные сварки. Пока хоть одна
			-- жива, деталь остаётся в сборке персонажа — и её перестановка
			-- двигает игрока. Ищем по всему инструменту любой сустав, который
			-- ссылается на эту деталь, и сносим.
			-- ⚠️ WeldConstraint — НЕ JointInstance, это отдельный класс. Проверять
			-- надо оба, иначе собственная сварка GripWeld переживёт снос и
			-- деталь останется в сборке.
			for _, j in ipairs(tool:GetDescendants()) do
				if (j:IsA("JointInstance") or j:IsA("WeldConstraint"))
					and (j.Part0 == part or j.Part1 == part) then
					j:Destroy()
				end
			end

			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part.CFrame = handle.CFrame * off

			local weld = Instance.new("WeldConstraint")
			weld.Name = "GripWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part

			-- по стволу отчитываемся: именно из него идёт струя, и если он снова
			-- окажется не там, это будет видно в логе сразу, а не по «огня нет»
			local v = variantOf(tool)
			if v and part.Name == v.muzzle then
				print(("%s %s: дуло собрано, %.2f студа от рукояти (%s)"):format(
					LOG, tool.Name, off.Position.Magnitude,
					templateOffset(tool.Name, part.Name) and "мерка из шаблона" or "мерка своя"))
			end
		end
	end
end

local function initTool(tool)
	if not isFlamethrower(tool) then return end
	weldTool(tool)
	if not tool:GetAttribute("GripWatched") then
		tool:SetAttribute("GripWatched", true)
		-- при каждом взятии в руки пересобираем: деталь могла отвязаться, пока
		-- инструмент лежал в рюкзаке или переезжал между персонажами
		tool.Equipped:Connect(function()
			task.defer(weldTool, tool)
		end)
	end
	-- ⚠️ ФЛАГ СТРЕЛЬБЫ ГАСИМ ПРИ КАЖДОЙ ВЫДАЧЕ.
	-- Смерть с зажатой кнопкой оставляла Firing = true прямо на инструменте, а
	-- KeepToolsOnDeath уносил его копию в StarterGear вместе с этим флагом. На
	-- respawn клиент видел «стреляем» и рисовал струю вечно — при том что сессии
	-- на сервере нет, а значит топливо не тратится.
	tool:SetAttribute("Firing", false)
	local v = variantOf(tool)
	tool:SetAttribute(Defs.ATTR_CAP, v.capacity)
	local fuel = tool:GetAttribute(Defs.ATTR_FUEL)
	if type(fuel) ~= "number" then
		-- ⚠️ САМОЗАРЯДНОЕ ОРУЖИЕ ВЫДАЁТСЯ ПОЛНЫМ.
		-- Огнемёт без топлива честен: его заправляют. Рука кракена копит заряд
		-- сама, и выданная пустой она просто молчала бы полторы минуты — игрок
		-- решил бы, что она сломана.
		tool:SetAttribute(Defs.ATTR_FUEL, v.refuelable and 0 or v.capacity)
	elseif fuel > v.capacity then
		tool:SetAttribute(Defs.ATTR_FUEL, v.capacity)
	end
end

-- ВОДА. Читаем воксель терраина в точке: и море, и залитый трюм считаются
-- одинаково, без единого «уровня моря» на весь мир.
local function inWater(pos)
	local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials = pcall(function()
		return Workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok or not materials then return false end
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] == Enum.Material.Water then return true end
			end
		end
	end
	return false
end

-- ═══════════ кто враг ═══════════

local function enemyModelOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then break end
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not model then return nil end
	if Players:GetPlayerFromCharacter(model) then return nil end
	-- враги острова фермеров (мутант, учёные, конвой) названы не по префиксам —
	-- их метит атрибут Hostile (FarmersIsland/NPCSpawner)
	if model:GetAttribute("Hostile") == true or model:GetAttribute("Flammable") == true then return model end
	if Defs.FRIENDLY_NAMES[model.Name] then return nil end
	for name in pairs(Defs.FRIENDLY_NAMES) do
		if model.Name:find(name, 1, true) then return nil end
	end
	for _, prefix in ipairs(Defs.ENEMY_PREFIXES) do
		if model.Name:sub(1, #prefix) == prefix then return model end
	end
	return nil
end

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
end

-- ═══════════ горящие враги ═══════════

local burning = {}   -- [model] = { untilT, dpsAt, shook, prevClip, fx }

-- Клип реакции. У гарнизона острова и живности это атрибуты Clip/ClipOnce
-- (позу считает каждый клиент), у экипажа катеров — свой проигрыватель, ему
-- отдаём тот же клип через хук. Абордажники крутят опубликованные анимации и
-- этих клипов не знают — им достаётся только урон и огонь.
-- ⚠️ ЛУП И РАЗОВЫЙ КЛИП — РАЗНЫЕ КАНАЛЫ, ПУТАТЬ НЕЛЬЗЯ.
-- Первая версия слала ВСЁ через ClipOnce, включая зацикленный Fire_Burn. А
-- разовый канал у клиента заканчивается только когда клип доиграл — у лупа
-- этого не случается никогда, и пират навсегда застывал с задранными руками,
-- даже потушившись. Лупы шлём обычным Clip: его перебьёт своей же анимацией
-- ИИ, как только оглушение снимется.
local function playClip(model, clipName, loopLike)
	if loopLike then
		model:SetAttribute("Clip", clipName)
		model:SetAttribute("ClipT", Workspace:GetServerTimeNow())
	else
		model:SetAttribute("ClipOnce", clipName)
		model:SetAttribute("ClipOnceT", Workspace:GetServerTimeNow())
	end
	if _G.PirateBoatReact then
		pcall(_G.PirateBoatReact, model, clipName, loopLike)
	end
end

-- ⚠️ ЦВЕТ ГОРЕНИЯ БЕРЁТСЯ ОТ ТОГО, ЧЕМ ПОДОЖГЛИ.
-- Рука кракена бьёт фиолетовым, и человек, которого она подожгла, должен гореть
-- тем же цветом — иначе оранжевое пламя на жертве выдаёт, что эффект нарисован
-- отдельно от оружия. Вариант передаётся по цепочке от струи к поджигу.
local function fireFxOn(model, v)
	v = v or Defs.VARIANTS[Defs.TOOL_NAME]
	local root = rootOf(model)
	if not root then return nil end
	local fx = Instance.new("Folder")
	fx.Name = "OnFire"
	fx.Parent = model

	-- ⚠️ ЭМИТТЕРЫ ВЕШАЕМ НА ДЕТАЛЬ, А НЕ НА ATTACHMENT: у Attachment огонь
	-- выходит из одной точки, а горит человек целиком.
	-- Слоёв три (языки, искры, дым) по той же причине, что и у струи: один
	-- спрайт на горящем человеке читается как наклейка, а не как пламя.
	local emitters = {}
	-- у чернил на жертве свой спрайт: не язык пламени, а стекающий потёк
	local textures = { Defs.clingFor(v), Defs.bodyTextures(v)[2] }
	for i = 1, 2 do
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "Flame" .. i
		flame.Texture = textures[i]
		flame.Rate = 22
		flame.Lifetime = NumberRange.new(0.35, 0.6)
		flame.Speed = NumberRange.new(1.5 + i, 3.5 + i)
		flame.SpreadAngle = Vector2.new(25, 25)
		flame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.4 + i * 0.3),
			NumberSequenceKeypoint.new(0.5, 2.2 + i * 0.4),
			NumberSequenceKeypoint.new(1, 0.4),
		})
		flame.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		flame.Color = Defs.tintFor(v, v.hot, v.cool)
		-- ⚠️ У ЧЕРНИЛ СВЕТИМОСТЬ НИЗКАЯ.
		-- Огонь светится сам, чернила — нет: на единице запечённый в спрайт
		-- градиент выгорал добела и превращался в сиреневый дым.
		flame.LightEmission = v.glow or 0.8
		flame.LightInfluence = 0
		flame.RotSpeed = NumberRange.new(-50, 50)
		flame.Acceleration = Vector3.new(0, 12, 0)
		flame.Parent = root
		table.insert(emitters, flame)
	end

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FlameSparks"
	sparks.Texture = Defs.emberFor(v)
	sparks.Rate = 14
	sparks.Lifetime = NumberRange.new(0.6, 1.1)
	sparks.Speed = NumberRange.new(3, 7)
	sparks.SpreadAngle = Vector2.new(45, 45)
	sparks.Size = NumberSequence.new(0.5, 0.05)
	sparks.Transparency = NumberSequence.new(0.2, 1)
	sparks.Color = Defs.tintFor(v, v.hot, v.light)
	sparks.LightEmission = v.glow or 1
	sparks.Acceleration = Vector3.new(0, 9, 0)
	sparks.Parent = root
	table.insert(emitters, sparks)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "FlameSmoke"
	smoke.Texture = Defs.smokeFor(v)
	smoke.Rate = 8
	smoke.Lifetime = NumberRange.new(1, 1.8)
	smoke.Speed = NumberRange.new(2, 4)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Size = NumberSequence.new(1.5, 6)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- дым у огня серый, у чернил — своя текстура со своим цветом
	smoke.Color = Defs.tintFor(v, Color3.fromRGB(80, 70, 64), Color3.fromRGB(40, 36, 34))
	smoke.LightEmission = 0
	smoke.RotSpeed = NumberRange.new(-25, 25)
	smoke.Acceleration = Vector3.new(0, 14, 0)
	smoke.Parent = root
	table.insert(emitters, smoke)

	local light = Instance.new("PointLight")
	light.Color = v.light
	light.Brightness = 4
	light.Range = 16
	light.Parent = root

	-- горит человек или с него течёт — звук разный, как и картинка
	local sc = v.sndBurn or { id = "rbxasset://sounds/snap.mp3", speed = 0.35, volume = 0.5 }
	local snd = Instance.new("Sound")
	snd.SoundId = sc.id
	snd.PlaybackSpeed = sc.speed
	snd.Volume = sc.volume
	snd.Looped = true
	snd.RollOffMaxDistance = 70
	snd.Parent = root
	snd:Play()

	return { emitters = emitters, light = light, sound = snd, folder = fx, host = root }
end

local function stopBurn(model)
	local st = burning[model]
	if not st then return end
	burning[model] = nil
	-- вернуть шаг и снять оглушение: чужие ИИ ждут именно снятия флага
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if hum and st.walkSpeed then hum.WalkSpeed = st.walkSpeed end
	if st.fx then
		for _, p in ipairs(st.fx.emitters or {}) do
			p.Enabled = false
			p:Destroy()
		end
		if st.fx.light then st.fx.light:Destroy() end
		if st.fx.sound then st.fx.sound:Destroy() end
		if st.fx.folder then st.fx.folder:Destroy() end
	end
	model:SetAttribute("OnFire", nil)
end

local function ignite(model, attacker, v)
	v = v or Defs.VARIANTS[Defs.TOOL_NAME]
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local root = rootOf(model)
	if not root or inWater(root.Position) then return end   -- в воде не поджечь

	local st = burning[model]
	if st then
		-- уже горит: просто продлеваем, второй костёр не разводим
		st.untilT = os.clock() + Defs.IGNITE_SEC
		return
	end

	burning[model] = {
		burnDps = v.burnDps,
		startT = os.clock(),
		untilT = os.clock() + Defs.IGNITE_SEC,
		nextDot = os.clock() + 1,
		nextClip = os.clock() + 0.9,        -- после шока пойдёт чередование
		nextWater = 0,
		attacker = attacker,
		walkSpeed = hum.WalkSpeed,          -- вернём, когда потухнет
		fx = fireFxOn(model, v),
		-- ⚠️ ЗВЕРЬ БЕЗ НОГ (чайка): её водит свой ИИ по CFrame, MoveTo и клипы
		-- пиратов ей не годятся. Ей — только огонь и урон, паникует она сама
		-- по флагу OnFire (SeagullAI).
		selfPanic = model:GetAttribute("BurnSelf") == true,
	}
	if burning[model].selfPanic then
		model:SetAttribute("OnFire", true)
		return
	end
	-- ⚠️ ФЛАГ ЧИТАЮТ ЧУЖИЕ ИИ. Пока он стоит, островной ИИ, экипаж катера и
	-- абордажники пропускают свой ход: горящий оглушён и не атакует.
	model:SetAttribute("OnFire", true)
	hum.WalkSpeed = math.max(hum.WalkSpeed, 20)   -- в панике бегут быстрее
	playClip(model, Defs.SHOCK_CLIPS[math.random(#Defs.SHOCK_CLIPS)])
end

-- ВОДА РЯДОМ.
-- ⚠️ ИЩЕМ ЛУЧОМ СВЕРХУ ВНИЗ, А НЕ ТОЧКОЙ НА СВОЕЙ ВЫСОТЕ.
-- Первый заход щупал воксель в двух студах под ногами — и у самого берега воды
-- «не находил»: океан лежит на десяток студов ниже кромки острова, пират стоял
-- в трёх шагах от моря и не бежал в него. Луч видит поверхность на любой высоте.
local WATER_DIRS  = 8
local WATER_STEPS = { 16, 34, 55 }

local waterRay = RaycastParams.new()
waterRay.IgnoreWater = false          -- ради этого всё и затевалось
waterRay.FilterType = Enum.RaycastFilterType.Exclude
waterRay.FilterDescendantsInstances = {}

-- ⚠️ ВОДА ПОД ПЛОТОМ НЕ СЧИТАЕТСЯ.
-- Горящий на палубе находил ближайшую воду прямо под собой — в щели настила —
-- и лез туда: заплывал под плот, упирался в него телом и останавливал его.
-- Точки внутри габаритов плота отбрасываем: пусть бежит за борт.
local function underRaft(p)
	local raft = Workspace:FindFirstChild("Raft")
	if not raft then return false end
	local ok, cf, size = pcall(function()
		local c, s = raft:GetBoundingBox()
		return c, s
	end)
	if not ok or not cf then return false end
	local lp = cf:PointToObjectSpace(p)
	return math.abs(lp.X) <= size.X * 0.5 + 2 and math.abs(lp.Z) <= size.Z * 0.5 + 2
end

local function waterNear(pos)
	local best, bestDist = nil, math.huge
	for i = 0, WATER_DIRS - 1 do
		local a = (i / WATER_DIRS) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		for _, dist in ipairs(WATER_STEPS) do
			local from = pos + dir * dist + Vector3.new(0, 8, 0)
			local hit = Workspace:Raycast(from, Vector3.new(0, -70, 0), waterRay)
			if hit and hit.Material == Enum.Material.Water and not underRaft(hit.Position) then
				if dist < bestDist then best, bestDist = hit.Position, dist end
				break   -- в этом направлении вода найдена, дальше не смотрим
			end
		end
	end
	return best
end

-- Ведём горящих: урон, паника, сбивание пламени, тушение в воде.
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for model, st in pairs(burning) do
			local hum = model:FindFirstChildWhichIsA("Humanoid")
			local root = rootOf(model)
			if not (model.Parent and hum and root) or hum.Health <= 0 then
				stopBurn(model)
			elseif inWater(root.Position) then
				stopBurn(model)   -- нырнул — потушился, это законный способ выжить
			elseif now >= st.untilT then
				stopBurn(model)
			else
				if now >= st.nextDot then
					st.nextDot = now + 1
					-- урон догорания у каждого оружия свой: рука кракена жжёт вдвое
					if st.attacker and st.attacker.Parent then model:SetAttribute("LastHitBy", st.attacker.UserId) end
					hum:TakeDamage(st.burnDps or Defs.BURN_DPS)
					-- сгорел заживо: с туши упадёт уже жареное (AnimalLife)
					if hum.Health <= 0 then model:SetAttribute("KilledByFire", true) end
				end
				if st.selfPanic then continue end   -- паника и бег — не наши (см. ignite)

				-- ⚠️ КЛИПЫ ЧЕРЕДУЮТСЯ, А НЕ КРУТЯТ ОДИН ЛУП.
				-- Первая версия всё горение гоняла Fire_Burn и один раз в конце
				-- давала Fire_Shake — со стороны это читалось как одна и та же
				-- дёрганина. Теперь мечется и сбивает пламя вперемешку, а под
				-- конец сбивает чаще: огонь уже слабый, и он верит, что собьёт.
				if now >= (st.nextClip or 0) then
					local left = (st.untilT - now) / Defs.IGNITE_SEC
					local shakeChance = (left <= 1 - Defs.SHAKE_AT) and 0.75 or 0.35
					if math.random() < shakeChance then
						playClip(model, Defs.SHAKE_CLIP)
						st.nextClip = now + 1.5          -- длина Fire_Shake
					else
						playClip(model, Defs.BURN_CLIP, true)
						st.nextClip = now + 0.7 + math.random() * 0.9
					end
				end

				-- ⚠️ ГОРЯЩИЙ ОБЯЗАН БЕГАТЬ САМ.
				-- Его собственный ИИ мы выключили флагом OnFire, значит ходить
				-- ему больше некому — первая версия двигала его ТОЛЬКО когда
				-- рядом нашлась вода, и посреди острова человек горел стоя.
				-- Нет воды — мечется вслепую короткими перебежками.
				-- ⚠️ НА КАТЕРЕ БЕЖАТЬ НЕКУДА — ТОЛЬКО ЗА БОРТ.
				-- Воды вокруг сколько угодно, но она внизу, и обычный поиск её
				-- находит там, куда пешком не дойти. Поэтому охранник катера
				-- через секунду паники прыгает сам, а дальше им занимается
				-- SwimmingPirate: плывёт к плоту и дерётся уже на палубе.
				if not st.jumped and now >= st.startT + 1.2 then
					st.jumped = true   -- пробуем один раз: не катерный — просто мимо
					if _G.PirateBoatOverboard and _G.PirateBoatOverboard(model) then
						playClip(model, Defs.SHAKE_CLIP)
						stopBurn(model)   -- в море огонь ему уже не нужен
						continue
					end
				end

				if now >= (st.nextWater or 0) then
					st.nextWater = now + 0.7
					st.water = waterNear(root.Position)
				end

				-- ⚠️ ЦЕЛЬ ВСЕГДА ВПЕРЕДИ И ОБНОВЛЯЕТСЯ КАЖДЫЙ ТИК.
				-- Раньше точка ставилась раз в секунду и близко — Humanoid успевал
				-- до неё дойти и вставал столбом до следующей. Теперь цель убегает
				-- вместе с ним, поэтому бег непрерывный; меняется только НАПРАВЛЕНИЕ,
				-- и то плавно, чтобы не дёргался на месте.
				local goal = st.water
				if not goal then
					if not st.dir or now >= (st.turnAt or 0) then
						st.turnAt = now + 0.6 + math.random() * 0.7
						local a = math.random() * math.pi * 2
						st.dir = Vector3.new(math.cos(a), 0, math.sin(a))
					end
					goal = root.Position + st.dir * 26
				end

				-- ⚠️ ПАНИКА НЕ УВОДИТ С ПОСТА.
				-- Горящий бежит к воде — и с острова убегал совсем: оставался жив
				-- где-то в море, а остров из-за него не засчитывался зачищенным
				-- («убил всех, а зачистки нет»). Держим его в круге вокруг своей
				-- точки: не дотянулся до воды — догорит на месте.
				local hx, hz = model:GetAttribute("HomeX"), model:GetAttribute("HomeZ")
				if hx and hz then
					local home = Vector3.new(hx, goal.Y, hz)
					local off = goal - home
					local limit = 60
					if off.Magnitude > limit then
						goal = home + off.Unit * limit
					end
				end
				hum:MoveTo(goal)
			end
		end
	end
end)

-- ═══════════ струя ═══════════

local sessions = {}   -- [player] = { tool, startT, minUntil, releaseAt, nextTick }
local cooldownUntil = {}

local function coneHits(origin, dir)
	local hits = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.MaxParts = 60

	-- Струя — это конус, но проверяем его дешёвым способом: берём шар вокруг
	-- середины и отсеиваем по углу. Точность тут не нужна, а рейкастов на
	-- каждый тик было бы вдвое больше.
	local center = origin + dir * (Defs.RANGE * 0.5)
	local parts = Workspace:GetPartBoundsInRadius(center, Defs.RANGE * 0.6, params)
	local cosLimit = math.cos(math.rad(Defs.CONE_DEG))
	for _, part in ipairs(parts) do
		local to = part.Position - origin
		local dist = to.Magnitude
		if dist > 1 and dist <= Defs.RANGE and to.Unit:Dot(dir) >= cosLimit then
			table.insert(hits, part)
		end
	end
	return hits
end

local function tickFlame(player, tool)
	local v = variantOf(tool) or Defs.VARIANTS[Defs.TOOL_NAME]
	local muzzle = muzzleOf(tool)
	if not muzzle then return end
	local origin = muzzle.Position
	local dir = muzzle.CFrame.LookVector
	-- ствол смотрит вдоль детали; если модель импортирована иначе, страхуемся
	-- направлением взгляда персонажа
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and dir:Dot(hrp.CFrame.LookVector) < 0.2 then
		dir = hrp.CFrame.LookVector
	end

	if inWater(origin) then return end   -- под водой струи нет

	local seen = {}
	for _, part in ipairs(coneHits(origin, dir)) do
		local model = enemyModelOf(part)
		if model and not seen[model] then
			seen[model] = true
			local hum = model:FindFirstChildWhichIsA("Humanoid")
			if hum and hum.Health > 0 then
				model:SetAttribute("LastHitBy", player.UserId)   -- кто бил последним (IslandQuestSystem)
				hum:TakeDamage(v.dps * Defs.TICK)
				if hum.Health <= 0 then model:SetAttribute("KilledByFire", true) end
				ignite(model, player, v)
			end
		end
	end

	-- Кусты вируса на террасе: поджигаем ТОЛЬКО их, бочки огнемётом не рвём.
	if _G.TerraceIgniteAt then
		local tip = origin + dir * (Defs.RANGE * 0.75)
		pcall(_G.TerraceIgniteAt, tip, 7, player)
	end
end

local function stopFire(player, reason)
	local s = sessions[player]
	if not s then return end
	sessions[player] = nil
	if s.tool and s.tool.Parent then
		s.tool:SetAttribute("Firing", false)
	end
	cooldownUntil[player] = os.clock() + Defs.COOLDOWN
	if reason == "empty" then
		fireEvent:FireClient(player, "empty")
	end
end

-- Причина отказа в лог, но не чаще раза в 2 секунды: иначе зажатая кнопка
-- зальёт Output, а понять, почему струи нет, всё равно нужно.
local lastWhy = {}
local function why(player, text)
	if (lastWhy[player] or 0) > os.clock() then return end
	lastWhy[player] = os.clock() + 2
	print(("%s %s: струи нет — %s"):format(LOG, player.Name, text))
end

local function startFire(player)
	if sessions[player] then return end
	if (cooldownUntil[player] or 0) > os.clock() then
		why(player, "откат ещё не вышел")
		return
	end

	local tool = heldFlamethrower(player)
	if not tool then
		why(player, "огнемёт не в руках")
		return
	end
	initTool(tool)
	if (tool:GetAttribute(Defs.ATTR_FUEL) or 0) <= 0 then
		why(player, "бак пуст")
		fireEvent:FireClient(player, "empty")
		return
	end

	local now = os.clock()
	sessions[player] = {
		tool = tool,
		startT = now,
		minUntil = now + Defs.MIN_BURST,   -- отпустит раньше — дожжёт до этого
		releaseAt = nil,
		nextTick = now,
	}
	tool:SetAttribute("Firing", true)
end

-- Сторож зависшего флага: инструмент, на котором Firing = true, но сессии нет
-- (умер, выронил, перезашёл), гасим сами — иначе струя живёт своей жизнью.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			if not sessions[player] then
				local tool = anyFlamethrower(player)
				if tool and tool:GetAttribute("Firing") then
					tool:SetAttribute("Firing", false)
				end
			end
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for player, s in pairs(sessions) do
		local tool = s.tool
		if not (tool and tool.Parent and heldFlamethrower(player) == tool) then
			stopFire(player)
		else
			-- топливо тратится всё время, пока идёт струя
			local v = variantOf(tool) or Defs.VARIANTS[Defs.TOOL_NAME]
			local fuel = (tool:GetAttribute(Defs.ATTR_FUEL) or 0) - v.burnRate * dt
			if fuel <= 0 then
				tool:SetAttribute(Defs.ATTR_FUEL, 0)
				stopFire(player, "empty")
			else
				tool:SetAttribute(Defs.ATTR_FUEL, fuel)
				if now >= s.nextTick then
					s.nextTick = now + Defs.TICK
					tickFlame(player, tool)
				end
				-- ⚠️ ОТПУСКАНИЕ УВАЖАЕТ МИНИМАЛЬНУЮ ПОРЦИЮ: кнопку бросили, а
				-- струя дожигает свои полсекунды. Иначе частым тыком можно было
				-- бы жечь непрерывно, обходя откат.
				if s.releaseAt and now >= s.minUntil then
					stopFire(player)
				end
			end
		end
	end
end)

-- ⚠️ САМОЗАРЯДКА ИДЁТ И В РЮКЗАКЕ, И ВО ВРЕМЯ СТРЕЛЬБЫ.
-- Рука кракена копит заряд сама: не оружие с патронами, а живая тварь. Считать
-- её «только пока в руках» значило бы наказывать за то, что игрок сменил
-- инструмент. Пока идёт струя, расход из Heartbeat всё равно больше прибавки
-- втрое — за секунду стрельбы уходит секунда, набегает треть.
task.spawn(function()
	while true do
		local dt = task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			for _, where in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
				if where then
					for _, tool in ipairs(where:GetChildren()) do
						local v = variantOf(tool)
						if v and v.regenRate > 0 then
							local have = tool:GetAttribute(Defs.ATTR_FUEL) or 0
							if have < v.capacity then
								tool:SetAttribute(Defs.ATTR_FUEL,
									math.min(v.capacity, have + v.regenRate * dt))
							end
						end
					end
				end
			end
		end
	end
end)

local refuel   -- определяется ниже, объявлен здесь ради единого обработчика

fireEvent.OnServerEvent:Connect(function(player, action)
	if action == "start" then
		startFire(player)
	elseif action == "stop" then
		local s = sessions[player]
		if s then
			s.releaseAt = os.clock()
			if os.clock() >= s.minUntil then stopFire(player) end
		end
	elseif action == "refuel" then
		refuel(player)
	end
end)

-- ═══════════ заправка ═══════════

-- Заправляем от бака на плоту и от канистры в руках: и то и другое — то же
-- топливо в миллилитрах, разница только в источнике.
function refuel(player)
	local tool = anyFlamethrower(player)
	if not tool then return end
	local v = variantOf(tool)
	-- ⚠️ РУКУ КРАКЕНА НЕ ЗАПРАВЛЯЮТ. Она копит заряд сама, и нефть в неё лить
	-- некуда: молча пропускаем, а не тратим топливо игрока впустую.
	if not v.refuelable then return end
	initTool(tool)
	local have = tool:GetAttribute(Defs.ATTR_FUEL) or 0
	local need = v.capacity - have
	if need <= 1 then
		fireEvent:FireClient(player, "full")
		return
	end

	-- сперва канистра игрока: она под рукой и её проще опустошить
	local canister = nil
	local char = player.Character
	for _, where in ipairs({ char, player:FindFirstChildOfClass("Backpack") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if OilCanister.isCanister(t) then canister = t break end
			end
		end
		if canister then break end
	end

	local taken = 0
	if canister then
		local inCan = canister:GetAttribute(OilCanister.ATTR_FILL) or 0
		taken = math.min(inCan, need)
		if taken > 0 then
			canister:SetAttribute(OilCanister.ATTR_FILL, inCan - taken)
		end
	end

	if taken < need then
		-- добираем из бака на плоту
		for _, name in ipairs(OilCanister.TANK_NAMES) do
			local tank = Workspace:FindFirstChild(name, true)
			if tank then
				local stored = tank:GetAttribute(OilCanister.TANK_ATTR) or 0
				local more = math.min(stored, need - taken)
				if more > 0 then
					tank:SetAttribute(OilCanister.TANK_ATTR, stored - more)
					taken = taken + more
				end
				break
			end
		end
	end

	if taken <= 0 then
		fireEvent:FireClient(player, "nofuel")
		return
	end
	tool:SetAttribute(Defs.ATTR_FUEL, have + taken)
	fireEvent:FireClient(player, "refueled", taken)
end

_G.RefuelFlamethrower = refuel

-- ⚠️ СВОЕЙ ПОДСКАЗКИ НА БАКЕ НЕТ.
-- Первый заход вешал на воронку второй промпт (R), и рядом с «Заливать» вырос
-- второй ярлык — две кнопки на одной бочке, игрок в них путался. Правильнее
-- одна кнопка, которая смотрит, что у игрока в руках: канистра — заливает бак,
-- огнемёт — заправляет огнемёт. Развилка живёт в OilCanisterSystem, владельце
-- этого промпта, и зовёт нас через _G.RefuelFlamethrower.

-- ═══════════ инициализация инструментов ═══════════

local function watch(container)
	container.ChildAdded:Connect(function(child)
		if isFlamethrower(child) then initTool(child) end
	end)
	for _, child in ipairs(container:GetChildren()) do
		if isFlamethrower(child) then initTool(child) end
	end
end

Players.PlayerAdded:Connect(function(player)
	local bp = player:WaitForChild("Backpack", 10)
	if bp then watch(bp) end
	player.CharacterAdded:Connect(function(char)
		watch(char)
		-- смерть с зажатой кнопкой не должна оставлять струю включённой
		stopFire(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	cooldownUntil[player] = nil
end)

print(("%s готов: бак %d мл = %d сек, порция от %.1f с, откат %.1f с")
	:format(LOG, Defs.CAPACITY, Defs.BURN_TIME, Defs.MIN_BURST, Defs.COOLDOWN))
do
	local k = Defs.VARIANTS[Defs.KRAKEN_NAME]
	print(("%s рука кракена: урон ×2 (%d/с), заряд копится сам за %d сек, дуло «%s»")
		:format(LOG, k.dps, math.floor(k.capacity / k.regenRate + 0.5), k.muzzle))
end
