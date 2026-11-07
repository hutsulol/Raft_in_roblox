--[[
	SheepClips — клипы овцы фермы, написаны таблицей (без публикации).

	Формат тот же, что у CowClips: { fps, loop, keys = { { t, p = { Деталь = 12 чисел } } } },
	но сдвиги здесь — В ДОЛЯХ ВЫСОТЫ ТУШИ (SheepAnimator умножает на Torso.Size.Y),
	так что клипы не зависят от масштаба импорта.

	Оси суставов (см. SheepRig): детали импортированы без поворота, значит
	Transform крутится в осях детали: X — вправо, Y — вверх, Z — к голове.
	  • нога вперёд (к голове) — ОТРИЦАТЕЛЬНЫЙ угол вокруг X;
	  • голова вниз — ПОЛОЖИТЕЛЬНЫЙ угол вокруг X.
	Редактируемый исходник — этот файл: клипы собираются из хелперов ниже.
]]

local function nums(cf, px, py, pz)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { px or 0, py or 0, pz or 0, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function A(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- поза: torsoY — подъём туши (доли высоты), head = {x, y}, legs = { FL, FR, RL, RR } (градусы вокруг X)
local function pose(o)
	o = o or {}
	local legs = o.legs or {}
	return {
		Torso = nums(A(o.torsoX or 0, o.torsoY or 0, o.torsoZ or 0), o.px or 0, o.dy or 0, o.pz or 0),
		Head  = nums(A(o.hx or 0, o.hy or 0, o.hz or 0)),
		LegFL = nums(A(legs[1] or 0, 0, 0)),
		LegFR = nums(A(legs[2] or 0, 0, 0)),
		LegRL = nums(A(legs[3] or 0, 0, 0)),
		LegRR = nums(A(legs[4] or 0, 0, 0)),
		Wool  = nums(CFrame.identity),
	}
end

local C = {}

-- Спокойное дыхание, уши/голова чуть шевелятся
C.Idle = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = 4 }) },
	{ t = 1.4, p = pose({ dy = 0.015, hx = 2, hy = 8 }) },
	{ t = 2.8, p = pose({ hx = 5, hy = -6 }) },
	{ t = 4.0, p = pose({ dy = 0.01, hx = 3 }) },
	{ t = 5.2, p = pose({ hx = 4 }) },
} }

-- Шаг: диагонали FL+RR / FR+RL, туша чуть покачивается
C.Walk = { fps = 30, loop = true, keys = {
	{ t = 0,    p = pose({ legs = { -22, 22, 22, -22 }, dy = 0.01, hx = 6, torsoZ = 1.5 }) },
	{ t = 0.25, p = pose({ legs = { 0, 0, 0, 0 }, dy = 0.025, hx = 3 }) },
	{ t = 0.5,  p = pose({ legs = { 22, -22, -22, 22 }, dy = 0.01, hx = 6, torsoZ = -1.5 }) },
	{ t = 0.75, p = pose({ legs = { 0, 0, 0, 0 }, dy = 0.025, hx = 3 }) },
	{ t = 1.0,  p = pose({ legs = { -22, 22, 22, -22 }, dy = 0.01, hx = 6, torsoZ = 1.5 }) },
} }

-- Пасётся: голова к земле, жуёт
C.Graze = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = 48, torsoX = 3 }) },
	{ t = 0.6, p = pose({ hx = 54, torsoX = 3 }) },
	{ t = 1.2, p = pose({ hx = 46, hy = 5, torsoX = 3 }) },
	{ t = 1.8, p = pose({ hx = 55, torsoX = 3 }) },
	{ t = 2.4, p = pose({ hx = 48, hy = -4, torsoX = 3 }) },
	{ t = 3.0, p = pose({ hx = 48, torsoX = 3 }) },
} }

-- Ест из кормушки: голова вперёд-вниз на высоте кормушки
C.Eat = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = 26 }) },
	{ t = 0.5, p = pose({ hx = 32, hy = 4 }) },
	{ t = 1.0, p = pose({ hx = 24 }) },
	{ t = 1.5, p = pose({ hx = 33, hy = -4 }) },
	{ t = 2.0, p = pose({ hx = 26 }) },
} }

-- Пьёт: морда к воде, редкие глотки
C.Drink = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = 40, torsoX = 2 }) },
	{ t = 0.8, p = pose({ hx = 44, torsoX = 2 }) },
	{ t = 1.6, p = pose({ hx = 38, torsoX = 2 }) },
	{ t = 2.4, p = pose({ hx = 40, torsoX = 2 }) },
} }

-- Лежит: ноги подобраны, туша опущена на высоту ноги (~0.45 высоты туши)
C.Rest = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ legs = { -88, -88, 88, 88 }, dy = -0.45, hx = 6 }) },
	{ t = 2.0, p = pose({ legs = { -88, -88, 88, 88 }, dy = -0.44, hx = 10, hy = 6 }) },
	{ t = 4.0, p = pose({ legs = { -88, -88, 88, 88 }, dy = -0.45, hx = 5, hy = -5 }) },
	{ t = 6.0, p = pose({ legs = { -88, -88, 88, 88 }, dy = -0.45, hx = 6 }) },
} }

-- Смотрит на фермера / отвечает на поглаживание: голова поднята и повёрнута
C.Look = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = -8, hy = 20 }) },
	{ t = 1.0, p = pose({ hx = -12, hy = 26 }) },
	{ t = 2.0, p = pose({ hx = -6, hy = 16 }) },
	{ t = 3.0, p = pose({ hx = -8, hy = 20 }) },
} }

-- Стрижка: стоит смирно, только дыхание
C.ShearIdle = { fps = 30, loop = true, keys = {
	{ t = 0,   p = pose({ hx = 10 }) },
	{ t = 1.5, p = pose({ hx = 12, dy = 0.01 }) },
	{ t = 3.0, p = pose({ hx = 10 }) },
} }

-- Вздрогнула: короткий шаг назад, голова вверх, без выхода за ограду
C.Startled = { fps = 30, loop = false, keys = {
	{ t = 0,    p = pose({ hx = 4 }) },
	{ t = 0.12, p = pose({ hx = -18, dy = 0.06, legs = { 18, 18, -12, -12 }, pz = -0.05 }) },
	{ t = 0.35, p = pose({ hx = -10, dy = 0.02, legs = { -8, -8, 6, 6 }, pz = -0.12 }) },
	{ t = 0.6,  p = pose({ hx = -4, legs = { 0, 0, 0, 0 }, pz = -0.08 }) },
	{ t = 0.9,  p = pose({ hx = 4 }) },
} }

return C
