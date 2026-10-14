--!strict
-- Animates the animals (workspace.Animals, from AnimalService) by turning their limb joints:
-- legs swing in step with how fast they're going, heads bob as they walk and dip to graze or
-- peck while they stand, wings flap while they run, and tails swish. Each joint is a Motor6D
-- on the animal's root with "Swing" (Leg, Head, Wing, Tail), "Phase" and "Side" attributes;
-- the animal's type is its "Animal" attribute (AnimalConfig.Types). Looks only: the server
-- moves them. Animals further than AnimalConfig.AnimateRange from the camera are left still.
-- Now and then each one makes its Call (a moo, a cluck), heard nearby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimalConfig = require(ReplicatedStorage.Shared.Config.AnimalConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local TAU = math.pi * 2
local LEG_SWING = 0.55 -- radians each way at a run
local MAX_STEPS = 6 -- leg cycles per second, at most (a sprinting chicken stays readable)
local STRIDE = 2.6 -- studs covered per leg cycle, per stud of leg
local EASE = 10 -- how quickly poses blend (per second)
local FLAP_SPEED = 26 -- radians per second
local FLAP_LIFT = 0.9 -- radians the wings open at the top of a flap

type Joint = { motor: Motor6D, swing: string, phase: number, side: number }
type Tracked = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	kind: AnimalConfig.AnimalType,
	joints: { Joint },
	cycle: number, -- walk cycle, in cycles
	stride: number, -- leg swing size, eased
	flap: number, -- 0..1, eased: how much it's flapping
	head: number, -- head pitch, eased
	grazeUntil: number,
	nextGraze: number,
	nextCall: number,
	seed: number,
}

local AnimalAnimator = {}

local tracked: { [Model]: Tracked } = {}
local random = Random.new()

local function ease(current: number, target: number, dt: number): number
	return current + (target - current) * math.min(dt * EASE, 1)
end

local function track(model: Model)
	local key = model:GetAttribute("Animal")
	local kind = if typeof(key) == "string" then AnimalConfig.Types[key] else nil
	local root = if kind then model:WaitForChild("HumanoidRootPart", 5) else nil
	if not kind or not root or not root:IsA("BasePart") or not model.Parent then
		return
	end
	local joints: { Joint } = {}
	for _, child in root:GetChildren() do
		local swing = child:GetAttribute("Swing")
		if child:IsA("Motor6D") and typeof(swing) == "string" then
			local phase, side = child:GetAttribute("Phase"), child:GetAttribute("Side")
			table.insert(joints, {
				motor = child,
				swing = swing,
				phase = if typeof(phase) == "number" then phase else 0,
				side = if typeof(side) == "number" then side else 1,
			})
		end
	end
	tracked[model] = {
		model = model,
		root = root,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		kind = kind,
		joints = joints,
		cycle = 0,
		stride = 0,
		flap = 0,
		head = 0,
		grazeUntil = 0,
		nextGraze = os.clock() + random:NextNumber(kind.Graze.Gap[1], kind.Graze.Gap[2]),
		nextCall = os.clock() + (if kind.Call then random:NextNumber(0, kind.Call.Gap[2]) else math.huge),
		seed = random:NextNumber(0, TAU),
	}
end

local function animate(animal: Tracked, dt: number, now: number)
	local kind = animal.kind
	local velocity = animal.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local health = animal.model:GetAttribute("Health")
	local alive = typeof(health) ~= "number" or health > 0
	local moving = alive and speed > 0.6
	local running = moving and speed > kind.WalkSpeed * 1.6

	-- Legs: a cycle per STRIDE leg-lengths covered.
	local legLength = if animal.humanoid then math.max(animal.humanoid.HipHeight, 0.2) else 1
	animal.cycle = (animal.cycle + dt * math.min(speed / (legLength * STRIDE), MAX_STEPS)) % 1
	local targetStride = if moving then LEG_SWING * math.clamp(0.45 + speed / kind.FleeSpeed * 0.55, 0, 1) else 0
	animal.stride = ease(animal.stride, targetStride, dt)
	animal.flap = ease(animal.flap, if running then 1 else 0, dt)

	-- Head: bob while walking; dip to graze now and then while standing.
	local graze = kind.Graze
	if moving or not alive then
		animal.grazeUntil = 0
		animal.nextGraze = math.max(animal.nextGraze, now + graze.Gap[1])
	elseif now >= animal.nextGraze then
		animal.grazeUntil = now + random:NextNumber(graze.Time[1], graze.Time[2])
		animal.nextGraze = animal.grazeUntil + random:NextNumber(graze.Gap[1], graze.Gap[2])
	end
	local targetHead = if now < animal.grazeUntil then graze.Pitch else 0
	animal.head = ease(animal.head, targetHead, dt * 1.5)
	local bob = math.sin(animal.cycle * TAU * 2) * 0.08 * (animal.stride / LEG_SWING)

	local call = kind.Call
	if call and now >= animal.nextCall then
		animal.nextCall = now + random:NextNumber(call.Gap[1], call.Gap[2])
		if alive then
			Sounds.play(call.Sound, animal.root, random:NextNumber(0.9, 1.1))
		end
	end

	for _, joint in animal.joints do
		local transform
		if joint.swing == "Leg" then
			transform = CFrame.Angles(math.sin((animal.cycle + joint.phase) * TAU) * animal.stride, 0, 0)
		elseif joint.swing == "Head" then
			transform = CFrame.Angles(animal.head + bob, 0, 0)
		elseif joint.swing == "Wing" then
			local open = (math.sin(now * FLAP_SPEED + animal.seed) * 0.5 + 0.5) * FLAP_LIFT * animal.flap
			transform = CFrame.Angles(0, 0, open * joint.side)
		elseif joint.swing == "Tail" then
			local swish = math.sin(now * (if running then 9 else 1.8) + animal.seed) * (if running then 0.5 else 0.25)
			transform = CFrame.Angles(0, 0, if alive then swish else 0)
		else
			transform = CFrame.identity
		end
		joint.motor.Transform = transform
	end
end

function AnimalAnimator.start()
	local folder = workspace:WaitForChild("Animals")
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

	local range = AnimalConfig.AnimateRange
	RunService.PreSimulation:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for _, animal in tracked do
			if (animal.root.Position - eye).Magnitude <= range then
				animate(animal, dt, now)
			end
		end
	end)
end

return AnimalAnimator
