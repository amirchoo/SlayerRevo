-- Studio Command Bar snippet: sculpts the land around the hub (src/server/WorldTerrain.luau,
-- from src/shared/Config/WorldConfig.luau) into the place's terrain, then rebuilds the town
-- and the world's trees/ruins in edit mode so you can see it. Takes a minute or two.
-- Save the place afterwards: terrain lives in the place file, not in the code.
-- Builds from fresh copies of the modules (Studio caches required modules between runs).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local shared = ReplicatedStorage.Shared
local fresh = shared:Clone()
shared.Parent = nil
fresh.Parent = ReplicatedStorage
local ok, err = pcall(function()
	local WorldTerrain = require(Server.WorldTerrain:Clone())
	WorldTerrain.generate()
	print("[generate_terrain] Rocks:", WorldTerrain.addRocks())
	require(Server.TownBuilder:Clone()).build()
	require(Server.WorldBuilder:Clone()).build()
end)
fresh:Destroy()
shared.Parent = ReplicatedStorage
if ok then
	print("[generate_terrain] Done: save the place to keep the terrain")
else
	warn("[generate_terrain] Failed:", err)
end
