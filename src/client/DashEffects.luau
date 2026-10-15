--!strict
-- What a dash looks and sounds like: a puff of dust at the feet, a whoosh, a pale neon
-- afterimage of the character left behind that fades out, and the body dropping low and
-- leaning hard along the dash for exactly as long as its i-frames last, then snapping
-- upright, so a dodge (and its invincible window) reads clearly. Your own dash plays here as soon as you press it (see Dash); other
-- players' dashes arrive from the server (DashEffect, see DashService).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local DUST_COLOR = Color3.fromRGB(170, 160, 145)
local DUST_COUNT = 10
local GHOST_COLOR = Color3.fromRGB(150, 210, 255)
local GHOST_START_TRANSPARENCY = 0.5
local GHOST_FADE_TIME = 0.35
-- The dash pose, laid over whatever animations are playing: hips dropped, the body leaning
-- toward the dash (any direction, e.g. sideways while locked on), knees bent.
local POSE_DROP = 0.55 -- studs the hips sink
local POSE_LEAN = math.rad(30)
local POSE_HIP = math.rad(35) -- thighs swung forward
local POSE_KNEE = math.rad(-65) -- knees bent back
local POSE_ANKLE = math.rad(30)
local POSE_IN = 0.04 -- seconds to drop into it
local POSE_OUT = 0.05 -- seconds to snap upright once the i-frames end
local MIN_DASH_SPEED = 5 -- below this the lean keeps its last direction

local dashEffectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DashEffect") :: RemoteEvent

local DashEffects = {}

local function dust(root: BasePart, humanoid: Humanoid)
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = feet -- particles emit along +Y: up and outward
	Debris:AddItem(attachment, 2)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = DUST_TEXTURE
	emitter.Color = ColorSequence.new(DUST_COLOR)
	emitter.Size = NumberSequence.new(0.8, 2.4)
	emitter.Transparency = NumberSequence.new(0.45, 1)
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(80, 80)
	emitter.Acceleration = Vector3.new(0, -4, 0)
	emitter.Drag = 5
	emitter.Parent = attachment
	emitter:Emit(DUST_COUNT)
end

-- A see-through neon copy of every visible part of `character`, left where it stands.
local function afterimage(character: Model)
	local ghost = Instance.new("Model")
	ghost.Name = "DashAfterimage"
	local parts: { BasePart } = {}
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("BasePart") or descendant.Transparency >= 1 or descendant.Name == "HumanoidRootPart" then
			continue
		end
		local copy = descendant:Clone()
		-- Keep only the shape: drop joints, scripts, decals, textures, effects and sounds.
		for _, child in copy:GetChildren() do
			if child:IsA("SpecialMesh") then
				child.TextureId = ""
			elseif not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		if copy:IsA("MeshPart") then
			copy.TextureID = ""
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Material = Enum.Material.Neon
		copy.Color = GHOST_COLOR
		copy.Transparency = GHOST_START_TRANSPARENCY
		copy.CFrame = descendant.CFrame
		copy.Parent = ghost
		table.insert(parts, copy)
	end
	ghost.Parent = workspace.CurrentCamera -- local to this client
	local fade = TweenInfo.new(GHOST_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in parts do
		TweenService:Create(part, fade, { Transparency = 1 }):Play()
	end
	Debris:AddItem(ghost, GHOST_FADE_TIME)
end

local function motor(character: Model, partName: string, jointName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

-- How long `character`'s dash i-frames last (with its player's Ghost Step; matches DashService).
local function iframeTime(character: Model): number
	local player = Players:GetPlayerFromCharacter(character)
	return CombatConfig.Dash.IFrameTime + (if player then SkillMath.general(player, "DashIFrames") else 0)
end

-- Each character's dash pose in progress; calling it takes the pose off (a new dash replaces it).
local endPose: { [Model]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

-- Holds `character` in the dash pose for its i-frames. The animations set each joint's
-- Transform before Stepped; the pose is laid on top of theirs every frame (and taken back
-- off if no animation rewrote a joint, so it never builds up).
local function dashPose(character: Model, root: BasePart, direction: Vector3?)
	local rootJoint = motor(character, "LowerTorso", "Root")
	if not rootJoint then
		return -- not an R15 body
	end
	local joints: { { joint: Motor6D, angle: number } } = {}
	for _, side in { "Left", "Right" } do
		local legJoints = {
			{ part = `{side}UpperLeg`, name = `{side}Hip`, angle = POSE_HIP },
			{ part = `{side}LowerLeg`, name = `{side}Knee`, angle = POSE_KNEE },
			{ part = `{side}Foot`, name = `{side}Ankle`, angle = POSE_ANKLE },
		}
		for _, entry in legJoints do
			local joint = motor(character, entry.part, entry.name)
			if joint then
				table.insert(joints, { joint = joint, angle = entry.angle })
			end
		end
	end

	local hold = iframeTime(character)
	local started = os.clock()
	local heading = if direction and direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
	-- What we last set each joint to, and the offset we added, to take it back off.
	local applied: { [Motor6D]: { set: CFrame, offset: CFrame } } = {}
	local function lay(joint: Motor6D, offset: CFrame?)
		local base = joint.Transform
		local last = applied[joint]
		if last and base == last.set then
			base = last.offset:Inverse() * base -- nothing rewrote it since: our offset is still on
		end
		if offset then
			local set = offset * base
			joint.Transform = set
			applied[joint] = { set = set, offset = offset }
		else
			joint.Transform = base
			applied[joint] = nil
		end
	end

	local connection: RBXScriptConnection
	local function finish()
		connection:Disconnect()
		lay(rootJoint)
		for _, entry in joints do
			lay(entry.joint)
		end
		if endPose[character] == finish then
			endPose[character] = nil
		end
	end
	local previous = endPose[character]
	if previous then
		previous()
	end
	connection = RunService.Stepped:Connect(function()
		local elapsed = os.clock() - started
		local weight = if elapsed < POSE_IN
			then elapsed / POSE_IN
			elseif elapsed < hold then 1
			else 1 - (elapsed - hold) / POSE_OUT
		if weight <= 0 or not rootJoint.Parent or not root.Parent then
			finish()
			return
		end

		local velocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		if velocity.Magnitude > MIN_DASH_SPEED then
			heading = velocity.Unit
		end
		-- Tip the top of the body toward the dash.
		local localHeading = root.CFrame:VectorToObjectSpace(heading)
		local axis = Vector3.yAxis:Cross(Vector3.new(localHeading.X, 0, localHeading.Z))
		local lean = if axis.Magnitude > 0.01 then CFrame.fromAxisAngle(axis.Unit, POSE_LEAN * weight) else CFrame.identity
		lay(rootJoint, CFrame.new(0, -POSE_DROP * weight, 0) * lean)
		for _, entry in joints do
			lay(entry.joint, CFrame.Angles(entry.angle * weight, 0, 0))
		end
	end)
	endPose[character] = finish
end

-- Shows `character` dashing: dust, whoosh, afterimage, and the dash pose. `direction` is
-- where it's dashing, if known (otherwise its movement shows it).
function DashEffects.play(character: Model, direction: Vector3?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	dust(root, humanoid)
	Sounds.play("DashWhoosh", root)
	afterimage(character)
	dashPose(character, root, direction)
end

function DashEffects.start()
	dashEffectRemote.OnClientEvent:Connect(function(character: Model?)
		if typeof(character) == "Instance" and character:IsA("Model") and character ~= Players.LocalPlayer.Character then
			DashEffects.play(character)
		end
	end)
end

return DashEffects
