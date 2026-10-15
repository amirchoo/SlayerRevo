--!strict
-- Dash i-frames. The dash itself runs on the player's client (it moves its own character);
-- the client reports each one (DashStart), and the server grants Dash.IFrameTime seconds
-- of invulnerability, during which any damage to the player is dodged (and the player is
-- told, Dodged). The server keeps its own count of dash charges, refilling like the
-- client's, so spamming the remote can't buy more invulnerability than real dashes would.
-- Each real dash is also passed on to the other players (DashEffect), who draw its dust and
-- afterimage (see client DashEffects); the dasher has already drawn their own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local HealthService = require(script.Parent.HealthService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local DASH = CombatConfig.Dash
local TIMING_SLACK = 0.1 -- network delay makes dashes arrive slightly early or late

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dashRemote = remotes:WaitForChild("DashStart") :: RemoteEvent
local dodgedRemote = remotes:WaitForChild("Dodged") :: RemoteEvent
local dashEffectRemote = remotes:WaitForChild("DashEffect") :: RemoteEvent

local DashService = {}

type DashState = { charges: number, updated: number, lastDash: number, invulnerableUntil: number }
local states: { [Player]: DashState } = {}

-- The player's dash charges, recharge time, and i-frames, with their skill bonuses
-- (see SkillTrees), and nearly instant recharges in the training camp (TutorialConfig); the
-- client's dash meter works these out the same way.
local function dashStats(player: Player): (number, number, number)
	local charges = DASH.MaxCharges + SkillMath.general(player, "DashCharges")
	local recharge = TutorialConfig.dashRecharge(player, DASH.RechargeTime * (1 - SkillMath.general(player, "DashRecharge")))
	local iframes = DASH.IFrameTime + SkillMath.general(player, "DashIFrames")
	return charges, recharge, iframes
end

local function freshState(player: Player): DashState
	return { charges = (dashStats(player)), updated = os.clock(), lastDash = 0, invulnerableUntil = 0 }
end

local function onDash(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end
	local state = states[player] or freshState(player)
	states[player] = state
	local now = os.clock()
	local maxCharges, recharge, iframes = dashStats(player)
	-- Refill like the client: one charge per recharge time.
	state.charges = math.min(maxCharges, state.charges + (now - state.updated) / recharge)
	state.updated = now
	if state.charges < 1 - TIMING_SLACK / recharge or now - state.lastDash < DASH.MinInterval - TIMING_SLACK then
		return -- no charge ready: no i-frames
	end
	state.charges = math.max(state.charges - 1, 0)
	state.lastDash = now
	state.invulnerableUntil = now + iframes
	for _, other in Players:GetPlayers() do
		if other ~= player then
			dashEffectRemote:FireClient(other, character)
		end
	end
end

-- Damage filter: a hit during a dash's i-frames is dodged.
local function dodgeFilter(target: Model, amount: number): number
	local player = Players:GetPlayerFromCharacter(target)
	local state = player and states[player]
	if player and state and os.clock() < state.invulnerableUntil then
		dodgedRemote:FireClient(player)
		return 0
	end
	return amount
end

-- When (os.clock) the player last dashed, or 0 if they haven't (the training camp's dodge drill
-- asks: a dash out of reach never reaches the damage filter).
function DashService.lastDash(player: Player): number
	local state = states[player]
	return if state then state.lastDash else 0
end

function DashService.start()
	local function onPlayerAdded(player: Player)
		states[player] = freshState(player)
		player.CharacterAdded:Connect(function()
			states[player] = freshState(player) -- the client refills its charges on respawn too
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RemoteGuard.connect(dashRemote, onDash)
	-- Added before BlockService's, so a dodged hit is never counted as blocked.
	HealthService.addDamageFilter(dodgeFilter)
end

return DashService
