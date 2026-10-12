--!strict
-- Applies shared/Config/LightingConfig: the Lighting properties, and exactly one of each
-- effect (Atmosphere, Bloom, ColorCorrection, SunRays) plus terrain clouds. Effects already
-- in the place are replaced, so duplicates can't stack (two ColorCorrections multiply), and
-- depth of field and blur are removed (they smear the far world). Stray effects parented to
-- Workspace, where they do nothing, are removed too.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Shared.Config.LightingConfig)

local LightingSetup = {}

local function set(instance: Instance, properties: { [string]: any })
	for key, value in properties do
		(instance :: any)[key] = value
	end
end

local function fresh(className: string, properties: { [string]: any }): Instance
	local instance = Instance.new(className)
	set(instance, properties)
	instance.Parent = Lighting
	return instance
end

function LightingSetup.apply()
	set(Lighting, LightingConfig.Lighting :: any)

	for _, child in Lighting:GetChildren() do
		local isEffect = child:IsA("PostEffect") or child:IsA("Atmosphere")
		local extraSky = child:IsA("Sky") and child.Name ~= LightingConfig.Sky
		if isEffect or extraSky then
			child:Destroy()
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("PostEffect") then
			child:Destroy()
		end
	end

	fresh("Atmosphere", LightingConfig.Atmosphere :: any)
	fresh("BloomEffect", LightingConfig.Bloom :: any)
	fresh("ColorCorrectionEffect", LightingConfig.ColorCorrection :: any)
	fresh("SunRaysEffect", LightingConfig.SunRays :: any)

	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	set(clouds, LightingConfig.Clouds :: any)
	clouds.Parent = workspace.Terrain
end

return LightingSetup
