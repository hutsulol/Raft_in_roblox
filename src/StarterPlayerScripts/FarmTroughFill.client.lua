local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	НАЛИТЬ ВОДУ В КОРЫТО ФЕРМЫ: кружка/бутылка с пресной водой в руках →
	ПКМ по корыту (на телефоне — тап по корыту, ПКМ там нет). Проверки и сам
	налив — на сервере (RaftFarmService, FarmRemotes.FillTrough); здесь только
	«на какое корыто смотрю».

	⚠️ ЛКМ КРУЖКИ НЕ ТРОГАЕМ: им она черпает воду из моря и очистителя
	(CupPurifier.client). Тап на телефоне — тот же Button1, поэтому там реагируем
	только с ПОЛНОЙ пресной кружкой: с ней ЛКМ сам по себе ничего не делает.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local C = require(ReplicatedStorage:WaitForChild("RaftFarmConfig"))
local remotes = ReplicatedStorage:WaitForChild("FarmRemotes", 30)
local fillEvent = remotes and remotes:WaitForChild("FillTrough", 10)

local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local function heldCup()
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if tool and tool:GetAttribute("CupState") ~= nil then return tool end
	return nil
end

local function troughUnder(screenPos)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local ray = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 120, params)
	local node = hit and hit.Instance
	while node and node ~= workspace do
		if node:IsA("Model") and C.TROUGH_NAMES[node.Name] then return node end
		node = node.Parent
	end
	return nil
end

local function tryFill(screenPos, requireFresh)
	if not fillEvent then return false end
	local cup = heldCup()
	if not cup then return false end
	if requireFresh and cup:GetAttribute("CupState") ~= "fresh" then return false end
	local trough = troughUnder(screenPos)
	if not trough then return false end
	fillEvent:FireServer(trough)
	return true
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		tryFill(Vector2.new(mouse.X, mouse.Y), false)
	elseif IS_TOUCH and input.UserInputType == Enum.UserInputType.Touch then
		tryFill(Vector2.new(input.Position.X, input.Position.Y), true)
	end
end)

print("[Ферма/корыто] ПКМ по корыту с кружкой — налить воду (на телефоне — тап)")
