--!strict
-- The town's animal NPCs (NpcConfig.Pets, e.g. Bonnie the cat): rigged models with their own
-- skeleton and clips, from ServerStorage.NpcModels (assets/npcs). Each is scaled to its
-- Height and rigged like the wildlife (AnimalService): an invisible HumanoidRootPart under
-- the body carries a Humanoid, so it walks with MoveTo, and the model is welded to it. The
-- client poses its bones from clip data (PetAnimator), so the import's AnimationController
-- and clips (AnimSaves) are removed: nothing else may move the bones.
--
-- The server decides what each pet is doing and publishes it as the model's "PetState"
-- attribute (Idle, Walking, Loafing, Sleeping, Playing); the client plays that state's clip,
-- swings the legs while walking and moves the eyelids (PetAnimator). "PetId" is its
-- NpcConfig.Pets Id. Pets have no Health attribute, so they can't be hurt.
--
-- Behaviour (NpcConfig.PetBehaviour): stand idle a few seconds, then (by the Next weights)
-- walk to a random spot in its Wander area, loaf or nap for a while, or keep standing. Its
-- "Pet" prompt stops it, turns it to face the player, and makes it play for PlayTime; the
-- player gets its Blessing buff (BuffService) and a short cutscene of it (PetCutscene remote:
-- the pet's model and the buff's id, to that player). One pet per PetCooldown per player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local BuffService = require(script.Parent.BuffService)

local cutsceneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PetCutscene") :: RemoteEvent

local BEHAVIOUR = NpcConfig.PetBehaviour
local THINK_INTERVAL = 0.25 -- seconds between behaviour checks
local ARRIVE_DISTANCE = 1.5 -- studs from a spot that counts as there
-- Per stud of the pet's Height: from the ground to the bottom of the root (Humanoid.HipHeight),
-- and the invisible root's size (about the body, long along -Z).
local HIP = 0.32
local ROOT_SIZE = Vector3.new(0.32, 0.32, 0.65)

type PetState = NpcConfig.PetState
type Live = {
	config: NpcConfig.Pet,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: PetState,
	stateUntil: number,
	goal: Vector3?,
	hover: number, -- the root's height above the ground
}

local PetService = {}

local folder = Instance.new("Folder")
folder.Name = "Pets"
local random = Random.new()
local lastPetted: { [Player]: number } = {} -- os.clock() of each player's last pet

local function groundAt(x: number, z: number): number
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

local function pick(range: NumberRange): number
	return random:NextNumber(range.Min, range.Max)
end

-- Distance from point `p` to the segment a-b (all on the ground plane).
local function segmentDistance(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local t = if ab.Magnitude > 1e-6 then math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

-- A random spot in the pet's Wander area it can walk to in a straight line from `from`
-- (not through the middle or any Avoid circle), or nil if none turned up.
local function pickSpot(config: NpcConfig.Pet, from: Vector2): Vector2?
	local area = config.Wander
	for _ = 1, 20 do
		local angle = random:NextNumber(0, math.pi * 2)
		-- Even over the ring's area (not bunched near the middle).
		local radius = math.sqrt(random:NextNumber(area.MinRadius ^ 2, area.MaxRadius ^ 2))
		local spot = area.Center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local clear = (spot - from).Magnitude > 4 and segmentDistance(area.Center, from, spot) >= area.MinRadius - 0.5
		for _, circle in area.Avoid do
			clear = clear and segmentDistance(circle.Center, from, spot) >= circle.Radius
		end
		if clear then
			return spot
		end
	end
	return nil
end

local function flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

local function setState(pet: Live, state: PetState, duration: number)
	pet.state = state
	pet.stateUntil = os.clock() + duration
	pet.model:SetAttribute("PetState", state)
end

local function stop(pet: Live)
	pet.goal = nil
	pet.humanoid:MoveTo(pet.root.Position)
end

-- After an idle spell: what next, by the Next weights.
local function chooseNext(pet: Live)
	local total = 0
	for _, weight in BEHAVIOUR.Next do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	local choice = "Idle"
	for state, weight in BEHAVIOUR.Next do
		roll -= weight
		if roll <= 0 then
			choice = state
			break
		end
	end
	if choice == "Walking" then
		local spot = pickSpot(pet.config, flat(pet.root.Position))
		if spot then
			local goal = Vector3.new(spot.X, groundAt(spot.X, spot.Y), spot.Y)
			pet.goal = goal
			pet.humanoid:MoveTo(goal)
			setState(pet, "Walking", BEHAVIOUR.WalkTimeout)
			return
		end
		choice = "Idle"
	end
	if choice == "Loafing" or choice == "Sleeping" then
		setState(pet, choice :: PetState, pick(BEHAVIOUR.RestTime))
	else
		setState(pet, "Idle", pick(BEHAVIOUR.IdleTime))
	end
end

-- Back into its area if it's been pushed or wandered out: walked straight in (radially, so
-- clear of the middle), or put back if it's far out.
local function leash(pet: Live): boolean
	local area = pet.config.Wander
	local offset = flat(pet.root.Position) - area.Center
	local out = offset.Magnitude - area.MaxRadius
	if out <= BEHAVIOUR.StrayDistance or pet.state == "Playing" then
		return false
	end
	local spot = area.Center + offset.Unit * (area.MaxRadius - 2)
	local ground = Vector3.new(spot.X, groundAt(spot.X, spot.Y), spot.Y)
	if out > BEHAVIOUR.LostDistance then
		pet.root.AssemblyLinearVelocity = Vector3.zero
		pet.model:PivotTo(CFrame.new(ground + Vector3.new(0, pet.hover, 0)) * pet.root.CFrame.Rotation)
		stop(pet)
		setState(pet, "Idle", pick(BEHAVIOUR.IdleTime))
	elseif pet.state ~= "Walking" or pet.goal ~= ground then
		pet.goal = ground
		pet.humanoid:MoveTo(ground)
		setState(pet, "Walking", BEHAVIOUR.WalkTimeout * 2)
	end
	return true
end

local function think(pet: Live)
	local now = os.clock()
	if leash(pet) and pet.state ~= "Walking" then
		return
	end
	if pet.state == "Walking" then
		local goal = pet.goal
		local arrived = goal ~= nil and (flat(goal) - flat(pet.root.Position)).Magnitude <= ARRIVE_DISTANCE
		if arrived or now >= pet.stateUntil then
			stop(pet)
			setState(pet, "Idle", pick(BEHAVIOUR.IdleTime))
		elseif goal then
			pet.humanoid:MoveTo(goal) -- MoveTo gives up after 8 seconds; keep it going
		end
	elseif now >= pet.stateUntil then
		if pet.state == "Idle" then
			chooseNext(pet)
		else
			setState(pet, "Idle", pick(BEHAVIOUR.IdleTime))
		end
	end
end

local function onPetted(pet: Live, player: Player)
	local now = os.clock()
	if now - (lastPetted[player] or -math.huge) < BEHAVIOUR.PetCooldown then
		return
	end
	lastPetted[player] = now
	stop(pet)
	local character = player.Character
	local target = character and character:FindFirstChild("HumanoidRootPart")
	if target and target:IsA("BasePart") then
		local from = pet.root.Position
		local toward = Vector3.new(target.Position.X, from.Y, target.Position.Z)
		if (toward - from).Magnitude > 0.1 then
			pet.root.CFrame = CFrame.lookAt(from, toward)
		end
	end
	setState(pet, "Playing", BEHAVIOUR.PlayTime)
	local blessing = pet.config.Blessing
	if blessing then
		BuffService.grant(player, blessing)
	end
	cutsceneRemote:FireClient(player, pet.model, blessing)
end

-- A rigged copy of the pet's model, standing with its feet at the origin, or nil.
local function build(config: NpcConfig.Pet, models: Instance): (Model?, Humanoid?, BasePart?)
	local template = models:FindFirstChild(config.Model)
	if not template or not template:IsA("Model") then
		warn(`[PetService] no model "{config.Model}" in ServerStorage.NpcModels; {config.Name} isn't spawned (see assets/npcs/README.md)`)
		return nil, nil, nil
	end
	local model = template:Clone()
	model.Name = config.Name
	local _, importedSize = model:GetBoundingBox()
	if importedSize.Y > 0 and math.abs(importedSize.Y - config.Height) > 0.01 then
		model:ScaleTo(model:GetScale() * config.Height / importedSize.Y)
	end
	local parts: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true -- while it's rigged
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			table.insert(parts, part)
		end
	end
	-- The client poses the bones itself (PetAnimator); nothing else may.
	for _, child in model:GetChildren() do
		if child:IsA("AnimationController") or child.Name == "AnimSaves" or child.Name == "InitialPoses" then
			child:Destroy()
		end
	end

	-- Feet at the origin, centered, turned by FacingOffset (so its front is the root's -Z).
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - box.Position + Vector3.new(0, size.Y / 2, 0))
	model:PivotTo(CFrame.Angles(0, math.rad(config.FacingOffset), 0) * model:GetPivot())

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * config.Height
	root.CFrame = CFrame.new(0, (HIP + ROOT_SIZE.Y / 2) * config.Height, 0)
	root.Transparency = 1
	-- Not solid: she's far lighter than a player, who'd shove her across town getting close
	-- enough to pet her. Players walk through her instead.
	root.CanCollide = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
	end
	root.Anchored = false

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 humanoids stand on HipHeight
	humanoid.HipHeight = HIP * config.Height
	humanoid.WalkSpeed = config.WalkSpeed
	humanoid.DisplayName = config.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pet"
	prompt.ObjectText = config.Name
	prompt.MaxActivationDistance = BEHAVIOUR.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom -- no popup over her: Nameplates shows the key under her name
	prompt.Parent = root

	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- reaches clients whole, bones and all
	model:SetAttribute("PetId", config.Id)
	return model, humanoid, root
end

local function spawnPet(config: NpcConfig.Pet, models: Instance)
	local model, humanoid, root = build(config, models)
	if not model or not humanoid or not root then
		return
	end
	local spot = pickSpot(config, config.Wander.Center + Vector2.new(config.Wander.MaxRadius, 0))
		or config.Wander.Center + Vector2.new(config.Wander.MinRadius, 0)
	local ground = Vector3.new(spot.X, groundAt(spot.X, spot.Y), spot.Y)
	local hover = (HIP + ROOT_SIZE.Y / 2) * config.Height
	model:PivotTo(CFrame.new(ground + Vector3.new(0, hover, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	model.Parent = folder
	root:SetNetworkOwner(nil) -- the server walks it

	local pet: Live = { config = config, model = model, humanoid = humanoid, root = root, state = "Idle", stateUntil = 0, goal = nil, hover = hover }
	setState(pet, "Idle", pick(BEHAVIOUR.IdleTime))
	local prompt = root:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			onPetted(pet, player)
		end)
	end
	task.spawn(function()
		while model.Parent do
			think(pet)
			task.wait(THINK_INTERVAL)
		end
	end)
end

function PetService.start()
	folder.Parent = workspace
	Players.PlayerRemoving:Connect(function(player)
		lastPetted[player] = nil
	end)
	local models = ServerStorage:FindFirstChild("NpcModels")
	if not models then
		warn("[PetService] ServerStorage.NpcModels is missing; no pets spawned")
		return
	end
	for _, config in NpcConfig.Pets do
		spawnPet(config, models)
	end
end

return PetService
