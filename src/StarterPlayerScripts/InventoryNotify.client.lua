-- InventoryNotify.client.lua
-- Generic "+N item" notification stack — listens on the
-- InventoryNotify RemoteEvent and renders a bottom-right card for
-- every inventory add the server reports. Used by tree chopping,
-- stone mining, ocean pulls, shovel digging, floor pickups, fishing —
-- anything that routes through _G.AddResourceToInventory.
-- Container takeouts (SmallContainerSystem / PlasticContainerSystem /
-- MercenaryEquipment) pass silent=true so chest extraction doesn't
-- spam this stack.
--
-- Редизайн «Вариант А — плашки с панелью» (палитра «Океан»):
--   • карточка = градиентная панель #54A7EC→#3A7FD0, рамка #1C4F8F, скругление;
--   • слева иконка в светлом слот-боксе #A9D6F7, затем «+N» золотом и имя белым;
--   • ширина адаптивна под текст (AutomaticSize.X);
--   • стопка в правом нижнем углу, новые снизу; повторный подбор того же
--     предмета суммирует счётчик и продлевает жизнь карточки;
--   • ПЕРВОЕ попадание предмета в инвентарь — золотая рамка + бейдж «NEW!».

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local notifyEvent = ReplicatedStorage:WaitForChild("InventoryNotify")

-- ─── Resource → display-name overrides ───────────────────────────
local DISPLAY_NAMES = {
	Iron_Ore       = "Iron Ore",
	Iron_Ingot     = "Iron Ingot",
	Wet_Brick      = "Wet Brick",
	Dry_Brick      = "Dry Brick",
	Blue_Fish      = "Blue Fish",
	Carp_Fish      = "Carp Fish",
	Foil_Fish      = "Foil Fish",
	Jelly_Fish     = "Jelly Fish",
	Legendary_Fish = "Legendary Fish",
	Seabass_Fish   = "Seabass Fish",
	Tilapia_Fish   = "Tilapia Fish",
	Fish_Bones     = "Fish Bones",
	Wood_Knife     = "Wood Knife",
	["Pick-Axe"]   = "Pick-Axe",
	Stone_Axe      = "Stone Axe",
	Banana_Seed    = "Banana Seed",
	Coconut_Seed   = "Coconut Seed",
	Pineapple_Seed      = "Pineapple Seed",
	Pineapple_Bush_Seed = "Pineapple Bush Seed",
}

local function displayName(rawName)
	return DISPLAY_NAMES[rawName] or rawName
end

local function iconFor(rawName)
	-- _G.GetItemIcon публикует InventoryUI; "" — карточка остаётся валидной.
	if typeof(_G.GetItemIcon) == "function" then
		return _G.GetItemIcon(rawName) or ""
	end
	return ""
end

-- ─── Палитра «Океан» ──────────────────────────────────────────────
local PANEL_TOP   = Color3.fromHex("54A7EC")
local PANEL_BOT   = Color3.fromHex("3A7FD0")
local FRAME_NAVY  = Color3.fromHex("1C4F8F")
local SLOT_LIGHT  = Color3.fromHex("A9D6F7")
local GOLD        = Color3.fromHex("FFD95A")
local GOLD_FRAME  = Color3.fromHex("B07A14")
local GOLD_NEW    = Color3.fromHex("F5B73C") -- рамка карточки «новый предмет»

-- ─── HUD root ────────────────────────────────────────────────────
local hud = Instance.new("ScreenGui")
hud.Name = "InventoryNotify"
hud.DisplayOrder = 60
hud.IgnoreGuiInset = true
hud.ResetOnSpawn = false
hud.Parent = playerGui

local NOTIF_LIFETIME = 3.0
local NOTIF_FADE     = 0.45
local NOTIF_HEIGHT   = 56
local NOTIF_GAP      = 8

local container = Instance.new("Frame")
container.Name = "Stack"
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(1, -16, 1, -110)   -- над хотбаром
container.Size = UDim2.fromOffset(340, 420)
container.BackgroundTransparency = 1
container.Parent = hud

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding   = UDim.new(0, NOTIF_GAP)
layout.Parent = container

-- ─── «Новый предмет» ──────────────────────────────────────────────
-- NEW показываем при ПЕРВОМ попадании предмета в инвентарь. «Уже есть» сидируем
-- из опубликованной инвентарём раскладки (_G.InventorySlotData): всё, что лежит
-- в слотах на момент загрузки, новым не считается.
local seenItems = {}
task.spawn(function()
	local t0 = os.clock()
	while not _G.InventorySlotData and os.clock() - t0 < 10 do
		task.wait(0.25)
	end
	local slots = _G.InventorySlotData
	if typeof(slots) ~= "table" then return end
	task.wait(1) -- дать слотам заполниться первым снапшотом сервера
	for _, data in pairs(slots) do
		if typeof(data) == "table" then
			local nm = data.name or data.toolName
			if nm then seenItems[nm] = true end
		end
	end
end)

-- ─── Per-item dedup ───────────────────────────────────────────────
-- Повторный подбор того же предмета, пока карточка жива, суммирует счётчик
-- и продлевает её жизнь (никаких дублей в стопке).
local activeCards = {}    -- [itemName] = { card, countLabel, total, bumpedAt }
local notifOrder  = 0

local function showNotif(rawName, count)
	if (count or 0) <= 0 then return end

	local existing = activeCards[rawName]
	if existing and existing.card.Parent then
		existing.total = existing.total + count
		existing.countLabel.Text = "+" .. tostring(existing.total)
		existing.bumpedAt = tick()
		return
	end

	local isNew = not seenItems[rawName]
	seenItems[rawName] = true

	notifOrder = notifOrder + 1

	-- Обычный Frame + РУЧНОЕ растворение по списку свойств: GroupTransparency у
	-- CanvasGroup гасил только фон (рамка/иконка/бокс оставались плотными).
	local card = Instance.new("Frame")
	card.Name = "Drop_" .. rawName
	card.AutomaticSize = Enum.AutomaticSize.X     -- ширина адаптивна под текст
	card.Size = UDim2.fromOffset(0, NOTIF_HEIGHT)
	card.BackgroundColor3 = Color3.new(1, 1, 1)   -- белый под градиент (он умножается)
	card.BorderSizePixel = 0
	card.LayoutOrder = notifOrder
	card.Parent = container

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(PANEL_TOP, PANEL_BOT)
	grad.Rotation = 90
	grad.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = isNew and GOLD_NEW or FRAME_NAVY
	stroke.Thickness = isNew and 4 or 3
	stroke.Parent = card

	-- Контент в строку: [слот-бокс с иконкой] +N Имя
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AutomaticSize = Enum.AutomaticSize.X
	body.Size = UDim2.new(0, 0, 1, 0)
	body.BackgroundTransparency = 1
	body.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 8)
	pad.PaddingRight  = UDim.new(0, 14)
	pad.PaddingTop    = UDim.new(0, 7)
	pad.PaddingBottom = UDim.new(0, 7)
	pad.Parent = body

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 9)
	row.Parent = body

	-- иконка в светлом слот-боксе
	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.fromOffset(NOTIF_HEIGHT - 14, NOTIF_HEIGHT - 14)
	iconBox.BackgroundColor3 = SLOT_LIGHT
	iconBox.BorderSizePixel = 0
	iconBox.LayoutOrder = 1
	iconBox.Parent = body

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 10)
	iconCorner.Parent = iconBox

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = FRAME_NAVY
	iconStroke.Thickness = 2
	iconStroke.Parent = iconBox

	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.BackgroundTransparency = 1
	icon.Image = iconFor(rawName)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = iconBox

	-- «+N» — золотым жирным
	local countLabel = Instance.new("TextLabel")
	countLabel.AutomaticSize = Enum.AutomaticSize.X
	countLabel.Size = UDim2.new(0, 0, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "+" .. tostring(count)
	countLabel.TextColor3 = GOLD
	countLabel.TextSize = 22
	countLabel.Font = Enum.Font.GothamBlack
	countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	countLabel.TextStrokeTransparency = 0.6
	countLabel.TextYAlignment = Enum.TextYAlignment.Center
	countLabel.LayoutOrder = 2
	countLabel.Parent = body

	-- имя предмета — белым жирным
	local nameLabel = Instance.new("TextLabel")
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Size = UDim2.new(0, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName(rawName)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextSize = 20
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.6
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.LayoutOrder = 3
	nameLabel.Parent = body

	-- бейдж «NEW!» — золотая пилюля на верхней кромке (первый подбор)
	local badge, badgeStroke, badgeText
	if isNew then
		badge = Instance.new("Frame")
		badge.Name = "NewBadge"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 14, 0, 2)
		badge.AutomaticSize = Enum.AutomaticSize.XY
		badge.BackgroundColor3 = GOLD
		badge.BorderSizePixel = 0
		badge.ZIndex = 3
		badge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(1, 0)
		badgeCorner.Parent = badge

		badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = GOLD_FRAME
		badgeStroke.Thickness = 2
		badgeStroke.Parent = badge

		local badgePad = Instance.new("UIPadding")
		badgePad.PaddingLeft = UDim.new(0, 8)
		badgePad.PaddingRight = UDim.new(0, 8)
		badgePad.PaddingTop = UDim.new(0, 2)
		badgePad.PaddingBottom = UDim.new(0, 2)
		badgePad.Parent = badge

		badgeText = Instance.new("TextLabel")
		badgeText.AutomaticSize = Enum.AutomaticSize.XY
		badgeText.Size = UDim2.new(0, 0, 0, 0)
		badgeText.BackgroundTransparency = 1
		badgeText.Text = "NEW!"
		badgeText.TextColor3 = Color3.fromHex("6B4A0E")
		badgeText.TextSize = 11
		badgeText.Font = Enum.Font.GothamBlack
		badgeText.ZIndex = 3
		badgeText.Parent = badge
	end

	-- Всё, что растворяем при уходе карточки: {объект, свойство, базовое значение}.
	local fadeItems = {
		{ card,       "BackgroundTransparency", 0 },
		{ stroke,     "Transparency",           0 },
		{ iconBox,    "BackgroundTransparency", 0 },
		{ iconStroke, "Transparency",           0 },
		{ icon,       "ImageTransparency",      0 },
		{ countLabel, "TextTransparency",       0 },
		{ countLabel, "TextStrokeTransparency", 0.6 },
		{ nameLabel,  "TextTransparency",       0 },
		{ nameLabel,  "TextStrokeTransparency", 0.6 },
	}
	if badge then
		table.insert(fadeItems, { badge,      "BackgroundTransparency", 0 })
		table.insert(fadeItems, { badgeStroke, "Transparency",          0 })
		table.insert(fadeItems, { badgeText,  "TextTransparency",       0 })
	end

	local rec = {
		card       = card,
		countLabel = countLabel,
		total      = count,
		bumpedAt   = tick(),
	}
	activeCards[rawName] = rec

	task.spawn(function()
		-- Жизнь меряем от последнего подбора (bumpedAt), затем плавное растворение.
		while card.Parent do
			local since = tick() - rec.bumpedAt
			if since >= NOTIF_LIFETIME then break end
			task.wait(NOTIF_LIFETIME - since)
		end
		if not card.Parent then return end
		local steps = 10
		for i = 0, steps do
			if not card.Parent then return end
			local a = i / steps
			for _, item in ipairs(fadeItems) do
				local obj, prop, base = item[1], item[2], item[3]
				obj[prop] = base + (1 - base) * a
			end
			task.wait(NOTIF_FADE / steps)
		end
		if card.Parent then card:Destroy() end
		if activeCards[rawName] == rec then
			activeCards[rawName] = nil
		end
	end)
end

notifyEvent.OnClientEvent:Connect(function(itemName, count)
	if typeof(itemName) ~= "string" or itemName == "" then return end
	if (tonumber(count) or 0) <= 0 then return end
	showNotif(itemName, count)
end)
