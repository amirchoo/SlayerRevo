--!strict
-- Dresses the land around the hub (sculpted by WorldTerrain) at server start, from
-- shared/Config/WorldConfig: the forest (the Tree model, in assorted sizes and leaf colors),
-- undergrowth, the ruins in each clearing, treasure chests, and bridges where paths cross
-- the river. Models come from ServerStorage.WorldAssets (assets/world) and the Tree from
-- TownAssets. Everything is seeded, so every server's world looks the same.
-- Treasure chests are tagged "TreasureChest" (CollectionService) for when they get loot;
-- for now they're scenery.
-- The code is the source of truth: a "World" saved into the place is replaced at start.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local WorldMap = require(ReplicatedStorage.Shared.WorldMap)

-- Degrees to turn a model so its front faces local -Z (see TownBuilder's ASSET_YAW).
local ASSET_YAW: { [string]: number } = {
	WoodenBridge = 90, -- the bridge spans the model's X
}

-- Mesh tints (SpecialMesh.VertexColor) for models whose color comes from a mesh texture.
local MESH_TINT: { [string]: Vector3 } = {
	TallGrass = Vector3.new(0.55, 0.78, 0.42), -- the model's own tint is a neon green
}

-- Ruins are darkened by this much (stone only, not their ivy), so they read as old stone.
local SHADE: { [string]: number } = {
	RuinArch = 0.82,
	RuinWall = 0.85,
	RuinPillars = 0.85,
}

local LEAF_COLORS = {
	Color3.fromRGB(75, 130, 60),
	Color3.fromRGB(60, 115, 50),
	Color3.fromRGB(90, 145, 65),
	Color3.fromRGB(105, 150, 60),
	Color3.fromRGB(70, 120, 75),
}
local AUTUMN_COLORS = {
	Color3.fromRGB(205, 125, 50),
	Color3.fromRGB(215, 165, 60),
	Color3.fromRGB(180, 85, 50),
}
-- Ground a tree or plant can't stand on.
local BARE: { [Enum.Material]: boolean } = {
	[Enum.Material.Rock] = true,
	[Enum.Material.Slate] = true,
	[Enum.Material.Snow] = true,
	[Enum.Material.Water] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Ground] = true,
}
local YIELD_EVERY = 40 -- placements between yields, so building never freezes the server

local WorldBuilder = {}

local worldFolder: Folder
local placedSinceYield = 0
local missing: { [string]: boolean } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function ground(p: Vector2): RaycastResult?
	return workspace:Raycast(Vector3.new(p.X, 400, p.Y), Vector3.new(0, -800, 0), groundParams)
end

local function template(name: string): Model?
	for _, folderName in { "WorldAssets", "TownAssets" } do
		local folder = ServerStorage:FindFirstChild(folderName)
		local found = folder and folder:FindFirstChild(name)
		if found and found:IsA("Model") then
			return found
		end
	end
	missing[name] = true
	return nil
end

local function worldBounds(model: Model): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local half = descendant.Size / 2
			for _, corner in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1) } do
				for _, sign in { 1, -1 } do
					local point = descendant.CFrame * (half * corner * sign)
					low, high = low:Min(point), high:Max(point)
				end
			end
		end
	end
	return low, high
end

-- Clones model `name`, scales it, turns it by its ASSET_YAW, and stands its bottom-center on
-- `base` (whose -Z is the model's front), a little sunk so it never floats on a slope.
local function place(name: string, base: CFrame, scale: number, sink: number?): Model?
	local source = template(name)
	if not source then
		return nil
	end
	local model = source:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			local color = descendant.Color
			if SHADE[name] and not (color.G > color.R * 1.15 and color.G > color.B * 1.15) then
				descendant.Color = Color3.new(color.R * SHADE[name], color.G * SHADE[name], color.B * SHADE[name])
			end
		elseif descendant:IsA("SpecialMesh") and MESH_TINT[name] then
			descendant.VertexColor = MESH_TINT[name]
		end
	end
	model:PivotTo(CFrame.Angles(0, math.rad(ASSET_YAW[name] or 0), 0) * model:GetPivot())
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	local low, high = worldBounds(model)
	local bottomCenter = Vector3.new((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2)
	model:PivotTo(base * CFrame.new(0, -(sink or 0.3), 0) * CFrame.new(-bottomCenter) * model:GetPivot())
	model.Parent = worldFolder

	placedSinceYield += 1
	if placedSinceYield >= YIELD_EVERY then
		placedSinceYield = 0
		task.wait()
	end
	return model
end

-- A ground CFrame at `p` facing `facing` (or a random way), or nil where nothing should grow.
local function spot(p: Vector2, random: Random, facing: Vector2?, allowBare: boolean?): CFrame?
	local hit = ground(p)
	if not hit or (not allowBare and BARE[hit.Material]) then
		return nil
	end
	local angle = random:NextNumber(0, math.pi * 2)
	local look = if facing then Vector3.new(facing.X, 0, facing.Y) else Vector3.new(math.sin(angle), 0, math.cos(angle))
	return CFrame.lookAt(hit.Position, hit.Position + look)
end

local function free(p: Vector2, margin: number): boolean
	return WorldMap.distanceTo(p, WorldMap.PathSegments) > WorldConfig.PathWidth / 2 + margin
		and WorldMap.riverDistance(p) > margin
		and not WorldMap.clearingAt(p, margin)
end

local function recolor(model: Model, partName: string, color: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == partName then
			descendant.Color = color
		end
	end
end

local function undergrowthNear(at: Vector2, random: Random)
	for _, plant in WorldConfig.Undergrowth do
		if plant.PerTree and random:NextNumber() < plant.PerTree then
			local angle, distance = random:NextNumber(0, math.pi * 2), random:NextNumber(5, 12)
			local p = at + Vector2.new(math.cos(angle), math.sin(angle)) * distance
			local base = free(p, 3) and spot(p, random)
			if base then
				place(plant.Model, base, random:NextNumber(plant.Scale[1], plant.Scale[2]))
			end
		end
	end
end

local function buildForest(random: Random)
	local trees = WorldConfig.Trees
	local half = WorldConfig.HalfSize
	local maxY = WorldConfig.GroundY + trees.MaxHeight
	local x = -half
	while x < half do
		local z = -half
		while z < half do
			local p = Vector2.new(x + random:NextNumber(0, trees.Cell), z + random:NextNumber(0, trees.Cell))
			local plain = WorldMap.plainWeight(p) > 0.5
			local chance = if plain then trees.PlainChance else trees.ForestChance
			-- Inside the town fence (and just past it) the town places its own trees.
			if random:NextNumber() < chance and WorldMap.squareDistance(p) > 152 and free(p, 6) then
				local base = spot(p, random)
				if base and base.Position.Y < maxY then
					local tree = place("Tree", base, random:NextNumber(trees.Scale[1], trees.Scale[2]))
					if tree then
						local autumn = random:NextNumber() < trees.AutumnChance
						local palette = if autumn then AUTUMN_COLORS else LEAF_COLORS
						recolor(tree, "Leaves", palette[random:NextInteger(1, #palette)])
					end
					if not plain then
						undergrowthNear(p, random)
					end
				end
			end
			z += trees.Cell
		end
		x += trees.Cell
	end
end

local function buildMeadows(random: Random)
	local area = WorldConfig.HuntingGrounds
	for _, plant in WorldConfig.Undergrowth do
		if plant.Plain then
			local placed, tries = 0, 0
			while placed < plant.Plain and tries < plant.Plain * 10 do
				tries += 1
				local p = Vector2.new(random:NextNumber(area.Min.X, area.Max.X), random:NextNumber(area.Min.Y, area.Max.Y))
				local base = WorldMap.plainWeight(p) > 0.6 and free(p, 3) and spot(p, random)
				if base then
					place(plant.Model, base, random:NextNumber(plant.Scale[1], plant.Scale[2]))
					placed += 1
				end
			end
		end
	end
end

local function buildClearings(random: Random)
	for _, clearing in WorldConfig.Clearings do
		if clearing.Ruin then
			local base = spot(clearing.Position, random, clearing.RuinFacing, true)
			if base then
				place(clearing.Ruin, base, clearing.RuinScale or 1, 0.6)
			end
		end
		for _, offset in clearing.Chests or {} do
			local p = clearing.Position + offset
			-- Facing out of the ruin, toward whoever walks up (or a random way in a bare spot).
			local facing = if offset.Magnitude > 1 then offset.Unit else nil
			local base = spot(p, random, facing, true)
			local chest = base and place("TreasureChest", base, WorldConfig.ChestScale)
			if chest then
				chest.Name = "TreasureChest"
				chest:SetAttribute("Spot", clearing.Name)
				CollectionService:AddTag(chest, "TreasureChest")
			end
		end
	end
end

-- Where segment a1-a2 crosses b1-b2, if it does.
local function crossing(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2): Vector2?
	local r, s = a2 - a1, b2 - b1
	local denominator = r.X * s.Y - r.Y * s.X
	if math.abs(denominator) < 1e-6 then
		return nil
	end
	local t = ((b1.X - a1.X) * s.Y - (b1.Y - a1.Y) * s.X) / denominator
	local u = ((b1.X - a1.X) * r.Y - (b1.Y - a1.Y) * r.X) / denominator
	if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
		return a1 + r * t
	end
	return nil
end

local function buildBridges()
	local built: { Vector2 } = {}
	for _, path in WorldMap.PathSegments do
		for _, river in WorldMap.RiverSegments do
			local at = crossing(path.A, path.B, river.A, river.B)
			-- A path crossing right at a bend in the path or river shows up more than once.
			for _, other in built do
				if at and (at - other).Magnitude < 30 then
					at = nil
				end
			end
			if at then
				table.insert(built, at)
				local along = (path.B - path.A).Unit
				-- Rest the bridge's ends on the banks: the higher of the ground either side.
				local bankY = -math.huge
				for _, side in { -1, 1 } do
					local hit = ground(at + along * side * (WorldConfig.River.Width / 2 + 6))
					if hit then
						bankY = math.max(bankY, hit.Position.Y)
					end
				end
				if bankY > -math.huge then
					local center = Vector3.new(at.X, bankY, at.Y)
					place("WoodenBridge", CFrame.lookAt(center, center + Vector3.new(along.X, 0, along.Y)), 1.4, 0.4)
				end
			end
		end
	end
end

-- Builds the forest, ruins and plain dressing into workspace.World. A World already saved in
-- the place is kept as it is (so hand edits made in Studio's edit mode stay), unless `replace`
-- is true: tools/generate_terrain.lua rebuilds it from WorldConfig.
function WorldBuilder.build(replace: boolean?)
	if not replace and workspace:FindFirstChild("World") then
		return
	end
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local saved = workspace:FindFirstChild("World")
	if saved then
		saved:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace

	local random = Random.new(WorldConfig.Seed)
	buildClearings(random)
	buildBridges()
	buildForest(random)
	buildMeadows(random)

	local names: { string } = {}
	for name in missing do
		table.insert(names, name)
	end
	if #names > 0 then
		table.sort(names)
		warn(`[WorldBuilder] Missing from WorldAssets/TownAssets: {table.concat(names, ", ")}`)
	end
end

return WorldBuilder
