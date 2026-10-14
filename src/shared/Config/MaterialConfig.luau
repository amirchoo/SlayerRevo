--!strict
-- Materials: items gathered in the world (dropped by animals and, later, monsters), kept in
-- the backpack's Materials tab and saved. Nothing uses them yet (cooking comes later).
-- Also the tuning for loot on the ground (LootService, LootClient).

export type Material = {
	Id: string,
	Name: string,
	Description: string,
	Model: string, -- a model in ReplicatedStorage.ItemModels (assets/items): its tile, and how it looks on the ground
	Icon: string?, -- shown if the Model is missing
}

local MaterialConfig = {}

MaterialConfig.Items = {
	{ Id = "CowMeat", Name = "Cow Meat", Description = "A raw cut of beef.", Model = "CowMeat", Icon = "Backpack" },
	{ Id = "ChickenMeat", Name = "Chicken Meat", Description = "A raw drumstick.", Model = "ChickenMeat", Icon = "Backpack" },
} :: { Material }

MaterialConfig.Category = "Materials" -- the backpack tab

-- Loot on the ground. Only the player who earned it sees it or can pick it up.
MaterialConfig.Loot = {
	PickupRange = 7, -- studs: walk this close and it's yours
	Lifetime = 120, -- seconds before uncollected loot vanishes
	FloatHeight = 1.6, -- studs above the ground it hovers at
	Size = 1.6, -- studs across a dropped item is drawn (its model is scaled to fit)
	Scatter = 3, -- studs drops land from where the animal fell
	PickupDelay = 0.6, -- seconds after dropping before it can be picked up (lets it land)
}

function MaterialConfig.item(id: string): Material?
	for _, item in MaterialConfig.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return MaterialConfig
