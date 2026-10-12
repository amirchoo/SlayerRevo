-- Studio Command Bar snippet: applies the game's lighting (src/shared/Config/LightingConfig.luau,
-- via src/server/LightingSetup.luau) in edit mode, so Studio looks like play. The game applies
-- it at start either way; save the place to keep it in edit mode.
-- Uses fresh module copies (Studio caches required modules between runs).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.Shared
local fresh = shared:Clone()
shared.Parent = nil
fresh.Parent = ReplicatedStorage
local ok, err = pcall(function()
	require(game:GetService("ServerScriptService").Server.LightingSetup:Clone()).apply()
end)
fresh:Destroy()
shared.Parent = ReplicatedStorage
print(if ok then "Lighting applied" else "Lighting failed: " .. tostring(err))
