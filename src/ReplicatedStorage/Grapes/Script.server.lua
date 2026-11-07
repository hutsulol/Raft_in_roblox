Tool = script.Parent
enabled = true

function onActivated()
	if not enabled  then
		return
	end

	enabled = false
	Tool.GripForward = Vector3.new(-0.97, 1.02e-005, -0.243)
	Tool.GripPos = Vector3.new(-0.2, 0, -1.23)
	Tool.GripRight = Vector3.new(0.197, 0.581, -0.79)
	Tool.GripUp = Vector3.new(-0.141, 0.814, 0.563)

	wait(1.2)
	
	Tool:Destroy()
	
end

script.Parent.Activated:connect(onActivated)