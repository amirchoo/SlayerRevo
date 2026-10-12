--!strict
-- Decides which weapons a player owns, and which of those are in their hotbar or stored.
-- Weapon services hand every weapon they give a player to InventoryService.give (instead of
-- putting it in the Backpack themselves); it goes to the Backpack if it's in the player's
-- hotbar, otherwise to their storage folder in ServerStorage, where it can't be equipped.
-- Weapons the player doesn't own (saved in their data's Weapons) are parked out of reach
-- instead, until InventoryService.grant gives them one (the starter pick, the Test Chest).
-- Owned weapons are published as the "OwnedWeapons" attribute (comma-separated).
-- The client asks to move weapons with the InventoryMove remote (name, toHotbar); the server
-- checks the weapon is theirs and the hotbar has room. The hotbar list lives in the
-- player's "Hotbar" attribute (comma-separated, in order) for the backpack UI, and survives
-- respawns.
-- The first time it sees each weapon it also puts a display copy (parts only: no scripts,
-- sounds, or trails) in ReplicatedStorage.WeaponPreviews, so the backpack can show weapons
-- the player has stored, which live where clients can't see them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local moveRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryMove") :: RemoteEvent

local InventoryService = {}

local hotbars: { [Player]: { string } } = {}

local previews = Instance.new("Folder")
previews.Name = "WeaponPreviews"
previews.Parent = ReplicatedStorage

-- A look-only copy of `tool` for the backpack's weapon tiles.
local function addPreview(tool: Tool)
	if previews:FindFirstChild(tool.Name) then
		return
	end
	local copy = tool:Clone()
	local preview = Instance.new("Model")
	preview.Name = tool.Name
	for _, child in copy:GetChildren() do
		child.Parent = preview
	end
	copy:Destroy()
	for _, descendant in preview:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") or descendant:IsA("Trail") or descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	preview.Parent = previews
end

local storageRoot = Instance.new("Folder")
storageRoot.Name = "StoredWeapons"
storageRoot.Parent = ServerStorage

local parkedRoot = Instance.new("Folder")
parkedRoot.Name = "UnownedWeapons"
parkedRoot.Parent = ServerStorage

local function storageOf(player: Player): Folder
	local name = tostring(player.UserId)
	local folder = storageRoot:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = storageRoot
	end
	return folder :: Folder
end

-- Where a player's weapons they don't own wait (each weapon service still makes them, so
-- granting one is just moving it over).
local function parkOf(player: Player): Folder
	local name = tostring(player.UserId)
	local folder = parkedRoot:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parkedRoot
	end
	return folder :: Folder
end

function InventoryService.owns(player: Player, name: string): boolean
	local data = DataService.data(player)
	return data ~= nil and data.Weapons[name] == true
end

local function hotbarOf(player: Player): { string }
	local hotbar = hotbars[player]
	if not hotbar then
		hotbar = table.clone(InventoryConfig.DefaultHotbar)
		hotbars[player] = hotbar
	end
	return hotbar
end

local function publish(player: Player)
	local data = DataService.data(player)
	if data then
		data.Hotbar = table.clone(hotbarOf(player)) -- saved
	end
	player:SetAttribute("Hotbar", table.concat(hotbarOf(player), ","))
	player:SetAttribute("HotbarSlots", InventoryConfig.HotbarSlots)
	local owned: { string } = {}
	for _, info in InventoryConfig.Weapons do
		if InventoryService.owns(player, info.Name) then
			table.insert(owned, info.Name)
		end
	end
	player:SetAttribute("OwnedWeapons", table.concat(owned, ","))
end

-- The player's copy of a weapon, wherever it is right now.
local function findTool(player: Player, name: string): Tool?
	for _, place in { player.Character, player:FindFirstChildOfClass("Backpack"), storageOf(player) } do
		local tool = place and place:FindFirstChild(name)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

-- Puts a freshly given weapon where it belongs: the hotbar, storage, or (if the player
-- doesn't own it) parked. Replaces the player's previous copy (e.g. from before they respawned).
function InventoryService.give(player: Player, tool: Tool)
	addPreview(tool)
	local old = findTool(player, tool.Name) or parkOf(player):FindFirstChild(tool.Name)
	if old and old ~= tool then
		old:Destroy()
	end
	if not InventoryService.owns(player, tool.Name) then
		tool.Parent = parkOf(player)
	elseif table.find(hotbarOf(player), tool.Name) then
		tool.Parent = player:WaitForChild("Backpack")
	else
		tool.Parent = storageOf(player)
	end
end

-- Moves one of the player's weapons into their hotbar (if there's room) or into storage.
-- Returns whether the weapon ends up where asked.
function InventoryService.move(player: Player, name: string, toHotbar: boolean): boolean
	if not InventoryConfig.weapon(name) then
		return false
	end
	local tool = findTool(player, name)
	if not tool then
		return false -- not theirs
	end
	local hotbar = hotbarOf(player)
	local index = table.find(hotbar, name)
	if toHotbar and not index then
		if #hotbar >= InventoryConfig.HotbarSlots then
			return false -- full
		end
		table.insert(hotbar, name)
		tool.Parent = player:FindFirstChildOfClass("Backpack")
	elseif not toHotbar and index then
		table.remove(hotbar, index)
		local character = player.Character
		if character and tool.Parent == character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools() -- put it away first, so its unequip cleanup runs
			end
		end
		tool.Parent = storageOf(player)
	end
	publish(player)
	return true
end

-- Gives the player weapon `name` to keep (saved), into their hotbar if there's room.
function InventoryService.grant(player: Player, name: string)
	local data = DataService.data(player)
	if not data or not InventoryConfig.weapon(name) or data.Weapons[name] then
		return
	end
	data.Weapons[name] = true
	local hotbar = hotbarOf(player)
	if not table.find(hotbar, name) and #hotbar < InventoryConfig.HotbarSlots then
		table.insert(hotbar, name)
	end
	local tool = parkOf(player):FindFirstChild(name)
	if tool then
		tool.Parent = if table.find(hotbar, name) then player:FindFirstChildOfClass("Backpack") else storageOf(player)
	end
	publish(player)
end

local function onMove(player: Player, name: unknown, toHotbar: unknown)
	if typeof(name) == "string" and typeof(toHotbar) == "boolean" then
		InventoryService.move(player, name, toHotbar)
	end
end

-- Restores a saved hotbar (owned weapons only, up to the slot limit; the default if nothing's
-- saved) and moves the player's weapons to match: owned ones out of the parking folder,
-- unowned ones into it.
local function applySaved(player: Player, saved: { string }?)
	local list = if typeof(saved) == "table" then saved else InventoryConfig.DefaultHotbar
	local hotbar: { string } = {}
	for _, name in list do
		if typeof(name) == "string" and InventoryService.owns(player, name) and not table.find(hotbar, name) and #hotbar < InventoryConfig.HotbarSlots then
			table.insert(hotbar, name)
		end
	end
	hotbars[player] = hotbar
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, info in InventoryConfig.Weapons do
		local tool = findTool(player, info.Name) or parkOf(player):FindFirstChild(info.Name)
		if tool and tool:IsA("Tool") and tool.Parent ~= player.Character then
			tool.Parent = if not InventoryService.owns(player, info.Name)
				then parkOf(player)
				elseif table.find(hotbar, info.Name) then backpack
				else storageOf(player)
		end
	end
	publish(player)
end

-- Re-sorts the player's weapons after their owned list changed outside grant() (dev tools).
function InventoryService.refresh(player: Player)
	local data = DataService.data(player)
	applySaved(player, data and data.Hotbar)
end

function InventoryService.start()
	local function onPlayerAdded(player: Player)
		publish(player)
	end
	DataService.onLoaded(function(player, data)
		applySaved(player, data.Hotbar)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		hotbars[player] = nil
		for _, root in { storageRoot, parkedRoot } do
			local folder = root:FindFirstChild(tostring(player.UserId))
			if folder then
				folder:Destroy()
			end
		end
	end)
	RemoteGuard.connect(moveRemote, onMove)
end

return InventoryService
