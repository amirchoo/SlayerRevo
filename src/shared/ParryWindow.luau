--!strict
-- How long after raising the guard a hit is parried, for a player holding a weapon: the
-- weapon's ParryWindow (heavier = shorter) plus their skill bonuses. Shared so the server
-- (BlockService, which decides) and the client (ParryPredict, which plays the clang without
-- waiting for it) agree.

local CombatConfig = require(script.Parent.Config.CombatConfig)
local SkillMath = require(script.Parent.SkillMath)

local BASE: { [string]: number } = {
	[CombatConfig.Sword.ToolName] = CombatConfig.Sword.Block.ParryWindow,
	[CombatConfig.Emberfang.ToolName] = CombatConfig.Emberfang.Block.ParryWindow,
	[CombatConfig.Mace.ToolName] = CombatConfig.Mace.Block.ParryWindow,
	[CombatConfig.Spear.ToolName] = CombatConfig.Spear.Block.ParryWindow,
	[CombatConfig.Rapier.ToolName] = CombatConfig.Rapier.Block.ParryWindow,
	[CombatConfig.Dagger.ToolName] = CombatConfig.Dagger.Block.ParryWindow,
	[CombatConfig.Axe.ToolName] = CombatConfig.Axe.Block.ParryWindow,
	[CombatConfig.DualBlade.ToolName] = CombatConfig.DualBlade.Block.ParryWindow,
	[CombatConfig.Scythe.ToolName] = CombatConfig.Scythe.Block.ParryWindow,
	[CombatConfig.Hammer.ToolName] = CombatConfig.Hammer.Block.ParryWindow,
	[CombatConfig.Greatsword.ToolName] = CombatConfig.Greatsword.ParryWindow,
}

local ParryWindow = {}

-- `player`'s parry window with `toolName` in hand, or nil if that weapon can't parry.
function ParryWindow.of(player: Player, toolName: string): number?
	local base = BASE[toolName]
	if not base then
		return nil
	end
	return base + SkillMath.general(player, "ParryWindow") + SkillMath.weapon(player, toolName, "ParryWindow")
end

return ParryWindow
