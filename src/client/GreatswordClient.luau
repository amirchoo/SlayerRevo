--!strict
-- Greatsword input and visuals. While equipped: heavier walk speed and the idle loops.
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

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

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
-- Fallback guard when no guard animation is set: blade turned flat in front.
local GUARD_GRIP = CFrame.Angles(math.rad(-15), 0, math.rad(-75))
local GUARD_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chargeRemote = remotes:WaitForChild("GreatswordCharge") :: RemoteEvent
local releaseRemote = remotes:WaitForChild("GreatswordRelease") :: RemoteEvent
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent

local GreatswordClient = {}

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	return animation
end

local IDLE_ANIMATION = makeAnimation(GREATSWORD.IdleAnimation)
local CHARGE_ANIMATION = makeAnimation(GREATSWORD.ChargeAnimation)
local SLAM_ANIMATION = makeAnimation(GREATSWORD.SlamAnimation)
local GUARD_ANIMATION = makeAnimation(GREATSWORD.GuardAnimation)

type Tracks = { idle: AnimationTrack?, charge: AnimationTrack?, slam: AnimationTrack?, guard: AnimationTrack? }
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
	local tracks: Tracks = {}
	if animator then
		-- Priorities set here so it doesn't matter how each animation was published.
		tracks.idle = load(animator, IDLE_ANIMATION, Enum.AnimationPriority.Idle, true)
		tracks.charge = load(animator, CHARGE_ANIMATION, Enum.AnimationPriority.Action, false)
		tracks.slam = load(animator, SLAM_ANIMATION, Enum.AnimationPriority.Action, false)
		tracks.guard = load(animator, GUARD_ANIMATION, Enum.AnimationPriority.Action, true)
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
	end
	return GREATSWORD.WalkSpeed
end

local function startCharge(state: Equipped)
	chargeRemote:FireServer()
	local startTime = os.clock()
	local bladePart = blade(state.tool)
	local originalColor = bladePart and bladePart.Color
	local originalMaterial = bladePart and bladePart.Material
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
		-- Local checks only avoid pointless requests; the server enforces the real ones.
		if not stopCharge and not stopGuard and os.clock() - lastSlam >= GREATSWORD.Recovery then
			startCharge(state)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not stopCharge and not stopGuard and os.clock() >= busyUntil then
			startGuard(state)
		end
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and stopCharge then
		stopCharge(true)
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
	HandGrip.detach(tool, "LocalGreatswordGrip")
	for _, track in { state.tracks.idle, state.tracks.charge, state.tracks.slam, state.tracks.guard } do
		if track then
			track:Stop(0.2)
		end
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
