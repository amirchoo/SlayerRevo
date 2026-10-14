--!strict
-- Townsfolk in Beginning Town: where each stands, how they look, and what they say.
-- NpcService (server) spawns them with a "Talk" prompt; Dialogue (client) shows their lines.
-- Positions are X/Z on the ground; Facing is the direction they look.
-- Action "StarterPick": after their lines, a player who hasn't picked a starter weapon is
-- offered the choice (see shared/Starter); ChosenLines replace Lines once they have.

export type Npc = {
	Id: string,
	Name: string,
	Title: string,
	Position: Vector2,
	Facing: Vector2,
	Shirt: Color3,
	Pants: Color3,
	Lines: { string },
	ChosenLines: { string }?,
	Action: string?,
}

local NpcConfig = {}

NpcConfig.TalkDistance = 10 -- studs from an NPC its Talk prompt shows
NpcConfig.CloseDistance = 18 -- the dialogue closes when you walk this far away
NpcConfig.TypeSpeed = 60 -- characters per second as a line types out

NpcConfig.List = {
	{
		Id = "Guide",
		Name = "Elder Maren",
		Title = "Town Guide",
		Position = Vector2.new(9, 13),
		Facing = Vector2.new(-1, 0.4),
		Shirt = Color3.fromRGB(90, 110, 80),
		Pants = Color3.fromRGB(70, 55, 40),
		Lines = {
			"Welcome to Beginning Town, traveler. Every slayer's road starts here.",
			"Beyond the north arch lie the hunting grounds. Monsters there won't wait for you to be ready.",
			"No one walks out that gate empty-handed. Choose the weapon you'll learn first, and the armor that goes with it.",
		},
		ChosenLines = {
			"That weapon suits you. Learn its rhythm before you learn its strength.",
			"The Training Grounds pad beside the spawn will take you to dummies and sparring partners.",
			"When you're ready, the north arch leads to the hunting grounds. Come back alive.",
		},
		Action = "StarterPick",
	},
	{
		Id = "Blacksmith",
		Name = "Bram",
		Title = "Blacksmith",
		Position = Vector2.new(-54, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(60, 60, 65),
		Pants = Color3.fromRGB(50, 40, 30),
		Lines = {
			"Mind the sparks. This forge hasn't gone cold in twenty years.",
			"I've got weapons for every fighting style. Two hundred coins each.",
		},
		Action = "Shop",
	},
	{
		Id = "Armorer",
		Name = "Hilde",
		Title = "Armorer",
		Position = Vector2.new(-93, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(120, 85, 60),
		Pants = Color3.fromRGB(60, 50, 45),
		Lines = {
			"Leather, hide, quilted cloth: every piece you wear turns a little of a blow aside.",
			"Full armor sets are two hundred fifty coins each.",
		},
		Action = "Shop",
	},
	{
		Id = "Innkeeper",
		Name = "Tobin",
		Title = "Innkeeper",
		Position = Vector2.new(54, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(150, 120, 80),
		Pants = Color3.fromRGB(70, 50, 35),
		Lines = {
			"Welcome to the Sleeping Boar! Warm stew, warm beds, and the best stories this side of the forest.",
			"Hunters swap tales here at night. Some of them are even true.",
		},
	},
	{
		Id = "Merchant",
		Name = "Pip",
		Title = "Merchant",
		Position = Vector2.new(52, 10.5),
		Facing = Vector2.new(0, -1),
		Shirt = Color3.fromRGB(90, 140, 70),
		Pants = Color3.fromRGB(60, 50, 40),
		Lines = {
			"The supply cart finally made it through. Nothing fancy yet, but potions keep slayers alive.",
			"Health and Mana potions are stocked and ready.",
		},
		Action = "Shop",
	},
	{
		Id = "GuildClerk",
		Name = "Sera",
		Title = "Guild Clerk",
		Position = Vector2.new(10, 97),
		Facing = Vector2.new(0, -1),
		Shirt = Color3.fromRGB(70, 80, 110),
		Pants = Color3.fromRGB(45, 45, 55),
		Lines = {
			"The Hunters' Guild keeps track of every beast that threatens this town.",
			"The quest board will fill up soon. Until then, the hunting grounds to the north need thinning.",
		},
	},
	{
		Id = "Guard",
		Name = "Fenn",
		Title = "Gate Guard",
		Position = Vector2.new(11, -132),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(110, 115, 125),
		Pants = Color3.fromRGB(55, 55, 60),
		Lines = {
			"Halt. Past this arch you're outside the safe zone; nothing out there cares that you're new.",
			"Orcs roam close to the road. Further in, something worse. Keep your guard up and your stamina higher.",
		},
	},
} :: { Npc }

function NpcConfig.get(id: string): Npc?
	for _, npc in NpcConfig.List do
		if npc.Id == id then
			return npc
		end
	end
	return nil
end

return NpcConfig
