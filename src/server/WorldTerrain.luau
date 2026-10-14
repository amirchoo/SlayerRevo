--!strict
-- Sculpts the land around the hub from shared/Config/WorldConfig: flat ground at the hub,
-- forested hills around it, a gently rolling plain to the north (the hunting grounds) with a
-- river and lakes across it, dirt paths, flattened clearings, rock outcrops, and mountains
-- along the map edge. Terrain is saved in the place, so this isn't run by the game: run
-- tools/generate_terrain.lua in Studio (edit mode) after changing the world's shape, then
-- save the place. It's deterministic (WorldConfig.Seed): the same config gives the same land.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local WorldMap = require(ReplicatedStorage.Shared.WorldMap)

type Segment = WorldMap.Segment

local RESOLUTION = 4
local CHUNK = 64 -- studs per side of one WriteVoxels call
local Y_MIN = -16
local Y_MAX = 176
-- Sculpt this far from the center: past the mountains' far side (whole chunks).
local EDGE = math.ceil((WorldConfig.HalfSize + WorldConfig.Mountains.Back) / CHUNK) * CHUNK

local G = WorldConfig.GroundY
local SEED = WorldConfig.Seed
local WATER_LEVEL = G - 1
local smoothstep = WorldMap.smoothstep

local WorldTerrain = {}

local function noise(p: Vector2, scale: number, octaves: number, salt: number): number
	local total, amplitude, frequency = 0, 1, 1 / scale
	for _ = 1, octaves do
		total += math.noise(p.X * frequency, p.Y * frequency, SEED + salt) * amplitude
		amplitude /= 2
		frequency *= 2
	end
	return total
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The land before paths, clearings and the river shape it.
local function naturalHeight(p: Vector2): number
	local wild, plain, mountain = WorldMap.wildWeight(p), WorldMap.plainWeight(p), WorldMap.mountainWeight(p)
	local hills = math.clamp(noise(p, 260, 3, 0) * 1.3 + 0.5, 0, 1) * WorldConfig.HillHeight + noise(p, 60, 2, 10) * 3
	local plainHeight = noise(p, 300, 2, 20) * WorldConfig.PlainHeight * 2 + noise(p, 90, 2, 30) * 1.5
	local height = G + wild * lerp(hills, plainHeight, plain)
	local peaks = 0.75 + 0.5 * math.clamp(noise(p, 140, 3, 40) + 0.5, 0, 1)
	return height + mountain ^ 1.5 * WorldConfig.Mountains.Height * peaks
end

-- Paths follow a smoothed version of the land, so they never climb a steep hill.
local function pathHeight(p: Vector2): number
	local wild, plain, mountain = WorldMap.wildWeight(p), WorldMap.plainWeight(p), WorldMap.mountainWeight(p)
	local low = math.clamp(noise(p, 400, 1, 50) * 1.3 + 0.5, 0, 1) * 10
	local plainHeight = noise(p, 300, 2, 20) * WorldConfig.PlainHeight * 2
	return G + wild * lerp(low, plainHeight, plain) + mountain ^ 1.5 * WorldConfig.Mountains.Height * 0.75
end

local clearingHeights: { [WorldConfig.Clearing]: number } = {}
for _, clearing in WorldConfig.Clearings do
	clearingHeights[clearing] = naturalHeight(clearing.Position)
end

type Nearby = { paths: { Segment }, river: { Segment } }

-- Final ground height at `p`, and how much of a path (0..1) and how far from the water it is.
local function shape(p: Vector2, nearby: Nearby): (number, number, number)
	local height = naturalHeight(p)

	local halfPath = WorldConfig.PathWidth / 2
	local pathDistance = WorldMap.distanceTo(p, nearby.paths)
	local onPath = smoothstep(halfPath + 10, halfPath, pathDistance)
	if onPath > 0 then
		height = lerp(height, pathHeight(p), onPath)
	end

	for clearing, centerHeight in clearingHeights do
		local distance = (p - clearing.Position).Magnitude
		if distance < clearing.Radius + 30 then
			height = lerp(height, centerHeight, smoothstep(clearing.Radius + 30, clearing.Radius * 0.8, distance))
		end
	end

	local water = WorldMap.riverDistance(p, nearby.river)
	if water < 14 then
		local bed = G - WorldConfig.River.Depth
		height = bed + (height - bed) * smoothstep(-3, 14, water)
	end
	return height, onPath, water
end

local function surface(p: Vector2, height: number, slope: number, onPath: number, water: number): Enum.Material
	local mountain = WorldMap.mountainWeight(p)
	if water < 3 then
		return Enum.Material.Mud
	elseif onPath > 0.5 + noise(p, 8, 1, 60) * 0.3 then
		return Enum.Material.Ground
	elseif height > G + 112 then
		return Enum.Material.Snow
	elseif slope > 1.1 or (mountain > 0.3 and slope > 0.55) or height > G + 85 then
		return if noise(p, 30, 1, 70) > 0 then Enum.Material.Rock else Enum.Material.Slate
	elseif water < 7 then
		return Enum.Material.Ground
	end
	local forest = WorldMap.wildWeight(p) > 0.5 and WorldMap.plainWeight(p) < 0.5 and not WorldMap.clearingAt(p)
	if forest and noise(p, 50, 2, 80) < 0.15 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

local function writeChunk(x0: number, z0: number)
	local cells = CHUNK // RESOLUTION
	local layers = (Y_MAX - Y_MIN) // RESOLUTION
	local nearby: Nearby = {
		paths = WorldMap.near(WorldMap.PathSegments, Vector2.new(x0, z0), Vector2.new(x0 + CHUNK, z0 + CHUNK), 40),
		river = WorldMap.near(WorldMap.RiverSegments, Vector2.new(x0, z0), Vector2.new(x0 + CHUNK, z0 + CHUNK), 40),
	}

	-- Heights for the chunk's columns plus a one-column border (for slopes).
	local heights: { { number } } = {}
	local paths: { { number } } = {}
	local waters: { { number } } = {}
	for i = 0, cells + 1 do
		heights[i], paths[i], waters[i] = {}, {}, {}
		for k = 0, cells + 1 do
			local p = Vector2.new(x0 + (i - 0.5) * RESOLUTION, z0 + (k - 0.5) * RESOLUTION)
			heights[i][k], paths[i][k], waters[i][k] = shape(p, nearby)
		end
	end

	local materials = table.create(cells)
	local occupancies = table.create(cells)
	for i = 1, cells do
		local materialColumn, occupancyColumn = table.create(layers), table.create(layers)
		materials[i], occupancies[i] = materialColumn, occupancyColumn
		for j = 1, layers do
			materialColumn[j], occupancyColumn[j] = table.create(cells), table.create(cells)
		end
		for k = 1, cells do
			local p = Vector2.new(x0 + (i - 0.5) * RESOLUTION, z0 + (k - 0.5) * RESOLUTION)
			local height = heights[i][k]
			local slope = Vector2.new(heights[i + 1][k] - heights[i - 1][k], heights[i][k + 1] - heights[i][k - 1]).Magnitude / (2 * RESOLUTION)
			local top = surface(p, height, slope, paths[i][k], waters[i][k])
			local deep = if WorldMap.mountainWeight(p) > 0.3 then Enum.Material.Rock else Enum.Material.Ground
			local wet = waters[i][k] < 4
			for j = 1, layers do
				local bottom = Y_MIN + (j - 1) * RESOLUTION
				local solid = math.clamp((height - bottom) / RESOLUTION, 0, 1)
				local material, occupancy = Enum.Material.Air, 0
				if solid > 0.05 then
					material = if height - (bottom + RESOLUTION) > 6 then deep else top
					occupancy = solid
				elseif wet and bottom < WATER_LEVEL then
					material = Enum.Material.Water
					occupancy = math.clamp((WATER_LEVEL - bottom) / RESOLUTION, 0, 1)
				end
				materials[i][j][k] = material
				occupancies[i][j][k] = occupancy
			end
		end
	end

	local region = Region3.new(Vector3.new(x0, Y_MIN, z0), Vector3.new(x0 + CHUNK, Y_MAX, z0 + CHUNK))
	workspace.Terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)
end

-- How many rows of chunks the land has (for running it in parts).
WorldTerrain.Rows = (2 * EDGE) // CHUNK

-- Sculpts rows `first` to `last` (1-based, north to south) of the land; all rows when omitted.
function WorldTerrain.generate(first: number?, last: number?)
	for row = first or 1, last or WorldTerrain.Rows do
		local z0 = -EDGE + (row - 1) * CHUNK
		for x0 = -EDGE, EDGE - CHUNK, CHUNK do
			writeChunk(x0, z0)
		end
		task.wait()
	end
end

-- Rock outcrops scattered through the forest and plain (run after all rows).
function WorldTerrain.addRocks()
	local random = Random.new(SEED + 1)
	local rocks = WorldConfig.Rocks
	local placed, tries = 0, 0
	local nearby: Nearby = { paths = WorldMap.PathSegments, river = WorldMap.RiverSegments }
	while placed < rocks.Count and tries < rocks.Count * 20 do
		tries += 1
		local p = Vector2.new(random:NextNumber(-900, 900), random:NextNumber(-900, 900))
		local clear = WorldMap.squareDistance(p) > WorldConfig.HubFlat + 20
			and WorldMap.distanceTo(p, WorldMap.PathSegments) > 20
			and WorldMap.riverDistance(p) > 20
			and not WorldMap.clearingAt(p, 15)
		if clear then
			local height = shape(p, nearby)
			local radius = random:NextNumber(rocks.Radius[1], rocks.Radius[2])
			local center = Vector3.new(p.X, height - radius * 0.35, p.Y)
			workspace.Terrain:FillBall(center, radius, if random:NextNumber() < 0.6 then Enum.Material.Rock else Enum.Material.Slate)
			if random:NextNumber() < 0.5 then
				local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * radius
				workspace.Terrain:FillBall(center + offset, radius * 0.6, Enum.Material.Rock)
			end
			placed += 1
		end
	end
	return placed
end

return WorldTerrain
