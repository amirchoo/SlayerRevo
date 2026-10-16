--!strict
-- Gives players a two-handed greatsword and resolves its attacks on the server.
-- Tapping swings a 3-hit combo of wide sweeps (GreatswordSwing); the server tracks the
-- combo step and timing itself and hits everything in each sweep's arc.
-- Holding charges a slam: the client reports when it starts charging (GreatswordCharge)
-- and when it releases (GreatswordRelease); the server times the charge itself, so clients
-- can't fake a full charge, picks the charge level, deals that level's damage with a big
-- hitbox, and knocks enemies back on strong slams. Guarding uses the shared block system
-- (BlockService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local EnemyEffects = require(script.Parent.EnemyEffects)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local MeleeHitbox = require(script.Parent.MeleeHitbox)
local WeaponModels = require(script.Parent.WeaponModels)
local StaminaService = require(script.Parent.StaminaService)

local GREATSWORD = CombatConfig.Greatsword
local LEVELS = GREATSWORD.ChargeLevels

-- Network delay makes messages arrive slightly early or late; allow this much.
local TIMING_SLACK = 0.1

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chargeRemote = remotes:WaitForChild("GreatswordCharge") :: RemoteEvent
local releaseRemote = remotes:WaitForChild("GreatswordRelease") :: RemoteEvent
local swingRemote = remotes:WaitForChild("GreatswordSwing") :: RemoteEvent

local GreatswordService = {}

local chargeStarted: { [Player]: number } = {}
local lastSlam: { [Player]: number } = {}
local comboStates: { [Player]: { step: number, time: number } } = {}

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

-- Placeholder greatsword built from parts: a long two-hand grip, wide crossguard, and a
-- broad 6.5-stud blade along the grip's +Z. Same Grip convention as the sword (the blade
-- points up out of the fist); the right hand holds it just below the guard.
local function createGreatsword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = GREATSWORD.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = false -- held via HandGrip so the default tool arm pose doesn't fight the animations
	tool.Grip = CFrame.new(0, 0, 0.45) * CFrame.Angles(math.pi / 2, 0, 0)

	local steel = Color3.fromRGB(190, 195, 205)
	local leather = Color3.fromRGB(55, 35, 25)
	local gold = Color3.fromRGB(190, 150, 60)

	local grip = Instance.new("Part")
	grip.Name = HandGrip.GRIP_NAME
	grip.Size = Vector3.new(0.35, 0.35, 1.7)
	grip.Color = leather
	grip.Material = Enum.Material.Fabric
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.Parent = tool

	addPart(grip, "Pommel", Vector3.one * 0.55, CFrame.new(0, 0, -1), gold, Enum.Material.Metal, Enum.PartType.Ball)
	addPart(grip, "Guard", Vector3.new(2.4, 0.35, 0.35), CFrame.new(0, 0, 0.95), gold, Enum.Material.Metal)
	local blade = addPart(grip, "Blade", Vector3.new(0.25, 1, 6.5), CFrame.new(0, 0, 4.35), steel, Enum.Material.Metal)
	addPart(grip, "Fuller", Vector3.new(0.27, 0.22, 5.4), CFrame.new(0, 0, 4.0), Color3.fromRGB(120, 125, 135), Enum.Material.Metal)

	-- Slam trail along the blade; the client turns it on during the slam.
	local trailBase = Instance.new("Attachment")
	trailBase.Name = "TrailBase"
	trailBase.Position = Vector3.new(0, 0, -2.8)
	trailBase.Parent = blade
	local trailTip = Instance.new("Attachment")
	trailTip.Name = "TrailTip"
	trailTip.Position = Vector3.new(0, 0, 3.2)
	trailTip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = trailBase
	trail.Attachment1 = trailTip
	trail.Lifetime = 0.2
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = blade

	-- The slam's impact, played by the client as it lands (found by the name "SlamSound"); see Sounds.
	local slamSound = Sounds.create("GreatswordSlam", grip)
	if slamSound then
		slamSound.Name = "SlamSound"
	end

	return tool
end

local function holdingGreatsword(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == GREATSWORD.ToolName
end

local function midSwing(player: Player, now: number): boolean
	local previous = comboStates[player]
	return previous ~= nil and now - previous.time < GREATSWORD.Combo[previous.step].Cooldown - TIMING_SLACK
end

local function onSwing(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) or not holdingGreatsword(character) then
		return
	end
	if player:GetAttribute("Blocking") == true or chargeStarted[player] then
		return
	end
	local now = os.clock()
	if now - (lastSlam[player] or 0) < GREATSWORD.Recovery - TIMING_SLACK or midSwing(player, now) then
		return -- still recovering from a slam or the last swing
	end

	-- Same rule as the client: the next step if clicked soon enough after the last swing,
	-- otherwise back to the first.
	local combo = GREATSWORD.Combo
	local step = 1
	local previous = comboStates[player]
	if previous and previous.step < #combo then
		local window = combo[previous.step].Cooldown + GREATSWORD.ComboWindow + TIMING_SLACK
		if now - previous.time <= window then
			step = previous.step + 1
		end
	end
	if not StaminaService.spend(player, SkillMath.staminaCost(player, GREATSWORD.ToolName, GREATSWORD.SwingStamina, "Light")) then
		return -- too tired
	end
	comboStates[player] = { step = step, time = now }

	local move = combo[step]
	task.delay(move.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) or not holdingGreatsword(character) then
			return
		end
		local damage = SkillMath.damage(player, GREATSWORD.ToolName, move.Damage, "Light")
		for _, hit in MeleeHitbox.strikeArc(player, character, root, move.Radius, move.Arc, damage, GREATSWORD.ToolName) do
			if move.Knockback and HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, move.Knockback, GREATSWORD.KnockbackTime)
			end
		end
	end)
end

local function onCharge(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) or not holdingGreatsword(character) then
		return
	end
	if player:GetAttribute("Blocking") == true then
		return
	end
	local now = os.clock()
	if now - (lastSlam[player] or 0) < GREATSWORD.Recovery - TIMING_SLACK or midSwing(player, now) then
		return -- still recovering from the last slam or swing
	end
	if not StaminaService.spend(player, SkillMath.staminaCost(player, GREATSWORD.ToolName, GREATSWORD.SlamStamina, "Heavy")) then
		return -- too tired
	end
	chargeStarted[player] = now
	comboStates[player] = nil -- a slam ends the combo
end

local function onRelease(player: Player)
	local started = chargeStarted[player]
	chargeStarted[player] = nil
	local character = player.Character
	if not started or not character or not HealthService.isAlive(character) or not holdingGreatsword(character) then
		return
	end

	-- The highest level reached, from the server's own timing of the charge.
	local now = os.clock()
	-- Swift Charge and the like make each level come sooner (see SkillTrees).
	local held = (now - started) * (1 + SkillMath.weapon(player, GREATSWORD.ToolName, "ChargeSpeed"))
	local level = LEVELS[1]
	for _, candidate in LEVELS do
		if held >= candidate.Time then
			level = candidate
		end
	end
	lastSlam[player] = now

	task.delay(GREATSWORD.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) then
			return
		end
		local size = Vector3.new(GREATSWORD.Width, GREATSWORD.Height, GREATSWORD.Range)
		local damage = SkillMath.damage(player, GREATSWORD.ToolName, level.Damage, "Heavy")
		for _, hit in MeleeHitbox.strike(player, character, root, size, damage, GREATSWORD.ToolName) do
			if level.Knockback > 0 and HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, level.Knockback, GREATSWORD.KnockbackTime)
			end
		end
	end)
end

local function giveGreatsword(player: Player, template: Tool)
	local greatsword = template:Clone()
	greatsword.Equipped:Connect(function()
		local character = greatsword.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(greatsword, character, GREATSWORD.Hand :: HandGrip.Hand, "GreatswordGrip")
		end
	end)
	greatsword.Unequipped:Connect(function()
		HandGrip.detach(greatsword, "GreatswordGrip")
		chargeStarted[player] = nil
	end)
	InventoryService.give(player, greatsword) -- the hotbar, or stored in the backpack
end

function GreatswordService.start()
	local template = createGreatsword()
	WeaponModels.apply(template, GREATSWORD.ModelFit) -- a real model, if one's been added (assets/weapons)
	InventoryService.register(template)

	local function onPlayerAdded(player: Player)
		-- The Backpack is reset on every respawn, so hand out a fresh one each time.
		player.CharacterAdded:Connect(function()
			giveGreatsword(player, template)
		end)
		if player.Character then
			giveGreatsword(player, template)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		chargeStarted[player] = nil
		lastSlam[player] = nil
		comboStates[player] = nil
	end)

	RemoteGuard.connect(chargeRemote, onCharge)
	RemoteGuard.connect(releaseRemote, onRelease)
	RemoteGuard.connect(swingRemote, onSwing)
end

return GreatswordService
