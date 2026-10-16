--!strict
-- Draws fewer of the world's small walk-through plants on lower quality tiers (QualityConfig
-- Decor): grass tufts, small flowers and bushes. Looks only: none of them collide, so taking
-- some out on this screen changes nothing for movement or the server. Which ones go is fixed by
-- where they stand, so the same plants are missing every time, and raising the tier puts them back.
-- Each plant model streams in whole (Atomic), as a child of workspace.World.

local Quality = require(script.Parent.Quality)

local THINNED = { TallGrass = true, Wildflower = true, HogWeed = true, Bush = true }

local WorldDensity = {}

local keep = 1
local shown: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- plant → its fixed 0..1 roll
local hidden: { [Model]: number } = {} -- taken out on this screen, kept to put back
local world: Instance? = nil

-- A fixed 0..1 roll from where the plant stands.
local function roll(model: Model): number
	local position = model:GetPivot().Position
	local value = math.sin(position.X * 12.9898 + position.Z * 78.233) * 43758.5453
	return value - math.floor(value)
end

local function consider(child: Instance)
	if not child:IsA("Model") or not THINNED[child.Name] then
		return
	end
	local value = roll(child)
	-- Streaming takes a far plant away (even a hidden one); forget it then.
	child.Destroying:Once(function()
		hidden[child] = nil
	end)
	if value >= keep then
		hidden[child] = value
		child.Parent = nil
	else
		shown[child] = value
	end
end

local function apply(newKeep: number)
	keep = newKeep
	for model, value in shown do
		if value >= keep and model.Parent then
			shown[model] = nil
			hidden[model] = value
			model.Parent = nil
		end
	end
	for model, value in hidden do
		if value < keep then
			hidden[model] = nil
			shown[model] = value
			model.Parent = world
		end
	end
end

function WorldDensity.start()
	task.spawn(function()
		local folder = workspace:WaitForChild("World")
		world = folder
		folder.ChildAdded:Connect(consider) -- streamed in
		for _, child in folder:GetChildren() do
			consider(child)
		end
		Quality.onChange(function(settings)
			apply(settings.Decor)
		end)
	end)
end

return WorldDensity
