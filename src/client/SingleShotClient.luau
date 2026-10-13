--!strict
-- Input and visuals for a weapon that fires once and then reloads (the crossbow, the
-- blunderbuss; see SingleShotService), one instance per config:
-- SingleShotClient.new(CombatConfig.Crossbow).start(). While equipped the idle animation
-- loops. Hold Block (right-click) to aim: the aim animation raises it to the shoulder, the
-- camera zooms in, the player slows and faces the aim. Attack (left-click) fires if it's
-- loaded, aiming or not: the shoot animation kicks; once the clip is empty (every shot, for a
-- one-shot clip) the reload animation plays (paced to the reload time) and the player walks
-- slower until it's loaded again. The server owns ammo,
-- the "Loaded" state, the shot's flight, and damage; this only asks to shoot and shows what
-- the server decided.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Stamina = require(ReplicatedStorage.Shared.Stamina)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)
local CombatInput = require(script.Parent.CombatInput)
local Aim = require(script.Parent.Aim)

local HOLD_MARGIN = 0.05 -- pause the aim this close to its end so it holds the raised pose
local SHOT_KICK_TIME = 0.25 -- the shoot animation plays this long before the reload takes over
local PENDING_TIMEOUT = 0.6 -- give up waiting for the server to answer a shot after this long

local player = Players.LocalPlayer

local SingleShotClient = {}

type Tracks = { [string]: AnimationTrack }

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil -- not published yet
	end
	local animation = Instance.new("Animation")
	-- A bare number (e.g. pasted straight from the Creator Dashboard) still works.
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animation
end

function SingleShotClient.new(config: CombatConfig.SingleShot)
	local self = {}
	local shootRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(config.ShootRemote) :: RemoteEvent
	local gripName = config.ToolName .. "Grip"

	-- By role; a role whose animation isn't published yet is left out.
	local ANIMATIONS: { [string]: Animation } = {}
	for role, id in { idle = config.IdleAnimation, aim = config.AimAnimation, shoot = config.ShootAnimation, reload = config.ReloadAnimation } do
		ANIMATIONS[role] = makeAnimation(id)
	end
	-- Reload over shoot over aim over idle, so each shows through the one below it.
	local PRIORITIES: { [string]: Enum.AnimationPriority } = {
		idle = Enum.AnimationPriority.Idle,
		aim = Enum.AnimationPriority.Action,
		shoot = Enum.AnimationPriority.Action2,
		reload = Enum.AnimationPriority.Action3,
	}

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
				local track = animator:LoadAnimation(animation)
				track.Priority = PRIORITIES[name]
				track.Looped = name == "idle"
				tracks[name] = track
			end
		end
		tracksByHumanoid[humanoid] = tracks
		return tracks
	end

	local function currentHumanoid(): Humanoid?
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	local function equippedTool(): Tool?
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		return if tool and tool.Name == config.ToolName then tool else nil
	end

	-- Same formula as SingleShotService.reloadTime.
	local function reloadTime(): number
		return config.ReloadTime * math.max(1 - SkillMath.weapon(player, config.ToolName, "ReloadSpeed"), 0.3)
	end

	-- Walk speed: the slowest of what aiming and reloading ask for, normal otherwise.
	local aiming = false
	local reloadingVisual = false
	local function applyWalkSpeed()
		local humanoid = currentHumanoid()
		if not humanoid then
			return
		end
		local speed = StarterPlayer.CharacterWalkSpeed
		if aiming then
			speed = math.min(speed, config.AimWalkSpeed)
		end
		if reloadingVisual then
			speed = math.min(speed, config.ReloadWalkSpeed)
		end
		humanoid.WalkSpeed = speed
	end

	local function faceAim(point: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
			if flat.Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			end
		end
	end

	local function aimPoint(): Vector3
		local arrows = workspace:FindFirstChild("Arrows")
		return Aim.point(if arrows then { arrows } else nil)
	end

	-- Aiming --------------------------------------------------------------------------------

	-- The camera's field of view before aiming zoomed it; kept until the zoom-out finishes, so
	-- aiming again mid zoom-out still returns to the real original.
	local normalFov: number? = nil
	local zoomTween: Tween? = nil
	local aimConnection: RBXScriptConnection? = nil

	local function zoomTo(fov: number, time: number, onDone: (() -> ())?)
		local camera = workspace.CurrentCamera
		if zoomTween then
			zoomTween:Cancel()
		end
		local tween = TweenService:Create(camera, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fov })
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and zoomTween == tween then
				zoomTween = nil
				if onDone then
					onDone()
				end
			end
		end)
		zoomTween = tween
		tween:Play()
	end

	local function startAim()
		local humanoid = currentHumanoid()
		if aiming or not humanoid or not equippedTool() then
			return
		end
		aiming = true
		humanoid.AutoRotate = false
		applyWalkSpeed()

		normalFov = normalFov or workspace.CurrentCamera.FieldOfView
		zoomTo(config.AimZoomFov, config.AimZoomTime)

		local tracks = getTracks(humanoid)
		local aim = tracks.aim
		if aim then
			aim:Play(0.1)
		end
		aimConnection = RunService.RenderStepped:Connect(function()
			faceAim(aimPoint())
			-- Freeze on the last frame instead of letting the non-looping track end.
			if aim and aim.IsPlaying and aim.Speed > 0 and aim.Length > 0 and aim.TimePosition >= aim.Length - HOLD_MARGIN then
				aim:AdjustSpeed(0)
			end
		end)
	end

	local function stopAim()
		if not aiming then
			return
		end
		aiming = false
		if aimConnection then
			aimConnection:Disconnect()
			aimConnection = nil
		end
		local humanoid = currentHumanoid()
		if humanoid then
			humanoid.AutoRotate = true
			local tracks = tracksByHumanoid[humanoid]
			if tracks and tracks.aim then
				tracks.aim:Stop(0.2)
			end
		end
		applyWalkSpeed()
		if normalFov then
			zoomTo(normalFov, config.ZoomOutTime, function()
				normalFov = nil
			end)
		end
	end

	-- Firing and reloading ------------------------------------------------------------------

	local pendingShot = 0 -- when we last asked to shoot; blocks double shots until the server answers
	local lastFired = 0 -- when we last fired; shots from one clip are at least ShotDelay apart
	local reloadStart: thread? = nil

	local function stopReloadVisual()
		if reloadStart then
			task.cancel(reloadStart)
			reloadStart = nil
		end
		reloadingVisual = false
		local humanoid = currentHumanoid()
		local tracks = humanoid and tracksByHumanoid[humanoid]
		if tracks and tracks.reload then
			tracks.reload:Stop(0.15)
		end
		applyWalkSpeed()
	end

	-- Plays the reload, timed to end when the server says it's loaded. `delay` leaves room for
	-- the shot's kick first.
	local function startReloadVisual(delay: number)
		stopReloadVisual()
		reloadingVisual = true
		applyWalkSpeed()
		local total = reloadTime()
		reloadStart = task.delay(delay, function()
			reloadStart = nil
			local humanoid = currentHumanoid()
			local reload = humanoid and getTracks(humanoid).reload
			if reload then
				local remaining = math.max(total - delay, 0.1)
				reload:Play(0.1, 1, if reload.Length > 0 then reload.Length / remaining else 1)
			end
		end)
	end

	local function fire()
		local tool = equippedTool()
		local ammo = player:GetAttribute(config.Ammo)
		-- Local checks only avoid pointless requests; the server enforces the real ones.
		if not tool or not tool:GetAttribute("Loaded") or typeof(ammo) ~= "number" or ammo <= 0 then
			return
		end
		if os.clock() - pendingShot < PENDING_TIMEOUT or os.clock() - lastFired < (config.ShotDelay or 0) then
			return
		end
		if not Stamina.canAfford(player, SkillMath.staminaCost(player, config.ToolName, config.ShotStamina, "Light")) then
			return
		end
		pendingShot = os.clock()
		lastFired = pendingShot
		local point = aimPoint()
		faceAim(point)
		shootRemote:FireServer(point)
		local humanoid = currentHumanoid()
		local shoot = humanoid and getTracks(humanoid).shoot
		if shoot then
			shoot:Play(0.05)
		end
	end

	-- Tools ---------------------------------------------------------------------------------

	local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function hookTool(child: Instance)
		if not child:IsA("Tool") or child.Name ~= config.ToolName then
			return
		end
		local tool = child :: Tool
		-- Equipping moves the tool into the character: weld it into its hand locally right
		-- away; the server adds the replicated weld (see HandGrip).
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and tool.Parent == character then
			HandGrip.attachLocal(tool, character, config.Hand :: HandGrip.Hand, gripName)
			local idle = humanoid and getTracks(humanoid).idle
			if idle then
				idle:Play(0.2)
			end
			if not tool:GetAttribute("Loaded") then
				startReloadVisual(0) -- the server picks the reload back up on equip
			end
		end

		if not hookedTools[tool] then
			hookedTools[tool] = true
			-- A shot that leaves rounds in the clip only changes Rounds; the last one also
			-- clears Loaded.
			tool:GetAttributeChangedSignal("Rounds"):Connect(function()
				pendingShot = 0 -- the server answered
			end)
			tool:GetAttributeChangedSignal("Loaded"):Connect(function()
				if tool.Parent ~= player.Character then
					return
				end
				pendingShot = 0 -- the server answered
				if tool:GetAttribute("Loaded") then
					stopReloadVisual()
				else
					startReloadVisual(SHOT_KICK_TIME)
				end
			end)
			tool.Unequipped:Connect(function()
				HandGrip.detach(tool, "Local" .. gripName)
				stopAim()
				stopReloadVisual()
				local current = currentHumanoid()
				local tracks = current and tracksByHumanoid[current]
				if tracks and tracks.idle then
					tracks.idle:Stop(0.2)
				end
			end)
		end
	end

	function self.start()
		-- Load the animations up front so the first use doesn't stall or have Length 0.
		local preload: { Instance } = {}
		for _, animation in ANIMATIONS do
			table.insert(preload, animation)
		end
		task.spawn(function()
			ContentProvider:PreloadAsync(preload)
		end)

		CombatInput.AttackBegan:Connect(fire)
		CombatInput.BlockBegan:Connect(startAim)
		CombatInput.BlockEnded:Connect(stopAim)

		local function onCharacterAdded(character: Model)
			-- A respawn resets everything.
			stopAim()
			stopReloadVisual()
			pendingShot = 0
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

	return self
end

return SingleShotClient
