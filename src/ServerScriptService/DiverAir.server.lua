-- DiverAir.server.lua
-- Механика воздуха ПОД МАСКОЙ. Работает только у игрока, надевшего маску для
-- ныряния (_G.HasDivingMask): океан отравлен, и другого способа дышать под водой
-- нет — ни класс, ни что-либо ещё запаса воздуха не дают.
--   • пока голова игрока под водой — тратится воздух маски;
--     кончился — наносится урон (захлёбывается);
--   • на поверхности воздух восстанавливается;
--   • значения пишутся в Characteristics.AirMax/AirCurrent (полоса воздуха
--     в UIManager), а атрибут DiverAirActive показывает полосу только пока
--     дайвер под водой.
-- Радиацию океана дайверу отключает ToxicWater.server.lua (1 ур.), так что
-- под водой единственный источник урона — это захлёбывание здесь.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Terrain = workspace.Terrain

local TICK           = 0.25  -- шаг цикла (сек)
local VOXEL          = 4     -- размер вокселя террейна
local REGEN_MULT     = 3     -- во сколько раз воздух восстанавливается быстрее траты
local DROWN_FRACTION = 0.08  -- доля MaxHealth урона в секунду, когда воздух кончился
-- ⚠️ Запасы по уровням класса (20 и 50 секунд) убраны вместе с самой выдачей
-- воздуха за класс: единственный источник воздуха — маска, см. цикл ниже.

-- МАСКА ДЛЯ НЫРЯНИЯ даёт свой воздух ЛЮБОМУ игроку, даже если класс дайвера не
-- выбран. Числа — в EquipmentDefs.MASK, чтобы не разъезжались с самой маской.
local EquipmentDefs = require(ReplicatedStorage:WaitForChild("EquipmentDefs"))
local MASK = EquipmentDefs.MASK

local air = {} -- [player] = оставшиеся секунды воздуха

-- воксельный тест воды в точке (как в UnderwaterPostFX, но на сервере)
local function isPointInWater(pos)
	local region = Region3.new(
		pos - Vector3.new(2, 2, 2),
		pos + Vector3.new(2, 2, 2)
	):ExpandToGrid(VOXEL)
	local ok, materials, occupancies = pcall(function()
		return Terrain:ReadVoxels(region, VOXEL)
	end)
	if not ok or not materials then return false end
	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = (occupancies[1] and occupancies[1][1] and occupancies[1][1][1]) or 0
	return material == Enum.Material.Water and occupancy > 0.5
end

-- точка головы (там, где реально проверяем «под водой»)
local function headPos(char)
	local head = char:FindFirstChild("Head")
	if head then return head.Position end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.Position + Vector3.new(0, 1.5, 0) end
	return nil
end

local function airValues(player)
	local folder = player:FindFirstChild("Characteristics")
	if not folder then return nil, nil end
	return folder:FindFirstChild("AirMax"), folder:FindFirstChild("AirCurrent")
end

-- ставим значение только при изменении (лишняя репликация не нужна)
local function setIfChanged(valueObj, v)
	if valueObj and valueObj.Value ~= v then valueObj.Value = v end
end
local function setAttrIfChanged(player, name, v)
	if player:GetAttribute(name) ~= v then player:SetAttribute(name, v) end
end

Players.PlayerRemoving:Connect(function(player)
	air[player] = nil
end)

while true do
	task.wait(TICK)
	for _, player in ipairs(Players:GetPlayers()) do
		local maskOn = (_G.HasDivingMask ~= nil) and _G.HasDivingMask(player) or false
		local aMax, aCur = airValues(player)

		--[[ ⚠️ ВОЗДУХ ДАЁТ ТОЛЬКО МАСКА. КЛАСС ДАЙВЕРА — БОЛЬШЕ НЕТ.
		     Океан отравлен, и плавать в нём можно единственным способом — надев
		     маску. Пока запас воздуха выдавался ещё и за выбранный класс, игрок
		     без маски спокойно нырял на 20–50 секунд: у него была и полоса
		     воздуха, и (через ToxicWater) полный иммунитет к отраве. Это ровно
		     то, чего быть не должно.
		     Класс при этом не обесценен: с маской он по-прежнему её носит, а
		     сама маска остаётся единственным пропуском под воду. ]]
		if not maskOn then
			-- без маски воздуха нет вовсе — полосу прячем
			air[player] = nil
			setIfChanged(aMax, 0)
			setIfChanged(aCur, 0)
			setAttrIfChanged(player, "DiverAirActive", false)
		else
			-- запас и скорость восстановления — целиком от маски
			local maxAir = MASK.air
			local regen = MASK.air / MASK.refill
			local char = player.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			local cur = air[player]
			if cur == nil then cur = maxAir end
			cur = math.min(cur, maxAir)

			local pos = char and headPos(char)
			-- ⚠️ СПЯЩИЙ В КРОВАТИ НЕ ЗАХЛЁБЫВАЕТСЯ.
			-- Лежащий человек держит голову у самой палубы, а плот сидит по уровень
			-- воды: воксель под головой оказывается водой, и запас воздуха тратился
			-- всю ночь, добивая игрока во сне. Та же защита стоит в ToxicWater.
			local asleep = char and char:GetAttribute("Sleeping") == true
			local submerged = (not asleep) and (hum ~= nil and hum.Health > 0 and pos ~= nil)
				and isPointInWater(pos) or false

			if submerged then
				cur = cur - TICK
				if cur <= 0 then
					cur = 0
					if hum then hum:TakeDamage(hum.MaxHealth * DROWN_FRACTION * TICK) end
				end
			else
				cur = math.min(maxAir, cur + TICK * regen)
			end
			air[player] = cur

			setIfChanged(aMax, maxAir)
			setIfChanged(aCur, math.ceil(cur))
			setAttrIfChanged(player, "DiverAirActive", submerged)
		end
	end
end
