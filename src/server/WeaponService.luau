--!strict
-- Gives players a sword and resolves sword hits on the server.
-- The client only reports "I swung"; the server checks cooldown, builds the hitbox, and deals damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HealthService = require(script.Parent.HealthService)

local SWORD = CombatConfig.Sword

local swingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SwordSwing") :: RemoteEvent

local WeaponService = {}

local lastSwing: { [Player]: number } = {}

local function addSwordPart(handle: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
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

-- Placeholder sword built from parts. The Handle is the grip; the blade extends along +Z.
local function createSword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = SWORD.ToolName
	tool.CanBeDropped = false
	-- Rotated so the blade (+Z) points straight up out of the fist.
	tool.Grip = CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 1.2)
	handle.Color = Color3.fromRGB(70, 45, 30)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	addSwordPart(handle, "Guard", Vector3.new(1.4, 0.3, 0.25), CFrame.new(0, 0, 0.7), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	local blade = addSwordPart(handle, "Blade", Vector3.new(0.15, 0.5, 4), CFrame.new(0, 0, 2.8), Color3.fromRGB(210, 215, 225), Enum.Material.Metal)

	-- Swing trail along the blade; the client enables it during the slash.
	local trailBase = Instance.new("Attachment")
	trailBase.Name = "TrailBase"
	trailBase.Position = Vector3.new(0, 0, -1.6)
	trailBase.Parent = blade

	local trailTip = Instance.new("Attachment")
	trailTip.Name = "TrailTip"
	trailTip.Position = Vector3.new(0, 0, 2)
	trailTip.Parent = blade

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = trailBase
	trail.Attachment1 = trailTip
	trail.Lifetime = 0.15
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Enabled = false
	trail.Parent = blade

	local slashSound = Instance.new("Sound")
	slashSound.Name = "SlashSound"
	slashSound.SoundId = "rbxasset://sounds/swordslash.wav"
	slashSound.Volume = 0.6
	slashSound.Parent = handle

	return tool
end

-- Walks up from a hit part to the model that owns a Health attribute, if any.
local function findDamageable(part: BasePart): Model?
	local current = part.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Health") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function resolveHit(player: Player, character: Model, root: BasePart)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local boxCFrame = root.CFrame * CFrame.new(0, 0, -SWORD.Range / 2)
	local boxSize = Vector3.new(SWORD.Width, SWORD.Height, SWORD.Range)
	local hitModels: { [Model]: boolean } = {}

	for _, part in workspace:GetPartBoundsInBox(boxCFrame, boxSize, params) do
		local model = findDamageable(part)
		-- Co-op game: no friendly fire, and each model is hit at most once per swing.
		if model and not hitModels[model] and not Players:GetPlayerFromCharacter(model) then
			hitModels[model] = true
			HealthService.damage(model, SWORD.Damage, player)
		end
	end
end

local function onSwing(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= SWORD.ToolName then
		return
	end

	local now = os.clock()
	if now - (lastSwing[player] or 0) < SWORD.Cooldown then
		return
	end
	lastSwing[player] = now

	task.delay(SWORD.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and HealthService.isAlive(character) then
			resolveHit(player, character, root)
		end
	end)
end

function WeaponService.start()
	local swordTemplate = createSword()

	local function onPlayerAdded(player: Player)
		-- The Backpack is reset on every respawn, so hand out a fresh sword each time.
		player.CharacterAdded:Connect(function()
			swordTemplate:Clone().Parent = player:WaitForChild("Backpack")
		end)
		if player.Character then
			swordTemplate:Clone().Parent = player:WaitForChild("Backpack")
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)

	swingRemote.OnServerEvent:Connect(onSwing)
end

return WeaponService
