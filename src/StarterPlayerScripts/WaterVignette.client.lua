-- WaterVignette.client.lua
-- The missing listener for ReplicatedStorage.WaterVignette (ToxicWater.server.lua fires it with an
-- intensity 0..1 while the player is over toxic water). Draws a soft toxic-green edge vignette that
-- deepens with intensity. Built from 4 gradient edge frames — no image assets needed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local event     = ReplicatedStorage:WaitForChild("WaterVignette")

--[[ ⚠️ ДВА СЛОЯ И ПУЛЬСАЦИЯ — КАК В МАКЕТЕ «Предупреждения.dc.html».
     Раньше кромка была одна, зелёная и неподвижная: она читалась как «тут
     мутно», а не как «мне сейчас снимают здоровье». В макете слоёв два —
     ядовито-зелёная муть дышит медленно, красная кромка бьётся вдвое чаще, и
     вместе это и есть «я получаю урон». ]]
local TINT      = Color3.fromRGB(38, 74, 34)   -- ядовито-зелёная муть
local RED       = Color3.fromRGB(240, 69, 69)  -- #f04545: кромка урона
local EDGE      = 0.28                         -- доля экрана под зелёный градиент
local EDGE_RED  = 0.16                         -- красная кромка уже: только по краю
local MAX_ALPHA = 0.55                         -- плотность зелени при интенсивности 1
local RED_ALPHA = 0.5                          -- плотность красного на пике пульса
local PULSE_G   = 0.9                          -- секунд на вдох-выдох зелени
local PULSE_R   = 0.45                         -- красный бьётся вдвое чаще

local gui = Instance.new("ScreenGui")
gui.Name = "WaterVignetteGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- до кромки iPhone (чёлка, углы): см. пояснение в WaterVingette
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
gui.DisplayOrder = 90
gui.Parent = playerGui

-- по четыре кромки на слой: сверху, снизу, слева и справа, каждая гаснет к центру
local function makeEdgeSet(color, width)
	local set = {}
	local function makeEdge(pos, size, rotation)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Position = pos
		f.Size = size
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = rotation   -- плотно у края экрана → прозрачно к центру
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		table.insert(set, f)
	end
	makeEdge(UDim2.fromScale(0, 0), UDim2.fromScale(1, width), 90)
	makeEdge(UDim2.fromScale(0, 1 - width), UDim2.fromScale(1, width), -90)
	makeEdge(UDim2.fromScale(0, 0), UDim2.fromScale(width, 1), 0)
	makeEdge(UDim2.fromScale(1 - width, 0), UDim2.fromScale(width, 1), 180)
	return set
end

local greenEdges = makeEdgeSet(TINT, EDGE)
local redEdges   = makeEdgeSet(RED, EDGE_RED)
local RunService = game:GetService("RunService")

local current = 0   -- 0 = не в воде, 1 = максимум

event.OnClientEvent:Connect(function(intensity)
	current = math.clamp(tonumber(intensity) or 0, 0, 1)
	if current <= 0.001 then
		-- вышел из воды: гасим обе кромки одним плавным движением
		for _, f in ipairs(greenEdges) do
			TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		for _, f in ipairs(redEdges) do
			TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
	end
end)

--[[ Пульсация. Считаем прозрачность каждый кадр, а не твинами: твин на
     повторе пришлось бы отменять и перезапускать на каждое изменение
     интенсивности, а тут просто две синусоиды с разным периодом. Пока игрок
     не в воде, цикл выходит на первой же строке и ничего не стоит. ]]
RunService.Heartbeat:Connect(function()
	if current <= 0.001 then return end
	local now = os.clock()
	local g = 0.25 + 0.75 * (math.sin(now * (2 * math.pi / PULSE_G)) * 0.5 + 0.5)
	local r = 0.15 + 0.85 * (math.sin(now * (2 * math.pi / PULSE_R)) * 0.5 + 0.5)
	local ga = 1 - current * MAX_ALPHA * g
	local ra = 1 - current * RED_ALPHA * r
	for _, f in ipairs(greenEdges) do f.BackgroundTransparency = ga end
	for _, f in ipairs(redEdges) do f.BackgroundTransparency = ra end
end)