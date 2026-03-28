local TweenService = game:GetService("TweenService")
local rs = game:GetService("ReplicatedStorage")

local SPAWN_INTERVAL = 10 -- seconds between spawn checks
local SPAWN_CHANCE = 0.7 -- 70% chance each check (high for testing)
local PIRATE_COUNT = 2 -- pirates per raft
local APPROACH_SPEED = 40 -- studs per second
local SINK_DURATION = 4 -- seconds to sink and fade

local raftPartTemplate = rs:WaitForChild("Raft_part")
local pirateTemplate = rs:FindFirstChild("Pirate lvl1")

local function getPlayerRaft()
	return workspace:FindFirstChild("Raft")
end

local function spawnPirateRaft()
	local playerRaft = getPlayerRaft()
	if not playerRaft or not playerRaft.PrimaryPart then return end

	local raftPos = playerRaft.PrimaryPart.Position

	-- Spawn 200-400 studs away in a random direction
	local angle = math.random() * math.pi * 2
	local dist = math.random(200, 400)
	local spawnPos = Vector3.new(
		raftPos.X + math.cos(angle) * dist,
		raftPos.Y,
		raftPos.Z + math.sin(angle) * dist
	)

	-- Create the pirate raft model
	local pirateRaft = Instance.new("Model")
	pirateRaft.Name = "PirateRaft"

	-- Clone a raft floor piece
	local floor = raftPartTemplate:Clone()
	if floor:IsA("Model") then
		floor:PivotTo(CFrame.new(spawnPos))
		pirateRaft.PrimaryPart = floor.PrimaryPart
		floor.Parent = pirateRaft
		for _, desc in floor:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				desc:SetNetworkOwner(nil)
			end
		end
	elseif floor:IsA("BasePart") then
		floor.CFrame = CFrame.new(spawnPos)
		floor.Anchored = false
		floor:SetNetworkOwner(nil)
		pirateRaft.PrimaryPart = floor
		floor.Parent = pirateRaft
	end

	pirateRaft.Parent = workspace

	-- Spawn pirates on the raft
	local pirates = {}
	if pirateTemplate then
		for i = 1, PIRATE_COUNT do
			local pirate = pirateTemplate:Clone()

			-- Offset pirates slightly so they don't overlap
			local offsetX = (i - 1) * 3 - 1.5
			local piratePos = spawnPos + Vector3.new(offsetX, 3, 0)

			if pirate:IsA("Model") then
				pirate:PivotTo(CFrame.new(piratePos))
			end
			pirate.Parent = pirateRaft

			table.insert(pirates, pirate)
		end
	end

	-- Move the pirate raft toward the player raft
	task.spawn(function()
		-- Use BodyVelocity-like approach with AlignPosition on the floor
		local rootPart = pirateRaft.PrimaryPart
		if not rootPart then return end

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

		-- Update target position toward player raft
		while pirateRaft and pirateRaft.Parent and rootPart and rootPart.Parent do
			local pRaft = getPlayerRaft()
			if not pRaft or not pRaft.PrimaryPart then break end

			local targetPos = pRaft.PrimaryPart.Position
			alignPos.Position = Vector3.new(targetPos.X, rootPart.Position.Y, targetPos.Z)

			-- Face toward player raft
			local dir = (targetPos - rootPart.Position)
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 1 then
				local lookCF = CFrame.lookAt(Vector3.zero, dir.Unit)
				local _, yaw, _ = lookCF:ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			-- Stop approaching when close enough (within 15 studs)
			local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)).Magnitude
			if flatDist < 15 then
				alignPos.MaxVelocity = 0
			else
				alignPos.MaxVelocity = APPROACH_SPEED
			end

			task.wait(0.5)
		end
	end)

	-- Monitor pirates: when all dead, sink the raft
	task.spawn(function()
		while pirateRaft and pirateRaft.Parent do
			task.wait(1)

			-- Check if all pirates are dead
			local allDead = true
			for _, pirate in pirates do
				if pirate and pirate.Parent then
					local humanoid = pirate:FindFirstChildWhichIsA("Humanoid")
					if humanoid and humanoid.Health > 0 then
						allDead = false
						break
					end
				end
			end

			if allDead then
				-- Begin sinking
				local rootPart = pirateRaft.PrimaryPart
				if not rootPart then
					pirateRaft:Destroy()
					return
				end

				-- Remove movement forces
				for _, desc in pirateRaft:GetDescendants() do
					if desc:IsA("AlignPosition") or desc:IsA("AlignOrientation") or desc:IsA("Attachment") then
						desc:Destroy()
					end
				end

				-- Collect all base parts for fading
				local allParts = {}
				for _, desc in pirateRaft:GetDescendants() do
					if desc:IsA("BasePart") then
						table.insert(allParts, desc)
					end
				end

				-- Sink downward and fade out
				local startY = rootPart.Position.Y
				local sinkY = startY - 15

				-- Anchor all parts for controlled sinking
				for _, part in allParts do
					part.Anchored = true
					part.CanCollide = false
				end

				local elapsed = 0
				local steps = SINK_DURATION / 0.05
				for step = 1, steps do
					if not pirateRaft or not pirateRaft.Parent then break end

					elapsed = step * 0.05
					local alpha = elapsed / SINK_DURATION

					-- Move down
					local currentY = startY + (sinkY - startY) * alpha

					for _, part in allParts do
						if part and part.Parent then
							part.CFrame = part.CFrame * CFrame.new(0, (sinkY - startY) * (0.05 / SINK_DURATION), 0)
							part.Transparency = alpha
						end
					end

					task.wait(0.05)
				end

				-- Fully remove
				if pirateRaft and pirateRaft.Parent then
					pirateRaft:Destroy()
				end
				return
			end
		end
	end)
end

-- Main spawn loop
while true do
	task.wait(SPAWN_INTERVAL)

	local raft = getPlayerRaft()
	if not raft then continue end

	if math.random() < SPAWN_CHANCE then
		spawnPirateRaft()
	end
end
