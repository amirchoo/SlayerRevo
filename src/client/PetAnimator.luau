--!strict
-- Animates the pets (workspace.Pets, from PetService) by posing their bones every frame from
-- their clip data (PetClips; src/shared/PetClips/<Clips>.luau, made by tools/npc_clips.py):
-- the clip for each one's "PetState" attribute (NpcConfig.Pets States), looped, cross-fading
-- from the last one over PetBehaviour.Fade seconds. On top of that it swings the legs in a
-- trot while the pet moves, and sets the eyelids (PetEyes): open with blinks while idle,
-- walking or playing, half shut while loafing (slow blinks, the way cats do), shut asleep.
-- Looks only: the server moves the pets and picks their state. Pets further than
-- ANIMATE_RANGE from the camera aren't posed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local PetClips = require(script.Parent.PetClips)
local PetEyes = require(script.Parent.PetEyes)

local BEHAVIOUR = NpcConfig.PetBehaviour
local ANIMATE_RANGE = 150 -- studs from the camera
local TAU = math.pi * 2
local STRIDE = 0.75 -- studs covered per leg cycle, per stud of the pet's Height
local LEG_SWING = 0.45 -- radians each way the upper legs swing at a walk
local KNEE_BEND = 0.5 -- radians the lower legs fold as they swing forward
local EASE = 8 -- how quickly the walk blends in and out (per second)

-- The legs, trotting: each front leg moves with the opposite hind leg.
local LEGS = {
	{ upper = "FrontUpperL", lower = "FrontLowerL", phase = 0 },
	{ upper = "HindUpperR", lower = "HindLowerR", phase = 0 },
	{ upper = "FrontUpperR", lower = "FrontLowerR", phase = 0.5 },
	{ upper = "HindUpperL", lower = "HindLowerL", phase = 0.5 },
}
local LIDS = { "LidL", "LidR" }

type Tracked = {
	model: Model,
	root: BasePart,
	config: NpcConfig.Pet,
	data: PetClips.Data,
	rig: PetClips.Rig,
	clip: string,
	clipTime: number,
	previous: string?, -- the clip fading out
	previousTime: number,
	fade: number, -- 0..1: how far the fade into `clip` has got
	eyes: PetEyes.PetEyes,
	cycle: number, -- walk cycle, in cycles
	walk: number, -- 0..1, eased: how much it's walking
	nextBlink: number,
}

local PetAnimator = {}

local tracked: { [Model]: Tracked } = {}
local random = Random.new()

local function configOf(id: unknown): NpcConfig.Pet?
	for _, pet in NpcConfig.Pets do
		if pet.Id == id then
			return pet
		end
	end
	return nil
end

local function stateOf(pet: Tracked): string
	local state = pet.model:GetAttribute("PetState")
	return if typeof(state) == "string" then state else "Idle"
end

local function applyState(pet: Tracked)
	local state = stateOf(pet)
	local clip = pet.config.States[state] or "Idle"
	if clip ~= pet.clip then
		pet.previous, pet.previousTime = pet.clip, pet.clipTime
		pet.clip, pet.clipTime, pet.fade = clip, 0, 0
	end
	pet.eyes:set(pet.config.Eyes[state] or 1)
end

local function track(model: Model)
	local config = configOf(model:GetAttribute("PetId"))
	local root = model:WaitForChild("HumanoidRootPart", 10)
	local module = config and ReplicatedStorage.Shared.PetClips:FindFirstChild(config.Clips)
	if not config or not root or not root:IsA("BasePart") or not module or not module:IsA("ModuleScript") or not model.Parent then
		return
	end
	local data = (require :: any)(module) :: PetClips.Data
	local pet: Tracked = {
		model = model,
		root = root,
		config = config,
		data = data,
		rig = PetClips.rig(model, data),
		clip = "Idle",
		clipTime = random:NextNumber(0, 4), -- not every pet in step
		previous = nil,
		previousTime = 0,
		fade = 1,
		eyes = PetEyes.new(config.Lids),
		cycle = 0,
		walk = 0,
		nextBlink = os.clock() + random:NextNumber(BEHAVIOUR.BlinkEvery.Min, BEHAVIOUR.BlinkEvery.Max),
	}
	pet.clip = config.States[stateOf(pet)] or "Idle"
	pet.eyes:set(config.Eyes[stateOf(pet)] or 1, true)
	tracked[model] = pet
	model:GetAttributeChangedSignal("PetState"):Connect(function()
		applyState(pet)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			tracked[model] = nil
		end
	end)
end

local function step(pet: Tracked, dt: number, now: number)
	pet.clipTime += dt
	pet.previousTime += dt
	pet.fade = math.min(pet.fade + dt / BEHAVIOUR.Fade, 1)
	local pose = PetClips.sample(pet.data, pet.clip, pet.clipTime)
	local previous = pet.previous
	if previous and pet.fade < 1 then
		local from = PetClips.sample(pet.data, previous, pet.previousTime)
		PetClips.blend(from, pose, pet.fade)
		pose = from
	end

	-- The trot, on top of the clip.
	local velocity = pet.root.AssemblyLinearVelocity
	local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
	local walking = stateOf(pet) == "Walking" and speed > 0.3
	pet.walk += ((if walking then 1 else 0) - pet.walk) * math.min(dt * EASE, 1)
	pet.cycle = (pet.cycle + dt * speed / (STRIDE * pet.config.Height)) % 1
	if pet.walk > 0.001 then
		for _, leg in LEGS do
			local t = TAU * (pet.cycle + leg.phase)
			local upper, lower = pose[leg.upper], pose[leg.lower]
			if upper then
				pose[leg.upper] = upper * CFrame.Angles(math.sin(t) * LEG_SWING * pet.walk, 0, 0)
			end
			if lower then
				-- Fold while swinging forward (lifting the paw), straight while pushing back.
				pose[leg.lower] = lower * CFrame.Angles(-math.max(math.cos(t), 0) * KNEE_BEND * pet.walk, 0, 0)
			end
		end
	end

	-- The eyes.
	if now >= pet.nextBlink then
		pet.nextBlink = now + random:NextNumber(BEHAVIOUR.BlinkEvery.Min, BEHAVIOUR.BlinkEvery.Max)
		if pet.eyes.target > 0 then
			pet.eyes:blink()
		end
	end
	pet.eyes:step(dt)
	local lid = CFrame.Angles(pet.eyes:angle(), 0, 0)
	for _, name in LIDS do
		local cf = pose[name]
		if cf then
			pose[name] = CFrame.new(cf.Position) * lid
		end
	end

	PetClips.apply(pet.rig, pose)
end

function PetAnimator.start()
	local folder = workspace:WaitForChild("Pets")
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end

	RunService.PreRender:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local now = os.clock()
		for _, pet in tracked do
			if camera and (pet.root.Position - camera.CFrame.Position).Magnitude <= ANIMATE_RANGE then
				step(pet, dt, now)
			end
		end
	end)
end

return PetAnimator
