--!strict
-- Hitstop: when one of your hits lands (the server's DamageDealt), your character and the
-- target freeze for a split second, longer for bigger hits, so impacts feel heavy. Only
-- animations pause (on this screen); movement, timing, and damage are unaffected.
-- Damage over time (bleed) doesn't cause hitstop.
-- Every landed hit also shakes the camera a little and punches the view in. Heavy hits (a
-- combo's last swing, a heavy attack, or a kill; the weapon scripts mark the heavy moves with
-- setHeavyWindow) punch harder and flash an impact frame: a split second of grey, harsh screen
-- with the target as a black silhouette. All of it is on this screen only.

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

-- Camera shake through Humanoid.CameraOffset, like the other shakes (block, hurt, quake). A new
-- hit keeps the stronger of the two shakes and restarts the fade.
local shakeStrength = 0
local shakeStarted = 0
local shakeConnection: RBXScriptConnection? = nil

local function shake(strength: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or strength <= 0.01 then
		return
	end
	local now = os.clock()
	local left = if shakeConnection then shakeStrength * (1 - (now - shakeStarted) / IMPACT.Shake.Time) else 0
	shakeStrength = math.max(strength, left)
	shakeStarted = now
	if shakeConnection then
		return
	end
	shakeConnection = RunService.RenderStepped:Connect(function()
		local remaining = 1 - (os.clock() - shakeStarted) / IMPACT.Shake.Time
		if remaining <= 0 or not humanoid.Parent then
			(shakeConnection :: RBXScriptConnection):Disconnect()
			shakeConnection = nil
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local s = shakeStrength * remaining
		humanoid.CameraOffset = Vector3.new(random:NextNumber(-s, s), random:NextNumber(-s, s), 0)
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

local function impactFrame(target: Model?)
	local look = IMPACT.ImpactFrame
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	if not look.Enabled or now - lastImpactFrame < look.MinGap or not camera then
		return
	end
	lastImpactFrame = now
	local effect = grade
	if not effect then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "ImpactFrame"
		made.Contrast = look.Contrast
		made.Saturation = look.Saturation
		made.Brightness = look.Brightness
		effect = made
		grade = made
	end
	local shown = effect :: ColorCorrectionEffect
	shown.Parent = camera
	shown.Enabled = true
	local silhouette: Highlight? = nil
	if target and target.Parent then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.new(0, 0, 0)
		highlight.FillTransparency = 0
		highlight.OutlineColor = look.Outline
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = target
		highlight.Parent = target
		silhouette = highlight
	end
	task.delay(look.Time, function()
		shown.Enabled = false
		if silhouette then
			silhouette:Destroy()
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
		local duration = math.clamp(HITSTOP.Base + amount * HITSTOP.PerDamage, HITSTOP.Min, HITSTOP.Max)
		freeze(animatorOf(player.Character), duration)
		freeze(animatorOf(target), duration)

		-- The server sets the target's health before telling us, so a kill already reads 0 here.
		local health = target and target:GetAttribute("Health")
		local killed = typeof(health) == "number" and health <= 0
		local heavy = killed or os.clock() < heavyUntil
		local near = if typeof(position) == "Vector3" then nearness(position) else 0
		local shakeConfig = IMPACT.Shake
		local strength = math.min(shakeConfig.Min + amount * shakeConfig.PerDamage, shakeConfig.Max)
		shake(strength * near * (if heavy then shakeConfig.Heavy else 1))
		if near > 0 then
			punchZoom(if heavy then IMPACT.Zoom.HeavyDegrees else IMPACT.Zoom.Degrees)
			if heavy then
				impactFrame(target)
			end
		end
	end)
end

return HitFeel
