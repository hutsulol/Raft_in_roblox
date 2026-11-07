local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[ GamepadAdapter — ПРИЦЕЛ, КУРСОР В ЦЕНТРЕ И КНОПКИ, У КОТОРЫХ НЕТ СВОЕГО ФАЙЛА.

     Правила (что считать кликом, чем заменить E/Q/R) живут в GamepadInput;
     здесь — то, что должно происходить ГЛОБАЛЬНО, пока в руках контроллер:

       1. Курсор заперт в центре экрана. Все лучи «от мыши» (mouse.Hit,
          mouse.Target, GetMouseLocation) теперь смотрят в центр — и топор,
          вылов, кирка, лопата, постановка целятся туда, куда повёрнута камера.
          Правый стик крутит камеру штатно.
       2. Прицел: маленькое кольцо в центре, чтобы было видно, куда попадёт удар.
       3. L1 / R1 листают слоты хотбара, крестовина ↑/↓ крутит лебёдку якоря,
          R2 в режиме стройки ставит доску (на компьютере это ЛКМ).
       4. Открылось меню — выделяем в нём первую кнопку: со стика и крестовины
          Roblox сам ходит по кнопкам, A нажимает. Без стартового выделения
          игрок жмёт крестовину в пустоту.

     ⚠️ УСТУПАЕМ РАЗБЛОКИРОВЩИКУ КУРСОРА.
     ModalUIUnlocker каждый кадр ставит MouseBehavior = Default, пока открыто
     хоть одно модальное окно. Если запирать курсор в те же кадры, два скрипта
     перетягивали бы одно свойство. Поэтому смотрим на его же признак — кнопки
     __ModalUnlock с Modal = true — и, пока окно открыто, не трогаем курсор. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GamepadInput = require(ReplicatedStorage:WaitForChild("GamepadInput"))

-- ── прицел ──
local gui = Instance.new("ScreenGui")
gui.Name = "GamepadCrosshair"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromOffset(18, 18)
ring.BackgroundTransparency = 1
ring.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = ring
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.new(1, 1, 1)
stroke.Transparency = 0.15
stroke.Parent = ring
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(3, 3)
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.BorderSizePixel = 0
dot.Parent = ring
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot

-- ── модальные окна: тот же признак, что у ModalUIUnlocker ──
local function anyModalOpen()
	for _, sg in ipairs(playerGui:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled then
			local unlock = sg:FindFirstChild("__ModalUnlock")
			if unlock and unlock:IsA("GuiButton") and unlock.Modal then return sg end
		end
	end
	return nil
end

-- первая видимая кнопка в окне — для стартового выделения
local function firstButtonIn(sg)
	for _, d in ipairs(sg:GetDescendants()) do
		if d:IsA("GuiButton") and d.Selectable and d.Visible
			and d.AbsoluteSize.X > 4 and d.AbsoluteSize.Y > 4
			and d.Name ~= "__ModalUnlock" then
			local ok = true
			local p = d.Parent
			while p and p ~= sg do
				if p:IsA("GuiObject") and not p.Visible then ok = false break end
				p = p.Parent
			end
			if ok then return d end
		end
	end
	return nil
end

-- ── режим: курсор и прицел ──
local padMode = false
local selectedFor = nil   -- окно, в котором мы уже поставили выделение

RunService.RenderStepped:Connect(function()
	local active = GamepadInput.active()
	if active ~= padMode then
		padMode = active
		gui.Enabled = active
		if not active then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			GuiService.SelectedObject = nil
			selectedFor = nil
		end
	end
	if not padMode then return end

	local modal = anyModalOpen()
	if modal then
		-- курсор отдаём разблокировщику, прицел прячем: в меню он лишний
		gui.Enabled = false
		if selectedFor ~= modal then
			selectedFor = modal
			local b = firstButtonIn(modal)
			if b then GuiService.SelectedObject = b end
		end
		return
	end
	selectedFor = nil
	if GuiService.SelectedObject then GuiService.SelectedObject = nil end
	gui.Enabled = true
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end)

-- ── хотбар: L1 / R1 ──
local HOTBAR_SLOTS = 8
local lastSlot = 1

-- слот, в котором лежит надетый сейчас тул; нет тула — последний выбранный
local function currentSlot()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local data = _G.InventorySlotData
	if tool and type(data) == "table" then
		for i = 1, HOTBAR_SLOTS do
			local s = data[i]
			if type(s) == "table" and (s.toolInst == tool or s.toolName == tool.Name) then
				return i
			end
		end
	end
	return lastSlot
end

--[[ Куда шагнуть от текущего слота. Читает InventoryUI: подставляет результат
     вместо номера клавиши в свою ветку «1…8», так что надевание идёт тем же
     кодом, что и с клавиатуры. Пустые слоты пропускаем — иначе половина
     нажатий уходила бы в ничего. ]]
_G.GamepadHotbarStep = function(keyCode)
	local dir
	if keyCode == Enum.KeyCode.ButtonR1 then dir = 1
	elseif keyCode == Enum.KeyCode.ButtonL1 then dir = -1
	else return nil end
	local data = _G.InventorySlotData
	local from = currentSlot()
	for step = 1, HOTBAR_SLOTS do
		local i = ((from - 1 + dir * step) % HOTBAR_SLOTS) + 1
		local s = type(data) == "table" and data[i]
		if type(s) == "table" and (s.toolInst or s.toolName or s.name) then
			lastSlot = i
			return i
		end
	end
	return nil
end

-- ── стройка: R2 = ЛКМ, лебёдка: крестовина ──
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not GamepadInput.isGamepadType(input.UserInputType) then return end

	if input.KeyCode == Enum.KeyCode.ButtonR2 then
		-- на компьютере ЛКМ ставит доску сразу; BuildPlaceNow сам проверяет,
		-- идёт ли стройка, так что вне режима это пустой вызов
		if typeof(_G.BuildPlaceNow) == "function" then
			_G.BuildAim = nil
			_G.BuildPlaceNow()
		end
	elseif input.KeyCode == Enum.KeyCode.DPadUp then
		if typeof(_G.AnchorHudStep) == "function" then _G.AnchorHudStep(-1) end
	elseif input.KeyCode == Enum.KeyCode.DPadDown then
		if typeof(_G.AnchorHudStep) == "function" then _G.AnchorHudStep(1) end
	end
end)

print("[Геймпад] адаптер готов: прицел в центре, R2 = удар/поставить, X = взять, Y = повернуть, B = назад, L1/R1 = слоты")
