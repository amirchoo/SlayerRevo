--!strict
-- Gives players their click-combo weapons (sword, mace, spear) and resolves their hits on the server.
-- The client only reports "I swung" (MeleeSwing); the server finds which combo weapon is in
-- hand, works out which step of its combo this is (from its own timing, so clients can't
-- skip to the finisher), checks the cooldown, builds the hitbox, and deals that step's
-- damage, plus its knockback and stun if it has any.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local MeleeHitbox = require(script.Parent.MeleeHitbox)

type ComboWeapon = CombatConfig.ComboWeapon

-- Network delay makes clicks arrive slightly early or late; allow this much either way.
local TIMING_SLACK = 0.1
local KNOCKBACK_TIME = 0.2

local swingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MeleeSwing") :: RemoteEvent

local WeaponService = {}

type ComboState = { step: number, time: number }
local comboStates: { [Player]: ComboState } = {}

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

local CREATORS: { [string]: () -> Tool } = {
	[CombatConfig.Sword.ToolName] = createSword,
	[CombatConfig.Mace.ToolName] = createMace,
	[CombatConfig.Spear.ToolName] = createSpear,
}

local COMBO_WEAPONS: { ComboWeapon } = { CombatConfig.Sword, CombatConfig.Mace, CombatConfig.Spear }

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
	if not config or player:GetAttribute("Blocking") == true then
		return -- not holding a combo weapon, or blocking
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
	comboStates[player] = { step = step, time = now }

	local move = combo[step]
	task.delay(move.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) then
			return
		end
		local size = Vector3.new(config.Width, config.Height, config.Range)
		for _, hit in MeleeHitbox.strike(player, character, root, size, move.Damage, config.ToolName) do
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
	end)
	weapon.Parent = player:WaitForChild("Backpack")
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
	end)
	swingRemote.OnServerEvent:Connect(onSwing)
end

-- Hands one combo weapon to every player (on each spawn). Call in the order the weapons
-- should appear in the hotbar.
function WeaponService.give(config: ComboWeapon)
	local create = CREATORS[config.ToolName]
	assert(create, `No model for combo weapon {config.ToolName}`)
	distribute(config, create())
end

return WeaponService
