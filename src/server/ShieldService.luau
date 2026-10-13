--!strict
-- Shields (see ShieldConfig): what each player owns and wears, and where it hangs.
-- The worn shield is held on the left forearm while a one-handed weapon is out, and slung on
-- the back otherwise. Its blocking bonus is applied by BlockService, which reads the "Shield"
-- attribute through ShieldConfig.active.
-- The backpack (ShieldEquip remote) puts an owned shield on or takes it off; the server checks
-- ownership. The worn shield stays on through respawns and is saved.
-- State the HUD reads, as player attributes: "Shield" (the worn shield's id, or nil) and
-- "OwnsShield<Id>".
-- Looks: if ServerStorage.ShieldModels (assets/shields) has a Model or MeshPart named after
-- the shield's id, that's worn (scaled to ShieldConfig.Diameter, its face along its -Z);
-- otherwise a placeholder built from plain parts. Look-only copies of every shield go in
-- ReplicatedStorage.ShieldPreviews, for the backpack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ShieldConfig = require(ReplicatedStorage.Shared.Config.ShieldConfig)
local AvatarService = require(script.Parent.AvatarService)
local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)

type Loadout = { owned: { [string]: boolean }, worn: string? }

local MODEL_NAME = "WornShield"

local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShieldEquip") :: RemoteEvent

local ShieldService = {}

local loadouts: { [Player]: Loadout } = {}

-- Looks --------------------------------------------------------------------------------------

local function placeholderPart(model: Model, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = model
end

-- A round shield of plain parts, its face toward -Z (like an imported model).
local function placeholder(shield: ShieldConfig.Shield): Model
	local model = Instance.new("Model")
	local flat = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is X; turn it to Z
	local dark = Color3.fromRGB(25, 20, 20)
	placeholderPart(model, Enum.PartType.Cylinder, Vector3.new(0.15, 2.6, 2.6), CFrame.new(0, 0, 0) * flat, shield.TrimColor, Enum.Material.Metal)
	placeholderPart(model, Enum.PartType.Cylinder, Vector3.new(0.15, 2.3, 2.3), CFrame.new(0, 0, -0.08) * flat, shield.Color, Enum.Material.WoodPlanks)
	placeholderPart(model, Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 0, -0.12), shield.TrimColor, Enum.Material.Metal)
	placeholderPart(model, Enum.PartType.Block, Vector3.new(0.25, 0.9, 0.2), CFrame.new(0, 0, 0.18), dark, Enum.Material.Fabric) -- the grip
	model.WorldPivot = CFrame.new()
	return model
end

-- The shield's model: the imported one (a lone MeshPart gets wrapped in a Model), or the placeholder.
local function modelFor(id: string, shield: ShieldConfig.Shield): Model
	local folder = ServerStorage:FindFirstChild("ShieldModels")
	local source = folder and folder:FindFirstChild(id)
	local model: Model? = nil
	if source and source:IsA("Model") then
		model = source:Clone()
	elseif source and source:IsA("BasePart") then
		model = Instance.new("Model")
		source:Clone().Parent = model
	elseif source then
		warn(`ShieldService: {id} should be a Model or a MeshPart, not a {source.ClassName}`)
	end
	if not model then
		return placeholder(shield)
	end
	-- Measure along the biggest part's own axes (an imported mesh's axes are the model's).
	local biggest: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and (not biggest or descendant.Size.Magnitude > biggest.Size.Magnitude) then
			biggest = descendant
		end
	end
	if not biggest then
		warn(`ShieldService: {id} has no parts`)
		model:Destroy()
		return placeholder(shield)
	end
	model.PrimaryPart = biggest
	return model
end

-- Where the shield goes on `bodyPart`: its center and turn, face along the returned frame's -Z.
local function mountOn(bodyPart: BasePart, onArm: boolean): CFrame
	local size = bodyPart.Size
	if onArm then
		-- On the outside of the left forearm (its -X), lying along the arm.
		local position = Vector3.new(-(size.X / 2 + ShieldConfig.ArmGap), ShieldConfig.ArmAlong, 0)
		return CFrame.fromMatrix(position, Vector3.yAxis, Vector3.zAxis, Vector3.xAxis)
	end
	-- Flat on the back (+Z), facing away.
	local position = Vector3.new(0, 0, size.Z / 2 + ShieldConfig.BackGap)
	return CFrame.fromMatrix(position, -Vector3.xAxis, Vector3.yAxis, -Vector3.zAxis)
end

-- Fits `model` to ShieldConfig.Diameter and welds it onto `bodyPart`.
local function attach(model: Model, bodyPart: BasePart, onArm: boolean)
	local _, before = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * ShieldConfig.Diameter / math.max(before.X, before.Y))
	local center, size = model:GetBoundingBox()
	if ShieldConfig.FlipFace then
		center *= CFrame.Angles(0, math.pi, 0)
	end
	-- The plate's back is a little behind the model's center (the grip sticks out further
	-- back, around the arm), so move it out by that much.
	local mount = mountOn(bodyPart, onArm) * CFrame.new(0, 0, -size.Z * 0.15)
	model:PivotTo(bodyPart.CFrame * mount * center:ToObjectSpace(model:GetPivot()))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false -- never gets in the way of hitboxes or raycasts
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bodyPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

-- Puts the worn shield where it belongs right now (arm or back), or takes it off.
local function dress(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild(MODEL_NAME)
	if old then
		old:Destroy()
	end
	local id = loadouts[player] and loadouts[player].worn
	local shield = id and ShieldConfig.Shields[id]
	if not id or not shield then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local onArm = tool ~= nil and ShieldConfig.canUseWith(tool.Name)
	local bodyPart = character:FindFirstChild(if onArm then "LeftLowerArm" else "UpperTorso")
	if not bodyPart or not bodyPart:IsA("BasePart") then
		return
	end
	local model = modelFor(id, shield)
	model.Name = MODEL_NAME
	attach(model, bodyPart, onArm)
	model.Parent = character
end

-- Player state -------------------------------------------------------------------------------

local function loadoutOf(player: Player): Loadout
	local loadout = loadouts[player]
	if not loadout then
		loadout = { owned = {} }
		loadouts[player] = loadout
	end
	return loadout
end

local function publish(player: Player)
	local loadout = loadoutOf(player)
	local data = DataService.data(player)
	if data then
		data.Shield = { Owned = table.clone(loadout.owned), Worn = loadout.worn } -- saved
	end
	player:SetAttribute("Shield", loadout.worn)
	for id in ShieldConfig.Shields do
		player:SetAttribute(`OwnsShield{id}`, loadout.owned[id] == true)
	end
end

-- Wears shield `id`, or takes the shield off when `id` is nil.
local function wear(player: Player, id: string?)
	loadoutOf(player).worn = id
	publish(player)
	dress(player)
end

-- Gives the player a shield and puts it on.
function ShieldService.giveShield(player: Player, id: string)
	assert(ShieldConfig.Shields[id], `Unknown shield {id}`)
	loadoutOf(player).owned[id] = true
	wear(player, id)
end

-- Never trust the client: nil (take it off), or a shield it owns.
local function onEquip(player: Player, id: unknown)
	if id == nil then
		wear(player, nil)
	elseif typeof(id) == "string" and ShieldConfig.Shields[id] and loadoutOf(player).owned[id] then
		wear(player, id)
	end
end

-- Look-only copies (anchored parts, no joints) of every shield, so the backpack can show them.
local function publishPreviews()
	local previews = Instance.new("Folder")
	previews.Name = "ShieldPreviews"
	for id, shield in ShieldConfig.Shields do
		local preview = modelFor(id, shield)
		preview.Name = id
		for _, descendant in preview:GetDescendants() do
			if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") or descendant:IsA("LuaSourceContainer") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		preview.Parent = previews
	end
	previews.Parent = ReplicatedStorage
end

function ShieldService.start()
	publishPreviews()
	-- Restores the saved shield: owned ones that still exist, and the worn one if owned.
	DataService.onLoaded(function(player, data)
		local saved = data.Shield
		local loadout = loadoutOf(player)
		if typeof(saved) == "table" then
			if typeof(saved.Owned) == "table" then
				for id, owned in saved.Owned do
					if owned == true and ShieldConfig.Shields[id] then
						loadout.owned[id] = true
					end
				end
			end
			if typeof(saved.Worn) == "string" and loadout.owned[saved.Worn] then
				loadout.worn = saved.Worn
			end
		end
		publish(player)
		dress(player)
	end)

	local function onCharacter(player: Player, character: Model)
		-- Moves between arm and back as weapons are drawn and put away.
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				dress(player)
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				dress(player)
			end
		end)
		dress(player)
	end
	local function onPlayerAdded(player: Player)
		publish(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	-- Applying the character's look can rebuild its parts, so put the shield back after.
	AvatarService.onApplied(dress)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		loadouts[player] = nil
	end)

	RemoteGuard.connect(equipRemote, onEquip)
end

return ShieldService
