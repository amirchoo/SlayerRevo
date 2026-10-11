--!strict
-- Connects RemoteEvent handlers with a per-player rate limit (NetworkConfig): each player
-- gets a bucket of requests per remote that refills over time; requests when it's empty are
-- dropped (with one warning per player per remote, so logs aren't flooded either).
-- Use RemoteGuard.connect(remote, handler) instead of remote.OnServerEvent:Connect(handler).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkConfig = require(ReplicatedStorage.Shared.Config.NetworkConfig)

local RemoteGuard = {}

type Bucket = { tokens: number, updated: number, warned: boolean }
local buckets: { [Player]: { [RemoteEvent]: Bucket } } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

local function allow(player: Player, remote: RemoteEvent, perSecond: number): boolean
	local byRemote = buckets[player]
	if not byRemote then
		byRemote = {}
		buckets[player] = byRemote
	end
	local now = os.clock()
	local bucket = byRemote[remote]
	if not bucket then
		bucket = { tokens = perSecond, updated = now, warned = false }
		byRemote[remote] = bucket
	end
	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.updated) * perSecond)
	bucket.updated = now
	if bucket.tokens < 1 then
		if not bucket.warned then
			bucket.warned = true
			warn(`[RemoteGuard] {player.Name} is firing {remote.Name} too fast; dropping requests`)
		end
		return false
	end
	bucket.tokens -= 1
	return true
end

function RemoteGuard.connect(remote: RemoteEvent, handler: (Player, ...any) -> ()): RBXScriptConnection
	local perSecond = NetworkConfig.PerSecond[remote.Name] or NetworkConfig.DefaultPerSecond
	return remote.OnServerEvent:Connect(function(player: Player, ...)
		if allow(player, remote, perSecond) then
			handler(player, ...)
		end
	end)
end

return RemoteGuard
