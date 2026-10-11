--!strict
-- The skill trees on the server: spending points (SkillSpend remote: treeId, nodeId) and
-- resetting them for free (SkillRespec remote: treeId, or nil for every tree). Every request
-- is checked against the rules in SkillTrees (via SkillMath.check): enough points, tier
-- requirements, prerequisites, the rival-branch lock, and the mastery forks.
-- A player's allocations are saved in their data (DataService) and published as the
-- "Skills" attribute (JSON) with "SkillPoints" (unspent), which the game systems and the
-- client read through SkillMath. After any change the bonuses are applied right away
-- (max health, stamina, block charges...).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local StaminaService = require(script.Parent.StaminaService)
local BlockService = require(script.Parent.BlockService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spendRemote = remotes:WaitForChild("SkillSpend") :: RemoteEvent
local respecRemote = remotes:WaitForChild("SkillRespec") :: RemoteEvent

local SkillService = {}

-- Publishes the player's allocations and unspent points, and applies the bonuses.
function SkillService.refresh(player: Player)
	local data = DataService.data(player)
	if not data then
		return
	end
	player:SetAttribute("Skills", HttpService:JSONEncode(data.Skills))
	player:SetAttribute("SkillPoints", SkillMath.availablePoints(data.Skills, data.Level))
	HealthService.refreshPlayer(player)
	StaminaService.refreshMax(player)
	BlockService.refreshCharges(player)
end

local function onSpend(player: Player, treeId: unknown, nodeId: unknown)
	local data = DataService.data(player)
	if not data or typeof(treeId) ~= "string" or typeof(nodeId) ~= "string" then
		return
	end
	if not SkillMath.check(data.Skills, data.Level, treeId, nodeId) then
		return
	end
	local tree = data.Skills[treeId] or {}
	tree[nodeId] = (tree[nodeId] or 0) + 1
	data.Skills[treeId] = tree
	SkillService.refresh(player)
end

local function onRespec(player: Player, treeId: unknown)
	local data = DataService.data(player)
	if not data then
		return
	end
	if treeId == nil then
		data.Skills = {}
	elseif typeof(treeId) == "string" and SkillMath.isTree(treeId) then
		data.Skills[treeId] = nil
	else
		return
	end
	SkillService.refresh(player)
end

function SkillService.start()
	DataService.onLoaded(function(player, data)
		-- Saved skills are re-checked against today's trees (e.g. after a rebalance).
		data.Skills = SkillMath.sanitize(data.Skills, data.Level)
		SkillService.refresh(player)
	end)
	RemoteGuard.connect(spendRemote, onSpend)
	RemoteGuard.connect(respecRemote, onRespec)
end

return SkillService
