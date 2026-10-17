--!strict
-- Weapon carry clips (<Weapon>Walk, e.g. SwordWalk): an upper-body loop played instead of the
-- weapon's idle while moving, so the weapon swings with the steps (the legs keep the default
-- walk/run). One cycle of the clip is one cycle of the default walk (two steps); sync() keeps
-- it at the same rate and phase as whichever default walk or run track is carrying the most
-- weight, so the arm swings with the feet at any speed.

local WeaponWalk = {}

local MOVING_SPEED = 0.1 -- MoveDirection length above which we count as walking
local STOP_DELAY = 0.12 -- seconds stopped before the idle comes back (no flicker on a tap)
local DRIFT = 0.05 -- fraction of a cycle out of step before the clip is snapped back in step

-- The default Animate script's walk or run track carrying the most weight, if one is playing.
local function stepTrack(animator: Animator): AnimationTrack?
	local best: AnimationTrack? = nil
	local weight = 0
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		local name = animation and animation.Name
		if (name == "WalkAnim" or name == "RunAnim") and track.Length > 0 and track.WeightCurrent > weight then
			best, weight = track, track.WeightCurrent
		end
	end
	return best
end

-- A function telling whether `humanoid` is walking, with a short delay on stopping.
function WeaponWalk.mover(humanoid: Humanoid): () -> boolean
	local stoppedAt: number? = nil
	return function(): boolean
		if humanoid.MoveDirection.Magnitude > MOVING_SPEED then
			stoppedAt = nil
			return true
		end
		local now = os.clock()
		local since = stoppedAt or now
		stoppedAt = since
		return now - since < STOP_DELAY
	end
end

-- Keeps `walk` in step with the feet: the default walk/run's rate and phase, plus `phase`
-- (a fraction of a cycle) for a clip whose cycle starts on the other foot.
function WeaponWalk.sync(walk: AnimationTrack, animator: Animator, phase: number?)
	local steps = stepTrack(animator)
	if not steps or walk.Length <= 0 then
		return
	end
	walk:AdjustSpeed(steps.Speed * walk.Length / steps.Length)
	local want = (steps.TimePosition / steps.Length + (phase or 0)) % 1
	local off = math.abs(walk.TimePosition / walk.Length - want)
	if math.min(off, 1 - off) > DRIFT then
		walk.TimePosition = want * walk.Length
	end
end

return WeaponWalk
