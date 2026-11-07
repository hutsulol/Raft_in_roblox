local RaftController = {}

RaftController.SPEED = 6
RaftController.offset = Vector3.zero

function RaftController.advance(lookVector: Vector3, dt: number)
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	RaftController.offset += direction * RaftController.SPEED * dt
end

return RaftController