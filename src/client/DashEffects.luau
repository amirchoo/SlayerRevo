--!strict
-- What a dash looks and sounds like: a puff of dust at the feet, a whoosh, and a pale neon
-- afterimage of the character left behind that fades out, so a dodge (and its i-frames)
-- reads clearly. Your own dash plays here as soon as you press it (see Dash); other
-- players' dashes arrive from the server (DashEffect, see DashService).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local DUST_COLOR = Color3.fromRGB(170, 160, 145)
local DUST_COUNT = 10
local GHOST_COLOR = Color3.fromRGB(150, 210, 255)
local GHOST_START_TRANSPARENCY = 0.5
local GHOST_FADE_TIME = 0.35

local dashEffectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DashEffect") :: RemoteEvent

local DashEffects = {}

local function dust(root: BasePart, humanoid: Humanoid)
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = feet -- particles emit along +Y: up and outward
	Debris:AddItem(attachment, 2)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = DUST_TEXTURE
	emitter.Color = ColorSequence.new(DUST_COLOR)
	emitter.Size = NumberSequence.new(0.8, 2.4)
	emitter.Transparency = NumberSequence.new(0.45, 1)
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(80, 80)
	emitter.Acceleration = Vector3.new(0, -4, 0)
	emitter.Drag = 5
	emitter.Parent = attachment
	emitter:Emit(DUST_COUNT)
end

-- A see-through neon copy of every visible part of `character`, left where it stands.
local function afterimage(character: Model)
	local ghost = Instance.new("Model")
	ghost.Name = "DashAfterimage"
	local parts: { BasePart } = {}
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("BasePart") or descendant.Transparency >= 1 or descendant.Name == "HumanoidRootPart" then
			continue
		end
		local copy = descendant:Clone()
		-- Keep only the shape: drop joints, scripts, decals, textures, effects and sounds.
		for _, child in copy:GetChildren() do
			if child:IsA("SpecialMesh") then
				child.TextureId = ""
			elseif not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		if copy:IsA("MeshPart") then
			copy.TextureID = ""
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Material = Enum.Material.Neon
		copy.Color = GHOST_COLOR
		copy.Transparency = GHOST_START_TRANSPARENCY
		copy.CFrame = descendant.CFrame
		copy.Parent = ghost
		table.insert(parts, copy)
	end
	ghost.Parent = workspace.CurrentCamera -- local to this client
	local fade = TweenInfo.new(GHOST_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in parts do
		TweenService:Create(part, fade, { Transparency = 1 }):Play()
	end
	Debris:AddItem(ghost, GHOST_FADE_TIME)
end

-- Shows `character` dashing: dust, whoosh, and afterimage.
function DashEffects.play(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	dust(root, humanoid)
	Sounds.play("DashWhoosh", root)
	afterimage(character)
end

function DashEffects.start()
	dashEffectRemote.OnClientEvent:Connect(function(character: Model?)
		if typeof(character) == "Instance" and character:IsA("Model") and character ~= Players.LocalPlayer.Character then
			DashEffects.play(character)
		end
	end)
end

return DashEffects
