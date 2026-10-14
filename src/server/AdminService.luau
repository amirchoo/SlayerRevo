--!strict
-- Admin test tools, for checking systems like the skill trees by hand. Only admins can use
-- them: everyone in Studio, and in live servers only the game's owner (when a user, not a
-- group, owns it). Admins get the "Admin" attribute, which shows them the admin panel
-- (client AdminPanel, the ` key). The panel fires AdminCommand (action, amount?):
--   "Level":       changes their level by `amount` (each level is a skill point; ProgressionService.setLevel)
--   "MaxLevel":    sets them to the max level
--   "ResetSkills": refunds every skill point
--   "Heal":        refills health, stamina and mana
--   "Damage":      hurts them by `amount` (to watch regen or test max health)
--   "Coins":       gives them `amount` coins
-- Level and coin changes are saved like normal progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local ProgressionService = require(script.Parent.ProgressionService)
local SkillService = require(script.Parent.SkillService)
local CurrencyService = require(script.Parent.CurrencyService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local commandRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AdminCommand") :: RemoteEvent

local MAX_AMOUNT = 100000

local AdminService = {}

function AdminService.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function onCommand(player: Player, action: unknown, amount: unknown)
	if not AdminService.isAdmin(player) or typeof(action) ~= "string" then
		return
	end
	-- `amount == amount` rejects NaN.
	local n = if typeof(amount) == "number" and amount == amount then math.clamp(math.floor(amount), -MAX_AMOUNT, MAX_AMOUNT) else 0
	local data = DataService.data(player)
	if not data then
		return
	end
	local character = player.Character
	if action == "Level" then
		ProgressionService.setLevel(player, data.Level + n)
	elseif action == "MaxLevel" then
		ProgressionService.setLevel(player, ProgressionConfig.MaxLevel)
	elseif action == "ResetSkills" then
		data.Skills = {}
		SkillService.refresh(player)
	elseif action == "Heal" then
		if character then
			local _, maxHealth = HealthService.getHealth(character)
			if maxHealth then
				HealthService.heal(character, maxHealth)
			end
		end
		player:SetAttribute("Stamina", player:GetAttribute("MaxStamina"))
		player:SetAttribute("Mana", player:GetAttribute("MaxMana"))
	elseif action == "Damage" then
		if character and n > 0 then
			HealthService.damage(character, n)
		end
	elseif action == "Coins" then
		if n > 0 then
			CurrencyService.add(player, n)
		end
	end
end

function AdminService.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("Admin", AdminService.isAdmin(player))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	RemoteGuard.connect(commandRemote, onCommand)
end

return AdminService
