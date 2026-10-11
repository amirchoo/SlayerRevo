--!strict
-- Hit effects on enemies: knockback, stun, bleed, and the flinch when hit. Enemies are simulated by the server,
-- so these happen here (players' own characters are pushed by their clients instead).
-- A stunned enemy has a "StunnedUntil" attribute (server os.clock() time); EnemyService
-- checks it to freeze the enemy and cancel its wind-up attacks.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)

local STUN_LABEL_NAME = "StunLabel"
local BLEED_DRIPS_NAME = "BleedDrips"

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

local flinchAnimation: Animation? = nil
if EnemyConfig.FlinchAnimation ~= "" then
	flinchAnimation = Instance.new("Animation")
	local id = EnemyConfig.FlinchAnimation
	flinchAnimation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
end
local flinchTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any

-- The running bleed per model (a unique table, so a replaced bleed's loop knows to stop).
local bleeds: { [Model]: {} } = setmetatable({}, { __mode = "k" }) :: any

local EnemyEffects = {}

-- Pushes `model` horizontally away from `from` at `speed` studs/s for `duration` seconds.
function EnemyEffects.knockBack(model: Model, from: Vector3, speed: number, duration: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root.Anchored then
		return
	end
	local away = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	if away.Magnitude < 0.01 then
		return
	end
	away = away.Unit

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(away.X, away.Z) * speed
	push.MaxForce = 1e5
	push.Parent = root
	Debris:AddItem(push, duration)
	Debris:AddItem(attachment, duration)
end

function EnemyEffects.isStunned(model: Model): boolean
	local stunnedUntil = model:GetAttribute("StunnedUntil")
	return typeof(stunnedUntil) == "number" and os.clock() < stunnedUntil
end

-- Stuns `model` for `duration` seconds (extending any current stun) and shows a
-- "STUNNED" label over its head until it wears off.
function EnemyEffects.stun(model: Model, duration: number)
	local stunnedUntil = os.clock() + duration
	local current = model:GetAttribute("StunnedUntil")
	if typeof(current) == "number" and current > stunnedUntil then
		stunnedUntil = current
	end
	model:SetAttribute("StunnedUntil", stunnedUntil)

	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild(STUN_LABEL_NAME)
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = STUN_LABEL_NAME
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 220, 80)
	label.TextStrokeTransparency = 0.3
	label.Text = "STUNNED"
	label.Parent = gui

	Debris:AddItem(gui, stunnedUntil - os.clock())
end

-- Jolts `model` back from a hit (a quick flinch animation). Skipped while it's winding up an
-- attack (its "Attacking" attribute), so a flinch never looks like it cancelled a hit that
-- still lands. Models without an Animator (e.g. training dummies) don't flinch.
function EnemyEffects.flinch(model: Model)
	if not flinchAnimation or model:GetAttribute("Attacking") == true then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local track = flinchTracks[animator]
	if not track then
		track = animator:LoadAnimation(flinchAnimation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		flinchTracks[animator] = track
	end
	track:Play(0.05)
end

-- Makes `model` bleed: `damage` every `interval` seconds for `duration` seconds, credited to
-- `source` (who sees red damage numbers). A new bleed replaces the current one (restarting
-- the timer) rather than stacking. Red drips fall from the model while it bleeds.
function EnemyEffects.bleed(model: Model, source: Player?, damage: number, interval: number, duration: number)
	local token = {}
	bleeds[model] = token
	local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")

	local drips = root and root:FindFirstChild(BLEED_DRIPS_NAME)
	if root and not drips then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = BLEED_DRIPS_NAME
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 20, 30))
		emitter.Size = NumberSequence.new(0.25, 0.1)
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.Lifetime = NumberRange.new(0.4, 0.7)
		emitter.Rate = 14
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Acceleration = Vector3.new(0, -25, 0)
		emitter.Parent = root
		drips = emitter
	end

	task.spawn(function()
		local ends = os.clock() + duration
		while bleeds[model] == token and os.clock() < ends do
			task.wait(interval)
			if bleeds[model] ~= token or not model.Parent or not HealthService.isAlive(model) then
				break
			end
			local dealt = HealthService.damage(model, damage, source)
			if dealt > 0 and source then
				local cframe, size = model:GetBoundingBox()
				damageRemote:FireClient(source, cframe.Position + Vector3.new(0, size.Y / 2, 0), dealt, "Bleed")
			end
		end
		if bleeds[model] == token then
			bleeds[model] = nil
			if drips then
				drips:Destroy()
			end
		end
	end)
end

return EnemyEffects
