--!strict
-- Input and visuals for click-combo weapons (sword, mace, spear), one controller per weapon config.
-- While equipped the idle animation loops. Left-click steps through the combo: each click
-- plays the next swing, and pausing too long (or finishing the last swing) starts it over.
-- The server decides what's hit and how hard (see WeaponService). Holding right-click raises
-- a guard and tells the server we're blocking (see BlockService).
-- Weapons with a heavy attack tell a tap from a hold: a quick tap (released within
-- Heavy.HoldTime) is a normal combo swing, while holding starts the heavy:
--   Spin: spins until release. The server runs the spin's hits and can end it early (time
--   limit, weapon switch, death).
--   Quake: raises the weapon while a ring on the ground shows how far the smash will reach
--   (growing with the charge); release smashes the ground.
--   Thrust: draws back, turning with the camera, while a strip on the ground shows how far
--   the lunge will carry; release lunges forward.
--   For both, the server times the charge and attacks by itself at MaxHold.
-- The server's "HeavyAttacking" attribute going false ends the visuals here too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Stamina = require(ReplicatedStorage.Shared.Stamina)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Push = require(script.Parent.Push)

type ComboWeapon = CombatConfig.ComboWeapon
type SpinHeavy = CombatConfig.SpinHeavy
type QuakeHeavy = CombatConfig.QuakeHeavy
type ThrustHeavy = CombatConfig.ThrustHeavy
-- How a heavy ends: we let go ("release"), the server ended it ("server"), or it was
-- called off (weapon switch, or the server refused it) ("cancel").
type StopHow = "release" | "server" | "cancel"

local BLOCKING = CombatConfig.Blocking
local TRAIL_AFTER_HIT = 0.15 -- keep the trail on this long after the hit lands
local LUNGE_TIME = 0.15 -- seconds a lunging move pushes forward
-- The ground indicator showing a charged heavy's reach.
local REACH_COLOR = Color3.fromRGB(255, 200, 120)
local REACH_TRANSPARENCY = 0.8
local REACH_TRANSPARENCY_FULL = 0.55 -- brighter once fully charged
local PLANTED_AFTER_HIT = 0.35 -- seconds the feet stay planted after a charged heavy lands
local FLIPPED_GRIP = CFrame.Angles(0, 0, math.pi) -- a FlipGrip heavy's weapon, turned around its handle
local UNFLIP_AFTER_HIT = 0.45 -- matches WeaponService: when a flipped weapon turns back after the hit

-- Fallback guard pose when a weapon has no guard animation (Block.Animation = ""): the
-- weapon turned sideways across the body, tipped slightly forward. Local only.
local GUARD_GRIP = CFrame.Angles(math.rad(-20), 0, math.rad(-80))
local GUARD_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local swingRemote = remotes:WaitForChild("MeleeSwing") :: RemoteEvent
local heavyRemote = remotes:WaitForChild("HeavyAttack") :: RemoteEvent
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent

local ComboWeaponClient = {}

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	-- A bare number (e.g. pasted straight from the Creator Dashboard) still works.
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animation
end

type Tracks = {
	idle: AnimationTrack?,
	guard: AnimationTrack?,
	heavy: AnimationTrack?, -- spin loop, or a quake's or thrust's wind-up
	heavySlam: AnimationTrack?, -- a quake's smash, or a thrust's lunge
	swings: { AnimationTrack },
}

local HEAVY_CONFIRM_TIME = 0.5 -- if the server hasn't started the spin by now, it refused

-- Creates the controller for one combo weapon; call :start() once on the client.
function ComboWeaponClient.new(config: ComboWeapon)
	local combo = config.Combo
	local weldName = `{config.ToolName}Grip`
	local localWeldName = `Local{weldName}`

	local idleAnimation = makeAnimation(config.IdleAnimation)
	local guardAnimation = makeAnimation(config.Block.Animation)
	local heavy = config.Heavy
	local heavyAnimation: Animation? = nil
	local heavySlamAnimation: Animation? = nil
	if heavy and heavy.Kind == "Spin" then
		heavyAnimation = makeAnimation((heavy :: SpinHeavy).Animation)
	elseif heavy and heavy.Kind == "Quake" then
		local quake = heavy :: QuakeHeavy
		heavyAnimation = makeAnimation(quake.WindUpAnimation)
		heavySlamAnimation = makeAnimation(quake.SlamAnimation)
	elseif heavy then
		local lunge = heavy :: ThrustHeavy
		heavyAnimation = makeAnimation(lunge.WindUpAnimation)
		heavySlamAnimation = makeAnimation(lunge.ThrustAnimation)
	end
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
		if heavyAnimation then
			local heavyTrack = animator:LoadAnimation(heavyAnimation)
			heavyTrack.Priority = Enum.AnimationPriority.Action
			heavyTrack.Looped = heavy ~= nil and heavy.Kind == "Spin" -- a quake's wind-up holds its last frame instead
			tracks.heavy = heavyTrack
		end
		if heavySlamAnimation then
			local slam = animator:LoadAnimation(heavySlamAnimation)
			slam.Priority = Enum.AnimationPriority.Action
			slam.Looped = false
			tracks.heavySlam = slam
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
	-- Set during a heavy; call it to end it (see StopHow).
	local stopHeavy: ((how: StopHow) -> ())? = nil
	-- When the left button went down (nil when it's up), and a token to tell presses apart.
	local pressedAt: number? = nil
	local pressToken = 0

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
		if not step or not Stamina.canAfford(player, SkillMath.staminaCost(player, config.ToolName, config.Stamina, "Light")) then
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

	-- Turns the weapon 180 degrees around its handle on this screen (see Heavy.FlipGrip; the
	-- server does the same to the weld everyone else sees).
	local function setGripFlipped(tool: Tool, flipped: boolean)
		local weld = localWeld(tool)
		if weld then
			weld.C1 = if flipped then FLIPPED_GRIP * tool.Grip else tool.Grip
		end
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

	-- Ends the heavy when the server says it's over, and calls it off if the server never
	-- confirms it started (e.g. still recovering from the last one).
	local function watchServer(stop: (how: StopHow) -> ()): RBXScriptConnection
		local serverStarted = false
		local connection = player:GetAttributeChangedSignal("HeavyAttacking"):Connect(function()
			if player:GetAttribute("HeavyAttacking") == true then
				serverStarted = true
			elseif serverStarted then
				stop("server")
			end
		end)
		task.delay(HEAVY_CONFIRM_TIME, function()
			if connection.Connected and not serverStarted and player:GetAttribute("HeavyAttacking") ~= true then
				stop("cancel")
			end
		end)
		return connection
	end

	local function startSpin(tool: Tool, spin: SpinHeavy)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		heavyRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		local tracks = currentTracks()
		local spinTrack = tracks and tracks.heavy
		if spinTrack then
			spinTrack:Play(0.15)
		end
		local trail = tool:FindFirstChild("SwingTrail", true)
		if trail and trail:IsA("Trail") then
			trail.Enabled = true
		end
		local walkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = spin.WalkSpeed
		setGripFlipped(tool, spin.FlipGrip == true)

		local active = true
		local attributeConnection: RBXScriptConnection? = nil

		local function stop(how: StopHow)
			if not active then
				return
			end
			active = false
			stopHeavy = nil
			if attributeConnection then
				attributeConnection:Disconnect()
			end
			if how ~= "server" then
				heavyRemote:FireServer(false)
			end
			if spinTrack then
				spinTrack:Stop(0.2)
			end
			setGripFlipped(tool, false)
			if trail and trail:IsA("Trail") then
				trail.Enabled = false
			end
			humanoid.WalkSpeed = walkSpeed
		end
		stopHeavy = stop
		-- The server ends the spin on its own at the time limit (or a weapon switch/death).
		attributeConnection = watchServer(stop)

		-- A whoosh each turn, starting when the hits do.
		task.delay(spin.WindUp, function()
			while active do
				local sound = tool:FindFirstChild("SlashSound", true)
				if sound and sound:IsA("Sound") then
					sound:Play()
				end
				task.wait(spin.TickInterval)
			end
		end)
	end

	-- Charge-and-release heavies (Quake, Thrust): wind up while held, with an indicator on
	-- the ground showing the reach (growing with the charge), then attack on release.
	local function startCharged(tool: Tool, charged: QuakeHeavy | ThrustHeavy)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		local quake: QuakeHeavy? = if charged.Kind == "Quake" then charged :: QuakeHeavy else nil
		local lunge: ThrustHeavy? = if charged.Kind == "Thrust" then charged :: ThrustHeavy else nil
		local fullChargeTime = if quake then quake.FullChargeTime elseif lunge then lunge.FullChargeTime else 1
		local lungeBonus = 1 + SkillMath.weapon(player, config.ToolName, "LungeDistance") -- matches the server (WeaponService)
		local hitDelay = if quake then quake.HitDelay elseif lunge then lunge.HitDelay else 0

		heavyRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		local tracks = currentTracks()
		local windUp = tracks and tracks.heavy
		local release = tracks and tracks.heavySlam
		if windUp then
			windUp:Play(0.1)
		end
		local walkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = charged.WalkSpeed
		local flipped = charged.FlipGrip == true
		setGripFlipped(tool, flipped)
		-- A thrust is aimed: face where the camera looks while drawing back.
		if lunge then
			humanoid.AutoRotate = false
		end

		-- The reach indicator, flat on the ground (only we see it): a disc for a quake, a
		-- strip ahead of us for a thrust.
		local indicator = Instance.new("Part")
		indicator.Name = "HeavyReach"
		indicator.Shape = if quake then Enum.PartType.Cylinder else Enum.PartType.Block
		indicator.Anchored = true
		indicator.CanCollide = false
		indicator.CanQuery = false
		indicator.CanTouch = false
		indicator.CastShadow = false
		indicator.Material = Enum.Material.Neon
		indicator.Color = REACH_COLOR
		indicator.Transparency = REACH_TRANSPARENCY
		indicator.Parent = workspace.CurrentCamera

		local groundParams = RaycastParams.new()
		groundParams.FilterType = Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }
		local started = os.clock()
		local fullyCharged = false
		local function power(): number
			return math.clamp((os.clock() - started) / fullChargeTime, 0, 1)
		end
		local renderConnection = RunService.RenderStepped:Connect(function()
			local charge = power()
			if lunge then
				local look = workspace.CurrentCamera.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
				end
			end

			local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
			local ground = (if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)) + Vector3.new(0, 0.05, 0)
			if quake then
				local radius = (quake.MinRadius + (quake.MaxRadius - quake.MinRadius) * charge) * (1 + SkillMath.weapon(player, config.ToolName, "QuakeRadius"))
				indicator.Size = Vector3.new(0.1, radius * 2, radius * 2)
				indicator.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2)
			elseif lunge then
				local length = (lunge.MinDistance + (lunge.MaxDistance - lunge.MinDistance) * charge) * lungeBonus + lunge.Reach
				local facing = CFrame.lookAt(ground, ground + root.CFrame.LookVector * Vector3.new(1, 0, 1))
				indicator.Size = Vector3.new(lunge.Width, 0.1, length)
				indicator.CFrame = facing * CFrame.new(0, 0, -length / 2)
			end

			-- Hold the wind-up on its last frame instead of letting it end.
			if windUp and windUp.IsPlaying and windUp.Speed > 0 and windUp.Length > 0 and windUp.TimePosition >= windUp.Length - 0.05 then
				windUp:AdjustSpeed(0)
			end
			if charge >= 1 and not fullyCharged then
				fullyCharged = true
				indicator.Transparency = REACH_TRANSPARENCY_FULL
				Sounds.play("ChargeLevel", workspace.CurrentCamera, 1.6)
			end
		end)

		local active = true
		local attributeConnection: RBXScriptConnection? = nil

		local function stop(how: StopHow)
			if not active then
				return
			end
			active = false
			stopHeavy = nil
			if attributeConnection then
				attributeConnection:Disconnect()
			end
			renderConnection:Disconnect()
			indicator:Destroy()
			humanoid.AutoRotate = true
			local releasePower = power()
			if windUp then
				windUp:Stop(if how == "cancel" then 0.2 else 0.05)
			end
			if how == "cancel" then
				-- Called off: no attack. (A weapon switch also cancels it on the server.)
				humanoid.WalkSpeed = walkSpeed
				setGripFlipped(tool, false)
				return
			end
			if flipped then
				-- Stays turned through the release animation (unless the next heavy has started).
				task.delay(hitDelay + UNFLIP_AFTER_HIT, function()
					if not stopHeavy then
						setGripFlipped(tool, false)
					end
				end)
			end
			if how == "release" then
				heavyRemote:FireServer(false)
			end

			-- The attack itself (a quake's shockwave is drawn for everyone; see HitEffectsClient).
			humanoid.WalkSpeed = 0
			if release then
				release:Play(0.05)
			end
			if lunge then
				local distance = (lunge.MinDistance + (lunge.MaxDistance - lunge.MinDistance) * releasePower) * lungeBonus
				Push.apply(root, root.CFrame.LookVector, distance / lunge.LungeTime, lunge.LungeTime)
			end
			local sound = tool:FindFirstChild("SlashSound", true)
			if sound and sound:IsA("Sound") then
				sound:Play()
			end
			local trail = tool:FindFirstChild("SwingTrail", true)
			if trail and trail:IsA("Trail") then
				trail.Enabled = true
			end
			task.delay(hitDelay + TRAIL_AFTER_HIT, function()
				if trail and trail:IsA("Trail") then
					trail.Enabled = false
				end
			end)
			task.delay(hitDelay + PLANTED_AFTER_HIT, function()
				humanoid.WalkSpeed = walkSpeed
			end)
		end
		stopHeavy = stop
		-- The server attacks on its own after MaxHold (and calls it off on a weapon switch/death).
		attributeConnection = watchServer(stop)
	end

	local function startHeavy(tool: Tool)
		if not heavy then
			return
		end
		if heavy.Kind == "Spin" then
			startSpin(tool, heavy :: SpinHeavy)
		elseif heavy.Kind == "Quake" then
			startCharged(tool, heavy :: QuakeHeavy)
		else
			startCharged(tool, heavy :: ThrustHeavy)
		end
	end

	local function onInputBegan(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local tool = equippedTool()
		if not tool then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if not stopBlock and not stopHeavy then
				startBlock(tool)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and heavy then
			-- Wait to see whether this is a tap (normal swing on release) or a hold (heavy).
			pressedAt = os.clock()
			pressToken += 1
			local token = pressToken
			task.delay(heavy.HoldTime, function()
				if token == pressToken and pressedAt and not stopBlock and not stopHeavy and equippedTool() == tool and heavy and Stamina.canAfford(player, SkillMath.staminaCost(player, config.ToolName, heavy.Stamina, "Heavy")) then
					startHeavy(tool)
				end
			end)
		end
	end

	local function onInputEnded(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and stopBlock then
			stopBlock()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and heavy then
			local wasPressedAt = pressedAt
			pressedAt = nil
			pressToken += 1
			if stopHeavy then
				stopHeavy("release")
			elseif wasPressedAt and os.clock() - wasPressedAt < heavy.HoldTime then
				local tool = equippedTool()
				if tool then
					onActivated(tool) -- a quick tap: normal combo swing
				end
			end
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
			-- Weapons with a heavy attack read the mouse directly (tap vs hold); the rest
			-- swing as soon as the tool is activated.
			if not heavy then
				child.Activated:Connect(function()
					onActivated(child)
				end)
			end
			child.Unequipped:Connect(function()
				if stopBlock then
					stopBlock()
				end
				if stopHeavy then
					stopHeavy("cancel")
				end
				pressedAt = nil
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
			for _, animation in { idleAnimation, guardAnimation, heavyAnimation, heavySlamAnimation } do
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
			-- A respawn clears any block, spin, or combo in progress (the server resets too).
			stopBlock = nil
			stopHeavy = nil
			pressedAt = nil
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
