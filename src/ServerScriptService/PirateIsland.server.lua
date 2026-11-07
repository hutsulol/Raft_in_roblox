--[[
	ПИРАТСКИЙ ОСТРОВ: заселение при спавне.

	Сам остров поднимает WorldEventSpawner (там же кнопка «(тест)» из настроек).
	Здесь — всё, что должно появиться ВМЕСТЕ с ним, по маркерам Pt_* из модели:

	  • ГАРНИЗОН — 14 постов. Пираты кладутся в папку Enemies внутри острова, и
	    дальше их ведёт уже существующий IslandClearSystem: он даёт HP, полоску над
	    головой, смерть с отбросом и засчитывает «остров зачищен». Заводить вторую
	    систему врагов ради этого острова незачем.
	  • ПЛЕННЫЕ — 5 точек. Врагами НЕ считаются (в Enemies не попадают), иначе
	    остров нельзя было бы зачистить, не перебив тех, кого пришли спасать.
	  • ЖИВОТНЫЕ — корова и три курицы по своим маркерам.

	Лица пленных меняются по ходу событий (ТЗ): в плену грусть, при освобождении
	удивление, на выходе из клетки радость. Снаружи это _G.FreePrisoners.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
-- нужен щиту первых секунд: смотрим, есть ли рядом кому убить зверя
local Players           = game:GetService("Players")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))
-- сборщики Motor6D-ригов новых животных (модули из пакетов Cow/Chicken)
local CowRig     = require(ReplicatedStorage:WaitForChild("CowRig"))
local ChickenRig = require(ReplicatedStorage:WaitForChild("ChickenRig"))

local ISLAND_NAME = Defs.ISLAND_NAME

-- ── поиск моделей ──
-- Имя сверяем БЕЗ регистра, пробелов, подчёркиваний и дефисов: модель курицы в
-- проекте зовётся то Chiken, то Chicken, и точный поиск на этом уже спотыкался.
local function normalize(s)
	return (s:lower():gsub("[%s_%-]", ""))
end

local templateCache = {}
local function findTemplate(name, alsoTry)
	if templateCache[name] and templateCache[name].Parent then return templateCache[name] end

	local names = { name }
	for _, n in ipairs(alsoTry or {}) do table.insert(names, n) end
	for _, n in ipairs(names) do
		local t = ReplicatedStorage:FindFirstChild(n) or ReplicatedStorage:FindFirstChild(n, true)
		if t then
			templateCache[name] = t
			return t
		end
	end

	local want = {}
	for _, n in ipairs(names) do want[normalize(n)] = true end
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("Accessory")) and want[normalize(d.Name)] then
			templateCache[name] = d
			return d
		end
	end
	return nil
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn("[ПиратОстров] " .. msg)
end

-- ── маркеры ──
-- Пивот маркера и есть точка спавна, его LookVector — куда смотреть.
local function markers(island)
	local out = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():sub(1, #Defs.MARKER_PREFIX) == Defs.MARKER_PREFIX then
			local post = Defs.postName(d.Name)
			if post then out[post] = d end
		end
	end
	return out
end

local function hideMarker(part)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
end

-- Ставим модель НА маркер: пивот в точку, лицом по маркеру. Чуть приподнимаем —
-- утопленный в грунт риг Roblox считает застрявшим и роняет ему здоровье.
local LIFT = 0.5
local function placeAt(model, marker)
	local cf = marker.CFrame
	local pos = cf.Position + Vector3.new(0, LIFT, 0)
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
end

-- ── лица ──
local function setFace(model, who, mood)
	local set = Defs.FACES[who]
	local id = set and set[mood]
	if not id then return false end
	local head = model:FindFirstChild("Head")
	if not head then return false end
	local ok = false
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			d.Texture = id
			ok = true
		end
	end
	if not ok then
		-- у некоторых скинов лица нет вовсе — заводим своё, иначе смена настроения
		-- не сработает ни сейчас, ни при освобождении
		local decal = Instance.new("Decal")
		decal.Name = "face"
		decal.Face = Enum.NormalId.Front
		decal.Texture = id
		decal.Parent = head
		ok = true
	end
	model:SetAttribute("Mood", mood)
	return ok
end

-- ── СУСТАВЫ R6: СТРОИМ САМИ ──
--
-- ⚠️ У моделей пиратов и пленных НЕТ НИ ОДНОГО Motor6D — детали склеены намертво
-- (диагностика CrewClips показала «0 из 6»). Пока сустава нет, анимация невозможна
-- в принципе: ни наши клипы, ни Animator двигать нечего. Поэтому собираем
-- стандартный набор R6 руками, с каноничными C0/C1, и убираем сварку между теми же
-- парами — иначе связь задвоится и конечности заклинит.
local R6_JOINTS = {
	{ name = "RootJoint",      p0 = "HumanoidRootPart", p1 = "Torso",
	  c0 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
	  c1 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi) },
	{ name = "Neck",           p0 = "Torso", p1 = "Head",
	  c0 = CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
	  c1 = CFrame.new(0, -0.5, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi) },
	{ name = "Left Shoulder",  p0 = "Torso", p1 = "Left Arm",
	  c0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0),
	  c1 = CFrame.new(0.5, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0) },
	{ name = "Right Shoulder", p0 = "Torso", p1 = "Right Arm",
	  c0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0),
	  c1 = CFrame.new(-0.5, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0) },
	{ name = "Left Hip",       p0 = "Torso", p1 = "Left Leg",
	  c0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0),
	  c1 = CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0) },
	{ name = "Right Hip",      p0 = "Torso", p1 = "Right Leg",
	  c0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0),
	  c1 = CFrame.new(0.5, 1, 0) * CFrame.Angles(0, math.pi / 2, 0) },
}

-- Имя детали → каноничное R6-имя. Без регистра, пробелов и подчёркиваний:
-- «Left Arm», «LeftArm» и «left_arm» — одно и то же.
local function normPart(s) return (s:lower():gsub("[%s_%-]", "")) end
local R6_ALIAS = {
	humanoidrootpart = "HumanoidRootPart", hrp = "HumanoidRootPart",
	torso = "Torso", head = "Head",
	leftarm = "Left Arm",  armleft = "Left Arm",  larm = "Left Arm",
	rightarm = "Right Arm", armright = "Right Arm", rarm = "Right Arm",
	leftleg = "Left Leg",  legleft = "Left Leg",  lleg = "Left Leg",
	rightleg = "Right Leg", legright = "Right Leg", rleg = "Right Leg",
}

-- Дамп структуры один раз на ТИП модели: если и эта версия не найдёт части, лог
-- назовёт их поимённо, и гадать больше не придётся.
local dumpedParts = {}
local function dumpParts(model)
	local kind = model.Name:match("^([%a_]+)_") or model.Name
	if dumpedParts[kind] then return end
	dumpedParts[kind] = true
	local names, seen = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not seen[d.Name] and #names < 15 then
			seen[d.Name] = true
			table.insert(names, d.Name .. (d.Parent ~= model and " (вложен в " .. d.Parent.Name .. ")" or ""))
		end
	end
	print(("[ПиратОстров] структура %s: %s"):format(model.Name,
		#names > 0 and table.concat(names, ", ") or "НЕТ ДЕТАЛЕЙ ВООБЩЕ"))
end

local function ensureR6Joints(model)
	--[[ ⚠️ ДОПОЛНЯЕМ, А НЕ СДАЁМСЯ. Раньше один найденный Motor6D значил «модель
	     нормальная, выходим». У ребёнка из клетки в шаблоне было четыре сустава из
	     шести (нет Left Shoulder и Right Hip) — и клипы играли на половине тела.
	     Теперь запоминаем, какие есть, и ставим только недостающие. ]]
	local have = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then have[d.Name] = true end
	end
	local complete = true
	for _, j in ipairs(R6_JOINTS) do if not have[j.name] then complete = false end end
	if complete then return 0 end
	dumpParts(model)

	-- ⚠️ ЧАСТИ ИЩЕМ ПО ВСЕЙ МОДЕЛИ, а не среди прямых детей: риги в этом проекте
	-- вложены под-моделью (у механика ровно так, см. findRig в EngineerSystem).
	-- Прошлая версия делала FindFirstChild("Torso") по верхнему уровню и молча
	-- возвращала 0 — поэтому суставы так и не появились.
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local canon = R6_ALIAS[normPart(d.Name)]
			if canon and not parts[canon] then parts[canon] = d end
		end
	end

	if not parts.Torso then
		local r15 = false
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and normPart(d.Name) == "uppertorso" then r15 = true break end
		end
		warnOnce("no_torso_" .. (model.Name:match("^([%a_]+)_") or model.Name),
			model.Name .. (r15 and ": риг R15 — набор клипов R6 не подойдёт, нужен другой"
				or ": Torso не нашёлся ни под каким именем — структура в строке выше"))
		return 0
	end

	-- Сварку МЕЖДУ ЧАСТЯМИ ТЕЛА сносим всю (любые пары, не только «свои»): Motor6D
	-- поверх сварки — заклиненная конечность. Сварка тела с аксессуарами и оружием
	-- остаётся: там вторая деталь не из списка.
	local bodySet = {}
	for _, p in pairs(parts) do bodySet[p] = true end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Snap") or d:IsA("Motor") then
			if d.Part0 and d.Part1 and bodySet[d.Part0] and bodySet[d.Part1] then d:Destroy() end
		end
	end

	local made = 0
	for _, j in ipairs(R6_JOINTS) do
		local p0, p1 = parts[j.p0], parts[j.p1]
		if p0 and p1 and not have[j.name] then
			local m = Instance.new("Motor6D")
			m.Name = j.name
			m.Part0 = p0
			m.Part1 = p1
			m.C0 = j.c0
			m.C1 = j.c1
			m.Parent = (j.name == "RootJoint") and p0 or parts.Torso
			made += 1
		end
	end
	return made
end

-- ── звезда начальника ──
-- Капитан и квартирмейстер помечены золотой звездой над головой, ПОКА ЦЕЛЫ:
-- игрок с порога видит, кто на острове главный. Первый же урон снимает метку.
local function attachBossStar(npc)
	local head = npc:FindFirstChild("Head", true) or npc.PrimaryPart
		or npc:FindFirstChildWhichIsA("BasePart", true)
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "BossStar"
	bb.Adornee = head
	-- ⚠️ РАЗМЕР В СТУДАХ (Scale), А НЕ В ПИКСЕЛЯХ (Offset).
	-- Было fromOffset(34, 34) — то есть 34 экранных пикселя, ПОСТОЯННЫХ на любом
	-- расстоянии. Вблизи это выглядело нормально, а с полсотни студов звезда
	-- оставалась прежней и накрывала пирата целиком: полоска ХП под ней —
	-- SurfaceGui, она честно уменьшается с расстоянием, звезда же не уменьшалась
	-- никак. Отсюда и «слишком большая»: дело не в числе, а в том, что метка жила
	-- в экранных координатах, а всё вокруг неё — в мировых.
	-- Scale у BillboardGui считается в студах, поэтому теперь звезда убывает
	-- вместе с полоской и остаётся ей соразмерной на любой дистанции.
	-- 0.9 студа — чуть меньше высоты полоски ХП (~1.08 студа).
	bb.Size = UDim2.fromScale(0.9, 0.9)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)   -- выше полоски подозрения/ХП
	bb.AlwaysOnTop = false                    -- за стеной звезду не видно
	bb.MaxDistance = 220
	bb.LightInfluence = 0

	local star = Instance.new("TextLabel")
	star.BackgroundTransparency = 1
	star.Size = UDim2.fromScale(1, 1)
	star.Font = Enum.Font.GothamBlack
	star.Text = "★"
	star.TextScaled = true
	star.TextColor3 = Color3.fromRGB(255, 205, 60)
	star.TextStrokeColor3 = Color3.fromRGB(45, 28, 0)
	star.TextStrokeTransparency = 0.2
	star.Parent = bb
	bb.Parent = npc

	local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
	if hum then
		hum.HealthChanged:Connect(function(hp)
			if hp < hum.MaxHealth and bb.Parent then bb:Destroy() end
		end)
	end
end

-- ── гарнизон ──
local function spawnGarrison(island, marks)
	local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
	if not enemies then
		enemies = Instance.new("Folder")
		enemies.Name = Defs.ENEMIES_FOLDER
		enemies.Parent = island
	end

	local placed = 0
	for post, crewName in pairs(Defs.POST_CREW) do
		local marker = marks[post]
		if marker then
			local tpl = findTemplate(crewName)
			if not tpl then
				warnOnce("crew_" .. crewName,
					("модели «%s» нет в ReplicatedStorage — пост %s остался пустым"):format(crewName, post))
			else
				local npc = tpl:Clone()
				npc.Name = crewName .. "_" .. post
				local cfg = Defs.CREW[crewName]
				if cfg then
					-- Урон и тип оружия — атрибутами: их читает боевой скрипт внутри
					-- модели, и правится это в одной таблице, а не в восьми моделях.
					npc:SetAttribute("MeleeDamage", (cfg.kind == "melee") and cfg.damage or nil)
					npc:SetAttribute("ShotDamage", (cfg.kind == "ranged") and cfg.damage or nil)
					npc:SetAttribute("WeaponKind", cfg.kind)
					npc:SetAttribute("WeaponName", cfg.weapon)
				end
				npc:SetAttribute("IslandPost", post)
				-- «Дом» поста: вокруг этой точки ходит обход (Defs.POST_WANDER),
				-- сюда же работает поводок и возврат после боя. ⚠️ Раньше дом был
				-- только у ЖИВОТНЫХ — у пиратов home в PirateIslandAI выходил nil,
				-- и ветка обхода молча не включалась: все стояли столбами.
				npc:SetAttribute("HomeX", marker.Position.X)
				npc:SetAttribute("HomeZ", marker.Position.Z)
				if Defs.BOSS and Defs.BOSS[crewName] then
					attachBossStar(npc)
				end

				-- ⚠️ ГЛУШИМ РОДНОЙ ИИ МОДЕЛИ. Внутри пиратов лежат свои скрипты
				-- преследования (Zombie/NpcAi/Combat), и они ведут ВСЕХ одинаково:
				-- бегут вплотную и машут. Именно из-за них стрелок вёл себя как
				-- сабельник. Бой теперь ведёт PirateIslandAI — по одному водителю на
				-- NPC, иначе два MoveTo дёргают его в разные стороны.
				for _, d in ipairs(npc:GetDescendants()) do
					if d:IsA("Script") then
						local n = d.Name:lower()
						if n:find("zombie") or n:find("npcai") or n:find("combat")
							or n:find("chase") or n:find("attack") or n:find("ai") then
							d.Disabled = true
						end
					end
				end

				placeAt(npc, marker)
				npc.Parent = enemies      -- HP, смерть и зачистку берёт IslandClearSystem
				local joints = ensureR6Joints(npc)
				if joints > 0 then
					warnOnce("joints", ("у моделей пиратов не было суставов — собрал R6 (%d на модель). "
						.. "Без этого анимация невозможна в принципе"):format(joints))
				end
				placed += 1
			end
		end
	end
	return placed
end

-- ── пленные: ОДНА СЕМЬЯ ЦЕЛИКОМ ──
-- В клетке сидит семья — отец, мать и ребёнок, — а не набор случайных людей.
-- Семья выбирается при спавне одна из трёх (Prisoner_<семья>_<роль> в ReplicatedStorage).
local function spawnPrisoners(island, marks)
	local folder = Instance.new("Folder")
	folder.Name = "Prisoners"
	folder.Parent = island

	local family = Defs.FAMILIES[math.random(#Defs.FAMILIES)]
	island:SetAttribute("PrisonerFamily", family.id)

	local placed = 0
	for i, roleCfg in ipairs(Defs.FAMILY_ROLES) do
		local point = Defs.PRISONER_POINTS[i]
		local marker = point and marks[point]
		local modelName = ("Prisoner_%s_%s"):format(family.id, roleCfg.role)
		if marker then
			local tpl = findTemplate(modelName)
			if not tpl then
				warnOnce("prisoner_" .. modelName,
					("модели «%s» нет в ReplicatedStorage — %s не поставлен"):format(modelName, roleCfg.role))
			else
				local npc = tpl:Clone()
				npc.Name = modelName
				npc:SetAttribute("Prisoner", true)
				npc:SetAttribute("FaceSet", roleCfg.face)
				npc:SetAttribute("Freed", false)
				npc:SetAttribute("WaterImmune", true)
				-- Пока в клетке — стоит на месте. Врагом не считается: он лежит вне
				-- папки Enemies, иначе остров нельзя было бы зачистить.
				local hum = npc:FindFirstChildWhichIsA("Humanoid")
				if hum then hum.WalkSpeed = 0 end
				placeAt(npc, marker)
				setFace(npc, roleCfg.face, "sad")   -- в плену — грусть
				npc.Parent = folder
				ensureR6Joints(npc)   -- пленным суставы нужны так же: они играют Bound
				if _G.PirateIslandAnim then _G.PirateIslandAnim.loop(npc, "idle") end
				placed += 1
			end
		end
	end
	print(("[ПиратОстров] в клетке семья: %s (%d человек)"):format(family.ru, placed))
	return placed
end

-- ── ЖИВОТНЫЕ: ПОСТАВИТЬ НА НОГИ И НА ЗЕМЛЮ ──
--
-- ⚠️ НОВЫЕ РИГИ. «Cow» и «Chicken» — отдельные MeshPart на Motor6D (сборка
-- CowRig / ChickenRig), стоят ровно, PrimaryPart = HumanoidRootPart, нос по -Z.
-- Вся ориентационная эквилибристика старых скинованных мешей (подбор «верха» по
-- габаритам, стойка с детали, NoseFlip, повёрнутый PivotOffset) умерла вместе с
-- ними — размещение теперь обычное: позиция маркера + рыскание по его взгляду.

-- Низ модели — по мировым осям, а не GetBoundingBox: тот бокс ориентирован по
-- пивоту, и у вытянутого зверя его size.Y — это длина, а не рост (прошлая корова
-- из-за этого парила на высоте травы). Честный мировой AABB по деталям.
local function worldBottomY(model)
	local bottom
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local half = 0.5 * (math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z)
			local b = cf.Position.Y - half
			if not bottom or b < bottom then bottom = b end
		end
	end
	return bottom
end

-- Высота грунта в точке. ⚠️ ТОЛЬКО ПО ТАЙЛАМ РЕЛЬЕФА: луч «мимо всего» сажал
-- корову на валун, а трава на этом острове коллидная. Земля — это
-- Island_terrain_* / Island_seabed, остальное для посадки не существует.
local function groundYAt(island, pos, model)
	local params = RaycastParams.new()
	params.IgnoreWater = true
	local terrain = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name:lower()
			if n:find("island_terrain", 1, true) or n:find("island_seabed", 1, true) then
				table.insert(terrain, d)
			end
		end
	end
	if #terrain > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = terrain
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true
	end
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), params)
	return hit and hit.Position.Y or nil
end

-- рыскание, при котором LookVector смотрит вдоль v
local function yawOf(v) return math.atan2(-v.X, -v.Z) end

local function placeAnimal(island, model, marker)
	local root = model.PrimaryPart
	if not root then return end

	-- ⚠️ ЯКОРЬ — ТОЛЬКО НА КОРНЕ. Зверя ведёт код (CFrame каждый кадр), а
	-- конечности держит Motor6D: заякоренная деталь сустав игнорирует, и
	-- анимация её не сдвинет. Упасть им сустав и не даст.
	-- ⚠️ CanQuery ОБЯЗАТЕЛЬНО ВКЛЮЧИТЬ: сборщики ригов его гасят, а конус
	-- топора и прочий урон ищут цели пространственным запросом — зверь с
	-- CanQuery=false для них не существовал (урон «не проходил»).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = (d == root)
			d.CanQuery = true
		end
	end
	-- твёрдое тело зверя — коробка корня (у коровы риг делал её неколлидной, и
	-- игрок проходил сквозь тушу)
	root.CanCollide = true

	-- Отступ «корень → копыта» меряем В АВТОРСКОЙ ПОЗЕ, до перестановки:
	-- конечности сервер довозит на новое место только следующим шагом физики,
	-- и замер после переезда увидел бы их на старом месте. При рыскании отступ
	-- не меняется — он один на всю жизнь зверя (читает и AnimalLife).
	local toBottom = root.Position.Y - (worldBottomY(model) or root.Position.Y)
	model:SetAttribute("FootOffset", toBottom)

	-- ⚠️ КУДА У РИГА НОС. Ось «вперёд» у корня после импорта непредсказуема: у
	-- коровы LookVector корня смотрел в хвост, и она ходила задом. Правду знает
	-- геометрия — голова всегда впереди торса; расхождение с LookVector корня
	-- запоминаем поправкой, движение (AnimalLife) довинчивает её к курсу.
	local headP = model:FindFirstChild("Head", true) or model:FindFirstChild("chicken_head", true)
	local torsoP = model:FindFirstChild("Torso", true) or model:FindFirstChild("chicken_torso", true)
	local flip = 0
	if headP and torsoP then
		local nose = headP.Position - torsoP.Position
		nose = Vector3.new(nose.X, 0, nose.Z)
		local rl = root.CFrame.LookVector
		if nose.Magnitude > 0.05 and nose:Dot(Vector3.new(rl.X, 0, rl.Z)) < 0 then
			flip = math.pi
		end
	end
	model:SetAttribute("YawFlip", flip)

	local look = marker.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local yaw = yawOf(flat.Unit)

	local gy = groundYAt(island, marker.Position, model)
	local y = gy and (gy + toBottom + 0.05) or (marker.Position.Y + toBottom)
	root.CFrame = CFrame.new(marker.Position.X, y, marker.Position.Z)
		* CFrame.Angles(0, yaw + flip, 0)

	print(("[ПиратОстров] %s встал в (%.0f, %.0f, %.0f)%s"):format(
		model.Name, root.Position.X, root.Position.Y, root.Position.Z,
		flip ~= 0 and " (нос против оси корня — довинчен на 180°)" or ""))
end

-- ── животные ──
-- Шаблон опознаём по имени И детали-паспорту (mustHave из конфига): в
-- ReplicatedStorage может валяться и СТАРАЯ модель с тем же именем «Cow».
-- Запасной вариант — Workspace: пока новую модель не перенесли в
-- ReplicatedStorage, берём её прямо оттуда (с предупреждением).
local function findAnimalTemplate(cfg)
	local function scan(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("Model") and normalize(d.Name) == normalize(cfg.model)
				and d:FindFirstChild(cfg.mustHave, true) then
				return d
			end
		end
		return nil
	end
	local t = scan(ReplicatedStorage)
	if t then return t end
	t = scan(Workspace)
	if t then
		warnOnce("animal_ws_" .. cfg.model,
			("шаблон «%s» найден в Workspace, а не в ReplicatedStorage — перенеси его туда"):format(cfg.model))
	end
	return t
end

local ANIMAL_RIGS = { Cow = CowRig, Chicken = ChickenRig }

local function spawnAnimals(island, marks)
	local folder = Instance.new("Folder")
	folder.Name = "Animals"
	folder.Parent = island

	local placed = 0
	for point, cfg in pairs(Defs.ANIMALS) do
		local marker = marks[point]
		if marker then
			local tpl = findAnimalTemplate(cfg)
			if not tpl then
				warnOnce("animal_" .. cfg.model,
					("модели «%s» (внутри должна быть деталь %s) нет в ReplicatedStorage — %s не поставлен")
						:format(cfg.model, cfg.mustHave, point))
			else
				local npc = tpl:Clone()
				npc.Name = cfg.model .. "_" .. point
				-- ⚠️ СУСТАВЫ — ПО АВТОРСКОЙ ПОЗЕ КЛОНА, до любых перемещений:
				-- CowRig снимает точки крепления с текущих позиций деталей.
				local okRig, rigErr = pcall(function()
					ANIMAL_RIGS[cfg.rig].setup(npc)
				end)
				if not okRig then
					warnOnce("rig_" .. cfg.model,
						("риг «%s» не собрался: %s"):format(cfg.model, tostring(rigErr)))
					npc:Destroy()
					continue
				end
				npc:SetAttribute("AnimalRig", cfg.rig)      -- каким аниматором его вести
				npc:SetAttribute("GrazeRadius", cfg.graze)  -- радиус выпаса, студы
				npc:SetAttribute("HomeX", marker.Position.X)
				npc:SetAttribute("HomeZ", marker.Position.Z)
				npc:SetAttribute("WaterImmune", true)
				-- ДИЧЬ, А НЕ ДЕКОРАЦИЯ: по этому флагу топор перестаёт считать
				-- зверя неприкосновенным (см. isFriendly в AxeCombat). Без него
				-- корову нельзя было убить ничем, кроме пушки: она попадала в
				-- список друзей по одному имени модели.
				npc:SetAttribute("Huntable", true)

				-- ЗДОРОВЬЕ: без Humanoid по животному не проходил никакой урон —
				-- и топор, и пули ищут именно Humanoid. Стейт-машину глушим: зверя
				-- ведёт код, физика гуманоида ему не нужна.
				local hum = npc:FindFirstChildWhichIsA("Humanoid")
				if not hum then
					hum = Instance.new("Humanoid")
					hum.Parent = npc
				end
				hum.MaxHealth = cfg.hp or 30
				hum.Health = hum.MaxHealth
				hum.BreakJointsOnDeath = false
				hum.EvaluateStateMachine = false
				hum.PlatformStand = true
				--[[ ⚠️ ШЕЮ У ЗВЕРЯ ДВИЖОК НЕ ПРОВЕРЯЕТ.
				     Humanoid по умолчанию требует деталь Head, соединённую
				     суставом «Neck», и БЕЗ НЕЁ УБИВАЕТ персонажа сам, без
				     всякого урона. У наших зверей риг собирается кодом
				     (CowRig/ChickenRig), имена суставов свои, и любая правка
				     рига мгновенно превращается в «зверь появился уже мёртвым».
				     Здоровьем животных распоряжается игра, а не проверка
				     скелета. ]]
				hum.RequiresNeck = false
				-- штатный дисплей Roblox гасим: имя модели и зелёная полоска над
				-- головой дублировали бы наш бар
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

				npc.Parent = folder
				placeAnimal(island, npc, marker)

				--[[ ⚠️ ЩИТ ПЕРВЫХ СЕКУНД: ЗВЕРЬ НЕ УМИРАЕТ «САМ ПО СЕБЕ».
				     Корова стартового острова появлялась уже трупом: остров
				     только встал, игрок ещё на плоту в сотне студов, а на берегу
				     лежит туша с выпавшим мясом. Убить её было некому — значит
				     это не урон, а что-то в самой сборке (проверка шеи,
				     столкновение при постановке, чужой скрипт внутри модели).
				     Ловим ровно этот случай: смерть в первые секунды И без
				     единого игрока поблизости. Такого «убийства» в игре не
				     бывает, поэтому здоровье возвращаем и пишем в лог — иначе
				     сюжетный квест «убей корову» становится невыполнимым, а
				     второй коровы не будет.
				     Настоящее убийство сюда не попадёт: чтобы ударить зверя,
				     игроку надо стоять рядом. ]]
				do
					local born = os.clock()
					local SHIELD_TIME = 20   -- секунд после появления
					local KILLER_NEAR = 90   -- студов: дальше топором не достать

					hum.HealthChanged:Connect(function(hp)
						if hp > 0 then return end
						if os.clock() - born > SHIELD_TIME then return end
						local root = npc.PrimaryPart
						if not root then return end

						for _, plr in ipairs(Players:GetPlayers()) do
							local ch = plr.Character
							local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
							if hrp and (hrp.Position - root.Position).Magnitude <= KILLER_NEAR then
								return   -- рядом есть кому убить: смерть настоящая
							end
						end

						hum.Health = hum.MaxHealth
						warn(("[ПиратОстров] %s умер сам через %.1f с после появления, рядом никого — здоровье возвращено. Ищи причину в сборке рига или в скриптах внутри модели.")
							:format(npc.Name, os.clock() - born))
					end)
				end

				-- ПОЛОСКА ХП — та же, что у врагов острова (EnemyHealthBar).
				-- Видна СРАЗУ (просили «ХП над ними»); гаснет только на трупе.
				local okHb, EnemyHealthBar = pcall(function()
					return require(ReplicatedStorage:WaitForChild("EnemyHealthBar", 5))
				end)
				local head = npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
				if okHb and EnemyHealthBar and head then
					local hb = EnemyHealthBar.new({
						name = cfg.ru or cfg.model,
						maxHp = hum.MaxHealth,
						cur = hum.Health,
						surface = true,
					})
					hb.attach(head, cfg.barUp or 2.5, "EnemyHP")
					hb.setVisible(true)
					hb.setHP(hum.Health, hum.MaxHealth)
					hum.HealthChanged:Connect(function(hp)
						if hp <= 0 then
							-- у трупа бара нет: встроенная плашка «МЁРТВ» модуля
							-- висела парящим словом без подложки
							hb.setVisible(false)
						else
							hb.setVisible(true)
							hb.setHP(hp, hum.MaxHealth)
						end
					end)
				end

				placed += 1
			end
		end
	end
	return placed
end

-- ⚠️ ПОСТАНОВКА ЗВЕРЕЙ ОТДАЁТСЯ НАРУЖУ, А НЕ КОПИРУЕТСЯ.
-- Стартовому острову нужна ровно одна корова, и соблазн переписать этот кусок у
-- себя большой — а в нём сидят три неочевидных требования подряд: риг собирается
-- ПО АВТОРСКОЙ ПОЗЕ (до любых перемещений), якорь ставится ТОЛЬКО на корень, и
-- CanQuery нужно вернуть руками, иначе конус топора зверя не находит. Две копии
-- этого разъедутся на первой же правке. Здесь тот же спавнер, просто с чужой
-- картой маркеров: ключи те же, что в Defs.ANIMALS, — какие точки передали, те
-- звери и встанут (стартовый остров передаёт только Cow_1).
_G.SpawnIslandAnimals = function(island, marks)
	if not (island and island.Parent and type(marks) == "table") then return 0 end
	local ok, placed = pcall(spawnAnimals, island, marks)
	if not ok then
		warn("[Пиратский остров] чужой остров: звери не встали — " .. tostring(placed))
		return 0
	end
	return placed
end

-- ── освобождение ──
-- Цепочка из ТЗ: удивление в момент освобождения → выход из клетки → радость.
local FREE_SURPRISE = 1.6    -- сколько держится удивление, прежде чем семья пойдёт
local WALK_OUT      = 18     -- на сколько студов отходят от клетки
local CAGE_NAMES    = { "Cage_prisoner", "Cage", "Cage_small" }

-- Куда идти из клетки: к воротам, если они есть в модели, иначе просто наружу от
-- центра острова — лишь бы не остаться стоять в решётке.
local function exitPoint(island, npc)
	local gate = island:FindFirstChild("Pt_Gate", true)
	if gate and gate:IsA("BasePart") then return gate.Position end
	local pivot = island:GetPivot().Position
	local hrp = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Torso")
	if not hrp then return pivot end
	local away = hrp.Position - pivot
	away = Vector3.new(away.X, 0, away.Z)
	away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(1, 0, 0)
	return hrp.Position + away * WALK_OUT
end

-- Дверь клетки. Модели двери у клетки нет, поэтому «открытие» — это снятие
-- коллизии и прозрачность у решётки: семья должна суметь выйти.
local function openCage(island)
	local opened = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, n in ipairs(CAGE_NAMES) do
				if d.Name:lower():find(n:lower(), 1, true) then
					d.CanCollide = false
					d.Transparency = math.max(d.Transparency, 0.55)
					opened += 1
					break
				end
			end
		end
	end
	return opened
end

--[[ ⚠️ ОСВОБОЖДЁННЫЙ РАДУЕТСЯ, ВЫХОДИТ И ИСЧЕЗАЕТ.
     Раньше после открытия клетки пленный стоял как вкопанный: детали шаблона
     приходили заякоренными (MoveTo такому не указ), Humanoid искался без
     рекурсии, а клипа ходьбы у пленного не было вовсе — при движении играла
     бы поза «связан». Теперь: удивление → клип «Freed» (радость, руки
     свободны) → атрибут Prisoner снимается, и NPC идёт к выходу обычной
     походкой команды → у выхода (или по таймауту) растворяется и удаляется.
     Владелец: «должен радоваться и пропадать после освобождения». ]]
local FREE_JOY      = 2.7    -- длина клипа Freed (2.67 с): даём дорадоваться
local WALK_TIMEOUT  = 8      -- не дошёл за столько секунд — всё равно растворяем
local FADE_TIME     = 1.2

local function vanish(npc)
	if not npc.Parent or npc:GetAttribute("Vanishing") then return end
	npc:SetAttribute("Vanishing", true)
	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(FADE_TIME + 0.1, function()
		if npc.Parent then npc:Destroy() end
	end)
end

-- Суставы нужны и пленным малых островов (IslandCrews): без Motor6D клипы
-- некуда класть, а модель без якоря разваливается на детали.
_G.EnsureR6Joints = ensureR6Joints

_G.FreePrisoners = function(island)
	local folder = island and island:FindFirstChild("Prisoners")
	if not folder then return 0 end
	if island:GetAttribute("PrisonersFreed") then return 0 end
	island:SetAttribute("PrisonersFreed", true)

	local bars = openCage(island)
	local n = 0
	for _, npc in ipairs(folder:GetChildren()) do
		if not npc:GetAttribute("Freed") then
			npc:SetAttribute("Freed", true)
			setFace(npc, npc:GetAttribute("FaceSet"), "surprise")
			n += 1

			task.delay(FREE_SURPRISE, function()
				if not npc.Parent then return end
				-- радость: лицо и клип «Freed» (руки развязаны, вскидывает их)
				setFace(npc, npc:GetAttribute("FaceSet"), "happy")
				if _G.PirateIslandAnim then _G.PirateIslandAnim.once(npc, "freed") end

				task.delay(FREE_JOY, function()
					if not npc.Parent then return end
					local hum = npc:FindFirstChildWhichIsA("Humanoid", true)
					local root = npc:FindFirstChild("HumanoidRootPart", true)
					-- шаблон мог прийти заякоренным — заякоренного MoveTo не сдвинет
					for _, d in ipairs(npc:GetDescendants()) do
						if d:IsA("BasePart") then d.Anchored = false end
					end
					-- дальше это уже не пленный: клипы ходьбы берутся из набора команды
					npc:SetAttribute("Prisoner", nil)
					if not (hum and root) then
						vanish(npc)
						return
					end
					hum.WalkSpeed = 10
					hum:MoveTo(exitPoint(island, npc))
					if _G.PirateIslandAnim then _G.PirateIslandAnim.loop(npc, "walk") end
					hum.MoveToFinished:Once(function() vanish(npc) end)
					task.delay(WALK_TIMEOUT, function() vanish(npc) end)
				end)
			end)
		end
	end
	print(("[ПиратОстров] клетка открыта (решёток %d), освобождено %d — радуются, выходят и исчезают"):format(bars, n))
	return n
end

-- КЛЕТКА ОТКРЫВАЕТСЯ, КОГДА ГАРНИЗОН МЁРТВ. Отдельного «ключа» не нужно: пираты
-- и есть замок. Проверяем папку Enemies — ту же, по которой считает зачистку
-- IslandClearSystem, чтобы два условия не разъехались.
local function watchGarrison(island)
	task.spawn(function()
		while island.Parent do
			task.wait(1)
			if island:GetAttribute("PrisonersFreed") then return end
			local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
			if enemies then
				local alive = 0
				for _, npc in ipairs(enemies:GetChildren()) do
					local hum = npc:IsA("Model") and npc:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0 then alive += 1 end
				end
				if alive == 0 then
					_G.FreePrisoners(island)
					return
				end
			end
		end
	end)
end

-- ── сборка ──
local function setup(island)
	if island:GetAttribute("PirateIslandReady") then return end
	if island:GetAttribute("Cleared") then return end   -- из сейва, уже зачищен: гарнизона нет
	island:SetAttribute("PirateIslandReady", true)

	local marks = markers(island)
	local total = 0
	for _ in pairs(marks) do total += 1 end

	local crew      = spawnGarrison(island, marks)
	local prisoners = spawnPrisoners(island, marks)
	local animals   = spawnAnimals(island, marks)
	watchGarrison(island)   -- перебьют гарнизон → откроется клетка

	-- маркеры прячем ПОСЛЕ расстановки: до неё они нужны видимыми только коду,
	-- но игрок не должен видеть на траве три десятка кубов
	for _, part in pairs(marks) do hideMarker(part) end

	print(("[ПиратОстров] заселён: маркеров %d, гарнизон %d, пленных %d, животных %d")
		:format(total, crew, prisoners, animals))
end

Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child.Name == ISLAND_NAME then
		task.defer(setup, child)
	end
end)

for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Model") and child.Name == ISLAND_NAME then
		setup(child)
	end
end
