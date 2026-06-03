-- PirateSpawner.server.lua
-- Spawns a pirate raft that approaches the player's raft and drops
-- pirates off to attack, without docking / welding to the raft.
--
-- Behaviour:
--   1. Approach: pirate raft chases the player raft with an
--      AlignPosition that outpaces the player's current speed, so it
--      always catches up.
--   2. Boarding: once the pirate raft is within BOARD_DISTANCE of the
--      player raft, every pirate is teleported onto a random floor
--      tile on the player's raft (not welded — free to walk / fight).
--   3. Shadow: the pirate raft keeps AlignPosition-ing alongside the
--      player raft (offset to the side) instead of docking, so it
--      doesn't add phantom tiles / collisions to the player's raft.
--   4. Cleanup: when every pirate is dead (or after the self-destruct
--      timer) the pirate raft sinks and despawns.
--
-- Anti-drown: a background watchdog teleports any live pirate that
-- falls into the water or drifts off the raft back to a tile on the
-- player raft, and keeps Humanoid.JumpPower at 0 so they don't try
-- to jump off the edge.

local rs                = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local PIRATE_COUNT      = 2
local APPROACH_MARGIN   = 14   -- studs/s on top of player raft's speed
local MIN_APPROACH_VEL  = 22   -- never slower than this, even if raft is still
local APPROACH_FORCE    = 60000

-- How far to the side of the player raft the pirate raft holds once
-- they've collided. Small enough to stay in contact so pirates can
-- walk across, large enough that the pirate raft doesn't drift into
-- the player's build grid.
local SHADOW_OFFSET     = 18

-- Almost-touching threshold. Both triggers (Touched + this distance
-- fallback) fire only when the rafts are practically edge-to-edge,
-- so the teleport is a short hop to the nearest tile, not a long
-- reach across open water.
local BOARD_FALLBACK_DISTANCE = 12
local PIRATE_JUMP_POWER = 50   -- enough to hop the gap between the two rafts
local PIRATE_JUMP_HEIGHT = 7
local WATER_DROP_MARGIN = 5    -- below raft Y by this much = considered fallen
local RAFT_STAY_RADIUS  = 80   -- too far from either raft → snap back

local SELF_DESTRUCT_TIME = 180
local SINK_DURATION      = 4
local SPAWN_INTERVAL     = 180
local FIRST_SPAWN_DELAY  = 10

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

-- Wait for player raft.
local boat = getBoat()
while not boat do
	task.wait(1)
	boat = getBoat()
end
while not boat.PrimaryPart do task.wait(0.1) end

-- Return the world position on top of the player raft floor tile
-- nearest to `fromPos`. Used as the teleport target once the pirate
-- raft is almost touching the player raft — every pirate drops onto
-- the closest piece of floor to where they currently stand, so they
-- never land on the player (or behind walls on the far side of the
-- raft).
local function nearestRaftDropPoint(raft, fromPos)
	if not raft then return nil end
	local best, bestDist = nil, math.huge
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part"
			or child:GetAttribute("BuildType") == "raft"
			or child == raft.PrimaryPart then
			local pos
			if child:IsA("Model") then
				pos = child:GetPivot().Position
			elseif child:IsA("BasePart") then
				pos = child.Position
			end
			if pos then
				local d = (pos - fromPos).Magnitude
				if d < bestDist then
					bestDist = d
					best = pos
				end
			end
		end
	end
	if not best and raft.PrimaryPart then
		best = raft.PrimaryPart.Position
	end
	if best then
		return best + Vector3.new(0, 4, 0)
	end
	return nil
end

-- True when the pirate has dropped into the water: Y below the player
-- raft plane. Drift is only considered "too far" if it's past both
-- rafts at once, since pirates are allowed to be on either.
local function hasFallenInWater(pirate, playerRaft, pirateRaftRoot)
	local hrp = pirate:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local refY
	if playerRaft and playerRaft.PrimaryPart then
		refY = playerRaft.PrimaryPart.Position.Y
	elseif pirateRaftRoot then
		refY = pirateRaftRoot.Position.Y
	else
		return false
	end
	if hrp.Position.Y < refY - WATER_DROP_MARGIN then return true end

	-- Allow being near either raft; only wander-teleport if far from both.
	local function planarDist(rootPart)
		if not rootPart then return math.huge end
		local dx = hrp.Position.X - rootPart.Position.X
		local dz = hrp.Position.Z - rootPart.Position.Z
		return math.sqrt(dx * dx + dz * dz)
	end
	local dPlayer = planarDist(playerRaft and playerRaft.PrimaryPart)
	local dPirate = planarDist(pirateRaftRoot)
	if math.min(dPlayer, dPirate) > RAFT_STAY_RADIUS then return true end
	return false
end

-- Strip every weld / constraint connecting this pirate to anything
-- outside its own model, force-unanchor its parts, and wake the
-- Humanoid up. Called during boarding so the transit weld (plus any
-- template-level welds pointing at the pirate raft) can't pull the
-- pirate back once it's been teleported.
local function releasePirate(pirate)
	for _, d in pirate:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor") then
			local p0, p1 = d.Part0, d.Part1
			local inside0 = p0 and p0:IsDescendantOf(pirate)
			local inside1 = p1 and p1:IsDescendantOf(pirate)
			-- Keep internal joints (character Motor6Ds etc.) intact;
			-- only kill bonds that reach outside the pirate model.
			if (p0 and not inside0) or (p1 and not inside1) then
				d:Destroy()
			end
		elseif d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	local hum = pirate:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
	end
	local hrp = pirate:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity  = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Kept for the drown-recovery path only: when a pirate falls in the
-- water we teleport them back onto their own raft so they can try to
-- board again instead of drifting forever.
local function rescueToPirateRaft(pirate, pirateRaftRoot)
	releasePirate(pirate)
	if not pirateRaftRoot then return end
	local hrp = pirate:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = CFrame.new(pirateRaftRoot.Position + Vector3.new(0, 5, 0))
	hrp.AssemblyLinearVelocity  = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Pirate raft spawn + approach + shadow logic.
local function spawnPirateRaft()
	boat = getBoat()
	if not boat or not boat.PrimaryPart then return end

	local root = boat.PrimaryPart
	local waterY = root.Position.Y

	-- Drop the pirate raft some distance away in a random direction.
	local angle = math.random() * math.pi * 2
	local dist  = math.random(120, 220)
	local spawnPos = Vector3.new(
		root.Position.X + math.cos(angle) * dist,
		waterY,
		root.Position.Z + math.sin(angle) * dist
	)

	local floorTemplate = rs:FindFirstChild("Raft_part")
	if not floorTemplate then
		warn("[PirateSpawner] Raft_part template missing")
		return
	end

	local floor = floorTemplate:Clone()
	floor.Name = "PirateRaftFloor"
	if floor:IsA("Model") and not floor.PrimaryPart then
		local p = floor:FindFirstChildWhichIsA("BasePart", true)
		if p then floor.PrimaryPart = p end
	end

	local rootPart = floor:IsA("Model") and floor.PrimaryPart or floor
	if not rootPart then
		floor:Destroy()
		return
	end

	local flatCF = CFrame.new(spawnPos) * root.CFrame.Rotation
	if floor:IsA("Model") then floor:PivotTo(flatCF) else floor.CFrame = flatCF end
	floor.Parent = workspace

	for _, part in floor:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part:SetNetworkOwner(nil)
		end
	end
	if floor:IsA("BasePart") then
		floor.Anchored = false
		floor:SetNetworkOwner(nil)
	end

	-- Spawn pirates welded to the pirate raft for transit. They stay
	-- welded only until boarding (no AI, no pathing).
	local pirates = {}
	local transitWelds = {}
	local pirateTemplate = rs:FindFirstChild("Pirate lvl1")
	if not pirateTemplate then
		warn("[PirateSpawner] Pirate lvl1 template missing")
		floor:Destroy()
		return
	end

	for i = 1, PIRATE_COUNT do
		local pirate = pirateTemplate:Clone()
		local offsetX = (i - 1) * 3 - 1.5
		pirate:PivotTo(CFrame.new(spawnPos + Vector3.new(offsetX, 5, 0)))
		CollectionService:AddTag(pirate, "HostilePirate")
		-- NpcType drives recruitment / blood / merc filtering. The
		-- recruitment system rejects models without a known NpcType
		-- so a stray ragdoll never opens the wrong recruit panel.
		pirate:SetAttribute("NpcType", "Pirate lvl1")
		pirate.Parent = workspace

		local hrp = pirate:FindFirstChild("HumanoidRootPart")
		if hrp then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = hrp
			weld.Parent = rootPart
			table.insert(transitWelds, weld)
		end
		table.insert(pirates, pirate)
	end

	-- Approach / shadow driver. AlignPosition pulls the pirate raft
	-- toward a target recomputed every tick; AlignOrientation keeps it
	-- facing the player raft.
	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0  = attachment
	alignPos.Mode         = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce     = APPROACH_FORCE
	alignPos.Responsiveness = 10
	alignPos.Parent       = rootPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Attachment0    = attachment
	alignOri.Mode           = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque      = 20000
	alignOri.Responsiveness = 5
	alignOri.Parent         = rootPart

	local boarded = false
	local running = true

	-- Release every pirate from the transit weld and teleport them
	-- onto the nearest floor tile of the player raft. With the
	-- boarding trigger tightened to near-contact, this is a short
	-- sideways hop rather than a warp through the whole raft —
	-- pirates still land on a legitimate floor cell, so walls around
	-- the raft interior are respected.
	local function triggerBoarding()
		if boarded then return end
		boarded = true
		for _, w in transitWelds do
			if w and w.Parent then w:Destroy() end
		end
		local b = getBoat()
		for _, pirate in pirates do
			if pirate and pirate.Parent then
				releasePirate(pirate)
				local hum = pirate:FindFirstChildWhichIsA("Humanoid")
				if hum then
					-- JumpPower keeps them capable of small hops if
					-- they walk over a gap afterwards.
					hum.JumpPower  = PIRATE_JUMP_POWER
					hum.JumpHeight = PIRATE_JUMP_HEIGHT
					hum.AutoJumpEnabled = true
				end
				local configs = pirate:FindFirstChild("Configurations")
				if configs then
					local canRespawn = configs:FindFirstChild("CanRespawn")
					if canRespawn then canRespawn.Value = false end
				end
				local hrp = pirate:FindFirstChild("HumanoidRootPart")
				if b and hrp then
					local target = nearestRaftDropPoint(b, hrp.Position)
					if target then
						hrp.CFrame = CFrame.new(target)
						hrp.AssemblyLinearVelocity  = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
					end
				end
			end
		end
	end

	-- Touched trigger: any pirate-raft part hitting any player-raft
	-- part counts as "boarded". This is the authoritative signal —
	-- the player might have built walls or not, so we don't guess,
	-- we just wait for physical contact.
	local function hookTouched(part)
		if not part:IsA("BasePart") then return end
		part.Touched:Connect(function(other)
			if boarded then return end
			local b = getBoat()
			if b and other:IsDescendantOf(b) then
				triggerBoarding()
			end
		end)
	end
	if floor:IsA("BasePart") then
		hookTouched(floor)
	else
		for _, d in floor:GetDescendants() do
			hookTouched(d)
		end
	end

	task.spawn(function()
		while running and floor.Parent do
			local b = getBoat()
			if not b or not b.PrimaryPart then break end
			local target = b.PrimaryPart.Position

			-- Keep a small lateral offset so the pirate raft ends up
			-- edge-to-edge with the player raft instead of grinding
			-- into the middle of it. The rafts collide → boarding
			-- trigger → pirates walk or hop across.
			local right = b.PrimaryPart.CFrame.RightVector
			local planarRight = Vector3.new(right.X, 0, right.Z)
			if planarRight.Magnitude > 0.01 then
				target = target + planarRight.Unit * SHADOW_OFFSET
			end
			alignPos.Position = target

			-- Out-pace the player raft: cap chase speed at the player's
			-- current planar speed plus APPROACH_MARGIN, with a floor
			-- so we still move when the raft is still.
			local v = b.PrimaryPart.AssemblyLinearVelocity
			local planar = math.sqrt(v.X * v.X + v.Z * v.Z)
			alignPos.MaxVelocity = math.max(MIN_APPROACH_VEL, planar + APPROACH_MARGIN)

			-- Face the player raft.
			local flat = b.PrimaryPart.Position - rootPart.Position
			flat = Vector3.new(flat.X, 0, flat.Z)
			if flat.Magnitude > 1 then
				local _, yaw = CFrame.lookAt(Vector3.zero, flat.Unit):ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			-- Safety net for edge cases (tiny / stacked tiles, Touched
			-- filter misses): if the pirate raft is nose-to-nose with
			-- the player raft but Touched hasn't fired, still trigger.
			if not boarded then
				local dx = rootPart.Position.X - b.PrimaryPart.Position.X
				local dz = rootPart.Position.Z - b.PrimaryPart.Position.Z
				if math.sqrt(dx * dx + dz * dz) < BOARD_FALLBACK_DISTANCE then
					triggerBoarding()
				end
			end

			task.wait(0.2)
		end
	end)

	-- Watchdog: if a pirate falls in the water, put them back on
	-- whichever raft makes sense — boarded pirates go to the nearest
	-- player-raft tile so they keep fighting, pre-boarding pirates
	-- go back to their own raft.
	task.spawn(function()
		while running and floor.Parent do
			task.wait(0.5)
			local b = getBoat()
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0
						and hasFallenInWater(pirate, b, rootPart)
					then
						if boarded and b then
							releasePirate(pirate)
							local hrp = pirate:FindFirstChild("HumanoidRootPart")
							local target = hrp and nearestRaftDropPoint(b, hrp.Position)
							if hrp and target then
								hrp.CFrame = CFrame.new(target)
								hrp.AssemblyLinearVelocity  = Vector3.zero
								hrp.AssemblyAngularVelocity = Vector3.zero
							end
						else
							rescueToPirateRaft(pirate, rootPart)
						end
					end
				end
			end
		end
	end)

	-- Cleanup: sink when all pirates are dead, and self-destruct after
	-- the timer regardless so we don't leave debris behind.
	task.spawn(function()
		local deadline = tick() + SELF_DESTRUCT_TIME
		while running and floor.Parent do
			task.wait(1)
			local aliveCount = 0
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0 then aliveCount = aliveCount + 1 end
				end
			end
			if aliveCount == 0 then break end
			if tick() > deadline then
				for _, pirate in pirates do
					if pirate and pirate.Parent then
						local hum = pirate:FindFirstChildWhichIsA("Humanoid")
						if hum and hum.Health > 0 then hum.Health = 0 end
					end
				end
				break
			end
		end

		running = false

		if alignPos.Parent then alignPos:Destroy() end
		if alignOri.Parent then alignOri:Destroy() end
		if attachment.Parent then attachment:Destroy() end

		if not floor.Parent then return end

		-- Gather pirate raft parts, freeze and sink.
		local parts = {}
		if floor:IsA("Model") then
			for _, d in floor:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					table.insert(parts, d)
				end
			end
		elseif floor:IsA("BasePart") then
			floor.Anchored = true
			floor.CanCollide = false
			table.insert(parts, floor)
		end

		local steps = math.floor(SINK_DURATION / 0.05)
		local sinkPerStep = -15 / steps
		for step = 1, steps do
			if not floor.Parent then break end
			local alpha = step / steps
			for _, p in parts do
				if p and p.Parent then
					p.CFrame = p.CFrame + Vector3.new(0, sinkPerStep, 0)
					p.Transparency = alpha
				end
			end
			task.wait(0.05)
		end

		if floor.Parent then floor:Destroy() end

		task.delay(180, function()
			for _, pirate in pirates do
				if pirate and pirate.Parent and not pirate:GetAttribute("Claimed") then
					pirate:Destroy()
				end
			end
		end)
	end)
end

task.wait(FIRST_SPAWN_DELAY)
spawnPirateRaft()

while true do
	task.wait(SPAWN_INTERVAL)
	spawnPirateRaft()
end
