
--------DO NOT TOUCH ANYTHING IN HERE UNLESS YOU KNOW WHAT YOU'RE DOING!!!--------

script.Parent.MaxSpeed = script.Parent.Settings.MaxSpeed.Value
maxspeed = script.Parent.MaxSpeed
script.Parent.BodyPosition.position = script.Parent.Position
script.Parent.BodyGyro.cframe = script.Parent.CFrame

value1 = 0

while true do

wait()

if script.Parent.Throttle == 1 then
	
	if value1 < maxspeed then value1 = value1 + script.Parent.Settings.Acceleration.Value end
		
		script.Parent.Driving.Value = true
		
		script.Parent.BodyVelocity.velocity = script.Parent.CFrame.lookVector*value1
		
		script.Parent.Left.Value = false
		
		script.Parent.Right.Value = false
end

if script.Parent.Throttle == 0 then 
	
	script.Parent.Driving.Value = false
	
	script.Parent.BodyVelocity.velocity = script.Parent.CFrame.lookVector*value1
	
	script.Parent.Left.Value = false
	
	script.Parent.Right.Value = false
	
end

if script.Parent.Throttle == -1 then

	if value1 > - maxspeed then value1 = value1 -script.Parent.Settings.Acceleration.Value end
		
		script.Parent.Driving.Value = true
		
		script.Parent.BodyVelocity.velocity = script.Parent.CFrame.lookVector*value1
		
		script.Parent.Left.Value = false
		
		script.Parent.Right.Value = false
		
end

if script.Parent.Steer == 1 then
	
	script.Parent.BodyGyro.cframe = script.Parent.BodyGyro.cframe * CFrame.fromEulerAnglesXYZ(0,- script.Parent.Settings.TurnSpeed.Value,0)
	
	script.Parent.Driving.Value = true
	
	script.Parent.Right.Value = true
	
	script.Parent.Left.Value = false
	
end

if script.Parent.Steer == -1 then
	
	
	script.Parent.BodyGyro.cframe = script.Parent.BodyGyro.cframe * CFrame.fromEulerAnglesXYZ(0,script.Parent.Settings.TurnSpeed.Value,0)
	
	script.Parent.Driving.Value = true
	
	script.Parent.Left.Value = true
	
	script.Parent.Right.Value = false
	
end
end
--Boat script by Rengate