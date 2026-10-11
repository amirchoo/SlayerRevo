--!strict
-- Client-side stamina check. The server owns the real value (see StaminaService) and
-- refuses attacks you can't afford; clients check first so they don't play an attack the
-- server will refuse. A failed check fires NotEnough, which the stamina bar flashes on.

local Stamina = {}

local notEnough = Instance.new("BindableEvent")
Stamina.NotEnough = notEnough.Event

-- True if `player` has at least `cost` stamina (or the server hasn't set it yet, in which
-- case the server decides).
function Stamina.canAfford(player: Player, cost: number): boolean
	local current = player:GetAttribute("Stamina")
	if typeof(current) ~= "number" or current >= cost then
		return true
	end
	notEnough:Fire()
	return false
end

return Stamina
