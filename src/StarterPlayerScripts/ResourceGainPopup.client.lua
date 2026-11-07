local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[ ResourceGainPopup — «+N дерево» НАД ГОЛОВОЙ, когда что-то добыл.

     Жалоба игрока дословно: «бью топором и вижу только в инвентаре, что чего-то
     стало больше». Карточка в правом нижнем углу (InventoryNotify) есть, но
     взгляд во время рубки — на дереве и на персонаже, а не в угол. Поэтому
     число всплывает там, куда смотрят: над головой, как уже всплывает «-HP»
     (RadiationUI, popDamage). Стиль тот же — кегль, обводка, длительность, —
     чтобы читалось как одна семья, только зелёное и со знаком плюс.

     ⚠️ НЕ ПРЯМО ВВЕРХ, А ВРАЗЛЁТ.
     У «-HP» числа уезжают строго вверх; для добычи владелец просил иначе:
     появляться в разных точках вокруг головы и лететь В СТОРОНУ появления —
     справа возникло, вправо-вверх и уходит. Так три удара подряд дают три
     разных траектории, а не столбик одинаковых цифр друг над другом.

     ⚠️ ТОЛЬКО ТОПОР. Первая версия слушала InventoryNotify — общий прирост
     инвентаря, — и число всплывало на любую добычу: вылов, грядку, сундук.
     Владелец решил: над головой отмечаем только то, что срубил топором.
     Источник — ответ сервера StoneAxe «drops» по событию ChopTree: там ровно
     то, что выпало от ЭТОГО удара. Подпись убрана — только «+N» и иконка,
     оранжевым, как дерево. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudScale
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudScale", 10))
	end)
	if ok then HudScale = mod end
end
local function noticeK()
	if HudScale and HudScale.noticeFactor then
		local ok, k = pcall(HudScale.noticeFactor)
		if ok and type(k) == "number" and k > 0 then return k end
	end
	return 1
end

-- ── та же семья, что у «-HP» (RadiationUI) ──
local RISE        = 1.4     -- студов вверх за полёт
local SIDE        = 1.3     -- студов в сторону появления
local TIME        = 1.0     -- секунд на весь полёт
local START_UP    = 1.1     -- стартовая высота над головой: почти у макушки (владелец: «пониже, ближе к голове»)
local SPREAD_X    = 1.2     -- насколько далеко от центра может появиться (в стороны)
local SPREAD_Z    = 0.6     -- и чуть вперёд-назад, чтобы не в одной плоскости
local MAX_ONSCREEN = 6      -- больше — каша, как и у урона
local MERGE_WINDOW = 0.45   -- секунд: тот же предмет — прибавляем к живому числу

local INK   = Color3.fromRGB(20, 38, 26)      -- общая тёмная обводка макета
local ORANGE = Color3.fromRGB(255, 166, 54)   -- «плюс» — оранжевый, под цвет дерева

local live = 0
-- [itemName] = { at = os.clock(), label = TextLabel, amount = n }
local lastByItem = {}

local function iconFor(rawName)
	if typeof(_G.GetItemIcon) == "function" then
		local ok, id = pcall(_G.GetItemIcon, rawName)
		if ok and type(id) == "string" then return id end
	end
	return ""
end

local function popGain(head, itemName, amount)
	--[[ Быстрая серия одного и того же — одно растущее число, а не очередь.
	     Топор снимает с дерева несколько брёвен подряд за доли секунды; без
	     склейки над головой висели бы три «+1» друг на друге. ]]
	local last = lastByItem[itemName]
	if last and last.label.Parent and (os.clock() - last.at) < MERGE_WINDOW then
		last.amount += amount
		last.label.Text = "+" .. tostring(last.amount)
		return
	end
	if live >= MAX_ONSCREEN then return end
	live += 1

	local K = noticeK()
	local function P(n) return math.max(1, math.floor(n * K + 0.5)) end

	--[[ Точка появления — случайно вокруг головы; направление полёта берём из
	     неё же: знак X решает, в какую сторону уезжать. Центр (|x| мал) уходит
	     почти вверх, края — заметно вбок. ]]
	local sx = (math.random() * 2 - 1) * SPREAD_X
	local sz = (math.random() * 2 - 1) * SPREAD_Z
	local dir = (sx >= 0) and 1 or -1
	local sideAmount = SIDE * (0.35 + 0.65 * math.abs(sx) / SPREAD_X)

	local bb = Instance.new("BillboardGui")
	bb.Name = "GainPop"
	bb.Size = UDim2.fromOffset(P(260), P(72))
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	bb.StudsOffsetWorldSpace = Vector3.new(sx, START_UP, sz)
	bb.Adornee = head
	bb.Parent = playerGui

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromOffset(0, 0)
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Parent = bb

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, P(5))
	list.Parent = row

	local num = Instance.new("TextLabel")
	num.LayoutOrder = 1
	num.BackgroundTransparency = 1
	num.AutomaticSize = Enum.AutomaticSize.XY
	num.Size = UDim2.fromOffset(0, 0)
	num.Font = Enum.Font.GothamBlack
	num.TextSize = P(42)   -- крупнее: владелец просил «побольше»
	num.TextColor3 = ORANGE
	num.Text = "+" .. tostring(amount)
	num.Parent = row
	local numInk = Instance.new("UIStroke")
	numInk.Thickness = P(4)
	numInk.Color = INK
	numInk.Parent = num

	local icon = iconFor(itemName)
	local img
	if icon ~= "" then
		img = Instance.new("ImageLabel")
		img.LayoutOrder = 2
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(P(40), P(40))
		img.Image = icon
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = row
	end


	local info = TweenInfo.new(TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, {
		StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(dir * sideAmount, RISE, 0),
	}):Play()
	-- гаснем во второй половине полёта, чтобы число успели прочитать
	local fade = TweenInfo.new(TIME * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, TIME * 0.5)
	TweenService:Create(num, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(numInk, fade, { Transparency = 1 }):Play()
	if img then TweenService:Create(img, fade, { ImageTransparency = 1 }):Play() end

	lastByItem[itemName] = { at = os.clock(), label = num, amount = amount }

	task.delay(TIME + 0.05, function()
		bb:Destroy()
		live = math.max(0, live - 1)
		if lastByItem[itemName] and lastByItem[itemName].label == num then
			lastByItem[itemName] = nil
		end
	end)
end

-- ответ сервера StoneAxe на удар: ("drops", { [ресурс] = сколько }, здоровье дерева)
local chopEvent = ReplicatedStorage:WaitForChild("ChopTree", 30)
if chopEvent then
	chopEvent.OnClientEvent:Connect(function(action, drops)
		if action ~= "drops" or type(drops) ~= "table" then return end
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if not head then return end
		for itemName, count in pairs(drops) do
			local n = math.floor(tonumber(count) or 0)
			if type(itemName) == "string" and n > 0 then popGain(head, itemName, n) end
		end
	end)
	print("[Добыча] всплывающее «+N» над головой готово (только топор, ChopTree)")
else
	warn("[Добыча] ChopTree не появился за 30 с — всплывающих «+N» не будет")
end
