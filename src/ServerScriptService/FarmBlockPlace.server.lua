--[[
	УСТАНОВКА БЛОКА ФЕРМЫ Raft_farm_block (2×2 клетки плота) И РОСТ ТРАВЫ.

	  тул-заготовка "Raft_farm_block" (пока выдаёт кнопка в настройках, _G.GiveFarmBlock)
	  → призрак ведёт FarmBlockPlace.client → сюда CupAction "placeFarmBlock", tile, dx, dz

	Клиент шлёт НЕ позу, а клетку, на которую навёлся (деталь пола плота), и
	четверть (dx, dz = ±1): блок займёт эту клетку и три соседние в сторону
	четверти. Позу считает сервер сам, по живой геометрии тайлов, — так блок
	всегда встаёт ровно в решётку, а подделать место нельзя.

	Ставится голая земля с забором кругом и калиткой (FarmBlock.init); со
	временем земля зарастает: bare → cover → grass. Время посадки — атрибут
	SoilPlantedAt (os.time), он сохраняется вместе с блоком (RaftSaveSystem 1в1),
	поэтому рост продолжается и после перезахода.
	Соседние блоки сами теряют забор между собой (FarmFence) — так ферма
	расширяется: ещё один блок рядом, и она становится одной большой.
]]

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetFind  = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck = require(ReplicatedStorage:WaitForChild("PlaceCheck"))
local FarmBlock  = require(ReplicatedStorage:WaitForChild("FarmBlock"))

local NAME     = "Raft_farm_block"
local HUT      = "Raft_farmer_hut"   -- дом фермера: тоже 2×2, ставится только вплотную к ферме
local HALL     = "IslandHall"        -- таверна (создание жителей): 2×2, ставится где угодно, к ферме не привязана
local LOG      = "[Ферма]"
local GRID     = 10
local MAX_DIST = 60
local COVER_AFTER = 7     -- сек: голая земля → первая поросль (ВРЕМЕННО для видео, было 180)
local GRASS_AFTER = 15    -- сек: → трава (ВРЕМЕННО для видео, было 420)

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

--[[ ⚠️ ШАБЛОН ПРИВОДИМ К ПЕРВОМУ ВАРИАНТУ СРАЗУ.
     В импортированной модели видно ВСЁ разом: три грядки, восемь заборов и
     восемь калиток друг в друге. Из шаблона рисуется иконка в хотбаре и строится
     призрак у клиента — там это была бы каша. init прячет лишнее (прозрачность
     1), клиент для призрака ещё и выбрасывает спрятанное. ]]
local template = AssetFind.find(NAME)
if template and template:IsA("Model") then
	FarmBlock.init(template)
else
	warn(LOG .. " шаблона Raft_farm_block нет в ReplicatedStorage — ставить нечего")
end

--[[ ДОМ ФЕРМЕРА. Маркеры wp_* и fx_lamp — служебные кубики: невидимые и без
     коллизии (RAFT_FARMER_HUT.md). Делаем это на шаблоне, чтобы и призрак, и
     иконка, и поставленный дом получили их уже спрятанными. ]]
local hutTemplate = AssetFind.find(HUT)
local function hideMarkers(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 3) == "wp_" or d.Name == "fx_lamp") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end
--[[ СТЕНЫ ДОМИКА С УРОВНЯМИ. У мешей нового домика (RaftBuildings_Upgrades)
     коллизия выключена, а включать её на целом доме нельзя: форма Hull закрыла
     бы дверной проём, а CollisionFidelity скриптом в игре не поменять. Поэтому —
     невидимые простые стены по периметру с проёмом под дверь (по маркерам
     модели: дверь raft_farmhut_gate, кровать у задней стены). Кладём в сам
     шаблон: их получат и новый дом, и дом из сохранения, и сварятся они вместе
     с домом — без лишней перестройки сборки плота. Призрак выбросит их сам
     (невидимые детали). Координаты — от AssemblyOrigin (центр 2×2, верх настила). ]]
local function addHutWalls(model)
	local origin = model:FindFirstChild("AssemblyOrigin")
	if not (origin and origin:IsA("BasePart")) or model:FindFirstChild("HutColliders") then return end
	local folder = Instance.new("Model")
	folder.Name = "HutColliders"
	local H, T = 8, 0.6                 -- высота и толщина стен
	local X0, X1 = -9.4, 9.4            -- боковые стены
	local ZF, ZB = -4.6, 9.3            -- передняя (с дверью) и задняя
	local DOOR0, DOOR1 = -6.1, -1.7     -- проём двери по X (створка 3,4 студа)
	local function wall(name, x0, x1, z0, z1)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(math.max(x1 - x0, T), H, math.max(z1 - z0, T))
		p.CFrame = origin.CFrame * CFrame.new((x0 + x1) / 2, H / 2, (z0 + z1) / 2)
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Parent = folder
	end
	wall("WallFrontLeft", X0, DOOR0, ZF - T / 2, ZF + T / 2)
	wall("WallFrontRight", DOOR1, X1, ZF - T / 2, ZF + T / 2)
	wall("WallBack", X0, X1, ZB - T / 2, ZB + T / 2)
	wall("WallLeft", X0 - T / 2, X0 + T / 2, ZF, ZB)
	wall("WallRight", X1 - T / 2, X1 + T / 2, ZF, ZB)
	folder.Parent = model
end

--[[ ТАВЕРНА ТВЁРДАЯ. В хендоффе коллизия выключена у всего здания — сквозь стены
     ходили. Включаем её у простых деталей каркаса OpenFrontShell (доски стен,
     косяки, перемычки — обычные Part, проём двери между ними свободен) и у
     алтаря. Меши (крыша, рама, крыльцо) — без коллизии: их форма Hull закрыла
     бы вход. Двери и интерьер — локальные копии на клиенте (IslandHallClient).
     Massless остаётся (weldToRaft): с массой каждая постройка проседала и
     тормозила плот. ]]
do
	local hall = AssetFind.find("IslandHall")
	if hall and hall:IsA("Model") then
		local n = 0
		for _, sub in ipairs({ "OpenFrontShell", "RecruitAltar" }) do
			local m = hall:FindFirstChild(sub)
			if m then
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") and not d.Name:find("Runner") and d.Name ~= "RecruitProgressPlaque" then
						d.CanCollide = true
						d.CanQuery = true
						n += 1
					end
				end
			end
		end
		print(LOG .. " таверна: твёрдых деталей стен и алтаря " .. n)
	end
end

if hutTemplate and hutTemplate:IsA("Model") then
	hideMarkers(hutTemplate)
	addHutWalls(hutTemplate)
else
	hutTemplate = nil
	warn(LOG .. " шаблона Raft_farmer_hut нет в ReplicatedStorage — дом фермера ставить нечего")
end

local function notify(player, title, body)
	if typeof(_G.NotifyPlayer) == "function" then
		_G.NotifyPlayer(player, { type = "warn", icon = "no", title = title, body = body })
	end
end

-- центр блока фермы: по грядке (она во всю клетку 2×2), иначе по габаритам
local function blockCenter(m)
	local soil = m:FindFirstChild("raft_farm_soil", true)
	if soil and soil:IsA("BasePart") then return soil.Position end
	return (m:GetBoundingBox()).Position
end

--[[ Дом стоит ВПЛОТНУЮ к ферме: какой-то блок фермы касается его стороной
     (центры в 20 студах по одной оси и не дальше клетки по другой). Держать
     равным FarmBlockPlace.client. ]]
local function nextToFarm(raft, flat, center)
	local c = flat:PointToObjectSpace(center)
	for _, m in ipairs(raft:GetChildren()) do
		if m:IsA("Model") and m.Name == NAME then
			local l = flat:PointToObjectSpace(blockCenter(m))
			local ax, az = math.abs(l.X - c.X), math.abs(l.Z - c.Z)
			if (math.abs(ax - 2 * GRID) < 1.5 and az <= GRID + 1)
				or (math.abs(az - 2 * GRID) < 1.5 and ax <= GRID + 1) then
				return true
			end
		end
	end
	return false
end

-- ─── решётка плота ───
local function isTile(child, raft)
	if child == raft.PrimaryPart then return true end
	if child.Name == "Net_Part" then return false end
	return child.Name == "Raft_part" or child:GetAttribute("BuildType") == "raft"
end

-- позиция тайла по живой геометрии (как в BuildingSystem.getFloorOffsets)
local function tilePos(tile)
	if tile:IsA("BasePart") then return tile.Position end
	if tile:IsA("Model") then
		if tile.PrimaryPart then return tile.PrimaryPart.Position end
		local best, vol = nil, -1
		for _, d in ipairs(tile:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > vol then best, vol = d, v end
			end
		end
		return best and best.Position
	end
	return nil
end

local function flatFrame(raft)
	local primary = raft.PrimaryPart
	local yaw = primary:GetAttribute("RestYaw")
	if not yaw then
		local _, y = primary.CFrame:ToEulerAnglesYXZ()
		yaw = y
	end
	return CFrame.new(primary.Position) * CFrame.Angles(0, yaw, 0)
end

local function topTileOf(inst, raft)
	local node = inst
	while node and node.Parent ~= raft do
		node = node.Parent
		if node == nil or node == workspace then return nil end
	end
	return node
end

--[[ Четыре тайла под блок: клетка hit и соседи в сторону (dx, dz).
     Возвращает список тайлов и центр блока в мире (на уровне центров тайлов)
     либо nil, если хоть одной клетки нет. ]]
local function findCells(raft, hit, dx, dz)
	local flat = flatFrame(raft)
	local hp = tilePos(hit)
	if not hp then return nil end
	local h = flat:PointToObjectSpace(hp)
	local want = {
		Vector3.new(h.X, h.Y, h.Z),
		Vector3.new(h.X + dx * GRID, h.Y, h.Z),
		Vector3.new(h.X, h.Y, h.Z + dz * GRID),
		Vector3.new(h.X + dx * GRID, h.Y, h.Z + dz * GRID),
	}
	local found = {}
	for i, w in ipairs(want) do
		for _, child in ipairs(raft:GetChildren()) do
			if isTile(child, raft) then
				local p = tilePos(child)
				if p then
					local l = flat:PointToObjectSpace(p)
					if math.abs(l.X - w.X) < 3 and math.abs(l.Z - w.Z) < 3 and math.abs(l.Y - w.Y) < 2 then
						found[i] = child
						break
					end
				end
			end
		end
		if not found[i] then return nil end
	end
	local centerLocal = Vector3.new(h.X + dx * GRID * 0.5, h.Y, h.Z + dz * GRID * 0.5)
	return found, flat:PointToWorldSpace(centerLocal), flat
end

--[[ Верх настила — по габаритам видимых деталей самих тайлов.
     ⚠️ НЕ ЛУЧОМ: луч с фильтром Include по моделям тайлов на сервере проходил
     мимо (детали пола без CanQuery / лучи по Include в сборке плота), и блок не
     ставился вообще — «луч не нашёл верх настила». Габариты считаются всегда. ]]
local function partTop(p)
	local cf, sz = p.CFrame, p.Size
	local up = Vector3.new(0, 1, 0)
	local half = math.abs(cf.RightVector:Dot(up)) * sz.X * 0.5
		+ math.abs(cf.UpVector:Dot(up)) * sz.Y * 0.5
		+ math.abs(cf.LookVector:Dot(up)) * sz.Z * 0.5
	return cf.Position.Y + half
end

local function deckTop(tiles)
	local best
	for _, t in ipairs(tiles) do
		local parts = t:IsA("BasePart") and { t } or t:GetDescendants()
		for _, p in ipairs(parts) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local y = partTop(p)
				if not best or y > best then best = y end
			end
		end
	end
	return best
end

-- поставить модель: низ габаритов — на верх настила, центр — в центр 2×2
local function poseModel(model, center, top, flat, quarter)
	-- домик с уровнями апгрейда: точка посадки AssemblyOrigin (центр 2×2, верх настила).
	-- По габаритам нельзя: в них входят спрятанные детали будущих уровней.
	local origin = model:FindFirstChild("AssemblyOrigin")
	if origin and origin:IsA("BasePart") then
		local rot0 = (flat - flat.Position) * CFrame.Angles(0, math.rad(90 * (quarter or 0)), 0)
		model:PivotTo(CFrame.new(center.X, top, center.Z) * rot0 * origin.CFrame.Rotation:Inverse()
			* CFrame.new(-origin.Position) * model:GetPivot())
		return
	end
	local bbCF, bbSize = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(bbCF.Position)
	local rot = (flat - flat.Position) * CFrame.Angles(0, math.rad(90 * (quarter or 0)), 0)
	model:PivotTo(CFrame.new(center.X, top + bbSize.Y * 0.5, center.Z) * rot)
end

local function weldToRaft(model, raft)
	local primary = raft.PrimaryPart
	local linVel, angVel = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, part in ipairs(parts) do part.Anchored = true end
	for _, part in ipairs(parts) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = primary
		weld.Parent = part
		part.Massless = true
	end
	for _, part in ipairs(parts) do part.Anchored = false end
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- скорость ещё раз после шага физики + удержать игроков (RaftShake)
end

cupActionEvent.OnServerEvent:Connect(function(player, action, hit, dx, dz, quarter)
	if action ~= "placeFarmBlock" then return end
	local function why(msg) warn(("%s %s: не поставлено — %s"):format(LOG, player.Name, msg)) end
	print(("%s %s просит поставить: клетка %s, четверть %s %s"):format(LOG, player.Name,
		typeof(hit) == "Instance" and hit:GetFullName() or tostring(hit), tostring(dx), tostring(dz)))
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (hrp and tool and (tool.Name == NAME or tool.Name == HUT or tool.Name == HALL)) then return why("в руках не блок фермы: " .. tostring(tool and tool.Name)) end
	local isHut = tool.Name == HUT
	local isHall = tool.Name == HALL
	local tpl = isHut and hutTemplate or isHall and AssetFind.find(HALL) or template
	quarter = ((isHut or isHall) and type(quarter) == "number") and (math.floor(quarter) % 4) or 0
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then return why("нет плота") end
	if typeof(hit) ~= "Instance" or not hit:IsDescendantOf(raft) then return why("клетка не на плоту") end
	if (dx ~= 1 and dx ~= -1) or (dz ~= 1 and dz ~= -1) then return why("плохая четверть") end
	if not tpl then return why("нет шаблона " .. tool.Name) end

	local tile = topTileOf(hit, raft)
	if not (tile and isTile(tile, raft)) then return why("навёлся не на пол: " .. tostring(tile)) end
	local tiles, center, flat = findCells(raft, tile, dx, dz)
	if not tiles then
		notify(player, "Нужно место 2×2", "Наведись на пол плота: нужны четыре свободные клетки")
		return why("не нашлось четырёх клеток пола")
	end
	if (center - hrp.Position).Magnitude > MAX_DIST then return why("далеко") end
	local top = deckTop(tiles)
	if not top then return why("у клеток нет видимых деталей") end

	if isHut and not nextToFarm(raft, flat, center) then
		notify(player, "Только рядом с фермой", "Дом фермера ставится вплотную к грядке-ферме")
		return why("дом не рядом с фермой")
	end

	local model = tpl:Clone()
	model.Name = tool.Name
	poseModel(model, center, top, flat, quarter)
	local blocker = PlaceCheck.blocked(model, raft)
	if blocker then
		PlaceCheck.refuseIfBlocked(model, raft, player)
		return why("место занято: " .. blocker:GetFullName())
	end

	if isHall then
		-- таверна: просто встаёт; сцену и создание жителей заводит IslandHallService
		hideMarkers(model)
		model.Parent = raft
		weldToRaft(model, raft)
	elseif isHut then
		hideMarkers(model)
		model.Parent = raft
		weldToRaft(model, raft)   -- фермера, корыто и табличку заведёт RaftFarmService
	else
		-- первый вариант: земля, забор кругом, калитка (атрибуты уже с шаблона)
		FarmBlock.init(model)
		FarmBlock.setSoil(model, "bare")
		model:SetAttribute("SoilPlantedAt", os.time())
		model.Parent = raft
		weldToRaft(model, raft)
		FarmBlock.apply(model)
	end

	tool:Destroy()
	if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
	-- у каждой постройки своё событие: сюжет торговца различает участок, домик и таверну
	local questEvent = isHall and "built:IslandHall" or isHut and "built:FarmerHut" or "built:FarmBlock"
	if typeof(_G.OnQuestEvent) == "function" then pcall(_G.OnQuestEvent, player, questEvent, 1) end
	if typeof(_G.MerchantStoryEvent) == "function" then pcall(_G.MerchantStoryEvent, questEvent, player) end
	print(("%s %s поставил %s 2×2 (верх настила Y=%.2f, центр клеток Y=%.2f)"):format(LOG, player.Name, isHall and "таверну" or isHut and "дом фермера" or "блок фермы", top, center.Y))
end)

-- ─── блоки из сохранения: вид привести к атрибутам ───
local function adopt(inst)
	if inst:IsA("Model") and inst.Name == NAME and inst ~= template then
		task.defer(function()
			if not inst:IsDescendantOf(workspace) then return end
			if inst:GetAttribute("PlacementGhost") then return end
			FarmBlock.init(inst)   -- у загруженного атрибуты уже есть — init их не трогает
			if inst:GetAttribute("SoilPlantedAt") == nil then inst:SetAttribute("SoilPlantedAt", os.time()) end
		end)
	end
end
for _, d in ipairs(workspace:GetDescendants()) do adopt(d) end
workspace.DescendantAdded:Connect(adopt)

-- ─── рост: голая земля → поросль → трава ───
task.spawn(function()
	while true do
		task.wait(1)
		local raft = workspace:FindFirstChild("Raft")
		if raft then
			local now = os.time()
			for _, m in ipairs(raft:GetChildren()) do
				if m:IsA("Model") and m.Name == NAME then
					local planted = m:GetAttribute("SoilPlantedAt")
					local soil = m:GetAttribute("Soil")
					if planted and soil ~= "none" then
						local age = now - planted
						local want = (age >= GRASS_AFTER and "grass") or (age >= COVER_AFTER and "cover") or "bare"
						if soil ~= want and not (soil == "grass" and want ~= "grass") then
							FarmBlock.setSoil(m, want)
						end
					end
				end
			end
		end
	end
end)

-- ─── выдача тула (кнопка в настройках) ───
local function giveTool(player, name)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool:SetAttribute("PreviewModel", name)   -- иконка — сама модель (шаблон уже в первом варианте)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	if typeof(_G.GiveToolOrDrop) == "function" then
		_G.GiveToolOrDrop(player, tool)
	else
		tool.Parent = player:FindFirstChildOfClass("Backpack")
	end
	if typeof(_G.SendInventory) == "function" then pcall(_G.SendInventory, player) end
	return true
end
_G.GiveFarmBlock = function(player) return giveTool(player, NAME) end
_G.GiveFarmerHut = function(player) return giveTool(player, HUT) end
_G.GiveIslandHall = function(player) return giveTool(player, HALL) end

print(LOG .. " готово: тул Raft_farm_block → навестись на пол → ферма 2×2, трава растёт сама")
