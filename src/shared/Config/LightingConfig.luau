--!strict
-- The game's look: lighting, atmosphere and post effects, applied by server LightingSetup at
-- start (and in edit mode by tools/apply_lighting.lua). Warm afternoon sun, soft shadows,
-- gentle color, and a cool haze that fades the far hills and mountains: bright and friendly
-- in town, with depth across the big world. Lighting.Technology isn't scriptable; set it in
-- Studio (Future looks best).

local LightingConfig = {}

LightingConfig.Lighting = {
	ClockTime = 14.5,
	GeographicLatitude = 35,
	Brightness = 2.6,
	ExposureCompensation = 0,
	Ambient = Color3.fromRGB(90, 85, 100),
	OutdoorAmbient = Color3.fromRGB(150, 140, 130),
	ColorShift_Top = Color3.fromRGB(255, 235, 205), -- warm sunlight
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.5,
	GlobalShadows = true,
	ShadowSoftness = 0.35,
}

LightingConfig.Atmosphere = {
	Density = 0.24,
	Offset = 0.25,
	Color = Color3.fromRGB(215, 215, 210),
	Decay = Color3.fromRGB(150, 165, 190),
	Glare = 0.2,
	Haze = 0.3,
}

LightingConfig.Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 }
LightingConfig.ColorCorrection = {
	Saturation = 0.25,
	Contrast = 0.1,
	Brightness = 0.02,
	TintColor = Color3.fromRGB(255, 248, 235),
}
LightingConfig.SunRays = { Intensity = 0.04, Spread = 0.5 }

-- Soft clouds drifting over the land (Terrain.Clouds).
LightingConfig.Clouds = { Cover = 0.62, Density = 0.45, Color = Color3.fromRGB(255, 255, 255) }

-- The sky kept (by name, in Lighting); any other Sky is removed.
LightingConfig.Sky = "Sky"

return LightingConfig
