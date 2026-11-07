--[[
	FarmerClips — рабочие клипы ФЕРМЕРА для R6-жителя, таблицей, без публикации.

	Подключается хвостом PirateCrewClips: build(DATA.clips) дописывает клипы в
	общий словарь, и клиентский проигрыватель поз (CrewClips) играет их по имени
	из атрибута Clip / ClipOnce, как у рабочих вышки.

	Правила те же, что у блока «НЕФТЕВЫШКА» в PirateCrewClips:
	  • торс (корневой сустав) не трогаем в рабочих клипах — он кренит всю фигуру;
	  • рука вперёд — поворот вокруг Z (плюс «вперёд» для обеих, зеркало внутри);
	  • tilt — завал рук внутрь, к средней линии (ось X);
	  • голова: плюс — вниз, минус — вверх;
	  • ноги при ходьбе: ОДИН знак на обе (зеркальность уже в риге).
	Стрижка строится от авторской позы WorkKneel (стоя на колене, руки у работы):
	вход — смесь простоя и её, цикл — движения ножницами правой рукой, выход —
	обратная смесь. Длительности разовых клипов продублированы в FarmDefs.CLIP_LEN.

	Редактируемый исходник — этот файл.
]]

local function cfOf(n)
	return CFrame.new(n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8], n[9], n[10], n[11], n[12])
end

local function numsOf(cf, px, py, pz)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

-- поза src с наложенными поворотами extras (сустав → CFrame), торс подброшен на dy
local function posed(src, extras, dy)
	local p = {}
	for joint, nums in pairs(src) do
		local cf = cfOf(nums)
		local e = extras and extras[joint]
		if e then cf = e * cf end
		local py = nums[2] + ((joint == "Torso") and (dy or 0) or 0)
		p[joint] = numsOf(cf, nums[1], py, nums[3])
	end
	return p
end

-- смесь двух поз сустав за суставом
local function blend(from, to, f)
	local out = {}
	for joint, nums in pairs(from) do
		local other = to[joint]
		if other then
			local cf = cfOf(nums):Lerp(cfOf(other), f)
			out[joint] = numsOf(cf,
				nums[1] + (other[1] - nums[1]) * f,
				nums[2] + (other[2] - nums[2]) * f,
				nums[3] + (other[3] - nums[3]) * f)
		else
			out[joint] = nums
		end
	end
	return out
end

local function arms(rFwd, lFwd, hRx, hRy, tilt)
	local t = math.rad(tilt or 0)
	return {
		["Right Arm"] = CFrame.Angles(t, 0, math.rad(rFwd)),
		["Left Arm"]  = CFrame.Angles(t, 0, math.rad(-lFwd)),
		["Head"]      = CFrame.Angles(math.rad(hRx or 0), math.rad(hRy or 0), 0),
	}
end

local function legs(deg)
	return {
		["Right Leg"] = CFrame.Angles(0, 0, math.rad(deg)),
		["Left Leg"]  = CFrame.Angles(0, 0, math.rad(deg)),
	}
end

local function withLegs(p, step)
	for k, v in pairs(legs(step)) do p[k] = v end
	return p
end

return function(Clips)
	local MI = Clips["MeleeIdle"]
	if not (MI and #MI.keys > 0) then
		warn("[FarmerClips] нет базового MeleeIdle — клипы фермера не собраны")
		return
	end
	local I0 = MI.keys[1].p

	-- ОЖИДАНИЕ С ГРУЗОМ: связка/ведро перед животом, обе руки вперёд и внутрь
	Clips["Farm_CarryIdle"] = { loop = true, length = 4, keys = {
		{ t = 0,   p = posed(I0, arms(42, 40, 4, 0, 18)) },
		{ t = 1.3, p = posed(I0, arms(44, 42, 2, 10, 19)) },
		{ t = 2.6, p = posed(I0, arms(41, 39, 5, -8, 18)) },
		{ t = 4,   p = posed(I0, arms(42, 40, 4, 0, 18)) },
	} }

	-- ПЕРЕНОСКА: руки держат груз устойчиво, ноги идут циклом Oil_Carry
	Clips["Farm_CarryWalk"] = { loop = true, length = 1.07, keys = {
		{ t = 0,    p = posed(I0, withLegs(arms(42, 40, 3, 0, 18),  22)) },
		{ t = 0.27, p = posed(I0, withLegs(arms(44, 42, 2, 0, 18),   0), 0.02) },
		{ t = 0.53, p = posed(I0, withLegs(arms(42, 40, 3, 0, 18), -22)) },
		{ t = 0.8,  p = posed(I0, withLegs(arms(44, 42, 2, 0, 18),   0), 0.02) },
		{ t = 1.07, p = posed(I0, withLegs(arms(42, 40, 3, 0, 18),  22)) },
	} }

	-- ПОЛОЖИТЬ: наклон к земле, отпускание на 0.6 с (FarmDefs.RELEASE_AT)
	Clips["Farm_PutDown"] = { loop = false, length = 1.1, keys = {
		{ t = 0,   p = posed(I0, arms(42, 40, 4, 0, 18)) },
		{ t = 0.35, p = posed(I0, arms(34, 32, 26, 0, 16)) },
		{ t = 0.6, p = posed(I0, arms(28, 26, 32, 0, 12)) },   -- ОТПУСТИЛ
		{ t = 0.85, p = posed(I0, arms(16, 14, 16, 0, 4)) },
		{ t = 1.1, p = posed(I0, arms(8, 10, 0, 0)) },
	} }

	-- ДВЕРЬ/ВОРОТА: правая рука к створке и толчок в сторону
	Clips["Farm_Door"] = { loop = false, length = 1.2, keys = {
		{ t = 0,   p = posed(I0, arms(8, 10, 0, 0)) },
		{ t = 0.3, p = posed(I0, arms(62, 12, 4, 8, 6)) },     -- потянулся к створке
		{ t = 0.7, p = posed(I0, arms(58, 12, 2, 24, -14)) },  -- повёл её в сторону
		{ t = 1.0, p = posed(I0, arms(30, 12, 0, 10, -4)) },
		{ t = 1.2, p = posed(I0, arms(8, 10, 0, 0)) },
	} }

	-- РАЗЛОЖИТЬ СЕНО: опустил связку в кормушку/на подстилку и распушил руками
	Clips["Farm_PlaceHay"] = { loop = false, length = 2.4, keys = {
		{ t = 0,   p = posed(I0, arms(42, 40, 6, 0, 18)) },
		{ t = 0.5, p = posed(I0, arms(30, 28, 28, 0, 14)) },   -- опустил
		{ t = 0.9, p = posed(I0, arms(26, 34, 30, 8, -6)) },   -- развёл руками
		{ t = 1.4, p = posed(I0, arms(34, 24, 30, -8, -10)) },
		{ t = 1.9, p = posed(I0, arms(22, 26, 24, 0, 2)) },
		{ t = 2.4, p = posed(I0, arms(8, 10, 0, 0)) },
	} }

	-- НАЛИТЬ: ведро в правой, наклон — с 1.0 с (FarmDefs.POUR_AT) льётся, до 2.0 с
	Clips["Farm_Pour"] = { loop = false, length = 2.6, keys = {
		{ t = 0,   p = posed(I0, arms(40, 14, 8, 0, 16)) },
		{ t = 0.6, p = posed(I0, arms(48, 30, 24, 0, 26)) },   -- поднёс к поилке
		{ t = 1.0, p = posed(I0, arms(52, 34, 30, 0, 46)) },   -- ОПРОКИНУЛ
		{ t = 2.0, p = posed(I0, arms(50, 34, 30, 0, 44)) },   -- льётся
		{ t = 2.3, p = posed(I0, arms(38, 20, 12, 0, 18)) },
		{ t = 2.6, p = posed(I0, arms(40, 14, 8, 0, 16)) },
	} }

	-- ГРАБЛИ: обе руки на черенке, гребёт к себе, смотрит под ноги
	Clips["Farm_Rake"] = { loop = true, length = 1.8, keys = {
		{ t = 0,   p = posed(I0, arms(58, 44, 28, 0, 24)) },   -- вытянул грабли
		{ t = 0.6, p = posed(I0, arms(36, 26, 32, 0, 22)) },   -- подгрёб
		{ t = 0.9, p = posed(I0, arms(30, 22, 30, 4, 20)) },
		{ t = 1.4, p = posed(I0, arms(50, 38, 26, -4, 24)) },  -- снова вперёд
		{ t = 1.8, p = posed(I0, arms(58, 44, 28, 0, 24)) },
	} }

	-- ПОГЛАДИТЬ: правая рука к боку овцы (низко, внутрь), плавные движения
	Clips["Farm_Calm"] = { loop = false, length = 3.6, keys = {
		{ t = 0,   p = posed(I0, arms(8, 10, 6, 0)) },
		{ t = 0.5, p = posed(I0, arms(38, 10, 26, -18, 30)) },  -- потянулся к шее
		{ t = 1.2, p = posed(I0, arms(46, 10, 28, -14, 34)) },  -- погладил
		{ t = 1.9, p = posed(I0, arms(36, 10, 26, -18, 30)) },
		{ t = 2.6, p = posed(I0, arms(45, 10, 27, -14, 34)) },
		{ t = 3.2, p = posed(I0, arms(24, 10, 14, -8, 14)) },
		{ t = 3.6, p = posed(I0, arms(8, 10, 6, 0)) },
	} }

	-- ОСМОТР: наклон головы к животному, рука на нём
	Clips["Farm_Inspect"] = { loop = false, length = 2.0, keys = {
		{ t = 0,   p = posed(I0, arms(8, 10, 4, 0)) },
		{ t = 0.5, p = posed(I0, arms(30, 12, 26, 18, 16)) },
		{ t = 1.2, p = posed(I0, arms(32, 12, 28, -10, 18)) },  -- повернул голову
		{ t = 1.6, p = posed(I0, arms(20, 12, 14, 0, 8)) },
		{ t = 2.0, p = posed(I0, arms(8, 10, 4, 0)) },
	} }

	-- ═══ СТРИЖКА: на колене, от авторской позы WorkKneel ═══
	local WK = Clips["WorkKneel"]
	local K0 = (WK and #WK.keys > 0) and WK.keys[1].p or posed(I0, arms(40, 36, 30, 0, 20))

	Clips["Farm_ShearEnter"] = { loop = false, length = 1.2, keys = {
		{ t = 0,   p = posed(I0, arms(8, 10, 4, 0)) },
		{ t = 0.4, p = blend(posed(I0, arms(30, 24, 20, 0, 12)), K0, 0.35) },
		{ t = 0.8, p = blend(I0, K0, 0.8) },
		{ t = 1.2, p = K0 },
	} }

	-- ножницы в правой руке: раскрываются/смыкаются взмахом руки
	local function snip(rFwd, tilt, hRy)
		return {
			["Right Arm"] = CFrame.Angles(math.rad(tilt), 0, math.rad(rFwd)),
			["Head"]      = CFrame.Angles(math.rad(6), math.rad(hRy or 0), 0),
		}
	end
	Clips["Farm_ShearLoop"] = { loop = true, length = 2.0, keys = {
		{ t = 0,   p = posed(K0, snip(0, 0, 0)) },
		{ t = 0.3, p = posed(K0, snip(14, 8, 4)) },     -- взмах
		{ t = 0.6, p = posed(K0, snip(-6, -4, 0)) },    -- сомкнул
		{ t = 1.0, p = posed(K0, snip(16, 10, -4)) },
		{ t = 1.3, p = posed(K0, snip(-6, -4, 0)) },
		{ t = 1.7, p = posed(K0, snip(12, 6, 2)) },
		{ t = 2.0, p = posed(K0, snip(0, 0, 0)) },
	} }

	Clips["Farm_ShearExit"] = { loop = false, length = 1.2, keys = {
		{ t = 0,   p = K0 },
		{ t = 0.5, p = blend(I0, K0, 0.6) },
		{ t = 0.9, p = posed(I0, arms(20, 16, 8, 0, 6)) },
		{ t = 1.2, p = posed(I0, arms(8, 10, 0, 0)) },
	} }

	-- Сильный завал нужен занятой руке; свободную не уводим за спину.
	local function farmArms(r, l, hx, hy, tilt)
		local p = arms(r, l, hx, hy, tilt)
		if tilt > 30 and l < 15 then
			p["Left Arm"] = CFrame.Angles(0, 0, math.rad(-l))
		end
		return p
	end
	-- Свободная рука не заваливается внутрь вместе с рукой, удерживающей мотыгу.
	local function hoeShoulder(r, l, hx, hy)
		local p = arms(r, l, hx, hy, 40)
		p["Left Arm"] = CFrame.Angles(0, 0, math.rad(-l))
		return p
	end

	-- Мотыга с плеча в рабочий хват; угол плеча ограничен ради целого меша.
	Clips["Farm_HoeEnter"] = { loop = false, length = 0.8, keys = {
		{ t = 0, p = posed(I0, farmArms(15, 8, 0, 0, 40), 0) },
		{ t = 0.2, p = posed(I0, farmArms(28, 20, 4, -3, 32), 0) },
		{ t = 0.5, p = posed(I0, farmArms(48, 38, 10, 0, 26), 0) },
		{ t = 0.8, p = posed(I0, farmArms(45, 34, 12, 0, 24), 0) },
	} }

	-- Замах, удар на 0.7 с и короткая протяжка к себе.
	Clips["Farm_HoeLoop"] = { loop = true, length = 1.6, keys = {
		{ t = 0, p = posed(I0, farmArms(45, 34, 12, 0, 24), 0) },
		{ t = 0.3, p = posed(I0, farmArms(65, 50, -8, -2, 28), 0) },
		{ t = 0.52, p = posed(I0, farmArms(63, 48, -5, 0, 27), 0) },
		{ t = 0.7, p = posed(I0, farmArms(20, 15, 30, 0, 22), 0) },
		{ t = 0.9, p = posed(I0, farmArms(24, 18, 32, 3, 24), 0) },
		{ t = 1.15, p = posed(I0, farmArms(32, 24, 24, 2, 24), 0) },
		{ t = 1.6, p = posed(I0, farmArms(45, 34, 12, 0, 24), 0) },
	} }

	-- Вернул инструмент на плечо.
	Clips["Farm_HoeExit"] = { loop = false, length = 0.8, keys = {
		{ t = 0, p = posed(I0, farmArms(45, 34, 12, 0, 24), 0) },
		{ t = 0.25, p = posed(I0, farmArms(52, 38, 4, 0, 26), 0) },
		{ t = 0.55, p = posed(I0, farmArms(30, 18, 0, -3, 34), 0) },
		{ t = 0.8, p = posed(I0, farmArms(15, 8, 0, 0, 40), 0) },
	} }

	-- Мотыга на плече; свободная рука движется против шага.
	Clips["Farm_WalkHoe"] = { loop = true, length = 1.07, keys = {
		{ t = 0, p = posed(I0, withLegs(hoeShoulder(15, 25, 0, -2), 22), 0) },
		{ t = 0.27, p = posed(I0, withLegs(hoeShoulder(17, 10, -2, 0), 0), 0.02) },
		{ t = 0.53, p = posed(I0, withLegs(hoeShoulder(15, -12, 1, 2), -22), 0) },
		{ t = 0.8, p = posed(I0, withLegs(hoeShoulder(16, 10, -1, 0), 0), 0.02) },
		{ t = 1.07, p = posed(I0, withLegs(hoeShoulder(15, 25, 0, -2), 22), 0) },
	} }

	-- Сено у правого плеча, взгляд свободен слева.
	Clips["Farm_HayShoulderWalk"] = { loop = true, length = 1.07, keys = {
		{ t = 0, p = posed(I0, withLegs(farmArms(70, 55, 2, -10, 30), 22), 0) },
		{ t = 0.27, p = posed(I0, withLegs(farmArms(68, 57, 0, -12, 30), 0), 0.02) },
		{ t = 0.53, p = posed(I0, withLegs(farmArms(70, 55, 3, -10, 30), -22), 0) },
		{ t = 0.8, p = posed(I0, withLegs(farmArms(69, 56, 1, -8, 30), 0), 0.02) },
		{ t = 1.07, p = posed(I0, withLegs(farmArms(70, 55, 2, -10, 30), 22), 0) },
	} }

	-- Лёгкое покачивание с охапкой.
	Clips["Farm_HayShoulderIdle"] = { loop = true, length = 3, keys = {
		{ t = 0, p = posed(I0, farmArms(70, 55, 2, -10, 30), 0) },
		{ t = 0.7, p = posed(I0, farmArms(68, 57, 0, -12, 30), 0.015) },
		{ t = 1.5, p = posed(I0, farmArms(69, 54, 4, -8, 29), 0) },
		{ t = 2.2, p = posed(I0, farmArms(68, 56, 1, -11, 31), 0.01) },
		{ t = 3, p = posed(I0, farmArms(70, 55, 2, -10, 30), 0) },
	} }

	-- Два ведра по сторонам; небольшой противоход рук.
	Clips["Farm_BucketsWalk"] = { loop = true, length = 1.07, keys = {
		{ t = 0, p = posed(I0, withLegs(farmArms(9, 1, 2, 0, -8), 22), 0) },
		{ t = 0.27, p = posed(I0, withLegs(farmArms(5, 5, 0, -2, -8), 0), 0.02) },
		{ t = 0.53, p = posed(I0, withLegs(farmArms(1, 9, 2, 0, -8), -22), 0) },
		{ t = 0.8, p = posed(I0, withLegs(farmArms(5, 5, 1, 2, -8), 0), 0.02) },
		{ t = 1.07, p = posed(I0, withLegs(farmArms(9, 1, 2, 0, -8), 22), 0) },
	} }

	-- Перехват ручек вёдер без высокого подъёма рук.
	Clips["Farm_BucketsIdle"] = { loop = true, length = 3, keys = {
		{ t = 0, p = posed(I0, farmArms(5, 5, 2, 0, -8), 0) },
		{ t = 0.65, p = posed(I0, farmArms(8, 6, 0, -4, -10), 0.015) },
		{ t = 1.4, p = posed(I0, farmArms(5, 5, 3, 0, -8), 0) },
		{ t = 2.2, p = posed(I0, farmArms(6, 8, 1, 4, -10), 0.015) },
		{ t = 3, p = posed(I0, farmArms(5, 5, 2, 0, -8), 0) },
	} }

	-- Короткий шаг с тяжёлым грузом у груди.
	Clips["Farm_HeavyCarryWalk"] = { loop = true, length = 1.2, keys = {
		{ t = 0, p = posed(I0, withLegs(farmArms(45, 43, -8, 0, 25), 15), 0) },
		{ t = 0.3, p = posed(I0, withLegs(farmArms(47, 45, -6, -2, 25), 0), 0.015) },
		{ t = 0.6, p = posed(I0, withLegs(farmArms(45, 43, -8, 0, 25), -15), 0) },
		{ t = 0.9, p = posed(I0, withLegs(farmArms(46, 46, -7, 2, 25), 0), 0.015) },
		{ t = 1.2, p = posed(I0, withLegs(farmArms(45, 43, -8, 0, 25), 15), 0) },
	} }

	-- Левая держит мешочек, правая набирает и рассыпает семена веером.
	Clips["Farm_SowLoop"] = { loop = true, length = 2, keys = {
		{ t = 0, p = posed(I0, farmArms(22, 30, 15, -8, 18), 0) },
		{ t = 0.35, p = posed(I0, farmArms(20, 32, 24, -12, 26), 0) },
		{ t = 0.65, p = posed(I0, farmArms(36, 30, 15, -5, 12), 0) },
		{ t = 1, p = posed(I0, farmArms(58, 31, 10, 12, -12), 0) },
		{ t = 1.35, p = posed(I0, farmArms(48, 30, 12, 22, -18), 0) },
		{ t = 1.7, p = posed(I0, farmArms(28, 32, 18, 4, 8), 0) },
		{ t = 2, p = posed(I0, farmArms(22, 30, 15, -8, 18), 0) },
	} }

	-- Лейка наклонена; плавно поливает по ширине грядки.
	Clips["Farm_WaterLoop"] = { loop = true, length = 2, keys = {
		{ t = 0, p = posed(I0, farmArms(40, 18, 22, -10, 28), 0) },
		{ t = 0.45, p = posed(I0, farmArms(43, 20, 24, -4, 32), 0) },
		{ t = 0.95, p = posed(I0, farmArms(41, 18, 22, 12, 36), 0) },
		{ t = 1.45, p = posed(I0, farmArms(38, 20, 25, 5, 31), 0) },
		{ t = 2, p = posed(I0, farmArms(40, 18, 22, -10, 28), 0) },
	} }

	-- Присел к сорняку, выдернул на 0.8 с, отбросил.
	Clips["Farm_Pluck"] = { loop = false, length = 1.4, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.35, p = posed(blend(I0, K0, 0.3), farmArms(22, 14, 12, 0, 8), 0) },
		{ t = 0.65, p = posed(blend(I0, K0, 0.6), farmArms(25, 14, 15, 0, 10), 0) },
		{ t = 0.8, p = posed(blend(I0, K0, 0.35), farmArms(44, 16, 8, 0, 14), 0) },
		{ t = 1.05, p = posed(I0, farmArms(48, 12, 4, 20, -18), 0) },
		{ t = 1.4, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Поднёс ладонь к морде, подождал и убрал руку.
	Clips["Farm_FeedHand"] = { loop = false, length = 2.2, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 4, 0, 0), 0) },
		{ t = 0.4, p = posed(I0, farmArms(35, 14, 20, -4, 12), 0) },
		{ t = 0.8, p = posed(I0, farmArms(37, 12, 22, -2, 14), 0) },
		{ t = 1.4, p = posed(I0, farmArms(35, 13, 20, 2, 12), 0) },
		{ t = 1.8, p = posed(I0, farmArms(24, 12, 12, 0, 8), 0) },
		{ t = 2.2, p = posed(I0, farmArms(8, 10, 4, 0, 0), 0) },
	} }

	-- Набрал сено и поднял к груди; захват на 0.9 с.
	Clips["Farm_Scoop"] = { loop = false, length = 1.6, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 4, 0, 0), 0) },
		{ t = 0.4, p = posed(I0, farmArms(30, 28, 28, 0, 16), 0) },
		{ t = 0.75, p = posed(I0, farmArms(22, 20, 32, -3, 22), 0) },
		{ t = 0.9, p = posed(I0, farmArms(28, 26, 30, 0, 24), 0) },
		{ t = 1.2, p = posed(I0, farmArms(42, 40, 16, 0, 24), 0) },
		{ t = 1.6, p = posed(I0, farmArms(45, 43, 6, 0, 25), 0) },
	} }

	-- Сдержанные движения наружу и короткие шаги при сгоне овец.
	Clips["Farm_Herd"] = { loop = true, length = 1.4, keys = {
		{ t = 0, p = posed(I0, withLegs(farmArms(25, 23, 8, -10, -30), 12), 0) },
		{ t = 0.35, p = posed(I0, withLegs(farmArms(29, 25, 6, 0, -38), 0), 0.015) },
		{ t = 0.7, p = posed(I0, withLegs(farmArms(23, 27, 8, 10, -30), -12), 0) },
		{ t = 1.05, p = posed(I0, withLegs(farmArms(26, 30, 6, 0, -38), 0), 0.015) },
		{ t = 1.4, p = posed(I0, withLegs(farmArms(25, 23, 8, -10, -30), 12), 0) },
	} }

	-- Быстрый двойной толчок ладонями вперёд.
	Clips["Farm_Shoo"] = { loop = false, length = 1, keys = {
		{ t = 0, p = posed(I0, farmArms(12, 14, 2, 0, -10), 0) },
		{ t = 0.18, p = posed(I0, farmArms(30, 28, -4, 0, -18), 0) },
		{ t = 0.4, p = posed(I0, farmArms(65, 62, 10, 0, -12), 0) },
		{ t = 0.6, p = posed(I0, farmArms(48, 46, 8, 2, -16), 0) },
		{ t = 0.78, p = posed(I0, farmArms(58, 56, 12, 0, -12), 0) },
		{ t = 1, p = posed(I0, farmArms(12, 14, 2, 0, -10), 0) },
	} }

	-- Присел и обхватил овцу, затем поднял к груди.
	Clips["Farm_CatchSheep"] = { loop = false, length = 1.5, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 6, 0, 0), 0) },
		{ t = 0.35, p = posed(blend(I0, K0, 0.3), farmArms(18, 18, 12, 0, 12), 0) },
		{ t = 0.65, p = posed(blend(I0, K0, 0.6), farmArms(24, 24, 12, 0, 18), 0) },
		{ t = 0.9, p = posed(blend(I0, K0, 0.4), farmArms(32, 30, 8, 0, 28), 0) },
		{ t = 1.2, p = posed(I0, farmArms(48, 46, 10, 0, 42), 0) },
		{ t = 1.5, p = posed(I0, farmArms(55, 55, 4, -10, 50), 0) },
	} }

	-- Бережно держит овцу двумя руками, короткий шаг.
	Clips["Farm_CarrySheep"] = { loop = true, length = 1.2, keys = {
		{ t = 0, p = posed(I0, withLegs(farmArms(55, 55, 4, -10, 50), 15), 0) },
		{ t = 0.3, p = posed(I0, withLegs(farmArms(57, 54, 2, -12, 48), 0), 0.015) },
		{ t = 0.6, p = posed(I0, withLegs(farmArms(55, 55, 4, -10, 50), -15), 0) },
		{ t = 0.9, p = posed(I0, withLegs(farmArms(54, 57, 3, -8, 49), 0), 0.015) },
		{ t = 1.2, p = posed(I0, withLegs(farmArms(55, 55, 4, -10, 50), 15), 0) },
	} }

	-- Приветствие: безопасный подъём до 120°, три покачивания рукой.
	Clips["Farm_Wave"] = { loop = false, length = 1.6, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.3, p = posed(I0, farmArms(120, 10, -8, 0, 8), 0) },
		{ t = 0.45, p = posed(I0, farmArms(120, 12, -6, 2, 20), 0) },
		{ t = 0.6, p = posed(I0, farmArms(120, 10, -7, 0, -6), 0) },
		{ t = 0.75, p = posed(I0, farmArms(120, 12, -6, 2, 20), 0) },
		{ t = 0.9, p = posed(I0, farmArms(120, 10, -7, 0, -6), 0) },
		{ t = 1.05, p = posed(I0, farmArms(120, 12, -6, 2, 20), 0) },
		{ t = 1.2, p = posed(I0, farmArms(120, 10, -7, 0, -6), 0) },
		{ t = 1.6, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Попеременные жесты и кивки во время разговора.
	Clips["Farm_TalkLoop"] = { loop = true, length = 3, keys = {
		{ t = 0, p = posed(I0, farmArms(12, 10, 0, 0, 4), 0) },
		{ t = 0.5, p = posed(I0, farmArms(32, 14, -6, -4, 10), 0) },
		{ t = 1, p = posed(I0, farmArms(18, 28, 6, 4, 8), 0) },
		{ t = 1.5, p = posed(I0, farmArms(10, 35, -8, 6, 12), 0) },
		{ t = 2, p = posed(I0, farmArms(26, 18, 8, -2, 6), 0) },
		{ t = 2.5, p = posed(I0, farmArms(18, 12, 2, -4, 4), 0) },
		{ t = 3, p = posed(I0, farmArms(12, 10, 0, 0, 4), 0) },
	} }

	-- Указал направление; плечо ограничено 70° согласно проверке ТЗ.
	Clips["Farm_Point"] = { loop = false, length = 1.4, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.3, p = posed(I0, farmArms(40, 12, 0, 12, -8), 0) },
		{ t = 0.55, p = posed(I0, farmArms(70, 10, -3, 25, -16), 0) },
		{ t = 0.95, p = posed(I0, farmArms(68, 12, 0, 25, -14), 0) },
		{ t = 1.15, p = posed(I0, farmArms(36, 10, 2, 12, -6), 0) },
		{ t = 1.4, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Пожал плечами, чуть развёл руки и склонил голову.
	Clips["Farm_Shrug"] = { loop = false, length = 1.2, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.25, p = posed(I0, farmArms(20, 22, -4, -8, -15), 0.03) },
		{ t = 0.5, p = posed(I0, farmArms(26, 24, -6, -10, -20), 0.04) },
		{ t = 0.8, p = posed(I0, farmArms(24, 25, -2, 6, -18), 0.03) },
		{ t = 1.2, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Два отчётливых кивка.
	Clips["Farm_Nod"] = { loop = false, length = 0.8, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.18, p = posed(I0, farmArms(8, 10, 15, 0, 0), 0) },
		{ t = 0.35, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.55, p = posed(I0, farmArms(8, 10, 15, 0, 0), 0) },
		{ t = 0.8, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Одобрительный жест цельной рукой R6, без пальцев.
	Clips["Farm_ThumbUp"] = { loop = false, length = 1.2, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.25, p = posed(I0, farmArms(34, 12, -2, 0, 12), 0) },
		{ t = 0.45, p = posed(I0, farmArms(60, 10, -4, -3, 20), 0) },
		{ t = 0.75, p = posed(I0, farmArms(58, 12, 8, 0, 18), 0) },
		{ t = 0.95, p = posed(I0, farmArms(34, 10, 2, 0, 10), 0) },
		{ t = 1.2, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Оглядел хозяйство слева направо.
	Clips["Farm_IdleLook"] = { loop = false, length = 3, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.6, p = posed(I0, farmArms(10, 8, 3, -30, 2), 0) },
		{ t = 1.2, p = posed(I0, farmArms(8, 12, 0, -26, 0), 0) },
		{ t = 1.9, p = posed(I0, farmArms(10, 8, 2, 30, 2), 0) },
		{ t = 2.5, p = posed(I0, farmArms(8, 12, -2, 20, 0), 0) },
		{ t = 3, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Вытер лоб, затем опустил руку; высокий замах не нужен.
	Clips["Farm_WipeBrow"] = { loop = false, length = 2, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.4, p = posed(I0, farmArms(55, 12, 12, -8, 30), 0) },
		{ t = 0.7, p = posed(I0, farmArms(70, 14, 18, -10, 44), 0) },
		{ t = 1.1, p = posed(I0, farmArms(68, 12, 16, 8, 36), 0) },
		{ t = 1.4, p = posed(I0, farmArms(65, 14, 12, 12, 42), 0) },
		{ t = 1.7, p = posed(I0, farmArms(32, 10, 4, 0, 18), 0) },
		{ t = 2, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Потянул плечи и поднял голову, не вращая торс.
	Clips["Farm_StretchBack"] = { loop = false, length = 2.4, keys = {
		{ t = 0, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
		{ t = 0.5, p = posed(I0, farmArms(32, 30, -10, 0, -12), 0) },
		{ t = 1, p = posed(I0, farmArms(65, 62, -20, -3, -18), 0) },
		{ t = 1.5, p = posed(I0, farmArms(62, 65, -18, 3, -20), 0) },
		{ t = 1.9, p = posed(I0, farmArms(36, 34, -10, 0, -12), 0) },
		{ t = 2.4, p = posed(I0, farmArms(8, 10, 0, 0, 0), 0) },
	} }

	-- Отдых с опорой на черенок и небольшим переносом веса.
	Clips["Farm_LeanTool"] = { loop = true, length = 4, keys = {
		{ t = 0, p = posed(I0, farmArms(30, 28, 8, 0, 35), -0.03) },
		{ t = 1, p = posed(I0, farmArms(32, 30, 4, -10, 36), -0.02) },
		{ t = 2, p = posed(I0, farmArms(29, 31, 10, 4, 34), -0.04) },
		{ t = 3, p = posed(I0, farmArms(31, 29, 6, 10, 35), -0.025) },
		{ t = 4, p = posed(I0, farmArms(30, 28, 8, 0, 35), -0.03) },
	} }
end
