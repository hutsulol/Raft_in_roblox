local SPEED = 25
local FORCE_PER_MASS = 33 -- force scales with total raft mass

local boat = workspace:WaitForChild("Raft")
while not boat.PrimaryPart do
	task.wait(0.1)
end

local primaryPart = boat.PrimaryPart

local attachment = Instance.new("Attachment")
attachment.Parent = primaryPart

local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = attachment
vectorForce.ApplyAtCenterOfMass = true
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.Force = Vector3.new(0, 0, 0)
vectorForce.Parent = primaryPart

-- Lock the raft heading at startup so it travels in a straight line
local _, initialYaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedCFrame = CFrame.Angles(0, initialYaw, 0)

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Attachment0 = attachment
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.RigidityEnabled = false
alignOrientation.MaxTorque = 50000
alignOrientation.Responsiveness = 15
alignOrientation.CFrame = lockedCFrame
alignOrientation.Parent = primaryPart

-- Compute forward direction once (LookVector = along the logs)
local forwardVector = primaryPart.CFrame.LookVector
local forwardDirection = Vector3.new(forwardVector.X, 0, forwardVector.Z).Unit

game:GetService("RunService").Heartbeat:Connect(function()
	if not primaryPart or not primaryPart.Parent then
		return
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local flatSpeed = flatVelocity.Magnitude

	local forceFactor = math.clamp(1 - (flatSpeed / SPEED), 0, 1)

	local totalMass = primaryPart.AssemblyMass
	vectorForce.Force = forwardDirection * FORCE_PER_MASS * totalMass * forceFactor

	-- Keep the raft locked to its initial heading (prevents curving)
	alignOrientation.CFrame = lockedCFrame
end)
