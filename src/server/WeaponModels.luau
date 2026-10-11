--!strict
-- Swaps a weapon's placeholder look for a real model, when there is one.
-- Models live in ServerStorage.WeaponModels (assets/weapons), named after the weapon's
-- ToolName (e.g. "Sword"): a Model or a single MeshPart, straight from Studio's Import 3D.
-- The model is fitted automatically, so it can come in at any size or position. It should be
-- in this pose (tools/weapon_glb.py can turn a model into it):
--   * its length (handle to tip) along its own Y axis, handle at -Y (FlipBlade = true if
--     it's the other end); it's scaled so that length is Fit.Length
--   * its thinnest side along Z (the blade's thickness, so the edge leads the swing)
-- The hand holds it Fit.GripFrom of the way up from the handle end, moved by Fit.Shift.
-- Note: Studio's Import 3D turns GLB models 180 degrees around Y, so a model's X and Z sides
-- come in opposite to the file's (tools/weapon_glb.py --info shows the file's). Shift and
-- FlipEdge are in the imported model's terms.
-- Only the look changes: the grip, hitboxes, stats, and animations stay the same.

local ServerStorage = game:GetService("ServerStorage")

local HandGrip = require(game:GetService("ReplicatedStorage").Shared.HandGrip)

export type Fit = {
	Length: number, -- studs from the end of the handle to the tip
	GripFrom: number, -- where the hand holds it, as a fraction of Length from the handle end
	FlipBlade: boolean?, -- true if the model comes in with the handle at the positive end
	FlipEdge: boolean?, -- true to turn it 180 degrees around its handle (e.g. an axe edge facing backwards)
	-- Moves where the hand holds it off the model's center line, as fractions of Length along
	-- the model's X (front/back across the blade) and Z (thickness), e.g. onto a bow's grip.
	Shift: Vector3?,
}

local WeaponModels = {}

-- The model for `toolName`, as a Model (a lone MeshPart gets wrapped in one), or nil.
local function sourceModel(toolName: string): Model?
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local source = folder and folder:FindFirstChild(toolName)
	if not source then
		return nil
	end
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		source:Clone().Parent = model
	else
		warn(`WeaponModels: {toolName} should be a Model or a MeshPart, not a {source.ClassName}`)
		return nil
	end
	-- Measure along the biggest part's own axes (an imported mesh's axes are the model's).
	local biggest: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and (not biggest or descendant.Size.Magnitude > biggest.Size.Magnitude) then
			biggest = descendant
		end
	end
	if not biggest then
		warn(`WeaponModels: {toolName} has no parts`)
		return nil
	end
	model.PrimaryPart = biggest
	return model
end

-- The model's bounding box, measured along its own axes (its biggest part's).
local function bounds(model: Model): (CFrame, Vector3)
	return model:GetBoundingBox()
end

-- Replaces `tool`'s placeholder parts with its model, if one exists. The grip part stays
-- (now invisible) and keeps the swing sound; the trail is rebuilt along the new blade.
-- Returns true if a model was applied.
function WeaponModels.apply(tool: Tool, fit: Fit?): boolean
	local model = sourceModel(tool.Name)
	local grip = tool:FindFirstChild(HandGrip.GRIP_NAME)
	if not model or not fit or not grip or not grip:IsA("BasePart") then
		return false
	end

	-- Scale so its length (along Y) is the weapon's length.
	local _, before = bounds(model)
	if before.Y < math.max(before.X, before.Z) then
		warn(`WeaponModels: {tool.Name}'s longest side isn't its Y axis; it may be held sideways (see tools/weapon_glb.py)`)
	end
	model:ScaleTo(model:GetScale() * fit.Length / before.Y)
	local center, size = bounds(model)
	local length = size.Y
	local flip = if fit.FlipBlade then -1 else 1
	local along = center.YVector * flip -- handle -> tip
	local thin = center.ZVector * flip * (if fit.FlipEdge then -1 else 1)

	-- Line the hand's grip point up with the grip part: blade along its +Z, flat side along X.
	local handleEnd = center.Position - along * length / 2
	local shift = fit.Shift or Vector3.zero
	local gripPoint = handleEnd + along * length * fit.GripFrom + (center.XVector * shift.X + thin * shift.Z) * length
	local frame = CFrame.fromMatrix(gripPoint, thin, along:Cross(thin))
	model:PivotTo(grip.CFrame * frame:ToObjectSpace(model:GetPivot()))

	-- Remove the placeholder (every part but the grip; its trail goes with the blade).
	local oldTrail = tool:FindFirstChild("SwingTrail", true)
	local trailLifetime = if oldTrail and oldTrail:IsA("Trail") then oldTrail.Lifetime else 0.15
	local trailColor = if oldTrail and oldTrail:IsA("Trail") then oldTrail.Color else nil
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= grip then
			child:Destroy()
		end
	end
	grip.Transparency = 1

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = grip
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	model.Name = "Model"
	model.Parent = tool

	-- Swing trail from a little above the hand to the tip.
	local tipZ = length * (1 - fit.GripFrom)
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0, tipZ * 0.3)
	base.Parent = grip
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = Vector3.new(0, 0, tipZ)
	tip.Parent = grip
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = trailLifetime
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	if trailColor then
		trail.Color = trailColor -- e.g. Emberfang's ember
	end
	trail.Parent = grip
	return true
end

return WeaponModels
