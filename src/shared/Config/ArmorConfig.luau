--!strict
-- Armor sets, shared by the server (protection, visuals) and client (backpack, HUD).
-- Each worn piece negates a fraction of incoming damage; pieces add up (capped at
-- MaxProtection). A 0.12 chestplate turns a 50 damage hit into 44.

export type ArmorSet = {
	Name: string,
	Color: Color3, -- the plates
	TrimColor: Color3, -- straps, belt, crest
	Material: Enum.Material,
	-- Protection per slot (fraction of damage negated). A set without a slot has no piece for it.
	Pieces: { [string]: number },
}

local ArmorConfig = {}

-- Every armor slot, in the order the backpack lists them.
ArmorConfig.Slots = { "Helmet", "Chestplate", "Armwear", "Leggings", "Boots" }

ArmorConfig.MaxProtection = 0.8 -- no combination of pieces negates more than this

ArmorConfig.PanelKey = Enum.KeyCode.G -- also opens the backpack (where armor is managed)

ArmorConfig.Sets = {
	Iron = {
		Name = "Iron",
		Color = Color3.fromRGB(165, 170, 180),
		TrimColor = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Metal,
		Pieces = {
			Helmet = 0.06,
			Chestplate = 0.12,
			Armwear = 0.05,
			Leggings = 0.08,
			Boots = 0.04,
		}, -- 35% with the full set
	},
} :: { [string]: ArmorSet }

-- The armor stand in the hub: which set it hands out, and where it stands (X/Z; it faces
-- the town center).
ArmorConfig.Stand = {
	Set = "Iron",
	Position = Vector2.new(-8, -26),
}

-- Display name of one piece, e.g. "Iron Helmet".
function ArmorConfig.pieceName(setId: string, slot: string): string
	local set = ArmorConfig.Sets[setId]
	return if set then `{set.Name} {slot}` else slot
end

return ArmorConfig
