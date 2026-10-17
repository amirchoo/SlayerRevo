--!strict
-- What a dash looks and sounds like: a puff of dust at the feet, a whoosh, pale white
-- afterimages of the character trailing behind it and fading out, and a body dash: the body snaps
-- low and leans hard into the dash (forward, sideways or back), legs split like a sprinter's
-- lunge when going forward (bent when going sideways or back), holds it while it travels, then
-- eases back up, so a dodge reads clearly. Your own dash plays here as soon as you press it (see Dash); other
-- players' dashes arrive from the server (DashEffect, see DashService).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Quality = require(script.Parent.Quality)

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local DUST_COLOR = Color3.fromRGB(170, 160, 145)
local DUST_COUNT = 10
local AFTERIMAGE = CombatConfig.Dash.Afterimages
-- The dash pose, laid over whatever animations are playing (all on this screen only).
local POSE_IN = 0.05 -- seconds to snap into it
local POSE_HOLD = 0.2 -- seconds held while the dash travels (about Dash.Duration)
local POSE_OUT = 0.16 -- seconds to ease back upright
local POSE_DROP = 0.6 -- studs the hips sink
local POSE_LEAN = math.rad(32) -- whole body tipped toward the dash
local POSE_SPINE = math.rad(12) -- the chest curls a little further over
-- Legs, (hip, knee, ankle) in degrees: split like a sprinter's lunge when dashing forward
-- (left leads, right pushes off behind), both bent when dashing sideways or back.
local LEAD_LEG = { 55, -75, 20 }
local TRAIL_LEG = { -35, -30, 35 }
local BENT_LEG = { 35, -65, 30 }
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
	emitter:Emit(math.max(1, math.round(DUST_COUNT * Quality.settings().Particles)))
end

-- Afterimages: see-through copies of the dasher left behind as it travels (CombatConfig
-- Dash.Afterimages). Each character gets a small pool of ghost bodies, cloned once on its first
-- dash and reused after that (just moved into place and faded), so a dash clones nothing.
-- A pool is rebuilt only when the character's parts change (armor or weapon swapped).
type Ghost = { model: Model, copies: { BasePart }, sources: { BasePart }, shown: { BasePart }, started: number }
type Pool = { ghosts: { Ghost }, nextGhost: number, dirty: boolean, connections: { RBXScriptConnection } }

local pools: { [Model]: Pool } = {}
local fading: { [Ghost]: true } = {}
local fadeConnection: RBXScriptConnection? = nil

-- A shape-only, anchored copy of `source` in the afterimage look, or nil if it can't be cloned.
local function ghostCopy(source: BasePart): BasePart?
	local archivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = archivable
	if not copy then
		return nil
	end
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
	copy.Color = AFTERIMAGE.Color
	copy.Transparency = 1
	return copy
end

local function buildGhost(character: Model): Ghost
	local ghost: Ghost = { model = Instance.new("Model"), copies = {}, sources = {}, shown = {}, started = 0 }
	ghost.model.Name = "DashAfterimage"
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			local copy = ghostCopy(descendant)
			if copy then
				copy.Parent = ghost.model
				table.insert(ghost.copies, copy)
				table.insert(ghost.sources, descendant)
			end
		end
	end
	return ghost
end

local function dropPool(character: Model)
	local pool = pools[character]
	if not pool then
		return
	end
	pools[character] = nil
	for _, connection in pool.connections do
		connection:Disconnect()
	end
	for _, ghost in pool.ghosts do
		fading[ghost] = nil
		ghost.model:Destroy()
	end
end

local function poolFor(character: Model): Pool
	local pool = pools[character]
	if pool and pool.dirty then
		dropPool(character)
		pool = nil
	end
	if pool then
		return pool
	end
	local newPool: Pool = { ghosts = {}, nextGhost = 1, dirty = false, connections = {} }
	local function partsChanged(descendant: Instance)
		if descendant:IsA("BasePart") then
			newPool.dirty = true
		end
	end
	table.insert(newPool.connections, character.DescendantAdded:Connect(partsChanged))
	table.insert(newPool.connections, character.DescendantRemoving:Connect(partsChanged))
	table.insert(
		newPool.connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(game) then
				dropPool(character)
			end
		end)
	)
	pools[character] = newPool
	return newPool
end

local function fadeStep()
	local now = os.clock()
	for ghost in fading do
		local t = (now - ghost.started) / AFTERIMAGE.Fade
		if t >= 1 then
			fading[ghost] = nil
			ghost.model.Parent = nil
			continue
		end
		local eased = 1 - (1 - t) * (1 - t) -- quick at first, like a Quad out
		local transparency = AFTERIMAGE.StartTransparency + (1 - AFTERIMAGE.StartTransparency) * eased
		for _, copy in ghost.shown do
			copy.Transparency = transparency
		end
	end
	if next(fading) == nil and fadeConnection then
		fadeConnection:Disconnect()
		fadeConnection = nil
	end
end

-- Leaves one afterimage of `character` where it is now, from its pool.
local function afterimage(character: Model)
	if not character:IsDescendantOf(workspace) then
		return
	end
	local pool = poolFor(character)
	local ghost = pool.ghosts[pool.nextGhost]
	if not ghost then
		ghost = buildGhost(character)
		pool.ghosts[pool.nextGhost] = ghost
	end
	pool.nextGhost = pool.nextGhost % AFTERIMAGE.MaxCount + 1

	-- Line every copy up with its part; parts hidden right now stay hidden in the copy.
	local moved: { BasePart } = {}
	local cframes: { CFrame } = {}
	table.clear(ghost.shown)
	for i, copy in ghost.copies do
		local source = ghost.sources[i]
		if source.Transparency < 1 and source:IsDescendantOf(character) then
			table.insert(moved, copy)
			table.insert(cframes, source.CFrame)
			table.insert(ghost.shown, copy)
			copy.Transparency = AFTERIMAGE.StartTransparency
		else
			copy.Transparency = 1
		end
	end
	workspace:BulkMoveTo(moved, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	ghost.model.Parent = workspace.CurrentCamera -- local to this client
	ghost.started = os.clock()
	fading[ghost] = true
	if not fadeConnection then
		fadeConnection = RunService.Heartbeat:Connect(fadeStep)
	end
end

-- Leaves a trail of afterimages along the dash: one now, then one every Interval while it
-- travels (as many as the quality tier allows). Taken on Heartbeat, so they show the dash pose.
local function afterimageTrail(character: Model)
	local count = math.min(Quality.settings().Afterimages, AFTERIMAGE.MaxCount)
	if count <= 0 then
		return
	end
	afterimage(character)
	for i = 1, count - 1 do
		task.delay(AFTERIMAGE.Interval * i, afterimage, character)
	end
end

-- An animated body joint: a Motor6D, or an AnimationConstraint (newer avatars use those).
type Joint = Motor6D | AnimationConstraint

local function motor(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	return if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then joint :: Joint else nil
end

local function getTransform(joint: Joint): CFrame
	return if joint:IsA("Motor6D") then joint.Transform else (joint :: AnimationConstraint).Transform
end

local function setTransform(joint: Joint, transform: CFrame)
	if joint:IsA("Motor6D") then
		joint.Transform = transform
	else
		(joint :: AnimationConstraint).Transform = transform
	end
end

-- Each character's dash pose in progress; calling it takes the pose off (a new dash replaces it).
local endPose: { [Model]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

-- Holds `character` in the dash pose (see POSE_*). The animations set each joint's
-- Transform before Stepped; the pose is laid on top of theirs every frame (and taken back
-- off if no animation rewrote a joint, so it never builds up).
local function dashPose(character: Model, root: BasePart, direction: Vector3?)
	local rootJoint = motor(character, "LowerTorso", "Root")
	if not rootJoint then
		return -- not an R15 body
	end
	-- Each leg joint with its angle (radians) in the forward split and in the bent stance.
	local joints: { { joint: Joint, split: number, bent: number } } = {}
	for _, side in { "Left", "Right" } do
		local split = if side == "Left" then LEAD_LEG else TRAIL_LEG
		local legJoints = {
			{ part = `{side}UpperLeg`, name = `{side}Hip`, index = 1 },
			{ part = `{side}LowerLeg`, name = `{side}Knee`, index = 2 },
			{ part = `{side}Foot`, name = `{side}Ankle`, index = 3 },
		}
		for _, entry in legJoints do
			local joint = motor(character, entry.part, entry.name)
			if joint then
				table.insert(joints, { joint = joint, split = math.rad(split[entry.index]), bent = math.rad(BENT_LEG[entry.index]) })
			end
		end
	end
	local waist = motor(character, "UpperTorso", "Waist")

	local started = os.clock()
	local heading = if direction and direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
	-- What we last set each joint to, and the offset we added, to take it back off.
	local applied: { [Joint]: { set: CFrame, offset: CFrame } } = {}
	local function lay(joint: Joint, offset: CFrame?)
		local base = getTransform(joint)
		local last = applied[joint]
		-- Compared loosely: an AnimationConstraint hands back a hair off what was set, and an
		-- exact check would stack the offset again every frame until the body spins over.
		if last and base:FuzzyEq(last.set, 1e-4) then
			base = last.offset:Inverse() * base -- nothing rewrote it since: our offset is still on
		end
		if offset then
			local set = offset * base
			setTransform(joint, set)
			applied[joint] = { set = set, offset = offset }
		else
			setTransform(joint, base)
			applied[joint] = nil
		end
	end

	local connection: RBXScriptConnection
	local function finish()
		connection:Disconnect()
		lay(rootJoint)
		if waist then
			lay(waist)
		end
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
		if elapsed >= POSE_IN + POSE_HOLD + POSE_OUT or not rootJoint.Parent or not root.Parent then
			finish()
			return
		end
		local weight
		if elapsed < POSE_IN then
			weight = elapsed / POSE_IN
		elseif elapsed < POSE_IN + POSE_HOLD then
			weight = 1
		else
			local v = math.clamp((elapsed - POSE_IN - POSE_HOLD) / POSE_OUT, 0, 1)
			weight = 1 - v * v * (3 - 2 * v) -- eases back up
		end
		if weight <= 0 then
			finish()
			return
		end

		local velocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		if velocity.Magnitude > MIN_DASH_SPEED then
			heading = velocity.Unit
		end
		-- Tip the body toward the dash; the more it's going forward, the more the legs split.
		local localHeading = root.CFrame:VectorToObjectSpace(heading)
		local flatHeading = Vector3.new(localHeading.X, 0, localHeading.Z)
		local forward = if flatHeading.Magnitude > 0.01 then math.max(0, -flatHeading.Unit.Z) else 1
		local axis = Vector3.yAxis:Cross(flatHeading)
		local function tip(angle: number): CFrame
			return if axis.Magnitude > 0.01 then CFrame.fromAxisAngle(axis.Unit, angle) else CFrame.identity
		end
		lay(rootJoint, CFrame.new(0, -POSE_DROP * weight, 0) * tip(POSE_LEAN * weight))
		if waist then
			lay(waist, tip(POSE_SPINE * weight))
		end
		for _, entry in joints do
			local angle = entry.bent + (entry.split - entry.bent) * forward
			lay(entry.joint, CFrame.Angles(angle * weight, 0, 0))
		end
	end)
	endPose[character] = finish
end

-- Shows `character` dashing: dust, whoosh, afterimages, and the dash pose. `direction` is
-- where it's dashing, if known (otherwise its movement shows it).
function DashEffects.play(character: Model, direction: Vector3?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	dust(root, humanoid)
	Sounds.play("DashWhoosh", root)
	afterimageTrail(character)
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
