-- WeaponHUD.client.lua  (StarterPlayerScripts)
-- Единый худ оружия по дизайну "Weapon HUD Roblox": когда игрок держит ствол —
-- в правом нижнем углу показываются НАЗВАНИЕ + редкость (цветом), крупно текущий
-- магазин /размер, ЗАПАС, и подсказка перезарядки. Текст без фона (как в дизайне).
-- Работает с любым Tool, у которого есть Configs.Ammo (АК, Револьвер, Pirate Gun и т.п.).
-- Заодно ГАСИТ родной ammo-GUI ствола, чтобы не было двух счётчиков.

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- шрифты: числа/имя — LuckiestGuy (как в дизайне; кириллица там не рендерится, поэтому
-- имя/подписи — жирным GothamBlack), цифры латиница — LuckiestGuy.
local FONT_NUM = Enum.Font.LuckiestGuy
local FONT_TXT = Enum.Font.GothamBlack

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)

-- редкости (метка + цвет) из дизайна
local RARITY = {
	legendary = { label = "ЛЕГЕНДАРНОЕ", color = Color3.fromRGB(200, 143, 232) },
	epic      = { label = "ЭПИЧЕСКОЕ",   color = Color3.fromRGB(127, 192, 255) },
	rare      = { label = "РЕДКОЕ",      color = Color3.fromRGB(127, 224, 122) },
	common    = { label = "ОБЫЧНОЕ",     color = Color3.fromRGB(154, 165, 176) },
}

-- название + редкость по стволу (ключ = начало имени тула)
local WEAPONS = {
	["Revolver"]   = { name = "РЕВОЛЬВЕР",       rarity = "rare" },
	["AK-47"]      = { name = "АК-47",           rarity = "epic" },
	["AK47"]       = { name = "АК-47",           rarity = "epic" },
	["Pirate_Gun"] = { name = "ПИРАТСКАЯ ПУШКА", rarity = "common" },
	["Pirate Gun"] = { name = "ПИРАТСКАЯ ПУШКА", rarity = "common" },
}

local function weaponConfig(tool)
	for key, cfg in pairs(WEAPONS) do
		if tool.Name:sub(1, #key) == key then return cfg end
	end
	return { name = string.upper(tool.Name), rarity = "common" }
end

-- ── строим худ (скрыт до экипировки) ──
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
gui.IgnoreGuiInset = false
gui.Enabled = false
gui.Parent = playerGui

local root = mk("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -22, 1, -20),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundTransparency = 1,
}, gui)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 2),
}, root)

-- название
local nameLbl = mk("TextLabel", {
	LayoutOrder = 1, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28),
	Font = FONT_TXT, TextSize = 24, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Right, Text = "ОРУЖИЕ",
}, root)
-- редкость
local rarityLbl = mk("TextLabel", {
	LayoutOrder = 2, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16),
	Font = FONT_TXT, TextSize = 13, TextColor3 = RARITY.common.color,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.1,
	TextXAlignment = Enum.TextXAlignment.Right, Text = "ОБЫЧНОЕ",
}, root)

-- строка патронов (магазин / размер | ЗАПАС запас)
local ammoRow = mk("Frame", {
	LayoutOrder = 3, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46),
}, root)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, ammoRow)

local magLbl = mk("TextLabel", {
	LayoutOrder = 1, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46),
	Font = FONT_NUM, TextSize = 44, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
	TextYAlignment = Enum.TextYAlignment.Bottom, Text = "6",
}, ammoRow)
local magSizeLbl = mk("TextLabel", {
	LayoutOrder = 2, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
	Font = FONT_NUM, TextSize = 24, TextColor3 = Color3.fromRGB(90, 122, 150),
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
	TextYAlignment = Enum.TextYAlignment.Bottom, Text = "/30",
}, ammoRow)
local sep = mk("Frame", {
	LayoutOrder = 3, BackgroundColor3 = WHITE, BackgroundTransparency = 0.82,
	BorderSizePixel = 0, Size = UDim2.fromOffset(3, 28),
}, ammoRow)
local zapasLbl = mk("TextLabel", {
	LayoutOrder = 4, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30),
	Font = FONT_TXT, TextSize = 12, TextColor3 = Color3.fromRGB(127, 168, 201),
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.4,
	TextYAlignment = Enum.TextYAlignment.Bottom, Text = "ЗАПАС",
}, ammoRow)
local reserveLbl = mk("TextLabel", {
	LayoutOrder = 5, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
	Font = FONT_NUM, TextSize = 24, TextColor3 = Color3.fromRGB(255, 210, 58),
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
	TextYAlignment = Enum.TextYAlignment.Bottom, Text = "18",
}, ammoRow)

-- подсказка перезарядки
local reloadHint = mk("Frame", {
	LayoutOrder = 4, BackgroundColor3 = Color3.fromRGB(212, 53, 53),
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
	Visible = false,
}, root)
mk("UIStroke", { Color = BLACK, Thickness = 2 }, reloadHint)
mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, reloadHint)
mk("TextLabel", {
	BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1),
	Font = FONT_TXT, TextSize = 13, TextColor3 = WHITE,
	TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.2, Text = "ПЕРЕЗАРЯДКА — [R]",
}, reloadHint)

-- ── обновление значений ──
local function setValues(cfg, cur, magSize, reserve)
	nameLbl.Text = cfg.name
	local r = RARITY[cfg.rarity] or RARITY.common
	rarityLbl.Text = r.label
	rarityLbl.TextColor3 = r.color

	cur = cur or 0; magSize = math.max(magSize or 1, 1); reserve = reserve or 0
	magLbl.Text = tostring(cur)
	magSizeLbl.Text = "/" .. magSize
	reserveLbl.Text = tostring(reserve)
	local pct = cur / magSize
	magLbl.TextColor3 = (cur == 0 and Color3.fromRGB(212, 53, 53))
		or (pct <= 0.25 and Color3.fromRGB(232, 185, 58)) or WHITE
	reloadHint.Visible = (cur == 0 and reserve > 0)
end

-- ── гасим родной ammo-GUI ствола (чтобы не дублировать) ──
local function hideKitGui(tool)
	local names = {}
	local g = tool:FindFirstChild("GUI")
	if g then
		for _, d in g:GetDescendants() do
			if d:IsA("ScreenGui") then d.Enabled = false; names[d.Name] = true end
		end
	end
	for _, sg in playerGui:GetChildren() do
		if sg:IsA("ScreenGui") and names[sg.Name] then sg.Enabled = false end
	end
	local conn
	conn = playerGui.ChildAdded:Connect(function(sg)
		if sg:IsA("ScreenGui") and names[sg.Name] then sg.Enabled = false end
	end)
	task.delay(1.5, function() if conn then conn:Disconnect() end end)
end

-- ── экипировка ──
local function attach(tool)
	if not tool:IsA("Tool") then return end
	local configs = tool:FindFirstChild("Configs") or tool:WaitForChild("Configs", 4)
	local ammo = configs and (configs:FindFirstChild("Ammo") or configs:WaitForChild("Ammo", 4))
	if not ammo then return end -- не стрелковое оружие
	local magSize = configs:FindFirstChild("MagSize")
	local reserve = configs:FindFirstChild("ReserveAmmo")

	local cfg = weaponConfig(tool)
	hideKitGui(tool)

	local conns = {}
	local function refresh()
		setValues(cfg, ammo.Value, magSize and magSize.Value, reserve and reserve.Value)
	end
	table.insert(conns, ammo.Changed:Connect(refresh))
	if magSize then table.insert(conns, magSize.Changed:Connect(refresh)) end
	if reserve then table.insert(conns, reserve.Changed:Connect(refresh)) end
	refresh()
	gui.Enabled = true

	local uConn
	uConn = tool.Unequipped:Connect(function()
		for _, c in conns do c:Disconnect() end
		if uConn then uConn:Disconnect() end
		gui.Enabled = false
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
