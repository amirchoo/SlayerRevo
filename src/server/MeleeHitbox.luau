--!strict
-- Shared melee hit detection (sword, mace, spear, greatsword): a box in front of the
-- attacker, a wide arc for sweeps, a radius all around them for spin attacks, or a radius
-- around any point (blasts that burst where they land).
-- Hits each damageable model at most once, never other players (co-op, no friendly fire),
-- sends the attacker damage numbers for every hit that lands, and shows everyone the
-- weapon's hit effect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local EnemyEffects = require(script.Parent.EnemyEffects)

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

local MeleeHitbox = {}

export type Hit = { model: Model, dealt: number }

-- Damages each model found among `parts` once (skipping the attacker's own character
-- and other players), with damage numbers and hit effects. Returns every model that took damage.
local function damageParts(player: Player, origin: Vector3, parts: { BasePart }, damage: number, weapon: string): { Hit }
	local alreadyHit: { [Model]: boolean } = {}
	local hits: { Hit } = {}
	for _, part in parts do
		local model = HealthService.findDamageable(part)
		if model and not alreadyHit[model] and not Players:GetPlayerFromCharacter(model) then
			alreadyHit[model] = true
			local dealt = HealthService.damage(model, damage, player, origin)
			if dealt > 0 then
				-- Damage numbers, shown just above the target.
				local modelCFrame, modelSize = model:GetBoundingBox()
				damageRemote:FireClient(player, modelCFrame.Position + Vector3.new(0, modelSize.Y / 2, 0), dealt, nil, model)
				local impact, direction = HitEffects.meleeImpactPoint(model, origin)
				HitEffects.broadcast(model, impact, direction, weapon, dealt)
				if HealthService.isAlive(model) then
					EnemyEffects.flinch(model)
				end
				table.insert(hits, { model = model, dealt = dealt })
			end
		end
	end
	return hits
end

local function excludeAttacker(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

-- `size` is (width, height, reach): the box starts at the attacker and extends `reach`
-- studs forward. `weapon` is the weapon's ToolName (for its hit effect). Returns every
-- model that took damage.
function MeleeHitbox.strike(player: Player, character: Model, root: BasePart, size: Vector3, damage: number, weapon: string): { Hit }
	return MeleeHitbox.strikeFrom(player, character, root, root.CFrame, size, damage, weapon)
end

-- Like strike, but the box starts at `origin` (e.g. where a lunge began) instead of the
-- attacker's current position.
function MeleeHitbox.strikeFrom(player: Player, character: Model, root: BasePart, origin: CFrame, size: Vector3, damage: number, weapon: string): { Hit }
	local boxCFrame = origin * CFrame.new(0, 0, -size.Z / 2)
	local parts = workspace:GetPartBoundsInBox(boxCFrame, size, excludeAttacker(character))
	return damageParts(player, root.Position, parts, damage, weapon)
end

-- Hits everything within `radius` studs of the attacker, in every direction (spin attacks).
function MeleeHitbox.strikeAround(player: Player, character: Model, root: BasePart, radius: number, damage: number, weapon: string): { Hit }
	local parts = workspace:GetPartBoundsInRadius(root.Position, radius, excludeAttacker(character))
	return damageParts(player, root.Position, parts, damage, weapon)
end

-- Hits everything within `radius` studs that lies inside an `arc` (degrees, centred on where
-- the attacker faces) — wide sweeps. An arc of 360 or more is the same as strikeAround.
function MeleeHitbox.strikeArc(player: Player, character: Model, root: BasePart, radius: number, arc: number, damage: number, weapon: string): { Hit }
	local parts = workspace:GetPartBoundsInRadius(root.Position, radius, excludeAttacker(character))
	if arc < 360 then
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local minDot = math.cos(math.rad(arc / 2))
		local inArc: { BasePart } = {}
		for _, part in parts do
			local offset = part.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			-- Anything right on top of the attacker counts whichever way it is.
			if flat.Magnitude < 2 or facing:Dot(flat.Unit) >= minDot then
				table.insert(inArc, part)
			end
		end
		parts = inArc
	end
	return damageParts(player, root.Position, parts, damage, weapon)
end

-- Hits everything within `radius` studs of `center` (e.g. where a blast landed), except the
-- attacker. Hit effects point away from `center`.
function MeleeHitbox.strikeAt(player: Player, character: Model, center: Vector3, radius: number, damage: number, weapon: string): { Hit }
	local parts = workspace:GetPartBoundsInRadius(center, radius, excludeAttacker(character))
	return damageParts(player, center, parts, damage, weapon)
end

return MeleeHitbox
