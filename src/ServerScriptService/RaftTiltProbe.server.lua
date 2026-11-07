-- RaftTiltProbe.server.lua (DIAGNOSTIC + GUARDS)
-- Watches the raft for the two failure shapes and reports enough context to name the culprit:
--   • TILT  — deck leaves world-up (yaw-proof). >THRESHOLD° → report; >RESCUE_TILT° → snap upright.
--   • BOUNCE — vertical oscillation in place (Y peak-to-peak > B_AMP with B_FLIPS direction changes
--     inside B_WINDOW seconds). On detection prints:
--       - an ASSEMBLY AUDIT: every part welded into the raft assembly that is NOT part of the Raft
--         model, flagging any with real mass ([HAS MASS]) — one non-massless welded part is the
--         classic raft-bounce cause;
--       - the max server Heartbeat dt since the last report (big value = a hitch, e.g. island clone);
--       - foreign parts inside the hull volume.

local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local THRESHOLD   = 4     -- degrees of deck tilt that trigger a report
local COOLDOWN    = 5     -- seconds between reports
local RESCUE_TILT = 40    -- beyond this the raft is capsizing → snap it upright NOW
local B_WINDOW    = 2     -- seconds of Y history for the bounce detector
local B_AMP       = 2.5   -- studs peak-to-peak that count as "jumping"
local B_FLIPS     = 4     -- vertical direction changes within the window

local raft = Workspace:WaitForChild("Raft")
while not raft.PrimaryPart do task.wait(0.5) end
local pp = raft.PrimaryPart

task.wait(5) -- let the raft settle on the water first
local restLocalUp = pp.CFrame:VectorToObjectSpace(Vector3.yAxis)

-- server hitch tracker (an island template cloning in stalls the heartbeat)
local maxDt = 0
RunService.Heartbeat:Connect(function(dt)
	if dt > maxDt then maxDt = dt end
end)

-- everything physically welded into the raft assembly that is NOT the Raft model itself
local function assemblyAudit()
	local foreign, foreignMass, totalMass = {}, 0, 0
	local ok, parts = pcall(function() return pp:GetConnectedParts(true) end)
	if not ok then return { "(audit failed)" }, 0, 0 end
	for _, p in ipairs(parts) do
		totalMass += p.Mass
		if not p:IsDescendantOf(raft) then
			foreignMass += p.Mass
			local top = p
			while top.Parent and top.Parent ~= Workspace do top = top.Parent end
			local key = ("%s/%s%s"):format(top.Name, p.Name, p.Massless and "" or (" [HAS MASS %.1f]"):format(p.Mass))
			if not table.find(foreign, key) then table.insert(foreign, key) end
		end
	end
	return foreign, foreignMass, totalMass
end

-- foreign parts inside the hull volume (collision suspects)
local function hullDump()
	local cf, size = raft:GetBoundingBox()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { raft }
	params.MaxParts = 24
	local parts = Workspace:GetPartBoundsInBox(cf, size + Vector3.new(4, 8, 4), params)
	local names = {}
	for _, p in ipairs(parts) do
		local top = p
		while top.Parent and top.Parent ~= Workspace do top = top.Parent end
		local key = top.Name .. "/" .. p.Name .. (p.Anchored and " [ANCHORED]" or "")
		if not table.find(names, key) then table.insert(names, key) end
	end
	return #names > 0 and table.concat(names, ", ") or "(none)"
end

local hist = {} -- { {t, y}, ... } sliding window for the bounce detector
local lastReport = 0

while true do
	task.wait(0.1)
	if not (raft.Parent and pp.Parent) then break end

	-- ── tilt ──
	local worldUp = pp.CFrame:VectorToWorldSpace(restLocalUp)
	local tilt = math.deg(math.acos(math.clamp(worldUp.Y, -1, 1)))
	if tilt > RESCUE_TILT then
		local rest = pp:GetAttribute("RestCFrame")
		if typeof(rest) == "CFrame" then
			pp.AssemblyAngularVelocity = Vector3.zero
			local v = pp.AssemblyLinearVelocity
			pp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
			pp.CFrame = CFrame.new(pp.Position) * rest.Rotation
			warn(("[RaftTiltProbe] RESCUE: raft was capsizing (%.1f°) — snapped upright"):format(tilt))
		end
	end
	if tilt > THRESHOLD and os.clock() - lastReport > COOLDOWN then
		lastReport = os.clock()
		local foreign, fMass, total = assemblyAudit()
		warn(("[RaftTiltProbe] deck tilted %.1f° | maxDt=%.3f | assemblyMass=%.0f foreignWeldedMass=%.0f | welded-on: %s | hull: %s")
			:format(tilt, maxDt, total, fMass, table.concat(foreign, ", "), hullDump()))
		maxDt = 0
	end

	-- ── bounce (vertical oscillation in place) ──
	table.insert(hist, { os.clock(), pp.Position.Y })
	while hist[1] and os.clock() - hist[1][1] > B_WINDOW do table.remove(hist, 1) end
	if #hist >= 10 then
		local minY, maxY = math.huge, -math.huge
		local flips, lastSign = 0, 0
		for i = 1, #hist do
			local y = hist[i][2]
			if y < minY then minY = y end
			if y > maxY then maxY = y end
			if i > 1 then
				local dy = y - hist[i - 1][2]
				if math.abs(dy) > 0.05 then
					local s = (dy > 0) and 1 or -1
					if lastSign ~= 0 and s ~= lastSign then flips += 1 end
					lastSign = s
				end
			end
		end
		if (maxY - minY) > B_AMP and flips >= B_FLIPS and os.clock() - lastReport > COOLDOWN then
			lastReport = os.clock()
			local foreign, fMass, total = assemblyAudit()
			warn(("[RaftTiltProbe] BOUNCE: Y swing %.1f studs, %d flips/%.0fs | maxDt=%.3f | assemblyMass=%.0f foreignWeldedMass=%.0f | welded-on: %s | hull: %s")
				:format(maxY - minY, flips, B_WINDOW, maxDt, total, fMass,
					#foreign > 0 and table.concat(foreign, ", ") or "(nothing)", hullDump()))
			maxDt = 0
		end
	end
end
