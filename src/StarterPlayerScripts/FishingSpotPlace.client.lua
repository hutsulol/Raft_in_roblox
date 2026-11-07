local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	РЫБАЦКОЕ МЕСТО — призрак установки. Тул Raft_fishing_spot в руках → станция
	прилипает к клетке пола под курсором (FishingSpotGrid.pose — ровно как
	поставит сервер), перед ней — подсвеченная клетка воды, где рыбак будет
	забрасывать удочку. Зелёное — можно, красное — нельзя (впереди пол, сеть,
	что-то ещё, или эта клетка — вода соседней станции). R — повернуть на
	четверть, ЛКМ — поставить (CupAction "placeFishingSpot", сервер —
	FishingSpotPlace.server).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local G          = require(ReplicatedStorage:WaitForChild("FishingSpotGrid"))
local AssetFind  = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck = require(ReplicatedStorage:WaitForChild("PlaceCheck"))
local GamepadInput = require(ReplicatedStorage:WaitForChild("GamepadInput"))
local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local OK_COLOR, BAD_COLOR = Color3.fromRGB(80, 255, 80), Color3.fromRGB(255, 80, 80)

local ghost, marker = nil, nil
local quarter = G.DEFAULT_QUARTER
local lastTile, lastValid, lastWhy = nil, false, nil
-- поза призрака относительно плота: курсор на воде — призрак едет с плотом, а не стоит в мире
local ghostRel = nil

local function destroyGhost()
	if ghost then ghost:Destroy() ghost = nil end
	if marker then marker:Destroy() marker = nil end
	lastTile, lastValid, lastWhy = nil, false, nil
end

local function createGhost()
	destroyGhost()
	local tpl = AssetFind.find(G.NAME)
	if not tpl then warn("[Рыбацкое место] шаблона " .. G.NAME .. " нет") return end
	ghost = tpl:Clone()
	ghostRel = nil
	ghost.Name = "FishingSpotGhost"
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.Transparency = math.max(d.Transparency, 0.45)
		end
	end
	ghost:SetAttribute("PlacementGhost", true)
	local hl = Instance.new("Highlight")
	hl.Name = "GhostHighlight"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.6
	hl.Parent = ghost
	ghost.Parent = workspace
	-- клетка воды впереди: туда рыбак забрасывает, строить нельзя
	marker = Instance.new("Part")
	marker.Name = "FishingSpotFront"
	marker.Anchored = true; marker.CanCollide = false; marker.CanQuery = false; marker.CanTouch = false
	marker.Size = Vector3.new(G.GRID * 0.94, 0.15, G.GRID * 0.94)
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.55
	marker.Parent = workspace
end

local function setValid(ok)
	lastValid = ok
	local color = ok and OK_COLOR or BAD_COLOR
	if ghost then
		local hl = ghost:FindFirstChild("GhostHighlight")
		if hl then hl.FillColor = color; hl.OutlineColor = color end
	end
	if marker then marker.Color = color end
end

local function update()
	if not ghost then return end
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) then setValid(false) return end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost, marker, player.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	local tile = res and res.Instance:IsDescendantOf(raft) and G.topTileOf(res.Instance, raft)
	if not (tile and G.isTile(tile, raft)) then
		lastTile, lastWhy = nil, "Наведись на клетку пола плота"
		if ghostRel then ghost:PivotTo(raft.PrimaryPart.CFrame * ghostRel) end
		marker.Transparency = 1
		setValid(false)
		return
	end
	lastTile = tile
	local front = G.pose(ghost, raft, tile, quarter)
	if not front then setValid(false) return end
	ghostRel = raft.PrimaryPart.CFrame:ToObjectSpace(ghost:GetPivot())
	marker.Transparency = 0.55
	marker.CFrame = CFrame.new(front + Vector3.new(0, 0.1, 0)) * G.flatFrame(raft).Rotation
	local why = nil
	if G.frontReserved(raft, G.tilePos(tile)) then
		why = "Эта клетка — вода соседней станции"
	else
		why = G.frontProblem(raft, front, { ghost, marker })
	end
	if not why then
		local by = PlaceCheck.blocked(ghost, raft)
		if by then why = "Сюда нельзя — место занято" end
	end
	lastWhy = why
	setValid(why == nil)
end

local equipped = false
local function onEquip(tool)
	if tool.Name ~= G.NAME then return end
	equipped = true
	quarter = G.DEFAULT_QUARTER
	createGhost()
end
local function onUnequip(tool)
	if tool.Name ~= G.NAME then return end
	equipped = false
	destroyGhost()
end
local function setupCharacter(char)
	char.ChildAdded:Connect(function(c) if c:IsA("Tool") then onEquip(c) end end)
	char.ChildRemoved:Connect(function(c) if c:IsA("Tool") then onUnequip(c) end end)
	for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") then onEquip(c) end end
end
if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()
	if equipped and ghost then update() end
end)

UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if equipped and GamepadInput.isKey(input, Enum.KeyCode.R) then
		quarter = (quarter + 1) % 4
	end
end)

GamepadInput.onPrimary(mouse, function()
	if not (equipped and ghost) then return end
	if not (lastValid and lastTile) then
		if lastWhy and typeof(_G.Notify) == "function" then
			pcall(_G.Notify, { type = "warn", icon = "no", title = "Сюда нельзя", body = lastWhy })
		end
		return
	end
	cupActionEvent:FireServer("placeFishingSpot", lastTile, quarter)
end)

print("[Рыбацкое место/клиент] готово: строго на клетку пола, впереди — вода (1×2)")
