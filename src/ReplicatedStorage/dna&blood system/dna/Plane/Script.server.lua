
local part = script.Parent
local rotationSpeed = 180 


game:GetService("RunService").Heartbeat:Connect(function(dt)
	local angle = math.rad(rotationSpeed * dt)
	part.CFrame = part.CFrame * CFrame.Angles(0, angle, 0)
end)
