local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[ IslandQuestCard — КАРТОЧКА «ЗАЧИСТИ ОСТРОВ»: ТАЙМЕР, ПОДСКАЗКИ, БОНУС.

     Состояние шлёт IslandQuestSystem.server.lua (ремоут IslandQuest). Карточка
     в стиле HUD-трекера (TrackerCard.client) встаёт ПОД ним, пока игрок рядом
     с враждебным островом:
       • первые три минуты вместо «?» — красный таймер: успел — бонус;
       • таймер вышел — появляется «?», и по нему идут пошаговые подсказки:
           1) пираты — подсвечен ОДИН (ближайший живой), убил — подсвечен
              следующий; на баре «осталось 3 из 5»;
           2) бочки (если сценарий держит зачистку полем) — зелёная стрелка
              над одной бочкой, «Взорви бочку»;
           3) поля — стрелка над одним кустом, «Сожги поле». Стрелка переезжает
              на новую цель не чаще раза в SWITCH_DELAY секунд: кусты сгорают
              почти разом, и без задержки указатель метался бы по полю.
       • бонус: над головой победителя у ВСЕХ игроков растёт белое число с
         монетой (1 → 30) и подпись «Дополнительная награда получена». ]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local remote = ReplicatedStorage:WaitForChild("IslandQuest", 60)
if not remote then
	warn("[ОстровКвест/клиент] ремоут IslandQuest не появился — карточки не будет")
	return
end

-- ── геометрия/палитра: та же, что у HUD-трекера ──
local TRACKER_W = 300
local MARGIN_X, MARGIN_Y = 14, 10
local UNDER_TRACKER = 64      -- смещение вниз, когда трекер квестов виден
local TITLE_H = 28
local BAR_H = 13
local BAR_Y = TITLE_H + 8
local BLUE       = Color3.fromRGB(74, 144, 220)
local FILL_TOP   = Color3.fromRGB(111, 220, 95)
local FILL_MID   = Color3.fromRGB(53, 180, 53)
local FILL_DARK  = Color3.fromRGB(31, 122, 36)
local TIMER_RED  = Color3.fromRGB(255, 107, 90)
local GOLD       = Color3.fromRGB(255, 210, 58)
local LOG_GREEN  = Color3.fromRGB(70, 235, 90)
local FONT       = Enum.Font.GothamBlack
local ARROW_ICON = "rbxassetid://78628006161298"
local COIN_ICON  = "rbxassetid://93617165412571"

local SHOW_RANGE   = 260    -- студов от края суши, на которых карточка видна
local SWITCH_DELAY = 5      -- секунд между переездами стрелки на новую цель
local RESCAN       = 0.5
local ENEMIES      = "Enemies"
local DRUM_NAME    = "Virus_drum"
local CROP_NAME    = "Virus_crop_sm"

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ── UI ──
local screenGui = new("ScreenGui", {
	Name = "IslandQuestGui", ResetOnSpawn = false, IgnoreGuiInset = false,
	DisplayOrder = 81, Enabled = false,
}, playerGui)

local container = new("Frame", {
	Name = "Card", Position = UDim2.new(0, MARGIN_X, 0, MARGIN_Y + UNDER_TRACKER),
	Size = UDim2.fromOffset(TRACKER_W, BAR_Y + BAR_H + 4),
	BackgroundTransparency = 1, BorderSizePixel = 0,
}, screenGui)
do
	local ok, Hud = pcall(function() return require(ReplicatedStorage:WaitForChild("HudScale", 10)) end)
	if ok and Hud and Hud.applyScaleLive then pcall(Hud.applyScaleLive, container, Hud.trackerFactor) end
end

local titleRow = new("Frame", { Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundTransparency = 1 }, container)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 9),
}, titleRow)

local title = new("TextLabel", {
	LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, TITLE_H),
	BackgroundTransparency = 1, Font = FONT, TextSize = 23, TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left, Text = "", TextTruncate = Enum.TextTruncate.AtEnd,
}, titleRow)
new("UISizeConstraint", { MaxSize = Vector2.new(TRACKER_W - 90, TITLE_H) }, title)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5 }, title)

local helpWrap = new("Frame", { LayoutOrder = 2, Size = UDim2.fromOffset(26, 29), BackgroundTransparency = 1, Visible = false }, titleRow)
local helpShadow = new("Frame", {
	Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, helpShadow)
local helpAura = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(13, 13),
	Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(90, 180, 255),
	BackgroundTransparency = 0.5, BorderSizePixel = 0, Visible = false, ZIndex = 0,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, helpAura)
local helpAuraTween = TweenService:Create(helpAura,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.1, Size = UDim2.fromOffset(42, 42) })
local helpBtn = new("TextButton", {
	Size = UDim2.fromOffset(26, 26), BackgroundColor3 = BLUE, Text = "?", Font = FONT, TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true, ZIndex = 2,
}, helpWrap)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, helpBtn)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, helpBtn)
local helpScale = new("UIScale", { Scale = 1 }, helpBtn)
local helpBreath = TweenService:Create(helpScale,
	TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 })

local timerLabel = new("TextLabel", {
	LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, TITLE_H),
	BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextColor3 = TIMER_RED, Text = "", Visible = false,
}, titleRow)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, timerLabel)

local COUNTER_W = 130
local track = new("Frame", {
	Position = UDim2.new(0, 0, 0, BAR_Y), Size = UDim2.new(1, -(COUNTER_W + 10), 0, BAR_H),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ClipsDescendants = true,
}, container)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, track)
local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = FILL_MID, BorderSizePixel = 0 }, track)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, FILL_TOP), ColorSequenceKeypoint.new(0.5, FILL_MID), ColorSequenceKeypoint.new(1, FILL_DARK),
	}),
}, fill)
local counter = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, BAR_Y - 4),
	Size = UDim2.fromOffset(COUNTER_W, 20), BackgroundTransparency = 1,
	Font = FONT, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Right, Text = "",
}, container)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, counter)

-- ── состояние ──
local islands = {}     -- [model] = снимок с сервера
local current = nil    -- снимок острова, который показываем
local hintOn  = false

local function fmtSeconds(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function setHelp(on)
	if on then
		helpAura.Visible = true; helpAuraTween:Play(); helpBreath:Cancel(); helpScale.Scale = 1
	else
		helpAuraTween:Cancel(); helpAura.Visible = false; helpAura.BackgroundTransparency = 0.5
		helpAura.Size = UDim2.fromOffset(34, 34); helpBreath:Play()
	end
end

local function setBar(pct)
	pct = math.clamp(pct, 0, 1)
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(pct, 0, 1, 0) }):Play()
end

local function paint(s)
	if s.stage == "pirates" then
		title.Text = "Перебей пиратов"
		setBar(s.total > 0 and s.killed / s.total or 0)
		counter.Text = ("осталось %d из %d"):format(s.alive, s.total)
	elseif s.stage == "barrels" then
		title.Text = "Взорви бочки"
		setBar(s.cropsTotal > 0 and (s.cropsTotal - s.cropsLeft) / s.cropsTotal or 0)
		counter.Text = ("бочек: %d"):format(s.drums)
	elseif s.stage == "crops" then
		title.Text = "Выжги поля"
		setBar(s.cropsTotal > 0 and (s.cropsTotal - s.cropsLeft) / s.cropsTotal or 0)
		counter.Text = ("осталось %d из %d"):format(s.cropsLeft, s.cropsTotal)
	elseif s.stage == "done" then
		title.Text = s.bonus and ("Остров зачищен! +" .. s.bonus) or "Остров зачищен!"
		setBar(1); counter.Text = s.winner and ("бонус: " .. s.winner) or ""
	else
		title.Text = "Зачистка острова…"
		setBar(1); counter.Text = ""
	end
	local live = not s.done
	timerLabel.Visible = live and not s.expired
	helpWrap.Visible = live and s.expired
	if not helpWrap.Visible and hintOn then hintOn = false; setHelp(false) end
	if helpWrap.Visible and not hintOn then helpBreath:Play() end
end

-- позиция: под трекером квестов, если он на экране
local function placeCard()
	local tracker = playerGui:FindFirstChild("QuestTrackerGui")
	local y = (tracker and tracker.Enabled) and (MARGIN_Y + UNDER_TRACKER) or MARGIN_Y
	container.Position = UDim2.new(0, MARGIN_X, 0, y)
end

-- ── подсветка и стрелка ──
local hl = new("Highlight", {
	Name = "IslandQuestGlow", FillColor = GOLD, FillTransparency = 0.75, OutlineColor = GOLD,
	OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false,
}, Workspace)

local arrowBB = new("BillboardGui", {
	Name = "IslandQuestArrow", Size = UDim2.fromScale(7, 5), AlwaysOnTop = true,
	LightInfluence = 0, MaxDistance = 500, Enabled = false, StudsOffset = Vector3.new(0, 4, 0),
}, playerGui)
new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.42, 0.62),
	BackgroundTransparency = 1, Image = ARROW_ICON, ScaleType = Enum.ScaleType.Fit,
}, arrowBB)
local arrowText = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.3),
	BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = LOG_GREEN, Text = "",
}, arrowBB)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, arrowText)
local arrowBob = TweenService:Create(arrowBB,
	TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ StudsOffset = Vector3.new(0, 4.8, 0) })

local target, targetKind, lastSwitch = nil, nil, 0

local function clearHint()
	target, targetKind = nil, nil
	hl.Adornee = nil; hl.Enabled = false
	arrowBB.Adornee = nil; arrowBB.Enabled = false; arrowBob:Cancel()
end

local function showHint(inst, adornPart, label, glow)
	target = inst
	hl.Adornee = glow and inst or nil; hl.Enabled = glow == true
	arrowBB.Adornee = adornPart; arrowText.Text = label
	if not arrowBB.Enabled then arrowBB.Enabled = true; arrowBob:Play() end
end

local function myPos()
	local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position
end

local function nearestOf(list, pos)
	local best, bestD
	for _, inst in ipairs(list) do
		local p = inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position
		local d = pos and (p - pos).Magnitude or 0
		if not bestD or d < bestD then best, bestD = inst, d end
	end
	return best
end

local function aliveEnemies(island)
	local out = {}
	local f = island:FindFirstChild(ENEMIES)
	if not f then return out end
	for _, m in ipairs(f:GetChildren()) do
		local h = m:IsA("Model") and m:FindFirstChildWhichIsA("Humanoid")
		if h and h.Health > 0 and m:FindFirstChild("HumanoidRootPart") then table.insert(out, m) end
	end
	return out
end

local function partsOf(island, prefix, skipAttr)
	local out = {}
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, #prefix) == prefix and not d:GetAttribute(skipAttr) then
			table.insert(out, d)
		end
	end
	return out
end

local function applyHint()
	if not (hintOn and current and current.expired and not current.done and current.island and current.island.Parent) then
		clearHint(); return
	end
	local island, stage, pos = current.island, current.stage, myPos()
	local now = os.clock()
	if stage == "pirates" then
		local h = target and target:FindFirstChildWhichIsA("Humanoid")
		if targetKind == "pirate" and target and target.Parent and h and h.Health > 0 then return end
		local cand = nearestOf(aliveEnemies(island), pos)
		if cand then targetKind = "pirate"; showHint(cand, cand:FindFirstChild("HumanoidRootPart"), "", true)   -- подпись убрана: стрелка и подсветка говорят сами
		else clearHint() end
	elseif stage == "barrels" or stage == "crops" then
		local prefix, skip, label = DRUM_NAME, "Exploded", "Взорви бочку"
		if stage == "crops" then prefix, skip, label = CROP_NAME, "Burnt", "Сожги поле" end
		local ok = targetKind == stage and target and target.Parent and not target:GetAttribute(skip)
		if ok then return end
		-- цель пропала: новую ставим не раньше, чем через SWITCH_DELAY после прошлой
		if targetKind == stage and now - lastSwitch < SWITCH_DELAY then
			hl.Enabled = false; arrowBB.Enabled = false
			return
		end
		local cand = nearestOf(partsOf(island, prefix, skip), pos)
		if cand then
			targetKind = stage; lastSwitch = now
			showHint(cand, cand, label, false)
		else clearHint() end
	else
		clearHint()
	end
end

helpBtn.MouseButton1Click:Connect(function()
	if not (current and current.expired and not current.done) then return end
	hintOn = not hintOn
	setHelp(hintOn)
	applyHint()
end)

-- ── выбор острова и показ ──
local function islandDistance(island)
	local pos = myPos()
	if not pos then return math.huge end
	local c = island:GetAttribute("LandCenter")
	if typeof(c) ~= "Vector3" then c = island:GetPivot().Position end
	local r = tonumber(island:GetAttribute("LandRadius")) or 300
	return (Vector3.new(c.X, 0, c.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude - r
end

local visible = false
local OPEN_INFO  = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function setVisible(on)
	if on == visible then return end
	visible = on
	if on then
		screenGui.Enabled = true
		placeCard()
		local dest = container.Position
		container.Position = UDim2.new(0, -TRACKER_W - 20, 0, dest.Y.Offset)
		TweenService:Create(container, OPEN_INFO, { Position = dest }):Play()
	else
		screenGui.Enabled = false
		hintOn = false; setHelp(false); clearHint()
	end
end

task.spawn(function()
	while true do
		task.wait(RESCAN)
		local best, bestD
		for island, s in pairs(islands) do
			if island.Parent then
				local d = islandDistance(island)
				if d <= SHOW_RANGE and (not bestD or d < bestD) then best, bestD = s, d end
			else
				islands[island] = nil
			end
		end
		current = best
		if current then
			paint(current); placeCard(); setVisible(true); applyHint()
		else
			setVisible(false)
		end
	end
end)

-- таймер тикает между снимками сервера
RunService.Heartbeat:Connect(function()
	if not (visible and current and timerLabel.Visible) then return end
	timerLabel.Text = fmtSeconds(current.deadline - Workspace:GetServerTimeNow())
end)

-- ── бонус над головой: видят все ──
local function bonusPop(winner, coins)
	local char = winner and winner.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	local bb = new("BillboardGui", {
		Name = "IslandBonusPop", Size = UDim2.fromOffset(340, 110), AlwaysOnTop = true,
		LightInfluence = 0, MaxDistance = 140, StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0), Adornee = head,
	}, playerGui)
	local col = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bb)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
	}, col)
	local row = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, col)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
	}, row)
	local num = new("TextLabel", {
		LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 50), BackgroundTransparency = 1,
		Font = FONT, TextSize = 44, TextColor3 = Color3.new(1, 1, 1), Text = "+1",
	}, row)
	local numInk = new("UIStroke", { Color = Color3.fromRGB(20, 38, 26), Thickness = 4 }, num)
	local icon = new("ImageLabel", { LayoutOrder = 2, Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Image = COIN_ICON, ScaleType = Enum.ScaleType.Fit }, row)
	local sub = new("TextLabel", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
		Font = FONT, TextSize = 18, TextColor3 = GOLD, Text = "Дополнительная награда получена",
	}, col)
	local subInk = new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, sub)

	local COUNT, HOLD, FADE = 1.1, 2.4, 0.5
	TweenService:Create(bb, TweenInfo.new(COUNT + HOLD + FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0) }):Play()
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local k = math.min(1, (os.clock() - t0) / COUNT)
			local eased = 1 - (1 - k) * (1 - k)
			num.Text = "+" .. math.max(1, math.floor(coins * eased + 0.5))
			if k >= 1 then break end
			task.wait()
		end
		task.wait(HOLD)
		local fade = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(num, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(numInk, fade, { Transparency = 1 }):Play()
		TweenService:Create(icon, fade, { ImageTransparency = 1 }):Play()
		TweenService:Create(sub, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(subInk, fade, { Transparency = 1 }):Play()
		task.wait(FADE + 0.05)
		bb:Destroy()
	end)
end

-- наружу для трекера квестов: секунды до конца бонусного отсчёта (nil — не идёт)
_G.IslandQuestClock = function()
	if not (current and not current.done and not current.expired) then return nil end
	local left = current.deadline - Workspace:GetServerTimeNow()
	return left > 0 and left or nil
end

remote.OnClientEvent:Connect(function(action, a, b)
	if action == "state" and type(a) == "table" and a.island then
		islands[a.island] = a
		if current and current.island == a.island then current = a; paint(a); applyHint() end
	elseif action == "gone" and a then
		islands[a] = nil
	elseif action == "bonus" then
		bonusPop(a, tonumber(b) or 0)
	end
end)

print("[ОстровКвест/клиент] карточка зачистки готова (таймер → «?» с подсказками, бонус над головой)")
