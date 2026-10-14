--!strict
-- The starter pick (see shared/Starter): once per save, a player chooses a starter weapon
-- (StarterChoose remote: from the new-player intro's Hall of Oaths, or the guide's dialogue)
-- and gets it, drawn, with its starter armor set put on (never a shield). The pick is saved
-- as the data's Starter and published as the "Starter" attribute ("" until chosen), which
-- the intro and the guide's dialogue read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local Starter = require(ReplicatedStorage.Shared.Starter)
local ArmorService = require(script.Parent.ArmorService)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local chooseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StarterChoose") :: RemoteEvent

local StarterService = {}

-- Never trust the client: a real choice, and not picked before.
local function onChoose(player: Player, weapon: unknown)
	if typeof(weapon) ~= "string" then
		return
	end
	local choice = Starter.choiceFor(weapon)
	local data = DataService.data(player)
	if not choice or not data or data.Starter ~= nil then
		return
	end

	data.Starter = choice.Weapon
	if InventoryService.owns(player, choice.Weapon) then
		InventoryService.move(player, choice.Weapon, true) -- an older save: into the hotbar
	else
		InventoryService.grant(player, choice.Weapon)
	end
	ArmorService.giveSet(player, choice.ArmorSet)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(choice.Weapon)
	if humanoid and tool and tool:IsA("Tool") then
		humanoid:EquipTool(tool)
	end
	player:SetAttribute("Starter", choice.Weapon) -- last: the intro ends when it changes
end

function StarterService.start()
	DataService.onLoaded(function(player, data)
		player:SetAttribute("Starter", data.Starter or "")
	end)
	RemoteGuard.connect(chooseRemote, onChoose)

	-- Studio only: ServerStorage.StarterDevTools:Invoke(player, "new" | "restore") puts a
	-- player's save in a brand-new player's state (no weapons, no pick) to test the starter
	-- flow, or gives every weapon back with the pick cleared. Never exists in live servers.
	if RunService:IsStudio() then
		local dev = Instance.new("BindableFunction")
		dev.Name = "StarterDevTools"
		dev.OnInvoke = function(player: Player, action: string): string
			local data = DataService.data(player)
			if not data then
				return "data not loaded"
			end
			data.Starter = nil
			table.clear(data.Weapons)
			if action == "restore" then
				for _, info in InventoryConfig.Weapons do
					data.Weapons[info.Name] = true
				end
			end
			player:SetAttribute("Starter", "")
			InventoryService.refresh(player)
			return `{action}: owns {player:GetAttribute("OwnedWeapons")}`
		end
		dev.Parent = ServerStorage
	end
end

return StarterService
