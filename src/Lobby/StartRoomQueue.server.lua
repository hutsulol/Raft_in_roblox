-- StartRoomQueue.server.lua
-- Queue tracker for lobby rooms. Auto-adapts to where it's placed:
--
--   * If parented INSIDE a room Model → operates on script.Parent only
--     (per-room mode). Useful when each room ships with its own copy.
--   * Anywhere else (ServerScriptService.Lobby, etc.) → walks
--     workspace for every Model named "Barrier_Players" and treats
--     its first Model ancestor as a room (central mode). Hot-adds
--     new rooms via DescendantAdded.
--
-- Inside each room we expect:
--   Ring (BasePart)                       — inner play floor
--   RingBeams.Barrier_Players (Model)     — corner Attachments forming
--                                            the queue-perimeter beams
--   InfoPart > Bg.Container.Entry         — text-list entry template
--   InfoPart > ParticipantsGui.Container.Entry — avatar tile template
--   CharacterCount (SurfaceGui w/ TextLabel)   — "N / MAX" readout
--
-- A player auto-joins the room's queue the moment their
-- HumanoidRootPart enters either the Ring's bbox or the
-- Barrier_Players polygon. Stepping out (or disconnecting) auto-
-- leaves. No prompts.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ─── Config ───────────────────────────────────────────────────────

-- Capacity ("MAX" in the count label) reads from a MaxPlayers
-- attribute on the room model first; falls back to a per-name default
-- below, else to FALLBACK_MAX.
local DEFAULT_MAX_BY_NAME = {
	StartRoom    = 1,
	DuelPad      = 2,
	DuelRing_1v1 = 1,
	DuelRing_2v2 = 4,
	DuelRing_3v3 = 6,
	DuelRing_4v4 = 8,
}
local FALLBACK_MAX     = 4
local POLL_INTERVAL    = 0.25
local VERTICAL_SLACK   = 12  -- studs of Y room above/below the zone
local FULL_TIMER_SECS  = 10  -- countdown once a room hits capacity

local LOG_TAG = "[StartRoomQueue]"

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

-- ─── UI helpers ──────────────────────────────────────────────────

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

-- ─── Per-room state ──────────────────────────────────────────────

local roomState = {}  -- [roomModel] = state

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
		queue           = {},
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
		ring            = ring,
		barrier         = barrier,
		locked          = false,
		timerExpires    = nil,
		-- Cache the Ring's Beam children so the sweep doesn't
		-- re-walk descendants every 0.25 s.
		ringBeams       = {},
	}
	if ring then
		for _, desc in ring:GetDescendants() do
			if desc:IsA("Beam") then
				table.insert(state.ringBeams, desc)
			end
		end
	end
	roomState[roomModel] = state

	print(string.format(
		"%s registered %q. attachments=%s Ring=%s CountLabel=%s PartsTpl=%s BgTpl=%s Max=%d",
		LOG_TAG, roomModel:GetFullName(),
		tostring(attachCount),
		tostring(ring and "ok" or "<missing>"),
		tostring(countLabel and "ok" or "<missing>"),
		tostring(partsTemplate and "ok" or "<missing>"),
		tostring(bgTemplate and "ok" or "<missing>"),
		state.maxPlayers))

	return state
end

-- ─── UI sync ─────────────────────────────────────────────────────

local function queueSize(state)
	local n = 0
	for _ in pairs(state.queue) do n = n + 1 end
	return n
end

local function updateCount(state)
	if not state.countLabel then return end
	if state.locked and state.timerExpires then
		-- Countdown takes over the slot read-out while the room is
		-- locked. We refresh from the sweep so the value ticks down.
		local remaining = math.max(0, math.ceil(state.timerExpires - os.clock()))
		state.countLabel.Text = tostring(remaining)
	else
		state.countLabel.Text = string.format("%d / %d", queueSize(state), state.maxPlayers)
	end
end

-- Drive the glow Beams on the Ring based on whether anyone is in
-- queue. Cheap — cached BasePart references, no descendant walk
-- per sweep.
local function updateRingBeams(state)
	local on = next(state.queue) ~= nil
	for _, beam in state.ringBeams do
		if beam.Parent then beam.Enabled = on end
	end
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
	print(string.format("%s %s joined %q (count=%d/%d)",
		LOG_TAG, player.Name, state.room.Name, queueSize(state), state.maxPlayers))
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

-- ─── Discovery: pick rooms based on where the script lives ──────

-- A "room container" is the closest Folder/Model ancestor of the
-- barrier that ALSO carries one of the room's UI pieces (InfoPart or
-- CharacterCount). That lets us climb through an intermediate
-- RingBeams folder without stopping there, and stop before we hit a
-- DuelRingsGroup-style wrapper that contains multiple rooms.
local function isRoomContainer(container)
	if not container then return false end
	if not (container:IsA("Folder") or container:IsA("Model")) then return false end
	return container:FindFirstChild("CharacterCount", true) ~= nil
		or container:FindFirstChild("InfoPart", true) ~= nil
end

local function findRoomFor(barrier)
	local cur = barrier.Parent
	while cur and cur ~= workspace do
		if isRoomContainer(cur) then return cur end
		cur = cur.Parent
	end
	return nil
end

local parent = script.Parent
-- Per-room mode triggers when the script lives directly inside a
-- container that already qualifies as a room (has CharacterCount /
-- InfoPart under it). Accept Folder or Model — your DuelRing_*
-- wrappers are Folders, not Models.
local isInsideRoom = isRoomContainer(parent)

if isInsideRoom then
	-- Per-room mode: bind to script.Parent only.
	ensureRoomState(parent)
	print(string.format("%s per-room mode bound to %s",
		LOG_TAG, parent:GetFullName()))
else
	-- Central mode: discover every Barrier_Players in workspace and
	-- register its first Model ancestor as a room. Hot-add new ones
	-- via DescendantAdded so a lobby that streams in arenas later
	-- still picks them up.
	for _, desc in workspace:GetDescendants() do
		if desc.Name == "Barrier_Players" and desc:IsA("Model") then
			local room = findRoomFor(desc)
			if room then ensureRoomState(room) end
		end
	end
	workspace.DescendantAdded:Connect(function(desc)
		if desc.Name == "Barrier_Players" and desc:IsA("Model") then
			task.wait(0.1)  -- let sibling parts settle into the model
			local room = findRoomFor(desc)
			if room and not roomState[room] then
				ensureRoomState(room)
			end
		end
	end)
	local n = 0
	for _ in pairs(roomState) do n = n + 1 end
	print(string.format("%s central mode — discovered %d room(s) at boot.",
		LOG_TAG, n))
end

-- ─── Sweep loop ──────────────────────────────────────────────────

-- Called every sweep on a state that's currently locked. Refreshes
-- the timer display, and on expiry fires _G.OnRoomFull (if defined)
-- + force-empties the queue so the lock cycle doesn't immediately
-- re-trigger.
local function tickLock(state)
	if not state.locked or not state.timerExpires then return end
	if os.clock() < state.timerExpires then
		-- Just refresh the visible countdown.
		updateCount(state)
		return
	end

	-- Timer expired. Snapshot the players, fire the optional handler
	-- so downstream code can teleport them / start a match / etc.
	local players = {}
	for uid in pairs(state.queue) do
		local p = Players:GetPlayerByUserId(uid)
		if p then table.insert(players, p) end
	end
	if typeof(_G.OnRoomFull) == "function" then
		pcall(_G.OnRoomFull, state.room, players)
	else
		print(string.format("%s %s timer expired with %d player(s); no _G.OnRoomFull handler wired",
			LOG_TAG, state.room.Name, #players))
	end

	-- Force-clear the queue so the room frees up. If the players are
	-- still physically in the zone the next sweep re-adds them and
	-- the 10s cycle restarts; if the handler teleported them out the
	-- zone is empty and the room is back to "0 / N".
	for uid in pairs(state.queue) do
		removePlayer(state, uid)
	end
	state.locked = false
	state.timerExpires = nil
	updateCount(state)
end

local function sweep()
	for room, state in pairs(roomState) do
		if not room.Parent then
			roomState[room] = nil
		else
			-- Recompute zones every pass: a drifting lobby platform
			-- would otherwise strand the zone in world space.
			if state.barrier and state.barrier.Parent then
				state.barrierCF, state.barrierSize = computeBarrierZone(state.barrier)
			end
			if state.ring and state.ring.Parent then
				state.ringCF, state.ringSize = partAsZone(state.ring)
			end

			local seen = {}
			for _, player in Players:GetPlayers() do
				local char = player.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local pos = hrp.Position
					local inside = (state.barrierCF and pointInZone(pos, state.barrierCF, state.barrierSize))
						or (state.ringCF and pointInZone(pos, state.ringCF, state.ringSize))
					if inside then
						if state.locked then
							-- Locked room: existing queued players
							-- keep their slot, new walk-ins are
							-- ignored so the countdown can resolve
							-- with the original roster.
							if state.queue[player.UserId] then
								seen[player.UserId] = true
							end
						else
							seen[player.UserId] = true
							if not state.queue[player.UserId] then
								addPlayer(state, player)
							end
						end
					end
				end
			end
			for uid in pairs(state.queue) do
				if not seen[uid] then
					removePlayer(state, uid)
				end
			end

			-- Trip the lock the moment the queue fills up. Player
			-- leaving during the countdown cancels the lock and
			-- restores the normal "N / N" display.
			local size = queueSize(state)
			if not state.locked and size >= state.maxPlayers and size > 0 then
				state.locked = true
				state.timerExpires = os.clock() + FULL_TIMER_SECS
				print(string.format("%s %s reached capacity (%d) — %ds countdown started",
					LOG_TAG, state.room.Name, state.maxPlayers, FULL_TIMER_SECS))
				updateCount(state)
			elseif state.locked and size < state.maxPlayers then
				state.locked = false
				state.timerExpires = nil
				updateCount(state)
				print(string.format("%s %s lock cancelled — player left during countdown",
					LOG_TAG, state.room.Name))
			end

			tickLock(state)
			updateRingBeams(state)
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

-- Console helper: `_G.DumpStartRoomQueue()` dumps every room's state.
_G.DumpStartRoomQueue = function()
	for room, state in pairs(roomState) do
		print(string.format("%s %s max=%d queue=%d barrier=%s ring=%s",
			LOG_TAG, room:GetFullName(), state.maxPlayers, queueSize(state),
			state.barrierSize and tostring(state.barrierSize) or "<nil>",
			state.ringSize    and tostring(state.ringSize)    or "<nil>"))
	end
end
