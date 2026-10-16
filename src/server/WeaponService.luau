--!strict
-- Gives players their click-combo weapons (sword, Emberfang, mace, spear, rapier, axe, dual blade, scythe, hammer) and resolves their hits on the server.
-- The client only reports "I swung" (MeleeSwing); the server finds which combo weapon is in
-- hand, works out which step of its combo this is (from its own timing, so clients can't
-- skip to the finisher), checks the cooldown, builds the hitbox, and deals that step's
-- damage, plus its knockback and stun if it has any. A step with a Radius sweeps an arc around
-- the player instead of the box ahead; one with Shockwave also shakes the ground in front.
-- Weapons with a heavy attack can also be held (HeavyAttack remote: true on hold, false on
-- release). Spin: the server runs the spin, hitting all around every tick until release,
-- the time limit, a weapon switch, or death. Quake: the server times the charge itself and
-- on release (or after MaxHold) smashes the ground, hitting and pushing back everything
-- in a radius that grows with the charge. Thrust: charged the same way, but on release
-- the player lunges forward and everything along the line (from where the lunge began) is hit.
-- Flurry: charged the same way; on release, a run of rapid stabs (more for a longer charge)
-- each hits along a narrow line ahead, the last knocking back. Rush: after ChargeTime of
-- holding, the server hits all around every tick (the client steers the rush) until release,
-- the time limit, running out of stamina, a weapon switch, or death; letting go before then
-- calls it off. Reap: one press runs the whole move (letting go doesn't stop it): the hook
-- lands ahead and drags what it caught in close, then the cut hits all around and knocks
-- back. The "HeavyAttacking" player attribute
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
type FlurryHeavy = CombatConfig.FlurryHeavy
type RushHeavy = CombatConfig.RushHeavy
type ReapHeavy = CombatConfig.ReapHeavy

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
-- Until when each player's flurry is still stabbing (no combo swings until then).
local flurryUntil: { [Player]: number } = {}

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
local function addTrail(part: BasePart, fromZ: number, toZ: number, lifetime: number, color: Color3?)
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
	if color then
		trail.Color = ColorSequence.new(color)
	end
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

-- Placeholder Emberfang (until its model is in assets/weapons): a dark blade edged in ember,
-- black grip and crossguard.
local function createEmberfang(): Tool
	local config = CombatConfig.Emberfang
	local tool, grip = newTool(
		config,
		CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.3, 0.3, 1.2),
		Color3.fromRGB(15, 15, 18),
		Enum.Material.Fabric
	)
	local ember = config.TrailColor or Color3.fromRGB(255, 120, 40)
	addPart(grip, "Guard", Vector3.new(1.6, 0.32, 0.3), CFrame.new(0, 0, 0.7), Color3.fromRGB(20, 20, 24), Enum.Material.Metal)
	local blade = addPart(grip, "Blade", Vector3.new(0.12, 0.5, 4.2), CFrame.new(0, 0, 2.9), Color3.fromRGB(125, 130, 140), Enum.Material.Metal)
	local edge = addPart(grip, "Edge", Vector3.new(0.14, 0.08, 4), CFrame.new(0, 0.26, 2.9), ember, Enum.Material.Neon)
	edge.Transparency = 0.1
	addTrail(blade, -1.6, 2.1, 0.15, ember)
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

-- Placeholder rapier: a long, slender blade, a bell guard over a red grip.
local function createRapier(): Tool
	local tool, grip = newTool(
		CombatConfig.Rapier,
		CFrame.new(0, 0, -0.25) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.2, 0.2, 0.9),
		Color3.fromRGB(150, 35, 35),
		Enum.Material.Fabric
	)
	local steel = Color3.fromRGB(215, 220, 230)
	addPart(grip, "Pommel", Vector3.one * 0.28, CFrame.new(0, 0, -0.5), Color3.fromRGB(60, 60, 65), Enum.Material.Metal, Enum.PartType.Ball)
	addPart(grip, "Bell", Vector3.new(0.25, 0.9, 0.9), CFrame.new(0, 0, 0.55) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(60, 60, 65), Enum.Material.Metal, Enum.PartType.Cylinder)
	local blade = addPart(grip, "Blade", Vector3.new(0.08, 0.12, 4.2), CFrame.new(0, 0, 2.75), steel, Enum.Material.Metal)
	addTrail(blade, 0.6, 2.1, 0.1, CombatConfig.Rapier.TrailColor)
	addSwingSound(grip, "RapierSwing")
	return tool
end

-- Placeholder dagger (until its model is in assets/weapons): a short steel blade over a
-- small guard and a wrapped wooden grip.
local function createDagger(): Tool
	local tool, grip = newTool(
		CombatConfig.Dagger,
		CFrame.new(0, 0, -0.2) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.22, 0.22, 0.7),
		Color3.fromRGB(70, 40, 25),
		Enum.Material.Wood
	)
	addPart(grip, "Guard", Vector3.new(0.7, 0.18, 0.16), CFrame.new(0, 0, 0.42), Color3.fromRGB(150, 120, 50), Enum.Material.Metal)
	local blade = addPart(grip, "Blade", Vector3.new(0.08, 0.3, 1.4), CFrame.new(0, 0, 1.2), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
	addTrail(blade, -0.5, 0.7, 0.1, CombatConfig.Dagger.TrailColor)
	addSwingSound(grip, "DaggerSwing")
	return tool
end

-- Placeholder dual blades: two short blades with dark grips, one on each grip part (the
-- off-hand one is welded to the other hand when equipped; see HandGrip.OFFHAND_NAME). At rest
-- (in the backpack's icon) the off-hand blade crosses the main one.
local function createDualBlade(): Tool
	local config = CombatConfig.DualBlade
	local tool, grip = newTool(
		config,
		CFrame.new(0, 0, -0.25) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.24, 0.24, 0.8),
		Color3.fromRGB(25, 20, 22),
		Enum.Material.Fabric
	)
	local offhand = grip:Clone()
	offhand.Name = HandGrip.OFFHAND_NAME
	offhand.CFrame = grip.CFrame * CFrame.new(0, 0, 1.3) * CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(0, 0, -1.3)
	offhand.Parent = tool
	local steel = Color3.fromRGB(150, 150, 165)
	for _, holder in { grip, offhand } do
		addPart(holder, "Guard", Vector3.new(0.9, 0.22, 0.18), CFrame.new(0, 0, 0.5), Color3.fromRGB(30, 28, 34), Enum.Material.Metal)
		local blade = addPart(holder, "Blade", Vector3.new(0.1, 0.4, 2.4), CFrame.new(0, 0, 1.8), steel, Enum.Material.Metal)
		addTrail(blade, -1, 1.2, 0.12, config.TrailColor)
	end
	addSwingSound(grip, "DualBladeSwing")
	return tool
end

-- Placeholder scythe: a long dark shaft (held low on its grip wrap) with a steel blade curving
-- out from the top on the grip's +Y side, so it leads the reaps.
local function createScythe(): Tool
	local config = CombatConfig.Scythe
	local tool, grip = newTool(
		config,
		CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.26, 0.26, 1.4),
		Color3.fromRGB(20, 14, 14),
		Enum.Material.Fabric
	)
	local dark = Color3.fromRGB(30, 28, 34)
	local steel = Color3.fromRGB(170, 175, 190)
	-- The hand is 2.4 studs up an 8-stud shaft.
	addPart(grip, "Shaft", Vector3.new(0.22, 0.22, 8), CFrame.new(0, 0, 1.6), Color3.fromRGB(60, 35, 20), Enum.Material.Wood)
	addPart(grip, "ButtCap", Vector3.one * 0.32, CFrame.new(0, 0, -2.4), dark, Enum.Material.Metal, Enum.PartType.Ball)
	addPart(grip, "Collar", Vector3.new(0.34, 0.34, 0.5), CFrame.new(0, 0, 5.3), dark, Enum.Material.Metal)
	-- The blade: three tilted segments sweeping out and curving down toward the tip.
	addPart(grip, "Blade1", Vector3.new(0.08, 1.4, 0.45), CFrame.new(0, 0.7, 5.45) * CFrame.Angles(math.rad(-8), 0, 0), steel, Enum.Material.Metal)
	addPart(grip, "Blade2", Vector3.new(0.07, 1.3, 0.38), CFrame.new(0, 1.95, 5.3) * CFrame.Angles(math.rad(12), 0, 0), steel, Enum.Material.Metal)
	addPart(grip, "Blade3", Vector3.new(0.06, 1.1, 0.28), CFrame.new(0, 3.0, 4.95) * CFrame.Angles(math.rad(30), 0, 0), steel, Enum.Material.Metal)
	addTrail(grip, 3, 5.6, 0.15, config.TrailColor)
	addSwingSound(grip, "ScytheSwing")
	return tool
end

-- Placeholder hammer: a long wooden haft with a dark grip, a big steel head on top (blunt
-- faces front and back along the grip's Y).
local function createHammer(): Tool
	local config = CombatConfig.Hammer
	local tool, grip = newTool(
		config,
		CFrame.new(0, 0, -0.4) * CFrame.Angles(math.pi / 2, 0, 0),
		Vector3.new(0.34, 0.34, 1.8),
		Color3.fromRGB(20, 14, 14),
		Enum.Material.Fabric
	)
	local steel = Color3.fromRGB(85, 82, 95)
	-- The hand is 1.7 studs up a 7.2-stud haft.
	addPart(grip, "Haft", Vector3.new(0.3, 0.3, 5.2), CFrame.new(0, 0, 2.6), Color3.fromRGB(65, 35, 15), Enum.Material.Wood)
	addPart(grip, "Pommel", Vector3.one * 0.45, CFrame.new(0, 0, -1.5), steel, Enum.Material.Metal, Enum.PartType.Ball)
	local head = addPart(grip, "Head", Vector3.new(1.4, 2.8, 1.5), CFrame.new(0, 0, 4.7), steel, Enum.Material.Metal)
	addPart(grip, "Band1", Vector3.new(1.5, 0.3, 1.6), CFrame.new(0, 0.9, 4.7), Color3.fromRGB(20, 18, 22), Enum.Material.Metal)
	addPart(grip, "Band2", Vector3.new(1.5, 0.3, 1.6), CFrame.new(0, -0.9, 4.7), Color3.fromRGB(20, 18, 22), Enum.Material.Metal)
	addTrail(head, -0.6, 0.6, 0.2, config.TrailColor)
	addSwingSound(grip, "HammerSwing")
	return tool
end

local CREATORS: { [string]: () -> Tool } = {
	[CombatConfig.Sword.ToolName] = createSword,
	[CombatConfig.Emberfang.ToolName] = createEmberfang,
	[CombatConfig.Mace.ToolName] = createMace,
	[CombatConfig.Spear.ToolName] = createSpear,
	[CombatConfig.Rapier.ToolName] = createRapier,
	[CombatConfig.Dagger.ToolName] = createDagger,
	[CombatConfig.Axe.ToolName] = createAxe,
	[CombatConfig.DualBlade.ToolName] = createDualBlade,
	[CombatConfig.Scythe.ToolName] = createScythe,
	[CombatConfig.Hammer.ToolName] = createHammer,
}

local COMBO_WEAPONS: { ComboWeapon } = { CombatConfig.Sword, CombatConfig.Emberfang, CombatConfig.Mace, CombatConfig.Spear, CombatConfig.Rapier, CombatConfig.Dagger, CombatConfig.Axe, CombatConfig.DualBlade, CombatConfig.Scythe, CombatConfig.Hammer }

local function configFor(tool: Tool): ComboWeapon?
	for _, config in COMBO_WEAPONS do
		if config.ToolName == tool.Name then
			return config
		end
	end
	return nil
end

-- Where a ground smash lands: the ground under the player's feet, or `ahead` studs in front.
local function groundBelow(character: Model, root: BasePart, ahead: number?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local from = root.Position + root.CFrame.LookVector * Vector3.new(1, 0, 1) * (ahead or 0)
	local result = workspace:Raycast(from, Vector3.new(0, -12, 0), params)
	return if result then result.Position else from - Vector3.new(0, 3, 0)
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
	if (flurryUntil[player] or 0) > os.clock() - TIMING_SLACK then
		return -- still stabbing
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
		local damage = SkillMath.damage(player, config.ToolName, move.Damage, "Light")
		if move.Shockwave and move.Radius then
			-- The head lands about halfway out along the reach.
			shockwaveRemote:FireAllClients(groundBelow(character, root, move.Radius / 2), move.Radius / 2, config.ToolName)
		end
		local hits = if move.Radius
			then MeleeHitbox.strikeArc(player, character, root, move.Radius, move.Arc or 360, damage, config.ToolName)
			else MeleeHitbox.strike(player, character, root, Vector3.new(config.Width, config.Height, config.Range), damage, config.ToolName)
		for _, hit in hits do
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

local function smash(player: Player, character: Model, tool: Tool, config: ComboWeapon, quake: QuakeHeavy, power: number)
	local function lerp(min: number, max: number): number
		return min + (max - min) * power
	end
	local radius = lerp(quake.MinRadius, quake.MaxRadius) * (1 + SkillMath.weapon(player, config.ToolName, "QuakeRadius"))
	local damage = SkillMath.damage(player, config.ToolName, lerp(quake.MinDamage, quake.MaxDamage), "Heavy")
	local knockback = lerp(quake.Knockback, quake.MaxKnockback or quake.Knockback)
	local knockbackTime = quake.KnockbackTime or KNOCKBACK_TIME

	task.delay(quake.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) or character:FindFirstChildOfClass("Tool") ~= tool then
			return
		end
		shockwaveRemote:FireAllClients(groundBelow(character, root), radius, config.ToolName)
		for _, hit in MeleeHitbox.strikeAround(player, character, root, radius, damage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, knockback, knockbackTime)
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

-- The flurry's stabs, one every Interval after HitDelay, each along a narrow line ahead
-- (from wherever the player is by then: they creep forward as they stab).
local function flurry(player: Player, character: Model, tool: Tool, config: ComboWeapon, heavy: FlurryHeavy, power: number)
	local hits = CombatConfig.flurryHits(heavy, power, SkillMath.weapon(player, config.ToolName, "FlurryHits"))
	local damage = SkillMath.damage(player, config.ToolName, heavy.Damage, "Heavy")
	local size = Vector3.new(heavy.Width, heavy.Height, heavy.Range)
	local finish = os.clock() + heavy.HitDelay + (hits - 1) * heavy.Interval
	flurryUntil[player] = finish
	lastHeavyEnd[player] = finish -- the recovery counts from the last stab
	task.spawn(function()
		task.wait(heavy.HitDelay)
		for stab = 1, hits do
			local root = character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) or character:FindFirstChildOfClass("Tool") ~= tool then
				break
			end
			for _, hit in MeleeHitbox.strike(player, character, root, size, damage, config.ToolName) do
				if stab == hits and HealthService.isAlive(hit.model) then
					EnemyEffects.knockBack(hit.model, root.Position, heavy.FinalKnockback, KNOCKBACK_TIME)
				end
			end
			if stab < hits then
				task.wait(heavy.Interval)
			end
		end
		if flurryUntil[player] == finish then
			flurryUntil[player] = nil
		end
	end)
end

-- Ends a charge (quake, thrust or flurry) with its attack; the power comes from the server's own
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
	local charged = releasing and releasing.Kind ~= "Spin" and releasing.Kind ~= "Rush" and releasing.Kind ~= "Reap"
	stopHeavy(player, if charged then (releasing :: ThrustHeavy).HitDelay + UNFLIP_AFTER_HIT else nil)
	local tool = character and character:FindFirstChildOfClass("Tool")
	local config = tool and configFor(tool)
	local heavy = config and config.Heavy
	if not character or not tool or not config or not heavy or heavy.Kind == "Spin" or heavy.Kind == "Rush" or heavy.Kind == "Reap" or not HealthService.isAlive(character) then
		return
	end
	if heavy.Kind == "Quake" then
		local quake = heavy :: QuakeHeavy
		smash(player, character, tool, config, quake, math.clamp((os.clock() - token.started) / quake.FullChargeTime, 0, 1))
	elseif heavy.Kind == "Flurry" then
		local stabs = heavy :: FlurryHeavy
		flurry(player, character, tool, config, stabs, math.clamp((os.clock() - token.started) / stabs.FullChargeTime, 0, 1))
	else
		local lunge = heavy :: ThrustHeavy
		thrust(player, character, tool, config, lunge, math.clamp((os.clock() - token.started) / lunge.FullChargeTime, 0, 1))
	end
end

-- The reap's hook, then its cut (see ReapHeavy); ends the heavy once the move is over. Each
-- step is skipped if the player died, switched weapons, or the heavy was ended meanwhile.
local function reap(player: Player, character: Model, tool: Tool, config: ComboWeapon, heavy: ReapHeavy, token: HeavyState)
	local reach = heavy.Reach * (1 + SkillMath.weapon(player, config.ToolName, "HookReach"))
	local hookDamage = SkillMath.damage(player, config.ToolName, heavy.HookDamage, "Heavy")
	local cutDamage = SkillMath.damage(player, config.ToolName, heavy.CutDamage, "Heavy")
	local function stillGoing(): BasePart?
		local root = character:FindFirstChild("HumanoidRootPart")
		if heavyTokens[player] ~= token or not HealthService.isAlive(character) or character:FindFirstChildOfClass("Tool") ~= tool then
			return nil
		end
		return if root and root:IsA("BasePart") then root else nil
	end

	task.wait(heavy.HookDelay)
	local root = stillGoing()
	if root then
		-- Hooked enemies are held until the cut lands, and dragged in front of us meanwhile.
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local landing = root.Position + (if look.Magnitude > 0.01 then look.Unit else Vector3.zero) * heavy.PullTo
		local hold = heavy.CutDelay - heavy.HookDelay + 0.1
		local size = Vector3.new(heavy.Width, heavy.Height, reach)
		for _, hit in MeleeHitbox.strike(player, character, root, size, hookDamage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				EnemyEffects.stun(hit.model, hold, true)
				EnemyEffects.pull(hit.model, landing, heavy.PullTime)
			end
		end
	end

	task.wait(heavy.CutDelay - heavy.HookDelay)
	root = stillGoing()
	if root then
		for _, hit in MeleeHitbox.strikeArc(player, character, root, heavy.CutRadius, heavy.CutArc, cutDamage, config.ToolName) do
			if HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, heavy.Knockback, KNOCKBACK_TIME)
			end
		end
	end

	task.wait(heavy.Duration - heavy.CutDelay)
	if heavyTokens[player] == token then
		stopHeavy(player)
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
	-- A charge pays up front; a spin pays per hit, starting with the first; a rush pays per
	-- hit once it starts (gathering is free, but you need enough for the first hit).
	local cost = SkillMath.staminaCost(player, config.ToolName, heavy.Stamina, "Heavy")
	if heavy.Kind == "Rush" then
		if not StaminaService.has(player, cost) then
			return -- too tired
		end
	elseif not StaminaService.spend(player, cost) then
		return -- too tired
	end

	local token: HeavyState = { started = os.clock() }
	heavyTokens[player] = token
	comboStates[player] = nil
	player:SetAttribute("HeavyAttacking", true)
	if heavy.FlipGrip then
		setGripFlipped(player, tool, config, true)
	end

	if heavy.Kind == "Reap" then
		task.spawn(reap, player, character, tool, config, heavy :: ReapHeavy, token)
		return
	end

	if heavy.Kind == "Rush" then
		local rush = heavy :: RushHeavy
		local maxDuration = rush.MaxDuration + SkillMath.weapon(player, config.ToolName, "RushDuration")
		local tickDamage = SkillMath.damage(player, config.ToolName, rush.Damage, "Heavy")
		task.spawn(function()
			task.wait(rush.ChargeTime) -- gathering; letting go before now calls it off
			local started = os.clock()
			while heavyTokens[player] == token do
				local root = character:FindFirstChild("HumanoidRootPart")
				local stillHolding = character:FindFirstChildOfClass("Tool") == tool
				if os.clock() - started > maxDuration or not HealthService.isAlive(character) or not stillHolding then
					break
				end
				if not StaminaService.spend(player, cost) then
					break -- out of stamina
				end
				if root and root:IsA("BasePart") then
					MeleeHitbox.strikeAround(player, character, root, rush.Radius, tickDamage, config.ToolName)
				end
				task.wait(rush.TickInterval)
			end
			if heavyTokens[player] == token then
				stopHeavy(player)
			end
		end)
		return
	end

	if heavy.Kind ~= "Spin" then
		-- Charging (quake, thrust or flurry): attacks on release, or by itself after MaxHold.
		local maxHold = if heavy.Kind == "Quake" then (heavy :: QuakeHeavy).MaxHold
			elseif heavy.Kind == "Flurry" then (heavy :: FlurryHeavy).MaxHold
			else (heavy :: ThrustHeavy).MaxHold
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
		if heavy and heavy.Kind == "Reap" then
			return -- the reap runs to the end once started
		elseif heavy and heavy.Kind ~= "Spin" and heavy.Kind ~= "Rush" then
			releaseCharge(player)
		else
			stopHeavy(player)
		end
	end
end

local function giveWeapon(player: Player, config: ComboWeapon, template: Tool)
	local weapon = template:Clone()
	local weldName = `{config.ToolName}Grip`
	local offhandWeldName = `{config.ToolName}OffhandGrip`
	weapon.Equipped:Connect(function()
		local character = weapon.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(weapon, character, config.Hand :: HandGrip.Hand, weldName)
			if config.DualWield then
				HandGrip.attach(weapon, character, HandGrip.opposite(config.Hand :: HandGrip.Hand), offhandWeldName, HandGrip.OFFHAND_NAME)
			end
		end
	end)
	weapon.Unequipped:Connect(function()
		HandGrip.detach(weapon, weldName)
		HandGrip.detach(weapon, offhandWeldName, HandGrip.OFFHAND_NAME)
		comboStates[player] = nil
		stopHeavy(player)
	end)
	InventoryService.give(player, weapon) -- the hotbar, or stored in the backpack
end

-- Gives a combo weapon to every player on each spawn (the Backpack resets on respawn).
local function distribute(config: ComboWeapon, template: Tool)
	InventoryService.register(template)
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
		flurryUntil[player] = nil
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
