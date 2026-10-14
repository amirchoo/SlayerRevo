-- Studio Command Bar snippet: rebuilds Beginning Town in edit mode from the code
-- (src/server/TownBuilder.luau, from TownConfig), replacing the copy saved in the place. The
-- game plays with the saved copy (hand edits and all), so run this after changing the town's
-- code or config, then save the place. WARNING: it throws away any hand edits to
-- workspace.Town. Townsfolk aren't included: they only exist in play.
-- Studio caches required modules between runs, so this builds from fresh copies of
-- TownBuilder and ReplicatedStorage.Shared (swapped in for the build, then put back).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.Shared
local fresh = shared:Clone()
shared.Parent = nil
fresh.Parent = ReplicatedStorage
local ok, err = pcall(function()
	require(game:GetService("ServerScriptService").Server.TownBuilder:Clone()).build(true)
end)
fresh:Destroy()
shared.Parent = ReplicatedStorage
if ok then
	print("Beginning Town rebuilt in edit mode; save the place to keep it")
else
	warn("Town preview failed:", err)
end
