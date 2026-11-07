--[[
	ЭКИПИРОВКА: надеть / снять.

	Предмет лежит в инвентаре как обычный ресурс (одна штука), поэтому его можно
	таскать по слотам и хранить в сундуке. Надевание переносит его из инвентаря в
	слот: имя пишется в атрибут игрока, вещь из ReplicatedStorage надевается на
	персонажа. Снятие делает обратное.

	ВЕЩЬ ПЕРЕЖИВАЕТ СМЕРТЬ: атрибуты живут на игроке, а не на персонаже, поэтому
	после респавна аксессуары надеваются заново сами (CharacterAdded ниже). Иначе
	каждая смерть молча съедала бы экипировку.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentDefs = require(ReplicatedStorage:WaitForChild("EquipmentDefs"))

local ACCESSORY_TAG = "EquippedItem"   -- метка на надетом клоне, чтобы снять именно его

local remote = ReplicatedStorage:FindFirstChild("EquipmentAction")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EquipmentAction"
	remote.Parent = ReplicatedStorage
end

-- ── инвентарь ──
local function invCount(player, item)
	local inv = _G.GetInventory and _G.GetInventory(player)
	return inv and (inv[item] or 0) or 0
end

local function invTake(player, item)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv or (inv[item] or 0) <= 0 then return false end
	inv[item] = inv[item] - 1
	if _G.SendInventory then _G.SendInventory(player) end
	return true
end

local function invGive(player, item)
	if _G.AddResourceToInventory then
		-- через общий путь: если инвентарь полон, вещь ляжет под ноги, а не пропадёт
		_G.AddResourceToInventory(player, item, 1, nil)
		return true
	end
	local inv = _G.GetInventory and _G.GetInventory(player)
	if not inv then return false end
	inv[item] = (inv[item] or 0) + 1
	if _G.SendInventory then _G.SendInventory(player) end
	return true
end

-- ── поиск вещи в ReplicatedStorage ──
-- Имя сверяем БЕЗ учёта регистра, пробелов, подчёркиваний и дефисов: «DivingMask»,
-- «Diving Mask» и «diving_mask» — одно и то же. Точное имя ломалось от одной
-- заглавной буквы, и вещь молча «не надевалась».
local function normalize(s)
	return (s:lower():gsub("[%s_%-]", ""))
end

local function findTemplate(item)
	local exact = ReplicatedStorage:FindFirstChild(item)
		or ReplicatedStorage:FindFirstChild(item, true)
	if exact then return exact end

	local want = normalize(item)
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if (d:IsA("Accessory") or d:IsA("Model") or d:IsA("BasePart"))
			and normalize(d.Name) == want then
			return d
		end
	end
	return nil
end

-- Когда не нашли — не просто ругаемся, а показываем, что рядом лежит похожего:
-- почти всегда это опечатка в имени или вещь не в ReplicatedStorage.
local function reportMissing(item)
	local stem = normalize(item):sub(1, 5)
	local hints = {}
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if #hints < 5 and normalize(d.Name):find(stem, 1, true) then
			table.insert(hints, ("%s (%s)"):format(d:GetFullName(), d.ClassName))
		end
	end
	warn(("[Экипировка] в ReplicatedStorage нет «%s» — надеть нечего.%s"):format(item,
		#hints > 0 and (" Похожее рядом: " .. table.concat(hints, ", "))
			or " Ничего похожего не нашлось вообще."))
end

-- ── надеть на персонажа ──
local function removeFromCharacter(char, item)
	if not char then return end
	for _, d in ipairs(char:GetChildren()) do
		if d:GetAttribute(ACCESSORY_TAG) == item then d:Destroy() end
	end
end

local function wearOnCharacter(player, item)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return false end

	removeFromCharacter(char, item)

	local template = findTemplate(item)
	if not template then
		reportMissing(item)
		return false
	end

	local clone = template:Clone()
	clone:SetAttribute(ACCESSORY_TAG, item)
	if clone:IsA("Accessory") then
		-- AddAccessory сам приваривает по аттачменту (HatAttachment, FaceFrontAttachment…)
		hum:AddAccessory(clone)
		return true
	end

	warn(("[Экипировка] %s — не Accessory, а %s (%s). Надеваются только аксессуары: "
		.. "оберни модель в Accessory с деталью Handle и аттачментом внутри неё")
		:format(item, clone.ClassName, template:GetFullName()))
	clone:Destroy()
	return false
end

-- ── действия ──
local function unequip(player, slotKey, giveBack)
	local item = EquipmentDefs.worn(player, slotKey)
	if not item then return false end
	player:SetAttribute(EquipmentDefs.attr(slotKey), "")
	removeFromCharacter(player.Character, item)
	if giveBack ~= false then invGive(player, item) end
	return true
end

local function equip(player, item)
	local slotKey = EquipmentDefs.slotOf(item)
	if not slotKey then return false end
	if invCount(player, item) <= 0 then return false end

	-- В слоте уже что-то есть — возвращаем прежнее в инвентарь, как в RAFT.
	unequip(player, slotKey, true)

	if not invTake(player, item) then return false end
	player:SetAttribute(EquipmentDefs.attr(slotKey), item)

	-- ⚠️ ОТКАТ, ЕСЛИ НАДЕТЬ НЕ ВЫШЛО. Без него вещь уже списана из инвентаря, слот
	-- «занят», а на персонаже ничего нет — предмет просто исчезал. Именно так
	-- пропали первые маски: модели в ReplicatedStorage не нашлось.
	if not wearOnCharacter(player, item) then
		player:SetAttribute(EquipmentDefs.attr(slotKey), "")
		invGive(player, item)
		return false
	end
	return true
end

remote.OnServerEvent:Connect(function(player, action, arg)
	if action == "equip" then
		if type(arg) ~= "string" then return end
		equip(player, arg)
	elseif action == "unequip" then
		if type(arg) ~= "string" then return end
		unequip(player, arg, true)
	end
end)

-- ── жизненный цикл ──
local function onCharacter(player, char)
	-- Персонаж собирается не мгновенно: без ожидания Humanoid аксессуар вешать не на что.
	if not char:FindFirstChildWhichIsA("Humanoid") then
		char:WaitForChild("Humanoid", 10)
	end
	task.wait(0.2)
	for _, slot in ipairs(EquipmentDefs.SLOTS) do
		local item = EquipmentDefs.worn(player, slot.key)
		if item then wearOnCharacter(player, item) end
	end
end

local function onPlayer(player)
	-- Пустые слоты заводим сразу: интерфейс читает атрибуты и не должен гадать,
	-- «слот пуст» или «атрибут ещё не приехал».
	for _, slot in ipairs(EquipmentDefs.SLOTS) do
		if player:GetAttribute(EquipmentDefs.attr(slot.key)) == nil then
			player:SetAttribute(EquipmentDefs.attr(slot.key), "")
		end
	end
	if player.Character then task.spawn(onCharacter, player, player.Character) end
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)

print("[Экипировка] готова: слотов " .. #EquipmentDefs.SLOTS)

-- СЕЙВ: что надето — по слотам; предметы уже сняты с инвентаря при надевании
_G.EquipmentExport = function(player)
	local out = {}
	for _, slot in ipairs(EquipmentDefs.SLOTS) do
		local item = EquipmentDefs.worn(player, slot.key)
		if item then out[slot.key] = item end
	end
	return out
end
_G.EquipmentRestore = function(player, map)
	if type(map) ~= "table" then return end
	for key, item in pairs(map) do
		if type(item) == "string" and item ~= "" then
			player:SetAttribute(EquipmentDefs.attr(key), item)
			pcall(wearOnCharacter, player, item)
		end
	end
end
