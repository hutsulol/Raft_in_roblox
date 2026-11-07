-- WeaponPickup.client.lua
-- Подбор поставленного оружия (пушки/ПВО/пулемёты) обратно в инвентарь ЗА ПИРАТОВ.
-- Подходишь близко к постройке → в левом-верхнем углу (там же, где кнопка факела) появляется
-- её иконка: СВЕРХУ цена, СНИЗУ «Подобрать». Цена = 10 + 20 за каждый прошлый подбор
-- (1й=10, 2й=30, 3й=50). Если пиратов не хватает — на месте цены красная «Не хватает».
-- Клик → сервер (CanonSystem) списывает валюту, убирает постройку и выдаёт Tool.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

local PICKUP_RADIUS = 13
local COIN_ICON     = "rbxassetid://93617165412571" -- значок пиратской валюты

-- иконки КНОПКИ подбора по типу оружия (отдельные от инвентарных)
local WEAPON_ICONS = {
	Cannon           = "rbxassetid://104845834066414",
	Deffender        = "rbxassetid://93920358609831",
	MagmaCannon      = "rbxassetid://134521395115474",
	Big_Magma_Cannon = "rbxassetid://90320830647969",
	Pulemet_lvl_1    = "rbxassetid://133987945170380",
	Pulemet_lvl_2    = "rbxassetid://110274103623366",
}
-- пока держим размещаемый тул — идёт постройка (CanonPlacer), кнопку подбора прячем
local PLACEABLE_TOOLS = {}
for k in pairs(WEAPON_ICONS) do PLACEABLE_TOOLS[k] = true end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- имя модели на плоту → тип оружия
local function weaponTypeOf(model)
	if WEAPON_ICONS[model.Name] then return model.Name end
	if model.Name:sub(1, 10) == "Deffender_" then return "Deffender" end
	return nil
end

-- ══════════ UI: иконка + цена сверху + «Подобрать» снизу ══════════
local gui = new("ScreenGui", { Name = "WeaponPickupButton", ResetOnSpawn = false, DisplayOrder = 12, Enabled = false }, playerGui)
local holder = new("Frame", {
	Position = UDim2.new(0.18, 0, 0.1, 0), Size = UDim2.fromOffset(92, 116), BackgroundTransparency = 1,
}, gui)

-- ЦЕНА сверху: монета + число (или красная «Не хватает»)
local priceRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(90, 22),
	BackgroundTransparency = 1, ZIndex = 3,
}, holder)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
}, priceRow)
local coinImg = new("ImageLabel", {
	Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = COIN_ICON,
	ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1, ZIndex = 3,
}, priceRow)
local priceLbl = new("TextLabel", {
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = Color3.fromRGB(255, 210, 58),
	Text = "10", LayoutOrder = 2, ZIndex = 3,
}, priceRow)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5 }, priceLbl)

-- иконка оружия (кнопка)
local btn = new("ImageButton", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6), Size = UDim2.fromOffset(74, 74),
	BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 1,
}, holder)
local btnScale = new("UIScale", {}, btn)
btn.MouseEnter:Connect(function() btnScale.Scale = 1.1 end)
btn.MouseLeave:Connect(function() btnScale.Scale = 1 end)

-- подпись «Подобрать» снизу
local caption = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1.4, 0, 0, 20),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "Подобрать", TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
}, holder)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5 }, caption)

-- НАШЕ: НА ТЕЛЕФОНЕ КНОПКА МЕНЬШЕ И НЕ НА ТРЕКЕРЕ КВЕСТА. В исходном месте
-- (18% ширины, 10% высоты) она ложилась на полосу «Собери брёвна» и была
-- крупнее соседних иконок HUD. Ставим справа от столбика кнопок (Квесты /
-- Магазин) и ужимаем до их размера.
do
	local UIS = game:GetService("UserInputService")
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		holder.Position = UDim2.new(0, 214, 0, 150)
		new("UIScale", { Scale = 0.65 }, holder)
	end
end

-- ══════════ поиск ближайшего оружия ══════════
local nearWeapon, nearType = nil, nil
local lastScan = 0

local best, bestType, bestD
local function scanContainer(cont, hrpPos)
	if not cont then return end
	for _, c in ipairs(cont:GetChildren()) do
		if c:IsA("Model") then
			local wt = weaponTypeOf(c)
			if wt then
				-- Расстояние меряем до ЖИВОЙ детали, а НЕ до c:GetPivot(). У модели
				-- без PrimaryPart GetPivot возвращает сохранённый WorldPivot, который
				-- НЕ едет за физикой: турель приварена к плывущему плоту, реальные
				-- части уезжают с ним, а пивот остаётся на месте старта — и через
				-- пару секунд «уходит» дальше радиуса, кнопка пропадает навсегда.
				local part = c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local d = (part.Position - hrpPos).Magnitude
					if d <= PICKUP_RADIUS and (not bestD or d < bestD) then
						best, bestType, bestD = c, wt, d
					end
				end
			end
		end
	end
end

local function findNearWeapon()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	best, bestType, bestD = nil, nil, nil
	-- оружие через постройку → ребёнок Raft; из эдитора → прямо в Workspace
	local hp = hrp.Position
	scanContainer(workspace:FindFirstChild("Raft"), hp)
	scanContainer(workspace, hp)
	return best, bestType
end

--[[ ⚠️ КНОПКА ПОДБОРА ЖИВЁТ ТОЛЬКО ПОД МОЛОТКОМ.
     Раньше она загоралась от одного присутствия пушки или турели рядом — то
     есть почти всё время, пока игрок ходит по плоту, и занимала верх экрана
     без всякого повода. Подбор — действие строителя, как и перенос построек
     (RaftRelocateClient требует молоток ровно по той же причине).
     На телефоне вдобавок ужимаем: там этот угол делят подсказка квеста и
     строка дня, и кнопка в 92 пикселя выглядела вдвое крупнее нужного. ]]
local HAMMER_TOOL = "Hammer"

local function holdingHammer()
	local char = player.Character
	local t = char and char:FindFirstChildWhichIsA("Tool")
	return t ~= nil and t.Name == HAMMER_TOOL
end

do
	local ok, Hud = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale", 5))
	end)
	if ok and Hud and Hud.isPhone and Hud.isPhone() then
		Hud.applyScaleLive(gui, Hud.iconFactor)
	end
end

local function holdingPlaceable()
	local char = player.Character
	local t = char and char:FindFirstChildWhichIsA("Tool")
	return t ~= nil and PLACEABLE_TOOLS[t.Name] == true
end

RunService.RenderStepped:Connect(function()
	if os.clock() - lastScan > 0.2 then
		lastScan = os.clock()
		nearWeapon, nearType = findNearWeapon()
	end
	-- прячем во время постройки (держим размещаемый тул → активен призрак CanonPlacer)
	if not nearWeapon or holdingPlaceable() or not holdingHammer() then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	btn.Image = WEAPON_ICONS[nearType]

	-- цена и проверка баланса (оба — атрибуты игрока, реплицируются)
	local count = player:GetAttribute("WeaponPickups") or 0
	local price = 10 + 20 * count
	local balance = player:GetAttribute("Pirate") or 0
	if balance >= price then
		coinImg.Visible = true
		priceLbl.Text = tostring(price)
		priceLbl.TextColor3 = Color3.fromRGB(255, 210, 58)
	else
		coinImg.Visible = false
		priceLbl.Text = "Не хватает"
		priceLbl.TextColor3 = Color3.fromRGB(235, 70, 60)
	end
end)

btn.Activated:Connect(function()
	if not (nearWeapon and nearWeapon.Parent) then return end
	local count = player:GetAttribute("WeaponPickups") or 0
	local price = 10 + 20 * count
	if (player:GetAttribute("Pirate") or 0) < price then return end -- не хватает — сервер и так отклонит
	cupActionEvent:FireServer("pickupWeapon", nearWeapon)
end)
