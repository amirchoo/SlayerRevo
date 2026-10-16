--!strict
-- Bosses (BossConfig): builds one in its arena and fights it. DungeonService makes one per
-- run (BossService.spawn) and says who's fighting it (the run's players) and when the fight
-- starts (Fight:engage, when one walks into the arena). See BossConfig for the fight itself.
--
-- The model is rigged like the pets (PetService): its mesh is welded to an invisible
-- HumanoidRootPart with a Humanoid (so it walks with MoveTo), and the client poses its bones
-- from the .glb's own clip data (BossAnimator). The server says which clip by attributes on
-- the model: "BossAction" (a clip name, "" for idle/walk/run by speed), "BossActionAt" (when
-- it started, workspace:GetServerTimeNow()) and "BossActionSpeed". It also sets "Boss",
-- "BossId", "BossState" (Dormant, Intro, Fight, Dead) and "Phase" for the boss bar.
--
-- Damage is the server's: each blow is checked against the attack's Shape at the moment it
-- lands (BossConfig times), so a dash or stepping out dodges it. Telegraphs, the beam, slam
-- dust and knockback go to the fighters' clients over the DungeonEvent remote:
--   ("Telegraph", { boss, shape, floorY, duration, aim }), ("Beam", { boss, length, width,
--   duration }), ("Slam", { position, radius }), ("Knockback", { direction, speed }),
--   ("Banner", { text }).
-- Only the fighters can hurt it, and only while it's fighting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BlockService = require(script.Parent.BlockService)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local EnemyEffects = require(script.Parent.EnemyEffects)

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local RigClips = require(ReplicatedStorage.Shared.RigClips)

type Boss = BossConfig.Boss
type Attack = BossConfig.Attack

local bossEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DungeonEvent") :: RemoteEvent

local TICK = 0.1 -- seconds between decisions
local AIM_STEP = 0.05 -- seconds between turns while aiming
local TURN_RATE = math.rad(240) -- degrees/s it turns while aiming
local BEHIND_ANGLE = math.rad(110) -- further round than this from its front is "behind"
local PLAYER_RADIUS = 1.5 -- added to every shape, so a hit on the edge of a player counts
-- Per stud of Height: from the ground to the bottom of the root (Humanoid.HipHeight), and the
-- invisible root's size (roughly the trunk; it's solid, so players can't walk into the boss).
local HIP = 0.3
local ROOT_SIZE = Vector3.new(0.4, 0.3, 0.3)
local ROOT_DENSITY = 20 -- heavy, so players can't shove it

export type Fight = {
	config: Boss,
	model: Model,
	-- Set by the caller: the players in this fight, and where the arena is.
	fighters: () -> { Player },
	arenaCenter: Vector3,
	arenaRadius: number,
	onDefeated: ((killer: Player?) -> ())?,
	onWipe: (() -> ())?,
	engage: (self: Fight) -> (),
	destroy: (self: Fight) -> (),
}

type State = {
	fight: Fight,
	config: Boss,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	home: CFrame,
	floorY: number,
	state: "Dormant" | "Intro" | "Fight" | "Dead",
	phase: number,
	token: number, -- bumped to cancel whatever the boss is doing (stagger, wipe, death)
	busy: boolean, -- attacking, staggered or flinching: not choosing what to do next
	target: Model?,
	poise: number,
	parries: number, -- parried blows since its last stagger (ParriesToStun knocks it down)
	lastUsed: { [string]: number },
	lastHurt: number,
}

local BossService = {}

local states: { [Model]: State } = {}
local random = Random.new()
local clipData: { [string]: RigClips.Data } = {}

local function dataFor(config: Boss): RigClips.Data
	local data = clipData[config.Clips]
	if not data then
		data = (require :: any)(ReplicatedStorage.Shared.EnemyClips:WaitForChild(config.Clips)) :: RigClips.Data
		clipData[config.Clips] = data
	end
	return data
end

local function clipLength(config: Boss, clip: string): number
	local entry = dataFor(config).Clips[clip]
	return if entry then entry.Length else 1
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function send(boss: State, kind: string, data: { [string]: any })
	for _, player in boss.fight.fighters() do
		bossEvent:FireClient(player, kind, data)
	end
end

local function setAction(boss: State, clip: string, speed: number?)
	boss.model:SetAttribute("BossAction", clip)
	boss.model:SetAttribute("BossActionAt", workspace:GetServerTimeNow())
	boss.model:SetAttribute("BossActionSpeed", speed or 1)
end

local function setState(boss: State, state: "Dormant" | "Intro" | "Fight" | "Dead")
	boss.state = state
	boss.model:SetAttribute("BossState", state)
end

-- Fighters alive and inside the arena (the ones it can see and hit).
local function present(boss: State): { Model }
	local inside = {}
	for _, player in boss.fight.fighters() do
		local character = player.Character
		local root = rootOf(character)
		if character and root and HealthService.isAlive(character) then
			if flat(root.Position - boss.fight.arenaCenter).Magnitude <= boss.fight.arenaRadius + 4 then
				table.insert(inside, character)
			end
		end
	end
	return inside
end

local function phaseOf(boss: State): BossConfig.Phase
	return boss.config.Phases[boss.phase]
end

-- Turns toward `position` by at most `maxAngle` radians.
local function turnToward(boss: State, position: Vector3, maxAngle: number)
	local root = boss.root
	local want = flat(position - root.Position)
	if want.Magnitude < 0.1 then
		return
	end
	local look = flat(root.CFrame.LookVector).Unit
	local angle = math.atan2(look:Cross(want.Unit).Y, look:Dot(want.Unit))
	local step = math.clamp(angle, -maxAngle, maxAngle)
	local turned = CFrame.Angles(0, step, 0):VectorToWorldSpace(look)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + turned)
end

-- Is a player standing at `position` inside the attack's shape, from where the boss stands now?
local function inShape(boss: State, shape: BossConfig.Shape, position: Vector3): boolean
	local frame = CFrame.lookAt(flat(boss.root.Position), flat(boss.root.Position) + flat(boss.root.CFrame.LookVector))
	local offset = frame:PointToObjectSpace(flat(position))
	if math.abs(position.Y - boss.floorY) > boss.config.Height then
		return false -- far above or below
	end
	if shape.Kind == "Cone" then
		local reach = Vector2.new(offset.X, offset.Z).Magnitude
		local angle = math.deg(math.atan2(math.abs(offset.X), -offset.Z))
		return reach <= (shape.Radius or 0) + PLAYER_RADIUS and angle <= (shape.Angle or 180)
	elseif shape.Kind == "Circle" then
		local center = Vector2.new(0, -(shape.Forward or 0))
		return (Vector2.new(offset.X, offset.Z) - center).Magnitude <= (shape.Radius or 0) + PLAYER_RADIUS
	else
		local along = -offset.Z
		return along >= 0 and along <= (shape.Length or 0) and math.abs(offset.X) <= (shape.Width or 0) / 2 + PLAYER_RADIUS
	end
end

local stagger: (boss: State) -> ()

-- One blow of `attack` landing now: everyone in the shape (not already in `struck`) takes
-- `damage`, unless they parry it. Each parry counts; the ParriesToStun-th staggers the boss
-- and returns true (the attack stops). Until then a parried blow just misses that player.
local function land(boss: State, attack: Attack, damage: number, struck: { [Model]: boolean }): boolean
	for _, character in present(boss) do
		local root = rootOf(character)
		if root and not struck[character] and inShape(boss, attack.Shape, root.Position) then
			struck[character] = true
			if attack.Parryable and BlockService.tryParry(character, boss.model) then
				boss.parries += 1
				local needed = boss.config.ParriesToStun
				local player = Players:GetPlayerFromCharacter(character)
				if boss.parries >= needed then
					if player then
						bossEvent:FireClient(player, "Banner", { text = `{boss.config.DisplayName} is staggered!`, small = true })
					end
					stagger(boss)
					return true
				end
				boss.model:SetAttribute("Parries", boss.parries)
				if player then
					bossEvent:FireClient(player, "Banner", { text = `Parried! {boss.parries}/{needed}`, small = true })
				end
				continue
			end
			local dealt = HealthService.damage(character, damage, nil, boss.root.Position)
			if dealt > 0 then
				local impact, direction = HitEffects.meleeImpactPoint(character, boss.root.Position)
				HitEffects.broadcast(character, impact, direction, "DemonClaw", dealt)
				local player = Players:GetPlayerFromCharacter(character)
				if player and attack.Knockback then
					local away = flat(root.Position - boss.root.Position)
					local thrown = if away.Magnitude > 0.1 then away.Unit else -flat(root.CFrame.LookVector).Unit
					bossEvent:FireClient(player, "Knockback", { direction = thrown, speed = attack.Knockback })
				end
			end
		end
	end
	return false
end

-- Waits until `time` seconds after `start`; false if the boss was interrupted meanwhile.
local function waitUntil(boss: State, token: number, start: number, time: number): boolean
	local left = start + time - os.clock()
	if left > 0 then
		task.wait(left)
	end
	return boss.token == token and boss.state == "Fight"
end

local function perform(boss: State, name: string, attack: Attack)
	boss.token += 1
	local token = boss.token
	boss.busy = true
	boss.lastUsed[name] = os.clock()
	local speed = phaseOf(boss).Speed
	local humanoid, root = boss.humanoid, boss.root
	humanoid:MoveTo(root.Position)
	humanoid.AutoRotate = false

	local lead = attack.Lead or 0
	local firstHit = if attack.Hits then attack.Hits[1] elseif attack.Window then attack.Window[1] else 0
	if attack.Telegraph then
		send(boss, "Telegraph", {
			boss = boss.model,
			shape = attack.Shape,
			floorY = boss.floorY,
			duration = lead + firstHit / speed,
			aim = lead + attack.Aim / speed,
		})
	end
	local start = os.clock()
	if lead > 0 and not waitUntil(boss, token, start, lead) then
		return
	end
	setAction(boss, attack.Clip, speed)
	start = os.clock()

	-- Keep turning to the target until Aim.
	task.spawn(function()
		while boss.token == token and os.clock() - start < attack.Aim / speed do
			local targetRoot = rootOf(boss.target)
			if targetRoot then
				turnToward(boss, targetRoot.Position, TURN_RATE * AIM_STEP)
			end
			task.wait(AIM_STEP)
		end
	end)

	if attack.Hits then
		for index, time in attack.Hits do
			if not waitUntil(boss, token, start, time / speed) then
				return
			end
			local damage = attack.Damage[index] or attack.Damage[1]
			if land(boss, attack, damage, {}) then
				return
			end
			if attack.Shape.Kind == "Circle" and (attack.Shape.Forward or 0) > 0 then
				send(boss, "Slam", { position = (root.CFrame * CFrame.new(0, 0, -(attack.Shape.Forward or 0))).Position, radius = attack.Shape.Radius })
			end
		end
	elseif attack.Window then
		if not waitUntil(boss, token, start, attack.Window[1] / speed) then
			return
		end
		if attack.Shape.Kind == "Line" then
			send(boss, "Beam", { boss = boss.model, length = attack.Shape.Length, width = attack.Shape.Width, duration = (attack.Window[2] - attack.Window[1]) / speed })
		end
		local struck = {}
		while os.clock() - start < attack.Window[2] / speed do
			if boss.token ~= token or boss.state ~= "Fight" then
				return
			end
			if land(boss, attack, attack.Damage[1], struck) then
				return
			end
			task.wait(0.05)
		end
	end

	if not waitUntil(boss, token, start, clipLength(boss.config, attack.Clip) / speed) then
		return
	end
	setAction(boss, "")
	humanoid.AutoRotate = true
	if not waitUntil(boss, token, os.clock(), phaseOf(boss).Recovery) then
		return
	end
	boss.busy = false
end

-- Knocked off its feet: everything stops for StunTime (the punish window).
stagger = function(boss: State)
	if boss.state ~= "Fight" then
		return
	end
	boss.token += 1
	local token = boss.token
	boss.busy = true
	boss.poise = 0
	boss.parries = 0
	boss.model:SetAttribute("Parries", 0)
	boss.humanoid:MoveTo(boss.root.Position)
	setAction(boss, boss.config.Animations.Stunned)
	task.delay(boss.config.StunTime, function()
		if boss.token == token and boss.state == "Fight" then
			setAction(boss, "")
			boss.humanoid.AutoRotate = true
			boss.busy = false
		end
	end)
end

-- A short flinch from a big hit, between attacks.
local function hurt(boss: State)
	boss.token += 1
	local token = boss.token
	boss.busy = true
	boss.lastHurt = os.clock()
	boss.humanoid:MoveTo(boss.root.Position)
	local clip = boss.config.Animations.Hurt
	setAction(boss, clip)
	task.delay(clipLength(boss.config, clip), function()
		if boss.token == token and boss.state == "Fight" then
			setAction(boss, "")
			boss.busy = false
		end
	end)
end

local function updatePhase(boss: State)
	local health, maxHealth = HealthService.getHealth(boss.model)
	if not health or not maxHealth then
		return
	end
	local fraction = health / maxHealth
	local phases = boss.config.Phases
	while boss.phase < #phases and fraction <= phases[boss.phase + 1].HealthBelow do
		boss.phase += 1
		boss.model:SetAttribute("Phase", boss.phase)
		local banner = phases[boss.phase].Banner
		if banner then
			send(boss, "Banner", { text = banner })
		end
	end
end

-- Picks an attack for where the target stands (BossConfig When), or nil to keep closing in.
local function choose(boss: State, targetRoot: BasePart): (string?, Attack?)
	local config = boss.config
	local offset = flat(targetRoot.Position - boss.root.Position)
	local distance = offset.Magnitude
	local look = flat(boss.root.CFrame.LookVector).Unit
	local behind = distance > 0.1 and math.acos(math.clamp(look:Dot(offset.Unit), -1, 1)) > BEHIND_ANGLE
	local where = if distance <= config.MeleeRange then (if behind then "Behind" else "Near") elseif distance >= config.FarRange then "Far" else nil
	if not where then
		return nil, nil
	end
	local now = os.clock()
	local total = 0
	local options: { { name: string, attack: Attack, weight: number } } = {}
	for name, attack in config.Attacks do
		local weight = (attack.When :: any)[where] :: number?
		if weight and attack.Phase <= boss.phase and now - (boss.lastUsed[name] or -math.huge) >= attack.Cooldown then
			table.insert(options, { name = name, attack = attack, weight = weight })
			total += weight
		end
	end
	local roll = random:NextNumber(0, total)
	for _, option in options do
		roll -= option.weight
		if roll <= 0 then
			return option.name, option.attack
		end
	end
	return nil, nil
end

-- Nobody left standing in the arena: heal up and wait for the next try.
local function reset(boss: State)
	boss.token += 1
	boss.busy = false
	boss.target = nil
	boss.poise = 0
	boss.parries = 0
	boss.model:SetAttribute("Parries", 0)
	boss.phase = 1
	table.clear(boss.lastUsed)
	boss.model:SetAttribute("Phase", 1)
	local _, maxHealth = HealthService.getHealth(boss.model)
	if maxHealth then
		HealthService.heal(boss.model, maxHealth)
	end
	boss.humanoid:MoveTo(boss.root.Position)
	boss.humanoid.AutoRotate = true
	boss.root.AssemblyLinearVelocity = Vector3.zero
	boss.model:PivotTo(boss.home)
	setAction(boss, "")
	setState(boss, "Dormant")
	local onWipe = boss.fight.onWipe
	if onWipe then
		onWipe()
	end
end

local function think(boss: State)
	if boss.state ~= "Fight" then
		return
	end
	local inside = present(boss)
	if #inside == 0 then
		reset(boss)
		return
	end
	updatePhase(boss)
	if boss.busy then
		return
	end
	-- The nearest fighter (sticking with the current one unless another is much closer).
	local best, bestDistance = nil, math.huge
	for _, character in inside do
		local root = rootOf(character) :: BasePart
		local distance = (root.Position - boss.root.Position).Magnitude - (if character == boss.target then 8 else 0)
		if distance < bestDistance then
			best, bestDistance = character, distance
		end
	end
	boss.target = best
	local targetRoot = rootOf(best)
	if not targetRoot then
		return
	end
	local name, attack = choose(boss, targetRoot)
	if name and attack then
		task.spawn(perform, boss, name, attack)
		return
	end
	local config = boss.config
	local distance = flat(targetRoot.Position - boss.root.Position).Magnitude
	local speed = if distance > config.RunAbove then config.RunSpeed else config.WalkSpeed
	boss.humanoid.WalkSpeed = speed * EnemyEffects.speedFactor(boss.model)
	if distance > config.MeleeRange * 0.6 then
		boss.humanoid:MoveTo(targetRoot.Position)
	else
		boss.humanoid:MoveTo(boss.root.Position)
		turnToward(boss, targetRoot.Position, TURN_RATE * TICK)
	end
end

-- A rigged copy of the boss's model with its feet at the origin, facing -Z, or nil.
local function build(config: Boss): (Model?, Humanoid?, BasePart?)
	local models = ServerStorage:FindFirstChild("EnemyModels")
	local template = models and models:FindFirstChild(config.Model)
	if not template or not template:IsA("Model") then
		warn(`[BossService] no model "{config.Model}" in ServerStorage.EnemyModels; {config.DisplayName} isn't spawned (see assets/enemies/README.md)`)
		return nil, nil, nil
	end
	local model = template:Clone()
	model.Name = config.DisplayName
	-- The client poses the bones (BossAnimator); nothing else may move them.
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("AnimationController")
			or descendant:IsA("Humanoid")
			or descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant.Name == "AnimSaves"
			or descendant.Name == "InitialPoses"
		then
			descendant:Destroy()
		end
	end
	local _, importedSize = model:GetBoundingBox()
	if importedSize.Y > 0 then
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
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - box.Position + Vector3.new(0, size.Y / 2, 0))
	model:PivotTo(CFrame.Angles(0, math.rad(config.FacingOffset), 0) * model:GetPivot())

	local height = config.Height
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * height
	root.CFrame = CFrame.new(0, (HIP + ROOT_SIZE.Y / 2) * height, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(ROOT_DENSITY, 0.3, 0)
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

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 humanoids stand on HipHeight
	humanoid.HipHeight = HIP * height
	humanoid.WalkSpeed = config.WalkSpeed
	humanoid.DisplayName = config.DisplayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Jumping } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- reaches clients whole, bones and all
	return model, humanoid, root
end

-- Makes `config`'s boss standing at `at` (feet on the floor, facing its front), dormant until
-- Fight:engage. Returns nil if its model isn't in ServerStorage.EnemyModels.
function BossService.spawn(config: Boss, at: CFrame, fighters: () -> { Player }, arenaCenter: Vector3, arenaRadius: number): Fight?
	local model, humanoid, root = build(config)
	if not model or not humanoid or not root then
		return nil
	end
	local home = at * CFrame.new(0, (HIP + ROOT_SIZE.Y / 2) * config.Height, 0)
	model:PivotTo(home)

	local fight = {} :: Fight
	fight.config = config
	fight.model = model
	fight.fighters = fighters
	fight.arenaCenter = arenaCenter
	fight.arenaRadius = arenaRadius

	local boss: State = {
		fight = fight,
		config = config,
		model = model,
		humanoid = humanoid,
		root = root,
		home = home,
		floorY = at.Position.Y,
		state = "Dormant",
		phase = 1,
		token = 0,
		busy = false,
		target = nil,
		poise = 0,
		parries = 0,
		lastUsed = {},
		lastHurt = 0,
	}

	function fight.engage(_self: Fight)
		if boss.state ~= "Dormant" then
			return
		end
		boss.token += 1
		local token = boss.token
		setState(boss, "Intro")
		local inside = present(boss)
		local first = rootOf(inside[1])
		if first then
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(first.Position.X, root.Position.Y, first.Position.Z))
		end
		local clip = config.Animations.Intro
		setAction(boss, clip)
		task.delay(clipLength(config, clip), function()
			if boss.token == token and boss.state == "Intro" then
				setAction(boss, "")
				boss.busy = false
				setState(boss, "Fight")
			end
		end)
	end

	function fight.destroy(_self: Fight)
		boss.token += 1
		states[model] = nil
		if model.Parent then
			model:Destroy()
		end
	end

	states[model] = boss
	model:SetAttribute("Boss", true)
	model:SetAttribute("BossId", config.Id)
	model:SetAttribute("EnemyId", config.Id)
	model:SetAttribute("Level", config.Level)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("XPReward", config.XP) -- ProgressionService gives it to whoever defeats it
	model:SetAttribute("CoinReward", config.Coins) -- CurrencyService gives it to whoever defeats it
	setAction(boss, "")
	setState(boss, "Dormant")
	HealthService.register(model, config.MaxHealth)
	model.Parent = workspace:FindFirstChild("Enemies") or workspace
	root.Anchored = false
	root:SetNetworkOwner(nil) -- the server walks it

	task.spawn(function()
		while model.Parent and boss.state ~= "Dead" do
			think(boss)
			task.wait(TICK)
		end
	end)
	return fight
end

function BossService.start()
	-- Only its fighters can hurt it, only while it's fighting. Hitting it before then (from the
	-- doorway, say) starts the fight. Damage builds up its stagger, and a big hit between
	-- attacks makes it flinch.
	HealthService.addDamageFilter(function(target: Model, amount: number, source: Player?)
		local boss = states[target]
		if not boss then
			return amount
		end
		if not source or not table.find(boss.fight.fighters(), source) then
			return 0
		end
		if boss.state == "Dormant" then
			boss.fight:engage()
			return 0
		elseif boss.state ~= "Fight" then
			return 0
		end
		boss.poise += amount
		if boss.poise >= boss.config.Poise then
			stagger(boss)
		elseif amount >= boss.config.HurtAbove and not boss.busy and os.clock() - boss.lastHurt > 1.5 then
			hurt(boss)
		end
		return amount
	end)

	HealthService.Died:Connect(function(model: Model, killer: Player?)
		local boss = states[model]
		if not boss then
			return
		end
		boss.token += 1
		setState(boss, "Dead")
		setAction(boss, boss.config.Animations.Death)
		boss.humanoid:MoveTo(boss.root.Position)
		boss.humanoid.AutoRotate = false
		task.delay(0.5, function()
			if boss.root.Parent then
				boss.root.CanCollide = false
				boss.root.Anchored = true
			end
		end)
		local onDefeated = boss.fight.onDefeated
		if onDefeated then
			onDefeated(killer)
		end
	end)
end

return BossService
