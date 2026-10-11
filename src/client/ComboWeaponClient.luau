--!strict
-- Input and visuals for click-combo weapons (sword, mace, spear), one controller per weapon config.
-- While equipped the idle animation loops. Left-click steps through the combo: each click
-- plays the next swing, and pausing too long (or finishing the last swing) starts it over.
-- The server decides what's hit and how hard (see WeaponService). Holding right-click raises
-- a guard and tells the server we're blocking (see BlockService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Push = require(script.Parent.Push)

type ComboWeapon = CombatConfig.ComboWeapon

local BLOCKING = CombatConfig.Blocking
local TRAIL_AFTER_HIT = 0.15 -- keep the trail on this long after the hit lands
local LUNGE_TIME = 0.15 -- seconds a lunging move pushes forward

-- Fallback guard pose when a weapon has no guard animation (Block.Animation = ""): the
-- weapon turned sideways across the body, tipped slightly forward. Local only.
local GUARD_GRIP = CFrame.Angles(math.rad(-20), 0, math.rad(-80))
local GUARD_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local swingRemote = remotes:WaitForChild("MeleeSwing") :: RemoteEvent
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent

local ComboWeaponClient = {}

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	return animation
end

type Tracks = { idle: AnimationTrack?, guard: AnimationTrack?, swings: { AnimationTrack } }

-- Creates the controller for one combo weapon; call :start() once on the client.
function ComboWeaponClient.new(config: ComboWeapon)
	local combo = config.Combo
	local weldName = `{config.ToolName}Grip`
	local localWeldName = `Local{weldName}`

	local idleAnimation = makeAnimation(config.IdleAnimation)
	local guardAnimation = makeAnimation(config.Block.Animation)
	local swingAnimations: { Animation } = {}
	for index, move in combo do
		local animation = makeAnimation(move.Animation)
		if animation then
			swingAnimations[index] = animation
		end
	end

	local tracksByHumanoid: { [Humanoid]: Tracks } = setmetatable({}, { __mode = "k" }) :: any

	local function getTracks(humanoid: Humanoid): Tracks?
		local cached = tracksByHumanoid[humanoid]
		if cached then
			return cached
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return nil
		end
		-- Priorities set here so it doesn't matter how each animation was published.
		local tracks: Tracks = { swings = {} }
		if idleAnimation then
			local idle = animator:LoadAnimation(idleAnimation)
			idle.Priority = Enum.AnimationPriority.Idle
			idle.Looped = true
			tracks.idle = idle
		end
		for index, animation in swingAnimations do
			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			tracks.swings[index] = track
		end
		if guardAnimation then
			local guard = animator:LoadAnimation(guardAnimation)
			guard.Priority = Enum.AnimationPriority.Action
			guard.Looped = true
			tracks.guard = guard
		end
		tracksByHumanoid[humanoid] = tracks
		return tracks
	end

	local function currentTracks(): Tracks?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return if humanoid then getTracks(humanoid) else nil
	end

	local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local comboStep = 0 -- the last step played; 0 means the combo hasn't started
	local lastSwing = 0
	local swingToken = 0

	-- Set while blocking; call it to lower the guard.
	local stopBlock: (() -> ())? = nil

	-- Which combo step a click right now would play, or nil if the last swing isn't done.
	-- Matches the server's rule in WeaponService.
	local function nextStep(now: number): number?
		if comboStep == 0 then
			return 1
		end
		local since = now - lastSwing
		local previous = combo[comboStep]
		if since < previous.Cooldown then
			return nil
		end
		if comboStep < #combo and since <= previous.Cooldown + config.ComboWindow then
			return comboStep + 1
		end
		return 1
	end

	local function stopSwings(fade: number)
		local tracks = currentTracks()
		if tracks then
			for _, track in tracks.swings do
				track:Stop(fade)
			end
		end
	end

	local function playSwingEffects(tool: Tool, step: number)
		local sound = tool:FindFirstChild("SlashSound", true)
		if sound and sound:IsA("Sound") then
			sound:Play()
		end

		local trail = tool:FindFirstChild("SwingTrail", true)
		if trail and trail:IsA("Trail") then
			swingToken += 1
			local token = swingToken
			trail.Enabled = true
			task.delay(combo[step].HitDelay + TRAIL_AFTER_HIT, function()
				if token == swingToken then
					trail.Enabled = false
				end
			end)
		end
	end

	local function onActivated(tool: Tool)
		-- Local checks only avoid pointless requests; the server enforces the real ones.
		if stopBlock then
			return
		end
		local now = os.clock()
		local step = nextStep(now)
		if not step then
			return
		end
		comboStep, lastSwing = step, now
		swingRemote:FireServer()

		local tracks = currentTracks()
		local swing = tracks and tracks.swings[step]
		if tracks and swing then
			for index, track in tracks.swings do
				if index ~= step and track.IsPlaying then
					track:Stop(0.05)
				end
			end
			swing:Play(0.05, 1, config.AnimationSpeed)
		end
		playSwingEffects(tool, step)

		-- Lunging moves carry the player forward (our own movement, so the client does it).
		local lunge = combo[step].Lunge
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if lunge and root and root:IsA("BasePart") then
			Push.apply(root, root.CFrame.LookVector, lunge, LUNGE_TIME)
		end
	end

	local function localWeld(tool: Tool): Weld?
		local grip = tool:FindFirstChild(HandGrip.GRIP_NAME)
		local weld = grip and grip:FindFirstChild(localWeldName)
		return if weld and weld:IsA("Weld") then weld else nil
	end

	local function startBlock(tool: Tool)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		blockRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		local trail = tool:FindFirstChild("SwingTrail", true)
		if trail and trail:IsA("Trail") then
			trail.Enabled = false
		end

		local tracks = currentTracks()
		local guardTrack = tracks and tracks.guard
		if guardTrack then
			guardTrack:Play(0.1)
		else
			local weld = localWeld(tool)
			if weld then
				TweenService:Create(weld, GUARD_TWEEN, { C1 = tool.Grip * GUARD_GRIP }):Play()
			end
		end
		local walkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = BLOCKING.WalkSpeed

		stopBlock = function()
			stopBlock = nil
			blockRemote:FireServer(false)
			if guardTrack then
				guardTrack:Stop(0.15)
			else
				local currentWeld = localWeld(tool)
				if currentWeld then
					TweenService:Create(currentWeld, GUARD_TWEEN, { C1 = tool.Grip }):Play()
				end
			end
			humanoid.WalkSpeed = walkSpeed
		end
	end

	local function equippedTool(): Tool?
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		return if tool and tool.Name == config.ToolName then tool else nil
	end

	local function onInputBegan(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton2 or stopBlock then
			return
		end
		local tool = equippedTool()
		if tool then
			startBlock(tool)
		end
	end

	local function onInputEnded(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and stopBlock then
			stopBlock()
		end
	end

	local function hookTool(child: Instance)
		if not child:IsA("Tool") or child.Name ~= config.ToolName then
			return
		end
		-- Equipping moves the tool into the character: hold it in hand locally right away
		-- (the server adds the replicated grip; see HandGrip) and start the idle.
		local character = player.Character
		if character and child.Parent == character then
			HandGrip.attachLocal(child, character, config.Hand :: HandGrip.Hand, weldName)
			local tracks = currentTracks()
			if tracks and tracks.idle then
				tracks.idle:Play(0.2)
			end
		end

		if not hookedTools[child] then
			hookedTools[child] = true
			child.Activated:Connect(function()
				onActivated(child)
			end)
			child.Unequipped:Connect(function()
				if stopBlock then
					stopBlock()
				end
				HandGrip.detach(child, localWeldName)
				comboStep = 0
				local tracks = currentTracks()
				if tracks and tracks.idle then
					tracks.idle:Stop(0.2)
				end
				stopSwings(0.1)
			end)
		end
	end

	local controller = {}

	function controller.start()
		-- Load the animations up front so the first swing doesn't stall.
		task.spawn(function()
			local preload: { Instance } = {}
			for _, animation in { idleAnimation, guardAnimation } do
				if animation then
					table.insert(preload, animation)
				end
			end
			for _, animation in swingAnimations do
				table.insert(preload, animation)
			end
			if #preload > 0 then
				ContentProvider:PreloadAsync(preload)
			end
		end)

		UserInputService.InputBegan:Connect(onInputBegan)
		UserInputService.InputEnded:Connect(onInputEnded)

		local function onCharacterAdded(character: Model)
			-- A respawn clears any block or combo in progress (the server resets too).
			stopBlock = nil
			comboStep = 0
			-- Tools move into the character when equipped.
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

return ComboWeaponClient
