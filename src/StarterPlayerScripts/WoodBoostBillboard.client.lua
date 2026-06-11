-- WoodBoostBillboard.client.lua
-- Иконка доната «2x / 4x дерево» у камня возле фермы деревьев.
--
-- Якорь: парт (или модель) с именем Wood_Donate — поставь его в то место, где
-- должна висеть иконка. Биллборд видно в радиусе 50 студов (MaxDistance), он
-- прячется за рельефом (AlwaysOnTop = false), как в референсе.
--
-- Вёрстка как в примере: сверху «2X ДЕРЕВО», в центре иконка (брёвна на сером
-- круге — круг запечён в картинку), снизу цена «50 R». Белый жирный текст с
-- чёрной обводкой. После покупки 2x предложение меняется на «4X ДЕРЕВО / 75 R»,
-- после 4x биллборд исчезает (максимум).
--
-- Наведение: иконка увеличивается и слегка поворачивается. Клик/тап → RemoteEvent
-- WoodBoostBuy → сервер открывает родное окно покупки Roblox.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local ANCHOR_NAME = "Wood_Donate"
local ICON        = "rbxassetid://111260937639554"
local ATTR        = "WoodMultiplier"
local SHOW_RADIUS = 50

-- Что предлагает биллборд при текущем множителе игрока.
local TIERS = {
	[1] = { title = "2X ДЕРЕВО", price = "50 R" },
	[2] = { title = "4X ДЕРЕВО", price = "75 R" },
	-- [4] — максимум: биллборд выключается
}

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local buyRemote = ReplicatedStorage:WaitForChild("WoodBoostBuy")

local HOVER_IN  = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local guis = {} -- все построенные биллборды (обновляем при смене тира)

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

local function refreshOne(rec)
	local mult = player:GetAttribute(ATTR)
	mult = type(mult) == "number" and mult or 1
	local tier = TIERS[mult]
	if tier == nil then
		rec.gui.Enabled = false -- 4x куплен — больше покупать нечего
		return
	end
	rec.gui.Enabled = true
	rec.title.Text = tier.title
	rec.price.Text = tier.price
end

local function buildBillboard(part)
	local gui = Instance.new("BillboardGui")
	gui.Name = "WoodBoostBillboard"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(6, 8)        -- размер в студах
	gui.MaxDistance = SHOW_RADIUS           -- «появляется в зоне 50»
	gui.AlwaysOnTop = false                 -- прячется за рельефом, как в примере
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0)
	title.Size = UDim2.fromScale(1, 0.17)
	styleText(title)
	title.Parent = gui

	local icon = Instance.new("ImageButton")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.BackgroundTransparency = 1
	icon.Image = ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = icon

	local price = Instance.new("TextLabel")
	price.AnchorPoint = Vector2.new(0.5, 1)
	price.Position = UDim2.fromScale(0.5, 1)
	price.Size = UDim2.fromScale(1, 0.15)
	styleText(price)
	price.Parent = gui

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

	local rec = { gui = gui, title = title, price = price }
	table.insert(guis, rec)
	refreshOne(rec)
end

--====================================================
-- Поиск якорей Wood_Donate (сейчас и появляющихся позже)
--====================================================

local attached = {}

local function tryAttach(inst)
	if inst.Name ~= ANCHOR_NAME then return end
	local part
	if inst:IsA("BasePart") then
		part = inst
	elseif inst:IsA("Model") then
		part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	if part == nil or attached[part] then return end
	attached[part] = true
	buildBillboard(part)
end

for _, d in ipairs(workspace:GetDescendants()) do
	tryAttach(d)
end
workspace.DescendantAdded:Connect(tryAttach)

-- Смена тира (покупка прошла) — обновить все биллборды.
player:GetAttributeChangedSignal(ATTR):Connect(function()
	for _, rec in ipairs(guis) do
		if rec.gui.Parent then refreshOne(rec) end
	end
end)
