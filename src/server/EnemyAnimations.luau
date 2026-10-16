--!strict
-- An enemy's body language: loads its clips (its type's own Animations, else the shared ones
-- in EnemyConfig), loops the idle underneath, and walks or runs (RunAbove) while it moves, each
-- played faster or slower to match its real speed so the feet don't slide. Its flinch and
-- parried recoil are handed to EnemyEffects. Returns the attack track for its owner to play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local EnemyEffects = require(script.Parent.EnemyEffects)

type EnemyType = EnemyConfig.EnemyType

local MOVING = 0.5 -- studs/s: slower than this counts as standing still
local MIN_RATE, MAX_RATE = 0.6, 1.8 -- how far a cycle is sped up or slowed down to fit

local EnemyAnimations = {}

local function load(animator: Animator, id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	-- A bare number (e.g. pasted straight from the Creator Dashboard) still works.
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

local function pick(own: string?, shared: string): string
	return if own and own ~= "" then own else shared
end

-- Starts `enemy`'s animations (a `kind` enemy) and returns its attack track.
function EnemyAnimations.start(enemy: Model, humanoid: Humanoid, kind: EnemyType): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local own = kind.Animations
	-- Idle always runs underneath, so the enemy never shows its rest pose (a T-pose for
	-- models made with Avatar Auto Setup); walking and attacking play over it.
	local idle = load(animator, pick(own and own.Idle, EnemyConfig.IdleAnimation), Enum.AnimationPriority.Idle, true)
	if idle then
		idle:Play()
	end
	local walk = load(animator, pick(own and own.Walk, EnemyConfig.WalkAnimation), Enum.AnimationPriority.Movement, true)
	local run = if own then load(animator, own.Run, Enum.AnimationPriority.Movement, true) else nil
	local attack = load(animator, pick(kind.AttackAnimation, EnemyConfig.DefaultAttackAnimation), Enum.AnimationPriority.Action, false) :: AnimationTrack
	EnemyEffects.setClips(enemy, pick(own and own.Flinch, EnemyConfig.FlinchAnimation), pick(own and own.Parried, EnemyConfig.ParriedAnimation))

	humanoid.Running:Connect(function(speed)
		local running = run ~= nil and own ~= nil and speed > own.RunAbove
		local current = if speed <= MOVING then nil elseif running then run else walk
		for _, track in { walk, run } :: { AnimationTrack? } do
			if track and track ~= current and track.IsPlaying then
				track:Stop(0.2)
			end
		end
		if not current then
			return
		end
		if not current.IsPlaying then
			current:Play(0.2)
		end
		-- Match the cycle to the ground speed (the shared R15 walk just plays as it is). A
		-- scaled-up enemy's stride is longer by its Scale.
		if own then
			local clipSpeed = (if running then own.RunClipSpeed else own.WalkClipSpeed) * (kind.Scale or 1)
			current:AdjustSpeed(math.clamp(speed / clipSpeed, MIN_RATE, MAX_RATE))
		end
	end)
	return attack
end

return EnemyAnimations
