--!strict
-- Decides which weapons/consumables a player owns, and which of those are in their hotbar.
-- Weapon services hand every weapon they give a player to InventoryService.give (instead of
-- putting it in the Backpack themselves); it goes to the Backpack if it's in the player's
-- hotbar, otherwise to their storage folder in ServerStorage, where it can't be equipped.
-- Weapons the player doesn't own (saved in their data's Weapons) are parked out of reach
-- instead, until InventoryService.grant gives them one (the starter pick, the Test Chest).
-- Owned weapons are published as the "OwnedWeapons" attribute (comma-separated).
-- The hotbar has fixed slots (InventoryConfig): one weapon per category (Primary, Magic,
-- Ranged), then the potion slots. The client asks to move items with the InventoryMove
-- remote (name, toHotbar); the server checks the item is theirs. A weapon moved in takes its
-- category's slot, sending whatever was there to storage; a consumable takes a free potion
-- slot, if there is one. The slots live in the player's "Hotbar" attribute (comma-separated,
-- in slot order, empty slots left blank) for the UI, and survive respawns.
-- The first time it sees each weapon it also puts a display copy (parts only: no scripts,
-- sounds, or trails) in ReplicatedStorage.WeaponPreviews, so the backpack can show weapons
-- the player has stored, which live where clients can't see them. It also keeps a whole copy
-- (InventoryService.displayCopy) for things like the Training Grounds' armor stands to hold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local moveRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryMove") :: RemoteEvent

local InventoryService = {}

local hotbars: { [Player]: { string } } = {}

local previews = Instance.new("Folder")
previews.Name = "WeaponPreviews"
previews.Parent = ReplicatedStorage

local displayTemplates: { [string]: Tool } = {} -- never parented, so their scripts don't run

-- A look-only copy of `tool` for the backpack's weapon tiles.
local function addPreview(tool: Tool)
	if previews:FindFirstChild(tool.Name) then
		return
	end
	displayTemplates[tool.Name] = tool:Clone()
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

local function ownsConsumable(player: Player, name: string): boolean
	local data = DataService.data(player)
	return data ~= nil and ShopConfig.consumable(name) ~= nil and (data.Consumables[name] or 0) > 0
end

local function ownsHotbarItem(player: Player, name: string): boolean
	return InventoryService.owns(player, name) or ownsConsumable(player, name)
end

local POTION_START = #InventoryConfig.WeaponSlots + 1

-- Lays `list` out in hotbar slots (each weapon in its category's slot, consumables in the
-- potion slots, in order; "" for an empty slot), skipping what `keep` rejects and anything
-- that doesn't fit. Works on saves from before the slots had categories too (plain lists).
local function arrange(list: { any }, keep: (name: string) -> boolean): { string }
	local hotbar = table.create(InventoryConfig.HotbarSlots, "")
	for _, name in list do
		if typeof(name) ~= "string" or name == "" or table.find(hotbar, name) or not keep(name) then
			continue
		end
		local slot = InventoryConfig.weaponSlot(name)
		if not slot and ShopConfig.consumable(name) then
			slot = table.find(hotbar, "", POTION_START)
		end
		if slot and hotbar[slot] == "" then
			hotbar[slot] = name
		end
	end
	return hotbar
end

local function hotbarOf(player: Player): { string }
	local hotbar = hotbars[player]
	if not hotbar then
		hotbar = arrange(InventoryConfig.DefaultHotbar, function()
			return true
		end)
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

-- A fresh copy of weapon `name` (the whole Tool, scripts and all), or nil until the first one
-- has been handed out (when the first player joins).
function InventoryService.displayCopy(name: string): Tool?
	local template = displayTemplates[name]
	return if template then template:Clone() else nil
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

-- Puts `tool` away into storage (unequipping it first if it's in hand, so its unequip
-- cleanup runs).
local function stash(player: Player, tool: Tool?)
	if not tool then
		return
	end
	local character = player.Character
	if character and tool.Parent == character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end
	tool.Parent = storageOf(player)
end

-- Moves one of the player's weapons/consumables into their hotbar or out. A weapon moved in
-- replaces the one in its category's slot (which goes to storage); a consumable needs a free
-- potion slot. Returns whether the item ends up where asked.
function InventoryService.move(player: Player, name: string, toHotbar: boolean): boolean
	local isWeapon = InventoryConfig.weapon(name) ~= nil
	local isConsumable = ShopConfig.consumable(name) ~= nil
	if not isWeapon and not isConsumable then
		return false
	end
	local tool = if isWeapon then findTool(player, name) else nil
	if isWeapon and not tool then
		return false -- not theirs
	elseif isConsumable and not ownsConsumable(player, name) then
		return false
	end
	local hotbar = hotbarOf(player)
	local index = table.find(hotbar, name)
	if toHotbar and not index then
		local slot = if isWeapon then InventoryConfig.weaponSlot(name) else table.find(hotbar, "", POTION_START)
		if not slot then
			return false -- no potion slot free (or a weapon with no category)
		end
		local replaced = hotbar[slot]
		if replaced ~= "" and InventoryConfig.weapon(replaced) then
			stash(player, findTool(player, replaced))
		end
		hotbar[slot] = name
		if tool then
			tool.Parent = player:FindFirstChildOfClass("Backpack")
		end
	elseif not toHotbar and index then
		hotbar[index] = ""
		stash(player, tool)
	end
	publish(player)
	return true
end

function InventoryService.removeFromHotbar(player: Player, name: string)
	local hotbar = hotbarOf(player)
	local index = table.find(hotbar, name)
	if index then
		hotbar[index] = ""
		publish(player)
	end
end

-- Gives the player weapon `name` to keep (saved), into its hotbar slot if that's empty.
function InventoryService.grant(player: Player, name: string)
	local data = DataService.data(player)
	if not data or not InventoryConfig.weapon(name) or data.Weapons[name] then
		return
	end
	data.Weapons[name] = true
	local hotbar = hotbarOf(player)
	local slot = InventoryConfig.weaponSlot(name)
	if slot and hotbar[slot] == "" then
		hotbar[slot] = name
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

-- Restores a saved hotbar (owned items only, each in its slot; the default if nothing's
-- saved) and moves the player's weapons to match: owned ones out of the parking folder,
-- unowned ones into it.
local function applySaved(player: Player, saved: { string }?)
	local list = if typeof(saved) == "table" then saved else InventoryConfig.DefaultHotbar
	local hotbar = arrange(list, function(name)
		return ownsHotbarItem(player, name)
	end)
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
