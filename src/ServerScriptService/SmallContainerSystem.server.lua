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

local function findTemplate(name)
	name = name or "Container_empty"
	local folder = rs:FindFirstChild("Containers_Player")
	local tmpl = folder and folder:FindFirstChild(name)
	if not tmpl then
		tmpl = rs:FindFirstChild(name, true)
	end
	return tmpl
end

local function countFilledSlots(container)
	local filled = 0
	for i = 1, CONTAINER_SLOTS do
		local name = container:GetAttribute("Slot" .. i .. "_Name")
		local count = container:GetAttribute("Slot" .. i .. "_Count") or 0
		if typeof(name) == "string" and name ~= "" and count > 0 then
			filled = filled + 1
		end
	end
	return filled
end

local function getContainerModelName(filled)
	if filled >= CONTAINER_SLOTS then
		return "Container_full"
	elseif filled >= 3 then
		return "Container_50"
	else
		return "Container_empty"
	end
end

local setupContainerPrompt -- forward decl for swap → setup

-- Same pattern as ThirstSystem.swapPurifierModel: clear children,
-- reparent the new template's children, preserve the container's
-- world CFrame + slot attributes (attributes live on the container
-- instance itself, so they survive child destruction), re-weld to
-- the raft, and re-bind the ProximityPrompt on the new primary part.
local function swapContainerModel(container)
	if not container or not container.Parent then return end

	local filled = countFilledSlots(container)
	local modelName = getContainerModelName(filled)

	local currentModel = container:GetAttribute("ModelName")
	if currentModel == modelName then return end

	local template = findTemplate(modelName)
	if not template then
		warn("[SmallContainer] swap model not found: " .. modelName)
		return
	end

	-- Snapshot raft velocity + capture container pose AS RAFT-RELATIVE
	-- before any destroy/clone work (T14). The destroy + clone steps span
	-- a couple of physics frames during which the raft drifts; saving a
	-- world CFrame and PivotTo'ing it back later places the new parts
	-- against a stale raft pose, then the welds lock that drift in and
	-- the solver kicks the assembly to compensate → bouncing.
	local raft = workspace:FindFirstChild("Raft")
	local raftPrimary = raft and raft.PrimaryPart or nil
	local linVel, angVel
	if raftPrimary then
		linVel = raftPrimary.AssemblyLinearVelocity
		angVel = raftPrimary.AssemblyAngularVelocity
	end

	local savedCF = container.PrimaryPart and container.PrimaryPart.CFrame
	if not savedCF then
		local first = container:FindFirstChildWhichIsA("BasePart", true)
		savedCF = first and first.CFrame
	end
	if not savedCF then return end
	local savedRelCF
	if raftPrimary then
		savedRelCF = raftPrimary.CFrame:ToObjectSpace(savedCF)
	end

	-- Preserve StoredTools across model swaps; only destroy the visual
	-- children (BaseParts, meshes, etc) the template will replace.
	for _, child in container:GetChildren() do
		if child.Name ~= "StoredTools" then
			child:Destroy()
		end
	end

	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			if clone:IsA("BasePart") then clone.Anchored = true end
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
			clone.Parent = container
		end
		if template.PrimaryPart then
			local newPrimary = container:FindFirstChild(template.PrimaryPart.Name)
			if newPrimary then container.PrimaryPart = newPrimary end
		end
		if not container.PrimaryPart then
			local first = container:FindFirstChildWhichIsA("BasePart", true)
			if first then container.PrimaryPart = first end
		end
	end

	-- Reposition against the raft's CURRENT pose, not the stale one.
	if savedRelCF and raftPrimary then
		container:PivotTo(raftPrimary.CFrame * savedRelCF)
	else
		container:PivotTo(savedCF)
	end

	local storage = container:FindFirstChild("StoredTools")
	if raftPrimary then
		for _, part in container:GetDescendants() do
			if part:IsA("BasePart") and not (storage and part:IsDescendantOf(storage)) then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raftPrimary
				weld.Parent = part
				part.Anchored = false
			end
		end
		raftPrimary.AssemblyLinearVelocity  = linVel
		raftPrimary.AssemblyAngularVelocity = angVel
	end

	container:SetAttribute("ModelName", modelName)

	if setupContainerPrompt then
		setupContainerPrompt(container)
	end
end

local function initSlots(model)
	for i = 1, CONTAINER_SLOTS do
		if model:GetAttribute("Slot" .. i .. "_Name") == nil then
			model:SetAttribute("Slot" .. i .. "_Name", "")
			model:SetAttribute("Slot" .. i .. "_Count", 0)
		end
	end
end

setupContainerPrompt = function(model)
	initSlots(model)
	model:SetAttribute("SlotCount", CONTAINER_SLOTS)
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

-- ───────────────── Tool storage helpers ─────────────────
-- Tools (Wood_Knife, Injector, capsules, placeable tool stubs, …) live
-- as Tool Instances in the player's Backpack / Character. We store them
-- inside a hidden "StoredTools" folder on the container and track the
-- per-slot count through the same Slot{i}_Name / Slot{i}_Count
-- attributes. Slot{i}_Kind = "tool" marks a slot as holding tools so
-- the take-side knows to hand back Instances instead of resource stacks.

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

-- Strip any WeldConstraints inside the tool that reference parts outside
-- of it. A previous model-swap bug welded every stored tool's Handle to
-- the raft; without cleanup the tool stays stuck to the raft after
-- being handed back to the player.
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

-- Tool BaseParts still render and collide when the Tool lives in a
-- Workspace Model/Folder (unlike Backpack/Character where the engine
-- hides them). Hide the handles while stored, cache their original
-- values on attributes, and restore them when the tool is handed back.
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
			-- Anchor so the Handle can't fall past FallenPartsDestroyHeight
			-- and get reaped by the engine while it's sitting in the chest.
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

	-- Velocity snapshot/restore around the placement weld (T13).
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = raft.PrimaryPart
			weld.Parent = part
		end
	end

	primary.AssemblyLinearVelocity  = linVel
	primary.AssemblyAngularVelocity = angVel

	container:SetAttribute("ModelName", "Container_empty")
	setupContainerPrompt(container)

	tool:Destroy()
end)

-- ═══════════════════════════════════════════
-- ContainerAction: take / put
-- ═══════════════════════════════════════════
containerAction.OnServerEvent:Connect(function(player, action, container, slotIndex, itemName, count, kind)
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
			-- Re-count matching tools actually left in storage rather than
			-- subtracting from the attribute count: if the engine destroyed
			-- some Tool instances (e.g. Handle fell past FallenPartsDestroy
			-- Height before this bug was fixed), the attribute is stale and
			-- we need to drop the ghost entries so the slot doesn't stay
			-- unretrievable forever.
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
			swapContainerModel(container)
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

		swapContainerModel(container)

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

			local function slotAcceptsTool(i)
				local n = container:GetAttribute("Slot" .. i .. "_Name")
				local k = container:GetAttribute("Slot" .. i .. "_Kind")
				local c = container:GetAttribute("Slot" .. i .. "_Count") or 0
				if n == itemName and k == "tool" and c < MAX_STACK then
					return true, c
				end
				if n == nil or n == "" then
					return true, 0
				end
				return false, 0
			end

			if slotIndex and slotIndex >= 1 and slotIndex <= CONTAINER_SLOTS then
				local ok, c = slotAcceptsTool(slotIndex)
				if ok then targetSlot = slotIndex; existingCount = c end
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

			swapContainerModel(container)
			return
		end

		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		local have = inv[itemName] or 0
		if have < count then
			if _G.SendInventory then _G.SendInventory(player) end
			return
		end

		-- If the client specified a target slot (drag lands in Slot N),
		-- honour it: stack when the item matches, claim when empty. Fall
		-- back to auto-find only when the requested slot isn't usable.
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
		-- Chest genuinely full: sync the client so the item the shift-click
		-- optimistically drained locally comes back to the inventory and
		-- no stacks are silently lost.
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

		swapContainerModel(container)

		-- If the client sent more than the chest could accept (space ran
		-- out mid-stack), the leftover is still in the player's inventory
		-- total. SendInventory drops it back into an empty slot instead
		-- of disappearing.
		if _G.SendInventory then _G.SendInventory(player) end

	elseif action == "move" then
		-- Chest-to-chest drag: slotIndex = src, itemName = dst (we reuse
		-- parameter slots since the RemoteEvent signature is fixed).
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

		swapContainerModel(container)
	end
end)

-- Setup existing containers on script load (after raft restore) and
-- reconcile the visual model to whatever slot counts survived the save.
for _, child in workspace:GetDescendants() do
	if child:IsA("Model") and child.Name == "SmallContainer" then
		setupContainerPrompt(child)
		swapContainerModel(child)
	end
end
