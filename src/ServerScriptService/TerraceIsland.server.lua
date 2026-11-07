--[[
	ОСТРОВ-ТЕРРАСА (TerraceIsle_SCENE): гарнизон + взрывоопасная перегонка.

	ЧТО ЗДЕСЬ:
	  • ГАРНИЗОН — четверо по маркерам Pt_* внутри модели (Farmer, Overseer,
	    Guard, Hauler). Кладутся в папку Enemies, дальше их ведут те же системы,
	    что и пиратский лагерь: IslandClearSystem (HP, полоски, смерть, зачистка)
	    и PirateIslandAI (посты, обход, слух, бой).
	  • ПЕРЕГОННЫЙ КУБ (Virus_still_001) — взрывается от попадания: красный
	    кислотный взрыв, который поджигает СОСЕДНИЕ кусты красной травы.
	  • ПОЖАР — куст горит ~10 секунд и всё это время поджигает соседей; сгорев,
	    даёт игроку монеты и салют иконок (как добыча с зомби).
	  • БОЧКИ (Virus_drum_*) — то же самое, но радиус и сам взрыв меньше.

	⚠️ КТО ПОЛУЧАЕТ МОНЕТЫ. Поджигатель тянется по цепочке: куб знает, кто в него
	выстрелил, и передаёт это каждому подожжённому кусту, а тот — своим соседям.
	Иначе за цепной пожар, который начал игрок, не платил бы никто.
]]

local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local Defs = require(ReplicatedStorage:WaitForChild("PirateIslandDefs"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

local LOG = "[Терраса]"

-- ⚠️ ОСТРОВОВ С ВИРУСОМ БОЛЬШЕ ОДНОГО.
-- На верфи те же Virus_drum и Virus_crop_sm, и цепной пожар им нужен точно
-- такой же. Вторая копия этого кода разошлась бы с первой при первой правке
-- баланса, поэтому здесь просто список имён, а не один остров.
local ISLAND_NAMES = {
	TerraceIsle_SCENE = true,
	ShipIsle_SCENE    = true,
	SmallIsle_SCENE   = true,
	-- аванпост: за частоколом та же плантация вируса, и по сюжету её жгут
	-- огнемётом — код поджига и пожара нужен ровно тот же
	OutpostIsle_SCENE = true,
	-- остров фермеров: грядки теплиц (GH_BurnCrop_*) и заражённая трава снаружи
	-- (BurnGrass_*) горят так же, бочек и куба там нет
	Farmers_Game_Water = true,
}
local function isVirusIsland(inst)
	return inst:IsA("Model") and ISLAND_NAMES[inst.Name] == true
end

-- ── гарнизон ──
-- Роли из garrison.json набора: у каждой свой пират из ReplicatedStorage, своё
-- оружие и занятие на посту. Клипы берём ИЗ СУЩЕСТВУЮЩЕГО набора: авторские
-- PickCrop/HaulSack/LeanFence в нашу таблицу ещё не приехали, поэтому подобраны
-- ближайшие по смыслу (работа на корточках, ящик, стойка у ограды).
-- ⚠️ ТИП ОРУЖИЯ И УРОН НЕ ЗАДАЁМ ЗДЕСЬ — их берём из Defs.CREW по модели.
-- Прошлая версия прописывала их руками, и надсмотрщик получил «ranged» при
-- модели с САБЛЕЙ: он стрелял из клинка. Модель решает, чем он вооружён, —
-- значит и тип боя должен идти оттуда же. Нужен стрелок на посту — ставь
-- стрелковую модель (Bosun/Gunner/Swab), а не переопределяй kind.
local POSTS = {
	Farmer   = { crew = "Pirate_Deckhand",  idle = "WorkKneel" },
	Overseer = { crew = "Pirate_Bosun",     idle = "Scan", boss = true },   -- револьвер: он и есть реле тревоги
	Guard    = { crew = "Pirate_Cutthroat", idle = "LeanPost" },
	Hauler   = { crew = "Pirate_Deckhand",  idle = "LeanCrate" },
}

-- ── взрывы и пожар ──
local STILL_NAME  = "Virus_still"      -- перегонный куб: большой взрыв
local DRUM_NAME   = "Virus_drum"       -- бочка: маленький
local CROP_NAME   = "Virus_crop_sm"    -- кусты красной травы (горят)
-- ⚠️ ИМЁН У ГОРЮЧИХ КУСТОВ НЕСКОЛЬКО: у острова фермеров свои (см. ISLAND_NAMES).
-- Те же префиксы читают IslandClearSystem и IslandQuestSystem — держать равными.
local CROP_PREFIXES = { CROP_NAME, "GH_BurnCrop_", "BurnGrass_" }
-- ⚠️ ТРАВА СНАРУЖИ (BurnGrass_*) ГОРИТ БЕСПЛАТНО (владелец): монеты и зачёт
-- квесту — только за заражённые грядки. В зачистку она тоже не входит
-- (IslandClearSystem/IslandQuestSystem её не считают).
local FREE_BURN_PREFIX = "BurnGrass_"
local function isFreeBurn(n) return n:sub(1, #FREE_BURN_PREFIX) == FREE_BURN_PREFIX end
local function isCropName(n)
	for _, pre in ipairs(CROP_PREFIXES) do
		if n:sub(1, #pre) == pre then return true end
	end
	return false
end

local STILL = {
	radius = 26,        -- на сколько студов поджигает кусты
	scale  = 1,         -- размер эффекта
	damage = 55,        -- урон игрокам и NPC рядом
	hurtR  = 16,
}
local DRUM = {
	radius = 13,
	scale  = 0.45,
	damage = 25,
	hurtR  = 9,
}

local BURN_TIME     = 10     -- сколько горит один куст
local SPREAD_EVERY  = 1.6    -- как часто горящий куст пробует поджечь соседа
local SPREAD_RADIUS = 11     -- «соседний» — вот в этом радиусе
local SPREAD_CHANCE = 0.75
local COINS_PER_CROP = 1     -- монет за сожжённый куст
local COIN_ICON = "rbxassetid://93617165412571"

local ACID = Color3.fromRGB(190, 20, 45)          -- гранатовая кислота
local ACID_LT = Color3.fromRGB(255, 120, 120)

-- ── ТЕКСТУРЫ ЭФФЕКТОВ ──
-- ⚠️ ВЗРЫВ — СВОЙ ФЛИПБУК 4×4 (16 кадров): вспышка → шар → дым.
-- Исходник листа: test/Acid_explosion_flipbook.png. Меняешь картинку — меняй id
-- здесь; сетка кадров задана ниже (Grid4x4), при другой раскладке править и её.
local TEX_EXPLOSION = "rbxassetid://139050293462686"
local TEX_FLAME     = "rbxassetid://140408648514726"  -- флипбук огня (тот же, что у мангала)
local EXPLOSION_IS_FLIPBOOK = TEX_EXPLOSION ~= ""

local LootBurstFX
pcall(function()
	LootBurstFX = require(ReplicatedStorage:WaitForChild("LootBurstFX", 5))
end)

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	warn(LOG .. " " .. msg)
end

local function playSound(pos, id, volume, speed)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	p.Parent = Workspace
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.7
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 260
	s.Parent = p
	s:Play()
	Debris:AddItem(p, 5)
end

-- ═══════════════════ ЭФФЕКТ КИСЛОТНОГО ВЗРЫВА ═══════════════════
-- Стандартный Explosion не используем как картинку: у него свой оранжевый шар,
-- который не перекрасить. Берём его только ради толчка (и то приглушённого), а
-- рисуем своё: гранатовая вспышка, кислотные брызги и багровый дым.
local function acidBlast(pos, cfg)
	local k = cfg.scale

	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery = true, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = Workspace
	Debris:AddItem(anchor, 6)

	local at = Instance.new("Attachment")
	at.Parent = anchor

	-- ── САМ ВЗРЫВ: НАШ ЛИСТ, ПРОКРУЧЕННЫЙ ПОКАДРОВО ВРУЧНУЮ ──
	-- ⚠️ ФЛИПБУК ЧАСТИЦ ЗДЕСЬ НЕ РАБОТАЕТ. ParticleEmitter.FlipbookLayout
	-- капризен к тому, как загружена картинка (Image против Decal), и молча
	-- рисует пустоту: id в логе есть, а на экране ничего. Поэтому кадры листаем
	-- сами — ImageRectOffset по сетке 4×4. Это работает с ЛЮБЫМ id и даёт точный
	-- контроль над темпом.
	local FRAMES, FPS, GRID, CELL = 16, 15, 4, 256
	local RUN = FRAMES / FPS
	if EXPLOSION_IS_FLIPBOOK then
		local size = 26 * k
		local bb = Instance.new("BillboardGui")
		bb.Name = "AcidBlast"
		bb.Size = UDim2.fromScale(size, size)   -- Scale у BillboardGui — это студы
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		bb.MaxDistance = 500
		bb.Adornee = anchor
		bb.Parent = anchor

		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = TEX_EXPLOSION
		img.ImageRectSize = Vector2.new(CELL, CELL)
		img.ImageRectOffset = Vector2.new(0, 0)
		img.Parent = bb

		task.spawn(function()
			local t0 = os.clock()
			while bb.Parent do
				local f = math.floor((os.clock() - t0) * FPS)
				if f >= FRAMES then break end
				img.ImageRectOffset = Vector2.new((f % GRID) * CELL, math.floor(f / GRID) * CELL)
				-- шар ещё и растёт: одна прокрутка кадров без роста читается плоско
				local grow = 1 + 0.5 * (f / FRAMES)
				bb.Size = UDim2.fromScale(size * grow, size * grow)
				task.wait()
			end
			bb:Destroy()
		end)
	end

	-- дым: багровый, оседает медленно
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(ACID, Color3.fromRGB(60, 10, 18))
	smoke.LightInfluence = 0.6
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4 * k),
		NumberSequenceKeypoint.new(1, 22 * k),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.4, 2.6)
	smoke.Speed = NumberRange.new(3 * k, 9 * k)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.Rate = 0
	smoke.Parent = at

	local light = Instance.new("PointLight")
	light.Color = ACID
	light.Brightness = 6
	light.Range = 30 * k
	light.Parent = anchor

	smoke:Emit(math.floor(18 * k) + 5)

	-- ── УДАРНАЯ ВОЛНА ── (не зависит от текстур)
	-- Прозрачная сфера, которая за треть секунды раздувается и тает. Нужна не
	-- только для красоты: если флипбук по какой-то причине не подхватится,
	-- взрыв всё равно читается как взрыв, а не как «мигнуло и пропало».
	task.spawn(function()
		local wave = Instance.new("Part")
		wave.Shape = Enum.PartType.Ball
		wave.Material = Enum.Material.Neon
		wave.Color = ACID_LT
		wave.Anchored, wave.CanCollide, wave.CanQuery, wave.CastShadow = true, false, false, false
		wave.Size = Vector3.one * 2
		wave.CFrame = CFrame.new(pos)
		wave.Parent = Workspace
		local T = 0.35
		local t0 = os.clock()
		while wave.Parent do
			local a = (os.clock() - t0) / T
			if a >= 1 then break end
			wave.Size = Vector3.one * (2 + (cfg.hurtR * 2.2) * a)
			wave.Transparency = 0.25 + 0.75 * a
			task.wait()
		end
		wave:Destroy()
	end)

	playSound(pos, "rbxassetid://3802269741", cfg.scale >= 1 and 0.85 or 0.5,
		cfg.scale >= 1 and 0.75 or 1.15)

	-- ⚠️ Instance Explosion НЕ СОЗДАЁМ ВООБЩЕ: его оранжевый шар не
	-- перекрашивается, а толчок разбирает остров на детали. Урон считаем сами.
	-- урон живым в радиусе
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 and (hrp.Position - pos).Magnitude <= cfg.hurtR then
			hum:TakeDamage(cfg.damage)
		end
	end
end

-- ═══════════════════ ПОЖАР НА ГРЯДКАХ ═══════════════════
local burning = {}   -- [part] = { until, igniter, nextSpread }

-- ЗВУК ГОРЕНИЯ берём У КОСТРА, а не хардкодим id: он лежит авторски внутри
-- шаблона FireCamp, поменяют его там — поле зашумит так же. Тем же путём идёт
-- мангал (см. findCampfireBurnSound в GrillSystem).
local burnSoundId, burnSoundVol
local function fireSound()
	if burnSoundId ~= nil then return burnSoundId, burnSoundVol end
	-- ⚠️ ЗАПАСНОЙ ВАРИАНТ — ВСТРОЕННЫЙ ЗВУК. Костра (FireCamp) может не быть в
	-- ReplicatedStorage, его звук может не грузиться по правам — и поле горело
	-- молча. rbxasset:// лежит в самом движке: он играет всегда и ни от чего не
	-- зависит. Треск получаем из «щелчка» на пониженном питче.
	burnSoundId, burnSoundVol = "rbxasset://sounds/snap.mp3", 0.6
	local tpl = AssetFind.find("FireCamp")
	if tpl then
		for _, d in ipairs(tpl:GetDescendants()) do
			-- Флаг Looped не требуем: в шаблоне звук лежит не зацикленным,
			-- зацикливает его уже сам костёр. Одноразовый «бросок бревна»
			-- пропускаем по имени — так же делает мангал.
			if d:IsA("Sound") and d.SoundId ~= ""
				and not d.Name:lower():find("drop", 1, true) then
				burnSoundId = d.SoundId
				burnSoundVol = (d.Volume > 0) and d.Volume or 0.6
				print(("%s звук горения взят у костра: %s (%s)"):format(LOG, d.Name, d.SoundId))
				return burnSoundId, burnSoundVol
			end
		end
	end
	print(LOG .. " звук костра не нашёлся — горим на встроенном (rbxasset://sounds/snap.mp3)")
	return burnSoundId, burnSoundVol
end

local function cropParts(island)
	local out = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and isCropName(d.Name)
			and not d:GetAttribute("Burnt") then
			table.insert(out, d)
		end
	end
	return out
end

local function fireOn(part)
	local at = part:FindFirstChild("CropFire")
	if at then return end
	-- ⚠️ ЭМИТТЕР ВЕШАЕМ НА ДЕТАЛЬ, А НЕ НА ТОЧКУ.
	-- Attachment — это ОДНА точка, и всё пламя било из центра куста тонкой
	-- струйкой. Родитель-BasePart раздаёт частицы по всему объёму детали, и куст
	-- горит целиком — что и нужно. Метку-attachment оставляем только как признак
	-- «этот куст уже подожжён» и как место для света.
	at = Instance.new("Attachment")
	at.Name = "CropFire"
	at.Position = Vector3.new(0, -part.Size.Y * 0.2, 0)
	at.Parent = part

	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Flame"
	-- тот же флипбук, что у мангала: настоящие языки пламени вместо пятна
	fire.Texture = TEX_FLAME
	fire.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	fire.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	fire.FlipbookFramerate = NumberRange.new(20, 20)
	fire.FlipbookStartRandom = true   -- иначе все языки пульсируют хором
	fire.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 170, 90), ACID)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.4, 1.5),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.35, 0.6)
	fire.Rate = 26                       -- куст горит весь, а не одной струйкой
	fire.Speed = NumberRange.new(0.5, 1.3)
	fire.SpreadAngle = Vector2.new(16, 16)
	fire.Acceleration = Vector3.new(0, 1.6, 0)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.ZOffset = 0.05
	fire.Parent = part                   -- ← по всему объёму куста

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 30, 35))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1, 1.8)
	smoke.Rate = 7
	smoke.Speed = NumberRange.new(1, 2)
	smoke.Acceleration = Vector3.new(0.4, 3.2, 0)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = part

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 70)
	light.Brightness = 1.3
	light.Range = 8
	light.Parent = at

	-- ТРЕСК ОГНЯ — ОДИН НА ОЧАГ, А НЕ НА КАЖДЫЙ КУСТ.
	-- Горящих кустов бывает полсотни разом: полсотни одинаковых зацикленных
	-- звуков дают либо кашу, либо (если делать каждый тихим) неслышный шорох.
	-- Поэтому звук получает только тот куст, рядом с которым его ещё нет — и он
	-- нормальной громкости, слышный по всему полю.
	local hasNear = false
	for other in pairs(burning) do
		if other ~= part and other.Parent and other:FindFirstChild("BurnSound")
			and (other.Position - part.Position).Magnitude < 26 then
			hasNear = true
			break
		end
	end
	if not hasNear then
		local id, vol = fireSound()
		if id ~= "" then
			local builtin = id:sub(1, 10) == "rbxasset:/"
			local s = Instance.new("Sound")
			s.Name = "BurnSound"
			s.SoundId = id
			s.Volume = math.max(vol, 0.5)
			s.Looped = true
			-- встроенный «щелчок» на низком питче даёт треск; авторский звук
			-- костра играем почти как есть, лишь чуть расстраивая соседние очаги
			s.PlaybackSpeed = builtin and (0.32 + math.random() * 0.08)
				or (0.92 + math.random() * 0.2)
			s.RollOffMaxDistance = 130
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.Parent = part
			s:Play()
			-- проверка «звук вообще запустился»: если нет, скажем об этом один раз
			task.delay(0.4, function()
				if s.Parent and not s.IsPlaying then
					warnOnce("burn_silent",
						("звук горения не играет (%s) — вероятно, ассет недоступен"):format(id))
				end
			end)
		end
	end
end

-- Куст догорел: салют монет над ним, начисление поджигателю, куст исчезает.
-- последнее результативное действие на острове — для бонуса IslandQuestSystem
local function markActor(inst, plr)
	if not (plr and plr.Parent) then return end
	local island = inst:FindFirstAncestorWhichIsA("Model")
	while island and island.Parent ~= Workspace do island = island.Parent end
	if island then island:SetAttribute("LastActorId", plr.UserId) end
end

local function burnOut(part, igniter)
	part:SetAttribute("Burnt", true)
	burning[part] = nil
	markActor(part, igniter)

	if igniter and igniter.Parent and not isFreeBurn(part.Name) then
		if _G.AddPirate then
			pcall(_G.AddPirate, igniter, COINS_PER_CROP)
		else
			igniter:SetAttribute("Pirate", (igniter:GetAttribute("Pirate") or 0) + COINS_PER_CROP)
		end
		-- ⚠️ ЗАЧЁТ КВЕСТУ ИДЁТ ИМЕННО ЗДЕСЬ, А НЕ В МОМЕНТ ПОДЖИГА.
		-- Поджечь куст можно и случайно — от бочки, от соседнего пожара. Квест
		-- «выжги заразу» закрывает СГОРЕВШИЙ куст: он досчитался до конца и
		-- исчез с грядки. Заодно это единственное место, где известен и куст, и
		-- кто его поджёг.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, igniter, "burned:VirusCrop", 1)
		end
	end
	if LootBurstFX and not isFreeBurn(part.Name) then
		pcall(LootBurstFX.play, part, { COIN_ICON }, { heightOffset = 1.2 })
	end

	-- Огонь и звук гасим сразу: эмиттеры и Sound висят на самой детали, и без
	-- этого догоревший куст продолжал бы гореть и трещать, пока тает.
	for _, d in ipairs(part:GetChildren()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Sound") and d.Name == "BurnSound" then
			d:Stop()
			d:Destroy()
		end
	end
	local mark = part:FindFirstChild("CropFire")
	if mark then mark:Destroy() end

	-- пепел: куст съёживается и тает, а не пропадает кадром
	task.spawn(function()
		local t0 = os.clock()
		local size0 = part.Size
		while part.Parent and os.clock() - t0 < 1.2 do
			local a = (os.clock() - t0) / 1.2
			part.Transparency = a
			part.Size = size0:Lerp(size0 * 0.35, a)
			part.Color = Color3.fromRGB(40, 30, 30)
			task.wait()
		end
		if part.Parent then part:Destroy() end
	end)
end

local function ignite(part, igniter)
	if burning[part] or part:GetAttribute("Burnt") then return end
	if not part.Parent then return end
	burning[part] = {
		untilT = os.clock() + BURN_TIME,
		igniter = igniter,
		nextSpread = os.clock() + SPREAD_EVERY,
	}
	fireOn(part)
end

-- Соседние кусты: те, что реально рядом. Радиус небольшой — пожар должен
-- ползти от грядки к грядке, а не накрывать поле разом.
local function igniteNear(island, pos, radius, igniter)
	local n = 0
	for _, crop in ipairs(cropParts(island)) do
		if (crop.Position - pos).Magnitude <= radius then
			ignite(crop, igniter)
			n += 1
		end
	end
	return n
end

-- ВХОД ДЛЯ ОГНЕМЁТА.
-- ⚠️ ПОДЖИГАЕТ ТОЛЬКО КУСТЫ. Общий обработчик попадания умеет ещё и рвать
-- бочки, а струя огнемёта их взрывать не должна — поэтому у неё свой вход,
-- который ничего, кроме igniteNear, не зовёт.
_G.TerraceIgniteAt = function(pos, radius, igniter)
	if typeof(pos) ~= "Vector3" then return 0 end
	local total = 0
	for _, island in ipairs(Workspace:GetChildren()) do
		if isVirusIsland(island) then
			total += igniteNear(island, pos, radius or 7, igniter)
		end
	end
	return total
end

-- ── УРОН ОТ ОГНЯ ──
-- Стоять посреди горящего поля должно быть больно. Урон считаем РАЗ В ТИК и
-- один раз на игрока, сколько бы кустов вокруг ни горело: иначе в гуще пламени
-- он умирал бы мгновенно от полусотни источников сразу.
local FIRE_HURT_RADIUS = 7      -- ближе этого к горящему кусту — жжёт
local FIRE_DPS         = 9      -- урона в секунду
local FIRE_TICK        = 0.5
local nextHurt = 0

local function hurtInFire(now)
	if now < nextHurt then return end
	nextHurt = now + FIRE_TICK
	if not next(burning) then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 then
			for part in pairs(burning) do
				if part.Parent and (part.Position - hrp.Position).Magnitude <= FIRE_HURT_RADIUS then
					hum:TakeDamage(FIRE_DPS * FIRE_TICK)
					break   -- один куст за тик: горящее поле не должно убивать мгновенно
				end
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	hurtInFire(now)
	for part, st in pairs(burning) do
		if not part.Parent then
			burning[part] = nil
		elseif now >= st.untilT then
			burnOut(part, st.igniter)
		elseif now >= st.nextSpread then
			st.nextSpread = now + SPREAD_EVERY
			local island = part:FindFirstAncestorWhichIsA("Model")
			while island and island.Parent ~= Workspace do
				island = island.Parent
			end
			if island and math.random() < SPREAD_CHANCE then
				igniteNear(island, part.Position, SPREAD_RADIUS, st.igniter)
			end
		end
	end
end)

-- ═══════════════════ ВЗРЫВООПАСНЫЕ ОБЪЕКТЫ ═══════════════════
local function explode(part, cfg, byPlayer)
	if part:GetAttribute("Exploded") then return end
	part:SetAttribute("Exploded", true)

	local island = part:FindFirstAncestorWhichIsA("Model")
	while island and island.Parent ~= Workspace do island = island.Parent end
	local pos = part.Position
	markActor(part, byPlayer)

	acidBlast(pos, cfg)
	local lit = igniteNear(island or Workspace, pos, cfg.radius, byPlayer)
	print(("%s взрыв: %s, текстура %s, подожжено кустов %d"):format(
		LOG, part.Name, EXPLOSION_IS_FLIPBOOK and TEX_EXPLOSION or "(своей нет — огонь мангала)", lit))

	-- сама ёмкость исчезает: осталась бы стоять целой — было бы странно
	part:Destroy()

	-- цепная детонация: соседние бочки ловят взрыв с задержкой
	if island then
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("BasePart") and not d:GetAttribute("Exploded")
				and d.Name:sub(1, #DRUM_NAME) == DRUM_NAME
				and (d.Position - pos).Magnitude <= cfg.radius then
				task.delay(0.25 + math.random() * 0.5, function()
					if d.Parent then explode(d, DRUM, byPlayer) end
				end)
			end
		end
	end
end

-- КТО ВЫСТРЕЛИЛ. Пуля — это деталь с именем Bullet_* (револьвер, пушки), и в
-- ней лежит атрибут стрелка, если система его проставила. Иначе считаем
-- ближайшего игрока: он и нажимал на курок.
local function shooterOf(bullet, pos)
	local byId = bullet and bullet:GetAttribute("FiredBy")
	if byId then
		local plr = Players:GetPlayerByUserId(byId)
		if plr then return plr end
	end
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < (bestD or 300) then best, bestD = plr, d end
		end
	end
	return best
end

-- Похоже ли задевшее на снаряд. Имя «Bullet_*» ставит наш револьвер и пушки,
-- но у стороннего оружия оно может быть любым — поэтому второй признак:
-- маленькая быстрая незаякоренная деталь, не принадлежащая персонажу.
local function looksLikeProjectile(hit)
	if hit.Name:sub(1, 6) == "Bullet" then return true end
	if hit.Anchored then return false end
	if hit.Size.Magnitude > 4 then return false end
	local model = hit:FindFirstAncestorWhichIsA("Model")
	if model and model:FindFirstChildWhichIsA("Humanoid") then return false end
	return hit.AssemblyLinearVelocity.Magnitude > 60
end

local function hookExplosive(part, cfg)
	if part:GetAttribute("ExplosiveHooked") then return end
	part:SetAttribute("ExplosiveHooked", true)
	part.CanQuery = true
	part.CanTouch = true

	local function onHit(hit)
		if part:GetAttribute("Exploded") then return end
		if not looksLikeProjectile(hit) then return end
		explode(part, cfg, shooterOf(hit, part.Position))
	end
	part.Touched:Connect(onHit)

	-- ⚠️ РАСШИРЕННЫЙ ХИТБОКС. Бочка мелкая, а пуля летит сотнями студов в
	-- секунду: между шагами физики она перепрыгивает её насквозь, и Touched не
	-- срабатывает вовсе — потому куб (он большой) взрывался, а бочка нет.
	-- Невидимая коробка вокруг ловит такие пролёты. Без коллизии и без массы:
	-- ни ходьбу, ни физику она не трогает.
	local pad = 2.5
	local hb = Instance.new("Part")
	hb.Name = "ExplosiveHitbox"
	hb.Size = part.Size + Vector3.new(pad, pad, pad)
	hb.CFrame = part.CFrame
	hb.Transparency = 1
	hb.CanCollide = false
	hb.CanQuery = false
	hb.CanTouch = true
	hb.Massless = true
	hb.Anchored = part.Anchored
	hb.Parent = part
	if not part.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, hb
		w.Parent = hb
	end
	hb.Touched:Connect(onHit)
end

-- ═══════════════════ ГАРНИЗОН ═══════════════════
local templateCache = {}
local function findCrew(name)
	if templateCache[name] and templateCache[name].Parent then return templateCache[name] end
	local t = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
	if t then templateCache[name] = t end
	return t
end

local function spawnGarrison(island)
	local enemies = island:FindFirstChild(Defs.ENEMIES_FOLDER)
	if not enemies then
		enemies = Instance.new("Folder")
		enemies.Name = Defs.ENEMIES_FOLDER
		enemies.Parent = island
	end

	local placed = 0
	for post, cfg in pairs(POSTS) do
		local marker = island:FindFirstChild("Pt_" .. post, true)
		if marker and marker:IsA("BasePart") then
			local tpl = findCrew(cfg.crew)
			if not tpl then
				warnOnce("crew_" .. cfg.crew,
					("модели «%s» нет в ReplicatedStorage — пост %s пуст"):format(cfg.crew, post))
			else
				local npc = tpl:Clone()
				npc.Name = cfg.crew .. "_" .. post
				-- чем вооружён — решает модель (общая таблица), а не пост
				local crew = Defs.CREW[cfg.crew] or { kind = "melee", damage = 10 }
				npc:SetAttribute("WeaponKind", crew.kind)
				npc:SetAttribute("MeleeDamage", (crew.kind == "melee") and crew.damage or nil)
				npc:SetAttribute("ShotDamage", (crew.kind == "ranged") and crew.damage or nil)
				npc:SetAttribute("IslandPost", post)
				npc:SetAttribute("HomeX", marker.Position.X)
				npc:SetAttribute("HomeZ", marker.Position.Z)
				npc:SetAttribute("WaterImmune", true)

				-- родной ИИ модели глушим: ведёт PirateIslandAI (иначе два водителя)
				for _, d in ipairs(npc:GetDescendants()) do
					if d:IsA("Script") then
						local n = d.Name:lower()
						if n:find("zombie") or n:find("npcai") or n:find("combat")
							or n:find("chase") or n:find("attack") or n:find("ai") then
							d.Disabled = true
						end
					end
				end

				-- ставим на маркер: пивот модели ниже ног, поэтому по габариту
				local prim = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart", true)
					or npc:FindFirstChildWhichIsA("BasePart", true)
				if prim then
					local _, size = npc:GetBoundingBox()
					npc:PivotTo(CFrame.new(marker.Position + Vector3.new(0, size.Y * 0.5, 0))
						* CFrame.Angles(0, math.atan2(-marker.CFrame.LookVector.X,
							-marker.CFrame.LookVector.Z), 0))
				end
				npc.Parent = enemies
				placed += 1
			end
		end
	end
	return placed
end

-- ═══════════════════ ЗАСЕЛЕНИЕ ОСТРОВА ═══════════════════
local done = setmetatable({}, { __mode = "k" })

local function setupIsland(island)
	if island:GetAttribute("Cleared") then return end   -- из сейва, уже зачищен: гарнизона нет
	if done[island] then return end
	done[island] = true

	local stills, drums, crops = 0, 0, 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name:sub(1, #STILL_NAME) == STILL_NAME then
				hookExplosive(d, STILL)
				stills += 1
			elseif d.Name:sub(1, #DRUM_NAME) == DRUM_NAME then
				hookExplosive(d, DRUM)
				drums += 1
			elseif isCropName(d.Name) then
				crops += 1
			end
		end
	end

	-- ⚠️ ГАРНИЗОН СТАВИМ ТОЛЬКО СВОЙ.
	-- Взрывы и пожар общие для всех островов с вирусом, а вот посты у каждого
	-- свои: на верфи это Shipwright/Sawyer/Grower/Watch, и селит их ShipIsle.
	-- Иначе на верфи появилась бы вторая, террасная четвёрка поверх первой.
	local garrison = 0
	if island.Name == "TerraceIsle_SCENE" then
		garrison = spawnGarrison(island)
	end
	print(("%s %s: гарнизон %d, перегонных кубов %d, бочек %d, кустов вируса %d")
		:format(LOG, island.Name, garrison, stills, drums, crops))
end

local function scan()
	for _, m in ipairs(Workspace:GetChildren()) do
		if isVirusIsland(m) then
			setupIsland(m)
		end
	end
end

Workspace.ChildAdded:Connect(function(inst)
	if isVirusIsland(inst) then
		task.defer(function()
			if inst.Parent then setupIsland(inst) end
		end)
	end
end)
scan()

print(LOG .. " готов: гарнизон по маркерам, куб и бочки взрываются кислотой, поле горит")
