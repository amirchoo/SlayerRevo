--!strict
-- Freezes each display mannequin tagged "PosedMannequin" (the Training Grounds' armor stands,
-- see TrainingStands) in its pose: its "PoseAnimation", stopped "PoseAt" of the way through
-- (0..1). Played here on each client, where a frozen track's time can be set reliably.

local CollectionService = game:GetService("CollectionService")

local POSE_TAG = "PosedMannequin"
local LOAD_TIMEOUT = 10 -- seconds to wait for an animation's length to arrive

local MannequinPoses = {}

local function pose(mannequin: Instance)
	local id = mannequin:GetAttribute("PoseAnimation")
	local at = mannequin:GetAttribute("PoseAt")
	local humanoid = mannequin:WaitForChild("Humanoid", 10)
	if typeof(id) ~= "string" or id == "" or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	local track = (animator :: Animator):LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0, 1, 0) -- no fade, stopped where it's put
	local waited = 0
	while track.Length == 0 and waited < LOAD_TIMEOUT do
		waited += task.wait(0.1)
	end
	local fraction = if typeof(at) == "number" then math.clamp(at, 0, 1) else 1
	track.TimePosition = math.max(0, track.Length * fraction - 0.02) -- just before the end, so it doesn't stop
end

function MannequinPoses.start()
	CollectionService:GetInstanceAddedSignal(POSE_TAG):Connect(function(mannequin)
		task.spawn(pose, mannequin)
	end)
	for _, mannequin in CollectionService:GetTagged(POSE_TAG) do
		task.spawn(pose, mannequin)
	end
end

return MannequinPoses
