--!strict
-- Owns every player's mana, which the staff's spells spend (StaffService). Like stamina:
-- spend() before casting (false = not enough, the cast is refused); it refills at
-- RegenPerSecond once the player has gone RegenDelay seconds without spending, but not while
-- charging (the "HeavyAttacking" attribute). Max and regen grow with the Arcana skills.
-- Lives in the player's "Mana"/"MaxMana" attributes for the HUD; full again on respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)

local MANA = CombatConfig.Mana
local REGEN_INTERVAL = 0.1

local ManaService = {}

local lastSpent: { [Player]: number } = {}

local function maxOf(player: Player): number
	return MANA.Max + SkillMath.general(player, "MaxMana")
end

-- Takes `cost` mana if the player has that much and returns true; otherwise false.
function ManaService.spend(player: Player, cost: number): boolean
	local current = player:GetAttribute("Mana")
	if typeof(current) ~= "number" or current < cost then
		return false
	end
	player:SetAttribute("Mana", current - cost)
	lastSpent[player] = os.clock()
	return true
end

-- Restores up to `amount` mana. Returns the amount actually restored.
function ManaService.restore(player: Player, amount: number): number
	local current = player:GetAttribute("Mana")
	local max = player:GetAttribute("MaxMana")
	if typeof(current) ~= "number" or typeof(max) ~= "number" or not (amount > 0) then
		return 0
	end
	local restored = math.min(amount, max - current)
	player:SetAttribute("Mana", current + restored)
	return restored
end

local function refill(player: Player)
	player:SetAttribute("MaxMana", maxOf(player))
	player:SetAttribute("Mana", maxOf(player))
end

-- Re-applies max mana after the player's skills change.
function ManaService.refreshMax(player: Player)
	local max = maxOf(player)
	player:SetAttribute("MaxMana", max)
	local current = player:GetAttribute("Mana")
	if typeof(current) == "number" and current > max then
		player:SetAttribute("Mana", max)
	end
end

function ManaService.start()
	local function onPlayerAdded(player: Player)
		refill(player)
		player.CharacterAdded:Connect(function()
			refill(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSpent[player] = nil
	end)

	task.spawn(function()
		while true do
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local current = player:GetAttribute("Mana")
				local max = maxOf(player)
				local resting = now - (lastSpent[player] or 0) >= MANA.RegenDelay
				if typeof(current) == "number" and current < max and resting and player:GetAttribute("HeavyAttacking") ~= true then
					local regen = MANA.RegenPerSecond + SkillMath.general(player, "ManaRegen")
					player:SetAttribute("Mana", math.min(current + regen * REGEN_INTERVAL, max))
				end
			end
			task.wait(REGEN_INTERVAL)
		end
	end)
end

return ManaService
