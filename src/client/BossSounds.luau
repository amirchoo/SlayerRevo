--!strict
-- A boss's voice and attack sounds on this screen (BossConfig Sounds and each attack's cues,
-- names in shared/Sounds), played from the boss so they're loud up close. Sounds only: it
-- follows the attributes BossService sets on the model:
--   BossState Intro: Roar; Dead: Death.  Phase going up: Enrage (furious, enraged).
--   BossAction: an attack's clip plays its cues on time (scaled by BossActionSpeed; a new
--     action cancels the rest), the Stunned clip its Stunned groan.
--   Health going down: Hurt, at most every HURT_GAP seconds, not while attacking or down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local HURT_GAP = 0.9 -- seconds between hurt grunts
local ROLL_OFF_MAX = 260 -- studs: a boss is heard across its arena and beyond

local BossSounds = {}

local watched: { [Model]: boolean } = {}

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function play(model: Model, name: string?)
	if not name then
		return
	end
	local root = rootOf(model)
	if not root then
		return
	end
	local sound = Sounds.create(name, root)
	if not sound then
		return
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = ROLL_OFF_MAX
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function watch(model: Model)
	if watched[model] or not model:GetAttribute("Boss") then
		return
	end
	local config = (BossConfig :: any)[model:GetAttribute("BossId")] :: BossConfig.Boss?
	if not config then
		return
	end
	watched[model] = true
	local voice = config.Sounds
	local attacksByClip: { [string]: BossConfig.Attack } = {}
	for _, attack in config.Attacks do
		attacksByClip[attack.Clip] = attack
	end

	local actionToken = 0
	local lastHurt = 0
	local phase = model:GetAttribute("Phase")
	local health = model:GetAttribute("Health")

	local function onAction()
		actionToken += 1
		local token = actionToken
		local clip = model:GetAttribute("BossAction")
		if clip == config.Animations.Stunned then
			play(model, voice.Stunned)
			return
		end
		local attack = if typeof(clip) == "string" then attacksByClip[clip] else nil
		if not attack or not attack.Sounds then
			return
		end
		local speed = model:GetAttribute("BossActionSpeed")
		speed = if typeof(speed) == "number" and speed > 0 then speed else 1
		for _, cue in attack.Sounds do
			task.delay(cue.At / speed, function()
				if actionToken == token and model.Parent then
					play(model, cue.Sound)
				end
			end)
		end
	end

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, model:GetAttributeChangedSignal("BossActionAt"):Connect(onAction))
	table.insert(connections, model:GetAttributeChangedSignal("BossState"):Connect(function()
		local state = model:GetAttribute("BossState")
		if state == "Intro" then
			play(model, voice.Roar)
		elseif state == "Dead" then
			actionToken += 1
			play(model, voice.Death)
		end
	end))
	table.insert(connections, model:GetAttributeChangedSignal("Phase"):Connect(function()
		local now = model:GetAttribute("Phase")
		if typeof(now) == "number" and typeof(phase) == "number" and now > phase then
			play(model, voice.Enrage)
		end
		phase = now
	end))
	table.insert(connections, model:GetAttributeChangedSignal("Health"):Connect(function()
		local now = model:GetAttribute("Health")
		local dropped = typeof(now) == "number" and typeof(health) == "number" and now < health
		health = now
		local action = model:GetAttribute("BossAction")
		local busy = typeof(action) == "string" and action ~= "" and action ~= config.Animations.Hurt
		if dropped and not busy and model:GetAttribute("BossState") == "Fight" and os.clock() - lastHurt >= HURT_GAP then
			lastHurt = os.clock()
			play(model, voice.Hurt)
		end
	end))
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			watched[model] = nil
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end)
end

function BossSounds.start()
	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies")
		enemies.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Its attributes may land a moment after it does.
				task.defer(watch, child)
				child:GetAttributeChangedSignal("Boss"):Once(function()
					watch(child)
				end)
			end
		end)
		for _, child in enemies:GetChildren() do
			if child:IsA("Model") then
				watch(child)
			end
		end
	end)
end

return BossSounds
