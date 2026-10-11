--!strict
-- Owns every player's stamina. Attacks call spend() before they happen and are refused if
-- it returns false. Stamina refills at RegenPerSecond once the player has gone RegenDelay
-- seconds without spending, but not during a heavy attack (the "HeavyAttacking" attribute).
-- The value lives in the player's "Stamina"/"MaxStamina" attributes so the HUD can read it,
-- and is topped up on every respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)

local STAMINA = CombatConfig.Stamina
local REGEN_INTERVAL = 0.1 -- seconds between regen updates (the bar tweens between them)

local StaminaService = {}

local lastSpent: { [Player]: number } = {}

-- Takes `cost` stamina if the player has that much and returns true; otherwise takes
-- nothing and returns false.
function StaminaService.spend(player: Player, cost: number): boolean
	local current = player:GetAttribute("Stamina")
	if typeof(current) ~= "number" or current < cost then
		return false
	end
	player:SetAttribute("Stamina", current - cost)
	lastSpent[player] = os.clock()
	return true
end

-- Max stamina and regen, with the player's skill bonuses (see SkillTrees).
local function maxOf(player: Player): number
	return STAMINA.Max + SkillMath.general(player, "MaxStamina")
end

local function refill(player: Player)
	player:SetAttribute("MaxStamina", maxOf(player))
	player:SetAttribute("Stamina", maxOf(player))
end

-- Re-applies max stamina after the player's skills change.
function StaminaService.refreshMax(player: Player)
	local max = maxOf(player)
	player:SetAttribute("MaxStamina", max)
	local current = player:GetAttribute("Stamina")
	if typeof(current) == "number" and current > max then
		player:SetAttribute("Stamina", max)
	end
end

function StaminaService.start()
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
				local current = player:GetAttribute("Stamina")
				local resting = now - (lastSpent[player] or 0) >= STAMINA.RegenDelay
				local max = maxOf(player)
				if typeof(current) == "number" and current < max and resting and player:GetAttribute("HeavyAttacking") ~= true then
					local regen = STAMINA.RegenPerSecond + SkillMath.general(player, "StaminaRegen")
					player:SetAttribute("Stamina", math.min(current + regen * REGEN_INTERVAL, max))
				end
			end
			task.wait(REGEN_INTERVAL)
		end
	end)
end

return StaminaService
