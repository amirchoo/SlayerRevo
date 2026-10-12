--!strict
-- The starter pick: a new player chooses one weapon (once per save) and gets it with its
-- starter armor set. The choices are every armor set with a StarterFor weapon (ArmorConfig),
-- in the order InventoryConfig lists weapons. Shared so the guide's dialogue (client) and
-- StarterService (server) agree.

local ArmorConfig = require(script.Parent.Config.ArmorConfig)
local InventoryConfig = require(script.Parent.Config.InventoryConfig)

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

return Starter
