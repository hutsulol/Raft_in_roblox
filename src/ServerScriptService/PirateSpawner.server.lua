local TweenService = game:GetService("TweenService")
local rs = game:GetService("ReplicatedStorage")

local SPAWN_INTERVAL = 5
local SPAWN_CHANCE = 1.0
local PIRATE_COUNT = 2
local APPROACH_SPEED = 80
local SINK_DURATION = 4
local FIRST_SPAWN_DELAY = 3

local raftPartTemplate = rs:WaitForChild("Raft_part")
local pirateTemplate = rs:FindFirstChild("Pirate lvl1")

local function getPlayerRaft()
	return workspace:FindFirstChild("Raft")
end

local function spawnPirateRaft()
	local playerRaft = getPlayerRaft()
	if not playerRaft or not playerRaft.PrimaryPart then return end

	local raftPos = playerRaft.PrimaryPart.Position

	local angle = math.random() * math.pi * 2
	local dist = math.random(80, 150)
	local spawnPos = Vector3.new(
		raftPos.X + math.cos(angle) * dist,
		raftPos.Y,
		raftPos.Z + math.sin(angle) * dist
	)

	-- Create a simple Part as the pirate raft floor
	local floorPart = Instance.new("Part")
	floorPart.Name = "PirateRaftFloor"
	floorPart.Size = Vector3.new(8, 1, 8)
	floorPart.CFrame = CFrame.new(spawnPos)
	floorPart.Anchored = false
	floorPart.Material = Enum.Material.Wood
	floorPart.BrickColor = BrickColor.new("Brown")
	floorPart:SetNetworkOwner(nil)

	local pirateRaft = Instance.new("Model")
	pirateRaft.Name = "PirateRaft"
	pirateRaft.PrimaryPart = floorPart
	floorPart.Parent = pirateRaft

	-- Also clone the visual Raft_part and weld it on top for looks
	local visual = raftPartTemplate:Clone()
	if visual:IsA("Model") then
		visual:PivotTo(CFrame.new(spawnPos))
		visual.Parent = pirateRaft
		for _, desc in visual:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				desc.CanCollide = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = desc
				weld.Part1 = floorPart
				weld.Parent = desc
			end
		end
	elseif visual:IsA("BasePart") then
		visual.CFrame = CFrame.new(spawnPos)
		visual.Anchored = false
		visual.Parent = pirateRaft
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = visual
		weld.Part1 = floorPart
		weld.Parent = visual
	end

	-- Hide the base part inside the visual
	floorPart.Transparency = 1

	pirateRaft.Parent = workspace

	-- Spawn pirates on the raft
	local pirates = {}
	if pirateTemplate then
		for i = 1, PIRATE_COUNT do
			local pirate = pirateTemplate:Clone()
			local offsetX = (i - 1) * 3 - 1.5
			local piratePos = spawnPos + Vector3.new(offsetX, 4, 0)

			if pirate:IsA("Model") then
				pirate:PivotTo(CFrame.new(piratePos))
			end
			pirate.Parent = workspace

			table.insert(pirates, pirate)
		end
	end

	-- Movement: approach the player raft
	task.spawn(function()
		local attachment = Instance.new("Attachment")
		attachment.Parent = floorPart

		local alignPos = Instance.new("AlignPosition")
		alignPos.Attachment0 = attachment
		alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPos.MaxForce = 50000
		alignPos.MaxVelocity = APPROACH_SPEED
		alignPos.Responsiveness = 10
		alignPos.Parent = floorPart

		local alignOri = Instance.new("AlignOrientation")
		alignOri.Attachment0 = attachment
		alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOri.RigidityEnabled = false
		alignOri.MaxTorque = 10000
		alignOri.Responsiveness = 10
		alignOri.Parent = floorPart

		while pirateRaft and pirateRaft.Parent and floorPart and floorPart.Parent do
			local pRaft = getPlayerRaft()
			if not pRaft or not pRaft.PrimaryPart then break end

			local targetPos = pRaft.PrimaryPart.Position
			alignPos.Position = Vector3.new(targetPos.X, floorPart.Position.Y, targetPos.Z)

			local dir = Vector3.new(targetPos.X - floorPart.Position.X, 0, targetPos.Z - floorPart.Position.Z)
			if dir.Magnitude > 1 then
				local lookCF = CFrame.lookAt(Vector3.zero, dir.Unit)
				local _, yaw, _ = lookCF:ToEulerAnglesYXZ()
				alignOri.CFrame = CFrame.Angles(0, yaw, 0)
			end

			local flatDist = dir.Magnitude
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
				-- Remove movement
				for _, desc in pirateRaft:GetDescendants() do
					if desc:IsA("AlignPosition") or desc:IsA("AlignOrientation") or desc:IsA("Attachment") then
						desc:Destroy()
					end
				end

				-- Collect all parts for sinking
				local allParts = {}
				for _, desc in pirateRaft:GetDescendants() do
					if desc:IsA("BasePart") then
						desc.Anchored = true
						desc.CanCollide = false
						table.insert(allParts, desc)
					end
				end

				-- Sink and fade
				local sinkPerStep = -15 * (0.05 / SINK_DURATION)
				local steps = math.floor(SINK_DURATION / 0.05)
				for step = 1, steps do
					if not pirateRaft or not pirateRaft.Parent then break end
					local alpha = step / steps

					for _, part in allParts do
						if part and part.Parent then
							part.CFrame = part.CFrame + Vector3.new(0, sinkPerStep, 0)
							part.Transparency = alpha
						end
					end
					task.wait(0.05)
				end

				if pirateRaft and pirateRaft.Parent then
					pirateRaft:Destroy()
				end
				-- Clean up dead pirate bodies
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

-- First spawn quickly for testing
task.wait(FIRST_SPAWN_DELAY)
local raft = getPlayerRaft()
if raft then
	spawnPirateRaft()
end

-- Main spawn loop
while true do
	task.wait(SPAWN_INTERVAL)

	raft = getPlayerRaft()
	if not raft then continue end

	if math.random() < SPAWN_CHANCE then
		spawnPirateRaft()
	end
end
