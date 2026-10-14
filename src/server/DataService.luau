--!strict
-- Saves each player's progress in a DataStore: level, XP, skill trees, owned weapons, the
-- starter pick, hotbar, armor, shield, and materials.
-- Session-locked: while a server has a player's data loaded it marks the save as its own, so
-- a second server (e.g. after a quick rejoin) waits instead of loading stale data and
-- overwriting newer progress later. A lock older than LOCK_TIMEOUT is assumed abandoned
-- (a crashed server) and taken over.
-- Other services read and change the player's data table in place (DataService.data) and
-- register with onLoaded to apply it once it arrives; it's saved every AUTOSAVE_INTERVAL,
-- when the player leaves, and when the server shuts down.
-- If DataStores aren't available (e.g. Studio without API access), data lives in memory
-- only, with a warning.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyConfig = require(ReplicatedStorage.Shared.Config.CurrencyConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_TIMEOUT = 600 -- seconds before another server's lock counts as abandoned
local LOAD_ATTEMPTS = 6

export type Data = {
	Level: number,
	XP: number,
	Coins: number,
	Skills: { [string]: { [string]: number } },
	Weapons: { [string]: boolean }, -- owned weapons (by tool name)
	Consumables: { [string]: number },
	Materials: { [string]: number }, -- gathered materials (MaterialConfig), by Id
	Starter: string?, -- the starter weapon picked (once per save)
	Hotbar: { string }?,
	Armor: { Owned: { [string]: boolean }, Worn: { [string]: string } }?,
	Shield: { Owned: { [string]: boolean }, Worn: string? }?,
}

local DataService = {}

local profiles: { [Player]: Data } = {}
local waiting: { [Player]: { thread } } = {}
local loadedCallbacks: { (Player, Data) -> () } = {}
local store: DataStore? = nil

local function defaults(): Data
	return { Level = 1, XP = 0, Coins = CurrencyConfig.StartingCoins, Skills = {}, Weapons = {}, Consumables = {}, Materials = {} }
end

-- Fills in anything missing (e.g. from an older save).
local function reconcile(raw: any): Data
	local data = defaults()
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.Level) == "number" then
		data.Level = math.max(1, math.floor(raw.Level))
	end
	if typeof(raw.XP) == "number" then
		data.XP = math.max(0, raw.XP)
	end
	if typeof(raw.Coins) == "number" then
		data.Coins = math.max(0, math.floor(raw.Coins))
	end
	if typeof(raw.Skills) == "table" then
		data.Skills = raw.Skills
	end
	if typeof(raw.Weapons) == "table" then
		data.Weapons = raw.Weapons
	elseif typeof(raw.Level) == "number" then
		-- A save from before weapons were owned: everyone had every weapon, so they keep them.
		for _, info in InventoryConfig.Weapons do
			data.Weapons[info.Name] = true
		end
	end
	if typeof(raw.Consumables) == "table" then
		for id, count in raw.Consumables do
			if typeof(id) == "string" and typeof(count) == "number" and count > 0 then
				data.Consumables[id] = math.floor(count)
			end
		end
	end
	if typeof(raw.Materials) == "table" then
		for id, count in raw.Materials do
			if typeof(id) == "string" and typeof(count) == "number" and count > 0 then
				data.Materials[id] = math.floor(count)
			end
		end
	end
	if typeof(raw.Starter) == "string" then
		data.Starter = raw.Starter
	end
	if typeof(raw.Hotbar) == "table" then
		data.Hotbar = raw.Hotbar
	end
	if typeof(raw.Armor) == "table" then
		data.Armor = raw.Armor
	end
	if typeof(raw.Shield) == "table" then
		data.Shield = raw.Shield
	end
	return data
end

local function keyOf(player: Player): string
	return `player_{player.UserId}`
end

-- Loads the player's data and takes the session lock. Returns nil if it never got the lock.
local function load(player: Player): Data?
	local activeStore = store
	if not activeStore then
		return defaults()
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local stealing = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			return activeStore:UpdateAsync(keyOf(player), function(old: any)
				local saved = if typeof(old) == "table" then old else {}
				local lock = saved._lock
				if typeof(lock) == "table" and lock.job ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT and not stealing then
					lockedElsewhere = true
					return nil -- leave it alone; try again shortly
				end
				saved._lock = { job = game.JobId, time = os.time() }
				return saved
			end)
		end)
		if ok and not lockedElsewhere then
			if stealing and attempt > 1 then
				warn(`[DataService] Took over {player.Name}'s save from another server`)
			end
			return reconcile(result)
		elseif not ok then
			warn(`[DataService] Loading {player.Name} failed (attempt {attempt}): {result}`)
		end
		task.wait(attempt * 2)
	end
	return nil
end

-- Writes the player's data; `release` also gives up the session lock (when they leave).
local function save(player: Player, release: boolean)
	local data = profiles[player]
	local activeStore = store
	if not data or not activeStore then
		return
	end
	local ok, err = pcall(function()
		activeStore:UpdateAsync(keyOf(player), function(old: any)
			local lock = if typeof(old) == "table" then old._lock else nil
			if typeof(lock) == "table" and lock.job ~= game.JobId then
				return nil -- another server took over; don't overwrite its newer data
			end
			local saved: any = table.clone(data)
			saved._lock = if release then nil else { job = game.JobId, time = os.time() }
			return saved
		end)
	end)
	if not ok then
		warn(`[DataService] Saving {player.Name} failed: {err}`)
	end
end

-- The player's loaded data, or nil while it's still loading. Change it in place; it's saved.
function DataService.data(player: Player): Data?
	return profiles[player]
end

-- Waits until the player's data is loaded (nil if they left first).
function DataService.get(player: Player): Data?
	if profiles[player] then
		return profiles[player]
	end
	if not player.Parent then
		return nil
	end
	local list = waiting[player] or {}
	waiting[player] = list
	table.insert(list, coroutine.running())
	return coroutine.yield()
end

-- Calls `callback(player, data)` for each player once their data is loaded (including
-- players already loaded when this is called).
function DataService.onLoaded(callback: (Player, Data) -> ())
	table.insert(loadedCallbacks, callback)
	for player, data in profiles do
		task.spawn(callback, player, data)
	end
end

local function resume(player: Player, data: Data?)
	local list = waiting[player]
	waiting[player] = nil
	if list then
		for _, thread in list do
			task.spawn(thread, data)
		end
	end
end

function DataService.start()
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		-- In Studio, a store can be created but every request fails without API access.
		local probe = pcall(function()
			(result :: DataStore):GetAsync("probe")
		end)
		if probe then
			store = result
		end
	end
	if not store then
		warn("[DataService] DataStores unavailable: progress won't be saved. In Studio: Game Settings > Security > Enable Studio Access to API Services.")
	end

	local function onPlayerAdded(player: Player)
		local data = load(player)
		if not player.Parent then
			return -- left while loading (the lock times out on its own)
		end
		if not data then
			player:Kick("Couldn't load your save. Please rejoin in a minute.")
			return
		end
		profiles[player] = data
		resume(player, data)
		for _, callback in loadedCallbacks do
			task.spawn(callback, player, data)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
		resume(player, nil)
	end)
	game:BindToClose(function()
		-- Save everyone at once, then wait for them all (Roblox allows up to 30 s).
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)
end

return DataService
