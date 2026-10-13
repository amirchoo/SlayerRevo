--!strict
-- Projectiles (the bow's arrows, the crossbow's bolts, the blunderbuss's pellets), simulated
-- on the server. Each one is stepped every frame with a raycast along the step, so fast shots
-- can't skip through things; it drops under its weapon's Gravity, deals damage to whatever
-- damageable thing it hits first (unless it's flown past its damage range), and stays stuck
-- there for a while. They fly through every player (no friendly fire). They all live in
-- workspace.Arrows (which client aiming ignores).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local EnemyEffects = require(script.Parent.EnemyEffects)

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

-- What a projectile needs from its weapon's config (see CombatConfig.Bow / Crossbow / Blunderbuss).
export type Config = {
	ToolName: string, -- picks the hit effect and sound
	Gravity: number,
	MaxRange: number,
	StuckLifetime: number,
	TrailLifetime: number,
}

-- How a projectile looks: a shaft `size` long along Z (or a ball), with a glowing streak
-- behind it.
export type Look = {
	Name: string,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material?, -- Wood if nil
	Shape: Enum.PartType?, -- a Block if nil
	TrailColor: ColorSequence,
}

local Projectile = {}

local folder = Instance.new("Folder")
folder.Name = "Arrows"
folder.Parent = workspace

local templates: { [string]: Part } = {}

local function template(look: Look, config: Config): Part
	local key = `{look.Name}:{config.ToolName}`
	local existing = templates[key]
	if existing then
		return existing
	end
	local shaft = Instance.new("Part")
	shaft.Name = look.Name
	shaft.Size = look.Size
	shaft.Color = look.Color
	shaft.Material = look.Material or Enum.Material.Wood
	shaft.Shape = look.Shape or Enum.PartType.Block
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.Massless = true

	-- A glowing streak behind it in flight: a thin ribbon from the tail (it points along -Z,
	-- so the tail is at +Z) that fades and narrows as it trails off.
	local tail = math.max(look.Size.Z / 2 - 0.2, 0)
	local halfWidth = math.min(0.12, look.Size.Y / 2)
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, halfWidth, tail)
	top.Parent = shaft
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -halfWidth, tail)
	bottom.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Name = "ProjectileTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.Lifetime = config.TrailLifetime
	trail.LightEmission = 1
	trail.Color = look.TrailColor
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.MinLength = 0.05
	trail.Parent = shaft

	templates[key] = shaft
	return shaft
end

local function raycastParams(): RaycastParams
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

-- `damage` 0: it's flown past its damage range, so it only sticks.
local function onHit(player: Player, shaft: Part, result: RaycastResult, direction: Vector3, damage: number, config: Config)
	-- Stop the streak (what's already drawn fades out), and leave it stuck in what it hit,
	-- tip slightly buried.
	local trail = shaft:FindFirstChild("ProjectileTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = false
	end
	shaft.CFrame = CFrame.lookAt(result.Position - direction * math.max(shaft.Size.Z / 2 - 0.4, 0), result.Position + direction)

	local model = HealthService.findDamageable(result.Instance)
	if model then
		local dealt = if damage > 0 then HealthService.damage(model, damage, player) else 0
		if dealt > 0 then
			damageRemote:FireClient(player, result.Position, dealt, nil, model)
			if HealthService.isAlive(model) then
				EnemyEffects.flinch(model)
			end
			HitEffects.broadcast(model, result.Position, direction, config.ToolName, dealt)
		end
		-- Weld it on so it moves with the target.
		shaft.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shaft
		weld.Part1 = result.Instance :: BasePart
		weld.Parent = shaft
	end
	Debris:AddItem(shaft, config.StuckLifetime)
end

-- Fires one from `origin` along `direction` (a unit vector) at `speed` studs per second.
-- Past `damageRange` studs (if given) it does no damage.
function Projectile.fire(player: Player, config: Config, look: Look, origin: Vector3, direction: Vector3, speed: number, damage: number, damageRange: number?)
	local shaft = template(look, config):Clone()
	shaft.CFrame = CFrame.lookAt(origin, origin + direction)
	shaft.Parent = folder

	local params = raycastParams()
	local gravity = Vector3.new(0, -config.Gravity, 0)
	local position, velocity, traveled = origin, direction * speed, 0

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local nextVelocity = velocity + gravity * dt
		local step = (velocity + nextVelocity) / 2 * dt

		local result = workspace:Raycast(position, step, params)
		if result then
			connection:Disconnect()
			local inRange = not damageRange or traveled + result.Distance <= damageRange
			onHit(player, shaft, result, step.Unit, if inRange then damage else 0, config)
			return
		end

		position += step
		velocity = nextVelocity
		traveled += step.Magnitude
		shaft.CFrame = CFrame.lookAt(position, position + velocity)
		if traveled >= config.MaxRange then
			connection:Disconnect()
			shaft:Destroy()
		end
	end)
end

return Projectile
