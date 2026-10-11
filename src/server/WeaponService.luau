--!strict
-- Gives players their click-combo weapons (sword, mace, spear) and resolves their hits on the server.
-- The client only reports "I swung" (MeleeSwing); the server finds which combo weapon is in
-- hand, works out which step of its combo this is (from its own timing, so clients can't
-- skip to the finisher), checks the cooldown, builds the hitbox, and deals that step's
-- damage, plus its knockback and stun if it has any.
-- Weapons with a heavy attack can also be held (HeavyAttack remote: true on hold, false on
-- release). Spin: the server runs the spin, hitting all around every tick until release,
-- the time limit, a weapon switch, or death. Quake: the server times the charge itself and
-- on release (or after MaxHold) smashes the ground, hitting and pushing back everything
-- in a radius that grows with the charge. Thrust: charged the same way, but on release
-- the player lunges forward and everything along the line (from where the lunge began) is hit. The "HeavyAttacking" player attribute
-- tells the client while a heavy is running (so it reacts if the server ends it first).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local EnemyEffects = require(script.Parent.EnemyEffects)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local MeleeHitbox = require(script.Parent.MeleeHitbox)
local WeaponModels = require(script.Parent.WeaponModels)
local StaminaService = require(script.Parent.StaminaService)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)

type ComboWeapon = CombatConfig.ComboWeapon
type QuakeHeavy = CombatConfig.QuakeHeavy
type ThrustHeavy = CombatConfig.ThrustHeavy

-- Network delay makes clicks arrive slightly early or late; allow this much either way.
local TIMING_SLACK = 0.1
local KNOCKBACK_TIME = 0.2
local UNFLIP_AFTER_HIT = 0.45 -- seconds after a release attack lands before a flipped weapon turns back

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local swingRemote = remotes:WaitForChild("MeleeSwing") :: RemoteEvent
local heavyRemote = remotes:WaitForChild("HeavyAttack") :: RemoteEvent
local shockwaveRemote = remotes:WaitForChild("GroundShockwave") :: RemoteEvent

local WeaponService = {}

type ComboState = { step: number, time: number }
local comboStates: { [Player]: ComboState } = {}

-- The running heavy per player (a unique table, so a stale spin loop knows it's been
-- replaced), and when each player's last heavy ended (for the recovery time).
type HeavyState = { started: number }
local heavyTokens: { [Player]: HeavyState } = {}
local lastHeavyEnd: { [Player]: number } = {}

local function addPart(grip: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = grip.CFrame * offset
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = grip.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function newTool(config: ComboWeapon, grip: CFrame, gripSize: Vector3, gripColor: Color3, gripMaterial: Enum.Material): (Tool, BasePart)
	local tool = Instance.new("Tool")
	tool.Name = config.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = false -- held via HandGrip so the default tool arm pose doesn't fight the animations
	tool.Grip = grip

	local part = Instance.new("Part")
	part.Name = HandGrip.GRIP_NAME
	part.Size = gripSize
	part.Color = gripColor
	part.Material = gripMaterial
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = tool
	return tool, part
end

-- Swing trail between two points on `part` (local Z offsets); the client turns it on mid-swing.
local function addTrail(part: BasePart, fromZ: number, toZ: number, lifetime: number)
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0, fromZ)
	base.Parent = part
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = Vector3.new(0, 0, toZ)
	tip.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = lifetime
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Enabled = false
	trail.Parent = part
end

-- The swing whoosh the client plays (found by the name "SlashSound"); see Sounds.
local function addSwingSound(grip: BasePart, soundName: string)
	local sound = Sounds.create(soundName, grip)
	if sound then
		sound.Name = "SlashSound"
	end
end

-- Placeholder sword built from parts. The grip's +Z points up out of the fist (the blade).
local function createSword(): Tool
	local tool, grip = newTool(
		CombatConfig.Sword,
		CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.3, 0.3, 1.2),
		Color3.fromRGB(70, 45, 30),
		Enum.Material.Wood
	)
	addPart(grip, "Guard", Vector3.new(1.4, 0.3, 0.25), CFrame.new(0, 0, 0.7), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	local blade = addPart(grip, "Blade", Vector3.new(0.15, 0.5, 4), CFrame.new(0, 0, 2.8), Color3.fromRGB(210, 215, 225), Enum.Material.Metal)
	addTrail(blade, -1.6, 2, 0.15)
	addSwingSound(grip, "SwordSwing")
	return tool
end

-- Placeholder mace: wooden haft with a leather grip, a spiked steel ball head on top.
local function createMace(): Tool
	local tool, grip = newTool(
		CombatConfig.Mace,
		CFrame.new(0, 0, -0.2) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.32, 0.32, 1.1),
		Color3.fromRGB(55, 35, 25),
		Enum.Material.Fabric
	)
	local steel = Color3.fromRGB(150, 155, 165)
	addPart(grip, "Haft", Vector3.new(0.26, 0.26, 2.2), CFrame.new(0, 0, 1.6), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
	addPart(grip, "Pommel", Vector3.one * 0.4, CFrame.new(0, 0, -0.6), steel, Enum.Material.Metal, Enum.PartType.Ball)
	addPart(grip, "Collar", Vector3.new(0.45, 0.45, 0.25), CFrame.new(0, 0, 2.6), Color3.fromRGB(190, 150, 60), Enum.Material.Metal)
	local head = addPart(grip, "Head", Vector3.one * 1.2, CFrame.new(0, 0, 3.2), steel, Enum.Material.Metal, Enum.PartType.Ball)

	-- Six spikes sticking out of the head (up, down, and four around).
	local spikeRotations = {
		CFrame.Angles(0, 0, 0),
		CFrame.Angles(math.pi, 0, 0),
		CFrame.Angles(math.pi / 2, 0, 0),
		CFrame.Angles(-math.pi / 2, 0, 0),
		CFrame.Angles(0, math.pi / 2, 0),
		CFrame.Angles(0, -math.pi / 2, 0),
	}
	for index, rotation in spikeRotations do
		addPart(grip, `Spike{index}`, Vector3.new(0.22, 0.22, 0.5), CFrame.new(0, 0, 3.2) * rotation * CFrame.new(0, 0, 0.75), steel, Enum.Material.Metal)
	end

	addTrail(head, -0.5, 0.5, 0.18)
	addSwingSound(grip, "MaceSwing")
	return tool
end

-- Placeholder spear: a long wooden shaft (held a third of the way up) with a steel head.
local function createSpear(): Tool
	local tool, shaft = newTool(
		CombatConfig.Spear,
		CFrame.new(0, 0, -1.2) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.22, 0.22, 7),
		Color3.fromRGB(110, 80, 50),
		Enum.Material.Wood
	)
	local steel = Color3.fromRGB(200, 205, 215)
	addPart(shaft, "ButtCap", Vector3.one * 0.3, CFrame.new(0, 0, -3.5), steel, Enum.Material.Metal, Enum.PartType.Ball)
	addPart(shaft, "Collar", Vector3.new(0.32, 0.32, 0.3), CFrame.new(0, 0, 3.45), Color3.fromRGB(190, 150, 60), Enum.Material.Metal)
	local head = addPart(shaft, "Head", Vector3.new(0.12, 0.45, 1.1), CFrame.new(0, 0, 4.1), steel, Enum.Material.Metal)
	addPart(shaft, "Tip", Vector3.new(0.1, 0.22, 0.45), CFrame.new(0, 0, 4.85), steel, Enum.Material.Metal)

	addTrail(head, -0.5, 0.6, 0.12)
	addSwingSound(shaft, "SpearSwing")
	return tool
end

-- Placeholder one-handed axe: a wooden haft with a steel head whose edge faces the grip's
-- +Y (the side the hand leads with, so the edge leads every chop).
local function createAxe(): Tool
	local tool, grip = newTool(
		CombatConfig.Axe,
		CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.28, 0.28, 1),
		Color3.fromRGB(70, 45, 30),
		Enum.Material.Wood
	)
	local steel = Color3.fromRGB(170, 175, 185)
	local haft = addPart(grip, "Haft", Vector3.new(0.24, 0.24, 2.2), CFrame.new(0, 0, 1.4), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	addPart(grip, "Head", Vector3.new(0.14, 0.9, 0.8), CFrame.new(0, 0.5, 2.15), steel, Enum.Material.Metal)
	addPart(grip, "Edge", Vector3.new(0.08, 0.12, 1.1), CFrame.new(0, 0.98, 2.15), Color3.fromRGB(220, 225, 235), Enum.Material.Metal)
	addPart(grip, "Poll", Vector3.new(0.3, 0.3, 0.45), CFrame.new(0, -0.2, 2.15), steel, Enum.Material.Metal)
	addTrail(haft, -0.4, 1.2, 0.15)
	addSwingSound(grip, "AxeSwing")
	return tool
end

local CREATORS: { [string]: () -> Tool } = {
	[CombatConfig.Sword.ToolName] = createSword,
	[CombatConfig.Mace.ToolName] = createMace,
	[CombatConfig.Spear.ToolName] = createSpear,
	[CombatConfig.Axe.ToolName] = createAxe,
}

local COMBO_WEAPONS: { ComboWeapon } = { CombatConfig.Sword, CombatConfig.Mace, CombatConfig.Spear, CombatConfig.Axe }

local function configFor(tool: Tool): ComboWeapon?
	for _, config in COMBO_WEAPONS do
		if config.ToolName == tool.Name then
			return config
		end
	end
	return nil
end

local function onSwing(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	local config = tool and configFor(tool)
	if not config or player:GetAttribute("Blocking") == true or heavyTokens[player] then
		return -- not holding a combo weapon, blocking, or mid-spin
	end
	local combo = config.Combo

	-- Same rule as the client: the next step if clicked soon enough after the last swing,
	-- otherwise back to the first.
	local now = os.clock()
	local step = 1
	local previous = comboStates[player]
	if previous then
		local since = now - previous.time
		local previousMove = combo[previous.step]
		if since < previousMove.Cooldown - TIMING_SLACK then
			return -- still mid-swing
		end
		if previous.step < #combo and since <= previousMove.Cooldown + config.ComboWindow + TIMING_SLACK then
			step = previous.step + 1
		end
	end
	if not StaminaService.spend(player, SkillMath.staminaCost(player, config.ToolName, config.Stamina, "Light")) then
		return -- too tired
	end
	comboStates[player] = { step = step, time = now }

	local move = combo[step]
	task.delay(move.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) then
			return
		end
		local size = Vector3.new(config.Width, config.Height, config.Range)
		local damage = SkillMath.damage(player, config.ToolName, move.Damage, "Light")
		for _, hit in MeleeHitbox.strike(player, character, root, size, damage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				if move.Knockback then
					EnemyEffects.knockBack(hit.model, root.Position, move.Knockback, KNOCKBACK_TIME)
				end
				if move.Stun then
					EnemyEffects.stun(hit.model, move.Stun)
				end
			end
		end
	end)
end

local releaseCharge: (player: Player) -> ()

-- Heavies with FlipGrip turn the weapon 180 degrees around its handle (by rotating the
-- replicated hand weld, so everyone sees it) and turn it back when they're over.
local FLIPPED_GRIP = CFrame.Angles(0, 0, math.pi)
local flipTokens: { [Player]: {} } = {}

local function setGripFlipped(player: Player, tool: Tool, config: ComboWeapon, flipped: boolean)
	local grip = tool:FindFirstChild(HandGrip.GRIP_NAME)
	local weld = grip and grip:FindFirstChild(`{config.ToolName}Grip`)
	if weld and weld:IsA("Weld") then
		weld.C1 = if flipped then FLIPPED_GRIP * tool.Grip else tool.Grip
	end
	flipTokens[player] = if flipped then {} else nil
end

-- Turns a flipped weapon back, now or `after` seconds from now (e.g. once a release attack
-- has finished), unless a new heavy has flipped it again by then.
local function unflipGrip(player: Player, after: number?)
	local token = flipTokens[player]
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local config = tool and configFor(tool)
	if not token or not tool or not config then
		flipTokens[player] = nil
		return
	end
	task.delay(after or 0, function()
		if flipTokens[player] == token and tool.Parent then
			setGripFlipped(player, tool, config, false)
		end
	end)
end

local function stopHeavy(player: Player, unflipAfter: number?)
	if heavyTokens[player] then
		heavyTokens[player] = nil
		lastHeavyEnd[player] = os.clock()
		player:SetAttribute("HeavyAttacking", false)
		unflipGrip(player, unflipAfter)
	end
end

-- Where a ground smash lands: the ground under the player's feet.
local function groundBelow(character: Model, root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	return if result then result.Position else root.Position - Vector3.new(0, 3, 0)
end

local function smash(player: Player, character: Model, tool: Tool, config: ComboWeapon, quake: QuakeHeavy, power: number)
	local function lerp(min: number, max: number): number
		return min + (max - min) * power
	end
	local radius = lerp(quake.MinRadius, quake.MaxRadius) * (1 + SkillMath.weapon(player, config.ToolName, "QuakeRadius"))
	local damage = SkillMath.damage(player, config.ToolName, lerp(quake.MinDamage, quake.MaxDamage), "Heavy")

	task.delay(quake.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) or character:FindFirstChildOfClass("Tool") ~= tool then
			return
		end
		shockwaveRemote:FireAllClients(groundBelow(character, root), radius, config.ToolName)
		for _, hit in MeleeHitbox.strikeAround(player, character, root, radius, damage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, quake.Knockback, KNOCKBACK_TIME)
			end
		end
	end)
end

local function thrust(player: Player, character: Model, tool: Tool, config: ComboWeapon, lunge: ThrustHeavy, power: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	-- The line starts where the lunge began (level), so the hit covers the whole path no
	-- matter how far the player has moved by the time it lands.
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		return
	end
	local origin = CFrame.lookAt(root.Position, root.Position + look)
	local distance = (lunge.MinDistance + (lunge.MaxDistance - lunge.MinDistance) * power) * (1 + SkillMath.weapon(player, config.ToolName, "LungeDistance"))
	local damage = SkillMath.damage(player, config.ToolName, lunge.MinDamage + (lunge.MaxDamage - lunge.MinDamage) * power, "Heavy")
	local size = Vector3.new(lunge.Width, lunge.Height, distance + lunge.Reach)

	task.delay(lunge.HitDelay, function()
		if not HealthService.isAlive(character) or character:FindFirstChildOfClass("Tool") ~= tool then
			return
		end
		for _, hit in MeleeHitbox.strikeFrom(player, character, root, origin, size, damage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, lunge.Knockback, KNOCKBACK_TIME)
				local bleed = lunge.Bleed
				if bleed then
					local bleedDamage = bleed.Damage + SkillMath.weapon(player, config.ToolName, "BleedDamage")
					EnemyEffects.bleed(hit.model, player, bleedDamage, bleed.Interval, bleed.Duration)
				end
			end
		end
	end)
end

-- Ends a charge (quake or thrust) with its attack; the power comes from the server's own
-- timing of the charge.
releaseCharge = function(player: Player)
	local token = heavyTokens[player]
	if not token then
		return
	end
	local character = player.Character
	local held = character and character:FindFirstChildOfClass("Tool")
	local heldConfig = held and configFor(held)
	local releasing = heldConfig and heldConfig.Heavy
	-- A flipped weapon stays flipped through the release attack's animation.
	stopHeavy(player, if releasing and releasing.Kind ~= "Spin" then (releasing :: ThrustHeavy).HitDelay + UNFLIP_AFTER_HIT else nil)
	local tool = character and character:FindFirstChildOfClass("Tool")
	local config = tool and configFor(tool)
	local heavy = config and config.Heavy
	if not character or not tool or not config or not heavy or heavy.Kind == "Spin" or not HealthService.isAlive(character) then
		return
	end
	if heavy.Kind == "Quake" then
		local quake = heavy :: QuakeHeavy
		smash(player, character, tool, config, quake, math.clamp((os.clock() - token.started) / quake.FullChargeTime, 0, 1))
	else
		local lunge = heavy :: ThrustHeavy
		thrust(player, character, tool, config, lunge, math.clamp((os.clock() - token.started) / lunge.FullChargeTime, 0, 1))
	end
end

local function startHeavy(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) or heavyTokens[player] then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local config = tool and configFor(tool)
	local heavy = config and config.Heavy
	if not tool or not config or not heavy or player:GetAttribute("Blocking") == true then
		return
	end
	if os.clock() - (lastHeavyEnd[player] or 0) < heavy.Recovery - TIMING_SLACK then
		return -- still recovering from the last heavy
	end
	-- A charge pays up front; a spin pays per hit, starting with the first.
	if not StaminaService.spend(player, SkillMath.staminaCost(player, config.ToolName, heavy.Stamina, "Heavy")) then
		return -- too tired
	end

	local token: HeavyState = { started = os.clock() }
	heavyTokens[player] = token
	comboStates[player] = nil
	player:SetAttribute("HeavyAttacking", true)
	if heavy.FlipGrip then
		setGripFlipped(player, tool, config, true)
	end

	if heavy.Kind ~= "Spin" then
		-- Charging (quake or thrust): attacks on release, or by itself after MaxHold.
		local maxHold = if heavy.Kind == "Quake" then (heavy :: QuakeHeavy).MaxHold else (heavy :: ThrustHeavy).MaxHold
		task.delay(maxHold, function()
			if heavyTokens[player] == token then
				releaseCharge(player)
			end
		end)
		return
	end

	local spin = heavy :: CombatConfig.SpinHeavy
	-- Skill bonuses for this spin (see SkillTrees).
	local maxDuration = spin.MaxDuration + SkillMath.weapon(player, config.ToolName, "SpinDuration")
	local tickDamage = SkillMath.damage(player, config.ToolName, spin.Damage, "Heavy")
	local tickCost = SkillMath.staminaCost(player, config.ToolName, spin.Stamina, "Heavy")
	task.spawn(function()
		local started = os.clock()
		local paid = true -- the first hit was paid for when the spin started
		task.wait(spin.WindUp)
		while heavyTokens[player] == token do
			local root = character:FindFirstChild("HumanoidRootPart")
			local stillHolding = character:FindFirstChildOfClass("Tool") == tool
			if os.clock() - started > maxDuration or not HealthService.isAlive(character) or not stillHolding then
				break
			end
			if not paid and not StaminaService.spend(player, tickCost) then
				break -- out of stamina
			end
			paid = false
			if root and root:IsA("BasePart") then
				MeleeHitbox.strikeAround(player, character, root, spin.Radius, tickDamage, config.ToolName)
			end
			task.wait(spin.TickInterval)
		end
		if heavyTokens[player] == token then
			stopHeavy(player)
		end
	end)
end

local function onHeavy(player: Player, holding: unknown)
	if typeof(holding) ~= "boolean" then
		return
	end
	if holding then
		startHeavy(player)
	elseif heavyTokens[player] then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local config = tool and configFor(tool)
		local heavy = config and config.Heavy
		if heavy and heavy.Kind ~= "Spin" then
			releaseCharge(player)
		else
			stopHeavy(player)
		end
	end
end

local function giveWeapon(player: Player, config: ComboWeapon, template: Tool)
	local weapon = template:Clone()
	local weldName = `{config.ToolName}Grip`
	weapon.Equipped:Connect(function()
		local character = weapon.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(weapon, character, config.Hand :: HandGrip.Hand, weldName)
		end
	end)
	weapon.Unequipped:Connect(function()
		HandGrip.detach(weapon, weldName)
		comboStates[player] = nil
		stopHeavy(player)
	end)
	InventoryService.give(player, weapon) -- the hotbar, or stored in the backpack
end

-- Gives a combo weapon to every player on each spawn (the Backpack resets on respawn).
local function distribute(config: ComboWeapon, template: Tool)
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			giveWeapon(player, config, template)
		end)
		if player.Character then
			giveWeapon(player, config, template)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- Starts resolving combo swings. Weapons are handed out with give(), in hotbar order.
function WeaponService.start()
	Players.PlayerRemoving:Connect(function(player)
		comboStates[player] = nil
		heavyTokens[player] = nil
		lastHeavyEnd[player] = nil
		flipTokens[player] = nil
	end)
	RemoteGuard.connect(swingRemote, onSwing)
	RemoteGuard.connect(heavyRemote, onHeavy)
end

-- Hands one combo weapon to every player (on each spawn). Call in the order the weapons
-- should appear in the hotbar.
function WeaponService.give(config: ComboWeapon)
	local create = CREATORS[config.ToolName]
	assert(create, `No model for combo weapon {config.ToolName}`)
	local template = create()
	WeaponModels.apply(template, config.ModelFit) -- a real model, if one's been added (assets/weapons)
	distribute(config, template)
end

return WeaponService
