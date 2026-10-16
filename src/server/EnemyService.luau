--!strict
-- Spawns enemies and runs their AI. Enemies with a Pack (EnemyConfig) live in packs that
-- roam the world around a camp, turn on a player together, surround them (a few attack, the
-- rest circle), give up if dragged too far from camp, and re-form at a new camp once all are
-- dead. Single enemies (SpawnPoints, the Training Grounds) chase the nearest player and
-- respawn where they stood. Giving up heals an enemy to full at once, and a pack walking home
-- can't be hurt (and heals again once home), so you can't wear one down by kiting it. Every attack has a short wind-up, so players can dodge. A kill
-- leaves the enemy's Drops on the ground for the killer (LootService). A dead enemy keeps its
-- body whole: it topples over, lies there, then fades away (it never falls apart).
-- Sparring enemies (the training camp, spawnSparring) belong to one player: they fight only
-- that player, even in the safe zone, only that player can hurt them, they give no XP or
-- coins (or drops), and they never respawn. A puppet (spawnPuppet) is one with no AI at all: its owner
-- (TutorialService) moves it and resolves its attacks.
-- Looks: the enemy's Model from ServerStorage.EnemyModels (assets/enemies) if it's there,
-- an R15 character (with a Humanoid and HumanoidRootPart, e.g. made with Avatar Auto Setup);
-- otherwise a plain R15 body in the enemy's color.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local BlockService = require(script.Parent.BlockService)
local EnemyAnimations = require(script.Parent.EnemyAnimations)
local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local LootService = require(script.Parent.LootService)

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local WorldMap = require(ReplicatedStorage.Shared.WorldMap)

type EnemyType = EnemyConfig.EnemyType

local SPAWN_RAY_HEIGHT = 500
local SPAWN_HEIGHT_ABOVE_GROUND = 4

local AI_TICK = EnemyConfig.AiTick

local EnemyService = {}

local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"

-- Where each live enemy spawned and what it is, so it respawns as the same thing there.
local spawnPointOf: { [Model]: Vector2 } = {}
local typeOf: { [Model]: EnemyType } = {}
-- Enemies spawned with spawnOnce: when they die, the body is cleared away and nothing respawns.
local oneOff: { [Model]: boolean } = {}
-- Sparring enemies: the one player each fights (and the only one who can hurt it).
local ownerOf: { [Model]: Player } = {}

-- How a dungeon's orc gets about (spawnOnFloor): a patrol route it walks while it has no
-- target, a way round walls (the next point to walk to on the way somewhere; nil when
-- there's no way), and whether it must see a player to notice them.
export type Roam = {
	route: { Vector3 }?,
	navigate: ((from: Vector3, to: Vector3) -> Vector3?)?,
	sight: boolean?,
}
local roamOf: { [Model]: Roam } = {}
local PATROL_PAUSE = { 1, 3 } -- seconds a patroller stands at each waypoint
local PATROL_SPEED = 0.45 -- of WalkSpeed
local SIGHT_HEIGHT = 1.5 -- studs above the root that sight lines start and end

-- The ground under X/Z: the highest thing below SPAWN_RAY_HEIGHT, or below `fromY` (within
-- DROP_REACH) for floors up in the sky, like a dungeon's.
local DROP_REACH = 40
local DEATH_TIP = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DEATH_FADE = TweenInfo.new(0.8)
local function groundCFrame(spawnPoint: Vector2, fromY: number?): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemiesFolder, workspace:FindFirstChild("World") or enemiesFolder }

	local origin = Vector3.new(spawnPoint.X, fromY or SPAWN_RAY_HEIGHT, spawnPoint.Y)
	local reach = if fromY then DROP_REACH else SPAWN_RAY_HEIGHT * 2
	local result = workspace:Raycast(origin, Vector3.new(0, -reach, 0), params)
	if not result then
		warn(`[EnemyService] No ground under spawn point {spawnPoint}; the enemy may fall`)
	end
	local groundY = if result then result.Position.Y else 0
	return CFrame.new(spawnPoint.X, groundY + SPAWN_HEIGHT_ABOVE_GROUND, spawnPoint.Y)
end

local function findNearestCharacter(position: Vector3, maxDistance: number): (Model?, BasePart?, number)
	local nearest: Model?, nearestRoot: BasePart? = nil, nil
	local nearestDistance = maxDistance
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- The town is a safe zone: players inside it are ignored.
		if
			character
			and root
			and root:IsA("BasePart")
			and not SafeZone.contains(root.Position)
			and HealthService.isAlive(character)
		then
			local distance = (root.Position - position).Magnitude
			if distance < nearestDistance then
				nearest, nearestRoot, nearestDistance = character, root, distance
			end
		end
	end
	return nearest, nearestRoot, nearestDistance
end

-- A sparring enemy's target: its owner's character if alive and within `maxDistance`
-- (anywhere, the safe zone included).
local function ownerTarget(owner: Player, position: Vector3, maxDistance: number): (Model?, BasePart?, number)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root and root:IsA("BasePart") and HealthService.isAlive(character) then
		local distance = (root.Position - position).Magnitude
		if distance <= maxDistance then
			return character, root, distance
		end
	end
	return nil, nil, maxDistance
end

-- A pack of enemies that roam, hunt and leash together (see EnemyConfig.Pack).
type PackState = {
	kind: EnemyType,
	config: EnemyConfig.Pack,
	camp: Vector3,
	members: { Model },
	formation: { [Model]: Vector3 }, -- each member's spot around the pack's centre while roaming
	roles: { [Model]: { attacking: boolean, slot: number, slots: number } },
	target: Model?,
	targetRoot: BasePart?,
	hurtBy: Model?, -- set when a member is hit: the pack turns on them
	roamGoal: Vector3,
	nextRoam: number,
	returning: boolean, -- gave up a target: heading home (and healing) before roaming again
}
local packOf: { [Model]: PackState } = {}
local packs: { PackState } = {}

local STUCK_TIME = 1 -- seconds of barely moving toward a far goal before trying a jump
local PACK_TICK = 0.3

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function attackPlayer(enemy: Model, root: BasePart, kind: EnemyType, attackTrack: AnimationTrack, target: Model, targetRoot: BasePart)
	attackTrack:Play(0.1)
	enemy:SetAttribute("Attacking", true) -- no flinching mid-attack (EnemyEffects.flinch)
	task.delay(kind.AttackWindup, function()
		enemy:SetAttribute("Attacking", false)
		-- Re-check range after the wind-up so players can dodge out of it, and a stun during
		-- the wind-up cancels the attack.
		local stillInRange = (targetRoot.Position - root.Position).Magnitude <= kind.AttackRange + 1
		if HealthService.isAlive(enemy) and stillInRange and not EnemyEffects.isStunned(enemy) then
			if BlockService.tryParry(target, enemy) then
				attackTrack:Stop(0.05) -- parried: knocked out of the swing
				return
			end
			local dealt = HealthService.damage(target, kind.AttackDamage, nil, root.Position)
			if dealt > 0 then
				local impact, direction = HitEffects.meleeImpactPoint(target, root.Position)
				HitEffects.broadcast(target, impact, direction, "DemonClaw", dealt)
			end
		end
	end)
end

local function fullHeal(enemy: Model)
	local _, maxHealth = HealthService.getHealth(enemy)
	if maxHealth then
		HealthService.heal(enemy, maxHealth)
	end
end

-- Whether `root` has a clear line to `target` (nothing but enemies in the way).
local function canSee(root: BasePart, target: Model, targetRoot: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemiesFolder, target }
	local from = root.Position + Vector3.new(0, SIGHT_HEIGHT, 0)
	local to = targetRoot.Position + Vector3.new(0, SIGHT_HEIGHT, 0)
	return workspace:Raycast(from, to - from, params) == nil
end

local function runAI(enemy: Model, humanoid: Humanoid, root: BasePart, home: Vector3, kind: EnemyType)
	local attackTrack = EnemyAnimations.start(enemy, humanoid, kind) -- idle, walk/run, flinch, parried
	local roam = roamOf[enemy]
	local waypoint = 1 -- the patrol waypoint it's walking to
	local pauseUntil: number? = nil
	-- Walks toward `goal`, round walls if it knows the way (and stands still if there's none).
	local function head(goal: Vector3)
		local navigate = roam and roam.navigate
		local step = if navigate then navigate(root.Position, goal) else goal
		humanoid:MoveTo(step or root.Position)
	end

	local lastAttack = 0
	local stuckSince: number? = nil
	-- Walks toward `goal` (or stops when close); jumps if it seems stuck on something.
	local function walkTo(goal: Vector3, speedFactor: number)
		humanoid.WalkSpeed = kind.WalkSpeed * speedFactor * EnemyEffects.speedFactor(enemy) -- slowed by Water, etc.
		local away = flat(goal - root.Position).Magnitude
		if away < 1.5 then
			humanoid:MoveTo(root.Position)
			stuckSince = nil
			return
		end
		humanoid:MoveTo(goal)
		if away > 4 and flat(root.AssemblyLinearVelocity).Magnitude < 1 then
			stuckSince = stuckSince or os.clock()
			if os.clock() - (stuckSince :: number) > STUCK_TIME then
				humanoid.Jump = true
				stuckSince = nil
			end
		else
			stuckSince = nil
		end
	end
	local function face(position: Vector3)
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(position.X, root.Position.Y, position.Z))
	end
	local function tryAttack(target: Model, targetRoot: BasePart)
		face(targetRoot.Position)
		if os.clock() - lastAttack >= kind.AttackCooldown then
			lastAttack = os.clock()
			attackPlayer(enemy, root, kind, attackTrack, target, targetRoot)
		end
	end

	local chasing = false -- a single enemy: had a target last think
	while enemy.Parent and HealthService.isAlive(enemy) do
		if EnemyEffects.isStunned(enemy) then
			humanoid:MoveTo(root.Position)
			attackTrack:Stop(0.1)
			task.wait(AI_TICK)
			continue
		end

		local pack = packOf[enemy]
		if pack then
			local target, targetRoot = pack.target, pack.targetRoot
			local role = pack.roles[enemy]
			if target and targetRoot and role then
				local toMe = flat(root.Position - targetRoot.Position)
				local distance = toMe.Magnitude
				if role.attacking then
					-- Close in from our own side, so attackers spread round the target.
					if distance > kind.AttackRange then
						local side = if distance > 0.1 then toMe.Unit else Vector3.xAxis
						walkTo(targetRoot.Position + side * kind.AttackRange * 0.7, 1)
					else
						humanoid:MoveTo(root.Position)
						tryAttack(target, targetRoot)
					end
				else
					-- Wait our turn on a ring round the target (slowly circling), facing it.
					local angle = role.slot / math.max(role.slots, 1) * math.pi * 2 + os.clock() * 0.25
					local ring = targetRoot.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * pack.config.RingRadius
					walkTo(ring, 0.8)
					if distance <= kind.AttackRange then
						tryAttack(target, targetRoot) -- the target walked into us
					elseif flat(ring - root.Position).Magnitude < 3 then
						face(targetRoot.Position)
					end
				end
			else
				local offset = pack.formation[enemy] or Vector3.zero
				walkTo(pack.roamGoal + offset, if pack.returning then 1 else pack.config.RoamSpeed)
			end
		else
			humanoid.WalkSpeed = kind.WalkSpeed * EnemyEffects.speedFactor(enemy) -- slowed by Water, etc.
			local owner = ownerOf[enemy]
			local target, targetRoot, distance
			if owner then
				target, targetRoot, distance = ownerTarget(owner, root.Position, kind.AggroRange)
			else
				target, targetRoot, distance = findNearestCharacter(root.Position, kind.AggroRange)
				-- A dungeon orc notices you only if it can see you (once on you, it follows).
				if target and targetRoot and roam and roam.sight and not chasing and not canSee(root, target, targetRoot) then
					target, targetRoot = nil, nil
				end
			end
			if target then
				chasing = true
			elseif chasing then
				chasing = false
				if not owner then
					fullHeal(enemy) -- gave up on you: back to full health
				end
			end
			local route = roam and roam.route
			if target and targetRoot then
				if distance > kind.AttackRange then
					head(targetRoot.Position)
				else
					humanoid:MoveTo(root.Position)
					tryAttack(target, targetRoot)
				end
			elseif route and #route > 0 then
				-- Walk the patrol, standing a moment at each waypoint.
				local point = route[waypoint]
				if flat(point - root.Position).Magnitude < 3 then
					humanoid:MoveTo(root.Position)
					pauseUntil = pauseUntil or os.clock() + math.random() * (PATROL_PAUSE[2] - PATROL_PAUSE[1]) + PATROL_PAUSE[1]
					if os.clock() >= (pauseUntil :: number) then
						waypoint = waypoint % #route + 1
						pauseUntil = nil
					end
				else
					humanoid.WalkSpeed *= PATROL_SPEED
					head(point)
				end
			elseif (root.Position - home).Magnitude > 4 then
				humanoid:MoveTo(home) -- no target: walk back to the spawn point
			else
				humanoid:MoveTo(root.Position)
			end
		end

		task.wait(AI_TICK)
	end
end

-- The enemy's own R15 model, ready to spawn, or nil if it hasn't been added (or is unusable).
local function modelFromTemplate(kind: EnemyType): Model?
	local folder = ServerStorage:FindFirstChild("EnemyModels")
	local template = folder and folder:FindFirstChild(kind.Model)
	if not template or not template:IsA("Model") then
		return nil
	end
	if not template:FindFirstChildOfClass("Humanoid") or not template:FindFirstChild("HumanoidRootPart") then
		warn(`[EnemyService] EnemyModels.{kind.Model} needs a Humanoid and a HumanoidRootPart (an R15 rig); using the plain body`)
		return nil
	end
	local enemy = template:Clone()
	for _, descendant in enemy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false -- models are often saved anchored
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy() -- e.g. an "Animate" script; the AI plays its own animations
		end
	end
	local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") :: BasePart
	enemy.PrimaryPart = enemyRoot
	enemyRoot.Transparency = 1
	return enemy
end

-- A plain R15 body in the enemy's color.
local function plainBody(kind: EnemyType): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = kind.Color
	description.TorsoColor = kind.Color
	description.LeftArmColor = kind.Color
	description.RightArmColor = kind.Color
	description.LeftLegColor = kind.Color
	description.RightLegColor = kind.Color

	local ok, result = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[EnemyService] Failed to build enemy model:", result)
		return nil
	end
	return result :: Model
end

local function idOf(kind: EnemyType): string
	for id, value in EnemyConfig do
		if typeof(id) == "string" and value == kind then
			return id
		end
	end
	return kind.DisplayName
end

local function spawnEnemy(spawnPoint: Vector2, kind: EnemyType, pack: PackState?, once: boolean?, owner: Player?, puppet: boolean?, fromY: number?, roam: Roam?): Model?
	local enemy = modelFromTemplate(kind) or plainBody(kind)
	if not enemy then
		return nil
	end
	if kind.Scale and kind.Scale ~= 1 then
		enemy:ScaleTo(enemy:GetScale() * kind.Scale)
	end
	enemy.Name = kind.DisplayName

	local humanoid = enemy:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = enemy:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayName = kind.DisplayName
	humanoid.WalkSpeed = kind.WalkSpeed
	-- The name and health bar are drawn by the client (EnemyHealthBars), not the Humanoid.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false -- dies whole (see topple), not in pieces

	-- Only HealthService changes health; drop any default regen script.
	local regen = enemy:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end

	local spawnCFrame = groundCFrame(spawnPoint, fromY)
	enemy:PivotTo(spawnCFrame)
	enemy.Parent = enemiesFolder
	root:SetNetworkOwner(nil) -- server simulates enemy movement

	if owner then
		ownerOf[enemy] = owner
		oneOff[enemy] = true
		enemy.Destroying:Once(function()
			ownerOf[enemy] = nil
			oneOff[enemy] = nil
			typeOf[enemy] = nil
		end)
	elseif pack then
		packOf[enemy] = pack
		table.insert(pack.members, enemy)
	elseif once then
		oneOff[enemy] = true
	else
		print(`[EnemyService] Spawned {enemy.Name} at {root.Position}`)
		spawnPointOf[enemy] = spawnPoint -- respawns here (pack members re-form as a pack instead)
	end
	typeOf[enemy] = kind
	if roam then
		roamOf[enemy] = roam
		enemy.Destroying:Once(function()
			roamOf[enemy] = nil
		end)
	end
	HealthService.register(enemy, kind.MaxHealth)
	enemy:SetAttribute("XPReward", kind.XP) -- ProgressionService gives it to whoever defeats it
	enemy:SetAttribute("CoinReward", kind.Coins or 0) -- CurrencyService gives it to whoever defeats it
	enemy:SetAttribute("EnemyId", idOf(kind)) -- QuestService counts kills by config id
	enemy:SetAttribute("Level", kind.Level) -- shown over its head when locked on (EnemyHealthBars)
	if owner then
		enemy:SetAttribute("XPReward", 0)
		enemy:SetAttribute("CoinReward", 0)
		enemy:SetAttribute("SparringOwner", owner.UserId) -- its bar shows in town, for its owner only
	end
	if not puppet then
		task.spawn(runAI, enemy, humanoid, root, spawnCFrame.Position, kind)
	end
	return enemy
end

-- Packs ------------------------------------------------------------------------------------

local function inSafeZone(position: Vector3): boolean
	return SafeZone.contains(position)
end

local function playerNear(position: Vector3, range: number): boolean
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude < range then
			return true
		end
	end
	return false
end

-- Somewhere a pack can stand: on dry, open ground in its area (off the river, out of
-- clearings), SafeMargin clear of the safe zone and, when `keepAway`, from other camps and players.
local function openSpot(config: EnemyConfig.Pack, random: Random, near: Vector3?, radius: number?, keepAway: boolean): Vector3?
	local area = config.Area
	for _ = 1, 40 do
		local x, z
		if near and radius then
			local angle, distance = random:NextNumber(0, math.pi * 2), random:NextNumber(0, radius)
			x, z = near.X + math.cos(angle) * distance, near.Z + math.sin(angle) * distance
		else
			x, z = random:NextNumber(area.Min.X, area.Max.X), random:NextNumber(area.Min.Y, area.Max.Y)
		end
		x, z = math.clamp(x, area.Min.X, area.Max.X), math.clamp(z, area.Min.Y, area.Max.Y)
		local p = Vector2.new(x, z)
		local fromHub = Vector2.new(x - SafeZone.CENTER.X, z - SafeZone.CENTER.Z)
		local clearOfHub = math.max(math.abs(fromHub.X), math.abs(fromHub.Y)) > SafeZone.HALF_SIZE + config.SafeMargin
		local ok = clearOfHub and WorldMap.riverDistance(p) > 12 and not WorldMap.clearingAt(p, 8)
		if ok and keepAway then
			for _, other in packs do
				if flat(other.camp - Vector3.new(x, 0, z)).Magnitude < config.CampSpacing then
					ok = false
				end
			end
			ok = ok and not playerNear(Vector3.new(x, 0, z), config.AggroRange * 2)
		end
		if ok then
			return groundCFrame(p).Position
		end
	end
	return nil
end

local packRandom = Random.new()
local dropRandom = Random.new()

local function aliveMembers(pack: PackState): { Model }
	local alive = {}
	for _, member in pack.members do
		if member.Parent and HealthService.isAlive(member) then
			table.insert(alive, member)
		end
	end
	return alive
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The pack's middle (where its members are), or its camp if none are left.
local function centreOf(members: { Model }, fallback: Vector3): Vector3
	local sum, count = Vector3.zero, 0
	for _, member in members do
		local root = rootOf(member)
		if root then
			sum += root.Position
			count += 1
		end
	end
	return if count > 0 then sum / count else fallback
end

local function validTarget(character: Model?): BasePart?
	if not character or not HealthService.isAlive(character) then
		return nil
	end
	local root = rootOf(character)
	return if root and not inSafeZone(root.Position) then root else nil
end

-- Gives up the hunt: back to full health at once, then back to camp (unhurtable on the way).
local function giveUp(pack: PackState)
	pack.target, pack.targetRoot, pack.hurtBy = nil, nil, nil
	pack.returning = true
	pack.roamGoal = pack.camp
	for _, member in aliveMembers(pack) do
		fullHeal(member)
	end
end

-- One think for the whole pack: who it's hunting, who attacks and who circles, and where it
-- roams when it isn't hunting. Members act on this in runAI.
local function thinkPack(pack: PackState)
	local config = pack.config
	local members = aliveMembers(pack)
	local centre = centreOf(members, pack.camp)

	-- Hunting: drop a target that's dead, safe, or dragged us too far from camp.
	if pack.target then
		local targetRoot = validTarget(pack.target)
		if not targetRoot or flat(targetRoot.Position - pack.camp).Magnitude > config.LeashRange then
			giveUp(pack)
		else
			pack.targetRoot = targetRoot
		end
	end
	-- Not hunting: a member that was hit, or a player any member can see, starts a hunt.
	if not pack.target and not pack.returning then
		local hurtByRoot = validTarget(pack.hurtBy)
		if hurtByRoot and pack.hurtBy then
			pack.target, pack.targetRoot = pack.hurtBy, hurtByRoot
		else
			for _, member in members do
				local root = rootOf(member)
				local found, foundRoot = nil, nil
				if root then
					found, foundRoot = findNearestCharacter(root.Position, config.AggroRange)
				end
				if found and foundRoot and flat(foundRoot.Position - pack.camp).Magnitude <= config.LeashRange then
					pack.target, pack.targetRoot = found, foundRoot
					break
				end
			end
		end
		pack.hurtBy = nil
	end

	if pack.target and pack.targetRoot then
		-- The closest few attack; the rest take turns round the ring.
		local targetPosition = pack.targetRoot.Position
		table.sort(members, function(a, b)
			local ra, rb = rootOf(a), rootOf(b)
			local da = if ra then (ra.Position - targetPosition).Magnitude else math.huge
			local db = if rb then (rb.Position - targetPosition).Magnitude else math.huge
			return da < db
		end)
		local waiting = math.max(#members - config.MaxAttackers, 0)
		table.clear(pack.roles)
		for index, member in members do
			local attacking = index <= config.MaxAttackers
			pack.roles[member] = { attacking = attacking, slot = if attacking then 0 else index - config.MaxAttackers, slots = waiting }
		end
		return
	end

	-- Roaming (or walking home after giving up).
	if pack.returning then
		if flat(centre - pack.camp).Magnitude < 10 then
			pack.returning = false
			for _, member in members do
				fullHeal(member) -- in case anything got through on the way
			end
			pack.nextRoam = os.clock() + packRandom:NextNumber(config.RoamPause[1], config.RoamPause[2])
		end
		return
	end
	if os.clock() >= pack.nextRoam then
		local goal = openSpot(config, packRandom, pack.camp, config.RoamRadius, false)
		if goal then
			pack.roamGoal = goal
			local travel = flat(goal - centre).Magnitude / (pack.kind.WalkSpeed * config.RoamSpeed)
			pack.nextRoam = os.clock() + travel + packRandom:NextNumber(config.RoamPause[1], config.RoamPause[2])
		end
	end
end

-- Forms a new pack of `kind` at a fresh camp.
local function spawnPack(kind: EnemyType)
	local config = kind.Pack :: EnemyConfig.Pack
	local camp = openSpot(config, packRandom, nil, nil, true)
	if not camp then
		warn(`[EnemyService] No room for a {kind.DisplayName} pack; trying again later`)
		task.delay(config.RespawnDelay, spawnPack, kind)
		return
	end
	local pack: PackState = {
		kind = kind,
		config = config,
		camp = camp,
		members = {},
		formation = {},
		roles = {},
		target = nil,
		targetRoot = nil,
		hurtBy = nil,
		roamGoal = camp,
		nextRoam = os.clock() + packRandom:NextNumber(config.RoamPause[1], config.RoamPause[2]),
		returning = false,
	}
	table.insert(packs, pack)
	local size = packRandom:NextInteger(config.Min, config.Max)
	for index = 1, size do
		-- Members stand in a loose ring round the pack's centre.
		local angle = index / size * math.pi * 2 + packRandom:NextNumber(-0.3, 0.3)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * config.Spread * packRandom:NextNumber(0.6, 1)
		local member = spawnEnemy(Vector2.new(camp.X + offset.X, camp.Z + offset.Z), kind, pack)
		if member then
			pack.formation[member] = offset
		end
	end
	print(`[EnemyService] A pack of {#pack.members} {kind.DisplayName}s formed at {math.floor(camp.X)}, {math.floor(camp.Z)}`)

	task.spawn(function()
		while #aliveMembers(pack) > 0 do
			thinkPack(pack)
			task.wait(PACK_TICK)
		end
		-- Wiped out: a new pack forms somewhere else after a while.
		table.remove(packs, table.find(packs, pack) :: number)
		task.wait(config.RespawnDelay)
		for _, member in pack.members do
			packOf[member] = nil
			typeOf[member] = nil
			if member.Parent then
				member:Destroy()
			end
		end
		spawnPack(kind)
	end)
end

-- Spawns one more enemy of `kind` (an EnemyConfig entry) at X/Z (dropped onto the ground
-- there); it respawns there too. Yields while the model loads, so call it with task.spawn.
EnemyService.spawnAt = spawnEnemy

-- Like spawnAt, but the enemy never respawns: once dead, its body is cleared away. Yields
-- while the model loads.
function EnemyService.spawnOnce(spawnPoint: Vector2, kind: EnemyType): Model?
	return spawnEnemy(spawnPoint, kind, nil, true)
end

-- Like spawnOnce, but dropped onto the floor just below `position` (not the land's ground), for
-- floors up in the sky like a dungeon's. Yields while the model loads.
-- `roam` (dungeon orcs): see Roam.
function EnemyService.spawnOnFloor(position: Vector3, kind: EnemyType, roam: Roam?): Model?
	return spawnEnemy(Vector2.new(position.X, position.Z), kind, nil, true, nil, nil, position.Y, roam)
end

-- A sparring enemy for `owner` (see the top): chases and attacks only them. Never respawns.
-- Yields while the model loads.
function EnemyService.spawnSparring(spawnPoint: Vector2, kind: EnemyType, owner: Player): Model?
	return spawnEnemy(spawnPoint, kind, nil, true, owner)
end

-- Like spawnSparring, but with no AI: the caller moves it and runs its attacks.
function EnemyService.spawnPuppet(spawnPoint: Vector2, kind: EnemyType, owner: Player): Model?
	return spawnEnemy(spawnPoint, kind, nil, true, owner, true)
end

function EnemyService.start()
	enemiesFolder.Parent = workspace

	-- A pack member that's hit makes its pack turn on whoever hit it.
	HealthService.addDamageFilter(function(target: Model, amount: number, source: Player?)
		local owner = ownerOf[target]
		if owner and source ~= owner then
			return 0 -- someone else's sparring partner
		end
		local pack = packOf[target]
		if pack and pack.returning then
			return 0 -- walking home after giving up: can't be worn down on the way
		end
		if pack and source and source.Character and not pack.target then
			pack.hurtBy = source.Character
		end
		return amount
	end)

	-- A dead body stops where it is and tips over onto its side, whole.
	local function topple(model: Model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.2)
			end
		end
		root.Anchored = true
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local yaw = if look.Magnitude > 0.01 then CFrame.lookAlong(Vector3.zero, look.Unit) else CFrame.identity
		local lying = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 + root.Size.X / 2
		local fallen = CFrame.new(root.Position.X, lying, root.Position.Z) * yaw * CFrame.Angles(0, 0, math.rad(90))
		TweenService:Create(root, DEATH_TIP, { CFrame = fallen }):Play()
	end

	-- Fades the body out and clears it away, `after` seconds from now (then runs `andThen`).
	local function clearBody(model: Model, after: number, andThen: (() -> ())?)
		task.delay(math.max(0, after - DEATH_FADE.Time), function()
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					TweenService:Create(part, DEATH_FADE, { Transparency = 1 }):Play()
				elseif part:IsA("Decal") then
					TweenService:Create(part, DEATH_FADE, { Transparency = 1 }):Play()
				end
			end
			task.wait(DEATH_FADE.Time)
			if model.Parent then
				model:Destroy()
			end
			if andThen then
				andThen()
			end
		end)
	end

	HealthService.Died:Connect(function(model: Model, killer: Player?)
		local kind = typeOf[model]
		if kind then
			topple(model)
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if kind and kind.Drops and killer and not ownerOf[model] and root and root:IsA("BasePart") then
			for _, drop in kind.Drops do
				if dropRandom:NextNumber() < drop.Chance then
					for _ = 1, dropRandom:NextInteger(drop.Min, drop.Max) do
						LootService.drop(killer, drop.Item, root.Position)
					end
				end
			end
		end
		if oneOff[model] then
			oneOff[model] = nil
			ownerOf[model] = nil
			clearBody(model, typeOf[model].RespawnDelay) -- leave the body a moment, like the others
			typeOf[model] = nil
			return
		end
		local pack = packOf[model]
		if pack then
			-- Pack members don't respawn alone (the pack re-forms); clear the body away.
			clearBody(model, pack.kind.RespawnDelay)
			return
		end
		local spawnPoint = spawnPointOf[model]
		if not spawnPoint then
			return
		end
		spawnPointOf[model] = nil
		typeOf[model] = nil

		clearBody(model, kind.RespawnDelay, function()
			spawnEnemy(spawnPoint, kind)
		end)
	end)

	for _, kind in EnemyConfig.Types do
		for _, spawnPoint in kind.SpawnPoints do
			task.spawn(spawnEnemy, spawnPoint, kind)
		end
		if kind.Pack then
			task.spawn(function()
				-- The world (trees, ruins) is still being placed; wait so camps land on open ground.
				task.wait(3)
				for _ = 1, kind.Pack.Count do
					spawnPack(kind)
				end
			end)
		end
	end
end

return EnemyService
