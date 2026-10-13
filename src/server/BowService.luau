--!strict
-- Gives players a bow and simulates its arrows on the server.
-- The client reports when it starts drawing (BowDraw) and where it aims on release
-- (BowShoot). The server times the draw itself to get the power, checks the bow is
-- equipped, the cooldown, and ammo, then flies the arrow (with a little drop; see Projectile) and deals damage.
-- Ammo lives in the player's "Arrows"/"MaxArrows" attributes so the HUD can read it.
-- Arrows refill on respawn and while standing in the hub or the training grounds.

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

local BOW = CombatConfig.Bow

local REFILL_CHECK_INTERVAL = 1
local SHOOT_HEIGHT = 1.5 -- arrows leave from about chest height above the root
local SHOOT_FORWARD = 2 -- and this far ahead of the player, so they don't start inside them

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local drawRemote = remotes:WaitForChild("BowDraw") :: RemoteEvent
local shootRemote = remotes:WaitForChild("BowShoot") :: RemoteEvent

local BowService = {}

local lastShot: { [Player]: number } = {}
local drawStarted: { [Player]: number } = {}

local function addBowPart(handle: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
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
end

-- Placeholder bow built from parts, held in BOW.Hand (see HandGrip). Uses the
-- same Grip as the sword, so its grip part's +Z points up out of the fist and -Y points
-- back toward the player.
local function createBow(): Tool
	local tool = Instance.new("Tool")
	tool.Name = BOW.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = false -- we weld it to the left hand ourselves
	tool.Grip = CFrame.Angles(math.pi / 2, 0, 0)

	local wood = Color3.fromRGB(110, 70, 40)
	local handle = Instance.new("Part")
	handle.Name = HandGrip.GRIP_NAME
	handle.Size = Vector3.new(0.35, 0.35, 1.2)
	handle.Color = Color3.fromRGB(60, 40, 25)
	handle.Material = Enum.Material.Fabric -- leather-wrapped grip
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	-- Limbs angle back toward the player at the tips; the string joins the tips.
	local limbAngle = math.rad(20)
	addBowPart(handle, "UpperLimb", Vector3.new(0.25, 0.3, 2.4), CFrame.new(0, -0.35, 1.7) * CFrame.Angles(limbAngle, 0, 0), wood, Enum.Material.Wood)
	addBowPart(handle, "LowerLimb", Vector3.new(0.25, 0.3, 2.4), CFrame.new(0, -0.35, -1.7) * CFrame.Angles(-limbAngle, 0, 0), wood, Enum.Material.Wood)
	local tipY = -0.35 - 1.2 * math.sin(limbAngle)
	local tipZ = 1.7 + 1.2 * math.cos(limbAngle)
	addBowPart(handle, "String", Vector3.new(0.05, 0.05, tipZ * 2), CFrame.new(0, tipY, 0), Color3.fromRGB(235, 230, 215), Enum.Material.SmoothPlastic)

	-- Where the string ends meet the limbs; the client draws the pulled string between them.
	for name, z in { UpperTip = tipZ, LowerTip = -tipZ } do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = Vector3.new(0, tipY, z)
		attachment.Parent = handle
	end

	return tool
end

local ARROW: Projectile.Look = {
	Name = "Arrow",
	Size = Vector3.new(0.15, 0.15, 3),
	Color = Color3.fromRGB(200, 170, 120),
	TrailColor = ColorSequence.new(Color3.fromRGB(255, 245, 220), Color3.fromRGB(255, 190, 110)),
}

local function hasBowReady(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= BOW.ToolName then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

local function onDraw(player: Player)
	if hasBowReady(player) then
		drawStarted[player] = os.clock()
	end
end

local function onShoot(player: Player, aimPoint: unknown)
	-- Never trust client input: must be a real, finite position.
	if typeof(aimPoint) ~= "Vector3" or aimPoint.Magnitude ~= aimPoint.Magnitude or aimPoint.Magnitude > 1e6 then
		return
	end

	local _, root = hasBowReady(player)
	local started = drawStarted[player]
	drawStarted[player] = nil
	if not root or not started then
		return
	end

	local now = os.clock()
	if now - (lastShot[player] or 0) < BOW.Cooldown then
		return
	end
	local arrows = player:GetAttribute("Arrows")
	if typeof(arrows) ~= "number" or arrows <= 0 then
		return
	end

	local start = root.Position + Vector3.new(0, SHOOT_HEIGHT, 0)
	local toAim = aimPoint - start
	if toAim.Magnitude < 1 then
		return
	end
	local direction = toAim.Unit
	if not StaminaService.spend(player, SkillMath.staminaCost(player, BOW.ToolName, BOW.ShotStamina, "Light")) then
		return -- too tired
	end

	-- Power comes from the server's own timing of the draw, so clients can't fake a full draw.
	-- Quick Draw and the like shorten the full draw (see SkillTrees).
	local drawTime = BOW.MaxDrawTime * math.max(1 - SkillMath.weapon(player, BOW.ToolName, "DrawSpeed"), 0.3)
	local power = math.clamp((now - started) / drawTime, 0, 1)
	local speed = BOW.MinArrowSpeed + (BOW.MaxArrowSpeed - BOW.MinArrowSpeed) * power
	local damage = SkillMath.damage(player, BOW.ToolName, BOW.MinDamage + (BOW.MaxDamage - BOW.MinDamage) * power, "Light")

	lastShot[player] = now
	player:SetAttribute("Arrows", arrows - 1)
	Projectile.fire(player, BOW, ARROW, start + direction * SHOOT_FORWARD, direction, speed, math.round(damage))
end

local function giveBow(player: Player, template: Tool)
	local bow = template:Clone()
	bow.Equipped:Connect(function()
		local character = bow.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(bow, character, BOW.Hand :: HandGrip.Hand, "BowGrip")
		end
	end)
	bow.Unequipped:Connect(function()
		HandGrip.detach(bow, "BowGrip")
	end)
	InventoryService.give(player, bow) -- the hotbar, or stored in the backpack
end

local function refill(player: Player)
	player:SetAttribute("Arrows", BOW.MaxArrows)
end

function BowService.start()
	local bowTemplate = createBow()
	-- A real model, if one's been added (assets/weapons). Its string is drawn by the game, so
	-- move the string's ends to the model's limb tips and put the resting string back.
	if WeaponModels.apply(bowTemplate, BOW.ModelFit) then
		local handle = bowTemplate:FindFirstChild(HandGrip.GRIP_NAME) :: BasePart
		local tips = BOW.StringTips * BOW.ModelFit.Length
		local upper = handle:FindFirstChild("UpperTip") :: Attachment
		local lower = handle:FindFirstChild("LowerTip") :: Attachment
		upper.Position = Vector3.new(0, tips.Y, tips.Z)
		lower.Position = Vector3.new(0, tips.Y, -tips.Z)
		addBowPart(handle, "String", Vector3.new(0.05, 0.05, tips.Z * 2), CFrame.new(0, tips.Y, 0), Color3.fromRGB(235, 230, 215), Enum.Material.SmoothPlastic)
	end

	local function onPlayerAdded(player: Player)
		player:SetAttribute("MaxArrows", BOW.MaxArrows)
		refill(player)

		-- The Backpack is reset on every respawn, so hand out a fresh bow each time.
		player.CharacterAdded:Connect(function()
			refill(player)
			giveBow(player, bowTemplate)
		end)
		if player.Character then
			giveBow(player, bowTemplate)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
		drawStarted[player] = nil
	end)

	RemoteGuard.connect(drawRemote, onDraw)
	RemoteGuard.connect(shootRemote, onShoot)

	-- Restock anyone standing somewhere safe.
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local arrows = player:GetAttribute("Arrows")
				if root and root:IsA("BasePart") and typeof(arrows) == "number" and arrows < BOW.MaxArrows then
					if SafeZone.contains(root.Position) or TrainingArea.contains(root.Position) then
						refill(player)
					end
				end
			end
			task.wait(REFILL_CHECK_INTERVAL)
		end
	end)
end

return BowService
