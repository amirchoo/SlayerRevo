--!strict
-- Weapon carry clips (<Weapon>Walk, e.g. SwordWalk): an upper-body loop played instead of the
-- weapon's idle while moving, so the weapon swings with the steps (the legs keep the default
-- walk/run, or the player's animation pack). One cycle of the clip is two steps, and its time 0
-- is the moment the LEFT foot is furthest ahead (the right arm swung back).
--
-- A syncer keeps the clip at the rate of whichever walk/run track carries the most weight, and
-- in phase with the feet: it watches the character's real feet, and each time the left foot is
-- furthest ahead it notes where that track was in its cycle. Measured, not assumed, so it holds
-- for any walk or run animation.

local WeaponWalk = {}

local MOVING_SPEED = 0.1 -- MoveDirection length above which we count as walking
local STOP_DELAY = 0.12 -- seconds stopped before the idle comes back (no flicker on a tap)
local DRIFT = 0.05 -- fraction of a cycle out of step before the clip is snapped back in step
local MIN_STRIDE = 0.4 -- studs the left foot must be ahead for a stride peak to count

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

-- A function to call every frame while `walk` plays: keeps it in step with the character's feet.
-- `phase` (a fraction of a cycle) shifts it for a clip that doesn't start left foot forward.
function WeaponWalk.syncer(character: Model, animator: Animator, walk: AnimationTrack, phase: number?): () -> ()
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local left = character:FindFirstChild("LeftFoot") :: BasePart?
	local right = character:FindFirstChild("RightFoot") :: BasePart?
	local offsets: { [string]: number } = {} -- per walk/run animation: its cycle fraction at the left foot's peak
	local lastLead, lastFraction, rising = -math.huge, 0, false

	return function()
		local steps = stepTrack(animator)
		if not steps or walk.Length <= 0 then
			return
		end
		walk:AdjustSpeed(steps.Speed * walk.Length / steps.Length)
		local fraction = steps.TimePosition / steps.Length
		local id = (steps.Animation :: Animation).AnimationId

		-- How far the left foot is ahead of the right, along where the character faces.
		if root and left and right then
			local lead = (left.Position - right.Position):Dot(root.CFrame.LookVector)
			if lead < lastLead and rising and lastLead > MIN_STRIDE then
				offsets[id] = lastFraction -- the last frame was the peak
			end
			rising = lead > lastLead
			lastLead, lastFraction = lead, fraction
		end

		local offset = offsets[id]
		if offset == nil then
			return -- no stride measured yet for this animation: run at its rate, phase as it is
		end
		local want = (fraction - offset + (phase or 0)) % 1
		local off = math.abs(walk.TimePosition / walk.Length - want)
		if math.min(off, 1 - off) > DRIFT then
			walk.TimePosition = want * walk.Length
		end
	end
end

return WeaponWalk
