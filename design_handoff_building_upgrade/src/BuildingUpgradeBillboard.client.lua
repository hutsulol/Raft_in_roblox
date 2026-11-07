-- StarterPlayerScripts/BuildingUpgradeBillboard (LocalScript)
-- Вешает табличку над каждой постройкой с тегом "UpgradableBuilding" и держит её в актуальном состоянии.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Data = require(ReplicatedStorage:WaitForChild("BuildingUpgradeData"))
local Assets = require(ReplicatedStorage:WaitForChild("BuildingUpgradeAssets"))
local Upgrade = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeBuilding")
local player = Players.LocalPlayer

local C = {
	outline = Color3.fromHex("0D2A4F"), glassTop = Color3.fromHex("1F4F8F"), glassBot = Color3.fromHex("143A6B"), glassStroke = Color3.fromHex("A9D6F7"),
	blueTop = Color3.fromHex("54A7EC"), blueBot = Color3.fromHex("3A7FD0"), blueBorder = Color3.fromHex("1C4F8F"), blueFlat = Color3.fromHex("2E6BB4"),
	greenTop = Color3.fromHex("6FF08A"), greenBot = Color3.fromHex("34B84E"), greenBorder = Color3.fromHex("1F7A33"),
	goldTop = Color3.fromHex("FFE38A"), goldBot = Color3.fromHex("F5B73C"), goldBorder = Color3.fromHex("B07A14"),
	gold = Color3.fromHex("FFD95A"), red = Color3.fromHex("FF8A7E"), badge = Color3.fromHex("E84A3A"), track = Color3.fromHex("143A6B"),
}
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local function new(class, props, parent) local i = Instance.new(class); for k, v in pairs(props) do i[k] = v end; i.Parent = parent; return i end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function border(p, color, t) return new("UIStroke", { Color = color, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p) end
local function grad(p, a, b) return new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = 90 }, p) end
local function text(p, size, color, strokeT, order)
	local t = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = size, TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = order or 0 }, p)
	if strokeT then new("UIStroke", { Color = C.outline, Thickness = strokeT, LineJoinMode = Enum.LineJoinMode.Round }, t) end
	return t
end
local function hlist(p, pad) return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, pad), SortOrder = Enum.SortOrder.LayoutOrder }, p) end

local function build(model: Model)
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"); if not adornee then return end
	local size = model:GetExtentsSize()

	local bb = new("BillboardGui", { Name = "UpgradeBillboard", Adornee = adornee, AlwaysOnTop = true, LightInfluence = 0,
		Size = UDim2.fromOffset(260, 100), StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 3, 0), MaxDistance = 60, ResetOnSpawn = false },
		player:WaitForChild("PlayerGui"))

	local col = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, bb)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, -9), SortOrder = Enum.SortOrder.LayoutOrder }, col)

	-- название: золотая плашка, наклон −2°
	local nameTag = new("Frame", { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Rotation = -2, LayoutOrder = 1, ZIndex = 3, BackgroundColor3 = Color3.new(1, 1, 1) }, col)
	corner(nameTag, 12); border(nameTag, C.outline, 3); grad(nameTag, C.goldTop, C.goldBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 5) }, nameTag)
	local nameLabel = text(nameTag, 17, Color3.new(1, 1, 1), 2.5); nameLabel.ZIndex = 3

	-- стеклянная плашка
	local plate = new("Frame", { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15 }, col)
	corner(plate, 16); grad(plate, C.glassTop, C.glassBot)
	new("UIStroke", { Color = C.glassStroke, Thickness = 3, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, plate)
	hlist(plate, 6)

	-- уровень
	local lvlBox = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(40, 40), LayoutOrder = 1, BackgroundColor3 = Color3.new(1, 1, 1) }, plate)
	corner(lvlBox, 11); local lvlStroke = border(lvlBox, C.blueBorder, 3); local lvlGrad = grad(lvlBox, C.blueTop, C.blueBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, lvlBox); hlist(lvlBox, 3).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local lvlCap = text(lvlBox, 10, Color3.fromHex("CFE6FA"), nil, 1); lvlCap.Text = "УР"
	local lvlNum = text(lvlBox, 20, Color3.new(1, 1, 1), 1.5, 2)

	-- множитель
	local mult = text(plate, 24, C.gold, 3, 2)

	-- кнопка-молоток
	local btn = new("TextButton", { Text = "", AutoButtonColor = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 3, BackgroundColor3 = Color3.new(1, 1, 1) }, plate)
	corner(btn, 11); local btnStroke = border(btn, C.greenBorder, 3); local btnGrad = grad(btn, C.greenTop, C.greenBot)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }, btn); hlist(btn, 6)
	new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Hammer, Size = UDim2.fromOffset(24, 24), LayoutOrder = 1 }, btn)
	new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Coin, Size = UDim2.fromOffset(15, 15), LayoutOrder = 2 }, btn)
	local cost = text(btn, 15, Color3.new(1, 1, 1), 1.5, 3)
	local bang = new("TextLabel", { Text = "!", FontFace = FONT, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = C.badge,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 4 }, btn)
	corner(bang, 8); border(bang, Color3.new(1, 1, 1), 2)

	-- прогресс сборки
	local prog = new("Frame", { Size = UDim2.fromOffset(96, 40), LayoutOrder = 3, BackgroundColor3 = C.track, ClipsDescendants = true, Visible = false }, plate)
	corner(prog, 11); border(prog, C.outline, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, prog); grad(fill, C.goldTop, C.goldBot)
	local pct = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 2 }, prog)
	new("UIStroke", { Color = C.outline, Thickness = 2 }, pct)

	-- стрелка вниз (ImageLabel треугольника)
	new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.Pointer, ImageColor3 = C.glassBot, Size = UDim2.fromOffset(18, 10), LayoutOrder = 3 }, col)

	local function coins() local ls = player:FindFirstChild("leaderstats"); local c = ls and ls:FindFirstChild("Coins"); return c and c.Value or 0 end

	local function refresh()
		local lvl = model:GetAttribute("Level") or 0
		local building = model:GetAttribute("Building") == true
		local isMax = lvl >= Data.MaxLevel
		local price = Data.Costs[lvl]
		local enough = not isMax and coins() >= price

		nameLabel.Text = model:GetAttribute("BuildingName") or model.Name
		lvlNum.Text = tostring(lvl)
		mult.Text = Data.FormatMult(Data.Mults[lvl])
		if isMax then
			lvlGrad.Color = ColorSequence.new(C.goldTop, C.goldBot); lvlStroke.Color = C.goldBorder
		else
			lvlGrad.Color = ColorSequence.new(C.blueTop, C.blueBot); lvlStroke.Color = C.blueBorder
		end

		btn.Visible = not isMax and not building
		prog.Visible = building
		if btn.Visible then
			cost.Text = Data.FormatNum(price)
			bang.Visible = enough
			btnGrad.Color = enough and ColorSequence.new(C.greenTop, C.greenBot) or ColorSequence.new(C.blueFlat, C.blueFlat)
			btnStroke.Color = enough and C.greenBorder or C.blueBorder
			cost.TextColor3 = enough and Color3.new(1, 1, 1) or C.red
		end
	end

	btn.Activated:Connect(function()
		if bang.Visible then
			Upgrade:FireServer(model)
			local s = new("UIScale", {}, btn)
			TweenService:Create(s, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
			task.delay(0.08, function() TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play(); task.delay(0.2, function() s:Destroy() end) end)
		end
	end)

	local hb = RunService.Heartbeat:Connect(function()
		if prog.Visible then
			local t0 = model:GetAttribute("BuildStart") or workspace:GetServerTimeNow()
			local p = math.clamp((workspace:GetServerTimeNow() - t0) / Data.BuildTime, 0, 1)
			fill.Size = UDim2.fromScale(p, 1)
			pct.Text = math.floor(p * 100) .. "%"
		end
	end)

	for _, a in ipairs({ "Level", "Building", "BuildingName" }) do model:GetAttributeChangedSignal(a):Connect(refresh) end
	local ls = player:WaitForChild("leaderstats", 10)
	if ls and ls:FindFirstChild("Coins") then ls.Coins.Changed:Connect(refresh) end
	model.AncestryChanged:Connect(function(_, parent) if not parent then hb:Disconnect(); bb:Destroy() end end)
	refresh()
end

for _, m in ipairs(CollectionService:GetTagged("UpgradableBuilding")) do task.spawn(build, m) end
CollectionService:GetInstanceAddedSignal("UpgradableBuilding"):Connect(build)
