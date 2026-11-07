--[[
	SharkAnimator — анимация акулы, которая пишется прямо в Motor6D.Transform.
	Ни одного опубликованного ассета, ни загрузки рига, ни деформации.

	Клипы:

	  Swim    базовый цикл. Бегущая волна от носа к хвосту: каждый сустав
	          повторяет предыдущий с запозданием, поэтому тело идёт змейкой,
	          а не качается целиком как доска.
	  Gnaw    базовый цикл: акула вцепилась в плот. Пасть приоткрыта и держит,
	          а туша мотается вправо-влево ВОКРУГ ПАСТИ, не утаскивая её.
	  Notice  разовый: заметила игрока, дёрнула головой и начала доворачивать.
	  Attack  разовый: рывок вперёд с раскрытой пастью и захлопом.

		local a = Animator.new(motors)
		a:setBase("Swim")
		a:fire("Attack")             -- можно звать сто раз, они складываются
		RunService.Heartbeat:Connect(function(dt) a:step(dt) end)

	Оси здесь роблоксовы: нос смотрит в −Z, верх +Y, вбок X. Значит рыскание
	(змейка) — это Y, а челюсть и наклон головы — X.

	⚠️ ЗНАК ЧЕЛЮСТИ. Точка перед шарниром лежит по −Z, и поворот Rx уводит её
	ВВЕРХ при положительном угле. Пасть открывается ОТРИЦАТЕЛЬНЫМ X. Знак взят
	не из общего правила — общего правила нет, — а посчитан для этого рига.

	⚠️ УГЛЫ СКЛАДЫВАЮТСЯ ЧИСЛАМИ, А НЕ МАТРИЦАМИ. Сегменты входят друг в друга
	хвостовиками, и хвостовик обязан остаться спрятанным: у каждого сустава есть
	предел, дальше которого он вылазит сквозь стенку соседа. Складывая базу и
	накладки перемножением CFrame, зажать сумму нельзя — а так можно, и LIMITS
	ниже держат её жёстко.
]]

local Animator = {}
Animator.__index = Animator

local Z3 = { 0, 0, 0 }

--[[ Потолок поворота на сустав, в градусах, по осям X / Y / Z.

     Замерено, а не выбрано: scratchpad/joint_limits.py берёт вершины ребёнка,
     спрятанные в родителе на покое, и считает, сколько из них перестало быть
     прикрытыми после поворота. Замер идёт ПО ОБЕИМ ОСЯМ — хвостовик не круглый,
     и потолок на рыскание для тангажа не годится:

                     тангаж (X)        рыскание (Y)
         Head        18° / вниз 33°        24°
         Body2            9°                9°
         Tail        24° / вниз 18°        15°

     Здесь взято с запасом. Крен (Z) не мерился отдельно — стоит заведомо
     скромный. Челюсть в этот счёт не попадает: она снаружи и ничего собой не
     закрывает, её потолок задан тем, где зубы перестают смыкаться, и проверен
     рендером. Root не ограничен вовсе — он двигает всю тушу целиком,
     разъехаться нечему. ]]
local LIMITS = {
	Head  = { 14, 20, 12 },
	Body2 = { 8, 8, 8 },
	Tail  = { 15, 13, 13 },
	Jaw   = { 34, 6, 6 },
}

------------------------------------------------------------ клипы -----------
local Clips = {}
Animator.Clips = Clips

--[[ Синусоида ключами. Считается кодом, а не вбивается руками: у волны важна
     только амплитуда и запаздывание, а два десятка чисел, набранных вручную,
     ошибаются молча и ловятся уже глазами на модели. ]]
local function wave(amp: number, lag: number, n: number?)
	local keys, steps = {}, n or 8
	for i = 0, steps do
		local f = i / steps
		keys[#keys + 1] = { f, { 0, amp * math.sin(2 * math.pi * (f - lag)), 0 } }
	end
	return keys
end

--[[ Рыскание корня ВОКРУГ ЗАДАННОЙ ТОЧКИ, а не вокруг самого корня.

     Нужно для Gnaw: акула держится за плот, значит держаться должна голова, а
     мотаться — туша. Поворот вокруг точки v — это тот же поворот плюс перенос
     t = v − R·v; в toCF перенос стоит слева от поворота, ровно как надо.

     ⚠️ ТОЧКА — ШЕЯ, А НЕ ПАСТЬ. Кажется, что держать надо пасть, но голова в
     этом же клипе гасит поворот корпуса на СВОЁМ суставе, то есть вокруг шеи.
     Сложи одно с другим — и неподвижной выходит шея, а с ней и вся голова
     целиком, челюсть включительно. С точкой пасти замер дал уход 0.71 стада
     против 0.43 вообще без компенсации; с шеей — 0.00.

     Приезжает из SharkRigData (Neck), а не вбита сюда: пересобрали модель —
     поехала и она. ]]
local function swayAbout(v: Vector3, amp: number, n: number?)
	local keys, steps = {}, n or 12
	for i = 0, steps do
		local f = i / steps
		local a = math.rad(amp * math.sin(2 * math.pi * f))
		local r = CFrame.Angles(0, a, 0)
		local t = v - r * v
		keys[#keys + 1] = { f, { 0, amp * math.sin(2 * math.pi * f), 0 }, { t.X, t.Y, t.Z } }
	end
	return keys
end

-- Ход вперёд. Запаздывание растёт к хвосту — это и есть бегущая волна;
-- поставь всем один сдвиг, и акула завиляет как одна палка. Повороты идут
-- вниз по цепочке, поэтому у хвоста в мире выходит сумма Body2 + Tail.
Clips.Swim = {
	length = 2.2, loop = true, additive = false,
	tracks = {
		Head  = wave(2.5, 0.00),
		Body2 = wave(5.5, 0.14),
		Tail  = wave(10.0, 0.28),
		-- лёгкий крен в сторону поворота и подъём-опускание всей туши
		Root = {
			{ 0, { 0, 0, 3.0 }, { 0, 0.10, 0 } },
			{ 0.25, { 0, 0, 0 }, { 0, 0, 0 } },
			{ 0.50, { 0, 0, -3.0 }, { 0, -0.10, 0 } },
			{ 0.75, { 0, 0, 0 }, { 0, 0, 0 } },
			{ 1, { 0, 0, 3.0 }, { 0, 0.10, 0 } },
		},
	},
}

--[[ Вцепилась в плот и мотает тушей.

     Пасть приоткрыта и ДЕРЖИТСЯ — челюсть неподвижна весь цикл. Туша ходит
     вправо-влево вокруг пасти (см. swayAbout), а голова докручивается назад на
     тот же угол, чтобы морда оставалась направленной в плот: тогда мотается
     тело, а не то, за что акула держится.

     Голова получает −14° при рыскании корня +14°, и это влезает в её потолок
     20°; корень не ограничен вовсе — он несёт всю тушу разом. ]]
Clips.Gnaw = {
	length = 1.5, loop = true, additive = false, sway = 14.0,
	tracks = {
		Jaw = {
			{ 0, { -13, 0, 0 } },
			{ 0.5, { -16, 0, 0 } },     -- чуть подрабатывает, будто перехватывает
			{ 1, { -13, 0, 0 } },
		},
		-- ⚠️ ТЕМ ЖЕ ГЕНЕРАТОРОМ И С ТЕМ ЖЕ ЧИСЛОМ КЛЮЧЕЙ, что и рыскание корня,
		-- иначе гашение неточное: пять ключей против двенадцати сглаживаются
		-- по-разному, и голова гуляла на 0.20 стада вместо нуля.
		Head  = wave(-14.0, 0.0, 12),
		Body2 = wave(6.5, 0.10, 12),
		Tail  = wave(11.0, 0.22, 12),
		-- Root заполняется в build() ниже: ему нужна точка пасти из RigData
	},
}

--[[ Заметила. Короткий рывок головой в сторону цели и разворот корпуса вслед —
     сам доворот делает ИИ, перемещая модель; клип продаёт момент.
     ⚠️ Аддитивный: все дорожки обязаны вернуться в ноль на t = 1. ]]
Clips.Notice = {
	length = 0.85, loop = false, additive = true,
	tracks = {
		Head = {
			{ 0, { 0, 0, 0 } },
			{ 0.12, { -4, 11, 0 } },     -- голова дёрнулась вбок и пригнулась
			{ 0.34, { -2, 9, 0 } },
			{ 0.70, { 0, 4, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Body2 = {
			{ 0, { 0, 0, 0 } },
			{ 0.20, { 0, -2, 0 } },      -- корпус выгибается против головы
			{ 0.55, { 0, 2, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Tail = {
			{ 0, { 0, 0, 0 } },
			{ 0.16, { 0, -6, 0 } },      -- и один резкий мах хвостом в доворот
			{ 0.46, { 0, 4, 0 } },
			{ 0.74, { 0, -2, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Root = {
			{ 0, Z3, { 0, 0, 0 } },
			{ 0.18, { 0, -7, 5 }, { 0, 0.06, 0 } },
			{ 0.50, { 0, -4, 3 }, { 0, 0.03, 0 } },
			{ 1, Z3, { 0, 0, 0 } },
		},
	},
}

--[[ Атака: рывок вперёд с раскрытой пастью и захлопом.
     Ход даёт корень (переносом по −Z), пасть — челюсть, толчок — хвост.
     ⚠️ Все дорожки обязаны вернуться в ноль на t = 1. ]]
Clips.Attack = {
	length = 0.66, loop = false, additive = true,
	tracks = {
		Jaw = {
			{ 0, { 0, 0, 0 } },
			{ 0.20, { -28, 0, 0 } },     -- минус — пасть раскрывается
			{ 0.44, { -32, 0, 0 } },
			{ 0.60, { 2, 0, 0 } },       -- захлоп с перебором: читается как щелчок
			{ 0.78, { -1, 0, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Head = {
			{ 0, { 0, 0, 0 } },
			{ 0.18, { 7, 0, 0 } },       -- плюс — нос вверх, замах
			{ 0.42, { 5, 0, 0 } },
			{ 0.60, { -5, 0, 0 } },      -- и вниз, вместе с захлопом
			{ 1, { 0, 0, 0 } },
		},
		Body2 = {
			{ 0, { 0, 0, 0 } },
			{ 0.14, { 0, 0, 0 } },
			{ 0.40, { -4, 0, 0 } },      -- корпус подбирается под бросок
			{ 0.70, { 2, 0, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Tail = {
			{ 0, { 0, 0, 0 } },
			{ 0.14, { 0, -12, 0 } },
			{ 0.42, { 0, 8, 0 } },
			{ 0.72, { 0, -3, 0 } },
			{ 1, { 0, 0, 0 } },
		},
		Root = {
			{ 0, Z3, { 0, 0, 0 } },
			{ 0.18, { 5, 0, 0 }, { 0, 0.12, -0.55 } },
			{ 0.44, { -4, 0, 0 }, { 0, -0.08, -1.30 } },
			{ 0.74, { 1, 0, 0 }, { 0, 0, -0.45 } },
			{ 1, Z3, { 0, 0, 0 } },
		},
	},
}

--[[ Дорожка Root у Gnaw строится из точки пасти, которую знает только RigData,
     поэтому клипы досоздаются вызовом build() из рига. Пока его не позвали,
     Gnaw просто мотает тушей вокруг корня — работает, но пасть уезжает. ]]
function Animator.build(mouth: Vector3)
	Clips.Gnaw.tracks.Root = swayAbout(mouth, Clips.Gnaw.sway)
end

-- ⚠️ Аддитивный слой снимается тем, что доходит до нуля сам. Клип, который
-- этого не делает, на последнем кадре дёргает деталь — ловится глазами и
-- долго, поэтому проверяем на загрузке модуля.
for name, clip in pairs(Clips) do
	if clip.additive then
		for track, keys in pairs(clip.tracks) do
			local last = keys[#keys]
			assert(last[1] == 1, ("SharkAnimator: %s/%s не кончается на t=1")
				:format(name, track))
			for i = 1, 3 do
				assert(math.abs(last[2][i]) < 1e-6 and math.abs((last[3] or Z3)[i]) < 1e-6,
					("SharkAnimator: аддитивный %s/%s не возвращается в ноль")
						:format(name, track))
			end
		end
	end
end

-- А базовый цикл обязан сойтись сам с собой на стыке, иначе на каждом обороте
-- будет рывок.
for name, clip in pairs(Clips) do
	if clip.loop then
		for track, keys in pairs(clip.tracks) do
			local a, b = keys[1], keys[#keys]
			for i = 1, 3 do
				assert(math.abs(a[2][i] - b[2][i]) < 1e-6,
					("SharkAnimator: цикл %s/%s не замыкается"):format(name, track))
			end
		end
	end
end

------------------------------------------------------------ математика ------
local function ease(f)
	return f * f * (3 - 2 * f)
end

local function sample(track, t, rot, pos, w)
	local n = #track
	local k0, k1, f = track[n], track[n], 1
	if t <= track[1][1] then
		k0, k1, f = track[1], track[1], 0
	else
		for i = 1, n - 1 do
			if t <= track[i + 1][1] then
				k0, k1 = track[i], track[i + 1]
				f = ease((t - k0[1]) / math.max(k1[1] - k0[1], 1e-6))
				break
			end
		end
	end
	local r0, r1 = k0[2], k1[2]
	local p0, p1 = k0[3] or Z3, k1[3] or Z3
	for i = 1, 3 do
		rot[i] += (r0[i] + (r1[i] - r0[i]) * f) * w
		pos[i] += (p0[i] + (p1[i] - p0[i]) * f) * w
	end
end

local function clamp(name, rot)
	local lim = LIMITS[name]
	if not lim then return end
	for i = 1, 3 do
		if rot[i] > lim[i] then rot[i] = lim[i]
		elseif rot[i] < -lim[i] then rot[i] = -lim[i] end
	end
end

local function toCF(rot, pos)
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

------------------------------------------------------------ объект ----------
function Animator.new(motors)
	return setmetatable({
		motors = motors,
		base = nil, baseName = nil, baseT = 0,
		prev = nil, prevT = 0, fade = 0, fadeLen = 0,
		layers = {},
	}, Animator)
end

--[[ Смена цикла. Старый клип не выбрасывается, а доигрывается с падающим весом:
     иначе тело дёргается ровно в кадр переключения. ]]
function Animator:setBase(name: string, fade: number?)
	local clip = Clips[name]
	assert(clip and not clip.additive, "SharkAnimator: нет базового клипа " .. tostring(name))
	if self.baseName == name then return end
	self.prev, self.prevT = self.base, self.baseT
	self.base, self.baseName, self.baseT = clip, name, 0
	self.fadeLen = fade or 0.25
	self.fade = self.fadeLen
end

--[[ Разовый аддитивный слой. Каждый вызов — свой экземпляр, поэтому частые
     атаки складываются и затухают независимо. ]]
function Animator:fire(name: string, speed: number?)
	local clip = Clips[name]
	assert(clip and clip.additive, "SharkAnimator: нет аддитивного клипа " .. tostring(name))
	table.insert(self.layers, { clip = clip, t = 0, speed = speed or 1 })
	while #self.layers > 4 do
		table.remove(self.layers, 1)   -- больше этого слои только дерутся друг с другом
	end
end

function Animator:stop()
	self.base, self.baseName, self.prev = nil, nil, nil
	self.layers = {}
	for _, m in pairs(self.motors) do
		m.Transform = CFrame.new()
	end
end

function Animator:step(dt: number)
	if self.base then
		self.baseT += dt / self.base.length
		if self.baseT >= 1 then
			self.baseT = self.base.loop and (self.baseT % 1) or 1
		end
	end
	if self.prev then
		self.prevT += dt / self.prev.length
		if self.prevT >= 1 then
			self.prevT = self.prev.loop and (self.prevT % 1) or 1
		end
		self.fade -= dt
		if self.fade <= 0 then self.prev, self.fade = nil, 0 end
	end
	local blend = (self.prev and self.fadeLen > 0) and (self.fade / self.fadeLen) or 0

	for i = #self.layers, 1, -1 do
		local L = self.layers[i]
		L.t += dt * L.speed / L.clip.length
		if L.t >= 1 then table.remove(self.layers, i) end
	end

	for name, motor in pairs(self.motors) do
		local rot, pos = { 0, 0, 0 }, { 0, 0, 0 }
		if self.base and self.base.tracks[name] then
			sample(self.base.tracks[name], self.baseT, rot, pos, 1 - blend)
		end
		if self.prev and self.prev.tracks[name] then
			sample(self.prev.tracks[name], self.prevT, rot, pos, blend)
		end
		-- накладки ПРИБАВЛЯЮТСЯ к базе, а не подменяют её: атака посреди гребка
		-- добавляет рывок и сходит на нет, гребок при этом продолжается
		for _, L in ipairs(self.layers) do
			local tr = L.clip.tracks[name]
			if tr then sample(tr, L.t, rot, pos, 1) end
		end
		clamp(name, rot)
		motor.Transform = toCF(rot, pos)
	end
end

return Animator
