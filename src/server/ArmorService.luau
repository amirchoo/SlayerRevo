--!strict
-- Armor: what each player owns and wears, how much damage it negates, and how it looks.
-- Players get a set from the armor stand in the hub (a ProximityPrompt), which also puts
-- the whole set on; the backpack (ArmorEquip remote) takes single pieces on and off.
-- The server checks ownership; worn armor stays on through respawns.
-- State the HUD reads, as player attributes: "Protection" (0..1), "Armor<Slot>" (the worn
-- set's id, or nil), and "OwnsArmor<SetId>".
-- Looks: if ServerStorage.ArmorModels (assets/armor) has a file for a set's slot, that's
-- worn: one Accessory, or a Model holding several, e.g. a pair of boots (see
-- assets/armor/README.md). Otherwise a
-- placeholder built from plain parts is welded over the R15 body parts, sized to each part
-- so it fits any avatar. The stand shows the set on a wooden R15 mannequin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local HealthService = require(script.Parent.HealthService)
local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)

type ArmorSet = ArmorConfig.ArmorSet
type Loadout = { owned: { [string]: boolean }, worn: { [string]: string } } -- worn[slot] = set id

local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ArmorEquip") :: RemoteEvent

local ArmorService = {}

local loadouts: { [Player]: Loadout } = {}

-- Builders ------------------------------------------------------------------------------

-- Welds one armor plate onto `bodyPart`, `size` studs big, at `offset` from its center.
local function plate(parent: Instance, bodyPart: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false -- never gets in the way of hitboxes or raycasts
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = bodyPart.CFrame * offset
	part.Parent = parent

	local weld = Instance.new("Weld")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return part
end

type Body = { [string]: BasePart }

-- Each slot's look. `s` is the body part's size, so plates fit whatever avatar wears them.
-- Front is -Z, up is +Y.
local BUILDERS: { [string]: (model: Model, body: Body, set: ArmorSet) -> () } = {
	Helmet = function(model, body, set)
		local head = body.Head
		if not head then
			return
		end
		local s = head.Size
		local shell = Vector3.new(s.X + 0.3, s.Y + 0.25, s.Z + 0.3)
		plate(model, head, shell, CFrame.new(0, 0.1, 0), set.Color, set.Material)
		-- Dark eye slit across the front, and a crest along the top.
		plate(model, head, Vector3.new(shell.X * 0.8, 0.12, 0.06), CFrame.new(0, 0.12, -shell.Z / 2 - 0.02), Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic)
		plate(model, head, Vector3.new(0.14, 0.22, shell.Z * 0.85), CFrame.new(0, 0.1 + shell.Y / 2 + 0.1, 0), set.TrimColor, Enum.Material.Fabric)
	end,

	Chestplate = function(model, body, set)
		local upper, lower = body.UpperTorso, body.LowerTorso
		if upper then
			local s = upper.Size
			local shell = Vector3.new(s.X + 0.2, s.Y + 0.1, s.Z + 0.25)
			plate(model, upper, shell, CFrame.new(0, 0.05, 0), set.Color, set.Material)
			-- A raised breastplate on the front.
			plate(model, upper, Vector3.new(shell.X * 0.55, shell.Y * 0.7, 0.1), CFrame.new(0, 0.1, -shell.Z / 2 - 0.04), set.Color:Lerp(Color3.new(1, 1, 1), 0.15), set.Material)
		end
		if lower then
			local s = lower.Size
			plate(model, lower, Vector3.new(s.X + 0.25, s.Y + 0.15, s.Z + 0.3), CFrame.new(), set.TrimColor, Enum.Material.Fabric) -- belt
		end
	end,

	Armwear = function(model, body, set)
		for _, side in { "Left", "Right" } do
			local upper, lower = body[`{side}UpperArm`], body[`{side}LowerArm`]
			if upper then
				local s = upper.Size
				plate(model, upper, Vector3.new(s.X + 0.35, s.Y * 0.45, s.Z + 0.35), CFrame.new(0, s.Y * 0.3, 0), set.Color, set.Material) -- pauldron
			end
			if lower then
				local s = lower.Size
				plate(model, lower, Vector3.new(s.X + 0.18, s.Y * 0.75, s.Z + 0.18), CFrame.new(0, -0.05, 0), set.Color, set.Material) -- vambrace
			end
		end
	end,

	Leggings = function(model, body, set)
		for _, side in { "Left", "Right" } do
			local upper, lower = body[`{side}UpperLeg`], body[`{side}LowerLeg`]
			if upper then
				local s = upper.Size
				plate(model, upper, Vector3.new(s.X + 0.18, s.Y * 0.9, s.Z + 0.18), CFrame.new(), set.Color, set.Material) -- cuisse
			end
			if lower then
				local s = lower.Size
				plate(model, lower, Vector3.new(s.X + 0.16, s.Y * 0.55, s.Z + 0.16), CFrame.new(0, s.Y * 0.18, 0), set.Color, set.Material) -- knee and greave
			end
		end
	end,

	Boots = function(model, body, set)
		for _, side in { "Left", "Right" } do
			local lower, foot = body[`{side}LowerLeg`], body[`{side}Foot`]
			if foot then
				local s = foot.Size
				plate(model, foot, Vector3.new(s.X + 0.2, s.Y + 0.2, s.Z + 0.3), CFrame.new(0, 0.05, -0.05), set.Color, set.Material)
			end
			if lower then
				local s = lower.Size
				plate(model, lower, Vector3.new(s.X + 0.22, s.Y * 0.35, s.Z + 0.22), CFrame.new(0, -s.Y * 0.3, 0), set.TrimColor, Enum.Material.Fabric) -- cuff
			end
		end
	end,
}

local function bodyOf(model: Model): Body
	local body: Body = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			body[child.Name] = child
		end
	end
	return body
end

-- R15 body parts. Each gets an "Armor<PartName>" attachment at its center, so an armor
-- Accessory can sit on any body part (Roblox's own attachments skip the legs and lower arms).
local BODY_PARTS = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local function addArmorAttachments(model: Model)
	for _, name in BODY_PARTS do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") and not part:FindFirstChild(`Armor{name}`) then
			local attachment = Instance.new("Attachment")
			attachment.Name = `Armor{name}`
			attachment.Parent = part
		end
	end
end

-- The Accessories made for a set's slot in ServerStorage.ArmorModels, if any: the slot's
-- entry is one Accessory, or a Model holding several (one per body part, like a pair of boots).
local function accessoriesFor(setId: string, slot: string): { Accessory }?
	local models = ServerStorage:FindFirstChild("ArmorModels")
	local setFolder = models and models:FindFirstChild(setId)
	local entry = setFolder and setFolder:FindFirstChild(slot)
	if not entry then
		return nil
	end
	if entry:IsA("Accessory") then
		return { entry }
	end
	local list: { Accessory } = {}
	for _, child in entry:GetChildren() do
		if child:IsA("Accessory") then
			table.insert(list, child)
		end
	end
	return if #list > 0 then list else nil
end

-- Puts the look of `setId`'s `slot` piece on `model` (replacing whatever was there), or
-- just removes it when `setId` is nil. `model` needs a Humanoid to wear accessories.
local function dressSlot(model: Model, slot: string, setId: string?)
	-- Take off what's in the slot now: the placeholder, and any accessories we put on.
	for _, child in model:GetChildren() do
		if child.Name == `Armor{slot}` or child:GetAttribute("ArmorSlot") == slot then
			child:Destroy()
		end
	end
	local set = setId and ArmorConfig.Sets[setId]
	if not setId or not set or not set.Pieces[slot] then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local accessories = accessoriesFor(setId, slot)
	if accessories and humanoid then
		addArmorAttachments(model)
		for _, template in accessories do
			local accessory = template:Clone()
			accessory:SetAttribute("ArmorSlot", slot)
			-- Armor never gets in the way of hitboxes, raycasts, or movement (and an anchored
			-- piece would pin the wearer in place).
			for _, descendant in accessory:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.Massless = true
				end
			end
			humanoid:AddAccessory(accessory)
		end
		return
	end

	-- No model for this piece yet: the placeholder.
	local piece = Instance.new("Model")
	piece.Name = `Armor{slot}`
	BUILDERS[slot](piece, bodyOf(model), set)
	piece.Parent = model
end

-- Player state -----------------------------------------------------------------------------

local function loadoutOf(player: Player): Loadout
	local loadout = loadouts[player]
	if not loadout then
		loadout = { owned = {}, worn = {} }
		loadouts[player] = loadout
	end
	return loadout
end

local function protectionOf(loadout: Loadout): number
	local total = 0
	for slot, setId in loadout.worn do
		local set = ArmorConfig.Sets[setId]
		total += if set then set.Pieces[slot] or 0 else 0
	end
	return math.min(total, ArmorConfig.MaxProtection)
end

local function publish(player: Player)
	local loadout = loadoutOf(player)
	local data = DataService.data(player)
	if data then
		data.Armor = { Owned = table.clone(loadout.owned), Worn = table.clone(loadout.worn) } -- saved
	end
	player:SetAttribute("Protection", protectionOf(loadout))
	for _, slot in ArmorConfig.Slots do
		player:SetAttribute(`Armor{slot}`, loadout.worn[slot])
	end
	for setId in ArmorConfig.Sets do
		player:SetAttribute(`OwnsArmor{setId}`, loadout.owned[setId] == true)
	end
end

local function dressCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local loadout = loadoutOf(player)
	for _, slot in ArmorConfig.Slots do
		dressSlot(character, slot, loadout.worn[slot])
	end
end

-- Wears `setId`'s piece in `slot`, or takes the slot off when `setId` is nil.
local function wear(player: Player, slot: string, setId: string?)
	local loadout = loadoutOf(player)
	loadout.worn[slot] = setId
	if player.Character then
		dressSlot(player.Character, slot, setId)
	end
	publish(player)
end

-- Gives the player a whole set and puts every piece of it on.
function ArmorService.giveSet(player: Player, setId: string)
	local set = ArmorConfig.Sets[setId]
	assert(set, `Unknown armor set {setId}`)
	loadoutOf(player).owned[setId] = true
	for _, slot in ArmorConfig.Slots do
		if set.Pieces[slot] then
			wear(player, slot, setId)
		end
	end
	publish(player)
end

-- Never trust the client: a real slot, and a set it owns that has a piece for that slot.
local function onEquip(player: Player, slot: unknown, setId: unknown)
	if typeof(slot) ~= "string" or not table.find(ArmorConfig.Slots, slot) then
		return
	end
	if setId == nil then
		wear(player, slot, nil)
		return
	end
	if typeof(setId) ~= "string" then
		return
	end
	local set = ArmorConfig.Sets[setId]
	if set and set.Pieces[slot] and loadoutOf(player).owned[setId] then
		wear(player, slot, setId)
	end
end

-- Damage taken by a player is reduced by their armor. Runs after blocking (BlockService
-- adds its filter first), so armor reduces whatever gets through a block.
local function armorFilter(target: Model, amount: number): number
	local player = Players:GetPlayerFromCharacter(target)
	local protection = player and player:GetAttribute("Protection")
	if typeof(protection) ~= "number" then
		return amount
	end
	return amount * (1 - math.clamp(protection, 0, ArmorConfig.MaxProtection))
end

-- The armor stand ---------------------------------------------------------------------------

-- R15 body proportions for the fallback mannequin (studs): size and center relative to the
-- stand's base. Only used if a real R15 rig can't be made.
local MANNEQUIN: { { name: string, size: Vector3, position: Vector3 } } = {
	{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), position = Vector3.new(0, 5.85, 0) },
	{ name = "UpperTorso", size = Vector3.new(2, 1.6, 1), position = Vector3.new(0, 4.45, 0) },
	{ name = "LowerTorso", size = Vector3.new(2, 0.4, 1), position = Vector3.new(0, 3.45, 0) },
	{ name = "LeftUpperArm", size = Vector3.new(1, 1.17, 1), position = Vector3.new(-1.5, 4.65, 0) },
	{ name = "RightUpperArm", size = Vector3.new(1, 1.17, 1), position = Vector3.new(1.5, 4.65, 0) },
	{ name = "LeftLowerArm", size = Vector3.new(1, 1.05, 1), position = Vector3.new(-1.5, 3.55, 0) },
	{ name = "RightLowerArm", size = Vector3.new(1, 1.05, 1), position = Vector3.new(1.5, 3.55, 0) },
	{ name = "LeftUpperLeg", size = Vector3.new(1, 1.22, 1), position = Vector3.new(-0.5, 2.65, 0) },
	{ name = "RightUpperLeg", size = Vector3.new(1, 1.22, 1), position = Vector3.new(0.5, 2.65, 0) },
	{ name = "LeftLowerLeg", size = Vector3.new(1, 1.19, 1), position = Vector3.new(-0.5, 1.45, 0) },
	{ name = "RightLowerLeg", size = Vector3.new(1, 1.19, 1), position = Vector3.new(0.5, 1.45, 0) },
	{ name = "LeftFoot", size = Vector3.new(1, 0.3, 1), position = Vector3.new(-0.5, 0.7, 0) },
	{ name = "RightFoot", size = Vector3.new(1, 0.3, 1), position = Vector3.new(0.5, 0.7, 0) },
}

local function anchoredPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.Parent = parent
	return part
end

local function buildStand()
	local stand = ArmorConfig.Stand
	local set = ArmorConfig.Sets[stand.Set]
	assert(set, `Unknown armor set {stand.Set} for the armor stand`)

	-- Find the ground under the stand.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include: { Instance } = { workspace.Terrain }
	for _, name in { "Baseplate", "Town" } do
		local ground = workspace:FindFirstChild(name)
		if ground then
			table.insert(include, ground)
		end
	end
	params.FilterDescendantsInstances = include
	local top = Vector3.new(stand.Position.X, 500, stand.Position.Y)
	local hit = workspace:Raycast(top, Vector3.new(0, -1000, 0), params)
	local base = Vector3.new(stand.Position.X, if hit then hit.Position.Y else 0, stand.Position.Y)
	local facing = Vector3.new(-base.X, 0, -base.Z) -- toward the town center
	local origin = if facing.Magnitude > 0.1 then CFrame.lookAt(base, base + facing) else CFrame.new(base)

	local standModel = Instance.new("Model")
	standModel.Name = "ArmorStand"
	local wood = Color3.fromRGB(150, 110, 70)
	anchoredPart("Pedestal", Vector3.new(4, 0.5, 3), origin * CFrame.new(0, 0.25, 0), Color3.fromRGB(100, 100, 105), Enum.Material.Slate, standModel)

	-- The mannequin: a real R15 rig (so accessories can attach to it), painted as wood and
	-- pinned in place. Falls back to plain parts in R15 proportions if one can't be made.
	local mannequin: Model
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		mannequin = rig
		mannequin.Name = "Mannequin"
		local humanoid = mannequin:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			local bodyColors = humanoid:FindFirstChildOfClass("BodyColors")
			if bodyColors then
				bodyColors:Destroy()
			end
		end
		for _, child in mannequin:GetDescendants() do
			if child:IsA("BasePart") then
				child.Color = wood
				child.Material = Enum.Material.Wood
			elseif child:IsA("Decal") then
				child:Destroy() -- no face
			end
		end
		local root = mannequin:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true
			local height = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2)
			mannequin:PivotTo(origin * CFrame.new(0, 0.5 + height, 0))
		end
	else
		warn("ArmorService: couldn't make an R15 mannequin, using a plain one:", rig)
		mannequin = Instance.new("Model")
		mannequin.Name = "Mannequin"
		for _, piece in MANNEQUIN do
			anchoredPart(piece.name, piece.size, origin * CFrame.new(piece.position), wood, Enum.Material.Wood, mannequin)
		end
	end
	mannequin.Parent = standModel
	for _, slot in ArmorConfig.Slots do
		dressSlot(mannequin, slot, stand.Set)
	end
	local body = bodyOf(mannequin)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Take {set.Name} Armor`
	prompt.ObjectText = "Armor Stand"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body.UpperTorso
	prompt.Triggered:Connect(function(player)
		ArmorService.giveSet(player, stand.Set)
	end)

	standModel.Parent = workspace
end

function ArmorService.start()
	-- Restores saved armor: owned sets that still exist, and worn pieces of those sets.
	DataService.onLoaded(function(player, data)
		local saved = data.Armor
		if typeof(saved) ~= "table" then
			publish(player)
			return
		end
		local loadout = loadoutOf(player)
		if typeof(saved.Owned) == "table" then
			for setId, owned in saved.Owned do
				if owned == true and ArmorConfig.Sets[setId] then
					loadout.owned[setId] = true
				end
			end
		end
		if typeof(saved.Worn) == "table" then
			for slot, setId in saved.Worn do
				local set = ArmorConfig.Sets[setId]
				if table.find(ArmorConfig.Slots, slot) and set and set.Pieces[slot] and loadout.owned[setId] then
					loadout.worn[slot] = setId
				end
			end
		end
		dressCharacter(player)
		publish(player)
	end)

	local function onPlayerAdded(player: Player)
		publish(player)
		-- Worn armor stays on through respawns. Dress again once the avatar has loaded, since
		-- loading it can swap out the body parts the armor is welded to.
		player.CharacterAdded:Connect(function()
			dressCharacter(player)
		end)
		player.CharacterAppearanceLoaded:Connect(function()
			dressCharacter(player)
		end)
		dressCharacter(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		loadouts[player] = nil
	end)

	RemoteGuard.connect(equipRemote, onEquip)
	HealthService.addDamageFilter(armorFilter)
	task.spawn(buildStand) -- making the R15 mannequin waits on Roblox, so don't hold up the rest
end

return ArmorService
