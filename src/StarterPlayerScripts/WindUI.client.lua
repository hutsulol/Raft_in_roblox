-- WindUI.client.lua
-- Shows a wind icon while a wind event is active. Coordinates its slot
-- position with the RadiationUI icon via _G.StatusIconSlots so the two
-- icons sit side-by-side in order of appearance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Shared status icon slot coordination ───
-- Both this script and RadiationUI use this table to claim a horizontal
-- slot above the stat bars. Whichever status appears first takes slot 0
-- (the original spot); the second takes slot 1 (offset to the right).
local SLOTS = _G.StatusIconSlots
if not SLOTS then
	SLOTS = {
		order = {}, -- list of {name = string} in claim order
		hooks = {}, -- list of refresh callbacks
	}
	_G.StatusIconSlots = SLOTS
end

local function takeSlot(name)
	for _, entry in ipairs(SLOTS.order) do
		if entry.name == name then return end
	end
	table.insert(SLOTS.order, {name = name})
end

local function releaseSlot(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then
			table.remove(SLOTS.order, i)
			return
		end
	end
end

local function getSlotIndex(name)
	for i, entry in ipairs(SLOTS.order) do
		if entry.name == name then return i - 1 end
	end
	return -1
end

local function notifyAll()
	for _, fn in ipairs(SLOTS.hooks) do
		pcall(fn)
	end
end

-- ─── UI ───
local BASE_X = 16
local BASE_Y_OFFSET = -188
local SLOT_STRIDE = 44 -- 36px icon + 8px gap

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WindUI"
screenGui.DisplayOrder = 16
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local icon = Instance.new("ImageLabel")
icon.Name = "WindIcon"
icon.AnchorPoint = Vector2.new(0, 1)
icon.Position = UDim2.new(0, BASE_X, 1, BASE_Y_OFFSET)
icon.Size = UDim2.new(0, 36, 0, 36)
icon.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
icon.BackgroundTransparency = 0.3
icon.Image = "rbxassetid://97997149442461"
icon.ScaleType = Enum.ScaleType.Stretch
icon.Visible = false
icon.ClipsDescendants = true
icon.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = icon

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 130, 180)
stroke.Thickness = 2
stroke.Parent = icon

-- Cooldown overlay (grows top→bottom as wind expires)
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.Name = "CooldownOverlay"
cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.5
cooldownOverlay.BorderSizePixel = 0
cooldownOverlay.ZIndex = 2
cooldownOverlay.Parent = icon

-- Tooltip
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.Size = UDim2.new(0, 200, 0, 60)
tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tooltip.BackgroundTransparency = 0.15
tooltip.Visible = false
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(80, 130, 180)
tooltipStroke.Thickness = 1.5
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Size = UDim2.new(1, -12, 0, 20)
tooltipTitle.Position = UDim2.new(0, 6, 0, 4)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = "Wind Event"
tooltipTitle.TextColor3 = Color3.fromRGB(150, 200, 255)
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Size = UDim2.new(1, -12, 0, 32)
tooltipBody.Position = UDim2.new(0, 6, 0, 24)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Text = "Strong wind redirecting the raft"
tooltipBody.TextColor3 = Color3.fromRGB(200, 200, 200)
tooltipBody.TextSize = 12
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextWrapped = true
tooltipBody.Parent = tooltip

icon.MouseEnter:Connect(function()
	if icon.Visible then tooltip.Visible = true end
end)
icon.MouseLeave:Connect(function()
	tooltip.Visible = false
end)

-- ─── State ───
local WIND_DURATION = 6
local windStartTime = 0
local active = false

local function refreshPosition()
	local slot = getSlotIndex("wind")
	if slot < 0 then
		icon.Visible = false
		tooltip.Visible = false
		return
	end
	icon.Visible = true
	local x = BASE_X + slot * SLOT_STRIDE
	icon.Position = UDim2.new(0, x, 1, BASE_Y_OFFSET)
	tooltip.Position = UDim2.new(0, x + 36 + 8, 1, BASE_Y_OFFSET)
end

table.insert(SLOTS.hooks, refreshPosition)

local windRemoteEvent = ReplicatedStorage:WaitForChild("WindUpdate", 10)

if windRemoteEvent then
	windRemoteEvent.OnClientEvent:Connect(function(isActive, remaining, duration, _direction)
		if isActive then
			WIND_DURATION = duration or 6
			windStartTime = tick() - (WIND_DURATION - (remaining or WIND_DURATION))
			active = true
			takeSlot("wind")
			cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			notifyAll()
		else
			active = false
			windStartTime = 0
			releaseSlot("wind")
			cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			notifyAll()
		end
	end)
end

-- Cooldown overlay animation
RunService.Heartbeat:Connect(function()
	if not active then return end
	local elapsed = tick() - windStartTime
	local progress = math.clamp(elapsed / WIND_DURATION, 0, 1)
	cooldownOverlay.Size = UDim2.new(1, 0, progress, 0)
end)

-- Initial state in case the script loads after the event fired
refreshPosition()
