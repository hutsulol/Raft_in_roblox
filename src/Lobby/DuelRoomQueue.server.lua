-- DuelRoomQueue.server.lua
-- Per-room queue manager for the lobby duel rings.
--
-- A "duel room" is any Model whose descendant tree contains a
-- `Barrier_Players` Model. The script discovers them automatically
-- so the Studio author can name the parent anything they like
-- (DuelPad / DuelRing_2v2 / Arena_North / …). Inside the room we
-- expect:
--   * Ring (BasePart)   — the inner play area
--   * RingBeams.Barrier_Players (Model with corner Attachments
--     forming the queue-perimeter beams)
--   * InfoPart > Bg.Container.Entry            (textual list entry template)
--   * InfoPart > ParticipantsGui.Container.Entry (avatar tile template)
--   * CharacterCount (SurfaceGui showing "N / MAX")
--
-- A player automatically joins the room's queue the moment their
-- HumanoidRootPart enters either the Ring's bbox or the
-- Barrier_Players polygon. Stepping out removes them. No prompts.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ─── Config ───────────────────────────────────────────────────────

-- Capacity (the "MAX" in the SurfaceGui count) comes from a
-- `MaxPlayers` attribute on the room model first; falls back to a
-- per-name default below, then to 4.
local DEFAULT_MAX_BY_NAME = {
	DuelPad      = 2,
	DuelRing_2v2 = 4,
	DuelRing_3v3 = 6,
	DuelRing_4v4 = 8,
}
local FALLBACK_MAX = 4

local POLL_INTERVAL  = 0.25  -- seconds between zone-occupancy sweeps
local VERTICAL_SLACK = 12    -- studs of Y room above/below the zone
                              -- so jumping / on-stairs players still
                              -- count as "inside"
local LOG_TAG = "[DuelRoomQueue]"

-- ─── Avatar headshot helper ──────────────────────────────────────

local headshotCache = {}
local function getHeadshot(userId)
	if headshotCache[userId] then return headshotCache[userId] end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
	end)
	if ok and content then
		headshotCache[userId] = content
		return content
	end
	return "rbxasset://textures/ui/GuiImagePlaceholder.png"
end

-- ─── Zone geometry ───────────────────────────────────────────────

-- The barrier is drawn as Beams between corner Attachments
-- (C1..C4 / P1..P4). Compute the axis-aligned XZ rectangle that
-- wraps every attachment, with vertical slack so jumps don't drop
-- the player out of the queue.
local function computeBarrierZone(barrierModel)
	local minX, minZ =  math.huge,  math.huge
	local maxX, maxZ = -math.huge, -math.huge
	local sumY, count = 0, 0
	for _, desc in barrierModel:GetDescendants() do
		if desc:IsA("Attachment") then
			local p = desc.WorldPosition
			if p.X < minX then minX = p.X end
			if p.X > maxX then maxX = p.X end
			if p.Z < minZ then minZ = p.Z end
			if p.Z > maxZ then maxZ = p.Z end
			sumY = sumY + p.Y
			count = count + 1
		end
	end
	if count == 0 then return nil end
	local centerY = sumY / count
	local center = Vector3.new((minX + maxX) / 2, centerY, (minZ + maxZ) / 2)
	local size   = Vector3.new(maxX - minX, VERTICAL_SLACK * 2, maxZ - minZ)
	return CFrame.new(center), size, count
end

-- Returns CFrame + Size for a Ring / Pad BasePart, expanded vertically.
local function partAsZone(part)
	if not part or not part:IsA("BasePart") then return nil end
	local size = Vector3.new(part.Size.X, part.Size.Y + VERTICAL_SLACK * 2, part.Size.Z)
	return part.CFrame, size
end

local function pointInZone(point, zoneCF, zoneSize)
	if not zoneCF or not zoneSize then return false end
	local localPos = zoneCF:PointToObjectSpace(point)
	return math.abs(localPos.X) <= zoneSize.X / 2
		and math.abs(localPos.Y) <= zoneSize.Y / 2
		and math.abs(localPos.Z) <= zoneSize.Z / 2
end

local function pointInsideRoom(point, state)
	if state.barrierCF and pointInZone(point, state.barrierCF, state.barrierSize) then
		return true
	end
	if state.ringCF and pointInZone(point, state.ringCF, state.ringSize) then
		return true
	end
	return false
end

-- ─── Per-room state ──────────────────────────────────────────────

local roomState = {}  -- [roomModel] = state

local function hideTemplate(inst)
	if not inst then return end
	pcall(function() inst.Visible = false end)
end

local UTILITY_CLASSES = {
	UIListLayout = true, UIGridLayout = true, UIPadding = true,
	UIAspectRatioConstraint = true, UISizeConstraint = true,
	UICorner = true, UIStroke = true, UIGradient = true,
}
local function clearStaleEntries(container, templateName)
	if not container then return end
	for _, child in container:GetChildren() do
		if not UTILITY_CLASSES[child.ClassName] and child.Name ~= templateName then
			child:Destroy()
		end
	end
end

local function defaultMaxFor(roomModel)
	local attr = roomModel:GetAttribute("MaxPlayers")
	if type(attr) == "number" then return attr end
	return DEFAULT_MAX_BY_NAME[roomModel.Name] or FALLBACK_MAX
end

local function ensureRoomState(roomModel)
	if roomState[roomModel] then return roomState[roomModel] end

	local infoPart       = roomModel:FindFirstChild("InfoPart", true)
	local bg             = infoPart and infoPart:FindFirstChild("Bg", true)
	local bgContainer    = bg and bg:FindFirstChild("Container", true)
	local bgTemplate     = bgContainer and bgContainer:FindFirstChild("Entry")
	local partsGui       = infoPart and infoPart:FindFirstChild("ParticipantsGui", true)
	local partsContainer = partsGui and partsGui:FindFirstChild("Container", true)
	local partsTemplate  = partsContainer and partsContainer:FindFirstChild("Entry")
	local countGui       = roomModel:FindFirstChild("CharacterCount", true)
	local countLabel     = countGui and countGui:FindFirstChildWhichIsA("TextLabel", true)

	local ring     = roomModel:FindFirstChild("Ring", true)
	local ringCF, ringSize = partAsZone(ring)

	local barrier  = roomModel:FindFirstChild("Barrier_Players", true)
	local barrierCF, barrierSize, attachCount
	if barrier then
		barrierCF, barrierSize, attachCount = computeBarrierZone(barrier)
	end

	hideTemplate(bgTemplate)
	hideTemplate(partsTemplate)
	clearStaleEntries(bgContainer,    bgTemplate    and bgTemplate.Name)
	clearStaleEntries(partsContainer, partsTemplate and partsTemplate.Name)

	local state = {
		room            = roomModel,
		queue           = {},   -- [userId] = true
		bgTemplate      = bgTemplate,
		bgContainer     = bgContainer,
		partsTemplate   = partsTemplate,
		partsContainer  = partsContainer,
		countLabel      = countLabel,
		maxPlayers      = defaultMaxFor(roomModel),
		ringCF          = ringCF,
		ringSize        = ringSize,
		barrierCF       = barrierCF,
		barrierSize     = barrierSize,
	}
	roomState[roomModel] = state

	print(string.format(
		"%s registered room %q. Barrier attachments=%s. Ring=%s. CountLabel=%s. PartsTemplate=%s. BgTemplate=%s. Max=%d",
		LOG_TAG,
		roomModel:GetFullName(),
		tostring(attachCount),
		tostring(ring and ring:GetFullName() or "<missing>"),
		tostring(countLabel and countLabel:GetFullName() or "<missing>"),
		tostring(partsTemplate and partsTemplate:GetFullName() or "<missing>"),
		tostring(bgTemplate and bgTemplate:GetFullName() or "<missing>"),
		state.maxPlayers
	))

	return state
end

-- ─── Auto-discovery ──────────────────────────────────────────────

-- A duel room is any Model whose subtree contains a Barrier_Players
-- Model. Walk workspace once at boot, then watch for additions.
local function findRoomFor(barrier)
	-- Climb until we either hit workspace (no Model wrapper) or the
	-- first Model ancestor. That ancestor is treated as the room.
	local cur = barrier.Parent
	while cur and cur ~= workspace do
		if cur:IsA("Model") then return cur end
		cur = cur.Parent
	end
	return nil
end

local function scanForRooms(root)
	for _, desc in root:GetDescendants() do
		if desc.Name == "Barrier_Players" and desc:IsA("Model") then
			local room = findRoomFor(desc)
			if room and not roomState[room] then
				ensureRoomState(room)
			end
		end
	end
end

scanForRooms(workspace)
workspace.DescendantAdded:Connect(function(desc)
	if desc.Name == "Barrier_Players" and desc:IsA("Model") then
		local room = findRoomFor(desc)
		if room and not roomState[room] then
			task.wait(0.1)  -- let sibling parts settle into the model
			ensureRoomState(room)
		end
	end
end)

local function roomCount()
	local n = 0
	for _ in pairs(roomState) do n = n + 1 end
	return n
end
print(string.format("%s discovered %d duel room(s) at boot.", LOG_TAG, roomCount()))

-- ─── UI sync ─────────────────────────────────────────────────────

local function updateCount(state)
	if not state.countLabel then return end
	local count = 0
	for _ in pairs(state.queue) do count = count + 1 end
	state.countLabel.Text = string.format("%d / %d", count, state.maxPlayers)
end

local function addPlayer(state, player)
	if state.queue[player.UserId] then return end
	state.queue[player.UserId] = true
	local uid = tostring(player.UserId)

	if state.bgTemplate and state.bgContainer then
		local entry = state.bgTemplate:Clone()
		entry.Name = uid
		pcall(function() entry.Visible = true end)
		local nameLabel = entry:FindFirstChild("Name", true)
			or entry:FindFirstChildWhichIsA("TextLabel", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = player.Name
		end
		entry.Parent = state.bgContainer
	end

	if state.partsTemplate and state.partsContainer then
		local entry = state.partsTemplate:Clone()
		entry.Name = uid
		pcall(function() entry.Visible = true end)
		local headshot = entry:FindFirstChild("Headshot", true)
		if headshot and headshot:IsA("ImageLabel") then
			headshot.Image = getHeadshot(player.UserId)
		end
		entry.Parent = state.partsContainer
	end

	updateCount(state)
	print(string.format("%s %s joined queue %q (count=%d/%d)",
		LOG_TAG, player.Name, state.room.Name,
		(function() local n=0 for _ in pairs(state.queue) do n=n+1 end return n end)(),
		state.maxPlayers))
end

local function removePlayer(state, userId)
	if not state.queue[userId] then return end
	state.queue[userId] = nil
	local uid = tostring(userId)
	if state.bgContainer then
		local e = state.bgContainer:FindFirstChild(uid)
		if e then e:Destroy() end
	end
	if state.partsContainer then
		local e = state.partsContainer:FindFirstChild(uid)
		if e then e:Destroy() end
	end
	updateCount(state)
end

-- ─── Sweep loop ──────────────────────────────────────────────────

local function sweep()
	for room, state in pairs(roomState) do
		if not room.Parent then
			roomState[room] = nil
		else
			-- Recompute the barrier each pass: corner attachments
			-- could be parented to a moving Model and the cost is
			-- trivial.
			local barrier = room:FindFirstChild("Barrier_Players", true)
			if barrier then
				state.barrierCF, state.barrierSize = computeBarrierZone(barrier)
			end
			local ring = room:FindFirstChild("Ring", true)
			if ring then
				state.ringCF, state.ringSize = partAsZone(ring)
			end

			local seen = {}
			for _, player in Players:GetPlayers() do
				local char = player.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and pointInsideRoom(hrp.Position, state) then
					seen[player.UserId] = true
					if not state.queue[player.UserId] then
						addPlayer(state, player)
					end
				end
			end
			for uid in pairs(state.queue) do
				if not seen[uid] then
					removePlayer(state, uid)
				end
			end
		end
	end
end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum = accum + dt
	if accum >= POLL_INTERVAL then
		accum = 0
		sweep()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, state in pairs(roomState) do
		removePlayer(state, player.UserId)
	end
end)

-- ─── Diagnostic helper ───────────────────────────────────────────
-- Run in the server console at any time:
--   _G.DumpDuelRooms()
-- to print every room's current queue, zone CFrame and capacity.
-- Cheaper than reading the running sweep state by hand.
_G.DumpDuelRooms = function()
	for room, state in pairs(roomState) do
		print(string.format("%s %s: max=%d queue=%d barrierSize=%s ringSize=%s",
			LOG_TAG, room:GetFullName(), state.maxPlayers,
			(function() local n=0 for _ in pairs(state.queue) do n=n+1 end return n end)(),
			state.barrierSize and tostring(state.barrierSize) or "<nil>",
			state.ringSize    and tostring(state.ringSize)    or "<nil>"))
	end
end
