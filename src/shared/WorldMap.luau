--!strict
-- Geometry of the world around the hub (from Config/WorldConfig), shared by the terrain
-- sculptor (server WorldTerrain, run in edit mode) and the world builder (server WorldBuilder,
-- which places trees, ruins and chests at start): which region a spot is in, and how far it
-- is from the paths, the river and the clearings.

local WorldConfig = require(script.Parent.Config.WorldConfig)

local WorldMap = {}

export type Segment = { A: Vector2, B: Vector2 }

local function segments(lines: { { Vector2 } }): { Segment }
	local list = {}
	for _, line in lines do
		for i = 1, #line - 1 do
			table.insert(list, { A = line[i], B = line[i + 1] })
		end
	end
	return list
end

WorldMap.PathSegments = segments(WorldConfig.Paths)
WorldMap.RiverSegments = segments({ WorldConfig.River.Points })

local function distanceToSegment(p: Vector2, s: Segment): number
	local ab = s.B - s.A
	local t = math.clamp((p - s.A):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (s.A + ab * t)).Magnitude
end

-- Distance from `p` to the nearest of `list` (math.huge if empty).
function WorldMap.distanceTo(p: Vector2, list: { Segment }): number
	local best = math.huge
	for _, s in list do
		best = math.min(best, distanceToSegment(p, s))
	end
	return best
end

-- The segments of `list` passing within `margin` of the box from `low` to `high`, so a
-- caller working on one area only measures against nearby ones.
function WorldMap.near(list: { Segment }, low: Vector2, high: Vector2, margin: number): { Segment }
	local found = {}
	for _, s in list do
		local minX, maxX = math.min(s.A.X, s.B.X) - margin, math.max(s.A.X, s.B.X) + margin
		local minY, maxY = math.min(s.A.Y, s.B.Y) - margin, math.max(s.A.Y, s.B.Y) + margin
		if maxX >= low.X and minX <= high.X and maxY >= low.Y and minY <= high.Y then
			table.insert(found, s)
		end
	end
	return found
end

-- Distance to the river's water edge: negative in the water. Its ends widen into lakes.
function WorldMap.riverDistance(p: Vector2, list: { Segment }?): number
	local river = WorldConfig.River
	local d = WorldMap.distanceTo(p, list or WorldMap.RiverSegments) - river.Width / 2
	local points = river.Points
	for _, endPoint in { points[1], points[#points] } do
		d = math.min(d, (p - endPoint).Magnitude - river.LakeRadius)
	end
	return d
end

-- Square distance from the world center (the hub and mountains are measured this way).
function WorldMap.squareDistance(p: Vector2): number
	return math.max(math.abs(p.X), math.abs(p.Y))
end

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end
WorldMap.smoothstep = smoothstep

-- 1 inside the hunting grounds, easing to 0 across its feathered edge.
function WorldMap.plainWeight(p: Vector2): number
	local area = WorldConfig.HuntingGrounds
	local outside = math.max(area.Min.X - p.X, p.X - area.Max.X, area.Min.Y - p.Y, p.Y - area.Max.Y)
	return 1 - smoothstep(-area.Feather / 2, area.Feather / 2, outside)
end

-- 0 at the hub, easing to 1 out in the wilds.
function WorldMap.wildWeight(p: Vector2): number
	return smoothstep(WorldConfig.HubFlat, WorldConfig.HubBlend, WorldMap.squareDistance(p))
end

-- 0 inland, rising to 1 at the map edge (the ridge), and falling back to 0 beyond it.
function WorldMap.mountainWeight(p: Vector2): number
	local distance = WorldMap.squareDistance(p)
	local mountains = WorldConfig.Mountains
	local rise = smoothstep(mountains.Start, WorldConfig.HalfSize, distance)
	local fall = smoothstep(WorldConfig.HalfSize + mountains.Back, WorldConfig.HalfSize, distance)
	return rise * fall
end

-- The clearing `p` is in (within its radius), if any.
function WorldMap.clearingAt(p: Vector2, margin: number?): WorldConfig.Clearing?
	for _, clearing in WorldConfig.Clearings do
		if (p - clearing.Position).Magnitude <= clearing.Radius + (margin or 0) then
			return clearing
		end
	end
	return nil
end

return WorldMap
