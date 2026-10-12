-- Studio Command Bar snippet: builds Beginning Town into the place in edit mode, exactly as
-- the game builds it in play (src/server/TownBuilder.luau from TownConfig), replacing the
-- old copy. Run it after changing the town's code or config so edit mode matches play, then
-- save the place. (The game rebuilds the town at start either way; this is only so you can
-- see it while editing.) Townsfolk aren't included: they only exist in play.
-- Studio caches required modules between runs, so this builds from fresh copies of
-- TownBuilder and ReplicatedStorage.Shared (swapped in for the build, then put back).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.Shared
local fresh = shared:Clone()
shared.Parent = nil
fresh.Parent = ReplicatedStorage
local ok, err = pcall(function()
	require(game:GetService("ServerScriptService").Server.TownBuilder:Clone()).build()
end)
fresh:Destroy()
shared.Parent = ReplicatedStorage
if ok then
	print("Beginning Town rebuilt in edit mode; save the place to keep it")
else
	warn("Town preview failed:", err)
end
