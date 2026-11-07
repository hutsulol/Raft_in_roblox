--[[
	МАСКА ДЛЯ НЫРЯНИЯ: заряд и поломка.

	Что маска даёт, пока надета:
	  • видно под водой — затемнение и размытие не включаются (UnderwaterPostFX);
	  • радиация океана не действует (ToxicWater);
	  • свой запас воздуха: 60 секунд под водой, полное восстановление за 8
	    на поверхности (DiverAir).

	ЗАРЯД ТРАТИТСЯ ТОЛЬКО ПОД ВОДОЙ. «Используется» — это когда маска делает свою
	работу; висеть на лице на палубе она может сколько угодно. 300 секунд ныряния —
	и она ломается прямо на лице: слот пустеет, вещь пропадает совсем, в инвентарь
	не возвращается.

	Остаток заряда живёт в атрибуте игрока и НЕ обнуляется при снятии: иначе маску
	достаточно было бы снять и надеть заново, чтобы обнулить износ.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentDefs = require(ReplicatedStorage:WaitForChild("EquipmentDefs"))
local MASK = EquipmentDefs.MASK

local Terrain = workspace.Terrain
local TICK  = 0.25
local VOXEL = 4

-- Тем же ремоутом ломается инструмент — карточка «сломалось» у игрока уже есть.
local brokenEvent = ReplicatedStorage:FindFirstChild("ToolBroken")
if not brokenEvent then
	brokenEvent = Instance.new("RemoteEvent")
	brokenEvent.Name = "ToolBroken"
	brokenEvent.Parent = ReplicatedStorage
end

-- воксельный тест воды — так же, как в DiverAir и UnderwaterPostFX
local function isPointInWater(pos)
	local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2))
		:ExpandToGrid(VOXEL)
	local ok, materials, occupancies = pcall(function()
		return Terrain:ReadVoxels(region, VOXEL)
	end)
	if not ok or not materials then return false end
	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = (occupancies[1] and occupancies[1][1] and occupancies[1][1][1]) or 0
	return material == Enum.Material.Water and occupancy > 0.5
end

local function headPos(char)
	local head = char:FindFirstChild("Head")
	if head then return head.Position end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position + Vector3.new(0, 1.5, 0)) or nil
end

local function charge(player)
	local v = player:GetAttribute(MASK.attr)
	return (type(v) == "number") and v or MASK.charge
end

-- Наружу: этим пользуются воздух дайвера и радиация океана.
_G.HasDivingMask = function(player)
	return player ~= nil and EquipmentDefs.hasMask(player) and charge(player) > 0
end

local function breakMask(player)
	player:SetAttribute(EquipmentDefs.attr(MASK.slot), "")
	player:SetAttribute(MASK.attr, MASK.charge)   -- следующая маска придёт целой

	-- снять с лица: аксессуар помечен при надевании (см. EquipmentSystem)
	local char = player.Character
	if char then
		for _, d in ipairs(char:GetChildren()) do
			if d:GetAttribute("EquippedItem") == MASK.item then d:Destroy() end
		end
	end

	brokenEvent:FireClient(player, MASK.item)
	print(("[Маска] %s: маска износилась и рассыпалась"):format(player.Name))
end

local warned = {}   -- [player] = true, чтобы предупредить один раз за маску

while true do
	task.wait(TICK)
	for _, player in ipairs(Players:GetPlayers()) do
		if not EquipmentDefs.hasMask(player) then
			warned[player] = nil
		else
			local char = player.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			local pos = char and headPos(char)
			local underwater = (hum and hum.Health > 0 and pos) and isPointInWater(pos) or false

			if underwater then
				local left = math.max(0, charge(player) - TICK)
				player:SetAttribute(MASK.attr, left)

				if left <= 0 then
					breakMask(player)
					warned[player] = nil
				elseif left <= MASK.warnAt and not warned[player] then
					warned[player] = true
					print(("[Маска] %s: осталось %d с"):format(player.Name, math.ceil(left)))
				end
			end
		end
	end
end
