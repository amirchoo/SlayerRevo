--!strict
-- Wildlife (AnimalConfig): herds of cows and flocks of chickens wandering the land around
-- their homes. They never fight back: hit one and it runs from you (zig-zagging, the
-- skittish ones more), and so does the rest of its herd nearby. Kill one and it tips over,
-- and its Drops land on the ground for the killer (LootService); a new one joins its herd a
-- while later. Tame animals (AnimalConfig.TownPens) wander their pen in town instead; they
-- have no health, so they can't be hurt.
-- Models come from ServerStorage.AnimalModels (assets/animals, made by tools/box_glb.py):
-- plain Parts, rigged here at spawn: an invisible HumanoidRootPart over the Body carries a
-- Humanoid (so they walk like everything else and every weapon's hits, knockback, stuns and
-- slows work on them), with each of the type's Limbs on a Motor6D the client animates
-- (AnimalAnimator). The "Animal" attribute is the type's AnimalConfig.Types key.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Dormancy = require(script.Parent.Dormancy)
local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local LootService = require(script.Parent.LootService)

local AnimalConfig = require(ReplicatedStorage.Shared.Config.AnimalConfig)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local WorldMap = require(ReplicatedStorage.Shared.WorldMap)

type AnimalType = AnimalConfig.AnimalType

local SPAWN_RAY_HEIGHT = 500
local STUCK_TIME = 1 -- seconds barely moving toward a far goal before trying a jump
local GOAL_TIMEOUT = 15 -- seconds to reach a wander goal before giving up on it
local FLEE_STEP = 14 -- studs ahead it aims each tick while fleeing
local KEEP_FROM_PLAYERS = 40 -- studs: replacements don't appear closer to a player than this
local DEATH_TIP = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DEATH_LIE = 2.5 -- seconds the body lies there before fading
local DEATH_FADE = TweenInfo.new(0.8)

local AnimalService = {}

local animalsFolder = Instance.new("Folder")
animalsFolder.Name = "Animals"

type Herd = {
	key: string,
	kind: AnimalType,
	home: Vector3,
	anchor: Vector3, -- where the herd is grazing now: it drifts around home
	pen: AnimalConfig.Pen?, -- tame: kept inside this pen, and can't be hurt
	nextDrift: number,
	members: { Model },
}

type Animal = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	herd: Herd,
	kind: AnimalType,
	threat: Model?, -- the character it's running from
	threatAt: Vector3, -- where the threat was last seen
	fleeUntil: number,
	goal: Vector3?,
	goalSince: number,
	nextWander: number,
	seed: number, -- offsets its zig-zag from its herd mates'
	removed: boolean,
}

local animalOf: { [Model]: Animal } = {}
local herds: { Herd } = {}
local random = Random.new()

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function groundAt(point: Vector2): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { animalsFolder, workspace:FindFirstChild("World") or animalsFolder }
	local result = workspace:Raycast(Vector3.new(point.X, SPAWN_RAY_HEIGHT, point.Y), Vector3.new(0, -SPAWN_RAY_HEIGHT * 2, 0), params)
	return if result then result.Position else nil
end

local function playerNear(position: Vector3, range: number): boolean
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and flat(root.Position - position).Magnitude < range then
			return true
		end
	end
	return false
end

-- Whether animals may stand at `p`: in the herd's area, on dry open ground (off the river,
-- out of clearings), clear of the safe zone. Tame animals: anywhere in their pen.
local function openGround(herd: AnimalConfig.Herd, p: Vector2, pen: AnimalConfig.Pen?): boolean
	if pen then
		return p.X >= pen.Min.X and p.X <= pen.Max.X and p.Y >= pen.Min.Y and p.Y <= pen.Max.Y
	end
	local area = herd.Area
	if p.X < area.Min.X or p.X > area.Max.X or p.Y < area.Min.Y or p.Y > area.Max.Y then
		return false
	end
	local fromHub = Vector2.new(p.X - SafeZone.CENTER.X, p.Y - SafeZone.CENTER.Z)
	local clearOfHub = math.max(math.abs(fromHub.X), math.abs(fromHub.Y)) > SafeZone.HALF_SIZE + herd.SafeMargin
	return clearOfHub and WorldMap.riverDistance(p) > 10 and not WorldMap.clearingAt(p, 4)
end

-- A spot on open ground within `radius` of `near` (anywhere in the area if `near` is nil),
-- or nil if none turned up.
local function spotNear(herd: AnimalConfig.Herd, near: Vector3?, radius: number, pen: AnimalConfig.Pen?): Vector3?
	for _ = 1, 20 do
		local p
		if near then
			local angle, distance = random:NextNumber(0, math.pi * 2), random:NextNumber(0, radius)
			p = Vector2.new(near.X + math.cos(angle) * distance, near.Z + math.sin(angle) * distance)
		else
			p = Vector2.new(random:NextNumber(herd.Area.Min.X, herd.Area.Max.X), random:NextNumber(herd.Area.Min.Y, herd.Area.Max.Y))
		end
		if openGround(herd, p, pen) then
			local ground = groundAt(p)
			if ground then
				return ground
			end
		end
	end
	return nil
end

-- Rigging ----------------------------------------------------------------------------------

-- The Parts a limb is made of: everything in the sub-Model of that name, or the Part itself.
local function limbParts(model: Model, names: { string }): { BasePart }
	local parts = {}
	for _, name in names do
		local child = model:FindFirstChild(name)
		if child and child:IsA("BasePart") then
			table.insert(parts, child)
		elseif child then
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
		end
	end
	return parts
end

local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		low = low:Min(part.Position - part.Size / 2)
		high = high:Max(part.Position + part.Size / 2)
	end
	return low, high
end

-- Where a limb turns (in the model's space; the model faces -Z): legs at the hip, the head
-- at the back of the neck, wings at the shoulder, the tail where it joins the body.
local function limbPivot(limb: AnimalConfig.Limb, low: Vector3, high: Vector3): Vector3
	local middle = (low + high) / 2
	if limb.Swing == "Head" then
		return Vector3.new(middle.X, low.Y + (high.Y - low.Y) * 0.3, high.Z)
	elseif limb.Swing == "Wing" then
		local inner = if (limb.Side or 1) > 0 then low.X else high.X
		return Vector3.new(inner, high.Y, middle.Z)
	elseif limb.Swing == "Tail" then
		return Vector3.new(middle.X, if limb.Upright then low.Y else high.Y, low.Z)
	end
	return Vector3.new(middle.X, high.Y, middle.Z) -- Leg
end

local function weld(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part1
end

-- A rigged copy of the animal's model (anywhere; spawnAnimal places it), or nil if its model
-- is missing. Returns the model, its Humanoid and root.
local function build(key: string, kind: AnimalType): (Model?, Humanoid?, BasePart?)
	local folder = ServerStorage:FindFirstChild("AnimalModels")
	local template = folder and folder:FindFirstChild(kind.Model)
	if not template or not template:IsA("Model") then
		warn(`[AnimalService] No AnimalModels.{kind.Model} (assets/animals); no {kind.DisplayName}s`)
		return nil, nil, nil
	end
	local model = template:Clone()
	if kind.Scale ~= 1 then
		model:ScaleTo(model:GetScale() * kind.Scale)
	end
	local body = model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		warn(`[AnimalService] AnimalModels.{kind.Model} needs a Part named Body`)
		return nil, nil, nil
	end
	local all: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true -- while it's rigged
			part.CanCollide = false
			part.Massless = true
			table.insert(all, part)
		end
	end
	local groundY = (bounds(all)).Y

	-- The root: an invisible box over the body, which the Humanoid holds HipHeight off the ground.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = body.Size
	root.CFrame = body.CFrame
	root.Transparency = 1
	root.CanCollide = true
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	local inLimb: { [BasePart]: boolean } = {}
	for _, limb in kind.Limbs do
		local parts = limbParts(model, limb.Parts or { limb.Name })
		if #parts == 0 then
			warn(`[AnimalService] {kind.Model} has no {limb.Name}; it won't move`)
			continue
		end
		local low, high = bounds(parts)
		local pivot = CFrame.new(limbPivot(limb, low, high))
		local main = parts[1]
		for index, part in parts do
			inLimb[part] = true
			if index > 1 then
				weld(main, part)
			end
		end
		local motor = Instance.new("Motor6D")
		motor.Name = limb.Name
		motor.Part0 = root
		motor.Part1 = main
		motor.C0 = root.CFrame:ToObjectSpace(pivot)
		motor.C1 = main.CFrame:ToObjectSpace(pivot)
		motor:SetAttribute("Swing", limb.Swing)
		motor:SetAttribute("Phase", limb.Phase or 0)
		motor:SetAttribute("Side", limb.Side or 1)
		motor.Parent = root
	end
	for _, part in all do
		if not inLimb[part] then
			weld(root, part)
		end
	end
	for _, part in all do
		part.Anchored = false
	end
	root.Anchored = false

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 humanoids stand on HipHeight
	humanoid.HipHeight = root.Position.Y - root.Size.Y / 2 - groundY
	humanoid.WalkSpeed = kind.WalkSpeed
	humanoid.DisplayName = kind.DisplayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- animals show no name or health bar
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	model.Name = kind.DisplayName
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- reaches clients whole, joints and all
	model:SetAttribute("Animal", key)
	return model, humanoid, root
end

-- Behaviour --------------------------------------------------------------------------------

local spawnAnimal: (herd: Herd, near: Vector3) -> ()

-- Takes a dead or lost animal out of its herd; a new one joins after its RespawnDelay.
local function remove(animal: Animal)
	if animal.removed then
		return
	end
	animal.removed = true
	animalOf[animal.model] = nil
	local herd = animal.herd
	local index = table.find(herd.members, animal.model)
	if index then
		table.remove(herd.members, index)
	end
	task.delay(animal.kind.RespawnDelay, function()
		-- Somewhere round home that no one is watching, if there is such a place.
		for _ = 1, 5 do
			local spot = spotNear(herd.kind.Herd, herd.home, herd.kind.RoamRadius, herd.pen)
			if spot and (herd.pen or not playerNear(spot, KEEP_FROM_PLAYERS)) then
				spawnAnimal(herd, spot)
				return
			end
		end
		spawnAnimal(herd, herd.home)
	end)
end

local function runAI(animal: Animal)
	local humanoid, root, kind, herd = animal.humanoid, animal.root, animal.kind, animal.herd
	local stuckSince: number? = nil

	local function walkTo(goal: Vector3, speed: number)
		humanoid.WalkSpeed = speed * EnemyEffects.speedFactor(animal.model) -- slowed by Water, etc.
		humanoid:MoveTo(goal)
		if flat(goal - root.Position).Magnitude > 4 and flat(root.AssemblyLinearVelocity).Magnitude < 0.5 then
			stuckSince = stuckSince or os.clock()
			if os.clock() - (stuckSince :: number) > STUCK_TIME then
				humanoid.Jump = true
				stuckSince = nil
			end
		else
			stuckSince = nil
		end
	end

	local tame = herd.pen ~= nil
	local asleep = false -- far from every player (Dormancy)
	while animal.model.Parent and (tame or HealthService.isAlive(animal.model)) do
		local now = os.clock()
		-- Far from every player: stand still, anchored, and only check now and then. A scare
		-- (being hit, or a hurt herd mate) wakes it.
		if asleep then
			if now < animal.fleeUntil or Dormancy.playerNear(root.Position, Dormancy.Config.WakeRange) then
				asleep = false
				Dormancy.wake(root)
			else
				Dormancy.sleep(humanoid, root) -- until it's anchored on the ground
				task.wait(Dormancy.Config.Tick)
				continue
			end
		elseif now >= animal.fleeUntil and not Dormancy.playerNear(root.Position, Dormancy.Config.SleepRange) then
			asleep = true
			animal.goal = nil
			Dormancy.sleep(humanoid, root)
			task.wait(Dormancy.Config.Tick)
			continue
		end

		if EnemyEffects.isStunned(animal.model) then
			humanoid:MoveTo(root.Position)
		elseif now < animal.fleeUntil then
			-- Run from the threat, veering side to side.
			local threat = animal.threat
			local threatRoot = threat and threat:FindFirstChild("HumanoidRootPart")
			if threatRoot and threatRoot:IsA("BasePart") then
				animal.threatAt = threatRoot.Position
			end
			local away = flat(root.Position - animal.threatAt)
			away = if away.Magnitude > 0.1 then away.Unit else root.CFrame.LookVector
			local veer = math.sin(now * 2.5 + animal.seed) * kind.Skittish * math.rad(70)
			local direction = CFrame.Angles(0, veer, 0):VectorToWorldSpace(away)
			walkTo(root.Position + direction * FLEE_STEP, kind.FleeSpeed)
			animal.goal = nil
			animal.nextWander = now + random:NextNumber(kind.RoamPause[1], kind.RoamPause[2])
		else
			-- Wander: the herd's grazing spot drifts round home; each animal mills about it.
			if now >= herd.nextDrift then
				herd.anchor = spotNear(kind.Herd, herd.home, kind.RoamRadius, herd.pen) or herd.anchor
				herd.nextDrift = now + random:NextNumber(kind.RoamPause[1], kind.RoamPause[2]) * 4
			end
			local goal = animal.goal
			if goal then
				if flat(goal - root.Position).Magnitude < 2 or now - animal.goalSince > GOAL_TIMEOUT then
					animal.goal = nil
					humanoid:MoveTo(root.Position)
					animal.nextWander = now + random:NextNumber(kind.RoamPause[1], kind.RoamPause[2])
				else
					walkTo(goal, kind.WalkSpeed)
				end
			elseif now >= animal.nextWander then
				animal.goal = spotNear(kind.Herd, herd.anchor, kind.Herd.Spread, herd.pen)
				animal.goalSince = now
				animal.nextWander = now + 2 -- try again soon if no spot turned up
			end
		end
		task.wait(AnimalConfig.AiTick)
	end
	if not tame and not HealthService.isAlive(animal.model) then
		return -- died: the Died handler takes it from here
	end
	remove(animal) -- lost (e.g. fell out of the world)
end

spawnAnimal = function(herd: Herd, near: Vector3)
	local model, humanoid, root = build(herd.key, herd.kind)
	if not model or not humanoid or not root then
		return
	end
	local kind = herd.kind
	local hover = humanoid.HipHeight + root.Size.Y / 2 -- the root's height above the ground
	local angle = random:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(near + Vector3.new(0, hover, 0)) * CFrame.Angles(0, angle, 0))
	model.Parent = animalsFolder
	root:SetNetworkOwner(nil) -- the server moves them
	if not herd.pen then
		HealthService.register(model, kind.MaxHealth)
		model:SetAttribute("XPReward", kind.XP) -- ProgressionService gives it to whoever kills it
	end

	local animal: Animal = {
		model = model,
		humanoid = humanoid,
		root = root,
		herd = herd,
		kind = kind,
		threat = nil,
		threatAt = root.Position,
		fleeUntil = 0,
		goal = nil,
		goalSince = 0,
		nextWander = os.clock() + random:NextNumber(0, kind.RoamPause[2]),
		seed = random:NextNumber(0, math.pi * 2),
		removed = false,
	}
	animalOf[model] = animal
	table.insert(herd.members, model)
	task.spawn(runAI, animal)
end

-- Frightens `animal` away from `character` for its FleeTime.
local function scare(animal: Animal, character: Model)
	animal.threat = character
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		animal.threatAt = root.Position
	end
	animal.fleeUntil = os.clock() + animal.kind.FleeTime
end

-- Tips the body over, fades it, and clears it away.
local function die(animal: Animal, killer: Player?)
	local model, root, kind = animal.model, animal.root, animal.kind
	remove(animal)

	if killer then
		for _, drop in kind.Drops do
			if random:NextNumber() < drop.Chance then
				for _ = 1, random:NextInteger(drop.Min, drop.Max) do
					LootService.drop(killer, drop.Item, root.Position)
				end
			end
		end
	end

	animal.humanoid:MoveTo(root.Position)
	root.Anchored = true
	local yaw = CFrame.lookAlong(Vector3.zero, flat(root.CFrame.LookVector).Unit)
	local lying = root.Position.Y - animal.humanoid.HipHeight - root.Size.Y / 2 + root.Size.X / 2
	local fallen = CFrame.new(root.Position.X, lying, root.Position.Z) * yaw * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(root, DEATH_TIP, { CFrame = fallen }):Play()
	task.delay(DEATH_LIE, function()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				TweenService:Create(part, DEATH_FADE, { Transparency = 1 }):Play()
			end
		end
		task.wait(DEATH_FADE.Time)
		model:Destroy()
	end)
end

-- Forms a herd of `kind` at a new home and fills it.
local function spawnHerd(key: string, kind: AnimalType)
	local config = kind.Herd
	local home: Vector3? = nil
	for _ = 1, 10 do
		local spot = spotNear(config, nil, 0)
		local ok = spot ~= nil
		if spot then
			for _, other in herds do
				if flat(other.home - spot).Magnitude < config.HomeSpacing then
					ok = false
				end
			end
		end
		if ok then
			home = spot
			break
		end
	end
	if not home then
		warn(`[AnimalService] No room for a {kind.DisplayName} herd`)
		return
	end
	local herd: Herd = { key = key, kind = kind, home = home, anchor = home, pen = nil, nextDrift = 0, members = {} }
	table.insert(herds, herd)
	for _ = 1, random:NextInteger(config.Min, config.Max) do
		spawnAnimal(herd, spotNear(config, home, config.Spread) or home)
	end
end

function AnimalService.start()
	animalsFolder.Parent = workspace

	-- A hit animal runs from whoever hit it, and so do its herd mates nearby.
	HealthService.addDamageFilter(function(target: Model, amount: number, source: Player?)
		local animal = animalOf[target]
		local character = source and source.Character
		if animal and character then
			for _, mate in animal.herd.members do
				local other = animalOf[mate]
				if other and (other == animal or flat(other.root.Position - animal.root.Position).Magnitude <= AnimalConfig.HerdPanicRange) then
					scare(other, character)
				end
			end
		end
		return amount
	end)

	HealthService.Died:Connect(function(model: Model, killer: Player?)
		local animal = animalOf[model]
		if animal then
			die(animal, killer)
		end
	end)

	task.spawn(function()
		-- The world (trees, ruins) is still being placed; wait so herds land on open ground.
		task.wait(3)
		for key, kind in AnimalConfig.Types do
			for _ = 1, kind.Herd.Count do
				spawnHerd(key, kind)
			end
		end
		-- The tame ones in town.
		for _, pen in AnimalConfig.TownPens do
			local kind = AnimalConfig.Types[pen.Type]
			local center = (pen.Min + pen.Max) / 2
			local home = groundAt(center)
			if kind and home then
				local herd: Herd = { key = pen.Type, kind = kind, home = home, anchor = home, pen = pen, nextDrift = 0, members = {} }
				table.insert(herds, herd)
				for _ = 1, pen.Count do
					spawnAnimal(herd, spotNear(kind.Herd, home, kind.RoamRadius, pen) or home)
				end
			end
		end
	end)
end

return AnimalService
