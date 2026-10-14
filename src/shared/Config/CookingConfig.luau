--!strict
-- Cooking at the tavern-yard campfire (the one with the pot). Press its prompt and the camera
-- zooms in on the fire while you crouch beside it, and a cooking panel opens (CookingPanel):
-- pick a meat, how many, and Cook. Each piece takes CookTime over the fire, then pops out as
-- food (a consumable in ShopConfig) that heals when eaten from a potion slot.
-- CookingService runs it on the server: the range check, the meat taken and the food given.

export type Recipe = {
	From: string, -- a MaterialConfig item Id (raw)
	To: string, -- a ShopConfig consumable Id (cooked)
}

local CookingConfig = {}

CookingConfig.Recipes = {
	{ From = "CowMeat", To = "CookedCowMeat" },
	{ From = "ChickenMeat", To = "CookedChickenMeat" },
} :: { Recipe }

CookingConfig.CookTime = 1.5 -- seconds each piece takes
CookingConfig.MaxBatch = 20 -- most pieces cooked in one go

-- The campfire (TownConfig's campfire prop, the CookingFire model) and where the cook crouches.
CookingConfig.Station = {
	Position = Vector2.new(83.6, 85.5), -- the fire (X/Z)
	Seat = Vector2.new(82, 90.7), -- where you crouch, facing the fire and its pot (in the widest gap between the tripod's legs)
	Height = 3, -- studs above the ground the prompt sits
	Range = 12, -- studs: how close you must be to use it
}

-- The camera while cooking: from beside and a little in front of you, looking at you and the
-- fire, turned a little so the scene sits left of the cooking panel.
CookingConfig.Camera = {
	Side = 9, -- studs to your right
	Front = 3, -- studs toward the fire from you
	Up = 4.5, -- studs above the ground
	Turn = 16, -- degrees turned right, so the scene shifts left of the panel
	FieldOfView = 55,
	ZoomTime = 0.6, -- seconds to fly in (and back out)
}

function CookingConfig.recipe(toId: string): Recipe?
	for _, recipe in CookingConfig.Recipes do
		if recipe.To == toId then
			return recipe
		end
	end
	return nil
end

return CookingConfig
