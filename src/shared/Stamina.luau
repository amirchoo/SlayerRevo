--!strict
-- Client-side stamina (and mana) check. The server owns the real values (StaminaService,
-- ManaService) and refuses attacks you can't afford; clients check first so they don't play
-- an attack the server will refuse. A failed check fires NotEnough with the resource that
-- ran short ("Stamina" or "Mana"), which that bar flashes on.

local Stamina = {}

local notEnough = Instance.new("BindableEvent")
Stamina.NotEnough = notEnough.Event

-- True if `player` has at least `cost` stamina (or the server hasn't set it yet, in which
-- case the server decides).
function Stamina.canAfford(player: Player, cost: number, resource: string?): boolean
	local name = resource or "Stamina"
	local current = player:GetAttribute(name)
	if typeof(current) ~= "number" or current >= cost then
		return true
	end
	notEnough:Fire(name)
	return false
end

return Stamina
