--!strict
-- Dash i-frames. The dash itself runs on the player's client (it moves its own character);
-- the client reports each one (DashStart), and the server grants Dash.IFrameTime seconds
-- of invulnerability, during which any damage to the player is dodged (and the player is
-- told, Dodged). The server keeps its own count of dash charges, refilling like the
-- client's, so spamming the remote can't buy more invulnerability than real dashes would.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HealthService = require(script.Parent.HealthService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local DASH = CombatConfig.Dash
local TIMING_SLACK = 0.1 -- network delay makes dashes arrive slightly early or late

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dashRemote = remotes:WaitForChild("DashStart") :: RemoteEvent
local dodgedRemote = remotes:WaitForChild("Dodged") :: RemoteEvent

local DashService = {}

type DashState = { charges: number, updated: number, lastDash: number, invulnerableUntil: number }
local states: { [Player]: DashState } = {}

local function freshState(): DashState
	return { charges = DASH.MaxCharges, updated = os.clock(), lastDash = 0, invulnerableUntil = 0 }
end

local function onDash(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end
	local state = states[player] or freshState()
	states[player] = state
	local now = os.clock()
	-- Refill like the client: one charge per RechargeTime.
	state.charges = math.min(DASH.MaxCharges, state.charges + (now - state.updated) / DASH.RechargeTime)
	state.updated = now
	if state.charges < 1 - TIMING_SLACK / DASH.RechargeTime or now - state.lastDash < DASH.MinInterval - TIMING_SLACK then
		return -- no charge ready: no i-frames
	end
	state.charges = math.max(state.charges - 1, 0)
	state.lastDash = now
	state.invulnerableUntil = now + DASH.IFrameTime
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

function DashService.start()
	local function onPlayerAdded(player: Player)
		states[player] = freshState()
		player.CharacterAdded:Connect(function()
			states[player] = freshState() -- the client refills its charges on respawn too
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
