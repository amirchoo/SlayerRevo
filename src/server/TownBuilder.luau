--!strict
-- Builds the starter town at server start: a plaza with a fountain, roads, houses,
-- a guild hall, market stalls with NPCs, lamps, a wall with a north gate, and trees.
-- The town is a safe zone: enemies ignore players inside it (see isInTown).
-- Layout is centered on the world origin; the north gate (-Z) leads to the hunting grounds.
-- Houses and stalls use imported models from ServerStorage.TownAssets (synced from
-- assets/town) when present, and fall back to simple part-built versions otherwise.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local TOWN_HALF_SIZE = 70 -- the wall is a square this far from the center on each side
local PLAZA_SIZE = 50
local ROAD_WIDTH = 12
local GATE_WIDTH = 16
local WALL_HEIGHT = 10
local WALL_SEGMENT = 14

local COLORS = {
	Stone = Color3.fromRGB(150, 145, 135),
	Road = Color3.fromRGB(115, 105, 95),
	Wood = Color3.fromRGB(105, 70, 45),
	DarkWood = Color3.fromRGB(70, 45, 30),
	Plaster = Color3.fromRGB(230, 220, 195),
	Glass = Color3.fromRGB(150, 190, 210),
	Water = Color3.fromRGB(60, 130, 190),
	Leaves = Color3.fromRGB(75, 130, 60),
	Trunk = Color3.fromRGB(90, 65, 45),
	LampGlow = Color3.fromRGB(255, 200, 120),
	Metal = Color3.fromRGB(50, 50, 55),
	SignText = Color3.fromRGB(250, 235, 200),
	Skin = Color3.fromRGB(234, 184, 146),
}

-- Degrees to turn each imported model so its front door faces the road. If a building
-- faces the wrong way in-game, change its number here (try 90, 180 or -90).
local ASSET_YAW: { [string]: number } = {
	House_1 = 0,
	Houses_SecondAge_1_Level2 = 0,
	Blacksmith = 0,
}
local ASSET_SINK = 0.3 -- push models slightly into the ground so they don't float on uneven terrain

local ROOF_RED = Color3.fromRGB(150, 60, 45)
local ROOF_SLATE = Color3.fromRGB(70, 80, 110)
local ROOF_BROWN = Color3.fromRGB(110, 75, 45)

type HouseSpec = {
	position: Vector2, -- X/Z of the house center
	facing: Vector2, -- direction the front door faces
	size: Vector3, -- width, wall height, depth (depth must be <= 2 * height for the gable)
	roof: Color3,
	sign: string?,
	asset: string?, -- model in TownAssets to use instead of the part-built house
}

local HOUSES: { HouseSpec } = {
	{ position = Vector2.new(-42, -18), facing = Vector2.new(0, 1), size = Vector3.new(16, 10, 12), roof = ROOF_RED, asset = "House_1" },
	{ position = Vector2.new(-42, 18), facing = Vector2.new(0, -1), size = Vector3.new(14, 9, 12), roof = ROOF_SLATE, asset = "Houses_SecondAge_1_Level2" },
	{ position = Vector2.new(42, -18), facing = Vector2.new(0, 1), size = Vector3.new(14, 9, 12), roof = ROOF_BROWN, asset = "Houses_SecondAge_1_Level2" },
	{ position = Vector2.new(42, 18), facing = Vector2.new(0, -1), size = Vector3.new(16, 10, 12), roof = ROOF_RED, asset = "House_1" },
	{ position = Vector2.new(-20, 38), facing = Vector2.new(1, 0), size = Vector3.new(12, 9, 12), roof = ROOF_BROWN, asset = "Houses_SecondAge_1_Level2" },
	{ position = Vector2.new(20, 38), facing = Vector2.new(-1, 0), size = Vector3.new(12, 9, 12), roof = ROOF_SLATE, asset = "House_1" },
	{ position = Vector2.new(0, 58), facing = Vector2.new(0, -1), size = Vector3.new(24, 14, 16), roof = ROOF_RED, sign = "Hunters' Guild", asset = "House_1" },
}

type StallSpec = {
	position: Vector2,
	facing: Vector2,
	label: string,
	awning: Color3,
	npcShirt: Color3,
	asset: string?, -- building model in TownAssets to use instead of the stall
	assetFootprint: Vector2?, -- width/depth to fit the building into
}

local STALLS: { StallSpec } = {
	{ position = Vector2.new(-17, -38), facing = Vector2.new(1, 0), label = "Blacksmith", awning = Color3.fromRGB(160, 50, 40), npcShirt = Color3.fromRGB(60, 60, 65), asset = "Blacksmith", assetFootprint = Vector2.new(14, 12) },
	{ position = Vector2.new(17, -38), facing = Vector2.new(-1, 0), label = "Item Shop", awning = Color3.fromRGB(50, 110, 160), npcShirt = Color3.fromRGB(90, 140, 70) },
}

local TownBuilder = {}

local townFolder = Instance.new("Folder")
townFolder.Name = "Town"

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

function TownBuilder.isInTown(position: Vector3): boolean
	return math.abs(position.X) <= TOWN_HALF_SIZE and math.abs(position.Z) <= TOWN_HALF_SIZE
end

-- Creates an anchored part. `props` may include ClassName (defaults to "Part") and Parent
-- (defaults to the town folder); every other key is set as a property.
local function part(props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part") :: any
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent or townFolder
	return instance
end

-- Height of the terrain/baseplate at X/Z, ignoring anything we've built.
local function groundAt(x: number, z: number): number
	local result = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), groundParams)
	return if result then result.Position.Y else 0
end

local function groundCFrame(position: Vector2, facing: Vector2): CFrame
	local origin = Vector3.new(position.X, groundAt(position.X, position.Y), position.Y)
	return CFrame.lookAt(origin, origin + Vector3.new(facing.X, 0, facing.Y))
end

local function addSign(target: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = target

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.Fantasy
	label.TextColor3 = COLORS.SignText
	label.Parent = gui
end

-- Freestanding signpost at `cframe` (ground level), with the board facing local -Z.
local function addSignpost(cframe: CFrame, text: string, parent: Instance)
	part({ Name = "SignPost", Size = Vector3.new(0.5, 6, 0.5), CFrame = cframe * CFrame.new(0, 2.5, 0.3), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = parent })
	local board = part({ Name = "SignBoard", Size = Vector3.new(7, 1.8, 0.3), CFrame = cframe * CFrame.new(0, 5, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = parent })
	addSign(board, text)
end

-- World-aligned bounding box of every part in a model.
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

-- Clones an imported model from TownAssets and fits it to a spot: scripts stripped,
-- anchored, scaled to fit `footprint` (width along local X, depth along local Z),
-- turned by its ASSET_YAW, and resting on the ground at `base`. Returns nil if the
-- asset hasn't been added yet.
local function placeAsset(assetName: string, base: CFrame, footprint: Vector2): Model?
	local assets = ServerStorage:FindFirstChild("TownAssets")
	local template = assets and assets:FindFirstChild(assetName)
	if not template or not template:IsA("Model") then
		warn(`[TownBuilder] No model "{assetName}" in ServerStorage.TownAssets; using the part-built version`)
		return nil
	end

	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		-- Free models can hide malicious scripts; town buildings never need code.
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	-- Work around the origin first: turn, scale to fit, then move the bottom-center to the origin.
	model:PivotTo(CFrame.Angles(0, math.rad(ASSET_YAW[assetName] or 0), 0) * model:GetPivot())
	local low, high = worldBounds(model)
	local size = high - low
	model:ScaleTo(model:GetScale() * math.min(footprint.X / size.X, footprint.Y / size.Z))
	low, high = worldBounds(model)
	local bottomCenter = Vector3.new((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2)

	model:PivotTo(base * CFrame.new(0, -ASSET_SINK, 0) * CFrame.new(-bottomCenter) * model:GetPivot())
	model.Parent = townFolder
	print(`[TownBuilder] Placed {assetName} at {base.Position}, size {high - low}`)
	return model
end

-- Swaps tall decorative grass for leafy grass inside the walls so it doesn't poke through floors.
local function clearGrass(baseY: number)
	local half = TOWN_HALF_SIZE + 4
	local region = Region3.new(Vector3.new(-half, baseY - 16, -half), Vector3.new(half, baseY + 16, half)):ExpandToGrid(4)
	workspace.Terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
end

local function buildPlaza(baseY: number)
	local plazaTop = baseY + 0.4
	part({ Name = "Plaza", Size = Vector3.new(PLAZA_SIZE, 2, PLAZA_SIZE), CFrame = CFrame.new(0, plazaTop - 1, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })

	-- Fountain. Cylinders run along X, so rotate them upright.
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local function cylinder(name: string, height: number, diameter: number, y: number, color: Color3, material: Enum.Material): BasePart
		return part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(0, plazaTop + y, 0) * upright,
			Color = color,
			Material = material,
		})
	end
	cylinder("FountainBasin", 2.5, 16, 1.25, COLORS.Stone, Enum.Material.Slate)
	cylinder("FountainWater", 0.2, 14.5, 2.55, COLORS.Water, Enum.Material.Glass).Transparency = 0.2
	cylinder("FountainPillar", 6, 2, 5.5, COLORS.Stone, Enum.Material.Slate)
	cylinder("FountainBowl", 0.8, 6, 8.9, COLORS.Stone, Enum.Material.Slate)
	cylinder("FountainBowlWater", 0.2, 5, 9.35, COLORS.Water, Enum.Material.Glass).Transparency = 0.2

	part({
		ClassName = "SpawnLocation",
		Name = "TownSpawn",
		Size = Vector3.new(8, 1, 8),
		CFrame = CFrame.new(0, plazaTop - 0.4, 16),
		Color = COLORS.Stone,
		Material = Enum.Material.Slate,
		Neutral = true,
		Duration = 0, -- no spawn forcefield
	})
end

local function buildRoads(baseY: number)
	local roads = {
		{ direction = Vector3.new(0, 0, -1), length = TOWN_HALF_SIZE + 20 - PLAZA_SIZE / 2 }, -- north, out through the gate
		{ direction = Vector3.new(0, 0, 1), length = 50 - PLAZA_SIZE / 2 }, -- south, ends at the guild hall
		{ direction = Vector3.new(1, 0, 0), length = TOWN_HALF_SIZE - 10 - PLAZA_SIZE / 2 },
		{ direction = Vector3.new(-1, 0, 0), length = TOWN_HALF_SIZE - 10 - PLAZA_SIZE / 2 },
	}
	for _, road in roads do
		local center = road.direction * (PLAZA_SIZE / 2 + road.length / 2)
		local size = if road.direction.X ~= 0
			then Vector3.new(road.length, 2, ROAD_WIDTH)
			else Vector3.new(ROAD_WIDTH, 2, road.length)
		part({ Name = "Road", Size = size, CFrame = CFrame.new(center.X, baseY - 0.7, center.Z), Color = COLORS.Road, Material = Enum.Material.Cobblestone })
	end
end

local function buildHouse(spec: HouseSpec)
	local width, height, depth = spec.size.X, spec.size.Y, spec.size.Z
	local base = groundCFrame(spec.position, spec.facing) -- front faces local -Z

	local asset = spec.asset and placeAsset(spec.asset, base, Vector2.new(width, depth))
	if asset then
		asset.Name = spec.sign or "House"
		if spec.sign then
			addSignpost(base * CFrame.new(width / 2 - 2, 0, -depth / 2 - 2.5), spec.sign, asset)
		end
		return
	end

	local model = Instance.new("Model")
	model.Name = spec.sign or "House"
	model.Parent = townFolder

	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end

	piece({ Name = "Foundation", Size = Vector3.new(width + 1, 3, depth + 1), CFrame = base * CFrame.new(0, -0.5, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	piece({ Name = "Body", Size = Vector3.new(width, height + 2, depth), CFrame = base * CFrame.new(0, (height - 2) / 2, 0), Color = COLORS.Plaster, Material = Enum.Material.Plaster })

	-- Timber frame corners.
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		piece({
			Name = "Beam",
			Size = Vector3.new(1.2, height, 1.2),
			CFrame = base * CFrame.new(corner.X * width / 2, height / 2, corner.Y * depth / 2),
			Color = COLORS.DarkWood,
			Material = Enum.Material.Wood,
		})
	end

	-- 45° gable roof: two tilted slabs meeting at the ridge, plus a diamond at each end
	-- whose top half fills the triangular gable (the bottom half hides inside the walls).
	local roofRise = depth / 2
	local slabLength = roofRise * math.sqrt(2) + 1.5
	for _, side in { -1, 1 } do
		piece({
			Name = "Roof",
			Size = Vector3.new(width + 2, 0.6, slabLength),
			CFrame = base * CFrame.new(0, height + roofRise / 2, side * depth / 4) * CFrame.Angles(side * math.rad(45), 0, 0),
			Color = spec.roof,
			Material = Enum.Material.Slate,
		})
		piece({
			Name = "Gable",
			Size = Vector3.new(0.6, depth / math.sqrt(2), depth / math.sqrt(2)),
			CFrame = base * CFrame.new(side * (width / 2 - 0.35), height, 0) * CFrame.Angles(math.rad(45), 0, 0),
			Color = COLORS.Plaster,
			Material = Enum.Material.Plaster,
		})
	end

	local front = -depth / 2
	local doorHeight = math.min(7, height - 2)
	piece({ Name = "Door", Size = Vector3.new(3.5, doorHeight, 0.3), CFrame = base * CFrame.new(0, 1 + doorHeight / 2, front - 0.15), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	if width >= 14 then
		for _, side in { -1, 1 } do
			piece({ Name = "Window", Size = Vector3.new(2.6, 2.6, 0.2), CFrame = base * CFrame.new(side * width / 4, 5.5, front - 0.1), Color = COLORS.Glass, Material = Enum.Material.Glass })
		end
	end

	if spec.sign then
		local sign = piece({ Name = "Sign", Size = Vector3.new(math.min(width - 4, 14), 2.2, 0.3), CFrame = base * CFrame.new(0, height - 2, front - 0.2), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		addSign(sign, spec.sign)
	end
end

local function spawnNpc(name: string, cframe: CFrame, shirtColor: Color3)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = COLORS.Skin
	description.LeftArmColor = COLORS.Skin
	description.RightArmColor = COLORS.Skin
	description.TorsoColor = shirtColor
	description.LeftLegColor = COLORS.DarkWood
	description.RightLegColor = COLORS.DarkWood

	local ok, result = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[TownBuilder] Failed to build NPC:", result)
		return
	end

	-- No Health attribute, so NPCs can't be damaged.
	local npc = result :: Model
	npc.Name = name
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	-- `cframe` is at ground level; lift the root so the feet rest on the ground.
	npc:PivotTo(cframe * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
	npc.Parent = townFolder
end

local function buildStall(spec: StallSpec)
	local base = groundCFrame(spec.position, spec.facing) -- front faces local -Z

	local footprint = spec.assetFootprint or Vector2.new(12, 10)
	local asset = spec.asset and placeAsset(spec.asset, base, footprint)
	if asset then
		asset.Name = spec.label
		-- The shopkeeper stands out front, beside a signpost.
		local front = base * CFrame.new(0, 0, -footprint.Y / 2 - 2.5)
		addSignpost(front * CFrame.new(4, 0, 0), spec.label, asset)
		task.spawn(spawnNpc, spec.label, front, spec.npcShirt)
		return
	end

	local model = Instance.new("Model")
	model.Name = spec.label
	model.Parent = townFolder

	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end

	piece({ Name = "Counter", Size = Vector3.new(10, 3.5, 2), CFrame = base * CFrame.new(0, 1.75, -3), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		piece({ Name = "Post", Size = Vector3.new(0.8, 9, 0.8), CFrame = base * CFrame.new(corner.X * 4.6, 4.5, corner.Y * 3.6), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	-- Awning slopes down toward the front.
	piece({ Name = "Awning", Size = Vector3.new(11, 0.4, 9.5), CFrame = base * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(-10), 0, 0), Color = spec.awning, Material = Enum.Material.Fabric })

	local sign = piece({ Name = "Sign", Size = Vector3.new(8, 1.6, 0.3), CFrame = base * CFrame.new(0, 1.9, -4.15), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(sign, spec.label)

	task.spawn(spawnNpc, spec.label, base * CFrame.new(0, 0, 1.5), spec.npcShirt)
end

local function buildLamp(x: number, z: number)
	local y = groundAt(x, z)
	part({ Name = "LampPost", Size = Vector3.new(0.6, 10, 0.6), CFrame = CFrame.new(x, y + 4, z), Color = COLORS.Metal, Material = Enum.Material.Metal })
	local lantern = part({ Name = "Lantern", Size = Vector3.new(1.4, 1.6, 1.4), CFrame = CFrame.new(x, y + 9.8, z), Color = COLORS.LampGlow, Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = COLORS.LampGlow
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = lantern
end

local function buildLamps()
	local offset = ROAD_WIDTH / 2 + 1.5
	for _, along in { 30, 48, 66 } do
		buildLamp(-offset, -along) -- north road
		buildLamp(offset, -along)
	end
	for _, along in { 30, 48 } do
		buildLamp(-offset, along) -- south road
		buildLamp(offset, along)
		buildLamp(along, -offset) -- east road
		buildLamp(along, offset)
		buildLamp(-along, -offset) -- west road
		buildLamp(-along, offset)
	end
end

-- Builds a straight run of wall from `from` to `to` (Y ignored), following the ground.
local function buildWallRun(from: Vector3, to: Vector3)
	local count = math.ceil((to - from).Magnitude / WALL_SEGMENT)
	for i = 0, count - 1 do
		local a = from:Lerp(to, i / count)
		local b = from:Lerp(to, (i + 1) / count)
		local mid = (a + b) / 2
		local y = groundAt(mid.X, mid.Z) + (WALL_HEIGHT - 3) / 2 -- 3 studs buried
		part({
			Name = "Wall",
			Size = Vector3.new(1.6, WALL_HEIGHT + 3, (b - a).Magnitude),
			CFrame = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)),
			Color = COLORS.DarkWood,
			Material = Enum.Material.WoodPlanks,
		})
	end
	-- Posts at each joint. The run's end post is skipped: the next run (or a gate tower) starts there.
	for i = 0, count - 1 do
		local p = from:Lerp(to, i / count)
		local y = groundAt(p.X, p.Z) - 3 + (WALL_HEIGHT + 5) / 2
		part({ Name = "WallPost", Size = Vector3.new(2.4, WALL_HEIGHT + 5, 2.4), CFrame = CFrame.new(p.X, y, p.Z), Color = COLORS.Wood, Material = Enum.Material.Wood })
	end
end

local function buildWalls()
	local h = TOWN_HALF_SIZE
	local gate = GATE_WIDTH / 2
	buildWallRun(Vector3.new(-h, 0, -h), Vector3.new(-gate - 2, 0, -h)) -- north, west of gate
	buildWallRun(Vector3.new(gate + 2, 0, -h), Vector3.new(h, 0, -h)) -- north, east of gate
	buildWallRun(Vector3.new(h, 0, -h), Vector3.new(h, 0, h)) -- east
	buildWallRun(Vector3.new(h, 0, h), Vector3.new(-h, 0, h)) -- south
	buildWallRun(Vector3.new(-h, 0, h), Vector3.new(-h, 0, -h)) -- west

	-- Gate towers, crossbeam, and signs on both sides.
	local y = groundAt(0, -h)
	for _, side in { -1, 1 } do
		part({ Name = "GateTower", Size = Vector3.new(4, WALL_HEIGHT + 11, 4), CFrame = CFrame.new(side * (gate + 2), y + (WALL_HEIGHT + 5) / 2, -h), Color = COLORS.Wood, Material = Enum.Material.Wood })
	end
	part({ Name = "GateBeam", Size = Vector3.new(GATE_WIDTH + 8, 2, 3), CFrame = CFrame.new(0, y + WALL_HEIGHT + 5, -h), Color = COLORS.DarkWood, Material = Enum.Material.Wood })

	local signY = y + WALL_HEIGHT + 2.6
	local inward = part({ Name = "GateSign", Size = Vector3.new(GATE_WIDTH - 2, 2.4, 0.4), CFrame = CFrame.lookAt(Vector3.new(0, signY, -h + 1.3), Vector3.new(0, signY, 0)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(inward, "Hunting Grounds")
	local outward = part({ Name = "GateSign", Size = Vector3.new(GATE_WIDTH - 2, 2.4, 0.4), CFrame = CFrame.lookAt(Vector3.new(0, signY, -h - 1.3), Vector3.new(0, signY, -h - 10)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(outward, "Town - Safe Zone")
end

local function buildTree(x: number, z: number, scale: number)
	local y = groundAt(x, z)
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8 * scale, 1.8 * scale, 1.8 * scale),
		CFrame = CFrame.new(x, y + 3.5 * scale, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.Trunk,
		Material = Enum.Material.Wood,
	})
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 9 * scale,
		CFrame = CFrame.new(x, y + 9 * scale, z),
		Color = COLORS.Leaves,
		Material = Enum.Material.Grass,
	})
end

local function buildTrees()
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		buildTree(corner.X * (TOWN_HALF_SIZE - 10), corner.Y * (TOWN_HALF_SIZE - 10), 1)
	end

	-- Fixed seed so the forest looks the same every server.
	local random = Random.new(7)
	local placed = 0
	while placed < 40 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(TOWN_HALF_SIZE + 15, TOWN_HALF_SIZE + 80)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		-- Keep the path north of the gate (where enemies roam) clear.
		local onNorthPath = math.abs(x) < 35 and z < -TOWN_HALF_SIZE + 10
		local nearWall = math.max(math.abs(x), math.abs(z)) < TOWN_HALF_SIZE + 8
		if not onNorthPath and not nearWall then
			buildTree(x, z, random:NextNumber(0.8, 1.3))
			placed += 1
		end
	end
end

function TownBuilder.build()
	local include: { Instance } = { workspace.Terrain }
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(include, baseplate)
	end
	groundParams.FilterDescendantsInstances = include

	local baseY = groundAt(0, 0)

	-- Once the town has been pasted into the place and edited in Studio, keep it as-is.
	if workspace:FindFirstChild("Town") then
		clearGrass(baseY)
		return
	end

	clearGrass(baseY)
	buildPlaza(baseY)
	buildRoads(baseY)
	for _, house in HOUSES do
		buildHouse(house)
	end
	for _, stall in STALLS do
		buildStall(stall)
	end
	buildLamps()
	buildWalls()
	buildTrees()

	townFolder.Parent = workspace
end

return TownBuilder
