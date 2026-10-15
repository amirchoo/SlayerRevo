--!strict
-- Hit effects on enemies: knockback, pull, stun, bleed and burn, slow, and the flinch when hit. Enemies are simulated by the server,
-- so these happen here (players' own characters are pushed by their clients instead).
-- A stunned enemy has a "StunnedUntil" attribute (server os.clock() time); EnemyService
-- checks it to freeze the enemy and cancel its wind-up attacks.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)

local STUN_LABEL_NAME = "StunLabel"

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

local function makeAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animation
end

local flinchAnimation = makeAnimation(EnemyConfig.FlinchAnimation)
local flinchTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any
local parriedAnimation = makeAnimation(EnemyConfig.ParriedAnimation)
local parriedTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any


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

-- Drags `model` horizontally to `to` over `duration` seconds (the scythe's hook). Nothing
-- happens if it's already there.
function EnemyEffects.pull(model: Model, to: Vector3, duration: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root.Anchored or duration <= 0 then
		return
	end
	local toward = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
	if toward.Magnitude < 0.5 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local drag = Instance.new("LinearVelocity")
	drag.Attachment0 = attachment
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drag.PrimaryTangentAxis = Vector3.xAxis
	drag.SecondaryTangentAxis = Vector3.zAxis
	drag.PlaneVelocity = Vector2.new(toward.X, toward.Z) / duration
	drag.MaxForce = 1e5
	drag.Parent = root
	Debris:AddItem(drag, duration)
	Debris:AddItem(attachment, duration)
end

function EnemyEffects.isStunned(model: Model): boolean
	local stunnedUntil = model:GetAttribute("StunnedUntil")
	return typeof(stunnedUntil) == "number" and os.clock() < stunnedUntil
end

-- Stuns `model` for `duration` seconds (extending any current stun) and shows a
-- "STUNNED" label over its head until it wears off (unless `silent`, e.g. while it's held
-- by a hook: the hold isn't a stun the player earned).
function EnemyEffects.stun(model: Model, duration: number, silent: boolean?)
	local stunnedUntil = os.clock() + duration
	local current = model:GetAttribute("StunnedUntil")
	if typeof(current) == "number" and current > stunnedUntil then
		stunnedUntil = current
	end
	model:SetAttribute("StunnedUntil", stunnedUntil)
	if silent then
		return
	end

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

-- Throws `model` into its parried recoil (weapon arm knocked wide, head snapped back) and
-- holds it there for `duration` seconds (the parry's stun), then lets it recover. It plays
-- over a flinch, so hits landed in the punish window don't break the open pose.
function EnemyEffects.recoil(model: Model, duration: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not parriedAnimation or not animator then
		return
	end
	local track = parriedTracks[animator]
	if not track then
		track = animator:LoadAnimation(parriedAnimation)
		track.Priority = Enum.AnimationPriority.Action2
		track.Looped = false
		parriedTracks[animator] = track
	end
	local playing = track
	playing:Play(0.03)
	-- Stretched to end just after the stun, so it's still holding when it's let go.
	if playing.Length > 0 then
		playing:AdjustSpeed(playing.Length / (duration + 0.05))
	end
	task.delay(duration, function()
		playing:Stop(0.15)
	end)
end

-- Damage over time, by kind (each kind runs separately, so a bleed and a burn can tick
-- together): its particles and the colour its damage numbers show in.
type DotKind = { particles: string, color: Color3, texture: string, rise: boolean }
local DOT_KINDS: { [string]: DotKind } = {
	Bleed = { particles = "BleedDrips", color = Color3.fromRGB(200, 20, 30), texture = "rbxasset://textures/particles/sparkles_main.dds", rise = false },
	Burn = { particles = "BurnFlames", color = Color3.fromRGB(255, 130, 40), texture = "rbxasset://textures/particles/fire_main.dds", rise = true },
}
local dots: { [string]: { [Model]: {} } } = {}

-- Damages `model` by `damage` every `interval` seconds for `duration` seconds, credited to
-- `source` (who sees the damage numbers, tagged `kind`). A new one of the same kind replaces
-- the current one (restarting the timer) rather than stacking.
local function damageOverTime(kind: string, model: Model, source: Player?, damage: number, interval: number, duration: number)
	local style = DOT_KINDS[kind]
	local running = dots[kind]
	if not running then
		running = setmetatable({}, { __mode = "k" }) :: any
		dots[kind] = running
	end
	local token = {}
	running[model] = token
	local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

	local particles = root and root:FindFirstChild(style.particles)
	if root and not particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = style.particles
		emitter.Texture = style.texture
		emitter.Color = ColorSequence.new(style.color)
		emitter.LightEmission = if style.rise then 0.8 else 0
		emitter.Size = if style.rise then NumberSequence.new(0.9, 0.2) else NumberSequence.new(0.25, 0.1)
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.Lifetime = NumberRange.new(0.4, 0.7)
		emitter.Rate = if style.rise then 20 else 14
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Acceleration = if style.rise then Vector3.new(0, 6, 0) else Vector3.new(0, -25, 0)
		emitter.Parent = root
		particles = emitter
	end

	task.spawn(function()
		local ends = os.clock() + duration
		while running[model] == token and os.clock() < ends do
			task.wait(interval)
			if running[model] ~= token or not model.Parent or not HealthService.isAlive(model) then
				break
			end
			local dealt = HealthService.damage(model, damage, source)
			if dealt > 0 and source then
				local cframe, size = model:GetBoundingBox()
				damageRemote:FireClient(source, cframe.Position + Vector3.new(0, size.Y / 2, 0), dealt, kind)
			end
		end
		if running[model] == token then
			running[model] = nil
			if particles then
				particles:Destroy()
			end
		end
	end)
end

-- Makes `model` bleed (the axe): `damage` every `interval` seconds for `duration` seconds,
-- credited to `source`. Red drips fall from it while it bleeds.
function EnemyEffects.bleed(model: Model, source: Player?, damage: number, interval: number, duration: number)
	damageOverTime("Bleed", model, source, damage, interval, duration)
end

-- Sets `model` on fire (the staff's Fire): like bleed, with flames.
function EnemyEffects.burn(model: Model, source: Player?, damage: number, interval: number, duration: number)
	damageOverTime("Burn", model, source, damage, interval, duration)
end

-- Slows `model` to `factor` of its speed for `duration` seconds (the staff's Water). The
-- strongest current slow wins. EnemyService reads it through speedFactor.
function EnemyEffects.slow(model: Model, factor: number, duration: number)
	local now = os.clock()
	local untilTime = model:GetAttribute("SlowUntil")
	local current = model:GetAttribute("SlowFactor")
	if typeof(untilTime) == "number" and untilTime > now and typeof(current) == "number" and current < factor then
		return -- already slowed harder
	end
	model:SetAttribute("SlowFactor", factor)
	model:SetAttribute("SlowUntil", now + duration)
end

-- The speed multiplier from any current slow (1 if none).
function EnemyEffects.speedFactor(model: Model): number
	local untilTime = model:GetAttribute("SlowUntil")
	local factor = model:GetAttribute("SlowFactor")
	if typeof(untilTime) == "number" and os.clock() < untilTime and typeof(factor) == "number" then
		return factor
	end
	return 1
end

return EnemyEffects
