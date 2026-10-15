--!strict
-- Builds a dungeon's rooms out of parts (DungeonConfig layout) for one run, and the cave mouth
-- that leads into it in the world. Looks only: DungeonService runs what happens in it.
--
-- A run's copy: the entry hall (a glowing way out on its back wall), then each room joined by
-- a corridor, then the round boss arena; dark stone, lit by torches. Every room's doorways have
-- an iron portcullis (a Gate) that DungeonService raises and drops.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonConfig = require(ReplicatedStorage.Shared.Config.DungeonConfig)

type Dungeon = DungeonConfig.Dungeon

export type Gate = { bars: { BasePart }, closed: { [BasePart]: CFrame }, isOpen: boolean }

export type Built = {
	folder: Folder,
	spawn: CFrame, -- where players arrive in the hall (facing in)
	exitPrompt: ProximityPrompt, -- the hall's way out
	-- Per room (DungeonConfig Rooms order): its doorway gates, and where its orcs drop in.
	roomGates: { { entry: Gate, exit: Gate } },
	orcSpawns: { { Vector3 } },
	arenaGate: Gate,
	arenaCenter: Vector3, -- on the floor
	bossSpot: CFrame, -- the boss's feet, facing the arena's doorway
	victorySpot: CFrame, -- where the way out appears once the boss is beaten
}

local T = 2 -- wall, floor and ceiling thickness
local GATE_TIME = 0.8 -- seconds to raise or drop a portcullis

local COLORS = {
	Floor = Color3.fromRGB(74, 66, 60),
	Wall = Color3.fromRGB(56, 51, 52),
	Ceiling = Color3.fromRGB(38, 35, 36),
	ArenaFloor = Color3.fromRGB(60, 50, 46),
	Lava = Color3.fromRGB(255, 110, 40),
	Iron = Color3.fromRGB(45, 45, 50),
	Wood = Color3.fromRGB(95, 64, 40),
	Flame = Color3.fromRGB(255, 150, 60),
	Portal = Color3.fromRGB(110, 190, 255),
	Rock = Color3.fromRGB(105, 100, 96),
	Void = Color3.fromRGB(8, 6, 6),
}

local DungeonBuilder = {}

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

-- A torch on a wall: a bracket, a flame and its light. `at` is the flame, `outward` points
-- away from the wall.
local function torch(parent: Instance, at: Vector3, outward: Vector3, fire: boolean)
	local frame = CFrame.lookAt(at, at + outward)
	part(parent, { Name = "Bracket", Size = Vector3.new(0.5, 0.5, 1.6), CFrame = frame * CFrame.new(0, -0.8, 0.6), Color = COLORS.Iron, Material = Enum.Material.Metal, CanCollide = false })
	local flame = part(parent, { Name = "Flame", Size = Vector3.new(0.7, 1, 0.7), CFrame = frame, Color = COLORS.Flame, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = COLORS.Flame
	light.Range = 26
	light.Brightness = 2.2
	light.Shadows = true
	light.Parent = flame
	if fire then
		local flames = Instance.new("Fire")
		flames.Size = 2.5
		flames.Heat = 6
		flames.Color = COLORS.Flame
		flames.SecondaryColor = Color3.fromRGB(255, 60, 20)
		flames.Parent = flame
	end
end

-- A box room on the floor at `origin`: floor, ceiling, side walls, and end walls with a doorway
-- on the open ends (`north` is the -Z end, `south` the +Z end). Corridors leave their ends open.
local function box(parent: Instance, origin: Vector3, center: Vector2, size: Vector2, height: number, ends: { north: boolean?, south: boolean?, open: boolean? }, dungeon: Dungeon)
	local c = origin + Vector3.new(center.X, 0, center.Y)
	part(parent, { Name = "Floor", Size = Vector3.new(size.X + 2 * T, T, size.Y + 2 * T), CFrame = CFrame.new(c + Vector3.new(0, -T / 2, 0)), Color = COLORS.Floor, Material = Enum.Material.Slate })
	part(parent, { Name = "Ceiling", Size = Vector3.new(size.X + 2 * T, T, size.Y + 2 * T), CFrame = CFrame.new(c + Vector3.new(0, height + T / 2, 0)), Color = COLORS.Ceiling, Material = Enum.Material.Rock })
	for _, side in { -1, 1 } do
		part(parent, { Name = "Wall", Size = Vector3.new(T, height, size.Y), CFrame = CFrame.new(c + Vector3.new(side * (size.X / 2 + T / 2), height / 2, 0)), Color = COLORS.Wall, Material = Enum.Material.Basalt })
	end
	if ends.open then
		return
	end
	for _, entry in { { z = -1, door = ends.north }, { z = 1, door = ends.south } } do
		local z = c.Z + entry.z * (size.Y / 2 + T / 2)
		if entry.door then
			local w, h = dungeon.DoorWidth, dungeon.DoorHeight
			local side = (size.X + 2 * T - w) / 2
			for _, s in { -1, 1 } do
				part(parent, { Name = "Wall", Size = Vector3.new(side, height, T), CFrame = CFrame.new(c.X + s * (w / 2 + side / 2), c.Y + height / 2, z), Color = COLORS.Wall, Material = Enum.Material.Basalt })
			end
			part(parent, { Name = "Lintel", Size = Vector3.new(w, height - h, T), CFrame = CFrame.new(c.X, c.Y + h + (height - h) / 2, z), Color = COLORS.Wall, Material = Enum.Material.Basalt })
		else
			part(parent, { Name = "Wall", Size = Vector3.new(size.X + 2 * T, height, T), CFrame = CFrame.new(c.X, c.Y + height / 2, z), Color = COLORS.Wall, Material = Enum.Material.Basalt })
		end
	end
end

-- An iron portcullis across the doorway centred on X/Z `at` (in the wall plane, across X).
local function gate(parent: Instance, at: Vector3, dungeon: Dungeon): Gate
	local w, h = dungeon.DoorWidth, dungeon.DoorHeight
	local model = Instance.new("Model")
	model.Name = "Gate"
	model.Parent = parent
	local bars: { BasePart } = {}
	local count = math.floor(w / 1.6)
	for i = 0, count do
		local x = -w / 2 + 0.3 + (w - 0.6) * i / count
		table.insert(bars, part(model, { Name = "Bar", Size = Vector3.new(0.45, h, 0.45), CFrame = CFrame.new(at + Vector3.new(x, h / 2, 0)), Color = COLORS.Iron, Material = Enum.Material.Metal }))
	end
	for _, y in { h * 0.3, h * 0.7 } do
		table.insert(bars, part(model, { Name = "Crossbar", Size = Vector3.new(w, 0.5, 0.6), CFrame = CFrame.new(at + Vector3.new(0, y, 0)), Color = COLORS.Iron, Material = Enum.Material.Metal }))
	end
	local closed = {}
	for _, bar in bars do
		closed[bar] = bar.CFrame
	end
	return { bars = bars, closed = closed, isOpen = false }
end

-- Raises (open) or drops (closed) a gate. `instant` skips the slide (while building).
function DungeonBuilder.setGate(gate: Gate, open: boolean, instant: boolean?)
	if gate.isOpen == open and not instant then
		return
	end
	gate.isOpen = open
	local lift = if open then Vector3.new(0, (gate.bars[1].Size.Y) + 1, 0) else Vector3.zero
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

-- A glowing doorway with a prompt (the ways out).
local function portal(parent: Instance, at: CFrame, objectText: string): ProximityPrompt
	local glow = part(parent, { Name = "Portal", Size = Vector3.new(8, 11, 0.4), CFrame = at * CFrame.new(0, 5.5, 0), Color = COLORS.Portal, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false })
	for _, s in { -1, 1 } do
		part(parent, { Name = "PortalPillar", Size = Vector3.new(1.5, 13, 1.5), CFrame = at * CFrame.new(s * 4.75, 6.5, 0), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	end
	part(parent, { Name = "PortalTop", Size = Vector3.new(11, 1.5, 1.5), CFrame = at * CFrame.new(0, 13.25, 0), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	local light = Instance.new("PointLight")
	light.Color = COLORS.Portal
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = glow
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Leave"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = glow
	return prompt
end

-- A brazier on the arena floor: a stone bowl of fire.
local function brazier(parent: Instance, at: Vector3)
	part(parent, { Name = "BrazierBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.5, 2.5), CFrame = CFrame.new(at + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Rock, Material = Enum.Material.Cobblestone })
	local bowl = part(parent, { Name = "Brazier", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 5, 5), CFrame = CFrame.new(at + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Iron, Material = Enum.Material.Metal })
	local coals = part(parent, { Name = "Coals", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.2, 4.2), CFrame = CFrame.new(at + Vector3.new(0, 5.25, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Lava, Material = Enum.Material.Neon, CanCollide = false })
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = COLORS.Flame
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = coals
	local light = Instance.new("PointLight")
	light.Color = COLORS.Flame
	light.Range = 45
	light.Brightness = 2.5
	light.Shadows = true
	light.Parent = bowl
end

-- Some orc clutter along a room's side walls: crates and a barrel.
local function clutter(parent: Instance, c: Vector3, size: Vector2, random: Random)
	for i = 1, 4 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (size.X / 2 - 3)
		local z = random:NextNumber(-size.Y / 2 + 8, size.Y / 2 - 8)
		local s = random:NextNumber(2.5, 4)
		part(parent, { Name = "Crate", Size = Vector3.new(s, s, s), CFrame = CFrame.new(c + Vector3.new(x, s / 2, z)) * CFrame.Angles(0, random:NextNumber(0, 1), 0), Color = COLORS.Wood, Material = Enum.Material.WoodPlanks })
	end
end

-- Builds `dungeon` for one run with its hall's floor centre at `origin`.
function DungeonBuilder.build(dungeon: Dungeon, origin: Vector3, name: string): Built
	local folder = Instance.new("Folder")
	folder.Name = name
	local random = Random.new(1)

	-- The hall: its back (+Z) wall holds the way out.
	local hall = dungeon.Hall
	box(folder, origin, hall.Center, hall.Size, hall.Height, { north = true }, dungeon)
	local hallC = origin + Vector3.new(hall.Center.X, 0, hall.Center.Y)
	local exitPrompt = portal(folder, CFrame.new(hallC + Vector3.new(0, 0, hall.Size.Y / 2 - 1)), dungeon.DisplayName)
	for _, side in { -1, 1 } do
		torch(folder, hallC + Vector3.new(side * (hall.Size.X / 2 - 0.6), 9, 0), Vector3.new(-side, 0, 0), true)
	end
	local spawn = CFrame.lookAt(hallC + Vector3.new(0, 3, hall.Size.Y / 2 - 9), hallC + Vector3.new(0, 3, -hall.Size.Y))

	-- Rooms and the corridors between them; each room's doorways get a gate.
	local roomGates, orcSpawns = {}, {}
	local previousEdge = hall.Center.Y - hall.Size.Y / 2 -- the -Z edge of the last piece
	local function corridor(toEdge: number)
		local length = previousEdge - toEdge
		local center = Vector2.new(0, (previousEdge + toEdge) / 2)
		box(folder, origin, center, Vector2.new(dungeon.CorridorWidth, length), dungeon.CorridorHeight, { open = true }, dungeon)
		local c = origin + Vector3.new(0, 0, center.Y)
		for _, side in { -1, 1 } do
			torch(folder, c + Vector3.new(side * (dungeon.CorridorWidth / 2 - 0.6), 8, 0), Vector3.new(-side, 0, 0), false)
		end
	end
	for _, room in dungeon.Rooms do
		local top = room.Center.Y + room.Size.Y / 2
		corridor(top)
		box(folder, origin, room.Center, room.Size, room.Height, { north = true, south = true }, dungeon)
		local c = origin + Vector3.new(room.Center.X, 0, room.Center.Y)
		local bottom = room.Center.Y - room.Size.Y / 2
		table.insert(roomGates, {
			entry = gate(folder, origin + Vector3.new(0, 0, top), dungeon),
			exit = gate(folder, origin + Vector3.new(0, 0, bottom), dungeon),
		})
		for _, side in { -1, 1 } do
			for _, z in { -room.Size.Y / 4, room.Size.Y / 4 } do
				torch(folder, c + Vector3.new(side * (room.Size.X / 2 - 0.6), 10, z), Vector3.new(-side, 0, 0), true)
			end
		end
		clutter(folder, c, room.Size, random)
		local spawns = {}
		local count = room.Orcs or 0
		for i = 1, count do
			local x = (if count > 1 then (i - 1) / (count - 1) - 0.5 else 0) * room.Size.X * 0.6
			table.insert(spawns, origin + Vector3.new(room.Center.X + x, 6, bottom + dungeon.OrcSpawnDepth))
		end
		table.insert(orcSpawns, spawns)
		previousEdge = bottom
	end

	-- The arena: a round room, its doorway on the +Z side.
	local arena = dungeon.Arena
	local arenaCenter = origin + Vector3.new(arena.Center.X, 0, arena.Center.Y)
	corridor(arena.Center.Y + arena.Radius)
	local R, H = arena.Radius, arena.Height
	part(folder, { Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(T, 2 * R + 2 * T, 2 * R + 2 * T), CFrame = CFrame.new(arenaCenter - Vector3.new(0, T / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.ArenaFloor, Material = Enum.Material.Basalt })
	part(folder, { Name = "LavaRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2 * R - 10, 2 * R - 10), CFrame = CFrame.new(arenaCenter + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Lava, Material = Enum.Material.CrackedLava, CanCollide = false })
	part(folder, { Name = "ArenaInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2 * R - 16, 2 * R - 16), CFrame = CFrame.new(arenaCenter + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.ArenaFloor, Material = Enum.Material.Slate, CanCollide = false })
	part(folder, { Name = "ArenaCeiling", Shape = Enum.PartType.Cylinder, Size = Vector3.new(T, 2 * R + 2 * T, 2 * R + 2 * T), CFrame = CFrame.new(arenaCenter + Vector3.new(0, H + T / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = COLORS.Ceiling, Material = Enum.Material.Rock })
	local segments = 32
	local segmentWidth = 2 * math.pi * (R + T / 2) / segments * 1.04
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local at = arenaCenter + outward * (R + T / 2)
		local frame = CFrame.lookAt(at, at + outward)
		if i == 0 then
			-- The doorway (+Z): a lintel over the gap.
			local h = dungeon.DoorHeight
			part(folder, { Name = "Lintel", Size = Vector3.new(segmentWidth, H - h, T), CFrame = frame + Vector3.new(0, h + (H - h) / 2, 0), Color = COLORS.Wall, Material = Enum.Material.Basalt })
		else
			part(folder, { Name = "ArenaWall", Size = Vector3.new(segmentWidth, H, T), CFrame = frame + Vector3.new(0, H / 2, 0), Color = COLORS.Wall, Material = Enum.Material.Basalt })
			if i % 4 == 2 then
				torch(folder, arenaCenter + outward * (R - 0.6) + Vector3.new(0, 12, 0), -outward, false)
			end
		end
	end
	local arenaGate = gate(folder, arenaCenter + Vector3.new(0, 0, R + T / 2), dungeon)
	for _, angle in { 45, 135, 225, 315 } do
		local a = math.rad(angle)
		brazier(folder, arenaCenter + Vector3.new(math.sin(a), 0, math.cos(a)) * (R * 0.62))
	end

	for _, gates in roomGates do
		DungeonBuilder.setGate(gates.entry, true, true)
		DungeonBuilder.setGate(gates.exit, false, true)
	end
	DungeonBuilder.setGate(arenaGate, true, true)

	return {
		folder = folder,
		spawn = spawn,
		exitPrompt = exitPrompt,
		roomGates = roomGates,
		orcSpawns = orcSpawns,
		arenaGate = arenaGate,
		arenaCenter = arenaCenter,
		bossSpot = CFrame.lookAt(arenaCenter - Vector3.new(0, 0, R * 0.25), arenaCenter + Vector3.new(0, 0, R)),
		victorySpot = CFrame.lookAt(arenaCenter - Vector3.new(0, 0, R - 6), arenaCenter),
	}
end

-- A way out that appears in the arena once the boss is beaten.
function DungeonBuilder.victoryPortal(built: Built, dungeon: Dungeon): ProximityPrompt
	return portal(built.folder, built.victorySpot, dungeon.DisplayName)
end

-- The cave mouth in the world: a rock arch over a black opening, torches either side, and the
-- "Enter" prompt at eye height in the mouth. `ground` is the floor of the mouth; it faces
-- `facing` (X/Z). Also returns the doorway: a part you walk into (not solid) to go in.
function DungeonBuilder.entrance(dungeon: Dungeon, ground: Vector3, parent: Instance): (ProximityPrompt, BasePart)
	local folder = Instance.new("Model")
	folder.Name = dungeon.Id .. "Entrance"
	local facing = Vector3.new(dungeon.EntranceFacing.X, 0, dungeon.EntranceFacing.Y).Unit
	local frame = CFrame.lookAt(ground, ground + facing) -- -Z (LookVector) points out of the cave
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, -z)
	end
	local w, h = 14, 16
	for _, s in { -1, 1 } do
		part(folder, { Name = "Pillar", Size = Vector3.new(8, h + 26, 10), CFrame = at(s * (w / 2 + 4), (h + 26) / 2 - 18, 0) * CFrame.Angles(0, 0, s * -0.06), Color = COLORS.Rock, Material = Enum.Material.Rock })
	end
	part(folder, { Name = "Lintel", Size = Vector3.new(w + 22, 9, 12), CFrame = at(0, h + 4, 0) * CFrame.Angles(0.04, 0, 0.03), Color = COLORS.Rock, Material = Enum.Material.Rock })
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

return DungeonBuilder
