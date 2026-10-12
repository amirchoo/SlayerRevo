--!strict
-- The Test Chest in the Training Grounds: holds every item in the game, by category, for
-- testing while content is added bit by bit (not part of the final game's loot).
-- Its ProximityPrompt opens the chest panel on that player's screen (TestChestOpen remote,
-- with the chest's position so the panel closes when they walk away). Taking an item fires
-- TestChestTake (kind, id): the server checks the player is at the chest, then
--   "Weapon": gives the weapon if the player doesn't own it, and moves it into their hotbar;
--   "Armor":  gives the whole armor set and puts it on (ArmorService.giveSet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)
local ArmorService = require(script.Parent.ArmorService)
local CurrencyService = require(script.Parent.CurrencyService)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = remotes:WaitForChild("TestChestOpen") :: RemoteEvent
local takeRemote = remotes:WaitForChild("TestChestTake") :: RemoteEvent

-- In front of where players arrive in the arena, facing them.
local POSITION = TrainingArea.CENTER + Vector3.new(-12, 0, 24)
local FACING = TrainingArea.CENTER + Vector3.new(-20, 0, 40) -- the arena's arrival point
local USE_RANGE = 16 -- studs from the chest a take is accepted (a bit past the prompt's reach)

local COLORS = {
	Wood = Color3.fromRGB(120, 78, 45),
	DarkWood = Color3.fromRGB(85, 52, 30),
	Gold = Color3.fromRGB(230, 180, 60),
	Glow = Color3.fromRGB(255, 215, 120),
	Text = Color3.fromRGB(250, 235, 200),
}

local TestChest = {}

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- A wooden chest with gold bands and a lock, its front (-Z) facing the arrival point.
local function buildModel(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "TestChest"
	local origin = CFrame.lookAt(POSITION, Vector3.new(FACING.X, POSITION.Y, FACING.Z))

	local body = part(model, "Body", Vector3.new(4.4, 2.4, 2.8), origin * CFrame.new(0, 1.2, 0), COLORS.Wood, Enum.Material.WoodPlanks)
	part(model, "Lid", Vector3.new(4.5, 0.9, 2.9), origin * CFrame.new(0, 2.85, 0), COLORS.DarkWood, Enum.Material.WoodPlanks)
	for _, x in { -1.6, 1.6 } do
		part(model, "Band", Vector3.new(0.35, 3.4, 3.0), origin * CFrame.new(x, 1.65, 0), COLORS.Gold, Enum.Material.Metal)
	end
	part(model, "Rim", Vector3.new(4.6, 0.2, 3.0), origin * CFrame.new(0, 2.4, 0), COLORS.Gold, Enum.Material.Metal)
	part(model, "Lock", Vector3.new(0.7, 0.8, 0.25), origin * CFrame.new(0, 2.3, -1.5), COLORS.Gold, Enum.Material.Metal)

	-- A soft glow so it reads as "the place to get stuff".
	local light = Instance.new("PointLight")
	light.Color = COLORS.Glow
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = body

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 30)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.MaxDistance = 80
	gui.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = COLORS.Text
	label.TextStrokeTransparency = 0.4
	label.Text = "Test Chest"
	label.Parent = gui

	model.PrimaryPart = body
	return model, body
end

local function atChest(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and HealthService.isAlive(character :: Model) and (root.Position - POSITION).Magnitude <= USE_RANGE
end

-- Never trust the client: a known kind and item, and the player standing at the chest.
local function onTake(player: Player, kind: unknown, id: unknown)
	if typeof(kind) ~= "string" or typeof(id) ~= "string" or not atChest(player) then
		return
	end
	if kind == "Weapon" and InventoryConfig.weapon(id) then
		if InventoryService.owns(player, id) then
			InventoryService.move(player, id, true)
		else
			InventoryService.grant(player, id)
		end
	elseif kind == "Armor" and ArmorConfig.Sets[id] then
		ArmorService.giveSet(player, id)
	elseif kind == "Coins" then
		local amount = tonumber(id) or 100
		if amount > 0 and amount <= 5000 then
			CurrencyService.add(player, amount)
		end
	end
end

function TestChest.build()
	local model, body = buildModel()

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Test Chest"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		openRemote:FireClient(player, POSITION)
	end)

	model.Parent = workspace:FindFirstChild("TrainingGround") or workspace
	RemoteGuard.connect(takeRemote, onTake)
end

return TestChest
