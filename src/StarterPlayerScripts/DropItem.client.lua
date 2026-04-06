local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local dropEvent = ReplicatedStorage:WaitForChild("DropItem")

local HOTBAR_SLOTS = 8

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
	local cam = workspace.CurrentCamera
	local mPos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mPos.X, mPos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	if char then rayParams.FilterDescendantsInstances = {char} end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	return result and result.Position or nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Q then return end

	local slotIndex = getHoveredHotbarSlot()
	if not slotIndex then return end

	local slotData = _G.InventorySlotData
	if not slotData then return end

	local data = slotData[slotIndex]
	if not data then return end
	if data.type ~= "resource" then return end

	-- Deduct from this specific slot
	if data.count <= 1 then
		slotData[slotIndex] = nil
	else
		data.count = data.count - 1
	end

	local dropPos = getMouseWorldPosition()
	dropEvent:FireServer(data.name, 1, dropPos)
end)
