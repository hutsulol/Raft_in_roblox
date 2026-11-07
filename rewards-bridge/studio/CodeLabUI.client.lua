local Players = game:GetService("Players")
local remote = game:GetService("ReplicatedStorage"):WaitForChild("CodeLabAction")
local gui = Instance.new("ScreenGui")
gui.Name = "PirateCodeLab"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = Instance.new("Frame")
root.Size = UDim2.new(0, 650, 0, 550)
root.Position = UDim2.new(0.5, -325, 0.5, -275)
root.BackgroundColor3 = Color3.fromRGB(16, 30, 43)
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 20)
local function label(text, y, height, size, color)
	local item = Instance.new("TextLabel")
	item.Position = UDim2.new(0, 26, 0, y)
	item.Size = UDim2.new(1, -52, 0, height)
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Gotham
	item.TextSize = size
	item.TextColor3 = color or Color3.fromRGB(225, 237, 243)
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Text = text
	item.Parent = root
	return item
end
label("ПИРАТ · ПРИЁМ КОДОВ В ROBLOX", 22, 35, 23)
label("Локальный стенд: настоящий HTTP + база SQLite. Telegram не нужен.", 65, 32, 14, Color3.fromRGB(155, 180, 193))
local network = label("Готов к запросу", 108, 40, 16)
local amount = label("Карточка ещё не получена", 153, 38, 24, Color3.fromRGB(231, 190, 106))
local code = Instance.new("TextBox")
code.Position = UDim2.new(0, 26, 0, 201)
code.Size = UDim2.new(1, -52, 0, 55)
code.BackgroundColor3 = Color3.fromRGB(8, 20, 29)
code.TextColor3 = Color3.fromRGB(237, 206, 139)
code.Font = Enum.Font.Code
code.TextSize = 19
code.ClearTextOnFocus = false
code.Text = "Здесь появится код от сервера"
code.Parent = root
Instance.new("UICorner", code).CornerRadius = UDim.new(0, 8)
local checks = label("Проверки ещё не запускались", 269, 36, 14)
local result = label("", 312, 45, 15, Color3.fromRGB(152, 218, 179))
local function render(data)
	if data.error then result.Text = data.error; return end
	network.Text = data.network or ""
	checks.Text = data.checks or ""
	if data.pending then
		amount.Text = "Новая карточка ожидает ответа API"
		if not code:IsFocused() then code.Text = "Код появится после подтверждения сервера" end
	elseif data.card then
		amount.Text = tostring(data.card.amount) .. " пиратов · " .. (data.card.status == "redeemed" and "активировано" or "готово")
		if not code:IsFocused() then code.Text = data.card.code end
	end
	result.Text = (data.redeemed or "") .. (data.balance and ((data.redeemed and ". " or "") .. "Баланс стенда: " .. tostring(data.balance)) or "")
end
local busy = false
local function button(text, y, action)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, 26, 0, y)
	b.Size = UDim2.new(1, -52, 0, 44)
	b.BackgroundColor3 = Color3.fromRGB(223, 181, 100)
	b.TextColor3 = Color3.fromRGB(20, 32, 39)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = text
	b.Parent = root
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
	b.Activated:Connect(function()
		if busy then return end
		busy = true
		local ok, data = pcall(function() return remote:InvokeServer(action) end)
		if ok then render(data) else result.Text = "Ошибка запроса к серверу Roblox" end
		busy = false
	end)
end
button("1. Открыть тестовый пак → получить код", 365, "issue")
button("2. Проверить активацию и защиту от повтора", 419, "redeem")
button("Восстановить карточку из истории API", 473, "history")
task.spawn(function()
	while gui.Parent do
		task.wait(2)
		if not busy then
			local ok, data = pcall(function() return remote:InvokeServer("state") end)
			if ok then render(data) end
		end
	end
end)
