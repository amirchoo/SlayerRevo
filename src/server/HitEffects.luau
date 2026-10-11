--!strict
-- Tells every client to show a hit effect: the weapon's impact visual and sound at the hit
-- point, plus a white flash on whatever was hit (see client HitEffectsClient). Visual only;
-- the damage itself has already been decided by the caller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local hitEffectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HitEffect") :: RemoteEvent

local HitEffects = {}

-- `weapon`: the weapon's ToolName (picks the effect style and sound).
-- `direction`: which way the blow was travelling. `damage` scales the effect's size.
function HitEffects.broadcast(model: Model, position: Vector3, direction: Vector3, weapon: string, damage: number)
	hitEffectRemote:FireAllClients(model, position, direction, weapon, damage)
end

-- Where a melee blow from `attackerPosition` visibly lands on `model`: on its surface
-- facing the attacker, around chest height.
function HitEffects.meleeImpactPoint(model: Model, attackerPosition: Vector3): (Vector3, Vector3)
	local center, size = model:GetBoundingBox()
	local toTarget = Vector3.new(center.Position.X - attackerPosition.X, 0, center.Position.Z - attackerPosition.Z)
	local direction = if toTarget.Magnitude > 0.01 then toTarget.Unit else Vector3.zAxis
	local surface = math.min(size.X, size.Z) / 2
	return center.Position - direction * surface + Vector3.new(0, size.Y * 0.1, 0), direction
end

return HitEffects
