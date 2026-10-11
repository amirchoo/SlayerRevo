--!strict
-- Greatsword input and visuals. While equipped: heavier walk speed and the idle loops.
-- Tap left-click (release within HoldTime) for the 3-hit combo of wide sweeps; the swing
-- fires on release, since that's when a tap can be told apart from a hold.
-- Hold left-click to charge: feet planted, turn with the camera, the charge animation
-- winds up, and the blade glows brighter (with a rising clang) at each charge level.
-- Release to slam: the slam plays, the trail sweeps, and the camera shakes on impact,
-- harder for higher levels. Hold right-click to guard (shared block system, BlockService).
-- The server times the charge and decides hits; these visuals are just feedback.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Stamina = require(ReplicatedStorage.Shared.Stamina)

local GREATSWORD = CombatConfig.Greatsword
local LEVELS = GREATSWORD.ChargeLevels
local BLOCK = CombatConfig.Blocking

-- Blade look per charge level (index matches ChargeLevels).
local LEVEL_LOOKS = {
	{ color = nil, neon = false }, -- level 0: the blade's own look
	{ color = Color3.fromRGB(255, 225, 140), neon = true },
	{ color = Color3.fromRGB(255, 150, 60), neon = true },
	{ color = Color3.fromRGB(255, 250, 235), neon = true },
}
local SHAKE_TIME = 0.25
local SHAKE_PER_LEVEL = 0.25 -- studs of shake added per charge level
local TRAIL_AFTER_HIT = 0.2
local SWING_TRAIL_BEFORE_HIT = 0.1
local FINISHER_SHAKE = 0.2
-- Fallback guard when no guard animation is set: blade turned flat in front.
local GUARD_GRIP = CFrame.Angles(math.rad(-15), 0, math.rad(-75))
local GUARD_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chargeRemote = remotes:WaitForChild("GreatswordCharge") :: RemoteEvent
local releaseRemote = remotes:WaitForChild("GreatswordRelease") :: RemoteEvent
local swingRemote = remotes:WaitForChild("GreatswordSwing") :: RemoteEvent
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent

local GreatswordClient = {}

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	-- A bare number (e.g. pasted straight from the Creator Dashboard) still works.
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animation
end

local IDLE_ANIMATION = makeAnimation(GREATSWORD.IdleAnimation)
local CHARGE_ANIMATION = makeAnimation(GREATSWORD.ChargeAnimation)
local SLAM_ANIMATION = makeAnimation(GREATSWORD.SlamAnimation)
local GUARD_ANIMATION = makeAnimation(GREATSWORD.GuardAnimation)
local SWING_ANIMATIONS: { Animation? } = {}
for index, move in GREATSWORD.Combo do
	SWING_ANIMATIONS[index] = makeAnimation(move.Animation)
end

type Tracks = {
	idle: AnimationTrack?,
	charge: AnimationTrack?,
	slam: AnimationTrack?,
	guard: AnimationTrack?,
	swings: { [number]: AnimationTrack },
}
local tracksByHumanoid: { [Humanoid]: Tracks } = setmetatable({}, { __mode = "k" }) :: any

local function load(animator: Animator, animation: Animation?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

local function getTracks(humanoid: Humanoid): Tracks
	local cached = tracksByHumanoid[humanoid]
	if cached then
		return cached
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local tracks: Tracks = { swings = {} }
	if animator then
		-- Priorities set here so it doesn't matter how each animation was published.
		tracks.idle = load(animator, IDLE_ANIMATION, Enum.AnimationPriority.Idle, true)
		tracks.charge = load(animator, CHARGE_ANIMATION, Enum.AnimationPriority.Action, false)
		tracks.slam = load(animator, SLAM_ANIMATION, Enum.AnimationPriority.Action, false)
		tracks.guard = load(animator, GUARD_ANIMATION, Enum.AnimationPriority.Action, true)
		for index, animation in SWING_ANIMATIONS do
			local track = load(animator, animation, Enum.AnimationPriority.Action, false)
			if track then
				tracks.swings[index] = track
			end
		end
	end
	tracksByHumanoid[humanoid] = tracks
	return tracks
end

-- State for the currently equipped greatsword (nil when not equipped).
type Equipped = {
	tool: Tool,
	humanoid: Humanoid,
	root: BasePart,
	tracks: Tracks,
	baseWalkSpeed: number,
}
local equipped: Equipped? = nil
local stopCharge: ((released: boolean) -> ())? = nil
local stopGuard: (() -> ())? = nil
local lastSlam = 0
local busyUntil = 0 -- feet stay planted until the slam recovers
local comboStep = 0 -- last combo swing played (0 = none)
local lastSwing = 0
local swingUntil = 0 -- slowed down until the current swing's cooldown ends
local pressedAt: number? = nil -- when left-click went down, while it's held and not yet charging

local function blade(tool: Tool): BasePart?
	local part = tool:FindFirstChild("Blade", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function shakeCamera(humanoid: Humanoid, strength: number)
	if strength <= 0 then
		return
	end
	local random = Random.new()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local remaining = 1 - (os.clock() - started) / SHAKE_TIME
		if remaining <= 0 then
			connection:Disconnect()
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local s = strength * remaining
		humanoid.CameraOffset = Vector3.new(random:NextNumber(-s, s), random:NextNumber(-s, s), 0)
	end)
end

local function walkSpeedFor(state: Equipped): number
	if stopGuard then
		return BLOCK.WalkSpeed
	elseif stopCharge or os.clock() < busyUntil then
		return 0
	elseif os.clock() < swingUntil then
		return GREATSWORD.SwingWalkSpeed
	end
	return GREATSWORD.WalkSpeed
end

local function swing(state: Equipped)
	local now = os.clock()
	if now < swingUntil or now < busyUntil then
		return -- still mid-swing or recovering from a slam
	end
	if not Stamina.canAfford(player, GREATSWORD.SwingStamina) then
		return
	end
	-- Same rule as the server: the next step if clicked soon enough after the last swing,
	-- otherwise back to the first.
	local combo = GREATSWORD.Combo
	local step = 1
	if comboStep > 0 and comboStep < #combo and now - lastSwing <= combo[comboStep].Cooldown + GREATSWORD.ComboWindow then
		step = comboStep + 1
	end
	local move = combo[step]
	comboStep = step
	lastSwing = now
	swingUntil = now + move.Cooldown
	swingRemote:FireServer()

	local track = state.tracks.swings[step]
	if track then
		track:Play(0.05)
	end
	state.humanoid.WalkSpeed = walkSpeedFor(state)

	local trail = state.tool:FindFirstChild("SwingTrail", true)
	task.delay(math.max(move.HitDelay - SWING_TRAIL_BEFORE_HIT, 0), function()
		if equipped == state and trail and trail:IsA("Trail") then
			trail.Enabled = true
		end
		Sounds.play("GreatswordSwing", state.root, if step == #combo then 0.9 else 1.15)
	end)
	task.delay(move.HitDelay, function()
		if equipped == state and step == #combo then
			shakeCamera(state.humanoid, FINISHER_SHAKE)
		end
	end)
	task.delay(move.HitDelay + TRAIL_AFTER_HIT, function()
		-- Leave the trail alone if a slam has taken over.
		if trail and trail:IsA("Trail") and not stopCharge and os.clock() >= busyUntil then
			trail.Enabled = false
		end
	end)
	task.delay(move.Cooldown, function()
		if equipped == state then
			state.humanoid.WalkSpeed = walkSpeedFor(state)
		end
	end)
end

local function startCharge(state: Equipped)
	chargeRemote:FireServer()
	comboStep = 0 -- a slam ends the combo
	local startTime = os.clock()
	local bladePart = blade(state.tool)
	local originalColor = bladePart and bladePart.Color
	local originalMaterial = bladePart and bladePart.Material
	local modelChild = state.tool:FindFirstChild("Model")
	local realModel: Model? = if modelChild and modelChild:IsA("Model") then modelChild else nil
	local glow: Highlight? = nil
	local shownLevel = 1

	state.humanoid.AutoRotate = false
	local charge = state.tracks.charge
	if charge then
		charge:Play(0.1)
	end

	local connection = RunService.RenderStepped:Connect(function()
		local held = os.clock() - startTime

		-- Turn with the camera (feet stay planted).
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			state.root.CFrame = CFrame.lookAt(state.root.Position, state.root.Position + flat)
		end

		-- Freeze the wind-up on its last frame instead of letting it end.
		if charge and charge.IsPlaying and charge.Speed > 0 and charge.Length > 0 and charge.TimePosition >= charge.Length - 0.05 then
			charge:AdjustSpeed(0)
		end

		-- Brighter blade and a rising clang at each new level.
		local level = 1
		for index, candidate in LEVELS do
			if held >= candidate.Time then
				level = index
			end
		end
		if level > shownLevel then
			shownLevel = level
			local levelLook = LEVEL_LOOKS[level]
			if bladePart and levelLook.color then
				bladePart.Color = levelLook.color
				bladePart.Material = if levelLook.neon then Enum.Material.Neon else Enum.Material.Metal
			elseif realModel and levelLook.color then
				-- A real model (see WeaponModels) has textures, not a blade to recolor: glow instead.
				glow = glow or Instance.new("Highlight")
				glow.Adornee = realModel
				glow.FillColor = levelLook.color
				glow.OutlineColor = levelLook.color
				glow.FillTransparency = 0.55
				glow.OutlineTransparency = 0.3
				glow.DepthMode = Enum.HighlightDepthMode.Occluded
				glow.Parent = realModel
			end
			Sounds.play("ChargeLevel", workspace.CurrentCamera, 0.9 + 0.25 * level)
		end
	end)

	stopCharge = function(released: boolean)
		stopCharge = nil
		connection:Disconnect()
		state.humanoid.AutoRotate = true
		if charge then
			charge:Stop(if released then 0.05 else 0.2)
		end

		local level = shownLevel
		local function restoreBlade()
			if bladePart and originalColor and originalMaterial then
				bladePart.Color = originalColor
				bladePart.Material = originalMaterial
			end
			if glow then
				glow:Destroy()
				glow = nil
			end
		end

		if not released then
			restoreBlade()
			state.humanoid.WalkSpeed = walkSpeedFor(state)
			return
		end

		releaseRemote:FireServer()
		lastSlam = os.clock()
		busyUntil = lastSlam + GREATSWORD.Recovery
		state.humanoid.WalkSpeed = 0
		if state.tracks.slam then
			state.tracks.slam:Play(0.05)
		end
		local trail = state.tool:FindFirstChild("SwingTrail", true)
		if trail and trail:IsA("Trail") then
			trail.Enabled = true
		end

		task.delay(GREATSWORD.HitDelay, function()
			local sound = state.tool:FindFirstChild("SlamSound", true)
			if sound and sound:IsA("Sound") then
				sound:Play()
			end
			shakeCamera(state.humanoid, SHAKE_PER_LEVEL * (level - 1) + 0.1)
		end)
		task.delay(GREATSWORD.HitDelay + TRAIL_AFTER_HIT, function()
			if trail and trail:IsA("Trail") then
				trail.Enabled = false
			end
			restoreBlade()
		end)
		task.delay(GREATSWORD.Recovery, function()
			if equipped == state then
				state.humanoid.WalkSpeed = walkSpeedFor(state)
			end
		end)
	end

	state.humanoid.WalkSpeed = 0
end

local function localWeld(tool: Tool): Weld?
	local grip = tool:FindFirstChild(HandGrip.GRIP_NAME)
	local weld = grip and grip:FindFirstChild("LocalGreatswordGrip")
	return if weld and weld:IsA("Weld") then weld else nil
end

local function startGuard(state: Equipped)
	blockRemote:FireServer(true)
	local guard = state.tracks.guard
	if guard then
		guard:Play(0.1)
	else
		local weld = localWeld(state.tool)
		if weld then
			TweenService:Create(weld, GUARD_TWEEN, { C1 = state.tool.Grip * GUARD_GRIP }):Play()
		end
	end

	stopGuard = function()
		stopGuard = nil
		blockRemote:FireServer(false)
		if guard then
			guard:Stop(0.15)
		else
			local weld = localWeld(state.tool)
			if weld then
				TweenService:Create(weld, GUARD_TWEEN, { C1 = state.tool.Grip }):Play()
			end
		end
		state.humanoid.WalkSpeed = walkSpeedFor(state)
	end
	state.humanoid.WalkSpeed = walkSpeedFor(state)
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	local state = equipped
	if gameProcessed or not state then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if stopCharge or stopGuard then
			return
		end
		-- Tap or hold? Released before HoldTime is a combo swing (see onInputEnded);
		-- still held after it starts a charge, once any swing or slam has finished.
		local pressed = os.clock()
		pressedAt = pressed
		task.delay(GREATSWORD.HoldTime, function()
			-- Local checks only avoid pointless requests; the server enforces the real ones.
			while pressedAt == pressed and equipped == state and (os.clock() < swingUntil or os.clock() - lastSlam < GREATSWORD.Recovery) do
				task.wait()
			end
			if pressedAt == pressed and equipped == state and not stopCharge and not stopGuard then
				pressedAt = nil
				if Stamina.canAfford(player, GREATSWORD.SlamStamina) then
					startCharge(state)
				end
			end
		end)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not stopCharge and not stopGuard and os.clock() >= busyUntil and os.clock() >= swingUntil then
			pressedAt = nil
			startGuard(state)
		end
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and stopCharge then
		stopCharge(true)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and pressedAt then
		local held = os.clock() - pressedAt
		pressedAt = nil
		local state = equipped
		if state and not stopGuard and held < GREATSWORD.HoldTime then
			swing(state)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and stopGuard then
		stopGuard()
	end
end

local function onEquipped(tool: Tool, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	HandGrip.attachLocal(tool, character, GREATSWORD.Hand :: HandGrip.Hand, "GreatswordGrip")

	local state: Equipped = {
		tool = tool,
		humanoid = humanoid,
		root = root,
		tracks = getTracks(humanoid),
		baseWalkSpeed = humanoid.WalkSpeed,
	}
	equipped = state
	if state.tracks.idle then
		state.tracks.idle:Play(0.2)
	end
	humanoid.WalkSpeed = walkSpeedFor(state)
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
	equipped = nil
	pressedAt = nil
	HandGrip.detach(tool, "LocalGreatswordGrip")
	for _, track in { state.tracks.idle, state.tracks.charge, state.tracks.slam, state.tracks.guard } do
		if track then
			track:Stop(0.2)
		end
	end
	for _, track in state.tracks.swings do
		track:Stop(0.2)
	end
	local trail = tool:FindFirstChild("SwingTrail", true)
	if trail and trail:IsA("Trail") then
		trail.Enabled = false
	end
	state.humanoid.WalkSpeed = state.baseWalkSpeed
end

local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hookTool(child: Instance)
	if not child:IsA("Tool") or child.Name ~= GREATSWORD.ToolName then
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

function GreatswordClient.start()
	task.spawn(function()
		local preload: { Instance } = {}
		for _, animation in { IDLE_ANIMATION, CHARGE_ANIMATION, SLAM_ANIMATION, GUARD_ANIMATION } do
			if animation then
				table.insert(preload, animation)
			end
		end
		for _, animation in SWING_ANIMATIONS do
			if animation then
				table.insert(preload, animation)
			end
		end
		if #preload > 0 then
			ContentProvider:PreloadAsync(preload)
		end
	end)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	local function onCharacterAdded(character: Model)
		-- A respawn clears any charge, guard, or slam in progress.
		equipped = nil
		stopCharge = nil
		stopGuard = nil
		busyUntil = 0
		swingUntil = 0
		comboStep = 0
		pressedAt = nil
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

return GreatswordClient
