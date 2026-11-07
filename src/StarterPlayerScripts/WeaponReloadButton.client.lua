--[[
	КНОПКА ПЕРЕЗАРЯДКИ ДЛЯ ТЕЛЕФОНА.

	На ПК перезарядка висит на R (RevolverInput, Pirate_Gun/FrontendScript), а на
	телефоне клавиши нет — револьвер и мушкет было НЕ перезарядить вовсе. Кнопка
	показывается только на тач-устройстве и только пока в руках стрелковый Tool
	(тот же признак, что у WeaponHUD: Configs.Ammo).

	Куда шлёт нажатие — по типу ствола:
	  • Revolver*  → RemoteEvent «RevolverReload» (его слушает RevolverServer);
	  • всё остальное → tool.Remotes.Reload (мушкет и прочие на общем ките).
	Клавишу R «нажать» из кода нельзя, поэтому дублируем адресатов, а не бинд.

	Иконка и место — те же, что у кнопки поворота при установке предметов
	(HudScale.TouchPlace, ICON_ROTATE): игрок уже знает этот круг по стройке.
	Белого кольца нет — владелец просил без него.
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local onTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
if not onTouch then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RELOAD_ICON = "rbxassetid://108864632671430"   -- та же, что ICON_ROTATE в HudScale
-- Кнопка стройки/выстрела на телефоне — 132 px; эта в полтора раза меньше.
local SIZE = math.floor(132 / 1.5 + 0.5)    -- 88
-- Там же, где кнопка стройки (BuildSlot 1,-184 / 1,-190, 132 px): центры совпадают,
-- место отмечено владельцем на телефоне.
local POS  = UDim2.new(1, -206, 1, -212)

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponReloadButton"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Enabled = false
gui.Parent = playerGui

local btn = Instance.new(RELOAD_ICON ~= "" and "ImageButton" or "TextButton")
btn.Name = "Reload"
btn.AnchorPoint = Vector2.new(1, 1)
btn.Position = POS
btn.Size = UDim2.fromOffset(SIZE, SIZE)
btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
-- как у кнопки прыжка Roblox: полупрозрачная, не перетягивает внимание
btn.BackgroundTransparency = 0.6
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
if btn:IsA("ImageButton") then
	btn.Image = RELOAD_ICON
	btn.ImageTransparency = 0.4
	btn.ScaleType = Enum.ScaleType.Fit
else
	btn.Text = "⟲"
	btn.TextColor3 = Color3.fromRGB(235, 240, 245)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
end
btn.Parent = gui
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(1, 0)
round.Parent = btn

--[[ НАШЕ: МЕСТО — НАД КНОПКОЙ ПРЫЖКА, В ПРАВОМ НИЖНЕМ УГЛУ.
     Фиксированные (1,−206, 1,−212) на телефоне давали кнопку почти в центре
     экрана, над плотом. Размер и место кнопки прыжка Roblox меняет от экрана,
     поэтому меряем её саму: центр перезарядки — на одной вертикали с прыжком,
     низ — на 14 px выше его верха. Кнопки прыжка нет — прижимаемся к углу. ]]
local GuiService = game:GetService("GuiService")
local function placeNearJump()
	local touchGui = playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 1 then
		-- TouchGui не игнорирует верхнюю вставку, наш ScreenGui — игнорирует
		local inset = (touchGui:IsA("ScreenGui") and not touchGui.IgnoreGuiInset) and GuiService:GetGuiInset().Y or 0
		-- место указал владелец: выше и правее прыжка, у правого края экрана
		local J = jump.AbsoluteSize.X
		local size = math.floor(math.clamp(J * 0.8, 56, SIZE))
		btn.Size = UDim2.fromOffset(size, size)
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		local screenW = gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.X or math.huge
		local x = math.min(jump.AbsolutePosition.X + J * 1.0, screenW - size / 2 - 8)
		local y = jump.AbsolutePosition.Y + inset - J * 1.75
		btn.Position = UDim2.fromOffset(x, y)
	else
		btn.AnchorPoint = Vector2.new(1, 1)
		btn.Position = UDim2.new(1, -24, 1, -150)
	end
end
gui:GetPropertyChangedSignal("Enabled"):Connect(function() if gui.Enabled then placeNearJump() end end)
task.spawn(function()
	while gui.Parent do
		if gui.Enabled then placeNearJump() end
		task.wait(1)
	end
end)

local revolverReload = ReplicatedStorage:FindFirstChild("RevolverReload")

local current = nil   -- Tool в руках со стрелковым китом

local function reloadNow()
	local tool = current
	if not (tool and tool.Parent) then return end
	if tool.Name:match("^Revolver") then
		revolverReload = revolverReload or ReplicatedStorage:FindFirstChild("RevolverReload")
		if revolverReload then revolverReload:FireServer() end
		return
	end
	local remotes = tool:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("Reload")
	if r and r:IsA("RemoteEvent") then r:FireServer() end
end
btn.Activated:Connect(reloadNow)

local function attach(tool)
	if not tool:IsA("Tool") then return end
	task.spawn(function()
		local configs = tool:FindFirstChild("Configs") or tool:WaitForChild("Configs", 4)
		local ammo = configs and (configs:FindFirstChild("Ammo") or configs:WaitForChild("Ammo", 4))
		if not ammo or tool.Parent ~= player.Character then return end
		current = tool
		gui.Enabled = true
		local uConn
		uConn = tool.Unequipped:Connect(function()
			if current == tool then
				current = nil
				gui.Enabled = false
			end
			if uConn then uConn:Disconnect() end
		end)
	end)
end

local function onCharacter(char)
	current = nil
	gui.Enabled = false
	char.ChildAdded:Connect(attach)
	for _, c in ipairs(char:GetChildren()) do attach(c) end
end
if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)
