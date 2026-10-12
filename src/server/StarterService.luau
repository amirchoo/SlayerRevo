--!strict
-- The starter pick (see shared/Starter): once per save, a player standing at the guide
-- chooses a starter weapon (StarterChoose remote) and gets it, with its starter armor set
-- put on. The pick is saved as the data's Starter and published as the "Starter" attribute
-- ("" until chosen), which the guide's dialogue reads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local Starter = require(ReplicatedStorage.Shared.Starter)
local ArmorService = require(script.Parent.ArmorService)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local NpcService = require(script.Parent.NpcService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local chooseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StarterChoose") :: RemoteEvent

local GUIDE = "Guide" -- the NpcConfig entry who hands out the starter pick

local StarterService = {}

-- Never trust the client: a real choice, not picked before, and standing at the guide.
local function onChoose(player: Player, weapon: unknown)
	if typeof(weapon) ~= "string" then
		return
	end
	local choice = Starter.choiceFor(weapon)
	local data = DataService.data(player)
	if not choice or not data or data.Starter ~= nil then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local guide = NpcService.position(GUIDE)
	if not (root and root:IsA("BasePart") and guide) then
		return
	end
	local flat = Vector3.new(root.Position.X - guide.X, 0, root.Position.Z - guide.Z)
	if flat.Magnitude > NpcConfig.CloseDistance then
		return
	end

	data.Starter = choice.Weapon
	player:SetAttribute("Starter", choice.Weapon)
	InventoryService.grant(player, choice.Weapon)
	ArmorService.giveSet(player, choice.ArmorSet)
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
