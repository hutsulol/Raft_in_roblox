-- StarterPlayerScripts/FishSellPopup (LocalScript)
-- Слушает RemoteEvent ReplicatedStorage.Remotes.FishSold(fishId, weight, pay)
-- и показывает попап: свечение (крутится + пульсирует) → рыба (крутится) → вес → название → прибыль.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local FishData = require(ReplicatedStorage:WaitForChild("FishData"))
local Assets = require(ReplicatedStorage:WaitForChild("FishSellAssets"))
local FishSold = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FishSold")

local OUTLINE = Color3.fromHex("0D2A4F")
local GOLD = Color3.fromHex("FFD95A")
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local SHOW_TIME = 2.6
local NAME_BASE = 30

local gui = Instance.new("ScreenGui")
gui.Name = "FishSellPopup"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function stroke(parent, thickness)
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function label(parent, size, color, order)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FONT
	t.TextSize = size
	t.TextColor3 = color
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function build()
	-- корень: колонка по центру, слева над полосками здоровья
	local root = Instance.new("Frame")
	root.Name = "Popup"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 40, 1, -230)
	root.Size = UDim2.fromOffset(240, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Parent = gui
	local scale = Instance.new("UIScale"); scale.Parent = root

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = root

	-- сцена 240×180: лучи + мягкое свечение + рыба
	local stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromOffset(240, 180)
	stage.LayoutOrder = 1
	stage.Parent = root

	local function centered(name, size, image, z)
		local i = Instance.new("ImageLabel")
		i.Name = name
		i.BackgroundTransparency = 1
		i.AnchorPoint = Vector2.new(0.5, 0.5)
		i.Position = UDim2.fromScale(0.5, 0.5)
		i.Size = UDim2.fromOffset(size, size)
		i.Image = image
		i.ZIndex = z
		i.Parent = stage
		return i
	end
	local rays = centered("Rays", 260, Assets.GlowRays, 1)
	local soft = centered("Soft", 195, Assets.GlowSoft, 2)
	local fish = centered("Fish", 150, "", 3)
	fish.ScaleType = Enum.ScaleType.Fit

	-- вес: белая плашка
	local weightPill = Instance.new("Frame")
	weightPill.BackgroundColor3 = Color3.new(1, 1, 1)
	weightPill.AutomaticSize = Enum.AutomaticSize.XY
	weightPill.Size = UDim2.fromOffset(0, 0)
	weightPill.LayoutOrder = 2
	weightPill.Parent = root
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = weightPill
	local ws = Instance.new("UIStroke"); ws.Color = OUTLINE; ws.Thickness = 3; ws.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ws.Parent = weightPill
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12); p.PaddingTop = UDim.new(0, 3); p.PaddingBottom = UDim.new(0, 3)
	p.Parent = weightPill
	local weight = label(weightPill, 22, OUTLINE, 1)

	-- название (ширина = ширина строки прибыли)
	local name = label(root, NAME_BASE, Color3.new(1, 1, 1), 3)
	stroke(name, 3)

	-- прибыль: +X,XX + монета
	local payRow = Instance.new("Frame")
	payRow.BackgroundTransparency = 1
	payRow.AutomaticSize = Enum.AutomaticSize.XY
	payRow.Size = UDim2.fromOffset(0, 0)
	payRow.LayoutOrder = 4
	payRow.Parent = root
	local pl = Instance.new("UIListLayout")
	pl.FillDirection = Enum.FillDirection.Horizontal
	pl.VerticalAlignment = Enum.VerticalAlignment.Center
	pl.Padding = UDim.new(0, 6)
	pl.Parent = payRow
	local pay = label(payRow, 42, GOLD, 1)
	stroke(pay, 4)
	local coin = Instance.new("ImageLabel")
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.fromOffset(40, 40)
	coin.Image = Assets.CoinPirate
	coin.LayoutOrder = 2
	coin.Parent = payRow

	return {
		root = root, scale = scale, rays = rays, soft = soft, fish = fish,
		weight = weight, name = name, pay = pay, payRow = payRow,
	}
end

local ui = build()
ui.root.Visible = false

-- подгон размера названия под ширину строки прибыли
local function fitName(text)
	ui.name.Text = text
	local payW = ui.payRow.AbsoluteSize.X / math.max(ui.scale.Scale, 0.01)
	local nameW = TextService:GetTextSize(text, NAME_BASE, Enum.Font.FredokaOne, Vector2.new(9999, 9999)).X
	if nameW > 0 and payW > 0 then
		ui.name.TextSize = math.clamp(math.floor(NAME_BASE * payW / nameW), 10, NAME_BASE * 2)
	end
end

-- анимации (одна петля на RenderStepped)
local t0, spin = 0, 7
RunService.RenderStepped:Connect(function()
	if not ui.root.Visible then return end
	local t = os.clock() - t0
	ui.rays.Rotation = (t / spin * 360) % 360                     -- лучи крутятся
	local k = 0.5 - 0.5 * math.cos(t / 1.6 * math.pi * 2)        -- пульс 1.6 c
	local s = 0.82 + 0.30 * k
	ui.soft.Size = UDim2.fromOffset(195 * s, 195 * s)
	ui.soft.ImageTransparency = 0.45 * (1 - k)
	-- рыба «вертится» вокруг Y: сжатие по X + лёгкий подскок, оборот 3.2 c
	local a = t / 3.2 * math.pi * 2
	ui.fish.Size = UDim2.fromOffset(150 * math.max(math.abs(math.cos(a)), 0.05), 150)
	ui.fish.Position = UDim2.new(0.5, 0, 0.5, -6 * math.abs(math.sin(a)))
end)

local hideToken = 0
local function show(fishId: string, weight: number, pay: number)
	local f = FishData.FishById[fishId]; if not f then return end
	local r = FishData.RarityById[f.rarity]

	ui.fish.Image = f.image
	ui.rays.ImageColor3 = r.glow
	ui.soft.ImageColor3 = r.glow
	ui.name.TextColor3 = r.text
	ui.weight.Text = FishData.Format(weight) .. " кг"
	ui.pay.Text = "+" .. FishData.Format(pay)
	spin = r.spin
	t0 = os.clock()

	ui.root.Visible = true
	task.defer(function() fitName(f.name) end) -- после пересчёта AutomaticSize

	-- pop-in
	ui.scale.Scale = 0.3
	TweenService:Create(ui.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	hideToken += 1
	local my = hideToken
	task.delay(SHOW_TIME, function()
		if my ~= hideToken then return end
		local tw = TweenService:Create(ui.scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw:Play(); tw.Completed:Wait()
		if my == hideToken then ui.root.Visible = false end
	end)
end

FishSold.OnClientEvent:Connect(show)
