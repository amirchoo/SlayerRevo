--!strict
-- Staff input and visuals (see StaffService for what the spells do).
--   Attack, tapped: cast a light missile at your aim (Aim: lock-on target, mouse, or screen
--     centre). Held past HoldTime: charge a blast (the staff is raised and sparks in the
--     element's colour gather at its tip, with a chime at full charge); let go to release it.
--   Spells spend mana (see ManaService), not stamina.
--   Block (held): guard, like any weapon.
--   R, or clicking/tapping an element in the bar above the meters: switch element.
-- The element bar (the unlocked elements, the current one highlighted) shows only while the
-- staff is in hand and at least one element is unlocked. Spells need the Mage class and the element unlocked in the
-- Staff skill tree (SkillMath.staffUnlocked); until then a hint says what to unlock. The server times charges and decides every hit; this is input and feedback.

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
local CombatInput = require(script.Parent.CombatInput)
local HudStyle = require(script.Parent.HudStyle)

local STAFF = CombatConfig.Staff
local BLOCK = CombatConfig.Blocking
local ELEMENT_ICON_SIZE = 36
local ELEMENT_GAP = 8
local ELEMENT_BAR_BOTTOM = -208 -- above the dash and block meters

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
				track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Action
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

local function missileIgnore(): { Instance }?
	local folder = workspace:FindFirstChild("StaffMissiles")
	return if folder then { folder } else nil
end

-- The element spells will use: the chosen one if unlocked, else the first unlocked one (as
-- the server does), or nil if none is.
local function currentElementName(): string?
	local name = player:GetAttribute("StaffElement")
	if typeof(name) == "string" and SkillMath.staffUnlocked(player, name) then
		return name
	end
	for _, element in STAFF.Elements do
		if SkillMath.staffUnlocked(player, element.Name) then
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
	if not SkillMath.staffUnlocked(player) then
		showHint("Unlock the Mage class in the Staff skill tree (K) to cast spells")
		return false
	elseif not currentElementName() then
		showHint("Unlock an element in the Staff skill tree (K)")
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
	chargeRemote:FireServer()
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
		releaseRemote:FireServer(Aim.point(missileIgnore()))
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

-- The element bar -----------------------------------------------------------------------------

local elementBar: Frame? = nil
type ElementIcon = { name: string, frame: Frame }
local elementIcons: { ElementIcon } = {}

local function selectElement(name: string)
	if not SkillMath.staffUnlocked(player) then
		showHint("Unlock the Mage class in the Staff skill tree (K) first")
		return
	elseif not SkillMath.staffUnlocked(player, name) then
		showHint(`Unlock {name} in the Staff skill tree (K)`)
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
		if SkillMath.staffUnlocked(player, element.Name) then
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
		local unlocked = SkillMath.staffUnlocked(player, icon.name)
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
	gui.Name = "StaffElements"
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
	player:GetAttributeChangedSignal("StaffElement"):Connect(updateElementBar)
	player:GetAttributeChangedSignal("Skills"):Connect(updateElementBar) -- unlocking elements
	updateElementBar()

	-- The hint line under the crosshair.
	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "StaffHint"
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
	HandGrip.attachLocal(tool, character, STAFF.Hand :: HandGrip.Hand, "StaffGrip")
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
	HandGrip.detach(tool, "LocalStaffGrip")
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

function StaffClient.start()
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

return StaffClient
