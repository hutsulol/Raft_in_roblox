-- DiverNotifyUI.client.lua — a toast when the diver delivers a crate (DiverNotify from the server).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local notify    = ReplicatedStorage:WaitForChild("DiverNotify")

local RES_RU = { Log = "Дерево", Leaves = "Листва", Plastic = "Пластик", Stone = "Камень",
	Iron_Ore = "Руда", Iron_Ingot = "Железный слиток" }
local CONTENT_RU = { Food = "Еда", Resources = "Ресурсы", Ammo = "Снаряды" }

local gui
local function ensureGui()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "DiverNotifyGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60; gui.Parent = playerGui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 6); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = gui
	local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0.1, 0); pad.Parent = gui
end

notify.OnClientEvent:Connect(function(content, resource, amount)
	ensureGui()
	local t = Instance.new("Frame")
	t.Size = UDim2.fromOffset(360, 52); t.BackgroundColor3 = Color3.fromHex("3A7FD0"); t.BackgroundTransparency = 0.05
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = t
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromHex("1C4F8F"); stroke.Thickness = 3; stroke.Parent = t
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromHex("54A7EC"), Color3.fromHex("3A7FD0")); grad.Rotation = 90; grad.Parent = t
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 1); lbl.Font = Enum.Font.GothamBold
	lbl.Text = "Дайвер принёс: " .. (RES_RU[resource] or resource) .. " ×" .. tostring(amount)
		.. "  (" .. (CONTENT_RU[content] or content or "") .. ")"
	lbl.TextColor3 = Color3.new(1, 1, 1); lbl.TextSize = 18; lbl.TextStrokeTransparency = 0.4; lbl.Parent = t
	t.Parent = gui

	t.BackgroundTransparency = 1; lbl.TextTransparency = 1
	TweenService:Create(t, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(lbl, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(2.6, function()
		TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		task.wait(0.45); t:Destroy()
	end)
end)
