-- DuelRoomQueue.server.lua
-- Per-room queue manager for the lobby duel rings.
--
-- Each room model (DuelPad / DuelRing_2v2 / 3v3 / 4v4) lives in
-- workspace and bundles:
--   * Ring (BasePart)   — the inner play area
--   * RingBeams.Barrier_Players (Model with corner Attachments
--     forming the queue-perimeter beams)
--   * InfoPart > Bg.Container.Entry            (textual list entry template)
--   * InfoPart > ParticipantsGui.Container.Entry (avatar tile template)
--   * CharacterCount (SurfaceGui showing "N / MAX")
--
-- A player automatically joins the room's queue the moment their
-- HumanoidRootPart enters either the Ring's bbox or the Barrier_Players
-- polygon. Stepping out removes them. No prompts.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ─── Config ───────────────────────────────────────────────────────

-- Rooms we manage. Names match the Studio-authored Model names.
-- The capacity (right column) is the "MAX" displayed in the SurfaceGui
-- count and acts as the soft cap for the queue. Override per-room by
-- setting a `MaxPlayers` attribute on the room model in Studio.
local ROOMS = {
	{ name = "DuelPad",      defaultMax = 2 },  -- 1v1
	{ name = "DuelRing_2v2", defaultMax = 4 },  -- 2v2
	{ name = "DuelRing_3v3", defaultMax = 6 },  -- 3v3
	{ name = "DuelRing_4v4", defaultMax = 8 },  -- 4v4
}

local POLL_INTERVAL = 0.25  -- seconds between zone-occupancy sweeps
local VERTICAL_SLACK = 12   -- studs of Y room above/below the zone
                             -- floor so jumping / on-stairs players
                             -- still count as "inside"

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
-- (C1..C4 / P1..P4 in 2v2+, just four corners in 1v1). Compute the
-- axis-aligned XZ rectangle that wraps every attachment, with vertical
-- slack so jumps don't drop the player out of the queue.
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
	return CFrame.new(center), size
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

-- Hide a template instance (used as an authoring reference) without
-- destroying it, so we can :Clone() from it on every join.
local function hideTemplate(inst)
	if not inst then return end
	-- Setting Visible=false on a Frame / ImageLabel is enough; for
	-- generic containers the property might not exist, so guard.
	local ok = pcall(function() inst.Visible = false end)
	if not ok then end
end

-- Wipe stale per-player entries left from a previous play session
-- (Studio reload, server restart, …). Keep layout/utility instances.
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

local function ensureRoomState(roomModel)
	if roomState[roomModel] then return roomState[roomModel] end

	local infoPart       = roomModel:FindFirstChild("InfoPart")
	local bg             = infoPart and infoPart:FindFirstChild("Bg")
	local bgContainer    = bg and bg:FindFirstChild("Container")
	local bgTemplate     = bgContainer and bgContainer:FindFirstChild("Entry")
	local partsGui       = infoPart and infoPart:FindFirstChild("ParticipantsGui")
	local partsContainer = partsGui and partsGui:FindFirstChild("Container")
	local partsTemplate  = partsContainer and partsContainer:FindFirstChild("Entry")
	local countGui       = roomModel:FindFirstChild("CharacterCount", true)
	local countLabel     = countGui and countGui:FindFirstChildWhichIsA("TextLabel", true)

	local ring     = roomModel:FindFirstChild("Ring")
	local ringCF, ringSize = partAsZone(ring)

	local barrier  = roomModel:FindFirstChild("Barrier_Players", true)
	local barrierCF, barrierSize
	if barrier then
		barrierCF, barrierSize = computeBarrierZone(barrier)
	end

	local maxPlayers = roomModel:GetAttribute("MaxPlayers")
	if not maxPlayers then
		for _, entry in ROOMS do
			if entry.name == roomModel.Name then
				maxPlayers = entry.defaultMax
				break
			end
		end
	end
	maxPlayers = maxPlayers or 4

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
		maxPlayers      = maxPlayers,
		ringCF          = ringCF,
		ringSize        = ringSize,
		barrierCF       = barrierCF,
		barrierSize     = barrierSize,
	}
	roomState[roomModel] = state
	return state
end

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

	-- Bg entry (textual list line — usually carries the player name).
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

	-- ParticipantsGui tile (avatar headshot inside a rounded square).
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
	for _, entry in ROOMS do
		local room = workspace:FindFirstChild(entry.name, true)
		if room and room:IsA("Model") then
			local state = ensureRoomState(room)

			-- Recompute the barrier each pass: corner attachments
			-- could be parented to a moving Model (raft / lobby
			-- platform), and the cost is trivial.
			local barrier = room:FindFirstChild("Barrier_Players", true)
			if barrier then
				state.barrierCF, state.barrierSize = computeBarrierZone(barrier)
			end
			local ring = room:FindFirstChild("Ring")
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

-- Drop a player from every queue on disconnect even if the sweep
-- hasn't run yet — avoids leaving a stale avatar tile up for a
-- quarter-second.
Players.PlayerRemoving:Connect(function(player)
	for _, state in pairs(roomState) do
		removePlayer(state, player.UserId)
	end
end)
