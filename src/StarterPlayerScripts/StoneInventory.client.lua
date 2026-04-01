-- StoneInventory.client.lua
-- Adds Stone as a resource to the hotbar display
-- Matches the exact style of Log/Plastic slots

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STONE_ICON = "rbxassetid://134781813180973"
local SLOT_SIZE = 60
local SLOT_PAD = 6

local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")

local stoneCount = 0

-- ─── Find the hotbar frame ───
local function getHotbar()
	local hotbarGui = playerGui:FindFirstChild("HotbarGui")
	if not hotbarGui then return nil, nil end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	return hotbarGui, bar
end

-- ─── Create or update Stone slot in hotbar ───
local function updateStoneSlot(count)
	stoneCount = count

	local hotbarGui, bar = getHotbar()
	if not bar then return end

	-- Find existing stone slot
	local stoneSlot = bar:FindFirstChild("StoneSlot")

	if count <= 0 then
		if stoneSlot then stoneSlot.Visible = false end
		return
	end

	if not stoneSlot then
		-- Create a new slot that extends the hotbar to the right
		stoneSlot = Instance.new("Frame")
		stoneSlot.Name = "StoneSlot"
		stoneSlot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		-- Position after the last hotbar slot (slot 8)
		stoneSlot.Position = UDim2.new(0, SLOT_PAD + 8 * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD)
		stoneSlot.BackgroundColor3 = Color3.fromRGB(175, 145, 95)
		stoneSlot.BackgroundTransparency = 0.1
		stoneSlot.BorderSizePixel = 0
		stoneSlot.Parent = bar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = stoneSlot

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(120, 90, 50)
		stroke.Thickness = 1.5
		stroke.Parent = stoneSlot

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 40, 0, 40)
		icon.Position = UDim2.new(0.5, -20, 0.5, -20)
		icon.BackgroundTransparency = 1
		icon.Image = STONE_ICON
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = stoneSlot

		local countLabel = Instance.new("TextLabel")
		countLabel.Name = "Count"
		countLabel.Size = UDim2.new(1, -4, 0, 16)
		countLabel.Position = UDim2.new(0, 2, 1, -18)
		countLabel.BackgroundTransparency = 1
		countLabel.Text = tostring(count)
		countLabel.TextColor3 = Color3.fromRGB(255, 245, 220)
		countLabel.TextSize = 14
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.TextStrokeTransparency = 0.5
		countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		countLabel.Parent = stoneSlot

		-- Widen the hotbar background to fit
		local currentWidth = bar.Size.X.Offset
		bar.Size = UDim2.new(0, currentWidth + SLOT_SIZE + SLOT_PAD, bar.Size.Y.Scale, bar.Size.Y.Offset)
		bar.Position = UDim2.new(0.5, -(currentWidth + SLOT_SIZE + SLOT_PAD) / 2, bar.Position.Y.Scale, bar.Position.Y.Offset)
	end

	stoneSlot.Visible = true
	local countLabel = stoneSlot:FindFirstChild("Count")
	if countLabel then
		countLabel.Text = tostring(count)
	end
end

-- ─── Listen for inventory updates ───
inventoryEvent.OnClientEvent:Connect(function(inv)
	if inv and inv.Stone ~= nil then
		-- Wait a frame to ensure HotbarGui exists
		task.defer(function()
			updateStoneSlot(inv.Stone)
		end)
	end
end)

-- ─── Retry: hotbar might not exist yet on first inventory update ───
task.spawn(function()
	-- Keep trying to set up the Stone slot when hotbar appears
	while true do
		task.wait(2)
		if stoneCount > 0 then
			local _, bar = getHotbar()
			if bar and not bar:FindFirstChild("StoneSlot") then
				updateStoneSlot(stoneCount)
			end
		end
	end
end)
