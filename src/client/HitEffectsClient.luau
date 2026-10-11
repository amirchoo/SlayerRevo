--!strict
-- Draws hit effects when the server reports a hit (see server HitEffects): a white flash
-- on whatever was hit, the weapon's impact visual, and its impact sound. Each weapon has a
-- style: "Slash" (bright streak across the target + sparks), "Blunt" (expanding shockwave
-- ring + dust), or "Pierce" (thin streak along the blow + a narrow cone of sparks).
-- Ground smashes (GroundShockwave) draw an expanding ring of dust along the ground and
-- shake the camera of anyone close enough to feel it.
-- Everything is built from plain parts and Roblox's bundled particle textures.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local FLASH_TIME = 0.12
local REFERENCE_DAMAGE = 25 -- a hit this big draws the effect at its base size
local SHOCKWAVE_TIME = 0.4
local SHOCKWAVE_SHAKE = 0.5 -- studs of camera shake at the impact (less further away)
local SHOCKWAVE_SHAKE_TIME = 0.3

type Style = "Slash" | "Blunt" | "Pierce"
type Look = { style: Style, color: Color3, size: number }

-- Per weapon (by ToolName). size scales the whole effect; the sound is "<ToolName>Hit".
local LOOKS: { [string]: Look } = {
	Sword = { style = "Slash", color = Color3.fromRGB(255, 240, 190), size = 1 },
	Greatsword = { style = "Slash", color = Color3.fromRGB(255, 200, 120), size = 1.6 },
	Mace = { style = "Blunt", color = Color3.fromRGB(255, 215, 150), size = 1.1 },
	Spear = { style = "Pierce", color = Color3.fromRGB(200, 230, 255), size = 1 },
	Axe = { style = "Slash", color = Color3.fromRGB(255, 190, 150), size = 1.15 },
	Bow = { style = "Pierce", color = Color3.fromRGB(230, 220, 200), size = 0.7 },
	DemonClaw = { style = "Slash", color = Color3.fromRGB(255, 70, 60), size = 0.9 }, -- enemies hitting players
	Parry = { style = "Blunt", color = Color3.fromRGB(255, 235, 150), size = 1.3 }, -- a parried enemy (see BlockService)
}
local DEFAULT_LOOK: Look = { style = "Slash", color = Color3.new(1, 1, 1), size = 1 }

local hitEffectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HitEffect") :: RemoteEvent
local shockwaveRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GroundShockwave") :: RemoteEvent

local HitEffectsClient = {}

local random = Random.new()

local function effectPart(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	if shape then
		part.Shape = shape
	end
	part.Parent = workspace.CurrentCamera -- local to this client
	return part
end

local function fadeAndGrow(part: BasePart, time: number, goalSize: Vector3, goalCFrame: CFrame?)
	local goal: { [string]: any } = { Transparency = 1, Size = goalSize }
	if goalCFrame then
		goal.CFrame = goalCFrame
	end
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, time)
end

-- An attachment at `position` whose +Y points along `direction` (particles emit along +Y).
local function emitterAt(position: Vector3, direction: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldCFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	Debris:AddItem(attachment, 2)
	return attachment
end

local function burst(attachment: Attachment, props: { [string]: any }, count: number)
	local emitter = Instance.new("ParticleEmitter") :: any
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LockedToPart = false
	for key, value in props do
		emitter[key] = value
	end
	emitter.Parent = attachment
	emitter:Emit(count)
end

local function sparks(position: Vector3, direction: Vector3, color: Color3, scale: number, spread: number, count: number)
	burst(emitterAt(position, direction), {
		Texture = SPARK_TEXTURE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(0.35 * scale, 0),
		Transparency = NumberSequence.new(0, 1),
		Lifetime = NumberRange.new(0.15, 0.35),
		Speed = NumberRange.new(14 * scale, 26 * scale),
		SpreadAngle = Vector2.new(spread, spread),
		Drag = 6,
	}, count)
end

local function slash(position: Vector3, direction: Vector3, look: Look, scale: number)
	-- A bright streak across the blow, at a random angle around it.
	local length = 5 * scale
	local across = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, 0, random:NextNumber(0, math.pi)) * CFrame.Angles(0, math.pi / 2, 0)
	local streak = effectPart(Vector3.new(0.12 * scale, 0.12 * scale, length), across, look.color)
	fadeAndGrow(streak, 0.16, Vector3.new(0.02, 0.02, length * 1.3))
	sparks(position, -direction, look.color, scale, 70, math.round(10 * scale))
end

local function blunt(position: Vector3, direction: Vector3, look: Look, scale: number)
	-- A shockwave ring facing the blow, bursting outward.
	local facing = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.pi / 2, 0)
	local ring = effectPart(Vector3.new(0.15, 1.2 * scale, 1.2 * scale), facing, look.color, Enum.PartType.Cylinder)
	ring.Transparency = 0.3
	fadeAndGrow(ring, 0.25, Vector3.new(0.05, 6 * scale, 6 * scale))

	burst(emitterAt(position, -direction), {
		Texture = DUST_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(160, 150, 135)),
		Size = NumberSequence.new(0.8 * scale, 2.6 * scale),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(80, 80),
		Drag = 4,
	}, math.round(7 * scale))
	sparks(position, -direction, look.color, scale * 0.8, 90, math.round(5 * scale))
end

local function pierce(position: Vector3, direction: Vector3, look: Look, scale: number)
	-- A thin streak along the blow that shoots through the target.
	local length = 3 * scale
	local along = CFrame.lookAt(position, position + direction)
	local streak = effectPart(Vector3.new(0.08 * scale, 0.08 * scale, length), along, look.color)
	fadeAndGrow(streak, 0.14, Vector3.new(0.02, 0.02, length * 0.5), along * CFrame.new(0, 0, -length))
	sparks(position, direction, look.color, scale, 22, math.round(8 * scale))
end

local function flash(model: Model)
	if not model.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FillTransparency = 1 }):Play()
	Debris:AddItem(highlight, FLASH_TIME)
end

local function onHit(model: Model?, position: Vector3, direction: Vector3, weapon: string, damage: number)
	local look = LOOKS[weapon] or DEFAULT_LOOK
	-- Bigger hits draw bigger effects, within limits.
	local scale = look.size * math.clamp(damage / REFERENCE_DAMAGE, 0.75, 2.2)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis

	if model then
		flash(model)
	end
	if look.style == "Blunt" then
		blunt(position, direction, look, scale)
	elseif look.style == "Pierce" then
		pierce(position, direction, look, scale)
	else
		slash(position, direction, look, scale)
	end

	-- Impact sound from the hit point (3D, so it's quieter further away).
	local soundSource = Instance.new("Attachment")
	soundSource.Parent = workspace.Terrain
	soundSource.WorldPosition = position
	Debris:AddItem(soundSource, 3)
	local soundName = `{weapon}Hit`
	local ok = pcall(Sounds.play, soundName, soundSource)
	if not ok then
		Sounds.play("SwordHit", soundSource) -- a weapon without its own hit sound yet
	end
end

local function shakeCamera(strength: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or strength <= 0.02 then
		return
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local remaining = 1 - (os.clock() - started) / SHOCKWAVE_SHAKE_TIME
		if remaining <= 0 or not humanoid.Parent then
			connection:Disconnect()
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local s = strength * remaining
		humanoid.CameraOffset = Vector3.new(random:NextNumber(-s, s), random:NextNumber(-s, s), 0)
	end)
end

local function onShockwave(position: Vector3, radius: number, weapon: string)
	local look = LOOKS[weapon] or DEFAULT_LOOK
	local flat = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)

	-- A bright disc and a fainter wide ring racing out to the edge of the reach.
	local core = effectPart(Vector3.new(0.2, 2, 2), flat, look.color, Enum.PartType.Cylinder)
	core.Transparency = 0.2
	fadeAndGrow(core, SHOCKWAVE_TIME * 0.6, Vector3.new(0.05, radius, radius))
	local ring = effectPart(Vector3.new(0.1, 2, 2), flat, look.color, Enum.PartType.Cylinder)
	ring.Transparency = 0.55
	fadeAndGrow(ring, SHOCKWAVE_TIME, Vector3.new(0.05, radius * 2, radius * 2))

	-- Dust kicked up around the impact and along the edge.
	burst(emitterAt(position, Vector3.yAxis), {
		Texture = DUST_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(160, 150, 135)),
		Size = NumberSequence.new(2, 5),
		Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(radius * 0.8, radius * 1.6),
		SpreadAngle = Vector2.new(85, 85),
		Drag = 5,
	}, math.round(radius * 1.5))
	sparks(position, Vector3.yAxis, look.color, 1.2, 60, 14)

	local soundSource = Instance.new("Attachment")
	soundSource.Parent = workspace.Terrain
	soundSource.WorldPosition = position
	Debris:AddItem(soundSource, 3)
	local ok = pcall(Sounds.play, `{weapon}Hit`, soundSource, 0.7)
	if not ok then
		Sounds.play("SwordHit", soundSource, 0.7)
	end

	-- Shake for anyone near it, fading out with distance.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local distance = (root.Position - position).Magnitude
		shakeCamera(SHOCKWAVE_SHAKE * (1 - math.clamp(distance / (radius * 2), 0, 1)))
	end
end

function HitEffectsClient.start()
	hitEffectRemote.OnClientEvent:Connect(onHit)
	shockwaveRemote.OnClientEvent:Connect(onShockwave)
end

return HitEffectsClient
