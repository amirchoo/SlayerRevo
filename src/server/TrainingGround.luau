--!strict
-- Training Grounds: a floating arena for working on combat, away from the hub.
-- West side: wooden dummies that reset after "dying" (for testing damage).
-- East side: a sparring ring with one demon behind a low wall (for testing dodging);
-- players can jump the wall, enemies never jump. A grid on the floor marks every
-- 10 studs for judging ranges. Teleport pads link the arena and the hub plaza.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)
local HealthService = require(script.Parent.HealthService)
local EnemyService = require(script.Parent.EnemyService)

local CENTER = TrainingArea.CENTER
local HALF = TrainingArea.HALF_SIZE

local DUMMY_MAX_HEALTH = 500
local DUMMY_RESET_DELAY = 1.5
local DUMMY_POSITIONS = { -45, -30, -15 } -- X offsets, in a row along the north side
local DUMMY_ROW_Z = -30

local DIVIDER_X = 10 -- the sparring ring is everything east of this line
local DIVIDER_HEIGHT = 4 -- low enough for players to jump (default jump clears ~7 studs)
local SPARRING_SPAWN = Vector2.new(CENTER.X + 40, CENTER.Z)

local GRID_SPACING = 10
local PAD_COOLDOWN = 2
local HUB_PAD = Vector2.new(-14, 16) -- X/Z in the hub plaza, beside the spawn

local COLORS = {
	Floor = Color3.fromRGB(70, 72, 78),
	Grid = Color3.fromRGB(95, 98, 106),
	Wall = Color3.fromRGB(110, 105, 95),
	Post = Color3.fromRGB(105, 70, 45),
	Sack = Color3.fromRGB(196, 170, 120),
	Pad = Color3.fromRGB(90, 170, 255),
	Glow = Color3.fromRGB(255, 200, 120),
	Text = Color3.fromRGB(250, 235, 200),
}

local TrainingGround = {}

local folder = Instance.new("Folder")
folder.Name = "TrainingGround"

local dummies: { [Model]: boolean } = {}
local lastTeleport: { [Player]: number } = {}

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
	instance.Parent = props.Parent or folder
	return instance
end

local function addLabel(adornee: BasePart, text: string, offsetY: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 120
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = COLORS.Text
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	return label
end

local function buildArena()
	part({ Name = "Floor", Size = Vector3.new(HALF * 2, 4, HALF * 2), CFrame = CFrame.new(CENTER - Vector3.new(0, 2, 0)), Color = COLORS.Floor, Material = Enum.Material.Slate })

	-- Grid lines every GRID_SPACING studs, for judging attack ranges.
	for offset = -HALF + GRID_SPACING, HALF - GRID_SPACING, GRID_SPACING do
		local y = CENTER.Y + 0.02
		part({ Name = "GridLine", Size = Vector3.new(0.2, 0.04, HALF * 2), CFrame = CFrame.new(CENTER.X + offset, y, CENTER.Z), Color = COLORS.Grid, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false })
		part({ Name = "GridLine", Size = Vector3.new(HALF * 2, 0.04, 0.2), CFrame = CFrame.new(CENTER.X, y, CENTER.Z + offset), Color = COLORS.Grid, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false })
	end

	-- Outer walls, tall enough that nobody falls off.
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local size = if side.X ~= 0 then Vector3.new(1, 10, HALF * 2) else Vector3.new(HALF * 2, 10, 1)
		part({ Name = "Wall", Size = size, CFrame = CFrame.new(CENTER + side * HALF + Vector3.new(0, 5, 0)), Color = COLORS.Wall, Material = Enum.Material.Cobblestone })
	end

	-- Corner lanterns.
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
		local base = CENTER + corner * (HALF - 3)
		part({ Name = "LampPost", Size = Vector3.new(0.6, 10, 0.6), CFrame = CFrame.new(base + Vector3.new(0, 5, 0)), Color = COLORS.Post, Material = Enum.Material.Wood })
		local lantern = part({ Name = "Lantern", Size = Vector3.new(1.4, 1.6, 1.4), CFrame = CFrame.new(base + Vector3.new(0, 10.8, 0)), Color = COLORS.Glow, Material = Enum.Material.Neon })
		local light = Instance.new("PointLight")
		light.Color = COLORS.Glow
		light.Range = 40
		light.Brightness = 1.5
		light.Parent = lantern
	end

	-- Low divider between the dummies and the sparring ring.
	local divider = part({ Name = "SparringDivider", Size = Vector3.new(1, DIVIDER_HEIGHT, HALF * 2), CFrame = CFrame.new(CENTER + Vector3.new(DIVIDER_X, DIVIDER_HEIGHT / 2, 0)), Color = COLORS.Wall, Material = Enum.Material.Cobblestone })
	addLabel(divider, "Sparring Ring (jump over) ►", DIVIDER_HEIGHT / 2 + 2)
end

local function buildDummy(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Training Dummy"

	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
	part({ Name = "Post", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 0.8, 0.8), CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * upright, Color = COLORS.Post, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 4.5, 0)) * upright, Color = COLORS.Sack, Material = Enum.Material.Fabric, Parent = model })
	local arms = part({ Name = "Arms", Size = Vector3.new(4.5, 0.6, 0.6), CFrame = CFrame.new(position + Vector3.new(0, 5.2, 0)), Color = COLORS.Post, Material = Enum.Material.Wood, Parent = model })
	local head = part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, CFrame = CFrame.new(position + Vector3.new(0, 6.9, 0)), Color = COLORS.Sack, Material = Enum.Material.Fabric, Parent = model })
	-- An unrotated part, so the model's bounding box stays upright (used to place damage numbers).
	model.PrimaryPart = arms
	model.Parent = folder

	local label = addLabel(head, "", 2)
	local function updateLabel()
		local health, maxHealth = HealthService.getHealth(model)
		if health and maxHealth then
			label.Text = if health > 0 then `{math.ceil(health)} / {maxHealth}` else "Resetting..."
		end
	end
	model:GetAttributeChangedSignal("Health"):Connect(updateLabel)

	dummies[model] = true
	HealthService.register(model, DUMMY_MAX_HEALTH)
	updateLabel()
end

-- A pad that teleports any player who steps on it to `destination`.
local function buildPad(position: Vector3, text: string, destination: CFrame)
	local pad = part({ Name = "TeleportPad", Size = Vector3.new(6, 0.4, 6), CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)), Color = COLORS.Pad, Material = Enum.Material.Neon })
	addLabel(pad, text, 3)

	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character or not character:IsA("Model") then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player or not HealthService.isAlive(character) then
			return
		end
		local now = os.clock()
		if now - (lastTeleport[player] or 0) < PAD_COOLDOWN then
			return
		end
		lastTeleport[player] = now
		character:PivotTo(destination)
	end)
end

-- Height of whatever is at X/Z in the hub (plaza, terrain, ...), ignoring characters and our own parts.
local function hubGroundAt(x: number, z: number): number
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	return if result then result.Position.Y else 0
end

local function buildPads()
	local hubPad = Vector3.new(HUB_PAD.X, hubGroundAt(HUB_PAD.X, HUB_PAD.Y), HUB_PAD.Y)
	local arenaPad = CENTER + Vector3.new(-40, 0, 45)

	-- Arrive beside the other pad (not on it), facing somewhere useful.
	local arenaArrival = CENTER + Vector3.new(-20, 3, 40)
	local dummyRow = CENTER + Vector3.new(-30, 3, DUMMY_ROW_Z)
	buildPad(hubPad, "Training Grounds", CFrame.lookAt(arenaArrival, Vector3.new(dummyRow.X, arenaArrival.Y, dummyRow.Z)))

	local hubArrival = hubPad + Vector3.new(0, 3, -8)
	buildPad(arenaPad, "Return to Hub", CFrame.lookAt(hubArrival, Vector3.new(0, hubArrival.Y, 0)))
end

function TrainingGround.build()
	buildArena()
	for _, x in DUMMY_POSITIONS do
		buildDummy(CENTER + Vector3.new(x, 0, DUMMY_ROW_Z))
	end
	buildPads()
	folder.Parent = workspace

	-- Dummies never stay dead: refill their health shortly after they "die".
	HealthService.Died:Connect(function(model: Model)
		if dummies[model] then
			task.delay(DUMMY_RESET_DELAY, function()
				HealthService.register(model, DUMMY_MAX_HEALTH)
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)

	task.spawn(EnemyService.spawnAt, SPARRING_SPAWN)
end

return TrainingGround
