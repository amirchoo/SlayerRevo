--!strict
-- Caster weapon input and visuals (the staff, the grimoire: one controller each, from
-- CombatConfig.Casters; see StaffService for what the spells do).
--   Attack, tapped: cast a light missile at your aim (Aim: lock-on target, mouse, or screen
--     centre). Held past HoldTime: charge a blast (the staff is raised and sparks in the
--     element's colour gather at its tip, with a chime at full charge); let go to release it.
--   Spells spend mana (see ManaService), not stamina.
--   Block (held): guard, like any weapon.
--   R, or clicking/tapping an element in the bar above the meters: switch element.
-- The element bar (the unlocked elements, the current one highlighted) shows only while the
-- caster is in hand and at least one element is unlocked. Spells need the caster's class and
-- the element unlocked in its skill tree (SkillMath.spellUnlocked); until then a hint says what
-- to unlock. A heavy release also names the lock-on target (homing spells go for it first).
-- The server times charges and decides every hit; this is input and feedback.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Stamina = require(ReplicatedStorage.Shared.Stamina)
local Aim = require(script.Parent.Aim)
local SkillTrees = require(ReplicatedStorage.Shared.Config.SkillTrees)
local CombatInput = require(script.Parent.CombatInput)
local HudStyle = require(script.Parent.HudStyle)
local LockOn = require(script.Parent.LockOn)

type Caster = typeof(CombatConfig.Staff)

local BLOCK = CombatConfig.Blocking
local ELEMENT_ICON_SIZE = 36
local ELEMENT_GAP = 8
local ELEMENT_BAR_BOTTOM = -208 -- above the dash and block meters
-- Aiming with the free hand (AimWithHand): how long after a cast or release the hand stays on
-- the target, how fast the aim eases in and out (per second), and how far the arm and head
-- may be turned past the animation (radians).
local AIM_HOLD = 0.45
local AIM_EASE = 10
local AIM_ARM_LIMIT = math.rad(70)
local AIM_HEAD_LIMIT = math.rad(55)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local elementRemote = remotes:WaitForChild("StaffElement") :: RemoteEvent
local castRemote = remotes:WaitForChild("StaffCast") :: RemoteEvent
local chargeRemote = remotes:WaitForChild("StaffCharge") :: RemoteEvent
local releaseRemote = remotes:WaitForChild("StaffRelease") :: RemoteEvent
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent

local StaffClient = {}

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animation
end

-- An animated body joint: a Motor6D, or an AnimationConstraint (newer avatars use those),
-- with where it sits on its Part0 (c0) and Part1 (c1).
type Joint = { object: Motor6D | AnimationConstraint, c0: CFrame, c1: CFrame }

local function jointIn(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local object = part and part:FindFirstChild(jointName)
	if object and object:IsA("Motor6D") then
		return { object = object, c0 = object.C0, c1 = object.C1 }
	elseif object and object:IsA("AnimationConstraint") and object.Attachment0 and object.Attachment1 then
		return { object = object, c0 = object.Attachment0.CFrame, c1 = object.Attachment1.CFrame }
	end
	return nil
end

local function getTransform(joint: Joint): CFrame
	local object = joint.object
	return if object:IsA("Motor6D") then object.Transform else (object :: AnimationConstraint).Transform
end

local function setTransform(joint: Joint, transform: CFrame)
	local object = joint.object
	if object:IsA("Motor6D") then
		object.Transform = transform
	else
		(object :: AnimationConstraint).Transform = transform
	end
end

-- Where a joint's Part1 is this frame, from its Part0 and the animation's Transform (the
-- parts themselves still show last frame's pose during Stepped).
local function partAfter(joint: Joint, part0: CFrame): CFrame
	return part0 * joint.c0 * getTransform(joint) * joint.c1:Inverse()
end

-- Turns a joint's Part1 (and everything below it) about the joint, by the world rotation
-- taking direction `from` to `to`: at most `limit` radians, scaled by `weight`.
local function turnJoint(joint: Joint, part0: CFrame, from: Vector3, to: Vector3, limit: number, weight: number)
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-4 then
		return
	end
	local angle = math.min(math.acos(math.clamp(from:Dot(to), -1, 1)), limit) * weight
	local frame = part0 * joint.c0
	local transform = getTransform(joint)
	local pivot = (frame * transform).Position
	local rotation = CFrame.new(pivot) * CFrame.fromAxisAngle(axis.Unit, angle) * CFrame.new(-pivot)
	setTransform(joint, frame:Inverse() * rotation * frame * transform)
end

-- Creates the controller for one caster weapon; call :start() once on the client.
function StaffClient.new(STAFF: Caster)
	local TREE = SkillTrees.Casters[STAFF.ToolName]
	local CLASS = TREE.ClassNode.Name
	local ELEMENT_ATTRIBUTE = `{STAFF.ToolName}Element`

	local ANIMATIONS = {
		idle = makeAnimation(STAFF.IdleAnimation),
		cast = makeAnimation(STAFF.CastAnimation),
		charge = makeAnimation(STAFF.ChargeAnimation),
		blast = makeAnimation(STAFF.BlastAnimation),
		slam = makeAnimation(STAFF.SlamAnimation),
		guard = makeAnimation(STAFF.GuardAnimation),
	}

	type Tracks = { [string]: AnimationTrack }
	local tracksByHumanoid: { [Humanoid]: Tracks } = setmetatable({}, { __mode = "k" }) :: any

	local function getTracks(humanoid: Humanoid): Tracks
		local cached = tracksByHumanoid[humanoid]
		if cached then
			return cached
		end
		local tracks: Tracks = {}
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for name, animation in ANIMATIONS do
				if animation then
					local track = animator:LoadAnimation(animation)
					-- The idle is Movement, not Idle: Roblox's own "mood" animation plays at Idle and
					-- would win the arms (dropping the book). It still yields to the Action spells.
					track.Priority = if name == "idle" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
					track.Looped = name == "idle" or name == "guard"
					tracks[name] = track
				end
			end
		end
		tracksByHumanoid[humanoid] = tracks
		return tracks
	end

	type Equipped = { tool: Tool, humanoid: Humanoid, tracks: Tracks, baseWalkSpeed: number }
	local equipped: Equipped? = nil
	local pressedAt: number? = nil
	local stopCharge: ((released: boolean) -> ())? = nil
	local stopGuard: (() -> ())? = nil
	local lastCast = 0
	local lastBlast = 0
	local aimingUntil = 0 -- casters with AimWithHand: aim the hand at the target until then

	local function missileIgnore(): { Instance }?
		local folder = workspace:FindFirstChild("StaffMissiles")
		return if folder then { folder } else nil
	end

	-- The element spells will use: the chosen one if unlocked, else the first unlocked one (as
	-- the server does), or nil if none is.
	local function currentElementName(): string?
		local name = player:GetAttribute(ELEMENT_ATTRIBUTE)
		if typeof(name) == "string" and SkillMath.spellUnlocked(player, STAFF.ToolName, name) then
			return name
		end
		for _, element in STAFF.Elements do
			if SkillMath.spellUnlocked(player, STAFF.ToolName, element.Name) then
				return element.Name
			end
		end
		return nil
	end

	-- A short message under the crosshair (e.g. what to unlock).
	local hintLabel: TextLabel? = nil
	local hintToken = 0
	local function showHint(text: string)
		local label = hintLabel
		if not label then
			return
		end
		hintToken += 1
		local mine = hintToken
		label.Text = text
		label.Visible = true
		task.delay(2, function()
			if mine == hintToken then
				label.Visible = false
			end
		end)
	end

	-- True if a spell can be cast now; otherwise says what still needs unlocking.
	local function canCastAnything(): boolean
		if not SkillMath.spellUnlocked(player, STAFF.ToolName) then
			showHint(`Unlock the {CLASS} class in the {STAFF.ToolName} skill tree (K) to cast spells`)
			return false
		elseif not currentElementName() then
			showHint(`Unlock an element in the {STAFF.ToolName} skill tree (K)`)
			return false
		end
		return true
	end

	local function cast(state: Equipped)
		local now = os.clock()
		if now - lastCast < STAFF.CastCooldown or now - lastBlast < STAFF.Recovery * 0.5 then
			return
		end
		if not Stamina.canAfford(player, SkillMath.staminaCost(player, STAFF.ToolName, STAFF.CastMana, "Light"), "Mana") then
			return
		end
		lastCast = now
		aimingUntil = now + AIM_HOLD
		castRemote:FireServer(Aim.point(missileIgnore()))
		local track = state.tracks.cast
		if track then
			track:Play(0.05)
		end
		task.delay(STAFF.CastDelay, function()
			if equipped == state then
				Sounds.play("StaffCast", state.humanoid.Parent and state.humanoid.Parent:FindFirstChild("HumanoidRootPart") or workspace.CurrentCamera)
			end
		end)
	end

	local function elementColor(): Color3
		local name = currentElementName() or ""
		for _, element in STAFF.Elements do
			if element.Name == name then
				return element.Color
			end
		end
		return Color3.new(1, 1, 1)
	end

	-- Sparks gathering at the staff's tip while charging (only on this screen).
	local function chargeSparks(tool: Tool): ParticleEmitter?
		local tip = tool:FindFirstChild("Tip", true)
		if not tip or not tip:IsA("Attachment") then
			return nil
		end
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(elementColor())
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.35, 0)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(0.25, 0.45)
		sparks.Speed = NumberRange.new(2, 5)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 10
		sparks.Parent = tip
		return sparks
	end

	local function startCharge(state: Equipped)
		chargeRemote:FireServer(LockOn.target()) -- remembered in case the charge times out
		local started = os.clock()
		local chargeSpeed = 1 + SkillMath.weapon(player, STAFF.ToolName, "ChargeSpeed") -- matches StaffService
		local sparks = chargeSparks(state.tool)
		local charge = state.tracks.charge
		if charge then
			charge:Play(0.1)
		end
		state.humanoid.WalkSpeed = STAFF.ChargeWalkSpeed
		local full = false
		local connection = RunService.RenderStepped:Connect(function()
			local power = math.clamp((os.clock() - started) * chargeSpeed / STAFF.FullChargeTime, 0, 1)
			-- Hold the raised pose on its last frame.
			if charge and charge.IsPlaying and charge.Speed > 0 and charge.Length > 0 and charge.TimePosition >= charge.Length - 0.05 then
				charge:AdjustSpeed(0)
			end
			-- More and bigger sparks as power builds.
			if sparks then
				sparks.Rate = 10 + power * 60
				sparks.Size = NumberSequence.new(0.35 + power * 0.5, 0)
			end
			if power >= 1 and not full then
				full = true
				Sounds.play("ChargeLevel", workspace.CurrentCamera, 1.7)
			end
		end)

		stopCharge = function(released: boolean)
			stopCharge = nil
			connection:Disconnect()
			if sparks then
				sparks.Enabled = false
				game:GetService("Debris"):AddItem(sparks, 0.5)
			end
			if charge then
				charge:Stop(if released then 0.05 else 0.2)
			end
			state.humanoid.WalkSpeed = state.baseWalkSpeed
			if not released then
				return
			end
			lastBlast = os.clock()
			aimingUntil = lastBlast + AIM_HOLD
			releaseRemote:FireServer(Aim.point(missileIgnore()), LockOn.target())
			-- Fire slams the staff into the ground; the others thrust it forward.
			local slams = false
			for _, element in STAFF.Elements do
				if element.Name == currentElementName() then
					slams = element.Heavy.Kind == "FireWave"
				end
			end
			local blast = if slams then state.tracks.slam or state.tracks.blast else state.tracks.blast
			if blast then
				blast:Play(0.05)
			end
			task.delay(STAFF.BlastDelay, function()
				if equipped == state then
					Sounds.play("StaffBlast", workspace.CurrentCamera)
				end
			end)
		end
	end

	local function startGuard(state: Equipped)
		blockRemote:FireServer(true)
		local guard = state.tracks.guard
		if guard then
			guard:Play(0.1)
		end
		state.humanoid.WalkSpeed = BLOCK.WalkSpeed
		stopGuard = function()
			stopGuard = nil
			blockRemote:FireServer(false)
			if guard then
				guard:Stop(0.15)
			end
			state.humanoid.WalkSpeed = state.baseWalkSpeed
		end
	end

	local function onAttackBegan()
		local state = equipped
		if not state or stopCharge or stopGuard then
			return
		end
		if not canCastAnything() then
			return
		end
		local pressed = os.clock()
		pressedAt = pressed
		task.delay(STAFF.HoldTime, function()
			if pressedAt ~= pressed or equipped ~= state or stopCharge or stopGuard then
				return
			end
			pressedAt = nil
			if os.clock() - lastBlast < STAFF.Recovery then
				return
			end
			if Stamina.canAfford(player, SkillMath.staminaCost(player, STAFF.ToolName, STAFF.ChargeMana, "Heavy"), "Mana") then
				startCharge(state)
			end
		end)
	end

	local function onAttackEnded()
		if stopCharge then
			stopCharge(true)
		elseif pressedAt then
			local held = os.clock() - pressedAt
			pressedAt = nil
			local state = equipped
			if state and held < STAFF.HoldTime and not stopGuard then
				cast(state) -- a quick tap
			end
		end
	end

	-- Aiming with the free hand (AimWithHand) --------------------------------------------------------
	-- While a spell is cast (and for AIM_HOLD after), the body turns to face the aim and the head
	-- and right arm are turned the rest of the way onto it, on top of the animations; with a
	-- lock-on target the head also looks up from the book at it between casts. Runs in Stepped,
	-- after the animations have set this frame's joints. Only this screen sees the extra turn.

	local armWeight, headWeight = 0, 0
	local turning = false -- the body is being turned to the aim (AutoRotate off)
	-- A joint's animated Transform, and what we last wrote over it: if nothing has animated the
	-- joint since, the animated value is put back first, so turns never pile up frame on frame.
	local animated: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
	local written: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

	local function resetJoint(joint: Joint?)
		if not joint then
			return
		end
		local object = joint.object
		if written[object] and getTransform(joint) == written[object] then
			setTransform(joint, animated[object])
		else
			animated[object] = getTransform(joint)
		end
	end

	local function remember(joint: Joint)
		written[joint.object] = getTransform(joint)
	end

	local function stepAim(dt: number)
		local state = equipped
		local aiming = state ~= nil and (stopCharge ~= nil or os.clock() < aimingUntil)
		local watching = state ~= nil and LockOn.target() ~= nil
		local ease = math.min(dt * AIM_EASE, 1)
		armWeight += ((if aiming then 1 else 0) - armWeight) * ease
		headWeight += ((if aiming or watching then 1 else 0) - headWeight) * ease

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if turning and (not aiming or not humanoid) then
			turning = false
			if humanoid then
				humanoid.AutoRotate = true
			end
		end
		if not character or not humanoid then
			return
		end
		local neck = jointIn(character, "Head", "Neck")
		local shoulder = jointIn(character, "RightUpperArm", "RightShoulder")
		resetJoint(neck)
		resetJoint(shoulder)
		local root = character:FindFirstChild("HumanoidRootPart")
		local rootJoint = jointIn(character, "LowerTorso", "Root")
		local waist = jointIn(character, "UpperTorso", "Waist")
		local elbow = jointIn(character, "RightLowerArm", "RightElbow")
		local wrist = jointIn(character, "RightHand", "RightWrist")
		if not state or headWeight < 0.01 or not root or not root:IsA("BasePart") then
			return
		end
		if not rootJoint or not waist or not neck or not shoulder or not elbow or not wrist then
			return
		end

		local aim = Aim.point(missileIgnore())
		if aiming then
			-- Face it (flat), like drawing a bow.
			local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
			if flat.Magnitude > 0.1 then
				turning = true
				humanoid.AutoRotate = false
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			end
		end

		local upperTorso = partAfter(waist, partAfter(rootJoint, root.CFrame))
		if armWeight > 0.01 then
			local upperArm = partAfter(shoulder, upperTorso)
			local hand = partAfter(wrist, partAfter(elbow, upperArm))
			local from = (upperTorso * shoulder.c0 * getTransform(shoulder)).Position
			local reach = hand.Position - from
			local toAim = aim - from
			if reach.Magnitude > 0.1 and toAim.Magnitude > 0.1 then
				turnJoint(shoulder, upperTorso, reach.Unit, toAim.Unit, AIM_ARM_LIMIT, armWeight)
				remember(shoulder)
			end
		end
		local head = partAfter(neck, upperTorso)
		local toTarget = aim - head.Position
		if toTarget.Magnitude > 0.1 then
			turnJoint(neck, upperTorso, head.LookVector, toTarget.Unit, AIM_HEAD_LIMIT, headWeight)
			remember(neck)
		end
	end

	-- The element bar -----------------------------------------------------------------------------

	local elementBar: Frame? = nil
	type ElementIcon = { name: string, frame: Frame }
	local elementIcons: { ElementIcon } = {}

	local function selectElement(name: string)
		if not SkillMath.spellUnlocked(player, STAFF.ToolName) then
			showHint(`Unlock the {CLASS} class in the {STAFF.ToolName} skill tree (K) first`)
			return
		elseif not SkillMath.spellUnlocked(player, STAFF.ToolName, name) then
			showHint(`Unlock {name} in the {STAFF.ToolName} skill tree (K)`)
			return
		end
		elementRemote:FireServer(name)
	end

	-- The next unlocked element after the current one.
	local function cycleElement()
		if not canCastAnything() then
			return
		end
		local current = currentElementName()
		local start = 1
		for index, element in STAFF.Elements do
			if element.Name == current then
				start = index
			end
		end
		for step = 1, #STAFF.Elements do
			local element = STAFF.Elements[(start - 1 + step) % #STAFF.Elements + 1]
			if SkillMath.spellUnlocked(player, STAFF.ToolName, element.Name) then
				if element.Name ~= current then
					elementRemote:FireServer(element.Name)
				end
				return
			end
		end
	end

	local staffInHand = false
	local elementHint: TextLabel? = nil

	-- Shows only the unlocked elements, side by side and centred; hidden while none is unlocked
	-- (or the staff isn't in hand). The switch hint appears once there's more than one.
	local function updateElementBar()
		local bar = elementBar
		if not bar then
			return
		end
		local current = currentElementName()
		local shown = 0
		for _, icon in elementIcons do
			local unlocked = SkillMath.spellUnlocked(player, STAFF.ToolName, icon.name)
			icon.frame.Visible = unlocked
			if unlocked then
				icon.frame.Position = UDim2.fromOffset(shown * (ELEMENT_ICON_SIZE + ELEMENT_GAP), 0)
				shown += 1
				local stroke = icon.frame:FindFirstChildOfClass("UIStroke")
				local selected = icon.name == current
				icon.frame.BackgroundTransparency = if selected then 0 else 0.55
				if stroke then
					stroke.Color = if selected then Color3.new(1, 1, 1) else HudStyle.OUTLINE
					stroke.Thickness = if selected then 4 else 3
				end
				if selected then
					HudStyle.pop(icon.frame, 1.2)
				end
			end
		end
		bar.Size = UDim2.fromOffset(math.max(shown * ELEMENT_ICON_SIZE + (shown - 1) * ELEMENT_GAP, 0), ELEMENT_ICON_SIZE + 16)
		bar.Visible = staffInHand and shown > 0
		if elementHint then
			elementHint.Visible = shown > 1
		end
	end

	local function buildElementBar()
		local gui = Instance.new("ScreenGui")
		gui.Name = `{STAFF.ToolName}Elements`
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		local count = #STAFF.Elements
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, ELEMENT_BAR_BOTTOM)
		bar.Size = UDim2.fromOffset(count * ELEMENT_ICON_SIZE + (count - 1) * ELEMENT_GAP, ELEMENT_ICON_SIZE + 16)
		bar.BackgroundTransparency = 1
		bar.Visible = false
		bar.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))
		elementBar = bar
		for index, element in STAFF.Elements do
			local badge = HudStyle.badge(bar, ELEMENT_ICON_SIZE, element.Color, element.Icon)
			badge.Position = UDim2.fromOffset((index - 1) * (ELEMENT_ICON_SIZE + ELEMENT_GAP), 0)
			local button = Instance.new("TextButton")
			button.Size = UDim2.fromScale(1, 1)
			button.BackgroundTransparency = 1
			button.Text = ""
			button.ZIndex = 3
			button.Parent = badge
			button.Activated:Connect(function()
				selectElement(element.Name)
			end)
			table.insert(elementIcons, { name = element.Name, frame = badge })
		end
		local hint = HudStyle.caption(bar, `[{STAFF.ElementKey.Name}] switch element`, 12)
		elementHint = hint
		hint.AnchorPoint = Vector2.new(0.5, 0)
		hint.Position = UDim2.new(0.5, 0, 0, ELEMENT_ICON_SIZE + 2)
		hint.Size = UDim2.fromOffset(160, 14)
		hint.TextColor3 = Color3.fromRGB(210, 205, 220)
		player:GetAttributeChangedSignal(ELEMENT_ATTRIBUTE):Connect(updateElementBar)
		player:GetAttributeChangedSignal("Skills"):Connect(updateElementBar) -- unlocking elements
		updateElementBar()

		-- The hint line under the crosshair.
		local hintGui = Instance.new("ScreenGui")
		hintGui.Name = `{STAFF.ToolName}Hint`
		hintGui.ResetOnSpawn = false
		hintGui.Parent = player:WaitForChild("PlayerGui")
		local label = HudStyle.caption(HudStyle.holder(hintGui, Vector2.new(0.5, 0.5)), "", 18)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 90)
		label.Size = UDim2.fromOffset(560, 24)
		label.TextColor3 = Color3.fromRGB(230, 220, 255)
		label.Visible = false
		hintLabel = label
	end

	-- Equipping -----------------------------------------------------------------------------------

	local function onEquipped(tool: Tool, character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		HandGrip.attachLocal(tool, character, STAFF.Hand :: HandGrip.Hand, `{STAFF.ToolName}Grip`)
		local state: Equipped = { tool = tool, humanoid = humanoid, tracks = getTracks(humanoid), baseWalkSpeed = StarterPlayer.CharacterWalkSpeed } -- never a mid-move speed
		equipped = state
		if state.tracks.idle then
			state.tracks.idle:Play(0.2)
		end
		staffInHand = true
		updateElementBar()
	end

	local function onUnequipped(tool: Tool)
		local state = equipped
		if not state or state.tool ~= tool then
			return
		end
		if stopCharge then
			stopCharge(false)
		end
		if stopGuard then
			stopGuard()
		end
		pressedAt = nil
		equipped = nil
		HandGrip.detach(tool, `Local{STAFF.ToolName}Grip`)
		for _, track in state.tracks do
			track:Stop(0.2)
		end
		state.humanoid.WalkSpeed = state.baseWalkSpeed
		staffInHand = false
		updateElementBar()
	end

	local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function hookTool(child: Instance)
		if not child:IsA("Tool") or child.Name ~= STAFF.ToolName then
			return
		end
		local character = player.Character
		if character and child.Parent == character then
			onEquipped(child, character)
		end
		if not hookedTools[child] then
			hookedTools[child] = true
			child.Unequipped:Connect(function()
				onUnequipped(child)
			end)
		end
	end

	local controller = {}

	function controller.start()
		task.spawn(function()
			local preload: { Instance } = {}
			for _, animation in ANIMATIONS do
				if animation then
					table.insert(preload, animation)
				end
			end
			if #preload > 0 then
				ContentProvider:PreloadAsync(preload)
			end
		end)
		buildElementBar()
		if STAFF.AimWithHand then
			RunService.Stepped:Connect(function(_, dt)
				stepAim(dt)
			end)
		end

		CombatInput.AttackBegan:Connect(onAttackBegan)
		CombatInput.AttackEnded:Connect(onAttackEnded)
		CombatInput.BlockBegan:Connect(function()
			local state = equipped
			if state and not stopCharge and not stopGuard then
				pressedAt = nil
				startGuard(state)
			end
		end)
		CombatInput.BlockEnded:Connect(function()
			if stopGuard then
				stopGuard()
			end
		end)
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == STAFF.ElementKey and equipped then
				cycleElement()
			end
		end)

		local function onCharacterAdded(character: Model)
			equipped = nil
			stopCharge = nil
			stopGuard = nil
			pressedAt = nil
			staffInHand = false
			updateElementBar()
			character.ChildAdded:Connect(hookTool)
			for _, child in character:GetChildren() do
				hookTool(child)
			end
		end
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end

	return controller
end

return StaffClient
