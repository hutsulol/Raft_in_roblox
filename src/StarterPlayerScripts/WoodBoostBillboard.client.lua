-- WoodBoostBillboard.client.lua
-- ЭКРАННАЯ иконка доната «2x / 4x дерево»: компактный блок (сверху «2X ДЕРЕВО»,
-- в центре иконка, снизу «50 R») в левом верхнем углу экрана.
--
-- Показывается ТОЛЬКО когда:
--   • рядом (радиус 50) есть ферма Tree_Farm, которая ПОСТРОЕНА и работает
--     (атрибут Built = true — его ставит TreeFarmSystem по кнопке «Начать»);
--     до зачистки острова здания нет вовсе, а пока ферма закрыта — предлагать
--     буст нельзя;
--   • буст ещё не на максимуме (после 4x иконка не показывается никогда).
--
-- Парт-якорь Wood_Donate (опционально) тоже задаёт зону показа, но работает
-- только когда в мире есть хотя бы одна построенная ферма.
--
-- Наведение: иконка увеличивается и слегка поворачивается. Клик/тап → RemoteEvent
-- WoodBoostBuy → сервер открывает родное окно покупки Roblox. После покупки 2x
-- предложение меняется на «4X ДЕРЕВО / 75 R».
--
-- Заодно чистим мировые BillboardGui "WoodBoostBillboard" от СТАРОЙ версии
-- скрипта (иконка, висящая в воздухе) — если её дубликат ещё остался в Studio.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local ANCHOR_NAME = "Wood_Donate" -- необязательный парт-якорь зоны
local FARM_NAME   = "Tree_Farm"   -- зона вокруг каждой ПОСТРОЕННОЙ фермы
local ATTR        = "WoodMultiplier"
local ICON        = "rbxassetid://111260937639554"
local SHOW_RADIUS = 50            -- «появляется в зоне 50»
local CHECK_EVERY = 0.2           -- частота проверки дистанции, сек

-- Положение и размер блока на экране — правь под себя.
local UI_POS  = UDim2.new(0.18, 0, 0.1, 0) -- ближе к центру и выше
local UI_SIZE = UDim2.fromOffset(80, 80)   -- квадрат под иконку (текст наезжает)

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
	stroke.Thickness = 2.5
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

-- Иконка заполняет блок; текст накладывается на её верх/низ (ZIndex выше).
local icon = Instance.new("ImageButton")
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0.5, 0, 0.5, 0)
icon.Size = UDim2.new(1, 0, 1, 0)
icon.BackgroundTransparency = 1
icon.Image = ICON
icon.ScaleType = Enum.ScaleType.Fit
icon.ZIndex = 1
icon.Parent = holder

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.13, 0) -- наезжает на верх иконки
title.Size = UDim2.new(1.3, 0, 0, 19)
title.ZIndex = 2
styleText(title)
title.Parent = holder

local price = Instance.new("TextLabel")
price.AnchorPoint = Vector2.new(0.5, 0.5)
price.Position = UDim2.new(0.5, 0, 0.9, 0) -- наезжает на низ иконки
price.Size = UDim2.new(0.95, 0, 0, 17)
price.ZIndex = 2
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
-- Зона: ПОСТРОЕННЫЕ фермы Tree_Farm + якоря Wood_Donate
--====================================================

local farms   = {} -- [model Tree_Farm] = BasePart для замера дистанции
local anchors = {} -- set BasePart Wood_Donate

local function addZone(inst)
	if inst:IsA("BasePart") and inst.Name == ANCHOR_NAME then
		anchors[inst] = true
	elseif inst:IsA("Model") and inst.Name == FARM_NAME then
		local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if part then farms[inst] = part end
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

	-- Построенные фермы: и зона, и общее условие «ферма работает».
	local anyBuilt = false
	for farm, part in pairs(farms) do
		if not farm:IsDescendantOf(workspace) then
			farms[farm] = nil -- остров despawn'улся
		elseif farm:GetAttribute("Built") == true then
			anyBuilt = true
			if part:IsDescendantOf(workspace)
				and (part.Position - pos).Magnitude <= SHOW_RADIUS then
				return true
			end
		end
	end

	-- Якоря учитываются, только если в мире вообще есть работающая ферма.
	if anyBuilt then
		for part in pairs(anchors) do
			if not part:IsDescendantOf(workspace) then
				anchors[part] = nil
			elseif (part.Position - pos).Magnitude <= SHOW_RADIUS then
				return true
			end
		end
	end
	return false
end

-- Мировые биллборды старой версии скрипта (иконка в воздухе) — сносим.
local function killStaleBillboards()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("BillboardGui") and child.Name == "WoodBoostBillboard" then
			child:Destroy()
		end
	end
end

-- Показ/скрытие по дистанции + построенности фермы.
task.spawn(function()
	while true do
		killStaleBillboards()
		gui.Enabled = (not maxed) and inZone()
		task.wait(CHECK_EVERY)
	end
end)
