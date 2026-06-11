-- WoodBoostBillboard.client.lua
-- ЭКРАННАЯ иконка доната «2x / 4x дерево» (как в референсе): блок слева сверху
-- экрана — сверху «2X ДЕРЕВО», в центре иконка (брёвна на сером круге), снизу
-- цена «50 R». Появляется, только когда игрок в радиусе 50 студов от фермы
-- (модель Tree_Farm или парт-якорь Wood_Donate — он имеет тот же эффект).
--
-- Это ScreenGui, НЕ BillboardGui: ничего не висит в мире и не перехватывает
-- клики по кнопкам борда фермы.
--
-- Наведение: иконка увеличивается и слегка поворачивается. Клик/тап → RemoteEvent
-- WoodBoostBuy → сервер открывает родное окно покупки Roblox. После покупки 2x
-- предложение меняется на «4X ДЕРЕВО / 75 R», после 4x иконка исчезает навсегда.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local ANCHOR_NAME = "Wood_Donate" -- необязательный парт-якорь зоны
local FARM_NAME   = "Tree_Farm"   -- зона работает вокруг каждой фермы
local ATTR        = "WoodMultiplier"
local ICON        = "rbxassetid://111260937639554"
local SHOW_RADIUS = 50            -- «появляется в зоне 50»
local CHECK_EVERY = 0.2           -- частота проверки дистанции, сек

-- Положение блока на экране (левый верх, как в референсе) — правь под себя.
local UI_POS  = UDim2.new(0, 24, 0.12, 0)
local UI_SIZE = UDim2.fromOffset(170, 215)

-- Что предлагаем при текущем множителе игрока.
local TIERS = {
	[1] = { title = "2X ДЕРЕВО", price = "50 R" },
	[2] = { title = "4X ДЕРЕВО", price = "75 R" },
	-- [4] — максимум: иконка прячется
}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local buyRemote = ReplicatedStorage:WaitForChild("WoodBoostBuy")

local HOVER_IN  = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--====================================================
-- UI (строится один раз)
--====================================================

local function styleText(label)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label
end

local gui = Instance.new("ScreenGui")
gui.Name = "WoodBoostGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Enabled = false
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Position = UI_POS
holder.Size = UI_SIZE
holder.BackgroundTransparency = 1
holder.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 0)
title.Size = UDim2.new(1, 0, 0, 34)
styleText(title)
title.Parent = holder

local icon = Instance.new("ImageButton")
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0.5, 0, 0.5, 4)
icon.Size = UDim2.fromOffset(128, 128)
icon.BackgroundTransparency = 1
icon.Image = ICON
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = holder

local price = Instance.new("TextLabel")
price.AnchorPoint = Vector2.new(0.5, 1)
price.Position = UDim2.new(0.5, 0, 1, 0)
price.Size = UDim2.new(1, 0, 0, 30)
styleText(price)
price.Parent = holder

-- Наведение: увеличивается и слегка поворачивается.
local scale = Instance.new("UIScale")
scale.Parent = icon
icon.MouseEnter:Connect(function()
	TweenService:Create(scale, HOVER_IN, { Scale = 1.12 }):Play()
	TweenService:Create(icon, HOVER_IN, { Rotation = 8 }):Play()
end)
icon.MouseLeave:Connect(function()
	TweenService:Create(scale, HOVER_OUT, { Scale = 1 }):Play()
	TweenService:Create(icon, HOVER_OUT, { Rotation = 0 }):Play()
end)

-- Клик/тап — окно покупки (сервер сам выберет продукт текущего тира).
icon.Activated:Connect(function()
	buyRemote:FireServer()
end)

--====================================================
-- Тир: какие тексты показывать; 4x — спрятать насовсем
--====================================================

local maxed = false

local function refreshTier()
	local mult = player:GetAttribute(ATTR)
	mult = type(mult) == "number" and mult or 1
	local tier = TIERS[mult]
	if tier == nil then
		maxed = true -- 4x куплен — больше покупать нечего
		return
	end
	maxed = false
	title.Text = tier.title
	price.Text = tier.price
end

refreshTier()
player:GetAttributeChangedSignal(ATTR):Connect(refreshTier)

--====================================================
-- Зона: фермы Tree_Farm + якоря Wood_Donate (и появляющиеся позже)
--====================================================

local zoneParts = {} -- set: BasePart, от которых меряем дистанцию

local function addZone(inst)
	local part
	if inst.Name == ANCHOR_NAME and inst:IsA("BasePart") then
		part = inst
	elseif inst:IsA("Model") and (inst.Name == FARM_NAME or inst.Name == ANCHOR_NAME) then
		part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	if part then
		zoneParts[part] = true
	end
end

for _, d in ipairs(workspace:GetDescendants()) do
	addZone(d)
end
workspace.DescendantAdded:Connect(function(inst)
	task.wait(0.1) -- дать модели догрузить части
	addZone(inst)
end)

local function inZone()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local pos = hrp.Position
	for part in pairs(zoneParts) do
		if part.Parent == nil or not part:IsDescendantOf(workspace) then
			zoneParts[part] = nil -- ферма удалена/despawn
		elseif (part.Position - pos).Magnitude <= SHOW_RADIUS then
			return true
		end
	end
	return false
end

-- Показ/скрытие по дистанции.
task.spawn(function()
	while true do
		gui.Enabled = (not maxed) and inZone()
		task.wait(CHECK_EVERY)
	end
end)
