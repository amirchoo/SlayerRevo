--!strict
-- Timed buffs on players (BuffService grants them; BuffDisplay shows them by the health bar).
-- Each lasts Duration seconds; getting it again while it's on restarts the timer (they
-- don't stack). Kept through death, lost on leaving the game.
-- DamageTaken: multiplies the damage the player takes (0.9 = 10% damage negation), applied
-- after armor and blocking.

export type Buff = {
	Name: string,
	Description: string,
	Icon: string, -- an IconAtlas cell
	Color: Color3,
	Duration: number,
	DamageTaken: number?,
}

local BuffConfig = {}

BuffConfig.Buffs = {
	-- From petting Bonnie, the inn's cat (PetService).
	BonniesGrace = {
		Name = "Bonnie's Grace",
		Description = "10% damage negation",
		Icon = "Sparkles",
		Color = Color3.fromRGB(255, 196, 120),
		Duration = 300,
		DamageTaken = 0.9,
	},
} :: { [string]: Buff }

-- The player attribute holding when a buff ends (workspace:GetServerTimeNow()), if it's on.
function BuffConfig.attribute(id: string): string
	return `Buff{id}`
end

return BuffConfig
