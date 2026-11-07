-- InfiniteOcean.server.lua
-- БЕСКОНЕЧНАЯ ВОДА: авторский Terrain-океан конечен, а плот плывёт вечно (8 студов/с).
-- Скрипт дозаполняет воду ЧАНКАМИ вокруг плота — на том же уровне, что авторская
-- (уровень берём рейкастом, как wakeSurfaceY в ShipCombat), и с тем же вокс-гридом
-- (чанк кратен 4 студам), поэтому швов между старой и новой водой нет.
--
-- Память: воксели не бесплатны (~250к на чанк), поэтому чанки, оставшиеся далеко
-- позади, вычищаются (Air). Вокруг СТАРТОВОЙ точки — защитная зона: там авторская
-- карта, её не трогаем ни заливкой, ни очисткой.
--
-- Все дистанции считаются по XZ. Острова/цистерны/корабли — модели, не террейн,
-- им заливка и очистка безразличны.

local RunService = game:GetService("RunService")
local Terrain = workspace.Terrain

local CHUNK          = 512   -- сторона чанка (кратно 4 — вокс-грид)
local RADIUS         = 4     -- заполняем (2R+1)² чанков вокруг плота → ±~2300 студов:
                             -- покрывает горизонт, спавн островов (1700-1900) и цистерн (850-950)
local DEPTH          = 60    -- толщина водяного слоя (дайверу и подводным визуалам хватает)
local CLEANUP_DIST   = 3200  -- чанк дальше этого от плота (и вне защитной зоны) → убираем
local PROTECT_RADIUS = 4096  -- вокруг старта ничего не заливаем и не чистим (авторская карта)
local TICK           = 1.5   -- период проверки
local FILLS_PER_TICK = 3     -- заливок за проверку (размазываем нагрузку, без фриза кадра)

local created = {}  -- [key "cx,cz"] = Vector2 центра чанка — только НАШИ чанки

local function raftPart()
	local raft = workspace:FindFirstChild("Raft")
	return raft and raft.PrimaryPart
end

-- уровень воды: рейкаст вниз сквозь воду у плота; фолбэк — Y самого плота
-- (BoatMovement держит его ровно на поверхности)
local function findWaterY()
	local rpp = raftPart()
	if not rpp then return nil end
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Raft") }
	local res = workspace:Raycast(rpp.Position + Vector3.new(0, 120, 0), Vector3.new(0, -500, 0), params)
	if res and res.Material == Enum.Material.Water then
		return res.Position.Y
	end
	return rpp.Position.Y - 0.5
end

local waterY
local startXZ -- стартовая точка (центр защитной зоны)

repeat task.wait(1) until raftPart()
waterY = findWaterY()
local rpp0 = raftPart()
startXZ = Vector2.new(rpp0.Position.X, rpp0.Position.Z)
workspace:SetAttribute("WaterY", waterY)   -- уровень воды наружу (ResourceDrift и др.)
print(("[InfiniteOcean] уровень воды Y=%.1f, защитная зона %d студов вокруг старта"):format(waterY, PROTECT_RADIUS))

local function chunkCenter(cx, cz)
	return Vector2.new(cx * CHUNK, cz * CHUNK)
end

local function fillChunk(cx, cz)
	local c = chunkCenter(cx, cz)
	-- FillBlock не проваливается на огромных координатах, но террейн ограничен
	-- (~±131к студов) — за границей просто пропускаем, pcall на всякий случай
	pcall(function()
		Terrain:FillBlock(
			CFrame.new(c.X, waterY - DEPTH / 2, c.Y),
			Vector3.new(CHUNK, DEPTH, CHUNK),
			Enum.Material.Water
		)
	end)
end

local function clearChunk(cx, cz)
	local c = chunkCenter(cx, cz)
	pcall(function()
		Terrain:FillBlock(
			CFrame.new(c.X, waterY - DEPTH / 2, c.Y),
			Vector3.new(CHUNK, DEPTH, CHUNK),
			Enum.Material.Air
		)
	end)
end

task.spawn(function()
	while true do
		task.wait(TICK)
		local rpp = raftPart()
		if rpp then
			local px, pz = rpp.Position.X, rpp.Position.Z
			local ccx = math.floor(px / CHUNK + 0.5)
			local ccz = math.floor(pz / CHUNK + 0.5)

			-- ── заливка вокруг плота (ближние чанки первыми) ──
			local todo = {}
			for dx = -RADIUS, RADIUS do
				for dz = -RADIUS, RADIUS do
					local cx, cz = ccx + dx, ccz + dz
					local k = cx .. "," .. cz
					if not created[k] then
						local c = chunkCenter(cx, cz)
						-- авторскую карту не трогаем: там вода уже есть
						if (c - startXZ).Magnitude > PROTECT_RADIUS then
							todo[#todo + 1] = { cx = cx, cz = cz, k = k, d = dx * dx + dz * dz }
						else
							created[k] = c -- помечаем, чтобы не проверять каждый тик
						end
					end
				end
			end
			--[[ ⚠️ МЕЖДУ ЗАЛИВКАМИ ЖДЁМ КАДР — ИНАЧЕ ПЛОТ ДЁРГАЕТСЯ.
			     Один FillBlock на чанк 512×512×60 — это около четверти миллиона
			     вокселей: синхронная работа на серверном кадре плюс репликация
			     вокселей всем клиентам. Три подряд в одном кадре давали кадр в
			     десятки миллисекунд, и приходились они ровно на движение: плот на
			     восьми студах в секунду пересекает границу чанка примерно раз в
			     минуту, а после рейса телепорт переносит его сразу через несколько
			     чанков, и в очередь падает до восьмидесяти штук.
			     Заливки те же три за тик, но теперь каждая в СВОЁМ кадре. ]]
			table.sort(todo, function(a, b) return a.d < b.d end)
			for i = 1, math.min(FILLS_PER_TICK, #todo) do
				local t = todo[i]
				fillChunk(t.cx, t.cz)
				created[t.k] = chunkCenter(t.cx, t.cz)
				RunService.Heartbeat:Wait()
			end

			--[[ ⚠️ ОЧИСТКА ТОЖЕ ПО ОДНОМУ ЧАНКУ ЗА ТИК.
			     Здесь была самая дорогая строка файла: цикл по всем созданным чанкам
			     без всякого лимита. Сколько чанков осталось позади — столько
			     FillBlock и уходило в ОДИН кадр. После рейса позади оказывается
			     сразу весь прежний квадрат, то есть десятки заливок подряд.
			     Вода позади игрока никому не нужна сию секунду, поэтому чистим
			     неспешно: самый дальний чанк за тик. ]]
			local pos = Vector2.new(px, pz)
			local farKey, farCentre, farDist = nil, nil, CLEANUP_DIST
			for k, c in pairs(created) do
				local d = (c - pos).Magnitude
				if d > farDist and (c - startXZ).Magnitude > PROTECT_RADIUS then
					farKey, farCentre, farDist = k, c, d
				end
			end
			if farKey then
				clearChunk(math.floor(farCentre.X / CHUNK + 0.5),
					math.floor(farCentre.Y / CHUNK + 0.5))
				created[farKey] = nil
			end
		end
	end
end)

print("[InfiniteOcean] loaded")
