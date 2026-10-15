--!strict
-- Shop stock by NPC. Weapons and armor are permanent; consumables are saved and used later.
-- The Butcher also buys: an item with a SellPrice can be sold back to its Seller (raw meat,
-- a material: the main way to earn coins for now). Selling always pays less than buying.

local ArmorConfig = require(script.Parent.ArmorConfig)
local InventoryConfig = require(script.Parent.InventoryConfig)

export type Item = {
	Id: string,
	Name: string,
	Category: string,
	Description: string,
	Icon: string?, -- shown when there's no Model (or it hasn't been imported yet)
	Model: string?, -- a model in ReplicatedStorage.ItemModels (assets/items), shown in its tile
	Seller: string, -- the NPC that sells it ("" for things only cooked or found, never sold)
	Weapon: string?,
	ArmorSet: string?,
	Heal: number?,
	EatTime: number?, -- food: Heal is given gradually over this many seconds, not all at once
	ManaPercent: number?,
	Material: string?, -- a material (MaterialConfig) bought one at a time
	Price: number,
	SellPrice: number?, -- the Seller buys it back for this many coins each
}

local BASIC_WEAPON_PRICE = 300 -- every starter (Common) weapon; rarer ones aren't sold
local ARMOR_PRICE = 250

local ShopConfig = {}

ShopConfig.BasicWeaponPrice = BASIC_WEAPON_PRICE
ShopConfig.ArmorPrice = ARMOR_PRICE
ShopConfig.MerchantNpc = "Merchant"
ShopConfig.WeaponSellerNpc = "Blacksmith"
ShopConfig.ArmorSellerNpc = "Armorer"
ShopConfig.ButcherNpc = "Butcher"
ShopConfig.ConsumableCategory = "Consumeables"
ShopConfig.ArmorCategory = "Armor"
ShopConfig.MeatCategory = "Meat"
ShopConfig.SellCategory = "Sell" -- the tab listing what a shop buys back
ShopConfig.MaxSell = 999 -- most of one thing sold in one go

ShopConfig.Shops = {
	Merchant = { Title = "Merchant Shop", Subtitle = "Potions and supplies for the hunt.", Icon = "Backpack" },
	Blacksmith = { Title = "Blacksmith", Subtitle = `Weapons for every fighting style. Each costs {BASIC_WEAPON_PRICE} coins.`, Icon = "Swords" },
	Armorer = { Title = "Armorer", Subtitle = `Armor sets. Each set costs {ARMOR_PRICE} coins.`, Icon = "Shield" },
	Butcher = { Title = "Butcher", Subtitle = "Raw meat, bought and sold. Hunt cows and chickens outside town.", Icon = "Butcher" },
} :: { [string]: { Title: string, Subtitle: string, Icon: string } }

ShopConfig.Items = {} :: { Item }

for _, info in InventoryConfig.Weapons do
	if info.Rarity and info.Rarity ~= InventoryConfig.Rarities[1].Id then
		continue -- only the starter weapons are sold
	end
	table.insert(ShopConfig.Items, {
		Id = info.Name,
		Name = info.Name,
		Category = info.Class,
		Description = info.Description,
		Seller = ShopConfig.WeaponSellerNpc,
		Weapon = info.Name,
		Price = BASIC_WEAPON_PRICE,
	})
end

table.insert(ShopConfig.Items, { Id = "HP Potion", Name = "Health Potion", Category = ShopConfig.ConsumableCategory, Description = "Restores 50 HP when used.", Icon = "Vitality", Model = "HealthPotion", Seller = ShopConfig.MerchantNpc, Heal = 50, Price = 50 })
table.insert(ShopConfig.Items, { Id = "MP Potion", Name = "Mana Potion", Category = ShopConfig.ConsumableCategory, Description = "Restores 30% of max mana when used.", Icon = "Arcana", Model = "ManaPotion", Seller = ShopConfig.MerchantNpc, ManaPercent = 0.3, Price = 30 })

-- Food cooked at the tavern campfire from raw meat (CookingConfig): eaten from a potion slot,
-- it heals over EatTime. Not sold.
table.insert(ShopConfig.Items, { Id = "CookedCowMeat", Name = "Cooked Steak", Category = ShopConfig.ConsumableCategory, Description = "A juicy grilled steak. Restores 70 HP over 3 seconds.", Icon = "Vitality", Model = "CookedCowMeat", Seller = "", Heal = 70, EatTime = 3, Price = 0 })
table.insert(ShopConfig.Items, { Id = "CookedChickenMeat", Name = "Roast Chicken", Category = ShopConfig.ConsumableCategory, Description = "A roasted drumstick. Restores 35 HP over 2 seconds.", Icon = "Vitality", Model = "CookedChickenMeat", Seller = "", Heal = 35, EatTime = 2, Price = 0 })

-- Raw meat at the Butcher (MaterialConfig): bought for more than it sells for.
table.insert(ShopConfig.Items, { Id = "Meat:CowMeat", Name = "Cow Meat", Category = ShopConfig.MeatCategory, Description = "A raw cut of beef. Cook it at the campfire.", Model = "CowMeat", Icon = "Butcher", Seller = ShopConfig.ButcherNpc, Material = "CowMeat", Price = 35, SellPrice = 15 })
table.insert(ShopConfig.Items, { Id = "Meat:ChickenMeat", Name = "Chicken Meat", Category = ShopConfig.MeatCategory, Description = "A raw drumstick. Cook it at the campfire.", Model = "ChickenMeat", Icon = "Butcher", Seller = ShopConfig.ButcherNpc, Material = "ChickenMeat", Price = 15, SellPrice = 6 })

for _, setId in ArmorConfig.SetOrder do
	local set = ArmorConfig.Sets[setId]
	table.insert(ShopConfig.Items, {
		Id = `Armor:{setId}`,
		Name = `{set.Name} Armor`,
		Category = ShopConfig.ArmorCategory,
		Description = "Full armor set.",
		Icon = "Shield",
		Seller = ShopConfig.ArmorSellerNpc,
		ArmorSet = setId,
		Price = ARMOR_PRICE,
	})
end

function ShopConfig.item(id: string): Item?
	for _, item in ShopConfig.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function ShopConfig.consumable(id: string): Item?
	local item = ShopConfig.item(id)
	return if item and (item.Heal or item.ManaPercent) then item else nil
end

-- The item if `sellerId` buys it back.
function ShopConfig.sellable(sellerId: string, id: string): Item?
	local item = ShopConfig.item(id)
	return if item and item.Seller == sellerId and item.SellPrice then item else nil
end

function ShopConfig.shop(sellerId: string): { Title: string, Subtitle: string, Icon: string }?
	return ShopConfig.Shops[sellerId]
end

return ShopConfig
