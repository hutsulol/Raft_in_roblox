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

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

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

-- Destination for the countdown-finished teleport. Same place ID
-- LobbyServer uses for its raft / save-pad teleports. Each room can
-- override via a `DestinationPlaceId` attribute on its Model/Folder.
local DEFAULT_PLACE_ID = 77272676169005

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

-- Empty an entry's player-specific visuals — used both to scrub
-- newly-cloned slots into a neutral state and to clear a slot when
-- its assigned player walks out.
local function clearEntryVisuals(entry)
	if not entry then return end
	local nameLabel = entry:FindFirstChild("Name", true)
		or entry:FindFirstChildWhichIsA("TextLabel", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = ""
	end
	local headshot = entry:FindFirstChild("Headshot", true)
	if headshot and headshot:IsA("ImageLabel") then
		headshot.Image = ""
	end
end

-- Pick up the Entry instances the Studio author already dropped into
-- `container` and treat each one as a slot. We do NOT destroy /
-- clone / reposition anything — the author's layout, count and
-- positioning stays exactly as they built it. Per-player visuals
-- (Name TextLabel, Headshot Image) get reset to a neutral idle
-- state on script init, and filled / cleared by addPlayer /
-- removePlayer.
local function buildSlotsFromAuthoredEntries(container)
	if not container then return {} end
	local slots = {}
	for _, child in container:GetChildren() do
		if not UTILITY_CLASSES[child.ClassName] and child.Name == "Entry" then
			pcall(function() child.Visible = true end)
			clearEntryVisuals(child)
			table.insert(slots, { entry = child, assignedTo = nil })
		end
	end
	return slots
end

-- ─── Per-room state ──────────────────────────────────────────────

local roomState = {}  -- [roomModel] = state

local function ensureRoomState(roomModel)
	if roomState[roomModel] then return roomState[roomModel] end

	local infoPart       = roomModel:FindFirstChild("InfoPart", true)
	local bg             = infoPart and infoPart:FindFirstChild("Bg", true)
	local bgContainer    = bg and bg:FindFirstChild("Container", true)
	local partsGui       = infoPart and infoPart:FindFirstChild("ParticipantsGui", true)
	local partsContainer = partsGui and partsGui:FindFirstChild("Container", true)
	local countGui       = roomModel:FindFirstChild("CharacterCount", true)
	local countLabel     = countGui and countGui:FindFirstChildWhichIsA("TextLabel", true)

	local ring     = roomModel:FindFirstChild("Ring", true)
	local ringCF, ringSize = partAsZone(ring)

	-- The Studio author sometimes renames the perimeter beam model
	-- (Barrier_Players → Border_FindGame, …). Match either so the
	-- queue detection + the lock-yellow feedback below both wire up.
	local barrier  = roomModel:FindFirstChild("Barrier_Players", true)
		or roomModel:FindFirstChild("Border_FindGame", true)
		or roomModel:FindFirstChild("Border_Players", true)
	local barrierCF, barrierSize, attachCount
	if barrier then
		barrierCF, barrierSize, attachCount = computeBarrierZone(barrier)
	end

	-- Cache every Beam descendant of the barrier model with its
	-- author-time Color (ColorSequence), Transparency (NumberSequence)
	-- and LightInfluence (number). On state changes we override
	-- those properties; on the way back we restore each individual
	-- beam's original snapshot so the lobby looks the same as
	-- whatever the author built.
	local barrierBeams = {}
	if barrier then
		for _, desc in barrier:GetDescendants() do
			if desc:IsA("Beam") then
				barrierBeams[desc] = {
					color          = desc.Color,
					transparency   = desc.Transparency,
					lightInfluence = desc.LightInfluence,
				}
			end
		end
	end

	-- Capacity derivation:
	--   1. MaxPlayers attribute on the room (explicit override).
	--   2. Number of authored "Entry" instances in either container
	--      — lets the Studio author dictate capacity purely by how
	--      many slot frames they dropped in.
	--   3. DEFAULT_MAX_BY_NAME / FALLBACK_MAX.
	local bgSlots    = buildSlotsFromAuthoredEntries(bgContainer)
	local partsSlots = buildSlotsFromAuthoredEntries(partsContainer)
	local maxPlayers = roomModel:GetAttribute("MaxPlayers")
	if type(maxPlayers) ~= "number" then
		maxPlayers = math.max(#bgSlots, #partsSlots)
		if maxPlayers <= 0 then
			maxPlayers = DEFAULT_MAX_BY_NAME[roomModel.Name] or FALLBACK_MAX
		end
	end

	local state = {
		room            = roomModel,
		queue           = {},
		bgSlots         = bgSlots,
		partsSlots      = partsSlots,
		countLabel      = countLabel,
		maxPlayers      = maxPlayers,
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
		-- Beams of the barrier model, mapped to their original
		-- author-time Color so we can restore on unlock.
		barrierBeams    = barrierBeams,
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
		"%s registered %q. attachments=%s Ring=%s CountLabel=%s BgSlots=%d PartsSlots=%d Max=%d",
		LOG_TAG, roomModel:GetFullName(),
		tostring(attachCount),
		tostring(ring and "ok" or "<missing>"),
		tostring(countLabel and "ok" or "<missing>"),
		#bgSlots, #partsSlots, state.maxPlayers))

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
	if state.teleporting then
		-- Teleport is in flight — Roblox is processing TeleportAsync
		-- and the player hasn't physically been pulled out of the
		-- place yet. Don't restart a countdown; show "Loading" so
		-- they know the engine is working on it.
		state.countLabel.Text = "Loading"
	elseif state.locked and state.timerExpires then
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

-- Three layered overrides on the barrier-perimeter beams, each
-- restoring to the per-beam author snapshot when the trigger lifts:
--   * LightInfluence → 1 the moment any player is in queue (so the
--     beams pick up scene lighting and "wake up" visually).
--   * Color → ColorSequence(yellow) while the room is locked (full,
--     countdown ticking).
--   * Transparency → fully opaque (NumberSequence(0)) on lock so
--     the perimeter reads as a solid yellow bar instead of the
--     faded idle look.
-- Lock implies hasPlayers, so the Color/Transparency change happens
-- on top of the LightInfluence kick-up.
local YELLOW_SEQ      = ColorSequence.new(Color3.fromRGB(255, 255, 0))
local SOLID_TRANS_SEQ = NumberSequence.new(0)
local function updateBarrierBeams(state)
	local hasPlayers = next(state.queue) ~= nil
	local locked     = state.locked
	for beam, snap in pairs(state.barrierBeams) do
		if beam.Parent then
			beam.LightInfluence = hasPlayers and 1            or snap.lightInfluence
			beam.Color          = locked     and YELLOW_SEQ   or snap.color
			beam.Transparency   = locked     and SOLID_TRANS_SEQ or snap.transparency
		end
	end
end

-- Find the first slot in `slots` not yet assigned to a player.
local function firstFreeSlot(slots)
	for _, slot in slots do
		if slot.assignedTo == nil then
			return slot
		end
	end
	return nil
end

-- Find the slot currently assigned to a UserId.
local function findAssignedSlot(slots, userId)
	for _, slot in slots do
		if slot.assignedTo == userId then
			return slot
		end
	end
	return nil
end

local function addPlayer(state, player)
	if state.queue[player.UserId] then return end
	state.queue[player.UserId] = true

	-- Bg slot — usually carries the player's name.
	local bgSlot = firstFreeSlot(state.bgSlots)
	if bgSlot then
		bgSlot.assignedTo = player.UserId
		local nameLabel = bgSlot.entry:FindFirstChild("Name", true)
			or bgSlot.entry:FindFirstChildWhichIsA("TextLabel", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = player.Name
		end
	end

	-- ParticipantsGui slot — avatar headshot.
	local partsSlot = firstFreeSlot(state.partsSlots)
	if partsSlot then
		partsSlot.assignedTo = player.UserId
		local headshot = partsSlot.entry:FindFirstChild("Headshot", true)
		if headshot and headshot:IsA("ImageLabel") then
			headshot.Image = getHeadshot(player.UserId)
		end
	end

	updateCount(state)
	print(string.format("%s %s joined %q (count=%d/%d)",
		LOG_TAG, player.Name, state.room.Name, queueSize(state), state.maxPlayers))
end

local function removePlayer(state, userId)
	if not state.queue[userId] then return end
	state.queue[userId] = nil

	local bgSlot = findAssignedSlot(state.bgSlots, userId)
	if bgSlot then
		bgSlot.assignedTo = nil
		clearEntryVisuals(bgSlot.entry)
	end

	local partsSlot = findAssignedSlot(state.partsSlots, userId)
	if partsSlot then
		partsSlot.assignedTo = nil
		clearEntryVisuals(partsSlot.entry)
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

-- Teleport the given players into the room's destination place.
-- Each room can carry a `DestinationPlaceId` attribute on its
-- Folder/Model to send players to a custom destination; falls back
-- to DEFAULT_PLACE_ID (the same place LobbyServer's lobby/save flow
-- targets). Returns true on success so the caller can keep the
-- lock until the teleport actually fires off — that way a failed
-- TeleportAsync doesn't leave the room stuck "empty but countdown
-- ran" with players still standing on the pad.
local function teleportPlayers(state, players)
	if #players == 0 then return true end
	local placeId = state.room:GetAttribute("DestinationPlaceId") or DEFAULT_PLACE_ID

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions:SetTeleportData({
		fromRoom    = state.room.Name,
		playerCount = #players,
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, teleportOptions)
	end)
	if not ok then
		warn(string.format("%s teleport failed: %s", LOG_TAG, tostring(err)))
		return false
	end
	print(string.format("%s teleporting %d player(s) from %q to place %d",
		LOG_TAG, #players, state.room.Name, placeId))
	return true
end

-- Pin a player in place while the teleport is in flight so they
-- can't wander out of the zone during the 5-6 second gap between
-- TeleportAsync returning and Roblox physically pulling them into
-- the destination place.
local DEFAULT_WALK_SPEED = 16
local function freezePlayer(player)
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- Remember the original speed so unfreezing restores it.
	if hum:GetAttribute("StartRoomQueue_OriginalWalkSpeed") == nil then
		hum:SetAttribute("StartRoomQueue_OriginalWalkSpeed", hum.WalkSpeed)
		hum:SetAttribute("StartRoomQueue_OriginalJumpPower", hum.JumpPower)
	end
	hum.WalkSpeed = 0
	hum.JumpPower = 0
end

local function unfreezePlayer(player)
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local origWalk = hum:GetAttribute("StartRoomQueue_OriginalWalkSpeed")
	local origJump = hum:GetAttribute("StartRoomQueue_OriginalJumpPower")
	hum.WalkSpeed = (type(origWalk) == "number" and origWalk) or DEFAULT_WALK_SPEED
	hum.JumpPower = (type(origJump) == "number" and origJump) or 50
	hum:SetAttribute("StartRoomQueue_OriginalWalkSpeed", nil)
	hum:SetAttribute("StartRoomQueue_OriginalJumpPower", nil)
end

-- How long we'll wait in the teleporting phase before assuming the
-- teleport failed (Roblox raised, network glitch, etc.) and falling
-- back to a normal unlock so the players aren't stranded.
local TELEPORT_TIMEOUT_SECS = 30

-- Called every sweep. Drives both the countdown tick AND the
-- post-countdown "teleport pending" phase:
--   * Locked + countdown ticking → updates the visible counter.
--   * Locked + countdown reached zero → fires the teleport, enters
--     the teleporting phase. From here on the room ignores walk-
--     ins, holds queued players still, and displays "Loading"
--     until Roblox actually pulls them out of the place (their
--     queue entry vanishes the next sweep).
--   * Teleporting too long → safety unlock so a failed teleport
--     doesn't permanently strand the room.
-- Custom logic can override the teleport via _G.OnRoomFull(room,
-- players); when present, the built-in TeleportAsync is skipped.
local function tickLock(state)
	if state.teleporting then
		-- Keep the locked players frozen in place.
		for uid in pairs(state.queue) do
			local p = Players:GetPlayerByUserId(uid)
			if p then freezePlayer(p) end
		end
		updateCount(state)
		-- Safety: if Roblox hasn't pulled the players out within the
		-- timeout, abandon the teleport and unlock so the lobby
		-- stays usable.
		if os.clock() - (state.teleportingSince or 0) > TELEPORT_TIMEOUT_SECS then
			warn(string.format("%s %s teleport timed out after %ds — unlocking",
				LOG_TAG, state.room.Name, TELEPORT_TIMEOUT_SECS))
			for uid in pairs(state.queue) do
				local p = Players:GetPlayerByUserId(uid)
				if p then unfreezePlayer(p) end
			end
			state.teleporting     = false
			state.teleportingSince = nil
			state.locked          = false
			state.timerExpires    = nil
			updateCount(state)
		end
		return
	end

	if not state.locked or not state.timerExpires then return end
	if os.clock() < state.timerExpires then
		-- Just refresh the visible countdown.
		updateCount(state)
		return
	end

	-- Timer expired. Snapshot the players, fire the teleport, and
	-- enter the teleporting phase. We deliberately do NOT clear the
	-- queue or unlock here — sweep is told to keep them on hold so
	-- they don't get a second "10s countdown" cycle while Roblox is
	-- still processing the original TeleportAsync.
	local players = {}
	for uid in pairs(state.queue) do
		local p = Players:GetPlayerByUserId(uid)
		if p then table.insert(players, p) end
	end
	if typeof(_G.OnRoomFull) == "function" then
		pcall(_G.OnRoomFull, state.room, players)
	else
		teleportPlayers(state, players)
	end

	-- Freeze each player immediately so they can't step out of the
	-- zone during the teleport handshake.
	for _, p in players do
		freezePlayer(p)
	end

	state.teleporting     = true
	state.teleportingSince = os.clock()
	updateCount(state)  -- flips the label to "Loading"
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
						if state.locked or state.teleporting then
							-- Locked / teleporting room: existing
							-- queued players keep their slot, new
							-- walk-ins are ignored so the countdown
							-- can resolve / the teleport can finish
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
					-- Player no longer in the zone — could be a
					-- voluntary walk-out OR Roblox in the middle of
					-- yanking them out for the teleport. Either way
					-- they leave the queue.
					local p = Players:GetPlayerByUserId(uid)
					if p then unfreezePlayer(p) end
					removePlayer(state, uid)
				end
			end

			-- Lock cycle management — teleporting state takes
			-- precedence over the regular "queue fills up = lock"
			-- logic so we don't restart a countdown while Roblox is
			-- still processing the original teleport.
			if state.teleporting then
				if queueSize(state) == 0 then
					-- Last queued player physically left the place
					-- (teleport succeeded, or they timed out).
					-- Fully reset the room.
					state.teleporting     = false
					state.teleportingSince = nil
					state.locked          = false
					state.timerExpires    = nil
					updateCount(state)
					print(string.format("%s %s teleport complete — room reset",
						LOG_TAG, state.room.Name))
				end
			else
				-- Trip the lock the moment the queue fills up.
				-- A player leaving during the countdown cancels the
				-- lock and restores the normal "N / N" display.
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
			end

			tickLock(state)
			updateRingBeams(state)
			updateBarrierBeams(state)
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
