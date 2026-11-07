local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	УСТАНОВКА БЛОКА ФЕРМЫ 2×2 (призрак + клик). Устроена как ScarecrowPlace, но
	призрак не ездит свободно, а ПРИЛИПАЕТ К РЕШЁТКЕ ПЛОТА:

	  навёлся на клетку пола → блок займёт её и три соседние в ту сторону, в какую
	  четверть клетки смотрит прицел → зелёный, если все четыре клетки есть и
	  место свободно → ЛКМ (на телефоне — кнопка) ставит.

	Серверу уходит клетка и четверть (CupAction "placeFarmBlock"), позу он считает
	сам — FarmBlockPlace.server.

	⚠️ ПРИЗРАК — ТОЛЬКО ПЕРВЫЙ ВАРИАНТ. В модели лежат все стадии грядки и все
	заборы/калитки разом; спрятанное (прозрачность 1) из призрака выбрасываем,
	иначе подсветка рисует всю кашу. Детали переименованы: GateSwing и прочие
	ищут калитки по именам raft_farm_* и приняли бы призрак за настоящий блок.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local GamepadInput = require(ReplicatedStorage:WaitForChild("GamepadInput"))
local AssetFind    = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck   = require(ReplicatedStorage:WaitForChild("PlaceCheck"))

local IS_TOUCH = game:GetService("UserInputService").TouchEnabled
	and not game:GetService("UserInputService").MouseEnabled

-- механика постановки на телефоне — общая (см. ScarecrowPlace.client)
local TouchPlace do
	local function grab(name, field)
		local mod = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 5)
		if not mod then return nil end
		local ok, res = pcall(require, mod)
		if not ok then return nil end
		if field then res = (type(res) == "table") and res[field] or nil end
		return (type(res) == "table") and res or nil
	end
	TouchPlace = grab("HudScale", "Place") or grab("TouchPlace") or {
		isPhone = function() return false end,
		ray = function(m)
			local cam = workspace.CurrentCamera
			if not (cam and m) then return nil end
			return cam:ViewportPointToRay(m.X, m.Y)
		end,
		setHit = function() end,
		begin  = function() end,
		finish = function() end,
		active = function() return false end,
	}
end

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local TOOL_NAME = "Raft_farm_block"
local HUT_NAME  = "Raft_farmer_hut"   -- дом фермера: та же сетка 2×2, но только вплотную к ферме
local HALL_NAME = "IslandHall"        -- таверна: 2×2, где угодно, R поворачивает
local GRID = 10
local UserInputService = game:GetService("UserInputService")

local toolName = TOOL_NAME   -- какой из двух тулов сейчас в руках
local quarter = 0            -- поворот дома, четверти (R)

local onPlaceClick

local placing = false
local ghost = nil
local lastValid = false
local ghostRel = nil   -- поза призрака относительно плота (stickGhost)
local lastTarget = nil   -- { tile, dx, dz }
local lastClickAt = 0
local lastNoFarm = false

local function createGhost()
	if ghost then ghost:Destroy() end
	local template = AssetFind.find(toolName)
	if not template then
		warn("[Ферма/установка] шаблона " .. toolName .. " нет в ReplicatedStorage")
		return
	end
	ghost = template:Clone()
	ghostRel = nil
	ghost.Name = "FarmBlockGhost"
	-- дверь дома: запомнить до того, как маркеры (они невидимые) уйдут из призрака
	local bb0 = ghost:GetBoundingBox()
	local doorMarker = ghost:FindFirstChild("wp_door", true)
	local doorPos = doorMarker and doorMarker:IsA("BasePart") and doorMarker.Position
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then
			-- спрятанные варианты — вон, чтобы в призраке был ровно один
			if d.Name == "AssemblyOrigin" then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false   -- точка посадки домика с уровнями
			elseif d.Transparency >= 1 or d:GetAttribute("FarmHidden") == true then
				d:Destroy()
			else
				d.Name = d.Name .. "_ghost"
				d.Transparency = 0.5
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Anchored = true
			end
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("JointInstance")
			or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	local bbCF = ghost:GetBoundingBox()
	ghost.WorldPivot = CFrame.new(bbCF.Position)
	--[[ ⚠️ СТРЕЛКА «ДВЕРЬ ЗДЕСЬ». Подсветка заливает призрак целиком, и было не
	     понять, где у дома перёд: игрок крутил его R «дверью к ферме», а дом
	     вставал задом. Стрелка у крыльца показывает, куда смотрит дверь. ]]
	if doorPos then
		local out = Vector3.new(doorPos.X - bb0.Position.X, 0, doorPos.Z - bb0.Position.Z)
		if out.Magnitude > 0.1 then
			out = out.Unit
			local y = bbCF.Position.Y - (ghost:GetExtentsSize().Y * 0.5) + 0.4
			local base = Vector3.new(doorPos.X, y, doorPos.Z)
			local shaft = Instance.new("Part")
			shaft.Name = "DoorArrow"
			shaft.Size = Vector3.new(0.8, 0.3, 4)
			shaft.CFrame = CFrame.lookAt(base + out * 2, base + out * 3)
			local head = Instance.new("WedgePart")
			head.Name = "DoorArrowHead"
			head.Size = Vector3.new(2.4, 0.3, 1.8)
			head.CFrame = CFrame.lookAt(base + out * 4.9, base + out * 6) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			for _, p in ipairs({ shaft, head }) do
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
				p.Material = Enum.Material.Neon
				p.Color = Color3.fromRGB(255, 230, 60)
				p.Parent = ghost
			end
		end
	end
	ghost:SetAttribute("PlacementGhost", true)
	local hl = Instance.new("Highlight")
	hl.Name = "GhostHighlight"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = ghost
	-- сквозь заливку видно текстуру: где окна, где дверь
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0
	hl.Parent = ghost
	ghost.Parent = workspace

	TouchPlace.begin({
		confirm = function() if onPlaceClick then onPlaceClick() end end,
		-- поворачивается только дом: у блока фермы калитку двигает FarmFence
		rotate  = (toolName == HUT_NAME or toolName == HALL_NAME) and function() quarter = (quarter + 1) % 4 end or nil,
		ignore  = function() return ghost end,
	})
end

local function destroyGhost()
	if ghost then ghost:Destroy() ghost = nil end
	lastValid = false
	lastTarget = nil
	TouchPlace.finish()
end

local function setGhostColor(valid)
	lastValid = valid
	if not ghost then return end
	local color = valid and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	local hl = ghost:FindFirstChild("GhostHighlight")
	if hl then
		hl.FillColor = color
		hl.OutlineColor = color
	end
end

-- ─── решётка (держать равной FarmBlockPlace.server) ───
local function isTile(child, raft)
	if child == raft.PrimaryPart then return true end
	if child.Name == "Net_Part" then return false end
	return child.Name == "Raft_part" or child:GetAttribute("BuildType") == "raft"
end

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

-- центр блока фермы — по грядке (держать равным FarmBlockPlace.server)
local function blockCenter(m)
	local soil = m:FindFirstChild("raft_farm_soil", true)
	if soil and soil:IsA("BasePart") then return soil.Position end
	return (m:GetBoundingBox()).Position
end

local function nextToFarm(raft, flat, center)
	local c = flat:PointToObjectSpace(center)
	for _, m in ipairs(raft:GetChildren()) do
		if m:IsA("Model") and m.Name == TOOL_NAME then
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

--[[ Курсор ушёл с клеток (вода, мимо плота): призрак остаётся на последнем месте,
     но ОТНОСИТЕЛЬНО ПЛОТА — и краснеет. Раньше он стоял в мире, а плот уплывал, и
     призрак «ехал назад». ghostRel (объявлен выше) — поза в осях PrimaryPart плота. ]]
local function stickGhost(raft)
	if ghost and ghostRel then ghost:PivotTo(raft.PrimaryPart.CFrame * ghostRel) end
	setGhostColor(false)
end

local function updateGhost()
	if not ghost then return end
	lastTarget = nil
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then setGhostColor(false) return end

	local unitRay = TouchPlace.ray(mouse)
	if not unitRay then return stickGhost(raft) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, player.Character }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not (result and result.Instance and result.Instance:IsDescendantOf(raft)) then
		return stickGhost(raft)
	end
	local tile = topTileOf(result.Instance, raft)
	if not (tile and isTile(tile, raft)) then return stickGhost(raft) end
	local tp = tilePos(tile)
	if not tp then return stickGhost(raft) end

	local flat = flatFrame(raft)
	local h = flat:PointToObjectSpace(tp)
	local aim = flat:PointToObjectSpace(result.Position)
	local dx = (aim.X - h.X) >= 0 and 1 or -1
	local dz = (aim.Z - h.Z) >= 0 and 1 or -1

	-- все четыре клетки есть?
	local want = {
		Vector3.new(h.X, 0, h.Z), Vector3.new(h.X + dx * GRID, 0, h.Z),
		Vector3.new(h.X, 0, h.Z + dz * GRID), Vector3.new(h.X + dx * GRID, 0, h.Z + dz * GRID),
	}
	local allFound = true
	local found = {}
	for i, w in ipairs(want) do
		for _, child in ipairs(raft:GetChildren()) do
			if isTile(child, raft) then
				local p = tilePos(child)
				if p then
					local l = flat:PointToObjectSpace(p)
					if math.abs(l.X - w.X) < 3 and math.abs(l.Z - w.Z) < 3 and math.abs(l.Y - h.Y) < 2 then
						found[i] = child
						break
					end
				end
			end
		end
		if not found[i] then allFound = false end
	end

	local center = flat:PointToWorldSpace(Vector3.new(h.X + dx * GRID * 0.5, h.Y, h.Z + dz * GRID * 0.5))
	local top = result.Position.Y
	local rotQ = (flat - flat.Position) * CFrame.Angles(0, math.rad(90 * quarter), 0)
	local origin = ghost:FindFirstChild("AssemblyOrigin", true)
	if origin then
		-- как сервер (FarmBlockPlace.poseModel): точка посадки — на верх настила
		ghost:PivotTo(CFrame.new(center.X, top, center.Z) * rotQ * origin.CFrame.Rotation:Inverse()
			* CFrame.new(-origin.Position) * ghost:GetPivot())
	else
		local _, size = ghost:GetBoundingBox()
		ghost:PivotTo(CFrame.new(center.X, top + size.Y * 0.5, center.Z) * rotQ)
	end

	ghostRel = raft.PrimaryPart.CFrame:ToObjectSpace(ghost:GetPivot())
	local blocked = allFound and PlaceCheck.blocked(ghost, raft) ~= nil
	local nearFarm = toolName ~= HUT_NAME or nextToFarm(raft, flat, center)
	if allFound then lastTarget = { tile = tile, dx = dx, dz = dz } end
	-- место есть, но фермы рядом нет: клик всё равно уйдёт на сервер, и он скажет почему
	lastNoFarm = allFound and not blocked and not nearFarm
	setGhostColor(allFound and not blocked and nearFarm)
end

function onPlaceClick()
	if not (placing and ghost and lastTarget and (lastValid or lastNoFarm)) then return end
	if os.clock() - lastClickAt < 0.6 then return end
	cupActionEvent:FireServer("placeFarmBlock", lastTarget.tile, lastTarget.dx, lastTarget.dz, quarter)
	local folder = SoundService:FindFirstChild("Building") or SoundService:FindFirstChild("Building", true)
	local snd = folder and folder:FindFirstChild("Place_Block")
	if snd then snd:Play() end
	print(("[Ферма/установка] отправил: %s, четверть %d %d"):format(lastTarget.tile:GetFullName(), lastTarget.dx, lastTarget.dz))
	-- призрак НЕ убираем: поставил сервер — он заберёт тул, и призрак уйдёт вместе
	-- с ним; отказал — игрок видит призрак и может прицелиться заново
	lastClickAt = os.clock()
end

-- ─── тул в руках ───
local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and (child.Name == TOOL_NAME or child.Name == HUT_NAME or child.Name == HALL_NAME) then
			toolName = child.Name
			quarter = 0
			placing = true
			createGhost()
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == toolName then
			placing = false
			destroyGhost()
		end
	end)
	local held = char:FindFirstChild(TOOL_NAME) or char:FindFirstChild(HUT_NAME) or char:FindFirstChild(HALL_NAME)
	if held and held:IsA("Tool") then
		toolName = held.Name
		placing = true
		createGhost()
	end
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if placing and ghost then updateGhost() end
end)

UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if placing and (toolName == HUT_NAME or toolName == HALL_NAME) and GamepadInput.isKey(input, Enum.KeyCode.R) then
		quarter = (quarter + 1) % 4
	end
end)

-- на телефоне палец только целится, ставит кнопка (см. ScarecrowPlace.client)
GamepadInput.onPrimary(mouse, function()
	if IS_TOUCH and ghost then return end
	onPlaceClick()
end)
