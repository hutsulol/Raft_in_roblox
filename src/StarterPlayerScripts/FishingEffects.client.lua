--[[
	УЛОВ ПРОДАН — попап над ящиком улова (хендофф design_handoff_fish_sell).
	Свечение редкости (лучи крутятся, мягкое пятно пульсирует) → 3D-рыба
	крутится → вес → название цветом редкости → «+выручка» с монетой.

	Висит в мире: BillboardGui с размером в студах, поэтому он не раздувается
	при приближении — просто предмет над ящиком. Вёрстка нарисована в
	пикселях на холсте CANVAS и подгоняется под размер билборда (UIScale).

	Деньги выдаёт только сервер (FishingService); данные рыб и модели — FishData.
	Событие FishingSale: (ящик улова, запасная позиция, выручка, вес кг, id рыбы).
]]

local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Tween = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local event = RS:WaitForChild("FishingSale")
local FishData = require(RS:WaitForChild("FishData"))
local Assets = require(RS:WaitForChild("FishSellAssets"))

local OUTLINE = Color3.fromHex("0D2A4F")
local GOLD = Color3.fromHex("FFD95A")
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local SHOW_TIME = 3.6
local NAME_BASE = 30
local CANVAS = Vector2.new(240, 330)     -- холст вёрстки, px
local STUDS = 4.2                         -- ширина попапа в мире, студы
local LIFT = 0.4                          -- зазор над ящиком, студы

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function stroke(p, th)
	new("UIStroke", { Color = OUTLINE, Thickness = th, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, p)
end
local function label(p, size, color, order)
	return new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextSize = size, TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = order }, p)
end

-- рыба в ViewportFrame: клон модели, камера подогнана под габарит
local function fishViewport(parent, fish)
	local vp = new("ViewportFrame", { Name = "Fish", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(150, 150), ZIndex = 3,
		Ambient = Color3.fromRGB(170, 170, 170), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1) }, parent)
	local src = FishData.ModelFor(fish) or RS:FindFirstChild("FishermanFish")
	if not src then return vp, nil end
	local obj = src:Clone()
	for _, d in ipairs(obj:GetDescendants()) do if d:IsA("BaseScript") then d:Destroy() end end
	local model = obj
	if obj:IsA("BasePart") then
		model = Instance.new("Model")
		obj.Parent = model
		model.PrimaryPart = obj
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	local cf, size = model:GetBoundingBox()
	-- центр модели — в начало координат, вращение вокруг него
	local offset = cf:ToObjectSpace(model:GetPivot())
	--[[ Ставим рыбу «боком»: самая длинная ось — горизонтально (X), средняя
	     (высота тела) — вверх. Импорт пака мог положить длину по любой оси, и
	     тогда рыба крутилась вокруг собственной длины — видно было только морду. ]]
	local axes = { { Vector3.xAxis, size.X }, { Vector3.yAxis, size.Y }, { Vector3.zAxis, size.Z } }
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local upright = CFrame.fromMatrix(Vector3.zero, axes[1][1], -axes[2][1]):Inverse()   -- спиной вверх: у пака «верх» рыбы смотрит в −ось
	offset = upright * offset
	model.Parent = vp
	local cam = new("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	local radius = size.Magnitude / 2
	local dist = radius / math.sin(math.rad(cam.FieldOfView / 2)) * 0.95
	--[[ ⚠️ КРУТИТСЯ КАМЕРА, А НЕ РЫБА. ViewportFrame перерисовывает сдвинутую
	     модель не каждый кадр — рыба вертелась рывками, «как на 10 FPS». Смена
	     камеры рисуется каждый кадр, поэтому рыба стоит, а камера (и свет вместе
	     с ней, чтобы освещение не гуляло) облетает её по кругу. ]]
	model:PivotTo(offset)
	local light = Vector3.new(-1, -1, -1)
	local function view(angle, bob)
		local rot = CFrame.Angles(0, -angle, 0)
		local lift = -bob * radius
		cam.CFrame = rot * CFrame.lookAt(Vector3.new(0, radius * 0.25 + lift, dist), Vector3.new(0, lift, 0))
		vp.LightDirection = rot:VectorToWorldSpace(light)
	end
	view(0, 0)
	return vp, view
end

local current = {}   -- ящик/позиция → живой попап (новый заменяет старый)

event.OnClientEvent:Connect(function(box, position, pay, weight, fishId)
	if type(pay) ~= "number" or pay ~= pay or pay <= 0 or pay == math.huge then return end
	local fish = FishData.FishById[fishId] or FishData.Fish[1]
	local rar = FishData.RarityById[fish.rarity] or FishData.Rarities[1]
	local key = typeof(box) == "Instance" and box or "pos"
	if current[key] then current[key]() end

	-- куда цепляться: сам ящик (едет с плотом), иначе невидимый якорь в точке
	local anchor, ownAnchor = nil, false
	if typeof(box) == "Instance" and box:IsA("BasePart") and box.Parent then
		anchor = box
	elseif typeof(position) == "Vector3" then
		anchor = new("Part", { Name = "FishingSaleFX", Size = Vector3.new(0.1, 0.1, 0.1), Anchored = true, Transparency = 1,
			CanCollide = false, CanTouch = false, CanQuery = false, Position = position }, workspace)
		ownAnchor = true
	else
		return
	end
	local h = STUDS * CANVAS.Y / CANVAS.X
	local up = (ownAnchor and 0 or anchor.Size.Y / 2) + LIFT + h / 2
	local gui = new("BillboardGui", { Name = "FishSellPopup", Adornee = anchor, Size = UDim2.fromScale(STUDS, h),
		StudsOffsetWorldSpace = Vector3.new(0, up, 0), AlwaysOnTop = true, MaxDistance = 150, LightInfluence = 0,
		ResetOnSpawn = false }, ownAnchor and anchor or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"))

	-- холст фиксированного размера → растягивается под билборд
	local canvas = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y) }, gui)
	local fit = new("UIScale", {}, canvas)
	local root = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 1) }, canvas)
	local pop = new("UIScale", { Scale = 0.3 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, root)

	-- сцена 240×180: лучи + мягкое свечение + рыба
	local stage = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 180), LayoutOrder = 1 }, root)
	local function centered(name, size, image, z)
		return new("ImageLabel", { Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), Image = image,
			ImageColor3 = rar.glow, ZIndex = z }, stage)
	end
	local rays = centered("Rays", 260, Assets.GlowRays, 1)
	local soft = centered("Soft", 195, Assets.GlowSoft, 2)
	local _, spinFish = fishViewport(stage, fish)

	-- вес: белая плашка
	local pill = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0), LayoutOrder = 2 }, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
	new("UIStroke", { Color = OUTLINE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, pill)
	label(pill, 22, OUTLINE, 1).Text = FishData.Format(type(weight) == "number" and weight or 0) .. " кг"

	-- название цветом редкости, ширина = ширине строки прибыли
	local payText = "+" .. FishData.Format(pay)
	local name = label(root, NAME_BASE, rar.text, 3)
	name.Text = fish.name
	stroke(name, 3)
	local big = Vector2.new(9999, 9999)
	local payW = TextService:GetTextSize(payText, 42, Enum.Font.FredokaOne, big).X + 6 + 40
	local nameW = TextService:GetTextSize(fish.name, NAME_BASE, Enum.Font.FredokaOne, big).X
	if nameW > 0 then name.TextSize = math.clamp(math.floor(NAME_BASE * payW / nameW), 16, NAME_BASE + 6) end

	-- прибыль: +X,XX и монета
	local payRow = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0), LayoutOrder = 4 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, payRow)
	local payLabel = label(payRow, 42, GOLD, 1)
	payLabel.Text = payText
	stroke(payLabel, 4)
	new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Image = Assets.CoinPirate, LayoutOrder = 2 }, payRow)

	-- анимации: одна петля на попап
	local t0 = os.clock()
	local conn = Run.RenderStepped:Connect(function()
		fit.Scale = gui.AbsoluteSize.X / CANVAS.X
		local t = os.clock() - t0
		rays.Rotation = (t / rar.spin * 360) % 360
		local k = 0.5 - 0.5 * math.cos(t / 1.6 * math.pi * 2)       -- пульс 1.6 с
		local s = 0.82 + 0.30 * k
		soft.Size = UDim2.fromOffset(195 * s, 195 * s)
		soft.ImageTransparency = 0.45 * (1 - k)
		if spinFish then
			local a = t / 3.2 * math.pi * 2                          -- оборот рыбы 3.2 с
			spinFish(a, 0.08 * math.abs(math.sin(a)))
		end
	end)

	local done = false
	local function close()
		if done then return end
		done = true
		if current[key] == close then current[key] = nil end
		conn:Disconnect()
		gui:Destroy()
		if ownAnchor then anchor:Destroy() end
	end
	current[key] = close

	Tween:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(SHOW_TIME, function()
		if done then return end
		local tw = Tween:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw:Play()
		tw.Completed:Wait()
		close()
	end)
end)
