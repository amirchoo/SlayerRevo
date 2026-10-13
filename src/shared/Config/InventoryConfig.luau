--!strict
-- Weapons and the backpack, shared by the server (InventoryService: what's in the hotbar)
-- and the client (Backpack UI). Every weapon a player owns is either in their hotbar (the
-- Roblox Backpack, so it can be equipped) or stored in their backpack.

export type WeaponInfo = {
	Name: string, -- the tool's name (its ToolName)
	Class: string, -- one of Classes' Id
	Description: string,
	Rarity: string?, -- one of Rarities' Id; nil = "Common"
}

export type Rarity = { Id: string, Color: Color3 }

local InventoryConfig = {}

InventoryConfig.OpenKey = Enum.KeyCode.B -- (the armor key, ArmorConfig.PanelKey, opens it too)
InventoryConfig.HotbarSlots = 5 -- weapons the hotbar holds; the rest are stored

-- Rarity tiers, lowest first. The color tints a weapon's name and outline in the hotbar and
-- backpack. (Loot will roll these once drops exist; for now each weapon has a fixed one.)
InventoryConfig.Rarities = {
	{ Id = "Common", Color = Color3.fromRGB(215, 215, 220) },
	{ Id = "Uncommon", Color = Color3.fromRGB(100, 220, 110) },
	{ Id = "Rare", Color = Color3.fromRGB(80, 160, 255) },
	{ Id = "Epic", Color = Color3.fromRGB(190, 100, 255) },
	{ Id = "Legendary", Color = Color3.fromRGB(255, 175, 50) },
} :: { Rarity }

-- Weapon classes, in the order the backpack lists them.
InventoryConfig.Classes = {
	{ Id = "Swords", Icon = "Swords" },
	{ Id = "Axes", Icon = "Axes" },
	{ Id = "Blunt", Icon = "Blunt" },
	{ Id = "Polearms", Icon = "Polearms" },
	{ Id = "Ranged", Icon = "Ranged" },
	{ Id = "Magic", Icon = "Magic" },
}

InventoryConfig.Weapons = {
	{ Name = "Sword", Class = "Swords", Description = "Quick 3-hit combo. Hold to spin." },
	{ Name = "Emberfang", Class = "Swords", Rarity = "Epic", Description = "A slayer's blade: the sword's moves, hitting harder. Shares the Sword skill tree." },
	{ Name = "Rapier", Class = "Swords", Description = "Elegant, quick thrusts with long reach. Hold to unleash a flurry of stabs." },
	{ Name = "Greatsword", Class = "Swords", Description = "Wide sweeps. Hold to charge a slam." },
	{ Name = "Axe", Class = "Axes", Description = "Hard chops. Hold for a leaping cleave that bleeds." },
	{ Name = "Mace", Class = "Blunt", Description = "Heavy hits that stun. Hold for a ground pound." },
	{ Name = "Spear", Class = "Polearms", Description = "Long reach. Hold for a piercing lunge." },
	{ Name = "Bow", Class = "Ranged", Description = "Hold right-click to draw, release to fire." },
	{ Name = "Staff", Class = "Magic", Description = "Elemental missiles; hold to charge a blast. R switches element." },
	{ Name = "Grimoire", Class = "Magic", Description = "Necromancy and Faith: undead hands, homing swarms, and healing. R switches school." },
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

-- A rarity tier by its Id (Common if there's no such tier).
function InventoryConfig.rarityById(id: string?): Rarity
	for _, rarity in InventoryConfig.Rarities do
		if rarity.Id == id then
			return rarity
		end
	end
	return InventoryConfig.Rarities[1]
end

-- A weapon's rarity tier (Common if it has none, or isn't a known weapon).
function InventoryConfig.rarity(name: string): Rarity
	local info = InventoryConfig.weapon(name)
	return InventoryConfig.rarityById(info and info.Rarity)
end

return InventoryConfig
