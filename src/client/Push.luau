--!strict
-- Pushes the local player's character horizontally for a moment (dash, block knockback,
-- spear lunge). Each client simulates its own character's movement, so pushes on it are
-- applied here and replicate like normal movement. Horizontal only: gravity and jumping
-- are unaffected.

local Debris = game:GetService("Debris")

local Push = {}

-- Moves `root` along `direction` (flattened) at `speed` studs/s for `duration` seconds.
function Push.apply(root: BasePart, direction: Vector3, speed: number, duration: number)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit

	local attachment = Instance.new("Attachment")
	attachment.Name = "PushAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Push"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(flat.X, flat.Z) * speed
	velocity.MaxForce = 1e5
	velocity.Parent = root

	Debris:AddItem(velocity, duration)
	Debris:AddItem(attachment, duration)
end

return Push
