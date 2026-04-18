-- SmallContainerSystem.server.lua
-- Places the Small Container on the raft (WorkBench pattern) and gives
-- it six inventory slots the player can take from / put into via the
-- chest-style UI.

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local cupActionEvent = rs:WaitForChild("CupAction")

local containerAction = rs:FindFirstChild("ContainerAction")
if not containerAction then
	containerAction = Instance.new("RemoteEvent")
	containerAction.Name = "ContainerAction"
	containerAction.Parent = rs
end

local openContainerEvent = rs:FindFirstChild("OpenContainer")
if not openContainerEvent then
	openContainerEvent = Instance.new("RemoteEvent")
	openContainerEvent.Name = "OpenContainer"
	openContainerEvent.Parent = rs
end

local CONTAINER_SLOTS = 6
local CONTAINER_RANGE = 12
local MAX_STACK = 30

local function findTemplate()
	local folder = rs:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild("Container_empty")
	if not tmpl then
		tmpl = rs:FindFirstChild("Container_empty", true)
	end
	return tmpl
end

local function initSlots(model)
	for i = 1, CONTAINER_SLOTS do
		if model:GetAttribute("Slot" .. i .. "_Name") == nil then
			model:SetAttribute("Slot" .. i .. "_Name", "")
			model:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end
end

local function setupContainerPrompt(model)
	initSlots(model)
	CollectionService:AddTag(model, "SmallContainer")

	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end

	if part:FindFirstChildOfClass("ProximityPrompt") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Container"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = CONTAINER_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		openContainerEvent:FireClient(player, model)
	end)
end

local function withinRange(player, model)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then return false end
	return (char.HumanoidRootPart.Position - part.Position).Magnitude <= CONTAINER_RANGE + 5
end

local function addToPlayerInventory(player, itemName, count)
	if not _G.AddResourceToInventory then return 0 end
	return _G.AddResourceToInventory(player, itemName, count, nil) or 0
end

-- ═══════════════════════════════════════════
-- CupAction: place
-- ═══════════════════════════════════════════
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeSmallContainer" then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "SmallContainer" then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = findTemplate()
	if not template then return end

	local container = template:Clone()
	container.Name = "SmallContainer"

	if container:IsA("Model") then
		local bbCF = container:GetBoundingBox()
		container.WorldPivot = CFrame.new(bbCF.Position)
	end

	container:PivotTo(worldCF)
	container.Parent = raft

	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end

	setupContainerPrompt(container)

	tool:Destroy()
end)

-- ═══════════════════════════════════════════
-- ContainerAction: take / put
-- ═══════════════════════════════════════════
containerAction.OnServerEvent:Connect(function(player, action, container, slotIndex, itemName, count)
	if typeof(action) ~= "string" then return end
	if typeof(container) ~= "Instance" then return end
	if not container:IsDescendantOf(workspace) then return end
	if container.Name ~= "SmallContainer" then return end
	if not withinRange(player, container) then return end

	if action == "take" then
		slotIndex = tonumber(slotIndex)
		if not slotIndex or slotIndex < 1 or slotIndex > CONTAINER_SLOTS then return end

		local name = container:GetAttribute("Slot" .. slotIndex .. "_Name")
		local n = container:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
		if typeof(name) ~= "string" or name == "" or n <= 0 then return end

		local cap = _G.GetInventoryCapacity and _G.GetInventoryCapacity(player, name) or n
		local toTake = math.min(n, cap)
		if toTake <= 0 then return end

		local added = addToPlayerInventory(player, name, toTake)
		if added <= 0 then return end

		local remaining = n - added
		if remaining <= 0 then
			container:SetAttribute("Slot" .. slotIndex .. "_Name", "")
			container:SetAttribute("Slot" .. slotIndex .. "_Count", 0)
		else
			container:SetAttribute("Slot" .. slotIndex .. "_Count", remaining)
		end

	elseif action == "put" then
		if typeof(itemName) ~= "string" or itemName == "" then return end
		count = tonumber(count) or 1
		count = math.clamp(math.floor(count), 1, MAX_STACK)

		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		local have = inv[itemName] or 0
		if have < count then return end

		-- Find a target slot: existing stack with the same item first, then empty
		local targetSlot = nil
		local existingCount = 0
		for i = 1, CONTAINER_SLOTS do
			local n = container:GetAttribute("Slot" .. i .. "_Name")
			if n == itemName then
				local c = container:GetAttribute("Slot" .. i .. "_Count") or 0
				if c < MAX_STACK then
					targetSlot = i
					existingCount = c
					break
				end
			end
		end
		if not targetSlot then
			for i = 1, CONTAINER_SLOTS do
				local n = container:GetAttribute("Slot" .. i .. "_Name")
				if n == nil or n == "" then
					targetSlot = i
					existingCount = 0
					break
				end
			end
		end
		if not targetSlot then return end

		local space = MAX_STACK - existingCount
		local toPut = math.min(count, space)
		if toPut <= 0 then return end

		if _G.RemoveResourceFromInventory then
			_G.RemoveResourceFromInventory(player, itemName, toPut)
		else
			inv[itemName] = have - toPut
		end

		container:SetAttribute("Slot" .. targetSlot .. "_Name", itemName)
		container:SetAttribute("Slot" .. targetSlot .. "_Count", existingCount + toPut)

		if _G.SendInventory then _G.SendInventory(player) end
	end
end)

-- Setup existing containers on script load (after raft restore)
for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and child.Name == "SmallContainer" then
		setupContainerPrompt(child)
	end
end
