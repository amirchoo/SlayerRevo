--!strict
-- Server-authoritative coin currency system.
-- Coins are saved in the player's data (DataService) and published as the "Coins" attribute
-- for clients and HUDs (Backpack UI, shops, etc.) to read.
-- Defeating an enemy gives the killer its coin reward (the enemy's "CoinReward" attribute,
-- from EnemyConfig), and notifies the client via the CoinGained remote event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyConfig = require(ReplicatedStorage.Shared.Config.CurrencyConfig)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local coinGainedRemote = remotes:WaitForChild("CoinGained") :: RemoteEvent

local CurrencyService = {}

local function publish(player: Player, coins: number)
	player:SetAttribute("Coins", math.max(0, math.floor(coins)))
end

-- Returns the player's current coin balance (0 if not loaded).
function CurrencyService.get(player: Player): number
	local data = DataService.data(player)
	return if data then data.Coins else 0
end

-- Checks if a player can afford `amount` coins.
function CurrencyService.canAfford(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	return CurrencyService.get(player) >= amount
end

-- Adds `amount` coins to the player's balance.
function CurrencyService.add(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = DataService.data(player)
	if not data then
		return
	end
	data.Coins = math.max(0, math.floor(data.Coins + amount))
	publish(player, data.Coins)
end

-- Spends `amount` coins if the player can afford it. Returns true on success, false otherwise.
function CurrencyService.spend(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end
	if amount == 0 then
		return true
	end
	local data = DataService.data(player)
	if not data or data.Coins < amount then
		return false
	end
	data.Coins = math.max(0, math.floor(data.Coins - amount))
	publish(player, data.Coins)
	return true
end

function CurrencyService.start()
	DataService.onLoaded(function(player, data)
		publish(player, data.Coins)
	end)

	HealthService.Died:Connect(function(model: Model, killer: Player?)
		local reward = model:GetAttribute("CoinReward")
		if killer and typeof(reward) == "number" and reward > 0 and not Players:GetPlayerFromCharacter(model) then
			CurrencyService.add(killer, reward)
			local boxCFrame, size = model:GetBoundingBox()
			local popupPos = boxCFrame.Position + Vector3.new(0, size.Y / 2 + 2, 0)
			coinGainedRemote:FireClient(killer, popupPos, reward)
		end
	end)
end

return CurrencyService
