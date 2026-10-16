--!strict
-- A dungeon's grid map (DungeonConfig Map) placed in the world for one run: what each square
-- is, where it is, and the way through it for orcs (route: around walls, through open gates,
-- never through fake walls). Squares are numbered (row - 1) * cols + column; row 1 is the
-- north (-Z) edge and the map's middle sits on the run's origin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonConfig = require(ReplicatedStorage.Shared.Config.DungeonConfig)

export type Grid = {
	cols: number,
	rows: number,
	cell: number,
	origin: Vector3,
	chars: { string }, -- by square
	cave: { boolean }, -- by square: cave floor, or rock that borders more cave than stone
	gateOf: { [number]: { isOpen: boolean } }, -- the '+' squares' gates (DungeonBuilder fills it)
}

local DungeonGrid = {}

local LINE_STEP = 1 / 3 -- of a square, between the samples of clearLine
local LINE_HALF_WIDTH = 1.3 -- studs either side of a line that must be clear too (an orc's width)
local ROUTE_LOOKAHEAD = 12 -- squares along the way that route looks for a straight line to

local DIRECTIONS = { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) }
DungeonGrid.Directions = DIRECTIONS

function DungeonGrid.index(grid: Grid, c: number, r: number): number?
	if c < 1 or r < 1 or c > grid.cols or r > grid.rows then
		return nil
	end
	return (r - 1) * grid.cols + c
end

function DungeonGrid.square(grid: Grid, i: number): (number, number)
	return (i - 1) % grid.cols + 1, (i - 1) // grid.cols + 1
end

-- The character at a square ('#' off the map).
function DungeonGrid.char(grid: Grid, c: number, r: number): string
	local i = DungeonGrid.index(grid, c, r)
	return if i then grid.chars[i] else "#"
end

function DungeonGrid.isRock(char: string): boolean
	return char == "#"
end

-- Somewhere a player can stand (fake walls included).
function DungeonGrid.isFloor(char: string): boolean
	return char ~= "#"
end

-- The middle of a square, on the floor.
function DungeonGrid.position(grid: Grid, c: number, r: number): Vector3
	return grid.origin + Vector3.new((c - (grid.cols + 1) / 2) * grid.cell, 0, (r - (grid.rows + 1) / 2) * grid.cell)
end

-- The square under a point.
function DungeonGrid.squareAt(grid: Grid, position: Vector3): (number, number)
	local offset = position - grid.origin
	return math.floor(offset.X / grid.cell + grid.cols / 2) + 1, math.floor(offset.Z / grid.cell + grid.rows / 2) + 1
end

-- Every square holding `char`.
function DungeonGrid.find(grid: Grid, char: string): { Vector2 }
	local found = {}
	for i, ch in grid.chars do
		if ch == char then
			local c, r = DungeonGrid.square(grid, i)
			table.insert(found, Vector2.new(c, r))
		end
	end
	return found
end

-- Whether an orc can walk through a square: floor, not a fake wall, not a shut gate.
function DungeonGrid.passable(grid: Grid, c: number, r: number): boolean
	local i = DungeonGrid.index(grid, c, r)
	if not i then
		return false
	end
	local char = grid.chars[i]
	if char == "#" or char == "?" then
		return false
	end
	local gate = grid.gateOf[i]
	return not gate or gate.isOpen
end

function DungeonGrid.new(dungeon: DungeonConfig.Dungeon, origin: Vector3): Grid
	local rows = #dungeon.Map
	local cols = 0
	for _, line in dungeon.Map do
		cols = math.max(cols, #line)
	end
	local grid: Grid = { cols = cols, rows = rows, cell = dungeon.Cell, origin = origin, chars = {}, cave = {}, gateOf = {} }
	for r, line in dungeon.Map do
		for c = 1, cols do
			grid.chars[(r - 1) * cols + c] = if c <= #line then string.sub(line, c, c) else "#"
		end
	end
	-- Which squares are cave: cave floor (',' and the markers beside it, but not beside stone
	-- floor), the fake walls set in cave rock, and rock bordering more cave than stone.
	local function base(c: number, r: number): string
		local char = DungeonGrid.char(grid, c, r)
		return if char == "." or char == "," or char == "#" then char else ""
	end
	local floorCave: { boolean } = {}
	for i, char in grid.chars do
		local c, r = DungeonGrid.square(grid, i)
		if char == "," then
			floorCave[i] = true
		elseif char ~= "." and char ~= "#" then
			local stone, cave = false, false
			for _, d in DIRECTIONS do
				local b = base(c + d.X, r + d.Y)
				stone = stone or b == "."
				cave = cave or b == ","
			end
			floorCave[i] = cave and (char == "?" or not stone)
		else
			floorCave[i] = false
		end
	end
	for i, char in grid.chars do
		if char == "#" then
			local c, r = DungeonGrid.square(grid, i)
			local cave, stone = 0, 0
			for dr = -1, 1 do
				for dc = -1, 1 do
					local j = DungeonGrid.index(grid, c + dc, r + dr)
					if j and grid.chars[j] ~= "#" then
						if floorCave[j] then
							cave += 1
						else
							stone += 1
						end
					end
				end
			end
			grid.cave[i] = cave > stone
		else
			grid.cave[i] = floorCave[i]
		end
	end
	return grid
end

-- Whether an orc could walk straight from `a` to `b` (on the flat), with its width clear.
function DungeonGrid.clearLine(grid: Grid, a: Vector3, b: Vector3): boolean
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = delta.Magnitude
	local direction = if length > 0.01 then delta / length else Vector3.xAxis
	local side = Vector3.new(-direction.Z, 0, direction.X) * LINE_HALF_WIDTH
	local step = grid.cell * LINE_STEP
	local t = 0
	while true do
		local p = a + direction * math.min(t, length)
		for _, offset in { Vector3.zero, side, -side } do
			if not DungeonGrid.passable(grid, DungeonGrid.squareAt(grid, p + offset)) then
				return false
			end
		end
		if t >= length then
			return true
		end
		t += step
	end
end

-- A passable square at or next to the one under `position` (it may stand on a square's edge).
local function nearestPassable(grid: Grid, position: Vector3): number?
	local c, r = DungeonGrid.squareAt(grid, position)
	if DungeonGrid.passable(grid, c, r) then
		return DungeonGrid.index(grid, c, r)
	end
	local best, bestDistance = nil, math.huge
	for dr = -1, 1 do
		for dc = -1, 1 do
			if DungeonGrid.passable(grid, c + dc, r + dr) then
				local distance = (DungeonGrid.position(grid, c + dc, r + dr) - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = DungeonGrid.index(grid, c + dc, r + dr), distance
				end
			end
		end
	end
	return best
end

-- Where an orc at `from` should walk next on its way to `to`: `to` itself if it's in a
-- straight line, else the farthest square along the shortest way it can walk straight to.
-- Nil if there's no way (behind a shut gate, or off the map).
function DungeonGrid.route(grid: Grid, from: Vector3, to: Vector3): Vector3?
	local start, target = nearestPassable(grid, from), nearestPassable(grid, to)
	if not start or not target then
		return nil
	end
	if DungeonGrid.clearLine(grid, from, to) then
		return to
	end
	-- Breadth-first from the target, so each square knows its next step toward it.
	local toward: { [number]: number } = { [target] = target }
	local queue = { target }
	local head = 1
	while head <= #queue and not toward[start] do
		local i = queue[head]
		head += 1
		local c, r = DungeonGrid.square(grid, i)
		for _, d in DIRECTIONS do
			local j = DungeonGrid.index(grid, c + d.X, r + d.Y)
			if j and not toward[j] and DungeonGrid.passable(grid, c + d.X, r + d.Y) then
				toward[j] = i
				table.insert(queue, j)
			end
		end
	end
	if not toward[start] then
		return nil
	end
	local function at(i: number): Vector3
		local c, r = DungeonGrid.square(grid, i)
		local p = DungeonGrid.position(grid, c, r)
		return Vector3.new(p.X, from.Y, p.Z)
	end
	local i = toward[start]
	local aim = at(i)
	for _ = 1, ROUTE_LOOKAHEAD do
		if i == target then
			break
		end
		i = toward[i]
		local p = at(i)
		if not DungeonGrid.clearLine(grid, from, p) then
			break
		end
		aim = p
	end
	return aim
end

return DungeonGrid
