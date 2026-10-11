--!strict
-- Hit effects on enemies: knockback and stun. Enemies are simulated by the server, so
-- these happen here (players' own characters are pushed by their clients instead).
-- A stunned enemy has a "StunnedUntil" attribute (server os.clock() time); EnemyService
-- checks it to freeze the enemy and cancel its wind-up attacks.

local Debris = game:GetService("Debris")

local STUN_LABEL_NAME = "StunLabel"

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

return EnemyEffects
