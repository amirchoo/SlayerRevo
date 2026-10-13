--!strict
-- Ranged weapons that fire once and then reload: the crossbow (one bolt) and the blunderbuss
-- (a spread of pellets). One instance per weapon config: SingleShotService.start(config).
-- No draw: the client reports where it aims (the weapon's ShootRemote) and the shot flies at
-- full power (see Projectile). It holds Clip shots (1 if nil; the blunderbuss holds 3), at
-- least ShotDelay apart; the tool's "Rounds" attribute counts what's left in it. Once it's
-- empty it has to reload: the tool's "Loaded" attribute goes false, and back to true
-- ReloadTime later (with the clip filled again) if it's still in hand (putting it away stops
-- the reload; taking it out again restarts it). The server owns all of that, so
-- clients only ever see the result.
-- Ammo lives in the player's <Ammo>/Max<Ammo> attributes (e.g. "Bolts"/"MaxBolts") so the
-- HUD can read it. It refills on respawn and while standing in the hub or the training grounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local HealthService = require(script.Parent.HealthService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local InventoryService = require(script.Parent.InventoryService)
local WeaponModels = require(script.Parent.WeaponModels)
local StaminaService = require(script.Parent.StaminaService)
local Projectile = require(script.Parent.Projectile)

type Config = CombatConfig.SingleShot

local REFILL_CHECK_INTERVAL = 1
local SHOOT_HEIGHT = 1.5 -- shots leave from about chest height above the root
local SHOOT_FORWARD = 2 -- and this far ahead of the player, so they don't start inside them
local MIN_SHOT_GAP = 0.2 -- seconds; a floor under ReloadTime however fast skills make it

local WOOD, DARK = Color3.fromRGB(110, 70, 40), Color3.fromRGB(55, 35, 22)
local IRON = Color3.fromRGB(70, 72, 78)

-- What each weapon fires.
local LOOKS: { [string]: Projectile.Look } = {
	Crossbow = {
		Name = "Bolt",
		Size = Vector3.new(0.18, 0.18, 1.6),
		Color = Color3.fromRGB(90, 60, 40),
		TrailColor = ColorSequence.new(Color3.fromRGB(235, 240, 255), Color3.fromRGB(160, 190, 255)),
	},
	Blunderbuss = {
		Name = "Pellet",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Color = Color3.fromRGB(60, 60, 64),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
		TrailColor = ColorSequence.new(Color3.fromRGB(255, 235, 170), Color3.fromRGB(255, 150, 60)),
	},
}

local SingleShotService = {}

-- Seconds a reload takes for this player (Steady Hands and the like shorten it; the client
-- uses the same formula to pace the animation).
function SingleShotService.reloadTime(player: Player, config: Config): number
	return config.ReloadTime * math.max(1 - SkillMath.weapon(player, config.ToolName, "ReloadSpeed"), 0.3)
end

local function addPart(handle: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = handle.CFrame * offset
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = handle.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Placeholder looks built from parts (until a real model is added), held like a pistol: the
-- grip part's +Z runs forward along the forearm, +X is up (the thumb side), Y is across.
-- `behind`: how much of it is behind the hand.
local PLACEHOLDERS: { [string]: (handle: BasePart, length: number, behind: number) -> () } = {
	Crossbow = function(handle, length, behind)
		addPart(handle, "Stock", Vector3.new(0.3, 0.25, length), CFrame.new(0.15, 0, length / 2 - behind), WOOD, Enum.Material.Wood)
		addPart(handle, "Limbs", Vector3.new(0.15, length * 0.8, 0.2), CFrame.new(0.2, 0, length * 0.3), DARK, Enum.Material.Wood)
		addPart(handle, "String", Vector3.new(0.05, length * 0.75, 0.05), CFrame.new(0.2, 0, length * 0.22), Color3.fromRGB(235, 230, 215), Enum.Material.SmoothPlastic)
	end,
	Blunderbuss = function(handle, length, behind)
		addPart(handle, "Stock", Vector3.new(0.4, 0.25, behind + 0.4), CFrame.new(0, 0, (0.4 - behind) / 2), WOOD, Enum.Material.Wood)
		local barrel = length - behind
		addPart(handle, "Barrel", Vector3.new(0.2, 0.2, barrel), CFrame.new(0.25, 0, barrel / 2), IRON, Enum.Material.Metal)
		addPart(handle, "Muzzle", Vector3.new(0.4, 0.4, 0.3), CFrame.new(0.25, 0, barrel - 0.15), IRON, Enum.Material.Metal)
	end,
}

-- The crossbow's bolt resting on the rail while it's loaded (shown and hidden with "Loaded").
local function addLoadedBolt(tool: Tool, config: Config)
	local handle = tool:FindFirstChild(HandGrip.GRIP_NAME) :: BasePart
	local length = config.ModelFit.Length
	local z = length * (0.8 - config.ModelFit.GripFrom)
	local bolt = addPart(handle, "LoadedBolt", Vector3.new(0.12, 0.12, length * 0.35), CFrame.new(0.32, 0, z), LOOKS.Crossbow.Color, Enum.Material.Wood)
	bolt.CastShadow = false
end

local function createTool(config: Config): Tool
	local tool = Instance.new("Tool")
	tool.Name = config.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = false -- we weld it to the hand ourselves
	-- The hand's grip attachment has its Y forward out of the fist and Z up the arm; this
	-- turns the grip part so +Z runs down the forearm toward the fingers, +X toward the thumb.
	tool.Grip = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))
	tool:SetAttribute("Loaded", true)

	local handle = Instance.new("Part")
	handle.Name = HandGrip.GRIP_NAME
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	local length = config.ModelFit.Length
	PLACEHOLDERS[config.ToolName](handle, length, length * config.ModelFit.GripFrom)
	-- A real model, if one's been added (assets/weapons).
	WeaponModels.apply(tool, config.ModelFit)
	if config.ToolName == "Crossbow" then
		addLoadedBolt(tool, config)
	end
	return tool
end

-- A direction up to `spread` degrees off `aim`, spread evenly over the cone.
local function scatter(aim: Vector3, spread: number, random: Random): Vector3
	if spread <= 0 then
		return aim
	end
	local off = math.rad(spread) * math.sqrt(random:NextNumber())
	local around = random:NextNumber() * 2 * math.pi
	return (CFrame.lookAt(Vector3.zero, aim) * CFrame.Angles(0, 0, around) * CFrame.Angles(off, 0, 0)).LookVector
end

function SingleShotService.start(config: Config)
	local look = LOOKS[config.ToolName]
	local ammoName, maxName = config.Ammo, "Max" .. config.Ammo
	local shootRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(config.ShootRemote) :: RemoteEvent
	local gripName = config.ToolName .. "Grip"
	local random = Random.new()

	local lastShot: { [Player]: number } = {}
	-- Bumped to cancel a reload in progress; a reload only finishes if it's still the latest.
	local reloadToken: { [Player]: number } = {}
	local reloading: { [Player]: boolean } = {}

	local function inHand(player: Player): (Tool?, BasePart?)
		local character = player.Character
		if not character or not HealthService.isAlive(character) then
			return nil, nil
		end
		local tool = character:FindFirstChildOfClass("Tool")
		if not tool or tool.Name ~= config.ToolName then
			return nil, nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return nil, nil
		end
		return tool, root
	end

	local function setLoaded(tool: Tool, loaded: boolean)
		tool:SetAttribute("Loaded", loaded)
		local bolt = tool:FindFirstChild("LoadedBolt")
		if bolt and bolt:IsA("BasePart") then
			bolt.Transparency = if loaded then 0 else 1
		end
	end

	local function ammoOf(player: Player): number
		local ammo = player:GetAttribute(ammoName)
		return if typeof(ammo) == "number" then ammo else 0
	end

	local function roundsIn(tool: Tool): number
		local rounds = tool:GetAttribute("Rounds")
		return if typeof(rounds) == "number" then rounds else 0
	end

	local function setRounds(tool: Tool, rounds: number)
		tool:SetAttribute("Rounds", rounds)
		setLoaded(tool, rounds > 0)
	end

	-- Loads a full clip, or what's left of the player's ammo (the ammo count includes what's
	-- loaded, so a loaded round is spent from it when fired).
	local function fill(player: Player, tool: Tool)
		setRounds(tool, math.min(config.Clip or 1, ammoOf(player)))
	end

	local function cancelReload(player: Player)
		reloadToken[player] = (reloadToken[player] or 0) + 1
		reloading[player] = nil
	end

	-- Starts reloading `tool` if it's empty, in hand, and there's ammo to load.
	local function startReload(player: Player, tool: Tool)
		if roundsIn(tool) > 0 or reloading[player] or ammoOf(player) <= 0 then
			return
		end
		cancelReload(player)
		local token = reloadToken[player]
		reloading[player] = true
		task.delay(SingleShotService.reloadTime(player, config), function()
			if reloadToken[player] ~= token then
				return
			end
			reloading[player] = nil
			if tool.Parent == player.Character then
				fill(player, tool)
			end
		end)
	end

	local function onShoot(player: Player, aimPoint: unknown)
		-- Never trust client input: must be a real, finite position.
		if typeof(aimPoint) ~= "Vector3" or aimPoint.Magnitude ~= aimPoint.Magnitude or aimPoint.Magnitude > 1e6 then
			return
		end
		local tool, root = inHand(player)
		if not tool or not root or not tool:GetAttribute("Loaded") then
			return
		end
		local now = os.clock()
		if now - (lastShot[player] or 0) < math.max(config.ShotDelay or 0, MIN_SHOT_GAP) then
			return
		end
		local ammo = ammoOf(player)
		if ammo <= 0 then
			return
		end

		local start = root.Position + Vector3.new(0, SHOOT_HEIGHT, 0)
		local toAim = aimPoint - start
		if toAim.Magnitude < 1 then
			return
		end
		local direction = toAim.Unit
		if not StaminaService.spend(player, SkillMath.staminaCost(player, config.ToolName, config.ShotStamina, "Light")) then
			return -- too tired
		end

		lastShot[player] = now
		player:SetAttribute(ammoName, ammo - 1)
		setRounds(tool, roundsIn(tool) - 1)
		local damage = SkillMath.damage(player, config.ToolName, config.Damage, "Light")
		local damageRange = if config.DamageRange
			then config.DamageRange * (1 + SkillMath.weapon(player, config.ToolName, "DamageRange"))
			else nil
		local origin = start + direction * SHOOT_FORWARD
		for _ = 1, config.Pellets or 1 do
			local heading = scatter(direction, config.Spread or 0, random)
			Projectile.fire(player, config, look, origin, heading, config.ProjectileSpeed, damage, damageRange)
		end
		startReload(player, tool)
	end

	local function give(player: Player, template: Tool)
		local tool = template:Clone()
		fill(player, tool)
		tool.Equipped:Connect(function()
			local character = tool.Parent
			if character and character:IsA("Model") then
				HandGrip.attach(tool, character, config.Hand :: HandGrip.Hand, gripName)
			end
			startReload(player, tool) -- finish a reload that was interrupted
		end)
		tool.Unequipped:Connect(function()
			HandGrip.detach(tool, gripName)
			cancelReload(player)
		end)
		InventoryService.give(player, tool) -- the hotbar, or stored in the backpack
	end

	local function refill(player: Player)
		player:SetAttribute(ammoName, config.MaxAmmo)
	end

	local template = createTool(config)

	local function onPlayerAdded(player: Player)
		player:SetAttribute(maxName, config.MaxAmmo)
		refill(player)

		-- The Backpack is reset on every respawn, so hand out a fresh one each time.
		player.CharacterAdded:Connect(function()
			cancelReload(player)
			refill(player)
			give(player, template)
		end)
		if player.Character then
			give(player, template)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
		reloadToken[player] = nil
		reloading[player] = nil
	end)

	RemoteGuard.connect(shootRemote, onShoot)

	-- Restock anyone standing somewhere safe (and load the weapon in their hand if it ran dry).
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and ammoOf(player) < config.MaxAmmo then
					if SafeZone.contains(root.Position) or TrainingArea.contains(root.Position) then
						refill(player)
						local tool = inHand(player)
						if tool then
							startReload(player, tool)
						end
					end
				end
			end
			task.wait(REFILL_CHECK_INTERVAL)
		end
	end)
end

return SingleShotService
