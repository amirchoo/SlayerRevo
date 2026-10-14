--!strict
-- Poses players who are cooking at the campfire (the "Cooking" character attribute, set by
-- CookingService): crouched on their heels by the fire, left arm resting on the knee, right
-- hand holding the ladle over the pot, stirring while the "Stirring" attribute is on. Every
-- client poses every cook, so others see it too. It turns the R15 joints after the character's
-- own animations each frame (so it wins over idle and walk). Looks only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EASE = 8 -- how quickly they sink into (and rise out of) the crouch, per second
local STIR_SPEED = 4 -- radians per second round the pot
local JOINT_NAMES = { "Root", "Waist", "Neck", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow" }

local CookingPose = {}

type Joint = Motor6D | AnimationConstraint
type Cook = { character: Model, joints: { [string]: Joint }, amount: number, stir: number }
local cooks: { [Model]: Cook } = {}

local function jointsOf(character: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, descendant in character:GetDescendants() do
		if (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) and table.find(JOINT_NAMES, descendant.Name) then
			joints[descendant.Name] = descendant :: Joint
		end
	end
	return joints
end

-- Blends the joint's own (animated) pose toward `target` by `amount` (0..1).
local function blend(joints: { [string]: Joint }, name: string, target: CFrame, amount: number)
	local joint = joints[name] :: any
	if joint then
		joint.Transform = (joint.Transform :: CFrame):Lerp(target, amount)
	end
end

local function pose(cook: Cook, dt: number, now: number)
	local character = cook.character
	local cooking = character:GetAttribute("Cooking") == true
	local stirring = character:GetAttribute("Stirring") == true
	cook.amount += ((if cooking then 1 else 0) - cook.amount) * math.min(dt * EASE, 1)
	cook.stir += ((if stirring then 1 else 0) - cook.stir) * math.min(dt * EASE, 1)
	local a = cook.amount
	if a < 0.01 then
		if not cooking then
			cooks[character] = nil
		end
		return
	end
	local joints = cook.joints
	local angle = now * STIR_SPEED
	local stir = cook.stir

	-- A low crouch: hips forward, knees folded back, feet flat, body sunk toward the ground.
	blend(joints, "Root", CFrame.new(0, -1.15, 0.35), a)
	blend(joints, "LeftHip", CFrame.Angles(1.45, 0, -0.12), a)
	blend(joints, "RightHip", CFrame.Angles(1.35, 0, 0.12), a)
	blend(joints, "LeftKnee", CFrame.Angles(-2.05, 0, 0), a)
	blend(joints, "RightKnee", CFrame.Angles(-1.95, 0, 0), a)
	blend(joints, "LeftAnkle", CFrame.Angles(0.6, 0, 0), a)
	blend(joints, "RightAnkle", CFrame.Angles(0.6, 0, 0), a)
	-- Leaning in over the pot, eyes on it.
	blend(joints, "Waist", CFrame.Angles(-0.35, 0, 0), a)
	blend(joints, "Neck", CFrame.Angles(-0.3 + math.sin(angle * 0.5) * 0.05 * stir, 0, 0), a)
	-- Left forearm on the knee; right hand out over the pot, circling while stirring.
	blend(joints, "LeftShoulder", CFrame.Angles(0.75, 0, 0.15), a)
	blend(joints, "LeftElbow", CFrame.Angles(0.9, 0, 0), a)
	blend(joints, "RightShoulder", CFrame.Angles(1.15 + math.sin(angle) * 0.18 * stir, math.cos(angle) * 0.2 * stir, -0.1), a)
	blend(joints, "RightElbow", CFrame.Angles(0.55 + math.cos(angle) * 0.15 * stir, 0, 0), a)
end

local function watch(character: Model)
	local function check()
		if character:GetAttribute("Cooking") == true and not cooks[character] then
			cooks[character] = { character = character, joints = jointsOf(character), amount = 0, stir = 0 }
		end
	end
	character:GetAttributeChangedSignal("Cooking"):Connect(check)
	check()
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

function CookingPose.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			cooks[player.Character] = nil
		end
	end)
	-- After the characters' own animations have posed them this frame.
	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		for character, cook in cooks do
			if character.Parent then
				pose(cook, dt, now)
			else
				cooks[character] = nil
			end
		end
	end)
end

return CookingPose
