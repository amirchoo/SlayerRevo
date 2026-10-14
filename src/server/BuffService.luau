--!strict
-- Timed buffs on players (BuffConfig). A buff is on while its "Buff<Id>" player attribute
-- (when it ends, in workspace:GetServerTimeNow() seconds) is in the future; the client shows
-- them from that (BuffDisplay). Expired ones are cleared. Damage-taken buffs are applied as a
-- damage filter, so they work on every hit a player takes (after armor and blocking).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffConfig = require(ReplicatedStorage.Shared.Config.BuffConfig)
local HealthService = require(script.Parent.HealthService)

local SWEEP_INTERVAL = 1 -- seconds between clearing expired buffs

local BuffService = {}

-- Gives `player` the buff (or restarts its timer if they have it).
function BuffService.grant(player: Player, id: string)
	local buff = BuffConfig.Buffs[id]
	if not buff then
		warn(`[BuffService] no buff "{id}"`)
		return
	end
	player:SetAttribute(BuffConfig.attribute(id), workspace:GetServerTimeNow() + buff.Duration)
end

function BuffService.has(player: Player, id: string): boolean
	local ends = player:GetAttribute(BuffConfig.attribute(id))
	return typeof(ends) == "number" and ends > workspace:GetServerTimeNow()
end

-- All of the player's buffs multiplied together for `stat` (e.g. "DamageTaken"), 1 if none.
local function multiplier(player: Player, stat: "DamageTaken"): number
	local total = 1
	for id, buff in BuffConfig.Buffs do
		local value = buff[stat]
		if value and BuffService.has(player, id) then
			total *= value
		end
	end
	return total
end

function BuffService.start()
	HealthService.addDamageFilter(function(target: Model, amount: number): number
		local player = Players:GetPlayerFromCharacter(target)
		return if player then amount * multiplier(player, "DamageTaken") else amount
	end)
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				for id in BuffConfig.Buffs do
					local attribute = BuffConfig.attribute(id)
					local ends = player:GetAttribute(attribute)
					if typeof(ends) == "number" and ends <= now then
						player:SetAttribute(attribute, nil)
					end
				end
			end
			task.wait(SWEEP_INTERVAL)
		end
	end)
end

return BuffService
