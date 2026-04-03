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

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Attachment0 = attachment
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.RigidityEnabled = false
alignOrientation.MaxTorque = 10000
alignOrientation.Responsiveness = 10
alignOrientation.Parent = primaryPart

-- Lock the raft heading at startup so it travels in a straight line
local _, initialYaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
local lockedYaw = initialYaw

-- Compute forward direction once (LookVector = along the logs)
local forwardVector = primaryPart.CFrame.LookVector
local forwardDirection = Vector3.new(forwardVector.X, 0, forwardVector.Z)
if forwardDirection.Magnitude > 0.001 then
	forwardDirection = forwardDirection.Unit
else
	forwardDirection = Vector3.new(0, 0, -1)
end

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

	-- Lock yaw to initial heading (prevents curving), allow pitch/roll to follow water
	alignOrientation.CFrame = CFrame.Angles(0, lockedYaw, 0)
end)
