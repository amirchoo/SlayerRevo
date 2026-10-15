--!strict
-- Input and visuals for click-combo weapons (sword, mace, spear, dual blade, scythe...), one controller per weapon config.
-- While equipped the idle animation loops. Left-click steps through the combo: each click
-- plays the next swing, and pausing too long (or finishing the last swing) starts it over.
-- The server decides what's hit and how hard (see WeaponService). Holding right-click raises
-- a guard and tells the server we're blocking (see BlockService). With a shield worn and a
-- one-handed weapon, the idle and guard are the weapon's shield stance instead
-- (ShieldConfig.Stances); the attacks stay the same.
-- Weapons with a heavy attack tell a tap from a hold: a quick tap (released within
-- Heavy.HoldTime) is a normal combo swing, while holding starts the heavy:
--   Spin: spins until release. The server runs the spin's hits and can end it early (time
--   limit, weapon switch, death).
--   Quake: raises the weapon while a ring on the ground shows how far the smash will reach
--   (growing with the charge); release smashes the ground.
--   Thrust: draws back, turning with the camera, while a strip on the ground shows how far
--   the lunge will carry; release lunges forward.
--   Flurry: draws back like a thrust (aimed the same way); release plants you in a run of
--   rapid stabs, more for a longer charge.
--   For all three, the server times the charge and attacks by itself at MaxHold.
--   Rush: gathers (nearly planted) for ChargeTime, then surges wherever we walk (straight on
--   if we aren't), spinning, until release. The server runs its hits and can end it early
--   (time limit, out of stamina, weapon switch, death); letting go while gathering calls it off.
--   Reap: one press plays the whole move, aimed where the camera looks: reach out and hook,
--   yank back, cut. Letting go doesn't stop it; the server ends it (see WeaponService).
-- Dual-wielded weapons (DualWield) hold a second blade in the other hand; both trail.
-- The server's "HeavyAttacking" attribute going false ends the visuals here too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local ShieldConfig = require(ReplicatedStorage.Shared.Config.ShieldConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Stamina = require(ReplicatedStorage.Shared.Stamina)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local CombatInput = require(script.Parent.CombatInput)
local ParryPredict = require(script.Parent.ParryPredict)
local Push = require(script.Parent.Push)

type ComboWeapon = CombatConfig.ComboWeapon
type SpinHeavy = CombatConfig.SpinHeavy
type QuakeHeavy = CombatConfig.QuakeHeavy
type ThrustHeavy = CombatConfig.ThrustHeavy
type FlurryHeavy = CombatConfig.FlurryHeavy
type RushHeavy = CombatConfig.RushHeavy
type ReapHeavy = CombatConfig.ReapHeavy
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
local FLURRY_SOUND_SPEEDUP = 0.4 -- a fully charged flurry's stab sounds play this much faster

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

-- Turns the swing trails on or off (both blades' for a dual-wielded weapon).
local function setTrails(tool: Tool, enabled: boolean)
	for _, descendant in tool:GetDescendants() do
		if descendant.Name == "SwingTrail" and descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

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
	shieldIdle: AnimationTrack?, -- a one-handed weapon's idle with a shield worn
	guard: AnimationTrack?,
	shieldGuard: AnimationTrack?, -- a one-handed weapon's guard with a shield worn
	heavy: AnimationTrack?, -- spin loop, a quake's or thrust's wind-up, or the whole reap
	heavySlam: AnimationTrack?, -- a quake's smash, a thrust's lunge, a flurry's stabs, a rush's spin
	swings: { AnimationTrack },
}

local HEAVY_CONFIRM_TIME = 0.5 -- if the server hasn't started the spin by now, it refused

-- Creates the controller for one combo weapon; call :start() once on the client.
function ComboWeaponClient.new(config: ComboWeapon)
	local combo = config.Combo
	local weldName = `{config.ToolName}Grip`
	local localWeldName = `Local{weldName}`
	local offhandWeldName = `{config.ToolName}OffhandGrip`

	local idleAnimation = makeAnimation(config.IdleAnimation)
	local guardAnimation = makeAnimation(config.Block.Animation)
	local shieldIdleAnimation: Animation? = nil
	local shieldGuardAnimation: Animation? = nil
	if ShieldConfig.canUseWith(config.ToolName) then
		local stance = ShieldConfig.Stances[config.ToolName]
		shieldIdleAnimation = if stance then makeAnimation(stance.Idle) else nil
		shieldGuardAnimation = makeAnimation(if stance and stance.Guard ~= "" then stance.Guard else ShieldConfig.GuardAnimation)
	end
	local heavy = config.Heavy
	local heavyAnimation: Animation? = nil
	local heavySlamAnimation: Animation? = nil
	if heavy and heavy.Kind == "Spin" then
		heavyAnimation = makeAnimation((heavy :: SpinHeavy).Animation)
	elseif heavy and heavy.Kind == "Quake" then
		local quake = heavy :: QuakeHeavy
		heavyAnimation = makeAnimation(quake.WindUpAnimation)
		heavySlamAnimation = makeAnimation(quake.SlamAnimation)
	elseif heavy and heavy.Kind == "Flurry" then
		local stabs = heavy :: FlurryHeavy
		heavyAnimation = makeAnimation(stabs.WindUpAnimation)
		heavySlamAnimation = makeAnimation(stabs.FlurryAnimation)
	elseif heavy and heavy.Kind == "Rush" then
		local rush = heavy :: RushHeavy
		heavyAnimation = makeAnimation(rush.WindUpAnimation)
		heavySlamAnimation = makeAnimation(rush.RushAnimation)
	elseif heavy and heavy.Kind == "Reap" then
		heavyAnimation = makeAnimation((heavy :: ReapHeavy).Animation)
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
		if shieldIdleAnimation then
			local shieldIdle = animator:LoadAnimation(shieldIdleAnimation)
			shieldIdle.Priority = Enum.AnimationPriority.Idle
			shieldIdle.Looped = true
			tracks.shieldIdle = shieldIdle
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
		if shieldGuardAnimation then
			local shieldGuard = animator:LoadAnimation(shieldGuardAnimation)
			shieldGuard.Priority = Enum.AnimationPriority.Action
			shieldGuard.Looped = true
			tracks.shieldGuard = shieldGuard
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
			slam.Looped = heavy ~= nil and (heavy.Kind == "Flurry" or heavy.Kind == "Rush") -- loops until it ends
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
	local function equippedTool(): Tool?
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		return if tool and tool.Name == config.ToolName then tool else nil
	end

	local function shielded(): boolean
		return typeof(player:GetAttribute("Shield")) == "string"
	end

	-- Loops the idle that fits (the shield stance's while a shield is worn) and stops the other.
	local function playIdle()
		local tracks = currentTracks()
		if not tracks then
			return
		end
		local idle = if shielded() and tracks.shieldIdle then tracks.shieldIdle else tracks.idle
		for _, track in { tracks.idle, tracks.shieldIdle } :: { AnimationTrack? } do
			if track and track ~= idle and track.IsPlaying then
				track:Stop(0.2)
			end
		end
		if idle and not idle.IsPlaying then
			idle:Play(0.2)
		end
	end

	local function stopIdle()
		local tracks = currentTracks()
		for _, track in { tracks and tracks.idle, tracks and tracks.shieldIdle } :: { AnimationTrack? } do
			if track then
				track:Stop(0.2)
			end
		end
	end

	-- Moves always end at the character's normal speed (never a speed saved mid-move: a heavy
	-- started while the last one still had us planted would save 0 and leave us stuck): the
	-- weapon's own WalkSpeed while it's still in hand (heavy weapons), else the default.
	local function normalSpeed(): number
		return if config.WalkSpeed and equippedTool() then config.WalkSpeed else StarterPlayer.CharacterWalkSpeed
	end
	-- Set during a heavy; call it to end it (see StopHow).
	local stopHeavy: ((how: StopHow) -> ())? = nil
	-- When the left button went down (nil when it's up), and a token to tell presses apart.
	local pressedAt: number? = nil
	local pressToken = 0
	-- Until when a flurry is still stabbing (no swings or new heavies until then).
	local busyUntil = 0

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
			Sounds.replay(sound)
		end

		swingToken += 1
		local token = swingToken
		setTrails(tool, true)
		task.delay(combo[step].HitDelay + TRAIL_AFTER_HIT, function()
			if token == swingToken then
				setTrails(tool, false)
			end
		end)
	end

	local function onActivated(tool: Tool)
		-- Local checks only avoid pointless requests; the server enforces the real ones.
		if stopBlock or os.clock() < busyUntil then
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
		ParryPredict.guardUp() -- the clang can play without waiting for the server
		comboStep = 0
		stopSwings(0.1)
		setTrails(tool, false)

		local tracks = currentTracks()
		local guardTrack = tracks and (if shielded() and tracks.shieldGuard then tracks.shieldGuard else tracks.guard)
		if guardTrack then
			guardTrack:Play(0.1)
		else
			local weld = localWeld(tool)
			if weld then
				TweenService:Create(weld, GUARD_TWEEN, { C1 = tool.Grip * GUARD_GRIP }):Play()
			end
		end
		humanoid.WalkSpeed = BLOCKING.WalkSpeed

		stopBlock = function()
			stopBlock = nil
			blockRemote:FireServer(false)
			ParryPredict.guardDown()
			if guardTrack then
				guardTrack:Stop(0.15)
			else
				local currentWeld = localWeld(tool)
				if currentWeld then
					TweenService:Create(currentWeld, GUARD_TWEEN, { C1 = tool.Grip }):Play()
				end
			end
			humanoid.WalkSpeed = normalSpeed()
		end
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
		setTrails(tool, true)
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
			setTrails(tool, false)
			humanoid.WalkSpeed = normalSpeed()
		end
		stopHeavy = stop
		-- The server ends the spin on its own at the time limit (or a weapon switch/death).
		attributeConnection = watchServer(stop)

		-- A whoosh each turn, starting when the hits do.
		task.delay(spin.WindUp, function()
			while active do
				local sound = tool:FindFirstChild("SlashSound", true)
				if sound and sound:IsA("Sound") then
					Sounds.replay(sound)
				end
				task.wait(spin.TickInterval)
			end
		end)
	end

	-- Charge-and-release heavies (Quake, Thrust): wind up while held, with an indicator on
	-- the ground showing the reach (growing with the charge), then attack on release.
	local function startCharged(tool: Tool, charged: QuakeHeavy | ThrustHeavy | FlurryHeavy)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		local quake: QuakeHeavy? = if charged.Kind == "Quake" then charged :: QuakeHeavy else nil
		local lunge: ThrustHeavy? = if charged.Kind == "Thrust" then charged :: ThrustHeavy else nil
		local stabs: FlurryHeavy? = if charged.Kind == "Flurry" then charged :: FlurryHeavy else nil
		local fullChargeTime = if quake then quake.FullChargeTime elseif lunge then lunge.FullChargeTime elseif stabs then stabs.FullChargeTime else 1
		local lungeBonus = 1 + SkillMath.weapon(player, config.ToolName, "LungeDistance") -- matches the server (WeaponService)
		local hitDelay = if quake then quake.HitDelay elseif lunge then lunge.HitDelay elseif stabs then stabs.HitDelay else 0
		local aimed = lunge ~= nil or stabs ~= nil

		heavyRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		local tracks = currentTracks()
		local windUp = tracks and tracks.heavy
		local release = tracks and tracks.heavySlam
		if windUp then
			windUp:Play(0.1)
		end
		humanoid.WalkSpeed = charged.WalkSpeed
		local flipped = charged.FlipGrip == true
		setGripFlipped(tool, flipped)
		-- A thrust (or flurry) is aimed: face where the camera looks while drawing back.
		if aimed then
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
			if aimed then
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
			elseif stabs then
				local facing = CFrame.lookAt(ground, ground + root.CFrame.LookVector * Vector3.new(1, 0, 1))
				indicator.Size = Vector3.new(stabs.Width, 0.1, stabs.Range)
				indicator.CFrame = facing * CFrame.new(0, 0, -stabs.Range / 2)
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
				humanoid.WalkSpeed = normalSpeed()
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
			-- How long the attack keeps us planted after release: a flurry until its last stab.
			local attackTime = hitDelay
			if stabs then
				local hits = CombatConfig.flurryHits(stabs, releasePower, SkillMath.weapon(player, config.ToolName, "FlurryHits"))
				attackTime = stabs.HitDelay + (hits - 1) * stabs.Interval
				busyUntil = os.clock() + attackTime
				Push.apply(root, root.CFrame.LookVector, stabs.Advance, attackTime)
				-- A stab sound on every stab, played faster the harder it was charged (overlapping,
				-- so the rapid ones don't cut each other off).
				local stabSound = tool:FindFirstChild("SlashSound", true)
				local rate = 1 + FLURRY_SOUND_SPEEDUP * releasePower
				for stab = 1, hits do
					task.delay(stabs.HitDelay + (stab - 1) * stabs.Interval, function()
						if stabSound and stabSound:IsA("Sound") and tool.Parent == character then
							Sounds.playCopy(stabSound, rate)
						end
					end)
				end
				if release then
					task.delay(attackTime + 0.05, function()
						release:Stop(0.15)
					end)
				end
			end
			if release then
				release:Play(0.05)
			end
			if lunge then
				local distance = (lunge.MinDistance + (lunge.MaxDistance - lunge.MinDistance) * releasePower) * lungeBonus
				Push.apply(root, root.CFrame.LookVector, distance / lunge.LungeTime, lunge.LungeTime)
			end
			local sound = tool:FindFirstChild("SlashSound", true)
			if not stabs and sound and sound:IsA("Sound") then
				Sounds.replay(sound) -- (a flurry plays its own, one per stab)
			end
			setTrails(tool, true)
			task.delay(attackTime + TRAIL_AFTER_HIT, function()
				setTrails(tool, false)
			end)
			task.delay(attackTime + PLANTED_AFTER_HIT, function()
				-- A heavy or block started since sets its own speed (and restores it after).
				if not stopHeavy and not stopBlock then
					humanoid.WalkSpeed = normalSpeed()
				end
			end)
		end
		stopHeavy = stop
		-- The server attacks on its own after MaxHold (and calls it off on a weapon switch/death).
		attributeConnection = watchServer(stop)
	end

	-- Rush: gather while held, then surge wherever we walk, spinning, until release.
	local function startRush(tool: Tool, rush: RushHeavy)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") then
			return
		end

		heavyRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		local tracks = currentTracks()
		local windUp = tracks and tracks.heavy
		local rushTrack = tracks and tracks.heavySlam
		if windUp then
			windUp:Play(0.1)
		end
		humanoid.WalkSpeed = rush.WalkSpeed
		setGripFlipped(tool, rush.FlipGrip == true)

		local active = true
		local rushing = false
		local attributeConnection: RBXScriptConnection? = nil
		local steer: ((Vector3, number) -> ())? = nil
		local stopPush: (() -> ())? = nil
		local direction = root.CFrame.LookVector

		local renderConnection = RunService.RenderStepped:Connect(function(dt)
			if not rushing then
				-- Hold the gathering pose on its last frame.
				if windUp and windUp.IsPlaying and windUp.Speed > 0 and windUp.Length > 0 and windUp.TimePosition >= windUp.Length - 0.05 then
					windUp:AdjustSpeed(0)
				end
				return
			end
			-- Turn toward where we're walking (smoothly), or keep going the same way.
			local wanted = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
			if wanted.Magnitude > 0.1 then
				local turned = direction:Lerp(wanted.Unit, math.min(1, dt * 10))
				if turned.Magnitude > 0.01 then
					direction = turned.Unit
				end
			end
			if steer then
				steer(direction, rush.Speed)
			end
		end)

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
			if stopPush then
				stopPush()
			end
			if how ~= "server" then
				heavyRemote:FireServer(false)
			end
			if windUp then
				windUp:Stop(0.15)
			end
			if rushTrack then
				rushTrack:Stop(0.2)
			end
			setGripFlipped(tool, false)
			setTrails(tool, false)
			humanoid.WalkSpeed = normalSpeed()
		end
		stopHeavy = stop
		-- The server ends the rush on its own (time limit, stamina, weapon switch, death).
		attributeConnection = watchServer(stop)

		-- The rush starts once gathered (when the server starts its hits).
		task.delay(rush.ChargeTime, function()
			if not active then
				return
			end
			rushing = true
			if windUp then
				windUp:Stop(0.1)
			end
			if rushTrack then
				rushTrack:Play(0.1)
			end
			setTrails(tool, true)
			humanoid.WalkSpeed = rush.Speed
			local flat = Vector3.new(direction.X, 0, direction.Z)
			direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			steer, stopPush = Push.hold(root)
			Sounds.play("ChargeLevel", workspace.CurrentCamera, 1.6)
			-- A whoosh each turn.
			while active do
				local sound = tool:FindFirstChild("SlashSound", true)
				if sound and sound:IsA("Sound") then
					Sounds.replay(sound)
				end
				task.wait(rush.TickInterval)
			end
		end)
	end

	-- Reap: the whole move from one press, facing where the camera looks; the server lands the
	-- hook and the cut, and ends it.
	local function startReap(tool: Tool, reap: ReapHeavy)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") then
			return
		end

		-- Turn to the camera first, so the server hooks the way we're looking.
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
		humanoid.AutoRotate = false
		heavyRemote:FireServer(true)
		comboStep = 0
		stopSwings(0.1)
		busyUntil = os.clock() + reap.Duration
		local tracks = currentTracks()
		local reapTrack = tracks and tracks.heavy
		if reapTrack then
			reapTrack:Play(0.1)
		end
		humanoid.WalkSpeed = reap.WalkSpeed
		setGripFlipped(tool, reap.FlipGrip == true)
		setTrails(tool, true)

		local active = true
		local attributeConnection: RBXScriptConnection? = nil
		local function stop(how: StopHow)
			if not active or how == "release" then
				return -- letting go doesn't stop a reap
			end
			active = false
			stopHeavy = nil
			busyUntil = 0
			if attributeConnection then
				attributeConnection:Disconnect()
			end
			if reapTrack and how == "cancel" then
				reapTrack:Stop(0.2)
			end
			humanoid.AutoRotate = true
			setGripFlipped(tool, false)
			setTrails(tool, false)
			humanoid.WalkSpeed = normalSpeed()
		end
		stopHeavy = stop
		attributeConnection = watchServer(stop)

		-- A whoosh for the reach and another for the cut.
		for _, at in { 0, reap.CutDelay - 0.08 } do
			task.delay(at, function()
				local sound = tool:FindFirstChild("SlashSound", true)
				if active and sound and sound:IsA("Sound") then
					Sounds.replay(sound)
				end
			end)
		end
	end

	local function startHeavy(tool: Tool)
		if not heavy then
			return
		end
		if heavy.Kind == "Spin" then
			startSpin(tool, heavy :: SpinHeavy)
		elseif heavy.Kind == "Quake" then
			startCharged(tool, heavy :: QuakeHeavy)
		elseif heavy.Kind == "Flurry" then
			startCharged(tool, heavy :: FlurryHeavy)
		elseif heavy.Kind == "Rush" then
			startRush(tool, heavy :: RushHeavy)
		elseif heavy.Kind == "Reap" then
			startReap(tool, heavy :: ReapHeavy)
		else
			startCharged(tool, heavy :: ThrustHeavy)
		end
	end

	local function onBlockBegan()
		local tool = equippedTool()
		if tool and not stopBlock and not stopHeavy then
			startBlock(tool)
		end
	end

	local function onBlockEnded()
		if stopBlock then
			stopBlock()
		end
	end

	local function onAttackBegan()
		local tool = equippedTool()
		if not tool then
			return
		end
		if not heavy then
			onActivated(tool) -- no heavy: every press is a swing
		else
			-- Wait to see whether this is a tap (normal swing on release) or a hold (heavy).
			pressedAt = os.clock()
			pressToken += 1
			local token = pressToken
			task.delay(heavy.HoldTime, function()
				if token == pressToken and pressedAt and not stopBlock and not stopHeavy and os.clock() >= busyUntil and equippedTool() == tool and heavy and Stamina.canAfford(player, SkillMath.staminaCost(player, config.ToolName, heavy.Stamina, "Heavy")) then
					startHeavy(tool)
				end
			end)
		end
	end

	local function onAttackEnded()
		if heavy then
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
			if config.DualWield then
				HandGrip.attachLocal(child, character, HandGrip.opposite(config.Hand :: HandGrip.Hand), offhandWeldName, HandGrip.OFFHAND_NAME)
			end
			playIdle()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if config.WalkSpeed and humanoid then
				humanoid.WalkSpeed = config.WalkSpeed
			end
		end

		if not hookedTools[child] then
			hookedTools[child] = true
			child.Unequipped:Connect(function()
				if stopBlock then
					stopBlock()
				end
				if stopHeavy then
					stopHeavy("cancel")
				end
				pressedAt = nil
				HandGrip.detach(child, localWeldName)
				HandGrip.detach(child, `Local{offhandWeldName}`, HandGrip.OFFHAND_NAME)
				comboStep = 0
				stopIdle()
				stopSwings(0.1)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if config.WalkSpeed and humanoid then
					humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
				end
			end)
		end
	end

	local controller = {}

	function controller.start()
		-- Load the animations up front so the first swing doesn't stall.
		task.spawn(function()
			local preload: { Instance } = {}
			for _, animation in { idleAnimation, shieldIdleAnimation, guardAnimation, shieldGuardAnimation, heavyAnimation, heavySlamAnimation } :: { Animation? } do
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

		CombatInput.AttackBegan:Connect(onAttackBegan)
		CombatInput.AttackEnded:Connect(onAttackEnded)
		CombatInput.BlockBegan:Connect(onBlockBegan)
		CombatInput.BlockEnded:Connect(onBlockEnded)
		-- Putting a shield on or taking it off with the weapon out swaps the idle.
		player:GetAttributeChangedSignal("Shield"):Connect(function()
			if equippedTool() then
				playIdle()
			end
		end)

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
