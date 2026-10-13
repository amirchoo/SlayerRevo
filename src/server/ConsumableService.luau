--!strict
-- Persisted consumable inventory. Shops grant counts; players use items later from Backpack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local ManaService = require(script.Parent.ManaService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local useRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ConsumableUse") :: RemoteEvent

local ConsumableService = {}

local function serialize(counts: { [string]: number }): string
	local parts: { string } = {}
	for _, item in ShopConfig.Items do
		if ShopConfig.consumable(item.Id) then
			local count = counts[item.Id] or 0
			if count > 0 then
				table.insert(parts, `{item.Id}={count}`)
			end
		end
	end
	return table.concat(parts, ",")
end

local function publish(player: Player)
	local data = DataService.data(player)
	player:SetAttribute("Consumables", if data then serialize(data.Consumables) else "")
end

function ConsumableService.count(player: Player, itemId: string): number
	local data = DataService.data(player)
	return if data then data.Consumables[itemId] or 0 else 0
end

function ConsumableService.grant(player: Player, itemId: string, amount: number)
	local data = DataService.data(player)
	if not data or not ShopConfig.consumable(itemId) or amount <= 0 then
		return
	end
	data.Consumables[itemId] = math.max(0, (data.Consumables[itemId] or 0) + math.floor(amount))
	publish(player)
end

local function apply(player: Player, item: ShopConfig.Item): boolean
	local used = false
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return false
	end
	if item.Heal and character then
		used = HealthService.heal(character, item.Heal) > 0 or used
	end
	if item.ManaPercent then
		local maxMana = player:GetAttribute("MaxMana")
		if typeof(maxMana) == "number" then
			used = ManaService.restore(player, maxMana * item.ManaPercent) > 0 or used
		end
	end
	return used
end

function ConsumableService.use(player: Player, itemId: string): boolean
	local data = DataService.data(player)
	local item = ShopConfig.consumable(itemId)
	if not data or not item or (data.Consumables[itemId] or 0) <= 0 then
		return false
	end
	if not apply(player, item) then
		return false
	end
	data.Consumables[itemId] -= 1
	if data.Consumables[itemId] <= 0 then
		data.Consumables[itemId] = nil
		InventoryService.removeFromHotbar(player, itemId)
	end
	publish(player)
	return true
end

local function onUse(player: Player, itemId: unknown)
	if typeof(itemId) == "string" then
		ConsumableService.use(player, itemId)
	end
end

function ConsumableService.start()
	DataService.onLoaded(function(player)
		publish(player)
	end)
	Players.PlayerAdded:Connect(publish)
	for _, player in Players:GetPlayers() do
		publish(player)
	end
	RemoteGuard.connect(useRemote, onUse)
end

return ConsumableService
