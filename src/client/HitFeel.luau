--!strict
-- Hitstop: when one of your hits lands (the server's DamageDealt), your character and the
-- target freeze for a split second, longer for bigger hits, so impacts feel heavy. Only
-- animations pause (on this screen); movement, timing, and damage are unaffected.
-- Damage over time (bleed) doesn't cause hitstop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

local HITSTOP = CombatConfig.Hitstop

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent
local player = Players.LocalPlayer

local HitFeel = {}

-- Animators currently frozen, with when they unfreeze and each track's speed to restore.
type Frozen = { untilTime: number, speeds: { [AnimationTrack]: number } }
local frozen: { [Animator]: Frozen } = setmetatable({}, { __mode = "k" }) :: any

local function animatorOf(model: Model?): Animator?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local controller = model and model:FindFirstChildOfClass("AnimationController")
	local holder = humanoid or controller
	return if holder then holder:FindFirstChildOfClass("Animator") else nil
end

local function freeze(animator: Animator?, duration: number)
	if not animator then
		return
	end
	local untilTime = os.clock() + duration
	local current = frozen[animator]
	if current then
		-- Already frozen (e.g. several hits at once): just extend it.
		current.untilTime = math.max(current.untilTime, untilTime)
		return
	end
	local entry: Frozen = { untilTime = untilTime, speeds = {} }
	frozen[animator] = entry
	for _, track in animator:GetPlayingAnimationTracks() do
		entry.speeds[track] = track.Speed
		track:AdjustSpeed(0)
	end
	task.spawn(function()
		while os.clock() < entry.untilTime do
			task.wait()
		end
		frozen[animator] = nil
		for track, speed in entry.speeds do
			-- Leave alone a track someone else changed meanwhile (e.g. a charge holding its pose).
			if track.IsPlaying and track.Speed == 0 then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

function HitFeel.start()
	damageRemote.OnClientEvent:Connect(function(_position: Vector3, amount: number, kind: string?, target: Model?)
		if kind ~= nil then
			return -- damage over time
		end
		local duration = math.clamp(HITSTOP.Base + amount * HITSTOP.PerDamage, HITSTOP.Min, HITSTOP.Max)
		freeze(animatorOf(player.Character), duration)
		freeze(animatorOf(target), duration)
	end)
end

return HitFeel
