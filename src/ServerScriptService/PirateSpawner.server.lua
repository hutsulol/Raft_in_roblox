local rs = game:GetService("ReplicatedStorage")

-- Measure grid size from Raft_part template
local raftPartTemplate = rs:WaitForChild("Raft_part")
local GRID_SIZE
if raftPartTemplate:IsA("Model") and raftPartTemplate.PrimaryPart then
	GRID_SIZE = raftPartTemplate.PrimaryPart.Size.X
elseif raftPartTemplate:IsA("BasePart") then
	GRID_SIZE = raftPartTemplate.Size.X
else
	GRID_SIZE = 6
end

local PIRATE_COUNT = 2
local CHASE_SPEED = 20
local SINK_DURATION = 4
local SELF_DESTRUCT_TIME = 120

local function getBoat()
	return workspace:FindFirstChild("Raft")
end

-- When PrimaryPart is not a Raft_part (e.g. a SpawnLocation), its orientation
-- differs from tile orientation. Returns a rotation correction so new tiles
-- match existing Raft_part orientation instead of PrimaryPart's.
local function getTileRotationCorrection(raft)
	local primary = raft.PrimaryPart
	if not primary then return CFrame.new() end
	for _, child in raft:GetChildren() do
		if child.Name == "Raft_part" and child ~= primary then
			local tileCF
			if child:IsA("Model") then
				tileCF = child:GetPivot()
			elseif child:IsA("BasePart") then
				tileCF = child.CFrame
			end
			if tileCF then
				return primary.CFrame:ToObjectSpace(tileCF).Rotation
			end
		end
	end
	return CFrame.new()
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

	-- Spawn nearby
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

	if floor:IsA("Model") and not floor.PrimaryPart then
		local first = floor:FindFirstChildWhichIsA("BasePart", true)
		if first then
			floor.PrimaryPart = first
		end
	end

	-- Match the player raft's Raft_part orientation so the pirate tile lies
	-- flat. The player raft's PrimaryPart may be a SpawnLocation with a
	-- different orientation than its Raft_parts; use the same rotation
	-- correction as BuildingSystem so the pirate tile matches existing tiles.
	local tileCorrection = getTileRotationCorrection(boat)
	local flatCF = CFrame.new(spawnPos) * (root.CFrame.Rotation * tileCorrection)

	if floor:IsA("Model") then
		floor:PivotTo(flatCF)
	elseif floor:IsA("BasePart") then
		floor.CFrame = flatCF
	end

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

	-- Spawn pirates welded to the pirate raft for transit
	local pirates = {}
	local transitWelds = {}
	local deadCount = 0
	local allDeadEvent = Instance.new("BindableEvent")
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

			-- Weld HumanoidRootPart to pirate raft so they move smoothly with it.
			-- The weld physically prevents movement, so we do NOT set WalkSpeed = 0.
			-- Setting WalkSpeed before the baked ZombieScript initializes causes
			-- the script to cache 0 as its base speed and never move again.
			local hrp = pirate:FindFirstChild("HumanoidRootPart")
			if hrp then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = hrp
				weld.Parent = rootPart
				table.insert(transitWelds, weld)
			end

			local hum = pirate:FindFirstChildWhichIsA("Humanoid")

			table.insert(pirates, pirate)

			if hum then
				hum.Died:Connect(function()
					pirate:SetAttribute("Downed", true)
					pirate:SetAttribute("RecruitChance", 100)
					deadCount = deadCount + 1
					if deadCount >= PIRATE_COUNT then
						allDeadEvent:Fire()
					end
				end)
			end
		end
	else
		warn("PirateSpawner: Pirate lvl1 not found in ReplicatedStorage")
	end

	-- Backup ragdoll polling: the baked ZombieScript / Ragdoller may knock
	-- out the pirate without setting Humanoid.Health to 0, so Humanoid.Died
	-- never fires. Poll every 0.5s and detect the ragdoll state through
	-- multiple indicators.
	task.spawn(function()
		while floor and floor.Parent do
			for _, pirate in pirates do
				if pirate and pirate.Parent and not pirate:GetAttribute("Downed") then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum then
						local downed = false
						-- Standard death
						if hum.Health <= 0 then downed = true end
						-- Humanoid state
						local state = hum:GetState()
						if state == Enum.HumanoidStateType.Dead
							or state == Enum.HumanoidStateType.Physics then
							downed = true
						end
						-- PlatformStand (common ragdoll method)
						if hum.PlatformStand then downed = true end
						-- Motor6D absence: a ragdolled R6 character has its
						-- Motor6Ds replaced with constraints
						if not downed then
							local hasMotor = false
							for _, desc in pirate:GetDescendants() do
								if desc:IsA("Motor6D") and desc.Name ~= "DoorHinge" then
									hasMotor = true
									break
								end
							end
							if not hasMotor then downed = true end
						end
						if downed then
							pirate:SetAttribute("Downed", true)
							pirate:SetAttribute("RecruitChance", 100)
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)

	-- Approach using AlignPosition
	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = attachment
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce = 50000
	alignPos.MaxVelocity = CHASE_SPEED
	alignPos.Responsiveness = 5
	alignPos.Parent = rootPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Attachment0 = attachment
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque = 10000
	alignOri.Responsiveness = 5
	alignOri.Parent = rootPart

	local docked = false

	-- Movement loop: approach then dock (weld) to player raft
	task.spawn(function()
		while floor and floor.Parent and rootPart and rootPart.Parent do
			local b = getBoat()
			if not b or not b.PrimaryPart then break end

			local target = b.PrimaryPart.Position
			alignPos.Position = target

			local dir = Vector3.new(target.X - rootPart.Position.X, 0, target.Z - rootPart.Position.Z)
			if dir.Magnitude > 1 then
				local _, yaw, _ = CFrame.lookAt(Vector3.zero, dir.Unit):ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			-- When close enough, dock to player raft
			if not docked and dir.Magnitude < 15 then
				docked = true

				-- Remove AlignPosition/Orientation
				alignPos:Destroy()
				alignOri:Destroy()
				attachment:Destroy()

				-- Find the closest raft floor tile using grid coordinates
				local raftPrimary = b.PrimaryPart
				local piratePos = rootPart.Position

				-- Use yaw-only CFrame for consistent grid calculations.
				-- Prefer RestYaw attribute (matches BuildingSystem placement)
				-- since ToEulerAnglesYXZ on a 90° pitched PrimaryPart is
				-- gimbal-locked and unreliable.
				local raftYaw = raftPrimary:GetAttribute("RestYaw")
				if not raftYaw then
					local _, yaw, _ = raftPrimary.CFrame:ToEulerAnglesYXZ()
					raftYaw = yaw
				end
				local flatCF = CFrame.new(raftPrimary.Position) * CFrame.Angles(0, raftYaw, 0)

				-- Collect all floor tile world positions (initial + placed tiles)
				local tilePositions = {}
				-- Initial raft tiles: compute grid coords from position
				for _, child in b:GetChildren() do
					local gx = child:GetAttribute("GridX")
					local gz = child:GetAttribute("GridZ")
					if gx and gz and child:GetAttribute("BuildType") == "raft" then
						local worldPos = flatCF:PointToWorldSpace(Vector3.new(gx * GRID_SIZE, 0, gz * GRID_SIZE))
						table.insert(tilePositions, worldPos)
					elseif child.Name == "Raft_part" or child == raftPrimary then
						local pos
						if child:IsA("Model") then
							pos = child:GetPivot().Position
						elseif child:IsA("BasePart") then
							pos = child.Position
						end
						if pos then
							local localPos = flatCF:PointToObjectSpace(pos)
							local gridX = math.round(localPos.X / GRID_SIZE)
							local gridZ = math.round(localPos.Z / GRID_SIZE)
							local worldPos = flatCF:PointToWorldSpace(Vector3.new(gridX * GRID_SIZE, 0, gridZ * GRID_SIZE))
							table.insert(tilePositions, worldPos)
						end
					end
				end

				-- Find closest tile to the pirate raft
				local closestPos = tilePositions[1]
				local closestDist = (closestPos - piratePos).Magnitude
				for _, pos in tilePositions do
					local d = (pos - piratePos).Magnitude
					if d < closestDist then
						closestDist = d
						closestPos = pos
					end
				end

				-- Build flatCF centered on the closest tile
				local tileCF = CFrame.new(closestPos) * CFrame.Angles(0, raftYaw, 0)

				-- Determine which side the pirate raft is approaching from
				local localDir = tileCF:PointToObjectSpace(piratePos)
				local halfGrid = GRID_SIZE / 2
				local pirateHalf = rootPart.Size.X / 2

				local dockOffset
				if math.abs(localDir.X) > math.abs(localDir.Z) then
					if localDir.X > 0 then
						dockOffset = Vector3.new(halfGrid + pirateHalf, 0, 0)
					else
						dockOffset = Vector3.new(-halfGrid - pirateHalf, 0, 0)
					end
				else
					if localDir.Z > 0 then
						dockOffset = Vector3.new(0, 0, halfGrid + pirateHalf)
					else
						dockOffset = Vector3.new(0, 0, -halfGrid - pirateHalf)
					end
				end

				-- Snap pirate raft flush to the edge, matching existing
				-- Raft_part orientation (not the SpawnLocation PrimaryPart's
				-- orientation). Build the world rotation as
				-- raftPrimary.CFrame.Rotation * tileCorrection so pitch/roll/
				-- yaw all come from an existing Raft_part, avoiding the
				-- gimbal-locked ToEulerAnglesYXZ on a 90° pitched PrimaryPart.
				local dockWorld = tileCF:PointToWorldSpace(dockOffset)
				local tileCorrection = getTileRotationCorrection(b)
				local tileWorldRotation = raftPrimary.CFrame.Rotation * tileCorrection
				rootPart.CFrame = CFrame.new(Vector3.new(dockWorld.X, raftPrimary.Position.Y, dockWorld.Z)) * tileWorldRotation

				-- Weld all pirate raft parts to the player raft
				for _, part in floor:GetDescendants() do
					if part:IsA("BasePart") then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = raftPrimary
						weld.Part1 = part
						weld.Parent = part
					end
				end
				if floor:IsA("BasePart") then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = raftPrimary
					weld.Part1 = floor
					weld.Parent = floor
				end

				-- Remove transit welds and restore pirate movement
				for _, w in transitWelds do
					if w and w.Parent then
						w:Destroy()
					end
				end

				-- Release pirates onto the player raft
				for idx, pirate in pirates do
					if pirate and pirate.Parent then
						local hum = pirate:FindFirstChildWhichIsA("Humanoid")
						if hum then
							-- Don't touch WalkSpeed — the ZombieScript manages it.
							-- Only disable jumping so pirates stay on the raft.
							hum.JumpPower = 0
							hum.JumpHeight = 0
						end
						-- Disable respawn in their AI config
						local configs = pirate:FindFirstChild("Configurations")
						if configs then
							local canRespawn = configs:FindFirstChild("CanRespawn")
							if canRespawn then canRespawn.Value = false end
						end
						local hrp = pirate:FindFirstChild("HumanoidRootPart")
						if hrp then
							local offsetX = (idx - 1) * 3 - 1.5
							pirate:PivotTo(CFrame.new(raftPrimary.Position + Vector3.new(offsetX, 5, 0)))
						end
					end
				end

				break -- stop movement loop
			end

			task.wait(0.5)
		end
	end)

	-- Cleanup: when all pirates dead OR self-destruct after 2 minutes
	task.spawn(function()
		-- Self-destruct timer
		task.delay(SELF_DESTRUCT_TIME, function()
			-- Kill all living pirates
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local hum = pirate:FindFirstChildWhichIsA("Humanoid")
					if hum and hum.Health > 0 then
						hum.Health = 0
					end
				end
			end
			-- Fire in case Died events didn't cover all
			allDeadEvent:Fire()
		end)

		allDeadEvent.Event:Wait()
		allDeadEvent:Destroy()

		if not floor or not floor.Parent then return end

		-- Remove all welds connecting pirate raft to player raft before sinking
		local function removeWelds(obj)
			for _, d in obj:GetDescendants() do
				if d:IsA("WeldConstraint") then
					d:Destroy()
				end
			end
			if obj:IsA("BasePart") then
				for _, w in obj:GetChildren() do
					if w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end
			end
		end
		removeWelds(floor)

		-- Gather pirate raft parts only
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
			if pirate and pirate.Parent and not pirate:GetAttribute("Claimed") then
				pirate:Destroy()
			end
		end
	end)
end

-- First spawn after 10 seconds, guaranteed
task.wait(10)
spawnPirateRaft()

-- Then every 180 seconds (3 minutes)
while true do
	task.wait(180)
	spawnPirateRaft()
end
