-- PlasticContainerSystem.server.lua
-- Places the Plastic Container on the raft and gives it nine inventory
-- slots. Identical flow to SmallContainerSystem, minus the fill-level
-- model swap — the plastic_container model stays the same regardless
-- of how full it is.

local rs = game:GetService("ReplicatedStorage")
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

local CONTAINER_SLOTS = 9
local CONTAINER_RANGE = 12
local MAX_STACK = 30
local TEMPLATE_NAME = "plastic_container"
local TOOL_NAME = "PlasticContainer"
local CONTAINER_NAME = "PlasticContainer"
local PLACE_ACTION = "placePlasticContainer"

local function findTemplate()
	local folder = rs:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild(TEMPLATE_NAME)
	if not tmpl then
		tmpl = rs:FindFirstChild(TEMPLATE_NAME, true)
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
	model:SetAttribute("SlotCount", CONTAINER_SLOTS)
	CollectionService:AddTag(model, CONTAINER_NAME)

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

-- Tools (Wood_Knife, Injector, capsules, …) live as Tool Instances in
-- the player's Backpack / Character. Storing them inside a hidden
-- "StoredTools" folder and flagging the slot with Slot{i}_Kind = "tool"
-- lets the UI keep its flat slot-count / slot-name model while the
-- take-side reparents Instances back instead of crediting resources.

local function getOrCreateToolStorage(container)
	local folder = container:FindFirstChild("StoredTools")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StoredTools"
		folder.Parent = container
	end
	return folder
end

local function collectPlayerTools(player, toolName, limit)
	local out = {}
	local function scan(parent)
		if not parent then return end
		for _, t in parent:GetChildren() do
			if #out >= limit then return end
			if t:IsA("Tool") and t.Name == toolName then
				table.insert(out, t)
			end
		end
	end
	scan(player:FindFirstChild("Backpack"))
	scan(player.Character)
	return out
end

local function cleanseExternalWelds(tool)
	for _, d in tool:GetDescendants() do
		if d:IsA("WeldConstraint") then
			local p0, p1 = d.Part0, d.Part1
			local p0In = p0 and p0:IsDescendantOf(tool)
			local p1In = p1 and p1:IsDescendantOf(tool)
			if not p0In or not p1In then
				d:Destroy()
			end
		end
	end
end

local HIDDEN_TAG = "ChestHidden"

local function hideStoredTool(tool)
	if tool:GetAttribute(HIDDEN_TAG) then return end
	tool:SetAttribute(HIDDEN_TAG, true)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("__ct", d.Transparency)
			d:SetAttribute("__cc", d.CanCollide)
			d:SetAttribute("__cq", d.CanQuery)
			d:SetAttribute("__ch", d.CanTouch)
			d:SetAttribute("__ca", d.Anchored)
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = true
		end
	end
end

local function revealStoredTool(tool)
	if not tool:GetAttribute(HIDDEN_TAG) then return end
	tool:SetAttribute(HIDDEN_TAG, nil)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local t = d:GetAttribute("__ct")
			local c = d:GetAttribute("__cc")
			local q = d:GetAttribute("__cq")
			local h = d:GetAttribute("__ch")
			local a = d:GetAttribute("__ca")
			if t ~= nil then d.Transparency = t; d:SetAttribute("__ct", nil) end
			if c ~= nil then d.CanCollide = c; d:SetAttribute("__cc", nil) end
			if q ~= nil then d.CanQuery = q; d:SetAttribute("__cq", nil) end
			if h ~= nil then d.CanTouch = h; d:SetAttribute("__ch", nil) end
			if a ~= nil then d.Anchored = a; d:SetAttribute("__ca", nil) end
		end
	end
end

-- ═══════════════════════════════════════════
-- CupAction: place
-- ═══════════════════════════════════════════
cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= PLACE_ACTION then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= TOOL_NAME then return end

	local raft = workspace:FindFirstChild("Raft")
	if not raft or not raft.PrimaryPart then return end

	if typeof(target) ~= "CFrame" then return end

	local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

	local template = findTemplate()
	if not template then return end

	local container = template:Clone()
	container.Name = CONTAINER_NAME

	if container:IsA("Model") then
		local bbCF = container:GetBoundingBox()
		container.WorldPivot = CFrame.new(bbCF.Position)
	end

	container:PivotTo(worldCF)
	container.Parent = raft

	-- Velocity snapshot + weld-then-unanchor (T13 + T15).
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel

	setupContainerPrompt(container)

	tool:Destroy()
end)

-- ═══════════════════════════════════════════
-- ContainerAction: take / put / move
-- ═══════════════════════════════════════════
containerAction.OnServerEvent:Connect(function(player, action, container, slotIndex, itemName, count, kind)
	if typeof(action) ~= "string" then return end
	if typeof(container) ~= "Instance" then return end
	if not container:IsDescendantOf(workspace) then return end
	if container.Name ~= CONTAINER_NAME then return end
	if not withinRange(player, container) then return end

	if action == "take" then
		slotIndex = tonumber(slotIndex)
		if not slotIndex or slotIndex < 1 or slotIndex > CONTAINER_SLOTS then return end

		local name = container:GetAttribute("Slot" .. slotIndex .. "_Name")
		local n = container:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
		local slotKind = container:GetAttribute("Slot" .. slotIndex .. "_Kind")
		if typeof(name) ~= "string" or name == "" or n <= 0 then return end

		if slotKind == "tool" then
			local backpack = player:FindFirstChild("Backpack")
			if not backpack then return end
			local storage = container:FindFirstChild("StoredTools")
			if not storage then
				container:SetAttribute("Slot" .. slotIndex .. "_Name", "")
				container:SetAttribute("Slot" .. slotIndex .. "_Count", 0)
				container:SetAttribute("Slot" .. slotIndex .. "_Kind", nil)
				return
			end
			local moved = 0
			for _, t in storage:GetChildren() do
				if moved >= n then break end
				if t:IsA("Tool") and t.Name == name then
					cleanseExternalWelds(t)
					revealStoredTool(t)
					t.Parent = backpack
					moved = moved + 1
				end
			end
			local remaining = 0
			for _, t in storage:GetChildren() do
				if t:IsA("Tool") and t.Name == name then
					remaining = remaining + 1
				end
			end
			if remaining <= 0 then
				container:SetAttribute("Slot" .. slotIndex .. "_Name", "")
				container:SetAttribute("Slot" .. slotIndex .. "_Count", 0)
				container:SetAttribute("Slot" .. slotIndex .. "_Kind", nil)
			else
				container:SetAttribute("Slot" .. slotIndex .. "_Count", remaining)
			end
			return
		end

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
		if typeof(itemName) ~= "string" or itemName == "" then
			if _G.SendInventory then _G.SendInventory(player) end
			return
		end
		count = tonumber(count) or 1
		count = math.clamp(math.floor(count), 1, MAX_STACK)

		if kind == "tool" then
			local tools = collectPlayerTools(player, itemName, count)
			if #tools == 0 then return end

			slotIndex = tonumber(slotIndex)
			local targetSlot = nil
			local existingCount = 0

			if slotIndex and slotIndex >= 1 and slotIndex <= CONTAINER_SLOTS then
				local n = container:GetAttribute("Slot" .. slotIndex .. "_Name")
				local k = container:GetAttribute("Slot" .. slotIndex .. "_Kind")
				local c = container:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
				if n == itemName and k == "tool" and c < MAX_STACK then
					targetSlot = slotIndex; existingCount = c
				elseif n == nil or n == "" then
					targetSlot = slotIndex; existingCount = 0
				end
			end
			if not targetSlot then
				for i = 1, CONTAINER_SLOTS do
					local n = container:GetAttribute("Slot" .. i .. "_Name")
					local k = container:GetAttribute("Slot" .. i .. "_Kind")
					if n == itemName and k == "tool" then
						local c = container:GetAttribute("Slot" .. i .. "_Count") or 0
						if c < MAX_STACK then targetSlot = i; existingCount = c; break end
					end
				end
			end
			if not targetSlot then
				for i = 1, CONTAINER_SLOTS do
					local n = container:GetAttribute("Slot" .. i .. "_Name")
					if n == nil or n == "" then targetSlot = i; existingCount = 0; break end
				end
			end
			if not targetSlot then return end

			local space = MAX_STACK - existingCount
			local toPut = math.min(#tools, space)
			if toPut <= 0 then return end

			local storage = getOrCreateToolStorage(container)
			for i = 1, toPut do
				tools[i].Parent = storage
				hideStoredTool(tools[i])
			end

			container:SetAttribute("Slot" .. targetSlot .. "_Name", itemName)
			container:SetAttribute("Slot" .. targetSlot .. "_Count", existingCount + toPut)
			container:SetAttribute("Slot" .. targetSlot .. "_Kind", "tool")
			return
		end

		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		local have = inv[itemName] or 0
		if have < count then
			if _G.SendInventory then _G.SendInventory(player) end
			return
		end

		slotIndex = tonumber(slotIndex)
		local targetSlot = nil
		local existingCount = 0

		if slotIndex and slotIndex >= 1 and slotIndex <= CONTAINER_SLOTS then
			local n = container:GetAttribute("Slot" .. slotIndex .. "_Name")
			local c = container:GetAttribute("Slot" .. slotIndex .. "_Count") or 0
			if n == itemName and c < MAX_STACK then
				targetSlot = slotIndex
				existingCount = c
			elseif n == nil or n == "" then
				targetSlot = slotIndex
				existingCount = 0
			end
		end

		if not targetSlot then
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
		if not targetSlot then
			if _G.SendInventory then _G.SendInventory(player) end
			return
		end

		local space = MAX_STACK - existingCount
		local toPut = math.min(count, space)
		if toPut <= 0 then
			if _G.SendInventory then _G.SendInventory(player) end
			return
		end

		if _G.RemoveResourceFromInventory then
			_G.RemoveResourceFromInventory(player, itemName, toPut)
		else
			inv[itemName] = have - toPut
		end

		container:SetAttribute("Slot" .. targetSlot .. "_Name", itemName)
		container:SetAttribute("Slot" .. targetSlot .. "_Count", existingCount + toPut)

		if _G.SendInventory then _G.SendInventory(player) end

	elseif action == "move" then
		local src = tonumber(slotIndex)
		local dst = tonumber(itemName)
		if not src or not dst then return end
		if src == dst then return end
		if src < 1 or src > CONTAINER_SLOTS then return end
		if dst < 1 or dst > CONTAINER_SLOTS then return end

		local srcName = container:GetAttribute("Slot" .. src .. "_Name")
		local srcCount = container:GetAttribute("Slot" .. src .. "_Count") or 0
		local srcKind = container:GetAttribute("Slot" .. src .. "_Kind")
		if typeof(srcName) ~= "string" or srcName == "" or srcCount <= 0 then return end

		local dstName = container:GetAttribute("Slot" .. dst .. "_Name")
		local dstCount = container:GetAttribute("Slot" .. dst .. "_Count") or 0
		local dstKind = container:GetAttribute("Slot" .. dst .. "_Kind")

		if dstName == nil or dstName == "" then
			container:SetAttribute("Slot" .. dst .. "_Name", srcName)
			container:SetAttribute("Slot" .. dst .. "_Count", srcCount)
			container:SetAttribute("Slot" .. dst .. "_Kind", srcKind)
			container:SetAttribute("Slot" .. src .. "_Name", "")
			container:SetAttribute("Slot" .. src .. "_Count", 0)
			container:SetAttribute("Slot" .. src .. "_Kind", nil)
		elseif dstName == srcName and dstKind == srcKind then
			local space = MAX_STACK - dstCount
			if space <= 0 then
				container:SetAttribute("Slot" .. dst .. "_Name", srcName)
				container:SetAttribute("Slot" .. dst .. "_Count", srcCount)
				container:SetAttribute("Slot" .. dst .. "_Kind", srcKind)
				container:SetAttribute("Slot" .. src .. "_Name", dstName)
				container:SetAttribute("Slot" .. src .. "_Count", dstCount)
				container:SetAttribute("Slot" .. src .. "_Kind", dstKind)
			else
				local toMove = math.min(srcCount, space)
				container:SetAttribute("Slot" .. dst .. "_Count", dstCount + toMove)
				if toMove >= srcCount then
					container:SetAttribute("Slot" .. src .. "_Name", "")
					container:SetAttribute("Slot" .. src .. "_Count", 0)
					container:SetAttribute("Slot" .. src .. "_Kind", nil)
				else
					container:SetAttribute("Slot" .. src .. "_Count", srcCount - toMove)
				end
			end
		else
			container:SetAttribute("Slot" .. dst .. "_Name", srcName)
			container:SetAttribute("Slot" .. dst .. "_Count", srcCount)
			container:SetAttribute("Slot" .. dst .. "_Kind", srcKind)
			container:SetAttribute("Slot" .. src .. "_Name", dstName)
			container:SetAttribute("Slot" .. src .. "_Count", dstCount)
			container:SetAttribute("Slot" .. src .. "_Kind", dstKind)
		end
	end
end)

for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and child.Name == CONTAINER_NAME then
		setupContainerPrompt(child)
	end
end
