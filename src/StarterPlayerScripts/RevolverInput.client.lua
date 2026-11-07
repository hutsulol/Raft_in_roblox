-- RevolverInput.client.lua  (StarterPlayerScripts)
-- Ввод для револьвера СНАРУЖИ тула: клик = выстрел (шлём направление серверу), R =
-- перезарядка. Отображение патронов/названия — общий WeaponHUD. Прицел (подъём ствола)
-- и отдачу навешивает WeaponFeel. Работает с любым Tool с именем "Revolver*".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
-- ⚠️ Геймпад: что считать кликом и клавишей — одно правило на все файлы (GamepadInput).
local GamepadInput = require(game:GetService("ReplicatedStorage"):WaitForChild("GamepadInput"))

local fireRemote   = ReplicatedStorage:WaitForChild("RevolverFire")
local reloadRemote = ReplicatedStorage:WaitForChild("RevolverReload")

local function isRevolver(t)
	return t ~= nil and t:IsA("Tool") and t.Name:match("^Revolver") ~= nil
end

local equippedRev = nil
local lastClick = 0

local function attach(tool)
	if not isRevolver(tool) then return end
	local handle = tool:FindFirstChild("Handle") or tool:WaitForChild("Handle", 5)
	equippedRev = tool

	local aConn = tool.Activated:Connect(function()
		if tick() - lastClick < 0.35 then return end -- лёгкий клиентский кулдаун
		lastClick = tick()
		local origin = (handle and handle:GetPivot().Position) or mouse.Origin.Position
		local dir = mouse.Hit.Position - origin
		if dir.Magnitude < 0.001 then return end
		fireRemote:FireServer(dir.Unit)
	end)

	local uConn
	uConn = tool.Unequipped:Connect(function()
		aConn:Disconnect()
		if uConn then uConn:Disconnect() end
		if equippedRev == tool then equippedRev = nil end
	end)
end

local function hookChar(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then attach(c) end
	end)
	for _, c in char:GetChildren() do
		if c:IsA("Tool") then attach(c) end
	end
end
if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)

-- перезарядка на R. ВЫСОКИЙ приоритет + Pass: другие стволы (напр. Pirate Gun) тоже
-- вешают R и «глотают» его — иначе, когда в руках револьвер, их бинд перехватывал бы R,
-- и перезарядка не срабатывала. Держим револьвер → перезаряжаем и глотаем; иначе —
-- пропускаем R дальше (пусть его получат другие).
ContextActionService:BindActionAtPriority("RevolverReloadGlobal", function(_, state)
	if state == Enum.UserInputState.Begin and equippedRev then
		reloadRemote:FireServer()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, 4000, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
