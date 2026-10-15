--!strict
-- Animates bosses (models in workspace.Enemies with a "Boss" attribute, from BossService) by
-- posing their bones every frame from their clip data (RigClips; src/shared/EnemyClips/<Clips>,
-- made by tools/npc_clips.py from the .glb), like PetAnimator does for the pets.
--
-- The server names the clip: "BossAction" (a clip, played once from "BossActionAt" at
-- "BossActionSpeed"; the Stunned clip loops and Death holds its last frame) or "" for moving:
-- Idle, Walk or Run by how fast it's going, each cycle played at the rate that matches its
-- ground speed. Clips cross-fade over FADE seconds. Looks only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local RigClips = require(ReplicatedStorage.Shared.RigClips)

local ANIMATE_RANGE = 400 -- studs from the camera
local FADE = 0.2 -- seconds to cross-fade between clips
local MOVING = 1 -- studs/s: slower than this stands idle

type Tracked = {
	model: Model,
	root: BasePart,
	config: BossConfig.Boss,
	data: RigClips.Data,
	rig: RigClips.Rig,
	clip: string,
	time: number,
	previous: string?,
	previousTime: number,
	fade: number,
	loopTime: number, -- the walk/run/idle cycle's own clock
}

local BossAnimator = {}

local tracked: { [Model]: Tracked } = {}

local function track(model: Model)
	local id = model:GetAttribute("BossId")
	local config = if typeof(id) == "string" then BossConfig[id] :: BossConfig.Boss? else nil
	local root = model:WaitForChild("HumanoidRootPart", 10)
	local module = config and ReplicatedStorage.Shared.EnemyClips:FindFirstChild(config.Clips)
	if not config or not root or not root:IsA("BasePart") or not module or not module:IsA("ModuleScript") or not model.Parent then
		return
	end
	local data = (require :: any)(module) :: RigClips.Data
	tracked[model] = {
		model = model,
		root = root,
		config = config,
		data = data,
		rig = RigClips.rig(model, data),
		clip = config.Animations.Idle,
		time = 0,
		previous = nil,
		previousTime = 0,
		fade = 1,
		loopTime = 0,
	}
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			tracked[model] = nil
		end
	end)
end

-- The clip to show now and how far into it.
local function current(boss: Tracked, dt: number): (string, number)
	local anims = boss.config.Animations
	local action = boss.model:GetAttribute("BossAction")
	if typeof(action) == "string" and action ~= "" then
		local clip = boss.data.Clips[action]
		if clip then
			local at = boss.model:GetAttribute("BossActionAt")
			local speed = boss.model:GetAttribute("BossActionSpeed")
			local elapsed = (workspace:GetServerTimeNow() - (if typeof(at) == "number" then at else 0)) * (if typeof(speed) == "number" then speed else 1)
			elapsed = math.max(elapsed, 0)
			if action == anims.Stunned then
				return action, elapsed % clip.Length
			elseif action == anims.Death then
				return action, math.min(elapsed, clip.Length - 1e-3)
			elseif elapsed < clip.Length then
				return action, elapsed
			end
		end
	end
	local velocity = boss.root.AssemblyLinearVelocity
	local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
	local config = boss.config
	local clip, rate
	if speed > (config.WalkSpeed + config.RunSpeed) / 2 then
		clip, rate = anims.Run, speed / anims.RunClipSpeed
	elseif speed > MOVING then
		clip, rate = anims.Walk, speed / anims.WalkClipSpeed
	else
		clip, rate = anims.Idle, 1
	end
	boss.loopTime += dt * rate
	return clip, boss.loopTime
end

local function step(boss: Tracked, dt: number)
	local clip, time = current(boss, dt)
	if clip ~= boss.clip then
		boss.previous, boss.previousTime = boss.clip, boss.time
		boss.clip, boss.fade = clip, 0
	end
	boss.time = time
	boss.fade = math.min(boss.fade + dt / FADE, 1)
	local pose = RigClips.sample(boss.data, clip, time)
	local previous = boss.previous
	if previous and boss.fade < 1 then
		local from = RigClips.sample(boss.data, previous, boss.previousTime)
		RigClips.blend(from, pose, boss.fade)
		pose = from
	end
	RigClips.apply(boss.rig, pose)
end

function BossAnimator.start()
	local folder = workspace:WaitForChild("Enemies")
	local function added(child: Instance)
		if child:IsA("Model") and child:GetAttribute("Boss") then
			task.spawn(track, child)
		end
	end
	folder.ChildAdded:Connect(added)
	for _, child in folder:GetChildren() do
		added(child)
	end

	RunService.PreRender:Connect(function(dt)
		local camera = workspace.CurrentCamera
		for _, boss in tracked do
			if camera and (boss.root.Position - camera.CFrame.Position).Magnitude <= ANIMATE_RANGE then
				step(boss, dt)
			end
		end
	end)
end

return BossAnimator
