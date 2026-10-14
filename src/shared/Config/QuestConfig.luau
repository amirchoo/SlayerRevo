--!strict
-- Quest definitions shared by the server quest tracker and client quest UI.

export type Quest = {
	Id: string,
	Title: string,
	Description: string,
	Targets: { Target },
	TargetPosition: Vector2,
	RewardXP: number,
	RewardCoins: number,
}

export type Target = {
	Kind: "Enemy" | "Animal",
	Id: string,
	Label: string,
	Count: number,
}

local QuestConfig = {}

QuestConfig.Board = {
	Position = Vector2.new(-14, 96), -- outside the Hunters' Guild
	Facing = Vector2.new(0, -1),
}

QuestConfig.Quests = {
	{
		Id = "SlayOrcs5",
		Title = "Cull the Orcs",
		Description = "Slay 5 orcs outside town.",
		Targets = {
			{ Kind = "Enemy", Id = "Orc", Label = "Orcs", Count = 5 },
		},
		TargetPosition = Vector2.new(0, -460),
		RewardXP = 100,
		RewardCoins = 50,
	},
	{
		Id = "HuntFarmAnimals",
		Title = "Stock the Larder",
		Description = "Hunt 1 cow and 3 chickens in the wild.",
		Targets = {
			{ Kind = "Animal", Id = "Cow", Label = "Cow", Count = 1 },
			{ Kind = "Animal", Id = "Chicken", Label = "Chickens", Count = 3 },
		},
		TargetPosition = Vector2.new(330, 180),
		RewardXP = 25,
		RewardCoins = 10,
	},
} :: { Quest }

function QuestConfig.targetKey(target: Target): string
	return `{target.Kind}:{target.Id}`
end

function QuestConfig.totalTarget(quest: Quest): number
	local total = 0
	for _, target in quest.Targets do
		total += target.Count
	end
	return total
end

function QuestConfig.quest(id: string): Quest?
	for _, quest in QuestConfig.Quests do
		if quest.Id == id then
			return quest
		end
	end
	return nil
end

return QuestConfig
