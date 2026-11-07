--[[
	ПАССАЖИР НА ПИРАТСКОМ КАТЕРЕ И РЫБАЦКОЙ ЛОДКЕ.

	Судно движется телепортом якорных деталей: сервер переписывает CFrame каждый
	тик. Телепорт не сообщает скорости, поэтому стоящему на палубе физика ничего
	не передавала — палуба уезжала из-под ног, и игрока «сносило», хотя он просто
	стоял. Лечим как движущуюся платформу: сами переносим корень персонажа.

	⚠️ ДВИГАЕМСЯ С СУДНОМ В ЛОКСТЕП, А НЕ «ПЛАВНО САМИ ПО СЕБЕ».
	Была версия со сглаживанием по оценке скорости: персонаж ехал ровно, но судно
	под ним продолжало приходить рывками репликации — и теперь ТРЯСЛОСЬ ВСЁ, кроме
	игрока. Правильно наоборот: применять к персонажу тот же сдвиг, что пришёл
	судну. Тогда они дрожат ВМЕСТЕ, а камера следит за персонажем — и палуба
	относительно него стоит намертво.

	⚠️ ТОЛЬКО ГОРИЗОНТАЛЬ И РЫСКАНИЕ. Крен, дифферент и подъём на волне переносить
	нельзя: это качка вокруг центра судна, и на удалении от него она превращается
	в рывки вверх-вниз — ровно та «жёсткая тряска», с которой всё началось.
	Высоту держит обычная коллизия палубы.

	⚠️ ИМЕННО НА КЛИЕНТЕ. Персонажем владеет сам игрок (network ownership), и
	серверный перенос дрался бы с клиентской симуляцией — дёргало бы и персонажа,
	и камеру. Клиент переносит себя сам, репликация разносит это остальным.
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ⚠️ РЫБАЦКОЙ ЛОДКИ ЗДЕСЬ НЕТ НАМЕРЕННО. У неё своя, более честная схема: клиент
-- сам считает её ход каждый кадр (SkiffVisual + SkiffMotion) и там же переносит
-- игрока — в одном кадре с самой лодкой. Двойной перенос отсюда только дёргал бы.
local BOAT_NAMES = { PiratePatrolBoat = true, PirateCargoBoat = true, PirateRaiderBoat = true }
local REACH = 90        -- дальше этого от судна даже не проверяем
local FLOOR_RAY = -8    -- вниз от корня: ноги + запас на качку
local MAX_STEP = 12     -- сдвиг больше этого за кадр — телепорт судна, не везём

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

-- прошлое положение каждого судна; слабые ключи — утонувшее уходит само
local prev = setmetatable({}, { __mode = "k" })

local function yawOf(cf)
	local lv = cf.LookVector
	return math.atan2(-lv.X, -lv.Z)
end

--[[ ═══ ПЛАВНЫЙ ХОД КАТЕРА ═══
     Сервер двигает катер телепортом заякоренных деталей каждый кадр, а клиенту
     позы приходят пачками по сети, без сглаживания: катер (и экипаж на нём)
     ехал рывками. Здесь каждая новая поза корпуса пишется в буфер с серверным
     временем (атрибут PlaceT), и катер рисуется на DELAY позади — плавной
     интерполяцией между позами. Все детали (экипаж, груз) держим в той же
     позе относительно корпуса, что прислал сервер, — они едут вместе с ним.
     Незаякоренные (убитый матрос в рэгдолле) и таблички HP не трогаем. ]]
local CollectionService = game:GetService("CollectionService")
local DELAY = 0.12
local smooth = setmetatable({}, { __mode = "k" })   -- [boat] = { snaps, written, server }

local function sampleSnaps(snaps, t)
	local n = #snaps
	if n == 0 then return nil end
	if t <= snaps[1].t then return snaps[1].cf end
	for i = n, 2, -1 do
		local a, b = snaps[i - 1], snaps[i]
		if t >= a.t then
			if t >= b.t then return b.cf end
			return a.cf:Lerp(b.cf, (t - a.t) / math.max(b.t - a.t, 1e-3))
		end
	end
	return snaps[n].cf
end

--[[ ⚠️ ЭКИПАЖ: ПОЗУ ОТНОСИТЕЛЬНО КОРПУСА БЕРЁМ ТОЛЬКО ИЗ СОВПАВШИХ ПОЗ.
     Сервер двигает корпус и матросов в одном кадре, но по сети они могут
     прийти в разных пакетах. Если считать позу матроса от «чужой» позы корпуса,
     на ходу она скачет на скорость×кадр — матрос и его HP дрожали. Поэтому
     позу матроса относительно корпуса обновляем, только когда в этом же кадре
     пришла и новая поза корпуса (или корпус стоит). ]]
local function smoothBoats()
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, boat in ipairs(Workspace:GetChildren()) do
		local hull = boat:IsA("Model") and BOAT_NAMES[boat.Name] and boat.PrimaryPart
		if hull then
			local st = smooth[boat]
			if not st then
				st = { snaps = {}, written = setmetatable({}, { __mode = "k" }), rel = setmetatable({}, { __mode = "k" }), hullAt = 0 }
				smooth[boat] = st
			end
			-- корпус: новая поза с сервера?
			local hcur = hull.CFrame
			local hullNew = st.written[hull] ~= hcur
			if hullNew then
				st.hullServer = hcur
				st.hullAt = clock
				local last = st.snaps[#st.snaps]
				local t = boat:GetAttribute("PlaceT") or now
				if last and t <= last.t then t = last.t + 1 / 60 end
				table.insert(st.snaps, { t = t, cf = hcur })
				if #st.snaps > 12 then table.remove(st.snaps, 1) end
			end
			local hs = st.hullServer
			local cf = hs and sampleSnaps(st.snaps, now - DELAY)
			if cf then
				local hullIdle = clock - st.hullAt > 0.15
				local hsInv = hs:Inverse()
				local parts, cfs = { hull }, { cf }
				st.written[hull] = cf
				for _, p in ipairs(boat:GetDescendants()) do
					if p ~= hull and p:IsA("BasePart") and p.Anchored and not CollectionService:HasTag(p, "EnemyHPBoard") then
						local cur = p.CFrame
						if st.written[p] ~= cur and (hullNew or hullIdle or not st.rel[p]) then
							st.rel[p] = hsInv * cur
						end
						local rel = st.rel[p]
						if rel then
							local w = cf * rel
							table.insert(parts, p)
							table.insert(cfs, w)
							st.written[p] = w
						end
					end
				end
				Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
end

-- раньше всех в кадре: таблички HP, камера и перенос игрока видят уже плавную позу
RunService:BindToRenderStep("PirateBoatSmooth", Enum.RenderPriority.First.Value, smoothBoats)

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	local alive = hrp and hum and hum.Health > 0

	for _, boat in ipairs(Workspace:GetChildren()) do
		if boat:IsA("Model") and BOAT_NAMES[boat.Name] and boat.PrimaryPart then
			local cur = boat.PrimaryPart.CFrame
			local curYaw = yawOf(cur)
			local old = prev[boat]
			prev[boat] = { pos = cur.Position, yaw = curYaw }

			if old and alive then
				-- сдвиг судна за кадр: ТОЛЬКО горизонталь и рыскание
				local step = Vector3.new(cur.Position.X - old.pos.X, 0, cur.Position.Z - old.pos.Z)
				local spin = math.atan2(math.sin(curYaw - old.yaw), math.cos(curYaw - old.yaw))

				if (step.Magnitude > 1e-5 or math.abs(spin) > 1e-6)
					and step.Magnitude < MAX_STEP
					and (hrp.Position - cur.Position).Magnitude < REACH then

					-- честная проверка «стою ли я на этом судне»: луч вниз только по нему
					rayParams.FilterDescendantsInstances = { boat }
					if Workspace:Raycast(hrp.Position, Vector3.new(0, FLOOR_RAY, 0), rayParams) then
						-- поворот вокруг ВЕРТИКАЛЬНОЙ оси судна: и позиция по дуге,
						-- и разворот самого персонажа — ровно на тот же угол
						local pivot = Vector3.new(old.pos.X, hrp.Position.Y, old.pos.Z)
						local rot = CFrame.Angles(0, spin, 0)
						local newPos = pivot + rot:VectorToWorldSpace(hrp.Position - pivot) + step
						hrp.CFrame = CFrame.new(newPos) * rot * (hrp.CFrame - hrp.CFrame.Position)
					end
				end
			end
		end
	end
end)
