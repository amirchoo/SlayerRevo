--!strict
-- Armor stands in the Training Grounds: a row along the west wall, one per armor set, each a
-- wooden mannequin wearing the set and holding its weapon (the one it's the starter set of),
-- frozen in one of that weapon's own poses. Its ProximityPrompt gives the player the set and
-- the weapon and puts them on (like the Test Chest: for testing, not the final loot path).
-- The pose plays on each client (MannequinPoses), from the mannequin's "PoseAnimation" and
-- "PoseAt" attributes, tagged POSE_TAG.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local ArmorService = require(script.Parent.ArmorService)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)

type Stand = {
	Set: string, -- an ArmorConfig.Sets id
	Weapon: string, -- an InventoryConfig.Weapons name
	Pose: string, -- an animation of the weapon's
	PoseAt: number, -- how far through it to freeze, 0..1 (1 = its last frame)
}

-- In order along the wall, north to south.
local STANDS: { Stand } = {
	{ Set = "Leather", Weapon = "Sword", Pose = "rbxassetid://82457273702146", PoseAt = 1 }, -- SwordGuard
	{ Set = "Iron", Weapon = "Emberfang", Pose = "rbxassetid://108194359632313", PoseAt = 0.38 }, -- SwordSwing3, just past the hit (0.46 of 1.20 s)
	{ Set = "Warhide", Weapon = "Greatsword", Pose = "rbxassetid://98786062327224", PoseAt = 1 }, -- GreatswordCharge
	{ Set = "Woodcutter", Weapon = "Axe", Pose = "rbxassetid://86819744387869", PoseAt = 1 }, -- AxeWindUp
	{ Set = "Warden", Weapon = "Mace", Pose = "rbxassetid://92676795728467", PoseAt = 1 }, -- MaceWindUp
	{ Set = "Vanguard", Weapon = "Hammer", Pose = "rbxassetid://106260116576920", PoseAt = 1 }, -- HammerWindUp
	{ Set = "Skirmisher", Weapon = "Spear", Pose = "rbxassetid://116496473188639", PoseAt = 1 }, -- SpearWindUp
	{ Set = "Duelist", Weapon = "Rapier", Pose = "rbxassetid://84782831490199", PoseAt = 1 }, -- RapierWindUp
	{ Set = "Prowler", Weapon = "DualBlade", Pose = "rbxassetid://85472441817145", PoseAt = 1 }, -- DualBladeGuard
	{ Set = "Reaper", Weapon = "Scythe", Pose = "rbxassetid://93099600284244", PoseAt = 0.35 }, -- ScytheReap, mid-reap
	{ Set = "Apprentice", Weapon = "Staff", Pose = "rbxassetid://80897307077510", PoseAt = 1 }, -- StaffCharge
}

local POSE_TAG = "PosedMannequin"
local ROW_X = -53 -- X offset from the arena's center: along the west wall, facing east
local FIRST_Z = -30 -- Z offset of the first stand
local SPACING = 6
local PROMPT_RANGE = 8

local COLORS = {
	Pedestal = Color3.fromRGB(100, 100, 105),
	Text = Color3.fromRGB(250, 235, 200),
}

local TrainingStands = {}

-- Welds a display copy of `name` into the mannequin's hands, once it exists (the weapon
-- services register it with InventoryService at server start).
local function holdWeapon(mannequin: Model, name: string)
	local found = InventoryService.displayCopy(name)
	while not found do
		task.wait(1)
		found = InventoryService.displayCopy(name)
	end
	local tool = found :: Tool
	if not mannequin.Parent then
		tool:Destroy()
		return
	end
	local weapon = Instance.new("Model")
	weapon.Name = "HeldWeapon"
	for _, child in tool:GetChildren() do
		child.Parent = weapon
	end
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") or descendant:IsA("Trail") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	-- Which parts are welded together (the grip and its blade; a dual-wielded weapon is two
	-- such groups).
	local links: { [BasePart]: { BasePart } } = {}
	for _, joint in weapon:GetDescendants() do
		if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
			local a, b = joint.Part0, joint.Part1
			if a and b then
				links[a] = links[a] or {}
				links[b] = links[b] or {}
				table.insert(links[a], b)
				table.insert(links[b], a)
			end
		end
	end
	local function group(start: BasePart): { BasePart }
		local seen, list = { [start] = true }, { start }
		local index = 1
		while list[index] do
			for _, other in links[list[index]] or {} do
				if not seen[other] then
					seen[other] = true
					table.insert(list, other)
				end
			end
			index += 1
		end
		return list
	end

	-- The grip part in the right hand, and a dual-wielded weapon's twin in the left; the same
	-- offsets HandGrip uses when a player holds it.
	for gripName, hand in { [HandGrip.GRIP_NAME] = "Right", [HandGrip.OFFHAND_NAME] = "Left" } do
		local grip = weapon:FindFirstChild(gripName)
		local handPart = mannequin:FindFirstChild(`{hand}Hand`)
		local attachment = handPart and handPart:FindFirstChild(`{hand}GripAttachment`)
		if grip and grip:IsA("BasePart") and handPart and handPart:IsA("BasePart") and attachment and attachment:IsA("Attachment") then
			-- Move the grip and everything welded to it into the hand first: on an anchored
			-- mannequin the weld places the grip, but nothing drags its blade along, which
			-- stayed wherever the copy was made.
			local move = handPart.CFrame * attachment.CFrame * tool.Grip:Inverse() * grip.CFrame:Inverse()
			for _, part in group(grip) do
				part.CFrame = move * part.CFrame
			end
			local weld = Instance.new("Weld")
			weld.Part0 = handPart
			weld.Part1 = grip
			weld.C0 = attachment.CFrame
			weld.C1 = tool.Grip
			weld.Parent = grip
		end
	end
	tool:Destroy()
	weapon.Parent = mannequin
end

-- Gives the player the stand's set and weapon, wears the set, and draws the weapon.
local function equip(player: Player, stand: Stand)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end
	ArmorService.giveSet(player, stand.Set)
	if InventoryService.owns(player, stand.Weapon) then
		InventoryService.move(player, stand.Weapon, true)
	else
		InventoryService.grant(player, stand.Weapon)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(stand.Weapon)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if tool and tool:IsA("Tool") and humanoid then
		humanoid:EquipTool(tool)
	end
end

-- A mannequin standing on `feet`, wearing the stand's set, posed, and (soon) holding its
-- weapon. Parent it before yielding.
local function posed(feet: CFrame, stand: Stand): Model
	local mannequin = ArmorService.mannequin(feet, stand.Set)
	mannequin:SetAttribute("PoseAnimation", stand.Pose)
	mannequin:SetAttribute("PoseAt", stand.PoseAt)
	CollectionService:AddTag(mannequin, POSE_TAG)
	-- Deferred: the caller parents the mannequin first (holdWeapon drops the weapon on an
	-- unparented one, taking it for removed).
	task.defer(holdWeapon, mannequin, stand.Weapon)
	return mannequin
end

local function buildStand(parent: Instance, stand: Stand, index: number)
	local set = ArmorConfig.Sets[stand.Set]
	if not set or not InventoryConfig.weapon(stand.Weapon) then
		warn(`TrainingStands: unknown set {stand.Set} or weapon {stand.Weapon}`)
		return
	end
	local base = TrainingArea.CENTER + Vector3.new(ROW_X, 0, FIRST_Z + (index - 1) * SPACING)
	local origin = CFrame.lookAt(base, base + Vector3.xAxis)

	local model = Instance.new("Model")
	model.Name = `{stand.Set}Stand`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- never arrives half-built
	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Size = Vector3.new(4, 0.5, 3)
	pedestal.CFrame = origin * CFrame.new(0, 0.25, 0)
	pedestal.Color = COLORS.Pedestal
	pedestal.Material = Enum.Material.Slate
	pedestal.Anchored = true
	pedestal.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 24)
	gui.StudsOffset = Vector3.new(0, 7.6, 0)
	gui.MaxDistance = 40
	gui.Parent = pedestal
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = COLORS.Text
	label.TextStrokeTransparency = 0.4
	label.Text = `{set.Name} + {stand.Weapon}`
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Equip"
	prompt.ObjectText = `{set.Name} armor + {stand.Weapon}`
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal
	prompt.Triggered:Connect(function(player)
		equip(player, stand)
	end)

	local mannequin = posed(origin * CFrame.new(0, 0.5, 0), stand)
	mannequin.Parent = model
	model.Parent = parent
end

-- A posed mannequin like set `setId`'s stand (wearing it, holding its weapon), standing on
-- `feet`; nil if no stand shows that set. Yields (making the mannequin); parent the result
-- before yielding again. The Hall of Oaths' statues are these.
function TrainingStands.mannequin(feet: CFrame, setId: string): Model?
	for _, stand in STANDS do
		if stand.Set == setId then
			return posed(feet, stand)
		end
	end
	return nil
end

-- Builds every stand (making each mannequin yields, so call it with task.spawn).
function TrainingStands.build()
	local parent = workspace:FindFirstChild("TrainingGround") or workspace
	for index, stand in STANDS do
		task.spawn(buildStand, parent, stand, index)
	end
end

return TrainingStands
