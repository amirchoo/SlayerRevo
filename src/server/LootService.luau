--!strict
-- Loot on the ground: items dropped for one player (e.g. meat from an animal they killed),
-- hovering where they fell until that player walks close (MaterialConfig.Loot.PickupRange),
-- which puts them in their materials. Uncollected loot vanishes after Lifetime seconds, or
-- when its owner leaves.
-- Each drop is a Model in workspace.Loot (the item's model from ReplicatedStorage.ItemModels)
-- with "Owner" (UserId), "Item" and "From" (where it was dropped from) attributes; the
-- client hides other players' loot and makes its own pop out, bob and spin (LootClient).
-- Picking it up tells the owner's client (LootPickedUp remote: item Id, amount, position).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local MaterialService = require(script.Parent.MaterialService)

local LOOT = MaterialConfig.Loot
local CHECK_INTERVAL = 0.15

local pickedUpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LootPickedUp") :: RemoteEvent

local LootService = {}

local lootFolder = Instance.new("Folder")
lootFolder.Name = "Loot"

type Drop = { model: Model, owner: Player, item: string, droppedAt: number }
local drops: { Drop } = {}
local random = Random.new()

-- The ground under `position` (ignoring creatures, characters, loot, and the world's trees).
local function groundBelow(position: Vector3): Vector3
	local ignore: { Instance } = { lootFolder }
	for _, name in { "Animals", "Enemies", "World" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	return if result then result.Position else position
end

-- A copy of the item's model, scaled to LOOT.Size across, that can't be bumped or hit.
local function lootModel(item: MaterialConfig.Material): Model?
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	local source = folder and folder:FindFirstChild(item.Model)
	if not source or not source:IsA("Model") then
		warn(`[LootService] No ItemModels.{item.Model} for {item.Id}; it can't be dropped`)
		return nil
	end
	local model = source:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local _, size = model:GetBoundingBox()
	local largest = math.max(size.X, size.Y, size.Z)
	if largest > 0 then
		model:ScaleTo(model:GetScale() * LOOT.Size / largest)
	end
	return model
end

-- Drops one of `itemId` for `owner`, falling from `from` (e.g. where an animal died) to a
-- spot nearby.
function LootService.drop(owner: Player, itemId: string, from: Vector3)
	local item = MaterialConfig.item(itemId)
	if not item then
		warn(`[LootService] Unknown item {itemId}`)
		return
	end
	local model = lootModel(item)
	if not model then
		return
	end
	local angle = random:NextNumber(0, math.pi * 2)
	local spot = from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(0.5, 1) * LOOT.Scatter
	local rest = groundBelow(spot) + Vector3.new(0, LOOT.FloatHeight, 0)
	model.Name = item.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:PivotTo(CFrame.new(rest) * CFrame.Angles(0, angle, 0))
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("Item", item.Id)
	model:SetAttribute("From", from)
	model.Parent = lootFolder
	table.insert(drops, { model = model, owner = owner, item = item.Id, droppedAt = os.clock() })
end

local function check()
	local now = os.clock()
	for index = #drops, 1, -1 do
		local drop = drops[index]
		local keep = drop.model.Parent ~= nil and drop.owner.Parent ~= nil and now - drop.droppedAt < LOOT.Lifetime
		if keep and now - drop.droppedAt >= LOOT.PickupDelay then
			local character = drop.owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local position = drop.model:GetPivot().Position
			if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= LOOT.PickupRange then
				if MaterialService.grant(drop.owner, drop.item, 1) then
					pickedUpRemote:FireClient(drop.owner, drop.item, 1, position)
					keep = false
				end
			end
		end
		if not keep then
			drop.model:Destroy()
			table.remove(drops, index)
		end
	end
end

function LootService.start()
	lootFolder.Parent = workspace
	task.spawn(function()
		while true do
			check()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return LootService
