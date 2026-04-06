local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local dropEvent = ReplicatedStorage:WaitForChild("DropItem")
local pickupEvent = ReplicatedStorage:WaitForChild("PickupDroppedItem")

local HOTBAR_SLOTS = 8

local currentHighlight = nil
local currentTarget = nil
local promptBillboard = nil

-- Shared flag: when true, InventoryUI should NOT toggle on E press
_G.SuppressInventoryToggle = false

-- Find dropped item under mouse cursor
local function getDroppedItemUnderMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return nil, nil
	end

	local hit = result.Instance

	if CollectionService:HasTag(hit, "DroppedItem") then
		return hit, hit
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "DroppedItem") then
		return model, hit
	end

	return nil, nil
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	if promptBillboard then
		promptBillboard:Destroy()
		promptBillboard = nil
	end
	currentTarget = nil
	-- Defer the flag reset so InventoryUI's InputBegan handler
	-- still sees it as true during the same frame
	task.defer(function()
		if currentTarget == nil then
			_G.SuppressInventoryToggle = false
		end
	end)
end

local function getAdornee(resource)
	if resource:IsA("Model") and resource.PrimaryPart then
		return resource.PrimaryPart
	elseif resource:IsA("BasePart") then
		return resource
	end
	return resource:FindFirstChildWhichIsA("BasePart", true) or resource
end

local function createPrompt(resource)
	if promptBillboard then promptBillboard:Destroy() end

	local adornee = getAdornee(resource)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 1.2, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "Press E to pick up"
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	-- Show item name below
	local resType = resource:GetAttribute("ResourceType") or "Item"
	local resAmount = resource:GetAttribute("ResourceAmount") or 1
	local displayText = resType:gsub("_", " ")
	if resAmount > 1 then
		displayText = displayText .. " x" .. resAmount
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayText
	nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextScaled = true
	nameLabel.Parent = billboard

	promptBillboard = billboard
end

-- Find which hotbar slot the mouse is hovering over
local function getHoveredHotbarSlot()
	local hotbarGui = playerGui:FindFirstChild("HotbarGui")
	if not hotbarGui then return nil end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	if not bar then return nil end

	local mousePos = UserInputService:GetMouseLocation()

	for i = 1, HOTBAR_SLOTS do
		local slot = bar:FindFirstChild("HotbarSlot_" .. i)
		if slot then
			local absPos = slot.AbsolutePosition
			local absSize = slot.AbsoluteSize
			if mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
				and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y then
				return i
			end
		end
	end

	return nil
end

-- Raycast from mouse to get world drop position
local function getMouseWorldPosition()
	local mPos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mPos.X, mPos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	if char then rayParams.FilterDescendantsInstances = {char} end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	return result and result.Position or nil
end

-- Highlight dropped items under mouse
RunService.RenderStepped:Connect(function()
	local resource, part = getDroppedItemUnderMouse()

	if resource == currentTarget then
		return
	end

	clearHighlight()

	if resource then
		currentTarget = resource
		_G.SuppressInventoryToggle = true

		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 220, 100)
		highlight.FillTransparency = 0.5
		highlight.OutlineColor = Color3.fromRGB(255, 220, 100)
		highlight.OutlineTransparency = 0
		highlight.Parent = resource
		currentHighlight = highlight

		createPrompt(resource)
	end
end)

-- Input handling
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	-- E key pickup
	if input.KeyCode == Enum.KeyCode.E then
		if currentTarget and currentTarget.Parent then
			local hitPart = currentTarget
			if hitPart:IsA("Model") then
				hitPart = hitPart.PrimaryPart or hitPart:FindFirstChildWhichIsA("BasePart")
			end
			if hitPart then
				pickupEvent:FireServer(hitPart)
			end
			clearHighlight()
			return
		end
	end

	-- Q key drop from hovered hotbar slot
	if input.KeyCode == Enum.KeyCode.Q then
		local slotIndex = getHoveredHotbarSlot()
		if not slotIndex then return end

		local slotData = _G.InventorySlotData
		if not slotData then return end

		local data = slotData[slotIndex]
		if not data then return end

		if data.type == "resource" then
			if data.count <= 1 then
				slotData[slotIndex] = nil
			else
				data.count = data.count - 1
			end
			local dropPos = getMouseWorldPosition()
			dropEvent:FireServer(data.name, 1, dropPos)
		elseif data.type == "tool" then
			slotData[slotIndex] = nil
			local dropPos = getMouseWorldPosition()
			dropEvent:FireServer(data.toolName, 1, dropPos)
		end
	end
end)
