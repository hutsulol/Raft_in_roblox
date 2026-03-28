local rs = game:GetService("ReplicatedStorage")

local SPAWN_INTERVAL = 5
local PIRATE_COUNT = 2
local APPROACH_SPEED = 60
local SINK_DURATION = 4

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

-- Wait for raft to exist
local boat = getBoat()
while not boat do
	task.wait(1)
	boat = getBoat()
end
while not boat.PrimaryPart do
	task.wait(0.1)
end

local function spawnPirateRaft()
	boat = getBoat()
	if not boat or not boat.PrimaryPart then return end

	local root = boat.PrimaryPart
	local waterY = root.Position.Y

	-- Spawn nearby, like resources but closer
	local angle = math.random() * math.pi * 2
	local dist = math.random(100, 200)
	local spawnPos = Vector3.new(
		root.Position.X + math.cos(angle) * dist,
		waterY,
		root.Position.Z + math.sin(angle) * dist
	)

	-- Clone Raft_part for the pirate raft floor
	local floorTemplate = rs:FindFirstChild("Raft_part")
	if not floorTemplate then
		warn("PirateSpawner: Raft_part not found in ReplicatedStorage")
		return
	end

	local floor = floorTemplate:Clone()
	floor.Name = "PirateRaftFloor"

	-- Ensure it has a PrimaryPart
	if floor:IsA("Model") and not floor.PrimaryPart then
		local first = floor:FindFirstChildWhichIsA("BasePart", true)
		if first then
			floor.PrimaryPart = first
		end
	end

	-- Position it
	if floor:IsA("Model") then
		floor:PivotTo(CFrame.new(spawnPos))
	elseif floor:IsA("BasePart") then
		floor.CFrame = CFrame.new(spawnPos)
	end

	floor.Parent = workspace

	-- Unanchor and set network owner
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

	-- Get the root part for physics
	local rootPart
	if floor:IsA("Model") then
		rootPart = floor.PrimaryPart
	else
		rootPart = floor
	end

	if not rootPart then
		warn("PirateSpawner: no root part for pirate raft")
		floor:Destroy()
		return
	end

	-- Spawn pirates on top
	local pirates = {}
	local pirateTemplate = rs:FindFirstChild("Pirate lvl1")
	if pirateTemplate then
		for i = 1, PIRATE_COUNT do
			local pirate = pirateTemplate:Clone()
			local offsetX = (i - 1) * 3 - 1.5
			local piratePos = spawnPos + Vector3.new(offsetX, 5, 0)

			if pirate:IsA("Model") then
				pirate:PivotTo(CFrame.new(piratePos))
			end
			pirate.Parent = workspace
			table.insert(pirates, pirate)
		end
	else
		warn("PirateSpawner: Pirate lvl1 not found in ReplicatedStorage")
	end

	-- Move toward player raft using AlignPosition
	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = attachment
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce = 50000
	alignPos.MaxVelocity = APPROACH_SPEED
	alignPos.Responsiveness = 10
	alignPos.Parent = rootPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Attachment0 = attachment
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque = 10000
	alignOri.Responsiveness = 10
	alignOri.Parent = rootPart

	-- Movement loop
	task.spawn(function()
		while floor and floor.Parent and rootPart and rootPart.Parent do
			local b = getBoat()
			if not b or not b.PrimaryPart then break end

			local target = b.PrimaryPart.Position
			alignPos.Position = Vector3.new(target.X, rootPart.Position.Y, target.Z)

			local dir = Vector3.new(target.X - rootPart.Position.X, 0, target.Z - rootPart.Position.Z)
			if dir.Magnitude > 1 then
				local _, yaw, _ = CFrame.lookAt(Vector3.zero, dir.Unit):ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			if dir.Magnitude < 15 then
				alignPos.MaxVelocity = 0
			else
				alignPos.MaxVelocity = APPROACH_SPEED
			end

			task.wait(0.5)
		end
	end)

	-- Monitor: when all pirates dead, sink the raft
	task.spawn(function()
		while floor and floor.Parent do
			task.wait(1)

			local allDead = true
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0 then
						allDead = false
						break
					end
				end
			end

			if allDead then
				-- Stop movement
				if attachment then attachment:Destroy() end
				if alignPos then alignPos:Destroy() end
				if alignOri then alignOri:Destroy() end

				-- Gather all parts
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

				-- Sink and fade
				local steps = math.floor(SINK_DURATION / 0.05)
				local sinkPerStep = -15 / steps
				for step = 1, steps do
					if not floor or not floor.Parent then break end
					local alpha = step / steps
					for _, p in parts do
						if p and p.Parent then
							p.CFrame = p.CFrame + Vector3.new(0, sinkPerStep, 0)
							p.Transparency = alpha
						end
					end
					task.wait(0.05)
				end

				if floor and floor.Parent then
					floor:Destroy()
				end
				for _, pirate in pirates do
					if pirate and pirate.Parent then
						pirate:Destroy()
					end
				end
				return
			end
		end
	end)
end

-- Immediate first spawn
task.wait(3)
spawnPirateRaft()

-- Spawn loop
while true do
	task.wait(SPAWN_INTERVAL)
	spawnPirateRaft()
end
