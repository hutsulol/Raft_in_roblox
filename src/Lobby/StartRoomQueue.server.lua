-- StartRoomQueue.server.lua
-- Per-room queue tracker. Drop a copy of this Script inside each
-- StartRoom-style Model in Studio; each copy manages ITS OWN parent
-- model independently. No central registry, no name conventions —
-- the script reads script.Parent as the room.
--
-- Expected layout (inside script.Parent):
--   Ring (BasePart)                       — inner play floor
--   RingBeams.Barrier_Players (Model)     — corner Attachments forming
--                                            the queue perimeter beams
--   InfoPart > Bg.Container.Entry         — text-list entry template
--   InfoPart > ParticipantsGui.Container.Entry — avatar tile template
--   CharacterCount (SurfaceGui w/ TextLabel)   — "N / MAX" readout
--
-- A player auto-joins the queue the moment their HumanoidRootPart
-- enters either the Ring's bbox or the Barrier_Players polygon.
-- Stepping out (or disconnecting) auto-leaves. No prompts.
--
-- Capacity ("MAX" in the count label) reads from a MaxPlayers
-- attribute on the room model, else from DEFAULT_MAX_BY_NAME below,
-- else from FALLBACK_MAX.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local room = script.Parent
if not room or not room:IsA("Model") then
	warn(string.format(
		"[StartRoomQueue] script.Parent is %s, expected a Model — script disabled",
		tostring(room and room.ClassName or "<nil>")
	))
	return
end

-- ─── Config ───────────────────────────────────────────────────────

local DEFAULT_MAX_BY_NAME = {
	StartRoom    = 1,
	DuelPad      = 2,
	DuelRing_2v2 = 4,
	DuelRing_3v3 = 6,
	DuelRing_4v4 = 8,
}
local FALLBACK_MAX   = 4
local POLL_INTERVAL  = 0.25  -- seconds between zone-occupancy sweeps
local VERTICAL_SLACK = 12    -- studs of Y room above/below the zone

local LOG_TAG = "[" .. room.Name .. " Queue]"

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

-- Barrier_Players is drawn as Beams between corner Attachments
-- (C1..C4 / P1..P4). Build an axis-aligned XZ rectangle that wraps
-- every attachment, plus a Y slack so jumping doesn't drop the
-- player out of the queue.
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

-- ─── UI wiring ───────────────────────────────────────────────────

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

local infoPart       = room:FindFirstChild("InfoPart", true)
local bg             = infoPart and infoPart:FindFirstChild("Bg", true)
local bgContainer    = bg and bg:FindFirstChild("Container", true)
local bgTemplate     = bgContainer and bgContainer:FindFirstChild("Entry")
local partsGui       = infoPart and infoPart:FindFirstChild("ParticipantsGui", true)
local partsContainer = partsGui and partsGui:FindFirstChild("Container", true)
local partsTemplate  = partsContainer and partsContainer:FindFirstChild("Entry")
local countGui       = room:FindFirstChild("CharacterCount", true)
local countLabel     = countGui and countGui:FindFirstChildWhichIsA("TextLabel", true)

local maxPlayers = room:GetAttribute("MaxPlayers")
if type(maxPlayers) ~= "number" then
	maxPlayers = DEFAULT_MAX_BY_NAME[room.Name] or FALLBACK_MAX
end

hideTemplate(bgTemplate)
hideTemplate(partsTemplate)
clearStaleEntries(bgContainer,    bgTemplate    and bgTemplate.Name)
clearStaleEntries(partsContainer, partsTemplate and partsTemplate.Name)

local barrier = room:FindFirstChild("Barrier_Players", true)
local ring    = room:FindFirstChild("Ring", true)

local barrierCF, barrierSize, attachCount
if barrier then
	barrierCF, barrierSize, attachCount = computeBarrierZone(barrier)
end
local ringCF, ringSize = partAsZone(ring)

print(string.format(
	"%s online. Barrier attachments=%s. Ring=%s. CountLabel=%s. PartsTemplate=%s. BgTemplate=%s. Max=%d",
	LOG_TAG,
	tostring(attachCount),
	tostring(ring and ring:GetFullName() or "<missing>"),
	tostring(countLabel and countLabel:GetFullName() or "<missing>"),
	tostring(partsTemplate and partsTemplate:GetFullName() or "<missing>"),
	tostring(bgTemplate and bgTemplate:GetFullName() or "<missing>"),
	maxPlayers
))

-- ─── Queue state + UI updates ────────────────────────────────────

local queue = {}  -- [userId] = true

local function queueSize()
	local n = 0
	for _ in pairs(queue) do n = n + 1 end
	return n
end

local function updateCount()
	if not countLabel then return end
	countLabel.Text = string.format("%d / %d", queueSize(), maxPlayers)
end

local function addPlayer(player)
	if queue[player.UserId] then return end
	queue[player.UserId] = true
	local uid = tostring(player.UserId)

	if bgTemplate and bgContainer then
		local entry = bgTemplate:Clone()
		entry.Name = uid
		pcall(function() entry.Visible = true end)
		local nameLabel = entry:FindFirstChild("Name", true)
			or entry:FindFirstChildWhichIsA("TextLabel", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = player.Name
		end
		entry.Parent = bgContainer
	end

	if partsTemplate and partsContainer then
		local entry = partsTemplate:Clone()
		entry.Name = uid
		pcall(function() entry.Visible = true end)
		local headshot = entry:FindFirstChild("Headshot", true)
		if headshot and headshot:IsA("ImageLabel") then
			headshot.Image = getHeadshot(player.UserId)
		end
		entry.Parent = partsContainer
	end

	updateCount()
	print(string.format("%s %s joined (count=%d/%d)",
		LOG_TAG, player.Name, queueSize(), maxPlayers))
end

local function removePlayer(userId)
	if not queue[userId] then return end
	queue[userId] = nil
	local uid = tostring(userId)
	if bgContainer then
		local e = bgContainer:FindFirstChild(uid)
		if e then e:Destroy() end
	end
	if partsContainer then
		local e = partsContainer:FindFirstChild(uid)
		if e then e:Destroy() end
	end
	updateCount()
end

-- ─── Sweep loop ──────────────────────────────────────────────────

local function sweep()
	-- Recompute the zone geometry each pass so a lobby platform that
	-- drifts (raft, moving spawn pad) doesn't strand the zone in
	-- world space.
	if barrier and barrier.Parent then
		barrierCF, barrierSize = computeBarrierZone(barrier)
	end
	if ring and ring.Parent then
		ringCF, ringSize = partAsZone(ring)
	end

	local seen = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = hrp.Position
			local inside = (barrierCF and pointInZone(pos, barrierCF, barrierSize))
				or (ringCF and pointInZone(pos, ringCF, ringSize))
			if inside then
				seen[player.UserId] = true
				if not queue[player.UserId] then
					addPlayer(player)
				end
			end
		end
	end
	for uid in pairs(queue) do
		if not seen[uid] then
			removePlayer(uid)
		end
	end
end

local accum = 0
local conn = RunService.Heartbeat:Connect(function(dt)
	accum = accum + dt
	if accum >= POLL_INTERVAL then
		accum = 0
		sweep()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	removePlayer(player.UserId)
end)

-- Self-clean if the room is destroyed at runtime (lobby teardown,
-- Studio reload, …) so the heartbeat connection doesn't keep firing
-- against a stale model.
room.AncestryChanged:Connect(function()
	if not room:IsDescendantOf(game) then
		conn:Disconnect()
	end
end)
