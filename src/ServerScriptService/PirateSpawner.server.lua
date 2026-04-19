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

local BOARD_DISTANCE    = 45   -- studs from pirate raft to player raft
local SHADOW_OFFSET     = 35   -- keep pirate raft this far to the side
local WATER_DROP_MARGIN = 5    -- below raft Y by this much = considered fallen
local RAFT_STAY_RADIUS  = 60   -- too far from raft → snap back

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

-- Pick a random floor tile on the player raft, return a world CFrame
-- above it so a pirate teleported there lands cleanly on top.
local function pickRaftDropPoint(raft)
	local tiles = {}
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
			if pos then table.insert(tiles, pos) end
		end
	end
	if #tiles == 0 and raft.PrimaryPart then
		return raft.PrimaryPart.Position + Vector3.new(0, 5, 0)
	end
	return tiles[math.random(1, #tiles)] + Vector3.new(0, 4, 0)
end

-- True when the pirate looks like it's no longer on the raft — either
-- it dropped below the raft plane (fell off) or drifted out of bounds.
local function isOffRaft(pirate, raft)
	if not raft or not raft.PrimaryPart then return false end
	local hrp = pirate:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local raftY = raft.PrimaryPart.Position.Y
	if hrp.Position.Y < raftY - WATER_DROP_MARGIN then return true end
	local dx = hrp.Position.X - raft.PrimaryPart.Position.X
	local dz = hrp.Position.Z - raft.PrimaryPart.Position.Z
	if (dx * dx + dz * dz) > (RAFT_STAY_RADIUS * RAFT_STAY_RADIUS) then
		return true
	end
	return false
end

local function boardPirate(pirate, raft)
	local hrp = pirate:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local landing = pickRaftDropPoint(raft)
	pirate:PivotTo(CFrame.new(landing))
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

	task.spawn(function()
		while running and floor.Parent do
			local b = getBoat()
			if not b or not b.PrimaryPart then break end
			local target = b.PrimaryPart.Position

			-- Before boarding we steer straight at the player raft.
			-- After boarding we hold position to the side so the pirate
			-- raft never crashes into / overlaps the player's tiles.
			if boarded then
				local look = b.PrimaryPart.CFrame.RightVector
				target = target + Vector3.new(look.X, 0, look.Z).Unit * SHADOW_OFFSET
			end
			alignPos.Position = target

			-- Out-pace the player raft: cap chase speed at the player's
			-- current planar speed plus APPROACH_MARGIN, with a floor
			-- so we still move when the raft is still.
			local v = b.PrimaryPart.AssemblyLinearVelocity
			local planar = math.sqrt(v.X * v.X + v.Z * v.Z)
			alignPos.MaxVelocity = math.max(MIN_APPROACH_VEL, planar + APPROACH_MARGIN)

			-- Face the player raft.
			local flat = target - rootPart.Position
			flat = Vector3.new(flat.X, 0, flat.Z)
			if flat.Magnitude > 1 then
				local _, yaw = CFrame.lookAt(Vector3.zero, flat.Unit):ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			-- Boarding trigger: within range → drop pirates onto the
			-- player raft and switch to shadow mode.
			if not boarded then
				local dx = rootPart.Position.X - b.PrimaryPart.Position.X
				local dz = rootPart.Position.Z - b.PrimaryPart.Position.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < BOARD_DISTANCE then
					boarded = true
					for _, w in transitWelds do
						if w and w.Parent then w:Destroy() end
					end
					for _, pirate in pirates do
						if pirate and pirate.Parent then
							boardPirate(pirate, b)
							-- Don't jump off the edge chasing a player.
							local hum = pirate:FindFirstChildWhichIsA("Humanoid")
							if hum then
								hum.JumpPower  = 0
								hum.JumpHeight = 0
							end
							local configs = pirate:FindFirstChild("Configurations")
							if configs then
								local canRespawn = configs:FindFirstChild("CanRespawn")
								if canRespawn then canRespawn.Value = false end
							end
						end
					end
				end
			end

			task.wait(0.2)
		end
	end)

	-- Watchdog: once pirates have boarded, teleport any that fall into
	-- the water or wander too far back to a raft tile.
	task.spawn(function()
		while running and floor.Parent do
			task.wait(0.5)
			if not boarded then continue end
			local b = getBoat()
			if not b or not b.PrimaryPart then continue end
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0 and isOffRaft(pirate, b) then
						boardPirate(pirate, b)
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
