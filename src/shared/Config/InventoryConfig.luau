--!strict
-- Weapons and the backpack, shared by the server (InventoryService: what's in the hotbar)
-- and the client (Backpack UI). Every weapon a player owns is either in their hotbar (the
-- Roblox Backpack, so it can be equipped) or stored in their backpack.

export type WeaponInfo = {
	Name: string, -- the tool's name (its ToolName)
	Class: string, -- one of Classes' Id
	Description: string,
}

local InventoryConfig = {}

InventoryConfig.OpenKey = Enum.KeyCode.B -- (the armor key, ArmorConfig.PanelKey, opens it too)
InventoryConfig.HotbarSlots = 5 -- weapons the hotbar holds; the rest are stored

-- Weapon classes, in the order the backpack lists them.
InventoryConfig.Classes = {
	{ Id = "Swords", Icon = "⚔️" },
	{ Id = "Axes", Icon = "🪓" },
	{ Id = "Blunt", Icon = "🔨" },
	{ Id = "Polearms", Icon = "🔱" },
	{ Id = "Ranged", Icon = "🏹" },
}

InventoryConfig.Weapons = {
	{ Name = "Sword", Class = "Swords", Description = "Quick 3-hit combo. Hold to spin." },
	{ Name = "Greatsword", Class = "Swords", Description = "Wide sweeps. Hold to charge a slam." },
	{ Name = "Axe", Class = "Axes", Description = "Hard chops. Hold for a leaping cleave that bleeds." },
	{ Name = "Mace", Class = "Blunt", Description = "Heavy hits that stun. Hold for a ground pound." },
	{ Name = "Spear", Class = "Polearms", Description = "Long reach. Hold for a piercing lunge." },
	{ Name = "Bow", Class = "Ranged", Description = "Hold right-click to draw, release to fire." },
} :: { WeaponInfo }

-- What a new player's hotbar holds (in order); everything else starts stored.
InventoryConfig.DefaultHotbar = { "Sword", "Axe", "Mace", "Spear", "Bow" }

function InventoryConfig.weapon(name: string): WeaponInfo?
	for _, info in InventoryConfig.Weapons do
		if info.Name == name then
			return info
		end
	end
	return nil
end

return InventoryConfig
