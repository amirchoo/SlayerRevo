--!strict
-- Bounds of the Training Grounds arena (a floating platform away from the hub).
-- Shared so the server builds it and the client can name the zone.

local TrainingArea = {}

TrainingArea.CENTER = Vector3.new(800, 100, 0) -- center of the floor's top surface
TrainingArea.HALF_SIZE = 60 -- studs from the center to each edge (a 120 x 120 arena)

function TrainingArea.contains(position: Vector3): boolean
	local offset = position - TrainingArea.CENTER
	return math.abs(offset.X) <= TrainingArea.HALF_SIZE
		and math.abs(offset.Z) <= TrainingArea.HALF_SIZE
		and offset.Y > -20
		and offset.Y < 60
end

return TrainingArea
