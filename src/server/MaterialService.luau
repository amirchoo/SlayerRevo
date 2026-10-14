--!strict
-- Gathered materials (MaterialConfig): counts saved in the player's data, published as the
-- "Materials" attribute ("CowMeat=3,ChickenMeat=1") for the backpack to show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local DataService = require(script.Parent.DataService)

local MaterialService = {}

local function publish(player: Player)
	local data = DataService.data(player)
	local parts: { string } = {}
	if data then
		for _, item in MaterialConfig.Items do
			local count = data.Materials[item.Id] or 0
			if count > 0 then
				table.insert(parts, `{item.Id}={count}`)
			end
		end
	end
	player:SetAttribute("Materials", table.concat(parts, ","))
end

function MaterialService.count(player: Player, itemId: string): number
	local data = DataService.data(player)
	return if data then data.Materials[itemId] or 0 else 0
end

-- Gives the player `amount` of a material. Returns whether it was given (false while their
-- data is still loading, or for an unknown material).
function MaterialService.grant(player: Player, itemId: string, amount: number): boolean
	local data = DataService.data(player)
	if not data or not MaterialConfig.item(itemId) or not (amount > 0) then
		return false
	end
	data.Materials[itemId] = (data.Materials[itemId] or 0) + math.floor(amount)
	publish(player)
	return true
end

-- Takes up to `amount` of a material from the player; returns how many were taken.
function MaterialService.take(player: Player, itemId: string, amount: number): number
	local data = DataService.data(player)
	local have = if data then data.Materials[itemId] or 0 else 0
	local taken = math.min(have, math.max(0, math.floor(amount)))
	if data and taken > 0 then
		data.Materials[itemId] = if have - taken > 0 then have - taken else nil
		publish(player)
	end
	return taken
end

function MaterialService.start()
	DataService.onLoaded(function(player)
		publish(player)
	end)
	Players.PlayerAdded:Connect(publish)
	for _, player in Players:GetPlayers() do
		publish(player)
	end
end

return MaterialService
