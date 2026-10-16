--!strict
-- Brings Beginning Town to life on this screen (looks and sounds only):
--   * cloth marked "Sway" (flags, banners, washing) swings in the wind; models marked "Spin"
--     (the windmill's sails) turn about their pivot's look direction;
--   * the blacksmith works the anvil by day (clangs and sparks), the campfire crackles;
--   * birdsong by day and crickets at night (hushed in a dungeon run); the bell tower tolls at dawn and dusk;
--   * little flocks of birds peck about TownConfig.BirdSpots and fly off when you come close,
--     coming back a while later.
-- Things further than ANIMATE_RANGE from the camera are left still; Quality shortens that range
-- (nothing sways on Low) and hides the birds on Low.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local LightingConfig = require(ReplicatedStorage.Shared.Config.LightingConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local Quality = require(script.Parent.Quality)

local ANIMATE_RANGE = 180 -- studs from the camera
local WIND_SPEED = 1.7 -- radians per second of the sway
local ANVIL_GAP = { 1.4, 3.5 } -- seconds between hammer blows
local ANVIL_RANGE = 120 -- studs: further away you don't hear the forge
local BIRDS_PER_FLOCK = 4
local BIRD_SCARE_RANGE = 11 -- studs: closer than this and they fly off
local BIRD_RETURN = { 20, 35 } -- seconds before a flock that flew off lands again
local BIRD_FLIGHT = 4 -- seconds a scared bird flies before vanishing
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local player = Players.LocalPlayer

local TownAmbience = {}

type Swaying = { part: BasePart, rest: CFrame, amount: number, phase: number }
type Spinning = { model: Model, rest: CFrame, speed: number }
local swaying: { [BasePart]: Swaying } = {}
local spinning: { [Model]: Spinning } = {}
local random = Random.new()

local function cameraPosition(): Vector3?
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Sway and spin ---------------------------------------------------------------------------

local function watch(descendant: Instance)
	if descendant:IsA("BasePart") then
		local amount = descendant:GetAttribute("Sway")
		if typeof(amount) == "number" then
			local p = descendant.Position
			swaying[descendant] = { part = descendant, rest = descendant.CFrame, amount = amount, phase = p.X * 0.13 + p.Z * 0.07 }
		end
	elseif descendant:IsA("Model") then
		local speed = descendant:GetAttribute("Spin")
		if typeof(speed) == "number" then
			spinning[descendant] = { model = descendant, rest = descendant:GetPivot(), speed = speed }
		end
	end
end

local function unwatch(descendant: Instance)
	if descendant:IsA("BasePart") then
		swaying[descendant] = nil
	elseif descendant:IsA("Model") then
		spinning[descendant] = nil
	end
end

local function animateScenery(now: number, eye: Vector3, range: number)
	if range <= 0 then
		return
	end
	for _, item in swaying do
		if (item.rest.Position - eye).Magnitude <= range then
			local half = item.part.Size.Y / 2
			local t = now * WIND_SPEED + item.phase
			-- Hinged at its top edge: a slow swing with a little flutter on top.
			local swing = (math.sin(t) * 0.7 + math.sin(t * 2.9) * 0.3) * item.amount
			local twist = math.sin(t * 0.8 + 1) * item.amount * 0.35
			item.part.CFrame = item.rest * CFrame.new(0, half, 0) * CFrame.Angles(swing, 0, twist) * CFrame.new(0, -half, 0)
		end
	end
	for _, item in spinning do
		if (item.rest.Position - eye).Magnitude <= range * 1.5 then
			item.model:PivotTo(item.rest * CFrame.Angles(0, 0, now * item.speed))
		end
	end
end

-- Sounds ----------------------------------------------------------------------------------

local function loop(name: string, parent: Instance, maxDistance: number?): Sound?
	local sound = Sounds.create(name, parent)
	if not sound then
		return nil
	end
	sound.Looped = true
	if maxDistance then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = maxDistance
	end
	sound:Play()
	return sound
end

-- The first part in workspace.Town matching `test` (it may not have streamed in yet).
local function findInTown(test: (Instance) -> boolean): BasePart?
	local town = workspace:FindFirstChild("Town")
	if not town then
		return nil
	end
	for _, descendant in town:GetDescendants() do
		if descendant:IsA("BasePart") and test(descendant) then
			return descendant
		end
	end
	return nil
end

local function sparkEmitter(parent: BasePart): ParticleEmitter
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 110, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Rate = 0
	sparks.Parent = parent
	return sparks
end

local function startSounds()
	-- Birdsong by day, crickets by night: everywhere, fading with the time of day.
	local birds = loop("BirdsDay", SoundService)
	local crickets = loop("CricketsNight", SoundService)
	local birdVolume = if birds then birds.Volume else 0
	local cricketVolume = if crickets then crickets.Volume else 0

	local campfire: BasePart? = nil
	local anvil: BasePart? = nil
	local sparks: ParticleEmitter? = nil
	local bell: BasePart? = nil
	local nextClang = 0
	local wasNight = DayCycle.isNight()

	while true do
		local clock = DayCycle.clock()
		local night = DayCycle.night(clock)
		local outside = if typeof(player:GetAttribute("Dungeon")) == "string" then 0 else 1 -- none in a dungeon
		if birds then
			birds.Volume = birdVolume * (1 - night) * outside
		end
		if crickets then
			crickets.Volume = cricketVolume * night * outside
		end

		-- Places in town (looked up until they've streamed in).
		if not campfire or not campfire.Parent then
			campfire = findInTown(function(part)
				return part:FindFirstChildOfClass("Fire") ~= nil and part.Name ~= "Coals"
			end)
			if campfire then
				loop("FireCrackle", campfire, 70)
			end
		end
		if not anvil or not anvil.Parent then
			anvil = findInTown(function(part)
				return part.Name == "Anvil"
			end)
			sparks = if anvil then sparkEmitter(anvil) else nil
		end
		if not bell or not bell.Parent then
			bell = findInTown(function(part)
				return part:GetAttribute("Bell") == true
			end)
		end

		-- The blacksmith hammers away by day.
		local now = os.clock()
		local eye = cameraPosition()
		if anvil and sparks and night < 0.5 and now >= nextClang then
			nextClang = now + random:NextNumber(ANVIL_GAP[1], ANVIL_GAP[2])
			if eye and (anvil.Position - eye).Magnitude <= ANVIL_RANGE then
				local names = { "AnvilClang", "AnvilClang2", "AnvilClang3" }
				Sounds.play(names[random:NextInteger(1, #names)], anvil, random:NextNumber(0.95, 1.05))
				sparks:Emit(math.max(1, math.round(random:NextInteger(8, 16) * Quality.settings().Particles)))
			end
		end

		-- The bell tolls as night falls and as day breaks.
		local isNight = night >= LightingConfig.DayCycle.LightsOn
		if isNight ~= wasNight then
			wasNight = isNight
			if bell then
				local toll = Sounds.create("BellToll", bell)
				if toll then
					toll.RollOffMaxDistance = 700
					toll.Ended:Connect(function()
						toll:Destroy()
					end)
					toll:Play()
				end
			end
		end
		task.wait(0.25)
	end
end

-- Birds -----------------------------------------------------------------------------------

type Bird = {
	model: Model,
	parts: { [BasePart]: CFrame }, -- each part's offset from the body
	wings: { { part: BasePart, side: number } },
	head: BasePart,
	position: Vector3,
	yaw: number,
	hopUntil: number,
	nextHop: number,
	hopFrom: Vector3,
	hopTo: Vector3,
	flyDirection: Vector3?,
}
type Flock = { spot: Vector3, birds: { Bird }, scaredAt: number?, returnAt: number }

local BIRD_COLORS = { Color3.fromRGB(120, 90, 70), Color3.fromRGB(110, 110, 120), Color3.fromRGB(150, 110, 80) }

local function groundAt(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain, workspace:FindFirstChild("Town") or workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position.Y else 0
end

local function makeBird(parent: Instance): Bird
	local model = Instance.new("Model")
	model.Name = "Bird"
	local color = BIRD_COLORS[random:NextInteger(1, #BIRD_COLORS)]
	local parts: { [BasePart]: CFrame } = {}
	local function piece(name: string, size: Vector3, offset: CFrame, partColor: Color3): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = partColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		parts[part] = offset
		return part
	end
	piece("Body", Vector3.new(0.45, 0.4, 0.7), CFrame.new(0, 0.3, 0), color)
	local head = piece("Head", Vector3.new(0.32, 0.32, 0.32), CFrame.new(0, 0.6, -0.36), color)
	piece("Beak", Vector3.new(0.1, 0.08, 0.18), CFrame.new(0, 0.57, -0.6), Color3.fromRGB(230, 170, 60))
	piece("Tail", Vector3.new(0.3, 0.08, 0.35), CFrame.new(0, 0.42, 0.48) * CFrame.Angles(math.rad(20), 0, 0), color:Lerp(Color3.new(0, 0, 0), 0.3))
	local wings = {}
	for _, side in { -1, 1 } do
		local wing = piece("Wing", Vector3.new(0.06, 0.3, 0.5), CFrame.new(side * 0.25, 0.35, 0.02), color:Lerp(Color3.new(0, 0, 0), 0.2))
		table.insert(wings, { part = wing, side = side })
	end
	model.Parent = parent
	return {
		model = model,
		parts = parts,
		wings = wings,
		head = head,
		position = Vector3.zero,
		yaw = 0,
		hopUntil = 0,
		nextHop = 0,
		hopFrom = Vector3.zero,
		hopTo = Vector3.zero,
		flyDirection = nil,
	}
end

local function land(flock: Flock, bird: Bird, now: number)
	local angle, distance = random:NextNumber(0, math.pi * 2), random:NextNumber(0, 3.5)
	local x, z = flock.spot.X + math.cos(angle) * distance, flock.spot.Z + math.sin(angle) * distance
	bird.position = Vector3.new(x, groundAt(x, z), z)
	bird.yaw = random:NextNumber(0, math.pi * 2)
	bird.hopUntil = 0
	bird.nextHop = now + random:NextNumber(0.5, 3)
	bird.flyDirection = nil
end

local function poseBird(bird: Bird, now: number)
	local body = CFrame.new(bird.position) * CFrame.Angles(0, bird.yaw, 0)
	local flying = bird.flyDirection ~= nil
	local flap = if flying then math.sin(now * 40) * 1.1 else 0
	local peck = if not flying and math.sin(now * 3 + bird.yaw * 5) > 0.75 then math.rad(40) else 0
	for part, offset in bird.parts do
		local cframe = body * offset
		if part == bird.head then
			cframe = body * CFrame.new(0, 0.45, -0.2) * CFrame.Angles(-peck, 0, 0) * CFrame.new(0, 0.15, -0.16)
		elseif part.Name == "Beak" then
			cframe = body * CFrame.new(0, 0.45, -0.2) * CFrame.Angles(-peck, 0, 0) * CFrame.new(0, 0.12, -0.4)
		end
		part.CFrame = cframe
	end
	for _, wing in bird.wings do
		local hinge = body * CFrame.new(wing.side * 0.22, 0.45, 0)
		wing.part.CFrame = hinge * CFrame.Angles(0, 0, wing.side * (if flying then 1.2 + flap else 0.15)) * CFrame.new(wing.side * 0.03, -0.12, 0)
	end
end

local function updateFlock(flock: Flock, now: number, dt: number, scare: Vector3?)
	if flock.scaredAt == nil and scare and (Vector3.new(scare.X, flock.spot.Y, scare.Z) - flock.spot).Magnitude <= BIRD_SCARE_RANGE + 3 then
		-- Off they go, each its own way, up and away from you.
		flock.scaredAt = now
		flock.returnAt = now + random:NextNumber(BIRD_RETURN[1], BIRD_RETURN[2])
		Sounds.play("WingFlaps", flock.birds[1].head)
		for _, bird in flock.birds do
			local away = Vector3.new(bird.position.X - scare.X, 0, bird.position.Z - scare.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
			local turn = CFrame.Angles(0, random:NextNumber(-0.6, 0.6), 0)
			bird.flyDirection = (turn:VectorToWorldSpace(away) + Vector3.new(0, random:NextNumber(0.5, 0.9), 0)).Unit
			bird.yaw = math.atan2(-away.X, -away.Z)
		end
	end
	if flock.scaredAt then
		if now - flock.scaredAt > BIRD_FLIGHT then
			for _, bird in flock.birds do
				bird.model.Parent = nil
			end
		end
		if now >= flock.returnAt and not (scare and (Vector3.new(scare.X, flock.spot.Y, scare.Z) - flock.spot).Magnitude <= BIRD_SCARE_RANGE * 2) then
			flock.scaredAt = nil
			for _, bird in flock.birds do
				bird.model.Parent = workspace.CurrentCamera
				land(flock, bird, now)
			end
		end
	end
	for _, bird in flock.birds do
		if bird.model.Parent == nil then
			continue
		end
		local direction = bird.flyDirection
		if direction then
			bird.position += direction * dt * 22
		elseif now < bird.hopUntil then
			local t = 1 - (bird.hopUntil - now) / 0.25
			bird.position = bird.hopFrom:Lerp(bird.hopTo, t) + Vector3.new(0, math.sin(t * math.pi) * 0.4, 0)
		elseif now >= bird.nextHop then
			-- A little hop to a spot nearby (staying near the flock's spot).
			local angle = random:NextNumber(0, math.pi * 2)
			local to = bird.position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(0.6, 1.4)
			local fromSpot = Vector3.new(to.X - flock.spot.X, 0, to.Z - flock.spot.Z)
			if fromSpot.Magnitude > 4 then
				to = Vector3.new(flock.spot.X, 0, flock.spot.Z) + fromSpot.Unit * 3.5
			end
			to = Vector3.new(to.X, groundAt(to.X, to.Z), to.Z)
			bird.hopFrom, bird.hopTo = bird.position, to
			bird.hopUntil = now + 0.25
			bird.nextHop = now + random:NextNumber(0.8, 3.5)
			bird.yaw = math.atan2(-(to.X - bird.position.X), -(to.Z - bird.position.Z))
		end
		poseBird(bird, now)
	end
end

local function startBirds(): { Flock }
	local flocks: { Flock } = {}
	local camera = workspace.CurrentCamera
	for _, spot in TownConfig.BirdSpots do
		local flock: Flock = { spot = Vector3.new(spot.X, groundAt(spot.X, spot.Y), spot.Y), birds = {}, scaredAt = nil, returnAt = 0 }
		for _ = 1, BIRDS_PER_FLOCK do
			table.insert(flock.birds, makeBird(camera))
		end
		for _, bird in flock.birds do
			land(flock, bird, os.clock())
		end
		table.insert(flocks, flock)
	end
	return flocks
end

function TownAmbience.start()
	task.spawn(function()
		local town = workspace:WaitForChild("Town")
		town.DescendantAdded:Connect(watch)
		town.DescendantRemoving:Connect(unwatch)
		for _, descendant in town:GetDescendants() do
			watch(descendant)
		end
	end)
	task.spawn(startSounds)

	local flocks: { Flock }? = nil
	local birdsShown = true
	-- Birds come and go with the Quality tier (none on Low).
	local function showBirds(shown: boolean)
		birdsShown = shown
		if not flocks then
			return
		end
		local now = os.clock()
		for _, flock in flocks do
			flock.scaredAt = nil
			for _, bird in flock.birds do
				bird.model.Parent = if shown then workspace.CurrentCamera else nil
				if shown then
					land(flock, bird, now)
				end
			end
		end
	end
	task.delay(3, function()
		flocks = startBirds() -- once the town has had a moment to stream in under them
		showBirds(Quality.settings().Birds)
	end)
	Quality.onChange(function(settings)
		if settings.Birds ~= birdsShown then
			showBirds(settings.Birds)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local eye = cameraPosition()
		if not eye then
			return
		end
		local now = os.clock()
		local range = math.min(ANIMATE_RANGE, Quality.settings().AmbienceRange)
		animateScenery(now, eye, range)
		if flocks and birdsShown then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local scare = if root and root:IsA("BasePart") then root.Position else nil
			for _, flock in flocks do
				if (flock.spot - eye).Magnitude <= ANIMATE_RANGE then
					updateFlock(flock, now, dt, scare)
				end
			end
		end
	end)
end

return TownAmbience
