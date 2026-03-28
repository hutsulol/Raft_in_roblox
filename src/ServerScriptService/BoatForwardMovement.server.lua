local SPEED = 300
local FORCE_PER_MASS = 100 -- force scales with total raft mass

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

game:GetService("RunService").Heartbeat:Connect(function()
	if not primaryPart or not primaryPart.Parent then
		return
	end

	local lookVector = primaryPart.CFrame.LookVector
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local flatSpeed = flatVelocity.Magnitude

	local forceFactor = math.clamp(1 - (flatSpeed / SPEED), 0, 1)
	local forceDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit

	local totalMass = primaryPart.AssemblyMass
	vectorForce.Force = forceDirection * FORCE_PER_MASS * totalMass * forceFactor

	local currentCFrame = primaryPart.CFrame
	local _, currentY, _ = currentCFrame:ToEulerAnglesYXZ()
	alignOrientation.CFrame = CFrame.Angles(0, currentY, 0)
end)
