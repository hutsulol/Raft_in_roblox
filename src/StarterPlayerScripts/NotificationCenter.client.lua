-- NotificationCenter.client.lua  (Фаза 1 редизайна — см. GameDesign/UIRedesign_Plan.md)
-- Уведомления в новом стиле: карточки по типу (info/unlock/success/reward/warn) с
-- иконо-боксом + тайтлом + подзаголовком. Выезжают сбоку (справа), копятся стопкой
-- по центру высоты экрана, сами исчезают. Собрано через дизайн-модуль UITheme.
--
-- API:  _G.Notify({ title = "...", body = "...", type = "info", icon = "👥", duration = 4.5 })
--   type: info(синий) | unlock(фиолет) | success(зелёный) | reward(золото) | warn(красный)
-- Тест: клавиша N показывает три демо-уведомления.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CARD_WIDTH  = 340
local CARD_HEIGHT = 70
local DEFAULT_DURATION = 4.5

local DEFAULT_ICON = {
	info = "👥", unlock = "🗿", success = "🎯", reward = "🏆", warn = "⚠️",
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NotificationCenter"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

-- Контейнер: правый край, по центру высоты; карточки выезжают справа и центрируются.
-- Контейнер: по центру по горизонтали, над хотбаром; карточки всплывают снизу.
local container = Instance.new("Frame")
container.Name = "Stack"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -130) -- над панелью быстрого доступа
container.Size = UDim2.new(0, CARD_WIDTH, 0, 460)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Parent = container

local order = 0

-- Построить и показать одну карточку.
local function pushCard(opts)
	opts = opts or {}
	local nType = opts.type or "info"
	local colors = UITheme.Notif[nType] or UITheme.Notif.info
	order += 1

	-- Слот держит место в стопке; карточка внутри всплывает снизу.
	local slot = Instance.new("Frame")
	slot.Name = "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	slot.LayoutOrder = order
	slot.Parent = container

	local card = UITheme.panel({
		color = colors,
		corner = 14,
		stroke = 4,
		size = UDim2.new(1, 0, 1, 0),
		position = UDim2.new(0, 0, 1.4, 0), -- старт ниже слота (всплывёт вверх)
		parent = slot,
	})

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = card

	-- иконо-бокс слева — точный светлый slot-тон палитры
	UITheme.iconBox({
		icon = opts.icon or DEFAULT_ICON[nType] or "ℹ️",
		fill = Color3.fromHex(colors.slot or colors.top),
		stroke = Color3.fromHex(colors.frame),
		corner = 10,
		size = UDim2.fromOffset(CARD_HEIGHT - 16, CARD_HEIGHT - 16),
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 0, 0.5, 0),
		zindex = 2,
		parent = card,
	})

	-- колонка текста справа от иконки
	local textCol = Instance.new("Frame")
	textCol.BackgroundTransparency = 1
	textCol.AnchorPoint = Vector2.new(1, 0.5)
	textCol.Position = UDim2.new(1, 0, 0.5, 0)
	textCol.Size = UDim2.new(1, -(CARD_HEIGHT - 16) - 10, 1, 0)
	textCol.ZIndex = 2
	textCol.Parent = card

	local colLayout = Instance.new("UIListLayout")
	colLayout.SortOrder = Enum.SortOrder.LayoutOrder
	colLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	colLayout.Padding = UDim.new(0, 1)
	colLayout.Parent = textCol

	if opts.title and opts.title ~= "" then
		local title = UITheme.label({
			text = opts.title, font = UITheme.FONT_TITLE, textSize = 17,
			size = UDim2.new(1, 0, 0, 0), parent = textCol, zindex = 2, layoutOrder = 1,
		})
		title.AutomaticSize = Enum.AutomaticSize.Y
	end
	if opts.body and opts.body ~= "" then
		local body = UITheme.label({
			text = opts.body, font = UITheme.FONT_BODY, textSize = 14,
			textColor = Color3.fromRGB(235, 240, 245),
			size = UDim2.new(1, 0, 0, 0), parent = textCol, zindex = 2, layoutOrder = 2,
		})
		body.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- всплытие снизу
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 0, 0, 0) }):Play()

	-- авто-исчезание (уезжает вниз)
	task.delay(opts.duration or DEFAULT_DURATION, function()
		if not card.Parent then return end
		local out = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0, 0, 1.4, 0) })
		out:Play()
		out.Completed:Once(function()
			if slot.Parent then slot:Destroy() end
		end)
	end)
end

_G.Notify = pushCard

--====================================================
-- ТЕСТ: клавиша N → три демо-уведомления (можно убрать)
--====================================================

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.N then
		pushCard({ type = "info",    icon = "👥", title = "Жителей: +5",     body = "Освобождённые жители присоединились к лагерю" })
		task.delay(0.5, function()
			pushCard({ type = "unlock", icon = "🗿", title = "Древний монолит", body = "Открыто новое: Лесорубы" })
		end)
		task.delay(1.0, function()
			pushCard({ type = "success", icon = "🎯", title = "Остров исследован!", body = "Теперь на остров можно телепортироваться" })
		end)
	end
end)
