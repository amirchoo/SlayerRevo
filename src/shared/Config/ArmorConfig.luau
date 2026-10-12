--!strict
-- Armor sets, shared by the server (protection, visuals) and client (backpack, HUD).
-- Each worn piece negates a fraction of incoming damage; pieces add up (capped at
-- MaxProtection). A 0.12 chestplate turns a 50 damage hit into 44.

export type ArmorSet = {
	Name: string,
	Color: Color3, -- the plates
	TrimColor: Color3, -- straps, belt, crest
	Material: Enum.Material,
	Rarity: string?, -- one of InventoryConfig.Rarities' Id; nil = "Common"
	StarterFor: string?, -- the weapon this is the starter set of (a label for now: not given out automatically)
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
	Leather = {
		Name = "Leather",
		Color = Color3.fromRGB(110, 62, 34),
		TrimColor = Color3.fromRGB(45, 25, 15),
		Material = Enum.Material.Fabric,
		Rarity = "Uncommon",
		StarterFor = "Sword",
		Pieces = {
			Helmet = 0.04,
			Chestplate = 0.07,
			Armwear = 0.03,
			Leggings = 0.04,
			Boots = 0.02,
		}, -- 20% with the full set (the lowest protection tier)
	},
	Warhide = {
		Name = "Warhide",
		Color = Color3.fromRGB(140, 115, 88),
		TrimColor = Color3.fromRGB(60, 35, 20),
		Material = Enum.Material.Fabric,
		Rarity = "Uncommon",
		StarterFor = "Greatsword",
		Pieces = {
			Helmet = 0.04,
			Chestplate = 0.09,
			Armwear = 0.03,
			Leggings = 0.05,
			Boots = 0.03,
		}, -- 24% with the full set: heavier than Leather, for the slower Greatsword
	},
	Woodcutter = {
		Name = "Woodcutter",
		Color = Color3.fromRGB(120, 85, 60),
		TrimColor = Color3.fromRGB(130, 45, 35),
		Material = Enum.Material.Fabric,
		Rarity = "Uncommon",
		StarterFor = "Axe",
		Pieces = { -- placeholder numbers, to tune
			Helmet = 0.04,
			Chestplate = 0.08,
			Armwear = 0.03,
			Leggings = 0.04,
			Boots = 0.03,
		}, -- 22% with the full set
	},
	Warden = {
		Name = "Warden",
		Color = Color3.fromRGB(190, 175, 145),
		TrimColor = Color3.fromRGB(70, 80, 95),
		Material = Enum.Material.Fabric,
		Rarity = "Uncommon",
		StarterFor = "Mace",
		Pieces = { -- placeholder numbers, to tune
			Helmet = 0.05,
			Chestplate = 0.09,
			Armwear = 0.03,
			Leggings = 0.05,
			Boots = 0.03,
		}, -- 25% with the full set
	},
} :: { [string]: ArmorSet }

-- Set ids in a fixed order (by name), e.g. for cycling through owned sets in the backpack.
ArmorConfig.SetOrder = {} :: { string }
for setId in ArmorConfig.Sets do
	table.insert(ArmorConfig.SetOrder, setId)
end
table.sort(ArmorConfig.SetOrder)

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
