--!strict
-- Carves a dungeon run out of solid Terrain, so it looks like the land's rock: rough walls and
-- ceilings, cobbled floors in the built rooms and corridors, dirt in the caves, basalt in the
-- arena. The map's squares stay exactly as open as DungeonGrid says (orcs route on the grid):
-- the rock is only ever cut back past their edges, by a noisy amount, never closer.
--
-- Written while a run is built and cleared (back to air) when it ends. Yields between chunks.

local DungeonConfig = require(game:GetService("ReplicatedStorage").Shared.Config.DungeonConfig)
local DungeonGrid = require(script.Parent.DungeonGrid)

type Grid = DungeonGrid.Grid
type Dungeon = DungeonConfig.Dungeon

export type Region = { cframe: CFrame, size: Vector3 }

-- An open space in plan (min/max X and Z, world studs) up to `top` studs above the floor.
type Space = { x0: number, z0: number, x1: number, z1: number, top: number, kind: Kind }
type Kind = "Built" | "Cave" | "Arena"

local RES = 4 -- studs per voxel
local CHUNK = 16 -- voxels per side of one WriteVoxels call
local WALL_CARVE = { 1.5, 3.5 } -- how far past a square's edge the walls are cut back (least, most)
local CEILING_CARVE = { 1.5, 6 } -- and the ceilings (rougher)
local BELOW = 8 -- solid rock under the floor
local ABOVE = 10 -- and over the highest ceiling
local MARGIN = 12 -- solid rock round the outside

local MATERIALS: { [Kind]: { floor: Enum.Material, floorPatch: Enum.Material, wall: Enum.Material, wallPatch: Enum.Material } } = {
	Built = { floor = Enum.Material.Cobblestone, floorPatch = Enum.Material.Slate, wall = Enum.Material.Slate, wallPatch = Enum.Material.Basalt },
	Cave = { floor = Enum.Material.Ground, floorPatch = Enum.Material.Mud, wall = Enum.Material.Rock, wallPatch = Enum.Material.Slate },
	Arena = { floor = Enum.Material.Basalt, floorPatch = Enum.Material.CrackedLava, wall = Enum.Material.Basalt, wallPatch = Enum.Material.Rock },
}

local DungeonTerrain = {}

local function noise01(p: Vector3, scale: number, salt: number): number
	local n = math.noise(p.X / scale, p.Y / scale, p.Z / scale + salt) + 0.5 * math.noise(p.X / (scale / 2.5), p.Y / (scale / 2.5), p.Z / (scale / 2.5) - salt)
	return math.clamp(0.5 + n * 0.8, 0, 1)
end

local function snapDown(v: number): number
	return math.floor(v / RES) * RES
end

local function snapUp(v: number): number
	return math.ceil(v / RES) * RES
end

-- Carves `dungeon` on `grid`, plus the round arena (`arenaCenter` on its floor) and the
-- passage from its doorway squares (`door`: min and max corner on the floor). Round the
-- `gates` (points across each gate) the rock isn't cut back, so it hugs the gate's frame.
-- `within` (low and high corner) carves only that part (to redo a bit of a saved layout).
-- Returns the region written, for clear.
function DungeonTerrain.carve(dungeon: Dungeon, grid: Grid, arenaCenter: Vector3, door: { Vector3 }, gates: { Vector3 }, within: { Vector3 }?): Region
	local cell = grid.cell
	local H, RH = dungeon.Height, dungeon.RoomHeight
	local R, AH = dungeon.Arena.Radius, dungeon.Arena.Height
	local floorY = grid.origin.Y

	-- The open spaces: every floor square, and the doorway passage.
	local spaces: { Space } = {}
	local spacesBySquare: { [number]: Space } = {}
	for i, char in grid.chars do
		if not DungeonGrid.isFloor(char) then
			continue
		end
		local c, r = DungeonGrid.square(grid, i)
		local center = DungeonGrid.position(grid, c, r)
		local inRoom = false
		for _, room in dungeon.Rooms do
			if c >= room.From.X and c <= room.To.X and r >= room.From.Y and r <= room.To.Y then
				inRoom = true
				break
			end
		end
		local space: Space = {
			x0 = center.X - cell / 2,
			z0 = center.Z - cell / 2,
			x1 = center.X + cell / 2,
			z1 = center.Z + cell / 2,
			top = if inRoom then RH else H,
			kind = if grid.cave[i] and not inRoom then "Cave" else "Built",
		}
		table.insert(spaces, space)
		spacesBySquare[i] = space
	end
	local doorway: Space = { x0 = door[1].X, z0 = door[1].Z, x1 = door[2].X, z1 = door[2].Z, top = H, kind = "Built" }

	-- The region: the map and the arena, with solid rock round them.
	local half = Vector3.new(grid.cols, 0, grid.rows) * cell / 2
	local minX = snapDown(math.min(grid.origin.X - half.X, arenaCenter.X - R) - MARGIN)
	local maxX = snapUp(math.max(grid.origin.X + half.X, arenaCenter.X + R) + MARGIN)
	local minZ = snapDown(math.min(grid.origin.Z - half.Z, arenaCenter.Z - R) - MARGIN)
	local maxZ = snapUp(grid.origin.Z + half.Z + MARGIN)
	local minY = snapDown(floorY - BELOW)
	local maxY = snapUp(floorY + math.max(H, RH, AH) + CEILING_CARVE[2] + ABOVE)
	local whole = { low = Vector3.new(minX, minY, minZ), high = Vector3.new(maxX, maxY, maxZ) }
	if within then
		minX, minZ = math.max(minX, snapDown(within[1].X)), math.max(minZ, snapDown(within[1].Z))
		maxX, maxZ = math.min(maxX, snapUp(within[2].X)), math.min(maxZ, snapUp(within[2].Z))
	end

	-- How much of the usual cut-back there is at a point: none by a gate, all of it a little way off.
	local function roughness(x: number, z: number): number
		local nearest = math.huge
		for _, point in gates do
			nearest = math.min(nearest, (Vector2.new(x, z) - Vector2.new(point.X, point.Z)).Magnitude)
		end
		local t = math.clamp((nearest - cell) / (cell * 1.5), 0, 1)
		return t * t * (3 - 2 * t)
	end

	local reach = math.max(WALL_CARVE[2], CEILING_CARVE[2]) + RES -- past this, a space can't open a voxel
	local squaresAround = math.ceil(reach / cell) + 1

	-- Per voxel column: how far it is (in plan) from the open spaces of each ceiling height, and
	-- what kind of place is nearest.
	type Column = { dx: { [number]: number }, kind: Kind?, rough: number }
	local function column(x: number, z: number): Column
		local dx: { [number]: number } = {}
		local nearest, kind: Kind? = math.huge, nil
		local function consider(space: Space)
			local ox = math.max(space.x0 - x, 0, x - space.x1)
			local oz = math.max(space.z0 - z, 0, z - space.z1)
			local d = math.sqrt(ox * ox + oz * oz)
			if d > reach then
				return
			end
			if d < (dx[space.top] or math.huge) then
				dx[space.top] = d
			end
			if d < nearest then
				nearest, kind = d, space.kind
			end
		end
		local c, r = DungeonGrid.squareAt(grid, Vector3.new(x, floorY, z))
		for dr = -squaresAround, squaresAround do
			for dc = -squaresAround, squaresAround do
				local i = DungeonGrid.index(grid, c + dc, r + dr)
				local space = i and spacesBySquare[i]
				if space then
					consider(space)
				end
			end
		end
		consider(doorway)
		local fromArena = math.max(0, (Vector2.new(x, z) - Vector2.new(arenaCenter.X, arenaCenter.Z)).Magnitude - R)
		if fromArena <= reach then
			dx[AH] = math.min(dx[AH] or math.huge, fromArena)
			if fromArena < nearest then
				nearest, kind = fromArena, "Arena"
			end
		end
		return { dx = dx, kind = kind, rough = roughness(x, z) }
	end

	local sizeX, sizeY, sizeZ = (maxX - minX) / RES, (maxY - minY) / RES, (maxZ - minZ) / RES
	for cz = 0, sizeZ - 1, CHUNK do
		for cx = 0, sizeX - 1, CHUNK do
			local nx, nz = math.min(CHUNK, sizeX - cx), math.min(CHUNK, sizeZ - cz)
			local materials, occupancies = {}, {}
			local columns: { { Column } } = {}
			for ix = 1, nx do
				columns[ix] = {}
				for iz = 1, nz do
					local x = minX + (cx + ix - 0.5) * RES
					local z = minZ + (cz + iz - 0.5) * RES
					columns[ix][iz] = column(x, z)
				end
			end
			for ix = 1, nx do
				materials[ix], occupancies[ix] = {}, {}
				for iy = 1, sizeY do
					materials[ix][iy], occupancies[ix][iy] = {}, {}
					local y = minY + (iy - 0.5) * RES - floorY -- above the floor
					for iz = 1, nz do
						local col = columns[ix][iz]
						local p = Vector3.new(minX + (cx + ix - 0.5) * RES, y, minZ + (cz + iz - 0.5) * RES)
						local look = MATERIALS[col.kind or "Built"]
						local occupancy, material
						if y < 0 then
							-- The top layer half full puts the surface right on the floor line.
							occupancy = if y > -RES then 0.5 else 1
							material = if col.kind and noise01(p, 18, 3) > 0.68 then look.floorPatch elseif col.kind then look.floor else look.wall
						else
							-- How far the voxel is from open space, and how far the rock is cut back here.
							local distance, overCeiling = math.huge, false
							for top, d in col.dx do
								local up = math.max(0, y - top)
								local here = math.sqrt(d * d + up * up)
								if here < distance then
									distance, overCeiling = here, up > d
								end
							end
							local carve = if overCeiling then CEILING_CARVE else WALL_CARVE
							local cut = (carve[1] + (carve[2] - carve[1]) * noise01(p, 10, 7)) * col.rough
							-- Inside the open space itself, none at all (a little would lift the floor).
							-- A voxel's surface shows half a voxel out from its centre's value, hence the RES / 2.
							occupancy = if distance <= 0 then 0 else math.clamp(0.5 + (distance - cut - RES / 2) / RES, 0, 1)
							material = if noise01(p, 14, 11) > 0.62 then look.wallPatch else look.wall
						end
						materials[ix][iy][iz] = material
						occupancies[ix][iy][iz] = occupancy
					end
				end
			end
			local from = Vector3.new(minX + cx * RES, minY, minZ + cz * RES)
			local region = Region3.new(from, from + Vector3.new(nx, sizeY, nz) * RES)
			workspace.Terrain:WriteVoxels(region, RES, materials, occupancies)
			task.wait()
		end
	end

	local size = whole.high - whole.low
	return { cframe = CFrame.new(whole.low + size / 2), size = size }
end

-- The voxel cells of `region` (for copying it).
local function cells(region: Region): Region3int16
	local low = (region.cframe.Position - region.size / 2) / RES
	local high = (region.cframe.Position + region.size / 2) / RES
	return Region3int16.new(
		Vector3int16.new(math.round(low.X), math.round(low.Y), math.round(low.Z)),
		Vector3int16.new(math.round(high.X) - 1, math.round(high.Y) - 1, math.round(high.Z) - 1)
	)
end

-- A copy of the terrain in `region` (a saved layout's, to paste into each run).
function DungeonTerrain.copy(region: Region): TerrainRegion
	return workspace.Terrain:CopyRegion(cells(region))
end

-- Pastes a copy with its low corner at `low` (whole voxels); returns the region it covers.
function DungeonTerrain.paste(copy: TerrainRegion, low: Vector3, size: Vector3): Region
	local corner = low / RES
	workspace.Terrain:PasteRegion(copy, Vector3int16.new(math.round(corner.X), math.round(corner.Y), math.round(corner.Z)), true)
	return { cframe = CFrame.new(low + size / 2), size = size }
end

-- Puts a run's region back to air.
function DungeonTerrain.clear(region: Region)
	workspace.Terrain:FillBlock(region.cframe, region.size, Enum.Material.Air)
end

return DungeonTerrain
