--[[
	СТАТУС-БАР НАПОЛНЕННОСТИ КАНИСТРЫ.

	Пока канистра в руках, над хотбаром висит строка:
	    Заполнено:  ▬▬▬▬▬▬▬▬░░░░░  60%
	Вся шкала серая, налитая часть — зелёная, цифра справа.

	Место и оформление те же, что у статус-бара мангала (GrillFoodPlace): текст без
	подложки с чёрной обводкой по глифам, прижат к хотбару. Так строка читается на
	любом фоне и не выглядит отдельной плашкой посреди экрана.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local OilCanister = require(ReplicatedStorage:WaitForChild("OilCanister"))
local notifyEvent = ReplicatedStorage:WaitForChild("CanisterNotify")

local BAR_WIDTH  = 190
local BAR_HEIGHT = 12
local UPDATE_EVERY = 0.1

-- ─── строим ───
local gui = Instance.new("ScreenGui")
gui.Name = "CanisterStatus"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = playerGui

local row = Instance.new("Frame")
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -76)   -- тот же уровень, что у подсказки мангала
row.Size = UDim2.fromOffset(420, 26)
row.BackgroundTransparency = 1
row.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = row

local function mkText(text, order)
	local t = Instance.new("TextLabel")
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.new(0, 0, 1, 0)
	t.LayoutOrder = order
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.fromRGB(255, 235, 190)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 17
	t.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.15
	stroke.Parent = t
	return t
end

mkText(OilCanister.BAR_LABEL, 1)

local bar = Instance.new("Frame")
bar.LayoutOrder = 2
bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
bar.BackgroundColor3 = OilCanister.BAR_EMPTY
bar.BackgroundTransparency = 0.15
bar.BorderSizePixel = 0
bar.Parent = row

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar

local barStroke = Instance.new("UIStroke")
barStroke.Thickness = 2
barStroke.Color = Color3.fromRGB(0, 0, 0)
barStroke.Transparency = 0.35
barStroke.Parent = bar

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = OilCanister.BAR_FILLED
fill.BorderSizePixel = 0
fill.Parent = bar

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local pctText = mkText("0%", 3)

-- ─── обновление ───
local function heldCanister()
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if OilCanister.isCanister(t) then return t end
	end
	return nil
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < UPDATE_EVERY then return end
	acc = 0

	local tool = heldCanister()
	local frac = tool and OilCanister.fractionOf(tool) or nil
	if not frac then
		gui.Enabled = false
		return
	end
	fill.Size = UDim2.new(frac, 0, 1, 0)
	pctText.Text = ("%d%%"):format(math.floor(frac * 100 + 0.5))
	gui.Enabled = true
end)

-- ─── ответы сервера ───
local MESSAGES = {
	-- с катера в канистру
	filled       = { type = "success", icon = "🛢️", title = "Топливо перелито" },
	full         = { type = "warn",    icon = "🛢️", title = "Канистра полная" },
	empty_source = { type = "warn",    icon = "🛢️", title = "Канистра пуста" },
	-- из канистры в бак на плоту
	stored        = { type = "success", icon = "🛢️", title = "Залито в бак" },
	tank_full     = { type = "warn",    icon = "🛢️", title = "Бак полон" },
	canister_empty= { type = "warn",    icon = "🛢️", title = "В канистре пусто",
		body = "Набери топливо с катера" },
	no_canister  = { type = "warn",    icon = "🛢️", title = "Нужна канистра",
		body = "Возьми пластиковую канистру" },
	-- из бака на плоту в огнемёт
	flame_filled = { type = "success", icon = "🔥", title = "Огнемёт заправлен" },
	flame_full   = { type = "warn",    icon = "🔥", title = "Бак огнемёта полон" },
	tank_empty   = { type = "warn",    icon = "🛢️", title = "В баке пусто",
		body = "Залей топливо из канистры" },
}

notifyEvent.OnClientEvent:Connect(function(kind, amount)
	local msg = MESSAGES[kind]
	if not msg or not _G.Notify then return end
	local body = msg.body
	if not body and amount then
		body = "+" .. OilCanister.formatVolume(amount)
	end
	_G.Notify({ type = msg.type, icon = msg.icon, title = msg.title, body = body })
end)
