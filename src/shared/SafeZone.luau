--!strict
-- The hub safe zone: a square centered on the town where enemies ignore players.
-- Shared so the server (enemy AI) and client (zone banner) agree on the boundary.

local SafeZone = {}

SafeZone.CENTER = Vector3.zero
SafeZone.HALF_SIZE = 175 -- studs from the center to each edge (a 350 x 350 hub)

function SafeZone.contains(position: Vector3): boolean
	local offset = position - SafeZone.CENTER
	return math.abs(offset.X) <= SafeZone.HALF_SIZE and math.abs(offset.Z) <= SafeZone.HALF_SIZE
end

return SafeZone
