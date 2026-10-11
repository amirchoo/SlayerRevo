--!strict
-- The staff: a caster weapon with five elements (CombatConfig.Staff). Server side:
--   * gives players the staff (a real model if there is one, see WeaponModels), with a "Tip"
--     attachment at its end that the client gathers charging sparks at
--   * StaffElement (name): switches element; kept in the player's "StaffElement" attribute
--   * StaffCast (aim point): a light missile, after its cast delay
--   * StaffCharge / StaffRelease (aim point): a charged heavy attack; the server times the
--     charge (so it can't be faked), and releases it by itself after MaxHold. Each element's
--     is different: Fire's wave of flame along the ground, Water's torrent, Earth's thrown
--     boulder, Lightning's thunder strike, Faith's healing burst (see Heavy.Kind in config).
-- Light missiles fly on the server (raycast each step, like arrows) and apply their element
-- on impact: damage, slow, knockback, chain lightning, or Faith's healing (players only;
-- enemies just get nicked). Skills scale damage, healing, charge speed, and stamina
-- (SkillMath, tree "Staff"). Spells spend mana (ManaService), not stamina.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local InventoryService = require(script.Parent.InventoryService)
local MeleeHitbox = require(script.Parent.MeleeHitbox)
local RemoteGuard = require(script.Parent.RemoteGuard)
local ManaService = require(script.Parent.ManaService)
local WeaponModels = require(script.Parent.WeaponModels)

type Element = CombatConfig.StaffElement

local STAFF = CombatConfig.Staff
local TIMING_SLACK = 0.1
local CAST_HEIGHT = 1.5 -- missiles leave from about chest height...
local CAST_FORWARD = 2.5 -- ...this far in front of the caster
local KNOCKBACK_TIME = 0.2
local BOLT_TIME = 0.15 -- how long a chain-lightning bolt stays drawn

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local elementRemote = remotes:WaitForChild("StaffElement") :: RemoteEvent
local castRemote = remotes:WaitForChild("StaffCast") :: RemoteEvent
local chargeRemote = remotes:WaitForChild("StaffCharge") :: RemoteEvent
local releaseRemote = remotes:WaitForChild("StaffRelease") :: RemoteEvent
local damageRemote = remotes:WaitForChild("DamageDealt") :: RemoteEvent
local shockwaveRemote = remotes:WaitForChild("GroundShockwave") :: RemoteEvent

local StaffService = {}

local missiles = Instance.new("Folder")
missiles.Name = "StaffMissiles"

local lastCast: { [Player]: number } = {}
local lastBlast: { [Player]: number } = {}
local charging: { [Player]: { started: number, element: Element } } = {}

local function elementNamed(name: unknown): Element?
	for _, element in STAFF.Elements do
		if element.Name == name then
			return element
		end
	end
	return nil
end

-- The player's chosen element if they've unlocked it, else their first unlocked one (nil if
-- none: the Mage class or an element still has to be unlocked in the skill tree).
local function currentElement(player: Player): Element?
	local chosen = elementNamed(player:GetAttribute("StaffElement"))
	if chosen and SkillMath.staffUnlocked(player, chosen.Name) then
		return chosen
	end
	for _, element in STAFF.Elements do
		if SkillMath.staffUnlocked(player, element.Name) then
			return element
		end
	end
	return nil
end

-- The staff, ready to cast: in hand, alive. Returns the character, its root, and the tool.
local function staffInHand(player: Player): (Model?, BasePart?, Tool?)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return nil, nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not tool or tool.Name ~= STAFF.ToolName or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, root, tool
end

-- Never trust client input: a real, finite position.
local function validAim(aim: unknown): Vector3?
	if typeof(aim) ~= "Vector3" or aim.Magnitude ~= aim.Magnitude or aim.Magnitude > 1e6 then
		return nil
	end
	return aim
end

-- The tool ---------------------------------------------------------------------------------

-- Placeholder staff: a long wooden shaft held a little below the middle.
local function createStaff(): Tool
	local tool = Instance.new("Tool")
	tool.Name = STAFF.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool.Grip = CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0)

	local grip = Instance.new("Part")
	grip.Name = HandGrip.GRIP_NAME
	grip.Size = Vector3.new(0.3, 0.3, 1.2)
	grip.Color = Color3.fromRGB(70, 45, 30)
	grip.Material = Enum.Material.Fabric
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.Parent = tool

	local length, gripFrom = STAFF.ModelFit.Length, STAFF.ModelFit.GripFrom
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.24, 0.24, length)
	shaft.Color = Color3.fromRGB(110, 75, 45)
	shaft.Material = Enum.Material.Wood
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.Massless = true
	shaft.CFrame = grip.CFrame * CFrame.new(0, 0, length * (0.5 - gripFrom))
	shaft.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = shaft
	weld.Parent = shaft

	WeaponModels.apply(tool, STAFF.ModelFit) -- a real model, if one's been added (assets/weapons)

	-- Where the staff's end is, for the client's charging sparks.
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, length * (1 - gripFrom))
	tip.Parent = grip
	return tool
end

local function giveStaff(player: Player, template: Tool)
	local staff = template:Clone()
	staff.Equipped:Connect(function()
		local character = staff.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(staff, character, STAFF.Hand :: HandGrip.Hand, "StaffGrip")
		end
	end)
	staff.Unequipped:Connect(function()
		HandGrip.detach(staff, "StaffGrip")
		if charging[player] then
			charging[player] = nil
			player:SetAttribute("HeavyAttacking", false)
		end
	end)
	InventoryService.give(player, staff) -- the hotbar, or stored in the backpack
end

-- Impacts ----------------------------------------------------------------------------------

local function topOf(model: Model): Vector3
	local cframe, size = model:GetBoundingBox()
	return cframe.Position + Vector3.new(0, size.Y / 2, 0)
end

-- A short-lived jagged bolt between two points (chain lightning, thunder), seen by everyone.
local function bolt(from: Vector3, to: Vector3, color: Color3, thickness: number?)
	local points = { from }
	local random = Random.new()
	local jitter = math.max((to - from).Magnitude / 12, 0.8)
	for index = 1, 3 do
		table.insert(points, from:Lerp(to, index / 4) + random:NextUnitVector() * jitter)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local segment = Instance.new("Part")
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Size = Vector3.new(thickness or 0.15, thickness or 0.15, (b - a).Magnitude)
		segment.CFrame = CFrame.lookAt((a + b) / 2, b)
		segment.Parent = missiles
		Debris:AddItem(segment, BOLT_TIME)
	end
end

-- Damages one enemy with the element's damage, shows it, and returns what was dealt.
local function damageEnemy(player: Player, model: Model, amount: number, origin: Vector3, element: Element): number
	local dealt = HealthService.damage(model, amount, player, origin)
	if dealt > 0 then
		damageRemote:FireClient(player, topOf(model), dealt, nil, model)
		local impact, direction = HitEffects.meleeImpactPoint(model, origin)
		HitEffects.broadcast(model, impact, direction, `Staff{element.Name}`, dealt)
	end
	return dealt
end

type Effects = {
	Knockback: number?,
	Stun: number?,
	Slow: { Factor: number, Duration: number }?,
	Burn: { Damage: number, Interval: number, Duration: number }?,
	Chain: { Count: number, Range: number, DamageScale: number }?,
}

-- The element's lasting effects on an enemy that was hit, with the caster's element skills
-- (Undertow: harder knockback, Tremor: longer stun, Scorch: stronger burns).
local function applyEffects(player: Player, model: Model, effects: Effects, origin: Vector3, element: Element)
	if not HealthService.isAlive(model) then
		return
	end
	if effects.Knockback then
		local knockback = effects.Knockback * (1 + (if element.Name == "Water" then SkillMath.weapon(player, STAFF.ToolName, "WaterKnockback") else 0))
		EnemyEffects.knockBack(model, origin, knockback, KNOCKBACK_TIME)
	end
	if effects.Stun then
		EnemyEffects.stun(model, effects.Stun + SkillMath.weapon(player, STAFF.ToolName, "EarthStun"))
	end
	if effects.Slow then
		EnemyEffects.slow(model, effects.Slow.Factor, effects.Slow.Duration)
	end
	if effects.Burn then
		local burn = effects.Burn.Damage + SkillMath.weapon(player, STAFF.ToolName, "BurnDamage")
		EnemyEffects.burn(model, player, burn, effects.Burn.Interval, effects.Burn.Duration)
	end
end

-- Chain lightning: jumps from `first` to the nearest other enemies in range.
local function chain(player: Player, first: Model, damage: number, chainInfo: { Count: number, Range: number, DamageScale: number }, element: Element)
	local hit: { [Model]: boolean } = { [first] = true }
	local from = first:GetBoundingBox().Position
	for _ = 1, chainInfo.Count do
		local nearest: Model?, nearestDistance = nil, chainInfo.Range
		for _, part in workspace:GetPartBoundsInRadius(from, chainInfo.Range) do
			local model = HealthService.findDamageable(part)
			if model and not hit[model] and not Players:GetPlayerFromCharacter(model) and HealthService.isAlive(model) then
				local distance = (model:GetBoundingBox().Position - from).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = model, distance
				end
			end
		end
		if not nearest then
			return
		end
		hit[nearest] = true
		local to = nearest:GetBoundingBox().Position
		bolt(from, to, element.Color)
		damageEnemy(player, nearest, math.round(damage * chainInfo.DamageScale), from, element)
		from = to
	end
end

local function healPlayer(caster: Player, target: Player, amount: number)
	local character = target.Character
	if not character then
		return
	end
	local healed = HealthService.heal(character, amount)
	if healed > 0 then
		damageRemote:FireClient(caster, topOf(character), healed, "Heal")
		if target ~= caster then
			damageRemote:FireClient(target, topOf(character), healed, "Heal")
		end
	end
end

local function healPower(player: Player): number
	return 1 + SkillMath.weapon(player, STAFF.ToolName, "HealPower")
end

-- A light missile landed on `model` (or on nothing) at `position`.
local function lightImpact(player: Player, element: Element, model: Model?, position: Vector3, direction: Vector3)
	if not model then
		return
	end
	local light = element.Light
	local target = Players:GetPlayerFromCharacter(model)
	if target then
		if light.Heal and target ~= player then
			healPlayer(player, target, math.round(light.Heal * healPower(player)))
		end
		return
	end
	local origin = position - direction * 2
	local damage = SkillMath.spellDamage(player, element.Name, light.Damage, "Light")
	if damageEnemy(player, model, damage, origin, element) > 0 then
		applyEffects(player, model, light, origin, element)
		if light.Chain then
			chain(player, model, damage, light.Chain, element)
		end
	end
end

-- Heavy attacks --------------------------------------------------------------------------------

type Heavy = typeof(STAFF.Elements[1].Heavy)

-- The ground under `position` (or a little below it, over nothing).
local function groundUnder(position: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, missiles }
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 3, 0)
end

local function flatDirection(direction: Vector3, root: BasePart): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
end

-- Damages each enemy among `parts` once (skipping players and anything in `hit`), applying
-- the heavy's effects from `origin`.
local function hitParts(player: Player, parts: { BasePart }, hit: { [Model]: boolean }, damage: number, heavy: Heavy, origin: Vector3, element: Element)
	for _, part in parts do
		local model = HealthService.findDamageable(part)
		if model and not hit[model] and not Players:GetPlayerFromCharacter(model) then
			hit[model] = true
			if damageEnemy(player, model, damage, origin, element) > 0 then
				applyEffects(player, model, heavy, origin, element)
			end
		end
	end
end

local function visualPart(size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = missiles
	return part
end

-- Fire: the staff is slammed into the ground and a wall of fire rolls forward, widening as it
-- goes, burning everything it passes through (each enemy once).
local function fireWave(player: Player, character: Model, root: BasePart, element: Element, damage: number, direction: Vector3)
	local heavy = element.Heavy
	local range, width, speed = heavy.Range or 25, heavy.Width or 8, heavy.Speed or 35
	local forward = flatDirection(direction, root)
	local start = groundUnder(root.Position + forward * 2, character)
	shockwaveRemote:FireAllClients(start, 5, `Staff{element.Name}`)

	local wall = visualPart(Vector3.new(width * 0.5, 3, 1.5), CFrame.lookAt(start, start + forward), element.Color, 0.35)
	local flames = Instance.new("Fire")
	flames.Size = 9
	flames.Heat = 12
	flames.Color = element.Color
	flames.SecondaryColor = Color3.fromRGB(255, 220, 120)
	flames.Parent = wall
	local light = Instance.new("PointLight")
	light.Color = element.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = wall

	local hit: { [Model]: boolean } = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, missiles }
	local traveled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		traveled = math.min(traveled + speed * dt, range)
		local progress = traveled / range
		local currentWidth = width * (0.5 + 0.5 * progress)
		local ground = groundUnder(start + forward * traveled, character)
		local cframe = CFrame.lookAt(ground + Vector3.new(0, 1.5, 0), ground + Vector3.new(0, 1.5, 0) + forward)
		wall.CFrame = cframe
		wall.Size = Vector3.new(currentWidth, 3, 1.5)
		hitParts(player, workspace:GetPartBoundsInBox(cframe, Vector3.new(currentWidth, 7, 3), params), hit, damage, element.Heavy, ground, element)
		if traveled >= range then
			connection:Disconnect()
			flames.Enabled = false
			TweenService:Create(wall, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			Debris:AddItem(wall, 0.8)
		end
	end)
end

-- Water: a torrent straight ahead, hitting everything along it and pushing it back.
local function waterBlast(player: Player, character: Model, root: BasePart, element: Element, damage: number, direction: Vector3)
	local heavy = element.Heavy
	local range, width = heavy.Range or 25, heavy.Width or 7
	local forward = flatDirection(direction, root)
	local origin = root.Position + forward * 1.5
	local box = CFrame.lookAt(origin, origin + forward) * CFrame.new(0, 0, -range / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, missiles }
	hitParts(player, workspace:GetPartBoundsInBox(box, Vector3.new(width, 6, range), params), {}, damage, heavy, root.Position, element)

	-- The jet: shoots out to full length, then fades.
	local jet = visualPart(Vector3.new(width * 0.4, width * 0.4, 1), CFrame.lookAt(origin, origin + forward) * CFrame.new(0, 0, -0.5), element.Color, 0.3)
	local tween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(jet, tween, { Size = Vector3.new(width * 0.7, width * 0.5, range), CFrame = box }):Play()
	task.delay(0.18, function()
		TweenService:Create(jet, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(width, width * 0.7, range) }):Play()
		Debris:AddItem(jet, 0.4)
	end)
	shockwaveRemote:FireAllClients(groundUnder(origin + forward * range, character), width * 0.7, `Staff{element.Name}`)
end

-- Lightning: after a moment's warning, thunder strikes the aim point (within range), hitting
-- and slowing everything around it.
local function thunder(player: Player, character: Model, root: BasePart, element: Element, damage: number, aim: Vector3)
	local heavy = element.Heavy
	local range = heavy.Range or 60
	local radius = (heavy.Radius or 10) * (1 + SkillMath.weapon(player, STAFF.ToolName, "ElectricRadius")) -- Overload
	local offset = aim - root.Position
	if offset.Magnitude > range then
		aim = root.Position + offset.Unit * range
	end
	local ground = groundUnder(aim, character)
	-- The warning: a glowing ring on the ground where it'll land.
	local warning = visualPart(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), element.Color, 0.6)
	warning.Shape = Enum.PartType.Cylinder
	task.delay(heavy.Delay or 0.3, function()
		warning:Destroy()
		bolt(ground + Vector3.new(math.random(-4, 4), 70, math.random(-4, 4)), ground, element.Color, 0.6)
		bolt(ground + Vector3.new(math.random(-4, 4), 70, math.random(-4, 4)), ground, Color3.new(1, 1, 1), 0.3)
		shockwaveRemote:FireAllClients(ground, radius, `Staff{element.Name}`)
		if staffInHand(player) then
			for _, hit in MeleeHitbox.strikeAt(player, character, ground, radius, damage, `Staff{element.Name}`) do
				applyEffects(player, hit.model, heavy, ground, element)
			end
		end
	end)
end

-- Faith's charged burst: heals the caster and every player within its radius.
local function healingBurst(player: Player, root: BasePart, element: Element, power: number)
	local heavy = element.Heavy
	local amount = math.round(((heavy.MinHeal or 0) + ((heavy.MaxHeal or 0) - (heavy.MinHeal or 0)) * power) * healPower(player))
	local radius = (heavy.Radius or 15) * (1 + SkillMath.weapon(player, STAFF.ToolName, "FaithRadius")) -- Sanctuary
	shockwaveRemote:FireAllClients(root.Position - Vector3.new(0, 2.5, 0), radius, `Staff{element.Name}`)
	for _, other in Players:GetPlayers() do
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if otherRoot and otherRoot:IsA("BasePart") and (otherRoot.Position - root.Position).Magnitude <= radius then
			healPlayer(player, other, amount)
		end
	end
end

-- Missiles ----------------------------------------------------------------------------------

-- A glowing orb (the light missiles), or a rock (Earth's boulder).
local function makeMissile(element: Element, size: number, rock: boolean): Part
	local missile = Instance.new("Part")
	missile.Name = `{element.Name}Missile`
	missile.Shape = Enum.PartType.Ball
	missile.Size = Vector3.one * size
	missile.Material = if rock then Enum.Material.Slate else Enum.Material.Neon
	missile.Color = if rock then element.Color:Lerp(Color3.new(0, 0, 0), 0.35) else element.Color
	missile.Anchored = true
	missile.CanCollide = false
	missile.CanQuery = false
	missile.CanTouch = false
	if not rock then
		local light = Instance.new("PointLight")
		light.Color = element.Color
		light.Range = 6 + size * 3
		light.Brightness = 2
		light.Parent = missile
	end
	-- A streak behind it.
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, size * 0.35, 0)
	top.Parent = missile
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -size * 0.35, 0)
	bottom.Parent = missile
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.Lifetime = if rock then 0.2 else 0.3
	trail.LightEmission = if rock then 0 else 1
	trail.Color = if rock then ColorSequence.new(Color3.fromRGB(150, 130, 110)) else ColorSequence.new(Color3.new(1, 1, 1), element.Color)
	trail.Transparency = NumberSequence.new(if rock then 0.5 else 0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = missile
	return missile
end

-- Flies a missile from `origin` along `direction` (falling by `gravity`, if any); calls
-- `onImpact(model?, position)` when it hits something (or reaches max range, with nil).
-- Faith's light missile can hit other players (to heal them); the rest pass through players.
local function fly(player: Player, character: Model, element: Element, size: number, speed: number, origin: Vector3, direction: Vector3, hitsPlayers: boolean, onImpact: (Model?, Vector3) -> (), gravity: number?, rock: boolean?)
	local missile = makeMissile(element, size, rock == true)
	missile.CFrame = CFrame.lookAt(origin, origin + direction)
	missile.Parent = missiles

	local exclude: { Instance } = { missiles, character }
	if not hitsPlayers then
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(exclude, other.Character)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local position, velocity, traveled = origin, direction * speed, 0
	local fall = Vector3.new(0, -(gravity or 0), 0)
	local spin = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local nextVelocity = velocity + fall * dt
		local step = (velocity + nextVelocity) / 2 * dt
		-- A fat ray (spherecast), so a big missile hits what it visibly touches.
		local result = workspace:Spherecast(position, size / 2, step, params)
		if result then
			connection:Disconnect()
			missile:Destroy()
			onImpact(HealthService.findDamageable(result.Instance), result.Position)
			return
		end
		position += step
		velocity = nextVelocity
		traveled += step.Magnitude
		spin += dt * 8
		missile.CFrame = CFrame.lookAt(position, position + velocity) * (if rock then CFrame.Angles(spin, 0, 0) else CFrame.identity)
		if traveled >= STAFF.MaxRange then
			connection:Disconnect()
			missile:Destroy()
			onImpact(nil, position)
		end
	end)
end

-- Earth: a giant boulder thrown in an arc that crashes down, hitting, knocking back, and
-- stunning everything around where it lands.
local function boulder(player: Player, character: Model, element: Element, damage: number, origin: Vector3, direction: Vector3)
	local heavy = element.Heavy
	-- Thrown a little upward, so it arcs.
	local throw = (direction + Vector3.new(0, 0.25, 0)).Unit
	fly(player, character, element, heavy.Size or 4, heavy.Speed or 70, origin, throw, false, function(_, position)
		local radius = heavy.Radius or 8
		shockwaveRemote:FireAllClients(position, radius, `Staff{element.Name}`)
		for _, hit in MeleeHitbox.strikeAt(player, character, position, radius, damage, `Staff{element.Name}`) do
			applyEffects(player, hit.model, heavy, position, element)
		end
	end, heavy.Gravity, true)
end

-- Where a spell leaves the staff (chest height, a little in front) and which way it flies,
-- toward `aim`; nil if the aim is right on top of the caster.
local function launchPoint(root: BasePart, aim: Vector3): (Vector3?, Vector3?)
	local start = root.Position + Vector3.new(0, CAST_HEIGHT, 0)
	local toAim = aim - start
	if toAim.Magnitude < 1 then
		return nil, nil
	end
	local direction = toAim.Unit
	return start + direction * CAST_FORWARD, direction
end

-- Requests -----------------------------------------------------------------------------------

local function onElement(player: Player, name: unknown)
	local element = elementNamed(name)
	if not element or not SkillMath.staffUnlocked(player, element.Name) then
		return -- unknown, or not unlocked yet
	end
	player:SetAttribute("StaffElement", element.Name)
end

local function onCast(player: Player, aim: unknown)
	local point = validAim(aim)
	local character, root = staffInHand(player)
	if not point or not character or not root or charging[player] or player:GetAttribute("Blocking") == true then
		return
	end
	local now = os.clock()
	if now - (lastCast[player] or 0) < STAFF.CastCooldown - TIMING_SLACK then
		return
	end
	local element = currentElement(player)
	if not element then
		return -- the Mage class / an element isn't unlocked yet (checked before spending mana)
	end
	if not ManaService.spend(player, SkillMath.staminaCost(player, STAFF.ToolName, STAFF.CastMana, "Light")) then
		return
	end
	lastCast[player] = now
	task.delay(STAFF.CastDelay, function()
		local _, currentRoot = staffInHand(player)
		if not currentRoot then
			return
		end
		local origin, direction = launchPoint(currentRoot, point)
		if not origin or not direction then
			return
		end
		fly(player, character, element, element.Light.Size, element.Light.Speed, origin, direction, element.Light.Heal ~= nil, function(model, position)
			lightImpact(player, element, model, position, direction)
		end)
	end)
end

local function release(player: Player, aim: Vector3?)
	local state = charging[player]
	charging[player] = nil
	player:SetAttribute("HeavyAttacking", false)
	local character, root = staffInHand(player)
	if not state or not character or not root then
		return
	end
	local now = os.clock()
	lastBlast[player] = now
	local chargeSpeed = 1 + SkillMath.weapon(player, STAFF.ToolName, "ChargeSpeed")
	local power = math.clamp((now - state.started) * chargeSpeed / STAFF.FullChargeTime, 0, 1)
	local element = state.element
	local heavy = element.Heavy
	local damage = SkillMath.spellDamage(player, element.Name, heavy.MinDamage + (heavy.MaxDamage - heavy.MinDamage) * power, "Heavy")
	-- Released by the time limit (no aim sent): straight ahead.
	local point = aim or (root.Position + root.CFrame.LookVector * 40 + Vector3.new(0, CAST_HEIGHT, 0))
	task.delay(STAFF.BlastDelay, function()
		local _, currentRoot = staffInHand(player)
		if not currentRoot then
			return
		end
		if heavy.Kind == "HealBurst" then
			healingBurst(player, currentRoot, element, power)
			return
		elseif heavy.Kind == "Thunder" then
			thunder(player, character, currentRoot, element, damage, point)
			return
		end
		local origin, direction = launchPoint(currentRoot, point)
		if not origin or not direction then
			return
		end
		if heavy.Kind == "FireWave" then
			fireWave(player, character, currentRoot, element, damage, direction)
		elseif heavy.Kind == "WaterBlast" then
			waterBlast(player, character, currentRoot, element, damage, direction)
		elseif heavy.Kind == "Boulder" then
			boulder(player, character, element, damage, origin, direction)
		end
	end)
end

local function onCharge(player: Player)
	local character = staffInHand(player)
	if not character or charging[player] or player:GetAttribute("Blocking") == true then
		return
	end
	local now = os.clock()
	if now - (lastBlast[player] or 0) < STAFF.Recovery - TIMING_SLACK then
		return
	end
	local element = currentElement(player)
	if not element then
		return -- the Mage class / an element isn't unlocked yet (checked before spending mana)
	end
	if not ManaService.spend(player, SkillMath.staminaCost(player, STAFF.ToolName, STAFF.ChargeMana, "Heavy")) then
		return
	end
	local state = { started = now, element = element }
	charging[player] = state
	player:SetAttribute("HeavyAttacking", true)
	task.delay(STAFF.MaxHold, function()
		if charging[player] == state then
			release(player, nil)
		end
	end)
end

local function onRelease(player: Player, aim: unknown)
	if charging[player] then
		release(player, validAim(aim))
	end
end

function StaffService.start()
	missiles.Parent = workspace
	local template = createStaff()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("StaffElement", STAFF.Elements[1].Name)
		player.CharacterAdded:Connect(function()
			charging[player] = nil
			giveStaff(player, template)
		end)
		if player.Character then
			giveStaff(player, template)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastCast[player] = nil
		lastBlast[player] = nil
		charging[player] = nil
	end)
	RemoteGuard.connect(elementRemote, onElement)
	RemoteGuard.connect(castRemote, onCast)
	RemoteGuard.connect(chargeRemote, onCharge)
	RemoteGuard.connect(releaseRemote, onRelease)
end

return StaffService
