--!strict
-- Animates the villagers (workspace.Villagers, from VillagerService) by turning their R15
-- joints (AnimationConstraints on today's avatars, Motor6Ds on older rigs): an easy stroll while they move (legs swinging in step with their speed, a little
-- knee bend, relaxed arm swing, a slight sway of the hips) and a gentle idle while they stand
-- (breathing, looking about). Looks only: the server moves them. Villagers further than
-- ANIMATE_RANGE from the camera are left still.

local RunService = game:GetService("RunService")

local ANIMATE_RANGE = 150 -- studs from the camera
local STRIDE = 3.4 -- studs covered per full step cycle (left and right)
local LEG_SWING = 0.42 -- radians each way at a stroll
local KNEE_BEND = 0.55 -- radians the knee bends as the leg swings through
local ARM_SWING = 0.28 -- radians each way
local ELBOW_BEND = 0.18 -- radians the elbows are always a little bent
local EASE = 6 -- how quickly they blend between standing and walking (per second)
local TAU = math.pi * 2

local VillagerAnimator = {}

type Joint = Motor6D | AnimationConstraint
type Joints = { [string]: Joint }
type Tracked = { model: Model, root: BasePart, joints: Joints, cycle: number, walk: number, seed: number }

local tracked: { [Model]: Tracked } = {}
local random = Random.new()

local JOINT_NAMES = { "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Waist", "Neck" }

local function track(model: Model)
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or not model.Parent then
		return
	end
	local joints: Joints = {}
	for _, descendant in model:GetDescendants() do
		if (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) and table.find(JOINT_NAMES, descendant.Name) then
			joints[descendant.Name] = descendant :: Joint
		end
	end
	tracked[model] = { model = model, root = root, joints = joints, cycle = random:NextNumber(), walk = 0, seed = random:NextNumber(0, TAU) }
end

local function set(joints: Joints, name: string, transform: CFrame)
	local joint = joints[name]
	if joint then
		(joint :: any).Transform = transform
	end
end

local function animate(villager: Tracked, dt: number, now: number)
	local velocity = villager.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = speed > 0.5
	villager.walk += ((if moving then 1 else 0) - villager.walk) * math.min(dt * EASE, 1)
	villager.cycle = (villager.cycle + dt * speed / STRIDE) % 1
	local w = villager.walk
	local c = villager.cycle * TAU
	local joints = villager.joints

	-- Legs: one swings forward as the other goes back; the knee bends on the forward swing.
	set(joints, "LeftHip", CFrame.Angles(math.sin(c) * LEG_SWING * w, 0, 0))
	set(joints, "RightHip", CFrame.Angles(-math.sin(c) * LEG_SWING * w, 0, 0))
	set(joints, "LeftKnee", CFrame.Angles(-math.max(0, math.cos(c)) * KNEE_BEND * w, 0, 0))
	set(joints, "RightKnee", CFrame.Angles(-math.max(0, -math.cos(c)) * KNEE_BEND * w, 0, 0))

	-- Arms swing against the legs; at rest they hang with a slight sway.
	local breathe = math.sin(now * 1.6 + villager.seed)
	local rest = breathe * 0.03 * (1 - w)
	set(joints, "LeftShoulder", CFrame.Angles(-math.sin(c) * ARM_SWING * w + rest, 0, 0))
	set(joints, "RightShoulder", CFrame.Angles(math.sin(c) * ARM_SWING * w + rest, 0, 0))
	set(joints, "LeftElbow", CFrame.Angles(ELBOW_BEND + math.max(0, -math.sin(c)) * 0.15 * w, 0, 0))
	set(joints, "RightElbow", CFrame.Angles(ELBOW_BEND + math.max(0, math.sin(c)) * 0.15 * w, 0, 0))

	-- Body: a small hip twist with each step; breathing and a look about while standing.
	set(joints, "Waist", CFrame.Angles(breathe * 0.015, math.sin(c) * 0.08 * w, 0))
	local look = math.sin(now * 0.35 + villager.seed) * 0.35 * (1 - w)
	set(joints, "Neck", CFrame.Angles(0, look, 0))
end

function VillagerAnimator.start()
	local folder = workspace:WaitForChild("Villagers")
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			tracked[child] = nil
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end

	RunService.PreSimulation:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for _, villager in tracked do
			if (villager.root.Position - eye).Magnitude <= ANIMATE_RANGE then
				animate(villager, dt, now)
			end
		end
	end)
end

return VillagerAnimator
