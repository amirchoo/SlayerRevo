--!strict
-- Weapon icons: a weapon's model shown in a ViewportFrame, turned so its length runs
-- diagonally up and right (held by its grip, like an item icon) and framed to fill it.
-- The models are the look-only copies the server publishes in ReplicatedStorage.WeaponPreviews
-- (see InventoryService), so stored weapons can be shown too. showModel frames any other
-- model the same way (the backpack's armor and shield tiles), and showItem the item models
-- (potions) in ReplicatedStorage.ItemModels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponIcon = {}

local previews = ReplicatedStorage:WaitForChild("WeaponPreviews")
WeaponIcon.Previews = previews

local BOX_CORNERS = {
	Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
	Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
}

-- A ViewportFrame filling `parent`, ready for show().
function WeaponIcon.viewport(parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 185, 200)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Parent = parent
	return viewport
end

-- Puts `model` in `viewport`, with a camera (looking along -Z) framing it to fill the view.
local function frame(viewport: ViewportFrame, model: Model)
	local min, max = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			for _, corner in BOX_CORNERS do
				local point = part.CFrame:PointToWorldSpace(part.Size / 2 * corner)
				min, max = min:Min(point), max:Max(point)
			end
		end
	end
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if min.X < math.huge then
		local center = (min + max) / 2
		local extent = math.max(max.X - min.X, max.Y - min.Y)
		local distance = extent / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.15 + (max.Z - min.Z) / 2
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, distance), center)
	end
end

-- Shows weapon `name` in `viewport` (clearing what was there); returns false if its look
-- hasn't arrived yet (Previews.ChildAdded fires when it does).
function WeaponIcon.show(viewport: ViewportFrame, name: string?): boolean
	viewport:ClearAllChildren()
	local source = name and previews:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		return false
	end
	local model = source:Clone()
	local grip = model:FindFirstChild("GripPart")
	if grip and grip:IsA("BasePart") then
		local relative = grip.CFrame:ToObjectSpace(model:GetPivot())
		-- Grip +Z (toward the tip) up and right; its flat side toward the camera.
		local diagonal = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.new(0.707, -0.707, 0))
		model:PivotTo(diagonal * relative)
	end
	frame(viewport, model)
	return true
end

-- Shows a copy of `source` in `viewport` (clearing what was there), turned by `turn` (the
-- camera sees the turned model's +Z side), framed to fill it.
function WeaponIcon.showModel(viewport: ViewportFrame, source: Model, turn: CFrame)
	viewport:ClearAllChildren()
	local model = source:Clone()
	model:PivotTo(turn * model:GetPivot())
	frame(viewport, model)
end

local ITEM_TURN = CFrame.Angles(math.rad(10), math.rad(25), 0) -- upright, a little turned and tipped forward
local GLASS_TRANSPARENCY = 0.6

-- Shows item model `name` (from ReplicatedStorage.ItemModels, e.g. a potion) in `viewport`,
-- standing upright with its glass see-through; returns false (leaving it empty) if there's no
-- such model, so the caller can show the item's icon instead.
function WeaponIcon.showItem(viewport: ViewportFrame, name: string?): boolean
	viewport:ClearAllChildren()
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	local source = if name and folder then folder:FindFirstChild(name) else nil
	if not source or not source:IsA("Model") then
		return false
	end
	local model = source:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.find(string.lower(part.Name), "glass") then
			part.Transparency = GLASS_TRANSPARENCY
		end
	end
	model:PivotTo(ITEM_TURN * model:GetPivot())
	frame(viewport, model)
	return true
end

return WeaponIcon
