--!strict
-- Shared melee hit detection (sword, mace, spear, greatsword): a box in front of the attacker.
-- Hits each damageable model at most once, never other players (co-op, no friendly fire),
-- sends the attacker damage numbers for every hit that lands, and shows everyone the
-- weapon's hit effect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

local MeleeHitbox = {}

export type Hit = { model: Model, dealt: number }

-- `size` is (width, height, reach): the box starts at the attacker and extends `reach`
-- studs forward. `weapon` is the weapon's ToolName (for its hit effect). Returns every
-- model that took damage.
function MeleeHitbox.strike(player: Player, character: Model, root: BasePart, size: Vector3, damage: number, weapon: string): { Hit }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local boxCFrame = root.CFrame * CFrame.new(0, 0, -size.Z / 2)
	local alreadyHit: { [Model]: boolean } = {}
	local hits: { Hit } = {}

	for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, params) do
		local model = HealthService.findDamageable(part)
		if model and not alreadyHit[model] and not Players:GetPlayerFromCharacter(model) then
			alreadyHit[model] = true
			local dealt = HealthService.damage(model, damage, player, root.Position)
			if dealt > 0 then
				-- Damage numbers, shown just above the target.
				local modelCFrame, modelSize = model:GetBoundingBox()
				damageRemote:FireClient(player, modelCFrame.Position + Vector3.new(0, modelSize.Y / 2, 0), dealt)
				local impact, direction = HitEffects.meleeImpactPoint(model, root.Position)
				HitEffects.broadcast(model, impact, direction, weapon, dealt)
				table.insert(hits, { model = model, dealt = dealt })
			end
		end
	end
	return hits
end

return MeleeHitbox
