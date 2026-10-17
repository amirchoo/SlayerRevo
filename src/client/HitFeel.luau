--!strict
-- Hitstop: when one of your hits lands (the server's DamageDealt), your character and the
-- target freeze for a split second, longer for bigger hits, so impacts feel heavy. Only
-- animations pause (on this screen); movement, timing, and damage are unaffected.
-- Damage over time (bleed) doesn't cause hitstop.
-- Every landed hit also jolts the camera (it slides, tilts and rolls, then rings out) and punches
-- the view in. Heavy hits (a combo's last swing, a heavy attack, or a kill; the weapon scripts
-- mark the heavy moves with setHeavyWindow) freeze longer, jolt harder and flash an impact frame:
-- a white flash, then a split second of washed-out, harsh screen with you and the target as black
-- silhouettes. All of it is on this screen only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

local HITSTOP = CombatConfig.Hitstop
local IMPACT = CombatConfig.HitImpact

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent
local player = Players.LocalPlayer
local random = Random.new()

local HitFeel = {}

-- Until when a landed hit counts as heavy (set by the weapon scripts as a heavy move starts).
local heavyUntil = 0
local lastImpactFrame = -math.huge
local grade: ColorCorrectionEffect? = nil

-- Called by the weapon scripts on every swing: for the next `seconds`, hits that land are
-- heavy (0 for an ordinary swing, which also ends the previous heavy window).
function HitFeel.setHeavyWindow(seconds: number)
	heavyUntil = if seconds > 0 then os.clock() + seconds + IMPACT.HeavySlack else 0
end

-- Animators currently frozen, with when they unfreeze and each track's speed to restore.
type Frozen = { untilTime: number, speeds: { [AnimationTrack]: number } }
local frozen: { [Animator]: Frozen } = setmetatable({}, { __mode = "k" }) :: any

local function animatorOf(model: Model?): Animator?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local controller = model and model:FindFirstChildOfClass("AnimationController")
	local holder = humanoid or controller
	return if holder then holder:FindFirstChildOfClass("Animator") else nil
end

local function freeze(animator: Animator?, duration: number)
	if not animator then
		return
	end
	local untilTime = os.clock() + duration
	local current = frozen[animator]
	if current then
		-- Already frozen (e.g. several hits at once): just extend it.
		current.untilTime = math.max(current.untilTime, untilTime)
		return
	end
	local entry: Frozen = { untilTime = untilTime, speeds = {} }
	frozen[animator] = entry
	for _, track in animator:GetPlayingAnimationTracks() do
		entry.speeds[track] = track.Speed
		track:AdjustSpeed(0)
	end
	task.spawn(function()
		while os.clock() < entry.untilTime do
			task.wait()
		end
		frozen[animator] = nil
		for track, speed in entry.speeds do
			-- Leave alone a track someone else changed meanwhile (e.g. a charge holding its pose).
			if track.IsPlaying and track.Speed == 0 then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

-- Camera shake: a jolt that rings out. It slides the view through Humanoid.CameraOffset, like the
-- other shakes (block, hurt, quake; LockOn adds it too), and tilts and rolls it on top of whatever
-- camera is running (bound after the camera and LockOn). A new hit keeps the stronger of the two
-- shakes and restarts the ring.
local SHAKE_RENDER_NAME = "HitFeelShake"
local UNDO_RENDER_NAME = "HitFeelShakeUndo"
-- The tilt and roll put on last frame. They're taken back off just before the camera updates:
-- the default camera reads its own facing back each frame, so a tilt left on would creep in.
local shakeApplied: CFrame? = nil
local shakeStrength = 0 -- studs
local shakeRoll = 0 -- degrees
local shakeStarted = 0
local shakePhase = { 0, 0, 0, 0 }
local shakeHumanoid: Humanoid? = nil
local shaking = false

local function undoShakeTurn()
	local camera = Workspace.CurrentCamera
	if shakeApplied and camera then
		camera.CFrame *= shakeApplied:Inverse()
	end
	shakeApplied = nil
end

local function stopShake()
	shaking = false
	undoShakeTurn()
	RunService:UnbindFromRenderStep(SHAKE_RENDER_NAME)
	RunService:UnbindFromRenderStep(UNDO_RENDER_NAME)
	if shakeHumanoid and shakeHumanoid.Parent then
		shakeHumanoid.CameraOffset = Vector3.zero
	end
	shakeHumanoid = nil
end

local function shake(strength: number, roll: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or strength <= 0.01 then
		return
	end
	local config = IMPACT.Shake
	local now = os.clock()
	local left = if shaking then math.max(0, 1 - (now - shakeStarted) / config.Time) ^ 2 else 0
	shakeStrength = math.max(strength, shakeStrength * left)
	shakeRoll = math.max(roll, shakeRoll * left)
	shakeStarted = now
	for i = 1, 4 do
		shakePhase[i] = random:NextNumber(0, math.pi * 2)
	end
	if random:NextNumber() < 0.5 then
		shakeRoll = -shakeRoll -- roll either way
	end
	shakeHumanoid = humanoid
	if shaking then
		return
	end
	shaking = true
	RunService:BindToRenderStep(UNDO_RENDER_NAME, Enum.RenderPriority.Camera.Value - 1, undoShakeTurn)
	RunService:BindToRenderStep(SHAKE_RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		local t = os.clock() - shakeStarted
		local remaining = 1 - t / config.Time
		local camera = Workspace.CurrentCamera
		if remaining <= 0 or not humanoid.Parent or not camera then
			stopShake()
			return
		end
		local ring = remaining * remaining -- a hard jolt that dies away quickly
		local w = 2 * math.pi * config.Frequency * t
		local s = shakeStrength * ring
		humanoid.CameraOffset = Vector3.new(math.sin(w + shakePhase[1]) * s, math.sin(w * 1.37 + shakePhase[2]) * s, 0)
		local tilt = math.rad(config.Tilt * (shakeStrength / config.Max) * ring * math.sin(w * 1.13 + shakePhase[3]))
		local roll = math.rad(shakeRoll * ring * math.cos(w * 0.9 + shakePhase[4] * 0.2))
		local turn = CFrame.Angles(tilt, 0, roll)
		camera.CFrame *= turn
		shakeApplied = turn
	end)
end

-- Zoom punch. Applied as a change on top of whatever the field of view is, so a bow's aim zoom
-- (which sets it outright) and this never fight for long.
local zoomApplied = 0 -- degrees we've currently taken off the field of view
local zoomFrom = 0
local zoomDegrees = 0
local zoomStarted = 0
local zoomConnection: RBXScriptConnection? = nil

local function punchZoom(degrees: number)
	zoomFrom = zoomApplied
	zoomDegrees = math.max(degrees, zoomApplied)
	zoomStarted = os.clock()
	if zoomConnection then
		return
	end
	zoomConnection = RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		local t = os.clock() - zoomStarted
		local zoom = IMPACT.Zoom
		local target
		if t < zoom.In then
			target = zoomFrom + (zoomDegrees - zoomFrom) * (t / zoom.In)
		else
			local back = math.min((t - zoom.In) / zoom.Out, 1)
			target = zoomDegrees * (1 - back) ^ 2 -- quick at first, settling gently
		end
		if camera then
			camera.FieldOfView += zoomApplied - target
		end
		zoomApplied = target
		if t >= zoom.In + zoom.Out then
			zoomApplied = 0;
			(zoomConnection :: RBXScriptConnection):Disconnect()
			zoomConnection = nil
		end
	end)
end

local function silhouette(model: Model?, outline: Color3): Highlight?
	if not (model and model.Parent) then
		return nil
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(0, 0, 0)
	highlight.FillTransparency = 0
	highlight.OutlineColor = outline
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

local function impactFrame(target: Model?)
	local look = IMPACT.ImpactFrame
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	if not look.Enabled or now - lastImpactFrame < look.MinGap or not camera then
		return
	end
	lastImpactFrame = now
	local effect = grade or Instance.new("ColorCorrectionEffect")
	effect.Name = "ImpactFrame"
	grade = effect
	-- First a near-white flash, then the harsh washed-out frame with the silhouettes.
	effect.Contrast = look.Contrast
	effect.Saturation = look.Saturation
	effect.Brightness = look.FlashBrightness
	effect.Parent = camera
	effect.Enabled = true
	local shapes: { Highlight } = {}
	local targetShape = silhouette(target, look.Outline)
	if targetShape then
		table.insert(shapes, targetShape)
	end
	local attackerShape = if look.Attacker then silhouette(player.Character, look.AttackerOutline) else nil
	if attackerShape then
		table.insert(shapes, attackerShape)
	end
	task.delay(look.FlashTime, function()
		effect.Brightness = look.Brightness
	end)
	task.delay(look.Time, function()
		effect.Enabled = false
		for _, shape in shapes do
			shape:Destroy()
		end
	end)
end

-- How much of the shake a hit at `position` gets: all of it up close, none for far-off shots.
local function nearness(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	local distance = (root.Position - position).Magnitude
	local shakeConfig = IMPACT.Shake
	return 1 - math.clamp((distance - shakeConfig.FullRange) / (shakeConfig.NoneRange - shakeConfig.FullRange), 0, 1)
end

function HitFeel.start()
	damageRemote.OnClientEvent:Connect(function(position: Vector3, amount: number, kind: string?, target: Model?)
		if kind ~= nil then
			return -- damage over time
		end
		-- The server sets the target's health before telling us, so a kill already reads 0 here.
		local health = target and target:GetAttribute("Health")
		local killed = typeof(health) == "number" and health <= 0
		local heavy = killed or os.clock() < heavyUntil

		local duration = math.clamp(HITSTOP.Base + amount * HITSTOP.PerDamage, HITSTOP.Min, HITSTOP.Max)
			+ (if heavy then HITSTOP.Heavy else 0)
		freeze(animatorOf(player.Character), duration)
		freeze(animatorOf(target), duration)
		local near = if typeof(position) == "Vector3" then nearness(position) else 0
		local shakeConfig = IMPACT.Shake
		local strength = math.min(shakeConfig.Min + amount * shakeConfig.PerDamage, shakeConfig.Max)
		shake(strength * near * (if heavy then shakeConfig.Heavy else 1), (if heavy then shakeConfig.HeavyRoll else shakeConfig.Roll) * near)
		if near > 0 then
			punchZoom(if heavy then IMPACT.Zoom.HeavyDegrees else IMPACT.Zoom.Degrees)
			if heavy then
				impactFrame(target)
			end
		end
	end)
end

return HitFeel
