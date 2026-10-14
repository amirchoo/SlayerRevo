--!strict
-- Builds Beginning Town (the hub) at server start, from shared/Config/TownConfig: a cobblestone
-- plaza with the knight statue and the spawn, roads out to the buildings, shops and homes,
-- landmarks (bell tower, watchtowers, windmill), props and decor, lamps, a low fence ring with
-- an arch at the north road to the hunting grounds, and trees.
-- Things the client brings to life are marked with attributes: "Sway" (radians) on cloth that
-- sways in the wind, "Spin" (radians per second) on the windmill's sails, "Bell" on the bell;
-- chimneys get a smoke emitter. Lamps and windows light up at night (client DayCycle).
-- The town sits inside the hub safe zone (shared/SafeZone); its edge isn't marked in the world.
-- Buildings with an Asset use that model from ServerStorage.TownAssets (synced from
-- assets/town) when it exists, fitted to the building's footprint and recolored with its
-- Walls/Roof; otherwise they're built from parts. Lamps and trees use the LampPost and Tree
-- models the same way. Townsfolk are spawned separately (NpcService).
-- The code is the source of truth: a "Town" saved into the place is replaced at start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)

type Building = TownConfig.Building
type Prop = TownConfig.Prop

local FENCE_HEIGHT = 3.2
local FENCE_POST_SPACING = 8

local COLORS = {
	Stone = Color3.fromRGB(150, 145, 135),
	DarkStone = Color3.fromRGB(110, 105, 100),
	Road = Color3.fromRGB(115, 105, 95),
	Dirt = Color3.fromRGB(120, 95, 65),
	Wood = Color3.fromRGB(105, 70, 45),
	DarkWood = Color3.fromRGB(70, 45, 30),
	LightWood = Color3.fromRGB(160, 120, 80),
	Plaster = Color3.fromRGB(230, 220, 195),
	Glass = Color3.fromRGB(150, 190, 210),
	Water = Color3.fromRGB(60, 130, 190),
	Leaves = Color3.fromRGB(75, 130, 60),
	DarkLeaves = Color3.fromRGB(55, 105, 50),
	Trunk = Color3.fromRGB(90, 65, 45),
	LampGlow = Color3.fromRGB(255, 200, 120),
	Ember = Color3.fromRGB(255, 120, 40),
	Metal = Color3.fromRGB(50, 50, 55),
	Iron = Color3.fromRGB(90, 92, 98),
	SignText = Color3.fromRGB(250, 235, 200),
	Hay = Color3.fromRGB(215, 185, 100),
	Paper = Color3.fromRGB(235, 225, 195),
	Banner = Color3.fromRGB(70, 100, 60),
	Flowers = { Color3.fromRGB(220, 80, 90), Color3.fromRGB(240, 200, 70), Color3.fromRGB(150, 110, 220), Color3.fromRGB(245, 245, 240) },
}

-- Degrees to turn each imported model so its front door faces the road. If a building
-- faces the wrong way in-game, change its number here (try 90, 180 or -90).
local ASSET_YAW: { [string]: number } = {
	House_1 = 0,
	Houses_SecondAge_1_Level2 = 0,
	Blacksmith = 0,
	FantasyInn = 0, -- the Hunters' Guild
	CookingFire = 0,
	BellTower = 0,
	Watchtower = 0,
	Windmill = 0,
	LampPost = 90, -- the lantern hangs off the model's +X side; this turns it to the front
	Tree = 0,
	FarmFence = 90, -- a fence section runs along the model's X; this lines it up with the run
	ArcheryTarget = -90, -- the target's face points along the model's -X
	WeaponRack = 90,
	ItemBox = 180,
	StonePath = 90, -- the path runs along the model's X
	NoticeBoard = 180,
}
-- Props made from a TownAssets model (when it's there; otherwise part-built, if they can be).
local PROP_MODELS: { [string]: string } = {
	well = "Well",
	cart = "HayCart",
	questboard = "NoticeBoard",
	dummy = "TrainingDummy",
	target = "ArcheryTarget",
	rack = "WeaponRack",
	campfire = "CookingFire", -- saved already scaled to size
	table = "PicnicTable",
	itembox = "ItemBox",
	stable = "Stable",
	supplies = "SupplyPile",
	tent = "MarketStall",
}
-- Which parts of an imported building model take the building's Walls and Roof colors.
local ASSET_TINT: { [string]: { Walls: { string }, Roof: { string } } } = {
	House_1 = { Walls = { "Plaster" }, Roof = { "RoofTiles" } },
}
local TREE_SCALE = 0.5 -- the Tree model is ~38 studs tall; town trees are about half that
local ASSET_SINK = 0.3 -- push models slightly into the ground so they don't float on uneven terrain
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local CLOTH_SWAY = math.rad(9) -- how far flags and washing swing in the wind
-- Per-model ASSET_SINK overrides: thin models would vanish under it (the StonePath is ~0.23
-- studs thick), so the path sits a hair above the ground instead (negative = raised).
local ASSET_SINK_BY: { [string]: number } = {
	StonePath = -0.05,
	CookingFire = 1, -- its ring of stones reaches a stud below the dirt patch it sits on
}

local TownBuilder = {}

local townFolder: Folder = Instance.new("Folder")
townFolder.Name = "Town"

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

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

-- A ground-level CFrame at X/Z whose front (local -Z) points along `facing`.
local function groundCFrame(position: Vector2, facing: Vector2?): CFrame
	local origin = Vector3.new(position.X, groundAt(position.X, position.Y), position.Y)
	local look = if facing and facing.Magnitude > 0.01 then Vector3.new(facing.X, 0, facing.Y) else Vector3.new(0, 0, -1)
	return CFrame.lookAt(origin, origin + look)
end

local function addSign(target: BasePart, text: string, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
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
local function addSignpost(cframe: CFrame, text: string, parent: Instance, width: number?)
	part({ Name = "SignPost", Size = Vector3.new(0.5, 6, 0.5), CFrame = cframe * CFrame.new(0, 2.5, 0.3), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = parent })
	local board = part({ Name = "SignBoard", Size = Vector3.new(width or 7, 1.8, 0.3), CFrame = cframe * CFrame.new(0, 5, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = parent })
	addSign(board, text)
end

local function addLight(target: BasePart, range: number, brightness: number?, color: Color3?)
	local light = Instance.new("PointLight")
	light.Color = color or COLORS.LampGlow
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Parent = target
end

-- A gentle plume of chimney smoke rising from `position`.
local function addSmoke(position: Vector3, parent: Instance)
	local vent = part({ Name = "ChimneySmoke", Size = Vector3.new(1, 0.2, 1), CFrame = CFrame.new(position), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = parent })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 195, 190))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
	smoke.Lifetime = NumberRange.new(5, 7)
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Acceleration = Vector3.new(1.2, 0.4, 0.6) -- drifts off with the breeze
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-15, 15)
	smoke.LightInfluence = 1
	smoke.Parent = vent
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

local missingAssets: { [string]: boolean } = {}

-- Clones an imported model from TownAssets and fits it to a spot: scripts stripped,
-- anchored, scaled to fit `footprint` (width along local X, depth along local Z) or by
-- `scale`, turned by its ASSET_YAW, and resting on the ground at `base`. Returns nil if the
-- asset hasn't been added yet (the caller builds it from parts).
local function template(assetName: string): Model?
	local assets = ServerStorage:FindFirstChild("TownAssets")
	local found = assets and assets:FindFirstChild(assetName)
	if found and found:IsA("Model") then
		return found
	end
	missingAssets[assetName] = true
	return nil
end

local function placeAsset(assetName: string, base: CFrame, footprint: Vector2?, scale: number?): Model?
	local source = template(assetName)
	if not source then
		return nil
	end

	local model = source:Clone()
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
	local factor = if footprint then math.min(footprint.X / size.X, footprint.Y / size.Z) else scale or 1
	if factor ~= 1 then
		model:ScaleTo(model:GetScale() * factor)
	end
	low, high = worldBounds(model)
	local bottomCenter = Vector3.new((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2)

	model:PivotTo(base * CFrame.new(0, -(ASSET_SINK_BY[assetName] or ASSET_SINK), 0) * CFrame.new(-bottomCenter) * model:GetPivot())
	model.Parent = townFolder
	return model
end

-- Swaps tall decorative grass for leafy grass inside the fence so it doesn't poke through floors.
local function clearGrass(baseY: number)
	local half = TownConfig.EdgeHalfSize + 4
	local region = Region3.new(Vector3.new(-half, baseY - 16, -half), Vector3.new(half, baseY + 16, half)):ExpandToGrid(4)
	workspace.Terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
end

-- Plaza -----------------------------------------------------------------------------------

local function cylinder(name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance?): BasePart
	-- Cylinders run along X; `cframe` is for an upright one.
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

local function buildPlaza(baseY: number)
	local size = TownConfig.PlazaSize
	local plazaTop = baseY + 0.4
	part({ Name = "Plaza", Size = Vector3.new(size, 2, size), CFrame = CFrame.new(0, plazaTop - 1, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	-- A darker stone rim around the plaza.
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local rimSize = if side.X ~= 0 then Vector3.new(1.2, 2.2, size + 1.2) else Vector3.new(size + 1.2, 2.2, 1.2)
		part({ Name = "PlazaRim", Size = rimSize, CFrame = CFrame.new(side * size / 2 + Vector3.new(0, plazaTop - 0.95, 0)), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	end

	-- The knight statue in the middle, facing the spawn.
	local statue = TownConfig.PlazaStatue
	local facing = Vector3.new(statue.Facing.X, 0, statue.Facing.Y)
	placeAsset(statue.Asset, CFrame.lookAt(Vector3.new(0, plazaTop, 0), Vector3.new(0, plazaTop, 0) + facing), nil, statue.Scale)

	part({
		ClassName = "SpawnLocation",
		Name = "TownSpawn",
		Size = Vector3.new(8, 1, 8),
		CFrame = CFrame.new(TownConfig.Spawn.X, plazaTop - 0.4, TownConfig.Spawn.Y),
		Color = COLORS.Stone,
		Material = Enum.Material.Slate,
		Neutral = true,
		Duration = 0, -- no spawn forcefield
	})
end

-- Roads -------------------------------------------------------------------------------------

local function buildPath(from: Vector2, to: Vector2, width: number, color: Color3, material: Enum.Material, name: string)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local y = groundAt(mid.X, mid.Y)
	local a = Vector3.new(from.X, y - 0.7, from.Y)
	local b = Vector3.new(to.X, y - 0.7, to.Y)
	part({ Name = name, Size = Vector3.new(width, 2, length), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Material = material })
end

-- Roads are laid with the StonePath model (scaled to the road's width, pieces overlapping
-- to fill its length), or as cobblestone slabs without it. The trail past the arch is a dirt
-- path in the terrain (WorldTerrain).
local function buildRoads()
	local stones = template("StonePath")
	for _, road in TownConfig.Roads do
		if stones then
			local low, high = worldBounds(stones)
			local scale = TownConfig.RoadWidth / (high.Z - low.Z)
			local pieceLength = (high.X - low.X) * scale
			local length = (road.To - road.From).Magnitude
			local direction = (road.To - road.From).Unit
			local pieces = math.max(1, math.ceil(length / pieceLength))
			for i = 1, pieces do
				local center = road.From + direction * (pieceLength / 2 + (length - pieceLength) * (if pieces > 1 then (i - 1) / (pieces - 1) else 0.5))
				placeAsset("StonePath", groundCFrame(center, direction), nil, scale)
			end
		else
			buildPath(road.From, road.To, TownConfig.RoadWidth, COLORS.Road, Enum.Material.Cobblestone, "Road")
		end
	end
end

-- Lamps both sides of every road, every LampSpacing studs, lanterns hanging toward the road.
local function buildLamp(x: number, z: number, toward: Vector2)
	local lamp = placeAsset("LampPost", groundCFrame(Vector2.new(x, z), toward), nil, 1)
	if lamp then
		for _, descendant in lamp:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Material == Enum.Material.Neon then
				addLight(descendant, 18)
			end
		end
		return
	end
	local y = groundAt(x, z)
	part({ Name = "LampPost", Size = Vector3.new(0.6, 10, 0.6), CFrame = CFrame.new(x, y + 4, z), Color = COLORS.Metal, Material = Enum.Material.Metal })
	part({ Name = "LampArm", Size = Vector3.new(0.4, 0.4, 1.6), CFrame = CFrame.new(x, y + 8.8, z), Color = COLORS.Metal, Material = Enum.Material.Metal })
	local lantern = part({ Name = "Lantern", Size = Vector3.new(1.4, 1.6, 1.4), CFrame = CFrame.new(x, y + 9.8, z), Color = COLORS.LampGlow, Material = Enum.Material.Neon })
	addLight(lantern, 18)
end

local function buildLamps()
	local offset = TownConfig.RoadWidth / 2 + 1.5
	for _, road in TownConfig.Roads do
		local along = road.To - road.From
		local length = along.Magnitude
		local direction = along.Unit
		local side = Vector2.new(-direction.Y, direction.X)
		local distance = 6
		while distance < length - 2 do
			for _, s in { -1, 1 } do
				local point = road.From + direction * distance + side * offset * s
				buildLamp(point.X, point.Y, -side * s)
			end
			distance += TownConfig.LampSpacing
		end
	end
end

-- Buildings ---------------------------------------------------------------------------------

-- A timber-framed house (1 or 2 stories) with a gable roof, door, windows, and optional
-- chimney and sign. Front faces local -Z of `base`.
local function buildHouseParts(spec: Building, base: CFrame, model: Model)
	local width, storyHeight, depth = spec.Size.X, spec.Size.Y, spec.Size.Z
	local stories = spec.Stories or 1
	local height = storyHeight * stories
	local walls = spec.Walls or COLORS.Plaster
	local roof = spec.Roof or COLORS.DarkWood
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end

	piece({ Name = "Foundation", Size = Vector3.new(width + 1, 3, depth + 1), CFrame = base * CFrame.new(0, -0.5, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	piece({ Name = "Body", Size = Vector3.new(width, height + 2, depth), CFrame = base * CFrame.new(0, (height - 2) / 2, 0), Color = walls, Material = Enum.Material.Plaster })

	-- Timber frame: corner posts, and a beam between stories.
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		piece({ Name = "Beam", Size = Vector3.new(1.2, height, 1.2), CFrame = base * CFrame.new(corner.X * width / 2, height / 2, corner.Y * depth / 2), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	for story = 1, stories - 1 do
		local y = storyHeight * story
		piece({ Name = "FloorBeam", Size = Vector3.new(width + 0.6, 0.9, depth + 0.6), CFrame = base * CFrame.new(0, y, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
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
			Color = roof,
			Material = Enum.Material.Slate,
		})
		piece({
			Name = "Gable",
			Size = Vector3.new(0.6, depth / math.sqrt(2), depth / math.sqrt(2)),
			CFrame = base * CFrame.new(side * (width / 2 - 0.35), height, 0) * CFrame.Angles(math.rad(45), 0, 0),
			Color = walls,
			Material = Enum.Material.Plaster,
		})
	end
	piece({ Name = "Ridge", Size = Vector3.new(width + 2.2, 0.8, 0.8), CFrame = base * CFrame.new(0, height + roofRise + 0.1, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })

	if spec.Chimney then
		piece({ Name = "Chimney", Size = Vector3.new(2.2, roofRise + 4, 2.2), CFrame = base * CFrame.new(width / 2 - 3, height + roofRise / 2 + 1.5, depth / 4), Color = COLORS.DarkStone, Material = Enum.Material.Brick })
	end

	local front = -depth / 2
	local doorHeight = math.min(7, storyHeight - 1.5)
	piece({ Name = "Door", Size = Vector3.new(3.5, doorHeight, 0.3), CFrame = base * CFrame.new(0, 1 + doorHeight / 2, front - 0.15), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	piece({ Name = "DoorFrame", Size = Vector3.new(4.5, 0.6, 0.4), CFrame = base * CFrame.new(0, 1.3 + doorHeight, front - 0.2), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	-- Windows: either side of the door on the ground floor, and across each upper floor.
	for story = 1, stories do
		local y = storyHeight * (story - 1) + math.min(5.5, storyHeight - 2.5)
		local columns = if story == 1 then { -1, 1 } else { -1.5, -0.5, 0.5, 1.5 }
		if width >= 13 or story > 1 then
			for _, column in columns do
				local x = if story == 1 then column * width / 4 else column * width / 4.5
				piece({ Name = "Window", Size = Vector3.new(2.4, 2.4, 0.2), CFrame = base * CFrame.new(x, y, front - 0.1), Color = COLORS.Glass, Material = Enum.Material.Glass })
				piece({ Name = "WindowSill", Size = Vector3.new(3, 0.3, 0.6), CFrame = base * CFrame.new(x, y - 1.35, front - 0.3), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
			end
		end
	end

	if spec.Sign then
		local sign = piece({ Name = "Sign", Size = Vector3.new(math.min(width - 4, 16), 2.2, 0.3), CFrame = base * CFrame.new(0, math.min(storyHeight, 9) - 0.6, front - 0.25), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		addSign(sign, spec.Sign)
	end
end

-- The forge: a house-sized workshop with an open front (forge, glowing coals, bellows inside).
local function buildForgeParts(spec: Building, base: CFrame, model: Model)
	local width, height, depth = spec.Size.X, spec.Size.Y, spec.Size.Z
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	piece({ Name = "Floor", Size = Vector3.new(width + 1, 1.4, depth + 1), CFrame = base * CFrame.new(0, -0.3, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	-- Back and side walls (stone), front open between posts.
	piece({ Name = "BackWall", Size = Vector3.new(width, height, 1.2), CFrame = base * CFrame.new(0, height / 2, depth / 2 - 0.6), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	for _, side in { -1, 1 } do
		piece({ Name = "SideWall", Size = Vector3.new(1.2, height, depth), CFrame = base * CFrame.new(side * (width / 2 - 0.6), height / 2, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
		piece({ Name = "FrontPost", Size = Vector3.new(1.2, height, 1.2), CFrame = base * CFrame.new(side * width / 6, height / 2, -depth / 2 + 0.6), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	piece({ Name = "Lintel", Size = Vector3.new(width, 1.2, 1.2), CFrame = base * CFrame.new(0, height - 0.6, -depth / 2 + 0.6), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	-- Single sloped roof, high at the back.
	local slope = math.atan2(3, depth)
	piece({ Name = "Roof", Size = Vector3.new(width + 2, 0.6, depth + 2), CFrame = base * CFrame.new(0, height + 1.5, 0) * CFrame.Angles(slope, 0, 0), Color = spec.Roof or COLORS.DarkWood, Material = Enum.Material.Slate })
	-- The forge: a stone hearth with glowing coals against the back wall, and its chimney.
	local hearth = piece({ Name = "Hearth", Size = Vector3.new(6, 3.4, 4), CFrame = base * CFrame.new(-width / 4, 1.7, depth / 2 - 3), Color = COLORS.DarkStone, Material = Enum.Material.Brick })
	local coals = piece({ Name = "Coals", Size = Vector3.new(4.4, 0.4, 2.6), CFrame = hearth.CFrame * CFrame.new(0, 1.8, 0), Color = COLORS.Ember, Material = Enum.Material.Neon })
	addLight(coals, 16, 2.5, COLORS.Ember)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 4
	fire.Color = COLORS.Ember
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = coals
	piece({ Name = "Chimney", Size = Vector3.new(3, height + 6, 3), CFrame = base * CFrame.new(-width / 4, (height + 6) / 2, depth / 2 + 0.6), Color = COLORS.DarkStone, Material = Enum.Material.Brick })
	local smokeVent = piece({ Name = "ChimneyTop", Size = Vector3.new(2, 0.4, 2), CFrame = base * CFrame.new(-width / 4, height + 6.2, depth / 2 + 0.6), Color = COLORS.Metal, Material = Enum.Material.Metal, Transparency = 1, CanCollide = false })
	local smoke = Instance.new("Smoke")
	smoke.Size = 3
	smoke.RiseVelocity = 5
	smoke.Opacity = 0.15
	smoke.Color = Color3.fromRGB(120, 115, 110)
	smoke.Parent = smokeVent
	-- Weapon rack on the right wall.
	piece({ Name = "Rack", Size = Vector3.new(0.4, 4, 6), CFrame = base * CFrame.new(width / 2 - 1.6, 3, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	for i = -1, 1 do
		piece({ Name = "RackBlade", Size = Vector3.new(0.2, 3.6, 0.4), CFrame = base * CFrame.new(width / 2 - 2, 3.2, i * 1.8) * CFrame.Angles(0, 0, math.rad(8)), Color = COLORS.Iron, Material = Enum.Material.Metal })
	end
	if spec.Sign then
		local sign = piece({ Name = "Sign", Size = Vector3.new(math.min(width - 4, 12), 2, 0.3), CFrame = base * CFrame.new(0, height - 0.6, -depth / 2 - 0.1), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		addSign(sign, spec.Sign)
	end
end

-- A market stall: counter, four posts, a sloped awning, and a sign on the counter.
local function buildStallParts(spec: Building, base: CFrame, model: Model)
	local width, height, depth = spec.Size.X, spec.Size.Y, spec.Size.Z
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	piece({ Name = "Counter", Size = Vector3.new(width - 1, 3.5, 2), CFrame = base * CFrame.new(0, 1.75, -depth / 2 + 1.5), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		piece({ Name = "Post", Size = Vector3.new(0.8, height, 0.8), CFrame = base * CFrame.new(corner.X * (width / 2 - 0.9), height / 2, corner.Y * (depth / 2 - 0.9)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	piece({ Name = "Awning", Size = Vector3.new(width, 0.4, depth + 0.5), CFrame = base * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(-10), 0, 0), Color = spec.Awning or COLORS.Banner, Material = Enum.Material.Fabric })
	-- Goods on the counter.
	for i = -1, 1 do
		piece({ Name = "Goods", Size = Vector3.new(1.4, 1.2, 1.2), CFrame = base * CFrame.new(i * 2.6, 4.1, -depth / 2 + 1.5), Color = if i == 0 then COLORS.LightWood else COLORS.Hay, Material = Enum.Material.WoodPlanks })
	end
	if spec.Sign then
		local sign = piece({ Name = "Sign", Size = Vector3.new(width - 3, 1.6, 0.3), CFrame = base * CFrame.new(0, 1.9, -depth / 2 + 0.35), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		addSign(sign, spec.Sign)
	end
end

-- The guild hall: a big house with a porch roof, banners, and the sign.
local function buildHallParts(spec: Building, base: CFrame, model: Model)
	buildHouseParts(spec, base, model)
	local width, depth = spec.Size.X, spec.Size.Z
	local front = -depth / 2
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	for _, side in { -1, 1 } do
		piece({ Name = "PorchPost", Size = Vector3.new(1, 8, 1), CFrame = base * CFrame.new(side * 5, 4, front - 4), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		piece({ Name = "Banner", Size = Vector3.new(2.6, 6, 0.2), CFrame = base * CFrame.new(side * (width / 2 - 3), 7, front - 0.3), Color = COLORS.Banner, Material = Enum.Material.Fabric })
		piece({ Name = "BannerTrim", Size = Vector3.new(2.8, 0.4, 0.3), CFrame = base * CFrame.new(side * (width / 2 - 3), 10.1, front - 0.35), Color = COLORS.Hay, Material = Enum.Material.Fabric })
	end
	piece({ Name = "PorchRoof", Size = Vector3.new(12, 0.5, 5), CFrame = base * CFrame.new(0, 8.2, front - 2.3) * CFrame.Angles(math.rad(-12), 0, 0), Color = spec.Roof or COLORS.DarkWood, Material = Enum.Material.Slate })
	piece({ Name = "Steps", Size = Vector3.new(8, 0.8, 2), CFrame = base * CFrame.new(0, 0.1, front - 1), Color = COLORS.Stone, Material = Enum.Material.Slate })
end

-- Cloth hanging from its top edge (a banner, a flag, washing), swaying in the wind.
local function cloth(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local piece = part({ Name = name, Size = size, CFrame = cframe, Color = color, Material = Enum.Material.Fabric, CanCollide = false, Parent = parent })
	piece:SetAttribute("Sway", CLOTH_SWAY)
	return piece
end

-- A lantern hanging at `cframe`, lit at night (client DayCycle).
local function lantern(cframe: CFrame, parent: Instance)
	part({ Name = "LanternCap", Size = Vector3.new(1.3, 0.3, 1.3), CFrame = cframe * CFrame.new(0, 0.85, 0), Color = COLORS.Metal, Material = Enum.Material.Metal, Parent = parent })
	local glow = part({ Name = "Lantern", Size = Vector3.new(1, 1.4, 1), CFrame = cframe, Color = COLORS.LampGlow, Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
	addLight(glow, 16)
end

-- A lookout tower: four log legs with cross braces, a railed platform, a pointed roof, a
-- ladder up the back, a lantern and a pennant on top.
local function buildWatchtowerParts(spec: Building, base: CFrame, model: Model)
	local width, height = spec.Size.X, spec.Size.Y
	local half = width / 2
	local deck = height * 0.65
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		cylinder("Leg", deck + 5, 1.1, base * CFrame.new(corner.X * (half - 0.6), (deck + 5) / 2, corner.Y * (half - 0.6)), COLORS.Wood, Enum.Material.Wood, model)
	end
	for _, side in { -1, 1 } do
		-- X braces on two sides.
		for _, tilt in { -1, 1 } do
			local length = math.sqrt((width - 1.2) ^ 2 + (deck * 0.55) ^ 2)
			piece({ Name = "Brace", Size = Vector3.new(0.4, length, 0.4), CFrame = base * CFrame.new(side * (half - 0.6), deck * 0.4, 0) * CFrame.Angles(math.atan2(width - 1.2, deck * 0.55) * tilt, 0, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
			piece({ Name = "Brace", Size = Vector3.new(0.4, length, 0.4), CFrame = base * CFrame.new(0, deck * 0.4, side * (half - 0.6)) * CFrame.Angles(0, 0, math.atan2(width - 1.2, deck * 0.55) * tilt), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		end
	end
	piece({ Name = "Deck", Size = Vector3.new(width + 1, 0.6, width + 1), CFrame = base * CFrame.new(0, deck, 0), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		piece({ Name = "Rail", Size = Vector3.new(width + 1, 1.6, 0.3), CFrame = base * CFrame.new(0, deck + 1.1, side * (half + 0.35)), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
		piece({ Name = "Rail", Size = Vector3.new(0.3, 1.6, width + 1), CFrame = base * CFrame.new(side * (half + 0.35), deck + 1.1, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	end
	-- Roof: a four-sided cap of tilted slabs.
	local roofY = deck + 5
	for index = 0, 3 do
		local turn = CFrame.Angles(0, index * math.pi / 2, 0)
		piece({ Name = "Roof", Size = Vector3.new(width + 2.4, 0.5, (width + 2.4) * 0.62), CFrame = base * turn * CFrame.new(0, roofY + 1.3, (width + 2.4) / 4) * CFrame.Angles(math.rad(38), 0, 0), Color = spec.Roof or COLORS.DarkWood, Material = Enum.Material.Slate })
	end
	-- Pennant on a short pole at the peak.
	local poleTop = roofY + 6.5
	cylinder("FlagPole", 4, 0.3, base * CFrame.new(0, poleTop - 2, 0), COLORS.DarkWood, Enum.Material.Wood, model)
	cloth("Pennant", Vector3.new(0.1, 1.6, 2.6), base * CFrame.new(0, poleTop - 0.9, -1.4), COLORS.Banner, model)
	lantern(base * CFrame.new(0, deck + 3.4, -half - 0.2), model)
	-- Ladder up the back.
	for _, side in { -1, 1 } do
		piece({ Name = "LadderRail", Size = Vector3.new(0.3, deck + 1, 0.3), CFrame = base * CFrame.new(side * 1, (deck + 1) / 2, half + 0.9), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	for y = 1, deck, 1.5 do
		piece({ Name = "Rung", Size = Vector3.new(2.2, 0.25, 0.25), CFrame = base * CFrame.new(0, y, half + 0.9), Color = COLORS.Wood, Material = Enum.Material.Wood })
	end
end

-- A square stone bell tower: a tall shaft, an open belfry with the bell (marked "Bell": the
-- client tolls it at dawn and dusk), and a steep roof.
local function buildBellTowerParts(spec: Building, base: CFrame, model: Model)
	local width, height = spec.Size.X, spec.Size.Y
	local half = width / 2
	local shaft = height * 0.62
	local belfry = height * 0.2
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	piece({ Name = "Plinth", Size = Vector3.new(width + 2, 1.6, width + 2), CFrame = base * CFrame.new(0, 0.3, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	piece({ Name = "Shaft", Size = Vector3.new(width, shaft, width), CFrame = base * CFrame.new(0, shaft / 2, 0), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	for _, y in { shaft * 0.35, shaft * 0.7 } do
		piece({ Name = "Band", Size = Vector3.new(width + 0.5, 0.6, width + 0.5), CFrame = base * CFrame.new(0, y, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	end
	piece({ Name = "Door", Size = Vector3.new(3, 5.5, 0.3), CFrame = base * CFrame.new(0, 2.75, -half - 0.1), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	piece({ Name = "Window", Size = Vector3.new(1.6, 2.6, 0.2), CFrame = base * CFrame.new(0, shaft * 0.55, -half - 0.05), Color = COLORS.Glass, Material = Enum.Material.Glass })
	-- The belfry: corner pillars, open sides.
	piece({ Name = "BelfryFloor", Size = Vector3.new(width + 0.6, 0.8, width + 0.6), CFrame = base * CFrame.new(0, shaft + 0.4, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		piece({ Name = "Pillar", Size = Vector3.new(1.6, belfry, 1.6), CFrame = base * CFrame.new(corner.X * (half - 0.8), shaft + belfry / 2, corner.Y * (half - 0.8)), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
	end
	local top = shaft + belfry
	piece({ Name = "BelfryTop", Size = Vector3.new(width + 0.8, 1, width + 0.8), CFrame = base * CFrame.new(0, top + 0.5, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	piece({ Name = "BellBeam", Size = Vector3.new(width - 1, 0.6, 0.6), CFrame = base * CFrame.new(0, top - 0.6, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	local bell = piece({ Name = "Bell", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = base * CFrame.new(0, top - 2.6, 0), Color = Color3.fromRGB(180, 140, 60), Material = Enum.Material.Metal })
	bell:SetAttribute("Bell", true)
	piece({ Name = "BellLip", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6, 3.6), CFrame = base * CFrame.new(0, top - 3.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(160, 120, 50), Material = Enum.Material.Metal })
	-- A steep four-sided roof and a spire.
	local roofRise = height - top - 2
	for index = 0, 3 do
		local turn = CFrame.Angles(0, index * math.pi / 2, 0)
		local slope = math.atan2(roofRise, half + 0.6)
		local length = math.sqrt(roofRise ^ 2 + (half + 0.6) ^ 2) + 0.6
		piece({ Name = "Roof", Size = Vector3.new(width + 1.6, 0.5, length), CFrame = base * turn * CFrame.new(0, top + 1 + roofRise / 2, (half + 0.6) / 2) * CFrame.Angles(slope, 0, 0), Color = spec.Roof or COLORS.DarkWood, Material = Enum.Material.Slate })
	end
	cylinder("Spire", 3, 0.35, base * CFrame.new(0, height + 0.5, 0), COLORS.Metal, Enum.Material.Metal, model)
end

-- A stone windmill: a tapering round tower, a cap, and four lattice sails on a hub (a Model
-- marked "Spin"; the client turns it about the axle, its pivot's look direction).
local function buildWindmillParts(spec: Building, base: CFrame, model: Model)
	local width, height = spec.Size.X, spec.Size.Y
	local function piece(props: { [string]: any }): BasePart
		props.Parent = model
		return part(props)
	end
	local tiers = 4
	for tier = 0, tiers - 1 do
		local diameter = width * (1 - tier * 0.08)
		local tierHeight = height / tiers
		cylinder("Tower", tierHeight + 0.2, diameter, base * CFrame.new(0, tierHeight * (tier + 0.5), 0), if tier % 2 == 0 then COLORS.Plaster else COLORS.Stone, if tier % 2 == 0 then Enum.Material.Plaster else Enum.Material.Cobblestone, model)
	end
	piece({ Name = "Door", Size = Vector3.new(3, 5.5, 0.4), CFrame = base * CFrame.new(0, 2.75, -width / 2 + 0.1), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	piece({ Name = "Window", Size = Vector3.new(1.6, 2, 0.3), CFrame = base * CFrame.new(0, height * 0.6, -width * 0.42 + 0.1), Color = COLORS.Glass, Material = Enum.Material.Glass })
	-- The cap: a cone made of a stack of shrinking discs.
	for step = 0, 4 do
		cylinder("Cap", 1.2, width * (0.95 - step * 0.18), base * CFrame.new(0, height + 0.6 + step * 1.1, 0), spec.Roof or COLORS.DarkWood, Enum.Material.Slate, model)
	end
	-- The sails, in front (local -Z) of the cap.
	local hubCFrame = base * CFrame.new(0, height * 0.88, -width / 2 - 1.2)
	piece({ Name = "Axle", Size = Vector3.new(0.8, 0.8, 3), CFrame = hubCFrame * CFrame.new(0, 0, 1.2), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	local sails = Instance.new("Model")
	sails.Name = "Sails"
	local hub = part({ Name = "Hub", Size = Vector3.new(1.6, 1.6, 1), CFrame = hubCFrame, Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = sails })
	local length = height * 0.55
	for index = 0, 3 do
		local arm = hubCFrame * CFrame.Angles(0, 0, index * math.pi / 2 + math.rad(20))
		part({ Name = "Stock", Size = Vector3.new(0.5, length, 0.4), CFrame = arm * CFrame.new(0, length / 2, -0.2), Color = COLORS.DarkWood, Material = Enum.Material.Wood, CanCollide = false, Parent = sails })
		part({ Name = "Sail", Size = Vector3.new(2.6, length * 0.78, 0.15), CFrame = arm * CFrame.new(1.4, length * 0.58, -0.25), Color = COLORS.Paper, Material = Enum.Material.Fabric, CanCollide = false, Parent = sails })
		for rung = 1, 4 do
			part({ Name = "Lattice", Size = Vector3.new(2.8, 0.2, 0.2), CFrame = arm * CFrame.new(1.4, length * (0.2 + rung * 0.17), -0.35), Color = COLORS.Wood, Material = Enum.Material.Wood, CanCollide = false, Parent = sails })
		end
	end
	hub.CanCollide = false
	sails.PrimaryPart = hub
	sails.WorldPivot = hubCFrame
	sails:SetAttribute("Spin", 0.5)
	sails.Parent = model
end

local BUILDERS: { [string]: (Building, CFrame, Model) -> () } = {
	house = buildHouseParts,
	forge = buildForgeParts,
	stall = buildStallParts,
	hall = buildHallParts,
	watchtower = buildWatchtowerParts,
	belltower = buildBellTowerParts,
	windmill = buildWindmillParts,
}

-- The highest point of a model (its chimney top, on a house), found by raycasting down onto it.
local function topOf(model: Model): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local low, high = worldBounds(model)
	local best: Vector3? = nil
	for x = low.X, high.X, 1 do
		for z = low.Z, high.Z, 1 do
			local hit = workspace:Raycast(Vector3.new(x, high.Y + 5, z), Vector3.new(0, low.Y - high.Y - 10, 0), params)
			if hit and (not best or hit.Position.Y > best.Y + 0.05) then
				best = hit.Position
			end
		end
	end
	return best
end

local function buildBuilding(spec: Building)
	local base = groundCFrame(spec.Position, spec.Facing) -- front faces local -Z
	local footprint = Vector2.new(spec.Size.X, spec.Size.Z)
	local asset = spec.Asset and placeAsset(spec.Asset, base, if spec.Scale then nil else footprint, spec.Scale)
	if asset then
		asset.Name = spec.Name
		local tint = ASSET_TINT[spec.Asset :: string]
		if tint then
			for _, descendant in asset:GetDescendants() do
				if descendant:IsA("BasePart") then
					if spec.Walls and table.find(tint.Walls, descendant.Name) then
						descendant.Color = spec.Walls
					elseif spec.Roof and table.find(tint.Roof, descendant.Name) then
						descendant.Color = spec.Roof
					end
				end
			end
		end
		if spec.Sign then
			-- Beside the door, just in front of the model's actual front wall.
			local low, high = worldBounds(asset)
			local size = base:VectorToObjectSpace(high - low)
			local width, depth = math.abs(size.X), math.abs(size.Z)
			addSignpost(base * CFrame.new(width / 2 - 2, 0, -depth / 2 - 2.5), spec.Sign, asset, math.max(7, #spec.Sign * 0.55))
		end
		if spec.Chimney then
			local top = topOf(asset)
			if top then
				addSmoke(top + Vector3.new(0, 0.5, 0), asset)
			end
		end
		return
	end
	local model = Instance.new("Model")
	model.Name = spec.Name
	BUILDERS[spec.Kind](spec, base, model)
	model.Parent = townFolder
	local chimney = model:FindFirstChild("Chimney")
	if spec.Chimney and chimney and chimney:IsA("BasePart") then
		addSmoke(chimney.Position + Vector3.new(0, chimney.Size.Y / 2 + 0.3, 0), model)
	end
end

-- Props ---------------------------------------------------------------------------------------

local PROPS: { [string]: (CFrame, Prop) -> () } = {}

PROPS.bench = function(base)
	part({ Name = "BenchSeat", Size = Vector3.new(5, 0.4, 1.6), CFrame = base * CFrame.new(0, 1.6, 0), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
	part({ Name = "BenchBack", Size = Vector3.new(5, 1.4, 0.3), CFrame = base * CFrame.new(0, 2.6, 0.75) * CFrame.Angles(math.rad(-10), 0, 0), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		part({ Name = "BenchLeg", Size = Vector3.new(0.4, 1.6, 1.4), CFrame = base * CFrame.new(side * 2, 0.8, 0), Color = COLORS.Metal, Material = Enum.Material.Metal })
	end
end

PROPS.barrel = function(base)
	cylinder("Barrel", 3, 2.4, base * CFrame.new(0, 1.5, 0), COLORS.Wood, Enum.Material.WoodPlanks)
	for _, y in { 0.6, 2.4 } do
		cylinder("BarrelHoop", 0.25, 2.5, base * CFrame.new(0, y, 0), COLORS.Metal, Enum.Material.Metal)
	end
end

PROPS.crate = function(base)
	part({ Name = "Crate", Size = Vector3.one * 2.4, CFrame = base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.rad(12), 0), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
end

PROPS.anvil = function(base)
	cylinder("AnvilStump", 1.6, 2.2, base * CFrame.new(0, 0.8, 0), COLORS.Trunk, Enum.Material.Wood)
	part({ Name = "Anvil", Size = Vector3.new(2.6, 0.9, 1), CFrame = base * CFrame.new(0, 2.05, 0), Color = COLORS.Iron, Material = Enum.Material.Metal })
	part({ Name = "AnvilHorn", Size = Vector3.new(0.9, 0.5, 0.6), CFrame = base * CFrame.new(1.7, 2.2, 0), Color = COLORS.Iron, Material = Enum.Material.Metal })
end

PROPS.well = function(base)
	cylinder("WellWall", 2.6, 6, base * CFrame.new(0, 1.3, 0), COLORS.Stone, Enum.Material.Cobblestone)
	cylinder("WellWater", 0.2, 4.6, base * CFrame.new(0, 2, 0), COLORS.Water, Enum.Material.Glass).Transparency = 0.2
	for _, side in { -1, 1 } do
		part({ Name = "WellPost", Size = Vector3.new(0.6, 5, 0.6), CFrame = base * CFrame.new(side * 2.6, 4, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		part({ Name = "WellRoof", Size = Vector3.new(6.4, 0.4, 2.8), CFrame = base * CFrame.new(0, 7, side * 1.1) * CFrame.Angles(side * math.rad(-30), 0, 0), Color = COLORS.DarkWood, Material = Enum.Material.WoodPlanks })
	end
	cylinder("WellCrank", 5.4, 0.4, base * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Wood, Enum.Material.Wood)
end

PROPS.flowers = function(base)
	part({ Name = "FlowerBed", Size = Vector3.new(5, 1, 5), CFrame = base * CFrame.new(0, 0.5, 0), Color = COLORS.DarkStone, Material = Enum.Material.Slate })
	part({ Name = "Soil", Size = Vector3.new(4.4, 0.4, 4.4), CFrame = base * CFrame.new(0, 1, 0), Color = COLORS.Dirt, Material = Enum.Material.Ground })
	local random = Random.new(math.floor(base.Position.X * 7 + base.Position.Z * 13))
	for _ = 1, 9 do
		local x, z = random:NextNumber(-1.8, 1.8), random:NextNumber(-1.8, 1.8)
		part({ Name = "Leaf", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = base * CFrame.new(x, 1.5, z), Color = COLORS.DarkLeaves, Material = Enum.Material.Grass, CanCollide = false })
		part({ Name = "Flower", Size = Vector3.new(0.5, 0.5, 0.5), CFrame = base * CFrame.new(x, 2.1, z), Color = COLORS.Flowers[random:NextInteger(1, #COLORS.Flowers)], Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
end

PROPS.cart = function(base)
	part({ Name = "CartBed", Size = Vector3.new(4, 0.5, 7), CFrame = base * CFrame.new(0, 2.2, 0), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		part({ Name = "CartSide", Size = Vector3.new(0.3, 1.2, 7), CFrame = base * CFrame.new(side * 1.85, 3, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
		cylinder("Wheel", 0.4, 3.2, base * CFrame.new(side * 2.3, 1.6, 1.2) * CFrame.Angles(0, 0, math.rad(90)), COLORS.DarkWood, Enum.Material.Wood)
		part({ Name = "Shaft", Size = Vector3.new(0.3, 0.3, 4), CFrame = base * CFrame.new(side * 1.2, 2, -5.2), Color = COLORS.Wood, Material = Enum.Material.Wood })
	end
	part({ Name = "Sack", Size = Vector3.new(1.6, 1.2, 1.4), CFrame = base * CFrame.new(-0.6, 3.1, 1.5), Color = COLORS.Hay, Material = Enum.Material.Fabric })
	part({ Name = "Crate", Size = Vector3.one * 1.6, CFrame = base * CFrame.new(0.8, 3.25, -1.2), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
end

PROPS.hay = function(base)
	part({ Name = "HayBale", Size = Vector3.new(3.4, 2, 2.2), CFrame = base * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(20), 0), Color = COLORS.Hay, Material = Enum.Material.Sand })
end

PROPS.questboard = function(base)
	for _, side in { -1, 1 } do
		part({ Name = "BoardPost", Size = Vector3.new(0.6, 7, 0.6), CFrame = base * CFrame.new(side * 3.2, 3.5, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	local board = part({ Name = "QuestBoard", Size = Vector3.new(6.4, 4, 0.4), CFrame = base * CFrame.new(0, 4.2, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	part({ Name = "BoardRoof", Size = Vector3.new(7.6, 0.4, 1.6), CFrame = base * CFrame.new(0, 7.1, 0) * CFrame.Angles(math.rad(-15), 0, 0), Color = COLORS.DarkWood, Material = Enum.Material.WoodPlanks })
	local random = Random.new(11)
	for i = 1, 5 do
		local paper = part({ Name = "Notice", Size = Vector3.new(1.3, 1.6, 0.05), CFrame = board.CFrame * CFrame.new(-2.4 + (i - 1) * 1.2, random:NextNumber(-0.8, 0.8), -0.23) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-8, 8))), Color = COLORS.Paper, Material = Enum.Material.SmoothPlastic })
		paper.CanCollide = false
	end
	local title = part({ Name = "BoardTitle", Size = Vector3.new(5, 0.9, 0.2), CFrame = board.CFrame * CFrame.new(0, 2.5, -0.15), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(title, "Quest Board")
end

PROPS.signpost = function(base, prop)
	local text = prop.Text or ""
	addSignpost(base, text, townFolder, math.max(7, #text * 0.5))
end

-- A tilled bed with rows of leafy crops.
PROPS.crops = function(base, prop)
	local size = prop.Size or Vector2.new(14, 14)
	part({ Name = "Field", Size = Vector3.new(size.X, 1, size.Y), CFrame = base * CFrame.new(0, 0.2, 0), Color = COLORS.Dirt, Material = Enum.Material.Ground })
	local random = Random.new(math.floor(base.Position.X * 3 + base.Position.Z * 5))
	local rows = math.max(2, math.floor(size.X / 3))
	for row = 1, rows do
		local x = -size.X / 2 + (row - 0.5) * size.X / rows
		part({ Name = "Furrow", Size = Vector3.new(1.2, 0.5, size.Y - 1.5), CFrame = base * CFrame.new(x, 0.9, 0), Color = COLORS.Trunk, Material = Enum.Material.Ground })
		for z = -size.Y / 2 + 1.8, size.Y / 2 - 1.8, 2.2 do
			local height = random:NextNumber(0.9, 1.6)
			part({ Name = "Crop", Size = Vector3.new(1.1, height, 1.1), CFrame = base * CFrame.new(x, 1.1 + height / 2, z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0), Color = if random:NextNumber() < 0.5 then COLORS.Leaves else COLORS.DarkLeaves, Material = Enum.Material.Grass, CanCollide = false })
		end
	end
end

-- A round pond (Size.X across): water in a rocky rim, with a short wooden dock on its south side.
PROPS.pond = function(base, prop)
	local diameter = if prop.Size then prop.Size.X else 24
	local radius = diameter / 2
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; this stands them up
	local water = part({ Name = "PondWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, diameter, diameter), CFrame = base * CFrame.new(0, 0.1, 0) * upright, Color = COLORS.Water, Material = Enum.Material.Glass, Transparency = 0.15 })
	water.CanCollide = false
	part({ Name = "PondBed", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, diameter, diameter), CFrame = base * CFrame.new(0, -0.4, 0) * upright, Color = Color3.fromRGB(60, 80, 70), Material = Enum.Material.Mud })
	local random = Random.new(5)
	local rocks = math.floor(diameter * 1.1)
	for i = 0, rocks - 1 do
		local angle = i / rocks * math.pi * 2
		local rockSize = random:NextNumber(1.6, 2.6)
		local at = Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius)
		part({ Name = "PondRock", Size = Vector3.new(rockSize, rockSize * 0.6, rockSize), CFrame = base * CFrame.new(at) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0), Color = if i % 3 == 0 then COLORS.DarkStone else COLORS.Stone, Material = Enum.Material.Slate })
	end
	local dockLength = radius + 2
	part({ Name = "Dock", Size = Vector3.new(4, 0.5, dockLength), CFrame = base * CFrame.new(0, 1.2, radius + 2 - dockLength / 2), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		for _, z in { 0, radius / 2 } do
			part({ Name = "DockPost", Size = Vector3.new(0.6, 2.6, 0.6), CFrame = base * CFrame.new(side * 1.8, 0.4, z), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
		end
	end
end

-- The guild's trophy board: a big board on posts (LeaderboardService writes the top hunters on
-- "TrophyBoard"), a title plank, and orc heads mounted on plaques along the top.
PROPS.trophies = function(base)
	local model = Instance.new("Model")
	model.Name = "Trophies"
	for _, side in { -1, 1 } do
		part({ Name = "BoardPost", Size = Vector3.new(0.7, 11, 0.7), CFrame = base * CFrame.new(side * 5.4, 5.5, 0.1), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = model })
	end
	part({ Name = "TrophyBoard", Size = Vector3.new(10, 6.5, 0.4), CFrame = base * CFrame.new(0, 4.6, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks, Parent = model })
	local title = part({ Name = "BoardTitle", Size = Vector3.new(8, 1, 0.25), CFrame = base * CFrame.new(0, 8.4, -0.15), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = model })
	addSign(title, "Hall of Hunters")
	part({ Name = "TrophyShelf", Size = Vector3.new(11.4, 0.5, 1.6), CFrame = base * CFrame.new(0, 9.2, -0.4), Color = COLORS.DarkWood, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "BoardRoof", Size = Vector3.new(12.4, 0.4, 2.4), CFrame = base * CFrame.new(0, 11.6, -0.3) * CFrame.Angles(math.rad(-15), 0, 0), Color = COLORS.DarkWood, Material = Enum.Material.WoodPlanks, Parent = model })
	local enemies = ServerStorage:FindFirstChild("EnemyModels")
	local orc = enemies and enemies:FindFirstChild("Orc")
	local orcHead = orc and orc:FindFirstChild("Head")
	for index, x in { -3.6, 0, 3.6 } do
		local at = base * CFrame.new(x, 10.4, -0.2)
		part({ Name = "Plaque", Size = Vector3.new(1.8, 2.2, 0.3), CFrame = at * CFrame.new(0, 0, 0.5), Color = COLORS.LightWood, Material = Enum.Material.WoodPlanks, Parent = model })
		if orcHead and orcHead:IsA("BasePart") then
			local head = orcHead:Clone()
			for _, child in head:GetChildren() do
				if not child:IsA("SurfaceAppearance") and not child:IsA("Decal") then
					child:Destroy()
				end
			end
			head.Name = "OrcHead"
			head.Anchored = true
			head.CanCollide = false
			head.Size *= if index == 2 then 0.85 else 0.7
			head.CFrame = at * CFrame.new(0, 0.1, -0.2) * CFrame.Angles(0, math.rad(if index == 1 then 15 elseif index == 3 then -15 else 0), 0)
			head.Parent = model
		else
			part({ Name = "OrcHead", Size = Vector3.new(1.3, 1.4, 1), CFrame = at * CFrame.new(0, 0.1, -0.3), Color = Color3.fromRGB(95, 130, 70), Material = Enum.Material.SmoothPlastic, Parent = model })
		end
	end
	model.Parent = townFolder
end

-- A round leafy bush (a few overlapping balls).
PROPS.bush = function(base)
	local random = Random.new(math.floor(base.Position.X * 11 + base.Position.Z * 17))
	for index = 1, 4 do
		local size = random:NextNumber(2.4, 3.6) * (if index == 1 then 1.2 else 1)
		local offset = if index == 1 then Vector3.zero else Vector3.new(random:NextNumber(-1.4, 1.4), 0, random:NextNumber(-1.4, 1.4))
		part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = base * CFrame.new(offset + Vector3.new(0, size * 0.35, 0)), Color = if index % 2 == 0 then COLORS.DarkLeaves else COLORS.Leaves, Material = Enum.Material.Grass })
	end
end

-- A long wooden planter box full of flowers.
PROPS.planter = function(base)
	part({ Name = "Planter", Size = Vector3.new(7, 1.4, 2), CFrame = base * CFrame.new(0, 0.7, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	part({ Name = "Soil", Size = Vector3.new(6.4, 0.3, 1.5), CFrame = base * CFrame.new(0, 1.35, 0), Color = COLORS.Dirt, Material = Enum.Material.Ground })
	local random = Random.new(math.floor(base.Position.X * 5 + base.Position.Z * 3))
	for x = -2.8, 2.8, 0.8 do
		local leafX = x + random:NextNumber(-0.15, 0.15)
		part({ Name = "Leaf", Size = Vector3.new(0.8, 0.8, 0.8), CFrame = base * CFrame.new(leafX, 1.75, random:NextNumber(-0.3, 0.3)), Color = COLORS.DarkLeaves, Material = Enum.Material.Grass, CanCollide = false })
		part({ Name = "Flower", Size = Vector3.new(0.45, 0.45, 0.45), CFrame = base * CFrame.new(leafX, 2.3, random:NextNumber(-0.3, 0.3)), Color = COLORS.Flowers[random:NextInteger(1, #COLORS.Flowers)], Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
end

-- A washing line between two posts (along local X), with clothes swaying on it.
PROPS.laundry = function(base)
	local length = 14
	for _, side in { -1, 1 } do
		part({ Name = "LinePost", Size = Vector3.new(0.5, 7, 0.5), CFrame = base * CFrame.new(side * length / 2, 3.5, 0), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	part({ Name = "Line", Size = Vector3.new(length, 0.08, 0.08), CFrame = base * CFrame.new(0, 6.6, 0), Color = COLORS.Paper, Material = Enum.Material.Fabric, CanCollide = false })
	local colors = { Color3.fromRGB(240, 240, 235), Color3.fromRGB(150, 60, 55), Color3.fromRGB(90, 120, 170), Color3.fromRGB(230, 200, 120), Color3.fromRGB(120, 150, 100) }
	local random = Random.new(math.floor(base.Position.X * 7 + base.Position.Z))
	local x = -length / 2 + 1.4
	local index = 1
	while x < length / 2 - 1.4 do
		local width = random:NextNumber(1.4, 2.4)
		local drop = random:NextNumber(1.6, 2.8)
		cloth("Washing", Vector3.new(width, drop, 0.1), base * CFrame.new(x + width / 2, 6.6 - drop / 2, 0), colors[(index - 1) % #colors + 1], townFolder)
		x += width + random:NextNumber(0.4, 1)
		index += 1
	end
end

-- A tall pole with a banner hanging from a crossbar; the banner faces Facing.
PROPS.flag = function(base, prop)
	cylinder("FlagPole", 14, 0.45, base * CFrame.new(0, 7, 0), COLORS.DarkWood, Enum.Material.Wood)
	part({ Name = "FlagBar", Size = Vector3.new(4, 0.3, 0.3), CFrame = base * CFrame.new(0, 13.2, -0.35), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	part({ Name = "FlagTop", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = base * CFrame.new(0, 14.2, 0), Color = COLORS.Hay, Material = Enum.Material.Metal })
	cloth("Banner", Vector3.new(3.4, 6, 0.12), base * CFrame.new(0, 10.1, -0.45), prop.Color or COLORS.Banner, townFolder)
end

-- A stack of firewood logs under a little lean-to roof.
PROPS.woodpile = function(base)
	for row = 0, 2 do
		for i = 0, 3 - row do
			-- Cylinders run along X; turned to lie front to back.
			part({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 0.9, 0.9), CFrame = base * CFrame.new(-1.35 + i * 0.9 + row * 0.45, 0.45 + row * 0.8, 0) * CFrame.Angles(0, math.rad(90), 0), Color = if (i + row) % 2 == 0 then COLORS.Trunk else COLORS.Wood, Material = Enum.Material.Wood })
		end
	end
	part({ Name = "WoodRoof", Size = Vector3.new(5, 0.3, 6), CFrame = base * CFrame.new(0, 3.6, 0) * CFrame.Angles(math.rad(10), 0, 0), Color = COLORS.DarkWood, Material = Enum.Material.WoodPlanks })
	for _, x in { -2.2, 2.2 } do
		part({ Name = "WoodPost", Size = Vector3.new(0.4, 3.6, 0.4), CFrame = base * CFrame.new(x, 1.8, -2.6), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
end

-- A heap of grain sacks.
PROPS.sacks = function(base)
	local spots = { Vector3.new(-1, 0.6, 0), Vector3.new(0.9, 0.6, 0.3), Vector3.new(0, 0.6, -1.2), Vector3.new(-0.1, 1.6, -0.2) }
	for index, at in spots do
		part({ Name = "Sack", Size = Vector3.new(1.6, 1.2, 1.3), CFrame = base * CFrame.new(at) * CFrame.Angles(0, math.rad(index * 25), math.rad(if index == 4 then 10 else 0)), Color = COLORS.Hay, Material = Enum.Material.Fabric })
	end
end

local function buildProp(prop: Prop)
	local base = groundCFrame(prop.Position, prop.Facing)
	local modelName = PROP_MODELS[prop.Kind]
	local model = modelName and placeAsset(modelName, base, nil, prop.Scale)
	if model then
		for _, descendant in model:GetDescendants() do
			-- Fires (the campfire) light up their surroundings.
			if descendant:IsA("Fire") and descendant.Parent and descendant.Parent:IsA("BasePart") then
				addLight(descendant.Parent, 24, 2, COLORS.Ember)
			end
			-- Color recolors the model's colored cloth (a stall's canopy stripes), not white cloth.
			if prop.Color and descendant:IsA("BasePart") and descendant.Material == Enum.Material.Fabric then
				local h, sat, v = descendant.Color:ToHSV()
				if sat > 0.2 or v < 0.8 then
					descendant.Color = prop.Color
				end
			end
		end
	elseif PROPS[prop.Kind] then
		PROPS[prop.Kind](base, prop)
	end
end

local function buildProps()
	for _, prop in TownConfig.Props do
		buildProp(prop)
	end
	for _, prop in TownConfig.Decor do
		buildProp(prop)
	end
end

-- Edges ---------------------------------------------------------------------------------------

-- A wooden fence from `from` to `to` (X/Z): FarmFence model sections stretched (by scaling)
-- to fill the run exactly, or, without the model, posts and two rails following the ground.
local function buildFenceRun(from: Vector2, to: Vector2)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local fence = template("FarmFence")
	if fence then
		local low, high = worldBounds(fence)
		local section = high.X - low.X
		local sections = math.max(1, math.round(length / section))
		local direction = (to - from).Unit
		for i = 1, sections do
			local mid = from:Lerp(to, (i - 0.5) / sections)
			placeAsset("FarmFence", groundCFrame(mid, direction), nil, length / sections / section)
		end
		return
	end
	local count = math.max(1, math.ceil(length / FENCE_POST_SPACING))
	for i = 0, count do
		local p = from:Lerp(to, i / count)
		local y = groundAt(p.X, p.Y)
		part({ Name = "FencePost", Size = Vector3.new(0.7, FENCE_HEIGHT + 0.6, 0.7), CFrame = CFrame.new(p.X, y + FENCE_HEIGHT / 2, p.Y), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	end
	for i = 0, count - 1 do
		local a, b = from:Lerp(to, i / count), from:Lerp(to, (i + 1) / count)
		local mid = (a + b) / 2
		local y = groundAt(mid.X, mid.Y)
		for _, height in { FENCE_HEIGHT * 0.45, FENCE_HEIGHT * 0.85 } do
			local pa, pb = Vector3.new(a.X, y + height, a.Y), Vector3.new(b.X, y + height, b.Y)
			part({ Name = "FenceRail", Size = Vector3.new(0.3, 0.35, (pb - pa).Magnitude), CFrame = CFrame.lookAt((pa + pb) / 2, pb), Color = COLORS.Wood, Material = Enum.Material.Wood })
		end
	end
end

-- The fence ring, with gaps where roads leave town.
local function buildFence()
	local h = TownConfig.EdgeHalfSize
	local gap = TownConfig.FenceGap / 2
	-- Gaps on each side, from the roads that reach the edge.
	local gaps: { [string]: { number } } = { north = {}, south = {}, east = {}, west = {} }
	for _, road in TownConfig.Roads do
		if math.abs(road.To.Y) >= h - 1 then
			table.insert(gaps[if road.To.Y < 0 then "north" else "south"], road.To.X)
		elseif math.abs(road.To.X) >= h - 1 then
			table.insert(gaps[if road.To.X > 0 then "east" else "west"], road.To.Y)
		end
	end
	local function side(name: string, point: (number) -> Vector2)
		local cuts = gaps[name]
		table.sort(cuts)
		local start = -h
		for _, center in cuts do
			buildFenceRun(point(start), point(center - gap))
			start = center + gap
		end
		buildFenceRun(point(start), point(h))
	end
	side("north", function(t)
		return Vector2.new(t, -h)
	end)
	side("south", function(t)
		return Vector2.new(t, h)
	end)
	side("east", function(t)
		return Vector2.new(h, t)
	end)
	side("west", function(t)
		return Vector2.new(-h, t)
	end)
end

-- The wooden arch over the north road, signed both ways.
local function buildArch()
	local arch = TownConfig.Arch
	local half = arch.Width / 2
	local y = groundAt(arch.Position.X, arch.Position.Y)
	local center = Vector3.new(arch.Position.X, y, arch.Position.Y)
	for _, side in { -1, 1 } do
		part({ Name = "ArchPost", Size = Vector3.new(2.4, 16, 2.4), CFrame = CFrame.new(center + Vector3.new(side * half, 7, 0)), Color = COLORS.Wood, Material = Enum.Material.Wood })
		part({ Name = "ArchPostBase", Size = Vector3.new(3.4, 2, 3.4), CFrame = CFrame.new(center + Vector3.new(side * half, 0.5, 0)), Color = COLORS.Stone, Material = Enum.Material.Cobblestone })
		local lantern = part({ Name = "ArchLantern", Size = Vector3.new(1.2, 1.4, 1.2), CFrame = CFrame.new(center + Vector3.new(side * (half - 1.8), 12.5, 0)), Color = COLORS.LampGlow, Material = Enum.Material.Neon })
		addLight(lantern, 16)
	end
	part({ Name = "ArchBeam", Size = Vector3.new(arch.Width + 6, 1.6, 3), CFrame = CFrame.new(center + Vector3.new(0, 15, 0)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	part({ Name = "ArchCap", Size = Vector3.new(arch.Width + 8, 0.6, 3.6), CFrame = CFrame.new(center + Vector3.new(0, 16, 0)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	local signY = 13
	local inward = part({ Name = "ArchSign", Size = Vector3.new(arch.Width - 4, 2.2, 0.4), CFrame = CFrame.lookAt(center + Vector3.new(0, signY, 0.9), center + Vector3.new(0, signY, 10)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(inward, arch.Inward)
	local outward = part({ Name = "ArchSign", Size = Vector3.new(arch.Width - 4, 2.2, 0.4), CFrame = CFrame.lookAt(center + Vector3.new(0, signY, -0.9), center + Vector3.new(0, signY, -10)), Color = COLORS.DarkWood, Material = Enum.Material.Wood })
	addSign(outward, TownConfig.Name)
end

local function buildTree(x: number, z: number, scale: number, yaw: number)
	if placeAsset("Tree", groundCFrame(Vector2.new(x, z), Vector2.new(math.sin(yaw), math.cos(yaw))), nil, TREE_SCALE * scale) then
		return
	end
	local y = groundAt(x, z)
	cylinder("Trunk", 8 * scale, 1.8 * scale, CFrame.new(x, y + 3.5 * scale, z), COLORS.Trunk, Enum.Material.Wood)
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * 9 * scale, CFrame = CFrame.new(x, y + 9 * scale, z), Color = COLORS.Leaves, Material = Enum.Material.Grass })
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * 6 * scale, CFrame = CFrame.new(x + 1.5 * scale, y + 12 * scale, z - scale), Color = COLORS.DarkLeaves, Material = Enum.Material.Grass })
end

local function buildTrees()
	-- A fixed seed, so the trees look the same every server.
	local random = Random.new(7)
	for _, spot in TownConfig.Trees do
		buildTree(spot.X, spot.Y, 1, random:NextNumber(0, math.pi * 2))
	end
	-- Outside the fence.
	local h = TownConfig.EdgeHalfSize
	local placed, tries = 0, 0
	while placed < TownConfig.OutsideTrees and tries < TownConfig.OutsideTrees * 20 do
		tries += 1
		local x = random:NextNumber(-h - TownConfig.OutsideTreeReach, h + TownConfig.OutsideTreeReach)
		local z = random:NextNumber(-h - TownConfig.OutsideTreeReach, h + TownConfig.OutsideTreeReach)
		local outside = math.max(math.abs(x), math.abs(z)) > h + 8
		local onTrail = math.abs(x) < TownConfig.TrailClearance and z < 0
		local onRoad = math.abs(z) < 14 and math.abs(x) > h -- east/west road exits
		local inSafeZone = SafeZone.contains(Vector3.new(x, 0, z))
		if outside and not onTrail and not onRoad and inSafeZone then
			buildTree(x, z, random:NextNumber(0.8, 1.3), random:NextNumber(0, math.pi * 2))
			placed += 1
		end
	end
end

-- Adds `buildings` and `props` to the town already in workspace (the saved copy), leaving the
-- rest as it is: for putting new pieces of TownConfig into the place in edit mode without a
-- full rebuild (which would throw away hand edits). Returns the asset names that were missing.
function TownBuilder.add(buildings: { Building }, props: { Prop }): { string }
	local include: { Instance } = { workspace.Terrain }
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(include, baseplate)
	end
	groundParams.FilterDescendantsInstances = include
	local existing = workspace:FindFirstChild("Town")
	townFolder = if existing and existing:IsA("Folder") then existing else townFolder
	table.clear(missingAssets)
	for _, building in buildings do
		buildBuilding(building)
	end
	for _, prop in props do
		buildProp(prop)
	end
	townFolder.Parent = workspace
	local missing: { string } = {}
	for name in missingAssets do
		table.insert(missing, name)
	end
	return missing
end

-- Builds the town into workspace.Town. A Town already saved in the place is kept as it is
-- (so hand edits made in Studio's edit mode stay), unless `replace` is true: the edit-mode
-- tools (tools/preview_town.lua, tools/generate_terrain.lua) rebuild it from TownConfig.
function TownBuilder.build(replace: boolean?)
	if not replace and workspace:FindFirstChild("Town") then
		return
	end
	local include: { Instance } = { workspace.Terrain }
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(include, baseplate)
	end
	groundParams.FilterDescendantsInstances = include

	-- The town is built from TownConfig, replacing the saved copy. (SafeZoneBorder was the old
	-- pillar ring along the safe zone edge; it's no longer built.)
	for _, name in { "Town", "SafeZoneBorder" } do
		local saved = workspace:FindFirstChild(name)
		if saved then
			saved:Destroy()
		end
	end

	local baseY = groundAt(0, 0)
	clearGrass(baseY)
	buildPlaza(baseY)
	buildRoads()
	for _, building in TownConfig.Buildings do
		buildBuilding(building)
	end
	buildProps()
	buildLamps()
	buildFence()
	buildArch()
	buildTrees()
	townFolder.Parent = workspace

	local missing: { string } = {}
	for name in missingAssets do
		table.insert(missing, name)
	end
	if #missing > 0 then
		table.sort(missing)
		print(`[TownBuilder] Part-built (no model in assets/town yet): {table.concat(missing, ", ")}`)
	end
end

return TownBuilder
