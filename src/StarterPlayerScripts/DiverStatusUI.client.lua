-- DiverStatusUI.client.lua
-- Opened by clicking the monolith once the diver is working: a landscape card (same style as the
-- shop) showing the COUNTDOWN to the next crate + a SKIP button (free for now; wire to a Robux dev
-- product later). DiverStatusEvent drives it:
--   "open", secondsLeft → show the window and start the countdown
--   "skipped"           → timer skipped (crate incoming)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local statusEvent  = ReplicatedStorage:WaitForChild("DiverStatusEvent")
local DiverPreview = require(ReplicatedStorage:WaitForChild("DiverPreview"))
-- общая кнопка закрытия: одна на все меню океана (см. UITheme.closeButton)
local UITheme      = require(ReplicatedStorage:WaitForChild("UITheme"))

local C = {
	panelTop    = Color3.fromHex("54A7EC"),
	panelBg     = Color3.fromHex("3A7FD0"),
	panelBorder = Color3.fromHex("1C4F8F"),
	afford      = Color3.fromHex("4CD964"),
	gold        = Color3.fromHex("F5C95C"),
	white       = Color3.fromRGB(255, 255, 255),
}

local gui, panel, timerLbl, skipBtn
local secondsLeft = 0
local tickToken = 0

local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end
local function stroke(i, col, th) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = i; return s end

local function fmt(s)
	s = math.max(0, math.floor(s + 0.5))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function build()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "DiverStatusGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 41; gui.Enabled = false; gui.Parent = playerGui

	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""; backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0); backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.fromScale(1, 1); backdrop.ZIndex = 1; backdrop.Parent = gui

	panel = Instance.new("Frame")
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(568, 360); panel.BackgroundColor3 = C.panelBg
	panel.ZIndex = 2; panel.Parent = gui
	corner(panel, 18); stroke(panel, C.panelBorder, 3)
	local grad = Instance.new("UIGradient"); grad.Color = ColorSequence.new(C.panelTop, C.panelBg); grad.Rotation = 90; grad.Parent = panel

	local scale = Instance.new("UIScale"); scale.Parent = panel
	local function fit()
		local vp = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(vp.X / 620, vp.Y / 460), 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit); fit()

	-- RIGHT: live diver preview (working)
	DiverPreview.mount(panel)

	-- LEFT column
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(26, 18); title.Size = UDim2.fromOffset(300, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Font = Enum.Font.GothamBlack
	title.Text = "ДАЙВЕР РАБОТАЕТ"; title.TextSize = 24; title.TextColor3 = C.white; title.TextStrokeTransparency = 0.5
	title.ZIndex = 3; title.Parent = panel

	local subLbl = Instance.new("TextLabel")
	subLbl.BackgroundTransparency = 1; subLbl.Position = UDim2.fromOffset(26, 54); subLbl.Size = UDim2.fromOffset(300, 40)
	subLbl.TextXAlignment = Enum.TextXAlignment.Left; subLbl.TextYAlignment = Enum.TextYAlignment.Top
	subLbl.Font = Enum.Font.GothamMedium; subLbl.TextWrapped = true
	subLbl.Text = "Уплыл за ресурсами и скоро принесёт ящик."
	subLbl.TextSize = 15; subLbl.TextColor3 = Color3.fromRGB(220, 235, 255); subLbl.ZIndex = 3; subLbl.Parent = panel

	local capLbl = Instance.new("TextLabel")
	capLbl.BackgroundTransparency = 1; capLbl.Position = UDim2.fromOffset(26, 120); capLbl.Size = UDim2.fromOffset(300, 20)
	capLbl.TextXAlignment = Enum.TextXAlignment.Left; capLbl.Font = Enum.Font.GothamBold
	capLbl.Text = "Следующий ящик через:"; capLbl.TextSize = 15; capLbl.TextColor3 = Color3.fromRGB(220, 235, 255)
	capLbl.ZIndex = 3; capLbl.Parent = panel

	timerLbl = Instance.new("TextLabel")
	timerLbl.BackgroundTransparency = 1; timerLbl.Position = UDim2.fromOffset(26, 142); timerLbl.Size = UDim2.fromOffset(300, 56)
	timerLbl.TextXAlignment = Enum.TextXAlignment.Left; timerLbl.Font = Enum.Font.GothamBlack
	timerLbl.Text = "0:00"; timerLbl.TextSize = 46; timerLbl.TextColor3 = C.gold; timerLbl.TextStrokeTransparency = 0.5
	timerLbl.ZIndex = 3; timerLbl.Parent = panel

	skipBtn = Instance.new("TextButton")
	skipBtn.AnchorPoint = Vector2.new(0, 1); skipBtn.Position = UDim2.new(0, 26, 1, -20); skipBtn.Size = UDim2.fromOffset(300, 52)
	skipBtn.Font = Enum.Font.GothamBlack; skipBtn.Text = "ПРОПУСТИТЬ (бесплатно)"; skipBtn.TextSize = 19; skipBtn.TextColor3 = C.white
	skipBtn.TextStrokeTransparency = 0.6; skipBtn.BackgroundColor3 = C.afford; skipBtn.ZIndex = 3
	corner(skipBtn, 12); stroke(skipBtn, Color3.fromRGB(0, 0, 0), 2).Transparency = 0.7; skipBtn.Parent = panel

	--[[ ── крестик закрытия ──
	     Кнопку целиком делает UITheme.closeButton: владелец потребовал, чтобы во всех
	     меню океана закрытие выглядело ОДИНАКОВО, эталоном назван инвентарь. Своя
	     картинка 62 px с ростом на наведении жила только здесь и выбивалась из общего
	     ряда, поэтому её тут больше нет — размер и вид живут в UITheme.CLOSE_SIZE, и
	     правятся один раз на все окна.
	     Родителем передаём саму панель окна: у неё нет ClipsDescendants, детей она не
	     режет, и кнопка стоит целиком ВНУТРИ, в правом верхнем углу.
	     Посадку и размер НЕ передаём — умолчание модуля и есть посадка инвентаря.
	     ZIndex = 5 сохранён от прежней кнопки: панель лежит на 2, подписи на 3, превью
	     дайвера доходит до 5 — на меньшем крестик утонул бы в содержимом окна. ]]
	local closeBtn = UITheme.closeButton({ parent = panel, zIndex = 5 })

	closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false; tickToken += 1 end)
	backdrop.MouseButton1Click:Connect(function() gui.Enabled = false; tickToken += 1 end)
	skipBtn.MouseButton1Click:Connect(function() statusEvent:FireServer("skip") end)
end

local function render()
	if secondsLeft > 0 then
		timerLbl.Text = fmt(secondsLeft); timerLbl.TextColor3 = C.gold
	else
		timerLbl.Text = "Несёт ящик…"; timerLbl.TextColor3 = C.afford
	end
end

local function startTick()
	tickToken += 1
	local my = tickToken
	task.spawn(function()
		while gui and gui.Enabled and my == tickToken do
			render()
			task.wait(1)
			if secondsLeft > 0 then secondsLeft = secondsLeft - 1 end
		end
	end)
end

statusEvent.OnClientEvent:Connect(function(kind, a)
	if kind == "open" then
		build()
		secondsLeft = tonumber(a) or 0
		gui.Enabled = true
		render()
		startTick()
	elseif kind == "skipped" then
		secondsLeft = 0
		if gui and gui.Enabled then render() end
	end
end)
