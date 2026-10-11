--!strict
-- Owns every player's stamina. Attacks call spend() before they happen and are refused if
-- it returns false. Stamina refills at RegenPerSecond once the player has gone RegenDelay
-- seconds without spending, but not during a heavy attack (the "HeavyAttacking" attribute).
-- The value lives in the player's "Stamina"/"MaxStamina" attributes so the HUD can read it,
-- and is topped up on every respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

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

local function refill(player: Player)
	player:SetAttribute("MaxStamina", STAMINA.Max)
	player:SetAttribute("Stamina", STAMINA.Max)
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
				if typeof(current) == "number" and current < STAMINA.Max and resting and player:GetAttribute("HeavyAttacking") ~= true then
					player:SetAttribute("Stamina", math.min(current + STAMINA.RegenPerSecond * REGEN_INTERVAL, STAMINA.Max))
				end
			end
			task.wait(REGEN_INTERVAL)
		end
	end)
end

return StaminaService
