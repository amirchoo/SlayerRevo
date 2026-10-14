--!strict
-- The starter pick: a new player chooses one weapon (once per save) and gets it with its
-- starter armor set. The choices are every armor set with a StarterFor weapon (ArmorConfig),
-- in the order InventoryConfig lists weapons. Shared so the intro and the guide's dialogue
-- (client) and StarterService (server) agree. Each choice has a statue in the Hall of Oaths
-- (IntroConfig.Hall), in a ring in this order.

local ArmorConfig = require(script.Parent.Config.ArmorConfig)
local InventoryConfig = require(script.Parent.Config.InventoryConfig)
local IntroConfig = require(script.Parent.Config.IntroConfig)

export type Choice = { Weapon: string, ArmorSet: string }

local Starter = {}

function Starter.choices(): { Choice }
	local list: { Choice } = {}
	for _, info in InventoryConfig.Weapons do
		for _, setId in ArmorConfig.SetOrder do
			if ArmorConfig.Sets[setId].StarterFor == info.Name then
				table.insert(list, { Weapon = info.Name, ArmorSet = setId })
				break
			end
		end
	end
	return list
end

function Starter.choiceFor(weapon: string): Choice?
	for _, choice in Starter.choices() do
		if choice.Weapon == weapon then
			return choice
		end
	end
	return nil
end

-- Where the `index`th of `count` statues stands in the Hall of Oaths: its feet (on top of
-- its pedestal), facing the middle of the hall.
function Starter.statueFeet(index: number, count: number): CFrame
	local hall = IntroConfig.Hall
	local angle = (index - 1) / math.max(count, 1) * math.pi * 2
	local outward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	local feet = hall.Center + outward * hall.Radius + Vector3.new(0, hall.PedestalHeight, 0)
	return CFrame.lookAt(feet, feet - outward)
end

return Starter
