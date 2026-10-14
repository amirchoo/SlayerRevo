--!strict
-- Shop stock by NPC. Weapons and armor are permanent; consumables are saved and used later.

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
	Price: number,
}

local BASIC_WEAPON_PRICE = 200
local ARMOR_PRICE = 250

local ShopConfig = {}

ShopConfig.BasicWeaponPrice = BASIC_WEAPON_PRICE
ShopConfig.ArmorPrice = ARMOR_PRICE
ShopConfig.MerchantNpc = "Merchant"
ShopConfig.WeaponSellerNpc = "Blacksmith"
ShopConfig.ArmorSellerNpc = "Armorer"
ShopConfig.ConsumableCategory = "Consumeables"
ShopConfig.ArmorCategory = "Armor"

ShopConfig.Shops = {
	Merchant = { Title = "Merchant Shop", Subtitle = "Potions and supplies for the hunt.", Icon = "Backpack" },
	Blacksmith = { Title = "Blacksmith", Subtitle = "Weapons for every fighting style.", Icon = "Swords" },
	Armorer = { Title = "Armorer", Subtitle = "Armor sets. Each set costs 250 coins.", Icon = "Shield" },
} :: { [string]: { Title: string, Subtitle: string, Icon: string } }

ShopConfig.Items = {} :: { Item }

for _, info in InventoryConfig.Weapons do
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

function ShopConfig.shop(sellerId: string): { Title: string, Subtitle: string, Icon: string }?
	return ShopConfig.Shops[sellerId]
end

return ShopConfig
