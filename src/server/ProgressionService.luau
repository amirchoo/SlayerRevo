--!strict
-- Player levels and XP. Defeating an enemy gives the player who landed the final blow its
-- XP (the enemy's "XPReward" attribute, from EnemyConfig); enough XP levels them up, which
-- earns skill points (ProgressionConfig) and tells their client (LevelUp remote) for the
-- popup. The killer also sees how much XP they got (XPGained remote: where, how much).
-- Level and XP are saved in the player's data (DataService) and published as the
-- "Level", "XP", and "XPToNext" attributes for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local SkillService = require(script.Parent.SkillService)

local levelUpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LevelUp") :: RemoteEvent
local xpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("XPGained") :: RemoteEvent

local ProgressionService = {}

local function publish(player: Player, data: DataService.Data)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPToNext", if data.Level >= ProgressionConfig.MaxLevel then 0 else ProgressionConfig.xpToNext(data.Level))
end

function ProgressionService.addXP(player: Player, amount: number)
	local data = DataService.data(player)
	if not data or amount <= 0 or data.Level >= ProgressionConfig.MaxLevel then
		return
	end
	data.XP += amount
	local gained = 0
	while data.Level < ProgressionConfig.MaxLevel and data.XP >= ProgressionConfig.xpToNext(data.Level) do
		data.XP -= ProgressionConfig.xpToNext(data.Level)
		data.Level += 1
		gained += 1
	end
	if data.Level >= ProgressionConfig.MaxLevel then
		data.XP = 0
	end
	publish(player, data)
	if gained > 0 then
		levelUpRemote:FireClient(player, data.Level, gained * ProgressionConfig.PointsPerLevel)
		SkillService.refresh(player) -- new points
	end
end

function ProgressionService.start()
	DataService.onLoaded(function(player, data)
		data.Level = math.clamp(data.Level, 1, ProgressionConfig.MaxLevel)
		publish(player, data)
	end)
	HealthService.Died:Connect(function(model: Model, killer: Player?)
		local reward = model:GetAttribute("XPReward")
		if killer and typeof(reward) == "number" and not Players:GetPlayerFromCharacter(model) then
			local data = DataService.data(killer)
			if data and data.Level < ProgressionConfig.MaxLevel then
				local boxCFrame, size = model:GetBoundingBox()
				xpRemote:FireClient(killer, boxCFrame.Position + Vector3.new(0, size.Y / 2 + 1, 0), reward)
			end
			ProgressionService.addXP(killer, reward)
		end
	end)
end

return ProgressionService
