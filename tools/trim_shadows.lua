-- Studio Command Bar snippet (edit mode): trims the world's shadow casters for ShadowMap
-- (perf pass step 5). Every tree keeps shadows on its trunk and its KEEP_LEAVES largest leaf
-- parts (the canopy's shadow on the ground); its other leaves stop casting. Small walk-through
-- plants and the flat path stones stop casting (their shadows are lost in the grass anyway).
-- Safe to run again (e.g. after new trees are placed). Save the place to keep it.
local KEEP_LEAVES = 6
local NO_SHADOW_MODELS = { TallGrass = true, Bush = true, Wildflower = true, HogWeed = true, StonePath = true }

local trees, leavesOff, leavesKept, plantsOff = 0, 0, 0, 0
local seen = 0
for _, model in workspace:GetDescendants() do
	if model:IsA("Model") and model.Name == "Tree" then
		trees += 1
		local leaves = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Leaves" then
				table.insert(leaves, part)
			end
		end
		table.sort(leaves, function(a, b)
			return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
		end)
		for i, part in leaves do
			part.CastShadow = i <= KEEP_LEAVES
			if i <= KEEP_LEAVES then
				leavesKept += 1
			else
				leavesOff += 1
			end
		end
	elseif model:IsA("Model") and NO_SHADOW_MODELS[model.Name] then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.CastShadow then
				part.CastShadow = false
				plantsOff += 1
			end
		end
	end
	seen += 1
	if seen % 5000 == 0 then
		task.wait()
	end
end
print(`Shadows trimmed: {trees} trees ({leavesKept} leaves kept, {leavesOff} off), {plantsOff} plant/path parts off`)
