--!strict
-- Builds a dungeon's maze (its DungeonConfig grid map, placed by DungeonGrid) for one run, and
-- the cave mouth that leads into it in the world. Looks only: DungeonService runs what happens
-- in it.
--
-- A run's copy: rock, floors and ceilings carved out of terrain (DungeonTerrain: rough slate
-- and cobbles in rooms and corridors, rock and dirt in the caves), named rooms with taller
-- ceilings, iron portcullises (Gates) that DungeonService raises and drops, torches along the
-- walls (fewer in the caves), chests, a glowing way out in the hall, and the round boss arena
-- north of the map. Props go where a ray finds the carved rock, since its walls are uneven.
--
-- Models: a prop found in ServerStorage.DungeonAssets (assets/dungeon, see its README) is used
-- in place of its stand-in built from parts: Chest, Torch, Crate, Brazier, Portcullis, CaveRocks,
-- CaveMouth (and Crystal, which has no stand-in: without it the caves just have none).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local DungeonConfig = require(ReplicatedStorage.Shared.Config.DungeonConfig)
local DungeonGrid = require(script.Parent.DungeonGrid)
local DungeonTerrain = require(script.Parent.DungeonTerrain)

type Dungeon = DungeonConfig.Dungeon
type Grid = DungeonGrid.Grid

export type Gate = { bars: { BasePart }, closed: { [BasePart]: CFrame }, lift: number, isOpen: boolean }

export type Chest = {
	prompt: ProximityPrompt,
	open: () -> (), -- swings the lid up (once)
	position: Vector3,
	front: Vector3, -- the way it faces (out from the wall)
}

-- A dungeon's layout saved in the place (workspace.DungeonLayouts, made by
-- tools/dungeon_layout.lua and edited by hand), taken out of the world when the server starts.
export type Layout = {
	terrain: TerrainRegion,
	decor: Folder,
	working: Folder?, -- gates, chests and the way out (an older layout without one gets them built)
	origin: Vector3, -- the grid origin it was built on
	regionLow: Vector3, -- its terrain's low corner
	regionSize: Vector3,
}

export type Built = {
	folder: Folder,
	terrain: DungeonTerrain.Region, -- the carved terrain (DungeonBuilder.clear puts it back)
	spawn: CFrame, -- where players arrive in the hall (facing in)
	exitPrompt: ProximityPrompt, -- the hall's way out
	-- Per room (DungeonConfig Rooms order): its gates, and where its orcs drop in.
	roomGates: { { Gate } },
	orcSpawns: { { Vector3 } },
	chests: { Chest },
	arenaGate: Gate,
	arenaCenter: Vector3, -- on the floor
	bossSpot: CFrame, -- the boss's feet, facing the arena's doorway
	victorySpot: CFrame, -- where the way out appears once the boss is beaten
}

local T = 2 -- floor and ceiling thickness, the arena's wall
local GATE_TIME = 0.8 -- seconds to raise or drop a portcullis
local LID_TIME = 0.6 -- seconds for a chest's lid to swing open

-- Torches: the chance a stretch of wall gets one, by where it is (none within 2 squares of another).
local TORCH_CHANCE = { Room = 0.4, Corridor = 0.22, Cave = 0.08 }
-- Wall torches cast no shadows: dozens of shadowed lights flicker in and out on weaker GPUs
-- (Future lighting renders only a few at once). The arena's braziers keep theirs.
local TORCH_LIGHT = { Range = 22, Brightness = 1.3 }
-- The arena's floor plates: solid slabs whose tops stand clear of the terrain floor's bumps
-- (its rendered surface wobbles about ±0.8 studs), so the two never fight through each other.
local ARENA_PLATE = { Top = 0.9, Thickness = 2 }
local BRAZIER_LIGHT = { Range = 38, Brightness = 1.6 }
local BOULDER_CHANCE = 0.35 -- a lump of rock bulging out of a cave wall
local CRATE_CHANCE = 0.12 -- per square along a room's walls
local CRYSTAL_CHANCE = 0.04 -- per square along a cave's walls (only with a Crystal asset)

local COLORS = {
	Floor = Color3.fromRGB(74, 66, 60),
	Wall = Color3.fromRGB(56, 51, 52),
	CaveRock = Color3.fromRGB(78, 72, 68),
	ArenaFloor = Color3.fromRGB(60, 50, 46),
	Lava = Color3.fromRGB(255, 110, 40),
	Iron = Color3.fromRGB(45, 45, 50),
	Wood = Color3.fromRGB(95, 64, 40),
	Gold = Color3.fromRGB(255, 200, 80),
	Flame = Color3.fromRGB(255, 150, 60),
	FireLight = Color3.fromRGB(235, 165, 115), -- torch and brazier light: dim and not too orange (a grim place)
	Portal = Color3.fromRGB(110, 190, 255),
	Rock = Color3.fromRGB(105, 100, 96),
	Void = Color3.fromRGB(8, 6, 6),
}

local DungeonBuilder = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

-- Where the carved rock is, from `from` along `direction` (nil if it's further).
local function wallHit(from: Vector3, direction: Vector3): Vector3?
	local result = workspace:Raycast(from, direction, terrainOnly)
	return if result then result.Position else nil
end

-- Sets a floor prop down on the terrain under its middle, sunk SETTLE_SINK: the carved floor
-- is bumpy (up to about a stud), and a bump poking into the bottom of a box doesn't show where
-- a gap under it would. Looks down from the prop's top (the open air: there may be an overhang
-- above it).
local SETTLE_SINK = 0.15
local function settle(thing: PVInstance)
	local frame: CFrame, size: Vector3
	if thing:IsA("Model") then
		frame, size = thing:GetBoundingBox()
	elseif thing:IsA("BasePart") then
		frame, size = thing.CFrame, thing.Size
	else
		return
	end
	local top = frame.Position.Y + size.Y / 2
	local hit = workspace:Raycast(Vector3.new(frame.Position.X, top, frame.Position.Z), Vector3.new(0, -(size.Y + 8), 0), terrainOnly)
	if hit then
		thing:PivotTo(thing:GetPivot() + Vector3.new(0, hit.Position.Y - SETTLE_SINK - (top - size.Y), 0))
	end
end

local function part(parent: Instance, props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part") :: any
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" then
			instance[key] = value
		end
	end
	instance.Parent = parent
	return instance
end

-- A copy of ServerStorage.DungeonAssets[name], anchored, its pivot at `at`; nil if there's none.
local function asset(parent: Instance, name: string, at: CFrame): Model?
	local folder = ServerStorage:FindFirstChild("DungeonAssets")
	local source = folder and folder:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		elseif descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	model:PivotTo(at)
	model.Parent = parent
	return model
end

local function light(parent: Instance, range: number, brightness: number, shadows: boolean)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = COLORS.FireLight
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = shadows
	pointLight.Parent = parent
end

local function fire(parent: Instance, size: number, heat: number)
	local flames = Instance.new("Fire")
	flames.Size = size
	flames.Heat = heat
	flames.Color = COLORS.Flame
	flames.SecondaryColor = Color3.fromRGB(255, 60, 20)
	flames.Parent = parent
end

-- A torch on a wall: a bracket, a flame and its light. `at` is the flame, `outward` points
-- away from the wall. The Torch asset is pivoted on the wall, facing out (+Z), with a
-- "Flame" attachment where the fire goes.
local function torch(parent: Instance, at: Vector3, outward: Vector3, burning: boolean)
	local frame = CFrame.lookAt(at, at + outward)
	local model = asset(parent, "Torch", frame * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.pi, 0))
	local flamePoint = model and model:FindFirstChild("Flame", true)
	if model and flamePoint and flamePoint:IsA("Attachment") then
		light(flamePoint, TORCH_LIGHT.Range, TORCH_LIGHT.Brightness, false)
		-- A torch with its own fire (particles) keeps it; otherwise the game lights it.
		if burning and not model:FindFirstChildWhichIsA("ParticleEmitter", true) then
			fire(flamePoint, 2.5, 6)
		end
		return
	end
	if model then
		model:Destroy()
	end
	part(parent, { Name = "Bracket", Size = Vector3.new(0.5, 0.5, 1.6), CFrame = frame * CFrame.new(0, -0.8, 0.6), Color = COLORS.Iron, Material = Enum.Material.Metal, CanCollide = false })
	local flame = part(parent, { Name = "Flame", Size = Vector3.new(0.7, 1, 0.7), CFrame = frame, Color = COLORS.Flame, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	light(flame, TORCH_LIGHT.Range, TORCH_LIGHT.Brightness, false)
	if burning then
		fire(flame, 2.5, 6)
	end
end

-- An iron portcullis `width` wide and `height` tall standing on `frame` (on the floor), across
-- its X axis, built as a Model marked for readWorking: attributes "Gate" (true), "Room" (the
-- DungeonConfig Rooms index that owns it, 0 for the arena's, -1 for none: always open),
-- "Squares" (the map squares it closes, "i,j,...", for orc routing) and "Lift" (studs it rises
-- to open). The Portcullis asset stands on the floor across its X axis: its child "Door" (a
-- model) is what lifts, anything else (a "Frame") stays put. It's made for a 14-wide passage; in
-- a narrower one its sides sink into the rock.
local function gate(parent: Instance, frame: CFrame, width: number, height: number, room: number, squares: { number }): Model
	local model = asset(parent, "Portcullis", frame)
	if model and not model:FindFirstChild("Door") then
		model:Destroy()
		model = nil
	end
	if not model then
		local built = Instance.new("Model")
		local door = Instance.new("Model")
		door.Name = "Door"
		door.Parent = built
		local count = math.floor(width / 1.6)
		for i = 0, count do
			local x = -width / 2 + 0.3 + (width - 0.6) * i / count
			part(door, { Name = "Bar", Size = Vector3.new(0.45, height, 0.45), CFrame = frame * CFrame.new(x, height / 2, 0), Color = COLORS.Iron, Material = Enum.Material.Metal })
		end
		for _, y in { height * 0.3, height * 0.7 } do
			part(door, { Name = "Crossbar", Size = Vector3.new(width, 0.5, 0.6), CFrame = frame * CFrame.new(0, y, 0), Color = COLORS.Iron, Material = Enum.Material.Metal })
		end
		built.WorldPivot = frame
		built.Parent = parent
		model = built
	end
	local gateModel = model :: Model
	gateModel.Name = "Gate"
	-- The carved rock is cut back past the passage's edges, so seal the gaps either side of it
	-- (always there: they're outside the passage).
	for _, s in { -1, 1 } do
		part(gateModel, { Name = "GateSeal", Size = Vector3.new(8, height + 8, 1.5), CFrame = frame * CFrame.new(s * (width / 2 + 4), (height + 8) / 2, 0), Transparency = 1, CanQuery = false })
	end
	local list = {}
	for _, square in squares do
		table.insert(list, tostring(square))
	end
	gateModel:SetAttribute("Gate", true)
	gateModel:SetAttribute("Room", room)
	gateModel:SetAttribute("Squares", table.concat(list, ","))
	gateModel:SetAttribute("Lift", height - 1)
	return gateModel
end

-- A gate model (see gate) as the game drives it: what lifts (its Door's parts) and how far.
local function readGate(model: Model, height: number): Gate
	local door = model:FindFirstChild("Door")
	local bars: { BasePart } = {}
	local closed = {}
	for _, descendant in (door or model):GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "GateSeal" then
			table.insert(bars, descendant)
			closed[descendant] = descendant.CFrame
		end
	end
	local lift = model:GetAttribute("Lift")
	return { bars = bars, closed = closed, lift = if typeof(lift) == "number" then lift else height - 1, isOpen = false }
end

-- Raises (open) or drops (closed) a gate. `instant` skips the slide (while building).
function DungeonBuilder.setGate(gate: Gate, open: boolean, instant: boolean?)
	if gate.isOpen == open and not instant then
		return
	end
	gate.isOpen = open
	local lift = if open then Vector3.new(0, gate.lift, 0) else Vector3.zero
	for _, bar in gate.bars do
		local goal = gate.closed[bar] + lift
		bar.CanCollide = not open
		if instant then
			bar.CFrame = goal
		else
			TweenService:Create(bar, TweenInfo.new(GATE_TIME, Enum.EasingStyle.Quad, if open then Enum.EasingDirection.Out else Enum.EasingDirection.In), { CFrame = goal }):Play()
		end
	end
end

-- A glowing doorway with a prompt (the ways out), a Model named `name`.
local function portal(parent: Instance, at: CFrame, objectText: string, name: string): ProximityPrompt
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = at
	model.Parent = parent
	parent = model
	local glow = part(parent, { Name = "Portal", Size = Vector3.new(8, 11, 0.4), CFrame = at * CFrame.new(0, 5.5, 0), Color = COLORS.Portal, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false })
	for _, s in { -1, 1 } do
		part(parent, { Name = "PortalPillar", Size = Vector3.new(1.5, 13, 1.5), CFrame = at * CFrame.new(s * 4.75, 6.5, 0), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	end
	part(parent, { Name = "PortalTop", Size = Vector3.new(11, 1.5, 1.5), CFrame = at * CFrame.new(0, 13.25, 0), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	local glowLight = Instance.new("PointLight")
	glowLight.Color = COLORS.Portal
	glowLight.Range = 18
	glowLight.Brightness = 1.5
	glowLight.Parent = glow
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Leave"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = glow
	return prompt
end

-- A brazier on the arena floor: a stone bowl of fire. The Brazier asset stands on the floor
-- with a "Flame" attachment over its bowl.
local function brazier(parent: Instance, at: Vector3)
	local model = asset(parent, "Brazier", CFrame.new(at))
	local flamePoint = model and model:FindFirstChild("Flame", true)
	if model and flamePoint and flamePoint:IsA("Attachment") then
		fire(flamePoint, 6, 9)
		light(flamePoint, BRAZIER_LIGHT.Range, BRAZIER_LIGHT.Brightness, true)
		return
	end
	if model then
		model:Destroy()
	end
	part(parent, { Name = "BrazierBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.5, 2.5), CFrame = CFrame.new(at + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	local bowl = part(parent, { Name = "Brazier", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 5, 5), CFrame = CFrame.new(at + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Iron, Material = Enum.Material.Metal })
	local coals = part(parent, { Name = "Coals", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.2, 4.2), CFrame = CFrame.new(at + Vector3.new(0, 5.25, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Lava, Material = Enum.Material.Neon, CanCollide = false })
	fire(coals, 6, 9)
	light(bowl, BRAZIER_LIGHT.Range, BRAZIER_LIGHT.Brightness, true)
end

-- A chest on the floor at `frame`, its front toward LookVector, built as a Model marked
-- "Chest" (attribute) for readWorking, pivoted on the floor with +Z out of its front. The Chest
-- asset stands on the floor facing +Z with its lid a child named "Lid" (a part or a model)
-- pivoted on the hinge; it swings up about its X axis.
local function chest(parent: Instance, frame: CFrame): Model
	local front = frame * CFrame.Angles(0, math.pi, 0) -- +Z toward whoever walks up
	local model = asset(parent, "Chest", front)
	if not model then
		local box = Instance.new("Model")
		part(box, { Name = "Body", Size = Vector3.new(4.4, 2.4, 3), CFrame = front * CFrame.new(0, 1.2, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
		for _, x in { -1.5, 1.5 } do
			part(box, { Name = "Band", Size = Vector3.new(0.4, 2.5, 3.1), CFrame = front * CFrame.new(x, 1.2, 0), Color = COLORS.Iron, Material = Enum.Material.Metal })
		end
		local hinge = front * CFrame.new(0, 2.4, -1.5)
		local lidModel = Instance.new("Model")
		lidModel.Name = "Lid"
		part(lidModel, { Name = "Top", Size = Vector3.new(4.6, 1, 3.2), CFrame = hinge * CFrame.new(0, 0.5, 1.6), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
		part(lidModel, { Name = "Lock", Size = Vector3.new(0.7, 0.8, 0.3), CFrame = front * CFrame.new(0, 2.6, 1.75), Color = COLORS.Gold, Material = Enum.Material.Metal })
		lidModel.WorldPivot = hinge
		lidModel.Parent = box
		box.WorldPivot = front
		box.Parent = parent
		model = box
	end
	local box = model :: Model
	box.Name = "Chest"
	box:SetAttribute("Chest", true)
	part(box, { Name = "PromptAnchor", Size = Vector3.one, CFrame = front * CFrame.new(0, 2.5, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	settle(box)
	return box
end

-- A chest model (see chest) as the game drives it: a fresh "Open" prompt on its PromptAnchor
-- (made if it's missing), and its Lid swinging up about the lid's pivot.
local function readChest(model: Model): Chest
	local pivot = model:GetPivot()
	local found = model:FindFirstChild("Lid")
	local lid: PVInstance? = if found and found:IsA("PVInstance") then found else nil
	local hinge = if lid then lid:GetPivot() else pivot
	local anchor = model:FindFirstChild("PromptAnchor")
	if not anchor or not anchor:IsA("BasePart") then
		anchor = part(model, { Name = "PromptAnchor", Size = Vector3.one, CFrame = pivot * CFrame.new(0, 2.5, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	end
	for _, old in (anchor :: BasePart):GetChildren() do
		if old:IsA("ProximityPrompt") then
			old:Destroy()
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Chest"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local opened = false
	local function open()
		if opened then
			return
		end
		opened = true
		prompt.Enabled = false
		local glow = Instance.new("PointLight")
		glow.Color = COLORS.Gold
		glow.Range = 10
		glow.Brightness = 2
		glow.Parent = anchor
		if not lid then
			return
		end
		local swing = Instance.new("NumberValue")
		swing:GetPropertyChangedSignal("Value"):Connect(function()
			(lid :: PVInstance):PivotTo(hinge * CFrame.Angles(math.rad(-swing.Value), 0, 0))
		end)
		local tween = TweenService:Create(swing, TweenInfo.new(LID_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 105 })
		tween.Completed:Once(function()
			swing:Destroy()
		end)
		tween:Play()
	end
	return { prompt = prompt, open = open, position = pivot.Position, front = -pivot.LookVector }
end

-- A crate against a wall: `at` is on the floor at the wall, `outward` away from it.
local function crate(parent: Instance, at: Vector3, outward: Vector3, random: Random)
	local s = random:NextNumber(2.5, 4)
	local spot = at + outward * (s / 2 + 0.4)
	local frame = CFrame.lookAt(spot, spot + outward) * CFrame.Angles(0, random:NextNumber(-0.4, 0.4), 0)
	-- (The Crate asset's pivot may be its middle or its bottom: settle puts it on the floor.)
	settle(asset(parent, "Crate", frame) or part(parent, { Name = "Crate", Size = Vector3.new(s, s, s), CFrame = frame + Vector3.new(0, s / 2, 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks }))
end

-- A lump of rock `size` across centred on `at`: one of the CaveRocks asset's children (rock
-- parts or models), scaled and turned at random, or a ball of rock without it.
local function boulder(parent: Instance, at: Vector3, size: number, random: Random)
	local folder = ServerStorage:FindFirstChild("DungeonAssets")
	local rocks = folder and folder:FindFirstChild("CaveRocks")
	local choices = if rocks then rocks:GetChildren() else {}
	local source = if #choices > 0 then choices[random:NextInteger(1, #choices)] else nil
	if source and (source:IsA("BasePart") or source:IsA("Model")) then
		local model = Instance.new("Model")
		model.Name = "Boulder"
		local rock = source:Clone()
		rock.Parent = model
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			elseif descendant:IsA("BaseScript") or descendant:IsA("Light") or descendant:IsA("ParticleEmitter") then
				descendant:Destroy()
			end
		end
		local _, extents = model:GetBoundingBox()
		model:ScaleTo(size / math.max(extents.X, extents.Y, extents.Z))
		local turn = CFrame.Angles(random:NextNumber(0, math.pi * 2), random:NextNumber(0, math.pi * 2), random:NextNumber(0, math.pi * 2))
		model:PivotTo(CFrame.new(at) * turn * (model:GetBoundingBox():Inverse() * model:GetPivot()))
		model.Parent = parent
		return
	end
	part(parent, { Name = "Boulder", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(at), Color = COLORS.CaveRock, Material = Enum.Material.Rock })
end

-- A crystal cluster on a cave floor against a wall (the Crystal asset: pivot at the bottom
-- middle, its back -Z against the wall). Nothing without the asset.
local function crystal(parent: Instance, at: Vector3, outward: Vector3, random: Random)
	local frame = CFrame.lookAt(at, at + outward) * CFrame.Angles(0, math.pi + random:NextNumber(-0.5, 0.5), 0)
	local model = asset(parent, "Crystal", frame)
	if model then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
			end
		end
	end
end

-- A block over the squares of `rect`, from `bottom` to `top` (heights above the floor).
local function block(parent: Instance, grid: Grid, rect: { number }, bottom: number, top: number, props: { [string]: any }): BasePart
	local a = DungeonGrid.position(grid, rect[1], rect[2])
	local b = DungeonGrid.position(grid, rect[3], rect[4])
	props.Size = Vector3.new((rect[3] - rect[1] + 1) * grid.cell, top - bottom, (rect[4] - rect[2] + 1) * grid.cell)
	props.CFrame = CFrame.new((a + b) / 2 + Vector3.new(0, (bottom + top) / 2, 0))
	return part(parent, props)
end

-- The room (DungeonConfig Rooms index) a square is in, if any.
function DungeonBuilder.roomAt(dungeon: Dungeon, c: number, r: number): number?
	for index, room in dungeon.Rooms do
		if c >= room.From.X and c <= room.To.X and r >= room.From.Y and r <= room.To.Y then
			return index
		end
	end
	return nil
end

-- Which way a marker square backs onto rock (the first wall found), or nil.
local function wallBehind(grid: Grid, c: number, r: number): Vector2?
	for _, d in { Vector2.new(0, 1), Vector2.new(0, -1), Vector2.new(1, 0), Vector2.new(-1, 0) } do
		if DungeonGrid.isRock(DungeonGrid.char(grid, c + d.X, r + d.Y)) then
			return d
		end
	end
	return nil
end

-- The arena's doorway: the middle of its A squares, the arena's middle, and how many A squares.
local function arenaPlace(grid: Grid, dungeon: Dungeon): (Vector3, Vector3, number)
	local doorway = DungeonGrid.find(grid, "A")
	local doorCenter = Vector3.zero
	for _, spot in doorway do
		doorCenter += DungeonGrid.position(grid, spot.X, spot.Y)
	end
	doorCenter = if #doorway > 0 then doorCenter / #doorway else grid.origin
	return doorCenter, doorCenter - Vector3.new(0, 0, grid.cell / 2 + dungeon.Arena.Radius + T), #doorway
end

-- The passage from the A squares into the arena (low and high corner, on the floor).
function DungeonBuilder.arenaPassage(grid: Grid, dungeon: Dungeon): { Vector3 }
	local doorCenter, arenaCenter, squares = arenaPlace(grid, dungeon)
	local half = math.max(squares, 1) * grid.cell / 2
	return {
		Vector3.new(doorCenter.X - half, 0, arenaCenter.Z + dungeon.Arena.Radius - 1),
		Vector3.new(doorCenter.X + half, 0, doorCenter.Z),
	}
end

-- Points across every gate (each '+' square, and the arena's doorway), on the floor.
function DungeonBuilder.gatePoints(grid: Grid, dungeon: Dungeon): { Vector3 }
	local points = {}
	for _, spot in DungeonGrid.find(grid, "+") do
		table.insert(points, DungeonGrid.position(grid, spot.X, spot.Y))
	end
	local doorCenter, arenaCenter, squares = arenaPlace(grid, dungeon)
	local gateZ = arenaCenter.Z + dungeon.Arena.Radius + T / 2
	for k = 1, math.max(squares, 1) do
		table.insert(points, Vector3.new(doorCenter.X + (k - (squares + 1) / 2) * grid.cell, doorCenter.Y, gateZ))
	end
	return points
end

-- The working parts where the map puts them (needs the run's terrain in place, to find the
-- walls): a Folder of gates (one per run of '+' squares, across the passage, owned by the room
-- it touches; and the arena's), chests (C, backed against a wall) and the way out (E: an
-- "Exit" model). All marked for readWorking, so a hand-edited copy works just the same.
function DungeonBuilder.buildWorking(dungeon: Dungeon, grid: Grid): Folder
	local working = Instance.new("Folder")
	working.Name = "Working"
	local cell, H = grid.cell, dungeon.Height

	local seen: { [number]: boolean } = {}
	for i, char in grid.chars do
		if char ~= "+" or seen[i] then
			continue
		end
		local squares = {}
		local queue = { i }
		seen[i] = true
		while #queue > 0 do
			local j = table.remove(queue) :: number
			table.insert(squares, j)
			local c, r = DungeonGrid.square(grid, j)
			for _, d in DungeonGrid.Directions do
				local k = DungeonGrid.index(grid, c + d.X, r + d.Y)
				if k and grid.chars[k] == "+" and not seen[k] then
					seen[k] = true
					table.insert(queue, k)
				end
			end
		end
		local sum, owner = Vector3.zero, nil
		local firstC, firstR = DungeonGrid.square(grid, squares[1])
		local across = true -- spans X (the passage runs north-south)
		for _, j in squares do
			local c, r = DungeonGrid.square(grid, j)
			sum += DungeonGrid.position(grid, c, r)
			across = across and r == firstR
			for _, d in DungeonGrid.Directions do
				owner = owner or DungeonBuilder.roomAt(dungeon, c + d.X, r + d.Y)
			end
		end
		if #squares == 1 then
			across = DungeonGrid.isRock(DungeonGrid.char(grid, firstC - 1, firstR)) or DungeonGrid.isRock(DungeonGrid.char(grid, firstC + 1, firstR))
		end
		if not owner then
			warn(`[DungeonBuilder] {dungeon.Id}: a gate at square {firstC},{firstR} touches no room; it stays open`)
		end
		local center = sum / #squares
		local frame = if across then CFrame.new(center) else CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0)
		gate(working, frame, #squares * cell, H, owner or -1, squares)
	end

	local _, arenaCenter, doorSquares = arenaPlace(grid, dungeon)
	gate(working, CFrame.new(arenaCenter + Vector3.new(0, 0, dungeon.Arena.Radius + T / 2)), math.max(doorSquares, 1) * cell, H, 0, {})

	for _, spot in DungeonGrid.find(grid, "E") do
		local back = wallBehind(grid, spot.X, spot.Y) or Vector2.new(0, 1)
		local toWall = Vector3.new(back.X, 0, back.Y)
		local base = DungeonGrid.position(grid, spot.X, spot.Y)
		local hit = wallHit(base + Vector3.new(0, 3, 0), toWall * cell * 1.5)
		local at = if hit then Vector3.new(hit.X, base.Y, hit.Z) - toWall else base + toWall * (cell / 2 - 1)
		local prompt = portal(working, CFrame.lookAt(at, at + toWall), dungeon.DisplayName, "Exit")
		local model = prompt:FindFirstAncestorOfClass("Model")
		if model then
			model:SetAttribute("Exit", true)
		end
	end

	for _, spot in DungeonGrid.find(grid, "C") do
		local back = wallBehind(grid, spot.X, spot.Y) or Vector2.new(0, -1)
		local toWall = Vector3.new(back.X, 0, back.Y)
		local base = DungeonGrid.position(grid, spot.X, spot.Y)
		local hit = wallHit(base + Vector3.new(0, 1.5, 0), toWall * cell * 1.5)
		local at = if hit then Vector3.new(hit.X, base.Y, hit.Z) - toWall * 2 else base + toWall * (cell / 2 - 2)
		chest(working, CFrame.lookAt(at, at - toWall))
	end
	return working
end

-- Reads a working Folder (buildWorking's, or a saved layout's copy) for the run: every model in
-- it marked "Gate" (by its Room: a room's, the arena's, or none), "Chest" or "Exit", wherever
-- it stands now. Room gates start open, the arena's shut. A missing arena gate is built where
-- the map puts it.
local function readWorking(dungeon: Dungeon, grid: Grid, working: Folder): ({ { Gate } }, Gate, { Chest }, ProximityPrompt?)
	local H = dungeon.Height
	local roomGates: { { Gate } } = {}
	for index in dungeon.Rooms do
		roomGates[index] = {}
	end
	local arenaGate: Gate? = nil
	local chests: { Chest } = {}
	local exitPrompt: ProximityPrompt? = nil
	for _, model in working:GetDescendants() do
		if not model:IsA("Model") then
			continue
		end
		if model:GetAttribute("Gate") then
			local g = readGate(model, H)
			local squares = model:GetAttribute("Squares")
			for square in string.gmatch(if typeof(squares) == "string" then squares else "", "%d+") do
				grid.gateOf[tonumber(square) :: number] = g
			end
			local room = model:GetAttribute("Room")
			if room == 0 and not arenaGate then
				arenaGate = g
				DungeonBuilder.setGate(g, false, true) -- sealed until the war rooms are cleared
			else
				DungeonBuilder.setGate(g, true, true)
				if typeof(room) == "number" and roomGates[room] then
					table.insert(roomGates[room], g)
				end
			end
		elseif model:GetAttribute("Chest") then
			table.insert(chests, readChest(model))
		elseif model:GetAttribute("Exit") and not exitPrompt then
			local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
			if not prompt then
				local glow = model:FindFirstChild("Portal", true) or model:FindFirstChildWhichIsA("BasePart", true)
				if glow then
					local made = Instance.new("ProximityPrompt")
					made.ActionText = "Leave"
					made.HoldDuration = 0.5
					made.MaxActivationDistance = 10
					made.RequiresLineOfSight = false
					made.Parent = glow
					prompt = made
				end
			end
			if prompt then
				prompt.ObjectText = dungeon.DisplayName
				prompt.Enabled = true
				exitPrompt = prompt
			end
		end
	end
	if not arenaGate then
		local _, arenaCenter, doorSquares = arenaPlace(grid, dungeon)
		local model = gate(working, CFrame.new(arenaCenter + Vector3.new(0, 0, dungeon.Arena.Radius + T / 2)), math.max(doorSquares, 1) * grid.cell, H, 0, {})
		arenaGate = readGate(model, H)
		DungeonBuilder.setGate(arenaGate :: Gate, false, true)
	end
	return roomGates, arenaGate :: Gate, chests, exitPrompt
end

-- Moves everything in a Decor or Working folder by `offset` (each model or part on its own, so
-- they stay separate things to click on in Studio, like workspace.Town's).
local function shift(container: Instance, offset: Vector3)
	for _, child in container:GetChildren() do
		if child:IsA("PVInstance") then
			child:PivotTo(child:GetPivot() + offset)
		elseif child:IsA("Folder") then
			shift(child, offset)
		end
	end
end

-- Builds `dungeon` for one run on `grid` (DungeonGrid.new for this run's origin). With a
-- `layout` (the copy saved in the place, see loadLayout) its terrain and Decor are copied in;
-- without one they're generated. Either way the working parts (gates, chests, the way out)
-- are built here, where the map puts them.
function DungeonBuilder.build(dungeon: Dungeon, grid: Grid, name: string, layout: Layout?): Built
	local folder = Instance.new("Folder")
	folder.Name = name
	local random = Random.new(1) -- every run looks the same
	local cell = grid.cell
	local H = dungeon.Height
	local function inRoom(i: number): number?
		local c, r = DungeonGrid.square(grid, i)
		return DungeonBuilder.roomAt(dungeon, c, r)
	end

	-- The arena: a round room north of the map, its doorway (+Z) on the A squares.
	local _, arenaCenter = arenaPlace(grid, dungeon)
	local R = dungeon.Arena.Radius

	-- Rock, floors and ceilings: terrain, carved round the map's open squares, the arena and the
	-- passage between them (or the saved layout's). Decor: everything that's only looks.
	local terrain: DungeonTerrain.Region
	local decor: Folder
	if layout then
		local offset = grid.origin - layout.origin
		terrain = DungeonTerrain.paste(layout.terrain, layout.regionLow + offset, layout.regionSize)
		decor = layout.decor:Clone()
		for _, descendant in decor:GetDescendants() do
			if descendant:IsA("BaseScript") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		shift(decor, offset)
	else
		terrain = DungeonTerrain.carve(dungeon, grid, arenaCenter, DungeonBuilder.arenaPassage(grid, dungeon), DungeonBuilder.gatePoints(grid, dungeon))
		decor = Instance.new("Folder")
	end
	decor.Name = "Decor"
	decor.Parent = folder

	-- Fake walls: rock you walk through, a shade lighter than the real thing.
	for _, spot in if layout then {} else DungeonGrid.find(grid, "?") do
		local i = DungeonGrid.index(grid, spot.X, spot.Y) :: number
		local color = if grid.cave[i] then COLORS.CaveRock else COLORS.Wall
		-- Oversized, to cover where the carved rock round it is cut back.
		local fake = block(decor, grid, { spot.X, spot.Y, spot.X, spot.Y }, 0, H, { Name = "FakeWall", Color = color:Lerp(Color3.new(1, 1, 1), 0.06), Material = if grid.cave[i] then Enum.Material.Rock else Enum.Material.Slate, CanCollide = false, CanQuery = false })
		fake.Size += Vector3.new(7, 6, 7)
		fake.CFrame += Vector3.new(0, 3, 0)
	end

	-- The working parts: gates, chests and the way out, the saved layout's (moved and edited by
	-- hand, maybe) or built where the map puts them, then read back the same way.
	local working: Folder
	if layout and layout.working then
		working = layout.working:Clone()
		for _, descendant in working:GetDescendants() do
			if descendant:IsA("BaseScript") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		shift(working, grid.origin - layout.origin)
	else
		working = DungeonBuilder.buildWorking(dungeon, grid)
	end
	working.Name = "Working"
	working.Parent = folder
	local roomGates, arenaGate, chests, exitPrompt = readWorking(dungeon, grid, working)

	-- Torches along the walls, a crate here and there in the rooms, rock bulging out of the
	-- cave walls.
	local lit: { [number]: boolean } = {}
	local function nearTorch(c: number, r: number): boolean
		for dr = -2, 2 do
			for dc = -2, 2 do
				local j = DungeonGrid.index(grid, c + dc, r + dr)
				if j and lit[j] then
					return true
				end
			end
		end
		return false
	end
	for i, char in grid.chars do
		if layout or char == "#" or char == "?" or char == "+" or char == "E" then
			continue
		end
		local c, r = DungeonGrid.square(grid, i)
		local roomIndex = inRoom(i)
		local center = DungeonGrid.position(grid, c, r)
		for _, d in DungeonGrid.Directions do
			if not DungeonGrid.isRock(DungeonGrid.char(grid, c + d.X, r + d.Y)) then
				continue
			end
			local toWall = Vector3.new(d.X, 0, d.Y)
			local reach = toWall * cell * 1.5
			-- The rock face at `height` above this square's floor (it's uneven), on the floor.
			local function face(height: number, along: Vector3?): Vector3?
				local hit = wallHit(center + (along or Vector3.zero) + Vector3.new(0, height, 0), reach)
				return if hit then Vector3.new(hit.X, center.Y, hit.Z) else nil
			end
			local chance = if roomIndex then TORCH_CHANCE.Room elseif grid.cave[i] then TORCH_CHANCE.Cave else TORCH_CHANCE.Corridor
			if not lit[i] and not nearTorch(c, r) and random:NextNumber() < chance then
				local height = if roomIndex then 11 else 9
				local wall = face(height)
				if wall then
					lit[i] = true
					torch(decor, wall - toWall * 0.6 + Vector3.new(0, height, 0), -toWall, roomIndex ~= nil)
				end
			elseif grid.cave[i] and random:NextNumber() < BOULDER_CHANCE then
				local s = random:NextNumber(3.5, 6)
				local along = Vector3.new(d.Y, 0, d.X) * random:NextNumber(-cell / 3, cell / 3)
				local height = random:NextNumber(0.5, H - 3)
				local wall = face(height, along)
				if wall then
					boulder(decor, wall + toWall * s * 0.2 + Vector3.new(0, height, 0), s, random)
				end
			elseif grid.cave[i] and char == "," and random:NextNumber() < CRYSTAL_CHANCE then
				local wall = face(1)
				if wall then
					crystal(decor, wall, -toWall, random)
				end
			elseif roomIndex and char == "." and random:NextNumber() < CRATE_CHANCE then
				local wall = face(1.5)
				if wall then
					crate(decor, wall, -toWall, random)
				end
			end
		end
	end

	-- Where players arrive.
	local start = DungeonGrid.find(grid, "S")[1] or Vector2.new(1, 1)
	local startAt = DungeonGrid.position(grid, start.X, start.Y) + Vector3.new(0, 3, 0)
	local spawn = CFrame.lookAt(startAt, startAt - Vector3.zAxis)

	-- Where each war room's orcs drop in.
	local orcSpawns: { { Vector3 } } = {}
	for index in dungeon.Rooms do
		orcSpawns[index] = {}
	end
	for _, spot in DungeonGrid.find(grid, "O") do
		local index = DungeonBuilder.roomAt(dungeon, spot.X, spot.Y)
		if index then
			table.insert(orcSpawns[index], DungeonGrid.position(grid, spot.X, spot.Y) + Vector3.new(0, 6, 0))
		else
			warn(`[DungeonBuilder] {dungeon.Id}: an orc at square {spot.X},{spot.Y} isn't in a room; left out`)
		end
	end

	-- Decor in the arena: its floor markings, torches round its wall and braziers (the room
	-- itself is carved in the terrain).
	if not layout then
		local plateY = ARENA_PLATE.Top - ARENA_PLATE.Thickness / 2
		part(decor, { Name = "LavaRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(ARENA_PLATE.Thickness, 2 * R - 10, 2 * R - 10), CFrame = CFrame.new(arenaCenter + Vector3.new(0, plateY - 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Lava, Material = Enum.Material.CrackedLava })
		part(decor, { Name = "ArenaInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(ARENA_PLATE.Thickness, 2 * R - 16, 2 * R - 16), CFrame = CFrame.new(arenaCenter + Vector3.new(0, plateY, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.ArenaFloor, Material = Enum.Material.Slate })
		for i = 2, 30, 4 do
			local angle = i / 32 * math.pi * 2
			local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local hit = wallHit(arenaCenter + Vector3.new(0, 12, 0), outward * (R + 12))
			if hit then
				torch(decor, hit - outward * 0.6, -outward, false)
			end
		end
		for _, angle in { 45, 135, 225, 315 } do
			local a = math.rad(angle)
			brazier(decor, arenaCenter + Vector3.new(math.sin(a), 0, math.cos(a)) * (R * 0.62) + Vector3.new(0, ARENA_PLATE.Top, 0)) -- on the floor plate
		end
	end

	if not exitPrompt then
		warn(`[DungeonBuilder] {dungeon.Id}: no way out (an E on the map, or an Exit in the layout); putting one at the start`)
		exitPrompt = portal(working, spawn - Vector3.new(0, 3, 0), dungeon.DisplayName, "Exit")
	end

	return {
		folder = folder,
		terrain = terrain,
		spawn = spawn,
		exitPrompt = exitPrompt :: ProximityPrompt,
		roomGates = roomGates,
		orcSpawns = orcSpawns,
		chests = chests,
		arenaGate = arenaGate,
		arenaCenter = arenaCenter,
		bossSpot = CFrame.lookAt(arenaCenter - Vector3.new(0, 0, R * 0.25), arenaCenter + Vector3.new(0, 0, R)),
		victorySpot = CFrame.lookAt(arenaCenter - Vector3.new(0, 0, R - 6), arenaCenter),
	}
end

-- For Studio (tools/dungeon_layout.lua): builds `dungeon` on `grid` as an editable layout, a
-- Folder with its Decor (looks) and Working (gates, chests, the way out), both copied into every
-- run as they're saved: move, restyle, copy or delete anything in them.
function DungeonBuilder.buildLayout(dungeon: Dungeon, grid: Grid): Folder
	local built = DungeonBuilder.build(dungeon, grid, dungeon.Id)
	for _, prompt in built.folder:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt:Destroy() -- the game makes its own
		end
	end
	-- Saved shut: a run takes each door's saved place as where it closes.
	for _, gates in built.roomGates do
		for _, g in gates do
			DungeonBuilder.setGate(g, false, true)
		end
	end
	DungeonBuilder.setGate(built.arenaGate, false, true)
	local region = built.terrain
	built.folder:SetAttribute("Origin", grid.origin)
	built.folder:SetAttribute("RegionLow", region.cframe.Position - region.size / 2)
	built.folder:SetAttribute("RegionSize", region.size)
	return built.folder
end

-- The saved layout's terrain region (from its attributes), if it has them.
function DungeonBuilder.layoutRegion(saved: Instance): DungeonTerrain.Region?
	local low, size = saved:GetAttribute("RegionLow"), saved:GetAttribute("RegionSize")
	if typeof(low) ~= "Vector3" or typeof(size) ~= "Vector3" then
		return nil
	end
	return { cframe = CFrame.new(low + size / 2), size = size }
end

-- Takes a saved layout out of the world (its terrain and the folder) and returns it for runs.
-- Its Decor and Working are Folders (an older save's Models are read the same way).
local function asFolder(container: Instance?): Folder?
	if not container then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = container.Name
	for _, child in container:GetChildren() do
		child:Clone().Parent = folder
	end
	return folder
end

function DungeonBuilder.loadLayout(saved: Instance): Layout?
	local origin = saved:GetAttribute("Origin")
	local region = DungeonBuilder.layoutRegion(saved)
	local decor = saved:FindFirstChild("Decor")
	local working = saved:FindFirstChild("Working")
	if typeof(origin) ~= "Vector3" or not region or not decor then
		warn(`[DungeonBuilder] the saved layout {saved:GetFullName()} is missing its Decor folder or attributes; generating runs instead`)
		return nil
	end
	local layout: Layout = {
		terrain = DungeonTerrain.copy(region),
		decor = asFolder(decor) :: Folder,
		working = asFolder(working),
		origin = origin,
		regionLow = region.cframe.Position - region.size / 2,
		regionSize = region.size,
	}
	DungeonTerrain.clear(region)
	saved:Destroy()
	return layout
end

-- Takes a run's copy down: its parts and its carved terrain.
function DungeonBuilder.clear(built: Built)
	built.folder:Destroy()
	DungeonTerrain.clear(built.terrain)
end

-- A way out that appears in the arena once the boss is beaten.
function DungeonBuilder.victoryPortal(built: Built, dungeon: Dungeon): ProximityPrompt
	return portal(built.folder, built.victorySpot, dungeon.DisplayName, "VictoryPortal")
end

-- The cave mouth in the world: a rock arch over a black opening, torches either side, and the
-- "Enter" prompt at eye height in the mouth. `ground` is the floor of the mouth; it faces
-- `facing` (X/Z). Also returns the doorway: a part you walk into (not solid) to go in.
function DungeonBuilder.entrance(dungeon: Dungeon, ground: Vector3, parent: Instance): (ProximityPrompt, BasePart)
	local folder = Instance.new("Folder")
	folder.Name = dungeon.Id .. "Entrance"
	local facing = Vector3.new(dungeon.EntranceFacing.X, 0, dungeon.EntranceFacing.Y).Unit
	local frame = CFrame.lookAt(ground, ground + facing) -- -Z (LookVector) points out of the cave
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, -z)
	end
	local w, h = 14, 16
	-- The CaveMouth asset (the rock arch) stands on the ground in the middle of the opening,
	-- facing out (+Z), the opening about w × h.
	if not asset(folder, "CaveMouth", frame * CFrame.Angles(0, math.pi, 0)) then
		for _, s in { -1, 1 } do
			part(folder, { Name = "Pillar", Size = Vector3.new(8, h + 26, 10), CFrame = at(s * (w / 2 + 4), (h + 26) / 2 - 18, 0) * CFrame.Angles(0, 0, s * -0.06), Color = COLORS.Rock, Material = Enum.Material.Rock })
		end
		part(folder, { Name = "Lintel", Size = Vector3.new(w + 22, 9, 12), CFrame = at(0, h + 4, 0) * CFrame.Angles(0.04, 0, 0.03), Color = COLORS.Rock, Material = Enum.Material.Rock })
	end
	part(folder, { Name = "Mound", Size = Vector3.new(w + 26, h + 30, 26), CFrame = at(0, (h + 30) / 2 - 18, -18), Color = COLORS.Rock, Material = Enum.Material.Rock })
	local random = Random.new(7)
	for _ = 1, 7 do
		local s = random:NextNumber(10, 20)
		part(folder, { Name = "Boulder", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), CFrame = at(random:NextNumber(-24, 24), random:NextNumber(4, h + 14), random:NextNumber(-30, -8)), Color = COLORS.Rock, Material = Enum.Material.Rock })
	end
	part(folder, { Name = "Back", Size = Vector3.new(w, h, 1), CFrame = at(0, h / 2, -6), Color = COLORS.Void, Material = Enum.Material.SmoothPlastic })
	local doorway = part(folder, { Name = "Opening", Size = Vector3.new(w, h, 4), CFrame = at(0, h / 2, -2.5), Color = COLORS.Void, Material = Enum.Material.SmoothPlastic, Transparency = 0.15, CanCollide = false })
	local anchor = part(folder, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = at(0, 4.5, 1), Transparency = 1, CanCollide = false, CanQuery = false })
	part(folder, { Name = "Threshold", Size = Vector3.new(w + 4, 2, 10), CFrame = at(0, -0.9, 2), Color = COLORS.Floor, Material = Enum.Material.Slate })
	for _, s in { -1, 1 } do
		torch(folder, (at(s * (w / 2 + 1.5), 9, 1.2)).Position, facing, true)
	end
	-- Skulls on stakes either side: orc country.
	for _, s in { -1, 1 } do
		part(folder, { Name = "Stake", Size = Vector3.new(0.6, 7, 0.6), CFrame = at(s * (w / 2 + 6), 3, 6), Color = COLORS.Wood, Material = Enum.Material.Wood })
		part(folder, { Name = "Skull", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = at(s * (w / 2 + 6), 7, 6), Color = Color3.fromRGB(225, 215, 190), Material = Enum.Material.SmoothPlastic })
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter"
	prompt.ObjectText = `{dungeon.DisplayName} ({dungeon.Recommended})`
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	folder.Parent = parent
	return prompt, doorway
end

-- A cave mouth saved in the place (workspace.DungeonLayouts, `<Id>Entrance`, made by
-- tools/dungeon_layout.lua and placed and edited by hand): its prompt (in "PromptAnchor"), its
-- doorway ("Opening": walking into it goes in; it also says where the ground is and which way
-- the mouth faces), and that ground spot facing out of the cave. Nil if it's missing a part.
function DungeonBuilder.savedEntrance(dungeon: Dungeon, model: Instance): (ProximityPrompt?, BasePart?, CFrame?)
	local opening = model:FindFirstChild("Opening", true)
	local anchor = model:FindFirstChild("PromptAnchor", true)
	if not opening or not opening:IsA("BasePart") or not anchor then
		warn(`[DungeonBuilder] {model:GetFullName()} needs parts named Opening and PromptAnchor; building the entrance from the config instead`)
		return nil, nil, nil
	end
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Enter"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
	end
	prompt.ObjectText = `{dungeon.DisplayName} ({dungeon.Recommended})`
	prompt.Enabled = true
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	-- The Opening stands 2.5 studs in from the ground spot, its bottom on the ground.
	local frame = opening.CFrame * CFrame.new(0, -opening.Size.Y / 2, -2.5)
	local ground = frame.Position
	return prompt, opening, CFrame.lookAt(ground, ground + Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z))
end

return DungeonBuilder
